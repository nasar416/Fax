import SwiftUI
import PencilKit

struct FaxDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let fax: Fax
    @State private var showSign = false
    @State private var showReply = false
    @State private var confirmBlock = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: fax.state == .failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.title).foregroundStyle(fax.state.tint)
                    VStack(alignment: .leading) {
                        Text(fax.state.label).font(.headline)
                        Text(fax.direction == .received ? "All \(fax.pages) pages received" : "\(fax.pagesSent) of \(fax.pages) pages delivered")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(fax.state.tintBackground)
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(1...max(fax.pages, 1), id: \.self) { page in
                            PageThumbnail(width: 110).overlay(alignment: .bottomTrailing) {
                                Text(verbatim: "\(page)").font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(8)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            Section {
                LabeledContent(fax.direction == .received ? "From" : "To") { PhoneText(number: fax.number) }
                LabeledContent("Pages", value: "\(fax.pages)")
                LabeledContent("Date", value: fax.date.formatted(date: .abbreviated, time: .shortened))
                if let reason = fax.failureReason { LabeledContent("Reason", value: reason) }
                LabeledContent("Reference", value: String(fax.id.uuidString.prefix(8)))
            }
            Section {
                if fax.direction == .received {
                    Button { showSign = true } label: { Label("Sign & fill", systemImage: "pencil.and.scribble") }
                    Button { showReply = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                }
                Button { showReply = true } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                Button { printFax() } label: { Label("Print", systemImage: "printer") }
                ShareLink(item: receiptText) { Label("Share or save to Files", systemImage: "square.and.arrow.up") }
            }
            Section {
                if fax.direction == .received {
                    Button(role: .destructive) { confirmBlock = true } label: { Label("Block this sender", systemImage: "hand.raised") }
                }
                Button(role: .destructive) { model.moveToTrash(fax); dismiss() } label: { Label("Move to Trash", systemImage: "trash") }
            }
        }
        .navigationTitle(Text(verbatim: fax.party))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.markRead(fax) }
        .fullScreenCover(isPresented: $showSign) { SignFaxView(fax: fax) }
        .sheet(isPresented: $showReply) { NavigationStack { SendView() } }
        .confirmationDialog("Block this sender?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { model.block(fax.number) }
        } message: {
            Text("Faxes from blocked numbers are rejected before they arrive, so they never use your pages.")
        }
    }

    private var receiptText: String {
        "Faxlane · \(fax.party) · \(fax.number) · \(fax.pages) pages · \(fax.date.formatted())"
    }

    private func printFax() {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = fax.party
        controller.printInfo = info
        controller.printFormatter = UISimpleTextPrintFormatter(text: receiptText)
        controller.present(animated: true)
    }
}

/// Fill in and sign a received form with finger or Apple Pencil, then fax it back.
struct SignFaxView: View {
    @Environment(\.dismiss) private var dismiss
    let fax: Fax
    @State private var canvas = PKCanvasView()
    @State private var showReply = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGray5).ignoresSafeArea()
                ZStack {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Page 1").font(.system(.headline, design: .serif))
                        ForEach(0..<14, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(Color(.systemGray4)).frame(height: 5)
                                .frame(maxWidth: i % 3 == 2 ? 180 : .infinity, alignment: .leading)
                        }
                        Spacer()
                        Text("Signature").font(.caption).foregroundStyle(.gray)
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Brand.blue).frame(height: 70)
                    }
                    .padding(24)
                    CanvasRepresentable(canvas: $canvas)
                }
                .background(Color.white)
                .aspectRatio(8.5 / 11, contentMode: .fit)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(16)
            }
            .navigationTitle("Sign & fill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { canvas.drawing = PKDrawing() } label: { Image(systemName: "eraser") }.accessibilityLabel("Clear")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showReply = true } label: {
                        Label("Fax it back to the sender", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showReply) { NavigationStack { SendView() } }
        }
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: UIColor(hex: 0x0B1F44), width: 3)
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

/// A fax that arrived while the user had no pages left.
struct LockedFaxView: View {
    @Environment(AppModel.self) private var model
    @Environment(StoreManager.self) private var store
    let fax: Fax
    @State private var pack = PagePack.all[1]
    @State private var showPaywall = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    PageThumbnail(width: 64).blur(radius: 1.5).overlay {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(Color.primary, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: fax.party).font(.headline)
                        Text("\(fax.pages) pages").font(.footnote).foregroundStyle(.secondary)
                        Label("Locked", systemImage: "lock").font(.caption.weight(.semibold)).foregroundStyle(Brand.pending)
                    }
                }
            }
            Section {
                Text("You’ve used all your pages this month").font(.title3.weight(.bold))
                Text("This fax arrived safely and we’re keeping it for you. Add pages to open it now, or it opens on its own when your plan renews.")
                    .foregroundStyle(.secondary)
            }
            Section("Add pages") {
                Picker("Page pack", selection: $pack) {
                    ForEach(PagePack.all) { p in
                        Text("\(p.pages) pages · \(store.price(for: p.productID, fallback: p.fallbackPrice))").tag(p)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("New fax received")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button("Add \(pack.pages) pages and open fax") {
                    Task { await store.purchase(pack.productID, accountToken: model.accountToken) }
                }
                .buttonStyle(.primary)
                Button("Or upgrade to Business · 700 pages a month") { showPaywall = true }.font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}
