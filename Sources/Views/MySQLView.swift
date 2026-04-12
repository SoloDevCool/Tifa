import SwiftUI

struct MySQLView: View {
    @StateObject private var viewModel = MySQLViewModel()
    @State private var selectedTab = 0  // 0: 数据库, 1: 配置
    var onNavigateToVersions: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                // 运行状态（如果有版本）
                if !viewModel.installedVersions.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isRunning ? "MySQL 运行中" : "MySQL 已停止")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if !viewModel.mysqlVersion.isEmpty {
                        Text(viewModel.mysqlVersion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let serviceName = viewModel.activeVersionInfo?.formula {
                        Text(serviceName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    } else if viewModel.installedVersions.first(where: { $0.installed }) != nil {
                        Button("前往激活") {
                            onNavigateToVersions?()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Spacer()
                
                // 标签切换
                Picker("", selection: $selectedTab) {
                    Text("数据库").tag(0)
                    Text("配置").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                
                if viewModel.databases.count > 0 {
                    Text("\(viewModel.databases.count) 个数据库")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 内容区
            if viewModel.isLoading && viewModel.installedVersions.isEmpty {
                // 加载中
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.installedVersions.isEmpty {
                // 没有任何版本安装，引导到软件包页面
                NoVersionInstalledView(onNavigateToVersions: onNavigateToVersions)
            } else if selectedTab == 0 {
                // 数据库列表
                DatabaseListView(viewModel: viewModel)
            } else {
                // 配置页面
                ConfigView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - 未安装任何版本引导视图

struct NoVersionInstalledView: View {
    var onNavigateToVersions: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cylinder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("MYSQL 未安装")
                .font(.title2.bold())
            
            Text("请前往 MySQL 软件包安装 MySQL 版本")
                .foregroundColor(.secondary)
            
            Button(action: {
                onNavigateToVersions?()
            }) {
                Label("前往 MySQL 软件包", systemImage: "arrow.right.circle")
                    .frame(minWidth: 200)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - 数据库列表视图

struct DatabaseListView: View {
    @ObservedObject var viewModel: MySQLViewModel
    @State private var showingCreateDB = false
    @State private var newDBName = ""
    @State private var newDBCharset = "utf8mb4"
    @State private var selectedDB: MySQLDatabase?
    @State private var showingDropAlert = false
    @State private var dbToDrop: MySQLDatabase?
    @State private var showingTableInfo = false
    @State private var tableInfoText = ""
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    
    // 实时日志对话框
    @State private var showingLogDialog = false
    @State private var liveLogText = ""
    
    // 历史日志对话框
    @State private var showingHistoryLog = false
    
    private let charsets = ["utf8mb4", "utf8", "latin1", "gbk", "gb2312", "big5"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                
                if viewModel.isRunning {
                    Button(action: { startLiveLog(action: "stop") }) {
                        Label("停止", systemImage: "stop.fill")
                            .foregroundColor(.red)
                    }
                } else {
                    Button(action: { startLiveLog(action: "start") }) {
                        Label("启动", systemImage: "play.fill")
                            .foregroundColor(.green)
                    }
                }
                
                Button(action: { startLiveLog(action: "restart") }) {
                    Label("重启", systemImage: "arrow.clockwise.circle")
                }
                
                Spacer()
                
                // 历史日志按钮
                Button(action: { showingHistoryLog = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("历史日志")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                
                Button(action: { showingCreateDB = true }) {
                    Label("新建数据库", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isRunning)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            Divider()
            
            // 数据库列表
            if viewModel.isLoading && viewModel.databases.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.isRunning {
                EmptyStateView(
                    title: "MySQL 未运行",
                    systemImage: "poweroff",
                    description: "请先启动 MySQL 服务以查看数据库"
                )
            } else if viewModel.databases.isEmpty {
                EmptyStateView(
                    title: "暂无数据库",
                    systemImage: "cylinder",
                    description: "点击「新建数据库」创建"
                )
            } else {
                List(selection: $selectedDB) {
                    ForEach(viewModel.databases) { db in
                        HStack(spacing: 12) {
                            Image(systemName: "cylinder")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(db.name)
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                Task {
                                    tableInfoText = await viewModel.getTableInfo(database: db.name)
                                    showingTableInfo = true
                                }
                            }) {
                                Label("查看表", systemImage: "list.bullet")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            if !isSystemDatabase(db.name) {
                                Button(action: {
                                    dbToDrop = db
                                    showingDropAlert = true
                                }) {
                                    Label("删除", systemImage: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(db)
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("删除数据库", isPresented: $showingDropAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let db = dbToDrop {
                    Task {
                        let result = await viewModel.dropDatabase(name: db.name)
                        switch result {
                        case .success: await viewModel.refresh()
                        case .failure(let error):
                            commandResultText = error
                            showingCommandResult = true
                        }
                    }
                }
            }
        } message: {
            Text("确定要删除数据库「\(dbToDrop?.name ?? "")」吗？此操作不可撤销！")
        }
        .sheet(isPresented: $showingCreateDB) {
            CreateDatabaseSheet(
                newDBName: $newDBName,
                newDBCharset: $newDBCharset,
                charsets: charsets,
                onCreate: {
                    Task {
                        let result = await viewModel.createDatabase(name: newDBName, charset: newDBCharset)
                        switch result {
                        case .success:
                            await viewModel.refresh()
                            showingCreateDB = false
                            newDBName = ""
                        case .failure(let error):
                            commandResultText = "创建失败: \(error)"
                            showingCommandResult = true
                        }
                    }
                },
                onCancel: { showingCreateDB = false }
            )
        }
        .sheet(isPresented: $showingTableInfo) {
            TableInfoSheet(tableInfoText: tableInfoText, onClose: { showingTableInfo = false })
        }
        .sheet(isPresented: $showingCommandResult) {
            CommandResultSheet(commandResultText: commandResultText, onClose: { showingCommandResult = false })
        }
        .sheet(isPresented: $showingLogDialog) {
            LiveLogSheet(
                logText: $liveLogText,
                onClose: {
                    showingLogDialog = false
                    liveLogText = ""
                }
            )
        }
        .sheet(isPresented: $showingHistoryLog) {
            HistoryLogSheet(
                historyLog: viewModel.serviceLog,
                onClear: { viewModel.serviceLog = "" },
                onClose: { showingHistoryLog = false }
            )
        }
    }
    
    private func isSystemDatabase(_ name: String) -> Bool {
        ["information_schema", "mysql", "performance_schema", "sys"].contains(name)
    }
    
    private func startLiveLog(action: String) {
        liveLogText = ""
        showingLogDialog = true
        
        Task {
            switch action {
            case "start":
                liveLogText += "正在启动 MySQL...\n"
                await viewModel.startMySQLWithLiveLog { output in
                    liveLogText += output + "\n"
                }
            case "stop":
                liveLogText += "正在停止 MySQL...\n"
                await viewModel.stopMySQLWithLiveLog { output in
                    liveLogText += output + "\n"
                }
            case "restart":
                liveLogText += "正在重启 MySQL...\n"
                await viewModel.restartMySQLWithLiveLog { output in
                    liveLogText += output + "\n"
                }
            default:
                break
            }
            liveLogText += "\n✅ 操作完成"
        }
    }
}

// MARK: - 配置视图

struct ConfigView: View {
    @ObservedObject var viewModel: MySQLViewModel
    @State private var isEditingRaw = false
    @State private var rawConfigText = ""
    @State private var showingSaveConfirm = false
    @State private var hasUnsavedChanges = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                        MaintenanceButton(title: "优化所有表", icon: "wand.and.stars") {
                            await viewModel.optimizeAllTables()
                        }
                        
                        MaintenanceButton(title: "刷新权限", icon: "lock.rotation") {
                            await viewModel.flushPrivileges()
                        }
                        
                        MaintenanceButton(title: "查看进程列表", icon: "list.bullet.rectangle") {
                            await viewModel.showProcessList()
                        }
                    }
                } header: {
                    Text("维护")
                        .font(.headline)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await viewModel.loadConfig()
            rawConfigText = viewModel.getRawConfigText()
        }
        .alert("保存配置", isPresented: $showingSaveConfirm) {
            Button("取消", role: .cancel) {}
            Button("仅保存") {
                Task { await viewModel.saveConfig(restart: false, rawText: isEditingRaw ? rawConfigText : "") }
            }
            Button("保存并重启", role: .destructive) {
                Task { await viewModel.saveConfig(restart: true, rawText: isEditingRaw ? rawConfigText : "") }
            }
        } message: {
            Text("配置文件将保存到 \(viewModel.configFilePath)\n是否同时重启 MySQL 使配置生效？")
        }
    }
}

// MARK: - 维护按钮

struct MaintenanceButton: View {
    let title: String
    let icon: String
    let action: () async -> String
    
    @State private var showingResult = false
    @State private var resultText = ""
    
    var body: some View {
        Button(action: {
            Task {
                resultText = await action()
                showingResult = true
            }
        }) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingResult) {
            CommandResultSheet(commandResultText: resultText, onClose: { showingResult = false })
        }
    }
}

// MARK: - 配置编辑器组件

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
            }
            
            // [mysqld] 区段
            ConfigSectionHeader(title: "[mysqld]", icon: "server.rack")
            
            VStack(spacing: 10) {
                ConfigField(title: "端口 (port)", placeholder: "3306", text: $config.mysqldPort)
                ConfigField(title: "字符集 (character-set-server)", placeholder: "utf8mb4", text: $config.mysqldCharset)
                ConfigField(title: "排序规则 (collation-server)", placeholder: "utf8mb4_unicode_ci", text: $config.mysqldCollation)
                ConfigField(title: "数据目录 (datadir)", placeholder: "/opt/homebrew/var/mysql", text: $config.mysqldDatadir)
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

// MARK: - 配置编辑器辅助组件

struct ConfigSectionHeader: View {
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

struct ConfigField: View {
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

struct ConfigToggle: View {
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

private struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}

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

// MARK: - Sheet 组件

struct CreateDatabaseSheet: View {
    @Binding var newDBName: String
    @Binding var newDBCharset: String
    let charsets: [String]
    let onCreate: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("新建数据库")
                    .font(.headline)
                Spacer()
                Button("关闭") { onCancel() }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("数据库名称")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("输入数据库名称", text: $newDBName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("字符集")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("字符集", selection: $newDBCharset) {
                    ForEach(charsets, id: \.self) { charset in
                        Text(charset).tag(charset)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .buttonStyle(.bordered)
                Button("创建") { onCreate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newDBName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 250)
    }
}

struct TableInfoSheet: View {
    let tableInfoText: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("表信息")
                    .font(.headline)
                Spacer()
                Button("关闭") { onClose() }
            }
            
            ScrollView {
                Text(tableInfoText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding(24)
        .frame(width: 650, height: 400)
    }
}

struct CommandResultSheet: View {
    let commandResultText: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("操作结果")
                    .font(.headline)
                Spacer()
                Button("关闭") { onClose() }
            }
            
            ScrollView {
                Text(commandResultText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            
            Button("关闭") { onClose() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 500, height: 300)
    }
}

// MARK: - 实时日志对话框

struct LiveLogSheet: View {
    @Binding var logText: String
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.accentColor)
                Text("运行日志")
                    .font(.headline)
                Spacer()
                Button("关闭") { onClose() }
            }
            
            Divider()
            
            ScrollView {
                ScrollViewReader { proxy in
                    Text(logText.isEmpty ? "等待操作..." : logText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(logText.contains("❌") ? .red : (logText.contains("✅") ? .green : .primary))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("logBottom")
                        .onChange(of: logText) { _ in
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                }
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            HStack {
                Spacer()
                Button("完成") { onClose() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 400)
    }
}

// MARK: - 历史日志对话框

struct HistoryLogSheet: View {
    let historyLog: String
    let onClear: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("历史日志")
                    .font(.headline)
                Spacer()
                Button("清除") { onClear() }
                    .foregroundColor(.red)
                Button("关闭") { onClose() }
            }
            
            Divider()
            
            if historyLog.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无历史日志")
                        .foregroundColor(.secondary)
                    Text("点击启动/停止/重启按钮后会记录日志")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(historyLog)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(historyLog.contains("❌") ? .red : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            HStack {
                Spacer()
                Button("关闭") { onClose() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 400)
    }
}

// MARK: - ViewModel

@MainActor
class MySQLViewModel: ObservableObject {
    // 基本状态
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var mysqlVersion = ""
    @Published var serviceName = ""
    @Published var databases: [MySQLDatabase] = []
    @Published var isLoading = false
    @Published var installedVersions: [MySQLVersionInfo] = []
    
    // 安装相关
    @Published var activeVersion = ""
    @Published var activeVersionInfo: MySQLVersionInfo?
    @Published var isInstalling = false
    @Published var isSwitching = false
    @Published var installLog = ""
    @Published var selectedInstallFormula = ""
    @Published var selectedInstallName = ""
    
    // 服务控制日志
    @Published var serviceLog = ""
    @Published var isServiceActionInProgress = false
    
    // 配置相关
    @Published var mysqlPort = 3306
    @Published var dataDir = ""
    @Published var configFilePath = ""
    @Published var configFileExists = false
    @Published var config = MySQLConfigModel()
    @Published var uptime = "--"
    @Published var connections = "--"
    @Published var slowQueries = "--"
    @Published var openTables = "--"
    @Published var questionsPerSecond = "--"
    
    private let service = MySQLService.shared
    
    func load() async {
        isLoading = true
        await service.detectInstalledVersions()
        installedVersions = service.installedVersions
        activeVersion = service.activeVersion
        
        // 优先使用 PATH 激活的版本，否则使用第一个已安装的版本
        if let activated = installedVersions.first(where: { $0.activated }) {
            activeVersionInfo = activated
        } else if let firstInstalled = installedVersions.first(where: { $0.installed }) {
            activeVersionInfo = firstInstalled
        } else {
            activeVersionInfo = nil
        }
        
        isAvailable = service.checkMySQLAvailable()
        guard isAvailable else {
            isLoading = false
            return
        }
        
        serviceName = service.getServiceName()
        
        async let running = service.isMySQLRunning()
        async let version = service.getMySQLVersion()
        async let dbs = service.listDatabases()
        
        isRunning = await running
        mysqlVersion = "MySQL \(await version)"
        databases = await dbs
        
        isLoading = false
    }
    
    func loadConfig() async {
        await service.detectInstalledVersions()
        installedVersions = service.installedVersions
        activeVersion = service.activeVersion
        
        isAvailable = service.checkMySQLAvailable()
        guard isAvailable else { return }
        
        serviceName = service.getServiceName()
        configFilePath = service.getConfigFilePath()
        configFileExists = service.configFileExists()
        
        async let running = service.isMySQLRunning()
        async let version = service.getMySQLVersion()
        async let port = service.getMySQLPort()
        async let datadir = service.getDataDir()
        
        isRunning = await running
        mysqlVersion = "MySQL \(await version)"
        mysqlPort = await port
        dataDir = await datadir
        
        loadConfigFromFile()
        
        if isRunning {
            await refreshStatus()
        }
    }
    
    func refresh() async {
        await load()
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
            if isAvailable {
                serviceName = service.getServiceName()
            }
        }
        isInstalling = false
    }
    
    func switchVersion(to formula: String) async {
        guard !isSwitching else { return }
        isSwitching = true
        _ = await service.switchVersion(to: formula)
        await load()
        isSwitching = false
    }
    
    func uninstallVersion(formula: String) async -> OperationResult {
        return await service.uninstallVersion(formula: formula)
    }
    
    func startMySQL() async {
        isServiceActionInProgress = true
        serviceLog = ""
        
        _ = await service.startMySQLWithProgress { [weak self] output in
            self?.serviceLog += output + "\n"
        }
        
        isServiceActionInProgress = false
        isRunning = await service.isMySQLRunning()
        await refresh()
    }
    
    func stopMySQL() async {
        isServiceActionInProgress = true
        serviceLog = ""
        
        _ = await service.stopMySQLWithProgress { [weak self] output in
            self?.serviceLog += output + "\n"
        }
        
        isServiceActionInProgress = false
        isRunning = await service.isMySQLRunning()
        await refresh()
    }
    
    func restartMySQL() async {
        isServiceActionInProgress = true
        serviceLog = ""
        
        _ = await service.restartMySQLWithProgress { [weak self] output in
            self?.serviceLog += output + "\n"
        }
        
        isServiceActionInProgress = false
        isRunning = await service.isMySQLRunning()
        await load()
    }
    
    // MARK: - 带实时日志回调的服务控制（用于对话框）
    
    func startMySQLWithLiveLog(onOutput: @escaping @MainActor (String) -> Void) async {
        isServiceActionInProgress = true
        
        _ = await service.startMySQLWithProgress { [weak self] output in
            onOutput(output)
            self?.serviceLog += output + "\n"
        }
        
        isServiceActionInProgress = false
        isRunning = await service.isMySQLRunning()
        await refresh()
    }
    
    func stopMySQLWithLiveLog(onOutput: @escaping @MainActor (String) -> Void) async {
        isServiceActionInProgress = true
        
        _ = await service.stopMySQLWithProgress { [weak self] output in
            onOutput(output)
            self?.serviceLog += output + "\n"
        }
        
        isServiceActionInProgress = false
        isRunning = await service.isMySQLRunning()
        await refresh()
    }
    
    func restartMySQLWithLiveLog(onOutput: @escaping @MainActor (String) -> Void) async {
        isServiceActionInProgress = true
        
        _ = await service.restartMySQLWithProgress { [weak self] output in
            onOutput(output)
            self?.serviceLog += output + "\n"
        }
        
        isServiceActionInProgress = false
        isRunning = await service.isMySQLRunning()
        await load()
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
    
    func createDatabase(name: String, charset: String) async -> OperationResult {
        return await service.createDatabase(name: name, charset: charset)
    }
    
    func dropDatabase(name: String) async -> OperationResult {
        return await service.dropDatabase(name: name)
    }
    
    func getTableInfo(database: String) async -> String {
        return await service.getTableInfo(database: database)
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
    
    func saveConfig(restart: Bool, rawText: String) async {
        let content = rawText.isEmpty ? getRawConfigText() : rawText
        let result = service.saveConfigFile(content: content)
        
        if case .success(_) = result, restart {
            await restartMySQL()
            await loadConfig()
        }
    }
    
    // MARK: - 维护操作
    
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
    MySQLView()
}
