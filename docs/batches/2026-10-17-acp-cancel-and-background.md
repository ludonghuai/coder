# 2026-10-17 · acp-cancel-and-background
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-17 · 来源 = 独立评审（advisor reviewId f50d2068）🔴#1 + 两次真机探针复现 + 用户 2026-10-17 反馈「后台子代理曾被杀」。
> 台账 = #25（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：进行中（暂缓 · 复核条件 = 用户回头处理 ACP 取消/后台帧时（设计已过评审、15 条修正已落地，待批准实现）；2026-10-17 用户裁定「先把 IDE 完善」）
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
**状态行**：设计完成（评审 1 轮 15 条已落——见「评审 1 轮落地」（2026-10-17））
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

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
