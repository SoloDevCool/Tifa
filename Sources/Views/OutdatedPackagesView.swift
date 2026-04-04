import SwiftUI

struct OutdatedPackagesView: View {
    @StateObject private var viewModel = OutdatedPackagesViewModel()
    @StateObject private var service = HomebrewService.shared
    @State private var showingUpdateLog = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button(action: {
                    showingUpdateLog = true
                    Task { await viewModel.brewUpdate() }
                }) {
                    Label("更新源", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("执行 brew update 更新 Homebrew 源索引")
                .disabled(viewModel.isUpdating)

                Spacer()

                if !viewModel.packages.isEmpty {
                    Button(action: { Task { await viewModel.upgradeAll() } }) {
                        Label("升级全部", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 内容
            if viewModel.isLoading {
                ProgressView("检查更新...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.packages.isEmpty {
                EmptyStateView(
                    title: "所有包都是最新版本",
                    systemImage: "checkmark.circle",
                    description: "当前没有可用的更新"
                )
            } else {
                List {
                    ForEach(viewModel.packages) { package in
                        OutdatedPackageRow(package: package, onUpgrade: {
                            Task { await viewModel.upgrade(package) }
                        })
                    }
                }
                .listStyle(.inset)
            }
        }
        .task {
            await viewModel.loadOutdatedPackages()
        }
        .sheet(isPresented: $showingUpdateLog) {
            BrewUpdateLogSheet(isUpdating: viewModel.isUpdating, log: service.updateLog) {
                showingUpdateLog = false
            }
        }
    }
}

// MARK: - 过时包行

struct OutdatedPackageRow: View {
    let package: BrewPackage
    let onUpgrade: () -> Void
    
    @State private var isUpgrading = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("当前版本: \(package.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                isUpgrading = true
                onUpgrade()
            }) {
                if isUpgrading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("升级", systemImage: "arrow.up.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUpgrading)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - ViewModel

@MainActor
class OutdatedPackagesViewModel: ObservableObject {
    @Published var packages: [BrewPackage] = []
    @Published var isLoading = false
    @Published var isUpdating = false
    
    private let service = HomebrewService.shared
    
    func loadOutdatedPackages() async {
        isLoading = true
        packages = await service.fetchOutdatedPackages()
        isLoading = false
    }
    
    func refresh() async {
        await loadOutdatedPackages()
    }
    
    func brewUpdate() async {
        isUpdating = true
        let result = await service.updateHomebrew()
        if case .success = result {
            await loadOutdatedPackages()
        }
        isUpdating = false
    }
    
    func upgrade(_ package: BrewPackage) async {
        let result = await service.upgradePackage(package.name)
        switch result {
        case .success:
            packages.removeAll { $0.id == package.id }
        case .failure:
            break
        }
    }
    
    func upgradeAll() async {
        _ = await service.upgradeAllPackages()
        await loadOutdatedPackages()
    }
}

// MARK: - 更新日志弹窗

struct BrewUpdateLogSheet: View {
    let isUpdating: Bool
    let log: String
    let onClose: () -> Void
    
    @State private var autoScroll = true
    @State private var lastLineCount = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                HStack(spacing: 8) {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Brew Update")
                }
                .font(.headline)
                
                Spacer()
                
                if isUpdating {
                    Text("更新中...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if log.contains("✅") {
                    Label("完成", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if log.contains("❌") {
                    Label("失败", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 日志区域
            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.isEmpty ? "等待输出..." : log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .id("logBottom")
                        .onChange(of: log) { _ in
                            if autoScroll {
                                withAnimation {
                                    proxy.scrollTo("logBottom", anchor: .bottom)
                                }
                            }
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: {
                        autoScroll.toggle()
                    }) {
                        Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.title3)
                            .foregroundColor(autoScroll ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        }
        .frame(width: 650, height: 450)
    }
}

#Preview {
    OutdatedPackagesView()
}
