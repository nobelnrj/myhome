import Testing
import Foundation
@testable import MyHome

// Requirements: ING-01 (authorization URL construction with all required params)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/GmailAuthURLTests
// Plan 06-01 — RED phase: tests compile only after GmailSyncController + PKCE exist (Task 1).
// Tests FAIL RED because buildAuthorizationURL() returns nil (stub).

/// GmailAuthURLTests — unit tests for GmailSyncController.buildAuthorizationURL().
///
/// ING-01: The OAuth authorization URL must contain all required query parameters
///         for Google's authorization code flow with PKCE.
@MainActor
struct GmailAuthURLTests {

    // MARK: - Shared helpers

    private let testClientID = "test-client-id.apps.googleusercontent.com"
    private let testRedirectURI = "myhome-oauth://callback"
    private let testState = "test-state-12345"
    private let testPKCE = PKCE(verifier: "test-verifier-43-chars-padded-extra-padding-1234", challenge: "test-challenge-value")

    // MARK: - ING-01: All required query parameters present

    @Test("containsClientID: buildAuthorizationURL includes client_id — ING-01")
    func containsClientID() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let clientIDItem = items.first { $0.name == "client_id" }
        #expect(clientIDItem?.value == testClientID, "URL must include client_id — ING-01")
    }

    @Test("containsRedirectURI: buildAuthorizationURL includes redirect_uri — ING-01")
    func containsRedirectURI() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let redirectItem = items.first { $0.name == "redirect_uri" }
        #expect(redirectItem?.value == testRedirectURI, "URL must include redirect_uri — ING-01")
    }

    @Test("containsResponseTypeCode: buildAuthorizationURL includes response_type=code — ING-01")
    func containsResponseTypeCode() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let responseTypeItem = items.first { $0.name == "response_type" }
        #expect(responseTypeItem?.value == "code", "URL must include response_type=code — ING-01")
    }

    @Test("containsGmailScope: buildAuthorizationURL includes scope=gmail.readonly — ING-01")
    func containsGmailScope() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let scopeItem = items.first { $0.name == "scope" }
        #expect(scopeItem?.value == "https://www.googleapis.com/auth/gmail.readonly",
                "URL must include scope=https://www.googleapis.com/auth/gmail.readonly — ING-01 (D6-03)")
    }

    @Test("containsCodeChallenge: buildAuthorizationURL includes code_challenge from PKCE — ING-01")
    func containsCodeChallenge() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let challengeItem = items.first { $0.name == "code_challenge" }
        #expect(challengeItem?.value == testPKCE.challenge, "URL must include code_challenge — ING-01 (D6-02)")
    }

    @Test("containsCodeChallengeMethodS256: buildAuthorizationURL includes code_challenge_method=S256 — ING-01")
    func containsCodeChallengeMethodS256() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let methodItem = items.first { $0.name == "code_challenge_method" }
        #expect(methodItem?.value == "S256", "URL must include code_challenge_method=S256 — ING-01 (D6-02)")
    }

    @Test("containsAccessTypeOffline: buildAuthorizationURL includes access_type=offline — ING-01")
    func containsAccessTypeOffline() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let accessTypeItem = items.first { $0.name == "access_type" }
        #expect(accessTypeItem?.value == "offline", "URL must include access_type=offline to receive a refresh token — ING-01")
    }

    @Test("containsState: buildAuthorizationURL includes state parameter — ING-01")
    func containsState() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let stateItem = items.first { $0.name == "state" }
        #expect(stateItem?.value == testState, "URL must include state parameter — ING-01")
    }

    @Test("containsPromptConsent: buildAuthorizationURL includes prompt=consent — ING-01")
    func containsPromptConsent() throws {
        let controller = GmailSyncController()
        let url = try #require(
            controller.buildAuthorizationURL(clientID: testClientID, redirectURI: testRedirectURI, pkce: testPKCE, state: testState),
            "buildAuthorizationURL must return a non-nil URL"
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let promptItem = items.first { $0.name == "prompt" }
        #expect(promptItem?.value == "consent",
                "URL must include prompt=consent to ensure refresh token re-issuance on reconnect — ING-01")
    }
}
