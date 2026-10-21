# StickyTodo

macOS 菜单栏便签 Todolist —— 一个零依赖、单文件、原生 SwiftUI 的便签待办应用。

![macOS](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.1-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能清单

- **六色便签**：黄 / 粉 / 蓝 / 绿 / 紫 / 橙 六种便签卡片，自由切换
- **今日优先时间线**：按「今天 → 过期 → 将来 → 无期限」智能排序
- **历史**：已完成事项按日期归档查看
- **GitHub 风格热图**：近 180 天「新增 + 完成」贡献热图
- **双模式**：菜单栏 Popover 快速模式 + 独立主窗口模式
- **#时间提醒**：输入 `#15:30` / `#明天 9点` 等自然语言实时解析提醒，通知支持「稍后 5 分钟 / 稍后 1 小时」与超时未完成追加提醒
- **通知声音开关**：可关闭提醒声音
- **优先级**：`!高` / `!中` / `!低` 前缀快速标记优先级
- **重复任务**：`#每天` / `#每周` / `#每月` 重复规则
- **全局快捷添加**：任意应用下按 `Cmd+Shift+N` 呼出快速添加小窗
- **搜索**：面板内实时搜索便签与待办
- **便签折叠**：折叠收起便签内容，仅留标题
- **导出 / 导入备份**：JSON 一键备份与恢复
- **周报小结**：一键生成本周完成统计并复制文本
- **深色模式**：全面适配 macOS 深色 / 浅色外观
- **7 日自动归档**：已完成任务超过 7 天后自动从便签栏归档到历史区（历史区仍可随时查看）
- **标题 #日期 绑定**：标题输入 `#2026-10-20` / `#10-20` / `#10月20日` 自动绑定到对应日期视图，与 `#时间提醒` 可并存

## 技术说明

- **框架**：SwiftUI + AppKit（状态栏、全局快捷键、本地通知）
- **编译**：单文件 `.swift`，`swiftc` 命令行直接编译，**零第三方依赖**
- **持久化**：`UserDefaults`（key: `sticky-todo-notes-v1`，向后兼容旧数据）
- **通知**：`UserNotifications` 本地通知，增量同步、完成即移除
- **架构**：`NoteStore`（ObservableObject 数据层）+ `StatusItemController`（菜单栏）+ `ReminderManager`（提醒调度）+ `MainWindowController`（窗口模式）

## 构建方法

> 环境：macOS 15+，仅需安装 Xcode Command Line Tools（无需完整 Xcode）。

### 方式一：一键脚本（推荐）

```bash
chmod +x build.sh
./build.sh          # 生成 build/StickyTodo.app，并可选 zip / dmg
```

### 方式二：手动编译

源码为单文件 `StickyTodo.swift`，直接编译：

```bash
swiftc -O -parse-as-library \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -o StickyTodo StickyTodo.swift
```

**CLT 环境（无 Xcode）编译避坑说明**：

本机在仅有 Command Line Tools（无 Xcode GUI）的环境下，`swiftc` 可能因 CLT 自带的 SwiftBridging `module.modulemap` 与 SDK 冲突而报错（重定义 `SwiftBridging` 等符号）。此时需要 VFS overlay 屏蔽冲突的 modulemap：

1. 创建空文件 `empty.swiftmodule`（`touch empty.swiftmodule`）
2. 创建 `vfs-file.yaml`，内容：

```yaml
{
  "version": 0,
  "case-sensitive": "true",
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
      "type": "file",
      "external-contents": "/绝对路径/empty.swiftmodule",
      "use-external-name": "true"
    }
  ]
}
```

3. 编译时追加参数（注意两段式传参）：

```bash
swiftc -O -parse-as-library \
  -Xfrontend -vfsoverlay -Xfrontend /绝对路径/vfs-file.yaml \
  -framework SwiftUI -framework AppKit -framework UserNotifications \
  -o StickyTodo StickyTodo.swift
```

**替代方案**：安装完整 Xcode（`xcode-select -p` 指向 Xcode）后，直接使用方式二的普通命令即可，无需 VFS overlay。

### 组装 .app 包

```bash
mkdir -p StickyTodo.app/Contents/{MacOS,Resources}
cp StickyTodo StickyTodo.app/Contents/MacOS/
# Info.plist 见仓库根目录（LSUIElement=true 隐藏 Dock 图标）
cp Info.plist StickyTodo.app/Contents/
cp AppIcon.icns StickyTodo.app/Contents/Resources/
codesign --force --deep --sign - StickyTodo.app   # ad-hoc 签名
```

## 安装方法

1. 下载发布包 `StickyTodo-1.1.0-macOS.zip`（或 `.dmg`）并解压
2. 将 `StickyTodo.app` 拖入「应用程序」文件夹（`/Applications`）
3. 首次打开：因未进行 Apple 开发者签名，macOS Gatekeeper 会拦截。任选其一：
   - **右键** `StickyTodo.app` → **打开** → 再次点击「打开」
   - 或终端执行：`xattr -dr com.apple.quarantine /Applications/StickyTodo.app`

启动后菜单栏（屏幕右上角）会出现便签图标，点击即可开始使用。

## 截图

<!-- TODO: 在此添加应用截图 -->

## 开源协议

[MIT License](LICENSE) © 2026 StickyTodo contributors
