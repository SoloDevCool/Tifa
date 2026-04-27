import SwiftUI

// MARK: - Pip 源预设

struct PipSourcePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String

    static let tsinghua = PipSourcePreset(id: "tsinghua", name: "清华大学", url: "https://pypi.tuna.tsinghua.edu.cn/simple")
    static let aliyun = PipSourcePreset(id: "aliyun", name: "阿里云", url: "https://mirrors.aliyun.com/pypi/simple")
    static let ustc = PipSourcePreset(id: "ustc", name: "中国科技大学", url: "https://pypi.mirrors.ustc.edu.cn/simple")
    static let douban = PipSourcePreset(id: "douban", name: "豆瓣", url: "https://pypi.doubanio.com/simple")
    static let official = PipSourcePreset(id: "official", name: "官方源", url: "https://pypi.org/simple")

    static let allPresets: [PipSourcePreset] = [.tsinghua, .aliyun, .ustc, .douban, .official]

    static func == (lhs: PipSourcePreset, rhs: PipSourcePreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Pip 源视图

struct PipSourceView: View {
    @State private var selectedPreset: PipSourcePreset = .tsinghua
    @State private var isCustom = false
    @State private var customSourceUrl = ""
    @State private var showingSwitchResult = false
    @State private var switchResultMessage = ""
    @State private var currentSourceName = "加载中..."
    @State private var isApplying = false

    private let viewModel = PipSourceViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部当前状态栏
            HStack(spacing: 16) {
                Image(systemName: "diamond")
                    .font(.title3)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前 Pip 源")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentSourceName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 源选择列表（可滚动）
            sourceSelectionList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 底部操作栏（固定）
            bottomPanel
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

    // MARK: - 源选择列表

    private var sourceSelectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择 Pip 源")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(PipSourcePreset.allPresets) { preset in
                        PipSourceRow(
                            name: preset.name,
                            url: preset.url,
                            isSelected: selectedPreset == preset && !isCustom
                        ) {
                            selectedPreset = preset
                            isCustom = false
                        }

                        // 自定义入口（放在最后一个后面）
                        if preset == .official {
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

                Text("自定义 Pip 源")
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
            Text("源地址")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            TextField("https://pypi.example.com/simple", text: $customSourceUrl)
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
                    Text(isApplying ? "应用中..." : "应用 Pip 源")
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
        let currentUrl = await viewModel.getCurrentPipSource()
        for preset in PipSourcePreset.allPresets {
            if currentUrl.contains(preset.url) || preset.url.contains(currentUrl) {
                currentSourceName = preset.name
                selectedPreset = preset
                isCustom = false
                return
            }
        }

        if currentUrl.isEmpty {
            currentSourceName = "官方源（默认）"
        } else {
            currentSourceName = currentUrl
            customSourceUrl = currentUrl
            isCustom = true
        }
    }

    private func applySource() async {
        isApplying = true
        defer { isApplying = false }

        let targetUrl: String
        let targetName: String

        if isCustom {
            guard !customSourceUrl.isEmpty else { return }
            targetUrl = customSourceUrl
            targetName = "自定义"
        } else {
            targetUrl = selectedPreset.url
            targetName = selectedPreset.name
        }

        let result = await viewModel.switchPipSource(to: targetUrl)
        switch result {
        case .success(let output):
            switchResultMessage = "已切换 Pip 源到 \(targetName)\n\n地址: \(targetUrl)\n\n\(output)"
            currentSourceName = targetName
        case .failure(let error):
            switchResultMessage = "切换失败: \(error)"
        }
        showingSwitchResult = true
    }
}

// MARK: - Pip 源行视图

private struct PipSourceRow: View {
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
                    .frame(width: 90, alignment: .leading)

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

// MARK: - ViewModel

@MainActor
class PipSourceViewModel: ObservableObject {
    private let service = PyenvService.shared

    func getCurrentPipSource() async -> String {
        return await service.getPipSource()
    }

    func switchPipSource(to url: String) async -> OperationResult {
        return await service.setPipSource(url)
    }
}

#Preview {
    PipSourceView()
}
