# 2026-10-17 · ide-stability-guards
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-17 · 来源 = 用户 2026-10-17 21:30「批」= 批准 A 批开工；输入 = 体检报告（docs/batches/2026-10-17-ide-health-audit.md §1 S 表七条）。
> 台账 = #43（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-17
> 本批为**轻渠道轮**（缺陷修）：实现 = 父代理直改（逐笔披露在下方）；无 §2 设计档 / §3 设计评审 / §5 eng-coder 段；评审 = 两轮代码评审（结论见 §6）。

## 讨论与定界（2026-10-17 · 轻渠道轮）

### 轮的性质

**轻渠道轮**（缺陷修：实现与既有来源矛盾——代码注释写了"A 窗口不是活动窗口就退出"却没做；设计档写"release ⇒ close"而实现是延后）。七条都是**守卫补丁**，无新机制、无新语义、不改结构 ⇒ 不走「设计→评审→批准」链，逐笔编辑 + 现场走查，收尾跑一次完整链（形式化设计 · 独立评审 · 批准 · 结算）。

### 七笔（体检 S 表）

| 笔 | 位置 | 缺陷 | 判据（修好后） |
|---|---|---|---|
| P1 | `app_windows.dart:903/:1048` | `_remove` 在 `await leaveFullScreen` 后才摘除 ⇒ 重入同一关闭（重复 `host.close` / `_save` / `_quitIfNoneShows`） | 同一窗口的 `_remove` 并发调用只执行一次副作用 |
| P2 | `ide_workbench.dart:2878/:2898` | chord 等待态只判应用级生命周期 ⇒ 在别的窗口打字会执行本窗口命令 | 非活动窗口的 chord 前缀不接管按键 |
| P3 | `workbench.dart:3349/:3360/:3378` | 扫描失败被吞且缓存置空 ⇒ 整场会话不再重试，用户只见"没有仓库" | 失败后下一次请求会重试，并有一条可见提示 |
| P4 | `thincoder_kernel.dart:988/:999` | 释放后 `_connection!` 空断言（`unawaited` 里 ⇒ UI 只表现"点了没反应"） | 释放后点模型/模式不抛异常，静默返回 |
| P5 | `ide_editor.dart:2106/:2118/:2227` | `_surface()` 与 diff `modified` 回调绕过 null 守卫 | 文档关闭后 diff 重建不崩 |
| P6 | `terminal_view.dart:643` · `terminal_panel.dart:410` | 菜单回调 `findRenderObject()!` 强转 | 目标滚出视口/被移除时不崩、不弹错位菜单 |
| P7 | `chat_session.dart:158` | `_apply` 无 `_disposed` 守卫却 `notifyListeners()` | dispose 后到达的事件不通知 |

### 约束

- **只补守卫**：不改行为语义、不重构、不动结构（那是 C/D/E 批）。
- 每笔必须带一条**可复现的判据**（单测优先；不能单测的走现场走查并在 §6 记读数）。
- 每笔披露：轻渠道 · 改动 · 波及 · 可 revert。

## 逐笔记录（轻渠道 · 父代理直改，可 revert）

> 每笔：披露 · 改动 · 波及 · 判据。

**P1 · 窗口关两次** — 披露：轻渠道（缺陷修：`_remove` 未防重入，与 `requestClose` 的 `_closing` 纪律不一致）。改动：`lib/window/app_windows.dart` 新增 `_removing` 在途集合 + 包一层 `_remove`，原体改名 `_removeOnce`（零重排）。波及：`_agentsChanged` / `requestClose` 两条调用路径。判据：既有 `test/window/app_windows_test.dart` **70/70 通过**。

**P2 · 跨窗 chord** — 披露：轻渠道（缺陷修：注释写「窗口不是活动窗口就退出」，代码只判应用级生命周期）。改动：`lib/ide/ide_workbench.dart` `_onChordKey` 加 `!widget.visible || !mounted ⇒ _leaveChordMode() + ignored`；chord 定时器同步加 `!widget.visible`。波及：仅 chord 等待态。判据：**无既有 harness**（chord×多窗口无测试）⇒ 读码 + 走查步骤（两窗：A 按 Ctrl+K 前缀，切 B 打字，B 的键应正常落字、A 不执行命令）。

**P3 · 扫描失败永不重试** — 披露：轻渠道（缺陷修：`catch` 吞错且缓存置空，`found.isEmpty` 早退 ⇒ 整场会话不再扫）。改动：`lib/workbench.dart` 新增 `_sidePanelRetryAt`；失败时移出缓存 + 30 秒退避；成功时清退避。波及：仅侧栏仓库列举。判据：读码（退避有界：每 30 秒至多一次扫描）。**未做**：失败的用户可见提示（需新增 l10n 键 + 重生成三份 `app_localizations*.dart`，本笔不掺）⇒ 记台账。

**P4 · 释放后空断言** — 披露：轻渠道（缺陷修：`_config`/`_setMode` 直取 `_connection!`，`_teardown` 已置 null）。改动：`lib/kernel/thincoder/thincoder_kernel.dart` 两处先取局部变量并判空返回。波及：模型/模式/思考档位回调。判据：读码 + `flutter analyze` 干净。

**P5 · diff 回调绕过 null 守卫** — 披露：轻渠道（缺陷修：`_surface()` 无条件 `_nativeController!`，而 `modified` 回调不经 build 的 null 守卫）。改动：`lib/ide/ide_editor.dart` `_surface` 改块体，控制器为 null ⇒ `SizedBox.expand()`（表达式体 → 块体，其余逐字不动）。波及：编辑器/diff 渲染。判据：读码 + analyze；既有编辑器测试的红项经 A/B 复核为**既有失败**（stash 本档改动后同 6 红）。

**P6 · 终端菜单锚点** — 披露：轻渠道（缺陷修：`findRenderObject()!` 强转，目标滚出视口/被移除即崩）。改动：`lib/ide/terminal/terminal_view.dart` 与 `terminal_panel.dart` 两处改 `is! RenderBox || !hasSize ⇒ return`。波及：命令标记菜单、标签页菜单。判据：读码 + analyze。

**P7 · 已释放通知** — 披露：轻渠道（缺陷修：`_apply` 无 `_disposed` 守卫，同类 `_reviewChanged:210` 有）。改动：`lib/chat/chat_session.dart` `_apply` 首行 `if (_disposed) return;`。波及：仅事件应用入口。判据：读码 + analyze。

### 验证读数（父代理实跑）

- `flutter analyze`（8 个改动档）：**No issues found**。
- `test/window/app_windows_test.dart`：**70/70 通过**。
- 目标子集（kernel/chat/terminal/editor/window）：**3086 通过 / 29 红**；A/B 复核：`ide_editor.dart` 改动 stash 后同文件仍 6 红 ⇒ 29 红均为**既有环境类失败**（与合上游后基线 289 红同族，名单含 TextMate 资源、macOS 变体、shell integration 写盘）。

## 评审第 1 轮后的修正（2026-10-17 21:39 · 轻渠道）

评审结论：0 🔴 之外 1 🔴（P2 判据选错变量）+ 4 🟡 + 2 🔵。处置如下。

**R1（🔴 · P2）—— 已修**：原判据 `!widget.visible` 实为"本窗口内该 IDE 空间是否显示"（`workbench.dart:2466` 的 `visible: shown`，IDE 窗口恒 `shown: true`），不能表达"非活动窗口"。改为新增 `_holdsKeys()`（`ide_workbench.dart:2872`）：`mounted && widget.visible` + **主焦点与本工作台焦点互为祖先** + `ModalRoute.isCurrentOf(context)`——与同文件 `_onLateKey` 原先内联的判据同源，现两处共用一份；`_onChordKey`（`:2892`）与 chord 定时器（`:2911`）都改用它。`_onLateKey` 本体同时收正为调用 `_holdsKeys()`，消除第二份判据。

**R2（🟡 · P3 重试无驱动）—— 已修**：失败时除 30 s 退避外，新增一次性 `Timer`（`workbench.dart:3378` 一带）在到期时 `setState`，让"下一次请求"成为确定事件；定时器在 `dispose` 取消（`:695`）。

**R3（🟡 · P3 吞错 + 可见提示缺项）—— 已修一半，另一半如实披露**：`catch (error)` + `appEvent('sidePanel', …)`（`:3367`，新增 `platform/event_log.dart` 导入）；**可见提示仍不做**（l10n 键 + 三份生成档，台账 #49），§6 记缺项。

**R4（🟡 · 聊天窗口关闭无在途守卫）—— 已修**：`requestClose` 入口统一 `_closing.add` 守卫（`app_windows.dart:1001`），三条路径（chat / agent / IDE）共用一份在途判定；重入调用返回 `false`。

**R5（🟡 · P1 判据空转）—— 已修**：新增用例「a close asked for again while one is under way runs it once」——`FakeWindowHost` 新增 `holdLeaveFullScreen` 闸门（`test/window/fake_window_host.dart:96`），测试在 `leaveFullScreen` 悬住时二次 `requestClose`，断言返回 `false` 且 `hide` **只出现一次**。`test/window/app_windows_test.dart` **71/71 通过**（原 70 + 新 1）。

**R6（🔵 · `requestClose` 重入返回 true）—— 已修**：同上 R4，重入返回 `false`，布尔值与"窗口已关闭"同义。

**R7（🔵 · 文档状态位/占位）—— 收尾时处理**：§1 状态行与模板占位在 §6 结算时一并收正。

### 修正后的验证读数（父代理实跑）

- `flutter analyze`（8 档）：**No issues found**。
- `test/window` + `sidebar_hosts` + `workspace` + `thincoder_kernel` + `session_review`：**222/222 通过**。
- 说明：`test/ide/editor`、`test/ide/workbench` 等目录的红项为既有环境类失败（A/B 复核见上）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

## 用户批准（2026-10-17 21:53）

- 用户逐字：「批准收口」。
- 批准对象 = A 批七笔稳定性守卫的交付形态：P1–P7 按 §1 逐笔记录落地，经两轮独立代码评审（第 1 轮 changes-required → 7 条全处置；第 2 轮 pass、无新增问题）。
- 批准时**已知的两处缺口**（用户知情，不视为隐含承诺）：
  1. P2 的双窗现场走查**未执行**——Windows 上无法开第二窗（`New Window` 命令无执行器，台账 **#50**），待 #50 修复后补验；
  2. P3 的失败可见提示未做（台账 **#49**）。
- 本批为轻渠道轮（缺陷修），故 **§2/§3/§5 无内容**：无正式设计档、无设计评审、无 eng-coder 实施段；实现 = 父代理直改（逐笔披露见 §1），评审 = 代码评审（见 §6）。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

## 验证与收口（A 批 · 七笔守卫）

### 每笔读数（父代理实跑）

| 笔 | 判据 | 读数 | 手段 |
|---|---|---|---|
| P1 窗口重入 | 同一窗口关闭的副作用只跑一次 | 新增用例断言二次 `requestClose` 返回 `false` 且 `hide` 只一次 | 单测（`app_windows_test.dart` 新用例 + `FakeWindowHost.holdLeaveFullScreen` 闸门） |
| P2 跨窗 chord | 非活动窗口不接管按键 | 判据改为 `_holdsKeys()`（焦点互为祖先 + 当前路由），与 `_onLateKey` 共用；`_onChordKey` 与定时器双用 | **读码；真机双窗走查未跑**（见下「已知缺口」） |
| P3 扫描重试 | 失败后确定会重试 | 30 s 退避 + 一次性 `Timer` 触发重建；`dispose` 取消；失败留 `appEvent` 日志 | 读码 + analyze |
| P4 释放后空断言 | 释放后点模型/模式不抛 | 两处先取局部并判空返回 | 读码 + analyze |
| P5 diff 回调守卫 | 文档释放后 diff 重建不崩 | `_surface` 块体 + 局部提升，null ⇒ `SizedBox.expand()` | 读码 + A/B 复核既有红项 |
| P6 终端菜单锚点 | 目标不在场时不崩不弹错位菜单 | 两处 `is! RenderBox \|\| !hasSize ⇒ return` | 读码 + analyze |
| P7 已释放通知 | dispose 后到达的事件不通知 | `_apply` 首行 `_disposed` 守卫 | 读码 + analyze |

### 全量口径

- `flutter analyze`（8 个改动档）：**No issues found**。
- `test/window` + `sidebar_hosts` + `workspace` + `thincoder_kernel` + `session_review`：**222/222 通过**（含新增用例；`app_windows_test` 71/71）。
- `test/ide/editor`、`test/ide/workbench` 等目录红项：经 A/B 复核（stash 本批 `ide_editor.dart` 改动后同文件仍 6 红）判定为**既有环境类失败**，与本批改动无关。

### 评审轮次

- 第 1 轮：changes-required（1 🔴 + 4 🟡 + 2 🔵）→ 7 条全处置（6 Fixed / 1 Deferred-doc）。
- 第 2 轮：**pass**，无新增问题；三处易出问题改动（`_closing` 上提对退出链路、重试定时器生命周期、`_holdsKeys` 在定时器中的调用）逐条排查通过。

### 已知缺口（如实记录）

1. **P2 的双窗走查未跑**（需真机开两窗 + 键盘）：代码判据已从"布局态"改为"焦点态"并复用既有机制，但**现场读数仍缺**；请用户按 §1 的走查步骤验一次（A 窗按 `Ctrl+K` → 切 B 窗打字 ⇒ B 正常落字、A 不执行命令）。
2. **P3 的可见提示未做**（台账 #49）：失败只留 `appEvent` 日志与重试，界面仍显示"没有仓库"。
3. `_agentsChanged` 触发的那条 `_remove` 路径未单独覆盖用例（守卫与已测路径同一份）。

### P2 走查的执行记录（2026-10-17 21:52）

- 用户按指示尝试开第二个窗口，**失败**：`Ctrl+Shift+N` 无反应。
- 父代理核查（实读）：快捷键确实绑到 `workbench.action.newWindow`（`lib/keybindings/window_keybindings.dart:34`），但该命令**没有执行器**——全仓只有常量、`CommandInfo`、标题映射三处引用，`lib/workbench.dart` 的命令表里无此 id；真正开窗的只有原生回调 `newWindowRequested()`（`app_windows.dart:1247`）。
- 结论：**本批无法在 Windows 上凑出"两个窗口"的场景**，P2 的现场走查**未执行**，不得记为已验证。此缺陷已入台账 **#50**（New Window 无执行器）。
- 替代核验（可做的部分）：`_holdsKeys()` 的判据与 `_onLateKey` 同源（此前已用于"按键来自别处"的判定），代码层面已由第 1/2 轮评审复核；跨窗实证待 #50 修复后再补。

## 结算（2026-10-17 · 已收口）

- **批**：A 批 · 稳定性守卫七笔（轻渠道轮，父代理直改，逐笔可 revert）。
- **改动面**：`lib/window/app_windows.dart` · `lib/ide/ide_workbench.dart` · `lib/workbench.dart` · `lib/kernel/thincoder/thincoder_kernel.dart` · `lib/chat/chat_session.dart` · `lib/ide/ide_editor.dart` · `lib/ide/terminal/terminal_view.dart` · `lib/ide/terminal/terminal_panel.dart` · `test/window/app_windows_test.dart` · `test/window/fake_window_host.dart`。
- **读数**：`flutter analyze` 8 档 No issues；目标子集 **222/222**（含新增用例，`app_windows_test` 71/71）；既有环境红项已 A/B 复核排除。
- **评审**：2 轮（changes-required → pass）。
- **台账**：**#43 核销**；新增 **#49**（P3 可见提示缺项）· **#50**（New Window 无执行器）；`_agentsChanged` 的 `_remove` 路径未单独覆盖 → 随 #50 一并补验。
- **未闭环（已知并获批）**：P2 双窗走查（待 #50）· P3 可见提示（#49）。
- **结算同步**：状态行已置「已收口 2026-10-17」；§2/§3/§5 按轻渠道轮规则留空（§4 已说明）；本档冻结，不再回写。
