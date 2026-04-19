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

// MARK: - 镜像源视图

struct MirrorSourceView: View {
    @StateObject private var viewModel = MirrorSourceViewModel()
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
        VStack(spacing: 0) {
            // 顶部当前状态栏
            HStack(spacing: 16) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前镜像源")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentMirrorName)
                        .font(.headline)
                }

                Spacer()

                Button(action: testLatency) {
                    HStack(spacing: 6) {
                        if isTestingLatency {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "speedometer")
                        }
                        Text(isTestingLatency ? "检测中" : "一键测速")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(isTestingLatency)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 主内容区 - 上下分栏
            VStack(spacing: 0) {
                // 上半部分：镜像源选择列表
                mirrorSelectionList

                Divider()

                // 下半部分：测速结果 + 自定义
                bottomPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            currentMirrorName = await viewModel.detectCurrentMirror()
        }
        .sheet(isPresented: $showingSwitchResult) {
            VStack(spacing: 16) {
                HStack {
                    Text("切换结果")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingSwitchResult = false }
                        .buttonStyle(.bordered)
                }

                ScrollView {
                    Text(switchResultMessage)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            .padding(24)
            .frame(width: 550, height: 350)
        }
    }

    // MARK: - 镜像源列表

    private var mirrorSelectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择镜像源")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(MirrorPreset.allPresets) { preset in
                        MirrorSourceRow(
                            preset: preset,
                            isSelected: selectedPreset == preset && !isCustom,
                            latency: latencyResults[preset.name],
                            isBest: isBestMirror(name: preset.name),
                            isTesting: isTestingLatency
                        ) {
                            selectedPreset = preset
                            isCustom = false
                        }

                        // 自定义入口
                        if preset == .bfban {
                            MirrorCustomToggleRow(
                                isExpanded: isCustom,
                                onTap: { withAnimation(.easeInOut(duration: 0.25)) { isCustom.toggle() } }
                            )

                            if isCustom {
                                customFieldsPanel
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - 自定义输入面板

    private var customFieldsPanel: some View {
        VStack(spacing: 10) {
            customFieldRow("API 域名", placeholder: "https://example.com/api", text: $customApiDomain)
            customFieldRow("Bottle 域名", placeholder: "https://example.com/bottles", text: $customBottleDomain)
            customFieldRow("Core Git", placeholder: "https://example.com/homebrew-core.git", text: $customCoreGit)
            customFieldRow("Cask Git", placeholder: "https://example.com/homebrew-cask.git", text: $customCaskGit)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func customFieldRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }

    // MARK: - 底部面板

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if !latencyResults.isEmpty {
                latencyPanel
                Divider()
            }

            // 应用按钮
            HStack {
                Spacer()
                Button(action: applyMirror) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("应用镜像源")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - 延迟面板

    private struct LatencyItem: Identifiable {
        let id = UUID()
        let index: Int
        let key: String
        let value: Double
    }

    private var latencyItems: [LatencyItem] {
        latencyResults
            .sorted { $0.value < $1.value }
            .enumerated()
            .map { i, item in
                LatencyItem(index: i, key: item.key, value: item.value)
            }
    }

    private var latencyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("测速结果")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("按延迟排序，自动推荐最优源")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            latencyContent
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var latencyContent: some View {
        let items = latencyItems
        let bestLatency = items.first?.value ?? 0

        return HStack(spacing: 0) {
            buildLatencyCards(items: items, bestLatency: bestLatency)
        }
    }

    private func buildLatencyCards(items: [LatencyItem], bestLatency: Double) -> some View {
        let views: [AnyView] = items.enumerated().map { index, item in
            var views: [AnyView] = []
            if item.index > 0 {
                views.append(AnyView(
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                ))
            }
            views.append(AnyView(
                VStack(spacing: 4) {
                    Text(item.key)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if item.value < 0 {
                        Text("超时")
                            .font(.caption2.bold())
                            .foregroundColor(.red)
                    } else {
                        Text(String(format: "%.0f", item.value))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(latencyColor(item.value))
                        Text("ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if index == 0 && bestLatency > 0 {
                        Text("推荐")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            ))
            return views
        }.flatMap { $0 }

        return Group {
            ForEach(0..<views.count, id: \.self) { i in
                views[i]
            }
        }
    }

    // MARK: - 方法

    private func isBestMirror(name: String) -> Bool {
        guard let best = latencyResults.min(by: { $0.value < $1.value }) else { return false }
        return best.key == name && best.value > 0
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
            let results = MirrorSourceViewModel.testMirrorLatency()
            DispatchQueue.main.async {
                self.latencyResults = results
                self.isTestingLatency = false

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
        return .orange
    }
}

// MARK: - 镜像源行

private struct MirrorSourceRow: View {
    let preset: MirrorPreset
    let isSelected: Bool
    let latency: TimeInterval?
    let isBest: Bool
    let isTesting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // 选中指示器
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }

                // 名称
                Text(preset.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(width: 60, alignment: .leading)

                // 域名预览
                Text(preset.apiDomain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // 延迟标签
                if isTesting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else if let latency = latency {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(latencyColor(latency))
                            .frame(width: 6, height: 6)
                        Text(latency > 0 ? String(format: "%.0f ms", latency) : "超时")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(latency > 0 ? (isBest ? .green : .secondary) : .red)
                    }
                    .frame(width: 64, alignment: .trailing)

                    if isBest && latency > 0 {
                        Text("最佳")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.1)))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func latencyColor(_ latency: TimeInterval) -> Color {
        if latency < 0 { return .red }
        if latency < 100 { return .green }
        if latency < 300 { return .yellow }
        return .orange
    }
}

// MARK: - 自定义切换行

private struct MirrorCustomToggleRow: View {
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isExpanded ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isExpanded {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }

                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                Text("自定义镜像源")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isExpanded ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isExpanded ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
class MirrorSourceViewModel: ObservableObject {
    private let service = HomebrewService.shared

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

    nonisolated static func testMirrorLatency() -> [String: TimeInterval] {
        var results: [String: TimeInterval] = [:]
        for preset in MirrorPreset.allPresets {
            let latency = testSingleURL(urlString: preset.apiDomain)
            results[preset.name] = latency
        }
        return results
    }

    private nonisolated static func testSingleURL(urlString: String) -> TimeInterval {
        guard let url = URL(string: urlString) else { return -1 }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        let semaphore = DispatchSemaphore(value: 0)
        var latency: TimeInterval = -1
        let startTime = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if let httpResponse = response as? HTTPURLResponse,
               (200..<400).contains(httpResponse.statusCode) {
                latency = elapsed * 1000
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

    func switchMirror(to preset: MirrorPreset) -> String {
        let home = NSHomeDirectory()
        let shell = Foundation.ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let configFile: String
        if shell.contains("zsh") {
            configFile = home + "/.zshrc"
        } else {
            configFile = home + "/.bash_profile"
        }

        var log = ""
        let configContent = (try? String(contentsOfFile: configFile, encoding: .utf8)) ?? ""
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
            log += "已从 Shell 配置中移除镜像源设置\n\n"
            log += switchGitRemote(coreGit: "https://github.com/Homebrew/homebrew-core",
                                   caskGit: "https://github.com/Homebrew/homebrew-cask")
            service.updateMirrorEnvVars([:])
        } else {
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

            if !preset.coreGit.isEmpty {
                log += "\n"
                log += switchGitRemote(coreGit: preset.coreGit, caskGit: preset.caskGit)
            }

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

        let newContent = lines.joined(separator: "\n")
        do {
            try newContent.write(toFile: configFile, atomically: true, encoding: .utf8)
            log += "\n\n✅ 配置文件已保存成功（新打开的终端也将使用新源）"
        } catch {
            log += "\n\n❌ 保存配置文件失败: \(error.localizedDescription)"
        }

        return log
    }

    private func switchGitRemote(coreGit: String, caskGit: String) -> String {
        var log = "正在切换 Git 仓库源...\n\n"

        let brewPrefix: String
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPrefix = "/opt/homebrew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            brewPrefix = "/usr/local"
        } else {
            brewPrefix = ""
        }

        let env = Foundation.ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        var procEnv = env
        procEnv["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(path)"
        procEnv["HOME"] = NSHomeDirectory()

        let coreRepoResult = runCommand(executable: brewPrefix.isEmpty ? "brew" : "\(brewPrefix)/bin/brew",
                                        arguments: ["--repo", "homebrew/core"],
                                        environment: procEnv)
        let coreRepoPath = coreRepoResult.success ? coreRepoResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let caskRepoResult = runCommand(executable: brewPrefix.isEmpty ? "brew" : "\(brewPrefix)/bin/brew",
                                        arguments: ["--repo", "homebrew/cask"],
                                        environment: procEnv)
        let caskRepoPath = caskRepoResult.success ? caskRepoResult.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if coreRepoPath.isEmpty || !FileManager.default.fileExists(atPath: coreRepoPath) {
            log += "ℹ️ 当前使用 Homebrew API 模式，无需切换 Core Git 仓库\n"
        } else {
            let coreResult = runCommand(executable: "/usr/bin/git", arguments: [
                "-C", coreRepoPath, "remote", "set-url", "origin", coreGit
            ], environment: procEnv)
            log += coreResult.success
                ? "✅ Core 仓库已切换到 \(coreGit)\n"
                : "⚠️ Core 仓库切换失败: \(coreResult.output)\n"
        }

        if caskRepoPath.isEmpty || !FileManager.default.fileExists(atPath: caskRepoPath) {
            log += "ℹ️ 当前使用 Homebrew API 模式，无需切换 Cask Git 仓库\n"
        } else {
            let caskResult = runCommand(executable: "/usr/bin/git", arguments: [
                "-C", caskRepoPath, "remote", "set-url", "origin", caskGit
            ], environment: procEnv)
            log += caskResult.success
                ? "✅ Cask 仓库已切换到 \(caskGit)\n"
                : "⚠️ Cask 仓库切换失败: \(caskResult.output)\n"
        }

        return log
    }

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
}

#Preview {
    MirrorSourceView()
}
