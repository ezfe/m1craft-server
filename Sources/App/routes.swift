import Vapor
import Foundation
import InstallationManager

func routes(_ app: Application) throws {
	app.get { req in
		return req.view.render("index", ["title": "Hello Vapor!"])
	}

	app.get("hello") { req -> String in
		return "Hello, world!"
	}
}
