// swift-tools-version:5.7
import PackageDescription

let package = Package(
	name: "m1craft-server",
	platforms: [
		.macOS(.v13)
	],
	dependencies: [
		// 💧 A server-side Swift web framework.
		.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
		.package(url: "https://github.com/vapor/leaf.git", from: "4.0.0"),
		.package(url: "https://github.com/ezfe/minecraft-jar-command.git", branch: "main"),
		// .package(path: "/Users/ezekielelin/github_repositories/Minecraft Launcher/minecraft-jar-command"),
		.package(url: "https://github.com/mxcl/Version.git", from: "2.0.1"),
		.package(url: "https://github.com/crossroadlabs/Regex.git", from: "1.2.0")
	],
	targets: [
		.target(
			name: "App",
			dependencies: [
				.product(name: "Leaf", package: "leaf"),
				.product(name: "Vapor", package: "vapor"),
				.product(name: "Common", package: "minecraft-jar-command"),
				.product(name: "InstallationManager", package: "minecraft-jar-command"),
				.product(name: "Version", package: "Version"),
				.product(name: "Regex", package: "Regex")
			],
			swiftSettings: [
				// Enable better optimizations when building in Release configuration. Despite the use of
				// the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
				// builds. See <https://github.com/swift-server/guides/blob/main/docs/building.md#building-for-production> for details.
				.unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
			]
		),
		.executableTarget(name: "Run", dependencies: [.target(name: "App")]),
		.testTarget(name: "AppTests", dependencies: [
			.target(name: "App"),
			.product(name: "XCTVapor", package: "vapor"),
		])
	]
)
