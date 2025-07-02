// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AdapterStack",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "AdapterStack", targets: ["AdapterStack"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.2.0")
    ],
    targets: [
        .macro(
            name: "AdapterStackMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "AdapterStack",
            dependencies: ["AdapterStackMacros"]
        ),
        .testTarget(
            name: "AdapterStackTests",
            dependencies: [
                "AdapterStack",
                "AdapterStackMacros",
                .product(name: "MacroTesting", package: "swift-macro-testing")
            ]
        )
    ]
)