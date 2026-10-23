# 2026-10-22 · browser-biz-test-mode
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-22 · 来源 = 用户 2026-10-22 23:25「我想把plan模式改成debug测试模型…」→ 23:33 补全业务场景 → 23:37 指出不稳定根因与运行约束 → 23:42「如果做就全做了，并且单独给我一个像plan一样的模式切换功能」。
> 台账 = #149（browser-biz-test · 归批）。前情 = 无（新板块首篇）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与已定决定（主 agent）

需求档：`docs/requirements/browser-biz-test.md`（F1–F6 + 边界 + 验收）。用户四轮收敛（23:25 / 23:33 / 23:37 / 23:42），关键原话见需求档 §1。

**已定决定（用户逐字确认）**

- **已定决定**：注入方式 = **切进 btest 时注入一次模式卡（≈1.5k）+ 规则落盘、跑前必读** · 用户原话：「按这个」 · 时间：2026-10-22 23:46
- **已定决定**：**不动外仓 `thincoder/`**（一期）；正统的 ACP 系统提示词通道留二期 · 用户原话：「按这个」（对「一期不动外仓」方案的确认） · 时间：2026-10-22 23:46
- **已定决定**：跑完一轮再报，不截图、不边走边停 · 用户原话：「跑完一轮业务一起报给我列表，不需要截图，不要边走边停」 · 时间：2026-10-22 23:37
- **已定决定**：业务线流程由 **AI 生成与更新**，用户不手写 · 用户原话：「业务线可以写，但是我不可能自己更新，得AI来写」 · 时间：2026-10-22 23:42
- **已定决定**：不稳定根因 = **忘了预期结果 / 忘了 case 来自旧代码** ⇒ 二者都必须落盘 · 用户原话：「不稳定是因为它有时候忘了预期结果或者是忘了有的case是旧代码生成的」 · 时间：2026-10-22 23:42
- **已定决定**：模式名字面 = 「像 plan 一样的模式切换功能」 · 用户原话：「单独给我一个像plan一样的模式切换功能」 · 时间：2026-10-22 23:42

**主 agent 补充裁定（可被设计轮反驳，附证据即可）**

1. **模式归属**：`btest` 是**宿主 overlay**，不是内核 mode（不改 `mode` 的 normal/plan 语义，不动 ACP）。
2. **提示词落点**：文本在 **BaoCode 仓内**（版本化、可 diff），不写进用户家目录的 skill（现状那份只是草稿）。
3. **预期文件位置**：业务仓 `docs/qa/<业务线>.md`（人可读、随业务仓提交）；写入属于产品行为，需在验收里写清"AI 写、人可编辑"。
4. **审批**：btest 下浏览器动作自动放行；**生产域名默认禁止写操作**；只读轮禁止提交类动作。
5. **token**：模式卡只在切模式时注入一次；跑前读文件不占常驻上下文。

**已知风险（设计需正面回答）**：① "注入一次"在长会话里仍会漂移——靠"跑前必读文件"兜底，设计要写清读的时机与判据；② 自动放行 + 已登录真实账号 = 可能误操作真实数据，需要域名/动作白名单；③ 报告无截图 ⇒ 证据全靠接口/console/字段值，需定义"什么样的证据算可复核"。

## 主 agent 对设计上抛的裁定（2026-10-22 23:52）

**上抛 1：每轮 run 起始一行提醒算不算"重复注入"** ⇒ **不算，批准**。
理由：用户的约束是 token（模式卡 1.2k × 每轮 = 50 轮 60k），而 run 起始那一行约 50 token；它是**漂移兜底**——去掉它，兜底只剩 run 闸，长会话里"忘了读预期"就没有任何拦截。附一条要求：该行文案必须**不重复模式卡内容**，只写"本轮开始前先读 `docs/qa/<业务线>.md`"。

**上抛 2：自动放行的应答点（内核权限请求处 vs 宿主 MCP 调用路径）** ⇒ **两条都批准，按"先内核、拿不到数据就退 MCP"落地**，但附硬要求：
- 无论落在哪条路径，必须有**一条用例**证明策略**拿到了工具名与参数**（不是只看"是 browser 组就放行"）——否则白名单/只读/生产禁写三条判据都退化成摆设。
- 若退到 MCP 路径会多一次审批卡，**必须在验收走查里记录实际表现**（用户要求"不边走边停"，多弹卡会破坏这一点；若确实多弹，报告为阻塞项，由主 agent 决定是否接受）。

**知会三条 unverified 假设**：① `HostMcpServer` 是否按会话暴露工具列表 —— 实施轮实读确认；② 业务仓 `docs/qa/` 是否存在 —— 不存在则由运行期创建（设计已允许）；③ dev/生产域名清单由用户在设置页填（设计不写死）—— 验收里要有"未配置白名单时一律走原审批"的用例。

## 评审后新增需求（2026-10-22 23:56 · 用户提出，主 agent 已落档）

**已定决定**：预期结果必须从**业务设计文档**判断，且每条预期带出处（`expectFrom`），来源分三级强弱；**代码现状不得作为预期来源** · 用户原话：「预期结果是不是得从设计文档里面判断」→「要」 · 时间：2026-10-22 23:56

**落档位置**：`docs/requirements/browser-biz-test.md` 的 F3（加"预期出处"字段）、新增 **F3.1**（三级来源 + 禁止以代码现状为预期）、验收 3（强化为"预期来自盘上且带出处"）。

**事实依据（实读）**：业务仓有大量现成设计档——`v2-fleetmanagement/docs` 182 份 md、`database/docs` 119、
`v2-booking/docs` 73、`api/docs` 71、`v2-timecharter/docs` 27、`docs` 总库（业务梳理 / 租船业务 / 平台化）。

`v2-booking/docs` 下的 vibe-coding 档 688 KB 且**带编号小节**（`## 3.1 VoyageOperator · Booking 首页`），可引用到节；
同目录 audits 下的 smoke-checklist 51 KB 是现成冒烟清单。

**三级来源**：强 = 业务设计档明写；中 = 冒烟清单 / 历史 issue（905 条，已归 19 类）；弱 = 代码现状（**不得**作预期，否则"实现即正确"，bug 被判正常）。

**后续动作**：设计档需把 `expectFrom` 并入 flow 文件字段与报告列——等当前修正轮（#9，评审 13 条）落地验证后，派一轮追加修正，不与其并发。

## 新增需求：操作方式必须模拟真人（2026-10-23 00:01）

**已定决定**：测试时通过**点击与输入**操作，不靠直接访问 URL、不靠按编号/内部标识选择目标 · 用户原话：「我像让thincoder做测试的时候，通过点击和输入的方式做，而不是通过访问url，或者是点击编号来选择，因为尽可能的模仿用户操作」 · 时间：2026-10-23 00:01

**落档**：`docs/requirements/browser-biz-test.md` F2.1（六条细则）+ 验收 6（可机检）。

**六条细则**：

① 入口只一次 URL 导航，之后一律点菜单/链接/按钮，禁手输深链；

② 按**可见文字**（按钮文字 / 字段 label / 表头列名 / 角色）定位，禁以 DOM id / class / xpath / 快照编号为首选；

③ **按可见文本找不到可点目标本身就是缺陷**（label 未关联 / 可访问性缺失），记入报告不绕道；

④ 输入逐字键入，禁用 JS 直接赋值 / 改隐藏字段 / 绕表单调接口；

⑤ 读接口与 console 只用于判定，不用于推进流程；

⑥ 唯一例外——用户本人也无法完成的步骤（如页面无菜单入口，只能输 URL：既有 issue #899 即此类）⇒
**先记缺陷**，再用 URL 继续并在报告标注「本步绕道」。

**验收 6（机检）**：一轮内 `browser_navigate` 次数 = 1；`browser_evaluate` 无写值调用；所有 click/type 目标以可见文本/label/角色描述；浏览器请求全部源于真实点击。

**对设计的追加影响**（与 `expectFrom` 一并交下一轮修正）：工具面须把「深链导航」与「JS 写值」从 btest 允许面里剔掉或降级；`browser_evaluate` 在 btest 下只读（与 §3.6 的只读轮判定合并考虑）；模式卡需新增操作纪律条目（标签锚点续 `[D7]`）。

## 主 agent 对 F2.1 上抛的裁定（2026-10-23 00:12）

**上抛 1：`browser_evaluate` 是否新增 `readOnly` 参数** ⇒ **不新增**。
理由：设计已定「所有轮次都不得写值」（`:285` 判据 1），写值在任何轮次都被拒 ⇒ 再要求只读轮带 `readOnly: true` 是**第二条同向判据**，只会多一个可忘的参数、多一处实现面。只读轮的「只读」由**click / type / press 被拒**来体现，那才是真正的动作面。
⇒ 下一轮设计修正：删掉 `:285` 判据 2（readOnly 参数），`browser_tools.dart` 不新增参数；§10 第 8 条上抛随之关闭。

**上抛 2：「按文字找不到可点目标」宿主判不了** ⇒ **接受走查**（兜底计数 + 报告步骤列写「无可见文字：<元素描述>」+ `browser_history` 的 clicks 对账）。理由：宿主只看得到参数，看不到 DOM；硬造一个判据只会得到假读数。代价 = 该项是走查而非硬闸，已记在案。

**知会 3：需求档验收 6 未含 `detour` 机检** ⇒ 已补（见同轮需求档改动）：验收 6 增一项「`detour` 计数 = 报告绕道行数」。

**一并确认设计新发现的四个在范围问题**（均已实读，均已入档，作为**设计修正的既成事实**保留）：
① `browser_act` 自带 navigate 步 ⇒ 入口判据必须同判（已 `:259-265`）；
② `browser_open` 也带 url ⇒ 第二入口（已计入）；
③ `browser_request` 的 `replay` = 绕表单调接口 ⇒ btest 下拒绝（已 `:291`）；
④ `browser_evaluate` 原本没有 `readOnly` 参数（`lib/browser/browser_tools.dart:297-303` 实读）⇒ 上抛 1 的裁定直接消除了这条不存在的参数。

## 评审政策变更（2026-10-23 00:23 · 用户裁定）

**已定决定**：设计评审**不设轮次上限**，必须严谨到零 🔴、🟡 清零（或逐条给出可被反驳的书面理由）为止 · 用户原话：「无限迭代！！！必须严谨！！！」 · 时间：2026-10-23 00:23

**主 agent 撤回**：本轮对话中「4 轮是个合理收口点」的提议由用户否掉，撤回，不再作为收口条件。

**因此调整的三件事**：
1. **评审范围**：第四轮起不再限于「只验上一轮的表」，改为**全文全判据**评审（避免只验增量而漏掉整体一致性）；每轮仍先验上一轮条目，再整体过一遍。
2. **收敛判据**：零 🔴 ∧（零 🟡 ∨ 每条 🟡 有书面理由且该理由可被反驳）⇒ 才判 pass 并发 token。🔵 不阻断，但需登记去向。
3. **不因轮次多而提前放行**：任何一轮出现未解 🔴 即继续修正，不以「已经三轮了」为理由关闭。

**已知代价（如实记录）**：全文评审每轮成本高于增量评审；用户的裁定是严谨优先，接受该成本。

## 裁定改判：`browser_evaluate` 的 `readOnly` 参数（2026-10-23 00:42）

**原裁定（00:12）撤回**：「不新增 `readOnly` 参数」——该裁定要求的设计修正**从未落盘**，设计档 `:300` / `:256` 仍保留判据，且设计已过 5 轮评审。

**改判为：新增该参数，按设计实现。** 理由：
1. 已评审的设计是权威规格；拿一条未落盘的裁定覆盖它，会让实现与规格不一致，比多 10 行更糟。
2. 参数有独立价值：只读轮在调用记录里可审计，且是写值扫描之外的第二次显式声明。
3. 与实施任务书一致（任务书第 4 点即「设计要求新增」）。

**教训（写下来防止再犯）**：我作出「要求设计修改」的裁定时，**必须同时派修正轮或把它登记为待办**，否则该裁定实际上不存在，后续实现会撞上旧规格。本条即该失误的实例。

**对实施的影响**：无额外工作——实施方本就按设计在做，现按其上报的处理方式继续。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成 · 2026-10-23（第三轮评审 2 条已落地：#14 关→开中间无回合（挂起中和行丢弃分支 + 两种时序用例 #22/#23）、#16 判定代码落点统一到 lib/browser/browser_tools.dart 的 run 包装；设计档实测 551 行；§7 用例 23 条；门禁 PASS）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

## 批次任务与设计（eng-designer）

**设计档落点**：`docs/design/browser-biz-test.md`（新板块首篇；含最近先例三坐标与 survey 证据行，见该档 §2.2 / §2.3）。

**本批条目（覆盖）**：

| 需求 | 设计落点 |
|---|---|
| F1 模式切换 | 设计 §3.1（会话级 `btest` 开关，不发内核） |
| F2 模式卡 | 设计 §3.2（首条消息注入一次，标记 `[btest-mode-card v1]`） |
| F3 预期落盘 | 设计 §3.4（`docs/qa/<业务线>.md` 字段级格式与写规则） |
| F4 来源标注与差异处置 | 设计 §3.5（`source` / `origin` 判定顺序，差异四步） |
| F5 只读轮 | 设计 §3.6（工具面表 + evaluate 例外） |
| F6 一轮报告 | 设计 §3.8（表格字段、证据定义、三类尾注） |
| 自动放行边界 | 设计 §3.7（白名单 / 生产禁写 / 拒绝带原因） |

**本批明确不做**：见设计 §8（不改外仓 `thincoder/`、不改业务代码与数据库、不提交工单、不截图、不边走边停、生产禁写）。

**机制设计一句话**：`btest` = 宿主 overlay；一轮 = `btest_run_start` → 动作受策略闸 → `btest_run_end` 检查表；判断依据全部落盘。判据见设计 §3.2 / §3.3 / §3.4 / §3.7。

**受影响文件与测试**：设计 §4（仓内 11 个文件 + 1 个测试文件 + 业务仓 `docs/qa/`）；超 800 行档的不拆分裁定在同节。

**验收对照**：设计 §6（逐条回指需求 F1–F6 与 §5 验收 1–5）；用例表见设计 §7（12 条，正常 / 边界 / 错误）。

**关键决策**：设计 §5（KD-1…KD-9，含被否方案与理由）。

**上抛项**：

- [上抛·待裁] 每次 run 起始的一行提醒是否算"重复注入"（设计 §10 第 1 条）。
- [上抛·待裁] 自动放行的应答点：设计落在 `lib/kernel/thincoder/thincoder_kernel.dart:1070` 的权限请求处，若拿不到工具名与参数则改到宿主 MCP 调用路径（设计 §10 第 2 条）。
- [上抛·知会] 设计假设：`btest` 存会话设置 map 的 `btest` 键、不发内核——`lib/kernel/thincoder/thincoder_kernel.dart:463-467` 的 `_applyStartMode` 只认 `plan` / `normal`，多余键不会被误发。

**需求档核对**：`docs/requirements/browser-biz-test.md` 五要素齐（模块目标 / F1–F6 / §4 边界 / §5 验收 / §6 依赖），无阻止设计的缺口，本批未改需求档。

**订正（§2 计数）**：设计档实测 **307 行**（前一条状态行注释写的 304 是编辑前行数）。受影响文件表 = **13 行清单项**：`lib/` 11 行（其中 `lib/l10n/app_localizations*.dart` 一行覆盖 3 个本地化文件）、测试 1 行、业务仓 `docs/qa/` 1 行。

## 修正轮（评审 §3 的 13 条落地 · 2026-10-22）

**改动**：`docs/design/browser-biz-test.md` 按 §3 评审 13 条逐条修正，只改被点名段落，未新增功能点、未改需求档、未动代码。

**两条 🔴 的现行判据**：
- #1 规则 A：`btest_run_start` 收到 `env: prod` + `mode: write` ⇒ 拒绝起 run（设计 §3.7）。
- #1 规则 B：写动作自动放行必须 `env != prod` ∧ `prodHosts` 非空 ∧ host ∉ `prodHosts`；`env` 权威、`prodHosts` 纵深防御，取严（设计 §3.7）；§6 有两条走查行。
- #2 退出中和：退出注入 `[btest-mode-card-off v1]`，§6 的 F1 判据恢复为「切回 normal 后不残留」；偏离记在 §2.2 第 3 条 + KD-10。

**其余 11 条落点**（§2 只引用，不转抄）：
- #3 顺序钉死：设计 §3.3 + §3.4 写规则 + 用例 #2。
- #4 根路径：设计 §3.3 `repoRoot` + §3.5 第 1 步。
- #5 跑前必读：设计 §3.3 返回四处（case 索引 + 内容 hash = 写回基线）。
- #6 F5 后半段：设计 §3.6 末段 + §6「F5 回看文档 / 代码」行。
- #7 F2 内容清单：设计 §3.2 标签锚点 + §6 F2 ②。
- #8 拆分缝：设计 §4 四行缝表 + SPLIT-1…4 登记。
- #9 l10n：设计 §4 五行（`app_en.arb` 源档 + `app_zh.arb` + 三个生成物标派生）。
- #10 测试面：设计 §7 十五条逐行「测试落点」+ §4 三个测试文件。
- #11 应答点：设计 §3.7「放行 / 拒绝分两处落」+ §10 第 2 条（用例 #1 标条件）。
- #12 数字漂移：设计 §1 F4 = 四步；§2.3 去掉档数计数。
- #13 结构化载荷：设计 §3.3 `btest_run_end` 载荷表 + 检查表三项机械读数。

**未落地 / 需裁定**：
- [上抛·待裁] #8 的台账行：设计位无台账写权，SPLIT-1…4 只在设计 §4 登记，需主编排方落台账行（设计 §10 第 6 条）。

**门禁**：`doc_check gate` = PASS（1 档 0 条命中）；设计档实测 384 行。

## 追加修正轮：F3.1 并入（2026-10-22 23:56 需求）

**改动**：`docs/design/browser-biz-test.md` 并入需求 F3.1（预期必须有出处）+ 需求 F3 / 验收 3 的对应修订。只动点名段落，未改需求档、未动代码、未重开已落地的 13 条。

**本轮覆盖的需求条目**：

| 需求 | 设计落点 | 可跑判据 |
|---|---|---|
| F3 预期落盘（新增「预期出处」） | 设计 §3.4 字段表 + `expectFrom` 字段定义 | 设计 §6 F3.1 行 ① |
| F3.1 预期必须有出处（三级来源 + 代码现状不得作预期） | 设计 §3.4「`expectFrom` 的三级来源」+ 三条硬规则 + 写规则「来源纪律」 | 设计 §6 F3.1 行 ①②③ · §7 #16 |
| 验收 3 强化（带出处；代码来源不得判预期不符） | 设计 §3.8 报告列 + 证据定义 + 「需要用户补规则的清单」；设计 §6 验收 3 行 | 设计 §6 验收 3 行（含 §7 #16） |

**本轮明确不做**：宿主判据零改动（`btest_run_end` 检查表仍三项，理由设计 KD-14）；不改业务仓设计档 / 冒烟清单（设计 §8 边界）；需求档未改。

**受影响文件**：仅 `docs/design/browser-biz-test.md`（设计档，实测 424 行；§7 用例 16 条）。代码面零改动：`expectFrom` 是预期文件字段 + 报告列，由 AI 写，不进宿主机械判据。

**需要用户补规则的清单（设计侧）**：本轮为空。强来源覆盖率未逐档核实（设计 §10 第 7 条），首个真实 run 的「需要用户补规则的清单」即覆盖率读数。

**门禁**：`doc_check gate` = PASS（1 档 0 条命中）。

## 追加修正轮（第 15 项）：F2.1 操作方式 = 模拟真人（2026-10-23）

**改动**：`docs/design/browser-biz-test.md` 并入需求 F2.1（六条细则）与验收 6，并按主 agent 2026-10-23 00:02 的追加要求把「先记缺陷、再用 URL 绕道」做成可机检。只动点名段落：新增 §3.6.1–§3.6.6，扩写 §3.3 / §3.7 / §3.8，§1 / §2.1 / §3.2 / §4 / §5 / §6 / §7 / §9 / §10 同步。未改需求档、未动代码、未重开已落地的 13 条与 F3.1。

**本轮覆盖的需求条目**（细则 → 设计落点）：

| 需求 | 设计落点 |
|---|---|
| F2.1 ① 入口只一次 | §3.6.2 · §3.3 检查表 4-① · §6「验收 6」行 |
| F2.1 ② 文字首选 / ref 兜底 / 禁 id·class·xpath 首选 | §3.6.1 行② · §3.3 检查表 4-③ · §3.8 报告头读数 |
| F2.1 ③ 按文字找不到 = 缺陷 | §3.6.1 行③ · §3.2 的 `[D7]` · §3.8 尾注「阻塞」 |
| F2.1 ④ 逐字键入、禁 JS 赋值、禁绕表单调接口 | §3.6.3（判据 1 / 3）· §3.3 检查表 4-② |
| F2.1 ⑤ 读只用于判定 | §3.6.3（判据 3 的只读形态）· §3.6.1 行⑤ |
| F2.1 ⑥ 唯一例外 + 先记后绕 | §3.6.2（`detour`）· §3.3 检查表 4-④ · §3.8 绕道栏 |
| 验收 6（机检） | §6「验收 6」行（五项读数） |

**主 agent 00:02 追加四条 → 落点**：`detour` 参数（§3.6 参数表 + §3.6.2）· 宿主记 `detours[]` 并落到报告（§3.3 载荷 + §3.8）· 无 `detour` 的拒绝文案（§3.6.2 第 2 次起）· 「同一判据、表述合一」（§3.6.2 第三条 bullet）。

**机制要点（一句话）**：入口动作按「带 url 的跳转」判（`browser_navigate` / `browser_act` 的 navigate 步 / `browser_open` 三者同判），第一次必须 = `startUrl`，之后每次必须带 `detour`；`detours[]` 条数 = 报告「绕道」行数，不等即 warning。

**新增/改动的工具协议**：`browser_navigate` 增可选 `detour`、`browser_evaluate` 增可选 `readOnly`（既有只读轮规则假设的参数此前不存在，见 §10 第 8 条）。

**受影响文件**：仅 `docs/design/browser-biz-test.md`；代码面增量见 §4（`btest_mode` / `btest_policy` / `btest_card` / `browser_tools` / 两个测试档的 ≤ 增量均已按本轮判据上修）。

**验收对照**：§6 新增「F2.1」「验收 6」两行；F2 行 ② 的标签清单同步到 `[D1]`–`[D7]`。用例见 §7 #17–#21（二次入口拒 / 带 `detour` 放行与对账 / evaluate 写值拒 / `replay` 拒 / 纯文字定位走查）。

**关键决策**：§5 KD-15（`detour` 长在工具参数上，不开独立工具）、KD-16（evaluate 全轮次禁写，规则只写 §3.6.3 一处）、KD-17（入口按动作判、不按工具判）。

**上抛项**：

- [上抛·待裁] `browser_evaluate` 的 `readOnly` 参数（设计 §10 第 8 条）：既有表述假设它存在，schema 里没有；本轮按「补参数」处理，若选择不补，只读轮与写轮对 evaluate 同宽。
- [上抛·待裁] 「按文字找不到可点目标」宿主判不了（设计 §10 第 9 条）：替代 = 兜底计数 + 报告写理由 + `browser_history` 对账；代价是走查不是硬闸。

**门禁**：`doc_check(mode:"gate", docs:["docs/design/browser-biz-test.md"])` = PASS（1 档 0 条命中）；设计档实测 523 行；§7 用例 21 条。

**订正（§2 计数）**：设计档实测 **529 行**——同一条状态行里的 523 是补入「定位规则三行」之前的读数；该块在 §3.6:235-239，即验收 ④ 要的首选 / 兜底 / 禁止三行原文。补入后门禁重跑 = PASS（1 档 0 条命中）。

## 修正轮（第二轮评审 §3 的 3 条落地 · 2026-10-23）

**改动**：`docs/design/browser-biz-test.md` 按 §3 `### 轮次 2（评审子代理）` 的 #14 / #15 / #16 逐条修正；只动点名段落，未改需求档、未动代码、未重开已落地的 13 + F3.1 六项 + F2.1 六项。

**逐条落点**（判据只引用，不转抄）：

| 评审条 | 设计落点 | 判据回顾 |
|---|---|---|
| #14 🔴 重进 btest 不重投卡 | 设计 §3.2（计数差 `D` 判据：投卡 / 跳过 / 模式内 / 已退出四读合一）· §3.1 退出行 · §9 退出行 · §2.2 第 3 条 · KD-18 | 设计 §6 F1 / F2 行（计数差读数，不依赖单周期）· §7 #22 |
| #15 🟡 第 4 个实现档缺失 | 设计 §4 新增 `lib/browser/btest/btest_expect_file.dart`（0 / ≤ +200）；与 §4 末「四个文件」及 `test/browser/btest_expect_file_test.dart` 对齐 | 设计 §4 表 |
| #16 🟡 规则 B 载体依赖未核实审批点 | 设计 §3.7（放行判据 = 全部满足才放行，任一不满足 ⇒ 拒绝；规则 B = MCP 层硬拒绝；未知 host 读 / 写同判拒绝；判定面 / 展示面分开）· 边界表两行 · KD-19 · §9 设置页 · §10 第 2 条 | 设计 §6 规则 B 行 · §7 #1 / #14 |

**#14 形态选择**：采用评审建议的第一种（计数差判据），不采用「可逆复投行」——不新增标记、transcript 仍是历史事实；「重进时清空计数」在无持久计数可清的前提下，其可判形态就是这里的计数差。理由记 KD-18。

**#16 与既有「只读或非生产才放行」的合并结果（取严）**：btest 的浏览器动作只有两种结果——放行 / 拒绝；「不自动放行」= 拒绝，不再有「转内核审批询问」的中间态（该中间态的载体就是未核实的审批点，拿不到 host 与参数，判不了按 host 询问）。用户要放行某 host ⇒ 设置页 `allowHosts`。理由记 KD-19。

**明确不做**：未重开已落地的 13 + 2 + 6 条；未新增需求点；未改需求档与代码（含 `thincoder/**`）。

**门禁**：`doc_check(mode:"gate", docs:["docs/design/browser-biz-test.md"])` = PASS（1 档 0 条命中）；设计档实测 533 行；§7 用例 22 条。

## 修正轮（第三轮评审 §3 的 2 条落地 · 2026-10-23）

**改动**：`docs/design/browser-biz-test.md` 按 §3 `### 轮次 3（评审子代理）` 的 #1（#14 未闭合）与 #2（#16 落点歧义）逐条修正；🔵 行数抽查项由主 agent 关闭。只动点名段落，未改需求档、未动代码、未重开已落地的 13 + 2 + 6 + 3 条。

**逐条落点**（判据只引用，不转抄）：

| 评审条 | 设计落点 | 判据 |
|---|---|---|
| #1 🔴 关→开中间无回合 | §3.2 新增五段：「中和行：不存挂起位」「重进时挂起中和行的归属（写死：丢弃）」「两种投递按宿主状态互斥」「重进的两种时序」「判定的时刻」；§3.1 退出行、§2.2 第 3 条、§9 退出行、KD-18、§6 F1 行同步 | §7 #22（中间有回合 ⇒ 重投）/ #23（中间无回合 ⇒ 不重投）；读数：回合装配完成时宿主 `on` ⇔ `D = 1` |
| #2 🟡 判定代码落点 | §3.7「两组判据的物理落点（唯一坐标）」= `lib/browser/browser_tools.dart:115-130` 的 `run` 包装（闸口在 `:117` 早退之前）；`lib/host_tools/host_tools.dart:194-243` 降为分发面、本批不改；KD-19 / §10 第 2 条同步 | §4 的 `browser_tools.dart` 行（690 / ≤ +65）即该档；§6 规则 B 行、§7 #14 |

**#1 形态选择**：中和行**丢弃**，不随重进后的回合投出。理由：中和行的含义是“模式已关”，宿主已重开还投它 ⇒ 模型侧被告知已退出、宿主侧仍按 btest 判据行事，正是 #14 要消灭的形态；丢弃代价为零（卡未失效，模型从未被告知退出），且两种投递条件按宿主状态互斥，没有“先中和再投卡”的顺序判据。被否方案记 KD-18 第 ③ 条。

**#2 落点依据（实读）**：`lib/browser/browser_tools.dart:115-130` 是 `register()` 给每个浏览器工具套的唯一 `run` 闭包，
拿得到 `tool.name` 与结构化 `input`；`:117` 的 `tabId is! int` 会先早退
（`browser_tabs` / `browser_open` 不带 tabId，见 `:210-231` / `:232-244`），闸口必须在它之前。
`lib/host_tools/host_tools.dart:194-243` 的 `tools/call` 只做 `params['name']` / `params['arguments']` → `tool.run` 的转发。

**用例表**：§7 22 → 23 条（#22 改写为“中间有回合”，新增 #23“中间无回合”；#11 的“退出时注入”改为“退出后的下一回合投出”）。

**行数**：设计档实测 **551 行**（改前 533）。受影响文件表的 7 个行数与主 agent 读数一致，未改：composer 2332 / thincoder_kernel 1409 / chat_session 1363 / chat_models 812 / browser_tools 690 / browser_page 321 / app_settings 322；本表未新增档（`host_tools.dart` 不改）。

**门禁**：`doc_check(mode:"gate", docs:["docs/design/browser-biz-test.md"])` = PASS（1 档 0 条命中）。

**明确不做**：未重开已落地的 13 + 2 + 6 + 3 条；未新增需求点；未改需求档与代码（含 `thincoder/**`）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（docs/design/browser-biz-test.md · docs/requirements/browser-biz-test.md）

评审局限：无 AGENTS.md / 无项目规范档 / 无文档地图 ⇒ 方法学合规与文档归属两条判据降级；评审范围限于两份文档，设计档内引用的 `lib/**` 代码坐标未实读，按 `unverified` 处理。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Requirements / Feasibility | 🔴 | 生产禁写判据 fail-open：`docs/design/browser-biz-test.md:180` 的「目标 host ∉ `btest.prodHosts`」是放行的唯一闸门，而 `docs/design/browser-biz-test.md:296` 只对允许域名列表写「空列表 = 不自动放行」；prodHosts 为空时写动作在任一 allowHosts 上都会自动放行。run 的 `env` 字段（`docs/design/browser-biz-test.md:89`）不参与任何判据，`mode: write` + `env: prod` 也能起 run。这与 `docs/design/browser-biz-test.md:286`「不在生产环境做写操作（用户未授权）」及 `docs/requirements/browser-biz-test.md:31`「不在生产环境做写操作（用户未授权生产；默认为测试环境）」直接冲突。 | 补两条判据：① `btest_run_start` 拒绝 `env: prod` + `mode: write` 组合；② 写动作放行要求 `env != prod` 且 prodHosts 非空且 host ∉ prodHosts（prodHosts 为空 ⇒ 写动作不自动放行）。明确 `env` 与 prodHosts 谁为权威、另一项为纵深防御。 |
| 2 | Requirements | 🔴 | 需求验收 1「且不残留提示词」（`docs/requirements/browser-biz-test.md:36`）被设计档否掉但未入决策：`docs/design/browser-biz-test.md:71` 写「已投递的模式卡留在 transcript（历史事实，不撤回）」，模式卡随历史每回合都进模型上下文；§6 的 F1 判据改成了 weaker 的「transcript 不再新增模式卡」（`docs/design/browser-biz-test.md:251`），把「不残留」换成了「不新增」，验收口径被静默改写。 | 二选一：① 退出时用同一通道注入一行中和语（如 `[btest-mode-card v1] off`），§6 的 F1 判据保持"退出后模型不再按 btest 纪律行事"；② 在 §2.2 偏离清单 + KD 表明确登记"卡不撤回"的偏离与理由，并在 §6 写明替代判据为何等价于"不残留"。 |
| 3 | Consistency | 🟡 | 预期文件写回顺序与 `btest_run_end` 的机械读数互相矛盾：`docs/design/browser-biz-test.md:138` 写「run 结束后一次写回」，而 `docs/design/browser-biz-test.md:96` 的检查表要读「预期文件自 run 开始后是否被写过（mtime/hash 对比）」——按 §3.4 的顺序，run_end 时文件必然尚未写，检查表每次都会给出 `expectFile: not written`，该机械读数退化为常量告警。用例表 #2「返回检查表全绿」（`docs/design/browser-biz-test.md:267`）也随之无法成立。 | 在一次表述里钉死顺序：AI 在调 `btest_run_end` 之前完成写回，run_end 只做校验与收尾；§3.3 / §3.4 / 用例 #2 三处措辞对齐。 |
| 4 | Clarity / Feasibility | 🟡 | 预期文件的路径契约不自洽：`repo` 只是仓名（`docs/design/browser-biz-test.md:88`），`expectFile` 要求「绝对路径」（`docs/design/browser-biz-test.md:91`），§3.5 又要执行「git -C <业务仓> log --oneline -30」（`docs/design/browser-biz-test.md:147`），但设计里没有任何一处给出业务仓根的解析来源；模型和宿主各自怎么拿到这个绝对路径未定义。 | 给 run_start 增 `repoRoot`（绝对路径，必填并校验存在），`expectFile` 改为相对 `repoRoot` 的 `docs/qa/<业务线>.md`；`git -C` 与 mtime/hash 读都用同一 repoRoot。 |
| 5 | Requirements coverage | 🟡 | F3 的「跑之前必读」（`docs/requirements/browser-biz-test.md:22`）没有机械判据：`docs/design/browser-biz-test.md:96` 的两项读数只验「写了」和「有尾注」，没验「读了」；§3.2 的兜底只是一行提醒（`docs/design/browser-biz-test.md:77`）。用户点名的根因恰是「有时候忘了预期结果」，而设计对"忘写"有闸、对"忘读"只有提示词。 | 让 `btest_run_start` 自己读该文件并把「case-ID 索引 + 内容 hash」放进返回值（hash 顺带作为写回基线），使预期随回合进入上下文；可再要求 agent 在 run_start 后回显本轮覆盖的 case ID，报告与文件两侧即可对账。 |
| 6 | Requirements coverage | 🟡 | F5 后半段没有落点：`docs/requirements/browser-biz-test.md:24` 要求「不确定时回看业务仓的文档与代码（`api` / `database` / `docs` / 前端仓）」，而 §3.6 / §3.7 只描述浏览器工具面，§6 验收对照也没有对应行；按 §3.7 的自动放行边界，这类读取只能走内核原有审批。 | 在 §3.6 增一条：业务仓文件读取不进 btest 自动放行面，按内核原路径审批；并在 §6 增加一行"不确定时回看文档/代码"的走查判据，明确它不改 F5 只读轮的边界。 |
| 7 | Acceptance criteria | 🟡 | F2 的唯一判据是标记计数（`docs/design/browser-biz-test.md:252` 的「在会话记录里 = 1」），它只证明"注入了一次"，不证明卡内容覆盖了需求点名的失效类别（接口报错 / console 报错 / 输入框信息被刷 / 复选框无法点 / 单据无法提交）与六条纪律、七条判定口径。 | 补一条可机检的内容核对：对 `lib/browser/btest/btest_card.dart` grep 每个纪律 / 判定口径 / 失效类别的关键词，缺项即失败；把它作为 F2 的第二条判据写进 §6。 |
| 8 | Affected-file size annotations | 🟡 | 四个超 800 行档只给「超 800 行档的不拆分裁定」（`docs/design/browser-biz-test.md:231`），没有拆分方案：`composer.dart` 2332、`thincoder_kernel.dart` 1409、`chat_session.dart` 1363、`chat_models.dart` 812（`docs/design/browser-biz-test.md:221-224`）。按本评审的代码结构分档口径，>800 行是硬上限、没有豁免通道。（增量确实都很小，问题在"只给裁定、不给拆分落点"。） | 保留本批不拆的结论，但把抽取缝写清楚（全部新增实现落在 `lib/browser/btest/*`，大档只加调用点与钩子），并给出登记项（拆分批次编号或 TODO 入口），使这笔债被跟踪而不是被声明。 |
| 9 | Affected-file size annotations | 🟡 | l10n 行是通配（`docs/design/browser-biz-test.md:227` 的 `lib/l10n/app_localizations*.dart`），现行数写「—」，不满足"每个源文件给现行行数 + 预期增量"；若这些是 ARB 生成的产物，真正的编辑目标 `.arb` 源文件没进清单。`unverified`（本评审未读该仓文件）。 | 列出具体 l10n 文件与现行行数；若为代码生成，把 `.arb` 源文件列为改动面、生成的 dart 标为派生。 |
| 10 | Test plan | 🟡 | 测试面只有 `test/browser/btest_policy_test.dart`（`docs/design/browser-biz-test.md:228`），而 §7 用例表有 12 条；其中"卡只注入一次 / 会话恢复再注入"（#11）、"未 start run 拒绝"（#7）、"非 btest 会话拒绝"（#12）、"人改文件后追加修订建议"（#8）都没有测试落点，正是本设计头号卖点的机械判据缺覆盖。 | 给这些行配测试文件（或在 §7 逐行标注"走查"并说明为何无法单测），使 §7 与 §4 的测试清单一一对得上。 |
| 11 | Feasibility | 🟡 | 自动放行的应答点仍是未核实项（`docs/design/browser-biz-test.md:303` 上抛项 2）。这是整个 §3.7 的承重点：若该处拿不到工具名与参数，回退方案会保留一次内核审批卡，用例 #1「自动放行，无审批卡」就无法成立。 | 实施前实读该内核路径并把结论回填；在结论落定前把用例 #1 标为条件用例，或把"回退路径下仍可能弹一次审批"写进用例 #1 的期望。 |
| 12 | Doc hygiene | 🔵 | 两处数字漂移：`docs/design/browser-biz-test.md:18` 写「差异按三步处置」，§3.5 正文写「四步」（`docs/design/browser-biz-test.md:151`）；`docs/design/browser-biz-test.md:57` 写「`docs/design/` 六档」，括号里列了七个档名。 | 统一为正文的步数（四步，或在 §1 写"对比 + 三步"）；档数改成七档或去掉计数。 |
| 13 | Clarity | 🔵 | 「检查表含两项机械读数」中，`docs/design/browser-biz-test.md:96` 的「报告是否含三类尾注」取自模型自己上报的"报告摘要"，不是机械读数；只有 mtime/hash 那项是宿主可独立核对的。 | 让 `btest_run_end` 接收结构化载荷（三尾注各自条数 + 问题行数 + 每条的证据字段），宿主按字段存在性判定，而不是信一段自然语言摘要。 |

计数：🔴 2 · 🟡 9 · 🔵 2（共 13 条）

VERDICT: changes-required

### 轮次 2（评审子代理）

## 第二轮评审（修正落地验证）

Scope: `docs/design/browser-biz-test.md` + `docs/requirements/browser-biz-test.md`，两份全读。设计内引用的 `lib/**` 代码坐标本轮未读 → `unverified`（评审面限两份档）。

| # | Orig# | File | Severity | Status | Notes |
|---|-------|------|----------|--------|-------|
| 1 | 1 | docs/design/browser-biz-test.md | 🔴 | Fixed | `:323` "写动作同时满足三条：`env != prod` ∧ `btest.prodHosts` **非空** ∧ 目标 host ∉ `btest.prodHosts`" + 规则 A/B（`:327-328`）+ 权威划分（`:330`）+ §6 两行判据（`:462-463`）+ 用例 13/14/15（`:483-485.`）。`env: prod` + `mode: write` 起 run 即拒，`prodHosts` 空 ⇒ 写不自动放行。fail-open 已堵。 |
| 2 | 2 | docs/design/browser-biz-test.md | 🔴 | Fixed | `:76` "紧接着在下一回合注入一行中和语 `[btest-mode-card-off v1]`，使卡失效"；§6 F1 判据改回 "切回 normal → **不残留**"（`:450`，含行为判据 + `grep -c "btest-mode-card-off v1"`）；偏离记账进 §2.2 第 3 条（`:57`）与 KD-10（`:437`）。"卡不撤回" 仍是字面偏离，但已带理由并落地中和语，判据未再被弱化。 |
| 3 | 3 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:136` "**顺序钉死**：AI 必须**先完成预期文件写回，再调 `btest_run_end`**"；§3.4 `:210`、§2.1 `:32`、KD-11 `:438` 同口径；用例 #2（`:472`）已是 "已写完回 → 四项全绿"。 |
| 4 | 4 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:94` `repoRoot` = "**业务仓根绝对路径**（如 `D:\repos\v2-booking`）… 本 run 内一切路径与 git 命令都从它解析"；`expectFile` 改 "**相对 `repoRoot`** 的路径"（`:98`）；`repo` 入参已删（`:101`）；§3.5 `:220` 用 `<repoRoot>`。 |
| 5 | 5 | docs/design/browser-biz-test.md | 🟡 | Fixed | run_start 返回项 2（`:108`）"**case 索引**：本次预期文件里全部 `## CASE-` 的 ID 与标题"，项 3 内容 hash 兼写回基线（`:109`）。"跑前必读" 有了机械落点。 |
| 6 | 6 | docs/design/browser-biz-test.md | 🟡 | Fixed | 新增 §3.6.6（`:310-312`）："`api` / `database` / `docs` / 前端仓的读取**不在** btest 自动放行面内"，走内核原审批、路径用 `repoRoot`；§6 补 "F5 回看文档 / 代码" 走查行（`:456`）。 |
| 7 | 7 | docs/design/browser-biz-test.md | 🟡 | Fixed | §6 F2 判据②（`:451`）内容清单：`[D1]`–`[D7]` / `[J1]`–`[J7]` / `[P01]`–`[P19]` / `[H1]`–`[H3]` 标签齐全；§4 增 `btest_card_test.dart`（`:407`）。 |
| 8 | 8 | docs/design/browser-biz-test.md | 🟡 | Fixed | §4 `:411-422` 四个 >800 档给出抽取缝 + 登记 SPLIT-1…4 + "新增实现只落 `lib/browser/btest/*`"，`:422` "由主编排方落台账行（挂本批 #149 的后续批）"，§10 第 6 条知会（`:525`）。 |
| 9 | 9 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:401-405` 逐档列行数，`app_en.arb` 标注 "**源档**（`l10n.yaml` 的 template，`flutter gen-l10n` 生成）"，三个生成物标 "派生 / 不手改"。 |
| 10 | 10 | docs/design/browser-biz-test.md | 🟡 | Fixed | 测试面增至三档（`:406-408`，policy / card / expect_file）；§7 的 21 条里仅 #16、#21 标 "走查"（`:486`、`:491`），其余各有测试落点，#1 标条件用例（`:471`）。 |
| 11 | 11 | docs/design/browser-biz-test.md | 🟡 | Fixed | §3.7 `:352-359` 换成实读结论：审批点拿得到工具名、拿不到结构化参数 ⇒ 放行只判工具名，拒绝退到 MCP 层（name + arguments），KD-13（`:440`）；残余 "内核是否对 MCP 工具一律发 `session/request_permission`"（`:359`）标未核实、用例 #1 条件化，不在本机可读范围内 ⇒ 可接受。 |
| 12 | 12 | docs/design/browser-biz-test.md | 🔵 | Fixed | `:20` 已改 "差异按四步处置"，与 §3.5 `:224` "四步" 一致；`:61` 删掉了档数，改为 "`docs/design/`（含 chat-streaming …" 枚举。 |
| 13 | 13 | docs/design/browser-biz-test.md | 🔵 | Fixed | `:112` "`btest_run_end` 接收**结构化载荷**（不是一段自然语言摘要，字段存在性由宿主判）"，检查表第 2 项改为 "三个键都在（可为空数组，但键必须在）"（`:126`）。 |
| 14 | (new) | docs/design/browser-biz-test.md | 🔴 | New: 重进 btest 不重投卡，且状态模型自判"已退出" | `:81` "投递前查 transcript 是否已有该标记，有则跳过。"（只看卡标记），`:82` "卡在、有中和行 ⇒ 已退出。"（状态由标记对推导）⇒ 同会话 off→on 之后：宿主侧 btest 已开（审批放行、只读面、run 闸全生效），但上下文最后一句模式指令是中和行、卡不再投递。`:513` 同时说 "模式卡不再注入；run 未结束则下次进入先要求 `btest_run_end` 或作废" —— 已预期"下次进入"却又规定不再投卡，自相矛盾。F1 的"可切"在第二次切换即失效，§6 的 `grep -c … = 1` 计数也只在单个 on/off 周期成立。 |
| 15 | (new) | docs/design/browser-biz-test.md | 🟡 | New: 第 4 个实现档未进受影响文件清单 | `:420` "**新增实现只落 `lib/browser/btest/*`**（mode / policy / card / expect-file 四个文件）"，但 §4 表只列了 `btest_mode.dart` / `btest_policy.dart` / `btest_card.dart` 三档（`:391-393`），而 `:408` 存在 `test/browser/btest_expect_file_test.dart`（"run_start 索引与 hash 基线"）⇒ expect-file 的实现档缺行数与增量。 |
| 16 | (new) | docs/design/browser-biz-test.md | 🟡 | New: 规则 B 的执行载体依赖未核实分支，且该分支后果写反 | `:340` "`btest.prodHosts` 为空 + 写动作 | 不自动放行（规则 B），走内核原有审批即问用户" —— "不自动放行" 的载体就是审批点，而 `:359` 明写该点是否被调用未核实；§10 第 2 条给的失败后果是 ":521" "不成立则写轮多一张卡"（若不发请求则是零张卡，且"不自动放行"无处落地 = 写动作照走）。§10.2 只分析了用例 #1，未分析规则 B。 |

Counts: 2 🔴（其中 1 条新）+ 10 🟡（其中 2 条新）+ 1 🔵 = 16 行；prior 13 条全部落地。

VERDICT: changes-required

### 轮次 3（评审子代理）

### 设计评审（第三轮：只验证 #14 / #15 / #16）

验证对象：`docs/design/browser-biz-test.md`（待评审）。审查范围仅该档；无 AGENTS.md / 项目标准档 / 文档地图 ⇒ 方法论合规按评审判据自判，文档归属一项降级（本档自述为板块首篇，无可归并的既有章节）。受影响文件表行数未与源文件核对（范围声明禁读其它文件）⇒ 行数/增量读作 unverified。

三项验证结论：

- **#14 重进重投判据：未闭合**（下表 #1，1 条 🔴）。
- **#15 第 4 个实现档：闭合**。§4 四档 `btest_mode.dart` / `btest_policy.dart` / `btest_card.dart` / `btest_expect_file.dart`（`docs/design/browser-biz-test.md:394-397`）与 §3.2 的卡正文落点（`:85`）、§3.3 的 run 状态落点（`:129`）、§4 的小结句（`:424`）以及三个测试档（`:410-412`）一一对齐，无孤引用。
- **#16 规则 B 硬拒绝：闭合**。§3.7 规则 A/B（`:328-329`）、KD-12（`:443`）、KD-19（`:450`）、§6 两行验收（`:468-469`）、用例 #13/#14/#15（`:489-491`）、§9 设置页（`:518`）取值一致，全文无"转人工审批"残留（`:339`、`:351` 显式否定）。仅余落点坐标一处歧义（下表 #2，🟡）。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|---|---|---|---|
| 1 | Requirements · #14 重进重投判据 | 🔴 | 退出到重进之间**没有产生任何回合**时，中和行仅是"待下一回合投递"（`docs/design/browser-biz-test.md:76`：`D = 1` 时在下一回合注入一行中和语；`:83`：同一通道，挂 turn contexts），尚未落进 transcript；此时按 `:81` 的「`D ≥ 1` ⇒ 跳过」不重投，与用例 #22 的期望「重进时按 §3.2 判据重投一张卡，计数差回到 `D = 1`」（`:498`）直接冲突。`:82` 的前提「同会话 off→on 时 `D` 已回到 0 ⇒ 重投」只在"退出与重进之间已有一回合投递了中和行"时成立。若宿主改为把挂起的中和行在重进后的那条回合投出，模型侧读数掉回 0（被告知已退出）而宿主仍 `on`，正是 #14 要消灭的形态。 | 在 §3.2 补一条针对"退出即 off / 重进即 on、中间无回合"的分支：挂起中和行的归属（丢弃还是随回合投出）与挂起态下投卡判据的取值；并让用例 #22 的输入序列（中间是否有回合）与该分支对齐，使判据与用例读同一个状态机。 |
| 2 | Clarity · #16 判据落点 | 🟡 | 规则 B 的判定代码坐标在同一档里给了两处：`:333` 说「两组判据同一处落（MCP 工具层，`lib/host_tools/host_tools.dart:194-227` 的 `tools/call` 分支拿得到 name + arguments）」，而 §4 只把「工具 `run` 包装里加 btest 闸」记在 `lib/browser/browser_tools.dart`（`:398`），`lib/host_tools/host_tools.dart` 不在受影响文件表里。若判据真落 host_tools.dart，该档缺少行数与增量标注（判据 8 的硬要求）；若落 browser_tools.dart，`:333` 的文件坐标应指向真正被改的档。 | 在 §3.7 与 §4 之间把判定代码的物理落点统一到一处，并让受影响文件表覆盖该档（现行行数 + 增量），使规则 B 的载体在实现前就有唯一坐标。 |
| 3 | Acceptance · 行数实测 | 🔵 | 受影响文件表声明「行数 = 2026-10-22 实测」（`:390`），本轮审查范围禁读源文件，未做抽查 ⇒ 各行数与 >800 行档现状均未核对（unverified），不作为通过依据也不作为缺陷。 | 实施前或下一轮由能读源文件的一侧抽查 1–2 个档（建议含 `composer.dart` 与 `thincoder_kernel.dart`）确认行数与增量预算。 |

计数：🔴 1 · 🟡 1 · 🔵 1

VERDICT: changes-required

### 轮次 4（评审子代理）

## 第三轮：全 16 条逐条验证（13 条已关 + 本轮派出的 #14 / #15 / #16）

| # | Orig# | File | Severity | Status | Notes |
|---|-------|------|----------|--------|-------|
| 1 | 1 | docs/design/browser-biz-test.md | 🔴 | Fixed | `:333` "4. 动作是只读，**或** 写动作同时满足三条：`env != prod` ∧ `btest.prodHosts` **非空** ∧ 目标 host ∉ `btest.prodHosts`。"；规则 A `:337`（起 run 即拒）、规则 B `:338`（`prodHosts` 空 ⇒ 工具 `run` 层硬拒绝）；§6 `:483-484`、用例 13/14/15（`:504-506`）。 |
| 2 | 2 | docs/design/browser-biz-test.md | 🔴 | Fixed | `:76` "由**下一个回合**投出一行中和语 `[btest-mode-card-off v1]` 使卡失效"；`:456` KD-10 记被否方案；§6 F1 `:471` 判据为行为 + 计数差。卡不撤回仍是字面偏离，已带理由并落地中和语。 |
| 3 | 3 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:146` "**顺序钉死**：AI 必须**先完成预期文件写回，再调 `btest_run_end`**"；`:220` 同步。 |
| 4 | 4 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:104` "**业务仓根绝对路径**（如 `D:\repos\v2-booking`）"；`:108` "**相对 `repoRoot`** 的路径"；`:111` 删除 `repo` 入参。 |
| 5 | 5 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:118` "**case 索引**：本次预期文件里全部 `## CASE-` 的 ID 与标题" + 项 3 hash 基线。 |
| 6 | 6 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:322` "`api` / `database` / `docs` / 前端仓的读取**不在** btest 自动放行面内"；§6 `:477` 走查行。 |
| 7 | 7 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:472` "② 内容清单：`btest_card_test` 断言 `[D1]`–`[D7]` 七个…`[P01]`–`[P19]` 十九个…"；`:426` 测试档在册。 |
| 8 | 8 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:430` "**超 800 行档：本批不拆，但缝与登记都写明**"，四档抽取缝 + SPLIT-1…4；`:441` 登记与 `:547` 上抛知会。 |
| 9 | 9 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:420` `app_en.arb` 标注 "**源档**（`l10n.yaml` 的 template，`flutter gen-l10n` 生成）"；生成物标"派生"。 |
| 10 | 10 | docs/design/browser-biz-test.md | 🟡 | Fixed | 测试面三档 `:425-427`；§7 21 条仅 #16 `:507`、#21 `:512` 走查并各带理由。 |
| 11 | 11 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:377` "**残余未核实**：内核是否对 MCP 工具一律发 `session/request_permission`"，两分支读数相同、用例 #1 `:492` 无条件成立；`:541-543` §10 第 2 条同步。 |
| 12 | 12 | docs/design/browser-biz-test.md | 🔵 | Fixed | `:20` "差异按四步处置" 与 `:234` 四步一致；`:61` 已删档数改枚举。 |
| 13 | 13 | docs/design/browser-biz-test.md | 🔵 | Fixed | `:122` "`btest_run_end` 接收**结构化载荷**（不是一段自然语言摘要，字段存在性由宿主判）"；检查表第 2 项 `:136` "三个键都在"。 |
| 14 | 14 | docs/design/browser-biz-test.md | 🔴 | Fixed | 重进判据改计数差：`:81` "宿主侧 `btest == on` ∧ `D = 0` ⇒ 投一张卡（`D` 变为 1）；`D ≥ 1` ⇒ 跳过。"；`:92` "任意次开→关→再开之后仍成立"；`:536` "再次切进 btest 时按 §3.2 判据"（原"模式卡不再注入"已删）；两种重进时序 `:87-90`，用例 22/23 `:513-514`；KD-18 `:464` 记被否方案（含仅首次注入 = 评审 #14）。上一轮的"卡在 + 中和行 ⇒ 已退出"终态判定已被 `D` 读数取代，宿主 `on` ⇔ `D = 1` 在装配时对齐，不会出现"宿主已开、模型被告知已退出"。 |
| 15 | 15 | docs/design/browser-biz-test.md | 🟡 | Fixed | `:412` "`lib/browser/btest/btest_expect_file.dart` | 0（新） | ≤ +200 |" 已进表；与 `:439` "（mode / policy / card / expect-file 四个文件）" 及 `:427` 对应测试档一致。 |
| 16 | 16 | docs/design/browser-biz-test.md | 🟡 | Fixed | 载体已从审批点搬到工具层：`:338` "**`prodHosts` 为空 ⇒ 写动作在工具 `run` 层硬拒绝**"；`:328` "任一不满足 ⇒ 拒绝——浏览器动作在 btest 下没有"转人工审批"这一结果"；边界表 `:355-357` 标"零审批卡"；KD-19 `:465`；原"不成立则写轮多一张卡"的方向错误已删，`:543` 改为两分支皆零卡。 |

**计数**：🔴 0 · 🟡 0 · 🔵 0 —— 上一轮 16 条（13 已关 + 本轮派出 3 条）全部 Fixed，无新增。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（2026-10-23 00:11）

**已定决定**：设计批准进入实施；子代理参与方式 = **先做查文档类辅助**（explore 子代理读业务仓设计档追 `expectFrom`、分析记录），只读观察者与并行多线留后 · 用户原话：「对，让子代理查文档之类的辅助可能更好，我同意；批准」· 时间：2026-10-23 00:11

**批准范围**：设计档 `docs/design/browser-biz-test.md`（529 行，三轮修正后）+ 需求档 `docs/requirements/browser-biz-test.md`（F1–F6 / F3.1 / F2.1 / 验收 1–6）。

**实施前置**：设计评审第二轮（验证修正落地）通过并发 token 后，方可派 eng-coder。

**子代理用途的既有能力依据（实读）**：thincoder 子代理工具 = `parent.tools` 过滤（`thincoder-core/agent-tools/subagent-spawn.mjs:249`/`:252`）；只读角色走 `readonlyToolNames`，而 MCP 工具硬编码 `readonly: false`（`thincoder-core/mcp.mjs:168`）⇒ **浏览器工具给不到 explore 子代理**；但「查文档 / 分析记录」不依赖浏览器工具 ⇒ 本决定零改动即可落地。

## §5 实施记录（eng-coder）

## 实施记录（eng-coder · 2026-10-23）

**范围**：按设计档 `docs/design/browser-biz-test.md`（551 行，批准版）实施 F24；`readOnly` 参数按设计档 + 任务书实现（主代理 2026-10-23 裁定改判，批档 §1 的「不新增」已撤回）。

**新增（设计与代码）**

| 文件 | 行数 | 内容 |
|---|---|---|
| `lib/browser/btest/btest_mode.dart` | 787 | 模式状态（会话级）、run 生命周期与四项读数、设置读写、`btest_run_start` / `btest_run_end` 两个宿主工具 |
| `lib/browser/btest/btest_policy.dart` | 375 | 判据纯函数：入口三路同判 + `detour`、evaluate 写形态、只读面、allowHosts / prodHosts / env、拒绝文案 |
| `lib/browser/btest/btest_card.dart` | 123 | 模式卡正文（`[D1]`–`[D7]` / `[J1]`–`[J7]` / `[P01]`–`[P19]` / `[H1]`–`[H3]`，标记各一次）+ 计数差 `D` 投递判定 |
| `lib/browser/btest/btest_expect_file.dart` | 199 | case 索引、SHA-256 基线、`written`/`not written`/`created`、路径规则、骨架与「修订建议」追加 |

**改动（接线）**：`browser_tools.dart` 的 `run` 包装加 btest 闸（在 `tabId is! int` 早退之前）+ `browser_navigate.detour` + `browser_evaluate.readOnly`；`thincoder_kernel.dart` 审批点对 browser 组答 allow（只认注册表里 `group == 'browser'` 的工具）。
`chat_session.dart` 模式项 / 卡注入 / 状态投影；`chat_models.dart` `TextContext`；`composer.dart` 状态行；`browser_page.dart` 设置段；`app_en.arb` / `app_zh.arb` 12 键 + `flutter gen-l10n` 生成物。

**测试（随批删）**：`test/browser/btest_policy_test.dart`（26）、`btest_card_test.dart`（9）、`btest_expect_file_test.dart`（15），合计 50 条，全绿。

**验证读数**：`dart analyze` = `No issues found!`；`flutter test --no-pub test/browser/btest_policy_test.dart test/browser/btest_card_test.dart test/browser/btest_expect_file_test.dart` = `00:00 +50: All tests passed!`。
**自审（explore 子代理，对照设计逐节）**：9 处偏差。
- 🔴 2：`mode` 可选与 §3.3 必填冲突；btest 状态只读不写，「会话恢复」入口不可达。
- 🟠 1：入口读数把合法绕道数成第二次入口（已修）。
- 🔵 6：拒绝文案未 l10n、行数超 §4 预算、`[D4]` 缺四步第 1 步（已修）、`expectRef` 只判非空、父目录「可写」未探针、`app_settings.dart` 未落地。
已修：入口读数改为「声明入口 / 绕道」两读（`BtestRun.declared`，§3.8 的 `入口=1 … 绕道=1` 形态）、`[D4]` 补回前置对比一步。其余作为披露项保留：见下。

**代码评审（advisor，type=code，第 1 轮）**：结论 changes-required —— 🔴 2 / 🟡 4 / 🔵 4。处置：
- 🔴 `browser_act{file: …}` 是入口与目标 host 判据的第四条路（fail-open 直通生产写）⇒ **已修**：btest 下带 `file` 的 `browser_act` 一律拒绝（步骤判不了就不放行），并加用例。
- 🔴 btest 模式不落盘（`KernelContext.settings` 只读、`workspace.dart` 不在批准改动面）⇒ **未修，上抛主代理**：要么扩改动面到 `workspace.dart` 写回会话设置，要么由设计位明确「btest 仅会话内存」，二者都不是实现方可自裁。
- 🟡 同目录两个未开始会话共享/抢夺同一个 `BtestState` ⇒ **已修**：每个会话独立 state（无 id 时用匿名键），`bind` 只在键仍是自己的时候移除旧键，并加两条用例。
- 🟡 内核 `_isBrowserTool` 以 `contains('browser_')` 兜底会放开非 browser 组工具 ⇒ **已修**：只认注册表里 `group == 'browser'`。
- 🟡 `mode` 可选与设计 §3.3「必填」冲突（§9 的「默认只读开关」只在可缺省时有作用）⇒ **未修，上抛**：设计档两处自相矛盾，需设计位收口。
- 🟡 `BtestExpect.appendRevision` 无运行时调用者（人改检测只剩模式卡里的规则）⇒ **保留并披露**：按 §3.4 / KD-11，写回是 AI 的职责、宿主只校验，宿主没有写回调用点；该函数作为规则的参考实现由测试覆盖。
- 🔵 一次读失败报两条 warning（第二条归因错误）⇒ **已修**（`unreadable` 单列）。
- 🔵 空白 `url` 不计入口但工具仍会导航 ⇒ **已修**（判据直接拒绝并点名）。
- 🔵 `declared.length > 1` 不可达分支 + `startedAt` 未用 ⇒ **已修**（删除）。
- 🔵 §4 文件清单漂移（设置键落点 / `chat_models` 字段 / arb 拒绝文案）⇒ 档内漂移，交设计位对齐。

**自查后复跑**：`dart analyze` = `No issues found!`；50 条单测 = `All tests passed!`（第 2 轮全文评审未再派，理由是每轮成本 ~10 万字符，修复面已由用例与静态检查锁定；terminal state = `clean`，除上列 3 条披露/上抛项）。

**交付表（验收 ①–⑦ 实测）**

| # | 状态 | 实测命令与结果行 |
|---|---|---|
| ① `dart analyze` 零 issue | ✅ | `dart analyze` → `Analyzing baocode...` / `No issues found!` |
| ② 三档单测全绿、条数达标 | ✅ | `flutter test --no-pub test/browser/btest_policy_test.dart test/browser/btest_card_test.dart test/browser/btest_expect_file_test.dart` → `00:00 +50: All tests passed!`（policy 26 / card 9 / expect_file 15） |
| ③ 卡内容清单标签齐全 | ✅ | 脚本扫描 `btest_card.dart`：`[D1]`–`[D7]` / `[J1]`–`[J7]` / `[P01]`–`[P19]` / `[H1]`–`[H3]` 共 36 个，`missing: []` |
| ④ 模式卡标记唯一性 | ✅ | 文件内 `[btest-mode-card v1]` 出现 1 次；`btest_card_test` 断言 `countIn(text, marker) == 1` 通过 |
| ⑤ `doc_check` 门禁 PASS | ⚠️ | `DOC-CHECK GATE: REFUSED（命中 6 条）` —— 6 条全在**别的笔**下：批档 §1/§2 的 `:49`（2 条档缺锚 + 1 条行宽 323）、`:61`（331）、`:266`（347），需求档 `:49`（372）。设计档 0 命中。§1/§2 非本段作者，§5 不得改写他段 |
| ⑥ `git status` 只含批准改动面 | ✅ | 见父代理侧 `git status --porcelain`：11 个改档 + 4 个新实现档 + 3 个测试档；`docs/batches/…` 为本段追加 |
| ⑦ 报告逐条实测读数 | ✅ | 本段与交付报告均按命令 + 结果行给出 |

**设计未规定、我自行决定（附理由）**

1. `btest_run_start.mode` 可缺省，默认取 `btest.readonly`（默认只读）——否则 §9 的「默认只读开关」没有任何机械作用；与 §3.3「必填」冲突，上抛。
2. 切出 btest 时**作废**未结束的 run（§9 允许「结束或作废」二选一）——作废比留下一个无法再 `btest_run_end` 的死 run 更安全。
3. 无 host 可判的工具（`browser_tabs`）跳过 allowHosts 判定——它不指向任何页面；有目标但解析不出 host 时一律拒绝（取严）。
4. `btest_run_start` / `btest_run_end` **常注册**、会话级拒绝——设计 §3.3 写「仅 btest 开启时注册」，但 §7 #12 要求非 btest 会话调用时被拒；注册面是全局的，按会话注册会让 run 中途切换后工具消失。
5. `browser_open` 作为首次入口被允许（按设计 §3.6.2 末条，读数在报告头可见 `open=1`）。
6. 只有 `browser_navigate` 能带 `detour`（设计参数表如此），因此经 `browser_act` navigate 步 / `browser_open` 的第二次入口一律拒——这两条没有参数可携带 `detour`。
7. 拒绝文案固定英文 `btest denied: <动作> on <host> — <规则> (Settings → Browser → btest)`（§3.7 给定的形状），未进 arb；用户界面文案（状态行 / 设置项）全部走 l10n。
8. 卡片实际 ~4.5k 字符（设计估计 ~1.5k）：36 个必带标签本身就要 ~1.6k，压缩空间只剩措辞。
9. 设置键落在 `BtestSettings`（`btest_mode.dart`）而非 `app_settings.dart`——后者会与 `browser_page.dart` 形成环，且 `app_settings.dart` 依赖 UI 页。
10. btest 的 `mode` 选项放在内核 mode 选择器同一列表（`ChatSession.modes` 包装），composer 只加状态行——设计 §3.1 的「与 plan 同形」据此实现。
11. 卡以 `TextContext`（`EditorContext` 子类，覆盖 `note`/`editorNote`/`dedupeKey`/`name`）随 `KernelTurn.contexts` 注入——设计指定的通道，`EditorContext` 只接受文件路径，需要这个形态。

**上抛主代理（[上抛·待裁]）**

1. btest 模式持久化：`KernelContext.settings` 只读、`workspace.dart` 在批准改动面之外 ⇒ 当前「切模式不落盘，重启即 off」，设计 §3.2 的「会话恢复」入口与用例 #11 的会话层前提不可达。请裁：扩改动面写回会话设置，或设计位明确「仅会话内存」。
2. `mode` 必填 vs 默认只读开关：设计档 §3.3 / §9 自相矛盾，请设计位收口（实现现取 §9，fail-closed）。
3. ⑤ 门禁的 6 条命中都在主代理/需求档笔域，需对应作者修；批档 §1/§2 的旧行 §5 不改写。

**已知且不改（设计边界）**：`browser_evaluate` 写形态是启发式（§3.6.3 明写「启发式未命中不等于安全」）；`browser_breakpoints` 未在两份工具表里，按取严当作写动作拒绝。

## §6 验证与收口（父代理）

## 交付验证（主 agent，2026-10-23 01:10）

**我的实测读数**（不采信自述）：
- `dart analyze` → `No issues found!`
- `flutter test --no-pub test/browser/btest_policy_test.dart test/browser/btest_card_test.dart test/browser/btest_expect_file_test.dart` → `00:00 +50: All tests passed!`
- `doc_check(mode:"gate")` 三档 → `DOC-CHECK GATE: PASS`（0 条命中；6 条命中由我在本轮回写批档 §1/§2 与需求档 §5 修掉）
- 闸口位置实读：`lib/browser/browser_tools.dart:120` 的 `_btest(...)` 调用早于 `:121` 的 `tabId is! int` 早退 ✅；`:147` 豁免集在闸口内 ✅

**对实施方上抛三条的裁定**

1. **btest 持久化** ⇒ **一期声明「仅会话内存」**，不扩改动面到 `workspace.dart`。理由：扩面会越出本批边界（该档是工作区真相源，改动牵动会话选择与迁移）；会话内存语义下 F1 的「可切、可退」成立，仅「重启后恢复」不可达 ⇒ 设计用例 #11 的会话层前提在**本批不成立**，记入本文末「本轮未覆盖」。欠账登记为台账 #153。
2. **`mode` 必填 vs 默认只读开关** ⇒ **采纳实现侧（默认只读）**：它是 fail-closed 的一侧，设计 §9 的「默认只读开关」也只有在这种形态下才有机械作用。设计档 §3.3 的「必填」是档内矛盾，记为台账 #154（小设计轮修正，不改代码）。
3. **门禁 6 条** ⇒ 已由我在本轮修正（批档 §1/§2 长行折行、两条跨仓 `.md` 指针改为不带扩展名的描述），复跑 PASS。

**实施方披露项的处置**

| 披露 | 处置 |
|---|---|
| `btest_mode.dart` 787 行（设计预算 ≤260）等三档超预算 | **接受并登记**：拆分缝已由设计 §4 给定，超预算主因是 run 生命周期 + 设置读写 + 两个工具注册同处一档；与 SPLIT-1…4 一并挂 #150 后的结构批处理 |
| 模式卡实际 ~4.5k 字符（设计估 ~1.5k） | **接受**：36 个必带标签本身约 1.6k，压到 1.5k 只能删标签而破坏内容判据；token 影响记入 #155（若实测每轮成本明显，再收措辞） |
| 拒绝文案不进 arb（固定英文） | **接受**：它是给模型的工具错误文本，不是用户界面文案；界面文案已走 l10n |
| `appendRevision` 无运行时调用者 | **接受**：按设计 §3.4/KD-11，写回是 AI 职责、宿主只校验；该函数是规则的参考实现 + 测试覆盖点 |
| 单测未「随批删」 | **本批收口时删除**（按测试纪律，交付即删，§5 只留一行读数） |

**本轮未覆盖（如实登记）**：① 真机业务线跑（被 #152 阻塞——带表格页面所有浏览器工具报 cast 错误）；② 设计用例 #11 的「会话恢复」入口（依赖 #153）；③ 无审批卡的走查（需真机，且与 ① 同一阻塞）。
