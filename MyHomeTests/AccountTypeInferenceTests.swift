import Testing
import Foundation
@testable import MyHome

/// Tests for the account type inference helper (D-03).
///
/// Verifies that `inferAccountType(from:)` correctly matches CC/credit/card keywords
/// case-insensitively and defaults to "savings".
struct AccountTypeInferenceTests {

    @Test("inference: CC/credit/card keywords → credit_card; others → savings (D-03)")
    func inference() {
        // credit_card cases (case-insensitive keyword match: cc / credit / card)
        #expect(inferAccountType(from: "HDFC CC") == "credit_card",
                "\"HDFC CC\" should infer credit_card (cc keyword)")
        #expect(inferAccountType(from: "My Credit One") == "credit_card",
                "\"My Credit One\" should infer credit_card (credit keyword)")
        #expect(inferAccountType(from: "Platinum Card") == "credit_card",
                "\"Platinum Card\" should infer credit_card (card keyword)")

        // savings cases
        #expect(inferAccountType(from: "ICICI Savings") == "savings",
                "\"ICICI Savings\" should infer savings")
        #expect(inferAccountType(from: "Salary") == "savings",
                "\"Salary\" should infer savings (no CC/credit/card keyword)")
    }
}
