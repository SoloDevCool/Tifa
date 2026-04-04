import SwiftUI

struct MySQLSettingsView: View {
    @StateObject private var viewModel = MySQLSettingsViewModel()
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var isEditingRaw = false
    @State private var rawConfigText = ""
    @State private var showingSaveConfirm = false
    @State private var hasUnsavedChanges = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MySQL 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isAvailable ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.isAvailable ? "MySQL 已安装" : "MySQL 未安装")
                                .font(.headline)
                            if viewModel.isAvailable {
                                Text(viewModel.serviceName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("请先通过 Homebrew 安装：brew install mysql")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            if viewModel.isAvailable {
                                if viewModel.isRunning {
                                    Button(action: { Task { await viewModel.stopMySQL() } }) {
                                        Label("停止", systemImage: "stop.fill")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button(action: { Task { await viewModel.startMySQL() } }) {
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
                            InfoRow(title: "版本", value: viewModel.mysqlVersion)
                            InfoRow(title: "服务名称", value: viewModel.serviceName)
                            InfoRow(title: "端口", value: "\(viewModel.mysqlPort)")
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
                            StatusRow(title: "运行时间", value: viewModel.uptime)
                            StatusRow(title: "连接数", value: viewModel.connections)
                            StatusRow(title: "慢查询数", value: viewModel.slowQueries)
                            StatusRow(title: "已打开表数", value: viewModel.openTables)
                            StatusRow(title: "每秒查询数", value: viewModel.questionsPerSecond)
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
                    
                    // 配置编辑器
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // 配置文件路径
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("配置文件路径")
                                        .font(.subheadline)
                                    Text(viewModel.configFilePath)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                if !viewModel.configFileExists {
                                    Text("未创建")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .cornerRadius(4)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.bottom, 8)
                            
                            // 编辑模式切换
                            Picker("编辑模式", selection: $isEditingRaw) {
                                Text("可视化编辑").tag(false)
                                Text("原始文本").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, 8)
                            
                            if isEditingRaw {
                                // 原始文本编辑
                                TextEditor(text: $rawConfigText)
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
                            } else {
                                // 可视化表单编辑
                                MySQLConfigEditorView(
                                    config: $viewModel.config,
                                    onReset: {
                                        viewModel.loadConfigFromFile()
                                    },
                                    onLoadDefault: {
                                        viewModel.loadDefaultConfig()
                                        hasUnsavedChanges = true
                                    }
                                )
                                .onChange(of: viewModel.config) { _ in
                                    hasUnsavedChanges = true
                                }
                            }
                            
                            // 操作按钮
                            HStack(spacing: 12) {
                                if !viewModel.configFileExists {
                                    Button(action: {
                                        viewModel.generateDefaultConfig()
                                        rawConfigText = viewModel.getRawConfigText()
                                        hasUnsavedChanges = true
                                    }) {
                                        Label("生成默认配置", systemImage: "doc.badge.gearshape")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Button(action: {
                                    if isEditingRaw {
                                        viewModel.parseRawConfig(rawConfigText)
                                    } else {
                                        rawConfigText = viewModel.getRawConfigText()
                                    }
                                    isEditingRaw = true
                                }) {
                                    Label("导出为文本", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    if isEditingRaw {
                                        viewModel.parseRawConfig(rawConfigText)
                                    }
                                    isEditingRaw = false
                                }) {
                                    Label("从文本导入", systemImage: "doc.on.clipboard")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // 保存按钮
                            HStack(spacing: 12) {
                                Button(action: {
                                    if isEditingRaw {
                                        viewModel.parseRawConfig(rawConfigText)
                                    }
                                    showingSaveConfirm = true
                                }) {
                                    Label(hasUnsavedChanges ? "保存并重启" : "保存", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(hasUnsavedChanges ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                        .foregroundColor(hasUnsavedChanges ? .white : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .disabled(!hasUnsavedChanges && viewModel.configFileExists)
                                
                                if viewModel.isRunning {
                                    Button(action: { showingSaveConfirm = true }) {
                                        Label("保存并重启 MySQL", systemImage: "arrow.clockwise")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(Color.orange)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
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
                                    let result = await viewModel.optimizeAllTables()
                                    commandResultText = result
                                    showingCommandResult = true
                                }
                            }) {
                                HStack {
                                    Label("优化所有表", systemImage: "wand.and.stars")
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
                                    let result = await viewModel.flushPrivileges()
                                    commandResultText = result
                                    showingCommandResult = true
                                }
                            }) {
                                HStack {
                                    Label("刷新权限", systemImage: "lock.rotation")
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
                                    let result = await viewModel.showProcessList()
                                    commandResultText = result
                                    showingCommandResult = true
                                }
                            }) {
                                HStack {
                                    Label("查看进程列表", systemImage: "list.bullet.rectangle")
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
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await viewModel.load()
            rawConfigText = viewModel.getRawConfigText()
        }
        .alert("保存配置", isPresented: $showingSaveConfirm) {
            Button("取消", role: .cancel) {}
            Button("仅保存") {
                Task { await saveConfig(restart: false) }
            }
            Button("保存并重启", role: .destructive) {
                Task { await saveConfig(restart: true) }
            }
        } message: {
            Text("配置文件将保存到 \(viewModel.configFilePath)\n是否同时重启 MySQL 使配置生效？")
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
        .sheet(isPresented: $viewModel.showingInstallSheet) {
            BrewInstallSheet(
                title: "安装 \(viewModel.selectedInstallName)",
                formula: viewModel.selectedInstallFormula,
                isInstalling: viewModel.isInstalling,
                installLog: viewModel.installLog,
                onInstall: { formula in
                    Task { await viewModel.installVersion(formula: formula) }
                },
                onClose: {
                    viewModel.showingInstallSheet = false
                    Task { await viewModel.load() }
                }
            )
        }
    }
    
    private func saveConfig(restart: Bool) async {
        let content = isEditingRaw ? rawConfigText : viewModel.getRawConfigText()
        let result = viewModel.saveConfig(content: content)
        switch result {
        case .success(let msg):
            commandResultText = msg + (restart ? "\n\n正在重启 MySQL..." : "")
        case .failure(let error):
            commandResultText = "保存失败: \(error)"
        }
        hasUnsavedChanges = false
        if restart {
            await viewModel.restartMySQL()
            await viewModel.load()
        }
        showingCommandResult = true
    }
}

// MARK: - MySQL 可视化配置编辑器

struct MySQLConfigEditorView: View {
    @Binding var config: MySQLConfigModel
    let onReset: () -> Void
    let onLoadDefault: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // [client] 区段
            ConfigSectionHeader(title: "[client]", icon: "person")
            
            VStack(spacing: 10) {
                ConfigField(title: "端口 (port)", placeholder: "3306", text: $config.clientPort)
                ConfigField(title: "默认字符集 (default-character-set)", placeholder: "utf8mb4", text: $config.clientCharset)
                ConfigField(title: "Socket 路径", placeholder: "/tmp/mysql.sock", text: $config.clientSocket)
            }
            
            // [mysqld] 区段
            ConfigSectionHeader(title: "[mysqld]", icon: "server.rack")
            
            VStack(spacing: 10) {
                ConfigField(title: "端口 (port)", placeholder: "3306", text: $config.mysqldPort)
                ConfigField(title: "字符集 (character-set-server)", placeholder: "utf8mb4", text: $config.mysqldCharset)
                ConfigField(title: "排序规则 (collation-server)", placeholder: "utf8mb4_unicode_ci", text: $config.mysqldCollation)
                ConfigField(title: "数据目录 (datadir)", placeholder: "/opt/homebrew/var/mysql", text: $config.mysqldDatadir)
                ConfigField(title: "Socket 路径", placeholder: "/tmp/mysql.sock", text: $config.mysqldSocket)
                ConfigField(title: "错误日志 (log_error)", placeholder: "/opt/homebrew/var/mysql/mysql.err", text: $config.logError)
            }
            
            // [mysqld] 连接
            ConfigSectionHeader(title: "连接设置", icon: "network")
            
            VStack(spacing: 10) {
                ConfigField(title: "最大连接数 (max_connections)", placeholder: "200", text: $config.maxConnections)
                ConfigField(title: "最大连接错误数 (max_connect_errors)", placeholder: "100", text: $config.maxConnectErrors)
                ConfigField(title: "等待超时秒数 (wait_timeout)", placeholder: "28800", text: $config.waitTimeout)
            }
            
            // [mysqld] InnoDB
            ConfigSectionHeader(title: "InnoDB 引擎", icon: "internaldrive")
            
            VStack(spacing: 10) {
                ConfigField(title: "缓冲池大小 (innodb_buffer_pool_size)", placeholder: "256M", text: $config.innodbBufferPoolSize)
                ConfigField(title: "日志文件大小 (innodb_log_file_size)", placeholder: "48M", text: $config.innodbLogFileSize)
                ConfigField(title: "日志模式 (innodb_flush_log_at_trx_commit)", placeholder: "1", text: $config.innodbFlushLog)
                ConfigField(title: "文件每表模式 (innodb_file_per_table)", placeholder: "1", text: $config.innodbFilePerTable)
            }
            
            // [mysqld] 日志
            ConfigSectionHeader(title: "日志设置", icon: "doc.text")
            
            VStack(spacing: 10) {
                ConfigToggle(title: "开启慢查询日志 (slow_query_log)", isOn: $config.slowQueryLog)
                ConfigField(title: "慢查询时间阈值(秒)", placeholder: "2", text: $config.longQueryTime)
                ConfigField(title: "慢查询日志路径", placeholder: "/opt/homebrew/var/mysql/slow.log", text: $config.slowQueryLogFile)
            }
            
            // [mysqld] 缓存
            ConfigSectionHeader(title: "缓存设置", icon: "memorychip")
            
            VStack(spacing: 10) {
                ConfigField(title: "查询缓存大小 (query_cache_size)", placeholder: "0", text: $config.queryCacheSize)
                ConfigField(title: "临时表大小 (tmp_table_size)", placeholder: "64M", text: $config.tmpTableSize)
                ConfigField(title: "最大堆表大小 (max_heap_table_size)", placeholder: "64M", text: $config.maxHeapTableSize)
            }
        }
    }
}

// MARK: - 配置编辑器组件

private struct ConfigSectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            Divider()
        }
        .padding(.top, 4)
    }
}

private struct ConfigField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 240, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

private struct ConfigToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 240, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
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
class MySQLSettingsViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var mysqlVersion = ""
    @Published var serviceName = ""
    @Published var mysqlPort = 3306
    @Published var dataDir = ""
    @Published var configFilePath = ""
    @Published var configContent = ""
    @Published var configFileExists = false
    @Published var config = MySQLConfigModel()
    @Published var uptime = "--"
    @Published var connections = "--"
    @Published var slowQueries = "--"
    @Published var openTables = "--"
    @Published var questionsPerSecond = "--"
    @Published var installedVersions: [MySQLVersionInfo] = []
    @Published var activeVersion = ""
    @Published var isSwitching = false
    @Published var isInstalling = false
    @Published var installLog = ""
    @Published var selectedInstallFormula = ""
    @Published var selectedInstallName = ""
    @Published var showingInstallSheet = false
    
    private let service = MySQLService.shared
    
    func load() async {
        // 先检测版本信息
        await service.detectInstalledVersions()
        installedVersions = service.installedVersions
        activeVersion = service.activeVersion
        
        isAvailable = service.checkMySQLAvailable()
        guard isAvailable else { return }
        
        serviceName = service.getServiceName()
        configFilePath = service.getConfigFilePath()
        configFileExists = service.configFileExists()
        configContent = service.readConfigFile()
        
        async let running = service.isMySQLRunning()
        async let version = service.getMySQLVersion()
        async let port = service.getMySQLPort()
        async let datadir = service.getDataDir()
        
        isRunning = await running
        mysqlVersion = await version
        mysqlPort = await port
        dataDir = await datadir
        
        loadConfigFromFile()
        
        if isRunning {
            await refreshStatus()
        }
    }
    
    func switchVersion(to formula: String) async {
        guard !isSwitching else { return }
        isSwitching = true
        _ = await service.switchVersion(to: formula)
        await load()
        isSwitching = false
    }
    
    func installVersion(formula: String) async {
        guard !isInstalling else { return }
        isInstalling = true
        installLog = ""
        let result = await service.installVersion(formula: formula) { [weak self] output in
            self?.installLog += output
        }
        if case .success = result {
            await service.detectInstalledVersions()
            installedVersions = service.installedVersions
            activeVersion = service.activeVersion
            isAvailable = service.checkMySQLAvailable()
        }
        isInstalling = false
    }
    
    // MARK: - 配置管理
    
    func loadConfigFromFile() {
        let content = service.readConfigFile()
        config = MySQLConfigModel.parse(from: content)
    }
    
    func generateDefaultConfig() {
        let content = service.generateDefaultConfig()
        config = MySQLConfigModel.parse(from: content)
    }
    
    func loadDefaultConfig() {
        generateDefaultConfig()
    }
    
    func parseRawConfig(_ text: String) {
        config = MySQLConfigModel.parse(from: text)
    }
    
    func getRawConfigText() -> String {
        return config.toConfigFile()
    }
    
    func saveConfig(content: String) -> OperationResult {
        return service.saveConfigFile(content: content)
    }
    
    func refreshStatus() async {
        let status = await service.getStatusVariables()
        
        uptime = formatUptime(seconds: Int(status["Uptime"] ?? "0") ?? 0)
        connections = status["Threads_connected"] ?? "--"
        slowQueries = status["Slow_queries"] ?? "--"
        openTables = status["Open_tables"] ?? "--"
        
        let questions = Double(status["Questions"] ?? "0") ?? 0
        let uptimeSeconds = Double(status["Uptime"] ?? "1") ?? 1
        let qps = questions / uptimeSeconds
        questionsPerSecond = String(format: "%.1f", qps)
    }
    
    func startMySQL() async {
        _ = await service.startMySQL()
        await load()
    }
    
    func stopMySQL() async {
        _ = await service.stopMySQL()
        await load()
    }
    
    func restartMySQL() async {
        _ = await service.restartMySQL()
        await load()
    }
    
    func optimizeAllTables() async -> String {
        let dbs = await service.listDatabases()
        let userDBs = dbs.filter { !["information_schema", "mysql", "performance_schema", "sys"].contains($0.name) }
        if userDBs.isEmpty {
            return "没有需要优化的用户数据库"
        }
        var log = ""
        for db in userDBs {
            let tableResult = await service.getTableInfo(database: db.name)
            log += "数据库: \(db.name)\n\(tableResult)\n\n"
        }
        return log
    }
    
    func flushPrivileges() async -> String {
        let result = await service.executeMySQLCommandWithProgress(sql: "FLUSH PRIVILEGES")
        switch result {
        case .success: return "权限已刷新"
        case .failure(let error): return "刷新失败: \(error)"
        }
    }
    
    func showProcessList() async -> String {
        let result = await service.executeMySQLCommandWithProgress(sql: "SHOW FULL PROCESSLIST")
        switch result {
        case .success(let output): return output
        case .failure(let error): return "获取失败: \(error)"
        }
    }
    
    private func formatUptime(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        } else if seconds < 3600 {
            return "\(seconds / 60) 分钟"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours) 小时 \(minutes) 分钟"
        } else {
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            return "\(days) 天 \(hours) 小时"
        }
    }
}

#Preview {
    MySQLSettingsView()
}
