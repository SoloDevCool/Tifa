import SwiftUI

struct RVMGemsetView: View {
    @StateObject private var viewModel = RVMGemsetViewModel()
    @State private var selectedGemset: String?
    @State private var newGemsetName = ""
    @State private var showingCreateAlert = false
    @State private var showingDeleteAlert = false
    @State private var gemsetToDelete: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // 当前 Ruby 和 Gemset 信息
            HStack {
                if !viewModel.currentRuby.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "cube.fill")
                            .foregroundColor(.accentColor)
                        Text("Ruby: \(viewModel.currentRuby)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text("\(viewModel.gemsets.count) 个 Gemset")
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
                
                Button(action: { newGemsetName = ""; showingCreateAlert = true }) {
                    Label("新建 Gemset", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Gemset 列表
            if viewModel.isLoading && viewModel.gemsets.isEmpty {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.isRVMAvailable {
                EmptyStateView(
                    title: "RVM 未安装",
                    systemImage: "exclamationmark.triangle",
                    description: "请先安装 RVM"
                )
            } else if viewModel.gemsets.isEmpty {
                EmptyStateView(
                    title: "暂无 Gemset",
                    systemImage: "folder",
                    description: "点击\"新建 Gemset\"创建一个"
                )
            } else {
                List(selection: $selectedGemset) {
                    ForEach(viewModel.gemsets, id: \.self) { gemset in
                        HStack {
                            Image(systemName: gemset == viewModel.currentGemset ? "checkmark.circle.fill" : "folder")
                                .foregroundColor(gemset == viewModel.currentGemset ? .green : .secondary)
                            
                            Text(gemset)
                                .font(.headline)
                            
                            if gemset == viewModel.currentGemset {
                                Text("当前")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            if gemset != "default" && gemset != "global" {
                                Button(action: {
                                    gemsetToDelete = gemset
                                    showingDeleteAlert = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button(action: {
                                Task { await viewModel.useGemset(gemset) }
                            }) {
                                Label("使用", systemImage: "arrow.right.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                        .tag(gemset)
                    }
                }
                .listStyle(.inset)
            }
        }
        .task {
            await viewModel.load()
        }
        .alert("新建 Gemset", isPresented: $showingCreateAlert) {
            TextField("名称", text: $newGemsetName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                if !newGemsetName.isEmpty {
                    Task { await viewModel.createGemset(newGemsetName) }
                }
            }
            .disabled(newGemsetName.isEmpty)
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let gemset = gemsetToDelete {
                    Task { await viewModel.deleteGemset(gemset) }
                }
            }
        } message: {
            Text("确定要删除 Gemset \"\(gemsetToDelete ?? "")\" 吗？")
        }
    }
}

// MARK: - ViewModel

@MainActor
class RVMGemsetViewModel: ObservableObject {
    @Published var gemsets: [String] = []
    @Published var isLoading = false
    @Published var isRVMAvailable = false
    @Published var currentRuby: String = ""
    @Published var currentGemset: String = ""
    
    private let service = RVMService.shared
    
    func load() async {
        isRVMAvailable = service.checkRVMAvailability()
        guard isRVMAvailable else { return }
        
        isLoading = true
        async let cur = service.getCurrentRubyVersion()
        async let def = service.getDefaultRubyVersion()
        let current = await cur
        let defaultVer = await def
        currentRuby = defaultVer
        
        let result = await service.listGemsets(rubyVersion: defaultVer)
        gemsets = result
        currentGemset = current
        isLoading = false
    }
    
    func refresh() async {
        await load()
    }
    
    func useGemset(_ name: String) async {
        _ = await service.executeCommand(arguments: ["gemset", "use", name])
        await load()
    }
    
    func createGemset(_ name: String) async {
        _ = await service.executeCommand(arguments: ["gemset", "create", name])
        await load()
    }
    
    func deleteGemset(_ name: String) async {
        _ = await service.executeCommand(arguments: ["gemset", "delete", name, "--force"])
        await load()
    }
}

#Preview {
    RVMGemsetView()
}
