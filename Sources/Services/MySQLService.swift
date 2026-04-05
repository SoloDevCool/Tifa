import Foundation

/// MySQL 数据库信息模型
struct MySQLDatabase: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String
    let tableCount: Int
    let charset: String
}

/// MySQL 安装版本信息
struct MySQLVersionInfo: Identifiable, Hashable {
    let id: String          // formula 名称，如 "mysql@8.0"
    let displayName: String  // 显示名，如 "MySQL 8.0"
    let formula: String      // brew formula，如 "mysql@8.0"
    let installed: Bool
    let linked: Bool         // 当前是否为活跃版本
}

/// MySQL 服务 - 管理 MySQL/MariaDB
@MainActor
class MySQLService: ObservableObject {
    
    static let shared = MySQLService()
    
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var lastError: String?
    
    /// 所有可安装的 MySQL 版本
    static let availableVersions: [(name: String, formula: String)] = [
        ("MySQL 9.x（最新）", "mysql"),
        ("MySQL 8.4", "mysql@8.4"),
        ("MySQL 8.0", "mysql@8.0"),
        ("MySQL 5.7", "mysql@5.7"),
        ("MariaDB", "mariadb"),
    ]
    
    /// 当前活跃版本（linked）
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
    
    /// MySQL 可执行文件路径
    private var mysqlBasePath: String {
        // 常见的安装路径
        let paths = [
            "/opt/homebrew/opt/mysql/bin",
            "/opt/homebrew/opt/mariadb/bin",
            "/opt/homebrew/opt/mysql@5.7/bin",
            "/opt/homebrew/opt/mysql@8.0/bin",
            "/opt/homebrew/opt/mysql@8.4/bin",
            "/usr/local/opt/mysql/bin",
            "/usr/local/opt/mariadb/bin",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: "\(path)/mysql") {
                return path
            }
        }
        return ""
    }
    
    /// MySQL 服务名称（brew services 使用的名称）
    private var mysqlServiceName: String? {
        // 优先使用当前活跃版本
        if !activeVersion.isEmpty {
            let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
            if FileManager.default.fileExists(atPath: "\(brewPrefix)/opt/\(activeVersion)") {
                return activeVersion
            }
        }
        // 回退到检测
        let names = ["mysql", "mariadb", "mysql@5.7", "mysql@8.0", "mysql@8.4"]
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        for name in names {
            if FileManager.default.fileExists(atPath: "\(brewPrefix)/opt/\(name)") {
                return name
            }
        }
        return nil
    }
    
    /// MySQL 数据目录
    private var mysqlDataDir: String {
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        return "\(brewPrefix)/var/mysql"
    }
    
    /// 构建 MySQL 命令执行环境
    private var mysqlEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        let extraPaths = "\(mysqlBasePath):\(brewPrefix)/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        env["HOME"] = NSHomeDirectory()
        return env
    }
    
    // MARK: - 版本管理
    
    /// 检测所有已安装的 MySQL 版本及活跃版本
    func detectInstalledVersions() async {
        let brew = brewPath
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        
        // 通过 brew list 获取已安装的 formula
        let listResult = await executeCommand(executable: brew, arguments: ["list", "--formula"])
        let installedFormulas: Set<String>
        if case .success(let output) = listResult {
            installedFormulas = Set(output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        } else {
            installedFormulas = []
        }
        
        // 通过检查 bin/mysql 的 symlink 目标判断活跃版本
        let mysqlBinPath = "\(brewPrefix)/bin/mysql"
        var linkedFormula = ""
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: mysqlBinPath) {
            // dest 类似 "../Cellar/mysql@8.0/8.0.45_1/bin/mysql"
            // 或 "../Cellar/mysql/9.6.0/bin/mysql"
            for ver in Self.availableVersions {
                if dest.contains("/\(ver.formula)/") {
                    linkedFormula = ver.formula
                    break
                }
            }
        }
        
        // 如果 bin/mysql 不是 symlink 或无匹配，检查 opt 目录下哪个版本有 link
        if linkedFormula.isEmpty {
            for ver in Self.availableVersions {
                let optPath = "\(brewPrefix)/opt/\(ver.formula)"
                let binPath = "\(optPath)/bin/mysql"
                // 检查 opt/{formula} 存在且 bin/mysql 可执行（说明该 keg 被选中）
                if installedFormulas.contains(ver.formula) && FileManager.default.isExecutableFile(atPath: binPath) {
                    linkedFormula = ver.formula
                    break
                }
            }
        }
        
        var versions: [MySQLVersionInfo] = []
        for ver in Self.availableVersions {
            let formula = ver.formula
            let installed = installedFormulas.contains(formula)
            let linked = (formula == linkedFormula)
            
            versions.append(MySQLVersionInfo(
                id: formula,
                displayName: ver.name,
                formula: formula,
                installed: installed,
                linked: linked
            ))
        }
        
        installedVersions = versions
        activeVersion = linkedFormula
    }
    
    /// 安装指定版本
    func installVersion(formula: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let brew = brewPath
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: brew)
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
                    
                    if process.terminationStatus == 0 {
                        Task { @MainActor in
                            appendOutput("\n✅ \(formula) 安装成功")
                            await self.detectInstalledVersions()
                        }
                        continuation.resume(returning: .success(stdout))
                    } else {
                        Task { @MainActor in appendOutput("\n❌ 安装失败") }
                        let error = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(error.isEmpty ? "安装失败 (exit code \(process.terminationStatus))" : error))
                    }
                } catch {
                    Task { @MainActor in appendOutput("\n❌ 无法启动 brew: \(error.localizedDescription)") }
                    continuation.resume(returning: .failure("无法启动 brew: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    /// 切换活跃版本（unlink 当前 + link 新版本）
    func switchVersion(to formula: String) async -> OperationResult {
        // 先停止当前服务
        if let current = mysqlServiceName {
            _ = await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", current])
        }
        
        // unlink 所有已安装的 MySQL 版本
        for ver in installedVersions where ver.installed {
            _ = await executeCommand(executable: brewPath, arguments: ["unlink", ver.formula])
        }
        
        // link 新版本
        let result = await executeCommandWithProgress(executable: brewPath, arguments: ["link", formula, "--force", "--overwrite"])
        
        if case .success = result {
            await detectInstalledVersions()
            return .success("已切换到 \(formula)")
        }
        return result
    }
    
    /// 卸载指定版本
    func uninstallVersion(formula: String) async -> OperationResult {
        // 先停止服务（如果是当前版本）
        if formula == activeVersion, let serviceName = mysqlServiceName {
            _ = await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", serviceName])
            // unlink
            _ = await executeCommand(executable: brewPath, arguments: ["unlink", formula])
        }
        
        let result = await executeCommandWithProgress(executable: brewPath, arguments: ["uninstall", formula])
        
        if case .success = result {
            await detectInstalledVersions()
            return .success("\(formula) 已卸载")
        }
        return result
    }
    
    // MARK: - 检查可用性
    
    /// 检查 MySQL 是否已安装
    func checkMySQLAvailable() -> Bool {
        return !mysqlBasePath.isEmpty
    }
    
    /// 检查 MySQL 是否正在运行
    func isMySQLRunning() async -> Bool {
        guard let serviceName = mysqlServiceName else { return false }
        let brewPath = self.brewPath
        let result = await executeCommand(executable: brewPath, arguments: ["services", "list"])
        if case .success(let output) = result {
            // 匹配如 "mysql@8.0 started" 或 "mysql started"
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(serviceName) && trimmed.contains("started") {
                    return true
                }
            }
        }
        return false
    }
    
    /// 获取 MySQL 版本
    func getMySQLVersion() async -> String {
        if mysqlBasePath.isEmpty {
            return "未安装"
        }
        let result = await executeCommand(executable: "\(mysqlBasePath)/mysql", arguments: ["--version"])
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
        return mysqlServiceName ?? "未安装"
    }
    
    // MARK: - 服务控制
    
    /// 启动 MySQL
    func startMySQL() async -> OperationResult {
        guard let serviceName = mysqlServiceName else {
            return .failure("未检测到 MySQL，请先通过 Homebrew 安装")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "start", serviceName])
    }
    
    /// 停止 MySQL
    func stopMySQL() async -> OperationResult {
        guard let serviceName = mysqlServiceName else {
            return .failure("未检测到 MySQL")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", serviceName])
    }
    
    /// 重启 MySQL
    func restartMySQL() async -> OperationResult {
        guard let serviceName = mysqlServiceName else {
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
    
    /// Homebrew 前缀路径
    private var brewPrefix: String {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }
    
    /// 获取 MySQL 配置文件路径（无论文件是否存在）
    func getConfigFilePath() -> String {
        return "\(brewPrefix)/etc/my.cnf"
    }
    
    /// 配置文件是否存在
    func configFileExists() -> Bool {
        let path = getConfigFilePath()
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// 读取 MySQL 配置文件内容
    func readConfigFile() -> String {
        let path = getConfigFilePath()
        guard path != "未找到配置文件",
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    /// 保存配置文件内容
    func saveConfigFile(content: String) -> OperationResult {
        let path = getConfigFilePath()
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
    
    /// 生成默认 my.cnf 内容
    func generateDefaultConfig() -> String {
        let prefix = brewPrefix
        return """
        # MySQL 配置文件
        # 由 Tifa 生成
        
        [client]
        port = 3306
        default-character-set = utf8mb4
        
        [mysqld]
        port = 3306
        character-set-server = utf8mb4
        collation-server = utf8mb4_unicode_ci
        
        # 数据存储
        datadir = \(prefix)/var/mysql
        socket = /tmp/mysql.sock
        
        # 连接
        max_connections = 200
        max_connect_errors = 100
        
        # 缓冲区
        innodb_buffer_pool_size = 256M
        innodb_log_file_size = 48M
        
        # 日志
        log_error = \(prefix)/var/mysql/mysql.err
        slow_query_log = 0
        slow_query_log_file = \(prefix)/var/mysql/slow.log
        long_query_time = 2
        
        # 临时表
        tmp_table_size = 64M
        max_heap_table_size = 64M
        """
    }
    
    /// 获取 MySQL 端口
    func getMySQLPort() async -> Int {
        let result = await executeMySQLCommand(sql: "SHOW VARIABLES LIKE 'port'")
        if case .success(let output) = result {
            // 输出格式: port\t3306
            let parts = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if parts.count >= 2, let port = Int(parts[1]) {
                return port
            }
        }
        return 3306
    }
    
    /// 获取 MySQL 数据目录
    func getDataDir() async -> String {
        let result = await executeMySQLCommand(sql: "SHOW VARIABLES LIKE 'datadir'")
        if case .success(let output) = result {
            let parts = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if parts.count >= 2 {
                return parts[1]
            }
        }
        return mysqlDataDir
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
    
    private func executeCommand(executable: String, arguments: [String]) async -> OperationResult {
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
    
    private func executeMySQLCommand(sql: String, database: String? = nil) async -> OperationResult {
        var args = ["-u", "root"]
        if let db = database {
            args += ["-D", db]
        }
        args += ["-e", sql]
        
        if mysqlBasePath.isEmpty {
            return .failure("MySQL 未安装")
        }
        
        let result = await executeCommand(executable: "\(mysqlBasePath)/mysql", arguments: args)
        
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
    
    func executeMySQLCommandWithProgress(sql: String, database: String? = nil) async -> OperationResult {
        var args = ["-u", "root"]
        if let db = database {
            args += ["-D", db]
        }
        args += ["-e", sql]
        
        if mysqlBasePath.isEmpty {
            return .failure("MySQL 未安装")
        }
        
        return await executeCommandWithProgress(executable: "\(mysqlBasePath)/mysql", arguments: args)
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
