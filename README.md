# FluxRelay

FluxRelay 是一款使用 SwiftUI 和 AppKit 构建的 macOS 原生菜单栏下载工具。应用内置独立的 arm64 aria2 引擎，提供轻量的任务管理界面、完整的任务详情和系统级菜单栏体验。

当前打包版本为 `0.2.0`，支持 Apple Silicon（arm64）和 macOS 14 或更高版本。

简体中文 | [English](README.en.md)

## 功能

- 作为菜单栏应用运行，后台状态下不显示 Dock 图标。
- 打开主窗口时显示 Dock 图标，关闭窗口后回到菜单栏。
- 内置 aria2 `1.37.0-git.9e72735`，运行时不依赖额外下载引擎。
- 支持 HTTP、FTP、SFTP、磁力链接和 `.torrent` 文件。
- 添加 Torrent 时可选择需要下载的文件。
- 支持暂停、继续、移除、删除文件、清理完成记录和调整队列优先级。
- 支持筛选、搜索、排序、批量选择和批量操作。
- 持久化下载历史，重启后仍可按来源、完成时间、文件位置和校验结果搜索。
- 菜单栏和主窗口共享任务快照；活动任务每 2 秒刷新，空闲时延长至 10 秒，操作后立即刷新。
- 列表使用摘要查询，文件信息按需缓存，分块数据仅在打开详情时加载。
- 提供任务详情、传输统计、文件、来源、Peer、Tracker 和数据块矩阵视图。
- 提供下载、BitTorrent、连接、RPC、通知和登录启动设置。
- 保存设置后会列出已立即生效的项目；需要重启引擎的项目提供直接操作入口。
- 支持按服务器学习连接数，并根据文件大小推荐分段数。
- 支持完全关闭做种，并在任务完成后清理无用的 `.aria2` 控制文件。
- 使用 Retina 菜单栏图标显示整体进度，并提供完成和异常状态提醒。
- 提供简体中文和英文界面，可在设置中即时切换语言。

完成时间记录应用观察到的完成时刻；首次导入的已完成任务如果没有时间记录，不会补造日期。无法取得校验配置的历史任务显示“未知”。默认下载目录和默认暂停等设置用于新任务；待重启设置会一直提示，直到引擎成功应用。重启会先保存会话并等待自有引擎退出；连接外部引擎时不会误报重启成功。

应用会将配置、下载会话和日志保存在 macOS 的应用支持目录中。内置 aria2 通过本机 JSON-RPC 工作，退出时会保存会话并请求引擎正常关闭。

## 构建

首次构建或更新内置引擎时，先安装脚本所需的工具：

```sh
brew install autoconf automake libtool gettext pkgconf cppunit
Scripts/build-aria2-arm64.sh --install
```

脚本固定 aria2 源码版本和依赖版本，校验源码包，并构建仅包含 arm64 的引擎。引擎构建会运行上游测试；macOS 网络环境对 LPD 组播回送的单条环境性超时会被单独处理，其余测试必须通过。

构建 Swift 应用：

```sh
xcrun swift build -c release --arch arm64 --product FluxRelay
```

## 验证

```sh
swift test -c release
python3 Scripts/test-aria2-regressions.py
ARIA2_BINARY="$PWD/Resources/engine/aria2c" Scripts/smoke-test-aria2.sh
```

回归测试覆盖任务分页、智能并发探测收尾、异步任务取消和重复提交、代理配置兼容，以及 HTTPS 证书校验。还覆盖历史重载与删除竞争、摘要缓存、空闲查询抑制、设置待生效状态，以及真实引擎切换 RPC 端口和密钥后的会话恢复。引擎测试使用临时目录和独立本机端口，不连接正在运行的下载引擎，也不修改系统证书信任。自签名 HTTPS 测试需要 `python3` 和 `openssl`。数据块性能对比测试默认跳过，可按测试文件中的性能开关单独启用。

## 打包

```sh
Scripts/package-app.sh
```

打包脚本会检查引擎版本、架构和动态依赖，生成签名的应用包：

```text
.build/app/FluxRelay.app
```

## 项目结构

- `Models`：应用状态、任务模型和持久化配置。
- `Views`：SwiftUI/AppKit 界面、状态图标和用户提示。
- `Controllers`：应用生命周期、窗口、菜单栏和任务协调。
- `Services`：aria2 RPC、引擎进程、日志和系统服务。
- `Utilities`：格式化、本地化和无状态辅助逻辑。
- `Tests`：任务模型、渲染、配置、异步流程和引擎回归测试。

用户界面文案位于 `Resources/Localization`，打包时会同时加入简体中文和英文资源。
