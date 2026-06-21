// DesignTokensTests.swift
// Value-assertion tests for DS-01 DesignTokens constants.
// Phase 13 Plan 01

import Testing
import Foundation
@testable import MyHome

@MainActor
struct DesignTokensTests {

    @Test("DesignTokens.accent equals #FFD60A")
    func accentColorMatchesSpec() throws {
        #expect(DesignTokens.accent.hexString.uppercased() == "#FFD60A")
    }

    @Test("DesignTokens.shadowRaised light x=-6, dark x=7")
    func shadowRaisedSpec() throws {
        #expect(DesignTokens.shadowRaised.lightX == -6)
        #expect(DesignTokens.shadowRaised.darkX  == 7)
    }

    @Test("DesignTokens.radiusCard equals 26")
    func radiusCard() throws {
        #expect(DesignTokens.radiusCard == 26)
    }

    @Test("DesignTokens.tabBarClearance equals 100")
    func tabBarClearance() throws {
        #expect(DesignTokens.tabBarClearance == 100)
    }
}
