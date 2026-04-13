import Foundation

// MARK: - 系统指标模型

struct SystemMetrics {
    var cpuUsage: Double = 0
    var cpuCores: Int = 0
    var cpuModel: String = ""
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var temperature: Double?
    var thermalPressure: String = ""
    var hostname: String = ""
    var osVersion: String = ""
    var arch: String = ""
    var uptime: TimeInterval = 0
}

// MARK: - 进程信息模型

struct AppProcessInfo: Identifiable, Hashable {
    let id: Int32  // PID
    var pid: Int32 { id }
    var name: String
    var user: String
    var cpuUsage: Double
    var memoryUsage: Double
    var memoryMB: Double
    var threads: Int
    var category: ProcessCategory
    
    enum ProcessCategory: String, CaseIterable {
        case user = "用户进程"
        case system = "系统进程"
        case background = "后台进程"
        
        var icon: String {
            switch self {
            case .user: return "person.fill"
            case .system: return "gear"
            case .background: return "arrow.clockwise"
            }
        }
    }
}

// MARK: - 进程排序选项

enum ProcessSortOption: String, CaseIterable {
    case cpu = "CPU"
    case memory = "内存"
    case pid = "PID"
    case name = "名称"
}

// MARK: - 系统服务

@MainActor
class SystemService: ObservableObject {
    
    static let shared = SystemService()
    
    @Published var isLoading = false
    
    private func executeCommand(executable: String, arguments: [String]) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                do {
                    try process.run()
                    // 先读取 stdout 防止管道死锁
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
    
    // MARK: - 采集所有指标
    
    func collectMetrics() async -> SystemMetrics {
        var metrics = SystemMetrics()
        
        async let cpu = getCPUInfo()
        async let memory = getMemoryInfo()
        async let disk = getDiskInfo()
        async let system = getSystemInfo()
        async let temp = getTemperature()
        
        let cpuData = await cpu
        metrics.cpuUsage = cpuData.usage
        metrics.cpuCores = cpuData.cores
        metrics.cpuModel = cpuData.model
        
        let memData = await memory
        metrics.memoryUsed = memData.used
        metrics.memoryTotal = memData.total
        metrics.swapUsed = memData.swapUsed
        metrics.swapTotal = memData.swapTotal
        
        let diskData = await disk
        metrics.diskUsed = diskData.used
        metrics.diskTotal = diskData.total
        
        let sysData = await system
        metrics.hostname = sysData.hostname
        metrics.osVersion = sysData.osVersion
        metrics.arch = sysData.arch
        metrics.uptime = sysData.uptime
        
        let tempData = await temp
        metrics.temperature = tempData.temperature
        metrics.thermalPressure = tempData.thermalPressure
        
        return metrics
    }
    
    // MARK: - CPU
    
    private struct CPUData {
        var usage: Double = 0
        var cores: Int = 0
        var model: String = ""
    }
    
    private func getCPUInfo() async -> CPUData {
        let model = await executeCommand(executable: "/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let coresStr = await executeCommand(executable: "/usr/sbin/sysctl", arguments: ["-n", "hw.logicalcpu"])
        let cores = Int(coresStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        
        // top -l 1 采样约 1 秒，用于计算 CPU 使用率
        let topOutput = await executeCommand(executable: "/usr/bin/top", arguments: ["-l", "1", "-n", "0"])
        
        var usage: Double = 0
        for line in topOutput.components(separatedBy: .newlines) {
            if line.contains("CPU usage:") {
                let pattern = #"CPU usage:\s*([\d.]+)%\s*user,\s*([\d.]+)%\s*sys"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if let userRange = Range(match.range(at: 1), in: line),
                       let sysRange = Range(match.range(at: 2), in: line) {
                        let user = Double(line[userRange]) ?? 0
                        let sys = Double(line[sysRange]) ?? 0
                        usage = user + sys
                    }
                }
                break
            }
        }
        
        return CPUData(usage: usage, cores: cores, model: model)
    }
    
    // MARK: - 内存
    
    private struct MemoryData {
        var used: UInt64 = 0
        var total: UInt64 = 0
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
    }
    
    private func getMemoryInfo() async -> MemoryData {
        let memSizeStr = await executeCommand(executable: "/usr/sbin/sysctl", arguments: ["-n", "hw.memsize"])
        let total = UInt64(memSizeStr.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        
        // Swap
        let swapOutput = await executeCommand(executable: "/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"])
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        let swapParts = swapOutput.components(separatedBy: .whitespaces)
        for (i, part) in swapParts.enumerated() {
            if part == "total" && i + 2 < swapParts.count {
                swapTotal = parseMemorySize(swapParts[i + 2])
            }
            if part == "used" && i + 2 < swapParts.count {
                swapUsed = parseMemorySize(swapParts[i + 2])
            }
        }
        
        // vm_stat 获取内存页面统计
        let vmstat = await executeCommand(executable: "/usr/bin/vm_stat", arguments: [])
        var pageCounts: [String: Int] = [:]
        for line in vmstat.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ":")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
                let value = Int(valueStr.replacingOccurrences(of: ".", with: "")) ?? 0
                pageCounts[key] = value
            }
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(pageCounts["Pages active"] ?? 0)
        let wired = UInt64(pageCounts["Pages wired down"] ?? 0)
        let compressed = UInt64(pageCounts["Pages occupied by compressor"] ?? 0)
        let used = (active + wired + compressed) * pageSize
        
        return MemoryData(used: used, total: total, swapUsed: swapUsed, swapTotal: swapTotal)
    }
    
    // MARK: - 磁盘
    
    private struct DiskData {
        var used: UInt64 = 0
        var total: UInt64 = 0
    }
    
    private func getDiskInfo() -> DiskData {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]) {
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacity ?? 0)
            return DiskData(used: total - available, total: total)
        }
        return DiskData()
    }
    
    // MARK: - 系统信息
    
    private struct SystemData {
        var hostname = ""
        var osVersion = ""
        var arch = ""
        var uptime: TimeInterval = 0
    }
    
    private func getSystemInfo() async -> SystemData {
        let hostname = await executeCommand(executable: "/bin/hostname", arguments: [])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let swVers = await executeCommand(executable: "/usr/bin/sw_vers", arguments: [])
        var osVersion = ""
        for line in swVers.components(separatedBy: .newlines) {
            if line.hasPrefix("ProductVersion:") {
                osVersion = "macOS " + line
                    .replacingOccurrences(of: "ProductVersion:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        
        let arch = await executeCommand(executable: "/usr/bin/uname", arguments: ["-m"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let bootTimeStr = await executeCommand(executable: "/usr/sbin/sysctl", arguments: ["-n", "kern.boottime"])
        var uptime: TimeInterval = 0
        let pattern = #"sec\s*=\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: bootTimeStr, range: NSRange(bootTimeStr.startIndex..., in: bootTimeStr)),
           let range = Range(match.range(at: 1), in: bootTimeStr) {
            let bootTimestamp = Double(bootTimeStr[range]) ?? 0
            uptime = Date().timeIntervalSince1970 - bootTimestamp
        }
        
        return SystemData(hostname: hostname, osVersion: osVersion, arch: arch, uptime: uptime)
    }
    
    // MARK: - 温度
    
    private struct TempData {
        var temperature: Double?
        var thermalPressure: String = ""
    }
    
    private func getTemperature() async -> TempData {
        // 散热压力等级（无需 sudo）
        let thermOutput = await executeCommand(executable: "/usr/bin/pmset", arguments: ["-g", "therm"])
        var thermalPressure = ""
        let lowerTherm = thermOutput.lowercased()
        if lowerTherm.contains("critical") {
            thermalPressure = "critical"
        } else if lowerTherm.contains("serious") {
            thermalPressure = "serious"
        } else if lowerTherm.contains("fair") {
            thermalPressure = "fair"
        } else {
            thermalPressure = "nominal"
        }
        
        // 电池温度（通过 ioreg）
        let ioregOutput = await executeCommand(executable: "/usr/sbin/ioreg", arguments: ["-r", "-c", "AppleSmartBattery", "-w0"])
        var temperature: Double?
        for line in ioregOutput.components(separatedBy: .newlines) {
            if line.contains("\"Temperature\"") {
                let pattern = #"\"Temperature\"\s*=\s*(\d+)"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let range = Range(match.range(at: 1), in: line) {
                    let rawTemp = Double(line[range]) ?? 0
                    temperature = rawTemp / 100.0
                }
                break
            }
        }
        
        return TempData(temperature: temperature, thermalPressure: thermalPressure)
    }
    
    // MARK: - 进程信息
    
    func getProcessList() async -> [AppProcessInfo] {
        let output = await executeCommand(executable: "/bin/ps", arguments: ["-eo", "pid,pcpu,pmem,rss,user,comm"])
        
        var processes: [AppProcessInfo] = []
        let lines = output.components(separatedBy: "\n")
        
        // 正则解析: PID  %CPU  %MEM  RSS  USER  COMMAND
        // 数字字段在前，USER 是单个词，COMMAND 是剩余部分
        let pattern = #"^\s*(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        // 跳过第一行（表头）
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let pidRange = Range(match.range(at: 1), in: line),
                  let cpuRange = Range(match.range(at: 2), in: line),
                  let memRange = Range(match.range(at: 3), in: line),
                  let rssRange = Range(match.range(at: 4), in: line),
                  let userRange = Range(match.range(at: 5), in: line),
                  let commRange = Range(match.range(at: 6), in: line) else { continue }
            
            guard let pid = Int32(line[pidRange]) else { continue }
            let cpuUsage = Double(line[cpuRange]) ?? 0
            let memUsage = Double(line[memRange]) ?? 0
            let rssKB = Double(line[rssRange]) ?? 0
            let memMB = rssKB / 1024
            let user = String(line[userRange])
            let comm = String(line[commRange])
            
            if user.isEmpty || comm.isEmpty { continue }
            
            // 提取进程名称（去除路径）
            var name = comm
            if let lastSlash = comm.lastIndex(of: "/") {
                name = String(comm[comm.index(after: lastSlash)...])
            }
            
            // 判断进程类别
            let category: AppProcessInfo.ProcessCategory
            if user == "root" || user == "wheel" {
                category = .system
            } else if name.hasPrefix("_") || name.hasPrefix("kernel_") {
                category = .system
            } else if name == "login" || name == "launchd" || name == "WindowServer" {
                category = .system
            } else {
                category = .user
            }
            
            // 线程数（macOS ps 不支持便捷获取，固定为 1）
            let threads = 1
            
            processes.append(AppProcessInfo(
                id: pid,
                name: name,
                user: user,
                cpuUsage: cpuUsage,
                memoryUsage: memUsage,
                memoryMB: memMB,
                threads: threads,
                category: category
            ))
        }
        
        return processes
    }
    
    // MARK: - 端口信息
    
    func getPortList() async -> [PortInfo] {
        async let tcpOutput = executeCommand(executable: "/usr/sbin/netstat", arguments: ["-an", "-p", "tcp"])
        async let udpOutput = executeCommand(executable: "/usr/sbin/netstat", arguments: ["-an", "-p", "udp"])
        async let pidMapping = getPidMappingForPortsAsync()
        
        return parseNetstatOutput(
            tcpOutput: await tcpOutput,
            udpOutput: await udpOutput,
            pidMapping: await pidMapping
        )
    }
    
    private func parseNetstatOutput(tcpOutput: String, udpOutput: String, pidMapping: [String: (pid: Int, name: String)]) -> [PortInfo] {
        var ports: [PortInfo] = []
        
        // 解析 TCP 连接
        for line in tcpOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("Proto") || trimmed.hasPrefix("Active") {
                continue
            }
            if let port = parseNetstatLine(line, defaultProto: "TCP", pidMapping: pidMapping) {
                ports.append(port)
            }
        }
        
        // 解析 UDP
        for line in udpOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("Proto") || trimmed.hasPrefix("Active") {
                continue
            }
            if let port = parseNetstatLine(line, defaultProto: "UDP", pidMapping: pidMapping) {
                ports.append(port)
            }
        }
        
        return ports.sorted { $0.localPort < $1.localPort }
    }
    
    private func parseNetstatLine(_ line: String, defaultProto: String, pidMapping: [String: (pid: Int, name: String)]) -> PortInfo? {
        // netstat -an -p tcp 典型格式（6 列）:
        // tcp4  0  0  *.80  *.*  LISTEN
        // tcp4  0  0  192.168.2.243.54235  120.53.74.30.443  ESTABLISHED
        
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 6 else { return nil }
        
        let proto = String(parts[0]).trimmingCharacters(in: .newlines)
        
        // UDP 行只有 5 个字段（无 state），TCP 有 6 个
        let localAddr = String(parts[3]).trimmingCharacters(in: .newlines)
        let remoteAddr = String(parts[4]).trimmingCharacters(in: .newlines)
        let state = parts.count >= 6 ? String(parts[5]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        
        let (localAddress, localPort) = parseAddressPort(localAddr)
        let (remoteAddress, remotePort) = parseAddressPort(remoteAddr)
        
        // 通过 lsof 映射获取进程信息
        let key = "\(localAddress):\(localPort)"
        let pidInfo = pidMapping[key] ?? (pid: 0, name: "-")
        
        // 确定协议类型名称
        let protocolType: String
        if proto.hasPrefix("tcp") {
            protocolType = proto == "tcp6" ? "TCP6" : "TCP"
        } else {
            protocolType = proto == "udp6" ? "UDP6" : "UDP"
        }
        
        return PortInfo(
            id: "\(proto)-\(localAddr)-\(remoteAddr)",
            localAddress: localAddress,
            localPort: localPort,
            remoteAddress: remoteAddress,
            remotePort: remotePort,
            protocolType: protocolType,
            state: state,
            processName: pidInfo.name,
            pid: pidInfo.pid
        )
    }
    
    private func parseAddressPort(_ addr: String) -> (address: String, port: Int) {
        // 格式: *.80, 127.0.0.1.5432, ::1.5432, *.5353
        // IPv4: 最后一个点是端口分隔符
        // IPv6: 最后一个点是端口分隔符, * 表示所有接口
        
        if addr == "*.*" {
            return ("*", 0)
        }
        
        if let lastDot = addr.lastIndex(of: ".") {
            let portStr = String(addr[addr.index(after: lastDot)...])
            let address = String(addr[..<lastDot])
            let addressDisplay = address == "*" ? "*" : address
            let port = Int(portStr) ?? 0
            return (addressDisplay, port)
        }
        
        return (addr, 0)
    }
    
    /// 通过 lsof 获取端口与进程的映射（异步版本）
    private func getPidMappingForPortsAsync() async -> [String: (pid: Int, name: String)] {
        let result = await executeCommand(executable: "/usr/sbin/lsof", arguments: ["-i", "-P", "-n", "-sTCP:LISTEN"])
        
        var mapping: [String: (pid: Int, name: String)] = [:]
        
        for line in result.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }
            if parts[0] == "COMMAND" { continue }
            
            let name = String(parts[0])
            guard let pid = Int(parts[1]) else { continue }
            
            // lsof 格式: ... NAME 列通常是 :端口号 或 *:端口号
            // 例如: node    1234  user  ...  TCP *:3000 (LISTEN)
            let nameStr = parts.dropFirst(8).joined(separator: " ")
            
            // 提取端口: 从 NAME 列中解析，格式如 "*:3000" 或 "127.0.0.1:5432"
            var portKey = ""
            if let colonIdx = nameStr.lastIndex(of: ":") {
                let portPart = String(nameStr[nameStr.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ").first ?? ""
                if let port = Int(portPart) {
                    portKey = "*:\(port)"
                }
            }
            
            // 也尝试从倒数第二列获取地址
            if parts.count >= 9 {
                let addrField = String(parts[8])
                if let colonIdx = addrField.lastIndex(of: ":") {
                    let addrPart = String(addrField[..<colonIdx])
                    let portPart = String(addrField[addrField.index(after: colonIdx)...])
                    if let port = Int(portPart) {
                        portKey = "\(addrPart):\(port)"
                    }
                }
            }
            
            if !portKey.isEmpty {
                mapping[portKey] = (pid: pid, name: name)
            }
        }
        
        return mapping
    }
    
    // MARK: - 工具方法
    
    private func parseMemorySize(_ str: String) -> UInt64 {
        let str = str.trimmingCharacters(in: .whitespaces)
        if str.hasSuffix("G") {
            return UInt64((Double(str.dropLast()) ?? 0) * 1024 * 1024 * 1024)
        } else if str.hasSuffix("M") {
            return UInt64((Double(str.dropLast()) ?? 0) * 1024 * 1024)
        } else if str.hasSuffix("K") {
            return UInt64((Double(str.dropLast()) ?? 0) * 1024)
        }
        return UInt64(str) ?? 0
    }
}
