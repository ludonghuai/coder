# 2026-11-11 · upstream-sync-5
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-11 · 来源 = 用户 2026-11-11「拉代码更新」；上游 baocode-dev/baocode 远端 tip 5f4a1d50（1.9.5），本地 main = 9512b096（上次合到 43e05e39）。
> 台账 = #237（— · 归批）。前情 = docs/batches/2026-11-09-upstream-sync-4.md（已收口 2026-11-10）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-11
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：合上游 47 个提交（1.9.3 → 1.9.5）+ 出新构建

合基 `43e05e39`（上批合到的上游 tip）；本地合并前 `9512b096`；上游 tip `5f4a1d50`（1.9.5 发版）。

**已定决定**：按既有形态合上游到 main——冲突按 `docs/design/fork-deltas.md` 登记面处置（自有块保留、上游新形跟进、l10n 走键级并集 + `flutter gen-l10n` 重产）；合后出新 Release 构建并替换运行实例 · 用户原话：「拉代码更新」· 时间：2026-11-11 20:17

**网络**：本机直连 `github.com` 不通（`Recv failure: Connection was reset`），经本地代理 `http://127.0.0.1:7890`（FlClash 在跑）拉取成功。

**规模**：上游 47 个提交、99 档；其中 **26 档两侧都动过**（自有块 ∩ 上游改动）。

- 文档面 4：`README.md` · `README_CN.md` · `docs/release.md` · `.github/workflows/release.yml`
- 会话与面板 6：`lib/chat/chat_history_view.dart` · `lib/chat/chat_session.dart` · `lib/chat/panels/context_usage_panel.dart` · `lib/chat/side_panel/side_panel_view.dart` · `lib/ide/ide_agent_edits.dart` · `lib/ide/terminal/terminal_panel.dart`
- 编辑器与工作台 3：`lib/ide/ide_editor.dart` · `lib/workbench.dart` · `lib/main.dart`
- 内核与设置 6：`lib/kernel/claude_code/claude_code_kernel.dart` · `claude_code_transport.dart` · `lib/kernel/kernel_registry.dart` · `lib/kernel/kernel_types.dart` · `lib/settings/pages/general_page.dart` · `lib/bots/bots.dart`
- l10n 5：`lib/l10n/app_en.arb` · `app_zh.arb` · `app_localizations.dart` · `app_localizations_en.dart` · `app_localizations_zh.dart`
- 测试 2：`test/bots/bots_test.dart` · `test/chat/code_citation_test.dart`

**冲突（9 档，合并停在冲突态，未提交）**：

| 档 | 冲突块 | 现场 |
|---|---|---|
| `README.md` · `README_CN.md` | 各 1 | 上游把 Ubuntu 22.04 降到 20.04（glibc 2.31 构建）；我方那一句带 ThinCoder 可选装 |
| `lib/bots/bots.dart` | 1 | 上游改成 `instructions: [ …, groupPrompt … ].join('\n\n')`；我方该处用 `HostTools.called` / `HostTools.server` |
| `lib/l10n/app_en.arb` · `app_zh.arb` | 各 1 | 两侧在同一位置各追加了键（我方 sidePanel / thincoder / btest 键，上游 1.9.3–1.9.5 新键） |
| `lib/l10n/app_localizations.dart` · `_en.dart` · `_zh.dart` | 3 档 | 生成档，按第 1 节规则不手解，重产 |
| `lib/settings/pages/general_page.dart` | 1 | import 冲突：我方 `editor_context_setting.dart`，上游 `rewind_files_setting.dart` |

**当前状态**：`git merge --no-ff origin/main` 已执行并停在冲突态（`MERGE_HEAD` 在、工作树带冲突标记）；未提交、未构建、未替换实例。

**下一步**：§2（设计席，逐档处置表）→ 设计评审 → 批准 → eng-coder 解冲突并完成合并 → 机检（analyze / 定向 / 集成）→ 构建 → 替换实例 → 收口。

### 评审回来（0 🔴 · 8 🟡 · 5 🔵）· 父侧裁决与修轮清单

13 条全部受理。第 10 条的文件名部分父侧试改后撤回（见下条补记）；第 11 条（§3 旧行号）本批不动，留待触碰时改。其余 11 条派设计席修轮。

| # | 改什么 | 落点 |
|---|---|---|
| 1 | 补「最近先例」行：先例批次 + 对应设计档节 + 对齐 ∥ 偏离 | §2 |
| 2 | 补「调查证据」行：`publicRepos` 为空、上游经 `origin` 读、查过无外部相关 | §2 |
| 3 | 验收点名改动面用例（至少 `test/bots/bots_test.dart` + `test/l10n_test.dart`）；加一条「实跑名单与既有失败名单」；为 §3.1 两处改动各补读回判据 | §2.7 |
| 4 | 「零冲突残留」判据改为 `git diff --diff-filter=U --name-only` 为空 + 冲突标记扫描 = 0，`UU` 降为附加读数 | §2.1 第 1 条 · §2.7 第 1 条 · §2.8 |
| 5 | §3.1 下游两处写死读数改规则形：用例表行「15 档 numstat / 6 条非零」与「表外补登记的两行」段 | design 档 §3.1 |
| 6 | 给上游新到档 `wc -l` 读数（或明写全部 <500），档位结论扩成「本批触碰档里没有新档越过 500 / 800（除 11 档存量债）」 | §2.4 |
| 7 | 补 `类型` 列（修 bug / 功能 / 内核适配），与 §3 已落盘六行对齐 | §2.5 |
| 8 | `terminal_panel` 行记录场景，或明写「无场景记录，下一轮复核」 | §2.5 |
| 9 | 「行数预算」列去掉上限或标为参考上限；判据取落盘实测值 | §2.5 |
| 12 | 「生成前」改成「键并集后、`flutter gen-l10n` 前」 | §2.1 第 3 条 |
| 13 | 按 §8.4 的形态逐行列出 9 条 RTM 的断言面 | §2.11 |

**另**：§2 头部两条状态行只留一条（工具管理的那条）；文件名已改，正文标题与编制行的 2026-11-11 不再冲突。

**本修轮不做**：不改产品代码、不动冲突态工作树、不重跑合并、不写 §4 / §6。

### 裁决补记：档名不改（评审 #10 的处置）

试过把档名改成次日日期，但已落段的引用里有三处写着旧档名（§2 一处、§3 两处），改名后它们会变成死指针；§3 是评审子代理的段，本席无写权 ⇒ 撤回改名，存量指针保持可解析。

评审 #10 的两项因此这样处置：档名与正文标题 / 编制行的日期不一致——**受理不改**（档名是标识，标题里的日期才是本批日期；为一行日期制造三处死指针不值）；§2 头部两条状态行——由设计席在修轮里删掉多余那条。

### 设计席两处上抛的裁决

1. **`lib/ide/terminal/terminal_view.dart`（P6 同一条守卫，对 `origin/main` +4 / −1）—— 补第 7 行登记**。理由：`docs/design/fork-deltas.md` §5 第 2 步的「表外发现自有块时先补第 3 节」不看该档是否被本批触碰；它与本批已补的 6 行同类（表外自有块），不是新语义。
2. **存量债名单是否改成闭合枚举 —— 本批不改**。理由：闭合枚举要先做全仓共享档的体量普查，属另一次清理；本批 §2.4 的结论已收窄到「本批合并中上游侧触碰的档里没有新档越过 800 行」，这个判据成立。名单的非闭合性记 §6 为已知状态。

### 评审轮 2 的裁决与修轮清单（2 条 🟡，实施前修掉）

| # | 改什么 | 落点 |
|---|---|---|
| 1 | §2.2 第一条的「现文写死「本批 = 合并触碰的 15 档」」改成改后形态（或写明该节改动已落盘）——fork-deltas §3.1 现文是「本节不写死档数」，两档不能再给出同一节的两个现态 | §2.2 |
| 2 | §2.4 结论点明 500 档线，并给 `bot_groups.dart` 753 行的拆分复核结论（零自有行的上游新档 ⇒ 本批不拆、记候选）；「最大」限定为「新档内最大」 | §2.4 |

第 3 条（🔵）是 §6 的承诺项，收口时记，不进修轮。

**本修轮不做**：不改产品代码、不动冲突态工作树、不重跑合并、不写 §4 / §6。

### eng-coder 上抛裁决：README 的排版最小修（放行）

**事实**：写 §5 时文档机检拒写，命中 `README.md` 两段 >300 字符（徽标锚点 348 字符、Why 段 536 字符），两段都是上游原文；而本批设计写着 README 文案只登记、不重写。

**裁决：放行零改字的排版最小修**——徽标挪到 `# BaoCode` 标题行（标题行不计段落），536 字符那段在句号处拆成三段，一个词不改。

**依据**：本仓已有同类先例——`docs/release.md` 的 41 行换行重排被登记为格式差异，`docs/design/fork-deltas.md` §3 该行写明「格式、语义不变，下一轮冲突时可直接弃块」。零改字的排版修与它同形。

**代价与善后**：README 对 `origin/main` 的 numstat 从 `+4 / −3` 变为新值 ⇒ 登记行的实测列须随之更新（由设计席改，eng-coder 无该档写权）；§6 记这条。

**不做**：不改 README 措辞、不增删内容、不为过门改写任何产品文案。

### 实施后三处口径的处置（派设计席收尾）

父侧自核：合并提交 `de389d72`（父 `9512b096` + `5f4a1d50`）、冲突残留 0、标记扫描 0、README `+10 / −4`、登记表七行在位。

| # | 改什么 | 落点 |
|---|---|---|
| 1 | §2.3 的 `bots.dart` 判据笔误：现写 `HostTools.called` = 1、`HostTools.server` = 1，实为块内各 1 处、全档各 2 处（`:537` 的既有 `offersTool` 另有一处）⇒ 改成「块内各 1 处；全档 ≥1」，**不许**为凑数删既有行 | §2.3 |
| 2 | §2.7 第 9 条的「`l10n_test` 全绿」与第 10 条「既有失败可列」互斥：实测 `22 过 / 1 失败`，那 1 条是既有红（`git.fetchAll` 自有标签与上游 arb 措辞不一致，合前基线同）⇒ 改成带基线的读数 | §2.7 |
| 3 | README 登记读数：`+4 / −3` → `+10 / −4`（零改字排版修：徽标改为 `- ` 列表行、Why 段按句号拆 3 段），并注明「格式差异，语义不变，下一轮冲突时可直接弃块」 | `docs/design/fork-deltas.md` §3 README 行 · §2.5 README 行 |

第 3 条的形态差异（徽标改成列表行而非挪到标题行）父侧追认：目标是机检清零且零改字，形态本身不改语义。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（两轮修轮 + 实施后三处口径收尾已落定（§2.3 bots 块内各 1 / 全档各 2；§2.7 l10n 改带基线读数；README +10 / −4 与 fork-deltas §3 登记行同值）；产品代码零改写）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**最近先例**：同一形的先例 = 前三次 `upstream-sync` 合并批（`docs/batches/2026-11-08-upstream-sync-2.md` · `docs/batches/2026-11-09-upstream-sync-3.md` · `docs/batches/2026-11-09-upstream-sync-4.md`）。对应设计档节 = `docs/design/fork-deltas.md` §5（合并核对顺序）与 §3.1（登记面对账口径）。

对齐：冲突逐档按登记面处置、表外自有块先补表、l10n 键级并集 + `flutter gen-l10n` 重产。偏离：无 —— 本批只换档与读数，处置口径不变。

**调查证据**：`manifest.index.publicRepos` 为空（`PROJECT-MANIFEST.json` 读得 `"publicRepos":[]`），无独立公开文档仓；上游源码经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

### 2.1 本批条目（覆盖）

本批是一次上游合并轮（47 提交、1.9.3 → 1.9.5）。可实施面 = 解 9 处冲突、重产 l10n、补登记面；构建与实例替换是父侧操作步。

| # | 条目 | 判据（机器可判） | 设计落点 |
|---|---|---|---|
| 1 | 合上游到 main，父指针正确、零冲突残留 | `git log -1 --format=%P HEAD` = `9512b096 5f4a1d50`；`git diff --diff-filter=U --name-only` 输出为空；冲突标记扫描 `git grep -nE '^(<{7} |={7}[[:space:]]*$|>{7} )'` 行数 = 0；附加读数：`UU` 行数 = 0 | §2.3 |
| 2 | 9 处冲突按本节逐档处置，不整档取上游、不回退上游实现 | 每档判据见 §2.3 表「判据」列（逐档 1–3 条符号 / 计数读数） | §2.3 |
| 3 | l10n 键级并集并重产，不手解生成物 | 键并集后、`flutter gen-l10n` 前：`app_en.arb` 4786 键、`app_zh.arb` 3810 键、消息键两侧各 3808 且逐键相等（不含 `@@locale`）；生成后三个生成档零手改 | §2.3 · §2.5 |
| 4 | 表外 7 处自有块补登记（先补表，再谈其它） | `docs/design/fork-deltas.md` §3 新增 7 行：`.github/workflows/release.yml`、`README_CN.md`、`docs/release.md`、`lib/chat/panels/context_usage_panel.dart`、`lib/ide/ide_agent_edits.dart`、`lib/ide/terminal/terminal_panel.dart`、`lib/ide/terminal/terminal_view.dart` | §2.5 |
| 5 | 登记面读数刷新 | `test/bots/bots_test.dart` 行改 `+39 / −39`；l10n 行改 `en 4786 / zh 3810 / 消息 3808`；其余登记行按 §2.5 复核后数值不变 | §2.5 |
| 6 | 行数预算不超 | `bots.dart` 净增 ≤6；`general_page.dart` 净增 ≤93；`README.md` +10 / −4（含零改字排版修）；`file_preview` 净 27 ≤40；`chat_session` 净 107 ≤180 | §2.5 |
| 7 | 编译面不退化 | `flutter analyze --no-pub` 的 error 数 = 0 | §2.7 |
| 8 | 交付物：新 Release 构建替换运行实例 | 同 `docs/batches/2026-11-09-upstream-sync-4.md` §2.1 第 7 条三条读数（`data/app.so` mtime 晚于合并提交、旧实例已关、新实例 PID 与启动时间记 §6） | §2.9 |
| 9 | 文档机检 | `doc_check(mode:"gate")` 首行 = `DOC-CHECK GATE: PASS` | §2.7 |

### 2.2 设计档落点

`docs/design/fork-deltas.md`（`docRoot.design` 下，已在盘），四处就地改：

- **§3 补 7 行**（§2.5 七处新登记），并刷新 2 行读数（`bots_test`、l10n）。
- **§3.1 判据域为规则形**（已落盘）：判据域 = 本批合并中上游侧触碰的共享上游档，档数逐批读 `git diff --name-only <合基> <上游 tip>`，本节不写死档数；域外由全量 diff 发现的表外自有块另按第 5 节第 2 步补行（如 `lib/ide/terminal/terminal_view.dart`）。
- **§3.1 补一条生成物规则**：`lib/l10n/app_localizations*.dart` 的非零差异由 arb 行承载，不单列登记行。
- **§3.1 两处下游写死读数改规则形**：用例表行不再写「15 档 / 6 条非零」；「表外补登记的两行」段整段删除（两行已在 §3 内）。

不新建设计档：这是一张登记表的一次对账刷新，两个实体（新旧两处登记）会漂开。

**既有件三问：本批无新增命名**——7 行登记指向已存在的文件与已存在的接缝符号，无新组件 / 端点 / 文案。

### 2.3 机制设计：冲突逐档处置与合并形态

依据 docs/design/fork-deltas.md「自有目录 / 文件不得因冲突整档取上游；共享文件不得把上游实现回退成旧 fork 版本。」本批 9 处冲突全落在共享上游档，逐档按登记面处置。

| 档 | 冲突块 | 处置 | 判据（机器可判） |
|---|---|---|---|
| `README.md` | 1 | 取上游 Linux 行（Ubuntu 20.04，glibc 2.31 构建），保留我方 ThinCoder 可选装行 | 档内 `Ubuntu 20.04` ≥1 且 `Ubuntu 22.04` = 0；`npm i -g thincoder` = 1；numstat = +10 / −4（含零改字排版修：徽标改 `- ` 起头的列表行、Why 段按句号拆 3 段——格式差异，语义不变，下一轮冲突时可直接弃块） |
| `README_CN.md` | 1 | 同上（中文行） | `Ubuntu 20.04` ≥1 且 `Ubuntu 22.04` = 0；`npm i -g thincoder` = 1；numstat = +4 / −3（登记行实测列；合后读数） |
| `lib/bots/bots.dart` | 1 | 取上游列表形（`[ botInstructions(…), if (path != bot.folder) ?groupPrompt?.call(bot, path) ].join('\n\n')`），我方 `HostTools.called` / `HostTools.server` 留在块内 | `HostTools.called`、`HostTools.server` 块内各 1 处（全档各 2 处：另 1 处是既有 `offersTool` 放行判定的同一行 `HostTools.called('mcp__${HostTools.server}__$tool')?.kind ==`，与冲突块无关；判据取「≥1」，不许为凑数删既有行）、`groupPrompt` ≥1、`ClaudeSdkTools.called` = 0；净增 ≤6 行 |
| `lib/l10n/app_en.arb` · `app_zh.arb` | 各 1 | 键级并集：两侧新增键全留；同名键取上游措辞 | en 4786 键、zh 3810 键、消息键两侧各 3808 且逐键相等；我方独有键 en 101 / zh 55、上游独有键 en 49 / zh 36 全在盘 |
| `lib/l10n/app_localizations.dart` · `_en.dart` · `_zh.dart` | 3 | 不手解、不选边：清掉冲突标记后由 `flutter gen-l10n` 整档重产 | 生成后 `flutter analyze --no-pub` 无 error；`test/l10n_test.dart` 22 过 / 1 失——那 1 条为既有红（`git.fetchAll` 自有标签与上游 arb 措辞不一致，合前基线 `9512b096` 同为 22 / 1），判据取「重产面无新增失败」 |
| `lib/settings/pages/general_page.dart` | 1（import） | 两条 import 都留：`editor_context_setting.dart`（我方）与 `rewind_files_setting.dart`（上游）；两处设置组并存 | 两条 import 各 = 1；`EditorContextSetting` 与 `RewindFilesSetting` 各 ≥1；净增 ≤93 行 |

**计数口径**：上表 6 行覆盖 9 档 —— l10n 行合 2 档、生成物行合 3 档，其余 4 行各 1 档。

**处置次序**：先按上表解 9 处 → `flutter gen-l10n` 重产 l10n → 按 §3.1 对全档做 numstat 对账。解冲突期间不改 `packages/**`（扩面另议）。

**本批对账读数**（工作树对 `origin/main`，`git diff --numstat`）：上游本批触碰 99 档，其中 26 档有自有差异，全部对上 §3 的行；本批补登记的 7 处里 6 处落在这 26 档内，`lib/ide/terminal/terminal_view.dart` 不在上游触碰面、按 §5 第 2 步补行；其余 73 档零差异 = 纯上游面。冲突未解的 9 档当前读数含冲突标记，不作判据，合后重读；已解档的读数见 §2.5。

### 2.4 受影响文件清单（含档位结论）

| 文件 | 本批动作 |
|---|---|
| `docs/design/fork-deltas.md` | §3 补 7 行 + 刷新 2 行；§3.1 判据域改规则形、补生成物规则、两处下游写死读数改规则形 |
| 9 处冲突档 | 解冲突（§2.3 表），不改冲突块外的上游实现 |
| `lib/l10n/app_localizations*.dart` | 由 `flutter gen-l10n` 重产 |
| `docs/batches/2026-11-10-upstream-sync-5.md` §2 | 本节 |

**档位结论：无档跨档**。存量债 11 档名单（`docs/design/fork-deltas.md` §3 存量债段）成员不变：本批没有共享档被拆，也没有自有档变成共享档。

两条体量线逐条过：500 行 = 主动拆分审阅带（越过者逐档给结论），800 行 = 硬顶（存量债名单）。依据 docs/design/chat-streaming.md「体量档（>800 行 = 硬顶；>500 行 = 主动拆分审阅带，逐档给结论）」

- **500 线**：本批新到的 7 个上游档里只有 `bot_groups.dart` 753 越过（新档内最大；其余 6 档 25–345 行），落在审阅带内。拆分复核结论：**本批不拆、记候选**。该档对 `origin/main` 的 `git diff --numstat` 为空（零自有行，纯上游档），拆它会把一个上游档切成两半、两半都成常驻 fork 差异；依据 docs/design/fork-deltas.md「把上游共享档拆成两档，两半都成常驻 fork 差异，每次上游合并要在两处对账」。候选留待上游自己拆，或另起清理批。
- **800 线**：本批合并中上游侧触碰的档里没有新档越过 800，未触存量债门槛。9 处冲突档里过 800 的 `bots.dart` 1367 与 `general_page.dart` 842 都是既有上游共享档（前者在名单内），本批只解冲突、不拆档。
- 新到档的测试档同样在 500 线内（`wc -l` 实测：243 · 255 · 186 · 94 · 71 · 53），无审阅带档。

**上游新到档 `wc -l` 实测**（工作树）：

| 文件 | 行数 |
|---|---|
| `lib/bots/bot_groups.dart` | 753 |
| `lib/models/claude_resets.dart` | 345 |
| `lib/models/claude_resets_io.dart` | 254 |
| `lib/bots/bot_group_prompt.dart` | 107 |
| `lib/kernel/claude_code/tool_result_tally.dart` | 95 |
| `lib/chat/rewind_files_prompt.dart` | 80 |
| `lib/chat/rewind_files_setting.dart` | 25 |

**9 处冲突档 `wc -l` 实测**（HEAD `9512b096` 合前读数；冲突态工作树读数含标记，不作判据）：

| 文件 | 行数 |
|---|---|
| `lib/l10n/app_localizations.dart` | 22777 |
| `lib/l10n/app_localizations_en.dart` | 14004 |
| `lib/l10n/app_localizations_zh.dart` | 13246 |
| `lib/l10n/app_en.arb` | 9066 |
| `lib/l10n/app_zh.arb` | 3784 |
| `lib/bots/bots.dart` | 1367 |
| `lib/settings/pages/general_page.dart` | 842 |
| `README.md` | 101 |
| `README_CN.md` | 95 |

l10n 生成物三档（`app_localizations*.dart`）由 `gen-l10n` 重产，不按体量判。名单行数读数 §5 按原命令复核。

### 2.5 接口契约（七处补登记行 + 两处刷新读数）

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算（参考；判据取「实测」列） | 实测（对 `origin/main`） |
|---|---|---|---|---|
| `.github/workflows/release.yml` | 去掉 `push: tags` 触发（本 fork 无 R2 / 签名密钥），加 4 行注释指向 `tool/publish_release.dart` 与 `docs/design/distribution.md` §7 | 功能 | 工作流的 `on:` 触发面；发布走本仓脚本 | 实测即基线（首次登记） | +4 / −2 |
| `README_CN.md` | 与 `README.md` 行同形的四处发售面文案：首句并列 ThinCoder、正文「不包含自己的智能体」段改写、特性表「双内核」一条、Requirements 段 ThinCoder 可选安装行 | 功能 | 无代码接缝；消费面 = 仓库首页 | 实测即基线（首次登记；冲突态含标记，取合后读数） | +4 / −3 |
| `docs/release.md` | 首行 fork 发布说明（tag 发布已停用，指向 `docs/design/distribution.md` §7）+ 长段落拆行（语义不变） | 功能 | 该文档头部；发布流程文字 | 实测即基线（首次登记；含 41 行换行重排） | +42 / −7 |
| `lib/chat/panels/context_usage_panel.dart` | 会话累计用量一行：`usage.sessionSpent` 非空时追加 `usageSessionTotal` 统计行 | 功能 | `ContextUsage.sessionSpent`；与上游 `detail` 分段明细并存 | 参考上限每类 ≤40 行（同源 `kernel_types` 行）；基线 +7 / 0 | +7 / 0 |
| `lib/ide/ide_agent_edits.dart` | 窄标签栏图标态（`compact` 与 `Codicons`）+ 回退计划钩：`canPlanRevert` 为真时先问内核、展示计划 | 功能 | `ChatSession.canPlanRevert` / `revertTurn`；`PlansReverts`（`revert_dialog.dart`） | 参考上限净增 ≤35 行；基线 +29 / −6 | +29 / −6 |
| `lib/ide/terminal/terminal_panel.dart` | 标签在按下与菜单之间离场时不崩：`findRenderObject()` 空值判定后早退 | 修 bug | 标签菜单的锚点计算 | 参考上限净增 ≤3 行；基线 +3 / −1 | +3 / −1 |
| `lib/ide/terminal/terminal_view.dart` | 同一条 P6 守卫的隔壁档：菜单锚点计算前判 `findRenderObject()` 空值后早退 | 修 bug | 命令标记菜单与标签菜单的锚点计算 | 实测即基线（首次登记） | +4 / −1 |

**`terminal_panel` 行的场景**：依据 docs/batches/2026-10-17-ide-stability-guards.md「缺陷修：`findRenderObject()!` 强转，目标滚出视口/被移除即崩」——P6 记录的就是这个缺陷：标签滚出视口或被移除后按下菜单即崩。本行是同一守卫的现态，本批只登记、不改代码；下一轮合并时按本条复核。`terminal_view.dart` 行同一场景：P6 原文点名两档。

**两处刷新读数**：

- `test/bots/bots_test.dart` 行：实测列由 `+38 / −38`（净 0）改为 `+39 / −39`（净 0）；净增预算不变。
- l10n 行：键数读数改为 `en 4786 键、zh 3810 键，消息键两侧各 3808、逐键相等`（键级并集计算值：HEAD ∪ `origin/main`，不含 `@@locale`）。

**其余登记行本批复核后数值不变**，逐档实读（有差异者）：

- `chat_history_view` +337 / −26（与行内同值）· `side_panel_view` +10 / −3（同值）· `claude_code_transport` +1 / −1（同值）。
- `chat_session` 净 107 ≤180 · `ide_editor` 净 6 ≤7 · `claude_code_kernel` +7 / −6（净 1 = import）· `kernel_registry` +12 / −1。
- `main` +32 / −5 · `workbench` +56 / −3（面板 10 · 扫描 46）· `code_citation_test` +23 / −10（净 13 ≤33）。
- `workspace` +125 / −31 · `step_folds` +181 / −74 · `file_preview` 净 27 ≤40 · `kernel_types` +63 / 0。

### 2.6 关键决策记录

| 选项 | 内容 | 结论与理由 |
|---|---|---|
| A（采用） | 9 处冲突按登记面逐档处置，表外 7 处先补登记再合 | `docs/design/fork-deltas.md` §5 第 2 步与 §3.1 的既定处置；自有语义只在登记面存活 |
| B（否） | 冲突档整档取上游（README 取上游、bots 取上游） | 删的是产品语义（发售面文案、`HostTools` 注册表接线），且会让 `HostTools` 与 `ClaudeSdkTools` 两张表并存（§7.1 已论证的静默不可见） |
| C（否） | 手解 `app_localizations*.dart` 三档 | 生成物手解会在下一次 `gen-l10n` 被覆盖，且副作用不可见；第 1 节口径就是「不手解、不选边」 |
| D（否） | `docs/release.md` 不登记、把段落换行还原成上游长行 | 换行块是 41 行纯格式差异，登记行写明「格式、语义不变」，下一轮冲突时可直接弃块；还原属另一次文档改动，不在合并轮做 |
| E（否） | 为上游新档（`bot_groups.dart` 等）预先建登记行 | 零自有行 = 零差异；空登记行会让下一轮无法区分「没有块」与「块丢了」 |

### 2.7 验收对照

| 条目 | 判据（机器可判） | 读数来源 |
|---|---|---|
| 1 | `git log -1 --format=%P HEAD` = `9512b096 5f4a1d50`；`git diff --diff-filter=U --name-only` 输出为空；冲突标记扫描 `git grep -nE '^(<{7} |={7}[[:space:]]*$|>{7} )'` 行数 = 0；附加读数：`UU` = 0 | §5 实测 |
| 2 | §2.3 表判据列的逐档符号 / 计数 / numstat 读数全中 | §5 逐档实测 |
| 3 | `flutter gen-l10n` 后两 arb 键数 = 4786 / 3810，消息键逐键相等；`flutter test test/l10n_test.dart` 22 过 / 1 失，那 1 条为既有红（合前基线 `9512b096` 同为 22 / 1）⇒ 判据 = 重产面无新增失败 | §5 实测 |
| 4 | `docs/design/fork-deltas.md` §3 含 7 个新档名，每行实测列 = numstat 读数 | 设计档读回 + §5 |
| 5 | 26 档 numstat 的非零行逐条命中 §3 的行（生成物由 arb 行承载） | §5 实测 |
| 6 | `flutter analyze --no-pub` 的 error 数 = 0 | §5 实测 |
| 7 | `doc_check(mode:"gate")` 首行 = `DOC-CHECK GATE: PASS` | 本轮实跑 |
| 8 | 交付物三条读数（§2.1 第 8 条） | 父侧操作步后实测，读数记 §6 |
| 9 | 改动面用例：`flutter test test/bots/bots_test.dart` 50 过 / 0 失；`flutter test test/l10n_test.dart` 22 过 / 1 失，那 1 条是既有红（`git.fetchAll`：自有标签 `Fetch and Pull All Repositories` 与上游 arb 措辞 `Fetch From All Remotes` 不一致；合前基线 `9512b096` 同为 22 / 1）⇒ 判据 = 本批新增失败 0；逐档条数归因记 §5.3 | §5 实测 |
| 10 | 实跑名单与既有失败名单：§5 列实跑名单（每个用例文件 → 通过 / 失败条数）与失败条目归因；既有失败（平台族 #192 / #195、`fold_view_test` 既有那条）逐条在名单内，本批新增失败 = 0 | §5 实测 + 名单读回 |
| 11 | `docs/design/fork-deltas.md` §3.1 两处改动读回：全文无 `15 档` / `6 条非零` / `表外补登记的两行`；生成物规则一句在盘 | 设计档读回 |

### 2.8 用例表

| 场景 | 输入 | 期望 | 承载 |
|---|---|---|---|
| 正常 · 冲突解完 | 9 档工作树 | `git diff --diff-filter=U --name-only` 输出为空 + 冲突标记扫描 0 行（`UU` = 0 仅作附加读数），父指针正确 | `git log` / `git diff` / `git grep` |
| 正常 · 键并集 | 两侧 arb | en 4786 / zh 3810 / 消息 3808 两侧相等 | 键计数脚本（§5 记命令与读数） |
| 边界 · 同名键 | 两侧同键不同措辞 | 取上游措辞，我方键不覆盖上游文案 | `app_en.arb` 抽查 + 差异计数 |
| 边界 · 生成物 | `gen-l10n` 后三档 | 与生成器输出一致（无手改残留） | 重跑生成器后 `git diff --stat` 为空 |
| 错误 · 表外自有块 | 任一档非零而无登记行 | 停止实施、先补表 | 本批即此场景实例（7 处） |

本批无行为断言，用例面是 git / 键计数读数；不新造常驻测试文件。

### 2.9 边界（本批不做）

- 不改冲突块外的上游实现；不为消冲突整档回退。
- 不动 `packages/**` 的合并面（扩面另议，见 `docs/design/fork-deltas.md` §3 存量债段口径）。
- 不拆大档（存量债，认账不排期）。
- 不修平台路径族既有失败用例（台账 #192 / #195 面），本批只记实跑名单。
- 构建与实例替换不在本表：父侧操作步。

### 2.10 UI / 交互

**无自有界面变更**：合并进来的上游界面（设置 → 通用的「修改历史消息」组、群组 prompt、工具结果计数）是上游实现，本仓零改写。9 处冲突处置都不改我方界面决策：设置页多一组上游设置，共存。`open` 项：无。

### 2.11 集成测试设计（RTM delta）

读 `test/RTM.md`（9 行：1-1 / 2-1 / 3-1 / 4-1 / 5-1 / 6-1 / 7-1 / 8-1 / 9-1），逐行断言面如下（按 `docs/design/fork-deltas.md` §8.4 的形态）：

| 行 | 断言面（本轮逐行读过） |
|---|---|
| 1-1 | 五次切换各起一个进程（假件 `start` 计数）；每次切换后 300 ms 内历史行就位、输入可用；`[stall]` 0 行 |
| 2-1 | 失焦期重建 0 次、可见文本不变；恢复恰 1 次重建、可见文本 == 全文、底部仍在底部、中段偏移不变 |
| 3-1 | 终态可见文本 == 全文；500 / 20 回合两组每增量重建行数逐项相等且有上界 |
| 4-1 | btest card 恰一次；readonly 写调用被拒且原因可读；切回后 off 文本恰一次；composer 与工具门读同一状态 |
| 5-1 | 收尾缺项被拒（逐项点名缺的场景 / issue 字段，未走到的 case 只计数、不在拒绝里，run 未关）；补齐后同一 `runId` 重提成功，报告首块给场景四轴、判定、证据 |
| 6-1 | 两个开关写入设置后重开读回；起 run 默认 `traversal=chain` / `mode=write`；再点「广度」重开读回 `surface` |
| 7-1 | 连接后项目树列出远端目录；远端文件内容一致；终端命令输出回会话且不混入本机路径 |
| 8-1 | 导入后账号进模型列表并带额度；新会话可选到；坏 JSON 有可读拒绝且既有账号不变 |
| 9-1 | 上游加入后模型列表出现其模型；新会话可选到；发消息经本机端口收到请求并回一条答复 |

- **被破坏的行**：无 —— 上表 9 个断言面都不落在本批并入的上游改动上。逐档核对（`git diff 43e05e39 origin/main`）：2-1 / 3-1 的窗口门（`_showNow` / `_showWords` / `WindowVisible`）在 `lib/chat/chat_history_view.dart` 的上游 diff 里零命中；4-1 / 5-1 / 6-1 的 overlay 与 btest 面在 `lib/chat/chat_session.dart` 的上游 diff 里零命中；7-1（SSH）面未被上游触碰；8-1 与 9-1 的用例体尚未落地（行内状态：待假凭证端点 / 假网关 harness），本批不改行；9-1 涉及的 `models_page` / `model_proxy` 上游改动由上游用例 `test/models/proxy/model_proxy_test.dart` 承载。
- **冗余可删的行**：无。
- **缺失需新增的行**：无 —— 两条来路都不成立。上游并入的「修改历史消息时处理文件改动」是上游功能，验收由上游用例承载（`test/chat/rewind_files_prompt_test.dart`、`test/kernel/rewind_files_e2e_test.dart`），不从本仓用户入口长出新业务故事；本批无生产报告。

⇒ 本批收口报 `none`，不改 RTM。

### 2.12 上抛项

7 处补登记是 §3 既定处置的落地，不是新语义；9 处冲突处置都在登记面内。

**`lib/ide/terminal/terminal_view.dart` 补第 7 行（父侧裁决）**：该档带 P6 的同一条守卫（对 `origin/main` 实测 +4 / −1），上游本批触碰的是 `lib/ide/services/terminal_view.dart`，没有触碰该档 —— 它不在 §3.1 的判据域内。补行依据是 §5 第 2 步「对全量 diff 做自有块对账；表外发现自有块时先补第 3 节」，该步不看该档是否被本批触碰；§3.1 的判据域句已写明这条域外补行路径。

## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

审阅面：`docs/batches/2026-11-10-upstream-sync-5.md` §2 与 `docs/design/fork-deltas.md` §3 / §3.1（全文读完）。

判读限制（三条，明写）：① 无 AGENTS.md ⇒ 需求面按评审对象声明与两份文档自带的规则（fork-deltas §1 / §3.1 / §5、批档六段骨架）判；② 无项目标准文档 ⇒ 方法论合规按本评审标准判；③ 无文档地图 ⇒ 文档归属按文档内规则判。④ 源码档在本次评审声明的范围之外（「不要读其它文件」），故 §2.4 档位结论的体量抽测未做，该结论按作者断言记录（unverified）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Methodology · 最近先例（判据 9） | 🟡 | 批档 §2 无「最近先例」行：§2.1–§2.12 为全部节，唯一近似坐标是单条的「同 2026-11-09 批 §2.1 第 7 条三条读数」（只覆盖交付读数）；§2.6 A 引的是规则「`docs/design/fork-deltas.md` §5 第 2 步与 §3.1 的既定处置」，不是先例。`docs/design/fork-deltas.md` §3.1 自己带先例行（「**最近先例**：第 7 节（宿主工具类型复原）与第 8 节」），但批档设计侧的先例调查没有落字。 | 补一行先例坐标：先例批次（2026-11-09 / 11-08 / 11-05 三次 upstream-sync）+ 对应设计档节 + 对齐或偏离理由；若本批不主张先例，明写「无先例」。 |
| 2 | Methodology · 调查证据（判据 10） | 🟡 | 在 §2 全文检索「先例 / 调查证据 / 公开来源」零命中：设计侧没记「查了哪些公开来源、是否相关」，也没有「none relevant」的声明。覆盖只在 `docs/design/fork-deltas.md` §3.1（「**调查证据**：`manifest.index.publicRepos` 为空」），那属登记档面，不属本批设计。 | 在 §2 写同一句结论（`publicRepos` 为空、无独立文档仓；上游经 `origin` 读，属仓内读），或明写「无相关来源」。 |
| 3 | Acceptance（判据 5 / 12） | 🟡 | §2.7 的实跑面只有「`flutter test test/l10n_test.dart` 绿」；本批解了 `lib/bots/bots.dart` 与 `lib/settings/pages/general_page.dart` 的冲突，对应的改动面用例（`test/bots/bots_test.dart` 本批还在 §2.5 刷新读数）没有被点名跑；§2.9 承诺「不修平台路径族既有失败用例…本批只记实跑名单」，但 §2.7 没有记该名单的条目；§2.2 的两处 §3.1 文档改动也没有验收行（§2.7 第 4 条只覆盖「§3 含 6 个新档名，每行实测列 = numstat 读数」）。 | §2.7 点名改动面用例文件（至少 `test/bots/bots_test.dart` + `test/l10n_test.dart`），加一条「实跑名单与既有失败名单」的验收；并为 §3.1 的两处改动（判据域改规则形、生成物规则）各补一行读回判据。 |
| 4 | Acceptance · 可判性 | 🟡 | 条目 1 的机判是「`git status --porcelain` 的 `UU` 行数 = 0」（§2.1 第 1 条，§2.7 第 1 条与 §2.8「`UU` 行数 0，父指针正确」同源），但 `UU` 只记「两侧都改」的冲突，且 `git add` 之后即清零——档内留着 `<<<<<<<` 也会读 0；`AA` / `UD` / `DU` 状态根本不进这个计数。因此「零冲突残留」这个断言没有被它测到。 | 加「`git diff --diff-filter=U --name-only` 为空」+ 冲突标记扫描（`git grep -n '^<<<<<<<' / '^=======' / '^>>>>>>>'` = 0），`UU` 保留作附加读数。 |
| 5 | Document state（fork-deltas §3.1） | 🟡 | §3.1 已改成规则形——「**判据域**：只到共享上游档 —— 本批合并中上游侧触碰的档，档数逐批读 `git diff --name-only <合基> <上游 tip>`，本节不写死档数。」——但同节下游仍写死上一批读数：用例表行「| 正常 | 15 档 numstat | 6 条非零，每条有登记行 |」，以及「**表外补登记的两行**：`README.md`（发售面文案四处）与 `lib/kernel/claude_code/claude_code_transport.dart`（1 行指路注释）。两处都自合基 `99f225c6` 起就存在」。现状是 §3 已有六条「2026-11-11 合并时首次登记（此前表外）」行，且批档 §2.3 读「上游本批触碰 99 档，其中 26 档有自有差异」⇒ 规则形与写死读数在同一节里并存。§2.2 的改动清单（判据域改规则形 + 补生成物规则）不含这两处。 | 用例表行改成规则形（不写固定档数，判据为「每条非零行有登记行」）；「两行」那段改成不绑定批次的表述或删掉，使 §3.1 内不再留任何批次计数。 |
| 6 | Tier check（判据 8） | 🟡 | §2.4 的结论行是「**档位结论：无档跨档**。存量债 11 档名单…成员不变」，排除上游新档的理由写的是「本仓零自有行，不产生登记面，不进名单」；但名单自己的成员判据是体量——「**存量债（过 800 行的上游共享档，`wc -l` 实测）**」。零自有行不是体量读数，故 `bot_groups.dart` / `bot_group_prompt.dart` / `rewind_files_*.dart` / `tool_result_tally.dart` / `claude_resets*.dart` 的「不进名单」缺依据；同表的「9 处冲突档」也是成组一行，没有逐档体量读数。（本次未抽测：源码档在声明范围外。） | 给出上游新到档的 `wc -l` 读数（或明写全部 < 500 行），并把结论行扩成「本批触碰的档里，没有新档越过 500 / 800 行（除 11 档存量债外）」；越过者给拆分方案。 |
| 7 | Registry contract 完整性 | 🟡 | §2.5 六行契约表的列是「文件 | 我们的块 | 接缝 | 行数预算 | 实测（对 `origin/main`）」，没有 `类型` 列；而 fork-deltas §1 要求「确需新增接线时，先登记文件、块、类型、接缝和行数预算，再改代码」，且「类型只用：**修 bug · 功能 · 内核适配**」。已落盘的六行都带类型（五条「功能」、`terminal_panel` 一条「修 bug」），设计侧却没有这五字段中的一项，§5 只能自行判定。 | §2.5 补 `类型` 列，逐行取 修 bug / 功能 / 内核适配 之一，与 §3 已落盘行对齐。 |
| 8 | Branch provenance（判据 6b） | 🟡 | 新登记行「`lib/ide/terminal/terminal_panel.dart` | 标签在按下与菜单之间离场时不崩：`findRenderObject()` 空值判定后早退 | 修 bug」登记的是一条防御分支，而场景没有落字：没有日志行、没有用户报告、没有可复现路径。判据 6b 的 🔴 不成立——本批「产品代码零改写」，分支是搬过来的、本批只登记——但这条块正是「后来没人敢删」的那类。 | 在该行记录场景：观测（日志行 / 报告，引原话）或可复现路径；两者都没有就明写没有，并标为下一轮合并时复核的块。 |
| 9 | Budget 列形态 | 🔵 | §2.5 的「行数预算」列给的是上限（「每类 ≤40 行（`kernel_types` 行同源数据）」「净增 ≤35 行」「净增 ≤3 行」），而 fork-deltas §1 对这六行定的是另一种形态——「**首次登记行的「行数预算」列放实测值**」——已落盘行也按 §1 写了实测（如「对 `origin/main` 实测 +29 / −6」）。同一行于是有两个活着的数（≤35 与 +29 / −6），§3.1 的「各行的实测列 ≤ 该行的行数预算」会指向两个基准。 | §2.5 去掉上限，或显式标为参考上限；判据一律取落盘行的实测值（按 §1）。 |
| 10 | Doc hygiene | 🔵 | 档名是 `docs/batches/2026-11-10-upstream-sync-5.md`，标题却是「# 2026-11-11 · upstream-sync-5」，编制行也写「2026-11-11」；§2 有两条状态行并存：「**状态行**：（eng-designer 写入时更新）」与「**状态行**：设计完成」。 | 文件名与内文日期对齐；只留一条状态行（骨架那条），避免机读拿到两个值。 |
| 11 | Reference form（判据 13） | 🔵 | 被审的 §3 里，六条新行按符号命名（合规），但周边旧行仍按位置引用：「thincoder 设置组（`:442-457`，接线点 ⑦）」「`_offered` `:281-285`」「`lib/ide/ide_editor.dart:2638-2641`」等；文档自己的 §5 也把行号降为定位用（「行号只作定位参考」）。本批不新增这类引用。 | 本批不动；下次触及这些行时改写成符号名（与新六行同形）。 |
| 12 | Clarity · l10n 读数 | 🔵 | §2.1 第 3 条的机判以「生成前：`app_en.arb` 4786 键」起句，而两个 arb 当前处于冲突态（§1「MERGE_HEAD 在、工作树带冲突标记」）⇒「生成前」可被读成「此刻」，也可能读成「键并集后、`gen-l10n` 前」。 | 改写为「键并集后、`flutter gen-l10n` 前」，让 §5 测的是目标状态。 |
| 13 | Integration delta 的证据形态 | 🔵 | §2.11 断言「9 行的断言面…都不落在本批并入的上游改动上」，但没有列出这 9 行各自的断言面；同一份文档的 §8.4 是列出逐行断言面的形态（「| 1-1 | 五次切换各起一个进程（假件 `start` 计数）…」）。于是这条 delta 是断言而非读回。 | 按 §8.4 的形态把 9 行逐行列出断言面；结论（收口报 `none`）可以不变，但依据要可核。 |

计数：🔴 0 · 🟡 8 · 🔵 5。

结论：无 🔴。设计把 9 处冲突的逐档处置、l10n 键并集与重产、六处表外补登记、两处读数刷新都写成了机判条目，处置口径与 fork-deltas §1 / §5 一致，改动落在拥有该主题的文档（§3 / §3.1）且不新建文件，集成面的 RTM delta 有起句有理由。上面 8 条 🟡 与 5 条 🔵 是收紧项：其中第 4、5 两条影响「解完了没有」与「规则形改干净了没有」的可判性，建议在 §5 之前顺手补掉。

VERDICT: pass

### 轮次 2（评审子代理）

审阅面：`docs/batches/2026-11-10-upstream-sync-5.md` §2 与 `docs/design/fork-deltas.md` §3 / §3.1（全文读完）。轮 2 范围 = 轮 1 的 13 条裁决落点 + 两处上抛裁决，不另寻新问题。

**落地核对（13 条）**

| 轮 1 # | 落点（本轮读回） | 状态 |
|---|---|---|
| 1 | §2 头「**最近先例**：同一形的先例 = 前三次 `upstream-sync` 合并批」+「偏离：无 —— 本批只换档与读数」 | 落 |
| 2 | §2 头「**调查证据**：`manifest.index.publicRepos` 为空…查过，无外部相关来源」 | 落 |
| 3 | §2.7 第 9 条点名 `test/bots/bots_test.dart` + `test/l10n_test.dart`；第 10 条实跑名单与既有失败（平台族 #192 / #195、`fold_view_test`，后者在 fork-deltas §3 有同源记录）；第 11 条为 §3.1 两处改动各给读回判据 | 落 |
| 4 | §2.1 第 1 条 · §2.7 第 1 条 · §2.8 三处同形：`git diff --diff-filter=U --name-only` 为空 + 冲突标记扫描 = 0，`UU` 降为附加读数 | 落 |
| 5 | §3.1 用例表行改「档数逐批读，不写死」；「表外补登记的两行」段全文 0 命中；§3.1 判据域为规则形 | 落（§2.2 侧残留，见下表 #1） |
| 6 | 两张 `wc -l` 读数表在（上游新到档 7 行、冲突档 9 行）；结论只到 800 线 | 部分（见下表 #2） |
| 7 | §2.5 表头含 `类型`，7 行逐行给值（5 功能 / 2 修 bug），与 §3 落盘 7 行同值 | 落 |
| 8 | §2.5「`terminal_panel` 行的场景」引 P6 原文（「缺陷修：`findRenderObject()!` 强转，目标滚出视口/被移除即崩」） | 落 |
| 9 | §2.5 表头「行数预算（参考；判据取「实测」列）」；7 行实测列与 §3 各行行数预算列逐行同值 | 落 |
| 10 | §2 只剩一条状态行；档名不改有裁决补记与理由 | 落 |
| 11 | 按裁决本批不动（无落点） | 依裁决 |
| 12 | §2.1 第 3 条「键并集后、`flutter gen-l10n` 前」 | 落 |
| 13 | §2.11 九行断言面表 + 被破坏 / 冗余 / 缺失三问 | 落 |

**上抛裁决落地**

- 1 `terminal_view` 第 7 行：`docs/design/fork-deltas.md` §3 表内已有 `lib/ide/terminal/terminal_view.dart` 行（实测 +4 / −1，2026-11-11 首次登记）；§2.1 第 4 条已改「表外 7 处自有块补登记」并列出 7 个档名；§2.7 第 4 条「含 7 个新档名」；§2.5 七行实测列与 §3 逐行同值；§2.12 记了裁决依据；§3.1 判据域句写明域外补行路径并以该档为例。落。
- 2 存量债名单不改：十一档未动；§2.4 结论收窄到「没有新档越过 800 行」；承诺项 §6 未落字（见下表 #3）。

判读限制：源码 / 测试档在本次评审声明的范围之外，故 §2.4 的 `wc -l` 读数与 §2.5 的实测列按作者断言记录（unverified）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Document state（裁决 #5 落点） | 🟡 | §2.2 第一条仍以现在时写 fork-deltas §3.1 的「现文写死「本批 = 合并触碰的 15 档」」，而同一轮已在 §3.1 落成「本节不写死档数」——两档对同一节给出两个不同的现态。裁决 #5 的改动侧落了，描述侧没跟。 | 把 §2.2 第一条改成改后形态，或写明该节改动已落盘，使 §2 不再持有目标档的改前快照。 |
| 2 | Tier check（裁决 #6 落点） | 🟡 | 结论只到 800 线：「本批合并中上游侧触碰的档里没有新档越过 800 行（最大 `bot_groups.dart` 753）」——753 落在 500 档线之上而没有拆分复核结论，500 线在结论里没有名字；同句「最大」紧接 `bots.dart` 1367 / `general_page.dart` 842，可被读成全体最大值。 | 结论里点明 500 档线，并给 `bot_groups.dart` 753 的拆分复核结论（零自有行的上游新档 / 记候选）；「最大」限定为「新档内最大」。 |
| 3 | Coordination（上抛裁决 2 的承诺项） | 🔵 | 名单侧已落（十一档未动、结论收窄），但承诺「名单的非闭合性记 §6 为已知状态」尚无落点（§6 现为空段）；名单外过 800 的具体一例是 `general_page.dart` 842（§2.4 已点名，处置「本批只解冲突、不拆档」）。设计侧无改动。 | 在 §6 记一条：`general_page.dart` 842 越过 800 而不在十一档名单内，名单不闭合为已知状态。 |

计数：🔴 0 · 🟡 2 · 🔵 1。

判读：两条 🟡 是轮 1 裁决的落点残留（描述侧未跟、500 档线未落），🔵 是 §6 的承诺项；13 条裁决与两处上抛的可实施部分都已落盘，判据串（§2.1 · §2.5 · §2.7 · §3 · §3.1）逐条对得上，无 🔴。

VERDICT: pass

## §4 用户批准（主 agent）

**状态行**：已批准

- 用户 2026-11-11「拉代码更新」= 本批整批授权：合上游 → 解冲突 → 出构建（替换运行实例）。
- 设计评审两轮 pass：轮 1 = 0🔴 / 8🟡 / 5🔵（13 条全受理）；轮 2 = 0🔴 / 2🟡 / 1🔵（13 条落点逐条核对 + 两处上抛裁决落地）。
- 两条 🟡 已在实施前修掉（§2.2 改后形态、§2.4 500 线 + `bot_groups.dart` 复核结论）；🔵 那条（`general_page.dart` 842 记 §6）留收口。
- 实施面 = 9 处冲突 + l10n 键并集与重产；派 eng-coder 按 §2.3 处置表执行。

## §5 实施记录（eng-coder）
**状态行**：实施完成



**轮次与终态**：内部探索审计 1 轮（6 条 gaps，全为记录 / 口径项，无 silent simplification）· 内部 code review 1 轮（0 🔴 · 3 🟡 · 1 🔵，`VERDICT: pass`）· 自修 1 轮（本节 + 口径校正；产品代码零二次改动）· 终态 `clean`。

### 5.1 做了什么

1. 9 处冲突按 §2.3 逐档解（明细见 5.4），解完 `git add`，合成合并提交 `de389d72`（父指针见 5.2）。
2. l10n 两 arb 键级并集；`lib/l10n/app_localizations*.dart` 三档清掉冲突标记后由 `gen-l10n` 整档重产，未手解、未选边。
3. 合并提交内含一次 README 排版修（零改字）：原因、形态与代价见 5.5 第 1 条。
4. 未动 `docs/design/fork-deltas.md`（设计席面，仍在工作树未暂存）；未提交本批档本身。

### 5.2 机器读数（本机实跑，3.47.5 工具链）

| 判据 | 读数 |
|---|---|
| 父指针 | `git log -1 --format=%P HEAD` = `9512b096a5b5… 5f4a1d50b1d5…`（合并提交 `de389d72`） |
| 零冲突残留 | `git diff --diff-filter=U --name-only` = 0 行；冲突标记扫描 `git grep -nE '^(<{7} \|={7}[[:space:]]*$\|>{7} )'` = 0 行；附加读数 `UU` = 0 |
| arb 键数（不含 `@@locale`） | en 4786 · zh 3810；含 `@@locale` 时 en 4787 / zh 3811 |
| 消息键 | 两侧各 3808，逐键相等（en-only 0 / zh-only 0） |
| 并集完整性 | 我方独有 en 101 / zh 55、上游独有 en 49 / zh 36，逐键在盘（缺失 0）；同名键取值不同者 = 0，§2.8 的「同名键取上游措辞」本批无实例 |
| 生成物 | `gen-l10n` 连跑两次，三档 md5 逐档一致（`3ffc361f…` / `8a24b675…` / `f7bdfdf9…`）；随后 `git status --porcelain lib/l10n/` 空 = 零手改残留 |
| analyze | `flutter analyze --no-pub` = **error 0**；11 条（2 warning + 9 info）与基线同组 |
| 26 档对账 | 上游 `43e05e39..origin/main` 触碰 99 档，其中对 `origin/main` 非零 = **26 档**，逐条命中 `docs/design/fork-deltas.md` §3 的行（生成物 3 档由 arb 行承载） |

**9 处冲突档的 numstat（对 `origin/main`）**：

| 档 | numstat | 档 | numstat |
|---|---|---|---|
| `README.md` | +10 / −4（含 5.5 第 1 条的排版修） | `README_CN.md` | +4 / −3 |
| `lib/bots/bots.dart` | +6 / −6 | `lib/settings/pages/general_page.dart` | +100 / −8（净 92 ≤93） |
| `lib/l10n/app_en.arb` | +258 / 0 | `lib/l10n/app_zh.arb` | +55 / 0 |
| `lib/l10n/app_localizations.dart` | +330 / 0 | `app_localizations_en.dart` | +228 / 0 |
| `app_localizations_zh.dart` | +221 / 0 | | |

**其余 17 档非零**（逐条命中 `docs/design/fork-deltas.md` §3 的行）：

| 档 | numstat | 档 | numstat |
|---|---|---|---|
| `release.yml` | +4 / −2 | `docs/release.md` | +42 / −7 |
| `chat_history_view` | +337 / −26 | `chat_session` | +178 / −71（净 107） |
| `context_usage_panel` | +7 / 0 | `side_panel_view` | +10 / −3 |
| `ide_agent_edits` | +29 / −6 | `ide_editor` | +11 / −5（净 6） |
| `terminal_panel` | +3 / −1 | `claude_code_kernel` | +7 / −6 |
| `claude_code_transport` | +1 / −1 | `kernel_registry` | +12 / −1 |
| `kernel_types` | +63 / 0 | `main` | +32 / −5 |
| `workbench` | +56 / −3 | `bots_test` | +39 / −39 |
| `code_citation_test` | +23 / −10（净 13） | | |

### 5.3 实跑名单与既有失败归因（§2.7 第 9 / 10 条）

**基线方法**：`git worktree add /d/baocode-headcheck 9512b096` 并拷 `.dart_tool`，合前合后同命令对比；比完 `git worktree remove --force` 删除，仓内零残留。

| 用例档 | 合后 | 合前 `9512b096` | 归因 |
|---|---|---|---|
| `test/bots/bots_test.dart` | 50 通过 / 0 失败 | — | 冲突面，全绿 |
| `test/chat/rewind_files_prompt_test.dart` | 3 / 0 | 本批新到，无基线 | 上游新档，全绿 |
| `test/l10n_test.dart` | 22 / 1 | 22 / 1 | 同一失败：`every command of the catalog has a Chinese title` 点名 `git.fetchAll`——自有标签 `Fetch and Pull All Repositories` 与上游 arb 措辞 `Fetch From All Remotes` 不一致。既有 |
| `test/kernel_test.dart` | 131 / 5（8 skipped） | 128 / 5（8 skipped） | 同 5 条，平台族（台账 #192 / #195）；+3 通过 = 上游本批新到用例 |
| `test/chat/fold_view_test.dart` | 9 / 1 | 9 / 1 | 同一条，`docs/design/fork-deltas.md` §3 已记「本机合前合后都挂」 |
| `test/settings/settings_wiring_test.dart` | 4 / 4 | 4 / 4 | 同 4 条，均为 `(variant: TargetPlatform.macOS)` 变体 |
| `test/bots/bot_groups_test.dart` | 8 / 1 | 本批新到，无基线 | `a group kept: its members those there are…`：该档 `:80` 写死 POSIX 键 `'/bots/groups/groups.json'`，本机 `p.join` 产出 `/bots\groups\groups.json`（实跑 dart 片段证实）⇒ 平台族、新到档首跑即红，非解冲突所致 |

**本批新增失败（自有代码面）= 0**；失败条目全部落在上表既有 / 平台族归因内。

### 5.4 逐档处置与判据（§2.3 对照）

| 档 | 处置 | 判据实读 |
|---|---|---|
| `README.md` | 取上游 Linux 行，保留我方 ThinCoder 可选装行 | `Ubuntu 20.04` = 1、`Ubuntu 22.04` = 0、`npm i -g thincoder` = 1；numstat 见 5.2 |
| `README_CN.md` | 同上（中文行） | 同上；+4 / −3 |
| `lib/bots/bots.dart` | 取上游列表形，`HostTools.called` / `.server` 留在块内 | `groupPrompt` = 2（声明 + 使用）、`ClaudeSdkTools.called` = 0、`HostTools.called` / `.server` 各 2（块内 1 + `offersTool` 既有 1，见 5.5 第 2 条） |
| `lib/l10n/app_en.arb` · `app_zh.arb` | 键级并集 | 见 5.2 |
| `lib/l10n/app_localizations*.dart` | 不手解，清标记后重产 | analyze error 0；重跑生成器零差异 |
| `lib/settings/pages/general_page.dart` | 两条 import 都留、两组设置并存 | 两行 import 各 1；`EditorContextSetting` 4 处、`RewindFilesSetting` 4 处 |

### 5.5 偏离与口径（交父侧处置，本席无写权面）

1. **README 排版修（已获父侧裁决放行，合并提交内含）**：写本节时文档机检拒写，拒绝项之一是「触达账」`README.md` 的两处 >300 字符段落（徽标 `<a href…>` 348 字符、"Why" 段 536 字符），两段都是存量文本。修法零改字：Why 段在句号处拆成 3 段；徽标改成 `- ` 起头的列表行——**父侧裁决的「挪到标题行」形态机检不过**（标题行与徽标合并成 357 字符段落），故改为列表行，同样零改字。代价：`README.md` 对 `origin/main` 的 numstat 由 +4 / −3 变为 **+10 / −4**，`docs/design/fork-deltas.md` §3 的 `README.md` 行读数需设计席改一次。
2. **§2.3 的 `bots.dart` 计数判据与树不符**：判据写 `HostTools.called` = 1、`HostTools.server` = 1，实为各 **2**（`:491`/`:492` 冲突块内；`:537` 既有的 `offersTool` 查询）。代码正确（上游列表形在盘、`HostTools` 门保留），判据应改成「块内 1」或「≥1」；**不要**为凑数删 `:537` 那行（浏览器工具放行判定）。本席不改 §2、不改代码。
3. **§2.7 第 9 条「`l10n_test` 全绿」未达**：22 / 1，1 条为既有失败（归因见 5.3）。与第 10 条「既有失败列名单」并存时口径需父侧裁一次。
4. **§2.1 第 8 条（构建 + 替换实例）未做**：§2.9 明写属父侧操作步；`build/windows/x64/runner/Release/data/app.so` 的 mtime 仍是 2026-11-10 06:45，早于本次合并。
5. **code review 的 🟡 全在措辞 / 判据面，无代码改动**：
   - ① 上游 1.9.4 新键 `generalSettingsRewindFilesDescription` 向用户说「Claude Code and BaoCode agent only」，本 fork 只有 `claude-code` / `thincoder` 两内核（`lib/kernel/kernel_registry.dart`），设置页因此出现本仓不存在的 agent；本批按 §2.3「两侧新增键全留」与 §2.9 未改上游措辞。
   - ② `README.md` 的发版句（CI 在 `v*` 标签推送时发布）与 `docs/release.md` 首行、`.github/workflows/release.yml` 的 fork 注释相反——合前即如此，非本批引入。

### 5.6 文件面

- 本席改动 = 4 个冲突档 + 2 个 arb + 3 个生成档，均在派单声明面内；合并提交另含上游 99 档（合并必然，非手改）。
- **表外改动：无**。
- 未纳入本次提交：`docs/design/fork-deltas.md`（未暂存）、本批档（未跟踪）——留给父侧批档提交。
- 临时物：`/d/baocode-headcheck` 基线 worktree 已删，仓内零残留。

## §6 验证与收口（父代理）

**状态行**：已收口 2026-11-11

- **合并形态**：`de389d72`，第一父 `9512b096`、第二父 `5f4a1d50`；上游 47 个提交（1.9.3 → 1.9.5）、99 档；`git diff --name-only --diff-filter=U` = 0；冲突标记扫描 = 0 行；`UU` = 0。
- **冲突处置**：9 档按 §2.3 解开 —— `README` / `README_CN` 取上游 Ubuntu 20.04 并保留自有 ThinCoder 行；`bots.dart` 取上游列表形（`groupPrompt`）且 `HostTools` 门留在块内；两个 arb 键级并集；三个生成档由 `flutter gen-l10n` 重产（连跑两次三档 md5 一致）；`general_page.dart` 两条 import 并存。
- **l10n**：en 4786 / zh 3810 键（不含 `@@locale`），消息键两侧各 3808、逐键相等；自有独有 en 101 / zh 55、上游独有 en 49 / zh 36 全在盘。
- **登记面**：`docs/design/fork-deltas.md` §3 补 7 行（`.github/workflows/release.yml` +4/−2 · `README_CN.md` +4/−3 · `docs/release.md` +42/−7 · `context_usage_panel.dart` +7/0 · `ide_agent_edits.dart` +29/−6 · `terminal_panel.dart` +3/−1 · `terminal_view.dart` +4/−1）；刷新 2 行（`bots_test` +39/−39、l10n 三读数）；`README.md` 行改 `+10 / −4` 并注「格式差异，语义不变，可直接弃块」。
- **静态检查**：`flutter analyze --no-pub` = **error 0**；11 条（2 warning + 9 info）与基线同组。
- **实跑名单（§2.7 第 10 条）**：`bots_test` 50/0 · `bot_groups_test` 8/1（平台族：用例写死 POSIX 键，新到档无合前基线）· `rewind_files_prompt_test` 3/0 · `l10n_test` 22/1（既有红：`git.fetchAll` 自有标签与上游 arb 措辞不一致，合前基线同为 22/1）· `kernel_test` 131/5（同 5 条平台族 #192 / #195）· `fold_view_test` 9/1（既有）· `settings_wiring_test` 4/4（既有 macOS 变体）。**自有面新增失败 = 0**。
- **集成门（父侧收口门）**：`test/integration/chat_flows_test.dart` + `btest_flows_test.dart` = **6 过 / 0 挂**。
- **构建**：`dart run tool/build_windows.dart --patched-engine --remote-built`，230.7 s。`build/windows/x64/runner/Release/data/app.so` = 2026-11-11 21:25（晚于合并提交）；安装器 `build/installers/BaoCode-1.9.5-setup.exe`（46.7 MB）；`pubspec.yaml` = `1.9.5+31`。
- **实例替换**：旧 Release 实例（PID 37892）已关，新实例启动读数记在交付报告；`baocode-browser-host` 由新实例自行拉起。
- **README 排版修追认**：裁决要求「徽标挪到标题行」，实测该形态仍组成 357 字符段落、机检不过；最终形态 = 徽标改成 `- ` 起头的列表行 + Why 段按句号拆 3 段，**零改字、零增删**。目标（机检清零且语义不变）达成，形态差异在此追认。
- **已知状态（三条，均不阻塞）**：① `general_page.dart` 842 行越过 800 而不在存量债十一档名单内 —— 名单不闭合，属另一次清理，本批只解冲突、不拆档；② `bot_groups.dart` 753 行落在 500 行审阅带，复核结论 = 本批不拆、记候选（零自有行，拆则两半都成常驻 fork 差异）；③ 上游文案两处（`generalSettingsRewindFilesDescription` 提到本仓不存在的 agent；README 的 tag 发版句与 `docs/release.md` / `release.yml` 注释相反）—— 前者按 §2.9 不改上游措辞，后者合前即如此。
- **集成索引**：`test/RTM.md` 9 行 / 50–100；本批 delta = none（9 条既有用例的断言面都不落在本批改动上；上游新功能的验收由上游自带用例承载）。
- **用户面同步**：并入的上游界面（设置 → 通用的「修改历史消息」组、群聊 prompt、工具结果计数）是上游实现，本仓零改写。
- **暂缓批复核**：无。
- **doc-check gate**：PASS（`docs/batches/2026-11-10-upstream-sync-5.md` · `docs/design/fork-deltas.md`）。
- **台账**：`#237`（本批）随收口核销；派生两条记账 —— `bot_groups.dart` 753 的拆分候选、存量债名单不闭合（含 `general_page.dart` 842）。
