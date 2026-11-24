// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "macup",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "macup", targets: ["macup"])
    ],
    targets: [
        .executableTarget(
            name: "macup",
            path: "Sources/macup"
        ),
        .testTarget(
            name: "macupTests",
            dependencies: ["macup"],
            path: "Tests/macupTests"
        )
    ]
)
