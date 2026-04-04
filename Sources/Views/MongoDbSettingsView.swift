import SwiftUI

struct MongoDbSettingsView: View {
    @StateObject private var viewModel = MongoDbSettingsViewModel()
    @State private var configText = ""
    @State private var showingSaveConfirm = false
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var showingDbStats = false
    @State private var dbStatsText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 服务状态
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.isRunning ? "MongoDB 运行中" : "MongoDB 已停止")
                        .font(.headline)
                    Spacer()
                    if viewModel.isRunning {
                        Button(action: { Task { await viewModel.stopMongoDb(); await viewModel.load() } }) {
                            Label("停止", systemImage: "stop.fill").foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(action: { Task { await viewModel.startMongoDb(); await viewModel.load() } }) {
                            Label("启动", systemImage: "play.fill").foregroundColor(.green)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(action: { Task { await viewModel.restartMongoDb(); await viewModel.load() } }) {
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
                    SettingsRow(label: "服务名称", value: viewModel.serviceName)
                    SettingsRow(label: "端口", value: viewModel.port)
                    SettingsRow(label: "数据目录", value: viewModel.dataDir)
                    SettingsRow(label: "日志目录", value: viewModel.logDir)
                    SettingsRow(label: "配置文件", value: viewModel.configPath)
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // 服务器状态
                if viewModel.isRunning {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar").foregroundColor(.accentColor)
                            Text("服务器状态")
                                .font(.headline)
                        }
                        
                        SettingsRow(label: "运行时间", value: viewModel.uptime)
                        SettingsRow(label: "连接数", value: viewModel.connections)
                        SettingsRow(label: "内存使用", value: viewModel.memoryUsage)
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                
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
                            
                            Button(action: {
                                configText = viewModel.generateDefaultConfig()
                            }) {
                                Label("恢复默认", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { showingSaveConfirm = true }) {
                                Label("保存并重启", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(action: {
                                configText = viewModel.generateDefaultConfig()
                            }) {
                                Label("生成默认配置", systemImage: "doc.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if !viewModel.configFileExists && configText.isEmpty {
                        Text("配置文件不存在，点击「生成默认配置」创建")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    
                    TextEditor(text: $configText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 250)
                        .border(Color(nsColor: .separatorColor))
                        .cornerRadius(4)
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
                                let result = await viewModel.runCompact()
                                commandResultText = result.successValue.isEmpty ? "操作完成" : result.successValue
                                showingCommandResult = true
                            }
                        }) {
                            Label("压缩数据", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRunning)
                        
                        Button(action: {
                            Task {
                                commandResultText = await viewModel.getServerStatus()
                                showingCommandResult = true
                            }
                        }) {
                            Label("服务器状态", systemImage: "heart.text.square")
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
                        await viewModel.restartMongoDb()
                        await viewModel.load()
                    case .failure(let error):
                        commandResultText = error
                        showingCommandResult = true
                    }
                }
            }
        } message: {
            Text("保存配置文件后将自动重启 MongoDB 服务")
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

// MARK: - ViewModel

@MainActor
class MongoDbSettingsViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var version = ""
    @Published var serviceName = ""
    @Published var port = "27017"
    @Published var dataDir = ""
    @Published var logDir = ""
    @Published var configPath = ""
    @Published var configFileExists = false
    @Published var uptime = ""
    @Published var connections = ""
    @Published var memoryUsage = ""
    
    private let service = MongoDbService.shared
    
    func load() async {
        async let running = service.isMongoDbRunning()
        async let shellVersion = service.getMongoDbVersion()
        async let serverVersion = service.getMongoDbServerVersion()
        
        isRunning = await running
        let sv = await serverVersion
        let shv = await shellVersion
        
        version = shv.isEmpty ? sv : "\(shv) (server \(sv))"
        serviceName = service.getServiceName()
        configPath = service.getConfigFilePath()
        configFileExists = service.configFileExists()
        dataDir = service.getDataDir()
        logDir = service.getLogDir()
        
        if isRunning {
            let status = await service.getServerStatus()
            uptime = status["uptime"] ?? ""
            connections = status["connections"] ?? ""
            memoryUsage = status["memory"] ?? ""
        }
    }
    
    func startMongoDb() async {
        _ = await service.startMongoDb()
    }
    
    func stopMongoDb() async {
        _ = await service.stopMongoDb()
    }
    
    func restartMongoDb() async {
        _ = await service.restartMongoDb()
    }
    
    func readConfigFile() -> String {
        return service.readConfigFile()
    }
    
    func saveConfigFile(content: String) -> OperationResult {
        return service.saveConfigFile(content: content)
    }
    
    func generateDefaultConfig() -> String {
        return service.generateDefaultConfig()
    }
    
    func getServerStatus() async -> String {
        let status = await service.getServerStatus()
        if status.isEmpty { return "无法获取状态信息" }
        var lines: [String] = []
        for (key, value) in status.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }
        return lines.joined(separator: "\n")
    }
    
    func runCompact() async -> OperationResult {
        let dbs = await service.listDatabases()
        if dbs.isEmpty {
            return .failure("没有数据库或获取失败")
        }
        return .success("找到 \(dbs.count) 个数据库")
    }
}

#Preview {
    MongoDbSettingsView()
}
