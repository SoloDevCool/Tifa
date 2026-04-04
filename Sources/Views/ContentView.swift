import SwiftUI

// MARK: - 分类定义

enum ToolCategory: String, CaseIterable, Identifiable {
    case homebrew = "Homebrew"
    case rvm = "RVM"
    case pyenv = "pyenv"
    case mysql = "MySQL"
    case postgres = "PostgreSQL"
    case system = "系统监控"
    case env = "环境变量"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .homebrew: return "shippingbox"
        case .rvm: return "cube"
        case .pyenv: return "leaf"
        case .mysql: return "cylinder"
        case .postgres: return "externaldrive"
        case .system: return "chart.bar"
        case .env: return "gearshape.2"
        }
    }
}

// MARK: - Homebrew 子菜单

enum HomebrewTab: String, CaseIterable, Identifiable {
    case installed = "已安装"
    case search = "搜索"
    case outdated = "可用更新"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .installed: return "square.stack.3d.up"
        case .search: return "magnifyingglass"
        case .outdated: return "arrow.triangle.2.circlepath"
        case .settings: return "gear"
        }
    }
}

// MARK: - RVM 子菜单

enum RVMTab: String, CaseIterable, Identifiable {
    case rubies = "Ruby 版本"
    case gemsets = "Gemset"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .rubies: return "cube"
        case .gemsets: return "folder"
        case .settings: return "gear"
        }
    }
}

// MARK: - pyenv 子菜单

enum PyenvTab: String, CaseIterable, Identifiable {
    case versions = "Python 版本"
    case settings = "设置"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .versions: return "leaf"
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

// MARK: - MySQL 子菜单

enum MySQLTab: String, CaseIterable, Identifiable {
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

// MARK: - 主视图

struct ContentView: View {
    @StateObject private var homebrewService = HomebrewService.shared
    @State private var selectedCategory: ToolCategory = .homebrew
    @State private var selectedHomebrewTab: HomebrewTab = .installed
    @State private var selectedRVMTab: RVMTab = .rubies
    @State private var selectedMySQLTab: MySQLTab = .databases
    @State private var selectedPyenvTab: PyenvTab = .versions
    @State private var selectedPostgresTab: PostgresTab = .databases
    
    var body: some View {
        HStack(spacing: 0) {
            // 第一列：分类选择
            categorySidebar
            
            Divider()
            
            // 第二列：子菜单
            subSidebar
            
            Divider()
            
            // 第三列：内容页
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .overlay {
            if homebrewService.isLoading || RVMService.shared.isLoading || MySQLService.shared.isLoading || PyenvService.shared.isLoading || PostgresService.shared.isLoading {
                LoadingOverlay(message: homebrewService.isLoading ? homebrewService.loadingMessage : (RVMService.shared.isLoading ? RVMService.shared.loadingMessage : (MySQLService.shared.isLoading ? MySQLService.shared.loadingMessage : (PyenvService.shared.isLoading ? PyenvService.shared.loadingMessage : PostgresService.shared.loadingMessage))))
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
            Text("工具")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            List(selection: $selectedCategory) {
                ForEach(ToolCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
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
            } else {
                // 系统监控、环境变量 - 单页面，无子菜单
                VStack {
                    Spacer()
                    Text(selectedCategory == .system ? "系统监控" : "环境变量管理")
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
            case .search:
                SearchView()
            case .outdated:
                OutdatedPackagesView()
            case .settings:
                SettingsView()
            }
        case .rvm:
            switch selectedRVMTab {
            case .rubies:
                RVMView()
            case .gemsets:
                RVMGemsetView()
            case .settings:
                RVMSettingsView()
            }
        case .mysql:
            switch selectedMySQLTab {
            case .databases:
                MySQLView()
            case .settings:
                MySQLSettingsView()
            }
        case .pyenv:
            switch selectedPyenvTab {
            case .versions:
                PyenvView()
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
        case .env:
            EnvView()
        case .system:
            SystemView()
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
