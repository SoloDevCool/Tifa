import SwiftUI

struct MongoDbView: View {
    @StateObject private var viewModel = MongoDbViewModel()
    @State private var showingCreateDB = false
    @State private var newDBName = ""
    @State private var selectedDB: MongoDatabase?
    @State private var showingDropAlert = false
    @State private var dbToDrop: MongoDatabase?
    @State private var showingCollectionInfo = false
    @State private var collectionInfoText = ""
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    @State private var showingUninstallConfirm = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRunning ? "MongoDB 运行中" : "MongoDB 已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.isAvailable {
                    Text(viewModel.mongoVersion)
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
                // 未安装
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("MongoDB 未安装")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("点击下方按钮通过 Homebrew 安装 MongoDB Community")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button(action: { Task { await viewModel.install() } }) {
                        Label("安装 MongoDB", systemImage: "arrow.down.circle.fill")
                            .frame(width: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.isInstalling || viewModel.installResult != nil {
                // 安装中 / 结果
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if viewModel.isInstalling {
                            ProgressView().controlSize(.small)
                            Text("正在安装 MongoDB...")
                                .font(.subheadline)
                        } else if case .success = viewModel.installResult {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("安装完成").font(.subheadline).foregroundColor(.green)
                        } else if case .failure(let error) = viewModel.installResult {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            Text("安装失败: \(error)").font(.subheadline).foregroundColor(.red)
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
                                Button("关闭") { viewModel.dismissInstall() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                    Divider()
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
                            withAnimation { proxy.scrollTo("outputBottom", anchor: .bottom) }
                        }
                    }
                }
            } else {
                // 工具栏
                HStack {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    
                    if viewModel.isRunning {
                        Button(action: { Task { await viewModel.stopMongoDb() } }) {
                            Label("停止", systemImage: "stop.fill")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button(action: { Task { await viewModel.startMongoDb() } }) {
                            Label("启动", systemImage: "play.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Button(action: { Task { await viewModel.restartMongoDb() } }) {
                        Label("重启", systemImage: "arrow.clockwise.circle")
                    }
                    
                    Spacer()
                    
                    Button(action: { showingCreateDB = true }) {
                        Label("新建数据库", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isRunning)
                    
                    Button(action: { showingUninstallConfirm = true }) {
                        Label("卸载", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
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
                        title: "MongoDB 未运行",
                        systemImage: "poweroff",
                        description: "请先启动 MongoDB 服务以查看数据库"
                    )
                } else if viewModel.databases.isEmpty {
                    EmptyStateView(
                        title: "暂无数据库",
                        systemImage: "leaf.fill",
                        description: "点击「新建数据库」创建"
                    )
                } else {
                    List(selection: $selectedDB) {
                        ForEach(viewModel.databases) { db in
                            HStack(spacing: 12) {
                                Image(systemName: db.empty ? "cylinder" : "cylinder.fill")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(db.name)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        Text(db.sizeOnDisk)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if db.empty {
                                            Text("空")
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.15))
                                                .foregroundColor(.orange)
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    Task {
                                        collectionInfoText = await viewModel.getCollectionInfo(database: db.name)
                                        showingCollectionInfo = true
                                    }
                                }) {
                                    Label("集合", systemImage: "list.bullet")
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
        .alert("确认卸载", isPresented: $showingUninstallConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                Task {
                    let result = await viewModel.uninstall()
                    if case .failure(let error) = result {
                        commandResultText = error
                        showingCommandResult = true
                    }
                }
            }
        } message: {
            Text("确定要卸载 MongoDB 吗？数据库数据将被保留。")
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
                
                HStack {
                    Spacer()
                    Button("取消") { showingCreateDB = false }
                        .buttonStyle(.bordered)
                    Button("创建") {
                        Task {
                            let result = await viewModel.createDatabase(name: newDBName)
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
            .frame(width: 400, height: 200)
        }
        .sheet(isPresented: $showingCollectionInfo) {
            VStack(spacing: 16) {
                HStack {
                    Text("集合信息")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingCollectionInfo = false }
                }
                ScrollView {
                    Text(collectionInfoText)
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
        ["admin", "local", "config"].contains(name)
    }
}

// MARK: - ViewModel

@MainActor
class MongoDbViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var mongoVersion = ""
    @Published var serviceName = ""
    @Published var databases: [MongoDatabase] = []
    @Published var isLoading = false
    
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installResult: OperationResult?
    
    private let service = MongoDbService.shared
    
    func load() async {
        guard !isInstalling else { return }
        
        isAvailable = service.checkMongoDbAvailable()
        guard isAvailable else { return }
        
        isLoading = true
        serviceName = service.getServiceName()
        
        async let running = service.isMongoDbRunning()
        async let version = service.getMongoDbVersion()
        async let dbs = service.listDatabases()
        
        isRunning = await running
        mongoVersion = await version
        databases = await dbs
        
        isLoading = false
    }
    
    func refresh() async { await load() }
    
    func startMongoDb() async {
        _ = await service.startMongoDb()
        await refresh()
    }
    
    func stopMongoDb() async {
        _ = await service.stopMongoDb()
        await refresh()
    }
    
    func restartMongoDb() async {
        _ = await service.restartMongoDb()
        await refresh()
    }
    
    func createDatabase(name: String) async -> OperationResult {
        return await service.createDatabase(name: name)
    }
    
    func dropDatabase(name: String) async -> OperationResult {
        return await service.dropDatabase(name: name)
    }
    
    func getCollectionInfo(database: String) async -> String {
        return await service.getCollectionInfo(database: database)
    }
    
    func uninstall() async -> OperationResult {
        _ = await service.stopMongoDb()
        let result = await service.uninstallMongoDb()
        if case .success = result {
            isAvailable = false
            isRunning = false
            databases = []
        }
        return result
    }
    
    func install() async -> OperationResult {
        isInstalling = true
        installOutput = ""
        installResult = nil
        
        let formula = MongoDbService.availableVersions.first?.formula ?? "mongodb-community"
        let result = await service.installMongoDb(formula: formula) { [weak self] output in
            self?.installOutput += output
        }
        
        installResult = result
        isInstalling = false
        
        if case .success = result {
            installOutput += "\n✅ 安装成功！正在启动服务...\n"
            await startMongoDb()
            installOutput += "✅ MongoDB 服务已启动\n"
        }
        return result
    }
    
    func cleanupAndRetry() async {
        installOutput += "\n🔧 正在清理锁文件...\n"
        let script = """
        find ~/Library/Caches/Homebrew/downloads -name "*.incomplete" -delete 2>/dev/null
        find ~/Library/Caches/Homebrew -name "*.lock" -delete 2>/dev/null
        echo "✅ 锁文件已清理"
        """
        
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<OperationResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success(output))
                    } else {
                        continuation.resume(returning: .failure("清理失败"))
                    }
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
        
        switch result {
        case .success(let msg):
            installOutput += msg + "\n🔄 正在重新安装...\n"
            let _ = await install()
        case .failure(let error):
            installOutput += "❌ 清理失败: \(error)\n"
            installResult = .failure("清理失败: \(error)")
        }
    }
    
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
    MongoDbView()
}
