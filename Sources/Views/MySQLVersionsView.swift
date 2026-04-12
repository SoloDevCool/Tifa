import SwiftUI

struct MySQLVersionsView: View {
    @StateObject private var viewModel = MySQLVersionsViewModel()
    @State private var showingInstallSheet = false
    @State private var showingUninstallConfirm = false
    @State private var versionToUninstall: MySQLVersionInfo?
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("MySQL 软件包")
                    .font(.title2.bold())
                Spacer()
                Button(action: { Task { await viewModel.load() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            // 表格列表
            if #available(macOS 14.0, *) {
                Table(viewModel.packages) {
                    TableColumn("软件包名称") { pkg in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pkg.displayName)
                                .font(.body.bold())
                            Text(pkg.formula)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 120, ideal: 150)
                    
                    TableColumn("状态") { pkg in
                        StatusBadge(installed: pkg.installed, pid: pkg.pid)
                    }
                    .width(80)
                    
                    TableColumn("PID") { pkg in
                        Text(pkg.pid.map { String($0) } ?? "-")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(pkg.pid != nil ? .primary : .secondary)
                    }
                    .width(80)
                    
                    TableColumn("激活") { pkg in
                        ActivationBadge(activated: pkg.activated)
                    }
                    .width(80)
                    
                    TableColumn("控制") { pkg in
                        PackageControlButtons(
                            pkg: pkg,
                            isSwitching: viewModel.isSwitching,
                            isInstalling: viewModel.isInstalling,
                            onInstall: {
                                viewModel.selectedInstallFormula = pkg.formula
                                viewModel.selectedInstallName = pkg.displayName
                                showingInstallSheet = true
                            },
                            onUninstall: {
                                versionToUninstall = pkg
                                showingUninstallConfirm = true
                            },
                            onActivate: {
                                Task { await viewModel.switchVersion(to: pkg.formula) }
                            }
                        )
                    }
                    .width(min: 140)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            } else {
                // macOS 13 及以下版本的兼容表格
                LegacyPackageTable(viewModel: viewModel, onInstall: { pkg in
                    viewModel.selectedInstallFormula = pkg.formula
                    viewModel.selectedInstallName = pkg.displayName
                    showingInstallSheet = true
                }, onUninstall: { pkg in
                    versionToUninstall = pkg
                    showingUninstallConfirm = true
                }, onActivate: { pkg in
                    Task { await viewModel.switchVersion(to: pkg.formula) }
                })
            }
            
            Spacer()
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
                installLog: $viewModel.installLog,
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

// MARK: - 状态徽章

private struct StatusBadge: View {
    let installed: Bool
    let pid: Int?
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        if pid != nil {
            return .green
        } else if installed {
            return .orange
        } else {
            return .secondary
        }
    }
    
    private var statusText: String {
        if pid != nil {
            return "运行中"
        } else if installed {
            return "已安装"
        } else {
            return "未安装"
        }
    }
}

// MARK: - 激活徽章

struct ActivationBadge: View {
    let activated: Bool
    
    var body: some View {
        Text(activated ? "已激活" : "-")
            .font(.caption)
            .foregroundColor(activated ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(activated ? Color.green.opacity(0.15) : Color.clear)
            .cornerRadius(4)
    }
}

// MARK: - 控制按钮

struct PackageControlButtons: View {
    let pkg: MySQLVersionInfo
    let isSwitching: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onActivate: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            if pkg.installed {
                if pkg.activated {
                    Button("已激活") {}
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                } else {
                    Button("激活") {
                        onActivate()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSwitching)
                }
                Button("卸载") {
                    onUninstall()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            } else {
                Button("安装") {
                    onInstall()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)
            }
        }
    }
}

// MARK: - macOS 13 兼容表格

struct LegacyPackageTable: View {
    @ObservedObject var viewModel: MySQLVersionsViewModel
    let onInstall: (MySQLVersionInfo) -> Void
    let onUninstall: (MySQLVersionInfo) -> Void
    let onActivate: (MySQLVersionInfo) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                Text("软件包名称")
                    .frame(width: 150, alignment: .leading)
                Text("状态")
                    .frame(width: 80, alignment: .center)
                Text("PID")
                    .frame(width: 80, alignment: .center)
                Text("激活")
                    .frame(width: 80, alignment: .center)
                Text("控制")
                    .frame(minWidth: 140, alignment: .center)
            }
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 表格内容
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.packages) { pkg in
                        HStack(spacing: 0) {
                            // 软件包名称
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pkg.displayName)
                                    .font(.body.bold())
                                Text(pkg.formula)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 150, alignment: .leading)
                            
                            // 状态
                            StatusBadge(installed: pkg.installed, pid: pkg.pid)
                                .frame(width: 80)
                            
                            // PID
                            Text(pkg.pid.map { String($0) } ?? "-")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(pkg.pid != nil ? .primary : .secondary)
                                .frame(width: 80, alignment: .center)
                            
                            // 激活
                            ActivationBadge(activated: pkg.activated)
                                .frame(width: 80)
                            
                            // 控制
                            PackageControlButtons(
                                pkg: pkg,
                                isSwitching: viewModel.isSwitching,
                                isInstalling: viewModel.isInstalling,
                                onInstall: { onInstall(pkg) },
                                onUninstall: { onUninstall(pkg) },
                                onActivate: { onActivate(pkg) }
                            )
                            .frame(minWidth: 140)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class MySQLVersionsViewModel: ObservableObject {
    @Published var packages: [MySQLVersionInfo] = []
    @Published var activeVersion = ""
    @Published var isSwitching = false
    @Published var isInstalling = false
    @Published var installLog = ""
    @Published var selectedInstallFormula = ""
    @Published var selectedInstallName = ""
    
    private let service = MySQLService.shared
    
    func load() async {
        await service.detectInstalledVersions()
        packages = service.installedVersions
        activeVersion = service.activeVersion
    }
    
    func switchVersion(to formula: String) async {
        guard !isSwitching else { return }
        isSwitching = true
        installLog = ""
        
        // 1. 切换 PATH（永久生效）
        let pathResult = await service.switchPATH(to: formula)
        if case .failure(let error) = pathResult {
            installLog += "PATH 切换失败: \(error)\n"
        } else if case .success(let msg) = pathResult {
            installLog += "\(msg)\n"
        }
        
        // 2. 切换服务（停止其他版本，启动目标版本）
        let serviceResult = await service.switchVersion(to: formula)
        if case .failure(let error) = serviceResult {
            installLog += "服务切换失败: \(error)"
        } else if case .success(let msg) = serviceResult {
            installLog += "\(msg)"
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
}

#Preview {
    MySQLVersionsView()
}
