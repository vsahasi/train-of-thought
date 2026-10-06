// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "TrainOfThought",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TrainOfThought", targets: ["TrainOfThought"]),
        .library(name: "TrainCore", targets: ["TrainCore"]),
    ],
    targets: [
        // Pure Swift. No AppKit. Every rule of the railway lives here and is tested.
        .target(name: "TrainCore", path: "Sources/TrainCore"),

        // The Mac app: overlay, sensors, menu bar, settings.
        .executableTarget(
            name: "TrainOfThought",
            dependencies: ["TrainCore"],
            path: "Sources/TrainOfThought"
        ),

        .testTarget(
            name: "TrainCoreTests",
            dependencies: ["TrainCore"],
            path: "Tests/TrainCoreTests"
        ),
    ]
)
