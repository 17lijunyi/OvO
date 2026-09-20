// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ovo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ovo", targets: ["Ovo"])],
    targets: [
        .executableTarget(name: "Ovo", path: "Sources/Ovo"),
        .testTarget(name: "OvoTests", dependencies: ["Ovo"], path: "Tests/OvoTests")
    ],
    swiftLanguageVersions: [.v5]
)
