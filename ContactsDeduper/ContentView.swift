import Contacts
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var manager = ContactsManager()
    @State private var selectedGroup: DuplicateGroup?
    @State private var exportDocument = ContactsBackupDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: PendingContactImport?
    @State private var showImportConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var showBulkMergeConfirmation = false
    @State private var mergeReport: BulkMergeResult?
    @State private var notice: AppNotice?

    var body: some View {
        NavigationStack {
            Group {
                if manager.isLoading {
                    ProgressView("正在扫描通讯录")
                } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                    permissionView
                } else if manager.duplicateGroups.isEmpty {
                    emptyView
                } else {
                    duplicateList
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if manager.isBulkMerging || (!manager.isLoading && !manager.duplicateGroups.isEmpty) {
                    bulkMergePanel
                }
            }
            .navigationTitle("通讯录去重")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    backupMenu

                    Button {
                        Task { await manager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("重新扫描")
                    .disabled(manager.isLoading || manager.isBulkMerging)
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
            .sheet(item: $selectedGroup) { group in
                DuplicateDetailView(group: group, manager: manager)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $mergeReport) { report in
                MergeReportView(report: report)
                    .presentationDetents([.medium, .large])
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
                        message: "已导出 \(manager.allContacts.count) 个联系人到 \(url.lastPathComponent)。"
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
                "删除全部 \(manager.allContacts.count) 个联系人？",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("永久删除全部联系人", role: .destructive) {
                    Task { await deleteAllContacts() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作不可撤销。请先使用“导出备份”，确认备份文件可用后再继续。")
            }
            .confirmationDialog(
                "同步合并全部 \(manager.duplicateGroups.count) 组联系人？",
                isPresented: $showBulkMergeConfirmation,
                titleVisibility: .visible
            ) {
                Button("合并并删除全部重复项", role: .destructive) {
                    Task { await performBulkMerge() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("每组将自动保留资料最完整的联系人，补齐其他资料后删除重复项。建议先导出备份。")
            }
            .alert(item: $notice) { notice in
                Alert(title: Text("操作结果"), message: Text(notice.message), dismissButton: .default(Text("好")))
            }
        }
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
            .disabled(manager.allContacts.isEmpty)
        } label: {
            Image(systemName: "archivebox")
        }
        .accessibilityLabel("备份与恢复")
        .disabled(manager.isLoading || manager.isBulkMerging)
    }

    private var bulkMergePanel: some View {
        VStack(spacing: 10) {
            if let progress = manager.bulkMergeProgress {
                HStack {
                    Text(manager.bulkMergeStatus ?? "正在同步合并")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.linear)
            } else {
                Button {
                    showBulkMergeConfirmation = true
                } label: {
                    Label(
                        "一键同步合并 \(manager.duplicateGroups.count) 组",
                        systemImage: "person.2.badge.gearshape"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: 520)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
        do {
            exportDocument = try manager.makeBackupDocument()
            isExporting = true
        } catch {
            notice = AppNotice(message: "无法创建备份：\(error.localizedDescription)")
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain
            && cocoaError.code == NSUserCancelledError
    }

    private func prepareImport(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= ContactsBackupArchive.maximumFileSize else {
                throw ContactsBackupError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let preview = try manager.previewBackup(data: data)
            pendingImport = PendingContactImport(data: data, preview: preview)
            showImportConfirmation = true
        } catch {
            notice = AppNotice(message: "无法导入备份：\(error.localizedDescription)")
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
    private func performBulkMerge() async {
        do {
            let result = try await manager.mergeAllDuplicates()
            mergeReport = result
        } catch {
            notice = AppNotice(message: "同步合并失败：\(error.localizedDescription)")
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

    private var duplicateList: some View {
        List(manager.duplicateGroups) { group in
            Button {
                selectedGroup = group
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.crop.square.stack")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
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
        .safeAreaInset(edge: .top) {
            summaryBar
        }
        .disabled(manager.isBulkMerging)
    }

    private var summaryBar: some View {
        HStack {
            Label("\(manager.duplicateGroups.count) 组重复", systemImage: "sparkle.magnifyingglass")
            Spacer()
            Text("共 \(manager.allContacts.count) 人")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding()
        .background(.bar)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("没有发现重复联系人", systemImage: "checkmark.seal")
        } description: {
            Text("已扫描 \(manager.allContacts.count) 个联系人。")
        } actions: {
            Button("重新扫描") {
                Task { await manager.refresh() }
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

private struct PendingContactImport {
    let data: Data
    let preview: ContactImportPreview
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
                        ReportMetric(
                            title: "已合并",
                            value: "\(report.mergedGroupCount) 组",
                            systemImage: "person.2.fill"
                        )
                        ReportMetric(
                            title: "已清理",
                            value: "\(report.deletedContactCount) 项",
                            systemImage: "trash.fill"
                        )
                        ReportMetric(
                            title: "剩余重复",
                            value: "\(report.remainingDuplicateGroupCount) 组",
                            systemImage: "checkmark.circle"
                        )
                        ReportMetric(
                            title: "处理耗时",
                            value: durationText,
                            systemImage: "clock.fill"
                        )
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
        if report.duration < 1 {
            return String(format: "%.1f 秒", report.duration)
        }
        return "\(Int(report.duration.rounded())) 秒"
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
                        let elapsed = timeline.date.timeIntervalSince(startedAt)
                        drawConfetti(in: &context, size: size, elapsed: elapsed)
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
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(color)
                )
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
        NavigationStack {
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

                Section("重复项") {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("合并") {
                        showMergeConfirmation = true
                    }
                    .disabled(group.contacts.count < 2)
                }
            }
            .confirmationDialog("合并后会删除未保留的重复联系人", isPresented: $showMergeConfirmation, titleVisibility: .visible) {
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
        }
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !contact.emailSummary.isEmpty {
                Label(contact.emailSummary, systemImage: "envelope")
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

    @ViewBuilder
    func mergeReportFrameOnMac() -> some View {
#if os(macOS)
        frame(width: 520)
            .frame(minHeight: 500)
#else
        self
#endif
    }
}

#Preview {
    ContentView()
}
