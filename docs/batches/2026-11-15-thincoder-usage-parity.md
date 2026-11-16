# 2026-11-15 · thincoder-usage-parity
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-15 · 来源 = 用户 2026-11-15「nonono，我们直接有模板了，直接全抄过来，后端也抄过来」。
> 台账 = #244（— · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
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

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（§30（批 23）· R1 外仓 + R2 本仓；B1–B4 待裁）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

| # | 条目 | 设计落点 | 验收（回指） |
|---|---|---|---|
| E1 | `ThincoderKernel` 实现 `ReportsUsage`（空限额 + 空刷新），解锁 `ChatSession.stats` 的门 | §30.1 ①② | §30.9 ⑤ · T143 |
| E2 | 缓存命中 / 未命中 → `UsageStats.cache`（`PromptCache` 三段），面板既有缓存条显示 | §30.1 ④ · §30.5 | §30.9 ① · T140 / T142 |
| E3 | 费用：桌面 `UsagePrices` 价格表估算，线上带 `cost` 时优先；缺价 ⇒ null（不猜） | §30.1 ⑤ · §30.7 | §30.9 ② · T144 |
| E4 | 回合用量带拆分与费用（`TurnEnded.usage` 的 `inputTokens` / `outputTokens` / `costUsd`） | §30.1 ⑥ · §30.5 | §30.9 ③ · T145 |
| E5 | 旧 CLI / 旧桌面零回归（无扩展帧 ⇒ 逐字走今天） | §30.4 · §30.5 | §30.9 ④ · T141 |

**本批不做**：`ReportsUsageLimit`（账户限额，§1 同判）· 推理 token（线上无来源）· 跨会话历史统计 · 账单 / 账号用量（§30.10）。

### 设计档落点

- 新增 `docs/design/thincoder-adapter.md` §30（批 23）；同档 §23.4 D89、§23.7-4/5/6 与两处「成本无来源」已在本轮改成指向 §30（被否句删除，现口径留在 §30）。
- 同一机制单源（D2）：§30 之后不再拆新档。

### 机制设计（一句）

线形扩 `usage_update` 的 `_meta["thincoder.dev/usage"]{input, output, cacheRead, cacheWrite?}`（per-request），桌面翻成既有 `StatsReported(UsageStats)` + `TurnEnded.usage`；`ReportsUsage` 只做诚实空限额（无账户面，不造窗口）。零新事件、零新接口、零 UI 改动。详见 §30.3–§30.5。

### 受影响文件与执行轮次

| 轮 | 面 | 文件（详见 §30.6） |
|---|---|---|
| R1 | 外仓 `thincoder/` | `thincoder-cli/src/acp/bridge.mjs` · `thincoder-core/agent/turn-loop.mjs`——扩展帧。**外仓库、独立轮、需用户批准**（§25.13 先例）；首步复读两处字段（U19） |
| R2 | 本仓 | `lib/kernel/thincoder/{thincoder_kernel,thincoder_events,thincoder_usage(新),thincoder_turns}.dart` · `test/kernel/thincoder_kernel_test.dart` · `test/RTM.md` · `test/integration/thincoder_usage_test.dart`(新) |

- 测试覆盖：T140–T145 = 改动面单测档（§30.8），实施轮跑该档；集成 = RTM 新增 10-1（§30.9），父侧收口跑。
- 分层结论：R2 全在本仓内核适配一面，无跨档档位变化；`thincoder_events.dart` 已在 >800 名单 ⇒ 新逻辑落新 part 档，不动结构（§30.6 末段）。

### 关键决策（详见 §30.7）

1. 用既有 `StatsReported` / `UsageStats` / `TurnUsage`，不新增事件、不新增接口、不改 UI（面板缓存条与费用行已在盘）。
2. `ReportsUsage` 空限额 + 空刷新：空表 = 「没有已知限额」，不是假窗口。
3. 费用桌面价格表估算（唯一有来源的价格源），缺价即 null；线上带 `cost` 时以线上为准。
4. 扩展走 `_meta`、per-request（累计帧的重置点桌面看不见）。

### 上抛项（待裁）

- **[上抛·待裁] B1**：`ReportsUsage` 的语义 = 账户限额面（`accountLimits` / `refreshUsage`），§1 括注写的是它解锁的可见面。本档按「空限额 + `StatsReported`」落地；若判为不该出现在 thincoder 上，代价 = 面板永不显示缓存 / 费用。
- **[上抛·待裁] B2**：本批可见结果依赖 **R1 外仓扩帧**。加 = 一次外仓库轮（需用户批准）；不加 = 本批零可见变化。建议同批两轮（R1 外仓 → R2 本仓）。
- **[上抛·待裁] B3**：需求档 F20 现行文写「成本本批不做」，本批要做 ⇒ 需求档需扩句（归主 agent，本席不改需求档）。
- **[上抛·待裁] B4**：价格表 `upstream` 键取值（`provider:model` 的 provider 段）需确认；缺价一律 null ⇒ 错键的代价 = 费用恒空，不造数。

### 未验证项

U19（`bridge.mjs:307-308` / `turn-loop.mjs:216-229` 的字段，本席未复读）· U20（`UsagePrices.of` 对 thincoder 的 `provider:model` 是否命中）· U21（`limits` 空 + `limitsState: idle` 的面板渲染）——详见 §30.11，均带处置。

## §3 设计评审（评审子代理）

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

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
