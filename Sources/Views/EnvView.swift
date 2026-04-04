import SwiftUI

struct EnvView: View {
    @StateObject private var viewModel = EnvViewModel()
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var editingVar: EnvVariable?
    @State private var showingDeleteConfirm = false
    @State private var varToDelete: EnvVariable?
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var isEditingRaw = false
    @State private var rawFileContent = ""
    
    private var filteredVariables: [EnvVariable] {
        if searchText.isEmpty {
            return viewModel.variables
        }
        let query = searchText.lowercased()
        return viewModel.variables.filter {
            $0.name.lowercased().contains(query) || $0.value.lowercased().contains(query)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 文件选择和状态栏
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                    Picker("配置文件", selection: $viewModel.selectedFile) {
                        ForEach(viewModel.configFiles) { file in
                            HStack {
                                Text(file.name)
                                Text(file.exists() ? "" : " *")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .tag(file.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                
                Text(viewModel.currentShell)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(viewModel.variables.count) 个变量")
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
                
                // 编辑模式切换
                Picker("模式", selection: $isEditingRaw) {
                    Text("可视化").tag(false)
                    Text("文本编辑").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                
                Spacer()
                
                if !isEditingRaw {
                    Button(action: { showingAddSheet = true }) {
                        Label("新增变量", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if isEditingRaw {
                // 文本编辑模式
                VStack(spacing: 0) {
                    TextEditor(text: $rawFileContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    
                    HStack {
                        Spacer()
                        Button("保存文件") {
                            Task {
                                let result = viewModel.service.saveFileContent(rawFileContent, to: viewModel.selectedFile)
                                switch result {
                                case .success(let msg):
                                    resultMessage = msg
                                    showingResult = true
                                    await viewModel.refresh()
                                case .failure(let error):
                                    resultMessage = "保存失败: \(error)"
                                    showingResult = true
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
                .onChange(of: viewModel.selectedFile) { _ in
                    rawFileContent = viewModel.service.readFileContent(viewModel.selectedFile)
                }
                .onAppear {
                    rawFileContent = viewModel.service.readFileContent(viewModel.selectedFile)
                }
            } else {
                // 可视化列表模式
                if viewModel.isLoading && viewModel.variables.isEmpty {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredVariables.isEmpty {
                    EmptyStateView(
                        title: searchText.isEmpty ? "暂无环境变量" : "未找到匹配项",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: searchText.isEmpty ? "点击「新增变量」添加环境变量" : nil
                    )
                } else {
                    List(selection: $editingVar) {
                        ForEach(filteredVariables) { envVar in
                            EnvVariableRow(
                                envVar: envVar,
                                onEdit: { editingVar = envVar },
                                onDelete: { varToDelete = envVar; showingDeleteConfirm = true }
                            )
                            .tag(envVar)
                            .contextMenu {
                                Button("编辑") { editingVar = envVar }
                                Divider()
                                Button("删除", role: .destructive) {
                                    varToDelete = envVar
                                    showingDeleteConfirm = true
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索环境变量")
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.selectedFile) { _ in
            Task { await viewModel.refresh() }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEnvVariableSheet(
                onSave: { name, value, file in
                    Task {
                        let result = viewModel.service.saveVariable(name: name, value: value, to: file)
                        switch result {
                        case .success(let msg):
                            resultMessage = msg
                            await viewModel.refresh()
                        case .failure(let error):
                            resultMessage = "保存失败: \(error)"
                        }
                        showingResult = true
                        showingAddSheet = false
                    }
                },
                selectedFile: viewModel.selectedFile
            )
        }
        .sheet(item: $editingVar) { envVar in
            EditEnvVariableSheet(
                envVar: envVar,
                onSave: { name, value, file in
                    Task {
                        // 先删除旧的
                        _ = viewModel.service.deleteVariable(name: envVar.name, from: envVar.sourceFile)
                        // 再保存新的
                        let result = viewModel.service.saveVariable(name: name, value: value, to: file)
                        switch result {
                        case .success(let msg):
                            resultMessage = msg
                            await viewModel.refresh()
                        case .failure(let error):
                            resultMessage = "保存失败: \(error)"
                        }
                        showingResult = true
                        editingVar = nil
                    }
                }
            )
        }
        .alert("删除环境变量", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { varToDelete = nil }
            Button("删除", role: .destructive) {
                if let v = varToDelete {
                    Task {
                        let result = viewModel.service.deleteVariable(name: v.name, from: v.sourceFile)
                        switch result {
                        case .success(let msg):
                            resultMessage = msg
                            await viewModel.refresh()
                        case .failure(let error):
                            resultMessage = "删除失败: \(error)"
                        }
                        showingResult = true
                        varToDelete = nil
                    }
                }
            }
        } message: {
            Text("确定要从 \(varToDelete?.sourceFile ?? "") 中删除 \(varToDelete?.name ?? "") 吗？")
        }
        .sheet(isPresented: $showingResult) {
            VStack(spacing: 16) {
                HStack {
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
                
                Button("关闭") { showingResult = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(width: 450, height: 200)
        }
    }
}

// MARK: - 环境变量行

struct EnvVariableRow: View {
    let envVar: EnvVariable
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(envVar.name)
                    .font(.headline)
                
                Text(envVar.value)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            
            Spacer()
            
            Text(envVar.sourceFile)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("复制变量名") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(envVar.name, forType: .string) }
            Button("复制值") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(envVar.value, forType: .string) }
            Divider()
            Button("编辑") { onEdit() }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - 新增环境变量 Sheet

struct AddEnvVariableSheet: View {
    let onSave: (String, String, String) -> Void
    let selectedFile: String
    
    @State private var varName = ""
    @State private var varValue = ""
    @State private var targetFile: String
    @Environment(\.presentationMode) var presentationMode
    
    init(onSave: @escaping (String, String, String) -> Void, selectedFile: String) {
        self.onSave = onSave
        self.selectedFile = selectedFile
        self._targetFile = State(initialValue: selectedFile)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("新增环境变量")
                    .font(.headline)
                Spacer()
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("变量名")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("例如: JAVA_HOME", text: $varName)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("变量值")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("例如: /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home", text: $varValue)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            
            // 常用预设
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷预设")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PresetButton(title: "JAVA_HOME", name: "JAVA_HOME", value: "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home") {
                            varName = $0; varValue = $1
                        }
                        PresetButton(title: "ANDROID_HOME", name: "ANDROID_HOME", value: "$HOME/Library/Android/sdk") {
                            varName = $0; varValue = $1
                        }
                        PresetButton(title: "GOPATH", name: "GOPATH", value: "$HOME/go") {
                            varName = $0; varValue = $1
                        }
                        PresetButton(title: "PYTHONPATH", name: "PYTHONPATH", value: "/opt/homebrew/lib/python3.12/site-packages") {
                            varName = $0; varValue = $1
                        }
                        PresetButton(title: "GRADLE_HOME", name: "GRADLE_HOME", value: "/opt/homebrew/opt/gradle/libexec") {
                            varName = $0; varValue = $1
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("保存到")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("配置文件", selection: $targetFile) {
                    ForEach(EnvService.shared.getShellConfigFiles()) { file in
                        Text(file.name).tag(file.name)
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(.bordered)
                Button("保存") {
                    onSave(varName, varValue, targetFile)
                }
                .buttonStyle(.borderedProminent)
                .disabled(varName.isEmpty || varValue.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 580, height: 380)
    }
}

// MARK: - 编辑环境变量 Sheet

struct EditEnvVariableSheet: View {
    let envVar: EnvVariable
    let onSave: (String, String, String) -> Void
    
    @State private var varName: String
    @State private var varValue: String
    @State private var targetFile: String
    @Environment(\.presentationMode) var presentationMode
    
    init(envVar: EnvVariable, onSave: @escaping (String, String, String) -> Void) {
        self.envVar = envVar
        self.onSave = onSave
        self._varName = State(initialValue: envVar.name)
        self._varValue = State(initialValue: envVar.value)
        self._targetFile = State(initialValue: envVar.sourceFile)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("编辑环境变量")
                    .font(.headline)
                Spacer()
                Button("关闭") { presentationMode.wrappedValue.dismiss() }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("变量名")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("变量名", text: $varName)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("变量值")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("变量值", text: $varValue)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("保存到")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Picker("配置文件", selection: $targetFile) {
                    ForEach(EnvService.shared.getShellConfigFiles()) { file in
                        Text(file.name).tag(file.name)
                    }
                }
            }
            
            // 当前值预览
            VStack(alignment: .leading, spacing: 8) {
                Text("当前值预览")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("export \(varName)=\"\(varValue)\"")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
            
            HStack {
                Spacer()
                Button("取消") { presentationMode.wrappedValue.dismiss() }
                    .buttonStyle(.bordered)
                Button("保存") {
                    onSave(varName, varValue, targetFile)
                }
                .buttonStyle(.borderedProminent)
                .disabled(varName.isEmpty || varValue.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 340)
    }
}

// MARK: - 预设按钮

private struct PresetButton: View {
    let title: String
    let name: String
    let value: String
    let action: (String, String) -> Void
    
    var body: some View {
        Button(action: { action(name, value) }) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ShellConfigFile 扩展

private extension ShellConfigFile {
    func exists() -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - ViewModel

@MainActor
class EnvViewModel: ObservableObject {
    @Published var variables: [EnvVariable] = []
    @Published var configFiles: [ShellConfigFile] = []
    @Published var selectedFile = ".zshrc"
    @Published var isLoading = false
    @Published var currentShell = "/bin/zsh"
    
    let service = EnvService.shared
    
    func load() async {
        currentShell = service.getCurrentShell()
        configFiles = service.getShellConfigFiles()
        await refresh()
    }
    
    func refresh() async {
        isLoading = true
        variables = service.parseEnvVariables(from: selectedFile)
        isLoading = false
    }
}

#Preview {
    EnvView()
}
