import SwiftUI

// MARK: - Rustup 设置视图

struct RustupSettingsView: View {
    @StateObject private var viewModel = RustupSettingsViewModel()
    @State private var showingUninstallAlert = false
    @State private var showingUpdateAlert = false
    @State private var selectedConfigFile = ".zshrc"
    @State private var showingConfigResult = false
    @State private var configResultMessage = ""
    @State private var isInstalling = false
    @State private var isInstallingRustup = false
    @State private var installOutput = ""
    @State private var diskUsage = "未知"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // rustup 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isRustupAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isRustupAvailable ? .green : .red)

                        VStack(alignment: .leading) {
                            Text(viewModel.isRustupAvailable ? "rustup 已安装" : "rustup 未安装")
                                .font(.headline)
                            Text(viewModel.isRustupAvailable ? "可以正常使用" : "点击下方按钮安装")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !viewModel.isRustupAvailable {
                            Button(action: {
                                isInstallingRustup = true
                                installOutput = "📦 开始安装 rustup...\n\n"
                                Task {
                                    let result = await viewModel.service.installRustup { output in
                                        Task { @MainActor in
                                            installOutput += output + "\n"
                                        }
                                    }
                                    isInstallingRustup = false
                                    switch result {
                                    case .success:
                                        installOutput += "\n✅ 安装成功"
                                        await viewModel.load()
                                    case .failure(let error):
                                        installOutput += "\n❌ 安装失败: \(error)"
                                    }
                                }
                            }) {
                                if isInstallingRustup {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                    Text("安装中...")
                                        .font(.caption)
                                } else {
                                    Label("安装 rustup", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInstallingRustup)
                        } else {
                            Button(role: .destructive, action: {
                                showingUninstallAlert = true
                            }) {
                                Label("卸载 rustup", systemImage: "trash")
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

                if viewModel.isRustupAvailable {
                    // 安装信息
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(title: "安装路径", value: viewModel.rustupPath)
                            InfoRow(title: "rustup 版本", value: viewModel.rustupVersion)
                            InfoRow(title: "默认工具链", value: viewModel.defaultToolchain)
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

                        Text("rustup 需要在 Shell 配置文件中设置环境变量才能正常工作。")
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
                                Text(".zprofile").tag(".zprofile")
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

                    // 存储信息
                    Section {
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

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("已安装工具链数")
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.installedCount)")
                            }

                            HStack {
                                Text("占用空间")
                                    .foregroundColor(.secondary)
                                Text(diskUsage)
                            }

                            HStack {
                                Text("RUSTUP_HOME")
                                    .foregroundColor(.secondary)
                                Text(viewModel.rustupHome)
                                    .font(.system(.caption, design: .monospaced))
                            }

                            HStack {
                                Text("CARGO_HOME")
                                    .foregroundColor(.secondary)
                                Text(viewModel.cargoHome)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    } header: {
                        Text("存储信息")
                            .font(.headline)
                    }

                    // 维护操作
                    Section {
                        VStack(spacing: 12) {
                            Button(action: { showingUpdateAlert = true }) {
                                HStack {
                                    Label("更新 rustup", systemImage: "arrow.triangle.2.circlepath")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("维护")
                            .font(.headline)
                    }
                }

                // 关于
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(title: "版本", value: "1.0.0")
                        InfoRow(title: "兼容系统", value: "macOS 13.0+")
                        InfoRow(title: "安装方式", value: "官方脚本")
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
                Task { await viewModel.uninstallRustup() }
            }
        } message: {
            Text("确定要卸载 rustup 吗？这将同时移除所有已安装的 Rust 工具链和环境变量配置。此操作不可撤销！")
        }
        .alert("更新确认", isPresented: $showingUpdateAlert) {
            Button("取消", role: .cancel) {}
            Button("更新") {
                Task { await viewModel.updateRustup() }
            }
        } message: {
            Text("这将更新 rustup 到最新版本。确定要继续吗？")
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
        .sheet(isPresented: .constant(isInstallingRustup || !installOutput.isEmpty)) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: isInstallingRustup ? "arrow.down.circle" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(isInstallingRustup ? .accentColor : .green)
                    Text(isInstallingRustup ? "正在安装 rustup" : "安装完成")
                        .font(.headline)
                    Spacer()
                    if !isInstallingRustup {
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
class RustupSettingsViewModel: ObservableObject {
    @Published var isRustupAvailable = false
    @Published var rustupPath = "未知"
    @Published var rustupVersion = "未知"
    @Published var defaultToolchain = "未设置"
    @Published var installedCount = 0
    @Published var isEnvConfigured = false
    @Published var configuredFiles: [(file: String, hasConfig: Bool)] = []
    @Published var rustupHome = ""
    @Published var cargoHome = ""

    let service = RustupService.shared

    func load() async {
        isRustupAvailable = service.checkRustupAvailability()
        guard isRustupAvailable else { return }

        rustupPath = service.getRustupPath()
        isEnvConfigured = service.isRustupEnvConfigured()
        configuredFiles = service.getConfiguredFiles()
        rustupHome = NSHomeDirectory() + "/.rustup"
        cargoHome = NSHomeDirectory() + "/.cargo"

        async let versions = service.listInstalledVersions()
        async let defaultTool = service.getDefaultVersion()
        async let ver = service.getRustupVersion()

        let vers = await versions
        defaultToolchain = await defaultTool
        installedCount = vers.count
        rustupVersion = await ver
    }

    func uninstallRustup() async {
        _ = await service.uninstallRustup()
        await load()
    }

    func configureEnv(to fileName: String) async -> OperationResult {
        let result = await service.configureRustupEnv(to: fileName)
        await load()
        return result
    }

    func removeEnvConfig(from fileName: String) async -> OperationResult {
        let result = await service.removeRustupEnvConfig(from: fileName)
        await load()
        return result
    }

    func updateRustup() async {
        _ = await service.updateRustup()
        await load()
    }
}

#Preview {
    RustupSettingsView()
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
