import SwiftUI

// MARK: - RVM 设置视图

struct RVMSettingsView: View {
    @StateObject private var viewModel = RVMSettingsViewModel()
    @State private var showingUninstallAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusSection
                if viewModel.isRVMAvailable {
                    installInfoSection
                    maintenanceSection
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
                Task { await viewModel.uninstallRVM() }
            }
        } message: {
            Text("确定要完全卸载 RVM 及所有已安装的 Ruby 版本吗？此操作不可撤销！")
        }
        .alert("清理确认", isPresented: $viewModel.showingCleanupAlert) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task { await viewModel.cleanup() }
            }
        } message: {
            Text("这将删除所有已卸载 Ruby 版本的残留文件。确定要继续吗？")
        }
        .alert("更新确认", isPresented: $viewModel.showingUpdateAlert) {
            Button("取消", role: .cancel) {}
            Button("更新") {
                Task { await viewModel.update() }
            }
        } message: {
            Text("这将更新 RVM 到最新版本。确定要继续吗？")
        }
    }

    // MARK: - 状态

    @ViewBuilder
    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: viewModel.isRVMAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(viewModel.isRVMAvailable ? .green : .red)

                VStack(alignment: .leading) {
                    Text(viewModel.isRVMAvailable ? "RVM 已安装" : "RVM 未安装")
                        .font(.headline)
                    Text(viewModel.isRVMAvailable ? "可以正常使用" : "请先安装 RVM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !viewModel.isRVMAvailable {
                    Button(action: {
                        Task { await viewModel.installRVM() }
                    }) {
                        Label("安装 RVM", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive, action: {
                        showingUninstallAlert = true
                    }) {
                        Label("卸载 RVM", systemImage: "trash")
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
                InfoRow(title: "安装路径", value: viewModel.rvmPath)
                InfoRow(title: "RVM 版本", value: viewModel.rvmVersion)
                InfoRow(title: "当前 Ruby", value: viewModel.currentRuby)
                InfoRow(title: "默认 Ruby", value: viewModel.defaultRuby)
                InfoRow(title: "Ruby 数量", value: "\(viewModel.installedCount)")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        } header: {
            Text("安装信息")
                .font(.headline)
        }
    }

    // MARK: - 维护

    @ViewBuilder
    private var maintenanceSection: some View {
        Section {
            VStack(spacing: 12) {
                maintenanceButton(title: "清理旧版本", icon: "trash") {
                    viewModel.showingCleanupAlert = true
                }
                maintenanceButton(title: "更新 RVM", icon: "arrow.triangle.2.circlepath") {
                    viewModel.showingUpdateAlert = true
                }
                maintenanceButton(title: "重装所有 Gems", icon: "arrow.counterclockwise") {
                    Task { await viewModel.reinstallAllGems() }
                }
            }
        } header: {
            Text("维护")
                .font(.headline)
        }
    }

    private func maintenanceButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
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
class RVMSettingsViewModel: ObservableObject {
    @Published var isRVMAvailable = false
    @Published var rvmPath = "未知"
    @Published var rvmVersion = "未知"
    @Published var currentRuby = "未知"
    @Published var defaultRuby = "未知"
    @Published var installedCount = 0
    @Published var showingCleanupAlert = false
    @Published var showingUpdateAlert = false
    
    private let service = RVMService.shared
    
    func load() async {
        isRVMAvailable = service.checkRVMAvailability()
        guard isRVMAvailable else { return }
        
        rvmPath = service.getRVMPath()
        
        async let versions = service.listInstalledRubies()
        async let current = service.getCurrentRubyVersion()
        async let def = service.getDefaultRubyVersion()
        async let ver = service.executeCommand(arguments: ["version"])
        
        let rubies = await versions
        currentRuby = await current
        defaultRuby = await def
        installedCount = rubies.count
        
        if case .success(let output) = await ver {
            rvmVersion = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    func installRVM() async {
        _ = await service.installRVM()
        await load()
    }
    
    func uninstallRVM() async {
        _ = await service.uninstallRVM()
        await load()
    }
    
    func listGemSources() async -> [String] {
        return []
    }
    
    func getRubyInstallSource() async -> String {
        return await service.getRubyInstallSource()
    }
    
    func setRubyInstallSource(to url: String) async -> OperationResult {
        return await service.setRubyInstallSource(url)
    }
    
    func cleanup() async {
        _ = await service.executeCommand(arguments: ["cleanup", "all"])
        await load()
    }
    
    func update() async {
        _ = await service.executeCommand(arguments: ["get", "stable"])
        await load()
    }
    
    func reinstallAllGems() async {
        _ = await service.executeCommand(arguments: ["gemset", "empty", "--force"])
    }
}

#Preview {
    RVMSettingsView()
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

private struct CustomField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}
