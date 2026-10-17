// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SpecimenPress",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SpecimenPress", targets: ["SpecimenPress"]),
        .executable(name: "specimen-press", targets: ["SpecimenPressCLI"])
    ],
    targets: [
        .target(
            name: "SpecimenPress",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "SpecimenPressCLI",
            dependencies: ["SpecimenPress"]
        ),
        .testTarget(
            name: "SpecimenPressTests",
            dependencies: ["SpecimenPress"]
        )
    ]
)
