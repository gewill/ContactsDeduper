import Contacts
import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Opens the place where Contacts access can be granted: the app's own settings page
/// on iOS, the Privacy & Security pane on macOS, which has no per-app page.
@MainActor
func openContactsPrivacySettings() {
#if os(iOS)
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
#elseif os(macOS)
    guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
    ) else { return }
    NSWorkspace.shared.open(url)
#endif
}

#if os(macOS)
/// macOS caches the TCC decision for the life of the process: flipping the switch in
/// System Settings never reaches a running app, which is why the system itself offers
/// "Quit & Reopen" rather than applying it live. Do the same. If launching the new
/// instance is refused, the app still quits, leaving the user to reopen it by hand.
@MainActor
func relaunchApp() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(
        at: Bundle.main.bundleURL,
        configuration: configuration
    ) { _, _ in
        Task { @MainActor in NSApp.terminate(nil) }
    }
}
#endif

struct ContentView: View {
    @StateObject private var manager = ContactsManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var exportDocument = ContactsBackupDocument()
    @State private var exportedContactCount = 0
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: PendingContactImport?
    @State private var showImportConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var notice: AppNotice?

    var body: some View {
        NavigationStack {
            Group {
                if manager.isLoading && manager.contactAccounts.isEmpty {
                    ProgressView(.AppStrings.accountLoadingContactsAccounts)
                } else if !manager.permissionState.allowsAccess {
                    permissionView
                } else if manager.contactAccounts.isEmpty {
                    emptyView
                } else {
                    accountList
                }
            }
            .navigationTitle(.AppStrings.accountContactsAccounts)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    backupMenu

                    Button {
                        Task { await manager.loadAccounts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(.AppStrings.accountReloadAccount)
                    .disabled(isBusy)
                }
            }
            .task {
                await manager.requestAccessAndLoad()
            }
            // The setting can be flipped while the app is in the background, so pick
            // the change up on return instead of making the user relaunch.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await manager.refreshAuthorizationStatus() }
            }
            .alert(.AppStrings.commonAlert, isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )) {
                Button(.AppStrings.commonOk) { manager.errorMessage = nil }
            } message: {
                Text(manager.errorMessage ?? "")
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success(let url):
                    notice = AppNotice(
                        message: String(localized: .AppStrings.backupExportedContactsTo(value1: exportedContactCount, value2: url.lastPathComponent))
                    )
                case .failure(let error) where isUserCancellation(error):
                    break
                case .failure(let error):
                    notice = AppNotice(message: String(localized: .AppStrings.backupExportFailed(value1: error.localizedDescription)))
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
                prepareImport(from: result)
            }
            .confirmationDialog(
                importDialogTitle,
                isPresented: $showImportConfirmation,
                titleVisibility: .visible
            ) {
                Button(.AppStrings.backupStartSafeRecovery) {
                    guard let pendingImport else { return }
                    Task { await restoreContacts(from: pendingImport) }
                }
                Button(.AppStrings.commonCancel, role: .cancel) {
                    pendingImport = nil
                }
            } message: {
                if let pendingImport {
                    Text(.AppStrings.backupImportPreview(value1: pendingImport.preview.exportedAt.formatted(date: .abbreviated, time: .shortened), value2: pendingImport.preview.contactCount, value3: pendingImport.preview.contactsToAdd))
                }
            }
            .confirmationDialog(
                .AppStrings.deleteAllConfirmationTitle,
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(.AppStrings.deleteAllPermanentlyDeleteAllContacts, role: .destructive) {
                    Task { await deleteAllContacts() }
                }
                Button(.AppStrings.commonCancel, role: .cancel) {}
            } message: {
                Text(.AppStrings.deleteAllConfirmationMessage)
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(.AppStrings.reportOperationResult),
                    message: Text(notice.message),
                    dismissButton: .default(Text(.AppStrings.commonOk))
                )
            }
        }
    }

    private var isBusy: Bool {
        manager.isLoading || manager.isBulkMerging || manager.isBulkMergingContactLists
    }

    private var accountList: some View {
        List {
            if manager.permissionState == .limited {
                Section {
                    LimitedAccessNotice()
                }
            }

            Section {
                ForEach(manager.contactAccounts) { account in
                    NavigationLink {
                        AccountDuplicatesView(account: account, manager: manager)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.title2)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                    .font(.headline)
                                Text(account.typeName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            Text(.AppStrings.contactCount(value1: account.contactCount))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
            } header: {
                Text(.AppStrings.accountAccount)
            } footer: {
                Text(.AppStrings.accountSelectionHint)
            }

            Section {
                Picker(.AppStrings.phoneDefaultRegionForLocalNumbers, selection: defaultPhoneRegionBinding) {
                    Text(.AppStrings.phoneAutomaticDeviceRegion).tag(String?.none)
                    ForEach(supportedPhoneRegions) { region in
                        Text(.AppStrings.commonNameAndCode(value1: region.localizedName, value2: region.code)).tag(Optional(region.code))
                    }
                }
                .pickerStyle(.menu)

                NavigationLink(.AppStrings.phoneSupportTitle) {
                    PhoneMatchingSupportView()
                }
            } header: {
                Text(.AppStrings.phonePhoneMatching)
            } footer: {
                Text(.AppStrings.phoneDefaultRegionDescription)
            }
        }
        .disabled(manager.isLoading)
        .overlay(alignment: .top) {
            if manager.isLoading {
                ScanningBanner(title: String(localized: .AppStrings.progressScanningContacts))
            }
        }
        .animation(.default, value: manager.isLoading)
    }

    private var defaultPhoneRegionBinding: Binding<String?> {
        Binding(
            get: { manager.defaultPhoneRegionCode },
            set: { manager.setDefaultPhoneRegion($0) }
        )
    }

    /// Keeps the account list focused while still exposing the complete matching
    /// boundary before users act on scan results.
    private struct PhoneMatchingSupportView: View {
        var body: some View {
            List {
                Section(.AppStrings.phoneCoverageTitle) {
                    Label(.AppStrings.phoneFullInternationalFormatAvailableForAllCountriesAndRegions, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Label(.AppStrings.phoneLocalFormatConversionOnlySupportsTheFollowingRegions, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Section(.AppStrings.phoneSupportsLocalFormatsInCountriesAndRegions(value1: supportedPhoneRegions.count)) {
                    ForEach(supportedPhoneRegions) { region in
                        LabeledContent(region.localizedName) {
                            Text(.AppStrings.mergeAdditionGrowth(value1: region.callingCode, value2: region.code))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text(.AppStrings.phoneOtherRegionsHint)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(.AppStrings.phoneSupportTitle)
        }
    }

    private var backupMenu: some View {
        Menu {
            Button {
                prepareExport()
            } label: {
                Label(.AppStrings.backupExportBackup, systemImage: "square.and.arrow.up")
            }

            Button {
                isImporting = true
            } label: {
                Label(.AppStrings.backupRestoreFromBackup, systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label(.AppStrings.deleteAllDeleteAllContacts, systemImage: "trash")
            }
            .disabled(manager.totalContactCount == 0)
        } label: {
            Image(systemName: "archivebox")
        }
        .accessibilityLabel(.AppStrings.backupBackupRestore)
        .disabled(isBusy)
    }

    private var importDialogTitle: String {
        guard let pendingImport else { return String(localized: .AppStrings.backupRestoreContacts) }
        return pendingImport.preview.contactsToAdd == 0
            ? String(localized: .AppStrings.backupTheContactsInTheBackupAlreadyExist)
            : String(localized: .AppStrings.backupRecoverContacts(value1: pendingImport.preview.contactsToAdd))
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "ContactsDeduper_\(formatter.string(from: Date())).json"
    }

    private func prepareExport() {
        Task {
            do {
                exportDocument = try await manager.makeBackupDocument()
                exportedContactCount = try ContactsBackupArchive
                    .decode(from: exportDocument.data)
                    .contacts.count
                isExporting = true
            } catch {
                notice = AppNotice(message: String(localized: .AppStrings.backupUnableToCreateBackup(value1: error.localizedDescription)))
            }
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError
    }

    /// Reads the picked file while the security-scoped resource is still open, so the
    /// bytes are in memory before the preview scan suspends.
    private func readBackup(from result: Result<URL, Error>) throws -> Data {
        let url = try result.get()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= ContactsBackupArchive.maximumFileSize else {
            throw ContactsBackupError.fileTooLarge
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func prepareImport(from result: Result<URL, Error>) {
        Task {
            do {
                let data = try readBackup(from: result)
                let preview = try await manager.previewBackup(data: data)
                pendingImport = PendingContactImport(data: data, preview: preview)
                showImportConfirmation = true
            } catch {
                notice = AppNotice(message: String(localized: .AppStrings.backupUnableToImportBackup(value1: error.localizedDescription)))
            }
        }
    }

    @MainActor
    private func deleteAllContacts() async {
        do {
            let deletedCount = try await manager.deleteAllContacts()
            notice = AppNotice(message: String(localized: .AppStrings.backupContactsHaveBeenDeletedCanBeRestoredFromAPreviouslyExportedBackup(value1: deletedCount)))
        } catch {
            notice = AppNotice(message: String(localized: .AppStrings.commonDeletionFailed(value1: error.localizedDescription)))
        }
    }

    @MainActor
    private func restoreContacts(from pending: PendingContactImport) async {
        do {
            let result = try await manager.importBackup(data: pending.data)
            var message = String(localized: .AppStrings.backupRestoredContactsSkippingExistingContacts(value1: result.addedCount, value2: result.skippedCount))
            if result.restoredImageCount > 0 {
                message += String(localized: .AppStrings.backupRestoreImagesSuffix(value1: result.restoredImageCount))
            }
            notice = AppNotice(message: message)
        } catch {
            notice = AppNotice(message: String(localized: .AppStrings.backupRestoreFailedExistingContactsWereNotDeleted(value1: error.localizedDescription)))
        }
        pendingImport = nil
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(.AppStrings.accountNoContactsAccountsAvailable, systemImage: "person.crop.rectangle.stack")
        } description: {
            Text(.AppStrings.permissionTheSystemDidNotReturnAnyAccessibleOnMyDeviceIcloudOrOtherContactsAccounts)
        } actions: {
            Button(.AppStrings.commonReload) {
                Task { await manager.loadAccounts() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label(permissionTitle, systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(permissionDescription)
        } actions: {
            switch manager.permissionState {
            case .notDetermined:
                Button(.AppStrings.permissionAllowContactsAccess) {
                    Task { await manager.requestAccessAndLoad() }
                }
                .buttonStyle(.borderedProminent)

            case .denied:
                Button(.AppStrings.commonOpenSystemSettings) {
                    openContactsPrivacySettings()
                }
                .buttonStyle(.borderedProminent)

#if os(macOS)
                Button(.AppStrings.commonEnabledReopenApp) {
                    relaunchApp()
                }
#else
                Button(.AppStrings.commonEnabledCheckAgain) {
                    Task { await manager.refreshAuthorizationStatus() }
                }
#endif

            case .restricted, .granted, .limited:
                EmptyView()
            }
        }
    }

    private var permissionTitle: String {
        switch manager.permissionState {
        case .restricted:
            return String(localized: .AppStrings.permissionContactsAccessRestricted)
        default:
            return String(localized: .AppStrings.permissionContactsAccessRequired)
        }
    }

    private var permissionDescription: String {
        switch manager.permissionState {
        case .notDetermined:
            return String(localized: .AppStrings.permissionIntroduction)
        case .restricted:
            return String(localized: .AppStrings.permissionRestrictedDescription)
        default:
            return settingsPathHint
        }
    }

    private var settingsPathHint: String {
#if os(iOS)
        return String(localized: .AppStrings.permissionDeniedIOSDescription)
#else
        // macOS caches the decision for the life of the process, so no amount of
        // re-checking helps — the app has to start again.
        return String(localized: .AppStrings.permissionDeniedMacOSDescription)
#endif
    }
}

private struct AccountDuplicatesView: View {
    let account: ContactAccount
    @ObservedObject var manager: ContactsManager
    @State private var mergePlan: BulkMergePlan?
    @State private var showListMergeConfirmation = false
    @State private var mergeReport: BulkMergeResult?
    @State private var notice: AppNotice?

    var body: some View {
        Group {
            if manager.isLoading && manager.allContacts.isEmpty {
                ProgressView(.AppStrings.progressScanningAccount(value1: account.name))
            } else if manager.duplicateGroups.isEmpty && manager.duplicateContactLists.isEmpty {
                emptyView
            } else {
                resultsList
            }
        }
        // Keep the previous results on screen while a re-scan runs, so a merge does
        // not blank the list out from under the user.
        .overlay(alignment: .top) {
            if manager.isLoading && !manager.allContacts.isEmpty {
                ScanningBanner(title: String(localized: .AppStrings.progressRescanning))
            }
        }
        .animation(.default, value: manager.isLoading)
        .safeAreaInset(edge: .top) {
            matchRuleBar
        }
        .navigationTitle(account.name)
        .inlineNavigationTitleOnIOS()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await manager.loadAccount(account) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(.AppStrings.accountRescanAccount)
                .disabled(isMerging || manager.isLoading)
            }
        }
        .task(id: account.id) {
            await manager.loadAccount(account)
        }
        .sheet(item: $mergePlan) { plan in
            BulkMergePreviewView(accountName: account.name, items: plan.items) { selectedIDs in
                Task {
                    await mergeContacts(
                        groupIDs: selectedIDs,
                        expectedScanGeneration: plan.scanGeneration
                    )
                }
            }
            .presentationDetentsOnIOS()
        }
        .confirmationDialog(
            .AppStrings.duplicateListMergeConfirmationTitle(value1: manager.duplicateContactLists.count),
            isPresented: $showListMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button(.AppStrings.duplicateListMergeAction, role: .destructive) {
                Task { await mergeLists() }
            }
            Button(.AppStrings.commonCancel, role: .cancel) {}
        } message: {
            Text(.AppStrings.duplicateListMergeConfirmation(value1: account.name))
        }
        .sheet(item: $mergeReport) { report in
            MergeReportView(report: report)
                .presentationDetents([.medium, .large])
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(.AppStrings.reportOperationResult),
                message: Text(notice.message),
                dismissButton: .default(Text(.AppStrings.commonOk))
            )
        }
    }

    private var isMerging: Bool {
        manager.isBulkMerging || manager.isBulkMergingContactLists
    }

    private var matchRuleBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(.AppStrings.accountFindDuplicatesInAccount, systemImage: "sparkle.magnifyingglass")
                Spacer()
                Text(.AppStrings.contactTotalCount(value1: manager.allContacts.count))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))

            Picker(.AppStrings.duplicateMatchingRule, selection: matchRuleBinding) {
                ForEach(DuplicateMatchRule.allCases) { rule in
                    Text(rule.shortTitle).tag(rule)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isMerging || manager.isLoading)

            Text(manager.matchRule.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
    }

    private var matchRuleBinding: Binding<DuplicateMatchRule> {
        Binding(
            get: { manager.matchRule },
            set: { manager.setMatchRule($0) }
        )
    }

    private var resultsList: some View {
        List {
            if !manager.duplicateContactLists.isEmpty || manager.isBulkMergingContactLists {
                Section {
                    if let progress = manager.contactListMergeProgress {
                        MergeProgressRow(
                            progress: progress,
                            status: manager.contactListMergeStatus ?? String(localized: .AppStrings.progressMergingLists)
                        )
                    }

                    ForEach(manager.duplicateContactLists) { duplicateList in
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(duplicateList.name)
                                    .font(.headline)
                                Text(duplicateList.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                } header: {
                    DedupSectionHeader(
                        title: String(localized: .AppStrings.duplicateListTitle),
                        count: manager.duplicateContactLists.count,
                        buttonTitle: String(localized: .AppStrings.mergeMergeAll),
                        systemImage: "rectangle.stack.badge.plus",
                        isDisabled: isMerging || manager.duplicateContactLists.isEmpty
                    ) {
                        showListMergeConfirmation = true
                    }
                }
            }

            if !manager.duplicateGroups.isEmpty || manager.isBulkMerging {
                Section {
                    if let progress = manager.bulkMergeProgress {
                        MergeProgressRow(
                            progress: progress,
                            status: manager.bulkMergeStatus ?? String(localized: .AppStrings.progressMergingContacts)
                        )
                    }

                    ForEach(manager.duplicateGroups) { group in
                        NavigationLink {
                            DuplicateDetailView(group: group, manager: manager)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.crop.square.stack")
                                    .font(.title2)
                                    .foregroundStyle(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.displayName)
                                        .font(.headline)
                                    Text(group.reasonSummary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Text(group.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } header: {
                    DedupSectionHeader(
                        title: String(localized: .AppStrings.duplicateDuplicateContacts),
                        count: manager.duplicateGroups.count,
                        buttonTitle: String(localized: .AppStrings.mergeOneClickMerge),
                        systemImage: "person.2.badge.gearshape",
                        isDisabled: isMerging || manager.isLoading || manager.duplicateGroups.isEmpty
                    ) {
                        showMergePreview()
                    }
                }
            }
        }
        .disabled(isMerging || manager.isLoading)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(.AppStrings.accountThereAreNoDuplicatesInThisAccount, systemImage: "checkmark.seal")
        } description: {
            Text(.AppStrings.accountScanSummary(value1: account.name, value2: manager.allContacts.count))
        } actions: {
            Button(.AppStrings.commonRescan) {
                Task { await manager.loadAccount(account) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func showMergePreview() {
        let items = manager.makeBulkMergePlan()
        guard !items.isEmpty else {
            notice = AppNotice(message: String(localized: .AppStrings.mergeThereAreNoDuplicateContactsToMerge))
            return
        }
        mergePlan = BulkMergePlan(
            items: items,
            scanGeneration: manager.currentScanGeneration
        )
    }

    @MainActor
    private func mergeContacts(groupIDs: Set<String>, expectedScanGeneration: Int) async {
        do {
            mergeReport = try await manager.mergeAllDuplicates(
                groupIDs: groupIDs,
                expectedScanGeneration: expectedScanGeneration
            )
        } catch {
            notice = AppNotice(message: String(localized: .AppStrings.mergeContactMergeFailed(value1: error.localizedDescription)))
        }
    }

    @MainActor
    private func mergeLists() async {
        do {
            let result = try await manager.mergeAllDuplicateContactLists()
            notice = AppNotice(
                message: String(localized: .AppStrings.duplicateListMergeResult(value1: result.mergedSetCount, value2: result.deletedListCount, value3: result.addedMemberCount))
            )
        } catch {
            notice = AppNotice(message: String(localized: .AppStrings.duplicateListMergeFailed(value1: error.localizedDescription)))
        }
    }
}

private struct DedupSectionHeader: View {
    let title: String
    let count: Int
    let buttonTitle: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(.AppStrings.duplicateSectionSummary(value1: title, value2: count))
            Spacer()
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
        }
        .textCase(nil)
    }
}

/// Limited access hands the app only the contacts the user hand-picked. Every count
/// and every "no duplicates" verdict then covers a subset, which for a deduper is
/// misleading enough to say out loud rather than hide.
private struct LimitedAccessNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(.AppStrings.permissionLimitedContactsAccess, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(.AppStrings.permissionLimitedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(.AppStrings.permissionGrantFullContactsAccess) {
                openContactsPrivacySettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

/// Shown while a scan runs. Scans happen off the main actor, so this actually
/// spins instead of freezing with the rest of the UI.
private struct ScanningBanner: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.separator))
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct MergeProgressRow: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(.AppStrings.commonPercentage(value1: Int(progress * 100)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
        }
        .padding(.vertical, 6)
    }
}

private struct PendingContactImport {
    let data: Data
    let preview: ContactImportPreview
}

private struct BulkMergePlan: Identifiable {
    let id = UUID()
    let items: [BulkMergePlanItem]
    let scanGeneration: Int
}

private struct BulkMergePreviewView: View {
    let accountName: String
    let items: [BulkMergePlanItem]
    let onConfirm: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>

    init(accountName: String, items: [BulkMergePlanItem], onConfirm: @escaping (Set<String>) -> Void) {
        self.accountName = accountName
        self.items = items
        self.onConfirm = onConfirm
        _selectedIDs = State(initialValue: Set(items.map(\.id)))
    }

    private var deletionCount: Int {
        items
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.removedNames.count }
    }

    private var isEverythingSelected: Bool {
        selectedIDs.count == items.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            toggle(item.id)
                        } label: {
                            row(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(.AppStrings.mergeSelectedGroupCount(value1: selectedIDs.count, value2: items.count))
                        Spacer()
                        Button(isEverythingSelected ? String(localized: .AppStrings.commonSelectNone) : String(localized: .AppStrings.commonSelectAll)) {
                            selectedIDs = isEverythingSelected ? [] : Set(items.map(\.id))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .textCase(nil)
                } footer: {
                    Text(.AppStrings.mergeBulkConfirmation(value1: accountName))
                }
            }
            .navigationTitle(.AppStrings.mergeMergePreview)
            .inlineNavigationTitleOnIOS()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.AppStrings.commonCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(.AppStrings.mergeMergeAndDeleteItems(value1: deletionCount), role: .destructive) {
                        dismiss()
                        onConfirm(selectedIDs)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .bulkMergePreviewFrameOnMac()
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func row(for item: BulkMergePlanItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)

                Label(.AppStrings.mergeKeepNamedContact(value1: item.keeperName), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.green)

                if !item.keeperSummary.isEmpty {
                    Text(item.keeperSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(
                    .AppStrings.mergeDeleteItemsSummary(value1: item.removedNames.count, value2: item.removedSummary),
                    systemImage: "trash"
                )
                .font(.subheadline)
                .foregroundStyle(.red)

                Label(item.additionSummary, systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(.AppStrings.duplicateReasonsLabel(value1: item.reasonSummary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AppNotice: Identifiable {
    let id = UUID()
    let message: String
}

private struct MergeReportView: View {
    let report: BulkMergeResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    VStack(spacing: 5) {
                        Text(.AppStrings.mergeMergeCompleted)
                            .font(.title2.weight(.bold))
                        Text(report.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ReportMetric(title: String(localized: .AppStrings.mergeMerged), value: String(localized: .AppStrings.duplicateGroupCount(value1: report.mergedGroupCount)), systemImage: "person.2.fill")
                        ReportMetric(title: String(localized: .AppStrings.reportCleaned), value: String(localized: .AppStrings.commonItemCount(value1: report.deletedContactCount)), systemImage: "trash.fill")
                        ReportMetric(title: String(localized: .AppStrings.duplicateDuplicatesLeft), value: String(localized: .AppStrings.duplicateGroupCount(value1: report.remainingDuplicateGroupCount)), systemImage: "checkmark.circle")
                        ReportMetric(title: String(localized: .AppStrings.reportProcessingTime), value: durationText, systemImage: "clock.fill")
                    }

                    VStack(spacing: 12) {
                        HStack {
                            Label(.AppStrings.contactTotalLabel, systemImage: "person.crop.circle")
                            Spacer()
                            Text(.AppStrings.reportBeforeAndAfter(value1: report.contactCountBefore, value2: report.contactCountAfter))
                                .font(.body.monospacedDigit().weight(.semibold))
                        }

                        Divider()

                        if report.remainingDuplicateGroupCount == 0 {
                            Label(.AppStrings.duplicateAllDuplicatesFromThisScanHaveBeenHandled, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label(
                                .AppStrings.duplicateRemainingGroups(value1: report.remainingDuplicateGroupCount),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: 560)
                .padding(24)
            }
            .navigationTitle(.AppStrings.mergeMergeReport)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.AppStrings.commonComplete) { dismiss() }
                }
            }
        }
        .overlay {
            ConfettiCelebrationView()
                .ignoresSafeArea()
        }
        .mergeReportFrameOnMac()
    }

    private var durationText: String {
        report.duration < 1
            ? String(localized: .AppStrings.durationSecondsDecimal(value1: Float(report.duration)))
            : String(localized: .AppStrings.durationSeconds(value1: Int(report.duration.rounded())))
    }
}

private struct ReportMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ConfettiCelebrationView: View {
    @State private var startedAt = Date()
    @State private var isActive = true

    private let colors: [Color] = [.red, .yellow, .green, .blue, .pink, .orange]
    private let duration: TimeInterval = 2.8

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        drawConfetti(
                            in: &context,
                            size: size,
                            elapsed: timeline.date.timeIntervalSince(startedAt)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            isActive = false
        }
    }

    private func drawConfetti(
        in context: inout GraphicsContext,
        size: CGSize,
        elapsed: TimeInterval
    ) {
        guard elapsed < duration + 0.7 else { return }

        for index in 0..<100 {
            let delay = randomUnit(index * 13 + 1) * 0.65
            let time = elapsed - delay
            guard time >= 0, time <= duration else { continue }

            let width = 5 + randomUnit(index * 17 + 2) * 6
            let height = 7 + randomUnit(index * 19 + 3) * 8
            let startX = randomUnit(index * 23 + 4) * size.width
            let drift = (randomUnit(index * 29 + 5) - 0.5) * 70 * time
            let wobble = sin(time * (4 + randomUnit(index * 31 + 6) * 5) + Double(index)) * 14
            let speed = 85 + randomUnit(index * 37 + 7) * 105
            let x = startX + drift + wobble
            let y = -height + speed * time + 34 * time * time
            let fade = min(1, max(0, (duration - time) / 0.55))
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let color = colors[index % colors.count].opacity(fade)

            if index.isMultiple(of: 3) {
                context.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
            }
        }
    }

    private func randomUnit(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

struct DuplicateDetailView: View {
    let group: DuplicateGroup
    @ObservedObject var manager: ContactsManager
    @Environment(\.dismiss) private var dismiss
    @State private var keeperID: String
    @State private var showMergeConfirmation = false

    init(group: DuplicateGroup, manager: ContactsManager) {
        self.group = group
        self.manager = manager
        _keeperID = State(initialValue: group.contacts.first?.identifier ?? "")
    }

    var body: some View {
        List {
            Section(.AppStrings.duplicateMatchReasons) {
                ForEach(group.reasons) { reason in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reason.description)
                            .font(.body.weight(.medium))
                        Text(reason.matchingContactNames(in: group.contacts))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(.AppStrings.mergeKeepContacts) {
                Picker(.AppStrings.mergeKeepContact, selection: $keeperID) {
                    ForEach(group.contacts, id: \.identifier) { contact in
                        Text(contact.displayName).tag(contact.identifier)
                    }
                }
            }

            Section(.AppStrings.commonContactDetails) {
                ForEach(group.contacts, id: \.identifier) { contact in
                    ContactRow(contact: contact, isKeeper: contact.identifier == keeperID) {
                        Task {
                            await manager.delete(contact)
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle(group.displayName)
        .inlineNavigationTitleOnIOS()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(.AppStrings.mergeMerge) {
                    showMergeConfirmation = true
                }
                .disabled(group.contacts.count < 2)
            }
        }
        .confirmationDialog(
            .AppStrings.mergeUnretainedDuplicateContactsWillBeDeletedAfterMerging,
            isPresented: $showMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button(.AppStrings.mergeMergeAndRemoveDuplicates, role: .destructive) {
                guard let keeper = group.contacts.first(where: { $0.identifier == keeperID }) else { return }
                Task {
                    await manager.merge(group, keeping: keeper)
                    dismiss()
                }
            }
            Button(.AppStrings.commonCancel, role: .cancel) {}
        } message: {
            Text(.AppStrings.duplicateMergeConfirmation(value1: group.reasonSummary))
        }
        .detailFrameOnMac()
    }
}

struct ContactRow: View {
    let contact: CNContact
    let isKeeper: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(contact.displayName)
                    .font(.headline)
                if isKeeper {
                    Text(.AppStrings.mergeKeepContact)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.green, in: Capsule())
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(.AppStrings.commonDeleteContact)
            }

            if !contact.phoneSummary.isEmpty {
                Label(contact.phoneSummary, systemImage: "phone")
                    .detailTextStyle()
            }
            if !contact.emailSummary.isEmpty {
                Label(contact.emailSummary, systemImage: "envelope")
                    .detailTextStyle()
            }
            if !contact.organizationName.isEmpty {
                Label(contact.organizationName, systemImage: "building.2")
                    .detailTextStyle()
            }
            if !contact.jobTitle.isEmpty {
                Label(contact.jobTitle, systemImage: "briefcase")
                    .detailTextStyle()
            }
            if contact.phoneSummary.isEmpty,
               contact.emailSummary.isEmpty,
               contact.organizationName.isEmpty,
               contact.jobTitle.isEmpty {
                Text(.AppStrings.contactNoDetails)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private extension View {
    @ViewBuilder
    func inlineNavigationTitleOnIOS() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    func detailTextStyle() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func presentationDetentsOnIOS() -> some View {
#if os(iOS)
        presentationDetents([.large])
#else
        self
#endif
    }

    @ViewBuilder
    func bulkMergePreviewFrameOnMac() -> some View {
#if os(macOS)
        frame(minWidth: 620, minHeight: 540)
#else
        self
#endif
    }

    @ViewBuilder
    func mergeReportFrameOnMac() -> some View {
#if os(macOS)
        frame(width: 520)
            .frame(minHeight: 500)
#else
        self
#endif
    }

    @ViewBuilder
    func detailFrameOnMac() -> some View {
#if os(macOS)
        frame(minWidth: 560, minHeight: 460)
#else
        self
#endif
    }
}

#Preview {
    ContentView()
}
