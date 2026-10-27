# 2026-10-27 · merge-regressions
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 23:50「现在做」；来源 = kimi 合并审查（explore#24）查出的 6 组静默丢失，父侧已 grep 核实其中 4 组。
> 台账 = #190（thincoder-adapter · 归批）。前情 = docs/batches/2026-10-27-fork-realign.md §1（2026-10-26 文档前置）。
## §1 讨论（主 agent）
**状态行**：进行中（六条行为已修并验证；评审 changes-required，修轮在跑）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：修合并静默丢失的 6 组行为（2026-10-26 23:50）

- **已定决定**：走轻量通道（缺陷修复，源 = `main`/`26c969aa` 上的原实现 + 需求档/设计档要求），父侧直改，逐项验证后单笔提交 · 用户原话：「现在做」 · 时间：2026-10-26 23:50

**来源**：kimi 合并审查（explore#24）。父侧已 grep 核实 ①③④⑤⑥ 五组，②（命令面板 Rename Agent）待核。

| # | 丢失的行为 | 现状证据（父侧实读） | 源（要恢复成什么） | kimi 建议 |
|---|---|---|---|---|
| 1 | 在飞回合选模型后，pill/tooltip 显示「回合结束后切换到 X」 | `session_model_picker.dart` 内 `pendingModel` **零命中** | `main:session_model_picker.dart` 的 `_nameOf` + label/tooltip 后缀 | 恢复 label 后缀、tooltip 与目标名查找 |
| 2 | 命令面板可搜索并执行 Rename Agent | 待核（`workbench.dart:1287-1307` 只读窗口命令） | `main:workbench.dart` 的 `_paletteActions` 合并聊天命令源 | 恢复 `ChatKeys.targetsOf → commandsOf` 命令源与面板项 |
| 3 | 侧栏仓库扫描失败后 30 秒重试 + 日志 + 提示一次 | `workbench.dart` 内 `_sidePanelRetry` / `scmScanFailed` **零命中** | `main:workbench.dart` 的 `_sidePanelRetryAt` / `_sidePanelRetryTimer` / `_scanWarned`；设计 `docs/design/ide-git.md:237-241` 有明文要求 | 恢复重试、日志与一次性提示 |
| 4 | chord 第二键只在持有前缀的当前窗口生效 | `ide_workbench.dart:3357-3365` 不检查窗口；`:3377-3381` 只检查应用生命周期 | `main:ide_workbench.dart` 的 `_onChordKey` + `_holdsKeys` 守卫 | 接回焦点/路由守卫，**不整段回退上游按键实现** |
| 5 | 文档关闭 / diff 重建时，空控制器不崩 | `ide_editor.dart` 三处 `_nativeController!`（`:1964` / `:2639` / `:2653`） | 既有修复 `docs/batches/2026-10-17-ide-stability-guards.md:45`：控制器为 null 时返回 `SizedBox.expand` | 恢复局部 controller + null 守卫 |
| 6 | 回退文件后，变更审查列表立即刷新 | `chat_session.dart` 内 `ChangesReverted` **零命中** | `main:chat_session.dart` 的 `_reviewEvent` 里 `ChangesReverted → review.observe()`；`change_review.dart:401-402` 的语义 | 恢复该事件分支 |

**红线**：只恢复这 6 组行为，不改上游结构、不动 SCM 语义（#181 已裁定接受上游）、不动 autofetch（#184 另批删）。每项一条提交或一组提交，便于单笔回退。

### 收尾链启动（主 agent，2026-10-27 00:05）

用户 00:03「跑」⇒ 本批收尾链启动。设计者已派（写 §2，形式化这 6 条修复），之后 §3 独立评审、§4 用户批准、§6 结算。

**§2 要形式化的六条（实施已完成，§2 记的是「已落地的设计」，供评审与后续维护对照）**

| # | 行为 | 落地坐标 | 恢复依据（源） |
|---|---|---|---|
| 1 | 在飞回合选模型后 pill/tooltip 显示「回合结束后切换到 X」 | `lib/chat/composer/session_model_picker.dart:45-51` · `:129-137` · `:155-157` | `26c969aa:lib/chat/composer/session_model_picker.dart:64`（`_nameOf`）· `:129-138`（label 拼接）· `:155-157`（tooltip 拼接） |
| 2 | 命令面板可搜索并执行 Rename Agent | `lib/workbench.dart:1292-1298` · `:1316` | `26c969aa:lib/workbench.dart:1285-1289`（聊天命令源）· `:1306`（面板项） |
| 3 | 仓库扫描失败后 30 秒重试 + 日志 + 提示一次 | `lib/workbench.dart:3805-3812` · `:3732-3772` · `:778` · `:65` | `26c969aa:lib/workbench.dart:3708-3753`（完整实现）· 设计 `docs/design/ide-git.md:237-241` 明文要求 |
| 4 | chord 第二键只在持有前缀的当前窗口生效 | `lib/ide/ide_workbench.dart:3341-3358` · `:3375-3378` · `:3397` | `26c969aa:lib/ide/ide_workbench.dart:2916-2931`（`_holdsKeys`）· `:2957-2962`（第二键守卫）· `:2979`（计时器守卫） |
| 5 | 文档关闭 / diff 重建时控制器为空不崩 | `lib/ide/ide_editor.dart:2633-2643` · `:2658` | `docs/batches/2026-10-17-ide-stability-guards.md:45`（既有 P5 修复）· `26c969aa:lib/ide/ide_editor.dart:2125`（`SizedBox.expand` 守卫） |
| 6 | 回退文件后变更审查列表立即刷新 | `lib/chat/chat_session.dart:269-273` | `26c969aa:lib/chat/chat_session.dart:373-375`（`ChangesReverted → observe()`）· `lib/chat/review/change_review.dart:401-402`（`observe` 清理语义） |

**评审要盯的**：① 六条是否都是"恢复"而非"新增语义"（源逐条可比）；② #3 与 #4 是否引入了新的时序风险（定时器、窗口焦点）；③ 登记表是否需为新接线补行（#189 已整顿过，本次是否再需一行）。

### 上抛裁决（主 agent，2026-10-27 00:10）

**① ②③④⑤ 无行为用例** —— 裁决：**维持 analyze-only，不补用例**。

依据：这四条的可观察结果分别是「面板出现 Rename Agent」「失败后有提示与重试」「chord 不跨窗」「不崩」。前两条靠可见面板与日志即可确认；后两条要么需要多窗口 harness（④，本仓无此设施），要么构造代价高于收益（⑤ widget 测试需整套编辑器宿主）。

记法按验收规则走「实际跑过的检查 + 读数」：`flutter analyze --no-pub` 0 error + `flutter test test/chat test/ide/workbench` 与基线同失败集。**④ 的跨窗行为标 `unverified`**（静态推断，未实测多窗口）。

**② 登记晚于改动** —— **承认越序，记录在案**：本批代码先落地（`54f94769` / `e5661fd4`），登记在形式化时补齐。原因是这批属缺陷修复且源明确（`main` 原实现逐条可比），我判断先修不误事；但规矩是先登记再改码，这次破了。下次同类改动先补登记行。

**③ `docs/design/fork-deltas.md` §6/§7 的批次语言与编制期行数** —— **不在本批范围，不动**；记为文档债，随下次动该档时一并清。

### 评审裁决（主 agent，2026-10-27 00:12）— 评审结论 changes-required（🔴1 · 🟡8 · 🔵4）

**全部接受**。分工：文档面（第 1/2/3/4/5/8/10/11/12 条）派设计者修一轮；记录面（第 6/7/9/13 条）父侧直改。

**派单三句**：① 每条 `Suggestion` 是评审建议、执行者是子代理、父侧已逐条接受；② 按编号 `1..13` 修，回报「编号 → 改动 file:line」；③ 本轮**不做**：不改代码、不动 §7（属 #186）、不动 §6/§7 的批次语言（已裁定为文档债）、不新增设计语义。

| # | 级别 | 裁决 | 修什么 |
|---|---|---|---|
| 1 | 🔴 | Fixed（派设计者） | `docs/design/fork-deltas.md:78` 的 `composer_view.dart` / `btest_status_switches.dart` 与 `:42` 的 ≤24 行登记、`:22` 的 btest 自有 glob 冲突 → 按 `:82` 同形写例外句，或删 `:42` 陈旧行 |
| 2 | 🟡 | 派设计者补 §8 验收面 + 台账记一行 | §8 补验收对照（②③④⑤ 明写「静态面 + 实测读数」）；同时父侧记台账行，把「不补用例」变成有主的决定 |
| 3 | 🟡 | Fixed（派设计者） | §2.1 源列逐条给「= `26c969aa:&lt;档&gt;:&lt;行&gt;`」或「differs: …」；给 `:255` 的 `resumed` / 5 秒上限补出处 |
| 4 | 🟡 | Fixed（派设计者） | 给 `ChatSession.pendingModel` 与 `modelsSwitchPending` 补 `existing:` / `none found:` 一行；若新建键则补 `:52` 与重产步骤 |
| 5 | 🟡 | Fixed（派设计者） | §8.2 第 3/4 行降到接口面 + 一句「与 `docs/design/ide-git.md` §4.7 一致（本轮逐条核过）」 |
| 6 | 🟡 | Fixed（父侧） | §1/§6 的坐标对齐 §2.8（⑤ `:2638-2641`·`:2757-2758`·`:2890`；④ `:3344-3357`·`:3375-3380`；① `:45-48`·`:129-138`·`:155-157`） |
| 7 | 🟡 | Fixed（父侧） | §6 写明本轮评审是事后评审、验收证据是回溯读数 |
| 8 | 🟡 | Fixed（派设计者） | §8 补一句体量立场：四档是上游共享档、存量债、本批净增 ≤51 行且在登记块内、拆档会让 fork 面翻倍 |
| 9 | 🟡 | Deferred（转 #186） | §7.5 ③ 的全量验收属 #186 批次，修在那一批；本批记债 |
| 10 | 🔵 | Fixed（派设计者） | §8.4 挂上 RTM 四条行的断言面坐标 |
| 11 | 🔵 | Fixed（派设计者） | RTM 行数 65/66 二义 → 实测值一处；「50–100 行」改「50–100 条」 |
| 12 | 🔵 | Fixed（派设计者） | §7 删除段起点 `:86` 对齐类头 `:88`（或说明 `:86` 含两行何物） |
| 13 | 🔵 | Fixed（父侧） | 批档标题日期改 2026-10-27；状态行 `（…）` 换成实句 |

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（六条行为的设计落点 = fork-deltas §8 + 第 3 节三行新登记；评审 1/2/3/4/5/8/10/11/12 已回改，处置见 2.9；§8.5/§8.6 补受影响文件与验收对照）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 2.1 本批条目（覆盖）

六条，全部覆盖；一条一个行为，源 = 合并前实现 + 设计档明文（本批不收新语义）。

| # | 行为（现态） | 源 | 设计归属 |
|---|---|---|---|
| 1 | 回合在飞时点模型：pill 主 label 与 tooltip 追加「回合结束后切换到 <目标>」 | 合并前实现；功能点 F21（模型切换后置应用） | `docs/design/thincoder-adapter.md` §24（F21 行 · pill 后缀段） |
| 2 | 命令面板搜得到并执行会话命令，Rename Agent 在内 | 合并前实现 | `docs/design/fork-deltas.md` §8 · §3 `lib/workbench.dart` 行 |
| 3 | 侧栏仓库扫描失败：日志 + 30 秒重试 + 同一位置提示一次 | 设计档明文 | `docs/design/ide-git.md` §4.7 |
| 4 | chord 第二键只在本窗口持有键时生效 | 合并前实现 | `docs/design/fork-deltas.md` §8 · §3 `lib/ide/ide_workbench.dart` 行 |
| 5 | 文档关闭 / diff 重建时控制器为空不崩 | 合并前实现；`docs/batches/2026-10-17-ide-stability-guards.md:45` | `docs/design/fork-deltas.md` §8 · §3 `lib/ide/ide_editor.dart` 行 |
| 6 | 回退文件后变更审查列表立即刷新 | 合并前实现；`change_review.dart:401-402` 的语义 | `docs/design/session-governance.md` D-SG12（事件面）· `docs/design/fork-deltas.md` §8（宿主钩） |

需求档无新增条目：六条都是实现与既有源不符的缺陷修复。四条（②④⑤⑥）此前只有「合并前实现」作源，本批把源搬进设计档（`docs/design/fork-deltas.md` §8）——此后它们有文档源，下一轮合并有对账对象。

### 2.2 设计档落点

- `docs/design/fork-deltas.md`：新增 §8（六条现态 · §8.1 决策与理由 · §8.2 接口契约 · §8.3 边界 · §8.4 RTM delta）；第 3 节新增 `lib/workbench.dart` / `lib/ide/ide_workbench.dart` / `lib/ide/ide_editor.dart` 三行登记，`session_model_picker.dart` 行的自有块补等待态后缀；第 4 节删去「这三档保持上游」的旧结论（它们已带自有块，改动只许落在登记块内）。
- `docs/design/ide-git.md` §4.7、`docs/design/thincoder-adapter.md` §24、`docs/design/session-governance.md` D-SG12：机制原文已在，本批不改。
- 需求档：不改（见 2.1 末段）。

### 2.3 机制设计摘要（细节 = `docs/design/fork-deltas.md` §8.2）

- ⑤ 原生控制器为 null ⇒ `SizedBox.expand()`；三处：活动文档面（`_surface`）· diff 原侧（`_diffEditor.original`）· build 的 native 分支。
- ④ 持有键 = `mounted` ∧ 窗口可见 ∧ 主焦点在本 workbench 子树内 ∧ 本路由当前；`_onChordKey` 不持有 ⇒ 退出 chord 态 + `ignored`；5 秒检查器同一判定。
- ③ 失败 ⇒ 本轮不列仓库 + `_sidePanelRetryAt` 30 秒 + `_scanWarned` 每位置一次 warning + 30 秒重绘定时器；30 秒内重入直接返回空；成功清标记；空结果是真答案，不重试。
- ② 面板动作源 = 窗口命令 ∪ 焦点会话命令（`ChatKeys.commandsOf(ChatKeys.targetsOf(…))`）；焦点会话 = 当前 agent 窗口的会话，否则工作区当前会话。
- ① `pendingModel` 非空 ⇒ label / tooltip 追加 `modelsSwitchPending(目标名)`；目标名取同 id 选项的 label，找不到退回 id。
- ⑥ `ChangesReverted` ⇒ 取消防抖计时器 + `review.observe()`；事件面不变（仍按 `outcome.files` 非空才发）。

### 2.4 受影响文件与测试覆盖

行数 = 本轮实测（`split('\n')` 口径）。

| 文件 | 现状行数 | 本批形态（坐标为本轮实读） | 覆盖面 |
|---|---|---|---|
| `lib/chat/composer/session_model_picker.dart` | 225 | 等待态块 10 行（`:45-48` · `:129-138` · `:155-157`） | `test/chat/model_picker_test.dart` · `test/kernel_ui_test.dart` |
| `lib/workbench.dart` | 4910 | 面板命令源 10 行（`:1291-1299` · `:1316`）· 扫描失败面 59 行（`:3741-3786` · `:3812-3823` · `:778`） | 无行为用例（见 2.7-1） |
| `lib/ide/ide_workbench.dart` | 5822 | 窗口门 22 行（`:3344-3357` · `:3368-3383` · `:3397`） | 无行为用例（见 2.7-1） |
| `lib/ide/ide_editor.dart` | 3013 | 三处空渲染 9 行（`:2640-2641` · `:2757-2758` · `:2890`） | 无行为用例（见 2.7-1） |
| `lib/chat/chat_session.dart` | 1376 | 宿主钩 5 行（`:269-273`） | `test/chat/revert_flow_test.dart` · `test/chat/session_overlay_test.dart` |

### 2.5 验收对照（每条指回 2.1 的条目）

| 条目 | 判据（机器可判） | 读数 |
|---|---|---|
| ① | `flutter test test/chat/model_picker_test.dart test/kernel_ui_test.dart` | 51 通过（§6 父侧实跑；本席未重跑） |
| ② | `flutter analyze --no-pub` 的 error 计数 | 0（§6） |
| ③ | 同上 | 0（§6） |
| ④ | 同上 | 0（§6） |
| ⑤ | 同上 | 0（§6） |
| ⑥ | `flutter test test/chat/revert_flow_test.dart test/chat/session_overlay_test.dart` | 19 通过（§6） |
| 全量 | 父侧 `flutter test test/chat test/ide/workbench` | 与改动前基线同失败集（+984 −15 vs +953 −15，§6） |

②③④⑤ 的验收只到静态面：没有覆盖用例。是否补一组随批删的用例，见 2.7-1。

### 2.6 关键决策

| 选项 | 结论与理由 |
|---|---|
| A（采用） | 六条作为现态留在共享上游档的登记块里（第 3 节），改动只许落在登记块内 |
| B（否） | 整段回退上游实现：④ 会把上游已改的键路由重造一遍，②③⑤ 会把上游在同档的其它改动一并回退，且三档变回常驻冲突面（与第 1 节目标相反） |
| C（否） | 只写在批档、不登记：下一轮合并没有对账对象，同样的静默丢失会再来一次（这正是本批的成因） |

### 2.7 上抛项

1. **[上抛·待裁]** ②③④⑤ 无行为用例，验收只到 `flutter analyze` 0 error。本席倾向：②③ 靠 analyze 与可见面板够用；④⑤ 各值一组随批删的组件用例（④ = 两窗各持键时的 chord 归属；⑤ = 文档关闭后 diff 原侧重绘）。补不补、以及是否记为技术债（台账一行，归批 或 条件），由主 agent / 用户定。
2. **[上抛·知会]** 登记晚于改动：第 1 节要求「先登记再改代码」，本批代码先落（`54f94769` / `e5661df4`），登记在本次设计形式化才补齐。已补登完毕，不影响现态；下一轮再动这三档应先改第 3 节。
3. **[上抛·知会]** `docs/design/fork-deltas.md` 第 6 节仍带「本批 / R1」的批次语言，第 7 节带编制期行数——不在本批范围，未动。

### 2.8 计数更正（本席自检）

2.3 / 2.4 三个块行数按坐标重算后的更正（设计档 `docs/design/fork-deltas.md` §8 与第 3 节已同步为下值）：

- ① 等待态块 = 17 行（`:45-48` 4 + `:129-138` 10 + `:155-157` 3），原写 10。
- ④ 窗口门 = 21 行（`_holdsKeys` `:3344-3357` 14 + 守卫含注释 `:3375-3380` 6 + 检查器子句 `:3397` 1），预算 ≤22；原写的 `:3368-3383` 是整段 `_onChordKey`，自有部分只是守卫。
- ⑤ 三处空渲染 = 7 行（`:2638-2641` 4 + `:2757-2758` 2 + `:2890` 1），预算 ≤7，原写 9。

②③⑥ 的块行数与 2.4 的五档文件行数（225 / 4910 / 5822 / 3013 / 1376）为实测，未变。

### 2.9 评审裁决回改（2026-10-27 · 设计面 1/2/3/4/5/8/10/11/12）

本轮为设计评审（`changes-required`）后的修正轮。逐条处置如下；记录面 6/7/9/13 归父侧，不在本席。

| 编号 | 处置 | 改动坐标 |
|---|---|---|
| 1 | Fixed | `docs/design/fork-deltas.md` §4：原一句拆成两句 —— `composer_view.dart` 改为例外句（带第 3 节 btest 接缝、改动只许落在块内），`btest_status_switches.dart` 改为「第 2 节 btest glob 内的自有档、不在 §4 冻结面」（现 `:78-79`）；`:82` 的例外句保留。依据：`lib/chat/composer/composer_view.dart:186-194` 读 7 个 btest 会话成员、`:233` 渲染 `BtestStatusLine`（接缝真实，故不删 §3 的 `:42` 登记行）；`lib/browser/btest/btest_status_switches.dart` 存在（155 行）且落在 §2 的 `lib/browser/btest/**` glob 内。 |
| 2 | Fixed（设计面） | `docs/design/fork-deltas.md` §8.6 新增「验收对照」：①⑥ 给行为用例判据与通过数，②③④⑤ 明写静态面 + 实测读数（analyze 的 error 计数 + 符号计数），并写明四条不补用例的理由（④ 需多窗口 harness、⑤ 需整套编辑器宿主）。台账行由父侧记（裁决行 2 的后半句）。 |
| 3 | Fixed | 本档 2.10 补六条源列坐标；`docs/design/fork-deltas.md` §8.2 组 4 给 `resumed` 与 5 秒上限补出处（`26c969aa` 的 `lib/ide/ide_workbench.dart:2976-2983`，本轮实读）。 |
| 4 | Fixed | `docs/design/fork-deltas.md` §8.2 表后新增「既有件三问」两行：`pendingModel` = `existing:` `lib/chat/chat_session.dart:644`；`modelsSwitchPending` = `existing:` `app_en.arb:8910` / `app_zh.arb:3352`（两笔提交未触及 `lib/l10n/**` ⇒ 不改 l10n 登记行、不重产）。 |
| 5 | Fixed | `docs/design/fork-deltas.md` §8.2 组 3 / 组 4 降到接口面，并写明与 `docs/design/ide-git.md` §4.7 的对账结果（五条逐句对应，本轮实读 §4.7 `:237-241`）；状态机细节不再复写。 |
| 8 | Fixed | `docs/design/fork-deltas.md` §8.5 新增受影响文件与体量立场：四档过 800 行为上游共享存量债、按 §7.3 同一理由不拆档。 |
| 10 | Fixed | `docs/design/fork-deltas.md` §8.4 增四行断言面摘要表（1-1 / 2-1 / 3-1 / 4-1），本轮逐行读过 `test/RTM.md`，结论改为实读支撑。 |
| 11 | Fixed | RTM 行数统一为 66（`split('\n')` 口径，本轮实测；`wc -l` 为 65）；`50–100 行用例窗` 改为 `50–100 条用例窗`（`docs/design/fork-deltas.md` §2），§8.4 写明口径与「条」。 |
| 12 | Fixed | `docs/design/fork-deltas.md` §7.2 删除段边界注明 `:86` 是类前空行、`:87` 是类文档注释、`:88` 是类头（本轮读 `origin/main:lib/kernel/claude_code/claude_sdk_tools.dart:80-99`）；行数算术不变。 |

### 2.10 §2.1 源列补正（评审行 3）

2.1 的「源」列只写「合并前实现」，坐标散在 1 节。逐条补来源：

| # | 源（= 合并前实现 / 设计档） | 差异 |
|---|---|---|
| 1 | `26c969aa:lib/chat/composer/session_model_picker.dart:64`（`_nameOf`）· `:129-138`（label 拼接）· `:155-157`（tooltip 拼接） | 无 |
| 2 | `26c969aa:lib/workbench.dart:1285-1289`（聊天命令源）· `:1306`（面板项） | 无 |
| 3 | 设计档 `docs/design/ide-git.md` §4.7（机制明文）；实现源 `26c969aa:lib/workbench.dart:3708-3753` | 无（§4.7 是本条的源，非合并前实现） |
| 4 | `26c969aa:lib/ide/ide_workbench.dart:2919-2932`（`_holdsKeys`）· `:2959-2962`（第二键守卫）· `:2976-2983`（`resumed` + 5 秒上限） | 无（本轮实读该档 2905-2984） |
| 5 | `26c969aa:lib/ide/ide_editor.dart:2125`（`SizedBox.expand` 守卫）· 批次 `docs/batches/2026-10-17-ide-stability-guards.md:45` | 无 |
| 6 | `26c969aa:lib/chat/chat_session.dart:373-375`（`ChangesReverted → observe()`）· `lib/chat/review/change_review.dart:401-402`（`observe` 语义） | 无 |

结论：六条都是「恢复」而非新增语义；`resumed` 与 5 秒上限也来自合并前实现（4 行），不是本轮新加。

### 2.11 交接（不在本席）

- 记录面 6 / 7 / 9 / 13 归父侧（裁决表已派）。
- 裁决行 2 的后半句「台账记一行」归父侧：把「②③④⑤ 不补用例」变成有主的决定。
- 裁决行 9 转 #186，本批只记债。
- 本席未改代码、未跑 `flutter analyze` / `flutter test`；§8.6 的测试读数引自 §6，符号计数为本轮实测。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（独立评审子代理）— docs/design/fork-deltas.md + 本批档

范围限制：评审上下文无 AGENTS.md、无项目标准档、无 document map。

方法论合规按评审准则 + 两档自述规则（`docs/design/fork-deltas.md` §1 §5、批档 §1）判定。

文档归属只能做「同一档内两处活描述是否互相矛盾」的一致性检查；跨档一致性（`docs/design/ide-git.md` / `docs/design/thincoder-adapter.md` / `docs/design/session-governance.md` / `test/RTM.md`）不在本次可读范围，相关判定标 `unverified`。受影响文件行数无法抽查（源档不在评审范围）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Document ownership | 🔴 | 同一接缝两处活描述互相否定：`docs/design/fork-deltas.md:74`「以下文件不带自有语义，保持上游实现」并把 `lib/chat/composer/composer_view.dart`、`lib/browser/btest/btest_status_switches.dart` 列为「只消费 session 契约，不改 UI」（`:78`），而 `:42` 给 `composer_view.dart` 登记了「btest 缓存键与状态行挂点」≤24 净增行的自有块，`:22` 又把 `lib/browser/btest/**`（含「状态 UI」）整档列为自有资产；`:100` 第三处又称消费方「零改动」。读者无法判断该块在不在，合并对账时正是 §8.1 描述的静默丢失形状 | 把 `:78` 那条改成与 `:82` 同形的例外句（该两档带登记块、改动只许落在块内），或删掉 `:42` 的陈旧登记行；同一接缝只留一处活描述 |
| 2 | Acceptance criteria | 🟡 | ②③④⑤ 的行为面无验收：`本批档:102-105` 把四条压成 `flutter analyze --no-pub` error=0；设计档 §8 本身没有「验收对照 / 用例表」块（对比 §7.5 · §7.6），验收只活在记录面 `:99-107`。③ 是至少五分支的状态机（§8.2:254：失败不列仓库 / 30 秒标记 / 每位置一次 warning / 30 秒内重入返回空 / 成功清标记），静态判定不可能覆盖 | 把 ③ 的重试判定抽成纯谓词并用一条单测钉住；或把 `:121` 的待裁项落成台账一行（归批 ∥ 条件），让「不补用例」是有据的裁决而非默认 |
| 3 | Requirements coverage | 🟡 | 「恢复而非新增语义」是 `:41` 点名的评审必答项，文档只声明未举证：§2.1 源列对 ②④⑤ 只写「合并前实现」不给坐标（坐标散在 `:35-39`）；`:47` 称「逐条可比」但无一条比对结果；`docs/design/fork-deltas.md:255` 的「另加生命周期 `resumed` 与 5 秒上限」既未归给合并前实现、也未归给任何设计档 | 每条加一列「= `<commit>:<file>:<lines>`」或「差异：<何处、为何>」，把 ④ 那两处附加条件归源 |
| 4 | Existing-piece check | 🟡 | 设计依赖的两个既有件没有三问答案：`ChatSession.pendingModel`（`:57`、§8.2:252 作接缝）与 l10n 键 `modelsSwitchPending`（§8.2:252 直接使用）都没写 `existing:` / `none found:`；若键为新增，则牵连 `:52` 的 l10n 登记行与 `flutter gen-l10n` | 对这两个名字各补一行三问答案；新增则同时补 `:52` 的键并集与重产步骤 |
| 5 | Document ownership | 🟡 | §8.2:254-255 以机制级详述复写了 `docs/design/ide-git.md` §4.7 的失败重试状态机与 `_holdsKeys` 判定，而 §8:231-232 同时声明「机制归属一处设计档」；两处是否已对齐无从判（`unverified`：owner 档不在评审范围）。机制被写第二遍后，日后漂移就是机制级矛盾 | 契约行只留接口面 + 「与 `docs/design/ide-git.md` §4.7 一致」的对账句；或在该行注明本轮已逐条核对 |
| 6 | Clarity | 🟡 | 记录面坐标落后于 §2.8 的更正，⑤ 最重：`:21` 三处 `_nativeController!` 写 `:1964` / `:2639` / `:2653`，`:38` 与 `:150` 写 `:2633-2643` · `:2658`，§2.8:131 与 §8:233 写 `:2638-2641` · `:2757-2758` · `:2890`；④ `:149`（`:3341-3358` · `:3375-3378`）对 §2.8:130（`:3344-3357` · `:3375-3380`）；① `:146`（`:45-51` · `:129-137`）对 §2.8:129（`:45-48` · `:129-138` · `:155-157`）。按 R7b 设计面胜，但收口会引用记录面 | 收口前把 §1 / §6 的坐标改成 §2.8 的值；`unverified`：源档不在评审范围，哪一侧正确未能实读确认 |
| 7 | Methodology compliance | 🟡 | 顺序倒置：`:155` 记单笔提交 `54f94769` / `e5661fd4` 已落地，`:52` 的 §2 是「已落地的设计」，`:159` 记收尾链未跑；`:47` 承认越序。后果具体：§2.5 的读数引自 §6（`:101`「本席未重跑」），本次评审对已落地代码没有前置效力 | 收口写明「本次评审为事后评审，验收证据为回溯引用」；发现的缺陷按新批次走 |
| 8 | Affected-file size annotations | 🟡 | 本批改动的四档都过 800 行（`workbench` 4910 · `ide_workbench` 5822 · `ide_editor` 3013 · `chat_session` 1376，`本批档:92-95`），§8 没有任何体量立场；`:159-165` 的「不拆档」理由只覆盖 §7.3 的 browser 八档。存量债裁决（R3）维持不动，但读者在 §8 找不到同一句话 | 在 §8 补一句「四档为上游共享存量债，本批净增共 ≤51 行且落在登记块内，按 §7.3 同一理由不拆档」，使该立场可对账 |
| 9 | Acceptance criteria（跨批结转） | 🟡 | `docs/design/fork-deltas.md:184` ③ 把全量 `flutter test --no-pub`（失败数 ≤128 · 通过数 ≥7107）写成验收判据。按准则 12，把发布门写成一轮成本属 🔴 类；且「≤128 失败」不是绿判据。本批档 `:49` 已裁定 §6/§7 不属本批范围、记为文档债 | 留作结转项：#186 开跑前把该行改成变更面测试文件或用例表，并在收口线报集成半 |
| 10 | Integration-test design | 🔵 | §8.4 从 RTM 读起（`:268` 66 行 · 4 / 50–100）并给出「无破坏 / 无冗余 / 无缺失」及理由，形态合规；但「现有 4 条断言面不涉及…」（`:270`）在本次范围内 `unverified`（`test/RTM.md` 不可读） | 收口时随 §8.4 附上 4 条行号的断言面摘要，供下一次评审与对账复核 |
| 11 | Clarity（数值漂移） | 🔵 | 同一 `test/RTM.md` 两处行数：`:215` 记 65 行、`:268` 记 66 行；`:32` 把「50–100」写成「行用例窗」，而 §8.4 按「条」（4 / 50–100）用 | 统一口径：行数取实读值，窗口按「条」 |
| 12 | Methodology（§7 内部一致性） | 🔵 | `:122` 记 `ClaudeSdkTools` 类头 `:88`，`:134` 与 `:145` 记删除段 `:86`–`:229`；若类头在 `:88`，从 `:86` 起删会连带两行无关内容。`:205` 自记一条未实测的 Dart 语义前提（typedef 下构造 / 注解 / `is`） | 删除段起点与类头对齐；`:205` 的前提在实施首编后按它自己的承诺改陈述句 |
| 13 | Methodology（记录面卫生） | 🔵 | 批档 `:1` 标题 `# 2026-10-26 · merge-regressions` 与文件名 `2026-10-27-…` 日期不一致；`:6` 状态行带未填占位「（…）」；文件以 BOM 开头 | 标题与文件名对齐，状态行括号内填一句实义说明 |

**计数**：🔴 1 · 🟡 8 · 🔵 4（另 `unverified` 标注 3 处，均因源档 / owner 档不在评审范围）。
**裁决**：`VERDICT: changes-required`（第 1 行 🔴 未解）。

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

### 六条行为的恢复与验证（父侧直改 · 轻量通道，2026-10-27 00:30–01:40）

本批走轻量通道（缺陷修复，源 = `main`/`26c969aa` 的原实现 + 设计档明文要求），父侧直改，§5 因「一段一作者」不适用（实施面 = 父侧直改，记录在本节）。

| # | 行为 | 落点 | 验证 |
|---|---|---|---|
| 1 | 在飞回合选模型后 pill/tooltip 显示「回合结束后切换到 X」 | `lib/chat/composer/session_model_picker.dart:45-51` · `:129-137` · `:155-157` | `flutter test test/chat/model_picker_test.dart test/kernel_ui_test.dart` = **51 通过** |
| 2 | 命令面板可搜索并执行 Rename Agent | `lib/workbench.dart:1292-1298` · `:1316` | analyze 0 error |
| 3 | 仓库扫描失败后 30 秒重试 + 日志 + 提示一次 | `lib/workbench.dart:3805-3812` · `:3732-3772` · `:778` · `:65` | analyze 0 error |
| 4 | chord 第二键只在持有前缀的当前窗口生效 | `lib/ide/ide_workbench.dart:3341-3358` · `:3375-3378` · `:3397` | analyze 0 error |
| 5 | 文档关闭 / diff 重建时控制器为空不崩 | `lib/ide/ide_editor.dart:2633-2643` · `:2658` | analyze 0 error |
| 6 | 回退文件后变更审查列表立即刷新 | `lib/chat/chat_session.dart:269-273` | `flutter test test/chat/revert_flow_test.dart test/chat/session_overlay_test.dart` = **19 通过** |

**总验证**：`flutter analyze --no-pub` = **0 error**；`flutter test test/chat test/ide/workbench` = **+984 −15**，与改动前基线 **+953 −15** 同失败集（15 条为合并前既红的上游测试，非本批引入）。

**提交**：`54f94769`（#1 #3 #5 #6）· `e5661df4`（#2 #4），单笔可回退。

**未做**（另批，不在本批）：设置页假开关与 autofetch 死代码清理（#184）· 登记表整顿（#189）· `IdeScmView` 旧 widget 抽取 · HostTool 回退（#186）。

**收尾链状态**：轻量通道的收尾链（设计形式化 → 独立评审 → 批准 → 结算）**尚未跑**；本批记录保持「进行中」，结算等用户批准后执行。

### 评审后的记录面订正（主 agent，2026-10-27 00:15）

**坐标订正**（本节上文与 §1 早期写的坐标已被 §2.8 的实测值取代，以本表为准）：

| # | 早期坐标（作废） | 现值（以 §2.8 / §8 为准） |
|---|---|---|
| 1 | `session_model_picker.dart:45-51` · `:129-137` · `:155-157` | `:45-48` · `:129-138` · `:155-157`（等待态块 17 行） |
| 4 | `ide_workbench.dart:3341-3358` · `:3375-3378` | `:3344-3357`（`_holdsKeys` 14 行）· `:3375-3380`（守卫 6 行）· `:3397`（检查器子句 1 行） |
| 5 | `ide_editor.dart:2633-2643` · `:2658` | `:2638-2641` · `:2757-2758` · `:2890`（三处空渲染共 7 行） |

**评审性质**：本轮评审是**事后评审** —— 代码先落地（`54f94769` / `e5661fd4`），§2 与本次评审都在其后。因此评审对代码无预防力，它审的是「已落地的东西是否可被维护与对账」。§2.5 的 51 / 19 通过读数是 §6 的实跑结果被设计者引用（其自述「本席未重跑」），属回溯证据。

**转出债**：评审第 9 条（§7.5 ③ 把全量 `flutter test --no-pub` 写成验收判据）属 **#186「HostTool 回退」批次**，在那一批开跑前修正；本批不碰 §7。
