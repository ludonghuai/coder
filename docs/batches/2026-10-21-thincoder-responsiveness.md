# 2026-10-21 · thincoder-responsiveness
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-21 · 来源 = 用户 2026-10-21 00:45「我要机制的性能体验，响应做到和 claude code 内核一样强劲，反应灵敏！」。
> 台账 = #125（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-21
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论（主 agent）

**用户诉求（逐字，2026-10-21 00:45）**：「我要机制的性能体验，响应做到和 claude code 内核一样强劲，反应灵敏！」

**为什么是现在**：今晚走查 thincoder 会话时用户感到「系统有点卡」。先排除了自动拉取（当时 `git` 进程为 0）；证实了一部分卡顿来自本轮新加的 `@` 建议（已修，提交 `ebde624d`：短查询不扫树、缓存 30s、后台刷新）。用户随即把目标抬到「与 Claude 内核同档」，即 F22。

**实测（2026-10-21 00:47，直发 ACP 帧到 `thincoder acp`，本机 D:\baocode）**：

| 阶段 | 读数 | 判断 |
|---|---|---|
| 进程启动 + `initialize` | 364 ms | 可接受 |
| `session/new`（首次） | 1545 ms | 慢 |
| `session/new`（同进程第二次） | 1507 ms | **每会话都付**，非一次性预热 |
| `session/prompt` → 首帧 | 344 ms | 快 |
| 一句话回合总计 | 3913 ms | 模型本身 |

⇒ 差距在「开一个会话要等约 1.9 秒」，不在流式；Claude 内核是同进程 isolate（无进程、无管道），所以对比感受集中在这里。

**边界（用户已定 / 需求档钉定）**：
- 验收数字以需求档 A11 为准：新建会话 ≤300 ms 可输入 · 首帧 ≤600 ms · 切内核 ≤200 ms · 同项目第二会话不付全量装配。
- 不动 Claude 内核；不做内核间会话迁移。
- 外仓 `thincoder/` 的装配瘦身只设计、不实施，等用户单独批准（B1 例外）。

**本批范围**：宿主侧（预热进程 + 乐观就绪 + 计时打点 + 回归切内核）；外仓只出设计。

**未定项**：外仓改动是否获批（影响「1.5s 装配」能否真降下来，还是只能靠宿主侧把等待藏起来）。

**用户裁定（2026-10-21 00:53）**：逐字「允许修改thincoder仓库」⇒ B1 例外批准。

- 范围：CLI 侧装配瘦身（设计档 §25.13 的 C1 模型目录懒取 / C2 MCP ∥ embedding 并行 / C3 manifest 并行或缓存），落点 `thincoder/thincoder-cli/src/acp/handlers-session.mjs` 的 `session/new` 装配段。
- 批次边界：外仓改动**另起外仓批次**（该仓自己的批次档与测试、自己的提交）；本批（宿主侧）不碰 `thincoder/` 一个文件。
- 前置：C1–C3 各占多少毫秒**未实测**（设计档 U3）⇒ 外仓批次第一步是打点分解，不许按"看起来最重"排序。
- 需求档依赖行已同步（B1 例外已批准）。
- 未定：外仓批次何时开工（本批实施后再开，还是与宿主侧并行）——待用户定。

## 外仓轮（主 agent 直接执行，2026-10-21 01:05–01:12）

**为什么由主 agent 做**：`thincoder/` 是嵌套独立仓，机制侧不允许子代理写本仓之外的文件，也不允许从本会话跨仓建批档（`batch create` 已按 fail-closed 拒绝：路径不在本仓 `docRoot.batches` 基根内）。⇒ 按「外仓改动由主 agent 在单独一轮处理」执行；本轮账记在此。

**用户裁定**：2026-10-21 01:05「外仓开工」。

**改动（4 档，外仓自己的提交，未动他人 40 改动面）**：

| 文件 | 改动 |
|---|---|
| `thincoder-core/process-probe-exec.mjs` | `batchAlive` / `batchAliveAsync` 在 win32 改走 `process.kill(pid, 0)`（`ESRCH` ⇒ 死；`EPERM` ⇒ 存在；其它异常 ⇒ `null` = 未知，维持「不得据此判死」）；POSIX 仍一次 `ps`；测试注入缝语义零改 |
| `thincoder-core/process-probe.mjs` | `probeOwnersAsync(pids, { cmdlines = true })`：会话起点传 `false` ⇒ 不发命令行探测；存活但无命令行 ⇒ `ownerState` = `unknown` ⇒ 保守保留（方向不变） |
| `thincoder-core/session-lifecycle.mjs` | `newSession` 的属主探测改 `{ cmdlines: false }` —— 命令行探测离开建会话热路径 |
| `thincoder-core/agent/assemble.mjs` | `gitAuthor()` 进程级缓存（每次装配一个 `git` 进程 = 71 ms） |

**读数（改前 → 改后，同一台机器）**：`batchAliveAsync` 658 ms → **0 ms** · `probeOwnersAsync(cmdlines:false)` **0 ms** · `session/new` 1501 ms → **189 ms** · 进程启动到可用会话 1909 ms → **657 ms**（`init` 468 + 新会话 189）。
**回归**：外仓批测试 `rewind 7/7` · `cleanup-defects 2/2` · `session-governance-a1 fail 0`；`thincoder-core` / `thincoder-cli` 的 `test/run.mjs` 自报「manifest 为空 = 零测试即绿（2026-09-28 全量重置）」。
**保守方向已验**：`ownerState(自身 pid, 无命令行)` = `unknown`（保留）· `ownerState(死 pid)` = `dead`（可清理）——死属主清理仍在，只有「活但身份不明」的条目改为保留。

**未做 / 留给后续**：
- 外仓批档：本会话无法在 `thincoder/` 建记录（跨仓被拒）⇒ 若要在该仓留账，需以 `thincoder/` 为锚开会话后补建。
- 命令行探测本身（633 ms）没被删除，只是离开热路径；`peerInstances` 等读面仍会用到，是否再优化留观测。
- 外仓工作树另有 40 个与本轮无关的既有改动（他批/他人），未触碰、未提交。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（修正轮 1 已落（评审 14 条 R1–R14 + M1 实测前提修正；设计档 §25 与本节同拍））
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**设计档落点**：`docs/design/thincoder-adapter.md` §25（新增，含 §25.1–§25.15）。

**本批条目（覆盖）**

| # | 条目 | 需求回指 | 动作 | `file:line` 落点 | 预期结果 | 验收 |
|---|---|---|---|---|---|---|
| B1 | 预热池（新档） | F22 / A11① | 新增 `ThincoderWarm`：`warm(cwd, files)` / `take(key)` / `drop(reason)` / TTL 10min / 失败冷却 60s / 进程退出自清 | `lib/kernel/thincoder/thincoder_warm.dart`（新增，~+170） | 打开项目即 spawn + `initialize`；进程无会话、不占槽 | T108 / T109 |
| B2 | 内核领池 | F22 / A11① | `_launch` 拆「领池 ∥ 照旧起」；领到则跳过 spawn + `initialize`，从 `_openSession` 起跑；`_ensureStarted` 签名不变 | `thincoder_kernel.dart:220-297`（领池点 `:231`） | 领池命中 ⇒ 少付 ≈364ms | T108；`timing: warm hit` |
| B3 | 预热触发与释放 | F22 / A11① | 打开项目（默认内核 = thincoder）调 `warm`；项目切换 / 关项目 / 进后台调 `drop`；`release()` 后不立即补位 | `workspace.dart:239-240` 邻近（行号实施首轮核定） | 池随项目生命周期；不进 `_canClose` 判据 | 走查 S1 / S4 |
| B4 | 乐观就绪可见面 | F22 / A11① | 起内核期间「准备中」可见：优先既有 `starting` 呈现；缺 ⇒ `NoticeItem(warning)` + ready 时 `ItemRemoved` | `thincoder_kernel.dart:229` / `:270`；`chat_session.dart:693` 旁读 `preparing` | 未就绪不表现为「发不出去」；等待可见 | T107 |
| B5 | 打点 5 处 | F22 / A11 全项 | `timing: open` / `input-ready` / `warm hit|miss` / `session-new` / `first-frame` / `kernel-switch`，每迁移一行 | `chat_session.dart:402` / `:435`；`thincoder_kernel.dart:229` / `:231` / `:270` / `:415` / prompt 发出处 `:697`+首内容帧 | 真机可读、可取证 A11 四项 | T110；走查 S1–S3 |
| B6 | 切内核只读数 | A11③ | `setKernel` 记 t0、新内核 ready 记 t1；实现零改 | `chat_session.dart:435-455` | 读数 ≤200ms；无回归 | T111 |
| B7 | 第二会话装配 | A11④ | **宿主侧不可达**：只省 364ms（池命中）；1545ms 装配归 CLI ⇒ 设计档 §25.13 C1–C3 列 B1 待批 | 设计档 §25.4 / §25.13 | 走查记「未达标，待 B1」，不伪造绿 | 走查 S2 |
| B8 | 测试 | A9 / A11 | T107–T111；池单测不启真进程 | `test/kernel/thincoder_kernel_test.dart`（+≤150）· `test/kernel/thincoder_warm_test.dart`（新增 ~+110） | 全绿；`flutter test test/kernel` 228/229 基线不破 | — |
| B9 | 外仓 | F22 依赖 | **只设计不实施**，B1 待批（C1 模型目录懒取 / C2 MCP ∥ embedding 并行 / C3 manifest 并行） | `thincoder/thincoder-cli/src/acp/handlers-session.mjs:285` 起 | 本批一行不写 `thincoder/` | — |

**受影响文件**：新增 `lib/kernel/thincoder/thincoder_warm.dart`、`test/kernel/thincoder_warm_test.dart`；修改 `thincoder_kernel.dart`(+≤55) · `chat_session.dart`(+≤14) · `workspace.dart`(+≤12) · `composer.dart`(0~+6) · `test/kernel/thincoder_kernel_test.dart`(+≤150)。零改：`thincoder_protocol.dart` / `thincoder_events.dart` / `thincoder_mock.dart` / `lib/kernel/claude_code/**` / `thincoder/`。

**验收对照（A11 四项，诚实口径）**：① ≤300ms 可输入 = 可达成（输入面不看健康位，`chat_session.dart:693` 实读）；② 首帧 ≤600ms = **条件达成**（打字时间 ≥ 装配剩余时间；300ms 内即发 ⇒ 下界 ≈1.6s，无条件达成需 B1）；③ 切内核 ≤200ms = 既有 `fe403e32` 温启动，只加读数；④ 第二会话不付全量装配 = **宿主侧不可达**，待 B1。交付报告不得合并成「全部达标」。

**关键决策**：D100 池键 `(cwd, hasFilesCapability)` · D101 触发 = 打开项目 · D102 不做单进程多会话 · D103 复用 §18 队列 · D104 预热失败静默 + 冷却 · D105 打点只在迁移处 · D106 A11④ 判不可达不伪造。

**复用的既有机制**：§19 挂起窗释放判据（`_canClose` 四条件零改）· §18 队列（`send`→`_queue`→`_drain`→气泡先落 `:653`→`await _ensureStarted` `:680`）· `fe403e32` 切内核温启动（`_warm` 表 `chat_session.dart:440`）。

**上抛项**

| # | 项 | 现状 | 待裁 |
|---|---|---|---|
| P1 | 外仓 B1 例外（CLI 侧装配瘦身，§25.13 C1–C3） | 本批只设计；A11④ 无条件达标依赖它 | 用户批准后才另立 out-of-repo 批；本批不实施 |
| P2 | 首帧 ≤600ms 的无条件达成 | 宿主侧上界 ≈1.6s（300ms 内发首条时） | 与 P1 同一裁定：批准 B1 后由外仓批补齐；不批准 ⇒ A11② 按条件达成记 |

**未核实**（实施首轮核，设计档 §25.15）：U1 composer 健康门 · U2 starting 呈现 · U3 装配分解 · U4 池内存 · U5 `workspace.dart` 预热接缝行号。

**补记（计数与未核实项校正，同节内）**

- B5 的打点计数按设计档 §25.6 的事件表为准 = **7 处**（内核侧 5：`:229` / `:231` / `:270` / `:415` / 首个内容帧；宿主侧 2：`chat_session.dart:402` / `:435`），上文「5 处」为内核侧小计。
- 追加未核实项 **U6**：`ChatSession.isStreaming` 的定义处未定位（本批实读只确认 `chat_session.dart:693` 的表达式 `!isStreaming || canQueue`），故「起内核期间可输入」的最终判据 = T107 的行为断言与真机 `timing: input-ready` 读数；若实施首轮发现 `isStreaming` 在 starting 期间为真 ⇒ 按设计档 §25.3-1 的同一原则处置（放宽为只看能否发送），并回报设计档 §25.15 增项。

**修正轮 1（评审 14 条 + M1 实测前提修正；2026-10-21 00:58–01:10）**

本块取代上表中 B3 / B4 / B7 / B9 四行与 P1 / P2 两行的表述（以本块为准，设计档 §25 已同拍改写）。

- **M1（前提修正）**：`session/new` 实测 1501 ms = `newSession`（认领槽）**1358 ms**（属主探测：`tasklist` 658 + PowerShell CIM 633）+ `createSession`（含 `assembleAgent` 95 ms）**138 ms** + 余 ≈5 ms；模型目录**早已后台**（`acp.mjs:97-111` 不 await `refreshModelChoices`）⇒ 旧稿「装配 1545 ms」不成立，C1（模型目录懒取）无收益，已撤。判活替代实测：`process.kill(pid, 0)` 0.19 ms/pid。
- **B3（R5 收正）**：预热触发 = **打开项目**；释放 = 项目切换 / 关项目；`release()` 后不补位。「应用进后台关池 / 回前台补位」**本批删除**，登记为条件项（设计档 §25.12-8）。
- **B4（R10 收正）**：等待面 = `NoticeItem(warning, 'thincoder is starting…')`（唯一路径；宿主侧无 `starting` 呈现，`health_banner.dart:27-28` 只在 `failed` 显示）；删掉 `bool get preparing` 投影，文案登记设计档 §14-29。
- **B7（M1 改写）**：A11④ **宿主侧不可达**（受理 364 ms 池命中）；1501 ms 里 1358 是属主探测、138 是装配 ⇒ 归**已批准的外仓批** C′1+C′2，落地后判据 = `timing: session-new` ≤400 ms。
- **B9（M1 改写）**：外仓清单改为 **C′1**（Windows 判活改 `process.kill(pid,0)` 批量查表，保留 unknown ⇒ 不认领不判死 + 注入缝，≈658 ms）· **C′2**（`probeCmdlinesAsync` 只在 pid 复用复核身份时发；死属主清理移出热路径，≈633 ms）· **C′3**（`git config user.name` 缓存 / 读 `.git/config`，≈71 ms）。
- **P1（R1 收正）**：外仓 B1 例外 **已获用户批准（2026-10-21 00:53，逐字「允许修改thincoder仓库」）**，落点 = 独立外仓批；A11④ 归属 = **外仓批交付**（不再写「无人认领」）。
- **P2（R1 收正）**：首帧 ≤600 ms —— 本批**条件达成**；**无条件面归外仓批**（C′1+C′2 后：预热命中 0 + 装配 138 + 首帧 344 ≈ 482 ms）。
- **U6 关闭（R14）**：`isStreaming` = `lib/chat/chat_session.dart:687` 的 `_transcript.activeTurn != null`；`canQueue` 在 `:651`（`_kernel is QueuesMessages`）⇒ starting 期间 `canSend` 为真，§25.3 前提成立。
- **R2 / R3 / R6–R9 / R11–R13**：设计档 §25 内已落（领池交整条 `ThincoderConnection`、预热键 == 内核领池键、事件名统一 `timing: *`、`input-ready` 固定 t0/落点、`warm: held` 入表、走查步骤 6 改写、索引补批 16、拆分立场一句话、时钟 / transport 工厂可注入）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

**评审对象**：设计档 `docs/design/thincoder-adapter.md` §25（批 16 / F22）∥ 回指需求档 F22 + A11 ∥ 批档 §2 任务表。对象状态 = 待评审；触发 = 用户 2026-10-21 00:54「评审」。

**结论摘要**：设计可信且可实施——先例行（§25 对齐①–④ / 偏离①② 均带理由）、survey-evidence 行（:3321「公开资料本批未查」+ 已查仓内/外仓坐标 + 结论）齐全；受影响档行数经抽核（`thincoder_kernel.dart` 1353、`chat_session.dart` 1324、`workspace.dart` 2940、`composer.dart` 2416 实测）与设计标注一致；`canSend`（`chat_session.dart:693`）/ `_warm`（`:435-455`）两条承重事实实读成立。无 🔴。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Requirements / Coordination | 🟡 | B1 批准状态两个方向并存：设计 §25.13:3485 标题写「B1 待批」、§25.10:3460 记「④ 判不过（待 B1）」；需求档 :155 记「B1 例外已获用户批准 2026-10-21 00:53」，批档 §1:36 有同一裁定逐字，而批档 §2:45 / :76 仍把 P1 / P2 记为「待裁」⇒ A11②④ 的外仓交付无人认领 | 把 00:53 裁定同步进 §25.13 / §25.10 与批档 §2 的 P1 / P2；逐项写明 A11 四项的交付归属（①②③ 宿主批 · ②无条件面与④ 外仓批） |
| 2 | Feasibility | 🟡 | 领池交接对象未定：§25.2:3353 写「直接拿 transport + 已存 handshake」，但 T108（:3467）要求 `initialize` 只出现 1 次 ⇒ 池侧已持有一条连接；而 `thincoder_protocol.dart` 列为零改动（:3434）⇒ 内核再用同一 transport 新建 `ThincoderConnection` 即变成对已消费 `messages` 流的第二个订阅 | 写明 `take()` 交的是 `ThincoderConnection`（或 `{connection, handshake}`），以及 `_launch` 如何直接领用它；T108 的断言改为「领用的连接上不再出现 `initialize`」 |
| 3 | Feasibility | 🟡 | 预热键的能力位在打开项目侧无来源：键 = `(cwd, hasFilesCapability)`（:3358），该位在内核侧由 `_context.files` 决定；而 `ThincoderWarm.warm(cwd, files)` 由 workspace 调（:3429），那里没有 `KernelContext` | 指定 workspace 侧该判据的取法（与内核同一表达式），并补一条断言/用例钉住「warm 键 == 内核领池键」；否则每次都 miss，A11①② 白丢 364 ms |
| 4 | Affected-file annotation | 🟡 | `composer.dart` 行（:3430）括号里写的是代码位置「2126 附近」而非本档现存行数，且该档未进 §25.8 的体量段（:3435）；实测该档 2416 行，属 >800 | 改成「（2416）」，并把它并入 >800 立场段（或明写本批 delta 恒 0、结构不变） |
| 5 | Affected files / coverage | 🟡 | 生命周期触发无落点：§25.2:3350「应用进后台 ⇒ 关池」与 :3362「应用从后台回到前台且池空 ⇒ 补位」，但 §25.8 只列 workspace 的打开/切换/关闭（:3429），无 app 生命周期钩子，T109 也未覆盖进后台 drop（批档 §2:56 同样把「进后台 drop」派给 workspace） | 点名承载该钩子的档并补进 §25.8 与 T109；若不打算做，则从 §25.2 删掉这两个触发（补位只留「打开项目」） |
| 6 | Clarity | 🟡 | 打点事件名两套并存：§25.3:3370 `acp.input-ready`、§25.5:3387 `acp.kernel-switch` vs §25.6:3397/:3401 `timing: input-ready` / `timing: kernel-switch`、§25.10:3454 `timing: input-ready`——A11 是「真机 appEvent 计时为证」，走查按名 grep | 统一到 §25.6 的一张表（该表自述「供实施与走查共用」），在 §25.3 / §25.5 / §25.10 改成同名 |
| 7 | Clarity | 🟡 | `input-ready` 无 t0 与落点的配对口径，且给了两个候选触发点（:3397「`thincoder_kernel.dart:229`……或 attach 同帧」）；同一张表的 `first-frame` 有明确配对口径（:3404） | 照 `first-frame` 的写法固定：t0 = `timing: open`（attach，:3396），落点 = 首个可发送帧，且只保留一个触发点 |
| 8 | Consistency | 🟡 | 走查与机制互打：§25.14-1:3500 要 `events.log` 有 `warm: held`，但 §25.6（:3394-3402）只定义 `warm: dropped`；§25.14-6:3505 写「若池已被 TTL 关闭则付全量启动」，而 §25.2:3362 规定 release 后不补位 ⇒ 池必空，全量启动与 TTL 无关 | `warm: held` 补进 §25.6（或改走查期望为 `warm hit` / `warm: dropped`）；步骤 6 改写为「release 后池空 ⇒ 下一次开会话付全量启动，属预期」 |
| 9 | Clarity / UI + l10n | 🟡 | 等待面悬在 U2 上并给了中文硬字面量：§25.3-2:3371「优先用既有 `starting` 现成呈现；若……未核实 U2）则发 `NoticeItem(..., '正在准备内核…')`」。实读：宿主侧无任何消费 `KernelHealthStatus.starting` 的分支（`health_banner.dart:27-28` 只在 `failed` 显示；全仓仅 `ready` / `failed` 比较）⇒ 回退路就是实际路径；中文内核通知又与 §14-28:571「内核口英文」冲突，且无 l10n 键 / §14 登记项 / §25.8 的 ARB 行 | 用上面的实读结论关掉 U2，把 `NoticeItem` 定为唯一路径并给文案一个归属：要么加 l10n 键（+§25.8 补两源档/生成档行），要么英文 + 在 §14 登记（形同 §14-28） |
| 10 | Scope | 🟡 | `bool get preparing`（:3427）无点名消费者、无用例；§25.3-2 选定的路径（`NoticeItem`）也不需要它（批档 §2:57 只说「旁读 `preparing`」不指读者） | 点名读取它的宿主面并补一条用例，或从受影响文件与投影面删掉它 |
| 11 | Doc state | 🟡 | 本档自身的索引停在上一批：头部分批行（:5）止于批 15、状态日期（:7）仍写 2026-10-19、§7 验收对照表（:396-398）止于 F21 且汇总行写「F1–F7、F10–F20」、§9/§10/§11 的逐批指针（:457 / :474 / :490）止于批 14——§25 在正文而进不去索引 | 补批 16 行：分批行、状态日期、§7 增 F22 行并把汇总行改成实际覆盖，§9/§10/§11 各加一条「批 16 见 §25」 |
| 12 | Size stance | 🔵 | 本批触碰四个已在 >800 的档（`thincoder_kernel.dart` 1353⇒≤1408，含 `_launch` 的结构性拆分 :3426；`chat_session.dart` 1324⇒≤1338；`workspace.dart` 2940⇒≤2952；测试 3644⇒≤3794），沿用的是 §5.2（:335）已裁「不续拆」立场，本批无拆分方案 | 维持立场即可，但请显式写一句「`_launch` 拆分不动任何缝候选、触发仍归独立拆分批」；属已裁债务，不阻断 |
| 13 | Test determinism / seam | 🔵 | T109① 依赖 10 min TTL、T107 依赖 800 ms 工厂延迟，而 T110 假定「假时钟 344 ms」（:3469）；池的假 transport 工厂只在 :3432 提到「注入」，未写默认回落形 | 把时钟 / 定时器与 transport 工厂都做成可注入参数（或模块级 setter + `??` 生产缺省，`finally` 复位），池单测不依赖墙钟 |
| 14 | Batch-record drift | 🔵 | 批档 §2:84 的 U6 仍记「`isStreaming` 定义处未定位」；实读已可关：`lib/chat/chat_session.dart:687` = `_transcript.activeTurn != null`，`canQueue` 在 `:651`（`_kernel is QueuesMessages`）⇒ starting 期间 `canSend` 为真，§25.3 的前提成立 | 在批档 §2 关闭 U6，并把该项并入设计 §25.15 的 U 表（现只到 U5） |

**计数**：🔴 0 · 🟡 11 · 🔵 3。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（主 agent 记录）

**用户裁定（2026-10-21 01:03）**：逐字「批准」⇒ 批 16 **宿主侧实施**获批。

| 项 | 批准范围 |
|---|---|
| 实施面 | `lib/kernel/thincoder/thincoder_warm.dart`（新档）· `thincoder_kernel.dart`（`_launch` 拆领池/照旧 + 打点）· `chat_session.dart`（`timing: open` / `kernel-switch`）· `workspace.dart`（打开项目预热） |
| 测试 | T107–T111（含 `thincoder_warm_test.dart`，不启真进程） |
| 依据 | 设计档 §25（修正轮 1 已落）· 批档 §2 任务表 B1–B8 · 需求档 F22 / A11 |
| 明确不含 | 外仓 `thincoder/`（C′1–C′3 归独立外仓批，等用户另批）· Claude 内核 · 队列/审批/取消语义 · `preparing` 投影 |

前提已核对：设计评审通过（🔴 0 · 🟡 11 · 🔵 3，§3 在册）· 14 条发现修正落地并经主 agent 核验 · 机检门 PASS · 设计档已提交 `f3c1f373`。

## §5 实施记录（eng-coder）

**实施记录（eng-coder · 2026-10-21 01:05–02:40）**

**状态行**：实施完成（宿主侧 B1–B8 落地；4 条「设计与代码不符 / 口径」见下，待裁定）

### 改动清单（file:line）

| 档 | 落点 | 改了什么 |
|---|---|---|
| `lib/kernel/thincoder/thincoder_warm.dart`（新增，227 行） | 全档 | `ThincoderWarm`：`warm(cwd, files:)` / `take(key)` / `drop(reason)` / `cwd`；键 = `(cwd, files)` 与内核同一表达式；TTL 10 min（注入时钟 + 注入 `_schedule`，不读墙钟）；失败冷却 60 s；`exited` 自清；`take` 交整条连接 + transport + 握手回包 |
| `lib/kernel/thincoder/thincoder_kernel.dart:247-278` | `_launch` | 先领池（`:247`）再照旧起：命中⇒不 spawn、不再 `initialize`，握手回包走 `_handshake(warm.handshake)`；`:248-250` 打 `timing: warm hit|miss` |
| 同档 `:219-226` | `_setHealth` | 离开 `starting` 时撤等待行（`ItemRemoved _startingId`） |
| 同档 `:437-445` | `_openNew` | `timing: session-new <N>ms` |
| 同档 `:705-708` | `_deliver` | 回合等进程时发 `NoticeItem(warning, 'thincoder is starting…')`（一次） |
| 同档 `:724-726` | `_deliver` | `timing: first-frame` 起飞点（prompt 写出前一行） |
| 同档 `:1169-1190` | `_sayWaiting` / `_noteFirstFrame` / `_content` | 等待行发一次；首个内容帧落点（`usage_update` / `config_option_update` 不计） |
| 同档 `:1199` | `_notification` | 每帧先过 `_noteFirstFrame`（只读一次即弃，无逐帧日志） |
| `lib/chat/chat_session.dart:405-409` | `attach` | `timing: open`（t0）与 `timing: input-ready <N>ms`（首个可发送帧；U1 实读 `_canSend` 只看内容） |
| 同档 `:443-471` | `setKernel` / `_readSwitch` / `_apply` | `timing: kernel-switch`：setKernel 记 t0，新内核 ready 时落 t1（温内核当下、冷内核首个 `KernelInfoChanged`） |
| `lib/workspace/workspace.dart:443` / `:447-454` / `:1303` | `_openProject` / `_warmThincoder` / `hideProject` | 打开项目（默认内核 = thincoder 且本机）调 `warm(path, files: true)`；别的情形 `drop('project-switch')`；关项目（`hideProject`，且池正服务该 path）`drop('project-closed')` |
| `test/kernel/thincoder_warm_test.dart`（新增，256 行） | 全档 | 8 条：只起一次 + 握手一次、TTL、exited、能力位、drop、只有一个、失败冷却、交接后连接归内核 |
| `test/kernel/thincoder_kernel_test.dart:4243-4546` | `responsiveness (F22)` 组 | T107①/②、T108、T108②、T110、T111（6 条），另 `_NoTimer` 假定时器 |

零改动（如设计）：`thincoder_protocol.dart` · `thincoder_events.dart` · `thincoder_mock.dart` · `composer.dart`（U1 实读：发送键 `enabled: _canSend` 只看内容，无健康门）· `agent_kernel.dart` · `thincoder/`。

### 打点事件（grep 可列全，9 个名字形态）

`timing: open`（chat_session.dart:406）· `timing: input-ready`（:409）· `timing: warm hit` / `timing: warm miss`（kernel:250 / :249）· `warm: held`（warm:215）· `warm: dropped`（warm:156 / :224）· `timing: session-new`（kernel:445）· `timing: first-frame`（kernel:1183）· `timing: kernel-switch`（chat_session:470）。

### 测试读数

- `flutter test test/kernel/thincoder_kernel_test.dart`：**147/147 绿**（既有 141 + 新 6）。
- `flutter test test/kernel/thincoder_warm_test.dart`：**8/8 绿**，不启真进程（注入假 transport 工厂）。
- `flutter test test/chat`：543/543 绿；`test/workspace_test.dart`：25/25 绿。
- `flutter analyze lib/kernel/thincoder lib/chat/chat_session.dart lib/workspace/workspace.dart`：No issues found。
- 全量 `flutter test`：其余失败档为 Windows 路径分隔符 / 渲染环境既有失败（例：`kernel_test.dart` Volta 用例在 **stash 掉本轮改动后仍失败**，已实测）。

### 行数实测（对照预算）

| 档 | 实测 | 预算 | 结论 |
|---|---|---|---|
| `thincoder_warm.dart` | 227 | <300 | ✅ |
| `thincoder_warm_test.dart` | 256 | <300 | ✅ |
| `thincoder_kernel.dart` | 1408 | ≤1408 | ✅ |
| `workspace.dart` | 2952 | ≤2952 | ✅ |
| `chat_session.dart` | 1340 | ≤1332 | ❌ +8（见不符项 ①） |
| `thincoder_kernel_test.dart` | 4609 | §25.8 行 ≤3794 | 设计基线过期（见不符项 ④） |

### 设计与代码不符 / 实现口径（待主 agent 裁定）

1. **`chat_session.dart` 预算不可达**：§25.8 行 ③ 写 ≤ +8（⇒ ≤1332）。三处打点的事实成本：import `event_log`（1）+ `_switching` 字段（1）+ `_apply` 一行（1）+ `attach` 三行（3）+ `setKernel` 两行（2）+ `_readSwitch` 六行（6）≈ +14，已压到 +16（含空行）。要进 1332 只能删掉 `timing: kernel-switch`（A11③ 的唯一读数）——按「不静默降级」选前者，请裁定改预算或接受 +8。
2. **`timing: kernel-switch` 的 t1**：§25.5 与 §25.8 行 ② 把 t1 定在 `_setHealth(ready)`（kernel:270 附近）。但切回被 `_warm` 保留的内核时 `prepare()` 走 `_ensureStarted` 的 `_running` 短路（kernel:222），**没有 health 迁移** ⇒ 该行永不落（T111 要求「每个方向各一行」）。落地：ChatSession 在 `setKernel` 记 t0、在新内核 ready 时落 t1（温内核在 setKernel 末尾即落，冷内核在首个 `KernelInfoChanged` 落）；语义与 §25.5 的配对一致，读数位置在 `chat_session.dart:466-471`。
3. **等待面的发点**：§25.3-2 字面写「在 `_setHealth(starting)` 处发 `NoticeItem`」。代码事实：`kernelLocked = _transcript.length > 0`（`chat_session.dart:423-424`）——任何一条 Notice 都让会话算「已开始」，于是 `_apply` 里 `if (kernelLocked) _dropWarm()`（`:203`）会在每次起内核时丢掉 `_warm` 保留的内核，`setKernel` 也被 `kernelLocked` 挡住 ⇒ 破坏 §25.5 温切内核（T111）与内核选择器。故按 §25.3-2 自己的条件句（「首条消息的回合已经开着」）落点改为：`_deliver` 里、`await _ensureStarted()` 之前发（仅当 `_health != ready`），`_setHealth` 离开 starting 时撤。零回合的准备期不显示等待行（也避开 `kernelLocked`）。
4. **测试档行数**：§25.8 行 ⑦ 记 `thincoder_kernel_test.dart`（3644）⇒ +≤150 ⇒ ≤3794；实施首轮实测基线 **4299 行**（编制日读数过期），本轮 +310 ⇒ 4609。任务书验收 ⑥ 未列该档。
5. **`warm miss` 前缀**：§25.6 单元格写 `timing: warm hit <N>ms` / `warm miss`（后者无前缀）。实现统一为 `timing: warm miss`（与 hit 同族）；`warm miss` 仍是子串，两种 grep 都命中。

### 未核实项 U4（已量）

`thincoder acp` 起进程 + `initialize` 应答后、无会话：node 工作集 **79.2 MB**（私有 51.6 MB），低于设计阈值 ~120 MB ⇒ 池保持默认开（不改按需预热）。

### 边界（本批不做，随设计）

- `deleteWorkspace`（删工作区）不 drop：池靠 10 min TTL 收；`hideProject` 覆盖「关项目」主路径。
- 恢复上次项目（`load()` → `create()`）不预热：D101 已否「应用启动即预热」。

### 外仓

本会话对 `thincoder/` 零写（无任何工具调用指向该目录）；主仓 `git status --short thincoder/` 输出为空。`git -C thincoder status` 里另有一轮未提交改动（`thincoder-core/agent/assemble.mjs`、`process-probe*.mjs`、`session-lifecycle.mjs` 等，mtime 01:05 之后）——非本轮所为，属并行外仓批。

**修正轮 1（内部 explore 差异审计 + advisor 代码评审之后的自我修正）**

- **🔴 已修（advisor 第 1 条，真实路径必 miss）**：应用里「打开项目」就是 `openFolder` = `create(project: _openProject(path))`（`workspace.dart:403`）——`_openProject` 在 `:443` 调 `_warmThincoder` 后**立刻**建会话，视图 `attach()`（`chat_screen.dart:314`）→ `prepare()` → `_launch` 的领池（当时 `kernel:247`）发生在池的 spawn + `initialize` 之前（`_heldAt` 要等回包，`warm:211`，实测 `initialize` 364 ms）⇒ `take` 必返回 null、`timing: warm miss`，364 ms 没省下，还多留一个 Node 进程（U4 79.2 MB）到 TTL；原 T108 先 `await warm()` 再 `prepare()`，恰好绕过了这条竞态。另外 `_openProject` 的调用点只有 4 处（`:403` 开文件夹 / `:409` 换新会话目录 / `:809` 新窗口会话 / `:1596` 建工作区）⇒ 「点已列出的项目 / 点已有会话」根本不预热（D101 的边界，见下）。
- **修法**：新增 `ThincoderWarm.takeWhenReady(key)`（`warm:155-164`）——同一 key 的预热在途 ⇒ 等它（最多 `startup` 30 s，会话本来也要付这段启动），领到即交接；别的 key 不等。`_hold` 的 spawn 加同额超时（`warm:198`），防一次挂死的 spawn 把池永远卡住（advisor 第 12 条）。`kernel._launch` 改为 `await ThincoderWarm.instance.takeWhenReady(...)`（`kernel:247`），`timing: warm hit <N>ms` 现在读的是「等池 + 领池」的实际耗时（不再恒 0，advisor 第 5 条顺势关掉）。
- **测试同步**：T108 改成真实顺序（`unawaited(warm)` + 立刻 `prepare()`，池的 start 用 gate 卡住）⇒ 断言：会话自己的进程 0（`s.agents` 空）、池进程 1、`initialize` 1、`session/new` 1、`warm: held` 1、`warm hit` 1、`warm miss` 0；`thincoder_warm_test.dart` 增「在途 start 被等到并交出去」一条。两档共 **156 绿**，analyze 无 issue。
- **explore 审计 11 条**（🔴0 · 🟡4 · 🔵7）处理：代码侧已修 `_endTurn` 清 `_firstFrame`（陈旧起点，advisor 第 6 条同源）；其余为**设计档坐标/数字漂移**（§25.3-2 发点、§25.5/§25.6 的 `kernel-switch` 坐标、§25.8 行数、§25.6 `warm miss` 写法、§25.15 U1/U4/U5 回填）——属设计档作者笔域，清单进交付报告，`§6` 收口时按清单改。
- **未采纳（🔵，理由在交付报告）**：`timing: open` / `input-ready` 未按内核 gate（`chat_session.dart` 已超预算 8 行；且这两行正是跨内核对照的同一读数）；T110 用真 `Stopwatch` 断言 ≤600（无注入时钟缝，`kernel` 侧不加时钟参数）；`files: true` 硬编码（workspace 每个 `KernelContext` 都传 `IdeKernelFiles`，就地注明）。
- **行数复测**：`thincoder_kernel.dart` 1408 · `thincoder_warm.dart` 242 · `workspace.dart` 2952 · `chat_session.dart` 1340 · `thincoder_warm_test.dart` 284 · `thincoder_kernel_test.dart` 4617。

## §6 验证与收口（父代理）

## 验证与收口（主 agent）

**交付物**：`thincoder_warm.dart`（新，242 行）· `thincoder_kernel.dart`（1408，贴预算）· `chat_session.dart`（1340）· `workspace.dart`（2952，贴预算）· `thincoder_warm_test.dart`（新，284）· `thincoder_kernel_test.dart`（4617）；外仓 4 档独立提交。

**读数（我自己跑的，不是转述）**：

| 项 | 命令 | 结果 |
|---|---|---|
| 本批两档 | `flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_warm_test.dart` | **156 passed** |
| 广域回归 | `flutter test test/kernel test/chat test/ide/workbench test/workspace_test.dart` | **1145 passed / 2 failed**，两条均有账（见下） |
| 静态 | `flutter analyze lib/kernel/thincoder lib/chat/chat_session.dart lib/workspace/workspace.dart` | **No issues found** |
| 外仓零写 | `git status --short thincoder/` | **空** |
| 机检门 | `doc_check gate`（设计档 + 需求档） | **PASS**，0 命中 |
| 外仓有效性 | 改前/改后直发 ACP 帧 | `session/new` **1501 → 189 ms**；进程启动到可用会话 **1909 → 657 ms** |

两条红：① `dart_core_e2e_test.dart` 的 diff 行 = 既知 **#122**（与本批无关）；② 同档 `:101` `PathAccessException: Deletion failed …\Temp\baocode-core-e2e-*` = Windows 临时目录锁，测试卫生问题，**非本批回归**，登记 #128。

**裁定（设计评审后实施期上抛 5 条 + 降级 4 条）**：

| # | 上抛项 | 裁定 |
|---|---|---|
| 1 | `chat_session.dart` 1340 > 设计预算 1332 | **接受 1340**：另一条路是删掉 `timing: kernel-switch`（A11③ 唯一读数）⇒ 改预算不改读数。设计档 §25.8 ③ 已同步 |
| 2 | `timing: kernel-switch` 的 t1 在内核 vs 宿主 | **按代码**：切回 `_warm` 保留内核时 `_ensureStarted` 走 `_running` 短路、无 health 迁移 ⇒ 内核落点永不触发。设计档 §25.5/§25.6 已收正 |
| 3 | 等待面发点 `_setHealth(starting)` vs `_deliver` | **按代码**：`kernelLocked = _transcript.length > 0` 会把 Notice 计成「会话已开始」⇒ 每次起内核丢温存内核并挡住 `setKernel`。设计档 §25.3-2 已写理由与代价 |
| 4 | 测试档基线 3644 vs 实测 4299 | **按实测**改 §25.8 ⑦（⇒ 4617） |
| 5 | 预热只在 4 个 `_openProject` 调用点（「启动后点已有会话」不预热） | **不在本批扩**（D101 明确否掉「启动即预热」）；作为产品决定登记 **#126** 待用户定 |

**父侧直接执行（机械修正，可回退）**：设计档 §25.3-2 发点一句 · §25.5 t1 落点一句 · §25.6 kernel-switch 行 · §25.8 ③ 预  

算数字 · §25.8 ⑦ 测试行。均为坐标/计数/一句事实，无语义新增。

**诚实口径（未达标项）**：
- **A11② 首帧 ≤600 ms**：条件达成（打字时间 ≥ 装配等待时成立）；无条件达成需外仓批落地后复测。
- **A11④ 同项目第二会话不付全量装配**：宿主侧只能省进程启动（池命中），装配仍由 CLI 的 `session/new` 决定——外仓批已把该项从 1501 降到 189 ms，判据 `timing: session-new ≤400` **本轮已满足**（实测 189），但因属外仓交付，按设计口径记为「外仓批达成」。
- **降级项**（未做，已登记）：`deleteWorkspace` 不 drop 池（靠 TTL）；`timing: open` / `input-ready` 未按内核 gate（claude 会话也会落这两行，污染读数，登记 **#127**）；`_switching` 失败不清（诊断噪声）；T110 用真 Stopwatch（语义已覆盖）。

**设计 token**：`designId 73861cbc` 链路收口，已 `consume-design` 消费。
