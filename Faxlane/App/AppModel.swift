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

    init(service: FaxService = MockFaxService()) {
        self.service = service
        let defaults = UserDefaults.standard
        if let token = AccountStore.loadToken() {
            accountToken = token
            restoredFromBackup = !defaults.bool(forKey: "hasLaunched")
        } else {
            let token = UUID()
            AccountStore.saveToken(token)
            accountToken = token
            restoredFromBackup = false
        }
        if restoredFromBackup {
            stage = .restored
        } else if defaults.bool(forKey: "hasOnboarded") {
            stage = .main
        } else {
            stage = .language
        }
        defaults.set(true, forKey: "hasLaunched")
        let firstNumber = numbers.first?.id
        sendingNumberID = firstNumber
        groups = [ContactGroup(name: "Pharmacies", memberIDs: [contacts[0].id]),
                  ContactGroup(name: "Insurance companies", memberIDs: [contacts[1].id]),
                  ContactGroup(name: "Law offices", memberIDs: [contacts[2].id])]
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        withAnimation { stage = .main }
    }

    func loadRemoteConfig() async { remoteConfig = await RemoteConfig.fetch() }

    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }

    // MARK: Faxes

    var inbox: [Fax] { faxes.filter { $0.direction == .received && $0.deletedAt == nil }.sorted { $0.date > $1.date } }
    var sent: [Fax] { faxes.filter { $0.direction == .sent && !$0.isInOutbox && $0.deletedAt == nil }.sorted { $0.date > $1.date } }
    var outbox: [Fax] { faxes.filter { $0.isInOutbox && $0.deletedAt == nil } }
    var trash: [Fax] { faxes.filter { $0.deletedAt != nil } }
    var recent: [Fax] { Array(faxes.filter { $0.deletedAt == nil && !$0.isInOutbox }.sorted { $0.date > $1.date }.prefix(3)) }
    var unreadCount: Int { inbox.filter(\.unread).count }

    func markRead(_ fax: Fax) { update(fax) { $0.unread = false } }
    func moveToTrash(_ fax: Fax) { update(fax) { $0.deletedAt = .now } }
    func restore(_ fax: Fax) { update(fax) { $0.deletedAt = nil } }
    func emptyTrash() { faxes.removeAll { $0.deletedAt != nil } }
    func retry(_ fax: Fax) { update(fax) { $0.state = .queued } }

    func block(_ number: String, reason: String = String(localized: "Blocked by you")) {
        guard !blocked.contains(where: { $0.number == number }) else { return }
        blocked.insert(BlockedNumber(number: number, blockedAt: .now, reason: reason), at: 0)
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
        AccountStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: "hasOnboarded")
        faxes = []; contacts = []; blocked = []
        plan = nil
        isSignedIn = false
        let token = UUID()
        AccountStore.saveToken(token)
        accountToken = token
        stage = .language
    }
}
