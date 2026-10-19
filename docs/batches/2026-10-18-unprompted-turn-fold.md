# 2026-10-18 · unprompted-turn-fold
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-18 · 来源 = 用户 2026-10-18 20:43 报告 + 20:45「要修改完善这个问题」。
> 台账 = #68（chat-streaming · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-18
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-18）

### 来源与性质

- 用户 2026-10-18 20:43：与主 agent 聊完，子 agent 回调、主 agent 汇报时，上一轮聊天结果被自动折叠；被折叠的正是用户要看的内容。20:45「要修改完善这个问题」。
- 性质 = **缺陷修复，但需要机制级设计**：折叠层没有回合边界，unprompted 回合把自己的回答当成「最后一个答案」，把上一回合的答案并入 work fold。修法要给回合一个折叠可见的边界（新标记项 ∥ 首项回合标记 ∥ 由会话传给折叠层的边界），属数据模型/机制改动 ⇒ 走完整链（设计 → 评审 → 批准 → 实现），不走轻渠道。

### 事实基线（实读）

- `lib/chat/step_folds.dart:207-250`：work fold 以「最后一个 `UserMessageItem(queued:false)` → 最后一个 `AssistantTextItem`」为范围；`answer` 是范围内最后一条 `AssistantTextItem`，`[start, answer)` 被折。
- unprompted 回合（`thincoder_kernel.dart` 的 `_beginTurn('auto:<n>', unprompted: true)`；设计 `docs/design/thincoder-adapter.md` §19.2）**没有新的 `UserMessageItem`**，其回答成为最后一个 `AssistantTextItem` ⇒ 上一回合的答案落进 `[start, answer)`。
- `lib/chat/chat_models.dart:121-125`：`AssistantTextItem` 只有 `text`，无回合边界/`unprompted` 标记；`UserMessageItem.worked`（`:28-30`）承载回合耗时。
- `lib/chat/chat_history_view.dart:1407-1410`：回合结束且贴底 ⇒ `_unfoldedTurns` 清空、work fold 关闭；用户往上读时才会保持展开。
- 既有单回合语义：`test/chat/fold_view_test.dart:102-110` 证明「同一回合内中间回答被折、最后回答保留」是设计；本批**不得改这条**。
- B 批读数：A1 六类外壳 0/0、`ChatItemView` 每增量 1；A4 外壳非 0 恰 1 帧 @37。本批不得回退这些读数。

### 本批要什么

- 每个回合（含 unprompted 回合）有折叠层可判的边界；work fold 只折**本回合自己的** work，折到**本回合自己的答案之前**；上一回合的答案保持可见。
- 子代理回调汇报落地后，上一回合答案不被折走；汇报轮自己的 work 可折、汇报答案保留。
- 保留单回合内「中间回答被折」的既有语义；保留性能读数与既有测试面。

### 本批不做什么

- 不改 unprompted 回合的语义（`TurnStarted(unprompted: true)` / 不自起轮 / 释放规则）；不改 thincoder 仓；不改内核事件面（若设计判定必须加事件字段，先在设计中给出理由并停给用户裁）。
- 不改折叠的视觉形态（Worked for 行本身、展开交互）；只改「折哪些、折到哪」。
- 不做与回合边界无关的清理（`_unfoldedTurns` 的其它行为、粘顶/选择区/滚动锚定保持）。

### 关联

- 台账 #68（chat-streaming · 归批）。
- F16 / 批 8：`docs/batches/thincoder-suspension.md` §19（unprompted 回合来源）。
- B 批折叠：`docs/design/chat-streaming.md`（§3.x / §6.1-A1 / §13）；`lib/chat/step_folds.dart` 的 work fold。

### 父侧裁定（2026-10-18 · 设计后）

- **需求档边界**：本批不新增需求档条目。`docs/requirements/chat-streaming.md` §4 的「不改数据模型（`ChatSession` / transcript 的事件形态零动）」按**事件形态**解读——`KernelEvent` / `Transcript` 零改；宿主侧回合账（`TurnMark` / `MarksTurns`）是视图投影，不在此限（主 agent 裁定）。
- **重放退化**：设计 §14-8-1 已登记（`session/load` 重放无回合事件 ⇒ 旧回合仍按提示词折，重载后第一个新回合起恢复正确）。是否另立批改事件面，**待用户裁**；本批设计按「接受退化 + 另批」推进。
- **`chat_session.dart` 1103 行 >800**：本批不拆（全部为新增私有投影 + 一个 getter）；已记台账「下一动先拆分（归批）」。

### 设计修正轮 #8 核验（2026-10-18 · 父侧）

- 设计档 §14-3 已改为 `TurnMark = (turnId, start, prompt?, worked?)`；`TurnEnded` 按 `turnId` 匹配、找不到 ⇒ 不改账；`_apply` 记账条件写准（只有 `_transcript.apply(event)` 为 true 才记，`KernelInfoChanged` 不记）；R8 补迟到 `TurnEnded` 的处置。父侧实读 `:475-509` / `:584`，与修正轮报告一致。
- 批次档 §2 正文的旧 `TurnMark = (start, prompt?, worked?)` 结论已被设计档取代；§2 是 eng-designer 的 append-only 段，本轮不追改，**以设计档 §14 为准**（设计评审按设计档读）。
- 修正轮只改设计档；未改产品代码、需求档、批次档 §3–§6。

### 评审发现处置（2026-10-18 · 父侧）

- 评审 changes-required（🔴 1 / 🟡 6 / 🔵 4，发现表见 §3）；11 条全部采纳，设计修正轮 2 在飞（eng-designer）。
- **发现 #2（需求未落需求档）**：父侧已补 `docs/requirements/chat-streaming.md` 的 **F4**（回合边界与跨回合答案可见 + 验收 + 边界），并更新状态行 / 模块目标；设计头部配对行由修正轮同步。属父侧直改，已标记。
- **发现 #6（>800 档无拆分计划）**：按「既有体量债不升级」处理——设计修正轮给 `chat_session.dart` 补拆分预案行（候选 / 预算 / 触发批），`chat_models.dart` 补拆分评审结论；不要求本批真拆。
- 其余发现按评审建议逐条落设计档；修正轮验收 = 11 条逐条有落点 + 无其它语义改动。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成 2026-10-18（修正轮 5：状态档卫生两处——头部状态行补 §14 / §14-12；§14-5 最近先例去批次档指针）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

## 批次任务与设计（eng-designer；设计档 `docs/design/chat-streaming.md` §14）

### 本批覆盖的条目（回指 §1「本批要什么」）

| # | 条目 | 本轮落点 |
|---|---|---|
| 1 | 每个回合（含 unprompted）有折叠层可判的边界；work fold 只折本回合、折到本回合答案之前；上一回合答案保持可见 | 设计档 §14-2（边界并集 + 窗 + 窗内规则 1–6）、§14-3（回合账与接口） |
| 2 | 汇报轮自己的工作可折、汇报答案保留（`worked` 不能只挂在用户消息上） | §14-3 回合账的 `worked` 来自 `TurnEnded`；§14-6 R1/R3 |
| 3 | 保留单回合内「中间回答被折」的既有语义（`test/chat/fold_view_test.dart:102-110` 不改） | §14-2 规则 4–6「窗内规则逐字沿用」；§14-11 ③ |
| 4 | 保留既有性能读数（A1 六类外壳 0/0、`ChatItemView` 每增量 1；A4 非 0 恰 1 帧 @37）与既有测试面 | §14-3 性能面（快路径不读账）；§14-11 ④（E） |

### 设计结论（一句话）

边界来自**内核已有的回合事件**：`ChatSession._apply` 在事件进 UI 的唯一入口上记一份**回合账**（`TurnMark = (start, prompt?, worked?)`），经独立能力接口 `MarksTurns` 交给视图，再传给 `StepFolds`；折叠把「最后一条提示词 → 最后一条文本」的窗换成「本回合起点 → 下一回合起点」，窗内规则逐字沿用。**`KernelEvent` / `Transcript` / 内核零改动**，不新增事件面 ⇒ 无需停给用户裁的扩面。

### 选择与否决（详见 §14-5 T1–T9）

- 选：会话传边界（候选③）。理由：事件面零改、`worked` 由 `TurnEnded` 给（汇报轮自己能量出「Worked for」）、下标在 `TurnStarted` 那一刻确定、独立能力接口不连累既有 feed 与测试替身。
- 否：新增边界标记条目（候选①）——合成条目会打乱条目流 / 下标 / 编辑 / 回退，重放没有它，且要动行结构。
- 否：首项带回合标记（候选②）——要改所有能开回合的条目类型与全部构造点，「首项」在流式里不稳定，重放同样没有标记而改动面大一个数量级。
- 否：视图自己记边界——`ChatFeed` 只暴露 `isStreaming` / `isUnprompted`，拿不到 `worked`，汇报轮折不了。
- 否：按条目形状猜边界——与既有「答案 → 工具 → 答案」的单回合语义不可区分。
- 否（本批不做）：持久化回合边界（跨重载正确）——需要事件面，见下「上抛项」。

### 受影响文件与测试覆盖（行数 = 2026-10-18 现行工作树实测）

| # | 坐标 | 现行 | 预期增量 | 档位结论 |
|---|---|---|---|---|
| ① | `lib/chat/chat_models.dart` | 713 | ≤ +8 | 超 500、未到 800；只加类型别名，不拆 |
| ② | `lib/chat/chat_feed.dart` | 154 | ≤ +18 | 500 档内 |
| ③ | `lib/chat/chat_session.dart` | 1104 | ≤ +70 | 超 800：不动结构（新增私有投影 + getter）；拆分另立批 |
| ④ | `lib/chat/step_folds.dart` | 435 | ≤ +65 | 仍 < 500（与 §4 的 <500 预算一致） |
| ⑤ | `lib/chat/chat_history_view.dart` | 3676 | ≤ +10 | 超 800：沿用 §4 拆分预案，本批不触发（只动 `_refold` 一处） |
| ⑥ | `test/chat/step_folds_test.dart` | 501 | ≤ +110 | 测试档 |
| ⑦ | `test/chat/fold_view_test.dart` | 316 | ≤ +55 | 测试档；既有 102-110 用例不改 |
| ⑧ | `test/chat/turn_marks_test.dart` | 0（新档） | +≈120 | 新测试档 |
| — | `test/chat/chat_history_rebuild_test.dart` | 507 | 0 | 零改动，重跑取 A1/A4 |
| — | `lib/kernel/**`（含 `transcript.dart` / `kernel_event.dart`） | — | 0 | 零改动 |

### 验收对照（可机检）

- **A**（`step_folds_test` 新用例，R1/R3）：上一回合 `work.end == 答案一下标`；`rowAt(答案一).item == true`；汇报回合有自己的 work 折（`worked` 来自它的 mark）；`rowAt(答案二).item == true`。
- **B**（`fold_view_test` 新用例）：同一脚本经实现 `MarksTurns` 的测试替身 ⇒ 两条答案同时可见、`WorkFoldLine` 两条。
- **C**（`turn_marks_test`）：`TurnStarted`/`TurnEnded` 记账、`prompt` 解析、`HistoryPrepended` 平移、`Rewound` 裁剪、换内核清空、unprompted 回合 `prompt == null`。
- **D**（对拍）：有账 / 无账在同一份条目上 `stepsAt` / `workAt` / `turnEndingAt` / `rowAt` 三态 / `shownAt` 逐下标全等；无账一侧等于今天。
- **E**（性能）：`chat_history_rebuild_test` 零改动重跑，A1 六类外壳 0/0、`ChatItemView` 每增量恰 1；A4 非 0 恰 1 帧 @37；不同 ⇒ 判缺陷。
- **F**（既有面全绿）：`step_folds_test`（既有）、`fold_view_test:102-110`、`history_scroll_test`、`sticky_message_test`、`selection_scroll_test`。

回滚：`_refold` 不传 `turns`（`turns: const []`）即回到今天的提示词规则（一行）；整批回滚 = revert ①–⑧，账是内存投影、无数据迁移。

### 上抛 / 需用户裁的事项

1. **重载退化**（§14-8-1）：账是内存投影；`session/load` 重放只有条目、没有回合事件 ⇒ 重载后旧回合按提示词折（= 今天的画面），从重载后第一个新回合起恢复正确。要让重载也正确 = 给重放加回合事件、或给条目加 `turnId`（改事件面）⇒ 本批不做，需用户裁是否另立批。协议侧是否已给重放回合边界**未核（unverified）**。
2. **需求档缺口**（主 agent 的笔）：`docs/requirements/chat-streaming.md` 只有 F1–F3（性能面），没有「回合边界 / work 折到哪」这一条；本批验收回指用户报告（§1）。若要落成需求档功能点，请主 agent 裁。该档 §4「不改数据模型（`ChatSession` / transcript 的事件形态零动）」按**事件形态**读：本设计不动 `KernelEvent` / `Transcript`，只在 `ChatSession` 加只读投影 —— 若按「ChatSession 零动」严读，则与 §1「候选③」相抵，需裁。
3. **`chat_session.dart` 超 800 档且无既有拆分计划**：本批不拆（新增 ≤70 行私有投影）；是否登记技术待办，请主 agent 定。
4. **工作树现状**：`lib/chat/chat_models.dart` 另有一处注释改名未提交（`host_tools.dart` 相关），非本批内容；设计按现行工作树读。

## 设计修正轮 5 · 状态档卫生（2026-10-18）

- `docs/design/chat-streaming.md:5` 头部状态行 → 设计稿 v4（§12 / §14-12 记实施偏差；§14 = #68 回合边界与折叠）· 2026-10-18。
- `:579` §14-5 最近先例行去掉 `docs/batches/...` 路径与「批次档 §x」指针：改为「本仓无该能力接口族的引入批」+ `agent_kernel.dart` 能力接口族为早期既有事实（`:100-102` / `:121-125` / `:226-240`）+ 同形先例 `AcceptsImageFiles`（`agent_kernel.dart:267`，本轮实读）。
- 未做（越出本轮授权，报主 agent）：`:6`「前情」仍引 `docs/batches/2026-10-17-ide-health-audit.md` §1；`:570`「测试档口径」仍引 `docs/batches/forge-gitee.md:228`——同为状态档引过程档，需另行裁。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

设计评审 · unprompted 回合折叠修复（#68）· 设计 = docs/design/chat-streaming.md §14 ∥ 需求 = docs/requirements/chat-streaming.md

限制：无 AGENTS.md / 无项目标准档 / 无文档地图（本评审 context 未提供）⇒ 方法论与文档归属按两份档自身的约定 + 本评审准则判；设计内对源码的行号引用属评审范围外，一律记为 unverified。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Feasibility / Correctness | 🔴 | §14-2 规则 4（`start >= count` 即丢弃）会丢掉 `TurnStarted` 刚建的那条 mark：§14-3 说 mark 的 `start` 就是本回合第一条条目的下标，而该通知时刻这条条目尚未落地 ⇒ `start == count`。新边界被丢后，刚结束的回合变成「最后一条窗」，§14-2 的「`live` 时最后一条…不折」把它的 Worked 行清掉；此后每次 `extend` 都从最新 mark 的 `start` 起扫（§14-3 第 521 行），被清掉的折叠再也不会重建。与 R4（§14-6 第 580 行「两回合结束后同 R1」）和本批要求①（§14-11 第 633 行）冲突；相对今天的提示词窗（§14-1 第 441 行）也是渲染回退——今天在下一回合流式期间上一回合仍保持折叠 | 把 `start == count` 当作合法的空边界（只丢 `start > count`），并补一条增量用例：A 回合 → `TurnEnded(A)` → `TurnStarted(B)` → B 的条目，全程 notify+pump，断言 A 的折叠仍在；20 / 200 回合各跑一次 |
| 2 | Methodology / Document ownership | 🟡 | #68 的要求只以「用户 2026-10-18 报告」的形式重述在设计 §14-11 第 631 行，配对需求档仍是 F1–F3 + N1（需求档第 3 节），且设计 §14-8-6（第 612 行「不改需求档」）明确不改它 ⇒ §14 没有可追溯的需求编号与验收条目；设计头部第 4 行仍写「配对需求档：…（F1–F3 + N1）」 | 在需求档新增功能点（如 F4 + 对应验收），并同步设计头部第 4 行的配对说明；确无需求档改动的理由也写在同处 |
| 3 | Acceptance criteria | 🟡 | 现有验收不覆盖「跨回合边界的增量路径」：§14-11 的 A/B/C 可用直接构造的 `StepFolds.of`（全路径）满足，而发现 #1 的失效只出现在 `extend` 序列里；§14-6 的 R4 也没有被映射成一条走 notify+pump 的机检条目 | 增补一条用例：从有账状态起，按真实事件顺序（TurnEnded → TurnStarted → 尾条追加）驱动视图，断言两回合各自的折叠与答案可见性 |
| 4 | Clarity | 🟡 | `HistoryPrepended` 的记账要「加上本次前置条数（`_transcript.prepended` 的增量，`chat_session.dart:267`）」（§14-3 第 503 行），但「增量」的基准值无人保存——§14-3 的接口与字段清单里没有记录上次 `prepended` 的成员 | 定名一个私有字段给出上次见到的前置条数（与视图侧 `_prependedSeen` 同形），并写明取值 / 更新顺序 |
| 5 | Evidence | 🟡 | 本批核心交付（汇报轮自己有一条 Worked 行）依赖「unprompted 回合的 `TurnEnded` 带非 null `worked`」；T1（第 563 行）以 `kernel_event.dart:16-52`（事件形态）与 `thincoder_kernel.dart:595-601`（回合起点）为据，未给自动回合 `TurnEnded(..., worked:)` 的发出点 | 补该发出点的坐标；若一时无法核，按 §3.6「第 0 步」的同一做法把它标成 `unverified` 并挂一条前置用例 |
| 6 | Code-structure annotation | 🟡 | §14-4 第 546 行的 ③ `chat_session.dart` 现行 1104 行、已在 800 档之上，却只有「本批不动结构…拆分另立批」，没有拆分计划（候选块 / 行数预算 / 触发批），与同表 ⑤（第 548 行，指回 §4 的拆分预案）不对称；① `chat_models.dart`（第 544 行，713 行、500–800 档）只有一句「不拆档」，无拆分评审结论（既有体量债，按不升级处理） | 给 ③ 补一行与 ⑤ 同形的拆分预案（候选 = 回合账投影 + `_apply` 记账，预算与触发批写清）；① 补一句拆分评审结论（为何本批不触发） |
| 7 | Methodology / Closest precedent | 🟡 | §14-5 第 557 行的最近先例行只给实现坐标（`chat_session.dart:341-345`），缺「对应设计档章节」与「先例批次」两个坐标；「偏离 = 无」的结论因此缺一半依据 | 把 `SelectsModel` / `RewindsConversation` / `StartsPlans` 的定义章节与引入批次补进该行，再落「偏离 = 无」 |
| 8 | Doc-state | 🔵 | §4 的实测值（第 221 行 3541 / 第 224 行 433 / 第 225 行 501）与 §14-4 的现行值（第 548 行 3676 / 第 552 行 507）不一致，且 §4 未标注是上游 1.3.0 合并前口径 | 在 §4 表头注明「上游合并前口径，现行值见 §14-4」，或回填现行值 |
| 9 | Clarity | 🔵 | §14-2 规则 3（第 451 行）只说「mark 优先（取 mark 的 `worked` 与 `prompt`）」，两条都是 mark 时取哪条未写，只有 R5 的「取靠后者」给出答案 | 把 R5 的取法并进规则 3 正文 |
| 10 | API surface | 🔵 | `turns` 返回 `ChatSession` 自持的可变 `List<TurnMark>`（§14-3 第 495 行、T8），折叠层拿到的是可写视图 | 在接口文档注释里写明只读契约，或返回只读视图（并说明是否落在预算内） |
| 11 | Code-structure annotation | 🔵 | §14-4 第 549 行「测试文件，无拆分档」是断言而非本仓已声明的规则（⑥ 将到 611 行）；④ `step_folds.dart`（第 547 行）≤500 恰好压线、零余量 | 把「测试文件不受文件档约束」写明为口径；④ 的预算留一行余量或注明压线即触发档检 |

计数：🔴 1 · 🟡 6 · 🔵 4 = 11 条

VERDICT: changes-required

### 轮次 2（评审子代理）

## 设计复评（第 2 轮）· unprompted 回合折叠修复（#68）

评审对象：docs/design/chat-streaming.md §14 ∥ docs/requirements/chat-streaming.md（均本轮全文实读）。

### 第 1 轮 11 条发现的复核

| # | 第 1 轮发现 | 状态 | 本轮实读依据 |
|---|---|---|---|
| 1 | 🔴 规则 4 丢弃 `start == count` 的 mark ⇒ 上一回合折叠被清且不再重建 | Fixed | §14-2 规则 4 改判据为 `start < 0` / `start > count`，并明写「`start == count` 是**合法的空边界**」；「边界落在 `count` …上一回合的窗在它处收口，照常折」；R11 / R13 / §14-11 ⑤·G 均已落 |
| 2 | 🟡 #68 要求只记在设计档，需求档无 F4 | Fixed | 需求档第 3 行「2026-10-18 追加 F4」+ 正文 F4（含验收与边界）；设计第 4 行改「F1–F4 + N1」；§14-8-6「配对条目 F4 已落盘」 |
| 3 | 🟡 验收不覆盖跨回合增量路径 | Fixed | §14-6 R13（真实顺序、每步 notify+pump、20/200 两跑）+ §14-11 ⑤/G |
| 4 | 🟡 `HistoryPrepended` 增量基准未定义 | Fixed | `_apply` 记账表：`moved = _transcript.prepended - _prependedSeen`，字段初值 0、换内核归 0；§14-4 ③ 列入改动清单 |
| 5 | 🟡 汇报轮 `worked` 的前提缺发出点 | Fixed | T1 补「`worked` 的发出点已核 = `thincoder_kernel.dart:682-699` 的 `_endTurn`」及 `:664-668` 路径 |
| 6 | 🟡 `chat_session.dart`（>800 档）无拆分预案；`chat_models.dart`（500 档）无拆分评审结论 | Fixed | §14-4 表后补「`chat_session.dart` 拆分预案」（候选块 / 90–130 行到 `lib/chat/session_turns.dart` / 触发批）；① 列给「拆分评审 = 保留 + 触发 = 改动条目模型」；④ 列给零余量登记口径 |
| 7 | 🟡 最近先例行缺设计档章节与先例批次坐标 | Fixed | §14-5 补「设计档章节 = `thincoder-adapter.md` §4-F5 / §4-F3 / §6-D8」与「先例批次 = **无档**（附同形先例 §5.2 ②）」 |
| 8 | 🔵 §4 与 §14-4 两套行数口径无说明 | Fixed | §4 表头补口径：本表为上游 1.3.0 合并前读数，现行值以 §14-4 为准 |
| 9 | 🔵 规则 3「两条都是 mark」时取谁未写 | Fixed | 规则 3 补「两条都是 mark 时取**靠后**的（列表里较新的那条，R5）」 |
| 10 | 🔵 `turns` 暴露会话自持的可变 List | Accepted | §14-3 接口注释写明只读契约，并给不包 `UnmodifiableListView` 的理由（换内核失效点 + 每全路径一次分配、消费方唯一）——理由成立，非修复项已具文 |
| 11 | 🔵「测试文件无拆分档」是断言；`step_folds.dart` 压线零余量 | Fixed | §14-4 表后「测试档口径」给两处先例 + ⑥⑦⑧ 逐档结论；④ 列写「落地实测达 500 即按 >500 审阅带登记缝候选，收口后不得再往上加」 |

### 本轮新发现（均不阻断）

| # | Severity | 位置 | 说明 |
|---|---|---|---|
| N1 | 🟡（可选，建议） | §14-3 性能面 · R4 · R13 | 设计只写「`TurnStarted` 翻转 `isStreaming`」，未写 `TurnEnded` 也翻转；而 `_tailFrom` 有账时只取最后一条 mark 的 `start`，`TurnStarted(B)` 后重扫范围为空 ⇒ A 的折叠冻结在 B 的 mark 出现前的最后一次重扫。若某内核在 `_pendingAuto` 顺延时不让 `isStreaming` 落回 false，A 的折叠永不产生；R13 的测试替身自己控制 `isStreaming`，抓不到该前提为假。建议把前提写进 §14-3，并让替身按生产语义翻转（或加一跑「不在 `TurnEnded` 落 false」）。 |
| N2 | 🔵 | §3.4 算法（`_turnEnds` 先删后重算）+ §14-3 空边界 | `from == count` 的空边界重扫范围为空；「先删「最后一条提示词」的旧条目，再按尾部重算」若按上一回合的旧键删除，会删掉上一回合的 `_turnEnds` 条目且不重建（回合页脚消失到下一次全路径）。建议在 §14-3 明写「重扫范围为空时不做 `_turnEnds` 删除」或把删除限定为本次将要重算的窗的键。 |

计数：第 1 轮 11 条 → Fixed 10 · Accepted 1 · Unfixed 0 · 未解决 🔴 0；本轮新增 🟡 1 · 🔵 1。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（2026-10-18）

- 用户 2026-10-18 21:12「批准设计」。
- 设计 = `docs/design/chat-streaming.md` §14（复评第 2 轮 **pass**；第 1 轮 11 条关闭 + 第 2 轮 2 条不阻断观察）。
- designToken 已签发（运行时状态，不落档、不进本档）。
- 批准后的实现范围 = §14-4 的 5 个产品档 + 3 个测试档；不扩面。

## §5 实施记录（eng-coder）

**状态行**：实施完成

### 交付（8 档，均在 §14-4 清单内）
- `lib/chat/chat_models.dart`：`TurnMark` 记录别名（含注释）。
- `lib/chat/chat_feed.dart`：`MarksTurns` 能力接口（`turns`，只读契约写在注释）。
- `lib/chat/chat_session.dart`：`implements ChatFeed, MarksTurns`；`_turns` / `_prependedSeen` / `turns`；`_apply` 只在 `_transcript.apply` 返回 true 后记账（`KernelInfoChanged` 不记）；`_markTurn` 四事件（TurnStarted / TurnEnded / HistoryPrepended / Rewound）；`setKernel` 清账 + 归零。
- `lib/chat/step_folds.dart`：`of` / `extend` 增 `turns`；`_boundaries` 边界并集（提示词 + mark，mark 优先、同下标取靠后、越界/乱序丢弃、`start == count` 为空边界）；`_tailFrom` / `_rescan` / `_liveStart` 取边界；`extend` 的 `_turnEnds` 改为按键删除，且 `start == count` 时不做任何删除（评审 #13）。
- `lib/chat/chat_history_view.dart`：`_refold` 读账并传入（唯一一处；快路径不读账）。
- `test/chat/step_folds_test.dart`：新增 `turns` 组（R1、R2/R12、R3、R4、R5、R6、R7、R10、R11 含乱序）；D（有账/无账逐下标对拍）放在 `extending as items come`（复用 `expectSame`）。
- `test/chat/fold_view_test.dart`：替身 `implements MarksTurns`（空账默认）；两回合可见性用例；R13 20/200 两跑（每步 notify+pump，逐项相等）+ 生产语义变体（`TurnEnded` 不落 false，保持到 `TurnStarted`）。
- `test/chat/turn_marks_test.dart`：新档（起/止/提示词解析/前置平移/回退裁剪/换内核/unprompted）。

### 实现轮决策与偏差
- 事件面零改：`KernelEvent` / `Transcript` / 内核未动；账是内存投影。
- 评审第 1 轮 🔴（Rewound 在「截断点 = 下一回合提示词下标」时多删上一回合 mark，使 unprompted 回合的 worked 与边界消失、前一个用户回合的答案重新被折走）已修：`_cutsAtMessage`（求值在 `apply` 之前）+ `crossed && !atMessage`；并补判别用例（turn_marks_test 的「a rewind at the next message keeps the turn before it」，去掉 `!atMessage` 该用例会变红）。
- 内部审计发现并修：Rewound 空账 `removeLast()` 抛 `StateError`（补 `isNotEmpty`）；「跨过截断点」判定改用**最小**被删起点（`nearest`），并把「没删任何 mark 但截断点切进了末条回合」纳入。
- 行数（实测 = 换行数）vs §14-4 预期增量：chat_models 718/≤721 ✓；chat_feed 163/≤172 ✓；chat_session 1187/≤1173（+14，全部来自评审 🔴 修复的 `_cutsAtMessage` 与 `before`/`atMessage` 管线）；step_folds 500/≤500（压线，按 §14-4 应登记缝候选）；chat_history_view 3685/≤3686 ✓；step_folds_test 618/≤611（+7：R11 乱序用例 + 块间空行）；fold_view_test 477/≤406（+71：R13 逐步行进机器 + 变体 + fixture）；turn_marks_test 243（新档，设计估计 ≈120）。三处超出均为**估计值**超出；各档仍在本仓体量档的实质边界内（测试档 <500；chat_session 的 >800 是既有体量债，台账已记「下一动先拆分」）。
- 评审遗留（不阻断，交父侧）：extend 与 turns 的逐下标对拍未补（可选）；`StepFolds.none` 的原地 grow 防护未加（step_folds 恰 500 行）；折起点的 `queued` 过滤与设计措辞二选一未定。
- 设计档漂移（未改设计档，供设计方修正）：§12-2 称「共享单例下误用会立即失败」，而 `assert(count >= _items.length)` 对 `none` 恒真，实际挡不住。

### 验证读数（本机，2026-10-18）
- `flutter test test/chat/step_folds_test.dart test/chat/fold_view_test.dart test/chat/turn_marks_test.dart` → **47 passed**（0 failed）。
- 加跑既有相关面：`chat_history_rebuild_test`（零改动）+ `history_scroll_test` + `selection_scroll_test` + `sticky_message_test` → 合计 **77 passed**。
- `host_tools` 目录 → **26 passed**（未碰）。
- R13 读数：`short=[read:1100, started:1100, worked:1101, ended:1111]`，`long` 逐项相同（20 / 200 两跑相等）。
- `chat_history_rebuild_test`：A1 六类外壳 20/200 全 0、`ChatItemView` 每增量恰 1（20/200 reads 全等）、`A2 equal=true`；A4 非 0 **恰 1 帧 @37**（值 7，该帧 item 2）——与本批前基线逐项相同。
- `flutter analyze`（8 档）→ No issues found；`dart format --set-exit-if-changed`（8 档）→ 0 changed。

### 审计 / 评审轮次
- 分歧审计（explore，1 轮）：1 🔴（Rewound 空账崩溃）+ 1 🟡（跨过判定取最大而非最小）+ 行数越界 + R11 乱序缺口 → 已修 + 补用例。
- 代码评审第 1 轮：changes-required（🔴 1 = Rewound 多删上一回合；🟡 1 可选；🔵 4；文档状态 1）→ 🔴 已修 + 判别用例。
- 代码评审第 2 轮：**pass**（🔴 已修并经实读核过；余项不阻断；其中 `_cutsAtMessage` 的 `?? event.index` 回退与 `_liveStart` 注释已顺手修正）。
- 终态：**clean**（无未解决 🔴）。

## §6 验证与收口（父代理）

## 验证与收口（2026-10-18 · 父代理）

### 实现核验（父侧实跑）

- `flutter test test/chat/step_folds_test.dart test/chat/fold_view_test.dart test/chat/turn_marks_test.dart test/chat/chat_history_rebuild_test.dart` → **62 passed, 0 failed**。
- `flutter analyze` 8 档 → **No issues found**。
- A1：六类外壳 20/200 全 0；`ChatItemView` 每增量恰 1；`reads=1200 per=10`（20/200 相等）；A2 `equal=true`。
- A4：非 0 恰 1 帧 @37（值 7）——与基线一致。
- R13：`short` / `long` 逐项相同（read:1100 / started:1100 / worked:1101 / ended:1111）。
- 代码实读：`TurnMark`（`chat_models:76`）· `MarksTurns`（`chat_feed:39`）· `ChatSession implements … MarksTurns`（`:98`）· `_apply` 的 `before` + `_cutsAtMessage`（`:185`）· `_markTurn` 四事件（`:196-250`）· `_boundaries`（`step_folds:284-321`，`start == count` 合法）· `_refold` 读账（`chat_history_view:141`）。

### 实现与偏差

- 8 档（5 产品 + 3 测试）；行数：718 / 163 / 1187 / 500 / 3685 / 618 / 477 / 243。
- 三处超预算：`chat_session` +14（评审 🔴 修复）、`step_folds_test` +7、`fold_view_test` +71（R13 机 + 变体）——设计 §14-12 已记；`step_folds` 500 压线 ⇒ 缝候选登记（台账 #72）。
- 内部审计 1 轮（`Rewound` 空账 `StateError` / 跨过截断点取最小 / R11 乱序——已修）；代码评审 2 轮（第 1 轮 🔴 = 截断点落在下一回合提示词时多删 mark ⇒ `_cutsAtMessage`；第 2 轮 **pass**，终态 clean）。
- 遗留：`StepFolds.none` 原地 grow 防护 + `extend↔turns` 逐下标对拍 ⇒ 台账 #73。

### 设计档同步

- §14-12 实施偏差记录（8 档读数 / 缝候选 / `Rewound` 口径）；§12-2 的 `StepFolds.none` 陈述改正；§14-2 规则 5 与实现对齐；§14-4 拆分触发句可判定；头部 v4 + §14-5 去批次档指针（修正轮 #18 / #19）。

### 已知限制（用户已接受 / 设计边界）

- 重放 / 旧会话无账 ⇒ 提示词规则；重载后第一个新回合恢复（用户 2026-10-18 接受，另批再议）。
- 汇报回合答案下无回合页脚（§14-8-3）；折起点不按 `queued` 过滤（§14-2 规则 5）。

### 台账与结算

- 台账 #68 追认核销（待设计 → 已核销）。
- 本轮新增：#72（step_folds 缝候选）、#73（两项收尾）、#74（设计档残留批次档指针 2 处）。
- 批次档冻结。
