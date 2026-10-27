# 2026-10-27 · autofetch-removal
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-27 · 来源 = 用户 2026-10-26 22:07 裁定接受上游 SCM 面（弃 autofetch / 获取=fetch+merge / ↓N）；2026-10-27 00:21「开干」；来源 = kimi 合并审查（explore#24）查出 autofetch 引擎失去唯一构造点、设置页三控件成假开关。
> 台账 = #184（ide-git · 归批）。前情 = docs/batches/2026-10-27-merge-regressions.md（已收口 2026-10-27）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
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

**② C′ 组（`git_service` 四方法）** —— **认领**。父侧实测：`fastForward` 外部命中 6（全在 `git_autofetch_engine.dart` / `git_pull.dart`）· `abortMerge` 1（`git_repository.dart:731`，在 `pullFromUpstream` 内）· `changedPaths` 1（`:711`，同）· `merging` 2（`:720`/`:728`，同）—— 删 A 组与 `pullFromUpstream` 后全部失去消费者。且**上游一个都没有**（`git show origin/main:lib/ide/git/git_service.dart` 对四者零命中）⇒ 删了正好回上游形态。

**③ §1「待澄清」条** —— **关闭**。用户 2026-10-27 00:21「开干」即对删除方案的确认（前一次 22:07 已裁定接受上游 SCM 面）。时间线：22:07 裁定方向 → 23:50 之后修 6 处回归 → 00:21 「开干」= 对 #184 的执行授权。**若用户事后收回，本批可整批回退**（每删一组单独提交）。

**④ 两处待实施核（U1 `fake_git.dart` 其他消费者 / U2 泛型去掉后的返回值调用点）** —— 采纳，留实施首轮 `flutter analyze` 判；判不出来停下上报，不硬改。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**状态行**：设计完成 · 2026-10-27

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

## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
