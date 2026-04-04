import Foundation

/// Ruby 版本信息
struct RubyVersion: Identifiable, Hashable {
    let id: String
    let version: String
    let isCurrent: Bool
    let isDefault: Bool
    
    init(version: String, isCurrent: Bool = false, isDefault: Bool = false) {
        self.id = version
        self.version = version
        self.isCurrent = isCurrent
        self.isDefault = isDefault
    }
    
    // 解析 "ruby-3.2.2 [ x86_64 ]" 格式
    static func parse(_ line: String) -> RubyVersion? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        let isCurrent = trimmed.contains("*")
        let isDefault = trimmed.contains("=>")
        
        // 提取版本号
        let pattern = #"ruby-([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range(at: 1), in: trimmed) else {
            // 回退：尝试提取第一个看起来像版本号的
            let parts = trimmed.components(separatedBy: .whitespaces)
            for part in parts {
                let cleaned = part.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "=>", with: "")
                if cleaned.hasPrefix("ruby-") {
                    let ver = cleaned.replacingOccurrences(of: "ruby-", with: "")
                    return RubyVersion(version: ver, isCurrent: isCurrent, isDefault: isDefault)
                }
            }
            return nil
        }
        
        let version = String(trimmed[range])
        return RubyVersion(version: version, isCurrent: isCurrent, isDefault: isDefault)
    }
}

/// 可安装的 Ruby 版本
struct AvailableRuby: Identifiable, Hashable {
    let id: String
    let version: String
    let isInstalled: Bool
    
    init(version: String, isInstalled: Bool = false) {
        self.id = version
        self.version = version
        self.isInstalled = isInstalled
    }
}
