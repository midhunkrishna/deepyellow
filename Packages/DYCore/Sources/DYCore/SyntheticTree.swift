import Foundation

/// Generates realistic, deterministic disk trees for tests, demos and screenshots, so nothing depends on or exposes real files.
public enum SyntheticTree {
    /// Builds a tree of roughly `50_000 * scale` nodes shaped like a developer's Mac: a few giants, many swarms, a long tail.
    public static func make(seed: UInt64 = 42, scale: Double = 1, rootPath: String = "/") -> FileTree {
        var generator = Generator(seed: seed, scale: scale, rootPath: rootPath)
        generator.populate()
        return generator.builder.freeze(meta: ScanMeta(rootPath: rootPath, scannedAt: Date(timeIntervalSince1970: TimeInterval(referenceNow))))
    }

    /// The fixed "now" used for synthetic timestamps, so age-based output is reproducible.
    public static let referenceNow: Int32 = 1_790_000_000

    private struct Generator {
        let builder: TreeBuilder
        var random: SplitMix
        let scale: Double
        let megabyte: UInt64 = 1_000_000

        init(seed: UInt64, scale: Double, rootPath: String) {
            builder = TreeBuilder(rootPath: rootPath)
            random = SplitMix(state: seed)
            self.scale = scale
        }

        mutating func populate() {
            let users = directory(0, "Users")
            let home = directory(users, "demo")
            populateMedia(home)
            populateDeveloper(home)
            populateLibrary(home)
            populateDownloads(home)
            populateApplications()
            populateSystem()
        }

        mutating func populateMedia(_ home: NodeID) {
            let movies = directory(home, "Movies")
            let footage = directory(movies, "Iceland 2023")
            for index in 1...14 { file(footage, "C\(1000 + index).mov", random.size(800 * megabyte, 9_000 * megabyte), ageDays: 900) }
            file(movies, "wedding-final-master.mov", 38_000 * megabyte, ageDays: 1_100)
            file(movies, "interview-raw.mp4", 410 * megabyte, ageDays: 400)
            let renders = directory(movies, "Exports")
            for index in 1...6 { file(renders, "cut_v\(index).mp4", random.size(300 * megabyte, 1_400 * megabyte), ageDays: 300) }

            let photos = directory(home, "Pictures")
            let library = directory(photos, "Photos Library.photoslibrary", package: true)
            let originals = directory(library, "originals")
            scatter(originals, count: scaled(4_000), prefix: "IMG_", ext: "heic", low: 1 * megabyte, high: 8 * megabyte, ageDays: 1_400)
            let shoots = directory(photos, "Shoots")
            for shoot in ["Patagonia", "Tokyo Nights", "Studio Session"] {
                scatter(directory(shoots, shoot), count: scaled(350), prefix: "DSC", ext: "arw", low: 20 * megabyte, high: 55 * megabyte, ageDays: 1_000)
            }

            let music = directory(home, "Music")
            scatter(directory(music, "Lossless"), count: scaled(1_400), prefix: "track_", ext: "flac", low: 15 * megabyte, high: 60 * megabyte, ageDays: 1_800)

            let documents = directory(home, "Documents")
            scatter(directory(documents, "Taxes"), count: scaled(120), prefix: "statement_", ext: "pdf", low: 100_000, high: 4 * megabyte, ageDays: 700)
            scatter(directory(documents, "Notes"), count: scaled(900), prefix: "note_", ext: "md", low: 1_000, high: 60_000, ageDays: 200)
            file(documents, "thesis-final.pages", 88 * megabyte, ageDays: 1_500)
        }

        mutating func populateDeveloper(_ home: NodeID) {
            let projects = directory(home, "Developer")
            for (name, age) in [("storefront", 40), ("old-mobile-app", 700), ("data-pipeline", 12), ("portfolio-2021", 1_200), ("ml-experiments", 180)] {
                let project = directory(projects, name)
                scatter(directory(project, "src"), count: scaled(180), prefix: "module_", ext: "ts", low: 800, high: 40_000, ageDays: age)
                swarm(directory(project, "node_modules"), packages: scaled(170), filesPerPackage: 14, ageDays: age)
                let git = directory(project, ".git")
                scatter(directory(git, "objects"), count: scaled(420), prefix: "obj", ext: "pack", low: 500, high: 3 * megabyte, ageDays: age)
            }
            let target = directory(directory(projects, "rust-engine"), "target")
            scatter(directory(target, "debug"), count: scaled(1_400), prefix: "dep_", ext: "rlib", low: 200_000, high: 30 * megabyte, ageDays: 90)
            let venv = directory(directory(projects, "ml-experiments-2"), ".venv")
            swarm(venv, packages: scaled(90), filesPerPackage: 30, ageDays: 150)
            file(directory(projects, "datasets"), "imagenet-subset.tar", 24_000 * megabyte, ageDays: 500)
        }

        mutating func populateLibrary(_ home: NodeID) {
            let library = directory(home, "Library")
            let caches = directory(library, "Caches")
            for name in ["com.apple.Safari", "com.spotify.client", "Homebrew", "com.google.Chrome", "pip", "go-build"] {
                scatter(directory(caches, name), count: scaled(600), prefix: "cache_", ext: "bin", low: 2_000, high: 9 * megabyte, ageDays: 20)
            }
            let developer = directory(library, "Developer")
            let xcode = directory(developer, "Xcode")
            let derived = directory(xcode, "DerivedData")
            for name in ["Storefront-abcxyz", "OldMobile-qrstuv"] {
                scatter(directory(derived, name), count: scaled(2_500), prefix: "obj_", ext: "o", low: 4_000, high: 5 * megabyte, ageDays: 60)
            }
            let support = directory(xcode, "iOS DeviceSupport")
            for version in ["16.4", "17.2", "18.0"] {
                scatter(directory(support, "iPhone \(version)"), count: scaled(300), prefix: "sym_", ext: "dylib", low: 1 * megabyte, high: 30 * megabyte, ageDays: 400)
            }
            let simulators = directory(directory(developer, "CoreSimulator"), "Devices")
            for index in 1...5 {
                scatter(directory(simulators, "A1B2C3D\(index)-SIM"), count: scaled(500), prefix: "data_", ext: "db", low: 3_000, high: 12 * megabyte, ageDays: 300)
            }
            let support2 = directory(library, "Application Support")
            let backups = directory(directory(support2, "MobileSync"), "Backup")
            scatter(directory(backups, "00008110-IPHONE"), count: scaled(1_800), prefix: "bk", ext: "", low: 20_000, high: 25 * megabyte, ageDays: 650)
            file(directory(directory(directory(library, "Containers"), "com.docker.docker"), "Data"), "Docker.raw", 64_000 * megabyte, ageDays: 3)
            scatter(directory(library, "Logs"), count: scaled(400), prefix: "log_", ext: "log", low: 500, high: 2 * megabyte, ageDays: 30)
            file(directory(library, "Preferences"), ".DS_Store", 16_384, ageDays: 10)
        }

        mutating func populateDownloads(_ home: NodeID) {
            let downloads = directory(home, "Downloads")
            for (name, size, age) in [("Xcode_15.2.xip", 8_100, 620), ("Ubuntu-24.04.iso", 5_900, 300), ("Figma.dmg", 280, 500), ("Install macOS.pkg", 13_000, 720), ("old-backup.zip", 6_400, 1_000), ("conference-talk.mp4", 2_100, 240)] as [(String, UInt64, Int)] {
                file(downloads, name, size * megabyte, ageDays: age)
            }
            scatter(downloads, count: scaled(260), prefix: "download_", ext: "pdf", low: 50_000, high: 40 * megabyte, ageDays: 400)
            file(home, ".DS_Store", 12_288, ageDays: 2)
        }

        mutating func populateApplications() {
            let applications = directory(0, "Applications")
            for (name, files) in [("Xcode", 3_000), ("Final Cut Pro", 900), ("Docker", 400), ("Figma", 180), ("Spotify", 120), ("Safari Technology Preview", 90)] as [(String, Int)] {
                let bundle = directory(applications, "\(name).app", package: true)
                scatter(directory(bundle, "Contents"), count: scaled(files), prefix: "res_", ext: "dylib", low: 5_000, high: 14 * megabyte, ageDays: 50)
            }
        }

        mutating func populateSystem() {
            let system = directory(0, "System", flags: .restricted)
            scatter(directory(system, "Library", flags: .restricted), count: scaled(2_000), prefix: "sys_", ext: "dylib", low: 3_000, high: 8 * megabyte, ageDays: 60, flags: .restricted)
        }

        mutating func scaled(_ value: Int) -> Int { max(1, Int(Double(value) * scale)) }

        mutating func directory(_ parent: NodeID, _ name: String, package: Bool = false, flags: NodeFlags = []) -> NodeID {
            var nodeFlags: NodeFlags = [.directory]
            if package { nodeFlags.insert(.package) }
            nodeFlags.formUnion(flags)
            return builder.add(parent: parent, name: name, record: NodeRecord(allocated: 4_096, logical: 4_096, modified: timestamp(ageDays: 100), accessed: timestamp(ageDays: 100), flags: nodeFlags, kind: .other, inode: random.next()))
        }

        mutating func file(_ parent: NodeID, _ name: String, _ size: UInt64, ageDays: Int, flags: NodeFlags = []) {
            let modified = timestamp(ageDays: Int(Double(ageDays) * random.unit(0.5, 1.2)))
            let accessed = timestamp(ageDays: Int(Double(ageDays) * random.unit(0.1, 0.5)))
            builder.add(parent: parent, name: name, record: NodeRecord(allocated: size, logical: size, modified: modified, accessed: accessed, flags: flags, kind: FileKindClassifier.classify(name), inode: random.next()))
        }

        /// Adds files whose sizes follow a heavy-tailed distribution between `low` and `high`.
        mutating func scatter(_ parent: NodeID, count: Int, prefix: String, ext: String, low: UInt64, high: UInt64, ageDays: Int, flags: NodeFlags = []) {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            for index in 0..<count {
                file(parent, "\(prefix)\(index)\(suffix)", random.size(low, high), ageDays: ageDays, flags: flags)
            }
        }

        /// Adds a `node_modules`-style swarm: many small packages of tiny files.
        mutating func swarm(_ parent: NodeID, packages: Int, filesPerPackage: Int, ageDays: Int) {
            for package in 0..<packages {
                let folder = directory(parent, "pkg-\(package)")
                scatter(folder, count: filesPerPackage, prefix: "index_", ext: "js", low: 200, high: 90_000, ageDays: ageDays)
            }
        }

        func timestamp(ageDays: Int) -> Int32 { SyntheticTree.referenceNow - Int32(max(ageDays, 0) * 86_400) }
    }

    /// A small deterministic random generator, so synthetic trees are identical across runs and platforms.
    private struct SplitMix {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func unit(_ low: Double = 0, _ high: Double = 1) -> Double {
            low + (high - low) * Double(next() >> 11) / Double(UInt64(1) << 53)
        }

        /// A log-uniform size biased small, which produces a long tail.
        mutating func size(_ low: UInt64, _ high: UInt64) -> UInt64 {
            let lowLog = log(Double(max(low, 1))), highLog = log(Double(max(high, low + 1)))
            let skewed = pow(unit(), 2.2)
            return UInt64(exp(lowLog + (highLog - lowLog) * skewed))
        }
    }
}
