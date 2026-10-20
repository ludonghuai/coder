# 2026-10-19 · ↓N 数字放进「获取」按钮内（轻渠道 UI 细节）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 20:33「能把⬇N放在一起吗？就是把数字直接放进那个按键里面，好看一点，现在显得有点奇怪」+ 截图（获取图标旁独立 ↓2）。
> 台账 = #99（ide-git · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
**本笔披露**：This pen = light channel（detail — 视觉/位置）| change: `↓N` 数字从获取按钮右侧的独立徽标改为**按钮内**（图标 + 计数同一点击区；窄宽仍回落到分支名后的 `↓N`）| reach: `lib/ide/git/ide_scm_view.dart`（`_InlineAction` 加 `iconWidget`/`width`、新增 `_fetchWithBehind` / `_fetchWithBehindWidth`、头部去掉独立徽标）+ `test/ide/git/scm_fetch_button_test.dart`（W1/W2/W3/W5 随改）| rollback = revertable
**本批条目**：① 宽屏仓库头的获取按钮内显示待拉取提交数（图标 + 数字），不再在按钮右侧另起一个 `↓2`；窄宽仍是分支名后 `↓N`；状态栏 `↓N` 不动。
**关键判据**：W1（按钮内含 '2'、行内无独立 `↓2`、按钮在 Refresh 左侧）· W2/W5（分支标签无 `↓`、按钮内恰一个计数）· W3（behind 0 无计数）· W4 不变（窄宽 `↓2` 在分支后）；tooltip 含 `scmFetchAndPull` 与 `scmBehindCommits(N)`。
**授权口径**：用户 2026-10-19 20:33 逐字 + 截图（获取图标旁的独立 `↓2` 显得重复）。

> 不适用：§2 —— 设计形式化已在台账清理轮落地：`docs/design/ide-git.md` D19 已按用户 2026-10-19 20:33 裁定改写（数字进按钮内、窄宽回落、状态栏不动），§12.6 同步；本档不重复设计段。

**实施读数（父侧复跑，2026-10-19 21:0x）**：`scm_fetch_button_test` + `git_pull_real_test` **20/20 全绿**；`flutter analyze` 两档 No issues；W1–W5 随改（按钮内含 '2'、行内无独立 `↓2`、分支标签无 `↓`、behind 0 无计数、窄宽 `↓2` 仍在分支后）。构建 `bash#75` 含本改动（107.6s，exit 0）。

**已知缺口**：真机观感未单独走查（用户未启动验证）；机检覆盖见上。

**评审后修正笔（advisor code #81，🔴 0 · 🟡 2 · 🔵 2，全部接受）**

| 号 | 落点 | 改动 |
|---|---|---|
| 🟡1 | `ide_scm_view.dart:2289-2295` / `:4231-4246` | 量宽改为带环境 `MediaQuery.textScalerOf(context)` 的 `TextPainter`（原先无视字号缩放，多位数 + 非默认字号会撑出按钮盒）；常量 `_fetchFaceIcon/_fetchFaceGap/_fetchFaceSlack` 提为具名 |
| 🟡2 | `:2326` / `:4164-4165` / `:4246` | 三处旧位置注释（「beside the Get action」）改为「inside / after the name」 |
| 🔵3 | 同上 | 随 🟡1 收（magic number + 「button's own padding」误述） |
| 🔵4 | `scm_fetch_button_test.dart:80-95` + 新 W6 | W1 补「数字矩形落在按钮矩形内」断言；新增 W6（behind 12 两位数同断言） |
| 范围外 1 | `docs/design/ide-git.md:398/509/510/571/573` | §11-2、§12.6-1/-2、§12.8 W1/W3 的旧位置描述收正（父侧直改，机械对齐 D19） |
| 范围外 2 | `docs/requirements/ide-git.md:20/39` | 功能点 8 与 AC 8 改「按钮内」（用户 20:33 改口） |

**读数**：`test/ide/git` **183/183**（原 182 + 新 W6）；`flutter analyze lib/ide/git test/ide/git` No issues。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

**用户批准（2026-10-19 23:44）**：用户逐字「批准」。

批准对象：`↓N` 数字进按钮（宽屏）+ 窄宽回落 + 评审四条与两条范围外文档收正。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**验收读数（父侧复跑）**：`test/ide/git` **183/183**（原 182 + 新 W6）；`flutter analyze lib/ide/git test/ide/git` **No issues**；`scm_fetch_button_test` + `git_pull_real_test` 21/21。

**评审**：advisor code #81 —— 🔴 0 · 🟡 2（optional）· 🔵 2；四条全部 Fixed（量宽带 scaler / 三处旧注释 / 具名常量 / 矩形包含断言 + W6）。范围外两条（设计档 §11-2/§12.6/§12.8 旧位置、需求档功能点 8/AC 8 旧口径）已由父侧机械收正。

**诚实面**：真机观感未单独走查（用户未启动验证）；机检覆盖 = 结构断言 + 矩形包含（含两位数）。
