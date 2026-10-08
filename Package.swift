// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicSpeedChanger",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "MusicSpeedChanger", targets: ["MusicSpeedChanger"]),
        .executable(name: "ExportTest", targets: ["ExportTest"]),
    ],
    targets: [
        .target(name: "MSCCore"),
        .executableTarget(
            name: "MusicSpeedChanger",
            dependencies: ["MSCCore"]
        ),
        .executableTarget(
            name: "ExportTest",
            dependencies: ["MSCCore"]
        ),
    ]
)
