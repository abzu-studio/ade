// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ade",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AdeCore", targets: ["AdeCore"]),
    ],
    targets: [
        .target(name: "AdeCore"),
        .testTarget(name: "AdeCoreTests", dependencies: ["AdeCore"]),
    ],
    swiftLanguageVersions: [.v5]
)

#if os(macOS)
package.products.append(.executable(name: "Ade", targets: ["Ade"]))
package.targets.append(
    .executableTarget(
        name: "Ade",
        dependencies: ["AdeCore"],
        resources: [.process("Resources")]
    )
)
#endif
