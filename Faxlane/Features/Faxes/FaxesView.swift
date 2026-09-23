import SwiftUI

struct FaxesView: View {
    @Environment(AppModel.self) private var model
    @State private var folder = Folder.inbox
    @State private var query = ""
    @State private var selection = Set<Fax.ID>()
    @State private var editMode = EditMode.inactive
    @State private var showPaywall = false
    @State private var confirmEmpty = false

    enum Folder: String, CaseIterable, Identifiable {
        case inbox, sent, outbox, trash
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self { case .inbox: "Inbox"; case .sent: "Sent"; case .outbox: "Outbox"; case .trash: "Trash" }
        }
    }

    private var items: [Fax] {
        let base: [Fax]
        switch folder {
        case .inbox: base = model.inbox
        case .sent: base = model.sent
        case .outbox: base = model.outbox
        case .trash: base = model.trash
        }
        guard !query.isEmpty else { return base }
        return base.filter { $0.party.localizedCaseInsensitiveContains(query) || $0.number.contains(query) }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("Folder", selection: $folder) {
                    ForEach(Folder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if folder == .inbox, let number = model.faxNumber {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Faxes sent to this number land here").font(.caption).foregroundStyle(Brand.navyText)
                            PhoneText(number: number).font(.title3.weight(.semibold))
                        }
                        Spacer()
                        Button { UIPasteboard.general.string = number } label: { Image(systemName: "doc.on.doc") }
                            .accessibilityLabel("Copy fax number")
                            .buttonStyle(.borderless)
                            .foregroundStyle(.white)
                    }
                    .foregroundStyle(.white)
                    .listRowBackground(Brand.navy)
                }
            }

            content
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Faxes")
        .searchable(text: $query, prompt: "Search name, number or date")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty && folder != .outbox { EditButton() }
            }
            if editMode.isEditing && !selection.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    ShareLink(item: selectedSummary) { Label("Share", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button { selectedFaxes.forEach(model.markRead); selection = [] } label: { Label("Mark read", systemImage: "envelope.open") }
                    Spacer()
                    Button(role: .destructive) { selectedFaxes.forEach(model.moveToTrash); selection = [] } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationDestination(for: Fax.self) { fax in
            if fax.state == .locked { LockedFaxView(fax: fax) } else { FaxDetailView(fax: fax) }
        }
        .safeAreaInset(edge: .bottom) { if folder != .inbox { UpgradeBanner() } }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .confirmationDialog("Erase everything in Trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        }
        .refreshable { try? await Task.sleep(for: .seconds(1)) }
    }

    private var selectedFaxes: [Fax] { items.filter { selection.contains($0.id) } }
    private var selectedSummary: String { selectedFaxes.map(\.party).joined(separator: ", ") }

    @ViewBuilder private var content: some View {
        if folder == .inbox && model.faxNumber == nil {
            Section {
                ContentUnavailableView {
                    Label("Get a number to receive faxes", systemImage: "number")
                } description: {
                    Text("With your own fax number, faxes sent to you land right here. Sending already works without one.")
                } actions: {
                    Button("Choose your number") { showPaywall = true }.buttonStyle(.borderedProminent)
                }
            }
        } else if items.isEmpty {
            Section { ContentUnavailableView("Nothing here", systemImage: "tray") }
        } else {
            switch folder {
            case .outbox:
                Section {
                    ForEach(items) { OutboxRow(fax: $0) }
                } footer: {
                    Text("Outbox faxes send on their own. A fax that fails doesn’t use your pages.")
                }
            case .trash:
                Section {
                    ForEach(items) { fax in
                        HStack {
                            FaxRow(fax: fax).opacity(0.6)
                            Button("Restore") { model.restore(fax) }.buttonStyle(.bordered)
                        }
                    }
                } header: {
                    HStack {
                        Text("Deleted faxes stay here for 30 days, then they’re erased for good.")
                        Spacer()
                        Button("Empty", role: .destructive) { confirmEmpty = true }.font(.caption.weight(.semibold))
                    }
                    .textCase(nil)
                }
            default:
                Section {
                    ForEach(items) { fax in
                        NavigationLink(value: fax) { FaxRow(fax: fax) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { model.moveToTrash(fax) } label: { Label("Delete", systemImage: "trash") }
                                Button { model.block(fax.number) } label: { Label("Block", systemImage: "hand.raised") }.tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                if fax.unread {
                                    Button { model.markRead(fax) } label: { Label("Read", systemImage: "envelope.open") }.tint(Brand.blue)
                                }
                            }
                            .contextMenu {
                                Button { model.markRead(fax) } label: { Label("Mark read", systemImage: "envelope.open") }
                                Button { model.block(fax.number) } label: { Label("Block sender", systemImage: "hand.raised") }
                                Button(role: .destructive) { model.moveToTrash(fax) } label: { Label("Move to Trash", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }
}

private struct OutboxRow: View {
    @Environment(AppModel.self) private var model
    let fax: Fax
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PageThumbnail()
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: fax.party).font(.body.weight(.semibold))
                    switch fax.state {
                    case .sending: Text("Sending · page \(fax.pagesSent) of \(fax.pages)").font(.footnote).foregroundStyle(Brand.pending)
                    case .queued: Label("Queued · starts after the current fax", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                    default: Label("Waiting for internet connection", systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if fax.state == .offline { Button("Retry") { model.retry(fax) }.buttonStyle(.bordered) }
            }
            if fax.state == .sending {
                ProgressView(value: Double(fax.pagesSent), total: Double(fax.pages)).tint(Brand.blue)
            }
        }
    }
}
