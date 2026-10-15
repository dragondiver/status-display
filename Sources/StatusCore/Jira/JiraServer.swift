import Foundation

public struct JiraServer: Codable, Equatable, Identifiable {
    public var domain: String
    public var email: String
    public var token: String

    public var id: String { domain }

    public init(domain: String, email: String, token: String) {
        self.domain = domain; self.email = email; self.token = token
    }
}
