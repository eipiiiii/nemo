// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "nemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
        .package(url: "https://github.com/gonzalezreal/MarkdownUI", from: "2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "nemo",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "MarkdownUI", package: "MarkdownUI")
            ],
            path: "nemo",
            exclude: ["nemo.xcodeproj", "Assets.xcassets"] 
        ),
        .testTarget(
            name: "nemoTests",
            dependencies: ["nemo"],
            path: "nemoTests"
        ),
    ]
)
