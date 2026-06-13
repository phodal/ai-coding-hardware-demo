// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArduinoCameraTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CameraAligner", targets: ["CameraAligner"]),
        .executable(name: "CameraSnapshot", targets: ["CameraSnapshot"])
    ],
    targets: [
        .executableTarget(name: "CameraAligner"),
        .executableTarget(name: "CameraSnapshot")
    ]
)
