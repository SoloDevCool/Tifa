import SwiftUI

struct RedisSettingsView: View {
    @StateObject private var viewModel = RedisSettingsViewModel()
    @State private var configText = ""
    @State private var showingSaveConfirm = false
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 服务状态
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.isRunning ? "Redis 运行中" : "Redis 已停止")
                        .font(.headline)
                    Spacer()
                    if viewModel.isRunning {
                        Button(action: { Task { await viewModel.stopRedis(); await viewModel.load() } }) {
                            Label("停止", systemImage: "stop.fill").foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: { Task { await viewModel.startRedis(); await viewModel.load() } }) {
                            Label("启动", systemImage: "play.fill").foregroundColor(.green)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(action: { Task { await viewModel.restartRedis(); await viewModel.load() } }) {
                        Label("重启", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 基本信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundColor(.accentColor)
                        Text("基本信息")
                            .font(.headline)
                    }
                    
                    SettingsRow(label: "版本", value: viewModel.version)
                    SettingsRow(label: "端口", value: viewModel.port)
                    SettingsRow(label: "连接数", value: viewModel.connectedClients)
                    SettingsRow(label: "运行模式", value: viewModel.runMode)
                    SettingsRow(label: "配置文件", value: viewModel.configPath)
                    SettingsRow(label: "运行天数", value: viewModel.uptimeDays)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 内存信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip").foregroundColor(.accentColor)
                        Text("内存信息")
                            .font(.headline)
                    }
                    
                    SettingsRow(label: "已用内存", value: viewModel.usedMemory)
                    SettingsRow(label: "峰值内存", value: viewModel.peakMemory)
                    SettingsRow(label: "总键数", value: viewModel.totalKeys)
                    
                    if let memPct = viewModel.memoryUsagePercentage {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("内存使用率")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f%%", memPct))
                                    .font(.subheadline)
                                    .foregroundColor(memPct < 80 ? .green : (memPct < 95 ? .orange : .red))
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: .separatorColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(memPct < 80 ? Color.green : (memPct < 95 ? Color.orange : Color.red).opacity(0.7))
                                            .frame(width: geo.size.width * min(memPct / 100, 1.0), height: geo.size.height)
                                    )
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 配置文件编辑
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").foregroundColor(.accentColor)
                            Text("配置文件")
                                .font(.headline)
                        }
                        Spacer()
                        if viewModel.configFileExists {
                            Button(action: {
                                configText = viewModel.readConfigFile()
                            }) {
                                Label("加载配置", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { showingSaveConfirm = true }) {
                                Label("保存并重启", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if !viewModel.configFileExists {
                        Text("配置文件不存在")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        TextEditor(text: $configText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 300)
                            .border(Color(nsColor: .separatorColor))
                            .cornerRadius(4)
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 维护操作
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench").foregroundColor(.accentColor)
                        Text("维护操作")
                            .font(.headline)
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                commandResultText = await viewModel.getClientList()
                                showingCommandResult = true
                            }
                        }) {
                            Label("查看客户端连接", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRunning)
                        
                        Button(action: {
                            Task {
                                let result = await viewModel.bgsave()
                                commandResultText = result.successValue.isEmpty ? "操作完成" : result.successValue
                                showingCommandResult = true
                            }
                        }) {
                            Label("保存 RDB 快照", systemImage: "externaldrive.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRunning)
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(20)
        }
        .task {
            await viewModel.load()
        }
        .alert("确认保存", isPresented: $showingSaveConfirm) {
            Button("取消", role: .cancel) {}
            Button("保存并重启", role: .destructive) {
                Task {
                    let result = viewModel.saveConfigFile(content: configText)
                    switch result {
                    case .success:
                        await viewModel.restartRedis()
                        await viewModel.load()
                    case .failure(let error):
                        commandResultText = error
                        showingCommandResult = true
                    }
                }
            }
        } message: {
            Text("保存配置文件后将自动重启 Redis 服务")
        }
        .sheet(isPresented: $showingCommandResult) {
            VStack(spacing: 16) {
                HStack {
                    Text("详细信息")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingCommandResult = false }
                }
                ScrollView {
                    Text(commandResultText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            .padding(24)
            .frame(width: 600, height: 400)
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

// MARK: - ViewModel

@MainActor
class RedisSettingsViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var version = ""
    @Published var port = "6379"
    @Published var connectedClients = "0"
    @Published var runMode = "standalone"
    @Published var configPath = ""
    @Published var uptimeDays = ""
    @Published var usedMemory = ""
    @Published var peakMemory = ""
    @Published var totalKeys = "0"
    @Published var memoryUsagePercentage: Double?
    @Published var configFileExists = false
    
    private let service = RedisService.shared
    
    func load() async {
        async let running = service.isRedisRunning()
        async let serverInfo = service.getServerInfo()
        async let memInfo = service.getMemoryInfo()
        async let clients = service.getConnectedClients()
        
        isRunning = await running
        let info = await serverInfo
        let mem = await memInfo
        connectedClients = "\(await clients)"
        
        version = info["redis_version"] ?? "未知"
        port = info["tcp_port"] ?? "6379"
        runMode = info["redis_mode"] ?? "standalone"
        configPath = info["config_file"] ?? service.getConfigFilePath()
        configFileExists = service.configFileExists()
        
        // 运行时间
        if let uptimeSeconds = Double(info["uptime_in_seconds"] ?? "0") {
            let days = Int(uptimeSeconds) / 86400
            let hours = (Int(uptimeSeconds) % 86400) / 3600
            if days > 0 {
                uptimeDays = "\(days) 天 \(hours) 小时"
            } else {
                uptimeDays = "\(hours) 小时"
            }
        }
        
        // 内存
        if let used = parseMemory(mem["used_memory_human"] ?? ""),
           let peak = parseMemory(mem["used_memory_peak_human"] ?? "") {
            usedMemory = used
            peakMemory = peak
        }
        
        if let maxMemory = parseMemoryBytes(mem["maxmemory"] ?? "0"), maxMemory > 0,
           let used = parseMemoryBytes(mem["used_memory"] ?? "0") {
            memoryUsagePercentage = Double(used) / Double(maxMemory) * 100
        }
        
        totalKeys = mem["db0"] ?? "0"
    }
    
    func startRedis() async {
        _ = await service.startRedis()
    }
    
    func stopRedis() async {
        _ = await service.stopRedis()
    }
    
    func restartRedis() async {
        _ = await service.restartRedis()
    }
    
    func readConfigFile() -> String {
        return service.readConfigFile()
    }
    
    func saveConfigFile(content: String) -> OperationResult {
        return service.saveConfigFile(content: content)
    }
    
    func getClientList() async -> String {
        let clientResult = await service.executeRedisCLI(arguments: ["CLIENT", "LIST"])
        return clientResult.successValue
    }
    
    func bgsave() async -> OperationResult {
        let result = await service.executeRedisCLI(arguments: ["BGSAVE"])
        return result
    }
    
    private func parseMemory(_ str: String) -> String? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func parseMemoryBytes(_ str: String) -> UInt64? {
        return UInt64(str.trimmingCharacters(in: .whitespaces))
    }
}

#Preview {
    RedisSettingsView()
}
