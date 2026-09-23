import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    let recipientName: String
    let number: String
    let pages: [DraftPage]
    let cover: CoverSheet
    let cost: Int
    @State private var goStatus = false
    @State private var showTopUp = false

    var body: some View {
        List {
            Section("To") {
                LabeledContent { PhoneText(number: number) } label: { Text(verbatim: recipientName) }
            }
            Section("Pages") {
                LabeledContent("Pages", value: "\(pages.count + (cover.enabled ? 1 : 0))")
                LabeledContent("Cover sheet") { Text(cover.enabled ? LocalizedStringKey("Yes") : LocalizedStringKey("No")) }
            }
            Section {
                LabeledContent("Uses", value: String(localized: "\(cost) pages"))
                LabeledContent("Left after sending", value: "\(max(model.pagesLeft - cost, 0))")
            } footer: {
                Text("Failed faxes never use your pages.")
            }
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom) {
            Button {
                if model.pagesLeft < cost { showTopUp = true; return }
                model.send(recipient: recipientName, number: number, pages: pages, cover: cover, cost: cost)
                goStatus = true
            } label: {
                Label("Send fax", systemImage: "paperplane.fill")
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationDestination(isPresented: $goStatus) { SendingStatusView() }
        .sheet(isPresented: $showTopUp) { TopUpView() }
    }
}

struct SendingStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            if let job = model.activeSend {
                Spacer()
                switch job.phase {
                case .dialing, .sending:
                    ZStack {
                        Circle().stroke(Brand.blueSoft, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: CGFloat(job.pagesSent) / CGFloat(max(job.totalPages, 1)))
                            .stroke(Brand.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: job.pagesSent)
                        VStack {
                            Text(verbatim: "\(job.pagesSent)/\(job.totalPages)").font(.display(40)).contentTransition(.numericText())
                            Text("pages").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 200, height: 200)
                    Text(job.phase == .dialing ? LocalizedStringKey("Calling the fax machine…") : LocalizedStringKey("Sending your fax…")).font(.title2.weight(.bold))
                    Text("You can leave this screen. Follow progress on your Lock Screen.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .delivered:
                    ResultView(success: true, title: "Delivered", message: "All \(job.totalPages) pages reached \(job.number).")
                case .failed(let reason):
                    ResultView(success: false, title: "Fax not sent", message: LocalizedStringKey(reason))
                }
                Spacer()
                if job.phase == .delivered {
                    ShareLink(item: "Faxlane delivery receipt: \(job.totalPages) pages to \(job.number), \(Date.now.formatted())") {
                        Label("Share receipt", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.secondary)
                }
                Button("Done") { dismiss() }.buttonStyle(.primary)
            }
        }
        .padding(20)
        .navigationBarBackButtonHidden(model.activeSend.map { $0.phase == .dialing || $0.phase == .sending } ?? false)
        .sensoryFeedback(trigger: model.activeSend?.phase) { _, new in
            switch new {
            case .some(.delivered): .success
            case .some(.failed): .error
            default: nil
            }
        }
    }
}

private struct ResultView: View {
    let success: Bool
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @State private var shown = false
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(success ? Brand.delivered : Brand.failed)
                .symbolEffect(.bounce, value: shown)
            Text(title).font(.display(32))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .onAppear { shown = true }
    }
}
