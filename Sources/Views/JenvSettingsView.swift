import SwiftUI

struct JenvSettingsView: View {
    @StateObject private var viewModel = JenvSettingsViewModel()
    @State private var showingUninstallAlert = false
    @State private var showingInstallProgress = false
    @State private var showingConfigureAlert = false
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var showingPluginResult = false
    @State private var pluginResultText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusSection
                if viewModel.isJenvAvailable {
                    installInfoSection
                    pluginSection
                    envConfigSection
                }
                aboutSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await viewModel.load()
        }
        .alert("卸载确认", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                Task { await viewModel.uninstallJenv() }
            }
        } message: {
            Text("确定要完全卸载 jenv 吗？已注册的 Java 版本配置将会丢失。")
        }
        .alert("配置 jenv 环境变量", isPresented: $showingConfigureAlert) {
            Button("取消", role: .cancel) {}
            Button("写入 ~/.zshrc") {
                Task {
                    let result = await viewModel.configureShell()
                    commandResultText = result.successValue.isEmpty ? "配置失败" : result.successValue
                    showingCommandResult = true
                    await viewModel.load()
                }
            }
        } message: {
            Text("将在 ~/.zshrc 中添加 jenv 初始化配置，使终端中可以使用 jenv 命令。")
        }
        .alert("操作结果", isPresented: $showingCommandResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(commandResultText)
        }
        .alert("插件操作结果", isPresented: $showingPluginResult) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(pluginResultText)
        }
        .sheet(isPresented: $showingInstallProgress) {
            VStack(spacing: 16) {
                Text("安装 jenv")
                    .font(.headline)

                ScrollView {
                    Text(viewModel.installOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)

                if viewModel.isInstalling {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("安装中...")
                    }
                    Button("取消安装") {
                        viewModel.cancelInstall()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("关闭") {
                        showingInstallProgress = false
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 550, height: 420)
        }
    }

    // MARK: - 状态

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: viewModel.isJenvAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(viewModel.isJenvAvailable ? .green : .red)

                VStack(alignment: .leading) {
                    Text(viewModel.isJenvAvailable ? "jenv 已安装" : "jenv 未安装")
                        .font(.headline)
                    Text(viewModel.isJenvAvailable ? "可以正常使用" : "请先安装 jenv")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.isJenvAvailable {
                    Button(action: {
                        showingInstallProgress = true
                        Task { await viewModel.installJenv() }
                    }) {
                        Label("安装 jenv", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive, action: {
                        showingUninstallAlert = true
                    }) {
                        Label("卸载 jenv", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        } header: {
            Text("状态")
                .font(.headline)
        }
    }

    // MARK: - 安装信息

    @ViewBuilder
    private var installInfoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(title: "安装路径", value: viewModel.jenvPath)
                InfoRow(title: "jenv 版本", value: viewModel.jenvVersion)
                InfoRow(title: "全局 Java", value: viewModel.globalVersion)
                InfoRow(title: "已注册版本", value: "\(viewModel.registeredCount)")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        } header: {
            Text("安装信息")
                .font(.headline)
        }
    }

    // MARK: - 插件管理

    @ViewBuilder
    private var pluginSection: some View {
        Section {
            VStack(spacing: 12) {
                ForEach(viewModel.plugins, id: \.self) { plugin in
                    let isEnabled = viewModel.enabledPlugins.contains(plugin)
                    HStack {
                        Label(plugin, systemImage: isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isEnabled ? .green : .secondary)

                        Spacer()

                        Button(action: {
                            Task {
                                let result: OperationResult
                                if isEnabled {
                                    result = await viewModel.disablePlugin(plugin)
                                } else {
                                    result = await viewModel.enablePlugin(plugin)
                                }
                                pluginResultText = result.successValue.isEmpty
                                    ? (result.failureValue ?? "操作失败")
                                    : result.successValue
                                showingPluginResult = true
                                await viewModel.load()
                            }
                        }) {
                            Text(isEnabled ? "禁用" : "启用")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                }

                if viewModel.plugins.isEmpty {
                    Text("正在加载插件列表...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
        } header: {
            Text("插件")
                .font(.headline)
        }
    }

    // MARK: - 环境配置

    @ViewBuilder
    private var envConfigSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("jenv 需要在 Shell 配置文件中初始化才能在终端中使用。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("以下内容将被添加到 ~/.zshrc:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("""
                export PATH="$HOME/.jenv/bin:$PATH"
                eval "$(jenv init -)"
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)

                HStack {
                    if viewModel.isEnvConfigured {
                        Label("环境已配置", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    Spacer()
                    Button(action: { showingConfigureAlert = true }) {
                        Label("写入配置", systemImage: "doc.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        } header: {
            Text("环境配置")
                .font(.headline)
        }
    }

    // MARK: - 关于

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "版本", value: "1.0.0")
                InfoRow(title: "兼容系统", value: "macOS 13.0+")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        } header: {
            Text("关于")
                .font(.headline)
        }
    }
}

// MARK: - ViewModel

@MainActor
class JenvSettingsViewModel: ObservableObject {
    @Published var isJenvAvailable = false
    @Published var isEnvConfigured = false
    @Published var jenvVersion = "未知"
    @Published var jenvPath = "未知"
    @Published var globalVersion = "未知"
    @Published var registeredCount = 0
    @Published var plugins: [String] = []
    @Published var enabledPlugins: [String] = []

    // 安装进度
    @Published var isInstalling = false
    @Published var installOutput = ""

    private let service = JenvService.shared

    func load() async {
        isJenvAvailable = service.checkJenvAvailable()
        jenvPath = service.getJenvPath()

        if isJenvAvailable {
            async let ver = service.getJenvVersion()
            async let envConf = service.isJenvConfigured()
            async let globalVer = service.getGlobalVersion()
            async let versions = service.listVersions()
            async let availablePlugins = service.getAvailablePlugins()
            async let enabled = service.getEnabledPlugins()

            jenvVersion = await ver
            isEnvConfigured = await envConf
            globalVersion = await globalVer
            registeredCount = (await versions).count
            plugins = await availablePlugins
            enabledPlugins = await enabled
        }
    }

    func installJenv() async {
        isInstalling = true
        installOutput = "开始安装 jenv...\n\n"

        let result = await service.installJenv { [weak self] output in
            Task { @MainActor in
                self?.installOutput += output + "\n"
            }
        }

        switch result {
        case .success:
            installOutput += "\n安装完成"
        case .failure(let error):
            installOutput += "\n安装失败: \(error)"
        }

        isInstalling = false
    }

    func cancelInstall() {
        service.cancelCurrentInstall()
        installOutput += "\n\n安装已取消"
        isInstalling = false
    }

    func uninstallJenv() async {
        _ = await service.uninstallJenv()
        await load()
    }

    func configureShell() async -> OperationResult {
        return await service.configureShell()
    }

    func enablePlugin(_ plugin: String) async -> OperationResult {
        return await service.enablePlugin(plugin)
    }

    func disablePlugin(_ plugin: String) async -> OperationResult {
        return await service.disablePlugin(plugin)
    }
}

// MARK: - OperationResult 辅助

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

private extension OperationResult {
    var failureValue: String? {
        if case .failure(let value) = self { return value }
        return nil
    }
}

#Preview {
    JenvSettingsView()
}
