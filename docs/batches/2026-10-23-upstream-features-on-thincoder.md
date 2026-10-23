# 2026-10-23 · 上游新功能在 thincoder 下的适配
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-23 · 来源 = 用户 2026-10-22 19:37「我们主要用的是thincoder，所以新功能要适配一下」+ 2026-10-23 06:48「上游新功能在thincoder的适配开工」；台账 #146。
> 台账 = #146（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 已定决定（2026-10-23 06:48）

- **已定决定**：上游随 1.6.0 进入、但**依赖内核事件面**的新功能，要在 thincoder 内核下补齐；宿主面功能（文件改动菜单 / `@` 找文件夹 / 排队消息 / 模型复制 / markdown 拖放 / SSH 重连 / Skia / 内存）不属本批 · 用户原话：「上游新功能在thincoder的适配开工」· 时间：2026-10-23 06:48

## 实测边界（2026-10-23 06:50，主 agent 实读）

| 项 | 读数 |
|---|---|
| `SessionRenamed` 的发出点 | **只有** `lib/kernel/claude_code/claude_code_kernel.dart:282`（事件定义在 `lib/kernel/kernel_event.dart:135`，消费在 `lib/chat/chat_session.dart:263` / `lib/kernel/transcript.dart:196`） |
| thincoder 改名路径 | `lib/kernel/thincoder/thincoder_catalog.dart:72` 的 `rename` → `:80` 发 `session/set_title`；**不发 `SessionRenamed`** |
| thincoder 的 slash 命令面 | `lib/kernel/thincoder/**` 无 slash 命令模型（`thincoder_events.dart` 里的 `command` 字段是**终端命令**，不是 `/` 命令） |

## 本批要覆盖的两条

1. **改名同步**：thincoder 改名成功后要让会话列表跟着变（今天只有 Claude 内核会）。做法在设计轮定：发 `SessionRenamed` ∥ 改由 catalog 回调 ∥ 两者。
2. **`/` 命令面**：thincoder 没有命令源。设计轮先判「有没有可映射的东西」，没有就**对 thincoder 隐藏该入口并说明**（不假装有）。

## 判据

| # | 判据 | 读数方式 |
|---|---|---|
| 1 | thincoder 会话改名后，列表与标题立刻是新的 | 走查 + 单测（改名 → 断言列表项标题与会话标题一致） |
| 2 | 改名失败路径不产生假事件 | 单测：`session/set_title` 抛错 ⇒ 不发 `SessionRenamed` |
| 3 | thincoder 会话里看不到 `/` 命令入口（若最终决定隐藏） | 走查 + 单测（命令列表对该内核为空） |

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（设计档 §28 新增，§1–§27 未动）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批覆盖的两条（台账 #146）

| # | 条目 | 需求锚 | 设计落点 |
|---|---|---|---|
| 1 | 改名同步：thincoder 会话改名成功后列表与标题一致；`session/set_title` 失败不发事件 | 需求档 §10 的 2026-10-22 19:37 裁定 | 设计档 §28.3 / §28.4 |
| 2 | `/` 命令面：thincoder 无可映射命令源 ⇒ 隐藏入口 | 同上 | 设计档 §28.5 |

### 设计档落点

新增 `docs/design/thincoder-adapter.md` 的 §28（`## 28. 批 22：改名同步与 / 命令面（台账 #146）`，从第 4064 行起）。既有 §1–§27 一行未动。

### 机制（结论）

- **改名同步**：`ThincoderKernel` 在 `session/set_title` **成功后**发 `SessionRenamed`（`_pumpTitle` 成功分支）；失败分支零事件、只留既有 `error:title` 提示。宿主对「内核会确认的改名」不再乐观改标题，等确认事件回到 `workspace._sync` 再改；catalog 路径（没开的会话）零改动。
- **`/` 命令面**：不实现 `ProvidesCommands`（即现状），`ChatSession.commands` 恒空；不从 Claude Code 的定制文件合成命令表。

### 受影响文件与测试覆盖

见设计档 §28.8：4 个产品文件（`agent_kernel.dart` / `thincoder_kernel.dart` / `chat_session.dart` / `workspace.dart`）+ 1 个测试档；`thincoder_catalog.dart` 与 `kernel_event.dart` 零改动。用例 T131–T134 见 §28.7。

### 验收对照

见设计档 §28.6（两行，均可跑）。口径对 §1「判据」表的 1 / 2 / 3 三条。

### 关键决策

- **发事件的位置选内核**（否掉「宿主」与「两者」）：确认点只有内核知道，发射通道也只有内核有（§28.3 候选表）。
- **失败不发「回滚事件」**：判据 2 的口径是「不发 `SessionRenamed`」，列表保持旧值靠「没确认就不改」，不靠事后改回来（§28.4）。
- **`/` 命令面选隐藏不选对齐**：唯一可对齐的源是 Claude Code 的定制文件，thincoder 既无命令清单也无执行通道，照搬 = 假装有（§28.5）。

### 上抛项

- 需求档没有为这两条分配 F 编号；本批以 §10 的 2026-10-22 19:37 裁定行为需求锚。是否在需求档立条目（如 F25 / F26）归主 agent 决定——需求档是主 agent 的写面，本席只读。

### 修正轮 1（评审 #47 的 6 🟡 + 5 🔵 全部落地）

处置口径：评审 VERDICT 为 pass、无 🔴；主 agent 把 6 🟡 提为必落。本轮只改设计档 §28 与档头，§1–§27 正文未动。

| 评审 # | 处置 | 落点 |
|---|---|---|
| 🟡1 | `renameConfirmed` 判据改为 `_slot != null && _running && !_releaseWanted`（`_closeSession` 只发 `session/close`、`_teardown` 只清 `_connection` 这一事实写进判据表）；§28.4 拆出「槽在连接无」行并在 §28.9 登记；机检 = T137 三态 | 设计档 §28.3 判据表 / §28.4 / §28.9 / §28.7 |
| 🟡2 | 「默认 false」给出机制：新增能力接口 `ConfirmsRename`（只 thincoder 实现）+ `ChatSession` 的 `_ => false` 兜底；写明为何 `implements` 与 `extension` 都给不出该默认 | 设计档 §28.3 |
| 🟡3 | §28.6 改为回指 F25 / F26 验收 ①–③；新增 T135（F25③）/ T136（F26②） | 设计档 §28.6 / §28.7 |
| 🟡4 | `chat_session.dart`（1485）补体量立场：本批 +4，触发 = 下一次向该档追加 >10 行 | 设计档 §28.8 |
| 🟡5 | `renameConfirmed` 补三问答复（`none found` + 检索范围），并写明与 `DefersRename.pendingTitle` 的显示／控制分工（复用、不新造可见面） | 设计档 §28.3 |
| 🟡6 | `{bool confirmed = false}` 给出真实使用点（`if (confirmed)` 分支 + `_sync` 传参）；`ChatSession.rename` 签名不动 | 设计档 §28.3 |
| 🔵7 | `confirmed` 归属统一到 `workspace.rename`；§28.8 #③ 只写 `renameConfirmed` 委托 | 设计档 §28.8 |
| 🔵8 | `test/kernel/thincoder_kernel_test.dart` 现值按实读 4814；U18 闭合 | 设计档 §28.8 / §28.10 |
| 🔵9 | 档头分批清单补批 17 / 18 / 22，状态行日期改 2026-10-23 | 设计档档头 |
| 🔵10 | T133 增 widget 层（`/` 后无 command 类建议），三层断言 | 设计档 §28.6 / §28.7 |
| 🔵11 | F26③ 的将来触发条件登记在 §28.10 | 设计档 §28.10 |

**受影响文件变化**：设计档 §28.8 由 5 行改为 7 行（产品 4 + 测试 3，新增 `test/kernel/rename_confirmed_test.dart` 与 `test/chat/thincoder_commands_test.dart`）；用例表由 T131–T134 扩到 T131–T137。验收对照见设计档 §28.6，用例见 §28.7。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 批 22 设计评审（§28 改名同步 + `/` 命令面；需求 F25/F26）

评审对象：`docs/design/thincoder-adapter.md` §28（4064–4228，10 子节）+ `docs/requirements/thincoder-adapter.md` F25/F26（179 起）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Feasibility | 🟡 | `renameConfirmed => _slot != null` 的判据与实际「会不会被确认」不一致：`_closeSession` 只发 `session/close`、不清 `_slot`（`lib/kernel/thincoder/thincoder_kernel.dart:542-551`），`_teardown` 只把 `_connection` 置空（`:509-510`），而 `release()` 由「视图归零」触发（`lib/chat/chat_session.dart:491`）。于是「槽在、连接没了」这一常态可达：宿主按 §28.3 不乐观改标题，内核走 `_pumpTitle` 的 no-connection 分支（`:1380-1387`）只发「no connection」提示 ⇒ 从侧栏改已释放会话的标题会静默失去改名且列表停在旧值。§28.4 表第 3 行把「`_connection` / `_slot` 为空」并成一条，掩盖了这一格 | 判据改成读活连接（`_slot != null && _connection != null && !_releaseWanted`），或在 §28.4 增一行「槽在连接无 ⇒ 宿主延后、内核报 no connection、列表保持旧值」，并在 §28.9 登记该形状 |
| 2 | Feasibility | 🟡 | `RenamesSession` 增 `renameConfirmed`「默认 `false`」没写机制。Dart 的 `abstract interface class` 上的具体成员不给 `implements` 方任何默认：`ClaudeCodeKernel` 也 `implements RenamesSession`（`lib/kernel/claude_code/claude_code_kernel.dart:109`），按字面实现会在该档编译失败，而该档不在 §28.8 清单内（§28.1 只声明「Claude 路径行为不变」） | 指明机制：`extension ... on RenamesSession { bool get renameConfirmed => false; }`（内核自身成员遮蔽）／或在接口上给具体成员并同步把 `claude_code_kernel.dart` 加进 §28.8 一行 ≈ +2 |
| 3 | Acceptance | 🟡 | 需求 F25 验收 ③（Claude 内核路径行为不变 · 回归）与 F26 验收 ②（Claude 会话里面板行为不变 · 回归）在 §28.6 验收对照与 §28.7 用例表（T131–T134）里都没有落点，只有散文断言；§28.6 也不回指 F25 / F26 编号（本档其余批次节均回指，如 §27.8 / §26.12） | §28.6 增一行「F25③ / F26②：`renameConfirmed` 默认 false ⇒ Claude 仍走 `_retitle`；机检 = 既有 claude 内核测试 + 一条 `commands`/`SessionRenamed` 回归断言」，标题补「（回指 F25 / F26 验收 ①–③）」 |
| 4 | Affected-file annotations | 🟡 | §28.8 的体量立场只点了 `thincoder_kernel.dart`（1436）与 `workspace.dart`（2962），漏了同表 #③ `chat_session.dart`（1485，实测），它同样越过 >800 硬顶且本批 +6。本档自己的先例（§27.9）对每个越顶档都写一句体量立场 | 给 #③ 补同形一句（本批只在 `rename`/`renameConfirmed` 两点加分支、不动结构、拆分批另行立项） |
| 5 | Existing-piece | 🟡 | 新名字 `renameConfirmed` 没有「existing / none found」三问答复（实读 `grep renameConfirmed lib/**` 零命中）；更关键的是同族既有件 `DefersRename.pendingTitle`（`lib/kernel/agent_kernel.dart:340-344`）及其宿主出口 `ChatSession.pendingTitle`（`lib/chat/chat_session.dart:776-779`）、`AgentThread.pendingTitle`（`lib/workspace/workspace.dart:126`，已被侧栏改名框 `lib/sidebar/sidebar.dart:2991` 与 `lib/chat/chat_screen.dart:509` 消费）完全未被考察——它是「写入待确认」现成的可见面，而这正是新流程在回合进行中被压后（`thincoder_kernel.dart:929-937`）时缺的东西 | 补一条既有件答复：`existing: DefersRename.pendingTitle / pendingTitle 三处出口`，并说明本批是否复用它显示待确认标题（复用 ⇒ 少一个 open） |
| 6 | Clarity | 🟡 | §28.3 的落点形状里新增的 `{bool confirmed = false}` 在给出的代码片段中没有出现任何使用点（片段只有 `record != null && byKernel && thread.session.renameConfirmed` 分支）；`confirmed` 如何越过前面 `if (trimmed == thread._title) return true;`（`lib/workspace/workspace.dart:2769`）、`_named`/`_wantsTitle`（`:2770-2772`）与 catalog 分支、以及为什么要 `record != null` 这半个条件，都只在散文里 | 把 `confirmed` 的实际用法写进片段（例如 `if (confirmed || (record != null && byKernel && renameConfirmed) == false)` 的显式形态），并一句话说明 `record == null` 时为何仍乐观更新 |
| 7 | Clarity | 🔵 | §28.8 #③ 写 `chat_session.dart` 改动含「`rename` 的 `confirmed` 参数说明」，但该参数是加在 `workspace.rename`（#④）；两行对参数归属互相矛盾，`ChatSession.rename` 实际是 `void rename(String title)`（`lib/chat/chat_session.dart:1452-1454`） | #③ 改成只写 `renameConfirmed` 委托；参数说明归 #④ |
| 8 | Affected-file annotations | 🔵 | §28.8 #⑤ 的现值 4299（自注「本轮未重读」）与盘上实数不符：`test/kernel/thincoder_kernel_test.dart` 现为 4814 行（U18 已登记该不确定，仍是个陈旧现值） | 实施轮以盘上实数为准即可；若本轮要闭合，重读一次回填 |
| 9 | Doc state | 🔵 | 档头 `docs/design/thincoder-adapter.md:5` 的分批清单止于批 16，状态行 `:7` 仍写 2026-10-21 ⇒ §27（批 18）与 §28（批 22）都不在档头可见 | 档头补批 17 / 18 / 22 三项与状态日期 |
| 10 | Clarity | 🔵 | T133 只断言能力接口与 `ChatSession.commands` 为空；需求 F26 验收 ① 的「`/` 不弹命令面板」落在走查。实读支持再加一层机检：`lib/chat/chat_screen.dart:624-641` 的候选完全由 `_session.commands` 生成，`:651-674` 的说明/命令文件路径对空列表返回 null | T133 增一条 widget 级断言（thincoder 会话 `/` 后无 command 类建议），把验收 ① 变成纯机检 |
| 11 | Requirements | 🔵 | 需求 F26 功能点 ③ 的将来条件（「外仓 ACP 面提供命令清单与执行通道 ⇒ 从隐藏改为对齐」）在本档 §28.9 / §28.10 无登记处 | 在 §28.9 或 §28.10 增一行登记该触发条件（与 U17 同形） |

**已核实的准确项**（抽样）：`agent_kernel.dart` 531 · `thincoder_kernel.dart` 1436 · `chat_session.dart` 1485 · `workspace.dart` 2962 · `thincoder_catalog.dart` 150 与 §28.8 现值逐项相符；`SessionRenamed` 定义 `kernel_event.dart:135-139` ✓、全仓唯一发出点 `claude_code_kernel.dart:1704` ✓；`_pumpTitle` 成功/失败分支 `:1391-1398` / `:1399-1407`（`error:title` 在 `:1402-1403`）✓；`commands` 恒空 `chat_session.dart:659-662` ✓；`ProvidesCommands` 只在 claude（`:99`）与 codex（`codex_kernel.dart:22`）✓；`command` 只作终端命令字段 `thincoder_events.dart:335-337` / `:392` ✓；`customizations.dart:1-2` 与 `customization_store.dart:62-70` 支持「宿主命令书写源 = Claude 定制文件」✓。先例行（对齐 ∥ 偏离 + 理由）与 survey 行（明写未调公开检索）均在位。

计数：🔴 0 · 🟡 6 · 🔵 5。

VERDICT: pass

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
