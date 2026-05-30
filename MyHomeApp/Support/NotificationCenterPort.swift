import Foundation
import UserNotifications

// MARK: - NotificationCenterPort

/// Protocol seam that abstracts the four UNUserNotificationCenter operations required
/// by NotificationScheduler. Injecting this protocol lets unit tests run without
/// touching the OS notification center (SpyCenter in MyHomeTests).
///
/// NOTE: This protocol is defined here for the production conformer.
/// The test double (SpyCenter) in MyHomeTests/Support/SpyCenter.swift also conforms.
/// SpyCenter.swift declares `import MyHome` — the protocol must be public.
public protocol NotificationCenterPort: Sendable {
    /// Requests user authorization for the given options.
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    /// Adds a notification request to the center.
    func add(_ request: UNNotificationRequest) async throws
    /// Removes pending requests by identifier.
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    /// Returns all currently pending notification requests.
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

// MARK: - SystemNotificationCenter

/// Production conformer that wraps `UNUserNotificationCenter.current()`.
///
/// This is the only type in the scheduler subsystem that touches the OS notification center.
/// All unit tests inject SpyCenter instead.
public final class SystemNotificationCenter: NotificationCenterPort, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}
