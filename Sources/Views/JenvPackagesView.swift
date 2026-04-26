import SwiftUI

// MARK: - Java 软件包视图

struct JenvPackagesView: View {
    @StateObject private var viewModel = JenvPackagesViewModel()
    @State private var searchText = ""
    @State private var showingUninstallAlert = false
    @State private var packageToUninstall: JavaPackageInfo?
    @State private var showingInstallProgress = false
    @State private var installVersion = ""

    var filteredPackages: [JavaPackageInfo] {
        if searchText.isEmpty {
            return viewModel.packages
        }
        return viewModel.packages.filter {
            $0.version.localizedCaseInsensitiveContains(searchText) ||
            "openjdk@\($0.version)".localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            statusBar

            Divider()

            // 工具栏
            toolbar

            Divider()

            // 列表
            if viewModel.isLoading && viewModel.packages.isEmpty {
                loadingView
            } else if filteredPackages.isEmpty && !searchText.isEmpty {
                emptyStateNoResults
            } else {
                packagesTable
            }
        }
        .searchable(text: $searchText, prompt: "搜索 OpenJDK 版本号")
        .task {
            await viewModel.load()
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let pkg = packageToUninstall {
                    installVersion = pkg.version
                    showingInstallProgress = true
                    Task { await viewModel.uninstall(pkg.version) }
                }
            }
        } message: {
            Text("确定要卸载 OpenJDK \(packageToUninstall?.version ?? "") 吗？此操作不可撤销。")
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

    // MARK: - 子视图

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Homebrew 可用")
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
    }

    private var toolbar: some View {
        HStack {
            Button(action: { Task { await viewModel.refresh() } }) {
                Label("刷新", systemImage: "arrow.clockwise")
            }

            let installedCount = viewModel.packages.filter { $0.isInstalled }.count
            if installedCount > 0 {
                Button(action: {
                    installVersion = ""
                    showingInstallProgress = true
                    Task { await viewModel.fixLinks() }
                }) {
                    Label("修复链接", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .help("将已安装的 OpenJDK 链接到系统 Java 虚拟机目录")
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
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("正在获取可用的 OpenJDK 版本...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var emptyStateNoResults: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("未找到匹配的 OpenJDK 版本")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var packagesTable: some View {
        Table(filteredPackages) {
            TableColumn("包名称") { pkg in
                HStack(spacing: 6) {
                    Image(systemName: "cube.fill")
                        .foregroundColor(pkg.isInstalled ? .orange : .secondary.opacity(0.4))
                        .font(.caption)
                    Text("openjdk@\(pkg.version)")
                        .fontWeight(.medium)
                    if pkg.isDefault {
                        Text("默认")
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

                        Button(action: {
                            packageToUninstall = pkg
                            showingUninstallAlert = true
                        }) {
                            Label("卸载", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isOperating)
                    }
                }
            }
            .width(150)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - Java 软件包数据模型

struct JavaPackageInfo: Identifiable {
    let id: String
    let version: String
    let isInstalled: Bool
    var isDefault: Bool = false
}

// MARK: - ViewModel

@MainActor
class JenvPackagesViewModel: ObservableObject {
    @Published var packages: [JavaPackageInfo] = []
    @Published var isLoading = false
    @Published var isOperating = false

    // 安装进度
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installSuccess = false
    @Published var installError: String?

    private let service = JenvService.shared

    func cancelInstall() {
        service.cancelCurrentInstall()
        installOutput += "\n\n⚠️ 安装已取消"
        isInstalling = false
        installError = "用户取消了安装"
        isOperating = false
    }

    func load() async {
        isLoading = true

        let availableVersions = service.getAvailableOpenJdkVersions()
        let installedVersions = await service.listInstalledOpenJdkVersions()
        let installedSet = Set(installedVersions)
        let activeVersion = await service.getActiveJdkVersion()

        packages = availableVersions.map { version in
            JavaPackageInfo(
                id: version,
                version: version,
                isInstalled: installedSet.contains(version),
                isDefault: version == activeVersion
            )
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }

    func setAsDefault(_ version: String) async {
        isOperating = true
        let result = await service.setActiveJdkVersion(version)
        switch result {
        case .success:
            // 更新所有包的默认状态
            for idx in packages.indices {
                packages[idx] = JavaPackageInfo(
                    id: packages[idx].id,
                    version: packages[idx].version,
                    isInstalled: packages[idx].isInstalled,
                    isDefault: packages[idx].version == version
                )
            }
        case .failure(let error):
            print("设置默认版本失败: \(error)")
        }
        isOperating = false
    }

    func fixLinks() async {
        isOperating = true
        installOutput = ""
        installSuccess = false
        installError = nil

        await service.fixAllOpenJdkLinks { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output
            }
        }

        installSuccess = true
        isOperating = false
    }

    func install(_ version: String) async {
        isOperating = true
        isInstalling = true
        installOutput = ""
        installSuccess = false
        installError = nil

        installOutput = "📦 开始安装 OpenJDK \(version)...\n\n"

        let result = await service.installOpenJdk(version: version) { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output + "\n"
            }
        }

        switch result {
        case .success:
            installOutput += "\n✅ 安装完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = JavaPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: true,
                    isDefault: packages[idx].isDefault
                )
            }
        case .failure(let error):
            installOutput += "\n❌ 安装失败: \(error)"
            installError = error
        }

        isInstalling = false
        isOperating = false
    }

    func uninstall(_ version: String) async {
        isOperating = true
        isInstalling = true
        installOutput = ""
        installSuccess = false
        installError = nil

        installOutput = "🗑️ 开始卸载 OpenJDK \(version)...\n\n"

        let result = await service.uninstallOpenJdk(version: version) { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output + "\n"
            }
        }

        switch result {
        case .success:
            installOutput += "\n✅ 卸载完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = JavaPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: false,
                    isDefault: false
                )
            }
        case .failure(let error):
            installOutput += "\n❌ 卸载失败: \(error)"
            installError = error
        }

        isInstalling = false
        isOperating = false
    }
}

#Preview {
    JenvPackagesView()
}
