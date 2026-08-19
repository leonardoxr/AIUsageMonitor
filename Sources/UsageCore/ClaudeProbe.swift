import Foundation

/// Reads the Claude plan quota with Claude Code's own OAuth credential.
///
/// The credential is read, never written: refreshing it is Claude Code's job, and
/// a clobbered store logs the user out of their CLI. An expired credential is
/// reported rather than refreshed.
///
/// `GET /api/oauth/usage` bills nothing against the plan, so this stays pollable
/// once a limit is reached — which is exactly when the number matters.
public enum ClaudeProbe {
    private static let quotaURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// The endpoint is gated behind Anthropic's OAuth beta flag.
    private static let oauthBeta = "oauth-2025-04-20"

    /// Where Claude Code keeps the credential in the macOS login keychain.
    private static let keychainService = "Claude Code-credentials"

    private static let timeout: TimeInterval = 15

    struct Credential: Sendable {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
    }

    public static func run(now: Date = Date()) async -> ProviderUsage {
        guard let credential = await Background.run({ readCredential() }) else {
            return .empty(
                .claude,
                .unauthenticated,
                "Claude Code is not signed in to a plan on this machine."
            )
        }
        if let expiresAt = credential.expiresAt, expiresAt <= now {
            return .empty(
                .claude,
                .unauthenticated,
                "The stored Claude Code login expired. Run `claude` to sign in again."
            )
        }

        var request = URLRequest(url: quotaURL, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue(oauthBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let body: Data
        let status: Int
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            body = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .empty(
                .claude,
                .unavailable,
                "Could not reach Anthropic: \(error.localizedDescription)"
            )
        }

        switch status {
        case 200..<300:
            return ClaudeUsageParser.parse(
                body: body,
                planLabel: credential.subscriptionType,
                fetchedAt: Date()
            )
        case 401, 403:
            return .empty(.claude, .unauthenticated, "Anthropic rejected the stored Claude Code login.")
        case 404:
            return .empty(.claude, .unsupported, "This Anthropic account does not report a plan quota.")
        default:
            return .empty(
                .claude,
                .unavailable,
                "Anthropic answered the quota request with HTTP \(status)."
            )
        }
    }

    /// The keychain on macOS, the credentials file everywhere else — the two stores
    /// hold the same JSON.
    static func readCredential() -> Credential? {
        let raw = readKeychain() ?? readCredentialFile()
        guard
            let raw,
            let root = JSON.object(try? JSONSerialization.jsonObject(with: Data(raw.utf8))),
            // A plan login nests under `claudeAiOauth`. An API-key login has no
            // such key, and an API key carries no plan quota.
            let oauth = JSON.object(root["claudeAiOauth"]),
            let accessToken = JSON.string(oauth["accessToken"])
        else { return nil }

        return Credential(
            accessToken: accessToken,
            expiresAt: ISODate.fromEpochMilliseconds(JSON.number(oauth["expiresAt"])),
            subscriptionType: JSON.string(oauth["subscriptionType"])
        )
    }

    private static func readKeychain() -> String? {
        Subprocess.capture(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", keychainService, "-w"]
        )
    }

    /// A default install nests the credential under `.claude`; an overridden
    /// `CLAUDE_CONFIG_DIR` is itself the config dir, so probe both.
    private static func readCredentialFile() -> String? {
        let home = NSHomeDirectory()
        var directories = [(home as NSString).appendingPathComponent(".claude")]
        if let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !configured.isEmpty {
            directories.insert((configured as NSString).expandingTildeInPath, at: 0)
        }
        for directory in directories {
            let path = (directory as NSString).appendingPathComponent(".credentials.json")
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) { return contents }
        }
        return nil
    }
}
