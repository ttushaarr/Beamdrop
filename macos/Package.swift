// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BeamDrop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BeamDrop",
            targets: ["BeamDrop"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BeamDrop",
            path: "Sources/BeamDrop"
        )
    ]
)
