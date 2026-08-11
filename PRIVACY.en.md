# Privacy Policy

[English](PRIVACY.en.md) · [简体中文](PRIVACY.md)

Effective date: August 10, 2026

ContactsDeduper is a local-first contact organization tool for iOS and macOS. This policy explains how the app accesses, uses, and protects contact data.

## Data the app accesses

After you grant Contacts access, the app may read and modify the following contact information:

- Names, nicknames, organizations, departments, and job titles
- Phone numbers, email addresses, URLs, and postal addresses
- Birthdays, anniversaries, and contact relationships
- Social profiles, instant messaging accounts, and contact images
- List and group names and membership relationships in your Contacts accounts

This information is used only to find duplicate contacts, show matching evidence, merge contacts, and create or restore a backup that you explicitly choose.

## Collection and transmission

- The app has no account system, advertising, analytics, telemetry, or third-party tracking SDKs.
- The app does not upload contact data to the developer or any third-party server.
- The app does not require a network connection. The macOS sandbox configuration disables outgoing network access by default.
- Whether contacts sync through iCloud, Google, or another account is controlled by the system Contacts settings and the relevant account provider, not by the app.

## Backup files

You can explicitly export contacts as a JSON file. A backup may contain sensitive phone numbers, email addresses, postal addresses, birthdays, relationships, social accounts, and contact images.

- Backup files are saved to the location you choose in the system file picker.
- Backup files are not uploaded to the developer’s servers.
- The current backup format is not encrypted. Store it in a trusted location and do not publicly share it or commit it to a Git repository.
- During import, the app validates the file size, format version, and contact count before writing to Contacts.

## Data changes and deletion

- Single-contact-group and bulk merges modify the system Contacts database and delete the duplicate records selected for removal.
- List merging consolidates members and removes duplicate Lists within the same Contacts account; it does not delete contacts as a side effect.
- “Delete all contacts” deletes contacts currently accessible to the app.
- All destructive actions require explicit confirmation.
- The app does not maintain a cloud copy. Export a backup before merging or deleting when possible.

## Permission controls

You can revoke Contacts access at any time in iOS or macOS System Settings. The app cannot read or modify contacts after access is revoked.

## Updates to this policy

If the app adds network services, analytics, cloud synchronization, or a new use of data, this policy will be updated alongside the code and release version.

## Contact

For privacy questions, use the project’s [GitHub Issues](https://github.com/gewill/ContactsDeduper/issues). Do not attach real contact data or backup files to an issue.
