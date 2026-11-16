# 2026-11-15 · upstream-sync-6
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-15 · 来源 = 用户 2026-11-15「拉代码更新」。
> 台账 = #242（— · 归批）。前情 = docs/batches/2026-11-10-upstream-sync-5.md §6（已收口 2026-11-11）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-15
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：合上游 111 个提交（1.9.5 → 1.9.6）+ 出新构建

合基 `5f4a1d50`（上批合到的上游 tip）；本地合并前 `8d80c089`；上游 tip `1987ad78`（1.9.6 发版，2026-11-16 10:17 +0800）。

**已定决定**：按既有形态合上游到 main——冲突按 `docs/design/fork-deltas.md` 登记面处置（自有块保留、上游新形跟进、不整档回退）；l10n 只做键级并集 + `flutter gen-l10n` 重产；合后出新 Release 构建并替换运行实例 · 用户原话：「拉代码更新」· 时间：2026-11-15 19:38

**网络**：经本地代理 `http://127.0.0.1:7890` 拉取成功。

**规模**：上游 111 个提交、189 档；版本 `1.9.5+31` → `1.9.6+32`；其中 **27 档与登记表重叠**（自有块 ∩ 上游改动）。

- 会话与面板：`chat_session.dart` · `chat_screen.dart` · `chat_models.dart` · `composer.dart` · `side_panel_view.dart` · `file_preview.dart` · `sidebar.dart` · `workspace.dart` · `workbench.dart`
- 内核与设置：`claude_code_kernel.dart` · `app_settings.dart` · `general_page.dart` · `main.dart`
- Bots 与工具：`bots.dart` · `bot_tools.dart`
- 其它：`frame_watch.dart` · `ide_scm_view.dart` · `ide_workbench.dart` · `version.dart` · l10n 三档
- 测试：`bots_test` · `file_open_test` · `side_panel_test` · `kernel_test` · `models_test`

**上游主线项**：每条消息图片上限 100 · 会话工具（一个会话调度其它会话）· 项目内加文件夹（不升为工作区）· 远程终端支持 `code` + 上传下载进度 · `bash.exe` · 设置转移 · 手机上传与增量推送 · 会话扫描改有界内存 · 多处在 Windows 上的修复（拖动窗口置前、托盘图标、远程终端刷屏）。

**冲突（6 档 / 12 块，合并停在冲突态，未提交）**：

| 档 | 块 | 现场 |
|---|---|---|
| `lib/settings/pages/general_page.dart` | 5 | 两侧各加设置：我方 `thincoderStatus` + 编辑器上下文，上游 `bash`（Windows 的 BaoCode Bash）+ `chat.liveTurnStats` 改名 |
| `lib/chat/composer/composer.dart` | 3 | 我方把 `_copyToHost` / `_handleEditorChanged` 抽成 `…Of(this, …)` 的薄壳；上游重写了这两个函数体（传输进度 + 通知、`_lag.time`） |
| `lib/workbench.dart` | 1 | 我方 `_sidePanelRetryTimer?.cancel()`，上游 `_workspace.removeListener(_reloadedElsewhere)` —— 两侧各一行 |
| `lib/settings/app_settings.dart` | 1 | 传参：`thincoderStatus` vs `bash`，两侧都要 |
| `lib/ide/ide_workspace.dart` | 1 | 我方 git 检测两行，上游删空该处 |
| `lib/chat/chat_session.dart` | 1 | 我方 overlay 的 `beforeSend` + 编辑器上下文 + notes；上游 `userSent?.call()` + 精简后的 turn |

**l10n 注意**：两个 arb 与三个生成档本轮**自动合并成功**（无冲突块）——但生成档是产物，按 §1 规则仍须 `flutter gen-l10n` 重产，不得以自动合并结果为准。

**当前状态**：`git merge --no-ff origin/main` 已执行并停在冲突态（`MERGE_HEAD` 在、工作树带冲突标记）；未提交、未构建、未替换实例。

**下一步**：§2（设计席，逐档处置表）→ 设计评审 → 批准 → eng-coder 解冲突并完成合并 → 机检 → 构建 → 替换实例 → 收口。

### 父侧核读 §2 后的修轮清单（评审前）

两处实测缺陷，派设计席修：

| # | 缺陷 | 实测 | 改法 |
|---|---|---|---|
| 1 | 验收 ⑦ 点名 `test/chat/composer_test.dart`，**该档不存在** | `test/chat/` 下没有 `composer_test.dart`；composer 面拆在 `composer_*_test.dart` 多档 + `test/chat/composer/` 目录 | 换成真实在盘的用例档：`test/chat/composer_files_test.dart`（块 6 · 复制到主机）、`test/chat/composer_input_lag_test.dart`（块 7 · `_lag` 计时）、`test/chat/composer_draft_sync_test.dart`（块 7 · 编辑变更）；保留 `test/chat/session_overlay_test.dart`（块 12） |
| 2 | 验收 ① 的标记扫描只到 `-- lib` | 本批冲突全在 lib（实测 6 档），但判据不该绑在本批形态上 | 改成全仓扫描（去掉路径参数），或 `-- lib test docs` |

**其余**：§2 的 12 块处置表、表外补登记、tier 结论、RTM 报 none、决策 A–D 均已核读，无异议。

**本修轮不做**：不改产品代码、不动冲突态工作树、不跑测试、不写 §4 / §6。

### 评审轮 1 的裁决（1🔴 · 8🟡 · 3🔵 ⇒ 12 条全受理，派设计席修）

§3 表的 `Suggestion` 列就是改法，执行者是设计席。本席逐条裁定：**12 条全部受理**，无双非、无 Deferred。

- **按编号逐条改（1..12），报告按「编号 → 改了什么 + 档路径 + 改动后的原话」回报**，不要只写「已改」。
- 第 1 条的要点：fork-deltas 的 `lib/chat/composer/composer.dart` 行与 §2 块 7 对齐成同一锚点（计时器在壳、体进 `_handleEditorChangedOf`），并给验收 ③ 补位置读数。
- 第 9 条先把定位换成符号锚，行号只留作括注（本仓规则：不以旧行号判断接线）。

**本修轮不做**：不改产品代码、不动冲突态工作树、不跑测试、不写 §4 / §5 / §6、不改其它设计档。

### eng-coder 上抛裁决：⑦ 按「无新增失败」判

**事实**（eng-coder 实跑）：基线 `8d80c089` 上同一批用例 189 passed / 6 failed / 8 skipped；解冲突后 374 passed / 6 failed / 8 skipped，失败集逐条相同——`test/kernel_test.dart` 5 条（Windows 路径拼写 / 仅 POSIX 夹具），`test/composer_test.dart` 1 条（semantics-tree 检查抛错，非断言失败）。

**裁决**：⑦ 的「全绿」按「**与合前基线同一失败集、无新增失败**」判。这是本仓既有口径（上一批 §2.7 第 10 条同形）。**不授权**改上游 `test/kernel_test.dart` / `test/composer_test.dart`：为过判据给上游测试加 Windows skip，会新增常驻 fork 差异，代价高于收益。§5 写明基线读数与失败清单。

**附带**：eng-coder 另修的两处（`test/chat/side_panel/file_open_test.dart` 的 `const` 复用我方 `final` 导致 analyze 2 error、以及该档 2 条 Windows 拼写期望）不在 §2 受影响文件表内，但该档在 `docs/design/fork-deltas.md` §3 有登记行（接缝 = 按宿主拼写改断言），修法合规 ⇒ §6 记账，并记一条设计面遗漏（§2 受影响文件表未收该档）。

### 实施后的登记面补记（派设计席）

合后 numstat 对账（验收 ④）查出 5 条表外非零行 + 1 处登记行不完整，均按 `docs/design/fork-deltas.md` §5 第 2 步补登记：

| # | 档 | 合后 numstat | 自有块 |
|---|---|---|---|
| 1 | `lib/kernel/claude_code/claude_code_translator.dart` | +2 / −1 | `HostTools.called` + `HostTool` 换符（上游写 `ClaudeSdkTools.called` / `ClaudeSdkTool`） |
| 2 | `lib/window/app_windows.dart` | +28 / −10 | `requestClose` / `_remove` 的一次性守卫（`_closing` 前置、`_removing`） |
| 3 | `test/forge/forge_test.dart` | +2 / −2 | `issue.number` → `issue.key` 两条断言 |
| 4 | `test/window/app_windows_test.dart` | +20 / −0 | 上述守卫的用例 |
| 5 | `test/workspace_test.dart` | +93 / −9 | `_DirectoryCatalog` 与按目录列会话的用例组 |

另两处更正：`lib/ide/ide_workspace.dart` 行只覆盖 6 行（`openWorkspaces` 三处 + 构造期 `_detectIn` 一行），其余 7 行是 `IdeWorkspace.documentOf`（消费方 `lib/ide/ide_kernel_files.dart` 三处 + 两个用例档）⇒ 补齐；`test/chat/side_panel/file_open_test.dart` 行的措辞仍是合前形态（`p.normalize` 3 / `p.join` 1，合后 6 / 3）⇒ 按合后改写。

**另记一条**：`ide_workspace.dart` 构造体的 `_detectIn(root)` 一行经核为空转（`_setRoots` 同一守卫已调用过，`_gitOf == null` 时 `isMultiRoot` 恒假）。§2 块 11 明写保留，本批照设计保留；删除归下一次清理，记 §6 已知状态。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（评审轮 1 的 12 条已按编号落地；实施后补记五条表外补登记与两处更正已落 docs/design/fork-deltas.md §3）


### 本批条目（覆盖）

| # | 条目 | 判据去向 |
|---|---|---|
| 1 | 6 档 12 个冲突块逐块处置，每块按 `docs/design/fork-deltas.md` 登记面判（自有块保留 / 上游新形跟进 / 不整档回退） | 本文「逐档处置表」；验收 ①③ |
| 2 | 表外自有块补登记六行（`lib/ide/ide_workspace.dart` + 五条表外档，见「实施后补记」）+ 5 行形态更新（`chat_session` / `composer` / `general_page` / `app_settings` / `workbench`） | `docs/design/fork-deltas.md` §3；验收 ④ |
| 3 | l10n 两档 arb 键级并集 + `flutter gen-l10n` 重产三档生成物 | 验收 ⑤ |
| 4 | 版本两档同值 `1.9.6+32` | 验收 ⑥ |
| 5 | 合后按 `origin/main` 的 numstat 对账，判据域内每条非零行命中 §3 登记行 | 验收 ④ |
| 6 | 出新 Release 构建并替换运行实例 | §1「下一步」；父侧收口面，不属本设计判据 |

### 设计档落点

- `docs/design/fork-deltas.md` §3：新增 `lib/ide/ide_workspace.dart` 行（表外首次登记，实测值见该行）；`chat_session.dart`、`composer.dart`、`general_page.dart`、`app_settings.dart`、`workbench.dart` 五行改后形态更新。
- 其它设计档不改。`docs/design/structure-splits.md` §4.3 的拆分机制不动；`docs/design/thincoder-adapter.md` 的 `send()` 契约不动。

**最近先例**：`docs/design/fork-deltas.md` §3.1 记的四条表外补登记与第 7 / 8 节同一形——自有语义压成最小登记块，其余交给上游符号。

- 那四条：2026-11-05 `lib/chat/step_folds.dart` / `lib/sidebar/sidebar.dart`；2026-11-08 `lib/models/secret_store_io.dart` / `lib/keybindings/workbench_keybindings.dart`。
- 本批 `lib/ide/ide_workspace.dart` 同一形，登记行即 §3 新增的那行。
- 偏离：块 7 的计时器留壳（不搬进助手），理由见下「块 7 的依据」。

**调查证据**：本轮查过 `docs/design/fork-deltas.md` 全档、本批批档 §1、`PROJECT-MANIFEST.json`；上游源码经本仓 `origin` 远端读取（`git show origin/main:<path>`），属仓内读。

- `PROJECT-MANIFEST.json` 本轮读得 `"publicRepos":[]`、`docRoot.standards` 为 null ⇒ 无独立文档仓、无项目标准档。
- 结论：无外部相关来源，沿用 `docs/design/fork-deltas.md` §3.1 的调查证据口径。

### 逐档处置表（12 块）

| # | 档 · 块 | 现场 | 处置 |
|---|---|---|---|
| 1 | `general_page.dart` · 类注释 | 我方多 `telemetry`/`chat.liveTurn.*`/`thincoder.path` 段；上游把 `chat.liveTurn.*` 改名 `chat.liveTurnStats` 并加「tokens」「BaoCode Bash on Windows」 | 取上游新措辞，句末补我方 `thincoder.path` 一段；`telemetry` 句**删**——上游 `origin/main` 该档类注释已无该键（`git show origin/main:lib/settings/pages/general_page.dart` 内 `telemetry` 无命中，本席实测） |
| 2 | `general_page.dart` · 构造参数 | `this.thincoderStatus` vs `this.bash` | 两个都留 |
| 3 | `general_page.dart` · 字段 | `Future<ThincoderStatus> Function()? thincoderStatus` vs `BaoBash? bash` | 两个字段带各自文档注释都留 |
| 4 | `general_page.dart` · 开关行 | 我方 `chat.editorContext` 行 vs 上游 `chat.sessionTools` 行 | 两行都留（两个独立设置项） |
| 5 | `general_page.dart` · 设置组 | 我方 thincoder 组 vs 上游 BaoCode Bash 组 | 两组都留，组尾 `],` / `),` 各收一次 |
| 6 | `composer.dart` · `_copyToHost` | 我方薄壳 `=> _copyToHostOf(this, files)` vs 上游 `withTransferProgress` 新体 | 留我方薄壳；上游新体（进度 / 可取消 / 失败通知）写进 `composer_editing.dart` 的 `_copyToHostOf`，替换其中手写的计时器进度体 |
| 7 | `composer.dart` · `_handleEditorChanged` | 我方 `=> _handleEditorChangedOf(this)` vs 上游 `_lag.time('edit', _editorChanged)` + 重写的编辑体 | 壳写成 `void _handleEditorChanged() => _lag.time('edit', () => _handleEditorChangedOf(this));`；上游新编辑体写进 `_handleEditorChangedOf`（`state.` 前缀，`_lag.time('draft', …)` 同步带入） |
| 8 | `composer.dart` · `_handleKey` | 我方 `=> _handleKeyOf(this, event)` vs 上游全量体 | 留我方薄壳；上游体写进 `composer_menu.dart` 的 `_handleKeyOf`，补首行 `state._lag.begin('key')` |
| 9 | `app_settings.dart` · 页面构造 | 传 `thincoderStatus:` vs 传 `bash:` | 两个都传 |
| 10 | `workbench.dart` · `dispose` | 我方 `_sidePanelRetryTimer?.cancel();` vs 上游 `_workspace.removeListener(_reloadedElsewhere);` | 两行都留（互不相干） |
| 11 | `ide_workspace.dart` · 构造体 | 我方 `openWorkspaces.add(this)` + 构造期 git 检测两行；上游删空该处 | 留我方两行，锚点是符号：`IdeWorkspace.openWorkspaces` 的静态声明 / 构造登记 / `dispose` 注销，加构造体的 `_detectIn(root)` 一行；上游自己的 `_detectIn` 两处调用仍在，不冲突 |
| 12 | `chat_session.dart` · `send()` | 我方 `beforeSend` + `takesContext` + `_placeNotes` + `acceptsEditorContext` 收口 vs 上游 `userSent?.call()` + 精简 turn | 取我方结构（`beforeSend` 包住 `KernelTurn`、`open`、notes 三来源）；上游的 `if (from != null) userSent?.call();` 落在空消息早退 `if (message.isEmpty || !canSend) return;` 之后、`_overlay.beforeSend(` 之前（空消息不计数，与上游同）；`_editorNotes` 仍按 `!takesContext` 收，勿取上游的无条件 `if (editor != null)` |

**块 7 的依据**：上游 1.9.6 把 `_handleEditorChanged` 拆成两段——计时器一行，编辑体落在新方法 `_editorChanged`（读自 `origin/main:lib/chat/composer/composer.dart`）。

本仓委托形态要求方法体在 `…Of` 助手里，故计时器留壳上、体进助手：

- 壳：`void _handleEditorChanged() => _lag.time('edit', () => _handleEditorChangedOf(this));`。`_lag.time('edit'` 只在 `composer.dart`，助手档 0 处。
- 体：进 `_handleEditorChangedOf`，体内 `state._lag.time('draft', …)` 随带入。
- 语义等价：`_lag` 仍是本 state 的字段。

### 受影响文件与测试覆盖

| 文件 | 改动面 |
|---|---|
| `lib/settings/pages/general_page.dart` | 5 块（注释 / 参数 / 字段 / 开关行 / 设置组） |
| `lib/chat/composer/composer.dart` | 3 块（三条委托行） |
| `lib/chat/composer/composer_editing.dart` | `_copyToHostOf` 换上游新体；`_handleEditorChangedOf` 换上游新体 |
| `lib/chat/composer/composer_menu.dart` | `_handleKeyOf` 补 `_lag.begin('key')` |
| `lib/settings/app_settings.dart` | 1 块（两个参数都传） |
| `lib/workbench.dart` | 1 块（两行并存） |
| `lib/ide/ide_workspace.dart` | 1 块（我方两行保留） |
| `lib/chat/chat_session.dart` | 1 块（我方结构 + `userSent`） |
| `lib/l10n/app_en.arb`、`app_zh.arb`、三档 `app_localizations*.dart` | 源档键级并集已自动合并；生成物重产 |
| `lib/update/version.dart`、`pubspec.yaml` | `1.9.6+32` |

**tier 结论**：零跨档——本批无文件因本节改写跨档，不新建模块、不迁目录，无拆分计划。

表内两档是已被裁定的存量债，本批不动拆分：

- `lib/workbench.dart` 与 `lib/chat/chat_session.dart`：按 `docs/design/fork-deltas.md` §8.5 的体量立场（过 800 行的上游共享档「属存量债，不拆档」）与 §3 的存量债段处置。
- `lib/chat/composer/composer.dart`：它的拆分状态就是它的拆分机制（`docs/design/structure-splits.md` §4.3 的 `…Of` 助手拆分）；本批只往助手内搬上游体，不动拆分落点。

**测试覆盖**：`flutter analyze --no-pub` 全批一次，加两组定向用例。

第一组是上游本批触碰的用例档（回归面）：`test/bots/bots_test.dart` · `test/chat/side_panel/file_open_test.dart` · `test/kernel_test.dart` · `test/models/models_test.dart` 进 ⑦。

`test/chat/side_panel/side_panel_test.dart` 不进 ⑦，作可选回归：

- 它在 `docs/design/fork-deltas.md` §4 的上游冻结面内（该档与上游逐字节相同，本批不改它）。
- Windows 下该档是已知的路径拼写族红（台账 #216），判据无法判绿。

第二组是冲突块的行为面用例档（本批改动面，逐块一行）：

- `test/chat/composer_files_test.dart` —— 块 6 · 复制到主机经 `_copyToHost`；调用点在 `lib/chat/composer/composer_editing.dart` 的 `state._copyToHost(`。
- `test/chat/remote_drops_test.dart` —— 块 6 · 远程投放走同一调用点。
- `test/chat/composer_input_lag_test.dart` —— 块 7 · `_lag` 的 `draft` / `edit` 计时（断言 `draft … , edit …` 日志行；`edit` 计时来自 `composer.dart` 的壳）。
- `test/chat/composer_draft_sync_test.dart` —— 块 7 · 一处的编辑同步进草稿，另一处随之更新。
- `test/chat/chat_keys_test.dart` —— 块 8 · `_handleKey` → `ChatKeys.dispatch`（`lib/chat/composer/composer_menu.dart` 的 `_handleKeyOf`）。
- `test/composer_test.dart` —— 块 8 · 该档 `Shift+Tab in the input goes through the modes` 走同一条链：`_handleKeyOf` → `ChatKeys.dispatch` → `ChatCommandsOf` 的 `ChatCommandIds.nextMode` → `_nextMode` → `_nextModeOf`，而块 8 换的正是 `_nextModeOf` 所在的助手档。
- `test/chat/session_overlay_test.dart` —— 块 12。

### 验收对照（机器可判）

| # | 判据 |
|---|---|
| ① | `git status --short` 的冲突条数 = 0；全仓 `git grep -c "^<<<<<<<"` 与 `git grep -c "^>>>>>>>"` 均无输出（不带路径参数；判据不绑本批形态） |
| ② | `flutter analyze --no-pub` 的 error 数 = 0 |
| ③ | 逐块静态读数（符号锚：每条只数它证明的那一处，不数注释与邻近标识符）。`chat_session.dart`：`_overlay.beforeSend(` = 1 · `if (from != null) userSent?.call();` = 1 且位于 `if (message.isEmpty || !canSend) return;` 之后 · `final takesContext = acceptsEditorContext;` = 1 · `if (!takesContext && editor != null)` = 1。`composer.dart`：`=> _copyToHostOf(this, files)` = 1 · `=> _handleEditorChangedOf(this)` = 1（同一行含 `_lag.time('edit'`）· `=> _handleKeyOf(this, event)` = 1。`composer_editing.dart`：`_lag.time('edit'` = 0（计时器在壳上）· `withTransferProgress` ≥ 1 · `state._lag.time('draft'` ≥ 1 · `void _handleEditorChangedOf(` = 1。`composer_menu.dart`：`state._lag.begin('key')` = 1。`general_page.dart`：`this.thincoderStatus,` = 1 · `final Future<ThincoderStatus> Function()? thincoderStatus;` = 1 · `this.bash,` = 1 · `final BaoBash? bash;` = 1 · `BaoBashSetting(bash: bash)` = 1 · `EditorContextSetting.enabled(` = 1 · `SessionToolsSetting.enabled(` = 1。`app_settings.dart`：`thincoderStatus: thincoderStatus,` = 1 · `bash: bash,` = 1。`workbench.dart`：`_sidePanelRetryTimer?.cancel()` = 2（`dispose` 与扫描失败路径各一）· `_reloadedElsewhere` ≥ 2（构造期 `addListener` 与 `dispose` 的 `removeListener`）。`ide_workspace.dart`：`static final Set<IdeWorkspace> openWorkspaces` = 1 · `openWorkspaces.add(this)` = 1 · `openWorkspaces.remove(` = 1 |
| ④ | 判据域 = 本批上游触碰且为共享上游档的档：合后 `git diff --numstat origin/main` 的每条非零行逐条命中 `docs/design/fork-deltas.md` §3 的登记行；`lib/l10n/app_localizations*.dart` 由 arb 行承载。`ide_workspace.dart` 的块是否存活按 ③ 的符号锚判（`openWorkspaces.add(this)` = 1 · `static final Set<IdeWorkspace> openWorkspaces` = 1），不按 numstat；§3 各补登记行的「行数预算」列一律取合后 `git diff --numstat origin/main HEAD` 的读数（该档 +13 / 0） |
| ⑤ | `flutter gen-l10n` 后三档生成物与 arb 一致，且 `generalSettingsEditorContext`（自有）与 `generalSettingsSessionTools` / `generalSettingsCommandLine`（上游新）三类键都在生成物里 |
| ⑥ | `flutter test test/update/version_test.dart` 绿；`lib/update/version.dart` 与 `pubspec.yaml` 均 `1.9.6+32` |
| ⑦ | 定向用例绿：`flutter test test/chat/composer_files_test.dart test/chat/remote_drops_test.dart test/chat/composer_input_lag_test.dart test/chat/composer_draft_sync_test.dart test/chat/chat_keys_test.dart test/composer_test.dart test/chat/session_overlay_test.dart test/bots/bots_test.dart test/chat/side_panel/file_open_test.dart test/kernel_test.dart test/models/models_test.dart` |

### 用例表

| 场景 | 输入 | 期望 |
|---|---|---|
| 正常 | 12 块按上表解完 | ① ② ③ 全绿 |
| 边界 | `general_page.dart` 块 1 的注释（纯文字） | `flutter analyze` 无悬空文档标记，措辞含上游新键名与 `thincoder.path` |
| 边界 | 判据域内某档 numstat 非零而 §3 无行 | 停止实施，先补登记行（`docs/design/fork-deltas.md` §1 第 1 条） |
| 错误 | 某块取上游体、丢自有语义 | ③ 的对应读数缺失 ⇒ 判失败，回块重解 |

### 关键决策

| 选项 | 内容 | 结论与理由 |
|---|---|---|
| A（采用） | 冲突全部按登记面解：自有块保留，上游新体折进 `…Of` 助手，块外取上游 | 与 §1 已定决定一致；守住 `docs/design/fork-deltas.md` §1 的目标（共享档可优先合并，自有语义存活在登记块内） |
| B（否） | `composer.dart` 三块取上游体（放弃委托） | 等于拆掉 `docs/design/structure-splits.md` §4.3 的拆分形态，档变常驻冲突面；上游体进本档，下次同处再冲突 |
| C（否） | `_copyToHostOf` 保留手写计时器进度体 | 手写体是旧上游的复制，缺取消与失败通知；块外语义跟上游，不自建第二套 |
| D（否） | `ide_workspace.dart` 取上游、删我方两行 | `openWorkspaces` 由 `lib/ide/ide_kernel_files.dart:35` 消费；删了就编译失败或运行期拿不到工作区清单。先把块登记上 |

### 边界（不做）

- 不改上游新增功能的行为（会话工具、bash.exe、图片上限 100、设置转移、上传下载进度等）。
- 不拆大档、不动 `docs/design/structure-splits.md` 的拆分落点。
- 不重写 `README*` / `docs/release.md` / 发布脚本。
- 不修前批遗留的失败用例（`fold_view_test` 那条）。

### UI / 交互

设置 → 通用页并存五组：上游 `chat.sessionTools`、Bash（Windows）、`chat.liveTurnStats`，与本仓 thincoder 路径组、`chat.editorContext`。文案各走各的 l10n 键，不合并；`chat.liveTurnStats` 是上游改名，本仓不另立旧键。无 `open` 项。

### 集成测试设计（RTM delta）

读了 `test/RTM.md`（9 个业务故事、13 行用例）。本批是合并面：冲突全是「同一处两侧各写一块」的并存冲突，不改任何 RTM 行断言的行为。

- 被破坏的行：无 —— 切会话 / 失焦重建 / 流式折叠 / btest / SSH / 模型账号 / magpie 的断言面都不落在 12 块上。
- 冗余可删的行：无。
- 缺失需新增的行：无 —— 上游能力不是本仓新长出的业务故事，也无生产报告；两条入口都不成立。

⇒ 收口报 `none`。

### 上抛项

无。`ide_workspace.dart` 此前表外，属本设计写域内的一致性处置（补登记行），已按 §3.1 落地。

### 实施后补记（登记面 · 2026-11-15）

合后 numstat 对账（验收 ④）报出一条：判据域内五档非零、无登记行；另两处既有行需更正。全部落在 `docs/design/fork-deltas.md` §3，读数一律取合后 `git diff --numstat origin/main HEAD`。

| # | 档 | 合后读数 | 落地形态（§3 该行） |
|---|---|---|---|
| 1 | `lib/kernel/claude_code/claude_code_translator.dart` | +2 / −1 | `HostTools.called` / `HostTool` 换符 + 自有 import；首次登记（此前表外） |
| 2 | `lib/window/app_windows.dart` | +28 / −10 | `requestClose` / `_remove` 的一次性守卫；首次登记 |
| 3 | `test/forge/forge_test.dart` | +2 / −2 | 两条断言按 `ForgeRef.key` 写（上游写 `number`）；首次登记 |
| 4 | `test/window/app_windows_test.dart` | +20 / 0 | 上述守卫的用例；首次登记 |
| 5 | `test/workspace_test.dart` | +93 / −9 | `_DirectoryCatalog` 与按目录列会话的用例组（机制归 `docs/design/thincoder-adapter.md` §14-11）；首次登记 |

另两处更正：

- `lib/ide/ide_workspace.dart` 行补全——原行只覆盖 6 行（`openWorkspaces` 三处 + 构造期 `_detectIn` 一行），其余 7 行是 `IdeWorkspace.documentOf`（消费方 `lib/ide/ide_kernel_files.dart` 三处，用例 `test/ide/ide_kernel_files_test.dart`、`test/kernel/thincoder_kernel_test.dart`）。同一行记下构造体 `_detectIn(root)` 一行为空转：本批照块 11 保留，删行归下一次清理。
- `test/chat/side_panel/file_open_test.dart` 行按合后形态改写——`p.normalize` 6 处 / `p.join` 3 处，读数 +22 / −19（原行记的 `p.normalize` 3 / `p.join` 1 与 +10 / −13 是合前形态）。

§3.1 的先例清单补一行，使表外补登记的清点与本批的六行一致（读数只在 §3 各行，不复制）。

实施面另改一档 `test/chat/side_panel/file_open_test.dart`，不在本文「受影响文件与测试覆盖」表内（设计面遗漏，见 §1 末段与 §5.2）：本批不动该表，该档的登记行已按合后形态落。

本修轮范围：只写 `docs/design/fork-deltas.md` 与本节；不改产品代码、不动工作树、不跑测试。

## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

设计评审轮次结论（对象 = 批档 §2 与 `docs/design/fork-deltas.md` §3 新增/更新行）。

评审口径：
- 无 AGENTS.md、无项目标准档、无文档地图 ⇒ 方法学按判据本身判；文档归属按「改动是否落在拥有该主题的既有档」判。
- tier 抽检受评审范围约束（只读两份文档），未做新的 `wc -l` 实测，读数取文档自记值。
- `lib/workbench.dart` 5408、`lib/chat/chat_session.dart` 1401 取自 `docs/design/fork-deltas.md` §8.5 表。
- `composer.dart` 744 取自同档 §3.1 的存量债段。
- 用例档在盘情况按路径实测：`test/chat/remote_drops_test.dart`、`test/chat/chat_keys_test.dart`、`test/chat/composer_files_test.dart`、`test/composer_test.dart` 均在盘。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Document ownership | 🔴 | 块 7 的计时器位置两处写法互斥。`docs/batches/2026-11-15-upstream-sync-6.md` §2 写「故计时器留壳上、体进助手」，壳停在 `composer.dart`；`docs/design/fork-deltas.md` §3 的 `lib/chat/composer/composer.dart` 行写「`_handleEditorChanged` 的 `_lag.time('edit', …)` 与重写后的编辑体进 `_handleEditorChangedOf`」，即进 `lib/chat/composer/composer_editing.dart`。两条都是本轮交付的改后形态，读者无法判定哪条为准；验收 ③ 只数 `_handleEditorChangedOf(this` = 1，两种解法都过。 | 把该行的 `_lag.time('edit', …)` 落到与 §2 同一锚点：计时器在 `composer.dart` 的壳、体在 `_handleEditorChangedOf`。验收 ③ 加位置读数（`composer_editing.dart` 内 `_lag.time('edit'` = 0、`composer.dart` 内 = 1）。 |
| 2 | Document ownership | 🟡 | `userSent?.call()` 的落点两处措辞不一致。§2 块 12 写「在空消息早退之后补上游 `if (from != null) userSent?.call();`」；fork-deltas 同行写「落在 `send()` 开头，在 `_overlay.beforeSend` 之前」。若空消息早退是 `send()` 首句，两条不能同时成立，空消息是否触发上游计数钩因此不可判。验收 ③ 只数次数 = 1，两种落点都过。 | 该行措辞改用 §2 的同一锚点（空消息早退之后、`_overlay.beforeSend` 之前）；或写明两种落点的行为差异，并在验收 ③ 补一条位置读数。 |
| 3 | Affected-file tier check | 🟡 | 「零跨档」与本批自己点名三档的读数不一致。`docs/design/fork-deltas.md` §8.5 记 `lib/workbench.dart` 5408、`lib/chat/chat_session.dart` 1401，两档在受影响文件表内且过 800；§3.1 记 `lib/chat/composer/composer.dart` 现 744 行，过 500。结论行既不点名，也不引既有裁定（§3.1「认账不排期」、§8.5「属存量债，不拆档」）。 | 结论行改成：本批无文件因本节改写跨档；表内 `lib/workbench.dart`、`lib/chat/chat_session.dart` 属 §3.1 / §8.5 已裁定的存量债，本批不动拆分；`composer.dart` 的拆分机制（structure-splits §4.3）即其拆分状态。 |
| 4 | Closest precedent | 🟡 | 批档 §2 无「最近先例」行，无先例坐标、无对齐 / 偏离理由。先例材料只在 `docs/design/fork-deltas.md` §3.1 的「最近先例」段，未与本批对位；块 7 的偏离理由写在「块 7 的依据」，不是一条先例行。 | §2 加一行：最近先例 = §3.1 的四条表外补登记（2026-11-05 `step_folds` / `sidebar`、2026-11-08 `secret_store_io` / `workbench_keybindings`）与第 7 / 8 节同形；本批 `ide_workspace.dart` 同一形，块 7 的偏离见「块 7 的依据」。 |
| 5 | Survey evidence | 🟡 | 批档 §2 无「调查证据」行。仅 fork-deltas §3.1 有存量一行：`manifest.index.publicRepos` 为空、无独立文档仓、查过无外部相关来源；未声明是否沿用到本批。 | §2 加一行调查证据：写明查过哪些公开来源、`PROJECT-MANIFEST.json` 的 `publicRepos` 读数为空、结论。沿用 §3.1 就写「沿用 §3.1」。 |
| 6 | Acceptance | 🟡 | §2「测试覆盖」声明五个上游触碰用例档，含 `test/chat/side_panel/side_panel_test.dart` 与 `test/models/models_test.dart`；验收 ⑦ 的命令串里两者都不在。声明与判据不一致，按 ⑦ 执行会漏跑两档。 | ⑦ 补齐这两档；或把「测试覆盖」改成「两档作可选回归，不进本批判据」。两处对齐其中一处。 |
| 7 | Acceptance | 🟡 | 块 6–8 改的是 composer 面，用例集却缺两档。一为 `test/chat/composer_files_test.dart`，§1 修轮清单把块 6 · 复制到主机点给该档；二为 `test/composer_test.dart`，fork-deltas 的 `test/composer_test.dart` 行记着 Shift+Tab 跳过 btest 的期望，而块 8 换的正是 `lib/chat/composer/composer_menu.dart` 的 `_handleKeyOf`。两档在盘，未说明为何不跑。 | 两档加进 ⑦ 与「测试覆盖」；若判定不相关，写出理由（例如 `_handleKeyOf` 不经 `_nextModeOf`），让判断可复核。 |
| 8 | Clarity / Feasibility | 🟡 | 新增行记「对 `origin/main` 实测 +21 / −25」，验收 ④ 又要求合后读数「与新行一致」，但没写读数读自哪棵树 / 哪条命令。§1 记当前树停在冲突态、工作树带冲突标记；冲突标记树上读 numstat 得到的数与合后不同，④ 的等值判据可能落在无来源的基准上。 | 写明读数来源（例如 `origin/main` 对合前本地 `8d80c089` 的 `git diff --numstat`）；把 ④ 写成「合后读数 = 该来源读数」，或合后重读并同步该行。 |
| 9 | Reference form | 🟡 | 定位写成行号。§2 用 `lib/chat/composer/composer_editing.dart` 的 `:230`、`lib/chat/composer/composer_menu.dart` 的 `:167`、`lib/ide/ide_kernel_files.dart` 的 `:35`；新增的 `lib/ide/ide_workspace.dart` 行用 `:217` / `:246` / `:247` / `:1377` / `:296` / `:304`。本批自身会插删行，坐标落地当轮即漂移；fork-deltas §1 与 §5 也写「不以旧行号判断接线是否仍在」「行号只作定位参考」。 | 改成符号锚：`IdeWorkspace.openWorkspaces` 的声明 / 构造登记 / `dispose` 注销三处、构造体内 `_detectIn(root)` 那一行、`_detectIn` 的两处调用、`ChatKeys.dispatch` 与 `_copyToHost` 的调用点。行号若要留只作括注。 |
| 10 | Clarity | 🔵 | 块 1 把 `telemetry` 句留成条件：「`telemetry` 句按上游是否仍有该键判」。用例表边界行只判「措辞含上游新键名与 `thincoder.path`」，不覆盖这句的结论。 | §2 写明判定结果（保留 / 删）与依据（上游该键在 / 不在）；或在用例表边界行补一条该句的可判读数。 |
| 11 | Method | 🔵 | 「设计档落点」把「对 `origin/main` 实测 +21 / −25」写进设计档。行数与预期增量按判据只该进登记行，设计档留结论。 | 设计档留一句「首次登记，实测值见该行」，数字只在 `docs/design/fork-deltas.md` §3 该行。 |
| 12 | Acceptance | 🔵 | 验收 ③ 的 ≥ 计数用裸子串：`general_page.dart` 内 `bash` ≥ 3、`thincoderStatus` ≥ 4 等。注释与邻近标识符即可满足，块 1 的注释改写本身就被计进 `bash`。 | 改成符号锚计数：`this.bash` / 字段声明 / `bash:` 传参各 = 1。或给每条读数标出它证明的那一处。 |

核对通过的面（不列问题）：
- 条目 1–6 覆盖 §1 的三条已定决定：登记面处置、l10n 键级并集 + 重产、构建替换。
- 12 块与 §1 的「6 档 / 12 块」逐块对得上。
- 受影响文件表含两块助手档：`composer_editing.dart` / `composer_menu.dart`。
- 验收 ① 已去掉路径参数、改全仓扫描；⑦ 已换掉不存在的 `test/chat/composer_test.dart`。
- ⑥ 版本两档同值，可判。
- 集成测试设计节从 `test/RTM.md` 起，报 none 的理由属唯一成立的那一条。
- l10n 生成物按 arb 行承载，与 §3.1 对账口径一致。
- 五条既有登记行的改后形态与 §2 的块 2 / 3 / 4 / 5 / 9 / 10 / 11 / 12 处置一致；块 7 见第 1 条。

计数：🔴 1 · 🟡 8 · 🔵 3。

VERDICT: changes-required

### 轮次 2（评审子代理）

设计评审轮次 2（对象 = 批档 §2 与 `docs/design/fork-deltas.md` §3 新增/更新行）。

范围：只核轮 1 的 12 条（1🔴 · 8🟡 · 3🔵）落地，两份文档本轮全读。

结论：12 条全部落地（Fixed），无新增 🔴；新增 1 条 🔵 = 第 9 条的残留一处。

| # | Orig# | Severity | Status | Notes |
|---|---|---|---|---|
| 1 | 1 | 🔴 | Fixed | fork-deltas 的 `composer.dart` 行已改「`_handleEditorChanged` 的计时器留壳」，并写「`_lag.time('edit'` 只在 `composer.dart`」；批档「故计时器留壳上、体进助手」同锚；验收 ③ 补「`_lag.time('edit'` = 0（计时器在壳上）」。 |
| 2 | 2 | 🟡 | Fixed | 该行改为「落在空消息早退 `if (message.isEmpty || !canSend) return;` 之后、`_overlay.beforeSend(` 之前（空消息不计数，与上游同）」；③ 加「= 1 且位于 … 之后」位置读数。 |
| 3 | 3 | 🟡 | Fixed | 结论行改「**tier 结论**：零跨档——本批无文件因本节改写跨档」；另段「表内两档是已被裁定的存量债，本批不动拆分：」，点名 `lib/workbench.dart` 与 `lib/chat/chat_session.dart` 引 §8.5 体量立场，`composer.dart` 写明拆分机制即拆分状态。 |
| 4 | 4 | 🟡 | Fixed | 新增「**最近先例**：`docs/design/fork-deltas.md` §3.1 记的四条表外补登记与第 7 / 8 节同一形」，列四条坐标，并写「偏离：块 7 的计时器留壳（不搬进助手），理由见下「块 7 的依据」」。 |
| 5 | 5 | 🟡 | Fixed | 新增「**调查证据**：本轮查过 `docs/design/fork-deltas.md` 全档、本批批档 §1、`PROJECT-MANIFEST.json`」，写 `"publicRepos":[]` 读数与「结论：无外部相关来源，沿用 `docs/design/fork-deltas.md` §3.1 的调查证据口径。」 |
| 6 | 6 | 🟡 | Fixed | ⑦ 已补 `test/models/models_test.dart`；`test/chat/side_panel/side_panel_test.dart` 改写「不进 ⑦，作可选回归：」，理由两条（§4 冻结面、Windows 路径族红 台账 #216）。 |
| 7 | 7 | 🟡 | Fixed | 测试覆盖与 ⑦ 均补 `test/chat/composer_files_test.dart`（块 6 · 调用点 `state._copyToHost(`）与 `test/composer_test.dart`（块 8 · Shift+Tab 链到 `_nextModeOf` 所在助手档）。 |
| 8 | 8 | 🟡 | Fixed | 新增行写「（来源 = `git diff --numstat origin/main 8d80c089`，合前本地树对上游 tip）」；④ 写明不等属口径差，且「块是否存活不按此数判，按 ③ 的 `openWorkspaces.add(this)` = 1 判」。 |
| 9 | 9 | 🟡 | Fixed | 块 11 改「锚点是符号：`IdeWorkspace.openWorkspaces` 的静态声明 / 构造登记 / `dispose` 注销」；`composer_editing.dart` 的 `:230`、`composer_menu.dart` 的 `:167`、新行的 `:217` / `:246` / `:247` / `:1377` / `:296` / `:304` 均已换符号锚。残留见第 13 条。 |
| 10 | 10 | 🔵 | Fixed | 块 1 已定「`telemetry` 句**删**——上游 `origin/main` 该档类注释已无该键」，并给 `git show origin/main:…` 的实测依据。 |
| 11 | 11 | 🔵 | Fixed | 设计档落点改为「新增 `lib/ide/ide_workspace.dart` 行（表外首次登记，实测值见该行）」，数字只在 §3 该行。 |
| 12 | 12 | 🔵 | Fixed | ③ 改「逐块静态读数（符号锚：每条只数它证明的那一处，不数注释与邻近标识符）」，裸 `bash` / `thincoderStatus` 计数换成「`this.bash,` = 1 · `final BaoBash? bash;` = 1」等。 |
| 13 | (new) | 🔵 | New: 残留行号 | 关键决策 D 仍写「`openWorkspaces` 由 `lib/ide/ide_kernel_files.dart:35` 消费」；第 9 条要求行号只作括注，此处仍是 `path:line` 形态，改符号锚即可。 |

计数：🔴 0 · 🟡 0 · 🔵 1（旧项 12 条全部 Fixed）。

VERDICT: pass

## §4 用户批准（主 agent）

**状态行**：已批准

- 用户 2026-11-15「拉代码更新」= 本批整批授权：合上游 → 解冲突 → 出构建（替换运行实例）。
- 评审两轮：轮 1 changes-required（1🔴 / 8🟡 / 3🔵）→ 12 条全修 → 轮 2 pass（0🔴 / 0🟡 / 1🔵）。
- 轮 2 的 1 条 🔵（`关键决策 D` 里残留 `lib/ide/ide_kernel_files.dart:35` 的行号写法）记 §6，本批不改判据。
- 实施面 = 6 档 12 块 + l10n 键级并集与重产；派 eng-coder 按 §2 处置表执行。

## §5 实施记录（eng-coder）
**状态行**：实施完成



### 5.1 交付面与提交

- 合并提交 `137724e8`（父 = `8d80c089` 本地 + `1987ad78` 上游 tip），`lib/` 与 `test/` 的 12 块按 §2「逐档处置表」解完；6 档冲突清零。
- 该提交另带三样非冲突内容：`docs/mobile-link.md` / `docs/ssh-remote.md`（上游本批自带的文档改动，随合并）、`docs/design/fork-deltas.md`（设计席的登记面更新）、批档 §1–§4（当时状态）。后两者被带进来是因为 `git commit` 未带路径参数时按 `git add -A` 收全部改动；内容本身是批准过的形态，只记在这里，不另回退。
- l10n：两个 arb 自动合并后 `flutter gen-l10n` 连跑两遍，三档生成物 md5 三遍同值（`app_localizations.dart` / `_en.dart` / `_zh.dart` 各 OK）⇒ 生成物与 arb 一致，未手改。
- 版本：`pubspec.yaml` 与 `lib/update/version.dart` 均 `1.9.6+32`（自动合并结果，未手改）。

### 5.2 表外改动一档：`test/chat/side_panel/file_open_test.dart`

两处修改：一处是本批引入的红，一处是合前既有红。

- 本批引入：上游 1.9.6 新加 `group('a folder')`，用 `const folder = '$_root/lib/chat'` 复用我方 `final _root`（该档是我方「按宿主拼写改断言」的已登记档）⇒ `flutter analyze` 2 error（`const_initialized_with_non_constant_value`）。
- 合前既有：`another machine's file` 两条在合前基线上就是红的（`8d80c089` 的 worktree 跑该档 = 9 passed / 2 failed），按该档已登记的「按宿主拼写改断言」口径收口。

两处都在该档已登记的接缝内：

| # | 位置 | 改法 |
|---|---|---|
| 1 | `group('a folder')` 的 `folder` / `makefile` | `const` 改 `final`，值改宿主拼写：`p.join(_root, 'lib', 'chat')` / `p.join(_root, 'Makefile')` |
| 2 | `group('another machine's file')` 的两条用例 | 期望值按宿主拼写：`p.normalize(onHost)` / `p.normalize('/nowhere/c.md')`；`local:` 链接的 href 用 `/` 拼写的 `_readHref`（`parseHref` 只认 `/` 起的绝对路径） |

断言条数与强度不变（无 `skip`、无放宽成 `contains`）。该档合后 `git diff --numstat origin/main HEAD` = **+22 / −19**；§3 该行记的合前实测是 +10 / −13，差额即上游新分组（+12 / −6）。

### 5.3 逐块处置与读回（12 块）

| # | 档 · 块 | 处置 | 读回 |
|---|---|---|---|
| 1 | `general_page.dart` · 类注释 | 取上游新措辞（`chat.liveTurnStats`、BaoCode Bash），句末补 `thincoder.path`，`telemetry` 句删 | 无悬空文档标记；`flutter analyze` 该档 0 issue |
| 2 | `general_page.dart` · 构造参数 | 两个都留 | `this.thincoderStatus,` = 1 · `this.bash,` = 1 |
| 3 | `general_page.dart` · 字段 | 两个字段带各自文档注释 | `final Future<ThincoderStatus> Function()? thincoderStatus;` = 1 · `final BaoBash? bash;` = 1 |
| 4 | `general_page.dart` · 开关行 | 两行都留 | `EditorContextSetting.enabled(` = 1 · `SessionToolsSetting.enabled(` = 1 |
| 5 | `general_page.dart` · 设置组 | 两组都留 | `BaoBashSetting(bash: bash)` = 1 |
| 6 | `composer.dart` · `_copyToHost` | 留薄壳，上游体进助手 | `=> _copyToHostOf(this, files)` = 1 · 助手内 `withTransferProgress` = 1 |
| 7 | `composer.dart` · `_handleEditorChanged` | 壳带计时器，体进助手 | `=> _handleEditorChangedOf(this)` = 1（同行含 `_lag.time('edit'`）· `composer_editing.dart` 内 `_lag.time('edit'` = 0 · `state._lag.time('draft'` = 1 |
| 8 | `composer.dart` · `_handleKey` | 留薄壳，上游体进助手 | `=> _handleKeyOf(this, event)` = 1 · `composer_menu.dart` 内 `state._lag.begin('key')` = 1 |
| 9 | `app_settings.dart` · 页面构造 | 两个都传 | `thincoderStatus: thincoderStatus,` = 1 · `bash: bash,` = 1 |
| 10 | `workbench.dart` · `dispose` | 两行都留 | `_sidePanelRetryTimer?.cancel()` = 2（dispose + 扫描失败路径）· `_reloadedElsewhere` = 7 |
| 11 | `ide_workspace.dart` · 构造体 | 我方两行保留 | `static final Set<IdeWorkspace> openWorkspaces` = 1 · `openWorkspaces.add(this)` = 1 · `openWorkspaces.remove(` = 1 |
| 12 | `chat_session.dart` · `send()` | 我方结构 + 上游 `userSent` | `_overlay.beforeSend(` = 1 · `if (from != null) userSent?.call();` = 1，位于 `if (message.isEmpty || !canSend) return;` 之后 · `final takesContext = acceptsEditorContext;` = 1 · `if (!takesContext && editor != null)` = 1 |

### 5.4 测试读数：合前基线 vs 合后

- 合前基线（`8d80c089` 的临时 worktree，`flutter test --no-pub test/kernel_test.dart test/composer_test.dart`）= **189 passed / 6 failed / 8 skipped**。
- 合后（本机，§2 验收 ⑦ 的 11 档一条命令）= **374 passed / 6 failed / 8 skipped**，失败集与基线逐条相同。

| 失败用例 | 归因 |
|---|---|
| `kernel_test` · `claude locator BAOCODE_CLAUDE_PATH…` | 用例只造 `/bin/claude` 与 `/` 拼写，无 `.exe`；Windows 上定位器找不到 ⇒ `Claude Code is not installed`。上游原有的 POSIX-only 用例 |
| `kernel_test` · `Volta's shim…` | 期望值 `'${root.path}/Volta'` 用 `/` 拼，实际 `\`。Windows 拼写族 |
| `kernel_test` · `Claude Code storage` · `a session file is read again only once it changes, and the cache keeps only the files still there` | 同上，`config/projects/-p/x.jsonl` 与 `config\projects\-p/x.jsonl` 口径差 |
| `kernel_test` · `Claude Code storage` · `a fork copies the conversation up to a message, apart` | 同上 |
| `kernel_test` · `Claude Code storage` · `a folder's sessions move to another's, with what is kept beside them and its memory; a folder dashed alike keeps its own` | 同上 |
| `composer_test` · `an edit stays open while another conversation is visited from the sidebar` | Flutter semantics-tree 检查抛 4 次（`Node N is not in the tree…`），非断言失败；框架版本相关 |

- `test/chat/side_panel/file_open_test.dart`：合前基线（同一 worktree、同一口径）**9 passed / 2 failed**，合后 **11/11 绿**（本批比合前少 2 条既有红）。两次读数同一 `flutter test` 口径，⑦ 取「同一失败集、无新增失败」（父代理 2026-11-15 裁决，见 §1）。
- 两侧命令的文件集不同（合前 2 档、合后 11 档），可比的是失败集与 skipped 数；pass 数不可相减——多出的 9 档合后 0 失败。

### 5.5 numstat 对账（验收 ④）

- 判据域 = `git diff --name-only 5f4a1d50 origin/main` = **189 档**。
- `git diff --numstat origin/main HEAD` 域内非零 **30 行**：**22** 行命中 §2 / §3 登记行；**3** 行为 l10n 生成物，按 `docs/design/fork-deltas.md` §3.1 由 arb 行承载；**5** 行无登记行（表外，见 5.6）。
- `lib/ide/ide_workspace.dart` 合后 `git diff --numstat origin/main HEAD` = **+13 / −0**；§3 该行记的 +21 / −25 是合前本地树对上游 tip 的口径（`git diff --numstat origin/main 8d80c089`），两者不等属口径差。块存活按符号判：`openWorkspaces.add(this)` = 1（见 5.3 第 11 块）。

### 5.6 偏差与上抛面

- **验收 ⑦ 的字面「全绿」本机不可达**：6 条失败为合前既有，见 5.4。按父代理裁决以「无新增失败」判；未改上游 `test/kernel_test.dart` / `test/composer_test.dart`（加 Windows skip 会新增常驻 fork 差异）。
- **5 条表外非零行，需设计席补 §3 登记行**（我不动设计档）：
  - `lib/kernel/claude_code/claude_code_translator.dart` +2 / −1：`HostTools.called` + `HostTool` 换符。
  - `lib/window/app_windows.dart` +28 / −10：`requestClose` / `_remove` 的一次性守卫。
  - `test/forge/forge_test.dart` +2 / −2：`issue.number` → `issue.key` 两条断言。
  - `test/window/app_windows_test.dart` +20 / −0：上述守卫的用例。
  - `test/workspace_test.dart` +93 / −9：`_DirectoryCatalog` 与按目录列会话的用例组。
- **`lib/ide/ide_workspace.dart` 登记行不完整**：合后 13 行里，§3 该行只覆盖 `openWorkspaces` 三处 + 构造期 `_detectIn` 一行（6 行）；其余 7 行为 `IdeWorkspace.documentOf`（消费方 `lib/ide/ide_kernel_files.dart` 三处，用例 `test/ide/ide_kernel_files_test.dart`、`test/kernel/thincoder_kernel_test.dart`），需补进该行。

依据 `docs/design/fork-deltas.md`「非零行 = 必须有本节的登记行」，以及 `docs/design/fork-deltas.md`「表外不许改上游档」——5.6 的 6 项即按这两条报出，不自行补表。

### 5.7 单测与集成测试面

- 本批无新增单测档；改动面的读数即 5.4 的 ⑥ / ⑦ 两条命令。
- 集成面按 §2 的 RTM delta 报 **none**：12 块不改任何 RTM 行断言的行为，上游能力不是本仓新长出的业务故事，也无生产报告。

### 5.8 审计轮、代码评审轮与终态

- 内部审计（explore，只读，对 §2 逐条）：12 块逐块判为与 §2 一致；计 1🔴 + 2🟡 + 2🔵。🔴 = 5 条表外登记行（同 5.6，设计席补表）；🟡 = `ide_workspace.dart` 行不完整（同 5.6）+ `file_open_test.dart` 行措辞仍是合前形态（见下条）；🔵 = 块 8 守卫疑点（核为上游原文，非偏离）+ 临时诊断件（已删，见末条）。
- `test/chat/side_panel/file_open_test.dart` 的 §3 行与合后形态不符：该行写「`p.normalize`（档内 3 处）」「`p.join`（1 处）」，合后实测 `p.normalize(` 6 处、`p.join(` 3 处；差的三处正是 5.2 第 2 项。需设计席把该行更新成合后形态。
- 块 8 的守卫不是简化：`git show origin/main:lib/chat/composer/composer.dart` 的 `KeyEventResult _handleKey` 首行即 `if (event is! KeyUpEvent) _lag.begin('key');`，与合入形态逐字同。
- 内部代码评审（advisor，type=code，对象 = 9 档 + 本批档与登记表）：0🔴；🟡 1 条 = 登记面协调项（同 5.6）；🔵 2 条（见下两条）。代码面终态 clean，登记面待设计席。
- 🔵 之一（已核，不改）：`lib/ide/ide_workspace.dart` 构造体的 `if (_gitOf == null && _git != null && hasFolder) _detectIn(root);` 是空转。`_setRoots(roots);` 就在它上一行，而 `origin/main` 的 `_setRoots` 在 `!isMultiRoot` 分支已有 `if (_git != null && hasFolder) _detectIn(root);`；`_gitOf == null` 时 `isMultiRoot` 恒假，故该行对任何输入都不改行为，`_detectIn` 自身也按 `_found.containsKey(folder)` 早退。§2 块 11 明写保留这一行，本批照设计保留；删行与改 §3 措辞归设计席。
- 🔵 之二（已修）：5.4 原把 3 条 storage 失败压成一行、且两侧命令的文件集不同未注明；现已逐条列名并补注。
- 临时件：`test/chat/side_panel/_tmp_probe_test.dart`（诊断 `p.join` 的拼写）创建后删除，`git status` 无残留，不进交付。

## §6 验证与收口（父代理）

**状态行**：已收口 2026-11-15

- **合并形态**：`137724e8`，第一父 `8d80c089`、第二父 `1987ad78`；上游 111 个提交（1.9.5 → 1.9.6）、189 档；未解冲突 0；全仓 `^<<<<<<<` / `^>>>>>>>` 扫描无输出。
- **冲突处置**：6 档 12 块按 §2 逐块解开——自有块保留、上游新体折进 `…Of` 助手（`composer_editing.dart` / `composer_menu.dart`）、块外取上游。
- **l10n**：两档 arb 键级并集后 `flutter gen-l10n` 重产三档生成物，连跑两遍 md5 同值；`generalSettingsEditorContext`（自有）与 `generalSettingsSessionTools` / `generalSettingsCommandLine`（上游新）都在生成物里。
- **登记面**：`docs/design/fork-deltas.md` §3 新增 5 行首次登记（`claude_code_translator` +2/−1 · `app_windows` +28/−10 · `forge_test` +2/−2 · `app_windows_test` +20/0 · `workspace_test` +93/−9），补全 `ide_workspace.dart` 行的 `documentOf` 段，按合后改写 `file_open_test.dart` 行；§3.1 先例清单补 2026-11-15 一条。
- **静态检查**：`flutter analyze --no-pub` = error 0；11 issues（2 warning + 9 info）与合前基线同组。
- **实跑（⑦ 按「与合前基线同一失败集」判，裁决见 §1）**：解冲突后 374 passed / 6 failed / 8 skipped；基线 `8d80c089` 同批用例 189 passed / 6 failed / 8 skipped，失败集逐条相同（`kernel_test` 5 条为 Windows 路径拼写 / 仅 POSIX 夹具，`composer_test` 1 条为 semantics-tree 检查抛错）。**新增失败 = 0**。
- **集成门（父侧收口门）**：`test/integration/chat_flows_test.dart` + `btest_flows_test.dart` = **6 过 / 0 挂**。
- **构建**：`dart run tool/build_windows.dart --patched-engine --remote-built`，303.2 s。`data/app.so` = 2026-11-15 20:35；安装器 `BaoCode-1.9.6-setup.exe`（46.8 MB）；远程 server `1.8.1.26-336401b2e048` 双产物；`pubspec.yaml` = `1.9.6+32`。
- **实例替换**：旧 Debug 实例（PID 16824）连树杀掉，遗孤 browser-host 已清；新实例 **PID 23708**（20:38:52 启动，窗口 `BaoCode`，跑 Release 1.9.6）。
- **已知状态（三条）**：① §5.5 仍写「§3 该行记的 `+21 / −25` 是合前本地树对上游 tip 的口径」，该数已被 §3 行的合后口径 `+13 / 0` 取代——以 §3 行为准，§5 是实施席的段，本席不改。② `ide_workspace.dart` 构造体的 `_detectIn(root)` 一行经核为空转，本批照设计保留，删行归下一次清理。③ `test/chat/side_panel/file_open_test.dart` 的逻辑属主仓面、在 §3 有登记行；§2 受影响文件表漏收该档，属设计面遗漏，已在登记行内写明改法。
- **集成索引**：`test/RTM.md` 9 个业务故事 / 13 行用例；本批 delta = none（上游能力不是本仓新长出的业务故事，无生产报告）。
- **用户面同步**：并入的上游界面（会话工具、项目加文件夹、每条消息 100 图、BaoCode Bash、设置转移、终端 `code`）都是上游实现，本仓零改写。
- **暂缓批复核**：无。
- **doc-check gate**：PASS（本批档 + `docs/design/fork-deltas.md`）。
- **台账**：`#242`（本批）随收口核销。
