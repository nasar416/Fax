import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: MainTabView.Tab
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let note = model.remoteConfig.announcement {
                    NoteBox(text: LocalizedStringKey(note))
                }
                Text("Send a fax\nin 30 seconds.").font(.display(36)).lineSpacing(-4)
                Button { selectedTab = .send } label: {
                    HStack {
                        Text("New fax").font(.title3.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.forward")
                            .font(.headline).foregroundStyle(Brand.blue)
                            .frame(width: 44, height: 44)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.leading, 22).padding(.trailing, 10)
                    .frame(height: 64)
                    .foregroundStyle(.white)
                    .background(Brand.blue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: selectedTab)
                pagesCard
                quickActions
                recent
            }
            .padding(20)
        }
        .background(Brand.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { UpgradeBanner() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .navigationDestination(for: Fax.self) { FaxDetailView(fax: $0) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            FaxlaneMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Faxlane").font(.display(20))
                if let number = model.faxNumber {
                    PhoneText(number: number).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("No fax number yet").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.plan == nil {
                Button { showPaywall = true } label: {
                    Label("Go Pro", systemImage: "bolt.fill").font(.footnote.weight(.bold))
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Color.primary, in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                }
            }
        }
    }

    private var pagesCard: some View {
        let total = model.plan == nil ? 3 : model.pageLimit
        let left = model.pagesLeft
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Group {
                    if model.plan == nil { Text("\(left) of \(total) free pages left") } else { Text("\(left) of \(total) pages left") }
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Get more") { showPaywall = true }.font(.footnote.weight(.bold))
            }
            ProgressView(value: Double(left), total: Double(max(total, 1)))
                .tint(Brand.blue)
            Group {
                if model.plan == nil { Text("One-time free pages to try the app") } else { Text("Sent and received pages both count") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            ForEach(QuickAction.all) { item in
                Button { selectedTab = .send } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: item.icon).font(.title3).foregroundStyle(Brand.blue)
                        Text(item.title).font(.subheadline).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        HStack {
            Text("Recent").font(.title3.weight(.semibold))
            Spacer()
            Button("See all") { selectedTab = .faxes }.font(.subheadline)
        }
        if model.recent.isEmpty {
            ContentUnavailableView("No faxes yet", systemImage: "printer",
                                   description: Text("Your sent and received faxes will show up here."))
        } else {
            VStack(spacing: 0) {
                ForEach(model.recent) { fax in
                    NavigationLink(value: fax) { FaxRow(fax: fax) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                    if fax.id != model.recent.last?.id { Divider().padding(.leading, 66) }
                }
            }
            .card(padding: 0)
        }
    }
}

/// One fax in a list.
struct FaxRow: View {
    let fax: Fax
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(fax.unread ? Brand.blue : .clear).frame(width: 8, height: 8)
            PageThumbnail()
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: fax.party).font(.body.weight(fax.unread ? .bold : .medium)).lineLimit(1)
                Text("\(fax.pages) pages · \(fax.date.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if fax.direction == .sent { StatusChip(state: fax.state) }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct QuickAction: Identifiable {
    let icon: String
    let title: LocalizedStringKey
    var id: String { icon }
    static let all = [QuickAction(icon: "doc.viewfinder", title: "Scan"),
                      QuickAction(icon: "doc", title: "Files"),
                      QuickAction(icon: "photo", title: "Photos")]
}
