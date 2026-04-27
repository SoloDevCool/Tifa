import SwiftUI

struct ToolSettingsView: View {
    @AppStorage("systemMetricsRefreshInterval") private var metricsInterval: TimeInterval = 5.0
    @AppStorage("systemProcessesRefreshInterval") private var processesInterval: TimeInterval = 5.0
    @AppStorage("systemPortsRefreshInterval") private var portsInterval: TimeInterval = 5.0
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text(L("settings.title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // 语言设置
                    settingsSection(
                        icon: "globe",
                        title: L("settings.language"),
                        description: L("settings.languageDesc")
                    ) {
                        HStack(spacing: 12) {
                            ForEach(AppLanguage.allCases) { language in
                                Button(action: {
                                    loc.currentLanguage = language
                                }) {
                                    HStack(spacing: 8) {
                                        Text(language.displayName)
                                        if loc.currentLanguage == language {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(loc.currentLanguage == language ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(loc.currentLanguage == language ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }

                    // 系统监控刷新设置
                    settingsSection(
                        icon: "chart.bar",
                        title: L("settings.systemMonitor"),
                        description: L("settings.systemMonitorDesc")
                    ) {
                        settingsRow(
                            icon: "gauge",
                            title: L("settings.systemMetrics"),
                            description: L("settings.systemMetricsDesc"),
                            interval: $metricsInterval
                        )

                        Divider().padding(.leading, 40)

                        settingsRow(
                            icon: "list.bullet",
                            title: L("settings.processMonitor"),
                            description: L("settings.processMonitorDesc"),
                            interval: $processesInterval
                        )

                        Divider().padding(.leading, 40)

                        settingsRow(
                            icon: "network",
                            title: L("settings.portMonitor"),
                            description: L("settings.portMonitorDesc"),
                            interval: $portsInterval
                        )
                    }
                }
                .padding(20)
            }
        }
        .id(loc.currentLanguage)
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

            Picker(L("settings.refreshInterval"), selection: interval) {
                Text(L("interval.3s")).tag(3.0)
                Text(L("interval.5s")).tag(5.0)
                Text(L("interval.10s")).tag(10.0)
                Text(L("interval.30s")).tag(30.0)
                Text(L("interval.60s")).tag(60.0)
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
