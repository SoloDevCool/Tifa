import SwiftUI

struct OutdatedPackagesView: View {
    @StateObject private var viewModel = OutdatedPackagesViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                if !viewModel.packages.isEmpty {
                    Button(action: { Task { await viewModel.upgradeAll() } }) {
                        Label("升级全部", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // 内容
            if viewModel.isLoading {
                ProgressView("检查更新...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.packages.isEmpty {
                EmptyStateView(
                    title: "所有包都是最新版本",
                    systemImage: "checkmark.circle",
                    description: "当前没有可用的更新"
                )
            } else {
                List {
                    ForEach(viewModel.packages) { package in
                        OutdatedPackageRow(package: package, onUpgrade: {
                            Task { await viewModel.upgrade(package) }
                        })
                    }
                }
                .listStyle(.inset)
            }
        }
        .task {
            await viewModel.loadOutdatedPackages()
        }
    }
}

// MARK: - 过时包行

struct OutdatedPackageRow: View {
    let package: BrewPackage
    let onUpgrade: () -> Void
    
    @State private var isUpgrading = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("当前版本: \(package.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                isUpgrading = true
                onUpgrade()
            }) {
                if isUpgrading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("升级", systemImage: "arrow.up.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isUpgrading)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - ViewModel

@MainActor
class OutdatedPackagesViewModel: ObservableObject {
    @Published var packages: [BrewPackage] = []
    @Published var isLoading = false
    
    private let service = HomebrewService.shared
    
    func loadOutdatedPackages() async {
        isLoading = true
        packages = await service.fetchOutdatedPackages()
        isLoading = false
    }
    
    func refresh() async {
        await loadOutdatedPackages()
    }
    
    func upgrade(_ package: BrewPackage) async {
        let result = await service.upgradePackage(package.name)
        switch result {
        case .success:
            packages.removeAll { $0.id == package.id }
        case .failure:
            break
        }
    }
    
    func upgradeAll() async {
        _ = await service.upgradeAllPackages()
        await loadOutdatedPackages()
    }
}

#Preview {
    OutdatedPackagesView()
}
