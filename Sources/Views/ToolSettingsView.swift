import SwiftUI

struct ToolSettingsView: View {
    @AppStorage("systemMetricsRefreshInterval") private var metricsInterval: TimeInterval = 5.0
    @AppStorage("systemProcessesRefreshInterval") private var processesInterval: TimeInterval = 5.0
    @AppStorage("systemPortsRefreshInterval") private var portsInterval: TimeInterval = 5.0

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text("工具设置")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // 系统监控刷新设置
                    settingsSection(
                        icon: "chart.bar",
                        title: "系统监控",
                        description: "配置系统监控各子模块的数据刷新频率"
                    ) {
                        settingsRow(
                            icon: "gauge",
                            title: "系统指标",
                            description: "CPU、内存、磁盘等硬件指标数据采集频率",
                            interval: $metricsInterval
                        )

                        Divider().padding(.leading, 40)

                        settingsRow(
                            icon: "list.bullet",
                            title: "进程监控",
                            description: "进程列表数据刷新频率",
                            interval: $processesInterval
                        )

                        Divider().padding(.leading, 40)

                        settingsRow(
                            icon: "network",
                            title: "端口监控",
                            description: "网络端口连接数据刷新频率",
                            interval: $portsInterval
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - 设置区块

    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            content()
                .padding(.leading, 16)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - 设置行

    private func settingsRow(
        icon: String,
        title: String,
        description: String,
        interval: Binding<TimeInterval>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("刷新间隔", selection: interval) {
                Text("3秒").tag(3.0)
                Text("5秒").tag(5.0)
                Text("10秒").tag(10.0)
                Text("30秒").tag(30.0)
                Text("60秒").tag(60.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ToolSettingsView()
}
