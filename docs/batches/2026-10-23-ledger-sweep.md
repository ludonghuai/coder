# 2026-10-23 · 台账清理与可开工项
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-23 · 来源 = 用户 2026-10-23 06:53「能开工的都开工，我们要开始清理所有的台账了」。
> 台账 = #160（core · 条件）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 分层（2026-10-23 06:55，用户「能开工的都开工，我们要开始清理所有的台账了」）

**本笔 = 轻通道轮**（缺陷修 + 文档一致性），逐笔披露、逐笔落 §1；结构类与需求类不在轻通道内。

| 层 | 判据 | 条目 |
|---|---|---|
| **A 立刻能修（轻通道）** | 有明确根因 + 单点改法 + 可复现读数 | #133 Stash 排序无 id 兜底 · #138 设置文案仍指 baocode.dev · #131 SCM 图 build 期通知 · #129 analyze 存量 8 条 |
| **B 等在飞** | 已过评审或评审在跑 | #155（F11 评审 #46）· #146（#47）· #153/#150（本批后拆） |
| **C 需诊断** | 根因未定，先要读数 | #158（6 条 macOS 设置测试）· #159/#144（拖选探针）· #151（Gitee 四方法需真机对拍） |
| **D 要你裁** | 需求池/结构/取舍 | #2 远程 SSH · #3 Customize 对接 · #36 会话级跨端 · #18 手机远程 · #150/#153 拆分 · #159 是否开诊断轮 |
| **E 条件未触发** | 有触发条件，今天不动 | 其余 ~35 条（thincoder 竞态/能力协商/进程收尾/IDE 结构债…） |

**本轮先做 A 层四条**，然后按 B→C 推进；D 层等你逐条拍。

## 已定决定：待确认项改为「发现即派」（2026-10-23 07:05）

- **已定决定**：F8 的研判从「run 结束后统一派子代理」改为「**run 中每发现一条待确认差异就立刻派只读子代理**」，结论当场写进该行的「建议」列 · 用户原话：「待确认差异在主agent那里只会在结束的时候调用子agent，我希望主agent发现一个立马丢给子agent」· 时间：2026-10-23 07:05

**与 F10 同机制**（断点查明已在 run 中立刻派），差别只在触发点（断点 vs 待确认项）与上限。

**待落盘位置**（btest 批档与设计档现在 #46 评审冻结，解冻后落）：
1. 需求档 `docs/requirements/browser-biz-test.md` 的 F8：把「交付前由子代理逐条给」改成「发现即派」；
2. 设计档 §3.10 与卡片 `[D8]`／报告格式说明：去掉「run 之后回填」，改为「run 中即时回填」；
3. 上限：**一次 run 最多 5 次**（待确认项比断点频繁；超限后剩余条目写 `待研判 · 达到本轮上限`）；
4. 判定列仍不动（子代理只给建议）。

**回滚**：无代码改动前，本条只改文档。

## 笔 A：SCM 面板窄宽度溢出（用户截图 07:03）

**披露（轻通道 · 缺陷修）**：本笔 = 轻通道（缺陷修 · 用户当场点名）| 改动：`lib/ide/git/ide_scm_view.dart` 三处行内缩进按可用宽度收敛 + 提交按钮标签自适应 | 触达：该档 + 一条新用例 | 回退 = revert 单提交。

**症状（用户原话 + 读数）**：截图右侧黄黑斜纹，`A RenderFlex overflowed by 2.0 pixels on the right`。旧构建日志同一症状重复 20+ 次，另有 `22 / 3.8` 像素若干。

**根因（实测）**：行内缩进（`indent + 8 + (depth-1)*8` 或 `+22`）是**固定 Padding**，而一行的固定件（twistie 22 + 图标 16 + 间隙 6 + 状态字母 19 + 右内边 12 = 75）不可压缩；窄面板下 `left` 吃掉全部宽度 ⇒ 行 Row 必然溢出。

**改法**：新增 `_rowInset(room, wanted)`，把左内边裁到 `room - 80`（保留 80 给固定件与名字）；三处行构建（资源行 / 文件夹行 / 分组行）改用之；`_SplitButton` 标签行外包 `FittedBox(scaleDown)`，极窄时整体等比缩小而不报错。

**验证（实测）**：
- 新增用例 `test/ide/git/scm_view_test.dart` 的 `narrow` 组（420px 窗口 + 悬停行）：**通过**，且日志中 `ide_scm_view.dart` 的溢出行 **0 条**（改前同条件 4 处：2438 / 1664 / 2737 / 3653）。
- `flutter test --no-pub test/ide/git`：**184 条全绿**；`dart analyze` 该档 **No issues found!**

**未覆盖（诚实说明）**：240px 窗口（侧栏约 60px）下文件夹行仍会溢出——那不是可排版的宽度；本轮不追。

## 笔 B：编辑器标签栏右侧动作区溢出（用户截图 07:40）

**披露（轻通道 · 缺陷修）**：本笔 = 轻通道（缺陷修 · 用户截图点名）| 改动：`lib/ide/ide_tab_bar.dart` + `lib/ide/ide_agent_edits.dart` | 触达：两个档 | 回退 = revert 单提交。

**症状**：Markdown 预览标签栏右端（「撤销当前 / 保留当前」+ Markdown 切换 + 更多）在窄编辑器面板下出现黄黑条纹并截断文字。

**根因（实测）**：标签栏 `Row` 的结构是 `Expanded(标签条)` + 一串**固定宽度**尾部（动作区、MarkdownSwitch 两段文字、更多按钮）；面板一窄，`Expanded` 先被压到 0，尾部仍有最小宽度 ⇒ 行按差额溢出。`IdeAgentEditActions` 的两个按钮是**带文字的药丸**，是最宽的一段。

**改法**：
- `lib/ide/ide_agent_edits.dart`：`IdeAgentEditActions` 增 `compact`；`_TitleAction` 增 `icon` + `compact`（紧凑时只画图标，tooltip 保留原文）。
- `lib/ide/ide_tab_bar.dart`：标签栏 `Row` 包进 `LayoutBuilder`，`tight = maxWidth < 620`；动作区改 `if (widget.actions case final actions?) Flexible(child: actions)`（给有界宽度）；`MarkdownSwitch` 增 `compact`（紧凑时只画一个「切换到的那个」按钮）。

**验证（实测）**：
- `dart analyze lib/ide/ide_tab_bar.dart lib/ide/ide_agent_edits.dart` ⇒ **No issues found!**
- `flutter test --no-pub test/ide/workbench/global_keys_test.dart` ⇒ **113 全绿**（标签栏键盘面未被破坏）
- `flutter test --no-pub test/ide` ⇒ 3755 过 / **53 红**；逐条核对红因：`ide_workspace_model_test.dart` 单跑 `Expected '\\virtual-project\\first.txt'` / `Actual 'D:\\virtual-project\\first.txt'` ⇒ **已知 Windows 路径夹具族（#130）**，与本笔无关（本笔只碰标签栏与动作区两个档）
- 重建后（pit 待填）用户复看条纹

**未覆盖**：本笔没有新增窄宽度 widget 用例（标签栏需要整套 workbench 夹具，成本高于本笔改动）；如需回归，建议在结构批给 workbench 补一条窄宽度用例。

**笔 B 复看（用户 2026-10-23 07:44）**：新构建 pid 8960，`overflow=0`；用户未再报条纹（同一时段确认 F11 持久化正常：「再打开确实是保留了 btest；没问题」）。笔 B 视为验证通过，未新增窄宽度用例的缺口保留在本段「未覆盖」。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 覆盖条目

| # | 条目 | 设计落点 |
|---|---|---|
| 1 | 台账 #163：btest 设计档里 SPLIT-1 / SPLIT-4 两条旧缝登记改指结构拆分设计 | `docs/design/browser-biz-test.md` §4「超 800 行档：本轮先拆后加」表的 composer 行（SPLIT-1）与 chat_models 行（SPLIT-4） |

**不在本批**：`docs/design/structure-splits.md`（权威源，只引用不改）· btest 档的判据 / 计数 / 验收 / 节结构 · 其余任何档。

### 设计（纯指针修正）

权威源 = `docs/design/structure-splits.md` §4.3（composer 的六段切法，取代旧缝「内核模式选择区整段抽 `composer/mode_selector.dart`」）与 §4.5（chat_models 抽 `EditorContext` / `TextContext`，取代旧缝 `chat/btest_models.dart`——该缝前提不成立，本档没有任何 btest 类型）。

改法：「余下抽取缝」两格改为指向上述两节；「登记」列各写一句旧缝已被取代及理由。旧缝名只保留在这句说明里，不再以活登记形式出现——读者记得旧名时仍有一条改指路径，删掉旧名则它变成档内无法解析的悬空指针。

### 验收对照

| # | 判据 | 读数 |
|---|---|---|
| ① | 两处登记行指向 §4.3 / §4.5，各带一句「旧缝已被取代，理由见该节」 | `docs/design/browser-biz-test.md:643` · `:646` |
| ② | 全档检索旧缝名，只出现在「已取代」句里 | `grep "mode_selector\|btest_models"` ⇒ 2 行命中，均在 `:643` / `:646` 的已取代说明内 |
| ③ | 判据 / 计数 / 节结构未动 | `git diff` 只 2 行替换、无增删行、无新增标题 |
| ④ | `doc_check(mode:"gate", docs:["docs/design/browser-biz-test.md"])` 首行 PASS | `DOC-CHECK GATE: PASS`（0 条命中） |
| ⑤ | 只改这一档 | 改动档只有 `docs/design/browser-biz-test.md` |

### 发现（不在本笔边界内，交父侧裁定）

§4 表「现行」列的行数读数已旧于当前树。实测：2026-10-23 本笔，按换行符计行、末行计入。

| 档 | 档内登记（§4） | 当前实测 |
|---|---|---|
| `chat_models.dart` | 839 | 732（⇒ §4.5 已落地，`lib/chat/editor_context.dart` 在盘） |
| `composer.dart` | 2466 | 2346（第 5 步未开，仍 >800） |
| `thincoder_kernel.dart` | 1435 | 480 |
| `chat_session.dart` | 1492 | 793 |
| `btest_mode.dart` | 1131 | 556 |

本笔按边界不改计数；是否刷新、或把该列标注为 as-of 读数，由父侧决定。

## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
