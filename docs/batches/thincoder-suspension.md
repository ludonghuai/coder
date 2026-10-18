# 2026-10-17 · thincoder 挂起驱动
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-17 · 来源 = 用户 2026-10-17 01:31 报告（主 agent 在子代理结束后停在原地，不回来找用户要批准）。
> 台账 = #21（thincoder-adapter · 归批）。前情 = docs/batches/thincoder-queue.md（已收口 2026-10-17）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-17
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

- **开批**（2026-10-17 01:31 用户报告）：评审 / 设计子代理真结束后，主 agent 停住不回来找用户发批准——「需要保证主 agent 时刻关注子 agent」。
- **根因**（父侧实读）：终端面有整套挂起驱动（`thincoder-cli/src/tui/suspension-drive.mjs` 的 `suspensionSession` + 核 `@thincoder/core/agent/suspension.mjs` 的 `startSuspension`；回合尾进挂起，子代理结算 ⇒ `digestTurn` 自起回合）；**ACP 面零挂起机制**（`src/acp/session.mjs` / `src/acp.mjs` / `handlers-session.mjs` 无 `suspension` / `digest` / `poolLive` 引用）⇒ 桌面会话回合结束即静默。
- **范围**：把挂起驱动搬进 ACP 会话层（复用核状态机，**零改**状态机）；为「自起回合」补一个回合边界帧（`session_info_update` 的 `_meta` 载波），桌面把它翻成既有「无提示回合」面（`TurnStarted(unprompted: …)`）——宿主与 UI 本仓零改动。
- **父侧裁定**：
  ① 回合边界帧用 `session_info_update` 的 `_meta` 载波（不加新方法、不进能力位；旧客户端忽略即合规）；
  ② 与批 7 的客户端队列不冲突（服务端挂起只管后台子代理；队列在客户端）；
  ③ 旧 CLI 无此机制 ⇒ 桌面照旧静默（今天），不加版本门；
  ④ 该仓 `docs/core/design/AGENT-LOOP-ASYNC-POOL.md:442` 现写「ACP 不支持挂起」与本批相反，out-of-repo 轮须同轮改。
- **前情**：批 7（F15 队列）已收口 2026-10-17；本批与其无文件交叠（批 7 = kernel 队列面；本批 = CLI 侧挂起装配 + 本仓翻译一行）。

- **外仓轮已执行**（2026-10-17 02:0x，父侧直接写——子代理不得写本仓以外的文件）：`thincoder` 仓提交 **`a14c3658`**（分支 `feat/acp-subagent-attribution`）= `src/acp/suspension.mjs`（新增 130 行）+ `src/acp/session.mjs` 改写（55→150）+ 四处 `cancel()`→`close()` + `ACP-CLIENT.md` §12.8 + `AGENT-LOOP-ASYNC-POOL.md` §6.30 行 + 该仓批次档与单测。读数：`node --test docs/batches/2026-10-17-acp-suspension.test.mjs` ⇒ 7/7 pass；`npm run lint` ⇒ 127 files OK。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（2026-10-17 · 设计档 §19（F16）+ 实现期修正轮 2–7（D62 / D63 · D64 · D65 / D66 · 修正轮 5 裁定 · 修正轮 7 普通回合同旗 + W9/W10 + timer 交付边界）；零代码）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖）**

| # | 条目 | 来源 |
|---|---|---|
| 1 | F16：子代理 / 后台任务结算后主 agent **自起一轮**继续（看见报告、回到用户要下一步），不刷新、不靠用户再发话 | 需求档 F16（批 8） |
| 2 | 终端与桌面同形：同一核挂起状态机驱动（终端已有；ACP 面无） | 需求档 F16 |
| 3 | （派生）自动轮在桌面可见：运行中 / 可停止 / 结束即回「该你了」 | 设计自定（§19.2 / D61） |
| 4 | （派生）自动轮期间发消息 ⇒ 进批 7 的本地队列（宿主既有面） | 设计自定（§19.2 末条） |
| 5 | （派生）收束：会话关闭 / 取消 / 进程退出 / 旧 CLI 兼容 | 设计自定（§19.3-④ / §19.11） |

**不覆盖**：timer 唤醒轮 · 自动轮请求审批 · 重放（session/load）里的回合边界 · 「只停这一轮、后台继续」 · 子代理级控制面（逐条带判定条件，设计 §19.8）。

**设计档落点**：`docs/design/thincoder-adapter.md` §19（做法与最近先例 / 回合边界帧与桌面翻译 / 挂起窗装配与收束 / 受影响文件 / 验收 §19.6 / 决策 D55–D61 / 用例 T68–T74 + W1–W5 / UI / 边界 / 走查 / 兼容）。
索引随改：§3.4 通知表（turn meta）· §3.6 翻译表（新增行 + 自动轮边界一句）· §5.2 尾（§19.4 指针）· §7（F16 行 + 一致链）· §9（挂起测试面）· §10（B1 例外 + 边界指针）· §11（批 8 行）· §12-A-4（核对形状）· §14-4（剩余边界改写）· §14-21（timer 登记）· §15.3 / §15.5 D26 / §15.6 走查 6 / §15.7 T34 / §15.8-1（digest 边界按现状改写并闭合）· 抬头分批行 · 变更记录。

**机制一句话**：thincoder 仓的 ACP 会话在**用户回合收尾后一个 macrotask**（`setImmediate`，保证 `session/prompt` 应答先出线）进挂起窗——复用核 `startSuspension`，与终端 / VSC / thincoder 桌面同源；池内结果结算 ⇒ 自起一轮（`autoTurn`），轮起 / 轮收发**回合边界帧**（`session_info_update` 的 `_meta["thincoder.dev/turn"]` = `{phase,kind?,ok?}`）；本仓把该帧翻成宿主**既有**的「无提示回合」（`TurnStarted(unprompted: true)` / `TurnEnded`）——UI 与宿主零改动。旧 CLI 无帧 ⇒ 行为 = 今天（行为探测，不加版本门）。

**两仓分工**

| 面 | 仓 | 交付 |
|---|---|---|
| 挂起窗 + 边界帧 + 收束 | thincoder（out-of-repo 轮） | `acp/suspension.mjs`（新）· `acp/session.mjs` 接线 · 4 处 `cancel()` ⇒ `close()` · ACP-CLIENT.md §12.8 · 该仓批次档 + 单元测试 |
| 帧翻译 + 测试面 | baocode（本仓） | `thincoder_kernel.dart` ≤ +45 · `thincoder_kernel_test.dart` T68–T74 · 固件 `digest-turn.ndjson` + `_check` 键 |

**受影响文件与测试覆盖**（详见设计 §19.4）

- 本仓：`thincoder_kernel.dart`（1027 → ≤1072）· `thincoder_kernel_test.dart`（2303 → ≤2473）· `test/fixtures/thincoder/digest-turn.ndjson`（新增 ~15）· `thincoder_fixtures_test.dart`（+4）· `test/fixtures/thincoder/README.md`（+2）。零改动：`thincoder_events.dart` / `thincoder_mock.dart` / 宿主 / l10n。
- thincoder 仓：`acp/suspension.mjs`（新增 ~150）· `acp/session.mjs`（55 → ~120）· `handlers-session.mjs` / `handlers-slots.mjs`（净 0）· ACP-CLIENT.md（+~40）· AGENT-LOOP-ASYNC-POOL.md（1 行）· 该仓批次档 + `.test.mjs`。
- 测试覆盖：T68–T74（本仓；mock `push` 直推边界帧，零 mock 改动）· W1–W5（thincoder 仓；假 run 直驱 `createAcpSession`）· 固件 `digest-turn.ndjson`；既有 `subagent-digest.ndjson` 不改 = 旧 CLI 兼容哨兵。
- 体量：`thincoder_kernel.dart` 1027 行在 >800 名单，本批 = 会话面行级新增、不动结构 ⇒ 不触发拆分批（设计 §19.4 末条）。

**验收对照**（设计 §19.6，逐条可验）

| F16 条目 | 判据 |
|---|---|
| 子代理结算后自起一轮 | 走查 2–4；CLI 单测 W1 |
| 看见报告 / 回「该你了」 | T68；走查 4（切走再回看：未读徽标在） |
| 终端与桌面同形 | 走查 9（同一核状态机 + 同一帧） |
| 不刷新、不靠用户发话 | T68（transcript 只有 `text:`，无 `user:`） |
| （派生）可见 / 可停止 | T68 / T71 / T73 |
| （派生）期间发消息 | T70 |
| （派生）收束 | T72 + W3 / W4 |
| （派生）旧 CLI 兼容 | 既有 `subagent-digest` 固件保持绿 + 走查 8 |

**关键决策**：D55（挂起驱动在 CLI 会话层，不在桌面——池与 pending 在子进程）· D56（`_meta` 扩展帧，不新增 `sessionUpdate` 变体、不加版本门）· D57（`start` 在用户回合在飞时暂存，由该回合 `TurnEnded` 起点，不强制结束回合）· D58（自动轮剥 `onPermissionRequest`，与终端 D-S7 同判）· D59（`session/cancel` 有轮在飞才 abort；`session/close` 无条件）· D60（进窗点 = 回合尾 + 一个 macrotask）· D61（`start` 轮起即发，不惰性）。

**上抛 / 待裁**

1. [上抛·知会] 本批 §1 未落（`docs/batches/thincoder-suspension.md:6-7` 仍是模板占位）。本设计以 spawn 简报（含验收①–⑥）为任务书；若 §1 另有口径，请回灌，我按新口径改 §19。
2. [上抛·知会] 需求档 §9「实施分批」只列到批 5（F13–F16 未列）——需求档一致性问题，主 agent 笔（我不改需求档）。
3. [上抛·知会] out-of-repo 轮清单（设计 §19.4 ①–⑦）：需父侧另起轮在 thincoder 仓落 `acp/suspension.mjs` / `session.mjs` 接线 / 4 处 `close()` / ACP-CLIENT.md §12.8 / 该仓批次档 + 单元测试；该仓 `docs/core/design/AGENT-LOOP-ASYNC-POOL.md:442` 现写「CLI headless / ACP ❌ 不支持挂起」，与本批相反，须同轮改。
4. [上抛·知会] 多面一致核对（主 agent 职责）：thincoder 仓 ACP-CLIENT.md §12.8 与本档 §19.2 是同一机制的两个文档面——out-of-repo 轮落盘后请按本档 §19.2 的线上形核对一致（帧形状 / 字段域 / 兼容句）。

**修正轮 1（2026-10-17 · 评审 §3 的 #1–#5、#8、#9 落地；零代码）**：设计档 `docs/design/thincoder-adapter.md` §19 按号改——#1 插入点钉死（`_endTurn` 内 `emit(TurnEnded)` 后、`_drain()` 前；暂存自动轮先起，队列 / 释放等自动轮收尾）+ T69② + §18.1 一行；
#2 自动轮 `try … finally` 必发 `end{ok:false}` + W6 / T71②；#3 D58 回调缺席 = 拒绝（桥侧 `unverified`）+ W5②；#4 upstream 返回路（核 consult 注入 ∥ 桌面只收文本；核侧入口 `unverified`）+ W7；
#5 §15.3 加「无在飞回合时」+ §19.2 末条改实际改动；#8 §5.2 尾改「本仓 1 档（kernel）+ 固件 / 测试面」；#9 `_turnKey` / `_turnUnprompted` / `lastTurnUnprompted` 取值层。用例表标题随改为 W1–W7。

**修正轮 2（2026-10-17 · 批 8 实现期两处设计缺口，父侧裁定「按设计缺口处理」；零代码）**：设计档 `docs/design/thincoder-adapter.md` §19 按号改——

- **① 暂存轮与自己的 `end` 不配对**（缺口 1，裁定 = 方案 (a) **撤暂存**）：§19.2 翻译表 +「`end` · 用户回合在飞 · 暂存位非空 ⇒ 撤暂存」行（`design:1800`）+ 配套 bullet「暂存位的收尾（D62）」（`design:1807`）+ D62 含被否（`:1918`）；用例 T74①（`:1954`）。代价写明 = 该轮内容仍入 transcript（搭在用户回合分组里）、`lastTurnUnprompted` 保持 false、零幽灵边界帧；被否 = 先起后收（0 项空轮 + 幽灵边界 + 补标 interrupted）/ 帧加回合 id。同一状态机的闭合：`start` · 暂存位已占 ⇒ 忽略、不覆盖（`:1798`）——由缺口①直接派生，非新语义。
- **② `ok` 非布尔不收轮**（缺口 2，裁定 = 宽容方向按「未中断」）：§19.2 `ok` 域改「任意；只有布尔 `false` 有意义」（`:1779`）+ 段「`ok` 的宽容方向（D63）」（`:1804`）+ `end` · 自动轮在飞 ⇒ 一律收轮（`:1799`）；D63 含被否（`:1919`）；用例 T74②（`:1955`）；「坏形忽略」现只剩：`_meta` / `phase` 坏形、无在飞自动轮（且无暂存）的 `end`、自动轮在飞或暂存位已占的第二个 `start`。W 侧口径一句（`:1969`）：CLI 恒发布尔 `ok`，D63 是客户端防御。
- **③ 读数回灌**（§19.4，按 2026-10-17 实测）：㉟ 实交 +43（⇒ 1070）· ㊱ 实交 +168（⇒ 2471）· ㊲ 9 行（原估 ~15）· ㊳ +3 · ㊴ +3（32 → 35；原估 +2）· 体量行同刷（`:1904`）。修正轮 2 的行数上界供 eng-coder 修正轮收口：㉟ ≤ +12（⇒ ≤1082）· ㊱ ≤ +45（⇒ ≤2516）。
- **④ 变更记录**：`:2067-2068`。索引随同步：§3.6 turn meta 行（`:170`）· §19.6 判据（`:1929`）。
- **读数目测差 1**（不阻塞）：实施报告写 README 33 → 35（+2），实测 `HEAD:test/fixtures/thincoder/README.md` = 32 行、现文件 = 35 行 ⇒ **+3**；本档按实测记 +3，README 内容本身无错、不改代码。

**修正轮 3（2026-10-17 · 走查暴露的设计缺口：切走视图丢后台子代理；父侧裁定「按设计缺口处理」；零代码）**：设计档 `docs/design/thincoder-adapter.md` §19 按号改——

- **释放规则（D64）**：§19.2 新增「释放规则（D64）：挂起窗可能开着 ⇒ `release()` 也要延后」（`design:1829` 起）——谓词 = `_turn != null || _starting != null || _events.hasLiveSubagents`（`hasLiveSubagents` 新增加在翻译层 = 卡片里有 `status == running`；queued / async / turn / approval 都建成 running）；兑现点两处 = `_endTurn` 尾（`kernel:600-606`）+ 每条 `session/update` 交 `_events.update` 之后（`_notification` `:813`）检查。
- **静默期（一个 macrotask，`Timer.run`）**：最后一个子代理离开即关会杀掉紧随其后的消化轮（`async-settle.mjs:306` 先发 `⟦ev⟧settled`、`:311` 才唤醒窗；`acp/suspension.mjs:66-67` 发 `start`；进程 `close()` = kill）——静默期让同批在飞帧先落地，`start` 一旦到达即转由轮末兑现；`prepare()` / `_teardown()` 取消计时。代价 = 释放恒晚一个 macrotask（含空闲释放；既有用例经 `settle()` 泵 0ms 定时器，断言不变）。被否：最后一个离开即关（丢消化轮）/ 等窗退出信号（CLI 新增帧，out-of-repo）/ 按卡片终态判有没有消化轮（窗可能不在，仍会永等）/ 秒级长计时（无信号依据）。
- **边界登记**：§19.8-10（静默期只有一个 macrotask，`start` 晚到 ⇒ 截；判定条件 + 加长静默期 ∥ 窗退出帧）· -11（后台 bash / browser / ssh 无帧 ⇒ 看不见，切走仍按今天释放）· -12（切走再切回：卡片 = 终态快照，不重建——`endSubagents` 清状态、`session/resume` 不重放子代理帧）；§19.9 一句可见面；§19.11 旧 CLI 一句（子代理帧 F11 起即有 ⇒ 同样延后，无窗 ⇒ 无副作用）。
- **用例 / 验收**：§19.7 +T75①–③（`design:2003` / `:2013` / `:2014`）——queued 也算忙（零 `session/close`）/ 最后一个离开后的静默期才关 / 消化轮在飞则轮末才关 / `prepare()` 切回作废；§19.6 派生判据行（`design:1987`）。
- **体量（§19.4）**：㉟ `thincoder_kernel.dart` 1079，修正轮 3 ≤ +35（⇒ ≤1114）· ㊱ `thincoder_kernel_test.dart` 2516，≤ +60（⇒ ≤2576）· 新增 ㊵ `thincoder_events.dart` 778，≤ +6（⇒ ≤784；移出「零改动」名单）· 体量行按实测刷（`design:1953`）。
- **索引随同步（一致性）**：§19.2 插入点坐标刷为现行（`:583-592` / `:602`）· §15.5 D26 指针 `D55–D61` → `D55–D64`（`design:623`）· §9 测试面 `T68–T74` → `T68–T75`（`design:419`）· §19.7 抬头与补项抬头随改。
- **变更记录**：`design:2135`。
- 读数（2026-10-17 只读实测）：kernel 1079 · events 778 · kernel_test 2516。

**修正轮 4（2026-10-17 · 走查第二条缺陷：子代理结算那一刻切走项目窗口 ⇒ 结果丢；父侧裁定「按设计缺口处理」；零代码）**：设计档 `docs/design/thincoder-adapter.md` §19 按号改——

- **根因（证据）**：释放靠时序。最后一个子代理 settle 与消化轮 `start` 之间桌面没有任何卡片可看（`hasLiveSubagents` 已假、`_turn` 还没起），修正轮 3 的一个 macrotask 静默期正是补这一段；机器 / 帧分批一慢就落在静默期外，切项目窗口（`ChatSession` 被 `dispose()`）时进程被杀、该轮消化与被杀的子代理一起丢。
- **修法（D65 · 窗开关帧）**：CLI 在挂起窗进 / 出各发一条 `watch` 帧（同一 `_meta` 键 `thincoder.dev/turn`，`phase:"watch"` + 布尔 `on`）——`on:true` 建窗时先于本窗任何轮帧（`startSuspension` 的循环在同步段就可能起消化轮），`on:false` 在窗 `done` 的 `finally`（池空自然退出 / `close()` / 有轮在飞的 `cancel()` 中止 / 窗内异常四径同达），建窗失败由 `catch` 补 `on:false` 再上抛；至多一对。线上形、字段域、发射点与理由 = `design:1783`–`:1798`。
- **桌面侧**：新增 `_watching`（`watch{on:true}` 置真、`on:false` 置假、`_teardown()` 清、`prepare()` 清；`on` 非布尔 ⇒ 忽略 + 留痕、状态不动，`design:1805`）；`_canClose` 加 `!_watching`；兑现点从两处扩到**三处**（轮末 / 每条 `session/update` 之后 / 窗关帧的 `_turnReport` 分支跑 `_releaseWhenIdle()`）；静默期降为**旧 CLI 兜底**（新 CLI 下窗开着先被 `_watching` 挡住，窗关后才轮到一个 macrotask）。骨架与逐条说明 = `design:1845`–`:1934`。
- **D66 · `dispose()` 同判据延后**：`dispose()` 今天无条件 `_closeSession()` + `_teardown()`（`thincoder_kernel.dart:467-472`）⇒ 切项目窗口 = 杀在跑的子代理与窗里的消化轮。改为：清队列 / 撤暂存 / 立即 `closeEvents()`（宿主已取消订阅，`emit` 有 `isClosed` 守卫 `agent_kernel.dart:403`），关会话按同一谓词延后、由静默期兑现；`_disposed` 从 `_releaseWhenIdle` 的守卫里去掉（否则延后永远兑现不了），`release()` 首行守卫挡 disposed 之后的释放请求，`send()` 首行加 `if (_disposed) return;`（防 `_turn` 永久非空挡死关闭）。同上 §19.2 骨架。
- **决定记录**：§19.5 改写 D64（前提去掉、被否表去掉「等窗退出信号」——本轮采纳）、新增 D65（窗帧 + `_canClose`；被否：加长静默期 / 桌面轮询 / 并进 start·end / 按卡片终态推断）、D66（dispose 延后；被否：照旧立即关 / 不关等下次启动）；§15.5 D26 指针 `D55–D64` → `D55–D65`…（同链）。
- **用例 / 验收**：§19.7 +T76①–③（窗开全程零 `session/close`，含卡片已 settled、消化轮未起的空档；旧 CLI 无窗帧时行为 = T75②；`dispose()` 有 live 子代理不立即关、窗关 + 空闲后关、dispose 后 `send` 不入队）+ W8（建窗即发且先于首个 `start` / 窗退出恰一条且在最末 `end` 之后 / 关会话时 `off` 仍出站）；`design:2073`–`:2075` / `:2088`。§19.6 派生判据行扩到 T75①–③ + T76①–③ + W8。
- **边界登记**：§19.8-10 改写为「静默期只在旧 CLI 上是唯一判据」（判定条件按新旧分叉）；新增 -13（`prepare()` 清 `_watching` ⇒ 离开→回来→再离开同一窗会退回兜底，判定条件 = 改回不清）、-14（`dispose()` 延后无上界：卡片卡 running ⇒ 进程残留，判定条件 = 加上界）；§19.8-8「两帧」→「本键的帧」。
- **体量（§19.4）**：㉟ `thincoder_kernel.dart` 1113，修正轮 4 ≤ +35（⇒ ≤1148）· ㊱ `thincoder_kernel_test.dart` 2570，≤ +60（⇒ ≤2630）· CLI ① 新增 ~150 + 窗开关帧 ~15 · ⑤ ACP-CLIENT +~45（含 `watch` 行）· 体量行刷读数（`design:2013`）。
- **索引随同步（一致性）**：§3.4 通知表 turn meta 改「回合边界 / 窗开关」· §3.6 翻译表 turn meta 行补 watch ⇒ `_watching`（不成事件）· §5.2 尾批 8 改「本仓 2 档（kernel + events）」· §9 测试面 `T68–T75` → `T68–T76` · §19.1 流程图 / §19.3-① / ④ 收束表 / §19.9 / §19.10 步 8 / §19.11 三组合表随改。
- **变更记录**：`design:2202`。
- 读数（2026-10-17 只读实测）：kernel 1113 · events 784 · kernel_test 2570。

**本轮偏差与上抛（逐条）**

1. `[上抛·待裁]` 派单 ② 要求「`prepare()` 清 `_watching`」已按令写入，但与 `attach()` 的引用计数形（`chat_session.dart:302-309`）冲突：离开 → 回来 → 再离开同一窗内会丢掉窗在线位，退回静默期兜底。已登记 §19.8-13；彻底消除需改一行（`prepare()` 不清，只由 `on:false` / `_teardown()` 清）。请父侧裁定是否按后者改。
2. `[上抛·知会]` 派单 ⑥ 的 `ACP-CLIENT.md §12.8` 属 out-of-repo（`thincoder` 独立仓；§1 既有裁定 = 子代理不写本仓以外文件）⇒ **本轮未写**。建议父侧 out-of-repo 轮补三处：`phase` 行加 `"watch"` · 新增 `on` 字段行（boolean，仅 watch）· 发射时机一句（「窗建立后先发 `on:true`、窗退出时发 `on:false`；旧客户端忽略无害」）。本仓设计档 §19.4 ⑤ 已按此记预计增量。
3. `[上抛·知会]` §5 未含本轮（零代码，无实施记录）；本轮改码待父侧另起实现轮（D65 / D66 + T76①–③）。

**修正轮 4 · 订正**：上文「决定记录」一条把 §19.5 的 D26 指针写成 `D55–D65`，实际落盘为 `D55–D66`（`design:623`；链尾 = 本轮新增的 D66）。

**修正轮 5（2026-10-17 · 上抛 1 裁定落地：`prepare()` 不清 `_watching`；零代码）**：设计档 `docs/design/thincoder-adapter.md` 按裁定改字段条 / 骨架条 / 代价条 + 边界条 + 变更记录——

- **裁定**：`_watching` 只由 `watch{on:false}`（四条退径都发：池空自然退出 / `close()` / 有轮在飞时 `cancel()` 中止 / 窗内异常）与 `_teardown()` 清；`prepare()` 只清 `_releaseWanted`（连静默期计时一起取消），**不清 `_watching`**。理由：窗状态是服务端事实，视图回来不改变它；`attach()` 是引用计数（`chat_session.dart:302-309`），`prepare()` 每次附加都会调到，清位会让「离开 → 回来 → 再离开」的同一窗内下一次 `release()` 失去 `!_watching`、退回静默期兜底——正是本批要消灭的时序。
- **改动坐标**：§19.2 `_watching` 字段条（`design:1805`）· 骨架末条 `prepare()` 语义（`design:1923`）· 代价与边界条（`design:1934`）· §19.8-13 改写为该裁定（`design:2109`）· 变更记录（`design:2203`）。
- **§19.8-13 新口径**：为什么不清（同上）· 丢 `on:false` 帧的后果 = `_watching` 停在真 ⇒ 桌面判忙、进程不释放，直到该会话下一次 `_teardown()` · 判定条件 = 走查见到「窗早已退出（无子代理、无在飞轮）而桌面仍判忙」⇒ 说明帧丢了，按 E4 留痕补（帧链路日志）并核 CLI 出站面（W8②）。
- 用例侧不变：T75③（`prepare()` 取消延后）仍成立——清的仍是 `_releaseWanted`；T76①③ 不涉 `prepare()`。
- 上文「本轮偏差与上抛 1」至此裁定落地（原两择一取「不清」）；零代码，D65 / D66 的改码仍待父侧另起实现轮。

**修正轮 7（2026-10-17 · 普通用户回合也带 `suspDriven:true` + W9/W10 + timer 交付边界；零代码）**：设计档 `docs/design/thincoder-adapter.md` §19 按号改——

- **① §19.3-②**：补「普通用户回合（窗外）同带 `suspDriven: true`」（`design:1967`）——`session.mjs:106-109` 的 `runNormal` 调 `execTurn(input, { suspDriven: true })`（窗内两型轮由窗包装补同旗 `suspension.mjs:100-102`）；与 TUI 同源（`tui/agent-turn.mjs:194`）。理由：不传 ⇒ 用户回合进行中结算的子代理条目被该轮在回合尾收走（核 `run-stages.mjs:283` fallback：注入并出池）⇒ 池空不开窗、无自动续轮 = F16 最窄漏实例。影响面：用户回合的工具轮收尾不再注入到期 timer（`post-turn.mjs:23`）。
- **② §19.7 W 表**：抬头改 W1–W10（`design:2048`）+ W9（窗内两型轮 `suspDriven === true`，`design:2090`）+ W10（普通回合 `suspDriven === true`、`autoTurn:false`、不发边界帧，`design:2091`）。
- **③ §19.8-1**：补 timer 交付边界（`design:2099`）——`suspDriven && timerWakeEnabled` ⇒ 工具轮收尾零注入、到期件留在途；ACP 无 `timerFace` / 无空闲闩，且本批之后每条 ACP 轮都经 `execTurn` 带旗 ⇒ 没有「下一个非驱动工具轮」可顺延；判定条件 = 接 `timerFace`。
- **④ 一致性随改**：§14-21 timer 登记行改写为新口径（`design:519`；原「等下一个用户回合边界才投递」在本批后不成立，按 D8 删除失效句）；变更记录一条（`design:2207`）。

**读数（2026-10-17 只读实测）**：`thincoder-cli/src/acp/session.mjs:106-109`（普通轮带旗，工作树未提交）· `suspension.mjs:100-102`（窗内两轮带旗）· 外仓测试 `docs/batches/2026-10-17-acp-suspension.test.mjs:267-315`（W9 含窗外断言 + W10）。本仓 / 外仓代码零改动。

**上抛 / 待裁**

1. `[上抛·知会]` 派单 ③ 的「交付顺延到下一次窗外工具轮」与 ① 不一致：普通轮也带旗后，ACP 面不再产生 `suspDriven:false` 的轮（`runNormal` / 窗包装 / 残余补发三径都经 `execTurn`），timer 没有交付面。设计档按实况写「没有下一个非驱动工具轮可顺延」。外仓批次档 `docs/batches/2026-10-17-acp-suspension.md` 的「顺延到下一次窗外的工具轮收尾」一句现已被 ① 推翻，属外仓文件，未改。
2. `[上抛·知会]` 外仓 W9（`test.mjs:267-303`）现同时断言「窗外普通回合 = true」（`:296`），与 W10 重叠；设计 W9 行只写窗内两型轮、W10 单独覆盖普通回合。外仓测试若要按设计拆开，需父侧在实现轮改 W9 标题 / 断言（不影响绿）。
3. `[上抛·知会]` 派单「已知事实」记 `session.mjs:106` 不带旗 / W9 仅窗内；实读工作树已是 `:106-109` 带旗、W9 改写 + W10 新增（外部实现轮先落）。设计按现行坐标写，读数已回灌。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

**评审基线**：本仓无 AGENTS.md / 项目标准 / 文档地图（三者均未声明），方法论与文档归属两项按本档 §15–§18 各批的同构小节惯例判；thincoder 仓侧坐标（`acp/suspension.mjs`、`core/agent/suspension.mjs`、`bridge.mjs` 等）不在本评审可读范围内，涉及它们的行为断言一律视为 `unverified`。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Clarity / Feasibility | 🟡 | 桌面插入点钉不住：㉟ 只写「`_endTurn` 起点暂存自动轮」（design:1853），而 §18.1 把批 7 的排水钉在同一方法的「`_endTurn`（`:518-531`，`emit(TurnEnded)` 之后、`_releaseWanted` 之前）」（design:1528），并立有前置不变量「`_turn = null` 在 `:513`」（design:1532）——按字面「起点」取方法开头，`_beginTurn` 刚置的 `_turn` 会被 `:513` 抹掉；且「暂存的自动轮」与「`_drain()`」在同一收尾点谁先谁后未定（先起自动轮 ⇒ 排队消息排到消化轮之后；先排水 ⇒ 用户回合在飞，暂存项失去触发点）。 | 在 ㉟ 把插入点写死为「`emit(TurnEnded)` 之后、`_releaseWanted` 之前」，并写明与 `_drain()` 的先后（推荐：暂存自动轮先起、`_drain()` 见 `_turn != null` 返回 false ⇒ 队列等消化轮收尾再排）；T69 补一条「有排队消息 + 暂存 `start` 同批」的变体。 |
| 2 | Acceptance / error conditions | 🟡 | 「自动轮失败但进程存活」无规则、无用例：§19.3-② 只写了用户唤醒轮失败（design:1831），自动轮侧只有字段域「false = 中断 / 出错」（design:1777）与「轮起即发 start、轮收即发 end」（design:1779），没有 `finally` 必发保证，W1–W5 / T68–T74 也无此形。缺这一帧 ⇒ 桌面 `activeTurn` 永不收 ⇒ 永久「正在续写」且排队消息永不排水——恰是本批要消灭的停住态。 | 在 §19.3-② / §19.1 写明自动轮的 `try … finally { emit(end, ok) }`；W 侧补一条（自动轮抛错 ⇒ `end{ok:false}` + 窗按核语义收窗），T 侧补一条非本端 `cancel()` 来源的 `end{ok:false}` ⇒ `TurnEnded(interrupted: true)`。 |
| 3 | Clarity / safety | 🟡 | D58 剥掉 `onPermissionRequest`（design:1830 / :1882），但设计未写服务端在回调缺席时给什么判决（放行 ∥ 拒绝），W5 也只断言「callbacks 无 `onPermissionRequest`」（design:1922）。这一位决定无人值守的自动轮能否执行需审批的工具——放行 = 静默越权，拒绝 = 自动轮用不了工具。桥侧语义本评审不可读 ⇒ `unverified`。 | 在 D58 / §19.3-② 写明期望判决（建议与终端手动档同判：直接拒绝），并把 W5 的断言扩到「判决 = 拒绝」。 |
| 4 | Requirements coverage / Clarity | 🟡 | `upstream` 只进不出：`kind` 域声明「upstream = 子代理在等回复」（design:1776），§19.3-② 也传 `upstreamTurn?`（design:1827），但没有任何一处说这轮的答话怎么回到等着的子代理——`injectResidual` 仅注为「核注入器（consult / 子代理两族分发）」（design:1814），W1–W5 / T68–T74 也没有 upstream 用例。 | 补一句该轮的返回路（是否走核 consult 注入、桌面侧是否只收文本）；做不到就在 §19.8 立「upstream 本轮不接」+ 判定条件，并从 §19.2 的现发射集里摘掉。 |
| 5 | Document ownership / doc-state | 🟡 | 同一节两句打架：§15.3「挂起期再发消息」仍写「服务端排队 / 合并后作答——桌面零特判」（design:591），下一条则写「自动轮期间发消息进本地队列（§19.2 末条）」（design:592）；§19.2 末条还声称「§15.3 的那句口径随本批改写」（design:1798）——实际只改了 digest 到达形那一条。未升 🔴 的理由：新口径在 :592 已明确在场，冲突出在 :591 缺状态限定词，非机制争议。 | 给 :591 加状态限定（「无在飞回合时」），并把 :1798 的「随本批改写」修成实际改了什么（或改 :591 后保留原句）。 |
| 6 | Scope authority（coordination item） | 🟡 | B1 的例外要「经用户裁定」（requirements:160）；F12 / F13 / F14 的条目都记了裁定原话（requirements:87 / :97），F16 条目只记「用户 2026-10-17 01:31 报告」（requirements:112），而设计侧直接把它算进例外清单（design:372 / :429）。批 8 的外仓面（新档 ~150 行 + `session.mjs` +65 + 4 处 `cancel()`→`close()` + 契约档，design:1864-1870）比 F12 的 +11 行接口标大一个量级。 | 在需求档 F16 条目补一句裁定（照 F12/F13/F14 的写法），或在 §19.4 注明该外仓轮的准入前提 = 用户裁定后才开。 |
| 7 | Document ownership（cross-file lag） | 🟡 | 需求档 §9 实施分批只到批 5（requirements:185-191），而同一档的 F13/F14（批 6，requirements:97-106）、F15（批 7，:108-110）、F16（批 8，:112-115）都已落，设计抬头也声明批 6–8（design:5）。按层序（设计 > 需求）落后的是需求档这一侧。 | 在需求档 §9 补批 6 / 批 7 / 批 8 三行（与设计抬头一致）。 |
| 8 | Clarity（note） | 🔵 | §5.2 尾把本批本仓面写成「批 8 见 §19.4（本仓一行 + 测试面」（design:300），与 ㉟「≤ +45（⇒ ≤1072）」（design:1853）不一致；同段批 6 / 批 7 的同位写法是「宿主 1 档」「内核本地队列」，不会被读成「一行代码」。 | 改成「本仓 1 档（kernel）+ 固件 / 测试面」。 |
| 9 | Clarity（note） | 🔵 | 命名对不上：㉟ 引入 `_turnKey`（design:1853）但 §19 全文没有定义；㉟ 的字段是 `_turnUnprompted`，而 T68 / T73 断言的是 `lastTurnUnprompted`（design:1906 / :1911）——后者不在本批任何文件清单里，且「其余本仓档 **零改动**：`thincoder_events.dart`」（design:1858）是硬约束。 | 在 §19.2 定义 `_turnKey`（= `thincoder.dev/turn` 键常量）；统一成一处取值口径（内核 getter ∥ 宿主既有字段），并写明该断言读的是哪一层的属性。 |

计数：🔴 0 · 🟡 7 · 🔵 2。
VERDICT: pass

## §4 用户批准（主 agent）

- **用户批准**（2026-10-17 01:55，逐字「批准」）——批准对象 = 设计档 §19（经评审 0 🔴 / 7 🟡 / 2 🔵 + 修正轮 1 全落地）。
- **B1 例外仍待明示**：用户在 01:55 只回了「批准」，未回「可以动 thincoder 仓」⇒ 本批先落**本仓翻译面**（设计 §19.4 ㉟–㊴）；外仓轮（①–⑦）在收到明示前不开。
- 裁决表（评审 #1–#9）已全数收敛：7 条 Dispatched → Fixed（#61 修正轮落地并经父侧逐条核读）；#6 / #7 由父侧直接修（需求档 F16 B1 状态句 · §9 分批补批 6/7/8）。

## §5 实施记录（eng-coder）

**状态行**：实施完成（2026-10-17 · 主轮 ㉟–㊴ + 修正轮 2–4、6–7：本仓 103/103 未变 · 外仓 suspDriven 两处 + W9/W10 = 10/10 · 外仓 lint 127 files OK）

**交付摘要**（本仓 1 档 + 测试面；flutter = `C:\Users\xinbo\repos\flutter\bin\flutter.bat`）

| # | 文件 | 改动 | 读数 |
|---|---|---|---|
| ㉟ | `lib/kernel/thincoder/thincoder_kernel.dart` | 回合边界翻译：`_turnKey`（`:786`）· `_turnUnprompted` / `_autoTurns` / `_pendingAuto`（`:96-100`）· `_beginTurn(unprompted:)`（`:536`）· `_turnReport`（`:544-561`）· `_endTurn` 暂存起轮（`:584-590`，`emit(TurnEnded)` 后、`_drain()` 前）· `_notification` 拦截（`:798-803`）· `_teardown` 清暂存（`:382`） | 1027 → 1070（+43，≤1072） |
| ㊱ | `test/kernel/thincoder_kernel_test.dart` | 新组 `thincoder automatic turns`：T68 · T69 · T69② · T70 · T71 + T71②（一条两段）· T72 · T73 · T74，共 8 条用例 | 2303 → 2471（+168，≤2473） |
| ㊲ | `test/fixtures/thincoder/digest-turn.ndjson`（新） | 线形 start → 文本 → end；`expect` 含 `unprompted: true` | 9 行 |
| ㊳ | `test/kernel/thincoder_fixtures_test.dart` | `_check` 增 `unprompted` 键（`:166-168`） | +3 行 |
| ㊴ | `test/fixtures/thincoder/README.md` | `expect` 键清单补 `unprompted` + 一条回合边界说明（`:23-26`） | +2 行 |

**验证读数**：`flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` = **95/95 全绿**（含 T68–T74 + 两个补项、`digest-turn` 固件）；`flutter analyze` 本批三档 = **No issues found**。零改动面（`thincoder_events.dart` / `thincoder_mock.dart` / 宿主 / l10n）未动；既有 `subagent-digest.ndjson` 未动（旧 CLI 哨兵）。跑 `flutter test/analyze` 顺带把 `pubspec.lock` 的 pub 镜像 URL 改写为 `pub.dev`（环境副作用），已 `git restore pubspec.lock` 还原，不入本批。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | 自动轮 id 在「暂存」时分配（`auto:<n>`），起轮时沿用 | design §19.2「起轮行的 id = 暂存时的 `auto:<n>`」 | 落地 |
| 2 | `kind` 只在轮起时 `appEvent` 留痕（暂存与直接起轮同一口径） | design §19.2「kind 只留痕」 | 落地 |
| 3 | `ok` 非布尔（如 `"false"`）按坏形忽略、不收轮 | §19.2 坏形行（:1801）与 `end` 表格行（:1799）二义 | [上抛·待裁] 评审 #2：若 CLI 写出非布尔 `ok`，桌面将永久「正在续写」；推荐「有 `end` 且自动轮在飞 ⇒ 一律收轮，仅 `ok == false` 标 interrupted」，待父侧裁定后改 |
| 4 | 暂存 `start` 的 `end` 若在用户回合内先到 ⇒ 只留痕、不撤暂存；该用户回合收尾仍会起一个永不收的 `auto:<n>` | §19.2:1797 / :1800 两行各自成立、未写该形；帧无回合 id | [上抛·待裁] 评审 #1：可达路径 = 用户连发两条 + 子代理结算（CLI 窗内先跑自动轮、桌面把队列第二条发成新回合）。代码忠实于设计，未擅自改语义；建议二选一（代码侧对无从归属的 `end` 顺带撤暂存 ∥ 设计侧补该形 + 帧加 id），并补 T74 用例 |
| 5 | `_teardown` 只清 `_pendingAuto`，不清 `_turn` / `_turnUnprompted`（`restart()` 在自动轮在飞时留旧轮状态） | batch 7 既有 `_turn` 形；`_exited` 依赖 teardown 后 `_endTurn` 收轮 | [上抛·知会] 评审 #3：非本批引入，建议后续单在 `restart()` 侧先收轮再 teardown；本批不动 |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮 · CLEAN** —— ㉟–㊴ 五件逐项对 design §19.2 / §19.4 / §19.7：翻译表六行、插入点（`emit(TurnEnded)` 后、`_drain()` 前）、`_teardown` 清暂存、8 条用例、固件 / README / `_check` 键均对齐；未发现 PARTIAL / 静默简化 / 文档漂移 / 表外改动。审计装配无 shell，测试与 analyze 未跑（以本段读数为准）。
- 内部 advisor 代码评审：**1 轮 · pass**（🔴 0 · 🟡 2 · 🔵 3）。处置：#1 / #2 = 上抛待裁（设计缺口，未改语义）；#3 = 知会（既有形）；#4 = 采纳，已把长行折为两行（test:2273-2274；格式化器在本仓未强制——`dart format` 对三个未触碰档同样报 Changed，故只折行不整档重排）；#5 = §5 本段落地，设计 / 批档读数回灌归父侧。
- **fix round：1**（评审 #4 折行；审计 0 项）。**终态：clean。**

**修正轮 2（2026-10-17 · 按修订设计 #63 改码：D62 撤暂存 · D63 `ok` 宽容 · T74① / T74②）**

**交付摘要**（号 → 改动 file:line）

| 号 | 坐标 | 改动 |
|---|---|---|
| #1（D62） | `lib/kernel/thincoder/thincoder_kernel.dart:561-566` | `_turnReport` 增 `end · 用户回合在飞 · 暂存位非空` 分支：`_pendingAuto = null` + 带 kind 留痕（`an automatic turn (digest) ended before it was taken up`）；不起轮。该轮内容仍入 transcript（搭用户回合分组）、`lastTurnUnprompted` 保持 false；用户回合收尾时暂存位已空 ⇒ `_drain()` 照常排水（`:594-602` 既有形） |
| #1b（派生闭合） | `:554` | `start` 暂存分支加 `pending == null` 守卫：暂存位已占 ⇒ 落 `:568` 通用「leave alone」留痕，不覆盖原暂存项 |
| #2（D63） | `:556-560` | 自动轮在飞时 `end` 一律收轮：`_endTurn(interrupted: ok == false)`（只有布尔假算中断；缺省 / 非布尔 / 其它按未中断）；非布尔非空 `ok` 另留痕一条（`:557-559`） |
| 用例 T74① | `test/kernel/thincoder_kernel_test.dart:2305-2326` | `hold` 下 `send('one')` → 用户回合在飞 push `start{kind:digest}` → 同回合 push `end{ok:true}` ⇒ 撤暂存；断言：`TurnStarted` 1 / `TurnEnded` 0（`release` 前）、撤暂存留痕一条、`release` 后 `activeTurn == null` / `lastTurnUnprompted == false` / `TurnEnded(interrupted:false)` 一条、随后 `send('two')` 直接写出 `session/prompt`（`_prompts == ['one','two']`） |
| 用例 T74② | `:2328-2347` | 两条独立会话：① `end{ok:"false"}`、② `end`（键缺席）⇒ 都收轮且 `lastTurnInterrupted == false`；① 留痕一条；② 另钉 `TurnEnded` 恰一条 + 第二会话不新增非布尔留痕 |

**验证读数**：`flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart` = **97/97 全绿**（既有 95 + 新 2 条）；`flutter analyze` 两档 = **No issues found**；行数 `wc -l`：kernel **1079**（≤1082；主轮 1070 + 9）/ kernel_test **2516**（≤2516；主轮 2471 + 45）；`pubspec.lock` 已 `git restore`（跑 flutter 的镜像改写是环境副作用，不入本批）。本轮只动上述两档；`thincoder_events.dart` / `thincoder_mock.dart` / 宿主 / l10n / 固件 / 设计档 / 需求档 / 批次档零改动。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | 非布尔 `ok` 收轮时留痕一条（T74②「① 另留痕一条」） | 设计 §19.7 T74② 补项 + §19.2 `end` 行 | 落地：`ok != null && ok is! bool` 时 `appEvent`；缺席（null）不留痕，与「键缺席」用例期望一致 |
| 2 | 第二会话（键缺席）断言 `TurnEnded` 恰一条 + 不新增留痕 | 内部代码评审 #2（🔵）：原用例只经 `lastTurnInterrupted` 间接证明收轮，`ok` 缺席方向无回归保护 | 采纳，`test:2346-2347`；测试档到 2516 上界 |
| 3 | T74① 的 `end` 帧补 `ok: true`，对齐设计 §19.7 输入形 | 内部代码评审 #1（🔵）：原文只推 `end`（键缺席），D62 分支不读 `ok` 但输入形与设计档不一致 | 采纳，`test:2312` |
| 4 | 「暂存位已占的第二个 `start` 不覆盖」不补用例 | 设计 §19.2 表第 3 行有行为、§19.7 用例表未列；测试档已到 ≤2516 硬上界（实测 2516），再加用例必越界 | 不修，留待后续轮（需先修订体量上界）；实现侧守卫在 `kernel:554` |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮 · CLEAN** —— 逐条对 design §19.2 翻译表 7 行 / §19.5 D62·D63 / §19.7 T74①②：撤暂存、`ok` 宽容、暂存位不覆盖、插入点（`emit(TurnEnded)` 后、`_drain()` 前）、`_teardown` 清暂存均对齐；无 PARTIAL / 静默简化 / 文档漂移 / 表外改动（审计无 shell，测试与 analyze 未跑，以本段读数为准）。
- 内部 advisor 代码评审：**2 轮 · pass**。第 1 轮（🔴 0 · 🟡 0 · 🔵 3）：#1 / #2 采纳（上表 #2 / #3），#3 因体量上界不修（上表 #4）；第 2 轮复核两项修复 + 不修理由，结论 pass（无新增问题）。
- **fix round：2**（评审 🔵 #1 / #2 落地；#3 有理由不修）。**终态：clean。**

**修正轮 3（2026-10-17 · 走查缺陷「切走对话丢后台子代理」；按设计 D64 改码）**

**交付摘要**（号 → 改动 file:line）

| 号 | 坐标 | 改动 |
|---|---|---|
| D64 · 谓词 | `lib/kernel/thincoder/thincoder_kernel.dart:440-442` | `_canClose` = `_turn == null && _starting == null && !_events.hasLiveSubagents`；新增字段 `Timer? _releaseCheck`（`:110-114`） |
| D64 · 兑现点 1 | `:634-637`（`_endTurn` 尾） | `if (_releaseWanted) { … }` 整段换成 `_releaseWhenIdle()`；顺序仍是 `emit(TurnEnded)` → 暂存自动轮 → `_drain()` → 释放判定 |
| D64 · 兑现点 2 | `:842-847`（`_notification`） | `_events.update(update)` 之后 `_releaseWhenIdle()`（回合边界帧仍经 `_turnReport` 提前返回） |
| D64 · `release()` / 静默期 | `:428-464` | `release()` 置 `_releaseWanted` 后交 `_releaseWhenIdle()`；静默期 = 一个 macrotask（`Timer(Duration.zero, …)` = `Timer.run` 的等价实现——Dart 的 `Timer.run` 返回 `void`，设计骨架的 `_releaseCheck ??= Timer.run(…)` 不可编译）；到点复核 wanted/disposed/`_canClose` 才关；空手守卫（`_transport == null && _starting == null`）清位不排计时 |
| D64 · 取消 | `:365-367`（`_teardown`）· `:409-415`（`prepare`） | 取消并置空 `_releaseCheck`；`prepare()` 另清 `_releaseWanted` |
| ㊵ · `hasLiveSubagents` | `lib/kernel/thincoder/thincoder_events.dart:63-67` | `_subagents` 里有卡片 `status == CommandStatus.running`；`_tasks` 不参与 |
| T75① | `test/kernel/thincoder_kernel_test.dart:2350-2366` | queued 卡片 + `release()` ⇒ 零 `session/close`、health ready；`settled` 后静默期到点才关（close 一条、idle、`await stopped` 兑现） |
| T75② | `:2368-2389` | async 卡片 + `release()` ⇒ 零 close；同批 `settled` + `start` ⇒ 零 close、`activeTurn == 'auto:1'`；`end` 后的静默期才关 |
| T75③ | `:2391-2402` | async + `release()` → `prepare()` → `settled` ⇒ 零 close、health ready |

**验证读数**：`flutter test test\kernel\thincoder_kernel_test.dart test\kernel\thincoder_fixtures_test.dart` = **100/100 全绿**（既有 97 + T75 三例）；`flutter analyze` 三档 = **No issues found**；行数（末行读数）：kernel **1113**（≤1114）· kernel_test **2570**（≤2576）· events **784**（≤784）；`pubspec.lock` 已 `git restore`。零改动面：`thincoder_mock.dart` / 宿主 / l10n / 固件 / 设计档 / 需求档 / 批次档。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | 静默期用 `Timer(Duration.zero, …)` 而非设计骨架字面 `Timer.run` | Dart `Timer.run` 返回 `void`，不能作 `??=` 右值（首跑编译失败实测）；`Timer.run(cb)` 即 `Timer(Duration.zero, cb)` | 落地 + 行内注释说明；设计档骨架建议父侧改一行（doc drift，代码无偏差） |
| 2 | `_releaseWhenIdle` 保留设计 :1872 的空手守卫（无 transport 且无 starting ⇒ 清 `_releaseWanted`、不排计时） | design §19.2 | 落地；防进程已死后计时器把 failed 覆盖成 idle |
| 3 | T75③ 未覆盖「计时器已排、`prepare()` 取消」这条形 | 设计 §19.7 T75③ 的输入形 = release 时有 live 卡片（谓词为假 ⇒ 计时器从未排）；本轮验收 = 97 + T75 三例，且 ㊱ 距上界仅 6 行 | 按设计落地；审计/评审各记一条（未补用例，理由见上） |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮 · CLEAN** —— 谓词 / 两兑现点 / 静默期 / 取消 / `hasLiveSubagents` / T75①–③ 逐项对 design §19.2 / §19.4 / §19.7；无 PARTIAL / 静默简化 / 表外改动。唯一 drift = 设计骨架 `Timer.run` 返回 void（代码侧等价实现，doc 侧待父侧改）。审计无 shell，测试与 analyze 以本段读数为准。
- 内部 advisor 代码评审：**2 轮 · pass**。第 1 轮（🔴 0 · 🟡 3 · 🔵 1）：🔵 = dartdoc 引用 `[canClose]` → `[_canClose]` 已采纳（`kernel:444`）；三项 🟡 为非阻塞——① 计时器取消路径无用例；② 卡片卡在 running ⇒ 释放无上界兜底、§19.8 未登记；③ §5/§6 记录与读数回灌未落（父侧笔）。第 2 轮复核：1 项 Fixed、3 项 Unfixed（均非阻塞）· pass，无新增问题。
- **fix round：1**（评审 🔵 落地）。**终态：clean。**

**修正轮 4（2026-10-17 · 外仓轮：thincoder 仓 ACP 挂起窗 `watch` 帧；按设计 §19.2 D65 / §19.3-①④ / §19.7 W8）**

外仓 = `D:\baocode\thincoder`（分支 `feat/acp-subagent-attribution`，基线 `0578ed8a`）；改动在工作树、未提交（提交归父侧）。

**交付摘要**（号 → 改动 file:line）

| 号 | 坐标 | 改动 |
|---|---|---|
| ① 窗进帧 | `thincoder-cli/src/acp/suspension.mjs:83-84` | `watchEnter()` 在 `startSuspension(...)`（`:88`）之前；发 `{phase:"watch", on:true}`——核循环在同步段就可能起消化轮发 `start`（核 `agent/suspension.mjs:278`），故必须先于调用 |
| ① 窗退帧 | `:152-163`（`done` 的 finally，`watchExit()` 在 `:162`） | 发 `{phase:"watch", on:false}`；四径同达 = 池空自然退 / `close()` / 有轮在飞的 `cancel()` / 窗内异常 |
| ① 建窗失败 | `:123-128` | `catch` 先 `watchExit()` 补 `on:false` 再上抛（配对不悬空） |
| ① 至多一对 | `:45-47` / `:65-77` | `watchAnnounced` / `watchClosed` 两旗 + 守卫；`off` 只在 `on` 之后、且只一次 |
| ② 帧载体 | `:49-77` | 抽出 `emitFrame`；watch 帧同走 `session_info_update` + `_meta["thincoder.dev/turn"]`；`on` 恒布尔、不带 `kind` |
| ③ 契约档 | `docs/cli/design/ACP-CLIENT.md:625-630` / `:635` / `:637` / `:641` / `:644` | 线上形加 watch 两帧；`phase` 加 `"watch"`；新增 `on` 行（boolean，仅 watch）；新 bullet「窗开关帧」（时机 + 四径 + 至多一对 +「旧客户端忽略无害」）；落点 W1–W7 → W1–W8 |
| ④ W8 | `docs/batches/2026-10-17-acp-suspension.test.mjs:220-264` | ①② 池空自然退：首帧 `watch{on:true}`、序 `watch→start→end→watch`、恰一对；③ `close()` 径：重复 `close()` 不重发、`off` 在最后一个 `end` 之后 |
| ④ 收集器 | `:43-66` | `makeSession` 新增 `stream`（全部帧，按出站序）；`frames` 过滤 watch——W1–W7 断言体逐字未改 |
| ⑤ 删诊断 | `thincoder-cli/src/acp/dbg.mjs`（删档）· `src/acp/session.mjs`（删 import + 4 处 `dbg` 调用）· `src/acp/suspension.mjs`（删 import + 2 处） | 全仓 `dbg` 零命中；`session.mjs` 与 HEAD 逐字相同（设计「窗帧在窗体里发、`session.mjs` 零改」成立） |

**验证读数**：`node --test docs/batches/2026-10-17-acp-suspension.test.mjs` = **8/8 全绿**（W1–W7 既有断言 + W8）；`node --check` = suspension.mjs / session.mjs / 测试档 全 OK；`npm run lint`（thincoder-cli）= **127 file(s) OK**；`grep dbg **/*.mjs` = 0 命中。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | `on:true` 发在 `startSuspension(...)` 之前，而非 `_suspended` 置位之后 | 设计 §19.2「先于本窗任何轮帧」；核在 `startSuspension` 同步段置 `_suspended` 并可能当场发首个 `start` ⇒ 两者不可兼得 | 取设计（可观测序，W8① 钉住） |
| 2 | 测试收集器拆 `frames`（start/end）∥ `stream`（全部帧） | 派单「W1–W7 断言零改动」与 W8 需含 watch 的完整出站序 | 落地；W1–W7 断言逐字未改（diff 仅收集器 + 头注 + W8） |
| 3 | `suspDriven` 恒 false（审计发现） | 设计 §19.3-② 两轮均传 `suspDriven:true`；核 `runTurn` 只传 `{autoTurn, upstreamTurn, timerTurn}`（核 `suspension.mjs:278` / `:308`）⇒ 窗侧未补，`session.mjs:74` 恒 false；TUI 同形硬编码 `tui/agent-turn.mjs:194` | [上抛·待裁] 不在本轮 5 项；一行修法 = 窗包装 `runTurn(text, { ...opts, suspDriven: true })`，并补 W1 断言（需父侧批准，因「不改 W1–W7 断言」） |
| 4 | 窗拒绝径残余输入不结算（评审 🟡，非 must-fix，既有面） | 窗 `submit()` 只经 `item.done` 兑现（`suspension.mjs:137`）；核抛错径不返回 `residualInput`（核 `:341` 只在正常收束执行）；`session.mjs:58-61` 拒绝回调只置空 + 记日志 | [上抛·待裁] 需设计裁定（窗体侧登记未结算条 ∥ 核回传残余），本轮不改 |
| 5 | 外仓批次档未回灌 | 派单禁止清单含批次档（父侧笔）；该档 §2 ⑦ / §5 仍 W1–W7 / 7/7 | [上抛·知会] 收口时补 W8 行与 8/8 读数 |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮**。本轮 ①–⑥ 全部对齐；记 2 条：① `suspDriven` 既有偏差（表 #3，待裁）· ② 外仓批次档滞后（表 #5，知会）。无表外改动。
- 内部 advisor 代码评审：**1 轮 · pass**（🔴 0 · 🟡 1（非 must-fix，表 #4）· 🔵 3）。🔵 三项 = 外仓批次档 W8 行滞后（#5）· W8 未覆盖 cancel 径 / 建窗失败径（建议或批档注明覆盖边界）· 测试用真实计时器 `flush(10)`（R4 建议改宏任务泵）。三项均非阻断，本轮不改。
- **fix round：0**（无 must-fix 项）。**终态：clean（本轮 5 项）/ 上抛 2 项（suspDriven 一行修法 · 窗拒绝径残余结算）。**

**修正轮 4 · 实现轮（2026-10-17 · 按设计 D65 / D66 改码 + T76①–③；主轮 = 两档）**

**交付摘要**（号 → 改动 file:line）

| 号 | 坐标 | 改动 |
|---|---|---|
| D65 · 窗位 | `lib/kernel/thincoder/thincoder_kernel.dart:115-116` | 新增 `bool _watching = false`（挂起窗在线位） |
| D65 · 谓词 | `:444-450` | `_canClose` 增 `&& !_watching`（四谓词：无轮 / 无启动 / 无 live 子代理 / 窗不在） |
| D65 · 翻译 | `:603-617` | `_turnReport` 增 `watch` 分支：`on` 布尔 ⇒ `_watching = on`；`on:false` 再跑 `_releaseWhenIdle()`；非布尔 ⇒ E4 留痕（`a watch frame with an on not a boolean`）、状态不动 |
| D65 · 清位 | `:393` | `_teardown()` 清 `_watching`；`prepare()` 不清（修正轮 5 裁定；`:414-421` 仍只清 `_releaseWanted` + 取消计时） |
| D66 · 延后 | `:474-496` | `dispose()` 重写：`_disposed` 幂等守卫 · 撤队列 / `_next` / `_pendingAuto` · `_resolveApprovals(refuse: true)` · 立即 `closeEvents()` · `_canClose` ⇒ 立即 `_closeSession()` + `_teardown()`，否则 `_releaseWanted = true; _releaseWhenIdle()` |
| D66 · 守卫 | `:456-472` | `_releaseWhenIdle()` 两个 `_disposed` 守卫去掉（disposed 之后的释放请求由 `release()` 首行 `:433` 挡）；计时回调仍复核 wanted / `_canClose` |
| D66 · 入口 | `:501-503` | `send()` 首行 `if (_disposed) return;` |
| T76① | `test/kernel/thincoder_kernel_test.dart:2406-2428` | 窗开着全程零 `session/close`（含卡片已 settled、消化轮未起空档；消化轮在飞 / 收尾后仍零 close）；窗关帧后的静默期：close 一条、health idle、`stopped` 兑现 |
| T76② | `:2430-2443` | 无窗帧（旧 CLI）⇒ 静默期兜底 = T75②：同批 settled + start 零 close（`activeTurn == 'auto:1'`），end 后一条 close、health idle |
| T76③ | `:2445-2461` | `dispose()` 有 live 子代理 + 窗开 ⇒ 零 close、`send` 不入队；settled + `watch{on:false}` 后的静默期一条 close、`stopped` 兑现 |
| 测试助手 | `:154-162` | `_turn()` 增 `bool? on`；`kind` 只在非 `watch` 帧发射（线上形，设计 :1786） |

**验证读数**：`flutter test test\kernel\thincoder_kernel_test.dart test\kernel\thincoder_fixtures_test.dart` = **103/103 全绿**（既有 100 + T76①–③）；`flutter analyze` 本批三档 = **No issues found**；行数：kernel **1148**（上界 1148）· kernel_test **2629**（上界 2630）· events 784 未动；`pubspec.lock` 已 `git restore`（flutter 的镜像改写不入本批）。本轮只动上述两档；`thincoder_events.dart` / `thincoder_mock.dart` / 宿主 / l10n / 固件 / 设计档 / 需求档零改动。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | `dispose()` 在 `closeEvents()` 前补 `_resolveApprovals(refuse: true)`（设计骨架 §19.2 `:1883-1902` 未列此步） | 既有用例「a disposition with an approval in flight answers it as cancelled」（`test:549-567`）要求面板走了当场答 cancelled；D66 延后后 `_teardown()` 的拒答要等轮末，不补则旧保证丢失、延后关闭要等客户端自身超时（`design:2097`「反向请求 5 分钟超时按拒绝」） | 落地（`kernel:484-485`）；**设计档缺口已披露**：建议父侧在 §19.2 dispose 骨架 + D66 理由补该行（文档笔，我不改设计档） |
| 2 | `_teardown()` 只取消 `_releaseCheck`、不清 `_releaseWanted` | 设计 `:1866` 括号句写「`_releaseWanted` 同时清」；实现沿用修正轮 3 既有形（`prepare()` 清） | 不修：可达路径均无害（`_launch` 尾 `:210` 先清、`prepare()` `:417` 清、空手守卫 `:460` 清），且 kernel 已在 1148 上界；披露给父侧按文档收紧 `:1866` |
| 3 | T76③ 未断言「`stopped` 在 dispose 时不兑现」（设计 `:2075`） | `_stopped` 初始即已完成的 `Future.value()`（`kernel:73`），只由 `_teardown()` 换成进程退出 future（`kernel:378`）⇒ 该句按现字段形**不可断言** | 以「dispose 后零 close + 窗关后一条 close + `stopped` 兑现」代偿；披露，建议父侧把设计句改成可观察判据 |
| 4 | T76① 按设计分步（settled → settle → start → `end{ok:true}` → `watch{on:false}`），并断 `activeTurn == 'auto:1'` | 设计 `:2073`；审计 🟡 指出背靠背 push 钉不住「已 settled、消化轮未起」的空档 | 落地（`test:2406-2428`） |
| 5 | `_turn()` 的 `kind` 只在非 `watch` 帧发射 | 设计 `:1786`「`kind` … 仅 `start` / `end`」；审计 🔵 | 落地（`test:159`） |
| 6 | `prepare()` 无 `_disposed` 守卫（`release()` / `send()` 有） | 评审 🔵：迟到的 `attach()`（宿主 `chat_screen.dart:308` / `workspace_bridge.dart:709`）会清掉延后关闭；可达性 `unverified` | 不修（设计未要求、kernel 在上界）；登记为后续单建议 |
| 7 | 坏形 `watch{on:非布尔}` 分支无用例 | 设计 §19.7 T76①–③ 未要求（口径来自翻译表 `:1822`） | 不补（`:613-615` 行为已实现；受 test 档行上界约束） |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮 · DEVIATIONS（1 🟡 + 2 🔵，全在测试档）** —— kernel 逐项对齐（窗位 / 谓词 / 三兑现点 / dispose 延后 / 清位 / 非布尔留痕）；🟡 = T76① 未留 settled→start 空档且缺 `activeTurn` 断言；🔵 = T76③ 缺 `stopped` 未兑现断言（不可断言，见决策 3）· watch 帧测试输入多带 `kind`。处置：🟡 与 `kind` 已修（决策 4 / 5）；`stopped` 披露不改码。审计无 shell，测试与 analyze 以本段读数为准。
- 内部 advisor 代码评审：**1 轮 · pass**（🔴 0 · 🟡 5 · 🔵 4）。🟡 全为文档 / 记录层（dispose 骨架缺审批答 cancelled · `_teardown` 清 `_releaseWanted` 口径 · T76③ `stopped` 句不可断言 · 批档 `:105` 的「`prepare()` 清」残留 · 批档 `:228` 的「复核 disposed」残留）⇒ 归父侧文档笔；🔵 中 `end{ok:true}`（#8）与 T76② 补 `activeTurn`（#9）已采纳，`prepare()` 守卫（#6）与坏 `on` 用例（#7）不修（理由见决策表）。
- **fix round：2**（审计 🟡 + 2 项测试形；评审 🔵 #8 / #9）。**终态：clean**（0 🔴、0 must-fix；全部 🟡 为父侧笔的文档 / 记录项）。

**修正轮 6（2026-10-17 · 外仓小轮：窗内轮补 `suspDriven:true`（上一轮审计发现落地）+ W9）**

外仓 = `D:\baocode\thincoder`（分支 `feat/acp-subagent-attribution`，基线 `0578ed8a`）；改动在工作树、未提交（提交归父侧）。本仓（baocode）零改动。

**交付摘要**（号 → 改动 file:line）

| 号 | 坐标 | 改动 |
|---|---|---|
| #1 suspDriven | `thincoder-cli/src/acp/suspension.mjs:100-102` | 窗包装调核改为 `runTurn(text, { ...opts, suspDriven: true })`（`autoTurn` / `upstreamTurn` 原样透传；`timerTurn` 不动）+ 两行注释（设计 §19.3-②：核 `run-stages.mjs:283` 据此把结算项留池给窗消化） |
| #2 W9 | `docs/batches/2026-10-17-acp-suspension.test.mjs:266-302`（头注 `:4-6`） | 新用例 W9：窗内自动轮与用户唤醒轮核收到 `suspDriven === true`，窗外普通回合仍 `false`；W1–W8 断言体逐字未动 |
| #3 批次档 | `docs/batches/2026-10-17-acp-suspension.md:42-50` | 追加段：watch 帧两行（窗进 `:84` / 窗退 `:164`）、W1–W8 = 8/8、suspDriven 一条（含 W9 坐标）、timer 边界登记、本轮 9/9、旧读数快照说明 |

**验证读数**

- `node --test docs/batches/2026-10-17-acp-suspension.test.mjs` ⇒ **9/9 pass**（W1–W9）。红→绿对：临时回退 `:102` 跑 W9 ⇒ 失败；恢复后 ⇒ 通过。
- `node --check` `suspension.mjs` / 测试档 ⇒ 两档 OK。
- `npm run lint`（thincoder-cli）⇒ `check-syntax: 127 file(s) OK`。
- 零改动面：本仓 `lib/**` / `test/**` / 设计档 / 需求档 / 本仓批次档；外仓新增依赖零。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | 补旗位置 = 窗包装（`startSuspension` 的 `runTurn`）而非 `session.mjs` | 核的三条起轮路径（用户输入 / 消化·上行 / timer）都经该包装；`session.mjs` 的普通回合必须保持 fallback（设计 §19.3-② 的窗外口径） | 落地；W9 同时钉窗内 true / 窗外 false |
| 2 | `timerTurn` 不动 | 派单明令；ACP 不传 `timerFace` ⇒ timer 轮不可达，`{...opts}` 原样透传 | 落地 |
| 3 | timer 交付边界（代码评审 🟡） | `suspDriven && timerWakeEnabled` ⇒ 工具轮收尾不注入到期 timer（`post-turn.mjs:23`），ACP 无 `timerFace` / 空闲闩 ⇒ 交付顺延到下一次窗外工具轮 | 已登记外仓批次档 `:48`；设计 §19.8-1 的登记属桌面仓设计档（父侧笔），本仓不改他仓设计档 |
| 4 | 设计 §19.7 W 表仍 W1–W8（无 W9） | 设计档在桌面仓，用户授权仅 thincoder 仓；设计 `:2081` 的 W1 期望本就含 `suspDriven:true`，实现已满足 | `[上抛·知会]` 父侧 / 设计笔补 W9 行 |
| 5 | 方法名 `runTurn` 与注入入参同名（代码评审 🔵） | 对象字面量方法名不产生作用域绑定 ⇒ `:102` 调外层执行器，语义正确；终端面先例叫 `driveTurn` | 不修（本轮派单 = 一行修 + 两条配套，不扩面）；留作后续可读性轮 |
| 6 | W9 沿用真实计时器泵 `flush(10)`（评审 🔵） | 共用 `flush()` 被 W1–W8 使用（派单禁改 W1–W7）；修正轮 4 已裁定该族不修 | 不修，记录 |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮 · CLEAN** —— ① 三条核起轮路径覆盖核对（timer 不可达，两型可达轮全覆盖）② W9 抓取力（漏传必红；窗内用户轮若走窗退残余补发也会红）+ W1–W7 冻结 ③ 批次档与代码 / 测试现状一致 ④ 无表外改动 / 静默简化 / 设计漂移。审计无 shell，测试读数以本段为准。附两条表外观察（设计 W 表滞后 / 外仓批次档 §6 旧读数），已分别由本表 #4 与外仓批次档 `:50` 快照说明处置。
- 内部 advisor 代码评审：**2 轮 · pass**。第 1 轮（🔴 0 · 🟡 2 · 🔵 3）：🟡 #1 timer 边界 → 已登记外仓批次档 `:48`（设计侧留父侧）；🟡 #2 设计 W 表 → `[上抛·知会]`（越仓）；🔵 #3 W9 标题超出所测 → 采纳（收窄为「核据此把结算项留池」，计时器泵不修）；🔵 #4 `runTurn` 同名 → 不修（表 #5）；🔵 #5 批次档措辞 / 坐标 / 快照 → 采纳。第 2 轮复核：修正项 Fixed / Accepted、无新增 🔴 / 🟡，结论 pass。
- **fix round：1**（评审 🔵 #3 / 🔵 #5 落地 + 🟡 #1 落档；🟡 #2 上抛；🔵 #4 有理由不修）。**终态：clean。**

**上抛 / 待裁**

1. `[上抛·知会]` 设计 §19.7 W 表需补 W9 行、§19.8-1 需补 timer 交付边界（桌面仓设计档，非本轮可写）。
2. `[上抛·知会]` 窗外用户回合仍 `suspDriven:false`（`session.mjs:106` 的 `execTurn(input, {})`）⇒「子代理在用户回合进行中结算」这一形仍走核 fallback（`run-stages.mjs:285-293` 注入并出池）⇒ 池空即不开窗 = F16 症状的最窄实例；终端面恒传 `suspDriven:true`（`tui/agent-turn.mjs:194`），两者仍有端差。落在本轮对象（窗内两型轮）之外，建议父侧登记 / 另轮。

**修正轮 6 · 订正（2026-10-17）**

- 段首「本仓 100/100 未变」应为 **103/103**：本仓最近读数是修正轮 4 实现轮（D65 / D66 + T76①–③）的 103/103（本档 §5 修正轮 4 · 实现轮「验证读数」行）；本轮未触碰本仓代码，读数不变。状态行已同刷。
- 「零改动面」应读作 **本仓 `lib/**` / `test/**` / 设计档 / 需求档 零改动**；本档 §5 按批次档纪律（该段作者 = eng-coder）由本轮写入，不在零改动之列。

**修正轮 7（2026-10-17 · 外仓小轮：窗外普通回合也带 `suspDriven:true` + W10）**

外仓 = `D:\baocode\thincoder`（分支 `feat/acp-subagent-attribution`，基线 `0578ed8a`）；改动在工作树、未提交（提交归父侧）。本仓（baocode）代码面零改动（`lib/**` / `test/**` / 设计档 / 需求档 均未动）。

**交付摘要**（号 → 改动 file:line）

| 号 | 坐标 | 改动 |
|---|---|---|
| #1 suspDriven | `thincoder-cli/src/acp/session.mjs:106-109` | 普通回合改 `execTurn(input, { suspDriven: true })`（一行改 + 三行注释：结算项留池给窗消化，与终端 `tui/agent-turn.mjs:194` 同源；否则「子代理在用户回合进行中结算」⇒ 池空 ⇒ 不开窗 ⇒ 无自动续轮 = F16 最窄漏实例） |
| #2 W10 | `docs/batches/2026-10-17-acp-suspension.test.mjs:305-316` | 新用例：窗外普通回合 `opts.suspDriven === true`、`autoTurn === false`、池空无消化轮、不开窗、无回合边界帧 |
| #2b W9（父侧裁定例外） | `:267` / `:296` | W9 标题与窗外断言随行为同步（`false` ⇒ `true`，消息「窗外普通回合同带 suspDriven:true」）；其余 W1–W8 断言逐字未动（W9 其余断言亦未动） |
| #3 外仓批档 | `thincoder/docs/batches/2026-10-17-acp-suspension.md:52-60` | 追加修正轮 7 段：#1–#3 + timer 边界改写（#4）+ `:1073` 登记（#5）+ `doc-impact --base 0578ed8a` 反查读数（#6）+ 评审补充（#7） |

**验证读数**

- `node --test docs/batches/2026-10-17-acp-suspension.test.mjs` ⇒ **10/10 pass**（W1–W10）。
- 红→绿对：临时回退 `session.mjs:109` 为 `execTurn(input, {})` ⇒ W10 断言失败（`false !== true`）；恢复 ⇒ 10/10。
- `node --check`：`session.mjs` / 测试档 ⇒ 两档 OK；`npm run lint`（thincoder-cli）⇒ `check-syntax: 127 file(s) OK`。
- 零改动面：本仓 `lib/**` / `test/**` / 设计档 / 需求档；外仓新增依赖零。

**决策透明表**

| # | 决策 / 发现 | 依据 | 处理 |
|---|---|---|---|
| 1 | W9 窗外断言改 `false` ⇒ `true` | 任务书「①改行为」与「禁止改 W1–W9」互斥；父侧回复裁定「允许改 W9 这一行，断言跟着行为走，不是放宽标准」 | 落地（`:296`，标题同步）；其余断言逐字未动 |
| 2 | `timer` 交付面随本轮归零（ACP 无 `timerFace`；核 `post-turn.mjs:23` 在全部回合跳过） | 本次改动直接后果；设计 §19.8-1 已登记 | 外仓批档 `:57` 改记；设计档 / 发布说明面归父侧 |
| 3 | 同档 `AGENT-LOOP-ASYNC-POOL.md:442` 因本轮变假（「到期仍在下一工具回合边界投递（既有语义不变）」） | 代码评审第 2 轮新发现；该行是本批 §2 ⑥ 已批准 / 已改写的行，`:58` 只登记了 `:1073` | `[上抛·待裁]` 父侧文档收口一并改（`:1073` + `:442`）；本轮不改设计档 |
| 4 | 带旗另两条副作用未登记：用户回合不再 drain 子→父在飞消息（核 `turn-loop.mjs:110`）· `injectedAdvisor` 恒假 ⇒ 回合尾一律关 advisor 线程（核 `run-stages.mjs:238` / `:283`） | 代码评审第 1 轮 🟡；与 TUI / 桌面同形、属消端差 | `[上抛·知会]` 设计 §19.3-② 影响面 / §19.8 补登记（父侧笔） |
| 5 | close/退出竞态：池内 settled 结果在 `closed` 早退径（`session.mjs:87`）无消费者；`save(agent)`（`:81`）先落盘 | 代码评审第 1 轮 🟡；窗口 = 一个 macrotask，桌面静默期 / `_watching` 有兜底 | `[上抛·待裁]` 需设计裁定（close 前按回退面收一次 ∥ §19.8 登记）；本轮不改码 |
| 6 | W10 标题收窄 + 补「不开窗」断言 | 代码评审第 1 轮 🔵 #5 / #6 | 落地（`:305` / `:314`） |
| 7 | `doc-impact` 反查读数补记 | `thincoder-cli/AGENTS.md:22`；代码评审第 1 轮 🔵 #7 | 落地（外仓批档 `:59`） |

**审计与代码评审轮次与终态**

- 内部 explore 偏差审计：**1 轮 · CLEAN** —— ① 普通回合旗与 `execTurn` 映射（`session.mjs:74`）链路成立 ② W10 抓取力（回退一行必红）与 W1–W8 冻结核对 ③ 外仓批档坐标 / 读数 / timer 边界一致 ④ 无表外改动 / 静默简化 / 设计漂移。附两条表外观察（`AGENT-LOOP-ASYNC-POOL.md:1073` 滞后 · `timerWake:false` 例外未记）已分别落档（`:58` / `:57`）。审计无 shell，测试与 lint 读数以本段为准。
- 内部 advisor 代码评审：**2 轮 · pass**。第 1 轮（🔴 0 · 🟡 4 · 🔵 3）：🔵 #5 / #6 / #7 采纳并落地；🟡 #2 落档；🟡 #1 / #3 / #4 属父侧设计 / 裁定面（上抛）。第 2 轮复核：3 项 🔵 Fixed、2 项 🟡 Accepted、2 项 🟡 Unfixed（非阻断）、新增 1 项 🟡（`:442`，上抛）；无新增 🔴 / must-fix，结论 pass。
- **fix round：1**（评审 🔵 #5 / #6 / #7 落地）。**终态：clean**（0 🔴、0 must-fix；🟡 为父侧文档 / 设计裁定面）。

**上抛 / 待裁**

1. `[上抛·待裁]` 外仓 `docs/core/design/AGENT-LOOP-ASYNC-POOL.md` 两处随本轮变假 / 滞后：`:1073`（ACP 列作 `suspDriven !== true`）· `:442`（「到期仍在下一工具回合边界投递」）；父侧收口一并改（该档在本批 §2 ⑥ 批准面内）。
2. `[上抛·待裁]` close/退出竞态（本轮新引入的「报告不落档」窄通道）需设计裁定：close 前按回退面收一次已 settle 条目 ∥ 按 §19.8 登记；本轮不改码。
3. `[上抛·知会]` 带旗两条副作用（upstream drain 收窄 · advisor 线程收尾判据）与 TUI 同形，建议设计 §19.3-② 影响面补登记。

## §6 验证与收口（父代理）

**验证读数（父侧实跑，不采信子代理自述）**

| 门 | 命令 | 读数 |
|---|---|---|
| 桌面单元 | `flutter test test\kernel\thincoder_kernel_test.dart test\kernel\thincoder_fixtures_test.dart` | **103/103 全绿**（T68–T76，含 T74①② / T75①–③ / T76①–③） |
| 桌面静态 | `flutter analyze lib\kernel\thincoder test\kernel\thincoder_kernel_test.dart` | **No issues found** |
| CLI 单元 | `node --test docs/batches/2026-10-17-acp-suspension.test.mjs` | **10/10 全绿**（W1–W10） |
| 体量 | `thincoder_kernel.dart` · `thincoder_events.dart` · `thincoder_kernel_test.dart` | **1148 / 784 / 2629**（§19.4 上界 1148 / 784 / 2630，**三者均已顶格**） |

**真机走查（用户逐条口头确认，2026-10-17）**

| # | 场景 | 结果 |
|---|---|---|
| 1 | 发指令 → 子代理 running → 切到别的**对话**再切回 | 子代理不被切断（D64 生效） |
| 2 | 子代理 running → 切到别的**项目窗口**再切回 | 子代理池子保留（D66 生效） |
| 3 | 子代理结算后（含切走期间） | **主 agent 自己说话**，用户未发任何消息（F16 主验收） |

走查期间发现并当批修掉的两个缺陷（设计侧各补一条决策）：
- D64：视图归零即释放 ⇒ 后台池被清场（08:26 用户报告）。
- D65 / D66：结算那一瞬与「起消化轮」之间的时序竞态；`dispose()` 无条件杀进程（切项目窗口）。

**测试面归属**

- 本批单元测试件 = `test/kernel/thincoder_kernel_test.dart`（T68–T76 随档）· `test/kernel/thincoder_fixtures_test.dart` + `test/fixtures/thincoder/digest-turn.ndjson`；CLI 侧 = `thincoder/docs/batches/2026-10-17-acp-suspension.test.mjs`（W1–W10，随该仓批次档）。
- **集成测试：无新增、无修订**——本批不改集成场景（既无 `test/integration` 面参与，也不新增业务路径）；发布门仍为空绿，等下一轮集成批。

**暂缓批复核**：无（本仓台账无「暂缓」标记条目；#18 手机远程已解除暂缓，属另一板块）。

**结算**

- 台账 #21（F16 挂起驱动）：待讨论 → 待设计 → 在途 → 待核销 → **已核销**，evidence 写落地坐标与本档指针。
- 提交：本仓代码 `06556be5`（kernel + events + T75/T76）· 文档随收口一笔；外仓 `thincoder` 提交见下（suspension.mjs / session.mjs / ACP-CLIENT §12.8 / 批次档 + 测试档 / AGENT-LOOP-ASYNC-POOL 两行）。
- 设计 token：收口后 `consume-design`（防复用）。

**遗留（已登记台账，不留在本档以外）**

| 项 | 说明 |
|---|---|
| 体量顶格 | kernel 1148/1148 · 测试档 2629/2630 —— 下一次触碰该面必须先拆分（会话面缝 = §18.4 候选集）或重新定预算 |
| 窗关帧丢失 | `on:false` 帧若丢（进程仍活），`_watching` 停真 ⇒ 该会话不释放，直到下一次 `_teardown`（§19.8-13 判定条件） |
| `dispose()` 延后无上界 | 卡片卡在 running 且无终态帧 ⇒ 进程不释放（§19.8-14 判定条件） |
| 窗拒绝径残余输入 | 窗内提交的 prompt 在消化轮抛错时永不回话（🟡，#75 上抛） |
| close/退出竞态 | 回合兑现与进窗 macrotask 之间 `closed` 早退 ⇒ 池内已结算条目无人消费（#78 上抛） |
| 其余带旗副作用 | 用户回合不再 drain 子→父在飞消息；advisor 线程回合尾一律关（与 TUI 同形，未登记面） |
| 后台 bash / browser / ssh | 无状态帧 ⇒ 切走仍按今天释放（§19.8-11） |

**收口结论**：F16 主验收（见上表 3）与两条派生验收（切对话 / 切项目窗口不丢后台子代理）全部走查通过；设计 D55–D66、用例 T68–T76 + W1–W10、真机三步一致。**本批收口**。
