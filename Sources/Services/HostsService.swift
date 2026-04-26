import Foundation

/// Hosts 文件条目模型
struct HostsEntry: Identifiable, Hashable {
    var id: Int          // 行号
    var ip: String       // IP 地址
    var hostname: String // 域名/主机名
    var comment: String? // 行尾注释
    var isEnabled: Bool  // 是否启用（未注释）
    var rawLine: String  // 原始行内容
}

/// Hosts 文件服务 - 管理 /etc/hosts 文件
@MainActor
class HostsService: ObservableObject {

    static let shared = HostsService()

    private let hostsPath = "/etc/hosts"

    /// 读取 Hosts 文件内容
    func readFileContent() -> String {
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else {
            return ""
        }
        return content
    }

    /// 解析 Hosts 文件条目
    func parseEntries() -> [HostsEntry] {
        let content = readFileContent()
        var entries: [HostsEntry] = []
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行和纯注释行 — 跳过，不加入可视化列表
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // 普通行
            if let parsed = parseHostLine(trimmed, rawLine: line) {
                var entry = parsed
                entry.id = index
                entries.append(entry)
            }
        }

        return entries
    }

    /// 解析单行 hosts 条目
    private func parseHostLine(_ line: String, rawLine: String) -> HostsEntry? {
        // 处理行尾注释
        var workingLine = line
        var comment: String?

        if let hashIndex = line.firstIndex(of: "#") {
            let beforeHash = String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
            if !beforeHash.isEmpty {
                comment = String(line[hashIndex...]).trimmingCharacters(in: .whitespaces)
                workingLine = beforeHash
            }
        }

        let parts = workingLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        let ip = parts[0]
        let hostname = parts[1]

        // 校验 IP 格式，避免纯注释文本被误解析为条目
        let ipPattern = #"^(\d{1,3}\.){3}\d{1,3}$|^([0-9a-fA-F:]+:+)+[0-9a-fA-F]*$|^::$"#
        guard ip.range(of: ipPattern, options: .regularExpression) != nil else { return nil }

        return HostsEntry(
            id: 0,
            ip: ip,
            hostname: hostname,
            comment: comment,
            isEnabled: true,
            rawLine: rawLine
        )
    }

    /// 保存完整文件内容（用于文本编辑模式）
    func saveFileContent(_ content: String) async -> OperationResult {
        // 需要管理员权限写入 /etc/hosts
        return await writeWithSudo(content)
    }

    /// 添加一条 Hosts 条目
    func addEntry(ip: String, hostname: String, comment: String?) async -> OperationResult {
        var content = readFileContent()
        var newLine = "\(ip)\t\(hostname)"
        if let comment = comment, !comment.isEmpty {
            newLine += "\t# \(comment)"
        }

        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += newLine + "\n"

        return await writeWithSudo(content)
    }

    /// 切换条目启用/禁用
    func toggleEntry(entry: HostsEntry) async -> OperationResult {
        let content = readFileContent()
        let lines = content.components(separatedBy: .newlines)

        guard entry.id < lines.count else {
            return .failure("条目索引超出范围")
        }

        var modifiedLines = lines
        let line = modifiedLines[entry.id]

        if entry.isEnabled {
            // 禁用：在行首添加 #
            if !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
                modifiedLines[entry.id] = String(leadingSpaces) + "# " + line.trimmingCharacters(in: .whitespaces)
            }
        } else {
            // 启用：移除行首的 #（仅对有 IP 的条目）
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let uncommented = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                let parts = uncommented.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
                    modifiedLines[entry.id] = String(leadingSpaces) + uncommented
                }
            }
        }

        let newContent = modifiedLines.joined(separator: "\n")
        return await writeWithSudo(newContent)
    }

    /// 删除指定条目
    func deleteEntry(_ entry: HostsEntry) async -> OperationResult {
        let content = readFileContent()
        let lines = content.components(separatedBy: .newlines)

        guard entry.id < lines.count else {
            return .failure("条目索引超出范围")
        }

        var modifiedLines = lines
        modifiedLines.remove(at: entry.id)
        let newContent = modifiedLines.joined(separator: "\n")
        return await writeWithSudo(newContent)
    }

    /// 编辑条目
    func editEntry(_ entry: HostsEntry, newIP: String, newHostname: String, newComment: String?) async -> OperationResult {
        let content = readFileContent()
        let lines = content.components(separatedBy: .newlines)

        guard entry.id < lines.count else {
            return .failure("条目索引超出范围")
        }

        var newLine = "\(newIP)\t\(newHostname)"
        if let comment = newComment, !comment.isEmpty {
            newLine += "\t# \(comment)"
        }

        var modifiedLines = lines
        if !entry.isEnabled {
            let leadingSpaces = modifiedLines[entry.id].prefix(while: { $0 == " " || $0 == "\t" })
            modifiedLines[entry.id] = String(leadingSpaces) + "# " + newLine
        } else {
            let leadingSpaces = modifiedLines[entry.id].prefix(while: { $0 == " " || $0 == "\t" })
            modifiedLines[entry.id] = String(leadingSpaces) + newLine
        }

        let newContent = modifiedLines.joined(separator: "\n")
        return await writeWithSudo(newContent)
    }

    /// 使用 sudo 写入 /etc/hosts
    private func writeWithSudo(_ content: String) async -> OperationResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["tee", self.hostsPath]
                process.standardInput = pipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    pipe.fileHandleForWriting.write(content.data(using: .utf8)!)
                    pipe.fileHandleForWriting.closeFile()

                    process.waitUntilExit()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Hosts 文件已保存"))
                    } else {
                        if stderr.contains("No tty present") || stderr.contains("no tty") {
                            continuation.resume(returning: .failure("需要管理员权限。请先在终端执行 'sudo echo ok' 授权，或使用文本编辑模式手动保存。"))
                        } else {
                            continuation.resume(returning: .failure("保存失败: \(stderr.isEmpty ? "未知错误" : stderr)"))
                        }
                    }
                } catch {
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 刷新 DNS 缓存
    func flushDNS() async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["dscacheutil", "-flushcache"]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    // 再执行 killall
                    let process2 = Process()
                    let pipe2 = Pipe()
                    process2.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                    process2.arguments = ["killall", "-HUP", "mDNSResponder"]
                    process2.standardOutput = pipe2
                    process2.standardError = pipe2

                    try process2.run()
                    process2.waitUntilExit()

                    continuation.resume(returning: .success("DNS 缓存已刷新"))
                } catch {
                    continuation.resume(returning: .failure("刷新 DNS 失败: \(error.localizedDescription)"))
                }
            }
        }
    }
}
