import Foundation

/// NVM 管理的 Node.js 版本信息
struct NvmNodeVersion: Identifiable, Hashable {
    let id: String
    let version: String       // 如 "v20.11.0"
    let isDefault: Bool       // 是否为默认版本
    let isInstalled: Bool     // 是否已本地安装
    let installPath: String?  // 安装路径
}

/// NVM 服务 - 管理 NVM 和 Node.js 版本
@MainActor
class NvmService: ObservableObject {
    
    static let shared = NvmService()
    
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var lastError: String?

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
    
    /// NVM 安装目录（Homebrew 安装的 nvm）
    private var nvmDir: String {
        "\(NSHomeDirectory())/Library/Application Support/nvm"
    }
    
    /// NVM 可执行脚本路径
    private var nvmScriptPath: String {
        "\(brewPrefix)/opt/nvm/nvm.sh"
    }
    
    /// Node 可执行文件路径模板
    private func nodePath(for version: String) -> String {
        "\(nvmDir)/versions/node/\(version)/bin/node"
    }
    
    /// npm 可执行文件路径模板
    private func npmPath(for version: String) -> String {
        "\(nvmDir)/versions/node/\(version)/bin/npm"
    }
    
    /// 构建 NVM 命令执行环境
    private var nvmEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        env["NVM_DIR"] = nvmDir
        
        // 确保 nvm 的 node 版本路径在 PATH 中
        let nvmPath = "\(nvmDir)/versions/node"
        let extraPaths = "\(brewPrefix)/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = env["PATH"] {
            // 把 nvm node 路径加到前面
            env["PATH"] = "\(nvmPath):\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = "\(nvmPath):\(extraPaths)"
        }
        return env
    }
    
    // MARK: - 安装
    
    /// 使用 Homebrew 安装 NVM（带实时输出）
    func installNvm(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "\(brewPath) install nvm"
        
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
                    timer.schedule(deadline: .now() + 600)
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
                        continuation.resume(returning: .failure("安装超时（10 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("安装成功"))
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
    
    // MARK: - 检查可用性
    
    /// 检查 NVM 是否已安装
    func checkNvmAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: nvmScriptPath)
    }
    
    /// 获取 NVM 版本
    func getNvmVersion() async -> String {
        let result = await executeNvmCommand(arguments: ["--version"])
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    /// 检查 NVM 环境是否已配置（shell 配置文件中是否有 nvm 初始化）
    func isNvmConfigured() async -> Bool {
        // 检查常见 shell 配置文件
        let configFiles = [".zshrc", ".bash_profile", ".bashrc", ".profile"]
        let home = NSHomeDirectory()
        
        for file in configFiles {
            let path = "\(home)/\(file)"
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                if content.contains("nvm") || content.contains("NVM_DIR") {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Node.js 版本管理
    
    /// 获取已安装的 Node.js 版本列表
    func listInstalledVersions() async -> [NvmNodeVersion] {
        let result = await executeNvmCommand(arguments: ["ls"])
        guard case .success(let output) = result else { return [] }
        
        return parseNvmList(output: output)
    }
    
    /// 获取远程可用的 Node.js 版本列表（LTS）
    func listRemoteVersions() async -> [String] {
        let result = await executeNvmCommand(arguments: ["ls-remote", "--lts"])
        guard case .success(let output) = result else { return [] }
        
        let versions = output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("v") }
            .compactMap { line -> String? in
                // 行格式: "v20.11.0 (LTS: Iron)" 或 "       v20.11.0"
                // 提取版本号
                let components = line.components(separatedBy: .whitespaces)
                for comp in components {
                    if comp.hasPrefix("v") && comp.dropFirst().allSatisfy({ $0.isNumber || $0 == "." }) {
                        return comp
                    }
                }
                // 可能整行就是版本号
                if line.hasPrefix("v") && line.count <= 15 {
                    return line
                }
                return nil
            }
        
        return Array(Set(versions)).sorted().reversed()
    }
    
    /// 安装指定版本的 Node.js（带实时输出）
    func installNodeVersion(version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let env = nvmEnvironment
        let script = "export NVM_DIR=\"\(nvmDir)\"; [ -s \"\(nvmScriptPath)\" ] && \\. \"\(nvmScriptPath)\"; nvm install \(version)"
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.environment = env
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
                    timer.schedule(deadline: .now() + 1200)
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
                        continuation.resume(returning: .failure("安装超时（20 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Node.js \(version) 安装成功"))
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
    
    /// 卸载指定版本的 Node.js
    func uninstallNodeVersion(version: String) async -> OperationResult {
        let result = await executeNvmCommand(arguments: ["uninstall", version])
        return result
    }
    
    /// 设置默认 Node.js 版本
    func setDefaultVersion(version: String) async -> OperationResult {
        let result = await executeNvmCommand(arguments: ["alias", "default", version])
        return result
    }
    
    /// 使用指定版本（仅当前 shell 会话有效，GUI 中主要用于确认操作）
    func useVersion(version: String) async -> OperationResult {
        let result = await executeNvmCommand(arguments: ["use", version])
        return result
    }
    
    /// 获取当前默认版本
    func getDefaultVersion() async -> String {
        let result = await executeNvmCommand(arguments: ["current"])
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "无"
    }
    
    /// 获取 Node.js 版本信息
    func getNodeVersion(for version: String) async -> String {
        let nodePath = nodePath(for: version)
        guard FileManager.default.fileExists(atPath: nodePath) else { return "未安装" }
        
        let result = await executeCommand(executable: nodePath, arguments: ["--version"])
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    /// 获取 npm 版本信息
    func getNpmVersion(for version: String) async -> String {
        let npm = npmPath(for: version)
        guard FileManager.default.fileExists(atPath: npm) else { return "未安装" }
        
        let result = await executeCommand(executable: npm, arguments: ["--version"])
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    /// 获取全局 npm 包列表
    func getGlobalPackages(for version: String) async -> String {
        let npm = npmPath(for: version)
        guard FileManager.default.fileExists(atPath: npm) else { return "Node.js \(version) 未安装" }
        
        let versionBinDir = "\(nvmDir)/versions/node/\(version)/bin"
        var env = nvmEnvironment
        env["PATH"] = "\(versionBinDir):\(env["PATH"] ?? "")"
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: npm)
                process.arguments = ["list", "-g", "--depth=0"]
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
                        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: trimmed.isEmpty ? "无全局包" : trimmed)
                    } else {
                        continuation.resume(returning: "执行失败: \(stderr.isEmpty ? stdout : stderr)")
                    }
                } catch {
                    continuation.resume(returning: "无法执行: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 获取已安装版本占用的磁盘空间
    func getVersionsDiskUsage() async -> String {
        let nvmVersionsDir = "\(nvmDir)/versions/node"
        guard FileManager.default.fileExists(atPath: nvmVersionsDir) else { return "0 B" }
        
        let result = await executeCommand(executable: "/usr/bin/du", arguments: ["-sh", nvmVersionsDir])
        if case .success(let output) = result {
            let parts = output.components(separatedBy: .whitespaces)
            return parts.first ?? "未知"
        }
        return "未知"
    }
    
    // MARK: - 私有方法
    
    private func updateLoadingState(message: String) {
        isLoading = true
        loadingMessage = message
    }
    
    /// 执行 nvm 命令（通过 bash 加载 nvm.sh）
    private func executeNvmCommand(arguments: [String]) async -> OperationResult {
        let env = nvmEnvironment
        let argsStr = arguments.joined(separator: " ")
        let script = "export NVM_DIR=\"\(nvmDir)\"; [ -s \"\(nvmScriptPath)\" ] && \\. \"\(nvmScriptPath)\"; nvm \(argsStr)"
        
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
    
    /// 执行通用命令
    private func executeCommand(executable: String, arguments: [String]) async -> OperationResult {
        let env = nvmEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
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
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func executeCommandWithProgress(executable: String, arguments: [String]) async -> OperationResult {
        updateLoadingState(message: "正在执行...")
        let env = nvmEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = env
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    DispatchQueue.main.async { self?.isLoading = false }
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(output))
                    } else {
                        continuation.resume(returning: .failure(output.isEmpty ? "命令执行失败" : output))
                    }
                } catch {
                    DispatchQueue.main.async { self?.isLoading = false }
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
    }
    
    /// 解析 nvm ls 输出
    private func parseNvmList(output: String) -> [NvmNodeVersion] {
        var versions: [NvmNodeVersion] = []
        let lines = output.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("v") else { continue }
            
            let isDefault = trimmed.contains("->") || trimmed.contains("*")
            let isSystem = trimmed.contains("system")
            if isSystem { continue }
            
            // 提取版本号，清理标记字符
            var version = trimmed
                .replacingOccurrences(of: "->", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "(default)", with: "")
                .replacingOccurrences(of: "(latest)", with: "")
                .replacingOccurrences(of: "(lts/*)", with: "")
                .replacingOccurrences(of: "N/A", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            // 如果行中有多个空格分隔的内容，取第一个（版本号）
            let components = version.components(separatedBy: .whitespaces)
            if let v = components.first, v.hasPrefix("v") {
                version = v
            }
            
            guard !version.isEmpty else { continue }
            
            let installPath = "\(nvmDir)/versions/node/\(version)"
            let isInstalled = FileManager.default.fileExists(atPath: installPath)
            
            versions.append(NvmNodeVersion(
                id: version,
                version: version,
                isDefault: isDefault && isInstalled,
                isInstalled: isInstalled,
                installPath: isInstalled ? installPath : nil
            ))
        }
        
        return versions
    }
}
