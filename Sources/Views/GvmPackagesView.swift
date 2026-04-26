import SwiftUI

// MARK: - Go 软件包视图

struct GvmPackagesView: View {
    @StateObject private var viewModel = GvmPackagesViewModel()
    @State private var searchText = ""
    @State private var showingUninstallAlert = false
    @State private var packageToUninstall: GvmPackageInfo?
    @State private var showingInstallProgress = false
    @State private var installVersion = ""

    var filteredPackages: [GvmPackageInfo] {
        if searchText.isEmpty {
            return viewModel.packages
        }
        return viewModel.packages.filter {
            $0.version.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isGvmAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isGvmAvailable ? "gvm 已连接" : "gvm 未安装")
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
                    Text("正在获取可用的 Go 版本...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !viewModel.isGvmAvailable {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("gvm 未安装")
                        .foregroundColor(.secondary)
                    Text("请先在设置中安装 gvm 以管理 Go 版本")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredPackages.isEmpty && !searchText.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("未找到匹配的 Go 版本")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredPackages) {
                    TableColumn("版本") { pkg in
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(pkg.isInstalled ? .cyan : .secondary.opacity(0.4))
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
        .searchable(text: $searchText, prompt: "搜索 Go 版本号")
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
            Text("确定要卸载 Go \(packageToUninstall?.version ?? "") 吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingInstallProgress) {
            InstallProgressSheet(
                version: installVersion,
                isInstalling: viewModel.isInstalling,
                output: viewModel.installOutput,
                isSuccess: viewModel.installSuccess,
                error: viewModel.installError,
                canRetryWithCompile: viewModel.canRetryWithCompile,
                canAutoFix: false,
                onDismiss: {
                    showingInstallProgress = false
                    Task { await viewModel.refresh() }
                },
                onCancel: {
                    viewModel.cancelInstall()
                },
                onRetryCompile: {
                    Task { await viewModel.install(installVersion, preferBinary: false) }
                },
                onAutoFix: nil
            )
        }
    }
}

// MARK: - Go 软件包数据模型

struct GvmPackageInfo: Identifiable {
    let id: String
    let version: String
    let isInstalled: Bool
    var isDefault: Bool = false
}

// MARK: - ViewModel

@MainActor
class GvmPackagesViewModel: ObservableObject {
    @Published var packages: [GvmPackageInfo] = []
    @Published var isLoading = false
    @Published var isOperating = false
    @Published var isGvmAvailable = false
    @Published var defaultVersion = ""

    // 安装进度
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installSuccess = false
    @Published var installError: String?
    @Published var canRetryWithCompile = false

    private let service = GvmService.shared

    func cancelInstall() {
        service.cancelCurrentInstall()
        installOutput += "\n\n⚠️ 安装已取消"
        isInstalling = false
        installError = "用户取消了安装"
        isOperating = false
    }

    func load() async {
        isGvmAvailable = service.checkGvmAvailable()
        guard isGvmAvailable else { return }

        isLoading = true

        // 并行获取所有数据
        async let availableVersions = service.listAvailableVersions()
        async let installedVersions = service.listInstalledVersions()

        let available = await availableVersions
        let installed = await installedVersions

        let installedVersionSet = Set(installed.map { $0.version })
        defaultVersion = installed.first(where: { $0.isActive })?.version ?? ""

        packages = available.map { version in
            GvmPackageInfo(
                id: version,
                version: version,
                isInstalled: installedVersionSet.contains(version),
                isDefault: version == defaultVersion
            )
        }

        isLoading = false
    }

    func refresh() async {
        await load()
    }

    func install(_ version: String, preferBinary: Bool = true) async {
        isOperating = true
        isInstalling = true
        installOutput = ""
        installSuccess = false
        installError = nil
        canRetryWithCompile = false

        let methodLabel = preferBinary ? "" : "（源码编译）"
        installOutput += "📦 开始安装 Go \(version)\(methodLabel)...\n\n"

        let result = await service.installGoVersion(version, preferBinary: preferBinary, onOutput: { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output + "\n"
            }
        })

        switch result {
        case .success:
            installOutput += "\n✅ 安装完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = GvmPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: true,
                    isDefault: packages[idx].isDefault
                )
            }
            // 如果是第一个安装的版本，自动设为默认
            if defaultVersion.isEmpty {
                let setResult = await service.setDefaultVersion(version)
                if case .success = setResult {
                    defaultVersion = version
                    for idx in packages.indices {
                        packages[idx] = GvmPackageInfo(
                            id: packages[idx].id,
                            version: packages[idx].version,
                            isInstalled: packages[idx].isInstalled,
                            isDefault: packages[idx].version == version
                        )
                    }
                    installOutput += "\n✅ 已自动设为默认版本"
                }
            }
        case .failure(let error):
            installOutput += "\n❌ 安装失败: \(error)"
            installError = error
            // 二进制下载失败时，仅在版本可源码编译时才允许重试
            let needsGo14Bootstrap = GvmService.requiresGo14Bootstrap(version)
            if preferBinary && (installOutput.contains("Failed to download binary") || installOutput.contains("no binary") || installOutput.contains("404") || installOutput.contains("Failed to download binary go")) {
                if needsGo14Bootstrap {
                    installOutput += "\n\n💡 Go \(version) 没有 ARM64 预编译包，且需要 go1.4 引导编译器（ARM64 Mac 不支持），无法安装。建议安装 Go 1.21+。"
                } else {
                    canRetryWithCompile = true
                    installOutput += "\n\n💡 该版本没有预编译二进制包，可以尝试「从源码编译」。"
                }
            }
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

        installOutput = "🗑️ 开始卸载 Go \(version)...\n\n"

        let result = await service.uninstallGoVersion(version, onOutput: { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output + "\n"
            }
        })

        switch result {
        case .success:
            installOutput += "\n✅ 卸载完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = GvmPackageInfo(
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

    func setAsDefault(_ version: String) async {
        isOperating = true
        let result = await service.setDefaultVersion(version)
        switch result {
        case .success:
            defaultVersion = version
            for idx in packages.indices {
                packages[idx] = GvmPackageInfo(
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
}

#Preview {
    GvmPackagesView()
}
