import Foundation

final class ConfigStore {
    static let shared = ConfigStore()

    let baseDirectory: URL
    let configURL: URL
    let customProvidersURL: URL
    let cacheDirectory: URL
    let scriptsDirectory: URL

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("agentbar", isDirectory: true)

        self.baseDirectory = root
        self.configURL = root.appendingPathComponent("config.json")
        self.customProvidersURL = root.appendingPathComponent("providers.json")
        self.cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
        self.scriptsDirectory = root.appendingPathComponent("scripts", isDirectory: true)

        ensureDirectories()
    }

    func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
    }

    func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    func saveConfig(_ config: AppConfig) {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    func loadCustomProviders() -> [CustomProviderConfig] {
        guard let data = try? Data(contentsOf: customProvidersURL),
              let decoded = try? JSONDecoder().decode([CustomProviderConfig].self, from: data) else {
            return []
        }
        return decoded
    }

    func saveCustomProviders(_ providers: [CustomProviderConfig]) {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(providers) {
            try? data.write(to: customProvidersURL, options: .atomic)
        }
    }

    func cacheFileURL(for providerID: String) -> URL {
        cacheDirectory.appendingPathComponent("\(providerID).json")
    }

    func readStandardCache(for providerID: String) -> StandardQuotaPayload? {
        let url = cacheFileURL(for: providerID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StandardQuotaPayload.self, from: data)
    }
}
