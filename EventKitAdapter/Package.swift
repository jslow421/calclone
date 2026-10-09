// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EventKitAdapter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EventKitAdapter", targets: ["EventKitAdapter"]),
        .executable(name: "calclone-sync", targets: ["calclone-sync"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(
            name: "EventKitAdapter",
            dependencies: [.product(name: "Core", package: "Core")]
        ),
        .executableTarget(
            name: "calclone-sync",
            dependencies: ["EventKitAdapter", .product(name: "Core", package: "Core")],
            exclude: ["Info.plist"],
            linkerSettings: [
                // A bare CLI has no bundle; embed Info.plist so TCC can show the usage string.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", "Sources/calclone-sync/Info.plist"])
            ]
        ),
        .testTarget(
            name: "EventKitAdapterTests",
            dependencies: ["EventKitAdapter", .product(name: "Core", package: "Core")]
        ),
    ]
)
