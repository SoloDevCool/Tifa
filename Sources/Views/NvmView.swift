import SwiftUI

struct NvmView: View {
    @StateObject private var viewModel = NvmViewModel()
    @State private var searchText = ""
    @State private var selectedVersion: NvmNodeVersion?
    @State private var showingInstallSheet = false
    @State private var showingUninstallAlert = false
    @State private var versionToUninstall: NvmNodeVersion?
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var showingNodeInstallOutput = false
    @State private var nodeInstallOutput = ""
    @State private var isInstallingNode = false
    
    var filteredVersions: [NvmNodeVersion] {
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
                        .fill(viewModel.isAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isAvailable ? "nvm 已安装" : "nvm 未安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.defaultVersion != "无" && viewModel.defaultVersion != "N/A" {
                    Text("默认: \(viewModel.defaultVersion)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                if !viewModel.versions.isEmpty {
                    Text("\(viewModel.versions.count) 个版本")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if !viewModel.isAvailable && !viewModel.isInstalling && viewModel.installResult == nil {
                // 未安装
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "internaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("NVM 未安装")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("NVM (Node Version Manager) 用于管理多个 Node.js 版本")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("点击下方按钮通过 Homebrew 安装")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button(action: { Task { await viewModel.install() } }) {
                        Label("安装 NVM", systemImage: "arrow.down.circle.fill")
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.isInstalling || viewModel.installResult != nil {
                // 安装中 / 结果
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if viewModel.isInstalling {
                            ProgressView().controlSize(.small)
                            Text("正在安装 NVM...")
                                .font(.subheadline)
                        } else if case .success = viewModel.installResult {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("安装完成").font(.subheadline).foregroundColor(.green)
                        } else if case .failure = viewModel.installResult {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            Text("安装失败").font(.subheadline).foregroundColor(.red)
                        }
                        Spacer()
                        if viewModel.installResult != nil {
                            if case .failure(let error) = viewModel.installResult,
                               error.lowercased().contains("locked") {
                                Button(action: { Task { await viewModel.cleanupAndRetry() } }) {
                                    Label("一键修复并重试", systemImage: "wrench")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            Button("关闭") { viewModel.dismissInstall() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(viewModel.installOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .id("outputBottom")
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: viewModel.installOutput) { _ in
                            withAnimation { proxy.scrollTo("outputBottom", anchor: .bottom) }
                        }
                    }
                }
            } else {
                // 工具栏
                HStack {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    
                    Spacer()
                    
                    Button(action: { showingInstallSheet = true }) {
                        Label("安装版本", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
                
                // 版本列表
                if viewModel.isLoading && viewModel.versions.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.versions.isEmpty {
                    EmptyStateView(
                        title: "暂无已安装的 Node.js 版本",
                        systemImage: "cube",
                        description: "点击「安装版本」安装 Node.js"
                    )
                } else {
                    HStack {
                        TextField("搜索版本...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    
                    List(selection: $selectedVersion) {
                        ForEach(filteredVersions) { version in
                            HStack {
                                Image(systemName: version.isDefault ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(version.isDefault ? .green : .secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(version.version)
                                        .font(.headline)
                                    
                                    HStack(spacing: 12) {
                                        if version.isDefault {
                                            Text("默认")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                        Text(version.isInstalled ? "已安装" : "未安装")
                                            .font(.caption)
                                            .foregroundColor(version.isInstalled ? .secondary : .orange)
                                    }
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    if version.isInstalled && !version.isDefault {
                                        Button(action: {
                                            Task {
                                                let result = await viewModel.setDefault(version.version)
                                                switch result {
                                                case .success:
                                                    commandResultText = "已将 \(version.version) 设为默认版本"
                                                    showingCommandResult = true
                                                    await viewModel.refresh()
                                                case .failure(let error):
                                                    commandResultText = error
                                                    showingCommandResult = true
                                                }
                                            }
                                        }) {
                                            Label("设为默认", systemImage: "star")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)
                                        .help("设为默认版本")
                                    }
                                    
                                    if version.isInstalled {
                                        Button(action: {
                                            Task {
                                                let packages = await viewModel.getGlobalPackages(version: version.version)
                                                commandResultText = "全局 npm 包 (\(version.version)):\n\(packages)"
                                                showingCommandResult = true
                                            }
                                        }) {
                                            Label("全局包", systemImage: "shippingbox")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)
                                        .help("查看全局 npm 包")
                                        
                                        Button(action: {
                                            versionToUninstall = version
                                            showingUninstallAlert = true
                                        }) {
                                            Label("卸载", systemImage: "trash")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.bordered)
                                        .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(version)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .alert("卸载版本", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let version = versionToUninstall {
                    Task {
                        let result = await viewModel.uninstallVersion(version.version)
                        switch result {
                        case .success:
                            await viewModel.refresh()
                        case .failure(let error):
                            commandResultText = error
                            showingCommandResult = true
                        }
                    }
                }
            }
        } message: {
            Text("确定要卸载 Node.js \(versionToUninstall?.version ?? "") 吗？")
        }
        .sheet(isPresented: $showingInstallSheet) {
            NvmInstallView(viewModel: viewModel, showing: $showingInstallSheet)
        }
        .sheet(isPresented: $showingCommandResult) {
            VStack(spacing: 16) {
                HStack {
                    Text("操作结果").font(.headline)
                    Spacer()
                    Button("关闭") { showingCommandResult = false }
                }
                ScrollView {
                    Text(commandResultText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                Button("关闭") { showingCommandResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 500, height: 350)
        }
    }
}

// MARK: - 安装版本 Sheet

struct NvmInstallView: View {
    @ObservedObject var viewModel: NvmViewModel
    @Binding var showing: Bool
    @State private var customVersion = ""
    @State private var remoteVersions: [String] = []
    @State private var isLoadingRemote = false
    @State private var searchText = ""
    @State private var isInstalling = false
    @State private var installOutput = ""
    
    var filteredRemote: [String] {
        if searchText.isEmpty { return remoteVersions }
        return remoteVersions.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("安装 Node.js 版本")
                    .font(.headline)
                Spacer()
                Button("关闭") { showing = false }
            }
            
            if isInstalling {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在安装 Node.js...")
                        .font(.subheadline)
                }
                .padding()
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(installOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("installOutputBottom")
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: installOutput) { _ in
                        withAnimation { proxy.scrollTo("installOutputBottom", anchor: .bottom) }
                    }
                }
            } else {
                // 自定义版本输入
                VStack(alignment: .leading, spacing: 8) {
                    Text("输入版本号")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("例如: v20.11.0", text: $customVersion)
                            .textFieldStyle(.roundedBorder)
                        Button("安装") {
                            guard !customVersion.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            installVersion(customVersion.trimmingCharacters(in: .whitespaces))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customVersion.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                
                Divider()
                
                // 远程 LTS 版本列表
                HStack {
                    Text("可用的 LTS 版本")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if isLoadingRemote {
                        ProgressView().controlSize(.small)
                    }
                    Button(action: { Task { await loadRemoteVersions() } }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredRemote, id: \.self) { version in
                            HStack {
                                Image(systemName: viewModel.versions.contains(where: { $0.version == version }) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.versions.contains(where: { $0.version == version }) ? .green : .secondary)
                                    .font(.caption)
                                Text(version)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                if viewModel.versions.contains(where: { $0.version == version }) {
                                    Text("已安装")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Button("安装") {
                                        installVersion(version)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 550, height: 450)
        .task {
            await loadRemoteVersions()
        }
    }
    
    private func loadRemoteVersions() async {
        isLoadingRemote = true
        remoteVersions = await viewModel.service.listRemoteVersions()
        isLoadingRemote = false
    }
    
    private func installVersion(_ version: String) {
        let v = version.hasPrefix("v") ? version : "v\(version)"
        isInstalling = true
        installOutput = ""
        showing = false
        
        Task {
            let _ = await viewModel.installNodeVersion(version: v) { output in
                installOutput += output
            }
            isInstalling = false
            
            // 用 sheet 显示安装进度（需要 parent view 支持）
            await viewModel.refresh()
        }
    }
}

// MARK: - ViewModel

@MainActor
class NvmViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isEnvConfigured = false
    @Published var defaultVersion = ""
    @Published var nvmVersion = ""
    @Published var versions: [NvmNodeVersion] = []
    @Published var isLoading = false
    
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installResult: OperationResult?
    
    let service = NvmService.shared
    
    func load() async {
        guard !isInstalling else { return }
        
        isAvailable = service.checkNvmAvailable()
        guard isAvailable else { return }
        
        isLoading = true
        
        async let nvmVer = service.getNvmVersion()
        async let defaultVer = service.getDefaultVersion()
        async let envConfigured = service.isNvmConfigured()
        async let installedVersions = service.listInstalledVersions()
        
        nvmVersion = await nvmVer
        defaultVersion = await defaultVer
        isEnvConfigured = await envConfigured
        versions = await installedVersions
        
        isLoading = false
    }
    
    func refresh() async { await load() }
    
    func install() async {
        isInstalling = true
        installOutput = ""
        installResult = nil
        
        let result = await service.installNvm { [weak self] output in
            self?.installOutput += output
        }
        
        installResult = result
        isInstalling = false
        
        if case .success = result {
            installOutput += "\n✅ NVM 安装成功！\n"
            installOutput += "提示: 请在终端中重启或运行以下命令使 NVM 生效:\n"
            installOutput += "  source ~/.zshrc\n"
        }
    }
    
    func cleanupAndRetry() async {
        installOutput += "\n🔧 正在清理锁文件...\n"
        let script = """
        find ~/Library/Caches/Homebrew/downloads -name "*.incomplete" -delete 2>/dev/null
        find ~/Library/Caches/Homebrew -name "*.lock" -delete 2>/dev/null
        echo "✅ 锁文件已清理"
        """
        
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<OperationResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(output))
                    } else {
                        continuation.resume(returning: .failure("清理失败"))
                    }
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
        
        switch result {
        case .success(let msg):
            installOutput += msg + "\n🔄 正在重新安装...\n"
            let _ = await install()
        case .failure(let error):
            installOutput += "❌ 清理失败: \(error)\n"
            installResult = .failure("清理失败: \(error)")
        }
    }
    
    func dismissInstall() {
        if case .success = installResult {
            installResult = nil
            installOutput = ""
            Task { await load() }
        } else {
            installResult = nil
            installOutput = ""
        }
    }
    
    func setDefault(_ version: String) async -> OperationResult {
        let result = await service.setDefaultVersion(version: version)
        return result
    }
    
    func uninstallVersion(_ version: String) async -> OperationResult {
        return await service.uninstallNodeVersion(version: version)
    }
    
    func getGlobalPackages(version: String) async -> String {
        return await service.getGlobalPackages(for: version)
    }
    
    func installNodeVersion(version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        return await service.installNodeVersion(version: version, onOutput: onOutput)
    }
}

#Preview {
    NvmView()
}
