// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Synchrosphere",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Synchrosphere",
            targets: ["Synchrosphere"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/frameworklabs/Pappe.git", .upToNextMajor(from: "0.3.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Synchrosphere",
            dependencies: ["Pappe"]),
        .testTarget(
            name: "SynchrosphereTests",
            dependencies: ["Synchrosphere"]),
    ]
)
