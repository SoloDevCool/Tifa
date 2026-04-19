import SwiftUI

// MARK: - Ruby 安装源预设

struct RubyInstallSourcePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String

    static let official = RubyInstallSourcePreset(id: "official", name: "官方源", url: "https://cache.ruby-lang.org/pub/ruby")
    static let taobao = RubyInstallSourcePreset(id: "taobao", name: "淘宝镜像", url: "https://npm.taobao.org/mirrors/ruby")
    static let ustc = RubyInstallSourcePreset(id: "ustc", name: "中科大", url: "https://mirrors.ustc.edu.cn/ruby/")
    static let tsinghua = RubyInstallSourcePreset(id: "tsinghua", name: "清华大学", url: "https://mirrors.tuna.tsinghua.edu.cn/ruby/")

    static let allPresets: [RubyInstallSourcePreset] = [.official, .taobao, .ustc, .tsinghua]

    static func == (lhs: RubyInstallSourcePreset, rhs: RubyInstallSourcePreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - RVM 安装源视图

struct RVMSourceView: View {
    @State private var selectedSource: RubyInstallSourcePreset = .official
    @State private var isCustomSource = false
    @State private var customSourceUrl = ""
    @State private var showingSwitchResult = false
    @State private var switchResultMessage = ""
    @State private var currentSourceName = "加载中..."
    @State private var isApplying = false
    
    private let viewModel = RVMSettingsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部当前状态栏
            HStack(spacing: 16) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前 Ruby 安装源")
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
                // 上半部分：镜像源选择列表
                sourceSelectionList

                Divider()

                // 底部应用按钮
                bottomPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await detectCurrentSource()
        }
        .sheet(isPresented: $showingSwitchResult) {
            switchResultSheet
        }
    }

    // MARK: - 镜像源列表

    private var sourceSelectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择 Ruby 安装源")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(RubyInstallSourcePreset.allPresets) { preset in
                        SourceRow(
                            name: preset.name,
                            url: preset.url,
                            isSelected: selectedSource == preset && !isCustomSource
                        ) {
                            selectedSource = preset
                            isCustomSource = false
                        }

                        // 自定义入口
                        if preset == .tsinghua {
                            customToggleRow

                            if isCustomSource {
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
        Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isCustomSource.toggle() } }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isCustomSource ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isCustomSource {
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

                Image(systemName: isCustomSource ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCustomSource ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCustomSource ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
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
            TextField("https://mirrors.example.com/ruby/", text: $customSourceUrl)
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
        HStack {
            Spacer()

            Button(action: { Task { await detectCurrentSource() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("检测当前源")
                }
                .padding(.horizontal, 20)
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
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(isApplying ? Color.gray : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isApplying)

            Spacer()
        }
        .padding(.vertical, 14)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - 结果弹窗

    private var switchResultSheet: some View {
        VStack(spacing: 16) {
            Text("切换结果")
                .font(.headline)
            ScrollView {
                Text(switchResultMessage)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            Button("关闭") { showingSwitchResult = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 550, height: 350)
    }

    // MARK: - 方法

    private func detectCurrentSource() async {
        let currentUrl = await viewModel.getRubyInstallSource()
        for preset in RubyInstallSourcePreset.allPresets {
            if currentUrl.contains(preset.url) || preset.url.contains(currentUrl) {
                currentSourceName = preset.name
                selectedSource = preset
                isCustomSource = false
                return
            }
        }
        if currentUrl.isEmpty || currentUrl == "https://cache.ruby-lang.org/pub/ruby" {
            currentSourceName = "官方源（默认）"
        } else {
            currentSourceName = currentUrl
            customSourceUrl = currentUrl
            isCustomSource = true
        }
    }

    private func applySource() async {
        isApplying = true
        defer { isApplying = false }

        let targetUrl: String
        let targetName: String

        if isCustomSource {
            guard !customSourceUrl.isEmpty else { return }
            targetUrl = customSourceUrl
            targetName = "自定义"
        } else {
            targetUrl = selectedSource.url
            targetName = selectedSource.name
        }

        let result = await viewModel.setRubyInstallSource(to: targetUrl)
        switch result {
        case .success(let output):
            switchResultMessage = "已切换 Ruby 安装源到 \(targetName)\n\n地址: \(targetUrl)\n\n\(output)"
            currentSourceName = targetName
        case .failure(let error):
            switchResultMessage = "切换失败: \(error)"
        }
        showingSwitchResult = true
    }
}

// MARK: - 源行视图

private struct SourceRow: View {
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
    RVMSourceView()
}
