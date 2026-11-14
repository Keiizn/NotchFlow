// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchFlow", targets: ["NotchFlow"]),
        .executable(name: "notchflow-smc", targets: ["notchflow-smc"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchFlow",
            path: "Sources/NotchFlow"
        ),
        // Assistant de gestion de charge (écriture SMC, exécuté en root via sudo)
        .executableTarget(
            name: "notchflow-smc",
            path: "Sources/notchflow-smc",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
    ]
)
