import SwiftUI

// MARK: - 端口信息模型

struct PortInfo: Identifiable, Hashable {
    let id: String
    let localAddress: String
    let localPort: Int
    let remoteAddress: String
    let remotePort: Int
    let protocolType: String
    let state: String
    let processName: String
    let pid: Int
}

// MARK: - 端口状态颜色

extension String {
    var portStateColor: Color {
        switch self.lowercased() {
        case "listen", "listening":
            return .green
        case "established":
            return .blue
        case "time_wait", "close_wait":
            return .orange
        case "syn_sent", "syn_recv":
            return .yellow
        case "fin_wait", "last_ack", "closing":
            return .red
        default:
            return .secondary
        }
    }
}

// MARK: - 端口监控视图

struct PortMonitorView: View {
    @StateObject private var viewModel = PortMonitorViewModel()
    @State private var searchText = ""
    @State private var selectedProtocol = "全部"
    @State private var selectedState = "全部"
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("端口监控")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 协议筛选
                Picker("协议", selection: $selectedProtocol) {
                    Text("全部").tag("全部")
                    Text("TCP").tag("TCP")
                    Text("UDP").tag("UDP")
                    Text("TCP6").tag("TCP6")
                    Text("UDP6").tag("UDP6")
                }
                .frame(width: 90)
                .onChange(of: selectedProtocol) { _ in
                    applyFilters()
                }
                
                // 状态筛选
                Picker("状态", selection: $selectedState) {
                    Text("全部").tag("全部")
                    Text("LISTEN").tag("LISTEN")
                    Text("ESTABLISHED").tag("ESTABLISHED")
                    Text("TIME_WAIT").tag("TIME_WAIT")
                    Text("CLOSE_WAIT").tag("CLOSE_WAIT")
                    Text("SYN_SENT").tag("SYN_SENT")
                }
                .frame(width: 130)
                .onChange(of: selectedState) { _ in
                    applyFilters()
                }
                
                // 刷新间隔
                Picker("刷新间隔", selection: $viewModel.refreshInterval) {
                    Text("3秒").tag(3.0)
                    Text("5秒").tag(5.0)
                    Text("10秒").tag(10.0)
                    Text("30秒").tag(30.0)
                }
                .frame(width: 80)
                .onChange(of: viewModel.refreshInterval) { _ in
                    viewModel.restartTimer()
                }
                
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("刷新")
                
                Text("\(viewModel.lastUpdate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索端口、进程名称或地址...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _ in
                        applyFilters()
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 统计摘要
            HStack(spacing: 24) {
                StatChip(label: "总计", value: "\(viewModel.ports.count)", color: .primary)
                StatChip(label: "LISTEN", value: "\(viewModel.ports.filter { $0.state == "LISTEN" }.count)", color: .green)
                StatChip(label: "ESTABLISHED", value: "\(viewModel.ports.filter { $0.state == "ESTABLISHED" }.count)", color: .blue)
                StatChip(label: "TIME_WAIT", value: "\(viewModel.ports.filter { $0.state == "TIME_WAIT" }.count)", color: .orange)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 端口表格
            if viewModel.isLoading && viewModel.ports.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在加载端口信息...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if viewModel.ports.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("未发现端口信息")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredPorts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("未找到匹配端口")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredPorts) {
                    TableColumn("协议", value: \.protocolType)
                        .width(60)
                    
                    TableColumn("本地地址") { port in
                        Text("\(port.localAddress):\(port.localPort)")
                            .monospacedDigit()
                    }
                    .width(min: 160, ideal: 200)
                    
                    TableColumn("远程地址") { port in
                        if port.remoteAddress.isEmpty {
                            Text("*")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(port.remoteAddress):\(port.remotePort)")
                                .monospacedDigit()
                        }
                    }
                    .width(min: 160, ideal: 200)
                    
                    TableColumn("状态") { port in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(port.state.portStateColor)
                                .frame(width: 6, height: 6)
                            Text(port.state)
                                .font(.caption)
                        }
                    }
                    .width(100)
                    
                    TableColumn("进程", value: \.processName)
                        .width(min: 80, ideal: 120)
                    
                    TableColumn("PID") { port in
                        Text("\(port.pid)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .width(60)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
    
    private var filteredPorts: [PortInfo] {
        viewModel.ports.filter { port in
            let matchProtocol = selectedProtocol == "全部" || port.protocolType == selectedProtocol
            let matchState = selectedState == "全部" || port.state.contains(selectedState)
            let matchSearch = searchText.isEmpty ||
                port.processName.localizedCaseInsensitiveContains(searchText) ||
                "\(port.localPort)".contains(searchText) ||
                port.localAddress.localizedCaseInsensitiveContains(searchText) ||
                port.remoteAddress.localizedCaseInsensitiveContains(searchText) ||
                port.state.localizedCaseInsensitiveContains(searchText)
            return matchProtocol && matchState && matchSearch
        }
    }
    
    private func applyFilters() {
        // 过滤由 computed property 处理，无需额外逻辑
    }
}

// MARK: - 统计标签

private struct StatChip: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - 端口监控 ViewModel

@MainActor
class PortMonitorViewModel: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var isLoading = false
    @Published var lastUpdate = ""
    @Published var refreshInterval: Double = 5.0
    
    private var timer: Timer?
    private let systemService = SystemService.shared
    
    func startMonitoring() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
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
        isLoading = true
        ports = await systemService.getPortList()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastUpdate = formatter.string(from: Date())
        isLoading = false
    }
}

#Preview {
    PortMonitorView()
}
