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

        // Homebrew 安装的 JDK
        let homebrewJdkPaths = [
            "\(brewPrefix)/opt/openjdk",
            "\(brewPrefix)/opt/openjdk@11",
            "\(brewPrefix)/opt/openjdk@17",
            "\(brewPrefix)/opt/openjdk@21",
            "\(brewPrefix)/opt/openjdk@22",
            "\(brewPrefix)/opt/openjdk@23",
            "\(brewPrefix)/Cellar/openjdk"
        ]

        // 遍历 Homebrew Cellar 下的 JDK
        let cellarPath = "\(brewPrefix)/Cellar"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: cellarPath) {
            for item in contents where item.hasPrefix("openjdk") {
                let jdkDir = "\(cellarPath)/\(item)"
                if let versions = try? FileManager.default.contentsOfDirectory(atPath: jdkDir) {
                    for ver in versions.sorted().reversed() {
                        let libexecPath = "\(jdkDir)/\(ver)/libexec/openjdk.jdk/Contents/Home"
                        let normalPath = "\(jdkDir)/\(ver)/libexec"
                        if FileManager.default.fileExists(atPath: libexecPath) {
                            jdks.append((name: "openjdk \(ver)", path: libexecPath))
                        } else if FileManager.default.fileExists(atPath: "\(normalPath)/bin/java") {
                            jdks.append((name: "openjdk \(ver)", path: normalPath))
                        }
                    }
                }
            }
        }

        // 检查固定路径的 Homebrew JDK
        for path in homebrewJdkPaths {
            let javaHomePath = path.contains("Cellar") ? path : "\(path)/libexec/openjdk.jdk/Contents/Home"
            if !javaHomePath.contains("Cellar") {
                // 非 cellar 路径
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
        }

        // /Library/Java/JavaVirtualMachines 下的 JDK
        let jvmPath = "/Library/Java/JavaVirtualMachines"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: jvmPath) {
            for item in contents where item.hasSuffix(".jdk") {
                let homePath = "\(jvmPath)/\(item)/Contents/Home"
                if FileManager.default.fileExists(atPath: homePath) {
                    let name = item.replacingOccurrences(of: ".jdk", with: "")
                    jdks.append((name: name, path: homePath))
                }
            }
        }

        // ~/Library/Java/JavaVirtualMachines 下的 JDK
        let userJvmPath = "\(NSHomeDirectory())/Library/Java/JavaVirtualMachines"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: userJvmPath) {
            for item in contents where item.hasSuffix(".jdk") {
                let homePath = "\(userJvmPath)/\(item)/Contents/Home"
                if FileManager.default.fileExists(atPath: homePath) {
                    let name = item.replacingOccurrences(of: ".jdk", with: "")
                    jdks.append((name: name, path: homePath))
                }
            }
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
