# 2026-11-15 · thincoder-usage-parity
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-15 · 来源 = 用户 2026-11-15「nonono，我们直接有模板了，直接全抄过来，后端也抄过来」。
> 台账 = #244（— · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-15
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：「thincoder」内核能力对齐 · 第 1 批（用量面）

**已定决定**：照模板全抄——应用侧抄 `ClaudeCodeKernel` 的能力实现，后端缺的能力也补；分批落地，每批一次点火 · 用户原话：「nonono，我们直接有模板了，直接全抄过来，后端也抄过来」· 时间：2026-11-15 20:30

**模板在这**：应用侧 `lib/kernel/claude_code/claude_code_kernel.dart`（20 项能力）；后端 `packages/bao_agent/lib/src/{engine,tools,mcp,permissions,prompts,hooks}`（Dart 内核）。

**缺口共 12 项**（`ThincoderKernel` 缺、模板有）：`ReportsUsage` · `ReportsUsageLimit` · `ProvidesCommands` · `ManagesMcpServers` · `SelectsContextSize` · `SelectsFast` · `RunsBackgroundTasks` · `RevertsChanges` · `WatchesEdits` · `ForksConversation` · `AcceptsImages` · `SuggestsPrompts`。

**两条模板里也没有的**（须新造，不能抄）：`fork` 与逐文件 `revert`——`packages/bao_agent/lib/src` 内这两个词零命中，它们活在 Claude Code CLI 那侧。

**本批只做一项**：`ReportsUsage`（累计 token + 缓存命中/未命中 + 按价格表估的费用）。**不做** `ReportsUsageLimit`——thincoder 没有「账户限额」这个概念，硬造就是假能力。

**现状读数**：
- 引擎已累好数：`thincoder-core/agent/turn-loop.mjs:216-229` 累 `_cacheHitTokens` / `_cacheMissTokens` / `_lastPromptTokens` / `_usageTurns`。
- 协议只发两个字段：`thincoder-cli/src/acp/bridge.mjs:307-308` 的 `usage_update {used, size}`（`used = prompt_tokens + completion_tokens`）。
- 应用侧只接了上下文：`lib/kernel/thincoder/thincoder_events.dart:129` 的 `usage_update` → `_usage()`（喂上下文环）。
- 应用侧能力表没有 `ReportsUsage`：`lib/kernel/thincoder/thincoder_kernel.dart:52-72`。

**下一步**：§2（设计席，写 `docs/design/thincoder-adapter.md` 的新节 + 逐档落点）→ 设计评审 → 批准 → eng-coder 实施。

### 评审轮 1 的裁决（3🔴 · 5🟡 · 5🔵 ⇒ 13 条全受理）

三条 🔴 的方向由本席定，其余照 §3 表 `Suggestion` 列改：

| # | 裁决 |
|---|---|
| 1 | D88 / §14-25 / §23.2 一并改成 §30 口径，只留一份权威；§30.7 点名「反转的是实现 `ReportsUsage`」。 |
| 2 | ③ 落到消费方：改 `part of &apos;thincoder_events.dart&apos;`（形同 §23.3 的 `thincoder_agents.dart`），或独立库由 events import；写明 `_meta` 解析归 ② 还是 ③。 |
| 3 | 按删除办：`cost` 在线分支删掉；「字段部分 / 坏形」补实读读数或复现路径，并按 §15.2「绝不静默丢弃」给留痕与用例。 |

**需求档已扩**（父侧笔）：`docs/requirements/thincoder-adapter.md` 的 F20 加了「批 23 扩」句、验收加了缓存三段与费用一条、边界写了「`cost` 不在线上」与「`ReportsUsageLimit` 不实现」；§10 裁定记录记下 B1 例外原文（「后端也抄过来」）。10-1 的「回溯需求」指新 F20 文。

**另记**：需求档原有多段超长（16 处），本轮做了零语义重排（只插空行、只在「；」断段），去空白后字符序列逐字相等；机检现为 0 命中。

### 评审轮 2 裁决（pass · 3🔴 全解）

- 轮 2 = **pass**，设计 token 已签发、未消费。13 条交付：3🔴 Fixed · 🟡 4 Fixed / 1 Accepted · 🔵 3 Fixed / 2 Accepted。
- **N1（§1 与 §2 对需求档陈述相反）= 本席当场核实，判 Not an issue**：需求档确已扩——`F20` 带「批 23 扩」、验收有缓存三段与费用、§10 有 B1 例外与 B 裁定两行。设计席读到的是我落盘前的版本（并行所致）。**§2 的 B3 上抛作废**，父侧无需再动需求档。
- **N2 的裁定（设计席照此改）**：坏块**不清空**已知道的 cache，只留痕——理由：一块坏 payload 不构成「cache 归零」的证据，清空等于用垃圾帧丢真数据，与 §15.2「绝不静默丢弃」同理。§30.5 坏形行与 T146① 同步改成这一条。
- **修轮 1 定点（只改这四条，别扩面）**：N2（坏形行 ↔ T146① 的 cache 规则统一到上面的裁定）· N3（§30.5 半块行：补生产者侧的可能性，或写明「纯防御、只对陌生 `_meta`」）· N4（§5.2 的「1296」已过期，实测 483）· N5（§23 survey 结论「成本无来源」加一句指向 §30.1 ⑤）。
- **不动的**：§30 主口径、D88/D89、§14-25、§23.2、§2 条目表与验收。

### R2 交付裁决（clean · 1 条裁定 + 3 处设计漂移）

**B5 裁定（钱的事，按保守办）**：半块（有 `input` / `output`、缺 `cacheRead`）⇒ **`cost = null`，不显示费用**。

- 理由：缓存价远低于输入价，把缺的 `cacheRead` 按 0 计费 = 系统性高估，等于给用户一个错数字；不给，比给错好。
- 判据同源：§30.1 ⑤「缺价即 null，不猜」、§30.5「坏块不清空已知值」。
- 落点：§30.5 半块行 + T146② 改成 null；代码 `_priced` 的调用条件补 `cacheRead != null`。

**设计漂移三条（设计席改档，不改码）**：

1. §30.9 ② / §30.10-7 ③「清空价目表后费用行消失」限定为「**清表后新开的会话**」——本实现逐帧估价、不重算已估出的费用（RTM 10-1 已按此写）。
2. §30.5 补币种规则：非 USD 价目一律按无价处理（已实现，档里没记）。
3. §30.6 ② 的 `_cacheRead` / `_cacheUncached` 与实现的一个 `_cacheAll` 累加器语义等价——不改。

**顺序**：设计席先改档（本节 1–3 条），落完再派 coder 改 `_priced` 与 T146②。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（§30 修正轮 3：R2 交付裁决已落——B5 半块不估价 · 清表只影响新开会话 · 币种规则 · T146② 改 null；B2 / B4 / B5 均已定）
### 本批条目（覆盖）

| # | 条目 | 设计落点 | 验收（回指） |
|---|---|---|---|
| E1 | `ThincoderKernel` 实现 `ReportsUsage`（空限额 + 空刷新），解锁 `ChatSession.stats` 的门 | §30.1 ①② | §30.9 ⑤ · T143 |
| E2 | 缓存命中 / 未命中 → `UsageStats.cache`（`PromptCache`：`read` / `uncached` 已知，`written` 恒 0），面板既有缓存条显示 | §30.1 ④ · §30.5 | §30.9 ① · T140 / T142 |
| E3 | 费用：只由桌面 `UsagePrices` 价格表估算（线上不发 `cost`）；缺价 ⇒ null（不猜） | §30.1 ⑤ · §30.4 · §30.7 | §30.9 ② · T144 |
| E4 | 回合用量二选一形态：有扩展帧 ⇒ `inputTokens` / `outputTokens` / `costUsd`（`spentTokens` 留空）；无 ⇒ 只有 `spentTokens`（逐字今天） | §30.1 ⑥ · §30.5 | §30.9 ③ · T145 |
| E5 | 旧 CLI / 旧桌面零回归（无扩展帧 ⇒ 逐字走今天） | §30.4 · §30.5 | §30.9 ④ · T141 |
| E6 | 坏块 / 半块不静默丢弃（留痕一行 + 已知的照算；缺 `cacheRead` 的半块不估费用，见 B5） | §30.5 · §15.2 | §30.9 ⑥ · T146 |

**本批不做**：`ReportsUsageLimit`（账户限额，§1 同判）· 推理 token（线上无来源）· 跨会话历史统计 · 账单 / 账号用量 · 改 CLI 的 usage 计算（§30.10）。

### 设计档落点

- 主节 = `docs/design/thincoder-adapter.md` §30（批 23）；同一机制单源（D2），不拆新档。
- 同档本轮改动逐处：§14-25（成本 → 价格表口径 + 判定条件）· §23.2 的 `used` 拆分句与 `cost` 句 · §23.4 D88（删「被否：实现 `ReportsUsage`」，改指 §30.1 ②）与 D89（去掉「线上带 `cost` 时优先」）· §23.5 的成本行 · §23.7-4。现口径只在 §30。

### 机制设计（一句）

线形只扩 `usage_update` 的 `_meta["thincoder.dev/usage"]{input, output, cacheRead}`（per-request；无 `cacheWrite`、无 `cost`），桌面翻成既有 `StatsReported(UsageStats)` + `TurnEnded.usage`；`ReportsUsage` 只做诚实空限额（无账户面，不造窗口）。零新事件、零新接口、零 UI 改动。详见 §30.3–§30.5。

### 受影响文件与执行轮次

| 轮 | 面 | 文件（详见 §30.6） |
|---|---|---|
| R1 | 外仓 `thincoder/` | `thincoder-cli/src/acp/bridge.mjs` · `thincoder-core/agent/turn-loop.mjs`——扩展帧。**外仓库、独立轮、需用户批准**（§25.13 先例）；首步复读两处字段（U19） |
| R2 | 本仓 | `lib/kernel/thincoder/{thincoder_kernel,thincoder_events,thincoder_turns}.dart` · `lib/kernel/thincoder/thincoder_usage.dart`（新，`part of 'thincoder_events.dart'`）· `test/kernel/thincoder_kernel_test.dart` · `test/RTM.md` · `test/integration/thincoder_usage_test.dart`（新） |

- 测试覆盖：T140–T146 = 改动面单测档（§30.8），实施轮跑该档；集成 = RTM 新增 10-1（§30.9），父侧收口跑。
- 分层结论（§30.6 末段，逐档带本轮读数）：`thincoder_events.dart` 808 行（>800）⇒ 新逻辑落新 part 档，不续拆；`thincoder_kernel.dart` 483 行（<800）⇒ 行级新增；`test/kernel/thincoder_kernel_test.dart` 4967 行 ⇒ 末尾追加。

### 关键决策（详见 §30.7）

1. 用既有 `StatsReported` / `UsageStats` / `TurnUsage`，不新增事件、不新增接口、不改 UI（面板缓存条与费用行、footer 拆分与费用都已在盘）。
2. `ReportsUsage` 空限额 + 空刷新（反转的是「实现 `ReportsUsage`」这一项，D88 的旧被否理由已删）：空表 = 「没有已知限额」，不是假窗口。
3. 费用只由桌面价格表估算（唯一有来源的价格源），缺价即 null；线上不发 `cost`。
4. 扩展走 `_meta`、per-request（累计帧的重置点桌面看不见）；`written` 恒 0（线上无写计数）。
5. 拆分与合计二选一：并填会让 footer 总额与 hover 拆分对不上。

### 已裁项（口径与落点）

- **B2 已定**（§4）：批准范围 = R2 本仓轮；R1 外仓扩帧（`thincoder/` 的 `bridge.mjs` / `turn-loop.mjs`）在外仓锚定会话里另开批档。本批单独上线**零可见变化**，缓存与费用要等 R1 落地后自动出现。
- **B4 已定**（§4）：价格表键 = `UsagePrices.of` 的 `provider:model`（与模型选择器同口径）；缺价一律空、不填 0。
- **B5 已定**（§1 的 R2 交付裁决）：半块（缺 `cacheRead`）⇒ `costUsd = null`，不显示费用——缓存价远低于输入价，按 0 计 = 系统性高估，等于给一个错数字。落点：§30.5 半块行 + T146② 改成 null + 实现 `_priced` 的调用条件补 `cacheRead != null`（末项归实施轮）。

### 未验证项

U19（`bridge.mjs:307-308` / `turn-loop.mjs:216-229` 的字段，本席未复读，R1 首步复读）· U20（`UsagePrices.of` 是否命中 thincoder 的 `provider:model`，真机走查）· U21（已闭合：空限额 + `idle` ⇒ 面板不渲染限额区）· U22（已闭合：`UsageCall` 必填 `at` / `duration` / `status` / `provider` / `model`；`input` 传未命中量）——详见 §30.11，均带处置。

## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

设计评审 · 对象 = 批档 §2 + `docs/design/thincoder-adapter.md` §30（评审类型 design；两文件全文已读）。判据限制：无 AGENTS.md、无项目标准档、无文档地图 ⇒ 方法论与 document-ownership 按通用判据，降级记 🔵（第 13 项）。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|---|---|---|---|
| 1 | Document ownership | 🔴 | §30 反决了同档两条仍在位的判据且未改它们：§23.4 D88「被否：实现 `ReportsUsage`（`accountLimits` / `refreshUsage` 对 thincoder 是假面，E3）」↔ §30.1 ②「`accountLimits` 返回空表，`refreshUsage()` 空实现」（+「不造窗口 ⇒ 不是假能力」）；§14-25「core 无价目表 ⇒ 桌面不显示成本（不重算，D89）」与 §23.2「`cost` 不读（CLI 不发；§14-25）。」↔ §30.1 ⑤「价格表估算 `UsagePrices.of(upstream, model)?.cost(call)`；线上带 `cost` 时以线上值优先；缺价 ⇒ `costUsd = null`（不猜、不填 0）」。§14-25 还拿 D89 当依据，而 D89 已被改成「桌面按 `UsagePrices` 价格表估算」⇒ 同一机制两处相反，读者判不出哪份权威 | 把 D88 的「被否」格、§14-25、§23.2 改成 §30 口径（或就地写明反转与理由），只留一份权威；§30.7 第二行补一句点名 D88（反转的是「实现 ReportsUsage」，不只是「新事件」） |
| 2 | Feasibility | 🔴 | §30.6 ③「`lib/kernel/thincoder/thincoder_usage.dart`（新，`part of 'thincoder_kernel.dart'`）」要装「扩展块解析、`CacheTokens` 组装、`UsagePrices.of` + `ModelPrice.cost`、金额取整」——只被 ② 消费（「`_usage` 读 `_meta`；缓存累计；发 `StatsReported`」）。`thincoder_events.dart` 是独立库：`thincoder_kernel.dart` import 段有 `import 'thincoder_events.dart';`，part 段十档里没有它，该档自身也无 `part of` 行 ⇒ 内核库的 part 成员对 events 不可达；反向让 events 引内核库 = 循环 import（同档 §29.6「被否方案是允许循环 import，它会让独立模块边界再次失真」）。① 只加「implements 列表加 `ReportsUsage`；`accountLimits` / `refreshUsage` 两成员」⇒ ③ 的内容在计划里无处可用 | ③ 落到消费方（如 `part of 'thincoder_events.dart'`，形同 §23.3 的 `thincoder_agents.dart`；或独立库由 events import），并写明 `_meta` 解析归 ② 还是 ③（现在两处都写了「解析」） |
| 3 | Branch provenance | 🔴 | §30.5 三个输入态分支给不出场景：`cost` 在线「累加进 `costUsd`」——同档 §30.2「线上只有两字段」、§23.2「`cost` 不读（CLI 不发；§14-25）。」、§23 survey 均称该线今天不存在，也无复现路径；「字段部分」与「`_meta` 缺席 / 坏形」同无观察/复现；三条都无用例（T140=字段齐减 `cacheWrite`、T141=整块缺席、T144=缺价）。另 `cost` 是 ACP 可选 `{amount, currency}`，「累加进 `costUsd`」没说非 USD 怎么办 | 删 `cost` 在线分支（外仓 core 无价目表，本批不产生该字段），或补场景 + 币种规则 + 一条用例；「字段部分 / 坏形」补实读读数或复现路径，并循 §15.2「**绝不静默丢弃**」给留痕与用例 |
| 4 | Acceptance | 🟡 | 缓存写段无断言且三处口径互斥：§30.4「缺字段 = 不知道：不回推、不补 0」、§30.5「`CacheTokens` 的缺省 0 只在整块缺席时用」、§30.7「CLI 无写段时按 0（缺省）」；T140 只断言「`cache!.last == CacheTokens(read:700, uncached:200)`」，`written` 无断言，`CacheTokens` 形状也未引 | 定一条（缺席 ⇒ 不进 `StatsReported` 的 cache；或 ⇒ 0 并写明为何不算造数），三处统一，T140 补写段断言 |
| 5 | Clarity | 🟡 | 承载字段全无引文：§30.1 ③「既有 `StatsReported(UsageStats)`（`lib/kernel/kernel_event.dart:192-196`）」、⑥「字段已在 `TurnUsage`」（`costUsd` / `inputTokens` / `outputTokens`）均无形状；§30.2 两条「门线原文」=「abstract interface class ReportsUsage {」与「final ReportsUsage kernel =>」，都不含 `stats` ⇒ 核心主张「`ChatSession.stats` 只在 `_kernel is ReportsUsage` 时非空」在档内未证，且不在 U19–U21 | 各引一段字段声明原文，或列入 U 表并给处置；`stats` 那行也引原文 |
| 6 | Methodology（doc-state） | 🟡 | 批档 §2「同档 §23.4 D89、§23.7-4/5/6 与两处「成本无来源」已在本轮改成指向 §30（被否句删除，现口径留在 §30）。」与文档现状不符：§14-25 仍写「core 无价目表 ⇒ 桌面不显示成本（不重算，D89）」且无 §30 指针，§23.2 仍写「`cost` 不读（CLI 不发；§14-25）。」 | 按第 1 项落完再回写这句；或把该句改成实际改了哪几处（逐处点名） |
| 7 | Existing-piece | 🟡 | §30 对新名无三问答复：新 `_meta` 键 `thincoder.dev/usage`、新档 `thincoder_usage.dart`、`ThincoderEvents` 新 getter；同档其它新名段都有（§28.3「三问答复（新名字 `renameConfirmed`）」、§29.1「契约名的三问答复（本轮实读）」） | 补一节三问答复（where it lives · name verbatim · who）；`thincoder_usage.dart` 可写 `none found`（该路径不在盘，本次抽检一致） |
| 8 | Requirements | 🟡 | 本批可见结果的一半（费用）在需求档 F20 现行文之外：§30.11 B3「需求档 F20 现行文写「成本本批不做」，本批要做 ⇒ 需求档需扩句（归主 agent）」、§23.5 亦写「成本本批不做」⇒ 10-1 的费用断言暂无可回指的需求行（需求档不在评审范围，其现状 `unverified`） | 需求档 F20 扩句与设计同轮落；或把 10-1 拆两条（缓存 / 费用），费用那条挂扩句后的条目 |
| 9 | Acceptance（RTM） | 🔵 | 10-1 行内无「回溯需求」句（只有节标题「回指 F20 与台账 #244」），也未写扩展帧怎么进用例（真 CLI 需 R1 已落并装到 `thincoder.path`；mock 需推扩展帧）、价目表条目要在测试里配；§29.9 的 4-1 写了「回溯需求」 | 10-1 行补「回溯需求」与「帧来源（mock / 真 CLI + R1 前置）」各一句 |
| 10 | Reference form | 🔵 | 若干引用只有裸行号：§30.1 ①「`lib/kernel/agent_kernel.dart:281-289`」、survey 行「`context_usage_panel.dart:441-448` / `:557` / `:665`」「`usage_prices.dart:805`」；文档头虽声明行号 = 编制日快照，但 `:557` / `:665` 一带无符号可依 | 每处补符号名（`ReportsUsage` 两成员 / `_PromptCacheMeter` / 费用行 / `UsagePrices.of` / `ModelPrice.cost`），行号只作附注 |
| 11 | Tier check | 🔵 | §30.6 分层结论只点名 `thincoder_events.dart`（「已在 >800 名单（§5.2）⇒ 新逻辑落 ③ 新 part 档」），被触碰的另两档也在 >800 名单（`thincoder_kernel.dart`、`test/kernel/thincoder_kernel_test.dart`）。抽检：`thincoder_events.dart` 已过 800 行（末尾 `class _Tape` 落在 800 之后）、`thincoder_usage.dart` 不在盘、`thincoder_turns.dart` 是既有 part ⇒「无跨档档位变化」站得住，名单没点全 | 分层结论把三档一次点名，各带一句「行级新增 / 不续拆」（引 §5.2 既有裁定即可） |
| 12 | Clarity（可见面） | 🔵 | §30.5 让 `TurnEnded.usage` 同时带 `spentTokens` 与拆分，而 `TurnUsage.totalTokens` 取值为 `spentTokens ?? (input + output)`（§23.2 引文）⇒ 拆分在 turn footer 看不到；`thincoder_turns.dart` 的 `_endTurnOf` 现状为 `usage: spent == 0 ? null : TurnUsage(spentTokens: spent)`；§30.6 无 `turn_footer.dart` 一行 | 写明拆分是数据面还是可见面；要可见就补 `turn_footer.dart` 一行 + l10n 键（§23.3 ⑤ 先例）+ 一条用例 |
| 13 | Methodology（条件） | 🔵 | 无 AGENTS.md（工作目录与评审范围内均无）、无项目标准档、无文档地图 ⇒ 方法论与 ownership 只能按通用判据；「是否该新开档」只能按同档 D2「同一机制单源」自查（§30 为同档新节，符合） | 无需动设计；此条记录评审条件限制 |

计数：🔴 3 · 🟡 5 · 🔵 5（🔴 = 第 1–3 项；🟡 = 第 4–8 项；🔵 = 第 9–13 项）。

VERDICT: changes-required

### 轮次 2（评审子代理）

设计评审（轮 2）· 对象 = 批档 §2 + `docs/design/thincoder-adapter.md` §30（交叉核 §14-25 / §23.2 / §23.4 / §23.5 / §23.7-4 / §5.2）；两档本轮重读。轮 1 的 13 条：9 条 Fixed · 2 条 Accepted · 0 条 Unfixed；新增 3🟡 + 2🔵，无新增 🔴。

| # | Orig# | 文件 | 严重度 | 状态 | 证据 / 说明 |
|---|---|---|---|---|---|
| 1 | 1 | design §23.4 D88 / §14-25 / §23.2 | 🔴 | Fixed | D88 的被否格已删并改指「被否：新事件 `SessionUsageReported`（宿主与翻译面双改，E2 违规）。thincoder 对 `ReportsUsage` 的实现见 §30.1 ②（批 23）」；§14-25 现为「| 25 | 成本（F20） | 桌面按 `UsagePrices` 价格表估算（机制与判据 = §30.1 ⑤ / §30.5）」；§23.2 现为「`cost` 不在线上（§30.4）；费用由桌面价格表估算（§30.1 ⑤），缺价即不显示（§14-25）。」；D89 / §23.5 成本行 / §23.7-4 同口径；§30.7 第二行点名「**反转的是「实现 `ReportsUsage`」这一项**」⇒ 只剩一份权威 |
| 2 | 2 | design §30.6 ③ + 解析归属 | 🔴 | Fixed | ③ 改「**`part of 'thincoder_events.dart'`**」，归属写明「因为消费方是 ②——挂内核库不可达」。本轮实测佐证：`thincoder_events.dart` 只 import（无 `part of`），`thincoder_kernel.dart` 第 20 行 import 它、其 part 十档不含它 ⇒ 落点与依赖方向一致 |
| 3 | 3 | design §30.4 / §30.5 | 🔴 | Fixed | `cost` 在线分支已删（「**不在线上**：`cacheWrite`（core 无写计数）、`cost`（core 无价目表）——两者都要改 CLI 的 usage 计算，本批不做（§30.10-4）。」）；坏形 / 半块改为留痕 + 用例（T146），坏形引先例原文。残项见第 N3 行 |
| 4 | 4 | design §30.1 ④ / §30.7 / T140 | 🟡 | Fixed | 写段定一条：「`written` 恒 0：线上没有写计数（§30.4），0 说的是「没有已知写入量」，不是「没写」」+ §30.7 的「`CacheTokens` 三段是定长整数场（无「未知」态）」理由；三处互斥口径已合并；T140 断言「`CacheTokens(read:700, written:0, uncached:200)`」 |
| 5 | 5 | design §30.2 | 🟡 | Fixed | 承载字段 8 条原文在档，含门线「UsageStats? get stats => switch (_kernel) {」⇒ 核心主张有引文 |
| 6 | 6 | 批档 §2 | 🟡 | Fixed | 现逐处点名「§14-25（成本 → 价格表口径 + 判定条件）」，六处（§14-25 / §23.2 / D88 / D89 / §23.5 / §23.7-4）本轮逐一核对均与文档现状相符 |
| 7 | 7 | design §30.12 | 🟡 | Fixed | 三问答复已补：`thincoder.dev/usage`、新档路径、`ThincoderEvents.turnUsage`，各带 `none found` 与「谁用」 |
| 8 | 8 | 批档 §2 B3 / §30.9 | 🟡 | Accepted | 非修改项且理由成立：需求档归主 agent（本席不改），两次实读未见扩句已记 B3，10-1 的回指写成条件式（见第 9 行）⇒ 属 R5 协调项，非缺陷 |
| 9 | 9 | design §30.9 | 🔵 | Fixed | 补「**回溯需求** = 需求档 F20（本批扩句；扩句未落盘时见 §30.11 B3）。」与「**帧来源** = mock 传输推扩展帧（`usage_update` + `_meta["thincoder.dev/usage"]`）」+ 价目表在用例里配 |
| 10 | 10 | design §30 survey / §30.2 | 🔵 | Accepted | 文档头声明行号 = 编制日快照（实施按符号定位），门线主张已改由 §30.2 的原文承载 ⇒ 可接受；对齐 ① 仍留裸「`:557` / `:665`」 |
| 11 | 11 | design §30.6 末段 | 🔵 | Fixed | 三档一次点名并带读数，结论「三档同在本仓内核适配一面，无跨档档位变化。」本轮抽检：`thincoder_kernel.dart` 末行止于 483（与「483 行」一致）、`thincoder_events.dart` 末行止于 808、新档不在盘 ⇒ 结论成立 |
| 12 | 12 | design §30.1 ⑥ / §30.5 | 🔵 | Fixed | 可见面定死：「**不设 `spentTokens`**」+「拆分与合计只填一种形态，不并填」⇒ `totalTokens = input + output`，split 走既有 hint |
| 13 | 13 | 评审条件 | 🔵 | Accepted | 本轮复核：`PROJECT-MANIFEST.json` 的 `"docMap": ""` 为空、无 AGENTS.md ⇒ 方法论与 ownership 仍只能按通用判据；§30 的 survey 主张「`index.publicRepos` 为空」实测相符（`"publicRepos": []`） |
| N1 | (new) | 批档 §1 ↔ §2 / §30.11 B3 | 🟡 | New | 同一记录两处相反：§1「**需求档已扩**（父侧笔）」↔ §2「父侧称需求档 F20 已扩句、§10 已记 B1 例外；本席两次实读未见」。需求档不在本次评审范围 ⇒ 只报不改（R1/R7a）；父侧批准前用一次实读定论即可，非 must-fix |
| N2 | (new) | design §30.5 坏形行 ↔ T146① | 🟡 | New | 坏形行写「| 坏形（不是映射，或三段无一是非负整数） | 同上，且写一行 `appEvent('thincoder', …)` 点名坏块」，而 T146① 写「① 零 `StatsReported`、`cache` 不变」；「同上」含「`stats.cache == null`」⇒ 若坏块之前已有好帧，两条规则给出相反结果（单帧用例两种读法都过）。补一句定死「坏块是否清空已知 cache」即可，非 must-fix |
| N3 | (new) | design §30.5 半块行 | 🟡 | New | 轮 1 第 3 项的残余：「| 半块（`input` / `cacheRead` 缺一，或 `output` 缺） | 用已知的算」仍无实读读数或复现路径，而 §30.4 把三段都定为「非负整数，必填」⇒ 本设计自己的生产者发不出半块。补一句生产侧可能（如某后端无缓存计数）或注明「纯防外来 `_meta`」，非 must-fix |
| N4 | (new) | design §5.2 | 🔵 | New | 「`thincoder_kernel.dart`（会话治理 A1 后 1296）入 >800 名单，行级新增不续拆。」与实测 483 行（§30.6 同读数）不符 ⇒ 台账数字陈旧；档位结论不受影响（483 < 800，且旧裁定同为「不续拆」） |
| N5 | (new) | design §23 survey 结论 | 🔵 | New | 「成本无来源。」未指 §30；链条 §23 头 → §14-25 → §30 可走通，故仅属文档卫生（补「批 23 起由桌面价格表估算，§30.1 ⑤」） |

计数：轮 1 三条 🔴 全落地（Fixed）· 🟡 4 Fixed / 1 Accepted · 🔵 3 Fixed / 2 Accepted · 新增 3🟡（均非 must-fix）+ 2🔵 · 未决 🔴 0。

VERDICT: pass

## §4 用户批准（主 agent）

### 用户批准（R2 本仓轮）

- 2026-11-15 20:54 · 用户原话：**「批准」**——批准 §30 设计进入实施（应用侧 5 档 + T140–T146 七条用例）。
- **批准范围**：R2 本仓轮，即 `ReportsUsage` 实现 + ACP 扩展帧的**消费侧**翻译。**不含** R1 外仓轮（`thincoder/` 的扩展帧生产与 context% 改实测）——那一轮须在 `thincoder/` 锚定的会话里另开批档。
- **可见结果预期（用户已知悉）**：本批单独上线**零可见变化**；缓存三段与费用要等 R1 落地后自动出现。
- **已定 B4**：价格表键 = `UsagePrices.of` 的 `provider:model`（与模型选择器同口径）；缺价一律空、不填 0。

## §5 实施记录（eng-coder）

### 实施记录 · R2 本仓轮（eng-coder）

**范围**：§4 批准的 R2 = `ReportsUsage` 实现 + ACP 扩展帧的消费侧翻译。R1 外仓轮（`thincoder/` 的扩展帧生产）不在本批，未动。

#### 改动面（逐档）

| # | 文件 | 改动 |
|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_kernel.dart` | implements 列表加 `ReportsUsage`；`accountLimits => const []`；`refreshUsage()` 返回已完成 Future、不发请求 |
| ② | `lib/kernel/thincoder/thincoder_events.dart` | 会话级 `_cacheAll` / `_cacheKnown` / `_costUsd`，回合级 `_turnInput` / `_turnOutput` / `_turnCost`（`begin()` 清回合、不清会话）；公开 `turnUsage` getter；`_usage` 末尾接扩展块：累计 + 发 `StatsReported` |
| ③ | `lib/kernel/thincoder/thincoder_usage.dart`（新，**`part of 'thincoder_events.dart'`**） | `_meta["thincoder.dev/usage"]` 形判（absent / whole / partial / bad）、`CacheTokens` 组装、`UsagePrices.of` + `ModelPrice.cost`、金额取整（1e-6）、坏形与半块的 `appEvent` 留痕 |
| ④ | `lib/kernel/thincoder/thincoder_turns.dart` | `_endTurnOf`：`usage: split ?? (spent == 0 ? null : TurnUsage(spentTokens: spent))`，拆分与合计只填一种 |
| ⑤ | `test/kernel/thincoder_kernel_test.dart` | 末尾新增 group `thincoder usage frames (F20, §30)`，T140–T146 七条 |
| ⑥ | `test/RTM.md` · `test/integration/thincoder_usage_test.dart`（新） | 第 10 节 + 行 10-1（规模窗 9 → 10）+ 用例体；用例从上下文环进面板，两回合各带一次工具与一次扩展帧 |
| ⑦ | 外仓 `thincoder/...` | **未动**（R1，不在批准范围） |

#### 验收对照（§30.9 ①–⑥ / 批档 §2 E1–E6）

| # | 状态 | 条目 | 机检 |
|---|---|---|---|
| E1 | ✅ Done | `ReportsUsage` 空限额 + 空刷新，解锁 `ChatSession.stats` | T143（`isA<ReportsUsage>`、`accountLimits` 空、`refreshUsage` 零请求、`session.stats!.cache/costUsd` 为 null） |
| E2 | ✅ Done | 缓存命中/未命中 → `UsageStats.cache`，`written` 恒 0 | T140（`[700, 0, 200]`）· T142（会话 `[1000, 0, 400]`、`last` = 第二条） |
| E3 | ✅ Done | 费用只由桌面价格表估算，缺价 ⇒ null | T144（有价 = `ModelPrice.cost` 手算值；空表 ⇒ null 但 cache 仍在） |
| E4 | ✅ Done | 回合二选一形态 | T145（拆分：`inputTokens` 1400 / `outputTokens` 434 / `costUsd` 非空 / `spentTokens` null / `totalTokens` 1834；旧 CLI 回合只有 `spentTokens` 70） |
| E5 | ✅ Done | 旧 CLI 零回归 | T141（零 `StatsReported`，`usage` 三读与今天逐字同值） |
| E6 | ✅ Done | 坏块 / 半块不静默丢弃 | T146（坏块不增发 stats、已知 cache/cost 保持；冷态仍 null；半块 cache 不丢、拆分与费用在；两态各恰一行 `appEvent`） |
| — | ✅ Done | 集成 10-1 | `test/integration/thincoder_usage_test.dart` 通过（缓存条 60% / 会话 71%、费用 `$0.01`、空价目表新会话无费用行且无 `$0.00`） |

#### 机检读数（本轮实跑）

- `dart analyze lib/kernel/thincoder test/kernel/thincoder_kernel_test.dart test/integration/thincoder_usage_test.dart` ⇒ `No issues found!`
- `flutter test test/kernel/thincoder_kernel_test.dart --plain-name "thincoder usage frames"` ⇒ **7 passed**（T140–T146）
- `flutter test test/kernel/thincoder_kernel_test.dart` ⇒ **161 passed**（T96–T98 等既有用例不回归）
- `flutter test test/kernel/thincoder_kernel_test.dart test/integration/thincoder_usage_test.dart` ⇒ **162 passed / 0 failed**
- `doc_check(mode:"gate", docs:["test/RTM.md"])` ⇒ `DOC-CHECK GATE: PASS`（1 档全清）

#### 内部审计与代码评审轮次

- **内部审计（explore，比对设计 §30）**：3 条 —— 1 条我方修正（10-1 的回合原本不带工具，与 §30.9「两条带工具的回合」不符，已补 `tool_call` + `tool_call_update`）；2 条为设计档陈述漂移（列在上抛与披露，归设计席）。
- **内部代码评审（advisor `type="code"`）**：判 **pass**，无 🔴；1🟡（可选，半块费用口径待裁）+ 5🔵 + 1🟡（协调项：本段当时为空）。
- **修正轮 1（评审后）**：① `count()` 判据补 `value.isFinite`（`1e999` 解成 Infinity 的路径）；② 坏形/半块的 `appEvent` 移进 ③（设计的「留痕」落点），② 只调它、累计、发事件；③ 集成固件的 `used` 对齐 §30.4（1234 / 600）。修后 `dart analyze` 干净、两档测试 **162 passed**。
- **终态**：`clean`（无未修项；剩一条待裁 + 三条设计档漂移，均非代码缺陷）。

#### 上抛与披露

- **[上抛·待裁] B5（新）**：半块（有 `input` / `output`、缺 `cacheRead`）时，本实现按「cacheRead = 0」计费（整段输入按未命中价），这是 §30.5「`input` + `output` 齐 ⇒ 算费用」的字面实现；但 §30.1 ⑤ 的原则是「缺价即 null，不猜」，而缓存价通常远低于输入价 ⇒ 费用会系统性高估，且留痕只点名缺字段、不说「按 0 计费」。两种处置：缺 `cacheRead` 时 `cost = null`，或保留算法并在留痕里写明假设。T146② 现钉住的是后者（`half.costUsd, isNotNull`）。**未擅自改**：设计已授权「算费用」。
- **[上抛·知会] 设计档漂移（归设计席）**：
  1. §30.9 ② / §30.10-7 ③「清空价目表后不出现 / 费用行消失」——本实现逐帧估价、不重算，已估出的费用不会因后来清表而消失；该句只对清表后新开的会话成立（RTM 10-1 行已按此写）。
  2. §30.5 未记币种规则：非 USD 价目一律按「无价」处理（`costUsd` 为 null，不写错单位）。
  3. §30.6 ② 草拟的字段名 `_cacheRead` / `_cacheUncached` 实现为一个 `CacheTokens _cacheAll` 累加器（累计语义等价）。
- **U22 已闭合**（本轮实读 `lib/usage/usage_record.dart`）：`UsageCall` 的必填形参 = `at` / `duration` / `status` / `provider` / `model`，且 `input` 的语义是「Input not read from the cache」⇒ 传未命中部分，缓存部分走 `cacheRead`。U20（真实价目表是否命中 `provider:model`）仍待真机走查。
- **不做**（与 §30.10 一致）：不改 CLI 的 usage 计算（R1）、不新增内置价目（§30.10-6）、不做账号限额 / 推理 token / 跨会话统计。

### 实施记录 · 修正轮（R2 交付裁决 B5 落地 · eng-coder）

**范围**：§1「R2 交付裁决」的 B5 —— 半块（有 `input` / `output`、缺 `cacheRead`）不估价、`costUsd = null`。设计档修正轮 3 已落（§30.1 ⑤ · §30.5 半块行 · §30.8 T146②），本轮只改代码与用例；R1 外仓与其它条目不动。

#### 改动面（逐档）

| # | 文件 | 改动 |
|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_usage.dart` | 估价条件收成三段齐：`input` + `cacheRead` 齐才组 cache 段；`cost` 再要求 `output != null`，缺一即 null（不再按 `cacheRead = 0` 估价）。`_priced` 的 `cacheRead` 仍为必填。半块留痕区分「字段缺席」与「有值但不是计数」。 |
| ② | `test/kernel/thincoder_kernel_test.dart` | T146②：`TurnEnded.usage.costUsd` 由 `isNotNull` 改为 `isNull`；补断言「半块不增发 `StatsReported`」与「会话 cache / costUsd 保持已知值」；T144 注释改为「清表后新开的会话」。 |

#### 机检读数（本轮实跑）

- `dart analyze lib/kernel/thincoder/thincoder_usage.dart test/kernel/thincoder_kernel_test.dart` ⇒ `No issues found!`
- `flutter test test/kernel/thincoder_kernel_test.dart --plain-name "thincoder usage frames"` ⇒ **7 passed**（T140–T146）
- `flutter test test/kernel/thincoder_kernel_test.dart` ⇒ **161 passed**（既有用例不回归）

#### 内部审计与代码评审轮次

- **内部审计（explore，比对 §30 与 B5）**：`no divergence found`，0 must-fix；2 条 🔵 注释精度项，均已修（T144 注释「同一个会话」→「清表后新开会话」；T146② 的 reason 限定到「没有 `cacheRead` 的半块」）。
- **内部代码评审（advisor `type="code"`）**：判 **pass**，无 🔴；1🟡（可选：本段此前仍记 B5 待裁，由本 append 覆盖）+ 4🔵。4🔵 中修 2：`_meta` 非映射时的文档承诺收窄为「键下的块不读全才留痕」；留痕区分缺席 / 非计数。另 2 条留建议：缺 `output` 的半块无用例（纯防御路径，§30.8 用例表未列）；`input` 未知时 footer 把未知显示成 0（设计档「缺的留空」的显示面后果）。
- **终态**：`clean`。

#### 未改与说明

- 不新增半块形状用例：§30.8 用例表只规定「缺 `cacheRead`、`input` / `output` 在」一种；`input` + `cacheRead` 齐的半块是纯防御路径（§30.5：生产者三段必填）。
- 集成用例 `test/integration/thincoder_usage_test.dart` 只含整块帧，本轮未动；「未集成测试验证 —— 父侧收口跑是唯一一次集成测试跑」。

## §6 验证与收口（父代理）

### 验证与收口（R2 本仓轮）

**父侧实跑（本席执行，2026-11-15 21:25）**：`flutter test test/kernel/thincoder_kernel_test.dart test/integration/thincoder_usage_test.dart` ⇒ **162 passed / All tests passed**（含集成用例 10-1）。环境注记：`flutter` 不在会话 PATH 上，实操路径 `C:\Users\xinbo\repos\flutter\bin`。

**改动面**：`lib/kernel/thincoder/thincoder_usage.dart`（新）· `thincoder_events.dart` · `thincoder_kernel.dart` · `thincoder_turns.dart` · `test/kernel/thincoder_kernel_test.dart` · `test/integration/thincoder_usage_test.dart`（新）· `test/RTM.md`。

**交付对照**：

| 条目 | 结果 | 读数 |
|---|---|---|
| E1 `ReportsUsage` | ✅ | `accountLimits => const []`、`refreshUsage()` 不发请求；T143 |
| E2 缓存三段 | ✅ | `written` 恒 0；T140 / T142 |
| E3 费用 | ✅ | 只由桌面价格表估；缺价 ⇒ null；缺 `cacheRead` ⇒ null（B5）；T144 / T146② |
| E4 回合二选一 | ✅ | 拆分 ∥ `spentTokens`，不并填；T145 |
| E5 旧 CLI 零回归 | ✅ | T141 |
| E6 坏块/半块 | ✅ | 一行 `appEvent` + 已知值不清空；T146 |

**集成窗**：`test/RTM.md` 现 **10 / 50–100**（本批新增第 10 节行 10-1，用例 `test/integration/thincoder_usage_test.dart`）。

**机检**：本批所有 `batch` 写入回执均为 `DOC-CHECK GATE: PASS`；§6 本次写入自带同一门检。

**未决项（已落台账）**：#248（另一种半块形 `input`+`cacheRead`、缺 `output` 无用例）· #249（`inputTokens ?? 0` 在 footer 显成「0 in」的显示缺省）· #250（U20 真实价目表是否命中 `provider:model`，待真机走查，锚 R1）。

**已知空缺（如实记）**：本批单独上线**零可见变化**——缓存三段与费用要等 R1（`thincoder/` 外仓轮，独立批档）。真机走查 §30.10-7 未做，原因同此。

**暂缓批复核**：无。
