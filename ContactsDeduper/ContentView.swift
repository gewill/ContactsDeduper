import Contacts
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var manager = ContactsManager()
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
                    ProgressView("正在加载通讯录账户")
                } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                    permissionView
                } else if manager.contactAccounts.isEmpty {
                    emptyView
                } else {
                    accountList
                }
            }
            .navigationTitle("通讯录账户")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    backupMenu

                    Button {
                        Task { await manager.loadAccounts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新加载账户")
                    .disabled(isBusy)
                }
            }
            .task {
                await manager.requestAccessAndLoad()
            }
            .alert("提示", isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )) {
                Button("好") { manager.errorMessage = nil }
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
                        message: "已导出 \(exportedContactCount) 个联系人到 \(url.lastPathComponent)。"
                    )
                case .failure(let error) where isUserCancellation(error):
                    break
                case .failure(let error):
                    notice = AppNotice(message: "导出失败：\(error.localizedDescription)")
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
                Button("开始安全恢复") {
                    guard let pendingImport else { return }
                    Task { await restoreContacts(from: pendingImport) }
                }
                Button("取消", role: .cancel) {
                    pendingImport = nil
                }
            } message: {
                if let pendingImport {
                    Text("备份时间：\(pendingImport.preview.exportedAt.formatted(date: .abbreviated, time: .shortened))。文件内共 \(pendingImport.preview.contactCount) 个联系人，预计新增 \(pendingImport.preview.contactsToAdd) 个。现有联系人不会被删除或覆盖。")
                }
            }
            .confirmationDialog(
                "删除全部可访问联系人？",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("永久删除全部联系人", role: .destructive) {
                    Task { await deleteAllContacts() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会删除所有账户中可访问的联系人且不可撤销。请先导出备份。")
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text("操作结果"),
                    message: Text(notice.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var isBusy: Bool {
        manager.isLoading || manager.isBulkMerging || manager.isBulkMergingContactLists
    }

    private var accountList: some View {
        List {
            Section("账户") {
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
                            Text("\(account.contactCount) 人")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
        .disabled(manager.isLoading)
        .overlay(alignment: .top) {
            if manager.isLoading {
                ScanningBanner(title: "正在扫描通讯录")
            }
        }
        .animation(.default, value: manager.isLoading)
    }

    private var backupMenu: some View {
        Menu {
            Button {
                prepareExport()
            } label: {
                Label("导出备份", systemImage: "square.and.arrow.up")
            }

            Button {
                isImporting = true
            } label: {
                Label("从备份恢复", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label("删除全部联系人", systemImage: "trash")
            }
            .disabled(manager.totalContactCount == 0)
        } label: {
            Image(systemName: "archivebox")
        }
        .accessibilityLabel("备份与恢复")
        .disabled(isBusy)
    }

    private var importDialogTitle: String {
        guard let pendingImport else { return "确认恢复通讯录？" }
        return pendingImport.preview.contactsToAdd == 0
            ? "备份中的联系人已存在"
            : "恢复 \(pendingImport.preview.contactsToAdd) 个联系人？"
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
                notice = AppNotice(message: "无法创建备份：\(error.localizedDescription)")
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
                notice = AppNotice(message: "无法导入备份：\(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func deleteAllContacts() async {
        do {
            let deletedCount = try await manager.deleteAllContacts()
            notice = AppNotice(message: "已删除 \(deletedCount) 个联系人。可通过之前导出的备份恢复。")
        } catch {
            notice = AppNotice(message: "删除失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func restoreContacts(from pending: PendingContactImport) async {
        do {
            let result = try await manager.importBackup(data: pending.data)
            var message = "已恢复 \(result.addedCount) 个联系人，跳过 \(result.skippedCount) 个已有联系人。"
            if result.restoredImageCount > 0 {
                message += " 同时补回 \(result.restoredImageCount) 张头像。"
            }
            notice = AppNotice(message: message)
        } catch {
            notice = AppNotice(message: "恢复失败，现有联系人未被删除：\(error.localizedDescription)")
        }
        pendingImport = nil
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("没有可用通讯录账户", systemImage: "person.crop.rectangle.stack")
        } description: {
            Text("系统没有返回可访问的本机、iCloud 或其他通讯录账户。")
        } actions: {
            Button("重新加载") {
                Task { await manager.loadAccounts() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("需要通讯录权限", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("打开系统设置，为 ContactsDeduper 启用通讯录访问权限。")
        }
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
                ProgressView("正在扫描“\(account.name)”")
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
                ScanningBanner(title: "正在重新扫描")
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
                .accessibilityLabel("重新扫描账户")
                .disabled(isMerging)
            }
        }
        .task(id: account.id) {
            await manager.loadAccount(account)
        }
        .sheet(item: $mergePlan) { plan in
            BulkMergePreviewView(accountName: account.name, items: plan.items) { selectedIDs in
                Task { await mergeContacts(groupIDs: selectedIDs) }
            }
            .presentationDetentsOnIOS()
        }
        .confirmationDialog(
            "合并 \(manager.duplicateContactLists.count) 组同名 List？",
            isPresented: $showListMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button("合并同名 List", role: .destructive) {
                Task { await mergeLists() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只处理“\(account.name)”账户。成员会汇总到保留的 List，再删除其余同名 List；不会删除联系人。")
        }
        .sheet(item: $mergeReport) { report in
            MergeReportView(report: report)
                .presentationDetents([.medium, .large])
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text("操作结果"),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var isMerging: Bool {
        manager.isBulkMerging || manager.isBulkMergingContactLists
    }

    private var matchRuleBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("账户内查重", systemImage: "sparkle.magnifyingglass")
                Spacer()
                Text("共 \(manager.allContacts.count) 人")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))

            Picker("判定标准", selection: matchRuleBinding) {
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
                            status: manager.contactListMergeStatus ?? "正在合并 List"
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
                        title: "重复 List",
                        count: manager.duplicateContactLists.count,
                        buttonTitle: "合并全部",
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
                            status: manager.bulkMergeStatus ?? "正在合并联系人"
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
                        title: "重复联系人",
                        count: manager.duplicateGroups.count,
                        buttonTitle: "一键合并",
                        systemImage: "person.2.badge.gearshape",
                        isDisabled: isMerging || manager.duplicateGroups.isEmpty
                    ) {
                        showMergePreview()
                    }
                }
            }
        }
        .disabled(isMerging)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("这个账户没有重复项", systemImage: "checkmark.seal")
        } description: {
            Text("已扫描“\(account.name)”中的 \(manager.allContacts.count) 个联系人和 List。可在上方切换判定标准，放宽后可能找出更多重复项。")
        } actions: {
            Button("重新扫描") {
                Task { await manager.loadAccount(account) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func showMergePreview() {
        let items = manager.makeBulkMergePlan()
        guard !items.isEmpty else {
            notice = AppNotice(message: "没有可合并的重复联系人。")
            return
        }
        mergePlan = BulkMergePlan(items: items)
    }

    @MainActor
    private func mergeContacts(groupIDs: Set<String>) async {
        do {
            mergeReport = try await manager.mergeAllDuplicates(groupIDs: groupIDs)
        } catch {
            notice = AppNotice(message: "联系人合并失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func mergeLists() async {
        do {
            let result = try await manager.mergeAllDuplicateContactLists()
            notice = AppNotice(
                message: "已合并 \(result.mergedSetCount) 组同名 List，删除 \(result.deletedListCount) 个重复 List，并补充 \(result.addedMemberCount) 位成员。"
            )
        } catch {
            notice = AppNotice(message: "List 合并失败：\(error.localizedDescription)")
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
            Text("\(title) · \(count) 组")
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
                Text("\(Int(progress * 100))%")
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
                        Text("已选 \(selectedIDs.count) / \(items.count) 组")
                        Spacer()
                        Button(isEverythingSelected ? "全不选" : "全选") {
                            selectedIDs = isEverythingSelected ? [] : Set(items.map(\.id))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .textCase(nil)
                } footer: {
                    Text("只处理“\(accountName)”账户。每组保留资料最完整的一项并补齐资料，其余联系人会被删除且不可撤销。建议先导出备份。")
                }
            }
            .navigationTitle("合并预览")
            .inlineNavigationTitleOnIOS()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("合并并删除 \(deletionCount) 项", role: .destructive) {
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

                Label("保留 \(item.keeperName)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.green)

                if !item.keeperSummary.isEmpty {
                    Text(item.keeperSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(
                    "删除 \(item.removedNames.count) 项：\(item.removedSummary)",
                    systemImage: "trash"
                )
                .font(.subheadline)
                .foregroundStyle(.red)

                Label(item.additionSummary, systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("依据：\(item.reasonSummary)")
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
                        Text("同步合并完成")
                            .font(.title2.weight(.bold))
                        Text(report.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ReportMetric(title: "已合并", value: "\(report.mergedGroupCount) 组", systemImage: "person.2.fill")
                        ReportMetric(title: "已清理", value: "\(report.deletedContactCount) 项", systemImage: "trash.fill")
                        ReportMetric(title: "剩余重复", value: "\(report.remainingDuplicateGroupCount) 组", systemImage: "checkmark.circle")
                        ReportMetric(title: "处理耗时", value: durationText, systemImage: "clock.fill")
                    }

                    VStack(spacing: 12) {
                        HStack {
                            Label("联系人总数", systemImage: "person.crop.circle")
                            Spacer()
                            Text("\(report.contactCountBefore) → \(report.contactCountAfter)")
                                .font(.body.monospacedDigit().weight(.semibold))
                        }

                        Divider()

                        if report.remainingDuplicateGroupCount == 0 {
                            Label("本次查重结果已全部处理", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Label(
                                "仍有 \(report.remainingDuplicateGroupCount) 组需要检查",
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
            .navigationTitle("合并报告")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
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
            ? String(format: "%.1f 秒", report.duration)
            : "\(Int(report.duration.rounded())) 秒"
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
            Section("查重依据") {
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

            Section("保留联系人") {
                Picker("保留", selection: $keeperID) {
                    ForEach(group.contacts, id: \.identifier) { contact in
                        Text(contact.displayName).tag(contact.identifier)
                    }
                }
            }

            Section("联系人详情") {
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
                Button("合并") {
                    showMergeConfirmation = true
                }
                .disabled(group.contacts.count < 2)
            }
        }
        .confirmationDialog(
            "合并后会删除未保留的重复联系人",
            isPresented: $showMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button("合并并删除重复项", role: .destructive) {
                guard let keeper = group.contacts.first(where: { $0.identifier == keeperID }) else { return }
                Task {
                    await manager.merge(group, keeping: keeper)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("查重依据：\(group.reasonSummary)。请确认这些联系人确实属于同一个人。")
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
                    Text("保留")
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
                .accessibilityLabel("删除联系人")
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
                Text("没有电话、邮箱或单位资料")
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
