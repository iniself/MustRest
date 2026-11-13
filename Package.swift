// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MustRest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MustRest", targets: ["MustRest"]),
        .executable(name: "MustRestApp", targets: ["MustRestApp"]),
    ],
    targets: [
        .target(name: "MustRest"),
        .executableTarget(name: "MustRestApp", dependencies: ["MustRest"]),
        .testTarget(name: "MustRestTests", dependencies: ["MustRest"]),
    ]
)
