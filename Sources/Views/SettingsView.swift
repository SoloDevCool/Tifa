import SwiftUI

// MARK: - 镜像源预设

struct MirrorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let apiDomain: String
    let bottleDomain: String
    let coreGit: String
    let caskGit: String
    
    static let official = MirrorPreset(
        id: "official",
        name: "官方源",
        apiDomain: "https://formulae.brew.sh/api",
        bottleDomain: "https://ghcr.io/v2/homebrew/core",
        coreGit: "https://github.com/Homebrew/homebrew-core",
        caskGit: "https://github.com/Homebrew/homebrew-cask"
    )
    
    static let aliyun = MirrorPreset(
        id: "aliyun",
        name: "阿里云",
        apiDomain: "https://mirrors.aliyun.com/homebrew/homebrew-bottles/api",
        bottleDomain: "https://mirrors.aliyun.com/homebrew/homebrew-bottles/bottles",
        coreGit: "https://mirrors.aliyun.com/homebrew/homebrew-core.git",
        caskGit: "https://mirrors.aliyun.com/homebrew/homebrew-cask.git"
    )
    
    static let tsinghua = MirrorPreset(
        id: "tsinghua",
        name: "清华大学",
        apiDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api",
        bottleDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/bottles",
        coreGit: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git",
        caskGit: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git"
    )
    
    static let ustc = MirrorPreset(
        id: "ustc",
        name: "中科大",
        apiDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles/api",
        bottleDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles/bottles",
        coreGit: "https://mirrors.ustc.edu.cn/brew/homebrew-core.git",
        caskGit: "https://mirrors.ustc.edu.cn/brew/homebrew-cask.git"
    )
    
    static let bfban = MirrorPreset(
        id: "bfban",
        name: "腾讯云",
        apiDomain: "https://mirrors.cloud.tencent.com/homebrew/homebrew-bottles/api",
        bottleDomain: "https://mirrors.cloud.tencent.com/homebrew/homebrew-bottles/bottles",
        coreGit: "https://mirrors.cloud.tencent.com/homebrew/homebrew-core.git",
        caskGit: "https://mirrors.cloud.tencent.com/homebrew/homebrew-cask.git"
    )
    
    static let allPresets: [MirrorPreset] = [.official, .aliyun, .tsinghua, .ustc, .bfban]
    
    static func == (lhs: MirrorPreset, rhs: MirrorPreset) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingCleanupAlert = false
    @State private var showingUpdateAlert = false
    @State private var showingDoctorAlert = false
    @State private var selectedPreset: MirrorPreset = .official
    @State private var isCustom = false
    @State private var customApiDomain = ""
    @State private var customBottleDomain = ""
    @State private var customCoreGit = ""
    @State private var customCaskGit = ""
    @State private var showingSwitchResult = false
    @State private var switchResultMessage = ""
    @State private var currentMirrorName = "加载中..."
    @State private var isTestingLatency = false
    @State private var latencyResults: [String: TimeInterval] = [:]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Homebrew 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isHomebrewAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isHomebrewAvailable ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.isHomebrewAvailable ? "Homebrew 已安装" : "Homebrew 未安装")
                                .font(.headline)
                            
                            Text(viewModel.isHomebrewAvailable ? "可以正常使用" : "请先安装 Homebrew")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("状态")
                        .font(.headline)
                }
                
                // 安装信息
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(title: "安装路径", value: viewModel.brewPrefix)
                        InfoRow(title: "Cellar 目录", value: viewModel.cellarPath)
                        InfoRow(title: "可执行文件", value: viewModel.brewBinPath)
                        InfoRow(title: "Tap 数量", value: "\(viewModel.tapCount)")
                        InfoRow(title: "已安装包数", value: "\(viewModel.installedCount)")
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("安装信息")
                        .font(.headline)
                }
                
                // 镜像源配置
                Section {
                    // 当前源
                    HStack {
                        Label("当前镜像源", systemImage: "globe")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(currentMirrorName)
                            .font(.subheadline.bold())
                            .foregroundColor(.accentColor)
                    }
                    .padding(.bottom, 8)
                    
                    // 预设选择
                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择预设")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach(MirrorPreset.allPresets) { preset in
                                Button(action: {
                                    selectedPreset = preset
                                    isCustom = false
                                }) {
                                    Text(preset.name)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
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
                    Toggle("自定义镜像源", isOn: $isCustom)
                        .toggleStyle(.switch)
                        .padding(.top, 4)
                    
                    if isCustom {
                        VStack(spacing: 8) {
                            CustomField(title: "API 域名", placeholder: "https://example.com/api", text: $customApiDomain)
                            CustomField(title: "Bottle 域名", placeholder: "https://example.com/bottles", text: $customBottleDomain)
                            CustomField(title: "Core Git", placeholder: "https://example.com/homebrew-core.git", text: $customCoreGit)
                            CustomField(title: "Cask Git", placeholder: "https://example.com/homebrew-cask.git", text: $customCaskGit)
                        }
                        .padding(.top, 4)
                    }
                    
                    // 延迟检测结果
                    if !latencyResults.isEmpty || isTestingLatency {
                        LatencyResultView(
                            isTesting: isTestingLatency,
                            results: latencyResults,
                            latencyColor: latencyColor
                        )
                    }
                    
                    // 按钮行
                    HStack(spacing: 12) {
                        // 延迟检测按钮
                        Button(action: testLatency) {
                            Label(isTestingLatency ? "检测中..." : "测速", systemImage: "speedometer")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isTestingLatency)
                        
                        // 应用按钮
                        Button(action: applyMirror) {
                            Label("应用镜像源", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                    Button(action: applyMirror) {
                        HStack {
                            Spacer()
                            Label("应用镜像源", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                } header: {
                    Text("镜像源")
                        .font(.headline)
                }
                
                // 维护操作
                Section {
                    VStack(spacing: 12) {
                        Button(action: { showingUpdateAlert = true }) {
                            HStack {
                                Label("更新 Homebrew", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { showingCleanupAlert = true }) {
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
                        
                        Button(action: { showingDoctorAlert = true }) {
                            HStack {
                                Label("运行诊断", systemImage: "stethoscope")
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
                
                // 关于
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(title: "版本", value: "1.0.0")
                        InfoRow(title: "构建日期", value: "2026-04-03")
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
            currentMirrorName = await viewModel.detectCurrentMirror()
        }
        .alert("清理确认", isPresented: $showingCleanupAlert) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task { await viewModel.cleanup() }
            }
        } message: {
            Text("这将删除所有已卸载包的旧版本。确定要继续吗？")
        }
        .alert("更新确认", isPresented: $showingUpdateAlert) {
            Button("取消", role: .cancel) {}
            Button("更新") {
                Task { await viewModel.update() }
            }
        } message: {
            Text("这将更新 Homebrew 本身到最新版本。确定要继续吗？")
        }
        .sheet(isPresented: $showingDoctorAlert) {
            DoctorResultView(diagnostics: viewModel.diagnostics)
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
    
    private func applyMirror() {
        let preset: MirrorPreset
        if isCustom {
            preset = MirrorPreset(
                id: "custom",
                name: "自定义",
                apiDomain: customApiDomain,
                bottleDomain: customBottleDomain,
                coreGit: customCoreGit,
                caskGit: customCaskGit
            )
        } else {
            preset = selectedPreset
        }
        
        switchResultMessage = viewModel.switchMirror(to: preset)
        currentMirrorName = preset.name
        showingSwitchResult = true
    }
    
    private func testLatency() {
        isTestingLatency = true
        latencyResults = [:]
        
        DispatchQueue.global(qos: .userInitiated).async {
            let results = SettingsViewModel.testMirrorLatency()
            DispatchQueue.main.async {
                self.latencyResults = results
                self.isTestingLatency = false
                
                // 自动选中延迟最低的源
                if let best = results.min(by: { $0.value < $1.value }),
                   let preset = MirrorPreset.allPresets.first(where: { $0.name == best.key }) {
                    self.selectedPreset = preset
                    self.isCustom = false
                }
            }
        }
    }
    
    private func latencyColor(_ latency: TimeInterval) -> Color {
        if latency < 0 { return .red }
        if latency < 100 { return .green }
        if latency < 300 { return .yellow }
        return .orange }
    }

// MARK: - 自定义输入字段

struct CustomField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

// MARK: - 延迟检测结果视图

struct LatencyResultView: View {
    let isTesting: Bool
    let results: [String: TimeInterval]
    let latencyColor: (TimeInterval) -> Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("延迟检测")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if isTesting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在检测各源延迟...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                let sorted = results.sorted { $0.value < $1.value }
                let best = sorted.first?.value ?? 0
                
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, item in
                    LatencyRowView(
                        name: item.key,
                        latency: item.value,
                        best: best,
                        isBest: index == 0,
                        latencyColor: latencyColor
                    )
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct LatencyRowView: View {
    let name: String
    let latency: TimeInterval
    let best: TimeInterval
    let isBest: Bool
    let latencyColor: (TimeInterval) -> Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isBest ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isBest ? .green : .secondary.opacity(0.3))
                .font(.caption)
            
            Text(name)
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            
            let barWidth: CGFloat = latency > 0 ? min(max(CGFloat(latency / max(best, 1)) * 120, 0), 250) : 0
            RoundedRectangle(cornerRadius: 2)
                .fill(latencyColor(latency))
                .frame(width: barWidth, height: 6)
            
            Text(latency > 0 ? String(format: "%.0f ms", latency) : "超时")
                .font(.caption.monospacedDigit())
                .foregroundColor(latency > 0 ? (isBest ? .green : .secondary) : .red)
                .frame(width: 60, alignment: .trailing)
            
            Spacer()
            
            if isBest {
                Text("推荐")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - 信息行

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

// MARK: - 诊断结果视图

struct DoctorResultView: View {
    let diagnostics: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("诊断结果")
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
            
            ScrollView {
                Text(diagnostics.isEmpty ? "正在运行诊断..." : diagnostics)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

// MARK: - ViewModel

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var isHomebrewAvailable = false
    @Published var diagnostics = ""
    @Published var brewPrefix = "未知"
    @Published var cellarPath = "未知"
    @Published var brewBinPath = "未知"
    @Published var tapCount = 0
    @Published var installedCount = 0
    
    private let service = HomebrewService.shared
    
    init() {
        isHomebrewAvailable = service.checkHomebrewAvailability()
        if isHomebrewAvailable {
            loadBrewInfo()
        }
    }
    
    private func loadBrewInfo() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew") {
            brewPrefix = "/opt/homebrew"
            cellarPath = "/opt/homebrew/Cellar"
            brewBinPath = "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/Homebrew") {
            brewPrefix = "/usr/local"
            cellarPath = "/usr/local/Cellar"
            brewBinPath = "/usr/local/bin/brew"
        }
        
        if let enumerator = FileManager.default.enumerator(atPath: cellarPath) {
            var count = 0
            while enumerator.nextObject() != nil { count += 1 }
            installedCount = count
        }
        
        let tapDir = brewPrefix + "/Library/Taps"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tapDir) {
            tapCount = contents.count
        }
    }
    
    /// 检测当前使用的镜像源
    func detectCurrentMirror() async -> String {
        let result = await service.executeBrewCommand(arguments: ["config"])
        switch result {
        case .success(let output):
            for preset in MirrorPreset.allPresets where preset != .official {
                if output.contains(preset.apiDomain) || output.contains(preset.bottleDomain) {
                    return preset.name
                }
            }
            let shellConfig = readShellConfig()
            for preset in MirrorPreset.allPresets where preset != .official {
                if shellConfig.contains(preset.apiDomain) || shellConfig.contains(preset.bottleDomain) {
                    return "\(preset.name) (已配置但未生效，需重启终端)"
                }
            }
            return "官方源"
        case .failure:
            let shellConfig = readShellConfig()
            for preset in MirrorPreset.allPresets where preset != .official {
                if shellConfig.contains(preset.apiDomain) || shellConfig.contains(preset.bottleDomain) {
                    return "\(preset.name) (配置在 Shell 中)"
                }
            }
            return "官方源"
        }
    }
    
    /// 测试所有镜像源的延迟（非 MainActor 隔离）
    nonisolated static func testMirrorLatency() -> [String: TimeInterval] {
        var results: [String: TimeInterval] = [:]

        for preset in MirrorPreset.allPresets {
            let latency = testSingleURL(urlString: preset.apiDomain)
            results[preset.name] = latency
        }

        return results
    }

    /// 测试单个 URL 的延迟（HTTP HEAD 请求）
    private nonisolated static func testSingleURL(urlString: String) -> TimeInterval {
        guard let url = URL(string: urlString) else { return -1 }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        
        let semaphore = DispatchSemaphore(value: 0)
        var latency: TimeInterval = -1
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            
            if let httpResponse = response as? HTTPURLResponse,
               (200..<400).contains(httpResponse.statusCode) {
                latency = elapsed * 1000 // 转为毫秒
            } else {
                latency = -1 // 超时或错误
            }
            semaphore.signal()
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 6)
        return latency
    }
    
    private func readShellConfig() -> String {
        let home = NSHomeDirectory()
        var content = ""
        for file in [".zshrc", ".bash_profile", ".bashrc", ".zprofile"] {
            let path = home + "/" + file
            if let data = try? String(contentsOfFile: path, encoding: .utf8) {
                content += data + "\n"
            }
        }
        return content
    }
    
    /// 切换镜像源
    func switchMirror(to preset: MirrorPreset) -> String {
        let home = NSHomeDirectory()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let configFile: String
        if shell.contains("zsh") {
            configFile = home + "/.zshrc"
        } else {
            configFile = home + "/.bash_profile"
        }
        
        var log = ""
        
        // 读取现有配置
        let configContent = (try? String(contentsOfFile: configFile, encoding: .utf8)) ?? ""
        
        // 移除旧的 Homebrew 镜像配置
        let patterns = [
            "HOMEBREW_API_DOMAIN", "HOMEBREW_BOTTLE_DOMAIN",
            "HOMEBREW_BREW_GIT_REMOTE", "HOMEBREW_CORE_GIT_REMOTE", "HOMEBREW_CASK_GIT_REMOTE"
        ]
        
        var lines = configContent.components(separatedBy: "\n")
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return patterns.contains(where: { trimmed.contains($0) }) && trimmed.starts(with: "export")
        }
        
        if preset == .official {
            // 恢复官方源
            log += "已从 Shell 配置中移除镜像源设置\n\n"
            log += switchGitRemote(coreGit: "https://github.com/Homebrew/homebrew-core",
                                   caskGit: "https://github.com/Homebrew/homebrew-cask")
            // 立即生效：清除当前进程的镜像环境变量
            service.updateMirrorEnvVars([:])
        } else {
            // 写入新配置
            var newLines: [String] = []
            newLines.append("# Homebrew 镜像源配置 - 由 Tifa 生成")
            newLines.append("export HOMEBREW_API_DOMAIN=\"\(preset.apiDomain)\"")
            newLines.append("export HOMEBREW_BOTTLE_DOMAIN=\"\(preset.bottleDomain)\"")
            if !preset.coreGit.isEmpty {
                newLines.append("export HOMEBREW_CORE_GIT_REMOTE=\"\(preset.coreGit)\"")
            }
            if !preset.caskGit.isEmpty {
                newLines.append("export HOMEBREW_CASK_GIT_REMOTE=\"\(preset.caskGit)\"")
            }
            
            lines.append("")
            lines.append(contentsOf: newLines)
            
            log += "已切换到 \(preset.name) 镜像源\n\n"
            log += "配置已写入: \(configFile)\n\n"
            log += "配置内容:\n"
            for line in newLines {
                log += "  \(line)\n"
            }
            
            // 自动切换 git remote
            if !preset.coreGit.isEmpty {
                log += "\n"
                log += switchGitRemote(coreGit: preset.coreGit, caskGit: preset.caskGit)
            }
            
            // 立即生效：更新当前进程的镜像环境变量
            var envVars: [String: String] = [
                "HOMEBREW_API_DOMAIN": preset.apiDomain,
                "HOMEBREW_BOTTLE_DOMAIN": preset.bottleDomain
            ]
            if !preset.coreGit.isEmpty {
                envVars["HOMEBREW_CORE_GIT_REMOTE"] = preset.coreGit
            }
            if !preset.caskGit.isEmpty {
                envVars["HOMEBREW_CASK_GIT_REMOTE"] = preset.caskGit
            }
            service.updateMirrorEnvVars(envVars)
            log += "\n✅ 镜像源已在当前程序中立即生效"
        }
        
        // 保存配置
        let newContent = lines.joined(separator: "\n")
        do {
            try newContent.write(toFile: configFile, atomically: true, encoding: .utf8)
            log += "\n\n✅ 配置文件已保存成功（新打开的终端也将使用新源）"
        } catch {
            log += "\n\n❌ 保存配置文件失败: \(error.localizedDescription)"
        }
        
        return log
    }
    
    /// 执行 git remote set-url 切换仓库源
    private func switchGitRemote(coreGit: String, caskGit: String) -> String {
        var log = "正在切换 Git 仓库源...\n\n"
        
        // 通过 brew --repo 动态获取真实 tap 路径
        let brewPrefix: String
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPrefix = "/opt/homebrew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            brewPrefix = "/usr/local"
        } else {
            brewPrefix = ""
        }
        
        let env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        var procEnv = env
        procEnv["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(path)"
        procEnv["HOME"] = NSHomeDirectory()
        
        // 获取 homebrew-core 仓库路径
        let coreRepoResult = runCommand(executable: brewPrefix.isEmpty ? "brew" : "\(brewPrefix)/bin/brew",
                                        arguments: ["--repo", "homebrew/core"],
                                        environment: procEnv)
        let coreRepoPath = coreRepoResult.success ? coreRepoResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        
        // 获取 homebrew-cask 仓库路径
        let caskRepoResult = runCommand(executable: brewPrefix.isEmpty ? "brew" : "\(brewPrefix)/bin/brew",
                                        arguments: ["--repo", "homebrew/cask"],
                                        environment: procEnv)
        let caskRepoPath = caskRepoResult.success ? caskRepoResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        
        if coreRepoPath.isEmpty {
            log += "ℹ️ 当前使用 Homebrew API 模式，无需切换 Core Git 仓库\n"
        } else if !FileManager.default.fileExists(atPath: coreRepoPath) {
            log += "ℹ️ 当前使用 Homebrew API 模式，无需切换 Core Git 仓库\n"
        } else {
            let coreResult = runCommand(executable: "/usr/bin/git", arguments: [
                "-C", coreRepoPath,
                "remote", "set-url", "origin", coreGit
            ], environment: procEnv)
            
            if coreResult.success {
                log += "✅ Core 仓库已切换到 \(coreGit)\n"
            } else {
                log += "⚠️ Core 仓库切换失败: \(coreResult.output)\n"
            }
        }
        
        if caskRepoPath.isEmpty {
            log += "ℹ️ 当前使用 Homebrew API 模式，无需切换 Cask Git 仓库\n"
        } else if !FileManager.default.fileExists(atPath: caskRepoPath) {
            log += "ℹ️ 当前使用 Homebrew API 模式，无需切换 Cask Git 仓库\n"
        } else {
            let caskResult = runCommand(executable: "/usr/bin/git", arguments: [
                "-C", caskRepoPath,
                "remote", "set-url", "origin", caskGit
            ], environment: procEnv)
            
            if caskResult.success {
                log += "✅ Cask 仓库已切换到 \(caskGit)\n"
            } else {
                log += "⚠️ Cask 仓库切换失败: \(caskResult.output)\n"
            }
        }
        
        return log
    }
    
    /// 同步执行外部命令
    private func runCommand(executable: String, arguments: [String], environment: [String: String] = [:]) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    func cleanup() async {
        _ = await service.cleanupPackages()
    }
    
    func update() async {
        _ = await service.updateHomebrew()
    }
    
    func runDoctor() async {
        diagnostics = await service.getDiagnostics()
    }
}

#Preview {
    SettingsView()
}
