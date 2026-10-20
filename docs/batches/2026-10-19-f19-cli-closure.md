# 2026-10-19 · f19-cli-closure
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 02:30「好，你来安排即可」——对「#85 提为下一批」与「#87 槽剥离授权」的答复；#86 同仓同链并入。
> 台账 = #85（thincoder-adapter · 归批）。前情 = 批 11（F19 原生图片块 + F20 用量，2026-10-19 进行中；CLI 半已交，本批收口真机链）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**讨论（2026-10-19 02:30）** — 用户「好，你来安排即可」：把 F19 真机链收口的三笔并成一批。

- **#85（真机拦路虎）**：`thincoder-core/provider/anthropic.mjs:41-54` 原样下发消息，`image_url` parts 不转 Anthropic `image` 块（Claude 族 `multimodal:true` 不走剥除）⇒ F19「模型回答能引用图片内容」在 Claude 族真机被挡；既有 `read_image` 同病。未对真 API 实测（unverified）。
- **#87（体量代价）**：原生图随 `pushReal` 入历史，`saveSession` 的 `contextHistory` 未过滤 ⇒ base64 图随每回合 `save` 整写槽 JSON（≤30 MB/回合 ×4/3）。设计 §22.7-7 的「剥离（默认）」待落；`thincoder-cli/src/acp/session.mjs` 现载他批未提交改动，开工前对齐。
- **#86（窄窗残余）**：`thincoder-cli/src/acp/session.mjs:63-67` 窗退 idle 时残余输入只取 `.text`，窗内到达的图仍丢；主径已闭合。
- 范围仓 = `thincoder/`（B1 例外，用户 2026-10-19 01:37 已概准；本批为 F19 链收口，仍守「保持上游可合并」）。
- 台账 = #85 / #86 / #87（均已重锚到本批）。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（坐标残留清零）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖 · 批 12 = F19 CLI 收口）**

- #85（台账；需求锚 = F19「模型回答能引用图片内容」）：anthropic provider 把 `image_url` 转 Anthropic `image` 块——设计 §22.9。
- #87（台账；锚 = F19 §22.7-7 既定口径「剥离」）：槽文件机器线只丢图——设计 §22.10。
- #86（台账；锚 = F19 §22.7-4 残余口）：挂起窗 idle 残余输入取富对象——设计 §22.11。
- 不在本批：Anthropic tool 消息的 `tool_use` / `tool_result` 转换（U3，另批）· VSC 面自带 save 线对齐（U4，另批）· 需求档改动（主 agent 笔）· 桌面 `lib/**`（零改）。

**设计档落点**

- `docs/design/thincoder-adapter.md`（2930 → **3120 行**，+190；`wc -l` 实测）：
  - §22.9 真机 provider 面（image 块转换）· §22.10 槽文件剥离 · §22.11 挂起窗残余输入 · §22.12 受影响文件 / 行数预算 / 测试策略（T1 / T1b / T2 / T3 / T4 · S1–S3 · U1–U5）。
  - §22.7-4 / §22.7-7 改写为现状（删「实现待办 / 条件式缺口」旧措辞）；§22.7 标题去「本批不做」（不再是单批边界）。
  - 抬头分批补批 12；零变更记录条目（D8；既有存量不动）。

**机制设计（一句一条）**

- ①：`anthropic.mjs` 新增导出纯函数 `convertMessages`：data URL（png / jpg / jpeg / gif / webp）→ `{type:"image",source:{type:"base64",media_type,data}}`（`image/jpg` 归一 `image/jpeg`）；非 data / 白名单外 / 畸形 → 文本占位 + 一行 `logEvent("llm:image-drop")`（**写死丢弃**）；copy-on-write；`rate.mjs` 的 `estimateText` 同步计 `type:"image"`（转换先于限流估算，不补则图从估算里消失）。`read_image` 同源（工具结果注入的是同一 user 消息 parts，工具面零改）。
- ②：`session.mjs` 新增导出纯函数 `stripImagesForArchive`（只丢 `image_url` part、保 text 与 `[Image #N]`；丢空 → 单 text 占位；copy-on-write），挂 `saveSession` 的 `contextHistory` 生成点（CLI / 桌面 / TUI 同一入口）。
- ③：`thincoder-cli/src/acp/session.mjs` 新增导出纯函数 `residualTurnInput`；idle 残余循环用它——有图 ⇒ `{text, images}`，纯文字 ⇒ 字符串，两者皆无 ⇒ null（今天形：不补发、不应答）。

**受影响文件与测试覆盖**

| 面 | 文件（当前行数 = 2026-10-19 `wc -l`） | 增量 |
|---|---|---|
| ① | `thincoder-core/provider/anthropic.mjs`（239） | ≤ +36（⇒ ≤275） |
| ①' | `thincoder-core/provider/rate.mjs`（168） | 1 行改（净增 0） |
| ② | `thincoder-core/session.mjs`（275） | ≤ +16（⇒ ≤291） |
| ③ | `thincoder-cli/src/acp/session.mjs`（180；载他批未提交改动） | ≤ +12（⇒ ≤192） |
| 测试 | `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`（新增） | ~+150（零留存、不进任何门） |
| 文档同拍 | 核 PROVIDER 设计档 §6.8 · `thincoder-core/CHANGELOG` / `thincoder-cli/CHANGELOG` 的 `[Unreleased]` | 文档面 |

- 四档均 <500 行，无拆分议题；零改动：`session-store.mjs` · `session-segments.mjs` · `normalize.mjs` · `google.mjs` · `responses-request.mjs` · `suspension.mjs` · `agent/setup.mjs` · `agent/record-results.mjs` · `agent/image-heal.mjs` · baocode `lib/**`。
- **开工前对齐（③ 必做）**：`thincoder-cli/src/acp/session.mjs` 现载他批未提交改动（`git status` = ` M`）——开工前存 `git diff` 基线、只改 idle 残余支（现 `:62-68`）与文件头新增函数、写后逐 hunk 核对 = 基线 + 本批；不 checkout / 不整档格式化。`thincoder-core/session.mjs` 现干净。
- 测试策略：单元测试档 = `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`，跑法 `cd thincoder && node --test docs/batches/2026-10-19-f19-cli-closure.test.mjs`，收口删除；`npm test`（`test/run.mjs`）只收 `test/**` ⇒ 本档不进、读数保持「空清单 = 绿」；集成测试无业务场景变更 ⇒ 不新增、不修既有无；T3 用既有测试缝 `_setSessionsDirForTest` / `_resetSessionsDirForTest`。

**验收对照（任务条目 → 设计落点 → 判据）**

- ① F19「模型回答能引用图片内容」（Claude 族）→ §22.9 → T1（纯函数逐值：png / jpg 别名 / 坏源占位 / 无图引用不变）+ T1b（假 SSE 服务器抓 `POST /v1/messages` body：image 块逐值、body 无 `image_url`）+ S1 真机（首轮无工具提问）。
- ② F19 存档口径（剥离）→ §22.10 → T2（纯函数：只丢图、text 与 `[Image #N]` 在、只含图 ⇒ 占位）+ T3（`saveSession` 写槽：槽 JSON 无 `image_url` / `data:image/`，`agent.history` 原引用仍含图）+ S2（槽文件字节数与无图回合同量级）。
- ③ F19 挂起窗图不丢（残余口）→ §22.11 → T4（映射逐形）+ S3（窗退 idle 补发回合含 image 块）。
- 三方一致链：批 12 §2 条目 = 设计 §22.9–§22.12 判据 = 台账 #85 / #86 / #87（需求锚 F19；② / ③ 为设计派生，无新增需求条目）。

**关键决策**：D91 转换点住 transport（不进 `normalize.mjs` 共用层）· D92 不可转换 ⇒ 丢弃换占位 + 一行日志（不保留原样——保留 = 整单 400）· D93 剥离住核 `saveSession` 生成点（单入口，CLI / 桌面 / TUI 同享）· D94 残余按富对象透传（不丢图）。含被否项见设计 §22.9–§22.11 决策表。

**上抛项**

- [上抛·待裁] U3 预存在缺陷：`format:"anthropic"` 的 transport 不转换 tool 消息（`role:"tool"` / `tool_calls` 原样下发），与核 PROVIDER 设计档 §6.8「tool 用 `tool_use` / `tool_result` block」相抵（代码实读 `anthropic.mjs:41-49` + `core.mjs:143-151`；未对真 API 实测）。本批不修（只这三笔）；多轮工具会话在 Claude 族无保证 ⇒ 请裁定另立批。
- [上抛·待裁] U4 跨面差异：VSC 面自带 `saveLines` 仍把图写进机器线（`panel-session-write.mjs:83`）；本批不扩面（B1 只这三笔）⇒ 建议另批对齐到核 `stripImagesForArchive`（默认消除差异）。
- [上抛·知会] U5 需求档 F19 事实行尾「CLI 的 provider vision 支持待查（设计调查项）」已由批 11 / 本批回答——需求档主 agent 笔，本批不改。
- [上抛·知会] U1 / U2：块形 = 官方 SDK 类型定义逐字（2026-10-19 经 unpkg 取）；Anthropic 真 API 未实测、单图字节 / 像素上限未取到一手来源（文档站 region-blocked）——判据 = S1；超限走既有 §6.26 自愈。

**零代码确认**：本轮只写设计档（`docs/design/thincoder-adapter.md`）与本批档 §2；`thincoder/` 仓、需求档、批 11 档、`docs/design/ide-git.md` 零改动。设计档新增块行宽 ≤300 实测 0 超标；`doc_check` 命中数与动手前一致（46 条，无新增）。

**订正（设计档自我核对后；零代码）**

- 上抛 U2 行「既有 §6.26 自愈」的 §6.26 指核 PROVIDER 设计档（image-heal 一节），非本设计档节号——设计档已改写为「核 PROVIDER 设计档 §6.26」；本节文字不回改（append-only），以此条为准。
- 设计档读数复测（2026-10-19）：`docs/design/thincoder-adapter.md` = **3120 行**（`wc -l` 口径，含末尾空行前计数）；新增块（§22.9–§22.12）行宽 >300 = **0**；`doc_check` 命中 **46 条 = 动手前基线**（锚 21 / 行宽 25，无新增）。

**修正轮 1（设计评审 #1–#12 落地；零代码；2026-10-19）**

号 → 改动（`docs/design/thincoder-adapter.md`，行号 = 本轮写后 `wc -l` 口径）：

- #1 → `:2909-2910`（§22.12 首段补 B1 依据：引用户 2026-10-19 01:37 裁定 + 本批 core 3 档 / CLI 1 档 + 需求档 F19「依赖」行现行口径）。
- #2 → `:2953`（U5 现状行改引需求档现行原文；处置改「已闭合、本批不需再动需求档」，判据 = §22.9 的 T1 / T1b + S1）。
- #3 → `:2696`（§22.5「模型回答能引用图片内容」行补 §22.9，判据 = T1 / T1b + 走查 S1）· `:388`（§7 的 F19 行补「真机 provider 面 = §22.9」与判据）。
- #4 → `:2805-2806`（§22.10 survey 证据：`SESSION.md` / `ACP-CLIENT.md` §6.3 / `API-CONTRACT.md:1815` + 结论）· `:2853-2854`（§22.11 survey 证据：`ACP-CLIENT.md` §12.8 无 idle 残余补发措辞 · `AGENT-LOOP.md:78` / `:92`；结论 = 以代码实读为准）。
- #5 → `:2742`（§22.9 对齐 ① 补「核 PROVIDER 设计档 §6.8」，三坐标齐全）。
- #6 → `:2782`（验收行改 copy-on-write 两半边）· `:2789`（T1 期望补：返回数组 ≠ 入参数组 ∧ 入参数组与 `agent.history` 引用 / 内容均不变）。
- #7 → `:2929`（UI 行改「无新增 UI 面；有模型面行为变更」）· `:2938` / `:2943`（走查表头改 S1–S4，新增 S4 终端侧对照：`read_image` 回合成功 + 限额命中核 PROVIDER 设计档 §6.26 自愈）。
- #8 → 五处全局指针：`:310`（§5.2 尾）· `:445`（§9，含离线测试档与零留存口径）· `:459`（§10）· `:493`（§12-A-4 存档线形）· `:3152-3154`（变更记录一条）。
- #9 → `:2858-2870`（§22.11 贴今天形 `session.mjs:62-68` 循环 + 空条目行为一句：`text === ""` ⇒ `if (text)` 假 ⇒ 不补发、不应答）。
- #10 → `:2831-2832`（T3 前写明 `contextHistory` = 机器线单入口、`history` = 人读线两路（绑定态段投影 / 未绑定 `legacyHistory`），两路源头已剥图）。
- #11 → 行号统一为一组 `:96-101` / `:154-170`：`:2616`（§22 survey 行，并同步其括注为「窗内轮透传富对象——批 11 ⑤ 已落」）· `:2659`（§22.2 表 ⑤ 行）；`:2717` / `:2845` / `:2849` / `:2854` 本已同组。
- #12 → `:2789`（T1 输入写全 data URL 字面：`data:image/png;base64,AAAA` / `data:image/jpg;base64,AAAA`）。

**读数（写后实测）**：设计档 **3155 行**（`wc -l` 口径；轮前 3119 ⇒ +36）。`doc_check`（`D:\baocode`）= **47 条（锚 21 / 行宽 26）**；锚数 = 基线（21），本轮新增指针全部可解析（含外仓档 `thincoder/docs/**`）；行宽：本轮新增行最长 250 字符（无一 >300），设计档 9 条宽命中全在 §22 之外（§17 / §18 / §19 / 变更记录既有行）。

**表外发现（非阻塞；本轮不改）**

- 需求档 `docs/requirements/thincoder-adapter.md:132` 现 374 字符（>300）；该行含主 agent 本轮改写的「（批 12 的 #85 修）」——疑为本轮 `doc_check` 行宽 25 → 26 的落点（推定；需求档非本席笔）。
- 设计档 `:2613-2615`（§22 survey 证据）仍写「`client-caps.mjs` 现声明 `image:false`」「`handlers-session.mjs` 只调 `buildPromptText`」「`setup.mjs` 检索把 input 当串」；实读 `thincoder-cli/src/acp/client-caps.mjs:59-61` 已为 `image: true`（批 11 CLI 半已交）⇒ 这三处属存量过时陈述，不在 #1–#12 范围，未动。

**零代码确认**：本轮只改 `docs/design/thincoder-adapter.md` 与本批档 §2；`thincoder/` 仓、需求档、批 11 档、代码零改动。

**survey 现状订正（2026-10-19；零代码；回填本档表外发现第 2 条）**

号 → 改动（`docs/design/thincoder-adapter.md`，行号 = 本轮写后实测）：

1. → `:2613`（§22 survey 外仓行：`client-caps.mjs:59-61` 现声明 `promptCapabilities.image: true`；`handlers-session.mjs:374-395` 走 `buildPromptContent` ⇒ 有图 `session.run({text, images})`、无图单串——原「现声明 `image:false`」「只调 `buildPromptText` → 单串」为批 11 前实况）。
2. → `:2614`（`resource-link.mjs:144-171` = `buildPromptContent`：text = 首个合法 text 块 + resource_link 内联；images = 按数组序的合法 image 块、白名单 + 限额、畸形 ∥ 超阈弃 + 日志——原「image 块被忽略」同属批 11 前实况，一并订正，非表外发现列举的三处之一）。
3. → `:2615`（`setup.mjs:53-57` 富输入 `{text, images}`、检索只取 `input.text`；`:188-199` `pushReal` content = text part + `image_url` parts；原「检索把 input 当串」「content: input」为批 11 前实况）。
4. → `:2617`（结论行：原「**原生图必须改 CLI**」与上三行现状相反 ⇒ 改「**原生图 = CLI 侧三层改动**（能力声明 + 内容构造 + 富输入透传）；批 11 CLI 半已落（§22.2 表 ①–⑤）」；桌面半句零改）。

- 未改：`:2612`（ACP schema 行）· `:2616`（`bridge.mjs` / `suspension.mjs` 行，批 11 ⑤ 已落 = 修正轮 1 #11 内容）· #1–#12 其余落点 · 代码 / 需求档 / 批 11 档。
- 读数（写后实测）：设计档 **3155 行**（写前 3155；4 行等长替换，净增 0）；新增行最长 **237 字符**（≤300）；`doc_check`（`D:\baocode`）= **46 条（锚 21 / 行宽 25）**——锚数与轮前基线同（21）；行宽 26 → 25 的差额来自需求档 `thincoder-adapter.md:132` 已被改写为 229 字符（轮前表外发现第 1 条，主 agent 笔），非本轮改动、本轮新增行零宽命中。
- 零代码确认：本轮只改 `docs/design/thincoder-adapter.md` 与本批档 §2；`thincoder/` 仓、需求档、批 11 档零改动。

**实现坐标回灌（2026-10-19；零代码；#44 交付后小修）**

号 → 改动（`docs/design/thincoder-adapter.md`，行号 = 本轮写后实测；代码坐标 = `thincoder/` 工作区实读）

- 漂移 1（`saveSession` 机器线生成点 `:126` → `:142`）→ `:2808`（§22.10 做法）· `:2831`（T3 两键来源）· `:2918`（§22.12 文件表 ②）· `:2721`（§22.7-7）——同一坐标四处一并改正；实读 = `thincoder-core/session.mjs:142` `const contextHistory = stripImagesForArchive(...)`。
- 漂移 2（进槽 / 两键来源 `:183-184` / `:184` → `:199-200` / `:200`）→ `:2832`（T3 两键来源，`session.mjs:64-69` / `:200`）· `:2721`（§22.7-7 进槽 `:199-200`）；实读 = `:199` `saveProjectedSlot(...)` / `:200` `writeSessionFile(p, { history: legacyHistory(agent), contextHistory })`。
- 漂移 3（§22.11 今天形 `session.mjs:62-68` → `thincoder-cli/src/acp/session.mjs:72-78`）→ `:2858`（今天形块头）· `:2854`（survey 结论）· `:2919` / `:2926`（§22.12 文件表 ③ / 开工前对齐步骤 2）；实读 = `:72-78` 的 idle 残余 `else` 支。
- 判据缺行（空串 ⇒ `null`；代码 `thincoder-cli/src/acp/session.mjs:38` = `item || null`，测试已锁）→ `:2881`（映射行补「空串 ⇒ `null`——同空残余项」；字符串支与只有 text 支各一处）· `:2903`（T4 输入加 `""`、期望加 `null`，与 `:2896`「空残余项保持今天」同口径）。

**读数（写后实测）**

- 设计档 **3155 行**（`wc -l` 口径；改前 3155，本轮零增行 = 11 处行内替换）。
- 本轮改动行最长 **273 字符**（`:2854`，≤300）；`doc_check(D:\baocode)` = **46 条（锚 21 / 行宽 25）= 动手前基线**，无新增命中。
- 代码实读：`thincoder-core/session.mjs:142` · `:199` / `:200` · `thincoder-cli/src/acp/session.mjs:72-78` · `:38`。

**未改（本轮四处之外的同一漂移其余落点；逐条列，待裁）**

- `:2796` / `:2720`：`thincoder-cli/src/acp/session.mjs:101` 每回合 `save` 实为 **`:111`**（本批 +10 行所致）。
- `:2802` / `:2806`：`session.mjs:118-125` / `:118-131` 实为 **`:134-141` / `:134-147`**（核档 +16 行所致）。
- `:2717` / `:2845`：「原 / 仍只取 `.text`（`session.mjs:63-67`）」——旧行号已死；直接改号会把「原 / 仍」句改假，需措辞裁定（建议收口时按现状重写或删旧形）。
- `:2858` 下方贴的「今天形」块体 = 改前形；现 `:72-78` 已是改后形（`residualTurnInput` 调用）——坐标按派单改正，块体与坐标的对照建议收口时按 D8 收成单一现状形。
- `:831`（§3.6 重放面）`thincoder-core/session.mjs:184` 实为 **`:200`**（同 +16 漂移；批 1 区）。
- `:1112`（§6 区）`acp/session.mjs:44` `save(agent)` 在现档无对应（`:111` 才是 `save(agent)`；疑为本批前既有漂移）。
- [上抛·知会] `thincoder/` 工作区现 ` M` 两份 CHANGELOG（`thincoder-core` / `thincoder-cli`）——非本席改动（任务书归父侧笔），仅供收口核对。

**零代码确认**：本轮只改 `docs/design/thincoder-adapter.md` 与本批档 §2；`thincoder/` 仓、需求档、批 11 档、代码零改动（本席未向 `thincoder/` 写任何文件；其工作区 `M` 列表 = 批 12 及他批既有改动）。

**坐标残留清零（#48 未改项 6 处落地；零代码；2026-10-19）**

号 → 改动（`docs/design/thincoder-adapter.md`，行号 = 本轮写后实测；代码坐标 = `thincoder/` 工作区实读）：

1. → `:2720` · `:2796`（§22.7-7 / §22.10 回指）：`thincoder-cli/src/acp/session.mjs:101` → **`:111`**（每回合 `save`；实读 `:111` = `try { save(agent) } catch …`）。两处同改，全档该坐标只剩一个值。
2. → `:2802`（§22.10 偏离 ①）：恢复前缀缓存契约 `session.mjs:118-125` → **`:134-141`**（核档 +16 行漂移）。
3. → `:2806`（§22.10 survey 结论）：同仓代码实读 `session.mjs:118-131` → **`:134-147`**（同源 +16）。
4. → `:2717`（§22.7-4）：删「原只取 `.text`（`session.mjs:63-67`）」→ 「现按富对象补发（§22.11，批 12 已落）」——不依赖死行号，不留「原 / 仍」假陈述。
5. → `:2845`（§22.11 回指）：「**仍只取 `.text`（`session.mjs:63-67`）」→ 「现按富对象补发（本节 `residualTurnInput`，批 12 已落）」；保留「残余条目仍带 `images`」现状句。
6. → `:2856` / `:2858-2865`（§22.11 做法）：删「今天形」块体（改前循环 + 空条目行为说明）与「改后（本批）」标签——按 D8 收成单一现状形（现 `:72-78` 的 `else` 支代码块 + 一行空条目判据）；「做法」行改为直接指向现坐标。
7. → `:831`（§3.6 重放面）：`thincoder-core/session.mjs:184` → **`:200`**（实读 `:200` = `writeSessionFile(p, { history: legacyHistory(agent), contextHistory })`；同源 +16）。
8. → `:1112`（§17.1-② 桌面 → 终端）：`acp/session.mjs:44` → **`:111`**；同句第二坐标 `thincoder-core/session.mjs:139` → **`:155`**（实读 `:155` = `autoApprove: agent.autoApprove ?? false`；同源 +16）。

- **既有漂移订正**：`:1112` 的 `acp/session.mjs:44` 在现档无对应（实读 `:44` = 空行 / `residualTurnInput` 尾部；本批 +10 行也解释不了该偏差）——判为批前既有漂移，按现档实读改正；同句 `:139` → `:155` 属核档 +16 漂移，一并订正。基线副本已随 `.thincoder/tmp` 清理，无法回溯旧档版本（按现档实读为准）。
- 未改（范围外）：§22.11 映射行 `:2867` 的「保持今天」、验收行 `:2882` 同措辞；变更记录 `:3139` 仍记「贴今天形循环」（历史段，既有存量不动）。
- 读数（写后实测）：设计档 **3141 行**（改前 3155；删「今天形」块净 −14）。改动行最长 **267 字符**（`:831`，≤300）。`doc_check(D:\baocode)` = **46 条（锚 21 / 行宽 25）= 动手前基线**，无新增命中。旧坐标串全档命中 = 0（`acp/session.mjs:101` / `session.mjs:184` / `:118-125` / `:118-131` / `:63-67` / `acp/session.mjs:44` / `session.mjs:139`）。
- 零代码确认：本轮只改 `docs/design/thincoder-adapter.md` 与本批档 §2；`thincoder/` 仓、需求档、批 11 档、代码零改动。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（批 12 F19 CLI 收口 §22.9–§22.12）

评审对象：`docs/design/thincoder-adapter.md`（批 12 段 §22.9–§22.12）+ `docs/requirements/thincoder-adapter.md`（F19 / B1 例外）。无 AGENTS.md、无项目标准档、无文档地图 ⇒ 方法与文档归属按评审准则 + 本档自身惯例判定（已在报告中声明）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Requirements | 🟡 | B1 例外面与需求档记录不一致：§22.9/§22.10 改的是 `thincoder-core/**`（design:2885 `thincoder-core/provider/anthropic.mjs`（239）· design:2887 `thincoder-core/session.mjs`（275）），需求档把 F19 的 B1 例外面记成「CLI 侧 5 档 ≈ +70 行，out-of-repo 轮，保持上游可合并」（requirements:135）；§22.9–§22.12 无一处声明 core 侧改动的 B1 依据 | §22.12 文件表上方补 B1 依据行（引 2026-10-19 01:37 裁定 + 本批 core 3 档），并把需求档 B1 例外面扩面（5 档 → 5+4 档）写成同拍待办 |
| 2 | Requirements / doc-state | 🟡 | U5 引用的需求档文字已不存在：design:2921 记「需求档 F19 事实行尾「CLI 的 provider vision 支持待查（设计调查项）」」，需求档该行现为「CLI 的 provider vision = `anthropic.mjs` 的 `image_url` 未转 image 块（批 12 的 #85 修）」（requirements:132）；U5 的现状与处置建立在过时读法上 | U5 现状行改引需求档现行原文，处置改为「已闭合、不需再动需求档」 |
| 3 | Acceptance criteria | 🟡 | F19 验收链缺 §22.9：design:2693「| 模型回答能引用图片内容 | §22.1（CLI 半） |」仍落在 §22.1 / 走查 2，而该条在 Anthropic 族实际由本批 §22.9 兑现；§7 的 F19 行（design:388「F19 原生图片块（批 11） \| §22（验收对照 = §22.5 · 用例 = §22.6）」）同样只指 §22.5/§22.6 | §22.5 该行与 §7 的 F19 行各加 §22.9 指向（判据 = T1/T1b + S1），让「模型能看图」有唯一落点 |
| 4 | Methodology / survey | 🟡 | §22.10 与 §22.11 无 survey 证据行：§22.9 有完整块（design:2744「**survey 证据**：Anthropic 官方 TypeScript SDK 类型定义」），§22.10 直入做法（design:2802「**做法**：`thincoder-core/session.mjs` 新增导出纯函数」）、§22.11 同（design:2844），两节都建立了对核/CLI 内部行为的断言 | 两节各补一行 survey 证据（查过的档 / 坐标 ∥ 是否相关内容；无则明写「无外部档，仅代码实读」） |
| 5 | Precedent coordinates | 🔵 | §22.9 先例行只给实现坐标（design:2739「同 `provider/google.mjs:53-61`（…）与 `provider/responses-request.mjs:100-104`（→ `input_image`）」），未给对位设计档节；该档名到 §22.12 ⑤ 才出现（design:2890「核的 PROVIDER 设计档 §6.8」） | 先例行补「核 PROVIDER 设计档 §6.8」，三坐标齐全 |
| 6 | Acceptance criteria | 🟡 | copy-on-write 的「有图」半边无判据：做法声明「有 ⇒ 只重建涉及对象（`agent.history` 零触）」（design:2755），验收只覆盖无图半边（design:2779「| 无图请求零改（引用级 copy-on-write） | T1 |」），T1 期望也只有「无图数组 === 原引用」（design:2786） | T1 加一条断言：带图转换后入参数组 / `agent.history` 原引用与内容不变，只有返回的新数组含 image 块 |
| 7 | Scope / impact accuracy | 🟡 | §22.12 影响面判词偏窄：design:2898「三笔均无用户可见交互变更（桌面零改；CLI 日志面一行）」与本节实际影响不符——§22.9 使终端 Claude 族图从「到不了模型」变为「真发出 image 块」（同一 chat 路径，三端共享）；§22.10 使重开会话后模型见占位文本（design:2808「恢复语义：重开 / 恢复后不再持有旧图（模型见占位文本）」） | 该行改「无新增 UI 面；有模型面行为变更」，走查补一条终端侧观察（终端 Claude 族贴图 / `read_image` 回合是否成功） |
| 8 | Methodology / cross-index | 🟡 | 批 12 未按本档惯例挂全局指针：§5.2 尾止于「批 11 见 §22.3 / §23.3（F19 桌面半 + F20；B1 例外面 = §22.2 表）」（design:310）、§9 止于「图片与用量面（批 11）：§22.6 / §23.6 的 T93–T98 入」（design:444）、§10 止于「图片面（F19）= 批 11 设计已定（§22）」（design:456）、§12-A-4 止于「批 11 起的线形」（design:491）、变更记录末尾为「2026-10-17 · 批 8 实现期修正轮 7」（design:3119）；批 12 测试档在 `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`（design:2902），只读 §9 的读者找不到 | 按批 4–11 同形补 5 处指针（§5.2 尾 · §9 一条含离线测试档与零留存口径 · §10 一条 · §12-A-4 一条存档线形 · 变更记录一条） |
| 9 | Clarity | 🔵 | §22.11 的「保持今天」缺代码坐标：design:2853「两者皆无 ⇒ `null`（保持今天：不补发、不应答）」断言现行循环对空条目的行为，而本节现行坐标只描述「只取 `.text`」（design:2836「`session.mjs:63-67`」）；若今天对 `{text:""}` 也调 `runNormal`，`null` 支即调度变更，与 design:2841「只改入参形，不改调度」相抵 | 节内贴出现行 `:62-68` 循环或一句话写明它对空条目今天的行为 |
| 10 | Clarity | 🔵 | T3 的 `history` 断言来源未写明：期望「槽文件 `contextHistory` / `history` 均不含 `image_url` / `data:image/`」（design:2830），改动只定义在机器线生成点（design:2802「`saveSession` 的机器线生成点（现 `:126`）改用」）；`history` 键由哪条线产出只能从 design:2807「人读线零改（源头已剥）」推出 | T3 前写明两键来源（机器线单入口 / 人读线 `slimForDisplay` 已剥） |
| 11 | Numeric drift | 🔵 | 同一处批 11 改动两套行号：design:2656「`thincoder-cli/src/acp/suspension.mjs:96-109` / `:150-154`」vs design:2714「批 11 ⑤ 已落：`suspension.mjs:96-101` / `:154-170`」（§22.11 同，design:2836） | 统一为一组编制日实读坐标 |
| 12 | Clarity | 🔵 | T1 输入与期望不对齐：输入只写「含 `text` + `data:image/png` 的 user 消息」（design:2786），期望逐字给 `data:"AAAA"`，输入未写 payload | T1 输入写明 data URL 原文（如 `data:image/png;base64,AAAA`），或期望不写具体 payload |

计数：🔴 0 · 🟡 7 · 🔵 5（共 12 条）。无 🔴 ⇒ 不阻塞开工。

VERDICT: pass

## §4 用户批准（主 agent）

**用户批准（2026-10-19 02:45）**：逐字「批准」——批 12（F19 CLI 收口）设计批准；实现三笔：provider `image_url`→`image` 块 · 存档剥离 · 窗残余输入；范围仓 `thincoder/`（B1 同裁）。

## §5 实施记录（eng-coder）
**状态行**：实施完成（审计轮 1 pass · 评审轮 1 changes-required → 自修轮 1 落地 → 轮 2 pass · 终态 clean）



**实施记录（批 12 · F19 CLI 收口；eng-coder）**

**范围与读数（2026-10-19）**

| 笔 | 文件 | 改动 | 行数（`wc -l`） |
|---|---|---|---|
| ① | `thincoder-core/provider/anthropic.mjs` | `convertMessages`（data URL → `{type:"image",source:{type:"base64",media_type,data}}`；`image/jpg` 归一 `image/jpeg`；非 data / 白名单外 / 空 payload / 形状不符 ⇒ 原位文本占位 + 每次调用一行 `llm:image-drop{transport,count}`；copy-on-write）+ `chat()` 以它生成 `body.messages`（`anthropic.mjs:90`） | 239 → **275**（+36，恰在预算） |
| ①' | `thincoder-core/provider/rate.mjs` | `estimateText` 的 part 判据补 `type:"image"`（同计 85）——`rate.mjs:55` | 168 → **168**（1 行替换，净增 0） |
| ② | `thincoder-core/session.mjs` | 导出 `IMAGES_STRIPPED_PLACEHOLDER`（`session.mjs:72`）+ `stripImagesForArchive`（`:75-86`：只丢 `image_url`，text / `[Image #N]` 与其余 part 原样，丢空 ⇒ 单 text 占位，copy-on-write）；`saveSession` 机器线生成点改用它（`:142`） | 275 → **291**（+16，恰在预算） |
| ③ | `thincoder-cli/src/acp/session.mjs` | 导出 `residualTurnInput`（`:37-43`）；idle 残余循环改用它（`:74-77`）——字符串 ⇒ 原串（空串同空残余项）、带图 ⇒ `{text,images}`（text 空也发）、只有 text ⇒ 该串、皆无 ⇒ `null`（不补发 / 不应答）；中止径与调度零改 | 180 → **190**（+10；他批基线零改） |
| ⑤ | `docs/core/design/PROVIDER.md` §6.8 | Anthropic 事实行补 image 块转换 + 丢弃占位 / `llm:image-drop` / 限流 85（`:148`） | +1 行 |

- 测试档（新增，该仓惯例：随批次档、零留存、不进 `npm test`）：`docs/batches/2026-10-19-f19-cli-closure.test.mjs`（201 行）——T1 / T1b / T2 / T3 / T4。
- 零改动（实核）：`session-store.mjs` · `session-segments.mjs` · `normalize.mjs` · `google.mjs` · `responses-request.mjs` · `suspension.mjs` · `agent/setup.mjs` · `agent/record-results.mjs` · `agent/image-heal.mjs` · `thincoder-vscode/**` · baocode `lib/**` · 两份 CHANGELOG（父侧面）· 设计 / 需求档。

**③ 开工前对齐（基线记录）**

1. 开工前 `git diff -- thincoder-cli/src/acp/session.mjs` 存基线：**8 hunk**（`:7` 头注 / `:24` import / `:38` `_bgObserver` / `:47` 中止径 / `:66` signal / `:79` save-closed / `:109` busy 顺序 / `:128` run+cancel）；基线副本 `.thincoder/tmp/session.baseline.mjs`（9403 字节，与开工前档逐字节相同；`.gitignore:20-21` 覆盖 `.thincoder/tmp*`，不入库）。
2. 只改 idle 残余支 + 文件头新增函数；未 checkout / 未整档格式化。
3. 写后 `git diff --no-index <基线副本> <现档>` = **仅 2 处本批改动**：`residualTurnInput` + 注释（10 行）与 `:74-77` 两行替换；基线 8 hunk 原样保留（现档 `git diff` 仍为 8 hunk——本批两处因邻近被并入基线 hunk 2 / 4，无新增 hunk）。

**测试与检查读数**

- `cd thincoder && node --test docs/batches/2026-10-19-f19-cli-closure.test.mjs` ⇒ **tests 5 / pass 5 / fail 0**（T1、T1b、T2、T3、T4 全绿）。
- `node --check`：`anthropic.mjs` / `rate.mjs` / `session.mjs` / `acp/session.mjs` / 测试档 全 OK；`thincoder-cli && node scripts/check-syntax.mjs` ⇒ `127 file(s) OK`。
- 既有测试：`thincoder-core && npm test` / `thincoder-cli && npm test` ⇒ 均为「test manifest is empty — zero tests = green」（该仓现状，空集绿）。
- 文档面：`doc_check(D:\baocode\thincoder)` 行宽命中 **0**（597 条全为锚·存量报告项，本批零新增锚 / 零新增宽行）；PROVIDER.md 新行 300 字符（阈值 300，未超）。
- `git status --porcelain`（本批范围）：仅上列 4 代码档 + PROVIDER.md（`M`）与测试档（`??`）；thincoder 仓其余未提交改动 = 他批存量，本批未触。

**自查对照（设计 §22.9–§22.12 逐条）**

- ① T1 两半边：无图 ⇒ `convertMessages` 返回原数组引用；有图 ⇒ 新数组 / 只重建命中消息，text part 原引用，入参数组与内容零变（测试亦以 T1b 锁「chat 入参历史不被改写」）。T1b：假 SSE 服务抓 `POST /v1/messages`，`messages[0].content[1]` 逐值 = image 块，body 序列化无 `image_url`。S1 判据见下（真机未跑）。
- ② T2：只丢 `image_url`、text 与 `[Image #N]` 保序、只含图 ⇒ 单占位、无图消息 / 数组原引用；T3：`_setSessionsDirForTest` 临时目录 + `saveSession` ⇒ 槽 JSON `contextHistory` / `history` 均无 `image_url` / `data:image/`、`[Image #1]` 在场、`agent.history` 原引用仍含图。
- ③ T4 六形逐值 + 空串；循环只改入参形（字符串 / 有图 / 只有 text / 皆无），中止径与 `suspension.mjs` 零改。
- ①' `estimateText`：`image_url` 与 `image` 均 85（T1 内断言）。

**审计与代码评审轮次**

- **内部审计轮 1（explore，只读发散审计）**：VERDICT **pass**；无 PARTIAL / SILENT-SIMPLIFICATION / DOC-DRIFT / OUT-OF-LIST。面外记录：行数读数差（其读工具按「含末尾空行」计数得 session 292 / rate 169；`wc -l` 口径 = 291 / 168，与设计帽一致——本批以设计声明的 `wc -l` 为准）；§5 为空（即本段，已补）；`residualTurnInput("")` 边角（见下修正）；其装配无执行工具 ⇒ 测试由本会话实跑。
- **代码评审轮 1（advisor，独立）**：VERDICT **changes-required** —— 🟡×2 + 🔵×3：
  - 🟡（must-fix）两档 CHANGELOG `[Unreleased]` 条目未落（设计 §22.12 ⑤「同拍义务」）。**本批不写**：任务书明定 CHANGELOG = 父侧维护面；条目文本已随交付报告提交，由父侧落笔。
  - 🟡（协调项）§5 实施记录为空 / 走查与测试读数未记 —— 本段即修正；S1–S4 属父侧 §6 收口面（见下检查点）。
  - 🔵 `residualTurnInput("")` 返回 `""` ⇒ `input !== null` 下会补发空回合（今日 `if (text)` 不补发）——**自修轮 1 已改** `return item || null`（注释同步「空串同空残余项」）；活径本就不可达（`acp/suspension.mjs:159` 恒包 `{text, done}`），改后与「只改入参形、不改调度」严格一致。
  - 🔵 T1 未锁「空 payload / 带参数 data URL」两支 —— **自修轮 1 已补**两条输入（`data:image/png;base64,`、`data:image/png;charset=utf-8;base64,AA`）与 `residualTurnInput("")` 用例；复跑 5/5 全绿。
  - 🔵 设计档行号漂移（`saveSession`「现 `:126`」→ 实 `session.mjs:142`；两键来源 `:184` → `:200`；§22.11 今天形 `session.mjs:62-68` → 实 `acp/session.mjs:72-78`）——设计档非本席笔，随报告上抛，未改。
- **自修轮 1 后读数**：测试 5/5 全绿；`node --check` 全 OK；基线比对仍 = 2 处本批改动（基线 8 hunk 零变）。终态 = **clean**（唯一未闭环的 🟡 属父侧面：CHANGELOG 条目 + §6 收口）。

**决策透明表（本席所决）**

| 决定 | 理由 | 影响 / 替代 |
|---|---|---|
| 丢弃日志住 `convertMessages` 内（每次调用一行） | 设计 §22.9 原句「一次 `logEvent(…, {count})`（每请求至多一行）」；`chat()` 每请求恰调一次 | 纯函数名带一处 fire-and-forget 日志；T1 用既有 `_setLogsDirForTest` 缝取事件行，不新增测试缝 |
| `mediaType` 先算后验（`match?.[1]` 访问器） | 保持单行判据、避免二次写分支；无 match 时值为 undefined 且随即走占位支 | 与白名单检查同段，读一遍即懂 |
| `residualTurnInput` 字符串支用 `item || null` | 设计 §22.11 对齐②「只改入参形，不改调度」+「保持今天：不补发、不应答」在空串上交汇；空串在今日 `if (text)` 下不补发 | 与「字符串 ⇒ 原串」非空情形逐字一致；T4 加空串行锁死 |
| ② 常量与函数并排导出（`session.mjs:71-86`） | 常量只服务该函数；同段可读、与 `legacyHistory` 邻接 | 无循环依赖，`session.mjs` 既有 re-export 面不动 |

**偏差 / 未做（如实）**

- 代码零偏差：三笔均按设计逐条落地，无简化、无扩大。
- **真机走查 S1–S4 未跑**（本席无 CLI 真机 + Claude 族凭据；U1 明记未对真 API 实测）。收口检查点：
  - **S1（①）**：Claude 族（`format:"anthropic"`）+ 视觉模型，**首轮**发截图 +「这张图里是什么」⇒ 答出图中内容、不调 `read_image`（首轮避开 U3 工具消息面）。失败 ⇒ 按真实错误修形，不改判据。
  - **S2（②）**：同会话再发图 ⇒ 回合尾 `saveSession` 后槽 JSON 无 `data:image/`、`[Image #N]` 在、字节数与无图回合同量级；重开会话模型见占位文本、不崩。
  - **S3（③）**：挂起窗 live 时发带图 prompt 留在残余；窗退 idle ⇒ 补发回合 `pushReal` 入参 content 含 image 块。
  - **S4（终端对照）**：终端会话 `read_image <path>` ⇒ 回合成功、答出图中内容；日志 4xx 且带核 PROVIDER §6.26 全剥注记 ⇒ 命中限额自愈（二次失败 ⇒ 按 U2 另立缩放）。
- ⑤ 的另外两件（CHANGELOG 条目）按任务书归父侧；条目文本见交付报告。
- 表外观察（不在三笔，未动）：`slimForDisplay` 对「只含图」user 消息产出 `content: []`（`session-segments.mjs:37-39`），人读线恢复 / 展示可能出现空 user 气泡；设计 §22.10 明确划出人读线 ⇒ 仅上抛，未改。
- 设计档行号漂移（见评审 🔵 第 5 条）——设计档非本席笔，未改，随报告上抛。

**评审轮 2（fix 复核）**：VERDICT **pass**。

- 修复声明 1（`residualTurnInput` 空串支）——逐字核对通过：`acp/session.mjs:38` `if (typeof item === "string") return item || null`，注释同步（:35-36），调度点未动（:76 `if (input !== null) runNormal(input)…`）；活径不可达经独立实测确认（`acp/suspension.mjs:158-160` 残余项恒为 `{text, …, done}` 对象）。
- 修复声明 2（T1 空 payload / 带参数 data URL + T4 `""`）——逐字核对通过：`test.mjs:92-102` 两条输入 + `count === 2`，`test.mjs:200` `residualTurnInput("") === null`；与实装正则 `anthropic.mjs:44` 的判据一致，非空转断言。
- 外部项复核：① CHANGELOG（父侧笔）按具名理由 **Accepted**——收口前父侧须把两条写进 `[Unreleased]`（条目文本随交付报告）；② 设计档行号漂移 **Accepted**（他笔，随报告上抛）；③ 新增 🔵：自修轮引入的「空串 ⇒ null」未同步进设计档映射行（:2881）与 T4 行（:2903）——代码 / 测试比设计档多一条判据，意图与设计 :2896「空残余项保持今天」一致且活径不可达，归设计档笔主收口时补一行。
- **终态 = clean**：审计轮 1 pass · 评审轮 1 changes-required → 自修轮 1 落地 → 评审轮 2 pass；无未闭环的实现缺陷（未闭环项均属父侧 / 设计档笔主，已随交付报告上抛）。

## §6 验证与收口（父代理）

**验收读数（父侧复跑）**：`node --test docs/batches/2026-10-19-f19-cli-closure.test.mjs` ⇒ **tests 5 / pass 5 / fail 0**（T1 / T1b / T2 / T3 / T4）；`node --check` 四档 + 测试档全 OK；`thincoder-cli` 的 `check-syntax` 127 文件 OK；两仓 `npm test` 空集绿；`doc_check` 零新增。

**真机（用户 2026-10-19 19:43 确认）**：换稳定视觉模型后，「模型切换 + 发图识别」正常 ⇒ F19 端到端「模型看图」成立（此前的不稳 = deepseek-flash 模型级，非链路；台账 #96 已撤回）。Anthropic 实渠未验——`format:"anthropic"` 的 tool 消息转换缺口见台账 #88，另批处置。

**同拍义务**：`thincoder-core/CHANGELOG.md` `[Unreleased]` 已落 `### Fixed`（Anthropic 图块转换 + `llm:image-drop` + copy-on-write + 85 tokens）与 `### Changed`（存档剥图）；`thincoder-cli/CHANGELOG.md` `[Unreleased]` 已落 `### Fixed`（窗退 idle 残余保图）。

**零留存**：本批单测档 `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs` 已按设计删除（读数已记上文）。

**台账**：#85 / #86 / #87 由本批实现闭合；派生登记 #88（anthropic tool 消息）/ #89（VSC saveLines）/ #91（slimForDisplay 空气泡）均归批待处置。

**状态**：已收口 2026-10-19。
