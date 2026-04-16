import SwiftUI

// MARK: - Rustup 软件包视图

struct RustupPackagesView: View {
    @StateObject private var viewModel = RustupPackagesViewModel()
    @State private var searchText = ""
    @State private var showingUninstallAlert = false
    @State private var packageToUninstall: RustupPackageInfo?
    @State private var showingInstallProgress = false
    @State private var installVersion = ""

    var filteredPackages: [RustupPackageInfo] {
        if searchText.isEmpty {
            return viewModel.packages
        }
        return viewModel.packages.filter {
            $0.version.localizedCaseInsensitiveContains(searchText) ||
            "rust-\($0.version)".localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRustupAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRustupAvailable ? "rustup 已连接" : "rustup 未安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                let installedCount = viewModel.packages.filter { $0.isInstalled }.count
                Text("\(installedCount)/\(viewModel.packages.count) 已安装")
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

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 列表
            if viewModel.isLoading && viewModel.packages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在获取可用 Rust 工具链...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !viewModel.isRustupAvailable {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("rustup 未安装")
                        .foregroundColor(.secondary)
                    Text("请先安装 rustup 以查看可用的 Rust 工具链")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredPackages.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("未找到匹配的 Rust 工具链")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredPackages) {
                    TableColumn("工具链") { pkg in
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(pkg.isInstalled ? .accentColor : .secondary.opacity(0.4))
                                .font(.caption)
                            Text(pkg.version)
                                .fontWeight(.medium)
                            if pkg.isDefault {
                                Text("默认")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(3)
                            } else if pkg.isCurrent {
                                Text("当前")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(3)
                            }
                        }
                    }
                    .width(min: 220, ideal: 280)

                    TableColumn("状态") { pkg in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(pkg.isInstalled ? .green : .gray.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(pkg.isInstalled ? "已安装" : "未安装")
                                .font(.caption)
                                .foregroundColor(pkg.isInstalled ? .green : .secondary)
                        }
                    }
                    .width(80)

                    TableColumn("PID") { pkg in
                        if pkg.isInstalled, let pid = viewModel.rustPids[pkg.version] {
                            Text("\(pid)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        } else {
                            Text("-")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                    .width(60)

                    TableColumn("激活") { pkg in
                        if pkg.isDefault || pkg.isCurrent {
                            Button(action: {
                                if !pkg.isDefault {
                                    Task { await viewModel.setAsDefault(pkg.version) }
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: pkg.isDefault ? "checkmark.circle.fill" : "circle.fill")
                                        .foregroundColor(pkg.isDefault ? .green : .blue)
                                    Text(pkg.isDefault ? "默认" : "当前")
                                        .font(.caption)
                                        .foregroundColor(pkg.isDefault ? .green : .blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(pkg.isDefault)
                        } else {
                            Text("-")
                                .foregroundColor(.secondary.opacity(0.5))
                                .font(.caption)
                        }
                    }
                    .width(70)

                    TableColumn("控制") { pkg in
                        HStack(spacing: 6) {
                            if !pkg.isInstalled {
                                Button(action: {
                                    installVersion = pkg.version
                                    showingInstallProgress = true
                                    Task { await viewModel.install(pkg.version) }
                                }) {
                                    Label("安装", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isOperating)
                            } else {
                                Button(action: {
                                    packageToUninstall = pkg
                                    showingUninstallAlert = true
                                }) {
                                    Label("卸载", systemImage: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isOperating)

                                if !pkg.isDefault {
                                    Button(action: {
                                        Task { await viewModel.setAsDefault(pkg.version) }
                                    }) {
                                        Label("激活", systemImage: "star")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(viewModel.isOperating)
                                }
                            }
                        }
                    }
                    .width(150)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Rust 工具链")
        .task {
            await viewModel.load()
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let pkg = packageToUninstall {
                    Task { await viewModel.uninstall(pkg.version) }
                }
            }
        } message: {
            Text("确定要卸载 Rust 工具链 \(packageToUninstall?.version ?? "") 吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingInstallProgress) {
            InstallProgressSheet(
                version: installVersion,
                isInstalling: viewModel.isInstalling,
                output: viewModel.installOutput,
                isSuccess: viewModel.installSuccess,
                error: viewModel.installError,
                canRetryWithCompile: false,
                canAutoFix: false,
                onDismiss: {
                    showingInstallProgress = false
                    Task { await viewModel.refresh() }
                },
                onCancel: {
                    viewModel.cancelInstall()
                },
                onRetryCompile: nil,
                onAutoFix: nil
            )
        }
    }
}

// MARK: - Rustup 软件包数据模型

struct RustupPackageInfo: Identifiable {
    let id: String
    let version: String
    let isInstalled: Bool
    var isDefault: Bool = false
    var isCurrent: Bool = false
}

// MARK: - ViewModel

@MainActor
class RustupPackagesViewModel: ObservableObject {
    @Published var packages: [RustupPackageInfo] = []
    @Published var isLoading = false
    @Published var isOperating = false
    @Published var isRustupAvailable = false
    @Published var defaultVersion = ""
    @Published var currentVersion = ""
    @Published var rustPids: [String: Int] = [:]

    // 安装进度
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installSuccess = false
    @Published var installError: String?
    private var installingVersion = ""

    private let service = RustupService.shared

    /// 取消当前安装
    func cancelInstall() {
        service.cancelCurrentInstall()
        installOutput += "\n\n⚠️ 安装已取消"
        isInstalling = false
        installError = "用户取消了安装"
        isOperating = false
    }

    /// 分析安装失败原因，返回解决建议
    private func analyzeInstallFailure(output: String, version: String) -> [String] {
        var suggestions: [String] = []

        // 下载失败
        if output.contains("404") || output.contains("download") && output.contains("failed") {
            suggestions.append("下载 Rust 源码失败，请检查网络连接。")
        }

        // 编译失败
        if output.contains("error") && output.contains("linker") {
            suggestions.append("链接失败，可能缺少 Xcode Command Line Tools。")
            suggestions.append("可尝试在终端执行: xcode-select --install")
        }

        // 权限问题
        if output.contains("EACCES") || output.contains("permission") {
            suggestions.append("权限不足，请检查 rustup 安装目录的权限。")
        }

        // 磁盘空间
        if output.contains("No space left") || output.contains("disk space") {
            suggestions.append("磁盘空间不足，请清理磁盘空间后重试。")
        }

        return suggestions
    }

    func load() async {
        isRustupAvailable = service.checkRustupAvailability()
        guard isRustupAvailable else { return }

        isLoading = true

        // 并行获取所有数据
        async let availableVersions = service.listAvailableVersions()
        async let installedVersions = service.listInstalledVersions()
        async let defaultVer = service.getDefaultVersion()
        async let currentVer = service.getCurrentVersion()

        let available = await availableVersions
        let installed = await installedVersions
        defaultVersion = await defaultVer
        currentVersion = await currentVer

        let installedVersionStrings = Set(installed.map { $0.version })

        packages = available.map { version in
            RustupPackageInfo(
                id: version,
                version: version,
                isInstalled: installedVersionStrings.contains(version),
                isDefault: version == defaultVersion,
                isCurrent: version == currentVersion
            )
        }

        // 获取已安装版本的 PID
        await fetchRustPids(installedVersions: installedVersionStrings)

        isLoading = false
    }

    func refresh() async {
        await load()
    }

    func install(_ version: String) async {
        isOperating = true
        isInstalling = true
        installingVersion = version
        installOutput = ""
        installSuccess = false
        installError = nil

        installOutput = "📦 开始安装 Rust 工具链 \(version)...\n\n"

        let result = await service.installVersionWithOutput(version) { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output + "\n"
            }
        }

        switch result {
        case .success:
            installOutput += "\n✅ 安装完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = RustupPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: true,
                    isDefault: packages[idx].isDefault,
                    isCurrent: packages[idx].isCurrent
                )
            }
            await fetchRustPids(installedVersions: Set(packages.compactMap { $0.isInstalled ? $0.version : nil }))
        case .failure(let error):
            installOutput += "\n❌ 安装失败: \(error)"
            installError = error

            let suggestions = analyzeInstallFailure(output: installOutput, version: version)
            if !suggestions.isEmpty {
                installOutput += "\n"
                for suggestion in suggestions {
                    installOutput += "\n💡 \(suggestion)"
                }
            }
        }

        isInstalling = false
        isOperating = false
    }

    func uninstall(_ version: String) async {
        isOperating = true
        let result = await service.uninstallVersion(version)
        switch result {
        case .success:
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = RustupPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: false,
                    isDefault: false,
                    isCurrent: false
                )
            }
            rustPids.removeValue(forKey: version)
        case .failure(let error):
            print("卸载失败: \(error)")
        }
        isOperating = false
    }

    func setAsDefault(_ version: String) async {
        isOperating = true
        let result = await service.setDefaultVersion(version)
        switch result {
        case .success:
            defaultVersion = version
            // 更新所有包的默认状态
            for idx in packages.indices {
                packages[idx] = RustupPackageInfo(
                    id: packages[idx].id,
                    version: packages[idx].version,
                    isInstalled: packages[idx].isInstalled,
                    isDefault: packages[idx].version == version,
                    isCurrent: packages[idx].isCurrent
                )
            }
        case .failure(let error):
            print("激活失败: \(error)")
        }
        isOperating = false
    }

    /// 获取已安装 Rust 进程的 PID
    private func fetchRustPids(installedVersions: Set<String>) async {
        let systemService = SystemService.shared
        let processes = await systemService.getProcessList()

        var pids: [String: Int] = [:]
        for process in processes {
            let name = process.name.lowercased()
            if name == "rustc" || name == "cargo" || name.hasPrefix("rust") {
                // 记录第一个 rust 进程
                if pids.isEmpty {
                    pids[currentVersion] = Int(process.pid)
                }
            }
        }

        rustPids = pids
    }
}

#Preview {
    RustupPackagesView()
}
