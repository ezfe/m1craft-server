//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 6/13/22.
//

import Foundation
import Vapor
import InstallationManager
import Version

struct PreflightResponse: Content {
	let message: String?
	let url: String?
}

extension VersionPatch: Content { }

struct JavaVersionResponse: Content {
	let size: UInt
	let sha1: String
	let url: String
	let version: UInt
}

extension VersionManifest: Content { }

struct ApiController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let api = routes.grouped("api")
		
		api.get("preflight", use: self.getPreflight(req:))
		api.get("manifest", use: self.getManifest(req:))
		api.get("java", ":version", use: self.getJavaInfo(req:))
		api.get("patch", ":version", use: self.getVersionPatch(req:))
	}
	
	func getPreflight(req: Request) async throws -> Response {
		let appVersionString: String = try req.query.get(at: "app_version")
		let updateRequiredResponse = PreflightResponse(
			message: "An update is required to continue. Future updates can be installed faster.",
			url: "https://m1craft.ezekiel.dev"
		)
		
		guard let appVersion = Version(appVersionString) else {
			req.logger.warning("Unexpected app version string: \(appVersionString)")
			return try await updateRequiredResponse.encodeResponse(status: .forbidden, for: req)
		}
		
		if appVersion < Version(major: 1, minor: 2, patch: 0) {
			return try await updateRequiredResponse.encodeResponse(status: .forbidden, for: req)
		}
		
		// No fields set, no status code set
		return try await PreflightResponse(message: nil, url: nil).encodeResponse(for: req)
	}
	
	func getManifest(req: Request) async throws -> Response {
		let mojangUrl = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
		
		var manifest = try await VersionManifest.download(url: mojangUrl)
		
		if let version1_14_2 = manifest.versions.first(where: { $0.id == "1.14.2" }) {
			manifest.versions = manifest.versions.filter { $0.releaseTime >= version1_14_2.releaseTime }
		}
		
		let response = try await manifest.encodeResponse(for: req)
		response.headers.add(name: .cacheControl, value: "public, max-age=3600")
		
		return response
	}
	
	func getJavaInfo(req: Request) async throws -> Response {
		guard let versionParameter = req.parameters.get("version") else {
			throw Abort(.notFound)
		}
		let version = UInt(versionParameter.dropLast(5))
		guard let version = version else {
			throw Abort(.badRequest)
		}
		
		let jvr: JavaVersionResponse
		switch version {
			case 17:
				jvr = JavaVersionResponse(
					size: 42736210,
					sha1: "e84a8701daff8e3bd12bb607a0d63c0dd080b334",
					url: "https://f001.backblazeb2.com/file/minecraft-jar-command/java/java-17.32.13.zip",
					version: 17
				)
			case 16:
				jvr = JavaVersionResponse(
					size: 38552902,
					sha1: "6c8b77f739d5f80e7c278b9f174359eadee9ef3e",
					url: "https://f001.backblazeb2.com/file/minecraft-jar-command/java/zulu-16.jre.zip",
					version: 16
				)
			case 8:
				jvr = JavaVersionResponse(
					size: 42339191,
					sha1: "84615950501a3731e069844a01f865c6ece4b521",
					url: "https://f001.backblazeb2.com/file/minecraft-jar-command/java/zulu-8.jre.zip",
					version: 8
				)
			default:
				throw Abort(.notFound)
		}
		
		let response = try await jvr.encodeResponse(for: req)
		response.headers.add(name: .cacheControl, value: "public, max-age=3600")
		return response
	}
	
	func getVersionPatch(req: Request) async throws -> Response {
		guard let versionParameter = req.parameters.get("version")?.dropLast(5) else {
			throw Abort(.notFound)
		}
		
		let manifest = try await VersionManifest.download()
		
		let armIncludedFromVersion = manifest.versions.first(where: { $0.id == "1.19-pre1" })
		let selectedVersion = manifest.versions.first(where: { $0.id == versionParameter })
		
		guard let armIncludedFromVersion = armIncludedFromVersion,
			  let selectedVersion = selectedVersion else {
			throw Abort(.notFound)
		}
		
		let lwjglVersion = "3.3.1"
		func urlFor(_ prefix: String, _ suffix: String) -> String {
			return "https://libraries.minecraft.net/org/lwjgl/\(prefix)/\(lwjglVersion)/\(prefix)-\(lwjglVersion)\(suffix)";
		}
		
		var patch = VersionPatch(id: selectedVersion.id, clientJarURL: nil, removeIcon: false, libraries: [:])
		
		if selectedVersion.releaseTime < armIncludedFromVersion.releaseTime {
			patch.removeIcon = true
			patch.libraries["lwjgl"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl", ".jar"),
				macOSNativeURL: urlFor("lwjgl", "-natives-macos-arm64.jar")
			);
			patch.libraries["lwjgl-opengl"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-opengl", ".jar"),
				macOSNativeURL: urlFor("lwjgl-opengl", "-natives-macos-arm64.jar")
			);
			patch.libraries["lwjgl-openal"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-openal", ".jar"),
				macOSNativeURL: urlFor("lwjgl-openal", "-natives-macos-arm64.jar")
			);
			patch.libraries["lwjgl-jemalloc"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-jemalloc", ".jar"),
				macOSNativeURL: urlFor("lwjgl-jemalloc", "-natives-macos-arm64.jar")
			);
			patch.libraries["lwjgl-stb"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-stb", ".jar"),
				macOSNativeURL: urlFor("lwjgl-stb", "-natives-macos-arm64.jar")
			);
			patch.libraries["lwjgl-tinyfd"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-tinyfd", ".jar"),
				macOSNativeURL: urlFor("lwjgl-tinyfd", "-natives-macos-arm64.jar")
			);
			patch.libraries["lwjgl-glfw"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-glfw", ".jar"),
				macOSNativeURL: urlFor("lwjgl-glfw", "-natives-macos-arm64.jar")
			);
		}
		
		let response = try await patch.encodeResponse(for: req)
		response.headers.add(name: .cacheControl, value: "public, max-age=3600")
		return response
	}
}
