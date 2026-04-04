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

// MARK: - 系统服务

@MainActor
class SystemService: ObservableObject {
    
    static let shared = SystemService()
    
    @Published var isLoading = false
    
    private func executeCommand(executable: String, arguments: [String]) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
