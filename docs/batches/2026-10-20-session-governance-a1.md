# 2026-10-20 · 会话治理 A1：rename + 回合级文件回退
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 00:02「拆两拨做吧，允许 rename」+ 00:06「按建议写…也许你有更好的想法」——revert 改走内核撤销栈。
> 台账 = #104（session-governance · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-20
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**状态行**：🔄 进行中（设计完成待评审）

**本批条目**：需求档 `docs/requirements/session-governance.md` 的 **F1 会话重命名** + **F2 回合级文件回退**（A1）。A2（rewind）已拆出为 #105 条件项。

**关键判据**：六条能力门 = `RenamesSession` / `RevertsChanges`（Claude 已实现，thincoder 本批补）；单源 = 内核（槽标题 + 撤销栈），宿主不建第二份快照；revert 语义 = 「从该回合起」，与 `RevertsChanges.revertChanges(sinceTurn:)` 契约一致。

**授权口径**：用户 2026-10-20 00:02「拆两拨做吧，允许 rename」——A 拆分 + 允许动 `thincoder/` 外仓（B1 例外，最小接口改动、保持上游可合并）；00:06「按建议写」确认 F1/F2 需求草案。

**对设计上抛的处置（父侧，2026-10-20 00:17）**：
1. 外仓写入面：**已授权**（同上 B1 例外）。实施按两段走——外仓段与宿主段各一轮，均在同一批内；外仓段首轮先 `git diff` 存基线，只加本批 hunk。
2. 需求 F2.2「同一份快照」的读法：**取设计的读法 = 同一实现（进程内撤销栈），不做跨进程共享**；需求档 F2.2 已补一句限定。「终端改过的文件桌面能回退」不在本批，若需要另立需求。
3. 两仓工作树基线：实施首轮各存 `git diff` 基线（本批只加 hunk），父侧在交付核验时对照。
4. 标题上限 **80**（与终端 `/rename` 同源）——接受，不改。
5. 批档 §1 = 本段（设计未代写，符合分工）。

**修正轮 1 核验（父侧，2026-10-20 00:30）**：14 项落点抽验通过——§3.5 后置态（`_titleTarget/_titleDeferred/_titleSending`，发送前置判据「`_turn == null && _pendingAuto == null && !_titleSending && !_releaseWanted`」；超时只兜病理竞态）；投影带回合（`canRevertNow` / `revertPlan(String sinceTurn)` / `applyRevert(String sinceTurn)`，门 = 能力 × 空闲）；§6 A1 行已拆核侧（G19）/ 宿主侧（G1·G1b·G9）；⑲ `thincoder_mock.dart` 实测 **668**（node 换行计数核过，非 PowerShell 计数）⇒ 预算 ≤703。

**存量漂移记录**：适配档 §5.2 的现值行仍写 `thincoder_mock.dart` 632（差 36）与 `kernel_types.dart` 610（现 615）——属该档存量漂移，随 §4.1 ㉑ 的文档编辑一并修正（R1/R7a：本批不代改）。

**实施期上抛裁决（父侧，2026-10-20 00:47）**：eng-coder #89 报「设计内部相抵：挂起窗内用户回合的 turnId」。实况：`session/prompt` 在窗内走 `window.submit(input)`，`thincoder-cli/src/acp/suspension.mjs:154-160` 只收 text/images/done ⇒ turnId 丢；`execTurn` 按「自动轮继承上一键」，宿主的 `session/revert` 对该 turnId 得 `-32602 unknown turn`。

裁决 = **(a) 按已批准设计交付**（该档设计写明零改动）：区间语义本身正确（「从上一回合起」的回退仍覆盖该回合的写入），缺口仅「该回合不能单独作为回退起点」。已记台账 **#106**（技术待办，归批 A1 之后；修法 = +6 行透传）。未改设计、未扩范围。

**宿主段轮次划分（父侧，2026-10-20 00:55）**：H1 内核层（#90，6 档）· H3 l10n（#91，5 档）并行；H2 UI 层（10 档）等 H1。**用例归属修正**：任务书 H1 列的 G3 实属 `inline_rename_field`（UI 层）⇒ 移交 H2；G11 按设计 §7 = 宿主「部分成功映射」（mock files 1 + failed 1），留 H1。H1 范围 = G1 / G1b / G4–G8 / G11（+ G5–G7 接线）。

**轻渠道笔（2026-10-20 02:22，走查当场指出的问题 → 缺陷修）**

- **披露**：本笔 = 轻渠道（③ 走查发现）｜改动：`lib/workbench.dart:1276` 的 `_paletteActions()` 加一行 `?action(ChatCommandIds.renameAgent, Codicons.edit)`｜触达：命令面板「操作/全部」的搜索与动作清单（Rename Agent 从此可搜到）｜回滚 = 删该行（单行，可逆）。
- **根因**：命令本身存在（`chat_screen.dart:445`）且绑了 F2（`chat_keybindings.dart:382`），但 `_paletteActions()` 是手写白名单，未列该 id ⇒ 面板搜不到；双击 / 右键 / F2 三条手势一直可用（用户已逐条验证）。
- **读数**：`flutter analyze lib/workbench.dart` → No issues。
- **走查记录（真机）**：改名三手势（双击 / 右键→Rename / F2）用户已验可用；命令面板缺项即本笔所修。回退与在飞态两项走查**未做**，待用户继续。

**用户裁定**：2026-10-20 02:21「直接修改这个问题，不计入了」——不在台账另记。

**轻渠道笔（续，2026-10-20 02:35，走查复报「还是没有 Rename Agent」）**

- **首笔无效的根因**：`_paletteActions()` 的 `action()` 取命令 = `run ?? commands[id]`，而 `commands = _chatCommands()`（窗口命令表）**不合并聊天窗口自有命令**——`renameAgent` 只存在于 `ChatScreen.chatCommands`（`chat_screen.dart:445`）⇒ 传入的 `?action(...)` 求值为 null 被过滤。首笔只加了一行，未接通命令源。
- **本笔**：`lib/workbench.dart:1259-1265` 起，`_paletteActions()` 按按键分发同款取到焦点聊天命令（`ChatKeys.targetsOf(_chatKey(thread).currentContext)` → `ChatKeys.commandsOf(chat)`），`action()` 的命令源改为 `run ?? commands[id] ?? chatCommands[id]`；`renameAgent` 行保留。
- **读数**：`flutter analyze lib/workbench.dart` → No issues。**未重建**（app 在用户手里，等其发话）。
- **走查新读数**：用户 2026-10-20 02:34「现在 baocode 和终端命名是可以通过 session 切换来更新名字的」⇒ **A1 的①（同标题）通过**；②回合回退 / ③在飞态仍待验。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（设计档 = docs/design/session-governance.md；外仓执行面与「同一份快照」读法待裁）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

| # | 需求条目 | 本批落地 |
|---|---|---|
| 1 | F1.1 任意会话可改标题（含运行中，不打断回合） | ACP `session/set_title`（排队）+ 宿主三处 inline 改名入口；未打开会话走目录短命连接 |
| 2 | F1.2 单一来源 = 内核会话记录（终端 `session list` 与桌面同值） | 写路径 = 核 `renameSlot`（槽文件 + manifest）；桌面列表重读目录；宿主 `_names` 只留作无改名能力内核的兜底 |
| 3 | F1.3 手改标题粘住（自动标题不覆盖） | `agent.title` 同拍赋值（核 `ensureSessionTitle` 空短路）+ 宿主自动标题器对 thincoder 关闭（`GeneratesTitles`） |
| 4 | F1.4 空白标题拒绝并保留原值 | inline 字段 validator（空 / >80，行内提示）+ 核 `-32602` 兜底 |
| 5 | F2.1 任一已结束回合「从该回合起」回退 | ACP `session/revert {sinceTurn}`；回合键 = prompt `turnId` + `execTurn` 单点铸 ordinal（自动轮继承） |
| 6 | F2.2 单一来源 = 内核撤销栈，不建宿主快照 | 全部读写都落 `agent._undoStack`；宿主只调 ACP，不持有备份 |
| 7 | F2.3 创建态回退 = 删除 | 每个文件按最旧条目 `backup === null` ⇒ `delete` |
| 8 | F2.4 回合后被改过的文件跳过并列出 | 条目新增写后哈希（sha256 原始字节）；现状不符 ⇒ `skipped: changed` |
| 9 | F2.5 超限 / 逐出条目如实列「无法回退」 | oversize 判据在前 + 逐出路径记入回合索引 `lost` ⇒ `unrevertable` |
| 10 | F2.6 回退前弹确认（文件数 / 清单 / 丢弃提示） | 内核先 `dryRun` 出计划，确认框按计划展示；取消 ⇒ 零写入 |
| 11 | F2.7 与 Git 无耦合 | 纯文件级快照写回，不碰 Git |
| 12 | A6 Claude 非回归 | Claude 内核零改；新增能力走可选接口 `PlansReverts`，旧 `undoAllChanges` 路径保留 |

### 设计档落点

- 新板块主档：`docs/design/session-governance.md`（机制 / 接口契约 / 受影响文件 / 决策 / 验收对照 / 用例 / 边界 / UI / 未核实）。
- `docs/design/thincoder-adapter.md`：§3.4 方法表加一行指针、§4 F2 加一行指针（D2 单源，不重复机制）。
- 外仓设计档同拍义务（由主 agent 执行）：`thincoder/docs/cli/design/ACP-CLIENT.md` §2.1 + 新小节；`TUI-COMMANDS.md` §5.3 一行；`SESSION.md` §6.7 一行。

### 机制设计（一句一条）

1. ACP 增 `session/set_title {sessionId,title}`、`session/revert {sessionId,sinceTurn,dryRun?}`，`session/prompt` 增可选 `turnId`；两者默认排队、不进 FIFO 豁免白名单（ACP-CLIENT §3.1 三条判据不覆盖；排队同时避开与回合尾整档 save 的交错）。
2. 核内：撤销条目扩为 `{seq, turn, ordinal, tool, path, displayPath, backup, oversize, timestamp, after}`；新增回合索引 `agent._undoTurns`（key → firstOrdinal / paths / lost，上限 50）。`beginUndoTurn` 住 `execTurn` 单点；`recordUndoAfter` 在工具返回后逐路径读回。
3. 快照路径面改用核内单源 `toolTouchPaths` 并收窄到 `FILE_MUTATORS`：修掉 `apply_patch` / 批量 `edit` 不入栈的既有缺口（`/undo` 同病）。
4. 回退算法：按文件分组；最新条目 `after` 校验现状，最旧条目 `backup` 作为恢复值；组间按最新 `seq` 降序；逐文件失败隔离；成功才出栈，跳过 / 失败保留（可重试）。
5. 宿主：`PlansReverts`（计划 + 执行）、`GeneratesTitles`（内核自有标题）、`RenamesStoredSessions`（目录改未打开会话）；`ChatSession` 投影 `revertTurn` / `canPlanRevert` / `revertPlan()` / `applyRevert()` / `ownsTitle`；`ThincoderCatalog` 走短命连接改名。
6. UI：沿用 inline 改名字段（加 validator）与 ActivityStrip「Undo all」；新增用户消息右键「Revert files from this turn…」（复用既有选择右键菜单先例）；确认框按内核计划列文件 / 跳过 / 无法回退，取消为默认项；结果框 + 会话内 `NoticeItem` + `ChangesReverted`。
7. 「同一份快照」口径 = 同一实现 / 同一模块（进程内 `agent._undoStack`），非跨进程共享对象（终端与桌面各一进程）。

### 受影响文件与测试覆盖

- 本仓 18 档（`agent_kernel` / `kernel_types` / `thincoder_kernel` / `thincoder_catalog` / `chat_session` / `chat_screen` / 新 `revert_dialog` / `chat_history_view` / `user_message_bubble` / `inline_rename_field` / `workspace` / 四个改名调用点 / `ide_agent_edits` / l10n 两源 + 三生成 / 测试三档），逐档现况行数与 ≤±N 见设计档 §4.1。
- 外仓 11 档（`undo-stack` / `dispatch-run` / `session-rename` / `cmd-session` / `acp/session` / `handlers-session` / 新 `handlers-session-meta` / `acp.mjs` / 三份设计档 / 零留存测试档），见设计档 §4.2；`handlers-session.mjs` 477 行只加 prompt 透传（≤489），两个新 handler 落新档以守 500 行硬限。
- 测试：本仓 G1–G12（内核 / 目录 / 宿主投影三档）；外仓 G13–G20（纯函数 + 假传输，随批次档、收口删除）。集成面：无业务场景新增（桌面与终端共用同一 ACP 面，既有 e2e 冒烟覆盖握手→提示→收尾；回退真机走查见设计档 §6 A3–A7）。

### 验收对照（回指 A1–A7）

A1 → G1 / G2 / G9；A2 → G3 / G4；A3 → G5；A4 → G6；A5 → G7；A6 → Claude 既有测试零改哨兵；A7 → G10。逐条判据与落点见设计档 §6。

### 关键决策（编号见设计档 §5）

D-SG1 方法名与形状 · D-SG2 回合标识（key + ordinal，自动轮继承）· D-SG3 写后哈希（sha256 原始字节）· D-SG4 逐文件分组 / 逆序 / 部分成功 · D-SG5 确认框以内核 dryRun 计划为准 · D-SG6 自动轮归属其前 prompt 回合 · D-SG7 快照面改 `toolTouchPaths` · D-SG8 标题粘住 = 写槽 + `agent.title` + 关宿主标题器 · D-SG9 闭会话改名走目录短命连接 · D-SG10 两方法排队不豁免 · D-SG11 跳过 / 失败条目保留 · D-SG12 结果面 = 结果框 + notice + `ChangesReverted` · D-SG13「同一份快照」= 同一实现非共享对象。被否选项逐条在设计档内。

### 未覆盖项

1. 对话回退（rewind / 编辑已发消息）与 fork：需求档 §3 明列范围外（A2 批 / 未立项）。
2. 逐文件挑选回退：需求 §3 明列不做；v1 只做「从某回合起」全量。
3. `file_ops` move / rename 不入快照（不在 `FILE_MUTATORS`）：设计档 §8 / §10 U3 登记为后续判定项。
4. 撤销栈不跨进程 / 不落盘：进程释放或重启后回退返回未知回合（与终端 `/undo` 同口径）；持久化不在本批。
5. 二进制文件与 >10MB 单条不可回退：沿用既有撤销栈双上界（需求 F2.5 明写）。
6. 跨进程并发改名的 `mtime-conflict`：如实报错、用户重试；不做自动合并。

### 上抛项

1. **[上抛·待裁] 外仓写入的执行面**：本批范围含 `thincoder/`（用户 2026-10-20 00:02 已准 B1 例外），但子代理写外仓属越界（「子代理只写本仓」）——设计档 §4.2 已给外仓逐档坐标与预算，实施轮的**外仓部分需由主 agent 执行**（或主 agent 明确另行授权方式）。本设计未写外仓任何文件。
2. **[上抛·知会] 两仓工作树均有他批未提交改动**：本仓 `lib/kernel/agent_kernel.dart` / `kernel_types.dart` / `thincoder_kernel.dart` / `chat_session.dart` / `workspace.dart` 等，外仓 `acp/handlers-session.mjs` / `acp/session.mjs` / `suspension.mjs` / `transport.mjs` / `session.mjs` 等均为 `M`。实施首轮须按 `git diff` 存基线、只加本批 hunk（形同 `thincoder-adapter.md` §22.12 的开工前对齐），否则会把他批改动混入本批 diff。
3. **[上抛·知会] 批档 §1 仍为空占位**（仅模板行）：本设计所依据的需求与已知事实来自需求档 `docs/requirements/session-governance.md` 与本轮派单；按六段边界 §1 属主 agent，未代写。
4. **[上抛·待裁] 需求 F2.2「同一份快照」的读法**：设计取「同一实现 / 同一模块、不建宿主快照」，非跨进程共享内存栈（每会话一进程，物理上不可共享）。若用户原意是「终端改过的文件，桌面也能按终端回合回退」，则需撤销栈落盘 + 跨进程标识，另立需求。
5. **[上抛·知会] 需求 F1 未写标题长度上限**：设计取 80（与终端 `/rename` 一致；核自动标题规范是 ≤40，属生成面不是手改面）。若用户要求更短，仅改单源常量。

### 修正轮 1（设计评审 #85 · 14 项处置）

评审 2🔴 / 8🟡 / 4🔵 逐条处置（号 → 落点；行号 = 设计档 `docs/design/session-governance.md` 现况）：

| 号 | 处置 | 落点 |
|---|---|---|
| 🔴1 | 取 **(a) 后置态**：`_titleTarget` / `_titleDeferred` / `_titleSending`——回合在飞只记目标（last-wins）、`_endTurn` 收尾发送、迟到回报经下一次 `session/list` 自愈；`session/revert` 在飞时两处入口不可用（`canRevertNow`）。被否 = (b) `noTimeout` + 可见等待态（写卡住永久占位，适配档 §24.1 D98 同判据）、加 FIFO 豁免 | L47（§2.2 对齐⑤，含 §24.1 先例与被否）· L188（§3.4 时序）· L209（新 §3.5）· L305（D-SG14）；用例 G1b（L331） |
| 🔴2 | 投影携带回合：`revertPlan(String sinceTurn)` / `applyRevert(String sinceTurn)`；`canPlanRevert` = 能力 × 空闲（`PlansReverts.canRevertNow`），不以宿主 pending 为门；「该回合有核内记录」由 dryRun 空计划回答（「无可回退」）。被否 = 新增核侧只读判据；被否 = 以 `revertTurn != null` 为门 | L146（接口）· L178（§3.3 投影）· L188（§3.4）· L307（D-SG15）；G12（L342） |
| 🟡3 | §6 拆「核侧（外仓 G13–G20）/ 宿主侧（本仓）」两栏；A1/A3/A4/A5 核侧重指 G13–G20（真目录 + `undoApply` + 落盘断言），本仓 G1/G5–G7 收敛为接线 / 映射断言 | L312（§6）· L324（§7 两张表） |
| 🟡4 | §4.1 增 ㉑：适配档 §10 删「回退 / 改名」、§3.4 `session/prompt` 补 `turnId?`、§7 B1 例外与批次名册补本批、§5.2 缝行注明；按 R1/R7a 只报不改（他板块档） | L62（survey 同仓档）· L259（㉑） |
| 🟡5 | `/undo` 口径改「增量而非零变」：单步粒度、50 条 / 64MB 消耗速率与深度变化写明；**接受** + 判定条件 U6 | L49（偏离①）· L87（预算）· L366（§8）· L404（U6）· L310（D-SG18） |
| 🟡6 | 逐出账改范围口径：`Map<path, highestEvictedOrdinal>`（路径 + 回合下界）；索引逐出 / apply 后空键 / 无前键造键三规则；各配用例 | L80（§2.4 规则）· L126–140（§3.2）· L308（D-SG16）；G17（L352）/ G18（L353） |
| 🟡7 | 键位补至 **20**（2 校验 + 5 入口 + 4 组名 + 4 reason + 3 ICU 摘要 + 2 提示）；en +85 / zh +22；生成档各 +45 | L252（⑭）· L253（⑮）· L384（§9 键表） |
| 🟡8 | 宿主标题器门用例（thincoder 零调用 / Claude 照旧）入 §7 与测试预算 | L258（⑳）· L332（G2） |
| 🟡9 | §4.1 增 ⑲ `thincoder_mock.dart`（实测 668，≤ +35 ⇒ ≤703；>500 且 <800 不立缝） | L257（⑲）· L286（§4.3） |
| 🟡10 | routed 写后值 = 请求内容哈希（不读回）；U1 收窄为本地写半边 | L137（§3.2）· L294（D-SG3）· L309（D-SG17）· L399（U1）；G15（L350） |
| 🔵11 | §3.1 写两方法会话解析：`set_title` = 磁盘槽位、无需活跃会话；`revert` = 活跃会话 + 栈命中 | L114 |
| 🔵12 | 结果路径形态 = 绝对路径 + 可选 `displayPath`；样例与 `RevertFile` / `RevertSkip` / `RevertFailure` 对齐 | L103（样例）· L113（口径）· L168（§3.3 类型） |
| 🔵13 | 缝候选行注明「本批 +175 后再评估」（预算自 +135 上调，含标题后置态） | L285（§4.3）· L259（㉑） |
| 🔵14 | 可改名内核的 `_names` 不参与显示与落盘；代码形态实读闭合（`workspace.dart:527` 确先读 `_names`；写点 `:2667`） | L185（§3.3）· L249（⑪） |

**自检读数**（三向交叉）：

1. 引用集 ↔ 标题集：本档 §N 引用全部落在本档 §1–§10 / §2.1–2.4 / §3.1–3.5 / §4.1–4.3；§24.1 / §5.2 / §10 均带「适配档 `thincoder-adapter.md`」前缀（外部指针）。
2. 表行 ↔ 汇总计数：§7 共 21 行（G1、G1b、G2–G20）= 宿主 13 + 核 8；§4.1 用例分布 ⑯ 9 / ⑰ 1 / ⑱ 2 / ⑳ 1 = 13，与宿主表一致；l10n「20 键」= 键表 2+5+4+4+3+2。
3. 断言 ↔ 实测：新增读数均本轮实测（`thincoder_mock.dart` 668 · `test/workspace/agent_title_test.dart` 40 · 设计档 405 行）；其余现况行数沿用本档编制日读数（实施首轮复核）。
4. 行宽 / doc_check：设计档 0 行 >300；`doc_check` 命中 46 条全在他档（设计档零命中；批档在扫描排除区），与改前一致。

**被否选项汇总**：`set_title` 不设超时 + 等待态 · FIFO 豁免 · `canPlanRevert` 以 `revertTurn != null` 为门 · 新增核侧只读「有没有改动」查询 · 按键记 `lost` · 一律读回 · 按工具调用分组预算。

状态行保持「设计完成」。

### 修正轮 2（设计评审 pass 后 2 条 🔵）

轮 2 结论 = pass（前表 14/14 Fixed），新增 N1 / N2 两条 🔵；父侧裁决 = 收掉再进 §4。本轮单点修正、无新语义。行号 = 修正后设计档 `docs/design/session-governance.md` 现况（406 行）。

| 号 | 处置 | 落点 |
|---|---|---|
| N1 | 补计数键 `revertFileCount`（ICU 复数 `=0` / `=1` / `other`），§9 确认框正文改引该键；键表 20 → **21 键**（2 校验 + 5 入口 / 确认 + 1 计数 + 4 组名 + 4 reason + 3 摘要 + 2 提示）；⑭ 预算 en +85 → **+89** / zh +22 → **+23**；⑮ 各 +45 → **+48** | L379（确认框）· L384（键表头）· L390（键行）· L252（⑭）· L253（⑮） |
| N2a | `canRevertNow` 引用面两处 `（§3.4）` → `（§3.5 末条）`（在飞门的规范条文住那里：`_turn == null && _pendingAuto == null` + 两处入口同判据）；**另发现同句第三处同病**（§3.1 超时条「`revert` 要求在飞门（§3.4）」）一并改 —— 同一条发现的同类残留，非新语义 | L5（§1 结论行）· L147（`PlansReverts` 注释）· L115（§3.1 超时条） |
| N2b | §6 A1 宿主列补 G2（F1.3 宿主半边 = 自动标题器门），与 §2「验收对照」的「A1 → G1 / G2 / G9」对齐（原设计档是该链的离群点） | L316（§6 A1） |
| N2c | ㉑ 的「§7 B1 例外与批次名册」改为「档头批次名册（`:5`）+ §7 B1 例外」——名册实住适配档档头分批行（`thincoder-adapter.md:5`），§7 `:398` 是 B1 例外与覆盖链 | L259（㉑） |

**自检读数**（三向交叉）：

1. 引用集 ↔ 标题集：本档 `§N` 引用逐条存在（§1–§10 / §2.1–2.4 / §3.1–3.5 / §4.1–4.3）。改后 `§3.4` 仅剩两处且都对（㉑ 指适配档 §3.4；A7 落点 = §3.4 的取消径零写入）；`§3.5 末条` 四处（L5 / L115 / L147 / L365）全指在飞门。
2. 表行 ↔ 汇总计数：键表 7 行 = 2+5+1+4+4+3+2 = **21 键**，与表头「21 键」、⑭「21 键」一致；⑮ **+48** = ⌈21/20 × 45⌉（47.25 向上取整）；⑭ 的 en +89 / zh +23 = 旧值 + 一条复数键（ARB 1 行值 + en 的 `@` 占位元数据 ≈ +4；zh 只值 ≈ +1）。
3. 断言 ↔ 实测：设计档 405 → **406 行**（+1 = 新增键行）；最长行 **294 字符**，0 行 >300；`doc_check` = **46 条命中、全在他档、本档零命中**（与改前读数一致）。
4. 落点回读：L5 / L115 / L147 / L252 / L253 / L259 / L316 / L379 / L384 / L390 十处逐行读回，无残留旧值（`20 键` / §3.4 误指 / 旧预算均不在盘）。

另记一条存量观察（非本批动作）：§9 的摘要句仍是「3 条 ICU 复数片段」，指的是会话内 `NoticeItem` 的摘要（`revertSummary*` 三条），与新增的确认框计数键不冲突 —— 4 条复数键 = 3 摘要 + 1 计数，两处口径已对齐。

状态行保持「设计完成」。

### 实施期收口（设计面 · 2026-10-20）

依据 = 父裁 2026-10-20 01:26（三处漂移 + 两处实测回填）+ eng-coder #91 交付表。只动下列 5 处设计档 + 外仓三档登记；需求档 / 代码零改。行号 = 改后 `docs/design/session-governance.md`（423 行，逐处回读）。

| 号 | 性质 | 落点（设计档 · 改后行） | 回读 |
|---|---|---|---|
| 漂移 1 | §4.1 ③ 把「会话内 `NoticeItem` + `ChangesReverted`」记在内核档，§9 同文案归宿主 ICU 键 | L242：删 `NoticeItem`；`ChangesReverted` 注「仅 `outcome.files` 非空时发；摘要归宿主 §9」 | 内核档不再产出摘要 notice；摘要 owner = 宿主（§9 三键） |
| 漂移 2 | §3.4 结果面 / D-SG12 按「无条件发」读 | L206–207（通知标为宿主步骤 + `ChangesReverted` 条件发：全跳过 / 全失败不发）· L306（D-SG12 同条件 + 宿主待处理清单保留） | 与 §4.1 ③ 三处同口径 |
| 漂移 3 | `canRevertNow` 缺「有可用连接」 | L147（接口注释：`_running` = 连接非空且就绪）· L230（§3.5 末条：`_turn == null && _pendingAuto == null && _running`） | 两处同判据；与实现 `_running` 一致 |
| 回填 A | l10n 实测（#91） | ⑭ L253：en +42（⇒ 7283）/ zh +21（⇒ 2842）· ⑮ L254：+126 / +99 / +99（⇒ 17122 / 10474 / 9908）· L262 原因句（gen 体式：抽象档每成员 6 行、impl 每复数方法 12 行） | 五档现况行数本轮实测（`split('\n').length`） |
| 回填 B | §9 键表补逐键 en / zh 值 | L389–411（21 行；值 = 本档 §5 交付表） | 逐键比对 21/21 全等（en / zh） |

**外仓三档（B1 授权；只加登记与指针，不复制机制段）**

| 档 | 落点 | 内容 |
|---|---|---|
| `thincoder/docs/cli/design/ACP-CLIENT.md` | §2.1 表 L43–44 + 新 §2.4（L65–70） | 两扩展方法登记（形状 / 错误面 / 会话解析 / 排队）；§2.4 写队列归属与 `prompt.turnId`；形状单源 = 本设计 §3.1 |
| `thincoder/docs/cli/design/TUI-COMMANDS.md` | §5.3 `/undo` 条 L142 | 语义增量：条目逐触达路径 / 次、单步 = 单路径、可回退深度随 50 条 / 64MB 预算缩短 |
| `thincoder/docs/core/design/SESSION.md` | 新 §6.27（L1001–1007） | 回合标识 `{key, ordinal}` / 写后哈希（routed 用请求内容、本地读回）/ 逐出账 `Map<path, highestEvictedOrdinal>`；形状与算法指本设计 §2.4 / §3.2 |

**落点裁定**：`SESSION.md` 的登记位置经父侧 2026-10-20 01:26 回复裁定 = (a) 在该档末尾新增 §6.27（原 §6.7 = 会话标题生成，与撤销栈非同一机制；§6.7 未动，「手动重命名链零改」仍成立——新 ACP 入口复用 `renameSlot` 契约，登记在 ACP-CLIENT）。

**自检读数**：

1. 行宽：设计档 423 行，0 行 >300（外仓新增行最长 289）。
2. `doc_check`（本仓）：**46 条命中，全在他档，本设计档零命中**（与改前读数一致）。
3. 外仓 `doc_check` 首轮读数含本批 3 条跨仓 `锚·档缺`（`docs/design/session-governance.md` 在 thincoder 仓不可解析）⇒ 三处指针改为「桌面仓 `baocode` 设计档 `session-governance`」不带 `.md`；本批新增行 `.md` 锚 token 实测 **0**（不新增档缺）。
4. 一致性：`ChangesReverted` 条件在 §3.4 / §4.1 ③ / D-SG12 三处一致；`canRevertNow` 在 §3.3 / §3.5 两处一致；§9 键表 21 行逐键值 = 本档 §5 表（脚本比对 21/21 全等）。

状态行保持「设计完成」。

**追加一处（父裁 2026-10-20 01:33，随本轮落地）**

| 项 | 落点（设计档 · 改后行） | 回读 |
|---|---|---|
| §4.1 新增 ㉒ `activity_strip.dart`（「Undo all」在飞灰态 + `revertTurnInFlight` tooltip） | L261（现况 **520** 实测 ⇒ ≤ +5 ⇒ ≤525）；同档从 L265 零改动清单移出 | `PanelButton` 带 `tooltip` 参数（`lib/chat/panels/interaction_panel.dart:947-962`，已实读）；坐标按实际路径 `lib/chat/panels/activity_strip.dart`（派单写 `lib/ide/activity_strip.dart`，实盘无此档，全仓唯一 `activity_strip.dart` 在 `lib/chat/panels/`） |
| §9 右键项禁用形态 | L381：ActivityStrip 灰显 + tooltip ∥ 右键项 = **不出现**（只在 `canPlanRevert` 时构建；菜单面无 tooltip，不改 `ide_menu.dart`）；同句补「且有可用连接」与 §3.3 / §3.5 对齐 | 两处入口形态不再相抵；`lib/ide/ide_menu.dart` 实存、未动 |

**终态读数（以此为准）**：设计档 **424 行**、0 行 >300；`doc_check`（本仓）**46 条，全在他档，本设计档零命中**；§9 键表 21 行逐键值 = 本档 §5 表（脚本比对 21/21 全等）；外仓三档新增行 `.md` 锚 token = 0。

状态行保持「设计完成」。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审：A1 会话治理（rename / revert）· docs/design/session-governance.md

评审口径：设计档 + 需求档 + 适配档三档实读；无 AGENTS.md / 无 document map（标准面与归属面降级判定，已在报告中声明）。外仓（`thincoder/`）源文件不在评审可读范围 ⇒ 其对位断言一律按 unverified 处理，不计入发现。

通过项（不占发现位）：设计档在场；需求 F1.1–F1.4 / F2.1–F2.7 / A1–A7 均有落点；§2.2 最近先例（对齐 4 条 ∥ 偏离 3 条，逐条给理由与被否方案）在场；§2.3 survey 证据在场且「公开源：无新增」已记录；§4.1/§4.2 受影响文件逐档带现况行数 + 预算，逐行算术自洽（481+26=507 / 615+50=665 / 1122+135=1257 / 1223+34=1257 / 1272+28=1300 / 3691+45=3736 / 1134+12=1146 / 95+26=121 / 2835+48=2883 / 936+8=944 / 3844+230=4074 / 189+70=259 / 62+210=272 / 186+14=200 / 43+4=47 / 191+18=209 / 477+12=489 / 185+3=188）；外仓 500 行硬限处置正确（handlers-session.mjs 477→≤489 + 新档 ~110）；§10 风险登记（U1–U5）在场。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Feasibility / Requirements | 🔴 | 「运行中改名」走默认队列 + 连接缺省 60s 超时 ⇒ 回合 >60s 时请求被桌面丢弃、却被核在回合尾执行：`session-governance.md:284` 定「运行中改名：允许提交；标题在回合结束生效（排队）」+ `:234` D-SG10 自认该代价；但 `thincoder-adapter.md:3115`「连接缺省超时 60s；`session/prompt` 走 `noTimeout`，其余请求照缺省」，且 `:3116` 已实测同类写「回合在飞时点模型 ⇒ 写排在 prompt 之后、超 60s 被桌面丢弃」而核随后照常执行。结果 = §3.4 的失败面「`session-governance.md:158` 失败 ⇒ 会话内 NoticeItem(error)（值保持原样）」变成假失败：桌面显示旧标题并报错，核已改标题 ⇒ A1（桌面 ∥ `session/list` 同值）不成立；`_pendingTitle` 只覆盖「会话未建」，不覆盖「回合在飞」。§2.2 未引同仓最近先例（批 14 §24 D95–D98 的 `_modelDeferred` / `_modelSending` / last-wins 后置应用状态机） | 为标题引入与 §24.1 同形的后置态：`pendingTitle` + 发送位 + 迟到回报自愈（`config_option_update` 式通知或下一次 `session/list` 刷新），或对 `session/set_title` 显式不设超时并给出可见等待态；`session/revert` 同属该路径（回合在飞时被点）一并裁定 |
| 2 | Clarity / 接口契约 | 🔴 | 宿主投影无法表达「从某一回合起」：内核面有参（`session-governance.md:126` `Future<RevertPlan> revertPlan({required String sinceTurn});`），宿主投影无参（`:148`「`Future<RevertPlan> revertPlan()`、`Future<RevertOutcome> applyRevert()`」），而 `:285` 的入口 ② 要求「从该回合起」，`:162` 的时序也只调无参 `revertPlan()` ⇒ 入口 ② 只能落到 `revertTurn`（最早待处理回合），静默改范围，违 F2.1「对任一已结束的回合」。另 `:148` 的 `canPlanRevert` 以「内核为 `PlansReverts` 且 `revertTurn != null`」为门，即以宿主 pending 列表为真值源，与 D-SG5（`:229`「宿主 pending 列表会少列 ⇒ 弹窗说谎」）自相矛盾；「该回合有内核记录的改动」这一显示判据在契约里没有任何读面 | 让宿主投影携带回合参数（`revertPlan(String sinceTurn)` / `applyRevert(String sinceTurn)`），并补「该回合是否有核内记录」的只读判据（核侧查询或空计划探测）；`canPlanRevert` 不得以宿主 pending 列表为门 |
| 3 | Acceptance | 🟡 | A1/A3/A4/A5 的机检指向无法验证其所断言的层：`session-governance.md:243`/`:245`/`:246`/`:247` 把 A1–A5 指向 G1/G5/G6/G7，而 `:191` 把这些用例放在 `test/kernel/thincoder_kernel_test.dart`；该档以 `ThincoderMock` 假传输驱动，既不能改「槽文件 title」（G1 断言）也跑不了核内 JS 撤销栈与真实临时目录（G5「`undoApply` 后逐文件断言」、G6/G7）。具备该能力的是 `:211` 的外仓批次档（G13–G20） | 把 A1/A3/A4/A5 的机检重新指向外仓批次档的对应用例（真目录 + `undoApply`）与 ACP 面 `set_title` 落盘断言；本仓 G1/G5–G7 收敛为「宿主接线与投影」断言，并在 §6 表里分列「核侧 / 宿主侧」两栏 |
| 4 | Document ownership | 🟡 | 同机制在两档不一致且无档位接单：`thincoder-adapter.md:460`「❌ 各项不做（图片直传 / 多文件夹 / fork / 回退 / 后台任务 / MCP 管理 / 账号用量 / 建议类 / 改名」与本批（改名 + 回退）直接相抵；`:398` 的 B1 例外清单与 `:5` 的批次名册均未含本批；`:107` 的 `session/prompt` 行仍写 `{sessionId, prompt: [...]}`，未含本批新增的可选 `turnId`（`:112` 已给两扩展方法指针 ⇒ 同一档内亦不自洽）。设计档 §4 没有任何一行指向 `docs/design/thincoder-adapter.md`，即残留矛盾无处置位 | 在 §4.1 增加一行 `docs/design/thincoder-adapter.md`：§10 边界删去「回退 / 改名」、B1 例外与批次名册补本批、§3.4 的 `session/prompt` 行补 `turnId?`（R1/R7a：报告后由父侧文档层修正） |
| 5 | Document ownership / 自洽 | 🟡 | 设计自述互相打架：`session-governance.md:45`「`/undo` 的既有语义零变。」与同段落的偏离 ② 相抵（`:47`「现实现根本不为它入栈 ⇒ 桌面回退会漏掉整类写入，`/undo` 同病」）——条目由「单路径/次」扩为「逐触达路径/次」后，`/undo` 的单步粒度与 50 条 / 64MB 预算的消耗速率都变（一次 `apply_patch` 由 0–1 条变成 N 条），即终端可回退深度实质缩短。`cmd-undo.mjs` 零改动（`:213`）只说明代码未动，不等于语义未变 | 把该句改成「条目形状对 `/undo` 是增量，但单步粒度与回退深度随触达路径数变化」，并把 50 条 / 64MB 预算的影响与拟采取的补偿（或明确接受）写进 §2.4 / §10 |
| 6 | Clarity / Requirements（F2.5 · A5） | 🟡 | 逐出记账的边界未定，且记账口径窄于查询口径：`session-governance.md:108` 新增 `agent._undoTurns`「按 key 去重、上限 50」但未定逐出规则（逐哪端、条目仍在栈里的 key 被逐出会怎样——是 `-32602 unknown turn` 还是 `unrevertable: evicted`）；`:119` 的 `lost` 记在「其 key」名下，而 `:60` 的查询范围是「`ordinal >= key.firstOrdinal`」跨后续多键 ⇒ 只出现在后续回合、且已被逐出的路径，既不在计划里也不在 `unrevertable` 里，与 F2.5/A5「如实报出、不假装成功」相抵；此外 apply 成功后条目全清空的 key 再回退是「空计划」还是「未知回合」也未定；`beginUndoTurn` 在「无 `turnId` 且无上一键」（先于任何 prompt 的自动轮）时行为未定 | 把逐出记账提到「按路径 + 回合下界」的范围口径（或查询时用 `lost` 的并集 + 逐出序号判定），并写明索引逐出规则、apply 后空键语义、无前键时的造键规则；三者各补一条 G 用例 |
| 7 | Clarity（l10n） | 🟡 | 文案清单短于自身 UI 决定：`session-governance.md:189` 只列 8 键（en +34 / zh +8），而 `:286`–`:288` 要求确认框正文含跳过 / 无法回退分组、结果框含「恢复 / 跳过 / 无法回退 / 失败四组计数与清单」、会话内一条带计数的摘要句（「Reverted 3 files · skipped 1 (changed) · 1 cannot be reverted」）；「恢复」「失败」两个组名、四类 reason（changed / oversize / evicted / after-unknown）的显示名、摘要句的复数形态都没有键位 | 补键（组名 2–4 个 + reason 4 个 + 摘要句复数 1 个），并同步调 `:189` 的 en/zh 预算与 `:190` 的生成档增量 |
| 8 | Acceptance（F1.3） | 🟡 | 「粘住」只测了核侧一半：§6 A1 行把判据落在 G1/G2/G9，G2 断言的是核内 `ensureSessionTitle` 早退；宿主第二个写者（`:131` 新增的空标记接口 `GeneratesTitles`、`:148` 的 `ownsTitle` 投影、`:186` ⑪ 的自动标题器门）没有任何用例（G12 只覆盖 revert 投影） | 补一条宿主侧用例：thincoder 会话的自动标题器零调用（`GeneratesTitles` / `ownsTitle` 真），Claude 会话照旧调用；列入 §7 与 §4.1 对应测试档预算 |
| 9 | 受影响文件清单 | 🟡 | 缺一行：G1–G12 全部依赖 mock 对端应答 `session/set_title` / `session/revert`（`:243` G1「假传输收 `session/set_title`」、`:259` G5 等），而 `lib/kernel/thincoder/thincoder_mock.dart`（适配档 `:283`，~350 行）既不在 §4.1 表里，也不在 `:195` 的零改动清单里 —— 若需脚本化两个新方法即为漏记档（带预算） | 在 §4.1 增一行（现况行数 + 增量）；若判定零改，把该档移进 `:195` 的「零改动」清单并说明脚本化机制已够用 |
| 10 | Acceptance risk（§10 U1） | 🟡 | 硬验收依赖未验证的读回时序且修法被推到另立：`session-governance.md:295` U1 自认「若 `after` 读到的仍是旧内容 ⇒ 回退会误报 `changed`」而修法是「另立」；A3/A4 正建立在 `after` 真值上。routed 写在核侧本就知道所写内容（`fs/write_text_file` 反向请求的 params），可不经读回直接得哈希 | 把「routed 分支用请求内容算 `after`」并入本批（或给出本批内的兜底判定），使 A3/A4 不悬在 U1 上；U1 只保留「routed 之外的本地写入」那一半 |
| 11 | Clarity | 🔵 | `session/set_title` 的会话解析规则未写：目录路径（`:263` G9）要在**未 load 该会话的短命进程**里改标题，而 `session/revert` 必须命中内存栈 ⇒ 同一新档 `handlers-session-meta.mjs`（`:207`）里两者对「会话在不在」的要求相反，设计只写「含凭据门、错误映射」 | 在 §3.1 写明 `set_title` 的解析口径（磁盘槽位，无需活跃会话；同 `session/delete`）与 `revert` 的口径（须活跃会话 + 栈命中） |
| 12 | Clarity | 🔵 | `session/revert` 结果的路径形态未定：`:92` 样例是相对形态 `"path": "a.txt"`，而 `:60` 的分组键是「绝对路径」；宿主 `RevertFile.path`（`:143`）直接用于弹窗清单 | 明确 ACP 面返回绝对路径还是 `displayPath`（并说明裁剪基准），与 `RevertFile` 字段语义对齐 |
| 13 | 体量 | 🔵 | >800 档本批只行级新增（`thincoder_kernel.dart` 1122→≤1257、`chat_session.dart` 1223→≤1257、`chat_history_view.dart` 3691→≤3736 等），依 `thincoder-adapter.md` §5.2 的既有裁定不续拆；`agent_kernel.dart` 481→≤507 跨入 >500 层已显式声明「不立缝」。按既裁不复审体量本身 | 无需动作；建议在 `thincoder_kernel.dart` 的缝候选行注明「本批 +135 后再评估」以免缝被长期推后 |
| 14 | unverified / 单一来源 | 🔵 | 存量档案里 thincoder 会话的宿主 `_names` 条目只被限制「回放」（`:186` ⑪），未写显示读路径是否也绕开 `_names`；若显示先读 `_names`，迁移用户的标题仍可能双源（A1 风险）。代码形态未读（`workspace.dart` 不在评审可读范围） | 在设计里补一句：对具备改名能力的内核，`_names` 不参与显示与落盘（或说明迁移/清理口径） |

计数：🔴 2 · 🟡 8 · 🔵 4（共 14 项）

VERDICT: changes-required

### 轮次 2（评审子代理）

## 轮次 2 — 修正轮 1 后复核（14 条前表 + 新问题）

复核对象：`docs/design/session-governance.md`（2026-10-20 版）· `docs/requirements/session-governance.md` · `docs/design/thincoder-adapter.md`（交叉引用位）。
口径说明：外仓 `thincoder/` 源文件不在评审可读范围 ⇒ 设计对外仓代码的对位断言一律 `unverified`，未据此提任何发现。无 AGENTS.md / document map ⇒ 方法论合规与文档归属按降级口径判定。

### 前表逐条

| # | 前轮类别 | 严重度 | 结论 | 本轮证据（当前档） |
|---|---|---|---|---|
| 1 | 可行性 / 需求（F1.1 · A1）：运行中改名排队 + 60s 丢弃 ⇒ 假失败 + 标题分叉 | 🔴 | **Fixed** | §3.5 后置态（`_titleTarget` / `_titleDeferred` / `_titleSending`）；D-SG14 明确写出症结「排队写若发在回合在飞时，会排在 prompt 之后、超 60s 被桌面丢弃而核照常执行 ⇒ 假失败 + 标题分叉（A1 不成立）」；发送点只在队列空闲（`_turn == null && _pendingAuto == null && !_titleSending && !_releaseWanted`）；迟到执行由下一次 `session/list` 自愈、文案只说「未确认」；G1b 覆盖在飞零发送 + last-wins；`revert` 同判据改为在飞门（§3.5 末条） |
| 2 | 契约缺口：宿主投影缺 `sinceTurn`，入口②不可达 | 🔴 | **Fixed** | `PlansReverts` 含 `canRevertNow`；`revertPlan({required String sinceTurn})` / `applyRevert({required String sinceTurn})`；宿主投影同步带参；`canPlanRevert` = 能力 × 空闲（不以宿主 pending 为门）；「该回合有核内记录」由 dryRun 空计划回答；G12 断言 `sinceTurn` 透传与空计划提示 |
| 3 | 验收：A1/A3/A4/A5 机检指向无法验证的层 | 🟡 | **Fixed** | §6 拆两列（核侧 G13–G20 / 宿主侧 G1–G12）；A1→G19+G1/G1b/G9；A3→G14（真临时目录 + `undoApply` 逐文件断言）+ G5（接线）；A4→G15+G6；A5→G16/G17+G7；G1 期望改为「恰一条 `session/set_title`」不再断言槽文件 |
| 4 | 文档归属：适配档残留相抵，设计档无处置位 | 🟡 | **Fixed** | §4.1 ㉑ 新增 `docs/design/thincoder-adapter.md` 行，逐项点名 §10 边界删「回退 / 改名」、§3.4 `session/prompt` 行补 `turnId?`、§7 B1 例外与批次名册补本批、§5.2 缝候选行注明「本批 +175 后再评估」；§2.3 同步登记「处置见 §4.1 ㉑」。适配档文件本体仍为旧文（实测 `thincoder-adapter.md:460` 仍含「回退 / … / 改名」、`:107` 仍无 `turnId`、`:398` B1 例外未含本批、`:5` 名册止于批 14）⇒ 按 R7a 报告不代改，落地依 ㉑ |
| 5 | 自述相抵：「`/undo` 既有语义零变」 | 🟡 | **Fixed** | 改为「对 `/undo` 是**增量而非零变**」并给出单步粒度与 50 条 / 64MB 消耗速率分析、接受理由与判定条件（D-SG18 · §10 U6 · §8 边界行） |
| 6 | 逐出记账 / 回合索引边界未定（含跨键 `lost` 漏报） | 🟡 | **Fixed** | §2.4 逐出与索引边界四条：按路径 + 下界的逐出账（显式否掉按键 `lost`：「按键记账会漏…按路径 + 下界不会」）、索引 50 键最旧先出 + 键逐出 → `-32602 unknown turn`、apply 后空键 = 空计划、无前键铸 `p<n>`；D-SG16；G17/G18 三条判据各有用例 |
| 7 | l10n 文案清单短于 §9 的 UI 决定 | 🟡 | **Fixed** | 20 键表（2 校验 + 5 入口/确认 + 4 组名 + 4 reason + 3 ICU 复数摘要 + 2 空计划/在飞）；§4.1 ⑭ en +85 / zh +22、⑮ 各 +45 |
| 8 | 验收：`ownsTitle` / 宿主标题器门无用例 | 🟡 | **Fixed** | §4.1 ⑳ 新增 `test/workspace/agent_title_test.dart`（40）G2 ≤ +25；§7 G2 = thincoder 零调用 ∥ Claude 照旧 |
| 9 | 受影响文件清单漏 mock 档 | 🟡 | **Fixed** | §4.1 ⑲ `thincoder_mock.dart`（668）≤ +35：`session/set_title` + `session/revert` 脚本面与请求记录 |
| 10 | 验收风险：U1 读回时序把硬验收推出本批 | 🟡 | **Fixed** | D-SG17 + §3.2：routed 写不读回、写后值 = 请求 `content` 的 sha256；§10 U1 改为「routed 半边本批已闭合」，本地读回留判定条件；G15② 断言不读回也判得出 |
| 11 | 会话解析规则未写 | 🔵 | **Fixed** | §3.1 契约行：`set_title` 与 `session/delete` 同法（磁盘槽位、无需活跃会话）∥ `revert` 须活跃会话 + 命中内存栈 |
| 12 | 结果路径形态未定 | 🔵 | **Fixed** | §3.1：`path` = 绝对路径、`displayPath` 可选（相对 cwd 裁剪）；JSON 样例改绝对路径；`RevertFile/RevertSkip/RevertFailure` 带 `displayPath` |
| 13 | 体量：>800 档只行级新增 | 🔵 | **Fixed** | §4.3 体量与拆分：外仓 500 硬限处置、本仓 >800 只行级 + 缝候选沿用既有记录、>500 且 <800 三档按既裁不立缝；㉑ 给 `thincoder_kernel.dart` 缝候选行加注 |
| 14 | 存量 `_names` 与单一来源 | 🔵 | **Fixed** | §3.3 / §4.1 ⑪：对可改名内核 `_names` 不参与显示（`:527` 能力门）也不落盘（`:2667`）；存量条目由读面忽略；并注明代码形态已实读 |

### 新问题（本轮）

| # | 类别 | 严重度 | 问题 | 建议 |
|---|---|---|---|---|
| N1 | l10n 清单细节 | 🔵 | §9 确认框正文要求「文件数 + 文件清单」，但 20 键表里没有计数片段（`revertWarning` 是「回合之后的改动将丢弃」另一句），F2.6 明写要列文件数 | 缺一个计数键（复数）或明确计数并进 `revertWarning` 的占位；同步 ⑭/⑮ 预算 |
| N2 | 交叉引用精度 | 🔵 | §1 结论行与 §3.3 `canRevertNow` 注释都把「在飞门」指向 §3.4，实际条文在 §3.5 末条；§6 A1 行宿主列未引 G2（F1.3 宿主半边）；㉑ 把「批次名册」记在 §7，名册实际在档头 `:5` | 三处引用对齐；A1 行补 G2 |

### 计数与本轮结论

- 🔴 2 · 🟡 8 · 🔵 4（前表 14 条）：**全部 Fixed**，无 Unfixed / 无零理由搁置。
- 新增：🔵 2（N1 / N2），无新 🔴、无新 🟡。
- 结论：前轮两个 🔴 已由 §3.5 后置态与 §3.3 契约改写闭合，修正未引入新 🔴；适配档文件本体的相抵文字按 R7a 由 ㉑ 落地。

VERDICT: pass

## §4 用户批准（主 agent）

**用户批准（2026-10-20 00:35）**：用户逐字「批准」。

批准对象：A1 会话治理设计（`docs/design/session-governance.md` 406 行；两轮评审：R1 changes-required → 修正轮 1 → R2 **pass**（14/14 Fixed + 2🔵 修正轮 2）→ 批准）+ 需求档 F1/F2 + 本批档。

**实施分两段**：① 外仓段（`thincoder/` 声明的检出；用户 2026-10-20 00:02 的 B1 例外覆盖；含 ACP 两个方法、撤销栈回合化、标题粘住）→ ② 宿主段（能力门 / 投影 / 两个入口 / 确认与结果框 / 21 键 l10n / 测试）。两段各自验收，父侧核验后 §6 结算。

## §5 实施记录（eng-coder）
**状态行**：实施完成（宿主段 UI 层（第三轮）：回退两处入口 / 确认与结果框 / 改名校验与预填 / workspace 三径 / G2·G3·G9·G10·G12 落地；审计 1 轮 + advisor 1 轮，终态 clean；读数与行数见本段。）



### 交付摘要（外仓段 · A1）

外仓 `thincoder/` 按设计档 `docs/design/session-governance.md` §2 / §3 / §7（核侧 G13–G20）落地：
ACP 新增 `session/set_title` / `session/revert`（`session/prompt` 增可选 `turnId`），撤销栈条目回合化
（`{seq,turn,ordinal,tool,path,displayPath,backup,oversize,timestamp,after}`）+ 回合索引 `agent._undoTurns`
（key 去重、上限 50）+ 写后哈希（本地读回 / routed 用请求 content）+ 逐出账 `agent._undoLost`
（`Map<path, highestEvictedOrdinal>`）+ 回退算法（按路径分组 / 最旧 backup 作恢复值 / 最新 after 校验 /
组间最新 seq 降序 / 逐文件失败隔离 / 成功才出栈）。标题 80 上限收敛为单源常量。两个新方法不进
`transport.mjs` 白名单（默认排队）。**未提交**（按任务书）；只加本批 hunk。

### 改动清单（号 → 坐标 · 设计节号）

| # | 改动 | 坐标（现况行） | 设计节号 |
|---|---|---|---|
| 1 | 撤销栈回合化 + 计划 / 执行（全文重写） | `thincoder-core/undo-stack.mjs:69` `beginUndoTurn` · `:99` `snapshotForUndo` · `:143` `recordUndoAfter` · `:166` `findUndoTurn` · `:230` `undoPlan` · `:253` `undoApply` · `:42` `noteEvicted` · `:51` `pushEntry` | §3.2 / §2.4 / D-SG2·3·4·16·17 |
| 2 | 快照调用改参 + 三处写后值 | `thincoder-core/agent/dispatch-run.mjs:71`（快照）· `:84`（routed content）· `:142`（本地读回）· `:166`（异常径） | §3.2 |
| 3 | 标题上限单源 | `thincoder-core/session-rename.mjs:13` `MAX_TITLE_LENGTH = 80` | §3.1 / U5 |
| 4 | `/rename` 同引常量 | `thincoder-cli/src/tui/cmd-session.mjs:2`（import）· `:20`（判据） | §3.1 |
| 5 | `execTurn` 单点铸键 + `run` 透传 | `thincoder-cli/src/acp/session.mjs:93`（铸键）· `:145`（runNormal 透传）· `:166`（`run(input, opts)`） | §3.2 / D-SG2 |
| 6 | `session/prompt` 读 `turnId` 并透传 | `thincoder-cli/src/acp/handlers-session.mjs:389-390` | §3.1 / §3.2 |
| 7 | 新档：两扩展方法 | `thincoder-cli/src/acp/handlers-session-meta.mjs:29`（`session/set_title`）· `:49`（`session/revert`）· `:24`（错误映射）· `:42-45`（`agent.title` 同拍） | §3.1 |
| 8 | 装配 | `thincoder-cli/src/acp.mjs:35`（import）· `:160`（spread）· `:10`（模块名册） | §4.2 ⑧ |
| 9 | 零留存测试档 | `thincoder/docs/batches/2026-10-20-session-governance-a1.test.mjs`（G13–G20 + prompt turnId 透传 + 容器键命中；收口删除） | §4.2 ⑪ / §7 |

### 行数实测 vs 预算（设计 §4.2）

| 档 | 实测 | 预算 | 判 |
|---|---|---|---|
| `undo-stack.mjs` | 277 | ≤277 | ✅ 压线 |
| `agent/dispatch-run.mjs` | 191 | ≤200 | ✅ |
| `session-rename.mjs` | 45 | ≤47 | ✅ |
| `tui/cmd-session.mjs` | 140 | 净 0（140） | ✅（设计表现况值 140） |
| `acp/session.mjs` | 195 | ≤209 | ✅ |
| `acp/handlers-session.mjs` | 478 | ≤489（500 硬限） | ✅ |
| `acp/handlers-session-meta.mjs` | 63 | ~115（<500） | ✅（远小于估算） |
| `acp.mjs` | 187 | ≤188 | ✅ |
| 测试档 | 388 | ~+260（估算） | ⚠️ 超估算 128 行（「~」非硬顶；零留存、收口删除） |

### 验证读数

- `node --check` 九档（上表 8 档 + 测试档）：**全 OK**。
- `node --test thincoder/docs/batches/2026-10-20-session-governance-a1.test.mjs`（自 `D:\baocode`）：**tests 9 / pass 9 / fail 0**。逐条：G13 快照面（`file_ops` 零入栈、`apply_patch` / 批量 `edit` 逐路径、字段齐）；G14 三写 restore/restore/delete + apply 后空键空计划；G15 ①changed ②routed = 请求内容哈希；G16 oversize + 部分成功（成功出栈 / 失败保留）；G17 逐出两起点 + lost-only；G18 索引逐出→`-32602` / apply 后空键 / 无前键 `p<n>` / 逐出账清理；G19 槽文件 + manifest 摘要 + `agent.title` 同拍 / 空白 / 超 80 / 早退 / 容器键命中；G20 四个错误面 + dryRun 零写零出栈；另加 `session/prompt` turnId 透传例。
- `thincoder-cli`：`node scripts/check-syntax.mjs` → `check-syntax: 128 file(s) OK`；`node test/run.mjs` → manifest empty = green（仓内零留存纪律，无他档测试）；`thincoder-core` 同。
- 外仓工作树基线对照：开工前 `git status --porcelain` 存基线（34 条）。收工后 delta = **恰 7 档**：`M thincoder-cli/src/acp.mjs` / `M thincoder-cli/src/tui/cmd-session.mjs` / `M thincoder-core/agent/dispatch-run.mjs` / `M thincoder-core/session-rename.mjs` / `M thincoder-core/undo-stack.mjs` / `?? thincoder-cli/src/acp/handlers-session-meta.mjs` / `?? docs/batches/2026-10-20-session-governance-a1.test.mjs`；无删除、无其他新增。另两档（`M thincoder-cli/src/acp/session.mjs` / `M thincoder-cli/src/acp/handlers-session.mjs`）基线已是 M，本批 hunk 叠在他批改动之上（`git diff` 逐 hunk 核对，未动他批行）。`transport.mjs` / `suspension.mjs` / `cmd-undo.mjs` 零改；未提交。

### 评审轮次与终态

1. **内部 explore 审计（只读 divergence audit）· 1 轮 · VERDICT changes-required（5 项）**
   - 🟡#1 挂起窗内用户回合丢 `turnId` → **父裁 (a)**：不改 `suspension.mjs`，按设计零改动交付；该径如实登记（见下「父裁接受的缺口」）。
   - 🟡#2 外仓三份设计档未落 → 父侧文档义务（§2 已写「由主 agent 执行」），本批禁改。
   - 🔵#3 lost-only 分支 / 索引逐出清理无用例 → **已补两处断言**（G17 lost-only、G18 逐出账清理），复跑绿。
   - 🔵#4 cmd-session 行数 → 实测 140 = 设计表现况值 140（净 0），报告项。
   - 🔵#5 测试档体量 → 报告项（现 388，含 #3 补例与 G19 容器键例）。
2. **advisor 代码评审 · 1 轮 · 🔴1 / 🟡2 / 🔵5**
   - 🔴#1 = 上条窗口 `turnId` 缺口 → 父裁 (a)，报告 + 父侧已记台账技术待办（+6 行透传，归批 A1 之后）。
   - 🟡#2 routed `edit` 仍读回、§10 U1「routed 半边已闭合」只对 `write` 成立 → 报告（本批禁改设计档；建议父侧收窄 U1 口径或另立核侧定值）。
   - 🟡#3 二进制文件实际以 utf8 乱码入栈、回写会损坏（§8 的「读不出即不入栈」前提不成立；存量洞，本批放大暴露面）→ 报告（补探测＝新语义，本批不做）。
   - 🔵#6 `set_title` 只按 `_slot` 命中、fork 后粘不住 → **已修**：容器键 ∪ `_slot` 命中（`handlers-session-meta.mjs:42-45`）+ G19 补用例。
   - 🔵#4 `currentState()==null` 报成 `changed` · 🔵#5 索引 `paths` 只写不读（设计 §3.2 规定的形状）· 🔵#7 测试 chmod 依赖平台 / 身份 · 🔵#8 评审声明路径与实际位置不符 → 均报告项，不改。
   - **终态：clean**（无未处置代码项；1 项父裁接受的缺口 + 2 项设计档口径漂移待父侧文档层）。

### 决策透明表

| 决策 | 选择 | 理由 |
|---|---|---|
| `beginUndoTurn` 返回值 | 返回回合索引记录 `{key, firstOrdinal, paths}`；`agent._undoTurn` 仍留当前 `{key, ordinal}` 供快照 | 设计只规定索引结构、未规定返回值；返回记录让调用方 / 用例可直接交 `undoPlan` |
| routed 失败径的写后值 | `routedOk` 为假 ⇒ 不传 `routedText`，落回读回 | 设计只写成功径（核侧已知所写内容）；失败时内容未必落盘，读回取真实盘面（不假装） |
| `cmd-session.mjs` 引常量 | 新增 1 行 `import { MAX_TITLE_LENGTH } from "@thincoder/core/session-rename.mjs"`（139 → 140 行） | §3.1 要求「同引」session-rename 单源；§4.2 又把 `thincoder-core/session.mjs` 列为零改动且其未 re-export 该常量——两要求不自洽，选保住 `session.mjs` 零改动（实测 140 = 设计表现况值） |
| `entry.path` 形态 | 绝对路径（`displayPath` 另立） | §3.1「path = 绝对路径（分组键 / 去重 / 宿主身份同用）」；`/undo` 代码零改、展示随之变绝对路径（§2.2 已声明对 `/undo` 是增量而非零变） |
| 测试档体量 | 388 行（含 G17 lost-only / G18 清理 / G19 容器键 三处补例） | 「~+260」为估算非硬顶；零留存、收口删除 |

### 父裁接受的缺口（[上抛·待裁] 已裁 (a)）

挂起窗在时 `session/prompt` 走 `window.submit(input)`（`thincoder-cli/src/acp/session.mjs:171`），`opts.turnId` 被丢弃 ⇒ `execTurn` 的 `beginUndoTurn` 无 `turnId` ⇒ 按「自动轮继承上一键」落到上一回合键（`undo-stack.mjs:75`）。后果：宿主以该用户回合 id 调 `session/revert` 回 `-32602 unknown turn`（`handlers-session-meta.mjs:56`）；写入并入上一键的区间语义本身正确。**处置 = 父裁 (a)**：不改 `suspension.mjs`（设计 §4.2 零改动），父侧已记台账技术待办（+6 行透传，归批 A1 之后）。

### 未做 / 边界

1. 外仓三份设计档（`ACP-CLIENT.md` §2.1 方法表 + 新小节 / `TUI-COMMANDS.md` §5.3 / `SESSION.md` §6.7）——任务书与批档 §2 明确「由主 agent 执行」，本批禁改，**未做**。
2. 宿主段（`D:\baocode\lib/**`）不在本段。
3. `file_ops` move / rename 不入快照（设计 §8 已登记后续判定项）。
4. routed `edit` 写后值仍读回、二进制探测缺位——见评审 #2 / #3，报告项。
5. 零留存测试档 `thincoder/docs/batches/2026-10-20-session-governance-a1.test.mjs` 收口删除（本段保留供父侧复跑）。

### 宿主段 · l10n 21 键（eng-coder · 第二轮）

**交付摘要**：设计档 §9 键表的 21 键落两源档（`app_en.arb` / `app_zh.arb`）+ 三份手改生成档（无 SDK 生成器）。
父裁 (a)：设计档只有键名与用途、无逐键值，值由本段按设计既有用语 + 既有 arb 风格补写，逐键表见下、父侧核。
未改任何既有键值；未动 UI / 内核 / 设计档 / 需求档。

**逐键值（en / zh）**

| # | 键 | en | zh |
|---|---|---|---|
| 1 | `renameTitleRequired` | A title is required | 请填写标题 |
| 2 | `renameTitleTooLong` | A title is at most 80 characters | 标题最多 80 个字符 |
| 3 | `revertFromTurn` | Revert files from this turn… | 从这个回合起回退文件… |
| 4 | `revertTitle` | Revert files from this turn? | 从这个回合起回退文件？ |
| 5 | `revertWarning` | Changes made after this turn will be lost. | 回合之后的改动将丢弃。 |
| 6 | `revertConfirm` | Revert | 回退 |
| 7 | `revertDone` | Revert complete | 回退完成 |
| 8 | `revertFileCount` | {count, plural, =0{No files} =1{1 file} other{{count} files}} | {count, plural, =0{没有文件} =1{1 个文件} other{{count} 个文件}} |
| 9 | `revertGroupRestored` | Restored | 恢复 |
| 10 | `revertGroupSkipped` | Skipped | 跳过 |
| 11 | `revertUnrevertable` | Cannot be reverted | 无法回退 |
| 12 | `revertGroupFailed` | Failed | 失败 |
| 13 | `revertReasonChanged` | Changed after the turn | 回合之后改过 |
| 14 | `revertReasonOversize` | Too large to revert | 文件过大 |
| 15 | `revertReasonEvicted` | No longer kept | 已不再保留 |
| 16 | `revertReasonAfterUnknown` | Cannot tell if it changed | 无法确认是否改过 |
| 17 | `revertSummaryRestored` | {count, plural, =0{Reverted no files} =1{Reverted 1 file} other{Reverted {count} files}} | {count, plural, =0{没有回退文件} =1{回退了 1 个文件} other{回退了 {count} 个文件}} |
| 18 | `revertSummarySkipped` | {count, plural, =0{Skipped no files} =1{Skipped 1 file} other{Skipped {count} files}} | {count, plural, =0{没有跳过文件} =1{跳过了 1 个文件} other{跳过了 {count} 个文件}} |
| 19 | `revertSummaryUnrevertable` | {count, plural, =0{No files are unrevertable} =1{1 file cannot be reverted} other{{count} files cannot be reverted}} | {count, plural, =0{没有无法回退的文件} =1{1 个文件无法回退} other{{count} 个文件无法回退}} |
| 20 | `revertNothingToRevert` | Nothing to revert. | 无可回退。 |
| 21 | `revertTurnInFlight` | Unavailable while a turn is running | 回合进行中，暂时不能回退 |

**改动清单**

| 档 | 落点 | 增量 |
|---|---|---|
| `app_en.arb` | 21 值 + 21 条单行 `@` 元数据（`7240-7281`） | +42 行 |
| `app_zh.arb` | 21 值（`2820-2840`；zh 档既有形态不带 `@`） | +21 行 |
| `app_localizations.dart` | 抽象类 21 成员 + 生成体式文档注释（`16963-17086`） | +126 行 |
| `app_localizations_en.dart` | 17 getter + 4 复数方法（`10373-10472`） | +99 行 |
| `app_localizations_zh.dart` | 17 getter + 4 复数方法（`9810-9906`） | +99 行 |

**计数读数**：en / zh 消息键各 **2830**、集合相等（各新增 21；既有键零改）；en `@` 元数据新增 21 条；三生成档各 **21 个成员**（17 `String get` + 4 `String …(int count)`）。

**预算对照**：en +42（设计 +89，未超）· zh +21（设计 +23，未超）· 生成档 +126 / +99 / +99（设计各 +48，**超出**）。
原因：生成体式为硬约束——抽象档每成员 6 行（4 行文档注释 + 声明 + 空行）、impl 每 getter 3 行、每复数方法 12 行；21 键即 ≈126 / 99 / 99，+48 隐含每成员 ≈2.3 行，与该形态不可并存。未压行以迁就估算（压行即偏离生成体式）。设计档 ⑮ 的 `+48` 建议由设计侧下一轮按实测改记。

**EOL 读数（node：`\r\n` 数 / 总行数）**

| 档 | 改前 | 改后 | 判 |
|---|---|---|---|
| `app_en.arb` | 3647 / 7241 | 3647 / 7283 | 新增 42 行全 LF；既有混合 EOL 一字未动 |
| `app_zh.arb` | 7 / 2821 | 7 / 2842 | 新增 21 行全 LF；未整档归一 |
| `app_localizations.dart` | 16995 / 16996 | 17121 / 17122 | 纯 CRLF（`\r\n` = 行数−1） |
| `app_localizations_en.dart` | 10374 / 10375 | 10473 / 10474 | 纯 CRLF |
| `app_localizations_zh.dart` | 9808 / 9809 | 9907 / 9908 | 纯 CRLF |

**验证读数**

- `flutter analyze lib/l10n` → `No issues found!`（3.5s）。
- `flutter test test/l10n_test.dart` → `22 tests, All passed`。
- 零留存单测（临时档，跑完即删）→ 5 tests 全绿：21 键 en/zh 值逐条断言 + 4 条复数键 0 / 1 / 2 三态。
- `dart format --output=none --set-exit-if-changed` 三生成档 → 0 changed。
- 中途一次 `flutter test test/l10n_test.dart` 编译失败（`thincoder_kernel.dart` 缺 `_pumpTitle` / `_planOf` / `_revertFiles` 等定义，属并行宿主段的中间态）；该段推进后复跑 22/22 绿。非本段改动。

**评审轮次与终态**

1. 内部 explore 偏差审计 · 1 轮 · **CLEAN**（缺失 / 多余键、既有值改动、生成体式、EOL、zh 用词、越界文件六类零命中；报告了预算算术与两处工具度量限制）。
2. advisor 代码评审 · 1 轮 · **pass**（0🔴 / 3🟡 全标「可选，不阻断」 / 4🔵）。已取 2 处修正：
   - zh `revertReasonEvicted`「已逐出」→「已不再保留」——「逐出」全 `lib/` 仅此一处，属自造词，违「不自创说法」。
   - zh `revertReasonChanged`「回合后改过」→「回合之后改过」——与 `revertWarning` 的「回合之后」对齐。
   报告不改为：`=0` 分支措辞（notice 三条片段一律连接时会读出「Reverted no files · …」，零值抑制属 H2 / 设计 §9 口径）；手改生成档缺「源档 ↔ 生成档」护栏（建议后续给 `test/l10n_test.dart` 加值比对，超出本段范围）；80 上限硬编码 4 处；`revertUnrevertable` 前缀不齐（设计档原样）；生成档体量超估算；`无可回退。` 较裁决多一句号（与本档 zh 整句习惯一致）。
3. **终态：clean**。

**决策透明表**

| 决策 | 选择 | 理由 |
|---|---|---|
| 21 键取值 | 按设计档既有用语 + 既有 arb 风格补写，逐键表交父侧核 | 设计档 §9 无逐键值；父裁 (a) 明确授权并保留设计侧随后补记 |
| 复数 `=0` 形态 | 两语都写全 `=0 / =1 / other` | 任务书与父裁都要求三态写全；生成体式 `zero/one/other` 三参齐 |
| `revertDone` 语义 | 结果框标题（Revert complete / 回退完成） | 设计 §9 未给该键用途细节；按钮已复用 `commonOk` / `commonClose` 既有键，标题为唯一缺口 |
| zh 用词 | 只用 文件 / 回合 / 回退；`恢复` 仅作设计给定的组名 | 父裁词汇面；`逐出` 于评审后改为「已不再保留」 |
| ARB 插入 EOL | LF（与存量多数行、HEAD 一致），不整档归一 | 父裁 (b)；实测两源档为混合 EOL、`HEAD` 纯 LF |
| 生成档写法 | 逐字对齐 gen-l10n 体式（文档注释 / `@override` / `pluralLogic` 参数序） | 无生成器，体式一致性是唯一可核标准；`dart format` 0 changed 佐证 |
| 预算超估算 | 照体式落，不压行，读数如实登记 | 压行换预算会破坏体式，代价高于估算偏差 |

**未做 / 边界**

1. 设计档 §9 的逐键值补记 = 设计侧（父裁 (a)），本段只交表。
2. UI 调用点（H2）不在本段；21 键当前零调用，属预期。
3. 未新增测试档；护栏建议见上。

### 交付摘要（宿主段第一批 · A1 内核层）

按设计档 `docs/design/session-governance.md` §3.1–§3.5 / §4.1 ①②③④⑲ / §7 宿主侧表落地：四个可选接口与回退类型、
thincoder 内核接线（标题后置态 / `canRevertNow` / `revertPlan`+`applyRevert` / prompt 带 `turnId` / 自动轮归一 /
`ChangesReverted`）、目录短命连接改名、mock 脚本化两个新方法、G1/G1b/G4–G8/G11 宿主侧用例。UI 层（`lib/chat/**`、
`lib/workspace/**`、`lib/ide/**`、l10n）按批次拆分为下一轮，本段未碰；Claude 内核零改动（A6）。

### 改动清单（号 → 坐标 · 设计节号）

| # | 改动 | 坐标（现况行） | 设计节号 |
|---|---|---|---|
| 1 | 四接口：`PlansReverts`（`canRevertNow` / 带参计划与执行）、`GeneratesTitles`、`DefersRename`、`RenamesStoredSessions` | `lib/kernel/agent_kernel.dart:302-335` | §3.3 / §4.1 ① |
| 2 | 回退类型：`RevertAction` / `RevertFile` / `RevertSkip` / `RevertFailure` / `RevertPlan` / `RevertOutcome`（均带可选 `displayPath`） | `lib/kernel/kernel_types.dart:616-668` | §3.3 / §4.1 ② |
| 3 | implements 四接口 | `thincoder_kernel.dart:52-56` | §3.3 |
| 4 | 标题后置态字段 + `_pendingTitle` + `_autoTurnOf` | `thincoder_kernel.dart:128-141` | §3.5 / §3.3 |
| 5 | `pendingTitle` 投影 | `thincoder_kernel.dart:182-183` | §3.3 |
| 6 | 建会话后补发暂存标题 | `thincoder_kernel.dart:310-314` | §3.4 |
| 7 | `session/prompt` 带 `turnId`（= `KernelTurn.id`） | `thincoder_kernel.dart:694-698` | §3.1 / §3.2 |
| 8 | 自动轮 → 最近 prompt 键；`_teardown` 清映射；`revertPlan` 请求时归一 | `thincoder_kernel.dart:725-729` · `:499-500` · `:938` | §3.3 / D-SG2 |
| 9 | `_endTurn` 在 `_drain()` 前 pump 标题（与模型同收尾位） | `thincoder_kernel.dart:809-810` | §3.5 |
| 10 | `rename` 后置态（未建会话暂存 / 在飞 last-wins / 发送中 / 空闲直接 pump）；`_dropTitleOf` | `thincoder_kernel.dart:878-905` | §3.4 / §3.5 |
| 11 | `canRevertNow` | `thincoder_kernel.dart:881` | §3.5 末条 |
| 12 | `revertPlan` / `applyRevert`（请求 + 结果映射 + 摘要 notice + `ChangesReverted`） | `thincoder_kernel.dart:907-929` | §3.1 / D-SG12 |
| 13 | `_revert`（`{sessionId, sinceTurn, dryRun}`；错误 notice + appEvent + rethrow） | `thincoder_kernel.dart:931-955` | §3.1 |
| 14 | `_pumpTitle`（发送前置四判据、超时 60s、last-wins、失败文案只说「未确认」）与回退解析 helpers | `thincoder_kernel.dart:1234-1296` | §3.5 / §3.3 |
| 15 | dispose 清标题态（设计 §3.5 明列，评审轮 1 补） | `thincoder_kernel.dart:592` | §3.5 |
| 16 | 目录改名：`RenamesStoredSessions` 短命连接 `session/set_title`（`_serial` 同 `delete`） | `thincoder_catalog.dart:22` · `:71-88` | §3.3 / §4.1 ④ |
| 17 | mock：`session/set_title`（空白 / >80 / `titleError` ⇒ `-32602`；成功经 `session/list` 读新标题）· `session/revert`（脚本计划 / 结果 / 未知回合）· 请求记录沿用 `written` | `thincoder_mock.dart:16-29` · `:74-84` · `:120-123` · `:323-333` · `:339-356` · `:557-565` | §4.1 ⑲ |
| 18 | 用例：G1 两径 / G1b 四例（在飞 last-wins、错误、发送中、发送中失败后重发）/ G4 / G5 / G6 / G7 / G8 / G11 / 自动轮归一 | `test/kernel/thincoder_kernel_test.dart:3837-4137` | §7 宿主侧 |
| 19 | 既有断言更新：内核现声明改名/计划回退/自带标题/后置态；prompt 参数含 `turnId` | `test/kernel/thincoder_kernel_test.dart:319-327` · `:337-341` · `:688-692` | §3.3 |

### 行数实测 vs 预算（设计 §4.1；计数 = `split('\n').length`，与父侧同法）

| 档 | 实测 | 预算 | 判 |
|---|---|---|---|
| `lib/kernel/agent_kernel.dart` | 515 | ≤515 | ✅ 压线 |
| `lib/kernel/kernel_types.dart` | 669 | ≤669 | ✅ 压线 |
| `lib/kernel/thincoder/thincoder_kernel.dart` | 1297 | ≤1297 | ✅ 压线 |
| `lib/kernel/thincoder/thincoder_catalog.dart` | 150 | ≤153 | ✅ |
| `lib/kernel/thincoder/thincoder_mock.dart` | 703 | ≤703 | ✅ 压线 |
| `test/kernel/thincoder_kernel_test.dart` | 4144 | ≤4144 | ✅ 压线 |

### 验证读数

- `flutter analyze --no-pub` 六档（上表）：**No issues found**。
- `flutter test --no-pub test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_catalog_test.dart`：**+144 All tests passed**（kernel 135 = 既有 121 + 新 14；catalog 9 零回归）。
- `flutter test --no-pub test/kernel_test.dart`：**96 passed / 8 skipped / 4 failed**。4 条失败均为本批外的环境/平台项（`packages/bao_remote` 的 claude locator/storage：本机未安装 Claude Code；Windows 路径分隔符与用例期望的 `/` 不符），本批零改动面；A6 相关的 Claude kernel 用例（含 `undo rewinds the files since the turn`）全绿。
- `pubspec.lock`：flutter 跑批把镜像 URL 改写为 `pub.dev`（环境副作用，与既往批次一致），已 `git checkout` 还原；两处自动快照 `mvgc2dmg-0gy8` / `mvgc5i1m-zrr0`。
- 工作树：本段只改上表 6 档；`thincoder_catalog.dart` 基线 clean、本段只加本批 hunk；其余 5 档基线已有他批改动，本段只叠加本批 hunk。

### 审计 / 评审轮次与终态

1. **内部 explore 偏差审计 · 1 轮 · VERDICT changes-required（1 项 🟡）**：`_pumpTitle` 错误分支无条件清标题态 ⇒ 发送期间新选的标题被丢弃（设计 §3.5「应答 / 错误落地：目标已换 ⇒ 再发一次」）。
   - **已修**：错误分支先 `_titleSending = false`，目标已换则 `unawaited(_pumpTitle(...))` 再发；并补 G1b「发送中失败后最后一选仍发出」用例；复跑绿。
2. **advisor 代码评审 2 轮 · 终态 clean**
   - 轮 1：**pass**，5🟡 / 5🔵（无 🔴）。🟡 = dispose 未清标题态（设计 §3.5 明列）、无连接时改名静默丢、回退摘要 notice 归属与 §9 的 ICU 键冲突、`ChangesReverted` 无条件发、无会话回退抛 `StateError` 而非 `-32602`。
   - fix round：① `dispose()` 补 `_dropTitleOf()`（设计明列项）② `PlansReverts` 补抛异常契约注释（`agent_kernel.dart:304`）。
   - 轮 2：**pass**，修复声索 2/2 实读证实，无新问题（`_dropTitleOf` 的 `emitInfoChanged` 排在 `closeEvents()` 前、`emit` 有闭流保护 ⇒ 无 emit-after-close）；剩余项按「设计缺口 / 跨层口径」记为 Unfixed / Accepted 并附理由。
   - 合计 fix round = 2（审计 1 + 评审 1；每轮均复跑相关用例）。
3. **未处置项**：见下「上抛」——均为设计缺口 / 跨层口径，没有未记录的代码阻断项。

### 决策透明表

| 决策 | 选择 | 理由 |
|---|---|---|
| 回退摘要 notice 的文本 | 内核内英文计数摘要（` · ` 连接，零值分组抑制） | 设计 §4.1 ③ 把 `NoticeItem` 归内核；§9 的 3 条 ICU 键属 UI 轮产物、内核无 locale。冲突已上抛（H2 前定 owner） |
| mock 的标题落点 | `_titles` 旁表 + `session/list` 覆盖；调用方传入的 `slots` 不改 | mock 字段 doc 的契约就是「`session/list` 报什么」；避免改 const 调用面与既有用例 |
| 无会话时 `revertPlan` 的失败面 | 先发 error notice，再抛 `StateError`，接口 doc 写明「会抛」 | 设计未定；不吞错、不假装空计划；H2 按文档捕获（残留口径见上抛 #1） |
| 自动轮 → 回合键 | `_autoTurnOf[auto:<n>] = 最近一次 prompt 的 turnId`，请求时归一 | 设计 §3.3 原文；`_teardown` 清表 |
| G11 的断言面 | 按设计 §7 测宿主结果映射（mock `files` 1 + `failed` 1） | 任务书括注与 §7 冲突；父侧已裁按 §7，核侧不重测 |
| 失败文案 | `The title was not confirmed: …` / `Could not revert: …` | 设计 §3.5「error 文案只说未确认」；与既有模型切换 notice 同形 |

### 上抛（父侧裁 / H2 前定）

1. **[上抛·待裁] 无连接（已 release、但会话仍在 workspace）时的改名语义**：现实现静默丢弃（`_pumpTitle` 的 `connection == null` 分支清目标）。可选：并入 `_pendingTitle` 暂存并在下次建会话补发，或按 §3.5 失败面发 error notice；同源问题 = `canRevertNow` 未纳入「有会话 / 有连接」。建议 H2 前一次定清（两处同一状态）。
2. **[上抛·待裁] 回退摘要 notice 的 owner**：内核（英文、固定）vs 设计 §9 的 3 条 ICU 键（宿主生成）。不定就会出现「双摘要」或「3 键成死键 + 中文界面英文摘要」。
3. **[上抛·待裁] 全跳过 / 全失败时是否仍发 `ChangesReverted`**：现实现无条件发，会清空宿主待处理清单（ActivityStrip 的 Undo all 随之消失）而盘面文件仍未恢复，与 D-SG11「条目保留可重试」的可见面不一致；改法 = 只在 `files.isNotEmpty` 时发（或事件带恢复条数）。
4. **[上抛·知会] `test/kernel_test.dart` 的 4 条失败**：`packages/bao_remote` 的 claude locator/storage 平台/环境项（Claude 未安装、Windows 路径分隔符），不涉本批改动面；本批未改动这些档，无法在批内绿。
5. **[上抛·知会] 行头寸**：`agent_kernel.dart` 现 515 = 上限、`kernel_types.dart` 669 = 上限、`thincoder_kernel.dart` 1297 = 上限、`thincoder_mock.dart` 703 = 上限、测试档 4144 = 上限；后续任何补丁进这些档须先腾行。
6. **[上抛·知会] 未做项**：G3 字段校验按父裁移交 UI 轮（`inline_rename_field` 那批）；G2 / G9 / G10 / G12 属下一轮；UI 接线（`ChatSession` 投影、`workspace` 三径、两处入口、确认/结果框、21 键 l10n）本段未碰。

**勘误（本段 · 坐标行号，收工前逐处回读）**：改动清单 #1 应为 `agent_kernel.dart:302-334`；#6 应为 `thincoder_kernel.dart:311-315`；#8 的「请求时归一」在 `:929`（`:938` 是 `dryRun` 参数行）；#10 的 `rename` 本体为 `:883-899`、`canRevertNow` 在 `:881`、`_dropTitleOf` 在 `:901-904`；#14 `_pumpTitle` 起于 `:1233`。其余坐标复核无误。

### 交付摘要（H1 内核层 · 修正轮：三条父裁点）

按父侧 2026-10-20 01:13 修正单，按 1..3 点修（`lib/kernel/thincoder/thincoder_kernel.dart` + 接口注释一行 + 用例）：

1. **无连接改名不再静默丢**：`_pumpTitle` 的「无连接 / 无槽」分支由静默 `_dropTitleOf()` 改为先 `appEvent` + `NoticeItem(error, 'The title was not confirmed: no connection')`，再清标题态（值保持原样、不留 pending）；同源 `canRevertNow` 纳入 `_running`（连接 + 健康就绪），无连接 ⇒ false。
2. **内核不再拼英文回退摘要**：`applyRevert` 删去成功摘要 `NoticeItem` 与 `_revertSummary`（无残留引用），只回结构化 `RevertOutcome`；摘要由宿主（H2）按 §9 的 `revertSummary*` 三键渲染。错误面 `_revertFailed` 的 notice 保留（父裁只指摘要）。
3. **`ChangesReverted` 改条件发**：仅 `outcome.files.isNotEmpty` 时发；全跳过 / 全失败不发，宿主待处理清单保留（D-SG11 可见面）。

### 改动清单（号 → 坐标 · 设计节号）

| # | 改动 | 坐标（现况行） | 设计节号 |
|---|---|---|---|
| 1 | `canRevertNow` 纳入可用连接（`_running`）+ 注释 | `lib/kernel/thincoder/thincoder_kernel.dart:880-882` | §3.3 / §3.5 末条 |
| 2 | `applyRevert` 去成功摘要 notice；`ChangesReverted` 条件发 | `thincoder_kernel.dart:911-924`（条件在 `:922`） | §9 / D-SG12 / D-SG11 |
| 3 | `_pumpTitle` 无连接分支：错误 notice + appEvent，再清态 | `thincoder_kernel.dart:1240-1248` | §3.5 |
| 4 | 删除 `_revertSummary`（全仓零引用） | 原 `:1288-1296` | §9 |
| 5 | `PlansReverts.canRevertNow` 注释补「且有可用连接」 | `lib/kernel/agent_kernel.dart:306-307` | §3.3 |
| 6 | 新用例 G1c：无连接改名 ⇒ 零 `session/set_title`、恰一条错误 notice、`canRevertNow` false | `test/kernel/thincoder_kernel_test.dart:3884-3893` | §3.5 |
| 7 | G5 增断言：成功后会话内无内核 notice（摘要归宿主） | `thincoder_kernel_test.dart:4023` | §9 / D-SG12 |
| 8 | G6 增断言：全跳过 ⇒ 零 `ChangesReverted`、`transcript.revertedSeq` 仍 `-1` | `thincoder_kernel_test.dart:4046-4047` | D-SG11 |
| 9 | G11 原断言保留：部分成功 `outcome.files` 带恢复数、仍发一条事件（本轮仅同组行内压缩） | `thincoder_kernel_test.dart:4103-4108` | D-SG11 |

同组行内压缩（G5 / G6 / G7 / G8 / G11 的映射表与两处 `expect`、文件尾空行）：**零语义改动**，只为守住测试档 4144 行硬预算（压线，见「行数读数」）。

### 验证读数

- `flutter analyze --no-pub lib/kernel/agent_kernel.dart lib/kernel/thincoder/thincoder_kernel.dart test/kernel/thincoder_kernel_test.dart` → **No issues found!**（3 档）。
- `flutter test --no-pub test/kernel/thincoder_kernel_test.dart` → **+136 All tests passed!**（修前 135；新增 G1c 一例）。同命令复跑两次均绿。
- 新断言的判别力：G1c 在旧实现上必红（旧路径零 error notice）；G5 的 `items<NoticeItem>()` 为空在旧实现上必红（旧摘要即一条 info notice）；G6 的「零 `ChangesReverted`」在旧实现上必红（旧为无条件发）。
- 环境读数：本会话 shell 的 PATH 无 `flutter`，改用绝对路径 `C:\Users\xinbo\repos\flutter\bin\flutter.bat`；`pubspec.lock` 无改写（本段未触发镜像重写）。

### 行数实测 vs 预算（计数 = `split('\n').length`）

| 档 | 实测 | 预算 | 判 |
|---|---|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | 1296 | ≤1297 | ✅（删 `_revertSummary` 后腾出 1 行余量） |
| `lib/kernel/agent_kernel.dart` | 515 | ≤515 | ✅ 压线（仅改注释两行，行数不变） |
| `test/kernel/thincoder_kernel_test.dart` | 4144 | ≤4144 | ✅ 压线（新增 G1c + 三处断言 = 同组压缩抵消） |

### 审计 / 评审轮次与终态

1. **内部 explore 偏差审计 · 1 轮 · VERDICT changes-required**：三代码点无偏离、行数三档达标、新断言均可红；要求项只有设计档归属/定义面（§3.3 `:147`、§3.5 `:229`、§4.1 ③ `:241` 未随父裁更新）+ 4 条 🔵 观察。处置 = 转「上抛 1」，本轮禁改设计档。
2. **advisor 代码评审 · 1 轮 · 1🔴 / 3🟡 / 4🔵（详见下「评审处置」）**；因唯一 🔴 属设计档笔域，本轮无代码可修，未再开轮 2。
3. **终态 = stalled（仅设计档一项；代码面 clean）**：三父裁点已交付并复跑绿；唯一未决 = 设计档机制级归属不一致（见上抛 1），须设计笔主收口后才能转 clean。

### 评审处置（advisor 轮 1）

| 号 | 级别 | 内容 | 处置 |
|---|---|---|---|
| 1 | 🔴 | 设计档同一机制两处归属相反：§4.1 ③（`:241`）把「会话内 `NoticeItem` + `ChangesReverted`」记在内核档改动里，§9（`:381`）把同一条记录的文案交给宿主 ICU 键；§3.4（`:206`）/ D-SG12（`:303`）仍按无条件发读 | **父侧文档层收口**（本轮禁改设计档）：§4.1 ③ 删 `NoticeItem`、`ChangesReverted` 注「仅 `files` 非空发」；§3.4 `:206` 的 notice 标为宿主步骤；D-SG12 注明摘要 owner = 宿主。代码不改 |
| 2 | 🟡 | `_releaseWanted` 真而 `_turn == null` 时 `rename` 无 notice（可经子代理在飞 / 挂起窗开着到达） | **判为非本轮偏离**：设计 §3.5 `:224` 明写发送前置含 `!_releaseWanted`、「不满足 ⇒ 只记目标（不新发）」，`:228` 又写 teardown 清标题态——即该径由设计明定、非静默丢缺陷；记录为边界项，若父侧要求改语义再走设计 |
| 3 | 🟡 | `canRevertNow` 设计定义（无在飞回合）窄于实现（再加 `_running`） | 同 🔴1 的文档面：§3.3 `:147` / §3.5 `:229` 各补「且有可用连接」；代码按父裁 ① 不动 |
| 4 | 🟡 | 摘要改归宿主后，H2 必须消费 `RevertOutcome`（`revertSummary*` 现零调用，全在 l10n） | **协调项**：H2 任务书显式写「`applyRevert` 结果按 `files/skipped/unrevertable` 计数拼三条 ICU 摘要作为会话内 `NoticeItem`」 |
| 5 | 🔵 | 错误 notice 仍内核硬编码英文（`The title was not confirmed: …` / `Could not revert: …`） | 不改：既有口径，设计 §9 未给键位；留 H2/l10n 轮统一裁 |
| 6 | 🔵 | `revertPlan` / `applyRevert` 不复核 `canRevertNow`（`_revert` 只判连接/槽），调用方漏门会吃 60s | 不改：设计把在飞门放在两处入口；防御自检属新增语义 |
| 7 | 🔵 | `_dropTitleOf` / `dispose` 三语句压一行（`:903` / `:592`） | 不改：该档正卡 1297 上限，展开即超预算；下次动档时按「先腾行」处理 |
| 8 | 🔵 | G1c 未断言 `pendingTitle` 为 null | 不改：该态 `_titleDeferred` 本就为 false，断言无判别力；测试档在 4144 上限 |

### 决策透明表

| 决策 | 选择 | 理由 |
|---|---|---|
| 「有连接」判据 | `_running`（`_connection != null && health.ready`）而非裸 `connection != null` | 启动中 / 未就绪同属「无可用连接」；`_revert` 本就要求槽 + 连接，二者同源；接口注释同步为「live connection to ask」 |
| 无连接改名的 notice 文案 | `The title was not confirmed: no connection` | 与既有失败文案同前缀，合 §3.5「error 文案只说未确认」 |
| 无连接改名后的状态 | `_dropTitleOf()`（清 target/deferred/sending） | 值保持原样 + 不留 pending；否则下次连接会把过期目标补发 |
| 摘要 notice 的去留 | 成功摘要整条删；错误面 `_revertFailed` 保留 | 父裁 ② 只指摘要；错误面是内核既有口径（与 Claude 内核同形） |
| 条件事件判据 | `outcome.files.isNotEmpty`（不用事件带条数） | 父裁 ③ 给的两个选项之一；事件无负载改动最小，恢复数由 `RevertOutcome` 供宿主 |
| 测试档守预算 | 同组行内压缩抵消新增行 | 4144 = 本段预算；压缩零语义改动，逐条断言保留 |

### 未做 / 边界

1. 设计档 / 需求档 / 外仓 / l10n / `lib/chat/**` / `lib/workspace/**`：本轮任务书明列不做，未碰。
2. G2 / G9 / G10 / G12 属下一轮；G3 归 UI 轮。
3. 上抛 1（设计档归属）与上抛 2（H2 消费 `RevertOutcome`）见下。

**上抛 1 [上抛·待裁]**：设计档三处需与父裁对齐（§4.1 ③ `:241` 删 `NoticeItem`、`ChangesReverted` 注条件；§3.4 `:206` notice 标宿主步骤；§3.5 `:229` / §3.3 `:147` 的 `canRevertNow` 补「有可用连接」）。本轮禁改设计档，未动。
**上抛 2 [上抛·知会]**：`revertSummary*` 三键现零调用（全在 l10n），H2 不消费 `RevertOutcome` 则设计 §3.4 `:206` / §9 `:381` 要求的会话内记录无人产出；已建议写进 H2 任务书。

### 交付摘要（宿主段 UI 层 · A1 · 第三轮）

按设计档 `docs/design/session-governance.md` §3.3–§3.5 / §4.1 ⑤–⑬、⑰–⑳ / §7 宿主侧 / §9 落地：

- **ChatSession 投影**：`revertTurn` / `canPlanRevert`（能力 × 空闲）/ `revertPlan(sinceTurn)` / `applyRevert(sinceTurn)` / `ownsTitle` / `pendingTitle`；宿主自写的会话内 notice（`addNotice`）；`ChangesReverted` 触发项目复查刷新。
- **workspace**：`rename` 三径（开放且内核可改名 / 目录短命连接 / `_names` 兜底）并返回 `Future<bool>`；`_names` 对可改名内核不参与显示与回放；自动标题器 `ownsTitle` 门（`hostTitlesSession`）；`AgentThread.pendingTitle`。
- **改名 UI**：三处 inline 字段（会话标题栏 / 侧栏行 / IDE 聊天标签）校验空白与 >80（字段不关、行内红字），等待态预填 `pendingTitle`；宿主名（可清空）以 `checksTitle: false` 保留原行为；关闭态改失败以 `showIdeDialog` 说明。
- **回退 UI**：ActivityStrip「Undo all」从 `revertTurn` 起（在飞灰态 + `revertTurnInFlight` tooltip）；用户消息右键「Revert files from this turn…」（在飞不构建）；确认框按内核 dryRun（计数 / >12 行滚动清单 / `displayPath` / warning / 跳过与无法回退分组 / Cancel 为默认）；结果框四组零组不显示；空计划提示；确认后复核空闲门（防确认框停留期间起轮）。
- **`ide_agent_edits`** 的 undo-all 菜单走同一确认流程。
- 内核层未改；l10n 未改；Claude / Codex 既有路径未改（`canPlanRevert` 假 ⇒ 旧径）。

### 改动清单（号 → 坐标 · 设计节号）

| # | 改动 | 坐标（现况行） | 设计节号 |
|---|---|---|---|
| 1 | 六个投影 + `addNotice` + `itemCount`/`itemAt` 尾表 + `ChangesReverted` 复查刷新 | `lib/chat/chat_session.dart:599-608` · `:712-718` · `:1012-1045` | §3.3 / §3.5 / §9 |
| 2 | ActivityStrip `undoTooltip`（灰态 + 悬停原因） | `lib/chat/panels/activity_strip.dart:31` · `:65-67` · `:502-511` | §9 |
| 3 | `onUndo` 走确认流程 / 在飞灰态与 tooltip / 标题预填 `pendingTitle` | `lib/chat/chat_screen.dart:461-464` · `:537-553` | §3.5 / §9 |
| 4 | 新档：确认框 / 结果框 / 空计划提示 / 计划→确认→执行（含空闲复核） | `lib/chat/panels/revert_dialog.dart:15-124` · `:160-204` · `:207-232` · `:236-348` | §9 / D-SG5 / A7 |
| 5 | 用户消息右键 turn 菜单 + `_turnMenu` 消费 | `lib/chat/chat_history_view.dart:1131-1137` · `:1744` · `:2058-2061` · `:2229-2284` | §9 |
| 6 | 右键回调（只报位置） | `lib/chat/widgets/user_message_bubble.dart:41-50` · `:188-194` | §9 / §4.1 ⑨ |
| 7 | 转发回调（bubble → item view） | `lib/chat/widgets/chat_item_view.dart:28` · `:42-43` · `:73` | §4.1 ⑨（清单漏项，见「越界」） |
| 8 | 字段校验 + 行内红字 + `checksTitle` 开关 | `lib/chat/widgets/inline_rename_field.dart:27-29` · `:63-82` · `:113-116` | §9 / §4.1 ⑩ |
| 9 | `rename` 三径 + `_names` 显示/回放门 + 标题器门 | `lib/workspace/workspace.dart:527-533` · `:2221-2229` · `:2648-2656` · `:2668-2697` | §3.3 / §3.4 / §4.1 ⑪ |
| 10 | `hostTitlesSession`（G2 判据） | `lib/workspace/agent_title.dart:22-26` | §3.3 / §4.1 ⑪ |
| 11 | `AgentThread.pendingTitle` | `lib/workspace/workspace.dart:122-124` | §3.5 |
| 12 | IDE undo-all 同确认流程 | `lib/ide/ide_agent_edits.dart:16` · `:862-879` | §4.1 ⑬ |
| 13 | IDE 聊天标签 / 侧栏行预填 + 侧栏改失败说明 | `lib/ide/ide_chat_title.dart:339` · `lib/ide/ide_tab_bar.dart:557-558` · `lib/sidebar/sidebar.dart:915-918` · `:1484-1493` · `:2944-2948` | §3.5 / §9 / §4.1 ⑫ |
| 14 | 用例：G2 / G3 / G9 / G10 / G12（含入口灰态与确认后起轮） | `test/workspace/agent_title_test.dart` · `test/chat/revert_flow_test.dart` · `test/kernel/thincoder_catalog_test.dart` | §7 宿主侧 |

### 行数实测 vs 预算（`split('\n').length`）

| 档 | 实测 | 预算 | 判 |
|---|---|---|---|
| `lib/chat/chat_session.dart` | 1268 | ≤1269 | ✅ |
| `lib/chat/chat_screen.dart` | 1285 | ≤1300 | ✅ |
| `lib/chat/panels/revert_dialog.dart` | 357 | 349（父裁实测值）+ 8（评审修复：确认后复核空闲门） | ⚠️ 超原实测 8，报告 |
| `lib/chat/chat_history_view.dart` | 3738 | ≤3739 | ✅ |
| `lib/chat/widgets/user_message_bubble.dart` | 1143 | ≤1146 | ✅ |
| `lib/chat/widgets/inline_rename_field.dart` | 121 | ≤121 | ✅ |
| `lib/workspace/workspace.dart` | 2865 | ≤2891 | ✅ |
| `lib/ide/ide_agent_edits.dart` | 942 | ≤944 | ✅ |
| `lib/chat/panels/activity_strip.dart` | 525 | 525（+5，父裁 ㉒） | ✅ |
| `test/workspace/agent_title_test.dart` | 60 | ≤65 | ✅ |
| `test/chat/revert_flow_test.dart` | 289 | 241（父裁实测值）+ 48（G12 入口/复核两例） | ⚠️ 报告 |
| `test/kernel/thincoder_catalog_test.dart` | 204 | ≤259 | ✅ |
| ⑫ 四档合计 | 3792 / 515 / 789 / 4585（+8 / +6 / +4 / 0） | ≤ +18 | ✅ (=18) |

### 验证读数

- `flutter analyze --no-pub`（本段 17 档）→ **No issues found!**
- `flutter test --no-pub test/workspace/agent_title_test.dart test/chat/revert_flow_test.dart test/kernel/thincoder_catalog_test.dart` → **+20 All tests passed**（G2 / G3 / G9 / G10 / G12）。
- `flutter test --no-pub test/kernel/thincoder_kernel_test.dart` → **+136 All tests passed**（非回归）。
- 追加回归：`test/workspace_test.dart` · `test/sidebar_test.dart` · `test/chat/session_review_test.dart` · `turn_marks_test.dart` · `pending_model_test.dart` · `change_tree_test.dart` → 全绿（合并跑 +183）。
- 行数复核命令：`node -e "…split('\n').length"`（各档逐条见上表）。

### 审计 / 评审轮次与终态

1. **内部 explore 偏差审计 · 1 轮 · changes-required**：
   - 🔴「`revertTurn` 可空不能传入 `String` 参数」= **假阳性**：`flutter analyze` 对 `chat_screen.dart` 实跑 `No issues found!`（且先前 `revertTurn!` 曾报 `unnecessary_non_null_assertion`）——Dart 流分析经 `final canPlan` 布尔传播提升成立。未改代码。
   - 🟡「摘要零值抑制 vs §9 三条片段全连」= **保留抑制**：l10n 轮的评审记录已把「零值抑制」定为本轮口径（`§5` l10n 段），全连会读出「Reverted no files · …」。
   - 🟡 out-of-list：`chat_item_view.dart` 为必需转发层（bubble → item view → history），已在报告登记；`agent_title.dart` 为 G2 判据落点，已登记。
   - 🔵 `workbench.dart` 表列而未改：实读确认无行为缺口（开放会话恒真、失败由内核 notice 呈现），报告不改。
   - 🔵 **共享字段把宿主名改名也套上标题校验**（侧栏 `:915`）：已修——`InlineRenameField` 增 `checksTitle`，宿主名传 `false`，保留「清空即回本名」的既有语义。
2. **advisor 代码评审 · 1 轮 · pass（0🔴 / 4🟡 advisory / 5🔵）**；已取修正：
   - 🟡 确认框停留期间可起轮 ⇒ `revertFiles` 在 `confirm` 之后复核 `session.canPlanRevert`，不满足即 `blocked`（`revertTurnInFlight` 提示）且零写入；补 G12 用例。
   - 🟡 开放会话 + 内核无改名能力时 `_names` 兜底不可达（Codex 重启丢名）⇒ 改判据为「内核可改名才走内核径」，其余仍落 `_names` + `_save()`。
   - 🔵 `_turnMenu` 跨次残留 ⇒ 进入 `_showTurnMenu` 先清。
   - 🔵 `taken` 命名 ⇒ `accepted`。
   - 🔵 G12 入口判别力 ⇒ 补 ActivityStrip 灰态 + tooltip 的 widget 用例。
   - 未取（报告项）：宿主摘要落尾表而非 transcript（`lib/kernel/transcript.dart` 本批冻结）、关闭会话失败弹窗英文（l10n 21 键冻结）、`=0` 分支不可达、在飞门三处各写一份、`dart format` 形态、灰态只覆盖「在飞」不覆盖「无连接」。
3. **终态：clean**（无未处置代码阻断项；上述未取项均为「设计/文件冻结面」或口径观察，已在本段与报告登记）。

### 决策透明表

| 决策 | 选择 | 理由 |
|---|---|---|
| 在飞 tooltip 的落点 | ActivityStrip 灰态 + `IdeHover`；右键项在飞不构建 | 父裁 (b)/(a)：菜单面无 tooltip，`ide_menu.dart` 不在清单 |
| 摘要零值组 | 抑制（只连非零片段） | l10n 轮评审已定「零值抑制属 H2 / §9 口径」；全连会读出 `=0` 噪声 |
| 宿主 notice 落点 | `ChatSession._notices` 尾表（经 `itemCount`/`itemAt`） | `transcript.dart` 本批零改动（设计 §4.1 零改动清单） |
| 关闭会话改失败文案 | 英文单行 `Could not rename this session.` | l10n 21 键锁定，设计只要求「单行说明」；登记待 l10n 轮补键 |
| 字段错误提示形态 | `suffixText` 行内红字 | 三处宿主行高 24–30px，`errorText` 会撑破布局（设计 §9 只要「行内红字」） |
| 宿主名改名 | `checksTitle: false` | 共享字段不得把「标题」规则套到可清空的宿主名上 |
| 确认后复核空闲 | 复核 `canPlanRevert`，失败给 `revertTurnInFlight` 提示 | §3.5 末条：在飞时计划与执行之间盘面必漂 |

### 越界 / 设计外改动（如实登记）

1. `lib/chat/widgets/chat_item_view.dart`（+4 行）：bubble 回调的必需转发层，设计清单 ⑨ 未列。
2. `lib/workspace/agent_title.dart`（+8 行）：`hostTitlesSession` 判据，设计把该门记在 `workspace.dart`。
3. `lib/chat/widgets/inline_rename_field.dart` 的 `checksTitle` 开关（+3 行）：修正共享字段对宿主名改名的连带影响（审计 🔵）。
4. `lib/ide/ide_tab_bar.dart` + `lib/ide/ide_chat_title.dart`：`renameInitial` 仅为「行显示已确认标题、字段预填 pendingTitle」分离而加。

### 未做 / 边界

1. 加载历史里的用户消息没有本进程回合键（`session.turns` 只含本轮报告过的回合）⇒ 右键项不出现；内核本也会答 `unknown turn`（设计 §2.4「栈随进程」），登记为口径边界。
2. 「文件被改过 ⇒ 跳过」等核侧判定不在本段（H1 已交付，G13–G20 外仓档）。
3. 关闭会话改失败弹窗的 l10n 键未加（l10n 冻结）；`workbench.dart` / `ide_tab_bar.dart` 的 rename 调用点未改（实读无缺口，设计 ⑫ 过度列举）。
4. 本段未提交（按任务书）。

**坐标勘误（本段收工前逐处回读，覆盖上面「改动清单」的现况行）**：#1 `chat_session.dart:602-609`（`ownsTitle` :603）· `:711-718`（`itemCount` :711）· `:1013-1045`（`addNotice` :1038）；#2 `activity_strip.dart:66-67` · `:498-506`（`this.undoTooltip` :31）；#3 `chat_screen.dart:461-464` · `:538-553`；#4 `revert_dialog.dart:15-126`（`revertFiles` :45）· `:168-213` · `:215-242` · `:244-356`；#5 `chat_history_view.dart:1133-1137` · `:1747` · `:2060-2063` · `:2230-2285`（`_showRevertMenu` :2272）；#6 `user_message_bubble.dart:41-53` · `:192-194`；#7 `chat_item_view.dart:28` · `:43` · `:73`；#8 `inline_rename_field.dart:28-29` · `:62-86` · `:114-116`；#9 `workspace.dart:531-537` · `:2226-2229` · `:2651` · `:2672-2703`；#10 `agent_title.dart:22-26`（`hostTitlesSession` :25）；#11 `workspace.dart:122-124`；#12 `ide_agent_edits.dart:16` · `:862-880`（`revertTurn` :865）；#13 `sidebar.dart:915-918` · `:1484-1493` · `:2944-2948` · `ide_chat_title.dart:339` · `ide_tab_bar.dart:557-558` · `:699`。

## §6 验证与收口（父代理）

## 6. 验收与收口

**实施分段**：外仓段（eng-coder #89，9 档）→ 宿主内核层（#90 + 修正 #92）→ l10n（#91）→ 宿主 UI 层（#94）→ 设计收口（#93）。

**父侧复跑读数（2026-10-20 01:58）**

| 命令 | 结果 |
|---|---|
| `flutter test --no-pub test/workspace/agent_title_test.dart test/chat/revert_flow_test.dart test/kernel/thincoder_catalog_test.dart test/kernel/thincoder_kernel_test.dart test/l10n_test.dart` | **+180 All tests passed** |
| `flutter analyze --no-pub`（改动 17 档） | No issues |
| `flutter analyze --no-pub lib/chat lib/workspace lib/ide lib/kernel` | 4 条 info，全在**本批未触碰**档（`debug_editor_glue.dart` ×3 · `ide_code_find.dart` ×1，存量） |
| `node --test thincoder/docs/batches/2026-10-20-session-governance-a1.test.mjs` | **9/9** |
| 外仓 `git -C thincoder status --porcelain` | 34 → 41（+7：本批声明档，无删除） |
| 行数 | 逐档 ≤ 预算（唯一例外：`revert_dialog.dart` 357、`revert_flow_test.dart` 289，父裁接受并已回填设计档） |

**验收对照（需求档 §4 A1–A7）**

| # | 判据 | 结论 | 证据 |
|---|---|---|---|
| A1 | 改名后桌面与 `session/list` 同值；再跑一轮不变 | ✅ 机检 | 核侧 G19（槽 title + manifest + `agent.title` 同拍）· 宿主 G1/G1b/G9 · 自动标题门 G2 |
| A2 | 空白标题被拒、值不变 | ✅ | G3（widget 层，`inline_rename_field`） |
| A3 | 非 Git 临时目录三写 ⇒ 回退复原 | ✅ | 外仓 G14（真目录 + `undoApply` 逐文件） |
| A4 | 回合后被用户改过 ⇒ 跳过并列 | ✅ | 外仓 G15 + 宿主 G6 |
| A5 | 超限 / 逐出 ⇒ 无法回退清单，部分成功 | ✅ | 外仓 G16/G17 + 宿主 G7 |
| A6 | Claude 内核非回归 | ✅（带注） | Claude kernel 用例全绿；`test/kernel_test.dart` 整档 96/8/4，4 条为既有 `bao_remote` 平台/环境项（本机无 Claude、Windows 路径分隔），非本批 |
| A7 | 取消 ⇒ 零文件改动 | ✅ | G10 + G20（`dryRun` 零写入零出栈） |

**未在本批闭合（登记为台账，不静默）**

- **#106** 挂起窗提交的用户回合丢 `turnId` ⇒ 该回合不能单独作为回退起点（+6 行透传，归批 A1 之后）。
- **#107** l10n 无「源档 ↔ 生成档」值比对护栏。
- **#108** 标题 80 上限在文案层硬编码 4 处（条件项）。
- **真机走查未做**：A1 的「桌面与终端同标题」与「真实回合的回退」在 mock/核内测试层已验，**真 CLI 走查待用户启动 app 完成**（见 §6 附注）。

**父侧直改（已标记、可回退）**

- `docs/design/session-governance.md` ⑦/⑱ 预算改为实测值（349 / 241）。
- `docs/design/thincoder-adapter.md` 五处机械修正（本批名册 · `session/prompt` 的 `turnId?` · §7 B1 例外 · §10 边界删「回退/改名」· §5.2 缝行），闭合评审 R1 #4 的残留；`doc_check` 本批两档零新增。

**状态**：实现与机检完成；真机走查待做。

**真机走查读数（用户 2026-10-20 02:34 / 02:47 / 02:56）**

| # | 验项 | 结果 |
|---|---|---|
| ① | 桌面改名 ↔ 终端 | ✅ 通过——「baocode 和终端命名可以通过 session 切换来更新名字」（用户原话）；改名四手势可用（双击 / 右键 Rename / F2 / 命令面板搜「重命名」） |
| ② | 回合级回退入口 | ✅ 通过——右键用户消息出现「回退文件」；输入框上方「全部撤销 / 全部保留」在场 |
| ③ | 在飞态 | ✅ 通过——「是灰的无法点击了；运行过程中没有回退项」（用户原话） |

**走查期修掉的两处（轻渠道笔，均在 §1 记）**

1. 命令面板搜不到 Rename Agent：首笔只加行未接命令源（`_chatCommands()` 不含聊天自有命令）⇒ 二笔按按键分发同路径取 `ChatKeys.commandsOf(chat)`；另发现中文界面按本地化标题匹配（搜「重命名」而非「rename agent」）。
2. 在飞「全部撤销」仍可点：在飞分支回落到宿主 `undoAllChanges`（review 的 `undoAll`）⇒ 改为**实现了 `PlansReverts` 的内核永不回落**（新增 `ChatSession.plansReverts`），在飞 = `onUndo: null` + `revertTurnInFlight` tooltip。

**收口读数**：`flutter analyze` 改动档 0 issue；`revert_flow_test` + `thincoder_kernel_test` **145/145**；外仓 9/9；`test/ide/git` 无关。**A1 完成。**
