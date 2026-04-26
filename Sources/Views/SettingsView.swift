import SwiftUI

// MARK: - 设置视图

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingCleanupAlert = false
    @State private var showingUpdateAlert = false
    @State private var showingDoctorAlert = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Homebrew 状态
                Section {
                    HStack {
                        Image(systemName: viewModel.isHomebrewAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(viewModel.isHomebrewAvailable ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(viewModel.isHomebrewAvailable ? "Homebrew 已安装" : "Homebrew 未安装")
                                .font(.headline)
                            
                            Text(viewModel.isHomebrewAvailable ? "可以正常使用" : "请先安装 Homebrew")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("状态")
                        .font(.headline)
                }
                
                // 安装信息
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(title: "安装路径", value: viewModel.brewPrefix)
                        InfoRow(title: "Cellar 目录", value: viewModel.cellarPath)
                        InfoRow(title: "可执行文件", value: viewModel.brewBinPath)
                        InfoRow(title: "Tap 数量", value: "\(viewModel.tapCount)")
                        InfoRow(title: "已安装包数", value: "\(viewModel.installedCount)")
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("安装信息")
                        .font(.headline)
                }
                
                // 维护操作
                Section {
                    VStack(spacing: 12) {
                        Button(action: { showingUpdateAlert = true }) {
                            HStack {
                                Label("更新 Homebrew", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { showingCleanupAlert = true }) {
                            HStack {
                                Label("清理旧版本", systemImage: "trash")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            Task { await viewModel.runDoctor() }
                            showingDoctorAlert = true
                        }) {
                            HStack {
                                Label("运行诊断", systemImage: "stethoscope")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("维护")
                        .font(.headline)
                }
                
                // 关于
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(title: "版本", value: "1.0.0")
                        InfoRow(title: "构建日期", value: "2026-04-03")
                        InfoRow(title: "兼容系统", value: "macOS 13.0+")
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                } header: {
                    Text("关于")
                        .font(.headline)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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
}

// MARK: - 信息行

private struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - 诊断结果视图

struct DoctorResultView: View {
    let diagnostics: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
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
    @Published var tapCount = 0
    @Published var installedCount = 0
    
    private let service = HomebrewService.shared
    
    init() {
        isHomebrewAvailable = service.checkHomebrewAvailability()
        if isHomebrewAvailable {
            loadBrewInfo()
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
