import Foundation

/// Talks to the Faxlane backend. The backend holds the Telnyx API key and sends,
/// receives and stores faxes. Never put the Telnyx key inside the app.
protocol FaxService: Sendable {
    /// Sends a fax and reports progress page by page.
    func send(to number: String, pages: [DraftPage], cover: CoverSheet) -> AsyncThrowingStream<FaxProgress, Error>
}

enum FaxProgress: Sendable {
    case dialing
    case sentPage(Int, of: Int)
    case delivered
}

struct FaxSendError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// Simulated service used until the backend is ready (and in SwiftUI previews).
struct MockFaxService: FaxService {
    var failureRate: Double = 0

    func send(to number: String, pages: [DraftPage], cover: CoverSheet) -> AsyncThrowingStream<FaxProgress, Error> {
        let total = max(pages.count + (cover.enabled ? 1 : 0), 1)
        let shouldFail = Double.random(in: 0...1) < failureRate
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.dialing)
                try await Task.sleep(for: .seconds(1.2))
                for page in 1...total {
                    try await Task.sleep(for: .seconds(1.4))
                    if shouldFail && page == total {
                        continuation.finish(throwing: FaxSendError(reason: String(localized: "The line was busy. No pages were used from your plan.")))
                        return
                    }
                    continuation.yield(.sentPage(page, of: total))
                }
                continuation.yield(.delivered)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
