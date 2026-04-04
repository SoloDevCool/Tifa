import SwiftUI

/// 兼容 macOS 13.0 的空状态视图
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String?
    
    init(title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            if let description = description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        title: "没有数据",
        systemImage: "tray",
        description: "这里暂时没有内容"
    )
}
