import SwiftUI

struct SystemView: View {
    @StateObject private var viewModel = SystemViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 顶部栏
                HStack {
                    Text("系统监控")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    
                    Picker("刷新间隔", selection: $viewModel.refreshInterval) {
                        Text("3秒").tag(3.0)
                        Text("5秒").tag(5.0)
                        Text("10秒").tag(10.0)
                        Text("30秒").tag(30.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .onChange(of: viewModel.refreshInterval) { _ in
                        viewModel.restartTimer()
                    }
                    
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                Divider()
                
                // 主要指标卡片（3 列）
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    MetricCard(
                        title: "CPU 使用率",
                        value: String(format: "%.1f%%", viewModel.metrics.cpuUsage),
                        subtitle: "\(viewModel.metrics.cpuCores) 核心",
                        icon: "cpu",
                        color: usageColor(viewModel.metrics.cpuUsage),
                        progress: viewModel.metrics.cpuUsage / 100
                    )
                    
                    MetricCard(
                        title: "内存",
                        value: formatBytes(viewModel.metrics.memoryUsed),
                        subtitle: "/ " + formatBytes(viewModel.metrics.memoryTotal),
                        icon: "memorychip",
                        color: memoryColor(viewModel.metrics.memoryUsed, total: viewModel.metrics.memoryTotal),
                        progress: Double(viewModel.metrics.memoryUsed) / Double(max(viewModel.metrics.memoryTotal, 1))
                    )
                    
                    MetricCard(
                        title: "磁盘",
                        value: formatBytes(viewModel.metrics.diskUsed),
                        subtitle: "/ " + formatBytes(viewModel.metrics.diskTotal),
                        icon: "internaldrive",
                        color: usageColor(Double(viewModel.metrics.diskUsed) / Double(max(viewModel.metrics.diskTotal, 1)) * 100),
                        progress: Double(viewModel.metrics.diskUsed) / Double(max(viewModel.metrics.diskTotal, 1))
                    )
                }
                .padding(.horizontal)
                
                // 次要指标卡片（2 列）
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // 温度与散热
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "thermometer.medium")
                                .foregroundColor(thermalColor(viewModel.metrics.thermalPressure))
                            Text("温度与散热")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let temp = viewModel.metrics.temperature {
                            HStack(alignment: .lastTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", temp))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("°C")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 散热状态
                        HStack(spacing: 6) {
                            Circle()
                                .fill(thermalColor(viewModel.metrics.thermalPressure))
                                .frame(width: 8, height: 8)
                            Text(thermalLabel(viewModel.metrics.thermalPressure))
                                .font(.caption)
                        }
                        .padding(.top, 2)
                    }
                    .padding(16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                    
                    // 交换空间
                    MetricCard(
                        title: "交换空间",
                        value: formatBytes(viewModel.metrics.swapUsed),
                        subtitle: "/ " + formatBytes(viewModel.metrics.swapTotal),
                        icon: "arrow.left.arrow.right.circle",
                        color: .secondary,
                        progress: viewModel.metrics.swapTotal > 0 ? Double(viewModel.metrics.swapUsed) / Double(viewModel.metrics.swapTotal) : 0
                    )
                }
                .padding(.horizontal)
                
                // 系统信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.accentColor)
                        Text("系统信息")
                            .font(.headline)
                    }
                    
                    SystemInfoRow(label: "主机名", value: viewModel.metrics.hostname)
                    SystemInfoRow(label: "系统版本", value: viewModel.metrics.osVersion)
                    SystemInfoRow(label: "架构", value: viewModel.metrics.arch)
                    SystemInfoRow(label: "CPU", value: viewModel.metrics.cpuModel)
                    SystemInfoRow(label: "运行时间", value: formatUptime(viewModel.metrics.uptime))
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
        .task {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
    // MARK: - 格式化工具
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func usageColor(_ percentage: Double) -> Color {
        if percentage < 50 { return .green }
        if percentage < 80 { return .orange }
        return .red
    }
    
    private func memoryColor(_ used: UInt64, total: UInt64) -> Color {
        guard total > 0 else { return .secondary }
        let pct = Double(used) / Double(total) * 100
        return usageColor(pct)
    }
    
    private func thermalColor(_ level: String) -> Color {
        switch level {
        case "nominal": return .green
        case "fair": return .yellow
        case "serious": return .orange
        case "critical": return .red
        default: return .secondary
        }
    }
    
    private func thermalLabel(_ level: String) -> String {
        switch level {
        case "nominal": return "正常"
        case "fair": return "轻微发热"
        case "serious": return "严重发热"
        case "critical": return "过热"
        default: return "未知"
        }
    }
    
    private func formatUptime(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时 \(minutes) 分钟" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        return "\(minutes) 分钟"
    }
}

// MARK: - 指标卡片

struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let icon: String
    let color: Color
    var progress: Double?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let progress = progress {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: .separatorColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.7))
                                .frame(width: geo.size.width * min(progress, 1.0), height: geo.size.height)
                        )
                }
                .frame(height: 6)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - 系统信息行

struct SystemInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

// MARK: - ViewModel

@MainActor
class SystemViewModel: ObservableObject {
    @Published var metrics = SystemMetrics()
    @AppStorage("systemRefreshInterval") var refreshInterval: TimeInterval = 5.0
    
    private let service = SystemService.shared
    private var timer: Timer?
    
    func startMonitoring() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func restartTimer() {
        stopMonitoring()
        startMonitoring()
    }
    
    func refresh() async {
        metrics = await service.collectMetrics()
    }
}

#Preview {
    SystemView()
}
