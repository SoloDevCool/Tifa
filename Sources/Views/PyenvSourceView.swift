import SwiftUI

// MARK: - Python 安装源预设

struct PythonMirrorPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String

    static let official = PythonMirrorPreset(id: "official", name: "官方源", url: "")
    static let npmmirror = PythonMirrorPreset(id: "npmmirror", name: "npmmirror", url: "https://registry.npmmirror.com/binary.html?path=python/")
    static let ustc = PythonMirrorPreset(id: "ustc", name: "中科大", url: "https://mirrors.ustc.edu.cn/python/")
    static let huawei = PythonMirrorPreset(id: "huawei", name: "华为云", url: "https://repo.huaweicloud.com/python/")
    static let tsinghua = PythonMirrorPreset(id: "tsinghua", name: "清华大学", url: "https://mirrors.tuna.tsinghua.edu.cn/python/")

    static let allPresets: [PythonMirrorPreset] = [.official, .npmmirror, .ustc, .huawei, .tsinghua]

    static func == (lhs: PythonMirrorPreset, rhs: PythonMirrorPreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Pyenv 安装源视图

struct PyenvSourceView: View {
    @StateObject private var viewModel = PyenvSettingsViewModel()
    @State private var selectedConfigFile = ".zshrc"
    @State private var selectedPreset: PythonMirrorPreset = .official
    @State private var isCustom = false
    @State private var customUrl = ""
    @State private var currentSourceName = "加载中..."
    @State private var isApplying = false
    @State private var showingResult = false
    @State private var resultMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶部当前状态栏
            HStack(spacing: 16) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前 Python 安装源")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentSourceName)
                        .font(.headline)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 主内容区
            VStack(spacing: 0) {
                // 镜像源选择列表
                sourceSelectionList

                Divider()

                // 底部面板
                bottomPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await detectCurrentSource()
        }
        .sheet(isPresented: $showingResult) {
            resultSheet
        }
    }

    // MARK: - 镜像源列表

    private var sourceSelectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择 Python 安装源")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(PythonMirrorPreset.allPresets) { preset in
                        PyenvSourceRow(
                            name: preset.name,
                            url: preset.url.isEmpty ? "默认（官方源）" : preset.url,
                            isSelected: selectedPreset == preset && !isCustom
                        ) {
                            selectedPreset = preset
                            isCustom = false
                        }

                        // 自定义入口
                        if preset == .tsinghua {
                            customToggleRow

                            if isCustom {
                                customFieldsPanel
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - 自定义切换行

    private var customToggleRow: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isCustom.toggle() } }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isCustom ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isCustom {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }

                Image(systemName: "slider.horizontal.3")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                Text("自定义安装源")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: isCustom ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCustom ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCustom ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 自定义输入面板

    private var customFieldsPanel: some View {
        HStack(spacing: 12) {
            Text("镜像地址")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            TextField("https://mirrors.example.com/python/", text: $customUrl)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 底部面板

    private var bottomPanel: some View {
        HStack(spacing: 12) {
            // 配置文件选择
            Picker("写入配置到", selection: $selectedConfigFile) {
                Text(".zshrc").tag(".zshrc")
                Text(".zshenv").tag(".zshenv")
                Text(".bash_profile").tag(".bash_profile")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer()

            Button(action: { Task { await detectCurrentSource() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("检测")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button(action: { Task { await applySource() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                    Text(isApplying ? "应用中..." : "应用安装源")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(isApplying ? Color.gray : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 结果弹窗

    private var resultSheet: some View {
        VStack(spacing: 16) {
            Text("配置结果")
                .font(.headline)
            ScrollView {
                Text(resultMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            Button("关闭") { showingResult = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 500, height: 300)
    }

    // MARK: - 方法

    private func detectCurrentSource() async {
        let currentUrl = await viewModel.getPythonMirrorSource()
        if currentUrl.isEmpty {
            currentSourceName = "官方源（默认）"
            selectedPreset = .official
            isCustom = false
        } else {
            let matched = PythonMirrorPreset.allPresets.first { preset in
                !preset.url.isEmpty && (currentUrl.contains(preset.url) || preset.url.contains(currentUrl))
            }
            if let matched = matched {
                currentSourceName = matched.name
                selectedPreset = matched
                isCustom = false
            } else {
                currentSourceName = currentUrl
                customUrl = currentUrl
                isCustom = true
            }
        }
    }

    private func applySource() async {
        isApplying = true
        defer { isApplying = false }

        let targetUrl: String
        let targetName: String

        if isCustom {
            guard !customUrl.isEmpty else { return }
            targetUrl = customUrl
            targetName = "自定义"
        } else {
            targetUrl = selectedPreset.url
            targetName = selectedPreset.name
        }

        if targetUrl.isEmpty {
            let result = await viewModel.removePythonMirrorSource(from: selectedConfigFile)
            switch result {
            case .success(let msg):
                resultMessage = "已恢复为官方源\n\n\(msg)"
                currentSourceName = "官方源（默认）"
            case .failure(let error):
                resultMessage = "操作失败: \(error)"
            }
        } else {
            let result = await viewModel.setPythonMirrorSource(targetUrl, to: selectedConfigFile)
            switch result {
            case .success(let msg):
                resultMessage = "已切换到 \(targetName)\n\n\(msg)"
                currentSourceName = targetName
            case .failure(let error):
                resultMessage = "切换失败: \(error)"
            }
        }
        showingResult = true
    }
}

// MARK: - 源行视图

private struct PyenvSourceRow: View {
    let name: String
    let url: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(width: 80, alignment: .leading)

                Text(url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PyenvSourceView()
}
