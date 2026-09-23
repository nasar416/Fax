import SwiftUI

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var period = BillingPeriod.annual
    @State private var tier = PlanTier.premium

    private var tiers: [PlanTier] { PlanTier.allCases.filter { $0.periods.contains(period) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Billing period", selection: $period) {
                        ForEach(BillingPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(tiers) { plan in
                        PlanCard(tier: plan, period: period, selected: plan == tier) { tier = plan }
                    }
                    if period == .weekly {
                        Text("Business and Enterprise plans are billed monthly or annually.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    NoteBox(text: "Pages you send and pages you receive both count toward your plan. Faxes from blocked numbers never use pages.")
                }
                .padding(20)
            }
            .background(Brand.background)
            .navigationTitle("Choose your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { footer }
            .onChange(of: period) { _, new in if !tier.periods.contains(new) { tier = .premium } }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    if await store.purchase(tier.productID(period)) {
                        model.plan = tier
                        model.period = period
                        dismiss()
                    }
                }
            } label: {
                if store.isPurchasing { ProgressView().tint(.white) }
                else if period == .weekly { Text("Start 3-day free trial") }
                else { Text("Subscribe to \(Text(tier.name))") }
            }
            .buttonStyle(.primary)
            if let error = store.lastError { Text(verbatim: error).font(.caption).foregroundStyle(Brand.failed) }
            Text("\(tier.pages(for: period)) pages per \(period == .weekly ? String(localized: "week") : String(localized: "month")), sent and received. Unused pages do not roll over. Auto-renews, cancel anytime in Settings.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://sites.google.com/view/faxlaneprivacypolicy/home")!)
                Button("Restore") { Task { await store.restore() } }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(.bar)
    }
}

private struct PlanCard: View {
    @Environment(StoreManager.self) private var store
    let tier: PlanTier
    let period: BillingPeriod
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Brand.blue : Color(.systemGray3)).font(.title3)
                    Text(tier.name).font(.display(22))
                    Spacer()
                    Text(verbatim: store.price(for: tier.productID(period), fallback: tier.fallbackPrice(period)))
                        .font(.headline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Text(tier.tag).font(.caption.weight(.semibold)).foregroundStyle(tier == .premium ? Brand.blue : .secondary)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                    Label("\(tier.pages(for: period)) pages", systemImage: "doc.fill").font(.subheadline.weight(.bold))
                    ForEach(Array(tier.extras.enumerated()), id: \.offset) { _, extra in
                        Label(extra, systemImage: "checkmark").font(.subheadline)
                    }
                }
                .labelStyle(.titleAndIcon)
            }
            .padding(16)
            .background(selected ? Brand.blueSoft : Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Brand.blue : Color(.separator), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct TopUpView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pack = PagePack.all[1]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("You’re almost out of pages").font(.title3.weight(.bold))
                    Text("\(model.pagesLeft) pages left. Add a page pack now or upgrade your plan.").foregroundStyle(.secondary)
                }
                Section("Page packs · never expire") {
                    Picker("Pack", selection: $pack) {
                        ForEach(PagePack.all) { p in
                            Text("\(p.pages) pages · \(store.price(for: p.productID, fallback: p.fallbackPrice))").tag(p)
                        }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }
            .navigationTitle("Add pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Buy \(pack.pages) pages") {
                    Task {
                        if await store.purchase(pack.productID) {
                            if model.api == nil { model.extraPages += pack.pages } // with a server, the synced account already has them
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.primary).padding(20)
            }
        }
    }
}

/// Shown when a subscription ends: the number is held for 14 days.
struct NumberGraceView: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("We’re holding your fax number").font(.display(26))
                    Text("Your plan has ended. We keep this number for you for 14 days so you can renew.").foregroundStyle(.secondary)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    PhoneText(number: model.numbers.first?.number ?? "").font(.title2.weight(.semibold))
                    ProgressView(value: 9, total: 14).tint(Brand.lightBlue)
                    Text("9 days left").font(.footnote.weight(.semibold)).foregroundStyle(Brand.lightBlue)
                }
                .foregroundStyle(.white)
                .listRowBackground(Brand.navy)
            }
            Section {
                Label("Faxes sent to this number are saved. Open them after you renew.", systemImage: "checkmark.circle").foregroundStyle(Brand.delivered)
                Label("Sending is paused", systemImage: "pause.circle").foregroundStyle(Brand.pending)
                Label("After 14 days the number is released and may go to someone else", systemImage: "exclamationmark.circle").foregroundStyle(Brand.failed)
            }
            Section { NoteBox(text: "Payment problem? Update your payment method in App Store settings and your plan comes back right away.") }
        }
        .navigationTitle("Number on hold")
        .safeAreaInset(edge: .bottom) {
            Button("Renew and keep this number") { showPaywall = true }.buttonStyle(.primary).padding(20)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}

/// Shown before cancelling: offers a cheaper option, then links to Apple's subscription page.
struct WinBackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showManage = false
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "gift").font(.system(size: 56)).foregroundStyle(Brand.blue)
            Text("Before you go").font(.display(30))
            Text("Switch to Basic and keep your fax number for less. You keep your history and contacts.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Switch to Basic") { dismiss() }.buttonStyle(.primary)
            Button("Continue to cancel") { showManage = true }.foregroundStyle(.secondary)
        }
        .padding(24)
        .manageSubscriptionsSheet(isPresented: $showManage)
    }
}
