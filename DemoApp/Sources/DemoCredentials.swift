import Foundation

/// Demo credentials loader.
///
/// Checks, in order:
///  1. `Credentials.local.plist` (gitignored — put YOUR sandbox credentials here);
///  2. `Credentials.plist` (committed template with REPLACE_ME placeholders).
enum DemoCredentials {

    struct Creds {
        let appId: String
        let appSecret: String
    }

    static func load() -> Creds? {
        let url = Bundle.main.url(forResource: "Credentials.local", withExtension: "plist")
            ?? Bundle.main.url(forResource: "Credentials", withExtension: "plist")
        guard let url = url,
              let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            return nil
        }
        let appId = dict["MISPAY_APP_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = dict["MISPAY_APP_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !appId.isEmpty, !secret.isEmpty,
              appId != "REPLACE_ME", secret != "REPLACE_ME" else {
            return nil
        }
        return Creds(appId: appId, appSecret: secret)
    }
}
