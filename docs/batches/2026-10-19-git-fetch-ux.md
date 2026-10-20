# 2026-10-19 · Git 获取体验（自动轮不快进 / ↓N 位置 / 获取即可快进）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 03:22「⬇N能不能和获取按键放在一起？放在获取的右边；同时做好获取功能，我现在点击获取还是不能够拉下来代码，；没有自动拉代码；不过已经能看到⬇N了，继续维护的更好用一些」。
> 台账 = #92 · #93（ide-git · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
**本批条目**：① 自动轮 fetch 到了却不快进（`v2-fixturenote` behind 2、dirty 0、可快进，两轮未拉）；② `↓N` 移到仓库头「获取」按钮右侧；③ 获取按钮点击后：干净且可快进 ⇒ 直接快进拉下代码；脏树 / 分叉 ⇒ 保持只显示不拉。

**实测事实（2026-10-19）**：`FETCH_HEAD` 03:18:37 / 03:23:51 两批 14 仓自动 fetch；`v2-fixturenote` = `branch.ab +0 -2`、dirty 0、`merge-base --is-ancestor HEAD origin/master` 成功（可快进）；代码入口 `lib/ide/git/git_autofetch_engine.dart:314`（`state == null` 即返回 null）与 `:252`（`git.busy` 跳过）都能静默吞掉拉取。

**关键判据**：A 口径（脏树整仓不拉、`↓N` 常显）不变；获取是用户显式动作，仍不得覆盖本地修改；本批不得引入「有修改也拉」的口径。

**授权口径**：用户 2026-10-19 03:22 逐字（见抬头来源）；三项均在用户点名下。
## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（实施回灌）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

| # | 条目 | 来源 |
|---|---|---|
| ① | 自动轮 fetch 到了却不快进（`v2-fixturenote` behind 2、`status` 干净、`merge-base --is-ancestor` 成功，两轮未拉）：根因处理 + 真 git 夹具 | 用户 2026-10-19 03:22；台账 #92 |
| ② | `↓N` 移到仓库头「获取」按钮右侧（同一信息单源，不在两处重复） | 用户 03:22；台账 #93 |
| ③ | 获取按钮 = 真拉取（fetch + merge，允许合并提交）；本地冲突 / 会被本地修改覆盖 ⇒ 失败 + 可见错误 + 回滚，工作树不留半合并 | 用户 03:31 裁定第 1、2 条 |
| ④ | 自动轮 A 口径不变（脏树整仓不拉、仅 `--ff-only`、`↓N` 常显） | 用户 03:31 裁定第 3、4 条 |
| ⑤ | 多仓：单仓失败不影响其它仓，失败逐仓列在结果里 | 用户 03:31 裁定第 5 条 |

### 不在本批

- 不改 CLI / kernel / 设置默认；不新增设置项。
- 不动 `Pull` / `Sync Changes` 的既有语义；不改状态栏 `↓N`。
- 不改 `test/ide/git` 既有用例语义（只补新用例）。
- 不做冲突解决 UI（冲突一律回滚 + 报错）。

### 设计落点

`docs/design/ide-git.md` 新增 §12（12.1–12.10）；同步改 §3.1 / §4.1 / §4.2 / §4.3 / §4.5 / §6（D14–D21）/ §10 / §11-2 的旧表述，保证单源。

### 根因与证据（两条候选）

- `git.busy`（`git_autofetch_engine.dart:252`）：**排除**。两轮观测都完成了 fetch（`FETCH_HEAD` 03:18:37 / 03:23:51，14 仓），`_round` 已越过 busy 门；门保留（不与用户前台操作交错）。
- `state == null`（`:314-316`）：未能在源码层复现「fetch 成功后 state 仍为空」（真 git 探针：`v2-fixturenote` fetch 后 `state` 非空、`behind=2`、`decision=pull`）。但它是判定链上**唯一会静默返回空**的出口；本批把判定输入改为拉取操作内 fetch 后现读的 `status`，读不到即 issue / 报错 ⇒ 该类静默路径整体消灭。修复由 T1（真 git 一轮拉下）与 T5（status 不可读 ⇒ issue）机检。

### 受影响文件（实测 → 预算）

| 档 | 现状 | 增量 |
|---|---|---|
| `lib/ide/git/git_pull.dart`（新） | — | ~75 |
| `lib/ide/git/git_repository.dart` | 522 | +65 |
| `lib/ide/git/git_service.dart` | 641 | +30 |
| `lib/ide/git/git_autofetch_engine.dart` | 390 | ±0（≤400） |
| `lib/ide/git/ide_scm_view.dart` | 4119 | +80 |
| `lib/l10n/app_en.arb` / `app_zh.arb` | 7134 / 2749 | +6 / +2（2 键） |
| `lib/l10n/app_localizations*.dart` | 16564 / 10121 / 9570 | `flutter gen-l10n` 生成 |
| `test/ide/git/fake_git.dart` | 236 | +25 |
| `test/ide/git/git_autofetch_test.dart` | 894 | +80（随批删） |
| `test/ide/git/git_pull_real_test.dart`（新） | — | ~260（随批删） |
| `test/ide/git/scm_fetch_button_test.dart`（新） | — | ~140（随批删） |

产品码 +~250（①–⑤）；测试 +~505（⑧–⑪，随批删）。设计与预算明细见设计 §12.7。

### 验收对照

| 条目 | 判据（机检 / 走查） |
|---|---|
| ① | T1：真 git（临时 bare origin + clone + origin 前进 2 条）驱动引擎一轮 ⇒ HEAD 前进、behind 0；T5：status 不可读 ⇒ issue ≠ null；T6：busy 门仍在（本轮零 fetch） |
| ② | W1–W4：动作组顺序 `Commit` · `获取` · `↓2` · `Refresh` · `...`；`_headLabel` 不含 `↓`；窄宽回落且全页只有一处 `↓N` |
| ③ | P1/P5：HEAD 前进、分叉出合并提交；P3/P4/P6：失败且工作树原样、无 `MERGE_HEAD`、无冲突标记 |
| ④ | T2/T3/T4/T7：自动轮零合并提交；P3 同场景下自动轮仍零 merge |
| ⑤ | P9：另一仓 HEAD 前进；失败仓通知带仓库名；逐仓提示 |

### 关键决策

D14–D21（设计 §6）：D14 获取 = 真拉取 · D15 fetch + 显式 merge（非 `git pull`） · D16 共用 `pullFromUpstream` · D17 判定输入现读 status · D18 只回滚我们发起的合并 · D19 `↓N` 位置与单源 · D20 多仓 4 并发逐仓通知 · D21 自动轮口径不变。

### 测试与删除

- 真 git：`test/ide/git/git_pull_real_test.dart`（P1–P8 / T1–T8；夹具在系统临时目录）。
- FakeGit / widget：`git_autofetch_test.dart` + `scm_fetch_button_test.dart`（W1–W5 / P9–P10 / T2–T6）。
- 单测与 widget 用例随批删；交付前父侧走查 3 条（设计 §12.9 末行）。

### 上抛项

1. **[上抛·待裁] 需求档缺口（主 agent 笔）**：`docs/requirements/ide-git.md` 的功能点与 §4 验收未含「获取 = 真拉取、冲突失败回滚、`↓N` 位置」，也未把「自动轮 fetch 到了却不快进」列为缺陷条目；三链一致性待需求档补齐后再进评审。设计已按用户 03:31 裁定落笔。
2. **[上抛·知会] 设计档 §5 ⑯ 读数核对**：主 agent 报「251 行」；实测 580 行（UTF-8；`Get-Content -Encoding UTF8` = 580，`-Raw` 按 `\n` 切 = 581 含末尾空行；字节 40,479）。251 的来源 = `Get-Content` 未带 `-Encoding UTF8`（ANSI 误解码）。已把 ⑯ 的实测改为 580；若仍要按 251，请指明测量命令。
3. **[上抛·知会] 既有基线红**：`test/ide/git` 12 条 HEAD 基线红（台账 #90）；本批新增用例按既有基线对照，不把既有红算本批。
4. **[上抛·知会] 并发写面（已自行消失）**：03:33 `D:\baocode` 处于 #76 上游合并中间态（MERGE_HEAD 在、`general_page.dart` UU），曾短暂覆盖 git 面已跟踪改动；03:34 已恢复（`git_repository.dart` 522 行 / `git_service.dart` 641 行 / `ide_scm_view.dart` 4119 行 / l10n 键在）。设计以恢复后的基线落笔；实施不得在 merge 未解决时开始。

### 修正轮落点核对（评审修正轮 1 · 2026-10-19）

行号 = 本轮回填后的当前值。本轮只改设计档 `:245` / `:271` 两行（单行替换，行数不变）；其余 13 条落点为前几轮已落，照抄父侧已核行号。

| # | 落点（`docs/design/ide-git.md`） | 断言 |
|---|---|---|
| 1 | `:598` | 单仓无仓库头、`↓N` 由状态栏承担，理由写明（需求 §2.8 的适用面 = 多仓仓库头） |
| 2 | `:498` | 「单源」范围固定为仓库头内部；仓库头与状态栏两处并存是需求 §2.1 / §2.8 张力的裁定结果 |
| 3 | `:245` · `:271` | **本轮回填**：§5 ⑧ 与 §5.1 该行标为批 12 实现记录，并注明 `↓N` 的当前位置已在批 13 移到获取按钮右侧、`_headLabel` 不再含它（§12.6 第 2 条） |
| 4 | `:117-120` | 三条新命令进 §3.3 argv 表；`merge` 列入放宽档 |
| 5 | `:440` | `merging()` 契约：无 `MERGE_HEAD` ⇒ `false`，不按异常处理 |
| 6 | `:442` · `:456` | `merge --abort` 自身失败的处置写明 |
| 7 | `:513` | §12.7 补 `git_runner.dart` 行数行；放宽档含 `merge` |
| 8 | `:576-577` | T9（缓存 `state` 与现读 status 不一致 ⇒ 仍合并）/ T10（fetch 成功但按 A 口径不拉 ⇒ `↓N` 出现） |
| 9 | `:464` · `:501` | `fetchAll` 作用域固定：全仓遍历；每仓 `fetch --all --tags` = 单仓全 remote |
| 10 | `:22` · `:308` · `:319` | §2.1 数据流改为一次 `pullFromUpstream`；§7 表尾指向 §12.9 |
| 11 | `:240`/`:512` · `:241`/`:511` · `:245`/`:515` · `:252`/`:519` | §5 与 §12.7 同批档读数一致（640 / 521 / 4118 / 893）；`_fetchAll` 坐标收敛为 `:482` 与 `:501` 的 `ide_scm_view.dart:2017-2023` |
| 12 | `:514` | `_reported` 移入 `git_pull.dart`，与 `ideGitPullIssue` 同一实体 |
| 13 | `:500` | 禁用符号固定为 `_InlineAction.onPressed`（可空），另一处改为引用 |
| 14 | `:525` | 评审输入限制写明；超档读数在实施首轮以 `wc -l` 复核 |

同时去掉本节重复的状态行（原第 18 行仍写「initial 轮」，与置顶状态行冲突）——同属本节内的一致性修整，不改任何设计内容。

### 实施回灌（2026-10-19 · 批 13 交付后）

来源：§5 上抛 1（待裁）+ 知会 2–5。本轮只改设计档五处，零代码。

| # | 落点（`docs/design/ide-git.md`） | 改动 |
|---|---|---|
| ① | §12.2 步骤 6（`:440-442`） | 补「复查失败」口径：`merging()` 复查抛错 ⇒ 按「可能已开始合并」仍 `abortMerge()`；错误 = 合并原话 + 复查原话（拼接）；复查失败不得顶掉合并原话、不得跳过 abort；工作树可能留 `MERGE_HEAD`（已知限制） |
| ② | §12.6-5（`:504-505`） | 单仓 `...` 菜单：`获取` = 真拉取（与仓库头按钮同一动作）、`从所有远程获取` = 只 fetch；并列不加提示（菜单项无提示面，`IdeMenuAction` 只有 `label`） |
| ③ | §12.6-5（`:506`） | 工作区 `Fetch From All Remotes` = 全仓 fetch + merge ⇒ 选「改文案」：独立 l10n 键，文案「获取并拉取所有仓库」/ "Fetch and Pull All Repositories"；不加提示 |
| ④ | §12.7 ⑪（`:525`） | 按实交：真 git 档只含 T1 / P1–P8 / P6a / S1–S2，362 行；T2–T10 归 ⑩（FakeGit） |
| ⑤ | §12.8 P4（`:543`） | 判据按实测：不相交暂存不触发拒绝（可快进路径）；拒绝判据 = 暂存改动落在远端同样改动的文件上；分叉走真合并时 index ≠ HEAD 即拒绝 |

读数：`docs/design/ide-git.md` 600 → 605 行（换行数实测）；新增行均 ≤300 字符；`doc_check` 本档零新增命中（既有命中 `:471` / `:502` 行宽与 `:530` `AGENTS.md` 锚未动）。

未改项（本轮五处之外，如实登记）：

- ① / ③ 的实现未跟进（零代码）：`git_repository.dart:399` 仍是 `if (!await service.merging()) rethrow;`；工作区菜单仍与单仓只 fetch 项共用 `scmFetchFromAllRemotes`。两条需另批实施（① 回滚空档、③ 文案）。
- §12.3「有暂存改动（index ≠ HEAD）⇒ 合并前拒绝」只对真合并路径成立；可快进路径下不相交的暂存改动不拒绝（本机 Git 2.51.2 实测）。超出本轮五处，未改，待裁。

补充未改项（同一规则的其他转述，超出五处）：

- D18（`:301`）与 §3.3 回滚合并行（`:119`）仍写 abort 触发 = 「合并前无 `MERGE_HEAD`、现在有」，未含 ① 的「复查失败按可能已开始合并」；两处与 §12.2 步骤 6 的新口径不齐，待裁是否另批收口。
- §12.1（`:402`）与 §12.3（`:465`）同样把「有暂存改动」写成一律拒绝；与 ⑤ 的实测判据不一致（可快进路径下不相交暂存不拒绝），随 §12.3 行一并待裁。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

评审对象：批 13 Git 获取体验 §12（`docs/design/ide-git.md` 579 行）+ `docs/requirements/ide-git.md`。判定：无可实现性阻塞；9 条 🟡（多为口径未收敛 / 归属章节未跟更）+ 5 条 🔵。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Requirements | 🟡 | 需求侧 `↓N` 验收未限定面（`docs/requirements/ide-git.md:20`「分支名后不再重复显示同一信息」、`:39`「`↓N` 位于获取按钮右侧、分支名后无重复」），设计只覆盖多仓仓库头（`docs/design/ide-git.md:487`「多仓 CHANGES 的仓库头」），单仓路径被 `:576`「不改单仓无仓库头时的既有形态」与 `:365`「不为单仓 SCM 视图新增仓库头」判为不做且未给理由。 | 给单仓路径明确落点（同「按钮右侧」规则）或写明需求 §2.8 的适用面是仓库头、单仓由状态栏承担，并把这条偏差补进 §12.10 的理由；需求 AC 8 的作用面同步限定，否则机检按字面判失败。 |
| 2 | Acceptance | 🟡 | `↓N` 的「单源」口径自相矛盾：`:296`（D19）「同一信息单源，同一时刻只渲染一处」vs `:488`「状态栏 branch 项保留自己的 `↓N`（侧栏关闭时的常显面，与仓库头不同面）」；验收表继承该矛盾——`:541`（W4）「页面上只有一处 `↓N`」与 `:542`（W5）「branch 项仍为 `main ↓2`（不受仓库头影响）」在侧栏开 + 状态栏可见时不可能同时成立。 | 把「单源」范围固定为仓库头内部（分支标签 vs 按钮右侧），W4 断言改为「仓库头内只有一处」；在 §12.6 明确「仓库头 + 状态栏两处并存」是本批对需求 §2.1 与 §2.8 张力的裁定结果。 |
| 3 | Document ownership | 🟡 | §5 / §5.1 是上一批改动记录，但仍在规范面与 §12.6 相反：`:239`「`_headLabel` 追加 ` ↓N`」、`:265`「只改 `_headLabel` 与仓库头 tooltip（+19）」，而 `:488` 要求「`_headLabel` 不再含 `↓N`」。按 §5 读会把刚移走的 `↓N` 又加回分支标签。 | 把 §5 / §5.1 标为上一批记录（或在 §12.6 注明这两处已被本批取代），让 `↓N` 的当前位置只有一个权威描述。 |
| 4 | Document ownership | 🟡 | §3.3 是「新增 / 变更的 git 命令（argv 逐字）」的归属章节（`:109`），但本批三条新命令只在 §12.2 散文里：`merge --no-edit <ref>`、`rev-parse --verify -q MERGE_HEAD`、`merge --abort`（`:431`、`:435`）；§3.1 的 `IdeGitService` 段也只列 `fetch` / `fastForward` / `changedPaths`；§12.7 ⑫ 的更新清单（`:511`「本节与 §3.1 / §4.1–§4.3 / §4.5 / §6 / §10 / §11 的语义更新」）未含 §3.3。 | 三条命令按同一张 argv 表补进 §3.3（含超时归类），§3.1 的 service 面同补；或删掉 §12.2 的 argv 散文、只指向 §3.3，避免同一机制两份描述。 |
| 5 | Feasibility | 🟡 | `merging()` 的返回契约未定：`:431` 只写「先 `merging()`（`rev-parse --verify -q MERGE_HEAD`）；已在合并中 ⇒ 抛错」。按 §3.3（`:113` 非 0 退出即失败）与 §3.5（`:131` 由 `IdeGitException` 携带 stderr）的既有口径，该命令在「无 MERGE_HEAD」时自身返回非 0，实现者无法判断该当 `false` 还是异常。 | 写明 `merging()` 捕获「无 MERGE_HEAD」退出并映射为 `false`（仅 stderr 非空 / 仓库不可读时照抛），并给「无合并进行」与「合并进行中」两条单测断言。 |
| 6 | Acceptance | 🟡 | 回滚契约有空档：`:431` 只在「合并前无 `MERGE_HEAD`、现在有」时调 `abortMerge()`，未说 `merge --abort` 自身失败怎么办，而 `docs/requirements/ide-git.md:39`「工作树无 `MERGE_HEAD` / 冲突标记」是硬判据；`:453`「本设计先判「相交就根本不会开始合并」，把该窗口压到竞态级」与 `:395`「按钮传入 `merge` 模式且不否决」冲突——按钮路径没有设计侧预判。 | 补 abort 失败的处置（单独提示 + 保留 `MERGE_HEAD` 作为已知限制，或重试一次）；`:453` 改成「由 git 的合并前检查挡住，`--abort` 只处理真冲突」；为「不相交本地改动 + 冲突合并」这一角落加一条用例或明确不做。 |
| 7 | Feasibility | 🟡 | 新命令 `merge`（含 `--ff-only` / `--abort`）落在 60 秒档：`:114`「`fetch` / `pull` / `push` / `ls-remote` / `clone` / `submodule` ⇒ 300 秒；其余 60 秒」，而 `:55` 放宽 fetch 的理由正是「大仓 / 慢代理下一次 fetch 可能超过 60 秒，被杀了就永远成功不了」；merge 大量写工作树，被 60 秒杀掉比 fetch 被杀更难收拾，风险不对称。§12.7 也无 `git_runner.dart` 行。 | 把 `merge` 列入放宽档并说明 `merge --abort` 的档位；若 `gitTimeoutFor` 要改，在 §12.7 补 `packages/bao_remote/lib/src/git/git_runner.dart` 的当前行数与增量。 |
| 8 | Acceptance | 🟡 | 根因（`:459`「`git.state` 不再是判定输入」）缺回归证据：`:561` 的机检只给 T1/T5/T6；T1（`:548`「fetch + `merge --ff-only`；HEAD 前进」）是端到端成功路径，无法区分「现读 status」与「缓存恰好新鲜」；T5（`:552`「status 读不到（注入失败）」）只覆盖 status 为 null；无「缓存 `state` 与现读 status 不一致」的用例。用户第二个症状（`docs/requirements/ide-git.md:5`「不显示远端有提交」）不在 ① 的判据里，根因断言也未给代码坐标（§12.5 只给 `git_autofetch_engine.dart:265-378` 区间）。 | 补两条机检：（a）缓存 `state` 的 behind 为 0 / state 为 null、现读 status 的 behind > 0 ⇒ 必须发起合并；（b）fetch 成功但按 A 口径不拉 ⇒ `↓N` 必须出现。根因句后加读取缓存 `state` 与静默返回的代码坐标。 |
| 9 | Clarity | 🟡 | `git.fetchAll` 作用域两读：`:454`「从所有远程获取（`git.fetchAll` / `_fetchAll`）逐仓拉取」与 `:491`「`git.fetchAll`（从所有远程获取）走同一拉取」把它当逐仓，而 `:35` 的 `_fetchAll` 是「全仓遍历」先例；「从所有远程」按字面是单仓多 remote。两读法在 ⑤ 的改动范围与 P9（`:531`）覆盖面上不同。 | 在 §3.3 / §12.6 固定该命令的 argv 与作用域（单仓全 remote / 全仓），让 P9 明确覆盖哪一种；两者都存在则分开命名。 |
| 10 | Clarity | 🔵 | §2.1 引擎数据流仍是旧形（`:22`「每仓：git.fetch() → 判定 → git.fastForward()」），§12.2 之后每仓走一次 `pullFromUpstream`；§7 验收表（`:303` 起）只到需求 §4.7，需求已加 §4.8（`docs/requirements/ide-git.md:39`）。 | §2.1 数据流改成一次 `pullFromUpstream`；§7 表尾加一行指向 §12.9，表头注明「本批增量见 §12.9」。 |
| 11 | Document consistency | 🔵 | 同一批文件两处读数差 1：§5 `640`（`:234`）/ §12.7 `641`（`:502`）；`521`（`:235`）/ `522`（`:501`）；`4118`（`:239`）/ `4119`（`:504`）；`893`（`:246`）/ `894`（`:508`）。`_fetchAll` 坐标两个：`:35`「`lib/ide/git/ide_scm_view.dart:2016-2023`」与 `:472`「`ide_scm_view.dart:2017-2024`」。 | 注明 §5 为上一批实测、§12.7 为本批实测（或只留一份），`_fetchAll` 坐标收敛成一处。 |
| 12 | Clarity | 🔵 | `_reported` 去向未写：`:503` 只说「`_reported` 移出」，① 列的是 `ideGitPullIssue`（`:500`），未说两者同一实体；若它实际住在 `git_autofetch.dart`，§12.7 漏了该档的行数注记。 | 写明移入 `lib/ide/git/git_pull.dart`（与 `ideGitPullIssue` 同一实体），并确认 `git_autofetch.dart` 是否被改（被改则补当前行数与增量）。 |
| 13 | Clarity | 🔵 | 按钮禁用的符号名有两个：`:490`「`git.busy` 时禁用（`IdeActionButton.onPressed = null`）」与 `:504`「`_InlineAction` 支持禁用」。 | 固定一个符号名（SCM 视图里实际的那个），另一处改为引用。 |
| 14 | Methodology | 🔵 | 评审范围无 AGENTS.md / 项目标准 / 文档地图，「4 步流程」「文档地图」两条判据无从核对；§12.7 行数为其它档实测值，本轮按声明接受、未逐档 spot-check。 | 评审输入补齐 AGENTS.md / 文档地图；§12.7 行数在实施首轮以 `wc -l` 复核（优先 ⑤ 4199 与 ⑨ 894 两个超档读数）。 |

计数：🔴 0 / 🟡 9 / 🔵 5 ＝ 14 条

VERDICT: pass

## §4 用户批准（主 agent）

**用户批准（2026-10-19 19:22）**：逐字「批准13」——批 13（Git 获取体验）设计批准；实现面 = §12.7 的 ①–⑫（13 行表，⑬ 为文档）。

## §5 实施记录（eng-coder）

**状态行**：实施完成 2026-10-19（fix 轮 · 设计回灌 ①② · 终态 clean）
**轮次**：initial · 内部偏差审计 1 轮 · advisor 代码评审 1 轮 · 修正轮 1 轮 · 终态 clean

### 一、交付内容（按 §12.7 ①–⑫，读数 = 2026-10-19 换行数）

| # | 档 | 改动 | 读数 |
|---|---|---|---|
| ① | `lib/ide/git/git_pull.dart`（新） | `IdeGitPullMode` / `IdeGitPullVeto` / `IdeGitPullOutcome` / `ideGitPullIssue`（原 `_reported`） | 52 |
| ② | `lib/ide/git/git_repository.dart` | `pullFromUpstream`（一次 `_operate`：fetch → 现读 status → 上游检查 → changedPaths → 否决 → merge/ff → 回滚）；`_operate`/`_enqueue` 改为泛型返回值（见偏差 1） | 584（≤586） |
| ③ | `lib/ide/git/git_service.dart` | `merge(ref)`（stderr 空则 stdout，截 500）/ `merging()`（退出 0⇒true，1 且输出空⇒false，其余抛）/ `abortMerge()` | 669（≤670） |
| ④ | `packages/bao_remote/lib/src/git/git_runner.dart` | 放宽档加 `merge`（`merge --ff-only` / `--no-edit` / `--abort` 同档） | 257 |
| ⑤ | `lib/ide/git/git_autofetch_engine.dart` | `_fetchAndPull` 走共用核心 + `_veto`（判定链 + 快进前重读 `git.autofetch`）；`_reported` 移入 ①；迟到缓冲复查留引擎 | 381（≤400） |
| ⑥ | `lib/ide/git/ide_scm_view.dart` | Get = `_pullFromUpstream`（失败带仓库名；成功后 `host.reload(updated)`）；`_fetchAll` 4 并发逐仓拉取；`_RepositoryBehind` 徽标（roomy 在获取右侧 / 窄宽在分支名后）；`_headLabel` 去 `↓N`；`_InlineAction.onPressed` 可空 + key；tooltip 走 l10n | 4196（≤4198） |
| ⑦ | `lib/l10n/app_en.arb` / `app_zh.arb` | 2 键：`scmFetchAndPull`（获取并拉取 tooltip）、`scmBehindCommits`（`↓N` tooltip） | 7154 / 2751 |
| ⑧ | `lib/l10n/app_localizations*.dart` | `flutter gen-l10n` 重新生成（退出 0；三档含两新键，未手改） | 16581 / 10133 / 9582 |
| ⑨ | `test/ide/git/fake_git.dart` | `merge --no-edit` / `merge --abort` 可编程应答 | 246 |
| ⑩ | `test/ide/git/git_autofetch_test.dart` | T5 / T6 / T8 / T9 / T10；`gitTimeoutFor(merge)` 断言改 300 秒 | 1007（随批删） |
| ⑪ | `test/ide/git/git_pull_real_test.dart`（新） | 真 git 夹具（临时 bare origin + 两个 clone，`core.autocrlf=false`）：P1–P8 / P6a / S1–S2 / T1 | 362（随批删） |
| ⑫ | `test/ide/git/scm_fetch_button_test.dart`（新） | W1–W5 / P9 / P10 widget 用例 | 197（随批删） |

### 二、读数（命令 + 结果）

- 验收命令 `flutter test --no-pub test/ide/git/git_pull_real_test.dart test/ide/git/scm_fetch_button_test.dart test/ide/git/git_autofetch_test.dart test/ide/git/git_operations_test.dart test/ide/git/git_repository_test.dart` ⇒ **+85 全绿**。
- 全量 `flutter test --no-pub test/ide/git` ⇒ **+166 -12**；12 条红与基线**同名同数**：git_blame 1（blame after the caret line）/ git_service 1（CRLF）/ scm_diff 5 / scm_multiselect 3 / timeline_view 1 / scm_view 1；本波零新增红。
- `flutter test --no-pub test/ide/workbench/scm_repositories_test.dart test/ide/workbench/explorer_workspace_test.dart` ⇒ +18 全绿（多仓仓库头未回退）。
- `flutter test --no-pub test/l10n_test.dart` ⇒ +22 全绿。
- `flutter analyze --no-pub` 改动面（10 档）零新增；全仓另有 13 条既有 info/warning，均不在本批档。
- `flutter gen-l10n` ⇒ 退出 0；`scmFetchAndPull` / `scmBehindCommits` 在 `app_localizations{,_en,_zh}.dart` 中生成（`String scmBehindCommits(int count)`）。

### 三、用例归属（§12.8）

- 真 git `git_pull_real_test.dart`：P1（快进）/ P2（已最新）/ P3（未暂存相交拒绝）/ P4（暂存拒绝）/ P5（分叉合并提交 2 父）/ P6（冲突回滚、文本=本地、无 MERGE_HEAD/标记）/ P6a（回滚保留不相关本地改动）/ P7（已有合并拒绝且不 abort）/ P8（无上游、detached）/ S1 / S2 / T1（一轮 fetch+ff，HEAD 前进、behind 0、reload）。
- FakeGit `git_autofetch_test.dart`：T5（status 不可读 ⇒ other，零 merge）/ T6（busy ⇒ 本轮零 fetch）/ T8（两仓一仓 fetch 失败，另一仓仍快进）/ T9（缓存 state behind 0、现读 behind 2 ⇒ 仍 merge）/ T10（fetch 成功但脏树不拉 ⇒ behind 保留 2）；T2/T3/T4/T7 由既有 B2/B3/B4/B9 承接（未改语义）。
- Widget `scm_fetch_button_test.dart`：W1（动作组顺序 Commit·Get·↓2·Refresh·…、tooltip 新键）/ W2（分支文本无 ↓，仓库头内仅一处）/ W3（behind 0 无徽标）/ W4（180 宽：动作组隐藏、↓2 在分支名右、单源）/ W5（状态栏 `main ↓2` 与仓库头并存）/ P9（`git.fetchAll`：正常仓拉下、失败仓一条带仓库名通知）/ P10（busy ⇒ `onPressed == null`）。

### 四、偏差与处理（如实）

1. **`_operate`/`_enqueue` 泛型化**（② 内、HEAD 行）：设计要求「一次 `_operate`」且返回 `IdeGitPullOutcome`，原签名 `Future<void>` 无法承载；改为 `Future<T> _enqueue<T>/_operate<T>`（队列错误吞掉改为 `run.then<void>(…)`，语义不变）。
2. **P4 夹具**：实测本机 Git 对「不相交的暂存改动」不拒绝（fast-forward 成功），故 P4 的暂存改动放在远端同样改动的 `a.txt` 上（与「暂存/相交 ⇒ 合并前拒绝」的设计判据一致）；若设计坚持「任意暂存变更即拒绝」，需回设计档改判据。
3. **测试档读数超「~」估算**：⑩ 1007 vs ~973、⑪ 362 vs ~260、⑫ 197 vs ~140；均随批删，无硬上限命中。
4. `app_en.arb` +13 行（两键各带 `@` 说明/占位符），高于 §12.7 的 +6；`git_runner.dart` 257（档位注释拆行 +1）。
5. 设计 §12.7 ⑪ 行写「真 git 夹具：T1–T10 … ~260」，实际真 git 档只含 T1 + P*/S*，T2–T10 落在 ⑩（§12.8 允许 FakeGit）；档面读数漂移，归设计档（见上抛 5）。

### 五、基线对齐记录（他批未提交改动）

- 开工前保存：`.thincoder/tmp/b13-baseline/{git_repository,git_service,ide_scm_view,git_runner}.diff`（Git autofetch 批的未提交改动）。
- 写后逐行比对：基线新增/删除行**全部保留**；仅三处按本批设计/正确性明确改写（均如实登记）：
  1. `ide_scm_view.dart` `_headLabel` 的 `↓N` 追加与 `final behind`（设计 §12.6-2 明确移除）；
  2. `git_repository.dart` `fastForward` 三行注释（改为「自动轮已走 `pullFromUpstream`」，避免陈旧注释）；
  3. `git_runner.dart` 档位/集合三行注释（「talk to a remote」改为「long tier」，因集合已含本地 `merge`）。
- 未 `git checkout`、未整档格式化；工作树 `git status` 只含本波声明档 + 批次档。

### 六、审计与代码评审轮次

- **内部偏差审计（explore，第 1 轮）**：DEVIATIONS 2 条（均 note）：① 视图未调 `host.reload(updated)`（设计 §12.2 步 7 / §12.6-4）→ 已修（`_pullFromUpstream` 成功后 reload，失败静默）；② T8 组合用例缺失 → 已补（两仓一仓 fetch 失败，另一仓仍快进）。
- **advisor 代码评审（code，第 1 轮）**：VERDICT pass；3 🟡（optional）+ 7 🔵。已按可选建议修 4 条：`fastForward` 陈旧注释、`_headLabel` 方向写反的注释、失败路径 `root` 改 `state?.root ?? service.root`、`git_runner` 档位注释；**未修 3 条 🟡**（均为设计未规定或超出本批设计面，见上抛）。
- **修正轮**：1 轮（审计 2 条 + 评审 4 条可选建议）。终态 **clean**。

### 七、上抛（[上抛·待裁] / [上抛·知会]）

1. **[上抛·待裁] 设计缺口（`merging()` 复查失败）**：合并失败后 `if (!await service.merging()) rethrow;` 若复查抛错，会顶掉合并原话并跳过 `abortMerge()`，工作树可能留 `MERGE_HEAD`；§12.2 步骤 6 只规定「abort 自身失败」。建议设计补一句口径（复查失败按「可能已开始合并」处理并拼两段原话）。
2. **[上抛·知会] 菜单同词两义**：仓库 `...` 菜单「获取」已变真拉取，紧邻「从所有远程获取」仍只 fetch（`ide_scm_view.dart:2133`）；设计 §12.6-5 未覆盖该单仓菜单项。未自行扩大改动面。
3. **[上抛·知会] 工作区命令文案**：`Fetch From All Remotes` 现对全仓 fetch+merge（设计 §12.6-5 规定），菜单文案未改、没有「会合并」的提示；设计只改了按钮 tooltip。
4. **[上抛·知会] P4 判据实测**：不相交暂存改动不触发 Git 拒绝（本轮实测）；用例按「暂存 + 相交」落，判据文字若需绝对化请设计档定。
5. **[上抛·知会] 设计 §12.7 ⑪ 行读数**：真 git 档实际 362 行、只含 T1（T2–T10 在 ⑩），与「T1–T10 … ~260」不符；属设计档维护，不自行修改。
6. **[上抛·知会] 无 GUI 走查**：设计 §12.9 的三条真机走查（获取、冲突回滚、多仓断 remote）未执行（无 GUI 会话），留父侧收口。

### 实施回灌修复轮（2026-10-19 · fix）

**轮次**：fix · 内部偏差审计 1 轮（explore，clean）· advisor 代码评审 1 轮（pass：🟡1 / 🔵4）· 自修 1 轮 · 终态 **clean**

| # | 文件 | 改动（按设计档 §12.2 步骤 6 / §12.6-5） | 读数 |
|---|---|---|---|
| ① | `lib/ide/git/git_repository.dart:396-410` | 合并失败回滚：复查 `merging()` 用 `catchError` 收错（抛错 ⇒ 按「可能已开始合并」，`started=true` 且留住复查原话）；`started` ⇒ `abortMerge()`；错误 = 合并原话 + 复查原话 + abort 原话逐段拼接（缺段跳过），不再让复查错误顶掉合并原话或跳过 abort；注释指向 §12.2 | 586（≤586） |
| ② | `lib/ide/git/ide_scm_view.dart:2932` | 工作区 `...` 菜单项改用 `scmFetchAndPullAll`；单仓 `...` 的 `scmFetchFromAllRemotes`（只 fetch，`:2131-2134`）不动 | 4196（≤4198） |
| ③ | `lib/l10n/app_en.arb:2835-2838` / `app_zh.arb:1144` | 新键 `scmFetchAndPullAll`：en "Fetch and Pull All Repositories" / zh "获取并拉取所有仓库"（含 @description） | +4 / +1 |
| ④ | `lib/l10n/app_localizations{,_en,_zh}.dart` | `flutter gen-l10n` 重新生成（退出 0，未手改） | +6 / +3 / +3 |
| ⑤ | `test/ide/git/scm_fetch_button_test.dart:151-175` | 工作区菜单 = 新文案且无旧文案；单仓 `...` = 旧文案且无新文案（悬停 Changes 头再点 `...`，Esc 关闭后右键仓库头） | 225 行（随批删） |
| ⑥ | `test/ide/git/git_autofetch_test.dart:789-863` | FakeGit 机检 ① 两支：复查抛错 ⇒ `merge --abort` 被调、错误含合并原话 + 复查原话；再叠 abort 失败 ⇒ 再拼 abort 原话 + 收尾提示 | 1085 行（随批删） |
| ⑦ | `test/ide/workbench/scm_repositories_test.dart:193-201` | 既有工作区菜单断言随文案改名（强制跟改，非语义变化） | 3/3 |

**读数（命令 + 结果）**
- `flutter test --no-pub test/ide/git/scm_fetch_button_test.dart test/ide/git/git_pull_real_test.dart test/ide/git/git_autofetch_test.dart test/l10n_test.dart` ⇒ **+94 全绿**。
- `flutter test --no-pub test/ide/git` ⇒ **+169 -12**；12 条红与基线同名同数（git_blame 1 / git_service 1 / scm_diff 5 / scm_multiselect 3 / timeline_view 1 / scm_view 1），零新增。
- `flutter test --no-pub test/ide/workbench/scm_repositories_test.dart` ⇒ 全绿（含在验收 5 文件跑中）。
- `flutter analyze --no-pub`（`lib/ide/git`、`lib/l10n`、两个测试档）⇒ No issues found。
- `flutter gen-l10n` ⇒ 退出 0；`scmFetchAndPullAll` 在三档生成物中（`app_localizations.dart:6951` / `_en.dart:4199` / `_zh.dart:3947`）。
- 行数（换行数实测）：`git_repository.dart` 586 ≤586；`ide_scm_view.dart` 4196 ≤4198。

**偏差 / 说明（如实）**
1. **ARB 行尾**：编辑工具会把 `app_en.arb` / `app_zh.arb` 的混合行尾（en 有 3647 处 CRLF）整档化成 LF。已 `git checkout --` 从索引恢复原始字节，再按字节插入新键（其余字节零改动）；复核 CRLF 计数 en 3647、zh 7 未变，`git diff --numstat` = en 4/0、zh 1/0。未整档格式化。
2. ① 的复查用 `Future.catchError` 收错（返回 true = 可能已开始合并），错误用列表 `join('\n')` 拼接；两行较长（117/112 字符）是为守住 §12.7 的 586 行上限，`flutter analyze` 无新增。
3. ② 未改 `lib/l10n/command_titles.dart:190`（`git.fetchAll` 的命令面板标题仍映射 `scmFetchFromAllRemotes`）——设计 §12.6-5 只覆盖工作区 `...` 菜单项，命令面板面不在本轮范围，已上抛知会。
4. 未改设计/需求档；未动他批未提交改动。`git status --porcelain` 相对基线的第二列仅本轮声明档：`git_repository.dart` / `ide_scm_view.dart` / 两个 arb / 三档生成物 / `scm_repositories_test.dart`（强制跟改）；`scm_fetch_button_test.dart` / `git_autofetch_test.dart` 为既有未跟踪批档。

**上抛**
1. **[上抛·待裁] 设计档同规则转述未跟更**：D18（`docs/design/ide-git.md:301`）与 §3.3 的 abort 行（`:119`）仍写「只在合并前无 `MERGE_HEAD`、现在有」时 abort，字面排除本轮新增的「复查失败也 abort」；只读这两处会复现本轮修掉的缺陷。批档 §6 已登记待裁，建议父侧文档层各补一句。
2. **[上抛·知会] 命令面板面残留旧文案**：`lib/l10n/command_titles.dart:190` / `lib/keybindings/workbench_keybindings.dart:539` 的 `git.fetchAll` 标题仍是 "Fetch From All Remotes"，而该命令已逐仓 fetch + merge；设计未覆盖该面，是否另批收口待父侧裁定。
3. **[上抛·知会] advisor 4 条 🔵 的处置**：`git_repository.dart:342` 陈旧注释已修；`scm_repositories_test.dart:204` 用例名未改（其标题与命令面板当前标题一致，merge 面由 P9 覆盖）；`ide_scm_view.dart:899` 的 `git.fetchAll` 注释保留（它按命令面板的当前标题命名，命令标题本身在范围外）；abort 失败分支已补机检（⑥ 第二支）。

## §6 验证与收口（父代理）

**验收读数（父侧复跑）**：验收 5 文件（`git_pull_real_test` / `scm_fetch_button_test` / `git_autofetch_test` / `git_operations_test` / `git_repository_test`）⇒ **+94 全绿**；`test/ide/git` 全量 **+169 −12**（12 条基线红与 HEAD 同名同数，零新增，见台账 #90）；`flutter analyze --no-pub` 改动面零新增；`flutter gen-l10n` 退出 0。

**机制面**：① 自动轮不快进 ⇒ 判定改为拉取操作内 fetch 后**现读 status**（不再读缓存 `state`，静默出口消灭；T1 真 git 一轮、T9 缓存 vs 现读、T10 fetch 成功但不拉 ⇒ `↓N` 出现）；② `↓N` 移到仓库头获取按钮右侧、`_headLabel` 不再含它（窄宽回落分支名右侧，仓库头内单源）；③ 获取 = 真拉取（`pullFromUpstream` 一次 `_operate`：fetch → 现读 status → 否决 → merge/ff → 回滚；`merge --no-edit`；冲突 ⇒ `merge --abort` + 三段原话；`merge` 入 300 秒放宽档）；④ **A 口径不变**（自动轮只 `--ff-only`、脏树整仓不拉、`↓N` 常显）；⑤ 多仓逐仓失败通知带仓库名。

**补丁轮**：#65 设计回灌五处（§12.2 复查失败契约 / §12.6-5 单仓与全仓菜单语义 / §12.7 ⑪ 读数 / §12.8 P4 实测）+ #67 实现跟进（复查失败不顶掉合并原话且仍 abort，FakeGit 机检两支；全仓菜单独立键 `scmFetchAndPullAll`）。

**未闭合（诚实面）**：设计 §12.9 的三条真机走查（获取拉下 / 冲突回滚 / 多仓断 remote）**未执行**——用户 2026-10-19 20:20「不验了，直接合并」明确跳过；上述行为由 P1–P9 / W1–W5 / S1–S2 / T1–T10 的机检覆盖（真 git 夹具 + FakeGit + widget 用例），但「真机同一时刻的观感」没有读数。

**台账**：#92 / #93 追认核销；#90（12 条基线红）保留；#98（命令面板 `git.fetchAll` 标题仍为 "Fetch From All Remotes"，面窄）归批；设计档 D18 / §3.3 / §12.1 / §12.3 的同规则转述漂移入 #53。

**状态**：已收口 2026-10-19。
