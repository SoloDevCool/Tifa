import Foundation

/// PostgreSQL 数据库信息模型
struct PostgresDatabase: Identifiable, Hashable {
    let id: String
    let name: String
    let owner: String
    let encoding: String
    let size: String
    let tableCount: Int
}

/// PostgreSQL 服务 - 管理 PostgreSQL
@MainActor
class PostgresService: ObservableObject {
    
    static let shared = PostgresService()
    
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var lastError: String?
    
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
    
    /// PostgreSQL 可执行文件路径
    private var pgBasePath: String {
        let paths = [
            "/opt/homebrew/opt/postgresql@16/bin",
            "/opt/homebrew/opt/postgresql@15/bin",
            "/opt/homebrew/opt/postgresql@14/bin",
            "/opt/homebrew/opt/postgresql@13/bin",
            "/opt/homebrew/opt/postgresql/bin",
            "/opt/homebrew/opt/libpq/bin",
            "/usr/local/opt/postgresql@16/bin",
            "/usr/local/opt/postgresql@15/bin",
            "/usr/local/opt/postgresql@14/bin",
            "/usr/local/opt/postgresql/bin",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: "\(path)/psql") {
                return path
            }
        }
        return ""
    }
    
    /// PostgreSQL 服务名称（brew services 使用的名称）
    private var pgServiceName: String? {
        let names = ["postgresql@16", "postgresql@15", "postgresql@14", "postgresql@13", "postgresql", "postgis"]
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        
        for name in names {
            if FileManager.default.fileExists(atPath: "\(brewPrefix)/opt/\(name)") {
                return name
            }
        }
        return nil
    }
    
    /// PostgreSQL 数据目录
    private var pgDataDir: String {
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        return "\(brewPrefix)/var/postgresql@16"
    }
    
    /// 构建 PostgreSQL 命令执行环境
    private var pgEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        let extraPaths = "\(pgBasePath):\(brewPrefix)/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        env["HOME"] = NSHomeDirectory()
        env["PGDATA"] = pgDataDir
        return env
    }
    
    // MARK: - 安装
    
    /// 可安装的 PostgreSQL 版本
    static let availableVersions = [
        (name: "PostgreSQL 17", formula: "postgresql@17"),
        (name: "PostgreSQL 16", formula: "postgresql@16"),
        (name: "PostgreSQL 15", formula: "postgresql@15"),
        (name: "PostgreSQL 14", formula: "postgresql@14"),
        (name: "PostgreSQL 13", formula: "postgresql@13"),
    ]
    
    /// 使用 Homebrew 安装 PostgreSQL（带实时输出）
    func installPostgres(formula: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "\(brewPath) install \(formula)"
        
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
                    // 设置超时 1200 秒（20 分钟）
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    var timedOut = false
                    timer.schedule(deadline: .now() + 1200)
                    timer.setEventHandler { timedOut = true; process.terminate() }
                    timer.resume()
                    
                    process.waitUntilExit()
                    timer.cancel()
                    
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    
                    // 读取剩余数据
                    let remainingStdout = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }
                    
                    if timedOut {
                        continuation.resume(returning: .failure("安装超时（20 分钟），请检查网络连接后重试"))
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
    
    // MARK: - 修复安装
    
    /// 清理 brew 下载锁文件和缓存，用于修复安装中断
    func cleanupBrewLocks() async -> OperationResult {
        let script = """
        # 清理未完成的下载文件
        find ~/Library/Caches/Homebrew/downloads -name "*.incomplete" -delete 2>/dev/null
        # 清理 brew 锁文件
        find ~/Library/Caches/Homebrew -name "*.lock" -delete 2>/dev/null
        # 清理 Homebrew 临时文件
        rm -rf ~/Library/Caches/Homebrew/.cache_cleaned 2>/dev/null
        echo "✅ 锁文件和缓存已清理"
        """
        
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
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout + stderr))
                    } else {
                        continuation.resume(returning: .failure(stderr.isEmpty ? "清理失败" : stderr))
                    }
                } catch {
                    continuation.resume(returning: .failure("无法执行清理: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    // MARK: - 检查可用性
    
    /// 检查 PostgreSQL 是否已安装
    func checkPostgresAvailable() -> Bool {
        return !pgBasePath.isEmpty
    }
    
    /// 检查 PostgreSQL 是否正在运行
    func isPostgresRunning() async -> Bool {
        guard let serviceName = pgServiceName else { return false }
        let result = await executeCommand(executable: brewPath, arguments: ["services", "list"])
        if case .success(let output) = result {
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(serviceName) && trimmed.contains("started") {
                    return true
                }
            }
        }
        return false
    }
    
    /// 获取 PostgreSQL 版本
    func getPostgresVersion() async -> String {
        if pgBasePath.isEmpty {
            return "未安装"
        }
        let result = await executeCommand(executable: "\(pgBasePath)/postgres", arguments: ["--version"])
        if case .success(let output) = result {
            let versionPattern = #"postgres\s*\((PostgreSQL)?\s*([\d.]+)"#
            if let regex = try? NSRegularExpression(pattern: versionPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                let lastRange = match.range(at: match.numberOfRanges - 1)
                if let range = Range(lastRange, in: output) {
                    return String(output[range])
                }
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    /// 获取 PostgreSQL 服务名称
    func getServiceName() -> String {
        return pgServiceName ?? "未安装"
    }
    
    // MARK: - 服务控制
    
    /// 启动 PostgreSQL
    func startPostgres() async -> OperationResult {
        guard let serviceName = pgServiceName else {
            return .failure("未检测到 PostgreSQL，请先通过 Homebrew 安装")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "start", serviceName])
    }
    
    /// 停止 PostgreSQL
    func stopPostgres() async -> OperationResult {
        guard let serviceName = pgServiceName else {
            return .failure("未检测到 PostgreSQL")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", serviceName])
    }
    
    /// 重启 PostgreSQL
    func restartPostgres() async -> OperationResult {
        guard let serviceName = pgServiceName else {
            return .failure("未检测到 PostgreSQL")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "restart", serviceName])
    }
    
    // MARK: - 数据库管理
    
    /// 获取数据库列表
    func listDatabases() async -> [PostgresDatabase] {
        let sql = "SELECT datname, pg_catalog.pg_get_userbyid(datdba) as owner, pg_encoding_to_char(encoding) as enc, pg_database_size(datname) as size FROM pg_database WHERE datistemplate = false ORDER BY datname"
        let result = await executePGCommand(sql: sql)
        switch result {
        case .success(let output):
            return parseDatabases(output: output)
        case .failure:
            return []
        }
    }
    
    /// 创建数据库
    func createDatabase(name: String, encoding: String = "UTF8", owner: String = "") async -> OperationResult {
        var sql = "CREATE DATABASE \"\(name)\" ENCODING '\(encoding)'"
        if !owner.isEmpty {
            sql += " OWNER \"\(owner)\""
        }
        return await executePGCommandWithProgress(sql: sql)
    }
    
    /// 删除数据库
    func dropDatabase(name: String) async -> OperationResult {
        let sql = "DROP DATABASE \"\(name)\""
        return await executePGCommandWithProgress(sql: sql)
    }
    
    /// 获取数据库表信息
    func getTableInfo(database: String) async -> String {
        let sql = "SELECT schemaname, tablename, tableowner FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') ORDER BY schemaname, tablename"
        let result = await executePGCommand(sql: sql, database: database)
        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            return "获取失败: \(error)"
        }
    }
    
    /// 获取数据库大小
    func getDatabaseSize(database: String) async -> String {
        let sql = "SELECT pg_size_pretty(pg_database_size('\"\(database)\"'))"
        let result = await executePGCommand(sql: sql, database: database)
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    // MARK: - 配置信息
    
    /// Homebrew 前缀路径
    private var brewPrefix: String {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }
    
    /// 获取 PostgreSQL 配置文件路径
    func getConfigFilePath() -> String {
        let brewPrefix = self.brewPrefix
        return "\(brewPrefix)/var/postgresql@16/postgresql.conf"
    }
    
    /// 获取 hba 配置文件路径
    func getHBAFilePath() -> String {
        let brewPrefix = self.brewPrefix
        return "\(brewPrefix)/var/postgresql@16/pg_hba.conf"
    }
    
    /// 配置文件是否存在
    func configFileExists() -> Bool {
        let path = getConfigFilePath()
        return FileManager.default.fileExists(atPath: path)
    }
    
    /// 读取 PostgreSQL 配置文件内容
    func readConfigFile() -> String {
        let path = getConfigFilePath()
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    /// 保存配置文件内容
    func saveConfigFile(content: String) -> OperationResult {
        let path = getConfigFilePath()
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("配置文件已保存到 \(path)")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 读取 hba.conf
    func readHBAFile() -> String {
        let path = getHBAFilePath()
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    /// 保存 hba.conf
    func saveHBAFile(content: String) -> OperationResult {
        let path = getHBAFilePath()
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("pg_hba.conf 已保存")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 获取 PostgreSQL 端口
    func getPostgresPort() async -> Int {
        let result = await executePGCommand(sql: "SHOW port")
        if case .success(let output) = result {
            let port = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(port) ?? 5432
        }
        return 5432
    }
    
    /// 获取数据目录
    func getDataDir() async -> String {
        let result = await executePGCommand(sql: "SHOW data_directory")
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return pgDataDir
    }
    
    /// 获取 PostgreSQL 运行状态
    func getStatusVariables() async -> [String: String] {
        let result = await executePGCommand(sql: "SELECT name, setting FROM pg_settings WHERE name IN ('max_connections', 'shared_buffers', 'effective_cache_size', 'work_mem', 'maintenance_work_mem', 'wal_level', 'random_page_cost', 'effective_io_concurrency') ORDER BY name")
        switch result {
        case .success(let output):
            var status: [String: String] = [:]
            for line in output.components(separatedBy: .newlines) {
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    status[parts[0]] = parts[1]
                }
            }
            return status
        case .failure:
            return [:]
        }
    }
    
    /// 获取活跃连接数
    func getActiveConnections() async -> Int {
        let result = await executePGCommand(sql: "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")
        if case .success(let output) = result {
            return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }
    
    /// 获取数据库总数
    func getDatabaseCount() async -> Int {
        let result = await executePGCommand(sql: "SELECT count(*) FROM pg_database WHERE datistemplate = false")
        if case .success(let output) = result {
            return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }
    
    // MARK: - 维护操作
    
    /// 优化数据库
    func vacuumDatabase(database: String) async -> OperationResult {
        let sql = "VACUUM ANALYZE"
        return await executePGCommandWithProgress(sql: sql, database: database)
    }
    
    /// 查看活跃连接列表
    func getActiveProcesses() async -> String {
        let sql = "SELECT pid, usename, datname, state, query FROM pg_stat_activity WHERE pid <> pg_backend_pid() ORDER BY pid"
        let result = await executePGCommand(sql: sql)
        if case .success(let output) = result {
            return output
        }
        return "获取失败"
    }
    
    /// 获取数据库大小列表
    func getDatabaseSizes() async -> String {
        let sql = "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false ORDER BY pg_database_size(datname) DESC"
        let result = await executePGCommand(sql: sql)
        if case .success(let output) = result {
            return output
        }
        return "获取失败"
    }
    
    // MARK: - 私有方法
    
    private func updateLoadingState(message: String) {
        isLoading = true
        loadingMessage = message
    }
    
    private func executeCommand(executable: String, arguments: [String]) async -> OperationResult {
        let env = pgEnvironment
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
        let env = pgEnvironment
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
    
    /// 执行 psql 命令
    private func executePGCommand(sql: String, database: String? = nil) async -> OperationResult {
        var args = ["-U", NSUserName(), "-t", "-A", "-F", "|"]
        if let db = database {
            args += ["-d", db]
        }
        args += ["-c", sql]
        
        if pgBasePath.isEmpty {
            return .failure("PostgreSQL 未安装")
        }
        
        let result = await executeCommand(executable: "\(pgBasePath)/psql", arguments: args)
        if case .success(let output) = result {
            let cleaned = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return .success(cleaned)
        }
        return result
    }
    
    func executePGCommandWithProgress(sql: String, database: String? = nil) async -> OperationResult {
        var args = ["-U", NSUserName()]
        if let db = database {
            args += ["-d", db]
        }
        args += ["-c", sql]
        
        if pgBasePath.isEmpty {
            return .failure("PostgreSQL 未安装")
        }
        
        return await executeCommandWithProgress(executable: "\(pgBasePath)/psql", arguments: args)
    }
    
    private func parseDatabases(output: String) -> [PostgresDatabase] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return lines.compactMap { line -> PostgresDatabase? in
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            
            let name = parts[0]
            let owner = parts.count >= 2 ? parts[1] : ""
            let encoding = parts.count >= 3 ? parts[2] : ""
            
            guard !name.isEmpty else { return nil }
            
            // 尝试解析大小
            let size = parts.count >= 4 ? parts[3] : ""
            
            return PostgresDatabase(
                id: name,
                name: name,
                owner: owner,
                encoding: encoding,
                size: size,
                tableCount: 0
            )
        }
    }
}
