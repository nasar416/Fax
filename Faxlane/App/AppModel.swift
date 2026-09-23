import SwiftUI

/// App-wide state. Mock data today; swap in the backend through `FaxService`.
@MainActor
@Observable
final class AppModel {
    // Launch
    enum Stage { case language, onboarding, restored, main }
    var stage: Stage
    var remoteConfig = RemoteConfig()

    // Account
    var accountToken: UUID
    /// Server account ID; also the RevenueCat App User ID. Kept so purchases link up before the network answers.
    var accountID: String? = UserDefaults.standard.string(forKey: "accountID")
    var restoredFromBackup: Bool
    var isSignedIn = false
    var displayName = ""

    // Plan and pages
    var plan: PlanTier?
    var period: BillingPeriod = .monthly
    var pagesUsed = 88
    var freePagesLeft = 2
    var extraPages = 0
    var bannerDismissed = false

    var pageLimit: Int { plan.map { $0.pages(for: period) } ?? 3 }
    var pagesLeft: Int { plan == nil ? freePagesLeft : max(pageLimit - pagesUsed, 0) + extraPages }

    // Data
    var faxes: [Fax] = MockData.faxes
    var contacts: [Contact] = MockData.contacts
    var groups: [ContactGroup] = []
    var blocked: [BlockedNumber] = MockData.blocked
    var team: [TeamMember] = MockData.team
    var numbers: [FaxNumber] = MockData.numbers
    var sendingNumberID: UUID?
    var faxNumber: String? { plan == nil ? nil : (numbers.first?.number ?? "+1 (555) 014-2290") }

    // Settings
    var deliveryNotifications = true
    var newFaxAlerts = true
    var iCloudBackup = false
    var shareUsageForRefunds = false
    var requireFaceID = false
    var retentionDays = 30
    var pausedUntil: Date?

    // Sending
    var activeSend: SendJob?
    private let service: FaxService
    private let liveActivity = LiveActivityManager()

    struct SendJob: Identifiable {
        let id = UUID()
        var recipient: String
        var number: String
        var totalPages: Int
        var pagesSent = 0
        var phase: Phase = .dialing
        enum Phase: Equatable { case dialing, sending, delivered, failed(String) }
    }

    private(set) var api: APIClient?

    init(service: FaxService? = nil) {
        let defaults = UserDefaults.standard
        let token: UUID
        let restored: Bool
        if let saved = AccountStore.loadToken() {
            token = saved
            restored = !defaults.bool(forKey: "hasLaunched")
        } else {
            token = UUID()
            AccountStore.saveToken(token)
            restored = false
        }
        let client = APIClient.configuredBaseURL.map { APIClient(baseURL: $0, token: token) }

        // Every stored property without a default is set before `self` is used.
        accountToken = token
        restoredFromBackup = restored
        api = client
        if let service {
            self.service = service
        } else if let client {
            self.service = RemoteFaxService(api: client)
        } else {
            self.service = MockFaxService()
        }
        if restored {
            stage = .restored
        } else if defaults.bool(forKey: "hasOnboarded") {
            stage = .main
        } else {
            stage = .language
        }
        defaults.set(true, forKey: "hasLaunched")

        sendingNumberID = numbers.first?.id
        if client != nil {
            // Real data comes from the server; contacts stay on the phone.
            faxes = []
            blocked = []
            numbers = []
            team = [TeamMember(name: String(localized: "You"), email: "", role: .admin)]
        } else {
            groups = [ContactGroup(name: "Pharmacies", memberIDs: [contacts[0].id]),
                      ContactGroup(name: "Insurance companies", memberIDs: [contacts[1].id]),
                      ContactGroup(name: "Law offices", memberIDs: [contacts[2].id])]
        }
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        withAnimation { stage = .main }
    }

    func loadRemoteConfig() async { remoteConfig = await RemoteConfig.fetch() }

    /// Registers this device with the server and copies the account's plan and pages.
    func syncAccount() async {
        guard let api else { return }
        if let account = try? await api.register() { apply(account) }
    }

    func apply(_ account: APIClient.Account) {
        if accountID != account.id {
            accountID = account.id
            UserDefaults.standard.set(account.id, forKey: "accountID")
        }
        plan = account.plan.flatMap(PlanTier.init(rawValue:))
        if let p = account.period.flatMap(BillingPeriod.init(rawValue:)) { period = p }
        isSignedIn = account.signedIn
        if plan == nil {
            freePagesLeft = max(account.pagesLeft - max(account.extraPages, 0), 0)
        } else {
            pagesUsed = account.pagesUsed
        }
        extraPages = account.extraPages
    }

    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }

    // MARK: Faxes

    var inbox: [Fax] { faxes.filter { $0.direction == .received && $0.deletedAt == nil }.sorted { $0.date > $1.date } }
    var sent: [Fax] { faxes.filter { $0.direction == .sent && !$0.isInOutbox && $0.deletedAt == nil }.sorted { $0.date > $1.date } }
    var outbox: [Fax] { faxes.filter { $0.isInOutbox && $0.deletedAt == nil } }
    var trash: [Fax] { faxes.filter { $0.deletedAt != nil } }
    var recent: [Fax] { Array(faxes.filter { $0.deletedAt == nil && !$0.isInOutbox }.sorted { $0.date > $1.date }.prefix(3)) }
    var unreadCount: Int { inbox.filter(\.unread).count }

    func markRead(_ fax: Fax) {
        guard fax.unread else { return }
        update(fax) { $0.unread = false }
        remote { try await $0.updateFax(id: fax.id, read: true) }
    }
    func moveToTrash(_ fax: Fax) {
        update(fax) { $0.deletedAt = .now }
        remote { try await $0.updateFax(id: fax.id, deleted: true) }
    }
    func restore(_ fax: Fax) {
        update(fax) { $0.deletedAt = nil }
        remote { try await $0.updateFax(id: fax.id, deleted: false) }
    }
    func emptyTrash() {
        faxes.removeAll { $0.deletedAt != nil }
        remote { try await $0.emptyTrash() }
    }
    func retry(_ fax: Fax) { update(fax) { $0.state = .queued } }

    func block(_ number: String, reason: String = String(localized: "Blocked by you")) {
        guard !blocked.contains(where: { $0.number == number }) else { return }
        blocked.insert(BlockedNumber(number: number, blockedAt: .now, reason: reason), at: 0)
        remote { try await $0.block(number: number, reason: reason) }
    }

    func unblock(_ item: BlockedNumber) {
        blocked.removeAll { $0.id == item.id }
        remote { try await $0.unblock(number: item.number) }
    }

    /// Loads every folder from the server.
    func refreshFaxes() async {
        guard let api else { return }
        var all: [Fax] = []
        for folder in ["inbox", "sent", "outbox", "trash"] {
            if let items = try? await api.faxes(folder: folder) { all += items.map(\.model) }
        }
        faxes = all
        if let list = try? await api.blocked() {
            blocked = list.map { BlockedNumber(number: $0.number, blockedAt: Date(timeIntervalSince1970: $0.blockedAt), reason: $0.reason) }
        }
    }

    /// Fire-and-forget server call; the screen already shows the change.
    private func remote(_ action: @escaping @Sendable (APIClient) async throws -> Void) {
        guard let api else { return }
        Task { try? await action(api) }
    }

    private func update(_ fax: Fax, _ change: (inout Fax) -> Void) {
        guard let index = faxes.firstIndex(where: { $0.id == fax.id }) else { return }
        change(&faxes[index])
    }

    // MARK: Send

    /// Pages this fax will use. International pages count 3×.
    func cost(pages: Int, cover: Bool, country: Country) -> Int { (pages + (cover ? 1 : 0)) * country.pageMultiplier }

    func send(recipient: String, number: String, pages: [DraftPage], cover: CoverSheet, cost: Int) {
        let total = max(pages.count + (cover.enabled ? 1 : 0), 1)
        activeSend = SendJob(recipient: recipient, number: number, totalPages: total)
        liveActivity.start(recipient: recipient, number: number, totalPages: total)
        let stream = service.send(to: number, pages: pages, cover: cover)
        Task {
            do {
                for try await progress in stream {
                    switch progress {
                    case .dialing: activeSend?.phase = .dialing
                    case .sentPage(let page, let of):
                        activeSend?.phase = .sending
                        activeSend?.pagesSent = page
                        liveActivity.update(pagesSent: page, total: of)
                    case .delivered:
                        activeSend?.phase = .delivered
                        liveActivity.finish(delivered: true, total: total)
                        chargePages(cost)
                        faxes.append(Fax(party: recipient, number: number, pages: total, date: .now, direction: .sent, state: .delivered, pagesSent: total))
                    }
                }
            } catch {
                activeSend?.phase = .failed(error.localizedDescription)
                liveActivity.finish(delivered: false, total: total, reason: error.localizedDescription)
                faxes.append(Fax(party: recipient, number: number, pages: total, date: .now, direction: .sent, state: .failed, failureReason: error.localizedDescription))
            }
        }
    }

    private func chargePages(_ cost: Int) {
        if plan == nil { freePagesLeft = max(freePagesLeft - cost, 0); return }
        let fromPlan = min(cost, max(pageLimit - pagesUsed, 0))
        pagesUsed += fromPlan
        extraPages = max(extraPages - (cost - fromPlan), 0)
    }

    // MARK: Account

    func signOut() {
        isSignedIn = false
        displayName = ""
    }

    func deleteAccount() {
        if let api { Task { try? await api.deleteAccount() } }
        AccountStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: "hasOnboarded")
        faxes = []; contacts = []; blocked = []
        plan = nil
        isSignedIn = false
        let token = UUID()
        AccountStore.saveToken(token)
        accountToken = token
        accountID = nil
        UserDefaults.standard.removeObject(forKey: "accountID")
        if let base = APIClient.configuredBaseURL { api = APIClient(baseURL: base, token: token) }
        stage = .language
        Task { await syncAccount() } // registers the new guest; RevenueCat follows through accountID
    }
}
