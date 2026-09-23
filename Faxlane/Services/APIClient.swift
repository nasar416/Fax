import Foundation

/// Talks to the Faxlane server (Cloudflare Worker in /server).
/// Set `FaxlaneAPIBaseURL` in Info.plist (project.yml) to your Worker URL. When it's empty the app uses the mock service.
struct APIClient: Sendable {
    let baseURL: URL
    let token: UUID

    static var configuredBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FaxlaneAPIBaseURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }

    struct APIError: LocalizedError, Decodable {
        let error: String
        let message: String?
        var errorDescription: String? { message ?? error }
    }

    struct Account: Decodable {
        let id: String
        let signedIn: Bool
        let plan: String?
        let period: String?
        let pageLimit: Int
        let pagesUsed: Int
        let pagesLeft: Int
        let extraPages: Int
        let sendingNumber: String?
    }

    struct FaxDTO: Decodable {
        let id: String
        let state: String
        let pages: Int
        let failureReason: String?
    }

    /// Joins the base URL and a path that may carry a query string.
    func url(_ path: String) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        return URL(string: "\(base)/\(path)")!
    }

    func send<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil, auth: Bool = true) async throws -> T {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        if auth { request.setValue("Bearer \(token.uuidString)", forHTTPHeaderField: "authorization") }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw (try? JSONDecoder().decode(APIError.self, from: data)) ?? APIError(error: "http_\(status)", message: nil)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func register() async throws -> Account {
        try await send("POST", "v1/accounts", json: ["token": token.uuidString], auth: false)
    }

    func me() async throws -> Account { try await send("GET", "v1/me") }

    func reportPurchase(transactionID: UInt64) async throws -> Account {
        try await send("POST", "v1/purchases", json: ["transactionId": String(transactionID)])
    }

    func signInWithApple(identityToken: String) async throws -> Account {
        try await send("POST", "v1/auth/apple", json: ["identityToken": identityToken])
    }

    func fax(id: String) async throws -> FaxDTO { try await send("GET", "v1/faxes/\(id)") }

    /// Uploads one PDF (cover sheet first) and starts sending.
    func sendFax(to number: String, pages: Int, pdf: Data) async throws -> FaxDTO {
        let boundary = "faxlane-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("to", number)
        field("pages", String(pages))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"fax.pdf\"\r\nContent-Type: application/pdf\r\n\r\n".utf8))
        body.append(pdf)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url("v1/faxes"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.uuidString)", forHTTPHeaderField: "authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return try await perform(request)
    }
}

/// Sends through the Faxlane server and follows the fax until Telnyx reports the result.
struct RemoteFaxService: FaxService {
    let api: APIClient

    func send(to number: String, pages: [DraftPage], cover: CoverSheet) -> AsyncThrowingStream<FaxProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.dialing)
                    let (pdf, count) = try await PDFBuilder.build(pages: pages, cover: cover)
                    var fax = try await api.sendFax(to: number, pages: count, pdf: pdf)
                    let deadline = Date.now.addingTimeInterval(15 * 60)
                    while Date.now < deadline {
                        switch fax.state {
                        case "delivered":
                            continuation.yield(.sentPage(fax.pages, of: fax.pages))
                            continuation.yield(.delivered)
                            continuation.finish()
                            return
                        case "failed":
                            throw FaxSendError(reason: fax.failureReason ?? String(localized: "The fax didn’t go through."))
                        case "sending":
                            continuation.yield(.sentPage(0, of: count))
                        default:
                            break
                        }
                        try await Task.sleep(for: .seconds(3))
                        fax = try await api.fax(id: fax.id)
                    }
                    throw FaxSendError(reason: String(localized: "Still sending. We’ll notify you when it’s done."))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Faxes, blocked numbers, account

extension APIClient {
    struct FaxItem: Decodable {
        let id: String
        let direction: String
        let number: String
        let pages: Int
        let state: String
        let failureReason: String?
        let unread: Bool
        let createdAt: Double
        let deletedAt: Double?

        var model: Fax {
            Fax(id: UUID(uuidString: id) ?? UUID(),
                party: number,
                number: number,
                pages: pages,
                date: Date(timeIntervalSince1970: createdAt),
                direction: direction == "received" ? .received : .sent,
                state: state == "sending" ? .sending : (FaxState(rawValue: state) ?? .queued),
                unread: unread,
                pagesSent: state == "delivered" ? pages : 0,
                failureReason: failureReason,
                deletedAt: deletedAt.map { Date(timeIntervalSince1970: $0) })
        }
    }

    struct BlockedItem: Decodable {
        let number: String
        let reason: String
        let blockedAt: Double
    }

    private struct FaxList: Decodable { let faxes: [FaxItem] }
    private struct BlockedList: Decodable { let blocked: [BlockedItem] }
    private struct Empty: Decodable {}

    func faxes(folder: String) async throws -> [FaxItem] {
        let list: FaxList = try await send("GET", "v1/faxes?folder=\(folder)")
        return list.faxes
    }

    func updateFax(id: UUID, read: Bool? = nil, deleted: Bool? = nil) async throws {
        var body: [String: Any] = [:]
        if let read { body["read"] = read }
        if let deleted { body["deleted"] = deleted }
        let _: FaxItem = try await send("PATCH", "v1/faxes/\(id.uuidString.lowercased())", json: body)
    }

    func unlockFax(id: UUID) async throws {
        let _: FaxItem = try await send("POST", "v1/faxes/\(id.uuidString.lowercased())/unlock")
    }

    func emptyTrash() async throws { let _: Empty = try await send("DELETE", "v1/trash") }

    func blocked() async throws -> [BlockedItem] {
        let list: BlockedList = try await send("GET", "v1/blocked")
        return list.blocked
    }

    func block(number: String, reason: String) async throws {
        let _: Empty = try await send("POST", "v1/blocked", json: ["number": number, "reason": reason])
    }

    func unblock(number: String) async throws {
        let encoded = number.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? number
        let _: Empty = try await send("DELETE", "v1/blocked/\(encoded)")
    }

    func deleteAccount() async throws { let _: Empty = try await send("DELETE", "v1/me") }
}
