import SwiftUI

struct InstalledPackagesView: View {
    @StateObject private var viewModel = InstalledPackagesViewModel()
    @StateObject private var service = HomebrewService.shared
    @State private var searchText = ""
    @State private var showingUpdateLog = false
    @State private var selectedPackage: BrewPackage?
    @State private var showingUninstallAlert = false
    @State private var showingDetail = false
    @State private var detailPackage: BrewPackage?
    @State private var detailInfo: String = ""
    
    var filteredPackages: [BrewPackage] {
        if searchText.isEmpty {
            return viewModel.packages
        }
        return viewModel.packages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
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
                
                Text("\(viewModel.packages.count) 个已安装包")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { Task { await viewModel.upgradeAll() } }) {
                    Label("升级全部", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 包列表
            if viewModel.isLoading && viewModel.packages.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPackages.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "暂无已安装的包" : "未找到匹配结果",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                    description: searchText.isEmpty ? nil : "尝试其他搜索词"
                )
            } else {
                List(selection: $selectedPackage) {
                    ForEach(filteredPackages) { package in
                        PackageRowView(
                            package: package,
                            onShowDetail: {
                                detailPackage = package
                                showingDetail = true
                                Task { await loadDetail(for: package) }
                            },
                            onUninstall: {
                                viewModel.selectedPackageForUninstall = package
                                showingUninstallAlert = true
                            }
                        )
                        .tag(package)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索已安装的包")
        .task {
            await viewModel.loadPackages()
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let package = viewModel.selectedPackageForUninstall {
                    Task { await viewModel.uninstall(package) }
                }
            }
        } message: {
            Text("确定要卸载 \(viewModel.selectedPackageForUninstall?.name ?? "") 吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingDetail) {
            PackageDetailSheet(package: detailPackage, info: detailInfo)
        }
        .sheet(isPresented: $showingUpdateLog) {
            BrewUpdateLogSheet(isUpdating: viewModel.isUpdating, log: service.updateLog) {
                showingUpdateLog = false
            }
        }
    }
    
    private func loadDetail(for package: BrewPackage) async {
        let info = await HomebrewService.shared.getPackageInfo(name: package.name)
        detailInfo = """
        包名：\(package.name)
        版本：\(package.version)
        
        完整信息：
        \(info?.description ?? "暂无详细描述")
        """
    }
}

// MARK: - 包详情弹窗

struct PackageDetailSheet: View {
    let package: BrewPackage?
    let info: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(package?.name ?? "未知")
                        .font(.title2.bold())
                    Text(package?.version ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
            }
            
            Divider()
            
            ScrollView {
                Text(info.isEmpty ? "加载中..." : info)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
}

// MARK: - 包行视图

struct PackageRowView: View {
    let package: BrewPackage
    let onShowDetail: () -> Void
    let onUninstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.headline)
                
                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if !package.version.isEmpty {
                Text(package.version)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // 查看详情按钮
            Button(action: onShowDetail) {
                Label("详情", systemImage: "info.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            
            // 卸载按钮（蓝色）
            Button(action: onUninstall) {
                Label("卸载", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - ViewModel

@MainActor
class InstalledPackagesViewModel: ObservableObject {
    @Published var packages: [BrewPackage] = []
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var selectedPackageForUninstall: BrewPackage?
    
    private let service = HomebrewService.shared
    
    func loadPackages() async {
        isLoading = true
        packages = await service.fetchInstalledPackages()
        isLoading = false
    }
    
    func refresh() async {
        await loadPackages()
    }
    
    func brewUpdate() async {
        isUpdating = true
        let result = await service.updateHomebrew()
        if case .success = result {
            await loadPackages()
        }
        isUpdating = false
    }
    
    func uninstall(_ package: BrewPackage) async {
        let result = await service.uninstallPackage(package.name)
        switch result {
        case .success:
            packages.removeAll { $0.id == package.id }
        case .failure(let error):
            print("卸载失败: \(error)")
        }
    }
    
    func upgradeAll() async {
        _ = await service.upgradeAllPackages()
        await loadPackages()
    }
}

#Preview {
    InstalledPackagesView()
}
