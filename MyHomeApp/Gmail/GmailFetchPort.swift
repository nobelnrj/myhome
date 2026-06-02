import Foundation

// MARK: - GmailFetchPort

/// Protocol seam that abstracts Gmail API calls for email retrieval and profile.
/// Mirrors GmailAuthPort pattern (D6-23). Injected into GmailSyncController.
/// The test double (SpyGmailFetch) lives in MyHomeTests/Support/SpyGmailFetch.swift.
public protocol GmailFetchPort: Sendable {
    func getProfile(accessToken: String) async throws -> GmailProfile
    func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String]
    func getRawMessage(accessToken: String, messageID: String) async throws -> String
}

// MARK: - GmailProfile

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String

    public init(emailAddress: String) {
        self.emailAddress = emailAddress
    }
}

// MARK: - GmailFetchError

/// UI-facing error states for Gmail API fetch operations.
///
/// Mirrors GmailAuthError's wrapping style (D6-18/19).
public enum GmailFetchError: Error, Sendable {
    /// A network-level error occurred during the request.
    case networkError(Error)
    /// The JSON response could not be decoded into the expected type.
    case decodingError
    /// The server returned a non-2xx HTTP status code.
    case httpError(Int)
}

// MARK: - SystemGmailFetch

/// Production conformer that performs real Gmail REST API calls via URLSession.
///
/// Implements the three GmailFetchPort methods against Gmail API v1:
/// - `getProfile`: GET /gmail/v1/users/me/profile
/// - `listMessageIDs`: GET /gmail/v1/users/me/messages with q + pagination (Pitfall 7)
/// - `getRawMessage`: GET /gmail/v1/users/me/messages/{id}?format=RAW + base64url decode
///
/// All calls use `Authorization: Bearer {accessToken}` over HTTPS (T-07-10).
/// Token never logged; held in-memory only.
/// Timeout: 60s (D6-24 pattern).
///
/// D6-23: Wrapped behind GmailFetchPort protocol seam (mirrors GmailAuthPort).
public final class SystemGmailFetch: GmailFetchPort, @unchecked Sendable {

    private static let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private static let timeoutInterval: TimeInterval = 60
    /// Maximum pages to follow for nextPageToken (Pitfall 7 — prevents runaway pagination).
    private static let maxPages = 3

    public init() {}

    // MARK: - getProfile

    /// Fetches the Gmail profile (emailAddress) for the authenticated user.
    ///
    /// GET https://gmail.googleapis.com/gmail/v1/users/me/profile
    /// Authorization: Bearer {accessToken}
    public func getProfile(accessToken: String) async throws -> GmailProfile {
        let urlString = "\(SystemGmailFetch.baseURL)/profile"
        guard let url = URL(string: urlString) else {
            throw GmailFetchError.decodingError
        }
        let data = try await performGET(url: url, accessToken: accessToken)
        do {
            return try JSONDecoder().decode(GmailProfile.self, from: data)
        } catch {
            throw GmailFetchError.decodingError
        }
    }

    // MARK: - listMessageIDs

    /// Lists message IDs matching a Gmail search query, following pagination.
    ///
    /// GET https://gmail.googleapis.com/gmail/v1/users/me/messages?q={q}&maxResults={n}
    /// Authorization: Bearer {accessToken}
    ///
    /// Follows `nextPageToken` up to `maxPages` pages (Pitfall 7 — do not fetch unbounded).
    /// Effective maxResults is capped at 500 per the Gmail API limit.
    public func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String] {
        let effectiveMax = min(maxResults, 500)
        var allIDs: [String] = []
        var pageToken: String? = nil
        var pagesFollowed = 0

        repeat {
            var components = URLComponents(string: "\(SystemGmailFetch.baseURL)/messages")!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "maxResults", value: "\(effectiveMax)"),
            ]
            if let token = pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw GmailFetchError.decodingError
            }

            let data = try await performGET(url: url, accessToken: accessToken)
            let response = try decodeMessagesResponse(data)
            allIDs.append(contentsOf: response.messageIDs)
            pageToken = response.nextPageToken
            pagesFollowed += 1

        } while pageToken != nil && pagesFollowed < SystemGmailFetch.maxPages

        return allIDs
    }

    // MARK: - getRawMessage

    /// Fetches the raw RFC 2822 email body for a given message ID.
    ///
    /// GET https://gmail.googleapis.com/gmail/v1/users/me/messages/{id}?format=RAW
    /// Authorization: Bearer {accessToken}
    ///
    /// The API returns a base64url-encoded `raw` field. Decoding:
    /// 1. Substitute `-` → `+` and `_` → `/` (base64url → base64 standard)
    /// 2. Pad to multiple of 4 with `=`
    /// 3. `Data(base64Encoded:)` → raw bytes
    /// 4. Decode as UTF-8
    public func getRawMessage(accessToken: String, messageID: String) async throws -> String {
        let urlString = "\(SystemGmailFetch.baseURL)/messages/\(messageID)?format=RAW"
        guard let url = URL(string: urlString) else {
            throw GmailFetchError.decodingError
        }
        let data = try await performGET(url: url, accessToken: accessToken)

        // Decode JSON to get the `raw` field (RESEARCH A3: lowercase "raw")
        struct RawMessageResponse: Decodable {
            let raw: String
        }
        let response: RawMessageResponse
        do {
            response = try JSONDecoder().decode(RawMessageResponse.self, from: data)
        } catch {
            throw GmailFetchError.decodingError
        }

        // Decode base64url → raw email bytes → UTF-8 string
        return try decodeBase64URL(response.raw)
    }

    // MARK: - Private helpers

    /// Performs a GET request with Bearer token authorization.
    ///
    /// Returns response body data. Throws GmailFetchError on network or HTTP errors.
    private func performGET(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = SystemGmailFetch.timeoutInterval
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        // T-07-10: token never logged; in-memory only

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailFetchError.networkError(
                    NSError(domain: "SystemGmailFetch", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "not an HTTPURLResponse"]))
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw GmailFetchError.httpError(httpResponse.statusCode)
            }
            return data
        } catch let fetchError as GmailFetchError {
            throw fetchError
        } catch {
            throw GmailFetchError.networkError(error)
        }
    }

    /// Decodes the messages list response JSON.
    private struct MessagesResponse {
        let messageIDs: [String]
        let nextPageToken: String?
    }

    private func decodeMessagesResponse(_ data: Data) throws -> MessagesResponse {
        struct Message: Decodable { let id: String }
        struct ListResponse: Decodable {
            let messages: [Message]?
            let nextPageToken: String?
        }
        do {
            let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
            let ids = decoded.messages?.map { $0.id } ?? []
            return MessagesResponse(messageIDs: ids, nextPageToken: decoded.nextPageToken)
        } catch {
            throw GmailFetchError.decodingError
        }
    }

    /// Decodes a base64url string (RFC 4648) to a UTF-8 string.
    ///
    /// base64url uses `-` and `_` instead of `+` and `/`, and omits `=` padding.
    private func decodeBase64URL(_ base64url: String) throws -> String {
        // Step 1: translate base64url → standard base64
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Step 2: pad to multiple of 4
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        // Step 3: decode to Data
        guard let data = Data(base64Encoded: base64) else {
            throw GmailFetchError.decodingError
        }
        // Step 4: decode UTF-8
        guard let string = String(data: data, encoding: .utf8) else {
            // Fallback: try latin-1 (some old emails use ISO-8859-1)
            guard let latin1 = String(data: data, encoding: .isoLatin1) else {
                throw GmailFetchError.decodingError
            }
            return latin1
        }
        return string
    }
}
