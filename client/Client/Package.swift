// swift-tools-version: 6.2
import PackageDescription

// Exercises the app's exact sources on macOS, including cross-language tests.
// Xcode compiles these same files in the iOS app and its XCTest target.
let package = Package(
    name: "ClientAuth",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ClientAuth", targets: ["ClientAuth"])],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.4"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", exact: "2.12.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.5.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.39.0"),
    ],
    targets: [
        .target(
            name: "ClientAuth",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2TransportServices", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Client",
            exclude: ["ClientApp.swift", "ContentView.swift", "Assets.xcassets"]
        ),
        .testTarget(name: "ClientAuthTests", dependencies: ["ClientAuth"], path: "ClientTests"),
    ]
)
