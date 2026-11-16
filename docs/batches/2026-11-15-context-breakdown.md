# 2026-11-15 · context-breakdown
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-15 · 来源 = 用户 2026-11-15 22:48「thincoder的上下文窗口显示还是没claude code那样详细，先做一下这个」（承同日「A」裁定：上下文分段照 Claude Code 补齐）。
> 台账 = #253（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-16
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：thincoder 的上下文窗口面板对齐 Claude Code 的详细度

**已定决定**：上下文分段照 Claude Code 补齐，不做宿主侧估算 · 用户原话：「thincoder的上下文窗口显示还是没claude code那样详细，先做一下这个」+「A」· 时间：2026-11-15 22:48

**差距（2026-11-15 22:38 用户截图实拍）**：

- Claude Code 面板：`22.7k / 128.0k · 18%` + 距自动压缩 72.3k + 六段（系统提示词 3.1k 14% / 技能 2.0k 9% / 工具定义 17.4k 77% / MCP 125 1% / 为压缩预留 33.0k）。
- thincoder 面板：`0 / 128.0k · 0%` + 一根空进度条，**零分段**。

**根因（本轮实读）**：分段数据模型 `ContextDetail`（`lib/kernel/kernel_types.dart`）的注释写明「as Claude Code counts them（`get_context_usage`）」——它是 Claude 内核独有的数据源。thincoder 的 ACP 只发 `usage_update {used, size}`（`thincoder-cli/src/acp/bridge.mjs` 的 `onUsage`），没有任何分段字段；本仓 `ThincoderKernel` 也从不构造 `ContextDetail`。

**两半**：

| 半 | 改哪 | 内容 |
|---|---|---|
| R1（外仓） | `thincoder/` | `onUsage` 的 `_meta` 补报 `segments[{system, tools, messages}]`（`messages` = `contextUsage().history` 的裸估算，**不做减法**）+ `threshold` + `basis`；分段单源 = `thincoder-core/token-window.mjs` 的 `contextUsage()`，固定开销经 `agent._ctxBasis.overhead` 传入（`agent-tools/context.mjs`） |
| R2b（本仓） | 本仓 | 把分段映射成 `ContextDetail`，喂 `lib/chat/panels/context_usage_panel.dart` |

**边界**：不做宿主侧估算（数字是猜的，不给比给错好）；`ReportsUsageLimit` 仍不实现（thincoder 无账户概念）。

**下一步**：§2（设计席：R2b 落点、`ContextDetail` 各字段的映射与缺省、R1 的接口契约、验收）→ 评审 → 批准 → 实施。

### 评审轮 1 裁决（changes-required · 2🔴 + 6🟡 + 3🔵 ⇒ 11 条全受理）

**两条 🔴 的方向**：

1. **分支场景（评审第 1 条）**：`§31.5` 的「段之和 > `used` ⇒ 整块丢弃」不是编出来的分支——**场景就在同一行**：`messages` 是「钳 ≥ 0」的余量，钳到 0 之后和必然大于 `used`；而 `system` / `tools` 是估算、`used` 是实测，估算偏高即触达。T151 的输入就是这条路径的复现。改法：在 `§31.5` 点明场景，把 `§31.4` 的「必然自洽」改成「除该钳制路径外自洽」。
2. **文档归属（评审第 2 条）**：`§30.4` 的「这三段是线上唯一新增的载荷」现在是假话（`§31.4` 同帧加了第二块）。改法：把该句改成两块并列，或就地指一句 `§31.4`；**不再适用「§30.4 逐字不动」**。

**修轮 1 定点（只改这十条，不扩面）**：

- 第 3 条：补一句「和判作用在生产者 `segments` 上，先于 buffer 追加」。
- 第 4 条：`test/RTM.md` 的 `§10` 业务故事扩到分段面（或另立故事段），并给 10-2 行的 状态 单元值。
- 第 5 条：分层结论点名 ③ 的体量（4967）与档位，并指 §15.4 的四组拆法/触发。
- 第 6 条：`§2` 的上抛·知会**撤回**——`§1` 已改成 `token-window.mjs` / `contextUsage()`，与设计坐标一致，无待确认项。
- 第 7 条：判据① 注明真机半边 = `§31.10-7` 走查，收口勿把 ① 报成 R1 落地前的可见结果。
- 第 8 条：给 buffer 段补三问答复（`ContextSegment` 构造形 + `ContextKind.buffer` 的在场证据，或 `none found` + 新建方案）。
- 第 9–11 条：统一 core 输出清单（`history` vs `threshold`/`window`）· `§2` 删掉重复的状态行 · `§5.2` 把 `context_usage_panel.dart` 从「>500 且 <800」移到 >800 名单。

**不动的**：`§31` 的载体选择（第二块 `_meta`）、面板零改动结论、T147–T152 的判据面、RTM 10-2 的编号。

### 方向复核（用户指派 Kimi 会诊）——设计需返工：`messages` 减法作废

**结论：评审轮 2 的 pass 随之作废。** 评审只验「上一轮改没改到位」，没验方向；方向错了，改到位也是错。

**Kimi 的判断 + 本席复核（已实证）**：

- `thincoder-core/token-window.mjs` 的 `contextUsage()` 返回 `{basis, total, history, system, tools, overhead, threshold, window}` —— `history`（消息段）**是一等字段**。
- CLI 自己的 `context` 工具就在打印三段：`thincoder-core/agent-tools/context.mjs` 的 `Segments ≈: system … · tools … · history … (basis: …)`。
- **设计 §31.2 写「只给 `system` / `tools` 两个名目总数」= 误读**，设计、修轮、评审三轮都没抓到。

**为什么这处减法必须整条删掉**（不只是换个执行方）：

1. 它把三种误差全塞进消息段——`system` / `tools` 的估算偏差、`used` 里含的 completion、以及「实测 vs 裸估算」两把尺的差。
2. 这正是我们自己裁过的「猜的数字」（不给比给错好）。
3. 它存在的唯一理由是「三段之和 = used ⇒ 占比恒 100%」——**用编出来的数买整齐**。
4. 设计内部本就自相矛盾：一处说「桌面只做 `size − threshold` 一处减法」，另一处又冒出 messages 减法。
5. round 1 的 🔴「钳制路径场景」**是这个误读的副产品**——源头没了，那条分支连同它的场景一起消失。

**修轮 3 定点**：

- `messages` 段改由 **CLI 直发** `contextUsage().history`（裸估算，未乘比），**删掉一切 `used − system − tools` 减法与钳制**（§31.1 ④ / §31.4 / §31.5 / T147 / T151 同步）。
- 随带 `basis`（`measured` ∥ `estimated`）——§31.8 的 open②「估算态标注」由此闭合。
- **保留和判守卫**（三段之和 > `used` ⇒ 整块丢弃）作为诚实兜底：裸估算已知偏低（ratio ≥ 1），多数帧段之和 &lt; `used`，面板显示为未填满——这是诚实形态，不是缺陷。
- §1 的 R1 半栏、§31.6 受影响面、§31.9 的 10-2 断言随之一并改。

**不变**：第二块 `_meta` 的载体选择（Kimi 判对，ACP v1 标准面确无分段字段，`_meta` 是协议明文的扩展位）；两仓拆分（边界真实）；面板零改动。

### 评审轮 3 裁决（pass · 3🟡 + 2🔵，全受理）

方向修正四项经评审确认全部落地；余下五条虽不阻塞，但都是实施轮会踩到的口径，一并定死。

**修轮 4 定点（只改这五条，不扩面）**：

1. 🟡 **对齐 ③ 的「已知值不清空」与 per-frame 相抵**：删掉那半句，或改成「本块 per-frame，无可保留的已知值（§31.1 ③）」。分段块按帧自足，照抄 §30.5 的累计语义会让实现去造一个 §31.1 ③ 明禁的回填态。
2. 🟡 **判据 ② 的机检没检它声明的量**：`§31.9` ② 写的「距自动压缩 = `threshold − used`」在 T147/T152 里没有断言（那两条断的是压缩线 95000 与预留 33000）。要么把面板算该距离的表达式原文补进 `§31.5` 的引据块，要么让 T147/T152 断到 72300——两者都做更好。
3. 🟡 **「多数帧段之和 < `used`」是断言不是读数**：落进 `§31.11` 未验证项（R1 首步用真实帧读一次），并让 `§31.10-7` 走查把「段之和 vs `used`」列成读数项。若真实帧多数落在另一侧，整块会被逐帧丢弃、面板回单条 `used` 格，判据 ① 就看不见分段。
4. 🔵 **和判输入端未钉死**：`§31.5` 补一句「和判作用在坏项丢弃后的保留集」；T150 补一个 `used`，让两种读法的产出可区分。
5. 🔵 **数值漂移**：`§31.6` ④ 的 `test/RTM.md`（123 行）本轮实测 126 行；更新读数或注明取值日。

**不动的**：`messages` = CLI 直发 `history`（方向裁决）、第二块 `_meta` 载体、和判守卫本身、面板零改动、T147/T151 的主断言。

### 修轮 4 落地核验（本席实跑）

四处关键点逐一核过，全部在盘：

- 对齐 ③ 的「「已知值不清空」不照抄」句在场（1 处）。
- 面板距离算式 `math.max(0, compactAt - used)` **实体档与设计引据两侧各 1 处** —— 判据 ② 的 72300 从此有据。
- `§31.11 U26`（真实帧「段之和 vs `used`」分布，无读数）+ `§31.10-7` 读数项在场；`§31.1 ④` / `§31.4` 的同一断言已降级为「落在哪一侧本轮无读数」。
- `§31.9` 的 RTM 计数已改「现行 11 / 50–100」，并写明 10-2 行已由前置轮次定行、实施轮只落用例体。

**一条上抛就地裁决**：`§2` 里「需求档 F10 / F20 要不要补一句分段判据」——**半日前就已办**（需求档 F10 现文：分段与「距自动压缩」都要显示，数据由 CLI 报、桌面不估算，带用户原话）。下轮修 §2 时把这条撤掉，别再当待裁项挂着。

**下一步**：向用户请求批准实施。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 批次任务（设计席 · 批 = 上下文分段 R2b；台账 #253）

**设计档落点**：`docs/design/thincoder-adapter.md` §31（整节新增，就地落在板档末尾；不另立新档——同一机制同一板档，§30 是其直接前身）。本段只指路，不复述：判据、帧形、映射表、用例表、边界全在 §31 各小节。

**本批覆盖（条目表）**

| # | 条目 | 设计落点 | 验收 |
|---|---|---|---|
| 1 | `usage_update` 第二个扩展块 `_meta["thincoder.dev/context"]` 的帧形与桌面翻译：分段进 `ContextUsage.segments`（帧含 `threshold` / `basis`） | `design §31.4`（帧形）· `§31.5`（翻译表） | `T147` · `T149` |
| 2 | 「距自动压缩」与「为压缩预留」两面（`threshold` ⇒ buffer 段） | `design §31.1 ⑤` · `§31.5` 预留面两行 | `T147` · `T152` |
| 3 | 旧 CLI / 缺块 / 坏块零回归与留痕（不静默丢弃、不裁不缩） | `design §31.5` 各行 | `T148` · `T150` · `T151` |
| 4 | 集成面：RTM 新增 10-2（面板按段显示、距自动压缩可见） | `design §31.9` RTM 增量 | RTM 10-2 + `test/integration/thincoder_usage_test.dart` 的 `test('10-2 …')` |
| 5 | R1 接口契约（外仓 CLI 侧）：本仓只定消费者契约，生产者落外仓独立轮 | `design §31.4` · `§31.10-6` | 本批不验（外仓轮验）；本仓侧 = `T148` 证明缺块可活 |

**本批不做 / 不在本批**

- 外仓 `thincoder/` 的实现（R1）：独立 git 仓、须在该仓锚定的会话里开批，需用户批准（`design §31.6 ⑥`）。
- 逐项下钻（`ContextDetail`）与面板上的「估算」标注：`design §31.8` 的两个 open 项（`basis` 本身已随帧上线、桌面在丢弃留痕里用它；不显示的是面板上的标注）。
- 宿主侧估算：用户 2026-11-15 裁定逐字不做（`design §31.10-1`）。
- `ReportsUsageLimit`：仍不实现（`design §31.10-5`）。

**受影响文件**：`design §31.6` 的六行（①`thincoder_usage.dart` ②`thincoder_events.dart` ③内核测试档 ④RTM + 集成用例 ⑤面板零改动（登记）⑥外仓 bridge）。分层结论在该节末两条，本段不重复计数。

**验收对照**：`design §31.9` 五条判据（①分段可见 ②距压缩可见 ③缺块零回归 ④坏形留痕 ⑤桌面零估算），每条带机检。① 的机检分两半——mock 帧（T147 + RTM 10-2）与 `design §31.10-7` 真机走查；R1 落地前 ① 无可见结果。**本批机检命令**（改动面单测档，非全量）：

```text
flutter test test/kernel/thincoder_kernel_test.dart test/integration/thincoder_usage_test.dart
```

**关键决策**：`design §31.1` 决议总表七条 + §31 开头的对齐五条 / 偏离一条。三条要评审批的：

- **偏离「不构造 `ContextDetail`」**：core 的 `contextUsage()` 给三个段总数 `system` / `tools` / `history`、两个窗口数 `threshold` / `window`、估算态 `basis`（`design §31.2` 实读），但无逐项名目（每个工具 / 技能各占多少）；造空壳会让面板挂出可点空的逐项态。若评审认为逐项面必须同期补，那属于 R1 扩 + 本档改判，不在本批。
- **三段直收，桌面不做减法、不做钳制**：`messages` = CLI 直发的 `contextUsage().history`（`estimateTokens(history)` 裸估算，未乘标定比）。三种误差（`system` / `tools` 的估算偏差、`used` 含 completion、实测 vs 裸估算两把尺的差）不塞进任何一段——塞进去就是编数。随之：**段之和与 `used` 无相等关系**；落在 < 侧则面板留未填满份额（诚实形态，不是缺陷），落在哪一侧本轮无读数（`design §31.11 U26`）。
- **段之和 > `used` 时整块丢弃**：估算偏高即触达，两把尺不一致的实证引文在 `design §31.2`；份额分母被 `used` 钉住，和超了就是估算法失准 ⇒ 回单条 `used` 格 + 一行 `appEvent`（点名和、`used`、`basis`），不裁不缩、不按比例归一（`design §31.5` 第三行）。
- **`basis` 上线、不上面板**：帧上随带（`design §31.4`），桌面只在丢弃留痕里用它；面板零改动是本批边界，「估算」标注是一条独立 UI 决定（`design §31.8` open② 的显示半边）。

**上抛项**

- `[上抛·待裁]` **需求档的决策记录与已批准设计不一致**（需求档写入面 = 主 agent，本席只报不改）：需求档「2026-11-15 · 用户「A」」那条写「CLI 在 `_meta["thincoder.dev/usage"]` 里补报分段（估器与固定开销估算在 `thincoder-core/context.mjs` 已在），本仓映射成 `ContextDetail` 供面板画」；已批准的设计写的是第二块 `_meta["thincoder.dev/context"]`（`design §31.4`）、翻译进既有 `ContextUsage.segments`、**不构造 `ContextDetail`**（`design §31 偏离 ①`），分段单源 = `token-window.mjs` 的 `contextUsage()`（`design §31.2`）。三处对不上：块键、映射目标、单源档。F10 正文已与设计一致（分段与「距自动压缩」都显示、数据由 CLI 报、桌面不估算），不一致的只是那条决策记录。处置建议：主 agent 就地订正该行——用户 2026-11-15 已「批准」设计，方向无需重议。


## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

**设计评审**：`docs/design/thincoder-adapter.md` §31 · 本档 §2 · 状态 = 待评审 · 结论 = changes-required

范围限制：
- 无 AGENTS.md、无项目规范档、无文档地图 ⇒ 方法学按两档自身惯例判。
- 只读两档全文，未逐档复读源码。
- 定点核对：`thincoder_events.dart` 32088 B · `thincoder_usage.dart` 6986 B · `context_usage_panel.dart` 31893 B · `thincoder_usage_test.dart` 13809 B。
- 与所报 878 / 192 / 951 行相互一致。
- `test/RTM.md` 已有 10-1、无 10-2 ⇒ 与「新增 10-2」一致。

| # | Category | Severity | Issue | Suggestion |
|---|---|---|---|---|
| 1 | 分支来历（6b） | 🔴 | §31.5「段之和 > `used`」整块丢弃一行无场景来源。§31.4 同表又写「钳 ≥ 0」：钳到 0 后和必大于 `used`。估算较实测偏高即触达。T151 的输入是编的，不是场景。 | 点明场景（估算超实测，T151 即其复现），并把「必然自洽」改成「除该路径外自洽」；若坚持不可达，则连同 `appEvent` 与 T151 删行。 |
| 2 | 文档归属 | 🔴 | §30.4 仍写「这三段是线上唯一新增的载荷」。§31.4 同帧加第二块 `_meta`。§31.10-3 又声明 §30.4 逐字不动。 | 把 §30.4 的唯一性断言改成两块并列，或就地指一句 §31.4。 |
| 3 | 清晰度 | 🟡 | 和判与 buffer 追加是同一表的两行，未写先后。追加后整表之和必大于 `used`。 | 补一句：和判只作用于生产者 `segments`，先于 buffer 追加。 |
| 4 | 集成用例设计（12） | 🟡 | `test/RTM.md` 的 §10 业务故事只覆盖缓存与费用。增量未写 10-2 的故事落点，也未给该行 状态 单元。 | 写明是把 §10 业务故事扩到分段面，还是另立故事段；补 状态 取值。 |
| 5 | 受影响文件档位（8） | 🟡 | 分层结论只点 ①②⑤；③④ 只写「行级追加」。③ 是 §30.6 记的 4967 行，已在 >800 之上，缝候选未点名。 | 点名 ③ 的体量与档位及既有缝候选（§15.4 四组拆法），或明写只追加、触发沿用登记。 |
| 6 | 状态一致性 | 🟡 | §2 上抛·知会称 §1 写「估算器与『固定开销』面在 `thincoder-core/context.mjs` 已在」。§1 现文是「分段单源 = `thincoder-core/token-window.mjs` 的 `contextUsage()`」。 | 撤回该知会：§1 现文已与设计坐标一致，无需确认。 |
| 7 | 验收 / 协同（R5） | 🟡 | 判据① 写「面板出现分段，不再是一根空条」，机检却是 mock 帧上的 10-2。§31 开头自写「只做 R2b = 零可见变化」。 | 注明真机半边 = §31.10-7 走查；收口勿把 ① 报成 R1 落地前的可见结果。 |
| 8 | 三问（11） | 🟡 | §31.12 只给 `ContextUsage.segments` 的字段与既有构造点。预留行依赖的 `ContextSegment('', size − threshold, kind: ContextKind.buffer)` 无在场证据。 | 为 buffer 段补一条三问：构造形与 `ContextKind.buffer` 的在场证据，或 `none found` + 新建方案。 |
| 9 | 内部一致性 | 🔵 | 偏离行写 core「只给 `system` / `tools` / `history` 三个总数」。§31.2 实读写「已有 `system` / `tools` / `threshold` / `window`」。 | 统一两份清单。 |
| 10 | 文档卫生 | 🔵 | §2 有两行「**状态行**：设计完成」：段首一行、段末一行。状态行只有一个写者。 | 留一行。 |
| 11 | 数值漂移（R7c） | 🔵 | §31.6 记 `context_usage_panel.dart` 951 行。§5.2 仍把它列在「>500 且 <800 的档」并记 530。 | 移到 >800 名单，或注明现读数。 |

计数：🔴 2 · 🟡 6 · 🔵 3

VERDICT: changes-required

### 轮次 2（评审子代理）

**设计评审（轮 2 · 只核轮 1 的 11 条，不拓新发现面）**：`docs/design/thincoder-adapter.md` §31 / §30.4 / §5.2 · 本档 §2 · `test/RTM.md` §10 · 状态 = 待评审 · 结论 = pass

范围限制：
- 无 AGENTS.md、无项目规范档、无文档地图 ⇒ 方法学按两档自身惯例判。
- 触发 = 复核轮 1 的 11 条（2🔴 + 6🟡 + 3🔵）是否落地；按触发口径不另开发现面。
- 档位抽核（本机 `ls` 字节读数，只作同档量级对照，行数未逐档点数 = `unverified`）：`thincoder_events.dart` 32088 B · `thincoder_usage.dart` 6986 B · `test/kernel/thincoder_kernel_test.dart` 191971 B · `context_usage_panel.dart` 31893 B——与所报 878 / 192 / 5287 / 951 行同档。

| # | Category | Severity | Issue | Suggestion |
|---|---|---|---|---|
| 1 | 分支来历（6b） | 已核销（原 🔴） | 已落地：§31.5 第三行现写「段之和 > `used`（**真实场景 = 上述钳制路径**：`messages` 钳到 0，`system` + `tools` 两项估算之和已超实测 `used`；T151 的输入即这条路径的复现——`used: 5000` 对 `system 4000` + `tools 4000`）」；§31.4 同表行现写「**除该钳制路径外自洽**」并指 §31.5 第三行。两处齐，T151 输入即该路径。 | 无需再改 |
| 2 | 文档归属 | 已核销（原 🔴） | 已落地：§30.4 现写「线上新增的载荷 = 两块 `_meta` 扩展：`thincoder.dev/usage`（本节的缓存三段）与 `thincoder.dev/context`（§31.4 的上下文分段，同帧；两块各自独立解析，§31.4 末行）」；§31.10-3 现写「不改 `used` / `size` 语义，不改 `thincoder.dev/usage` 块的字段与语义（§30.4）」，不再声称§30.4 逐字不动。grep「唯一新增的载荷」全档零命中。 | 无需再改 |
| 3 | 清晰度 | 已核销（原 🟡） | 已落地：§31.5 末段「**和判先于 buffer 追加，且只作用在生产者的 `segments` 上**……次序钉死：先判生产者段之和 > `used`（丢弃 ∥ 保留），再追加 buffer 段」。 | 无需再改 |
| 4 | 集成用例设计（12） | 已核销（原 🟡） | 已落地：`test/RTM.md` §10 标题 = 「用量与上下文分段：thincoder 会话的缓存、费用与分段」，业务故事含「按段分段（系统提示词 / 工具定义 / 消息 / 为压缩预留）与「距自动压缩」就在那儿」，回溯需求含「另：F10 / F20 的上下文面——上下文分段按段显示、距自动压缩可见（台账 #253）」；10-2 行八字段齐（组件间交互 / 业务可观察结果 / 用户入口 / 回溯需求 / 用例文件·标题 / 状态），状态 = 「行已定；用例体本批实施轮落地」；档头「当前 **11 / 50–100**」与十一行一致。 | 无需再改 |
| 5 | 受影响文件档位（8） | 已核销（原 🟡） | 已落地：§31.6 分层结论点名 ③「`test/kernel/thincoder_kernel_test.dart` **5287 行**（>800，名单内）」+「缝候选沿用 §15.4 的四组拆法（connection / session ids / locator / the registered kernel 各成档），触发 = 独立拆分批立项」，并点名 ④⑤；末句「无档位跨越，无本批内拆分计划」。 | 无需再改 |
| 6 | 状态一致性 | 已核销（原 🟡） | 已落地：本档 §2 不再有 `context.mjs` 知会（该坐标只余 §1 的 R1 半边表与设计 §31.11 U23，两处与 §1 现文的 `token-window.mjs` / `contextUsage()` 一致）；上抛项只剩一条需求档协调项（R5 协同，非缺陷）。 | 无需再改 |
| 7 | 验收 / 协同（R5） | 已核销（原 🟡） | 已落地：§31.9 ① 现写「机检半边 = T147 + RTM 10-2（mock 帧）；**真机半边 = §31.10-7 走查**。R1 落地前 ① 无可见结果（§31 开头「只做 R2b = 零可见变化」）——收口不得把 ① 报成 R1 前的可见结果」；本档 §2 验收对照同步（「R1 落地前 ① 无可见结果」）。 | 无需再改 |
| 8 | 三问（11） | 已核销（原 🟡） | 已落地：§31.12 第四条给 buffer 段「`existing: lib/kernel/kernel_types.dart:116` · `name: "const ContextSegment(this.label, this.tokens, {this.kind = ContextKind.used});"`」+ 两个消费方（面板 `.where((s) => s.kind == ContextKind.buffer)`、Claude 侧 `'buffer' => ContextKind.buffer,`）+ 三行原文引据。 | 无需再改 |
| 9 | 内部一致性 | 已核销（原 🔵） | 已落地：§31 偏离 ① 与本档 §2 关键决策同写「只给 `system` / `tools` 两个名目总数与 `threshold` / `window` 两个窗口数」；§31 全节无 `history` 作分段名。 | 无需再改 |
| 10 | 文档卫生 | 已核销（原 🔵） | 已落地：本档 §2 段内只有段首一行「**状态行**：设计完成」，段末重复行已删（§2 的「状态行」字样仅此一处）。 | 无需再改 |
| 11 | 数值漂移（R7c） | 已核销（原 🔵） | 已落地：§5.2 现写「`context_usage_panel.dart`（951 行，本轮 `wc -l` 实测）：**入 >800 名单**（原记在 >500 层，读数已过线）……本批不动结构、不立缝」；「>500 且 <800 的档」行已不再列它（现列 `thincoder_mock.dart` 668 · `kernel_types.dart` 615）。 | 无需再改 |

计数：🔴 0 · 🟡 0 · 🔵 0 —— 轮 1 的 11 条（2🔴 + 6🟡 + 3🔵）全部核销，无未决项。

VERDICT: pass

### 轮次 3（评审子代理）

**设计评审（轮 3 · 只核方向修正：`messages` 减法删净 ∥ `basis` 落地 ∥ 和判语义 ∥ T147/T151 与新契约一致）**：`docs/design/thincoder-adapter.md` §31.1 / §31.4 / §31.5 / §31.6 / §31.8 / §31.9 · 本档 §2 · `test/RTM.md` 10-2 · 状态 = 待评审 · 结论 = pass

范围限制：
- 无 AGENTS.md、无项目规范档、无文档地图 ⇒ 方法学按两档自身惯例判；方向裁决只可回指本档 §1「方向复核」。
- 按触发口径只核方向修正四项，不另开发现面；下表的 🟡/🔵 全落在被核的几节之内。
- 档位抽核（`ls` 字节读数，仅作同档量级对照）：`thincoder_usage.dart` 6986 B ↔ §31.6 ① 记 192 行；`thincoder_events.dart` 32088 B ↔ §31.6 ② 记 878 行；`test/integration/thincoder_usage_test.dart` 13809 B 在盘（10-1 用例体已落）。

**四项核对（均已落地，逐条实证）**

1. `messages` 减法删净：§31.1 ④ 现写「桌面**不做减法、不做钳制**」；§31.1 ② 现写「唯一的减法 = `size − threshold`（预留面），三段 token 数逐字照收」；§31.4 现写「与帧上的 `used` **无相等关系**」；§31.6 ① 现写「段组装（三段直收，无减法、无钳制）」。全档搜「钳」只余 §30.4 的 `cacheRead` 行（`未命中 = input − cacheRead`，属另一块），搜「减法」四处全是上述订正句 ⇒ 无 `used − system − tools` 残留。
2. `basis` 落地：§31.4 帧形含 `"basis": "estimated"` 并单列字段行；§31.5 和判行留痕点名 `basis`；T151 断言「点名和 7500、`used` 5000、`basis estimated`」；§31.8 open② 现写「「估算态在数据面上不可得」这一半已闭合」；§31.12 第三条给 core 原文「`basis: measured ? "measured" : "estimated",`」。
3. 和判语义：§31.5 现写「**和判先于 buffer 追加，且只作用在生产者的 `segments` 上**」；丢弃侧写「**整块丢弃**（空分段 + 恰一行 `appEvent`，点名和、`used` 与 `basis`）」；未填满侧写「段之和 < `used` 不补段」+ `share: used <= 0 ? null : part.tokens / used`。
4. T147 / T151 与新契约一致：T147「`UsageReported.context.segments` 恰 4 项」+「三段之和 22300 < `used` 22700（面板留未填满份额）」——22300 = 3100 + 17400 + 1800 逐字取帧值，无减法；T151「`segments` 空表 + 恰一行 `appEvent`（点名和 7500、`used` 5000、`basis estimated`）」与 §31.5 第三行同源；RTM 10-2 的「各格占比 = 该段 tokens / `used`」同口径。

| # | Category | Severity | Issue | Suggestion |
|---|---|---|---|---|
| 1 | 内部一致性 / 和判与坏形口径 | 🟡 | §31 开头「对齐 ③」写「坏块口径照抄 §30.5：坏形留痕 `appEvent('thincoder', …)`、不静默丢弃、已知值不清空。」，而 §31.1 ③ 写「per-frame：每个 `usage_update` 自带全部已归因段；不带 = 本帧没有分段（不回填上一帧）」，§31.5 坏形行的落点是「坏的那项丢弃，其余照用；整块一项都读不出 ⇒ 空分段」。分段块按帧自足、没有可「不清空」的已知值；照「已知值不清空」实现要造一个 §31.1 ③ 明令禁止的回填态。 | 把对齐 ③ 收窄成「坏形留痕 `appEvent` + 不静默丢弃」，删去「已知值不清空」（或改写成「本块 per-frame，无可保留的已知值（§31.1 ③）」）。口径单源仍是 §31.4 末句「缺失 / 坏形的处理只有一处口径：§31.5。」 |
| 2 | 验收可检性 | 🟡 | §31.9 ② 写「「距自动压缩」可见（`threshold − used`）」，机检列 T147 / T152；但 T147 只断 buffer 33000 与段之和，T152 只断「第三态 buffer = 33000 且 `total − reserved == 95000`」——95000 是压缩线本身（`threshold`），不是「距自动压缩」72300（= 95000 − 22700）。§31.5 也只引「并由 `total − reserved` 得压缩线」，未引面板把压缩线再减 `used` 的那一行原文。 | 把面板算该距离的表达式原文补进 §31.5 的引据块，并让 T147 或 T152 断到 72300；RTM 10-2 的同一句随之有据。 |
| 3 | 分支来历 / 实测缺项 | 🟡 | §31.1 ④ 写「多数帧段之和 < `used`（估算偏低）」，§31.4 同断言，§31.5 的丢弃行按此推。T147 的 22300 < 22700 是构造的；§31.11 只有 U23 / U24 / U25，没有这一条。若真实帧多数落在另一侧，整块会被逐帧丢弃、面板回单条 `used` 格 ⇒ R1 落地后判据 ① 仍看不见分段。 | 把「真实帧段之和相对 `used` 的分布」列进 §31.11（R1 首步用真实帧读一次），或让 §31.10-7 走查把「段之和 vs `used`」列成读数项。 |
| 4 | 清晰度 / 和判输入端 | 🔵 | §31.5 坏形行「坏的那项丢弃，其余照用」与和判行相邻，但没写和判作用在「坏项丢弃后的保留集」还是原表；T150 的输入 `[{system,3100}, {tools,"17k"}, {"" ,5}, {mcp,0}]` 不带 `used`，两种读法产出相同、分不出。 | §31.5 补一句「和判作用在坏项丢弃后的保留集」；给 T150 补一个 `used` 让次序可辨。 |
| 5 | 数值漂移（R7c） | 🔵 | §31.6 ④ 记「`test/RTM.md`（123 行）」；本轮读该档至末行「- **删除**：无。」共 126 行。结论（远低于 800 硬顶）不受影响。 | 更新读数或注明取值日。 |

计数：🔴 0 · 🟡 3 · 🔵 2 —— 方向修正四项（减法删净 / `basis` 落地 / 和判语义 / T147·T151 断言）全部与新契约一致，无未决 🔴。

VERDICT: pass

## §4 用户批准（主 agent）

### 用户批准（R2b 本仓轮）

- 2026-11-15 23:55 · 用户原话：**「批准」**——批准 `design §31` 进入实施。
- **批准范围**：R2b 本仓轮——`thincoder_usage.dart` 加 `_contextOf`、`thincoder_events.dart` 一处实参、T147–T152、RTM 10-2 用例体。**不含** R1 外仓轮（`thincoder/` 的发帧与终端 context% 改实测），那一轮须在 `thincoder/` 锚定的会话里另开批档。
- **可见结果预期（用户已知悉）**：本批单独上线**零可见变化**；分段条要等 R1 把 `_meta["thincoder.dev/context"]` 发出来。
- **实施轮不得自裁的两条**：`messages` 由 CLI 直发（不做减法）；和判超 `used` ⇒ 整块丢弃（不裁不缩）。真实帧落在哪一侧无读数（`§31.11 U26`），实施轮不据此改口径。

## §5 实施记录（eng-coder）
**状态行**：✅ 实施完成



### 实施轮（R2b 本仓）· 2026-11-16

**改了什么（design §31.6 四行，逐行；行数 = `wc -l` 实测，HEAD → 现在）**

- ① `lib/kernel/thincoder/thincoder_usage.dart`（192 → 302 行）：新增第二块解析 `_contextOf`——形判、坏形逐项 `appEvent`、段组装、buffer 段推导、和判；`+110` 行。`count` 闭包提为文件级 `_count`，两块共用同一条「是不是计数」的判据（行为不变）。
- ② `lib/kernel/thincoder/thincoder_events.dart`（878 → 888 行）：`_usage` 一处——`_contextOf(...)` 一行调用 + `ContextUsage(...)` 加 `segments:` 一处实参。
- ③ `test/kernel/thincoder_kernel_test.dart`（5287 → 5581 行）：T147–T152 六条；`frame()` 助手加 `context` / `size` 两参、新增 `block()` 助手。
- ④ `test/integration/thincoder_usage_test.dart`（430 → 530 行）：10-2 用例体 + `_segmentedFrame()` 助手 + `_togglePanel()`；`test/RTM.md` 的 10-2 状态改「本批落地」、变更记录一句、本档头注扩到 10-1 / 10-2。
- ⑤ `lib/chat/panels/context_usage_panel.dart`：零改动（登记项，未触碰）。

**两处口径的落点**

- 和判先于 buffer 追加，且只作用在坏项丢弃后的保留集：`sum` 在逐项循环之后求（保留集），buffer 在 `sum > used` 判过之后才加。
- 三段逐字照收、无减法、无钳制：桌面侧唯一的减法是 `size − threshold`；段之和小于 `used` 时不补段、不放大。

**设计档未指定的一格（本席定，已钉住）**

- 输入组合：「`segments` 是列表、但一项都读不出」且 `threshold` 有效。按 §31.5 末段的次序（和判 → buffer 追加）⇒ 预留段照样追加。
- 落地形态：`_contextOf` 的文档注释写明该格；T150 末尾补一条断言（全坏项 + `threshold: 95000` ⇒ 分段恰一项 `('', 105000, buffer)`）。
- 另一条路（`segments` 不是列表）仍返空表，T150 已断；两条路在这一格不同：前者是「块读得通、零件全坏」，后者是「块读不通」。
- 若设计席要相反口径，那是设计档补一句 + 改一行。

**机检（本批命令，非全量）**

```text
flutter test test/kernel/thincoder_kernel_test.dart test/integration/thincoder_usage_test.dart
```

- 结果：`All tests passed!`（169 条）。
- `flutter analyze` 四个改动档：`No issues found!`。
- RTM 10-2 的可见断言走真面板（`ContextUsagePanel`）：三格 + 预留格 + 占比 14% / 77% / 8% + `72.3k to auto-compact`。

**U25（设计档要求实施轮实读的）**

- `lib/usage/` 全目录对 `ContextUsage` / `ContextSegment` / `ContextKind` 零读点（`usage_capture.dart`、`claude_usage_meter.dart` 都在内）。
- 全仓读 `usage.segments` 的只有两处：`lib/chat/panels/context_usage_panel.dart`（`segment.kind != ContextKind.used` 的先跳过，buffer 只用于算预留）与 `lib/link/workspace_bridge.dart`（`if (segment.kind != ContextKind.used …) continue;`）。
- 结论：无一处把 buffer 当 used 用 ⇒ `none found`，无单列项。

**两轮内部关口**

- 差异审计（只读 explore，对本档 §2 + design §31 逐条）：代码侧 0 条差异；口径歧义 1 条（上面那格，已补注释 + 断言）；命名差异 1 条（实现 `_contextSegmentsOf` 对不上 §31.6 ① 写的 `_contextOf`）——已改名对齐，剩设计档行数漂移。
- 代码评审（advisor，type=code）：结论 pass。🟡 1 条 = 本节原先空着（这次补上）；🔵 2 条 = 上面那格已补注释与断言、§31.6 行数漂移转设计席。
- 收口状态：`clean`（差异审计 1 轮 + 代码评审 1 轮，无未修项）。

**给设计席的漂移（本席不改设计档）**

- design §31.6 ① 记「（192 行）」「≈ +60 行」「① 192 → ≈250 行（<800）不触档」：实读 302 行（+110）。档位结论（<800、不触档）不变。
- design §31.6 ② 记 878 行：实读 888。③ 记 5287 行：实读 5581。两档本就在 >800 名单内，结论不变。
- design §31.9 括注的 10-2 行状态「行已定；用例体本批实施轮落地」：现文是「本批落地」（用例体已落）。
- design §31.5 建议补一句上面那格的口径（全坏项 + 有效 `threshold`）。

**越界改动**：无。改动的五个文件都在本 spawn 的写域内。

**记录机检**：`doc_check` gate over `test/RTM.md` = `PASS`。

## §6 验证与收口（父代理）

### 验证与收口（R2b 本仓轮）

**父侧实跑（本席执行，2026-11-16 00:17）**：`flutter test test/kernel/thincoder_kernel_test.dart test/integration/thincoder_usage_test.dart` ⇒ **169 passed / All tests passed**。

- 含新集成用例 **10-2「a thincoder chat shows the context by part, and how far the auto-compaction line is」**——真面板断言（三格 + 预留格 + 占比 14% / 77% / 8% + `72.3k to auto-compact`），不是 mock 层。
- 实施席另跑 `flutter analyze` 四档 ⇒ `No issues found!`。

**改动面与实测行数**：

| 文件 | 变化 |
|---|---|
| `lib/kernel/thincoder/thincoder_usage.dart` | 192 → **302**（新增 `_contextOf`：形判 / 坏形逐项留痕 / 段组装 / buffer 推导 / 和判） |
| `lib/kernel/thincoder/thincoder_events.dart` | 878 → **888**（一处实参） |
| `test/kernel/thincoder_kernel_test.dart` | 5287 → **5581**（T147–T152） |
| `test/integration/thincoder_usage_test.dart` | 430 → **530**（10-2 用例体） |
| `lib/chat/panels/context_usage_panel.dart` | **零改动**（951 行不动，设计登记项兑现） |

**验收对照**：E1 帧形与翻译（T147 · T149）· E2 双面可见（T147 断 72300 / T152 三态 / RTM 10-2 真面板）· E3 零回归与留痕（T148 · T149② · T150 · T151）· E4 集成面（RTM 10-2）· E5 消费者契约（T148 证明缺块可活）。

**集成窗**：`test/RTM.md` 现 **11 / 50–100**。

**已知空缺（如实记）**：本批单独上线**零可见变化**——分段条要等外仓 R1 把 `_meta["thincoder.dev/context"]` 发出来。真机走查 `design §31.10-7` 未做，原因同此；**收口不把判据 ① 报成 R1 前的可见结果**。

**设计档漂移（已派设计席 #36 补）**：§31.6 的 192 / 878 / 5287 三处行数已过期（实测 302 / 888 / 5581，档位结论不变）· §31.9 括注的 10-2 状态词 · §31.5 需补一句「全坏项 + 有效 `threshold` ⇒ 预留段照追加」的口径。

**暂缓批复核**：无。
