import Foundation

nonisolated struct AppSettings: Codable, Hashable {
    var mlxServerExecutablePath: String
    var rapidMLXExecutablePath: String
    var defaultHost: String
    var defaultPort: Int
    var apiKeyPlaceholder: String
    var hermesConfigPath: String
    var downloadSaveDirectory: String
    var maxConcurrentModelDownloads: Int
    var autoUnloadEnabledByModelID: [String: Bool]
    var autoUnloadMinutesByModelID: [String: Int]
    var benchmarkPreset: BenchmarkPreset
    var launchPlans: [LaunchPlanDefinition]
    var resourceCalibrationRecords: [ResourceCalibrationRecord]
    var uiLanguage: AppLanguage
    var uiAppearance: String
    /// Show the status item in the menu bar.
    var showMenuBarIcon: Bool
    /// When the last window closes: hide the Dock icon and keep running (menu bar icon on),
    /// or quit (menu bar icon off). When false the app simply stays in the Dock.
    var backgroundOnLastWindowClose: Bool

    static let defaults = AppSettings(
        mlxServerExecutablePath: "",
        rapidMLXExecutablePath: "",
        defaultHost: "127.0.0.1",
        defaultPort: 8080,
        apiKeyPlaceholder: "not-required-local",
        hermesConfigPath: "~/.hermes/config.yaml",
        downloadSaveDirectory: "~/Models/mlx",
        maxConcurrentModelDownloads: 2,
        autoUnloadEnabledByModelID: [:],
        autoUnloadMinutesByModelID: [:],
        benchmarkPreset: .standard,
        launchPlans: [],
        resourceCalibrationRecords: [],
        uiLanguage: .system,
        uiAppearance: "system",
        showMenuBarIcon: true,
        backgroundOnLastWindowClose: false
    )

    init(
        mlxServerExecutablePath: String,
        rapidMLXExecutablePath: String = "",
        defaultHost: String,
        defaultPort: Int,
        apiKeyPlaceholder: String,
        hermesConfigPath: String = "~/.hermes/config.yaml",
        downloadSaveDirectory: String = "~/Models/mlx",
        maxConcurrentModelDownloads: Int = 2,
        autoUnloadEnabledByModelID: [String: Bool] = [:],
        autoUnloadMinutesByModelID: [String: Int] = [:],
        benchmarkPreset: BenchmarkPreset = .standard,
        launchPlans: [LaunchPlanDefinition] = [],
        resourceCalibrationRecords: [ResourceCalibrationRecord] = [],
        uiLanguage: AppLanguage = .system,
        uiAppearance: String = "system",
        showMenuBarIcon: Bool = true,
        backgroundOnLastWindowClose: Bool = false
    ) {
        self.mlxServerExecutablePath = mlxServerExecutablePath
        self.rapidMLXExecutablePath = rapidMLXExecutablePath
        self.defaultHost = defaultHost
        self.defaultPort = defaultPort
        self.apiKeyPlaceholder = apiKeyPlaceholder
        self.hermesConfigPath = hermesConfigPath
        self.downloadSaveDirectory = downloadSaveDirectory
        self.maxConcurrentModelDownloads = min(max(maxConcurrentModelDownloads, 1), 5)
        self.autoUnloadEnabledByModelID = autoUnloadEnabledByModelID
        self.autoUnloadMinutesByModelID = autoUnloadMinutesByModelID.mapValues { min(max($0, 1), 999) }
        self.benchmarkPreset = benchmarkPreset
        self.launchPlans = launchPlans
        self.resourceCalibrationRecords = Array(resourceCalibrationRecords.suffix(100))
        self.uiLanguage = uiLanguage
        self.uiAppearance = uiAppearance
        self.showMenuBarIcon = showMenuBarIcon
        self.backgroundOnLastWindowClose = backgroundOnLastWindowClose
    }

    private enum CodingKeys: String, CodingKey {
        case mlxServerExecutablePath
        case rapidMLXExecutablePath
        case defaultHost
        case defaultPort
        case apiKeyPlaceholder
        case hermesConfigPath
        case downloadSaveDirectory
        case maxConcurrentModelDownloads
        case autoUnloadEnabledByModelID
        case autoUnloadMinutesByModelID
        case benchmarkPreset
        case launchPlans
        case resourceCalibrationRecords
        case uiLanguage
        case uiAppearance
        case showMenuBarIcon
        case backgroundOnLastWindowClose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mlxServerExecutablePath = try container.decode(String.self, forKey: .mlxServerExecutablePath)
        rapidMLXExecutablePath = try container.decodeIfPresent(String.self, forKey: .rapidMLXExecutablePath) ?? ""
        defaultHost = try container.decode(String.self, forKey: .defaultHost)
        defaultPort = try container.decode(Int.self, forKey: .defaultPort)
        apiKeyPlaceholder = try container.decode(String.self, forKey: .apiKeyPlaceholder)
        hermesConfigPath = try container.decodeIfPresent(String.self, forKey: .hermesConfigPath) ?? "~/.hermes/config.yaml"
        downloadSaveDirectory = try container.decodeIfPresent(String.self, forKey: .downloadSaveDirectory) ?? "~/Models/mlx"
        let decodedConcurrentDownloads = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentModelDownloads) ?? 2
        maxConcurrentModelDownloads = min(max(decodedConcurrentDownloads, 1), 5)
        autoUnloadEnabledByModelID = try container.decodeIfPresent([String: Bool].self, forKey: .autoUnloadEnabledByModelID) ?? [:]
        let decodedAutoUnloadMinutes = try container.decodeIfPresent([String: Int].self, forKey: .autoUnloadMinutesByModelID) ?? [:]
        autoUnloadMinutesByModelID = decodedAutoUnloadMinutes.mapValues { min(max($0, 1), 999) }
        benchmarkPreset = try container.decodeIfPresent(BenchmarkPreset.self, forKey: .benchmarkPreset) ?? .standard
        launchPlans = try container.decodeIfPresent([LaunchPlanDefinition].self, forKey: .launchPlans) ?? []
        resourceCalibrationRecords = Array(
            (try container.decodeIfPresent([ResourceCalibrationRecord].self, forKey: .resourceCalibrationRecords) ?? [])
                .suffix(100)
        )
        uiLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .uiLanguage) ?? .system
        uiAppearance = try container.decodeIfPresent(String.self, forKey: .uiAppearance) ?? "system"
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        backgroundOnLastWindowClose = try container.decodeIfPresent(Bool.self, forKey: .backgroundOnLastWindowClose) ?? false
    }

    func executablePath(for backend: InferenceBackend) -> String {
        switch backend {
        case .mlxLM:
            mlxServerExecutablePath
        case .rapidMLX:
            rapidMLXExecutablePath
        }
    }
}
