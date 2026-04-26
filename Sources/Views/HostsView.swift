import SwiftUI

struct HostsView: View {
    @StateObject private var viewModel = HostsViewModel()
    @State private var searchText = ""
    @State private var isEditingRaw = false
    @State private var rawContent = ""
    @State private var showingAddSheet = false
    @State private var editingEntry: HostsEntry?
    @State private var showingDeleteConfirm = false
    @State private var entryToDelete: HostsEntry?
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultIsError = false

    private var entriesWithIP: [HostsEntry] {
        let filtered = viewModel.entries.filter { !$0.ip.isEmpty && $0.isEnabled }
        if searchText.isEmpty { return filtered }
        let query = searchText.lowercased()
        return filtered.filter {
            $0.ip.lowercased().contains(query) ||
            $0.hostname.lowercased().contains(query) ||
            ($0.comment?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .foregroundColor(.accentColor)
                    Text("/etc/hosts")
                        .font(.headline)
                }

                Spacer()

                let enabledCount = viewModel.entries.filter { !$0.ip.isEmpty && $0.isEnabled }.count
                let totalCount = viewModel.entries.filter { !$0.ip.isEmpty }.count
                Text("\(enabledCount)/\(totalCount) 条启用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button(action: {
                    Task {
                        let result = await viewModel.flushDNS()
                        resultMessage = result.description
                        resultIsError = result.isFailure
                        showingResult = true
                    }
                }) {
                    Label("刷新DNS", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("刷新系统 DNS 缓存")

                // 模式切换
                Picker("模式", selection: $isEditingRaw) {
                    Text("可视化").tag(false)
                    Text("文本编辑").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                if !isEditingRaw {
                    Button(action: { showingAddSheet = true }) {
                        Label("添加条目", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if isEditingRaw {
                // 文本编辑模式
                VStack(spacing: 0) {
                    TextEditor(text: $rawContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    HStack {
                        Text("修改 /etc/hosts 需要管理员权限")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("保存文件") {
                            Task {
                                let result = await viewModel.saveRawContent(rawContent)
                                resultMessage = result.description
                                resultIsError = result.isFailure
                                showingResult = true
                                if result.isSuccess {
                                    await viewModel.refresh()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
                .onAppear { rawContent = viewModel.rawContent }
                .onChange(of: isEditingRaw) { _ in
                    rawContent = viewModel.rawContent
                }
            } else {
                // 可视化列表模式
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entriesWithIP.isEmpty {
                    EmptyStateView(
                        title: searchText.isEmpty ? "暂无 Hosts 条目" : "未找到匹配项",
                        systemImage: searchText.isEmpty ? "network" : "magnifyingglass",
                        description: searchText.isEmpty ? "点击「添加条目」添加域名映射" : nil
                    )
                } else {
                    List {
                        ForEach(entriesWithIP) { entry in
                            HStack(spacing: 12) {
                                Button(action: {
                                    Task {
                                        let result = await viewModel.toggleEntry(entry)
                                        resultMessage = result.description
                                        resultIsError = result.isFailure
                                        showingResult = true
                                        if result.isSuccess { await viewModel.refresh() }
                                    }
                                }) {
                                    Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(entry.isEnabled ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(entry.isEnabled ? "点击禁用" : "点击启用")
                                .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(entry.ip)
                                            .font(.system(.body, design: .monospaced))
                                            .monospacedDigit()
                                            .foregroundColor(entry.isEnabled ? .primary : .secondary)
                                        Text("→")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(entry.hostname)
                                            .foregroundColor(entry.isEnabled ? .primary : .secondary)
                                    }
                                    if let comment = entry.comment {
                                        Text(comment)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button(action: {
                                    Task {
                                        let result = await viewModel.toggleEntry(entry)
                                        resultMessage = result.description
                                        resultIsError = result.isFailure
                                        showingResult = true
                                        if result.isSuccess { await viewModel.refresh() }
                                    }
                                }) {
                                    Label(entry.isEnabled ? "禁用" : "启用", systemImage: entry.isEnabled ? "eye.slash" : "eye")
                                }
                                Button { editingEntry = entry } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    entryToDelete = entry
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索 IP 或域名")
        .task { await viewModel.load() }
        .sheet(isPresented: $showingAddSheet) {
            AddHostsEntrySheet { ip, hostname, comment in
                Task {
                    let result = await viewModel.addEntry(ip: ip, hostname: hostname, comment: comment)
                    resultMessage = result.description
                    resultIsError = result.isFailure
                    showingResult = true
                    showingAddSheet = false
                    if result.isSuccess { await viewModel.refresh() }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditHostsEntrySheet(entry: entry) { newIP, newHostname, newComment in
                Task {
                    let result = await viewModel.editEntry(entry, newIP: newIP, newHostname: newHostname, newComment: newComment)
                    resultMessage = result.description
                    resultIsError = result.isFailure
                    showingResult = true
                    editingEntry = nil
                    if result.isSuccess { await viewModel.refresh() }
                }
            }
        }
        .alert("删除确认", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { entryToDelete = nil }
            Button("删除", role: .destructive) {
                if let entry = entryToDelete {
                    Task {
                        let result = await viewModel.deleteEntry(entry)
                        resultMessage = result.description
                        resultIsError = result.isFailure
                        showingResult = true
                        entryToDelete = nil
                        if result.isSuccess { await viewModel.refresh() }
                    }
                }
            }
        } message: {
            Text("确定要删除这条映射吗？\(entryToDelete.map { "\n\($0.ip) → \($0.hostname)" } ?? "")")
        }
        .sheet(isPresented: $showingResult) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(resultIsError ? .red : .green)
                    Text("操作结果")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingResult = false }
                }
                Text(resultMessage)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .textSelection(.enabled)
                Button("关闭") { showingResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 450, height: 200)
        }
    }
}

// MARK: - 添加条目 Sheet

struct AddHostsEntrySheet: View {
    let onSave: (String, String, String?) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var ip = "127.0.0.1"
    @State private var hostname = ""
    @State private var comment = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("添加 Hosts 条目")
                    .font(.headline)
                Spacer()
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("IP 地址")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("例如: 127.0.0.1", text: $ip)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            // 常用 IP 快捷按钮
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickIPButton(label: "127.0.0.1", ip: "127.0.0.1") { ip = $0 }
                    QuickIPButton(label: "0.0.0.0", ip: "0.0.0.0") { ip = $0 }
                    QuickIPButton(label: "::1", ip: "::1") { ip = $0 }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("域名")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("例如: example.com", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("注释（可选）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("例如: 本地开发", text: $comment)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(.bordered)
                Button("添加") { onSave(ip, hostname, comment.isEmpty ? nil : comment) }
                    .buttonStyle(.borderedProminent)
                    .disabled(hostname.isEmpty || ip.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 340)
    }
}

// MARK: - 编辑条目 Sheet

struct EditHostsEntrySheet: View {
    let entry: HostsEntry
    let onSave: (String, String, String?) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var ip: String
    @State private var hostname: String
    @State private var comment: String

    init(entry: HostsEntry, onSave: @escaping (String, String, String?) -> Void) {
        self.entry = entry
        self.onSave = onSave
        self._ip = State(initialValue: entry.ip)
        self._hostname = State(initialValue: entry.hostname)
        self._comment = State(initialValue: entry.comment ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("编辑 Hosts 条目")
                    .font(.headline)
                Spacer()
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("IP 地址")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("IP 地址", text: $ip)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("域名")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("域名", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("注释（可选）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("注释", text: $comment)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(.bordered)
                Button("保存") { onSave(ip, hostname, comment.isEmpty ? nil : comment) }
                    .buttonStyle(.borderedProminent)
                    .disabled(hostname.isEmpty || ip.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 300)
    }
}

// MARK: - 快捷 IP 按钮

private struct QuickIPButton: View {
    let label: String
    let ip: String
    let action: (String) -> Void

    var body: some View {
        Button(action: { action(ip) }) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
class HostsViewModel: ObservableObject {
    @Published var entries: [HostsEntry] = []
    @Published var isLoading = false
    @Published var rawContent = ""

    private let service = HostsService.shared

    func load() async {
        isLoading = true
        entries = service.parseEntries()
        rawContent = service.readFileContent()
        isLoading = false
    }

    func refresh() async {
        entries = service.parseEntries()
        rawContent = service.readFileContent()
    }

    func addEntry(ip: String, hostname: String, comment: String?) async -> OperationResult {
        await service.addEntry(ip: ip, hostname: hostname, comment: comment)
    }

    func toggleEntry(_ entry: HostsEntry) async -> OperationResult {
        await service.toggleEntry(entry: entry)
    }

    func editEntry(_ entry: HostsEntry, newIP: String, newHostname: String, newComment: String?) async -> OperationResult {
        await service.editEntry(entry, newIP: newIP, newHostname: newHostname, newComment: newComment)
    }

    func deleteEntry(_ entry: HostsEntry) async -> OperationResult {
        await service.deleteEntry(entry)
    }

    func saveRawContent(_ content: String) async -> OperationResult {
        await service.saveFileContent(content)
    }

    func flushDNS() async -> OperationResult {
        await service.flushDNS()
    }
}

#Preview {
    HostsView()
}
