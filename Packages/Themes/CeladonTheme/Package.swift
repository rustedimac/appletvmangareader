// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CeladonTheme",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [.library(name: "CeladonTheme", targets: ["CeladonTheme"])],
    targets: [.target(name: "CeladonTheme")]
)
