import Foundation

/// Saved mapping lives in ~/Library/Application Support, not the app bundle, so it survives
/// updates/reinstalls — same rationale as the Electron app's userData path.
enum MappingStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NagaConfigurator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mapping.json")
    }

    static func load() -> ButtonMapping {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(ButtonMapping.self, from: data) else {
            return DefaultMapping.value
        }
        return DefaultMapping.value.merging(saved) { _, new in new }
    }

    static func save(_ mapping: ButtonMapping) {
        guard let data = try? JSONEncoder().encode(mapping) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
