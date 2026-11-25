import Foundation

/// Merge rules, shared by iCloud sync and backup restore.
///
/// - Most records: last writer wins by `modifiedAt` (ties: larger device id).
/// - Progress: the position is last writer wins by `positionAt`, and every
///   chapter's read mark merges on its own, so reading chapter 3 on one
///   device and chapter 5 on another keeps both.
/// - A deletion is a record like any other: it wins if it's newer.
public enum SyncMerge {
    public static func newer(_ a: SyncRecord, _ b: SyncRecord) -> SyncRecord {
        if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt ? a : b }
        return a.deviceID >= b.deviceID ? a : b
    }

    /// The merged value of two versions of one record.
    public static func merge(_ local: SyncRecord, _ remote: SyncRecord) -> SyncRecord {
        guard local.kind == .progress,
              let lp = local.payload.flatMap({ SyncMapper.decode(SyncedProgress.self, $0) }),
              let rp = remote.payload.flatMap({ SyncMapper.decode(SyncedProgress.self, $0) }) else {
            return newer(local, remote)
        }
        let winner = newer(local, remote)
        var merged = mergeProgress(lp, rp)
        if merged == rp { merged = rp } // keep the remote bytes when nothing changed
        return SyncRecord(key: local.key, kind: .progress, payload: SyncMapper.encode(merged),
                          modifiedAt: max(local.modifiedAt, remote.modifiedAt), deviceID: winner.deviceID)
    }

    public static func mergeProgress(_ a: SyncedProgress, _ b: SyncedProgress) -> SyncedProgress {
        var out = a.positionAt >= b.positionAt ? a : b
        var marks = a.marks
        for (chapter, mark) in b.marks {
            if let existing = marks[chapter], existing.at >= mark.at { continue }
            marks[chapter] = mark
        }
        out.marks = marks
        return out
    }

    /// Gives a progress value from local state (where every read chapter is
    /// stamped with the position time) real per-chapter times, using the
    /// last value this device synced: unchanged chapters keep their old
    /// mark, newly read ones are stamped `now`, and chapters that were read
    /// but no longer are become unread marks at `now`.
    public static func stampProgress(_ local: SyncedProgress, previous: SyncedProgress?, now: Date) -> SyncedProgress {
        guard let previous else { return local }
        var out = local
        var marks: [String: ReadMark] = [:]
        let read = local.readChapterIDs
        for chapter in read {
            if let old = previous.marks[chapter], old.read { marks[chapter] = old } else { marks[chapter] = ReadMark(read: true, at: now) }
        }
        for (chapter, old) in previous.marks where !read.contains(chapter) {
            marks[chapter] = old.read ? ReadMark(read: false, at: now) : old
        }
        out.marks = marks
        if previous.chapterID == local.chapterID && previous.page == local.page {
            out.positionAt = max(previous.positionAt, local.positionAt)
        }
        return out
    }

    /// Records for the current local state, compared with `reference` (what
    /// this device last synced, or queued but couldn't send).
    ///
    /// - Unchanged values return the reference record as is.
    /// - Changed values are stamped `now`. Values the device never synced
    ///   are stamped `now` too, unless `joining` (first sync or a restore):
    ///   then they get their own timestamp or the distant past, so what's
    ///   already in the cloud wins over a fresh install's defaults.
    /// - Values in `reference` that are gone locally become deletions.
    public static func localRecords(state: AppState, reference: [String: SyncRecord], deviceID: String,
                                    now: Date, joining: Bool) -> [String: SyncRecord] {
        var out: [String: SyncRecord] = [:]
        let payloads = SyncMapper.payloads(from: state)
        for (key, item) in payloads {
            let ref = reference[key]
            var payload = item.payload
            if item.kind == .progress, let local = SyncMapper.decode(SyncedProgress.self, payload) {
                let previous = ref?.payload.flatMap { SyncMapper.decode(SyncedProgress.self, $0) }
                payload = SyncMapper.encode(stampProgress(local, previous: previous, now: now))
            }
            if let ref, SyncMapper.samePayload(item.kind, ref.payload, payload) {
                out[key] = ref
                continue
            }
            let stamp: Date
            if ref == nil && joining {
                stamp = SyncMapper.naturalDate(item.kind, payload) ?? .distantPast
            } else {
                stamp = now
            }
            out[key] = SyncRecord(key: key, kind: item.kind, payload: payload, modifiedAt: stamp, deviceID: deviceID)
        }
        for (key, ref) in reference where out[key] == nil {
            // Only delete what this build knows how to read; anything else
            // (a newer app's records) is left alone.
            guard SyncMapper.canRead(ref) else { continue }
            out[key] = ref.isDeleted ? ref
                : SyncRecord(key: key, kind: ref.kind, payload: nil, modifiedAt: now, deviceID: deviceID)
        }
        return out
    }

    /// Same value and timestamp.
    public static func sameContent(_ a: SyncRecord, _ b: SyncRecord) -> Bool {
        a.modifiedAt == b.modifiedAt && SyncMapper.samePayload(a.kind, a.payload, b.payload)
    }
}
