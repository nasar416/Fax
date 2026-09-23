import Foundation

/// Sample content so every screen has something to show before the backend exists.
enum MockData {
    static func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static let faxes: [Fax] = [
        Fax(party: "Westside Pharmacy", number: "+1 (555) 013-4470", pages: 2, date: date(daysAgo: 0, hour: 8, minute: 3), direction: .received, state: .received, unread: true),
        Fax(party: "+1 (555) 011-6620", number: "+1 (555) 011-6620", pages: 1, date: date(daysAgo: 0, hour: 7, minute: 41), direction: .received, state: .received, unread: true),
        Fax(party: "Lee and Ortiz Law Office", number: "+1 (555) 016-7731", pages: 4, date: date(daysAgo: 1, hour: 16, minute: 20), direction: .received, state: .received),
        Fax(party: "Harbor Insurance", number: "+1 (555) 019-2208", pages: 6, date: date(daysAgo: 5, hour: 11, minute: 0), direction: .received, state: .received),
        Fax(party: "City Tax Office", number: "+1 (555) 012-9054", pages: 3, date: date(daysAgo: 0, hour: 9, minute: 12), direction: .sent, state: .delivered, pagesSent: 3),
        Fax(party: "Harbor Insurance", number: "+1 (555) 019-2208", pages: 6, date: date(daysAgo: 1, hour: 14, minute: 2), direction: .sent, state: .delivered, pagesSent: 6),
        Fax(party: "+44 20 7946 0958", number: "+44 20 7946 0958", pages: 2, date: date(daysAgo: 4, hour: 10, minute: 30), direction: .sent, state: .failed, failureReason: "The line was busy."),
        Fax(party: "Westside Pharmacy", number: "+1 (555) 013-4470", pages: 4, date: .now, direction: .sent, state: .queued),
        Fax(party: "Dr. Amara Okafor", number: "+1 (555) 018-3316", pages: 3, date: .now, direction: .sent, state: .offline),
        Fax(party: "Harbor Insurance", number: "+1 (555) 019-2208", pages: 6, date: date(daysAgo: 8, hour: 9, minute: 0), direction: .received, state: .received, deletedAt: date(daysAgo: 3, hour: 9, minute: 0))
    ]

    static let contacts: [Contact] = [
        Contact(name: "Westside Pharmacy", faxNumber: "+1 (555) 013-4470"),
        Contact(name: "Harbor Insurance", faxNumber: "+1 (555) 019-2208"),
        Contact(name: "Lee and Ortiz Law Office", faxNumber: "+1 (555) 016-7731"),
        Contact(name: "City Tax Office", faxNumber: "+1 (555) 012-9054"),
        Contact(name: "Dr. Amara Okafor", faxNumber: "+1 (555) 018-3316", fromPhone: true)
    ]

    static let blocked: [BlockedNumber] = [
        BlockedNumber(number: "+1 (555) 010-8841", blockedAt: date(daysAgo: 9, hour: 10, minute: 0), reason: "Unknown sender"),
        BlockedNumber(number: "+1 (555) 017-0023", blockedAt: date(daysAgo: 21, hour: 10, minute: 0), reason: "Spam")
    ]

    static let team: [TeamMember] = [
        TeamMember(name: "You", email: "you@example.com", role: .admin),
        TeamMember(name: "Sara Malik", email: "sara@example.com", role: .member),
        TeamMember(name: "Chen Wei", email: "chen@example.com", role: .invited)
    ]

    static let numbers: [FaxNumber] = [
        FaxNumber(number: "+1 (555) 014-2290", label: "Main office", sharedWithTeam: true),
        FaxNumber(number: "+1 (555) 014-7715", label: "Billing", sharedWithTeam: false)
    ]
}
