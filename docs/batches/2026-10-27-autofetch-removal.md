# 2026-10-27 · autofetch-removal
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-27 · 来源 = 用户 2026-10-26 22:07 裁定接受上游 SCM 面（弃 autofetch / 获取=fetch+merge / ↓N）；2026-10-27 00:21「开干」；来源 = kimi 合并审查（explore#24）查出 autofetch 引擎失去唯一构造点、设置页三控件成假开关。
> 台账 = #184（ide-git · 归批）。前情 = docs/batches/2026-10-27-merge-regressions.md（已收口 2026-10-27）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-27
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：删除 autofetch 整簇（2026-10-27 00:25）

- **已定决定**：接受上游 SCM 面，放弃 fork 的「自动获取 / 获取=fetch+merge / ↓N 徽标」三件 · 用户原话：「接受上游」+ 22:07 会话裁定 · 时间：2026-10-26 22:07
- **已定决定**：本批只删不补，删除后 SCM 面为纯上游形态 · 用户原话：「开干」 · 时间：2026-10-27 00:21

**要删什么**（依据 = kimi 合并审查 explore#24 的逐行实核 + 登记表整顿后的现态）

| 组 | 对象 | 依据 / 现状 |
|---|---|---|
| A · 引擎与设置 | `lib/ide/git/git_autofetch.dart` · `git_autofetch_engine.dart` · `git_pull.dart` · `git_settings.dart` | 引擎唯一构造点已随合并消失（旧在 `main:lib/workbench.dart` 的 `_attachAutoFetch`）；全 `lib` 只剩 `git_autofetch_engine.dart:28-45` 的构造声明 |
| B · 假控件 | `lib/settings/pages/general_page.dart:487` 的挂载 + `git_settings.dart:56-89` 的两个开关与周期下拉 | 三个控件读写设置，但无引擎消费 ⇒ 点了没反应 |
| C · 仓库侧残留 | `lib/ide/git/git_repository.dart` 的 `lastFetchAt`（`:86-105`，只写不读）· `autoFetchIssue`（`:91-99`，只由引擎写）· `pullFromUpstream`（`:688-747`）· `fastForward`（`:749-755`，无调用方）· 相关 import（`:20-22`）与 clock 注入 | 全部失去消费者 |
| D · 测试档 | `test/ide/git/git_autofetch_test.dart` · `git_pull_real_test.dart` | 被测对象删除 ⇒ 同批删 |
| E · l10n | autofetch / 获取 / ↓N / `gitLastFetched` 等键（17 组，含 `scmFetchAndPullAll`、`scmFetchAndPull`、`scmBehindCommits`） | `lib/l10n/command_titles.dart:202` 已改上游 `scmFetchFromAllRemotes` ⇒ 旧键无消费者 |
| F · 文档 | `docs/requirements/ide-git.md` 的 autofetch / 获取 / ↓N 三节 · `docs/design/ide-git.md` 对应节 | D8：失效表达式删除，不留尸体 |

**不删什么**（kimi 复核的三处修正，逐条采纳）

1. **`lib/ide/git/git_repository.dart:871-875` 保留** —— 空仓构建期修复（`scheduleMicrotask(_notify)`，见 `release-notes/1.7.2.zh.md:19-21`），与 autofetch 无关，删了会让 `git init` 后立刻用挂掉。
2. **系统代理保留** —— `docs/design/ide-git.md:123-131` 是独立机制，删文档时只删 autofetch/获取/↓N 三节。
3. **`_enqueue` / `_operate` 回退成上游 `Future<void>` 形态** —— 它们是被 pull 返回值泛型化的（现 `:198-220`），删 `pullFromUpstream` 后应一并回退，否则仍不是上游形态。

**红线**：① 不动上游 SCM 面板（`ide_scm_view.dart` / `ide_git_log_view.dart` / `ide_git_commit_panel.dart`）；② 不动 `git_repository.dart:871-875`；③ 系统代理面零改动；④ 每删一组单独提交，便于单笔回退。

**待澄清（开工前问用户一次）**：这是**撤销 2026-10-19 02:01 用户亲口提出的功能**（原话「要把autofetch入池子…自动拉代码远端提交的功能」）。删除后无替代方案，除非重新实现。实施前需用户再点一次头。

### 上抛裁决（主 agent，2026-10-27 00:35）

**① 需求档改写** —— **已由父侧完成**（需求档是主 agent 的笔）。`docs/requirements/ide-git.md` 44 行 → **29 行**：标题改「Git 系统代理（ide-git）需求」· 模块目标只留代理 · 功能点 2 条（代理继承 + 复用既有设置）· 边界 2 条 · 验收 2 条 · 依赖改 `runGit` + Settings→Network。**autofetch / auto-pull / 多仓轮询 / 错误可见 / 不打断 / 获取=真拉取 / ↓N 七条全删**（D8：失效表达式删除，不留尸体）。

**② C′ 组（`git_service` 四方法）** —— **认领**。父侧实测外部消费：

- `fastForward`：六处，全在 `git_autofetch_engine.dart` / `git_pull.dart`；
- `abortMerge`：一处（`git_repository.dart:731`，在 `pullFromUpstream` 内）；
- `changedPaths`：一处（`:711`，同）；
- `merging`：两处（`:720`/`:728`，同）。

删 A 组与 `pullFromUpstream` 后全部失去消费者。且**上游一个都没有**（`git show origin/main:lib/ide/git/git_service.dart` 对四者零命中）⇒ 删了正好回上游形态。

**③ §1「待澄清」条** —— **关闭**。用户 2026-10-27 00:21「开干」即对删除方案的确认（前一次 22:07 已裁定接受上游 SCM 面）。时间线：22:07 裁定方向 → 23:50 之后修 6 处回归 → 00:21 「开干」= 对 #184 的执行授权。**若用户事后收回，本批可整批回退**（每删一组单独提交）。

**④ 两处待实施核（U1 `fake_git.dart` 其他消费者 / U2 泛型去掉后的返回值调用点）** —— 采纳，留实施首轮 `flutter analyze` 判；判不出来停下上报，不硬改。

### 评审裁决（主 agent，2026-10-27 00:35）— pass（🔴0 · 🟡7 · 🔵4）

**全部接受，一轮修完**。三条口径先定，避免修轮再猜：

| 评审 # | 父侧口径（设计者按此修） |
|---|---|
| 1 | §5 ⑪ 改成**已完成的现态**（需求档已改写、29 行、无残项），从受影响文件表移出或标「已完成」；批档 §2 上抛项 1 由设计者 append 一句「已由 §1 裁决 ① 关闭」，别让两处状态并存 |
| 2 | **保留需求档的来源行**（那是用户原话的出处，删了等于抹掉原始诉求）；判据收缩为「需求档规范面（§1–§5）`grep -ci autofetch` = 0」，出处行不计 |
| 3 | 三类清单补全为：删除清单（§5 ①②⑥⑧⑩⑪ 及表后判据）· 旧键名（§3.2 / §6-D6 / §7 / §8-B1·E2）· 上游键说明（§2.3） |
| 4 | §2.2 偏离 / §4 / §6 每行加「现态 ∥ 本批」标注；**先实读 `packages/bao_remote/lib/src/git/git_runner.dart` 判 `gitTimeoutFor` 是存量还是新增**：存量 ⇒ 给坐标并注「存量，本批零改动」；新增 ⇒ 补 §5 行 + §7 验收行 + three-question 答案。§4 的扫描失败分支同样先判存量/新增，新增就补场景来源 |
| 5 | `（§1 条 3）` → `（批档 §1「不删什么」第 3 条）` |
| 6 | 实读 `test/RTM.md` 定案：查过 ⇒ 删 U3 并把检索命令与零命中写进 §9；没查 ⇒ 先读再定 §9 |
| 7 | §6 增 D9：>800 存量债、本批不动、触发点 = 下次碰历史命令段/图段，指回 §5.1 |
| 8–11 | 照评审建议改：l10n 豁免给依据 · 行数统一（627 标为改写前）· 键数对齐 21 · 验收列拆「机检 / 走查」并点名存在的测试档 |

**红线**：不改代码；不动需求档（父侧笔）；不新增删除对象（C′ 组已认，除此之外一律不加）。

**派单三句**：① 每条 `Suggestion` 是评审建议、执行者是子代理、父侧已逐条接受并按上表定口径；② 按编号 `1..11` 修，回报「编号 → 改动 file:line」；③ 本轮**不做**：不动 §5 的删除清单范围、不改验收里的删除判据（`grep` 零命中那几条本身是对的）、不碰系统代理面。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成 · 2026-10-27（修轮：§3 评审 11 条逐条处置，改动全在 docs/design/ide-git.md）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

| # | 条目 | 设计档落点 |
|---|---|---|
| 1 | A 组删除：`git_autofetch.dart` · `git_autofetch_engine.dart` · `git_pull.dart` · `lib/settings/pages/git_settings.dart` 四档整删 | design §5 ①–④ |
| 2 | B 组删除：`general_page.dart:487` 的 `GitSettingsGroup` 挂载 + import | design §5 ⑤ |
| 3 | C 组删除：`git_repository.dart` 的 `lastFetchAt` / `autoFetchIssue` / `_markFetched` 及三处调用 / `clock` / `pullFromUpstream` / `fastForward` / 两个 import；`_enqueue`·`_operate` 回退 `Future<void>` | design §5 ⑥ |
| 4 | C′ 连带删除：`git_service.dart` 的 `fastForward` / `merging` / `abortMerge` / `changedPaths`（同一判据：无消费者） | design §3.3、§5 ⑦ |
| 5 | D 组删除：`test/ide/git/git_autofetch_test.dart` · `git_pull_real_test.dart` | design §5 ⑩ |
| 6 | E 组删除：20 个 l10n 键（`app_en.arb` / `app_zh.arb` + `gen-l10n` 重新生成） | design §5 ⑧⑨ |
| 7 | F 组文档：设计档已按删除后现态重写；需求档待主 agent 改 | design §5 ⑪⑫ |
| 8 | 保留面零改动：空仓 `scheduleMicrotask(_notify)` · 系统代理面 · 上游 SCM 三档 | design §10 |

**本批不覆盖**：重新实现任何「自动关注远端提交」形态 · 用户 settings.json 的清洗 / 迁移 · `git_service.dart` / `git_repository.dart` / `general_page.dart` 的体积拆档。

### 设计档落点

`docs/design/ide-git.md` 已按删除后的现态重写（627 → 209 行）：删掉 autofetch / 获取 / ↓N 各节，保留系统代理（§3.4）与仓库扫描失败面（§4），并写入本批的受影响文件表、验收对照、用例表、边界与未核实点。

### 受影响文件与行数

见 design §5 表 ①–⑫（本批编制时换行数实测 + 预算后行数）；跨档文件的缝与触发见 design §5.1。删除面判据 = 无消费者，grep 读数与实施首轮的复核口径见 design §5 表后三条。

### 验收对照

见 design §7 表（八行，逐行一条机检命令或一处 `git diff --stat` 断言）。运行检查：`flutter analyze` 全仓零 error + `flutter test test/ide/git/` 绿。本批两个测试档随批删，不新增单测。

### 关键决策

D3 删除而非留空壳 · D4 残留按「无消费者」一并删 · D5 l10n 删键与重新生成同批 · D6 用户旧设置不动、不清洗 · D7 文档删失效节 · D8 每删一组单独提交。理由与被否项见 design §6。

### 上抛项

1. **[上抛·待裁] 需求档须由主 agent 改写**：`docs/requirements/ide-git.md` 现在整篇是 autofetch / 获取 / ↓N；删掉三节后标题、状态行、§1 模块目标都不再成立。建议保留系统代理面（§2.3、§3 代理条、§4.4、§5），标题改「Git 系统代理（ide-git）需求」。需求层不是我的写面，我没有动它。
2. **[上抛·知会] C′ 组不在 §1「要删什么」的字面清单里**：判据是同一批 C 组的理由（全部失去消费者），grep 读数见 design §5。若认为越界，删掉 C′ 一项即可，其余不受影响。
3. **[上抛·知会] §1「待澄清」条的复点**：§1 要求「实施前需用户再点一次头」；批档页首记载 2026-10-26 22:07 裁定 + 2026-10-27 00:21「开干」。设计按已裁定推进，这一条请主 agent 在 §1 / §4 明确关闭。
4. **[上抛·知会] `test/ide/git/fake_git.dart` 是否还有别处消费未核**（design §10.1 U1）：实施首轮 `flutter analyze` + `flutter test test/ide/git/` 判。

### 修轮（2026-10-27 · §3 评审 11 条逐条处置）

评审 VERDICT: pass（🟡 7 · 🔵 4）。逐条落点如下，改动全在 `docs/design/ide-git.md`。

| # | 处置 | 落点 |
|---|---|---|
| 1 | 已修：§5 ⑪ 改为删除后现态（需求档 29 行、无残项），不再写成待办 | design §5 ⑪ |
| 2 | 已修：判据收到规范面——需求档 §1–§5 查 autofetch = 0；档头「来源」行不属规范面、不计，删除史只留批档 | design §7 §2-6 |
| 3 | 已修：三类改为按位置枚举（删除清单 · 旧设置键名 · 上游键说明），并把 §5 ⑥⑧、表后判据与 §8-E2 补进类内；本档唯一一处不在三类内的表述已改写（§2.2 的现态声明不再带该词） | design §7 §2-6、§2.2 |
| 4 | 已修：§2.2 加「本节写的都是现态」声明；两条偏离改为现态表达（坐标 `git_runner.dart:40-76`），删掉「原为 60 秒固定超时」这句历史；§3.4 标现态，§4 标现态 + 实现坐标 `lib/workbench.dart:3763-3819`。`gitTimeoutFor` / `gitProcessEnvironmentMap` / `setGitProcessEnvironment` 三处经本轮实读确认为存量，因此不进 §5 改动清单 | design §2.2、§3.4、§4 |
| 5 | 已修：删悬空的「（§1 条 3）」，回退理由在本档写全——不改指批档（状态档不指一次性档） | design §5 ⑥ |
| 6 | 已修：实读 `test/RTM.md`（66 行 / 4 条用例 1-1…4-1 / 规模窗 4 / 50–100），全文检索 git、scm、fetch、获取、仓库、拉取 零命中 ⇒ §9 零行 delta 成立；U3 从 §10.1 删除 | design §9、§10.1 |
| 7 | 已修：§6 增 D9（三个 >800 档本批不拆，缝与触发点见 §5.1）——「不拆」从边界旁白变成记录内裁决 | design §6-D9 |
| 8 | 已修：§5.1 补依据——`app_localizations*.dart` 是 `flutter gen-l10n` 生成物，权威是生成器、手改会被下次生成覆盖 | design §5.1 |
| 9 | 已修：行数口径统一为 `\n` 计数（= `wc -l`），全表复测；本档自身评审读数 212 → 修后 214；`627` 是改写前旧值，已删不留 | design §5 表头 + ⑫ |
| 10 | 已修：键数 = 21，按 21 个键名逐个列全（en / zh 同名，`@` 块在 en，坐标 en `:8893-9049` / zh `:3349-3381`）；「17 组」「20 键」两个旧数不再使用 | design §5 ⑧ |
| 11 | 已修：§7 判据列拆「机检 / 走查」两栏；运行检查点名删后实际存在的 41 个测试档 + 夹具 `fake_git.dart` | design §7 |

**上抛项关闭**：上抛项 1（需求档改写）由 §1「上抛裁决 ①」关闭——需求档已由父侧改写完成（44 → 29 行），design §5 ⑪ 同步改为现态。上抛项 2（C′ 组）由 §1「②」认领。上抛项 3（§1「待澄清」条）由 §1「③」关闭。上抛项 4（U1）保留为实施首轮判据。

**本轮新发现（不在评审单内，交主 agent 定）**：需求档档头「来源」行（`docs/requirements/ide-git.md:5`）写着「autofetch / 获取 / ↓N 已于 2026-10-27 按用户裁定移除」。这是「已移除物件的否定陈述」——检索面无法表达否定，这类句子会被当现态取回。删不删属需求档（父侧的笔），本档只把验收判据收到规范面，不裁决这一行。

**本轮实读读数**：

- `docs/design/ide-git.md` 214 行；`docs/requirements/ide-git.md` 29 行，规范面（§1–§5）autofetch / 获取 / 拉取 零命中。
- `test/RTM.md` 66 行、git 面零命中；`app_en.arb` / `app_zh.arb` 各 21 键。
- `test/ide/git/` 44 项 = 41 个测试档 + 夹具 `fake_git.dart` + 2 个待删档。
- `git_runner.dart` 300 行且 `gitTimeoutFor` 等在档（存量）。

`flutter analyze` / `flutter test` 未跑——本批是设计轮，运行检查属实施轮。`doc_check(mode:"gate")` 首行 PASS。

### 修轮补记 · 对「评审裁决」口径的两处偏差（2026-10-27）

读回 §1「评审裁决（00:35）」后逐条比对，11 条处置与该口径一致；两处写法偏差在此写明。

1. **第 5 条**：口径要求改成「（批档 §1「不删什么」第 3 条）」。本档没那么改，改为把回退理由在本档写全、不指向批档——状态档指一次性档（批档可整档删除）会留下删档即死的指向，理由同口径要达成的目标（去掉悬空指针）。
2. **第 9 条**：口径要求「627 标为改写前」。本档把 627 直接删了：状态档只写现态，历史归 git 提交与批档；现读数 214（`\n` 计数），全表同口径复测。
3. **上一段「本轮新发现」已由 §1 口径 #2 结掉**：需求档来源行（`docs/requirements/ide-git.md:5`）**保留**——那是用户原话的出处；验收判据已按此收到规范面（§1–§5）。该条不再是待裁项。

**另**：本节早前正文把若干数字留在旧值上（l10n 键数写 20、需求档写「待主 agent 改」、「627 → 209 行」）。§2 是 append-only，本工具不改既有行，以本修轮的补记与 design 为准：键数 21 · 需求档已改写（29 行）· 本档 214 行。父侧若要与现态对齐，需按文件编辑就地改那几行。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

**评审对象**：`docs/design/ide-git.md` · `docs/requirements/ide-git.md` · 本批记录。无 AGENTS.md / 项目规范档 / 文档地图 ⇒ 方法学与文档归属只能按批档六段形态与评审准则判。

**范围限制（先声明）**：评审对象声明限定只读这三份文档 ⇒ 准则 8 要求的行数抽查未执行，§5 表内所有行数（`git_runner.dart` 是否已带 `gitTimeoutFor`、各档 1001/1705/845/9171 等）均为 **unverified**；`test/RTM.md` 不在评审面 ⇒ §9/§10.1-U3 的 RTM 内容为 **unverified**。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|------|--------|------|------|
| 1 | 需求覆盖 / 文档状态 | 🟡 | 设计 §5 ⑪ 仍把需求档改写写成待办：「`docs/requirements/ide-git.md`（45）」（`docs/design/ide-git.md:114`）、结论列「待主 agent 落」，并逐条点名 §2.1/§2.2/§2.4–§2.8 等节；而这些节在需求档里已不存在——需求档现为 29 行、标题已是「Git 系统代理（ide-git）需求」、只留代理面（`docs/requirements/ide-git.md:1`）。批档 §1 亦记「已由父侧完成」（`docs/batches/2026-10-27-autofetch-removal.md:37`：44 行 → 29 行），但同档 §2 上抛项 1 仍称「需求档须由主 agent 改写」（`docs/batches/2026-10-27-autofetch-removal.md:84`）⇒ 三处对同一事实给了两种状态，实施方无法判定 ⑪ 是否还有活。 | 把 §5 ⑪ 改成删除后现态（需求档=已改写，30 行左右，无残项）；若确无残项就从受影响文件表移出、并在批档 §2 上抛项 1 标注「已由 §1 裁决 ① 关闭」，只留一处权威状态。 |
| 2 | 验收 | 🟡 | §7 §2-6 的判据「需求档改写后 `grep -ci autofetch` = 0」（`docs/design/ide-git.md:157`）按现盘状态**必然失败**：需求档的来源行含「autofetch / 获取 / ↓N 已于 2026-10-27 按用户裁定移除」（`docs/requirements/ide-git.md:5`，`grep -ci` 记 1 行）。这条要么逼实施方删掉记录用户原始诉求的出处行，要么在收口时挂红。 | 把判据收到**规范面**：改判「需求档规范面（§1–§5）`grep -ci autofetch` = 0」或直接判「无 autofetch / 获取 / 拉取 节」，出处行不计；删除史只留在批档。 |
| 3 | 验收 | 🟡 | §2-6 第二句「本档 `grep -n autofetch` 的每一行只属三类」（`docs/design/ide-git.md:157`）**按字面自证伪**：不区分大小写的命中还落在 `docs/design/ide-git.md:109`（§5 ⑥ 的 `autoFetchIssue`）、`:111`（§5 ⑧ 的 `gitAutoFetch*` 键名）、`:119`（§5 表后判据的 `ideGitAutoFetch*`）、`:177`（§8 E2 的 `gitAutoFetch*`），四行都不属于它列的三类（§5 ①②⑩⑪ · 旧设置键名 · 上游键说明）。 | 把三类补成「删除清单（§5 ①②⑥⑧⑩⑪ 及表后判据）· 旧键名（§3.2 / §6-D6 / §7 / §8-B1·E2）· 上游键说明（§2.3）」，或把判据改写为「无一行把 autofetch 描述成活机制」——补完这条才可通过。 |
| 4 | 范围 / 清晰 | 🟡 | 设计未区分**现态说明与本批改动**：§2.2 偏离 2 说「`runGit` 原为 60 秒固定超时」（`docs/design/ide-git.md:35`）并按命令名放宽到 300 秒，§6 将其列为决策 D2（`docs/design/ide-git.md:140`）；但 §5 受影响文件表**没有** `packages/bao_remote/lib/src/git/git_runner.dart` 一行，§10 又写「不改 `packages/bao_remote` 的代理注入契约」（`docs/design/ide-git.md:196`）。同一机制在两处一说「改了」、一说「零改动」。同形问题：§4 的扫描失败重试 / `scmScanFailed` 单次提示（`docs/design/ide-git.md:94-96`）既无 §5 行、无 §7 验收行，也未给分支来历（场景 / 可复现路径）——若它是本批新增分支，则缺 6b 要求的情景来源。（`git_runner.dart` 现状未核实：源档不在本次评审面。） | 在 §2.2 偏离 / §4 / §6 每行加「现态（某批已落）∥ 本批」标注，并把 §5 的受影响文件表保持为唯一改动清单；`gitTimeoutFor` / `gitProcessEnvironmentMap()` / `setGitProcessEnvironment` 三处写明是存量（给坐标）还是本批新增（补 affected-file 行 + 验收行 + existing-piece 三问）。§4 若为本批新分支，补情景来源，否则注明存量。 |
| 5 | 清晰 | 🟡 | §5 ⑥ 尾注「（§1 条 3）」（`docs/design/ide-git.md:109`）指向悬空：设计档 §1 只有模块目标、范围与「不做的事」，没有编号条（`docs/design/ide-git.md:6-11`）；该内容实际是**批档** §1「不删什么」第 3 条（`docs/batches/2026-10-27-autofetch-removal.md:29`）。 | 改为「（批档 §1「不删什么」第 3 条）」或直接在本档把回退理由写全。 |
| 6 | 集成测试设计 | 🟡 | §9 与 §10.1 对同一事实相反：§9 称「`test/RTM.md` 已查」（`docs/design/ide-git.md:187`，「编制时全文检索 … 零命中」）据此把 delta 定为零行；§10.1 U3 又把「`test/RTM.md` 的 git 面行集」列为未核实，判定条件为「打开该档逐行核对（§9）」（`docs/design/ide-git.md:204`）。两者不能同真；若 U3 成立，§9 的零行 delta 就没有已记录的 RTM 读。（RTM 档不在评审面，内容未核实。） | 二选一：查过就删 U3 并把检索命令与零命中写进 §9；没查就先读 `test/RTM.md` 再定 §9。 |
| 7 | 体积档 | 🟡 | `git_service.dart`（1705 → ~1655，`docs/design/ide-git.md:129`）与 `git_repository.dart`（1008 → ~904，`docs/design/ide-git.md:130`）删后仍 >800，明确「本批不拆」（`docs/design/ide-git.md:194`）。>800 档没有豁免通道；本档虽给了缝（`git_history_service.dart` / `git_repository_graph.dart`）与触发点，但「不拆」只是在 §10 边界里说了一次，未作为裁决落进 §6，读起来像默认而非已决。按既定约定（体积存量债不重开）不作阻断项。 | 在 §6 增一行 D9：>800 存量债、本批不动、触发点 = 下次碰历史命令段 / 图段，并指回 §5.1；让「不拆」成为记录内的裁决而不是边界旁白。 |
| 8 | 体积档 | 🔵 | §5.1 用一句声明把 `lib/l10n/*.arb` 与 `app_localizations*.dart` 划出源码行数档（`docs/design/ide-git.md:125`，理由是资源 / 生成物），但 `app_localizations.dart`（20506 行）在 `lib/` 下是 `.dart` 档，准则的档位表述没有这条豁免；本档未引任何裁决坐标。 | 在该句补依据（生成物不得手改、权威是 `flutter gen-l10n`；要动只能改生成器），否则后续批次会按同一句再次豁免。 |
| 9 | 数字漂移 | 🔵 | §5 ⑫ 把本档自身的行数记为 627（`docs/design/ide-git.md:115`），而现盘本档为 212 行内容（末条 `docs/design/ide-git.md:212`）；批档 §2 记「627 → 209 行」（`docs/batches/2026-10-27-autofetch-removal.md:68`）。三处数字不一致。 | 统一为改写后的实测行数，并把 627 标为改写前行数。 |
| 10 | 数字漂移 | 🔵 | l10n 键数三处不一：设计 §5 ⑧ 写「删 20 键及其 `@` 元数据」（`docs/design/ide-git.md:111`），同句逐名列出实为 21 键（19 个基名 + 2 个 `+Description`）；批档 §1 写「17 组」（`docs/batches/2026-10-27-autofetch-removal.md:22`），§2 写「20 个 l10n 键」（`docs/batches/2026-10-27-autofetch-removal.md:60`）。逐名清单权威且 §2-5 的 grep 覆盖全部名，故只影响核对。 | 键数只写一处并与逐名清单对齐（21）。 |
| 11 | 验收 | 🔵 | §7 第三列标题为「判据（机检）」（`docs/design/ide-git.md:150`），但 §2-2 的「设置 → General 打开后 Items 里没有 Git 分组」（`docs/design/ide-git.md:153`）与 §2-8 的「无异常日志」（`docs/design/ide-git.md:159`）是人工走查；运行检查写的是目录 `flutter test test/ide/git/`（`docs/design/ide-git.md:161`），未点名剩下哪些档。 | 该列拆「机检 / 走查」两栏；运行检查点名删除后实际存在的那几个测试档（或注明本批两个档随批删）。 |

VERDICT: pass

计数：🔴 0 · 🟡 7 · 🔵 4

## §4 用户批准（主 agent）

### 用户批准（2026-10-27 01:05）

**批准口径**：用户 2026-10-27 00:21「开干」= 对删除方案的执行授权（前情 22:07 已裁定接受上游 SCM 面）；00:33「要，我不喜欢休息」= 继续实施；00:45「拉一下代码」期间未收回。**若事后收回，本批可整组回退**（7 笔提交各自独立）。

**批准时的状态**

| 项 | 状态 |
|---|---|
| 代码 | 7 笔提交落地：`16a6830e`(§5) · `17e88b8f`(l10n) · `04f1533b` · `3f59d5cc` · `7513e66b` · `cedd3a0e` · `7a46a7c6` |
| 设计 | `docs/design/ide-git.md` 214 行（删除后现态）· `docs/requirements/ide-git.md` 29 行 |
| 评审 | 设计评审 `ed218d95` **pass**（🔴0 · 7🟡 · 4🔵 全修）；实施内部审计五面全过 + 代码评审 pass（🔴0 🟡0 🔵3，三条均「不改」并有理由） |
| 验证 | `flutter analyze` **0 error**（7 条 warning/info 全在未触碰的测试档）· `flutter test test/ide/git/` **+204 −1**（唯一失败 = 已裁定的存量 `ask_ai_test.dart:134`） |
| 合并 | 上游 3 提交（含 #386 Git 面）已合入，**零冲突**；合并后 analyze 仍 0 error |

## §5 实施记录（eng-coder）
**状态行**：实施完成（6 笔提交 · analyze 零 error · test/ide/git +203 −1（唯一失败为存量 ask_ai_test.dart:134，父侧裁决保持原样）· 审计+评审各 1 轮，终态 clean）



### 实施记录（eng-coder · 2026-10-27）

**做了什么**：按 design §5 表 ①–⑩ 删除 fork 的 autofetch 整簇，SCM 面回上游形态。14 个文件、6 笔提交、净 +9 / −2925 行。

#### 逐条覆盖（design §5 表 ↔ 现态）

| # | 条目 | 状态 | 落点 / 读数 |
|---|---|---|---|
| ①②③ | `git_autofetch.dart`(300) · `git_autofetch_engine.dart`(410) · `git_pull.dart`(52) | ✅ | 三档已不在盘 |
| ④⑤ | `git_settings.dart`(112) 整删 · `general_page.dart` 去挂载与 import | ✅ | `grep "GitSettingsGroup\|git_settings" lib/` 零命中；现 843 行（预算 ~842） |
| ⑥ | `git_repository.dart` 残留 + 泛型回上游 | ✅ | 1007 → 902 行（预算 ~903）；`lastFetchAt` / `autoFetchIssue` / `_markFetched` / 三处调用 / `clock` / `pullFromUpstream` / `fastForward` / 两个 import 全去；`_enqueue`(`:169`) 与 `_operate`(`:189`) 回 `Future<void>` |
| ⑦ | `git_service.dart` 四方法 | ✅ | 1704 → 1658 行（预算 ~1654）；`merge(ref)` 保留，`git_branch_actions.dart:146` 仍在用 |
| ⑧⑨ | 21 个 l10n 键 + 重新生成 | ✅ | `app_en.arb` −109 行、`app_zh.arb` −21 行（恰为 21 键）；三个生成档由 `flutter gen-l10n`（退出 0）重出；五档对 21 键全部零命中 |
| ⑩ | 两个测试档 | ✅ | 两路径已不在盘 |
| ⑪ | 需求档 | ✅ 父侧已完成 | 29 行，规范面（§1–§5）无 autofetch；档头来源行按 §1 裁决 #2 保留 |
| ⑫ | 设计档 | ✅ 已完成 | 214 行，按删除后现态 |

`test/ide/git/` 现为 **41 个测试档 + 夹具 `fake_git.dart`**（共 42 项）。删前 44 项 = 这 41 个 + 夹具 + 本批删掉的 2 个——不是删少了档。

#### 提交（每删一组单独提交，D8）

| # | 提交 | 组 | 文件 |
|---|---|---|---|
| 1 | `7a46a7c6` | D 测试档 | 2 个测试档删除 |
| 2 | `cedd3a0e` | B 控件 + 挂载 | `git_settings.dart` + `general_page.dart` |
| 3 | `7513e66b` | A 引擎（叶子） | `git_autofetch_engine.dart` |
| 4 | `3f59d5cc` | C 仓库侧 + C′ | `git_repository.dart` + `git_service.dart` |
| 5 | `04f1533b` | A 余下两档 | `git_autofetch.dart` + `git_pull.dart` |
| 6 | `17e88b8f` | E l10n | 两个 arb + 三个生成档 |

**A 组为什么拆成两笔**：A 与 C 互相引用——引擎档调用 `pullFromUpstream` 与 `service.fastForward`，仓库档 import `git_pull.dart` 的类型。任何一侧先落，中间那笔都编译不过。按可编译顺序落：引擎（叶子）先走，仓库侧跟上，最后删掉失去全部 import 者的两档。组粒度只变细不变粗，单笔回退照旧成立。

#### 验证读数（实施轮实跑）

| 检查 | 命令 | 读数 |
|---|---|---|
| 静态分析 | `flutter analyze`（全仓） | **7 issues / 零 error**；7 条全在未触碰的测试档（`session_overlay_test.dart` 5、`lsp_settings_template_test.dart` 1、`remote_project_test.dart` 1），均为存量 |
| git 面测试 | `flutter test test/ide/git/` | **+203 −1**；唯一失败 `test/ide/git/ask_ai_test.dart:134`——断言 prompts 含 `lib/a.dart`，Windows 实际给 `lib\a.dart`。**存量**：在实施前基点 `cc18fad1` 单跑该档得 `+3 −1`、同一报错 |
| 设置面测试 | `flutter test test/settings/settings_wiring_test.dart` 等三档 | 新树 `+8 −4`；基点上 `+4 −4`、**同四条**（3 条 Windows 临时目录 `PathAccessException` 收尾 + 1 条 "Automatic" 文案查找）⇒ 存量、环境性 |
| l10n 生成 | `flutter gen-l10n` | 退出 0，三个生成档重出 |
| 文档门 | `doc_check(mode:"gate")`（设计档 + 需求档） | 首行 `DOC-CHECK GATE: PASS` |

**验收判据（按父侧 2026-10-27 裁决改判）**：`test/ide/git/` 判「除 `ask_ai_test.dart:134` 这条存量外全绿」。本批运行读数为 `+203 −1`，失败即该条，非本批引入；断言与产品两侧均未改动。

#### 关键判据复核（design §5 表后三条）

实施首轮按同一 grep 复跑：`lastFetchAt` / `autoFetchIssue` / `pullFromUpstream` / `ideGitPull` / `ideGitAutoFetch*` / `service.fastForward|merging|abortMerge|changedPaths` 在 `lib/` 与 `test/` 全部零命中。命中集与预期完全一致，未出现预期外消费者，删除面未扩大。

#### 偏离与披露

| 项 | 说明 |
|---|---|
| 提交顺序 | D8 列的是 A/B/C/D/E/F；实落顺序为 D → B → A(引擎) → C+C′ → A(余下) → E，理由同上（每一笔都要编译得过）。F 组无待办——父侧与设计轮已完成 |
| 清单外的改动 | **无**。14 个文件 = design §5 ①–⑩ 的并集；`ide_scm_view.dart` / `ide_git_log_view.dart` / `ide_git_commit_panel.dart` / `packages/bao_remote` / `lib/network` 零改动 |
| 行数预算 | `git_repository.dart` 902（~903）· `git_service.dart` 1658（~1654）· `general_page.dart` 843（~842），均在预算内 |
| design §5 ⑧ 坐标 | en 的删除区间写到 `:8893-9049`，实删到 `:9057`（最后一个 `@gitAutoFetchOther` 块尾）；zh `:3349-3381` 与实测一致 |
| §2-8 走查 | **未跑**（需起 GUI 应用）。可机检的一半已证：`lib/` 对 `git.autofetch` / `autoPull` 零读取，设置读法是 `settings?[...]` 容错取键、无键白名单 ⇒ 带旧键的 settings.json 不会炸 |
| 用户旧设置 | 未迁移、未清洗（D6），且零代码读取 |

#### 审计与评审

| 轮 | 类型 | 结果 | 处置 |
|---|---|---|---|
| 1 | 内部 explore 偏离审计（只读，逐条对 design） | 五个检查面全过；**1 条文档漂移** | `docs/design/fork-deltas.md:31` 仍把 `test/ide/git/git_autofetch_test.dart` 登记为现存的 fork 自有档；`:268` 的「autofetch 死代码清理在 #184」是本批要做完的待办指针。**设计档不是我的笔**，未改，交父侧按 D1 路由 |
| 1 | 独立代码评审（advisor · type=code） | **VERDICT: pass**（🔴0 · 🟡0 · 🔵3） | 三条 🔵 处置见下 |

**三条 🔵 的处置**

1. `git_repository.dart:106` 的 `_enqueue(background: true, () async {`（命名参数排在位置参数前）：**不改**。逐字比对 `git show origin/main:lib/ide/git/git_repository.dart` 第 106 行，上游就长这样；本批目标是回上游形态，改它反而成了偏离。
2. `test/ide/git/fake_git.dart:40`（`merges` 映射）与 `:166`（`case ['merge', '--ff-only', final ref]:`）：`fastForward` 删掉后已无生产发出者，成为死夹具分支，无行为影响。**不改**——该档不在 design §5 清单内，§1 红线「不新增删除对象」。建议 `归批`：下次碰 git 夹具时扫掉。
3. 批档 §2 第 6 行「20 个 l10n 键」与现态 21 的差：§2 是 append-only，同节补记已自行声明这几处为旧值，**不改**，属已披露漂移。

**终态**：`clean` —— 审计 1 轮 + 评审 1 轮，零修复轮，无未决修复项。

**上抛（待父侧路由）**：`[上抛·待裁]` `docs/design/fork-deltas.md:31` / `:268` 的设计档漂移——由 eng-designer 就地改（删该登记行、收掉 #184 的待办指针），或记 `归批`。

## §6 验证与收口（父代理）

### 父侧独立核验（2026-10-27 01:10）— 不采信子代理报告，逐条 grep

| 检查 | 读数 |
|---|---|
| 6 个待删档 | **全部已删**（`git_autofetch.dart` · `git_autofetch_engine.dart` · `git_pull.dart` · `settings/pages/git_settings.dart` · 两个测试档） |
| 该留的空仓修复 | **在**：`lib/ide/git/git_repository.dart:770` `scheduleMicrotask(_notify);` |
| l10n 旧键 | `app_en.arb` **0 处** · `app_zh.arb` **0 处**（查 `gitAutoFetch` / `gitLastFetched` / `gitPeriodMinutes` / `generalSettingsGit` / `scmFetchAndPull` / `scmBehindCommits`） |
| 死代码 | `lib/` 对 `IdeGitAutoFetch` / `GitSettingsGroup` / `pullFromUpstream` **零命中** |
| 编译 | `flutter analyze --no-pub` = **0 error**（7 条 warning/info，全在未触碰的测试档） |
| 测试 | `flutter test test/ide/git/` = **+204 −1**；唯一失败 `ask_ai_test.dart`（存量，已在批外基点复现） |
| 工作树 | 干净 |

**批量**：删 6 档 / 改 9 档 · **净 +89 / −2925 行** · 7 笔提交，各自可单笔回退。

### 合并上游 3 提交（2026-10-27 01:08）

`origin/main` 新增 3 提交（#386 Git 检查点移出 UI isolate · #384 忽略目录不读 status · #382 步骤动画同帧），**与本次删除面重叠（都在 `lib/ide/git/**`）但合并零冲突**。合并后：`analyze` 0 error · `test/ide/git/` +204 −1（同上存量）· 与上游差距 **179 / 0**。

**过程中撞到一个坑并已按既有经验处置**：合并后首跑 `flutter test` 报 `Building native assets failed`（hook 退出码 253）⇒ 删 `.dart_tool/hooks_runner` + `flutter pub get` ⇒ 恢复。**这是构建缓存失效，不是代码问题**，已记入本节以免下次误判。

### 结算（2026-10-27 01:12）

| 项 | 结论 |
|---|---|
| 删除面 | A/B/C/C′/D/E/F 七组全落，逐组核验通过 |
| 保留面 | 空仓修复 · 系统代理 · 上游 SCM 三档 · `packages/bao_remote` **零改动**（`git diff --stat` 对 `packages/` / `lib/network/` / SCM 三档零命中） |
| 设计/需求档 | 均已是删除后现态；`doc_check(gate)` **PASS**（3 档） |
| 单元测试 | 两个测试档随被测对象同批删除（不新增）；本批验证读数 = analyze 0 error + `test/ide/git/` +204 −1 |
| 集成测试 | RTM 66 行、git 面零命中 ⇒ delta = none（本批是删除，无新业务故事） |
| 台账 | #184 核销 · #185 已核销（需求档）· #192 新增（ask_ai 存量归批） |
| 未做 | `fake_git.dart:40/:166` 的死夹具（越出 design §5 清单，建议归批）· §2-8 的旧 settings.json 走查（需起 GUI，可机检的一半已证） |

**转出债**：`docs/design/fork-deltas.md:31` 仍把 `test/ide/git/git_autofetch_test.dart` 登记为现存自有档、`:268` 仍写「autofetch 死代码清理在 #184」——设计档是 eng-designer 的笔，另派一轮改（本批不碰）。
