import Foundation

/// pyenv 服务 - 执行 pyenv 命令和管理环境变量配置
@MainActor
class PyenvService: ObservableObject {
    
    static let shared = PyenvService()
    
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
    
    /// 构建 pyenv 需要的环境变量
    private var pyenvEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        
        // pyenv 需要的 PATH
        let pyenvPaths = "\(home)/.pyenv/shims:\(home)/.pyenv/bin"
        let extraPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "\(pyenvPaths):\(extraPaths):\(currentPath)"
        
        env["HOME"] = home
        env["PYENV_ROOT"] = "\(home)/.pyenv"
        
        return env
    }
    
    // MARK: - 可用性检查
    
    /// 检查 pyenv 是否已安装
    func checkPyenvAvailability() -> Bool {
        // 优先检查 .pyenv 目录
        let home = NSHomeDirectory()
        let pyenvDir = "\(home)/.pyenv"
        if FileManager.default.fileExists(atPath: pyenvDir) {
            return true
        }
        // 检查 Homebrew 是否安装了 pyenv
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew" : "/usr/local"
        let pyenvBin = "\(brewPrefix)/bin/pyenv"
        return FileManager.default.fileExists(atPath: pyenvBin)
    }
    
    /// 获取 pyenv 安装路径
    func getPyenvPath() -> String {
        let home = NSHomeDirectory()
        let pyenvDir = "\(home)/.pyenv"
        if FileManager.default.fileExists(atPath: pyenvDir) {
            return pyenvDir
        }
        // 通过 brew 路径返回
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew" : "/usr/local"
        let pyenvBin = "\(brewPrefix)/bin/pyenv"
        if FileManager.default.fileExists(atPath: pyenvBin) {
            return pyenvBin
        }
        return "未知"
    }
    
    // MARK: - 通过 Homebrew 安装/卸载
    
    /// 使用 Homebrew 安装 pyenv
    func installPyenv() async -> OperationResult {
        isLoading = true
        loadingMessage = "正在通过 Homebrew 安装 pyenv..."
        
        let script = "\(brewPath) install pyenv"
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                // 超时处理（安装可能较慢）
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + 300)
                timer.setEventHandler {
                    process.terminate()
                }
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
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "安装失败" : errorMsg))
                    }
                } catch {
                    timer.cancel()
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("安装失败: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 使用 Homebrew 卸载 pyenv
    func uninstallPyenv() async -> OperationResult {
        // 先清理环境变量配置
        _ = await removePyenvEnvConfig()
        
        // 通过 brew 卸载
        isLoading = true
        loadingMessage = "正在通过 Homebrew 卸载 pyenv..."
        
        let home = NSHomeDirectory()
        let script = "\(brewPath) uninstall pyenv && rm -rf \(home)/.pyenv"
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + 120)
                timer.setEventHandler {
                    process.terminate()
                }
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
    
    /// 检查 pyenv 环境变量是否已配置
    func isPyenvEnvConfigured() -> Bool {
        let home = NSHomeDirectory()
        
        // 检查 .zshrc 是否包含 pyenv 配置
        let zshrcPath = "\(home)/.zshrc"
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else {
            return false
        }
        
        return content.contains("PYENV_ROOT") || content.contains("pyenv init")
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
            let hasConfig = content.contains("PYENV_ROOT") || content.contains("pyenv init")
            return (file: fileName, hasConfig: hasConfig)
        }
    }
    
    /// 自动配置 pyenv 环境变量到指定 Shell 配置文件
    func configurePyenvEnv(to fileName: String = ".zshrc") async -> OperationResult {
        let home = NSHomeDirectory()
        let path = "\(home)/\(fileName)"
        
        // pyenv 配置片段
        let configBlock = """
        
        # pyenv configuration added by Tifa
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        eval "$(pyenv init -)"
        
        """
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // 读取现有内容
                var content = ""
                if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
                    content = existing
                    
                    // 检查是否已存在配置
                    if content.contains("PYENV_ROOT") && content.contains("pyenv init") {
                        DispatchQueue.main.async {
                            continuation.resume(returning: .success("\(fileName) 中已存在 pyenv 配置，无需重复添加。"))
                        }
                        return
                    }
                }
                
                // 追加配置
                if !content.isEmpty && !content.hasSuffix("\n") {
                    content += "\n"
                }
                content += configBlock
                
                do {
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    continuation.resume(returning: .success("已将 pyenv 环境变量配置写入 \(fileName)。请重新打开终端使配置生效。"))
                } catch {
                    continuation.resume(returning: .failure("写入失败: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 移除 pyenv 环境变量配置
    func removePyenvEnvConfig(from fileName: String = ".zshrc") async -> OperationResult {
        let home = NSHomeDirectory()
        let path = "\(home)/\(fileName)"
        
        guard let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty else {
            return .success("\(fileName) 为空或不存在，无需清理。")
        }
        
        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var inPyenvBlock = false
        var removed = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 检测 pyenv 配置块开始
            if trimmed.contains("# pyenv configuration") || trimmed.contains("Added by Tifa") && trimmed.contains("pyenv") {
                inPyenvBlock = true
                removed = true
                continue
            }
            
            // 检测 pyenv 相关配置行
            if trimmed.contains("PYENV_ROOT") || trimmed.contains("pyenv init") || trimmed.contains("pyenv shims") {
                removed = true
                continue
            }
            
            // 如果不在 pyenv 配置块中，保留该行
            if !inPyenvBlock || !trimmed.isEmpty {
                newLines.append(line)
            }
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
                return .success("已从 \(fileName) 中移除 pyenv 环境变量配置。")
            } else {
                return .success("\(fileName) 中未找到 pyenv 配置。")
            }
        } catch {
            return .failure("清理失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Python 安装源管理
    
    /// 获取当前 Python 安装源（PYENV_BUILD_MIRROR_URL）
    func getPythonMirrorSource() async -> String {
        let home = NSHomeDirectory()
        
        // 检查各 Shell 配置文件
        let files = [".zshrc", ".zshenv", ".zprofile", ".bash_profile", ".bashrc"]
        for fileName in files {
            let path = "\(home)/\(fileName)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("PYENV_BUILD_MIRROR_URL") {
                    // 解析 export PYENV_BUILD_MIRROR_URL="xxx"
                    let pattern = #"PYENV_BUILD_MIRROR_URL\s*=\s*["']?(.+?)["']?$"#
                    guard let regex = try? NSRegularExpression(pattern: pattern),
                          let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                          let range = Range(match.range(at: 1), in: trimmed) else { continue }
                    return String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return ""
    }
    
    /// 设置 Python 安装源
    func setPythonMirrorSource(_ url: String, to fileName: String = ".zshrc") async -> OperationResult {
        let home = NSHomeDirectory()
        let path = "\(home)/\(fileName)"
        
        let exportLine = "export PYENV_BUILD_MIRROR_URL=\"\(url)\""
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var content = ""
                if let existing = try? String(contentsOfFile: path, encoding: .utf8) {
                    content = existing
                }
                
                let lines = content.components(separatedBy: .newlines)
                var newLines: [String] = []
                var found = false
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("PYENV_BUILD_MIRROR_URL") {
                        newLines.append(exportLine)
                        found = true
                    } else {
                        newLines.append(line)
                    }
                }
                
                if !found {
                    if !content.isEmpty && !content.hasSuffix("\n") {
                        newLines.append("")
                    }
                    newLines.append("")
                    newLines.append("# Python mirror for pyenv - Added by Tifa")
                    newLines.append(exportLine)
                }
                
                let newContent = newLines.joined(separator: "\n")
                
                do {
                    try newContent.write(toFile: path, atomically: true, encoding: .utf8)
                    continuation.resume(returning: .success("已将 Python 安装源设置为 \(url)\n\n写入文件: \(fileName)\n\n请重启终端使配置生效。"))
                } catch {
                    continuation.resume(returning: .failure("写入失败: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 移除 Python 安装源配置
    func removePythonMirrorSource(from fileName: String = ".zshrc") async -> OperationResult {
        let home = NSHomeDirectory()
        let path = "\(home)/\(fileName)"
        
        guard let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty else {
            return .success("文件为空或不存在。")
        }
        
        let lines = content.components(separatedBy: .newlines)
        var newLines: [String] = []
        var removed = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("PYENV_BUILD_MIRROR_URL") || (trimmed.contains("Python mirror for pyenv") && trimmed.contains("Tifa")) {
                removed = true
            } else {
                newLines.append(line)
            }
        }
        
        if !removed {
            return .success("未找到 Python 安装源配置。")
        }
        
        let newContent = newLines.joined(separator: "\n")
        
        do {
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("已从 \(fileName) 中移除 Python 安装源配置。")
        } catch {
            return .failure("移除失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Python 版本管理
    
    /// 获取已安装的 Python 版本列表
    func listInstalledVersions() async -> [PyenvVersion] {
        let result = await executeCommand(arguments: ["versions"])
        switch result {
        case .success(let output):
            return parseVersionList(output: output)
        case .failure:
            return []
        }
    }
    
    /// 获取当前全局 Python 版本
    func getGlobalVersion() async -> String {
        let result = await executeCommand(arguments: ["global"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未设置"
        }
    }
    
    /// 设置全局 Python 版本
    func setGlobalVersion(_ version: String) async -> OperationResult {
        return await executeCommand(arguments: ["global", version])
    }
    
    /// 获取当前目录本地版本
    func getLocalVersion() async -> String {
        let result = await executeCommand(arguments: ["local"])
        switch result {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "跟随全局" : trimmed
        case .failure:
            return "跟随全局"
        }
    }
    
    /// 设置本地版本
    func setLocalVersion(_ version: String) async -> OperationResult {
        return await executeCommand(arguments: ["local", version])
    }
    
    /// 获取当前激活的 Python 版本
    func getCurrentVersion() async -> String {
        let result = await executeCommand(arguments: ["version"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }
    
    /// 获取可用安装的 Python 版本列表
    func listAvailableVersions() async -> [String] {
        let result = await executeCommand(arguments: ["install", "--list"])
        switch result {
        case .success(let output):
            return parseAvailableVersions(output: output)
        case .failure:
            return []
        }
    }
    
    /// 安装 Python 版本
    func installVersion(_ version: String) async -> OperationResult {
        return await executeCommand(arguments: ["install", version])
    }
    
    /// 卸载 Python 版本
    func uninstallVersion(_ version: String) async -> OperationResult {
        return await executeCommand(arguments: ["uninstall", "-f", version])
    }
    
    /// 获取 pyenv 版本
    func getPyenvVersion() async -> String {
        let result = await executeCommand(arguments: ["--version"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }
    
    /// 更新 pyenv
    func updatePyenv() async -> OperationResult {
        isLoading = true
        loadingMessage = "正在更新 pyenv..."
        
        let script = "\(brewPath) upgrade pyenv"
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
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
    
    /// 检查是否有可更新的已安装版本
    func checkUpdates() async -> [String] {
        let result = await executeCommand(arguments: ["install", "--list"])
        guard case .success(let availableOutput) = result else { return [] }
        
        let installedResult = await listInstalledVersions()
        let installedVersions = Set(installedResult.map { $0.version })
        
        let availableVersions = parseAvailableVersions(output: availableOutput)
        
        // 找出已安装版本的补丁更新
        return availableVersions.filter { avail in
            installedVersions.contains { installed in
                // 匹配主版本号相同但补丁版本不同
                let availParts = avail.split(separator: ".")
                let installedParts = installed.split(separator: ".")
                guard availParts.count >= 2, installedParts.count >= 2 else { return false }
                return availParts[0] == installedParts[0] && availParts[1] == installedParts[1]
            }
        }
    }
    
    /// 安装 Python 版本（带实时输出回调）
    func installVersionWithOutput(_ version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let shell = "/bin/bash"
        let script = """
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        pyenv install \(version)
        """

        let env = pyenvEnvironment
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

                Task { @MainActor in
                    self.currentInstallProcess = process
                }

                // 实时读取 stdout
                let stdoutHandle = stdoutPipe.fileHandleForReading
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        Task { @MainActor in
                            onOutput(line)
                        }
                    }
                }

                // 实时读取 stderr
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        Task { @MainActor in
                            onOutput(line)
                        }
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
                        Task { @MainActor in
                            onOutput(line)
                        }
                    }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Python \(version) 安装成功"))
                    } else {
                        continuation.resume(returning: .failure("Python \(version) 安装失败（退出码: \(process.terminationStatus)）"))
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

    // MARK: - 私有方法
    
    /// 解析已安装版本列表
    private func parseVersionList(output: String) -> [PyenvVersion] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // 获取全局版本用于标记
        // 直接从输出中解析
        return lines.compactMap { line -> PyenvVersion? in
            let isGlobal = line.hasPrefix("*")
            let cleanVersion = line
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            guard !cleanVersion.isEmpty else { return nil }
            
            return PyenvVersion(
                version: cleanVersion,
                isGlobal: isGlobal
            )
        }
    }
    
    /// 解析可用版本列表（简化显示）
    private func parseAvailableVersions(output: String) -> [String] {
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                // 只保留稳定版本（纯数字开头，如 3.12.0）
                let pattern = #"^\d+\.\d+\.\d+$"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
                let range = NSRange(line.startIndex..., in: line)
                return regex.firstMatch(in: line, range: range) != nil
            }
    }
    
    /// 执行 pyenv 命令
    func executeCommand(arguments: [String]) async -> OperationResult {
        _ = NSHomeDirectory()
        let shell = "/bin/bash"
        let script = """
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        pyenv \(arguments.joined(separator: " "))
        """
        
        let env = pyenvEnvironment
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
    
    /// 执行带进度的 pyenv 命令
    private func executeCommandWithProgress(arguments: [String], message: String? = nil, timeout: TimeInterval = 300) async -> OperationResult {
        isLoading = true
        loadingMessage = message ?? "正在执行 pyenv \(arguments.joined(separator: " "))..."
        
        _ = NSHomeDirectory()
        let shell = "/bin/bash"
        let script = """
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init --path)"
        pyenv \(arguments.joined(separator: " "))
        """
        
        let env = pyenvEnvironment
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

// MARK: - Python 版本模型

struct PyenvVersion: Identifiable, Hashable {
    let id: String
    let version: String
    let isGlobal: Bool
    
    init(version: String, isGlobal: Bool = false) {
        self.id = version
        self.version = version
        self.isGlobal = isGlobal
    }
}
