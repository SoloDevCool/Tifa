import Foundation

/// Redis 键值对信息
struct RedisKeyInfo: Identifiable, Hashable {
    let id: String
    let key: String
    let type: String
    let ttl: Int
    let size: String
}

/// Redis 服务 - 管理 Redis
@MainActor
class RedisService: ObservableObject {
    
    static let shared = RedisService()
    
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
    
    /// redis-cli 路径
    private var redisCLIPath: String {
        let paths = [
            "\(brewPrefix)/opt/redis/bin/redis-cli",
            "\(brewPrefix)/bin/redis-cli",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return ""
    }
    
    /// Redis 服务名称
    private var redisServiceName: String? {
        if FileManager.default.fileExists(atPath: "\(brewPrefix)/opt/redis") {
            return "redis"
        }
        return nil
    }
    
    // MARK: - 安装
    
    static let availableVersions = [
        (name: "Redis（最新）", formula: "redis"),
    ]
    
    /// 使用 Homebrew 安装 Redis（带实时输出）
    func installRedis(formula: String, onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
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
    
    func checkRedisAvailable() -> Bool {
        return !redisCLIPath.isEmpty
    }
    
    func getServiceName() -> String {
        return redisServiceName ?? "未安装"
    }
    
    func isRedisRunning() async -> Bool {
        guard let serviceName = redisServiceName else { return false }
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
    
    func getRedisVersion() async -> String {
        if redisCLIPath.isEmpty { return "未安装" }
        let result = await executeRedisCommand(arguments: ["--version"])
        if case .success(let output) = result {
            // redis-cli 7.2.6
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }
    
    // MARK: - 服务控制
    
    func startRedis() async -> OperationResult {
        guard let serviceName = redisServiceName else {
            return .failure("未检测到 Redis，请先通过 Homebrew 安装")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "start", serviceName])
    }
    
    func stopRedis() async -> OperationResult {
        guard let serviceName = redisServiceName else {
            return .failure("未检测到 Redis")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "stop", serviceName])
    }
    
    func restartRedis() async -> OperationResult {
        guard let serviceName = redisServiceName else {
            return .failure("未检测到 Redis")
        }
        return await executeCommandWithProgress(executable: brewPath, arguments: ["services", "restart", serviceName])
    }
    
    // MARK: - Redis 操作
    
    /// 获取数据库大小列表
    func getDBSizes() async -> [String] {
        let result = await executeRedisCommand(arguments: ["INFO", "keyspace"])
        guard case .success(let output) = result else { return [] }
        
        var sizes: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("db") && trimmed.contains(":") {
                // db0:keys=123,expires=45,avg_ttl=3600000
                sizes.append(trimmed)
            }
        }
        return sizes
    }
    
    /// 获取指定数据库的键列表
    func listKeys(dbIndex: Int = 0) async -> [RedisKeyInfo] {
        let selectResult = await executeRedisCommand(arguments: ["SELECT", "\(dbIndex)"])
        guard case .success = selectResult else { return [] }
        
        let result = await executeRedisCommand(arguments: ["DBSIZE"])
        guard case .success = result else { return [] }
        
        let keyCount = Int(result.successValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard keyCount > 0 && keyCount <= 10000 else { return [] }
        
        // 获取所有键
        let keysResult = await executeRedisCommand(arguments: ["KEYS", "*"])
        guard case .success(let keysOutput) = keysResult else { return [] }
        
        var keyInfos: [RedisKeyInfo] = []
        let keys = keysOutput.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // 限制展示数量，逐个获取类型和 TTL
        let displayKeys = Array(keys.prefix(500))
        for key in displayKeys {
            async let typeResult = executeRedisCommand(arguments: ["TYPE", key])
            async let ttlResult = executeRedisCommand(arguments: ["TTL", key])
            
            var keyType = "string"
            if case .success(let t) = await typeResult { keyType = t.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            var ttl = -1
            if case .success(let t) = await ttlResult {
                ttl = Int(t.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
            }
            
            keyInfos.append(RedisKeyInfo(
                id: key,
                key: key,
                type: keyType,
                ttl: ttl,
                size: ""
            ))
        }
        
        if keys.count > 500 {
            keyInfos.append(RedisKeyInfo(id: "more", key: "... 还有 \(keys.count - 500) 个键", type: "", ttl: 0, size: ""))
        }
        
        return keyInfos
    }
    
    /// 获取键的值
    func getValue(key: String) async -> String {
        // 先获取类型
        let typeResult = await executeRedisCommand(arguments: ["TYPE", key])
        guard case .success(let keyType) = typeResult else { return "获取失败" }
        let type = keyType.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch type {
        case "string":
            let result = await executeRedisCommand(arguments: ["GET", key])
            if case .success(let value) = result { return value }
            return "获取失败"
        case "list":
            let result = await executeRedisCommand(arguments: ["LRANGE", key, "0", "20"])
            if case .success(let value) = result { return "(list) 共展示前 20 条:\n" + value }
            return "获取失败"
        case "set":
            let result = await executeRedisCommand(arguments: ["SMEMBERS", key])
            if case .success(let value) = result { return "(set)\n" + value }
            return "获取失败"
        case "zset":
            let result = await executeRedisCommand(arguments: ["ZRANGE", key, "0", "20", "WITHSCORES"])
            if case .success(let value) = result { return "(zset) 共展示前 20 条:\n" + value }
            return "获取失败"
        case "hash":
            let result = await executeRedisCommand(arguments: ["HGETALL", key])
            if case .success(let value) = result { return "(hash)\n" + value }
            return "获取失败"
        default:
            return "不支持的类型: \(type)"
        }
    }
    
    /// 删除键
    func deleteKey(key: String) async -> OperationResult {
        let result = await executeRedisCommand(arguments: ["DEL", key])
        if case .success(let output) = result {
            let count = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success("已删除 \(count) 个键")
        }
        return .failure("删除失败")
    }
    
    /// 设置键值
    func setKey(key: String, value: String, ttl: Int = 0) async -> OperationResult {
        var args = ["SET", key, value]
        if ttl > 0 { args += ["EX", "\(ttl)"] }
        let result = await executeRedisCommand(arguments: args)
        if case .success = result {
            return .success("设置成功")
        }
        return .failure("设置失败")
    }
    
    /// 清空当前数据库
    func flushDB() async -> OperationResult {
        let result = await executeRedisCommand(arguments: ["FLUSHDB"])
        if case .success = result {
            return .success("当前数据库已清空")
        }
        return .failure("清空失败")
    }
    
    /// 获取 Redis 服务器信息
    func getServerInfo() async -> [String: String] {
        let result = await executeRedisCommand(arguments: ["INFO", "server"])
        guard case .success(let output) = result else { return [:] }
        
        var info: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(":") && !trimmed.hasPrefix("#") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count == 2 {
                    info[parts[0]] = parts[1]
                }
            }
        }
        return info
    }
    
    /// 获取 Redis 内存信息
    func getMemoryInfo() async -> [String: String] {
        let result = await executeRedisCommand(arguments: ["INFO", "memory"])
        guard case .success(let output) = result else { return [:] }
        
        var info: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(":") && !trimmed.hasPrefix("#") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count == 2 {
                    info[parts[0]] = parts[1]
                }
            }
        }
        return info
    }
    
    /// 获取客户端连接数
    func getConnectedClients() async -> Int {
        let result = await executeRedisCommand(arguments: ["INFO", "clients"])
        guard case .success(let output) = result else { return 0 }
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("connected_clients:") {
                let value = line.replacingOccurrences(of: "connected_clients:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }
    
    /// 供外部调用的 redis-cli 命令
    func executeRedisCLI(arguments: [String]) async -> OperationResult {
        return await executeRedisCommand(arguments: arguments)
    }
    
    /// 获取配置文件路径
    func getConfigFilePath() -> String {
        return "\(brewPrefix)/etc/redis.conf"
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
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("配置文件已保存")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 私有方法
    
    private var redisEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "\(brewPrefix)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(currentPath)"
        } else {
            env["PATH"] = extraPaths
        }
        env["HOME"] = NSHomeDirectory()
        return env
    }
    
    private func updateLoadingState(message: String) {
        isLoading = true
        loadingMessage = message
    }
    
    /// 执行 redis-cli 命令
    private func executeRedisCommand(arguments: [String]) async -> OperationResult {
        guard !redisCLIPath.isEmpty else {
            return .failure("Redis 未安装")
        }
        let env = redisEnvironment
        let cliPath = redisCLIPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: cliPath)
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
    
    private func executeBrewCommand(arguments: [String]) async -> OperationResult {
        let env = redisEnvironment
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
    
    private func executeCommandWithProgress(executable: String, arguments: [String]) async -> OperationResult {
        updateLoadingState(message: "正在执行...")
        let env = redisEnvironment
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
}

// MARK: - OperationResult 扩展

extension OperationResult {
    var successValue: String {
        if case .success(let value) = self { return value }
        return ""
    }
}
