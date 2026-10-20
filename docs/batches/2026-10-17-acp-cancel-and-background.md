# 2026-10-17 · acp-cancel-and-background
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-17 · 来源 = 独立评审（advisor reviewId f50d2068）🔴#1 + 两次真机探针复现 + 用户 2026-10-17 反馈「后台子代理曾被杀」。
> 台账 = #25（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-17）

### 来源

- **独立评审**（advisor，reviewId `f50d2068`）判 `changes-required`，🔴#1 = ACP 入站串行把 `session/cancel` 关在回合外。
- **我自己的两次真机探针**（不是转述评审结论）：起真 `thincoder acp` + 真模型，回合在飞时发 `session/cancel`：
  - 探针 A：cancel 在 13.8s 发出，prompt 直到 59.0s 才回 `{"stopReason":"end_turn"}`（回合照跑完），cancel 应答在 prompt 应答**之后 1ms** 才到。
  - 探针 B：迟到 cancel 打到 `runNormal` 已重建的新 controller 上 ⇒ 下一条 prompt **1064ms** 就回 `{"stopReason":"cancelled"}`（模型根本没跑）。
- **用户现场反馈**（2026-10-17 20:52）：后台子代理**确实**被杀过——批 8 只堵住"子代理"一族，"后台 bash / browser / advisor / consult"四族仍无状态帧。

### 本批要解决的三件事（都在 thincoder 仓的 CLI 面）

1. **取消真的能停**：`session/cancel` / `session/close` / `session/list` 不再排在回合 handler 之后（入站 FIFO 豁免），且迟到 cancel 不得污染下一条 prompt。
2. **挂起窗中止回 `cancelled`**：窗内跑的 prompt 被中止时不得回 `-32603`（设计 W3 的应答形状），桌面侧不得弹协议错误。
3. **后台工作可见**：`bash` / `browser` / `advisor` / `consult` 四族的"在做/做完"以 `_meta` 帧报到客户端，让客户端**有据可依地不关会话**（批 8 的 D64 判据缺这一项，导致切走视图 ⇒ 释放进程 ⇒ 任务被杀）。

### 硬约束（定界）

- **实现面全在 thincoder 仓**：`thincoder-cli/src/acp/{transport,handlers-session,handlers-slots,suspension,session}.mjs` + 新帧的发射点（`thincoder-core/agent-tools/{bash,browser,advisor,consult}-async.mjs` 的登记池）+ 用例档。
- **桌面侧（消费新帧、扩 `_canClose`）不在本批**：`thincoder_kernel.dart` 当前 **1148/1148 行**（设计 §5.2 上界满格，不续拆）⇒ 桌面消费必须先拆档，归**批 10**。
- **协议面零破坏**：新帧只走 `session_info_update._meta`（`docs/cli/design/ACP-CLIENT.md` §12 既有扩展载波，不认它的客户端忽略即合规）；`initialize` 形状、方法面、版本号零动。
- **本档位置说明**：本批实现面在 `D:\baocode\thincoder`（独立 git 仓），批次档按本会话语义落在 baocode 仓；该仓自身的用例档仍按其惯例落 `thincoder/docs/batches/`。这属机制限制（批次档跨仓创建被拒是正确行为），不是把别人的事记进本仓。

### 与既有条目的关系

- 台账 **#25**（取消 FIFO · 归批）· **#26**（窗中止回 cancelled）· **#27**（`_teardown` 收在飞回合，批 10）· **#28**（mock 串行档）· **#33**（后台任务帧）。
- 评审 🟡#5（mock 保真度）与本批绑定：**没有串行档**，本轮修的取消路径测不出来。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（autoApprove 窄豁免修正）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

实现面 = `D:\baocode\thincoder`（独立仓；下表的 file:line 均相对该仓根）。需求档 = `thincoder/docs/cli/requirements/ACP-CLIENT.md`（主 agent 笔，本批只读）。

| # | 需求 | 判定句 |
|---|---|---|
| 1 | **F9** 取消与关闭不被回合阻塞 | R-A6.1 / R-A6.2 / R-A6.3 / R-A6.4 |
| 2 | **F10** 后台工作可见（`_meta` 扩展帧） | R-A7.1 / R-A7.2 / R-A7.3 |
| 3 | **N9** 取消时延 ≤2s | N9 |

**明确不在本批**：桌面侧消费新帧 / 扩 `_canClose`（`thincoder_kernel.dart` 1148/1148 行顶格 ⇒ 归批 10）；`_teardown` 收在飞回合（台账 #27，批 10）；需求档改写（主 agent 笔）；`session/delete` / `load` / `resume` / `set_*` 的 FIFO 豁免（语义上必须留队，设计 §3.1 已给判据）。

### 设计档落点

`thincoder/docs/cli/design/ACP-CLIENT.md`（675 → 787 行）：

- §2.1 方法表（list / cancel / close 三行标「入站豁免」；cancel 标「回合定向」）。
- §3.1 FIFO 豁免（三方法白名单 + 三条判据 + `session/new` 顺序依赖论证 + 行为变化 + 并发安全 + N9 时延 + 实现位点）。
- §3.2 cancel 回合定向（`busy` + controller 绑定；空闲零动作；窗收束后新 prompt 走普通队列）。
- §3.5 模块表补 `acp/background`（非 handler）。
- §9 关键决策 D24–D27。
- §11.3 一处一致性收正（「先 cancel」→ `close()`，见「发现」）。
- §12.8 窗内中止应答形状（**唯一折算点**）+ 用例口径 W1–W8 → W1–W10。
- §12.9 后台工作扩展契约（形状 / 配对 / 幂等 / 重放 / 观察者缝 / 四族起止时点 / AC + 验收回指表）。

### 行级任务表（22 行）

| # | 动作 | 落点（file:line） | 期望结果 | 回指 |
|---|---|---|---|---|
| 1 | transport：`handleLine` 解析一次 + 白名单分派 | `thincoder-cli/src/acp/transport.mjs:68-93` | `session/cancel` / `close` / `list` 不进 `inbound` 链（读到即 `processLine`）；其余行原样串行 | R-A6.1 |
| 2 | transport：`start()` 注入缝 | `transport.mjs:139-151` | `start({ input, installSignalHandlers })`；缺省 = `process.stdin` + 装信号（今日行为零变） | 用例前提 |
| 3 | session：cancel 回合定向 | `thincoder-cli/src/acp/session.mjs:137-141` | `closed` 零动作；`busy` ⇒ abort 当前 controller；窗在未收束 ⇒ `window.cancel()`；否则零动作 | R-A6.1 / .2 / .4 |
| 4 | session：controller 先换新、`busy` 后落 | `session.mjs:110-114` | 顺序固定（同一同步段，等价）；`busy` 真 ⇒ controller 必属在飞回合 | R-A6.2 |
| 5 | session：`execTurn` 不取收束中的窗信号 | `session.mjs:66-75` | `window.ending` ⇒ 用 per-turn controller（新回合不继承中止信号） | R-A6.2 |
| 6 | session：`run()` 窗收束后走普通队列 | `session.mjs:128-136` | `window && !ended && !ending` 才 submit；否则 `runNormal` | R-A6.2 |
| 7 | suspension：`ending` 只读位 | `thincoder-cli/src/acp/suspension.mjs:145-151` | `cancel()` 有在飞才置位；`close()` 无条件置位 | R-A6.2 |
| 8 | suspension：窗内用户轮 abort 不外抛 | `suspension.mjs:99-112` | abort 径吞下、让核循环顶的 `abortSignal.aborted` 检查收窗（残余可应答） | R-A6.3 |
| 9 | suspension：`done` 交回原始错误 | `suspension.mjs:132-143` | `item.done({ ok:false, error })`；`submit` 以 `res.error` 拒绝，`TurnFailedError` 只作兜底 | R-A6.3 |
| 10 | session：窗内残余 = cancel 形 | `session.mjs:46-56`（`trackWindow`） | 中止径残余以 `name:"AbortError"` 拒绝（原为布尔 ⇒ `TurnFailedError`） | R-A6.3 |
| 11 | 核：观察者两助手 | `thincoder-core/agent-tools/async-settle.mjs:109-133` 一带（新增） | `backgroundStart` / `backgroundEnd`：读 `carrierField("_bgObserver")`；缺省零行为；`_bgStarted` / `_bgEnded` 幂等；try/catch | R-A7.1 / .3 |
| 12 | 核：bash 起 / 止 | `thincoder-core/agent-tools/bash-async.mjs:185`（起）· `:193`（止） | 入池即 start；`finalizeBgEntry` 即 end（正常 / 超时 / 杀 / 丢弃 / spawn 失败五径） | R-A7.1 |
| 13 | 核：browser 起 / 止 | `thincoder-core/agent-tools/browser-async.mjs:126`（起）· `:135`（止） | 入池即 start；`finalizeBrowserEntry` 即 end | R-A7.1 |
| 14 | 核：advisor 起 / 止 | `thincoder-core/agent-tools/advisor-async.mjs:458`（起）· `:253-269`（排队取消止）· `async-settle.mjs:308-311`（settle 尾）· `async-discard.mjs:114-121`（清池止） | 入池即 start（含 queued）；三 end 径同一守卫 | R-A7.1 |
| 15 | 核：consult 起 / 止 | `thincoder-core/agent-tools/consult.mjs:432`（起）· `:152`（settle 止）· `:390-396`（清池止） | 会话入池即 start；normal / `consult_stop` / cleanup 各一条 end | R-A7.1 |
| 16 | ACP：帧单源 | 新建 `thincoder-cli/src/acp/background.mjs` | 键 `thincoder.dev/background` + 观察者工厂（`closed` 丢弃、try/catch、无值键缺席） | R-A7.1 / .2 / .3 |
| 17 | ACP：装观察者 | `thincoder-cli/src/acp/session.mjs:28-40`（`createAcpSession`） | `agent._bgObserver = ...`（会话 id / notify 闭包；`closed` 后丢弃） | R-A7.1 |
| 18 | 用例 U1：真 readline 取消 | 新建 `thincoder/docs/batches/2026-10-17-acp-cancel-and-background.test.mjs` | 直驱 `start({ input })`：cancel 通知在 prompt 未收束时即生效（假 run 的 signal 收到 abort）、prompt 回 `cancelled`、下一条 prompt 回 `end_turn` | R-A6.1 / .2 / N9 |
| 19 | 用例 U2：窗内中止形状 | 同上 | 窗内用户轮中止 ⇒ `cancelled`；窗内模型报错 ⇒ `-32603`；残余输入必应答（不挂死） | R-A6.3 |
| 20 | 用例 U3：后台帧配对 | 同上 | 四族 start/end 配对 + 重复 end 幂等 + 无后台零帧 + 无观察者零行为 + `load` 零帧 | R-A7.1 / .2 / .3 |
| 21 | 回归：既有窗用例 | `thincoder/docs/batches/2026-10-17-acp-suspension.test.mjs`（W1–W10 不改） | 改后全绿（窗行为零回归） | N7 |
| 22 | 文档同步 | 契约档 §2.1 / §3.1 / §3.2 / §3.5 / §9 / §11.3 / §12.8 / §12.9 | 回指表 8 行在位；§12.8 用例口径 W1–W10 | 回指 |

### 受影响文件（现状行数 → 预期；相对 thincoder 仓根）

| 文件 | 现状 | 预期 |
|---|---|---|
| `thincoder-cli/src/acp/transport.mjs` | 155 | ≈185（+30） |
| `thincoder-cli/src/acp/session.mjs` | 148 | ≈168（+20） |
| `thincoder-cli/src/acp/suspension.mjs` | 169 | ≈185（+16） |
| `thincoder-cli/src/acp/background.mjs` | — | 新建 ≈45 |
| `thincoder-core/agent-tools/async-settle.mjs` | 329 | ≈355（+26） |
| `thincoder-core/agent-tools/async-discard.mjs` | 255 | 256（+1） |
| `thincoder-core/agent-tools/bash-async.mjs` | 281 | 282（+1） |
| `thincoder-core/agent-tools/browser-async.mjs` | 198 | 199（+1） |
| `thincoder-core/agent-tools/advisor-async.mjs` | 499 | 500（+1，触 500 上界——见「登记」） |
| `thincoder-core/agent-tools/consult.mjs` | 471 | ≈473（+2） |
| `thincoder-cli/src/acp/handlers-session.mjs` | 429 | 429（0——唯一折算点不动） |
| `thincoder-cli/src/acp/bridge.mjs` | 461 | 461（0） |
| `thincoder/docs/batches/2026-10-17-acp-cancel-and-background.test.mjs` | — | 新建 ≈380 |
| `thincoder/docs/cli/design/ACP-CLIENT.md` | 675 | 787（本设计轮已落） |

### 验收对照（一条不落）

| 需求行 | 验收方式 | 判据 |
|---|---|---|
| R-A6.1 | 单测 U1 + 收口真机 | 回合在飞写 cancel ⇒ 该请求 ≤2s 被处理；prompt 收 `cancelled` |
| R-A6.2 | 单测 U1 | 取消后下一条 prompt 回 `end_turn`（不立即 `cancelled`） |
| R-A6.3 | 单测 U2 | 窗内中止 ⇒ `cancelled`；窗内模型 / 工具报错 ⇒ `-32603`；残余不挂死 |
| R-A6.4 | 单测 U1/U2 + 代码判据 | 空闲 cancel 零动作；abort 仍传到 provider 的 `AbortSignal` |
| R-A7.1 | 单测 U3 | 四族各恰一条 start + 一条 end（同 `(kind,id)`）；无后台零帧 |
| R-A7.2 | 单测 U3 | 帧不含任务正文；`detail` ≤80 字符；`initialize` / 版本零动 |
| R-A7.3 | 单测 U3 | 无观察者零行为；发帧抛错不破任务收束 |
| N9 | 收口真机（父侧） | cancel 写入 → 回合收束 ≤2s |

### 关键决策

- **D24** 入站 FIFO 豁免 = 显式三方法白名单 + 三条判据（默认留队）。
- **D25** cancel = 回合定向（`busy` + controller 绑定；空闲零动作；排队 prompt 不传染）。
- **D26** 窗内中止 ⇒ `cancelled` 的唯一折算点 = `session/prompt` 的错误映射；会话层只归一「因」（`AbortError` 形态）。
- **D27** 后台帧 = 中性观察者缝（`_bgObserver`）+ `_meta["thincoder.dev/background"]`；核零 ACP 依赖。
- **设计补判（需求未定处）**：advisor **排队条目也算「活的后台工作」**（start 于入池、不于实际起跑）——否则客户端会关掉一个还在排队的评审；不改变 R-A7.1 语义，只定「开始」的观测点。

### 待实现期确认（显式未定，不得假装已定）

1. `bash` 杀树（win32 `taskkill /T /F`）后子进程**是否必达 `close`**——实现期用真子进程验证；不达则按 R-A7.3（缺 end 不阻塞），配对守卫不破。
2. `browser` 的 `runAction` 在中止径是否**恒达 `.finally`**（设计按「动作 promise 恒达」假设）——实现期用例验证。
3. `advisor` 的 `.finally` 是否覆盖所有已启动评审的收束（含 abort）——按代码读为真；实现期用 `settleAsyncEntry` 直驱用例验证。
4. `consult` 的 `run.length === 0`（`selectConsultModels` 过滤到空）是否可达——若可达，start 无 end；实现期加 `run.length > 0` 守卫或立即补 end。
5. `settleAsyncEntry` / `discardRole` 对 `_bgStarted` 缺席条目的**零行为**——回归用例验证。
6. `transport.start()` 注入签名（`{ input, installSignalHandlers }`）——实现期定形；默认值必须保持今日行为。

### 发现 / 登记（逐条）

- **登记（跨批 · 档位）**：`advisor-async.mjs` 现 499 行，本批 +1 触及 **500 上界** ⇒ 下一触碰先拆档（queued 队列 helpers 外提为 `advisor-queue.mjs`），否则必破 500 档。
- **登记（本批不做）**：窗内某一用户轮以**非中止**错误抛穿 ⇒ 核 `done` 以拒绝收场、其后窗内输入失去应答（既有边；设计 §12.8 已登记，本批只覆盖中止径）。
- **观察（他档 · 契约一致性）**：`thincoder/docs/cli/design/ACP-PROTOCOL-COMPLIANCE.md:94/:98` 仍写「同 id 在存 ⇒ 旧实例 `cancel()`」；实装（批 8 起）为 `close()`。非本批契约档，仅报。
- **观察（核设计档）**：`thincoder/docs/core/design/AGENT-LOOP-ASYNC-POOL.md:442/:1073` 仍把 ACP 列作 `suspDriven !== true` 面（批 8 §5 #5/#7 已登，父侧处置）。
- **观察（一致性修已落）**：契约档 §11.3「先 cancel」→ `close()`（与实装一致；本批 cancel 语义收窄后该措辞会误导实现者）。
- **需求面（只报不改）**：R-A7.1 未定「排队条目算不算开始」与「id 类型」——设计已补判（见「关键决策」），需求档由主 agent 决定是否补一句。

### 评审 1 轮落地（2026-10-17 · 15 条全接受 · 对「设计档落点」的增量）

设计档 = `thincoder/docs/cli/design/ACP-CLIENT.md`（788 → 819 行，本轮 +31）。逐号落点：

- #1 → §3.2.1 AC-A6-2 扩为三方法同一 harness（cancel / close / list + 队中 prompt + close ⇒ `-32602`）。
- #2 → §3.2.1 新增 AC-A6-4（空闲 cancel = 空操作）。
- #3 → §3.2「close 与回合收尾的并发不变量」（`closed` 后 finally 存档跳过；close 不删持久槽档）。
- #4 → §12.9 `detail` 定形（输入快照 / 单行化 / ≤80 码点 / 逐族；browser 的 `subject` 给出定义）+ AC-A7-3 补断言。
- #5 → §12.9 观察者缝参数契约表（两助手 + `observer(frame)`）。
- #6 → §12.9 四项「待实现期确认」各带判定方式（另两项仍住本档）。
- #7 → §3.5 受影响文件指针（→ 本档「受影响文件」表）+ 阈值读数；§7.2 悬空回指改指 §12.5。
- #8 → §11 开头作用域收窄（受影响文件表指针在 §3.5；AC 块住 §12.5 / §12.9）。
- #9 → §12 开头补需求档 §5 例外通道回指。
- #10 → 三处修订式表述改目标态（见下）。
- #11 → §3.1 / §3.2 / §12.9 补先例三坐标（§3.2 明写「无先例——本批新立」）。
- #12 → F9 验收块迁 §3.2.1；§12.9 只留 F10；回指表随迁为索引（§2「设计档落点」的 §12.9 一行按此调整）。
- #13 → §3.2 补跨轮 cancel 已接受边界。
- #14 → §3.1 判据①「删除」限定为持久槽档删除（`session/delete`）。
- #15 → §12.9 补「`id` 恒字符串、与 §12.2 整数 `id` 分属不同键」。

**修订式表述清理（评审 #10 · 历史只在本段）**：§3.2「顺序收正 / 语义等价」（原表述）⇒ 目标态「先换 controller 后落 busy（同一同步段）」；
§12.8「原为布尔」⇒「原始错误随 `done` 交回」；「原为 `TurnFailedError`」⇒「以 `AbortError` 形态拒绝」。设计档规范面只留目标态。

**本轮机检读数（父侧复跑可核）**：设计档无新增单行 >300 字符（既有 2 行超宽不在本轮改动面）；`node scripts/doc-check.mjs --root .` 锚闸 repo 全域红（267 悬空，含本档既有同类代码锚）——非本批闸，仅报。

**行数口径补正**：上句「788 → 819」= 编辑器显示行；与「设计档落点」表同口径（`wc -l`）= **787 → 818**，本轮增量 +31 不变。

### 修正轮 1 落地（2026-10-19 · 评审第 2 轮 1–9、11 全接受）

设计档 = thincoder 仓 `docs/cli/design/ACP-CLIENT.md`（1118 → 1144 行，`wc -l` 实测）。逐号落点：

- **#1** → §12.8 点名三个改动点：`suspension.mjs:110`（`done` 载荷 = `{ok, error}`）· `:139`（`submit` 以 `res.error` 拒绝，`TurnFailedError` 仅兜底）· `session.mjs:48-51`（窗关残余以 `AbortError` 形拒绝）；AC-A6-3 补「窗关残余逐条回 `cancelled`」断言。
- **#2** → §3.2 新增 `window.ending` 置位判据（仅实际 abort：`cancel()` 仅 `inflight > 0`、`close()` 无条件）+ 与 AC-A6-4 的关系（空闲取消不改门控）。
- **#3** → 坐标重钉：`handlers-session.mjs:390`（AbortError→cancelled）· `:404-421`（`session/close`）；§3.2 / §3.2.1 回指表 / §12.8 / N9 行同改。
- **#4** → §3.2「closed 后存档跳过」标为改动点（`session.mjs:82`）+ 新增 **AC-A6-5**（注入计数 `save`：close 在飞时回合收尾后调用次数不增）。
- **#5** → §3.5 恢复**逐文件受影响表**（13 行，`wc -l` 口径，2026-10-19 实测）；读数统一：`acp.mjs` **184**（原 160）· `handlers-session.mjs` **474**（原 465/475 之歧）· `handlers-slots.mjs` 241 · `client-caps.mjs` 88 · `read-data.mjs` 146；表注标明 §15.9 两张表 = F11 批日期化快照。
- **#6** → `advisor-async.mjs` 实际增量 = **+2 语句（499 → 501，越 500）** ⇒ §3.5 给拆分计划：`dequeueAdvisor`（`:299-306`）与 `refreshAdvisorQueuedTokens`（`:311-322`）外提 `advisor-queue.mjs`（新档 ≈31 行），再导出保持公开面零变，拆后 ≈476；§12.9「落点（代码）」同步。
- **#7** → §3.1 行为变化 ① 标为**有意接受** + **重启条件**（出现排队期取消需求 ⇒ 立批扩 cancel 语义）+ 新增 **AC-A6-6**（背靠背 / 排队期取消两条断言）。
- **#8** → §3.2 顺序表述改为「**先落 `busy`、后换 controller**」（`session.mjs:112-114`，与实装一致；同步段内两序观察等价）。
- **#9** → §12.9「`id` / `role` 域（防混读）」补 `role` 跨键语义（本键 = 评审类型；§12.2 = relay 角色名）。
- **#11** → §3.1 补**批次级调查证据行**（沿用 §11.1 锁定基线；两条新增依赖均在其内；无新增相关公开源）。
- #10 由父代理改需求档 R-A7.2（设计档零改）。

**§2 上文更正（以本段为准）**：

- 「受影响文件」表行数已过时 ⇒ 现行读数 = 设计档 §3.5 表（`wc -l`，2026-10-19 实测）。
- 行级任务表 **#4** 的动作改为「先落 `busy`、后换 controller」（与设计档 §3.2 一致）。
- 新增行：**#23** 核：advisor 拆档 —— 新建 `thincoder-core/agent-tools/advisor-queue.mjs`，`advisor-async.mjs` 再导出；判据 = 拆后 <500 且公开面零变；回指 R-A7.1。
- 设计档行数：**675 → 1144**（上文「675 → 787」以本段实测为准）。

**本轮机检读数（父侧可复跑）**：设计档 1144 行（`wc -l`）；行宽 0 命中（300 字符阈；`doc_check` 全域报 0 行宽命中，锚命中 597 条均为 thincoder 仓既有、本档零新增 ✗）。**零代码改动**。

**坐标补正（同轮 · 以本段为准；行级任务表计数 = 23 行）**：下表行号均为 thincoder 仓 `wc -l` 口径下的现行行号（2026-10-19 实测）。

- 行 #3（session：cancel 回合定向）：`session.mjs:138-142`。判据终形 = `closed` ⇒ 零动作 → `busy` ⇒ abort 当前 controller → 窗在且未收束 ⇒ `window.cancel()` → 其余 ⇒ 零动作。
- 行 #4（session：回合收尾顺序）：`session.mjs:112-114`；动作 = **先落 `busy`、后换 controller**（与实装一致）。
- 行 #5（session：执行器不取收束中的窗信号）：`session.mjs:69`（取信号点）。
- 行 #6（session：`run()` 窗收束后走普通队列）：`session.mjs:129-137`；判据 = `window && !window.ended && !window.ending` 才 submit。
- 行 #9（suspension：`done` 交回原始错误）：`suspension.mjs:110`（`done` 载荷）+ `:134-143`（`submit` 以 `res.error` 拒绝，`TurnFailedError` 兜底）。
- 行 #10（session：窗内残余 = cancel 形）：`session.mjs:48-51`（`reason === "aborted"` 径逐条 `done({ok:false, error:<AbortError>})`）。
- 行 #23（advisor 拆档 · 本轮新增）：新建 `thincoder-core/agent-tools/advisor-queue.mjs`（`dequeueAdvisor` / `refreshAdvisorQueuedTokens`），`advisor-async.mjs` 再导出；拆后 ≈476（<500），公开面零变。

### 交付后坐标重钉（2026-10-19 · eng-designer · 按 §5 实测）

设计档 `docs/cli/design/ACP-CLIENT.md`（1144 → 1143 行）：§3.1 / §3.2 / §3.2.1 / §3.5 / §12.9 的代码锚点全量重钉；§3.5 受影响文件表改为「本批前 → 实交（`wc -l`）→ 增量」，补 `acp/background.mjs`（46）· `advisor-queue.mjs`（37）两行。31 个坐标端点逐条实读，均落到所述符号。

读数（本机 `wc -l` 复测）：transport 175 · session 180 · suspension 196 · background 46 · handlers-session 474 · `acp.mjs` 184 · async-settle 384 · async-discard 256 · bash-async 286 · browser-async 203 · advisor-async 483 · advisor-queue 37 · consult 479 · 用例档 703 —— 全部代码档 <500。

与 §5 的两处读数差（实测为准；§5 不改）：`advisor-async.mjs` 483（§5 写 484）· 用例档 703（§5 写 705）。口径 = `wc -l`（换行符数）；同一脚本复测 transport / session / suspension / consult 等档与 §5 一致。

发现（未改——超出本轮指定范围，建议收口轮一并重钉）：§12.8「窗内中止的应答形状」的锚点已被本批改动漂移——`suspension.mjs:110` → `:124`（`done` 载荷）、`:139` → `:156-157`（`submit` 拒绝映射）、`session.mjs:48-51` → `:57-61`（残余取消形）、`suspension.mjs:99-112` → `:110-117`（不外抛的 `throw e` 在 `:117`）；同段 `:748` 引批内用例档（该档随批删后成死指针）。

### 修正轮 2 落地（2026-10-19 · 用户裁定「按A修」= autoApprove 窄豁免）

设计档 = thincoder 仓 `docs/cli/design/ACP-CLIENT.md`（**零代码**）。范围 = §3.1 / §3.2.1，另两处一致性同步（§2.1 方法表 · §9 D24）。

- **§3.1 豁免面**：标题改「三方法 + 审批短路位 `autoApprove`」；入白名单条件 = `session/set_config_option` ∧ `params.configId === "autoApprove"`（实现位点 = `transport.mjs:30` 白名单 Set、`:106` 判据处窄判入）。
- **§3.1 判据①**：改「模型 / 模式 / 其余 configId 的配置 / 持久槽档删除不豁免；`configId === "autoApprove"` 的 `set_config_option` 为唯一例外」；判据②补「只改审批请求面」；判据③补 `set_config_option` 的 id 来源。
- **§3.1 新增「`autoApprove` 可豁免的理由」**：只翻审批短路位（下一次工具调用问不问），不改回合输入 / 模型 / 模式 / 会话；用户点击即表达意图，同回合生效是开关语义；提前生效不扩大授权面。
- **§3.1 留队清单**：load / resume / delete / set_mode / **其余 configId 的 `set_config_option`**。
- **§3.1 行为变化 ⑤**：连发 load + autoApprove 写入 ⇒ 可能先到 `-32602 unknown session`（与 ② 同族；正解 = 等 load 应答再写）。
- **§3.2.1 新增 AC-A6-7（可机检）**：在飞写 `{configId:"autoApprove", value:true}` ⇒ 写入响应 + `config_option_update` 先于 prompt 收束；假 agent `autoApprove === true`（「后续工具不再弹审批」单测面只经该状态间接验证）；负向 `{configId:"mode", value:"plan"}` 仍留队。
- **一致性同步（非新增语义）**：§2.1 `session/set_config_option` 行补「`autoApprove` 入站豁免」标记；§9 D24 的「三方法白名单」表述扩为「三控制方法 + `autoApprove` 审批短路位」。

**发现（需求面 · 只报不改）**：需求档 `docs/cli/requirements/ACP-CLIENT.md:100` R-A6.1 只列三方法，无 autoApprove 窄豁免条文——窄豁免依据 = 用户裁定（本档 §4）。需求档是否补句由主 agent 决定。

**机检读数**：设计档 `wc -l` = **1152**（read / 编辑器行 1153；上一轮编辑器口径 1143 ⇒ +10 行）；本轮改动行宽 max **224** 字符（全档 4 行 >300 均为既有表行，不在本轮改动面）；AC-A6-1…7 连续无缺；**零代码**。

**D8 清理（同轮 · §3.1）**：行为变化 ②/③ 删两处历史括注（`docs/cli/design/ACP-CLIENT.md:106`「原来会排在 load 后取消它」· `:107`「原来排在 new 后可见」）——规范面只留目标态，语义零改。

**行数不变**：两次 1 对 1 替换不影响行数；设计档 `wc -l` 仍 = 1152（read / 编辑器行 1153）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

批 9 设计评审（对象：批 9 设计 ACP 取消不被回合阻塞 + 后台工作扩展契约；范围 = docs/cli/design/ACP-CLIENT.md 与 docs/cli/requirements/ACP-CLIENT.md，全文已读）

评审限制（明写）：本仓无 AGENTS.md / 无项目标准档 / 无文档地图 ⇒ 方法学合规与文档归属两项按降级口径判（仅按评审准则 + 两档内部自洽性）；设计档内所有代码锚点（行号 / 符号）因评审范围限于两档，一律未核验（unverified），不作事实断言。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | 验收标准 | 🟡 | 三方法白名单只有 cancel 一路有用例：AC-A6-2 只写 "prompt 在飞时写 `session/cancel`（通知形）⇒ 假 run 的 `signal` 在它自然完成前收到 abort"（design:737），AC-A6-1 亦只测 cancel；需求 R-A6.1 三方法同列（requirements:99 "`session/cancel` / `session/close` / `session/list` 的处理**不得排在在飞回合的 `session/prompt` handler 之后**"）⇒ close / list 的豁免无验收；设计自己登记的可观测行为（design:102 "`prompt` 在队 + 同会话 `close` 先到 ⇒ 该 prompt 回 `-32602 unknown session`"）落地后无断言钉住 | 在 AC-A6-2 同一 harness 上补：回合在飞时写 `session/close` ⇒ prompt 收束 `cancelled` 且 close 的 `{}` 先回；回合在飞时写 `session/list` ⇒ 应答先于 prompt resolve；`prompt` 在队 + `close` ⇒ `-32602` |
| 2 | 验收标准 | 🟡 | R-A6.4 后半句「空闲态取消为空操作」（requirements:105 "取消仍**真实中止**运行中的工具与模型调用（既有 `AbortController` 语义零改）；空闲态取消为空操作"）无验收；而这正是本批 controller 换序（design:123 "（`session.mjs:110-114` 顺序收正；同一同步段，语义等价）"）最容易回归的行为 | 加一条单测 AC：无在飞回合时写 `session/cancel` ⇒ 零会话状态变化（下一条 prompt 回 `end_turn`、不发 `cancelled`） |
| 3 | 清晰度 / 可行性 | 🟡 | 出队 `close` 与在飞 prompt 的收尾存档之间的并发不变量未写：close 语义 = "先 abort 在飞回合再删除 session"（design:42），而回合 finally 恒 "每回合末 `save(agent)` 持久化存档"（design:120）；认领释放后该存档可能经 activeSlot 早退写回同进程活动槽——§3.3 已把同一失败模式写成硬警告（design:139 "否则下次保存经 activeSlot 早退分支落回同进程活动槽 → 两会话写同一槽"） | 补一条不变量：会话 `closed` 后 finally 存档跳过（或认领保持到该回合收束），并明确 close 不删持久槽档 |
| 4 | 清晰度 | 🟡 | `detail` 规则未定形：design:707 "**短标签，不是任务正文**（R-A7.2）：bash = 命令头；browser = `action + subject`" 的 `subject` 无定义；≤80 字符的截断算法（切 / 省略号 / 是否单行化）未写；需求 R-A7.2「帧不携带任务正文」（requirements:112）在 AC 里无断言 | 定形 `detail` 的取值来源（输入快照、非输出）与截断 / 单行化规则，并把「不含任务正文 / 长度 ≤80」写进 AC-A7-3 |
| 5 | 清晰度 | 🟡 | 观察者缝只给函数名（design:716 "核 `async-settle.mjs` 新增两助手 `backgroundStart(carrier, task, frame)` / `backgroundEnd(carrier, task)`"），`task` 与 `frame` 的分工、kind / id / detail 由谁构造、观察者如何取 `notify` / `sessionId` / `closed` 均未定形（design:718 仅 "（`acp/background.mjs` = 键 / 形状单源）"） | 把两助手的参数契约与观察者签名（接收 frame 对象；闭包持有 notify / sessionId / closed）列成一张小表 |
| 6 | 验收标准 | 🟡 | R-A7.1「开始与结束各发一条」的成立依赖四项未决读数（design:731 "**待实现期确认（显式未定，不得假装已定）**"），当前无法判定 AC-A7-1（design:743）的「进程收束 ⇒ 恰一条 `end`」在四族各终态径可达 | 四项各自落一条先红后绿断言，或逐项明写「该径不发 end、由 R-A7.3 兜底」，使 AC-A7-1 的边界可判定 |
| 7 | 受影响文件体量标注 / 方法学 | 🟡 | 无受影响文件表：§3.5 明写 "受影响文件与逐档读数 = 一次性材料，不入本档。"（design:175），但 §7.2 仍回指 "受影响文件（当前行数 / 增量）= 本档 §3.5"（design:357）——指针悬空；本批要动的 `session.mjs` / `transport.mjs` / `suspension.mjs` / 核侧 `async-settle.mjs` 与四族发射点均无行数 / 预期增量 ⇒ 文件档（>500 预警 / >800 必拆）与函数档阈无法核对 | 给出逐文件当前行数 + 预期增量（或 ≤±N）并留指针到承载材料；同时删掉 §7.2 指向 §3.5 的悬空回指 |
| 8 | 文档归属 | 🟡 | design:421 "**受影响文件表 / AC 与用例表** = 一次性材料，不入本档" 与本档实际保留的 AC 块（§12.5 AC-862-*、§12.9 AC-A6-* / AC-A7-*）并存，读者无法判定 AC 归本档还是归一次性材料 | 把该句作用域收窄为「§11 本节」，或改为「AC 与受影响文件表住批档 / 一次性材料，本节只引用」，二者取一 |
| 9 | 文档归属 | 🟡 | 需求档 §5 的 `_meta` 例外通道只点名 R-A5.11（requirements:144 "**`_meta` 扩展契约面 = 例外通道**——R-A5.11 结构化子代理事件"），而本批 F10 / R-A7.1 与 §12.8 的回合边界帧同用该通道——机制未变（标准变体 + `_meta`，非机制级冲突），但实例枚举已陈旧，按字面读 §5 会否掉 §12.9 | 在 §5 例外通道句补上 (a) §12.7 归属帧标 / §12.8 回合帧 / (b) 本批 R-A7 后台帧，或改为「实例清单见 R-A5.11 / R-A7」 |
| 10 | 文档卫生 | 🟡 | 规范面留有修订式表述（历史应归批档 / changelog）：design:123「（`session.mjs:110-114` 顺序收正；同一同步段，语义等价）」、design:677「（原为布尔）」、design:678「（原为 `TurnFailedError`）」 | 三处改为目标态直述（只写「收尾先换 controller 后落 busy」「被中止的错误以 AbortError 形态交回」），前后对比移入批档 §2 |
| 11 | 最近先例 | 🟡 | 仅 §3.1（design:93 反向 RPC 应答先例）与 §12.9（design:689 与 §12.8 同形）带先例行，且两处坐标不全（§3.1 无对应设计档小节 / 先例批；§12.9 无实现坐标）；§3.2 的回合定向 cancel 既无先例行，也无「无先例」显式声明 | §3.2 补一行先例坐标或明写「无先例——本批新立」+ 由；§3.1 / §12.9 补齐（实现坐标 ∥ 设计档小节 ∥ 先例批）三坐标 |
| 12 | 验收标准（组织） | 🟡 | F9 的验收块落在 §12.9（F10 专节）内（design:733 "**验收（F9 · 单测 + 收口真机）**"），而 §3.1 又把 N9 的读数回指 §12.9（design:105 "≤2s 的读数由收口真机探针给（回指见 §12.9）"）——按 F9 找验收会落在后台工作节 | 把 F9 验收移到 §3.1 / §3.2 之后（或单列验收小节），§12.9 只留 F10；回指表保留为索引 |
| 13 | 可行性（边界登记） | 🔵 | R-A6.2「不污染后续回合」的成立边界未写：协议无回合 id，若 stale cancel 在下一轮已开跑后到达仍会中止该轮（design:126 只覆盖 "`busy` 落之后到达的 cancel 一律空操作"） | 加一句已接受边界：cancel 只能对准当下在飞回合，跨轮到达即作用于新一轮 |
| 14 | 清晰度 | 🔵 | §3.1 判据①「槽装载与删除一律不豁免」（design:94）与 `close` 的「删除 session」（design:42，指内存会话）用词重叠，易读成 close 也违反判据① | 把判据①的「删除」限定为「持久槽档删除（`session/delete`）」，并注 close 的内存移除按判据② 入白名单 |
| 15 | 清晰度 | 🔵 | 两个 `_meta` 键的 `id` 域不同：子代理 `id` = integer（design:579），后台 `id` = string（design:705）——同一客户端易混读 | §12.9 加一句「`id` 恒字符串，与 §12.2 的整数 `id` 分属不同键，客户端不得跨键比较」 |

VERDICT: pass
计数：🔴 0 · 🟡 12 · 🔵 3

### 轮次 2（评审子代理）

**批 9 设计重评（入站 FIFO 豁免 / cancel 回合定向 / 后台工作扩展契约）** — 复评范围：`docs/cli/design/ACP-CLIENT.md` 全文 + `docs/cli/requirements/ACP-CLIENT.md` 全文；对设计内代码锚点与阈值读数做了实核抽检（transport / session / suspension / handlers-session / advisor-async / browser-async / bash-async / consult / async-settle / async-discard / session-slots）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | 验收 / 需求覆盖 | 🟡 | R-A6.3「窗关 ⇒ cancelled」缺可验断言，且机制描述指错改点：`docs/cli/design/ACP-CLIENT.md:728` 称 `item.done({ok:false, error})`，实核 `thincoder-cli/src/acp/suspension.mjs:110` 只传 `{ ok }`；`:729` 称 `session.mjs:49` 以 `name:"AbortError"` 拒绝，实为 `suspension.mjs:139` 铸 `TurnFailedError`、`session.mjs:50` 只传 `{ok:false}` ⇒ 该径今日回 `-32603`（`handlers-session.mjs:390` 只认 AbortError）；AC-A6-3（`:146`）对残余输入只要求「必应答」 | 在 §12.8 点名改点（`suspension.mjs` 的 `done` 载荷 + `submit` 的拒绝映射），并给残余输入补一条 `stopReason:"cancelled"` 断言 |
| 2 | 清晰度 | 🟡 | `window.ending` 置位时机未定形：`:127` 让 cancel 无条件调 `window.cancel()`（D59：inflight=0 零动作），`:135` 又说 `ending` 是 `suspension.mjs` 的「只读位」——若 inflight=0 也置位，则空闲窗取消改变门控（与 AC-A6-4 `:147`「零状态变化」相抵）；若只在实际 abort 时置位，需写明 | 定形置位判据（仅实际 abort 时置位），并说明与 AC-A6-4 的关系 |
| 3 | 清晰度（坐标） | 🟡 | 两处锚点不落到所述代码：`handlers-session.mjs:345`（`:155` / `:726`）实为 session/new 的 stale 处置，AbortError→cancelled 映射在 `thincoder-cli/src/acp/handlers-session.mjs:390`；`handlers-session.mjs:359-376`（`:131`）实为 session/new 的 catch/finally，`session/close` 在 `:404-421` | 重钉坐标，或按本档 §11 自己的口径改「按方法名定位」 |
| 4 | 清晰度（状态） | 🟡 | `:132` 把「finally 的 save 在 closed 后跳过」写成既有不变量，实核 `thincoder-cli/src/acp/session.mjs:82` 无条件 `save(agent)`；该跳过是 close 豁免 FIFO 后才可达的竞态，属本批改动，且无对应 AC | 标为改动项并补 AC（close 在飞 ⇒ 认领释放后不再写槽） |
| 5 | 受影响文件（判据 8） | 🟡 | `:209` 明确写「逐文件表 = 一次性材料（不入状态档）」⇒ 本批被改的 10 个源文件 + 新档 `acp/background.mjs` + 批内测试档全无「当前行数 → 增量」标注，仅剩 `:210` 一行阈值读数；读数本身亦自相矛盾：`:207` 写 `acp.mjs` 现 160 行，`:1041` 的实施后读数为 184；`:188` 的 `handlers-session.mjs` 465 与实核 475 不符 | 恢复逐文件表（当前行数 ∥ 增量），至少覆盖全部被改源文件与新测试档，并统一读数口径 |
| 6 | 受影响文件（阈值） | 🟡 | `:210` 的 `advisor-async.mjs` 499 → 500 只能容 +1 行，而 §12.9 要求在该档 `:458`（实核 `parent._asyncAdvisors.set(String(id), entry)`）加 start、在 `:253-269` 排队取消径加 end——两条新语句即越 500（导入可并入 `:66` 既有行，仍 +2）；同条又写「下一触碰先拆档」，而本批即该触碰 | 核实际增量；若越 500，按判据带拆分计划（或给出折行写法把增量压回 ≤500） |
| 7 | 范围 / 行为 | 🟡 | `:100` 接受「prompt + cancel 背靠背且 prompt 尚未开跑 ⇒ cancel 为空操作」——用户「停止」在排队期静默失效；需求档无条文授权，AC 亦不覆盖 | 记为登记项或补一条行为条款 / AC（含重启条件），让该接受有据 |
| 8 | 清晰度（状态） | 🔵 | `:125` 称「先换新 controller、后落 `busy`（`session.mjs:110-114`）」，实核 `thincoder-cli/src/acp/session.mjs:112-114` 是先 `busy = false` 再换 controller；同步段内两序等价，但描述与代码相反 | 改为「先落 busy、后换 controller」，或标明这是改动 |
| 9 | 契约清晰度 | 🔵 | 同一 `role` 键两族语义不同：`thincoder.dev/subagent` 的 `role` = relay 角色名（§12.2），`thincoder.dev/background` 的 `role` = 评审类型（`:758`）；`:765` 只对 `id` 给了跨键不可比声明 | 对 `role` 补同一句跨键语义提示 |
| 10 | 需求歧义 | 🔵 | R-A7.2「帧不携带任务正文」的读法只记在设计侧（`detail` = 输入快照、永不含输出）；bash 的 `detail` = 命令头可被读成「正文」 | 把该读法写进需求档 R-A7.2（或登记），免两档口径漂移 |
| 11 | 方法论（调查证据） | 🔵 | 调查证据是本档级的（§11.1 as-of 2026-09-18 / §15.1），本批新增面（`session/cancel` 通知形、`session_info_update` 承载体）无批次级 survey 行 | 补一行批次级调查记录（「无新增相关」也算记录） |

计数：🔴 0 · 🟡 7 · 🔵 4 ⇒ VERDICT: pass（裁决项 5 / 6 属文件尺寸债，按 R3 不升级；其余为可改进项）。

## §4 用户批准（主 agent）

**用户批准（2026-10-19 00:29）**：用户逐字「批准9实施」。实现面 = `thincoder` 仓；按 §2 的 23 行任务表；设计档 `docs/cli/design/ACP-CLIENT.md`（1144 行，修正轮 1 已落）；收口前须过 U1–U3 + W1–W10 回归与 lint，收口轮父侧跑真机探针（cancel ≤2s / 下一轮 `end_turn`）。

**用户裁定（2026-10-19 00:55）**：逐字「按A修」。方案 A = 仅 `configId === 'autoApprove'` 的 `session/set_config_option` 入 FIFO 豁免；其余 configId（`model` / `mode` / `thinkingLevel` 等）继续留队。理由 = autoApprove 只翻审批短路位，不改回合输入 / 模型 / 模式 / 会话；与批 6 §17.1-④「同一回合写 autoApprove」对齐。顺序：设计档 §3.1 / §3.2.1 先改 → `transport.mjs` + U1 用例 → 重跑 U1–U3 / W1–W10 / 真机探针 → 收口。复用批 9 designToken。

## §5 实施记录（eng-coder）

### 实施摘要（2026-10-19）
实现面 = `D:\baocode\thincoder`（独立仓；起点 `main` dd9f2e49 + 父侧两份未提交设计/需求改动——**本批零触碰**）。按 §2 的 23 行任务表逐行落地；设计档 = 规范源，本批未改设计/需求与 `handlers-session.mjs` / `bridge.mjs`（唯一折算点 `:390` 零动）。

| # | 条目 | 落点（实测行号） |
|---|---|---|
| ① | advisor 拆档（#23） | 新建 `thincoder-core/agent-tools/advisor-queue.mjs`（37 行；`dequeueAdvisor` / `refreshAdvisorQueuedTokens` 逐字迁出）；`advisor-async.mjs:67-70` import + 再导出，公开面零变（`tui/mouse.mjs:21` · `subagent-async.mjs:34` 未改）；499 → 483（+两处发射点 = 484，<500） |
| ② | transport FIFO 豁免（#1/#2） | `thincoder-cli/src/acp/transport.mjs:30`（白名单 Set）· `:81-116`（`handleLine` 解析一次 + 豁免即分派，其余仍 `inbound` 链）· `:154-168`（`start({ input, installSignalHandlers })`；缺省 = 今日行为） |
| ③ | session 回合定向 cancel（#3–#6/#10） | `session.mjs:161-171`（closed→busy→window→零动作）· `:153`（窗内门控含 `!ending`）· `:80-83`（`execTurn` 不取收束中的窗信号）· `:57-61`（窗关残余 `AbortError` / message `cancelled by client`）· `:98-102`（closed 后存档跳过）· `:49`（装观察者） |
| ③ | suspension 窗收束（#7–#9） | `suspension.mjs:41-48`（`ending` 位）· `:166-171`（`cancel()` 仅 `inflight>0` 置位）· `:172-176`（`close()` 无条件置位）· `:110-117`（窗自身中止吞下、非窗中止照旧上抛）· `:124`（`done` 带原始错误）· `:152-160`（`submit` 以 `res.error` 拒绝、`TurnFailedError` 兜底） |
| ④ | ACP 帧单源（#16） | 新建 `thincoder-cli/src/acp/background.mjs`（46 行；键 `thincoder.dev/background` + 观察者工厂：closed 丢弃 / try-catch / 无值键缺席 / id 恒字符串） |
| ④ | 核观察者缝（#11） | `async-settle.mjs:112-163`（`backgroundStart` / `backgroundEnd`；`carrierField(_bgObserver)`、`_bgStarted` 存 (kind,id)、`_bgEnded` 幂等、detail 单行化 + ≤80 码点）；`:365`（settle 公共尾 end） |
| ④ | 四族发射点（#12–#15） | bash 起 `bash-async.mjs:187` / 止 `:206`；browser 起 `browser-async.mjs:128` / 止 `:144`；advisor 起 `advisor-async.mjs:439` / 止（排队取消 `:271` · settle 尾 `async-settle.mjs:365` · 清池 `async-discard.mjs:119`）；consult 起 `consult.mjs:440` / 止（`sessionSettled` `:157`（早退之前）· 清池 `:397`） |
| ⑤ | 用例档（#18–#20） | 新建 `thincoder/docs/batches/2026-10-17-acp-cancel-and-background.test.mjs`（20 例：U1×6 / U2×3 / U3×11） |

### 读数（本机实测）
- `cd thincoder-cli && node --test ..\docs\batches\2026-10-17-acp-cancel-and-background.test.mjs ..\docs\batches\2026-10-17-acp-suspension.test.mjs` ⇒ **30/30 pass**（U1–U3 = 20 · W1–W10 = 10），duration ≈3.2s。
- `cd thincoder-cli && npm run lint` ⇒ `check-syntax: 127 file(s) OK`。
- core 不在 CLI lint 默认遍历面 ⇒ 补跑 8 档显式路径 `node scripts/check-syntax.mjs …` ⇒ `check-syntax: 8 file(s) OK`。
- 行数（`wc -l` 口径实测）：transport 175 · session 180 · suspension 196 · acp/background 46 · async-settle 384 · async-discard 256 · bash-async 286 · browser-async 203 · advisor-async 484 · advisor-queue 37 · consult 479 · 用例档 705 —— **全部代码档 <500**。

### 决策透明表
| 判断点 | 决定 | 依据 |
|---|---|---|
| 窗内中止的吞下范围 | 仅「AbortError ∧ 窗控制器已中止」吞下；非窗中止照旧上抛 | R-A6.3 的意图是让核循环顶的 `abortSignal.aborted` 收窗；不该改写窗内轮自身失败径（仍 -32603） |
| `_bgStarted` / `_bgEnded` 置位时序 | start：先置位后调观察者；end：先置位后调观察者 | 观察者抛错时守卫已在位 ⇒ 多径同达仍只一条（R-A7.3 与幂等同时成立） |
| detail 定形位置 | 核侧 `backgroundStart` 单点（单行化 + ≤80 码点） | ACP 观察者只做载波外壳；TUI/VSC 若装观察者也拿到合规 detail |
| consult 空 run | 不加 `run.length > 0` 守卫 | `selectConsultModels`：缺省/空数组 ⇒ 全池（已验非空池）；未知选择器 ⇒ error 返回不入池 ⇒ `run` 恒非空（用例直驱两条径） |
| 用例档体积 705 > 设计 ≈380 | 接受 | 用例为一次性材料（随批删），多出部分 = 待实现期确认的实测径（杀树/中止/三族清池/选择集） |

### 偏差 / 未做
- **待实现期确认 1**（bash 杀树是否必达 close）：真子进程长驻 → `killBgTask` ⇒ 恰一条 end（绿，实测 ~0.5s）。
- **待实现期确认 2**（browser 动作 promise 是否恒达 `.finally`）：起跑前 abort ⇒ 动作 promise 拒绝（因由 `cancelled`）⇒ `.finally` ⇒ 恰一条 end（绿）。**真「在飞浏览器动作 abort」需真浏览器本机环境，未做**——R-A7.3 兜底（缺 end 不阻塞）。
- **待实现期确认 3**（consult 空 run 可达性）：不可达（判据见上表）；两条边界径有用例（错误 ⇒ 零帧不入池；空数组 ⇒ 全池）。
- **待实现期确认 4/5/6**：advisor 三收束径各一条 end（绿）；`_bgStarted` 缺席零行为（绿）；`transport.start()` 签名定形（绿）。
- **设计档读数漂移（只报不改——eng-designer 笔）**：§3.5 预期值 vs 实测（transport ≈185/175 · session ≈171/180 · suspension ≈185/196 · async-settle ≈355/384 · consult ≈473/479 · 用例档 ≈380/705）；§3.1/§3.2/§3.2.1/§12.9 的代码锚点行号亦漂移（如 `transport.mjs:68-93` 实为 `:81-116`）。收口轮父侧重钉。
- **未采纳的防御建议（评审 blue #4）**：`runNormal` 排队任务体复查 `closed`——今日经 transport FIFO 不可达，避免无据改语义；记入交付报告供后续裁定。
- 需求档 R-A7.1 未定「排队条目算不算开始」与「id 类型」——实现按设计补判（advisor 排队条目 start 于入池；`id` 恒字符串），需求档由主 agent 决定是否补句。

### 审计 / 评审轮次与终态
- **内部 explore 分歧审计 1 轮**：FINDINGS(4) = 1 yellow（§5 未写——即本段）+ 3 blue（bash 杀树径 / browser 中止径 / consult 选择集无读数）。处置：yellow 本段落笔即结；3 blue 全部补用例并通过（见上「偏差 / 未做」）。
- **advisor 代码评审 1 轮**：verdict **pass**（0 red · 1 yellow advisory · 4 blue）→ **fix round 1**：blue #3 按建议改测试同步点（`flush()` → `until`，3 处）；yellow #5 补 consult「正常收齐」会话结果断言（`received`/`failed`/出池）。blue #1/#2 = 设计档读数漂移（报父侧）；blue #4 = 防御性建议未采纳（理由见上）。
- **终态 = `clean`**（无未处置 must-fix；30/30 测试 + lint 全绿）。

### 修正轮 3 实施记录（2026-10-19 · autoApprove 窄豁免 · 用户裁定「按A修」）

**交付摘要**：实现面 = `D:\baocode\thincoder`（独立仓）。只动两个档；设计档 / 需求档 / `handlers-session.mjs` / `bridge.mjs` 零触碰。

| 落点 | 改动 |
|---|---|
| `thincoder-cli/src/acp/transport.mjs:13-19` | 头部契约注释补窄豁免（审批短路位同回合生效） |
| `:35-40` | 新增谓词 `isInboundExempt`：三方法白名单，或 `set_config_option` 且 `configId === "autoApprove"` |
| `:117` | `handleLine` 判据改调该谓词（三方法语义零变；其余 configId 仍走 `inbound.then(...)`） |
| `:87-89` | EXCEPTION ② 注释同步 |
| `docs/batches/2026-10-17-acp-cancel-and-background.test.mjs:299-344` | 新增 U1 用例（AC-A6-7）：在飞 prompt 中写 `autoApprove` ⇒ 写入响应与 `config_option_update` 先于 prompt 收束、假 agent 由 `false` 翻 `true`；负向 `{configId:"mode", value:"plan"}` 仍排在 prompt 之后 |
| 同档 `:5-8` | 头部用例清单补该例 |

**读数（本机实测）**

- `cd thincoder-cli && node --test ..\docs\batches\2026-10-17-acp-cancel-and-background.test.mjs ..\docs\batches\2026-10-17-acp-suspension.test.mjs` ⇒ **31/31 pass**（U1–U3 = 21 · W1–W10 = 10），2.96s。
- `npm run lint` ⇒ `check-syntax: 127 file(s) OK`。
- 红→绿（同一条用例）：临时撤掉窄判谓词 ⇒ `timeout waiting for response id=2`（1 failed，8s 超时）；恢复后 1 pass。
- 行数（`wc -l`）：`transport.mjs` **175 → 186**（+11）；用例档 **705 → 751**（+46）。

**决策透明表**

| 判断点 | 决定 | 依据 |
|---|---|---|
| 窄判形态 | 谓词 `isInboundExempt` 置于白名单 Set 旁，判据处调用 | 设计档写「判据处窄判入」；语义等同、单点可读；供 designer 重钉时对齐措辞 |
| 是否校验 `value` 类型 | 不校验，只按 `configId` 豁免 | 设计 §3.1 判据只列 configId；非法 value 由 handler 回 `-32602`，与留队时同形 |
| 「全量 configOptions」断言形态 | 精确成员序列 `["thinking","mode","autoApprove"]` + 与通知 deepEqual | AC-A6-7 原文 = 「含全量 configOptions」；一次性用例，耦合成本为零 |

**审计 / 评审轮次与终态**

- **内部 explore 分歧审计 1 轮**：FINDINGS(5) = 4 yellow + 1 blue。处置：yellow #4（§5 缺本轮记录）= 本段落笔即结；blue #5（「全量」断言未钉）= 采纳，补成员序列断言 + 通知同源 deepEqual；yellow #1–#3 = 设计档坐标漂移（禁改设计档，报父侧）。
- **advisor 代码评审 1 轮**：verdict **pass**（0 red · 3 yellow · 3 blue）。处置：yellow #1（§3.1 实现位点行号作废）、#2（批档读数失真）、#3（设计档「行为变化」未枚举豁免写入与队列写的交错）= doc 层，只报不改；blue #4（精确成员序列宜改结构断言）不采纳——AC 要求「全量」且用例随批删；blue #5（`flush(20)` 墙钟否定断言）不采纳——prompt 由 gate 持有，不会假红，最终判定以 `:342` 响应序号为准；blue #6（用例档 751 行过 500 建议线）无需动作——§5 已就 705 行作接受，随批删。
- **终态 = `clean`**（无未处置 must-fix；31/31 + lint 全绿；红→绿可复现）。

**偏差 / 未做**

- **设计档坐标漂移（只报不改）**：§3.1「实现位点」写 `transport.mjs:30`（Set）、`:106`（判据）、`:81-116`（handleLine）、`:99-102`（client 响应豁免）、`:157-171`（start）；实测 `:33`、`:39-40`（调用点 `:117`）、`:92-127`、`:110-113`、`:168-182`。建议改符号锚（`INBOUND_EXEMPT` / `isInboundExempt` / `handleLine` / `start`）。
- **未做**：设计 / 需求档零改（授权禁止）；`handlers-session.mjs` / `bridge.mjs` 零改；未扩到其它 configId；未跑真机探针（父侧收口轮）。
- **观察（只报）**：设计档「行为变化（接受）」①–⑤ 未列「队列中已有其它 configId 写入时，豁免写入的全形通知会带出前一条尚未落地的投影」——最终态收敛（last-write-wins），且按「等应答再写」的客户端不可达。

## §6 验证与收口（父代理）

### 验证（2026-10-19 父侧复跑）
- 单测：`cd thincoder-cli && node --test ..\docs\batches\2026-10-17-acp-cancel-and-background.test.mjs ..\docs\batches\2026-10-17-acp-suspension.test.mjs` ⇒ **30/30 pass**（U1–U3 20 + W1–W10 10），3.03s。
- lint：`npm run lint` ⇒ `check-syntax: 127 file(s) OK`。
- 真机探针（AC-A6-1 / N9，本仓 CLI + 真模型）：`initialize` ok（0.12.76）；`session/new` → 1；prompt 在飞 2.5s 后写 `session/cancel` ⇒ **1.72s** 收束 `{"stopReason":"cancelled"}`（≤2s）；紧随 prompt ⇒ `{"stopReason":"end_turn"}`。**AC-A6-1 通过**。
- 探针脚本 = `.thincoder/tmp/acp-probe.mjs`（临时区，随批清）。

### 上抛处置（父侧）
- 评审 blue #4（`runNormal` 排队任务体复查 `closed`）**不采纳，接受**：今日经 transport FIFO 不可达；加无据守卫 = 改语义。复核条件 = transport 豁免面扩大或 queue 路径变化。
- 需求档 R-A7.1「排队条目算不算开始 / id 类型」**不改需求档**：设计档 §12.9 已定（advisor 入池即 start；`id` 恒字符串），需求只要求「开始/结束各一条帧」，不冲突；设计是「怎么实现」的规范源。
- 设计档坐标重钉 = eng-designer #16 在飞（交付实测落点见 §5；只改设计档，零代码）。
- 现状：未提交（thincoder 仓 11 改 + 3 新）；提交待收口时一并处理。

### 父侧机械修正（2026-10-19 · 可回退）
- §12.8 四个锚点重钉（#16 发现 1；逐条对代码核过）：`suspension.mjs:110`→`:124`（`done` 载荷）· `:139`→`:155-157`（`submit` 拒绝）· `session.mjs:48-51`→`:57-61`（窗关残余）· `suspension.mjs:99-112`→`:110-117`（不外抛）。
- 删 §12.8 的批内测试档指针（`docs/batches/2026-10-17-acp-suspension.test.mjs` W1–W10）——状态档不引过程档。
- 删 §3.5 表第 13 行（批内用例档，703 行）——随批删后是死指针；表余 12 行（产品文件）。
- 以上为父侧直接执行（机械修正：锚点 / 指针 / 表行），可回退。

### 收口结算（2026-10-19）
- **autoApprove 窄豁免（用户 00:55「按A修」）**：设计档 §3.1 / §3.2.1 AC-A6-7、需求档 R-A6.1 窄豁免条文；`transport.mjs` 窄判入 + U1 新例。父侧复跑 **31/31**（U1–U3 21 + W 10）、lint **127 OK**；用户真机确认「点 for this session ⇒ 立即 auto；停止键可用」。
- **设计档读数**：§3.5 transport 实交 **186**（+31，含窄豁免）；§12.8 四锚点 + §3.5 批内用例行已由父侧机械修正（见上）。
- **批内测试档**：`docs/batches/2026-10-17-acp-cancel-and-background.test.mjs` 已删（随批删，读数留 §5/§6）；`2026-10-17-acp-suspension.test.mjs`（批 8，tracked）仍留——零保留待用户确认后删。
- **台账**：#25 / #26 / #33 已核销；#28（mock 入站串行未做）由本记录收口重锚为「条件」（原批已收口，须另起批次接手）；#37 / #38（批 10）待设计 → 在途；#77（`open_editor_test` 既有红）归批；#76（上游合并轻渠道轮）在途。
- **未决读数**：本批收口前 **54** → 收口后 **51**（核销 #25/#26/#33 三条；#28 重锚仍计未决；#37/#38 状态推进不改计数；#77 已计）。
- **验收命令**：`cd thincoder-cli && node --test ..\docs\batches\2026-10-17-acp-cancel-and-background.test.mjs ..\docs\batches\2026-10-17-acp-suspension.test.mjs` ⇒ **31/31**（删除前）；`npm run lint` ⇒ **127 file(s) OK**；真机探针（`.thincoder/tmp/acp-probe.mjs`）⇒ cancel **1.72s** / `cancelled` / 下一轮 `end_turn`。
- **集成测试**：本批不新增业务场景；CLI 面由 U1–U3 + W1–W10 与真机探针覆盖；桌面消费后台帧不在本批（按 §2 边界）。
- **结算行**：requirement 行 #25/#26/#33 已核销；#28 重锚；本批交付物 = CLI 取消/后台帧 + autoApprove 窄豁免；设计/需求/批次三档同步。
