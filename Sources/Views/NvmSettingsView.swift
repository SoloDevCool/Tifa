import SwiftUI

struct NvmSettingsView: View {
    @StateObject private var viewModel = NvmSettingsViewModel()
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var showingConfigureAlert = false
    @State private var diskUsage = "未知"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // NVM 状态卡片
                statusCard
                
                // 环境配置卡片
                envConfigCard
                
                // 存储信息卡片
                storageCard
                
                // NVM 配置文件
                configFileCard
            }
            .padding(24)
        }
        .task {
            await viewModel.load()
        }
        .alert("操作结果", isPresented: $showingCommandResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(commandResultText)
        }
    }
    
    // MARK: - 状态卡片
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("NVM 状态", systemImage: "info.circle")
                .font(.headline)
            
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("安装状态")
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isAvailable ? "已安装" : "未安装")
                    }
                }
                
                GridRow {
                    Text("NVM 版本")
                        .foregroundColor(.secondary)
                    Text(viewModel.nvmVersion)
                }
                
                GridRow {
                    Text("默认版本")
                        .foregroundColor(.secondary)
                    Text(viewModel.defaultVersion)
                }
                
                GridRow {
                    Text("NVM 目录")
                        .foregroundColor(.secondary)
                    Text(viewModel.nvmDir)
                        .font(.system(.caption, design: .monospaced))
                }
                
                GridRow {
                    Text("安装路径")
                        .foregroundColor(.secondary)
                    Text(viewModel.nvmScriptPath)
                        .font(.system(.caption, design: .monospaced))
                }
                
                GridRow {
                    Text("Shell 配置")
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isEnvConfigured ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isEnvConfigured ? "已配置" : "未配置")
                        if !viewModel.isEnvConfigured && viewModel.isAvailable {
                            Button("配置") { showingConfigureAlert = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .alert("配置 NVM 环境变量", isPresented: $showingConfigureAlert) {
            Button("取消", role: .cancel) {}
            Button("写入 ~/.zshrc") {
                Task { await viewModel.configureShell() }
            }
        } message: {
            Text("将在 ~/.zshrc 中添加 NVM 初始化配置，使终端中可以使用 nvm 命令。")
        }
    }
    
    // MARK: - 环境配置卡片
    
    private var envConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("环境配置", systemImage: "gearshape")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("NVM 需要在 Shell 配置文件中初始化才能在终端中使用。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("以下内容将被添加到 ~/.zshrc:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("""
                export NVM_DIR="$HOME/Library/Application Support/nvm"
                [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \\. "/opt/homebrew/opt/nvm/nvm.sh"
                [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \\. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }
            
            HStack {
                if viewModel.isEnvConfigured {
                    Label("环境已配置", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                Spacer()
                Button(action: {
                    Task {
                        let result = await viewModel.configureShell()
                        commandResultText = result.successValue.isEmpty ? "配置失败" : result.successValue
                        showingCommandResult = true
                        await viewModel.load()
                    }
                }) {
                    Label("写入配置", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isAvailable)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - 存储信息卡片
    
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("存储信息", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task {
                        diskUsage = await viewModel.service.getVersionsDiskUsage()
                    }
                }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("已安装版本数")
                        .foregroundColor(.secondary)
                    Text("\(viewModel.installedCount)")
                }
                
                GridRow {
                    Text("占用空间")
                        .foregroundColor(.secondary)
                    Text(diskUsage)
                }
            }
            
            if !viewModel.versions.isEmpty {
                Divider()
                
                Text("已安装的版本:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.versions) { version in
                        HStack {
                            Text(version.version)
                                .font(.system(.caption, design: .monospaced))
                            if version.isDefault {
                                Text("(默认)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - 配置文件卡片
    
    private var configFileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("NVM 信息", systemImage: "doc.text")
                .font(.headline)
            
            HStack {
                Text("NVM_DIR:")
                    .foregroundColor(.secondary)
                Text(viewModel.nvmDir)
                    .font(.system(.caption, design: .monospaced))
            }
            
            HStack {
                Text("nvm.sh:")
                    .foregroundColor(.secondary)
                Text(viewModel.nvmScriptPath)
                    .font(.system(.caption, design: .monospaced))
            }
            
            if !viewModel.nvmBashCompletion.isEmpty {
                HStack {
                    Text("补全脚本:")
                        .foregroundColor(.secondary)
                    Text(viewModel.nvmBashCompletion)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - ViewModel

@MainActor
class NvmSettingsViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isEnvConfigured = false
    @Published var nvmVersion = ""
    @Published var defaultVersion = ""
    @Published var nvmDir = ""
    @Published var nvmScriptPath = ""
    @Published var nvmBashCompletion = ""
    @Published var versions: [NvmNodeVersion] = []
    @Published var installedCount = 0
    
    let service = NvmService.shared
    
    func load() async {
        isAvailable = service.checkNvmAvailable()
        
        if isAvailable {
            async let nvmVer = service.getNvmVersion()
            async let defVer = service.getDefaultVersion()
            async let envConf = service.isNvmConfigured()
            async let installed = service.listInstalledVersions()
            
            nvmVersion = await nvmVer
            defaultVersion = await defVer
            isEnvConfigured = await envConf
            versions = await installed
            installedCount = versions.filter { $0.isInstalled }.count
        }
        
        nvmDir = NSHomeDirectory() + "/Library/Application Support/nvm"
        
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        nvmScriptPath = "\(brewPrefix)/opt/nvm/nvm.sh"
        
        let completionPath = "\(brewPrefix)/opt/nvm/etc/bash_completion.d/nvm"
        nvmBashCompletion = FileManager.default.fileExists(atPath: completionPath) ? completionPath : ""
    }
    
    /// 配置 shell 环境变量
    func configureShell() async -> OperationResult {
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        
        let configBlock = """

        # NVM (Node Version Manager)
        export NVM_DIR="$HOME/Library/Application Support/nvm"
        [ -s "\(brewPrefix)/opt/nvm/nvm.sh" ] && \\. "\(brewPrefix)/opt/nvm/nvm.sh"
        [ -s "\(brewPrefix)/opt/nvm/etc/bash_completion.d/nvm" ] && \\. "\(brewPrefix)/opt/nvm/etc/bash_completion.d/nvm"
        """
        
        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        
        // 检查是否已有配置
        if FileManager.default.fileExists(atPath: zshrcPath),
           let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
           content.contains("NVM_DIR") {
            return .success("NVM 配置已存在于 ~/.zshrc")
        }
        
        // 追加配置
        if var content = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) {
            content += configBlock
            do {
                try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
                return .success("已将 NVM 配置写入 ~/.zshrc\n\n请重启终端或运行: source ~/.zshrc")
            } catch {
                return .failure("写入失败: \(error.localizedDescription)")
            }
        } else {
            do {
                try configBlock.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
                return .success("已创建 ~/.zshrc 并写入 NVM 配置\n\n请重启终端或运行: source ~/.zshrc")
            } catch {
                return .failure("创建文件失败: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    NvmSettingsView()
}
