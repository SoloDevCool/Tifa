import Foundation

/// RVM 服务 - 执行 rvm 命令
@MainActor
class RVMService: ObservableObject {
    
    static let shared = RVMService()
    
    @Published var isLoading = false
    @Published var loadingMessage = ""

    /// 当前正在执行的安装进程（用于取消）
    private var currentInstallProcess: Process?
    
    /// 取消当前安装进程
    func cancelCurrentInstall() {
        currentInstallProcess?.terminate()
        currentInstallProcess = nil
    }

    /// RVM 路径
    private var rvmPath: String {
        let home = NSHomeDirectory()
        let path = "\(home)/.rvm/scripts/rvm"
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
        // 尝试通过 shell 查找
        return "rvm"
    }
    
    /// 构建 RVM 需要的环境变量
    private var rvmEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        
        // RVM 需要的 PATH
        let rvmPaths = "\(home)/.rvm/bin:\(home)/.rvm/gems/ruby-*/bin"
        let extraPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "\(rvmPaths):\(extraPaths):\(currentPath)"
        
        env["HOME"] = home
        env["rvm_path"] = "\(home)/.rvm"
        
        return env
    }
    
    /// 检查 RVM 是否可用
    func checkRVMAvailability() -> Bool {
        let home = NSHomeDirectory()
        let rvmDir = "\(home)/.rvm"
        return FileManager.default.fileExists(atPath: rvmDir)
    }
    
    /// 获取 RVM 安装路径
    func getRVMPath() -> String {
        let home = NSHomeDirectory()
        let rvmDir = "\(home)/.rvm"
        if FileManager.default.fileExists(atPath: rvmDir) {
            return rvmDir
        }
        return "未知"
    }
    
    /// 获取当前使用的 Ruby 版本
    func getCurrentRubyVersion() async -> String {
        let result = await executeCommand(arguments: ["ruby", "--version"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }
    
    /// 获取已安装的 Ruby 版本列表
    func listInstalledRubies() async -> [RubyVersion] {
        let result = await executeCommand(arguments: ["list"])
        switch result {
        case .success(let output):
            return parseRubyList(output: output)
        case .failure:
            return []
        }
    }
    
    /// 获取已知的 Ruby 版本（用于安装）
    func listKnownRubies() async -> [String] {
        let result = await executeCommand(arguments: ["list", "known"])
        switch result {
        case .success(let output):
            return parseKnownRubies(output: output)
        case .failure:
            return []
        }
    }
    
    /// 切换默认 Ruby 版本
    func useRuby(version: String) async -> OperationResult {
        let rubyName = "ruby-\(version)"
        return await executeCommandWithProgress(arguments: ["use", rubyName, "--default"])
    }
    
    /// 安装 Ruby 版本
    func installRuby(version: String) async -> OperationResult {
        let rubyName = "ruby-\(version)"
        return await executeCommandWithProgress(arguments: ["install", rubyName])
    }
    
    /// 安装 Ruby 版本（带实时输出）
    func installRubyWithOutput(version: String, method: RubyInstallMethod, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let rubyName = "ruby-\(version)"
        let home = NSHomeDirectory()
        let binaryFlag = method == .binary ? " --binary" : ""
        let script = "source \(home)/.rvm/scripts/rvm && rvm install \(rubyName)\(binaryFlag)"
        
        return await runInstallScript(script: script, onOutput: onOutput)
    }
    
    /// 自动修复 openssl 依赖后编译安装
    func installRubyWithOpenSSLFix(version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let home = NSHomeDirectory()
        
        // 步骤 1: 安装 openssl@1.1
        let opensslScript = """
        brew install rbenv/tap/openssl@1.1 2>&1
        OPENSSL_DIR=$(brew --prefix rbenv/tap/openssl@1.1 2>/dev/null || echo "")
        echo "OPENSSL_PREFIX=$OPENSSL_DIR"
        """
        let opensslResult = await runInstallScript(script: opensslScript, onOutput: onOutput)
        
        // 提取 openssl 安装路径
        var opensslDir = ""
        if case .success(let output) = opensslResult {
            if let range = output.range(of: "OPENSSL_PREFIX=") {
                let after = output[range.upperBound...]
                opensslDir = after.prefix(while: { !$0.isNewline }).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // 步骤 2: 用 openssl 路径编译安装
        Task { @MainActor in
            onOutput("\n--- 开始使用 openssl@1.1 编译安装 ---\n")
        }
        
        let installScript: String
        if !opensslDir.isEmpty {
            installScript = """
            source \(home)/.rvm/scripts/rvm
            export PKG_CONFIG_PATH="\(opensslDir)/lib/pkgconfig:$PKG_CONFIG_PATH"
            export RUBY_CONFIGURE_OPTS="--with-openssl-dir=\(opensslDir)"
            rvm install ruby-\(version) --with-openssl-dir=\(opensslDir)
            """
        } else {
            // 回退：尝试 rvm 自带的 openssl
            installScript = """
            source \(home)/.rvm/scripts/rvm
            rvm pkg install openssl
            rvm install ruby-\(version) --with-openssl-dir=$rvm_path/usr
            """
        }
        
        return await runInstallScript(script: installScript, onOutput: onOutput)
    }
    
    /// 执行安装脚本（通用）
    private func runInstallScript(script: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let shell = "/bin/zsh"
        let env = rvmEnvironment
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    Task { @MainActor in
                        continuation.resume(returning: .failure("Service not available"))
                    }
                    return
                }
                
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
                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .newlines)
                        if !trimmed.isEmpty {
                            Task { @MainActor in
                                onOutput(trimmed)
                            }
                        }
                    }
                }
                
                // 实时读取 stderr
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .newlines)
                        if !trimmed.isEmpty {
                            Task { @MainActor in
                                onOutput(trimmed)
                            }
                        }
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    Task { @MainActor in
                        self.currentInstallProcess = nil
                    }
                    
                    // 清理 handler
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    
                    let exitCode = process.terminationStatus
                    DispatchQueue.main.async {
                        if exitCode == 0 {
                            continuation.resume(returning: .success("安装成功"))
                        } else {
                            continuation.resume(returning: .failure("安装失败，退出码: \(exitCode)"))
                        }
                    }
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    DispatchQueue.main.async {
                        continuation.resume(returning: .failure(error.localizedDescription))
                    }
                }
            }
        }
    }
    
    /// 卸载 Ruby 版本
    func uninstallRuby(version: String) async -> OperationResult {
        let rubyName = "ruby-\(version)"
        return await executeCommandWithProgress(arguments: ["uninstall", rubyName, "--force"])
    }
    
    /// 获取当前默认版本
    func getDefaultRubyVersion() async -> String {
        let result = await executeCommand(arguments: ["list", "default"])
        switch result {
        case .success(let output):
            // 解析 default 字符串
            if let regex = try? NSRegularExpression(pattern: #"ruby-([\d.]+)"#),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) {
                return String(output[range])
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }
    
    /// 获取 Gemset 列表
    func listGemsets(rubyVersion: String) async -> [String] {
        let rubyName = "ruby-\(rubyVersion)"
        let result = await executeCommand(arguments: ["gemset", "list", rubyName])
        switch result {
        case .success(let output):
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case .failure:
            return []
        }
    }
    
    // MARK: - RVM 安装/卸载
    
    /// 安装 RVM
    func installRVM() async -> OperationResult {
        return await executeRawCommand(
            script: "\\curl -sSL https://get.rvm.io | bash -s stable",
            message: "正在安装 RVM...",
            timeout: 300
        )
    }
    
    /// 卸载 RVM
    func uninstallRVM() async -> OperationResult {
        let home = NSHomeDirectory()
        return await executeRawCommand(
            script: "rvm implode --force && rm -rf \(home)/.rvm",
            message: "正在卸载 RVM...",
            timeout: 60
        )
    }
    
    // MARK: - Ruby 安装源管理（rvm_ruby_url）
    
    /// RVM 用户配置文件路径
    private var rvmUserConfigPath: String {
        return "\(NSHomeDirectory())/.rvm/user/db"
    }
    
    /// 获取当前 Ruby 安装源 URL
    func getRubyInstallSource() async -> String {
        // 优先通过 RVM 命令检测
        let result = await executeCommand(arguments: ["ruby", "-e", "puts ENV['rvm_ruby_url'] || ''"])
        if case .success(let output) = result, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 回退：检查 ~/.rvm/user/db 文件中的 rvm_ruby_url
        let path = rvmUserConfigPath
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("rvm_ruby_url=") {
                    let value = trimmed
                        .replacingOccurrences(of: "rvm_ruby_url=", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                    return value
                }
            }
        }
        // 默认返回官方源
        return ""
    }
    
    /// 设置 Ruby 安装源 URL
    func setRubyInstallSource(_ url: String) async -> OperationResult {
        return await executeRawCommand(
            script: "mkdir -p ~/.rvm/user && echo 'rvm_ruby_url=\"\(url)\"' >> ~/.rvm/user/db && echo '成功设置 rvm_ruby_url=\(url)'",
            message: "正在设置 Ruby 安装源...",
            timeout: 10
        )
    }
    
    // MARK: - Gem 源管理
    
    /// 获取当前 gem 源列表
    func listGemSources() async -> [String] {
        let home = NSHomeDirectory()
        let script = "source \(home)/.rvm/scripts/rvm && gem sources 2>&1"
        let result = await runGemCommand(script: script, timeout: 15)
        if case .success(let output) = result {
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        }
        return []
    }
    
    /// 添加 gem 源（同时移除其他源，确保单源）
    func addGemSource(_ url: String) async -> OperationResult {
        return await switchGemSource(to: url)
    }
    
    /// 移除 gem 源
    func removeGemSource(_ url: String) async -> OperationResult {
        let home = NSHomeDirectory()
        let script = "source \(home)/.rvm/scripts/rvm && gem sources --remove \(url) 2>&1"
        return await runGemCommand(script: script, timeout: 15)
    }
    
    /// 清空所有 gem 源
    func clearGemSources() async -> OperationResult {
        let home = NSHomeDirectory()
        let script = "source \(home)/.rvm/scripts/rvm && gem sources --clear 2>&1"
        return await runGemCommand(script: script, timeout: 15)
    }
    
    /// 原子化切换 gem 源（直接写入 ~/.gemrc，确保单源）
    func switchGemSource(to url: String) async -> OperationResult {
        let home = NSHomeDirectory()
        let gemrcPath = "\(home)/.gemrc"
        let content = "---\n:sources:\n- \(url)\n"
        let script = "echo '\(content)' > \"\(gemrcPath)\" 2>&1 && gem sources 2>&1"
        
        let result = await runGemCommand(script: script, timeout: 15)
        
        if case .success(let output) = result {
            let lines = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            
            if lines.count == 1 {
                return .success("已切换到 \(url)")
            } else {
                // ~/.gemrc 已写入，但 gem sources 可能还读到系统默认源
                return .success("已设置 ~/.gemrc 为 \(url)\n\n注意：gem sources 显示 \(lines.count) 个源，可能是系统默认源的影响。重启终端后生效。")
            }
        }
        return result
    }
    
    /// 执行 gem 相关命令（不触发全局 loading）
    private func runGemCommand(script: String, timeout: TimeInterval) async -> OperationResult {
        let env = ProcessInfo.processInfo.environment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", script]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
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
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    timer.cancel()
                    continuation.resume(returning: .failure("命令执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    // MARK: - 私有方法
    
    /// 执行原始 shell 命令（不依赖 RVM 环境）
    func executeRawCommand(script: String, message: String, timeout: TimeInterval = 60) async -> OperationResult {
        isLoading = true
        loadingMessage = message
        
        let env = ProcessInfo.processInfo.environment
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", script]
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
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
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    timer.cancel()
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("命令执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func parseRubyList(output: String) -> [RubyVersion] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ($0.contains("ruby-") || $0.contains("=")) }
        
        return lines.compactMap { line -> RubyVersion? in
            let isCurrent = line.contains("=>") || line.contains("*")
            let isDefault = line.contains("=>")
            
            let pattern = #"ruby-([\d.]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else {
                return nil
            }
            
            let version = String(line[range])
            return RubyVersion(version: version, isCurrent: isCurrent, isDefault: isDefault)
        }
    }
    
    private func parseKnownRubies(output: String) -> [String] {
        // rvm list known 输出格式: [ruby-]3.3.0, [ruby-]3.2.2, ...
        let pattern = #"\[ruby-\]([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, range: range)
        
        return matches.compactMap { match -> String? in
            guard let versionRange = Range(match.range(at: 1), in: output) else { return nil }
            return String(output[versionRange])
        }
    }
    
    func executeCommand(arguments: [String]) async -> OperationResult {
        let home = NSHomeDirectory()
        let shell = "/bin/zsh"
        let script = "source \(home)/.rvm/scripts/rvm && rvm \(arguments.joined(separator: " "))"
        
        let env = rvmEnvironment
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
                    continuation.resume(returning: .failure("无法启动 rvm: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func executeCommandWithProgress(arguments: [String]) async -> OperationResult {
        isLoading = true
        loadingMessage = "正在执行 rvm \(arguments.joined(separator: " "))..."
        
        let home = NSHomeDirectory()
        let shell = "/bin/zsh"
        let script = "source \(home)/.rvm/scripts/rvm && rvm \(arguments.joined(separator: " "))"
        
        let env = rvmEnvironment
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
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                    }
                    continuation.resume(returning: .failure("无法启动 rvm: \(error.localizedDescription)"))
                }
            }
        }
    }
}
