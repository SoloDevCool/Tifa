import SwiftUI

struct MySQLView: View {
    @StateObject private var viewModel = MySQLViewModel()
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
    
    private let charsets = ["utf8mb4", "utf8", "latin1", "gbk", "gb2312", "big5"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRunning ? "MySQL 运行中" : "MySQL 已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.isAvailable {
                    Text(viewModel.mysqlVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.serviceName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
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
            
            if !viewModel.isAvailable {
                EmptyStateView(
                    title: "MySQL 未安装",
                    systemImage: "xmark.icloud",
                    description: "请先通过 Homebrew 安装：brew install mysql"
                )
            } else {
                // 工具栏
                HStack {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    
                    // 启停控制
                    if viewModel.isRunning {
                        Button(action: { Task { await viewModel.stopMySQL() } }) {
                            Label("停止", systemImage: "stop.fill")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button(action: { Task { await viewModel.startMySQL() } }) {
                            Label("启动", systemImage: "play.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Button(action: { Task { await viewModel.restartMySQL() } }) {
                        Label("重启", systemImage: "arrow.clockwise.circle")
                    }
                    
                    Spacer()
                    
                    Button(action: { showingCreateDB = true }) {
                        Label("新建数据库", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isRunning)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
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
        }
        .task {
            await viewModel.load()
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
            VStack(spacing: 20) {
                HStack {
                    Text("新建数据库")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingCreateDB = false }
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
                    Button("取消") { showingCreateDB = false }
                        .buttonStyle(.bordered)
                    Button("创建") {
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
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newDBName.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 450, height: 250)
        }
        .sheet(isPresented: $showingTableInfo) {
            VStack(spacing: 16) {
                HStack {
                    Text("表信息")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingTableInfo = false }
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
                        .font(.system(.body, design: .monospaced))
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
            .frame(width: 500, height: 300)
        }
    }
    
    private func isSystemDatabase(_ name: String) -> Bool {
        ["information_schema", "mysql", "performance_schema", "sys"].contains(name)
    }
}

// MARK: - ViewModel

@MainActor
class MySQLViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var mysqlVersion = ""
    @Published var serviceName = ""
    @Published var databases: [MySQLDatabase] = []
    @Published var isLoading = false
    
    private let service = MySQLService.shared
    
    func load() async {
        isAvailable = service.checkMySQLAvailable()
        guard isAvailable else { return }
        
        serviceName = service.getServiceName()
        isLoading = true
        
        async let running = service.isMySQLRunning()
        async let version = service.getMySQLVersion()
        async let dbs = service.listDatabases()
        
        isRunning = await running
        mysqlVersion = "MySQL \(await version)"
        databases = await dbs
        
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    func startMySQL() async {
        let result = await service.startMySQL()
        if case .failure = result {
            // 错误通过 lastError 暴露
        }
        await refresh()
    }
    
    func stopMySQL() async {
        let result = await service.stopMySQL()
        if case .failure = result {
            // 错误通过 lastError 暴露
        }
        await refresh()
    }
    
    func restartMySQL() async {
        let result = await service.restartMySQL()
        if case .failure = result {
            // 错误通过 lastError 暴露
        }
        await refresh()
    }
    
    func createDatabase(name: String, charset: String) async -> OperationResult {
        return await service.createDatabase(name: name, charset: charset)
    }
    
    func dropDatabase(name: String) async -> OperationResult {
        return await service.dropDatabase(name: name)
    }
    
    func getTableInfo(database: String) async -> String {
        let result = await service.getTableInfo(database: database)
        return result
    }
}

#Preview {
    MySQLView()
}
