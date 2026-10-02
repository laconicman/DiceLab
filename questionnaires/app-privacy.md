# App Privacy — answer sheet

Answered items carry their evidence; open items are for the owner.

## Answered

- **Does the app track users (ATT definition)?**
  No — every privacy manifest declares `NSPrivacyTracking = false`.
  - evidence: `DiceLab/Resources/PrivacyInfo.xcprivacy`: NSPrivacyTracking = false
  - evidence: no `ATTrackingManager`/`ASIdentifierManager`/`SKAdNetwork` referenced in sources

- **Required-reason API usage declared**
  User Defaults — CA92.1
  - evidence: `DiceLab/Resources/PrivacyInfo.xcprivacy`

- **Third-party analytics/ads SDKs**
  None found in linked frameworks or SwiftPM dependencies.
  - evidence: project file scan found no linked frameworks or packages

## Open questions

- **Does the app collect user data?**
  No manifest declares collected data — confirm the app collects nothing, or add the declarations.

## Evidence base

- `DiceLab.xcodeproj/project.pbxproj`
- `DiceLab/Features/Roll/HistoryPanel.swift`
- `DiceLab/Features/Roll/RollScreen.swift`
- `DiceLab/Features/Roll/SettingsView.swift`
- `DiceLab/Resources/PrivacyInfo.xcprivacy`
