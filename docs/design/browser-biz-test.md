# 浏览器业务测试模式（browser-biz-test）设计档

> 板块：浏览器业务测试（宿主 overlay + 测试状态 + 预期文件）· 范围仓：baocode。
> 需求：`docs/requirements/browser-biz-test.md`（F1–F6 · F2.1 · F3.1 · F3.2 · §4 边界 · §5 验收）。
> 结构：本档覆盖设计档 8 项（做法与理由 / 接口契约 / 受影响文件 / 关键决策 / 验收回指 / 用例表 / 边界 / UI 决定），并含最近先例行与 survey 证据行。

## 1. 目标与范围

一句话：让 BaoCode 在 Chrome 上把一条航运业务线跑完整，判断依据（预期结果、case 来源）来自盘上的文件而不是模型记忆，一轮结束给一份可复验的问题清单。

范围内的八件事：

| 编号 | 内容 | 落点 |
|---|---|---|
| F1 | 第三种模式 `btest`，像 plan 一样可切、可退 | §3.1 · §3.2 |
| F2 | 随模式注入一次的模式卡（纪律 / 判定口径 / 报告格式 / 禁止项） | §3.2 · §3.8 |
| F2.1 | 操作方式 = 模拟真人：入口一次导航、文字定位、逐字键入、evaluate 不写值 | §3.6 · §3.8 |
| F3 | 预期结果落盘独立 QA 仓（`<qaRoot>/<仓名>/<业务线>.md`，§3.4），AI 写、人可编辑 | §3.3 · §3.4 |
| F3.1 | 预期必须带出处 `expectFrom`：强 / 中 / 弱三级，代码现状不得作预期 | §3.4 · §3.8 |
| F4 | case 标 `source: new \| old` 与出处，差异按四步处置 | §3.5 |
| F5 | 只读轮（导航 + 快照 + 读接口） | §3.6 |
| F6 | 一轮跑完的报告表格 + 三类尾注，不截图、不边走边停 | §3.8 |

范围外：见 §8。

## 2. 做法与理由

### 2.1 机制总览（五件事，缺一件就退化）

1. **模式是宿主 overlay**：`btest` 是会话级的一个开关，显示在内核模式旁边，但不发给内核（内核只认 `plan` / `normal`）。
2. **一轮测试是一个有头有尾的 run**：`btest_run_start` 开、`btest_run_end` 收；没有 run 的浏览器动作一律拒绝——这是"忘没忘纪律"的机械判据，不靠模型自觉。
3. **判断依据落盘**：预期文件（独立 QA 仓，路径见 §3.4）在 run 开始时由 `btest_run_start` 读出（索引 + hash + 绝对路径）、在 `btest_run_end` 之前写回；写失败进报告尾注，不静默。
4. **放行有边界**：域名白名单 + 生产禁写 + 只读轮动作面，三条都在宿主侧判；拒绝必须带原因（哪条规则、哪个 host、哪个动作）。
5. **操作路径是真的**：一轮只从 `startUrl` 进一次，之后靠点与打；按看得见的文字定位；写值只经真人与表单。路径用户走不到，测出来的结论就不成立——所以这一条与上面四条同级，落在工具面判据（§3.6）与报告读数（§3.8）上，不只在提示词里。

**注入通道的选择**（模式卡怎么到模型）：走 `KernelTurn.contexts` → `editorNote`，与用户消息拼成同一段 `text`（`lib/kernel/thincoder/thincoder_kernel.dart:674-678`），并随 `UserMessageItem.contexts` 进 transcript（`lib/kernel/thincoder/thincoder_kernel.dart:684-688`）。

为什么不选另外两条现成通道：

- **MCP `instructions`**：`HostTools.instruct` 把文本并进 MCP `initialize` 的 `instructions`（`lib/host_tools/host_tools.dart:134-138`、`:174-181`）。它只在 initialize 读一次、且按 feature 全局共享——无法"按会话、按切模式的那一刻"注入，也无法在切回 normal 时撤回。它只适合常驻规则（如现有浏览器爬取禁令 `lib/browser/browser_tools.dart:183-184`），不适合模式卡。
- **Claude Code 的 append-system-prompt**：Claude 侧有（`lib/kernel/claude_code/claude_code_transport.dart:285-287`），thincoder 侧没有；要加就得改外仓 `thincoder/`（本批已定不做）。

### 2.2 最近先例（对齐 ∥ 偏离及理由）

先例三坐标：

- 实现坐标：模式选项源 `lib/kernel/thincoder/thincoder_choices.dart:7-11`；composer 选项渲染 `lib/chat/composer/composer.dart:1921-2007`；浏览器设置段 `lib/settings/pages/browser_page.dart`；宿主工具注册与分组 `lib/browser/browser_tools.dart:92-134`。
- 对应设计档章节：`docs/design/thincoder-adapter.md` 的 mode / configOptions 章节（模式选项与 `session/set_mode`）；`docs/design/host-tool-channel.md` 的 §4.5（审批语义）与 §4.7（宿主注册面）。
- 先例批次：`docs/batches/2026-10-20-thincoder-mentions-and-mode-notice.md`（模式选项与提示注入同形）；`docs/batches/2026-10-18-host-tool-channel.md`（宿主工具组）。

**对齐**：模式选择沿用同一套 `KernelChoice`（同一个选择器控件、同一种可切可退的形态）；`btest` 的宿主工具沿用 `HostTool` + `group` 注册（`lib/browser/browser_tools.dart:110-112`）。

**偏离**（三处，均带理由）：

1. **`btest` 不进内核 mode 列表**，而是宿主在同一个选择器里追加一个宿主项。理由：内核只接受 `plan` / `normal`（`lib/kernel/thincoder/thincoder_kernel.dart:463-467` 的 `_applyStartMode`），第三个值要么被内核丢掉、要么得改外仓；改外仓还会动 ACP `mode` 的语义。
2. **注入走 turn contexts 不走 MCP instructions**。理由：instructions 是 initialize 时一次性、全局的（见 §2.1），做不到"按会话切模式注入一次"。
3. **已投递的模式卡不删除**（transcript 是历史事实，删卡等于改历史，且会话恢复会重放）。改为退出后的下一个回合投出一行中和语使其失效；重进按计数差判——中和行已投出 ⇒ 重投一张新卡，中和行随重进丢弃 ⇒ 不重投（KD-18）。验收判据仍是「切回 normal 后不残留」（§3.1 · §6 F1），替代判据的等价理由见 KD-10。

### 2.3 公开资料调查（survey-evidence）

- 本仓：`docs/design/`（含 chat-streaming / distribution / forge-accounts / host-tool-channel / ide-git / session-governance / thincoder-adapter）、`docs/requirements/`、`lib/browser/**`、`lib/kernel/thincoder/**` 已读；无既有"浏览器业务测试模式"章节，本档是板块首篇。
- 项目清单 `PROJECT-MANIFEST.json` 的 `index.publicRepos` 为空 ⇒ 无声明外源可查。
- 业务仓侧（不在本仓文档域内）：`v2-booking` 的设计档带编号小节（形如 `## N.M <标题>`），`docs/audits/` 下有现成冒烟清单（51 KB）。两处由主 agent 实读（2026-10-22），设计位未再读；引用形实例见 §3.4。
- 用户家目录草稿 `~/.thincoder/skills/browser-biz-test/SKILL.md`（76 行）只作提示词输入参考，不是本仓的规范面。
- 外网公开资料：本轮未取用——机制全部落在本仓既有通道（turn contexts / HostTool / KernelChoice / 文件工具）上，没有新协议或新 API 需要外部核对。

## 3. 接口契约

### 3.1 模式状态（宿主侧）

| 项 | 决定 |
|---|---|
| 存储 | 会话设置 map 的 `btest` 键，值 `on` / `off`；与 `KernelChoiceKind.mode.name` 并列存放 |
| 不发内核 | `_applyStartMode` 只认 `plan` / `normal`（`lib/kernel/thincoder/thincoder_kernel.dart:463-467`），多余键不会被误发 |
| 显示 | composer 的 kernel 选项区（`lib/chat/composer/composer.dart:1921-2007`）追加一项 `btest`，与 plan 同形 |
| 退出 | 选中 normal / plan 即关闭；已投递的模式卡留在 transcript，`D = 1` 时由**下一个回合**投出一行中和语 `[btest-mode-card-off v1]` 使卡失效；**再次切进时按 §3.2 的重进判据**（中和行已投出 ⇒ 重投一张卡；中和行未及投出 ⇒ 随重进丢弃、不重投；卡不删除，中和行只标记失效） |

### 3.2 模式卡：注入的确切时机与唯一性判据

- **时机**：切进 `btest` 之后的**第一条用户消息**。原因是宿主只能把上下文挂在回合上——切模式那一瞬间没有投递点；若切换时正有一轮在跑，顺延到下一回合。
- **注入与重投（唯一性判据）**：卡文本首行带固定标记 `[btest-mode-card v1]`，**标记在卡内只出现一次**（正文不复述标记，否则计数失真）；投递前算**计数差** `D = count("btest-mode-card v1") − count("btest-mode-card-off v1")`。宿主侧 `btest == on` ∧ `D = 0` ⇒ 投一张卡（`D` 变为 1）；`D ≥ 1` ⇒ 跳过。
- **中和行：不存“挂起”位，投递条件在回合装配时现算**：中和行的投递条件 = **装配那一刻宿主 `off` ∧ `D ≥ 1`**（健康态即 `D = 1`），一次投一行（同一通道，挂 turn contexts）；`D = 0`（卡还没投过）⇒ 不投，避免出现“没有卡的中和”。
  退出只翻宿主状态，不排队、不记账——会话重启丢了内存里的挂起标志也不丢件，下一次装配照样按当前状态补上。
- **重进时挂起中和行的归属（写死：丢弃）**：退出后没经过任何回合就重进 ⇒ 下一回合装配时宿主已是 `on`，投递条件不成立 ⇒ **中和行丢弃、永不补投**，卡不重投、`D` 保持 1。
  理由：中和行的含义是“模式已关”；宿主已重新打开还把它投出去，模型侧被口头告知已退出、宿主侧却按 btest 判据放行 / 拒绝——正是本条要消灭的不一致。丢弃的代价为零：卡仍在 transcript，模型侧从未被告知退出。被否方案见 KD-18。
- **两种投递按宿主状态互斥**：宿主 `on` ⇒ 只可能投卡（`D = 0` 时）；宿主 `off` ⇒ 只可能投中和行（`D ≥ 1` 时）。同一回合里不会出现“先中和、再投卡”的顺序问题。
- **三种进入同一条判据 + 重进的两种时序**：首次进入、退出后再进入、会话恢复，都按 `D` 判——`D = 0` 就投、`D ≥ 1` 就跳过。重进分两种时序，读数各只有一个：
  - **退出与重进之间有过回合**：该回合把中和行投出（`D = 0`）⇒ 重进后的下一回合按 `D = 0` 重投卡，`D` 回到 1；
  - **退出与重进之间没有回合**：中和行随重进丢弃 ⇒ `D` 保持 1 ⇒ **不重投**（卡从未失效，重投只会让 `D = 2`）。
  两种时序收敛到同一句读数：**回合装配完成时，宿主 `on` ⇔ `D = 1`、宿主 `off` ⇔ `D = 0`**（KD-18）。
- **判定的时刻**：以上对账都发生在**回合的上下文装配时**，以那一刻的宿主状态为准；切换发生在回合进行中 ⇒ 本回合按装配时的状态跑完，下一回合生效。两次回合之间宿主可以先关再开，那个窗口里模型不做决策，下一次装配必然把它对齐。
- **中和行与状态读数（退出判据）**：两个标记互不包含 ⇒ 读数干净：**`D ≥ 1` ⇒ 模型侧在模式内；`D = 0` ⇒ 模型侧已退出**；健康态只有 0 / 1 两个读数（≥ 2 = 重复投卡，读数当场点出来），任意次开→关→再开之后仍成立。
- **长会话漂移兜底（判据，不靠记忆）**：没有活动 run 的浏览器动作一律拒绝（§3.3）；`btest_run_start` 的返回尾部带一行"先读返回项 2 的绝对路径，再开始"。这一行是**每次 run 一行**，不是模式卡重复；若用户要求连这一行也不要，见 §10 上抛项 1。
- **卡的内容边界**：角色、七条稳定性纪律（`[D1]`–`[D7]`；`[D7]` = 操作真实：入口一次、文字定位、逐字键入、读不推进流程）、七条判定口径（`[J1]`–`[J7]`）、需求 §7 的 19 类问题域各一条检查动作（`[P01]`–`[P19]`）、三条硬纪律（`[H1]`–`[H3]`）、差异处置四步、报告格式、禁止项、跑前必读。约 1.5k 字符；正文落 `lib/browser/btest/btest_card.dart`（版本化、可 diff），不写进用户家目录。标签是 F2 第二条判据的机械锚点（§6）。
- **漂移的第二个兜底**：`btest_run_end` 的返回带收尾检查表（四项机械读数：写回 hash、三尾注字段存在性、覆盖对账、操作真实性读数，§3.3），缺项直接点名字段——把"忘了"变成一次显式点名。

### 3.3 一轮测试的边界：run

`btest_run_start`（宿主工具，仅 btest 开启时注册）：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `line` | string | 是 | 业务线名，如「订舱」；预期文件名就是它（`<业务线>.md`） |
| `repoRoot` | string | 是 | **业务仓根绝对路径**（如 `D:\repos\v2-booking`）；宿主校验目录存在且含 `.git`，否则字段级拒绝。本 run 只从它跑 `git log`（判 `source`）并派生 `qaRoot`（§3.4）——**业务仓零写入** |
| `startUrl` | string | 是 | **本轮唯一入口 URL**（绝对 http(s)）；首次入口动作必须等它（去尾斜杠比较），不等即拒（§3.6.2） |
| `env` | enum | 是 | `dev` / `test` / `prod`；**写动作的总闸**（§3.7 规则 A / B） |
| `mode` | enum | 是 | `readonly` / `write`；`env: prod` + `mode: write` ⇒ 起 run 即拒 |
| `commitRange` | string | 是 | 本轮变更范围（`git -C <repoRoot> log --oneline -30` 的区间/摘要） |

`repo`（业务仓名）不再作为入参：显示名由 `repoRoot` 的末段派生（`v2-booking`），避开"一个仓名两处来源"。

`expectFile` 也不作入参：它要表达的只是业务线名（= `line`），预期文件的文件名与路径全由宿主按 §3.4 派生；`expectFile` 只作为这个文件在宿主内部的叫法保留（检查表的 `expectFile: written` 即此）。落点因此不依赖调用方每次传对相对路径。

`startUrl` 是入口 URL 的唯一权威；预期文件头的「起点」是它的记录副本，写回时以 `startUrl` 为准（不一致改文件，不改判据）。

返回（**五处，缺一即实现不全**）：

1. `runId`；
2. **预期文件的绝对路径**（解析后）：`<qaRoot>/<仓名>/<业务线>.md`；用户据此当场核对落点，不对就配 `btest.qaRoot` 覆盖后重跑（§3.4）；
3. **case 索引**：本次预期文件里全部 `## CASE-` 的 ID 与标题（read 结果随回合进上下文——"跑前必读"从此有机械判据，不靠模型自觉）；
4. **内容 hash**：预期文件此刻的 SHA-256（文件不存在 ⇒ `absent`），**同时作为写回基线**（§3.4）；
5. 一行纪律（读文件 / 不边走边停 / 三尾注）。

首次 run 若 `git init` 失败，返回里多一行 `未初始化 git，写入仍可，历史不可追`——不阻断 run（§3.4）。

`btest_run_end` 接收**结构化载荷**（不是一段自然语言摘要，字段存在性由宿主判）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `runId` | string | 本 run |
| `coveredCases` | string[] | 本轮实际覆盖的 case ID（与 run_start 索引对账） |
| `issues` | object[] | 每条：`caseId` / `step` / `symptom` / `evidence{kind,readout}` / `severity` / `pre` / `expectRef` / `detour`（可空；绕道而来的问题行必填，值 = §3.6.2 的 `detour` 原文） |
| `blockers` | object[] | 每条：`step` / `reason`（被 btest 拒绝的动作与规则原文进 `reason`） |
| `unconfirmedDiffs` | object[] | 每条：`caseId` / `runs`（≥ 2 次的步骤与状态） |
| `uncovered` | object[] | 每条：`branch` / `why` |

返回收尾检查表（**四项，全是机械读数**，不看模型措辞）：

1. **预期文件写回**：`expectFile` 当前 hash ≠ run_start 基线 ⇒ `written`；相等 ⇒ `not written`；基线 `absent` 且现在存在 ⇒ `created`。
2. **三尾注字段存在性**：`blockers` / `unconfirmedDiffs` / `uncovered` 三个键都在（可为空数组，但键必须在）；缺键 ⇒ 点名字段。
3. **覆盖对账**：`coveredCases` 里每个 ID 都在 run_start 索引中；`issues[].caseId` 与 `expectRef` 都非空且能指到索引里的 case。
4. **操作真实性读数**（宿主自己数，落 run 状态——新增 `lib/browser/btest/btest_mode.dart`，run 结束归零）：
   - ① **入口动作数** = 1，且首次 url = `startUrl`；0 ⇒ `入口=0`（本轮不是从声明的起点进入）；≥2 的已被拒，被拒次数单列。
   - ② **`browser_evaluate` 写值被拒次数**：> 0 ⇒ 点名（这是「试图用脚本改值」的读数，不是通过项）。
   - ③ **目标形态计数**：文字定位 a 次 / `ref`·`selector` 兜底 b 次（`browser_click` / `browser_type` / `browser_act` 的 click·type 步，按调用参数数）。
   - ④ **绕道对账**：`detours[]` 条数 = `issues[].detour` 非空条数；不等 ⇒ 点名差额。

缺项返回 `warning` 行，不阻断结束——该行同时写进报告头，用户看得见。

**顺序钉死**：AI 必须**先完成预期文件写回，再调 `btest_run_end`**；`btest_run_end` 只校验与收尾，不替 AI 写文件。反过来（先 run_end 再写回）会让检查表第 1 项恒为 `not written`，机械读数退化成常量告警（§3.4 · 用例 #2）。

判据：**任何浏览器工具调用**都需要活动 run（只读动作也计入，这样业务线、环境、预期文件三者始终有出处）；run 结束后旧 `runId` 失效，下一次动作先报错再要求新 run。

### 3.4 预期文件：位置、格式与写法

位置：**独立 QA 仓**，不写业务仓。路径由宿主在 `btest_run_start` 内一次派生，规则唯一、不设情形例外：

1. `btest.qaRoot` 有值 ⇒ `qaRoot` = 该值；配的值必须是绝对路径，否则 `btest_run_start` 拒绝并点名该设置项。
2. 未配 ⇒ `qaRoot = join(dirname(repoRoot), 'qa')`——`qa` 建在业务仓的父目录里，与各项目文件夹并列。
3. 预期文件 = `join(qaRoot, basename(repoRoot), '<业务线>.md')`。

实例（`repoRoot` ⇒ 预期文件）：

| `repoRoot` | 预期文件 |
|---|---|
| `C:\Users\\xinbo\repos\v2-booking` | `C:\Users\\xinbo\repos\qa\v2-booking\订舱.md` |
| `D:\work\客户A\v2-booking` | `D:\work\客户A\qa\v2-booking\订舱.md` |
| `D:\work\客户A\repos\v2-booking` | `D:\work\客户A\repos\qa\v2-booking\订舱.md` |

边界照规则走，不发明例外：`repoRoot` 直接在盘符根（`D:\v2-booking`）⇒ `qaRoot = D:\qa`。派生结果写在 `btest_run_start` 的返回项 2（§3.3），用户看到不对就用 `btest.qaRoot` 覆盖后重跑。多个工作区共用一个 `qaRoot` 时按 `basename(repoRoot)` 分子目录，互不串；同一 `qaRoot` 下同名的业务仓视为同一个仓，共用一个预期文件。

为什么放独立 QA 仓：业务仓要干净（本 run 对它们只做 `git log`），且业务提交会淹没预期文件的历史；放宿主数据目录则不可 diff、不随仓推远端，session 删了即失——等于回到"凭记忆判断"，正是本功能要消灭的。

**目录与 git init（都在 `btest_run_start` 内）**：

- **目录**：`Directory(join(qaRoot, basename(repoRoot))).createSync(recursive: true)`（连 `qaRoot` 一起建）；建不出来 ⇒ 拒绝起 run，文本点名路径与错误。
- **git init**：`qaRoot/.git` 不存在 ⇒ 在 `qaRoot` 跑一次 `git init`；已存在则跳过。**失败不阻断 run**：写入照旧，返回里多一行 `未初始化 git，写入仍可，历史不可追`。
- QA 仓自成一仓：不写业务仓、不改业务仓的 `.gitignore`。

预期文件的内容（文件内）：

```markdown
# 订舱（v2-booking）业务线

> 环境：dev · 起点：https://<dev 域名>/booking · 角色：货代操作员
> 更新：2026-10-22 · 变更范围：git log --oneline -30 @ <短号>

## CASE-BKG-001 新建订舱单并提交
- source: old            # new | old
- origin: 无（存量流程）  # 提交短号 / iss-编号 / 需求档节 / 无
- pre: 登录=货代操作员；入口=/booking/new；无草稿
- steps:
  1. 起运港填 CNSHA、目的港填 USNYC → 港口下拉出现两项，选中后回填文本
  2. 箱型 40HQ × 1 → 箱型行出现，合计=1
  3. 点「提交」 → 生成订舱号 BK…，状态=待审核，列表首行出现
- expect: 单据号非空；列表刷新；无 console error；POST /api/booking 200 且 code=0
- expectFrom: 强 · v2-booking/docs/vibe-coding.md §3.1
- last: 2026-10-22 pass
```

字段级约定：

| 字段 | 必填 | 含义 | 谁写 |
|---|---|---|---|
| 文件头 `环境/起点/角色` | 是 | 这一轮从哪进去、以谁的身份 | AI 首次生成，人可改 |
| `变更范围` | 是 | run 开始时读到的那段提交记录 | AI 每次 run 更新 |
| `## CASE-<线>-<序号>` | 是 | 一条 case | AI（人可加） |
| `source` | 是 | `new` = 行为来自本轮变更范围；`old` = 存量 | AI |
| `origin` | 是 | 提交短号 + issue 号 / 需求档节 / `无（存量）` | AI |
| `pre` | 是 | 前置状态（数据 / 角色 / 入口 / 草稿或缓存） | AI |
| `steps` | 是 | 每步「动作 → 期望」，期望必须可判定（值 / 文本 / 状态） | AI |
| `expect` | 是 | 整条 case 的通过判据 | AI |
| `expectFrom` | 是 | 该 case 预期的**出处 + 强弱级别**（字段定义与三级来源见下） | AI（人可改） |
| `last` | 是 | 最近一次结果 + 日期（pass / fail / blocked） | AI |

**`expectFrom` 字段定义**（每项一行）：

- 字段名：`expectFrom`
- 类型：string；多来源以 `;` 并列，每项自带级别
- 必填：是——缺该行即 case 非法
- 示例：`强 · <业务仓>/docs/<档>.md §N.M`

**`expectFrom` 的三级来源**：

| 级别 | 来源 | 引用形 | 能否支撑「预期不符」 |
|---|---|---|---|
| 强 | 业务设计档的某一节 | `<业务仓>/docs/<档>.md §N.M` | 能 |
| 中 | 冒烟清单条目 / 历史 issue | `<业务仓>/docs/audits/<清单>.md #L<行>` · `issue #<号>` | 能 |
| 弱 | 代码现状 | `<业务仓>/lib/…:行` · 接口实际返回（`POST /api/x 200 code=0`） | 不能，结论封顶「待确认」 |
| — | 无权威来源 | `无权威来源 · <缺哪条规则>` | 不能，结论一律「待确认」 |

三级 = 强 / 中 / 弱；`无权威来源` 不是级别，是「找不到任何来源」时的标记。引用形实例（主 agent 实读的业务仓）：

```text
v2-booking/docs/vibe-coding.md §3.1                 强：该档带编号小节（如 ## 3.1 VoyageOperator · Booking 首页）
v2-booking/docs/audits/smoke-checklist.md #L420     中：现成冒烟清单（51 KB）
issue #892                                          中：历史 issue（905 条，归 19 类，见需求档 §7）
```

三条硬规则：

1. **代码现状不得作预期**：`expectFrom` 指向代码现状（弱）的 case **不得判「预期不符」**——结论封顶「待确认」，并进报告「待确认差异」的「需要用户补规则的清单」。
2. **找不到强来源时的动作**：先降级找「中」（冒烟清单条目 / 历史 issue）；「中」也没有、或引用的档 / 节打不开 ⇒ 写 `无权威来源 · <缺哪条规则>`，结论一律「待确认」，由用户补规则。不得凭记忆补设计档内容，也不得为凑出处把读代码得到的行为写成「强 · <某节>」——两者都是把实现当权威。
3. **覆盖到每条预期**：case 级 `expectFrom` 覆盖该 case 的 `expect` 与 `steps` 里的全部期望；某一步的期望另有出处 ⇒ 该步内联 `（源：强 · <引用>）`，报告以该步的出处为准。

写规则：

- **谁写、何时写**：AI 用文件工具写。run 开始时 `btest_run_start` 已把预期文件读成"case 索引 + 内容 hash"（返回项 3 / 4），"必读"从此是机械保障；**run 结束前一次写回**（新增 case / 修正 expect / 更新 last / 更新变更范围），写回完成后再调 `btest_run_end`。基线 hash 来自 run_start 返回，宿主用"当前 hash ≠ 基线"判 `written`——所以顺序不能反。
- **写失败**：报告尾注「阻塞」记路径与错误原文；`btest_run_end` 的检查表标 `expectFile: not written`；该 run 仍可结束（业务不被文件权限堵死），但报告头会带这一行。
- **人已改过文件**：写回前先重读并算 hash；当前 hash ≠ run_start 基线 ⇒ 期间有人动过（AI 只在最后写一次，不会中途改）⇒ 不覆盖，改为在文件末尾追加 `## YYYY-MM-DD 修订建议` 段，并在报告尾注「待确认差异」里点名；下一次 run 由人决定是否合并。
- **首次生成**：目录已由 `btest_run_start` 建好（见上）；文件不存在时按骨架写（文件头 + 本轮读到的 case + 本轮 `commitRange`），骨架内容只写已验证的步骤与预期，不写推测。
- **来源纪律（写回时）**：AI 写回时可新增 `expectFrom`（新 case、旧 case 补出处），但**不得把「中 / 弱」来源改写成「强」**——级别是判据不是标签，升级等于把「可能对」写成「权威」，一条 bug 因此被放行。需要升级的进报告「待确认差异」，人确认后再改。

### 3.5 case 的 `source` 与出处；差异处置落成步骤

`source` 判定（可执行顺序）：

1. run 开始时读**一次** `git -C <repoRoot> log --oneline -30`，把区间与摘要记进 `commitRange`（只读一次，不每步查）。
2. 新 case 落盘时，看该 case 涉及的页面 / 字段 / 接口是否在 `commitRange` 里出现：出现 ⇒ `source: new`，`origin` 写提交短号（含 `iss-` 号）；未出现 ⇒ `source: old`，`origin` 写 `无（存量）` 或在需求档里点名的节。
3. `old` case 的 `expect` **只从文件读**，不从模型印象补；文件没有该 case ⇒ 先按只读轮生成，不直接报 bug。

差异处置（两个 case 效果不一样时，四步）：

1. 逐项对比两次前置：数据、登录角色、页面入口、草稿/缓存、时间。
2. 新建一个干净前置：重新登录 / 新建单据 / 清草稿与缓存。
3. 同步骤重跑一次（同一操作最多总共做 2 次，不反复点）。
4. 仍不同 ⇒ 报告尾注「待确认差异」，附三次的步骤与状态；一致 ⇒ 记为「环境问题」，把前置差异写回该 case 的 `pre`。

### 3.6 工具面：操作真实性（所有轮次）∥ 只读轮 ∥ 写轮

先定一条事实：**文字定位不需要新工具**。`browser_click` 的描述已写明 `by ref or by its words (text, with role and near to tell it from others alike)`（`lib/browser/browser_actions.dart:126-129`），`browser_type` 的输入面同样有「字段的话」形态（`lib/browser/browser_actions.dart:146-156`）。本批不改这两个工具的协议，只把「首选 / 兜底 / 禁止」定死，并在宿主侧数出来。

**定位规则三行（所有轮次）**：

- **首选**：可见文字——按钮文字、字段 label、表头列名、可见角色（`text` / `into` 加 `role` / `near`）。
- **兜底**：`ref`（或 `selector`）仅当该元素**没有可见文字**时使用，例如纯图标按钮；每次兜底在报告步骤列写「无可见文字：<元素描述>」，次数由检查表 4-③ 数出来（§3.3）。
- **禁止**：以 DOM id / class / xpath / 快照编号作为首选定位。更硬的一条：元素**有**可见文字却按文字找不到或点不动，那是缺陷（label 未关联 / 可访问性缺失），记入报告，不得改用 `ref` 或 id 绕过（F2.1 ③）。

本轮对工具协议只加两个可选参数：

| 工具 | 新增参数 | 用途 |
|---|---|---|
| `browser_navigate`（`lib/browser/browser_tools.dart:262-278`） | `detour`（string） | 入口之后那次导航必带：值 = 已记录缺陷的一句话（§3.6.2） |
| `browser_evaluate`（`lib/browser/browser_tools.dart:291-303`） | `readOnly`（boolean，默认 false） | 只读轮的声明；既有「带 `readOnly: true` 才放行」此前没有对应参数，本次补上 |

#### 3.6.1 六条细则各自判到哪一层

F2.1 的六条不是都能在宿主侧机械判。判不了的写清替代，不假装是硬闸：

| 细则 | 工具层能判多少 | 判据落点 |
|---|---|---|
| ① 入口只一次 | 能判：入口动作计数 + 首次 url = `startUrl` | §3.6.2 · §3.3 检查表 4-① |
| ② 文字首选、禁 id / class / xpath 首选 | 半能判：目标形态可数（带 `ref` / `selector` 即记兜底）；「当时有没有可见文字」判不了 | 计数在 §3.3 检查表 4-③；纪律在 `[D7]`（§3.2）；理由写进报告步骤列 |
| ③ 按文字找不到可点目标 = 缺陷 | 判不了（宿主看不到元素） | 纪律 `[D7]` + 报告：该步进「阻塞」，严重度按 §3.8 |
| ④ 逐字键入、禁 JS 赋值、禁绕表单调接口 | 能判：写入形态扫描 + `browser_request` 的 `replay` 拒绝 | §3.6.3 · §3.3 检查表 4-② |
| ⑤ 读只用于判定 | 半能判：`replay` 拒；「用读代替点击」靠走查 | §3.6.3 · §6 的「验收 6」行（走查列） |
| ⑥ 唯一例外 + 先记后绕 | 能判：`detour` 参数 + `detours[]` 与报告绕道行数相等 | §3.6.2 · §3.3 检查表 4-④ · §3.8 绕道栏 |

`detour` 的文本是否真描述「缺什么」，宿主判不了（只判非空）——这条归走查，见 §10 第 9 条。

#### 3.6.2 入口规则：一轮一次导航 + `detour` 例外通道（唯一表述）

**入口动作** = 任何带 url 的页面跳转，三条路径同判：

- `browser_navigate` 的 `url`（`lib/browser/browser_tools.dart:266-278`）；
- `browser_act` 的 `{action: "navigate", url}`（`lib/browser/browser_actions.dart:220`）；
- `browser_open` 的 `url`（`lib/browser/browser_tools.dart:232-244`）。

只关其中一条就 fail-open：另外两条照样能把页面直接送到深链。所以判据认「入口动作」，不认「哪个工具」。

规则一句话：**一轮内入口动作总数 = 1，且首次 url = run 的 `startUrl`；此后任何入口动作不带 `detour` 一律拒绝。**

- **第一次**：不带 `detour`；url 与 `startUrl` 比较（去尾斜杠）。不等 ⇒ 拒绝，文本点名「入口必须是本轮声明的起点」，并回显 `startUrl`。
- **第 2 次起**：必须带 `detour`（string，非空）。值 = **已经记录下来的那条缺陷的一句话**，例：`detour: "货代协议案无菜单入口，只能手输 URL"`（形态同 issue #899）。
  - 带 ⇒ 放行该次导航，宿主把 `detour` 原文、第几次入口、url 记进 run 状态的 `detours[]`。
  - 不带 ⇒ 拒绝，文本点名「先记缺陷再绕道」，并给出 `detour` 写法示例。
- 这两种结果是**同一条判据**（有 `detour` 放行 / 无 `detour` 拒绝），不存在第三种「静默绕道」：run 开始之后任何入口动作，只要不是第一次又没有 `detour`，就被拒。
- `action: back / forward / reload`（`lib/browser/browser_tools.dart:271-275`）不是入口动作，不计次数——它们是浏览器原生控件，用户本人随时可做。`reload` 不得用来代替点击推进，也不得让「页面不刷新」类问题消失（问题域 10 要求「不刷新读一次」，那次读数不得紧跟在 `reload` 之后）。
- 入口用 `browser_navigate`：`browser_open` 作入口会被计数并显示在报告头读数里（§3.8），用它起跑时验收 6 的「`browser_navigate` 次数 = 1」当场读作 0，用户一眼可见。

**为什么顺序可机检，不靠纪律**：`detour` 的文本就是缺陷描述本身，它必须出现在导航**之前**的同一次调用里——这不是提示词里的先后要求，是调用面的事实：不带 `detour` 的第二次导航在工具层就被拒，「先走再补记」没有那条路。run 结束时「`detours[]` 条数 = `issues[].detour` 非空条数」不等即报 warning（§3.3 检查表 4-④），绕道因此必须落到报告的一行上。

#### 3.6.3 写值类判据：`browser_evaluate` 与 `browser_request`（唯一表述，合并只读轮例外）

btest 下 `browser_evaluate` 只有一种合法用途：**读**。三条判据，写在这一处，别处只引用：

1. **所有轮次（write ∥ readonly）都不得写值**。宿主扫描表达式，命中即拒绝，文本点名「btest 下 evaluate 不得写值」。写入形态：字段赋值（`x.value =` / `x.checked =` / `x.selectedIndex =`）、`fetch(`、`XMLHttpRequest`、`document.cookie =`、`localStorage.setItem` / `sessionStorage.setItem`、`dispatchEvent(`，以及以脚本代替点击的 `click()` / `submit()`。
2. **只读轮另加一条（取严）：必须带 `readOnly: true`**，缺则拒绝，文本点名 `mode: readonly` 与 `readOnly`。它跑在第 1 条之后，是只读轮的附加要求，不是第二份判据。
3. **`browser_request` 的 `replay` 在 btest 下一律拒绝**（含 `changes`）——`replay` 是「从页面把请求再发一次，可改 url / method / headers / body」（`lib/browser/browser_debug_tools.dart:194-197`），正是 F2.1 ④ 禁止的「绕表单调接口」。只读形态（请求列表、headers、body、`as: curl|fetch`）照旧放行。

写轮里 evaluate 照常可用（写轮放宽的是「能不能动手」，不是「怎么动手」），但写值仍被第 1 条拒。**读绑定值 / 隐藏输入是合法读**（问题域 18 的判断要靠它）：读隐藏字段合法、写隐藏字段不合法——两件事，别混成一件。

**启发式未命中不等于安全**：凡以此取得的证据，报告里必须注明「该证据来自 evaluate」。

#### 3.6.4 只读轮（`mode: readonly`）的工具面

逐工具判，不按表达式猜：

| 面 | 工具 |
|---|---|
| 允许 | `browser_tabs` · `browser_open` · `browser_navigate` · `browser_snapshot` · `browser_inspect` · `browser_network` · `browser_console` · `browser_request` · `browser_watch` · `browser_history` · `browser_sources` · `browser_scroll` · `browser_close` · `browser_performance` · `browser_coverage` · `browser_memory` · `browser_screenshot`（工具可用，但截图不进报告） |
| 拒绝 | `browser_click` · `browser_type` · `browser_press` · `browser_act` · `browser_upload` · `browser_dialog` · `browser_intercept` · `browser_storage` · `browser_emulate` · `browser_debugger` · `browser_evaluate`（按 §3.6.3：只读轮必须带 `readOnly: true`） |

#### 3.6.5 写轮（`mode: write`）

全部动作开放，但仍受两处约束：§3.7 的域名与生产闸；§3.6.2 / §3.6.3 的操作真实性判据（写轮不放宽「怎么点、怎么输入」）。

#### 3.6.6 业务仓文档与代码的读取（F5 后半段）

`api` / `database` / `docs` / 前端仓的读取**不在** btest 自动放行面内——它们不是 `group == 'browser'` 的宿主工具（§3.7 放行范围）。宿主文件工具与 shell 走内核原有审批：btest 不替它们答 allow，也不额外加一道卡。路径用 run 的 `repoRoot` 拼绝对路径；因此"不确定时回看文档/代码"的代价是一张普通审批卡，与只读轮的浏览器边界无关（只读轮限制的是浏览器动作面，不是文件读）。

### 3.7 自动放行的边界与违规行为

放行范围：仅 `group == 'browser'` 的宿主工具（`lib/browser/browser_tools.dart:110-112`）——文件工具、bash、Git 等都不在 btest 的自动放行面内。

放行判据（**全部满足**才放行；**任一不满足 ⇒ 拒绝**——浏览器动作在 btest 下没有"转人工审批"这一结果，理由见本节末段）：

1. 本会话 `btest == on`；
2. 有活动 run；
3. 目标 host ∈ `btest.allowHosts`；
4. 动作是只读，**或** 写动作同时满足三条：`env != prod` ∧ `btest.prodHosts` **非空** ∧ 目标 host ∉ `btest.prodHosts`。

**两条生产闸（缺任一即 fail-open，故写成硬规则）**：

- **规则 A（起 run 即拒）**：`btest_run_start` 收到 `env: prod` + `mode: write` ⇒ **拒绝起 run**，文本点名 `env: prod` 与 `mode: write`。理由：需求边界"不在生产环境做写操作"是授权问题，不是域名判断问题——不能等第一个写动作才拦。
- **规则 B（写动作逐次判）**：写动作自动放行必须 `env != prod` ∧ `prodHosts` 非空 ∧ host ∉ `prodHosts`。**`prodHosts` 为空 ⇒ 写动作在工具 `run` 层硬拒绝**（空列表是"没配"，不是"没生产域名"），文本点名规则 B 与「设置 → 浏览器 → btest」的 prodHosts 入口。

**权威划分**：`env` 是**权威**（本 run 声明的环境，写动作的总闸）；`prodHosts` 是**纵深防御**（host 级网，兜住"env 标了 test 但实际打到生产域"的误配）。两者取严：任一判定为生产 ⇒ 拒。反过来不成立——`env: dev` 不能豁免 `prodHosts`，`env: prod` 也不因 host 不在 `prodHosts` 而放行。

**与操作真实性判据的先后**：§3.6.2 / §3.6.3 的判据是**前置拒绝**，在放行判据之前跑——host 在白名单、env 不是 prod，第二次入口动作照样被拒。放行只回答「这个动作能不能自动放行」，不回答「这个动作改写没改写操作路径」。

**两组判据的物理落点（唯一坐标）**：都落在浏览器工具的 `run` 包装——`lib/browser/browser_tools.dart:115-130` 的闭包是 `register()` 给每个浏览器工具套的那一个（`:96-98` 逐个构造），拿得到 `tool.name` 与结构化 `input`。
闸口写在闭包最前，先于 `:117` 的 `tabId is! int` 早退（否则 `browser_tabs` / `browser_open` 这类不带 tabId 的工具会绕过，`lib/browser/browser_tools.dart:210-231` / `:232-244`）。
`btest_run_start` / `btest_run_end` 自身豁免本闸（它们的判据是会话 `on` / 规则 A / 无 run 前置），其余浏览器工具一律过闸。
MCP 的 `tools/call`（`lib/host_tools/host_tools.dart:194-243`）只把 name + arguments 原样转给 `tool.run`，是**分发面**，不承载判据——本批不改该档，§4 因此无此行。

边界情形：

| 情形 | 行为 |
|---|---|
| 生产 host（`btest.prodHosts`）上的写动作 | **拒绝**（不是询问），文本点名规则与 host |
| `env: prod` + `mode: write` 起 run | **拒绝起 run**（规则 A），文本点名两项 |
| `btest.prodHosts` 为空 + 写动作 | **拒绝**（规则 B，工具 `run` 层硬拒绝；零审批卡），文本点名 prodHosts 未配置与设置入口 |
| `env: test` 但 host ∈ `prodHosts` | 拒绝（取严），文本点名 host 与"env 与 prodHosts 冲突" |
| 未知 host（不在 allowHosts） | **拒绝**（读 / 写同判，工具 `run` 层硬拒绝），文本点名 allowHosts 与设置入口 |
| 无活动 run | 拒绝，文本要求先 `btest_run_start` |
| 只读轮里的写动作 | 拒绝，文本点名 `mode: readonly` |
| 入口动作第 2 次、不带 `detour` | 拒绝，文本点名「先记缺陷再绕道」与 `detour` 写法（§3.6.2） |
| 入口动作第 2 次、带 `detour` | 放行并记入 `detours[]`；报告「绕道」栏必须有对应行（§3.3 检查表 4-④） |
| 任一轮次的 `browser_evaluate` 写值形态 | 拒绝，文本点名「btest 下 evaluate 不得写值」（§3.6.3） |
| 写 run 里的 `browser_request` 带 `replay` | 拒绝，文本点名「绕表单调接口」（§3.6.3） |

违规行为：工具抛 `BrowserError`（`lib/browser/browser_bridge.dart:698-700`），文本形如 `btest denied: <动作> on <host> — <规则>（设置 → 浏览器 → btest）`。用户看到该步失败；agent 必须把它记入报告尾注「阻塞」。**不静默跳过、不降级为询问**。

**判定面与展示面分开（实读结论，2026-10-22）**：

- **判定面 = 浏览器工具的 `run` 包装**（`lib/browser/browser_tools.dart:115-130`）：拿得到 `tool.name` 与结构化 `input` ⇒ 白名单 / 只读面 / 生产禁写 / `readOnly` / 入口 / evaluate 写值 / `replay` 全在这里判，**放行与拒绝都由这一层出结果**。拒绝抛 `BrowserError`（文本见上）。
- **分发面 = MCP `tools/call`**（`lib/host_tools/host_tools.dart:194-243`）：把 `params['name']` 与 `params['arguments']` 原样交给 `tool.run`，不加判据；本批不改该档。
- **展示面 = 内核审批点**：`lib/kernel/thincoder/thincoder_kernel.dart:1040-1080` 的 `_serverRequest` 收 `session/request_permission`，`request.params['toolCall']` 带 `title` 与 `content`（线形见 `docs/design/thincoder-adapter.md` §3.4）。
  **工具名可得**（`toolCall['title']`，桥侧已剥子代理前缀）；**参数只有显示预览文本**（`ThincoderEvents.preview(toolCall['content'])`，`thincoder_kernel.dart:1074`），没有结构化 `rawInput`。
  ⇒ 这一层只做一件事：**btest on 时对 browser 组答 allow，把审批卡压掉**；它不判 host、不判参数、也不决定放行还是拒绝（判也判不准，KD-13）。
- **为什么没有"转人工审批"这一结果**：工具 `run` 层只能放行或拒绝，问不了人；"交内核审批"要成立，前提是内核确实对 MCP 工具发 `session/request_permission`，而这一点未核实（下一条）——未核实分支（内核不发请求）下，"不自动放行"等于"照常执行"。
  写动作背后是需求边界「不在生产环境做写操作」（`docs/requirements/browser-biz-test.md` §4），不能架在一个未核实的审批点上：所以规则 B 的载体钉在工具 `run` 层硬拒绝，发请求的分支下也一行不差。
  只读动作没有数据变更，但同样没有可依赖的询问载体，所以一并拒绝（取严）。要放行某个 host，到设置页加进 `allowHosts`。
- **残余未核实**：内核是否对 MCP 工具一律发 `session/request_permission`（外仓 `thincoder/` 不在本机，无法实读）。**两个分支下 btest 的读数相同**：发 ⇒ 内核问我、我答 allow（零卡）；不发 ⇒ 无请求（零卡）。放行 / 拒绝只由工具 `run` 层定，因此该未核实项不影响任何判据，用例 #1 无条件成立（§7 · §10 第 2 条）。

### 3.8 报告格式（一轮跑完，一张表 + 三类尾注）

| # | 业务线 | case | source | 步骤 | 现象 | 证据 | 严重度 | 复现前置 | 预期出处（`expectFrom` 原文） | 绕道 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 订舱 | CASE-BKG-001 | old | 提单号填完点保存 | 提示保存成功但列表无新单 | POST /api/booking 200 · code=0 · data.id="" ；console 无 error；列表未刷新 | 高 | 新用户 / 空草稿 | 强 · <业务仓>/docs/<档>.md §3.1 | — |

**报告头一行操作真实性读数**（`btest_run_end` 检查表第 4 项原样贴出，不自报）：

```text
操作真实性：入口=1（navigate=1 · open=0）· evaluate 写值被拒=0 · 文字定位=41 · ref/selector 兜底=1 · 绕道=1
```

**「绕道」列**：非空 = 该步用户本人也做不完整，形如 `绕道：<缺什么> · 第 2 次入口`；每次绕道单独一行（同一缺陷再次绕道写「同上（第 2 次绕道）」，严重度不重复计），行数与 run 状态的 `detours[]` **一一对应**——检查表 4-④ 数的就是它。

**证据定义**（可复核 = 别人照着能重读一次）：接口方法 + 路径 + 状态码 + 关键响应字段；console 原文一行；字段前后值；页面提示原文。截图不计入证据。每条「预期不符」必须能指到预期文件的某条 case（预期文件的绝对路径 + `#CASE-…`，路径见 §3.4），指不到 ⇒ 进「待确认差异」。「预期出处」列写该 case 的 `expectFrom` 原文（级别 + 引用）；级别为「弱」或 `无权威来源` 的 case 不产生「预期不符」——进「待确认差异」，并单列进「需要用户补规则的清单」。

**严重度**：高 = 主流程断（不能提交 / 数据错 / 金额错）；中 = 局部功能不可用或体验断裂；低 = 文案 / 样式 / 边缘。

**三类尾注**（缺一不可）：

1. **阻塞**：本步做不下去，附原因（含被 btest 拒绝的动作与规则）。
2. **待确认差异**：两次或三次结果不一致、尚未定性的条目，附步骤与状态。其中 `expectFrom` 为 `无权威来源` 或指向代码现状（弱）的 case，在本尾注下单列一块 **「需要用户补规则的清单」**：每条 case ID + 缺的是哪条业务规则（一句话）；用户补规则后，下一轮写回 `expectFrom`。
3. **本轮未覆盖**：哪些分支没跑到、为什么（缺账号 / 缺数据 / 被生产禁写挡住等）。

不截图；不边走边停——问题记录后继续，除非整轮无法继续（此时进「阻塞」并结束）。

## 4. 受影响文件清单（现行数 = 2026-10-23 实测；编辑器行号，末行计入；增量 = 本轮 F3.2 的预计改动，`—` = 本轮不动）

| 文件 | 现行数 | 增量 | 说明 |
|---|---|---|---|
| `lib/browser/btest/btest_mode.dart` | 807 | ≤ +45 | 会话级模式状态、run 生命周期、run 闸；`BtestSettings` 增 `btest.qaRoot`；`btest_run_start` 内派生 qaRoot、建目录、`git init`、返回绝对路径 |
| `lib/browser/btest/btest_expect_file.dart` | 200 | ≤ +35 | 预期文件：路径派生（§3.4 规则）、case 索引 + hash 基线、写回校验（`written` / `not written` / `created`）、人改检测与「修订建议」追加、首次骨架生成 |
| `lib/browser/btest/btest_policy.dart` | 393 | — | 判据纯函数：域名 / 生产 / 只读面 / 入口动作与 `detour` / evaluate 写形态 / `replay` / 目标形态 / 拒绝文案 |
| `lib/browser/btest/btest_card.dart` | 124 | — | 模式卡正文（`[btest-mode-card v1]` 标记；含 `[D7]`） |
| `lib/browser/browser_tools.dart` | 787 | — | 工具 `run` 包装的 btest 闸；`btest_run_start` / `btest_run_end` 注册；`browser_navigate.detour`、`browser_evaluate.readOnly` |
| `lib/kernel/thincoder/thincoder_kernel.dart` | 1436 | — | 权限应答处接 btest 放行判据；回合上下文里挂模式卡 |
| `lib/chat/chat_session.dart` | 1458 | — | 模式状态读写、模式卡标记扫描、run 状态投影 |
| `lib/chat/chat_models.dart` | 840 | — | btest 模式与 run 状态的模型字段 |
| `lib/chat/composer/composer.dart` | 2369 | — | 模式选择器追加 `btest` 项 + 状态行 |
| `lib/settings/pages/browser_page.dart` | 390 | ≤ +25 | 允许域名 / 生产域名两个列表 + 默认只读开关 + **`btest.qaRoot` 输入框**（可空 = 派生，§3.4） |
| `lib/l10n/app_en.arb` | 7805 | ≤ +2 键 | **源档**（`l10n.yaml` 的 template，`flutter gen-l10n` 生成）：`btest.qaRoot` 的标签与说明 |
| `lib/l10n/app_zh.arb` | 2941 | ≤ +2 键 | 中文译文，键与模板一一对应 |
| `lib/l10n/app_localizations.dart` | 17716 | 派生 | 生成物，不手改 |
| `lib/l10n/app_localizations_en.dart` | 10847 | 派生 | 生成物，不手改 |
| `lib/l10n/app_localizations_zh.dart` | 10257 | 派生 | 生成物，不手改 |
| `test/browser/btest_policy_test.dart` | 445 | — | 策略判据用例（随批删） |
| `test/browser/btest_card_test.dart` | 110 | — | 模式卡用例（随批删） |
| `test/browser/btest_expect_file_test.dart` | 343 | ≤ +40 | 预期文件用例：`qaRoot` 未配 ⇒ 派生 / 已配 ⇒ 用之 / `git init` 失败不阻断（随批删） |

业务仓零写入：预期文件在独立 QA 仓（§3.4），不在本仓、也不在业务仓的改动面内。

**设置键的落点**：btest 的设置键都在 `BtestSettings`（`lib/browser/btest/btest_mode.dart:15-34`）；`app_settings.dart` 本批不改——它被设置页依赖，把 btest 键放进去会与 `browser_page.dart` 成环。

**超 800 行档：本批不拆，但缝与登记都写明**

| 档 | 现行 | 本轮只加 | 抽取缝（谁动它时从这里切） | 登记 |
|---|---|---|---|---|
| `composer.dart` | 2369 | — | 内核模式选择区整段抽 `composer/mode_selector.dart` | SPLIT-1 |
| `thincoder_kernel.dart` | 1436 | — | 审批面（`_serverRequest` / `answer` / `_resolveApprovals`）抽 `approvals.dart` | SPLIT-2 |
| `chat_session.dart` | 1458 | — | 模式与设置投影抽 `session/mode_state.dart` | SPLIT-3 |
| `chat_models.dart` | 840 | — | 模式 / run 模型抽 `chat/btest_models.dart` | SPLIT-4 |
| `btest_mode.dart` | 807 | `qaRoot` 设置 + 路径派生 + 返回项（≤ +45） | 设置读写（`lib/browser/btest/btest_mode.dart:15-34`）抽 `btest/btest_settings.dart`；路径派生抽 `btest/btest_expect_path.dart` | SPLIT-5 |

**新增实现只落 `lib/browser/btest/*`**（mode / policy / card / expect-file 四个文件）；四个大档里只出现"调用点 + 一个钩子"，不搬已有逻辑、不改已有签名；设置页的 `qaRoot` 输入框落在既有 `browser_page.dart` 的 btest 段内。

**登记**：SPLIT-1…5 = 拆分登记项（不在本批落地）。台账写权不在设计位，所以本批只在档内登记并在回执点名，由主编排方落台账行（挂本批 #149 的后续批）。

## 5. 关键决策记录（含被否）

| 编号 | 决策 | 被否方案与理由 |
|---|---|---|
| KD-1 | `btest` = 宿主 overlay，会话级开关，不发内核 | 改内核 mode：要动外仓 `thincoder/`，且改 ACP `mode` 语义（本批已定不做） |
| KD-2 | 模式卡走 `KernelTurn.contexts`，首条消息注入一次 | MCP `instructions`：全局、initialize 一次，不能按会话切模式；append-system-prompt：thincoder 无此通道 |
| KD-3 | 用 `btest_run_start` / `btest_run_end` 把一轮变成机械判据 | 只靠提示词：漂移无法判，忘没忘看不出来 |
| KD-4 | 预期文件放独立 QA 仓：`qaRoot`（`btest.qaRoot`；未配 ⇒ `join(dirname(repoRoot), 'qa')`）下的 `<仓名>/<业务线>.md` | ① 业务仓 `docs/qa/`：用户要求业务仓干净，业务仓只做 `git log` 来源判定，且业务提交会淹没预期文件的历史；② 宿主数据目录：不可 diff、不随仓推远端，session 删了即失（等于回到凭记忆判断）；③ 每轮一个文件：无法积累、无法对比 |
| KD-5 | 人已改文件时追加「修订建议」，不覆盖 | 直接覆盖：抹掉人的编辑，且无法追责 |
| KD-6 | 只读轮默认拒绝写动作与 evaluate | 按表达式白名单放行：判不准，等于假安全；全放开：F5 名存实亡 |
| KD-7 | 自动放行只覆盖 browser 组 | 全会话 bypass：文件与 shell 的面不在本批授权内 |
| KD-8 | 截图工具保留，但截图不进报告 | 删工具：调试仍要用；进报告：用户明确不要 |
| KD-9 | 报告一轮一次，不边走边停 | 边跑边报：慢（用户明确否掉），且打断整轮节奏 |
| KD-10 | 卡不撤回，退出注入中和语 `[btest-mode-card-off v1]` | 撤回卡（删 transcript）：改历史，且会话恢复会重放；不处理：验收 1「不残留提示词」被换成"不新增"（评审已判 🔴）。中和语让"有效指令"变成"已退出"，判据仍是退出后的行为 |
| KD-11 | 写回在 `btest_run_end` 之前，run_end 只校验 | 先 run_end 再写回：检查表第一项恒 `not written`，机械读数退化成常量告警 |
| KD-12 | `env` 为权威、`prodHosts` 为纵深防御，取严 | 只靠 `prodHosts`：空列表即 fail-open（评审 🔴）；只靠 `env`：env 标错就全放行 |
| KD-13 | 自动放行面只判工具名（内核审批点无结构化参数）；拒绝面判 name + arguments（工具 `run` 层） | 在审批点解析预览文本取参数：格式随内核变，是假判据 |
| KD-14 | `expectFrom` 按 case 一个字段（多来源 `;` 并列，单步另有出处用内联「源：」）；「指向代码 ⇒ 待确认」靠报告级别列 + 走查 | ① 逐步必填 `expectFrom`：写读翻倍，且与报告「一条问题一行」对不齐；② 宿主在 `btest_run_end` 校验引用：只能验「档在 / 节在」的形状，验不了「这一节是否真支持这条预期」，形状合规的假引用照样过——机械绿灯比没有更危险 |
| KD-15 | 入口判据挂在 `browser_navigate` 的 `detour` 参数上，不开独立工具 | ① 独立工具 `btest_detour`：多一次调用，顺序可被跳过（先导航、再补记录），正是用户 2026-10-23 00:02 追加要求否掉的；② 只写在模式卡里：顺序不可机检 |
| KD-16 | `browser_evaluate` 在 btest 下所有轮次禁写值，规则只写 §3.6.3 一处；只读轮另加 `readOnly: true`（取严） | ① 只读轮一套、写轮全开：写轮里脚本赋值能让「输入框信息被刷」这类问题消失，而它正是模式卡要判的对象；② 两处各写一份：第二个判据，两版迟早漂移 |
| KD-17 | 入口动作按「带 url 的跳转」判，不按工具判（`browser_navigate` / `browser_act` 的 navigate 步 / `browser_open` 同判） | 只锁 `browser_navigate`：另两条仍是直达深链的入口，判据当场面 fail-open（与评审 #1 同型） |
| KD-18 | 重进 btest 按计数差 `D` 判重投；中和行不存挂起位，投递条件在回合装配时现算（宿主 `off` ∧ `D ≥ 1`），重进早于投递 ⇒ **丢弃、不投、不重投卡**（卡从未失效）；模型侧状态由 `D = count(卡) − count(中和)` 判（`D = 0` 投卡 / `D ≥ 1` 跳过；`D = 1` 模式内 / `D = 0` 已退出），回合装配完成时宿主 `on` ⇔ `D = 1` | ① 只在首次注入（"transcript 有卡则跳过"）：同会话 off→on 后卡不再投、最后一句模式指令是中和行，宿主侧已开、模型侧却停在"已退出"，纪律静默失效（评审 #14）；② 可逆复投行 `[btest-mode-card-on v2]`：多一个标记、多一处状态推导，且卡正文可能已被压缩出上下文，复投行指向空气；③ 挂起中和行随重进后的回合投出、再补投一张卡：同一回合里"已退出 + 模式卡"两句互相抵消，多花约 1.5k，且先中和后投卡的顺序成了第三条隐含判据；丢弃则两种投递按宿主状态互斥，无顺序依赖 |
| KD-19 | 写动作在工具 `run` 层二值判定（放行 / 拒绝），btest 无"转人工审批"中间态；内核审批点只压审批卡 | 把写动作的不自动放行交给内核审批询问：该点是否被调用未核实，未核实分支（内核不发 `session/request_permission`）下等于放行，需求边界失守（评审 #16）；只读动作的非白名单情形同理取严拒绝 |
| KD-20 | 预期文件的文件名与路径全由宿主派生（`line` + `repoRoot` + `btest.qaRoot`），`expectFile` 不作入参；派生结果作为 `btest_run_start` 返回项 2 给出 | ① 保留 `expectFile` 作「业务线名」入参：`line` 已是业务线名，两个字段必须相等 ⇒ 多一个能漂移的来源；② 保留相对路径入参：落点依赖调用方每次传对路径，且路径绑死业务仓；③ 不返回绝对路径：用户无法当场核对落点，配错要等写入失败才发现 |

## 6. 验收对照（回指需求 F1–F6 · F2.1 · F3.1 · F3.2 与 §5 验收 1–6）

| 需求 | 设计落点 | 可跑判据 |
|---|---|---|
| F1 模式切换 | §3.1 · §3.2 | 走查：切到 btest → composer 出现状态行；切回 normal → **不残留**：状态行消失、下一回合起不再按 btest 纪律行事（不自动 start run、不套三尾注、不受只读面约束）；**计数差判据（任意次开→关→再开之后仍成立）**：`D = count("btest-mode-card v1") − count("btest-mode-card-off v1")` = 1（模式内）/ 0（已退出）；读数为**回合装配完成时**的值：宿主 `on` ⇔ `D = 1`、宿主 `off` ⇔ `D = 0`（§3.2「判定的时刻」）；`grep` 形态：`echo $(( $(grep -c "btest-mode-card v1" <会话记录>) - $(grep -c "btest-mode-card-off v1" <会话记录>) ))` |
| F2 模式卡 | §3.2 | ① 计数差 `D = 1`，第二条消息后仍 = 1（同一会话内多投一张即失败；`grep` 形态同 F1 行）；② 内容清单：`btest_card_test` 断言 `[D1]`–`[D7]` 七个、`[J1]`–`[J7]` 七个、`[P01]`–`[P19]` 十九个、`[H1]`–`[H3]` 三个标签齐全，缺一即失败 |
| F3 预期落盘 | §3.3 · §3.4 | ① `btest_run_start` 返回含绝对路径 + case 索引 + 内容 hash（缺一即实现不全）；② 跑完一条业务线后预期文件（§3.4 派生路径）存在，报告每条「预期不符」能指到其中一条 `## CASE-`；③ 检查表的 `written` / `not written` 与 hash 基线读数一致 |
| F3.2 落点 = 独立 QA 仓 | §3.3（`expectFile` 不入参 · 返回项 2）· §3.4（派生规则 + 目录 / git init）· §9（`btest.qaRoot`） | ① 跑一次后预期文件出现在 `<qaRoot>/<仓名>/<业务线>.md`：未配 `qaRoot` ⇒ `join(dirname(repoRoot), 'qa')`，已配 ⇒ 用之（§7 #24 / #25）；② 返回项 2 是解析后的绝对路径；③ 业务仓零写入：跑完 `git -C <repoRoot> status --porcelain` 为空；④ `qaRoot/.git` 存在（首次 run 已 init）；init 失败时返回含 `未初始化 git，写入仍可，历史不可追`，run 照常 |
| F3.1 预期带出处 | §3.4（三级来源 + 三条硬规则）· §3.8 | ① 预期文件每条 case 有 `expectFrom`，级别 ∈ {强, 中, 弱} 或 `无权威来源`，引用形合 §3.4 的表；② 对读写回前后的文件：级别只降不升（中 / 弱 不得被写成强）；③ `无权威来源` 的 case 在报告「需要用户补规则的清单」里逐条点名 |
| F4 来源标注 | §3.5 | 文件里每条 case 有 `source:` 与 `origin:` 两行；差异条目在报告尾注「待确认差异」里带三次步骤 |
| F5 只读轮 | §3.6 | 只读 run 里调 `browser_click` → 返回拒绝文本，含 `readonly` |
| F5 回看文档 / 代码 | §3.6 | 走查：只读 run 里读业务仓 `docs/` 下的文件 → 走内核原审批（btest 不代答 allow），读取成功，只读轮的浏览器边界不变 |
| F6 报告 | §3.8 | 报告是一张表 + 三尾注；表内无图片；每条证据是接口 / console / 字段值之一；三尾注由 `btest_run_end` 的 `blockers` / `unconfirmedDiffs` / `uncovered` 三个键承载 |
| 验收 2（证据可复核） | §3.8 | 任取一条问题，按「证据」列能在页面上重读出同一读数 |
| 验收 3（预期来自盘上且带出处） | §3.4 · §3.8 | 每条「预期不符」的「预期出处」列非空、级别 ∈ {强, 中}、引用能落到档 + 节 / 冒烟清单行 / issue 号；`expectFrom` 指向代码现状或为 `无权威来源` 的 case 不出现在「预期不符」行里（§7 #16） |
| 验收 4（来源可追溯） | §3.5 | 每条 case 的 `origin` 能在 `git -C <repoRoot> log` 里找到，或明确写 `无（存量）` |
| 验收 5（稳定性读数） | §3.8 | 连续两次只读跑，报告里步骤序列一致率可数（不作为硬门槛） |
| 生产禁写（规则 A） | §3.7 | 走查：`btest_run_start`（env: prod、mode: write）→ 拒绝起 run，文本点名两项，run 未建立 |
| 生产禁写（规则 B） | §3.7 | 走查：`prodHosts` 清空 + 写 run 的 `browser_click` → **拒绝**（工具 `run` 层硬拒绝，零审批卡），文本点名规则 B 与 prodHosts 未配置；`prodHosts` 填入该 host 后再点 → 拒绝，文本点名生产禁写 |
| F2.1 操作方式 = 模拟真人 | §3.6.1–§3.6.5 · §3.3 检查表 4 · §3.8 绕道栏 | 见下一行：验收 6 是它的机检口径 |
| 验收 6（操作真实性，机检） | §3.6.2 · §3.6.3 · §3.3 检查表 4 · §3.8 | ① 报告头读数「入口 = 1」且首次 url = `startUrl`；② 「evaluate 写值被拒」= 0；③ 「文字定位 / ref·selector 兜底」两个数都在报告头，兜底 > 0 时每步在步骤列写了理由；④ `browser_click` / `browser_type` 的目标以文字 / label / 角色描述（兜底步除外）；⑤ 请求源于真实点击：`browser_history` 的 clicks 记录对请求时间线走查（`lib/browser/browser_history.dart:537-547`） |

## 7. 用例表（正常 / 边界 / 错误）

| # | 类型 | 输入 | 期望输出 | 测试落点 |
|---|---|---|---|---|
| 1 | 正常 | btest 开、run（dev、write、host 在白名单）→ `browser_click` | 自动放行，无审批卡，动作执行（内核发不发审批请求都无卡：发则钩子答 allow，不发则无请求；§3.7 末段） | `btest_policy_test`（放行判据）+ 走查（无审批卡） |
| 2 | 正常 | 已写完回 + 三尾注结构化载荷 → `btest_run_end` | 检查表四项全绿；`expectFile: written` | `btest_expect_file_test` |
| 3 | 边界 | 只读 run → `browser_snapshot` / `browser_network` | 放行 | `btest_policy_test` |
| 4 | 边界 | 只读 run → `browser_evaluate` 不带 `readOnly` | 拒绝，文本点名 `readonly` | `btest_policy_test` |
| 5 | 边界 | 只读 run → `browser_evaluate` 带 `readOnly:true`，表达式只读 | 放行 | `btest_policy_test` |
| 6 | 边界 | 写 run（env: test）→ host ∈ `prodHosts` 的 `browser_click` | 拒绝，文本点名生产禁写与 host | `btest_policy_test` |
| 7 | 边界 | 未 start run → 任何浏览器动作 | 拒绝，文本要求 `btest_run_start` | `btest_policy_test` |
| 8 | 边界 | 人改了预期文件（写回前 hash ≠ 基线）→ 写回 | 追加「修订建议」段，原行不动 | `btest_expect_file_test` |
| 9 | 错误 | 预期文件不可写（权限 / 路径不存在） | `btest_run_end` 返回 `warning`，报告头标 `not written` | `btest_expect_file_test` |
| 10 | 错误 | `btest_run_start` 缺 `repoRoot` / `line` / `startUrl`，或 `btest.qaRoot` 配了相对路径 | 拒绝，字段级错误信息（`qaRoot` 一行点名设置项） | `btest_policy_test` |
| 11 | 错误 | 会话恢复后 btest 仍开、transcript 无卡标记 | 下一条消息重新注入一次卡；退出后的下一回合投出 `[btest-mode-card-off v1]` | `btest_card_test` |
| 12 | 错误 | 非 btest 会话调 `btest_run_start` | 拒绝，提示本会话未开 btest | `btest_policy_test` |
| 13 | 错误 | `btest_run_start`（env: prod、mode: write） | 拒绝起 run，文本点名两项（规则 A） | `btest_policy_test` |
| 14 | 边界 | `prodHosts` 为空 → 写 run 的 `browser_click` | **拒绝**（工具 `run` 层硬拒绝，规则 B；零审批卡），文本点名 prodHosts 未配置 | `btest_policy_test` |
| 15 | 边界 | env: test 但 host ∈ `prodHosts` → `browser_click` | 拒绝（取严），文本点名 host 与 env 冲突 | `btest_policy_test` |
| 16 | 边界 | 某 case 的 `expectFrom` 指向代码现状（`lib/…:行` 或接口实际返回） | 该 case 判「待确认」而非 bug，进「待确认差异」的「需要用户补规则的清单」；报告「预期出处」列显示 `弱 · <代码坐标>` | 走查（报告表 + 预期文件对读；不进 `btest_run_end` 检查表，理由 KD-14） |
| 17 | 边界 | run 中第 2 次入口动作、不带 `detour`（`browser_navigate` / `browser_act` 的 navigate 步 / `browser_open` 任一） | 拒绝，文本点名「先记缺陷再绕道」+ `detour` 写法示例；run 保持有效 | `btest_policy_test` |
| 18 | 边界 | run 中第 2 次入口动作、带 `detour: "货代协议案无菜单入口，只能手输 URL"` | 放行；`detours[]` 记一条；`btest_run_end` 检查表 4-④：`detours[]` 条数 = `issues[].detour` 非空条数（不等 ⇒ warning） | `btest_policy_test` |
| 19 | 错误 | 写 run（env: test）→ `browser_evaluate` 表达式 `document.querySelector('#a').value='1'` | 拒绝，文本点名「btest 下 evaluate 不得写值」；检查表 4-② 计数 +1 | `btest_policy_test` |
| 20 | 错误 | 写 run → `browser_request` 带 `replay: true` | 拒绝，文本点名「绕表单调接口」（F2.1 ④） | `btest_policy_test` |
| 21 | 正常 | 写 run → `browser_click` 以 `text` + `role` 定位（不带 `ref` / `selector`） | 放行；检查表 4-③ 读数：文字定位 +1、兜底 0；报告头读数行含这两个数 | 走查（报告头读数 + 工具参数） |
| 22 | 边界 | 同会话 btest 开 → 发一条消息（卡投出，`D = 1`）→ 关 → 发一条消息（**中间有回合**：挂起中和行在这一回合投出，`D = 0`）→ 再开 → 再发一条消息 | 重进后重投一张卡，`D` 回到 1；宿主侧在模式内 ⇔ 模型侧读数 = 1 | `btest_card_test` |
| 23 | 边界 | 同会话 btest 开 → 发一条消息（卡投出，`D = 1`）→ 关 → 再开 → 发一条消息（**中间无回合**） | 挂起中和行**丢弃**（transcript 里 `[btest-mode-card-off v1]` 计数 = 0，不补投）；卡不重投，`D` 仍 = 1；宿主侧在模式内 ⇔ 模型侧读数 = 1，不出现"宿主已开、模型被告知已退出" | `btest_card_test` |
| 24 | 正常 | `btest.qaRoot` 未配 → `btest_run_start`（`repoRoot` = `C:\Users\\xinbo\repos\v2-booking`、`line` = 订舱） | 返回项 2 = `C:\Users\\xinbo\repos\qa\v2-booking\订舱.md`；目录已建；`qaRoot/.git` 已 init | `btest_expect_file_test` |
| 25 | 边界 | `btest.qaRoot` = `E:\qa` → 同上起 run | 返回项 2 = `E:\qa\v2-booking\订舱.md`；读 / 写都落该路径，派生规则不参与 | `btest_expect_file_test` |

## 8. 边界（本批不做）

- 不改外仓 `thincoder/`；不加 ACP 系统提示通道（二期）。
- 不改业务代码、不改数据库、不提交工单。
- 不改业务仓的设计档与冒烟清单：`expectFrom` 只读引用（档 + 节 / 清单行）；业务仓零写入，回写只落 QA 仓的预期文件（§3.4）。
- 不做截图证据；不做边走边停。
- 不自动创建业务数据（前置状态靠操作产生，或在文件里写清楚怎么建）。
- 不支持同一会话并行多条业务线的 run。
- 不在生产环境做写操作（用户未授权）。
- 不替代人工复验：报告是清单，不是结论。

## 9. UI / 交互决定（全部落地，无 open）

| 面 | 决定 |
|---|---|
| 模式入口 | composer 内核模式选择旁追加 `btest`，与 plan 同形；文案固定为 `btest`（不翻译） |
| 状态行 | btest 开启时 composer 顶部显示 `btest · <业务线> · 只读/写 · run <id>`；无 run 时显示 `btest · 待开始` |
| 拒绝展示 | 以步骤失败卡出现，正文含动作、host、规则与「设置 → 浏览器 → btest」入口 |
| 设置页 | 浏览器段新增两块列表（允许域名 / 生产域名）+ 默认只读开关 + **QA 根目录**（`btest.qaRoot`，文本输入，可空）；允许域名空 = 全部浏览器动作拒绝；生产域名空 = 写动作拒绝；QA 根目录空 = 按 §3.4 派生（`join(dirname(repoRoot), 'qa')`），填了非绝对路径 ⇒ 起 run 时拒绝并点名该设置项 |
| 报告 | 会话正文一张表 + 三尾注；表头上方一行操作真实性读数；无图片；不中途插入 |
| 退出 | 状态行消失；`D = 1` 时由下一个回合投出一行 `[btest-mode-card-off v1]` 中和语使卡失效（重进早于该回合 ⇒ 中和行丢弃，§3.2）；**再次切进 btest 时按 §3.2 判据**（`D = 0` ⇒ 重投一张卡；`D = 1` ⇒ 卡仍有效，不投）；run 未结束则下次进入先要求 `btest_run_end` 或作废 |

## 10. 未核实项与上抛项

1. **[上抛·待裁] 每次 run 起始的一行提醒**（"先读返回项 2 的绝对路径"）是否算"重复注入"。本设计按"不算"处理（它不是模式卡，约 2 行）；若要求严格零重复，改为不注入，代价 = 漂移兜底只剩 run 闸与 `btest_run_end` 检查表。
2. **自动放行应答点（已实读，2026-10-22）**：内核审批点 `_serverRequest`（`lib/kernel/thincoder/thincoder_kernel.dart:1040-1080`）**拿得到工具名**（`toolCall['title']`）、**拿不到结构化参数**（只有 `content` 预览文本）⇒ 它只负责在 btest on 时对 browser 组答 allow、压掉审批卡；
   放行 / 拒绝判据全部落在浏览器工具的 `run` 包装（`lib/browser/browser_tools.dart:115-130`，name + arguments 都在；§3.7 落点段）。
   **残余未核实**：内核是否对 MCP 工具发 `session/request_permission`（外仓 `thincoder/` 不在本机）。**两个分支下 btest 的读数相同**——发请求 ⇒ 钩子答 allow（零卡）；不发 ⇒ 无请求（零卡）。用例 #1 因此无条件成立；写动作的"禁止"不依赖这一层（规则 B 已在工具 `run` 层硬拒绝，§3.7）。
3. **unverified**：`HostMcpServer` 是否按会话暴露工具列表（决定 btest 工具会不会对普通会话可见）；实施前实读 `lib/host_tools/host_mcp_server.dart`。当前设计按"全局注册 + 会话级判据"处理，普通会话调用会被拒。
4. **unverified**：`git` 是否在 PATH 上（`git init` 依赖它）。失败路径已定（不阻断 run，返回一行 `未初始化 git，写入仍可，历史不可追`），因此不构成判据缺口。
5. **unverified**：业务仓 `v2-booking` 的 dev 域名与生产域名清单，由用户在设置页填；设计不写死域名。
6. **[上抛·知会] 拆分登记 SPLIT-1…5**（§4）：设计位无台账写权，登记行由主编排方落（挂 #149 的后续批）；本批不拆。
7. **unverified：强来源的覆盖率**——业务设计档里有多少节写的是期望行为而非实现方式，本轮未逐档核实。设计不假设覆盖率高：找不到强来源按 §3.4 硬规则 2 降级到「中」或标 `无权威来源`；首个 run 的「需要用户补规则的清单」就是覆盖率读数。
8. **[上抛·待裁] `browser_evaluate` 的 `readOnly` 参数**：既有只读轮规则写「带 `readOnly: true` 才放行」，而该工具的 schema 只有 `tabId` / `expression`（`lib/browser/browser_tools.dart:297-303`）——参数不存在，那条规则此前无法落地。本轮按「补参数」处理（§3.6 的参数表）。若主 agent 选「不补、只留写入形态检查」，只读轮与写轮对 evaluate 就同宽，F5 的「只读」在 evaluate 这一项上失去可判性。
9. **[上抛·待裁] 「按文字找不到可点目标」判不了**：宿主只看到调用参数，看不到那个元素当时有没有可见文字 ⇒ 替代 = ref / `selector` 兜底计数（§3.3 检查表 4-③）+ 报告步骤列写理由 + `browser_history` 的 clicks 对账（`lib/browser/browser_history.dart:537-547`）；代价 = 这条靠走查，不是硬闸。
