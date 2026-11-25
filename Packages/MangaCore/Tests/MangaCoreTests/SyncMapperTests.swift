import XCTest
@testable import MangaCore

final class SyncMapperTests: XCTestCase {
    func testStateRoundTripsThroughRecords() {
        var source = SyncFixtures.populated()
        let p = source.activeProfile!.id
        let server = source.servers[0].id
        let kid = source.addProfile(name: "Kid").id
        source.setSelectedCategories(["3", "1"], profile: kid, server: server)
        var override = ReaderSettings.default
        override.mode = .webtoon
        source.setReaderSettings(override, for: SeriesRef(serverID: server, seriesID: "1"), profile: p)

        let records = SyncMapper.payloads(from: source).map { key, item in
            SyncRecord(key: key, kind: item.kind, payload: item.payload, modifiedAt: Date(), deviceID: "t")
        }
        var target = AppState()
        SyncMapper.apply(SyncPatch(records: records.shuffled()), to: &target)

        XCTAssertEqual(Set(target.profiles), Set(source.profiles))
        XCTAssertEqual(target.servers, source.servers)
        XCTAssertEqual(target.selectedCategories(profile: kid, server: server), ["1", "3"])
        XCTAssertEqual(target.favorites(profile: p), source.favorites(profile: p))
        XCTAssertEqual(target.progress(SeriesRef(serverID: server, seriesID: "1"), profile: p),
                       source.progress(SeriesRef(serverID: server, seriesID: "1"), profile: p))
        XCTAssertEqual(target.readerSettings(for: SeriesRef(serverID: server, seriesID: "1"), profile: p).mode, .webtoon)

        let a = SyncMapper.payloads(from: source), b = SyncMapper.payloads(from: target)
        XCTAssertEqual(Set(a.keys), Set(b.keys))
        for (key, item) in a {
            XCTAssertTrue(SyncMapper.samePayload(item.kind, item.payload, b[key]?.payload), key)
        }
    }

    func testSecretsNeverLeaveTheDevice() {
        let payloads = SyncMapper.payloads(from: SyncFixtures.populated())
        let all = payloads.values.map { String(decoding: $0.payload, as: UTF8.self) }.joined()
        XCTAssertFalse(all.contains("apiKey"))
        XCTAssertFalse(all.contains("password"))
    }

    func testSelectionEncodesTheSameWhateverTheOrder() {
        let a = SyncMapper.encode(SyncMapper.SyncedServerSettings(ProfileServerSettings(selectedCategoryIDs: ["b", "a", "c"])))
        let b = SyncMapper.encode(SyncMapper.SyncedServerSettings(ProfileServerSettings(selectedCategoryIDs: ["c", "a", "b"])))
        XCTAssertEqual(a, b)
    }

    func testKeysAreKindSlashId() {
        let s = SyncFixtures.populated()
        let p = s.activeProfile!.id.uuidString
        let server = s.servers[0].id.uuidString
        let keys = Set(SyncMapper.payloads(from: s).keys)
        XCTAssertTrue(keys.contains("server/\(server)"))
        XCTAssertTrue(keys.contains("profile/\(p)"))
        XCTAssertTrue(keys.contains("favorite/\(p)/\(server)|1"))
        XCTAssertTrue(keys.contains("progress/\(p)/\(server)|1"))
        XCTAssertTrue(keys.contains("readerDefaults/\(p)"))
        XCTAssertTrue(keys.contains("serverSettings/\(p)/\(server)"))
    }

    func testApplyingProgressKeepsLocalOnlyFields() {
        var s = SyncFixtures.populated()
        let p = s.activeProfile!.id
        let key = SeriesRef(serverID: s.servers[0].id, seriesID: "1").storageKey
        let incoming = SyncedProgress(chapterID: "c9", page: 2, positionAt: Date(timeIntervalSince1970: 1_800_000_000),
                                      marks: ["c1": ReadMark(read: true, at: .distantPast),
                                              "c8": ReadMark(read: true, at: .distantPast),
                                              "c2": ReadMark(read: false, at: .distantPast)])
        let record = SyncRecord(key: "progress/\(p.uuidString)/\(key)", kind: .progress,
                                payload: SyncMapper.encode(incoming), modifiedAt: Date(), deviceID: "x")
        SyncMapper.apply(SyncPatch(records: [record]), to: &s)
        let progress = s.profileData[p.uuidString]?.progress[key]
        XCTAssertEqual(progress?.chapterID, "c9")
        XCTAssertEqual(progress?.readChapterIDs, ["c1", "c8"])
    }

    func testUnreadableRecordsAreIgnored() {
        var s = SyncFixtures.populated()
        let before = s
        let junk = SyncRecord(key: "profile/\(UUID().uuidString)", kind: .profile, payload: Data("{\"nope\":1}".utf8),
                              modifiedAt: Date(), deviceID: "x")
        let unknown = SyncRecord(key: "bookmark/1", kind: SyncKind("bookmark"), payload: Data("{}".utf8),
                                 modifiedAt: Date(), deviceID: "x")
        SyncMapper.apply(SyncPatch(records: [junk, unknown]), to: &s)
        XCTAssertEqual(s, before)
        XCTAssertFalse(SyncMapper.canRead(junk))
        XCTAssertFalse(SyncMapper.canRead(unknown))
    }

    func testRemapMatchesAddressAndName() {
        var local = AppState.initial()
        let mine = ServerConfig(kind: .suwayomi, name: "S", baseURL: URL(string: "http://Suwayomi.example:4567/")!)
        let other = ServerConfig(kind: .kavita, name: "K", baseURL: URL(string: "http://suwayomi.example:4567")!)
        local.addServer(mine)
        local.addServer(other)
        let remoteServer = ServerConfig(kind: .suwayomi, name: "Home", baseURL: SyncFixtures.suwayomiURL)
        let remoteProfile = Profile(name: " me ")
        let incoming = [
            SyncRecord(key: "server/\(remoteServer.id.uuidString)", kind: .server, payload: SyncMapper.encode(remoteServer),
                       modifiedAt: Date(), deviceID: "x"),
            SyncRecord(key: "profile/\(remoteProfile.id.uuidString)", kind: .profile, payload: SyncMapper.encode(remoteProfile),
                       modifiedAt: Date(), deviceID: "x"),
        ]
        let remap = SyncRemap.matching(incoming: incoming, local: local)
        XCTAssertEqual(remap.servers, [mine.id: remoteServer.id], "kind must match too")
        XCTAssertEqual(remap.profiles, [local.profiles[0].id: remoteProfile.id])

        let p = local.profiles[0].id
        local.setFavorite(SyncFixtures.series(mine.id, "5"), true, profile: p)
        remap.apply(to: &local)
        XCTAssertEqual(local.activeProfileID, remoteProfile.id)
        XCTAssertEqual(local.favorites(profile: remoteProfile.id).first?.series.ref.serverID, remoteServer.id)
        XCTAssertNotNil(local.profileData[remoteProfile.id.uuidString]?.serverSettings[remoteServer.id.uuidString])
    }
}
