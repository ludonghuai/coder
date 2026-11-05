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
- 第 2 / 3 节各行登记的是**改后形态**；实施前的读数见第 7.3 节的「实施前」列与 §8.5 的「行数」列，两者可互证。实施是否落地归批档记录，本表只写形态。

## 2 整档自有资产

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/kernel/thincoder/**` | ACP 内核、协议、目录、配置与进程适配 | 内核适配 | `AgentKernel` / `SessionCatalog` / `HostTools` | 自有 |
| `lib/browser/btest/**` | 浏览器业务测试模式、策略、run、状态 UI 与工具门 | 功能 | `ChatSessionOverlay`、`HostTool` | 自有 |
| `lib/diagnostics/**`（除 `frame_watch.dart`：该档是共享上游档，接缝登记在第 3 节，不按本节整档自有判） | 帧、stall、hang 与诊断包 | 功能 | 应用启动与设置诊断入口 | 自有 |
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
| `lib/chat/chat_session.dart` | overlay 装配、host 投影、生命周期钩、缺失能力投影；`send()` 的 `editorContext` / `beforeSend` 与上游 `UserPlace? from` / `notes` 参数并存（`notes: [...notes, ..._placeNotes(from), ...自有 editor 注]`，自有注仍按 `acceptsEditorContext` 收） | 内核适配 | `docs/design/thincoder-adapter.md` §29.2 | 净增 ≤180 行 |
| `lib/chat/chat_feed.dart` | `MarksTurns` 只读接口 | 内核适配 | `ChatSession.turns` 与 folds | 净增 ≤16 行 |
| `lib/chat/chat_models.dart` | `TurnMark`、`NoticeItem` 与 `editor_context.dart` re-export | 内核适配 | overlay / `KernelTurn.contexts` | 每类 ≤30 行 |
| `lib/chat/composer/composer_editing.dart` | `hasCommandSource` 命令源门；另承载上游方法体（`_caretAtEndOf` / `_takeDraftCodeOf` / `_handleEditorChangedOf` 等，拆分落点见 `docs/design/structure-splits.md` §4.3 第 5 步；`_buildBoxOf` 与 `_buildMarkdownEditorOf` 两个上游盒体在 `lib/chat/composer/composer_view.dart`:215 / :312） | 内核适配 | `ChatSession.hasCommandSource`；`composer.dart` 的委托 | 自有语义 ≤12 行；上游搬入体不构成 fork 净增 |
| `lib/chat/composer/composer.dart` | 委托形态：`_initStateOf` / `_takeDraftCodeOf` / `_takeDraftMessageOf` / `_handleDraftChangedOf` / `_submitOf` 等，实现体在同目录的 `…Of` 助手（上游新增体含 `_takeDraftCode` 与 `_submit` 的 intercept / Send Now 分支；`_submit` 的新体落在 `composer_message.dart` 的 `_submitOf`，本档只留 `void _submit() => _submitOf(this);`）；拆分机制归 `docs/design/structure-splits.md` §4.3 | 内核适配 | 顶层 helper（`…Of(this, …)`） | 上游内联体不构成 fork 净增；委托行按助手数计 |
| `lib/chat/composer/composer_view.dart` | btest 缓存键与状态行挂点（自有语义）；档本体是 `composer.dart` 的拆档前端 | 功能 | `ChatSession` 的 btest 七成员 | 自有语义 ≤24 行，按 btest 接缝符号计；`origin/main` 无此路径，档内上游搬入体不构成 fork 净增，不按 `numstat` 判 |
| `lib/chat/chat_screen.dart` | `canStopTasks` 单行接线（接线点 ⑬）· 改名初值 `thread.pendingTitle` 三行 · 回退界面 15 行（`revert_dialog` import、撤销与计划接线） | 修 bug · 功能 | `ChatSession.canStopTasks`；`AgentThread.pendingTitle`；`PlansReverts` | 净增 ≤19 行（实测 +19 / −3） |
| `lib/chat/side_panel/file_preview.dart` | 动作区按宽度收口：`tight`（`:505`，<420）与 `compactActions`（`:509`，<720）两个门，外加 `Flexible(FittedBox(scaleDown))`（`:538-539`）；文案按门槛收（`:545` / `:552`），`compact:` 传参 `:564` | 修 bug | 动作区装配点；上游新分支 `sidePanelChanges` 折入同一动作区 | 净增 ≤40 行 |
| `lib/browser/browser_tools.dart` | `HostTools` 注册包装、数字归一、description schema、btest gate、tab watch/blocked/acting | 功能 | `ClaudeSdkTool` / `HostTools` / `ClaudeSdkCall`；btest 经独立模块 | 净增 ≤150 行 |
| `lib/workspace/workspace.dart` | thincoder 目录、默认内核偏好、确认改名；标题门 `hostTitlesSession` 落在 `_titleAfter` 内（与其 `canRename` 合一处） | 内核适配 | `SessionCatalog`、`ConfirmsRename`、`SessionRenamed`；`hostTitlesSession` | 自有四块预算 ≤40 行；档整体相对上游 +125 / −31（`split('\n')` 口径实测 4051 / 3957） |
| `lib/main.dart` | thincoder 进程 reap/stop 与状态设置接线；上游设置清单由 `followSettingsFiles(files)` 承接，本档只留自有设置（`ThincoderPathSetting`、`EditorContextSetting`、Git 代理环境），逐键不重复赋值；诊断入口 7 行（`ViewportWatch.start()` / `StallWatch().start()` / `HangReports(...).check()` 三次调用、一行注释与三条 import） | 内核适配 | `ThincoderLocator` / process registry；`followSettingsFiles`；`lib/diagnostics/**` 的启动调用点 | 净增 ≤32 行（实测 +32 / −5） |
| `lib/platform/data_dir.dart` | 进程注册表文件名清单含 `thincoder`（`:87-88` 注释）+ `thincoderDataDir` 只读访问器 + `items` 加 `runtime-data` | 修 bug | `ChildProcessRegistry`；`items` 的迁移 / 清理条目表 | 净增 ≤7 行（≤2 + ≤5） |
| `lib/diagnostics/frame_watch.dart` | 顶层 `frameWatchState()` 一处定义 + `describeState()` 一行委托 + `_writeJank` 的调用点（台账 #201）；接缝 = `[slow]` / `[jank]` / `[stall]` 行的状态尾段；上游的体检体（树规模、会话数、内存、`heavyObjects` 之上按需分段）折进该函数体 | 功能 | `hang_watch.dart` / `stall_watch.dart` 读同一份定义 | 净增 ≤7 行（顶层函数文档 4 + 函数头 1 + 类收尾 1 + 空行 1） |
| `lib/kernel/kernel_registry.dart` | thincoder 为默认内核，Claude 保留 | 内核适配 | `_all = [thincoder, claudeCode]` | 净增 ≤12 行 |
| `lib/kernel/agent_kernel.dart` | fork 能力接口 | 内核适配 | `ConfirmsRename`、`AcceptsImageFiles`、`AcceptsEditorContext` 等 | 每个接口 ≤16 行 |
| `lib/kernel/kernel_types.dart` | `KernelTurn.contexts` 与回退数据形；`ContextUsage` 两字段并存（`sessionSpent` 会话已耗 + 上游 `detail` 分段明细） | 内核适配 | overlay 发送与 `PlansReverts`；上下文用量面板 | 每类 ≤40 行 |
| `lib/kernel/mock/mock_kernels.dart` | `MockKernels.thincoder` 描述符（`:34`，不进 `all`） | 内核适配 | `KernelDescriptor`；测试直用 | 净增 ≤16 行 |
| `lib/l10n/app_en.arb`、`app_zh.arb` | fork 文案键并集（合上游 52 后实测，不含 `@@locale`：en 4661 键、zh 3717 键，消息键两侧各 3715、逐键相等，余下为 en 侧的 `@` 元数据） | 功能 | ARB 源档；生成物由 `flutter gen-l10n` 再生，零手改 | 只增所需键；同名不覆盖上游措辞 |
| `lib/settings/pages/thincoder_models_page.dart` | thincoder 模型配置页 | 功能 | 设置页导航与 CLI 配置文件 | 自有页面；共享导航接缝另计 |
| `lib/settings/pages/general_page.dart` | thincoder 设置组（`:442-457`，接线点 ⑦）+ 设置 → 通用的 `chat.editorContext` 一行开关（接线点 ⑪） | 功能 | 设置页 `SettingsGroup` / `ThincoderPathSetting`；`EditorContextSetting` | 净增 ≤93 行（≤81 + ≤12） |
| `lib/settings/app_settings.dart`、`settings/settings_dialog.dart` | thincoder 设置入口；与上游 `SettingsSection.usage` 并存（enum / 分区列表 / 图标 / 文案四处） | 功能 | `SettingsSection.thincoderModels` / `SettingsSection.usage` | 合计净增 ≤50 行 |
| `lib/chat/composer/composer_picker.dart` | `startCollapsed` 参数与 `_collapseNewGroups`（新到的分组也收起，选中那组除外） | 功能 | `ComposerPicker.startCollapsed`；收起集合仍留在 picker 内 | 净增 ≤25 行 |
| `lib/chat/composer/session_model_picker.dart` | thincoder 会话默认收起 + 底部管理入口指向 thincoder 模型页；回合在飞时的等待态后缀（`pendingModel` → label / tooltip 的 `modelsSwitchPending`；机制见 `thincoder-adapter.md` §24） | 内核适配 | `ComposerPicker.startCollapsed`；`SettingsSection.thincoderModels`；`ChatSession.pendingModel` | 净增 ≤20 行 + 等待态块 17 行（`:45-48` · `:129-138` · `:155-157`） |
| `lib/kernel/claude_code/claude_sdk_tools.dart` | `ClaudeSdkTool` 的 `group` / `picturesOnly` 两字段；`ClaudeSdkTools` 保留上游类名，类体换成转发到自有 `HostTools` 的薄类（`server` / `register` / `unregister` / `instruct` / `instructFor` / `called` / `serversFor` / `handle` 八个成员，`:140-171`），档内不持有自己的工具表；类外的 `ClaudeSdkGate` 接口（`offersTool` / `asksUser` / `tellsFeature` 三个成员）与 `claudeSdkImage` / `claudeSdkText` 随上游保留 | 内核适配 | `HostTools` 注册表；ACP 的 MCP 面按 group 分服与 `picturesOnly` 门；`ClaudeSdkGate` 由自有 `HostTools.gate` 承接 | 净增 ≤38 行（两字段声明与构造参数 4 + 文档注释 2 + 转发类 32）；上游新增的 `ClaudeSdkAsk` / `ClaudeSdkCall.ask` / `ClaudeSdkTool.offeredIn` / `asksItself` 随上游保留；自有 `HostTools.handle` 按其新形跟进。上游以后给 `ClaudeSdkTools` 加静态成员会编译失败，按故意的信号处置。形态见 §7.2 |
| `lib/bots/bots.dart` | 按 cwd 的工具门落在自有注册表：两处 `gate`（`:153` 赋值 / `:174` 清空）与 `called` / `server`（`:460` / `:461` / `:497`）换 `HostTools.`，`claude_sdk_tools.dart` 的 import 换自有 `host_tools.dart`（`ClaudeSdkGate` 接口经自有档 re-export） | 功能 | `HostTools.gate` / `HostTools.called` / `HostTools.server`；`ClaudeSdkGate` 接口 | 净增 ≤6 行（5 行换符 + 至多 1 行自有 import） |
| `test/bots/bots_test.dart` | 删掉注册表类后的符号改名：档内 11 处 `HostTools.`（`handle` 5 · `register` 1 · `unregister` 1 · `server` 1 · `serversFor` 1 · `asksUser` 2）；断言内容随上游（工具集：`launch.tools` = `BotPermissions.agentTools`、带 `--tools`、无 `--strict-mcp-config`；符号仍 `HostTools.`），路径表达式按平台拼（26 处 `p.join`：上游写死 `/`，自有档在 Windows 上拼出 `\`） | 内核适配 | `HostTools` 的 handle / register / unregister / server / serversFor / asksUser | 净增 0 行（+38/−38：11 处换符 + 1 行 import 换行 + 断言路径改写） |
| `lib/bots/bot_tools.dart` | bots 的工具注册落自有注册表：`HostTools.register`（`:54`）/ `HostTools.unregister`（`:60`）；import 换自有 `host_tools.dart`（上游该档自带 `image_tools.dart` 与 `claude_sdk_tools.dart` 两行 import） | 功能 | `HostTools` 注册表；`HostTools.register` / `unregister` | 净增 1 行（import） |
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
| `lib/ide/ide_tab_bar.dart` | `renameInitial`：调用方给定的初值，优先于标签文本（改名框从该值起） | 功能 | `InlineRenameField.initial` | 净增 ≤6 行（`renameInitial` 三处：`_Tab` 字段 / 形参 / 透传；同段布局改写随上游 `96e61f6b`，前几批累积的 +89 / −57 随之失效） |
| `lib/chat/chat_history_view.dart` | 窗口可见性门：自有 `window_visible.dart` 的 import 与档内 9 处 `WindowVisible` 用法；重建的两个入口 `_showNow` / `_showWords` 各带一个门（窗口不可见时不重建，切回时一次追平） | 修 bug | `WindowVisible.changed` 订阅；集成面见 `test/RTM.md` 2-1 行 | 窗口门 1 行 import + 9 处用法；档整体相对上游 +337 / −26（`split('\n')` 口径实测 4262 / 3951） |
| `lib/chat/widgets/inline_rename_field.dart` | `checksTitle` 标题判定（空或超 80 不收，带错文案 `_error`），与上游的 `suggestions` / `onSummarize` 并存；`onChanged` 一处同时清错与过滤列表 | 功能 | 改名框的提交路径（§9 判定）；`InlineRenameField.checksTitle` / `initial` | 净增 ≤31 行（实测 +31 / −4） |
| `lib/kernel/claude_code/claude_code_kernel.dart` | 宿主工具通道：自有 `host_tools.dart` 的 import 与档内 5 行类型使用（`HostTools` 3 · `HostToolCall` 2） | 内核适配 | `HostTools` 注册表；`HostTool` / `HostToolCall` 别名 | 净增 ≤1 行（import） |
| `lib/update/version.dart`、`pubspec.yaml` | 版本行跟随上游 patch 并加 build 号（`1.9.0+27`）：两档必须同值，一处改了另一处不跟就是发货缺陷 | 修 bug | `test/update/version_test.dart` 校验两档同值 | 每档净增 0 |
| `lib/chat/side_panel/side_panel_view.dart` | 段条动作区的宽度算式：`_actionsWidth`（`:1538`）仍按三按钮计（`3 * 22.0 + 2 * 2 + 6` = 76），而 Islands 后动作区只剩两个按钮 —— 布局选择器（`:1662`）与关闭（`:1681`），实占 48（2 × 22 + 2 × 2）；`_actionsWidthFor(shown)`（`:1541`）在 plan 页扣掉列表开关（−24 ⇒ 52），而列表开关已移到文件页页签条的 `leading`（`:760-769`，`ValueKey('side-panel-list-toggle')`）⇒ 算式多算 28px（plan 页 4px），分段标题早 28px 收成纯图标 | 修 bug | `_SectionBar` 的 compact 阈值 | 净增 ≤14 行（实测 +10 / −3）；算式与 Islands 后的动作区不一致，改不改算式**待裁定**（open） |
| `lib/ide/ide_chat_title.dart` | 聊天页签的改名初值：`renameInitial: thread.pendingTitle`，经 `_ChatTab` 的形参透传到 `InlineRenameField.initial`（与 `lib/ide/ide_tab_bar.dart` 同一个 `renameInitial` 特性） | 功能 | `InlineRenameField.initial`；`AgentThread.pendingTitle` | 净增 ≤6 行 |
| `test/chat/code_citation_test.dart` | Windows 路径拼写：`path` import 与 `_q(path)`（`p.normalize`），断言按宿主拼写比对 | 修 bug | 路径断言的比较面 | 净增 ≤33 行 |
| `test/chat/side_panel/side_panel_workspace_test.dart` | Windows 路径拼写：三个根路径常量改 `p.normalize`，文件表与期望值改 `p.join`（档内 `p.join` 11 · `p.normalize` 4）；`_pump` 的 `roots` 默认值移进函数体（根路径改 `final` 后不能作 `const` 默认值） | 修 bug | 路径断言的比较面；用例条数与断言强度不变（无 `skip`、无放宽成 `contains`） | 净增 ≤3 行（上游 431 ⇒ 434） |
| `test/chat/side_panel/file_open_test.dart` | Windows 路径拼写：两个项目路径常量与「项目外文件」的绝对路径改 `p.normalize`（档内 3 处），文件名解析的期望值改 `p.join`（1 处） | 修 bug | 路径断言的比较面；三条用例与断言强度不变（无 `skip`、无放宽成 `contains`） | 上游 63 行 ⇒ 60 行（多行 `expect` 收到一行） |
| `test/composer_test.dart` | 自有用例 `two approvals are a switch at the end, five a menu (T61)`（`ComposerPermissionSwitch`：两条批准为开关、五条为菜单）+ 四条自有 import + btest 模式追加后的三处期望调整 | 功能 | `ComposerPermissionSwitch`；overlay 追加的 btest 模式 | 净增 ≤96 行（实测 +96 / −5） |

**恢复的上游 import 与自有 re-export 档重复**：`lib/browser/browser_tools.dart:13`、`lib/images/image_tools.dart:13` 与 `lib/bots/bot_tools.dart:13` 各带一条 `unnecessary_import` info（自有 `host_tools.dart` 的 re-export 覆盖同样四个符号）。这三行是上游行，删掉即重建常驻 fork 差异，**禁随 lint 清扫删除**。

**存量债（过 800 行的上游共享档，`wc -l` 实测 2026-11-04）**：`lib/kernel/claude_code/claude_code_kernel.dart` 3881 · `test/bots/bots_test.dart` 1690 · `lib/bots/bots.dart` 1367 · `lib/bots/bot_tools.dart` 963。

另四档（同口径）：`lib/chat/side_panel/side_panel_view.dart` 2303 · `lib/main.dart` 1112 · `lib/settings/settings_dialog.dart` 864 · `lib/ide/ide_tab_bar.dart` 946。

第九档 `lib/workspace/workspace.dart`（实测 4050）：按第 3 节该行维护四块自有语义（预算 ≤40 行）；档整体相对上游 `+125 / −31`，见该行读数。

九档都是上游共享档：拆分会让两半都成常驻 fork 差异（第 7.3 节同一理由），认账不排期。`lib/chat/composer/composer.dart` 现 744 行（<800），不在本名单。`workbench.dart` 的读数与体量立场归第 8.5 节，此处不复述。接手批次未排期，涨幅在下一次合并时按本行核对。

## 4 保持上游实现的共享文件

以下文件保持上游实现（两档带自有块，例外在行内注明）：

- `lib/ide/git/ide_scm_view.dart`；SCM「获取」语义按 #181 的裁定走上游。
- `lib/chat/composer/composer.dart`：带第 3 节登记的委托前端——助手名单、行数预算与拆分机制一律以第 3 节该行为准（`docs/design/structure-splits.md` §4.3），此处不复述；块外 UI 保持上游。
- `lib/chat/composer/composer_view.dart`：带第 3 节登记的 btest 接缝（缓存键与状态行挂点，自有语义 ≤24 行），改动只许落在该块内，块外 UI 保持上游。
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

## 7 宿主工具面：自有注册表与上游新形的共存

### 7.1 决策与理由

**决策**：`lib/kernel/claude_code/claude_sdk_tools.dart` 整档取上游新体，本档只做两处自有化，自有 `HostTools` 按上游新形同形跟进。

- ① `ClaudeSdkTools` 保留为**薄转发类**：类体只把上游消费方用到的八个成员（`server` / `register` / `unregister` / `instruct` / `instructFor` / `called` / `serversFor` / `handle`）转发到自有 `lib/host_tools/host_tools.dart`，档内不持有自己的工具表。
- ② `ClaudeSdkTool` 加回自有字段 `group`（默认 `''`）与 `picturesOnly`（默认 `false`）。
- ③ 自有 `HostTools` 与上游新 `handle` 同形：`_offers` 读 `offeredIn`、`_instructions` 按会话目录取值并带 `instructFor`、`tools/call` 透传 `ask`。

**为什么是转发类**：上游这批把注册表搬回本档，并且长出了新消费方，都按 `ClaudeSdkTools.<成员>` 调用：

- `lib/remote/local_tools.dart:74`（`register`）· `:76`（`instructFor`）· `:177`（`server`）
- `lib/kernel/claude_code/claude_code_kernel.dart:1650`（`called`）
- `test/kernel_test.dart:1635` / `:1645`、`test/remote/local_tools_test.dart:61` / `:63` / `:80` / `:177`
- `tool/e2e/ssh_windows_app.dart:1048` / `:1064`（`handle`）

转发类让这些上游档一行不动，与上游逐字节相同。

**为什么不是把消费方改名到 `HostTools`**：改名要在 `local_tools.dart` 与两个上游测试档上做十处改动、新立三行登记；测试档最易变，每批合并都要重新对账。转发类只落在已登记的本档上，零新登记行。两种做法语义等价，转发类的长期合并成本更低。

**为什么不许有自己的 `_tools` 表**：全部委托 `HostTools`。分表会让远程工具与本地工具各存一份，调用方看不见对方注册的工具 —— 静默不可见，比编译失败难查。

**代价（明写）**：转发类只覆盖那八个成员。上游以后给 `ClaudeSdkTools` 加静态成员会编译失败，这是故意的信号：看到失败就补一行转发，不让它在运行时静默缺失。另一面是 `HostTools.handle` 的 `ask` 透传、取消与抛错回 `isError` 仍随上游走形，上游改 `handle` 时本仓跟一次。这条维护面登记在本节。

**最近先例**：第 8 节的六组行为，同一形——改动压成最小登记块，其余交给上游符号。

**调查证据**：

- 上游侧 `git diff origin/main...HEAD -- lib/kernel/claude_code/claude_sdk_tools.dart` 本轮逐行读过：删 `group` / `picturesOnly`，加 `ClaudeSdkAsk`、`ClaudeSdkCall.ask`、`ClaudeSdkTool.offeredIn` / `asksItself`，并整段加回 `ClaudeSdkTools`（`register` / `unregister` / `instruct` / `instructFor` / `gate` / `_offers` / `_tells` / `asksUser` / `called` / `any` / `servers` / `serversFor` / `handle`）。
- 自有侧 `lib/host_tools/host_tools.dart` 现态（`:26` 起 `abstract final class HostTools`）：`_instructions` 值类型 `Map<String, String? Function(String cwd)>`（`:59`）、`instructFor`（`:69`）、`_offers` 读 `offeredIn`（`:85-86`）、`ask: call.ask`（`:194`）；取消表（`:179-186` / `:217-221`）与抛错回 `isError`（`:207-213`）在。三项与上游同形。
- 公开来源：`manifest.index.publicRepos` 为空，无独立文档仓；上游源码经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

### 7.2 接口契约

| 面 | 契约 |
|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 上游体 + `ClaudeSdkTool` 的 `group` / `picturesOnly` 两字段 + `ClaudeSdkTools` 转发类（八个成员，类体只调 `HostTools`，无自己的工具表）。类外 `ClaudeSdkGate`、`claudeSdkImage` / `claudeSdkText`、`ClaudeSdkAsk` 随上游保留 |
| `lib/host_tools/host_tools.dart` | `typedef HostTool = ClaudeSdkTool;` / `typedef HostToolCall = ClaudeSdkCall;` 与 re-export 照旧；`HostTools` 三项与上游同形：`_offers(cwd, name)` = `offeredIn` 判定 且 `gate.offersTool`（`:85-86`）、`_instructions` 值类型 `Map<String, String? Function(String cwd)>` 带 `instructFor`（`:59` / `:69`）、`tools/call` 的内层 `HostToolCall` 带 `ask: call.ask`（`:194`） |
| 数据流 | 注册 → `HostTools.handle`（JSON-RPC）→ `ClaudeSdkTool.run(input, ClaudeSdkCall)`；`ask` 与 `cancelled` 由内核经 `ClaudeSdkCall` 传入，工具自取 |
| 分服暴露 | `HostTools.byGroup(group)` 仍按自有 `group` 字段分；`picturesOnly` 仍在 `lib/host_tools/host_mcp_server.dart` 过滤 |

**净增算术**：本档自有增量 = 字段 4 行（两字段声明 + 两构造参数）+ 单行文档注释 2 行 + 转发类 32 行（`:140-171`）= 38 行；档内无 `_tools` 表（实测 0 处）。按符号核，不按旧行号。实测：上游 305 ⇒ 172。

### 7.3 受影响文件与行数

行数 = `split('\n')` 口径（含末行换行）。**实施前** = 本轮（2026-11-04）工作树实测；**上游** = `git show origin/main:<path>` 同口径；**合入后** = 合并提交 `f3a4ddb7` 后的工作树实测（2026-11-04）。

| 文件 | 实施前 | 上游 | 合入后 | 改写面 |
|---|---|---|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 106 | 305 | 172 | 上游体 + 两字段 + `ClaudeSdkTools` 转发类（38 行，§7.2 净增算术）；档内无 `_tools` 表 |
| `lib/host_tools/host_tools.dart` | 224 | —（自有档） | 237 | 三项同形跟进：`_offers` / `instructFor` / `ask` 透传 |
| `lib/browser/browser_tools.dart` | 748 | 705 | 768 | `group:` / `picturesOnly:` 两参数保持；上游本批体随之进来 |
| `lib/images/image_tools.dart` | 603 | 601 | 603 | 同上 |
| `lib/browser/browser_actions.dart` | 627 | 626 | 627 | 零改动 |
| `lib/browser/browser_debug_tools.dart` | 1786 | 1786 | 1786 | 零改动 |
| `lib/browser/browser_history.dart` | 825 | 825 | 825 | 零改动 |
| `lib/browser/browser_inspect.dart` | 1169 | 1169 | 1169 | 零改动 |
| `lib/browser/browser_intercept.dart` | 477 | 477 | 477 | 零改动 |
| `lib/browser/browser_sources.dart` | 1566 | 1566 | 1566 | 零改动 |
| `lib/browser/browser_watch.dart` | 616 | 616 | 616 | 零改动 |
| `lib/bots/bots.dart` | 1364 | 1368 | 1368 | 两块不重叠：自有 `HostTools.` 换符块 +6/−6（合基 `2967918` 起算），上游本批 +10/−6 落在块外，该档不在 12 处冲突内 ⇒ 1364 + 4 = 1368 |
| `lib/bots/bot_tools.dart` | 964 | 963 | 964 | 上游本批未动该档；自有 import 一行保留（+3/−2）⇒ 964 |
| `test/host_tools/host_tools_test.dart` | 393 | —（自有档） | 393 | 别名继续成立，零改动 |
| `test/host_tools/host_mcp_server_test.dart` | 384 | —（自有档） | 384 | 同上 |
| `test/browser/**` | 目录内档零改动 | — | 同实施前 | 零改动 |

### 7.4 关键决策记录

| 选项 | 内容 | 结论与理由 |
|---|---|---|
| A（采用） | 取上游体，`ClaudeSdkTools` 改成转发到自有 `HostTools` 的薄类（八个成员） | 上游消费方一行不动（逐字节与上游相同）；零新登记行；自有分服暴露与 `group` 面全保 |
| B（否） | 整档取上游，丢弃 `group` / `picturesOnly` | 自有 `host_mcp_server.dart` 的分组暴露失去依据，是删自有功能 |
| C（否） | 注册表让给上游，自有档改薄封装 | 上游 `_tools` 库私有，封装读不到内容；要读就得在上游体里加可见性改动，差异从一块变满档 |
| D（否） | 删掉类段，把上游消费方改名到 `HostTools` | 十处改动 + 三行新登记，测试档每批重新对账；与 A 语义等价但长期合并成本更高 |

### 7.5 验收对照

| 条目 | 判据（机器可判） |
|---|---|
| 上游档只做两处自有化 | `git diff origin/main -- lib/kernel/claude_code/claude_sdk_tools.dart` 的「增」≤ 40；档内 `ClaudeSdkTools` 类 = 1、类体成员 = 8 |
| 转发类不持表 | 上游档内 `static final Map<String, ClaudeSdkTool> _tools` 计数 = 0（实测 0）；每个成员体调 `HostTools.` |
| 三项同形 | 自有档内 `ask: call.ask` = 1、`instructFor` ≥ 1、`offeredIn` ≥ 1（实测 1 / 1 / 2） |
| 分组与纯图片面不变 | `lib/browser/browser_actions.dart` 的 `picturesOnly: true` 在盘；`lib/browser/browser_tools.dart` 的 `group: 'browser'` 与 `picturesOnly: tool.picturesOnly` 在盘；`lib/images/image_tools.dart` 的 `group: 'images'` 在盘 |
| 编译与测试 | `flutter analyze --no-pub` 的 error 数 = 0；`flutter test test/host_tools/host_tools_test.dart test/host_tools/host_mcp_server_test.dart` 全绿（改动面两档）。`test/browser/**` 本批零改动（§7.3），只作可选回归，不进本批判据 |

### 7.6 用例表

| 场景 | 输入 | 期望 | 承载用例 |
|---|---|---|---|
| 正常 · 注册后调用 | `HostTools.register` 后 `handle({'method': 'tools/call', 'params': {'name': t}})` | 返回该工具的文本块，`isError` 不置 | `test/host_tools/host_tools_test.dart` |
| 正常 · 组暴露 | `HostTools.byGroup('images')` | 含该组工具，不含别组 | `test/host_tools/host_tools_test.dart` |
| 边界 · 纯图片工具 | `picturesOnly: true` | MCP 面不给它 | `test/host_tools/host_mcp_server_test.dart` |
| 边界 · 目录门 | `offeredIn` 返回假 | `tools/list` 与 `tools/call` 都不给该工具 | 静态读数：自有档内 `offeredIn` ≥ 1 且 `flutter analyze --no-pub` 的 error 数 = 0（`offeredIn` 是上游本批新增，既有用例不含该判定，见下） |
| 错误 · 未注册工具 | `handle({'method': 'tools/call', 'params': {'name': 'nope'}})` | `isError: true` + `No tool nope.` | `test/host_tools/host_mcp_server_test.dart` |

**`ask` 透传与 `offeredIn` 目录门都无现成用例承载**：两者都是上游本批新增的行为（§7.1 调查证据），本仓既有用例写在这些行为之前，不可能已带该判定。它们改的是上游新行为在自有注册表里的存活，判据同取 §7.5 的静态读数（`ask: call.ask` = 1 · `offeredIn` ≥ 1）与 analyze 的 error 计数；不为它们新造常驻用例。

### 7.7 边界（不做）

- 不改上游 `handle` 的判定次序与返回形状。
- 不动自有 `group` / `picturesOnly` 的语义与消费方。
- 不让 `ClaudeSdkTools` 持表：它只转发，注册表仍是 `HostTools`。
- 不为上游消费方没用到的成员加转发：八个之外不加，上游加新成员时按编译失败补。
- 不动测试档的别名用法。

### 7.8 UI / 交互

无界面变化：本批改注册表落点、两个自有字段与三处判定，工具描述与返回形状不动。

关联档 `docs/design/host-tool-channel.md` 按本节改后形态核对，本轮逐段读过：

- 注册表落点：§2.2 偏离 ② 与 D2 写成自有 `lib/host_tools/host_tools.dart` —— 改后成立。
- `group` / `picturesOnly` 的字段来源：§4.7 标「自有新增」 —— 改后仍是自有字段，成立。
- `host-tool-channel.md` §7.1 ①′ 与 §16 的档位归属：类型层在该档、`ClaudeSdkTools` 是转发到自有 `lib/host_tools/host_tools.dart` 的薄类、注册表在自有档 —— 成立。

### 7.9 集成测试设计（RTM delta · 本机制）

本节只判本机制（宿主工具面）；全批范围的 delta 在批档 §2 的「集成测试设计（RTM delta）」节，两者不互相顶替。

`test/RTM.md` 读后：与本机制同字的行只有 1-1 行的 `ProcessHost`，不同面（本机制不碰进程创建）。

- 被破坏的行：无 —— 本机制不改业务可观察结果（注册表落点、两个带默认值的字段、三处内部判定）。
- 冗余可删的行：无。
- 缺失需新增的行：无 —— 两个入口都不成立：没有新的业务场景，也没有生产报告。

⇒ 本机制收口报 `none`，不改 RTM。

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

| 文件 | 行数（2026-11-02 实测） | 本批块 | 预算（第 3 节） |
|---|---|---|---|
| `lib/chat/composer/session_model_picker.dart` | 259 | 回合在飞时的等待态后缀，17 行 | ≤20 行 |
| `lib/workbench.dart` | 5408 | 面板命令源 · 扫描失败面 | 面板 ≤10 · 扫描 ≤59 |
| `lib/ide/ide_workbench.dart` | 5878 | chord 第二键的窗口门，21 行 | ≤22 行 |
| `lib/ide/ide_editor.dart` | 3160 | 控制器为空的空渲染，7 行 | ≤7 行 |
| `lib/chat/chat_session.dart` | 1401 | 回退后的审查刷新钩，5 行 | ≤180 行 |

**体量立场（不拆档）**：五档都是上游共享档。本批改动合计 +112 / −18（净增 94 行；`54f94769` +76 / −9 与 `e5661df4` +36 / −9，`git diff --numstat` 实测，不计批档自身 32 行），形态都是第 3 节登记块内的小块。

`workbench` 5408 · `ide_workbench` 5878 · `ide_editor` 3160 · `chat_session` 1401 四档过 800 行，属存量债，按 §7.3 同一理由不拆档：把上游共享档拆成两档，两半都成常驻 fork 差异，每次上游合并要在两处对账，与第 1 节的目标相反。

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
