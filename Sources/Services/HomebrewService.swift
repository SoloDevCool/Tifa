import Foundation

/// Homebrew 服务 - 执行 brew 命令
@MainActor
class HomebrewService: ObservableObject {
    
    static let shared = HomebrewService()
    
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var lastError: String?
    @Published var updateLog: String = ""
    
    /// 镜像源环境变量（可由设置页动态更新）
    private var mirrorEnvVars: [String: String] = [:]
    
    /// 动态获取 brew 路径
    private var brewPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }
    
    /// 构建 brew 需要的环境变量
    private var brewEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        
        // 关闭自动更新和交互式提示
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_UPGRADE"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["NONINTERACTIVE"] = "1"
        
        // 确保 PATH 包含 brew 的路径
        let extraPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        
        // Homebrew 需要的变量
        env["HOME"] = NSHomeDirectory()
        if env["HOMEBREW_PREFIX"] == nil {
            env["HOMEBREW_PREFIX"] = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        }
        
        // 合并镜像源环境变量（切换后立即生效）
        for (key, value) in mirrorEnvVars {
            env[key] = value
        }
        
        return env
    }
    
    /// 更新镜像源环境变量（切换源后立即生效，无需重启）
    func updateMirrorEnvVars(_ vars: [String: String]) {
        if vars.isEmpty {
            mirrorEnvVars.removeAll()
        } else {
            mirrorEnvVars = vars
        }
    }
    
    // MARK: - 包列表
    
    func fetchInstalledPackages() async -> [BrewPackage] {
        updateLoadingState(message: "正在获取已安装的包...")
        
        let result = await executeBrewCommand(arguments: ["list", "--formula", "--versions"])
        
        isLoading = false
        
        switch result {
        case .success(let output):
            return parseInstalledPackages(output: output)
        case .failure(let error):
            lastError = error
            return []
        }
    }
    
    func fetchOutdatedPackages() async -> [BrewPackage] {
        updateLoadingState(message: "检查过时的包...")
        
        let result = await executeBrewCommand(arguments: ["outdated", "--formula"])
        
        isLoading = false
        
        switch result {
        case .success(let output):
            return parseOutdatedPackages(output: output)
        case .failure(let error):
            lastError = error
            return []
        }
    }
    
    // MARK: - 搜索
    
    func searchPackages(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        
        updateLoadingState(message: "搜索中...")
        
        let result = await executeBrewCommand(arguments: ["search", query])
        
        isLoading = false
        
        switch result {
        case .success(let output):
            return parseSearchResults(output: output, query: query)
        case .failure(let error):
            lastError = error
            return []
        }
    }
    
    func getPackageInfo(name: String) async -> BrewPackage? {
        let result = await executeBrewCommand(arguments: ["info", name])
        
        switch result {
        case .success(let output):
            return parsePackageInfo(output: output, name: name)
        case .failure:
            return nil
        }
    }
    
    // MARK: - 安装/卸载
    
    func installPackage(_ name: String) async -> OperationResult {
        updateLoadingState(message: "正在安装 \(name)...")
        let result = await executeBrewCommandWithProgress(arguments: ["install", name])
        return result
    }
    
    func uninstallPackage(_ name: String) async -> OperationResult {
        updateLoadingState(message: "正在卸载 \(name)...")
        let result = await executeBrewCommandWithProgress(arguments: ["uninstall", "--force", name])
        return result
    }
    
    func upgradePackage(_ name: String) async -> OperationResult {
        updateLoadingState(message: "正在升级 \(name)...")
        let result = await executeBrewCommandWithProgress(arguments: ["upgrade", name])
        return result
    }
    
    func upgradeAllPackages() async -> OperationResult {
        updateLoadingState(message: "正在升级所有包...")
        let result = await executeBrewCommandWithProgress(arguments: ["upgrade"])
        return result
    }
    
    func cleanupPackages() async -> OperationResult {
        updateLoadingState(message: "正在清理旧版本...")
        let result = await executeBrewCommandWithProgress(arguments: ["cleanup", "--prune=all"])
        return result
    }
    
    func updateHomebrew() async -> OperationResult {
        updateLoadingState(message: "正在更新 Homebrew...")
        updateLog = ""
        let result = await executeBrewCommandStreaming(arguments: ["update"])
        return result
    }
    
    // MARK: - 诊断
    
    func checkHomebrewAvailability() -> Bool {
        return FileManager.default.fileExists(atPath: brewPath)
    }
    
    // MARK: - Tap 管理
    
    func fetchTaps() async -> [String] {
        let result = await executeBrewCommand(arguments: ["tap"])
        switch result {
        case .success(let output):
            return output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .failure:
            return []
        }
    }
    
    func addTap(_ tap: String) async -> OperationResult {
        updateLoadingState(message: "正在添加 tap \(tap)...")
        let result = await executeBrewCommandWithProgress(arguments: ["tap", tap])
        return result
    }
    
    func removeTap(_ tap: String) async -> OperationResult {
        updateLoadingState(message: "正在移除 tap \(tap)...")
        let result = await executeBrewCommandWithProgress(arguments: ["untap", tap])
        return result
    }
    
    func getDiagnostics() async -> String {
        let result = await executeBrewCommand(arguments: ["doctor"])
        switch result {
        case .success(let output): return output
        case .failure(let error): return error
        }
    }
    
    // MARK: - 私有方法
    
    func updateLoadingState(message: String) {
        isLoading = true
        loadingMessage = message
    }
    
    func executeBrewCommand(arguments: [String]) async -> OperationResult {
        let path = brewPath
        let env = brewEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: path)
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
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败 (exit code \(process.terminationStatus))" : errorMsg))
                    }
                } catch {
                    continuation.resume(returning: .failure("无法启动 brew: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func executeBrewCommandWithProgress(arguments: [String]) async -> OperationResult {
        let path = brewPath
        let env = brewEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: path)
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
                    
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败 (exit code \(process.terminationStatus))" : errorMsg))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("无法启动 brew: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 流式执行 brew 命令，实时输出日志到 updateLog
    private func executeBrewCommandStreaming(arguments: [String]) async -> OperationResult {
        let path = brewPath
        let env = brewEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                let semaphore = DispatchSemaphore(value: 0)
                
                func appendLog(_ text: String) {
                    let trimmed = text.trimmingCharacters(in: .newlines)
                    guard !trimmed.isEmpty else { return }
                    DispatchQueue.main.async {
                        self?.updateLog += trimmed + "\n"
                    }
                }
                
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        semaphore.signal()
                        return
                    }
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        appendLog(str)
                    }
                }
                
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        semaphore.signal()
                        return
                    }
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        appendLog(str)
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    // 等待 pipe 读完剩余数据
                    let group = DispatchGroup()
                    group.enter()
                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            stdoutPipe.fileHandleForReading.readabilityHandler = nil
                            group.leave()
                            return
                        }
                        if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                            appendLog(str)
                        }
                    }
                    group.enter()
                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            stderrPipe.fileHandleForReading.readabilityHandler = nil
                            group.leave()
                            return
                        }
                        if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                            appendLog(str)
                        }
                    }
                    group.wait()
                    
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    
                    // 读取最终残留数据
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let finalStdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let finalStderr = String(data: stderrData, encoding: .utf8) ?? ""
                    if !finalStdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendLog(finalStdout)
                    }
                    if !finalStderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendLog(finalStderr)
                    }
                    
                    let exitCode = process.terminationStatus
                    DispatchQueue.main.async {
                        self?.updateLog += exitCode == 0 ? "\n✅ 更新完成" : "\n❌ 更新失败 (exit code \(exitCode))"
                    }
                    
                    if exitCode == 0 {
                        continuation.resume(returning: .success(self?.updateLog ?? ""))
                    } else {
                        continuation.resume(returning: .failure(finalStderr.isEmpty ? finalStdout : finalStderr))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        self?.updateLog += "\n❌ 无法启动 brew: \(error.localizedDescription)"
                    }
                    continuation.resume(returning: .failure("无法启动 brew: \(error.localizedDescription)"))
                }
                
                _ = semaphore.wait(timeout: .now() + 1)
            }
        }
    }
    
    // MARK: - 解析方法
    
    private func parseInstalledPackages(output: String) -> [BrewPackage] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return lines.map { line in
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let name = parts.first ?? line
            let versions = parts.dropFirst().joined(separator: " ")
            return BrewPackage(name: name, version: versions)
        }
    }
    
    private func parseOutdatedPackages(output: String) -> [BrewPackage] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return lines.map { line in
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let name = parts.first ?? line
            let currentVersion = parts.count > 1 ? parts[1] : ""
            return BrewPackage(name: name, version: currentVersion)
        }
    }
    
    private func parseSearchResults(output: String, query: String) -> [SearchResult] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return lines.map { line in
            let parts = line.components(separatedBy: "/")
            let tap = parts.count > 1 ? parts[0] : "homebrew"
            let name = parts.count > 1 ? parts[1] : line
            return SearchResult(id: name, name: name, description: "", tap: tap)
        }
    }
    
    private func parsePackageInfo(output: String, name: String) -> BrewPackage? {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var description = ""
        
        // 跳过第一行（包名）和空行，取第二行非空内容作为描述
        for line in lines {
            if line == name || line.isEmpty {
                continue
            }
            if line.contains("==>") {
                break
            }
            description = line
            break
        }
        
        let versionPattern = #"(\d+\.[\d\.]+)"#
        if let regex = try? NSRegularExpression(pattern: versionPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range, in: output) {
            return BrewPackage(name: name, version: String(output[range]), description: description)
        }
        
        return BrewPackage(name: name, version: "", description: description)
    }
}
