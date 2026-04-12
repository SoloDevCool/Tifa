import SwiftUI

/// 通用 Brew 安装日志弹窗
struct BrewInstallSheet: View {
    let title: String
    let formula: String
    let isInstalling: Bool
    @Binding var installLog: String
    let onInstall: (String) -> Void
    let onClose: () -> Void
    
    @State private var hasStarted = false
    @State private var refreshTrigger = 0  // 刷新计数器，强制视图更新
    
    private var logColor: Color {
        if installLog.contains("❌") {
            return .red
        } else if installLog.contains("✅") {
            return .green
        } else {
            return .primary
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 8) {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Image(systemName: "arrow.down.circle")
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                if !isInstalling && hasStarted && installLog.contains("✅") {
                    Label("完成", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if !isInstalling && hasStarted && installLog.contains("❌") {
                    Label("失败", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isInstalling)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 操作按钮
            HStack {
                if !hasStarted && !isInstalling {
                    Button(action: {
                        hasStarted = true
                        onInstall(formula)
                    }) {
                        Label("开始安装", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if isInstalling {
                    Text("正在安装中...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if !isInstalling && hasStarted {
                    Button("完成") { onClose() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider()
            
            // 日志区域
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 使用 refreshTrigger 作为 id，确保每次更新都重新渲染
                        Text(installLog.isEmpty ? "等待安装..." : installLog)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(logColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor))
                            .id(refreshTrigger)
                    }
                    .onChange(of: installLog) { _ in
                        refreshTrigger += 1
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(refreshTrigger, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 650, height: 450)
    }
}
