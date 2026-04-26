import Foundation

/// GVM 管理的 Go 版本信息
struct GvmGoVersion: Identifiable, Hashable {
    let id: String
    let version: String
    let isActive: Bool
}

/// GVM 服务 - 管理 Go 版本管理器
@MainActor
class GvmService: ObservableObject {

    static let shared = GvmService()

    @Published var isLoading = false
    @Published var loadingMessage = ""

    /// 当前正在执行的安装进程（用于取消）
    private var currentInstallProcess: Process?

    /// 取消当前安装进程
    func cancelCurrentInstall() {
        currentInstallProcess?.terminate()
        currentInstallProcess = nil
    }

    /// gvm 安装目录
    private var gvmDir: String {
        "\(NSHomeDirectory())/.gvm"
    }

    /// gvm go 目录
    private var gvmGosDir: String {
        "\(gvmDir)/gos"
    }

    /// gvm 脚本路径
    private var gvmScriptPath: String {
        "\(gvmDir)/bin/gvm"
    }

    /// 构建 gvm 执行环境
    private var gvmEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        let gvmPaths = "\(gvmDir)/bin:\(gvmDir)/gos/go1.4/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(gvmPaths):\(currentPath)"
        } else {
            env["PATH"] = gvmPaths
        }
        env["GVM_ROOT"] = gvmDir
        // 动态查找已安装的 Go 作为引导编译器，优先使用最新版本
        env["GOROOT_BOOTSTRAP"] = Self.findGoBootstrap(gvmDir: gvmDir)
        return env
    }

    /// 在 gvm 已安装的 Go 版本中，查找一个可用的引导编译器
    /// 返回包含 bin/go 的最高版本 GOROOT 路径
    private static func findGoBootstrap(gvmDir: String) -> String {
        let fm = FileManager.default
        let gosDir = "\(gvmDir)/gos"
        guard let entries = try? fm.contentsOfDirectory(atPath: gosDir) else {
            return "\(gvmDir)/gos/go1.4" // 回退默认值
        }
        // 过滤出有 bin/go 的版本，按版本号降序排列，取最新的
        let validVersions = entries
            .filter { $0.hasPrefix("go") && fm.fileExists(atPath: "\(gosDir)/\($0)/bin/go") }
            .sorted { $0 > $1 }
        if let latest = validVersions.first {
            return "\(gosDir)/\(latest)"
        }
        return "\(gvmDir)/gos/go1.4"
    }

    // MARK: - 安装/卸载 gvm

    /// 安装 gvm
    func installGvm(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
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
                        continuation.resume(returning: .success("gvm 安装成功"))
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

    /// 卸载 gvm
    func uninstallGvm() async -> OperationResult {
        isLoading = true
        loadingMessage = "正在卸载 gvm..."
        defer { isLoading = false }

        // 移除 shell 配置中的 gvm 部分
        let configFiles = [".zshrc", ".bash_profile", ".bashrc", ".profile", ".zshenv"]
        let home = NSHomeDirectory()
        for file in configFiles {
            let path = "\(home)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: "\n")
            var newLines: [String] = []
            var skip = false
            for line in lines {
                if line.contains("GVM_ROOT") || line.contains(".gvm/bin") || line.contains("gvm init") {
                    skip = true
                    continue
                }
                if skip && line.trimmingCharacters(in: .whitespaces).isEmpty {
                    skip = false
                    continue
                }
                newLines.append(line)
            }
            let newContent = newLines.joined(separator: "\n")
            try? newContent.write(toFile: path, atomically: true, encoding: .utf8)
        }

        // 删除 gvm 目录
        let result = await executeRawCommand(script: "rm -rf \(gvmDir)")
        if case .success = result {
            return .success("gvm 已卸载")
        }
        return .failure("卸载失败")
    }

    // MARK: - 检查可用性

    /// 检查 gvm 是否已安装
    func checkGvmAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: gvmScriptPath)
    }

    /// 获取 gvm 版本
    func getGvmVersion() async -> String {
        let result = await executeGvmCommand(arguments: ["version"])
        if case .success(let output) = result {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "未知" : trimmed
        }
        return "未知"
    }

    /// 获取 gvm 路径
    func getGvmPath() -> String {
        return gvmScriptPath
    }

    /// 检查 gvm shell 环境是否已配置
    func isGvmConfigured() -> Bool {
        let configFiles = [".zshrc", ".bash_profile", ".bashrc", ".profile", ".zshenv"]
        let home = NSHomeDirectory()

        for file in configFiles {
            let path = "\(home)/\(file)"
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                if content.contains("GVM_ROOT") || content.contains(".gvm/bin") || content.contains("gvm init") {
                    return true
                }
            }
        }
        return false
    }

    /// 获取已配置的文件列表
    func getConfiguredFiles() -> [(file: String, hasConfig: Bool)] {
        let configFiles = [".zshrc", ".bash_profile", ".bashrc", ".profile", ".zshenv"]
        let home = NSHomeDirectory()
        return configFiles.map { file in
            let path = "\(home)/\(file)"
            let hasConfig: Bool
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                hasConfig = content.contains("GVM_ROOT") || content.contains(".gvm/bin") || content.contains("gvm init")
            } else {
                hasConfig = false
            }
            return (file: file, hasConfig: hasConfig)
        }
    }

    // MARK: - Go 版本管理

    /// 获取可用的 Go 版本列表
    func listAvailableVersions() async -> [String] {
        let result = await executeGvmCommand(arguments: ["listall"])
        guard case .success(let output) = result else { return [] }

        let allVersions = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.hasPrefix("go") }

        // 过滤掉 go1.4.x（GVM 内部引导版本，无需用户手动安装）
        // 以及 beta/rc/alpha 版本，返回前 20 个稳定版本
        let filtered = allVersions
            .filter { !$0.contains("beta") && !$0.contains("rc") && !$0.contains("alpha") }
            .filter { version in
                guard let range = version.range(of: "go1\\.4", options: .regularExpression) else { return true }
                let remainder = version[range.upperBound...]
                // go1.4 或 go1.4.x（如 go1.4.3）属于引导版本，go1.4+ 不是
                if remainder.isEmpty || remainder.first == "." { return false }
                return true
            }
            .prefix(20)

        return Array(filtered)
    }

    /// 获取已安装的 Go 版本列表
    func listInstalledVersions() async -> [GvmGoVersion] {
        let result = await executeGvmCommand(arguments: ["list"])
        guard case .success(let output) = result else { return [] }

        let activeResult = await getActiveVersion()
        var versions: [GvmGoVersion] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // gvm list 输出格式: "=> go1.22.0" (=> 表示活跃) 或 "   go1.21.0"
            let isActive = trimmed.contains("=>")
            var version = trimmed
                .replacingOccurrences(of: "=>", with: "")
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !version.isEmpty else { continue }
            versions.append(GvmGoVersion(
                id: version,
                version: version,
                isActive: isActive || version == activeResult
            ))
        }

        return versions
    }

    /// 获取当前活跃的 Go 版本
    func getActiveVersion() async -> String {
        let result = await executeGvmCommand(arguments: ["gvm", "pkgset", "list"])
        // 也尝试 go version
        let goResult = await executeGvmCommand(arguments: ["go", "version"])
        if case .success(let output) = goResult {
            // 输出如: go version go1.22.0 darwin/arm64
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            for part in trimmed.components(separatedBy: " ") {
                if part.hasPrefix("go") && part != "go" {
                    return part
                }
            }
        }
        return ""
    }

    /// 检查 go1.4 引导版本是否已安装
    func isBootstrapInstalled() async -> Bool {
        let result = await executeGvmCommand(arguments: ["list"])
        guard case .success(let output) = result else { return false }
        return output.contains("go1.4")
    }

    /// 安装 go1.4 引导版本
    /// 使用预编译二进制安装（go1.4 太旧，无法在现代 macOS 上从源码编译）
    func installBootstrapGo(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "source \(gvmDir)/scripts/gvm && gvm install go1.4 -B"
        let label = "📦 正在下载 go1.4 引导版本（预编译二进制）...\n"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = self.gvmEnvironment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                var capturedOutput = label
                Task { @MainActor in onOutput(label) }

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    capturedOutput += output
                    Task { @MainActor in onOutput(output) }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    capturedOutput += output
                    Task { @MainActor in onOutput(output) }
                }

                do {
                    try process.run()
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    var timedOut = false
                    timer.schedule(deadline: .now() + 300) // 5 分钟超时
                    timer.setEventHandler { timedOut = true; process.terminate() }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let remainingStdout = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { capturedOutput += remainingStdout; Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { capturedOutput += remainingStderr; Task { @MainActor in onOutput(remainingStderr) } }

                    if timedOut {
                        continuation.resume(returning: .failure("go1.4 引导版本下载超时，请检查网络后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("go1.4 引导版本安装成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "go1.4 安装失败 (exit code \(process.terminationStatus))" : remainingStderr
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

    /// 检测版本是否需要 go1.4 作为引导编译器
    /// Go 1.5 ~ 1.19 需要至少 Go 1.4 作为 GOROOT_BOOTSTRAP
    /// 在 ARM64 macOS 上无法安装 go1.4，因此这些版本无法源码编译
    static func requiresGo14Bootstrap(_ version: String) -> Bool {
        guard let major = version.dropFirst(2).split(separator: ".").first,
              let majorNum = Int(major) else { return false }
        return majorNum <= 19
    }

    /// 安装指定版本的 Go
    /// - Parameters:
    ///   - version: Go 版本号
    ///   - preferBinary: 是否优先使用二进制包（默认 true），失败后可从源码编译
    func installGoVersion(_ version: String, preferBinary: Bool = true, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        // 源码编译模式下，检测是否需要 go1.4 引导（ARM64 上不可用）
        if !preferBinary && Self.requiresGo14Bootstrap(version) && Self.findGoBootstrap(gvmDir: gvmDir).hasSuffix("go1.4") {
            return .failure("Go \(version) 需要 go1.4 引导编译器，但 ARM64 Mac 不支持安装 go1.4。\n建议安装 Go 1.21+ 版本（提供 ARM64 预编译包）。")
        }

        let useBinary = preferBinary && !version.hasPrefix("go1.4")
        let binaryFlag = useBinary ? "--prefer-binary" : ""
        let script = "source \(gvmDir)/scripts/gvm && gvm install \(version) \(binaryFlag)".trimmingCharacters(in: .whitespaces)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = self.gvmEnvironment
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
                    let remainingStderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if timedOut {
                        continuation.resume(returning: .failure("安装超时（10 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Go \(version) 安装成功"))
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

    /// 卸载指定版本的 Go
    func uninstallGoVersion(_ version: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "source \(gvmDir)/scripts/gvm && gvm uninstall \(version)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = self.gvmEnvironment
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
                    let remainingStderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Go \(version) 卸载成功"))
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

    /// 设置默认 Go 版本
    func setDefaultVersion(_ version: String) async -> OperationResult {
        return await executeGvmCommand(arguments: ["use", version, "--default"])
    }

    /// 使用指定版本的 Go（当前会话）
    func useVersion(_ version: String) async -> OperationResult {
        return await executeGvmCommand(arguments: ["use", version])
    }

    // MARK: - Shell 配置

    /// 配置 shell 环境变量
    func configureShell(to fileName: String = ".zshrc") async -> OperationResult {
        let configBlock = """

        # gvm (Go Version Manager)
        export GVM_ROOT="$HOME/.gvm"
        source "$GVM_ROOT/scripts/gvm"
        """

        let configPath = NSHomeDirectory() + "/\(fileName)"

        if FileManager.default.fileExists(atPath: configPath),
           let content = try? String(contentsOfFile: configPath, encoding: .utf8),
           content.contains("GVM_ROOT") {
            return .success("gvm 配置已存在于 \(fileName)")
        }

        if var content = (try? String(contentsOfFile: configPath, encoding: .utf8)) {
            content += configBlock
            do {
                try content.write(toFile: configPath, atomically: true, encoding: .utf8)
                return .success("已将 gvm 配置写入 \(fileName)\n\n请重启终端或运行: source \(fileName)")
            } catch {
                return .failure("写入失败: \(error.localizedDescription)")
            }
        } else {
            do {
                try configBlock.write(toFile: configPath, atomically: true, encoding: .utf8)
                return .success("已创建 \(fileName) 并写入 gvm 配置\n\n请重启终端或运行: source \(fileName)")
            } catch {
                return .failure("创建文件失败: \(error.localizedDescription)")
            }
        }
    }

    /// 移除 shell 配置
    func removeShellConfig(from fileName: String = ".zshrc") async -> OperationResult {
        let configPath = NSHomeDirectory() + "/\(fileName)"
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return .success("\(fileName) 不存在或为空")
        }

        let lines = content.components(separatedBy: "\n")
        var newLines: [String] = []
        var skip = false
        for line in lines {
            if line.contains("GVM_ROOT") || line.contains(".gvm/bin") || line.contains("gvm init") {
                skip = true
                continue
            }
            if skip && line.trimmingCharacters(in: .whitespaces).isEmpty {
                skip = false
                continue
            }
            newLines.append(line)
        }

        let newContent = newLines.joined(separator: "\n")
        do {
            try newContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            return .success("已从 \(fileName) 移除 gvm 配置\n\n请重启终端使配置生效。")
        } catch {
            return .failure("写入失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有方法

    private func executeGvmCommand(arguments: [String]) async -> OperationResult {
        let argsStr = arguments.joined(separator: " ")
        let script = "source \(gvmDir)/scripts/gvm && gvm \(argsStr)"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-l", "-c", script]
                process.environment = self.gvmEnvironment
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

    private func executeRawCommand(script: String) async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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

                    DispatchQueue.main.async { self.isLoading = false }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    DispatchQueue.main.async { self.isLoading = false }
                    continuation.resume(returning: .failure("命令执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }
}
