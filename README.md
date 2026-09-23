# Faxlane (iOS)

Faxlane is a native SwiftUI app for sending and receiving faxes from an iPhone. This code follows the Faxlane design canvas.

- iOS 17 and later
- Swift 5.9, SwiftUI, Observation
- Purchases go through the RevenueCat SDK (Swift Package, added by `project.yml`). RevenueCat is free until $2,500 a month in revenue, then 1% of revenue.

## Open the project

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), which is free.

```bash
brew install xcodegen
cd Fax
xcodegen generate
open Faxlane.xcodeproj
```

Then in Xcode:

1. Select the **Faxlane** target and set your Team under *Signing & Capabilities*. Do the same for **FaxlaneWidgets**.
2. Change the bundle IDs (`com.faxlane.app` and `com.faxlane.app.widgets`) if you use different ones.
3. Run on a real iPhone. The document scanner and Live Activities don't work in the Simulator.

Build with Xcode 26 or later to get the iOS 26 Liquid Glass tab bar and sheets automatically.

## What's inside

```
Faxlane/
  App/            FaxlaneApp (entry, routing, tab bar), AppModel (app state)
  Design/         Theme (colors, fonts), Components (logo, buttons, cards, banner)
  Models/         Fax, Contact, PlanTier, PagePack, Country, sample data
  Services/       FaxService (backend protocol + mock), StoreManager (RevenueCat),
                  AccountStore (Keychain + iCloud restore), RemoteConfig, LiveActivityManager
  Features/
    Onboarding/   Language (20), onboarding, notification primer, "Welcome back" restore
    Home/         Home, fax row, upgrade banner
    Send/         New fax, VisionKit scanner, Photos, Files, text page, cover sheet,
                  review, sending status (delivered / failed)
    Faxes/        Inbox · Sent · Outbox · Trash, search, select, swipe actions,
                  fax details, Sign & fill (PencilKit), locked fax
    Paywall/      Plans, page packs, number on hold, cancel offer
    Settings/     Settings, account, Sign in with Apple, delete account, privacy,
                  numbers, pause receiving, team, help, contact support
    Contacts/     Contacts, groups, team contacts, blocked numbers, import from phone
    System/       Force update, maintenance
  Resources/      Localizable.xcstrings (English + Arabic), Assets
FaxlaneWidgets/   Live Activity: Lock Screen + Dynamic Island
Shared/           FaxActivityAttributes (used by both targets)
```

## Before release

| Item | Where |
|---|---|
| Create the in-app purchases in App Store Connect with the IDs in `PlanTier.productID` (for example `com.faxlane.premium.annual`) and `PagePack.productID` (`com.faxlane.pages.25`). | `Models/Models.swift` |
| In RevenueCat, add the iOS app, import those products, and put them in an offering as packages (plans and page packs can share one offering). The public Apple SDK key is already in `FaxlaneRevenueCatAPIKey` in `project.yml`; the products, entitlements and the `default` offering are already set up in RevenueCat. Still to do there: connect App Store Connect (In-App Purchase key) once the app exists. Add the RevenueCat webhook and the secret key to the server (see `server/README.md`). | RevenueCat dashboard, `project.yml` |
| Remote config is read from the server's `/v1/config` (the `config` table in the server database). Change a row there to show an announcement, turn on maintenance, or force an update. No App Store update is needed. | `server/`, `Services/RemoteConfig.swift` |
| Set the App Store ID for the force-update button. | `Features/System/SystemViews.swift` |
| Optional: add `BricolageGrotesque-ExtraBold.ttf` to the target and `UIAppFonts` for large titles. Without it, SF Pro Rounded is used. | `Design/Theme.swift` |
| Add the other 18 languages to `Localizable.xcstrings`. English and Arabic are included. Right-to-left layout works automatically. | `Resources/` |

## How key parts work

- **Accounts:** a guest account token is created on first launch and stored in the Keychain (with iCloud Keychain sync) and in the iCloud key-value store. After a reinstall the token is found again and the "Welcome back" screen shows. Sign in with Apple makes the account permanent.
- **Purchases:** the app buys through RevenueCat with the Faxlane account ID as the RevenueCat App User ID. After each purchase or restore it asks the server to sync, and the server reads the customer straight from RevenueCat. Renewals, expiry and refunds reach the server through the RevenueCat webhook. Without an SDK key (and in Debug builds) purchases are simulated so the design can be tried.
- **Pages:** sent and received pages both count. International pages count 3× (Western Europe, UK, Australia, Japan and similar) or 10× (other countries), matching what those calls cost. If a fax fails, only pages that already went through count. During a free trial the plan is capped at 10 pages and the own number comes with the first paid period.
- **Live Activity:** starts when a fax is sent, updates after each page, and ends as delivered or failed. The app updates it locally, so no push server is needed.
- **Support:** "Contact support" opens the user's Mail app addressed to `developer.nasar416@gmail.com`. You can change the address in remote config.
- **Contacts import:** reads only fax numbers from the phone's contacts. Nothing is uploaded.

## App Store Connect

Already set up for app **Faxlane** (Apple ID 6815172582, bundle `com.faxlane.app`):

- 13 in-app purchases (10 subscriptions in "Faxlane Plans", 3 page packs), priced in all 175 countries, with a 3-day free trial on weekly plans. All are *Ready to Submit*.
- English and Arabic name, subtitle, description, keywords, promotional text, privacy policy, support and marketing links.
- Category (Business, Productivity), age rating 4+, free price, all countries, App Review contact and notes.
- Screenshots (6.9" iPhone) in `AppStore/screenshots/`, uploaded for both languages.
- RevenueCat is connected with the App Store Connect API key and the in-app purchase key.

Still to do in App Store Connect: the App Privacy questions (not available in Apple's API), and selecting the 13 in-app purchases on the version page when you submit the first build.
