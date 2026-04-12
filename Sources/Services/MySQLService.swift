import Foundation

/// MySQL 数据库信息模型
struct MySQLDatabase: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String
    let tableCount: Int
    let charset: String
}

/// MySQL 软件包信息
struct MySQLVersionInfo: Identifiable, Hashable {
    let id: String          // formula 名称，如 "tifa-mysql@8.0"
    let displayName: String // 显示名，如 "MySQL 8.0"
    let formula: String      // brew formula，如 "tifa-mysql@8.0"
    let port: Int            // 端口
    let dataDir: String      // 数据目录
    let installed: Bool      // 是否已安装
    let pid: Int?            // MySQL 服务进程 PID
    let activated: Bool      // 是否通过 PATH 激活
}

/// MySQL 服务 - 管理 MySQL（使用 homebrew-tifa-mysql tap）
/// 支持 MySQL 8.0 和 9.6 双版本同时运行
@MainActor
class MySQLService: ObservableObject {
    
    static let shared = MySQLService()
    
    /// Homebrew tap 地址
    static let tapRepo = "SoloDevCool/homebrew-tifa-mysql"
    
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var lastError: String?
    
    /// 所有可安装的 MySQL 版本
    static let availableVersions: [(name: String, formula: String, port: Int, dataDir: String)] = [
        ("MySQL 9.6", "tifa-mysql@9.6", 3306, "tifa-mysql9"),
        ("MySQL 8.0", "tifa-mysql@8.0", 3306, "tifa-mysql8"),
    ]
    
    /// 当前活跃版本
    @Published var activeVersion: String = ""
    
    /// 所有已安装版本信息
    @Published var installedVersions: [MySQLVersionInfo] = []
    
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
    
    /// MySQL 可执行文件路径（基于版本别名命令）
    func mysqlBinPath(for formula: String) -> String {
        let optPath = "\(brewPrefix)/opt/\(formula)"
        return "\(optPath)/bin"
    }
    
    /// MySQL 数据目录
    func mysqlDataDir(for formula: String, dataDir: String) -> String {
        if !dataDir.isEmpty {
            return "\(brewPrefix)/var/\(dataDir)"
        }
        return "\(brewPrefix)/var/mysql"
    }
    
    /// 构建 MySQL 命令执行环境
    private var mysqlEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "\(brewPrefix)/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        env["HOME"] = NSHomeDirectory()
        return env
    }
    
    // MARK: - Tap 管理
    
    /// 检查 tap 是否已添加
    func isTapAdded() async -> Bool {
        let result = await executeCommand(executable: brewPath, arguments: ["tap"])
        if case .success(let output) = result {
            return output.contains(Self.tapRepo)
        }
        return false
    }
    
    /// 添加 tap
    func addTap() async -> OperationResult {
        loadingMessage = "正在添加 Homebrew tap..."
        let result = await executeCommandWithProgress(executable: brewPath, arguments: ["tap", Self.tapRepo])
        return result
    }
    
    // MARK: - 版本管理
    
    /// 检测所有已安装的 MySQL 软件包
    func detectInstalledVersions() async {
        // 1. 获取已安装的 formula 列表
        let listResult = await executeCommand(executable: brewPath, arguments: ["list", "--formula"], timeoutSeconds: 10)
        
        // 2. 获取服务列表（不依赖 PID 解析）- 使用较短超时
        let servicesResult = await executeCommand(executable: brewPath, arguments: ["services", "list"], timeoutSeconds: 5)
        
        // 3. 使用 pgrep 查找 MySQL 进程 PID
        let pgrepResult = await executeCommand(executable: "/usr/bin/pgrep", arguments: ["-f", "mysqld"], timeoutSeconds: 5)
        
        // 解析已安装的 formula
        var installedFormulas: Set<String> = []
        if case .success(let output) = listResult {
            installedFormulas = Set(output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
        
        // 解析服务运行状态（只用 Status 列）
        var startedServices: Set<String> = []
        if case .success(let output) = servicesResult {
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("started") {
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if let formula = parts.first {
                        startedServices.insert(formula)
                    }
                }
            }
        }
        
        // 解析 PID（使用 pgrep 的第一行）
        var runningPID: Int?
        if case .success(let output) = pgrepResult {
            let pidStr = output.components(separatedBy: .newlines).first ?? ""
            runningPID = Int(pidStr.trimmingCharacters(in: .whitespaces))
        }
        
        // 检测 PATH 中激活的版本
        let activatedFormula = getCurrentPathVersion()
        
        var versions: [MySQLVersionInfo] = []
        
        // 首先检查已安装的 tifa-mysql 版本
        for ver in Self.availableVersions {
            let formula = ver.formula
            let installed = installedFormulas.contains(formula)
            let isStarted = installed && startedServices.contains(formula)
            let pid = isStarted ? runningPID : nil
            let activated = activatedFormula == formula
            
            versions.append(MySQLVersionInfo(
                id: formula,
                displayName: ver.name,
                formula: formula,
                port: ver.port,
                dataDir: ver.dataDir,
                installed: installed,
                pid: pid,
                activated: activated
            ))
        }
        
        // 如果没有检测到 tifa-mysql，检查普通 mysql 或 mysql@X.X
        let hasTifaMySQL = versions.contains { $0.installed }
        if !hasTifaMySQL {
            // 检查普通 mysql 相关包
            let mysqlFormulas = ["mysql", "mysql@8.0", "mysql@5.7", "mysql@8.4"]
            for formula in mysqlFormulas {
                if installedFormulas.contains(formula) {
                    // 创建一个简化的版本信息
                    let displayName = formula == "mysql" ? "MySQL (最新)" : formula.replacingOccurrences(of: "@", with: " ")
                    let isStarted = startedServices.contains(formula)
                    let pid = isStarted ? runningPID : nil
                    
                    versions.append(MySQLVersionInfo(
                        id: formula,
                        displayName: displayName,
                        formula: formula,
                        port: 3306,
                        dataDir: "mysql",
                        installed: true,
                        pid: pid,
                        activated: activatedFormula == formula
                    ))
                    break  // 只添加第一个匹配的
                }
            }
        }
        
        installedVersions = versions
        
        // 设置 activeVersion：PATH 中激活的版本
        if let pathVersion = activatedFormula {
            activeVersion = versions.first { $0.formula == pathVersion }?.displayName ?? pathVersion
        } else if let firstInstalled = versions.first(where: { $0.installed }) {
            activeVersion = firstInstalled.displayName
        } else {
            activeVersion = ""
        }
    }
    
    /// 安装指定版本（带重试机制）
    func installVersion(formula: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        // 立即输出开始信息
        Task { @MainActor in onOutput("正在准备安装 \(formula)...\n") }
        
        // 先检查 tap 是否已添加
        let tapAdded = await isTapAdded()
        if !tapAdded {
            Task { @MainActor in onOutput("正在添加 Homebrew tap...\n") }
            let _ = await addTap()
            Task { @MainActor in onOutput("Tap 添加完成\n") }
        } else {
            Task { @MainActor in onOutput("Tap 已存在\n") }
        }
        
        // 执行安装（带重试）
        let maxRetries = 2
        var lastError: String = ""
        
        for attempt in 0...maxRetries {
            if attempt > 0 {
                Task { @MainActor in onOutput("\n⚠️ 安装失败，准备第 \(attempt + 1) 次重试...\n") }
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 等待 2 秒
            }
            
            Task { @MainActor in onOutput("\n正在下载并安装 \(formula)，请稍候...\n") }
            
            let result = await executeInstallCommand(formula: formula, onOutput: onOutput)
            
            if case .success(let output) = result {
                return .success(output)
            } else if case .failure(let error) = result {
                lastError = error
                // 检查是否是网络错误
                if error.contains("Cannot download") || error.contains("network") || error.contains("Connection") {
                    continue // 继续重试
                } else {
                    // 非网络错误，不再重试
                    break
                }
            }
        }
        
        // 所有重试都失败
        Task { @MainActor in
            onOutput("\n" + """
            ❌ 安装失败 (已重试 \(maxRetries + 1) 次)
            
            💡 可能的解决方案:
            1. 检查网络连接
            2. 如果使用代理，请在系统设置中配置 Homebrew 代理
            3. 尝试清理缓存: brew cleanup --prune=all
            4. 手动在终端执行: brew update && brew install \(formula)
            """)
        }
        
        return .failure(lastError)
    }
    
    /// 执行 brew install 命令（内部使用）
    private func executeInstallCommand(formula: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let brewExecPath = brewPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: brewExecPath)
                process.arguments = ["install", formula]
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading
                
                func appendOutput(_ text: String) {
                    let trimmed = text.trimmingCharacters(in: .newlines)
                    guard !trimmed.isEmpty else { return }
                    Task { @MainActor in onOutput(trimmed + "\n") }
                }
                
                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
                    appendOutput(str)
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
                    appendOutput(str)
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    
                    // 读取残余数据
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    
                    if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendOutput(stdout)
                    }
                    if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        appendOutput(stderr)
                    }
                    
                    // 检查安装是否成功：退出码为0 或者输出包含成功标志
                    let combinedOutput = stdout + stderr
                    let isSuccess = process.terminationStatus == 0 || 
                                    combinedOutput.contains("🍺") || 
                                    combinedOutput.contains("Installing.*\(formula)") ||
                                    combinedOutput.contains("Cellar/\\(formula)")
                    
                    if isSuccess {
                        Task { @MainActor in
                            onOutput("\n✅ \(formula) 安装成功")
                            onOutput("\n💡 使用 \(self.getClientCommand(for: formula)) -u root 连接数据库")
                            await self.detectInstalledVersions()
                        }
                        continuation.resume(returning: .success(combinedOutput))
                    } else {
                        let error = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(error.isEmpty ? "安装失败 (exit code \(process.terminationStatus))" : error))
                    }
                } catch {
                    Task { @MainActor in onOutput("\n❌ 无法启动 brew: \(error.localizedDescription)") }
                    continuation.resume(returning: .failure("无法启动 brew: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 启动指定版本的 MySQL（同一时间只能运行一个版本）
    func switchVersion(to formula: String) async -> OperationResult {
        // 先停止所有 MySQL 服务
        for ver in Self.availableVersions {
            if ver.formula != formula {
                _ = await executeCommand(executable: brewPath, arguments: ["services", "stop", ver.formula])
            }
        }
        
        // 启动目标版本
        let result = await executeCommandWithProgress(executable: brewPath, arguments: ["services", "start", formula])
        if case .success = result {
            await detectInstalledVersions()
            return .success("已启动 \(formula)")
        }
        return result
    }
    
    /// 卸载指定版本
    func uninstallVersion(formula: String) async -> OperationResult {
        // 先停止服务
        _ = await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", formula])
        
        let result = await executeCommandWithProgress(executable: brewPath, arguments: ["uninstall", formula])
        
        if case .success = result {
            await detectInstalledVersions()
            return .success("\(formula) 已卸载")
        }
        return result
    }
    
    // MARK: - 检查可用性
    
    /// 获取运行中的服务名称
    private var runningServiceName: String? {
        for ver in installedVersions where ver.pid != nil {
            return ver.formula
        }
        return nil
    }
    
    /// 获取客户端命令（通过 PATH 指向的版本）
    func getClientCommand(for formula: String) -> String {
        let binPath = mysqlBinPath(for: formula)
        return "\(binPath)/mysql"
    }
    
    /// 获取当前 PATH 中指向的 MySQL 版本
    /// 优先从 ~/.zshrc 中解析（保证重启后状态持久化）
    func getCurrentPathVersion() -> String? {
        // 1. 先从 ~/.zshrc 解析（持久化配置）
        if let version = parseActiveVersionFromZshrc() {
            return version
        }
        
        // 2. 备用：检查当前进程的 PATH
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PATH"] else { return nil }
        
        for ver in Self.availableVersions {
            let binPath = "\(brewPrefix)/opt/\(ver.formula)/bin"
            if path.contains(binPath) {
                return ver.formula
            }
        }
        return nil
    }
    
    /// 从 ~/.zshrc 解析当前激活的 MySQL 版本
    private func parseActiveVersionFromZshrc() -> String? {
        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        guard let content = try? String(contentsOfFile: zshrcPath, encoding: .utf8) else {
            return nil
        }
        
        // 匹配任何 mysql 相关的 PATH 配置
        // 例如: "export PATH="/opt/homebrew/opt/tifa-mysql@8.0/bin:$PATH""
        // 或者: "export PATH="/opt/homebrew/opt/mysql/bin:$PATH""
        let patterns = [
            #"export\s+PATH="/opt/homebrew/opt/(tifa-mysql@[\d.]+)/bin:\$PATH""#,
            #"export\s+PATH="/usr/local/opt/(mysql@[\d.]+)/bin:\$PATH""#,
            #"export\s+PATH="/opt/homebrew/opt/(mysql)/bin:\$PATH""#,
            #"export\s+PATH="/usr/local/opt/(mysql)/bin:\$PATH""#
        ]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let range = Range(match.range(at: 1), in: content) else {
                continue
            }
            return String(content[range])
        }
        
        return nil
    }
    
    /// 切换 PATH 到指定版本（永久生效）
    func switchPATH(to formula: String) async -> OperationResult {
        let binPath = "\(brewPrefix)/opt/\(formula)/bin"
        
        // 检查 zshrc 是否已有 tifa-mysql PATH 配置
        let zshrcPath = NSHomeDirectory() + "/.zshrc"
        var zshrcContent = ""
        if FileManager.default.fileExists(atPath: zshrcPath) {
            zshrcContent = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""
        }
        
        // 移除旧的 tifa-mysql PATH 配置
        let oldPattern = #"export\s+PATH="/opt/homebrew/opt/tifa-mysql@[\d.]+/bin:\$PATH""#
        let newZshrc = zshrcContent.replacingOccurrences(of: oldPattern, with: "", options: .regularExpression)
        
        // 添加新的 PATH 配置
        let newExport = "\nexport PATH=\"\(binPath):$PATH\""
        let finalZshrc = newZshrc.trimmingCharacters(in: .whitespacesAndNewlines) + newExport
        
        do {
            try finalZshrc.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
            
            // 更新当前进程的 PATH（仅影响当前会话）
            if var currentPath = ProcessInfo.processInfo.environment["PATH"] {
                // 移除旧路径
                for ver in Self.availableVersions {
                    let oldBinPath = "\(brewPrefix)/opt/\(ver.formula)/bin"
                    currentPath = currentPath.replacingOccurrences(of: "\(oldBinPath):", with: "")
                    currentPath = currentPath.replacingOccurrences(of: ":\(oldBinPath)", with: "")
                }
                // 添加新路径到最前面
                setenv("PATH", "\(binPath):\(currentPath)", 1)
            }
            
            // 更新 activeVersion
            activeVersion = formula
            
            return .success("PATH 已切换到 \(formula)，请重启终端使配置生效")
        } catch {
            return .failure("写入 .zshrc 失败: \(error.localizedDescription)")
        }
    }
    
    /// 检查 MySQL 是否已安装
    func checkMySQLAvailable() -> Bool {
        return installedVersions.contains { $0.installed }
    }
    
    /// 检查 MySQL 是否正在运行
    func isMySQLRunning() async -> Bool {
        return installedVersions.contains { $0.pid != nil }
    }
    
    /// 获取 MySQL 版本
    func getMySQLVersion() async -> String {
        guard let runningVer = installedVersions.first(where: { $0.pid != nil }) else {
            return "未运行"
        }
        let mysqlCmd = getClientCommand(for: runningVer.formula)
        let result = await executeCommand(executable: mysqlCmd, arguments: ["--version"])
        if case .success(let output) = result {
            // 解析 "mysql  Ver 8.0.35 for macos14.0 on arm64 ..."
            let versionPattern = #"Ver\s+([\d.]+)"#
            if let regex = try? NSRegularExpression(pattern: versionPattern),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) {
                return String(output[range])
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    /// 获取 MySQL 服务名称
    func getServiceName() -> String {
        return runningServiceName ?? "未安装"
    }
    
    /// 获取当前运行的 MySQL 端口
    func getRunningPort() -> Int {
        return installedVersions.first(where: { $0.pid != nil })?.port ?? 3306
    }
    
    // MARK: - 服务控制（带流式输出）

    /// 启动 MySQL（带实时日志输出）
    func startMySQLWithProgress(formula: String? = nil, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        // 优先选择激活的版本（PATH 中设置的版本），其次选择第一个已安装的版本
        let targetFormula = formula ?? 
            installedVersions.first(where: { $0.activated })?.formula ??
            installedVersions.first(where: { $0.installed })?.formula
        
        guard let serviceName = targetFormula else {
            onOutput("❌ 未检测到 MySQL，请先通过 Homebrew 安装")
            return .failure("未检测到 MySQL，请先通过 Homebrew 安装")
        }

        onOutput("正在启动 \(serviceName)...")

        // 先停止其他版本
        for ver in installedVersions where ver.installed && ver.formula != serviceName {
            onOutput("停止其他 MySQL 版本: \(ver.formula)...")
            _ = await executeCommandWithProgressOnly(executable: brewPath, arguments: ["services", "stop", ver.formula])
        }

        return await executeCommandStreaming(executable: brewPath, arguments: ["services", "start", serviceName], onOutput: onOutput)
    }

    /// 停止 MySQL（带实时日志输出）
    func stopMySQLWithProgress(formula: String? = nil, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let targetFormula = formula ?? runningServiceName
        guard let serviceName = targetFormula else {
            onOutput("❌ 未检测到 MySQL")
            return .failure("未检测到 MySQL")
        }

        onOutput("正在停止 \(serviceName)...")
        return await executeCommandStreaming(executable: brewPath, arguments: ["services", "stop", serviceName], onOutput: onOutput)
    }

    /// 重启 MySQL（带实时日志输出）
    func restartMySQLWithProgress(formula: String? = nil, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        // 优先选择激活的版本（PATH 中设置的版本），其次选择正在运行的版本
        let targetFormula = formula ?? 
            installedVersions.first(where: { $0.activated })?.formula ??
            runningServiceName
        
        guard let serviceName = targetFormula else {
            onOutput("❌ 未检测到 MySQL")
            return .failure("未检测到 MySQL")
        }

        onOutput("正在重启 \(serviceName)...")
        return await executeCommandStreaming(executable: brewPath, arguments: ["services", "restart", serviceName], onOutput: onOutput)
    }

    /// 启动指定版本的 MySQL（同一时间只能运行一个版本）
    func startMySQL(formula: String? = nil) async -> OperationResult {
        let targetFormula = formula ?? 
            installedVersions.first(where: { $0.activated })?.formula ??
            installedVersions.first(where: { $0.installed })?.formula
        guard let serviceName = targetFormula else {
            return .failure("未检测到 MySQL，请先通过 Homebrew 安装")
        }
        
        // 先停止其他版本
        for ver in installedVersions where ver.installed && ver.formula != serviceName {
            _ = await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", ver.formula])
        }
        
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "start", serviceName])
    }
    
    /// 停止指定版本的 MySQL
    func stopMySQL(formula: String? = nil) async -> OperationResult {
        let targetFormula = formula ?? runningServiceName
        guard let serviceName = targetFormula else {
            return .failure("未检测到 MySQL")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", serviceName])
    }
    
    /// 重启指定版本的 MySQL
    func restartMySQL(formula: String? = nil) async -> OperationResult {
        let targetFormula = formula ?? 
            installedVersions.first(where: { $0.activated })?.formula ??
            runningServiceName
        guard let serviceName = targetFormula else {
            return .failure("未检测到 MySQL")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "restart", serviceName])
    }
    
    // MARK: - 数据库管理
    
    /// 获取数据库列表
    func listDatabases() async -> [MySQLDatabase] {
        let result = await executeMySQLCommand(sql: "SHOW DATABASES")
        switch result {
        case .success(let output):
            return parseDatabases(output: output)
        case .failure:
            return []
        }
    }
    
    /// 创建数据库
    func createDatabase(name: String, charset: String = "utf8mb4") async -> OperationResult {
        let sql = "CREATE DATABASE `\(name)` CHARACTER SET \(charset) COLLATE \(charset)_unicode_ci"
        return await executeMySQLCommandWithProgress(sql: sql)
    }
    
    /// 删除数据库
    func dropDatabase(name: String) async -> OperationResult {
        let sql = "DROP DATABASE `\(name)`"
        return await executeMySQLCommandWithProgress(sql: sql)
    }
    
    /// 获取数据库表信息
    func getTableInfo(database: String) async -> String {
        let sql = "SELECT TABLE_NAME, ENGINE, TABLE_ROWS, DATA_LENGTH, CREATE_TIME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '\(database)' ORDER BY TABLE_NAME"
        let result = await executeMySQLCommand(sql: sql, database: database)
        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            return "获取失败: \(error)"
        }
    }
    
    // MARK: - 配置信息
    
    /// 获取当前运行版本的 formula
    private var runningFormula: String {
        installedVersions.first(where: { $0.pid != nil })?.formula ?? "tifa-mysql@8.0"
    }
    
    /// 获取 MySQL 配置文件路径
    func getConfigFilePath(for formula: String) -> String {
        return "\(brewPrefix)/etc/my.cnf.d/\(formula).cnf"
    }
    
    /// 向后兼容：获取当前运行版本的配置文件路径
    func getConfigFilePath() -> String {
        return getConfigFilePath(for: runningFormula)
    }
    
    /// 配置文件是否存在
    func configFileExists(for formula: String) -> Bool {
        let path = getConfigFilePath(for: formula)
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// 向后兼容：检查当前运行版本的配置文件
    func configFileExists() -> Bool {
        return configFileExists(for: runningFormula)
    }
    
    /// 读取 MySQL 配置文件内容
    func readConfigFile(for formula: String) -> String {
        let path = getConfigFilePath(for: formula)
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    /// 向后兼容：读取当前运行版本的配置文件
    func readConfigFile() -> String {
        return readConfigFile(for: runningFormula)
    }
    
    /// 保存配置文件内容
    func saveConfigFile(content: String, for formula: String) -> OperationResult {
        let path = getConfigFilePath(for: formula)
        do {
            // 确保目录存在
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("配置文件已保存到 \(path)")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 向后兼容：保存到当前运行版本
    func saveConfigFile(content: String) -> OperationResult {
        return saveConfigFile(content: content, for: runningFormula)
    }
    
    /// 生成默认 my.cnf 内容（tifa-mysql 版本）
    func generateDefaultConfig(for formula: String) -> String {
        let versionInfo = Self.availableVersions.first { $0.formula == formula }
        let port = versionInfo?.port ?? 3306
        let dataDir = versionInfo?.dataDir ?? "mysql"
        let fullDataDir = "\(brewPrefix)/var/\(dataDir)"
        
        return """
        # MySQL 配置文件
        # \(formula) - 由 Tifa 生成
        
        [client]
        port = \(port)
        default-character-set = utf8mb4
        
        [mysqld]
        port = \(port)
        character-set-server = utf8mb4
        collation-server = utf8mb4_unicode_ci
        
        # 数据存储
        datadir = \(fullDataDir)
        
        # 连接
        max_connections = 200
        max_connect_errors = 100
        
        # 缓冲区
        innodb_buffer_pool_size = 256M
        innodb_log_file_size = 48M
        
        # 日志
        log_error = \(fullDataDir)/mysql.err
        slow_query_log = 0
        slow_query_log_file = \(fullDataDir)/slow.log
        long_query_time = 2
        
        # 临时表
        tmp_table_size = 64M
        max_heap_table_size = 64M
        """
    }
    
    /// 向后兼容：生成当前运行版本的默认配置
    func generateDefaultConfig() -> String {
        return generateDefaultConfig(for: runningFormula)
    }
    
    /// 获取 MySQL 端口
    func getMySQLPort() async -> Int {
        return getRunningPort()
    }
    
    /// 获取 MySQL 数据目录
    func getDataDir() async -> String {
        if let running = installedVersions.first(where: { $0.pid != nil }) {
            let dataDir = running.dataDir
            if !dataDir.isEmpty {
                return "\(brewPrefix)/var/\(dataDir)"
            }
        }
        return "\(brewPrefix)/var/mysql"
    }
    
    /// 获取 MySQL 运行状态变量
    func getStatusVariables() async -> [String: String] {
        let result = await executeMySQLCommand(sql: "SHOW STATUS")
        switch result {
        case .success(let output):
            var status: [String: String] = [:]
            for line in output.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "\t").filter { !$0.isEmpty }
                if parts.count >= 2 {
                    status[parts[0]] = parts[1]
                }
            }
            return status
        case .failure:
            return [:]
        }
    }
    
    // MARK: - 私有方法
    
    private func updateLoadingState(message: String) {
        isLoading = true
        loadingMessage = message
    }
    
    /// 带超时的命令执行（默认 10 秒超时）
    private func executeCommand(executable: String, arguments: [String], timeoutSeconds: TimeInterval = 10) async -> OperationResult {
        let env = mysqlEnvironment
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = env
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                // 设置超时
                let timeoutWorkItem = DispatchWorkItem {
                    lock.lock()
                    defer { lock.unlock() }
                    if !hasResumed {
                        hasResumed = true
                        process.terminate()
                    }
                    lock.unlock()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutWorkItem.cancel()
                    
                    lock.lock()
                    guard !hasResumed else {
                        lock.unlock()
                        return
                    }
                    hasResumed = true
                    lock.unlock()
                    
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
                    lock.lock()
                    guard !hasResumed else {
                        lock.unlock()
                        return
                    }
                    hasResumed = true
                    lock.unlock()
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func executeCommand(executable: String, arguments: [String]) async -> OperationResult {
        return await executeCommand(executable: executable, arguments: arguments, timeoutSeconds: 30)
    }
    
    private func executeCommandWithProgress(executable: String, arguments: [String]) async -> OperationResult {
        updateLoadingState(message: "正在执行...")
        let env = mysqlEnvironment
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 仅执行命令不关心输出（用于内部停止其他服务）
    private func executeCommandWithProgressOnly(executable: String, arguments: [String]) async -> OperationResult {
        let env = mysqlEnvironment
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
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(""))
                    } else {
                        continuation.resume(returning: .failure("命令执行失败"))
                    }
                } catch {
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 流式执行命令，实时输出日志
    private func executeCommandStreaming(executable: String, arguments: [String], onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let env = mysqlEnvironment
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
                
                var collectedOutput = ""
                
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading
                
                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
                    collectedOutput += str
                    let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    for line in lines {
                        Task { @MainActor in onOutput(line) }
                    }
                }
                
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
                    collectedOutput += str
                    let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    for line in lines {
                        Task { @MainActor in onOutput(line) }
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    
                    // 读取残余数据
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    
                    if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        for line in stdout.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                            Task { @MainActor in onOutput(line) }
                        }
                    }
                    if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        for line in stderr.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                            Task { @MainActor in onOutput(line) }
                        }
                    }
                    
                    if process.terminationStatus == 0 {
                        Task { @MainActor in onOutput("✅ 操作完成") }
                        continuation.resume(returning: .success(collectedOutput))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        Task { @MainActor in onOutput("❌ 操作失败 (exit code \(process.terminationStatus))") }
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    Task { @MainActor in onOutput("❌ 无法执行命令: \(error.localizedDescription)") }
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 执行 MySQL 命令（使用运行中的版本）
    private func executeMySQLCommand(sql: String, database: String? = nil) async -> OperationResult {
        guard let runningVer = installedVersions.first(where: { $0.pid != nil }) else {
            return .failure("MySQL 未运行")
        }
        
        let mysqlCmd = getClientCommand(for: runningVer.formula)
        var args = ["-u", "root"]
        
        if let db = database {
            args += ["-D", db]
        }
        args += ["-e", sql]
        
        let result = await executeCommand(executable: mysqlCmd, arguments: args)
        
        // 清理 MySQL 的 tabular 输出（移除表格边框线）
        if case .success(let output) = result {
            let cleaned = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("+") && $0 != "" }
                .joined(separator: "\n")
            return .success(cleaned)
        }
        return result
    }
    
    /// 执行 MySQL 命令（带进度显示）
    func executeMySQLCommandWithProgress(sql: String, database: String? = nil) async -> OperationResult {
        guard let runningVer = installedVersions.first(where: { $0.pid != nil }) else {
            return .failure("MySQL 未运行")
        }
        
        let mysqlCmd = getClientCommand(for: runningVer.formula)
        var args = ["-u", "root"]
        
        if let db = database {
            args += ["-D", db]
        }
        args += ["-e", sql]
        
        return await executeCommandWithProgress(executable: mysqlCmd, arguments: args)
    }
    
    private func parseDatabases(output: String) -> [MySQLDatabase] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "Database" && !$0.hasPrefix("+") }
        
        return lines.map { name in
            MySQLDatabase(
                id: name,
                name: name,
                size: "",
                tableCount: 0,
                charset: ""
            )
        }
    }
}
