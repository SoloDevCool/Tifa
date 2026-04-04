import SwiftUI

struct PostgresSettingsView: View {
    @StateObject private var viewModel = PostgresSettingsViewModel()
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var isEditingConfig = false
    @State private var isEditingHBA = false
    @State private var rawConfigText = ""
    @State private var rawHBAText = ""
    @State private var hasUnsavedChanges = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // PostgreSQL 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isAvailable ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.isAvailable ? "PostgreSQL 已安装" : "PostgreSQL 未安装")
                                .font(.headline)
                            if viewModel.isAvailable {
                                Text(viewModel.serviceName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("请先通过 Homebrew 安装：brew install postgresql@16")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if viewModel.isAvailable {
                                if viewModel.isRunning {
                                    Button(action: { Task { await viewModel.stopPostgres() } }) {
                                        Label("停止", systemImage: "stop.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button(action: { Task { await viewModel.startPostgres() } }) {
                                        Label("启动", systemImage: "play.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("状态")
                        .font(.headline)
                }
                
                if viewModel.isAvailable {
                    // 基本信息
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(title: "版本", value: viewModel.pgVersion)
                            InfoRow(title: "服务名称", value: viewModel.serviceName)
                            InfoRow(title: "端口", value: "\(viewModel.pgPort)")
                            InfoRow(title: "数据目录", value: viewModel.dataDir)
                            InfoRow(title: "配置文件", value: viewModel.configFilePath)
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                    } header: {
                        Text("基本信息")
                            .font(.headline)
                    }
                    
                    // 运行状态
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            StatusRow(title: "活跃连接", value: viewModel.activeConnections)
                            StatusRow(title: "数据库数", value: viewModel.databaseCount)
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                    } header: {
                        HStack {
                            Text("运行状态")
                                .font(.headline)
                            Spacer()
                            Button(action: { Task { await viewModel.refreshStatus() } }) {
                                Label("刷新", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // 配置文件
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("postgresql.conf")
                                        .font(.subheadline)
                                    Text(viewModel.configFilePath)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                if viewModel.configFileExists {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("未创建")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.bottom, 4)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("pg_hba.conf")
                                        .font(.subheadline)
                                    Text(viewModel.hbaFilePath)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                if viewModel.hbaFileExists {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("未创建")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                    } header: {
                        Text("配置文件")
                            .font(.headline)
                    }
                    
                    // 配置编辑器
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("选择配置文件", selection: Binding(
                                get: { isEditingHBA ? 1 : 0 },
                                set: { newValue in
                                    isEditingHBA = (newValue == 1)
                                    hasUnsavedChanges = false
                                }
                            )) {
                                Text("postgresql.conf").tag(0)
                                Text("pg_hba.conf").tag(1)
                            }
                            .pickerStyle(.segmented)
                            
                            TextEditor(text: isEditingHBA ? $rawHBAText : $rawConfigText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(minHeight: 300)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .onChange(of: rawConfigText) { _ in
                                    hasUnsavedChanges = true
                                }
                                .onChange(of: rawHBAText) { _ in
                                    hasUnsavedChanges = true
                                }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    if isEditingHBA {
                                        rawHBAText = viewModel.hbaContent
                                    } else {
                                        rawConfigText = viewModel.configContent
                                    }
                                    hasUnsavedChanges = false
                                }) {
                                    Label("重新加载", systemImage: "arrow.counterclockwise")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { Task { await saveCurrentConfig() } }) {
                                    Label(hasUnsavedChanges ? "保存并重启" : "保存", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(hasUnsavedChanges ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                        .foregroundColor(hasUnsavedChanges ? .white : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .disabled(!hasUnsavedChanges)
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                    } header: {
                        Text("配置编辑器")
                            .font(.headline)
                    }
                    
                    // 维护操作
                    Section {
                        VStack(spacing: 12) {
                            Button(action: {
                                Task {
                                    commandResultText = await viewModel.getActiveProcesses()
                                    showingCommandResult = true
                                }
                            }) {
                                HStack {
                                    Label("查看活跃连接", systemImage: "list.bullet.rectangle")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                Task {
                                    commandResultText = await viewModel.getDatabaseSizes()
                                    showingCommandResult = true
                                }
                            }) {
                                HStack {
                                    Label("查看数据库大小", systemImage: "chart.bar")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                Task {
                                    let result = await viewModel.vacuumAll()
                                    commandResultText = result
                                    showingCommandResult = true
                                }
                            }) {
                                HStack {
                                    Label("优化所有数据库 (VACUUM)", systemImage: "wand.and.stars")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("维护")
                            .font(.headline)
                    }
                    
                    // 关于
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(title: "版本", value: "1.0.0")
                            InfoRow(title: "兼容系统", value: "macOS 13.0+")
                            InfoRow(title: "安装方式", value: "Homebrew")
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                    } header: {
                        Text("关于")
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await viewModel.load()
            rawConfigText = viewModel.configContent
            rawHBAText = viewModel.hbaContent
        }
        .sheet(isPresented: $showingCommandResult) {
            VStack(spacing: 16) {
                HStack {
                    Text("操作结果")
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
                
                Button("关闭") { showingCommandResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 600, height: 400)
        }
    }
    
    private func saveCurrentConfig() async {
        let result: OperationResult
        if isEditingHBA {
            result = viewModel.saveHBAFile(content: rawHBAText)
        } else {
            result = viewModel.saveConfigFile(content: rawConfigText)
        }
        switch result {
        case .success(let msg):
            commandResultText = msg
            hasUnsavedChanges = false
            if viewModel.isRunning {
                await viewModel.restartPostgres()
                await viewModel.load()
                rawConfigText = viewModel.configContent
                rawHBAText = viewModel.hbaContent
            }
        case .failure(let error):
            commandResultText = "保存失败: \(error)"
        }
        showingCommandResult = true
    }
}

// MARK: - 辅助视图

private struct StatusRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline.bold())
        }
    }
}

// MARK: - ViewModel

@MainActor
class PostgresSettingsViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var pgVersion = ""
    @Published var serviceName = ""
    @Published var pgPort = 5432
    @Published var dataDir = ""
    @Published var configFilePath = ""
    @Published var configFileExists = false
    @Published var hbaFilePath = ""
    @Published var hbaFileExists = false
    @Published var configContent = ""
    @Published var hbaContent = ""
    @Published var activeConnections = "--"
    @Published var databaseCount = "--"
    
    private let service = PostgresService.shared
    
    func load() async {
        isAvailable = service.checkPostgresAvailable()
        guard isAvailable else { return }
        
        serviceName = service.getServiceName()
        configFilePath = service.getConfigFilePath()
        configFileExists = service.configFileExists()
        configContent = service.readConfigFile()
        hbaFilePath = service.getHBAFilePath()
        hbaFileExists = FileManager.default.fileExists(atPath: hbaFilePath)
        hbaContent = service.readHBAFile()
        
        async let running = service.isPostgresRunning()
        async let version = service.getPostgresVersion()
        async let port = service.getPostgresPort()
        async let datadir = service.getDataDir()
        
        isRunning = await running
        pgVersion = await version
        pgPort = await port
        dataDir = await datadir
        
        if isRunning {
            await refreshStatus()
        }
    }
    
    func refreshStatus() async {
        let connections = await service.getActiveConnections()
        let dbCount = await service.getDatabaseCount()
        activeConnections = "\(connections)"
        databaseCount = "\(dbCount)"
    }
    
    func startPostgres() async {
        _ = await service.startPostgres()
        await load()
    }
    
    func stopPostgres() async {
        _ = await service.stopPostgres()
        await load()
    }
    
    func restartPostgres() async {
        _ = await service.restartPostgres()
        await load()
    }
    
    func saveConfigFile(content: String) -> OperationResult {
        return service.saveConfigFile(content: content)
    }
    
    func saveHBAFile(content: String) -> OperationResult {
        return service.saveHBAFile(content: content)
    }
    
    func vacuumAll() async -> String {
        let dbs = await service.listDatabases()
        let userDBs = dbs.filter { !["template0", "template1"].contains($0.name) }
        if userDBs.isEmpty {
            return "没有需要优化的用户数据库"
        }
        var log = ""
        for db in userDBs {
            let result = await service.vacuumDatabase(database: db.name)
            log += "数据库: \(db.name)\n"
            switch result {
            case .success: log += "VACUUM ANALYZE 完成\n"
            case .failure(let error): log += "失败: \(error)\n"
            }
            log += "\n"
        }
        return log
    }
    
    func getActiveProcesses() async -> String {
        return await service.getActiveProcesses()
    }
    
    func getDatabaseSizes() async -> String {
        return await service.getDatabaseSizes()
    }
}

#Preview {
    PostgresSettingsView()
}
