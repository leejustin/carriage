// swift-tools-version: 6.2
import PackageDescription

// FoldKit is the shared fold-posture helper for Carriage, Grid Fleet and Firstlight.
// It lives in this repo for now; lift the folder into its own repo when the second app needs it.
let package = Package(
    name: "FoldKit",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "FoldKit", targets: ["FoldKit"]),
    ],
    targets: [
        .target(
            name: "FoldKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "FoldKitTests",
            dependencies: ["FoldKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
