# HomebrewGUI

一个简洁美观的 macOS Homebrew 可视化管理工具。

## 功能特性

- 📦 **已安装包管理** - 查看、搜索、卸载已安装的包
- 🔍 **包搜索** - 搜索 Homebrew 仓库中的所有可用包
- ⬆️ **版本更新** - 查看可更新的包，支持一键升级
- 🧹 **维护工具** - 清理旧版本、诊断 Homebrew 状态
- 🎨 **现代化界面** - 采用 SwiftUI 构建，美观简洁

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Homebrew 已安装

## 安装 Homebrew

如果你还没有安装 Homebrew，请在终端中运行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 构建项目

### 前置条件

确保已安装 XcodeGen：

```bash
brew install xcodegen
```

### 构建步骤

1. 生成 Xcode 项目文件：

```bash
cd HomebrewGUI
xcodegen generate
```

2. 使用 Xcode 打开生成的项目：

```bash
open HomebrewGUI.xcodeproj
```

3. 在 Xcode 中点击 **Run** 或按 `Cmd + R` 运行应用

## 项目结构

```
HomebrewGUI/
├── Sources/
│   ├── App/
│   │   └── HomebrewGUIApp.swift    # 应用入口
│   ├── Models/
│   │   └── BrewPackage.swift       # 数据模型
│   ├── Services/
│   │   └── HomebrewService.swift   # Homebrew 命令执行服务
│   └── Views/
│       ├── ContentView.swift       # 主视图
│       ├── InstalledPackagesView.swift  # 已安装包视图
│       ├── SearchView.swift       # 搜索视图
│       ├── OutdatedPackagesView.swift   # 可更新包视图
│       └── SettingsView.swift      # 设置视图
├── Resources/
│   └── Info.plist
└── project.yml                     # XcodeGen 配置
```

## 使用说明

### 查看已安装的包

启动应用后，默认显示已安装的包列表。你可以：
- 搜索特定的包
- 点击包查看详情
- 使用右键菜单卸载包

### 搜索新包

点击侧边栏的「搜索」，输入包名进行搜索。搜索结果可以一键安装。

### 更新包

点击侧边栏的「可用更新」，查看所有可更新的包。支持：
- 单个包升级
- 一键升级全部

### 系统维护

在「设置」中可以：
- 更新 Homebrew 本身
- 清理已卸载包的旧版本
- 运行诊断检查问题

## 技术栈

- **SwiftUI** - 用户界面框架
- **AppKit** - 原生 macOS 集成
- **Process** - 执行命令行工具
- **XcodeGen** - 项目生成工具

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
