import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// A color that switches between light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Faxlane design tokens. Backgrounds use system colors so dark mode works everywhere.
enum Brand {
    static let blue = Color(light: 0x1A56DB, dark: 0x3B82F6)
    static let blueSoft = Color(light: 0xE1EAFD, dark: 0x1C2D52)
    static let navy = Color(light: 0x0B1F44, dark: 0x16254A)
    static let navyText = Color(light: 0xB8C6E3, dark: 0xB8C6E3)
    static let lightBlue = Color(hex: 0x7FB0FF)

    static let delivered = Color(light: 0x166534, dark: 0x4ADE80)
    static let deliveredBg = Color(light: 0xDCFCE7, dark: 0x13301F)
    static let pending = Color(light: 0x92400E, dark: 0xFBBF24)
    static let pendingBg = Color(light: 0xFEF3C7, dark: 0x3A2A0B)
    static let failed = Color(light: 0xB91C1C, dark: 0xF87171)
    static let failedBg = Color(light: 0xFEE2E2, dark: 0x3B1414)

    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

extension Font {
    /// Bricolage Grotesque for large titles when it is bundled, otherwise SF Pro Rounded.
    /// Add BricolageGrotesque-ExtraBold.ttf to the target and to UIAppFonts to use it.
    static func display(_ size: CGFloat) -> Font {
        if UIFont(name: "BricolageGrotesque-ExtraBold", size: size) != nil {
            return .custom("BricolageGrotesque-ExtraBold", size: size, relativeTo: .largeTitle)
        }
        return .system(size: size, weight: .heavy, design: .rounded)
    }
}
