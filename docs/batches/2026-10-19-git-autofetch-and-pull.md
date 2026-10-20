# 2026-10-19 · git-autofetch-and-pull
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 02:01「要把autofetch入池子…自动拉代码远端提交的功能，系统代理和功能缺口你要给我做的完好完美稳定」。
> 台账 = #84（ide-git · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**讨论（2026-10-19 02:01）** — 用户逐字：「要把autofetch入池子；并且现在仓库有更新它就不拉了，不显示远端有提交，我需要这个功能，自动拉代码远端提交的功能，系统代理和功能缺口你要给我做的完好完美稳定」。

- 范围：autofetch（周期 + 前台恢复 + 设置项；工作区全仓）+ 安全 auto-pull（干净 / 快进 / 无脏缓冲才拉；否则可见原因）+ 系统代理继承（git 子进程；WinINET；设置可覆盖）+ 多仓工作区 + 错误可见；三个设置项都有 UI。
- 事实（2026-10-19 实读）：`lib/` 无 autofetch（grep 零命中）；fetch / pull 仅手动、`pull` 只作用当前选中仓；`~/.gitconfig` 无 `http.proxy`、git 不读 WinINET（Cursor 走系统代理所以能拉）；`repos` 为 17 仓工作区；本机系统代理 `127.0.0.1:7890`（父侧已配 `git config --global http.proxy` 临时解痛，本需求 = app 自继承）。
- 边界：不自动提交 / 推送 / 解冲突 / 递归 submodule / 改写历史。
- 需求档 = `docs/requirements/ide-git.md`（7 条验收）；台账 #84。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（实施回填 2026-10-19）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

- 需求 `docs/requirements/ide-git.md` §2.1–§2.6 与 §4.1–§4.7 全部覆盖；§3 的边界（不自动提交 / 推送 / 解冲突 / submodule 递归 / force-push 改写 / rebase）不做。
- 设计档：`docs/design/ide-git.md`（新建）。节号：§1 目标与范围 · §2 最近先例 + survey 证据 · §3 接口契约（设置键 / 新增命令 / 代理 / 错误分类 / 状态模型）· §4 机制（触发面 / 单轮 / auto-pull 判定链 / reload / 可见面 / 回收）· §5 受影响文件（含 >800 缝与触发）· §6 关键决策（13 条，含被否）· §7 验收对照（需求 §4 七行）· §8 用例表 · §9 测试策略 · §10 边界 + §10.1 未核实 · §11 UI 决策。
- 台账 #84（归批），需求档 §4 七条为对照面。

### 机制（一句话）

工作台级 `IdeGitAutoFetch`（`lib/ide/git/git_autofetch_engine.dart`，新）：周期 / 前台恢复 / 仓库发现对工作区全仓并发 fetch（4 worker）；每仓按「干净（含未跟踪）→ 可快进 → 远端改动 ∩ 脏缓冲为空」判定，满足则 `fetch` 后 `merge --ff-only <upstream>` 并 `workspace.reload(改动路径)`；网络类失败静默重试，认证 / 冲突 / 缓冲相交按「根 + 问题键」去重通知；`↓N` 上状态栏 branch 项与 CHANGES 仓库头；git 子进程经 `runGit` 注入 `ProxyRoute.environment`（复用 Settings→Network 的 `http.proxyMode` / `http.proxy`，不新增设置项）。

### 关键判据

- 脏缓冲与本次远端改动相交 ⇒ **整仓本轮不拉**，提示相交文件名；保存 / 关闭后下一周期自动拉；其余仓库照常（裁定 A）。
- 网络类失败（DNS / 连接 / 超时 / 代理隧道）**不通知**，tooltip 可见，下周期重试；认证 / 冲突 / 缓冲一次 / 状态变化才通知。
- 分支栏常显：状态栏 branch 项 `main ↓2 · 02:15`；CHANGES 仓库头 `_headLabel` 追加 ` ↓N`（脏树时 Sync 按钮被 Commit 顶掉，必须另设常显面，`ide_scm_view.dart:1889-1901`）。
- 代理优先级：`~/.gitconfig` 的 `http.proxy` > 应用注入的环境变量 > 父环境 > 直连（git `config/http.adoc` 逐字）。
- 超时：`fetch` / `pull` / `push` / `ls-remote` / `clone` / `submodule` 300 秒，其余 60 秒（`gitTimeoutFor`，在 `runGit` 内，本地与远端 host 同享）。
- fetch 失败仍进入 auto-pull 判定（refs 可能已被其它 remote 更新；behind 来自刷新后的 ref），避免一个坏 remote 让该仓永远不拉。

### 受影响文件（当前行数 → 预算）

产品码：`git_autofetch.dart`（新 ~170）· `git_autofetch_engine.dart`（新 ~210）· `git_service.dart`（613 → ~648）· `git_repository.dart`（477 → ~527）· `git_runner.dart`（198 → ~223）· `main.dart`（803 → ~806）· `ide_workbench.dart`（5185 → ~5240）· `ide_scm_view.dart`（4099 → ~4119）· `git_settings.dart`（新 ~110）· `general_page.dart`（867 → ~869）· `app_en.arb`（7035 +~30）· `app_zh.arb`（2706 +~25）· `app_localizations*.dart`（生成，+~210）。
测试：`fake_git.dart`（217 → ~229）· `test/ide/git/git_autofetch_test.dart`（新 ~260，随批删）。
>800 缝与触发（设计 §5.1）：`ide_scm_view.dart` 仓库头 widget → `scm_repository_row.dart`（下次碰或 >4300）；`ide_workbench.dart` 状态栏 → `ide_status_bar_items.dart`（下次碰或 >5400）；`general_page.dart` 本批即用缝（Git 三行抽 `git_settings.dart`）；`main.dart` 启动接线块（下次碰或 >850）；ARB / 生成档不拆。

### 验收对照

需求 §4.1–§4.7 逐条落在设计 §7 的七行表：每行「需求 → 设计落点 → 机检 / 走查判据」。摘要：§4.1 fetch→`↓N`→快进→归零；§4.2 dirty/diverged 不拉但 `↓N` 常显；§4.3 缓冲相交整仓不拉 + 文件名 + 下轮；§4.4 代理经 `gitProcessEnvironmentMap()`；§4.5 全仓遍历 + 单仓隔离；§4.6 network 静默 + 下轮成功；§4.7 三个设置控件 + autofetch 关全停。

### 决策（全表见设计 §6，13 条）

D2 `fetch` + `merge --ff-only`（被否 `git pull` / `pull --ff-only`）· D3 环境变量注入代理（被否 `-c http.proxy`、新增 `git.proxy`）· D6 脏缓冲相交整仓不拉（被否 B「照常快进、跳过重载」）· D7 `↓N` 上状态栏与仓库头（被否只靠 Sync 按钮）· D5 网络静默（被否全通知）· D9 网络命令 300 秒（被否全局 60 秒 / 协议加 timeout）· D12 fetch 失败仍判定 auto-pull（被否中止该仓）· D10 autoPull 从属 autofetch · D8 并发 4 · D13 同进程单飞。

### 未核实与判定条件（设计 §10.1）

U1 Windows Alt-Tab 是否触发 `onResume`（走查；不触发也有周期兜底）。U2 `git fetch --all` 单 remote 失败后是否继续（走查；两种行为下判定都成立）。U3 300 秒是否够最慢仓（首轮实测，不够只改 `gitTimeoutFor`）。

### 上抛项

无待裁。2026-10-19 02:06 需求更新与续接裁定 A 已解决 §2.2 / §2.6 / §4.3 的冲突；代理复用 Settings→Network 已获认可（需求 §2.3）。

### 事实修正（对 spawn 的「未核」项）

- `runGit` 确已传 `environment`（`packages/bao_remote/lib/src/git/git_runner.dart:44`、`:79`）；Dart `Process.run` 的 `includeParentEnvironment` 默认 `true`（官方 API 文档，2026-10-19 读）⇒ 只需注入增量代理变量。
- WinINET 读取已存在：`lib/network/network_proxy_io.dart:236-243`（`reg.exe`）+ `lib/network/proxy_settings.dart:462-513`（`ProxyEnable` / `ProxyServer` / `ProxyOverride`）；设计直接复用，不新写注册表读取。

### 修正轮 1（评审 #2–#11 → 设计档；#1 需求档状态行由主 agent 改）

- #2 路径归一化（设计 §3.1 / §3.3 / §3.6 / §4.3 归一化段 / 用例 B14·B15）：`changedPaths` 返回仓库顶层拼接的绝对路径；求交键 = normalize（Windows 再小写）；`reload` 入参 = 同一绝对路径（已核实 `ide_workspace.dart:776-777` 只 normalize、不 absolute）。
- #3 500–800 档（设计 §5.1）：`git_service.dart`（613 → ~648）与 `git_repository.dart`（477 → ~527）各补缝 + 触发，并写明本批不拆的理由。
- #4 关掉即完全停止（设计 §4.1 / §4.3 步骤 1·8 / §4.6 / §7 §4.7 / 用例 B8）：快进前按仓重读 `git.autofetch` 门；关停后不再开新轮、不再发起 merge。
- #5 代理生效时机（设计 §3.1 / §3.4）：写定为每次 spawn 求值（`NetworkProxy.instance.current` = 最近一次解析），逐条写设置改动 / 系统代理改动的生效路径。
- #6 先例（设计 §2.2）：加「先例来源声明」——本仓无同形设计档章节与 git 面机制先例批次，§2.2 代码坐标为唯一先例来源。
- #7 general_page / ARB（设计 §5.1）：general_page 改记存量债 + 触发；`.arb` / 生成物按本地化资源 / 生成物正面说明。
- #8 下拉坐标（设计 §2.2 / §5 / §11）：补 `SettingsDropdown`（`settings_dropdown.dart:12`）；控件只读复用、不改。
- #9 中间态（设计 §3.5 / §8 B13 / §9）：merge / rebase / cherry-pick 进行中 ⇒ 有改动判 dirty 静默；工作树干净的中间态 ⇒ merge 被拒判 conflict + 一次通知；conflict 样例补本机实测文案（git 2.51.2）。
- #10 远端 host 超时（设计 §9）：补远端 host 侧回归项（`gitTimeoutFor` 命令分类单测 + 交付前走查远端 Fetch / Pull）。
- #11 全局状态清理（设计 §4.6 / §9）：单飞条目完成即移除；测试 `tearDown` 还原环境注入 + 清空单飞表。

设计档行数：369（2026-10-19 实测）。零代码。

设计档最终行数：370（2026-10-19 实测；上一行 369 为归一化段最后一处行宽拆分之前的读数，拆分后 +1）。

### 实施回填（2026-10-19 · fix 轮）

- 设计档 §5：受影响文件表加「实测 / 结论」两列，①–⑮ 逐档回填：300 · 389 · +27（640）· +44（521）· +57（255）· +5（808）· +96（5281）· +19（4118）· 112 · +2（868）· ~69 行 / 19 键（7100）· +19（2725）· +119 / +81 / +75（16425 / 10037 / 9492）· +18（235）· 893；超因按类归并，不逐档展开；⑥⑩⑪⑫⑬ 为共享档，注明当前行数含另一在途批的未提交改动。
- 设计档 §5.1：缝表读数改实施后实测（613 → 640 · 477 → 521 · 4099 → 4118 · 5185 → 5281 · 867 → 868 · 803 → 808）；新增测试档处置行——`test/ide/git/git_autofetch_test.dart`（893）随批删除、不进长期名单（单测零保留），不拆；引入句写明测试档不属源码行数档。
- 设计档 §7：走查列标注「未执行（无 GUI 会话），待收口」；七行判据本身未改。
- 设计档行数：378（2026-10-19 实测，换行数）。零代码改动；需求档未改。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 评审发现（设计档 `docs/design/ide-git.md` ∥ 需求档 `docs/requirements/ide-git.md`）

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Document ownership（doc-state lag） | 🟡 | 需求档状态行仍写「待设计」（`docs/requirements/ide-git.md:4`），而设计档已存在并进入评审（`docs/design/ide-git.md:3` 已把两档并列为需求/设计对），同一状态在两处不一致。 | 把需求档状态行更新为「已设计 / 待评审」，保持状态单一真源。 |
| 2 | Clarity | 🟡 | 新增命令 `diff --name-only -z --no-renames HEAD <upstream>`（`docs/design/ide-git.md:107`）的输出是仓库根相对路径，但同一设计要求 issue 的 `paths`（相交文件，绝对路径）（`docs/design/ide-git.md:150`），并在 `incoming ∩ dirtyPaths` 处与「位于该仓根下的路径」求交（`docs/design/ide-git.md:181`）；`workspace.reload(incoming)`（`docs/design/ide-git.md:182`）的入参形态也未写明。按字面实现会把相对路径与绝对路径求交 ⇒ 交集恒空 ⇒ 需求 §2.2③ 的「脏缓冲相交」安全闸退化为「永远放行」。`IdeWorkspace.reload` 是否要求绝对路径：未核实（不在本次评审范围）。 | 一次性写明路径归一化规则（根路径拼接 + Windows 大小写不敏感比较）并明确 `changedPaths` 返回的形态，让求交与 reload 用同一路径空间。 |
| 3 | Affected-file size annotations | 🟡 | `lib/ide/git/git_repository.dart`（477）本批改动后约 527 行（`docs/design/ide-git.md:218`），在本次改动中跨过 500 行档；`lib/ide/git/git_service.dart`（613）改动后约 648 行（`docs/design/ide-git.md:217`）本已在 >500 档；而 §5.1 的缝表只覆盖「>800 档」（`docs/design/ide-git.md:234`），两文件都没有对应的拆出点与触发条件。 | 为 500–800 档的两个文件各补一行「缝 + 触发」，或并入既有缝表并说明本批为何不拆。 |
| 4 | Requirements coverage | 🟡 | 需求 §4.7 要求「关掉即完全停止」（`docs/requirements/ide-git.md:35`），设计允许进行中的一轮跑完为止（`docs/design/ide-git.md:205`），而该轮在关闭开关后仍可走到 `merge --ff-only`（`docs/design/ide-git.md:182`）并改写工作树。 | 在快进前（按仓而非按轮）重读 autofetch 门，并在 §4.3 / §4.6 写明该语义。 |
| 5 | Clarity | 🟡 | 代理注入点是一个按次求值的闭包 `setGitProcessEnvironment(() => NetworkProxy.instance.current.environment)`（`docs/design/ide-git.md:69`），但生效时机又写「应用启动读一次」（`docs/design/ide-git.md:119`）；按闭包语义，设置改动与系统代理改动的生效时刻与文档所述不同。 | 二选一写定（每次 spawn 求值 / 启动快照），并让 §3.4 的生效时机句与之自洽。 |
| 6 | Closest precedent | 🟡 | `docs/design/ide-git.md:27` 起的 §2.2 给了实现坐标与对齐 / 偏离理由，但没有给出被照抄形态所对应的设计档章节与先例批次坐标（判据的第 2、3 条腿）；本次评审上下文未提供文档地图，无法在别处补齐。 | 补上设计档章节 + 先例批次两条腿，或显式声明 §2.2 的代码坐标是唯一先例来源。 |
| 7 | Affected-file size annotations | 🔵 | `lib/settings/pages/general_page.dart`（867）本批后仍约 869 行（`docs/design/ide-git.md:240`），§5.1 把缝标为「已触发并落地」，但落地内容只是把新增行外移，文件本体仍 >800；`.arb` 两行以「l10n.yaml 生成器契约」为由不拆（`docs/design/ide-git.md:242`），该理由不属于判据认可的任何豁免通道。 | 把 general_page 记为已声明的存量债并给触发条件（而非「已落地」），`.arb` / 生成产物按「非源码文件 / 生成物」正面说明而非当豁免。 |
| 8 | Clarity | 🔵 | 新增设置组承诺「两个开关 + 周期下拉」（`docs/design/ide-git.md:223`），但只给了 `SettingsSwitchRow` 的坐标（`docs/design/ide-git.md:343`），没有下拉行的控件坐标；若仓内无现成下拉设置行，`lib/settings/pages/settings_widgets.dart` 就是 §5 表里缺席的受影响文件。 | 补下拉控件坐标，或把该文件加入 §5 受影响文件清单。 |
| 9 | Acceptance criteria | 🔵 | §8 用例表没有「仓库正处于 merge / rebase / cherry-pick 进行中」一格；判定链（`docs/design/ide-git.md:175`–`:184`）只看 clean / limit / behind / ahead，这类仓会落到 git 自身拒绝 ⇒ 归 `conflict`（`docs/design/ide-git.md:129`）⇒ 发通知。 | 要么加一个显式跳过类型，要么在用例表写明期望分类（conflict + 一次通知）。 |
| 10 | Scope | 🔵 | 超时放宽策略对 `fetch` / `pull` / `push` / `ls-remote` / `clone` / `submodule` 一并生效（`docs/design/ide-git.md:109`），而该 runner 同时服务远端 host；§7 验收里没有远端侧的回归项，影响面是「已声明但未验证」。 | 补一条远端 host 侧的超时回归 / 走查项，或把 300 秒限定在 fetch 类命令。 |
| 11 | Feasibility | 🔵 | 两处进程级全局状态的清理规则未写：环境注入是模块级 setter（`docs/design/ide-git.md:113`），单飞用静态 `Map<root, Future>`（`docs/design/ide-git.md:207`），都没有条目移除 / 测试内还原（finally / tearDown）的约定。 | 写明单飞条目完成即移除、测试内注入还原，避免跨轮 / 跨用例串味。 |

限制说明：本次评审上下文没有 AGENTS.md（Project Guide）、没有项目标准档、没有文档地图 ⇒ 方法论合规与文档归属两项按降级口径评估（只按设计档自身结构与需求档对照判断，未能核对仓内既有设计档是否存在重复 / 冲突描述）。跨文件代码坐标（`git_repository.dart`、`ide_workspace.dart`、`git_runner.dart` 等）按评审范围要求未读取，故**行数抽检未执行**，第 8 条判据只评估了「标注形态与拆出计划是否齐备」；凡引用的非本档代码行为均属未核实。

未发现阻断项：需求 §2.1–§2.6 / §3 / §4.1–§4.7 均有设计落点与机检 / 走查判据；最近先例表与公开资料调查两节均存在；受影响文件表具备当前行数与增量预算；未发现明显范围蔓延（`↓N` 上状态栏与仓库头、通知中心均能回指需求 §2.5 / §4.2）。

VERDICT: pass

counts: 🔴 0 · 🟡 6 · 🔵 5

## §4 用户批准（主 agent）

**用户批准（2026-10-19 02:23）**：逐字「批准」——Git autofetch 设计批准；实现按设计档 §5 的文件面（12 手写码 + l10n 两档与生成档 + 两测试档）。

## §5 实施记录（eng-coder）

**状态行**：实施完成（2026-10-19 · 内部审计 1 轮 + advisor 代码评审 1 轮（pass）· 终态 clean）

### 交付摘要

按设计 §3–§11 落地：工作台级 `IdeGitAutoFetch`（周期 / 前台恢复 / 仓库发现 / 设置变化四个触发面，4 worker 并发，单轮不重叠），每仓 `fetch` → 干净（含未跟踪）∧ `behind>0` ∧ `ahead==0` ∧ 远端改动 ∩ 脏缓冲为空 → `merge --ff-only <upstream>` → `workspace.reload(绝对路径)`；网络类失败静默重试、auth/conflict/buffered 按「根 + 问题键」只通知一次；`↓N` 上状态栏 branch 项与 CHANGES 仓库头，tooltip 带上次成功时间与 issue 原因；git 子进程经 `setGitProcessEnvironment` 按次求值继承 Settings → Network 的代理，网络命令超时 300 秒、其余 60 秒；三个设置项（autofetch / autoPull / period）在 Settings → General → Git。

### 交付面（设计 §5 ①–⑮）

- ① `lib/ide/git/git_autofetch.dart` 新增：设置解析/夹取、`ideGitAutoPullBlocker` + `decideAutoPull`（纯函数）、`ideGitFailureOf`（25 条 stderr 词 → 9 类 kind）、`IdeGitAutoFetchIssue`（key/needsAttention/==）、l10n 文案与时间格式化。
- ② `lib/ide/git/git_autofetch_engine.dart` 新增：`IdeGitAutoFetch`（定时器、resume 5 秒防抖、发现 2 秒补一轮、静态单飞、去重通知、repo 状态写回）。
- ③ `lib/ide/git/git_service.dart`：`fastForward(ref)`（`merge --ff-only`）、`changedPaths(from,to)`（`diff --name-only -z --no-renames`，仓库顶层拼接绝对路径，非仓库返回空表）。
- ④ `lib/ide/git/git_repository.dart`：`lastFetchAt` / `autoFetchIssue` / 可注入 `clock` / `fetch`·`pull`·`sync` 成功记账 / `fastForward()` / `incomingPaths()`。
- ⑤ `packages/bao_remote/lib/src/git/git_runner.dart`：`setGitProcessEnvironment` / `gitProcessEnvironmentMap()`（`Process.run` 与 `Process.start` 都用）、`gitTimeoutFor`（fetch/pull/push/ls-remote/clone/submodule 300 秒，其余 60 秒）。
- ⑥ `lib/main.dart`：`startNetworkProxy` 之后 `setGitProcessEnvironment(() => NetworkProxy.instance.current.environment)`。
- ⑦ `lib/ide/ide_workbench.dart`：引擎创建/销毁/换工作区与换 settings 时重建、resume 触发、状态栏 branch 项 `branch ↓N · HH:mm` + tooltip、`_gitChanged` 比较补 behind/lastFetchAt/issue、auth/conflict/buffered 通知入口。
- ⑧ `lib/ide/git/ide_scm_view.dart`：`_headLabel` 追加 ` ↓N`（在 `*`/`+`/`!` 之前）、仓库头 tooltip = 根 + 上次成功 + issue。
- ⑨ `lib/settings/pages/git_settings.dart` 新增：两个开关 + 周期下拉（1/2/3/5/10/15/30 分钟，默认 3 写 `null` 不落盘），autofetch 关时 autoPull 行灰显。
- ⑩ `lib/settings/pages/general_page.dart`：IDE 分组后插入 `GitSettingsGroup`。
- ⑪⑫ `app_en.arb` / `app_zh.arb`：新增 19 键（分组/两开关+说明/周期/上次成功/6 类失败+3 类跳过/文件名截断）。
- ⑬ `flutter gen-l10n` 重新生成 `app_localizations*.dart`（未手改）。
- ⑭ `test/ide/git/fake_git.dart`：`changedFiles`（`diff --name-only`）与 `merges`（`merge --ff-only`）可编程应答。
- ⑮ `test/ide/git/git_autofetch_test.dart` 新增 45 条：策略（设置/夹取/判定链每格/分类表/文案/时间）、代理注入与超时分类、service（merge argv / B14 绝对路径 / lastFetchAt）、引擎（N1 N2 B2 B3 B4 B5 B8×2 B9 B13 B14 B15 E1 E2 E5 N3 + auth 不被脏树掩盖）。

### 关键实现坐标

- 判定链：`git_autofetch.dart:154-196`（`ideGitAutoPullBlocker` → `decideAutoPull`）；引擎 10 步：`git_autofetch_engine.dart:270-374`。
- 每仓快进前重读开关：`git_autofetch_engine.dart:335`。
- 单飞：`git_autofetch_engine.dart:98`（静态表）+ `:250-263`（键 = `state?.root ?? service.root`，`whenComplete` 移除）。
- 代理注入：`git_runner.dart:26-35`、`:101`、`:147`；接线 `main.dart:166-169`。
- 状态栏：`ide_workbench.dart:4624-4632`（item）、`:4724-4752`（文本/tooltip）；CHANGES 头 `ide_scm_view.dart:2268-2277`、`:2281-2294`。
- 设置：`git_settings.dart:40-97`；插入点 `general_page.dart:511`。

### 验证读数（命令 + 结果）

- `flutter gen-l10n` → 退出码 0（生成 3 档）。
- `flutter analyze --no-pub lib/ide/git lib/settings/pages lib/main.dart lib/ide/ide_workbench.dart test/ide/git packages/bao_remote` → **No issues found**。
- `flutter analyze --no-pub`（全仓）→ 11 条既有 info/warning，**无一条在本波文件**（site_icons / debug_editor_glue / ide_code_find / chat 侧栏测试 / composer_test / ide_units_test / remote_project_test）。
- `flutter test --no-pub test/ide/git` → **+142 -12**；12 条失败与本机 HEAD 基线逐条同名（既有红：git_blame 1、git_service 1（CRLF）、scm_diff 5、scm_multiselect 3、scm_view 1、timeline_view 1）。基线测法：`git worktree add <tmp> HEAD` + 复制 `.dart_tool/package_config.json`、`package_graph.json` 后跑同目录 → **+97 -12**（差 45 = 本波新增档全绿）；worktree 已移除。
- `flutter test --no-pub test/ide/git/git_autofetch_test.dart` → **45 条全绿**。
- `flutter test --no-pub test/ide/git/{git_autofetch,git_operations,git_repository}_test.dart` → **61 条全绿**。
- `flutter test --no-pub test/ide/workbench test/ide/editor_status_test.dart` → **+237 -100**，与 HEAD 基线 **+237 -100** 完全一致（既有环境红，非本波）。

### 预算对照（设计 §5 vs 实测）

| # | 档 | 预算 | 实测 | 结论 |
|---|---|---|---|---|
| ① | git_autofetch.dart（新） | ~170 | 300 | 超 130 |
| ② | git_autofetch_engine.dart（新） | ~210 | 389 | 超 179 |
| ③ | git_service.dart | +35（→~648） | 净 +27（640） | 内 |
| ④ | git_repository.dart | +50（→~527） | 净 +44（521） | 内 |
| ⑤ | git_runner.dart | +25（→~223） | 净 +57（255） | 超 32 |
| ⑥ | main.dart | +3（→~806） | 本波 +5 | 超 2 |
| ⑦ | ide_workbench.dart | +55（→~5240） | 净 +96（5281） | 超 41 |
| ⑧ | ide_scm_view.dart | +20（→~4119） | 净 +19（4118） | 内 |
| ⑨ | git_settings.dart（新） | ~110 | 112 | 内 |
| ⑩ | general_page.dart | +2（→~869） | 本波 +2 | 内 |
| ⑪ | app_en.arb | +~30 | 本波 ~69 行 / 19 键 | 超（键 19 vs ~12） |
| ⑫ | app_zh.arb | +~25 | 本波 +19 | 内 |
| ⑬ | 生成档 ×3 | +90/+60/+60 | +156/+106/+99 | 超（含他批键；未手改） |
| ⑭ | fake_git.dart | +12（→~229） | 净 +18（235） | 超 6 |
| ⑮ | git_autofetch_test.dart（新） | ~260 | 893 | 超 |

超预算原因（不缩水实现，如实记录）：① ② 承担了设计 §3.5 全表（25 条 stderr 词、9 类 kind、每个 kind 的文案与「等」截断）、§4.3 十步链、四类触发与防抖/单飞/去重，预算未计注释与文案组装；⑤ 是超时分类 + 按次求值注入 + 说明注释；⑦ 多出「换工作区/换 settings 重建引擎」与两处 tooltip 组装；⑪ 的 19 键对应设计 §3.5 的 6+3 类与 §11 的设置/通知/tooltip 各自文案，压不到 ~12 键；⑮ 覆盖 §9 清单 + §7 七行 + 审计补的 B14/优先级两格，测试档随批删。

### 偏差与决定（设计未逐字写明的落地规则）

1. issue 合成：fetch 失败与快进跳过同时出现时，**需要用户动作的一类优先**（否则脏树会永久掩盖 auth 失败）；同类时快进侧优先。补单测「a sign-in Git needs is told even when the tree is dirty」。
2. `dirtyPaths` 的过滤基准 = **仓库顶层**（`state.root`），不是工作区文件夹根——设计 §4.3 步骤 6「位于该仓根下」；B14（工作区根是仓库子目录）下上游改上层文件时脏缓冲仍被发现。补引擎用例。
3. 单飞键 = `state?.root ?? service.root`（D13 的「同一仓」语义）；`_run` 的快照去重仍按 `service.root`（§4.2 步骤 1）。
4. 设置变化：只有 autofetch 开关或 period 变化才重排；**开→首轮按 startDelay（3 秒）**，不是等满一个周期；其他设置键变化不推迟下一轮。
5. `changedPaths` 在 `repositoryRoot() == null` 时返回空表（§4.3 步骤 6 字面），不抛。
6. `IdeGitRepository` 增可注入 `clock`（§3.6 的 `clock()`），默认 `DateTime.now`；`_markFetched` 用它。
7. reload 抛错只吞掉并继续（磁盘已更新，不把读取失败升级成 issue）。
8. 非整分钟周期显示最多两位小数（45 秒 → `0.75`），不四舍五入成 `0.8`。
9. 通知与 tooltip 文案：auth/conflict/buffered 带仓库名；buffered 列最多 3 个文件名 + 「等」；stderr 只进 tooltip，不进通知。

### 未做 / 不归本波

- 设计 §10 的边界全部不做（不自动提交/推送/解冲突/递归 submodule/改历史/PAC/凭据/远端 host 代理）。
- 设计 §7 的**走查列**未在本机执行（无 GUI 会话、`flutter pub get` 失败）：系统代理 127.0.0.1:7890 实连、多仓一仓断 remote、断网一周期、17 仓实测、U1–U3——留给父代理收口。
- 设计 §5 的「实施后回填实测」与需求档状态行：属设计者/主 agent 文面，本波不改。回填待办：`docs/design/ide-git.md` §5 表用上表实测值；`docs/requirements/ide-git.md:4` 状态行仍写「设计中（…修正轮 1 进行中）」；批次档 §6 走查记录。
- 设计 §4.3 步骤 10 的竞态缓冲沿用 `buffered` 文案（「未自动拉取」），此时磁盘其实已更新——按设计 §3.6 的 kind 集合与 §4.3 步骤 10 的口径保留，未新增 kind；父层若要区分文案需改设计。

### 文件面与工作区状态

- 本波改动 = 设计 §5 ①–⑮ 全部 + 本批次档 §5；**无源码档超出清单**。共享档（`main.dart` / `general_page.dart` / 两 `.arb` / 生成档）在本波之前已带另一在途批（编辑器上下文/thincoder）的未提交改动，故 `git status` 不满足「只含本波文件」——本波未触碰、未回退他批内容；本波在这些档里的净增见预算表。
- 过程中在仓内建过两件临时物，均已清理：`test/ide/git/tmp_timer_probe_test.dart`（验证 dispose 取消的 Timer 不触发 pending-timer 断言，跑完即删）、`D:\baocode-head` HEAD worktree（基线对照，已 `worktree remove`）。

### 内部审计与代码评审（轮次 + 终态）

- **explore 差异审计**：1 轮。8 项发现：should-fix 2（换工作区不重建引擎、脏缓冲按工作区根过滤）、defect 1（auth 被脏树跳过掩盖）、预算/文档 3、测试缺口 2。已修 3 项 + 补 3 条单测；预算/文档类转入本段；定时器面单测与 buffered 文案按设计口径保留。
- **advisor 代码评审（type=code）**：1 轮，**VERDICT pass**（🟡×3 + 🔵×4 + 协调项×1，无阻断）。已采纳 4 项（设置重排/开即首轮、单飞键、`clock()` 注入、非整分钟显示）；保留 3 项（buffered 竞态文案属设计口径、定时器面单测不在 §9 必测清单、设计 §5 回填属设计者）。
- **终态：clean**。

## §6 验证与收口（父代理）

**验收读数（父侧复跑）**：交付时 `flutter test --no-pub` 三档（新档 + operations + repository）⇒ **61/61 全绿**（新档 45 条）；`test/ide/git` +142 −12（12 条 HEAD 基线红同名同数，台账 #90）；`flutter analyze` 改动面 0 条新增；`flutter gen-l10n` 退出 0。

**机制面**：autofetch 周期 / resume 触发 / 17 仓覆盖；安全 auto-pull（A 口径：脏树整仓不拉、仅可快进、`↓N` 常显）；系统代理自动继承（`gitProcessEnvironmentMap` 每次 spawn 求值，`off` 清空）；超时按命令名（网络命令 300 秒）；三设置项有 UI 且关掉即停。

**收口期发现的缺陷（跨批闭合）**：真机走查暴露「自动轮 fetch 到了却不快进」（台账 #92）——根因在判定读缓存 `state` 的静默出口。该缺陷由**批 13**（`docs/batches/2026-10-19-git-fetch-ux.md`）修复并以 T1 真 git 夹具 / T9 / T10 机检；本批的自动拉取验收自批 13 起**转入批 13 的 §6 记录**，不再双记。

**未闭合（诚实面）**：本批 §7 的四条真机走查（3 分钟自动拉 / 脏树只显示 / 断网静默 / 代理无手配）中，代理与断网两条无真机读数；用户 2026-10-19 20:20「不验了」跳过走查。机检覆盖见本批 §5 与批 13 §6。

**台账**：#84（autofetch + auto-pull + 代理）追认核销；#90（12 条基线红）保留。

**状态**：已收口 2026-10-19。
