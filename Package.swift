// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MustRest",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MustRest", targets: ["MustRest"]),
        .executable(name: "MustRestApp", targets: ["MustRestApp"]),
    ],
    targets: [
        .target(
            name: "MustRest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MustRestApp",
            dependencies: ["MustRest"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MustRestTests",
            dependencies: ["MustRest"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
