import Foundation

/// MIS Pay API environment. Endpoints `token` (GET) and `start-checkout` (POST)
/// resolve relative to `baseUrl`.
public enum MISPayEnvironment: Sendable {
    /// Sandbox environment provided by the MIS Pay team.
    case sandbox
    /// Production environment.
    case production
    /// Custom environment for private deployments (HTTPS enforced).
    case custom(baseUrl: String)

    public var baseUrl: String {
        switch self {
        case .sandbox:
            return "https://api-sandbox.mispay.dev/v1/api/"
        case .production:
            return "https://api.mispay.co/v1/api/"
        case .custom(let baseUrl):
            let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            precondition(trimmed.lowercased().hasPrefix("https://"),
                         "Custom MISPayEnvironment must use HTTPS, got: \(trimmed)")
            return trimmed
        }
    }
}

/// SDK configuration captured by `MISPay.initialize`.
public struct MISPayConfig: Sendable {
    public let appId: String
    public let appSecret: String
    public let environment: MISPayEnvironment

    public init(appId: String, appSecret: String, environment: MISPayEnvironment) {
        self.appId = appId
        self.appSecret = appSecret
        self.environment = environment
    }
}
