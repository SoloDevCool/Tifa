import Foundation

/// MongoDB 数据库信息模型
struct MongoDatabase: Identifiable, Hashable {
    let id: String
    let name: String
    let sizeOnDisk: String
    let empty: Bool
}

/// MongoDB 服务 - 通过 Homebrew 安装和管理 MongoDB
@MainActor
class MongoDbService: ObservableObject {
    
    static let shared = MongoDbService()
    
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
    
    /// Homebrew 前缀路径
    private var brewPrefix: String {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }
    
    /// mongosh 路径
    private var mongoshPath: String {
        let paths = [
            "\(brewPrefix)/opt/mongodb-community/bin/mongosh",
            "\(brewPrefix)/bin/mongosh",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return ""
    }
    
    /// mongod 路径
    private var mongodPath: String {
        let paths = [
            "\(brewPrefix)/opt/mongodb-community/bin/mongod",
            "\(brewPrefix)/bin/mongod",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return ""
    }
    
    /// MongoDB 服务名称（brew services 使用的名称）
    private var mongoServiceName: String? {
        let names = ["mongodb-community", "mongodb"]
        for name in names {
            if FileManager.default.fileExists(atPath: "\(brewPrefix)/opt/\(name)") {
                return name
            }
        }
        return nil
    }
    
    // MARK: - 安装
    
    static let availableVersions = [
        (name: "MongoDB Community（最新）", formula: "mongodb-community"),
    ]
    
    /// 使用 Homebrew 安装 MongoDB（带实时输出）
    func installMongoDb(formula: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let brew = brewPath
        
        // 安装前清理可能残留的 Homebrew 下载锁文件
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Homebrew/downloads")
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasSuffix(".incomplete") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        
        let script = "\(brew) tap mongodb/brew && \(brew) install \(formula)"
        
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
    
    /// 使用 Homebrew 卸载 MongoDB
    func uninstallMongoDb() async -> OperationResult {
        guard let serviceName = mongoServiceName else {
            return .failure("未检测到 MongoDB")
        }
        updateLoadingState(message: "正在卸载 MongoDB...")
        let result = await executeCommandWithProgress(executable: brewPath, arguments: ["uninstall", "--force", serviceName])
        if case .success = result {
            // 同时移除 tap
            _ = await executeCommandWithProgress(executable: brewPath, arguments: ["untap", "mongodb/brew"])
        }
        return result
    }
    
    // MARK: - 检查可用性
    
    func checkMongoDbAvailable() -> Bool {
        return !mongoshPath.isEmpty
    }
    
    func getServiceName() -> String {
        return mongoServiceName ?? "未安装"
    }
    
    func isMongoDbRunning() async -> Bool {
        guard let serviceName = mongoServiceName else { return false }
        let result = await executeBrewCommand(arguments: ["services", "list"])
        if case .success(let output) = result {
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(serviceName) && trimmed.contains("started") {
                    return true
                }
            }
        }
        return false
    }
    
    func getMongoDbVersion() async -> String {
        if mongoshPath.isEmpty { return "未安装" }
        let result = await executeCommand(executable: mongoshPath, arguments: ["--version"])
        if case .success(let output) = result {
            // mongosh 2.3.0
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    func getMongoDbServerVersion() async -> String {
        let result = await executeMongoShell(script: "db.version()")
        if case .success(let output) = result {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    // MARK: - 服务控制
    
    func startMongoDb() async -> OperationResult {
        guard let serviceName = mongoServiceName else {
            return .failure("未检测到 MongoDB，请先通过 Homebrew 安装")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "start", serviceName])
    }
    
    func stopMongoDb() async -> OperationResult {
        guard let serviceName = mongoServiceName else {
            return .failure("未检测到 MongoDB")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", serviceName])
    }
    
    func restartMongoDb() async -> OperationResult {
        guard let serviceName = mongoServiceName else {
            return .failure("未检测到 MongoDB")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "restart", serviceName])
    }
    
    // MARK: - 数据库管理
    
    func listDatabases() async -> [MongoDatabase] {
        let result = await executeMongoShell(script: "db.adminCommand('listDatabases').databases.map(d => ({name: d.name, sizeOnDisk: (d.sizeOnDisk / 1024 / 1024).toFixed(2) + ' MB', empty: d.empty}))")
        guard case .success(let output) = result else { return [] }
        return parseDatabases(output: output)
    }
    
    func createDatabase(name: String) async -> OperationResult {
        let script = "use \(sanitizeDbName(name)); db.createCollection('_init_'); db.dropCollection('_init_')"
        return await executeMongoShellWithProgress(script: script)
    }
    
    func dropDatabase(name: String) async -> OperationResult {
        let script = "db.getSiblingDB('\(sanitizeDbName(name))').dropDatabase()"
        return await executeMongoShellWithProgress(script: script)
    }
    
    func getCollectionInfo(database: String) async -> String {
        let script = "db.getSiblingDB('\(sanitizeDbName(database))').getCollectionNames().map(name => { const stats = db.getSiblingDB('\(sanitizeDbName(database))')[name].stats(); return { name: name, documents: stats.count, size: (stats.size / 1024).toFixed(2) + ' KB' }; })"
        let result = await executeMongoShell(script: script)
        if case .success(let output) = result {
            return output
        }
        return "获取失败"
    }
    
    /// 获取 MongoDB 服务器状态
    func getServerStatus() async -> [String: String] {
        let result = await executeMongoShell(script: """
        const s = db.serverStatus();
        const info = {
            version: s.version,
            uptime: (s.uptime / 3600).toFixed(1) + ' hours',
            connections: JSON.stringify(s.connections),
            memory: JSON.stringify(s.memory),
            globalLock: JSON.stringify(s.globalLock)
        };
        printjson(info);
        """)
        guard case .success(let output) = result else { return [:] }
        
        var info: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(":") && !trimmed.hasPrefix("{") && !trimmed.hasPrefix("}") {
                if let range = trimmed.firstIndex(of: ":") {
                    let key = trimmed[trimmed.startIndex..<range].trimmingCharacters(in: .whitespaces)
                    let value = trimmed[trimmed.index(after: range)...].trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty && !value.isEmpty {
                        info[String(key)] = String(value)
                    }
                }
            }
        }
        return info
    }
    
    /// 获取数据库统计信息
    func getDbStats(database: String) async -> String {
        let script = "printjson(db.getSiblingDB('\(sanitizeDbName(database))').stats())"
        let result = await executeMongoShell(script: script)
        if case .success(let output) = result {
            return output
        }
        return "获取失败"
    }
    
    // MARK: - 配置
    
    func getConfigFilePath() -> String {
        return "\(brewPrefix)/etc/mongod.conf"
    }
    
    func configFileExists() -> Bool {
        return FileManager.default.fileExists(atPath: getConfigFilePath())
    }
    
    func readConfigFile() -> String {
        guard let content = try? String(contentsOfFile: getConfigFilePath(), encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    func saveConfigFile(content: String) -> OperationResult {
        let path = getConfigFilePath()
        do {
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("配置文件已保存")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    func generateDefaultConfig() -> String {
        let prefix = brewPrefix
        return """
        # MongoDB 配置文件
        # 由 Tifa 生成
        
        systemLog:
          destination: file
          path: \(prefix)/var/log/mongodb/mongo.log
          logAppend: true
        
        storage:
          dbPath: \(prefix)/var/mongodb
          journal:
            enabled: true
        
        net:
          bindIp: 127.0.0.1
          port: 27017
        """
    }
    
    func getDataDir() -> String {
        return "\(brewPrefix)/var/mongodb"
    }
    
    func getLogDir() -> String {
        return "\(brewPrefix)/var/log/mongodb"
    }
    
    // MARK: - 私有方法
    
    private var mongoEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "\(brewPrefix)/opt/mongodb-community/bin:\(brewPrefix)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        env["HOME"] = NSHomeDirectory()
        return env
    }
    
    private func sanitizeDbName(_ name: String) -> String {
        // 移除特殊字符防止注入
        return name.components(separatedBy: CharacterSet(charactersIn: " \t\n\r/\\.'\"`;"))
            .joined()
    }
    
    private func updateLoadingState(message: String) {
        isLoading = true
        loadingMessage = message
    }
    
    /// 执行 mongosh 命令（eval 模式，返回输出）
    private func executeMongoShell(script: String) async -> OperationResult {
        guard !mongoshPath.isEmpty else {
            return .failure("MongoDB 未安装")
        }
        let env = mongoEnvironment
        let cliPath = mongoshPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = ["--quiet", "--eval", script]
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
    
    private func executeMongoShellWithProgress(script: String) async -> OperationResult {
        guard !mongoshPath.isEmpty else {
            return .failure("MongoDB 未安装")
        }
        updateLoadingState(message: "正在执行...")
        let env = mongoEnvironment
        let cliPath = mongoshPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = ["--quiet", "--eval", script]
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
                    
                    DispatchQueue.main.async { self?.isLoading = false }
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    DispatchQueue.main.async { self?.isLoading = false }
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func executeCommand(executable: String, arguments: [String]) async -> OperationResult {
        let env = mongoEnvironment
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
        let env = mongoEnvironment
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
                    
                    DispatchQueue.main.async { self?.isLoading = false }
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(stdout))
                    } else {
                        let errorMsg = stderr.isEmpty ? stdout : stderr
                        continuation.resume(returning: .failure(errorMsg.isEmpty ? "命令执行失败" : errorMsg))
                    }
                } catch {
                    DispatchQueue.main.async { self?.isLoading = false }
                    continuation.resume(returning: .failure("无法执行命令: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    private func executeBrewCommand(arguments: [String]) async -> OperationResult {
        let env = mongoEnvironment
        let brew = brewPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: brew)
                process.arguments = arguments
                process.environment = env
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: .success(output))
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
    }
    
    private func parseDatabases(output: String) -> [MongoDatabase] {
        // mongosh 输出格式: [ { name: 'admin', sizeOnDisk: '0.00 MB', empty: true }, ... ]
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 尝试解析 mongosh 的数组输出
        var databases: [MongoDatabase] = []
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.hasPrefix("]") && $0 != "," }
        
        for line in lines {
            // 提取 name, sizeOnDisk, empty
            let nameRegex = try? NSRegularExpression(pattern: #"name:\s*'([^']+)'"#)
            let sizeRegex = try? NSRegularExpression(pattern: #"sizeOnDisk:\s*'([^']+)'"#)
            let emptyRegex = try? NSRegularExpression(pattern: #"empty:\s*(true|false)"#)
            
            var name = ""
            var size = "0 MB"
            var empty = false
            
            if let match = nameRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                name = String(line[range])
            }
            if let match = sizeRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                size = String(line[range])
            }
            if let match = emptyRegex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                empty = String(line[range]) == "true"
            }
            
            if !name.isEmpty {
                databases.append(MongoDatabase(id: name, name: name, sizeOnDisk: size, empty: empty))
            }
        }
        
        return databases
    }
}
