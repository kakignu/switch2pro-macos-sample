// swift-tools-version:5.9
// Minimal sample: drive a Switch 2 Pro Controller from user space on macOS
// (no kext, no DriverKit). See README.md.
import PackageDescription

let package = Package(
    name: "Switch2ProMacOSSample",
    platforms: [.macOS(.v13)],
    targets: [
        // Objective-C wrapper around IOUSBHost (bulk OUT/IN on a vendor interface).
        // SwiftPM compiles ObjC targets without ARC by default -> -fobjc-arc.
        .target(
            name: "USBBulk",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
            ]
        ),
        .executableTarget(
            name: "switch2-sample",
            dependencies: ["USBBulk"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
    ]
)
