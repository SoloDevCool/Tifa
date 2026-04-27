import Foundation

/// Maven 服务 - 管理 Maven 安装和版本
@MainActor
class MavenService: ObservableObject {

    static let shared = MavenService()

    @Published var isLoading = false
    @Published var loadingMessage = ""

    /// 当前正在执行的安装进程（用于取消）
    private var currentInstallProcess: Process?

    /// 取消当前安装进程
    func cancelCurrentInstall() {
        currentInstallProcess?.terminate()
        currentInstallProcess = nil
    }

    /// brew 可执行文件绝对路径
    private var brewPath: String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }

    /// Homebrew 前缀路径
    private var brewPrefix: String {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }

    // MARK: - 检查可用性

    /// 检查 Maven 是否已安装
    func checkMavenAvailable() -> Bool {
        let paths = [
            "\(brewPrefix)/bin/mvn",
            "/usr/local/bin/mvn",
            "/opt/homebrew/bin/mvn"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 获取 Maven 版本
    func getMavenVersion() async -> String {
        let mvnPath = getMavenPath()
        guard !mvnPath.isEmpty else { return "未安装" }

        let result = await runCommand(mvnPath, arguments: ["--version"])
        if case .success(let output) = result {
            // 输出格式: "Apache Maven 3.9.6 (bc0240f3c744dd6b6ec2920b3cd08dcc295161ae)"
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("Apache Maven") {
                    return trimmed
                }
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未知"
    }

    /// 获取 Maven 安装路径
    func getMavenPath() -> String {
        let paths = [
            "\(brewPrefix)/bin/mvn",
            "/usr/local/bin/mvn",
            "/opt/homebrew/bin/mvn"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) } ?? ""
    }

    /// 获取 Maven 安装信息
    func getMavenHome() async -> String {
        let mvnPath = getMavenPath()
        guard !mvnPath.isEmpty else { return "未安装" }

        let result = await runCommand(mvnPath, arguments: ["-v"])
        if case .success(let output) = result {
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("Maven home") {
                    return trimmed
                }
            }
        }
        return "未知"
    }

    // MARK: - 安装/卸载

    /// 使用 Homebrew 安装 Maven（带实时输出）
    func installMaven(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "\(brewPath) install maven"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                Task { @MainActor in
                    self.currentInstallProcess = process
                }

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }

                do {
                    try process.run()
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    var timedOut = false
                    timer.schedule(deadline: .now() + 1800)
                    timer.setEventHandler { timedOut = true; process.terminate() }
                    timer.resume()

                    process.waitUntilExit()
                    timer.cancel()

                    Task { @MainActor in
                        self.currentInstallProcess = nil
                    }

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let remainingStdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if timedOut {
                        continuation.resume(returning: .failure("安装超时（30 分钟），请检查网络连接后重试"))
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Maven 安装成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "安装失败 (exit code \(process.terminationStatus))" : remainingStderr
                        continuation.resume(returning: .failure(errorMsg))
                    }
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    Task { @MainActor in
                        self.currentInstallProcess = nil
                    }
                    continuation.resume(returning: .failure("无法执行安装命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// 使用 Homebrew 卸载 Maven（带实时输出）
    func uninstallMaven(onOutput: @escaping @MainActor (String) -> Void) async -> OperationResult {
        let script = "\(brewPath) uninstall maven"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }
                stderrHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                    Task { @MainActor in onOutput(output) }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let remainingStdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let remainingStderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if !remainingStdout.isEmpty { Task { @MainActor in onOutput(remainingStdout) } }
                    if !remainingStderr.isEmpty { Task { @MainActor in onOutput(remainingStderr) } }

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: .success("Maven 卸载成功"))
                    } else {
                        let errorMsg = remainingStderr.isEmpty ? "卸载失败" : remainingStderr
                        continuation.resume(returning: .failure(errorMsg))
                    }
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    continuation.resume(returning: .failure("无法执行卸载命令: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - 私有方法

    private func runCommand(_ executable: String, arguments: [String]) async -> OperationResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
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
                        continuation.resume(returning: .failure(output))
                    }
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
    }
}
