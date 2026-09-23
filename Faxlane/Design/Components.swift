import SwiftUI

// MARK: - Logo

/// The Faxlane mark: a page with a folded corner moving along a lane.
struct FaxlaneMark: View {
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3B74F0), Color(hex: 0x1A56DB), Color(hex: 0x1543B0)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, canvasSize in
                let s = canvasSize.width / 48
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                var page = Path()
                page.move(to: p(20, 12)); page.addLine(to: p(30, 12)); page.addLine(to: p(36, 18))
                page.addLine(to: p(36, 36)); page.addQuadCurve(to: p(34, 38), control: p(36, 38))
                page.addLine(to: p(20, 38)); page.addQuadCurve(to: p(18, 36), control: p(18, 38))
                page.addLine(to: p(18, 14)); page.addQuadCurve(to: p(20, 12), control: p(18, 12))
                ctx.fill(page, with: .color(.white))
                var fold = Path(); fold.move(to: p(30, 12)); fold.addLine(to: p(30, 18)); fold.addLine(to: p(36, 18))
                ctx.stroke(fold, with: .color(Color(hex: 0x1A56DB)), lineWidth: 2 * s)
                var lines = Path()
                lines.move(to: p(22, 25)); lines.addLine(to: p(30, 25))
                lines.move(to: p(22, 30)); lines.addLine(to: p(28, 30))
                ctx.stroke(lines, with: .color(Color(hex: 0x1A56DB)), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
                var lane = Path()
                lane.move(to: p(6, 20)); lane.addLine(to: p(14, 20))
                lane.move(to: p(3, 26)); lane.addLine(to: p(14, 26))
                lane.move(to: p(6, 32)); lane.addLine(to: p(14, 32))
                ctx.stroke(lane, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
            }
            .padding(size * 0.07)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Text helpers

/// Keeps phone numbers left-to-right inside Arabic, Hebrew and Persian text.
struct PhoneText: View {
    let number: String
    var body: some View { Text(verbatim: "\u{2066}\(number)\u{2069}") }
}

struct SectionLabel: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Brand.blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.primary)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(.separator)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var destructivePrimary: PrimaryButtonStyle { PrimaryButtonStyle(color: Brand.failed) }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Cards and chips

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct StatusChip: View {
    let state: FaxState
    var body: some View {
        Text(state.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(state.tint)
            .background(state.tintBackground, in: Capsule())
    }
}

struct PlanPill: View {
    let tier: PlanTier
    var body: some View {
        Label(tier.name, systemImage: "bolt.fill")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(Brand.navy, in: Capsule())
    }
}

struct NoteBox: View {
    enum Kind { case info, warning, success }
    let text: LocalizedStringKey
    var kind: Kind = .info
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(fg)
            Text(text).font(.footnote).foregroundStyle(fg)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    private var icon: String { kind == .warning ? "exclamationmark.triangle" : kind == .success ? "checkmark.circle" : "info.circle" }
    private var fg: Color { kind == .warning ? Brand.pending : kind == .success ? Brand.delivered : Brand.navy }
    private var bg: Color { kind == .warning ? Brand.pendingBg : kind == .success ? Brand.deliveredBg : Brand.blueSoft }
}

/// Small drawn thumbnail of a fax page.
struct PageThumbnail: View {
    var width: CGFloat = 40
    var body: some View {
        VStack(alignment: .leading, spacing: width * 0.1) {
            RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: width * 0.55, height: width * 0.1)
            ForEach([1.0, 0.9, 0.8], id: \.self) { w in
                RoundedRectangle(cornerRadius: 1).fill(Color(.systemGray4)).frame(width: width * 0.72 * w, height: width * 0.075)
            }
            Spacer(minLength: 0)
        }
        .padding(width * 0.16)
        .frame(width: width, height: width * 1.2, alignment: .topLeading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(.separator)))
        .accessibilityHidden(true)
    }
}

// MARK: - Upgrade banner

/// Shown to free users above the tab bar: invites them to get their own fax number.
struct UpgradeBanner: View {
    @Environment(AppModel.self) private var model
    @State private var showPaywall = false
    var body: some View {
        if model.plan == nil && !model.bannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Brand.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get your own fax number").font(.subheadline.weight(.bold))
                    Text("Receive faxes and send more pages").font(.caption).foregroundStyle(Brand.navyText)
                }
                Spacer(minLength: 0)
                Button("Upgrade") { showPaywall = true }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(.white, in: Capsule())
                    .foregroundStyle(Brand.navy)
                Button { withAnimation { model.bannerDismissed = true } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .accessibilityLabel("Dismiss")
                .foregroundStyle(Brand.navyText)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(Brand.navy, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Brand.navy.opacity(0.25), radius: 12, y: 6)
            .padding(.horizontal, 16).padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}
