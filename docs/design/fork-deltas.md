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
- 第 2 / 3 节各行登记的是**改后形态**（本批实施后成立）；实施前的现状读数见第 7.3 节的「现状行数」列，两者可互证。

## 2 整档自有资产

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/kernel/thincoder/**` | ACP 内核、协议、目录、配置与进程适配 | 内核适配 | `AgentKernel` / `SessionCatalog` / `HostTools` | 自有 |
| `lib/browser/btest/**` | 浏览器业务测试模式、策略、run、状态 UI 与工具门 | 功能 | `ChatSessionOverlay`、`HostTool` | 自有 |
| `lib/diagnostics/**` | 帧、stall、hang 与诊断包 | 功能 | 应用启动与设置诊断入口 | 自有 |
| `lib/platform/process_host.dart`、`process_host_io.dart`、`process_host_stub.dart` | 非窗口线程进程创建 | 修 bug | `ThincoderProcess` 与诊断测试 | 自有 |
| `lib/chat/session/**` | ChatSession overlay 与独立 helper | 内核适配 | `chat_session_overlay.dart` | 自有 |
| `lib/chat/chat_session_overlay.dart` | choice 数据、通用 overlay host 与完整生命周期 / 状态投影契约 | 内核适配 | `ChatSession` 构造及生命周期钩 | 自有 |
| `lib/host_tools/host_tools.dart` | 跨内核宿主工具注册与调用通道；`HostTool` / `HostToolCall` 两个 typedef 与上游符号 re-export | 功能 | `HostTool` / `HostToolCall` / `HostTools` / MCP | 自有 |
| `lib/host_tools/host_mcp_server.dart` | 环回 Streamable HTTP MCP 端点：按 `group` 分组暴露，`picturesOnly` 与组外工具一律不出（`_offered` `:281-285`、`tools/list` 记组 `:246`、`tools/call` 拒组外 `:259-266`） | 功能 | `HostTools` 注册表；ACP `mcpServers` 面 | 自有 |
| `lib/chat/editor_context.dart` | editor context 数据形与提示词渲染 | 内核适配 | overlay 发送与 `KernelTurn.contexts` | 自有 |
| `test/kernel/thincoder*_test.dart`、`test/diagnostics/**` | 自有内核与诊断断言 | 功能 | 对应独立模块 | 自有 |
| `test/ide/git/git_autofetch_test.dart` | 自有 SCM 断言，独立于上游测试 | 功能 | SCM 公共入口；#181 未裁定 | 自有 |
| `test/RTM.md`、`test/integration/**` | 本仓业务集成索引与用例 | 功能 | 用户入口与业务可观察结果 | 自有；50–100 行用例窗 |

## 3 共享上游文件的登记接缝

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/chat/chat_session.dart` | overlay 装配、host 投影、生命周期钩、缺失能力投影 | 内核适配 | `docs/design/thincoder-adapter.md` §29.2 | 净增 ≤180 行 |
| `lib/chat/chat_feed.dart` | `MarksTurns` 只读接口 | 内核适配 | `ChatSession.turns` 与 folds | 净增 ≤16 行 |
| `lib/chat/chat_models.dart` | `TurnMark`、`NoticeItem` 与 `editor_context.dart` re-export | 内核适配 | overlay / `KernelTurn.contexts` | 每类 ≤30 行 |
| `lib/chat/composer/composer_editing.dart` | `hasCommandSource` 命令源门 | 内核适配 | `ChatSession.hasCommandSource` | 净增 ≤12 行 |
| `lib/chat/composer/composer_view.dart` | btest 缓存键与状态行挂点 | 功能 | `ChatSession` 的 btest 七成员 | 净增 ≤24 行 |
| `lib/chat/chat_screen.dart` | `canStopTasks` 单行接线（`:603`，接线点 ⑬） | 修 bug | `ChatSession.canStopTasks` | 净增 ≤2 行 |
| `lib/browser/browser_tools.dart` | `HostTools` 注册包装、数字归一、description schema、btest gate、tab watch/blocked/acting | 功能 | `HostTool` / `HostTools` / `HostToolCall`；btest 经独立模块 | 净增 ≤150 行 |
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
| `lib/chat/composer/session_model_picker.dart` | thincoder 会话默认收起 + 底部管理入口指向 thincoder 模型页 | 内核适配 | `ComposerPicker.startCollapsed`；`SettingsSection.thincoderModels` | 净增 ≤20 行 |
| `lib/kernel/claude_code/claude_sdk_tools.dart` | `ClaudeSdkTool` 的 `group` / `picturesOnly` 两字段；上游注册表类 `ClaudeSdkTools` 整段不取（注册表在自有 `HostTools`） | 内核适配 | `HostTools` 注册表；ACP 的 MCP 面按 group 分服与 `picturesOnly` 门 | 净增 ≤6 行 + 1 个删除块（229 行 ⇒ 91 行） |
| `lib/browser/browser_actions.dart` | `browser_screenshot` 的 `picturesOnly: true`（`:105`）+ 7 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall`；MCP 面按 `picturesOnly` 过滤 | 结构不变（净 0） |
| `lib/browser/browser_debug_tools.dart` | 无自有块：7 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_history.dart` | 无自有块：1 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_inspect.dart` | 无自有块：3 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_intercept.dart` | 无自有块：1 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_sources.dart` | 无自有块：3 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/browser/browser_watch.dart` | 无自有块：1 个构造点用上游原名 | 内核适配 | `ClaudeSdkTool` / `ClaudeSdkCall` | 结构不变（净 0） |
| `lib/images/image_tools.dart` | `group: 'images'` + 注册接线（`HostTools.unregister` `:46` / `register` `:48`） | 功能 | `HostTools` 注册表；MCP 面按组暴露 | 净增 ≤1 行（第二根 import） |
| `lib/ide/git/git_repository.dart` | 空仓与未出生分支：图加载的无 await 早退路径上经 `scheduleMicrotask(_notify)` 通知（`:871-875`），避开 build 期 `setState` | 修 bug | `GitRepository` 图加载 getter 的监听者 | 净增 ≤5 行 |

## 4 本批冻结的共享文件

以下文件保持上游实现，本批不为恢复旧 fork 行为而修改：

- `lib/ide/git/ide_scm_view.dart`；SCM「获取」语义仍待 #181 裁定。
- `lib/ide/ide_editor.dart`、`lib/ide/ide_workbench.dart`、`lib/workbench.dart`。
- `lib/chat/composer/composer.dart`、`composer_editing.dart`。后者已有命令源门，仅由 R1 恢复其调用的 getter。
- `lib/chat/composer/composer_view.dart`、`lib/browser/btest/btest_status_switches.dart`。两者只由 session 契约恢复而编译，不改 UI。
- `lib/browser/browser_actions.dart`、`browser_debug_tools.dart`。两者按第 7 节复原为 `ClaudeSdkTool` 形态，只修父库。
- 上游 SCM 测试档与 `test/chat/side_panel/side_panel_test.dart`。

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

- 上游源：`git show origin/main:lib/kernel/claude_code/claude_sdk_tools.dart`（229 行，本轮逐字读过）。`ClaudeSdkCall`（类头 `:14`）、`ClaudeSdkTool`（类头 `:38`；八个字段，无 `group` / `picturesOnly`）、`claudeSdkImage` / `claudeSdkText`、注册表类 `ClaudeSdkTools`（类头 `:88`，到文件尾）。
- `claudeSdkImage` / `claudeSdkText` 两边逐字相同：签名与函数体一致（自有 `lib/host_tools/host_tools.dart:87-97`，上游同段以 `:85` 收尾）⇒ 用上游符号 re-export 后 `run` 的返回值不变，`lib/browser/btest/btest_mode.dart:264/336` 两处调用语义不动。
- 自有 `lib/host_tools/host_tools.dart`（264 行，本轮读过）：`HostToolCall`（`:16-35`）、`HostTool`（`:40-84`，多 `group` `:79`、`picturesOnly` `:83`）、`claudeSdkImage` / `claudeSdkText`（`:87-97`）、`HostTools`（`:100-263`，多 `byGroup` `:116`、`anyIn` `:123`、`lookup` `:128`、`named` `:151`）。
- 现状实测：`ClaudeSdkTool` 全仓 0 命中；`HostTool(` 12 档 34 处 —— 上游 9 档 30 处、`lib/browser/btest/btest_mode.dart:264/336` 2 处、`host_tools.dart:41` 声明 1 处、`lib/kernel/claude_code/claude_code_translator.dart:962` 对象模式 1 处。
- **行数口径**：本表行数 = 文本按 `\n` 切分的元素数（末行换行也计 1）；`wc -l` 口径比它少 1（例：`host_tools.dart` 记 264，`wc -l` 读 263）。
- `docs/design/host-tool-channel.md` 的 `HostTool` 表述本轮已逐条读过（26 行、32 处命中），结论见 7.8。`test/RTM.md`（65 行）读过：唯一同字命中是 1-1 行的 `ProcessHost`，与本机制无关。
- 公开来源：`manifest.index.publicRepos` 为空，无独立文档仓；上游源码经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

### 7.2 接口契约

| 面 | 契约 |
|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 上游 229 行 − `ClaudeSdkTools` 类整段（`:86`–`:229`，144 行）+ `ClaudeSdkTool` 的 `group`（默认 `''`）/ `picturesOnly`（默认 `false`）⇒ 91 行 |
| `lib/host_tools/host_tools.dart` | `import` + `export ... show ClaudeSdkTool, ClaudeSdkCall, claudeSdkImage, claudeSdkText`（两个 helper 与上游逐字同形，见 7.1）；`typedef HostTool = ClaudeSdkTool;`；`typedef HostToolCall = ClaudeSdkCall;`；`HostTools` 类体逐字保留（`:100-263`） |
| 9 个上游档 | 构造点 30 处与类型引用回上游名（`HostTool` → `ClaudeSdkTool`、`HostToolCall` → `ClaudeSdkCall`）；注册表调用只出现在 `browser_tools.dart`（`unregister` `:89` · `instruct` `:91` · `:98` · `register` `:100`）与 `image_tools.dart`（`unregister` `:46` · `register` `:48`），其余 7 档只构造工具、不碰注册表 |
| 数据流 | 不变：注册 → `HostTools.handle`（JSON-RPC）→ `ClaudeSdkTool.run(input, ClaudeSdkCall)` |

净增 6 行的算术：构造参数 2 行（`this.group = '',` / `this.picturesOnly = false,`）+ 字段 2 行 + 单行文档注释 2 行。

### 7.3 受影响文件与行数

| 文件 | 现状行数 | 期望变化 | `HostTools.` 引用 |
|---|---|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 无（新建） | 上游 229 行 − `ClaudeSdkTools` 类段（`:86`–`:229`，144 行）+ 6 行 ⇒ **91 行** | 0 |
| `lib/host_tools/host_tools.dart` | 264 | 移出 4 个声明连注释（`HostToolCall` `:16-35` · `HostTool` `:40-84` · `claudeSdkImage` `:87-91` · `claudeSdkText` `:94-97`；`:14`–`:98` 共 85 行）+ import / export / 两 typedef（4–6 行）⇒ **183–185 行**（净减 79–81） | 4 处 |
| `lib/browser/browser_actions.dart` | 627 | 构造点 7 处 + `HostToolCall` 引用回 `ClaudeSdkCall`；import 换上游路径 1:1 ⇒ 行数不变 | 0 |
| `lib/browser/browser_debug_tools.dart` | 1786 | 构造点 7 处；import 1:1 ⇒ 不变 | 0 |
| `lib/browser/browser_history.dart` | 788 | 构造点 1 处；import 1:1 ⇒ 不变 | 0 |
| `lib/browser/browser_inspect.dart` | 1169 | 构造点 3 处；import 1:1 ⇒ 不变 | 0 |
| `lib/browser/browser_intercept.dart` | 477 | 构造点 1 处；import 1:1 ⇒ 不变 | 0 |
| `lib/browser/browser_sources.dart` | 1566 | 构造点 3 处；import 1:1 ⇒ 不变 | 0 |
| `lib/browser/browser_tools.dart` | 773 | 构造点 6 处；+1 import（第二根 import 给 `HostTools`）⇒ 774 | 4 处 `:89/91/98/100` |
| `lib/browser/browser_watch.dart` | 616 | 构造点 1 处；import 1:1 ⇒ 不变 | 0 |
| `lib/images/image_tools.dart` | 601 | 构造点 1 处；+1 import（第二根 import 给 `HostTools`；保留 `group: 'images'`）⇒ 602 | 2 处 `:46/48` |

构造点合计 7+7+1+3+1+3+6+1+1 = 30。测试档零改动：`test/host_tools/host_tools_test.dart`（316）· `host_mcp_server_test.dart`（384）· `test/browser/browser_steps_test.dart`（326）· `test/kernel/thincoder_kernel_test.dart`（4919）里的 `HostTool(` / `HostToolCall` 经 typedef 继续成立（承载用例见 7.6）。

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
| 上游 import 行保留、另加自有 import | 而不是把上游 import 改成自有路径 | 改上游行与加一行同样冲突，但保留上游行让上游的 import 增删可整段套用 |

### 7.5 验收对照（每条机器可判）

| 条目 | 判据（机器可判） |
|---|---|
| 上游档只动 `claude_sdk_tools.dart` 且 +2 字段 | `git diff --numstat origin/main -- lib/kernel/claude_code/claude_sdk_tools.dart` 的「增」≤ 6，删除块只有 `ClaudeSdkTools` 一段（`:86`–`:229`）；改后文件 91 行 |
| 注册表留在自有档 | `lib/kernel/claude_code/claude_sdk_tools.dart` 内 `static final Map` 计数 = 0；`lib/host_tools/host_tools.dart` 内 `abstract final class HostTools` 在 |
| 9 档只改名字 | 9 档 `HostTool(` 计数 = 0、`ClaudeSdkTool(` 计数 = 30；`git diff origin/main -- <9 档>` 不含 `HostTool(` / `HostToolCall` / `ClaudeSdkCall`；两档的 `HostTools.` 调用数不变（`browser_tools` 4 · `image_tools` 2） |
| 自有档零改动（`lib/host_tools/host_tools.dart` 除外） | 本批允许改动的自有档只有 `lib/host_tools/host_tools.dart`（注册表所在：移出 4 个声明 + 加 typedef 与 re-export）；判据 = `git status --porcelain` 与 {`lib/browser/btest/**`, `lib/host_tools/host_mcp_server.dart`, `lib/kernel/thincoder/**`, `test/**`} 交集为空 |
| 编译与测试 | ① `flutter analyze --no-pub` 的 **error 数 = 0**（读命令尾行；与测试失败数不同量纲，分开判）；② `flutter test test/host_tools test/browser test/kernel/thincoder_kernel_test.dart test/platform` 全绿；③ 全量 `flutter test --no-pub` 收尾行 **失败数 ≤ 128 且通过数 ≥ 7107** —— 取自父侧 2026-10-26 全量实跑（333 s）的 `+7107 ~31 -128`（`+` 通过 / `~` 跳过 / `-` 失败） |

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

- 不改 `lib/kernel/claude_code/claude_code_translator.dart:962` 的对象模式（类型引用，别名保证编译）；把它也复原成 `ClaudeSdkTool(…)` 属下一次精修。
- 不动 9 档里的自有接缝行为（`group:` 参数、browser 的注册包装、btest gate）。
- 不删自有代码里的 `HostTool` / `HostToolCall` 名字；B 案不在本批。
- 不动测试档：别名让 `HostTool(` 与 `HostToolCall` 继续编译。

未实测的 Dart 语义前提（实施时第一次编译即验证）：`typedef HostTool = ClaudeSdkTool` 下构造调用、类型注解与 `is` 判定成立。证实后本条改为陈述句；若 `lib/kernel/claude_code/claude_code_translator.dart:962` 的对象模式不经别名解析，就把那一行改成 `ClaudeSdkTool(...)`（上游名，与本批方向一致，不算越界）。

### 7.8 UI / 交互

无界面变化：本批改类型名、导入与两字段的位置，工具描述与返回形状不动。

关联档已对齐：`docs/design/host-tool-channel.md` 的 `HostTool` 表述共 26 行、32 处命中，逐条读过；与改后形态相反的 3 行（§4.7 的注册面代码块、§2.2 偏离第 2 条、§8 的 D2）已按 A 案改后形态重写，其余 23 行（注册表名与别名类型引用）本批后仍成立。本节无 open 项。

### 7.9 集成测试设计（RTM delta）

读 `test/RTM.md`（65 行）：唯一同字命中是 1-1 行的 `ProcessHost`，与宿主工具无关。

- 被破坏的行：无 —— 本批不改业务可观察结果（类型名、导入面与两个带默认值的字段）。
- 冗余可删的行：无。
- 缺失需新增的行：无 —— 两个入口都不成立（没有新的业务场景，也没有生产问题）。

⇒ 收口报 `none`，并说明本批无 RTM 改动。
