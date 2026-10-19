# 2026-10-16 · Gitee 令牌接入（第三 forge）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-16 · 来源 = 用户 2026-10-16 裁定（令牌登录 · 功能面对齐 · 私有仓支持；需求档 forge-accounts.md）。
> 台账 = #13（forge-accounts · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-18


- **开批**（2026-10-16）：用户提出「设置里有 GitHub 令牌，还需要配 Gitee 令牌」；摸底确认账户页/forge 模块现为 `github` / `gitlab` 两家（令牌登录 + 浏览器/设备码登录；面 = me / 条目 / 列表 / 评论 / 关闭）。当日用户三点裁定：① 只做**令牌登录**（浏览器/设备码不做）② 功能面**对齐**两家 ③ **私有仓支持**（与两家同口径）。Gitee API 探针、端点来源核实在设计轮完成。
- **范围**：本仓新增第三个 forge kind（`gitee`）——`forge_ref` 主机/链接解析 · `GiteeApi`（API v5）· `forge_accounts` + `accounts_page`（令牌登录、令牌页、作用域文案、图标）。边界 = 需求档 B1–B3（无浏览器/设备码登录；无对应面不做；既有两家行为不动）。
- **需求落点**：需求档 `docs/requirements/forge-accounts.md`（板块首篇，五要素齐）。
- **共用面裁定**：`ForgeRef.number` `int`→`String`（Gitee issue 编号为字符串）——用户 2026-10-16 认可「该改就改」，评审重点核过（设计档 D1）。
- **前情**：无（独立批）。

## §2 批次任务与设计（eng-designer）
**状态行**：✅ 设计完成 2026-10-16（扩裁改文清单落档 —— §3.7 · 5 键；§8-B3 / §5 / R9 三处一致；既往轮次见下方各块）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖需求档 F1–F5；边界 B1–B3 全域沿用）**

| # | 条目（需求档） | 落点（设计档） | 判据（可验） |
|---|---|---|---|
| T1 | F1 令牌登录：账户页 Gitee 区块 + 令牌页 + 作用域文案 | §3.4 · §3.6 | 单元：`signInWithToken(gitee,…)` 打 `/api/v5/user`（G5）；走查：真实令牌登录成功、无效令牌明确报错 |
| T2 | F2 身份 | §3.1 端点 1 · §3.2 | 登录后显示 `login`（G5） |
| T3 | F3 协作面：条目详情 / issues 列表 / 评论 / 关闭 | §3.1 端点 2–7 · §3.2 · D4–D6 | 单元 G6–G12（请求路径与方法逐条断言）；checks 恒空（G14，B2） |
| T4 | F4 私有仓 | §3.6 作用域建议集 | 走查：私有仓 issue / PR 可读（R4 回填） |
| T5 | F5 链接与图标 | §3.3 · §3.4 图标行 | 解析用例 G1–G4；图标臂 16px 可辨（R7） |
| T6 | A4 零回退 | §4 D1 | 既有 github / gitlab 两 group 保持绿 |
| T7 | A5 真机走查 | §9 R1–R9 | 真实令牌走 A1–A3，回填未核实项 |

**设计档落点**：`docs/design/forge-accounts.md`（板块首篇，2026-10-16 首版，287 行）。

**机制设计（摘要；全文见设计档 §3–§4）**

1. `ForgeKind` 加 `gitee`（`label`/`publicHost`）· `publicForgeKind` 加 `gitee.com`/`www.gitee.com` · `ForgeRef.parse` 加 Gitee 臂（`/issues/{编号}`、`/pulls/{序号}`）· `/-/`（GitLab 形）臂的主机闸门收紧为「未识别或 gitlab」（设计档 §3.3）。
2. 新 `GiteeApi extends ForgeApi`：base `https://{host}/api/v5`，认证 `Authorization: Bearer`，面 = `me`/`item`/`issues`/`comment`/`close`；端点与字段逐条对位见设计档 §3.1–§3.2（来源 [D] 官方 OpenAPI / [O] 官方 OAuth / [M] 官方 MCP 客户端 / [P] 本批实测）。
3. 列表口径 = 未关闭：`state=open` + `state=progressing` 两请求合并取前 50（D4）；归属过滤用 `assignee=<login>`/`creator=<login>`（先 `me()` 取 login，D3）。
4. 账户页：主机行文案、令牌创建/撤销链接（私人令牌页）、作用域文案三处加 gitee 臂；令牌对话框复用不改；浏览器登录不显示（B1）。
5. **共用面一处改动**：`ForgeRef.number` 由 `int` 放宽为 `String`（Gitee issue 编号实测为字符串，如 `IKLL6H`），两家行为不变（D1）——评审重点。

**受影响文件与测试覆盖**：见设计档 §5（9 处既有文件 + `assets/branding/gitee.svg` 新资产 + l10n 生成物）。测试 = `test/forge/forge_test.dart` 新增 `group('GiteeApi')`（用例 G1–G14），命令 `flutter test test/forge/forge_test.dart`；`test/stash/*`、`test/l10n_test.dart` 不动且须保持绿。

**验收对照**：设计档 §6（A1–A5 逐条回指需求档 §5）。

**关键决策**：D1 编号类型放宽 · D2 链接形态 · D3 归属过滤 · D4 列表两次请求 · D5 关闭端点形态（命名空间级）· D6 无 checks 面 —— 含被拒备选，见设计档 §4。

**上抛项**

- **【知会】D1 触及共用面**：`ForgeRef.number` `int` → `String`（三家共用，两家行为不变；影响 `forge_ref.dart`、`forge_api.dart` 两处构造、既有测试字面量）。请评审重点核。
- **【待裁】R9**：账户页描述文案（现只提 GitHub 与 GitLab）是否随第三家更新 —— 依 B3「既有文案不动」本批**不改**；用户裁定后可一行补（设计档 §8 open 项）。
- **未核实清单 R1–R9**（设计档 §9）：其中 R1（关闭写路径无令牌不可实测）与 R2（`assignee` 过滤无令牌不可验）留 A5 首验；R3 认证后限流口径无官方明页。

### 修正轮 1（评审 10 项全 Accepted，主 agent 裁定 2026-10-16）

设计档 `docs/design/forge-accounts.md` 逐项落档（纯档面，零代码；设计档 287 → 302 行）：

| # | 裁定项 | 落点 |
|---|---|---|
| 1 | R9 收口：`accountsDescription` 补 Gitee | §3.4 表增行 · §3.4 l10n 段 · §5 l10n 行「+2 键 + 1 键改文」· §8 / §9 R9 改确定表述 |
| 2 | 500 行档拆包结论 | §5 体量与拆包：三件各给「保留 + 缝候选 + 触发」 |
| 3 | D3 失败路径 | §4 D3（仅 filter ≠ all 取 `me()`；失败传播至报错行）· §7 G9 · §6 A2 |
| 4 | D1 核查口径 | §4 D1：检索式 + 读点 / 构造点 / 断言读点清单 · §5 test 行计数改为逐点（共 6 处） |
| 5 | 资产声明方式 | §5 资产行（目录声明 ⇒ `pubspec.yaml` 无须改） |
| 6 | PR `comments` 恒 0 | §9 R10（A5 用有评论的 PR 复核）+ 第二条探针留痕 · §3.2 行注 |
| 7 | 端点 6 单来源 | §3.1 行 6 补 [M]（`operations/pulls/comment_pull.go` 佐证） |
| 8 | 先例三元组 | §2.2 首段（设计档 / 先例批次 = 无；旧记载 `docs/stash.md:141-142`） |
| 9 | 行号漂移 | 档首声明「行号各档自用、跨档不对齐」+ 档内图标臂取齐 `29-40` |
| 10 | `/-/` 闸门回归 | §7 +G15 · §3.3 / §6 A4 注 |

- 未新增语义：只按评审 Suggestion 列收口；用例 G1–G15（+G15）、未核实 R1–R10（+R10）。
- 上抛项 R9（上文「【待裁】R9」）已由用户 2026-10-16 裁定：账户页描述补 Gitee ⇒ 本表第 1 行落档，设计档不留待裁字样。

### 实施实测修正 1（2026-10-16，纯档面，零代码；父侧裁定）

- 实施实测：`test/forge/forge_test.dart` 899 行（Gitee 用例写实后 +381；实施中复读 927）⇒ 越 800 硬顶，上文自设触发（「触发 = 越 800 硬顶，缝候选 = 按 kind 拆」）成立 ⇒ 已拆包：既有用例（ForgeRef / GitHubApi / GitLabApi / ForgeAccounts）留 `test/forge/forge_test.dart`，Gitee 用例 G1–G15 落新档 `test/forge/forge_gitee_test.dart`。
- 验收命令同步（上文「受影响文件与测试覆盖」行与 A4 判据行）改为两档同跑：`flutter test test/forge/forge_test.dart test/forge/forge_gitee_test.dart`；设计档落点 = §5（文件行 / 测试覆盖 / 体量条）· §6 A4。
- 计数勘误：上文主块「用例 G1–G14」未随修正轮 1 同步，用例集 = G1–G15（+G15，见修正轮 1 与设计档 §7）。
- 留待随修：§5 其余行数与估值（`forge_api.dart` 等）待实施交付读数后另行随修，本轮只动 test 面。

### 实施交付读数随修（2026-10-16，纯档面，零代码；父侧裁定）

- 实测行数（交付读数 + 父侧复跑）—— 源码面：`lib/forge/forge_ref.dart` 271 · `lib/forge/forge_api.dart` 707 · `lib/forge/forge_accounts.dart` 450 · `lib/forge/forge_view.dart` 132 · `lib/settings/pages/accounts_page.dart` 503。
- 测试面：`test/forge/forge_test.dart` 475 · `test/forge/forge_gitee_test.dart` 452 · `test/forge/fake_forge_http.dart` 46（新，拆包抽出的共用 fake）。
- 清单外 import 连带（4 档各 1 行改指 `test/forge/fake_forge_http.dart`；拆包搬迁连带，Dart import 不传递）：`test/stash/stash_forge_test.dart` 182 · `test/stash/stash_forge_view_test.dart` 241 · `test/stash/stash_sidebar_test.dart` 224 · `test/settings/accounts_page_test.dart` 130。
- 验收读数：两档同跑 `flutter test test/forge/forge_test.dart test/forge/forge_gitee_test.dart` = **29/29 全绿**（父侧复跑）。
- 设计档落点 = `docs/design/forge-accounts.md` §5（文件表 / 测试覆盖 / 体量条）+ 变更记录；`forge_api.dart` 707 行 <800 且 >500 ⇒ 体量结论保持「保留 + 缝候选」形。

### 扩裁随修（用户 2026-10-16 19:22「补gitee」；纯档面，零代码）

设计档 `docs/design/forge-accounts.md` 落点：

- **§3.7 新增「用户可见文案（三家口径）改文清单」**（单一口径源）：5 键 = `accountsDescription`（R9 已落）+ 本轮 4 键 —— `accountsKeptLocally` · `stashImportNotALink` · `stashImportNoRepos` · `stashWelcomeTrack`；逐键给 en / zh 新文 + 落点（`app_en.arb` / `app_zh.arb` 行号 + 代码用点）。
- **§8-B3 口径改写**：行为不动；提及托管家数的用户可见文案随第三家更新（清单指 §3.7；两次裁定依据 = R9 + 「补gitee」扩裁）；原「账户页描述…唯一例外」条删除（内容并入 B3 与 §3.7，不留例外表述）。
- **§5 l10n 行**：各 +2 键 + **5 键改文**（清单见 §3.7：R9 已落 1 键 + 本轮 4 键）；`l10n` 生成物描述不变（`flutter gen-l10n` 重生成、不手改）。
- **R9 行**：裁定完成态（含本轮扩裁）；§8 / §5 / R9 三处口径与计数同源（5 键）。
- §1 边界行 · §3.4 表（`accountsKeptLocally` 行补入、描述行改指 §3.7）· §3.4 l10n 段 · §8 近邻键（同批不动）· 变更记录 +1 行。

**键数核对（实读两档 arb，`github|gitlab` 忽略大小写）**：导入对话框内只提两家的键 = 2（`stashImportNotALink` · `stashImportNoRepos`）；stash 面第 3 键 = `stashWelcomeTrack`（欢迎页「看清进展」卡，非对话框）；按纳入口径（用户可见 ∧ 现文只提两家 ∧ Gitee 链路已可用）三键皆入。`stashImportSignIn` 带 `{forge}` 参数（`kind.label`），三家自动成文，不改。

**本单判据**：改文清单逐键可核（键名 + en/zh 新文 + 落点 `file:line`）；§8 / §5 / R9 三处一致（5 键）；行宽 <300（实测最长 299，非本轮行）；零代码改动（本轮只改文档；`.arb` 与生成物由后续 coder 轮落）。

**发现项（未擅动，交主 agent）**：

1. 需求档 `docs/requirements/forge-accounts.md:44` B3 仍写「github / gitlab 链路与文案不动」——与本轮扩裁相抵；需求档笔在主 agent（需求档亦无文案面的 F / A 条目）。
2. `settingsAccountsKeywords`（`app_en.arb:6388` / `app_zh.arb:2408`）：设置搜索索引串，不含 Gitee ⇒ 搜索「Gitee」找不到「账号」节；非用户可见文案，未入清单，待裁是否补一词。
3. `lib/stash/stash_skill.dart:88` / `:98`：内置 skill 文本仍写 GitHub/GitLab（产品文本面、非 `.arb`），需另裁。
4. `docs/stash.md:140-142`：stash 板块档「支持 GitHub…和 GitLab」未含 Gitee（另一板块文档），需另裁。

### 发现项办结（2026-10-16，纯档面，零代码；用户已裁、实现已落）

- **发现项 2 办结**：`settingsAccountsKeywords`（`app_en.arb:6388` / `app_zh.arb:2408`）已裁定补「Gitee」一词并已落 —— 设置搜索「Gitee」命中「账号」节。设计档 `docs/design/forge-accounts.md` §3.7 补录为扩裁①；§8 边界句改「已裁定：补一词（见 §3.7 扩裁①）」。
- **发现项 3 办结**：`lib/stash/stash_skill.dart:88` / `:98` 枚举已补 Gitee（`GitHub/GitLab/Gitee` · `GitHub, GitLab or Gitee`）。设计档 §3.7 补录为扩裁②；§5 文件表补该行（117 行、文本替换）。
- **计数口径**：设计档 §3.7 / §5 / §8 三处一致 —— **5 键改文 + 2 项同源扩裁**；§3.4 l10n 段同步。
- 发现项 1 / 4 已由父侧另行处置（不属本单）：需求档 B3 已改（`docs/requirements/forge-accounts.md:44`）；`docs/stash.md` 板块档缺口入台账 #14。
- 本单判据：零代码改动；行宽 <300（新行机检均 <300）；设计档变更记录 +1 行。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

评审对象：docs/design/forge-accounts.md（Gitee 接入设计，板块首篇）· 对象状态：待评审；需求对照：docs/requirements/forge-accounts.md（同轮读完）。

范围与限制：无 AGENTS.md、无项目标准档、无文档地图 ⇒ 方法学合规与文档归属两项按降级口径判（设计档自带板块/配对需求档/状态/变更记录，且为板块首篇、未另起文件，未见归属冲突）。§5 体量标注已抽样核对总行数：`accounts_page.dart` 495 / `forge_api.dart` 527 / `test/forge/forge_test.dart` 518，与设计标注一致。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Doc-state / Requirements | 🟡 | R9 与 §8 的 open 项仍写作「本批**不改**」（docs/design/forge-accounts.md:255）与「B3 约束下不改」（:271），与本次评审声明转述的用户裁定（账户页描述补一行 Gitee 文案，按修改收口）不一致；§3.4 / §5 也未承载该项（无 `accountsDescription` 落点，§5 l10n 行仍写「各 +2 键」，:204） | 按裁定收口：§3.4 增加 `accountsDescription` 文案臂一行，§5 的 l10n 行改为「+2 键 + 1 键改文」并注明键名，§8 / R9 的「待用户裁定」改为确定表述（不留待裁字样） |
| 2 | Affected-file size annotations | 🟡 | §5「体量与拆包」（docs/design/forge-accounts.md:210，内含「无新增 >800 行文件」）只给 800 行硬顶方案，未覆盖 500 行档：`accounts_page.dart` 495 行 +约 15 行 ≈ 510 行，本次**跨过** 500 行档（:202）；`forge_api.dart` 527→约 650（:199）、`test/forge/forge_test.dart` 518→约 638（:206）同处 >500 档，均无拆包评审结论 | 在 §5 补一行拆包评审结论：对 `accounts_page.dart`（跨档）与 `forge_api.dart` / `forge_test.dart`（>500 档）各给「保留 + 越 800 时的拆法」或拆包计划，与既有条件拆法并列表述 |
| 3 | Acceptance criteria / Clarity | 🟡 | D3 让 `GiteeApi.issues` 先取一次 `me()`（docs/design/forge-accounts.md:46、:174），但未规定**未登录 / `me()` 失败**时列表路径的行为（`filter=assigned/created` 依赖 login，`filter=all` 不依赖）；§7 G9 与 §6 A2 均无该错误路径判据 | 补一条口径：仅 filter ≠ all 时取 `me()`，并给出失败时的行为（异常传播或降级 + 报错行）与对应用例/走查项 |
| 4 | Clarity / D1 影响面 | 🔵 | D1 的影响面只写「已核：`lib/stash/**` 无 `.number` 使用」（docs/design/forge-accounts.md:165），未给核查口径（范围与检索式），§5 清单隐含「其余文件不读 `number`」的结论不可审计 | 在 D1 或 §5 注明核查范围与检索式（如全仓 `.number` / `ForgeRef` 构造点检索），使 A4 的「只改字面量」可核 |
| 5 | Affected files | 🔵 | §5 列入新资产 `assets/branding/gitee.svg`（docs/design/forge-accounts.md:203），但未列 `pubspec.yaml`；若资产为逐文件声明而非目录声明，图标臂取不到资源（未核实） | 在 §5 或 §3.4 图标行注明资产声明方式：目录声明 ⇒ 无需改 pubspec；逐文件声明 ⇒ 计入受影响文件 |
| 6 | Field mapping / Risk list | 🔵 | PR 详情 `comments` 取「恒 0」（docs/design/forge-accounts.md:103），依据是单次探针的「无 `comments` 键」（:277）；该推断未进 §9 未核实清单 | 把「PR 评论数字段是否恒缺」补进 §9（A5 用一条有评论的 PR 核对），或明确有评论仍显示 0 的取舍 |
| 7 | Evidence sourcing | 🔵 | 端点 6（PR 评论，docs/design/forge-accounts.md:73）是 §3.1 表中唯一单来源行（仅 [D]），同伴行均带 [M] 或 [P] | A5 前用 [M] `operations/pulls/` 的客户端写法或带令牌探针补一条独立佐证，或列入 §9 首验项 |
| 8 | Closest-precedent | 🔵 | §2.2（docs/design/forge-accounts.md:28）给了实现坐标与偏离理由（5 条均带理由），但未给「匹配的设计档章节 / 先例批次」坐标 | 补一句先例出处：对应设计档章节，或声明两家早于板块、无设计档，补全先例三元组 |
| 9 | Doc hygiene（R7c） | 🔵 | 同一锚点两档行号漂移：`publicForgeKind` 设计档 `forge_ref.dart:33-37`（docs/design/forge-accounts.md:36）vs 需求档 `:34-35`（docs/requirements/forge-accounts.md:18）；主机表 `:59-65`（设计 :121）vs `:59-64`（需求 :22）；作用域文案 `:321-324`（设计 :126）vs `:322-323`（需求 :23）；设计档内部图标臂 `29-40`（:40）vs `27-41`（:127） | 两档自标「编制日快照」，可保留；建议同一锚点在档内先取齐一值，或档首声明「行号各档自用、不对齐」 |
| 10 | Test coverage | 🔵 | `/-/` 臂主机闸门收紧（docs/design/forge-accounts.md:114）是本批两处共用面改动之一，§7 只给 gitee 侧为 null 的 G3，无 github / gitlab 侧不受影响的显式回归用例（既有 group 是否已含此形未核实） | 在 §7 补一条 `https://gitlab.com/o/r/-/issues/1` 仍解析为 gitlab 的回归用例，或注明由既有 group 覆盖 |

计数：🔴 0 · 🟡 3 · 🔵 7
VERDICT: pass

## §4 用户批准（主 agent）

- **批准**（2026-10-16 18:11）：用户批「开工」。前置已闭合——设计评审 VERDICT pass（🔴 0 / 🟡 3 / 🔵 7，§3 轮次 1）+ 修正轮 1 全项落档、父侧核验 10/10（§2）。
- **实施**：eng-coder 单批派单（实现 → 审计 → 自检 → 交付）。
- **验收口径**：设计 §6 验收对照 A1–A5 + 用例 G1–G15；A5 真机走查用用户真实 Gitee 令牌（交付后与用户约时进行）。

## 用户批准（2026-10-18）

- 用户 2026-10-18 23:53「把哪几个在途做完吧」= 批准本批收口（实施 2026-10-16 已完成并经复验）。

## §5 实施记录（eng-coder）
**状态行**：✅ 实施完成 2026-10-16（修正轮：§3.7 四键 + 扩裁两处；l10n 测试 22/22 绿，analyze 干净）



### 交付摘要

Gitee 接成第三家 forge（令牌登录），实现面 = 设计档 §5 清单 + 拆包裁定的两处新增档。

| 面 | 文件（行数） | 内容 |
|---|---|---|
| 解析 | `lib/forge/forge_ref.dart`（271） | `ForgeKind.gitee`（label/publicHost）· `publicForgeKind` 加 gitee/www · `fromRemote` 两家→三家规约 · `ForgeRef.number` `int`→`String` · Gitee 解析臂 + `/-/` 臂闸门收紧（`known == null \|\| known == gitlab`）· url/tag 臂 |
| API | `lib/forge/forge_api.dart`（707） | 新 `GiteeApi`（`/api/v5`、Bearer）：me `/user` · issue `issues/{id}`（字母数字、区分大小写）· PR `pulls/{n}` · 评论 `issues\|pulls/{n}/comments` · 关闭 `PATCH /repos/{owner}/issues/{number}` 载荷 `{repo:<仓名>, state:'closed'}` · 列表 `state=open`+`state=progressing` 各 `per_page=50&sort=updated&direction=desc` 合并降序取前 50 · 无 checks；GitHub/GitLab 两处 number 构造改 `'${… as int}'`（保原行为） |
| 账户 | `lib/forge/forge_accounts.dart`（450） | `apiFor`/`_signIn` 加臂 · `canSignInFromBrowser(gitee)=false` · 设备流 5 处不可达臂抛 `ForgeException`（const 文案） |
| 视图 | `lib/forge/forge_view.dart`（132）+ `assets/branding/gitee.svg`（新） | 图标臂；资产 = 官方 logo 的 G 字形 path（`pubspec.yaml:106` 已按目录声明，未改 pubspec） |
| 账户页 | `lib/settings/pages/accounts_page.dart`（503） | 主机文案臂 · 撤销链接（私人令牌页）· 建令牌链接（无参）· 作用域文案臂 |
| l10n | `lib/l10n/app_en.arb`、`app_zh.arb` + 生成物 3 档 | +2 键、`accountsDescription` 一键改文（设计授权唯一例外）；`flutter gen-l10n` 已重生成 |
| 单测 | `test/forge/forge_test.dart`（475）· `test/forge/forge_gitee_test.dart`（453，新）· `test/forge/fake_forge_http.dart`（47，新） | 既有 6 处字面量改 String；G1–G15 面落新档（Gitee links / GiteeApi / Gitee account 三组 14 用例） |

**读数**（本机 `flutter test`，两目录同跑）：`test/forge/forge_test.dart` + `forge_gitee_test.dart` + `test/settings/accounts_page_test.dart` + `test/stash/{stash_forge_test,stash_forge_view_test,stash_sidebar_test}.dart` + `test/l10n_test.dart` = **64/64 全绿**；`dart analyze lib/forge lib/settings/pages/accounts_page.dart test/forge test/stash test/settings` = **No issues found**；8 档 `dart format --set-exit-if-changed` 全干净。

### 决策透明表

| # | 决策 / 偏差 | 依据 | 处理 |
|---|---|---|---|
| 1 | 单位测试面拆两档（`forge_test.dart` 原有两组 + 新 `forge_gitee_test.dart` 承 G1–G15） | 父侧本轮裁决：设计 §5「越 800 硬顶 ⇒ 触发拆包」与 §2/§6 单档验收命令冲突，按触发拆 | 已执行；验收命令改为两档同跑；档面口径更新留父侧 |
| 2 | 共用 fake 抽为 `test/forge/fake_forge_http.dart`，既有引用改指新档 | 拆包必需（Dart import 不传递） | 已执行 |
| 3 | **清单外改动 4 档**（仅 import 行）：`test/stash/stash_forge_test.dart`、`test/stash/stash_forge_view_test.dart`、`test/stash/stash_sidebar_test.dart`、`test/settings/accounts_page_test.dart` | 同上（搬迁连带，漏改即编译断链） | 已执行并在交付报告逐条披露 |
| 4 | 暂存件：`.thincoder/tmp/icons.png`（图标 16px 走查证据）+ `.thincoder/tmp/edge-profile/`（Edge headless 配置目录，非空、无工具删除路径） | 图标可辨性实机走查（设计 R7 指定 A5 判，先行取证） | 留档披露，父侧可清 |
| 5 | 未动项（不属本批授权）：l10n `accountsKeptLocally`、stash 导入三键文案；`forge_view` 两臂重复；`head` 取值加固 | 设计 §3.4/§8 只授权 `accountsDescription` 一键改文；其余属设计面缺口或可选 | 记入交付报告待父侧裁定 |

### 审计与代码评审轮次与终态

- **内部 explore 分歧审计（1 轮）**：6 条 —— ① 测试档 899 行越 800 硬顶 vs 单档验收命令（判定设计内部冲突 → 即时上抛，父侧裁定拆包）② `/enterprises/…` 未排除 ③ `_assignees` 取值顺序 ④ `take(50)` 截断无断言 ⑤ 临时件 ⑥ §5 待写。②③④ 依设计自修（含逐条补断言）；①⑤⑥ 依裁定/披露消解。**terminal = clean**。
- **advisor 代码评审（轮 1）**：7 条 —— 🔴1（拆包把 fake 移走后，`test/settings/accounts_page_test.dart:9`、`test/stash/stash_sidebar_test.dart:22` 仍从旧位置取 `FakeForgeHttp` ⇒ 两档编译断链）· 🟡2（A1 的 Gitee 401 签入用例未补；`accountsKeptLocally` 与 stash 导入文案仍只提两家，属设计面缺口）· 🔵3（`forge_view` 两臂重复 / `head` 取值加固 / 档面数字漂移）。**VERDICT: changes-required**。
- **fix round 1**：🔴 修（两处 import 收口新档；并用全仓检索机械证明无其它残留引用）· 🟡 之 A1 修（Gitee 组补「401 且不落库」用例）· 🟡 文案两条与 🔵 三条按「设计面缺口待父侧裁定 / 可选未动 / 父侧档面随修」记因，未擅动。
- **advisor 修正轮 2（仅核修正主张）**：🔴1 → **Fixed**（六处消费者全指新档、`forge_test.dart` 已无 import 消费方）；🟡4 → **Fixed**（`forge_gitee_test.dart:395` 新用例断言 401 抛错 + `accounts` 空 + keychain 未写）；其余 5 条 **Accepted**（未动项理由成立）；新引入问题 0。**VERDICT: pass**。
- **终态：clean**（审计 1 轮 + 评审 2 轮；无未决 🔴/🟡 必改项；无未回答的上抛）。

### fix round 记录

| 轮 | 来源 | 修正内容 | 复验 |
|---|---|---|---|
| 自修 | explore 审计 ②③④ | Gitee 臂排除 `enterprises` 首段 · `_assignees(kind, json)` 按 kind 取单/复数 · 新增「>50 条取前 50」用例 | 全档重跑绿 |
| 自修 | 交付纪律 | 两处代码注释与实现口径对齐；3 档 `dart format` 逐一格式（HEAD 版为格式干净档，可证偏差源自我新增行） | 8 档 format 干净 |
| fix 1 | advisor 轮 1 🔴 | 两处旧引用改指 `test/forge/fake_forge_http.dart`；全仓检索确认无残留 | 7 档 64 用例绿 |
| fix 2 | advisor 轮 1 🟡 | Gitee 组补 401 签入用例（语义对齐 A1） | 同上 |

### 修正轮（用户 2026-10-16 19:22「补gitee」扩裁落地；2026-10-16）

**范围**：设计 §3.7 四键改文 + 父侧同源扩裁两处；行为不动、`docs/**` 不动。

| 键 / 项 | 改动（file:line） | 口径 |
|---|---|---|
| `accountsKeptLocally` | `lib/l10n/app_en.arb:6392` · `app_zh.arb:2412` | 设计 §3.7 第 2 行逐字 |
| `stashImportNotALink` | `app_en.arb:6575` · `app_zh.arb:2477` | §3.7 第 3 行逐字 |
| `stashImportNoRepos` | `app_en.arb:6590` · `app_zh.arb:2485` | §3.7 第 4 行逐字 |
| `stashWelcomeTrack` | `app_en.arb:6624` · `app_zh.arb:2498` | §3.7 第 5 行逐字 |
| `settingsAccountsKeywords` | `app_en.arb:6388` · `app_zh.arb:2408` | 父侧扩裁①：各补 Gitee 一词（词形随既有索引风格） |
| 内置 skill 文本 | `lib/stash/stash_skill.dart:88`（`GitHub/GitLab/Gitee`）· `:98`（`GitHub, GitLab or Gitee`） | 父侧扩裁②：清单补 Gitee，句式不动、只改枚举 |
| 生成物 | `lib/l10n/app_localizations.dart` · `app_localizations_en.dart` · `app_localizations_zh.dart` | `flutter gen-l10n` 重产（不手改） |

**读数**：`flutter test test/l10n_test.dart` = **22/22 全绿**；`flutter analyze lib/l10n lib/stash/stash_skill.dart` = **No issues found**。

**决策透明表**

| # | 决策 / 偏差 | 依据 | 处理 |
|---|---|---|---|
| 1 | `settingsAccountsKeywords` 与 `stash_skill.dart` 两处本体在设计 §3.7 清单外；设计 §8:302 仍记「不在改文清单」，批次档 §2 发现项 2/3 仍写待裁/需另裁 | 父侧本轮扩裁（任务书授权） | 已执行；档面口径（设计 §3.7 / §8、批次档 §2 发现项）待父侧收口，记入交付报告 |
| 2 | `flutter` 不在 PATH，经 `.dart_tool/package_config.json` 定位 SDK（`C:\Users\xinbo\repos\flutter\bin\flutter.bat`） | 环境事实 | 以全路径执行；无代码影响 |

**审计与代码评审轮次与终态**

- **内部 explore 分歧审计（1 轮）**：代码面四类偏差 = 0（授权项逐条一致、无改动外文件、生成物与 arb 同步、禁止面未碰）；报 DOC-DRIFT 2 条（设计 §3.7 未含扩裁三处；批次档 §2 发现项 2/3 仍写待裁）—— owner = 父侧档面，按「`docs/**` 本单不动」记入交付报告。
- **advisor 代码评审（1 轮）**：🔴 0 · 🟡 2（同上述档面滞后，report-only）· 🔵 1（批次档发现项已办未勾）。**VERDICT: pass**。
- **终态：clean**（无 🔴 / must-fix；无代码改动待修；无未回答上抛）。

**未做项**：设计 §3.7 清单外其它键 · github/gitlab 行为与文案语义 · `docs/**`（含设计 §3.7 / §8 与批次档发现项收口）· 手改生成物 · `thincoder/` 仓。

## §6 验证与收口（父代理）

- **实施中的设计偏差与裁定**（2026-10-16 18:26；子代理 #11 上抛，父侧裁定）：`test/forge/forge_test.dart` 实测越 800 行硬顶（写实后 +381，超 §5 估计 +120）⇒ 按 §5 该档自设触发**拆包**——既有两组留 `forge_test.dart`，G1–G15 落新档 `test/forge/forge_gitee_test.dart`；验收命令 = 两档同跑。档面同步 = 设计档 §5/§6 A4 + 批次档 §2（修正单 #12，父侧已核验）；两档最终行数待 #11 交付读数随修。

## 验证与收口

- **实施**：2026-10-16 实施完成（§3.7 四键 + 扩裁两处；l10n 22/22 绿，analyze 干净）——读数见 §5；设计评审通过 + 修正轮 1 落档（§3）。
- **用户批准**：2026-10-18 23:53「把哪几个在途做完吧」。
- **落档**：`docs/batches/forge-gitee.md` + `docs/design/forge-accounts.md` + `docs/requirements/forge-accounts.md` 随本收口提交。
- **台账**：#13 核销（证据 = 本档 §6）。
