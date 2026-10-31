import Foundation

/// Maps file extensions to categories without allocating, so the scanner can classify millions of names quickly.
public enum FileKindClassifier {
    private static let table: [UInt64: FileKind] = {
        let groups: [(FileKind, String)] = [
            (.video, "mp4 m4v mov avi mkv webm mpg mpeg wmv flv 3gp 3g2 mts m2ts m2v vob ogv prores braw r3d mxf asf rm rmvb divx f4v dv"),
            (.image, "jpg jpeg png gif heic heif tif tiff bmp webp avif raw cr2 cr3 nef arw dng orf rw2 raf svg psd psb ai eps ico icns exr jp2 jxl tga dds hdr xcf sketch fig indd pbm pgm ppm pict heics"),
            (.audio, "mp3 m4a m4b m4r aac flac wav aif aiff ogg oga opus wma alac caf mid midi mka ape wv dsf aax amr ac3 dts sf2"),
            (.document, "pdf doc docx docm dot dotx xls xlsx xlsm ppt pptx pptm pages numbers key txt md rtf rtfd csv tsv epub mobi azw3 djvu cbz cbr tex odt ods odp odg eml emlx mbox log ics vcf rst adoc org bib ps pub vsd wpd wps"),
            (.code, "swift m mm h hpp c cc cpp rs go py rb js jsx ts tsx mjs cjs java kt cs php sh zsh bash lua sql json jsonl ndjson yaml yml toml xml html css scss lock map o a pyc class wasm db sqlite sqlite3 db3 sqlitedb realm parquet feather arrow avro orc npy npz ipynb gguf ggml safetensors weights ckpt pt pth onnx tflite mlmodel litertlm h5 hdf5 pkl pickle dat pack idx ldb sst wal shm ibd bson dump har patch diff proto graphql tf tfstate plist ini cfg conf env rlib rmeta d vue svelte dart scala clj ex exs erl hs ml jl pl pm tcl vb ps1 bat cmd gradle cmake mk"),
            (.application, "app dylib so framework bundle plugin kext xpc appex exe dll bin jar car nib strings pyd node ko dex vsix prefpane saver qlgenerator mdimporter component vst vst3 clap"),
            (.archive, "zip zipx tar gz tgz bz2 tbz2 xz txz 7z rar zst lz4 lzma z br cab cpio arj lz dmg iso img pkg sparseimage sparsebundle vmdk vdi qcow2 vhd vhdx vmem vmss nvram hdd ova ovf wim toast cdr raw_disk ipa apk xip deb rpm msi whl egg nupkg crx xpi appimage"),
        ]
        var table: [UInt64: FileKind] = [:]
        for (kind, extensions) in groups {
            for ext in extensions.split(separator: " ") {
                table[packed(Array(ext.utf8)[...])] = kind
            }
        }
        // `ts` is far more often TypeScript than MPEG transport stream on developer machines.
        table[packed(Array("ts".utf8)[...])] = .code
        return table
    }()

    /// Classifies a file by the extension of its UTF-8 name. Extensions longer than 8 bytes are `other` unless listed in the long table.
    public static func classify(name: UnsafeBufferPointer<UInt8>) -> FileKind {
        guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > 0, name.count - dot > 1 else { return .other }
        if name.count - dot - 1 > 8 { return longExtensionKind(name) }
        var key: UInt64 = 0
        for byte in name[(dot + 1)...] {
            let lower = (byte >= 65 && byte <= 90) ? byte + 32 : byte
            key = key << 8 | UInt64(lower)
        }
        if key == dockerRaw, name.count == 10, hasExtension(name, "raw"), isDockerName(name) { return .archive }
        return table[key] ?? .other
    }

    /// Extensions longer than eight bytes, which don't fit the packed table.
    private static let longExtensions: [(ext: String, kind: FileKind)] = [
        ("safetensors", .code), ("sparsebundle", .archive), ("sparseimage", .archive),
    ]

    /// The kind for a name whose extension is longer than eight bytes, or `other`.
    private static func longExtensionKind(_ name: UnsafeBufferPointer<UInt8>) -> FileKind {
        for (ext, kind) in longExtensions where hasLongExtension(name, ext) { return kind }
        return .other
    }

    /// Whether the name ends in `.ext`, ignoring case.
    private static func hasLongExtension(_ name: UnsafeBufferPointer<UInt8>, _ ext: String) -> Bool {
        let wanted = Array(ext.utf8)
        guard name.count > wanted.count + 1, name[name.count - wanted.count - 1] == UInt8(ascii: ".") else { return false }
        for (index, byte) in wanted.enumerated() {
            let actual = name[name.count - wanted.count + index]
            if ((actual >= 65 && actual <= 90) ? actual + 32 : actual) != byte { return false }
        }
        return true
    }

    /// The packed key of `raw`, used to spot Docker's disk image.
    private static let dockerRaw = packed(Array("raw".utf8)[...])

    /// Whether the name is `Docker.raw`, ignoring case.
    private static func isDockerName(_ name: UnsafeBufferPointer<UInt8>) -> Bool {
        String(decoding: name, as: UTF8.self).lowercased() == "docker.raw"
    }

    /// Files with this extension at or above this size are disk images, not camera files.
    public static let largeRawThreshold: UInt64 = 1_000_000_000

    /// Classifies a file by name and size. A `.raw` of `largeRawThreshold` bytes or more, and `Docker.raw`, is an archive.
    public static func classify(name: UnsafeBufferPointer<UInt8>, size: UInt64) -> FileKind {
        let kind = classify(name: name)
        guard kind == .image, size >= largeRawThreshold, hasExtension(name, "raw") else { return kind }
        return .archive
    }

    /// Classifies a file by name and size. Convenience form of `classify(name:size:)` for tests and UI.
    public static func classify(_ name: String, size: UInt64) -> FileKind {
        var name = name
        return name.withUTF8 { classify(name: $0, size: size) }
    }

    /// Whether the name ends in `.ext`, ignoring case.
    private static func hasExtension(_ name: UnsafeBufferPointer<UInt8>, _ ext: StaticString) -> Bool {
        let suffix = ext.utf8Start
        let length = ext.utf8CodeUnitCount
        guard name.count > length + 1, name[name.count - length - 1] == UInt8(ascii: ".") else { return false }
        for index in 0..<length {
            let byte = name[name.count - length + index]
            let lower = (byte >= 65 && byte <= 90) ? byte + 32 : byte
            if lower != suffix[index] { return false }
        }
        return true
    }

    /// The lowercase extension of a name as text, or nil when it has none or is longer than 8 bytes.
    public static func fileExtension(name: UnsafeBufferPointer<UInt8>) -> String? {
        guard let dot = name.lastIndex(of: UInt8(ascii: ".")), dot > 0, name.count - dot > 1, name.count - dot - 1 <= 8 else { return nil }
        return String(decoding: name[(dot + 1)...], as: UTF8.self).lowercased()
    }

    /// Classifies a file by name. Convenience form of `classify(name:)` for tests and UI.
    public static func classify(_ name: String) -> FileKind {
        var name = name
        return name.withUTF8 { classify(name: $0) }
    }

    private static func packed(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }
}
