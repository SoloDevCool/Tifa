import Foundation

/// Xcode 安装信息
struct XcodeApp: Identifiable, Hashable {
    let id = UUID()
    let name: String        // e.g. "Xcode", "Xcode-beta", "Xcode 15.4"
    let path: String        // e.g. "/Applications/Xcode.app"
    let version: String?    // e.g. "16.3"
    let buildVersion: String? // e.g. "16E140"
    let diskSize: Int64     // bytes
    let isActive: Bool      // 是否为当前激活版本

    var diskSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: diskSize, countStyle: .file)
    }

    var displayName: String {
        if let v = version {
            return "\(name) \(v)"
        }
        return name
    }
}

/// Xcode 管理服务
@MainActor
class XcodeService: ObservableObject {
    static let shared = XcodeService()

    @Published var installations: [XcodeApp] = []
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var lastError: String?

    /// 检测所有已安装的 Xcode
    func detectInstallations() {
        isLoading = true
        loadingMessage = "正在检测 Xcode..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var apps: [XcodeApp] = []
            let fileManager = FileManager.default
            let currentPath = self?.getCurrentXcodePath() ?? ""

            // 扫描 /Applications 目录下名称包含 Xcode 的 .app
            guard let contents = try? fileManager.contentsOfDirectory(atPath: "/Applications") else {
                DispatchQueue.main.async {
                    self?.installations = []
                    self?.isLoading = false
                }
                return
            }

            for item in contents where item.lowercased().contains("xcode") && item.hasSuffix(".app") {
                let fullPath = "/Applications/\(item)"
                let version = self?.getXcodeVersion(at: fullPath)
                let buildVersion = self?.getXcodeBuildVersion(at: fullPath)
                let diskSize = self?.getDirectorySize(at: fullPath) ?? 0

                apps.append(XcodeApp(
                    name: item.replacingOccurrences(of: ".app", with: ""),
                    path: fullPath,
                    version: version,
                    buildVersion: buildVersion,
                    diskSize: diskSize,
                    isActive: fullPath == currentPath
                ))
            }

            // 按版本号降序排列
            apps.sort { a, b in
                guard let va = a.version, let vb = b.version else {
                    return a.name > b.name
                }
                return va.compare(vb, options: .numeric) == .orderedDescending
            }

            DispatchQueue.main.async {
                self?.installations = apps
                self?.isLoading = false
            }
        }
    }

    /// 获取当前激活的 Xcode 路径
    func getCurrentXcodePath() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "/Developer", with: "") ?? ""
        } catch {
            return ""
        }
    }

    /// 切换活跃的 Xcode 版本
    func switchXcode(_ app: XcodeApp) async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["xcode-select", "-s", app.path + "/Contents/Developer"]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("已切换到 \(app.displayName)"))
                    } else {
                        if output.contains("No tty present") || output.contains("no tty") {
                            continuation.resume(returning: .failure("需要管理员权限。请先在终端执行 'sudo echo ok' 授权。"))
                        } else {
                            continuation.resume(returning: .failure(output.isEmpty ? "切换失败" : output))
                        }
                    }
                } catch {
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 获取 Command Line Tools 状态
    func getCLTStatus() -> (installed: Bool, path: String?, version: String?) {
        let fileManager = FileManager.default

        // 检查 CLT 是否安装
        let cltPath = "/Library/Developer/CommandLineTools"
        let installed = fileManager.fileExists(atPath: cltPath)

        var version: String?
        if installed {
            let versionFile = cltPath + "/usr/bin/clang"
            if fileManager.fileExists(atPath: versionFile) {
                // 尝试获取 CLT 版本
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: versionFile)
                process.arguments = ["--version"]
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    // 提取版本号，格式: Apple clang version 16.0.0 ...
                    if let range = output.range(of: "version \\d+[\\.\\d]*", options: .regularExpression) {
                        version = String(output[range])
                    }
                } catch {}
            }
        }

        // 获取 xcode-select 指向的路径
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        var selectPath: String?
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            selectPath = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if selectPath?.isEmpty == true { selectPath = nil }
        } catch {}

        return (installed, selectPath, version)
    }

    /// 安装 Command Line Tools
    func installCLT() async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
                process.arguments = ["--install"]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Command Line Tools 安装请求已发送，请在弹出窗口中确认安装。"))
                    } else {
                        continuation.resume(returning: .failure(output.isEmpty ? "安装失败" : output))
                    }
                } catch {
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 卸载 Xcode（移到废纸篓）
    func uninstallXcode(_ app: XcodeApp) async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["rm", "-rf", app.path]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("\(app.name) 已卸载"))
                    } else {
                        if output.contains("No tty present") || output.contains("no tty") {
                            continuation.resume(returning: .failure("需要管理员权限。请先在终端执行 'sudo echo ok' 授权。"))
                        } else {
                            continuation.resume(returning: .failure(output.isEmpty ? "卸载失败" : output))
                        }
                    }
                } catch {
                    continuation.resume(returning: .failure("执行失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - 私有方法

    private func getXcodeVersion(at path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-version", "-sdk", "iphoneos", "-productBuildVersion"]
        process.environment = ["DEVELOPER_DIR": path + "/Contents/Developer"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // xcodebuild -version 输出格式: Xcode 16.3\nBuild version 16E140
            let lines = output.components(separatedBy: .newlines)
            if let firstLine = lines.first, firstLine.hasPrefix("Xcode") {
                return firstLine.replacingOccurrences(of: "Xcode", with: "").trimmingCharacters(in: .whitespaces)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func getXcodeBuildVersion(at path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-version"]
        process.environment = ["DEVELOPER_DIR": path + "/Contents/Developer"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.lowercased().contains("build version") {
                    return line.components(separatedBy: .whitespaces).last
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func getDirectorySize(at path: String) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return totalSize
    }
}
