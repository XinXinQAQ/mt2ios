# MT2iOS

MT2（Android 版 MT 管理器仿写项目）的界面 + iOS 侧的文件系统权限，拼成一个双栏 iOS 文件管理器。

- 界面、颜色、行高、交互全部照 MT2 来：`#303030` 工具栏、43pt 行高、28pt 圆角图标框、`#65C0DF` 选中色、可拖动分隔条、底部操作栏。
- 文件权限走 `worse_query` 沙盒逃逸（`Sources/Exploit/worse_query.m`），拿到任意路径的 sandbox extension 后以 mobile 用户身份读写。

## 先明确一件事：MT2 的"漏洞"在 iOS 上不存在

MT2 里 `利用零宽获取 Android/data 文件夹` 用的是 Android 11+ 的 SAF 路径校验绕过 —— 在 `Android/data` 路径里塞零宽字符，让 `DocumentFile` 的路径比较失配从而放行。这套东西依赖 `MediaStore` / `DocumentsContract` 的实现细节，iOS 上没有任何对应物。

所以这里换成了 iOS 侧同功能的原语：`worse_query`。它做的事不一样，结果更彻底 —— 不是"某个目录能读了"，而是"任意路径都能申请一枚 sandbox extension"：

```
containermanagerd 查询(我们自己的 App Group, part=Library/Caches)
        ↓  查询前把 <group>/Library/Caches 换成指向目标的软链接
守护进程跟随软链接解析 part 路径
        ↓
下发的是"解析后真实路径"的 sandbox extension
        ↓  sandbox_extension_consume
本进程从此可以读写该路径（目录则整棵子树），身份仍是 mobile
```

没有内核利用、没有 root、没有代码签名绕过、没有 tweak 注入。系统卷（`/System`、`/usr`）依旧只读，因为 mobile 用户本来就写不了。

## 功能对照

| MT2 (Android) | MT2iOS | 位置 |
|---|---|---|
| 文件双列表 | 左右两个独立 `Pane`，各自路径/历史/选中 | `Sources/App/RootView.swift` |
| 双列表滑动滑块 | 中间 10pt 分隔条，拖拽改宽度（0.2–0.8） | `RootView.Splitter` |
| 下拉刷新 + 加载动画 | 滚动偏移 <-64 后回弹触发 reload | `PaneView.handleMetrics` |
| 列表阴影折叠 | 顶部渐变阴影随滚动偏移淡入 | `PaneView.topShadow` |
| 左右滑动选中 | 横向 drag >36pt 切换选中 + 触感反馈 | `PaneView.row(for:)` |
| 快速滚动滑块 | 右侧 3pt thumb，按内容比例计算 | `PaneView.scrollbar` |
| 底部操作栏 | 返回/前进/新建/跨栏传输/上级；选中后切成操作条 | `Sources/UI/ActionBar.swift` |
| 应用图标角标 | 容器目录上叠加真实 App 图标 | `AppIndex.icon(forDataPath:)` |
| — | 文本/十六进制编辑器、属性面板、书签、应用列表 | `Sources/UI/Sheets.swift` |

## 目录

```
mt2ios/
├── project.yml                  # XcodeGen 工程定义（改 App Group 在这里）
├── mt2ios.entitlements          # com.apple.security.application-groups
├── Resources/Info.plist
├── Sources/
│   ├── Exploit/
│   │   ├── worse_query.m        # 沙盒逃逸原语
│   │   ├── worse_query.h
│   │   └── MT2iOS-Bridging-Header.h
│   ├── Core/
│   │   ├── SandboxEscape.swift  # 扩展句柄的申请/缓存/诊断
│   │   ├── SandboxFS.swift      # 列目录、读写、复制移动、属性、chmod
│   │   ├── FSItem.swift         # lstat 出来的行数据 + 图标/配色/权限串
│   │   ├── AppIndex.swift       # 容器 UUID → Bundle ID → 显示名/图标
│   │   └── Pane.swift           # 单栏状态机（路径、历史、选中、排序）
│   ├── UI/
│   │   ├── PaneView.swift       # 单栏视图 + 滚动指标 + 手势
│   │   ├── FileRow.swift        # 43pt 行
│   │   ├── ActionBar.swift      # 底部栏 / 选中操作条
│   │   ├── RootsDrawer.swift    # 常用位置 + 书签
│   │   └── Sheets.swift         # 新建/重命名/属性/编辑器/应用列表/自检
│   └── App/
│       ├── MT2iOSApp.swift
│       ├── RootView.swift       # 双栏骨架 + 工具栏 + 所有文件操作
│       └── Theme.swift          # MT2 配色
└── scripts/build-ipa.sh
```

## 编译

需要 macOS + Xcode 15 以上 + `xcodegen`（`brew install xcodegen`）。

```bash
cd mt2ios
xcodegen generate
open mt2ios.xcodeproj      # 选你的 Team，真机运行
```

或者一条命令出 ipa：

```bash
APP_GROUP=group.com.yourteam.mt2ios.WQ \
TEAM_ID=ABCDE12345 \
BUNDLE_ID=com.yourteam.mt2ios \
./scripts/build-ipa.sh
```

装包用 SideStore / AltStore / Sideloadly / LiveContainer 这类"自己的 Apple ID 签名"的方式。企业证书会出问题，因为 App Groups 是按 Team 签的。

## 云编译（GitHub Actions）

`.github/workflows/build.yml` 已经在仓库里。push 到 `main`、发 PR、或者手动 `workflow_dispatch` 都会在 `macos-latest` 上跑一遍：

```
checkout → 切最新 Xcode → brew install xcodegen → xcodegen generate
        → xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO
        → Payload/ 打包成 ipa → upload-artifact
```

产物（artifact `MT2iOS-ipa`）：

| 文件 | 用途 |
|---|---|
| `MT2iOS-<sha>-unsigned.ipa` | 未签名包，交给重签工具 |
| `MT2iOS.entitlements` | 重签时要注入的 App Groups 权限 |
| `BUILD-INFO.txt` | commit、bundle id、app group、Xcode 版本 |

仓库可以在 **Settings → Secrets and variables → Actions → Variables** 里配两个变量，不用改代码：

- `BUNDLE_ID`（默认 `com.example.mt2ios`）
- `WQ_APP_GROUP`（默认 `group.com.example.mt2ios.WQ`）

也可以在手动触发时用输入框临时覆盖。

**未签名 ipa 不能直接装。** 必须在重签时把 `MT2iOS.entitlements` 一起注入，否则 `worse_query` 第一步就拿不到容器。几个工具的做法：

- Sideloadly：`Advanced Options` 里指定 entitlements 文件
- SideStore / AltStore：先在 Xcode 里用同一个 Team 跑一次空壳工程生成带 App Groups 的 profile，再把 ipa 交给它签
- 最省事的路子仍然是本地 `./scripts/build-ipa.sh`，有 Team 就能直接签

## 必须改的地方：App Group

`worse_query` 的第一步是 `containerURLForSecurityApplicationGroupIdentifier(group)`，拿不到容器就直接返回 `-1`。所以：

1. 打开 `project.yml`，把 `WQ_APP_GROUP` 改成你自己的 App Group（`group.<你的TeamID>.mt2ios.WQ` 这种形式）；
2. 在 Xcode 的 Signing & Capabilities 里加 App Groups，勾上同名的那一项；
3. 描述文件必须真的带 `com.apple.security.application-groups`。

免费个人团队通常勾不上 App Groups（能力受限于付费账号），这种情况下逃逸必然失败，App 会明确提示"签名里没有 App Groups"。App 内的 **自检** 面板会直接告诉你 `容器可用: 是/否`。

## 支持范围

`worse_query` 目前未修复的版本：iOS 26.0 – 26.7.2、27.0 – 27.2、27.3 beta 1。iOS 26.x 上 `container_query_operation_set_flags` 对 AppGroup 容器需要换一组 flag，代码里已按系统主版本自动切换。

苹果一旦修掉，这些版本之后全部失效，且无法降级 —— 所以在能用的版本上别随手升级。

## 已知限制

- 分隔条/滚动条是拖动改宽度和指示器，没做"拖到某个位置跳转"（MT2 的滑块点击定位）。
- 没有 zip 解压/压缩，没有 root 执行，没有 tweak 注入 —— 没有内核权限就做不了。
- 修改 `/var` 下的系统 plist 属于高风险操作（白苹果/循环重启），App 不做 undo，自己先备份。
- 这份代码没有在本机编译过（开发环境是 Windows，没有 Xcode）。逻辑和 API 调用按 iOS 17+ SDK 写，第一次 `xcodebuild` 可能需要处理少量签名/工程配置问题。

## 许可

`worse_query` 的技术与原始实现来自 forcequit / 0xjohnny（GPL-3.0），本仓库的 `Sources/Exploit/worse_query.m` 是按同一调用约定重写的实现，同样按 GPL-3.0 分发。
