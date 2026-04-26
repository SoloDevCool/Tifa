import SwiftUI

struct XcodeView: View {
    @StateObject private var service = XcodeService.shared
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultIsError = false
    @State private var appToDelete: XcodeApp?
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .foregroundColor(.accentColor)
                    Text("Xcode 管理")
                        .font(.headline)
                }
                Spacer()

                let active = service.installations.first(where: { $0.isActive })
                if let active = active {
                    Text("当前: \(active.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: { service.detectInstallations() }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if service.isLoading && service.installations.isEmpty {
                ProgressView("检测中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // MARK: - Xcode 版本列表
                        Section {
                            if service.installations.isEmpty {
                                EmptyStateView(
                                    title: "未检测到 Xcode",
                                    systemImage: "hammer",
                                    description: "点击下方按钮安装 Xcode"
                                )
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(service.installations) { app in
                                        XcodeVersionRow(app: app) {
                                            Task {
                                                let result = await service.switchXcode(app)
                                                resultMessage = result.description
                                                resultIsError = result.isFailure
                                                showingResult = true
                                                if result.isSuccess { service.detectInstallations() }
                                            }
                                        } onUninstall: {
                                            appToDelete = app
                                            showingDeleteConfirm = true
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("已安装的 Xcode")
                                .font(.headline)
                        }

                        // MARK: - Command Line Tools
                        CLTSection()

                        // MARK: - 安装 Xcode
                        Section {
                            VStack(spacing: 10) {
                                Button(action: {
                                    NSWorkspace.shared.open(URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!)
                                }) {
                                    HStack {
                                        Label("从 App Store 安装 Xcode", systemImage: "macwindow")
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    NSWorkspace.shared.open(URL(string: "https://developer.apple.com/download/all/")!)
                                }) {
                                    HStack {
                                        Label("从开发者网站下载", systemImage: "globe")
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .help("下载历史版本 Xcode 或 GM Seed 版本")
                            }
                        } header: {
                            Text("安装 Xcode")
                                .font(.headline)
                        }
                    }
                    .padding()
                }
            }
        }
        .task { service.detectInstallations() }
        .sheet(isPresented: $showingResult) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(resultIsError ? .red : .green)
                    Text("操作结果")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingResult = false }
                }
                Text(resultMessage)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .textSelection(.enabled)
                Button("关闭") { showingResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 450, height: 200)
        }
        .alert("卸载确认", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { appToDelete = nil }
            Button("卸载", role: .destructive) {
                if let app = appToDelete {
                    Task {
                        let result = await service.uninstallXcode(app)
                        resultMessage = result.description
                        resultIsError = result.isFailure
                        showingResult = true
                        appToDelete = nil
                        if result.isSuccess { service.detectInstallations() }
                    }
                }
            }
        } message: {
            Text("确定要卸载 \(appToDelete?.displayName ?? "") 吗？此操作不可恢复。")
        }
    }
}

// MARK: - Xcode 版本行

private struct XcodeVersionRow: View {
    let app: XcodeApp
    let onSwitch: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 状态图标
            Image(systemName: app.isActive ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(app.isActive ? .green : .secondary.opacity(0.3))

            // 版本信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.headline)
                    if app.isActive {
                        Text("当前使用")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 16) {
                    if let build = app.buildVersion {
                        Label(build, systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Label(app.diskSizeFormatted, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(app.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 8) {
                if !app.isActive {
                    Button(action: onSwitch) {
                        Text("切换")
                    }
                    .buttonStyle(.bordered)
                }

                Menu {
                    Button(role: .destructive, action: onUninstall) {
                        Label("卸载", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .padding()
        .background(app.isActive
            ? Color.accentColor.opacity(0.08)
            : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(app.isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Command Line Tools 区域

private struct CLTSection: View {
    @State private var cltInstalled = false
    @State private var cltPath: String?
    @State private var cltVersion: String?
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultIsError = false

    var body: some View {
        Section {
            VStack(spacing: 10) {
                // CLT 状态
                HStack(spacing: 12) {
                    Image(systemName: cltInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(cltInstalled ? .green : .red)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(cltInstalled ? "Command Line Tools 已安装" : "Command Line Tools 未安装")
                            .font(.headline)
                        if let version = cltVersion {
                            Text(version)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let path = cltPath {
                            Text(path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                // 操作按钮
                HStack(spacing: 10) {
                    if !cltInstalled {
                        Button(action: {
                            Task {
                                let service = XcodeService.shared
                                let result = await service.installCLT()
                                resultMessage = result.description
                                resultIsError = result.isFailure
                                showingResult = true
                                if result.isSuccess { loadCLTStatus() }
                            }
                        }) {
                            Label("安装 Command Line Tools", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(action: {
                        // 在 Finder 中显示 CLT 路径
                        if let path = cltPath {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }
                    }) {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(cltPath == nil)
                }
            }
        } header: {
            Text("Command Line Tools")
                .font(.headline)
        }
        .onAppear { loadCLTStatus() }
        .sheet(isPresented: $showingResult) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(resultIsError ? .red : .green)
                    Text("操作结果")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showingResult = false }
                }
                Text(resultMessage)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .textSelection(.enabled)
                Button("关闭") { showingResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 450, height: 200)
        }
    }

    private func loadCLTStatus() {
        let service = XcodeService.shared
        let status = service.getCLTStatus()
        cltInstalled = status.installed
        cltPath = status.path
        cltVersion = status.version
    }
}

#Preview {
    XcodeView()
}
