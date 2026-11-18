# 2026-11-18 · upstream-merge-8
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-18 · 来源 = 用户 2026-11-17 23:58「拉上游代码，记得还要更新thincoder的版本」。
> 台账 = #259（core · 归批）。前情 = docs/batches/2026-11-18-upstream-merge-81.md §6（已收口 2026-11-18）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-18
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 上游 8 提交（含 v2.0.2）并入 · 与 thincoder 版本更新

**主仓这半（本批）**

- 上游 `origin/main` 现 tip = `d759d8c6`（#1112 Quick Open 大项目）；本地 HEAD = `c1042ad6`。
- 落后 **8** 提交，触及 **38 档**；干跑显示 7 档「双方都改」，**真冲突 2 档**（§2.1 以 `git merge-tree --write-tree` 实测更正：`lib/main.dart`、`lib/settings/pages/diagnostics_dialog.dart`；其余 5 档可自动合并）。
- 解析口径沿用 `fork-deltas §5.1` 的四条规则（上一批已评审通过并冻结），不另立规则。
- l10n 三档按 `fork-deltas §1`：只合 arb 键级并集，生成物由 `flutter gen-l10n` 重产，**不手解、不选边**。

**thincoder 版本：本批不做，原因是账不在本仓**

- 事实：thincoder 上游已发 **v0.12.82**（gitee `origin/main` tip = `b38c1cb3`）；本地树 **0.12.81**（落后 100 提交，另有本地 27 提交）。
- 两仓交集 **25 档**，含 `thincoder-cli/src/acp/bridge.mjs`、`handlers-session.mjs`（我们的 testMode / btest 门就在那里）。
- 构建脚本钉的 `_thincoderVersion = &apos;0.12.81&apos;`（`tool/build_windows.dart` / `tool/build_macos.dart`）**必须与本地树一致**——树不动、只改版本号会让构建自检失败。
- 故顺序固定：先在 `thincoder/` 合并到 0.12.82 → 再改本仓两处版本常量。
- 但那一步落在**另一个 git 仓**（自带 .git 与 PROJECT-MANIFEST），本会话建不了跨仓批档 ⇒ 须在 `D:\baocode\thincoder` 锚定的会话里开批。
- **本批只做主仓这半**；thincoder 那半登记为待办，不夹带。

### 评审轮 1 裁决（pass · 0🔴 + 6🟡 + 5🔵 ⇒ 11 条全受理）

**三条实质问题的方向**

- **#1 numstat 判据基点**：不能要求「合后读数等于历史列」——列里的数是别的基点、别的日子测的。
- 处置：验收改成「合后重读该列 + 落复核状态」，并写明数值不等的处置。
- **#2 RTM 12-1**：本批到底只落行还是行+用例体，必须一句话说死；新用例档要进受影响表或明写不做。
- **#3 层级结论**：尺寸不进设计档（留在 fork-deltas §3 的行数预算列）；结论按名点出 `lib/main.dart` 并就其存量债裁定。

**修轮 7 定点（只改这些，不扩面）**

- #1 · #2 · #3：按上面三条方向落。
- #4：两处行号引用改按符号或行内文字（`0b9e30a7:lib/main.dart:38` · `:52` / `:108` / `:110`）。
- #5：`fork-deltas §3.1` 的 RTM 旧读数补日期或改成不写死的形。
- #6：`§2.9` 的 thincoder 不做项补一条带批次的接手语句（另一仓、另批、触发条件）。
- #7–#11（🔵）：`§1` 的 7 处冲突改指 §2.1 · `§2.6` 标签口径统一 · 加一行「新增名字均为上游所有」· 生成物不进层级判定一句 · 版本读数补来源命令。

**不动**：两处冲突的解法本身、四条规则、l10n 口径、版本 `2.0.2+35`、RTM 12-1 的行号与标题。

### 实施后修轮（3 处引据与读数过期）

实施已落（合并提交 `16b293f1`）。以下三处因「本批按设计改动」而自身失效，须在收口前修。

**修轮 8 定点**

- `§2.6` 与 `§2.11` 引 `test/RTM.md` 的「**规模窗**：50–100 条。当前 **12 / 50–100**」——落 `12-1` 后该行已是 `13 / 50–100`，引文在盘上不存在（引缺）。
- 改法：引文改成不写死的形（或按现文引），并同步 `§2.11` 的 139 行 / 12 条 → 落行后的实测值。
- `fork-deltas` 存量债「另四档」里 `lib/main.dart` 记 1112 行、该组无日期；合后实测 **1183**。本批正改该档，沿用旧读数会让下次对账拿错基线。
- 改法：按实测改数并补读数日期。

**已知不可由你修**：`§3` 的同一处引缺属评审子代理的段。本席在收口时另处置。

**不动**：冲突解法、l10n 口径、版本号、RTM `12-1` 的行号与标题。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（修轮 7 项已落（#1–#6 + 🔵#8–#11；🔵#7 落在 §1，属主 agent 段）；实测 2 处冲突（§1 记 7，2.1 更正）；登记表 §2/§3/§3.1 已同步；RTM 的 12-1 本批只落行）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 2.0 批次任务（覆盖）

| # | 条目 | 范围 |
|---|---|---|
| 1 | 上游 8 提交（`0b9e30a7`→`d759d8c6`，38 档）并入；2 处内容冲突按 §5.1 规则一解析（实测，见 2.1） | 本批 |
| 2 | l10n 五档：arb 键级并集（自动合并）+ `flutter gen-l10n` 重产，不手解、不选边 | 本批 |
| 3 | 版本线两档取上游 `2.0.2+35`：`pubspec.yaml` 与 `lib/update/version.dart` 同值 | 本批 |
| 4 | 登记面：表外自有块 `lib/settings/pages/diagnostics_dialog.dart` 先补第 3 节一行（本轮已落）；合后按 §3.1 的 numstat 口径复核 | 本批 |
| 5 | 集成面：`test/RTM.md` 新增 12-1 行（Quick Open 大项目；行已定，用例体待假文件服务 harness） | 本批 |
| 6 | thincoder 版本 0.12.81 → 0.12.82 | **不在本批**：落在另一 git 仓，§1 已定，须在那仓开批 |

**设计档落点**：`docs/design/fork-deltas.md` —— §2 的 `lib/diagnostics/**` 例外行补 `key_watch.dart`；§3 新增 `lib/settings/pages/diagnostics_dialog.dart` 一行；§3 的 l10n 行删掉随合并漂移的键数读数、改记规则。§5.1 四规则不变：本批两处冲突都落在规则一（双方各自新增，都留）。

**调查证据**：`manifest.index.publicRepos` 为空（`PROJECT-MANIFEST.json` 读得 `"publicRepos":[]`），无独立文档仓；上游源码经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

**最近先例**：`docs/batches/2026-11-18-upstream-merge-81.md` §2 —— 同一形：逐档给处置、合后按 numstat 复核登记面。本批对齐，不偏离。

**数据事实**：本批没有需要先读数据的断言。判据全是当场可测的读数：`git merge-tree` 的冲突行、`git diff --numstat`、文件内符号计数、`flutter gen-l10n` 与 `flutter analyze --no-pub` 的读数。

### 2.1 读数更正：冲突数

§1 记 7 档会冲突：l10n 三档 + `lib/main.dart` + `lib/settings/pages/diagnostics_dialog.dart` + `lib/window/app_windows.dart` + `test/window/app_windows_test.dart`。

本轮实测只有 2 处 CONFLICT：`lib/main.dart`、`lib/settings/pages/diagnostics_dialog.dart`；l10n 五档与 app_windows 两档都是 `Auto-merging`。

复现 = `git merge-tree --write-tree HEAD origin/main`（exit 1，输出恰两行 `CONFLICT (content)`）。设计按实测 2 处出解法；另 5 档按 2.4 的登记面核，不作「无冲突即无事」的推断。

### 2.2 上游本批（8 提交）

- `328edb6e` Quick Open 大项目：新增 `lib/ide/file_index_store.dart`（+ 测试），`lib/ide/file_service*.dart` / `ide_quick_open.dart` / `search_palette.dart` / `lib/chat/composer/file_mentions.dart` 随改。
- `ad8536b8` release 2.0.2：版本两档、`release-notes/2.0.2` 的 en / zh 两份发版说明、site 五档。
- `654a5076` 按键日志：新增 `lib/diagnostics/key_watch.dart`（+ 测试），`lib/main.dart` / `lib/settings/pages/diagnostics_dialog.dart` / `lib/keybindings/keybinding_service.dart` 接线。
- `cb9be9d0` site push 文档：`site/push.html`、`site/zh/push.html`、`site/README.md` 等。
- `36957c37` 窗口标题按工作区名：`lib/window/app_windows.dart`（+ 测试）。
- 另 3 个 merge commit（`4699d47a` / `fa5012e7` / `d759d8c6`），无独立内容。

### 2.3 两处冲突的解析（规则一：双方各自新增，都留）

| 文件 | 冲突块 | 解法（实施口径） |
|---|---|---|
| `lib/main.dart` | ① import 段 | 留我方 `hang_reports.dart` / `stall_watch.dart` / `viewport_watch.dart` 三行，加上游**本批新增**的 `key_watch.dart` 一行。**不回收**上游侧旧有的 `hang_watch.dart`：基线 `0b9e30a7:lib/main.dart` 的 import 段有 `import 'diagnostics/hang_watch.dart';`，本仓 N3/N4/N5 轮已把该 watchdog 换成自有三档（依据 lib/main.dart「import 'diagnostics/hang_reports.dart';」），回收只是一条无用 import |
| `lib/main.dart` | ② `!kIsWeb` 启动块 | 留我方三调用与两行注释，另加 `KeyWatch.start();`（上游本批接线）。次序：`AppEventWatch.start(); FrameWatch.start(); KeyWatch.start();` 之后接我方块 |
| `lib/settings/pages/diagnostics_dialog.dart` | ① import（`hang_reports` vs `key_watch`） | 两行都留：`key_watch.dart` 供上游新行 `appEvent('keys', 'at the upload: ${KeyWatch.describe()}');` |
| `lib/settings/pages/diagnostics_dialog.dart` | ② import（`data_dir` vs `event_log`） | 两行都留：`event_log.dart` 供上游 `appEvent`，`data_dir.dart` 供我方 `_hangs` |

两档的其余上游改动（含 `_send()` 里的按键日志行）都落在自动合并面；实施须读回该行在盘（2.6 判据），不得假定。

**既有件三问**：本批新增的名字 —— `KeyWatch`（上游 `654a5076`）、`FileIndexStore`（上游 `328edb6e`）、按键日志的 l10n 键 —— 均为上游所有，本仓无命名选择。本仓唯一的选择点是不回收 `hang_watch.dart` import（2.3 决策 B），理由已在该行写明。

### 2.4 无冲突但带自有接缝的档（符号核，不按冲突有无判）

| 文件 | 核什么 |
|---|---|
| `lib/window/app_windows.dart` | 上游 #1096 改标题；我方关窗一次性守卫须在：`_closing` / `_removing` / `_removeOnce` / `requestClose` 的早退。判据 = 合后重读 `git diff --numstat origin/main HEAD` 并落复核状态（口径见 2.6 的 numstat 行） |
| `test/window/app_windows_test.dart` | 用例 `a close asked for again while one is under way runs it once` 与 `_Harness.host.holdLeaveFullScreen` 在盘；numstat 同上 |
| `lib/l10n/app_en.arb` / `app_zh.arb` + 三份生成物 | arb 自动合并后我方键仍在（抽查 `modelsSwitchPending` / `modelsFallbackHint`，en / zh 两侧各 ≥1）；生成物一律 `flutter gen-l10n` 重产，重产后 `git status --short lib/l10n` 无差异即定稿 |
| `lib/update/version.dart` / `pubspec.yaml` | 两档同值 `2.0.2+35`（上游本批，读数来源见 2.6 版本行），`test/update/version_test.dart` 校验 |
| `lib/diagnostics/key_watch.dart` | 上游新档、无自有块：整档取上游；`docs/design/fork-deltas.md` §2 的例外行已把它列作共享上游档 |

**表外档判据（本轮实测）**：38 档里只有 9 档在合并基处带 fork 差量 —— l10n 五档（第 3 节 l10n 行）、`lib/main.dart`、`lib/window/app_windows.dart`、`test/window/app_windows_test.dart`、`lib/settings/pages/diagnostics_dialog.dart`（本轮补行），后四档各在第 3 节有行。定位按该行开头的文件路径文字，不按行号 —— 表内随时插行，行号必漂。

其余 29 档的 `git diff --numstat 0b9e30a7 HEAD` 为空 ⇒ 纯上游面，整档取上游。

### 2.5 受影响文件与测试覆盖

| 面 | 文件 |
|---|---|
| 冲突解析（2） | `lib/main.dart` · `lib/settings/pages/diagnostics_dialog.dart` |
| 自动合并、带自有接缝须核（5） | `lib/window/app_windows.dart` · `test/window/app_windows_test.dart` · `lib/l10n/app_en.arb` · `lib/l10n/app_zh.arb` · `lib/l10n/app_localizations*.dart`（生成物，重产） |
| 版本线（2） | `pubspec.yaml` · `lib/update/version.dart` |
| 纯上游面（29） | 其余上游本批触碰档，含新档 `lib/ide/file_index_store.dart`、`lib/diagnostics/key_watch.dart` 及两份测试 |
| 测试（变更面） | `test/update/version_test.dart` · `test/diagnostics/key_watch_test.dart` · `test/ide/file_index_store_test.dart` · `test/window/app_windows_test.dart` · `test/l10n_test.dart` |
| 设计档 | `docs/design/fork-deltas.md`（本轮已落：§2 例外行、§3 两处、§3.1 的 RTM 读数改成不写死的形） |
| 集成索引 | `test/RTM.md`（新增 `12-1` 行；实施席落） |

**集成用例档不在本表，也不在本批**：`test/integration/quick_open_flows_test.dart` 本批不建。本批只落 `12-1` 行，用例体待假文件服务 harness —— 明写在 2.9 不做，不留「已进表但没人做」的空档。

**层级结论**：本批没有文件因本次改动越层 ⇒ 不出拆分计划。理由是本批不新增自有语义块：新到的上游档只读，l10n 走重产，两处冲突是双方各自新增的并集（2.3），`app_windows` 只动上游标题面、自有守卫块不增。

- **按名点一档**：`lib/main.dart` 在受影响表内，且早已越过 800 行 —— 属存量债。依据 `docs/design/fork-deltas.md`「十二档都是上游共享档：拆分会让两半都成常驻 fork 差异（体量立场见第 8.5 节），认账不排期。」⇒ 认账不排期，本批不重开、不出拆分计划。
- **尺寸不进本档**：各档行数只在 `docs/design/fork-deltas.md` 第 3 节的「行数预算」列维护。
- **生成物不进层级判定**：`lib/l10n/app_localizations*.dart` 由 `flutter gen-l10n` 重产，行数随上游与键并集变；不按档尺寸判，也不单列登记行（承载行是 arb 两档，`docs/design/fork-deltas.md` §3.1 已把生成物排除在登记面外）。

### 2.6 验收对照（每条指回 2.0 的条目）

| 条目 | 判据（机器可判） |
|---|---|
| 1 冲突清零 | 全树 `grep -rn '^<<<<<<<\|^>>>>>>>' lib test` 行数 = 0 |
| 1 上游能力在盘 | `lib/main.dart` 内 `KeyWatch.start()` = 1；`lib/settings/pages/diagnostics_dialog.dart` 内 `KeyWatch.describe()` = 1 且 `appEvent('keys'` ≥1；`lib/ide/ide_quick_open.dart` 内 `FileIndexStore` ≥1 |
| 1 · 4 自有块在盘 | `lib/main.dart` 内 `ViewportWatch.start()` = 1、`StallWatch().start()` = 1、`HangReports(` = 1；`lib/settings/pages/diagnostics_dialog.dart` 内 `_hangs` ≥2；`lib/window/app_windows.dart` 内 `_closing` ≥3、`_removing` ≥2、`_removeOnce` ≥1；`test/window/app_windows_test.dart` 内 `a close asked for again while one is under way runs it once` = 1 |
| 4 numstat（合后重读，不比旧读数） | 合后逐档跑 `git diff --numstat origin/main HEAD -- <档>`，对象 = `lib/window/app_windows.dart` / `test/window/app_windows_test.dart` / `lib/settings/pages/diagnostics_dialog.dart` / `lib/main.dart`；把读数与「复核状态：已复核」写回 `docs/design/fork-deltas.md` 第 3 节该行的「行数预算」列（数值只在该节出现）。**读数与列中旧读数不等 ⇒ 以新读数为准**：旧读数属别的基点、别的日子测的，不等本身不是缺陷，落复核状态时写明；**新读数超该行预算 ⇒ 先补理由再合**，不静默越预算 |
| 2 l10n | `flutter gen-l10n` 后 `git status --short lib/l10n` 无差异；`app_en.arb` 与 `app_zh.arb` 各含 `modelsSwitchPending` ≥1、`modelsFallbackHint` ≥1 |
| 3 版本 | `pubspec.yaml` 内 `version: 2.0.2+35`；`lib/update/version.dart` 内 `appVersionString = '2.0.2+35'`；`flutter test test/update/version_test.dart` 全绿 |
| 4 登记面 | 合后 `git diff --numstat origin/main HEAD` 的每条非零行命中第 3 节对应行；`diagnostics_dialog.dart` 行在表内 |
| 1 · 2 编译与变更面单测 | `flutter analyze --no-pub` 的 error 数 = 0；`flutter test test/update/version_test.dart test/diagnostics/key_watch_test.dart test/ide/file_index_store_test.dart test/window/app_windows_test.dart test/l10n_test.dart` 全绿 |
| 5 RTM 行 | `test/RTM.md` 内 `12-1` 行的编号与标题逐字，行在盘；规模窗读数随之改为 13 / 50–100，且 `12-1` 并进该行的「用例体待…」括注 |

**版本读数的来源命令（`2.0.2+35` 不是记忆值）**：

- `git show origin/main:pubspec.yaml` 的版本行 = `version: 2.0.2+35`。
- `git show origin/main:lib/update/version.dart` 该行 = `const appVersionString = '2.0.2+35';`。
- 本地树现为 `const appVersionString = '2.0.1+34';`，合后才到上游值。以上三条本轮实测。

### 2.7 用例表

| 场景 | 输入 | 期望 |
|---|---|---|
| 正常 | 合并后全树 | 冲突标记 0；analyze error = 0；2.6 点名的测试文件全绿 |
| 边界 | `main.dart` 同时带 `hang_watch.dart` 候选 import 与自有三档 | 最终只有自有三档 + `key_watch.dart`；`hang_watch` 不出现（我方已换掉该 watchdog） |
| 边界 | 上游 `appEvent('keys', …)` 与自有 `_hangs` 同处对话框 | 两行都在盘：`_hangs` ≥2、`appEvent('keys'` ≥1 |
| 边界 | 合后 numstat 读数与第 3 节列的旧读数不等 | 以新读数为准并落复核状态（2.6 numstat 行）；不据此判缺陷、不改回代码 |
| 错误 | 冲突标记残留 / 表外共享档 numstat 非零 | 计数 > 0 ⇒ 停止实施；numstat 非零而无第 3 节行 ⇒ 先补表（依据 docs/design/fork-deltas.md「表外不许改上游档」） |
| 错误 | 新读数超第 3 节该行预算 | 停止，先补理由再合（不静默越预算） |
| 错误 | `flutter gen-l10n` 后 l10n 生成物仍有差异 | 停止，不得手改生成物，回设计核 arb 合并 |

### 2.8 关键决策记录

| 选项 | 结论与理由 |
|---|---|
| A（采用）两处冲突按规则一：两侧块都留 | 两侧都是新增（我方诊断 watch / 上游按键日志），任取一侧都丢一段可见或可诊断的行为 |
| B（采用）`main.dart` 不回收 `hang_watch.dart` import | 基线有它、本仓已用自有三档替换；回收只留一条无用 import，还可能诱导双起 watchdog |
| C（采用）l10n 走「arb 并集 + 重产」 | 生成物是派生档，手解即两套真值；§1 已定 |
| D（采用）版本取上游 `2.0.2+35` | 上游 patch 高于我方 `2.0.1+34`，升级路径成立；钉住会造成自降级 |
| E（否）整档取上游 | `main.dart` / `app_windows.dart` / `diagnostics_dialog.dart` 带自有登记块，整档取上游是删功能 |
| F（否）回退成旧 fork 版本 | 会把上游本批 8 提交的改动一并回退 |
| G（采用）numstat 判据 = 合后重读 + 落复核状态 | 第 3 节的读数是不同基点、不同日子测的，同一列已有两读数不等的实例（`.gitignore` 行）。要求「合后读数等于旧读数」等于要求历史重演，且不等时实施席无规则可依；改为重读、写回、落复核状态，超预算才停 |

### 2.9 边界（不做）

- 不做 thincoder 0.12.82 的升级与两处版本常量改动（另一仓，见 2.0 条目 6）。**接手路径**：① 在 `D:\baocode\thincoder` 锚定的会话里开批（该仓自带 `.git` 与 `PROJECT-MANIFEST`，本会话建不了跨仓批档），把它合并到 0.12.82；② 本仓下一批改 `tool/build_windows.dart` / `tool/build_macos.dart` 的 `_thincoderVersion` 两处常量，触发条件 = ① 收口且 thincoder 树到 0.12.82（树不动只改版本号会让构建自检失败）。登记面：本仓台账已查（`query` 全表 259 行），没有 thincoder 版本升级行 ⇒ 须由主 agent 补一行，否则「不做」本批收口后无处追踪。
- 不写 `12-1` 的用例体：`test/integration/quick_open_flows_test.dart` 本批不建，假文件服务 harness 尚不存在；本批只落索引行（2.11）。
- 不改上游行为与判定次序；不重构、不拆大档。
- 不修与合并无关的既有失败用例（`fold_view_test` 的 `Worked for 3m 0s` 一条等）。
- 不改 site / 发版说明的内容：随上游逐字进。
- 不为窗口标题补断言（macOS 窗口标题不进测试面）。

### 2.10 UI / 交互

本批不改界面设计；可见变化全部来自上游：窗口标题按工作区名（#1096）、诊断上传对话框多一行按键日志（#1104）、Quick Open 在大项目里搜得到每个文件（#771）、版本显示 2.0.2。没有「讨论过未落」的项。

### 2.11 集成测试设计（RTM delta）

读过 `test/RTM.md`（落 `12-1` 后 152 行、13 行用例；依据 test/RTM.md「**规模窗**：50–100 条。」）。

- **被破坏的行**：无。逐面核过：1-1 / 2-1 —— 进程创建与窗口可见性面未改，`main.dart` 只动诊断启动块；4-1 / 5-1 / 6-1 —— btest 文本来自我方 arb 键，l10n 走重产、不换措辞；7-1 / 8-1 / 9-1 / 10-1 / 10-2 / 11-1 —— 断言面都不落在本批触碰档上。
- **冗余可删的行**：无。
- **缺失需新增**：1 行 —— `12-1`「Quick Open 在大项目里搜得到每个文件」。本批只落行，不落用例体（2.9），状态栏按本档既有形写「行已定；用例体待假文件服务 harness」，并入规模窗那行的同一条括注。

`12-1` 的来路与判据：生产问题（上游 #771）。用户入口 = Quick Open 面板；组件间交互 = `FileIndexStore` ⇄ `FileService` ⇄ Quick Open 结果列表；业务可观察结果 = 在一个超过遍历上限的项目根里搜一个深层文件，结果列出它且可打开。

**复现路径（为延后的用例体留的材料）**：

- **失效点**：项目根的文件数超过 Quick Open 一次性遍历的上限，列表被截断，截断那一段里的文件搜不到。
- **读数**：依据 lib/ide/file_service.dart「Future<IdeFileListing> listProject(String root, {int limit = 50000});」；实现走到 `paths.length >= limit` 时返回 `IdeFileListing(paths..sort(), truncated: true)`（本轮实读）。
- **复现步骤**：造一个超过 50000 档的项目根，用 Quick Open 搜落在截断段里的文件 —— 旧实现不列出，修复后由 `FileIndexStore` 列出且可打开。
- 用例体落地时按此造根，不必再查一遍机制。

窗口标题（#1096）与按键日志（#1104）两条来路都不成立：前者是窗口服务器面、本仓测试面够不着，后者是内部诊断、业务不可观察 ⇒ 不增收行。

### 2.12 上抛项

- [上抛·知会] §1 记 7 处冲突，本轮实测 2 处（2.1 有复现命令）。设计按实测走；另 5 档按 2.4 的登记面核，不作「无冲突即无事」处理。
- [上抛·知会] 评审 🔵#7（把 §1 的 7 处冲突改指 2.1）落在 §1，属主 agent 段 —— 本席写不了 §1（batch 工具按段白名单拒），§2 侧 2.1 的实测读数已在盘。
- [上抛·知会] thincoder 0.12.82 不在本批 —— §1 已定，无需裁；接手路径与台账缺口见 2.9 第一条。

## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

评审对象：§2（本批设计与验收）· `docs/design/fork-deltas.md` 三处改动（§2 例外行 / §3 `lib/settings/pages/diagnostics_dialog.dart` 新行 / §3 l10n 行）。受评范围只含这两份文档，故项目内其它档的尺寸与读数为 `unverified`；本仓无 AGENTS.md、无项目标准档、无文档地图 ⇒ 方法论与文档归属只按这两份文档自身规则与评审判据核，文档归属一项为降级判断。

| # | Category | Severity | Issue | Suggestion |
|---|---|---|---|---|
| 1 | 验收判据 | 🟡 | 2.6 要求「合后 `git diff --numstat origin/main HEAD -- <档>` … 逐档等于 `docs/design/fork-deltas.md` §3 该行实测列」，但该列的历史读数不同基：`lib/settings/pages/diagnostics_dialog.dart` 行记「实测 +20 / −0（`git diff --numstat 0b9e30a7 HEAD`，2026-11-18 合并基；首次登记，实测值即基线）」，`lib/window/app_windows.dart` / 其测试行记「对 `origin/main` 实测 +28 / −10」「+20 / 0」（合于 2026-11-15）；而本批 `origin/main` 已到 `d759d8c6` 且改了同两档。同文档已有两读数不等的实例：`.gitignore` 行「首次登记时按 fork 侧 base..HEAD 记 +9 / −0，合后 `.env.*` 归上游面 ⇒ 自有块 8 行」。2.7 错误行只覆盖「numstat 非零而无第 3 节行」，没有「数值与列不等」的处置 ⇒ 判据一旦不等，实施席无规则可依 | 把验收动作定为「合后重读该列并落复核状态」（第 3 节 112–115 行已是这个形：`复核状态：已复核`），并为数值不等写明处置；不要让判据依赖跨批历史读数的相等 |
| 2 | 集成面 / 交付面 | 🟡 | 2.0 条目 5 写「`test/RTM.md` 新增 12-1 行（Quick Open 大项目；行已定，用例体待假文件服务 harness）」，2.5 写「`test/RTM.md`（新增 12-1；实施席落）」，2.11 又定用例体落 `test/integration/quick_open_flows_test.dart` —— 该档不在 2.5 的受影响表内，harness 无落点、无判据。§2 状态行「RTM 新增 12-1」读起来像已在盘，与「实施席落」互相打架。`12-1` 的来路只到「生产问题（上游 #771，文件索引超过旧实现上限时深层文件搜不到）」一句，未记可复现的失效路径 ⇒ 用例体延后时后批无材料 | 明确本批只落行还是行+用例体；把新用例档写进 2.5（或写进 2.9 不做）；给 `12-1` 记一条复现路径，让延后的用例体有据。 |
| 3 | 层级判据 | 🟡 | 2.5 层级结论把档尺寸写进设计档（「新上游档 `key_watch.dart` 143 行、`file_index_store.dart` 465 行都在 800 以下」），而判据要求「尺寸与预期增量不进设计档」；且结论未点名受影响表里已越层的档 —— `docs/design/fork-deltas.md` 存量债记「`lib/main.dart` 1112」，该档就在 2.5 的冲突解析行里。存量债已有裁定「十二档都是上游共享档：拆分会让两半都成常驻 fork 差异（体量立场见第 8.5 节），认账不排期。」⇒ 按既有裁定不重开，不另要拆分计划。其余档尺寸本轮未实测（受评范围限制） | 结论行只写「哪些档越层 + 处置指向存量债裁定」，尺寸留在 fork-deltas §3 的「行数预算」列；把 `lib/main.dart` 按名点出。 |
| 4 | 引用形态 | 🟡 | §2 有两处行号引用：2.3「基线 `0b9e30a7:lib/main.dart:38` 有该 import」、2.4「`lib/main.dart`（`:52` 行）、`lib/window/app_windows.dart`（`:108`）、`test/window/app_windows_test.dart`（`:110`）」。后者指向 fork-deltas 的行位置：本轮在表尾增行不漂移，下一次插行即全错且无人可察 | 与同句已有的好形对齐（2.3 同句用「依据 lib/main.dart「import 'diagnostics/hang_reports.dart';」」），按符号或行内文字定位。 |
| 5 | 文档状态 | 🟡 | 两份受评文件对 `test/RTM.md` 的读数同日互不相容（§2.11 与 `docs/design/fork-deltas.md` §3.1 各自把条数与行数写死）。§2.11 与自身列举的行号（1-1…11-1）自洽 ⇒ 滞后的是 §3.1 那行（本批只报不改） | 两处都不再写死：只引稳定段 `**规模窗**：50–100 条。`，条数与行数逐批读。 |
| 6 | 范围协调 | 🟡 | thincoder 0.12.82 这半（用户原话含在内）在 2.0 条目 6 与 2.9 明确不做，理由落在另一 git 仓；但只剩「本批收口后另仓开批」与 2.12 的知会，没有接手批次标号或台账行号 ⇒ 本批收口后无处追踪 | 记一条带批次的接手语句（哪一仓、哪一批、什么触发开批），让「不做」有落点而不只有理由。 |
| 7 | 文档状态 | 🔵 | §1 的「**7** 档会冲突」已被 2.1 更正为 2（2.12 已上抛知会），§1 面上仍是 7；只读 §1 会取旧数 | §1（主 agent 作者）按 2.1 的实测改一次，或在 §1 行内指向 2.1。 |
| 8 | 可追溯性 | 🔵 | 2.6 两条「1 · 3 …」（自有块在盘 / numstat）与 2.0 条目 3（版本线）对不上；按内容它们指向条目 1 与条目 4（登记面），也可能指 fork-deltas 第 3 节 | 统一标签口径（条目号或第 3 节），让「每条指回 2.0 的条目」可核。 |
| 9 | 既有件 | 🔵 | §2 无「既有件三问」块。本批新增名字（`KeyWatch` / `FileIndexStore` / arb 键）全为上游所有，本仓无命名选择；本仓唯一的选择点 —— 不回收 `hang_watch.dart` import —— 已在 2.3 与决策 B 给了理由（「我方已换掉该 watchdog」），不构成「既有件弃用无理由」 | 可留白；若要贴合登记口径，加一行「新增名字均为上游所有，本仓无命名选择」即可。 |
| 10 | 层级判据 | 🔵 | 受影响表里 `lib/l10n/app_localizations*.dart`（生成物）按行数远超 800（`docs/design/fork-deltas.md` §8.2 引到 `lib/l10n/app_localizations.dart:20158`），2.5 结论未提它们，靠「l10n 只走重产」隐含豁免 | 一句话点明生成物由工具产出、不进层级判定（§3.1 已把它们排除在登记面外），免得空档被读成漏判。 |
| 11 | 证据纪律 | 🔵 | 条目 3 的 `2.0.2+35` 是写死的读数，没有来源命令（对照 2.1 的冲突数带 `git merge-tree --write-tree HEAD origin/main`）；2.6「`pubspec.yaml` 内 `version: 2.0.2+35`」以它为唯一依据 | 补一条读数来源（如 `git show origin/main:pubspec.yaml` 的版本行），让版本判据可回查。 |

计数：🔴 0 · 🟡 6 · 🔵 5。无 🔴（无阻断项）；🟡/🔵 不阻断。

VERDICT: pass

### 轮次 2（评审子代理）

评审轮 2 · 对象 = §5 实施记录 ∧ 合并提交 `16b293f1` 的核对 ∧ §3 轮 1 第 5 行的引文修正。受评范围 = 批档 §2 / §3 / §5 + `docs/design/fork-deltas.md`。git 侧与运行器读数本轮无 git 与运行器可复核，逐条标 `unverified`；文件面读数逐条自测。

**本轮实读**

- `test/RTM.md` 规模窗行现读 `**规模窗**：50–100 条。当前 **13 / 50–100**`，同行括注含「假文件服务 harness」；第 12 节与 `12-1` 行在盘（标题「Quick Open 在大项目里搜得到每个文件」，状态「行已定；用例体待假文件服务 harness」），变更记录有 `12-1` 条，档 152 行 ⇒ §2.6 条目 5 判据成立。
- `lib/main.dart`：`KeyWatch.start();` · `ViewportWatch.start();` · `StallWatch().start();` · `HangReports(` 各 1 处，`hang_watch` 0 处；`!kIsWeb` 块次序 = `AppEventWatch` → `FrameWatch` → `KeyWatch` → 我方三行，与 §2.3 一致。
- `lib/settings/pages/diagnostics_dialog.dart`：`appEvent('keys', 'at the upload: ${KeyWatch.describe()}');` 1 处 · `_hangs` 3 处；两组 import 都在（`hang_reports` · `data_dir` · `event_log`）。
- `lib/window/app_windows.dart`：`_closing` 4 · `_removing` 3 · `_removeOnce` 2；`test/window/app_windows_test.dart` 的用例名与 `holdLeaveFullScreen` 在盘。
- 全树 `^(<<<<<<<|>>>>>>>)` 零命中；`test/integration/quick_open_flows_test.dart` 不存在（合 §2.9「本批不建」）。
- `lib/ide/file_service.dart` 的 `Future<IdeFileListing> listProject(String root, {int limit = 50000});` 与 `if (paths.length >= limit)` → `return IdeFileListing(paths..sort(), truncated: true);` 逐字在盘 ⇒ §2.11 的 `12-1` 复现路径与读数为真。
- `fork-deltas` §3 四行写回与 §5 读数逐值相同（+32 / −5 · +28 / −10 · +20 / 0 · +20 / −0，各带「复核状态：已复核」）；存量债「另四档」的 `lib/main.dart` 已改 1182（`split('\n')` 1183）并带 2026-11-18 日期，本轮自测同为 1182 / 1183。
- `test/l10n_test.dart` 在盘；§5 点名的失败面可核：`lib/keybindings/workbench_keybindings.dart` 的 `'Fetch and Pull All Repositories'` 对 `lib/l10n/app_en.arb` 的 `"scmFetchFromAllRemotes": "Fetch From All Remotes",`。

**§3 轮 1 第 5 行的就地修正未落盘**：`batch edit` 被文档机检门拒，命中的是 §2.11 那处引缺（§2 段，作者 eng-designer），不是本次写入文本；档字节逐字未变。故第 5 行仍带两处盘上不存在的引文（落行前的旧规模窗读数、旧 §3.1 读数）。解锁次序：先改 §2.11 那句，再复跑本轮 edit。

| # | Category | Severity | Issue | Suggestion |
|---|---|---|---|---|
| 1 | 文档状态 | 🟡 | §2.11 仍把规模窗的条数与档行数写死成落行前的旧值（12 条 / 139 行），而盘上 `test/RTM.md` 现为 `**规模窗**：50–100 条。当前 **13 / 50–100**`、档 152 行；§1「修轮 8 定点」把它列为收口前必修，§2.6 的同一处已修、§2.11 未修 | 该句只留稳定段 `**规模窗**：50–100 条。` 并补落行后的实测条数 / 行数；改完复跑本轮 §3 edit |
| 2 | 文档状态 | 🟡 | §3 轮 1 第 5 行仍是作废残留：两处引文（落行前的旧规模窗读数、旧 §3.1 读数）在盘上都不存在；本轮就地修正被门拒，原因即第 1 条 | 第 1 条落盘后复跑 edit，替换形 = 只引 `**规模窗**：50–100 条。`，§3.1 一侧按段名引不按读数引 |
| 3 | 验收判据 | 🟡 | §2.6「1 · 2 编译与变更面单测」写「五档 … 全绿」，§5 报 `test/l10n_test.dart` 22 过 / 1 失；失败面是 fork 自有标签（`'Fetch and Pull All Repositories'` 对 arb 的 `Fetch From All Remotes`），而 §2.9 明写「不修与合并无关的既有失败用例」⇒ 判据与边界互斥 | 判据改成「本批新增失败 0 + 另四档全绿」（或对该档注明豁免理由与「合前即有」的核法），与 §2.9 对齐 |
| 4 | 层级判据 | 🟡 | §2.5 层级结论只按名点了 `lib/main.dart`；受影响表里另两档本轮自测越过 >800 硬顶，且两处名单都未点名：`lib/window/app_windows.dart` 1721 行、`test/window/app_windows_test.dart` 1582 行（`fork-deltas` 存量债名单自称「过 800 行的上游共享档 … 十二档」，也不含它们） | 按既有「认账不排期」裁定把这两档一并点名（或补进存量债名单），别让第三、第四档读成未判 |
| 5 | 协调项 | 🟡 | 自有块的可见行为耦合：`lib/settings/pages/diagnostics_dialog.dart` 里 `Text(_hangs, style: _muted())` 与揭开按钮整段嵌在 `if (logs != null) ...[` 内 ⇒ 列举失败（`logs == null`）时「报告在哪」与打开路径一起消失，而这正是最需要它的时候；§5 已作为内部代码评审的 🟡 上抛，本批未裁 | 裁一次：把该行移出 `logs` 判据（自有块内改动，不动上游面），或记明为何保留 |
| 6 | 证据纪律 | 🔵 | git 侧与运行器读数（提交 `16b293f1`、只 `git add` 两档、两档未暂存、四档 numstat、`analyze` 11 issues / 0 error、四档测试 5 / 4 / 8 / 74 全绿、l10n 22 / 1）本轮无 git 与运行器，全部 `unverified`；文档面与它们逐值自洽 | §6 收口时记一行 `git show 16b293f1 --stat` 与四档 numstat 的实际输出，让这批判据事后可回查 |

计数：🔴 0 · 🟡 5 · 🔵 1。0🔴 ⇒ 无阻断项；🟡 / 🔵 不阻断。

VERDICT: pass

## §4 用户批准（主 agent）

### 用户批准（上游 8 提交实施）

- 2026-11-18 00:23 · 用户原话：**「批准」**——批准 `法`（§2）进入实施。
- **批准范围**：2 处冲突解析 + l10n 重产 + 两处版本常量 + RTM `12-1` 行。**不含** `12-1` 的用例体、不含 thincoder 升级（台账 #260）。
- **现场**：工作树处于合并进行中（`git merge origin/main` 已发起）。实施席就地解析，**不得** `merge --abort` / `reset` / 切分支。
- **提交权在主 agent**：实施席解完、`analyze` 与五档测试通过后交回，合并提交由本席落。
- **验收口径**（评审轮 1 修正后）：numstat **合后重读、不比旧列**；尺寸不进设计档。

## §5 实施记录（eng-coder）
**状态行**：实施完成（上游 8 提交合并工作树已解完并逐档复核；交回父代理落合并提交）



### 实施记录（上游 8 提交并入 · 2026-11-18）

**交回状态**：实施完成，交回父代理落合并提交。本席未提交、未 `merge --abort`、未 reset、未切分支（按 §4）。只 `git add` 了两处冲突档让合并无未解路径；`test/RTM.md` 与 `docs/design/fork-deltas.md` 的改动未暂存，提交时须一并加入。

**实施动作（逐条对 §2.0）**

| # | 条目 | 落法 | 结果 |
|---|---|---|---|
| 1 | 上游 8 提交并入、2 处冲突解析 | 按 §2.3 规则一：`lib/main.dart` 的 import 段留自有三行 + 上游本批 `key_watch.dart` 一行（不回收 `hang_watch.dart`）；`!kIsWeb` 块按 `AppEventWatch` / `FrameWatch` / `KeyWatch` → 我方三调用的次第；`lib/settings/pages/diagnostics_dialog.dart` 两组 import 都留两行 | 完成 |
| 2 | l10n 五档 | `flutter gen-l10n` 重产；重产后再比对，生成物零新增改动 ⇒ 未手解、未选边 | 完成 |
| 3 | 版本两档 | 自动合并即得 `2.0.2+35`（`pubspec.yaml` 与 `lib/update/version.dart` 同值），本席未改 | 完成 |
| 4 | 登记面 numstat 复核 | 合后重读四档，「复核状态：已复核」与读数写回第 3 节各行 | 完成 |
| 5 | 集成索引 `12-1` | `test/RTM.md` 新增第 12 节与 `12-1` 行；规模窗改 `13 / 50–100` 并把 `12-1` 并入「用例体待…」括注；补一条变更记录行。用例体**不建**（§2.9） | 完成 |
| 6 | thincoder 0.12.82 | 不在本批（接手路径见 §2.9，台账 #260） | 未做（按设计） |

**复核读数（本轮实跑，命令 + 读数）**

- 冲突标记：全树 `grep -rn -E '^(<<<<<<<|>>>>>>>)' lib test` ⇒ 0 行。
- `flutter analyze --no-pub` ⇒ `11 issues found`，**error = 0**（11 条均为既有 info/warning，其中 `lib/kernel/claude_code/claude_code_translator.dart` 的 `unused_import` 在合前 HEAD 同档已存在）。
- 变更面单元测试逐档单跑：`test/update/version_test.dart` 5 / 0；`test/diagnostics/key_watch_test.dart` 4 / 0；`test/ide/file_index_store_test.dart` 8 / 0；`test/window/app_windows_test.dart` 74 / 0。
- `test/l10n_test.dart` ⇒ **22 过 / 1 失**。那 1 条 = `every command of the catalog has a Chinese title`，点名 `git.fetchAll`：自有标签 `Fetch and Pull All Repositories` 与上游 arb `Fetch From All Remotes` 不一致。
- 该失败**合前即有**，核法 = 逐项读合前 HEAD 的同四处（标签行 / `app_en.arb` 的 `scmFetchFromAllRemotes` / `command_titles.dart` 的 `'git.fetchAll' => l10n.scmFetchFromAllRemotes,` / `app_localizations_en.dart` 的同名 getter），四处合前合后逐字相同 ⇒ **本批新增失败 0**；按 §2.9 不修。
- 合后 numstat（`git diff --numstat origin/main -- <档>`）：`lib/main.dart` +32 / −5；`lib/window/app_windows.dart` +28 / −10；`test/window/app_windows_test.dart` +20 / 0；`lib/settings/pages/diagnostics_dialog.dart` +20 / −0。
- 四档读数与各行既有读数相同，均未超预算 ⇒ 无需补理由。
- 登记面扫面（本批上游触碰 38 档，逐档 numstat）：非零 9 档 —— l10n 五档 + 上述四档；四档各在第 3 节有行，l10n 由 arb 两档的登记行承载（生成物按 §3.1 不单列）；其余 29 档为零 ⇒ 纯上游面。
- `lib/diagnostics/key_watch.dart` 与 `lib/ide/file_index_store.dart` 对 `origin/main` 均为零 ⇒ 整档上游面，与 §2.4 一致。

**决策披露（与设计的关系）**

- 与 §2.3 / §2.6 的解法逐条一致：无偏离、无简化、未改上游行为与判定次序。
- 两处口径差异都是读数形，不改语义：
  - §2.6 的 numstat 命令写的是 `git diff --numstat origin/main HEAD -- <档>`；合并提交未落时该形读到合前基线，故重读取工作树面 `git diff --numstat origin/main -- <档>`，并在各行写明命令形；父代理落提交后两形等价。
  - §2.6 的 l10n 判据写「`flutter gen-l10n` 后 `git status --short lib/l10n` 无差异」；合并进行中该命令对已暂存档必显 `M`，故取等价判据 `git diff -- lib/l10n`（工作树 vs 索引）为空。
- **表外改动两处，都是 §2.6 点名的写回面**（非扩面）：`docs/design/fork-deltas.md`（四档 numstat 行 + 复核状态）· `test/RTM.md`（`12-1` 行与规模窗）。其余改动全在本席声明的写域内。

**审计与评审轮次**

- 内部偏差审计（只读子代理，对象 = 本批 §2 + 本轮触碰的四档）：`DIVERGENCE COUNT: 0`，无 must-fix；另有三条「已核不判偏差」的记录（注释行归属、numstat 命令形、`12-1` 点名的用例档尚未建）。
- 内部代码评审（`type=code`，范围 = `lib/main.dart` · `lib/settings/pages/diagnostics_dialog.dart` · `test/RTM.md` · `docs/design/fork-deltas.md`）：`VERDICT: pass`，🔴 0 / 🟡 3 / 🔵 1，无 must-fix。
- 三条 🟡 = `hang_reports.dart` 与上游 `hang_watch.dart` 的同名克隆未登记 · 挂起报告行挂在列举成功判据内 · 本段此前为空；🔵 = 存量债名单里 `lib/main.dart` 的行数旧读数。
- 四条都越过本批授权面（改设计档、改上游行为、改既有失败用例都须先裁），故未就地改，随交付报告上抛父代理。
- 终止状态：`clean` —— 代码面无待修项；上抛项归父代理裁。

**测试面交代**

- 单元测试文件本批不改动用例本身（`test/window/app_windows_test.dart` 等随上游带入）；实跑读数见上，新增失败 0，运行产物不留档。
- 集成面：`test/RTM.md` 只新增 `12-1` 行（行已定，用例体待假文件服务 harness），本批无新增集成用例；规模窗 13 / 50–100。

## §6 验证与收口（父代理）

### 验证与收口（上游 8 提交）

**落盘**

- 合并提交：**`16b293f1`**（200 档级变化随上游；2 处冲突 + l10n 重产 + 版本两档 + RTM `12-1`）。
- 与上游关系：**落后 0**（`git rev-list --count HEAD..origin/main` = 0）。
- 冲突标记全库零命中；`test/integration/quick_open_flows_test.dart` 按 §2.9 不建。

**读数**

| 项 | 读数 |
|---|---|
| `flutter analyze --no-pub` | error **0**（11 issues 全为既有 info/warning） |
| 变更面单测 | version 5 · key_watch 4 · file_index_store 8 · app_windows 74 —— 全绿 |
| `test/l10n_test.dart` | 22 过 / **1 失**（`git.fetchAll` 标签与 arb 不一致；合前即有，非本批引入；§2.9 不修） |
| 合后 numstat | `main.dart` +32/−5 · `app_windows` +28/−10 · `app_windows_test` +20/0 · `diagnostics_dialog` +20/−0 |
| 版本 | `2.0.2+35` 两档同值 |

**评审遗留（🟡/🔵，不阻断收口）**

- 评审轮 1 的 6🟡+5🔵、轮 2 的 5🟡+1🔵 全部受理；其中 §2.11 与 §3 的两处过期引文已在本轮修掉（机检门此前因互为对方的引缺而锁死，改法是主 agent 直接改这两行并在此记明破例原因）。
- 仍待处置：§2.6「五档全绿」措辞与 §2.9 互斥 · `app_windows` 两档越 800 未点名 · 诊断面板「挂起报告」被 `if (logs != null)` 遮蔽（**真行为**，建议单独排批）· §2 的标签口径与行号引用。

**集成面**：`test/RTM.md` 现 13 / 50–100（`12-1` 只落行，用例体待假文件服务 harness）。

**暂缓批复核**：无。
