import Foundation

/// Rustup 管理的 Rust 工具链版本信息
struct RustupToolchain: Identifiable, Hashable {
    let id: String
    let version: String
    let isDefault: Bool
    let isInstalled: Bool

    init(version: String, isDefault: Bool = false, isInstalled: Bool = true) {
        self.id = version
        self.version = version
        self.isDefault = isDefault
        self.isInstalled = isInstalled
    }
}

/// Rustup 服务 - 执行 rustup 命令和管理环境变量配置
@MainActor
class RustupService: ObservableObject {

    static let shared = RustupService()

    @Published var isLoading = false
    @Published var loadingMessage = ""

    /// 当前正在执行的安装进程（用于取消）
    private var currentInstallProcess: Process?

    /// 取消当前安装进程
    func cancelCurrentInstall() {
        currentInstallProcess?.terminate()
        currentInstallProcess = nil
    }

    /// brew 绝对路径（GUI 应用 PATH 中缺少 /opt/homebrew/bin）
    private var brewPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }

    /// Rustup 安装目录
    private var rustupHome: String {
        "\(NSHomeDirectory())/.rustup"
    }

    /// Cargo 安装目录
    private var cargoHome: String {
        "\(NSHomeDirectory())/.cargo"
    }

    /// 构建 rustup 需要的环境变量
    private var rustupEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()

        // rustup / cargo 需要的 PATH
        let rustupPaths = "\(home)/.cargo/bin"
        let extraPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "\(rustupPaths):\(extraPaths):\(currentPath)"

        env["HOME"] = home
        env["RUSTUP_HOME"] = rustupHome
        env["CARGO_HOME"] = cargoHome

        return env
    }

    // MARK: - 可用性检查

    /// 检查 rustup 是否已安装
    func checkRustupAvailability() -> Bool {
        let home = NSHomeDirectory()
        let rustupDir = "\(home)/.rustup"
        if FileManager.default.fileExists(atPath: rustupDir) {
            return true
        }
        let cargoBin = "\(home)/.cargo/bin/rustup"
        return FileManager.default.fileExists(atPath: cargoBin)
    }

    /// 获取 rustup 安装路径
    func getRustupPath() -> String {
        let home = NSHomeDirectory()
        let rustupDir = "\(home)/.rustup"
        if FileManager.default.fileExists(atPath: rustupDir) {
            return rustupDir
        }
        let cargoBin = "\(home)/.cargo/bin/rustup"
        if FileManager.default.fileExists(atPath: cargoBin) {
            return "\(home)/.cargo"
        }
        return "未知"
    }

    // MARK: - 安装/卸载

    /// 安装 rustup（通过官方脚本）
    func installRustup(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let tmpScript = NSTemporaryDirectory() + "rustup_installer.sh"

        // 第一步：下载安装脚本
        Task { @MainActor in onOutput("正在下载 rustup 安装脚本...\n") }

        let downloadResult = await withCheckedContinuation { (continuation: CheckedContinuation<OperationResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = ["--proto", "=https", "--tlsv1.2", "-sSf", "-o", tmpScript, "https://sh.rustup.rs"]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(""))
                    } else {
                        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        continuation.resume(returning: .failure("下载安装脚本失败: \(output)"))
                    }
                } catch {
                    continuation.resume(returning: .failure("下载安装脚本失败: \(error.localizedDescription)"))
                }
            }
        }

        if case .failure(let error) = downloadResult {
            return .failure(error)
        }

        // 第二步：执行安装脚本
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [tmpScript, "-y"]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        Task { @MainActor in onOutput(str) }
                    }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        Task { @MainActor in onOutput(str) }
                    }
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

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    // 清理临时文件
                    try? FileManager.default.removeItem(atPath: tmpScript)

                    let remainingStdout = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if timedOut {
                        continuation.resume(returning: .failure("安装超时（10 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("rustup 安装成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "安装失败 (exit code \(process.terminationStatus))" : remainingStderr
                        continuation.resume(returning: .failure(errorMsg))
                    }
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    try? FileManager.default.removeItem(atPath: tmpScript)
                    continuation.resume(returning: .failure("无法执行安装命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 卸载 rustup
    func uninstallRustup() async -> OperationResult {
        // 先清理环境变量配置
        _ = await removeRustupEnvConfig()

        isLoading = true
        loadingMessage = "正在卸载 rustup..."

        let home = NSHomeDirectory()
        let env = rustupEnvironment
        let script = "rustup self uninstall -y && rm -rf \(home)/.rustup \(home)/.cargo"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + 120)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "卸载失败" : errorMsg))
                    }
                } catch {
                    timer.cancel()
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("卸载失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - 环境变量自动配置

    /// 检查 rustup 环境变量是否已配置
    func isRustupEnvConfigured() -> Bool {
        let home = NSHomeDirectory()

        let files = [".zshrc", ".zshenv", ".zprofile", ".bash_profile", ".bashrc"]
        for fileName in files {
            let path = "\(home)/\(fileName)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            if content.contains(".cargo/bin") || content.contains("RUSTUP_HOME") || content.contains("CARGO_HOME") {
                return true
            }
        }
        return false
    }

    /// 获取检测到的配置文件列表
    func getConfiguredFiles() -> [(file: String, hasConfig: Bool)] {
        let files = [".zshrc", ".zshenv", ".zprofile", ".bash_profile", ".bashrc"]
        let home = NSHomeDirectory()

        return files.compactMap { fileName in
            let path = "\(home)/\(fileName)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return (file: fileName, hasConfig: false)
            }
            let hasConfig = content.contains(".cargo/bin") || content.contains("RUSTUP_HOME") || content.contains("CARGO_HOME")
            return (file: fileName, hasConfig: hasConfig)
        }
    }

    /// 自动配置 rustup 环境变量到指定 Shell 配置文件
    func configureRustupEnv(to fileName: String = ".zshrc") async -> OperationResult {
        let home = NSHomeDirectory()
        let path = "\(home)/\(fileName)"

        let configBlock = """

        # rustup configuration added by Tifa
        export RUSTUP_HOME="$HOME/.rustup"
        export CARGO_HOME="$HOME/.cargo"
        export PATH="$HOME/.cargo/bin:$PATH"

        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var content = ""
                if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
                    content = existing

                    if content.contains(".cargo/bin") || content.contains("RUSTUP_HOME") {
                        DispatchQueue.main.async {
                            continuation.resume(returning: .success("\(fileName) 中已存在 rustup 配置，无需重复添加。"))
                        }
                        return
                    }
                }

                if !content.isEmpty && !content.hasSuffix("\n") {
                    content += "\n"
                }
                content += configBlock

                do {
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    continuation.resume(returning: .success("已将 rustup 环境变量配置写入 \(fileName)。请重新打开终端使配置生效。"))
                } catch {
                    continuation.resume(returning: .failure("写入失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 移除 rustup 环境变量配置
    func removeRustupEnvConfig(from fileName: String = ".zshrc") async -> OperationResult {
        let home = NSHomeDirectory()
        let path = "\(home)/\(fileName)"

        guard let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty else {
            return .success("\(fileName) 为空或不存在，无需清理。")
        }

        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var removed = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if (trimmed.contains("# rustup configuration") && trimmed.contains("Tifa")) ||
               trimmed.contains("RUSTUP_HOME") ||
               trimmed.contains("CARGO_HOME") ||
               trimmed.contains(".cargo/bin") && trimmed.contains("export") {
                removed = true
                continue
            }

            newLines.append(line)
        }

        if !removed {
            return .success("\(fileName) 中未找到 rustup 配置。")
        }

        // 清理连续空行
        var cleanedLines: [String] = []
        var lastWasEmpty = true
        for line in newLines {
            let isEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isEmpty && lastWasEmpty {
                continue
            }
            cleanedLines.append(line)
            lastWasEmpty = isEmpty
        }

        let newContent = cleanedLines.joined(separator: "\n")

        do {
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            if removed {
                return .success("已从 \(fileName) 中移除 rustup 环境变量配置。")
            } else {
                return .success("\(fileName) 中未找到 rustup 配置。")
            }
        } catch {
            return .failure("清理失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Rust 工具链版本管理

    /// 获取已安装的工具链列表
    func listInstalledVersions() async -> [RustupToolchain] {
        let result = await executeCommand(arguments: ["toolchain", "list"])
        switch result {
        case .success(let output):
            return parseToolchainList(output: output)
        case .failure:
            return []
        }
    }

    /// 获取默认工具链
    func getDefaultVersion() async -> String {
        let result = await executeCommand(arguments: ["show", "active-toolchain"])
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "未设置" : trimmed
        case .failure:
            return "未设置"
        }
    }

    /// 设置默认工具链
    func setDefaultVersion(_ version: String) async -> OperationResult {
        return await executeCommandWithProgress(arguments: ["default", version])
    }

    /// 获取当前激活的工具链
    func getCurrentVersion() async -> String {
        let result = await executeCommand(arguments: ["show", "active-toolchain"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }

    /// 获取可用安装的工具链列表
    func listAvailableVersions() async -> [String] {
        let result = await executeCommand(arguments: ["toolchain", "list"])
        switch result {
        case .success(let output):
            return parseAvailableToolchains(output: output)
        case .failure:
            return []
        }
    }

    /// 安装工具链版本
    func installVersion(_ version: String) async -> OperationResult {
        return await executeCommand(arguments: ["toolchain", "install", version])
    }

    /// 安装工具链版本（带实时输出）
    func installVersionWithOutput(_ version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let env = rustupEnvironment
        let script = "source \"$HOME/.cargo/env\" && rustup toolchain install \(version)"

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

                Task { @MainActor in
                    self.currentInstallProcess = process
                }

                let stdoutHandle = stdoutPipe.fileHandleForReading
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        Task { @MainActor in onOutput(line) }
                    }
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        Task { @MainActor in onOutput(line) }
                    }
                }

                // 超时处理
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + 1200)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    Task { @MainActor in
                        self.currentInstallProcess = nil
                    }

                    // 清理 readabilityHandler
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    // 读取剩余数据
                    let remainingStdout = stdoutHandle.readDataToEndOfFile()
                    if !remainingStdout.isEmpty, let line = String(data: remainingStdout, encoding: .utf8) {
                        Task { @MainActor in onOutput(line) }
                    }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Rust \(version) 安装成功"))
                    } else {
                        continuation.resume(returning: .failure("Rust \(version) 安装失败（退出码: \(process.terminationStatus)）"))
                    }
                } catch {
                    timer.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 卸载工具链版本
    func uninstallVersion(_ version: String) async -> OperationResult {
        return await executeCommandWithProgress(arguments: ["toolchain", "uninstall", version])
    }

    /// 获取 rustup 版本
    func getRustupVersion() async -> String {
        let result = await executeCommand(arguments: ["--version"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }

    /// 更新 rustup
    func updateRustup() async -> OperationResult {
        isLoading = true
        loadingMessage = "正在更新 rustup..."

        let env = rustupEnvironment
        let script = "source \"$HOME/.cargo/env\" && rustup self update"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + 300)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "更新失败" : errorMsg))
                    }
                } catch {
                    timer.cancel()
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("更新失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 获取已安装版本占用的磁盘空间
    func getVersionsDiskUsage() async -> String {
        let rustupDir = rustupHome
        guard FileManager.default.fileExists(atPath: rustupDir) else { return "0 B" }

        let env = rustupEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                process.arguments = ["-sh", rustupDir]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: stdoutData, encoding: .utf8) ?? ""
                    let parts = output.components(separatedBy: .whitespaces)
                    continuation.resume(returning: parts.first ?? "未知")
                } catch {
                    continuation.resume(returning: "未知")
                }
            }
        }
    }

    // MARK: - 私有方法

    /// 解析已安装工具链列表
    private func parseToolchainList(output: String) -> [RustupToolchain] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 同时获取默认版本
        // 格式: stable-aarch64-apple-darwin (default), nightly-aarch64-apple-darwin, 1.75.0-aarch64-apple-darwin
        return lines.compactMap { line -> RustupToolchain? in
            let isDefault = line.contains("(default)")
            let cleanVersion = line
                .replacingOccurrences(of: "(default)", with: "")
                .replacingOccurrences(of: "(override)", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanVersion.isEmpty else { return nil }

            return RustupToolchain(
                version: cleanVersion,
                isDefault: isDefault,
                isInstalled: true
            )
        }
    }

    /// 解析可用工具链列表
    private func parseAvailableToolchains(output: String) -> [String] {
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 执行 rustup 命令
    func executeCommand(arguments: [String]) async -> OperationResult {
        let env = rustupEnvironment
        let shell = "/bin/bash"
        let script = "source \"$HOME/.cargo/env\" && rustup \(arguments.joined(separator: " "))"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: shell)
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
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 执行带进度的 rustup 命令
    private func executeCommandWithProgress(arguments: [String], message: String? = nil, timeout: TimeInterval = 300) async -> OperationResult {
        isLoading = true
        loadingMessage = message ?? "正在执行 rustup \(arguments.joined(separator: " "))..."

        let env = rustupEnvironment
        let shell = "/bin/bash"
        let script = "source \"$HOME/.cargo/env\" && rustup \(arguments.joined(separator: " "))"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-l", "-c", script]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    timer.cancel()
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }
}
