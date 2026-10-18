# 2026-10-17 · chat-streaming-rebuild
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-17 · 来源 = 用户 2026-10-17 21:55「开工」；输入 = IDE 架构体检 E 表（docs/batches/2026-10-17-ide-health-audit.md §1 E1–E7）+ 新建需求档 docs/requirements/chat-streaming.md。
> 台账 = #44（chat-streaming · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-18
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-17）

### 来源

- 用户 2026-10-17 21:19：「把 IDE 做得更稳定、更清晰、更高效」→ 三路体检 → 效率表唯一高收益项 E1（流式每增量整树重建）。
- 用户 21:55：「开工」= 批准本批范围（先做流式重建，不掺结构重构）。

### 本批三件事（需求档 F1–F3 + N1）

1. **F1**：一个增量到达时，重建范围不随历史长度增长（外壳不进每增量路径）。
2. **F2**：折叠与图片收集改增量/缓存，并与全量结果对拍。
3. **F3**：流式 markdown 不再整篇重解析（按块缓存或 ≥50ms 节流，设计二选一）。
4. **N1**：改前 / 改后同法读数——**没有基线不算完成**。

### 硬约束

- 不改视觉与交互：粘顶消息、跨重建选择、滚动锚定（`_BeforeLayout` / `_StickyFollower`）、`cacheExtent: 900` 语义保持。
- 不改数据模型、不动内核、不引入依赖、不换列表实现。
- `chat_history_view.dart` 现 3358 行：若必须拆，只拆本批所需的一小块并写明行数预算。

### 范围外

- 体检里的 C 批（命令表 / 输入框 / 侧栏定时器）与 E 批（结构拆分）**不在本批**（台账 #45 / #47）。
- `packages/bao_editor` 未体检面（体检自述边界）——若实现需要动它，先停并上报。

### 已知事实（实读坐标，供设计直接用）

- 增量通知：`lib/chat/chat_session.dart:159-163`；视图 `setState`：`lib/chat/chat_history_view.dart:1214`。
- 整树重算：`chat_history_view.dart:2090`（`_built = null`）+ `:2113`；`cacheExtent: 900` 在 `:2219`。
- 折叠全量：`lib/chat/step_folds.dart:65-70`；图片收集：`chat_history_view.dart:2122`；折叠行收集：`:1857-1874`。
- markdown 整篇重解析：`lib/chat/widgets/markdown_view.dart:83-98`。
- 已做对的先例（不得破坏）：`SuperListView.builder:2214`；非流式 markdown 缓存 `markdown_view.dart:69-98`；折叠行实例记忆化 `chat_history_view.dart:1763-1793`。
- 既有测试（本批验收面）：`test/chat/chat_history_rebuild_test.dart` · `history_scroll_test.dart` · `sticky_message_test.dart` · `selection_scroll_test.dart` · `fold_view_test.dart` · `step_folds_test.dart` · `markdown_test.dart`。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（设计档 v2：评审第 1 轮 🔴3 / 🟡8 / 🔵4 全部落档；预算 ③ 832 / ≤877；设计档 358 行）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 设计落点

`docs/design/chat-streaming.md`（新建，≤500 行；配对需求档 `docs/requirements/chat-streaming.md`）。本批**不建第二个设计档**，实施面全部在 `lib/chat/**`。

### 本批条目（覆盖）

| 需求 | 本批落点 | 机检判据（详见设计档 §6） |
|---|---|---|
| F1 增量只重建该重建的 | 设计档 §3.1–3.3（witness + `_LiveItem` + 快路径豁免清单） | A1 每增量 `ChatFindRow` 0 / `SuperListView` 0 / `SelectionArea` 0 / `ChatItemView` 恰 1；A2 20 与 200 回合历史逐项相等；A3 文本确实更新 |
| F2 折叠与图片收集不随历史增长 + 对拍 | 设计档 §3.4–3.5（`StepFolds.extend` 稳定点 / 图片缓存键与失效） | B1 20 / 200 回合两次跑的条目读逐次相等、增量期间图片收集 0；B2 `extend` 与 `of` 逐下标全等 |
| F3 流式 markdown 解析上界 + 最终态 | 设计档 §3.6（50ms 节流 + 帧时间戳 + trailing 必达） | C1 ≥5000 字 / 200 增量 × 8ms：解析 ≤34 且 ≥5；C2 最终节点文本 == 一次性解析；C3 无 pending timer |
| N1 改前 / 改后同法读数 | 设计档 §8（同一测试文件先在未改代码上跑，记红读数，再实现、再跑绿） | D1 两次读数写进本批次 §5 |

### 明确不在本批

- C 批（命令表 / 输入框 / 侧栏定时器，台账 #45）· E 批（结构拆分，台账 #47）· `packages/bao_editor` 未体检面。
- 数据模型 / `KernelEvent` 形态 / `ChatFeed` 接口：零改动；不换 `SuperListView`、不引入依赖。
- 视觉 / 交互：粘顶、跨重建选择、滚动锚定、`cacheExtent: 900` 语义全部保持。

### 机制一句话

会话通知在视图里分两路：**文字尾巴增量**（O(1) 判据）只 `_liveTick++`，仅流式那条的 `_LiveItem` 重建；其余走既有全路径。折叠改尾部增量（稳定点 = 最后一条提示词），图片集合按 `(itemCount, 末内容条实例)` 缓存并在全路径通知时丢弃，流式 markdown 以 50ms 节流 + trailing 解析收敛到最终态。

### 受影响文件（行数 = 2026-10-17 实测）

| 坐标 | 改动 | 增量预算 |
|---|---|---|
| `lib/chat/chat_history_view.dart`（3358） | witness + `_LiveItem` + `_refold` 调用规则 + 图片缓存 + 合并缓存失效 | ≤ +110（⇒ ≤3468）；不拆档 |
| `lib/chat/step_folds.dart`（353） | `count` / `extend` / `invalidateTail` / 尾部三段重算 | ≤ +120（⇒ ≤473） |
| `lib/chat/widgets/markdown_view.dart`（831） | 50ms 节流 + trailing Timer | ≤ +45（⇒ ≤876） |
| `test/chat/chat_history_rebuild_test.dart`（134） | F1 + N1 脚本（短 / 长两跑） | ≤ +120（⇒ ≤254） |
| `test/chat/step_folds_test.dart`（374） | 增量 ↔ 全量对拍 | ≤ +90（⇒ ≤464） |
| `test/markdown_test.dart`（397） | F3 上界 + 最终态 | ≤ +80（⇒ ≤477） |
| `chat_feed.dart` / `chat_session.dart` / `transcript.dart` / `chat_screen.dart` | 零改动 | 0 |

### 既有测试通过面（必须全绿、零改动）

`test/chat/chat_history_rebuild_test.dart` · `test/chat/history_scroll_test.dart` · `test/sticky_message_test.dart` · `test/selection_scroll_test.dart` · `test/chat/fold_view_test.dart` · `test/chat/step_folds_test.dart` · `test/markdown_test.dart`。

### 关键决策（D1–D9，见设计档 §5）

D1 重建手段 = `ValueNotifier` + 独立 `_LiveItem`；D2 快路径判据 = O(1) witness（模型零动）；D3 快路径豁免清单；D4 折叠稳定点与全量回退规则；D5 图片缓存键 + 「全路径通知即丢」；D6 markdown 选 50ms 节流（被否：按块缓存）；D7 量法 = 框架钩子 + 测试 feed 计数（产品零计数钩子）；D8 不拆档；D9 非流式 markdown 缓存不动。

### 上抛 / 发现项（请主 agent 处置）

1. 需求档抬头仍写「状态：待用户确认」，而本批次 §1 记录用户 21:55「开工」已批准范围——状态句不一致（需求档笔在主 agent，我不改）。
2. 需求档 §5-2 把 `sticky_message_test.dart` / `selection_scroll_test.dart` / `markdown_test.dart` 写成 `test/chat/...`，实为 `test/` 根下（本设计按实测路径落）。
3. 需求档 F1 验收句「历史行的构建次数与历史长度无关」：因列表早已虚拟化，该句在改前也可能成立（可见行数不随历史增长）。本设计把 F1 的判据补成「每次增量历史行重建为 0、外壳为 0、仅流式一条重建」并加「20 / 200 回合逐项相等」，使改前 / 改后读数有区分度（§6-A1/A2）。
4. 体量口径：`chat_history_view.dart` 批次档记 3358 行，`wc -l` 实测 3357（文件末无换行）；本设计沿用批次档口径。

### 评审第 1 轮修复（2026-10-17 · 设计档 v2）

15 条逐条落档（均落在 `docs/design/chat-streaming.md`，代码零改动）：

| # | 严重度 | 落点 |
|---|---|---|
| 1 | 🔴 | §3.1 `liveRow`（`rowOf` 取思绪连跑首行）+ §3.2 挂载位置 + §7-T3 |
| 2 | 🔴 | §6.1-A3 拆「数据层 / 渲染节奏 / 终态」+ §8 回放 `pump(8ms)` |
| 3 | 🔴 | §3.4 合法条件加「feed 未换」+ §7-T9 + §11-2 |
| 4 | 🟡 | §2.1 基线更正 + §3.5 + §6.1-B1③ + §9-3 |
| 5 | 🟡 | §8-4 循环内只累计、先打汇总再断言（`addTearDown` 兜底） |
| 6 | 🟡 | §3.6 共享件影响面（四处调用；stash 预览 ≤50ms 判可接受） |
| 7 | 🟡 | §3.6 前缀条件 + §7-T10 |
| 8 | 🟡 | §3.4 `extend` 定死「原地改、返回 `this`」+ `refreshTail` + B2 连跑 1→2→3 |
| 9 | 🟡 | §6 新增 W1（真机走查，人工判据） |
| 10 | 🟡 | §4 拆档预案与预算（450–550 行，E 批 #47） |
| 11 | 🟡 | §6 测试路径改为「与需求档 §5-2 一致」 |
| 12 | 🔵 | §4 ③ 832 / ≤877；「其余四个」 |
| 13 | 🔵 | §6.1-A1 计数补 `ChatColumn` / `ChatImages` / `ScrollbarTheme` |
| 14 | 🔵 | §8 第 0 步计时前置用例（⑥ 内；不过即停并上报） |
| 15 | 🔵 | §9-10 文档地图备注 |

- 预算表更正：③ `markdown_view.dart` 832 行，≤ +45 ⇒ ≤877；其余不变。
- 上抛项更正：第 2 条作废（需求档 §5-2 本就注明后三个在 `test/` 根下）；第 3 条已由主 agent 在需求档改为「数据层 + 终态」口径；第 1、4 条维持。
- 实现提示（由 #1/#8 推出，已写入 §3.4）：思绪合并缓存从 `StepFolds._items` 取值，快路径必须先 `refreshTail` 更新折叠副本，否则合并文本不更新。
- 设计档 358 行（≤500）；最长行 285 字符（≤300）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

设计评审 · B 批「对话流式渲染的重建边界」· 对象：docs/design/chat-streaming.md（§2–§8）+ docs/requirements/chat-streaming.md · 状态：待评审

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Feasibility / Clarity | 🔴 | 快路径只让「尾巴下标」那条重建，但思绪连跑时真正显示增量文本的是连跑首行：`_shownAt` 取 `_folds.shownAt(index, _feed.itemAt(index))`（`lib/chat/chat_history_view.dart:575`），`StepFolds` 把 ≥2 连续思绪合并到首行（`lib/chat/step_folds.dart:77-91`、`:184-190`），被合并的后续思绪 `rowAt` 返回 `item: false`，`_buildItem` 直接返回 `SizedBox`（`:1810-1811`），itemBuilder 还先走 `_isHidden` → `_hiddenRow(index)`（`:2229-2232`），`_LiveItem` 根本挂不上 ⇒ 多段思绪流式时可见文本停住到下一次全路径；T3（设计档 `:246`）与 A3 均不成立 | 把 `live` 判据从「尾巴下标」改成「实际渲染流式文本的那一行」（合并连跑时 = 连跑起点 / `_thoughtRuns` 里覆盖尾巴的 start），并纳入快路径重建集合；T3 明确断言首行合并文本在快路径后已变 |
| 2 | Acceptance | 🔴 | A3「每次 `pump` 后流式文本已更新」（设计档 `:228`）与 §3.6 的 50ms 节流自相矛盾：按 C1 自己的参数（200 增量 × 8ms，`:230`）相邻增量必然 <50ms，节流按设计即跳过解析；§8 回放是 `await tester.pump()` 无时长（`:260`），假时钟不推进时 120 次回放只解析一次 ⇒ 该验收实现后必然红，需求档 F1「每次回放后流式文本确实已更新」与 F3 允许的节流在测量点上未调和 | A3 写死观察点与节奏（数据层 `MarkdownView.widget.data` 每 pump 最新；渲染块按 ≥50ms 节奏更新，回放结束 `pumpAndSettle` 断言最终文本），并给回放 pump 明确时长（与 C1 的 8ms 对齐） |
| 3 | Feasibility / Clarity | 🔴 | `extend` 的合法调用条件（设计档 `:143-147`）漏了「同一个 feed」：`didUpdateWidget` 换 feed 时直接 `_refold()`（`lib/chat/chat_history_view.dart:477-494`，`:490`），而 `_refold` 仍是唯一入口（`:116-120`）；新会话条目数 ≥ 旧 `_folds.count` 时按规则会走 `extend`，把上一会话的 `[0, from)` 折叠原样复用 ⇒ 折叠线 / 隐藏行错乱 | 合法条件加「feed 未换（`_folds` 来自当前 feed）」；`didUpdateWidget` 的 `_refold` 一律走 `StepFolds.of` 全量；§7 增「切换会话（新会话更长）」用例 |
| 4 | Requirements / Evidence | 🟡 | 图片收集基线事实不成立：`_images` 只作为 `ChatImages.all` 回调传入（`chat_history_view.dart:2094-2095`），`ChatImages` 是 `updateShouldNotify => false` 的 InheritedWidget（`lib/chat/widgets/content_image.dart:265`），`all()` 只在打开图库时调用（`content_image.dart:273`），全仓无其他 `_images()` 调用点 ⇒ 设计档 `:159`「这些今天每次都付 O(N)」与 `:160` 均非现状，B1 图片子句（`:229`）改前 / 改后都是 0，无法区分 | 修正基线描述（需求档 §2 同句一并改）；D5 / §3.5 改为「按需缓存，防重复收集」并给真实读数，或把该子项移出本批 |
| 5 | Acceptance / Procedure | 🟡 | §8 基线流程按字面跑不通：④ 要在未改代码上跑出改前读数（`:269`），但 A1/B1/C1 的断言若在回放循环内，第一次不匹配即抛，`:265` 的汇总 `debugPrint` 永远打不出 ⇒ N1 的「改前必须实测」拿不到 | 循环内只累计计数，循环后先打汇总行（或 `finally` / `addTearDown` 输出）再 `expect`；改前 / 改后共用同一段采集代码 |
| 6 | Scope / Blast radius | 🟡 | 50ms 节流加在共享的 `MarkdownView.build`（设计档 `:165`），而 `MarkdownView` 不只服务对话：`assistant_text.dart:32`、`notice_row.dart:51`、`plan_card.dart:230`、`lib/stash/stash_editor.dart:3469`（stash 预览随输入重解析）；§10「视觉零变化」只覆盖对话 | 写明影响面与结论（stash 预览 ≤50ms 可接受，或该处不受影响），必要时把节流限定在对话路径（开关默认关，行为不变） |
| 7 | Edge case | 🟡 | 节流只按时间判定，不看「新数据是否是旧数据的延长」：同一元素位换成另一条消息时（前置右移 `chat_history_view.dart:685-721`；编辑提交替换后续条目 `:1726-1738`，`ChatItemView` 以 `ValueKey(index)` 复用 `:1816`），窗口内会返回上一条的 widgets，最多 50ms 显示错文本 | 命中条件加「旧文本是新文本的前缀（同一消息在长）」，否则立即解析；§7 增「前置历史 / 编辑提交后同一行换条目」用例 |
| 8 | Clarity | 🟡 | `extend` 实例语义未定：签名返回 `StepFolds`（`:126`），算法写成「旧 count 为新条目追加 `_items`」（`:136`）像原地改；`_merged` 是实例字段初始化（`lib/chat/step_folds.dart:180`），新实例天然为空无需失效，原地改则必须自清 ≥ from 的合并项，而 `invalidateTail` 文中只用于文字快路径（`:151`） | 二选一写死（新实例 + `_merged` 从空开始 / 原地改并在 `extend` 内清 ≥ from 的 `_merged`）；B2 补「思绪连跑 1→2→3 条」的 `shownAt` 文本对拍 |
| 9 | Requirements coverage | 🟡 | 需求档 §5 第 3 项（真机走查 ≥200 条长对话、用户主观确认，`docs/requirements/chat-streaming.md:44`）未进 §6 验收对照表，设计档只在 §10 当作 F3 节奏判断线（`:295`） | 把走查列为 §6 一行（判据 = 主观跟手确认，记录历史长度与结论），与 A1–C3 并列 |
| 10 | Structure / tier | 🟡 | `chat_history_view.dart` 现 3358 行，本批 +110 并新增 StatefulWidget（`:194`），仍在 800 行硬档之上；D8（`:219`）与 §4（`:204`）只写「不拆档、E 批负责」，未按结构档给拆分计划 | 把既有裁定写成计划一行（引 E 批台账 #47 + 需求档 §4「只拆本批需要的那一小块」），并说明新增部分为何不必拆；不改裁定，只补落档 |
| 11 | Doc accuracy | 🟡 | 设计档 `:236` 称「需求档写的 `test/chat/` 前缀与实况不符」，但需求档 `:43` 中这三个文件本就写作 `test/sticky_message_test.dart` 等并注明「（后三个在 `test/` 根下）」 | 删掉该判断或改为「与需求档一致」；确需记差异则引具体不一致行 |
| 12 | Numeric drift | 🔵 | ③ 标注 `markdown_view.dart`（831）（`:199`），实读 832 行；§4 末行「其余六个验收测试」（`:201`）实为 4 个（需求档 7 个验收文件 − 本批改动的 ④⑤⑥）；不影响预算（≤876） | 更新为 832 与「其余四个」 |
| 13 | Acceptance coverage | 🔵 | §3.2 称 `_row` / `ChatFindRow` / `ChatColumn` 不在快路径（`:111`），但 A1 计数只含 `ChatFindRow` / `ChatItemView` / `SuperListView` / `SelectionArea` / `MarkdownBlocks`（`:228`），`ChatColumn`、`ChatImages`、`ScrollbarTheme` 未计数 | 把 `ChatColumn`、`ChatImages`、`ScrollbarTheme` 加进计数，或把 §3.2 断言收窄到已计数类型 |
| 14 | Evidence | 🔵 | 计时依据引 SDK 源码（`scheduler/binding.dart:1132-1135`、`flutter_test/lib/src/binding.dart:2259`，`:174`），不在本仓、本次无法核对（unverified）；C1/C3 结论依赖它 | 在 ⑥ 里先用一条最小用例验证「`pump(duration)` 推进 `currentFrameTimeStamp`」，作为 C1 前置 |
| 15 | Document ownership（降级） | 🔵 | 本次无文档地图、无 AGENTS.md / 项目规范，归属与流程合规只能按通用判据看；就可见范围 `chat-streaming` 为首篇，新建配对设计档不构成切分重复（需求档 `:6`） | 若有文档地图，补「对话渲染板块」条目指向这两档，避免 C/E 批重复描述同一节 |

范围外备注（不计严重度）：`chat_screen.dart:599-657` 的 `ListenableBuilder` 每个通知仍重跑 builder（`_commandSuggestions()` / `_suggestFiles()`），`child: _buildBody()` 已核对使 body 子树不重建；该处属 C 批（台账 #45），不在本设计计数内。无 AGENTS.md / 项目规范 ⇒ 方法论合规按通用判据判断（设计档结构、决策记录、行数预算、最近先例对照齐备）。

VERDICT: changes-required
计数：🔴 3 · 🟡 8 · 🔵 4

### 轮次 2（评审子代理）

B 批设计 · 第 2 轮（只验第 1 轮 15 条；未收到修复说明表，逐条按当前文件状态核验）

评审面：`docs/design/chat-streaming.md`（v2，359 行）+ `docs/requirements/chat-streaming.md`（51 行）。代码坐标沿用第 1 轮实读结论，本轮未重读代码文件（范围声明）。

| # | 原# | 位置 | 严重度 | 状态 | 依据 / 说明 |
|---|-----|------|--------|------|-------------|
| 1 | 1 | 设计档 §2.2/§3.1/§3.2/§7-T3/§11-3 | 🔴 | Fixed | 新增 `liveRow = _folds.rowOf(tail)`（:95）与 `rowOf` 契约（:136）；`_LiveItem` 挂「实际渲染流式文本的那一行」（:44、:118）；`_hiddenRow` 分支不包并给理由（:119）；T3 改为断言连跑首行（:284）；清单 :348。与第 1 轮三处证据自洽。 |
| 2 | 2 | 设计档 §6.1-A3 / §8 / 需求档 F1 验收 | 🔴 | Fixed | A3 拆三层：数据层逐次（`MarkdownView.widget.data`）、渲染层 ≥5 次、终态逐块（:264）；回放 pump 明确 8ms（:301）；需求档 F1 验收同步（需求档:22）。50ms 节流与「文本在更新」不再冲突。 |
| 3 | 3 | 设计档 §3.4/§5-D4/§11-2/§7-T9 | 🔴 | Fixed | 合法调用条件首条「feed 未换，换 feed 一律 `StepFolds.of`」（:160）；D4（:241）；§11-2（:347）；新增 T9（:290）。 |
| 4 | 4 | 设计档 §2.1/§3.5/§5-D5 / 需求档 §2 | 🟡 | Fixed | 基线更正（:37、:173）；D5（:242）；需求档:16 同步；B1 ③（:265）改为「无会话变更时连读两次：改前各 +N / 改后 +N 再 +0」，可判别。 |
| 5 | 5 | 设计档 §8 | 🟡 | Fixed | 循环内不写断言不打印（:301）；循环后先 `debugPrint` + `addTearDown` 兜底、之后 `expect`（:306）；基线顺序注明「红也有数」（:310）。 |
| 6 | 6 | 设计档 §3.6/§5-D6/§10 | 🟡 | Accepted | 共享件做法未改，但登记四处调用点（:200）并给裁定（stash 预览 ≤50ms、trailing 必达，判为可接受；:338）。理由成立：非流式三处 data 不变命中缓存，预览为输入限速且终态必达，与 F3 允许的 ≥50ms 同量级。 |
| 7 | 7 | 设计档 §3.6/§7-T10/§11-5 | 🟡 | Fixed | 前缀条件（:188、:195）；新增 T10（:291）；清单第 5 条（:350）。 |
| 8 | 8 | 设计档 §3.4/§5-D4 | 🟡 | Fixed | 「实例语义（定死）：原地改、返回 this」+ `_merged` 自清 + 选型理由（:141）；算法块补「与 `_merged` 项」（:151）。 |
| 9 | 9 | 设计档 §6 / §10 | 🟡 | Fixed | §6 新增 W1 行（:258），人工判据与记录要求写入。 |
| 10 | 10 | 设计档 §4 | 🟡 | Fixed | 新增「拆档裁定与计划」（:227-230）：候选搬 `history_rows.dart`、预算 450–550 行、触发条件 = E 批；本批不拆的裁定保留。 |
| 11 | 11 | 设计档 §6 | 🟡 | Fixed | 改为「与需求档 §5-2 的注明一致」（:274），与需求档:43 实际文字相符。 |
| 12 | 12 | 设计档 §4 | 🔵 | Fixed | ③（832）（:219）；「其余四个验收测试」（:224）。 |
| 13 | 13 | 设计档 §6.1-A1 | 🔵 | Fixed | 计数补 `ChatColumn` / `ChatImages` / `ScrollbarTheme`，共八类（:262），与 :121、:303 一致。 |
| 14 | 14 | 设计档 §3.6/§8-0 | 🔵 | Fixed | SDK 依据标 unverified 并给「用例不过即停并上报」门（:196）；§8 第 0 步计时前置用例（:299）。 |
| 15 | 15 | 设计档 §9-10 | 🔵 | Fixed | 文档地图备注（:330）。 |
| 16 | （新） | 设计档:93 | 🟡 | New | 同一句自相矛盾：先说「判据自然失败」，紧跟括号又说「仍快路径」；「见下『失败面』」指向的 :103 只讲「判据失败回全路径」，不覆盖该误判面。证据：`若内核以后引入这种事件，判据自然失败（文本长度虽增但流式位 / 条数不变时仍快路径——见下「失败面」）` |
| 17 | （新） | 设计档:264 / :301 | 🟡 | New | 同一段回放的验收规则冲突：A3 ① 要求「逐次断言」，§8 第 2 步要求「循环内只累计计数，不写断言」。证据：`① 数据层：每次 \`pump(8ms)\` 后 \`MarkdownView.widget.data\` == 当时最新全文（逐次断言）` / `循环内只累计计数，不写断言、不打印` |

关闭情况：第 1 轮 15 条全部关闭（Fixed 14 / Accepted 1）；新增 🟡 2（不阻断）。
计数：🔴 0 · 🟡 2 · 🔵 0
VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（2026-10-18 06:22）

- 用户逐字：「批准收口」。
- 批准对象 = 流式重建的实现形态：F1 快路径 + F2 折叠增量/图片缓存 + F3 50ms 节流，经两轮设计评审（changes-required → pass）与两轮子代理代码评审（终态 clean），父代理独立复跑 `flutter analyze` 干净、`flutter test` 三档 51 passed / 3 既有红项。
- 批准时**已知并接受**：
  1. **W1 真机走查未跑**（≥200 条长对话的主观跟手度）——机器测不了，用户批准时未执行；本批以读数收口，走查作为遗留项挂台账。
  2. 四条实现偏差（设计档 §12）：`extend` 重读最后一回合 · 防御性 `assert` · A1 用 bubble 口径 · 图片缓存键只比 `itemCount`。
  3. 四个文件超设计预算（源码 1 个超 73 行，测试 3 个），功能未裁剪。
- 本批为完整链（需求 → 设计 → 评审 → 批准 → 实现 → 复核），§3 由两轮设计评审逐字写入。

## §5 实施记录（eng-coder）

### 实施记录

**状态行**：实施完成（内部审计 1 轮 + 代码评审 2 轮，终态 clean；预算超限已记档，见第 5 条）

#### 1. 改动文件与规模（实测，`dart format` 后）

| 文件 | 基线 | 实测 | 净增 | 设计预算 | 结论 |
|---|---|---|---|---|---|
| `lib/chat/chat_history_view.dart` | 3358 | 3541 | +183 | ≤ +110（≤3468） | 超 73 行（记档，理由见第 5 条） |
| `lib/chat/step_folds.dart` | 353 | 435 | +82 | ≤ +120（≤473） | 在预算内 |
| `lib/chat/widgets/markdown_view.dart` | 832 | 875 | +43 | ≤ +45（≤877） | 在预算内（余 2 行） |
| `test/chat/chat_history_rebuild_test.dart` | 134 | 433 | +299 | ≤ +120（≤254） | 超 179 行（含 A2/A3/B1 与 T3 用例） |
| `test/chat/step_folds_test.dart` | 374 | 501 | +127 | ≤ +90（≤464） | 超 37 行（B2 逐下标对拍） |
| `test/markdown_test.dart` | 397 | 504 | +107 | ≤ +80（≤477） | 超 27 行（C1/C2/C3 与 T10） |

设计档「零改动」的四个文件（`chat_feed.dart` / `chat_session.dart` / `transcript.dart` / `chat_screen.dart`）未改；`_hiddenRow` / `_BeforeLayout` / `_StickyFollower` / 选择器 / 滚动控制器未改。

#### 2. 设计档 §11 六条 → 落点

1. **快路径判据（8 条 O(1) 事实）**：`chat_history_view.dart` 的 `_tailSeen` 快照（`:105` 起）、`_tailNow()`、`_tailGrew()`（`:178`-`:193`）。8 条 = count / streaming(now+seen) / unprompted / editing(now+seen 均为空) / prepended / tail 下标 / 末条目运行时类型 / 长度增长。
2. **`_liveTick` + `_LiveItem`**：`_liveTick`（`:119`）；`_LiveItem` 类与其 State（`:3058` 起）；`_row(...)` 的 `live: index == _liveRow`（`:2365`）。
3. **`_liveRow`**：`:197`，`_folds.rowOf(_contentCount - 1)`，非流式为 -1；思绪连跑落在连跑首行。
4. **`_refold({grow})` 规则**：`:133`-`:140`；调用点 `:1282`-`:1284`（`grow: moved == 0 && grew`，`grew = count >= _folds.count && (count > _folds.count || liveChanged)`）；换 feed 走 `didUpdateWidget` 的 `_refold()` 全量（`:566`-`:573`）。
5. **图片缓存**：`_imagesCache` / `_imagesKey` 与 `_images()`（`:2222`-`:2251`）；全路径通知首行丢弃（`:1272`-`:1273`）；`didUpdateWidget` 换 feed 丢弃（`:568`-`:569`）；命中只比 `itemCount`（比较末条目实例会在每次命中多读一次，与 B1③「第二次 +0 读」冲突，`.imagesKey` 的第二分量仅记录）。
6. **`StepFolds.extend` / `refreshTail`**：`step_folds.dart:104`-`:141`；`of` 改为 `of → _rescan(0)`，与 `extend → _rescan(from)` 共用同一扫描（`:72`、`:171` 起）。
7. **markdown 50ms 节流**：`markdown_view.dart:79`-`:137`，前缀判据 + trailing `Timer` 必达 + `dispose` / `didChangeDependencies` 撤计时器。

#### 3. 偏差与理由（须披露）

- **`extend` 会重读最后一回合的条目**，设计档 §3.4 写的是「[0, from) 原样复用、只 append 新条目」。实现改为：`_tailFrom(itemAt, count)` 用 feed 读稳定点（最后一个非排队提示词 / 尾部思绪连跑起点 / 尾部连续快步骤起点），再把 `start..count` 用 `itemAt` 重读后 `_rescan`。原因：回合结束时同下标条目会被原地替换（prompt 补 `worked`、状态行位置换成答案），只 append 会保留旧实例，`fold_view_test` 两条既有用例红。代价 = 每增量重读最后一回合（实测 8 读/增量，与历史长度无关，B1① 20/200 相同）。
- **`extend` 增加 `assert(count >= _items.length)`**，并写明 `StepFolds.none` 为共享单例、不可就地 grow。属防御性收紧，调用方 `_refold` 已先判 `count >= _folds.count`。
- **A1 的测量口径**：回放用 bubble 消息样式（测试全局默认 sticky）。sticky 下布局结束后的粘顶候选重算会触发一次 `setState`（实测第 72 个增量，20/200 回合一致），把外壳 29 行连带重建；该 `setState` 由布局引起、不属增量路径（设计 §3.3 已把粘顶调度排除在快路径外）。改 bubble 后按设计档 §8 原文（每段 `notify` + `pump(8ms)`，无额外 settle 帧）测得严格 0。

#### 4. 读数（同机同法，改前 / 改后）

改前（基线，未改产品码）：

- A1：每增量 `findRow` 27..31、`item` 21..24、`superList` 1、`selection` 1、`images` 1、`scrollbar` 2、`column` 0、`markdown` 1。
- A2：20 回合与 200 回合逐项 `equal=false`。B1①：`itemAt` 调用 258,101（20）vs 474,101（200）；整表扫描 120/120。B1③：两次 `all()` 均全量读（202/202），`same=false`。C1：`parses=200`。

改后：

- **F1-20 / F1-200**：`findRow` 0、`superList` 0、`selection` 0、`column` 0、`images` 0、`scrollbar` 0、`item` 120（每次增量 1）、`markdown` 18（每次 0..1）；`reads` 960（每次增量 8）；`readAll` 0；`dataOk=true`；`terminal=true`；`images=1645/0`（20 回合）、`images=16405/0`（200 回合），`same=true`。
- **A2**：`equal=true`；**B1①**：两跑 `reads` 逐次相等。
- **C1**：`parses=30`（≥5、≤34）；**C2**：`terminal=true`；C1 时钟前置：7 帧 8ms 推进 56ms（≥50ms）。
- 每次增量的重建面固定为「`ChatItemView` 1 + `MarkdownBlocks` ≤1」，与历史长度无关。

#### 5. 预算超限的说明（不裁）

四个文件超预算，均已实测记录（表见第 1 条）。原因：① 快照/判据是 11 字段的命名记录类型（12 行）+ 对外行为注释，压缩只能牺牲可读性；④⑤⑥ 是设计档 §7 用例表（T3 思绪连跑、T10 前缀条件、A2/A3/B1②、B2 逐下标对拍）与两跑读数脚本带来的用例体量，设计档排预算时只计了 F1+N1。未做裁剪：用例对应验收项，删用例等于删验收。设计档 §4 表未改（设计档笔在 eng-designer）。

#### 6. 验证

- `flutter analyze lib/chat/chat_history_view.dart lib/chat/step_folds.dart lib/chat/widgets/markdown_view.dart test/chat/chat_history_rebuild_test.dart test/chat/step_folds_test.dart test/markdown_test.dart` → `No issues found`。
- `flutter test` 七个验收文件（上述三个测试 + `history_scroll_test` / `sticky_message_test` / `selection_scroll_test` / `fold_view_test`）→ 68 passed / 3 failed。3 条均为 `test/markdown_test.dart` 的 link/icon 用例在本机 Windows 的既有红项（`p.normalize` 把 `/p/lib/a.dart` 变成 `\p\lib\a.dart`），与本次改动无关：把三个产品文件回退到 HEAD 后同红。
- 与本批同面的既有红项另查：`test/steps_test.dart`「summarized thought headed by bold title」、`test/chat_split_test.dart`（277 vs 317）在 HEAD 上同样红；全仓 `flutter test` 的大量红项集中在 macOS/终端/LSP/安装器等平台面，非本批面。
- 单元测试文件：`test/chat/chat_history_rebuild_test.dart`、`test/chat/step_folds_test.dart`、`test/markdown_test.dart`（随本批次档归档，未进 CI，未转集成测试）。

#### 7. 审计与评审轮次

- **内部 explore 分歧审计**：1 轮，结论 FAIL（2×🟡 + 5×🔵，无 🔴）。已修：B1③ 补 `imagesFirst` 断言；删掉计帧前的两个零时长 `pump()`（改为 bubble 样式消除粘顶 setState 干扰，回到设计档 §8 原文）；补 T3 思绪连跑用例与 T10 前缀条件用例；图片键与注释对齐；`readAll` 指标改名；测试钩子拆卸与读数标签。
- **内部 advisor 代码评审**：2 轮。第 1 轮 `pass`（🟡：编辑判据与设计不符、预算未记档；🔵 5 条），逐条修复后第 2 轮 `pass`，仅余「预算未记档」，即本节第 1/5 条所记。
- **终态**：`clean`（无未解决 🔴；余项为已记档的预算说明）。

#### 8. 未做 / 边界

- **W1 真机走查**（≥200 条长对话主观跟手、图片灯箱、粘顶样式）未由本角色执行，待父代理/用户按设计档 §6.1-W1 走查。
- 设计档未同步的两处（`extend` 重读最后一回合、行数实测）需 eng-designer 在 §3.4/§4 补记；本角色不改设计档。

## §6 验证与收口（父代理）

## 验证与收口（B 批 · 流式重建）

### 父代理复核（2026-10-17 22:56，独立复跑）

| 项 | 我的读数 | 结论 |
|---|---|---|
| 行数（node 逐文件实测） | 3541 / 435 / 875 / 433 / 501 / 504 | 与 §5-1、设计档 §4 表**逐格一致** |
| `flutter analyze`（本批六档） | **No issues found**（7.0s） | 通过 |
| `flutter test` 三个目标文件 | **51 passed / 3 failed** | 见下条归因 |
| 3 条红项 | `test/markdown_test.dart` 的 link/icon 用例；失败信息 `/p/lib/a.dart` vs `\p\lib\a.dart` | 根因 = Windows 路径分隔符（`p.normalize`），**既有环境类** |
| 归因证据（不靠自述） | 核对 `markdown_view.dart` 完整 diff：**只有节流新增**，链接/图标解析零改动；单次 `pumpWidget` 的用例不可能被 50ms 节流影响 | 与本批无关，成立 |

### 设计偏差（四条，已由 eng-designer 记入设计档 §12）

1. `extend` 重读最后一回合（原写"只 append"）——回合结束会原地替换同下标条目；代价 8 读/增量，与历史长度无关（20/200 相同）。
2. `extend` 加 `assert(count >= _items.length)`（debug 生效，零运行时成本）。
3. A1 测量口径 = bubble 样式；sticky 下布局引起的一次 `setState`（第 72 个增量，连带外壳 29 行）属布局噪声，不属增量路径。
4. 图片缓存键实际只比 `itemCount`（比末条实例会多一次读，破坏 B1③）；安全性依赖"全路径通知无条件丢"。

四条均**改动前披露、改动后记档**，不是事后补写；机制结论（快路径判据 / `_LiveItem` / 50ms 窗口）未变。

### 读数摘要（同机同法，详见 §5-4）

- 每增量：外壳六类 **0**，`ChatItemView` **恰 1**，`MarkdownBlocks` 0–1；
- 20 回合 ∥ 200 回合**逐增量相等**；条目读 960（每增量 8），两跑相同；
- markdown 解析 **200 → 30**（上界 34）；
- 改前每条增量外壳重建 27–31 行、条目读 258k（20 回合）/474k（200 回合）。

### 已知缺口

1. **W1 真机走查未跑**（需求档 §5-3）：≥200 条长对话持续输出时的滚动跟手度与键入延迟——机器测不了，待用户确认。
2. 四个文件超设计预算（① 超 73 行、④⑤⑥ 超用例预算），已记档；功能未裁剪，预算上限本身未改。
3. `chat_history_view.dart` 3541 行仍在 800 行硬档之上——拆档属 E 批（台账 #47），设计档 §4 已给预案。

### 测试线

- 本批单元测试文件：`test/chat/chat_history_rebuild_test.dart` · `test/chat/step_folds_test.dart` · `test/markdown_test.dart`（随本批次档归档，不进 CI、不转集成测试）。
- 集成场景：**无影响**（本批只改渲染路径，未动业务流与数据模型）；前端集成套件本批不新增。

## 结算（2026-10-18 · 已收口）

- **批**：B 批 · 对话流式渲染（完整链：需求 → 设计 → 两轮设计评审 → 用户批准 → eng-coder 实现 → 父代理复核）。
- **改动面**：`lib/chat/chat_history_view.dart`（3541，+183）· `lib/chat/step_folds.dart`（435，+82）· `lib/chat/widgets/markdown_view.dart`（875，+43）· 三个测试文件（433 / 501 / 504）。
- **读数**：每增量外壳六类 0 · `ChatItemView` 恰 1 · 条目读 960（20 与 200 回合相同，改前 258k / 474k）· markdown 解析 200 → 30 · `flutter analyze` 干净 · 目标三档 51 passed / 3 既有红项（Windows 路径分隔符，已用 diff 排除本批）。
- **评审**：设计 2 轮（15 条 + 2 条 → 全闭）· 代码 2 轮（clean）。
- **台账**：**#44 核销**；W1 走查另立遗留行（条件触发）。
- **未闭环（真机）**：W1 长对话走查未执行——读数达标不等于手感达标，已挂台账待用户下次长会话时顺带确认。
- **结算同步**：状态行置「已收口 2026-10-18」；本档冻结，不再回写。
