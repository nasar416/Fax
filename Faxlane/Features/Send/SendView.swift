import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SendView: View {
    @Environment(AppModel.self) private var model
    @State private var country = Country.all[0]
    @State private var number = ""
    @State private var recipientName = ""
    @State private var pages: [DraftPage] = []
    @State private var cover = CoverSheet()

    @State private var showContacts = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var showTextEditor = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var goReview = false

    private var cost: Int { model.cost(pages: max(pages.count, 1), cover: cover.enabled, country: country) }
    private var canContinue: Bool { number.filter(\.isNumber).count >= 6 && !pages.isEmpty }

    var body: some View {
        Form {
            Section("To") {
                HStack {
                    Menu {
                        Picker("Country", selection: $country) {
                            ForEach(Country.all) { c in
                                Text(verbatim: "\(c.flag) \(c.name) \(c.dial)").tag(c)
                            }
                        }
                    } label: {
                        Text(verbatim: "\(country.flag) \(country.dial)").monospacedDigit()
                    }
                    TextField("Fax number", text: $number)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .environment(\.layoutDirection, .leftToRight)
                    Button { showContacts = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Choose from contacts")
                }
                if !recipientName.isEmpty {
                    Label { Text(verbatim: recipientName) } icon: { Image(systemName: "person.fill") }
                        .foregroundStyle(.secondary)
                }
                if country.pageMultiplier > 1 {
                    Text("Each page to \(country.name) counts as \(country.pageMultiplier) pages.").font(.footnote).foregroundStyle(Brand.pending)
                }
            }

            Section {
                ForEach(pages) { page in
                    HStack(spacing: 12) {
                        if let image = page.image {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 40, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            PageThumbnail()
                        }
                        Text(verbatim: page.title).lineLimit(1)
                    }
                }
                .onDelete { pages.remove(atOffsets: $0) }
                .onMove { pages.move(fromOffsets: $0, toOffset: $1) }

                Menu {
                    Button { showScanner = true } label: { Label("Scan with camera", systemImage: "doc.viewfinder") }
                    PhotosPicker(selection: $photoItems, matching: .images) { Label("Photos", systemImage: "photo") }
                    Button { showFiles = true } label: { Label("Files, iCloud Drive, Google Drive, Dropbox", systemImage: "folder") }
                    Button { showTextEditor = true } label: { Label("Write a page", systemImage: "text.alignleft") }
                } label: {
                    Label("Add pages", systemImage: "plus.circle.fill").font(.headline)
                }
            } header: {
                Text("Pages")
            } footer: {
                Text("Files opens every storage app you have, including iCloud Drive, Google Drive, Dropbox and Box.")
            }

            Section {
                Toggle("Add a cover sheet", isOn: $cover.enabled)
                if cover.enabled {
                    NavigationLink("Edit cover sheet") { CoverSheetView(cover: $cover) }
                }
            }

            Section {
                HStack {
                    Text("Uses \(cost) pages")
                    Spacer()
                    Text("\(model.pagesLeft) left").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("New fax")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(pages.isEmpty) }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Review") { goReview = true }
                .buttonStyle(.primary)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
                .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationDestination(isPresented: $goReview) {
            ReviewView(recipientName: recipientName.isEmpty ? "\(country.dial) \(number)" : recipientName,
                       number: "\(country.dial) \(number)", pages: pages, cover: cover, cost: cost)
        }
        .sheet(isPresented: $showContacts) {
            RecipientPickerView { contact in
                recipientName = contact.name
                number = contact.faxNumber.replacingOccurrences(of: "+1 ", with: "")
                country = Country.all[0]
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView { images in
                pages += images.enumerated().map { DraftPage(source: .scan, image: $0.element, title: String(localized: "Scanned page \($0.offset + 1)")) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                pages += urls.map { DraftPage(source: .file($0), title: $0.lastPathComponent) }
            }
        }
        .sheet(isPresented: $showTextEditor) {
            TextPageEditorView { text in pages.append(DraftPage(source: .text(text), title: String(localized: "Text page"))) }
        }
        .onChange(of: photoItems) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        pages.append(DraftPage(source: .photo, image: image, title: String(localized: "Photo")))
                    }
                }
                photoItems = []
            }
        }
    }
}

struct RecipientPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var onPick: (Contact) -> Void

    var body: some View {
        NavigationStack {
            List(model.contacts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { contact in
                Button {
                    onPick(contact); dismiss()
                } label: {
                    ContactRow(contact: contact)
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $query, prompt: "Search contacts")
            .navigationTitle("Choose recipient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ContactRow: View {
    let contact: Contact
    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: contact.initials)
                .font(.subheadline.weight(.bold)).foregroundStyle(Brand.blue)
                .frame(width: 42, height: 42).background(Brand.blueSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: contact.name).font(.body.weight(.semibold))
                PhoneText(number: contact.faxNumber).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if contact.fromPhone {
                Text("From phone").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }
}
