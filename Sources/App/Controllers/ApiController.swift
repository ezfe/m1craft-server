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
		let manifest = try await VersionManifest.download(url: mojangUrl)
		
		let response = try await manifest.encodeResponse(for: req)
		response.headers.add(name: .cacheControl, value: "public, max-age=3600")
		
		return response
	}
	
	func getJavaInfo(req: Request) async throws -> JavaVersionResponse {
		guard let versionParameter = req.parameters.get("version") else {
			throw Abort(.notFound)
		}
		let version = UInt(versionParameter.dropLast(5))
		guard let version = version else {
			throw Abort(.badRequest)
		}
		
		switch version {
			case 17:
				return JavaVersionResponse(
					size: 42736210,
					sha1: "e84a8701daff8e3bd12bb607a0d63c0dd080b334",
					url: "https://f001.backblazeb2.com/file/minecraft-jar-command/java/java-17.32.13.zip",
					version: 17
				)
			case 16:
				return JavaVersionResponse(
					size: 38552902,
					sha1: "69dfc26aea8c82f77adbb73bda006cb457807f53",
					url: "https://f001.backblazeb2.com/file/minecraft-jar-command/java/zulu-16.jre.zip",
					version: 16
				)
			case 8:
				return JavaVersionResponse(
					size: 42339191,
					sha1: "84615950501a3731e069844a01f865c6ece4b521",
					url: "https://f001.backblazeb2.com/file/minecraft-jar-command/java/zulu-8.jre.zip",
					version: 8
				)
			default:
				throw Abort(.notFound)
		}
	}
	
	func getVersionPatch(req: Request) async throws -> VersionPatch {
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
		
		var response = VersionPatch(id: selectedVersion.id, clientJarURL: nil, libraries: [:])
		
		if selectedVersion.releaseTime < armIncludedFromVersion.releaseTime {
			response.libraries["lwjgl"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl", ".jar"),
				macOSNativeURL: urlFor("lwjgl", "-natives-macos-arm64.jar")
			);
			response.libraries["lwjgl-opengl"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-opengl", ".jar"),
				macOSNativeURL: urlFor("lwjgl-opengl", "-natives-macos-arm64.jar")
			);
			response.libraries["lwjgl-openal"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-openal", ".jar"),
				macOSNativeURL: urlFor("lwjgl-openal", "-natives-macos-arm64.jar")
			);
			response.libraries["lwjgl-jemalloc"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-jemalloc", ".jar"),
				macOSNativeURL: urlFor("lwjgl-jemalloc", "-natives-macos-arm64.jar")
			);
			response.libraries["lwjgl-stb"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-stb", ".jar"),
				macOSNativeURL: urlFor("lwjgl-stb", "-natives-macos-arm64.jar")
			);
			response.libraries["lwjgl-tinyfd"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-tinyfd", ".jar"),
				macOSNativeURL: urlFor("lwjgl-tinyfd", "-natives-macos-arm64.jar")
			);
			response.libraries["lwjgl-glfw"] = VersionPatch.LibraryPatch(
				newLibraryVersion: lwjglVersion,
				artifactURL: urlFor("lwjgl-glfw", ".jar"),
				macOSNativeURL: urlFor("lwjgl-glfw", "-natives-macos-arm64.jar")
			);
		}
		
		return response
	}
}
