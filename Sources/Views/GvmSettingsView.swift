import SwiftUI

// MARK: - GVM 设置视图

struct GvmSettingsView: View {
    @StateObject private var viewModel = GvmSettingsViewModel()
    @State private var showingUninstallAlert = false
    @State private var selectedConfigFile = ".zshrc"
    @State private var showingConfigResult = false
    @State private var configResultMessage = ""
    @State private var isInstallingGvm = false
    @State private var installOutput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // gvm 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isGvmAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isGvmAvailable ? .green : .red)

                        VStack(alignment: .leading) {
                            Text(viewModel.isGvmAvailable ? "gvm 已安装" : "gvm 未安装")
                                .font(.headline)
                            Text(viewModel.isGvmAvailable ? "Go Version Manager 运行正常" : "点击下方按钮安装")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !viewModel.isGvmAvailable {
                            Button(action: {
                                isInstallingGvm = true
                                installOutput = "📦 开始安装 gvm...\n\n"
                                Task {
                                    let result = await viewModel.service.installGvm { output in
                                        Task { @MainActor in
                                            installOutput += output + "\n"
                                        }
                                    }
                                    isInstallingGvm = false
                                    switch result {
                                    case .success:
                                        installOutput += "\n✅ 安装成功"
                                        await viewModel.load()
                                    case .failure(let error):
                                        installOutput += "\n❌ 安装失败: \(error)"
                                    }
                                }
                            }) {
                                if isInstallingGvm {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                    Text("安装中...")
                                        .font(.caption)
                                } else {
                                    Label("安装 gvm", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInstallingGvm)
                        } else {
                            Button(role: .destructive, action: {
                                showingUninstallAlert = true
                            }) {
                                Label("卸载 gvm", systemImage: "trash")
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

                if viewModel.isGvmAvailable {
                    // 安装信息
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(title: "安装路径", value: viewModel.gvmPath)
                            InfoRow(title: "gvm 版本", value: viewModel.gvmVersion)
                            InfoRow(title: "默认 Go 版本", value: viewModel.defaultGoVersion)
                            InfoRow(title: "已安装数量", value: "\(viewModel.installedCount)")
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                    } header: {
                        Text("安装信息")
                            .font(.headline)
                    }

                    // 环境变量配置
                    Section {
                        HStack {
                            Label("环境变量配置", systemImage: "gearshape")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if viewModel.isEnvConfigured {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 8, height: 8)
                                    Text("已配置")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 8, height: 8)
                                    Text("未配置")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.bottom, 4)

                        Text("gvm 需要在 Shell 配置文件中设置环境变量才能正常工作。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 12)

                        // 配置文件检测
                        VStack(alignment: .leading, spacing: 8) {
                            Text("配置文件检测")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ForEach(viewModel.configuredFiles, id: \.file) { item in
                                HStack {
                                    Text(item.file)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 100, alignment: .leading)

                                    if item.hasConfig {
                                        Label("已配置", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Label("未配置", systemImage: "circle")
                                            .font(.caption)
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.bottom, 12)

                        // 选择目标文件
                        VStack(alignment: .leading, spacing: 8) {
                            Text("写入配置到")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Picker("配置文件", selection: $selectedConfigFile) {
                                Text(".zshrc").tag(".zshrc")
                                Text(".zshenv").tag(".zshenv")
                                Text(".bash_profile").tag(".bash_profile")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        // 操作按钮
                        HStack(spacing: 12) {
                            Button(action: {
                                Task { await applyConfig() }
                            }) {
                                Label("一键配置", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                Task { await removeConfig() }
                            }) {
                                Label("移除配置", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    } header: {
                        Text("环境变量配置")
                            .font(.headline)
                    }
                }

                // 关于
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(title: "工具", value: "Go Version Manager (gvm)")
                        InfoRow(title: "版本", value: "1.0.0")
                        InfoRow(title: "兼容系统", value: "macOS 13.0+")
                        InfoRow(title: "安装方式", value: "官方脚本")
                        InfoRow(title: "项目地址", value: "github.com/moovweb/gvm")
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("关于")
                        .font(.headline)
                }
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
                Task { await viewModel.uninstallGvm() }
            }
        } message: {
            Text("确定要卸载 gvm 吗？这将同时移除所有已安装的 Go 版本和环境变量配置。此操作不可撤销！")
        }
        .sheet(isPresented: $showingConfigResult) {
            VStack(spacing: 16) {
                Text("配置结果")
                    .font(.headline)

                ScrollView {
                    Text(configResultMessage)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)

                Button("关闭") { showingConfigResult = false }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(width: 520, height: 300)
        }
        .sheet(isPresented: .constant(isInstallingGvm || !installOutput.isEmpty)) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: isInstallingGvm ? "arrow.down.circle" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(isInstallingGvm ? .accentColor : .green)
                    Text(isInstallingGvm ? "正在安装 gvm" : "安装完成")
                        .font(.headline)
                    Spacer()
                    if !isInstallingGvm {
                        Button("关闭") { installOutput = "" }
                            .buttonStyle(.borderedProminent)
                    }
                }

                ScrollView {
                    ScrollViewReader { proxy in
                        Text(installOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("bottom")
                            .onChange(of: installOutput) { _ in
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                    }
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            .padding(24)
            .frame(width: 560, height: 420)
        }
    }

    private func applyConfig() async {
        let result = await viewModel.configureEnv(to: selectedConfigFile)
        switch result {
        case .success(let msg):
            configResultMessage = "\(msg)\n\n请重启终端使配置生效。"
        case .failure(let error):
            configResultMessage = "配置失败: \(error)"
        }
        showingConfigResult = true
    }

    private func removeConfig() async {
        let result = await viewModel.removeEnvConfig(from: selectedConfigFile)
        switch result {
        case .success(let msg):
            configResultMessage = "\(msg)\n\n建议重启终端使配置生效。"
        case .failure(let error):
            configResultMessage = "移除失败: \(error)"
        }
        showingConfigResult = true
    }
}

// MARK: - ViewModel

@MainActor
class GvmSettingsViewModel: ObservableObject {
    @Published var isGvmAvailable = false
    @Published var gvmPath = "未知"
    @Published var gvmVersion = "未知"
    @Published var defaultGoVersion = "未设置"
    @Published var installedCount = 0
    @Published var isEnvConfigured = false
    @Published var configuredFiles: [(file: String, hasConfig: Bool)] = []

    let service = GvmService.shared

    func load() async {
        isGvmAvailable = service.checkGvmAvailable()
        guard isGvmAvailable else { return }

        gvmPath = service.getGvmPath()
        isEnvConfigured = service.isGvmConfigured()
        configuredFiles = service.getConfiguredFiles()

        async let versions = service.listInstalledVersions()
        async let ver = service.getGvmVersion()

        let vers = await versions
        gvmVersion = await ver
        installedCount = vers.count
        defaultGoVersion = vers.first(where: { $0.isActive })?.version ?? "未设置"
    }

    func uninstallGvm() async {
        _ = await service.uninstallGvm()
        await load()
    }

    func configureEnv(to fileName: String) async -> OperationResult {
        let result = await service.configureShell(to: fileName)
        await load()
        return result
    }

    func removeEnvConfig(from fileName: String) async -> OperationResult {
        let result = await service.removeShellConfig(from: fileName)
        await load()
        return result
    }
}

#Preview {
    GvmSettingsView()
}

// MARK: - 辅助视图

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
