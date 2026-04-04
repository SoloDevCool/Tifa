import SwiftUI

struct PyenvView: View {
    @StateObject private var viewModel = PyenvViewModel()
    @State private var searchText = ""
    @State private var selectedVersion: PyenvVersion?
    @State private var showingInstallSheet = false
    @State private var showingUninstallAlert = false
    @State private var versionToUninstall: PyenvVersion?
    
    var filteredVersions: [PyenvVersion] {
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
                        .fill(viewModel.isPyenvAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isPyenvAvailable ? "pyenv 已安装" : "pyenv 未安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let current = viewModel.currentVersion {
                    Text("当前: \(current)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let global = viewModel.globalVersion, global != "未设置" {
                    Text("全局: \(global)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(viewModel.versions.count) 个 Python 版本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                if viewModel.isPyenvAvailable && !viewModel.isEnvConfigured {
                    Button(action: {
                        Task { await viewModel.configureEnv() }
                    }) {
                        Label("配置环境变量", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                
                Button(action: { showingInstallSheet = true }) {
                    Label("安装版本", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isPyenvAvailable)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Python 版本列表
            if viewModel.isLoading && viewModel.versions.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.isPyenvAvailable {
                EmptyStateView(
                    title: "pyenv 未安装",
                    systemImage: "exclamationmark.triangle",
                    description: "请先在「设置」中通过 Homebrew 安装 pyenv"
                )
            } else if !viewModel.isEnvConfigured {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text("pyenv 环境变量未配置")
                        .font(.headline)
                    Text("请先配置环境变量，否则 pyenv 无法正常工作")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("一键配置") {
                        Task { await viewModel.configureEnv() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredVersions.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "暂无已安装的 Python" : "未找到匹配版本",
                    systemImage: searchText.isEmpty ? "shippingbox" : "magnifyingglass"
                )
            } else {
                List(selection: $selectedVersion) {
                    ForEach(filteredVersions) { version in
                        PyenvVersionRow(
                            version: version,
                            onSetGlobal: {
                                await viewModel.setGlobal(version)
                            },
                            onUninstall: {
                                versionToUninstall = version
                                showingUninstallAlert = true
                            }
                        )
                        .tag(version)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Python 版本")
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallPythonSheet(viewModel: viewModel, isPresented: $showingInstallSheet)
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let ver = versionToUninstall {
                    Task { await viewModel.uninstall(ver) }
                }
            }
        } message: {
            Text("确定要卸载 Python \(versionToUninstall?.version ?? "") 吗？")
        }
    }
}

// MARK: - Python 版本行

struct PyenvVersionRow: View {
    let version: PyenvVersion
    let onSetGlobal: () async -> Void
    let onUninstall: () -> Void
    
    @State private var isSettingGlobal = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            if version.isGlobal {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 32)
            } else {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.3))
                    .frame(width: 32)
            }
            
            // 版本信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(version.version)
                        .font(.headline)
                    
                    if version.isGlobal {
                        Text("全局")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Text("Python \(version.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 设为全局按钮
            if !version.isGlobal {
                Button(action: {
                    Task {
                        isSettingGlobal = true
                        await onSetGlobal()
                        isSettingGlobal = false
                    }
                }) {
                    if isSettingGlobal {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("设为全局", systemImage: "star")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSettingGlobal)
            }
            
            // 卸载按钮
            Button(action: onUninstall) {
                Label("卸载", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 安装 Python Sheet

struct InstallPythonSheet: View {
    @ObservedObject var viewModel: PyenvViewModel
    @Binding var isPresented: Bool
    @State private var installVersion = ""
    @State private var isSearching = false
    @State private var searchResults: [String] = []
    
    private let commonVersions = ["3.13.0", "3.12.7", "3.12.6", "3.11.10", "3.11.9", "3.10.15", "3.10.14", "3.9.20", "3.9.19", "3.8.20"]
    
    /// 是否正在安装中
    private var isInstallingActive: Bool { viewModel.isInstalling }
    
    /// 安装是否已完成（成功或失败）
    private var isInstallDone: Bool { viewModel.installResult != nil && !viewModel.isInstalling }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("安装 Python")
                    .font(.headline)
                Spacer()
                if isInstallDone {
                    Button("关闭") { 
                        viewModel.clearInstallOutput()
                        isPresented = false 
                    }
                } else if !isInstallingActive {
                    Button("取消") { isPresented = false }
                }
            }
            
            if isInstallingActive || isInstallDone {
                // 安装进度/输出面板
                VStack(spacing: 0) {
                    // 状态栏
                    HStack(spacing: 8) {
                        if isInstallingActive {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                            Text("正在安装 Python \(viewModel.installingVersion)...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if let result = viewModel.installResult {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Python \(viewModel.installingVersion) 安装成功")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            case .failure(let error):
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error.prefix(80))
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        Spacer()
                        if isInstallDone {
                            Button("关闭") {
                                viewModel.clearInstallOutput()
                                isPresented = false
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    
                    Divider()
                    
                    // 终端输出
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(viewModel.installOutput.isEmpty ? "等待输出..." : viewModel.installOutput)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(viewModel.installOutput.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                                .id("outputBottom")
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: viewModel.installOutput) { _ in
                            proxy.scrollTo("outputBottom", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                // 快捷选择
                VStack(alignment: .leading, spacing: 8) {
                    Text("常用版本")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(commonVersions, id: \.self) { version in
                            let installed = viewModel.versions.contains(where: { $0.version == version })
                            Button(action: { installVersion = version }) {
                                HStack(spacing: 4) {
                                    Text(version)
                                        .font(.caption)
                                    if installed {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(installed ? Color.green.opacity(0.15) : (installVersion == version ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
                                .foregroundColor(installed ? .green : (installVersion == version ? .white : .primary))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(installed ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // 手动输入
                HStack {
                    TextField("输入版本号，如 3.12.0", text: $installVersion)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("在线搜索") {
                        Task { await searchOnline() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSearching)
                }
                
                // 搜索结果
                if !searchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("可用版本")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ScrollView {
                            FlowLayout(spacing: 8) {
                                ForEach(searchResults, id: \.self) { version in
                                    let installed = viewModel.versions.contains(where: { $0.version == version })
                                    Button(action: { installVersion = version }) {
                                        HStack(spacing: 4) {
                                            Text(version)
                                                .font(.caption)
                                            if installed {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(installed ? Color.green.opacity(0.15) : (installVersion == version ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
                                        .foregroundColor(installed ? .green : (installVersion == version ? .white : .primary))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(installed ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
                
                Divider()
                
                // 安装按钮
                HStack {
                    Spacer()
                    Button("安装") {
                        Task { await viewModel.install(version: installVersion) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(installVersion.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
    }
    
    private func searchOnline() async {
        isSearching = true
        searchResults = await viewModel.listAvailableVersions()
        isSearching = false
    }
}

// MARK: - ViewModel

@MainActor
class PyenvViewModel: ObservableObject {
    @Published var versions: [PyenvVersion] = []
    @Published var isLoading = false
    @Published var isPyenvAvailable = false
    @Published var isEnvConfigured = false
    @Published var currentVersion: String?
    @Published var globalVersion: String?
    
    /// 安装进度相关
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installingVersion = ""
    @Published var installResult: OperationResult?
    
    private let service = PyenvService.shared
    
    func load() async {
        isPyenvAvailable = service.checkPyenvAvailability()
        isEnvConfigured = service.isPyenvEnvConfigured()
        
        guard isPyenvAvailable else { return }
        
        isLoading = true
        async let vers = service.listInstalledVersions()
        async let current = service.getCurrentVersion()
        async let global = service.getGlobalVersion()
        
        versions = await vers
        currentVersion = await current
        globalVersion = await global
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    func setGlobal(_ version: PyenvVersion) async {
        let result = await service.setGlobalVersion(version.version)
        switch result {
        case .success:
            await load()
        case .failure(let error):
            print("设置全局版本失败: \(error)")
        }
    }
    
    func install(version: String) async {
        guard !version.isEmpty else { return }
        isInstalling = true
        installingVersion = version
        installOutput = ""
        installResult = nil
        
        let result = await service.installVersionWithOutput(version) { [weak self] output in
            self?.installOutput += output
        }
        
        installResult = result
        isInstalling = false
        
        if case .success = result {
            await load()
        }
    }
    
    func clearInstallOutput() {
        installOutput = ""
        installResult = nil
        installingVersion = ""
    }
    
    func uninstall(_ version: PyenvVersion) async {
        let result = await service.uninstallVersion(version.version)
        switch result {
        case .success:
            await load()
        case .failure(let error):
            print("卸载失败: \(error)")
        }
    }
    
    func configureEnv() async {
        _ = await service.configurePyenvEnv()
        isEnvConfigured = service.isPyenvEnvConfigured()
    }
    
    func listAvailableVersions() async -> [String] {
        return await service.listAvailableVersions()
    }
}

#Preview {
    PyenvView()
}
