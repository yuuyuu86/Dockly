// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dockly",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Dockly",
            path: "Sources/Dockly",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
