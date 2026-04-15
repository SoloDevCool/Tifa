import SwiftUI

// MARK: - Ruby 软件包视图

struct RubyPackagesView: View {
    @StateObject private var viewModel = RubyPackagesViewModel()
    @State private var searchText = ""
    @State private var showingUninstallAlert = false
    @State private var packageToUninstall: AvailableRuby?
    @State private var showingUseAlert = false
    @State private var packageToUse: AvailableRuby?
    @State private var showingInstallProgress = false
    @State private var installVersion = ""
    @State private var showingInstallMethodAlert = false
    @State private var packageToInstall: AvailableRuby?
    
    var filteredPackages: [AvailableRuby] {
        if searchText.isEmpty {
            return viewModel.packages
        }
        return viewModel.packages.filter {
            $0.version.localizedCaseInsensitiveContains(searchText) ||
            "ruby-\($0.version)".localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRVMAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRVMAvailable ? "RVM 已连接" : "RVM 未安装")
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
                    Text("正在获取可用 Ruby 版本...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if !viewModel.isRVMAvailable {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("RVM 未安装")
                        .foregroundColor(.secondary)
                    Text("请先安装 RVM 以查看可用的 Ruby 软件包")
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
                    Text("未找到匹配的 Ruby 版本")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredPackages) {
                    TableColumn("包名称") { pkg in
                        HStack(spacing: 6) {
                            Image(systemName: "cube.fill")
                                .foregroundColor(pkg.isInstalled ? .accentColor : .secondary.opacity(0.4))
                                .font(.caption)
                            Text("ruby-\(pkg.version)")
                                .fontWeight(.medium)
                            if pkg.version == viewModel.defaultVersion {
                                Text("默认")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(3)
                            } else if pkg.version == viewModel.currentVersion {
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
                        if pkg.isInstalled, let pid = viewModel.rubyPids[pkg.version] {
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
                        let isDefault = pkg.version == viewModel.defaultVersion
                        let isCurrent = pkg.version == viewModel.currentVersion
                        if isDefault || isCurrent {
                            Button(action: {
                                if !isDefault {
                                    packageToUse = pkg
                                    showingUseAlert = true
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: isDefault ? "checkmark.circle.fill" : "circle.fill")
                                        .foregroundColor(isDefault ? .green : .blue)
                                    Text(isDefault ? "默认" : "当前")
                                        .font(.caption)
                                        .foregroundColor(isDefault ? .green : .blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isDefault)
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
                                    packageToInstall = pkg
                                    showingInstallMethodAlert = true
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
                                
                                if pkg.version != viewModel.defaultVersion {
                                    Button(action: {
                                        packageToUse = pkg
                                        showingUseAlert = true
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
        .searchable(text: $searchText, prompt: "搜索 Ruby 版本号")
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
            Text("确定要卸载 Ruby \(packageToUninstall?.version ?? "") 吗？此操作不可撤销。")
        }
        .alert("确认激活", isPresented: $showingUseAlert) {
            Button("取消", role: .cancel) {}
            Button("激活") {
                if let pkg = packageToUse {
                    Task { await viewModel.useAsDefault(pkg.version) }
                }
            }
        } message: {
            Text("确定要将 Ruby \(packageToUse?.version ?? "") 设为默认版本吗？")
        }
        .alert("选择安装方式", isPresented: $showingInstallMethodAlert) {
            Button("编译安装") {
                if let pkg = packageToInstall {
                    installVersion = pkg.version
                    showingInstallProgress = true
                    Task { await viewModel.install(pkg.version, method: .compile) }
                }
            }
            Button("二进制安装") {
                if let pkg = packageToInstall {
                    installVersion = pkg.version
                    showingInstallProgress = true
                    Task { await viewModel.install(pkg.version, method: .binary) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Ruby \(packageToInstall?.version ?? "")")
        }
        .sheet(isPresented: $showingInstallProgress) {
            InstallProgressSheet(
                version: installVersion,
                isInstalling: viewModel.isInstalling,
                output: viewModel.installOutput,
                isSuccess: viewModel.installSuccess,
                error: viewModel.installError,
                canRetryWithCompile: viewModel.canRetryWithCompile,
                canAutoFix: viewModel.canAutoFix,
                onDismiss: {
                    showingInstallProgress = false
                    Task { await viewModel.refresh() }
                },
                onCancel: {
                    viewModel.cancelInstall()
                },
                onRetryCompile: {
                    Task { await viewModel.install(installVersion, method: .compile) }
                },
                onAutoFix: {
                    Task { await viewModel.autoFixAndRetry() }
                }
            )
        }
    }
}

// MARK: - ViewModel

enum RubyInstallMethod {
    case compile   // 源码编译安装
    case binary    // 二进制安装
}

@MainActor
class RubyPackagesViewModel: ObservableObject {
    @Published var packages: [AvailableRuby] = []
    @Published var isLoading = false
    @Published var isOperating = false
    @Published var isRVMAvailable = false
    @Published var defaultVersion = ""
    @Published var currentVersion = ""
    @Published var rubyPids: [String: Int] = [:]
    
    // 安装进度
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installSuccess = false
    @Published var installError: String?
    @Published var installMethod: RubyInstallMethod = .compile
    @Published var canRetryWithCompile = false
    @Published var canAutoFix = false
    private var installingVersion = ""
    
    /// 取消当前安装
    func cancelInstall() {
        service.cancelCurrentInstall()
        installOutput += "\n\n⚠️ 安装已取消"
        isInstalling = false
        installError = "用户取消了安装"
        isOperating = false
    }
    
    private let service = RVMService.shared
    
    func load() async {
        isRVMAvailable = service.checkRVMAvailability()
        guard isRVMAvailable else { return }
        
        isLoading = true
        
        // 并行获取所有数据
        async let knownVersions = service.listKnownRubies()
        async let installedRubies = service.listInstalledRubies()
        async let defaultVer = service.getDefaultRubyVersion()
        async let currentVer = service.getCurrentRubyVersion()
        
        let known = await knownVersions
        let installed = await installedRubies
        defaultVersion = await defaultVer
        currentVersion = await currentVer
        
        let installedVersions = Set(installed.map { $0.version })
        
        packages = known.map { version in
            AvailableRuby(version: version, isInstalled: installedVersions.contains(version))
        }
        
        // 获取已安装版本的 PID
        await fetchRubyPids(installedVersions: installedVersions)
        
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    /// 自动修复 openssl 依赖并重新编译安装
    func autoFixAndRetry() async {
        guard !installingVersion.isEmpty else { return }
        isOperating = true
        isInstalling = true
        installOutput += "\n\n🔧 正在自动修复...\n--- 步骤 1/2: 安装 openssl@1.1 ---\n\n"
        installError = nil
        canAutoFix = false
        canRetryWithCompile = false
        
        let version = installingVersion
        let result = await service.installRubyWithOpenSSLFix(version: version, onOutput: { [weak self] line in
            Task { @MainActor in
                self?.installOutput += line + "\n"
            }
        })
        
        switch result {
        case .success:
            installOutput += "\n✅ 安装完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = AvailableRuby(version: version, isInstalled: true)
            }
            await fetchRubyPids(installedVersions: Set(packages.compactMap { $0.isInstalled ? $0.version : nil }))
        case .failure(let error):
            installOutput += "\n❌ 自动修复安装仍然失败: \(error)"
            installError = error
            let suggestions = analyzePostFixFailure(output: installOutput, version: version)
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
    
    func install(_ version: String, method: RubyInstallMethod = .compile) async {
        isOperating = true
        isInstalling = true
        installingVersion = version
        installOutput = ""
        installSuccess = false
        installError = nil
        installMethod = method
        canRetryWithCompile = false
        canAutoFix = false
        
        let methodLabel = method == .binary ? "（二进制）" : "（编译）"
        installOutput = "📦 开始安装 Ruby \(version) \(methodLabel)...\n\n"
        
        let result = await service.installRubyWithOutput(version: version, method: method, onOutput: { [weak self] line in
            Task { @MainActor in
                self?.installOutput += line + "\n"
            }
        })
        
        switch result {
        case .success(let output):
            installOutput += "\n✅ 安装完成"
            installSuccess = true
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = AvailableRuby(version: version, isInstalled: true)
            }
            await fetchRubyPids(installedVersions: Set(packages.compactMap { $0.isInstalled ? $0.version : nil }))
            _ = output
        case .failure(let error):
            installOutput += "\n❌ 安装失败: \(error)"
            installError = error
            
            // 智能建议：根据错误信息提供解决建议
            let suggestions = analyzeInstallFailure(output: installOutput, method: method, version: version)
            if !suggestions.isEmpty {
                installOutput += "\n"
                for suggestion in suggestions {
                    installOutput += "\n💡 \(suggestion)"
                }
            }
            
            // 二进制安装失败且提示无二进制包时，允许重试用编译安装
            if method == .binary && (installOutput.contains("no rubies are available to download") || installOutput.contains("no binary")) {
                canRetryWithCompile = true
            }
            
            // 检测 openssl@1.1 缺失导致的编译失败，允许自动修复
            if installOutput.contains("openssl@1.1") && (installOutput.contains("No available formula") || installOutput.contains("Requirements installation failed")) {
                canAutoFix = true
                installOutput += "\n🔧 点击「自动修复并重试」可自动安装 openssl@1.1 并重新编译。"
            }
        }
        
        isInstalling = false
        isOperating = false
    }
    
    func uninstall(_ version: String) async {
        isOperating = true
        let result = await service.uninstallRuby(version: version)
        switch result {
        case .success:
            if let idx = packages.firstIndex(where: { $0.version == version }) {
                packages[idx] = AvailableRuby(version: version, isInstalled: false)
            }
            rubyPids.removeValue(forKey: version)
        case .failure(let error):
            print("卸载失败: \(error)")
        }
        isOperating = false
    }
    
    func useAsDefault(_ version: String) async {
        isOperating = true
        let result = await service.useRuby(version: version)
        switch result {
        case .success:
            defaultVersion = version
        case .failure(let error):
            print("激活失败: \(error)")
        }
        isOperating = false
    }
    
    /// 获取已安装 Ruby 进程的 PID（通过 ps 查找）
    private func fetchRubyPids(installedVersions: Set<String>) async {
        // 通过 SystemService 获取进程列表
        let systemService = SystemService.shared
        let processes = await systemService.getProcessList()
        
        var pids: [String: Int] = [:]
        for process in processes {
            let name = process.name.lowercased()
            if name == "ruby" || name.hasPrefix("ruby") {
                // 尝试匹配已安装的版本
                for version in installedVersions {
                    if process.name.lowercased().contains("ruby-\(version)") ||
                       process.name.lowercased().contains("ruby\(version)") {
                        pids[version] = Int(process.pid)
                    }
                }
                // 如果没有精确匹配，记录第一个 ruby 进程
                if pids.isEmpty || !processes.contains(where: { p in
                    installedVersions.contains { $0 != "" && pids[$0] != nil }
                }) {
                    if pids[currentVersion] == nil {
                        pids[currentVersion] = Int(process.pid)
                    }
                }
            }
        }
        
        rubyPids = pids
    }
    
    /// 分析安装失败原因，返回解决建议
    private func analyzeInstallFailure(output: String, method: RubyInstallMethod, version: String) -> [String] {
        var suggestions: [String] = []
        
        // 二进制无可用包
        if method == .binary && (output.contains("no rubies are available") || output.contains("No binary rubies")) {
            suggestions.append("该版本没有可用的二进制预编译包，可尝试编译安装。")
        }
        
        // openssl 依赖缺失
        if output.contains("openssl@1.1") && (output.contains("No available formula") || output.contains("not found")) {
            suggestions.append("缺少 openssl@1.1 依赖，Ruby 2.6/2.7/3.0 需要 openssl@1.1，Homebrew 已移除该包。")
            suggestions.append("可尝试执行: brew install rbenv/tap/openssl@1.1")
        }
        
        // openssl@3 兼容问题
        if output.contains("openssl") && output.contains("error") {
            suggestions.append("OpenSSL 版本不兼容，可尝试: rvm pkg install openssl && rvm install ruby-\(version) --with-openssl-dir=$rvm_path/usr")
        }
        
        // Homebrew 更新失败
        if output.contains("Failed to update Homebrew") || output.contains("brew update") {
            suggestions.append("Homebrew 更新失败，可先执行: brew update 修复后再重试安装。")
        }
        
        // Requirements 安装失败
        if output.contains("Requirements installation failed") {
            suggestions.append("系统依赖安装失败，请检查 Homebrew 是否正常工作。")
        }
        
        // 旧版本兼容性提示
        if output.contains("Continuing with compilation") {
            let majorVersion = version.split(separator: ".").first.flatMap { Int($0) } ?? 0
            if majorVersion <= 2 {
                suggestions.append("Ruby \(version) 是较旧版本，在 macOS 15+ 上编译可能遇到兼容性问题。")
                suggestions.append("建议安装 Ruby 3.1+ 以获得更好的兼容性。")
            }
        }
        
        return suggestions
    }
    
    /// 自动修复后的失败分析（不再提示已修复的问题）
    private func analyzePostFixFailure(output: String, version: String) -> [String] {
        var suggestions: [String] = []
        
        // make 编译失败 — 源码与当前系统不兼容
        if output.contains("Error running") && output.contains("make") && output.contains("Halting the installation") {
            suggestions.append("Ruby \(version) 源码编译失败，与当前 macOS 版本不兼容。")
            let majorVersion = version.split(separator: ".").first.flatMap { Int($0) } ?? 0
            if majorVersion <= 2 {
                suggestions.append("Ruby 2.x 已停止维护，不支持 macOS 15+ 的编译环境。")
                suggestions.append("建议安装 Ruby 3.1 及以上版本以获得兼容性支持。")
            }
        }
        
        // 仍然有依赖问题
        if output.contains("Requirements installation failed") && !output.contains("openssl@1.1") {
            suggestions.append("系统依赖安装失败，请检查 Homebrew 是否正常工作。")
            suggestions.append("可尝试在终端执行: brew doctor")
        }
        
        return suggestions
    }
}

#Preview {
    RubyPackagesView()
}

// MARK: - 安装进度弹窗

struct InstallProgressSheet: View {
    let version: String
    let isInstalling: Bool
    let output: String
    let isSuccess: Bool
    let error: String?
    let canRetryWithCompile: Bool
    let canAutoFix: Bool
    let onDismiss: () -> Void
    let onCancel: (() -> Void)?
    let onRetryCompile: (() -> Void)?
    let onAutoFix: (() -> Void)?
    
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: isInstalling ? "arrow.down.circle" : (isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"))
                    .font(.title2)
                    .foregroundColor(isInstalling ? .accentColor : (isSuccess ? .green : .red))
                
                Text(isInstalling ? "正在安装 Ruby \(version)" : (isSuccess ? "安装完成" : "安装失败"))
                    .font(.headline)
                
                Spacer()
                
                if !isInstalling {
                    if canAutoFix {
                        Button("自动修复并重试") {
                            onAutoFix?()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        
                        Button("关闭") {
                            onDismiss()
                        }
                        .buttonStyle(.bordered)
                    } else if canRetryWithCompile {
                        Button("重试用编译安装") {
                            onRetryCompile?()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        
                        Button("关闭") {
                            onDismiss()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("完成") {
                            onDismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("取消") {
                        onCancel?()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 输出区域
            ScrollViewReader { proxy in
                ScrollView {
                    Text(output.isEmpty ? "准备安装..." : output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("bottom")
                        .onChange(of: output) { _ in
                            if autoScroll {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .padding(16)
            }
            
            // 进度指示
            if isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("正在编译安装，请耐心等待...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 14)
            }
        }
        .frame(width: 560, height: 420)
    }
}
