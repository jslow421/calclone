// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GoNoGo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "gonogo",
            path: "Sources/gonogo",
            linkerSettings: [
                // A bare CLI has no bundle; embed Info.plist so TCC can show the usage string.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"])
            ]
        )
    ]
)
