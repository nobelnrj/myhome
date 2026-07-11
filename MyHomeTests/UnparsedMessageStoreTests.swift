import Testing
import Foundation
@testable import MyHome

// Requirements: 07-08 — retry queue for bank mails that matched a sender but no template.
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/UnparsedMessageStoreTests

/// UnparsedMessageStoreTests — unit tests for the per-account unparsed-mail retry queue.
///
/// Each test uses an isolated UserDefaults suite, so the suite runs in parallel safely.
struct UnparsedMessageStoreTests {

    /// Isolated UserDefaults + store per test.
    private func makeStore() -> UnparsedMessageStore {
        let name = "test.unparsed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UnparsedMessageStore(defaults: defaults)
    }

    @Test("record + ids: queued IDs round-trip in insertion order")
    func recordAndReadBack() {
        let store = makeStore()
        store.record("msg-1", account: "a@gmail.com")
        store.record("msg-2", account: "a@gmail.com")
        #expect(store.ids(for: "a@gmail.com") == ["msg-1", "msg-2"])
    }

    @Test("record is idempotent: re-recording an ID neither duplicates nor reorders it")
    func recordIsIdempotent() {
        let store = makeStore()
        store.record("msg-1", account: "a@gmail.com")
        store.record("msg-2", account: "a@gmail.com")
        store.record("msg-1", account: "a@gmail.com")
        #expect(store.ids(for: "a@gmail.com") == ["msg-1", "msg-2"])
    }

    @Test("accounts are isolated and keys are case-insensitive (D-MA-01 lowercased identity)")
    func accountsIsolatedAndCaseInsensitive() {
        let store = makeStore()
        store.record("msg-a", account: "A@Gmail.com")
        store.record("msg-b", account: "b@gmail.com")
        #expect(store.ids(for: "a@gmail.com") == ["msg-a"])
        #expect(store.ids(for: "b@gmail.com") == ["msg-b"])
    }

    @Test("remove deletes only the target ID; removing an absent ID is a no-op")
    func removeDeletesOnlyTarget() {
        let store = makeStore()
        store.record("msg-1", account: "a@gmail.com")
        store.record("msg-2", account: "a@gmail.com")
        store.remove("msg-1", account: "a@gmail.com")
        store.remove("msg-ghost", account: "a@gmail.com")
        #expect(store.ids(for: "a@gmail.com") == ["msg-2"])
    }

    @Test("cap evicts the oldest entries first once maxPerAccount is exceeded")
    func capEvictsOldestFirst() {
        let store = makeStore()
        for i in 0...UnparsedMessageStore.maxPerAccount {  // one more than the cap
            store.record("msg-\(i)", account: "a@gmail.com")
        }
        let ids = store.ids(for: "a@gmail.com")
        #expect(ids.count == UnparsedMessageStore.maxPerAccount)
        #expect(ids.first == "msg-1", "oldest entry (msg-0) must be evicted first")
        #expect(ids.last == "msg-\(UnparsedMessageStore.maxPerAccount)")
    }

    @Test("removeAll clears one account's queue without touching others (sign-out)")
    func removeAllClearsAccount() {
        let store = makeStore()
        store.record("msg-a", account: "a@gmail.com")
        store.record("msg-b", account: "b@gmail.com")
        store.removeAll(for: "a@gmail.com")
        #expect(store.ids(for: "a@gmail.com").isEmpty)
        #expect(store.ids(for: "b@gmail.com") == ["msg-b"])
    }
}
