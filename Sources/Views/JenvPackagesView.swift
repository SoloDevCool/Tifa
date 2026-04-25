import SwiftUI

// MARK: - JEnv 版本管理视图

struct JenvPackagesView: View {
    @StateObject private var viewModel = JenvPackagesViewModel()
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingRemoveAlert = false
    @State private var versionToRemove: JenvJavaVersion?
    @State private var showingSetGlobalAlert = false
    @State private var versionToSetGlobal: JenvJavaVersion?
    @State private var jdkPathInput = ""
    @State private var addResultMessage = ""
    @State private var showingAddResult = false
    @State private var isAdding = false

    var filteredVersions: [JenvJavaVersion] {
        if searchText.isEmpty {
            return viewModel.versions
        }
        return viewModel.versions.filter {
            $0.version.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isJenvAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isJenvAvailable ? "jenv 已连接" : "jenv 未安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(viewModel.versions.count) 个版本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Spacer()

                Button(action: {
                    Task { await viewModel.scanAndLoadJdks() }
                }) {
                    Label("扫描 JDK", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)

                Button(action: { showingAddSheet = true }) {
                    Label("添加 JDK", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 内容
            if viewModel.isLoading && viewModel.versions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在加载 Java 版本...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !viewModel.isJenvAvailable {
                EmptyStateView(
                    title: "jenv 未安装",
                    systemImage: "exclamationmark.triangle",
                    description: "请先在设置中安装 jenv"
                )
            } else if filteredVersions.isEmpty && viewModel.versions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cube")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无已注册的 Java 版本")
                        .foregroundColor(.secondary)
                    Text("点击\"扫描 JDK\"自动发现或\"添加 JDK\"手动指定路径")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredVersions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("未找到匹配的 Java 版本")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredVersions) {
                    TableColumn("版本") { ver in
                        HStack(spacing: 6) {
                            Image(systemName: "cube")
                                .foregroundColor(.orange.opacity(0.8))
                                .font(.caption)
                            Text(ver.version)
                                .fontWeight(.medium)
                            if ver.isGlobal {
                                Text("全局")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(3)
                            }
                        }
                    }
                    .width(min: 180, ideal: 240)

                    TableColumn("状态") { ver in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("已注册")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .width(80)

                    TableColumn("控制") { ver in
                        HStack(spacing: 6) {
                            if !ver.isGlobal {
                                Button(action: {
                                    versionToSetGlobal = ver
                                    showingSetGlobalAlert = true
                                }) {
                                    Label("设为全局", systemImage: "star")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isOperating)
                            }

                            Button(action: {
                                versionToRemove = ver
                                showingRemoveAlert = true
                            }) {
                                Label("移除", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isOperating)
                        }
                    }
                    .width(150)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Java 版本")
        .task {
            await viewModel.load()
        }
        .alert("确认移除", isPresented: $showingRemoveAlert) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                if let ver = versionToRemove {
                    Task { await viewModel.removeVersion(ver.version) }
                }
            }
        } message: {
            Text("确定要从 jenv 中移除 \(versionToRemove?.version ?? "") 吗？\n注意：这只是从 jenv 中取消注册，不会删除 JDK 文件。")
        }
        .alert("确认设为全局", isPresented: $showingSetGlobalAlert) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let ver = versionToSetGlobal {
                    Task { await viewModel.setGlobalVersion(ver.version) }
                }
            }
        } message: {
            Text("确定要将 \(versionToSetGlobal?.version ?? "") 设为全局默认 Java 版本吗？")
        }
        .sheet(isPresented: $showingAddSheet) {
            addJdkSheet
        }
        .sheet(isPresented: $showingAddResult) {
            VStack(spacing: 16) {
                Text("添加结果")
                    .font(.headline)
                Text(addResultMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                Button("关闭") { showingAddResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 500, height: 200)
        }
    }

    // MARK: - 添加 JDK 面板

    private var addJdkSheet: some View {
        VStack(spacing: 20) {
            Text("添加 JDK")
                .font(.headline)

            Text("请输入 JDK 的 JAVA_HOME 路径：")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("例如: /Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home", text: $jdkPathInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            if isAdding {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在添加...")
                        .font(.caption)
                }
            }

            Divider()

            HStack {
                Button("取消") { showingAddSheet = false }
                    .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    Task { await addJdk() }
                }) {
                    Label("添加", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(jdkPathInput.isEmpty || isAdding)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private func addJdk() async {
        isAdding = true
        defer { isAdding = false }

        let result = await viewModel.addVersion(path: jdkPathInput)
        switch result {
        case .success(let output):
            addResultMessage = "添加成功\n\n\(output)"
            showingAddResult = true
            showingAddSheet = false
            jdkPathInput = ""
            await viewModel.refresh()
        case .failure(let error):
            addResultMessage = "添加失败\n\n\(error)"
            showingAddResult = true
        }
    }
}

// MARK: - ViewModel

@MainActor
class JenvPackagesViewModel: ObservableObject {
    @Published var versions: [JenvJavaVersion] = []
    @Published var isLoading = false
    @Published var isOperating = false
    @Published var isJenvAvailable = false

    private let service = JenvService.shared

    func load() async {
        isJenvAvailable = service.checkJenvAvailable()
        guard isJenvAvailable else { return }

        isLoading = true
        versions = await service.listVersions()
        isLoading = false
    }

    func refresh() async {
        await load()
    }

    func addVersion(path: String) async -> OperationResult {
        isOperating = true
        defer { isOperating = false }
        return await service.addVersion(path: path)
    }

    func removeVersion(_ version: String) async {
        isOperating = true
        let result = await service.removeVersion(version)
        if case .success = result {
            versions.removeAll { $0.version == version }
        }
        isOperating = false
    }

    func setGlobalVersion(_ version: String) async {
        isOperating = true
        let result = await service.setGlobalVersion(version)
        if case .success = result {
            await refresh()
        }
        isOperating = false
    }

    func scanAndLoadJdks() async {
        guard isJenvAvailable else { return }
        isOperating = true

        let jdks = await service.scanSystemJdks()
        let currentVersions = versions.map { $0.version }

        var addedCount = 0
        for jdk in jdks {
            // 检查是否已注册（通过版本号匹配）
            let nameParts = jdk.name.split(separator: " ")
            let alreadyRegistered = currentVersions.contains { current in
                nameParts.contains { part in
                    current.localizedCaseInsensitiveContains(String(part))
                }
            }

            if !alreadyRegistered {
                let result = await service.addVersion(path: jdk.path)
                if case .success = result {
                    addedCount += 1
                }
            }
        }

        await refresh()
        isOperating = false
    }
}

#Preview {
    JenvPackagesView()
}
