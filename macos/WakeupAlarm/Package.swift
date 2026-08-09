// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WakeupAlarm",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WakeupAlarm", targets: ["WakeupAlarm"])
    ],
    targets: [
        .executableTarget(
            name: "WakeupAlarm",
            path: "Sources/WakeupAlarm"
        )
    ]
)
