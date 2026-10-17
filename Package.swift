// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DottTap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DottTap",
            path: "Sources/DottTap",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Network"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
