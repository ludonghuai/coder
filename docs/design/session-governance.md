# 会话治理（session-governance）设计

> 板块：会话治理 · 需求档：`docs/requirements/session-governance.md`（F1 / F2 / F3，验收 A1–A9）。
> 范围：本仓宿主与适配层（`lib/kernel` · `lib/chat` · `lib/workspace` · `lib/ide` · l10n）+ 声明的外仓检出 `thincoder/`（用户已准 B1 例外；F3 由 A2 批并入本档）。
> 批次：A1 = 改名 + 回合级回退（F1 / F2）；A2 = 编辑已发消息 rewind（F3，§2.5 / §3.4）。
> 一句结论：**重命名 = 内核槽标题的单一写路径**（ACP `session/set_title` → 核 `renameSlot` + `agent.title`）；**回合级回退 = 内核撤销栈加回合标识与写后哈希**（ACP `session/revert`，先 dryRun 出计划、再执行）——宿主不建第二份快照，确认框与结果清单都以内核计划为准。运行中改名走后置态（回合收尾发送，§3.5）；回退入口在回合在飞时不可用（§3.5 末条）。**编辑已发消息（rewind）= 按回合键把对话截到该回合起点**（ACP `session/rewind` → 核 `rewindConversation`：截记录存储 + 重建两线 + 剪回合索引），文件零触碰，截断与落盘在同一次动作内（§2.5 / §3.4）。

## 1. 模块目标与范围

一个操作在两个内核上语义一致，且终端与桌面看到同一份事实：

- **F1 会话重命名**：桌面可改任意会话标题（含运行中会话，不打断回合）；标题单一来源 = 内核槽记录（槽文件 + manifest），终端 `session list` / 桌面列表同读；手改标题粘住（内核自动标题不再覆盖）；空白标题被拒并有界面提示。
- **F2 回合级文件回退**：对任一已结束回合，把「从该回合起」内核改过的文件恢复原状；单一来源 = 内核撤销栈（`agent._undoStack`），不建宿主快照；创建态回退 = 删除；回合后被改过的文件跳过并列出；超限 / 已逐出条目列为「无法回退」；执行前弹确认；与 Git 无耦合。
- **F3 编辑已发消息（rewind）**：对一条**本进程创建的**用户消息，编辑后从该消息起截断对话并重发；文件保持不动（文件回退 = F2）；重放历史（无回合键）被拒并提示；截断在活会话内完成并落盘（§2.5）；不做自动轮编辑与消息级截断。
- **能力门**：宿主既有 `RenamesSession`（`lib/kernel/agent_kernel.dart:298-300`）与 `RevertsChanges`（同档 `:263-266`）不变；新增的「先看计划再执行」面走独立可选接口，Claude 内核零改。
- **重写能力**：`ThincoderKernel` 新增 implements `RewindsConversation`（同档 `:268-282`，接口零改）；Claude / Codex 既有实现非回归。

范围外（需求档 §3）：fork、Git 操作、逐文件挑选回退、消息级（非回合级）截断、自动轮编辑、跨进程实时同步、Claude 既有行为变更。

## 2. 做法与理由

### 2.1 机制总览

```text
重命名（手动）
  桌面 inline 字段（校验：空白 / >80）
    ├─ 会话已开且内核可改名 → ChatSession.rename → ThincoderKernel.rename（§3.5 后置态）
    │     └─ ACP session/set_title {sessionId, title}（排队；只在队列空闲时发送）
    │           └─ 核 renameSlot（槽文件 title + manifest 摘要）+ agent.title = title
    └─ 会话未开（catalog 列表项）→ ThincoderCatalog.rename（短命连接同 session/set_title）
          └─ 落盘后列表重读，桌面与 `session/list` 同值
  粘住：kernel 回合尾 ensureSessionTitle 以 agent.title 非空短路；宿主自动标题器对 thincoder 关闭
  运行中：回合在飞只记目标（last-wins），_endTurn 收尾发送；失败 / 超时 ⇒ error notice + 原值（§3.5）

回退（回合级）
  ACP session/prompt 携 turnId（宿主回合 id）→ 核 execTurn 起一个回合键（key + ordinal）
  每次写工具执行前 snapshotForUndo（逐触达路径）→ 条目带 key / ordinal / seq
  执行返回后 recordUndoAfter：routed 写用请求内容、本地写读回，记写后哈希
  session/revert {sinceTurn, dryRun:true} → undoPlan：按文件分组出计划（restore / delete / skipped / unrevertable）
  宿主确认框展示该计划 → session/revert {sinceTurn, dryRun:false} → undoApply（逐文件逆序、部分成功）→ 结果清单
  回合在飞 ⇒ 回退入口不可用（排队写会超时成假失败，且盘面在漂）

编辑已发消息（rewind）
  宿主 editMessage(index, msg) → stop() → session/rewind {sessionId, turnId: itemId}
    → 核排队执行：查回合键（本进程、未逐出、截断点有效）→ 在飞拒绝（-32002）
    → rewindConversation：记录存储 truncate(turn.storeFrom) → 两线重建 → 剪回合索引（条目保留）
    → persist()（与回合尾同一个 save）→ 返回 {} → 宿主 send(编辑后的文本) 开新回合
  拒绝（未知回合 / 重放历史 / 在飞）→ 宿主一条提示，对话不变
```

### 2.2 最近先例（对齐 ∥ 偏离及理由）

- **对齐 ① 终端 `/rename`**（`thincoder/thincoder-cli/src/tui/cmd-session.mjs:7-38`）：trim → 空则提示 → >80 字符拒绝 → `renameSlot(cwd, slot, title)` → 成功后 `agent.title = title`。ACP `session/set_title` 逐条同判据（同一 80 上限、同一 `{ok, reason}` 映射、同一 `agent.title` 赋值）——它同时证明了「写槽 + 写内存标题」是既有粘住口径。
- **对齐 ② Claude 内核**（`lib/kernel/claude_code/claude_code_kernel.dart:1188-1222`）：`RevertsChanges` / `RenamesSession` 的宿主侧形状（失败以 `NoticeItem` 可见）；本批不改其实现与调用路径（A6 = 非回归）。
- **对齐 ③ 终端 `/undo`**（`thincoder/thincoder-cli/src/tui/cmd-undo.mjs:15-66`）：消费同一 `agent._undoStack`；`oversize` 先于 `backup === null` 判定（防把超限占位误当创建态删档）。桌面回退不改该命令，新增的条目字段对它是增量（无键 = 旧行为）。
- **对齐 ④ ACP 入站队列**（`thincoder/thincoder-cli/src/acp/transport.mjs:13-19` / `:31-40`）：默认排队，白名单 = `session/cancel` · `session/close` · `session/list` + `autoApprove`；判据见 `thincoder/docs/cli/design/ACP-CLIENT.md` §3.1。两个新方法**默认排队、不进白名单**。
- **对齐 ⑤ 同仓最近先例**：模型切换后置应用（`docs/design/thincoder-adapter.md` §24.1 的 `_modelTarget` / `_modelDeferred` / `_modelSending` 状态机，批 14 已落）——本批标题写走同形后置态（`_titleTarget` / `_titleDeferred` / `_titleSending`，§3.5）：回合在飞只记目标、回合收尾发送、last-wins、迟到回报自愈。
  偏离点：模型面有 `config_option_update` 推送可自愈，标题面无推送 ⇒ 自愈径 = 下一次 `session/list` 刷新（桌面列表重读目录）。
- **对齐 ⑥ Claude 内核的 rewind**（`lib/kernel/claude_code/claude_code_kernel.dart:104` implements `RewindsConversation`）：宿主侧同一接口、同一「返回 false ⇒ 对话不变」契约、同一「先 stop、再 rewind、成功才 send」顺序（`lib/chat/chat_session.dart:1212-1240`）；本批只补 thincoder 内核实现与拒绝提示，接口零改。
  偏离点：Claude 按 transcript 项寻址，thincoder 按**回合键**寻址（`itemId` = A1 的回合 id）；宿主传的 `index / turns / lastSeen` 是宿主 transcript 坐标，不进请求（`index` 只作 `Rewound` 的位次兜底；实现注释注明）。
- **偏离 ①**：撤销条目由「单路径 + 无回合」扩为「逐触达路径 + 回合键 + 写后哈希」。理由 = F2.1/F2.4/F2.5 三条判据都要求回合粒度与事后比对，现有条目只有 `{tool, path, backup, oversize, timestamp}`（`thincoder/thincoder-core/undo-stack.mjs:50-52`），无法区分回合、也无法判断「回合后被改过」。
  对 `/undo` 是**增量而非零变**：条目形状变了 ⇒ 单步粒度变了（一次多文件 `apply_patch` 由 0 条变 N 条，`/undo` 一步只回一条路径），50 条 / 64MB 预算的消耗速率同倍变快，终端可回退深度实质缩短。本批**接受**（正确性优先：漏整类写入比深度缩短更坏；逐出仍如实报 `unrevertable: evicted`）；判定条件见 §10 U6。`cmd-undo.mjs` 零改动只说明代码未变（§4.2 零改动清单）。
- **偏离 ②**：快照的路径面由 `args.path ?? args.file`（`undo-stack.mjs:33`）改为工具自报触达面 `toolTouchPaths`（`thincoder/thincoder-core/agent/helpers.mjs:104-117`）。
  理由 = `apply_patch` 只有 `patch` 参数（`thincoder/thincoder-core/tools/patch.mjs:172-185`），现实现根本不为它入栈 ⇒ 桌面回退会漏掉整类写入，`/undo` 同病；
  触达面谓词已是核内单源（门禁 / 记账 / 足迹三面共用），此处只是第四个消费点。
- **偏离 ③**：宿主自动标题器对 thincoder 关闭（新标记接口 `GeneratesTitles`）。理由 = thincoder 核自带 `ensureSessionTitle` / `generateTitle`（`thincoder/thincoder-core/generate-title.mjs:130-147`），而桌面 `workspace.dart:2636-2655` 在 `canRename` 为真时会再跑一次 LLM 标题生成 —— 两个写者、两个 LLM 调用，F1.3 的「粘住」没有唯一判据。

### 2.3 survey 证据

查过：外仓设计档 `thincoder/docs/cli/design/ACP-CLIENT.md` §2.1（方法面表，`:29-44`）、§3.1（FIFO 豁免与三条判据，`:87-114`）、§3.3（方法 → agent 映射，`:174-184`）、§12.8 / §12.9（`_meta` 扩展帧先例）；
`thincoder/docs/cli/design/TUI-COMMANDS.md` §5.3（`/undo` 双上界与快照单源，`:139-141`）；
`thincoder/docs/core/design/SESSION.md` §6.7（标题生成五环：源 / 生成 / 触发 / 写 / 读，`:157-174`）、`:244-245`（`renameSlot` 标题写契约 `{ok, reason}`）、`:276`（`/rename` 只改标题，sidecar 零动作）。
公开源：无新增——两个方法名是 ACP 方法面之外的**扩展方法**（同 `session/delete`、`ledger/*` 的既有做法），不涉协议版本 / 能力位变更；`_meta` 扩展位未被本批使用。结论：上列档与本次设计无相抵之处；`session/set_title` / `session/revert` 需在 ACP-CLIENT §2.1 方法表登记为扩展方法。
A2 追加（2026-10-20）：`thincoder/docs/cli/design/ACP-CLIENT.md` §2.1（方法面表；`session/revert` 行在 `:44`，`session/prompt` 的 `turnId` 在 `:70`）、§2.4（排队归属）；`thincoder/docs/core/design/SESSION.md` §6.27（A1 的撤销栈回合化）、§6.14（记录存储分段与窗口）。公开源：无新增——`session/rewind` 同为扩展方法，不涉协议版本 / 能力位。
同仓设计档：`docs/design/thincoder-adapter.md` §24.1（后置态先例，本批对齐）、§5.2（体量立场 = 只跟 >800 硬顶）、§10（边界行与本批相抵，处置见 §4.1 ㉑，由父侧文档层修正）。

### 2.4 回退算法（逐文件、逆序、部分成功）

**范围** = 回合键 `key` 命中后，撤销栈中 `ordinal >= key.firstOrdinal` 的条目；按绝对路径分组。

**每文件**（组内条目按 `seq` 升序）：

1. 组内任一条 `oversize` ⇒ `unrevertable: oversize`（无备份，不可恢复）。
2. 该路径在本范围（`ordinal >= key.firstOrdinal`）内有条目被逐出（判据 = 逐出账 `_undoLost[path] >= key.firstOrdinal`，§3.2）⇒ `unrevertable: evicted`。
3. 最新条目的写后状态未知（`after == null`：超限占位 / 读不出）⇒ `unrevertable: after-unknown`。
4. 当前盘面与最新条目的 `after` 比对（存在性 + 原始字节 sha256）：不符 ⇒ `skipped: changed`（F2.4：不覆盖用户改动）。
5. 计划动作 = **最旧条目**的 `backup`：`null`（文件在范围内被创建）⇒ `delete`；否则 `restore`（写回最旧 `backup`）。

**执行顺序** = 组按最新条目的 `seq` 降序（越新的改动先处理）；逐文件独立 try/catch，失败进 `failed` 并继续（A5 部分成功）。成功才移除该文件的范围内条目；跳过 / 失败的条目保留（用户修好现场后可重试）。执行前对每文件重做第 3–5 步（dryRun 与执行之间可能隔了用户操作）。

**dryRun** = 同一算法、零写入、零出栈；返回同一形状的计划。确认框展示的就是该计划，执行结果与计划不一致时以执行结果为准并列出。

**逐出与索引的边界规则**（F2.5 / A5）：

- 逐出账 = `Map<path, highestEvictedOrdinal>`：条目被 `shift()` 逐出时记该条目的 `ordinal`（同路径取最大）；查询判据 = 存在 `>= 范围下界` 的逐出 ⇒ 该路径 `evicted`。按键记账会漏「只出现在后续回合、且已被逐出」的路径（查询跨键），按路径 + 下界不会。
- 回合索引逐出：`_undoTurns` 上限 50 键、最旧先出（与栈同向）；键被逐出而条目仍在栈里 ⇒ 该键的回退返回 `-32602 unknown turn`（范围下界已不可得，如实拒绝）；逐出时按新最旧键的 `firstOrdinal` 清理更早的逐出账（不可达）。
- apply 后空键：键保留，范围清空 ⇒ 计划为空（不是未知回合）；宿主对空计划提示「无可回退」。
- 无前键的造键：`beginUndoTurn` 无 `turnId` 且无上一键（先于任何 prompt 的自动轮）⇒ 铸 `p<n>` 新键（与无 `turnId` 客户端同法），不落成「无键条目」。

**预算影响**：每条目 = 一条路径的一次写；一次多文件 `apply_patch` 产出 N 条 ⇒ 50 条 / 64MB 按 N 倍速率消耗。本批接受（§2.2 偏离① / §10 U6）。

**回合键**：`session/prompt` 的 `turnId` 由宿主给（`KernelTurn.id`，UUIDv4，`lib/chat/chat_session.dart:1099-1101`）。
核 `execTurn`（`thincoder/thincoder-cli/src/acp/session.mjs:88-114`）为每个执行回合取键：用户回合用 `turnId`，自动轮（挂起窗消化 / 唤醒）**继承上一个键**、ordinal 自增。
无 `turnId` 的客户端（非桌面）由核铸 `p<n>`。未知键 ⇒ `-32602 unknown turn`（栈与会话同生共死，进程重开后没有可回退的回合）。

### 2.5 rewind 算法（截断点、两线、索引）

**截断点 = 回合起点在记录存储里的绝对位次**（`turn.storeFrom`）。`beginUndoTurn`（`thincoder-core/undo-stack.mjs:69-90`）起轮时记 `storeFrom = agent._recordStore?.total() ?? agent._fullHistory?.length ?? 0`；调用点在 `run` 之前（`thincoder-cli/src/acp/session.mjs:93`），用户消息尚未入线 ⇒ 该位次就是该回合用户消息的落点。自动轮继承键 ⇒ 沿用原键的 `storeFrom`，不重记。

**执行**（新模块 `thincoder-core/session-rewind.mjs` 的 `rewindConversation(agent, turn)`，五步）：

1. `total = store?.total() ?? full.length`；`from = turn.storeFrom`。非整数 / `from < 0` / `from > total` ⇒ `unknown turn`（截断点失配 = 历史已不可得，如实拒绝）；位次不变量不过 ⇒ 同码拒绝（见下）。检查全部在步骤 2 之前 ⇒ 拒绝 = 零变更。
2. `store?.truncate(from)`：记录存储只保留前 `from` 条（删后续段、重写界内末段、重置计数与 `firstUser` 缓存，§4.2 外仓 ⑫）。未绑定存储（模式 F / 测试）⇒ 跳过。
3. 人读线 `agent._fullHistory`（`win = agent._historyWindow > 0 ? agent._historyWindow : total`）：绑定态下前缀未被窗口逐出（`total - full.length === 0`，人读线即存储全尾）⇒ `full.splice(from)` 原位切；否则窗口已裁过前缀 ⇒ `full.splice(0, full.length, ...store.tail(win))` 由**截断后**的存储重载尾窗（恰 `min(from, win)` 条）。
   未绑定 ⇒ `full.splice(from)`。承重假设 = 位次不变量（见下）。
4. 机器线 `agent.history = full.map(stripTruncatedToolArgs)`（由人读线单源重建，逐条消毒：`…` 结尾的 tool 参数置 `{}`）。
   盘面瘦身形（tool 参数截 300 / 结果截 500 / 图占位）随重载支与恢复过的会话进入人读线；半截 `\uXXXX` 会毒化发送载荷（会诊 F6 结论，`thincoder-core/session-lifecycle.mjs:60-61`）⇒ 复用恢复面同一消毒（同档 `:62` 的既有导出，`session-rewind.mjs:13` import；本批只加 `export `、函数体零改，D2 单源）。D-SG22 的取舍不变：transient 注入与压缩摘要仍不在重建面。
5. 回合索引：从 `agent._undoTurns` 移除 `firstOrdinal >= turn.firstOrdinal` 的全部键（被截断回合及其后的键；实现 = `dropTurnsFrom(agent, turn.firstOrdinal)`，§4.2 ⑬）；**撤销栈条目原样保留**（ordinal 不变 ⇒ 前一回合的「从该回合起」仍覆盖它们，F3.4）；`_undoLost` 不动；`agent._undoTurn = null`。

**位次不变量（步骤 3 的承重假设）**：绑定态下 `_fullHistory` 恰为记录存储的末 `full.length` 条——`pushReal`（`thincoder-core/context-push.mjs:27-37`）是两线的单一写缝（同一消息对象、同一顺序）；存储侧按 `shouldAppend` 过滤（`thincoder-core/session-store.mjs:269-271`）——
注：transient 注入直推机器线、不走 `pushReal`（`context-push.mjs:13-14`），故两线条目集相同；窗口驱逐只在人读线尾部裁（`full.length = min(total, window)`）。由此 `_fullHistory[i]` ↔ 存储绝对位次 `total - full.length + i`；未绑定态无存储，位次 = 下标，恒成立。

**被否：按相对位次切**（`full.splice(from - (total - full.length))`）——窗口饱和（`total > win`）时它只删尾巴，留下 `win - (total - from)` 条，与不变量 `full.length === min(total, win)` 冲突 ⇒ 同一会话第二次 rewind 在步骤 1 被拒成 `-32602 unknown turn`（红绿读数：`_fullHistory.length` actual 2 / expected 4）。

**不成立时 ⇒ 拒绝**（步骤 1 的检查项，先于任何写入）：判据 = `store.degraded === false` ∧ `full.length === Math.min(total, agent._historyWindow > 0 ? agent._historyWindow : total)`（未绑定 ⇒ 免检）。
降级缺口（`memTotal > total`）与窗口长度不符都会让「存储尾 ≡ 人读线」不成立 ⇒ `-32602 unknown turn`、零变更。不选：断言抛错（内部不一致变 500，错误面不可见）；按 `_fullHistory` 下标直接切（两坐标系不同，错位会静默删错消息）。

**为什么重建机器线而不是按位切**：两线不等长（机器线多出 transient 提醒，`context-push.mjs:13-15`），且机器线会被压缩改形；按位切会漂。重建丢的是 transient 注入（每轮重发）与压缩摘要（下一次压缩重跑），内容面不缺。被否：按位切两线（漂）；被否：按对象身份找边界（降级是 copy-on-write，`context-degrade.mjs:55-57` 会换对象）。

**回合键继承源改一处**：`beginUndoTurn` 的「无 turnId ⇒ 继承上一键」由 `_undoTurns` 末项改读 `agent._undoTurn`（最近一次起轮指针）。rewind 清空该指针 ⇒ rewind 与重发之间若插入一个自动轮，它铸 `p<n>` 新键而不是并进更早的回合（否则前一回合被污染，回退范围悄悄变大）。正常路径两者等价（每次 `beginUndoTurn` 都写该指针）。

**落盘**：`truncate` 已改 sidecar；slot JSON 由同一个 `save`（`thincoder-core/session.mjs:131`）在同一次动作内重写（`session.persist()`，`closed` 守卫同 A1）。下一次回合存档是同一投影的再次重写。被否：只靠下一回合 save——truncate 已落盘而 slot 仍旧值时退出，两侧对不上，load 会看到旧历史（§10 U9）。

**在飞**：handler 先判 `session.busy || session.suspended` ⇒ `-32002 turn in flight`。正常路径上 rewind 排在 FIFO 里（在飞回合已收尾），该判据只兜挂起窗自起的自动轮。

## 3. 接口契约

### 3.1 ACP 方法面（本仓 → 外仓；均为扩展方法，默认排队）

| 方法 | params | 结果 | 错误面 |
|---|---|---|---|
| `session/set_title` | `{sessionId: string, title: string}` | `{}`（成功；槽文件 + manifest 已写） | `-32602` 空白 / 超 80 / 未知会话 / `invalid-slot`；`-32603` `parse-failure` / `mtime-conflict`（服务器不回滚，调用方可重试） |
| `session/revert` | `{sessionId: string, sinceTurn: string, dryRun?: boolean}` | `{files, skipped, unrevertable, failed}` 四个条目数组（`files` = restore/delete；`skipped` / `unrevertable` 带 reason；dryRun 时 `failed` 恒空） | `-32602` 未知会话 / 未知回合 / 缺 `sinceTurn`；`-32000` 凭据门 |
| `session/rewind` | `{sessionId: string, turnId: string}` | `{}`（成功；对话已截断 + 已落盘） | `-32602` 未知会话 / 缺 `turnId` / unknown turn（重放历史、键已逐出、截断点失配、位次不变量不成立）；`-32002` turn in flight；`-32603` `rewind failed: <msg>`（存储写失败：`truncate` 抛错，盘面可能已变、两线未动）/ `persist-failed`（截断已生效、槽 JSON 未重写）——两档见下；`-32000` 凭据门 |
| `session/prompt`（增参） | 既有 + `turnId?: string` | 不变 | 不变 |

```json
{ "files":       [{ "path": "/tmp/x/a.txt", "displayPath": "a.txt", "action": "restore" }],
  "skipped":     [{ "path": "/tmp/x/b.txt", "displayPath": "b.txt", "reason": "changed" }],
  "unrevertable":[{ "path": "/tmp/x/c.bin", "displayPath": "c.bin", "reason": "oversize" }],
  "failed":      [{ "path": "/tmp/x/d.txt", "displayPath": "d.txt", "error": "EACCES" }] }
```

- 三个方法都过 `requireConfigured()` 凭据门（与会话族同）：无 key 时 `-32000`。
- `session/rewind` 的会话解析与 `revert` 同：**须活跃会话**（回合键随进程；短命连接没有键可查）。排队归属同 A1（§2.2 对齐④）：默认排队、不进白名单。
- **`persist()` 失败面**（`session/rewind` 的落盘步）：`persist()` 与回合尾同一个 `save`（`thincoder-core/session.mjs:131`），槽 JSON 写失败（`EACCES` / `ENOSPC`，`saveProjectedSlot` 的 `.tmp` + rename 兜底也失败）向上抛 ⇒ 回 `-32603 persist-failed`。
  失败后状态：**截断已在内存两线与 sidecar 生效，槽 JSON / manifest 未重写**——**不可重试**（回合键已剪、`_undoTurn` 已清 ⇒ 同 `turnId` 再发得 `-32602`）；**会话内自愈** = 下一次任何 `save`（下一回合尾 `execTurn` 的 finally，`thincoder-cli/src/acp/session.mjs:106-117`）按同一投影重写槽 JSON，两侧收敛到「已截断」；
  **进程若先退出** = `load` 见槽 JSON 更长、`bind` 的 `_materialize` 以槽为准重建 sidecar（`thincoder-core/session-store.mjs:73-81`）⇒ 截断整体撤销，两侧同回旧值（不会停在对不上的两侧）。宿主面：`-32603` 落 §3.3「其余 ⇒ error 提示」，不加文案键。
- **`truncate` 失败面**（与 `persist-failed` 分档）：`rewindConversation` 的 `store.truncate(from)` 写盘失败（`EACCES` / `ENOSPC` / 删段中途失败）⇒ 存储按盘面重同步、保留缺口并置 `degraded`（`thincoder-core/session-store.mjs:256-261`），错误向上抛 ⇒ 回 `-32603 rewind failed: <msg>`。
  失败后状态：**盘面（记录段）可能已变，人读线 / 机器线 / 回合索引 / 槽 JSON 均未动**——本次 rewind 整体失败（宿主一条 error 提示，对话不变）；降级态下同 `turnId` 再发先被步骤 1 的位次不变量拒成 `-32602`。
  **会话内自愈** = 下一次 `save` 的 `catchUp` 按人读线窗口补回被误删的尾段并清降级（同档 `:383-398`，入口 `saveProjectedSlot` `:436`；缺口已滑出窗口 ⇒ 保持降级、投影按存储前缀写）⇒ 补回之后同 `turnId` 重发即正常截断。
- `session/rewind` 只认 `turnId`：`itemId` 由宿主传（= 回合 id），`itemId` 与核回合键是同一个值（`chat_session.dart:201-202` 的「用户消息项 id = 回合 id」约定）。
- `set_title` 成功时必须**同拍**写 `agent.title = title`：回合尾 `saveSession`（`thincoder/thincoder-core/session.mjs:146-149`）与 `ensureSessionTitle`（`generate-title.mjs:131`）都以该字段为准 —— 只写槽文件会被下一次保存覆盖。
- 80 字符上限单源 = `thincoder-core/session-rename.mjs` 新增导出 `MAX_TITLE_LENGTH`；`cmd-session.mjs:19-22` 与 ACP handler 同引。
- **路径形态**：`path` = 绝对路径（分组键 / 去重 / 宿主身份同用）；`displayPath` = 可选展示名（相对会话 cwd 裁剪；cwd 外的路径缺省，客户端回落 `path`）。宿主 `RevertFile.path` / `RevertSkip.path` / `RevertFailure.path` 收绝对路径，`displayPath` 另立可选字段（§3.3）。
- **会话解析**：`set_title` 与 `session/delete` 同法——按 `sessionId` 找磁盘槽位、**无需活跃会话**（目录短命连接即可改未打开会话）；`revert` 相反——**须活跃会话且命中内存栈**（栈随进程，短命连接没有可回退的回合；未知会话 / 未知回合如实 `-32602`）。
- **超时**：两方法仍照连接缺省 60s（不新设常量、不用 `noTimeout`）；不超时的保证来自**发送时机**——`set_title` 走后置态（§3.5）、`revert` 要求在飞门（§3.5 末条），两者都只在队列空闲时发出。

### 3.2 核内数据结构与写入点

**条目**（`agent._undoStack`，向后兼容扩展）：

```js
{ seq, turn, ordinal, tool, path, displayPath, backup, oversize, timestamp, after }
// after = { exists: true, hash: '<sha256 hex>' } | { exists: false } | null（未知）
```

**回合索引**（新增 `agent._undoTurns`，数组，按 key 去重、上限 50）：

```js
{ key, firstOrdinal, storeFrom, paths: ['<abs>', …] }
```

范围 = `ordinal >= firstOrdinal`（开区间到尾，跨后续键）；上限 50 键、最旧先出；键被逐出而条目仍在栈里 ⇒ 该键回退 `-32602 unknown turn`（§2.4 边界规则）。
`storeFrom` = 该回合起点在记录存储里的绝对位次（起轮时 `_recordStore.total()`；未绑定 = `_fullHistory.length`），rewind 的截断点（§2.5）；自动轮继承键 ⇒ 沿用原值。该字段的消费依赖**位次不变量**（存储尾 ≡ 人读线；`_fullHistory[i]` ↔ 绝对位次 `total - full.length + i`）；不成立 ⇒ rewind 拒绝（§2.5）。rewind 剪枝 = 移除 `firstOrdinal >= turn.firstOrdinal` 的全部键，条目保留（F3.4）。

**写入点**：
- `beginUndoTurn(agent, { turnId })`：`ordinal = ++agent._undoTurnSeq`；有 `turnId` ⇒ 新键；无 `turnId` 且有上一键 ⇒ 继承；无 `turnId` 且无上一键 ⇒ 铸 `p<n>` 新键。调用点 = `session.mjs` 的 `execTurn`（覆盖用户回合 / 消化轮 / 唤醒轮三条起轮径）。
- `snapshotForUndo(agent, tool, args, cwd)`：改收工具对象；路径 = `toolTouchPaths` 过滤非字符串并去重；每路径一条（条目带当前 key/ordinal/seq）。调用点 = `thincoder-core/agent/dispatch-run.mjs:68-71`（唯一调用点；本地执行与 routed 执行同在此前快照）。
- `recordUndoAfter(agent, entries, { routedText })`：工具返回后定写后值。routed 分支（`fs/write_text_file`）**不读回**：写后值 = 发给客户端的 `content` 的 sha256（核侧已知所写内容，`exists: true`）。
  本地分支逐路径读回：可读 ⇒ `{exists, hash: sha256(原始字节)}`；不可读 / 超限 ⇒ `null`。调用点 = `dispatch-run.mjs` 的三个返回面：routed 分支 `:74-86`（传 `content`）、本地成功 `:136-137` 之后（**不看** 结果串是否以 `Error:` 开头——部分写入也可能已落盘）、catch 分支 `:160-183` 之前。
- `undoPlan` / `undoApply`：`session/revert` 的两个实现面；`apply` 成功后把范围内条目从栈中移除并同步索引；键保留（范围清空 ⇒ 再次回退得空计划，不是未知回合）。
- 逐出：`undo-stack.mjs` 现有 `shift()` 两处（条数 / 总量）改为「按路径记逐出账」：`agent._undoLost` = `Map<path, highestEvictedOrdinal>`（同路径取最大）；回合索引逐出时按新最旧键的 `firstOrdinal` 清理更早的账。逐出账不按键记账——查询范围跨后续键，按键会漏（§2.4）。

### 3.3 宿主接口与投影

```dart
// lib/kernel/agent_kernel.dart：先看计划再执行的回退（可选能力；Claude 不实现）
abstract interface class PlansReverts {
  /// 现在能不能计划 / 执行回退：无在飞回合、无暂存自动轮，且有可用连接（`_running` = 连接非空且就绪；§3.5 末条）。
  bool get canRevertNow;
  Future<RevertPlan> revertPlan({required String sinceTurn});
  Future<RevertOutcome> applyRevert({required String sinceTurn});
}

/// 内核自己命名会话（回合尾自动标题）：宿主不再生成第二个标题。
abstract interface class GeneratesTitles {}

/// 内核对会话标题走后置态：回合在飞时只记目标（§3.5）。
abstract interface class DefersRename {
  /// 等待回合结束生效的标题；null = 无等待。
  String? get pendingTitle;
}

/// 目录能改一个未打开会话的标题（写内核记录，不建会话进程常驻）。
abstract interface class RenamesStoredSessions {
  Future<void> rename(SessionRecord session, String title);
}
```

```dart
// lib/kernel/kernel_types.dart
class RevertPlan { final List<RevertFile> files; final List<RevertSkip> skipped; final List<RevertSkip> unrevertable; }
class RevertOutcome { …同形…; final List<RevertFailure> failed; }
class RevertFile { final String path; final String? displayPath; final RevertAction action; }   // restore | delete
class RevertSkip { final String path; final String? displayPath; final String reason; }
class RevertFailure { final String path; final String? displayPath; final String error; }
```

- `ThincoderKernel implements RenamesSession, PlansReverts, GeneratesTitles, DefersRename, RewindsConversation`；`ThincoderCatalog implements RenamesStoredSessions`。
- `RewindsConversation.rewind`（`lib/kernel/agent_kernel.dart:268-282`）：thincoder 只消费 `itemId`（= A1 回合 id）⇒ 发 `session/rewind {sessionId, turnId: itemId}`。
  `index / turns / lastSeen` 不进请求；`index` 只作 `Rewound` 的位次兜底（实现注释注明）。
  成功 ⇒ 清内核 `_queue`（`thincoder_kernel.dart:146`；既有同类清理点 `:496` / `:591`）+ 发 `Rewound(itemId, index)`（同档 `:976`）+ 返回 `true`。
  清队列的由：被截断点之后仍在排队的回合消息不再投递——否则它们照常执行，重发回合反排在它们之后，与 F3.1「从该消息起截断」相抵。
  宿主 `lib/kernel/transcript.dart:174-180` 据此截断 transcript：按 `itemId` 定位、找不到时用 `index` 兜底（Claude / Codex 同法：`codex_kernel.dart:244` / `claude_code_kernel.dart:1123`）。
  `-32602` ⇒ 一条 `rewindNotInThisRun` 提示；`-32002` ⇒ `rewindTurnInFlight`；其余 ⇒ error 提示。
  失败一律 `false`，对话不变。请求发送走 `revertPlan` 的同一请求面。
- `ChatSession` 投影：
  - `String? get revertTurn` = 首个待处理改动的 `turnId`——只供 ActivityStrip「Undo all」取起点，不承担「有没有可回退的改动」的判据。
  - `bool get canPlanRevert` = **只看能力 + 空闲**（内核为 `PlansReverts` 且 `canRevertNow`）——不以宿主 pending 列表为门（与 D-SG5 一致：宿主会少列）。
  - `Future<RevertPlan> revertPlan(String sinceTurn)` / `Future<RevertOutcome> applyRevert(String sinceTurn)`：携带回合参数，入口 ② 传该用户回合的 id。
  - 「该回合是否有内核记录的改动」无独立读面：**入口常显、点击后 dryRun 空计划即提示「无可回退」**（`revertNothingToRevert`）。被否：新增核侧只读判据（多一条协议面，空计划探测已足够）。
  - `bool get ownsTitle`（内核自带标题，见 `GeneratesTitles`）；`String? get pendingTitle`（运行中改名的等待目标，见 §3.5）。
  - 既有 `undoAllChanges` 保持为 Claude 的旧路径（A6）；thincoder 面由它返回确认流程回调（条件 = `canPlanRevert && revertTurn != null`）。
- `workspace._names`：对具备 `RenamesSession` 的内核不参与显示（`workspace.dart:527` 的兜底判定加能力门）也不在改名时落盘（`:2667`）；存量条目由读面忽略，`_sync` 的既有清理（`:1735`）继续收敛。代码形态已实读（`:527` 确实先读 `_names`）。
- 宿主回合 id → 核键：`ThincoderKernel` 在 `session/prompt` 带 `turnId = _turn`（与 `TurnStarted` 同一 id）；自动轮帧开始时记 `auto:<n> → 最近一次 prompt 的 turnId`，供 `revertPlan(sinceTurn: 'auto:<n>')` 归一。

### 3.4 两条时序

```text
改名（会话已开）
用户 → inline 字段 onDone → workspace.rename(trim, ≤80)
  → session.rename(title) → 内核：_slot 未知 ⇒ 暂存 _pendingTitle；已知 ⇒ 入 §3.5 后置态
  → 队列空闲 ⇒ 立刻 session/set_title；回合在飞 ⇒ 只记目标（last-wins）
  → 成功 ⇒ workspace._retitle(thread, title)（桌面列表即时）
  → 失败 / 超时 ⇒ 会话内 NoticeItem(error)（值保持原样）；核已迟到执行的情形由下一次 session/list 刷新自愈

回退
用户 →「Undo all」（起点 = 首个待处理回合的 turnId）/ 回合菜单「Revert files from this turn…」（该回合 id）
  → 回合在飞 ⇒ 入口不可用（灰 + tooltip「回合结束后可回退」）；结束后可点
  → ChatSession.revertPlan(sinceTurn) → session/revert {sinceTurn, dryRun:true}
  → 空计划 ⇒ 提示「无可回退」，结束
  → 确认框（按计划列文件 / 跳过 / 无法回退）
  → 取消 ⇒ 结束（零写入）
  → 确认 ⇒ ChatSession.applyRevert(sinceTurn) → session/revert {sinceTurn, dryRun:false}
        → 结果框（恢复 / 跳过 / 无法回退 / 失败）+ 会话内 NoticeItem（宿主按 §9 的 revertSummary* 三键拼摘要）
        → ChangesReverted（清空待处理清单）仅当 outcome.files 非空时发；全跳过 / 全失败不发（条目保留，D-SG11）
```

**rewind 时序**：

```text
用户 → 编辑某条用户消息并提交 → 宿主 editMessage（chat_session.dart:1212-1240）：stop() → rewind
  → session/rewind {sessionId, turnId: itemId}（排队）
  → 核：活跃会话？在飞？回合键在 _undoTurns？storeFrom 有效？
        ├─ 任一否 ⇒ -32602 / -32002 ⇒ 宿主一条提示，对话不变（F3.6）
        └─ 是 ⇒ rewindConversation（§2.5 五步）→ persist() → {}
  → 宿主收到 true ⇒ send(编辑后的文本)（新回合）；false ⇒ 对话保持原样
```

### 3.5 标题后置态（与适配档 §24.1 同形）

```text
改标题（ThincoderKernel.rename）
  ├─ 会话尚未建（_slot == null）⇒ 暂存 _pendingTitle（既有；建会话后补发）
  ├─ 回合在飞（_turn != null）∥ 暂存自动轮在（_pendingAuto != null）
  │     ⇒ _titleTarget = title + _titleDeferred = true（last-wins；不发）
  ├─ 发送中（_titleSending）⇒ 只改 _titleTarget（应答落地后按 last-wins 再发）
  └─ 空闲 ⇒ _titleTarget = title; _titleDeferred = false; _titleSending = true
        ▼ session/set_title {sessionId, title}
        ├─ 成功 ⇒ 宿主 _retitle（列表即时）；槽文件 title + manifest 摘要已写
        └─ 错误 / 60s 超时 ⇒ NoticeItem(error)（标题保持原值）+ appEvent 一行
              ▼ 应答 / 错误落地：_titleSending = false；目标已换 ⇒ 再发一次
```

- 发送前置判据：`_turn == null && _pendingAuto == null && !_titleSending && !_releaseWanted`；不满足 ⇒ 只记目标（不新发）。触发点 = `_endTurn` 在 `_drain()` 之前（与适配档 §24.1 同一收尾位）+ 空闲点选直接走同一 pump。
- 超时 = 连接缺省 60s（不新设常量、不用 `noTimeout`）：发送点只在队列空闲时 ⇒ 正常一趟往返即答；60s 只兜病理竞态。被否：`set_title` 显式不设超时 + 可见等待态——写卡住会永久占住发送位（适配档 §24.1 D98 同判据），且等待窗口无上界；被否：把 `set_title` 加进 FIFO 豁免白名单（写落在在飞回合里，与回合尾整档 save 交错；D-SG10 不变）。
- 迟到回报自愈：`set_title` 无推送通知 ⇒ 超时被桌面丢弃、核随后执行的情形，下一次 `session/list` 刷新（列表重读 / 目录 re-list）读到新标题即自愈；error 文案只说「未确认」。
- 等待态可见面 = 行仍显示**已确认**标题；再次打开字段时预填 `pendingTitle`（last-wins 目标）。不把目标当已生效（显示只认成功回报）。
- `dispose()` / `_teardown()` / 会话切换 ⇒ 清 `_titleTarget` / `_titleDeferred` / `_titleSending`（不把 A 会话的标题设到 B）。
- **`session/revert` 的在飞路径**（同一个 60s 判据）：回退入口两处（ActivityStrip / 右键）都要求**无在飞回合且有可用连接**（`_turn == null && _pendingAuto == null && _running`，即 `canRevertNow`；`_running` = 连接非空且就绪——无连接时发请求同样只会吃 60s）；不满足时入口不可用（在飞时灰显、tooltip「回合结束后可回退」）。理由 = ① 排队写会超 60s 变成假失败（与本条同病）；② 在飞回合仍在写文件，计划与执行之间盘面必漂；③ F2.1 只要求已结束回合。

## 4. 受影响文件清单

行数 = 2026-10-20 本仓 / 外仓工作树实测（两仓均有他批未提交改动，实施首轮复核、以复核值为准）。

### 4.1 本仓

| # | 坐标（现况行数） | 改动 | 预算 |
|---|---|---|---|
| ① | `lib/kernel/agent_kernel.dart`（481） | `PlansReverts`（含 `canRevertNow`）/ `GeneratesTitles` / `DefersRename` / `RenamesStoredSessions` 四接口 + 文档 | ≤ +34（⇒ ≤515，入 >500 层，不立缝） |
| ② | `lib/kernel/kernel_types.dart`（615） | `RevertPlan` / `RevertOutcome` / `RevertFile` / `RevertSkip` / `RevertFailure` / 枚举（含可选 `displayPath`） | ≤ +54（⇒ ≤669；>500 且 <800，不立缝） |
| ③ | `lib/kernel/thincoder/thincoder_kernel.dart`（1122） | implements `RenamesSession` + 三新接口；`rename`（`_pendingTitle` + §3.5 后置态）；`revertPlan` / `applyRevert`（请求 + 结果映射；`ChangesReverted` 仅 `outcome.files` 非空时发；摘要归宿主 §9）；`canRevertNow`；prompt 带 `turnId`；自动轮 → 键映射 | ≤ +175（⇒ ≤1297；>800 名单，行级） |
| ④ | `lib/kernel/thincoder/thincoder_catalog.dart`（131） | implements `RenamesStoredSessions`；短命连接 `session/set_title`（`_serial` 队列同 `delete`） | ≤ +22（⇒ ≤153） |
| ⑤ | `lib/chat/chat_session.dart`（1223） | `revertTurn` / `canPlanRevert`（能力 × 空闲）/ `revertPlan(sinceTurn)` / `applyRevert(sinceTurn)` / `ownsTitle` / `pendingTitle` 投影；`undoAllChanges` 的 thincoder 面 | ≤ +46（⇒ ≤1269；>800 名单，行级） |
| ⑥ | `lib/chat/chat_screen.dart`（1272） | `onUndo` 改「可计划 ⇒ 确认流程，否则旧路径」；标题栏改名走校验结果 | ≤ +28（⇒ ≤1300；>800 名单，行级） |
| ⑦ | `lib/chat/panels/revert_dialog.dart`（新增） | 确认框 + 结果框 + 空计划提示（`showIdeDialog` 形；列表滚动、计数、取消为默认项） | 实测 349（新档） |
| ⑧ | `lib/chat/chat_history_view.dart`（3691） | 用户消息右键菜单项「Revert files from this turn…」（`_contextMenu` 加一分支，沿用 `_linkMenu` 同法；在飞时禁用） | ≤ +48（⇒ ≤3739；>800 名单，行级） |
| ⑨ | `lib/chat/widgets/user_message_bubble.dart`（1134） | 右键回调（只报位置，菜单由 history 持有） | ≤ +12（⇒ ≤1146；>800 名单，行级） |
| ⑩ | `lib/chat/widgets/inline_rename_field.dart`（95） | `validator`（空 / >80）+ 行内错误提示；提交被拒时不关闭 | ≤ +26（⇒ ≤121） |
| ⑪ | `lib/workspace/workspace.dart`（2835） | `rename` 走「内核 / 目录 / `_names` 兜底」三径并返回结果；`_names` 对可改名内核不参与显示（`:527`）与落盘（`:2667`）；自动标题器加 `ownsTitle` 门 | ≤ +56（⇒ ≤2891；>800 名单，行级） |
| ⑫ | `lib/sidebar/sidebar.dart`（3784）· `lib/ide/ide_chat_title.dart`（509）· `lib/ide/ide_tab_bar.dart`（785）· `lib/workbench.dart`（4585） | 改名的四个调用点接「被拒 ⇒ 保留编辑态」+ 失败提示（各 2–6 行） | 合计 ≤ +18 |
| ⑬ | `lib/ide/ide_agent_edits.dart`（936） | 菜单的 undo-all 改走同一确认流程 | ≤ +8（⇒ ≤944） |
| ⑭ | `lib/l10n/app_en.arb`（7241）· `app_zh.arb`（2821） | **21 键**（A1 面；§9 键表，A2 另 +2 见 ㉕；含逐键 en / zh 值、4 组名、4 类 reason、4 条 ICU 复数（3 条摘要 + 1 条文件计数）、空计划 / 在飞提示） | 实测 en +42（⇒ 7283）/ zh +21（⇒ 2842） |
| ⑮ | `lib/l10n/app_localizations.dart`（16996）· `_en`（10375）· `_zh`（9809） | 生成档同拍手改（无 SDK；保持 `test/l10n_test.dart` 绿） | 实测 +126 / +99 / +99（⇒ 17122 / 10474 / 9908） |
| ⑯ | `test/kernel/thincoder_kernel_test.dart`（3844） | G1 / G1b / G3–G8 / G11（宿主接线 / 后置态 / 结果映射；核侧断言见 §4.2 ⑪） | ≤ +300（⇒ ≤4144；>800 名单，只加用例） |
| ⑰ | `test/kernel/thincoder_catalog_test.dart`（189） | G9（闭会话改名走短命连接） | ≤ +70（⇒ ≤259） |
| ⑱ | `test/chat/revert_flow_test.dart`（新增） | G10 / G12（确认取消零调用 / 宿主投影：能力门、`sinceTurn` 透传、空计划提示） | 实测 241（新档） |
| ⑲ | `lib/kernel/thincoder/thincoder_mock.dart`（668） | G1 / G1b / G5–G8 的脚本面：`session/set_title`（空白 / 超 80 / `titleError` ⇒ `-32602`，成功改 `slots` 标题）+ `session/revert`（可脚本计划 / 结果 / 错误）+ 请求记录 | ≤ +35（⇒ ≤703；>500 且 <800，不立缝） |
| ⑳ | `test/workspace/agent_title_test.dart`（40） | G2（自动标题器门：thincoder 零调用、Claude 照旧） | ≤ +25（⇒ ≤65） |
| ㉑ | `docs/design/thincoder-adapter.md`（文档面） | §10 边界删「回退 / 改名」；§3.4 `session/prompt` 行补 `turnId?`；档头批次名册（`:5`）+ §7 B1 例外补本批；§5.2 的 `thincoder_kernel.dart` 缝候选行注明「本批 +175 后再评估」 | 文档面；**本批只报告，由父侧文档层修正**（R1/R7a：他板块档，不在本设计笔域） |
| ㉒ | `lib/chat/panels/activity_strip.dart`（520） | 「Undo all」在飞时灰态 + `revertTurnInFlight` tooltip（`PanelButton` 已支持 tooltip，`interaction_panel.dart:947-962`）；其余不动 | ≤ +5（⇒ ≤525） |
| ㉓ | `lib/kernel/thincoder/thincoder_kernel.dart`（1295） | implements `RewindsConversation`；`rewind`（发 `session/rewind` + 拒绝提示；`-32602` / `-32002` 分流）；成功 ⇒ 清 `_queue` + 发 `Rewound(itemId, index)` | ≤ +50（⇒ ≤1345） |
| ㉔ | `lib/kernel/thincoder/thincoder_mock.dart`（702） | `session/rewind` 脚本面（成功 / `-32602` / `-32002`）+ 请求记录 | ≤ +20（⇒ ≤722） |
| ㉕ | `lib/l10n/app_en.arb`（7282）· `app_zh.arb`（2841） | **2 键**（`rewindNotInThisRun` / `rewindTurnInFlight`，§9） | +4（⇒ 7286）/ +2（⇒ 2843） |
| ㉖ | `lib/l10n/app_localizations.dart`（17121）· `_en`（10473）· `_zh`（9907） | 生成档同拍手改（抽象档 6 行/键、impl 3 行/键） | +12（⇒ 17133）/ +6（⇒ 10479）/ +6（⇒ 9913） |
| ㉗ | `test/kernel/thincoder_kernel_test.dart`（4143） | T1–T5（§7） | 实测 4299（⇒ ≤4300；>800 名单，只加用例） |

生成档增量由成员体式决定：抽象档每成员 6 行（4 行文档注释 + 声明 + 空行）、impl 每 getter 3 行 ∥ 每复数方法 12 行 ⇒ 21 键即 +126 / +99 / +99；压行会偏离 gen-l10n 体式，按实测登记。

零改动：`lib/kernel/claude_code/**`（A6）· `lib/kernel/codex/**` · `lib/kernel/transcript.dart`（`ChangesReverted` 语义不变）· `lib/kernel/thincoder/thincoder_events.dart` · 固件 `test/fixtures/thincoder/**`。

F3（A2）零改动面（口径 = **A2 相对 A1 落地后的零改动**；A1 已改的档与行不在此列）：`lib/chat/chat_session.dart`（`editMessage` 已在 `:1212-1240`；`canEditMessages` `:593` 保持接口判据；A1 的 ⑤ 改动不与之冲突）· `lib/chat/chat_history_view.dart`（可编辑分支 `:1845-1849` 已在；A1 的 ⑧ 改动不与之冲突）
· `lib/kernel/agent_kernel.dart`（接口 `:268-282`；A1 的 ① 改动不与之冲突）· `lib/kernel/claude_code/**`（Claude 的 rewind 非回归）。

### 4.2 外仓 `thincoder/`（B1 例外；外仓写入由 eng-coder 子代理执行）

| # | 坐标（现况行数） | 改动 | 预算 |
|---|---|---|---|
| ① | `thincoder-core/undo-stack.mjs`（62） | 条目字段 + 回合索引 + `beginUndoTurn` / `recordUndoAfter` / `undoPlan` / `undoApply` / 逐出账（按路径 + 下界）；`snapshotForUndo` 改收工具对象 + 逐路径 | ≤ +215（⇒ ≤277） |
| ② | `thincoder-core/agent/dispatch-run.mjs`（186） | 快照调用改参并接返回值；两处执行返回后 `recordUndoAfter`（routed 分支传 `content`） | ≤ +14（⇒ ≤200） |
| ③ | `thincoder-core/session-rename.mjs`（43） | 导出 `MAX_TITLE_LENGTH = 80` | ≤ +4（⇒ ≤47） |
| ④ | `thincoder-cli/src/tui/cmd-session.mjs`（140） | 80 上限改引单源常量 | 净 0（改 1 行） |
| ⑤ | `thincoder-cli/src/acp/session.mjs`（191） | `execTurn` 起回合键（含无前键造键）；`run(input, {turnId})` 透传 | ≤ +18（⇒ ≤209） |
| ⑥ | `thincoder-cli/src/acp/handlers-session.mjs`（477） | 仅 `session/prompt` 读 `turnId` 并透传 | ≤ +12（⇒ ≤489，守住 500 硬限） |
| ⑦ | `thincoder-cli/src/acp/handlers-session-meta.mjs`（新增） | `createSessionMetaHandlers(ctx)`：`session/set_title`（磁盘槽位，无需活跃会话）+ `session/revert`（活跃会话 + 栈命中；含凭据门、错误映射） | ~+115（<500） |
| ⑧ | `thincoder-cli/src/acp.mjs`（185） | 装配 spread 一行 + import 一行 | ≤ +3（⇒ ≤188） |
| ⑨ | `thincoder/docs/cli/design/ACP-CLIENT.md` | §2.1 方法表登记两扩展方法；新增 §2.4（队列归属与 `session/prompt` 的 `turnId`；形状 / 错误面指本设计 §3.1） | 文档面 |
| ⑩ | `thincoder/docs/cli/design/TUI-COMMANDS.md` §5.3 · `thincoder/docs/core/design/SESSION.md` §6.27 | §5.3 一行：`/undo` 与桌面回退同栈同口径（条目逐触达路径 / 深度随预算缩短）；同档新增 §6.27「撤销栈回合化」（回合标识 / 写后哈希 / 逐出账，指本设计 §2.4 / §3.2） | 文档面 |
| ⑪ | `thincoder/docs/batches/<A1 批>.test.mjs`（新增，仓惯例：随批次档、零留存） | G13–G20（纯函数 + 假传输：快照 / 计划 / 执行 / 写后值 / 超限 / 逐出 / 索引边界 / 标题 / 错误面） | ~+260，收口删除 |
| ⑫ | `thincoder-core/session-store.mjs`（441） | `RecordStore.truncate(n)`：保留前 n 条（删后续段、重写界内末段）、重置计数 / `firstUser` 缓存；**段大小注入缝**（G21）= 模块级 `let _segSizeOverride = null` + `export function __setRecordSegSize(n)`（仅测试档 import、收尾置回 `null`、默认值不改生产行为），消费点统一走 `segSize() = _segSizeOverride ?? RECORD_SEG_MESSAGES`（7 处：`:96` / `:175` / `:197` / `:205-206` / `:209` / `:243` / `:312`） | ≤ +50（⇒ ≤491，守 500 硬限；含注入缝 ~+8） |
| ⑬ | `thincoder-core/undo-stack.mjs`（277） | `beginUndoTurn` 记 `storeFrom`、继承源改 `agent._undoTurn`；新增 `dropTurnsFrom(agent, firstOrdinal)` | ≤ +25（⇒ ≤302） |
| ⑭ | `thincoder-core/session-rewind.mjs`（新增） | `rewindConversation(agent, turn)`（§2.5 五步） | ~+85（<500） |
| ⑮ | `thincoder-cli/src/acp/handlers-session-meta.mjs`（63） | `session/rewind` handler（凭据门 / 活跃会话 / 在飞 / 未知回合 / persist） | ≤ +45（⇒ ≤108；远低于 500） |
| ⑯ | `thincoder-cli/src/acp/session.mjs`（195） | 暴露 `persist()`（同一 `save`，`closed` 守卫） | ≤ +8（⇒ ≤203） |
| ⑰ | `thincoder/docs/cli/design/ACP-CLIENT.md` §2.1 / §2.4 | 方法表加 `session/rewind` 一行；排队归属一句 | 文档面 |
| ⑱ | `thincoder/docs/core/design/SESSION.md` §6.27 | 补「rewind 截断点 = `storeFrom`；两线重建；索引剪枝」一段 | 文档面 |
| ⑲ | `thincoder/docs/batches/<A2 批>.test.mjs`（新增，零留存） | G21–G27（§7） | 实测 444（零留存、无硬限），收口删除 |
| ⑳ | `thincoder-core/session-lifecycle.mjs`（403） | `stripTruncatedToolArgs` 前加 `export `（步骤 4 的消毒复用；函数体零改） | 净 0（⇒ 403） |

零改动：`thincoder-cli/src/acp/transport.mjs`（默认排队，不进白名单）· `thincoder-cli/src/acp/handlers-session.mjs`（478，零加行）· `thincoder-cli/src/tui/cmd-undo.mjs`（代码零改；语义增量见 §2.2 偏离①）· `thincoder-core/agent/helpers.mjs`（复用 `toolTouchPaths`）· `thincoder-core/session.mjs`。

**`suspension.mjs` 不再零改动**（清理批 #106）：窗内到达的用户轮 `session/prompt` 的 `turnId` 经 `submit(input, opts)` 压进条目、`runTurn(item)` 读出并传 `execTurn`（+6 行）；丢它 ⇒ 该回合无键可铸、写入并入上一键，且宿主对该 turnId 的回退回 `-32602`。

### 4.3 体量与拆分

- **外仓 500 行硬限**：`handlers-session.mjs`（477）只加 prompt 透传（≤489）；两个新 handler 落新档 `handlers-session-meta.mjs`（~115）——不在原档追加（否则 547 越限）。
- **本仓 >800 名单**（`thincoder_kernel.dart` · `chat_session.dart` · `chat_screen.dart` · `chat_history_view.dart` · `user_message_bubble.dart` · `workspace.dart` · `sidebar.dart` · `workbench.dart` · 测试档）：本批只行级新增，**不动结构**；触发 = 独立拆分批。各档缝候选（行级，可检查）：
  - `thincoder_kernel.dart` — 适配档 §5.2 `:335`（续拆裁定 = 不续拆）+ 会话面缝候选（适配档 `:1668`：`send` / `_deliver` / `_beginTurn` / `_endTurn` / `cancel` 段 `:427-550` + 队列状态与 `_drain`）。本批 +175 后按该行再评估（该行住适配档，由父侧文档层修正，见 §4.1 ㉑）。
  - `chat_session.dart` — 适配档 §5.2 `:331`：Facets（`:329`）/ Projections（`:510`）/ Commands（`:920`）段。
  - `chat_screen.dart` — 适配档 §5.2 `:332`：`_ChatScreenState`（`:182`）之后的私有构件族（`:903`–`:1231`）。
  - `workspace.dart` — 适配档 §5.2 `:334`：The IDE's windows（`:727`）/ SSH hosts（`:1281`）/ Color theme（`:1858`）段。
  - `chat_history_view.dart` — 适配档 `:2316` 登记的「会话列渲染段 / 历史载入段」；段界按顶层类界：主渲染段 `_ChatHistoryViewState` `:88`–`:2655` 前，`:2655` 起的私有构件族（`_JumpToBottomButton` / 选择代理 / `_LiveItem` / 渲染件族）可整段出档。
  - `user_message_bubble.dart` — 适配档无登记（本批入名单）；顶层类界三族：`UserMessageBubble` `:34` / `UserMessageViewer` `:302` / 渲染件族 `:417`–`:1013`（`_Collapsed` / `_MessageShape` / `UserMessageEditMorph`）。
  - `workbench.dart` — 适配档无登记（本批入名单）：`Workbench` `:159` + `_WorkbenchState` `:232`–`:4450` 为一段，尾段 `:4450` 起（`_IdeNoFolderChat` / `_EmptyWorkspace` / `_SessionTerminalTasks`）可出档。
  - `sidebar.dart` — 适配档无登记、本设计未读该档：缝沿由拆分批按档内顶层类界勘定（本批只加 2–6 行调用点，不动结构）。
  - `test/kernel/thincoder_kernel_test.dart` — 适配档 §5.2 `:339` → 适配档 §15.4 的四组拆法（connection / session ids / locator / the registered kernel 各自成档；组起点按 §15.4 登记值，拆分批勘定）。
- **>500 且 <800**：`agent_kernel.dart`（481 → ≤515）入 >500 层，按既有立场（只跟 >800）不立缝；`kernel_types.dart`（615 → ≤669）同上；`thincoder_mock.dart`（668 → ≤703）同上。

## 5. 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D-SG1 | 重命名走 `session/set_title`；回退走 `session/revert`（带 `dryRun`）；`session/prompt` 增可选 `turnId` | 命名沿用 ACP `set_*` 家族（`set_mode` / `set_config_option`）；回合 id 必须由发起方给，核才知道「哪个宿主回合」。被否：`session/rename`（与 `renameSlot` 同名概念但 ACP 面无此惯例）；被否：把标题塞进 `set_config_option`（title 不是 configOption，会污染全量投影） |
| D-SG2 | 回合标识 = `{key, ordinal}`：prompt 给 key，`execTurn` 单点取 ordinal；自动轮继承上一 key | `execTurn` 覆盖用户回合 / 消化轮 / 唤醒轮三条起轮径（`session.mjs:88-114`），一处即可；宿主 auto 轮 id 无内核映射，继承键让「从该回合起」自然包含其后的自动轮。被否：用 `agent._currentTurn`（是 LLM 循环轮号，非回合）；被否：宿主维护「行号 ↔ 条数」映射（第二来源） |
| D-SG3 | 写后哈希 = sha256(写后内容)；routed 写用请求内容、本地写读回原始字节；超限 / 读不出 ⇒ `after = null` | F2.4 的判据是「内容与内核记录的写后值不符」，sha256 是内容本身；mtime 会被编辑器触碰误判。routed 写（`fs/write_text_file`）的内容核侧已知 ⇒ 不读回，消除时序不确定（§10 U1 的另一半）；本地写读回是唯一可得路径。被否：mtime；被否：不记写后值（无法判「回合后被改过」） |
| D-SG4 | 逐文件分组：最新条目的 `after` 校验现状、最旧条目的 `backup` 作为恢复值；组间按最新 `seq` 降序；逐文件失败隔离 | 同文件多次写时，恢复值必须取范围内最旧那份，才等于「回合前内容」；校验必须取最新那份，才等于「内核最后写成的样子」。被否：逐条逆序恢复（中间态校验会与用户改动混淆，且同文件重复写回） |
| D-SG5 | 确认框展示内核 `dryRun` 计划；执行后展示实际结果 | F2.6 要列「文件数 + 文件清单」，只有内核知道回合范围内到底改了哪些（含已被宿主「保留」的同回合文件）；宿主 pending 列表会少列 ⇒ 弹窗说谎。被否：用宿主 `_pendingEdits` 当计划 |
| D-SG6 | 自动轮（消化 / 唤醒）不单独成为回退单位，归属其前的 prompt 回合 | 桌面自动轮 id（`auto:<n>`）由宿主铸、核不知；继承键使「从该回合起」语义完整。被否：自动轮各自成键（需要新协议帧携带 ordinal，且与 Claude 的单口径不一致） |
| D-SG7 | 快照路径面扩到 `toolTouchPaths`，并收窄到 `FILE_MUTATORS` | `apply_patch` / 批量 `edit` 是多文件写入，现实现不入栈 ⇒ 回退漏文件；触达面是核内单源谓词。收窄避免 `file_ops` 等非内容写工具被意外纳入。被否：维持 `args.path`（A3 之外的整类写入不可回退） |
| D-SG8 | 手改标题粘住 = `agent.title` 同拍赋值 + 宿主自动标题器对 thincoder 关闭 | 核 `ensureSessionTitle` 以 `agent.title` 非空短路（`generate-title.mjs:131`）；宿主 titler 在 `canRename` 为真时会跑（`workspace.dart:2642-2652`）⇒ 不关就有两个写者。被否：让宿主 titler 继续跑并在内核侧丢弃（多一次 LLM 调用，且两处「谁赢」无单源） |
| D-SG9 | 未打开会话改名走目录短命连接（`RenamesStoredSessions`）；`_names` 只留给无此能力的内核 | F1.2 要求终端 `session list` 与桌面同值：只存宿主 `_names`（`workspace.dart:1716-1718`）终端永远看不到。短命连接 = 既有 `delete` 同法（`thincoder_catalog.dart:52-69`）。被否：打开会话再改（用户改的是列表项，不该拉起进程） |
| D-SG10 | 两个新方法**排队**（不进豁免白名单） | ACP-CLIENT §3.1 的三条豁免判据（`:96-98`）都不覆盖「写会话元数据 / 写工作区文件」；排队同时避免了改名与回合尾整档 save 的交错（mtime 门会把它变成可见失败）。代价：运行中会话的改名在回合结束生效（F1.1 只要求「不打断回合」）；客户端后置态保证发送点在队列空闲时（§3.5），60s 只兜病理竞态。被否：加白名单 |
| D-SG11 | 跳过 / 无法回退 / 失败的条目**保留在栈里**，只有成功恢复的文件出栈 | F2.4/F2.5 要求「如实列出、不假装成功」；保留让用户修好现场（关闭文件、撤销自己的改动）后可重试，与 `/undo` 失败路径同法（`cmd-undo.mjs:63-65` 只在成功后 splice）。被否：一律出栈（失败即永久丢失） |
| D-SG12 | 结果面 = 结果对话框 + 会话内一条摘要 `NoticeItem`（文案 owner = 宿主，§9 的 `revertSummary*` 三键）+ `ChangesReverted` 事件（仅 `outcome.files` 非空时发；全跳过 / 全失败不发，宿主待处理清单保留） | 清单可能长（超框仍可回看）；`ChangesReverted` 清空待处理清单是既有宿主语义（`transcript.dart:172-173`），但盘面未恢复时清空会让「保留可重试」失去可见面（D-SG11）。被否：只留 notice（长清单难读）；被否：只弹窗（关掉即无痕） |
| D-SG13 | 「与终端 `/undo` 同一份快照」的口径 = **同一实现 / 同一模块**（进程内 `agent._undoStack`），不是跨进程共享对象 | 终端与桌面各自一个 `thincoder acp` 进程（每会话一进程），内存栈不可能共享；需求原文的落点是「不另建宿主快照」。被否：把栈落盘共享（新增持久化面，需求未要求且与逐出预算语义冲突） |
| D-SG14 | 运行中改名 = 后置态（`_titleTarget` / `_titleDeferred` / `_titleSending`；回合收尾发送；last-wins；迟到回报经下一次 `session/list` 自愈） | 排队写若发在回合在飞时，会排在 prompt 之后、超 60s 被桌面丢弃而核照常执行 ⇒ 假失败 + 标题分叉（A1 不成立）。被否：`set_title` 显式不设超时 + 可见等待态（写卡住永久占位，适配档 §24.1 D98 同判据；等待窗口无上界）；
被否：加 FIFO 豁免（写落在在飞回合里，与回合尾整档 save 交错）。`revert` 同判据：在飞时入口不可用 |
| D-SG15 | 回退投影携带 `sinceTurn`；`canPlanRevert` = 能力 × 空闲（`PlansReverts.canRevertNow`），不以宿主 pending 列表为门；「该回合有核内记录」由 dryRun 空计划回答 | 入口 ② 必须能落到「该回合起」（F2.1）；宿主 pending 会少列（D-SG5）。被否：以 `revertTurn != null` 为门（= 用宿主 pending 当真值源）；被否：新增核侧只读「有没有改动」查询（多一条协议面，空计划探测已足够） |
| D-SG16 | 逐出账 = `Map<path, highestEvictedOrdinal>`（按路径 + 回合下界）；回合索引 50 键最旧先出；键逐出 ⇒ 该键回退未知回合；apply 后空键 = 空计划；无前键 ⇒ 铸 `p<n>` | 按键记账漏「只出现在后续回合、且已被逐出」的路径（查询跨键）；其余三条是 F2.5「如实报」与「不假装成功」的边界。被否：按键记 `lost` 列表（跨键漏报） |
| D-SG17 | routed 写的写后值 = 请求内容哈希（不读回）；本地写仍读回 | `fs/write_text_file` 的内容核侧已知，读回引入时序不确定（§10 U1 的另一半）；本地写读回是唯一可得路径。被否：一律读回（routed 半边悬在未验证时序上） |
| D-SG18 | 接受 `/undo` 粒度与深度变化（单步 = 单路径；预算按触达路径数消耗） | 条目形状变化是 F2.1/F2.4 的前置；漏整类写入比深度缩短更坏；逐出如实报。被否：按工具调用分组回退（改 `/undo` 语义，另立） |
| D-SG19 | `session/rewind {sessionId, turnId}` → `{}`；默认排队、不进白名单 | 方法只是截断对话（不改消息），名字取 `rewind`（与宿主接口 `RewindsConversation` 同词）；`turnId` = A1 回合键，是核内唯一的回合身份。被否：`session/edit_message`（语义超界）；被否：带 `index / turns`（宿主 transcript 坐标，核不知也不应知） |
| D-SG20 | 截断点 = 记录存储的绝对位次 `turn.storeFrom`（起轮时 `_recordStore.total()`；未绑定 = `_fullHistory.length`） | 该位次在 `run` 之前取，用户消息还没入线 ⇒ 正好是其落点；存储是 append-only、位次单调，不受人读线 200 条窗口移动影响。被否：对象身份（降级会换对象）；被否：`_fullHistory` 下标（窗口会前移）；被否：按文本内容匹配（改文 / 降级会偏） |
| D-SG21 | 索引剪枝：移除 `firstOrdinal >= turn.firstOrdinal` 的键；条目保留；`_undoTurn = null`；继承源改读 `agent._undoTurn` | F3.4 原文：条目保留（前一回合的回退仍覆盖它们），只移除截断起点的键；清指针 + 改继承源防「rewind 与重发之间的自动轮并进更早回合」 |
| D-SG22 | 机器线 = 由人读线重建（`agent.history = full.map(stripTruncatedToolArgs)`） | 两线不等长且机器线会被压缩改形，按位切必漂；重建丢的 transient 注入每轮重发、压缩摘要下一次重跑。被否：按位切两线 |
| D-SG23 | rewind 的末尾即落盘（`persist()`，与回合尾同一个 `save`） | `truncate` 已改 sidecar；若 slot JSON 留旧值，用户重发前退出会让两侧对不上且 load 看到旧历史。额外一次写与本批 `set_title` 同法（活会话内的直接写路径） |
| D-SG24 | 拒绝面：`-32602 unknown turn` 与重放历史同码，一条 `rewindNotInThisRun` 提示；在飞单独 `-32002` + `rewindTurnInFlight` | 内核分不清「伪造的 id」与「上一进程的历史」——两者都是「不在本进程回合索引里」；F3.2 只要求一条提示。`canEditMessages` 保持接口判据（不改）——代价 = 重放历史的消息看起来可编辑，点下去才被拒（§10 U7）。被否：新增逐消息能力读面（新协议面，F3 未要求） |
| D-SG25 | 需求 F3.2 字面（重放历史「不可编辑」）vs 本设计（可点、点后被拒，D-SG24） | **偏离登记**：内核分不清伪造 id 与上一进程历史；F3.2 只要求一条提示 ⇒ 以「点击后拒绝」实现同一可感知结果。代价与出口 = §10 U7 |
| D-SG26 | 需求 F3.3 字面（「随下一回合存档写入槽」）vs 本设计（rewind 末尾即 `persist()`，D-SG23） | **偏离登记**：`truncate` 已改 sidecar，留旧 slot 会在退出时两侧对不上（load 见旧历史）；额外一次写 = 活会话内的直接写路径（与 `set_title` 同法）。失败面见 §3.1 |

## 6. 验收对照（回指需求档 A1–A9）

| # | 判据 | 本档落点 | 核侧机检（外仓 G13–G20） | 宿主侧机检（本仓） |
|---|---|---|---|---|
| A1 | 改标题后桌面与 `session/list` 同值；再跑一轮（触发自动标题）不变 | §2.1 / §3.1 / §3.5 / D-SG8 / D-SG9 | G19：槽文件 title + manifest 摘要 + `agent.title` 同拍；`ensureSessionTitle` 早退 | G1 / G1b（接线与后置态）；G2（自动标题器门：回合后再跑不覆盖）；G9（目录改名后 `sessionsIn` 读新标题） |
| A2 | 空白标题被拒：值保持、界面有提示 | §9 / §4.1 ⑩ | G19：空白 / 超 80 ⇒ `-32602`、槽未变 | G3（字段校验、不调 `rename`）；G4（`-32602` ⇒ error notice、原值保持） |
| A3 | 非 Git 临时目录三文件（写 / 改 / 删）一回合内 ⇒ 回退后内容与存在性复原 | §2.4 / §3.2 / D-SG4 | G14：真临时目录 + `undoApply` 后逐文件断言（内容 / 删除 / 恢复） | G5（dryRun → 确认 → apply 接线；`sinceTurn` 透传） |
| A4 | 回合后被用户改过的文件 ⇒ 列为跳过、内容保持用户值 | §2.4 第 4 步 / D-SG3 | G15：`after` 不符 ⇒ `skipped: changed`；routed 写后值 = 请求内容哈希 | G6（结果映射；宿主不碰盘面） |
| A5 | 超限 / 逐出 ⇒ `unrevertable` 清单，其余正常回退 | §2.4 第 1–2 步 / D-SG11 | G16（oversize / 部分成功）；G17（逐出范围口径） | G7（两类 reason 映射；其余照常） |
| A6 | Claude 内核 rename / revert 既有用例全绿 | §3.3（不实现 `PlansReverts`；`undoAllChanges` 旧路径不变） | — | 跑 Claude 侧既有测试档；零改动 = 哨兵 |
| A7 | 回退确认弹窗取消 ⇒ 零文件改动 | §3.4 / §9 | G20：`dryRun` 零写入零出栈 | G10（取消 ⇒ 只发 `dryRun:true`、盘面哈希不变） |
| A8 | rewind：同一会话发 3 条（每轮改一个文件）⇒ 编辑第 2 条并重发 ⇒ 对话只剩第 1 条 + 新第 2 条；三个文件内容不变；终端重新 load 后看到截断后的历史 | §2.5 / §3.1 / §3.4 / D-SG20–D-SG23 | G22（两线 + 存储截断）、G23（索引剪枝）、G25（handler + persist） | T1（请求形状与 `turnId`）、T3（stop → rewind → 成功才 send）；文件不变 = 核侧断言盘面哈希不变 |
| A9 | rewind 拒绝面：编辑一条重放历史的消息 ⇒ 界面一条提示、对话不变 | §3.3 / §9 / D-SG24 | G24（未知回合 / 缺 turnId / 截断点失配：零变更） | T2（`-32602` ⇒ 一条提示、返回 false、无新回合）、T4（mock 重放历史场景） |

## 7. 用例表

**宿主侧（本仓；G1–G12 + A2 的 T1–T5）**

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| G1 | 改名（开，队列空闲） | 假传输 + 已起会话；`rename('新名')` | 恰一条 `session/set_title {sessionId, title}`；成功后 `thread.title` 变；`pendingTitle == null` |
| G1b | 运行中改名（后置态） | `hold = Completer()`；起回合后 `rename('a')` 再 `rename('b')`；`agent.release()` 收尾 | 在飞期间零 `session/set_title`、`pendingTitle == 'b'`、行仍显示已确认标题；收尾后 settle ⇒ 恰一条、title = `'b'`、`pendingTitle == null`；另例 `titleError` ⇒ 一条 error notice、标题保持原值 |
| G2 | 标题器门 | thincoder 会话（`GeneratesTitles`）∥ Claude 会话；各走一次自动标题路径 | thincoder ⇒ 宿主自动标题器零调用（`ownsTitle` 真）；Claude ⇒ 照旧调用 |
| G3 | 空标题（字段） | 字段提交 `'   '` / 81 字符 | `onDone` 未被调用；字段仍开；提示文案在场 |
| G4 | 标题错误映射 | mock 对 `set_title` 回 `-32602` | 会话内一条 error `NoticeItem`；标题保持原值；`pendingTitle == null` |
| G5 | 三文件回退（宿主接线） | mock 脚本：dryRun 计划 = restore / restore / delete | 确认前只发生 `dryRun:true` 且 `params.sinceTurn` = 传入回合 id；确认后一条 `dryRun:false`（同 `sinceTurn`）；结果框按计划渲染 |
| G6 | 跳过映射 | mock 脚本：`skipped: [{reason: changed}]` | 结果框「跳过」组显示该项与 `changed` 文案；宿主对盘面零触碰 |
| G7 | 无法回退映射 | mock 脚本：`unrevertable: [{oversize}, {evicted}]` | 结果框「无法回退」组两类 reason 各一；`files` 照常显示 |
| G8 | 未知回合 | mock 回 `-32602 unknown turn` | 一条 error notice；无结果框、无 `ChangesReverted` |
| G9 | 闭会话改名 | `ThincoderCatalog.rename(record, 'x')` | 短命连接一条 `session/set_title`；`sessionsIn` 读到新标题 |
| G10 | 取消 | 计划 → 取消 | 只发生 `dryRun:true`；盘面零改动 |
| G11 | 部分成功映射 | mock 脚本：`files` 一条 + `failed` 一条 | 结果框「恢复」「失败」两组各一；失败文件可再计划（核侧条目仍在栈，D-SG11） |
| G12 | 宿主投影 | 假内核 `PlansReverts`（`canRevertNow` 真 / 假）∥ 非该接口 | `canPlanRevert` = 能力 × 空闲（与宿主 pending 列表无关：无 pending 仍真）；`revertPlan('t1')` 透传 `sinceTurn`；非接口 ⇒ 走 `undoAllChanges` 旧径；在飞 ⇒ 两处入口禁用 + `revertTurnInFlight` tooltip；空计划 ⇒ `revertNothingToRevert` |
| T1 | rewind 接线 | mock 脚本：`session/rewind` 成功；`kernel.rewind(itemId: 't-2', index: 3, turns: 2, lastSeen: 't-3')` | 恰一条 `session/rewind`，`params` = `{sessionId, turnId: 't-2'}`（无 `index / turns / lastSeen`）；返回 `true`；零 `session/prompt` |
| T2 | 拒绝映射 | mock 回 `-32602 unknown turn` | 返回 `false`；会话内一条 `rewindNotInThisRun`；标题 / 对话项不变；零 `session/prompt` |
| T3 | 编辑顺序 | 假内核（`RewindsConversation`）记录 `stop` / `rewind` / `send` 顺序；`rewind` 返回真 / 假两例 | 真 ⇒ `stop → rewind → send`；假 ⇒ `stop → rewind`、无 `send`；`rewind` 未完成前不发 `send` |
| T4 | 在飞拒绝 | mock 回 `-32002 turn in flight` | 返回 `false`；一条 `rewindTurnInFlight`；对话不变 |
| T5 | 排队项随截断丢弃 | hold 让 turn-1 在飞；`send('later', id:'turn-2')` 入队；`rewind('turn-1')` 成功 | 队列面板清空；release 后总计恰 1 条 `session/prompt`，无 `user: later` |

**核侧（外仓批次档，零留存；A1 的 G13–G20 + A2 的 G21–G27；真临时目录 + 假传输）**

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| G13 | 快照面 | `apply_patch` 多文件 patch / 批量 `edit` / `write` / `file_ops` | 每触达路径一条、去重、条数 = 文件数；`file_ops` 被 `FILE_MUTATORS` 过滤（零条）；条目字段齐（`seq / turn / ordinal / tool / path / displayPath / backup / oversize / timestamp / after`） |
| G14 | 计划与执行 | 真临时目录三写（创建 / 改 / 删）同回合；`undoPlan` → `undoApply` | `files` 三项 = restore / restore / delete；组间按最新 `seq` 降序；执行后逐文件断言内容与存在性复原 |
| G15 | 写后值 | ① 本地写后手改文件 ② routed 写（假 `fs/write_text_file`） | ① `skipped: changed`、盘面保持用户值；② `after.hash == sha256(请求 content)`（不读回也判得出）且计划通过校验 |
| G16 | 超限与部分成功 | oversize 占位一条；两文件中一路径不可写 | oversize ⇒ `unrevertable: oversize`；部分成功 ⇒ `files` 一条 / `failed` 一条；成功出栈、失败条目保留 |
| G17 | 逐出范围 | 路径只在后续回合首次出现且被逐出；查询起点在前一回合 / 在逐出序号之后 | 起点在前 ⇒ `unrevertable: evicted`；起点在后 ⇒ 正常 `restore` |
| G18 | 索引边界（三判据） | ① 键被逐出而条目仍在 ② apply 后键空 ③ 无 `turnId` 且无上一键 | ① `-32602 unknown turn`；② 再回退得空计划（非错误）；③ 铸 `p<n>` 键、条目归属该键 |
| G19 | 标题写面 | `set_title` 成功 / 空白 / 超 80；`agent.title` 已设后再跑一轮 | 成功 ⇒ 槽文件 title + manifest 摘要 + `agent.title` 同拍；空白 / 超 80 ⇒ `-32602`、槽未变；`MAX_TITLE_LENGTH` 单源；`ensureSessionTitle` 早退（不再写第二次） |
| G20 | 回退错误面与 dryRun | 未知会话 / 未知回合 / 缺 `sinceTurn` / 无 key；`dryRun` | 前三条 `-32602`、无 key `-32000`；`dryRun` ⇒ 零写入零出栈（盘面哈希与栈长度不变） |
| G21 | 存储截断 | 6 条消息写满 2 个段（段大小可注入）；`truncate(2)` / `truncate(0)` / `truncate(段边界)` | `total()` = n；后续段文件消失；界内末段只留 n 条；计数 / `firstUser` 重置；下次 `append` 从 n 起 |
| G22 | 对话截断 | 假 agent：3 个键的回合（第 2 回合起 4 条真实消息 + 机器线多 1 条 transient）+ 绑定 store；`rewindConversation(agent, turn2)` | `_fullHistory` / `agent.history` 都到第 2 回合用户消息之前；`history` = `_fullHistory` 逐条过 `stripTruncatedToolArgs`；store `total()` = 第 2 回合起点；盘面文件零触（哈希不变） |
| G23 | 索引与回退交互 | 同上；rewind 后 `findUndoTurn(turn2/turn3)`；`undoPlan(turn1)` | 两键均 `null`；`turn1` 的计划仍含第 2/3 回合的条目（ordinal ≥ turn1.firstOrdinal）；`_undoStack` 条数不变 |
| G24 | 拒绝面（零变更） | 未知键 / 缺 `turnId` / `storeFrom` 越界 / 未绑定且越界 | `-32602`；`_fullHistory` / `agent.history` / store `total()` / `_undoTurns` 四读数全不变 |
| G25 | ACP handler | 假传输：成功 / 未知会话 / 缺 turnId / 在飞（`busy` / `suspended`）/ 无 key | 成功 ⇒ `{}` 且 `save` 被调一次；未知会话 / 缺参 / 未知键 ⇒ `-32602`；在飞 ⇒ `-32002`；无 key ⇒ `-32000` |
| G26 | 继承源 | rewind 后不传 `turnId` 起一轮（自动轮） | 新键 `p<n>`；不并进前一个用户键；该轮写入归属新键 |
| G27 | 落盘失败 | 注入抛错的 `save`（`createAcpSession({save})`）；`session/rewind` 走成功路径 | `-32603 persist-failed`；`store.total()` / `_fullHistory` / `_undoTurns` 已按截断值变化、槽 JSON 保持旧值；随后一次 `saveSession` ⇒ 槽 JSON = 截断后历史（自愈）；同 `turnId` 重试 ⇒ `-32602` |

## 8. 边界

- 不做 fork（需求 §3）。
- **rewind 的边界**：不做文件回退（= F2）；不做消息级（非回合级）截断；不做自动轮编辑（自动轮无宿主 id，随其所属用户回合一起被截断）；不做跨进程实时同步（终端下一次 `load` 读到）；不改标题；不删除撤销栈条目（F3.4） |
- 不做宿主快照、不碰 Git（无提交 / stash / index）。
- 不做逐文件挑选回退；一次 = 某回合起的全量。
- 不可回退项（如实报，不假装）：单条 >10MB（oversize 占位）、已逐出、写后状态未知（读不出）、二进制文件（现有快照只存 utf8 文本，读不出即不入栈）。
- `file_ops` 的 move / rename 不入快照（不在 `FILE_MUTATORS`）；本批不扩——登记为后续判定项（见 §10）。
- 撤销栈随会话进程存活：进程释放 / 重启后栈为空，回退返回未知回合（与终端 `/undo` 同口径）。
- 回合在飞时回退入口不可用（两处入口同判据，§3.5 末条）；`/undo` 不受影响（终端面零改）。
- `/undo` 单步 = 单路径（多文件 `apply_patch` 需多步）；深度随 50 条 / 64MB 预算缩短，逐出如实报（§10 U6）。
- 标题等待态不跨 `_teardown`（关窗 / 切会话 / 进程重启即清）；超时后的迟到执行由下一次 `session/list` 刷新自愈，不主动轮询。
- 不改 Claude 内核行为；Codex 无该能力，入口不显示。
- 不做标题历史 / 撤销改名；不解决跨进程并发改名的冲突（`mtime-conflict` 如实报错，用户重试）。

## 9. UI / 交互决定（全部落地，无 open）

- **改名入口**：既有三处 inline 编辑（会话标题栏 `chat_screen.dart:457-468`、侧栏行 `sidebar.dart:914` / `:2938`、IDE 标签条 `ide_tab_bar.dart:694`）——不新增控件。
- **改名校验**：空白或 >80 字符 ⇒ 字段不关闭、行内红字提示（`renameTitleRequired` / `renameTitleTooLong`）；内核 / 目录写失败 ⇒ 标题保持原值 + 会话内 `NoticeItem(error)`（关闭会话时用 `showIdeDialog` 单行说明）。
- **运行中改名**：允许提交；标题在回合结束生效（后置态，§3.5）。字段关闭，行仍显示**已确认**标题；等待期间再开字段预填 `pendingTitle`（last-wins 目标）。失败 / 超时 ⇒ 标题保持原值 + 会话内 `NoticeItem(error)`（关闭会话时 `showIdeDialog` 单行说明）；核已迟到执行的情形由下一次列表刷新自愈。
- **回退入口**：① ActivityStrip 的「Undo all」（`activity_strip.dart:494-504`）——起点 = 首个待处理回合的 `turnId`（`revertTurn`），仅当 `canPlanRevert` 且有待处理项时出现；② 用户消息右键「Revert files from this turn…」——该回合 id，仅当 `canPlanRevert`。
  `canPlanRevert` = 内核为 `PlansReverts` 且 `canRevertNow`（无在飞回合且有可用连接），**不以宿主 pending 列表为门**；「该回合有没有改动」由 dryRun 回答：空计划 ⇒ `revertNothingToRevert` 提示。在飞时：ActivityStrip 的「Undo all」灰显 + tooltip `revertTurnInFlight`；右键项的禁用形态 = **不出现**（该项本就只在 `canPlanRevert` 时构建；菜单面无 tooltip，不改 `ide_menu.dart`）。
  用户消息项 id = 回合 id（`chat_session.dart:201-202` 的 `_transcript.indexOf(turnId)` 即此约定）。两处同一确认流程。
- **确认框**：标题「Revert files from this turn?」；正文 = 文件数（`revertFileCount`，ICU 复数 =0 / =1 / other）+ 文件清单（超 12 行滚动，`displayPath`）+ 提示「回合之后的改动将丢弃」+ 跳过 / 无法回退分组（reason 用 `revertReason*`）；按钮 = Cancel（默认）/ Revert。
- **结果框**：恢复 / 跳过 / 无法回退 / 失败四组（`revertGroup*`）计数与清单；同类计数为零不显示该组。
- **会话内记录**：一条 `NoticeItem` 摘要 = 3 条 ICU 复数片段（`revertSummaryRestored` / `revertSummarySkipped` / `revertSummaryUnrevertable`）以 ` · ` 连接；`ChangesReverted` 清空待处理清单。
- **Claude 内核**：两处入口保持今天的行为（`undoAllChanges` 直呼，无确认框；改名同今天）——A6 非回归。
- **编辑已发消息**：入口 = 既有分支（`chat_history_view.dart:1845-1849`：`canEditMessages` 真 ⇒ `ChatComposer`）；`ThincoderKernel` 实现 `RewindsConversation` 后 thincoder 面即可编辑，**不加逐消息能力细分**（D-SG24）。提交 = 宿主 `editMessage`（`chat_session.dart:1212-1240`）：`stop()` → `rewind` → 成功才 `send`。
- **rewind 拒绝面**：内核拒绝 ⇒ 会话内一条 `NoticeItem`（`rewindNotInThisRun` / `rewindTurnInFlight`），对话不变；无对话框、无重试按钮。重放历史的消息看起来可编辑，失败时才说明（代价见 §10 U7）。
- **rewind 等待态**：不新增；rewind 与重发在同一次动作内完成（队列空闲、一次往返）。连接超时（60s）⇒ error 提示、对话不变。
- **内核提示的语言**：内核提示 v1 只听英文——内核无 locale 通道，`ThincoderKernel` 取 `englishLocalizations.*`；两源档的 zh 值只在 UI 面消费，内核提示是文案键表的例外。

**文案键（23 键；两源档 + 三生成档同拍；下表值 = 两源档现值，UI 照抄）**

| 键 | 用途 | en | zh |
|---|---|---|---|
| `renameTitleRequired` | 字段校验：空 | A title is required | 请填写标题 |
| `renameTitleTooLong` | 字段校验：>80 | A title is at most 80 characters | 标题最多 80 个字符 |
| `revertFromTurn` | 入口 / 右键菜单项 | Revert files from this turn… | 从这个回合起回退文件… |
| `revertTitle` | 确认框标题 | Revert files from this turn? | 从这个回合起回退文件？ |
| `revertWarning` | 确认框提示 | Changes made after this turn will be lost. | 回合之后的改动将丢弃。 |
| `revertConfirm` | 确认按钮（取消复用 `commonCancel`） | Revert | 回退 |
| `revertDone` | 结果框标题 | Revert complete | 回退完成 |
| `revertFileCount` | 确认框文件计数（ICU 复数 =0 / =1 / other） | `{count, plural, =0{No files} =1{1 file} other{{count} files}}` | `{count, plural, =0{没有文件} =1{1 个文件} other{{count} 个文件}}` |
| `revertGroupRestored` | 组名：恢复 | Restored | 恢复 |
| `revertGroupSkipped` | 组名：跳过 | Skipped | 跳过 |
| `revertUnrevertable` | 组名：无法回退 | Cannot be reverted | 无法回退 |
| `revertGroupFailed` | 组名：失败 | Failed | 失败 |
| `revertReasonChanged` | reason：changed | Changed after the turn | 回合之后改过 |
| `revertReasonOversize` | reason：oversize | Too large to revert | 文件过大 |
| `revertReasonEvicted` | reason：evicted | No longer kept | 已不再保留 |
| `revertReasonAfterUnknown` | reason：after-unknown | Cannot tell if it changed | 无法确认是否改过 |
| `revertSummaryRestored` | ICU 复数摘要：恢复 | `{count, plural, =0{Reverted no files} =1{Reverted 1 file} other{Reverted {count} files}}` | `{count, plural, =0{没有回退文件} =1{回退了 1 个文件} other{回退了 {count} 个文件}}` |
| `revertSummarySkipped` | ICU 复数摘要：跳过 | `{count, plural, =0{Skipped no files} =1{Skipped 1 file} other{Skipped {count} files}}` | `{count, plural, =0{没有跳过文件} =1{跳过了 1 个文件} other{跳过了 {count} 个文件}}` |
| `revertSummaryUnrevertable` | ICU 复数摘要：无法回退 | `{count, plural, =0{No files are unrevertable} =1{1 file cannot be reverted} other{{count} files cannot be reverted}}` | `{count, plural, =0{没有无法回退的文件} =1{1 个文件无法回退} other{{count} 个文件无法回退}}` |
| `revertNothingToRevert` | 空计划提示 | Nothing to revert. | 无可回退。 |
| `revertTurnInFlight` | 在飞禁用 tooltip | Unavailable while a turn is running | 回合进行中，暂时不能回退 |
| `rewindNotInThisRun` | rewind 拒绝：非本进程回合 / 重放历史 | This message cannot be edited — only messages sent in this run can be. | 这条消息不能编辑——只能编辑本次运行中发送的消息 |
| `rewindTurnInFlight` | rewind 拒绝：在飞 | Cannot edit while a turn is running | 回合进行中，暂时不能编辑 |

## 10. 未核实与判定条件

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U1 | 本地写路径的「写后读回」是否读到新内容 | routed 半边本批已闭合（写后值 = 请求内容哈希，§3.2）；本地写仍读回：`writeText` 写盘后 `_reload`（`lib/ide/ide_kernel_files.dart:91-108`，代码实读），全量落盘时序未真机验证 | A3 走查取三文件回执：本地 `after` 若仍是旧内容 ⇒ 误报 `changed`；修法 = 本地分支同样用工具入参（`write` / `edit` 的请求内容）算哈希（另立） |
| U2 | 非桌面客户端不传 `turnId` 时的回退 | 核铸 `p<n>`，标准客户端不会调用 `session/revert` | 判定条件：出现第二个 ACP 客户端要回退 ⇒ 按其回合模型补映射（另立） |
| U3 | `file_ops` move / rename 的回退 | 不入快照（`FILE_MUTATORS` 不含） | 判定条件：现场出现「移动后回退不完整」⇒ 扩快照面（需新增「删除新路径 + 恢复旧路径」动作，另立） |
| U4 | 大文件（>10MB）回退 | 现有双上界：oversize 占位，不可回退 | 维持（需求 F2.5 明写）；判定条件：产品要求可回退大档 ⇒ 备份改落盘（另立） |
| U5 | 标题 80 上限的来源 | TUI `/rename` 硬编码 80（`cmd-session.mjs:19`）；宿主 `cleanAgentTitle` 也按 80 截断（`test/workspace/agent_title_test.dart:35-37`）；核 `generateTitle` 规范是 ≤40 | 取 80 = 用户手改上限（与终端一致），不是自动标题规范；单源常量住 `session-rename.mjs` |
| U6 | `/undo` 深度随条目形状缩短 | 一次多文件 patch = N 条（50 条 / 64MB 同倍消耗）；批量写入的回合可一次吃掉大量预算；本批**接受**（§2.2 偏离①） | 判定条件：现场出现「大 patch 后历史被逐出」的实际损失 ⇒ 评估按工具调用分组预算（另立）；逐出已如实报 `unrevertable: evicted`（G17） |
| U7 | 重放历史的消息看起来可编辑（D-SG24 的代价） | `canEditMessages` 只看接口；无逐消息能力读面 | 判定条件：用户反馈「分不清哪些消息可编辑」⇒ 加能力读面（核侧枚举本进程回合 id，另立） |
| U8 | 界外回合的 rewind（起点早于人读线窗口 200 条） | 设计允许：截库后由 `store.tail(window)` 重载人读线；未真机验证 | 实现首轮真机取读数；若重载不稳 ⇒ 降为「界外拒绝」（`-32602`，如实提示） |
| U9 | `truncate` 与 `catchUp`（degraded 缺口）的交互 | 存储降级时 `total()` 与实际内容已有缺口；截断以 `total()` 为界 | 实现时确认 `truncate` 重置 `degraded` 并在下次保存时 `catchUp` 无洞；若冲突 ⇒ 截断前先 `catchUp` |
| U10 | 截断后机器线由人读线重建的代价 | transient 注入丢弃（每轮重发）、压缩摘要丢弃（下次重跑）；长会话的一次额外压缩未实测 | 验收时记一次长会话读数；若不可接受 ⇒ 保留压缩摘要的重建变体（另立） |
| U11 | 排队边界 | 宿主 transcript 由 `Rewound` 截断；内核 `_queue` 由本批清空；宿主自己的草稿 / 未发消息不在此列 | 无待判（本批口径即边界定义） |
