import SwiftUI
import Contacts

struct ContactsView: View {
    @Environment(AppModel.self) private var model
    @State private var section = Section.all
    @State private var query = ""
    @State private var showImport = false
    @State private var showTeamSheet = false
    @State private var newBlock = ""

    enum Section: String, CaseIterable, Identifiable {
        case all, groups, team, blocked
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self { case .all: "All"; case .groups: "Groups"; case .team: "Team"; case .blocked: "Blocked" }
        }
    }

    var body: some View {
        List {
            SwiftUI.Section {
                Picker("Section", selection: $section) { ForEach(Section.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            switch section {
            case .all: allContacts
            case .groups: groups
            case .team: teamContacts
            case .blocked: blocked
            }
        }
        .navigationTitle("Contacts")
        .searchable(text: $query, prompt: "Search contacts")
        .sheet(isPresented: $showImport) { ContactsImportView() }
        .sheet(isPresented: $showTeamSheet) { TeamContactsSheet().presentationDetents([.medium]) }
        .onChange(of: section) { _, new in
            if new == .team && (model.plan ?? .basic).teamSeats < 5 { showTeamSheet = true }
        }
    }

    @ViewBuilder private var allContacts: some View {
        SwiftUI.Section {
            Button { showImport = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle.stack").font(.title3).foregroundStyle(Brand.lightBlue)
                        .frame(width: 44, height: 44).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading) {
                        Text("Import from your phone").font(.headline)
                        Text("Find fax numbers saved in your contacts").font(.caption).foregroundStyle(Brand.navyText)
                    }
                }
                .foregroundStyle(.white)
            }
            .listRowBackground(Brand.navy)
        }
        SwiftUI.Section {
            ForEach(model.contacts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { ContactRow(contact: $0) }
                .onDelete { model.contacts.remove(atOffsets: $0) }
        }
    }

    @ViewBuilder private var groups: some View {
        SwiftUI.Section {
            NoteBox(text: "Sending to a group uses pages for each recipient: a 2-page fax to 3 contacts uses 6 pages.", kind: .warning)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        SwiftUI.Section {
            ForEach(model.groups) { group in
                HStack {
                    Image(systemName: "person.3").foregroundStyle(Brand.blue).frame(width: 40, height: 40)
                        .background(Brand.blueSoft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading) {
                        Text(LocalizedStringKey(group.name)).font(.headline)
                        Text("\(group.memberIDs.count) contacts").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink { SendView() } label: { Label("Send", systemImage: "paperplane.fill") }
                        .fixedSize()
                }
            }
            Button { model.groups.append(ContactGroup(name: String(localized: "New group"), memberIDs: [])) } label: {
                Label("New group", systemImage: "plus")
            }
        }
    }

    @ViewBuilder private var teamContacts: some View {
        SwiftUI.Section {
            ContentUnavailableView("Team contacts", systemImage: "person.2",
                                   description: Text("Share one contact list with your team, so everyone sends to the right fax number."))
        }
    }

    @ViewBuilder private var blocked: some View {
        SwiftUI.Section {
            Label("Faxes from blocked numbers are rejected before they arrive, so they never use your pages.", systemImage: "hand.raised")
                .font(.footnote).foregroundStyle(.secondary)
        }
        SwiftUI.Section("Block a number") {
            HStack {
                TextField("+1 (555) 000-0000", text: $newBlock)
                    .keyboardType(.phonePad)
                    .environment(\.layoutDirection, .leftToRight)
                Button("Block") { model.block(newBlock); newBlock = "" }
                    .buttonStyle(.borderedProminent).tint(Brand.failed)
                    .disabled(newBlock.filter(\.isNumber).count < 6)
            }
        }
        SwiftUI.Section {
            ForEach(model.blocked) { item in
                VStack(alignment: .leading) {
                    PhoneText(number: item.number).font(.headline)
                    Text("Blocked \(item.blockedAt.formatted(date: .abbreviated, time: .omitted)) · \(item.reason)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .swipeActions { Button("Unblock") { model.unblock(item) }.tint(Brand.blue) }
            }
        } footer: {
            Text("You can also block a sender from any fax’s details.")
        }
    }
}

struct TeamContactsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundStyle(.white)
                .frame(width: 80, height: 80).background(Brand.blue, in: RoundedRectangle(cornerRadius: 22))
            Text("Team contacts").font(.title2.weight(.bold))
            Text("Share one contact list with your team, so everyone sends to the right fax number.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Included in Business and Enterprise").font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6).background(Brand.blueSoft, in: Capsule()).foregroundStyle(Brand.blue)
            Button("See Business plan") { showPaywall = true }.buttonStyle(.primary)
            Button("Not now") { dismiss() }.foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}

/// Reads fax numbers from the phone's contacts. Nothing is uploaded.
struct ContactsImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack.fill").font(.system(size: 56)).foregroundStyle(Brand.blue).padding(.top, 30)
            Text("Find fax numbers in your contacts").font(.display(28))
            VStack(alignment: .leading, spacing: 14) {
                Label("We only look for fax numbers", systemImage: "checkmark.circle.fill")
                Label("Your contacts stay on this phone. We never upload them", systemImage: "checkmark.circle.fill")
                Label("Change this any time in iPhone Settings", systemImage: "checkmark.circle.fill")
            }
            .foregroundStyle(Brand.delivered)
            if let status { Text(verbatim: status).font(.footnote).foregroundStyle(.secondary) }
            Spacer()
            Button("Allow access") { Task { await importFaxNumbers() } }.buttonStyle(.primary)
            Button("Not now") { dismiss() }.frame(maxWidth: .infinity).foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func importFaxNumbers() async {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else {
            status = String(localized: "Access was not allowed. You can turn it on in iPhone Settings.")
            return
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var found: [Contact] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                let label = phone.label ?? ""
                if label == CNLabelPhoneNumberWorkFax || label == CNLabelPhoneNumberHomeFax || label == CNLabelPhoneNumberOtherFax {
                    let name = contact.organizationName.isEmpty ? "\(contact.givenName) \(contact.familyName)" : contact.organizationName
                    found.append(Contact(name: name.trimmingCharacters(in: .whitespaces), faxNumber: phone.value.stringValue, fromPhone: true))
                }
            }
        }
        let existing = Set(model.contacts.map(\.faxNumber))
        model.contacts += found.filter { !existing.contains($0.faxNumber) }
        status = String(localized: "\(found.count) fax numbers found")
        if !found.isEmpty { dismiss() }
    }
}
