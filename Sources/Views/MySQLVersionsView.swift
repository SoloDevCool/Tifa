import SwiftUI

struct MySQLVersionsView: View {
    @StateObject private var viewModel = MySQLVersionsViewModel()
    @State private var showingInstallSheet = false
    @State private var showingUninstallConfirm = false
    @State private var versionToUninstall: MySQLVersionInfo?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 当前活跃版本
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.activeVersion.isEmpty ? "未安装" : viewModel.activeVersion)
                                .font(.headline)
                            if !viewModel.activeVersion.isEmpty {
                                HStack(spacing: 8) {
                                    if viewModel.isRunning {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                        Text("运行中")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Circle().fill(Color.red).frame(width: 6, height: 6)
                                        Text("已停止")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if !viewModel.activeVersion.isEmpty {
                            if viewModel.isRunning {
                                Button(action: { Task { await viewModel.stopMySQL() } }) {
                                    Label("停止", systemImage: "stop.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button(action: { Task { await viewModel.startMySQL() } }) {
                                    Label("启动", systemImage: "play.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("当前版本")
                        .font(.headline)
                }
                
                // 已安装版本
                Section {
                    if viewModel.installedVersions.filter({ $0.installed }).isEmpty {
                        VStack(spacing: 8) {
                            Text("尚未安装任何 MySQL 版本")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(viewModel.installedVersions.filter({ $0.installed })) { ver in
                            HStack(spacing: 12) {
                                Image(systemName: ver.linked ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(ver.linked ? .accentColor : .secondary)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ver.displayName)
                                        .font(.subheadline.bold())
                                    Text(ver.formula)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if ver.linked {
                                    Text("活跃")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(4)
                                } else {
                                    HStack(spacing: 8) {
                                        Button("切换") {
                                            Task { await viewModel.switchVersion(to: ver.formula) }
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .disabled(viewModel.isSwitching)
                                        
                                        Button("卸载") {
                                            versionToUninstall = ver
                                            showingUninstallConfirm = true
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                } header: {
                    Text("已安装版本")
                        .font(.headline)
                }
                
                // 可安装版本
                Section {
                    let uninstalled = MySQLService.availableVersions.filter { v in
                        !viewModel.installedVersions.contains { $0.formula == v.formula }
                    }
                    
                    if uninstalled.isEmpty {
                        VStack(spacing: 8) {
                            Text("所有版本均已安装")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(uninstalled, id: \.formula) { v in
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name)
                                        .font(.subheadline.bold())
                                    Text(v.formula)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("安装") {
                                    viewModel.selectedInstallFormula = v.formula
                                    viewModel.selectedInstallName = v.name
                                    showingInstallSheet = true
                                }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.isInstalling)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                } header: {
                    Text("可安装版本")
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
        .sheet(isPresented: $showingInstallSheet) {
            BrewInstallSheet(
                title: "安装 \(viewModel.selectedInstallName)",
                formula: viewModel.selectedInstallFormula,
                isInstalling: viewModel.isInstalling,
                installLog: viewModel.installLog,
                onInstall: { formula in
                    Task { await viewModel.installVersion(formula: formula) }
                },
                onClose: {
                    showingInstallSheet = false
                    Task { await viewModel.load() }
                }
            )
        }
        .alert("卸载确认", isPresented: $showingUninstallConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let ver = versionToUninstall {
                    Task { await viewModel.uninstallVersion(formula: ver.formula) }
                }
            }
        } message: {
            Text("确定要卸载 \(versionToUninstall?.displayName ?? "") 吗？\n这将删除 \(versionToUninstall?.formula ?? "") 的所有文件。")
        }
    }
}

// MARK: - ViewModel

@MainActor
class MySQLVersionsViewModel: ObservableObject {
    @Published var installedVersions: [MySQLVersionInfo] = []
    @Published var activeVersion = ""
    @Published var isRunning = false
    @Published var isSwitching = false
    @Published var isInstalling = false
    @Published var installLog = ""
    @Published var selectedInstallFormula = ""
    @Published var selectedInstallName = ""
    
    private let service = MySQLService.shared
    
    func load() async {
        await service.detectInstalledVersions()
        installedVersions = service.installedVersions
        activeVersion = service.activeVersion
        
        if !activeVersion.isEmpty {
            isRunning = await service.isMySQLRunning()
        }
    }
    
    func switchVersion(to formula: String) async {
        guard !isSwitching else { return }
        isSwitching = true
        let result = await service.switchVersion(to: formula)
        if case .failure(let error) = result {
            installLog = "切换失败: \(error)"
        }
        await load()
        isSwitching = false
    }
    
    func installVersion(formula: String) async {
        guard !isInstalling else { return }
        isInstalling = true
        installLog = ""
        let result = await service.installVersion(formula: formula) { [weak self] output in
            self?.installLog += output
        }
        if case .success = result {
            await load()
        }
        isInstalling = false
    }
    
    func uninstallVersion(formula: String) async {
        let result = await service.uninstallVersion(formula: formula)
        if case .failure(let error) = result {
            installLog = "卸载失败: \(error)"
        }
        await load()
    }
    
    func startMySQL() async {
        _ = await service.startMySQL()
        await load()
    }
    
    func stopMySQL() async {
        _ = await service.stopMySQL()
        await load()
    }
}

#Preview {
    MySQLVersionsView()
}
