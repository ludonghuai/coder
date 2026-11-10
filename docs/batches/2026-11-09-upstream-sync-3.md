# 2026-11-09 · upstream-sync-3
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-09 · 来源 = 用户 2026-11-09「拉代码」；上游 baocode-dev/baocode 远端 tip 已到 99f225c6，本地 main = 692906ac（上次合到 f405dd00 / 合并提交 30c467d8）。
> 台账 = #231（— · 归批）。前情 = docs/batches/2026-11-08-upstream-sync-2.md（已收口 2026-11-08）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-09
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：合上游 2 个提交

合基 `f405dd00`（上一批合到的上游 tip）；本地合并前 tip `692906ac`；上游 tip `99f225c6`。

**已定决定**：按既有形态直接合上游到 main（`--no-ff` 合并提交、零冲突时不改上游语义、不整档回退）· 用户原话：「拉代码」· 时间：2026-11-09 18:32

| 提交 | 内容 | 落点（numstat） |
|---|---|---|
| `99f225c6`（#856） | 提交面板重建变便宜：改动列表按 `IdeGitState` 排一次、组树每列表一次、文件夹文件每树一次；`PieceTreeBase._newPieces` 大插入按偏移切块（不再每 64K 拷贝整段文本）。用户报告 250–350 ms 帧 / 4–5 秒卡顿（979EC9HD，Intel Mac，1.9.0/1.9.1） | `lib/ide/git/ide_git_commit_panel.dart` +40/−18 · `packages/bao_editor/lib/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart` +8/−5 · 同目录 `piece_tree_base_test.dart` +16/−0 |
| `37ea9184` | site: 1.9.2（下载页版本号 1.9.1 → 1.9.2） | 四个 HTML 各 +1/−1 |

**合并**：合并提交 `c71b6180`，第一父 `692906ac`、第二父 `99f225c6`，零冲突（自动合入 7 档）。`git merge-base --is-ancestor 99f225c6 HEAD` = 真；`git rev-list --count f405dd00..origin/main` = 2。

**自有块对账（合后实读）**：本批 7 档合后对 `origin/main` 的 `git diff --numstat` **全空**。

- 上游改动完整进树，没有自有块被挤掉。
- 合前同样 7 档的读数恰是上游改动的反向（`+18/−40`、`+5/−8`、`0/−16`、四个 `1/1`）⇒ 合前就没有自有块。
- 登记表零命中：`docs/design/fork-deltas.md` 第 2 节整档自有资产与第 3 节登记接缝对本批 7 档没有一行（按 `ide_git_commit_panel` · `piece_tree_base` · `site/(download|index)` 检索读到 0 行）。

**机检（父侧实测，工具链 `build/flutter-3475/flutter/bin/flutter.bat` 3.47.5）**：

- `flutter analyze --no-pub`：**error 0**；11 条（2 warning + 9 info）与合前基线同组。
- 提交面板一组 `partial_commit_panel` · `changelists` · `commit_options` · `commit_message` · `agent_marks` · `review` = **22 过 / 0 挂**。
- `packages/bao_editor` 的 `piece_tree_base_test.dart` = **9 过 / 0 挂**，含上游本批新增的 `large insert cuts its chunks in linear time`。

**版本**：`1.9.2+28` 未变（上游本批只改站点文案，不动 `pubspec.yaml` / `lib/update/version.dart`）。

**登记表**：本批零自有块 ⇒ `docs/design/fork-deltas.md` 预计零改动，由设计席按第 5 节核对结果确认。

**下一步**：§2（设计席）→ 设计评审 → 收口（本批预计无产品实施面）。

### 评审回来（1 🔴 · 7 🟡 · 3 🔵）· 父侧裁决与修轮清单

父侧已逐条复核评审读数：`wc -l` 实测 `lib/ide/git/ide_git_commit_panel.dart` = 3146 行、`piece_tree_base.dart` = 816 行，两条都过 800 硬顶 ⇒ 🔴 成立。第 1–9 条全部受理，派设计席修轮；第 10 条受理不修（存量，记账）；第 11 条是协作项、不是缺陷。

**修轮清单（只限这九条，其余不动）**

| # | 改什么 | 落点与判据 |
|---|---|---|
| 1 | 把「无档跨层」那句改成按行数 tier 的结论：点名两档的实测行数（3146 / 816，2026-11-09 `wc -l`）与处置 = 认账不排期（理由取 `docs/design/fork-deltas.md` §3 存量债段的反例：拆分让两半都成常驻 fork 差异） | §2 的档结论行；不得再写「无档跨层」 |
| 2 | `docs/design/fork-deltas.md` §3 存量债段补上 `lib/ide/git/ide_git_commit_panel.dart`（3146 行，2026-11-09 实测），并把该段的档数口径（现文「十档」）随之对齐 | 该段；档数词与列举须一致 |
| 3 | 三处 `test/RTM.md` 第 11 行改成节名「真实设备读数不在本档」；受影响文件表的「下一行的测试档」改成档路径 | §2（明确不覆盖 · 关键决策 C · 集成测试设计 · 受影响文件表） |
| 4 | 补最近先例行：先例坐标 = 上一批同类合并（`docs/batches/2026-11-08-upstream-sync-2.md` 的 §2 / §6 对账口径），对齐 ∥ 偏离各一句 | §2 |
| 5 | 补调查证据行（照 `docs/design/fork-deltas.md` §7.1 的形态；「查过、无相关」也照写） | §2 |
| 6 | C2 判据补 `git merge-base --is-ancestor 37ea9184 HEAD`（退出码 0），与 C1 同形 | §2 验收对照 C2 |
| 7 | C5 判据补两条 `git diff --numstat`（第一父→合并提交；`f405dd00..origin/main`），让「净差相等」可机检 | §2 验收对照 C5 |
| 8 | C6 判据点名 `test/update/version_test.dart`（该档已声明校验两档同值） | §2 验收对照 C6 |
| 9 | 第 2 步读数后补一句收窄依据：第一父→合并提交恰 7 行，故未改档与合前逐字节相同；全树对账属登记表自身的覆盖缺口（台账 #215） | §2 第 5 节核对表第 2 步 |

**本修轮不做**：不重跑合并、不改 `c71b6180`、不动上游 7 档与任何产品代码；不给 7 档补「无块」登记行（§2 决策 B 已否）；不为帧耗时加集成用例（决策 C 已否）；不整档回退（决策 D 已否）；不推远端、不改版本号；不把登记面扩到 `packages/**`（`piece_tree_base.dart` 属 `packages/bao_editor`，该段现零个 `packages/` 行，扩面另议）；不写 §1 / §3 / §4 / §6。

**第 10 条的处置**：`docs/design/fork-deltas.md` §3 的行号定位属存量形态（该档自写「每次上游合并后按符号核对本表」覆盖合并面），本批不触碰那些行 ⇒ 不修，记入台账（trigger = 条件：下次触碰各行时换符号名）。

**第 11 条的处置**：协作项不是缺陷。三项父侧交接逐条认领——推送（用户只说「拉代码」，未要求推送，本轮不推）、收口复跑（本批 analyze / 定向用例 / 集成已在父侧实跑，§6 复述读数）、版本两档不动（已核未变）。

### 修轮 2（评审轮 2 的新 🔴 #12）

父侧核过：`docs/design/fork-deltas.md` 的存量债段现含 `lib/ide/git/ide_git_commit_panel.dart`（第十一档），而 §2 的 C4 判据仍写「7 档路径在该档检索 0 命中」⇒ 该机检跑出来必假，且与同文「存量债段补一档」自相矛盾。属修轮 1 引入、父侧受理。

**只改这一处，四处同改**（其余一切不动）：

| 落点 | 现文 | 改成 |
|---|---|---|
| C4 判据 | 7 档路径在该档检索 0 命中 | 检索面写明 = 第 3 节**接缝表**与第 2 节 glob；存量债段那一行是体量说明、不计入。判据须能机检 |
| C4 验收读数 | 0 命中；落点只在存量债段，第 3 节接缝表零新增行 | 与上格同口径的读数（接缝表 0 行、存量债段 +1 档） |
| 第 5 节核对表第 3 步 | 第 3 节没有一行指向这 7 档 | 第 3 节**接缝表**没有一行指向这 7 档（注明存量债段该行是状态说明、不是接缝行） |
| 结论行 | 第 2 / 3 节零改动 | 第 2 节零改动、第 3 节接缝表零新增（状态行已有此口径，与之对齐） |

**不做**：不动已修好的 1–9 条；不动 `docs/design/fork-deltas.md`（本轮只在 §2 改字）；不动决策表 / 边界 / RTM 段；不重跑合并与测试。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（2026-11-09 · 零产品实施面，登记表只补存量债一档，第 3 节接缝表零新增）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>


### 本批条目（覆盖 / 明确不覆盖）

本批 = 合上游 2 个提交进 main，**零产品实施面**。

**最近先例**：先例坐标 = 上一批同类合并 `docs/batches/2026-11-08-upstream-sync-2.md` 的 §2 的 2.5 / 2.6 与 §6 对账口径（逐档 `git diff --numstat origin/main`、越 800 行按 `wc -l` 点数认账不排期、版本两档同值跑既有校验）。

- **对齐**：7 档逐档 diff 全空、两档体量点数与处置、版本两档同值，都照该口径。
- **偏离**：上一批补了 `test/models/models_test.dart` 一条接缝行；本批块数为 0 ⇒ 第 3 节接缝表零新增，只按评审 #2 补存量债名单一档。

**调查证据**：`manifest.index.publicRepos` 为空，本仓无独立文档仓；上游两提交经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。

| # | 条目 | 来源 | 判据（机检） |
|---|---|---|---|
| C1 | 上游 `99f225c6`（#856 提交面板重建变便宜 · 大插入按偏移切块）已在 main 上 | 用户 2026-11-09「拉代码」· 台账 #231 | `git merge-base --is-ancestor 99f225c6 HEAD` 退出码 0 |
| C2 | 上游 `37ea9184`（site 1.9.2 文案）已在 main 上 | 同上 | `git merge-base --is-ancestor 37ea9184 HEAD` 退出码 0；`git rev-list --count f405dd00..origin/main` = 2 且含 `37ea9184` |
| C3 | 本批 7 档合后与 `origin/main` 逐档同形：零自有块被上游挤掉 | 本节核对（§1 指定由设计席确认） | 7 档对 `origin/main` 的 `git diff --numstat` 输出为空 |
| C4 | 登记表的登记面（第 3 节接缝表 + 第 2 节自有资产档列）对 7 档零命中；第 3 节接缝表零新增，存量债段补一档 | 同上 · §3 评审 #2 | 检索面 = 第 3 节接缝表（`## 3` 下以竖线开头的表格行）与第 2 节自有资产档列，对 7 档路径逐个比对 = 0 命中；存量债段那一行（第十一档）是体量说明、不是接缝行，不计入；`git diff 692906ac -- docs/design/fork-deltas.md` 的落点只在存量债段（补一档 + 档数词与口径对齐），第 3 节接缝表零新增行 |
| C5 | 上游语义零改动、不整档回退 | §1 已定决定 | `git show -s --format=%P c71b6180` = 第一父 `692906ac`、第二父 `99f225c6`；`git diff --numstat 692906ac c71b6180` 与 `git diff --numstat f405dd00 origin/main` 两列逐档相等（各 7 行） |
| C6 | 版本行两档同值且未动 | `docs/design/fork-deltas.md` §3 版本行 | `git diff --numstat origin/main HEAD -- pubspec.yaml lib/update/version.dart` 为空；`pubspec.yaml` 的 `version:` 行 = `1.9.2+28`；`test/update/version_test.dart` 的既有同值校验 |

**明确不覆盖**：不改上游三档实现语义；不为帧耗时新增集成用例（`test/RTM.md` 的「真实设备读数不在本档」一节把真机读数排除在集成套件外）；不推送远端（合并落在本地 `main`，推送归主 agent）；不动 l10n（本批零 `lib/l10n/**` 改动）；SCM 无改动不跑对应断言。

### 设计档落点与核对（`docs/design/fork-deltas.md` §5 六步，逐条读数）

**本批无自有设计面**：7 档在上游是共享面，本仓在这 7 档上没有自有块 ⇒ 第 3 节不补接缝行。该档本批唯一的改动 = 存量债段补一档（评审 #2，见第 2 步读数与「结论」）。

依据 docs/design/fork-deltas.md「实施是否落地归批档记录，本表只写形态。」

| 步 | 核对面 | 本批读数 |
|---|---|---|
| 1 | 第 2 节自有文件仍在、未被选边覆盖 | 合并只动 7 档（第一父到合并提交的 `git diff --numstat` 恰这 7 行）；7 档无一位于第 2 节任一自有 glob ⇒ 自有档零触及 |
| 2 | 全量 diff 自有块对账；表外自有块先补第 3 节 | 7 档合后对 `origin/main` 的 `git diff --numstat` 全空 ⇒ 档内自有块数 = 0，无表外块、无需补行。收窄依据：第一父到合并提交恰 7 行（`git diff --numstat 692906ac c71b6180` 本节实测 7 行）⇒ 未改档与合前逐字节相同，7 档即全量；表外共享档的覆盖缺口属登记表自身（台账 #215），不在本批处置面 |
| 3 | 第 3 节每个接缝的符号与行为 | 第 3 节接缝表没有一行指向这 7 档（`ide_git_commit_panel` · `piece_tree_base` · `packages/bao_editor` · `site/` 在接缝表内检索 0 命中；存量债段那一行是状态说明、不是接缝行）；同目录在册的是 `lib/ide/git/git_repository.dart` 与第 4 节的 `ide_scm_view.dart`，两者本批零改动 ⇒ 接缝面零待核项 |
| 4 | `flutter analyze --no-pub` 按登记模块归因 | §1 实测 error 0；11 条（2 warning + 9 info）与合前基线同组，无新增归因项 |
| 5 | 重跑各模块定向测试 | §1 实测：提交面板一组 22 过 / 0 挂；`piece_tree_base_test.dart` 9 过 / 0 挂（含上游本批新增 `large insert cuts its chunks in linear time`） |
| 6 | 新出现的共享文件改动若没有行 ⇒ 停工先登记 | 「没有行」的判据是**块存在而无登记行**；第 2 步读数块数为 0 ⇒ 判据不成立，不停工、不补行 |

**结论**：`docs/design/fork-deltas.md` 本批只补存量债段一档（`lib/ide/git/ide_git_commit_panel.dart`，3146 行），第 2 节零改动、第 3 节接缝表零新增 —— 两节登记的是「我们的块」的形态，本批 7 档块数为 0 ⇒ 无可登记形态；存量债段那一行是体量说明，不是接缝行。

### 机制设计

无新机制、无自有实现落地。上游两提交的机制随合并整档进树：

- **提交面板重建**：改动列表按 `IdeGitState` 排一次、组树每列表一次、文件夹文件每树一次（`lib/ide/git/ide_git_commit_panel.dart`）。
- **大插入切块**：`PieceTreeBase._newPieces` 按偏移切块，不再每 64K 拷贝整段文本（`piece_tree_base.dart`），由上游新增用例 `large insert cuts its chunks in linear time` 承载。
- **站点文案**：四个 HTML 的下载页版本号 1.9.1 → 1.9.2。

上游净差逐档见 §1 的落点列，本节不复述数字。

### 受影响文件与测试覆盖

| 文件 | 合后对 `origin/main` | 承载测试 |
|---|---|---|
| `lib/ide/git/ide_git_commit_panel.dart` | 空 | 提交面板一组 6 档：`test/ide/git/partial_commit_panel_test.dart` · `changelists_test.dart` · `commit_options_test.dart` · `commit_message_test.dart` · `agent_marks_test.dart` · `review_test.dart`（§1 读数 22 过 / 0 挂） |
| `packages/bao_editor/lib/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart` | 空 | `packages/bao_editor/test/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base_test.dart`（9 过 / 0 挂） |
| `packages/bao_editor/test/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base_test.dart` | 空 | 上游本批新增 `large insert cuts its chunks in linear time`；§1 读数 9 过 / 0 挂 |
| `site/download.html` · `site/index.html` · `site/zh/download.html` · `site/zh/index.html` | 空 | 无（站点文案，无行为断言） |

**档结论**：两档越 800 行硬顶（2026-11-09 `wc -l` 实测），处置都是认账不排期。

- `lib/ide/git/ide_git_commit_panel.dart` 3146 行：上游共享档，拆分会让两半都成常驻 fork 差异（`docs/design/fork-deltas.md` §3 存量债段同一理由）；已按评审 #2 补进该段名单。
- `packages/bao_editor/lib/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart` 816 行：同口径处置；属 `packages/**`，该段现零个 `packages/` 行，登记面本批不扩（另议）。
- 其余 5 档（四个 site HTML 与测试档）未越顶：342 / 141 / 312 / 141 / 311 行（同口径实测）。

### 验收对照（条目 → 判据）

本批验收 = 上面 C1–C6；命令与读数收口时由父侧复跑。

| 条目 | 判据（机器可跑） | 本节实测读数 |
|---|---|---|
| C1 | `git merge-base --is-ancestor 99f225c6 HEAD; echo $?` | `0` |
| C2 | `git merge-base --is-ancestor 37ea9184 HEAD; echo $?`；`git rev-list --count f405dd00..origin/main` = 2 且含 `37ea9184` | 本席实测 `0`；`origin/main` tip = `99f225c6`，区间计数 `2`，两提交为 `37ea9184` 与 `99f225c6` |
| C3 | 上述 7 档路径的 `git diff --numstat origin/main HEAD` | 零行输出（本节实测） |
| C4 | 检索面 = 第 3 节接缝表（`## 3` 下以竖线开头的表格行）与第 2 节自有资产档列，对 7 档路径逐个比对 = 0 命中；存量债段那一行（第十一档）是体量说明、不是接缝行，不计入；`git diff 692906ac -- docs/design/fork-deltas.md` 的落点只在存量债段（补一档 + 档数词与口径对齐），第 3 节接缝表零新增行 | 接缝表 0 行 · 第 2 节自有资产档列 0 命中 · 该档全文 1 命中（存量债段第十一档）· 落点只在存量债段、接缝表零新增行（2026-11-09 本节实测） |
| C5 | `git show -s --format=%P c71b6180`；`git diff --numstat 692906ac c71b6180`；`git diff --numstat f405dd00 origin/main` | `692906ac… 99f225c6…`（第一父、第二父）；两个 numstat 各 7 行、逐列相等（本节实测 7 / 7） |
| C6 | `git diff --numstat origin/main HEAD -- pubspec.yaml lib/update/version.dart`；`grep -n '^version:' pubspec.yaml`；`test/update/version_test.dart` 的同值校验 | 零行输出；`version: 1.9.2+28`；该测试即 `docs/design/fork-deltas.md` §3 版本行点名的既有校验 |

改动面的定向验证归属：提交面板一组按上面的 6 档跑 `flutter test`；`piece_tree_base_test.dart` 在 `packages/bao_editor` 下跑（§1 已跑，读数同上）。

### 用例表

| 场景 | 输入 | 期望 | 承载 |
|---|---|---|---|
| 正常 · 零冲突合入 | `git merge --no-ff 99f225c6` | 7 档自动合入、零冲突、上游语义不动 | 合并提交 `c71b6180`（实测） |
| 正常 · 大插入线性 | `piece_tree_base_test.dart` 的 `large insert cuts its chunks in linear time` | 过 | 该用例（9 过 / 0 挂） |
| 边界 · 自有块被上游挤掉 | 合后对 `origin/main` 的 diff 非空 | 停工、先补登记再解冲突 | `docs/design/fork-deltas.md` §5 第 2 步；本批读数全空，未触发 |
| 错误 · 共享档有块而无登记行 | 表外自有块被发现 | 停工，先补 `docs/design/fork-deltas.md` 第 3 节 | `docs/design/fork-deltas.md` §5 第 6 步；本批块数为 0，未触发 |

### 关键决策

| 选项 | 内容 | 结论与理由 |
|---|---|---|
| A（采用） | 7 档整档取上游，登记表不补接缝行 | 合后 7 档对 `origin/main` 的 diff 实测为空 ⇒ 块数 0，没有可登记的形态；登记表只写形态（见上引） |
| B（否） | 给这 7 档各补一行「无自有块」登记 | 第 3 节登记的是我们的块；块数为 0 的行是永久对账对象却无物可对，下一轮合并要在空行上重做一遍对账 |
| C（否） | 为帧耗时新增一条集成用例 | `test/RTM.md` 的「真实设备读数不在本档」一节把这类读数排除在集成套件外；两条来路也不成立：本仓无生产报告、无新业务场景 |
| D（否） | 整档回退到合前版本 | 回退丢上游修复，且让 7 档变常驻 fork 差异，与 `docs/design/fork-deltas.md` §1 的目标相反 |

### 边界（不做）

- 不改上游 7 档的任何实现语义，不为消错回退。
- 不给共享档补「无块」登记行。
- 不重跑全量套件（`flutter analyze` 与定向测试的读数取 §1 实跑）。
- 不动 `pubspec.yaml` / `lib/update/version.dart`（上游本批未动版本）。

### UI / 交互

无本仓自决的界面变化：四个 HTML 的版本号文案随上游；提交面板与大插入是性能面，界面结构不变。无 `open` 项。

### 集成测试设计（RTM delta）

读 `test/RTM.md`（9 行：1-1 … 9-1）。本批改的是提交面板重建开销与编辑器文本缓冲的插入开销，属性能面。

- **被破坏的行**：无 —— 9 行断言的都是业务可观察结果（切换、失焦、流式、btest、SSH、凭证、网关），没有一行断言提交面板或 `PieceTreeBase`。
- **冗余可删的行**：无。
- **缺失需新增的行**：无 —— 两条来路都不成立：本仓无该问题的生产报告，也无新业务场景；帧耗时这类真机读数按 `test/RTM.md` 的「真实设备读数不在本档」一节不进集成套件。

⇒ 本批收口报 `none`，不改 RTM。

### 上抛项

无。本批无需求缺口、无实现冲突、无归属不清。

## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

评审面：`docs/batches/2026-11-09-upstream-sync-3.md` §2 + `docs/design/fork-deltas.md` 全文。

方法学限制（写在前）：仓内无 AGENTS.md、无项目规范档、无文档地图 ⇒ 方法学与文档归属两条按本评审的准则 + 在册两档判断。`test/RTM.md` 不在评审面内 ⇒ §2 关于 RTM 内容的断言（"第 11 行"、9 行 1-1…9-1、九行各断言什么）本次未复核（unverified）。

已实测通过的两处：C4 的零命中成立（在 `docs/design/fork-deltas.md` 检索 `ide_git_commit_panel` / `piece_tree_base` / `packages/bao_editor` / `site/` 无匹配）；§2 引用的登记表原句 "实施是否落地归批档记录，本表只写形态。" 与该档逐字一致；四档 site HTML 在盘。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|---|---|---|---|
| 1 | 受影响文件 tier（准则 8） | 🔴 | 受影响文件结论写的是 "无档跨层"，并按 "不跨包边界，无拆分计划" 立论 —— 讲的是包边界，不是行数 tier。本次实测两条 source 档都在 800 行硬顶之上：`lib/ide/git/ide_git_commit_panel.dart` 读到末行 `3147`；`packages/bao_editor/lib/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart` 读到 "817 lines total"。行数 tier 的结论缺失，方向还和实测相反，设计里没有一条点名这两档及其处置 | 把该行改成按行数 tier 的结论：点名这两档的实测行数与处置（拆分计划，或按 `docs/design/fork-deltas.md` 第 3 节「存量债」段既有理由显式记为接受债）；"无档跨层"这句不能留 |
| 2 | 文档归属 / 登记表现态 | 🟡 | `docs/design/fork-deltas.md` 的 "存量债（过 800 行的上游共享档，`wc -l` 实测 2026-11-04）" 逐档列举，`lib/ide/git/ide_git_commit_panel.dart`（本次实测 3147 行）既不在其内，也不在 "另四档（同口径）" / "第十档 `lib/workspace/workspace.dart`" 之内 ⇒ 该列表自称的范围与实测不符。既有裁定 "认账不排期" 不在此质疑，缺的是对账对象 | 在该段补这一档，或改写该段措辞说清它只覆盖哪些目录 |
| 3 | 引用形态（准则 13） | 🟡 | `test/RTM.md` 三处只以行号定位："`test/RTM.md` 第 11 行把真实设备读数排除在集成套件外"（明确不覆盖）· "帧耗时这类真机读数按 `test/RTM.md` 第 11 行不进集成套件"（集成测试设计）· 关键决策 C 同句；「不为帧耗时加集成用例」整条判断全靠这条引用。受影响文件表里另有一处位置引用 "下一行的测试档" | 换成稳定名：RTM 里承载该规则的节标题 / 条目名；表内直接写测试档路径 |
| 4 | 方法学 · 最近先例（准则 9） | 🟡 | §2 无最近先例行：既无先例坐标（实现坐标 ∥ 对应设计档节 ∥ 先例批次），也无对齐 ∥ 偏离理由。先例现成（记录头部「前情」指向 `docs/batches/2026-11-08-upstream-sync-2.md`），项目自有形态见 `docs/design/fork-deltas.md` 的 "**最近先例**：第 8 节的六组行为，同一形——改动压成最小登记块，其余交给上游符号。" | 补一行：先例 = 上一批同类合并及其 §2/§5 对账口径，写明本批何处对齐、何处偏离 |
| 5 | 方法学 · 调查证据（准则 10） | 🟡 | §2 无调查证据行：查过哪些公开来源、是否相关，两者都读不出来（"没查" 与 "查过无相关" 不可区分）。自有记录形态见同档 "**调查证据**：" 下 "`manifest.index.publicRepos` 为空，无独立文档仓；上游源码经本仓 `origin` 远端读取，属仓内读。查过，无外部相关来源。" | 照该形态补一行，无相关也照写 |
| 6 | 验收（C2） | 🟡 | C2 条目断言「已在 main 上」，判据只测到 `origin/main`：`git rev-list --count f405dd00..origin/main` = 2 且含 `37ea9184`；验收表该行读数写 "未在本节复跑（§1 读数 2）"。C1 用 `--is-ancestor … HEAD`，C2 没有同形的可达性判定 | C2 补 `git merge-base --is-ancestor 37ea9184 HEAD`（退出码 0），与 C1 同形 |
| 7 | 验收（C5） | 🟡 | C5 判据列半句无命令："合并提交第一父 `692906ac`、第二父 `99f225c6`；第一父到合并提交的净差 = 上游两提交的 7 档净差"，到验收表只剩 `git show -s --format=%P` 一条 ⇒「净差相等」不可机检 | 把两边 `git diff --numstat` 命令写进 C5 判据列 |
| 8 | 验收（C6） | 🔵 | "版本行两档同值且未动" 的「同值」由「对 `origin/main` 无 diff」推出，没跑项目已声明的同值校验（`docs/design/fork-deltas.md` 的 "`test/update/version_test.dart` 校验两档同值"） | 点名那条既有测试，或把推断写明 |
| 9 | 核对口径 | 🔵 | §2 第 2 步把第 5 节的 "对全量 diff 做自有块对账" 落成 7 档 `git diff --numstat origin/main HEAD` 全空。结论成立（合并只动这 7 档 ⇒ 其余档与合前逐字节相同），但「全量」被收窄这点没写明 | 在该步读数后加一句收窄依据（第一父到合并提交恰这 7 行） |
| 10 | 现存形态 | 🔵 | `docs/design/fork-deltas.md` 第 3 节大量以 `:281-285` / `:246` / `:2638-2641` 形态行号定位代码，与该档自写 "每次上游合并后按符号核对本表，不以旧行号判断接线是否仍在。" 方向相反；本批未触这些行，属存量 | 后续批次触碰各行时换成符号名 |
| 11 | 协作项（不是缺陷，R5） | 🟡 | 三处父侧交接明写在 §2：推送 —— "不推送远端（合并落在本地 `main`，推送归主 agent）"；收口复跑 —— "命令与读数收口时由父侧复跑"；版本两档不动 | 收口时逐条销号 |

计数：🔴 1 · 🟡 7 · 🔵 3（共 11 条）。阻塞项只有 #1：受影响文件 tier 结论与实测相反，须先改正该结论行。

VERDICT: changes-required

### 轮次 2（评审子代理）

评审面：`docs/batches/2026-11-09-upstream-sync-3.md` §2（修轮后）+ `docs/design/fork-deltas.md` 全文。轮 1 的 11 条逐条复核：9 条已修、1 条记账受理（#10）、1 条协作项受理（#11）；另有 1 条新 🔴，由本轮修复自身引入。

方法学限制（沿用轮 1）：仓内无 AGENTS.md / 项目规范档 / 文档地图 ⇒ 方法学与文档归属按本评审准则 + 在册两档判断；`test/RTM.md` 不在评审面内 ⇒ §2 关于 RTM 的断言（节名「真实设备读数不在本档」、9 行 1-1…9-1）本次仍未复核（unverified）。

本轮另做的读数：7 档路径在 `docs/design/fork-deltas.md` 检索 = 1 命中（第十一档那一行，本轮新增）；`packages/bao_editor/test/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base_test.dart` 从 400 行起读为空 ⇒ <400 行，与 §2 写的 311 一致 ⇒ 7 档中没有第三档越 800 硬顶。`wc -l` 3146 / 816 与轮 1 读工具总行数 3147 / 817 差 1，是末行无换行的口径差，不是数值漂移。

| # | Orig# | 文件 | 严重度 | 状态 | 依据 |
|---|---|---|---|---|---|
| 1 | 1 | §2 | 🔴 | Fixed | 档结论改为“**档结论**：两档越 800 行硬顶（2026-11-09 `wc -l` 实测），处置都是认账不排期。”，两档各自点名（`ide_git_commit_panel` 3146 行“已按评审 #2 补进该段名单”；`piece_tree_base.dart` 816 行同口径、`packages/**` 不在名单内另议），其余 5 档给点数“其余 5 档（四个 site HTML 与测试档）未越顶：342 / 141 / 312 / 141 / 311 行（同口径实测）”。“无档跨层”在 §2 已零出现（只剩 §1 修轮清单与 §3 轮 1 记录里的引述） |
| 2 | 2 | `docs/design/fork-deltas.md` | 🟡 | Fixed | 存量债段补上“第十一档 `lib/ide/git/ide_git_commit_panel.dart`（`wc -l` 实测 3146，2026-11-09）”，档数词随之对齐为“十一档都是上游共享档”，并加了口径句“本名单的口径是主仓（`lib/**` / `test/**`）的共享档；`packages/**` 子包不在其内，扩面另议。” |
| 3 | 3 | §2 | 🟡 | Fixed | 三处行号引用都换成节名：`test/RTM.md` 的「真实设备读数不在本档」一节（明确不覆盖 · 关键决策 C · 集成测试设计）；受影响文件表的「下一行的测试档」换成档路径本行。§2 内已无“第 11 行”（只剩 §1 清单引述） |
| 4 | 4 | §2 | 🟡 | Fixed | 补了“**最近先例**：先例坐标 = 上一批同类合并 …”并给出对齐 / 偏离各一 |
| 5 | 5 | §2 | 🟡 | Fixed | 补了“**调查证据**：`manifest.index.publicRepos` 为空，本仓无独立文档仓 … 查过，无外部相关来源。” |
| 6 | 6 | §2 | 🟡 | Fixed | C2 判据与验收读数都补了“`git merge-base --is-ancestor 37ea9184 HEAD` 退出码 0”，与 C1 同形 |
| 7 | 7 | §2 | 🟡 | Fixed | C5 判据补了两条 numstat，验收表点名为“`git diff --numstat 692906ac c71b6180` 与 `git diff --numstat f405dd00 origin/main` 两列逐档相等（各 7 行）” |
| 8 | 8 | §2 | 🔵 | Fixed | C6 判据点名“`test/update/version_test.dart` 的既有同值校验” |
| 9 | 9 | §2 | 🔵 | Fixed | 第 2 步读数后补了“收窄依据：第一父到合并提交恰 7 行”，并把全树对账缺口指到台账 #215 |
| 10 | 10 | `docs/design/fork-deltas.md` | 🔵 | Accepted | 受理不修，理由成立：该档自写“每次上游合并后按符号核对本表，不以旧行号判断接线是否仍在。”覆盖合并面，本批未触那些行；已记入台账（trigger = 条件）。存量形态，不重开 |
| 11 | 11 | §2 | 🟡 | Accepted | 协作项不是缺陷；三项父侧交接逐条认领（推送 / 收口复跑 / 版本两档不动），§1 已记录 |
| 12 | (new) | §2 | 🔴 | New | 本轮修复推翻了 C4 与第 3 步的检索读数：`docs/design/fork-deltas.md` 现有“第十一档 `lib/ide/git/ide_git_commit_panel.dart`（`wc -l` 实测 3146，2026-11-09）”，而 §2 仍写“7 档路径在该档检索 0 命中”（C4 机检）、“第 3 节没有一行指向这 7 档”（第 3 步读数）、“0 命中；落点只在存量债段，第 3 节接缝表零新增行”（C4 读数）；结论行还写“第 2 / 3 节零改动” ⇒ C4 跑出来必假，且与同文的“存量债段补一档”自相矛盾 | 检索面写成「接缝表 + 第 2 节 glob」并注明“存量债段该行不计入”，四处同改（C4 判据 / C4 读数 / 第 3 步读数 / 结论行的“第 2 / 3 节零改动”改成状态行已有的“第 3 节接缝表零新增”口径） |

计数：🔴 1（新）· 🟡 7（6 修 + 1 协作项受理）· 🔵 3（2 修 + 1 记账受理），共 12 条。阻塞项只有 #12。

VERDICT: changes-required

### 轮次 3（评审子代理）

评审面：`docs/batches/2026-11-09-upstream-sync-3.md` §2（修轮 2 后）+ `docs/design/fork-deltas.md` 全文（两档本轮重新读全）。轮 2 的 12 条逐条复核：1–11 条维持 Fixed / Accepted，轮 2 新 🔴 #12 的四处落点全部改正 ⇒ 未决 🔴 = 0。

方法学限制（沿用轮 1 / 轮 2）：仓内无 AGENTS.md / 项目规范档 / 文档地图 ⇒ 方法学与文档归属按本评审准则 + 在册两档判断；`test/RTM.md` 不在评审面内 ⇒ §2 关于 RTM 的断言（节名「真实设备读数不在本档」、9 行 1-1…9-1）本次仍未复核（unverified）。

#12 的四处落点，本轮逐一读过、都改了：
- C4 判据：`检索面 = 第 3 节接缝表（\`## 3\` 下以竖线开头的表格行）与第 2 节自有资产档列，对 7 档路径逐个比对 = 0 命中；存量债段那一行（第十一档）是体量说明、不是接缝行，不计入`
- C4 验收读数：`该档全文 1 命中（存量债段第十一档）`（不再是「0 命中」）
- 第 5 节核对表第 3 步：`第 3 节接缝表没有一行指向这 7 档`
- 结论行：`第 2 节零改动、第 3 节接缝表零新增`

判据与实测一致性：本轮按新判据实读 `docs/design/fork-deltas.md` 的第 3 节表格行（以竖线开头）与第 2 节档列，7 档路径 0 命中；存量债段的段落式行不以竖线开头 ⇒ 被判据定义正确排除；全文只有 1 命中（第十一档那一行），与验收读数一致。旧句式只存于 §1 修轮 2 清单与 §3 轮 2 记录，§2 已零残留。

| # | Orig# | 文件 | 严重度 | 状态 | 依据 |
|---|---|---|---|---|---|
| 1 | 1 | §2 | 🔴 | Fixed | 档结论为「**档结论**：两档越 800 行硬顶（2026-11-09 `wc -l` 实测），处置都是认账不排期。」；两档各自点名（3146 行「已按评审 #2 补进该段名单」、816 行「`packages/**` … 登记面本批不扩（另议）」），其余 5 档给点数「342 / 141 / 312 / 141 / 311 行（同口径实测）」 |
| 2 | 2 | `docs/design/fork-deltas.md` | 🟡 | Fixed | 存量债段有「第十一档 `lib/ide/git/ide_git_commit_panel.dart`（`wc -l` 实测 3146，2026-11-09）」；档数词对齐为「十一档都是上游共享档」；口径句「本名单的口径是主仓（`lib/**` / `test/**`）的共享档；`packages/**` 子包不在其内，扩面另议。」 |
| 3 | 3 | §2 | 🟡 | Fixed | 三处改为节名「「真实设备读数不在本档」一节把真机读数排除在集成套件外」（明确不覆盖 · 决策 C · 集成测试设计）；受影响文件表把测试档单列成行，直接给档路径；§2 内已无行号引用 |
| 4 | 4 | §2 | 🟡 | Fixed | 有「**最近先例**：先例坐标 = 上一批同类合并 `docs/batches/2026-11-08-upstream-sync-2.md` 的 §2 的 2.5 / 2.6 与 §6 对账口径」，对齐 ∥ 偏离各一句在 |
| 5 | 5 | §2 | 🟡 | Fixed | 有「**调查证据**：`manifest.index.publicRepos` 为空，本仓无独立文档仓…查过，无外部相关来源。」 |
| 6 | 6 | §2 | 🟡 | Fixed | C2 判据与验收表同形补「`git merge-base --is-ancestor 37ea9184 HEAD` 退出码 0」，读数为「本席实测 `0`」 |
| 7 | 7 | §2 | 🟡 | Fixed | C5 判据补两条 numstat：「`git diff --numstat 692906ac c71b6180` 与 `git diff --numstat f405dd00 origin/main` 两列逐档相等（各 7 行）」 |
| 8 | 8 | §2 | 🔵 | Fixed | C6 判据点名「`test/update/version_test.dart` 的既有同值校验」 |
| 9 | 9 | §2 | 🔵 | Fixed | 第 2 步读数后有「收窄依据：第一父到合并提交恰 7 行」，全树缺口指到台账 #215 |
| 10 | 10 | `docs/design/fork-deltas.md` | 🔵 | Accepted | 受理不修，理由成立且在案：§1「不修，记入台账（trigger = 条件：下次触碰各行时换符号名）」；该档自写按符号核对覆盖合并面，本批未触那些行 |
| 11 | 11 | §2 | 🟡 | Accepted | §1「**第 11 条的处置**：协作项不是缺陷。」；推送 / 收口复跑 / 版本两档不动三项交接已认领 |
| 12 | (new) | §2（C4 判据 · C4 读数 · 第 3 步 · 结论行） | 🔴 | Fixed | 四处全部改正并与实测对齐：判据写明检索面 = 第 3 节接缝表 + 第 2 节自有资产档列、存量债段不计入；读数为「该档全文 1 命中（存量债段第十一档）」；第 3 步「第 3 节接缝表没有一行指向这 7 档」；结论「第 2 节零改动、第 3 节接缝表零新增」。本轮实读：§3 表格行与本批 7 档 0 命中，全文 1 命中，与读数一致 |

计数：🔴 2（均 Fixed，未决 0）· 🟡 7（6 Fixed + 1 Accepted）· 🔵 3（2 Fixed + 1 Accepted），共 12 条。无未决 🔴、无本轮新问题。

VERDICT: pass

## §4 用户批准（主 agent）

**状态行**：已批准

- 用户 2026-11-09「拉代码」= 本批的整批授权：拉上游 → 合并 → 对账 → 收口，一链走完（设计评审的启动也在这句授权内）。
- 设计评审三轮收敛：轮 1 = 1🔴 + 7🟡 + 3🔵（全受理）；轮 2 = 11 条复核 + 1 条新 🔴（修轮 1 引入的 C4 检索面矛盾）；轮 3 = pass（12 条全部 Fixed / Accepted，未决 🔴 = 0）。
- 本批零产品实施面：合并已在 §1 落盘（`c71b6180`），无 eng-coder 实施轮；产物 = 合并提交 + 登记表一行存量债 + 本记录。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**状态行**：已收口 2026-11-09

- **合并形态**：`c71b6180`，第一父 `692906ac`、第二父 `99f225c6`；`git merge-base --is-ancestor 99f225c6 HEAD` = 真；`git rev-list --count f405dd00..origin/main` = 2（`37ea9184` · `99f225c6`）；零冲突。
- **自有块对账**：本批 7 档合后对 `origin/main` 的 `git diff --numstat` 全空；`docs/design/fork-deltas.md` 第 2 节自有资产与第 3 节接缝表对本批 7 档 0 命中（存量债段 1 命中，非接缝行）。
- **静态检查**（`build/flutter-3475/flutter/bin/flutter.bat analyze --no-pub`，3.47.5）：**error 0**；11 条（2 warning + 9 info）与合前基线同组。
- **定向用例**：提交面板一组 6 档 **22 过 / 0 挂**；`packages/bao_editor` 的 `piece_tree_base_test.dart` **9 过 / 0 挂**（含上游本批新增 `large insert cuts its chunks in linear time`）；`test/update/version_test.dart` **5 过 / 0 挂**（含 `AppVersion is pubspec.yaml's version`）。
- **集成用例（父侧收口门）**：`test/integration/chat_flows_test.dart` + `test/integration/btest_flows_test.dart` = **6 过 / 0 挂**。
- **版本**：`1.9.2+28`；`pubspec.yaml` 与 `lib/update/version.dart` 对 `origin/main` 零差异（未动）。
- **层级**：两档过 800 硬顶（`lib/ide/git/ide_git_commit_panel.dart` 3146 行 · `piece_tree_base.dart` 816 行，2026-11-09 `wc -l`）；按 `docs/design/fork-deltas.md` §3 存量债口径认账不排期，登记表补第十一档并加口径句（`packages/**` 不在名单内）。
- **评审裁决**：三轮收敛，§3 轮 1 / 2 / 3 共 12 条落点全部 Fixed / Accepted；修轮 1 九条、修轮 2 一条（#12，四处同改）。
- **集成索引**：`test/RTM.md` 9 行 / 50–100；本批 delta = none（性能面改动、无业务可观察结果变化；真机读数按「真实设备读数不在本档」不进套件）。
- **用户面同步**：无（本批无自有用户可见能力变更）。
- **暂缓批复核**：无。
- **doc-check gate**：PASS（`docs/batches/2026-11-09-upstream-sync-3.md` · `docs/design/fork-deltas.md`）。
- **台账**：`#231`（本批）随收口核销；派生行 `#232`（fork-deltas 行号定位存量，受理不修）已记账。推送未做——用户只说「拉代码」，未要求推送。
