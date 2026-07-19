import Foundation
import UniformTypeIdentifiers

/// SYNC-03 — the exported custom document type for `.myhomesnap` snapshot files.
///
/// AirDrop and the Files app both key on this UTType: because `Info.plist` declares it as an
/// `UTExportedTypeDeclaration` conforming to `public.json`, a `.myhomesnap` file becomes a
/// recognised document that can be shared to / opened into MyHome with NO entitlement (the
/// free-tier transport). The identifier here MUST match the `UTTypeIdentifier` in Info.plist
/// byte-for-byte or the type never registers.
extension UTType {
    /// The MyHome sync snapshot document type — `com.reojacob.myhome.snapshot`, extension
    /// `.myhomesnap`, conforming to `public.json`. Declared (exportedAs) by this app.
    static let myHomeSnapshot = UTType(exportedAs: "com.reojacob.myhome.snapshot")
}

/// A `URL` wrapped for `.sheet(item:)` presentation without a retroactive `URL: Identifiable`
/// conformance (which would risk colliding with a future SDK conformance). The `absoluteString`
/// is a stable identity for the incoming snapshot file.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Writes snapshot bytes to a shareable temporary `.myhomesnap` file.
///
/// The share sheet (AirDrop / Save to Files) shares a *file URL*, not raw Data, so the exported
/// snapshot must first land on disk with the correct extension. Files go to the system temp
/// directory (transient, user-controlled — see T-18-12) named
/// `MyHome-<sanitizedDeviceName>-<yyyyMMdd-HHmmss>.myhomesnap`.
enum SnapshotFile {

    /// Write `data` to a uniquely-named `.myhomesnap` file in `temporaryDirectory` and return its URL.
    /// `deviceName` is sanitized to alphanumerics only so an arbitrary device name can never produce
    /// an invalid or path-traversing filename.
    @MainActor
    static func writeTemporary(data: Data, deviceName: String) throws -> URL {
        let sanitized = deviceName.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
        let deviceComponent = sanitized.isEmpty ? "Device" : String(sanitized)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        let filename = "MyHome-\(deviceComponent)-\(stamp).myhomesnap"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
