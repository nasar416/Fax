import SwiftUI
import UserNotifications

struct AppLanguage: Identifiable, Hashable {
    let code: String
    let native: String
    let english: String
    var id: String { code }
    static let all: [AppLanguage] = [
        .init(code: "en", native: "English", english: "English"),
        .init(code: "ar", native: "العربية", english: "Arabic"),
        .init(code: "cs", native: "Čeština", english: "Czech"),
        .init(code: "nl", native: "Nederlands", english: "Dutch"),
        .init(code: "fr", native: "Français", english: "French"),
        .init(code: "de", native: "Deutsch", english: "German"),
        .init(code: "he", native: "עברית", english: "Hebrew"),
        .init(code: "id", native: "Bahasa Indonesia", english: "Indonesian"),
        .init(code: "it", native: "Italiano", english: "Italian"),
        .init(code: "ja", native: "日本語", english: "Japanese"),
        .init(code: "ko", native: "한국어", english: "Korean"),
        .init(code: "fa", native: "فارسی", english: "Persian"),
        .init(code: "pl", native: "Polski", english: "Polish"),
        .init(code: "pt", native: "Português", english: "Portuguese"),
        .init(code: "ru", native: "Русский", english: "Russian"),
        .init(code: "zh-Hans", native: "简体中文", english: "Simplified Chinese"),
        .init(code: "es", native: "Español", english: "Spanish"),
        .init(code: "zh-Hant", native: "繁體中文", english: "Traditional Chinese"),
        .init(code: "tr", native: "Türkçe", english: "Turkish"),
        .init(code: "vi", native: "Tiếng Việt", english: "Vietnamese")
    ]
    static var current: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return all.first { preferred.hasPrefix($0.code) }?.code ?? "en"
    }
}

/// iOS switches an app's language from Settings → Faxlane → Language.
/// Picking a different language here opens that screen.
struct LanguageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var selected = AppLanguage.current
    @State private var query = ""
    var embedded = false

    private var filtered: [AppLanguage] {
        query.isEmpty ? AppLanguage.all : AppLanguage.all.filter {
            $0.native.localizedCaseInsensitiveContains(query) || $0.english.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !embedded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        FaxlaneMark(size: 44)
                        Text(verbatim: "Faxlane").font(.display(22))
                    }
                    Text("Choose your language").font(.display(32))
                    Text("20 languages. You can change this later in Settings.").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
            }
            List(filtered) { lang in
                Button { selected = lang.code } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: lang.native).font(.body.weight(.semibold))
                            Text(verbatim: lang.english).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selected == lang.code {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search languages")
            Button(selected == AppLanguage.current ? LocalizedStringKey("Continue") : LocalizedStringKey("Switch language in Settings")) {
                if selected != AppLanguage.current, let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                } else if !embedded {
                    withAnimation { model.stage = .onboarding }
                }
            }
            .buttonStyle(.primary)
            .padding(20)
        }
        .background(Brand.background)
        .navigationTitle(embedded ? String(localized: "Language") : "")
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var askNotifications = false

    private let pages: [(icon: String, title: LocalizedStringKey, body: LocalizedStringKey)] = [
        ("doc.viewfinder", "Scan any paper in seconds", "Point your camera at a page. Faxlane finds the edges and makes it crisp and readable."),
        ("globe.americas", "Fax anywhere in the world", "Send to fax machines in over 100 countries straight from your iPhone. No machine, no phone line."),
        ("checkmark.seal", "Know it arrived", "Follow every page as it sends and get a delivery receipt you can share.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { askNotifications = true }.foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 8)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: pages[i].icon)
                            .font(.system(size: 88, weight: .regular))
                            .foregroundStyle(Brand.blue)
                            .frame(width: 220, height: 220)
                            .background(Brand.blueSoft, in: RoundedRectangle(cornerRadius: 48, style: .continuous))
                            .symbolEffect(.bounce, value: page)
                        Text(pages[i].title).font(.display(32)).multilineTextAlignment(.center)
                        Text(pages[i].body).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button(page < pages.count - 1 ? LocalizedStringKey("Continue") : LocalizedStringKey("Get started")) {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { askNotifications = true }
            }
            .buttonStyle(.primary)
            .padding(20)
        }
        .background(Brand.background)
        .sheet(isPresented: $askNotifications) { NotificationPrimerView() }
    }
}

struct NotificationPrimerView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(Brand.blue)
                .symbolEffect(.pulse, options: .repeating)
            Text("Know the moment your fax arrives").font(.display(28)).multilineTextAlignment(.center)
            Text("We only notify you about deliveries, failures and new faxes. Nothing else.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Turn on notifications") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                    model.finishOnboarding()
                }
            }
            .buttonStyle(.primary)
            Button("Not now") { model.finishOnboarding() }.foregroundStyle(.secondary)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}

struct RestoredView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Brand.blue)
                .symbolEffect(.bounce, value: appeared)
                .padding(.top, 40)
            Text("Welcome back").font(.display(34))
            Text("We found your account and brought it back. No sign-in needed.").foregroundStyle(.secondary)
            VStack(spacing: 0) {
                row("phone", "Fax number", value: model.faxNumber ?? String(localized: "None yet"))
                Divider()
                row("bolt", "Plan", value: model.plan.map { _ in String(localized: "Active") } ?? String(localized: "Free"))
                Divider()
                row("doc", "Pages left", value: "\(model.pagesLeft)")
                Divider()
                row("clock.arrow.circlepath", "Fax history", value: String(localized: "\(model.faxes.count) faxes"))
            }
            .card(padding: 0)
            Label("Restored with iCloud Keychain and your App Store purchase.", systemImage: "lock")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Continue") { model.finishOnboarding() }.buttonStyle(.primary)
            Button("Not your account? Start fresh") { withAnimation { model.stage = .onboarding } }
                .frame(maxWidth: .infinity).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Brand.background)
        .onAppear { appeared = true }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.blue).frame(width: 34, height: 34)
                .background(Brand.blueSoft, in: RoundedRectangle(cornerRadius: 10))
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).fontWeight(.semibold)
            Image(systemName: "checkmark").foregroundStyle(Brand.delivered)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}
