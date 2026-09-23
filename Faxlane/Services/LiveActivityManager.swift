import ActivityKit
import Foundation

/// Lock Screen + Dynamic Island progress while a fax is sending. Updated locally by the app,
/// so no push server is needed for the first version.
@MainActor
final class LiveActivityManager {
    private var activity: Activity<FaxActivityAttributes>?

    func start(recipient: String, number: String, totalPages: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = FaxActivityAttributes(recipientName: recipient, recipientNumber: number)
        let state = FaxActivityAttributes.ContentState(phase: .sending, pagesSent: 0, totalPages: totalPages)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
    }

    func update(pagesSent: Int, total: Int) {
        guard let activity else { return }
        let state = FaxActivityAttributes.ContentState(phase: .sending, pagesSent: pagesSent, totalPages: total)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func finish(delivered: Bool, total: Int, reason: String? = nil) {
        guard let activity else { return }
        let state = FaxActivityAttributes.ContentState(phase: delivered ? .delivered : .failed,
                                                       pagesSent: delivered ? total : 0,
                                                       totalPages: total, failureReason: reason)
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(4))) }
        self.activity = nil
    }
}
