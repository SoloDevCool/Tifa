import SwiftUI

// MARK: - Python 软件包视图

struct PythonPackagesView: View {
    @StateObject private var viewModel = PythonPackagesViewModel()
    @State private var searchText = ""
    @State private var showingUninstallAlert = false
    @State private var packageToUninstall: PythonPackageInfo?
    @State private var showingInstallProgress = false
    @State private var installVersion = ""
    
    var filteredPackages: [PythonPackageInfo] {
        if searchText.isEmpty {
            return viewModel.packages
        }
        return viewModel.packages.filter {
            $0.version.localizedCaseInsensitiveContains(searchText) ||
            "python-\($0.version)".localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isPyenvAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isPyenvAvailable ? "pyenv 已连接" : "pyenv 未安装")
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
                    Text("正在获取可用 Python 版本...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !viewModel.isPyenvAvailable {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("pyenv 未安装")
                        .foregroundColor(.secondary)
                    Text("请先安装 pyenv 以查看可用的 Python 软件包")
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
                    Text("未找到匹配的 Python 版本")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredPackages) {
                    TableColumn("包名称") { pkg in
                        HStack(spacing: 6) {
                            Image(systemName: "leaf.fill")
                                .foregroundColor(pkg.isInstalled ? .accentColor : .secondary.opacity(0.4))
                                .font(.caption)
                            Text("python-\(pkg.version)")
                                .fontWeight(.medium)
                            if pkg.isGlobal {
                                Text("全局")
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
                    .width(min: 180, ideal: 220)
                    
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
                        if pkg.isInstalled, let pid = viewModel.pythonPids[pkg.version] {
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
                        if pkg.isGlobal || pkg.isCurrent {
                            Button(action: {
                                if !pkg.isGlobal {
                                    Task { await viewModel.setGlobal(pkg.version) }
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: pkg.isGlobal ? "checkmark.circle.fill" : "circle.fill")
                                        .foregroundColor(pkg.isGlobal ? .green : .blue)
                                    Text(pkg.isGlobal ? "全局" : "当前")
                                        .font(.caption)
                                        .foregroundColor(pkg.isGlobal ? .green : .blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(pkg.isGlobal)
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
                                
                                if !pkg.isGlobal {
                                    Button(action: {
                                        Task { await viewModel.setGlobal(pkg.version) }
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
        .searchable(text: $searchText, prompt: "搜索 Python 版本号")
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
            Text("确定要卸载 Python \(packageToUninstall?.version ?? "") 吗？此操作不可撤销。")
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

// MARK: - Python 软件包数据模型

struct PythonPackageInfo: Identifiable {
    let id: String
    let version: String
    let isInstalled: Bool
    var isGlobal: Bool = false
    var isCurrent: Bool = false
}

// MARK: - ViewModel

@MainActor
class PythonPackagesViewModel: ObservableObject {
    @Published var packages: [PythonPackageInfo] = []
    @Published var isLoading = false
    @Published var isOperating = false
    @Published var isPyenvAvailable = false
    @Published var globalVersion = ""
    @Published var currentVersion = ""
    @Published var pythonPids: [String: Int] = [:]
    
    // 安装进度
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installSuccess = false
    @Published var installError: String?
    private var installingVersion = ""
    
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
        
        // make 编译失败 — 源码与当前系统不兼容
        if output.contains("BUILD FAILED") || (output.contains("make:") && output.contains("Error")) {
            let majorVersion = version.split(separator: ".").first.flatMap { Int($0) } ?? 0
            let minorVersion = version.split(separator: ".").dropFirst().first.flatMap { Int($0) } ?? 0
            
            if majorVersion == 3 && minorVersion <= 5 {
                suggestions.append("Python \(version) 源码编译失败，与当前 macOS 版本不兼容。")
                suggestions.append("Python 3.5 及更早版本已停止维护，不支持 macOS 15+ 的编译环境。")
                suggestions.append("建议安装 Python 3.8 及以上版本以获得兼容性支持。")
            } else if majorVersion == 2 {
                suggestions.append("Python 2.x 已于 2020 年停止维护，不支持 macOS 15+ 编译。")
                suggestions.append("建议安装 Python 3.8 及以上版本。")
            } else {
                suggestions.append("编译失败，可能是缺少依赖或版本不兼容。")
                suggestions.append("可尝试在终端执行: brew install openssl readline zlib xz")
            }
        }
        
        // 下载失败
        if output.contains("Downloading") && (output.contains("failed") || output.contains("404") || output.contains("Connection")) {
            suggestions.append("下载 Python 源码失败，请检查网络连接。")
        }
        
        // zlib / openssl / readline 缺失
        if output.contains("zlib") && output.contains("not found") {
            suggestions.append("缺少 zlib 依赖，可执行: brew install zlib")
        }
        if output.contains("openssl") && output.contains("not found") {
            suggestions.append("缺少 openssl 依赖，可执行: brew install openssl")
        }
        if output.contains("readline") && output.contains("not found") {
            suggestions.append("缺少 readline 依赖，可执行: brew install readline")
        }
        
        return suggestions
    }
    
    private let service = PyenvService.shared
    
    func load() async {
        isPyenvAvailable = service.checkPyenvAvailability()
        guard isPyenvAvailable else { return }
        
        isLoading = true
        
        // 并行获取所有数据
        async let availableVersions = service.listAvailableVersions()
        async let installedVersions = service.listInstalledVersions()
        async let globalVer = service.getGlobalVersion()
        async let currentVer = service.getCurrentVersion()
        
        let available = await availableVersions
        let installed = await installedVersions
        globalVersion = await globalVer
        currentVersion = await currentVer
        
        let installedVersionStrings = Set(installed.map { $0.version })
        
        packages = available.map { version in
            PythonPackageInfo(
                id: version,
                version: version,
                isInstalled: installedVersionStrings.contains(version),
                isGlobal: version == globalVersion,
                isCurrent: version == currentVersion
            )
        }
        
        // 获取已安装版本的 PID
        await fetchPythonPids(installedVersions: installedVersionStrings)
        
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
        
        installOutput = "📦 开始安装 Python \(version)...\n\n"
        
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
                packages[idx] = PythonPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: true,
                    isGlobal: packages[idx].isGlobal,
                    isCurrent: packages[idx].isCurrent
                )
            }
            await fetchPythonPids(installedVersions: Set(packages.compactMap { $0.isInstalled ? $0.version : nil }))
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
                packages[idx] = PythonPackageInfo(
                    id: version,
                    version: version,
                    isInstalled: false,
                    isGlobal: false,
                    isCurrent: false
                )
            }
            pythonPids.removeValue(forKey: version)
        case .failure(let error):
            print("卸载失败: \(error)")
        }
        isOperating = false
    }
    
    func setGlobal(_ version: String) async {
        isOperating = true
        let result = await service.setGlobalVersion(version)
        switch result {
        case .success:
            globalVersion = version
            // 更新所有包的全局状态
            for idx in packages.indices {
                packages[idx] = PythonPackageInfo(
                    id: packages[idx].id,
                    version: packages[idx].version,
                    isInstalled: packages[idx].isInstalled,
                    isGlobal: packages[idx].version == version,
                    isCurrent: packages[idx].isCurrent
                )
            }
        case .failure(let error):
            print("激活失败: \(error)")
        }
        isOperating = false
    }
    
    /// 获取已安装 Python 进程的 PID
    private func fetchPythonPids(installedVersions: Set<String>) async {
        let systemService = SystemService.shared
        let processes = await systemService.getProcessList()
        
        var pids: [String: Int] = [:]
        for process in processes {
            let name = process.name.lowercased()
            if name == "python" || name == "python3" || name.hasPrefix("python") {
                for version in installedVersions {
                    let shortVersion = String(version.prefix(3)) // 如 "3.12"
                    if name.contains(shortVersion.replacingOccurrences(of: ".", with: "")) ||
                       name.contains("python\(shortVersion)") {
                        if pids[version] == nil {
                            pids[version] = Int(process.pid)
                        }
                    }
                }
                // 如果没有精确匹配，记录第一个 python 进程
                if !currentVersion.isEmpty && pids[currentVersion] == nil && pids.isEmpty {
                    pids[currentVersion] = Int(process.pid)
                }
            }
        }
        
        pythonPids = pids
    }
}

#Preview {
    PythonPackagesView()
}
