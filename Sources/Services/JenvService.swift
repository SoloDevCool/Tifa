import Foundation

/// jenv 管理的 Java 版本信息
struct JenvJavaVersion: Identifiable, Hashable {
    let id: String
    let version: String
    let isGlobal: Bool
    let installedPath: String?
}

/// JEnv 服务 - 管理 jenv 和 Java 版本
@MainActor
class JenvService: ObservableObject {

    static let shared = JenvService()

    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var brokenJdkLinks: [String] = []

    /// 当前正在执行的安装进程（用于取消）
    private var currentInstallProcess: Process?

    /// 取消当前安装进程
    func cancelCurrentInstall() {
        currentInstallProcess?.terminate()
        currentInstallProcess = nil
    }

    /// brew 可执行文件绝对路径
    private var brewPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }

    /// Homebrew 前缀路径
    private var brewPrefix: String {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }

    /// jenv 安装目录
    private var jenvDir: String {
        "\(NSHomeDirectory())/.jenv"
    }

    /// 构建 jenv 命令执行环境
    private var jenvEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        let jenvPaths = "\(jenvDir)/bin:\(jenvDir)/shims"
        let extraPaths = "\(brewPrefix)/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(jenvPaths):\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = "\(jenvPaths):\(extraPaths)"
        }
        return env
    }

    // MARK: - 安装/卸载 jenv

    /// 使用 Homebrew 安装 jenv
    func installJenv(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "\(brewPath) install jenv"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }

                do {
                    try process.run()
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    var timedOut = false
                    timer.schedule(deadline: .now() + 300)
                    timer.setEventHandler { timedOut = true; process.terminate() }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let remainingStdout = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if timedOut {
                        continuation.resume(returning: .failure("安装超时（5 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("jenv 安装成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "安装失败 (exit code \(process.terminationStatus))" : remainingStderr
                        continuation.resume(returning: .failure(errorMsg))
                    }
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    continuation.resume(returning: .failure("无法执行安装命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 使用 Homebrew 卸载 jenv
    func uninstallJenv() async -> OperationResult {
        isLoading = true
        loadingMessage = "正在卸载 jenv..."
        defer { isLoading = false }

        let result = await executeJenvCommand(arguments: ["remove", "--force", "-a"])
        _ = result
        return await executeRawCommand(script: "\(brewPath) uninstall jenv && rm -rf \(jenvDir)")
    }

    // MARK: - 检查可用性

    /// 检查 jenv 是否已安装
    func checkJenvAvailable() -> Bool {
        let paths = [
            "\(brewPrefix)/bin/jenv",
            "/usr/local/bin/jenv",
            "\(NSHomeDirectory())/.jenv/bin/jenv"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 获取 jenv 版本
    func getJenvVersion() async -> String {
        let result = await executeJenvCommand(arguments: ["--version"])
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }

    /// 检查 jenv shell 环境是否已配置
    func isJenvConfigured() async -> Bool {
        let configFiles = [".zshrc", ".bash_profile", ".bashrc", ".profile"]
        let home = NSHomeDirectory()

        for file in configFiles {
            let path = "\(home)/\(file)"
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                if content.contains("jenv") || content.contains("JENV") {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Java 版本管理

    /// 获取已注册的 Java 版本列表
    func listVersions() async -> [JenvJavaVersion] {
        let result = await executeJenvCommand(arguments: ["versions"])
        guard case .success(let output) = result else { return [] }

        return parseJenvVersions(output: output)
    }

    /// 添加 JDK 路径到 jenv
    func addVersion(path: String) async -> OperationResult {
        return await executeJenvCommandWithProgress(arguments: ["add", path])
    }

    /// 移除 Java 版本
    func removeVersion(_ version: String) async -> OperationResult {
        return await executeJenvCommandWithProgress(arguments: ["remove", version])
    }

    /// 设置全局 Java 版本
    func setGlobalVersion(_ version: String) async -> OperationResult {
        return await executeJenvCommandWithProgress(arguments: ["global", version])
    }

    /// 获取当前全局版本
    func getGlobalVersion() async -> String {
        let result = await executeJenvCommand(arguments: ["global"])
        if case .success(let output) = result {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "no global version configured" {
                return "未设置"
            }
            return trimmed
        }
        return "未知"
    }

    /// 获取 jenv 路径
    func getJenvPath() -> String {
        let paths = [
            "\(brewPrefix)/bin/jenv",
            "/usr/local/bin/jenv",
            "\(jenvDir)/bin/jenv"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) } ?? "未知"
    }

    /// 扫描系统中已安装的 JDK
    func scanSystemJdks() async -> [(name: String, path: String)] {
        var jdks: [(name: String, path: String)] = []
        var brokenLinks: [String] = []

        // 方法1: 使用 /usr/libexec/java_home -V 扫描
        let javaHomeResult = await runCommand("/usr/libexec/java_home", arguments: ["-V"])
        if case .success(let output) = javaHomeResult {
            // 输出格式: "Java(TM) SE Runtime Environment (build 17.0.2+8-86)" 或 "AdoptOpenJDK (build 11.0.11+9)"
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.isEmpty == false else { continue }
                // 从 java_home -V 输出提取路径（最后一列在引号中或最后一个空格后）
                if let range = trimmed.range(of: "\"([^\"]+)\"", options: .regularExpression) {
                    let path = String(trimmed[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if FileManager.default.fileExists(atPath: path) {
                        let homePath = path.hasSuffix("/Home") ? path : "\(path)/Contents/Home"
                        let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".jdk", with: "")
                        if FileManager.default.fileExists(atPath: homePath) {
                            if !jdks.contains(where: { $0.path == homePath }) {
                                jdks.append((name: name, path: homePath))
                            }
                        }
                    }
                }
            }
        }

        // 方法2: 遍历 /Library/Java/JavaVirtualMachines
        let jvmPaths = [
            "/Library/Java/JavaVirtualMachines",
            "\(NSHomeDirectory())/Library/Java/JavaVirtualMachines"
        ]

        for jvmPath in jvmPaths {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: jvmPath) {
                for item in contents where item.hasSuffix(".jdk") || item.hasSuffix(".jre") {
                    let fullPath = "\(jvmPath)/\(item)"
                    let homePath = "\(fullPath)/Contents/Home"

                    if FileManager.default.fileExists(atPath: homePath) {
                        let name = item.replacingOccurrences(of: ".jdk", with: "").replacingOccurrences(of: ".jre", with: "")
                        if !jdks.contains(where: { $0.path == homePath }) {
                            jdks.append((name: name, path: homePath))
                        }
                    } else {
                        // 检查是否是损坏的符号链接
                        let fm = FileManager.default
                        if fm.fileExists(atPath: fullPath) == false {
                            do {
                                let linkDest = try fm.destinationOfSymbolicLink(atPath: fullPath)
                                brokenLinks.append("\(item) → \(linkDest)（链接已损坏）")
                            } catch {
                                brokenLinks.append("\(item)（无法访问）")
                            }
                        }
                    }
                }
            }
        }

        // 方法3: 遍历 Homebrew Cellar 下的 JDK
        let cellarPath = "\(brewPrefix)/Cellar"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: cellarPath) {
            for item in contents where item.lowercased().contains("openjdk") || item.lowercased().contains("jdk") {
                let jdkDir = "\(cellarPath)/\(item)"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: jdkDir) {
                    for ver in versions.sorted().reversed() {
                        let libexecPath = "\(jdkDir)/\(ver)/libexec/openjdk.jdk/Contents/Home"
                        let normalPath = "\(jdkDir)/\(ver)/libexec"
                        if FileManager.default.fileExists(atPath: libexecPath) {
                            if !jdks.contains(where: { $0.path == libexecPath }) {
                                jdks.append((name: "openjdk \(ver)", path: libexecPath))
                            }
                        } else if FileManager.default.fileExists(atPath: "\(normalPath)/bin/java") {
                            if !jdks.contains(where: { $0.path == normalPath }) {
                                jdks.append((name: "openjdk \(ver)", path: normalPath))
                            }
                        }
                    }
                }
            }
        }

        // 方法4: 检查 Homebrew opt 下的 JDK
        let homebrewJdkPaths = [
            "\(brewPrefix)/opt/openjdk",
            "\(brewPrefix)/opt/openjdk@11",
            "\(brewPrefix)/opt/openjdk@17",
            "\(brewPrefix)/opt/openjdk@21",
            "\(brewPrefix)/opt/openjdk@22",
            "\(brewPrefix)/opt/openjdk@23"
        ]
        for path in homebrewJdkPaths {
            if FileManager.default.fileExists(atPath: "\(path)/libexec/openjdk.jdk/Contents/Home") {
                let finalPath = "\(path)/libexec/openjdk.jdk/Contents/Home"
                let name = path.hasSuffix("/opt/openjdk") ? "openjdk" : String(path.split(separator: "@").last ?? "openjdk")
                if !jdks.contains(where: { $0.path == finalPath }) {
                    jdks.append((name: "openjdk \(name)", path: finalPath))
                }
            } else if FileManager.default.fileExists(atPath: "\(path)/libexec/bin/java") {
                let finalPath = "\(path)/libexec"
                let name = path.hasSuffix("/opt/openjdk") ? "openjdk" : String(path.split(separator: "@").last ?? "openjdk")
                if !jdks.contains(where: { $0.path == finalPath }) {
                    jdks.append((name: "openjdk \(name)", path: finalPath))
                }
            }
        }

        // 方法5: 使用 which/whereis 查找 java
        let whereResult = await runCommand("/usr/bin/which", arguments: ["java"])
        if case .success(let output) = whereResult {
            let javaPath = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if javaPath.hasPrefix("/") && !javaPath.hasPrefix("/usr/bin/java") {
                // 非 macOS 自带 java，可能是自定义安装
                let javaDir = (javaPath as NSString).deletingLastPathComponent
                if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: javaPath) {
                    let resolvedDir = (resolved as NSString).deletingLastPathComponent
                    if !jdks.contains(where: { $0.path == resolvedDir }) {
                        let name = (resolvedDir as NSString).lastPathComponent
                        jdks.append((name: name, path: resolvedDir))
                    }
                }
            }
        }

        // 保存损坏链接信息
        if !brokenLinks.isEmpty {
            self.brokenJdkLinks = brokenLinks
        }

        return jdks
    }

    /// 获取已启用的插件列表
    func getEnabledPlugins() async -> [String] {
        let result = await executeJenvCommand(arguments: ["plugins"])
        guard case .success(let output) = result else { return [] }

        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("*") || $0.contains("enabled") }
            .map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces) }
    }

    /// 启用插件
    func enablePlugin(_ plugin: String) async -> OperationResult {
        return await executeJenvCommandWithProgress(arguments: ["enable-plugin", plugin])
    }

    /// 禁用插件
    func disablePlugin(_ plugin: String) async -> OperationResult {
        return await executeJenvCommandWithProgress(arguments: ["disable-plugin", plugin])
    }

    /// 获取可用插件列表
    func getAvailablePlugins() async -> [String] {
        let result = await executeJenvCommand(arguments: ["plugins"])
        guard case .success(let output) = result else { return [] }

        // 解析插件列表，提取所有插件名称（包括未启用的）
        var plugins: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.hasPrefix("Available") && !trimmed.hasPrefix("---") else { continue }
            // 提取插件名：可能是 "* plugin-name" 或 "  plugin-name"
            let name = trimmed.replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).first ?? ""
            if !name.isEmpty {
                plugins.append(name)
            }
        }
        return plugins
    }

    /// 安装指定版本的 OpenJDK（通过 Homebrew，带实时输出）
    func installOpenJdk(version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let formula = "openjdk@\(version)"
        let script = "HOMEBREW_NO_AUTO_UPDATE=1 \(brewPath) install \(formula)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                Task { @MainActor in
                    self.currentInstallProcess = process
                }

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }

                do {
                    try process.run()
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    var timedOut = false
                    timer.schedule(deadline: .now() + 600)
                    timer.setEventHandler { timedOut = true; process.terminate() }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    Task { @MainActor in
                        self.currentInstallProcess = nil
                    }

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let remainingStdout = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if timedOut {
                        continuation.resume(returning: .failure("安装超时（10 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        // 安装成功后，自动创建符号链接到 JVM 目录
                        Task { @MainActor in
                            onOutput("\n🔗 正在配置 Java 环境...\n")
                        }
                        let linkResult = self.linkOpenJdkToSystem(version: version)
                        Task { @MainActor in
                            onOutput(linkResult + "\n")
                        }
                        continuation.resume(returning: .success("OpenJDK \(version) 安装成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "安装失败 (exit code \(process.terminationStatus))" : remainingStderr
                        continuation.resume(returning: .failure(errorMsg))
                    }
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    continuation.resume(returning: .failure("无法执行安装命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 获取 Homebrew 中可用的 OpenJDK 版本列表
    func getAvailableOpenJdkVersions() -> [String] {
        return ["8", "11", "17", "21", "22", "23", "24", "25"]
    }

    /// 将 Homebrew 安装的 OpenJDK 符号链接到用户 JVM 目录（不需要 sudo）
    private func linkOpenJdkToSystem(version: String) -> String {
        let brewJdkPath = "\(brewPrefix)/opt/openjdk@\(version)/libexec/openjdk.jdk"
        let userJvmDir = "\(NSHomeDirectory())/Library/Java/JavaVirtualMachines"
        let userJvmPath = "\(userJvmDir)/openjdk-\(version).jdk"

        guard FileManager.default.fileExists(atPath: brewJdkPath) else {
            return "⚠️ 未找到 Homebrew 安装的 OpenJDK: \(brewJdkPath)"
        }

        // 确保用户 JVM 目录存在
        do {
            try FileManager.default.createDirectory(atPath: userJvmDir, withIntermediateDirectories: true)
        } catch {
            return "⚠️ 无法创建目录 \(userJvmDir):\n\(error.localizedDescription)"
        }

        // 如果已存在旧链接，先删除
        if FileManager.default.fileExists(atPath: userJvmPath) {
            try? FileManager.default.removeItem(atPath: userJvmPath)
        }

        do {
            try FileManager.default.createSymbolicLink(atPath: userJvmPath, withDestinationPath: brewJdkPath)
            return "✅ 已链接到 \(userJvmPath)"
        } catch {
            return "⚠️ 链接失败: \(error.localizedDescription)"
        }
    }

    /// 修复所有已安装的 OpenJDK 的系统链接
    func fixAllOpenJdkLinks(onOutput: @escaping @MainActor (String) -> Void) async {
        let installedVersions = await listInstalledOpenJdkVersions()
        if installedVersions.isEmpty {
            onOutput("没有检测到已安装的 OpenJDK 版本\n")
            return
        }

        onOutput("🔧 正在修复 \(installedVersions.count) 个 OpenJDK 版本的系统链接...\n\n")

        var fixedCount = 0
        var failedCount = 0

        for version in installedVersions {
            let result = linkOpenJdkToSystem(version: version)
            onOutput("OpenJDK \(version): \(result)\n")
            if result.hasPrefix("✅") {
                fixedCount += 1
            } else {
                failedCount += 1
            }
        }

        onOutput("\n修复完成: \(fixedCount) 成功, \(failedCount) 失败\n")
    }

    /// 获取通过 Homebrew 已安装的 OpenJDK 版本列表
    func listInstalledOpenJdkVersions() async -> [String] {
        let result = await runCommand(brewPath, arguments: ["list", "--formula", "--quiet"])
        guard case .success(let output) = result else { return [] }

        let installed = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let available = getAvailableOpenJdkVersions()
        return available.filter { version in
            let formula = "openjdk@\(version)"
            return installed.contains { $0 == formula || $0.hasPrefix("\(formula) ") }
        }
    }

    /// 获取当前激活的默认 OpenJDK 版本
    func getActiveJdkVersion() async -> String {
        // 优先从 shell 配置中读取
        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        if let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) {
            // 查找 # Tifa Java Default: openjdk@XX 标记
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# Tifa Java Default: openjdk@"),
                   let range = trimmed.range(of: "openjdk@") {
                    let version = String(trimmed[range.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces).first ?? ""
                    return version
                }
            }
        }

        // 备选：通过 java -version 检测
        let result = await runCommand("/usr/bin/java", arguments: ["-version"])
        if case .success(let output) = result {
            // 输出如: openjdk version "17.0.12" 或 java version "21.0.2"
            if let range = output.range(of: #"version\s+"(\d+)"# , options: .regularExpression) {
                let match = String(output[range])
                if let verRange = match.range(of: #"\d+"# , options: .regularExpression) {
                    let major = String(match[verRange])
                    // 映射到支持的版本号
                    let available = getAvailableOpenJdkVersions()
                    if available.contains(major) {
                        return major
                    }
                }
            }
        }

        return ""
    }

    /// 设置默认的 OpenJDK 版本（通过更新 ~/.zshrc）
    func setActiveJdkVersion(_ version: String) async -> OperationResult {
        let jdkHome = "\(NSHomeDirectory())/Library/Java/JavaVirtualMachines/openjdk-\(version).jdk/Contents/Home"

        guard FileManager.default.fileExists(atPath: jdkHome) else {
            return .failure("OpenJDK \(version) 未正确链接，请先点击\"修复链接\"")
        }

        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        var content: String

        if let existing = try? String(contentsOfFile: zshrcPath, encoding: .utf8) {
            content = existing
        } else {
            content = ""
        }

        // 移除旧的 Tifa Java 配置块
        let pattern = #"\n# === Tifa Java Start ===.*?=== Tifa Java End ===\n"# 
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "\n")
        }

        // 追加新的配置块
        let configBlock = """

        # === Tifa Java Start ===
        # Tifa Java Default: openjdk@\(version)
        export JAVA_HOME="\(jdkHome)"
        export PATH="$JAVA_HOME/bin:$PATH"
        # === Tifa Java End ===
        """

        content += configBlock

        do {
            try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
            return .success("已将 OpenJDK \(version) 设为默认版本\n\n请重启终端或运行: source ~/.zshrc")
        } catch {
            return .failure("写入 ~/.zshrc 失败: \(error.localizedDescription)")
        }
    }

    /// 通过 Homebrew 卸载指定版本 OpenJDK
    func uninstallOpenJdk(version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let formula = "openjdk@\(version)"
        let script = "\(brewPath) uninstall \(formula)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let remainingStdout = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("OpenJDK \(version) 卸载成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "卸载失败" : remainingStderr
                        continuation.resume(returning: .failure(errorMsg))
                    }
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    continuation.resume(returning: .failure("无法执行卸载命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Shell 配置

    /// 配置 shell 环境变量
    func configureShell() async -> OperationResult {
        let configBlock = """

        # jenv (Java Environment Manager)
        export PATH="$HOME/.jenv/bin:$PATH"
        eval "$(jenv init -)"
        """

        let zshrcPath = NSHomeDirectory() + "/.zshrc"

        // 检查是否已有配置
        if FileManager.default.fileExists(atPath: zshrcPath),
           let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8),
           content.contains("jenv init") {
            return .success("jenv 配置已存在于 ~/.zshrc")
        }

        // 追加配置
        if var content = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) {
            content += configBlock
            do {
                try content.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
                return .success("已将 jenv 配置写入 ~/.zshrc\n\n请重启终端或运行: source ~/.zshrc")
            } catch {
                return .failure("写入失败: \(error.localizedDescription)")
            }
        } else {
            do {
                try configBlock.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
                return .success("已创建 ~/.zshrc 并写入 jenv 配置\n\n请重启终端或运行: source ~/.zshrc")
            } catch {
                return .failure("创建文件失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 私有方法

    private func executeJenvCommand(arguments: [String]) async -> OperationResult {
        let env = jenvEnvironment
        let argsStr = arguments.joined(separator: " ")
        let script = "export JENV_ROOT=\"\(jenvDir)\"; [ -s \"\(jenvDir)/bin/jenv\" ] && eval \"$(\(jenvDir)/bin/jenv init -)\"; \(jenvDir)/bin/jenv \(argsStr)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败 (exit code \(process.terminationStatus))" : errorMsg))
                    }
                } catch {
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 运行系统命令并返回结果
    private func runCommand(_ executable: String, arguments: [String]) async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(output))
                    } else {
                        continuation.resume(returning: .failure(output))
                    }
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
    }

    private func executeJenvCommandWithProgress(arguments: [String]) async -> OperationResult {
        isLoading = true
        loadingMessage = "正在执行 jenv \(arguments.joined(separator: " "))..."
        defer { isLoading = false }

        return await executeJenvCommand(arguments: arguments)
    }

    private func executeRawCommand(script: String) async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    DispatchQueue.main.async { self?.isLoading = false }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    DispatchQueue.main.async { self?.isLoading = false }
                    continuation.resume(returning: .failure("命令执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func parseJenvVersions(output: String) -> [JenvJavaVersion] {
        var versions: [JenvJavaVersion] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let isGlobal = trimmed.contains("*")

            // 提取版本字符串，清理标记字符
            var version = trimmed
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !version.isEmpty else { continue }

            versions.append(JenvJavaVersion(
                id: version,
                version: version,
                isGlobal: isGlobal,
                installedPath: nil
            ))
        }

        return versions
    }
}
