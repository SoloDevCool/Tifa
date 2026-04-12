import SwiftUI

struct PyenvSettingsView: View {
    @StateObject private var viewModel = PyenvSettingsViewModel()
    @State private var showingUninstallAlert = false
    @State private var showingUpdateAlert = false
    @State private var selectedConfigFile = ".zshrc"
    @State private var showingConfigResult = false
    @State private var configResultMessage = ""
    @State private var isInstalling = false
    @State private var configNeedsRestart = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // pyenv 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isPyenvAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isPyenvAvailable ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.isPyenvAvailable ? "pyenv 已安装" : "pyenv 未安装")
                                .font(.headline)
                            Text(viewModel.isPyenvAvailable ? "通过 Homebrew 安装" : "点击下方按钮安装")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !viewModel.isPyenvAvailable {
                            Button(action: {
                                Task { await installPyenv() }
                            }) {
                                if isInstalling {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                    Text("安装中...")
                                        .font(.caption)
                                } else {
                                    Label("安装 pyenv", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInstalling)
                        } else {
                            Button(role: .destructive, action: {
                                showingUninstallAlert = true
                            }) {
                                Label("卸载 pyenv", systemImage: "trash")
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
                
                if viewModel.isPyenvAvailable {
                    // 安装信息
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(title: "安装路径", value: viewModel.pyenvPath)
                            InfoRow(title: "pyenv 版本", value: viewModel.pyenvVersion)
                            InfoRow(title: "全局版本", value: viewModel.globalVersion)
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
                        // 当前配置状态
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
                        
                        Text("pyenv 需要在 Shell 配置文件中设置环境变量才能正常工作。")
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
                    
                    // Python 安装源配置
                    PythonMirrorSection(viewModel: viewModel, selectedConfigFile: $selectedConfigFile)
                    
                    // 维护操作
                    Section {
                        VStack(spacing: 12) {
                            Button(action: { showingUpdateAlert = true }) {
                                HStack {
                                    Label("更新 pyenv", systemImage: "arrow.triangle.2.circlepath")
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
                        InfoRow(title: "安装方式", value: "Homebrew")
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
                Task { await viewModel.uninstallPyenv() }
            }
        } message: {
            Text("确定要卸载 pyenv 吗？这将同时移除所有已安装的 Python 版本和环境变量配置。此操作不可撤销！")
        }
        .alert("更新确认", isPresented: $showingUpdateAlert) {
            Button("取消", role: .cancel) {}
            Button("更新") {
                Task { await viewModel.updatePyenv() }
            }
        } message: {
            Text("这将更新 pyenv 到最新版本。确定要继续吗？")
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
                
                HStack(spacing: 12) {
                    if configNeedsRestart {
                        Button(action: { restartTerminal() }) {
                            Label("重启终端", systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button("关闭") { showingConfigResult = false }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(width: 520, height: 320)
        }
    }
    
    private func applyConfig() async {
        let result = await viewModel.configureEnv(to: selectedConfigFile)
        switch result {
        case .success(let msg):
            configResultMessage = "\(msg)\n\n请点击「重启终端」使环境变量生效。"
            configNeedsRestart = true
        case .failure(let error):
            configResultMessage = "配置失败: \(error)"
            configNeedsRestart = false
        }
        showingConfigResult = true
    }
    
    private func removeConfig() async {
        let result = await viewModel.removeEnvConfig(from: selectedConfigFile)
        switch result {
        case .success(let msg):
            configResultMessage = "\(msg)\n\n建议重启终端使配置生效。"
            configNeedsRestart = true
        case .failure(let error):
            configResultMessage = "移除失败: \(error)"
            configNeedsRestart = false
        }
        showingConfigResult = true
    }
    
    private func installPyenv() async {
        isInstalling = true
        let result = await viewModel.installPyenv()
        isInstalling = false
        switch result {
        case .success:
            configResultMessage = "pyenv 安装成功！\n\n请前往「环境变量配置」进行一键配置，使 pyenv 在终端中生效。"
            configNeedsRestart = false
        case .failure(let error):
            configResultMessage = "安装失败：\(error)\n\n请确认 Homebrew 已正确安装。"
            configNeedsRestart = false
        }
        showingConfigResult = true
        await viewModel.load()
    }
    
    /// 重启终端（关闭所有 Terminal/iTerm 窗口并重新打开）
    private func restartTerminal() {
        showingConfigResult = false
        let script = """
        osascript -e 'tell application "Terminal" to quit'
        sleep 1
        open -a Terminal
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

// MARK: - ViewModel

@MainActor
class PyenvSettingsViewModel: ObservableObject {
    @Published var isPyenvAvailable = false
    @Published var pyenvPath = "未知"
    @Published var pyenvVersion = "未知"
    @Published var globalVersion = "未设置"
    @Published var installedCount = 0
    @Published var isEnvConfigured = false
    @Published var configuredFiles: [(file: String, hasConfig: Bool)] = []
    
    private let service = PyenvService.shared
    
    func load() async {
        isPyenvAvailable = service.checkPyenvAvailability()
        guard isPyenvAvailable else { return }
        
        pyenvPath = service.getPyenvPath()
        isEnvConfigured = service.isPyenvEnvConfigured()
        configuredFiles = service.getConfiguredFiles()
        
        async let versions = service.listInstalledVersions()
        async let global = service.getGlobalVersion()
        async let ver = service.getPyenvVersion()
        
        let vers = await versions
        globalVersion = await global
        installedCount = vers.count
        
        pyenvVersion = await ver
    }
    
    func installPyenv() async -> OperationResult {
        let result = await service.installPyenv()
        await load()
        return result
    }
    
    func uninstallPyenv() async {
        _ = await service.uninstallPyenv()
        await load()
    }
    
    func configureEnv(to fileName: String) async -> OperationResult {
        let result = await service.configurePyenvEnv(to: fileName)
        await load()
        return result
    }
    
    func removeEnvConfig(from fileName: String) async -> OperationResult {
        let result = await service.removePyenvEnvConfig(from: fileName)
        await load()
        return result
    }
    
    func updatePyenv() async {
        _ = await service.updatePyenv()
        await load()
    }
    
    func getPythonMirrorSource() async -> String {
        return await service.getPythonMirrorSource()
    }
    
    func setPythonMirrorSource(_ url: String, to fileName: String) async -> OperationResult {
        return await service.setPythonMirrorSource(url, to: fileName)
    }
    
    func removePythonMirrorSource(from fileName: String) async -> OperationResult {
        return await service.removePythonMirrorSource(from: fileName)
    }
}

#Preview {
    PyenvSettingsView()
}

// MARK: - Python 安装源预设

struct PythonMirrorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    
    static let official = PythonMirrorPreset(id: "official", name: "官方源", url: "")
    static let npmmirror = PythonMirrorPreset(id: "npmmirror", name: "npmmirror", url: "https://registry.npmmirror.com/binary.html?path=python/")
    static let ustc = PythonMirrorPreset(id: "ustc", name: "中科大", url: "https://mirrors.ustc.edu.cn/python/")
    static let huawei = PythonMirrorPreset(id: "huawei", name: "华为云", url: "https://repo.huaweicloud.com/python/")
    static let tsinghua = PythonMirrorPreset(id: "tsinghua", name: "清华大学", url: "https://mirrors.tuna.tsinghua.edu.cn/python/")
    
    static let allPresets: [PythonMirrorPreset] = [.official, .npmmirror, .ustc, .huawei, .tsinghua]
}

// MARK: - Python 安装源配置区块

struct PythonMirrorSection: View {
    @ObservedObject var viewModel: PyenvSettingsViewModel
    @Binding var selectedConfigFile: String
    
    @State private var selectedPreset: PythonMirrorPreset = .official
    @State private var isCustom = false
    @State private var customUrl = ""
    @State private var currentSourceName = "加载中..."
    @State private var isApplying = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    
    var body: some View {
        Section {
            // 当前源
            HStack {
                Label("当前安装源", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(currentSourceName)
                    .font(.subheadline.bold())
                    .foregroundColor(.accentColor)
            }
            .padding(.bottom, 4)
            
            Text("设置 pyenv 编译安装 Python 时的源码下载镜像，可大幅加速安装。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
            
            // 预设选择
            VStack(alignment: .leading, spacing: 8) {
                Text("选择镜像")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 8) {
                    ForEach(PythonMirrorPreset.allPresets) { preset in
                        Button(action: {
                            selectedPreset = preset
                            isCustom = false
                        }) {
                            Text(preset.name)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedPreset == preset && !isCustom ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                .foregroundColor(selectedPreset == preset && !isCustom ? .white : .primary)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedPreset == preset && !isCustom ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // 自定义
            Toggle("自定义镜像地址", isOn: $isCustom)
                .toggleStyle(.switch)
                .padding(.top, 4)
            
            if isCustom {
                TextField("https://mirrors.example.com/python/", text: $customUrl)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
            }
            
            // 按钮行
            HStack(spacing: 12) {
                Button(action: { Task { await detectCurrentSource() } }) {
                    Label("检测当前源", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { Task { await applySource() } }) {
                    Label(isApplying ? "应用中..." : "应用安装源", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isApplying ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isApplying)
            }
            .padding(.top, 8)
        } header: {
            Text("Python 安装源")
                .font(.headline)
        }
        .task {
            await detectCurrentSource()
        }
        .sheet(isPresented: $showingResult) {
            VStack(spacing: 16) {
                Text("配置结果")
                    .font(.headline)
                
                ScrollView {
                    Text(resultMessage)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                
                Button("关闭") { showingResult = false }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(width: 500, height: 300)
        }
    }
    
    private func detectCurrentSource() async {
        let currentUrl = await viewModel.getPythonMirrorSource()
        if currentUrl.isEmpty {
            currentSourceName = "官方源（默认）"
            selectedPreset = .official
            isCustom = false
        } else {
            // 匹配预设
            let matched = PythonMirrorPreset.allPresets.first { preset in
                !preset.url.isEmpty && (currentUrl.contains(preset.url) || preset.url.contains(currentUrl))
            }
            if let matched = matched {
                currentSourceName = matched.name
                selectedPreset = matched
                isCustom = false
            } else {
                currentSourceName = currentUrl
                customUrl = currentUrl
                isCustom = true
            }
        }
    }
    
    private func applySource() async {
        isApplying = true
        defer { isApplying = false }
        
        let targetUrl: String
        let targetName: String
        
        if isCustom {
            guard !customUrl.isEmpty else { return }
            targetUrl = customUrl
            targetName = "自定义"
        } else {
            targetUrl = selectedPreset.url
            targetName = selectedPreset.name
        }
        
        if targetUrl.isEmpty {
            // 官方源 = 移除配置
            let result = await viewModel.removePythonMirrorSource(from: selectedConfigFile)
            switch result {
            case .success(let msg):
                resultMessage = "已恢复为官方源\n\n\(msg)"
                currentSourceName = "官方源（默认）"
            case .failure(let error):
                resultMessage = "操作失败: \(error)"
            }
        } else {
            let result = await viewModel.setPythonMirrorSource(targetUrl, to: selectedConfigFile)
            switch result {
            case .success(let msg):
                resultMessage = "已切换到 \(targetName)\n\n\(msg)"
                currentSourceName = targetName
            case .failure(let error):
                resultMessage = "切换失败: \(error)"
            }
        }
        showingResult = true
    }
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
