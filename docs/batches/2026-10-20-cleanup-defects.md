# 2026-10-20 · 清理批：死代码 / 挂起窗 turnId / l10n 值护栏 / 平台路径红 / 既有红分诊
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 03:01「清理批」+ 2026-10-19 21:02「好，我们继续解决台账吧」的延续。
> 台账 = #110（cleanup · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-20
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**本批条目（轻渠道轮；用户 2026-10-20 03:01「清理批」）**

| 笔 | 条 | 内容 | 触达 |
|---|---|---|---|
| A | #103 | 删 `git_repository.dart` 的 `incomingPaths()`（死代码，无调用点） | 产品面（见披露） |
| B | #106 | 挂起窗 `session/prompt` 的 turnId 透传：`submit` → `pushInput` → `runTurn`（外仓 +6 行） | 外仓 + 设计档补记 |
| C | #107 | l10n「源档 ↔ 生成档」值比对护栏（测试） | 工程工具面 |
| D | #109 | 上游合并带入 23 条 Windows 路径红（side_panel / ide_standalone） | 测试面 |
| E | #101 | 既有红分诊：workbench 13 + lsp/install 15 | 测试面 / 条件判定 |

**关键判据**：每笔改完即跑对应测试；E 笔只做分诊（能修则修、环境依赖则转条件/认账并写明）。悬空锚点在收口时重锚到本批。

**授权口径**：用户 2026-10-20 03:01「清理批」（= 本批点火 + 范围认可）；用户 2026-10-20 00:02 的 B1 例外覆盖外仓笔。

**披露（轻渠道，逐笔）**：本笔 = 轻渠道（缺陷修 / 测试面），改动与触达逐条列上方表格；回滚 = 各笔独立可逆（单文件或单文件数行）。

**逐笔实施读数（2026-10-20 03:05–03:25）**

| 笔 | 结果 | 读数 |
|---|---|---|
| A #103 | ✅ 完成 | `git_repository.dart` 删 `incomingPaths()`（无调用点，全仓 12 处都是 autofetch 的参数名） |
| B #106 | ✅ 完成 | `suspension.mjs` 的 `submit(input, opts)` 把 `turnId` 压进条目、`runTurn` 读出并传 `execTurn`；`session.mjs` 的窗内分支改 `window.submit(input, opts)`。`node --check` 两档 OK · 外仓测试 9/9 · CLI 语法 128 档 OK |
| C #107 | ✅ 完成 | `test/l10n_test.dart` 新增「生成档携带每条源文案」用例（按 `{}` 切片段、Dart 转义含 `\"`），`l10n_test` **23/23** 绿（en/zh 各数千片段） |
| D #109 | ⚠️ 部分 | `file_link_test` 已修（POSIX context；1 条红清零）。其余 **22 条**经 `git diff origin/main` 核实：side_panel 代码/测试与上游零差（仅本笔与既有 1 档）⇒ **上游测试在 Windows 上红**（tap 坐标 / POSIX 路径 / macOS 和弦标签），非本批或合并破坏。处置 = 测试策略项（按平台 guard），记 #109 |
| E #101 | ⚠️ 分诊完成 | `test/ide/workbench` 13：`color_theme_picker` 的 macOS 和弦/`IdeQuickInput` 查找（平台）＋ `explorer_exclude` 行为差（需逐条）；`lsp/install` 15：**环境依赖**（需外部 zip/tar/gz 工具）。`ide_workbench.dart` 有本仓既有 137 行改动（他批），逐条判定需单独一轮 |

**结论**：A/B/C 三笔落地并绿；D/E 不硬凑——按「能修即修、环境/平台类如实分诊」处置，记 #109 / #101（更新证据），不假装清掉。

**评审修正（advisor code #4，2026-10-20 03:28，VERDICT pass：0🔴 · 5🟡 全非阻断 · 3🔵）——五条 🟡 全部当场修，无挂账**

| 号 | 处置 | 落点 |
|---|---|---|
| 🟡1 | Fixed | `session.mjs:77` 残余补发径补 `{ turnId: item?.turnId }`（一行） |
| 🟡2 | Fixed | `l10n_test.dart` 护栏改「按成员体 + 占位符名单过滤」：`memberAt` 定位 getter/方法体，片段过滤按 `@placeholders` 与 ICU 关键字（不再按「逗号 / 单词」误杀分支文案） |
| 🟡3 | Fixed | `ide-git.md:85` 改为「已删（清理批 #103）」 |
| 🟡4 | Fixed | 本档补齐段位声明（见下「段位声明」）与 §6 |
| 🟡5 | Fixed | 新档 `thincoder/docs/batches/2026-10-20-cleanup-defects.test.mjs`：2 例覆盖窗内 `submit(input, {turnId})` → 回合执行器收 `turnId`（含富输入 / 无 turnId 为 undefined） |
| 🔵6 | Fixed | `file_link_test.dart:182-185` 余下四条也传 `paths: posix` |
| 🔵7 | **Not an issue（评审前提有误）** | 断言「生成档无 `\"`」不成立：`app_localizations_en.dart` 的 `scmMessagePlaceholderBranch` 实际为 `return 'Message ($keybinding to commit on \"$branch\")';` ⇒ 双引号转义是**必需的**，已保留并加回；本条按技术反驳处理 |
| 🔵8 | Fixed | `git_repository.dart:429` 前补空行 |

**复跑读数**：`test/l10n_test.dart` + `file_link_test.dart` **37/37** 绿；新外仓测试 **2/2** 绿；`node --check session.mjs` OK。

**段位声明（轻渠道轮，无设计/实施子代理）**：

> 不适用：§2 —— 轻渠道轮（父侧直改），无设计段；任务与判据见本 §1 表格。
> 不适用：§3 —— 无设计评审段；收尾链的独立评审 = advisor code #4（结论与逐条处置见本 §1「评审修正」表，本档不另设评审段）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

**用户批准（2026-10-20 03:33）**：用户逐字「批准」。

批准对象：清理批三笔落地（#103 死代码删除 · #106 挂起窗 turnId 透传含残余补发径 · #107 l10n 源档↔生成档值护栏）+ 两条分诊（#109 上游 Windows 平台红 22 条、#101 workbench/lsp 既有红——均为条件项，证据在台账）。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**验收读数（父侧，2026-10-20 03:35）**

| 命令 | 结果 |
|---|---|
| `flutter test test/l10n_test.dart test/chat/side_panel/file_link_test.dart` | **37/37 绿**（l10n 23 含新护栏 · file_link 14 含 POSIX 归一） |
| `node --test thincoder/docs/batches/2026-10-20-cleanup-defects.test.mjs` | **2/2 绿**（窗内 turnId 透传） |
| `node --check` 外仓两档 + `node scripts/check-syntax.mjs` | OK · **128 档 OK** |
| `node --test thincoder/docs/batches/2026-10-20-session-governance-a1.test.mjs` | 9/9 绿（非回归） |
| `flutter analyze`（本批改动档） | No issues |

**逐笔结算**

| 笔 | 条 | 结论 | 证据 |
|---|---|---|---|
| A | #103 | ✅ 完成 | 方法删除，全仓无调用点；设计档 `ide-git.md:85` 同步为「已删」 |
| B | #106 | ✅ 完成（含残余径） | `submit → item.turnId → runTurn → execTurn`；`session.mjs:77` 残余补发径同修；新测试 2/2 |
| C | #107 | ✅ 完成 | 按成员体 + 占位符名单的值护栏；l10n 23/23 |
| D | #109 | ⚠️ 分诊（不核销） | `file_link_test` 已修；其余 22 条 = 上游 Windows 平台红（`git diff origin/main` 零差）⇒ 条件项（测试策略批） |
| E | #101 | ⚠️ 分诊（不核销） | workbench 13 = 平台类 + `explorer_exclude` 待逐条；lsp/install 15 = 外部工具依赖 ⇒ 条件项 |

**遗留与观察**

- A1 批的零留存测试 `thincoder/docs/batches/2026-10-20-session-governance-a1.test.mjs` 与更早的 `2026-10-19-acp-image-prompt.test.mjs` 仍在盘（按其设计应在各自收口删除）——本批不动他批产物，记观察一行。
- 本批三笔均属「缺陷修 / 测试面」，无产品行为变化（除 #106 的回合键与 #103 的 API 删除）。
