import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索 Homebrew 包", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await viewModel.search(query: searchText) }
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        viewModel.clearResults()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button("搜索") {
                    Task { await viewModel.search(query: searchText) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 结果列表
            if viewModel.isLoading {
                ProgressView("搜索中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty && !searchText.isEmpty {
                EmptyStateView(
                    title: "未找到结果",
                    systemImage: "magnifyingglass",
                    description: "尝试其他搜索词"
                )
            } else if viewModel.results.isEmpty {
                EmptyStateView(
                    title: "开始搜索",
                    systemImage: "magnifyingglass",
                    description: "输入包名进行搜索"
                )
            } else {
                List {
                    ForEach(viewModel.results) { result in
                        SearchResultRow(result: result)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Homebrew 包")
    }
}

// MARK: - 搜索结果行

struct SearchResultRow: View {
    let result: SearchResult
    @State private var isExpanded = false
    @State private var packageInfo: BrewPackage?
    @State private var isInstalling = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.headline)
                    
                    Text(result.tap)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let info = packageInfo, !info.version.isEmpty {
                    Text(info.version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Button(action: { Task { await installPackage() } }) {
                    if isInstalling {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("安装", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)
            }
            
            if !result.description.isEmpty {
                Text(result.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
        .task {
            await loadPackageInfo()
        }
    }
    
    private func loadPackageInfo() async {
        let info = await HomebrewService.shared.getPackageInfo(name: result.name)
        await MainActor.run {
            self.packageInfo = info
        }
    }
    
    private func installPackage() async {
        isInstalling = true
        _ = await HomebrewService.shared.installPackage(result.name)
        isInstalling = false
    }
}

// MARK: - ViewModel

@MainActor
class SearchViewModel: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var isLoading = false
    
    private let service = HomebrewService.shared
    
    func search(query: String) async {
        guard !query.isEmpty else { return }
        
        isLoading = true
        results = await service.searchPackages(query: query)
        isLoading = false
    }
    
    func clearResults() {
        results = []
    }
}

#Preview {
    SearchView()
}
