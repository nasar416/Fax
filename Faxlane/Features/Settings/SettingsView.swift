import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store
    @State private var showPaywall = false
    @State private var showRedeem = false

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                NavigationLink {
                    if model.isSignedIn { AccountView() } else { SignInView() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Color(.systemGray3))
                        VStack(alignment: .leading, spacing: 2) {
                            if model.isSignedIn {
                                Text(verbatim: model.displayName.isEmpty ? "Apple ID" : model.displayName).font(.headline)
                                Text("Signed in with Apple").font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("Guest account").font(.headline)
                                Text("Comes back if you reinstall").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button { showPaywall = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bolt.fill").frame(width: 40, height: 40)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading) {
                            if let plan = model.plan { Text(plan.name).font(.headline) } else { Text("Free plan").font(.headline) }
                            Text("\(model.pagesLeft) pages left").font(.footnote).opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
                .listRowBackground(Brand.blue)
            }

            Section("Fax") {
                LabeledContent("My fax number") {
                    if let n = model.faxNumber { PhoneText(number: n) } else { Text("None yet") }
                }
                NavigationLink("Fax numbers") { NumbersView() }
                NavigationLink("Pause receiving") { PauseReceivingView() }
                NavigationLink("Contacts, groups & blocked") { ContactsView() }
            }

            if model.remoteConfig.teamEnabled {
                Section("Team") {
                    NavigationLink { TeamView() } label: {
                        LabeledContent("Team members", value: "\(model.team.count) / \(model.plan?.teamSeats ?? 1)")
                    }
                }
            }

            Section("App") {
                NavigationLink("Language") { LanguageView(embedded: true) }
                NavigationLink("Replay intro") { OnboardingView() }
            }

            Section {
                Toggle("Delivery notifications", isOn: $model.deliveryNotifications)
                Toggle("New fax received alerts", isOn: $model.newFaxAlerts)
            }

            Section {
                Toggle(isOn: $model.iCloudBackup) {
                    Label("Back up faxes to iCloud", systemImage: "icloud")
                }
            } footer: {
                Text("Keeps a private copy of every sent and received fax in your own iCloud, even after we delete it from our servers. Uses your iCloud storage.")
            }

            Section("Privacy") {
                NavigationLink { RetentionView() } label: { LabeledContent("Keep faxes for", value: String(localized: "\(model.retentionDays) days")) }
                Toggle("Share page usage for refund reviews", isOn: $model.shareUsageForRefunds)
            }

            Section("Support") {
                Button("Restore purchases") { Task { await store.restore() } }
                Button("Redeem a code") { showRedeem = true }
                NavigationLink("Help and support") { HelpView() }
            }

            Section {
                Text(verbatim: "Faxlane · \(model.appVersion)").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .offerCodeRedemption(isPresented: $showRedeem) { _ in Task { await store.syncAfterRedeem() } }
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Keep your fax number on every device").font(.display(32))
                Text("Your guest account usually comes back on its own if you reinstall. Sign in with Apple so you never lose your number, plan, history and receipts, even on a new iPhone.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Label("One tap with Face ID. No password to remember.", systemImage: "faceid")
                    Label("You can hide your email. Apple gives us a private relay address instead.", systemImage: "envelope")
                    Label("Works on every iPhone and iPad with your Apple ID.", systemImage: "iphone")
                }
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Brand.blue)
                AppleSignInButton { name, identityToken in
                    model.displayName = name
                    Task {
                        if let api = model.api, let identityToken,
                           let account = try? await api.signInWithApple(identityToken: identityToken) {
                            model.apply(account)
                            await model.refreshFaxes()
                        }
                        model.isSignedIn = true
                        dismiss()
                    }
                }
            }
            .padding(20)
        }
        .background(Brand.background)
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var showManage = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Text(verbatim: String(model.displayName.prefix(1)).uppercased())
                        .font(.title2.weight(.heavy)).foregroundStyle(.white)
                        .frame(width: 56, height: 56).background(Brand.blue, in: Circle())
                    VStack(alignment: .leading) {
                        Text(verbatim: model.displayName.isEmpty ? "Apple ID" : model.displayName).font(.headline)
                        Label("Signed in with Apple", systemImage: "apple.logo").font(.caption)
                    }
                }
            }
            Section("Plan and usage") {
                LabeledContent("Plan") { if let p = model.plan { Text(p.name) } else { Text("Free") } }
                if model.plan != nil, let end = model.planExpiresAt {
                    // Apple renews on this date unless the subscription was cancelled.
                    LabeledContent("Renews or ends", value: end.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Pages left", value: "\(model.pagesLeft)")
                Button("Manage subscription") { showManage = true }
                NavigationLink("Cancel subscription") { WinBackView() }
            }
            Section("Sign-in") {
                LabeledContent("Sign-in method", value: "Apple ID")
                NavigationLink("Privacy, Face ID and your data") { RetentionView() }
            }
            Section {
                Button("Sign out of this phone") { model.signOut() }
                NavigationLink { DeleteAccountView() } label: { Text("Delete account").foregroundStyle(Brand.failed) }
            } footer: {
                Text(verbatim: "Account ID \(model.accountToken.uuidString.prefix(8))")
            }
        }
        .navigationTitle("Account")
        .manageSubscriptionsSheet(isPresented: $showManage)
    }
}

struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirm = ""
    var body: some View {
        Form {
            Section {
                Text("Delete your account?").font(.title2.weight(.bold))
                Label("Your fax number is released and can be given to someone else", systemImage: "xmark")
                Label("All sent and received faxes are erased", systemImage: "xmark")
                Label("Delivery receipts and saved contacts are erased", systemImage: "xmark")
                Label("Unused pages from page packs are lost", systemImage: "xmark")
            }
            .foregroundStyle(Brand.failed)
            Section { NoteBox(text: "Deleting your account does not cancel your App Store subscription. Cancel it in iPhone Settings first.", kind: .warning) }
            Section("Type DELETE to confirm") {
                TextField("DELETE", text: $confirm).textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            Section {
                Button("Delete account permanently", role: .destructive) { model.deleteAccount() }
                    .disabled(confirm != "DELETE")
            }
        }
        .navigationTitle("Delete account")
    }
}

struct RetentionView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Keep faxes for", selection: $model.retentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                .pickerStyle(.inline)
            } footer: {
                Text("After this time faxes are erased from our servers. Delivery receipts are kept until you delete them.")
            }
            Section { Toggle("Require Face ID to open app", isOn: $model.requireFaceID) }
        }
        .navigationTitle("Privacy & data")
    }
}

struct NumbersView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Picker("Send faxes from", selection: $model.sendingNumberID) {
                    ForEach(model.numbers) { number in
                        VStack(alignment: .leading) {
                            PhoneText(number: number.number).font(.headline)
                            Text(verbatim: number.label).font(.footnote).foregroundStyle(.secondary)
                        }
                        .tag(Optional(number.id))
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("\(model.numbers.count) of \(model.plan?.numbersIncluded ?? 1) numbers")
            }
            Section {
                Button { showPaywall = true } label: { Label("Add a number", systemImage: "plus") }
            } footer: {
                Text("Enterprise includes 5 numbers.")
            }
        }
        .navigationTitle("Fax numbers")
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}

struct PauseReceivingView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 14
    var body: some View {
        Form {
            Section {
                Picker("Pause for", selection: $days) {
                    Text("1 week").tag(7)
                    Text("2 weeks").tag(14)
                    Text("1 month").tag(30)
                    Text("Until I turn it back on").tag(0)
                }
                .pickerStyle(.inline)
            } footer: {
                Text("While paused, senders get a busy signal and no pages are used. Your number stays yours.")
            }
            Section {
                if let until = model.pausedUntil {
                    Text("Paused until \(until.formatted(date: .abbreviated, time: .omitted))")
                    Button("Turn receiving back on") { model.pausedUntil = nil }
                } else {
                    Button("Pause receiving") {
                        model.pausedUntil = days == 0 ? .distantFuture : Calendar.current.date(byAdding: .day, value: days, to: .now)
                    }
                }
            }
        }
        .navigationTitle("Pause receiving")
    }
}

struct TeamView: View {
    @Environment(AppModel.self) private var model
    @State private var role = TeamMember.Role.member
    @State private var shared = true
    var body: some View {
        List {
            Section {
                ProgressView(value: Double(model.team.count), total: Double(model.plan?.teamSeats ?? 5)) {
                    Text("\(model.team.count) of \(model.plan?.teamSeats ?? 5) members")
                }
            }
            Section {
                ForEach(model.team) { member in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: member.name).font(.headline)
                            Text(verbatim: member.email).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(member.role == .admin ? "Admin" : member.role == .member ? "Member" : "Invited")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(member.role == .invited ? Brand.pending : .secondary)
                    }
                }
            }
            Section("Invite someone") {
                Picker("Role", selection: $role) {
                    Text("Member · send and receive").tag(TeamMember.Role.member)
                    Text("Admin · also manages the plan").tag(TeamMember.Role.admin)
                }
                ShareLink(item: URL(string: "https://faxlane.app/join/\(UUID().uuidString.prefix(8))")!) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Send it by WhatsApp, Messages or any app. The link works once and expires in 7 days.")
            }
            Section { Toggle("Shared team inbox", isOn: $shared) }
        }
        .navigationTitle("Team")
    }
}

struct HelpView: View {
    @Environment(AppModel.self) private var model
    private let faq: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("How do I know my fax was delivered?", "You get a notification and a receipt with the time and page count. Open the fax in Faxes → Sent."),
        ("Why did my fax fail?", "Usually the line was busy or the number isn’t a fax machine. Failed faxes never use your pages. Try again from Outbox."),
        ("Do received pages count?", "Yes. Pages you send and receive both count toward your plan. Blocked senders never use pages."),
        ("How do I cancel my plan?", "Plans are billed by Apple. Cancel in iPhone Settings → your name → Subscriptions."),
        ("How long are my faxes kept?", "On our servers, for as long as you choose in Settings → Keep faxes for. Turn on iCloud backup to keep your own copy.")
    ]
    var body: some View {
        List {
            Section("Common questions") {
                ForEach(faq.indices, id: \.self) { i in
                    DisclosureGroup { Text(faq[i].1).foregroundStyle(.secondary) } label: { Text(faq[i].0).fontWeight(.semibold) }
                }
            }
            Section {
                NavigationLink { SupportFormView() } label: { Label("Contact support", systemImage: "envelope") }
                NavigationLink { SupportFormView() } label: { Label("Report a problem", systemImage: "exclamationmark.bubble") }
            } footer: {
                Text(verbatim: model.remoteConfig.supportEmail)
            }
        }
        .navigationTitle("Help")
    }
}

/// Opens the user's Mail app addressed to support. No email service needed.
struct SupportFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var topic = 0
    @State private var message = ""
    @State private var includeDetails = true
    private let topics: [LocalizedStringKey] = ["Sending a fax", "Receiving", "Billing and plans", "My account", "Something else"]

    var body: some View {
        Form {
            Picker("Topic", selection: $topic) { ForEach(topics.indices, id: \.self) { Text(topics[$0]).tag($0) } }
            Section("Tell us what happened") {
                TextField("Describe the problem", text: $message, axis: .vertical).lineLimit(5...10)
            }
            Section {
                Toggle("Include app details", isOn: $includeDetails)
            } footer: {
                Text("Helps us fix it faster. No fax content is sent. We usually reply within 2 business days.")
            }
            Section {
                Button("Send message") { send() }.disabled(message.isEmpty)
            } footer: {
                Text(verbatim: model.remoteConfig.supportEmail)
            }
        }
        .navigationTitle("Contact support")
    }

    private func send() {
        var body = message
        if includeDetails {
            body += "\n\n—\nApp \(model.appVersion) · iOS \(UIDevice.current.systemVersion) · Account \(model.accountToken.uuidString.prefix(8))"
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = model.remoteConfig.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Faxlane support"), URLQueryItem(name: "body", value: body)]
        if let url = components.url { openURL(url) }
    }
}
