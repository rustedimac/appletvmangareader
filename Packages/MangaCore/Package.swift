// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MangaCore",
    platforms: [.tvOS(.v17), .macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MangaCore", targets: ["MangaCore"]),
    ],
    targets: [
        .target(name: "MangaCore",
                resources: [.copy("FreeLibrary/catalog.json")]),
        .testTarget(name: "MangaCoreTests", dependencies: ["MangaCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
