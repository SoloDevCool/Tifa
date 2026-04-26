import Foundation

/// Homebrew 包信息模型
struct BrewPackage: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let description: String
    let installedDate: Date?
    let tap: String
    
    init(name: String, version: String = "", description: String = "", installedDate: Date? = nil, tap: String = "homebrew") {
        self.id = name
        self.name = name
        self.version = version
        self.description = description
        self.installedDate = installedDate
        self.tap = tap
    }
}

/// 包安装状态
enum PackageStatus: Equatable {
    case installed
    case outdated
    case notInstalled
    case installing
    case uninstalling
    case updating
}

/// 搜索结果模型
struct SearchResult: Identifiable {
    let id: String
    let name: String
    let description: String
    let tap: String
    let isCask: Bool
}

/// 搜索结果模型（兼容旧调用）
extension SearchResult {
    init(id: String, name: String, description: String, tap: String) {
        self.id = id
        self.name = name
        self.description = description
        self.tap = tap
        self.isCask = false
    }
}

/// Homebrew 命令类型
enum BrewCommand {
    case list
    case search
    case info
    case install
    case uninstall
    case update
    case upgrade
    case outdated
    case cleanup
    
    var arguments: [String] {
        switch self {
        case .list:
            return ["list", "--formula", "--json"]
        case .search:
            return ["search"]
        case .info:
            return ["info"]
        case .install:
            return ["install"]
        case .uninstall:
            return ["uninstall", "--force"]
        case .update:
            return ["update"]
        case .upgrade:
            return ["upgrade"]
        case .outdated:
            return ["outdated", "--formula"]
        case .cleanup:
            return ["cleanup", "--prune=all"]
        }
    }
}

/// 操作结果
enum OperationResult {
    case success(String)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .success(let msg): return msg
        case .failure(let msg): return msg
        }
    }
}
