import Foundation

/// Server-controlled switches so common changes don't need an App Store update.
/// Host `config.json` anywhere free (for example Firebase Remote Config or a static file on your server).
struct RemoteConfig: Codable {
    var minimumVersion = "1.0.0"
    var maintenance = false
    var maintenanceBackAround: String?
    var announcement: String?
    var supportEmail = "developer.nasar416@gmail.com"
    var teamEnabled = true
    var iCloudBackupEnabled = true

    init() {}

    /// Missing keys fall back to the defaults above, so the file only needs what changes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RemoteConfig()
        minimumVersion = try c.decodeIfPresent(String.self, forKey: .minimumVersion) ?? d.minimumVersion
        maintenance = try c.decodeIfPresent(Bool.self, forKey: .maintenance) ?? d.maintenance
        maintenanceBackAround = try c.decodeIfPresent(String.self, forKey: .maintenanceBackAround)
        announcement = try c.decodeIfPresent(String.self, forKey: .announcement)
        supportEmail = try c.decodeIfPresent(String.self, forKey: .supportEmail) ?? d.supportEmail
        teamEnabled = try c.decodeIfPresent(Bool.self, forKey: .teamEnabled) ?? d.teamEnabled
        iCloudBackupEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudBackupEnabled) ?? d.iCloudBackupEnabled
    }

    static let url: URL? = nil // e.g. URL(string: "https://your-server.example/config.json")

    static func fetch() async -> RemoteConfig {
        // Uses the Faxlane server's /v1/config when the server is configured.
        let source = url ?? APIClient.configuredBaseURL.map { APIClient(baseURL: $0, token: UUID()).url("v1/config") }
        guard let url = source else { return RemoteConfig() }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(RemoteConfig.self, from: data)
        } catch {
            return RemoteConfig()
        }
    }

    func requiresUpdate(current: String) -> Bool {
        current.compare(minimumVersion, options: .numeric) == .orderedAscending
    }
}
