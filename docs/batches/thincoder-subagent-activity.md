# 2026-10-16 · thincoder 子代理活动可见（批 4）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-16 · 来源 = 用户 2026-10-16 09:08 拍板开批（会话裁定；需求档 F11）。
> 台账 = #10（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-18


- **开批**（2026-10-16）：用户走查批 1 后提出「主代理异步调子代理时，桌面看不出它还在跑」。核对：thincoder 0.12.74 已在推子代理信号 `session_info_update._meta["thincoder.dev/subagent"]`，批 1 按设计忽略（设计 §14-4 登记「需要展示时接」）；宿主既有子代理 UI 面齐备（Claude Task 在用同一套）。用户当日 09:08 拍板开批。
- **范围（四条）**：① 子代理卡片（出现/进度/完成）② 活动条运行代号与计时 ③ 会话状态行「N 个子代理运行中」④ 长回合静默期活动指示。
- **授权口径**：本仓适配层翻译 + 既有面接线；不动 `thincoder/`（B1）；控制面（停止/转后台）以 ACP 能力为准，无则纯显示态。
- **需求落点**：需求档 F11（`docs/requirements/thincoder-adapter.md:81-84`）。
- **前情**：批 1（thincoder 内核适配）已收口（`docs/batches/thincoder-kernel.md`）。
- **文案对位**：F11 行文含「后台」二字；设计复用既有 l10n 键 `stripAgentsRunning`（`{count} 个子代理运行中`，无「后台」；该键为 Claude 面共用，不改键文）。

- 父侧机械随修（2026-10-16，可回退，父侧直接执行）：设计 §15.4 ⑪/⑰ 读数与缝坐标刷新为修正轮 2 后实测（638 / 1537 · `:1371`/`:1416`/`:1433`/`:1525`）——纯计数/坐标，零语义。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（批 4 · F11 子代理活动可见；评审过（🔴0 / 🟡4 / 🔵4）→ 修正轮 1 落地 #1–#8 → 交付随修 → 点修（守卫口径扩展：墓碑键任何迟到报告 ⇒ 忽略 + 实交读数刷新）；零代码改动）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖）**（需求档 F11，批 4；用户 2026-10-16 拍板开批）

| # | 条目 | 设计落点 | 判据 |
|---|---|---|---|
| 1 | 信号→面翻译表（state 开集 → 卡片 / 活动条 / 状态行；未知态前向兼容 E4） | §15.2 | 8 态表 + 未知 / 坏载荷处置；用例 T28–T33、T37 |
| 2 | 挂起态语义（prompt 应答已回、后台子代理仍跑：状态行呈现 + 与回合结束模型共存） | §15.3 | 活动条 / 侧栏挂起期持续；再发消息照常；T35 |
| 3 | auto-turn digest 原生到达的处置 | §15.3 + §15.8-① | 不合成回合边界（ACP 实核无信号）；文本照常入 transcript；T34 |
| 4 | 静默期活动指示载体（复用既有面，对齐 Claude 面语义） | §15.6（F11 ④）+ §15.9 | 活动条行 + 每秒计时 + 装填动效（与回合状态无关） |
| 5 | 控制面判定（仅当 ACP 有能力才提供 ⇒ 纯显示） | §15.5 D22 + §15.8-③ | 不声明 `RunsBackgroundTasks`；无停止 / 转后台；接线 ⑫⑬ |
| 6 | 测试 / 固件面 | §15.4 ⑮⑯⑰ + §15.7 | 固件 5 档（`subagent-*`）+ 用例 T28–T37；mock 零改（`push` 既有） |
| 7 | 与 §14-4 判定条件闭合 | §14-4（改写）+ §15.8 | 判定条件达成；剩余边界逐条带判定条件 |
| 8 | 零代码改动 + 真机走查步骤 | §15.6（走查 7 步 + 折叠注） | 本轮只改文档（设计档 + 本批次档） |

**设计档落点**：`docs/design/thincoder-adapter.md` 新增 **§15 批 4：子代理活动可见（F11）**（494 → 654 行）；随改 §3.4 通知表 · §3.6 翻译表 · §5.2 尾指针 · §7（F11 行）· §9 · §10（原「子代理结构化＝仅忽略」句随批 4 撤）· §11 · §12-A-4 · §14-4（判定条件闭合改写）· §14-15（新增）· 变更记录。

**机制设计（摘要）**

- 载体：`session_info_update._meta["thincoder.dev/subagent"]`（role/id/state/progress?/detail?；state 开集 8 名：queued/async/turn/approval/cancelled/stopped/settled/done）。
- 身份 = `role#id`；记录 id = `subagent:<role>#<id>`；显示名 = `<role>#<id>`（对齐 thincoder VSC 块标题措辞）。
- 卡片（`AgentItem`）：首见建卡（先 `closePiece()`）；queued→activity「queued」；turn→「turn n/max」；approval→「approval · tool」；settled→succeeded + duration；stopped→failed；cancelled→ItemRemoved；未知 state 保 live + 留痕。`AgentItem.id` 留空 ⇒ 不可打开、无动作（display-only）。
- 活动条（`KernelTask` + `TasksReported` 全量重报）：`async`/`turn` 起建；queued 不进（活动条 = 运行中）；>3 折叠计数行（既有）。
- 控制面：不声明 `RunsBackgroundTasks`（ACP 无子代理级方法）；宿主接线两处——⑫ `chat_session.tasks` 门控拆开（显示与停止能力解耦）+ `canStopTasks`；⑬ `chat_screen:515` `onStopTask` 按能力取 null。
- 进程退出：在跑子代理定格 failed（summary「thincoder stopped」，同 Claude `endTasks` 形）。
- 挂起态 / digest：回合结束后靠活动条 + 侧栏 `shownStatus` 保可见；digest 原生到达 ⇒ 不合成回合（D26）。

**受影响文件与测试覆盖**：⑪ `thincoder_events.dart`（413 → ≤593；+150≤N≤+180）· ⑫ `chat_session.dart`（+8）· ⑬ `chat_screen.dart`（+1）· ⑭ `thincoder_kernel.dart`（+4）· ⑮ 固件新增 5 档 · ⑯ `thincoder_fixtures_test.dart`（+25）· ⑰ `thincoder_kernel_test.dart`（+80）。mock / claude_code / thincoder 仓零改动。

**验收对照**：需求档 F11 四条 → §15.6 对照表；真机走查 7 步（A 段交付执行，含卡片折行预期注）。

**关键决策**：D21–D30（§15.5，含被否方案）。**上抛项**：无阻塞项；两处登记 = §15.8（剩余边界与判定条件）、§14-15（状态文案英文占位，同 §14-14 口径）。

（批 4 修正轮 1 · 2026-10-16 · 设计评审 #1–#8 全部 Accepted 落地；纯档面修订、零代码改动）

| # | 落点 | 改动 |
|---|---|---|
| 1 | §5.2 体量名单 + §15.4 | `chat_screen.dart` 入 >800 既有档名单（结构不动 · 缝候选 `:903` 起私有构件族 · 触发 = 独立拆分批）；`thincoder_kernel_test.dart` 体量裁定（用例增补 · 按 group 拆缝 · 触发 = 独立拆分批） |
| 2 | §15.4 + §5.2 | kernel +4 = 接线级改动、不触发顺拆；§5.2 触发句补「触碰按结构级改动计」 |
| 3 | §15.6 + §15.7 | 走查步 3 补 approval 观察点、步 7 补首帧终态 / 已建取消；用例 T38（approval 有 / 无 detail）· T39（首帧即终态） |
| 4 | §15.2 + §15.7 | 已建任务下 `cancelled` 处置 = 移除（不残留 running）+ 契约坐标（ACP-CLIENT.md §12.3 / `subagent-async.mjs:297`·`:222-226` / `subagent-blocks.mjs:184-186`）；用例 T40 |
| 5 | §15.2 | `{position}` = 不展示（queued 由卡片 + detail 承载） |
| 6 | §5.2 + §6-D2 | 快照数字刷新为当前值（chat_session 1087 · workspace 2795 · kernel 885 等 9 档 + D2 残余行数） |
| 7 | §14-15 | 枚举补 `thincoder stopped` |
| 8 | §15 引言块 | 删沿革括注「（§14-4 已改写）」 |

- 号外（一致性面随修，均已报告）：3 行超宽拆行（§12-A-4 核对线形 / §15.3 digest / §15.4 体量行，纯换行零语义）；⑰ 上界随 T38–T40 调至 ≤ +115。
- 设计档变更记录 +1 行；验收 = 8 项逐条落档（号 → file:line 见交付报告）。

**实施交付读数 + 裁定**（批 4 · 交付后随修 · 2026-10-16；纯档面、零代码改动）

- **实交读数（替设计估算）**：⑪ `thincoder_events.dart` 413 → 608（+195；估 +150~+180）· ⑫ `chat_session.dart` +5（估 +8）· ⑬ `chat_screen.dart` 1 行改动（净增 0）· ⑭ `thincoder_kernel.dart` +3（估 +4）· ⑯ `thincoder_fixtures_test.dart` 178 → 191（+13；估 +25）· ⑰ `thincoder_kernel_test.dart` 1092 → 1442（+350；估 ≤ +115）· ⑮ 固件 5 档新增 · 表外补录 ⑱ `test/fixtures/thincoder/README.md` +1 行（`expect` 键清单补 `tasks`，与固件 `_check` 键集同步）。
- ⑪ / ⑰ 超估算未破结构裁定（⑪ = 608 < 800 硬顶、不拆；⑰ 只增 group，缝候选与触发不变）⇒ 设计 §15.4 文件表（实交栏）与体量条、§5.2 kernel 条已按读数刷新（⑰ 缝坐标随实交刷新 = `thincoder_kernel_test.dart:1277` 起四组）。
- **裁定（父侧）· 终态后契约外报告 ⇒ 忽略**：同一 `role#id` 在终态（succeeded / failed / 卡片已移除）之后再收到 `queued` / `async` / `turn` / `approval` ⇒ 契约外失序、一律忽略（卡片不回动、活动条不复活）；实现 = 统一守卫（`queued` / `async` 补与 `turn` / `approval` 同款护栏）——由紧随的 coder 修正轮落地；用例 T41 随该轮入测试档。设计落点 = §15.2（两行 + 口径）· §15.5 D31 · §15.7 T41 · §15.8-7。
- 父侧复跑：`flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` = 58/58 全绿（T28–T40 + 固件复放）。
- 号外一致性随修（均已报告）：⑬ 实交精度同步（1 行改动 / 净增 0；§15.4 + §5.2）· §5.2 kernel 条读数（+3 / 888）· §5.2 kernel 条拆行（加读数后越 300 宽，纯换行零语义）。设计档变更记录 +1 行。

**点修 · 守卫口径扩展 + 实交读数刷新**（批 4 · 2026-10-16；来源 = §5 修正轮 1 上抛，评审同源；纯档面、零代码改动）

- 口径扩展（父侧裁定）：卡片已移除（`cancelled` 墓碑）后同键**任何**迟到报告（四态 + `settled` / `stopped` / `done` / 未知态）⇒ 契约外 ⇒ 忽略——不按首见重建（幽灵卡）、不报条；与四态口径并列为一条统一规则；判定条件句保留（thincoder 侧「同 id 重跑」契约更新 ⇒ 接续面重修）。实现面解耦（墓碑臂先于四态守卫）与 T41 非四态臂由随后的 coder 修正轮落。
- 实交读数刷新（随守卫修正轮）：`thincoder_events.dart` 413 → 637（+224；修正轮 609 → 637 +28）· `thincoder_kernel_test.dart` 1092 → 1524（+432；修正轮 1443 → 1524 +81）；缝坐标 `:1277` → `:1358` / `:1403` / `:1420` / `:1512`（旧起点已落于 T41 体内）。

| # | 落点 | 改动 |
|---|---|---|
| 1 | §15.8-7 · §15.5 D31 | 口径扩展：墓碑键任何迟到报告 ⇒ 忽略（与四态并列一条统一规则）；判定条件句保留 |
| 2 | §15.2 规则行 + 状态表 `queued` / `async` 行 · §15.7 T41 | 同规则同步（复述行、行注、用例输入列随扩展；已移除后不重建含非四态） |
| 3 | §15.4 ⑪ · ⑰ 行与体量条 | 实交读数刷新（⑪ 637 · ⑰ 1524）· 缝坐标 `:1358` 起 · ⑪ 行随修正轮同步（号外） |
| 4 | 变更记录 | +1 行 |

- 验收：口径与随后的 coder 守卫扩展实现一致（忽略 = 不重建、不报条）；零代码改动；行宽 <300。
- 未做（本单边界）：实现代码（coder 轮）· §15 之外章节实质内容 · 批次档 §1 / §4 / §5 / §6。
- 号外（一致性面随修，已报告）：⑪ 行实交读数随修正轮同步刷新（非点名项）；§5 交付表 ⑪ 608 与修正轮起点 609 的 1 行读差留记录面（不在本单处置）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

范围：§15 新增节（批 4：子代理活动可见 / F11）及随改（§3.4 / §3.6 / §5.2 / §7 / §9 / §10 / §11 / §12 / §14-4 / §14-15）；批 1–3 冻结内容不在本轮范围。限界：无 AGENTS.md、无文档地图、需求档不在评审范围（F11 条目覆盖仅按 §15.6 自列 ①–④ 判）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Affected-file size annotations | 🟡 | §15.4 改动的 4 个 >800 行档中，`chat_screen.dart`（`docs/design/thincoder-adapter.md:564`「`lib/chat/chat_screen.dart`（1231 行）」）与 `test/kernel/thincoder_kernel_test.dart`（`docs/design/thincoder-adapter.md:568`「`test/kernel/thincoder_kernel_test.dart`（1092 行）」，+80 ⇒ ≈1172）无任何体量裁定：§5.2 体量立场（`docs/design/thincoder-adapter.md:311`「体量立场（两个 >800 行既有档 + 新档的拆分审阅）：」）与 §15.4 体量行（`docs/design/thincoder-adapter.md:571` 仅涉 `thincoder_events.dart`）均未覆盖这两档——无「结构不动」声明、无缝候选、无触发；而 >800 已按硬顶口径处理（`docs/design/thincoder-adapter.md:313` 对 `chat_session.dart` 给出裁定） | 照既有裁定形（`docs/design/thincoder-adapter.md:313`）为这两档各补一条体量行：结构不动 + 缝候选 + 触发 = 独立拆分批；并把 `chat_screen.dart` 纳入 >800 既有档清单 |
| 2 | Affected-file size annotations（裁定触发） | 🟡 | §5.2 对 `thincoder_kernel.dart` 的裁定（`docs/design/thincoder-adapter.md:315`「续拆裁定 = 不续拆」）自带触发句「触发 = 独立拆分批立项（或下次触碰该档时顺拆）」（同档 `docs/design/thincoder-adapter.md:315`），而 §15.4 ⑭（`docs/design/thincoder-adapter.md:565`）本批即触碰该档（885 → 889），未表态是否触发顺拆 / +4 接线是否算「触碰」⇒ 该触发句在批 4 语境下悬置 | 在 §15.4 体量行补一句口径：批 4 对 kernel 的 +4 行属接线性改动、不触发顺拆（或给出顺拆落点），与 §5.2 触发句对齐 |
| 3 | Acceptance criteria | 🟡 | §15.7 用例表（T28–T37）与 §15.6 走查 7 步未覆盖状态机两行：`approval`（`docs/design/thincoder-adapter.md:540`「`approval · <detail>` ∥ `approval`」）与「首见（任意 state）」（`docs/design/thincoder-adapter.md:536`）的首帧即终态路径（首帧 `settled` / `stopped`）——契约内路径无断言、无走查观察点 | 补 2 条用例（`approval` 有 / 无 `detail`；首帧即终态），或为走查步指定该观察点 |
| 4 | Clarity（边界处置缺失） | 🟡 | `cancelled` 行（`docs/design/thincoder-adapter.md:543`「**ItemRemoved**（从未启动，无活动可留」）的处置只覆盖「从未启动」，活动条列「无（从未建）」；若 `cancelled` 在已建任务（`async` / `turn` 之后）到达，任务无处置 ⇒ 可残留永久 running 的活动条行，与 `docs/design/thincoder-adapter.md:550`「不留「永远在跑」的卡片」相悖；T31（`docs/design/thincoder-adapter.md:617`）只覆盖 queued → cancelled | 补一行已建任务下的 `cancelled` 处置（任务定格 failed 或移除 + 卡片 ItemRemoved），或注明服务端保证 `cancelled` 只在排队态到达（附坐标），并配一条用例 |
| 5 | Clarity | 🔵 | `progress` 域列两形（`docs/design/thincoder-adapter.md:523`「`{turn,maxTurns}` ∥ `{position}`」），状态机只用 turn / maxTurns（`docs/design/thincoder-adapter.md:539`「（单值取有者；皆无 ⇒ 不覆盖）」）⇒ `{position}` 形无展示落点、也未明说忽略 | 补半句：`{position}` ⇒ 展示为 X，或明确「不展示（留痕 / 忽略）」 |
| 6 | Doc-state（numeric drift） | 🔵 | 同日快照两处不一致：`thincoder_kernel.dart` §5.2「残余 818 行（2026-10-16 快照）」（`docs/design/thincoder-adapter.md:315`）vs §15.4 ⑭「（885 行）」（`docs/design/thincoder-adapter.md:565`）；`chat_session.dart` §5.2「`chat_session.dart` 1085」（`docs/design/thincoder-adapter.md:308`）vs §15.4 ⑫「（1087 行）」（`docs/design/thincoder-adapter.md:563`） | 刷新 §5.2 快照数字，或注明两处基准日不同（§5.2 = 批 1 编制日、§15.4 = 批 4 编制日），使「编制日快照」口径可用 |
| 7 | Doc hygiene（登记完备） | 🔵 | §14-15 的英文占位枚举（`docs/design/thincoder-adapter.md:486`「卡片 activity 与活动条详情英文直写」）未含进程退出定格串 `thincoder stopped`（`docs/design/thincoder-adapter.md:550`「summary = `thincoder stopped`」，T36 期望同串 `docs/design/thincoder-adapter.md:622`） | §14-15 枚举补 `thincoder stopped`（或改成「含但不限于」的口径） |
| 8 | Doc hygiene | 🔵 | §15 引言块「（§14-4 已改写）」（`docs/design/thincoder-adapter.md:493`）属修订沿革指注落在规范面（沿革已由变更记录 `docs/design/thincoder-adapter.md:653` 承载；非失效残留，但同修正轮 4 的「按现状表述」口径） | 删该括注，保留「判定条件就地闭合」的现状表述即可 |

已核通过（无发现）：文档归属——§15 属本档（既拥有该主题的设计档）的续节，随改各节均为指针式同步，未另立文件、未与既有节重复描述 · 最邻近先例行——§15.1 给出实现坐标 + 对齐 ∥ 偏离理由（D23 偏离 thincoder TUI 亦附理由）；「无设计档 / 批界先例」的显式声明见 `docs/design/thincoder-adapter.md:48`。

VERDICT: pass

计数：🔴 0 · 🟡 4 · 🔵 4

## §4 用户批准（主 agent）

- **批准**（2026-10-16 18:11）：用户批「开工」。前置已闭合——设计评审 VERDICT pass（🔴 0 / 🟡 4 / 🔵 4，§3 轮次 1）+ 修正轮 1 全项落档、父侧核验 8/8（§2）。
- **实施**：eng-coder 单批派单（实现 → 审计 → 自检 → 交付）；本批 = 显示态实现（D22），无控制面。
- **验收口径**：设计 §15.7 用例 T28–T40 + §15.6 真机走查 7 步（走查在交付后与用户约时进行）。

## 用户批准（2026-10-18）

- 用户 2026-10-18 23:53「把哪几个在途做完吧」= 批准本批收口（实施 2026-10-16 已完成，审计 clean / 评审 pass）。

## §5 实施记录（eng-coder）
**状态行**：实施完成（批 4 · F11 子代理活动可见；显示态（D22）· 主实现轮（审计 + 两轮评审收敛，clean）+ 修正轮 1（终态后契约外报告守卫 + T41）+ 修正轮 2 点修（墓碑后任何迟到报告 ⇒ 忽略 + T41 非四态臂；审计 clean / 评审 pass，🔵 1 归父侧））


### 交付摘要（改动坐标 · 实测行数）

| # | 坐标 | 改动 | 实测 |
|---|---|---|---|
| ⑪ | `lib/kernel/thincoder/thincoder_events.dart` | `session_info_update` 分支从忽略改为子代理翻译（§15.2 八态 + 未知态 + 坏载荷）；新增 `subagent()` / `endSubagents()` / `_card` / `_putSubagent` / `_reportTask` / `_endTask` / `_reportTasks` / `_stateLine` / `_named` | 413 → 608（+195） |
| ⑫ | `lib/chat/chat_session.dart` | `tasks` 门控拆开（只留 background ∧ running；空表 ⇒ null）+ 新增 `canStopTasks`（= 内核实现 `RunsBackgroundTasks`） | +5 行 |
| ⑬ | `lib/chat/chat_screen.dart` | `:515` `onStopTask: _session.canStopTasks ? _session.stopTask : null` | 1 行改动（净增 0） |
| ⑭ | `lib/kernel/thincoder/thincoder_kernel.dart` | `_teardown()` 调 `_events.endSubagents()`（覆盖 release / dispose / 进程退出 / restart 全部路径） | +3 行 |
| ⑮ | `test/fixtures/thincoder/` | 新增 `subagent-lifecycle`（21 帧）· `subagent-parallel-queued`（15）· `subagent-cancelled-stopped`（19）· `subagent-unknown`（18）· `subagent-digest`（14） | 5 档新增 |
| ⑯ | `test/kernel/thincoder_fixtures_test.dart` | `_shown` 增子代理卡行（`agent <status>: <role>#<id>[ · activity]`）+ `expect` 增 `tasks` 键（`_running`） | 178 → 191（+13） |
| ⑰ | `test/kernel/thincoder_kernel_test.dart` | 新增 group「thincoder subagents」9 个用例覆盖 T28–T40 + 助推帧（`_signal` / `_update`）+ `_Session.cards` / `_Session.running` | 1092 → 1442（+350） |

表外改动 1 处（已申报）：`test/fixtures/thincoder/README.md` 的 `expect` 键清单补 `tasks` 一行（同目录；与新 `_check` 键一致）。

### 决策透明表

| # | 决策 | 理由 |
|---|---|---|
| 1 | 终态三态（`settled`/`stopped`/`done`）合并为一支，动作条件 = 卡仍在 running | `settled` 即 succeeded（D25）、`stopped` 定格 failed（D24）、`done` 只是归档标记；合并后 `done` 无前序 `settled` 也不会留 running 卡，且重复 `done` 幂等 |
| 2 | `endSubagents()` 收尾清空 `_subagents` / `_tasks` 两表 | 进程重启后 thincoder 的 `role#id` 计数从头起（取号载体 = agent 本体内存计数）⇒ 同键再现属另一个子代理；不清表会把已定格卡当基准续写（状态 / 起算时刻被复用） |
| 3 | `_putSubagent()` 兼作表写入（每次展示都落表） | 「不覆盖」分支读的是最近一次展示的卡；只写首见值会让 `turn` 无 `progress` 时退化成首见卡——该缺陷由 T28 新增的单值 progress 断言查出并修 |
| 4 | `turn` / `approval` 的活动条动作加「卡仍在 running」护栏；未知态只留痕、不动任何面 | D27「宁可多示在跑，不可隐藏在跑」；E4 开集容忍；护栏防终态卡被同键报告复活 |
| 5 | `progress` 只有 `maxTurns`（无 `turn`）时不覆盖状态行 | 设计 §15.2：「单值取有者；皆无 ⇒ 不覆盖」；`turn` 缺席时没有可示形（D28 形固定，不发明新文案）——代码评审轮 1 已复核 Accepted |

### 审计与代码评审轮次与终态

- **内部发散审计**（explore，只读，对着设计 §15 逐节核）：无阻塞项。容量口径偏差 2 项 + 注记 4 项。收口动作：T32 的留痕断言补到未知态那一行（原先只覆盖坏载荷）；`subagent-parallel-queued` 输入对齐 T29 的「4 个 async」（原含一个 `turn`）。
- **代码评审轮 1**（独立评审子代理，全文核）：`VERDICT: pass`（🟡1 / 🔵4）。
- **代码评审轮 2**（修复核验）：`VERDICT: pass` —— 🟡（终态卡复活活动条行 + 收尾漏报）已修（`thincoder_events.dart:438` 护栏、`:479-487` 任务趟与重报先于清表）；🔵 两项已修（`// Hanging on past the turn (T35).`、补 `expect(s.kernel, isNot(isA<RunsBackgroundTasks>()));`）；🔵 一项 Accepted（上表 #5）。
- **终态：clean**（无未决 🔴 / must-fix 🟡）。

### 测试与读数

- `flutter analyze lib/kernel/thincoder/thincoder_events.dart lib/kernel/thincoder/thincoder_kernel.dart lib/chat/chat_session.dart lib/chat/chat_screen.dart test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` → `No issues found!`
- `flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` → `All tests passed!`（58 例：新增 9 个 subagent 用例覆盖 T28–T40 + 5 档固件复放 + 既有 44 例零回归）
- 单测文件随批留档（复跑 = 直接 `flutter test` 该两档；不进任何门）；集成面本批零改（无新增业务场景）。

### 未做 / 偏差 / 上抛项

- **偏差（仅容量口径，无行为偏差）**：⑪ 实交 +195（设计预估 +150~+180）；⑰ 实交 +350（设计预估 ≤ +115）。两档均未破结构裁定：⑪ 608 < 800 硬顶、结构不拆；⑰ 结构未动（新增 group，缝候选与触发按 §15.4 不变）。属「设计档数字未随交付刷新」，父侧收口时同步 §15.4 ⑪ / ⑰ 行即可。
- **未做（设计边界内）**：控制面（停止 / 转后台）按 D22 不做；digest 回合边界（D26）不合成；子代理内容归属（§15.8-2）不接；l10n / .arb 不动（英文占位留 SDK 轮，§14-15）。
- **上抛（非阻塞，待父侧裁定）**：代码评审轮 2 新列 🔵 —— 同键「终态之后再收到 `async` / `queued`」这一契约外序列下，`async` 支仍会复活一条活动条行（卡显示已完工、行在计时），且此后 `settled`/`done` 被护栏挡住、只能等进程收束清掉；`queued` 支只会覆写终态卡的 activity（不渲染，不可见）。三选一：加同款护栏 ∥ 同键再现按新子代理重建 ∥ 设计面明写「终态后同键报告 = 契约外，按现状忽略」。本单**未改**（评审通过后不再动被核字节），留父侧裁定后归批。
- **真机走查（§15.6 七步）未做**：按派单属交付后与用户约时进行；本单保证 debug 构建可用（analyze 干净 + 两档测试全绿）。

### 修正轮 1（终态后契约外报告守卫 · 2026-10-16 · 来源 = §2 裁定「终态后契约外报告 ⇒ 忽略」）

**交付摘要（号 → 改动 file:line · 实测）**

| # | 坐标 | 改动 | 实测 |
|---|---|---|---|
| R1 | `lib/kernel/thincoder/thincoder_events.dart:67-81` | 新增 `_liveStates`（四态常量：queued / async / turn / approval）与 `_removed`（cancelled 墓碑集） | +16 |
| R2 | `thincoder_events.dart:424-431` | `subagent()` 分派前统一前置守卫（四态在「卡已定格（succeeded / failed）或已移除（cancelled）」后 ⇒ 直接返回，不写卡不报条；`cancelled` 与终态族照旧） | +8 |
| R3 | `thincoder_events.dart:474-481` | `cancelled` 分支登记墓碑 `_removed.add(key)` | +2（含注释半句） |
| R4 | `thincoder_events.dart:492-495` + `:517` | `endSubagents()` doc 覆盖墓碑（跨进程同键从头起）+ `_removed.clear()` | +2 |
| R5 | `test/kernel/thincoder_kernel_test.dart:1276-1355` | 用例 T41（settled 后四态迟到 / stopped 后 queued·async / cancelled 后 async·queued / 新键对照 / 重启后同键从头起） | +81（含分隔空行） |

- 两档读数：`thincoder_events.dart` 609 → 637（+28）；`thincoder_kernel_test.dart` 1443 → 1524（+81）。表外零改动。

**决策透明表**

| # | 决策 | 理由 |
|---|---|---|
| 1 | 统一前置守卫（置于首见建卡之前），而非分支级补丁 | 守卫须先于首见路径——`cancelled` 已移除卡后同键再现若走首见会重建卡（T41「已移除的不重建」）；统一点同时覆盖四态、不触碰终态族与 `cancelled` 的既有处置（§2 裁定口径） |
| 2 | 新增 `_removed` 墓碑集 | 「卡片已移除」在 `_subagents` 里查不到（cancelled 已删表项），须独立记名；生命周期随 `endSubagents()` 清空——D31 跨进程口径（重启后同键按新子代理从头起） |
| 3 | 保留 `:462` 护栏（`turn` / `approval` 的旧护栏） | 统一守卫下该条件恒真（冗余但无害）；属被核过的字节，本单不改 |

**审计与代码评审轮次与终态**

- **内部发散审计**（explore，只读，对设计 §15.2 / D31 / §15.8-7 / T41 逐项核）：四类偏差（PARTIAL / 静默简化 / 文档漂移 / 表外改动）全无；注记 5 条均 🔵。收口动作：T41 补 `turn` / `approval` 两臂（防守卫退化）与重启段（钉 `_removed.clear()`）。
- **代码评审**（独立评审子代理）：`VERDICT: pass`（🟡 1 报告项 + 🔵 3；零 must-fix）。处置：🔵「`endSubagents()` 注释未提墓碑」已修（R4）；🟡「已移除后非 live 态迟到会重建卡」（与审计注记同源）与 🔵 另两项按本单边界不动、交父侧（见下）。
- **终态：clean**（无未决 🔴 / must-fix）。

**测试与读数**

- `flutter analyze lib/kernel/thincoder/thincoder_events.dart test/kernel/thincoder_kernel_test.dart` → `No issues found!`
- `flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` → `All tests passed!`（59 例 = 既有 58 + T41；固件复放零回归）
- T41 断言面：终态后四态迟到 ⇒ 卡片 status / activity / duration 不变、`running` 空、事件零新增；已移除后不重建；重启后同键新建（钉 `_removed.clear()`）。

**未做 / 偏差 / 上抛项**

- **未做（本单边界）**：claude / codex / mock 面、l10n、固件、设计档与批次档之外的文档零改动；不加新固件（T41 走 `ThincoderMock.push` 直驱）。
- **上抛·知会（两条评审同源，父侧可登记）**：卡片已移除（cancelled）后同键再现**非 live 态**（`settled` / `stopped` / `done` / 未知）仍会走首见重建卡（幽灵卡，与 D31 被否项同形）——设计忽略集显式只列四态、任务书裁「终态族照旧」，本单按口径未动；若需收口，设计面加一句（§15.8-7）或实现面把墓碑臂与四态解耦。
- **表外披露（工具链副作用）**：验证运行触发 `flutter pub get`（`Resolving dependencies → Changed 104 dependencies`），工作区 `pubspec.lock` 相对 HEAD 有 9 个传递依赖版本上调；非本单有意改动，未还原（无法区分是否前批遗留）。
- **父侧收口动作**：设计 §15.4 ⑰ 实交读数与缝坐标随本修正轮刷新（测试档 1524 行；四组现起于 `:1358` / `:1403` / `:1420` / `:1512`，旧 `:1277` 已落在 T41 体内）。

### 修正轮 2 · 点修（已移除后任何迟到报告 ⇒ 忽略 · 2026-10-16 · 来源 = §2 点修裁定 + 设计先行落档 §15.2:552 / D31:598 / §15.8-7:649 / T41:639）

**交付摘要（号 → 改动 file:line · 实测）**

| # | 坐标 | 改动 | 实测 |
|---|---|---|---|
| R6 | `lib/kernel/thincoder/thincoder_events.dart:426` | 墓碑前置守卫：`if (_removed.contains(key)) return;`——先于四态守卫（`:431-432`）、先于首见建卡路径（`:433` 起）；`cancelled` 墓碑键的任何迟到报告（四态 + `settled` / `stopped` / `done` / 未知态）一律不落面 | +1 行 |
| R7 | `thincoder_events.dart:431-432` | 四态守卫随解体：`ended` 删去 `_removed.contains(key) \|\|` 析取项（R6 后恒假、不可达），注释同步为「either」；语义零变更 | 净 0 |
| R8 | `thincoder_events.dart:78-81` | `_removed` 字段注释补「whatever it says」——任何状态同一忽略 | 净 0 |
| R9 | `test/kernel/thincoder_kernel_test.dart:1336-1347` | T41 非四态臂：`cancelled` 后同键推 `settled` / `stopped` / `done` / `settling`（未知态）⇒ 卡片不重建（2 张、描述表不变）、活动条无行（`running` 空）、事件零新增 | +13（含分隔行） |

- 两档读数：`thincoder_events.dart` 637 → 638（+1）；`thincoder_kernel_test.dart` 1524 → 1537（+13）。表外零改动。

**决策透明表**

| # | 决策 | 理由 |
|---|---|---|
| 1 | 墓碑臂独立前置，而非把四态守卫条件改宽 | 设计 §15.2:552 明写「实现：墓碑集命中即直接返回（先于四态守卫，不落首见路径）」；两类前置不同——墓碑键卡已不在表（`cancelled` 已删项），已定格卡仍在表且非 running；拆开后各自可读、四态守卫留原责 |
| 2 | 删四态守卫内 `_removed.contains(key) \|\|` 析取项 | R6 之后该析取恒假；留着会被读作活判据（审计/评审的「已死条件」漂移类）。行为零变更：非墓碑键该析取恒假、墓碑键在 R6 已返回 |
| 3 | `_removed` 字段注释补「whatever it says」 | 注释面随实现面同步（扩展后 = 任何状态同一忽略）——与设计口径一字一致 |
| 4 | T41 臂一次覆盖 4 个非四态（settled / stopped / done / 未知态），而非只推一个 | 设计 T41 输入列已列全「含 `settled` / `stopped` / `done` / 未知态」；四者都经首见路径 ⇒ 都会重建幽灵卡，一条臂四输入零额外成本、恰好钉住设计枚举 |
| 5 | 红→绿印证承重性（临时还原修前守卫单跑 T41，随即恢复） | 「新增臂是否真载重」是行为断言，须实测：修前形态下 T41 即败（3 张卡 = 幽灵卡重建）；恢复后两档复跑全绿 |

**审计与代码评审轮次与终态**

- **内部发散审计**（explore，只读，对设计 §15.2:552 / D31 / §15.8-7 / T41 逐项核）：代码面四类偏差（PARTIAL / 静默简化 / 文档漂移 / 表外改动）全零——墓碑键无任何路径可达建卡 / 状态 switch / 任务重建；非墓碑键行为等价；首见 `cancelled` / 终态族 / `endSubagents()` 与 `_removed.clear()`（restart 经 `_teardown`）未动。两条档面记录项：§5 本单子节（本段落笔即闭）、§15.4 ⑪ / ⑰ 读数与缝坐标（归父侧）。
- **代码评审**（独立评审子代理）：`VERDICT: pass`（🔴 0 / 🟡 0 / 🔵 1）。唯一 🔵 = 档面读数漂移：设计 §15.4 ⑪ / ⑰ 与体量条写 637 / 1524、缝坐标 `:1358` 起；实测 638 / 1537、四组现起于 `:1371` / `:1416` / `:1433` / `:1525`（+13 = 本单 T41 臂）——报告不改、归父侧。
- **终态：clean**（无未决 🔴 / must-fix 🟡）。

**测试与读数**

- `flutter analyze lib/kernel/thincoder/thincoder_events.dart test/kernel/thincoder_kernel_test.dart` → `No issues found!（ran in 6.6s）`
- `flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` → `All tests passed!`（59 例 = 既有 58 + T41；固件复放零回归）
- 红→绿印证：修前守卫单跑 T41 ⇒ `Expected: an object with length of <2> / Actual: [3 张卡]`（幽灵卡重建被抓）；恢复后复跑 = 59/59 全绿、analyze 干净。
- T41 断言面：终态后四态迟到 ⇒ 卡 status / activity / duration 不变、`running` 空、事件零新增；已移除后**任何态**（含非四态）⇒ 不重建、不报条；重启后同键新建（钉 `_removed.clear()`）。

**未做 / 偏差 / 上抛项**

- **偏差（1 处，行为等价，已披露）**：任务书 ㈢ 裁「不动四态守卫已核逻辑（只在它之前加墓碑判）」；实现动了四态守卫一行——删去 R6 后恒假的 `_removed.contains(key) \|\|` 析取项（理由见决策表 #2）。行为零变更；如需严格保守可原样放回该析取项（无行为影响）。
- **未做（本单边界）**：四态守卫语义、claude / codex / mock 面、固件、l10n、设计档与批次档 §1–§4 零改动；不加新固件（T41 走 `ThincoderMock.push` 直驱）。
- **父侧收口动作（评审同源 🔵）**：设计 §15.4 ⑪ / ⑰ 与体量条、变更记录 `:673`、批次档 §2 `:78` 的测试档读数与缝坐标刷新为 638 / 1537 · `:1371` / `:1416` / `:1433` / `:1525`。
- **表外披露（工具链副作用）**：验证运行触发 `flutter pub get`（依赖解析重跑）；`pubspec.lock` 相对 HEAD 的既有改动为前轮遗留，本单未有意改。

## §6 验证与收口（父代理）

## 验证与收口

- **实施**：批 4 主实现轮 + 修正轮 1/2（审计 clean / 评审 pass，🔵 1 归父侧）——读数见 §5。
- **用户批准**：2026-10-18 23:53「把哪几个在途做完吧」。
- **落档**：`docs/batches/thincoder-subagent-activity.md` 随本收口提交。
- **台账**：#10 核销（证据 = 本档 §6）。
