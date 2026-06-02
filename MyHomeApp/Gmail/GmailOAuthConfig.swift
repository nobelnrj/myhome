import Foundation

// MARK: - GmailOAuthConfig

/// Committable OAuth client configuration constants for the iOS Gmail sign-in flow.
///
/// These values come from a Google Cloud Console iOS OAuth 2.0 client registration.
/// iOS native apps have NO client_secret — the client_id is safe to commit.
/// (RFC 8252 §8.4 and Google Cloud documentation both confirm this.)
///
/// D6-04 (resolved via checkpoint D6-04): reverse-client-ID scheme is used.
/// The callbackScheme is the full reverse-domain prefix of the client_id,
/// which matches the registered CFBundleURLSchemes entry in Info.plist.
///
/// T-06-04-CALLBACK: ASWebAuthenticationSession validates the returned URL against
/// the registered scheme before delivering the callback, mitigating URL-scheme spoofing.
enum GmailOAuthConfig {
    /// Google Cloud Console iOS OAuth 2.0 client_id (not a secret for native apps).
    static let clientID: String = "555696841697-kd0mmjd21la88mk5aid2rh292l9gfbcj.apps.googleusercontent.com"

    /// Full redirect URI registered in Google Cloud Console.
    /// Must match exactly what the app sends in the authorize and exchangeCode requests.
    static let redirectURI: String = "com.googleusercontent.apps.555696841697-kd0mmjd21la88mk5aid2rh292l9gfbcj:/oauth2redirect"

    /// URL scheme prefix passed to ASWebAuthenticationSession as callbackURLScheme.
    /// This is the scheme component of redirectURI (before the colon).
    /// Also registered as CFBundleURLSchemes in Info.plist so the OS delivers the callback.
    static let callbackScheme: String = "com.googleusercontent.apps.555696841697-kd0mmjd21la88mk5aid2rh292l9gfbcj"
}
