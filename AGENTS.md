# AGENTS.md

This file applies to the entire repository.

## Project Overview

ContactsDeduper is a local-first SwiftUI application for iOS and native macOS. It reads and modifies contacts through Apple's Contacts framework. The app supports duplicate detection, manual and bulk merging, JSON backup and restore, full deletion, progress reporting, and merge reports.

## Engineering Constraints

- Preserve support for both iOS 17+ and native macOS 14+.
- Keep Contacts mutations inside `ContactsManager`, which is isolated to `@MainActor`.
- Use `CNContactStore`, `CNContactFetchRequest`, and `CNSaveRequest`; do not introduce a parallel contact database.
- Keep destructive actions behind an explicit confirmation UI.
- Never make backup import delete or overwrite existing contacts. Import may add missing contacts or restore a missing image.
- Keep bulk merges atomic by preparing one `CNSaveRequest` before execution whenever possible.
- Prefer the contact with the highest information score as the automatic merge keeper.
- Preserve all currently supported fields when merging or changing the backup schema.
- Bump `ContactsBackupArchive.currentVersion` when making an incompatible backup-format change. Add migration support when practical.
- Validate imported files before changing Contacts data. Retain the file-size and contact-count limits.
- Do not add networking, analytics, or telemetry without explicit product approval and corresponding privacy documentation.

## Cross-Platform UI

- Use shared SwiftUI views where APIs are available on both platforms.
- Guard platform-specific APIs with `#if os(iOS)` or `#if os(macOS)`.
- Verify toolbar placements, sheets, file import/export, and window sizing on both platforms.
- Keep bottom actions visible without covering list content or system safe areas.
- Preserve accessibility labels for icon-only controls and hide decorative effects from accessibility.

## Verification

Run both builds after changing Swift or project settings:

```bash
xcodebuild -quiet -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -quiet -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

When changing backup models, also verify an encode/decode/contact-reconstruction round trip and rejection of malformed JSON.

## Repository Hygiene

- Do not commit `DerivedData`, build products, `.DS_Store`, `xcuserdata`, or `*.xcuserstate` files.
- Never commit exported contact backups, real contact fixtures, signing certificates, provisioning profiles, or credentials.
- Keep generated backups outside the repository.
- Do not rewrite or remove user changes that are unrelated to the current task.
