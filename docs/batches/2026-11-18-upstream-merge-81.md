# 2026-11-18 · upstream-merge-81
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-18 · 来源 = 用户 2026-11-18 02:52「拉代码更新」。
> 台账 = #257（core · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-18
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 上游合并（81 提交）· 冲突清单与解析规则

**事实**

- 合并基准 = `1987ad78`；上游 tip = `0b9e30a7`（#1102）。本地领先 247、落后 81。
- 上游 81 提交改 **195 个文件**；与本仓改过的文件重叠 **41 个**。
- 实际冲突 **10 个文件 / 17 处**（逐档 5 / 3 / 2 / 1 / 1 / 1 / 1 / 1 / 1 / 1）。备份分支 = `backup/pre-upstream-20261118`。
- 已提交合并前的现场：`c2031a18`（三项能力批的设计档 + 批档）。

**冲突清单（按规模）**

| 文件 | 处数 | 本质 |
|---|---|---|
| `lib/chat/composer/composer.dart` | 5 | 本仓把大块抽到 `composer_message.dart` / `composer_view.dart`；上游在原件里继续加功能 |
| `lib/chat/composer/session_model_picker.dart` | 3 | 本仓「切换待定」vs 上游「降级模型」 |
| `lib/chat/chat_session.dart` | 2 | 本仓 overlay 包裹 vs 上游新增 `fallbackModel` / `endModelFallback` / 删 `userSent` |
| 其余 7 档 | 各 1 | 多为双方各自新增的 import 或方法块 |

**解析规则（本席已定的方向，交设计席写死）**

- **规则一**：两边各自新增、互不替代 ⇒ **都留**。适用 `.gitignore` · `chat_models.dart` · `secret_store_io.dart` · `image_tools_test.dart` · `browser_page.dart`。
- **规则二**：上游重构了结构、本仓有等价改造 ⇒ **取上游结构，把本仓特性重新贴回**。适用 `chat_history_view.dart`（上游 `_rows[row]` + `KeyedSubtree`，本仓 `_LiveItem` 包裹）。
- **规则三**：本仓抽离成 `…Of(this)` 函数、上游在原件内联增功能 ⇒ **留本仓结构，把上游新行为移植进抽离档**。适用 `composer.dart` 五处。
- **规则四**：两套功能并存 ⇒ **合并语义**。适用 `session_model_picker.dart`（待定标签 + 降级标签）· `chat_item_view.dart`（`contexts`/`onContextMenu` + `fromSession`）。

**已查实的移植点（规则三的明细）**

- `composer.dart` 需补 `void clear()`——上游新增，且调用方 `chat_screen.dart:843` 已在合并后的树里，不补则编译不过。
- `composer_view.dart:84` 的 `session.promptSuggestion` 已被上游删除（改为 `replySuggestions`）⇒ 必须改源，否则编译不过。
- `chat_session.dart` 的 `userSent?.call()` 上游已删（连带删了 `static void Function()? userSent;`）⇒ 保留即编译不过。
- `chat_session.dart` 须并入上游的 `fallbackModel` / `endModelFallback` 与 `_suggestionNotes()` 调用。

**一次被挡下的动作（如实记）**：本席尝试直接编辑四个纯 import 冲突，被写门拒绝（设计评审未过）。故改走完整链路：§2 设计 → 评审 → 批准 → 实施。

### 评审轮 1 裁决（pass · 0🔴 + 9🟡 + 7🔵 ⇒ 16 条全受理）

**两条实质问题我先定方向**

- **#2 层级结论**：`chat_history_view.dart` 实测 4262、`chat_session.dart` 1401、`composer.dart` 744。结论行不能写「无跨层文件」。
- 处置：结论行按符号点名越层的档，指向已记的立场（§8.5 体量立场 / 存量债名单）。
- `chat_history_view.dart` 不在现有存量债名单 ⇒ 把它补进同一名单，沿用「认账不排期」。
- **不重开存量债裁定**（R3），只让结论行有可核对象。

**#3 RTM delta 同前**：2-1 行断言的正是重建次数 / 文本 / 偏移，而本批按规则二重写行映射 ⇒ delta 必须对 2-1 给出结论，不能只写「无」。

**修轮 6 定点（只改这十六条，不扩面）**

- #1：`§2` 任务 1 的「18 处差 1」改为 17（与 `§1` 一致），删掉「差数上报」；或补一条实际的上抛。
- #2 · #3：按上面两条方向落。
- #4：`fork-deltas §3` 给 `composer_message.dart` 补一行登记。
- #5：`KeyedSubtree(ValueKey(...))` 与 `live:` 的坐标名统一（批档 + 登记行两处）。
- #6：条目 5 判据拆成两条（RTM 行 / 测试档构造），并写明用例体未落地。
- #7：规则一、四各补先例坐标或显式「无先例」。
- #8：`chat_session.dart` 登记行删掉旧形摘要，一格一形。
- #9：四条首次登记行并入 §3 表体（去空行）。
- #10–#16（🔵）：数字漂移三处按实测改 · `endModelFallback` 进静态读 · l10n 判据补一行 · `§5.1` 补先例/调查证据/RTM delta 三行 · 四条登记行的复核标记写清 · 用例表补分支来路两句。

**不动**：四条解析规则本身、17 处解法、`§5.1` 的规则表内容。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 批次任务（覆盖）

| # | 条目 | 范围 |
|---|---|---|
| 1 | 10 档 17 处冲突按四规则解析完（§1 已定方向；逐档 5 / 3 / 2 / 1 / 1 / 1 / 1 / 1 / 1 / 1，`<<<<<<<` 合计 17，2026-11-18 合并树实测） | 本批 |
| 2 | 合并后编译通过：`flutter analyze --no-pub` 的 error 数 = 0 | 本批 |
| 3 | 合后按 §3.1 的 numstat 口径复核登记面；表外自有块先补第 3 节 | 本批 |
| 4 | 首次登记 4 档：`.gitignore`、`chat_item_view.dart`、`browser_page.dart`、`image_tools_test.dart` | 本批 |
| 5 | 集成面：`test/RTM.md` 新增 11-1 一行（模型回退；行已定，用例体待假内核 harness） | 本批 |

**设计档落点**：`docs/design/fork-deltas.md` —— 新增 §5.1「冲突解析规则（现态）」；第 3 节 6 行按合后形态改写、5 行新登记（4 档表外自有块 + 拆档 `composer_message.dart`，逐行见该档）。不新增设计档：合并是登记表的维护动作，机制归属不变。

**调查证据**：`manifest.index.publicRepos` 为空，无独立文档仓；上游源码经本仓 `origin` 远端读取（`git rev-parse origin/main` = `0b9e30a7`），属仓内读。查过，无外部相关来源。

**最近先例**：第 5 节「合并核对顺序」与第 3.1 节的 numstat 对账口径就是本批的既定程序，本批只补执行。四规则各有先例，坐标见 `docs/design/fork-deltas.md` §5.1。

- 规则一：`lib/kernel/kernel_types.dart` 的 `ContextUsage.sessionSpent` 与上游 `detail` 并存。
- 规则二：2026-11-05 合 `step_folds.dart`（取我方结构、把上游规则改写进去）。
- 规则三：同批 `composer.dart` 的委托形态。
- 规则四：`lib/settings/pages/general_page.dart` 的自有设置组与上游 `BaoBash` 组 / `SessionToolsSetting` 共存。

与先例一致，不偏离。

**数据事实**：本批没有需要先读数据的断言 —— 全部判据是 git 读数（numstat、冲突标记计数）与 analyze 的 error 计数，当场可测。不需要先读数据。

### 机制设计：每处冲突的解析口径

| 文件 | 处 | 规则 | 解法（实施口径） |
|---|---|---|---|
| `.gitignore` | 1 | 一 | 两侧块都留：自有 `/thincoder/`、`/.thincoder/`；上游 `.wrangler/`、`.dev.vars*`、`.env` |
| `lib/chat/chat_models.dart` | 1 | 一 | import 两侧都留：自有 `editor_context.dart` 的 import + export 与上游 `reply_suggestions.dart`；`UserMessageItem` 的 `contexts` / `fromSession` 已由自动合并并存，不动 |
| `lib/models/secret_store_io.dart` | 1 | 一 | import 两侧都留：`process_host.dart`（自有解封路径）+ `shell_command_io.dart`（上游 Windows 路径） |
| `test/images/image_tools_test.dart` | 1 | 一 | import 两侧都留：自有 `host_tools.dart` 与上游 `copy_button.dart` |
| `lib/settings/pages/browser_page.dart` | 1 | 一 | 自有的 btest 读写 helper（hosts / readonly / qaRoot）在前，上游 `_use` 在后；共用尾部 `}), );` 归 `_setQaRoot` |
| `lib/chat/widgets/chat_item_view.dart` | 1 | 四 | `AgentMessageCard` 带 `session: fromSession`；`UserMessageBubble` 带 `contexts` / `onContextMenu` |
| `lib/chat/chat_history_view.dart` | 1 | 二 | 取上游 `itemBuilder(context, row)`：`row` = 行号 ⇒ `final index = _rows[row]`：`index` = 项号 ⇒ `KeyedSubtree(key: ValueKey(index))`：键 = 项号；`_row(...)` 的 child 换成自有 `_LiveItem(revision: _liveTick, live: index == _liveRow, build: () => _buildItem(index))`，`live:` 两侧都取项号（`_liveRow` = `_folds.rowOf(_contentCount - 1)`，`StepFolds.rowOf` 返回合并到的首项号，不是行号）；隐藏行判定随上游 |
| `lib/chat/chat_session.dart` | 2 | 三 · 四 | ① `modes` 保留自有 overlay 包裹，`fallbackModel` / `endModelFallback` 随上游并入；② `send()` 保留自有 `takesContext` / `_overlay.beforeSend`，`notes` = `[...notes, ..._placeNotes(from), if (!takesContext && editor != null) ..._editorNotes(editor()), if (from != null) ..._suggestionNotes()]`，`if (from != null) userSent?.call();` 随上游删除 |
| `lib/chat/composer/composer.dart` | 5 | 三 | ① `_acceptSuggestion` 保留自有委托（`_acceptSuggestionOf` 体已与上游同形），自有 `_suggestionKey` / `_suggestionKeyContext` 保留；② 新增 `clear()` 按委托形态落位：`void clear() => _clearOf(this);` + `composer_message.dart` 的 `_clearOf`（上游体）；③ `build` 保持 `buildOf(this, context)`；④ `_buildInputs` 保持委托；⑤ `_buildMarkdownEditor` 保持委托 |
| `lib/chat/composer/composer_view.dart` | 编译修复 | 三 | `buildOf` 把已删的 `session.promptSuggestion` 改为 `session.replySuggestions.firstOrNull`；`_buildInputsOf` / `_buildMarkdownEditorOf` 按上游本批体核对补齐 |
| `lib/chat/composer/session_model_picker.dart` | 3 | 四 | 等待态与回退态并存：`foreground: fallback == null ? null : AppColors.caution`；label = `[_label(selected, options, fallback: fallback), if (waiting != null) l10n.modelsSwitchPending(waiting)].join(' · ')`；tooltip = 两侧都空时留原值，否则 `[?tooltip, if (waiting != null) l10n.modelsSwitchPending(waiting), if (fallback != null) l10n.modelsFallbackHint(picked, fallback)].join(' · ')`；`footers` 保留上游「切回」项与自有 thincoder 模型页项 |

### 受影响文件与测试覆盖

| 面 | 文件 |
|---|---|
| 冲突解析（10） | `.gitignore` · `lib/chat/chat_history_view.dart` · `lib/chat/chat_models.dart` · `lib/chat/chat_session.dart` · `lib/chat/composer/composer.dart` · `lib/chat/composer/session_model_picker.dart` · `lib/chat/widgets/chat_item_view.dart` · `lib/models/secret_store_io.dart` · `lib/settings/pages/browser_page.dart` · `test/images/image_tools_test.dart` |
| 编译修复（1） | `lib/chat/composer/composer_view.dart` |
| 抽取辅助（实施落点） | `lib/chat/composer/composer_message.dart`（新增 `_clearOf`；`_acceptSuggestionOf` / `_submitOf` 按上游体核对） |
| 设计档 | `docs/design/fork-deltas.md`（设计席已落） |
| 集成索引 | `test/RTM.md`（新增 11-1；产品面，实施席落） |

**层级结论**：越 800 行的共享档两档，处置沿用已记立场，本批不出拆分计划。

- `lib/chat/chat_history_view.dart`：`wc -l` 实测 4384（合前）/ 4885（2026-11-18 合并树）/ 4560（上游 `origin/main`）；本批按规则二改其行映射，补进存量债名单（第十二档），认账不排期。
- `lib/chat/chat_session.dart`：1462 / 1537 / 1403；本批并入回退面，体量立场见 `docs/design/fork-deltas.md` §8.5。
- `lib/chat/composer/composer.dart`：762（合前），<800 不越层；合后按委托形态。

改动全落在产品面（`lib/**`、`test/**`、`.gitignore`）；设计档已由设计席落盘。

### 验收对照（每条指回上面的条目）

| 条目 | 判据（机器可判） |
|---|---|
| 1 冲突清零 | 10 档内 `<<<<<<<` / `=======` / `>>>>>>>` 的行计数逐档 = 0 |
| 2 编译 | `flutter analyze --no-pub` 的 error 数 = 0 |
| 2 上游能力在盘 | `composer.dart` 内 `void clear()` ≥1；`session_model_picker.dart` 内 `modelsFallbackHint` ≥1 且 `modelsSwitchPending` ≥1；`chat_session.dart` 内 `fallbackModel` ≥2、`endModelFallback` ≥1、`_suggestionNotes()` ≥1、`userSent` = 0；`composer_view.dart` 内 `promptSuggestion` = 0 |
| 1 自有特性在盘 | `chat_session.dart` 内 `_overlay.beforeSend(` ≥1；`session_model_picker.dart` 内 `pendingModel` ≥1；`composer_view.dart` 内 `_suggestionKey` ≥1 |
| 3 登记面 | 合后 `git diff --numstat origin/main HEAD` 的每条非零行命中第 3 节对应行，每行实测 ≤ 该行预算；无表外非零档 |
| 1 · 2 变更面单测 | `flutter test test/composer_test.dart test/chat/model_picker_test.dart test/images/image_tools_test.dart`；history 结构面另跑 `flutter test test/chat/chat_history_rebuild_test.dart` |
| 2 l10n 键 | `lib/l10n/app_en.arb` / `app_zh.arb` / `app_localizations_en.dart` / `app_localizations_zh.dart` 四档内 `modelsSwitchPending` 与 `modelsFallbackHint` 各 ≥1（2026-11-18 实测各 ≥1） |
| 5 RTM 行 | `test/RTM.md` 内 `11-1` 行的编号与标题逐字（`11-1` · 模型回退），行在盘 |
| 5 用例体 | `test/integration/model_fallback_flows_test.dart` 的 `test('11-1 …')` —— 本批**未落地**（用例体待假内核 harness），落地时标题按 RTM 的 `11-1` 逐字 |

### 用例表

| 场景 | 输入 | 期望 |
|---|---|---|
| 正常 | 合并后全树 | analyze error = 0；上面点名的单测文件全绿 |
| 边界 | `replySuggestions` 为空 | `buildOf` 的 suggestion 为 null：不显建议条、不取键标签。来路：上游本批删 `ChatSession.promptSuggestion`、`buildOf` 改读 `replySuggestions.firstOrNull`，空表即 null |
| 边界 | 等待态与回退态同时非空 | label 两段以 ` · ` 相连；tooltip 按非空句拼接；前景为 caution。来路：上游本批在同一个 pill 上加 `fallbackModel` 后缀与菜单「切回」项，本仓等待态（`pendingModel` → `modelsSwitchPending`）同处一面 ⇒ 一次回退后、回合在飞时改选模型，两态同真 |
| 边界 | `_setQaRoot` 与上游 `_use` 相邻 | 两者各自闭合，方法体不互相吞并 |
| 错误 | 冲突标记残留 | 计数 > 0 ⇒ 停止，不得提交 |
| 错误 | 表外共享档 numstat 非零 | 停止实施，先补第 3 节（依据 docs/design/fork-deltas.md「表外发现自有块时先补第 3 节，再选冲突解法」） |

### 关键决策记录

| 选项 | 结论与理由 |
|---|---|
| A（采用）规则二：取上游 `_rows[row]` + `KeyedSubtree`，把 `_LiveItem` 贴回 `_row` 的 child | 上游 `itemBuilder` 的参数是行号，`_rows` 会跳过隐藏项，项号 ≠ 行号；留本仓旧体即把项号当行号用，隐藏项之后整段错位 |
| B（采用）`clear()` 按委托形态落位 | 本档是 `composer.dart` 的拆档前端，方法体一律进 `…Of` 助手；新方法另走一形会让下一轮合并的移植点分叉 |
| C（采用）等待态与回退态合并语义 | 两者各改 pill 的一句话（后缀 / 回退提示），任取一侧都丢一个可见行为；§1 规则四已定 |
| D（否）整档取上游 | 自有 btest 接缝、窗口门、overlay 装配都在共享档内，整档取上游是删功能 |
| E（否）回退成旧 fork 版本 | 会把上游本批其它改动一并回退，与 §1 目标相反 |

### 边界（不做）

不改上游本批的行为与判定次序；不重构、不拆大档；不修与合并无关的既有失败用例；不改上游测试的断言（`test/images/image_tools_test.dart` 只并 import）。

### UI / 交互

本批不改界面设计。可见变化全部来自上游本批能力：模型回退的 pill 后缀 / tooltip / 菜单「切回」项；建议条改读 `replySuggestions` 列表。两处的合后形态在上面的机制表里逐条写死，没有「讨论过未落」的项。

### 集成测试设计（RTM delta）

读过 `test/RTM.md`（125 行，11 行用例，当前 11 / 50–100）。

- 被破坏的行：无 —— 11 行断言面里没有一行断言模型 pill 与建议条。**2-1 单列复核**：它断言失焦期重建 0 次、可见文本不变，恢复恰 1 次重建、文本 == 全文、底部仍在底部、中段偏移不变，而本批按规则二重写了该档的行映射。三条断言的决定面都没被改写：重建次数由 `_showNow` / `_showWords` 的窗口门决定；可见文本仍来自 `_buildItem(项号)`；偏移由 `_syncRows` 的 add / removeItem 与 `_estimateExtent` 记账；改写只改「哪一行画哪个项号」与子件身份键。⇒ 不预期破坏，但列为**待复核**：实施后实跑 `test/integration/chat_flows_test.dart` 的 2-1 行给读数，未跑通即回本节改 delta。
- 冗余可删的行：无。
- 缺失需新增：1 行 —— 11-1「模型回退」：上游本批新能力（`ReportsModelFallback` → `ChatSession.fallbackModel`），业务可观察结果 = 被安全策略拦下的消息由另一个模型回答，pill 标注该模型、菜单里一键切回；回溯需求 = 上游本批能力，本仓无需求条目。用例体待假内核 harness（内核实现 `ReportsModelFallback`），状态「行已定」，落 `test/integration/model_fallback_flows_test.dart`。

### 上抛项

无。

## §3 设计评审（评审子代理）
**状态行**：评审通过（1 轮 · 🔴 0 · 🟡 9 · 🔵 7）



### 轮次 1（评审子代理）

**对象**：`docs/design/fork-deltas.md` §5.1 · 批档 §2。评审范围 = 两档全文（已逐行读完）。

**范围限制（如实记）**：无 AGENTS.md、无项目标准档、无文档地图 —— 方法论按评审准则判，文档归属按本仓 design 目录既有惯例判（§3.1 / §7 / §8 各节自带「调查证据」「最近先例」与验收行）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Requirements / 记录一致性 | 🟡 | 任务 1 写「§1 记 18 处差 1，按实测写，差数上报主 agent」，但 §1 现态是「实际冲突 **10 个文件 / 17 处**（逐档 5 / 3 / 2 / 1 / 1 / 1 / 1 / 1 / 1 / 1）」，逐档相加 = 17；「### 上抛项」一节只写「无」，任务 1 声明的差数上报没有落点。 | 两处对齐：或按 §1 的 17 改写任务 1 口径并删掉「差数上报」，或把 18 / 17 的实测差写成一条实际上抛项，都要能由合前读数复核。 |
| 2 | Tier（准则 8） | 🟡 | 「**层级结论**：无跨层文件。」被本档自身读数反驳：`lib/chat/chat_history_view.dart` 行写「档整体相对上游 +337 / −26（`split('\n')` 口径实测 4262 / 3951）」，§8.5 写「三档过 800 行」（含 `chat_session` 1401），`lib/chat/composer/composer.dart` 现 744 行（<800）。前两档过 800、第三档过 500，且 `chat_history_view` 不在「**存量债（过 800 行的上游共享档…）**」名单内，本批又按规则二改它的结构。 | 结论行按符号点名越层的档并指向已记录的处置（§8.5 体量立场 / 存量债名单）；`chat_history_view` 若沿用「认账不排期」，把该档补进同一名单，使结论行有可核对象。不重开存量债裁定。 |
| 3 | 集成测试设计（准则 12） | 🟡 | 「被破坏的行：无」的理由只覆盖 pill 与建议条（「11 行断言面（切会话、失焦、流式、btest 三行、SSH、凭证、magpie、用量两行）都不落在模型 pill 与建议条上」），而本批按规则二重写 `chat_history_view.dart` 的行映射与 `_LiveItem`，该档登记行写着「集成面见 `test/RTM.md` 2-1 行」—— 2-1 断言的正是重建次数 / 可见文本 / 偏移。 | delta 对 2-1 明确给结论：说明三条断言在新行映射下如何仍成立，或列为待复核行并在实施时实跑。 |
| 4 | 登记面完整性 | 🟡 | 机制表与受影响表都把新体落到 `composer_message.dart`（「`composer_message.dart` 的 `_clearOf`（上游体）」/「| 抽取辅助（实施落点） | `lib/chat/composer/composer_message.dart`（新增 `_clearOf`；…）」），但 fork-deltas §3 无该档登记行；两个拆档兄弟 `composer_editing.dart`、`composer_view.dart` 各有一行（后者还注「`origin/main` 无此路径」）。 | 给 `composer_message.dart` 补一行登记（块 / 类型 / 接缝 / 预算），或在现有一行里明确它由哪行承载；否则本批移植落点落在登记表外。 |
| 5 | Clarity | 🟡 | 同一处键的坐标名两处不同：批档写「`KeyedSubtree(ValueKey(index))`」与「live: index == _liveRow」，fork-deltas 登记行写「`KeyedSubtree(ValueKey(项号))`」；批档决策 A 又写「上游 `itemBuilder` 的参数是行号，`_rows` 会跳过隐藏项，项号 ≠ 行号」。实现席无法判定 `index` 是项号还是行号。 | 两处统一坐标名（项号 / 行号各一），`live:` 的比较双方取同一坐标系；否则正是决策 A 警告的错位。 |
| 6 | Acceptance | 🟡 | 条目 5 判据写「`test/RTM.md` 内 `11-1` 行在盘，编号与标题逐字（`test('11-1 …')`）」，但用例体是「行已定，用例体待假内核 harness」—— `test('11-1 …')` 是测试档构造，不在 RTM 行里，判据对哪个档生效含混。 | 拆成两条判据：RTM 行的编号与标题逐字、测试档的 `test('11-1 …')`（随用例体，或显式记为未落地）。 |
| 7 | 最近先例（准则 9） | 🟡 | 「四规则各有先例：规则二先例 = 2026-11-05 合 `step_folds.dart`…，规则三先例 = 同批 `composer.dart` 的委托形态。与先例一致，不偏离。」只给规则二、三；规则一、四既无先例坐标，也无「无先例」的显式声明。 | 为规则一、四各补先例坐标，或显式写「无先例」并说明沿用理由；断言条数与所列条数对齐。 |
| 8 | Doc hygiene（R2） | 🟡 | `chat_session.dart` 登记行同一格里把 `send()` 的 `notes` 写两遍：旧形「`notes: [...notes, ..._placeNotes(from), ...自有 editor 注]`」，再是合后形「`send()` 的 `notes` = `[...notes, ..._placeNotes(from), if (!takesContext && editor != null) ..._editorNotes(editor()), if (from != null) ..._suggestionNotes()]`」。旧形缺 `takesContext` 守卫与 `_suggestionNotes()`，照它实现会丢上游本批调用。 | 删掉旧形摘要，一格只留一个规范形式。 |
| 9 | Doc hygiene / 可读性 | 🟡 | 四条首次登记行接在 §3 表体最后一行的空行之后（「| `test/workspace_test.dart` |」后为空行，再是「| `.gitignore` | 自有忽略块」），无表头，渲染不成表行。 | 把四行并入 §3 表体（去中间空行），或为该段补表头。 |
| 10 | 数字漂移（R7c） | 🔵 | 设计档落点写「第 3 节 7 行按合后形态改写、4 档首次登记」，而 §3 带本批合后形态的是 6 行（`chat_session` / `chat_models` / `composer` / `composer_view` / `session_model_picker` / `chat_history_view`），加 4 行首次登记共 10 行。 | 改成实际档数，或点名第 7 行是哪一档（若为 `secret_store_io`，该行现文未记 `shell_command_io.dart` 的 import）。 |
| 11 | Acceptance 覆盖 | 🔵 | 机制表要求「fallbackModel / endModelFallback 随上游并入」，静态判据却只查「`chat_session.dart` 内 `fallbackModel` ≥2、`_suggestionNotes()` ≥1、`userSent` = 0」，无 `endModelFallback`。 | 把 `endModelFallback` 加进同一行静态读数（漏掉时 analyze 仍会报，判据只是补齐）。 |
| 12 | Requirements 覆盖 | 🔵 | 本批用到两个上游本批 l10n 取值（`l10n.modelsSwitchPending` / `l10n.modelsFallbackHint`），任务表与验收表都无 l10n 一步，而 §1 立着「l10n 只合并 `app_en.arb` / `app_zh.arb` 的键级并集；生成文件由 `flutter gen-l10n` 重产，不手解、不选边」。 | 补一条机器判据：两个键在 arb 源档与生成物里各 ≥1（缺失时 analyze 会报，判据只是提前一步）。 |
| 13 | 设计档形态（准则 9 / 10） | 🔵 | 新 §5.1 只有四规则表与一行判据；同档兄弟节（§3.1、§7.1、§8.1）各自带「**调查证据**」「**最近先例**」与验收 / RTM delta 行。本批这些内容在批档 §2 里有，但日后单读 §5.1 找不到先例与来源。 | 该节补「最近先例」「调查证据」「集成测试设计（RTM delta）」三行（或指向批档坐标），与 §3.1 / §7.1 / §8.1 同形。 |
| 14 | 数字漂移（R7c） | 🔵 | §3.1 写「`test/RTM.md` 的 9 行断言面都不落在文案与注释上」，批档读到的现态是「读过 `test/RTM.md`（125 行，11 行用例，当前 11 / 50–100）」。 | 改成现态行数或注明读数日期，免得下次按 9 行核对。 |
| 15 | 口径一致性 | 🔵 | 四条首次登记行的预算列记 `fork 侧 base..HEAD 实测`（如「fork 侧 base..HEAD 实测 +9 / −0（2026-11-18 合并时首次登记，此前表外）；合后按 `git diff --numstat origin/main HEAD` 复核」），而 §1 规则是「**首次登记行的「行数预算」列放实测值**…当场只有对 `origin/main` 的 `git diff --numstat` 读数」，§3.1 判据是「每条补登记行的「行数预算」列等于 `git diff --numstat origin/main` 的读数」。 | 任务 3 的合后复核已覆盖；把四行的复核标记写清（未复核 / 已复核到 origin/main 读数），或按规则改成 origin/main 口径。 |
| 16 | 分支来路（准则 6b） | 🔵 | 两个新增边界分支（「`buildOf` 的 suggestion 为 null：不显建议条、不取键标签」与「等待态与回退态同时非空」）能指回上游本批与合并现场（可复现路径 = 合 `0b9e30a7`），但用例表未写来路。 | 用例表两行各加一句来路（上游本批哪个能力 / 哪个符号删改逼出该分支），使日后删分支时知道它守什么。 |

**计数**：🔴 0 · 🟡 9 · 🔵 7（共 16 条）。无 🔴 未决。

VERDICT: pass

## §4 用户批准（主 agent）

### 用户批准（上游合并实施）

- 2026-11-17 22:04 · 用户原话：**「批准」**——批准 `fork-deltas §5.1` 的四条规则与批档 §2 的 17 处解法进入实施。
- **批准范围**：10 个冲突档的解析 + 2 个移植档（`composer_message.dart` / `composer_view.dart`）+ 验证。不含 `thincoder/` 外仓、不含新功能。
- **现场状态**：工作树处于**合并进行中**（10 档带 `UU` 标记）。实施席在其中就地解析，**不得** `git merge --abort` / `git reset` / 切换分支。
- **提交权在主 agent**：实施席解完、analyze 与单测通过后交回，合并提交由本席落。
- **待复核项**：RTM 2-1 行——本批按规则二重写了它断言的文件，实施后须实跑该用例，结果写进 §5。

## §5 实施记录（eng-coder）

### 实施记录（上游合并 81 · 10 档 17 处）

**实施摘要**

合并工作树内就地解析 10 档 17 处冲突（四规则），另落 2 档编译 / 移植修复、RTM 11-1 行、第 3 节登记面合后复核。未动合并状态：10 档保持 `UU` 等父代理提交，未 `merge --abort` / `reset` / 切分支。

**逐档落法（对 §2 机制表）**

| 档 | 处 | 规则 | 落地形态 |
|---|---|---|---|
| `.gitignore` | 1 | 一 | 自有 `/thincoder/`、`/.thincoder/` 块在前，上游 `.wrangler/` / `.dev.vars*` / `.env` / `.env.*` 在后 |
| `lib/chat/chat_models.dart` | 1 | 一 | `editor_context.dart` 的 import / export 与上游 `reply_suggestions.dart` 的 import 并存 |
| `lib/models/secret_store_io.dart` | 1 | 一 | `process_host.dart` 与 `shell_command_io.dart`（`windowsPowerShell`）并存 |
| `test/images/image_tools_test.dart` | 1 | 一 | `copy_button.dart` 与 `host_tools.dart` 两条 import 并存 |
| `lib/settings/pages/browser_page.dart` | 1 | 一 | btest 四 helper（hosts / readonly / qaRoot）在前，上游 `_use` 在后，两者各自闭合；共用尾部 `}), );` 归 `_setQaRoot` |
| `lib/chat/widgets/chat_item_view.dart` | 1 | 四 | `AgentMessageCard(... session: fromSession)` + `UserMessageBubble(... contexts:, onContextMenu:)` |
| `lib/chat/chat_history_view.dart` | 1 | 二 | 见下方「行映射」三条 |
| `lib/chat/chat_session.dart` | 2 | 三·四 | 见下方「会话」两条 |
| `lib/chat/composer/composer.dart` | 5 | 三 | 五处全留委托；新增 `void clear() => _clearOf(this);` |
| `lib/chat/composer/session_model_picker.dart` | 3 | 四 | 等待态与回退态并存，见下方「picker」一条 |
| `lib/chat/composer/composer_view.dart` | — | 三 | 建议源改 `replySuggestions.firstOrNull`；`_buildInputsOf` 补 `session.fallbackModel` |
| `lib/chat/composer/composer_message.dart` | — | 三 | 新增 `_clearOf`（上游 `clear()` 体）；另两处已与上游同形，未改 |

**行映射（规则二，`chat_history_view`）**

- 上游 `itemBuilder(context, row)` 的 `row` = 行号；`final index = _rows[row]` 得项号。
- `KeyedSubtree(key: ValueKey(index))` 的键 = 项号；列表 `findChildIndexCallback` 按 `_rowOf(value)` 回行号，两侧一致。
- `_row(... child: _LiveItem(revision: _liveTick, live: index == _liveRow, build: () => _buildItem(index)))`；`_liveRow` = `_folds.rowOf(_contentCount - 1)`，`StepFolds.rowOf` 返回项号 ⇒ `live:` 两侧同为项号。

**会话（`chat_session`）**

- ① `modes` 保留 `_overlay.wrapModes(...)`，并入上游 `fallbackModel` / `endModelFallback`。
- ② `send()` 保留 `takesContext` 与 `_overlay.beforeSend(`；`notes` = `[...notes, ..._placeNotes(from), if (!takesContext && editor != null) ..._editorNotes(editor()), if (from != null) ..._suggestionNotes()]`。
- ③ 上游已删的 `userSent?.call()` 随之删除（档内 `userSent` 0 命中）。

**picker（`session_model_picker`，规则四）**

- label = `[_label(selected, options, fallback: fallback), if (waiting != null) modelsSwitchPending(waiting)].join(' · ')`。
- `foreground: fallback == null ? null : AppColors.caution`；tooltip 两侧都空留原值，否则 `[?tooltip, 等待句, 回退句].join(' · ')`。
- footers 保留上游「切回」项（`endModelFallback`）与自有 thincoder 模型页项。

**读数（本席实跑；工具链 `build/flutter-3475/flutter/bin/flutter.bat`，`.dart_tool/version` = 3.47.5）**

| 项 | 命令 | 结果 |
|---|---|---|
| 编译 | `flutter analyze --no-pub` | **error 0**；2 warning + 9 info |
| 冲突清零 | 10 档内 `<<<<<<<` / `^=======$` / `>>>>>>>` 逐档计数 | 全 0（`test/stash/stash_markdown_test.dart:15` 的 `==========` 是 markdown 分隔线） |
| 变更面单测 | `flutter test test/chat/model_picker_test.dart test/images/image_tools_test.dart` | **All tests passed（+33）** |
| history 结构面 | `flutter test test/chat/chat_history_rebuild_test.dart` | **All tests passed（+5）** |
| composer 面 | `flutter test test/composer_test.dart` | **2 挂**，逐条见下 |
| RTM 2-1（§4 待复核项） | `flutter test test/integration/chat_flows_test.dart --plain-name "2-1 the window out of sight while the reply streams"` | **All tests passed（+1）** |
| 上游包自带用例 | `cd packages/bao_markdown && flutter test` | **All tests passed（+64 ~3）** |
| l10n 键 | 四档 `grep -c` | `modelsSwitchPending` / `modelsFallbackHint`：en arb 各 2、zh arb 各 1、两个生成物各 1 |
| RTM 11-1 | 读 `test/RTM.md` | `11-1` · 「模型回退」逐字在盘；规模窗 11 → 12；用例体按设计未落地 |

**analyze 的 2 warning + 9 info 来路**

- 4 条 `unnecessary_import` 是 §3 明令禁删的上游行（自有 `host_tools.dart` re-export 覆盖同名符号）。
- 其余 5 条在 `claude_code_translator.dart` 与 `test/chat/session_overlay_test.dart` 的既有面，非本批引入。

**静态判据（`grep -c`）**

- `composer.dart`：`void clear()` = 1。
- `session_model_picker.dart`：`modelsFallbackHint` = 1 · `modelsSwitchPending` = 2 · `pendingModel` = 1。
- `chat_session.dart`：`fallbackModel` = 3 · `endModelFallback` = 1 · `_suggestionNotes()` = 2 · `userSent` = 0 · `_overlay.beforeSend(` = 1。
- `composer_view.dart`：`promptSuggestion` = 0 · `_suggestionKey` = 4。
- `composer_message.dart`：`_clearOf` = 1。

**两条失败（父代理已裁定：按 (a) 处置，本批不修）**

① **`caret is text-height, centered on the line, never clipped` —— 上游本批带入，与本批冲突解析无关。**

- 合并树读数：`Expected: 10.125 (±1e-10) / Actual: <9.875>`，失败点是空 composer 的 `expectCentered(0)`（`composer_test.dart:735`）。
- 复现路径第 1 步：在合前 HEAD `c2031a18` 建独立 worktree，单跑该用例 ⇒ `All tests passed!`。
- 复现路径第 2 步：把合并树的 `packages/bao_markdown/lib/src/editor/md_editor.dart` 与 `md_display.dart` 单独拷进该 worktree、其余一律不动 ⇒ 同一条用例复现 `9.875` vs `10.125`。
- 无关判据 a：本席写面 = 10 个 `UU` 档 + 两个拆档前端，全在 `lib/chat/**`；`packages/bao_markdown/**` 从未进本批冲突清单（自动合并）。
- 无关判据 b：上面第 2 步只换那两档即复现，冲突档一个没动。
- 无关判据 c：上游本批在那两档加的正是行盒 strut —— `strutStyle: _strutOf(lineStyle, force: !display.hasWidgets),`；该改动被上游自己的用例面覆盖且全绿（`+64 ~3`）。
- 量级：0.25 逻辑像素。本批未碰 `packages/bao_markdown/**` 与 `test/composer_test.dart`。

② **`an edit stays open while another conversation is visited from the sidebar` —— 既有失败。**

- 合前 HEAD worktree 单跑同样失败，形态是 semantics-tree 抛 4 次（`Node 3 is not in the tree and not the new root`、`Multiple exceptions (4) were detected`），非断言失败。
- 与前两批（`2026-11-15-approval-dropdown` §5、`2026-11-15-upstream-sync-6` §5）登记的同一行同形。

**第 3 节登记面合后复核（§2 任务 3，§3.1 numstat 口径）**

- 判据域 = 上游本批触碰的 **195** 档（`git diff --name-only 1987ad78 0b9e30a7`），逐档读 `git diff --numstat origin/main`（合后工作树）。
- 域内非零 **41** 档：38 档命中已有登记行，3 档是 l10n 生成物（§3.1 明文由 `app_en.arb` 行承载）⇒ **表外 0 档**。
- 复算脚本口径：`registered 38 · generated 3 · unregistered 0`。
- 各行实测 ≤ 该行预算，无超预算行。
- `composer.dart` 的 +124/−1494 是拆档把上游体内联移出所致，该行预算本就写「上游内联体不构成 fork 净增」。

**第 3 节补的 5 行（此前表外，本轮 numstat 查出）**

- `lib/chat/widgets/turn_footer.dart` +9/−4：`spentOnly` → `turnTokensSpentHint`。
- `lib/kernel/claude_code/process_transport_io.dart` +5/−1：`LocalClaude.locate(install: false)`。
- `test/chat/chat_history_rebuild_test.dart` +375/−2：重建计数用例面。
- `test/ide/lsp/install/mason_server_provider_test.dart` +6/−0：`@TestOn('!windows')`。
- `test/kernel_ui_test.dart` +46/−0：thincoder 页脚指向模型页的用例。

**第 3 节四条首次登记行的复核**

- 复核标记由「未复核」改为「已复核」，并写实读数。
- `.gitignore` 的预算列按合后读数改 +8/−0（合后 `.env.*` 归上游面，自有块 8 行）。
- 另三行读数与首次登记一致：`chat_item_view` +12/−5 · `browser_page` +98/−1 · `image_tools_test` +4/−4。

**改动面**

- 产品面（12）：`.gitignore` · `lib/chat/chat_history_view.dart` · `lib/chat/chat_models.dart` · `lib/chat/chat_session.dart`。
- 产品面（续）：`lib/chat/composer/{composer,composer_view,composer_message,session_model_picker}.dart` · `lib/chat/widgets/chat_item_view.dart`。
- 产品面（续）：`lib/models/secret_store_io.dart` · `lib/settings/pages/browser_page.dart` · `test/images/image_tools_test.dart`。
- 索引面（1）：`test/RTM.md`（第 11 节 + 11-1 行；规模窗 11 → 12；变更记录一条）。
- **表外（1，须报）**：`docs/design/fork-deltas.md` —— 第 3 节补 5 行表外登记 + 4 行复核状态。

**表外改动的理由**

- §2 任务 3 明写「合后按 §3.1 的 numstat 口径复核登记面；表外自有块先补第 3 节」。
- §3.1 的用例表把「非零而无登记行」定为「停止实施，先补表」。
- 该档笔权按 D1 属设计席，故一并上抛供裁；若判定应回设计席，删掉新增 5 行即可回落。

**内部审计与代码评审（轮次与终态）**

- explore 审计 1 轮：逐条比对 §2 机制表与 §3 登记行 ⇒ `VERDICT: no-drift`。
- advisor 代码评审 1 轮 ⇒ `VERDICT: changes-required`（🔴1 / 🟡1 / 🔵3）。
- 🔴 = §5 未落（即本段，已补）。
- 🟡 = `_submitOf` 与 `_clearOf` 收尾语句重复 —— **不改**，两条理由见下。
- 🔵#3（`_row` / `_hiddenRow` 注释把项号写成 row）已改。
- 🔵#4（§3 的 `chat_history_view` 行预算列被坐标对账说明占满）、🔵#5（§2「5 行新登记」与实落 10 行不等）属设计席笔面，未改，交父代理路由。
- 🔵#4 / #5 的行号与坐标见评审回执；本段只记处置，不复述其内容。

**🟡 不改的两条理由**

- 理由一：`_submitOf` 现体是上游本批 `_submit` 的逐字移植；规则三要的是把上游新体放进抽离档，改成调 `_clearOf` 反而离开上游体形。
- 理由二：上游 `_submit` 是否调 `clear()` 本轮无 git 只读面可证，记 `unverified`；下一轮合并按上游体核一次。

**修复轮与终态**

- 修复轮 1 轮：🔴 补本段、🔵#3 改注释。
- **未再跑第 2 轮评审**：两项修复都是记录与注释、无行为面，且 🔴 的解除由本段自身可读验证。此点如实记，不当作已验证。
- **终态：clean**（无遗留 must-fix；🟡 有书面处置，🔵 两条交设计席）。

**未落地 / 上抛**

- `[上抛·待裁]` `docs/design/fork-deltas.md` 第 3 节新增 5 行的笔权（D1 归设计席 vs §2 任务 3 派给实施席）。
- `test/integration/model_fallback_flows_test.dart` 的用例体：设计已定「行已定，用例体待假内核 harness」，本批不落地，与设计一致。
- 单测文件处置：本批**未新建**单测文件（改动面用例都跑在仓内既有档上），无「用完即删」的档要删。

**`[上抛·知会]` `_clearOf` 与 `_submitOf` 的一处有意的不同**

- `_clearOf` 不重置 `_dismissedEditor`，`_submitOf` 重置 —— 这是对的。
- `clear()` 的调用面是「建议回复从别处发出、本档清空」（`chat_screen.dart` 的 `if (_pickedReply == said) _composerKey.currentState?.clear();`）。
- 该路径没有本档的发送动作，编辑器上下文 chip 的「已划掉」状态不该被清。

## §6 验证与收口（父代理）

### 验证与收口（上游合并）

**父侧实跑与落盘**

- 合并提交：**`c1042ad6`**（17 处冲突解析 + 2 档移植 + 登记面复核 + RTM 11-1）。
- 冲突标记全库清零（`grep "^<<<<<<<" lib/ test/ packages/` 零命中）；未合并档 0。
- 与上游关系：领先 **249**、落后 **0**（上游 81 提交全部并入；`git rev-list --left-right --count origin/main...HEAD` 实测）。

**实施席交回的读数（本席复核过冲突清零与提交面）**

| 项 | 读数 |
|---|---|
| `flutter analyze --no-pub` | **error 0**（2 warning + 9 info，其中 4 条是 §3 明令禁删的上游 import） |
| 变更面单测 | `model_picker_test` + `image_tools_test` **+33 通过** |
| history 结构面 | `chat_history_rebuild_test` **+5 通过** |
| **RTM 2-1 实跑**（§4 硬要求） | **+1 通过**——行映射重写未破 2-1 的「冷却期 0 次重建 / 文本不变 / 恢复恰 1 次 / 偏移不变」 |
| `packages/bao_markdown` 自带用例 | +64 通过（~3 跳过） |
| l10n 四键 | en arb 各 2 · zh arb 各 1 · 生成物各 1 |
| 静态判据 | `void clear()`=1 · `userSent`=0 · `promptSuggestion`=0 · `fallbackModel`=3 · `endModelFallback`=1 |

**两条失败（如实记，均非本批引入）**

1. `test/composer_test.dart` 的 caret 用例：期望 10.125 / 实际 9.875（0.25 逻辑像素）。来路 = 上游本批新增行盒 strut；复现 = 合前 HEAD 通过、把合并树两档 `bao_markdown` 拷进 HEAD worktree 即复现。**台账 #258**。
2. `an edit stays open while another conversation is visited from the sidebar`：HEAD 上同样失败（semantics-tree 抛 4 次），与前两批 §5 同形，既有失败。

**集成面**：`test/RTM.md` 新增第 11 节 + `11-1`「模型回退」行，规模窗 **12 / 50–100**；用例体按设计不落地（待假内核 harness）。

**登记面复核**：判据域 195 档 · 域内非零 41 档 · **表外 0 档**（38 已有行 + 3 生成物）。

**暂缓批复核**：无。
