import SwiftUI

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

// MARK: - Localization Manager

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.zhHans.rawValue
        self.currentLanguage = AppLanguage(rawValue: stored) ?? .zhHans
    }

    // MARK: - String Table

    private let strings: [AppLanguage: [String: String]] = [
        // ====== 简体中文 ======
        .zhHans: [
            // - 分类分组 -
            "category.basic": "基础服务",
            "category.language": "语言管理器",
            "category.database": "数据库",
            "category.settings": "设置",

            // - 工具分类 -
            "tool.system": "系统监控",
            "tool.env": "环境变量",
            "tool.toolSettings": "工具设置",

            // - Homebrew 子菜单 -
            "tab.installed": "已安装",
            "tab.cask": "GUI 应用",
            "tab.search": "搜索",
            "tab.outdated": "可用更新",
            "tab.mirror": "镜像源",
            "tab.settings": "设置",

            // - RVM 子菜单 -
            "tab.rubyPackages": "Ruby 软件包",
            "tab.gemsets": "Gemset",
            "tab.gemSource": "Gem 源",
            "tab.installSource": "安装源",

            // - pyenv 子菜单 -
            "tab.pythonPackages": "Python 软件包",
            "tab.pipSource": "Pip 源",

            // - NVM 子菜单 -
            "tab.nvmPackages": "NVM 软件包",
            "tab.npmSource": "NPM 源",

            // - JEnv 子菜单 -
            "tab.javaPackages": "Java 软件包",

            // - Rustup 子菜单 -
            "tab.rustToolchains": "Rust 工具链",

            // - GVM 子菜单 -
            "tab.goPackages": "Go 软件包",

            // - 系统监控 子菜单 -
            "tab.systemMetrics": "系统指标",
            "tab.processMonitor": "进程监控",
            "tab.portMonitor": "端口监控",

            // - 数据库 子菜单 -
            "tab.databases": "数据库",
            "tab.redisKeys": "键管理",
            "tab.mysqlPackages": "MySQL 软件包",

            // - 通用按钮 -
            "common.install": "安装",
            "common.uninstall": "卸载",
            "common.update": "更新",
            "common.upgrade": "升级",
            "common.search": "搜索",
            "common.refresh": "刷新",
            "common.cancel": "取消",
            "common.confirm": "确定",
            "common.close": "关闭",
            "common.retry": "重试",
            "common.apply": "应用",
            "common.save": "保存",
            "common.delete": "删除",
            "common.copy": "复制",
            "common.start": "启动",
            "common.stop": "停止",
            "common.restart": "重启",
            "common.error": "错误",
            "common.success": "成功",
            "common.warning": "警告",
            "common.loading": "加载中...",
            "common.searching": "搜索中...",
            "common.noData": "暂无数据",
            "common.notInstalled": "未安装",
            "common.installed": "已安装",
            "common.outdated": "有可用更新",
            "common.default": "默认",
            "common.current": "当前",

            // - 子侧栏标题 -
            "sidebar.envManagement": "环境变量管理",
            "sidebar.xcodeManagement": "Xcode 管理",
            "sidebar.hostsManagement": "Hosts 文件管理",

            // - 工具设置页 -
            "settings.title": "工具设置",
            "settings.systemMonitor": "系统监控",
            "settings.systemMonitorDesc": "配置系统监控各子模块的数据刷新频率",
            "settings.systemMetrics": "系统指标",
            "settings.systemMetricsDesc": "CPU、内存、磁盘等硬件指标数据采集频率",
            "settings.processMonitor": "进程监控",
            "settings.processMonitorDesc": "进程列表数据刷新频率",
            "settings.portMonitor": "端口监控",
            "settings.portMonitorDesc": "网络端口连接数据刷新频率",
            "settings.refreshInterval": "刷新间隔",
            "settings.language": "语言",
            "settings.languageDesc": "切换应用显示语言（需重新打开对应页面生效）",

            // - 时间间隔 -
            "interval.3s": "3秒",
            "interval.5s": "5秒",
            "interval.10s": "10秒",
            "interval.30s": "30秒",
            "interval.60s": "60秒",

            // - 搜索页 -
            "search.placeholder": "搜索 Homebrew 包",
            "search.startSearch": "开始搜索",
            "search.noResults": "未找到结果",
            "search.tryOther": "尝试其他搜索词",
            "search.begin": "开始搜索",
            "search.inputToSearch": "输入包名进行搜索",

            // - 空状态 -
            "empty.notInstalled": "未安装",
            "empty.installFirst": "请先安装",

            // - 安装进度 -
            "install.starting": "开始安装",
            "install.success": "安装成功",
            "install.failed": "安装失败",
            "install.uninstallSuccess": "卸载成功",
            "install.timeout": "安装超时，请检查网络连接后重试",

            // - 版本页通用 -
            "version.available": "可用版本",
            "version.installed": "已安装版本",
            "version.installCount": "已安装版本数",
            "version.diskUsage": "占用空间",
            "version.setAsDefault": "设为默认",
            "version.uninstallConfirm": "确定要卸载吗？此操作不可撤销。",
        ],

        // ====== English ======
        .en: [
            "category.basic": "Basic Services",
            "category.language": "Languages",
            "category.database": "Database",
            "category.settings": "Settings",

            "tool.system": "System Monitor",
            "tool.env": "Environment",
            "tool.toolSettings": "Tool Settings",

            "tab.installed": "Installed",
            "tab.cask": "GUI Apps",
            "tab.search": "Search",
            "tab.outdated": "Updates",
            "tab.mirror": "Mirror",
            "tab.settings": "Settings",

            "tab.rubyPackages": "Ruby Packages",
            "tab.gemsets": "Gemset",
            "tab.gemSource": "Gem Source",
            "tab.installSource": "Install Source",

            "tab.pythonPackages": "Python Packages",
            "tab.pipSource": "Pip Source",

            "tab.nvmPackages": "NVM Packages",
            "tab.npmSource": "NPM Source",

            "tab.javaPackages": "Java Packages",

            "tab.rustToolchains": "Rust Toolchains",

            "tab.goPackages": "Go Packages",

            "tab.systemMetrics": "System Metrics",
            "tab.processMonitor": "Processes",
            "tab.portMonitor": "Ports",

            "tab.databases": "Databases",
            "tab.redisKeys": "Keys",
            "tab.mysqlPackages": "MySQL Packages",

            "common.install": "Install",
            "common.uninstall": "Uninstall",
            "common.update": "Update",
            "common.upgrade": "Upgrade",
            "common.search": "Search",
            "common.refresh": "Refresh",
            "common.cancel": "Cancel",
            "common.confirm": "OK",
            "common.close": "Close",
            "common.retry": "Retry",
            "common.apply": "Apply",
            "common.save": "Save",
            "common.delete": "Delete",
            "common.copy": "Copy",
            "common.start": "Start",
            "common.stop": "Stop",
            "common.restart": "Restart",
            "common.error": "Error",
            "common.success": "Success",
            "common.warning": "Warning",
            "common.loading": "Loading...",
            "common.searching": "Searching...",
            "common.noData": "No Data",
            "common.notInstalled": "Not Installed",
            "common.installed": "Installed",
            "common.outdated": "Update Available",
            "common.default": "Default",
            "common.current": "Current",

            "sidebar.envManagement": "Environment Variables",
            "sidebar.xcodeManagement": "Xcode Management",
            "sidebar.hostsManagement": "Hosts File Management",

            "settings.title": "Tool Settings",
            "settings.systemMonitor": "System Monitor",
            "settings.systemMonitorDesc": "Configure data refresh intervals for system monitor modules",
            "settings.systemMetrics": "System Metrics",
            "settings.systemMetricsDesc": "CPU, memory, disk and other hardware metric collection interval",
            "settings.processMonitor": "Process Monitor",
            "settings.processMonitorDesc": "Process list data refresh interval",
            "settings.portMonitor": "Port Monitor",
            "settings.portMonitorDesc": "Network port connection data refresh interval",
            "settings.refreshInterval": "Refresh Interval",
            "settings.language": "Language",
            "settings.languageDesc": "Switch app display language (reopen pages to take effect)",

            "interval.3s": "3s",
            "interval.5s": "5s",
            "interval.10s": "10s",
            "interval.30s": "30s",
            "interval.60s": "60s",

            "search.placeholder": "Search Homebrew packages",
            "search.startSearch": "Search",
            "search.noResults": "No Results",
            "search.tryOther": "Try other search terms",
            "search.begin": "Start Search",
            "search.inputToSearch": "Enter a package name to search",

            "empty.notInstalled": "Not Installed",
            "empty.installFirst": "Please install first",

            "install.starting": "Installing",
            "install.success": "Installation Successful",
            "install.failed": "Installation Failed",
            "install.uninstallSuccess": "Uninstall Successful",
            "install.timeout": "Installation timed out, please check your network and try again",

            "version.available": "Available Versions",
            "version.installed": "Installed Versions",
            "version.installCount": "Installed Versions",
            "version.diskUsage": "Disk Usage",
            "version.setAsDefault": "Set as Default",
            "version.uninstallConfirm": "Are you sure you want to uninstall? This cannot be undone.",
        ],

        // ====== 日本語 ======
        .ja: [
            "category.basic": "基本サービス",
            "category.language": "言語マネージャー",
            "category.database": "データベース",
            "category.settings": "設定",

            "tool.system": "システム監視",
            "tool.env": "環境変数",
            "tool.toolSettings": "ツール設定",

            "tab.installed": "インストール済み",
            "tab.cask": "GUIアプリ",
            "tab.search": "検索",
            "tab.outdated": "アップデート",
            "tab.mirror": "ミラー",
            "tab.settings": "設定",

            "tab.rubyPackages": "Rubyパッケージ",
            "tab.gemsets": "Gemset",
            "tab.gemSource": "Gemソース",
            "tab.installSource": "インストールソース",

            "tab.pythonPackages": "Pythonパッケージ",
            "tab.pipSource": "Pipソース",

            "tab.nvmPackages": "NVMパッケージ",
            "tab.npmSource": "NPMソース",

            "tab.javaPackages": "Javaパッケージ",

            "tab.rustToolchains": "Rustツールチェーン",

            "tab.goPackages": "Goパッケージ",

            "tab.systemMetrics": "システム指標",
            "tab.processMonitor": "プロセス監視",
            "tab.portMonitor": "ポート監視",

            "tab.databases": "データベース",
            "tab.redisKeys": "キー管理",
            "tab.mysqlPackages": "MySQLパッケージ",

            "common.install": "インストール",
            "common.uninstall": "アンインストール",
            "common.update": "更新",
            "common.upgrade": "アップグレード",
            "common.search": "検索",
            "common.refresh": "更新",
            "common.cancel": "キャンセル",
            "common.confirm": "OK",
            "common.close": "閉じる",
            "common.retry": "再試行",
            "common.apply": "適用",
            "common.save": "保存",
            "common.delete": "削除",
            "common.copy": "コピー",
            "common.start": "開始",
            "common.stop": "停止",
            "common.restart": "再起動",
            "common.error": "エラー",
            "common.success": "成功",
            "common.warning": "警告",
            "common.loading": "読み込み中...",
            "common.searching": "検索中...",
            "common.noData": "データなし",
            "common.notInstalled": "未インストール",
            "common.installed": "インストール済み",
            "common.outdated": "アップデートあり",
            "common.default": "デフォルト",
            "common.current": "現在",

            "sidebar.envManagement": "環境変数管理",
            "sidebar.xcodeManagement": "Xcode管理",
            "sidebar.hostsManagement": "Hostsファイル管理",

            "settings.title": "ツール設定",
            "settings.systemMonitor": "システム監視",
            "settings.systemMonitorDesc": "システム監視モジュールのデータ更新間隔を設定",
            "settings.systemMetrics": "システム指標",
            "settings.systemMetricsDesc": "CPU、メモリ、ディスクなどのハードウェア指標収集間隔",
            "settings.processMonitor": "プロセス監視",
            "settings.processMonitorDesc": "プロセス一覧のデータ更新間隔",
            "settings.portMonitor": "ポート監視",
            "settings.portMonitorDesc": "ネットワークポート接続のデータ更新間隔",
            "settings.refreshInterval": "更新間隔",
            "settings.language": "言語",
            "settings.languageDesc": "アプリの表示言語を切り替え（ページを再開すると反映されます）",

            "interval.3s": "3秒",
            "interval.5s": "5秒",
            "interval.10s": "10秒",
            "interval.30s": "30秒",
            "interval.60s": "60秒",

            "search.placeholder": "Homebrewパッケージを検索",
            "search.startSearch": "検索",
            "search.noResults": "結果なし",
            "search.tryOther": "他の検索語をお試しください",
            "search.begin": "検索を開始",
            "search.inputToSearch": "パッケージ名を入力して検索",

            "empty.notInstalled": "未インストール",
            "empty.installFirst": "先にインストールしてください",

            "install.starting": "インストール中",
            "install.success": "インストール成功",
            "install.failed": "インストール失敗",
            "install.uninstallSuccess": "アンインストール成功",
            "install.timeout": "インストールがタイムアウトしました。ネットワークを確認して再試行してください",

            "version.available": "利用可能なバージョン",
            "version.installed": "インストール済みバージョン",
            "version.installCount": "インストール済みバージョン数",
            "version.diskUsage": "ディスク使用量",
            "version.setAsDefault": "デフォルトに設定",
            "version.uninstallConfirm": "本当にアンインストールしますか？この操作は取り消せません。",
        ]
    ]

    // MARK: - Lookup

    func localized(_ key: String) -> String {
        strings[currentLanguage]?[key]
            ?? strings[.zhHans]?[key]
            ?? strings[.en]?[key]
            ?? key
    }
}

// MARK: - Global Convenience

/// Shorthand for `LocalizationManager.shared.localized(_:)`
func L(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}

// MARK: - Enum Display Names

extension CategoryGroup {
    var displayName: String {
        switch self {
        case .basic: return L("category.basic")
        case .language: return L("category.language")
        case .database: return L("category.database")
        case .settings: return L("category.settings")
        }
    }
}

extension ToolCategory {
    var displayName: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .xcode: return "Xcode"
        case .rvm: return "RVM"
        case .pyenv: return "pyenv"
        case .mysql: return "MySQL"
        case .postgres: return "PostgreSQL"
        case .redis: return "Redis"
        case .mongodb: return "MongoDB"
        case .nvm: return "NVM"
        case .rustup: return "rustup"
        case .jenv: return "JEnv"
        case .gvm: return "GVM"
        case .system: return L("tool.system")
        case .env: return L("tool.env")
        case .hosts: return "Hosts"
        case .toolSettings: return L("tool.toolSettings")
        }
    }
}

extension HomebrewTab {
    var displayName: String {
        switch self {
        case .installed: return L("tab.installed")
        case .cask: return L("tab.cask")
        case .tap: return "Tap"
        case .search: return L("tab.search")
        case .outdated: return L("tab.outdated")
        case .mirror: return L("tab.mirror")
        case .settings: return L("tab.settings")
        }
    }
}

extension RVMTab {
    var displayName: String {
        switch self {
        case .packages: return L("tab.rubyPackages")
        case .gemsets: return L("tab.gemsets")
        case .gemSource: return L("tab.gemSource")
        case .source: return L("tab.installSource")
        case .settings: return L("tab.settings")
        }
    }
}

extension PyenvTab {
    var displayName: String {
        switch self {
        case .packages: return L("tab.pythonPackages")
        case .pipSource: return L("tab.pipSource")
        case .source: return L("tab.installSource")
        case .settings: return L("tab.settings")
        }
    }
}

extension PostgresTab {
    var displayName: String {
        switch self {
        case .databases: return L("tab.databases")
        case .settings: return L("tab.settings")
        }
    }
}

extension RedisTab {
    var displayName: String {
        switch self {
        case .keys: return L("tab.redisKeys")
        case .settings: return L("tab.settings")
        }
    }
}

extension NVMTab {
    var displayName: String {
        switch self {
        case .packages: return L("tab.nvmPackages")
        case .npmSource: return L("tab.npmSource")
        case .settings: return L("tab.settings")
        }
    }
}

extension JenvTab {
    var displayName: String {
        switch self {
        case .versions: return L("tab.javaPackages")
        case .maven: return "Maven"
        case .settings: return L("tab.settings")
        }
    }
}

extension RustupTab {
    var displayName: String {
        switch self {
        case .packages: return L("tab.rustToolchains")
        case .settings: return L("tab.settings")
        }
    }
}

extension GvmTab {
    var displayName: String {
        switch self {
        case .packages: return L("tab.goPackages")
        case .settings: return L("tab.settings")
        }
    }
}

extension MongoDbTab {
    var displayName: String {
        switch self {
        case .databases: return L("tab.databases")
        case .settings: return L("tab.settings")
        }
    }
}

extension SystemTab {
    var displayName: String {
        switch self {
        case .metrics: return L("tab.systemMetrics")
        case .processes: return L("tab.processMonitor")
        case .ports: return L("tab.portMonitor")
        }
    }
}

extension MySQLTab {
    var displayName: String {
        switch self {
        case .databases: return L("tab.databases")
        case .versions: return L("tab.mysqlPackages")
        }
    }
}
