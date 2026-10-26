// swift-tools-version:6.2

// DesignSystem — the local SPM package carrying the app's color, spacing, and
// typography tokens. It imports nothing from the app: the dependency arrow
// points one way only.
//
// The platform floor belongs here as well as in project.yml. If the two drift,
// the app fails to compile with a deployment-target mismatch against this
// module — the failure is loud, but it is cheaper to keep them in step.
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
    ]
)
