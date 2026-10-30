# Fork delta 登记表

## 1 规则与覆盖口径

本表登记允许继续维护的自有资产，以及共享上游文件中可辨认的接线。目标 = 上游共享文件可优先合并，自有语义只在独立模块与登记接缝中存活。

- **表外不许改上游档**。确需新增接线时，先登记文件、块、类型、接缝和行数预算，再改代码。
- 本表不是历史 diff 的逐行镜像。表外共享文件是只读上游面；合并前仍须做全量 diff，对账发现自有块时先补表再解决冲突，不得凭「表外」推断没有自有块。
- 自有目录 / 文件不得因冲突整档取上游；共享文件不得把上游实现回退成旧 fork 版本。
- 「行数预算」约束共享文件的 fork 净增行；自有文件用「自有」标记，仍受既有结构拆分规则约束。
- 类型只用：**修 bug · 功能 · 内核适配**。
- l10n 只合并 `app_en.arb` / `app_zh.arb` 的键级并集；生成文件由 `flutter gen-l10n` 重产，不手解、不选边。
- 上游测试与自有断言分档；不为保留 fork 断言改写上游测试。
- 每次上游合并后按符号核对本表，不以旧行号判断接线是否仍在。
- 第 2 / 3 节各行登记的是**改后形态**；实施前的读数见第 7.3 节 / §8.5 的「实施前行数」列，两者可互证。实施是否落地归批档记录，本表只写形态。

## 2 整档自有资产

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/kernel/thincoder/**` | ACP 内核、协议、目录、配置与进程适配 | 内核适配 | `AgentKernel` / `SessionCatalog` / `HostTools` | 自有 |
| `lib/browser/btest/**` | 浏览器业务测试模式、策略、run、状态 UI 与工具门 | 功能 | `ChatSessionOverlay`、`HostTool` | 自有 |
| `lib/diagnostics/**` | 帧、stall、hang 与诊断包 | 功能 | 应用启动与设置诊断入口 | 自有 |
| `lib/platform/process_host.dart`、`process_host_io.dart`、`process_host_stub.dart` | 非窗口线程进程创建 | 修 bug | `ThincoderProcess` 与诊断测试 | 自有 |
| `lib/chat/session/**` | ChatSession overlay 与独立 helper | 内核适配 | `chat_session_overlay.dart` | 自有 |
| `lib/chat/chat_session_overlay.dart` | choice 数据、通用 overlay host 与完整生命周期 / 状态投影契约 | 内核适配 | `ChatSession` 构造及生命周期钩 | 自有 |
| `lib/host_tools/host_tools.dart` | 跨内核宿主工具注册与调用通道；`HostTool` / `HostToolCall` 两个 typedef 与上游符号 re-export；按 cwd 的工具门（`gate` / `offersTool` / `asksUser` / `tellsFeature`，与上游 `ClaudeSdkGate` 三成员同名；`serversFor(cwd)` 与 `initialize` 的 instructions 过滤） | 功能 | `HostTool` / `HostToolCall` / `HostTools` / `ClaudeSdkGate` / MCP | 自有 |
| `lib/host_tools/host_mcp_server.dart` | 环回 Streamable HTTP MCP 端点：按 `group` 分组暴露，`picturesOnly` 与组外工具一律不出（`_offered` `:281-285`、`tools/list` 记组 `:246`、`tools/call` 拒组外 `:259-266`），并施加同一门的 cwd 判定：`tools/list` 逐工具过滤 `:244`、`tools/call` 按 cwd 判准入 `:259-262` | 功能 | `HostTools` 注册表；ACP `mcpServers` 面；`ClaudeSdkGate` | 自有 |
| `lib/chat/editor_context.dart` | editor context 数据形与提示词渲染 | 内核适配 | overlay 发送与 `KernelTurn.contexts` | 自有 |
| `test/kernel/thincoder*_test.dart`、`test/diagnostics/**` | 自有内核与诊断断言 | 功能 | 对应独立模块 | 自有 |
| `test/RTM.md`、`test/integration/**` | 本仓业务集成索引与用例 | 功能 | 用户入口与业务可观察结果 | 自有；50–100 条用例窗 |

## 3 共享上游文件的登记接缝

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/chat/chat_session.dart` | overlay 装配、host 投影、生命周期钩、缺失能力投影 | 内核适配 | `docs/design/thincoder-adapter.md` §29.2 | 净增 ≤180 行 |
| `lib/chat/chat_feed.dart` | `MarksTurns` 只读接口 | 内核适配 | `ChatSession.turns` 与 folds | 净增 ≤16 行 |
| `lib/chat/chat_models.dart` | `TurnMark`、`NoticeItem` 与 `editor_context.dart` re-export | 内核适配 | overlay / `KernelTurn.contexts` | 每类 ≤30 行 |
| `lib/chat/composer/composer_editing.dart` | `hasCommandSource` 命令源门；另承载三处上游方法体（`_caretAtEndOf` / `_buildBoxOf` / `_buildMarkdownEditorOf`，拆分落点见 `docs/design/structure-splits.md` §4.3 第 5 步） | 内核适配 | `ChatSession.hasCommandSource`；`composer.dart` 的三行委托 | 自有语义 ≤12 行；上游搬入体不构成 fork 净增 |
| `lib/chat/composer/composer.dart` | 三行委托：`_caretAtEnd`（`:378`）· `_buildBox`（`:545`）· `_buildMarkdownEditor`（`:598`），实现体在同目录 `composer_editing.dart`；拆分机制归 `docs/design/structure-splits.md` §4.3 | 内核适配 | 三个顶层 helper（`…Of(this, …)`） | 净增 3 行 |
| `lib/chat/composer/composer_view.dart` | btest 缓存键与状态行挂点 | 功能 | `ChatSession` 的 btest 七成员 | 净增 ≤24 行 |
| `lib/chat/chat_screen.dart` | `canStopTasks` 单行接线（`:603`，接线点 ⑬） | 修 bug | `ChatSession.canStopTasks` | 净增 ≤2 行 |
| `lib/chat/side_panel/file_preview.dart` | 动作区按宽度收口：`tight`（`:505`，<420）与 `compactActions`（`:509`，<720）两个门，外加 `Flexible(FittedBox(scaleDown))`（`:538-539`）；文案按门槛收（`:545` / `:552`），`compact:` 传参 `:564` | 修 bug | 动作区装配点；上游新分支 `sidePanelChanges` 折入同一动作区 | 净增 ≤40 行 |
| `lib/browser/browser_tools.dart` | `HostTools` 注册包装、数字归一、description schema、btest gate、tab watch/blocked/acting | 功能 | `ClaudeSdkTool` / `HostTools` / `ClaudeSdkCall`；btest 经独立模块 | 净增 ≤150 行 |
| `lib/workspace/workspace.dart` | thincoder 目录、默认内核偏好、确认改名 | 内核适配 | `SessionCatalog`、`ConfirmsRename`、`SessionRenamed` | 新增净增 ≤40 行 |
| `lib/main.dart` | thincoder 进程 reap/stop 与状态设置接线 | 内核适配 | `ThincoderLocator` / process registry | 新增净增 ≤20 行 |
| `lib/platform/data_dir.dart` | 进程注册表文件名清单含 `thincoder`（`:87-88` 注释）+ `thincoderDataDir` 只读访问器 + `items` 加 `runtime-data` | 修 bug | `ChildProcessRegistry`；`items` 的迁移 / 清理条目表 | 净增 ≤7 行（≤2 + ≤5） |
| `lib/kernel/kernel_registry.dart` | thincoder 为默认内核，Claude 保留 | 内核适配 | `_all = [thincoder, claudeCode]` | 净增 ≤12 行 |
| `lib/kernel/agent_kernel.dart` | fork 能力接口 | 内核适配 | `ConfirmsRename`、`AcceptsImageFiles`、`AcceptsEditorContext` 等 | 每个接口 ≤16 行 |
| `lib/kernel/kernel_types.dart` | `KernelTurn.contexts` 与回退数据形 | 内核适配 | overlay 发送与 `PlansReverts` | 每类 ≤40 行 |
| `lib/kernel/mock/mock_kernels.dart` | `MockKernels.thincoder` 描述符（`:34`，不进 `all`） | 内核适配 | `KernelDescriptor`；测试直用 | 净增 ≤16 行 |
| `lib/l10n/app_en.arb`、`app_zh.arb` | fork 文案键并集 | 功能 | ARB 源档；生成物零手改 | 只增所需键；同名不覆盖上游措辞 |
| `lib/settings/pages/thincoder_models_page.dart` | thincoder 模型配置页 | 功能 | 设置页导航与 CLI 配置文件 | 自有页面；共享导航接缝另计 |
| `lib/settings/pages/general_page.dart` | thincoder 设置组（`:442-457`，接线点 ⑦）+ 设置 → 通用的 `chat.editorContext` 一行开关（接线点 ⑪） | 功能 | 设置页 `SettingsGroup` / `ThincoderPathSetting`；`EditorContextSetting` | 净增 ≤93 行（≤81 + ≤12） |
| `lib/settings/app_settings.dart`、`settings/settings_dialog.dart` | thincoder 设置入口 | 功能 | `SettingsSection.thincoderModels` | 合计净增 ≤50 行 |
| `lib/chat/composer/composer_picker.dart` | `startCollapsed` 参数与 `_collapseNewGroups`（新到的分组也收起，选中那组除外） | 功能 | `ComposerPicker.startCollapsed`；收起集合仍留在 picker 内 | 净增 ≤25 行 |
| `lib/chat/composer/session_model_picker.dart` | thincoder 会话默认收起 + 底部管理入口指向 thincoder 模型页；回合在飞时的等待态后缀（`pendingModel` → label / tooltip 的 `modelsSwitchPending`；机制见 `thincoder-adapter.md` §24） | 内核适配 | `ComposerPicker.startCollapsed`；`SettingsSection.thincoderModels`；`ChatSession.pendingModel` | 净增 ≤20 行 + 等待态块 17 行（`:45-48` · `:129-138` · `:155-157`） |
| `lib/kernel/claude_code/claude_sdk_tools.dart` | `ClaudeSdkTool` 的 `group` / `picturesOnly` 两字段；删除块只含注册表类 `ClaudeSdkTools` 类本体（注册表在自有 `HostTools`）；类外的 `ClaudeSdkGate` 接口（`offersTool` / `asksUser` / `tellsFeature` 三个成员）与 `claudeSdkImage` / `claudeSdkText` 随上游保留 | 内核适配 | `HostTools` 注册表；ACP 的 MCP 面按 group 分服与 `picturesOnly` 门；`ClaudeSdkGate` 由自有 `HostTools.gate` 承接 | 净增 ≤20 行（两字段 + `ClaudeSdkGate` 接口）+ 1 个删除块（类本体 174 行；改后 106 行 = 上游 273 − 174 + 7：两字段 6 行 + `tellsFeature` 文档注释去掉指向已删类的引用 1 行） |
| `lib/bots/bots.dart` | 按 cwd 的工具门落在自有注册表：两处 `gate`（赋值 + 清空）与两处 `called` / `server`（合树 `:463` / `:464`）换 `HostTools.`，`claude_sdk_tools.dart` 的 import 换自有 `host_tools.dart`（`ClaudeSdkGate` 接口经自有档 re-export） | 功能 | `HostTools.gate` / `HostTools.called` / `HostTools.server`；`ClaudeSdkGate` 接口 | 净增 ≤6 行（5 行换符 + 至多 1 行自有 import） |
| `test/bots/bots_test.dart` | 删掉注册表类后的符号改名：档内 11 处 `ClaudeSdkTools.`（`handle` 5 · `register` 1 · `unregister` 1 · `server` 1 · `serversFor` 1 · `asksUser` 2）改 `HostTools.`；断言内容随上游，路径表达式按平台拼（26 处 `p.join`：上游写死 `/`，自有档在 Windows 上拼出 `\`） | 内核适配 | `HostTools` 的 handle / register / unregister / server / serversFor / asksUser | 净增 0 行（+38/−38：11 处换符 + 1 行 import 换行 + 26 处断言路径改写） |
| `lib/bots/bot_tools.dart` | bots 的工具注册落自有注册表：`HostTools.register`（`:44`）/ `HostTools.unregister`（`:50`）；import 换自有 `host_tools.dart`（上游该档自带 `image_tools.dart` 与 `claude_sdk_tools.dart` 两行 import） | 功能 | `HostTools` 注册表；`HostTools.register` / `unregister` | 净增 1 行（import） |
| `lib/browser/browser_actions.dart` | `browser_screenshot` 的 `picturesOnly: true`（`:105`）+ 7 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall`；MCP 面按 `picturesOnly` 过滤 | 结构不变（净 0） |
| `lib/browser/browser_debug_tools.dart` | 无自有块：7 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_history.dart` | 无自有块：1 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_inspect.dart` | 无自有块：3 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_intercept.dart` | 无自有块：1 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_sources.dart` | 无自有块：3 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_watch.dart` | 无自有块：1 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/images/image_tools.dart` | `group: 'images'` + 注册接线（`HostTools.unregister` `:47` / `register` `:49`）+ 选图前的问人判定走 `HostTools.asksUser(call.cwd)`（同一行换符，净 0 行） | 功能 | `HostTools` 注册表；MCP 面按组暴露；`HostTools.asksUser` | 净增 ≤1 行（第二根 import） |
| `lib/ide/git/git_repository.dart` | 空仓与未出生分支：图加载的无 await 早退路径上经 `scheduleMicrotask(_notify)` 通知（`:871-875`），避开 build 期 `setState` | 修 bug | `GitRepository` 图加载 getter 的监听者 | 净增 ≤5 行 |
| `lib/workbench.dart` | 命令面板的会话命令源（`_paletteActions` 里窗口命令 ∪ 焦点会话的 `ChatKeys.commandsOf`，Rename Agent 一项在 `:1316`）；侧栏仓库扫描的失败面（机制见 `ide-git.md` §4.7） | 修 bug | `ChatKeys.targetsOf` / `ChatKeys.commandsOf`；`_sidePanelFolderRepositories` 的扫描 async 块 | 面板 ≤10 行 · 扫描 ≤59 行 |
| `lib/ide/ide_workbench.dart` | chord 第二键的窗口门（`_holdsKeys` `:3344-3357`：本窗口持有主焦点且本路由当前才吃键；`_onChordKey` 守卫 `:3375-3380` 与 5 秒检查器 `:3397` 共用） | 修 bug | 上游按键服务的 `_onChordKey` / `_onLateKey` 钩 | 净增 ≤22 行（实测 21） |
| `lib/ide/ide_editor.dart` | 控制器为空时的空渲染（三处 `SizedBox.expand`：`_surface` `:2638-2641` · diff 原侧 `:2757-2758` · build 的 native 分支 `:2890`） | 修 bug | `_nativeController` / `IdeOriginalDiff.controller` | 净增 ≤7 行 |
| `lib/chat/chat_history_view.dart` | 窗口可见性门：自有 `window_visible.dart` 的 import 与档内 8 处 `WindowVisible` 用法（窗口不可见时按可见性跳过重建） | 修 bug | `WindowVisible.changed` 订阅；集成面见 `test/RTM.md` 2-1 行 | 净增 ≤1 行（import） |
| `lib/kernel/claude_code/claude_code_kernel.dart` | 宿主工具通道：自有 `host_tools.dart` 的 import 与档内 10 处类型使用（`HostTool` 5 · `HostTools` 3 · `HostToolCall` 2） | 内核适配 | `HostTools` 注册表；`HostTool` / `HostToolCall` 别名 | 净增 ≤1 行（import） |
| `lib/update/version.dart`、`pubspec.yaml` | 版本行跟随上游（`1.7.3+23`）：两档必须同值，一处改了另一处不跟就是发货缺陷 | 修 bug | `test/update/version_test.dart` 校验两档同值 | 每档净增 0 |

**恢复的上游 import 与自有 re-export 档重复**：`lib/browser/browser_tools.dart:13` 与 `lib/images/image_tools.dart:13` 各带一条 `unnecessary_import` info（自有 `host_tools.dart` 的 re-export 覆盖同样四个符号）。这两行是上游行，删掉即重建常驻 fork 差异，**禁随 lint 清扫删除**。

**存量债（合并后过 800 行的共享档）**：`lib/kernel/claude_code/claude_code_kernel.dart` 3547 → ≈3600 · `lib/bots/bots.dart` 515 → ≈1248 · `lib/bots/bot_tools.dart` 470 → ≈835 · `test/bots/bots_test.dart` 413 → ≈1376。四档都是上游共享档：拆分会让两半都成常驻 fork 差异（第 7.3 节同一理由），本批不拆。接手批次未排期，涨幅在下一次合并时按本行核对。

## 4 保持上游实现的共享文件

以下文件保持上游实现（两档带自有块，例外在行内注明）：

- `lib/ide/git/ide_scm_view.dart`；SCM「获取」语义按 #181 的裁定走上游。
- `lib/chat/composer/composer.dart`：带第 3 节登记的三行委托（拆分机制见 `docs/design/structure-splits.md` §4.3），块外 UI 保持上游。
- `lib/chat/composer/composer_view.dart`：带第 3 节登记的 btest 接缝（缓存键与状态行挂点，净增 ≤24 行），改动只许落在该块内，块外 UI 保持上游。
- `lib/browser/btest/btest_status_switches.dart`：在 `lib/browser/btest/**` 自有资产内，不是上游共享档，不在本节冻结面内。
- `lib/browser/browser_actions.dart`、`browser_debug_tools.dart`：按第 7 节复原为 `ClaudeSdkTool` 形态，只修父库。
- 上游 SCM 测试档与 `test/chat/side_panel/side_panel_test.dart`。

`lib/ide/ide_editor.dart`、`lib/ide/ide_workbench.dart`、`lib/workbench.dart` 不在此列：三者各带第 8 节登记的自有行为块，改动只许落在登记块内。

## 5 合并核对顺序

1. 先核第 2 节自有文件仍存在，未被共享档选边覆盖。
2. 对全量 diff 做自有块对账；表外发现自有块时先补第 3 节，再选冲突解法。
3. 核第 3 节每个接缝的符号与行为；行号只作定位参考。
4. 运行 `flutter analyze --no-pub`，把错误按登记模块归因；不得以整档回退消除冲突。
5. 重跑各模块定向测试；l10n 由源档重产；SCM 只跑对应独立断言。
6. 新出现的共享文件改动若没有行，停止实施并先登记。

## 6 本批断点覆盖对照

390-error 是批档 §1 的父侧基线，本轮未重跑。下表按该基线点名的断点面核对登记归属；实施后以 §29.5 的实跑结果证明闭合，不把静态对照当作 analyze 通过。

| 断点面 | 登记位置 | 重接轮与处置 |
|---|---|---|
| `lib/chat/session/**` 七档与 `chat_session.dart` 宿主接缝 | 第 2 节 session glob / overlay 契约；第 3 节 `chat_session.dart` | R1 改为独立 library；两档重复 helper 删除，其余只留自有语义 |
| `composer_view.dart`、`composer_editing.dart`、`btest_status_switches.dart` 与其它 session 消费方 | 第 2 节 btest glob；第 3 节 composer / session 接缝 | R1 恢复既有公共契约，消费方零改动；第 4 节继续冻结 UI |
| `browser_tools.dart` | 第 3 节 browser_tools 行 | R2 只修父库 import、注册与调用包装 |
| `browser_actions.dart`、`browser_debug_tools.dart` | 第 4 节冻结行；经 browser_tools 父库装配 | R2 零改动；不得为消错回退或另写一套工具实现 |
| `lib/browser/btest/**`（含新增 gate） | 第 2 节 btest glob | 状态由 R1 overlay 持有；R2 只新增 `btest_tool_gate.dart`，其余档不改 |
| 基线的测试侧断点 | 第 2 节自有测试登记；第 4 节上游测试冻结 | R1 / R2 用设计 §29.5 点名测试验证；不改上游 SCM 与 side-panel 测试 |

表外若出现新的产品文件改动，无论是否属于 390-error 列表，都先停止并回设计登记。

## 7 宿主工具类型的上游复原

### 7.1 决策与理由

**决策**：上游 `lib/kernel/claude_code/claude_sdk_tools.dart` 回仓，只给 `ClaudeSdkTool` 加 `group` / `picturesOnly` 两字段（净增 ≤6 行）。注册表 `HostTools` 留在自有 `lib/host_tools/host_tools.dart`，该档另加 `typedef HostTool = ClaudeSdkTool;`、`typedef HostToolCall = ClaudeSdkCall;`，并 re-export 上游符号。9 个上游档把改名回退成上游原名，行为不动。

**为什么**：改名让 9 个上游档的每个工具构造点都成为一行常驻 fork 差异（实测 `git diff --stat origin/main`：9 档 121 增 / 57 删），每次上游合并都在这些行上冲突。回退后同一 diff 只剩自有接缝与 6 行注册表名（见 7.3）。类型身份不变：`typedef` 让自有代码继续用 `HostTool` 名字，零改动。

**最近先例**：`lib/chat/chat_session.dart:32` 的 `export 'chat_session_overlay.dart' show KernelChoice, ModelSettingChoice;` —— 已跑通的带 `show` 过滤的 re-export，调用方只 import `chat_session.dart`，源码不动。同形实现坐标还有 `lib/chat/chat_models.dart:5` 的 `export 'editor_context.dart';`。

本批 `lib/host_tools/host_tools.dart` 用同一形：自有档 export 上游符号，调用方只换 import。对齐，不偏离。

**调查证据**：

- 上游源：`git show origin/main:lib/kernel/claude_code/claude_sdk_tools.dart`（230 行，按 `\n` 切分口径；本轮逐字读过）。`ClaudeSdkCall`（类头 `:14`）、`ClaudeSdkTool`（类头 `:38`；八个字段，无 `group` / `picturesOnly`）、`claudeSdkImage` / `claudeSdkText`、注册表类 `ClaudeSdkTools`（类头 `:88`，到文件尾）。
- `claudeSdkImage` / `claudeSdkText` 只在上游档有一份实现（`lib/kernel/claude_code/claude_sdk_tools.dart:81` / `:88`），自有档 re-export ⇒ 全仓一份函数体，`lib/browser/btest/btest_mode.dart:264/336` 两处调用走同一实现，`run` 的返回值不变。
- 自有 `lib/host_tools/host_tools.dart`（220 行）：`import`（`:12`）+ re-export（`:14-20`）+ 两 typedef（`:22` / `:23`）+ `HostTools`（`:26-220`，自有静态方法 `byGroup` / `anyIn` / `lookup` / `instruct` / `called` / `named` / `serversFor` 与门的四格）。
- 现状实测：上游 9 档内 `HostTool` / `HostToolCall` 均 0 命中、`ClaudeSdkTool(` 30 处；九档外 `HostTool(` 3 处（`btest_mode.dart:264` / `:336`、`claude_code_translator.dart:962` 对象模式）+ 测试 9 处。
- **行数口径**：本表行数 = 文本按 `\n` 切分的元素数（末行换行也计 1）；`wc -l` 比它少 1。例：`host_tools.dart` 记 220，`wc -l` 读 219。第 7.2 的算式同此口径：上游 230 − 删除块 144 + 6 = 92。
- `docs/design/host-tool-channel.md` 的 `HostTool` 表述本轮已逐条读过（26 行、32 处命中），结论见 7.8。`test/RTM.md`（69 行）读过：唯一同字命中是 1-1 行的 `ProcessHost`，与本机制无关。
- 公开来源：`manifest.index.publicRepos` 为空，无独立文档仓；上游源码经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

### 7.2 接口契约

| 面 | 契约 |
|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 上游 265 行 − `ClaudeSdkTools` 类整段（合上游后 `:97`–`:265`，169 行 = 类前空行 + 类文档注释 + 类体；合上游前是 230 行版本的 `:86`–`:229`，144 行）+ `ClaudeSdkTool` 的 `group`（默认 `''`）/`picturesOnly`（默认 `false`）⇒ 102 行 |
| `lib/host_tools/host_tools.dart` | `import`（`:12`）+ `export ... show ClaudeSdkTool, ClaudeSdkCall, claudeSdkImage, claudeSdkText`（`:14-15`）；`typedef HostTool = ClaudeSdkTool;`（`:17`）；`typedef HostToolCall = ClaudeSdkCall;`（`:18`）；`HostTools` 类体逐字保留（`:21-185`） |
| 9 个上游档 | 改名按标识符分三步、次序固定：`HostToolCall` → `ClaudeSdkCall`，`HostTool` → `ClaudeSdkTool`，`HostTools` 不动。禁止按子串替换：子串做法会把 `HostToolCall` 改成 `ClaudeSdkToolCall`、把 `HostTools` 改成 `ClaudeSdkTools`。改写面 = 构造点 30 处 + 类型引用 7 处（坐标见 7.3）。import 只在两档动：`browser_tools.dart` 与 `image_tools.dart` 恢复上游 import 并保留自有 `host_tools.dart` import；其余七档是 `part of 'browser_tools.dart'`，part 档不能写 import，只改类型名。注册表调用只在 `browser_tools.dart`（`unregister` `:90` · `instruct` `:92` · `:99` · `register` `:101`）与 `image_tools.dart`（`unregister` `:47` · `register` `:49`），其余 7 档 0 处 |
| 数据流 | 不变：注册 → `HostTools.handle`（JSON-RPC）→ `ClaudeSdkTool.run(input, ClaudeSdkCall)` |

净增 6 行的算术：构造参数 2 行（`this.group = '',` / `this.picturesOnly = false,`）+ 字段 2 行 + 单行文档注释 2 行。

### 7.3 受影响文件与行数

| 文件 | 实施前行数 | 变化 | `HostTools.` 引用 |
|---|---|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 92（合上游前读数） | 上游本批 265 行 − `ClaudeSdkTools` 类段（`:97`–`:265`，169 行）+ 6 行 ⇒ **102 行**；类外 `ClaudeSdkGate` 接口（`:87`–`:96`）随上游保留 | 0 |
| `lib/host_tools/host_tools.dart` | 264 | 移出 4 个声明连注释（`HostToolCall` · `HostTool` · `claudeSdkImage` · `claudeSdkText`，85 行）+ import / export / 两 typedef（4–6 行）⇒ **220 行**（实测） | 0 |
| `lib/browser/browser_actions.dart` | 627 | `part of`（`:1`）⇒ import 零改动；构造点 7 处改 `ClaudeSdkTool(`、类型引用 0 处；`picturesOnly: true`（`:105`）保留 ⇒ 行数不变 | 0 |
| `lib/browser/browser_debug_tools.dart` | 1786 | `part of`（`:1`）⇒ import 零改动；构造点 7 处、类型引用 0 处 ⇒ 不变 | 0 |
| `lib/browser/browser_history.dart` | 788 | `part of`（`:1`）⇒ import 零改动；构造点 1 处、类型引用 0 处 ⇒ 不变 | 0 |
| `lib/browser/browser_inspect.dart` | 1169 | `part of`（`:1`）⇒ import 零改动；构造点 3 处、类型引用 0 处 ⇒ 不变 | 0 |
| `lib/browser/browser_intercept.dart` | 477 | `part of`（`:1`）⇒ import 零改动；构造点 1 处、类型引用 0 处 ⇒ 不变 | 0 |
| `lib/browser/browser_sources.dart` | 1566 | `part of`（`:1`）⇒ import 零改动；构造点 3 处、类型引用 0 处 ⇒ 不变 | 0 |
| `lib/browser/browser_tools.dart` | 773 | 独立库。恢复上游 import `import '../kernel/claude_code/claude_sdk_tools.dart';`（与上游同档 `:12` 逐字相同）+ 保留自有 `../host_tools/host_tools.dart`（现状 `:12`）⇒ +1 行。构造点 6 处 + 类型引用 3 处（`:73` `List<ClaudeSdkTool>` · `:137` `ClaudeSdkTool tool,` · `:139` `ClaudeSdkCall call,`）；`group: 'browser'`（`:117`）与 `picturesOnly: tool.picturesOnly`（`:118`）保留 ⇒ 774 | 4 处 `:90/92/99/101` |
| `lib/browser/browser_watch.dart` | 616 | `part of`（`:1`）⇒ import 零改动；构造点 1 处、类型引用 0 处 ⇒ 不变 | 0 |
| `lib/images/image_tools.dart` | 601 | 独立库。同形恢复上游 import（与上游同档 `:12` 逐字相同）+ 保留自有 import（现状 `:11`）⇒ +1 行。构造点 1 处 + 类型引用 4 处（`:59` 返回类型 `ClaudeSdkTool` · `:170` / `:263` / `:269` `ClaudeSdkCall`）；`group: 'images'`（`:67`）保留 ⇒ 602 | 2 处 `:47/49` |

构造点合计 7+7+1+3+1+3+6+1+1 = 30；类型引用合计 3+4 = 7 处（只在 `browser_tools` 与 `image_tools` 两档），九档合计改写 37 个标识符位。九档 `HostTools` 引用 6 处（`browser_tools` 4 · `image_tools` 2）逐字保留。

测试档（类型复原批口径）：`test/host_tools/host_tools_test.dart`（389）· `host_mcp_server_test.dart`（384）· `test/browser/browser_steps_test.dart`（326）· `test/kernel/thincoder_kernel_test.dart`（4919）里的 `HostTool(` / `HostToolCall` 经 typedef 继续成立（承载用例见 7.6）。

本批另有一格要补：接口带 `asksUser` 后 `test/host_tools/host_tools_test.dart` 的 `_Gate` 必须实现它，否则 `implements` 不成立、编译红。见第 3 节 `host_tools.dart` 行。

**体量立场（本批不改结构）**：表内 8 档已过 500 行，其中 3 档过 800（`browser_debug_tools` 1786 · `browser_sources` 1566 · `browser_inspect` 1169）。

过 500 的另 5 档：`browser_actions` 627 · `browser_history` 788 · `browser_tools` 773 · `browser_watch` 616 · `image_tools` 601。

这 8 档都是上游共享档：本批只把类型名与 import 换回上游形态，行数不变 ⇒ 属存量债，不构成结构级触碰。治理按第 3 节每档的行数预算与上游合并面进行，不拆档：把上游档拆成两档，两个档都成常驻 fork 差异，每次上游合并要在两处对账，与「上游共享文件可优先合并」相抵。

`test/kernel/thincoder_kernel_test.dart`（4919）同属存量债：本批零改动，拆分按后续拆分批处理。

### 7.4 关键决策记录

| 选项 | 内容 | 结论与理由 |
|---|---|---|
| A（采用） | 注册表留自有档，上游档只加两字段 | 9 档残留降到「自有接缝 + 6 行注册表名」；自有代码零改动（`lib/host_tools/host_tools.dart` 除外） |
| B（否） | 上游档整档回仓，注册表改名 `ClaudeSdkTools`，自有档只留 `typedef HostTools = ClaudeSdkTools;` | 9 档残留可降到 0，但把注册表塞回上游档，违反 7.1 的「注册表留自有档」；且自有 4 个静态方法与两字段一起在上游档长成约 +26 行的净增块，仍要登记；另「静态成员经 typedef 访问」是 Dart 语义前提，本仓未实测，不作设计依据 |
| C（否） | 保留改名现状 | 9 档每个构造点常驻差异，上游改工具即冲突，正是本批要消除的成本 |
| 上游 import 行保留、另加自有 import（采用） | 而不是只留自有路径：现状 `browser_tools.dart:12` 与 `image_tools.dart:11` 的自有 import 顶掉了上游本行的 `claude_sdk_tools.dart` import | 恢复上游行（与上游同档 `:12` 逐字相同）+ 保留自有行 ⇒ 该行零差异、只有一行新增；只留自有路径则上游每次改这行都要手工对账 |

### 7.5 验收对照（每条机器可判）

| 条目 | 判据（机器可判） |
|---|---|
| 上游档只动 `claude_sdk_tools.dart` 且 +2 字段 | `git diff --numstat origin/main -- lib/kernel/claude_code/claude_sdk_tools.dart` 的「增」≤ 6，删除块只有 `ClaudeSdkTools` 一段（合上游后为 `:97`–`:265`）；改后文件 102 行（`\n` 切分口径，`wc -l` 读 101） |
| 注册表留在自有档 | `lib/kernel/claude_code/claude_sdk_tools.dart` 内 `static final Map` 计数 = 0；`lib/host_tools/host_tools.dart` 内 `abstract final class HostTools` 在 |
| 9 档只改名字（标识符级） | 九档内 `HostTool` 与 `HostToolCall` 两个标识符命中均为 0 —— 含构造点与类型引用；只数 `HostTool(` 会漏掉 7 处类型引用。同档 `ClaudeSdkTool(` = 30、`HostTools` = 6（`browser_tools` 4 · `image_tools` 2）逐字不变；`git diff origin/main -- <9 档>` 不含 `HostTool` / `HostToolCall`，也不含 `ClaudeSdkToolCall` / `ClaudeSdkTools`（子串误改的读数） |
| 9 档 import 面 | 七档 `:1` 仍为 `part of 'browser_tools.dart';`；`browser_tools.dart` 与 `image_tools.dart` 各恰 +1 行（上游 `claude_sdk_tools.dart` import），其余 import 行与现状逐字相同 |
| 三处真值逐行读回（不许只跑合成用例） | 三行原样在盘：`browser_actions.dart:105` = `picturesOnly: true,` · `browser_tools.dart:117` = `group: 'browser',` 且 `:118` = `picturesOnly: tool.picturesOnly,` · `image_tools.dart:67` = `group: 'images',`。理由：`test/host_tools/host_mcp_server_test.dart:11-24` 的 `_tool()` 自造带两字段的工具，不经过这三处真实注册路径，宽面误删后测试仍绿 |
| 自有档与测试档继续用别名（不清零） | 九档之外 `HostToolCall` 命中 32 处（8 个自有 `lib/` 档 13 处 + 10 个测试档 19 处）、`HostTool(` 12 处（自有 `btest_mode.dart:264/336` 2 处 · `claude_code_translator.dart:962` 对象模式 1 处 · 测试档 9 处）逐字不变 |
| 自有档零改动（`lib/host_tools/host_tools.dart` 除外） | 本批允许改动的自有档只有 `lib/host_tools/host_tools.dart`（注册表所在：移出 4 个声明 + 加 typedef 与 re-export）；判据 = `git status --porcelain` 与 {`lib/browser/btest/**`, `lib/host_tools/host_mcp_server.dart`, `lib/kernel/thincoder/**`, `test/**`} 交集为空 |
| 编译与测试 | ① `flutter analyze --no-pub` 的 **error 数 = 0**（读命令尾行；与测试失败数不同量纲，分开判）；② `flutter test test/host_tools test/browser test/kernel/thincoder_kernel_test.dart test/platform` 全绿。全量跑是发布门，读数在批次收口行报告，不作本表验收判据 |

### 7.6 用例表

| 场景 | 输入 | 期望 | 承载用例 |
|---|---|---|---|
| 正常 · 注册后调用 | `HostTools.register(ClaudeSdkTool(name: 't', run: …))` 后 `handle({'method': 'tools/call', 'params': {'name': 't'}})` | 返回该工具的文本块，`isError` 不置 | `test/host_tools/host_tools_test.dart:69`「lists and calls its tools, failures as errors」 |
| 正常 · 别名构造 | `HostTool(name: 'i', group: 'images', …)` | 编译通过；`HostTools.byGroup('images')` 含该工具 | 编译面 = 两个 `test/host_tools/` 档全部构造点（`host_tools_test.dart:8` 的 `_tool()` 每例都经它）；行为面 = `host_tools_test.dart:295`「groups: a server exposing one group alone gives only its tools」（`:304` 断言 `byGroup('images')` 含它） |
| 边界 · 无分组 | `group` 缺省 | 落 `''` 组；任何具名 group 服都不给该工具 | `host_tools_test.dart:295` 同一用例：`:298` 的 `loose` 不带 group，`:305` `byGroup('none')` 为空、`:309` `anyIn({'none'})` 为假 |
| 边界 · 纯图片工具 | `picturesOnly: true` | ACP 的 MCP 面不给它（`lib/host_tools/host_mcp_server.dart:262` 的过滤与 `:283` 的 `lookup` 分派） | `test/host_tools/host_mcp_server_test.dart:140`「T3: only the exposed group is listed, and not the pictures-only tool」 |
| 错误 · 未注册工具 | `handle({'method': 'tools/call', 'params': {'name': 'nope'}})` | `isError: true` + 文本 `No tool nope.`（现状 `lib/host_tools/host_tools.dart:198-205`） | `test/host_tools/host_mcp_server_test.dart:196`「T6: a tool it does not have is answered as failed」；`host_tools_test.dart:69` 同判断 |

五例全部有现有用例承载（测试档本批零改动），不新增用例。

### 7.7 边界（本批不做）

- 不改 `lib/kernel/claude_code/claude_code_translator.dart:962` 的对象模式：`typedef` 是类型别名，构造调用、类型注解、`is` 判定与对象模式四种用法都按别名解析，该行不动照常编译。把它也复原成 `ClaudeSdkTool(…)` 属下一次精修。
- 不动 9 档里的自有接缝行为（`group:` 参数、browser 的注册包装、btest gate）。
- 不删自有代码里的 `HostTool` / `HostToolCall` 名字；B 案不在本批。
- 不动测试档：别名让 `HostTool(` 与 `HostToolCall` 继续编译。

### 7.8 UI / 交互

无界面变化：本批改类型名、导入与两字段的位置，工具描述与返回形状不动。

关联档已对齐：`docs/design/host-tool-channel.md` 的 `HostTool` 表述共 26 行、32 处命中，逐条读过；与改后形态相反的 3 行（§4.7 的注册面代码块、§2.2 偏离第 2 条、§8 的 D2）已按 A 案改后形态重写，其余 23 行（注册表名与别名类型引用）本批后仍成立。本节无 open 项。

### 7.9 集成测试设计（RTM delta）

读 `test/RTM.md`（69 行）：唯一同字命中是 1-1 行的 `ProcessHost`，与宿主工具无关。

- 被破坏的行：无 —— 本批不改业务可观察结果（类型名、导入面与两个带默认值的字段）。
- 冗余可删的行：无。
- 缺失需新增的行：无 —— 两个入口都不成立（没有新的业务场景，也没有生产问题）。

⇒ 收口报 `none`，并说明本节无 RTM 改动。

## 8 六组易被合并覆盖的行为（现态）

六组行为各由共享上游档里的一小块自有实现承载。共同形状：一小块决定一整段可见行为，块外是上游实现；块没登记时，下一次合并不声不响地把它取走。下表是现态，机制归属一处设计档。

| # | 行为（现态） | 机制归属 | 代码坐标 |
|---|---|---|---|
| 1 | 回合在飞时点模型：pill 主 label 后追加 ` · 回合结束后切换到 <目标>`，tooltip 同句；目标名取选项里同 id 的 label，选项已不在则退回 id | `thincoder-adapter.md` §24（F21 · pill 后缀段） | `lib/chat/composer/session_model_picker.dart:129-138` · `:155-157` · `_nameOf` `:45-48` |
| 2 | 命令面板搜得到并执行会话命令，Rename Agent 在内：面板动作源 = 窗口命令 ∪ 焦点会话的命令 | 第 3 节 `lib/workbench.dart` 行 · §8.1 | `lib/workbench.dart:1291-1299` · `:1316` |
| 3 | 侧栏仓库扫描失败：记一行 `appEvent('sidePanel', …)`、30 秒后自动重试、同一位置提示一次 `scmScanFailed`、一次成功即清标记；`dispose` 取消重试定时器 | `ide-git.md` §4.7 | `lib/workbench.dart:3741-3786` · `:3812-3823` · `:778` |
| 4 | chord 第二键只在本窗口持有键时生效：不持有 ⇒ 退出 chord 态并忽略该键，不把另一窗口的键当成自己的 | 第 3 节 `lib/ide/ide_workbench.dart` 行 · §8.1 | `lib/ide/ide_workbench.dart:3344-3357` · `:3375-3380` · `:3397` |
| 5 | 文档关闭 / diff 重建时控制器为空不崩：活动文档面、diff 原侧、build 的 native 分支三处渲染 `SizedBox.expand()` | 第 3 节 `lib/ide/ide_editor.dart` 行 · §8.1 | `lib/ide/ide_editor.dart:2638-2641` · `:2757-2758` · `:2890` |
| 6 | 回退文件后变更审查列表立即刷新：`ChangesReverted` ⇒ 取消防抖计时器 + `review.observe()` 立即看一次；事件本身仍按 `outcome.files` 非空才发 | `session-governance.md` D-SG12（事件面）· 第 3 节 `chat_session.dart` 行（宿主钩） | `lib/chat/chat_session.dart:269-273` |

### 8.1 决策与理由

**决策**：六组行为作为现态维护。其中落在共享上游档的五组各是一小块自有实现，按第 3 节登记；改动只许落在登记块内，合并时不得整段取上游。

**为什么登记而不是留着「表外」**：块外是上游实现，块内是一整段可见行为。表外的块在下一轮合并里没有对账对象，被整段取走时没有任何信号——这六组就是这样消失的。

**为什么不是整段回退上游实现**：④ 的载体是上游按键服务的主链（`_onWorkbenchKey` → `KeybindingService` 解析），自有部分只是一行窗口门。整段取旧 fork 版本会重造上游已改的键路由，并把该档变回常驻冲突面，与第 1 节的目标相反。② ⑤ 同理：改的是调用点与一处渲染分支，回退整档会把上游在该档的其它改动一并回退。

**最近先例**：第 7 节（宿主工具类型复原）——同一形：改动压成最小登记块，其余交给上游符号。本节五块的块大小见第 3 节对应行的行数预算。

**调查证据**：`manifest.index.publicRepos` 为空，无独立文档仓；上游实现经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

### 8.2 接口契约

| 组 | 面 | 契约 |
|---|---|---|
| 1 | `SessionModelPicker` ← `ChatSession.pendingModel` | 等待态非空 ⇒ 主 label 追加 ` · <modelsSwitchPending(目标名)>`，tooltip 追加同句（原 tooltip 保留）；目标名 = `_nameOf(pending, model.options)`，找不到退回 id |
| 2 | `Workbench._paletteActions` | 动作源 = 窗口命令 `_chatCommands()` ∪ 焦点会话命令 `ChatKeys.commandsOf(ChatKeys.targetsOf(会话上下文))`；焦点会话 = 当前 agent 窗口的会话，否则工作区当前会话，都没有 ⇒ 只有窗口命令 |
| 3 | `Workbench._sidePanelFolderRepositories` | 失败 ⇒ 记一条 `appEvent('sidePanel', …)`、面板本轮不列仓库、30 秒后自动重试、同一位置只提示一次 `scmScanFailed`、一次成功即清标记；机制与失败分类归属 `ide-git.md` §4.7（本轮逐条核过：五条与 §4.7 逐句对应，此处不重述状态机） |
| 4 | `IdeWorkbenchState._holdsKeys` | 第二键只在 `_holdsKeys()` 为真时进食，否则 `_leaveChordMode()` + `ignored`；5 秒检查器同一判定，另加生命周期 `resumed` 与 5 秒上限（同形源：`26c969aa` 的 `lib/ide/ide_workbench.dart:2976-2983`）。判定内容归第 3 节该行，此处只留接口面 |
| 5 | `_IdeEditorState` | 原生控制器为 null ⇒ `SizedBox.expand()`；三处 = 活动文档面（`_surface`）· diff 原侧（`_diffEditor.original`）· build 的 native 分支 |
| 6 | `ChatSession._reviewEvent` | `ChangesReverted` ⇒ 取消防抖计时器 + `review.observe()`（全量）；`review.session` 照旧按事件赋值。事件面不变：仍由内核按 `outcome.files` 非空才发（`session-governance.md` D-SG12） |

**既有件三问（§8.2 组 1 的两处接缝）**：

- `ChatSession.pendingModel` —— existing: `lib/chat/chat_session.dart:644`（`String? get pendingModel => pendingModelOf(this);`；投影 `lib/chat/session/mode_state.dart:49-51` 经 `DefersModelSwitch`，内核 getter `lib/kernel/agent_kernel.dart:143`）· 名 "pendingModel" · 消费方 `lib/chat/composer/session_model_picker.dart:129`。
- l10n 键 `modelsSwitchPending` —— existing: `lib/l10n/app_en.arb:8910` / `lib/l10n/app_zh.arb:3352`，生成物 `lib/l10n/app_localizations.dart:20158` 已有。本批未新增键：两笔提交 `54f94769` / `e5661df4` 都未触及 `lib/l10n/**`，故第 3 节的 l10n 行无需改键并集，也不需 `flutter gen-l10n` 重产。

### 8.3 边界（不做）

- 不改上游按键实现（`_onWorkbenchKey` / `KeybindingService` 的解析链）：只加窗口门。
- 不动 SCM 语义：SCM「获取」按 #181 的裁定走上游。autofetch 已清理完，本仓不再有该代码，不恢复。
- 不删 `IdeScmView` 旧 widget（另批）。
- 六组不各配集成用例：见 §8.4。

### 8.4 集成测试设计（RTM delta）

读 `test/RTM.md`（69 行 = `split('\n')` 口径含末行换行；6 / 50–100 条）。六组都改既有界面的可观察结果，但没有一条新的业务故事从用户入口长出来：六组是合并面审查发现的回归，无生产报告，也无新业务场景。

| 行 | 断言面（本轮逐行读过） |
|---|---|
| 1-1 | 五次切换各起一个进程（假件 `start` 计数）；每次切换后 300 ms 内历史行就位、输入可用；`[stall]` 0 行 |
| 2-1 | 失焦期重建 0 次、可见文本不变；恢复恰 1 次重建、可见文本 == 全文、底部仍在底部、中段偏移不变 |
| 3-1 | 终态可见文本 == 全文；500 / 20 回合两组每增量重建行数逐项相等且有上界 |
| 4-1 | btest card 恰一次；readonly 写调用被拒且原因可读；切回后 off 文本恰一次；composer 与工具门读同一状态 |

- 被破坏的行：无 —— 上述断言面都不落在六组的面（模型 pill / 命令面板 / 侧栏扫描 / chord / 编辑器空控制器 / 审查刷新）上。
- 冗余可删的行：无。
- 缺失需新增的行：无 —— 两条来路都不成立。

⇒ 收口报 `none`，本节不改 RTM。

### 8.5 受影响文件与体量立场

行数 = 本轮实测（`split('\n')` 口径，含末行换行）；块的形态与坐标见第 3 节对应行，不在此重复。

| 文件 | 实施前行数 | 本批块 | 预算（第 3 节） |
|---|---|---|---|
| `lib/chat/composer/session_model_picker.dart` | 225 | 回合在飞时的等待态后缀，17 行 | ≤20 行 |
| `lib/workbench.dart` | 4910 | 面板命令源 · 扫描失败面 | 面板 ≤10 · 扫描 ≤59 |
| `lib/ide/ide_workbench.dart` | 5822 | chord 第二键的窗口门，21 行 | ≤22 行 |
| `lib/ide/ide_editor.dart` | 3013 | 控制器为空的空渲染，7 行 | ≤7 行 |
| `lib/chat/chat_session.dart` | 1376 | 回退后的审查刷新钩，5 行 | ≤180 行 |

**体量立场（不拆档）**：五档都是上游共享档。本批改动合计 +112 / −18（净增 94 行；`54f94769` +76 / −9 与 `e5661df4` +36 / −9，`git diff --numstat` 实测，不计批档自身 32 行），形态都是第 3 节登记块内的小块。

`workbench` 4910 · `ide_workbench` 5822 · `ide_editor` 3013 · `chat_session` 1376 四档过 800 行，属存量债，按 §7.3 同一理由不拆档：把上游共享档拆成两档，两半都成常驻 fork 差异，每次上游合并要在两处对账，与第 1 节的目标相反。

### 8.6 验收对照

读数 = 2026-10-27 实跑。①⑥ 有行为用例；②③④⑤ 停在静态面：④ 需多窗口 harness（本仓无此设施）、⑤ 需整套编辑器宿主，构造代价高于收益，判据取 analyze 的 error 计数 + 符号静态读数。

| 组 | 判据（机器可判） | 读数 |
|---|---|---|
| 1 | `flutter test test/chat/model_picker_test.dart test/kernel_ui_test.dart`；静态：`session_model_picker.dart` 内 `modelsSwitchPending` = 2（label 与 tooltip 各一） | 51 通过 |
| 2 | `flutter analyze --no-pub` 的 error 计数；静态：`workbench.dart` 内 `commandsOf` ≥1（本轮 2） | 0 error |
| 3 | 同上；静态：`_sidePanelRetryAt` ≥2（本轮 4）· `_sidePanelRetryTimer` ≥2（本轮 4）· `_scanWarned` ≥2（本轮 3）· `scmScanFailed` ≥1（本轮 1）· `appEvent(` ≥1（本轮 1）；时序（30 秒重试、同一位置只提示一次）未实测 | 0 error |
| 4 | 同上；静态：`_holdsKeys` ≥2（本轮 4 = 定义 1 + 判定 3）。跨窗行为未实测（无多窗口 harness） | 0 error |
| 5 | 同上；静态：`SizedBox.expand` = 3（三处） | 0 error |
| 6 | `flutter test test/chat/revert_flow_test.dart test/chat/session_overlay_test.dart`；静态：`ChangesReverted` ≥1（本轮 1） | 19 通过 |

本节不另列用例表：①⑥ 的承载就是上表点名的用例文件；②③④⑤ 的承载是 analyze + 静态读数。六组的正常 / 边界 / 错误场景面由 §8.2 的接口契约界定，不另立断言。
