import SwiftUI

// MARK: - Ruby 安装源预设（RVM 下载 Ruby 源码包的镜像）

struct RubyInstallSourcePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    
    static let official = RubyInstallSourcePreset(id: "official", name: "官方源", url: "https://cache.ruby-lang.org/pub/ruby")
    static let taobao = RubyInstallSourcePreset(id: "taobao", name: "淘宝镜像", url: "https://npm.taobao.org/mirrors/ruby")
    static let ustc = RubyInstallSourcePreset(id: "ustc", name: "中科大", url: "https://mirrors.ustc.edu.cn/ruby/")
    static let tsinghua = RubyInstallSourcePreset(id: "tsinghua", name: "清华大学", url: "https://mirrors.tuna.tsinghua.edu.cn/ruby/")
    
    static let allPresets: [RubyInstallSourcePreset] = [.official, .taobao, .ustc, .tsinghua]
}

// MARK: - RVM 设置视图

struct RVMSettingsView: View {
    @StateObject private var viewModel = RVMSettingsViewModel()
    @State private var selectedSource: RubyInstallSourcePreset = .official
    @State private var isCustomSource = false
    @State private var customSourceUrl = ""
    @State private var showingSwitchResult = false
    @State private var switchResultMessage = ""
    @State private var showingUninstallAlert = false
    @State private var currentSourceName = "加载中..."
    @State private var isApplying = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // RVM 状态
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
                
                if viewModel.isRVMAvailable {
                    // 安装信息
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
                    
                    // Ruby 安装源配置
                    Section {
                        // 当前源
                        HStack {
                            Label("当前 Ruby 安装源", systemImage: "globe")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(currentSourceName)
                                .font(.subheadline.bold())
                                .foregroundColor(.accentColor)
                        }
                        .padding(.bottom, 8)
                        
                        Text("配置 RVM 安装 Ruby 时下载源码包的镜像地址，可加速安装。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 12)
                        
                        // 预设选择
                        VStack(alignment: .leading, spacing: 10) {
                            Text("选择镜像")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                ForEach(RubyInstallSourcePreset.allPresets) { preset in
                                    Button(action: {
                                        selectedSource = preset
                                        isCustomSource = false
                                    }) {
                                        Text(preset.name)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedSource == preset && !isCustomSource ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                            .foregroundColor(selectedSource == preset && !isCustomSource ? .white : .primary)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(selectedSource == preset && !isCustomSource ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // 自定义
                        Toggle("自定义镜像地址", isOn: $isCustomSource)
                            .toggleStyle(.switch)
                            .padding(.top, 4)
                        
                        if isCustomSource {
                            VStack(spacing: 8) {
                                CustomField(title: "镜像地址", placeholder: "https://mirrors.example.com/ruby/", text: $customSourceUrl)
                            }
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
                            
                            Button(action: {
                                Task { await applySource() }
                            }) {
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
                        Text("Ruby 安装源")
                            .font(.headline)
                    }
                    
                    // 维护操作
                    Section {
                        VStack(spacing: 12) {
                            Button(action: { viewModel.showingCleanupAlert = true }) {
                                HStack {
                                    Label("清理旧版本", systemImage: "trash")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.showingUpdateAlert = true }) {
                                HStack {
                                    Label("更新 RVM", systemImage: "arrow.triangle.2.circlepath")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { Task { await viewModel.reinstallAllGems() } }) {
                                HStack {
                                    Label("重装所有 Gems", systemImage: "arrow.counterclockwise")
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
            await detectCurrentSource()
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
        .sheet(isPresented: $showingSwitchResult) {
            VStack(spacing: 16) {
                Text("切换结果")
                    .font(.headline)
                
                ScrollView {
                    Text(switchResultMessage)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                
                Button("关闭") { showingSwitchResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 550, height: 350)
        }
    }
    
    private func detectCurrentSource() async {
        let currentUrl = await viewModel.getRubyInstallSource()
        // 匹配预设
        for preset in RubyInstallSourcePreset.allPresets {
            if currentUrl.contains(preset.url) || preset.url.contains(currentUrl) {
                currentSourceName = preset.name
                selectedSource = preset
                isCustomSource = false
                return
            }
        }
        if currentUrl.isEmpty || currentUrl == "https://cache.ruby-lang.org/pub/ruby" {
            currentSourceName = "官方源（默认）"
        } else {
            currentSourceName = currentUrl
            customSourceUrl = currentUrl
            isCustomSource = true
        }
    }
    
    private func applySource() async {
        isApplying = true
        defer { isApplying = false }
        
        let targetUrl: String
        let targetName: String
        
        if isCustomSource {
            guard !customSourceUrl.isEmpty else { return }
            targetUrl = customSourceUrl
            targetName = "自定义"
        } else {
            targetUrl = selectedSource.url
            targetName = selectedSource.name
        }
        
        let result = await viewModel.setRubyInstallSource(to: targetUrl)
        switch result {
        case .success(let output):
            switchResultMessage = "已切换 Ruby 安装源到 \(targetName)\n\n地址: \(targetUrl)\n\n\(output)"
            currentSourceName = targetName
        case .failure(let error):
            switchResultMessage = "切换失败: \(error)"
        }
        showingSwitchResult = true
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
