import ActivityKit
import SwiftUI
import WidgetKit

private let brandBlue = Color(red: 26 / 255, green: 86 / 255, blue: 219 / 255)
private let lightBlue = Color(red: 127 / 255, green: 176 / 255, blue: 1)

/// Lock Screen banner and Dynamic Island while a fax is sending.
struct FaxLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FaxActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "doc.fill").font(.title2).foregroundStyle(lightBlue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: "\(context.state.pagesSent)/\(context.state.totalPages)")
                        .font(.title2.weight(.bold)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(verbatim: context.attributes.recipientName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(context.state.pagesSent), total: Double(max(context.state.totalPages, 1)))
                            .tint(lightBlue)
                        StatusLine(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "doc.fill").foregroundStyle(lightBlue)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                ProgressView(value: Double(context.state.pagesSent), total: Double(max(context.state.totalPages, 1)))
                    .progressViewStyle(.circular)
                    .tint(context.state.phase == .failed ? .red : lightBlue)
            }
            .keylineTint(brandBlue)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<FaxActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(brandBlue, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sending to \(context.attributes.recipientName)").font(.subheadline.weight(.bold)).lineLimit(1)
                    StatusLine(state: context.state)
                }
                Spacer()
                Text(verbatim: "\(context.state.pagesSent)/\(context.state.totalPages)").font(.title2.weight(.bold)).monospacedDigit()
            }
            ProgressView(value: Double(context.state.pagesSent), total: Double(max(context.state.totalPages, 1)))
                .tint(lightBlue)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct StatusLine: View {
    let state: FaxActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .sending: Text("Sending page \(min(state.pagesSent + 1, state.totalPages))").font(.caption).foregroundStyle(.secondary)
        case .delivered: Label("Delivered · \(state.totalPages) pages", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed: Label(state.failureReason ?? String(localized: "Line busy · tap to retry"), systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red)
        }
    }
}

private struct CompactTrailing: View {
    let state: FaxActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case .sending: Text(verbatim: "\(state.pagesSent)/\(state.totalPages)").monospacedDigit().font(.caption.weight(.bold))
        case .delivered: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}
