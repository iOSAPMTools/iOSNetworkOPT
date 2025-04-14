// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkAPM",
    platforms: [
        .iOS(.v13) // Set appropriate minimum iOS version, requires Network framework and modern Swift
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NetworkAPM",
            targets: ["NetworkAPM"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NetworkAPM",
            dependencies: [],
            path: "NetworkAPM" // Specify the path to the source files
            // No need to explicitly link Foundation, UIKit, Network for target if deployment target is sufficient
        ),
        // Add test target if you have tests
        // .testTarget(
        //     name: "NetworkAPMTests",
        //     dependencies: ["NetworkAPM"]),
    ]
) 