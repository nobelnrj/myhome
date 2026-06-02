import Testing
@testable import MyHome

// ---------------------------------------------------------------------------
// SpyGmailFetch — in-memory GmailFetchPort test double.
//
// GmailFetchPort is defined in MyHomeApp/Gmail/GmailFetchPort.swift
// (production file, plan 07-01). This file provides the test double only.
//
// Mirrors SpyGmailAuth.swift exactly in structure and naming conventions.
// ---------------------------------------------------------------------------

/// In-memory spy that returns canned results so unit tests can exercise every
/// Gmail fetch path without touching the OS network stack.
public final class SpyGmailFetch: GmailFetchPort, @unchecked Sendable {

    // MARK: - Settable stubs

    /// Controls the return value of getProfile(accessToken:).
    public var profileResult: GmailProfile = GmailProfile(emailAddress: "test@gmail.com")

    /// Controls the return value of listMessageIDs(accessToken:q:maxResults:).
    public var messageIDsResult: [String] = []

    /// Controls the return value of getRawMessage(accessToken:messageID:) for all IDs.
    /// If rawMessagesByID is non-empty, that lookup takes precedence.
    public var rawMessageResult: String = ""

    /// Per-message-ID raw message overrides. If non-empty, getRawMessage uses this lookup
    /// first; falls back to rawMessageResult if the ID is not found.
    public var rawMessagesByID: [String: String] = [:]

    /// When non-nil, getProfile() throws this error instead of returning profileResult.
    public var shouldThrowOnGetProfile: Error? = nil

    /// When non-nil, listMessageIDs() throws this error instead of returning messageIDsResult.
    public var shouldThrowOnListMessages: Error? = nil

    /// When non-nil, getRawMessage() throws this error instead of returning a raw message.
    public var shouldThrowOnGetRaw: Error? = nil

    // MARK: - Recorded calls

    /// All accessToken values passed to getProfile(), in call order.
    public private(set) var getProfileCalls: [String] = []

    /// All (accessToken, q, maxResults) tuples passed to listMessageIDs(), in call order.
    public private(set) var listMessageIDsCalls: [(String, String, Int)] = []

    /// All (accessToken, messageID) pairs passed to getRawMessage(), in call order.
    public private(set) var getRawMessageCalls: [(String, String)] = []

    public init() {}

    // MARK: - GmailFetchPort

    public func getProfile(accessToken: String) async throws -> GmailProfile {
        getProfileCalls.append(accessToken)
        if let error = shouldThrowOnGetProfile { throw error }
        return profileResult
    }

    public func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String] {
        listMessageIDsCalls.append((accessToken, q, maxResults))
        if let error = shouldThrowOnListMessages { throw error }
        return messageIDsResult
    }

    public func getRawMessage(accessToken: String, messageID: String) async throws -> String {
        getRawMessageCalls.append((accessToken, messageID))
        if let error = shouldThrowOnGetRaw { throw error }
        if !rawMessagesByID.isEmpty, let msg = rawMessagesByID[messageID] {
            return msg
        }
        return rawMessageResult
    }

    // MARK: - Reset

    /// Clears all recorded calls and resets error stubs and result stubs to defaults.
    /// Useful between tests if the same SpyGmailFetch is reused.
    public func reset() {
        getProfileCalls = []
        listMessageIDsCalls = []
        getRawMessageCalls = []
        shouldThrowOnGetProfile = nil
        shouldThrowOnListMessages = nil
        shouldThrowOnGetRaw = nil
        profileResult = GmailProfile(emailAddress: "test@gmail.com")
        messageIDsResult = []
        rawMessageResult = ""
        rawMessagesByID = [:]
    }
}
