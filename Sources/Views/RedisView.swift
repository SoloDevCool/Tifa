import SwiftUI

struct RedisView: View {
    @StateObject private var viewModel = RedisViewModel()
    @State private var selectedDBIndex = 0
    @State private var selectedKey: RedisKeyInfo?
    @State private var showingKeyDetail = false
    @State private var keyDetailText = ""
    @State private var showingNewKey = false
    @State private var newKeyName = ""
    @State private var newKeyValue = ""
    @State private var newKeyTTL = ""
    @State private var showingDeleteAlert = false
    @State private var keyToDelete: RedisKeyInfo?
    @State private var showingFlushAlert = false
    @State private var showingCommandResult = false
    @State private var commandResultText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRunning ? "Redis 运行中" : "Redis 已停止")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if viewModel.isAvailable {
                    Text(viewModel.redisVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let dbInfo = viewModel.dbInfo {
                        Text(dbInfo)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                if !viewModel.keys.isEmpty {
                    Text("\(viewModel.keys.count) 个键")
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
                    Image(systemName: "internaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Redis 未安装")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("点击下方按钮一键安装 Redis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button(action: { Task { await viewModel.install() } }) {
                        Label("安装 Redis", systemImage: "arrow.down.circle.fill")
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
                            Text("正在安装 Redis...")
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
                        Button(action: { Task { await viewModel.stopRedis() } }) {
                            Label("停止", systemImage: "stop.fill").foregroundColor(.red)
                        }
                    } else {
                        Button(action: { Task { await viewModel.startRedis() } }) {
                            Label("启动", systemImage: "play.fill").foregroundColor(.green)
                        }
                    }
                    
                    Button(action: { Task { await viewModel.restartRedis() } }) {
                        Label("重启", systemImage: "arrow.clockwise.circle")
                    }
                    
                    Spacer()
                    
                    Button(action: { showingNewKey = true }) {
                        Label("新建键", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isRunning)
                    
                    Button(action: { showingFlushAlert = true }) {
                        Label("清空数据库", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(!viewModel.isRunning)
                }
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
                
                // 键列表
                if viewModel.isLoading && viewModel.keys.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.isRunning {
                    EmptyStateView(
                        title: "Redis 未运行",
                        systemImage: "poweroff",
                        description: "请先启动 Redis 服务以查看数据"
                    )
                } else if viewModel.keys.isEmpty {
                    EmptyStateView(
                        title: "当前数据库为空",
                        systemImage: "archivebox",
                        description: "点击「新建键」添加数据"
                    )
                } else {
                    List(selection: $selectedKey) {
                        ForEach(viewModel.keys) { key in
                            HStack {
                                Text(key.key)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(key.type)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(typeColor(key.type).opacity(0.15))
                                    .foregroundColor(typeColor(key.type))
                                    .cornerRadius(4)
                                    .frame(width: 60)
                                Text(key.ttl <= 0 ? "永不过期" : formatTTL(key.ttl))
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundColor(key.ttl <= 0 ? .secondary : .primary)
                                HStack(spacing: 4) {
                                    Button(action: {
                                        Task {
                                            keyDetailText = await viewModel.getValue(key: key.key)
                                            showingKeyDetail = true
                                        }
                                    }) {
                                        Label("查看", systemImage: "eye")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(key.key.hasPrefix("..."))
                                    
                                    Button(action: {
                                        keyToDelete = key
                                        showingDeleteAlert = true
                                    }) {
                                        Label("删除", systemImage: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                    .disabled(key.key.hasPrefix("..."))
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(key)
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .alert("删除键", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let key = keyToDelete {
                    Task {
                        let result = await viewModel.deleteKey(key: key.key)
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
            Text("确定要删除键「\(keyToDelete?.key ?? "")」吗？")
        }
        .alert("清空数据库", isPresented: $showingFlushAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                Task {
                    let result = await viewModel.flushDB()
                    switch result {
                    case .success: await viewModel.refresh()
                    case .failure(let error):
                        commandResultText = error
                        showingCommandResult = true
                    }
                }
            }
        } message: {
            Text("确定要清空当前数据库的所有数据吗？此操作不可撤销！")
        }
        .sheet(isPresented: $showingKeyDetail) {
            VStack(spacing: 16) {
                HStack {
                    Text("键值详情")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingKeyDetail = false }
                }
                ScrollView {
                    Text(keyDetailText)
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
        .sheet(isPresented: $showingNewKey) {
            VStack(spacing: 20) {
                HStack {
                    Text("新建键")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingNewKey = false }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("键名").font(.subheadline).foregroundColor(.secondary)
                    TextField("输入键名", text: $newKeyName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("值").font(.subheadline).foregroundColor(.secondary)
                    TextEditor(text: $newKeyValue)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .border(Color(nsColor: .separatorColor))
                        .cornerRadius(4)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("过期时间（秒，0 为永不过期）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("0", text: $newKeyTTL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    Spacer()
                }
                
                HStack {
                    Spacer()
                    Button("取消") { showingNewKey = false }
                        .buttonStyle(.bordered)
                    Button("创建") {
                        Task {
                            let ttl = Int(newKeyTTL) ?? 0
                            let result = await viewModel.setKey(key: newKeyName, value: newKeyValue, ttl: ttl)
                            switch result {
                            case .success:
                                await viewModel.refresh()
                                showingNewKey = false
                                newKeyName = ""
                                newKeyValue = ""
                                newKeyTTL = ""
                            case .failure(let error):
                                commandResultText = "创建失败: \(error)"
                                showingCommandResult = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newKeyName.isEmpty || newKeyValue.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 500, height: 380)
        }
        .sheet(isPresented: $showingCommandResult) {
            VStack(spacing: 16) {
                HStack {
                    Text("操作结果").font(.headline)
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
    
    private func typeColor(_ type: String) -> Color {
        switch type {
        case "string": return .blue
        case "list": return .green
        case "set": return .orange
        case "zset": return .purple
        case "hash": return .cyan
        default: return .secondary
        }
    }
    
    private func formatTTL(_ ttl: Int) -> String {
        if ttl >= 86400 {
            return "\(ttl / 86400) 天"
        } else if ttl >= 3600 {
            return "\(ttl / 3600) 小时"
        } else {
            return "\(ttl) 秒"
        }
    }
}

// MARK: - ViewModel

@MainActor
class RedisViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var redisVersion = ""
    @Published var dbInfo: String?
    @Published var keys: [RedisKeyInfo] = []
    @Published var isLoading = false
    
    @Published var isInstalling = false
    @Published var installOutput = ""
    @Published var installResult: OperationResult?
    
    private let service = RedisService.shared
    
    func load() async {
        guard !isInstalling else { return }
        
        isAvailable = service.checkRedisAvailable()
        guard isAvailable else { return }
        
        isLoading = true
        
        async let running = service.isRedisRunning()
        async let version = service.getRedisVersion()
        async let dbSizes = service.getDBSizes()
        async let keyList = service.listKeys()
        
        isRunning = await running
        redisVersion = await version
        let dbSizeList = await dbSizes
        keys = await keyList
        
        if !dbSizeList.isEmpty {
            dbInfo = dbSizeList.joined(separator: ", ")
        }
        
        isLoading = false
    }
    
    func refresh() async { await load() }
    
    func startRedis() async {
        _ = await service.startRedis()
        await refresh()
    }
    
    func stopRedis() async {
        _ = await service.stopRedis()
        await refresh()
    }
    
    func restartRedis() async {
        _ = await service.restartRedis()
        await refresh()
    }
    
    func getValue(key: String) async -> String {
        return await service.getValue(key: key)
    }
    
    func deleteKey(key: String) async -> OperationResult {
        return await service.deleteKey(key: key)
    }
    
    func setKey(key: String, value: String, ttl: Int) async -> OperationResult {
        return await service.setKey(key: key, value: value, ttl: ttl)
    }
    
    func flushDB() async -> OperationResult {
        return await service.flushDB()
    }
    
    func install() async -> OperationResult {
        isInstalling = true
        installOutput = ""
        installResult = nil
        
        let formula = RedisService.availableVersions.first?.formula ?? "redis"
        let result = await service.installRedis(formula: formula) { [weak self] output in
            self?.installOutput += output
        }
        
        installResult = result
        isInstalling = false
        
        if case .success = result {
            installOutput += "\n✅ 安装成功！正在启动服务...\n"
            await startRedis()
            installOutput += "✅ Redis 服务已启动\n"
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
    RedisView()
}
