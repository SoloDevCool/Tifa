import SwiftUI

// MARK: - 自定义环境键

private struct NavigateToMySQLVersionsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var navigateToMySQLVersions: (() -> Void)? {
        get { self[NavigateToMySQLVersionsKey.self] }
        set { self[NavigateToMySQLVersionsKey.self] = newValue }
    }
}

// MARK: - 分类分组

enum CategoryGroup: String, CaseIterable, Identifiable {
    case basic = "基础服务"
    case language = "语言管理器"
    case database = "数据库"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .basic: return "wrench.and.screwdriver"
        case .language: return "chevron.left.forwardslash.chevron.right"
        case .database: return "cylinder"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - 分类定义

enum ToolCategory: String, CaseIterable, Identifiable {
    case homebrew = "Homebrew"
    case xcode = "Xcode"
    case rvm = "RVM"
    case pyenv = "pyenv"
    case mysql = "MySQL"
    case postgres = "PostgreSQL"
    case redis = "Redis"
    case mongodb = "MongoDB"
    case nvm = "NVM"
    case rustup = "rustup"
    case jenv = "JEnv"
    case gvm = "GVM"
    case system = "系统监控"
    case env = "环境变量"
    case hosts = "Hosts"
    case toolSettings = "工具设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .homebrew: return "shippingbox"
        case .xcode: return "hammer"
        case .rvm: return "cube"
        case .pyenv: return "leaf"
        case .mysql: return "cylinder"
        case .postgres: return "externaldrive"
        case .redis: return "arrow.left.arrow.right"
        case .mongodb: return "leaf.fill"
        case .nvm: return "chevron.left.forwardslash.chevron.right"
        case .rustup: return "wrench.and.screwdriver.fill"
        case .jenv: return "leaf.arrow.triangle.circlepath"
        case .gvm: return "chevron.left.forwardslash.chevron.right"
        case .system: return "chart.bar"
        case .env: return "gearshape.2"
        case .hosts: return "network"
        case .toolSettings: return "gearshape"
        }
    }
    
    var group: CategoryGroup {
        switch self {
        case .system, .homebrew, .xcode, .env, .hosts: return .basic
        case .rvm, .pyenv, .nvm, .jenv, .gvm, .rustup: return .language
        case .mysql, .postgres, .redis, .mongodb: return .database
        case .toolSettings: return .settings
        }
    }
    
    /// 按分组排列的分类顺序
    static let grouped: [(group: CategoryGroup, items: [ToolCategory])] = {
        var result: [(group: CategoryGroup, items: [ToolCategory])] = []
        for group in CategoryGroup.allCases {
            let items = allCases.filter { $0.group == group }
            // 基础服务内按指定顺序排列
            let ordered: [ToolCategory] = {
                switch group {
                case .basic: return [.system, .homebrew, .xcode, .env, .hosts]
                case .language: return [.rvm, .pyenv, .nvm, .jenv, .gvm, .rustup]
                case .database: return items
                case .settings: return items
                }
            }()
            result.append((group: group, items: ordered))
        }
        return result
    }()
}

// MARK: - Homebrew 子菜单

enum HomebrewTab: String, CaseIterable, Identifiable {
    case installed = "已安装"
    case cask = "GUI 应用"
    case tap = "Tap"
    case search = "搜索"
    case outdated = "可用更新"
    case mirror = "镜像源"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .installed: return "square.stack.3d.up"
        case .cask: return "macwindow"
        case .tap: return "arrow.triangle.branch"
        case .search: return "magnifyingglass"
        case .outdated: return "arrow.triangle.2.circlepath"
        case .mirror: return "globe"
        case .settings: return "gear"
        }
    }
}

// MARK: - RVM 子菜单

enum RVMTab: String, CaseIterable, Identifiable {
    case packages = "Ruby 软件包"
    case gemsets = "Gemset"
    case gemSource = "Gem 源"
    case source = "安装源"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .packages: return "shippingbox"
        case .gemsets: return "folder"
        case .gemSource: return "diamond"
        case .source: return "globe"
        case .settings: return "gear"
        }
    }
}

// MARK: - pyenv 子菜单

enum PyenvTab: String, CaseIterable, Identifiable {
    case packages = "Python 软件包"
    case pipSource = "Pip 源"
    case source = "安装源"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .packages: return "shippingbox"
        case .pipSource: return "diamond"
        case .source: return "globe"
        case .settings: return "gear"
        }
    }
}

// MARK: - PostgreSQL 子菜单

enum PostgresTab: String, CaseIterable, Identifiable {
    case databases = "数据库"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .databases: return "cylinder"
        case .settings: return "gear"
        }
    }
}

// MARK: - Redis 子菜单

enum RedisTab: String, CaseIterable, Identifiable {
    case keys = "键管理"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .keys: return "archivebox"
        case .settings: return "gear"
        }
    }
}

// MARK: - NVM 子菜单

enum NVMTab: String, CaseIterable, Identifiable {
    case packages = "NVM 软件包"
    case npmSource = "NPM 源"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .packages: return "shippingbox"
        case .npmSource: return "diamond"
        case .settings: return "gear"
        }
    }
}

// MARK: - JEnv 子菜单

enum JenvTab: String, CaseIterable, Identifiable {
    case versions = "Java 软件包"
    case maven = "Maven"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .versions: return "cube"
        case .maven: return "shippingbox"
        case .settings: return "gear"
        }
    }
}

// MARK: - rustup 子菜单

enum RustupTab: String, CaseIterable, Identifiable {
    case packages = "Rust 工具链"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .packages: return "wrench.and.screwdriver.fill"
        case .settings: return "gear"
        }
    }
}

// MARK: - GVM 子菜单

enum GvmTab: String, CaseIterable, Identifiable {
    case packages = "Go 软件包"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .packages: return "shippingbox"
        case .settings: return "gear"
        }
    }
}

// MARK: - MongoDB 子菜单

enum MongoDbTab: String, CaseIterable, Identifiable {
    case databases = "数据库"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .databases: return "leaf.fill"
        case .settings: return "gear"
        }
    }
}

// MARK: - 系统监控 子菜单

enum SystemTab: String, CaseIterable, Identifiable {
    case metrics = "系统指标"
    case processes = "进程监控"
    case ports = "端口监控"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .metrics: return "gauge"
        case .processes: return "list.bullet"
        case .ports: return "network"
        }
    }
}

// MARK: - MySQL 子菜单

enum MySQLTab: String, CaseIterable, Identifiable {
    case databases = "数据库"
    case versions = "MYSQL 软件包"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .databases: return "cylinder"
        case .versions: return "square.stack.3d.up"
        }
    }
}

// MARK: - 主视图

struct ContentView: View {
    @StateObject private var homebrewService = HomebrewService.shared
    @State private var selectedCategory: ToolCategory = .homebrew
    @State private var selectedHomebrewTab: HomebrewTab = .installed
    @State private var selectedRVMTab: RVMTab = .packages
    @State private var selectedMySQLTab: MySQLTab = .databases
    @State private var selectedPyenvTab: PyenvTab = .packages
    @State private var selectedPostgresTab: PostgresTab = .databases
    @State private var selectedRedisTab: RedisTab = .keys
    @State private var selectedMongoDbTab: MongoDbTab = .databases
    @State private var selectedNVMTab: NVMTab = .packages
    @State private var selectedRustupTab: RustupTab = .packages
    @State private var selectedJenvTab: JenvTab = .versions
    @State private var selectedGvmTab: GvmTab = .packages
    @State private var selectedSystemTab: SystemTab = .metrics
    
    var body: some View {
        HStack(spacing: 0) {
            // 第一列：分类选择
            categorySidebar
            
            Divider()
            
            // 第二列：子菜单（环境变量和工具设置不需要）
            if selectedCategory != .env && selectedCategory != .hosts && selectedCategory != .toolSettings && selectedCategory != .xcode {
                subSidebar
                
                Divider()
            }
            
            // 第三列：内容页
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .overlay {
            if homebrewService.isLoading || RVMService.shared.isLoading || MySQLService.shared.isLoading || PyenvService.shared.isLoading || PostgresService.shared.isLoading || RedisService.shared.isLoading || NvmService.shared.isLoading || MongoDbService.shared.isLoading || RustupService.shared.isLoading || JenvService.shared.isLoading || GvmService.shared.isLoading {
                LoadingOverlay(message: homebrewService.isLoading ? homebrewService.loadingMessage : (RVMService.shared.isLoading ? RVMService.shared.loadingMessage : (MySQLService.shared.isLoading ? MySQLService.shared.loadingMessage : (PyenvService.shared.isLoading ? PyenvService.shared.loadingMessage : (PostgresService.shared.isLoading ? PostgresService.shared.loadingMessage : (RedisService.shared.isLoading ? RedisService.shared.loadingMessage : (NvmService.shared.isLoading ? NvmService.shared.loadingMessage : (MongoDbService.shared.isLoading ? MongoDbService.shared.loadingMessage : (RustupService.shared.isLoading ? RustupService.shared.loadingMessage : (JenvService.shared.isLoading ? JenvService.shared.loadingMessage : GvmService.shared.loadingMessage))))))))))
            }
        }
        .alert("错误", isPresented: .constant(homebrewService.lastError != nil)) {
            Button("确定") {
                homebrewService.lastError = nil
            }
        } message: {
            Text(homebrewService.lastError ?? "")
        }
    }
    
    // MARK: - 第一列：工具分类
    
    private var categorySidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedCategory) {
                ForEach(ToolCategory.grouped, id: \.group.id) { section in
                    Section {
                        ForEach(section.items) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Image(systemName: section.group.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(section.group.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 140)
    }
    
    // MARK: - 第二列：子菜单
    
    private var subSidebar: some View {
        VStack(spacing: 0) {
            Text(selectedCategory.rawValue)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            if selectedCategory == .homebrew {
                List(selection: $selectedHomebrewTab) {
                    ForEach(HomebrewTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .rvm {
                List(selection: $selectedRVMTab) {
                    ForEach(RVMTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .mysql {
                List(selection: $selectedMySQLTab) {
                    ForEach(MySQLTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .pyenv {
                List(selection: $selectedPyenvTab) {
                    ForEach(PyenvTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .postgres {
                List(selection: $selectedPostgresTab) {
                    ForEach(PostgresTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .redis {
                List(selection: $selectedRedisTab) {
                    ForEach(RedisTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .mongodb {
                List(selection: $selectedMongoDbTab) {
                    ForEach(MongoDbTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .nvm {
                List(selection: $selectedNVMTab) {
                    ForEach(NVMTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .rustup {
                List(selection: $selectedRustupTab) {
                    ForEach(RustupTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .jenv {
                List(selection: $selectedJenvTab) {
                    ForEach(JenvTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .gvm {
                List(selection: $selectedGvmTab) {
                    ForEach(GvmTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .system {
                List(selection: $selectedSystemTab) {
                    ForEach(SystemTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            } else if selectedCategory == .toolSettings {
                // 工具设置 - 单页面，无子菜单
                VStack {
                    Spacer()
                    Text("工具设置")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
            } else {
                VStack {
                    Spacer()
                    Text(selectedCategory == .env ? "环境变量管理" : (selectedCategory == .xcode ? "Xcode 管理" : "Hosts 文件管理"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
            }
        }
        .frame(width: 160)
    }
    
    // MARK: - 第三列：内容
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedCategory {
        case .homebrew:
            switch selectedHomebrewTab {
            case .installed:
                InstalledPackagesView()
            case .cask:
                CaskView()
            case .tap:
                TapView()
            case .search:
                SearchView()
            case .outdated:
                OutdatedPackagesView()
            case .mirror:
                MirrorSourceView()
            case .settings:
                SettingsView()
            }
        case .rvm:
            switch selectedRVMTab {
            case .packages:
                RubyPackagesView()
            case .gemsets:
                RVMGemsetView()
            case .gemSource:
                GemSourceView()
            case .source:
                RVMSourceView()
            case .settings:
                RVMSettingsView()
            }
        case .mysql:
            switch selectedMySQLTab {
            case .databases:
                MySQLView(onNavigateToVersions: {
                    selectedMySQLTab = .versions
                })
            case .versions:
                MySQLVersionsView()
            }
        case .pyenv:
            switch selectedPyenvTab {
            case .packages:
                PythonPackagesView()
            case .pipSource:
                PipSourceView()
            case .source:
                PyenvSourceView()
            case .settings:
                PyenvSettingsView()
            }
        case .postgres:
            switch selectedPostgresTab {
            case .databases:
                PostgresView()
            case .settings:
                PostgresSettingsView()
            }
        case .redis:
            switch selectedRedisTab {
            case .keys:
                RedisView()
            case .settings:
                RedisSettingsView()
            }
        case .mongodb:
            switch selectedMongoDbTab {
            case .databases:
                MongoDbView()
            case .settings:
                MongoDbSettingsView()
            }
        case .nvm:
            switch selectedNVMTab {
            case .packages:
                NvmPackagesView()
            case .npmSource:
                NpmSourceView()
            case .settings:
                NvmSettingsView()
            }
        case .rustup:
            switch selectedRustupTab {
            case .packages:
                RustupPackagesView()
            case .settings:
                RustupSettingsView()
            }
        case .jenv:
            switch selectedJenvTab {
            case .versions:
                JenvPackagesView()
            case .maven:
                MavenView()
            case .settings:
                JenvSettingsView()
            }
        case .gvm:
            switch selectedGvmTab {
            case .packages:
                GvmPackagesView()
            case .settings:
                GvmSettingsView()
            }
        case .xcode:
            XcodeView()
        case .env:
            EnvView()
        case .hosts:
            HostsView()
        case .toolSettings:
            ToolSettingsView()
        case .system:
            SystemView(selectedTab: $selectedSystemTab)
        }
    }
}

// MARK: - 加载覆盖层

struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 20)
            )
        }
    }
}

#Preview {
    ContentView()
}
