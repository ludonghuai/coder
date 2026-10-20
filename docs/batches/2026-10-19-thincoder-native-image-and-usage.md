# 2026-10-19 · thincoder 原生图片块 + 用量
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 01:21「原生图片块；远程SSH；用量这几个我们也要提上日程了」+ 01:23「先A后B」；A = 本批（F19 / F20），B = 批 2（F8 远程 SSH）。
> 台账 = #78 / #79（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-19）
- 来源：用户 2026-10-19 01:21「原生图片块；远程SSH；用量这几个我们也要提上日程了」+ 01:23「先A后B」。
- A = 本批（批 11：F19 原生图片块 + F20 用量）；B = 批 2（F8 远程 SSH，下一批）。
- 需求：`docs/requirements/thincoder-adapter.md` F19 / F20（本轮落条目）；F17/F18 属批 10（在飞），本批不动。
- 边界：F19 若需动 `thincoder/` ⇒ **B1 例外须用户明示裁定**；设计先查证并停报最小改动面与替代方案。F20 桌面侧；不改 CLI 的 usage 计算。
- 验收方向：F19 `session/prompt` 含原生 image 块 + 模型可引用图片内容 + 不支持时回退；F20 会话累计 = 回合之和 + 与终端 `/usage` 同口径。
- 流程：设计（eng-designer）→ 设计评审（用户点火）→ 用户批准 → 实现。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（桌面半交付回填）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖）**

- F19 原生图片块（需求档 `docs/requirements/thincoder-adapter.md` F19）：桌面按握手能力位分两路——`agentCapabilities.promptCapabilities.image === true` ⇒ `session/prompt` 的 `prompt` 数组 = 1 个 text 块 + 逐图 image 块（`{type:"image", data:<base64>, mimeType}`，不落盘）；缺位 / false ⇒ 今天逐字（落盘 `.thincoder/tmp/paste-…` + `[Attached images: …]` 正文行 + 单 text 块）。
- F20 用量（同档 F20；口径已由主 agent 收窄并同步需求档）：回合 token = 本回合各条 `usage_update.used` 之和（turn footer「N tokens」）；会话累计 = 全会话之和（上下文面板新增「本会话累计」一行）；上下文占用沿用最新 `used/size`（F10 不变）；成本不做（无来源，登记设计档 §14-25）；与终端同口径 = 同一 `onUsage` 来源的 token 合计（终端状态行 ↑prompt ↓completion；终端无 `/usage` 命令，登记 §14-26）。
- 不在本批：F17 / F18（批 10 在飞）· F8 远程 SSH（批 2）· 账号 / 账单用量 · 图片编辑 / OCR · 远程项目图片 · CLI usage 计算 · 终端 `/usage` 新增。

**设计档落点**

- `docs/design/thincoder-adapter.md`（2624 → **2889 行**）：
  - §22（F19）：最近先例（Claude 原生图 / 既有握手读取 / `_attachImages` 限额）· survey 证据（ACP v1 `ImageContent` 逐字；外仓 `client-caps.mjs` / `handlers-session.mjs` / `resource-link.mjs` / `setup.mjs` / `suspension.mjs` 坐标）· 22.1 两路做法 · 22.2 线形 / 限额 / CLI 最小面（B1 待裁）· 22.3 桌面半文件表 · 22.4 D82–D86 · 22.5 验收对照 · 22.6 T93–T95 · 22.7 边界 · 22.8 走查。
  - §23（F20）：先例 · survey（`usage_update` 语义 / 终端累计与 context% 两个仪器 / 无 `/usage` / core 无价目表）· 23.1 三条数据路 · 23.2 契约（`TurnUsage.spentTokens` / `ContextUsage.sessionSpent`）· 23.3 文件表 · 23.4 D87–D90 · 23.5 验收 · 23.6 T96–T98 · 23.7 边界 · 23.8 走查。
  - 索引面：抬头分批 + 批 11 · §5.2 尾指针 · §7 F19 / F20 行 + 覆盖句 · §9 测试面 · §10 边界 · §11 UI · §12-A-4 线形 · §14-25 / -26 / -27。

**机制设计（一句一条）**

- F19 桌面：能力位只在 `_handshake` 读（内核仍只声明 `AcceptsImageFiles`，D82）；原生路与回退路共用同一限额 / 丢弃判据（15 MB/图 · 30 MB/回合）；非多模态模型退化在 CLI（`stripImagesForTextModel`，D84）；回退判据 = 能力位在场且为 true（D85）。
- F19 CLI 半（B1，§22.2）：5 档 ≈ +70 行 + 测试——① `client-caps.mjs` 声明 `image:true`；② `resource-link.mjs` 新增 `buildPromptContent`（白名单 / 解码 / 限额）；③ `handlers-session.mjs` 有图走 `{text, images}`、无图仍传串；④ `thincoder-core/agent/setup.mjs` 收富输入（检索用 `.text`，`pushReal` 出 `image_url` parts）；⑤ `suspension.mjs` 窗内透传富对象。替代（`resource_link` / `embeddedContext`）已查实不可行。
- F20：`ThincoderEvents._usage` 累加 `_turnSpent` / `_spent`；`_endTurn` 填 `TurnEnded.usage = TurnUsage(spentTokens:)`；会话累计随 `ContextUsage.sessionSpent` 进面板；不重算、不拆分（ACP 只携合计）、不伪造 speed / cost。

**受影响文件与测试覆盖**

| 面 | 文件 | 增量 |
|---|---|---|
| F19 桌面 | `lib/kernel/thincoder/thincoder_kernel.dart`（1216） | ≤ +30 |
| F19 测试 | `test/kernel/thincoder_kernel_test.dart`（3088）· `thincoder_mock.dart`（632） | ≤ +110 · ≤ +6 |
| F20 翻译 | `lib/kernel/thincoder/thincoder_events.dart`（799） | ≤ +8（⇒ ≤807，入 >800 名单；缝 = 子代理段（段头 `:436`，段界由拆分批勘定）出档 `thincoder_agents.dart`，详设计档 §5.2） |
| F20 内核 | `thincoder_kernel.dart`（同上） | ≤ +6（与 F19 合计 ≤ +36） |
| F20 宿主 | `kernel_types.dart`（610）· `chat_models.dart`（806）· `turn_footer.dart`（348）· `context_usage_panel.dart`（530） | ≤ +4 · ≤ +8 · ≤ +6 · ≤ +14 |
| F20 测试 | `thincoder_kernel_test.dart`（同上） | ≤ +90（与 F19 合计 ≤ +200） |
| l10n | `app_en.arb`（7026）· `app_zh.arb`（2703） | 各 +2（⇒ 7028 / 2705） |
| CLI（B1，out-of-repo） | 5 档 ≈ +70 + 测试 | 待裁 |

- 行数 = 2026-10-19 `wc -l` 实测（与设计档 §22.3 / §23.3 同口径）。
- 零改动：`chat_session.dart` / `transcript.dart` / Claude·Codex 内核 / 宿主收图判据 / 固件 / `thincoder_catalog.dart`。

**验收对照（需求条目 → 设计落点 → 判据）**

- F19：prompt 数组含原生 image 块（§22.5 / T93）· 模型引用图片内容（走查 2 + CLI 半单测）· 不支持回退且行为同今天（T94）· 限额不回归（T95）。
- F20：多回合会话累计 = 各回合之和（T96）· 上下文占用随 `usage_update` 更新（T97）· 与终端同口径（走查 3；机检 = 同源求和）· 回合 token 可见（T96）· 成本不做（§14-25）。

**关键决策**

- D82 能力位随握手、不按编译期接口翻牌 · D83 原生路不落盘 · D84 视觉退化在 CLI · D85 能力位即回退判据 · D86 B1 面 5 档。
- D87 回合 / 会话 = `used` 之和 · D88 会话累计挂 `ContextUsage.sessionSpent` · D89 成本不做 · D90 同口径 = 同一 `onUsage` 来源的 token 合计、context% 不作对照。

**上抛项**

- [已裁] F19 B1 例外：**A = 允许**（用户 2026-10-19 01:37「运行改thincoder仓库」）；CLI 侧另立 out-of-repo 轮（≈5 档 +70 行，§22.2 表）；实现待设计评审通过后的批准。
- [上抛·知会] F20 口径收窄（会话累计 = Σ `usage_update.used`；context% 不作对照；成本不做 + 判定条件）已获主 agent 通过，需求档已同步（主 agent 笔）。
- [上抛·知会] 设计档尾部存在「变更记录」段（D8 禁止项的历史存量，早于本批）；本批未新增条目、未擅自删除——按「既有存量另立清理」处理。
- 零代码改动（设计轮）；设计档行数 = 2889（编制日实测）。

**修正轮 1（读数口径统一；零代码）**

- ① §23 引言的需求引用句改为「按回合与会话的 token、上下文占用，与终端状态行 ↑+↓ 口径对齐（终端无 `/usage`；context% 不作对照）；成本本批不做」——与 D90 / §23.5 / 需求档 F20 同句（`docs/design/thincoder-adapter.md:2711`）。同句原先把「成本」列为展示项，与 D89 / §23.1（成本不做）相抵，随本轮一并对齐。
- ② §22.3 / §23.3 行数统一 `wc -l` 实测（kernel 1216 · test 3088 · chat_models 806 · arb 7026 / 2703 · events 799 · mock 632 · kernel_types 610 · turn_footer 348 · context_usage_panel 530；两节标题注明口径，`:2648` / `:2768`），增量上界逐行重算（⇒ ≤1246 / ≤3198 / ≤638 / ≤807 / ≤1222 / ≤614 / ≤814 / ≤354 / ≤544 / 7028·2705 / ≤3178）。除任务给定的六档外，mock / kernel_types / turn_footer / context_usage_panel 四档同带 +1 偏差（实测 632 / 610 / 348 / 530），一并统一——否则两表仍是两套读数。
- ③ §5.2 的 >800 名单加 `thincoder_events`：799 ⇒ ≤807 越线；缝 = 子代理段（段头 `:436`）出档 `thincoder_agents.dart`，段界由拆分批勘定（`_putSubagent` / `_card` 另有 `:682` / `:741` 调用点）；触发 = 下一次结构级触碰或独立拆分批立项（`:331`）。
- ④ 缝坐标订正：原记 `:436-531` 不成立——531 在 `endSubagents()` 体内（该方法到 `:552`），且 `_card` / `_putSubagent` / `_reportTask` / `_endTask` / `_reportTasks`（`:557-607`）同属子代理段；已改为「段头 `:436`，段界由拆分批勘定」。
- ⑤ 本轮 16 处均为行内替换，零代码；未新增变更记录条目（D8）。设计档行数（含 ⑦ 的折行）见 ⑧。

- ⑥ 本节「受影响文件与测试覆盖」表同步为同一口径（1216 / 3088 / 806 / 799 / 610 / 348 / 530 / 7026·2703；events ≤807；arb 各 +2 ⇒ 7028 / 2705；缝坐标同 ④），表下注明 `wc -l`——实施基数只有一套（本表是实现者的起算面，同一缺陷不留在本档）。

- ⑦ §19.4 的批 8 体量行里「`thincoder_events.dart` 784（<800，不入名单）」改为「（<800；批 11 后 ⇒ ≤807 入名单，见 §5.2）」，并在句号处折行——同一档内不能一处说入名单、一处说不入；折行使该行由 308 字符降到 265（原已超 300，现达标）。
- ⑧ 读数与计数订正（对 ⑤）：设计档内容改动 = 17 处（16 处行内替换 + §19.4 口径订正 1 处），另加 1 处折行 ⇒ 净增 1 行；设计档 = **2889 行**（`wc -l` 实测；编辑器视图 2890，差 = 末尾空行）——⑤ 记的 2888 是折行前的读数。

**修正轮 2（评审 #2–#12 落地；零代码；设计档 2026-10-19）**

- #2 原生路指针：§4 F6 · D7 · §3.4 `session/prompt` 行（注明可含 image 块）· §18.2-② 各加「原生路见 §22（D82–D85）；F6 = 回退路」。
- #3 `thincoder_events.dart` 799 → ≤807 越 800：§23.3 补 `thincoder_agents.dart` 出档分步 + 行数预算（判据 = 拆后 ≤775）；§5.2 同步指针。
- #4 §22.3 体量条钉死顺序：§21.3 拆分（批 10 第三波）须先于 / 同批于 F19·F20 实施；未拆 ≈1252 > 1148 ⇒ 处置 = 不得先落 kernel 增量，违例停批上报。§22.3 ① / §23.3 ② 的投影改按拆分后基线（≤1075 / ≤1081）。
- #5 §22.2 CLI 半补契约档 `ACP-CLIENT.md` 与 `CHANGELOG.md` 两行（同拍义务，形同 §16.1 f–k）；测试档行号 ⑥ → ⑧。
- #6 / #8 §23.5 与 §23.8 步 4 改逐回合 delta（注明起算点 + 「一致」= 同源同算法、非同数值）；走查 3 → 走查 4。
- #7 抬头状态行日期刷 2026-10-19；不新增变更记录条目（D8；该节由台账 #53 统一删除）。
- #9 §23.1 补自动轮 / D62 撤暂存轮的用量归属（自动轮 = 自己的 `TurnEnded.usage`；撤暂存轮 = 并进在飞用户回合）；用例不补（走查见错 ⇒ T99）。
- #10 >500 层统一声明（§5.2 末段「体量立场只跟 >800」）+ mock / kernel_types / context_usage_panel 三处层位说明。
- #11 §22.7-4 改条件式（若 out-of-repo 轮裁剪 ⑤ ⇒ 缺口成立），与 §22.2 ⑤ 在做面一致。
- #12 §22.7-7 补 CLI 会话存档图块去留口径（默认剥离、与重放跳过同判据；保留须给体量上界 + 扫除；存档字段面未核）。
- §21.3 注册表改名：`IdeWorkspace.open`（静态 `Set`）→ `openWorkspaces`（与实例方法 `open(String path)` 同名遮蔽，批 10 第三波编译红）；§21.1 / §21.3 ⑥ / D78 同步；§21.6 经 grep 无该符号，无需改。
- 设计档行数：2892 → **2918**（`wc -l` 实测）。

**修正轮 3（桌面半交付上抛四条收口；零代码；2026-10-19）**

- ① 会话累计口径改「随聊天会话存活」：§23.2 原「进程生命周期内…重开 / 重连归零」改为同一内核实例（一次聊天会话）内累计、`restart()` / release 后重新 attach 不清零、新建聊天会话（新内核实例）从 0 起（`docs/design/thincoder-adapter.md:2792`）。代码依据：`_spent` 只在内核构造时置 0（`thincoder_events.dart:45`；`begin()` 只清 `_turnSpent`，`:107-112`），`_events` 只在构造时建（`thincoder_kernel.dart:59`）、`_teardown()` / `restart()` 不重建（`:426` / `:487-491`）。§23.7-7（`:2859`）、§23.7-3（`:2855`）、§23.5 走查 4 行（`:2837`）同步；§14-26 未写进程口径，未动。
- ② §22.7 新增第 8 条：握手完成前的首条消息走回退路——能力位在 `_deliver` 开头快照（`final native = _nativeImages`，`thincoder_kernel.dart:592`），握手在 `_ensureStarted()`（`:629`）才发生 ⇒ 冷启动首条含图消息在握手前发出时走回退路（落盘 + 路径行）；回退安全、窗口窄（仅首条）。判定条件 = 走查见到冷启动首条图未走原生 ⇒ 评估把附件判定移到 `_ensureStarted()` 之后（改变消息即时回显时机）⇒ 单独立项（`docs/design/thincoder-adapter.md:2719`）。
- ③ §22.7 新增第 9 条：原生路全部图被弃 + 无正文 ⇒ 空 `prompt` 数组 ⇒ CLI 按空判据回 `-32602`（`thincoder_kernel.dart:650-659`）；回退路同场景同样发不出有效文本。判定条件 = 走查见到未发图却报参数错 ⇒ 桌面补空判据（无有效内容 ⇒ 本地 error 提示，不发请求）（`:2720`）。
- ④ §22.6 T95 拆 T95①（15 MB/图）/ T95②（30 MB/回合合计）：T95② = 三张各 11 MB（每张合法、合计 33 MB > 30 MB）⇒ 前两张进块、第三张被弃 + 一条 `NoticeItem(warning)`（`:2705`）；§22.5 判据行随标 T95① / T95②（`:2695`）。代码侧用例另派（本批零代码）。
- 造数订正（对派单原例）：原文「两张合法图合计超 30 MB」算术不成立——每张 ≤15 MB 时两张最多恰 30 MB（判据为 `bytes > budget`，等号放行），超不过 ⇒ 改为三张各 11 MB 才能真正打到「回合合计」分支；语义（第二张之后的超预算图被弃）不变，仅造数改形。
- 设计档 = **2927** 行（`wc -l` 实测；本轮净 +3 = §22.7 两条 + T95② 一行）。
- 行宽：本轮新增 / 改动行均 ≤300 字符；档内另有 30 处 >300 字符的历史行长（本轮未触碰，按既有存量另处置）。
- 零代码；需求档 / 批次档 §3 / §5 / §6 未动。

**修正轮 3 · 追加（§22.7-7 存档图块收口；零代码；2026-10-19）**

- ⑤ §22.7-7 改口径并转实现待办（选 ①）：设计原写「口径 = 剥离」但只挂「走查见到膨胀 ⇒ 按剥离落地」的观测条件，与 #34 实现（`contextHistory` 未过滤、base64 图随每回合 `save` 整写槽 JSON）不一致。现改为：口径 = 剥离（默认）；落地 = out-of-repo 轮实现待办——`thincoder-core/session.mjs` 的 `contextHistory`（`:126`，进槽 `:183-184`）前加只丢 `image_url` parts 的 mapper（不复用 `slimForDisplay`：它会截断 tool args / content，机器线须逐字节保持），预估 ≤ +10 行 + 测试档另计；`thincoder-cli/src/acp/session.mjs` 现载他批未提交改动（`git status` 实测 M；`:101` 每回合 `save` 调用面），开工前与那条改动对齐、不得覆盖（`docs/design/thincoder-adapter.md:2717-2721`）。
- 选 ① 的依据：≤30 MB/回合 × 4/3 ≈ 40 MB 每回合写盘是真实代价（`thincoder-cli/src/acp/session.mjs:101` 每回合 `save`），不是观测项；观测条件只保留为「剥离未生效」的验伪判据。
- 行号刷新（§22.7-7 改写后）：§22.7-8 = `:2722`、§22.7-9 = `:2723`（前记 `:2719` / `:2720` 作废）。
- 设计档 = **2930** 行（`wc -l` 实测；本轮净 +6 = §22.7 两条（2 行）+ T95②（1 行）+ §22.7-7 改写（2 → 5 行，+3））。
- 行宽：本轮新增 / 改动行均 ≤300 字符；档内 30 处 >300 字符的历史行长（本轮未触碰）。
- 零代码；需求档 / 批次档 §3 / §5 / §6 未动。

- 行号刷新 ②（§22.7-7 改写使 §23 整体 +3）：§23.2 = `:2795`、§23.5 走查 4 行 = `:2840`、§23.7-3 = `:2858`、§23.7-7 = `:2862`（① 内前记 `:2792` / `:2837` / `:2855` / `:2859` 作废）；§22.5 = `:2695`、T95② = `:2705`、§22.7-8 = `:2722`、§22.7-9 = `:2723`。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 评审对象
批 11：原生图片块 + 用量（F19 / F20，设计 §22 / §23）· 对象状态 待评审 · 范围档：`docs/design/thincoder-adapter.md`（2892 行）· `docs/requirements/thincoder-adapter.md`（236 行）

### 结论摘要
- 设计档在场（同一档内追加 §22 / §23，未另立新档）；§22 / §23 各带「最近先例（对齐 ∥ 偏离及理由）」与「survey 证据」两行 ⇒ 先例坐标、偏离理由、公开源（ACP v1 schema）与同仓实测均在场。
- 需求覆盖：F19 三条验收（原生块 / 模型看图 / 回退同今天）与 F20 四条（回合与会话 token / 上下文占用 / 同口径 / 成本不做）逐条有落点与判据（§22.5 / §23.5）。
- 受影响文件表：两节均给「当前行数 + 预期增量」，算术自洽（1216+30/6、3088+110/90、events 799+8、mock 632+6、kernel_types 610+4、chat_models 806+8、turn_footer 348+6、panel 530+14、arb 7026+2 / 2703+2 全部核过）；仓内实测值本评审不越界核对（只读两份文档）。
- 未发现 🔴。🟡 7 条（需求档与设计前序段落的陈述滞后 2 条、体量/批次顺序 2 条、B1 契约档同拍 1 条、F20 跨进程对照判据 1 条、记录面滞后 1 条）；🔵 5 条。

### 发现表
| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Requirements / doc-state | 🟡 | 需求档内部与 F19 反向：§2.2 仍写 `promptCapabilities` 图片「全 false」（`docs/requirements/thincoder-adapter.md:39`）、§5 映射行仍写 `promptCapabilities.image: false`（`:170`）、B2 仍把「图片直传」列为首版不做（`:188`）；本批实施后这三处即成为说反的陈述，而 §5 正是 E5 的「单一维护点」。 | 三处按 F19 口径改写（能力位改 true / B2 补批 11 例外 / §2.2 事实基线标注批次现状），与 `docs/requirements/thincoder-adapter.md:131`–`:135` 对齐。 |
| 2 | Document ownership / doc-state | 🟡 | 设计档前序段落未回灌原生路：§4 F6 仍把「落盘 `paste-…` + 路径行」写成唯一形（`docs/design/thincoder-adapter.md:239`）、D7 同（`:348`）、§3.4 的 `session/prompt` 行仍写 `prompt: [{type:'text', text}]`（`:105`）、§18.2-② 仍称 `_attachImages(turn)` 就是既有路径（`:1591`）。本批只新增 §22，未在这些位置留指针 ⇒ 按 F6/§3.4 落地的读者会漏掉原生分支。 | 在 §4 F6、D7、§3.4 prompt 行、§18.2-② 各加一句「原生路见 §22（D82–D85）；F6 = 回退路」，或照项目「随改」惯例把表述改成两路口径。 |
| 3 | Affected-file size | 🟡 | `thincoder_events.dart` 由 799 涨到 ≤807（`docs/design/thincoder-adapter.md:2775`）——本批自身把该档推过 >800 硬顶；§5.2 与 §23.3 只登记「入名单 + 缝候选 + 触发」（`:331` / `:2784`），没有拆分方案（对比 kernel 在 §21.3 有分步与行数预算，`:2458`–`:2463`）。 | 二选一：把增量压回 ≤800（累加器上移内核 / getter 合成一处）；或在 §23.3 给出 `thincoder_agents.dart` 出档的分步与行数预算（照 §21.3 的形）。 |
| 4 | Size / 批次顺序（协调项） | 🟡 | §22.3 的体量论证以「拆分后基线 1045」为前提（`:2659`），但同档当前实测 1216（`:2655`）；§21.3 的拆分属批 10 第三波（`:2472` / `:2463`），本批未写「拆分须先于本批落地」。若批 11 先落，kernel ≈1252，越过 §21.3「实现后 ≤1148」硬要求。 | 在该体量行钉死顺序（拆分先于 / 同批于 F19·F20 实施）与不满足时的处置；或把 1148 预算改成含本批 +36 的显式数。 |
| 5 | Methodology / B1 例外面 | 🟡 | §22.2 的 CLI 半只列代码档与该仓测试档（`:2640`–`:2645`），没有契约档 / CHANGELOG 的同拍行；本档对 B1 改动的既有口径是「契约档与需求档同拍义务」（`:755`），而 `promptCapabilities.image` 由 false 改 true 正是该仓契约档记过的事实。 | 在 §22.2 补两行：`ACP-CLIENT.md` 的相关事实与 prompt 内容块说明、`CHANGELOG.md` 的 `Unreleased/Added` 一行（照 §16.1 f–k 的形）。 |
| 6 | Acceptance criteria（可验性） | 🟡 | F20 的终端对照写成跨进程总量相等：§23.5 判据（`:2802`）与 §23.8 步 4（`:2831`）。两个进程各持自己的 `state.tokens`（§23.2 明写进程生命周期内累加、重连归零，`:2768`），终端那两轮 prompt 含更长历史 ⇒ 按构造不可能相等。 | 把对照写成「同进程窗口内增量」或「逐回合 delta（注明起算点）」，或明确「一致」指同源同算法而非同数值。 |
| 7 | Record face / 文档卫生 | 🟡 | 变更记录停在 2026-10-17 批 8（`:2891`）；批 10 设计（§20 / §21）、2026-10-18 轻渠道轮（`:1190`）、批 11（§22 / §23）均无条目；抬头状态行仍写「设计稿 · 2026-10-16」（`:7`），与 2026-10-19 的内容不符。 | 补批 10 / 批 11 两轮设计记录行（含本轮评审修正轮），并刷新抬头日期与状态。 |
| 8 | Clarity / 交叉引用 | 🔵 | §23.5 把终端对照指向「走查 3」（`:2802`），而 §23.8 的对照步是第 4 步（`:2831`），步 3 是面板自检。 | 改指「走查 4」，或重排走查步使两处编号一致。 |
| 9 | Coverage（自动轮与回合用量） | 🔵 | §23 只写「回合边界 = `_beginTurn` 清 `_turnSpent`」（`:2744`），未写批 8 两类无提示轮如何计入：自动轮自成回合（`:1847`）⇒ 自己的 footer；D62 撤暂存那一轮的量落在在飞用户回合（`:1859`）。T96–T98 未覆盖。 | 加一句写明两类轮口径（自动轮 = 自己的 `TurnEnded.usage`；撤暂存轮 = 并进在飞用户回合），并注明是否补用例。 |
| 10 | Affected-file size（>500 层） | 🔵 | 两节的行数与增量齐全且自洽，但 >500 层三档（`thincoder_mock.dart` 632→638 `:2657`、`kernel_types.dart` 610→614 `:2777`、`context_usage_panel.dart` 530→544 `:2780`）没有 proactive split review 的一句话，而 >800 各档都有缝候选。 | 三档各补一行层位说明，或统一声明「体量立场只跟 >800，>500 层不立缝」，与 §5.2 名单口径对齐。 |
| 11 | Scope wording | 🔵 | §22.2 把第 ⑤ 档（`suspension.mjs` 富对象透传）算进 B1 例外面并计入 +70（`:2644` / `:2647`），§22.7-4 又写成「B1 第 ⑤ 档不做时…登记为已知缺口」（`:2697`）⇒ 同一改动一处在做、一处不做。 | 把 §22.7-4 改成条件式（「若 out-of-repo 轮裁剪 ⑤ ⇒ 此缺口成立」），与 §22.2 的在做面一致。 |
| 12 | 边界 / CLI 侧后果 | 🔵 | §22.2 ④ 把图块写进用户消息 `content`（`:2643`），该仓会话每轮 `save` 落盘（本档 `:2064`）；本档只登记「重放不带图」（`:2696`），未写图块在槽文件里的去留与体量后果（单回合 ≤30 MB 原始字节，base64 更大）。 | 在 §22.7 补一条：保存时图块去留口径（剥离 / 保留 + 体量上界）与判定条件，避免槽文件随图膨胀成为走查期缺陷。 |

### 计数
🔴 0 · 🟡 7 · 🔵 5

VERDICT: pass

## §4 用户批准（主 agent）

**用户 B1 裁定（2026-10-19 01:37）**：逐字「运行改thincoder仓库」——F19 允许改 `thincoder/` 仓（方案 A）；CLI 侧 5 档 ≈ +70 行 + 测试，另立 out-of-repo 轮，保持上游可合并。设计按 A 定稿；实现仍待设计评审通过后的批准。

**用户批准（2026-10-19 02:07）**：逐字「批准设计」——批 11（F19 原生图片块 + F20 用量）设计批准；实现分两轮：桌面半（本仓 13 文件）+ CLI 半（thincoder 仓 out-of-repo，B1 已裁 A）。

## §5 实施记录（eng-coder）
**状态行**：实施完成



**交付摘要（CLI 半：①–⑥ + ⑧；⑦ 待父侧落 CHANGELOG）**

- 改动面（`thincoder/` 仓，7 档）：① `thincoder-cli/src/acp/client-caps.mjs`（`promptCapabilities.image: true`；注释改述）· ② `thincoder-cli/src/acp/resource-link.mjs`（新增 `buildPromptContent`：白名单 / 解码 / 限额 / 弃 + 一行日志）· ③ `thincoder-cli/src/acp/handlers-session.mjs`（有图富输入 `{text, images}`、无图仍单串、空判据扩为「无 text ∧ 无 resource_link ∧ 无图」）· ④ `thincoder-core/agent/setup.mjs`（`input` 收富形；`docSearch` / `memorySearch` 用 `.text`；`pushReal` content = text part + `image_url` parts）· ⑤ `thincoder-cli/src/acp/suspension.mjs`（窗内轮 / `submit` 透传富对象）· ⑥ `docs/cli/design/ACP-CLIENT.md`（`init` 能力位事实行 + `session/prompt` 内容块说明 + 两处行数同步）· ⑧ `thincoder-cli/test/build_prompt_content.test.mjs`（8 例）。
- 行数读数（改动后实测）：`client-caps.mjs` 89（+1）· `resource-link.mjs` 170（+46）· `handlers-session.mjs` 476（+2）· `setup.mjs` 323（+16；设计估 ≈+12）· `suspension.mjs` 202（+6）· 测试档 159（新增）。
- 本轮 delta（对实施前工作树）：6 档 +93 / −22（净 +71）+ 测试档 159；设计预算 ≈ +70（不含测试），落在量级内。
- ⑦ `CHANGELOG.md` **未写**（父侧维护面）；应加条目文本见本轮交付报告。

**决策透明表**

| 点 | 决策 | 依据 |
|---|---|---|
| 日志面 | `buildPromptContent(blocks, {cwd, log})` 多收一个可选 `log`（缺省 no-op），handler 注入既有 stderr `log` | 设计只写 `{cwd}`；弃块日志须走端侧既有日志面（零第二通道），多一个可选参数保持签名兼容 |
| 空正文 | 正文为空（只发图）时**省略** text part，不发空 text 块 | 设计 ④ 字面 = `[{type:"text", text}] + image_url parts`；§22.2 线形条「两者都空 ⇒ 不发空 text 块」；空 text 块被 Anthropic 拒（按 API 已知约束取安全侧，未对真 API 实测）。正文非空时逐字按设计 |
| base64 判形 | 标准字母表 + 尾部 ≤2 个 `=` + 长度 %4 ≠ 1；先按 base64 长度预拦必弃块再解码 | 「畸形 ⇒ 弃」的判据实现；预拦只为不为一枚必弃块解出整段字节 |
| 限额常量 | 直引 `@thincoder/core/attachments.mjs` 的 `IMAGE_MAX_BYTES` / `TURN_MAX_BYTES` | 设计 §22.2 ②「直引 `attachments.mjs:31-36` 常量」——零副本 |

**读数（本波实际执行）**

- `node --check` × 6 改动档 + 测试档：全 OK。
- `cd thincoder-cli && npm run lint`：`check-syntax: 128 file(s) OK`。
- `cd thincoder-cli && npm test`（= `node test/run.mjs`）：**8 tests / 8 pass / 0 fail**。
- 真机 ACP stdio 冒烟（`node bin/thincoder.cjs acp` + `initialize`）：回包 `agentCapabilities.promptCapabilities = {"image":true,"audio":false,"embeddedContext":false}`。
- 运行时读数（临时脚本，未入档）：`prepareRun` 富输入 ⇒ `pushReal` content = `[{"type":"text","text":"看图"},{"type":"image_url","image_url":{"url":"data:image/png;base64,AAAA"}}]`；图片-only ⇒ 无空 text part；字符串输入 ⇒ content 仍为字符串。`createAcpSession` 富输入穿过 session 层原引用不变。挂起窗富输入原样到 `runTurn`、字符串路径不变。
- 该仓既有测试：全仓仅本测试档（其余套件已于 2026-09-28 退役）⇒「既有测试保持绿」= 空集绿，无回归面。

**与设计的偏差 / 披露（含 out-of-scope）**

1. （字面偏差，已在上表决策）空正文省略 text part——设计 ④ 字面含空 text，本条按「不发空 text 块」取安全侧。
2. （同文档同步，已做）`docs/cli/design/ACP-CLIENT.md:199-200` 同步本轮触及的两处行数（`handlers-session` 474→476 · `client-caps` 88→89）——同文档计数与实测一致。
3. （out-of-scope，未改，应登记）`docs/cli/design/ACP-PROTOCOL-COMPLIANCE.md:138 / :186 / :314 / :319` 仍写「image 块丢弃照旧」「仅 image ⇒ -32602」——不在批准文件表；建议另立一笔或由父侧裁定。
4. （out-of-scope，未改，应登记）`docs/core/design/MODEL-SPECS.md:195-197` 仍写「ACP 侧 promptCapabilities 全 false（`client-caps.mjs:59`）」——取值与行号均失效。
5. （out-of-scope，未改，应登记）`thincoder-cli/src/acp/session.mjs:63-67` 窗退 idle 径的残余输入只取 `.text`：若该窄竞态命中，图仍会丢；⑤ 的主径（窗内轮）已闭合。
6. （out-of-scope，预存在缺陷，建议另批）`thincoder-core/provider/anthropic.mjs:41-54` 把消息数组原样下发——`image_url` parts 是 OpenAI 形；Claude（`format:"anthropic"`、`multimodal:true`）经该 transport 时，既有 `read_image` 图路与本轮原生图路都不会被转成 Anthropic `image` 块。code 证据在档，未对真 API 实测（unverified）。
7. （过程披露）实现期为记录基线，在 baocode 仓根临时写过 `thincoder-baseline-stat.txt` / `-status.txt` 两个未跟踪文件，随即删除（现 ENOENT，净零）；除此之外 baocode 仓零改动。
8. （过程披露）`git diff --stat` 基线含他批未提交改动（`session.mjs` / `suspension.mjs` / `ACP-CLIENT.md` 等）——本轮自己的 delta 用实施前工作树副本逐档核对（见上「本轮 delta」行），不改他批内容。

**审计与代码评审轮次**

- 内部 divergaence 审计（explore，read-only）：轮 1 = divergent——代码面 ①–⑥、⑧ 忠实、⑦ 守住；findings = 本 §5 空（已由本条补齐）· 两条文档漂移未报（已列入上表 3 / 4）· 空正文边界未披露（已列上表 1）· 两个临时基线文件（已列上表 7）。自修：补 §5、补披露、复核临时文件已删。复核终态见下方第二轮结论。
- 独立代码评审（advisor code）：见本段后续记录（轮次与终态由评审回执追加）。

**未改项（按任务书禁止面）**：baocode 仓（除上述临时文件、已删）· `CHANGELOG.md` · 批设计 / 需求档 · 无关代码 / 格式。

**本波交付（F19 / F20 桌面半）**

- F19 原生图片块：`_handshake` 读 `agentCapabilities.promptCapabilities.image` 存 `_nativeImages`（缺省 false；缺位 / 非 Map / 非 true 均回退，D85）；`_deliver` 一处分支 `_nativePrompt` / `_attachImages`；原生 prompt = 非空 text 块（正文 + 编辑器 note）+ 逐图 `{type:'image', mimeType, data: base64}`，不落盘、无 `[Attached images:]` 行；限额判据同今天（15 MB/图 · 30 MB/回合 · 扩展名白名单），丢弃计数与 `NoticeItem(warning)` 文案不变；`UserMessageItem.images` 仍为已接受图；`[Image #N]` 正文标记未触碰。
- F20 用量：`ThincoderEvents._usage` 同帧累加 `_spent`（会话）与 `_turnSpent`（回合），`begin()` 清回合量；`ContextUsage.sessionSpent` 随 `UsageReported` 下发；`_endTurn` 填 `TurnUsage(spentTokens:)`（0 ⇒ null）；`TurnUsage.totalTokens` 增加 `spentTokens` 前置；turn footer 仅合计时用 `turnTokensSpentHint`；上下文面板新增「本会话累计」行（非 null 才显示）；成本 / speed 不伪造；`chat_session.dart` / `mock_conversation.dart` 零改。
- l10n：`turnTokensSpentHint` / `usageSessionTotal` 入 `app_en.arb` / `app_zh.arb`，`flutter gen-l10n` 重生成三个 `app_localizations*.dart`。
- 测试：T93–T98 入 `test/kernel/thincoder_kernel_test.dart`；mock 增 `promptImage` 开关（缺省 false = 今天）。

**读数（本机，2026-10-19）**

| 命令 | 结果 |
|---|---|
| `flutter test --no-pub test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_files_test.dart test/ide/ide_kernel_files_test.dart test/chat/editor_context_chip_test.dart test/usage_panel_test.dart test/chat/turn_footer_test.dart` | +151 全绿（含 T93–T98；既有图片回退用例保持绿） |
| `flutter analyze --no-pub` | 11 条，均为本波外既有项；本波 13 文件 0 新增 |
| `flutter gen-l10n` | 成功；两键入两源档 + 三生成档 |

**预算对照（`wc -l` 口径，与设计档同口径）**

| 档 | 预算 | 实测 |
|---|---|---|
| `thincoder_kernel.dart` | ≤1091 | 1091 |
| `thincoder_events.dart` | ≤807 | 807 |
| `kernel_types.dart` | ≤614 | 614 |
| `chat_models.dart` | ≤814 | 811 |
| `turn_footer.dart` | ≤354 | 353 |
| `context_usage_panel.dart` | ≤544 | 534 |
| `thincoder_mock.dart` | ≤638 | 637 |
| `app_en.arb` / `app_zh.arb` | 各 +2 | 各 +2（7036 / 2707） |
| `thincoder_kernel_test.dart` | ≤3595（+200） | 3590（+195） |

- 任务书「测试（3395，≤+200 ⇒ ≤3505）」的 3505 与 +200 算术不一致（+110 的上界）；按设计档 §22.3 +110 与 §23.3 +90 的合计 +200（⇒ ≤3595）执行，实测 +195。

**偏差 / 待裁**

1. [上抛·知会] 会话累计不随进程重连清零：`_spent` 只在内核构造时置 0，`restart()` / release-reattach 后继续累计；设计 `docs/design/thincoder-adapter.md` §23.2 / §23.7-7 写「重开 / 重连归零」。本波按任务书列出的改动面实施（无重置钩子，行数恰在预算上限），未擅自加面；建议设计侧二选一收口（补重置点 + 预算，或改口径为「随会话存活」）。
2. [上抛·知会] 原生能力位在 `_deliver` 开头快照（`final native = _nativeImages`）：首次冷启动若用户在握手完成前发送，首条消息走回退路（落盘 + 路径行）。回退安全、窗口窄；消除需把附件判定移到 `_ensureStarted()` 之后（会改变消息即时回显时机），本波未改。
3. 原生路与回退路各有一份限额谓词（行为一致）；原生路的 30 MB/回合合计未单测（T95 只覆盖 15 MB/图）。
4. 原生路「全部图被弃 + 无正文」得到空 `prompt` 数组（CLI 按 -32602 拒绝）；回退路同场景也发不出有效文本，属既有边界，未改。

**审计与代码评审**

- 内部 explore 偏差审计：1 轮，2 条非阻断（§5 未落档——本段即补；会话累计重连口径——见偏差 1）。
- advisor 代码评审：1 轮，0 🔴；🟡 2（重连口径、握手前首条回退）+ 🔵 4（限额谓词重复、空 prompt 边界、三档行数读数各 +1、英文 hint 措辞）。行数 +1 是编辑器视图口径（本轮审计以 `wc -l` 复核 = 1091 / 807 / 614，均在预算内）；英文措辞已改并经 `flutter gen-l10n` 重生。其余按报告面登记，终态 `clean`。
- 修正轮：0 轮代码修复（评审无阻断项）。

**文件（13）**

`lib/kernel/thincoder/thincoder_kernel.dart` · `lib/kernel/thincoder/thincoder_events.dart` · `lib/kernel/kernel_types.dart` · `lib/chat/chat_models.dart` · `lib/chat/widgets/turn_footer.dart` · `lib/chat/panels/context_usage_panel.dart` · `lib/kernel/thincoder/thincoder_mock.dart` · `lib/l10n/app_en.arb` · `lib/l10n/app_zh.arb` · `lib/l10n/app_localizations.dart` · `lib/l10n/app_localizations_en.dart` · `lib/l10n/app_localizations_zh.dart` · `test/kernel/thincoder_kernel_test.dart`

**代码评审轮 1（advisor code）：verdict = pass（0 🔴 · 3 🟡 · 3 🔵）**

- 🟡 测试档落在 `thincoder-cli/test/*.test.mjs` 收集面（`thincoder-cli/test/run.mjs:50` 两层 glob）⇒ 成为 `npm test` 常驻内容，与核 `docs/core/design/TESTING.md:92`「单元测试档零留存（用毕即删）、**不进任何门**」/ `:315`「不得以单元测试档凑门」相抵。**本波保留任务书默认路径**（父任务书明示 `thincoder-cli/test/build_prompt_content.test.mjs` 为默认、且 `npm test` 是父侧可复跑的门禁读数）；**上抛父侧裁定**——收口删档时按 TESTING.md §2.3 一并处置（移 `docs/batches/` 直跑或维持现路径并同步口径）。
- 🟡 `format:"anthropic"` 传输层不转 `image_url` part（`thincoder-core/provider/anthropic.mjs:47/:54` 原样下发；`normalize.mjs:109` 对 `multimodal:true` 的 Claude 族不剥）——预存在缺陷、已列本表第 6 条；属另一批。
- 🟡 槽文件体量（已补披露）：原生图经 `pushReal` 入 `agent.history`（`setup.mjs:191`），`saveSession` 的 `contextHistory` 未过滤（`thincoder-core/session.mjs:126` / `:184`），base64 图（≤30 MB/回合 ×4/3）随每回合 `save`（`thincoder-cli/src/acp/session.mjs:101`）整写槽 JSON；人类读线已剥（`session-segments.mjs:36-39`）。设计 §22.7-7 口径 = 剥离、判定条件 = 走查见到膨胀——本波按判定条件未落，建议 §6 收口挂「带图回合后的槽文件体量观测」。
- 🔵 已修：`resource-link.mjs` 白名单注释原写「与核 `DATA_URL_RE` 同集」——核另收别名 `image/jpg`，已改为「四型白名单；核另收 `image/jpg`，此处按设计不收」。
- 🔵 已修：`ACP-CLIENT.md:31` 能力位行补三键取值（`promptCapabilities: {image: true, audio: false, embeddedContext: false}`），与设计 §22.2 ⑥「事实行改 true」逐字对上。
- 🔵 超阈用例的 ≈60 MB 造数：随单元测试档零留存消失，不另处置。

**读数刷新（评审后复跑）**：`resource-link.mjs` = 171 行（注释折行 +1；前记 170 作废）· `npm run lint` = 128 files OK · `npm test` = 8/8 pass。

**审计 / 评审轮次终态**：explore 审计轮 1 = divergent（findings 已全部落账：§5 补写、两条文档漂移、空正文边界、临时文件）→ 自修后复审无新增；advisor code 轮 1 = pass（3 🟡 均已有落点：测试档上抛、anthropic 另批、槽体量补披露）。终态 = **clean**（无 🔴、无 must-fix）。

**归属澄清（并行两轮共写本段）**：本节中「交付摘要（CLI 半）」「决策透明表」「读数」「与设计的偏差 / 披露」「未改项」与「代码评审轮 1（advisor code）」「读数刷新」「审计 / 评审轮次终态」三块 = **CLI 半**（thincoder 仓 out-of-repo 轮，eng-coder）；「本波交付（F19 / F20 桌面半）」起的块 = **桌面半**（另一实现者）。两半并行追加、append-only 互不覆盖；§5 状态行 = 两半共同状态。

**修正轮（T95「30 MB/回合合计」变体；未实施，上抛待裁）**

- 任务书输入形与代码矛盾：两图各 ≤ 15 MB（`thincoder_kernel.dart:993` `imageMaxBytes`）⇒ 合计 ≤ 30 MB；回合合计判据 = `bytes > budget`（`:1065`，严格大于）⇒ 第二张永不因回合合计被弃。15 + 15 恰等于 30（2026-10-19 实测代码，非推测）。
- 能触发合计分支的最少图数 = 3：如 15 MB + 15 MB + 1 字节（第三张因余额 0 被弃）或 15 MB + 14 MB + 2 MB（第三张因余额 1 MB 被弃）；均 = 一条 `NoticeItem(warning)`、丢弃计数 1。
- 已发 ask（`notify_parent`）请裁输入形（候选 A = `[15 MB, 15 MB, 1 字节]`、候选 B = `[15 MB, 14 MB, 2 MB]`）；答复到达后落一条用例（T95 合计变体）+ 全文件绿 + analyze 读数。
- 本波零代码 / 零测试改动；本条为过程记录（未动 T93–T98 既有断言、设计 / 需求档）。

**修正轮落地（T95②「30 MB/回合合计」变体；2026-10-19）**

- 父代理裁定（2026-10-19 02:2x 回复，要点逐字）：「按你的口径 **[15 MB, 14 MB, 2 MB]**……以你的证据为准。不改生产常量、不引入 base64 线上体量口径。断言按你的（前两张进块、第三张弃、计数 1）。」上条「未实施，上抛待裁」至此收口。
- 新增一条用例 `T95②: pictures over the turn budget are dropped, the rest go native`（`test/kernel/thincoder_kernel_test.dart:1562`–`:1614`，53 行）：`ThincoderMock(promptImage: true)`；图 = png 15,000,000 + gif 14,000,000 + webp 2,000,000 ⇒ `session/prompt` = 1 text 块 + 2 image 块（mimeType 序 png / gif）；`NoticeItem(warning)` 恰一条（`1 image(s) went unsent…`，文案同 T95①）；`UserMessageItem.images` 2；`.thincoder/tmp` 不存在（原生路不落盘）。
- 分支归属：15,000,000 恰等于单图阈被放行（`bytes > imageMaxBytes` 不触发），余额 15,000,000；14,000,000 放行，余额 1,000,000；2,000,000 只可能被 `bytes > budget` 弃（`thincoder_kernel.dart:1061`–`:1069`）⇒ 真打「回合合计」分支（删掉该判据 ⇒ prompt 长度 4，用例红）。
- 读数（本机 2026-10-19，命令用本机 SDK `C:\Users\\xinbo\repos\flutter\bin\flutter.bat`）：
  - `flutter test --no-pub test/kernel/thincoder_kernel_test.dart` ⇒ **114 例全绿**（含 T93–T98 + T95②）。
  - `flutter analyze --no-pub test/kernel/thincoder_kernel_test.dart` ⇒ **No issues found**；全仓 `flutter analyze --no-pub` = 27 条，均为他批在飞改动（`lib/ide/git/git_autofetch.dart` 等）与既有存量，本档零命中。
  - `git status`：本波触碰 = 测试档（+ 本档 §5）；`pubspec.lock` 零改动（`--no-pub`）。
  - `wc -l`：`thincoder_kernel_test.dart` = **3644**（前记 3590，+54 = 1 空行 + 53 行用例）。
- 体量对照（父侧待办）：前记上界「≤3595（+200）」被本用例超出（3644，超 49）——设计 §22.6 已把 T95② 列为本批用例，属上界估算未含此用例；请按设计 > 记录刷新 `docs/design/thincoder-adapter.md` §22.3 ② 与本节预算对照两处读数（本段 append-only，旧表不回改）。
- 审计 / 评审：
  - 内部 explore 偏差审计（read-only）：1 轮，结论 DEVIATIONS——唯一 🔴 = §5 缺本轮实施记录（本段即补）；其余观察 = 设计档 `:2705` 的「合计 33 MB」算术应为 31 MB（15+14+2）、测试档体量越前记上界、审计无执行面故读数标 `unverified`。代码/断言面判「真覆盖合计分支、未误改既有用例、无任务书外改动」。
  - advisor code 评审：1 轮，verdict = **pass**（0 🔴 · 2 🟡 协调项 · 3 🔵）。🟡 = 测试档体量越前记上界（父侧刷新）、§5 记录滞后（本段补齐）；🔵 = 设计档 33 MB 数值漂移（设计面）、造数后两张用裸数字（可读性）、可选补载荷长度断言。按报告面登记，无 must-fix。
  - 终态 = **clean**（0 🔴 / 0 must-fix）。
- 未改项：生产代码（限额常量 / `_nativePrompt` / 既有 T93–T98 断言）· 设计档 · 需求档 · 其它测试档 · l10n。

## §6 验证与收口（父代理）

**验收读数**：F19 桌面半 114/114（T93–T98 + T95②）· CLI 半 8/8 + 真机 ACP 冒烟能力位 `{"image":true,"audio":false,"embeddedContext":false}` · 移动后的 CLI 测试档 8/8 · `flutter analyze` 基线。

**机制面**：F19 两路（原生 image 块 / 回退今天形）+ 能力位回退判据（D85）；F20 回合 Σ `used` + 会话 Σ（**随聊天会话存活**，restart 不清）；B1 CLI 五档 + 契约档 / CHANGELOG 同拍；预算 kernel 1091 / events 807 / kernel_types 614（三档到顶，下一动先拆）。

**设计档**：2930 行（批 12 另 +190 → 3120）。

**台账**：#78（F19）/ #79（F20）→ 已核销；#85（anthropic image_url 未转 image 块）/ #86（窗残余输入）/ #87（槽文件剥离）→ 批 12 待设计；#88（anthropic tool 消息未转）/ #89（VSC saveLines 未对齐剥离）→ 归批。

**未闭合（诚实面）**：F19 真机「模型回答能引用图片内容」被 #85 挡住——不是本批缺陷，是本批第一次把图送到 provider 面前才暴露；批 12 修完 #85 后必须真机走查 S1，否则 F19 只能算「桌面 + CLI 送达」而非「模型看见」。

**状态**：已收口 2026-10-19。
