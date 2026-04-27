import SwiftUI

// MARK: - Maven 管理视图

struct MavenView: View {
    @StateObject private var viewModel = MavenViewModel()
    @State private var showingUninstallAlert = false
    @State private var showingProgress = false

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isAvailable ? "Maven 已安装" : "Maven 未安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if viewModel.isAvailable {
                    Text(viewModel.mavenVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if viewModel.isAvailable {
                // 已安装：显示信息和操作
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        infoSection
                        settingsSection
                    }
                    .padding(24)
                }
            } else {
                // 未安装：显示安装引导
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "archivebox")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Maven 未安装")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Maven 是 Java 项目的构建和依赖管理工具")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: {
                        showingProgress = true
                        Task { await viewModel.install() }
                    }) {
                        Label("安装 Maven", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await viewModel.load()
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                showingProgress = true
                Task { await viewModel.uninstall() }
            }
        } message: {
            Text("确定要卸载 Maven 吗？卸载后将无法使用 mvn 命令。")
        }
        .sheet(isPresented: $showingProgress) {
            InstallProgressSheet(
                version: viewModel.isUninstalling ? "Maven" : "Maven",
                isInstalling: viewModel.isOperating,
                output: viewModel.operationOutput,
                isSuccess: viewModel.operationSuccess,
                error: viewModel.operationError,
                canRetryWithCompile: false,
                canAutoFix: false,
                onDismiss: {
                    showingProgress = false
                    Task { await viewModel.load() }
                },
                onCancel: {
                    viewModel.cancelOperation()
                },
                onRetryCompile: nil,
                onAutoFix: nil
            )
        }
    }

    // MARK: - 信息区域

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Maven 信息", systemImage: "info.circle")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("版本")
                        .foregroundColor(.secondary)
                    Text(viewModel.mavenVersion)
                }

                GridRow {
                    Text("安装路径")
                        .foregroundColor(.secondary)
                    Text(viewModel.mavenPath)
                        .font(.system(.caption, design: .monospaced))
                }

                GridRow {
                    Text("Maven Home")
                        .foregroundColor(.secondary)
                    Text(viewModel.mavenHome)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - 操作区域

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("操作", systemImage: "gearshape")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: {
                    showingProgress = true
                    Task { await viewModel.uninstall() }
                }) {
                    Label("卸载 Maven", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()

                Text("通过 Homebrew 安装的 Maven")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - ViewModel

@MainActor
class MavenViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var mavenVersion = ""
    @Published var mavenPath = ""
    @Published var mavenHome = ""
    @Published var isOperating = false
    @Published var isUninstalling = false

    // 操作进度
    @Published var operationOutput = ""
    @Published var operationSuccess = false
    @Published var operationError: String?

    private let service = MavenService.shared

    func load() async {
        isAvailable = service.checkMavenAvailable()

        if isAvailable {
            async let ver = service.getMavenVersion()
            async let home = service.getMavenHome()

            mavenVersion = await ver
            mavenHome = await home
            mavenPath = service.getMavenPath()
        } else {
            mavenVersion = "未安装"
            mavenPath = ""
            mavenHome = ""
        }
    }

    func cancelOperation() {
        service.cancelCurrentInstall()
        operationOutput += "\n\n⚠️ 操作已取消"
        isOperating = false
        isUninstalling = false
        operationError = "用户取消了操作"
    }

    func install() async {
        isOperating = true
        isUninstalling = false
        operationOutput = "📦 开始安装 Maven...\n\n"
        operationSuccess = false
        operationError = nil

        let result = await service.installMaven { [weak self] output in
            Task { @MainActor in
                self?.operationOutput += output + "\n"
            }
        }

        switch result {
        case .success:
            operationOutput += "\n✅ 安装完成"
            operationSuccess = true
            isAvailable = true
        case .failure(let error):
            operationOutput += "\n❌ 安装失败: \(error)"
            operationError = error
        }

        isOperating = false
    }

    func uninstall() async {
        isOperating = true
        isUninstalling = true
        operationOutput = "🗑️ 开始卸载 Maven...\n\n"
        operationSuccess = false
        operationError = nil

        let result = await service.uninstallMaven { [weak self] output in
            Task { @MainActor in
                self?.operationOutput += output + "\n"
            }
        }

        switch result {
        case .success:
            operationOutput += "\n✅ 卸载完成"
            operationSuccess = true
            isAvailable = false
            mavenVersion = "未安装"
            mavenPath = ""
            mavenHome = ""
        case .failure(let error):
            operationOutput += "\n❌ 卸载失败: \(error)"
            operationError = error
        }

        isOperating = false
        isUninstalling = false
    }
}

#Preview {
    MavenView()
}
