import SwiftUI

// MARK: - Cask 子标签

enum CaskSubTab: String, CaseIterable {
    case installed = "已安装"
    case market = "软件市场"
    
    var icon: String {
        switch self {
        case .installed: return "square.stack.3d.up"
        case .market: return "bag"
        }
    }
}

// MARK: - 软件分类

enum CaskCategory: String, CaseIterable, Identifiable {
    case developer = "开发者工具"
    case browser = "浏览器"
    case editor = "编辑器"
    case communication = "通讯社交"
    case productivity = "效率工具"
    case media = "媒体工具"
    case design = "设计工具"
    case utility = "系统工具"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .developer: return "wrench.and.screwdriver"
        case .browser: return "globe"
        case .editor: return "doc.text"
        case .communication: return "bubble.left.and.bubble.right"
        case .productivity: return "bolt"
        case .media: return "play.rectangle"
        case .design: return "paintbrush"
        case .utility: return "gearshape"
        }
    }
    
    /// 预定义推荐应用
    var recommendedApps: [String] {
        switch self {
        case .developer:
            return ["iterm2", "docker", "postman", "visual-studio-code", "tableplus", "insomnia", "fork", "proxyman", "charles", "android-studio"]
        case .browser:
            return ["google-chrome", "firefox", "arc", "brave-browser", "microsoft-edge"]
        case .editor:
            return ["visual-studio-code", "sublime-text", "typora", "obsidian", "nova", "zed"]
        case .communication:
            return ["wechat", "telegram", "discord", "slack", "skype"]
        case .productivity:
            return ["raycast", "alfred", "bartender", "itsycal", "karabiner-elements", "shottr", "iina", "appcleaner"]
        case .media:
            return ["iina", "vlc", "spotify", "obs", "downie"]
        case .design:
            return ["figma", "squirrel", "eudic"]
        case .utility:
            return ["appcleaner", "keka", "the-unarchiver", "stats", "monitorcontrol", "keepingyouawake"]
        }
    }
}

// MARK: - 市场应用模型

struct MarketApp: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let description: String
    let isInstalled: Bool
    let tap: String
}

// MARK: - CaskView 主视图

struct CaskView: View {
    @StateObject private var viewModel = CaskViewModel()
    @State private var searchText = ""
    @State private var showingDetail = false
    @State private var detailPackage: BrewPackage?
    @State private var detailInfo = ""
    @State private var showingUninstallAlert = false
    @State private var selectedCask: BrewPackage?
    @State private var selectedSubTab: CaskSubTab = .installed
    
    // 软件市场
    @State private var selectedCategory: CaskCategory = .developer
    @State private var showingInstallSheet = false
    @State private var installCaskName = ""
    @State private var marketSearchText = ""
    
    var filteredCasks: [BrewPackage] {
        if searchText.isEmpty { return viewModel.casks }
        return viewModel.casks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 子标签切换
            Picker("", selection: $selectedSubTab) {
                ForEach(CaskSubTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 内容区域
            switch selectedSubTab {
            case .installed:
                installedTabContent
            case .market:
                marketTabContent
            }
        }
        .task {
            await viewModel.loadCasks()
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let cask = viewModel.caskToUninstall {
                    Task { await viewModel.uninstall(cask) }
                }
            }
        } message: {
            Text("确定要卸载 \(viewModel.caskToUninstall?.name ?? "") 吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingDetail) {
            CaskDetailSheet(package: detailPackage, info: detailInfo)
        }
        .sheet(isPresented: $showingInstallSheet) {
            CaskInstallSheet(caskName: installCaskName) {
                showingInstallSheet = false
            }
        }
    }
    
    // MARK: - 已安装标签内容
    
    private var installedTabContent: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                Text("\(viewModel.casks.count) 个 GUI 应用")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.outdatedCasks.isEmpty {
                    Button(action: { Task { await viewModel.upgradeAll() } }) {
                        Label("升级全部", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if viewModel.isLoading && viewModel.casks.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCasks.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "暂无已安装的 GUI 应用" : "未找到匹配结果",
                    systemImage: searchText.isEmpty ? "macwindow" : "magnifyingglass",
                    description: searchText.isEmpty ? "通过 Homebrew Cask 安装的 GUI 应用将显示在这里" : "尝试其他搜索词"
                )
            } else {
                List(selection: $selectedCask) {
                    ForEach(filteredCasks) { cask in
                        CaskRowView(
                            cask: cask,
                            isOutdated: viewModel.outdatedCasks.contains(where: { $0.id == cask.id }),
                            onShowDetail: {
                                detailPackage = cask
                                showingDetail = true
                                Task { await loadDetail(for: cask) }
                            },
                            onUninstall: {
                                viewModel.caskToUninstall = cask
                                showingUninstallAlert = true
                            },
                            onUpgrade: {
                                Task { await viewModel.upgrade(cask) }
                            }
                        )
                        .tag(cask)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索已安装的 GUI 应用")
    }
    
    // MARK: - 软件市场标签内容
    
    private var marketTabContent: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("软件市场")
                    .font(.headline)
                
                Spacer()
                
                Text("发现并安装优质 GUI 应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            HStack(spacing: 0) {
                // 左侧分类栏
                categorySidebar
                
                Divider()
                
                // 右侧应用列表
                marketContent
            }
        }
    }
    
    // MARK: - 分类侧边栏
    
    private var categorySidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) {
                ForEach(CaskCategory.allCases) { category in
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Text(category.rawValue)
                            .font(.subheadline)
                    }
                    .tag(category)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 130)
    }
    
    // MARK: - 市场内容
    
    private var marketContent: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索应用...", text: $marketSearchText)
                    .textFieldStyle(.plain)
                
                if !marketSearchText.isEmpty {
                    Button(action: { marketSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor))
            
            Divider()
            
            // 应用列表
            let apps = viewModel.marketApps(for: selectedCategory)
            
            if viewModel.isMarketLoading {
                ProgressView("加载应用信息...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apps.isEmpty {
                EmptyStateView(
                    title: "暂无应用",
                    systemImage: "bag",
                    description: "该分类暂无推荐应用"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filterApps(apps)) { app in
                            MarketAppRow(app: app) {
                                installCaskName = app.name
                                showingInstallSheet = true
                            }
                            
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task(id: selectedCategory) {
            await viewModel.loadMarketApps(category: selectedCategory)
        }
    }
    
    private func filterApps(_ apps: [MarketApp]) -> [MarketApp] {
        guard !marketSearchText.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(marketSearchText) ||
            $0.description.localizedCaseInsensitiveContains(marketSearchText)
        }
    }
    
    private func loadDetail(for cask: BrewPackage) async {
        let info = await HomebrewService.shared.getCaskInfo(name: cask.name)
        detailInfo = """
        应用名：\(cask.name)
        版本：\(cask.version)
        
        完整信息：
        \(info?.description.isEmpty == false ? info!.description : "暂无详细描述")
        """
    }
}

// MARK: - 已安装 Cask 行视图

struct CaskRowView: View {
    let cask: BrewPackage
    let isOutdated: Bool
    let onShowDetail: () -> Void
    let onUninstall: () -> Void
    let onUpgrade: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(cask.name)
                        .font(.headline)
                    
                    if isOutdated {
                        Text("可更新")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange)
                            .cornerRadius(4)
                    }
                }
                
                if !cask.version.isEmpty {
                    Text(cask.version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isOutdated {
                Button(action: onUpgrade) {
                    Label("升级", systemImage: "arrow.up.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            Button(action: onShowDetail) {
                Label("详情", systemImage: "info.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            
            Button(action: onUninstall) {
                Label("卸载", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 市场应用行视图

struct MarketAppRow: View {
    let app: MarketApp
    let onInstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.isInstalled ? "checkmark.circle.fill" : "macwindow")
                .font(.title2)
                .foregroundColor(app.isInstalled ? .green : .accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                
                if !app.description.isEmpty {
                    Text(app.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    if !app.version.isEmpty {
                        Text(app.version)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(app.tap)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if app.isInstalled {
                Text("已安装")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Button(action: onInstall) {
                    Label("安装", systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Cask 详情弹窗

struct CaskDetailSheet: View {
    let package: BrewPackage?
    let info: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "macwindow")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(package?.name ?? "未知")
                        .font(.title2.bold())
                    Text(package?.version.isEmpty == false ? package!.version : "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("关闭") { dismiss() }
            }
            
            Divider()
            
            ScrollView {
                Text(info.isEmpty ? "加载中..." : info)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
}

// MARK: - 安装日志弹窗

struct CaskInstallSheet: View {
    let caskName: String
    let onClose: () -> Void
    @StateObject private var viewModel: CaskInstallViewModel
    
    init(caskName: String, onClose: @escaping () -> Void) {
        self.caskName = caskName
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: CaskInstallViewModel(caskName: caskName))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 8) {
                if viewModel.isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Image(systemName: "arrow.down.circle")
                Text("安装 \(caskName)")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.isInstalling && viewModel.hasStarted {
                    if viewModel.isSuccess {
                        Label("完成", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if viewModel.isFailed {
                        Label("失败", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isInstalling)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 操作按钮
            HStack {
                if !viewModel.hasStarted {
                    Button(action: {
                        viewModel.hasStarted = true
                        Task { await viewModel.install() }
                    }) {
                        Label("开始安装", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if viewModel.isInstalling {
                    Text("正在安装中...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if !viewModel.isInstalling && viewModel.hasStarted {
                    Button("完成") { onClose() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // 日志区域
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.installLog.isEmpty ? "等待安装..." : viewModel.installLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(viewModel.isFailed ? .red : (viewModel.isSuccess ? .green : .primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .id(viewModel.refreshTrigger)
                }
                .onChange(of: viewModel.installLog) { _ in
                    viewModel.refreshTrigger += 1
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(viewModel.refreshTrigger, anchor: .bottom)
                    }
                }
            }
        }
        .frame(width: 650, height: 450)
    }
}

// MARK: - Cask ViewModel

@MainActor
class CaskViewModel: ObservableObject {
    @Published var casks: [BrewPackage] = []
    @Published var outdatedCasks: [BrewPackage] = []
    @Published var isLoading = false
    @Published var caskToUninstall: BrewPackage?
    
    /// 市场缓存：分类 -> 应用列表
    @Published var marketAppsCache: [String: [MarketApp]] = [:]
    @Published var isMarketLoading = false
    
    private let service = HomebrewService.shared
    private var installedCaskNames: Set<String> = []
    
    func loadCasks() async {
        isLoading = true
        async let casksResult = service.fetchInstalledCasks()
        async let outdatedResult = service.fetchOutdatedCasks()
        casks = await casksResult
        outdatedCasks = await outdatedResult
        installedCaskNames = Set(casks.map { $0.name })
        // 刷新市场已安装状态
        refreshMarketInstalledState()
        isLoading = false
    }
    
    func refresh() async {
        await loadCasks()
    }
    
    func uninstall(_ cask: BrewPackage) async {
        let result = await service.uninstallCask(cask.name)
        switch result {
        case .success:
            casks.removeAll { $0.id == cask.id }
            outdatedCasks.removeAll { $0.id == cask.id }
            installedCaskNames.remove(cask.name)
            refreshMarketInstalledState()
        case .failure(let error):
            print("卸载失败: \(error)")
        }
    }
    
    func upgrade(_ cask: BrewPackage) async {
        let result = await service.upgradeCask(cask.name)
        switch result {
        case .success:
            outdatedCasks.removeAll { $0.id == cask.id }
            await loadCasks()
        case .failure(let error):
            print("升级失败: \(error)")
        }
    }
    
    func upgradeAll() async {
        _ = await service.upgradeAllCasks()
        await loadCasks()
    }
    
    // MARK: - 软件市场
    
    func marketApps(for category: CaskCategory) -> [MarketApp] {
        return marketAppsCache[category.rawValue] ?? []
    }
    
    func loadMarketApps(category: CaskCategory) async {
        if let cached = marketAppsCache[category.rawValue], !cached.isEmpty {
            return
        }
        
        isMarketLoading = true
        let appNames = category.recommendedApps
        
        var apps: [MarketApp] = []
        for name in appNames {
            let info = await service.getCaskInfo(name: name)
            let app = MarketApp(
                id: name,
                name: name,
                version: info?.version ?? "",
                description: info?.description ?? "",
                isInstalled: installedCaskNames.contains(name),
                tap: "homebrew/cask"
            )
            apps.append(app)
        }
        
        marketAppsCache[category.rawValue] = apps
        isMarketLoading = false
    }
    
    private func refreshMarketInstalledState() {
        for (key, var apps) in marketAppsCache {
            for i in apps.indices {
                apps[i] = MarketApp(
                    id: apps[i].id,
                    name: apps[i].name,
                    version: apps[i].version,
                    description: apps[i].description,
                    isInstalled: installedCaskNames.contains(apps[i].name),
                    tap: apps[i].tap
                )
            }
            marketAppsCache[key] = apps
        }
    }
}

// MARK: - 安装 ViewModel

@MainActor
class CaskInstallViewModel: ObservableObject {
    let caskName: String
    @Published var isInstalling = false
    @Published var hasStarted = false
    @Published var isSuccess = false
    @Published var isFailed = false
    @Published var installLog = ""
    @Published var refreshTrigger = 0
    
    init(caskName: String) {
        self.caskName = caskName
    }
    
    func install() async {
        isInstalling = true
        let result = await HomebrewService.shared.installCask(caskName)
        isInstalling = false
        
        switch result {
        case .success(let msg):
            installLog = msg
            isSuccess = true
        case .failure(let msg):
            installLog = msg
            isFailed = true
        }
    }
}

#Preview {
    CaskView()
}
