import Foundation
#if canImport(Compression)
import Compression
#endif

/// A minimal ZIP reader for comic archives (CBZ): reads the central
/// directory and extracts stored or deflated entries. No ZIP64, encryption
/// or multi-disk archives, which comic archives don't use.
public struct ZipArchive: Sendable {
    public struct Entry: Hashable, Sendable {
        public var path: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    public let data: Data
    public let entries: [Entry]

    public enum ZipError: Error, LocalizedError, Equatable {
        case notAZip
        case unsupported(String)
        case corrupt(String)

        public var errorDescription: String? {
            switch self {
            case .notAZip: return "The file isn't a ZIP or CBZ archive."
            case .unsupported(let s): return "This archive uses \(s), which isn't supported."
            case .corrupt(let s): return "The archive is damaged (\(s))."
            }
        }
    }

    public init(data: Data) throws {
        self.data = data
        entries = try Self.readDirectory(data)
    }

    /// Image files in reading order: natural sort by path, skipping macOS
    /// resource forks and hidden files.
    public var imageEntries: [Entry] {
        let images = entries.filter { entry in
            guard !entry.isDirectory else { return false }
            let parts = entry.path.split(separator: "/")
            guard !parts.contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) else { return false }
            let ext = (entry.path as NSString).pathExtension.lowercased()
            return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "jxl"].contains(ext)
        }
        return images.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func extract(_ entry: Entry) throws -> Data {
        let o = entry.localHeaderOffset
        guard o + 30 <= data.count, Self.u32(data, o) == 0x04034b50 else { throw ZipError.corrupt("local header") }
        let nameLength = Int(Self.u16(data, o + 26))
        let extraLength = Int(Self.u16(data, o + 28))
        let start = o + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt("entry data") }
        let compressed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, size: entry.uncompressedSize)
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    static func inflate(_ data: Data, size: Int) throws -> Data {
        #if canImport(Compression)
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE, which is what ZIP stores.
                return compression_decode_buffer(d, size, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt("inflate") }
        return output
        #else
        throw ZipError.unsupported("deflate on this platform")
        #endif
    }

    // MARK: Directory

    static func readDirectory(_ data: Data) throws -> [Entry] {
        // End of central directory: the last 0x06054b50 in the final 64 KB.
        guard data.count >= 22 else { throw ZipError.notAZip }
        var eocd = -1
        var i = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while i >= floor {
            if u32(data, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let count = Int(u16(data, eocd + 10))
        let directoryOffset = Int(u32(data, eocd + 16))
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw ZipError.unsupported("ZIP64") }
        var entries: [Entry] = []
        var p = directoryOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(data, p) == 0x02014b50 else { throw ZipError.corrupt("central directory") }
            let flags = u16(data, p + 8)
            if flags & 0x1 != 0 { throw ZipError.unsupported("encryption") }
            let method = u16(data, p + 10)
            let compressed = Int(u32(data, p + 20))
            let uncompressed = Int(u32(data, p + 24))
            let nameLength = Int(u16(data, p + 28))
            let extraLength = Int(u16(data, p + 30))
            let commentLength = Int(u16(data, p + 32))
            let offset = Int(u32(data, p + 42))
            guard p + 46 + nameLength <= data.count else { throw ZipError.corrupt("file name") }
            let nameData = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLength))
            // Bit 11 means UTF-8; older tools wrote CP437, which is ASCII for
            // the usual page names.
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(path: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed,
                                 localHeaderOffset: offset))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func u16(_ d: Data, _ o: Int) -> UInt16 {
        let b = d.startIndex + o
        return UInt16(d[b]) | UInt16(d[b + 1]) << 8
    }

    static func u32(_ d: Data, _ o: Int) -> UInt32 {
        let b = d.startIndex + o
        return UInt32(d[b]) | UInt32(d[b + 1]) << 8 | UInt32(d[b + 2]) << 16 | UInt32(d[b + 3]) << 24
    }
}
