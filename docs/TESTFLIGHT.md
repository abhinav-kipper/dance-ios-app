# Shipping Repaso to TestFlight

Xcode lives at `/Applications/Xcode.app`. If the command-line tools still point elsewhere (and you can't run `sudo xcode-select`), prefix commands with:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## One-time setup

1. Join the Apple Developer Program (paid; TestFlight needs it).
2. Put your Team ID in `project.yml` → `settings.base.DEVELOPMENT_TEAM`.
3. In App Store Connect, create an app with bundle ID `com.amudgal.repaso` (or change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to one you own).
4. Add a 1024×1024 app icon to `Repaso/Resources/Assets.xcassets/AppIcon.appiconset/` and reference it in its `Contents.json` (`"filename": "AppIcon.png"`).

## Each build

1. Bump `CFBundleVersion` in `project.yml`.
2. `xcodegen generate`
3. Open `Repaso.xcodeproj` → Product → Archive → Distribute App → TestFlight & App Store.
4. In App Store Connect → TestFlight, add internal testers (or an external group, which needs a short beta review).

Export compliance is already answered in Info.plist (`ITSAppUsesNonExemptEncryption = false`).

## Checks before uploading

```bash
cd Packages/RepasoCore && swift test
xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```
