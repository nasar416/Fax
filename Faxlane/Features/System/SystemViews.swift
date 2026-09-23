import SwiftUI

struct ForceUpdateView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            FaxlaneMark(size: 96)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline).foregroundStyle(Brand.blue)
                        .frame(width: 38, height: 38)
                        .background(Brand.card, in: Circle())
                        .offset(x: 8, y: 8)
                        .symbolEffect(.pulse, options: .repeating)
                }
            Text("Time to update Faxlane").font(.display(30)).multilineTextAlignment(.center)
            Text("This version can’t send or receive faxes anymore. The update takes a minute and keeps all your faxes and pages.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Update in the App Store") {
                // Replace with your App Store ID once the app is live.
                if let url = URL(string: "itms-apps://apps.apple.com/app/id0000000000") { openURL(url) }
            }
            .buttonStyle(.primary)
        }
        .padding(24)
        .background(Brand.background)
    }
}

struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 44))
                .foregroundStyle(Brand.pending)
                .frame(width: 120, height: 120)
                .background(Brand.pendingBg, in: Circle())
            Text("Sending is paused for a moment").font(.display(26)).multilineTextAlignment(.center)
            Text("Our fax network is under maintenance. Your faxes wait safely in Outbox and go out as soon as we’re back.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 0) {
                statusRow("Sending", value: model.remoteConfig.maintenanceBackAround.map { "Back around \($0)" } ?? String(localized: "Paused"), color: Brand.pending)
                Divider()
                statusRow("Receiving", value: String(localized: "Working normally"), color: Brand.delivered)
                Divider()
                statusRow("Your Outbox", value: String(localized: "\(model.outbox.count) waiting · no pages used yet"), color: Brand.blue)
            }
            .card(padding: 0)
            Spacer()
        }
        .padding(20)
        .background(Brand.background)
    }

    private func statusRow(_ title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).fontWeight(.semibold)
            Spacer()
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }
}
