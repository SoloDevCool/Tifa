import Foundation

/// 环境变量模型
struct EnvVariable: Identifiable, Hashable {
    let id: String
    var name: String
    var value: String
    var sourceFile: String  // 来源文件：.zshrc / .zshenv / .zprofile / .bash_profile
    var lineIndex: Int?     // 在文件中的行号
}

/// Shell 配置文件信息
struct ShellConfigFile: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let description: String
    let isSelected: Bool
    
    static func availableFiles() -> [ShellConfigFile] {
        let home = NSHomeDirectory()
        let files: [(name: String, desc: String)] = [
            (".zshrc", "Zsh 交互式 Shell 配置（最常用）"),
            (".zshenv", "Zsh 所有 Shell 配置"),
            (".zprofile", "Zsh 登录 Shell 配置"),
            (".bash_profile", "Bash 登录 Shell 配置"),
            (".bashrc", "Bash 交互式 Shell 配置"),
        ]
        return files.map { f in
            let path = "\(home)/\(f.name)"
            let exists = FileManager.default.fileExists(atPath: path)
            return ShellConfigFile(
                id: f.name,
                name: f.name,
                path: path,
                description: f.desc + (exists ? "" : "（未创建）"),
                isSelected: f.name == ".zshrc"
            )
        }
    }
}

/// 环境变量服务 - 管理 shell 配置文件中的环境变量
@MainActor
class EnvService: ObservableObject {
    
    static let shared = EnvService()
    
    @Published var isLoading = false
    @Published var loadingMessage = ""
    
    private let home = NSHomeDirectory()
    
    /// 获取当前用户的 Shell
    func getCurrentShell() -> String {
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
    
    /// 获取可用的 Shell 配置文件列表
    func getShellConfigFiles() -> [ShellConfigFile] {
        return ShellConfigFile.availableFiles()
    }
    
    /// 读取指定配置文件的内容
    func readFileContent(_ fileName: String) -> String {
        let path = "\(home)/\(fileName)"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    /// 从指定文件解析环境变量
    func parseEnvVariables(from fileName: String) -> [EnvVariable] {
        let content = readFileContent(fileName)
        return parseEnvVariables(content: content, sourceFile: fileName)
    }
    
    /// 从文本内容解析环境变量
    func parseEnvVariables(content: String, sourceFile: String) -> [EnvVariable] {
        var variables: [EnvVariable] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过空行和注释
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }
            
            // 匹配 export KEY=VALUE 或 export KEY="VALUE" 或 export KEY='VALUE'
            // 也匹配 KEY=VALUE（无 export）
            let pattern = #"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let nameRange = Range(match.range(at: 1), in: trimmed),
                  let valueRange = Range(match.range(at: 2), in: trimmed) else {
                continue
            }
            
            let name = String(trimmed[nameRange])
            var value = String(trimmed[valueRange])
            
            // 去除引号
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            
            // 展开 $HOME 等
            value = value.replacingOccurrences(of: "$HOME", with: home)
            
            variables.append(EnvVariable(
                id: "\(sourceFile)_\(index)",
                name: name,
                value: value,
                sourceFile: sourceFile,
                lineIndex: index
            ))
        }
        
        return variables
    }
    
    /// 保存环境变量到文件
    func saveVariable(name: String, value: String, to fileName: String) -> OperationResult {
        let path = "\(home)/\(fileName)"
        let exportLine = "export \(name)=\"\(value)\""
        
        // 读取现有内容
        let content = readFileContent(fileName)
        
        // 检查是否已存在同名变量
        let lines = content.components(separatedBy: .newlines)
        var found = false
        var newLines: [String] = []
        
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let updatePattern = #"^(?:export\s+)?#?\s*\#(escapedName)#=.*$"#
        guard let regex = try? NSRegularExpression(pattern: updatePattern, options: .caseInsensitive) else {
            return .failure("正则表达式错误")
        }
        
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                // 替换已有变量
                newLines.append(exportLine)
                found = true
            } else {
                newLines.append(line)
            }
        }
        
        if !found {
            // 新增变量，追加到末尾
            if !content.isEmpty && !content.hasSuffix("\n") {
                newLines.append("")
            }
            newLines.append("")
            newLines.append("# Added by Tifa")
            newLines.append(exportLine)
        }
        
        let newContent = newLines.joined(separator: "\n")
        
        do {
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("已保存 \(name) 到 \(fileName)")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 删除环境变量（从指定文件中移除）
    func deleteVariable(name: String, from fileName: String) -> OperationResult {
        let path = "\(home)/\(fileName)"
        let content = readFileContent(fileName)
        
        guard !content.isEmpty else {
            return .failure("文件为空")
        }
        
        let lines = content.components(separatedBy: .newlines)
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let deletePattern = #"^(?:export\s+)?#?\s*\#(escapedName)#=.*$"#
        
        guard let regex = try? NSRegularExpression(pattern: deletePattern, options: .caseInsensitive) else {
            return .failure("正则表达式错误")
        }
        
        var newLines: [String] = []
        var removed = false
        
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                removed = true
            } else {
                newLines.append(line)
            }
        }
        
        if !removed {
            return .failure("未找到变量 \(name)")
        }
        
        let newContent = newLines.joined(separator: "\n")
        
        do {
            try newContent.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("已从 \(fileName) 删除 \(name)")
        } catch {
            return .failure("删除失败: \(error.localizedDescription)")
        }
    }
    
    /// 保存文件原始内容（用于文本编辑器模式）
    func saveFileContent(_ content: String, to fileName: String) -> OperationResult {
        let path = "\(home)/\(fileName)"
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .success("文件 \(fileName) 已保存")
        } catch {
            return .failure("保存失败: \(error.localizedDescription)")
        }
    }
    
    /// 获取当前进程的环境变量（仅用于查看，不可编辑）
    func getCurrentEnvVariables() -> [EnvVariable] {
        let env = ProcessInfo.processInfo.environment
        return env.sorted(by: { $0.key < $1.key }).map { key, value in
            EnvVariable(id: "current_\(key)", name: key, value: value, sourceFile: "当前进程", lineIndex: nil)
        }
    }
    
    /// 应用环境变量（source 文件，使新终端窗口生效）
    func applyEnvVariables(_ fileName: String) async -> OperationResult {
        let path = "\(home)/\(fileName)"
        let shell = getCurrentShell()
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-c", "source \(path) && echo 'OK'"]
                process.standardOutput = pipe
                process.standardError = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("环境变量已生效，新打开的终端窗口将使用更新后的配置。"))
                    } else {
                        continuation.resume(returning: .failure("应用失败: \(output)"))
                    }
                } catch {
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }
}
