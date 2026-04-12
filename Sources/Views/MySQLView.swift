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

// MARK: - 配置视图 (重新设计)

struct ConfigView: View {
    @ObservedObject var viewModel: MySQLViewModel
    @State private var isEditingRaw = false
    @State private var rawConfigText = ""
    @State private var showingSaveConfirm = false
    @State private var hasUnsavedChanges = false
    @State private var selectedPreset: ConfigPreset = .production
    
    enum ConfigPreset: String, CaseIterable {
        case development = "开发环境"
        case production = "生产环境"
        case highPerformance = "高性能"
        
        var description: String {
            switch self {
            case .development: return "低资源占用，适合本地开发"
            case .production: return "平衡配置，适合一般生产环境"
            case .highPerformance: return "高资源占用，最大性能"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 顶部状态卡片
                StatusCard(viewModel: viewModel)
                
                // 快速操作
                QuickActionsCard(viewModel: viewModel, showingSaveConfirm: $showingSaveConfirm)
                
                // 预设配置选择
                PresetSelectorCard(
                    selectedPreset: $selectedPreset,
                    onApply: { preset in
                        applyPreset(preset)
                    }
                )
                
                // 配置编辑器
                ConfigurationCard(
                    viewModel: viewModel,
                    isEditingRaw: $isEditingRaw,
                    rawConfigText: $rawConfigText,
                    hasUnsavedChanges: $hasUnsavedChanges,
                    showingSaveConfirm: $showingSaveConfirm
                )
                
                // 维护工具
                MaintenanceCard(viewModel: viewModel)
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
    
    private func applyPreset(_ preset: ConfigPreset) {
        var config = viewModel.config
        switch preset {
        case .development:
            config.maxConnections = "50"
            config.innodbBufferPoolSize = "64M"
            config.innodbLogFileSize = "16M"
            config.waitTimeout = "600"
        case .production:
            config.maxConnections = "200"
            config.innodbBufferPoolSize = "256M"
            config.innodbLogFileSize = "48M"
            config.waitTimeout = "28800"
        case .highPerformance:
            config.maxConnections = "500"
            config.innodbBufferPoolSize = "512M"
            config.innodbLogFileSize = "128M"
            config.waitTimeout = "28800"
        }
        viewModel.config = config
        hasUnsavedChanges = true
    }
}

// MARK: - 状态卡片

struct StatusCard: View {
    @ObservedObject var viewModel: MySQLViewModel
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("MySQL 服务器")
                    .font(.headline)
                Spacer()
                StatusBadge(isRunning: viewModel.isRunning)
                Button(action: {
                    isRefreshing = true
                    Task {
                        await viewModel.refreshStatus()
                        isRefreshing = false
                    }
                }) {
                    Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }
            
            Divider()
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatusItem(title: "版本", value: viewModel.mysqlVersion.isEmpty ? "--" : viewModel.mysqlVersion, icon: "tag")
                StatusItem(title: "端口", value: "\(viewModel.mysqlPort)", icon: "network")
                StatusItem(title: "运行时间", value: viewModel.uptime, icon: "clock")
                StatusItem(title: "连接数", value: viewModel.connections, icon: "person.2")
                StatusItem(title: "QPS", value: viewModel.questionsPerSecond, icon: "speedometer")
                StatusItem(title: "慢查询", value: viewModel.slowQueries, icon: "tortoise")
            }
            
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(viewModel.dataDir)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct StatusBadge: View {
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isRunning ? "运行中" : "已停止")
                .font(.caption)
                .foregroundColor(isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isRunning ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StatusItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 快速操作卡片

struct QuickActionsCard: View {
    @ObservedObject var viewModel: MySQLViewModel
    @Binding var showingSaveConfirm: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text("快速操作")
                    .font(.headline)
            }
            
            HStack(spacing: 12) {
                QuickActionButton(
                    title: viewModel.isRunning ? "重启服务" : "启动服务",
                    icon: viewModel.isRunning ? "arrow.clockwise" : "play.fill",
                    color: viewModel.isRunning ? .orange : .green
                ) {
                    if viewModel.isRunning {
                        await viewModel.restartMySQL()
                    } else {
                        await viewModel.startMySQL()
                    }
                }
                
                QuickActionButton(
                    title: "打开配置",
                    icon: "doc.text",
                    color: .blue
                ) {
                    if !viewModel.configFilePath.isEmpty {
                        NSWorkspace.shared.selectFile(viewModel.configFilePath, inFileViewerRootedAtPath: "")
                    }
                }
                
                QuickActionButton(
                    title: "打开终端",
                    icon: "terminal",
                    color: .purple
                ) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                
                QuickActionButton(
                    title: "保存配置",
                    icon: "square.and.arrow.down",
                    color: .accentColor
                ) {
                    showingSaveConfirm = true
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () async -> Void
    
    @State private var isLoading = false
    
    var body: some View {
        Button(action: {
            isLoading = true
            Task {
                await action()
                isLoading = false
            }
        }) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                }
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - 预设选择卡片

struct PresetSelectorCard: View {
    @Binding var selectedPreset: ConfigView.ConfigPreset
    let onApply: (ConfigView.ConfigPreset) -> Void
    
    private typealias Preset = ConfigView.ConfigPreset
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.purple)
                Text("快速预设")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 12) {
                ForEach(ConfigView.ConfigPreset.allCases, id: \.self) { preset in
                    MySQLPresetButton(
                        preset: preset,
                        isSelected: selectedPreset == preset,
                        onSelect: {
                            selectedPreset = preset
                            onApply(preset)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct MySQLPresetButton: View {
    let preset: ConfigView.ConfigPreset
    let isSelected: Bool
    let onSelect: () -> Void
    
    var icon: String {
        switch preset {
        case .development: return "laptopcomputer"
        case .production: return "server.rack"
        case .highPerformance: return "bolt.fill"
        }
    }
    
    var color: Color {
        switch preset {
        case .development: return .blue
        case .production: return .green
        case .highPerformance: return .orange
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(preset.rawValue)
                    .font(.subheadline.bold())
                Text(preset.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.2) : Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 配置编辑器卡片

struct ConfigurationCard: View {
    @ObservedObject var viewModel: MySQLViewModel
    @Binding var isEditingRaw: Bool
    @Binding var rawConfigText: String
    @Binding var hasUnsavedChanges: Bool
    @Binding var showingSaveConfirm: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                Text("配置编辑")
                    .font(.headline)
                Spacer()
                
                Picker("", selection: $isEditingRaw) {
                    Text("可视化").tag(false)
                    Text("文本").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            
            Divider()
            
            if isEditingRaw {
                TextEditor(text: $rawConfigText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 250)
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
                MySQLConfigEditorView(config: $viewModel.config)
                    .onChange(of: viewModel.config) { _ in
                        hasUnsavedChanges = true
                    }
            }
            
            HStack(spacing: 12) {
                if !viewModel.configFileExists {
                    Button(action: {
                        viewModel.generateDefaultConfig()
                        rawConfigText = viewModel.getRawConfigText()
                        hasUnsavedChanges = true
                    }) {
                        Label("生成默认配置", systemImage: "doc.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if hasUnsavedChanges {
                    Button(action: {
                        showingSaveConfirm = true
                    }) {
                        Label("保存配置", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - 维护卡片

struct MaintenanceCard: View {
    @ObservedObject var viewModel: MySQLViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.secondary)
                Text("维护工具")
                    .font(.headline)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MaintenanceButton(title: "优化所有表", icon: "wand.and.stars", color: .blue) {
                    await viewModel.optimizeAllTables()
                }
                
                MaintenanceButton(title: "刷新权限", icon: "lock.rotation", color: .purple) {
                    await viewModel.flushPrivileges()
                }
                
                MaintenanceButton(title: "查看进程", icon: "list.bullet.rectangle", color: .orange) {
                    await viewModel.showProcessList()
                }
                
                MaintenanceButton(title: "检查状态", icon: "checkmark.shield", color: .green) {
                    await viewModel.refreshStatus()
                    return "状态已刷新\n版本: \(viewModel.mysqlVersion)\n连接数: \(viewModel.connections)\n运行时间: \(viewModel.uptime)"
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct MaintenanceButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () async -> String
    
    @State private var showingResult = false
    @State private var resultText = ""
    @State private var isLoading = false
    
    var body: some View {
        Button(action: {
            isLoading = true
            Task {
                resultText = await action()
                isLoading = false
                showingResult = true
            }
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.subheadline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .sheet(isPresented: $showingResult) {
            CommandResultSheet(commandResultText: resultText, onClose: { showingResult = false })
        }
    }
}

// MARK: - 配置编辑器组件 (重新设计)

struct MySQLConfigEditorView: View {
    @Binding var config: MySQLConfigModel
    @State private var expandedSections: Set<String> = ["basic", "connection", "innodb"]
    
    var body: some View {
        VStack(spacing: 12) {
            ConfigSection(
                title: "基础设置",
                icon: "server.rack",
                isExpanded: expandedSections.contains("basic"),
                onToggle: { toggleSection("basic") }
            ) {
                ConfigRow(label: "端口", description: "MySQL 服务端口", value: $config.mysqldPort)
                ConfigRow(label: "字符集", description: "服务器默认字符集", value: $config.mysqldCharset)
                ConfigRow(label: "排序规则", description: "默认排序规则", value: $config.mysqldCollation)
                ConfigRow(label: "数据目录", description: "数据库文件存储位置", value: $config.mysqldDatadir)
            }
            
            ConfigSection(
                title: "连接设置",
                icon: "network",
                isExpanded: expandedSections.contains("connection"),
                onToggle: { toggleSection("connection") }
            ) {
                ConfigRow(label: "最大连接数", description: "允许的最大并发连接", value: $config.maxConnections)
                ConfigRow(label: "等待超时", description: "空闲连接超时时间(秒)", value: $config.waitTimeout)
                ConfigRow(label: "连接错误上限", description: "阻止主机前的错误次数", value: $config.maxConnectErrors)
            }
            
            ConfigSection(
                title: "InnoDB 引擎",
                icon: "internaldrive",
                isExpanded: expandedSections.contains("innodb"),
                onToggle: { toggleSection("innodb") }
            ) {
                ConfigRow(label: "缓冲池大小", description: "InnoDB 缓存数据的大小", value: $config.innodbBufferPoolSize)
                ConfigRow(label: "日志文件大小", description: "事务日志文件大小", value: $config.innodbLogFileSize)
                ConfigToggleRow(label: "独立表空间", description: "每个表使用独立 .ibd 文件", isOn: $config.innodbFilePerTable)
            }
            
            ConfigSection(
                title: "日志设置",
                icon: "doc.text",
                isExpanded: expandedSections.contains("log"),
                onToggle: { toggleSection("log") }
            ) {
                ConfigToggleRow(label: "慢查询日志", description: "记录执行时间长的查询", isOn: $config.slowQueryLog)
                if config.slowQueryLog {
                    ConfigRow(label: "慢查询阈值", description: "记录超过此时间的查询(秒)", value: $config.longQueryTime)
                }
            }
        }
    }
    
    private func toggleSection(_ id: String) {
        if expandedSections.contains(id) {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }
}

// MARK: - 可折叠配置区段

struct ConfigSection<Content: View>: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(nsColor: .textBackgroundColor))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 8) {
                    content
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - 配置行

struct ConfigRow: View {
    let label: String
    let description: String
    @Binding var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct ConfigToggleRow: View {
    let label: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
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
