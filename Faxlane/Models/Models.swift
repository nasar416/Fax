import SwiftUI

enum FaxDirection: String, Codable { case received, sent }

enum FaxState: String, Codable {
    case received, delivered, failed, sending, queued, offline, locked

    var label: LocalizedStringKey {
        switch self {
        case .received: "Received"
        case .delivered: "Delivered"
        case .failed: "Failed"
        case .sending: "Sending"
        case .queued: "Queued"
        case .offline: "Waiting for internet"
        case .locked: "Locked"
        }
    }
    var tint: Color {
        switch self {
        case .delivered, .received: Brand.delivered
        case .failed: Brand.failed
        case .sending, .queued, .offline, .locked: Brand.pending
        }
    }
    var tintBackground: Color {
        switch self {
        case .delivered, .received: Brand.deliveredBg
        case .failed: Brand.failedBg
        case .sending, .queued, .offline, .locked: Brand.pendingBg
        }
    }
}

struct Fax: Identifiable, Hashable, Codable {
    var id = UUID()
    var party: String
    var number: String
    var pages: Int
    var date: Date
    var direction: FaxDirection
    var state: FaxState
    var unread = false
    var pagesSent = 0
    var failureReason: String?
    var deletedAt: Date?

    var isInOutbox: Bool { [.sending, .queued, .offline].contains(state) }
}

struct Contact: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var faxNumber: String
    var fromPhone = false
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
    }
}

struct ContactGroup: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var memberIDs: [UUID]
}

struct BlockedNumber: Identifiable, Hashable, Codable {
    var id = UUID()
    var number: String
    var blockedAt: Date
    var reason: String
}

struct TeamMember: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case admin, member, invited }
    var id = UUID()
    var name: String
    var email: String
    var role: Role
}

struct FaxNumber: Identifiable, Hashable, Codable {
    var id = UUID()
    var number: String
    var label: String
    var sharedWithTeam: Bool
    /// Set while the number is held after the plan ended. It is released at this date.
    var releaseAfter: Date? = nil
}

// MARK: - Plans

enum BillingPeriod: String, CaseIterable, Identifiable {
    case weekly, monthly, annual
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .weekly: "Weekly"; case .monthly: "Monthly"; case .annual: "Annual" }
    }
    var hint: LocalizedStringKey {
        switch self { case .weekly: "Free trial"; case .monthly: "Flexible"; case .annual: "Save up to 22%" }
    }
}

enum PlanTier: String, CaseIterable, Identifiable, Codable {
    case basic, premium, business, enterprise
    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self { case .basic: "Basic"; case .premium: "Premium"; case .business: "Business"; case .enterprise: "Enterprise" }
    }
    var tag: LocalizedStringKey {
        switch self {
        case .basic: "Starter"
        case .premium: "Most popular"
        case .business: "For small businesses"
        case .enterprise: "For large businesses"
        }
    }
    /// Pages per billing cycle. Sent and received pages both count.
    func pages(for period: BillingPeriod) -> Int {
        switch (self, period) {
        case (.basic, .weekly): 25
        case (.premium, .weekly): 75
        case (.basic, _): 100
        case (.premium, _): 300
        case (.business, _): 700
        case (.enterprise, _): 2000
        }
    }
    var numbersIncluded: Int { switch self { case .basic, .premium: 1; case .business: 2; case .enterprise: 5 } }
    var teamSeats: Int { switch self { case .basic, .premium: 1; case .business: 5; case .enterprise: 20 } }
    var extras: [LocalizedStringKey] {
        switch self {
        case .basic: ["1 fax number", "Cover sheets", "Sign & fill PDFs"]
        case .premium: ["1 fax number", "iCloud backup of faxes", "Pause receiving anytime"]
        case .business: ["2 fax numbers", "Up to 5 team members", "Shared team inbox", "Shared team contacts"]
        case .enterprise: ["5 fax numbers", "Up to 20 team members", "Priority support", "Shared team contacts"]
        }
    }
    var periods: [BillingPeriod] { self == .basic || self == .premium ? BillingPeriod.allCases : [.monthly, .annual] }

    /// App Store Connect product identifier for this plan and period.
    func productID(_ period: BillingPeriod) -> String { "com.faxlane.\(rawValue).\(period.rawValue)" }

    /// Shown until RevenueCat returns localized prices.
    func fallbackPrice(_ period: BillingPeriod) -> String {
        switch (self, period) {
        case (.basic, .weekly): "$3.99"
        case (.basic, .monthly): "$9.99"
        case (.basic, .annual): "$95.99"
        case (.premium, .weekly): "$5.99"
        case (.premium, .monthly): "$17.99"
        case (.premium, .annual): "$167.99"
        case (.business, .annual): "$334.99"
        case (.business, _): "$34.99"
        case (.enterprise, .annual): "$959.99"
        case (.enterprise, _): "$99.99"
        }
    }
}

struct PagePack: Identifiable, Hashable {
    let pages: Int
    let fallbackPrice: String
    var id: Int { pages }
    var productID: String { "com.faxlane.pages.\(pages)" }
    static let all = [PagePack(pages: 10, fallbackPrice: "$4.99"),
                      PagePack(pages: 25, fallbackPrice: "$9.99"),
                      PagePack(pages: 50, fallbackPrice: "$17.99")]
}

struct Country: Identifiable, Hashable {
    let code: String
    let name: String
    let dial: String
    /// Must match the server (server/src/phone.ts): US/Canada 1×, low-cost countries 3×, the rest 10×,
    /// because fax calls to those countries cost much more per minute.
    var pageMultiplier: Int {
        if code == "US" || code == "CA" { return 1 }
        let lowCost = ["+44", "+353", "+49", "+33", "+39", "+34", "+31", "+32", "+41", "+43", "+45", "+46", "+47",
                       "+358", "+351", "+48", "+420", "+61", "+64", "+81", "+82", "+852", "+65", "+972"]
        return lowCost.contains(dial) ? 3 : 10
    }
    var id: String { code }
    var flag: String {
        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            if let flag = UnicodeScalar(127397 + scalar.value) { scalars.append(flag) }
        }
        return String(scalars)
    }
    static let all: [Country] = [
        .init(code: "US", name: "United States", dial: "+1"), .init(code: "CA", name: "Canada", dial: "+1"),
        .init(code: "GB", name: "United Kingdom", dial: "+44"), .init(code: "DE", name: "Germany", dial: "+49"),
        .init(code: "FR", name: "France", dial: "+33"), .init(code: "SA", name: "Saudi Arabia", dial: "+966"),
        .init(code: "AE", name: "United Arab Emirates", dial: "+971"), .init(code: "JP", name: "Japan", dial: "+81"),
        .init(code: "AU", name: "Australia", dial: "+61"), .init(code: "IN", name: "India", dial: "+91"),
        .init(code: "BD", name: "Bangladesh", dial: "+880"), .init(code: "TR", name: "Türkiye", dial: "+90")
    ]
}

/// A page the user added to a new fax.
struct DraftPage: Identifiable, Hashable {
    enum Source: Hashable { case scan, file(URL), photo, text(String) }
    var id = UUID()
    var source: Source
    var image: UIImage?
    var title: String
}

struct CoverSheet: Hashable {
    var enabled = false
    var from = ""
    var to = ""
    var subject = ""
    var note = ""
    var urgent = false
}
