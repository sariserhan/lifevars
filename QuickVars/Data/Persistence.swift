import Foundation
import SwiftData

enum Persistence {
    /// SPEC.md §15.2 — a device restore never brings the Keychain-sealed DEK
    /// with it (.ThisDeviceOnly), so a restored store file would just be
    /// unreadable ciphertext. Excluding it from backup means a restore starts
    /// QuickVars empty instead of full of data nothing can decrypt.
    static func makeContainer() -> ModelContainer {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let storeURL = appSupport.appendingPathComponent("QuickVars.sqlite")
        excludeFromBackup(storeURL)

        let schema = Schema([QuickVar.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
