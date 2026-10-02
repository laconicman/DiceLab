# Age rating — answer sheet

Answered items carry their evidence; open items are for the owner.

## Answered

- **Unrestricted web access**
  No — no web-view usage found in sources.
  - evidence: no WKWebView/SFSafariViewController/UIWebView referenced in scanned sources

- **Third-party advertising or ad tracking**
  No — no ad/tracking SDKs or frameworks referenced.
  - evidence: no ATTrackingManager/ASIdentifierManager/SKAdNetwork referenced in scanned sources

## Open questions

- **Medical or treatment information**
  Content question — owner answers; HealthKit presence is context only.

- **Violence, horror, or fear themes**
  Content question — owner answers; code cannot supply evidence.

- **Sexual content or nudity**
  Content question — owner answers; code cannot supply evidence.

- **Profanity or crude humour**
  Content question — owner answers; code cannot supply evidence.

- **Alcohol, tobacco, or drug references**
  Content question — owner answers; code cannot supply evidence.

- **Gambling or contests**
  Content question — owner answers; code cannot supply evidence.

- **User-generated content or messaging**
  Content question — owner answers; code cannot supply evidence.

- **Made for Kids eligibility**
  Content question — owner answers; code cannot supply evidence.

## Evidence base

- `DiceLab.xcodeproj/project.pbxproj`
