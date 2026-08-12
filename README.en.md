# ContactsDeduper

A local-first contact deduplication and safe merge tool for iOS and macOS, built with SwiftUI and Apple’s Contacts framework.

[![CI](https://github.com/gewill/ContactsDeduper/actions/workflows/ci.yml/badge.svg)](https://github.com/gewill/ContactsDeduper/actions/workflows/ci.yml)

[English](README.en.md) · [简体中文](README.md)

[Privacy (8 languages)](PRIVACY.en.md) · [Security review](SECURITY_REVIEW.md) · [MIT License](LICENSE)

A multilingual static support and privacy site is being built in [`website/`](website/) for Cloudflare Pages deployment.

## Features

- Lists device, iCloud, Google, and other contact containers, then scans only the account you select.
- Finds duplicate contacts by name, phone number, or email with four matching rules: two fields, any field, name only, or phone only.
- Shows the evidence behind every duplicate group and supports transitive groups created by linked matches.
- Merges same-named Lists only when they belong to the same Contacts container; Lists from different accounts are never merged automatically.
- Lets you choose the keeper and merge one contact group manually.
- Previews the keeper, contacts to remove, and fields to fill before a bulk merge; individual groups can be cancelled.
- Presents a summary report after a merge.
- Exports a versioned JSON backup and safely restores missing contacts or missing images.
- Supports deleting all contacts behind an explicit confirmation.
- Includes an AppIcon, privacy manifest, and export-compliance declaration for App Store Connect preparation.
- Supports Simplified Chinese, Traditional Chinese, English, Japanese, Korean, Spanish, French, and German, following the system language automatically.

## Matching rules

Contacts are linked using three kinds of evidence:

1. **Name**: the combined family, given, and middle names match. A contact with no personal name falls back to its organization name; an organization is not added to the match key when a personal name exists.
2. **Phone**: normalized phone numbers match.
3. **Email**: email addresses match after trimming surrounding whitespace and ignoring case.

| Rule | Meaning |
| --- | --- |
| Two fields (default) | At least two of name, phone, and email match |
| Any field | Any one of the three fields matches |
| Name only | Compare names only |
| Phone only | Compare phone numbers only |

Matching contacts are linked into duplicate groups. For example, under “Any field”, A and B can share a phone number while B and C share a name; all three belong to one group. The “Two fields” rule still counts evidence pairwise between contacts, so sharing one phone bucket does not count as multiple fields.

System contact groups such as “Family” and “Work” are not part of contact deduplication. A List is mergeable only when its normalized name and Contacts container both match.

## Safety and privacy

- Contacts are read and changed directly through the system Contacts framework. The app has no upload, remote sync, analytics, or telemetry logic.
- Bulk merges prepare all changes first and submit them in one `CNSaveRequest`.
- Backup import only adds missing contacts or restores a missing image; it never deletes or overwrites an existing contact.
- JSON backups may contain sensitive phone numbers, email addresses, postal addresses, birthdays, and images, and are not encrypted. Store them securely.
- Review the preview before any bulk merge or deletion, and keep a readable backup when possible.

## Quick start

Requirements: iOS 17 or later and macOS 14 or later. The project is currently verified only with Xcode 26 (locally tested with Xcode 26.6); other Xcode versions are unverified and compatibility is not guaranteed.

Open `ContactsDeduper.xcodeproj`, choose an iPhone Simulator, an iOS device, or `My Mac`, and run. The first launch requests Contacts access.

When using temporary code signing for a macOS development build, macOS may ask for Contacts permission again after rebuilding. To keep the authorization stable, select a valid Personal Team under Signing & Capabilities in Xcode.

## Build and test

```bash
xcodebuild -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

The test bundle calls the matching and backup logic directly. It does not access `CNContactStore`, request Contacts permission, or launch the app (it intentionally has no `TEST_HOST`):

```bash
xcodebuild test -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

GitHub Actions builds and runs the full unit-test suite on macOS, and runs the iOS functionality tests in an available simulator.

## Project structure

- `ContactsDeduper/ContentView.swift`: account routing, deduplication UI, import/export, bulk actions, and reports.
- `ContactsDeduper/ContactsManager.swift`: permissions, container-scoped queries, matching, merging, deletion, and Contacts access.
- `ContactsDeduper/ContactsBackup.swift`: versioned backup model, validation, encoding, and restoration.
- `ContactsDeduper/Icon.icon` and `ContactsDeduper/PrivacyInfo.xcprivacy`: Icon Composer vector icon and Apple privacy manifest.
- `ContactsDeduperTests/`: matching, merge, backup, and performance tests.
- `ContactsDeduper/Info.plist` and `ContactsDeduper/Info-macOS.plist`: platform permissions and app configuration.
- `APP_STORE_PREP.md`: App Store Connect category, privacy, and upload checklist.
- `AppStoreMetadata.json`: store metadata and privacy-policy links for eight locales.
- `website/`: a dependency-free multilingual support and privacy site for Cloudflare Pages.

## Known limitations

- Full international numbers (`+country code`) work in every country and region. Local-format conversion currently covers the United States, Canada, mainland China, the United Kingdom, Germany, Japan, Taiwan, Hong Kong, Macao, Singapore, Australia, France, Spain, Italy, and India. You can manually choose the default region for local numbers on the home screen; an explicit country or region in a contact's address still takes priority. Local numbers elsewhere may not match their international form without region context.
- JSON backups are not encrypted; treat exported files as sensitive data.

## License

This project is released under the [MIT License](LICENSE).
