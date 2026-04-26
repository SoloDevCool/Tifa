import SwiftUI

// MARK: - 设置视图

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingCleanupAlert = false
    @State private var showingUpdateAlert = false
    @State private var showingDoctorAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 顶部三列卡片
                HStack(spacing: 16) {
                    statusCard
                    installInfoCard
                    environmentCard
                }
                
                // 维护操作卡片
                maintenanceCard
                
                // 关于卡片
                aboutCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.08))
        .task {
            await viewModel.load()
        }
        .alert("清理确认", isPresented: $showingCleanupAlert) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                Task { await viewModel.cleanup() }
            }
        } message: {
            Text("这将删除所有已卸载包的旧版本。确定要继续吗？")
        }
        .alert("更新确认", isPresented: $showingUpdateAlert) {
            Button("取消", role: .cancel) {}
            Button("更新") {
                Task { await viewModel.update() }
            }
        } message: {
            Text("这将更新 Homebrew 本身到最新版本。确定要继续吗？")
        }
        .sheet(isPresented: $showingDoctorAlert) {
            DoctorResultView(diagnostics: viewModel.diagnostics)
        }
    }
    
    // MARK: - 状态卡片
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "checkmark.shield", title: "Homebrew 状态", color: viewModel.isHomebrewAvailable ? .green : .red)
            
            Spacer()
            
            HStack(spacing: 10) {
                Image(systemName: viewModel.isHomebrewAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.isHomebrewAvailable ? .green : .red)
                
                Text(viewModel.isHomebrewAvailable ? "已安装" : "未安装")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            
            Text(viewModel.isHomebrewAvailable ? "可以正常使用所有功能" : "请先安装 Homebrew")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            if viewModel.isHomebrewAvailable {
                HStack {
                    Spacer()
                    Text(viewModel.brewVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 安装信息卡片
    
    private var installInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "info.circle", title: "安装信息", color: .blue)
            
            infoRow(label: "安装路径", value: viewModel.brewPrefix, icon: "folder")
            infoRow(label: "Cellar 目录", value: viewModel.cellarPath, icon: "archivebox")
            infoRow(label: "可执行文件", value: viewModel.brewBinPath, icon: "terminal")
            
            Divider()
            
            infoRow(label: "Tap 数量", value: "\(viewModel.tapCount)", icon: "arrow.triangle.branch")
            infoRow(label: "已安装包", value: "\(viewModel.installedCount)", icon: "shippingbox")
            infoRow(label: "已安装 Cask", value: "\(viewModel.installedCaskCount)", icon: "macwindow")
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 环境信息卡片
    
    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "gearshape", title: "环境信息", color: .orange)
            
            infoRow(label: "Homebrew 前缀", value: viewModel.brewPrefix, icon: "building.2")
            infoRow(label: "Xcode CLT", value: viewModel.xcodeCLTStatus, icon: "wrench.and.screwdriver")
            infoRow(label: "系统架构", value: viewModel.architecture, icon: "cpu")
            infoRow(label: "系统版本", value: viewModel.systemVersion, icon: "desktopcomputer")
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 维护操作卡片
    
    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "wrench", title: "维护操作", color: .purple)
            
            VStack(spacing: 10) {
                actionRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "更新 Homebrew",
                    description: "更新 Homebrew 本体和软件包索引",
                    color: .blue
                ) {
                    showingUpdateAlert = true
                }
                
                Divider()
                
                actionRow(
                    icon: "trash",
                    title: "清理旧版本",
                    description: "删除所有已卸载包的旧版本缓存",
                    color: .orange
                ) {
                    showingCleanupAlert = true
                }
                
                Divider()
                
                actionRow(
                    icon: "stethoscope",
                    title: "运行诊断",
                    description: "检查 Homebrew 配置和潜在问题",
                    color: .green
                ) {
                    Task { await viewModel.runDoctor() }
                    showingDoctorAlert = true
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 关于卡片
    
    private var aboutCard: some View {
        HStack(spacing: 16) {
            cardHeader(icon: "questionmark.circle", title: "关于", color: .secondary)
            
            Spacer()
            
            infoRow(label: "版本", value: "1.0.0", icon: "tag")
            infoRow(label: "构建", value: "2026-04-03", icon: "calendar")
            infoRow(label: "系统", value: "macOS 13.0+", icon: "laptopcomputer")
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 卡片头
    
    private func cardHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.bottom, 2)
    }
    
    // MARK: - 信息行
    
    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14, height: 14)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    // MARK: - 操作行
    
    private func actionRow(icon: String, title: String, description: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.1))
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 诊断结果视图

struct DoctorResultView: View {
    let diagnostics: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("诊断结果")
                    .font(.headline)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
            
            ScrollView {
                Text(diagnostics.isEmpty ? "正在运行诊断..." : diagnostics)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

// MARK: - ViewModel

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var isHomebrewAvailable = false
    @Published var diagnostics = ""
    @Published var brewPrefix = "未知"
    @Published var cellarPath = "未知"
    @Published var brewBinPath = "未知"
    @Published var brewVersion = "未知"
    @Published var tapCount = 0
    @Published var installedCount = 0
    @Published var installedCaskCount = 0
    @Published var xcodeCLTStatus = "未知"
    @Published var architecture = "未知"
    @Published var systemVersion = "未知"
    
    private let service = HomebrewService.shared
    
    init() {
        isHomebrewAvailable = service.checkHomebrewAvailability()
    }
    
    func load() async {
        if isHomebrewAvailable {
            loadBrewInfo()
            brewVersion = await loadBrewVersion()
            installedCaskCount = await loadCaskCount()
            xcodeCLTStatus = await loadXcodeCLTStatus()
            loadSystemInfo()
        }
    }
    
    private func loadBrewInfo() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew") {
            brewPrefix = "/opt/homebrew"
            cellarPath = "/opt/homebrew/Cellar"
            brewBinPath = "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/Homebrew") {
            brewPrefix = "/usr/local"
            cellarPath = "/usr/local/Cellar"
            brewBinPath = "/usr/local/bin/brew"
        }
        
        if let enumerator = FileManager.default.enumerator(atPath: cellarPath) {
            var count = 0
            while enumerator.nextObject() != nil { count += 1 }
            installedCount = count
        }
        
        let tapDir = brewPrefix + "/Library/Taps"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tapDir) {
            tapCount = contents.count
        }
    }
    
    private func loadBrewVersion() async -> String {
        let result = await service.executeBrewCommand(arguments: ["--version"])
        switch result {
        case .success(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure:
            return "未知"
        }
    }
    
    private func loadCaskCount() async -> Int {
        let casks = await service.fetchInstalledCasks()
        return casks.count
    }
    
    private func loadXcodeCLTStatus() async -> String {
        let result = await service.executeBrewCommand(arguments: ["--prefix"])
        switch result {
        case .success(let output):
            let prefix = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return FileManager.default.fileExists(atPath: prefix) ? "已安装" : "未安装"
        case .failure:
            return "未安装"
        }
    }
    
    private func loadSystemInfo() {
        var sysinfo = utsname()
        uname(&sysinfo)
        let arch = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        architecture = arch.contains("arm64") ? "Apple Silicon (arm64)" : (arch.contains("x86_64") ? "Intel (x86_64)" : arch)
        
        let os = ProcessInfo.processInfo.operatingSystemVersion
        systemVersion = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    
    func cleanup() async {
        _ = await service.cleanupPackages()
    }
    
    func update() async {
        _ = await service.updateHomebrew()
    }
    
    func runDoctor() async {
        diagnostics = await service.getDiagnostics()
    }
}

#Preview {
    SettingsView()
}
