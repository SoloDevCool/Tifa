import SwiftUI

struct PostgresView: View {
    @StateObject private var viewModel = PostgresViewModel()
    @State private var showingCreateDB = false
    @State private var newDBName = ""
    @State private var newDBEncoding = "UTF8"
    @State private var newDBOwner = ""
    @State private var selectedDB: PostgresDatabase?
    @State private var showingDropAlert = false
    @State private var dbToDrop: PostgresDatabase?
    @State private var showingTableInfo = false
    @State private var tableInfoText = ""
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    
    private let encodings = ["UTF8", "LATIN1", "SQL_ASCII", "EUC_JP", "EUC_CN", "EUC_KR", "EUC_TW"]
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRunning ? "PostgreSQL 运行中" : "PostgreSQL 已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.isAvailable {
                    Text(viewModel.pgVersion)
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
            
            if !viewModel.isAvailable && !viewModel.isInstalling && viewModel.installResult == nil {
                // 未安装 - 显示安装界面
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "externaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("PostgreSQL 未安装")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("选择版本，一键安装 PostgreSQL")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("版本", selection: $viewModel.selectedVersion) {
                        ForEach(PostgresService.availableVersions, id: \.formula) { version in
                            Text(version.name).tag(version.formula)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                    
                    Button(action: { Task { await viewModel.install(formula: viewModel.selectedVersion) } }) {
                        Label("安装", systemImage: "arrow.down.circle.fill")
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isInstalling)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.isInstalling || viewModel.installResult != nil {
                // 安装中 / 安装结果
                VStack(spacing: 0) {
                    // 安装状态栏
                    HStack(spacing: 8) {
                        if viewModel.isInstalling {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在安装 \(viewModel.selectedVersion)...")
                                .font(.subheadline)
                        } else if case .success = viewModel.installResult {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("安装完成")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else if case .failure(let error) = viewModel.installResult {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("安装失败: \(error)")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        Spacer()
                        if viewModel.installResult != nil {
                            HStack(spacing: 8) {
                                if case .failure(let error) = viewModel.installResult,
                                   error.lowercased().contains("locked") {
                                    Button(action: { Task { await viewModel.cleanupAndRetry() } }) {
                                        Label("一键修复并重试", systemImage: "wrench")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                Button("关闭") {
                                    viewModel.dismissInstall()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    
                    Divider()
                    
                    // 终端输出
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(viewModel.installOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .id("outputBottom")
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: viewModel.installOutput) { _ in
                            withAnimation {
                                proxy.scrollTo("outputBottom", anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                // 工具栏
                HStack {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    
                    // 启停控制
                    if viewModel.isRunning {
                        Button(action: { Task { await viewModel.stopPostgres() } }) {
                            Label("停止", systemImage: "stop.fill")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button(action: { Task { await viewModel.startPostgres() } }) {
                            Label("启动", systemImage: "play.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Button(action: { Task { await viewModel.restartPostgres() } }) {
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
                        title: "PostgreSQL 未运行",
                        systemImage: "poweroff",
                        description: "请先启动 PostgreSQL 服务以查看数据库"
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
                                    HStack(spacing: 12) {
                                        if !db.owner.isEmpty {
                                            Text("Owner: \(db.owner)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if !db.encoding.isEmpty {
                                            Text(db.encoding)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if !db.size.isEmpty {
                                            Text(db.size)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
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
                    Text("编码")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("编码", selection: $newDBEncoding) {
                        ForEach(encodings, id: \.self) { encoding in
                            Text(encoding).tag(encoding)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("所有者（可选）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField(NSUserName(), text: $newDBOwner)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Spacer()
                    Button("取消") { showingCreateDB = false }
                        .buttonStyle(.bordered)
                    Button("创建") {
                        Task {
                            let result = await viewModel.createDatabase(name: newDBName, encoding: newDBEncoding, owner: newDBOwner)
                            switch result {
                            case .success:
                                await viewModel.refresh()
                                showingCreateDB = false
                                newDBName = ""
                                newDBOwner = ""
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
            .frame(width: 450, height: 320)
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
        ["template0", "template1"].contains(name)
    }
}

// MARK: - ViewModel

@MainActor
class PostgresViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var pgVersion = ""
    @Published var serviceName = ""
    @Published var databases: [PostgresDatabase] = []
    @Published var isLoading = false
    
    // 安装状态（保存在 ViewModel 中，切换视图不会丢失）
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installResult: OperationResult?
    @Published var selectedVersion = "postgresql@16"
    
    private let service = PostgresService.shared
    
    func load() async {
        // 如果正在安装中，不重新检查可用性
        guard !isInstalling else { return }
        
        isAvailable = service.checkPostgresAvailable()
        guard isAvailable else { return }
        
        serviceName = service.getServiceName()
        isLoading = true
        
        async let running = service.isPostgresRunning()
        async let version = service.getPostgresVersion()
        async let dbs = service.listDatabases()
        
        isRunning = await running
        pgVersion = "PostgreSQL \(await version)"
        databases = await dbs
        
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    func startPostgres() async {
        _ = await service.startPostgres()
        await refresh()
    }
    
    func stopPostgres() async {
        _ = await service.stopPostgres()
        await refresh()
    }
    
    func restartPostgres() async {
        _ = await service.restartPostgres()
        await refresh()
    }
    
    func createDatabase(name: String, encoding: String, owner: String) async -> OperationResult {
        return await service.createDatabase(name: name, encoding: encoding, owner: owner)
    }
    
    func dropDatabase(name: String) async -> OperationResult {
        return await service.dropDatabase(name: name)
    }
    
    func getTableInfo(database: String) async -> String {
        return await service.getTableInfo(database: database)
    }
    
    func install(formula: String) async -> OperationResult {
        isInstalling = true
        installOutput = ""
        installResult = nil
        
        let result = await service.installPostgres(formula: formula) { [weak self] output in
            self?.installOutput += output
        }
        
        installResult = result
        isInstalling = false
        
        if case .success = result {
            installOutput += "\n✅ 安装成功！正在启动服务...\n"
            await startPostgres()
            installOutput += "✅ PostgreSQL 服务已启动\n"
        }
        
        return result
    }
    
    /// 清理锁文件并重试安装
    func cleanupAndRetry() async {
        installOutput += "\n🔧 正在清理锁文件...\n"
        let result = await service.cleanupBrewLocks()
        switch result {
        case .success(let msg):
            installOutput += msg + "\n"
            // 清理成功，自动重试安装
            installOutput += "🔄 正在重新安装...\n"
            let _ = await install(formula: selectedVersion)
        case .failure(let error):
            installOutput += "❌ 清理失败: \(error)\n"
            installResult = .failure("清理锁文件失败: \(error)")
        }
    }
    
    /// 安装完成后关闭安装面板，重置状态
    func dismissInstall() {
        if case .success = installResult {
            installResult = nil
            installOutput = ""
            Task { await load() }
        } else {
            installResult = nil
            installOutput = ""
        }
    }
}

#Preview {
    PostgresView()
}
