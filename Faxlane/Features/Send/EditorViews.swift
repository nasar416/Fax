import SwiftUI

/// Write a page of text that is sent as its own fax page.
struct TextPageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var plain = ""
    @State private var serif = true
    var onDone: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $plain)
                    .font(serif ? .system(.body, design: .serif) : .body)
                    .padding(20)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(20)
            }
            .background(Color(.systemGray5))
            .navigationTitle("Text page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add page") { onDone(plain); dismiss() }.disabled(plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Picker("Font", selection: $serif) {
                        Text("Serif").tag(true)
                        Text("Sans").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

struct CoverSheetView: View {
    @Binding var cover: CoverSheet
    var body: some View {
        Form {
            Section("From") { TextField("Your name or company", text: $cover.from) }
            Section("To") { TextField("Recipient name", text: $cover.to) }
            Section("Subject") { TextField("What is this fax about?", text: $cover.subject) }
            Section("Note") { TextField("Optional message", text: $cover.note, axis: .vertical).lineLimit(3...8) }
            Section { Toggle("Mark as urgent", isOn: $cover.urgent) }
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FAX").font(.system(.largeTitle, design: .serif).weight(.bold))
                    if cover.urgent { Text("URGENT").font(.caption.weight(.heavy)).foregroundStyle(.red) }
                    Divider()
                    Text("From: \(cover.from)").font(.system(.footnote, design: .serif))
                    Text("To: \(cover.to)").font(.system(.footnote, design: .serif))
                    Text("Subject: \(cover.subject)").font(.system(.footnote, design: .serif))
                    Text(verbatim: cover.note).font(.system(.footnote, design: .serif)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.black)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
        }
        .navigationTitle("Cover sheet")
    }
}
