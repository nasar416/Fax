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
| In RevenueCat, add the iOS app, import those products, and put them in an offering as packages (plans and page packs can share one offering). Copy the public Apple SDK key (`appl_...`) into `FaxlaneRevenueCatAPIKey` in `project.yml`. Add the RevenueCat webhook and the secret key to the server (see `server/README.md`). | RevenueCat dashboard, `project.yml` |
| Deploy the backend in [`server/`](server/README.md) (Cloudflare Worker + D1 + R2 + Telnyx). Then set `FaxlaneAPIBaseURL` in `project.yml` to the Worker URL. While it's empty the app runs on sample data. The Telnyx key stays on the server. | `server/`, `project.yml` |
| Remote config is read from the server's `/v1/config` (the `config` table in D1). Change a row there to show an announcement, turn on maintenance, or force an update. No App Store update is needed. | `server/`, `Services/RemoteConfig.swift` |
| Set the App Store ID for the force-update button. | `Features/System/SystemViews.swift` |
| Set your Privacy Policy URL. | `Features/Paywall/PaywallViews.swift` |
| Add the app icon (light, dark and tinted, 1024×1024) to `AppIcon`. | `Resources/Assets.xcassets` |
| Optional: add `BricolageGrotesque-ExtraBold.ttf` to the target and `UIAppFonts` for large titles. Without it, SF Pro Rounded is used. | `Design/Theme.swift` |
| Add the other 18 languages to `Localizable.xcstrings`. English and Arabic are included. Right-to-left layout works automatically. | `Resources/` |

## How key parts work

- **Accounts:** a guest account token is created on first launch and stored in the Keychain (with iCloud Keychain sync) and in the iCloud key-value store. After a reinstall the token is found again and the "Welcome back" screen shows. Sign in with Apple makes the account permanent.
- **Purchases:** the app buys through RevenueCat with the Faxlane account ID as the RevenueCat App User ID. After each purchase or restore it asks the server to sync, and the server reads the customer straight from RevenueCat. Renewals, expiry and refunds reach the server through the RevenueCat webhook. Without an SDK key (and in Debug builds) purchases are simulated so the design can be tried.
- **Pages:** sent and received pages both count. International pages count as 3. Failed faxes don't use pages.
- **Live Activity:** starts when a fax is sent, updates after each page, and ends as delivered or failed. The app updates it locally, so no push server is needed.
- **Support:** "Contact support" opens the user's Mail app addressed to `developer.nasar416@gmail.com`. You can change the address in remote config.
- **Contacts import:** reads only fax numbers from the phone's contacts. Nothing is uploaded.
