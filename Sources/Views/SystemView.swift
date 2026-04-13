import SwiftUI

struct SystemView: View {
    @StateObject private var viewModel = SystemViewModel()
    @Binding var selectedTab: SystemTab
    
    var body: some View {
        VStack(spacing: 0) {
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
                .frame(width: 200)
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
            .padding(.top, 8)
            
            // 内容区
            Group {
                switch selectedTab {
                case .metrics:
                    metricsContent
                case .processes:
                    ProcessMonitorView(viewModel: viewModel)
                case .ports:
                    PortMonitorView()
                }
            }
        }
        .task {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
    @ViewBuilder
    private var metricsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                
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
    @Published var processes: [AppProcessInfo] = []
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
        processes = await service.getProcessList()
    }
}

// MARK: - 进程监控视图

struct ProcessMonitorView: View {
    @ObservedObject var viewModel: SystemViewModel
    @State private var searchText = ""
    @State private var selectedCategory: AppProcessInfo.ProcessCategory? = nil
    @State private var sortOption: ProcessSortOption = .cpu
    @State private var sortAscending = false
    
    private var filteredProcesses: [AppProcessInfo] {
        var processes = viewModel.processes
        
        // 分类过滤
        if let category = selectedCategory {
            processes = processes.filter { $0.category == category }
        }
        
        // 搜索过滤
        if !searchText.isEmpty {
            processes = processes.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                String($0.pid).contains(searchText) ||
                $0.user.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 排序
        processes.sort { a, b in
            let result: Bool
            switch sortOption {
            case .cpu:
                result = a.cpuUsage > b.cpuUsage
            case .memory:
                result = a.memoryMB > b.memoryMB
            case .pid:
                result = a.pid < b.pid
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return sortAscending ? !result : result
        }
        
        return processes
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 工具栏
            HStack(spacing: 12) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索进程名称、PID 或用户", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                // 分类筛选
                Menu {
                    Button("全部") { selectedCategory = nil }
                    Divider()
                    ForEach(AppProcessInfo.ProcessCategory.allCases, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedCategory?.icon ?? "folder")
                        Text(selectedCategory?.rawValue ?? "全部")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // 排序选项
                Menu {
                    ForEach(ProcessSortOption.allCases, id: \.self) { option in
                        Button {
                            if sortOption == option {
                                sortAscending.toggle()
                            } else {
                                sortOption = option
                                sortAscending = false
                            }
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("排序: \(sortOption.rawValue)")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // 进程统计
                Text("\(filteredProcesses.count) / \(viewModel.processes.count) 进程")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // 表头
            HStack(spacing: 0) {
                Text("PID")
                    .frame(width: 70, alignment: .leading)
                Text("名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("用户")
                    .frame(width: 100, alignment: .leading)
                Text("CPU")
                    .frame(width: 80, alignment: .trailing)
                Text("内存")
                    .frame(width: 100, alignment: .trailing)
                Text("线程")
                    .frame(width: 60, alignment: .trailing)
                Text("类别")
                    .frame(width: 90, alignment: .center)
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            // 进程列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredProcesses.prefix(200)) { process in
                        ProcessRowView(process: process)
                        Divider()
                            .padding(.leading, 16)
                    }
                    
                if viewModel.processes.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("正在加载进程列表...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if filteredProcesses.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("未找到匹配进程")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
                }
            }
        }
    }
}

// MARK: - 进程行视图

struct ProcessRowView: View {
    let process: AppProcessInfo
    
    var body: some View {
        HStack(spacing: 0) {
            Text("\(process.pid)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            
            Text(process.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(process.user)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            
            Text(String(format: "%.1f%%", process.cpuUsage))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(cpuColor(process.cpuUsage))
                .frame(width: 80, alignment: .trailing)
            
            Text(String(format: "%.1f MB", process.memoryMB))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .trailing)
            
            Text("\(process.threads)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            
            HStack(spacing: 4) {
                Image(systemName: process.category.icon)
                    .font(.caption2)
                Text(process.category.rawValue)
                    .font(.caption2)
            }
            .foregroundColor(categoryColor(process.category))
            .frame(width: 90, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private func cpuColor(_ usage: Double) -> Color {
        if usage < 10 { return .primary }
        if usage < 50 { return .orange }
        return .red
    }
    
    private func categoryColor(_ category: AppProcessInfo.ProcessCategory) -> Color {
        switch category {
        case .user: return .blue
        case .system: return .purple
        case .background: return .green
        }
    }
}

#Preview {
    SystemView(selectedTab: .constant(.metrics))
}
