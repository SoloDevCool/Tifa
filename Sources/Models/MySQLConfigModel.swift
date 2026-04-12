import Foundation

/// MySQL 配置数据模型
struct MySQLConfigModel: Equatable {
    // 版本信息（用于多版本支持）
    var formula: String = "tifa-mysql@8.0"
    
    // [client]
    var clientPort = "3306"
    var clientCharset = "utf8mb4"
    
    // [mysqld] 基础
    var mysqldPort = "3306"
    var mysqldCharset = "utf8mb4"
    var mysqldCollation = "utf8mb4_unicode_ci"
    var mysqldDatadir = ""
    var logError = ""
    
    // 连接
    var maxConnections = "200"
    var maxConnectErrors = "100"
    var waitTimeout = "28800"
    
    // InnoDB
    var innodbBufferPoolSize = "256M"
    var innodbLogFileSize = "48M"
    var innodbFlushLog = "1"
    var innodbFilePerTable = "1"
    
    // 日志
    var slowQueryLog = false
    var longQueryTime = "2"
    var slowQueryLogFile = ""
    
    // 缓存
    var queryCacheSize = "0"
    var tmpTableSize = "64M"
    var maxHeapTableSize = "64M"
    
    /// 获取默认数据目录路径
    static func defaultDataDir(for formula: String) -> String {
        let prefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        if formula.contains("@9") {
            return "\(prefix)/var/tifa-mysql9"
        } else if formula.contains("@8") {
            return "\(prefix)/var/tifa-mysql8"
        }
        return "\(prefix)/var/mysql"
    }
    
    /// 从 my.cnf 文本解析配置
    static func parse(from text: String, formula: String = "tifa-mysql@8.0") -> MySQLConfigModel {
        var config = MySQLConfigModel()
        config.formula = formula
        
        // 确定默认数据目录和日志路径
        let dataDir = defaultDataDir(for: formula)
        config.mysqldDatadir = dataDir
        config.logError = "\(dataDir)/mysql.err"
        config.slowQueryLogFile = "\(dataDir)/slow.log"
        
        guard !text.isEmpty else { return config }
        
        var currentSection = ""
        
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 识别 section
            if trimmed.hasPrefix("[") && trimmed.contains("]") {
                currentSection = trimmed
                continue
            }
            
            // 跳过注释和空行
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix(";") else { continue }
            
            // 解析 key = value
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1].replacingOccurrences(of: "\"", with: "")
            
            switch currentSection {
            case "[client]":
                applyClientValue(&config, key: key, value: value)
            case "[mysqld]", "[mysqld_safe]", "[server]":
                applyMysqldValue(&config, key: key, value: value)
            default:
                // 未识别 section 中的 mysqld 级配置也尝试应用
                applyMysqldValue(&config, key: key, value: value)
            }
        }
        
        return config
    }
    
    /// 导出为 my.cnf 文本
    func toConfigFile() -> String {
        var lines: [String] = []
        lines.append("# MySQL 配置文件")
        lines.append("# \(formula) - 由 Tifa 生成")
        lines.append("")
        
        // [client]
        lines.append("[client]")
        lines.append("port = \(clientPort)")
        lines.append("default-character-set = \(clientCharset)")
        lines.append("")
        
        // [mysqld]
        lines.append("[mysqld]")
        lines.append("port = \(mysqldPort)")
        lines.append("character-set-server = \(mysqldCharset)")
        lines.append("collation-server = \(mysqldCollation)")
        if !mysqldDatadir.isEmpty { lines.append("datadir = \(mysqldDatadir)") }
        
        lines.append("")
        lines.append("# 连接")
        lines.append("max_connections = \(maxConnections)")
        lines.append("max_connect_errors = \(maxConnectErrors)")
        lines.append("wait_timeout = \(waitTimeout)")
        
        lines.append("")
        lines.append("# InnoDB")
        lines.append("innodb_buffer_pool_size = \(innodbBufferPoolSize)")
        lines.append("innodb_log_file_size = \(innodbLogFileSize)")
        lines.append("innodb_flush_log_at_trx_commit = \(innodbFlushLog)")
        lines.append("innodb_file_per_table = \(innodbFilePerTable)")
        
        lines.append("")
        lines.append("# 日志")
        if !logError.isEmpty { lines.append("log_error = \(logError)") }
        lines.append("slow_query_log = \(slowQueryLog ? "1" : "0")")
        lines.append("long_query_time = \(longQueryTime)")
        if !slowQueryLogFile.isEmpty { lines.append("slow_query_log_file = \(slowQueryLogFile)") }
        
        lines.append("")
        lines.append("# 缓存")
        lines.append("query_cache_size = \(queryCacheSize)")
        lines.append("tmp_table_size = \(tmpTableSize)")
        lines.append("max_heap_table_size = \(maxHeapTableSize)")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - 私有解析方法
    
    private static func applyClientValue(_ config: inout MySQLConfigModel, key: String, value: String) {
        switch key {
        case "port": config.clientPort = value
        case "default-character-set": config.clientCharset = value
        default: break
        }
    }
    
    private static func applyMysqldValue(_ config: inout MySQLConfigModel, key: String, value: String) {
        switch key {
        case "port": config.mysqldPort = value
        case "character-set-server": config.mysqldCharset = value
        case "collation-server": config.mysqldCollation = value
        case "datadir": config.mysqldDatadir = value
        case "log_error": config.logError = value
        case "max_connections": config.maxConnections = value
        case "max_connect_errors": config.maxConnectErrors = value
        case "wait_timeout": config.waitTimeout = value
        case "innodb_buffer_pool_size": config.innodbBufferPoolSize = value
        case "innodb_log_file_size": config.innodbLogFileSize = value
        case "innodb_flush_log_at_trx_commit": config.innodbFlushLog = value
        case "innodb_file_per_table": config.innodbFilePerTable = value
        case "slow_query_log": config.slowQueryLog = (value == "1" || value.lowercased() == "on" || value.lowercased() == "true")
        case "long_query_time": config.longQueryTime = value
        case "slow_query_log_file": config.slowQueryLogFile = value
        case "query_cache_size": config.queryCacheSize = value
        case "tmp_table_size": config.tmpTableSize = value
        case "max_heap_table_size": config.maxHeapTableSize = value
        default: break
        }
    }
}
