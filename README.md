# FluxRelay

由独立内置 aria2 引擎驱动的 macOS 原生菜单栏下载工具。</br>
由于原版Motrix会一直保留在Dock导航栏，不能隐藏在状态栏里，且npm下载环境异常的慢挂了梯子都慢，逼死强迫症了（怒），于是一怒之下用Swift重构了一个MotrixNative，但是其实只把内部的aria2引擎拿过来了...本质还是个套皮App

项目最初叫 Motrix Native，现在更名为 **FluxRelay**。起点来自 Motrix，下载引擎仍是 aria2，界面与应用逻辑则独立用 Swift 实现。

### 仅供个人使用！！！

当前版本仅支持 Apple Silicon（arm64）和 macOS 14 或更高版本。

简体中文 | [English](README.en.md)

## 已实现功能

- 作为菜单栏应用运行，后台状态下不显示 Dock 图标。
- 打开主窗口时显示 Dock 图标，关闭窗口后重新隐藏到菜单栏。
- 所有运行数据保存在 `~/Library/Application Support/Motrix Native`。
- 首次启动时可一次性继承 Motrix 的兼容设置和 `download.session`，完成后不再读取原版数据。
- 内置从上游源码编译的 aria2 `1.37.0-git.9e72735` 与独立配置，运行时不依赖原版 Motrix 或 Homebrew。
- 可连接已经运行的兼容 aria2 RPC 服务，也能自动启动和守护内置引擎。
- 菜单栏以清晰的 Retina 环形图标显示任务综合进度，并提供完成与异常状态提醒。
- 提供原生 SwiftUI 任务窗口、筛选、搜索、排序和批量选择。
- 支持 HTTP、FTP、磁力链接和 `.torrent` 文件，可在开始前选择 Torrent 内的具体文件。
- 支持暂停、继续、移除、删除文件、清理完成记录和调整队列优先级。
- 提供任务详情、传输统计、文件、来源、Peer、Tracker 和数据块矩阵视图。
- 提供下载、BitTorrent、RPC、监听端口、通知和登录启动等设置。
- 支持完全关闭做种，并在任务完成后清理无用的 `.aria2` 控制文件。
- 提供按服务器学习的智能并发连接调节，默认从 48 个连接开始探测。
- aria2 日志使用干净的文件输出，并在达到 5 MB 后滚动保留最近 3 份。
- 退出时保存 aria2 会话并请求引擎正常关闭。
- 已提供简体中文和英文界面资源。
- 可在通用设置中选择跟随系统、简体中文或 English，并即时切换界面语言。

## 构建

首次构建或更新引擎时，先安装脚本所列构建工具，再生成固定版本的 arm64 aria2：

```sh
brew install autoconf automake libtool gettext pkgconf cppunit
cd FluxRelay
Scripts/build-aria2-arm64.sh --install
```

脚本固定到 aria2 commit `9e7273583f83e881e3ec067b523ba88724088d2f`，恢复 Motrix 所需的单服务器 64 连接兼容上限，校验全部源码包，并静态编入 zlib、Expat、SQLite、c-ares 和带安全补丁的 libssh2/OpenSSL。aria2 自身的 HTTPS 使用系统 AppleTLS，最终产物只动态链接 macOS 系统库。构建会运行上游 979 项测试；部分 macOS 网络环境不会把 LPD 组播包回送给发送端，因此仅对这一条精确的组播超时作环境性豁免，其余 978 项必须通过。

然后构建 Swift 应用：

```sh
xcrun swift build -c release --arch arm64 --product FluxRelay
```

## 验证

```sh
swift test -c release
python3 Scripts/test-aria2-regressions.py
ARIA2_BINARY="$PWD/Resources/engine/aria2c" Scripts/smoke-test-aria2.sh
```

回归测试覆盖任务分页、智能并发探测收尾、异步任务取消和重复提交、旧代理配置兼容，以及 HTTPS 证书校验。引擎测试使用临时目录和独立本机端口，不连接正在运行的下载引擎，也不修改系统证书信任。自签名 HTTPS 测试需要 `python3` 和 `openssl`。数据块性能对比测试默认跳过，可通过 `MOTRIX_PERFORMANCE_CHECK=1` 单独启用。

## 打包

```sh
Scripts/package-app.sh
```

使用 Release 配置打包的 App 会生成在：

```text
FluxRelay/.build/app/FluxRelay.app
```

## 源码结构

GitHub 仓库、应用和可执行文件均已更名为 `FluxRelay`。Swift 内部模块暂时保留历史名称 `MotrixNative`，已有本地工作目录也无需改名。上面的路径示例按新克隆的仓库目录编写。

可执行目标位于 `Sources/MotrixNative`，采用面向 MVC 的职责划分：

- `Models`：应用状态和持久化配置。
- `Views`：SwiftUI/AppKit 视图、状态图标和用户确认窗口。
- `Views/MainWindow`：按主界面、设置、任务详情、任务列表和新建任务拆分的页面视图。
- `Controllers`：应用生命周期、窗口、状态栏和任务协调逻辑。
- `Services`：aria2 RPC、进程、日志，以及 macOS 系统服务集成。
- `Utilities`：无状态格式化、Tracker 解析和 `L10n` 本地化入口。
- `main.swift`：程序入口和自检命令。

界面文案统一存放在 `Resources/Localization`，Swift 源码仅使用语义化 key，通过 `L10n` 读取。打包脚本会把简体中文与英文资源一并放入 App Bundle。

## 独立性

打包后的应用包含自身所需的 arm64 aria2 引擎、默认配置、版本清单、图标和语言资源。打包脚本会拒绝非 arm64 产物、版本不匹配或第三方动态库依赖。首次迁移完成后，删除原版 Motrix 不会影响 FluxRelay 的引擎、配置或任务会话。

## 从 Motrix Native 升级

FluxRelay 沿用应用标识 `dev.codex.motrix-native`、数据目录 `~/Library/Application Support/Motrix Native` 和日志文件名 `motrix-native-aria2.log`，无需重新导入设置或下载会话。这些历史名称用于保持兼容，并不代表仍然依赖原版 Motrix。

更新时先退出旧版，再使用 `FluxRelay.app`，不要同时运行两个版本。若移动或更换 App 路径后登录启动失效，在设置中重新关闭并开启一次“登录时启动”。
