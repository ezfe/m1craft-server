import Common
import Foundation
import InstallationManager
import Regex
import Vapor

struct IndexContext: Encodable {
	let version: String?
	let size: Double?
	let url: String?
}

func routes(_ app: Application) throws {
	app.get() { (req: Request) async throws -> Response in
		let appcastUrl = URL(string: "https://f001.backblazeb2.com/file/minecraft-jar-command/appcast/appcast")!
		let appcastResponse = try await retrieveData(from: appcastUrl).0
		let appcastXml = String(data: appcastResponse, encoding: .utf8)!
		
		let versionRegex = #"<sparkle:shortVersionString>(.+)</sparkle:shortVersionString>"#.r!
		let downloadRegex = #"<enclosure url="(.+)" length="(\d+)""#.r!
		
		let version: String? = versionRegex.findFirst(in: appcastXml)?.group(at: 1)
		let url: String? = downloadRegex.findFirst(in: appcastXml)?.group(at: 1)
		var size: Double? = nil
		
		if let sizeStr = downloadRegex.findFirst(in: appcastXml)?.group(at: 2),
			let sizeBytes = Double(sizeStr) {
			
			size = round(sizeBytes / 100_000.0) / 10.0
		}
		
		let view: View = try await req.view.render(
			"index",
			IndexContext(version: version, size: size, url: url)
		)
		let response = try await view.encodeResponse(for: req)
		response.headers.add(name: .cacheControl, value: "public, max-age=3600")
		return response		
	}
	
	try app.register(collection: ApiController())
	try app.register(collection: AuthController())
}
