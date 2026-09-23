import ActivityKit
import Foundation

/// Shared between the app and the widget extension. Drives the Lock Screen
/// Live Activity and the Dynamic Island while a fax is being sent.
struct FaxActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case sending, delivered, failed }
        var phase: Phase
        var pagesSent: Int
        var totalPages: Int
        var failureReason: String?
    }

    var recipientName: String
    var recipientNumber: String
}
