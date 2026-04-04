import SwiftUI

struct TapView: View {
    @StateObject private var viewModel = TapViewModel()
    @State private var newTapName = ""
    @State private var showingAddSheet = false
    @State private var showingRemoveAlert = false
    @State private var tapToRemove: String?
    @State private var searchText = ""
    
    var filteredTaps: [String] {
        if searchText.isEmpty { return viewModel.taps }
        return viewModel.taps.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                Text("\(viewModel.taps.count) 个 Tap")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showingAddSheet = true }) {
                    Label("添加 Tap", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Tap 列表
            if viewModel.isLoading && viewModel.taps.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTaps.isEmpty {
                EmptyStateView(
                    title: searchText.isEmpty ? "暂无 Tap" : "未找到匹配结果",
                    systemImage: "arrow.triangle.branch",
                    description: searchText.isEmpty ? "Tap 是 Homebrew 的第三方软件仓库\n点击「添加 Tap」添加仓库源" : "尝试其他搜索词"
                )
            } else {
                List {
                    ForEach(filteredTaps, id: \.self) { tap in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tap)
                                    .font(.headline)
                                
                                if isDefaultTap(tap) {
                                    Text("Homebrew 官方")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if !isDefaultTap(tap) {
                                Button(action: {
                                    tapToRemove = tap
                                    showingRemoveAlert = true
                                }) {
                                    Label("移除", systemImage: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            } else {
                                Text("默认")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Tap...")
        .task {
            await viewModel.load()
        }
        .alert("移除 Tap", isPresented: $showingRemoveAlert) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                if let tap = tapToRemove {
                    Task {
                        let result = await viewModel.removeTap(tap)
                        switch result {
                        case .success:
                            await viewModel.refresh()
                        case .failure(let error):
                            viewModel.errorMessage = error
                        }
                    }
                }
            }
        } message: {
            Text("确定要移除 Tap「\(tapToRemove ?? "")」吗？\n通过此 Tap 安装的包不会被移除。")
        }
        .alert("操作失败", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showingAddSheet) {
            addTapSheet
        }
    }
    
    private func isDefaultTap(_ tap: String) -> Bool {
        let defaults = ["homebrew/core", "homebrew/cask"]
        return defaults.contains(tap)
    }
    
    private var addTapSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Text("添加 Tap")
                    .font(.headline)
                Spacer()
                Button("关闭") { showingAddSheet = false }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap 名称")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("格式: user/repo，例如 homebrew/services")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("user/repo", text: $newTapName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTap() }
                    Button("添加") {
                        addTap()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTapName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("常用 Tap")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(commonTaps, id: \.self) { tap in
                            HStack {
                                Text(tap)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                if viewModel.taps.contains(tap) {
                                    Label("已添加", systemImage: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Button("添加") {
                                        newTapName = tap
                                        addTap()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
    
    private let commonTaps = [
        "homebrew/services",
        "homebrew/cask-fonts",
        "homebrew/cask-versions",
        "homebrew/command-not-found",
    ]
    
    private func addTap() {
        guard !newTapName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let tap = newTapName.trimmingCharacters(in: .whitespaces)
        newTapName = ""
        showingAddSheet = false
        Task {
            let result = await viewModel.addTap(tap)
            switch result {
            case .success:
                await viewModel.refresh()
            case .failure(let error):
                viewModel.errorMessage = error
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class TapViewModel: ObservableObject {
    @Published var taps: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let service = HomebrewService.shared
    
    func load() async {
        isLoading = true
        taps = await service.fetchTaps()
        isLoading = false
    }
    
    func refresh() async { await load() }
    
    func addTap(_ tap: String) async -> OperationResult {
        let result = await service.addTap(tap)
        return result
    }
    
    func removeTap(_ tap: String) async -> OperationResult {
        return await service.removeTap(tap)
    }
}

#Preview {
    TapView()
}
