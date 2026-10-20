# 2026-10-19 · ForgeRef.parse 对坏百分号转义崩溃（轻渠道缺陷修）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 运行时未捕获异常（`flutter run` 会话 bash#6 结束时）：`FormatException: Missing extension byte (at offset 11)` ← `Uri.decodeComponent` ← `Uri.pathSegments` ← `ForgeRef.parse`（`lib/forge/forge_ref.dart:177`）；触发链 `ThincoderEvents.optionsFrom → emitInfoChanged → ChatSession._apply → Workspace.notifyListeners → StashThreads._sync → stashPullsIn → ForgeRef.allIn`。
> 台账 = #95（forge · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
**本笔披露**：This pen = light channel（defect fix — 运行时崩溃）| change: `ForgeRef.parse` 给 `uri.pathSegments` 加 `FormatException` 护栏（坏 `%` 转义 ⇒ 返回 null，不再抛）| reach: `lib/forge/forge_ref.dart` + `test/forge/forge_test.dart` 一条用例 | rollback = revertable
**本批条目**：① 修复 `ForgeRef.parse` 对坏百分号转义的未捕获异常（`FormatException: Missing extension byte`），使聊天文本里的坏 URL 只当作「不是页面」。
**关键判据**：`ForgeRef.parse('https://github.com/o/r/pull/7%')` / `'.../%zz'` ⇒ `null`（不抛）；`ForgeRef.allIn` 含坏 URL 的文本 ⇒ 零结果；既有合法页面用例不变。
**授权口径**：本轮无用户指令，属缺陷即时修（运行时崩溃，触发链见抬头）；修复范围只此一处。

**落笔（2026-10-19 03:45）**：`lib/forge/forge_ref.dart:176-186` — `uri.pathSegments` 包 `try/on FormatException`，坏 `%` 转义 ⇒ `return null`（不抛）；`test/forge/forge_test.dart:50-55` — 新增用例：`.../pull/7%` / `.../%zz` ⇒ `null`，`allIn` 含坏 URL ⇒ 空。

**走查读数（机检）**：
- `flutter test --no-pub test/forge/forge_test.dart` ⇒ **16/16 全绿**（含新用例）
- `flutter analyze --no-pub lib/forge/forge_ref.dart test/forge/forge_test.dart` ⇒ **No issues found**（24.7s）

**影响面**：`ForgeRef.parse` 的唯一变化是「坏 URL 从抛异常变为返回 null」；合法页面解析逐字不变（既有 15 条用例全绿）。触发链上 `StashThreads._sync` 不再因一条坏 URL 让整次通知抛未捕获异常。

**冻结**：本笔只改上述两档；工作树其余部分不动。

**收尾链**：待跑（设计形式化 → 独立评审 → 批准 → 核销）。

**设计形式化（收尾链 · 2026-10-19）**：`ForgeRef.parse` 的契约补一条——**任何无法安全解码的 URL（含坏百分号转义）一律返回 `null`**，不抛异常；其余解析（GitHub / GitLab / Gitee 形、尾标点剥离、去重）逐字不变。兜底位置 = `uri.pathSegments` 的 `FormatException` 捕获（`lib/forge/forge_ref.dart:176-186`）；不引入新的校验分支、不改调用方（`allIn` / `stashPullsIn` 零改）。回退 = 删除该 try/catch，恢复原抛异常行为。

**评审修正（2026-10-19，按 advisor code #63 建议）**：用例补强——加 `%E4` 两条（合法转义 + 非法 UTF-8，即线上崩溃的真实类别，命中 `pathSegments` 的 `FormatException`）；注释改为真实机制（stray `%` 在 `Uri.parse` 阶段被改写成 `%25`，不会到达 `pathSegments`）。复跑：**16/16 全绿**、`flutter analyze` 两档 No issues。

> 不适用：§2 —— 轻渠道缺陷笔，无独立设计段（契约见本节「设计形式化」）。
> 不适用：§3 —— 设计评审不适用；收尾链独立评审 = advisor code（#63，pass，0🔴/1🟡/2🔵，🟡 与两 🔵 均按建议处置）。
> 不适用：§4 —— 用户 2026-10-19 19:45「收掉吧」已授权收口，无单独批准段。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**验收读数**：`flutter test --no-pub test/forge/forge_test.dart` ⇒ **16/16 全绿**（含 `%E4` 两条真崩溃类断言）；`flutter analyze --no-pub lib/forge/forge_ref.dart test/forge/forge_test.dart` ⇒ No issues。

**独立评审**：advisor code #63 ⇒ **pass**（0🔴 / 1🟡 / 2🔵）。🟡 = 新用例未命中护栏（已按建议补 `%E4`）；🔵 = 注释机制失真（已改）+ 只捕 `FormatException`（当前无缺陷，注释已写明「只接收 `Uri.parse` 产物」）。

**范围外登记**：`lib/ide/terminal/links/terminal_link_resolver.dart:89` 只兜 `ArgumentError`，`:71-72` 的 `Uri.decodeComponent` 对同类输入抛 `FormatException` ⇒ 台账 #97。

**状态**：已收口 2026-10-19。
