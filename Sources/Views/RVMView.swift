import SwiftUI

struct RVMView: View {
    @StateObject private var viewModel = RVMViewModel()
    @State private var searchText = ""
    @State private var selectedVersion: RubyVersion?
    @State private var showingInstallSheet = false
    @State private var showingUninstallAlert = false
    @State private var versionToUninstall: RubyVersion?
    
    var filteredRubies: [RubyVersion] {
        if searchText.isEmpty {
            return viewModel.rubies
        }
        return viewModel.rubies.filter {
            $0.version.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRVMAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRVMAvailable ? "RVM 已安装" : "RVM 未安装")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let current = viewModel.currentRubyVersion {
                    Text("当前: \(current)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(viewModel.rubies.count) 个 Ruby 版本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                Button(action: { showingInstallSheet = true }) {
                    Label("安装版本", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Ruby 版本列表
            if viewModel.isLoading && viewModel.rubies.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.isRVMAvailable {
                EmptyStateView(
                    title: "RVM 未安装",
                    systemImage: "exclamationmark.triangle",
                    description: "请先在终端执行: \\curl -sSL https://get.rvm.io | bash -s stable"
                )
            } else if filteredRubies.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "暂无已安装的 Ruby" : "未找到匹配版本",
                    systemImage: searchText.isEmpty ? "cube" : "magnifyingglass"
                )
            } else {
                List(selection: $selectedVersion) {
                    ForEach(filteredRubies) { ruby in
                        RubyVersionRow(
                            ruby: ruby,
                            onSetDefault: {
                                Task { await viewModel.setDefault(ruby) }
                            },
                            onUninstall: {
                                versionToUninstall = ruby
                                showingUninstallAlert = true
                            }
                        )
                        .tag(ruby)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Ruby 版本")
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallRubySheet(viewModel: viewModel, isPresented: $showingInstallSheet)
        }
        .alert("确认卸载", isPresented: $showingUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let ruby = versionToUninstall {
                    Task { await viewModel.uninstall(ruby) }
                }
            }
        } message: {
            Text("确定要卸载 Ruby \(versionToUninstall?.version ?? "") 吗？")
        }
    }
}

// MARK: - Ruby 版本行

struct RubyVersionRow: View {
    let ruby: RubyVersion
    let onSetDefault: () -> Void
    let onUninstall: () -> Void
    
    @State private var isSettingDefault = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            if ruby.isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 32)
            } else if ruby.isCurrent {
                Image(systemName: "circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32)
            } else {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.3))
                    .frame(width: 32)
            }
            
            // 版本信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ruby.version)
                        .font(.headline)
                    
                    if ruby.isDefault {
                        Text("默认")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    } else if ruby.isCurrent {
                        Text("当前")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Text("ruby-\(ruby.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 设置默认按钮
            if !ruby.isDefault {
                Button(action: {
                    isSettingDefault = true
                    onSetDefault()
                }) {
                    if isSettingDefault {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("设为默认", systemImage: "star")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSettingDefault)
            }
            
            // 卸载按钮
            if !ruby.isCurrent {
                Button(action: onUninstall) {
                    Label("卸载", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 安装 Ruby Sheet

struct InstallRubySheet: View {
    @ObservedObject var viewModel: RVMViewModel
    @Binding var isPresented: Bool
    @State private var installVersion = ""
    @State private var isSearching = false
    @State private var searchResults: [String] = []
    @State private var isInstalling = false
    
    private let commonVersions = ["3.3.0", "3.2.2", "3.2.0", "3.1.3", "3.1.0", "3.0.5", "3.0.0", "2.7.8"]
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("安装 Ruby")
                    .font(.headline)
                Spacer()
                Button("关闭") { isPresented = false }
            }
            
            // 快捷选择
            VStack(alignment: .leading, spacing: 8) {
                Text("常用版本")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                FlowLayout(spacing: 8) {
                    ForEach(commonVersions, id: \.self) { version in
                        let installed = viewModel.rubies.contains(where: { $0.version == version })
                        Button(action: { installVersion = version }) {
                            HStack(spacing: 4) {
                                Text(version)
                                    .font(.caption)
                                if installed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(installed ? Color.green.opacity(0.15) : (installVersion == version ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
                            .foregroundColor(installed ? .green : (installVersion == version ? .white : .primary))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(installed ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // 手动输入
            HStack {
                TextField("输入版本号，如 3.3.0", text: $installVersion)
                    .textFieldStyle(.roundedBorder)
                
                Button("在线搜索") {
                    Task { await searchOnline() }
                }
                .buttonStyle(.bordered)
                .disabled(isSearching)
            }
            
            // 搜索结果
            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可用版本")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(searchResults, id: \.self) { version in
                                let installed = viewModel.rubies.contains(where: { $0.version == version })
                                Button(action: { installVersion = version }) {
                                    HStack(spacing: 4) {
                                        Text(version)
                                            .font(.caption)
                                        if installed {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9))
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(installed ? Color.green.opacity(0.15) : (installVersion == version ? Color.accentColor : Color(nsColor: .controlBackgroundColor)))
                                    .foregroundColor(installed ? .green : (installVersion == version ? .white : .primary))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(installed ? Color.green : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }
            
            Divider()
            
            // 安装按钮
            HStack {
                Spacer()
                Button("安装") {
                    Task {
                        isInstalling = true
                        await viewModel.install(version: installVersion)
                        isInstalling = false
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(installVersion.isEmpty || isInstalling)
            }
        }
        .padding(24)
        .frame(width: 550, height: 420)
    }
    
    private func searchOnline() async {
        isSearching = true
        searchResults = await viewModel.listKnownRubies()
        isSearching = false
    }
}

// MARK: - 流式布局（版本标签）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX)
        }
        
        totalHeight = currentY + rowHeight
        
        return ArrangeResult(size: CGSize(width: totalWidth, height: totalHeight), positions: positions)
    }
}

// MARK: - ViewModel

@MainActor
class RVMViewModel: ObservableObject {
    @Published var rubies: [RubyVersion] = []
    @Published var isLoading = false
    @Published var isRVMAvailable = false
    @Published var currentRubyVersion: String?
    
    private let service = RVMService.shared
    
    func load() async {
        isRVMAvailable = service.checkRVMAvailability()
        guard isRVMAvailable else { return }
        
        isLoading = true
        async let versions = service.listInstalledRubies()
        async let current = service.getCurrentRubyVersion()
        rubies = await versions
        currentRubyVersion = await current
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    func setDefault(_ ruby: RubyVersion) async {
        let result = await service.useRuby(version: ruby.version)
        switch result {
        case .success:
            await load()
        case .failure(let error):
            print("切换失败: \(error)")
        }
    }
    
    func install(version: String) async {
        guard !version.isEmpty else { return }
        let result = await service.installRuby(version: version)
        switch result {
        case .success:
            await load()
        case .failure(let error):
            print("安装失败: \(error)")
        }
    }
    
    func uninstall(_ ruby: RubyVersion) async {
        let result = await service.uninstallRuby(version: ruby.version)
        switch result {
        case .success:
            rubies.removeAll { $0.id == ruby.id }
        case .failure(let error):
            print("卸载失败: \(error)")
        }
    }
    
    func listKnownRubies() async -> [String] {
        return await service.listKnownRubies()
    }
}

#Preview {
    RVMView()
}
