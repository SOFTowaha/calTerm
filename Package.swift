// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "calTerm",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CalTermCore"),
        .executableTarget(
            name: "ct",
            dependencies: ["CalTermCore"],
            // Embed Info.plist so macOS can show why calendar access is requested.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist",
            ])]
        ),
        .testTarget(name: "CalTermCoreTests", dependencies: ["CalTermCore"]),
    ]
)
