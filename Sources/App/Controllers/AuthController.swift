//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 7/3/22.
//

import Vapor
import InstallationManager

let CLIENT_ID = "92188479-b731-4baa-b4cb-2aad9a47d10f"
let CLIENT_SECRET = ProcessInfo.processInfo.environment["CLIENT_SECRET"]!
let REDIRECT_URI = "http://localhost:8080/api/auth/redirect"

extension SignInResult: Content {}

struct AuthController: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		let api = routes.grouped("api", "auth")
		
		api.get("start", use: self.start(req:))
		api.get("redirect", use: self.auth(req:))
		api.get("refresh", use: self.refresh(req:))
	}
	
	func start(req: Request) async throws -> Response {
		req.logger.debug("Starting \(#function)")

		let clientId = "92188479-b731-4baa-b4cb-2aad9a47d10f"
		let redirectUri = REDIRECT_URI
		let scope = "XboxLive.signin%20offline_access"
		let sentState = try req.query.get(String.self, at: "state")
		
		return req.redirect(to: "https://login.live.com/oauth20_authorize.srf?client_id=\(clientId)&response_type=code&redirect_uri=\(redirectUri)&scope=\(scope)&state=\(sentState)")
	}
	
	func auth(req: Request) async throws -> Response {
		req.logger.debug("Starting \(#function)")

		let authCode = try req.query.get(String.self, at: "code")
		
		let azureAuthResult = try await azureAuth(code: authCode, refresh: false, logger: req.logger)
		let xblAuthResult = try await xblAuth(azureResponse: azureAuthResult, logger: req.logger)
		let xstsAuthResult = try await xstsAuth(xblResponse: xblAuthResult, logger: req.logger)
		let mcAuthResult = try await minecraftAuth(xstsResponse: xstsAuthResult, logger: req.logger)
		let mcProfileResult = try await minecraftProfile(minecraftAuthResponse: mcAuthResult, logger: req.logger)
		
		let result = SignInResult(id: mcProfileResult.id, name: mcProfileResult.name, token: mcAuthResult.accessToken, refresh: azureAuthResult.refreshToken)
		let encoded = try JSONEncoder().encode(result).base64EncodedString()
		
		return req.redirect(to: "m1craft://auth?signInResult=\(encoded)")
	}
	
	func refresh(req: Request) async throws -> SignInResult {
		req.logger.debug("Starting \(#function)")

		let authCode = try req.query.get(String.self, at: "refreshToken")
		
		let azureAuthResult = try await azureAuth(code: authCode, refresh: true, logger: req.logger)
		let xblAuthResult = try await xblAuth(azureResponse: azureAuthResult, logger: req.logger)
		let xstsAuthResult = try await xstsAuth(xblResponse: xblAuthResult, logger: req.logger)
		let mcAuthResult = try await minecraftAuth(xstsResponse: xstsAuthResult, logger: req.logger)
		let mcProfileResult = try await minecraftProfile(minecraftAuthResponse: mcAuthResult, logger: req.logger)
		
		return SignInResult(id: mcProfileResult.id, name: mcProfileResult.name, token: mcAuthResult.accessToken, refresh: azureAuthResult.refreshToken)
	}
}

// MARK: Azure
struct AzureAuthResponse: Decodable {
	let accessToken: String
	let refreshToken: String
}

func azureAuth(code: String, refresh: Bool, logger: Logger) async throws -> AzureAuthResponse {
	logger.debug("Starting \(#function)")

	let url = URL(string: "https://login.live.com/oauth20_token.srf")!
	
	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
	
	let body: String
	if refresh {
		body = "client_id=\(CLIENT_ID)&client_secret=\(CLIENT_SECRET)&refresh_token=\(code)&grant_type=refresh_token&redirect_uri=\(REDIRECT_URI)"
	} else {
		body = "client_id=\(CLIENT_ID)&client_secret=\(CLIENT_SECRET)&code=\(code)&grant_type=authorization_code&redirect_uri=\(REDIRECT_URI)"
	}
	
	request.httpBody = body.data(using: .utf8)
	
	return try await submitAndDecode(request: request, response: AzureAuthResponse.self, logger: logger)
}

// MARK: XBL

struct XblAuthRequest: Encodable {
	let properties: Properties
	let relyingParty = "http://auth.xboxlive.com"
	let tokenType = "JWT"
	
	init(accessToken: String) {
		self.properties = Properties(accessToken: accessToken)
	}
	
	struct Properties: Encodable {
		let authMethod = "RPS"
		let siteName = "user.auth.xboxlive.com"
		let rpsTicket: String
		
		init(accessToken: String) {
			self.rpsTicket = "d=\(accessToken)"
		}
		
		enum CodingKeys: String, CodingKey {
			case authMethod = "AuthMethod"
			case siteName = "SiteName"
			case rpsTicket = "RpsTicket"
		}
	}
	
	enum CodingKeys: String, CodingKey {
		case properties = "Properties"
		case relyingParty = "RelyingParty"
		case tokenType = "TokenType"
	}
}
struct XblAuthResponse: Decodable {
	let token: String
	
	enum CodingKeys: String, CodingKey {
		case token = "Token"
	}
}

func xblAuth(azureResponse: AzureAuthResponse, logger: Logger) async throws -> XblAuthResponse {
	logger.debug("Starting \(#function)")

	let url = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
	let body = XblAuthRequest(accessToken: azureResponse.accessToken)
	return try await jsonPost(url: url, body: body, response: XblAuthResponse.self, logger: logger)
}

// MARK: XSTS
struct XSTSAuthRequest: Encodable {
	let properties: Properties
	let relyingParty = "rp://api.minecraftservices.com/"
	let tokenType = "JWT"
	
	init(userTokens: [String]) {
		self.properties = Properties(userTokens: userTokens)
	}
	
	struct Properties: Encodable {
		let sandboxId = "RETAIL"
		let userTokens: [String]
		
		init(userTokens: [String]) {
			self.userTokens = userTokens
		}
		
		enum CodingKeys: String, CodingKey {
			case sandboxId = "SandboxId"
			case userTokens = "UserTokens"
		}
	}
	
	enum CodingKeys: String, CodingKey {
		case properties = "Properties"
		case relyingParty = "RelyingParty"
		case tokenType = "TokenType"
	}

}
struct XSTSAuthResponse: Decodable {
	let token: String
	let displayClaims: DisplayClaims

	struct DisplayClaims: Decodable {
		let xui: [XUI]
		
		struct XUI: Decodable {
			let userHash: String
			
			enum CodingKeys: String, CodingKey {
				case userHash = "uhs"
			}
		}
	}
	
	enum CodingKeys: String, CodingKey {
		case token = "Token"
		case displayClaims = "DisplayClaims"
	}
}

func xstsAuth(xblResponse: XblAuthResponse, logger: Logger) async throws -> XSTSAuthResponse {
	logger.debug("Starting \(#function)")

	let url = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
	let body = XSTSAuthRequest(userTokens: [xblResponse.token])
	return try await jsonPost(url: url, body: body, response: XSTSAuthResponse.self, logger: logger)
}

// MARK: Minecraft (Auth)
struct MinecraftAuthRequest: Encodable {
	let identityToken: String
	
	init(userHash: String, xstsToken: String) {
		self.identityToken = "XBL3.0 x=\(userHash);\(xstsToken)"
	}
}
struct MinecraftAuthResponse: Decodable {
	let accessToken: String
}

func minecraftAuth(xstsResponse: XSTSAuthResponse, logger: Logger) async throws -> MinecraftAuthResponse {
	logger.debug("Starting \(#function)")

	let url = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
	let body = MinecraftAuthRequest(userHash: xstsResponse.displayClaims.xui[0].userHash, xstsToken: xstsResponse.token)
	return try await jsonPost(url: url, body: body, response: MinecraftAuthResponse.self, logger: logger)
}

// MARK: Minecraft (Profile)
struct MinecraftProfileResponse: Decodable {
	let id: String
	let name: String
}

func minecraftProfile(minecraftAuthResponse: MinecraftAuthResponse, logger: Logger) async throws -> MinecraftProfileResponse {
	logger.debug("Starting \(#function)")

	let url = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
	var request = URLRequest(url: url)
	addJsonHeaders(request: &request)
	request.addValue("Bearer \(minecraftAuthResponse.accessToken)", forHTTPHeaderField: "Authorization")

	return try await submitAndDecode(request: request, response: MinecraftProfileResponse.self, logger: logger)
}

// MARK: - Common

func jsonPost<Response: Decodable>(url: URL, body: Encodable, response: Response.Type, logger: Logger) async throws -> Response {
	logger.debug("Starting \(#function)")
	
	var request = URLRequest(url: url)
	request.httpMethod = "POST"
	addJsonHeaders(request: &request)
	request.httpBody = try JSONEncoder().encode(body)
 
	return try await submitAndDecode(request: request, response: response, logger: logger)
}

func addJsonHeaders(request: inout URLRequest) {
	request.addValue("application/json", forHTTPHeaderField: "Content-Type")
	request.addValue("application/json", forHTTPHeaderField: "Accept")
}

func submitAndDecode<Response: Decodable>(request: URLRequest, response: Response.Type, logger: Logger) async throws -> Response {
	logger.debug("Starting \(#function)")

	let (data, response) = try await URLSession.shared.data(for: request)
	guard let httpResponse = response as? HTTPURLResponse else {
		throw Abort(.internalServerError)
	}
	
	let bodyText = String(data: data, encoding: .utf8) ?? "no response body"
	logger.debug("\(bodyText)")
	
	let decoder = JSONDecoder()
	decoder.keyDecodingStrategy = .convertFromSnakeCase

	if httpResponse.statusCode == 200 {
		return try decoder.decode(Response.self, from: data)
	} else {
		logger.warning("Non-200 Status Code: \(httpResponse)")
		throw Abort(.badRequest, reason: bodyText)
	}
}
