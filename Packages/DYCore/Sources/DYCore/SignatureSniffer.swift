import Foundation

/// Recognises a file's category from its first bytes, for files whose name says nothing.
///
/// Pure and allocation-light: it looks at a header already read and never touches a file.
public enum SignatureSniffer {
    /// How many leading bytes `kind(header:)` can use. Covers tar, GPT and filesystem signatures.
    public static let headerLength = 2048

    /// The category implied by the header, or nil when no signature matches.
    public static func kind(header: Data) -> FileKind? {
        guard !header.isEmpty else { return nil }
        let bytes = [UInt8](header.prefix(headerLength))
        return containerKind(bytes) ?? imageOrAudioKind(bytes) ?? archiveKind(bytes) ?? dataKind(bytes) ?? textKind(bytes)
    }

    /// Whether `bytes` holds `text` (ASCII) at `offset`.
    private static func has(_ bytes: [UInt8], _ text: String, at offset: Int = 0) -> Bool {
        let wanted = Array(text.utf8)
        guard bytes.count >= offset + wanted.count else { return false }
        return bytes[offset..<(offset + wanted.count)].elementsEqual(wanted)
    }

    /// Whether `bytes` holds the raw `values` at `offset`.
    private static func has(_ bytes: [UInt8], _ values: [UInt8], at offset: Int = 0) -> Bool {
        guard bytes.count >= offset + values.count else { return false }
        return bytes[offset..<(offset + values.count)].elementsEqual(values)
    }

    /// Video and RIFF/ISO-media containers, which need a second look at a brand or form type.
    private static func containerKind(_ bytes: [UInt8]) -> FileKind? {
        if has(bytes, "ftyp", at: 4) { return mediaBrandKind(bytes) }
        for atom in ["moov", "mdat", "wide", "free", "skip"] where has(bytes, atom, at: 4) { return .video }
        if has(bytes, [0x1A, 0x45, 0xDF, 0xA3]) || has(bytes, "FLV\u{1}") { return .video }
        if has(bytes, [0x00, 0x00, 0x01, 0xBA]) || has(bytes, [0x00, 0x00, 0x01, 0xB3]) { return .video }
        if has(bytes, "RIFF") {
            if has(bytes, "AVI ", at: 8) { return .video }
            if has(bytes, "WAVE", at: 8) { return .audio }
            if has(bytes, "WEBP", at: 8) { return .image }
        }
        if has(bytes, "FORM"), has(bytes, "AIFF", at: 8) || has(bytes, "AIFC", at: 8) { return .audio }
        if bytes.count > 376, bytes[0] == 0x47, bytes[188] == 0x47, bytes[376] == 0x47 { return .video }
        return nil
    }

    /// The category for an ISO base media file, from its major brand.
    private static func mediaBrandKind(_ bytes: [UInt8]) -> FileKind {
        let brand = String(decoding: bytes[8..<min(12, bytes.count)], as: UTF8.self)
        if ["heic", "heix", "hevc", "hevx", "mif1", "msf1", "avif", "avis"].contains(brand) { return .image }
        if ["M4A ", "M4B ", "M4P ", "F4A "].contains(brand) { return .audio }
        return .video
    }

    /// Still image and audio stream signatures.
    private static func imageOrAudioKind(_ bytes: [UInt8]) -> FileKind? {
        let images: [[UInt8]] = [[0xFF, 0xD8, 0xFF], [0x89, 0x50, 0x4E, 0x47], Array("GIF87a".utf8), Array("GIF89a".utf8),
                                 [0x49, 0x49, 0x2A, 0x00], [0x4D, 0x4D, 0x00, 0x2A], Array("8BPS".utf8), Array("icns".utf8),
                                 [0x76, 0x2F, 0x31, 0x01], [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20],
                                 [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20], [0xFF, 0x0A]]
        if images.contains(where: { has(bytes, $0) }) { return .image }
        if has(bytes, "BM"), bytes.count > 18, bytes[6..<10].allSatisfy({ $0 == 0 }), [12, 40, 52, 56, 64, 108, 124].contains(bytes[14]) {
            return .image
        }
        let audio = ["ID3", "fLaC", "OggS", "MThd", "caff", "MAC ", "wvpk"]
        return audio.contains(where: { has(bytes, $0) }) ? .audio : nil
    }

    /// Archive, disk image and package signatures.
    private static func archiveKind(_ bytes: [UInt8]) -> FileKind? {
        let leading: [[UInt8]] = [[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0x1F, 0x8B], Array("BZh".utf8),
                                  [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00], [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],
                                  [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07], [0x28, 0xB5, 0x2F, 0xFD], [0x04, 0x22, 0x4D, 0x18],
                                  Array("xar!".utf8), Array("conectix".utf8), Array("KDMV".utf8), [0x51, 0x46, 0x49, 0xFB],
                                  Array("vhdxfile".utf8), Array("<<< Oracle VM VirtualBox Disk Image >>>".utf8)]
        if leading.contains(where: { has(bytes, $0) }) { return .archive }
        if has(bytes, "ustar", at: 257) || has(bytes, "NXSB", at: 32) || has(bytes, "EFI PART", at: 512) { return .archive }
        if has(bytes, "H+", at: 1024) || has(bytes, "HX", at: 1024) { return .archive }
        return nil
    }

    /// Executables, databases and data formats that count as code and data or as applications.
    private static func dataKind(_ bytes: [UInt8]) -> FileKind? {
        if has(bytes, [0xCA, 0xFE, 0xBA, 0xBE]) { return isFatMachO(bytes) ? .application : .code }
        let machO: [[UInt8]] = [[0xFE, 0xED, 0xFA, 0xCE], [0xFE, 0xED, 0xFA, 0xCF], [0xCE, 0xFA, 0xED, 0xFE],
                                [0xCF, 0xFA, 0xED, 0xFE], [0xBE, 0xBA, 0xFE, 0xCA]]
        if machO.contains(where: { has(bytes, $0) }) || has(bytes, [0x7F, 0x45, 0x4C, 0x46]) { return .application }
        if has(bytes, "MZ"), bytes.count > 64, has(bytes, "PE\0\0", at: Int(bytes[60])) { return .application }
        if has(bytes, "%PDF-") || has(bytes, "%!PS") { return .document }
        let data: [[UInt8]] = [Array("SQLite format 3\0".utf8), Array("GGUF".utf8), [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A],
                               Array("PAR1".utf8), Array("ARROW1".utf8), Array("bplist00".utf8), Array("wOFF".utf8)]
        if data.contains(where: { has(bytes, $0) }) { return .code }
        return isSafetensors(bytes) ? .code : nil
    }

    /// A fat Mach-O has a small architecture count where a Java class file has a version of 45 or more.
    private static func isFatMachO(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 8 else { return false }
        let count = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        return count > 0 && count < 45
    }

    /// A safetensors file starts with a little-endian header length, then a JSON object.
    private static func isSafetensors(_ bytes: [UInt8]) -> Bool {
        guard bytes.count > 10, bytes[8] == UInt8(ascii: "{"), bytes[9] == UInt8(ascii: "\"") else { return false }
        let length = bytes[0..<8].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        return length > 1 && length < 100_000_000
    }

    /// Scripts, markup and plain text. Binary data (a NUL or invalid UTF-8) is not text.
    private static func textKind(_ bytes: [UInt8]) -> FileKind? {
        guard bytes.count >= 8, !bytes.contains(0) else { return nil }
        if has(bytes, "#!") || has(bytes, "<?xml") || has(bytes, "<!DOCTYPE") || has(bytes, "<html") { return .code }
        if bytes[0] == UInt8(ascii: "{") || bytes[0] == UInt8(ascii: "[") { return .code }
        // A multi-byte character may be cut at the end of the header, so tolerate a few trailing bytes.
        let usable = bytes.count == headerLength ? Array(bytes.dropLast(3)) : bytes
        guard String(validatingUTF8: usable.map { CChar(bitPattern: $0) } + [0]) != nil else { return nil }
        let controls = usable.filter { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }.count
        return controls == 0 ? .document : nil
    }
}
