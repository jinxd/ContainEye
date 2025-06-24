// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "SwiftTermFuzz", targets: ["SwiftTermFuzz"]),
        //.executable(name: "CaptureOutput", targets: ["CaptureOutput"]),
        .library(
            name: "SwiftTerm",
            targets: ["SwiftTerm"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftSH", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            dependencies: [
                .product(name: "SwiftSH", package: "SwiftSH")
            ],
            path: "Sources/SwiftTerm"
        ),
        .target (
            name: "SwiftTermFuzz",
            dependencies: ["SwiftTerm"],
            path: "Sources/SwiftTermFuzz"
        ),
//        .target (
//            name: "CaptureOutput",
//            dependencies: ["SwiftTerm"],
//            path: "Sources/CaptureOutput"
//        ),        
        .testTarget(
            name: "SwiftTermTests",
            dependencies: ["SwiftTerm"],
            path: "Tests/SwiftTermTests"
        )
    ]
)
