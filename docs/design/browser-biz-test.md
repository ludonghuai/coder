# 浏览器业务测试模式（browser-biz-test）设计档

> 板块：浏览器业务测试（宿主 overlay + 测试状态 + 预期文件）· 范围仓：baocode。
> 需求：`docs/requirements/browser-biz-test.md`（F1–F11 · F2.1 · F3.1 · F3.2 · §4 边界 · §5 验收 1–7）。
> 结构：本档覆盖设计档 8 项（做法与理由 / 接口契约 / 受影响文件 / 关键决策 / 验收回指 / 用例表 / 边界 / UI 决定），并含最近先例行与 survey 证据行。

## 1. 目标与范围

一句话：让 BaoCode 在 Chrome 上把一条航运业务线跑完整，判断依据（预期结果、case 来源）来自盘上的文件而不是模型记忆，一轮结束给一份可复验的问题清单。

范围内的十四行（`F7.1` 计入 `F7`）：

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
| F7 | 遍历策略 `chain`（能往下走就往下走）/ `surface`（按界面逐个摸完，直到本轮范围走完），run 参数，缺省 `surface` | §3.9 · §3.3 · §3.8 |
| F7.1 | 权重来自历史 issue 实测：一个 QA 根一份权重表，按缺陷密度排先后 | §3.9 |
| F8 | 待确认项只给建议、不改判定：run 后逐条研判，回填「建议」列 | §3.10 · §3.8 |
| F9 | 两个开关（遍历 / 写）：状态行点选、取值优先级；跨重启保留见 F11 | §9.1 · §3.3 |
| F10 | `chain` 断点可派只读子代理查明原因（`cause`）：上限 3 次/run，不可用降级 | §3.9 · §3.3 · §3.10 |
| F11 | 模式与两个开关跨重启：三个全局键 `btest.on` / `btest.traversal` / `btest.mode` 的读入与写回 | §9.1（持久化）· §3.1 · §3.3 |

范围外：见 §8。

## 2. 做法与理由

### 2.1 机制总览（七件事，缺一件就退化）

1. **模式是宿主 overlay**：`btest` 是会话级的一个开关，显示在内核模式旁边，但不发给内核（内核只认 `plan` / `normal`）。
2. **一轮测试是一个有头有尾的 run**：`btest_run_start` 开、`btest_run_end` 收；没有 run 的浏览器动作一律拒绝——这是"忘没忘纪律"的机械判据，不靠模型自觉。
3. **判断依据落盘**：预期文件（独立 QA 仓，路径见 §3.4）在 run 开始时由 `btest_run_start` 读出（索引 + hash + 绝对路径）、在 `btest_run_end` 之前写回；写失败进报告尾注，不静默。
4. **放行有边界**：域名白名单 + 生产禁写 + 只读轮动作面，三条都在宿主侧判；拒绝必须带原因（哪条规则、哪个 host、哪个动作）。
5. **操作路径是真的**：一轮只从 `startUrl` 进一次，之后靠点与打；按看得见的文字定位；写值只经真人与表单。路径用户走不到，测出来的结论就不成立——所以这一条与上面四条同级，落在工具面判据（§3.6）与报告读数（§3.8）上，不只在提示词里。
6. **遍历有方向**：一轮要么 `chain`（能往下走就往下走，走不动记断点、回头找别的路）要么 `surface`（把一个界面的页签 / 按钮 / 表单 / 筛选 / 列表底逐个摸完，就走到下一个界面继续，直到本轮声明的范围走完）；两种遍历共用一个权重表，按本工作区的历史缺陷密度排先后（§3.9）。这一轮选哪种由状态行的「遍历」开关给出（§9.1），模型显式传参时以参数为准（§3.3）。
   `chain` 走不动时当场派一个只读子代理查清原因、不等它继续走（§3.9，一次 run 最多 3 次）：回答在 run 内回来 ⇒ 写进断点的 `cause`；run 已结束 ⇒ 进收尾消息。
7. **待确认项只给建议**：弱 / 无来源的项在报告里永远标「待确认」；run 之后由会话主代理派只读子代理逐条给倾向、理由与优劣势，回填「建议」列——判定权在用户（§3.10）。

**注入通道的选择**（模式卡怎么到模型）：走 `KernelTurn.contexts` → `editorNote`，与用户消息拼成同一段 `text`（`lib/kernel/thincoder/thincoder_kernel.dart:674-678`），并随 `UserMessageItem.contexts` 进 transcript（`lib/kernel/thincoder/thincoder_kernel.dart:684-688`）。

为什么不选另外两条现成通道：

- **MCP `instructions`**：`HostTools.instruct` 把文本并进 MCP `initialize` 的 `instructions`（`lib/host_tools/host_tools.dart:134-138`、`:174-181`）。它只在 initialize 读一次、且按 feature 全局共享——无法"按会话、按切模式的那一刻"注入，也无法在切回 normal 时撤回。它只适合常驻规则（如现有浏览器爬取禁令 `lib/browser/browser_tools.dart:183-184`），不适合模式卡。
- **Claude Code 的 append-system-prompt**：Claude 侧有（`lib/kernel/claude_code/claude_code_transport.dart:285-287`），thincoder 侧没有；要加就得改外仓 `thincoder/`（本批已定不做）。

### 2.2 最近先例（对齐 ∥ 偏离及理由）

先例三坐标：

- 实现坐标：模式选项源 `lib/kernel/thincoder/thincoder_choices.dart:7-11`；composer 选项渲染 `lib/chat/composer/composer.dart:1953-2079`（`_buildToolbar`），选项控件 `lib/chat/composer/composer_picker.dart:33`（`ComposerPicker`）。
  浏览器设置段 `lib/settings/pages/browser_page.dart`；宿主工具注册与分组 `lib/browser/browser_tools.dart:92-134`。
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
- 外网公开资料：本批未取用——机制全部落在本仓既有通道（turn contexts / HostTool / KernelChoice / 文件工具）上，没有新协议或新 API 需要外部核对。

## 3. 接口契约

### 3.1 模式状态（宿主侧）

| 项 | 决定 |
|---|---|
| 存储 | 当前值 = 会话状态 `BtestState.on`（`lib/chat/chat_session.dart:156-162`）；跨重启落全局设置 `btest.on`（`settings.json`）：会话打开时读入、切换时写回（§9.1「持久化」，F11） |
| 不发内核 | `_applyStartMode` 只认 `plan` / `normal`（`lib/kernel/thincoder/thincoder_kernel.dart:463-467`），多余键不会被误发 |
| 显示 | composer 的 kernel 选项区（`lib/chat/composer/composer.dart:1953-2079` 的 `_buildToolbar`，选项由 `ComposerPicker` 渲染，`lib/chat/composer/composer_picker.dart:33`）追加一项 `btest`，与 plan 同形 |
| 两个 run 参数开关 | 遍历（`深度` / `广度`）与写（`只读` / `允许写`）的**当前值**存会话状态——字段落 `BtestState`（`lib/browser/btest/btest_mode.dart:221`，`_traversal` / `_write` 在 `:232-236`；写字段可空 = 未点选，规则见 §9.1「写初始」），`lib/chat/chat_session.dart` 只加访问器（`setBtest` 旁，`:190-214`）；**改值时写回全局设置，读取不写任何键**（`btest.on` / `btest.traversal` / `btest.mode`，§9.1「持久化」，F11）；控件的形态 / 位置 / 文案见 §9.1，取值优先级见 §3.3 字段表后一段 |
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
- **卡的内容边界**：角色、八条稳定性纪律（`[D1]`–`[D8]`；`[D7]` = 操作真实：入口一次、文字定位、逐字键入、读不推进流程）、七条判定口径（`[J1]`–`[J7]`）、需求 §7 的 19 类问题域各一条检查动作（`[P01]`–`[P19]`）+ 一条权重顺序（`[P20]`）、三条硬纪律（`[H1]`–`[H3]`）、两个开关的选项名 ↔ run 取值映射（`深度` = `chain` / `广度` = `surface` / `只读` = `readonly` / `允许写` = `write`）、差异处置四步、报告口径、禁止项、跑前必读。
- 卡正文 4624 字符（2026-10-23 实测；其中 36 个标签行共 3477 字符），落 `lib/browser/btest/btest_card.dart`（版本化、可 diff），不写进用户家目录。标签是 F2 第二条判据的机械锚点（§6）。
- **`[D8]` / `[P20]` 与报告口径要落的内容（清单；正文在 `btest_card.dart`）**：
  - `[D8]` 遍历纪律：`chain` =「只要有下一步就走下一步，先问这里还能往哪走，能走就走，走不动记一条断点（门控 / 无权限 / 数据不足 / 没有下一步）再回头找别的路」；`surface` =「把一个界面的每个东西摸完——每个页签、每个按钮、每个表单、每个筛选、列表滚到底——然后走到下一个界面继续，按界面逐个覆盖，直到本轮声明的范围走完；范围内没摸到的界面 / 分支记进 `uncovered`」；提交类动作之后必查刷新丢失 / 金额勾稽 / 重复提交。
  - `[P20]` 权重顺序：读 run 返回的权重表；`surface` 按条数降序摸，`已修` 的类排末尾仍摸一次；只追加「已修 / 已复现」标记，不删类目、不改条数。
  - 报告首行：操作真实性读数前加 `traversal=<chain|surface>`。
  - 报告表格：加「判定」（`预期不符` / `待确认`）与「建议」两列；run 只写判定，建议由 run 之后的研判回填（§3.10）。
- **漂移的第二个兜底**：`btest_run_end` 的返回带收尾检查表（五项机械读数：写回 hash、尾注与断点键存在性、覆盖对账、操作真实性读数、权重表类目齐，§3.3），缺项直接点名字段——把"忘了"变成一次显式点名。

### 3.3 一轮测试的边界：run

`btest_run_start`（宿主工具，仅 btest 开启时注册）：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `line` | string | 是 | 业务线名，如「订舱」；预期文件名就是它（`<业务线>.md`） |
| `repoRoot` | string | 是 | **业务仓根绝对路径**（如 `D:\repos\v2-booking`）；宿主校验目录存在且含 `.git`，否则字段级拒绝。本 run 只从它跑 `git log`（判 `source`）并派生 `qaRoot`（§3.4）——**业务仓零写入** |
| `startUrl` | string | 是 | **本轮唯一入口 URL**（绝对 http(s)）；首次入口动作必须等它（去尾斜杠比较），不等即拒（§3.6.2） |
| `env` | enum | 是 | `dev` / `test` / `prod`；**写动作的总闸**（§3.7 规则 A / B） |
| `mode` | enum | 否 | `readonly` / `write`；**缺省来源 = 会话「写」开关，再退设置 `btest.readonly`**（§9.1；优先级见本表后一段）。**规则 A 判优先级定值后的 `mode`**（缺省解析完成再判）：`env: prod` ∧ 定值后 = `write` ⇒ 起 run 即拒，不论 write 来自参数还是开关（§3.7） |
| `traversal` | enum | 否 | `chain`（能往下走就往下走）/ `surface`（按界面逐个摸完，直到本轮范围走完）；**缺省来源 = 会话「遍历」开关，再退内置 `surface`**（§9.1；优先级见本表后一段）；非法值 ⇒ 字段级拒绝并点名 `traversal`（§3.9） |
| `commitRange` | string | 是 | 本轮变更范围（`git -C <repoRoot> log --oneline -30` 的区间/摘要） |

`repo`（业务仓名）不再作为入参：显示名由 `repoRoot` 的末段派生（`v2-booking`），避开"一个仓名两处来源"。

`expectFile` 也不作入参：它要表达的只是业务线名（= `line`），预期文件的文件名与路径全由宿主按 §3.4 派生；`expectFile` 只作为这个文件在宿主内部的叫法保留（检查表的 `expectFile: written` 即此）。落点因此不依赖调用方每次传对相对路径。

`startUrl` 是入口 URL 的唯一权威；预期文件头的「起点」是它的记录副本，写回时以 `startUrl` 为准（不一致改文件，不改判据）。

**两个可选参数的取值优先级（写死）**：**显式参数 > 会话开关 > 设置缺省**。开关的初值在会话打开时由全局设置给出：遍历 = `btest.traversal`（键不存在 ⇒ `广度`）；写 = `btest.mode`（键不存在 ⇒ **开关未点选**，取值时解析 `btest.readonly`：true ⇒ `只读` / false ⇒ `允许写`——「未点选」的完整规则只写在 §9.1「写初始」一处，本段引用）；第三档只在开关未点选时兜底，保证任何时刻都有一个值。三档各一个读数例（返回项 1 与报告首行都可见，§3.8）：

| 档 | 现场 | 读数 |
|---|---|---|
| ① 显式参数 | 遍历开关 = `广度`，调用带 `traversal: chain` | `traversal=chain`——参数压过开关；开关当前值不变 |
| ② 会话开关 | 遍历开关 = `深度`，调用不带 `traversal` | `traversal=chain` |
| ③ 设置缺省 | `btest.mode` 键不存在 ⇒ 写开关未点选（§9.1）；调用不带 `mode` | 按 §9.1 解析 `btest.readonly`：true ⇒ `mode=readonly`，`browser_click` 被拒并点名 `mode: readonly`；同一现场把「默认只读」关掉（`btest.readonly` = false）⇒ `mode=write`，`browser_click` 放行 |

返回（**六处，缺一即实现不全**）：

1. `runId` + 本轮的 `traversal`（`chain` / `surface`）与 `mode`（`readonly` / `write`，已按上面的优先级定值）——报告首行据此回显（§3.8）；
2. **预期文件的绝对路径**（解析后）：`<qaRoot>/<仓名>/<业务线>.md` + **来源标记**（`设置值` / `工作区根` / `父目录兜底`）+ **降级原因**（`父目录兜底` 时必带，取值见 §3.4 分支 3 / 4——分支 3 与分支 4 因此在返回里可分辨）；用户据此当场核对落点、看出它按哪条分支算的，不对就配 `btest.qaRoot` 覆盖后重跑（§3.4）；
3. **case 索引**：本次预期文件里全部 `## CASE-` 的 ID 与标题（read 结果随回合进上下文——"跑前必读"从此有机械判据，不靠模型自觉）；
4. **内容 hash**：预期文件此刻的 SHA-256（文件不存在 ⇒ `absent`），**同时作为写回基线**（§3.4）；
5. 一行纪律（读文件 / 不边走边停 / 三尾注）；
6. **权重表**：`<qaRoot>/weights.md` 的绝对路径 + 来源（`file` = 本轮用的就是盘上这份，含首建刚落盘的那份 / `built-in` = 文件读不出或写不出、退回内置默认八类）+ **生效序一行**：按「条数」降序、「`已修` 的类整类排到末尾（仍在序中）」之后的实际顺序逐类写名；文件里多于八类（人加的类目）时**一并按条数参与排序**，不只排八类（§3.9）；`built-in` 时带一行 warning。

`btest_run_end` 接收**结构化载荷**（不是一段自然语言摘要，字段存在性由宿主判）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `runId` | string | 本 run |
| `coveredCases` | string[] | 本轮实际覆盖的 case ID（与 run_start 索引对账） |
| `issues` | object[] | 每条：`caseId` / `step` / `symptom` / `evidence{kind,readout}` / `severity` / `pre` / `expectRef` / `detour`（可空；绕道而来的问题行必填，值 = §3.6.2 的 `detour` 原文） |
| `blockers` | object[] | 每条：`step` / `reason`（被 btest 拒绝的动作与规则原文进 `reason`） |
| `unconfirmedDiffs` | object[] | 每条：`kind`（`diff` = 两次结果不一致；`pending` = `expectFrom` 弱 / 无来源、待用户判定）/ `caseId` / `step` / `symptom` / `evidence{kind,readout}`（`pending`）/ `runs`（`diff`）/ `expectRef` |
| `uncovered` | object[] | 每条：`branch` / `why`（`surface` 轮 = **本轮范围内没摸到的界面 / 分支**，不是单个控件；一个界面摸完走到下一个，直到范围走完） |
| `chainBreaks` | object[] | 每条：`path`（一路怎么走过来的）/ `at`（走到哪一步走不动）/ `reason`（`门控` / `无权限` / `数据不足` / `没有下一步`）/ `verified`（断点前已验什么）/ `cause`（**可空**：一句结论 + 一处 `file:line` 或文档节，由 run 内派出的只读子代理给出，§3.9；缺省 = 没派 / 未查明）；`traversal: chain` 时必带（可为空数组） |
| `noVisibleText` | object[] | 每条：`step` / `element`（按可见文字 / label / 角色找不到可点目标、只能靠 `ref`·`selector` 兜底的那一步）；检查表 4-③ 数的就是它 |

返回收尾检查表（**五项，全是机械读数**，不看模型措辞）：

1. **预期文件写回**：`expectFile` 当前 hash ≠ run_start 基线 ⇒ `written`；相等 ⇒ `not written`；基线 `absent` 且现在存在 ⇒ `created`。
2. **尾注与断点键存在性**：`blockers` / `unconfirmedDiffs` / `uncovered` 三个键都在（可为空数组，但键必须在）；`traversal: chain` 时 `chainBreaks` 键也在，每条 `path` / `at` / `reason` / `verified` 非空且 `reason` 取四值之一；`cause` 可缺省，出现时须为非空字符串（**只验形状，内容真不真由走查**，§3.9）；缺键 / 缺字段 / 取值非法 ⇒ 点名。
3. **覆盖对账**：`coveredCases` 里每个 ID 都在 run_start 索引中；`issues[].caseId` 与 `expectRef` 都非空且能指到索引里的 case；`unconfirmedDiffs[]` 每条 `caseId` 非空、`kind` 取 `diff` / `pending`。
4. **操作真实性读数**（宿主自己数，落 run 状态——新增 `lib/browser/btest/btest_mode.dart`，run 结束归零）：
   - ① **入口动作数** = 1，且首次 url = `startUrl`；0 ⇒ `入口=0`（本轮不是从声明的起点进入）；≥2 的已被拒，**被拒入口次数单列**并进报告头读数（§3.8）。
   - ② **写值与绕接口两项计数**：`browser_evaluate` 写值被拒次数（放行写值恒 = 0，工具 `run` 层拒绝）；`browser_request` 的 `replay` 放行次数（恒 = 0）与被拒次数。任一被拒 > 0 ⇒ 点名（这是「试图用脚本改值 / 试图绕表单调接口」的读数，不是通过项）。
   - ③ **目标形态计数**：文字定位 a 次 / `ref`·`selector` 兜底 b 次（`browser_click` / `browser_type` / `browser_act` 的 click·type 步，按调用参数数）；**对账：b = `noVisibleText[]` 条数 = 报告里「无可见文字」行数**，不等 ⇒ 点名差额。
   - ④ **绕道对账**：`detours[]` 条数 = `issues[].detour` 非空条数；不等 ⇒ 点名差额。
5. **权重表**：`<qaRoot>/weights.md` 在盘且八个类目齐；文件不存在 ⇒ 宿主首建、来源 `file`、不 warning；读不出 / 写不出 ⇒ `built-in` + warning；缺类目 ⇒ 点名缺的类（「不得删类目」的机械读数）；`已修：<类>` 标记行按 §3.9 逐字匹配，匹配不上 ⇒ 一行 warning 点名该标记行（不阻断）。

缺项返回 `warning` 行，不阻断结束——该行同时写进报告头，用户看得见。

**顺序钉死**：AI 必须**先完成预期文件写回，再调 `btest_run_end`**；`btest_run_end` 只校验与收尾，不替 AI 写文件。反过来（先 run_end 再写回）会让检查表第 1 项恒为 `not written`，机械读数退化成常量告警（§3.4 · 用例 #2）。

判据：**任何浏览器工具调用**都需要活动 run（只读动作也计入，这样业务线、环境、预期文件三者始终有出处）；run 结束后旧 `runId` 失效，下一次动作先报错再要求新 run。

### 3.4 预期文件：位置、格式与写法

位置：**独立 QA 仓**（普通目录，不是 git 仓），不写业务仓。**一个工作区只有一个 QA 根**——同一会话工作区下，业务仓是直接子目录还是嵌套几层，都解析到同一个 `<会话工作区根>/qa`。

**工作区根从哪取**：`HostToolCall.cwd`（`lib/host_tools/host_tools.dart:14-24`，注释即「agent 的工作目录（其项目路径，workspace 所见）」）。
btest 所在的 thincoder 路径**会填这个值**（2026-10-23 实读）：`lib/kernel/thincoder/thincoder_kernel.dart:353` 发放 grant（`HostMcpServer.issue(_sessionId ?? '', _cwd)`），`:231` 取值 `_cwd = _context.cwd ?? _context.resume?.cwd ?? '.'`。
`lib/host_tools/host_mcp_server.dart:186` 构造调用（`HostToolCall(cwd: grant.cwd, sessionId: grant.sessionId)`）；`issue` 把入参 `cwd` 存进 `_Grant`（`host_mcp_server.dart:112`）。
ACP 分支同理由 `grant.cwd` 填入；Claude Code 控制通道由 `_cwd` 填入（`lib/kernel/claude_code/claude_code_kernel.dart:1766-1767`）。⇒ 分支 2 / 3 可达。

**链尾是 `'.'`**：未配 `btest.qaRoot` 时，`_cwd` 的兜底值不是绝对路径 ⇒ **工作区根不可得**。此时不把 `'.'` 解析成任何相对落点，直接落分支 4，并在返回项 2 的「降级原因」里点名 `工作区根不可得`——用户看得见降级，不会误以为按工作区根算过。

工作区侧同一文件夹的两个面：`Project.path`（`cwd` 即它，`lib/workspace/workspace.dart:2580`）与 `Project.root`（`lib/workspace/workspace.dart:61`，去掉远端 host 前缀后的路径段）。设计以 `HostToolCall.cwd` 为准——它在工具调用里现成可用。

多根工作区里 `cwd` 与项目列出的其它根可能不同——**不猜「哪个根才是工作区」**：会话 `cwd` 就是本 run 的工作区根；套不上分支 2 / 3 ⇒ 走分支 4 兜底并在返回里说明。

派生顺序（写死，四条分支，命中即止；比较前统一分隔符与大小写；**包含判断按路径段比较**，见分支 2）：

1. `btest.qaRoot` 有值 ⇒ `qaRoot` = 该值；配的值必须是绝对路径，否则 `btest_run_start` 拒绝并点名该设置项。配的值落在 `repoRoot` 之内 ⇒ 照用，但返回项 2 的「降级原因」点名 `QA 根在业务仓内`（此时「业务仓零写入」不成立，§6 F3.2 ④）。来源 = `设置值`。
2. 未配，且 `repoRoot` 是**会话工作区根** `W` 的**严格后代**（`repoRoot` = `W` + 一个分隔符 + 其余段，且段数 > `W` 的段数；嵌套任意层）⇒ `qaRoot = join(W, 'qa')`。**包含关系按路径段比较**，不是裸字符串前缀：`C:\Users\\xinbo\repos2\v2-booking` 的段序里没有 `repos` 这一段 ⇒ **不**算在 `C:\Users\\xinbo\repos` 之下。来源 = `工作区根`。
3. 未配，且**会话工作区根就是 `repoRoot` 本身**（`cwd == repoRoot`，深度 0——分支 2 的「严格后代」不含它）⇒ `qaRoot = join(dirname(repoRoot), 'qa')`：工作区根就在业务仓里，`<工作区根>/qa` 会写进业务仓——退到父目录，守住「业务仓零写入」。来源 = `父目录兜底`，降级原因 = `工作区根即业务仓`。
4. 其余（套不上分支 2 / 3：`cwd` 非绝对路径 ⇒ 工作区根不可得 / 是远端位置 / `repoRoot` 在工作区根之外）⇒ 同分支 3 的算式。来源 = `父目录兜底`，降级原因按实际写死一条：`工作区根不可得` / `工作区根是远端位置` / `仓在工作区根之外`（进返回项 2 的字段，§3.3）。

预期文件 = `join(qaRoot, basename(repoRoot), '<业务线>.md')`。

**「一个工作区一个 QA 根」的判据**：未配 `btest.qaRoot` 时，同一会话工作区根 `W` 下任意两个 `repoRoot`（都命中分支 2）⇒ 算出的两个 `qaRoot` 逐字相等，都 = `join(W, 'qa')`；嵌套深度不影响结果（§7 #26）。

实例（**含嵌套用例**：同一工作区、两个不同深度的仓 ⇒ 同一个 `qaRoot`）：

| 会话工作区根 | `repoRoot` | `qaRoot` | 预期文件 |
|---|---|---|---|
| `C:\Users\\xinbo\repos` | `C:\Users\\xinbo\repos\v2-booking` | `C:\Users\\xinbo\repos\qa` | `repos\qa\v2-booking\订舱.md` |
| `C:\Users\\xinbo\repos` | `C:\Users\\xinbo\repos\clientA\v2-timecharter` | **`C:\Users\\xinbo\repos\qa`（同一个）** | `repos\qa\v2-timecharter\船期.md` |
| `D:\work\客户A` | `D:\work\客户A\repos\v2-booking` | `D:\work\客户A\qa` | `客户A\qa\v2-booking\订舱.md` |
| `C:\Users\\xinbo\repos\v2-booking`（工作区就是仓本身） | 同左 | `C:\Users\\xinbo\repos\qa` | `repos\qa\v2-booking\订舱.md` |

边界照规则走，不发明例外：`repoRoot` 直接在盘符根（`D:\v2-booking`）⇒ `qaRoot = D:\qa`（工作区根是 `D:\` 走分支 2；取不到走分支 4，两分支同解）。派生结果与来源标记写在 `btest_run_start` 的返回项 2（§3.3），用户看到不对就用 `btest.qaRoot` 覆盖后重跑。多个工作区共用一个 `qaRoot` 时按 `basename(repoRoot)` 分子目录，互不串；同一 `qaRoot` 下同名的业务仓视为同一个仓，共用一个预期文件。

为什么放独立 QA 仓（三条）：① **业务仓零写入**——本 run 对业务仓只读（`git log` 判 `source`），预期文件不进业务仓的改动面；② **盘上文件可 diff 可回看**——两次 run 的预期变化就是同一个文件的两版差异，人和 AI 都能直接比对；③ **不随 session 删除**——放宿主数据目录则 session 一删预期即失，等于回到"凭记忆判断"，正是本功能要消灭的。

**目录（在 `btest_run_start` 内）**：

- **建目录**：`Directory(join(qaRoot, basename(repoRoot))).createSync(recursive: true)`（连 `qaRoot` 一起建）；建不出来 ⇒ 拒绝起 run，文本点名路径与错误（§7 #28）。
- **不是 git 仓**：`qaRoot` 下不建 `.git`、不做仓库初始化（需求 F3.2）；也不写业务仓、不改业务仓的 `.gitignore`。

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
3. 同样步骤重跑一次（同一操作最多总共做 2 次，不反复点）。
4. 仍不同 ⇒ 报告尾注「待确认差异」，附三次的步骤与状态；一致 ⇒ 记为「环境问题」，把前置差异写回该 case 的 `pre`。

### 3.6 工具面：操作真实性（所有轮次）∥ 只读轮 ∥ 写轮

先定一条事实：**文字定位不需要新工具**。`browser_click` 的描述已写明 `by ref or by its words (text, with role and near to tell it from others alike)`（`lib/browser/browser_actions.dart:126-129`），`browser_type` 的输入面同样有「字段的话」形态（`lib/browser/browser_actions.dart:146-156`）。本批不改这两个工具的协议，只把「首选 / 兜底 / 禁止」定死，并在宿主侧数出来。

**定位规则三行（所有轮次）**：

- **首选**：可见文字——按钮文字、字段 label、表头列名、可见角色（`text` / `into` 加 `role` / `near`）。
- **兜底**：`ref`（或 `selector`）仅当该元素**没有可见文字**时使用，例如纯图标按钮；每次兜底在报告步骤列写「无可见文字：<元素描述>」，次数由检查表 4-③ 数出来（§3.3）。
- **禁止**：以 DOM id / class / xpath / 快照编号作为首选定位。更硬的一条：元素**有**可见文字却按文字找不到或点不动，那是缺陷（label 未关联 / 可访问性缺失），记入报告，不得改用 `ref` 或 id 绕过（F2.1 ③）。

本批对工具协议只加两个可选参数：

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

- **规则 A（起 run 即拒；判优先级定值后的 `mode`）**：`btest_run_start` 先按 §3.3 的优先级把 `mode` 定值（缺省解析完成），再判：`env: prod` ∧ 定值后的 `mode = write` ⇒ **拒绝起 run**，文本点名 `env: prod` 与 `mode: write`（来自缺省时注明「由写开关 / 设置得来」）。
  理由：需求边界"不在生产环境做写操作"是授权问题，不是域名判断问题——不能等第一个写动作才拦；只判字面参数会被「`env: prod` + 省掉 `mode` + 写开关 = `允许写`」绕过，起出一个 `mode=write` 的生产 run。
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
| `env: prod` + 定值后 `mode: write` 起 run（含不带 `mode`、写开关 = `允许写` 的定值形态） | **拒绝起 run**（规则 A），文本点名两项 |
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

| # | 业务线 | case | source | 步骤 | 现象 | 证据 | 严重度 | 判定 | 复现前置 | 预期出处（`expectFrom` 原文） | 绕道 | 建议 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 订舱 | CASE-BKG-001 | old | 提单号填完点保存 | 提示保存成功但列表无新单 | POST /api/booking 200 · code=0 · data.id="" ；console 无 error；列表未刷新 | 高 | 预期不符 | 新用户 / 空草稿 | 强 · <业务仓>/docs/<档>.md §3.1 | — | — |
| 2 | 订舱 | CASE-BKG-004 | old | 审核页点「放单」 | 提示已放单，单据状态仍为待放单 | 列表状态列 = 待放单；POST /api/release 200 · code=0 | — | 待确认 | 同上 | 弱 · <业务仓>/lib/booking/release.dart:88 | — | 可能有问题 · 理由：<file:line 或文档节> · 误判代价：<…> / 漏判代价：<…> |

**报告头一行读数**（`traversal` 取 run 的返回值、操作真实性取 `btest_run_end` 检查表第 4 项，原样贴出、不自报）：

```text
traversal=surface · mode=write · 操作真实性：入口=1（navigate=1 · open=0 · 被拒=0）· evaluate 写值被拒=0 · replay 放行=0/被拒=0 · 文字定位=41 · ref/selector 兜底=1 · 无可见文字=1 · 绕道=1
```

**「判定」列**：`预期不符`（有强 / 中来源支撑，进载荷 `issues[]`）或 `待确认`（`expectFrom` 弱 / 无来源，进 `unconfirmedDiffs[]` 的 `kind: pending`）。`待确认` 行的严重度列写 `—`——严重度只在判定成立后才有意义；判定权在用户（§3.10）。

**「建议」列**：`预期不符` 行写 `—`；`待确认` 行的建议由 run 之后的研判回填，形如 `倾向 · 理由 · 优劣势`（§3.10）。研判不可用 ⇒ `待研判 · <原因>`。

**「绕道」列**：非空 = 该步用户本人也做不完整，形如 `绕道：<缺什么> · 第 2 次入口`；每次绕道单独一行（同一缺陷再次绕道写「同上（第 2 次绕道）」，严重度不重复计），行数与 run 状态的 `detours[]` **一一对应**——检查表 4-④ 数的就是它。

**证据定义**（可复核 = 别人照着能重读一次）：接口方法 + 路径 + 状态码 + 关键响应字段；console 原文一行；字段前后值；页面提示原文。截图不计入证据。每条「预期不符」必须能指到预期文件的某条 case（预期文件的绝对路径 + `#CASE-…`，路径见 §3.4），指不到 ⇒ 进「待确认差异」。「预期出处」列写该 case 的 `expectFrom` 原文（级别 + 引用）；级别为「弱」或 `无权威来源` 的 case 不产生「预期不符」——表内标 `判定=待确认`（严重度 `—`），并发进「待确认差异」的「需要用户补规则的清单」。

**严重度**：高 = 主流程断（不能提交 / 数据错 / 金额错）；中 = 局部功能不可用或体验断裂；低 = 文案 / 样式 / 边缘。

**三类尾注**（缺一不可）：

1. **阻塞**：本步做不下去，附原因（含被 btest 拒绝的动作与规则）。
2. **待确认差异**：`kind: diff` = 两次或三次结果不一致、尚未定性，附步骤与状态；`kind: pending` = `expectFrom` 弱 / `无权威来源` 的项（表内 `判定=待确认`）。本尾注下单列一块 **「需要用户补规则的清单」**：每条 case ID + 缺的是哪条业务规则（一句话）；用户补规则后，下一轮写回 `expectFrom`。
3. **本轮未覆盖**：哪些界面 / 分支没跑到、为什么（缺账号 / 缺数据 / 被生产禁写挡住等）；`surface` 轮按界面 / 分支逐项点名（列的是范围内没摸到的界面 / 分支，不是单个控件）；`chain` 轮在本尾注下另起一块 **「链断点」**：每条 `path` / `at` / `reason` / `verified`，有 `cause` 时一并列出（§3.3 `chainBreaks`）。

不截图；不边走边停——问题记录后继续，除非整轮无法继续（此时进「阻塞」并结束）。

### 3.9 遍历策略：`chain` / `surface`（F7）与权重表（F7.1）

**参数**：`btest_run_start` 增 `traversal`（string，可缺省）：`chain` = 深度优先；`surface` = 广度优先。**缺省来源 = 会话「遍历」开关，再退内置 `surface`**（开关初始 = `广度`，既有 run 的行为不变；优先级见 §3.3）。非法值 ⇒ 拒绝起 run，文本点名 `traversal` 与两个合法值（§7 #32）。取值随返回项 1 与报告首行（§3.8）可见。

**两者对比**：`chain` 沿一条业务线往深走（能走就走，走不动记断点）；`surface` 按界面一个个铺开（一个界面摸完再走下一个，直到本轮范围走完）。

**`chain`：只要有下一步就走下一步**。每到一个界面，先问「这里还能往哪走」——能走就走，一直走到走不动为止。

- 走不动（门控 / 无权限 / 数据不足 / 没有下一步）⇒ 记一条断点（§3.3 `chainBreaks`），**回头找别的路继续**，不停轮（守 `[D5]`）；断点时可派只读子代理查明原因（见下「断点查明」）。
- 断点不是失败：不进 `issues[]`、不计严重度；报告在「本轮未覆盖」的「链断点」块里逐条列（§3.8）。
- 只读轮里能走的下一步少（写动作被策略闸拒）⇒ 断点原因记 `门控`，run 继续。

**断点查明：派只读子代理（F10）**

- **触发**：只在**断点发生的那一刻**派，不是每步派。断点是唯一需要「为什么走不动」这个答案的地方；每步都派会在一轮里堆出几十个子代理，稀释研判、白花成本。
- **谁去**：只读子代理 `explore`（既有件：`thincoder-core/agent-tools/subagent.mjs:144` 的 `role` 枚举含 `explore`；只读子集 `thincoder-core/agent-tools/subagent-spawn.mjs:248-250`）。派发入口是模型侧的 `subagent` 工具调用（`action:"spawn"` + `role:"explore"`），**不是宿主 API**——宿主不派子代理、不改判定。
- **派发方式 = 异步派、发现即派、不等待**：按上一条的模型侧 `subagent` 调用**异步**派出——depth 0 默认异步（`thincoder-core/agent-tools/subagent.mjs:235` 取值 `args.async ?? ((ctx.depth ?? 0) === 0)`）：调用立刻返回，主代理继续往下走，报告稍后自己到达。
  - **发现即派**：走到一个断点就派一个，**不等它的答案**，当场继续走下一步；派出去就继续走，等待才会把一轮拖成串行（用户 2026-10-23 19:07 原话：「主代理发现一个，就派一个先出去，否则等主代理都走完慢死了」）。
  - **主 agent 不因断点停下**：派完继续走；异步派发不等于结束回合，回合只在主代理手上没活时才收尾。
  - **答案落地时机**：报告回来时 **run 未结束 ⇒ 补进该断点的 `cause`**；**run 已结束 ⇒ 结论进收尾消息**，不重开 run、不阻塞。`cause` 保持可空（§3.3 原样）：没等到就是没有这条键，迟到的报告不破坏字段形。
- **任务书**：业务仓 `repoRoot` 绝对路径 + 断点现场（`path` / `at` / `reason`），要求一句结论 + 一处 `file:line`（或文档节）。
- **产出落哪**：写进该断点的 `cause`（可空字段，§3.3）；**`reason` 仍是四值枚举**（门控 / 无权限 / 数据不足 / 没有下一步）——子代理只回答「为什么」，不改 `reason` / `at` / `verified`，也不改任何判定。
- **上限 = 一次 run 最多 3 次**：每个断点都是一次独立子代理运行（各自读仓、各自出结论），不设上限会让一轮堆出几十个子代理、把研判成本与注意力耗在同一轮的断点上。第 4 个及以后的断点不派，`cause = 未查明（达到本轮研判上限）`，run 照常继续。
- **不可用降级**：`explore` 未装配 ⇒ 试 `plan`（同为只读角色，`subagent-spawn.mjs:248` 同判）；两者都不可用或 spawn 失败 ⇒ `cause = 未查明（<原因>）`，run 不因此重开、不停。`cause` 缺省也合法——它是可空字段，不是新闸门。
- **边界**：子代理不碰浏览器工具（MCP 工具硬编码非只读，§3.10 实读），不改预期文件、不写报告、不改判定；结论真不真宿主判不了，属走查面（见下表）。

**卡 `[D8]` 的替换句（逐字，实施照抄）**：替换 `[D8]` 里以 `A chain break may be sent to a read-only subagent` 开头的那一句（卡文本在 `lib/browser/btest/btest_card.dart:39`，同一句以 `reason stays one of the four.` 结尾；其后自 `At most 3 per run` 起的部分——上限 / 降级 / 不进 F8 三项——保留不动），新句为：

```text
A chain break may be sent to a read-only subagent (explore, else plan): the moment a break is recorded, send one and keep walking — never wait for its answer; it reads the repository and answers why in one line plus one file:line. An answer that arrives before the run ends goes into that break's cause; an answer that arrives after the run has ended goes into your closing message — do not reopen the run or block on it, and a late answer simply leaves cause absent. reason stays one of the four.
```

**`surface`：把一个界面的每个东西摸完，再走到下一个界面继续，直到本轮声明的范围走完**。功能面 = 页签 / 按钮 / 表单 / 筛选 / 列表底；不设「只在一个页面」的上限（用户 2026-10-23 03:59 原话：「广度测试并不局限与某一页面，只是这个界面探索完了，再往后走」，需求 F7.2）。

- 面**从当前 DOM 快照枚举**（`browser_snapshot` / `browser_inspect` 的当次读数），不凭记忆列、不照上一轮清单抄；每个界面各枚举一次。
- 一个界面的面摸完 ⇒ 走到下一个界面继续，直到本轮声明的范围走完才收工。
- 摸过的算覆盖（各有读数与证据）；**没摸到的进「本轮未覆盖」（`uncovered`），按界面 / 分支逐项点名**——列的是范围内没走到的界面或分支，不是单个控件。

**每一步的判定照常**：两种遍历都一样，走每一步都按 `[J1]`–`[J7]` 判（预期来源 / 成功提示 / 首开 / 绑定值 / 报错 / 数字 / 角色）。

**提交类动作之后必查三项**（两种遍历都适用；触发条件是动作类型，不是流转次数）：每次提交 / 保存 / 审核 / 放单这类动作之后，必查——

| 项 | 依据（F7.1 实测条数） | 检查点 |
|---|---|---|
| 刷新丢失 | 刷新 / 数据丢失 58 | `[P10]` · `[P05]` |
| 金额勾稽 | 金额 / 数字 31 | `[P04]` · `[J6]` |
| 重复提交 | 重复提交 20 | `[P06]` · `[J2]` |

三项各要一次读数（值 / 原文 / 前后值），不是"看起来对"。

**两种遍历的判定层**（宿主能判什么，判不了什么）：

| 判据 | 宿主能判吗 | 落点 |
|---|---|---|
| `traversal` 取值合法 / 缺省值 | 能 | §3.3 字段校验 · §7 #32 |
| `chainBreaks` 键在、四字段非空、`reason` 取四值之一（chain 轮）；`cause` 可缺省 | 能 | §3.3 检查表第 2 项 |
| 断点内容真不真（走到哪、为什么走不动） | 判不了 | 报告「链断点」块 · 走查 |
| 面是否从当次快照枚举 | 判不了 | 报告「本轮未覆盖」· 走查 |
| 「提交类动作」识别 | 半能判：工具名 + 参数可数（点击提交按钮 / 表单保存） | 报告证据列 · 走查 |
| 断点 `cause` 真不真 / 子代理派没派 | 判不了 | 报告「链断点」块 · 走查 |

#### 权重表：`<qaRoot>/weights.md`（F7.1）

一个 QA 根一份，不是每仓一份（同一工作区的仓共用一份，密度的实测来源只有一个）。路径 = `<qaRoot>/weights.md`，与预期文件同一个派生根（§3.4）。

宿主在 `btest_run_start` 里首建：文件不存在 ⇒ 按内置默认八类写盘，**写成功即本轮来源**（返回项 6 标 `file`、不出 warning——首次与被删后重建是同一个读数）；写不出来 ⇒ 用内置默认八类照跑，返回项 6 标 `built-in` + 一行 warning（不阻断 run）。内容 = 类目 × 实测条数 × 映射的检查点：

```markdown
# btest 权重表（历史缺陷密度）

> 由来：51marine-issue-audit-20261021/issues-v2dev.json（聚类样本 924 条，按标题关键词聚类）· 首建 2026-10-23
> 两个读数的口径不同：**905** = 语料全量条目数（需求档 `:74`）· **924** = 进聚类的条目数；差额来源设计位未复算（§10 第 10 条）

| 类 | 条数 | 检查点 |
|---|---|---|
| 刷新 / 数据丢失 | 58 | [P10] · [P05] |
| 报错 / 异常 | 52 | [P01] |
| 为空 / 空态 | 40 | [P17] |
| 筛选 / 查询 | 35 | [P09] |
| 金额 / 数字 | 31 | [P04] · [J6] |
| 按钮 / 交互 | 24 | [P11] |
| 英文 / 文案 | 22 | [P16] · [P01] |
| 重复提交 | 20 | [P06] · [J2] |

## 标记

- 已修：<类> — <证据> · <日期>
- 已复现：<类> — <run id> · <日期>
```

规则（写死）：

- **排序依据 = 「条数」列降序**；`surface` 在每个界面上按这个顺序摸面；`chain` 在同一个界面上有多条下一步时，先走与高权重类相关的那条（提交类动作排最前——它触发三项必查）。
- **AI 只追加**「已修 / 已复现」标记（带日期与证据），**不得删类目、不得改条数**；条数与标记的最终编辑权在用户（文件是人可编辑的权威）。
- **「已修」的类排到顺序末尾**（仍摸一次），「已复现」原位不动。否则权重表退化成「永远先查已修好的地方」——正是它要避免的。
- **`已修：<类>` 的类名按逐字匹配**（去掉首尾空白后与表内「类」列逐字相等）——匹配不上 ⇒ 一行 warning 点名该标记行，不阻断；不做相似 / 包含匹配：名称漂移要看得见，不要静默失效。
- **文件读不出 / 写不出**（解析失败、无权限）⇒ 用内置默认八类（与首建内容相同，落在 `btest_weights.dart`），run 照跑；返回项 6 标 `来源=built-in` + 一行 warning。**文件不存在不算这一类**：首建写盘成功 ⇒ 来源 = `file`、不 warning（§3.3 返回项 6 / 检查 5）。
- `btest_run_end` 检查 5 复核「八类目齐」：缺一 ⇒ warning 点名缺的类（不阻断）。

### 3.10 待确认项的研判：只给建议、不改判定（F8）

**run 只标待确认**：`expectFrom` 为弱或无权威来源的项，run 结束时不产生「预期不符」——表内 `判定=待确认`、`严重度=—`，并发进载荷 `unconfirmedDiffs[]` 的 `kind: pending`（§3.3）。

**研判在 run 之外做**（写死）：

1. run 结束、报告成形后，**会话主代理**（跑 run 的那个会话代理，不是子代理）派 `explore` 子代理：只读业务仓，可按需读本轮的预期文件。
   - **既有件三问（实读 2026-10-23）**：`existing: thincoder-core/agent-tools/subagent.mjs:144` · name: `explore` · consumers = 模型的 `subagent` 工具（`action:"spawn"` + `role:"explore"`）。
     `role` 的枚举里就有 `explore`（同档 `:241` 的 `ROLES` 集合同判）；只读过滤在 `thincoder-core/agent-tools/subagent-spawn.mjs:248-250`（`explore` / `plan` 走只读子集），权限固定拒绝询问（同档 `:266-267`）。
   - **派发入口是模型侧的工具调用**，不是 BaoCode 宿主的 API：`subagent` 工具由内核装配，BaoCode 只展示子代理卡片（`lib/chat/widgets/agent_step.dart:19`）。任务书写入 `repoRoot` 绝对路径 + 本轮预期文件路径作为 `knownFacts`，子代理用读档类工具直读。
   - **代价两条**：① 子代理拿不到浏览器工具（MCP 工具硬编码非只读，见批档 §4 的实读）⇒ 它只能读盘给倾向，不能自己开页面复核——这正是 F8 要的形态（研判要的是另一遍读盘，不是再跑一遍）；② 宿主不校验它派没派，证据 = 报告「建议」列有没有逐条回填（走查）。
   - `explore` 未装配时可用 `plan` 替代（同为只读角色，`subagent-spawn.mjs:248` 同判）；两者都不可用 ⇒ 按本节末段写 `待研判 · <原因>`。
2. 任务书逐条列出待确认项（caseId / 步骤 / 现象 / 证据 / `expectFrom` 原文），要求每项一条：
   - **倾向**：`可能正常` / `可能有问题` / `建议你定`；
   - **理由**：业务仓的 `file:line` 或设计档的某一节；
   - **优劣势**：误判为缺陷的代价 vs 漏判的代价，各一句。
3. 回填报告表的「建议」列（一项一格：`倾向 · 理由 · 误判代价 / 漏判代价`）。
4. 报告一次贴出（研判之后，不先贴一份再补一版）。

**判定列不动**：建议只进「建议」列；`判定` 仍是 `待确认`、`严重度` 仍是 `—`、`expectFrom` 级别不变。判定权在用户——这是 F3.1「弱来源不得判预期不符」的延长线。

**子代理的边界**：只读——不写业务仓、不写预期文件、不写报告；不改判定、不改严重度、不改来源级别。它给的是一份可被反驳的倾向，不是结论。

**研判不可用**（子代理未装配 / 失败）⇒「建议」列写 `待研判 · <原因>`，报告照发；待确认项不因缺建议而升级或降级。

**为什么不在 run 内**：run 内的复核是同一个代理看同一份证据，不构成第二双眼睛；研判要的是另一遍独立读（子代理只读业务仓），所以放在 run 之后、由会话主代理派。

**与 F10 的分工（同一件事不派两次单）**：F8 是 **run 之后**对「待确认项」的研判；F10 是 **run 之中**对「断点原因」的查明（§3.9）。
输入不同（F8 = `unconfirmedDiffs[]` 的 `kind: pending`；F10 = `chainBreaks[]` 的断点现场）、产出不同（F8 回填报告「建议」列；F10 写 `cause`）、时点不同（run 后 / run 中）。
**已带 `cause` 的断点不再进 F8 的待确认清单**——同一件事不重复派单；断点本身仍不进 `issues[]`（KD-23）。

## 4. 受影响文件清单（现行数 = 拆分后实测（2026-10-23）：按行尾换行符计行、末行计入；增量 = 「SPLIT-5 拆 run 生命周期 + SPLIT-6 抽状态行开关 + F11 持久化」的改动，三件均已完成（提交 `662a94d4`，`git show --stat 662a94d4` 可复核），`—` = 本批不动）

| 文件 | 现行数 | 增量（已完成，见提交 `662a94d4`） | 说明 |
|---|---|---|---|
| `lib/browser/btest/btest_mode.dart` | 556 | 拆 −≈655 · 加 ≤ +40 | 模式状态、`BtestSettings` 读写、注册与转发、闸；按 SPLIT-5 拆出 run 生命周期（已完成，两档，拆法见本节末「run 生命周期的拆法」）；F11：`BtestSettings` 加三个键（`onKey` / `traversalKey` / `modeKey`）与读写助手（缺省回落、非法值当缺失）；三键的**初值构造**落 `BtestState.fromSettings`（读三键、缺省回落、非法值当缺失、读不写），**写回**落 `BtestState` 的三个 setter（`set on` / `set traversal` / `set write`，显式闭包、失败不阻断，§9.1）；F9 的两开关字段与 `chainBreaks[].cause` 形状校验已落 |
| `lib/browser/btest/btest_run_state.dart` | 394 | ≤ +380 | run 状态（`BtestEntry` / `BtestRun` / 动作计数 / `truthLine`）+ `recordAllowed` / `recordDenied`（以 extension 落本档，调用点不变）+ `btest_run_start` 的返回项组装（§3.3）；**只搬不改行为** |
| `lib/browser/btest/btest_run_end.dart` | 309 | ≤ +315 | `btest_run_end` 的收尾检查表五项（§3.3）+ 载荷助手（`_diffKinds` / `_chainBreaks` / `_text` / `_short`）；**只搬不改行为** |
| `lib/browser/btest/btest_status_switches.dart` | 154 | ≤ +140 | 状态行的行文本 + 两个开关（从 `composer.dart` 抽出 `_buildBtestStatus` 与 `_btestSwitch`），对外一个 `BtestStatusLine`；F9 已实现的行为原样搬，显示口径按 §9.1 |
| `lib/browser/btest/btest_weights.dart` | 293 | — | 默认八类（条数 + 检查点）、`<qaRoot>/weights.md` 的路径 / 首建 / 解析 / 类目齐全读数、`已修` 排末尾、标记行逐字匹配（F7.1 已落，本批不动） |
| `lib/browser/btest/btest_policy.dart` | 417 | — | `BtestTraversal` / `BtestFace` 与 `parse`；入口 / evaluate / 只读面 / 生产闸的判据纯函数（本批不动，开关只改取值来源） |
| `lib/browser/btest/btest_card.dart` | 129 | — | `[D1]`–`[D8]` / `[J1]`–`[J7]` / `[P01]`–`[P20]` / `[H1]`–`[H3]`；报告口径与两列（本批不动） |
| `lib/browser/btest/btest_expect_file.dart` | 271 | — | 预期文件：路径派生（§3.4 四分支）、case 索引 + hash 基线、写回校验、人改检测（本批不动） |
| `lib/browser/browser_tools.dart` | 786 | — | 工具 `run` 包装的 btest 闸；`btest_run_start` / `btest_run_end` 注册；`browser_navigate.detour`、`browser_evaluate.readOnly` |
| `lib/kernel/thincoder/thincoder_kernel.dart` | 480 | — | 权限应答处接 btest 放行判据；回合上下文里挂模式卡 |
| `lib/chat/chat_session.dart` | 794 | 净增 ≤ +3（`_openBtest` 换成一行构造，预计 −3） | 模式状态读写、模式卡标记扫描、run 状态投影；**本批（F11）零净增**：三键的初值构造与写回都在 `BtestState`（`btest_mode.dart` 的 `BtestState.fromSettings` 与三个 setter），本档只把 `_openBtest`（`:158-162`）的函数体换成一行 `BtestState.fromSettings(...)`，`setBtest` / `setBtestTraversal` / `setBtestWrite`（`:172-214`）保持既有转发。**SPLIT-3 触发条件：下一次向该档追加 >10 行即先拆**（本批 +3 以内，不触发） |
| `lib/chat/chat_models.dart` | 732 | — | btest 模式与 run 状态的模型字段（两个开关不在模型里，不新增字段） |
| `lib/chat/composer/composer.dart` | 556 | 拆 −≈112 · 调用点 ≤ +5 | 模式选择器追加 `btest` 项 + 状态行；**本批**：行文本与两个开关抽到 `btest_status_switches.dart`（`_buildBtestStatus` `:1932-2017` + `_btestSwitch` `:2019-2049` 实读），本档只留 `if (widget.session.btestOn) BtestStatusLine(...)`（≤5 行）；拆后 ≈2354 仍 >800 ⇒ 后续增量按 SPLIT-1 先拆 |
| `lib/settings/pages/browser_page.dart` | 417 | — | 允许域名 / 生产域名两个列表 + 默认只读开关 + `btest.qaRoot` 输入框（F3.2 已落；本批无新设置项——写开关的复位走删键，见 §9.1） |
| `lib/l10n/app_en.arb` | 8043 | — | **源档**（`l10n.yaml` 的 template，`flutter gen-l10n` 生成）；遍历两个键 `btestTraversalDepth` / `btestTraversalBreadth` 与写侧复用的 `btestFaceReadonly` / `btestFaceWrite` 均已由 F9 落盘，本批不动 |
| `lib/l10n/app_zh.arb` | 2995 | — | 中文译文，键与模板一一对应（`btestTraversalDepth` = `深度` / `btestTraversalBreadth` = `广度`，`:2925-2926` 实读）；本批不动 |
| `lib/l10n/app_localizations.dart` | 18045 | 派生 | 生成物，不手改 |
| `lib/l10n/app_localizations_en.dart` | 11085 | 派生 | 生成物，不手改 |
| `lib/l10n/app_localizations_zh.dart` | 10490 | 派生 | 生成物，不手改 |
| `test/browser/btest_policy_test.dart` | 947 | ≤ +45 | F9 用例 #35 / #36 / #39 已落；**本批（F11）**加 #43（三键写回 → 重开会话读回）、#44（键缺失 / 非法值 ⇒ 缺省，读不写）、#45（切回 normal ⇒ `btest.on` 删键 ⇒ 重开 = 关）（随批删） |
| `test/browser/btest_card_test.dart` | 169 | — | 卡内标签计数与报告列（随批删） |
| `test/browser/btest_weights_test.dart` | 183 | — | 权重表首建 / 缺失 / 删类目 / 标记漂名（随批删） |
| `test/chat/composer_btest_status_test.dart` | 217 | ≤ +15 | #37（期望改为「重启读回三键」）/ #38 / #40；本批加一条「`btest.mode` 缺键 ⇒ 状态行显示解析后的 `btest.readonly` 值」（随批删） |
| `test/browser/btest_expect_file_test.dart` | 617 | — | 预期文件用例（F3.2 已落，本批不动；随批删） |

业务仓零写入：预期文件在独立 QA 仓（§3.4），不在本仓、也不在业务仓的改动面内。

**设置键的落点**：btest 的设置键都在 `BtestSettings`（`lib/browser/btest/btest_mode.dart:15-88`）；`app_settings.dart` 本批不改——它被设置页依赖，把 btest 键放进去会与 `browser_page.dart` 成环。

**超 800 行档：本批先拆后加（>800 无例外通道）；本批的 SPLIT-5 / SPLIT-6 已完成（提交 `662a94d4`；三个新档的实读见本表「现行数」列）**

| 档 | 现行 | 本批（已完成） | 余下抽取缝（谁动它时从这里切） | 登记 |
|---|---|---|---|---|
| `btest_mode.dart` | 556 | 已拆出 run 生命周期（−≈655）⇒ ≈480，并落 F11 的 ≤ +40 | `BtestSettings` 读写抽 `btest/btest_settings.dart` | SPLIT-5（本批落地） |
| `composer.dart` | 556 | 已抽状态行与两个开关（−≈112）⇒ ≈2354；只留 ≤5 行调用点 | 按 `docs/design/structure-splits.md` §4.3 的六段切法切（段表与符号点名见该节） | SPLIT-6（本批落地）/ SPLIT-1（余下；旧缝 `composer/mode_selector.dart` 已被取代，按它到不了 ≤800，理由见该节） |
| `thincoder_kernel.dart` | 480 | — | 审批面（`_serverRequest` / `answer` / `_resolveApprovals`）抽 `approvals.dart` | SPLIT-2 |
| `chat_session.dart` | 794 | 三键读写零净增（≤ +3） | 模式与设置投影抽 `session/mode_state.dart` | SPLIT-3（触发条件：下一次向该档追加 >10 行即先拆；本批 +3 以内，不触发） |
| `chat_models.dart` | 732 | — | 按 `docs/design/structure-splits.md` §4.5：`EditorContext` / `TextContext` 抽到 `lib/chat/editor_context.dart` | SPLIT-4（旧缝 `chat/btest_models.dart` 已被取代，本档没有任何 btest 类型，缝上无料可搬，理由见该节） |

**run 生命周期的拆法（本批第一步，已完成；随后落 F11。提交 `662a94d4`，拆后实读见本表「现行数」列与本批 §5）**：1131 行放进两个各 ≤500 的档在算术上做不到（要搬走 ≥631 行，而搬走的那侧自带文件头 ⇒ 新档必然 >631 行），所以 run 生命周期按「一轮的开」与「一轮的收」各成一档，三档都 ≤500：

- `btest_run_state.dart` ← `BtestEntry`（`:90-98`）+ `BtestRun`（`:100-217`，含 `truthLine` 与动作计数）。
  同档再放 `BtestState.recordAllowed` / `recordDenied` / `_count`（`:299-344`，以 **extension** 落，`state.recordAllowed(...)` 的调用点不变）+ `_startRun` 的返回项组装（`:650-835`）；`_start` 的 `run` 闭包改调本档顶层函数（参数与返回不变）⇒ 基区 359 + 文件头 ≈ 375。
- `btest_run_end.dart` ← `_endRun` 的收尾检查表五项（`:836-1066`）+ 载荷助手（`:1067-1131`，`_diffKinds` / `_chainBreaks` / `_text` / `_short`）；`_end` 的 `run` 闭包同上 ⇒ 296 + 文件头 ≈ 310。
- `btest_mode.dart` 留下：`BtestSettings`、`BtestState`（`on` + 两个开关 + `run` 字段 + `start`）、注册与转发、`BtestGate`、两个工具的 schema ⇒ ≈480（≤500）；F11 的 ≤ +40 落在这里 ⇒ ≈520（<800 硬顶；500 是拆分目标，不含后续增量）。`start` 不搬：它写私有 `_runs`，搬走就得连计数器一起搬，收益为零。

**新增实现只落 `lib/browser/btest/*`**（mode / run_state / run_end / status_switches / policy / card / expect-file / weights 八个文件）；四个大档里只出现"调用点 + 一个钩子"，不搬已有逻辑（本批唯一的搬运是本表列出的两处拆分）、不改已有签名。

**F10 增量（断点查明）**：`btest_mode.dart` 的检查 2 对 `chainBreaks[].cause` 只加「可缺省 + 出现须非空」的形状校验（≤ +10）；`btest_card.dart` 的 `[D8]` 一句断点可派只读子代理（≤ +3 行；替换后的句子实测 497 字符，比上一版多 288 字符）；`test/browser/btest_policy_test.dart` 加 #41 / #42（≤ +40，随批删）；其余档不动。

**登记**：SPLIT-1…6 = 拆分登记项；SPLIT-5 / SPLIT-6 本批落地，SPLIT-1…4 不在本批落地。台账写权不在设计位，所以本批只在档内登记并在回执点名，由主编排方落台账行（挂本批 #149 的后续批）。

## 5. 关键决策记录（含被否）

| 编号 | 决策 | 被否方案与理由 |
|---|---|---|
| KD-1 | `btest` = 宿主 overlay，会话级开关，不发内核 | 改内核 mode：要动外仓 `thincoder/`，且改 ACP `mode` 语义（本批已定不做） |
| KD-2 | 模式卡走 `KernelTurn.contexts`，首条消息注入一次 | MCP `instructions`：全局、initialize 一次，不能按会话切模式；append-system-prompt：thincoder 无此通道 |
| KD-3 | 用 `btest_run_start` / `btest_run_end` 把一轮变成机械判据 | 只靠提示词：漂移无法判，忘没忘看不出来 |
| KD-4 | 预期文件放独立 QA 仓：`qaRoot`（`btest.qaRoot`；未配 ⇒ 会话工作区根下的 `qa`，§3.4 四分支）下的 `<仓名>/<业务线>.md` | ① 业务仓 `docs/qa/`：用户要求业务仓干净，业务仓只做 `git log` 来源判定，写进去等于每轮都往业务仓添未提交改动；② 宿主数据目录：不可 diff、不可回看，session 删了即失（等于回到凭记忆判断）；③ 每轮一个文件：无法积累、无法对比 |
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
| KD-20 | 预期文件的文件名与路径全由宿主派生（`line` + `repoRoot` + 会话 `cwd` + `btest.qaRoot`），`expectFile` 不作入参；`qaRoot` 按 §3.4 四条分支派生（设置值 / 工作区根 / 父目录兜底），结果与来源作为 `btest_run_start` 返回项 2 给出 | ① 保留 `expectFile` 作「业务线名」入参：`line` 已是业务线名，两个字段必须相等 ⇒ 多一个能漂移的来源；② 保留相对路径入参：落点依赖调用方每次传对路径，且路径绑死业务仓；③ 不返回绝对路径：用户无法当场核对落点，配错要等写入失败才发现；④ 只按 `join(dirname(repoRoot), 'qa')` 一条规则派生：项目嵌套一层就冒出第二个 QA 根（`repos\qa` 与 `repos\clientA\qa`），同一工作区的预期分散两处，违反「一个工作区只有一个 QA 根」 |

| KD-21 | `traversal` 的内置缺省 = `surface`（既有 run 的行为就是广度，缺省不改既有调用方的行为）；`chain` 由调用方显式声明，或由会话「遍历」开关给出（优先级见 §3.3，控件见 §9.1） | ① 缺省 `chain`：所有既有 run 被悄悄改成深度优先；② 必填：既有调用方全部要改，且「默认怎么跑」没有答案 |
| KD-22 | 遍历写成意图级规则（「能往下走就走」/「把一个界面摸完再走下一个」），不写状态流转列表；三项必查绑在**提交类动作之后**（刷新丢失 / 金额勾稽 / 重复提交） | ① 形式化的流转列表：业务线的流转各家不同，写死一张表就只覆盖那张表里的路（用户 02:34 明确否掉）；② 把三项绑在「每跨一次流转」：没有流转概念的界面（列表 / 筛选）就漏查；绑在提交类动作之后才和缺陷来源对得上（58 / 31 / 20 都发生在提交前后） |
| KD-23 | 断点必录、断点不是失败、不停轮 | ① 断点当失败报告：用户收到的是「跑不动」而不是「哪里走不通」，且整轮提前结束违反 D5；② 不记断点：用户分不清「没跑」和「跑了但断」，覆盖读数失真 |
| KD-24 | 权重表落 `<qaRoot>/weights.md`，宿主首建、AI 只追加标记、`已修` 的类排末尾 | ① 提示词常量：缺陷修完后顺序不变，永远先查已修好的地方（用户给的理由）；② 每仓一份：同一工作区多个仓各写一份，而密度的实测来源只有一份语料；③ AI 改条数：历史密度是读数，改了不可复核 |
| KD-25 | F8 研判放在 run 之外，由会话主代理派只读子代理逐条给建议，判定列不动 | ① run 内自查：同一代理、同一份证据，不构成第二双眼睛；② 子代理改判定：违反 F3.1（弱来源不得判预期不符），判定权被让渡；③ 建议并进尾注：逐条对齐要靠 caseId 手找，表内一列才能一眼对照 |
| KD-26 | 报告加「判定」「建议」两列；报告在研判之后一次贴出 | ① 先贴一份再补一版：同一轮两份报告，用户要对照两版才能读；② 只加「建议」不加「判定」：建议列没有「不许改」的锚点，判定与建议混在一格 |
| KD-27 | 两个 run 参数做成状态行上的二选一开关（遍历：`深度` / `广度`；写：`只读` / `允许写`），值存会话状态（字段落 `BtestState`，`lib/browser/btest/btest_mode.dart:221`；`chat_session.dart` 只加访问器），改值时写回全局设置、读取不写（KD-30，§9.1）；业务线不做下拉；优先级 = 显式参数 > 会话开关 > 设置缺省；运行中点击只改开关、只对下一次 run 生效 | ① 继续让用户背参数名（`traversal: chain` / `mode: write`）：用户 2026-10-23 03:34 的话是「不能做成按键选择吗」「我没看懂」——参数名对用户是认知负担，而两个值各只有两档、没有中间态，正是开关的形态；② 按钮组：状态行很矮，两个按钮组把它撑高；③ 业务线下拉：要先知道 `repoRoot` 才能列 `<qaRoot>/<仓名>/*.md`，会逼用户先说仓、再选线，多一步；`line` 从用户句子里来更直接；④ 只存会话内存：重启即回默认，用户每天要重选两次——本项立项理由（用户 2026-10-23 06:46 选「A 全局记住」），落点与失败口径见 KD-30 |
| KD-28 | 规则 A 判优先级**定值后**的 `mode`（缺省解析完成再判）：`env: prod` ∧ 定值 = `write` ⇒ 拒绝起 run，不论 write 来自参数还是开关 | 只判字面参数：`env: prod` + 省掉 `mode` + 写开关 = `允许写` 能起一个 `mode=write` 的 run，与「起 run 即拒」的不变量相反（评审 #36 🔴）；数据面虽由规则 B 兜住，判据本身仍可被省参数绕过 |
| KD-29 | `chain` 断点查明：只在断点处派只读子代理（`explore`，退 `plan`）、**派出后不等回答**继续走，一次 run 最多 3 次；结论在 run 内回来 ⇒ 写 `chainBreaks[].cause`（可空），run 已结束 ⇒ 进收尾消息（不重开）；`reason` 四值枚举不变 | ① 每步派：一条业务线几十步，每步一个子代理会把一轮堆成几十个，稀释研判、白花成本；② 宿主 API 派：模型的 `subagent` 工具本来就是模型侧装配（§3.10 实读），宿主另开一条不经模型的派发路径 = 两套派发语义；③ 子代理改 `reason` / 判定：判定权在用户（F3.1 / F8 同一条线）；④ 不设上限：断点多的业务线同样会堆出几十个子代理，结论也收不完；⑤ 断点既派查明又进 F8：同一件事两次派单 |
| KD-30 | 模式与两个开关跨重启：三个全局键 `btest.on`（bool）/ `btest.traversal`（`chain` / `surface`）/ `btest.mode`（`readonly` / `write`），与既有四个 `btest.*` 键同处 `BtestSettings`；会话打开时读成 `BtestState` 初值，每次改值写回自己的键；写失败只 `debugPrint`、不阻断 UI；键缺失 / 值非法 ⇒ 回落缺省 | ① 会话设置 map（`kernelContext.settings`）：只随会话走，新建会话仍是默认，写入要动工作区真相源（台账 #153 的结论）；② 单一个 `btest` 对象键：三个值塞进一个键，改一个要整组重写、缺省解析耦合，读不出「哪个值缺」；③ 写失败弹错 / 回滚界面：设置写失败（文件被占用 / 不解析）不该吞掉用户刚做的操作——界面保持已改值，下一会话读到旧值即可（与 `browser_page.dart` 既有写回同口径）；④ 非法值自动改写成缺省：悄悄改写没人能看出被改过，读时回落 + 不写回，让文件保持用户原样 |

## 6. 验收对照（回指需求 F1–F11 · F2.1 · F3.1 · F3.2 · §5 验收 1–7）

| 需求 | 设计落点 | 可跑判据 |
|---|---|---|
| F1 模式切换 | §3.1 · §3.2 | 走查：切到 btest → composer 出现状态行；切回 normal → **不残留**：状态行消失、下一回合起不再按 btest 纪律行事（不自动 start run、不套三尾注、不受只读面约束）；**计数差判据（任意次开→关→再开之后仍成立）**：`D = count("btest-mode-card v1") − count("btest-mode-card-off v1")` = 1（模式内）/ 0（已退出）；读数为**回合装配完成时**的值：宿主 `on` ⇔ `D = 1`、宿主 `off` ⇔ `D = 0`（§3.2「判定的时刻」）；`grep` 形态：`echo $(( $(grep -c "btest-mode-card v1" <会话记录>) - $(grep -c "btest-mode-card-off v1" <会话记录>) ))` |
| F2 模式卡 | §3.2 | ① 计数差 `D = 1`，第二条消息后仍 = 1（同一会话内多投一张即失败；`grep` 形态同 F1 行）；② 内容清单：`btest_card_test` 断言 `[D1]`–`[D8]` 八个、`[J1]`–`[J7]` 七个、`[P01]`–`[P20]` 二十个、`[H1]`–`[H3]` 三个（共 38 个）标签齐全，缺一即失败 |
| F3 预期落盘 | §3.3 · §3.4 | ① `btest_run_start` 返回含绝对路径 + case 索引 + 内容 hash（缺一即实现不全）；② 跑完一条业务线后预期文件（§3.4 派生路径）存在，报告每条「预期不符」能指到其中一条 `## CASE-`；③ 检查表的 `written` / `not written` 与 hash 基线读数一致 |
| F3.2 落点 = 独立 QA 仓 | §3.3（`expectFile` 不入参 · 返回项 2）· §3.4（四分支派生 + 建目录）· §9（`btest.qaRoot`） | ① 跑一次后预期文件出现在 `<qaRoot>/<仓名>/<业务线>.md`：未配 `qaRoot` ⇒ 会话工作区根下的 `qa`（`repoRoot` 是工作区根的严格后代 = 分支 2，按路径段比较；`cwd == repoRoot` ⇒ 父目录兜底 = 分支 3），已配 ⇒ 用之（§7 #24–#28）；② 返回项 2 是解析后的绝对路径 + 来源标记（`设置值` / `工作区根` / `父目录兜底`）+ 降级原因（`父目录兜底` 时必带，分支 3 / 4 在返回里可分辨）；③ **一个工作区一个 QA 根**：同一 `cwd` 下两个不同深度的仓（`repos\v2-booking` 与 `repos\clientA\v2-timecharter`）⇒ 返回的两个 `qaRoot` 逐字相等（§7 #26）；④ 业务仓零写入（`qaRoot` ∉ `repoRoot` 时成立）：跑完 `git -C <repoRoot> status --porcelain` 为空；`qaRoot` 被配进 `repoRoot` 内 ⇒ 返回项 2 点名（§3.4 分支 1）；⑤ 不建 git 仓：`qaRoot` 下无 `.git`（§7 #24） |
| F3.1 预期带出处 | §3.4（三级来源 + 三条硬规则）· §3.8 | ① 预期文件每条 case 有 `expectFrom`，级别 ∈ {强, 中, 弱} 或 `无权威来源`，引用形合 §3.4 的表；② 对读写回前后的文件：级别只降不升（中 / 弱 不得被写成强）；③ `无权威来源` 的 case 在报告「需要用户补规则的清单」里逐条点名 |
| F4 来源标注 | §3.5 | 文件里每条 case 有 `source:` 与 `origin:` 两行；差异条目在报告尾注「待确认差异」里带三次步骤 |
| F5 只读轮 | §3.6 | 只读 run 里调 `browser_click` → 返回拒绝文本，含 `readonly` |
| F5 回看文档 / 代码 | §3.6 | 走查：只读 run 里读业务仓 `docs/` 下的文件 → 走内核原审批（btest 不代答 allow），读取成功，只读轮的浏览器边界不变 |
| F6 报告 | §3.8 | 报告是一张表（**13 列，含行号 `#`**；判定 / 建议两列在内）+ 三尾注；首行含 `traversal` / `mode` 与操作真实性读数；表内无图片；每条证据是接口 / console / 字段值之一；三尾注由 `btest_run_end` 的 `blockers` / `unconfirmedDiffs` / `uncovered` 三个键承载（chain 轮另有 `chainBreaks`） |
| F7 遍历策略 | §3.9 · §3.3（`traversal`）· §3.8（首行）· §9 | ① 缺省：不传 `traversal` 起 run ⇒ 取会话「遍历」开关（初始 = `广度`）⇒ 返回项 1 含 `traversal=surface`（§7 #31）；开关点成 `深度` ⇒ `traversal=chain`（§7 #35）；② 传 `chain` ⇒ 返回项 1 与报告首行都含 `traversal=chain`，且每一步都有「还能往哪走 → 走了 / 断点」的读数（§7 #29）；③ 非法值 ⇒ 拒绝起 run 并点名 `traversal` 与两个合法值（§7 #32）；④ chain 走不动 ⇒ 一条 `chainBreaks`（path / at / reason / verified）+ 报告「链断点」块，run 继续、不停轮（§7 #30）；⑤ surface ⇒ 每个界面的面从当次 DOM 快照枚举、摸完走到下一个界面，直到本轮范围走完；范围内没摸到的界面 / 分支进 `uncovered`（§7 #31） |
| F7.1 权重表 | §3.9（权重表）· §3.3 返回项 6 · 检查 5 | ① 首次 run 后 `<qaRoot>/weights.md` 在盘：八类 × 条数 × 检查点齐、来源 = `file`、无 warning（§7 #33）；② 删文件再起 run ⇒ 文件重建、来源 = `file`、无 warning（与首次同一读数，§3.9）；文件读不出 / 写不出 ⇒ `built-in` + warning（#33）；③ 删一个类目 ⇒ 检查 5 warning 点名该类（#33）；④ 顺序：surface 按条数降序、`已修` 的类排末尾仍摸一次；提交类动作之后三项必查（#29 · 走查） |
| F8 待确认研判 | §3.10 · §3.8（判定 / 建议列）· §3.3（`kind: pending`） | ① 弱 / 无来源项在表内 `判定=待确认`、`严重度=—`（#34）；② run 后会话主代理派 `explore` 子代理（装配点见 §3.10 三问行），逐条回填「建议」= 倾向 + 理由 + 优劣势（#34）；③ 判定列与 `expectFrom` 级别不变（子代理不改判定）；④ 子代理不可用 ⇒ `待研判 · <原因>`，报告照发（走查） |
| F9 两个开关（遍历 / 写） | §9.1 · §3.3（优先级） | ① 点「深度」→ 起 run（不带 `traversal`）⇒ 返回项 1 与报告首行都是 `traversal=chain`（§7 #35）；开关 = `广度` + 调用带 `traversal: chain` ⇒ 两处仍是 `traversal=chain`（显式压过开关，#36）；② 写开关：`只读` ⇒ `browser_click` 被拒并点名 `mode: readonly`，`允许写` ⇒ 放行；③ 跨重启保持（#37 / #43）：三个键在盘 ⇒ 重开会话读回同值（状态行与起 run 缺省一致）；键缺失 ⇒ 回落缺省（遍历 = `广度`；写 = 由 `btest.readonly` 初始化，默认 `只读`，设置关掉「默认只读」⇒ `允许写`；#44）；④ 点选写回会话状态（#38）：无 run 文案随开关变，运行中文案随 run 定值变；⑤ 中 run 点击只对下一次 run 生效，本 run 的 `traversal` / `mode` 不变（#40） |
| F10 断点查明 | §3.9（断点派只读子代理 · 异步派发）· §3.3（`chainBreaks[].cause`）· §3.10（与 F8 的分工） | ① `chain` 轮每个断点都当场派一个只读子代理且**不等回答**；回答在 run 内到达 ⇒ 该条带 `cause`（一句结论 + `file:line` 或文档节），`reason` 仍是四值之一（§7 #41）；② 同一条 run 第 4 个及以后的断点不派，`cause = 未查明（达到本轮研判上限）`，run 正常收尾（§7 #42）；③ `explore` / `plan` 都不可用 ⇒ `cause = 未查明（<原因>）`，报告照发（走查）；④ 已带 `cause` 的断点不进 F8 待确认研判（§3.10）；⑤ 派发方式 = 异步：断点当下派出，同一步之后的动作不等待它（走查：会话记录里 `subagent` 调用当下返回、其后的动作先于回答发生）；回答在 run 结束后到达 ⇒ 结论进收尾消息、run 不重开（走查：收尾消息 + 报告「链断点」块）；`cause` 可缺省——迟到的回答不破坏 §3.3 字段形 |
| F11 模式与两个开关跨重启 | §9.1（持久化）· §3.1 · §3.3（初值） | ① 写回：点烧瓶 / 点「深度」/ 点「允许写」后 `settings.json` 的 `btest.on` = `true`、`btest.traversal` = `chain`、`btest.mode` = `write`（§7 #43）；② 重开会话读回：状态行 = `btest · 待开始 · 深度 · 允许写`，起 run 不带参数 ⇒ 返回项 1 与报告首行都是 `traversal=chain` / `mode=write`（#43）；③ 键缺失 / 值非法 ⇒ 回落 关 / `广度` / 写开关未点选（取值时解析 `btest.readonly`，§9.1「写初始」），不报错、不阻断、不改写键（#44）；④ 读取不写：只开一次会话不点任何开关 ⇒ 三个键不出现（#44）；⑤ 写失败不阻断 UI：`settings.update` 抛错 ⇒ 只一条 `debugPrint`，界面与本会话照常（走查；与 `browser_page.dart` 同口径，§9.1）；⑥ 退出删键：切回 normal ⇒ `btest.on` 键被删（写 `null`）⇒ 关掉会话重开 = 关，不读回旧的 `true`（#45） |
| 验收 2（证据可复核） | §3.8 | 任取一条问题，按「证据」列能在页面上重读出同一读数 |
| 验收 3（预期来自盘上且带出处） | §3.4 · §3.8 | 每条「预期不符」的「预期出处」列非空、级别 ∈ {强, 中}、引用能落到档 + 节 / 冒烟清单行 / issue 号；`expectFrom` 指向代码现状或为 `无权威来源` 的 case 不出现在「预期不符」行里（§7 #16） |
| 验收 4（来源可追溯） | §3.5 | 每条 case 的 `origin` 能在 `git -C <repoRoot> log` 里找到，或明确写 `无（存量）` |
| 验收 5（稳定性读数） | §3.8 | 连续两次只读跑，报告里步骤序列一致率可数（不作为硬门槛） |
| 生产禁写（规则 A） | §3.7 | 走查：`btest_run_start`（`env: prod`、**定值后** `mode = write`）→ 拒绝起 run，文本点名 `env: prod` 与 `mode: write`，run 未建立；两条输形态同判：显式 `mode: write` / 不带 `mode` + 写开关 = `允许写`（§7 #13 / #39） |
| 生产禁写（规则 B） | §3.7 | 走查：`prodHosts` 清空 + 写 run 的 `browser_click` → **拒绝**（工具 `run` 层硬拒绝，零审批卡），文本点名规则 B 与 prodHosts 未配置；`prodHosts` 填入该 host 后再点 → 拒绝，文本点名生产禁写 |
| F2.1 操作方式 = 模拟真人 | §3.6.1–§3.6.5 · §3.3 检查表 4 · §3.8 绕道栏 | 见下一行：验收 6 是它的机检口径 |
| 验收 6（操作真实性，机检） | §3.6.2 · §3.6.3 · §3.3 检查表 4 · §3.8 | ① 报告头读数「入口 = 1」且首次 url = `startUrl`，同时有「被拒入口」格；② 「evaluate 写值被拒」= 0 且「`replay` 被拒」= 0（放行恒 0，§3.3 检查表 4-②）；③ 「文字定位 / ref·selector 兜底」两个数都在报告头，且**兜底数 = `noVisibleText[]` 条数 = 报告「无可见文字」行数**（不等即点名差额），兜底 > 0 时每步在步骤列写了理由；④ `browser_click` / `browser_type` 的目标以文字 / label / 角色描述（兜底步除外）；⑤ 请求源于真实点击：`browser_history` 的 clicks 记录对请求时间线走查（`lib/browser/browser_history.dart:537-547`） |

## 7. 用例表（正常 / 边界 / 错误）

| # | 类型 | 输入 | 期望输出 | 测试落点 |
|---|---|---|---|---|
| 1 | 正常 | btest 开、run（dev、write、host 在白名单）→ `browser_click` | 自动放行，无审批卡，动作执行（内核发不发审批请求都无卡：发则钩子答 allow，不发则无请求；§3.7 末段） | `btest_policy_test`（放行判据）+ 走查（无审批卡） |
| 2 | 正常 | 已写完回 + 三尾注结构化载荷 → `btest_run_end` | 检查表五项全绿；`expectFile: written` | `btest_expect_file_test` |
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
| 13 | 错误 | `btest_run_start`（env: prod、显式 `mode: write`） | 拒绝起 run，文本点名两项（规则 A，判定值后的 `mode`） | `btest_policy_test` |
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
| 24 | 正常 | `btest.qaRoot` 未配；会话 `cwd` = `C:\Users\\xinbo\repos` → `btest_run_start`（`repoRoot` = `C:\Users\\xinbo\repos\v2-booking`、`line` = 订舱） | 返回项 2 = `C:\Users\\xinbo\repos\qa\v2-booking\订舱.md`，来源 = `工作区根`；目录已建；`qaRoot` 下无 `.git`（不做仓库初始化） | `btest_expect_file_test` |
| 25 | 边界 | `btest.qaRoot` = `E:\qa` → 同上起 run | 返回项 2 = `E:\qa\v2-booking\订舱.md`，来源 = `设置值`；读 / 写都落该路径，派生规则不参与 | `btest_expect_file_test` |
| 26 | 边界 | **嵌套用例**：同一会话 `cwd` = `C:\Users\\xinbo\repos`；先起 run（`repoRoot` = `C:\Users\\xinbo\repos\v2-booking`），再起 run（`repoRoot` = `C:\Users\\xinbo\repos\clientA\v2-timecharter`） | 两次返回的 `qaRoot` **逐字相等** = `C:\Users\\xinbo\repos\qa`（来源 = `工作区根`）；文件分别 = `qa\v2-booking\订舱.md` / `qa\v2-timecharter\船期.md` | `btest_expect_file_test` |
| 27 | 边界 | 会话 `cwd` = `C:\Users\\xinbo\repos\v2-booking`（工作区就是仓本身）→ 起 run（`repoRoot` 同左） | `qaRoot` = `C:\Users\\xinbo\repos\qa`，来源 = `父目录兜底`，降级原因 = `工作区根即业务仓`；`repoRoot` 下不出现 `qa/` 目录（业务仓零写入） | `btest_expect_file_test` |
| 28 | 错误 | `btest.qaRoot` 指向建不出来的位置（只读盘 / 非法字符 / 无权限）→ 起 run | 拒绝起 run，文本点名 `qaRoot` 路径与错误原文，run 未建立（§3.4「建目录」） | `btest_expect_file_test` |
| 29 | 正常 | `traversal: chain` 起 run（写轮、dev）→ 从列表进详情，能编辑就编辑、能提交就提交，一直往下走 | 返回项 1 含 `traversal=chain`；每一步都先问「还能往哪走」并走；每次提交类动作之后有刷新丢失 / 金额勾稽 / 重复提交三项读数；报告首行 `traversal=chain`；问题行判定 = 预期不符 | `btest_policy_test`（参数解析）+ 走查（走法与三项读数） |
| 30 | 边界 | `traversal: chain`，走到一个走不动的界面（门控 / 无权限 / 数据不足 / 没有下一步） | 记一条 `chainBreaks`（`path` / `at` / `reason` / `verified`）；**回头找别的路继续**、不停轮；报告「本轮未覆盖」下「链断点」块有该条；不进 `issues[]`、不计严重度 | `btest_policy_test`（载荷校验）+ 走查 |
| 31 | 正常 | 不传 `traversal`、会话「遍历」开关 = `广度`（初始值）起 run，本轮范围有 2 个界面（列表页 → 详情页）；列表页有 3 个页签 + 1 个表单 + 1 个筛选 + 1 个列表 | 返回项 1 含 `traversal=surface`；列表页的面从当次 DOM 快照枚举、按权重序摸完 ⇒ 走到详情页继续摸；摸过的各有读数；范围内没走到的界面 / 分支进 `uncovered` 逐项点名（不是单个控件）；报告首行 `traversal=surface` | 走查（快照与报告对读） |
| 32 | 错误 | `traversal: depth`（非法值）起 run | 拒绝起 run，文本点名 `traversal` 与合法取值 `chain` / `surface`，run 未建立 | `btest_policy_test` |
| 33 | 边界 | 首次 run（`<qaRoot>/weights.md` 不存在）→ 起 run；再删掉该文件 → 起 run；再把文件内容改成读不出 → 起 run；再删文件里一个类目 → `btest_run_end` | 首次：文件建成、八类 × 条数 × 检查点齐、来源 = `file`、无 warning；删除后：与首次**同一读数**（重建、`file`、无 warning）；读不出：`built-in` + warning，run 照跑；删类目：检查 5 warning 点名缺的类 | `btest_weights_test` |
| 34 | 边界 | 一轮里有 2 个 `kind: pending` 项（`expectFrom` 弱 / 无来源）→ 报告成形 | 两项在表内 `判定=待确认`、`严重度=—`；派 `explore`（§3.10 三问行）后「建议」列逐项有 倾向 / 理由 / 优劣势；判定列不变；子代理不可用 ⇒ `待研判 · <原因>` | 走查（报告表 + 子代理任务书） |
| 35 | 正常 | 会话「遍历」开关点成 `深度`、「写」开关点成 `只读`；`btest_run_start` 不带 `traversal` / `mode`（dev、host 在白名单） | 返回项 1 含 `traversal=chain` 与 `mode=readonly`；`browser_click` 被拒、文本点名 `mode: readonly`；报告首行 `traversal=chain · mode=readonly` | `btest_policy_test`（缺省来源）+ 走查（开关点击与回显） |
| 36 | 边界 | 遍历开关 = `广度`、写开关 = `允许写`；调用带 `traversal: chain` + `mode: readonly` | 返回项 1 与报告首行都是 `traversal=chain` / `mode=readonly`；`browser_click` 被拒（显式参数压过开关）；两个开关的当前值不变（参数只在本次 run 生效） | `btest_policy_test` |
| 37 | 边界 | 会话重启（`BtestState` 重建），`settings.json` 三键齐（`btest.on` = `true` / `btest.traversal` = `chain` / `btest.mode` = `write`） | 状态行 = `btest · 待开始 · 深度 · 允许写`；只读不写：重启不产生任何键改动（三键值原样） | `composer_btest_status_test` |
| 38 | 正常 | 无 run 时点状态行「遍历」选 `深度`；再起 run（不带 `traversal`） | 会话状态写回 `chain`；无 run 文案 `btest · 待开始 · 深度 · 只读`；运行中文案 `btest · 航次 · 深度 · 只读 · run 1`，与返回项 1 / 报告首行 `traversal=chain` 一致 | `composer_btest_status_test` |
| 39 | 错误 | `btest_run_start`（`env: prod`、不带 `mode`、写开关 = `允许写`） | 拒绝起 run，文本点名 `env: prod` 与（缺省得来）`mode: write`；run 未建立（规则 A 判定值后的 `mode`） | `btest_policy_test` |
| 40 | 边界 | 运行中点「遍历」选 `深度`（起 run 时开关 = `广度`、未传 `traversal`） | 本 run 的 `traversal` 仍 = `surface`（返回项 1 与报告首行可核）；状态行仍显示本 run 实际值；开关当前值变为 `深度`，只对下一次 run 生效 | `composer_btest_status_test` |
| 41 | 正常 | `traversal: chain`，走到一个走不动的界面（如详情页无编辑入口）→ 当场派 `explore` 只读子代理读业务仓，**不等回答**继续走下一步 | 派发后 run 继续（会话记录里其后的动作先于回答发生）；回答在 run 内到达 ⇒ 该条 `chainBreaks` 带 `cause` = 一句结论 + `file:line`（如「详情页编辑入口被角色权限挡住 · <repoRoot>/lib/booking/detail.dart:88」），`reason` 不变，报告「链断点」块列出；回答在 run 结束后到达 ⇒ 结论进收尾消息、run 不重开、该条 `cause` 可缺省；子代理未操作浏览器、未改预期文件 | 走查（报告 + 收尾消息 + 子代理任务书与回执） |
| 42 | 边界 | 同一条 run 的第 4 个断点（前 3 个已各派一次） | 不再派子代理；该条 `cause = 未查明（达到本轮研判上限）`；run 继续跑完、不重开、不停 | 走查（`chainBreaks` 计数与 `cause` 文本） |
| 43 | 正常 | 点烧瓶切进 btest；点「遍历」选 `深度`；点「写」选 `允许写`；关掉会话重开 | `settings.json` 三键 = `true` / `chain` / `write`；重开后状态行 `btest · 待开始 · 深度 · 允许写`；起 run 不带 `traversal` / `mode`（dev）⇒ 返回项 1 = `traversal=chain` / `mode=write` | `btest_policy_test`（键读写 + 初值）· `composer_btest_status_test`（状态行读回） |
| 44 | 边界 | 三键都不存在（全新用户）；另一现场 `btest.traversal` = `depth`、`btest.mode` = `maybe`（两个都是非法值）、`btest.on` = 字符串 `'yes'` | 读回 = 关 / `广度` / 写开关**未点选**（取值时解析 `btest.readonly`：true ⇒ 只读，§9.1）；非法值按「键不存在」处理，不报错、不阻断、不自动改写该键；只开一次会话、不点任何开关 ⇒ 三个键不出现（读取不写） | `btest_policy_test` |
| 45 | 边界 | 切进 btest（`btest.on` 写成 `true`）→ 切回 normal → 关掉会话重开 | `settings.json` 里 `btest.on` 键被删（写 `null`）；重开会话状态行不出现、模式 = 关；不读回旧的 `true` | `btest_policy_test`（删键 + 读回） |

## 8. 边界（本批不做）

- 不改外仓 `thincoder/`；不加 ACP 系统提示通道（二期）。
- 不改业务代码、不改数据库、不提交工单。
- 不改业务仓的设计档与冒烟清单：`expectFrom` 只读引用（档 + 节 / 清单行）；业务仓零写入，回写只落 QA 仓的预期文件（§3.4）。
- 不做截图证据；不做边走边停。
- 不自动创建业务数据（前置状态靠操作产生，或在文件里写清楚怎么建）。
- 不支持同一会话并行多条业务线的 run。
- 不在生产环境做写操作（用户未授权）。
- 不替代人工复验：报告是清单，不是结论。
- 权重表的条数不由 AI 改（AI 只追加「已修 / 已复现」）；不做设置页编辑面。
- 业务线不做成下拉控件（仍由用户句子说，理由见 §9.1）；三个 `btest.*` 持久化键（F11）的写入口只有切模式与两个状态行开关，设置页不为它们新增控件（§4 `browser_page.dart` 本批不动）。
- 待确认项的研判不在 run 内做（§3.10），也不由子代理改判定。
- 断点查明只回答问题、不操作浏览器、不改 `reason` / 判定；`cause` 内容真不真由走查（宿主只验形状，§3.9）。

## 9. UI / 交互决定（全部落地，无 open）

| 面 | 决定 |
|---|---|
| 模式入口 | composer 内核模式选择旁追加 `btest`，与 plan 同形；文案固定为 `btest`（不翻译） |
| 状态行 | btest 开启时 composer 顶部显示 `btest · <业务线> · <遍历> · <写> · run <id>`；无 run 时显示 `btest · 待开始 · <遍历> · <写>`；行右侧是两个弹出选择（§9.1）；切回 normal 整行消失 |
| 拒绝展示 | 以步骤失败卡出现，正文含动作、host、规则与「设置 → 浏览器 → btest」入口 |
| 设置页 | 浏览器段新增两块列表（允许域名 / 生产域名）+ 默认只读开关 + **QA 根目录**（`btest.qaRoot`，文本输入，可空）；允许域名空 = 全部浏览器动作拒绝；生产域名空 = 写动作拒绝；QA 根目录空 = 按 §3.4 四条分支派生（分支 2 时 = `<会话工作区根>/qa`，否则 = `<repoRoot 父目录>/qa`）；填了非绝对路径 ⇒ 起 run 时拒绝并点名该设置项 |
| 报告 | 会话正文一张表 + 三尾注；表头上方一行读数（`traversal` + 操作真实性）；无图片；不中途插入 |
| 退出 | 状态行消失；`D = 1` 时由下一个回合投出一行 `[btest-mode-card-off v1]` 中和语使卡失效（重进早于该回合 ⇒ 中和行丢弃，§3.2）；**再次切进 btest 时按 §3.2 判据**（`D = 0` ⇒ 重投一张卡；`D = 1` ⇒ 卡仍有效，不投）；run 未结束则下次进入先要求 `btest_run_end` 或作废 |
| 遍历策略入口 | 不进设置页：入口是状态行的「遍历」弹出选择（§9.1），`btest_run_start` 不带参数时取它的当前值；模型显式传 `traversal` 时以参数为准（§3.3）。值随开关持久化到 `btest.traversal`（§9.1「持久化」），设置页不为它新增控件。业务线不进这套控件，仍由用户句子说（§9.1 末段） |
| 权重表 | 不是设置项：路径随 `qaRoot`（§3.4），文件本身人可直接编辑；设置页只保留 `qaRoot` |

### 9.1 btest 状态行的两个开关（遍历 / 写）

**为什么写在 §9 而不是 §3.1**：§3.1 写会话状态与模式生命周期，控件形态与文案属于 UI 面，取值如何决定属于接口契约（§3.3 字段表后一段）。三处各管一件事，同一个值不写两遍。

**位置与形态**：composer 顶部已有的 btest 状态行右侧，紧跟现有文本。

**控件落点**：`lib/browser/btest/btest_status_switches.dart`（本批从 `composer.dart` 抽出：现存实现 `_buildBtestStatus` `lib/chat/composer/composer.dart:1932-2017` + `_btestSwitch` `:2019-2049`），`composer.dart` 只留 ≤5 行调用点。
两个**紧凑的弹出选择**（当前值 + 下拉箭头，点开二选一），不用按钮组——状态行很矮，两个按钮组会把它撑高。

**既有件三问（实读 2026-10-23）**：`existing: lib/chat/composer/composer_picker.dart:33` · name: `ComposerPicker` · consumers: `lib/chat/composer/composer.dart:2081`（内核选项）/ `:2091`（模式选项）/ `:2105`（权限选项），三处均以 `options` / `selected` / `onSelected` 三件套调用（2026-10-23 06:58 实读）。
形态 = 当前值 + 点开二选一 ⇒ **复用 `ComposerPicker`**，不新造控件；本仓 `lib/**` 里没有 `PopupMenuButton` / `DropdownButton` 的实例（2026-10-23 grep：零命中），所以也不存在「既有 Flutter 菜单控件」这条替代路。

**两个遍历标签的三问（2026-10-23 06:58 实读）**：`existing: lib/l10n/app_zh.arb:2925-2926` · name: `btestTraversalDepth`（`深度`）/ `btestTraversalBreadth`（`广度`）。
consumers: 状态行的两个 `ComposerPicker`（今日在 `lib/chat/composer/composer.dart:1969` / `:1975` 消费，本批随控件搬进 `btest_status_switches.dart`）。
写侧的两个选项复用既有 `btestFaceReadonly` / `btestFaceWrite`（`:1995` / `:2002` 消费）；四个标签都已落盘，本批不新建键。

| 开关 | 选项（中 / 英） | 对应的 run 取值 |
|---|---|---|
| 遍历 | `深度` / `广度`（英：`chain` / `surface`） | `traversal: chain` / `surface` |
| 写 | `只读` / `允许写`（英：`readonly` / `write`，复用既有键） | `mode: readonly` / `write` |

选项键 = **2 个遍历键**（`btestTraversalDepth` / `btestTraversalBreadth`，F9 已落）+ **写侧复用既有 2 个**（`btestFaceReadonly` / `btestFaceWrite`），不新建。**英文选项名 = run 取值**（`chain` / `surface` / `readonly` / `write`），中文只做翻译——一个值只有一个词，状态行与报告首行不再各说一套。

**文案（中 / 英各一句）**：

- 中文：`btest · 待开始 · 广度 · 只读`；运行中 `btest · 航次 · 广度 · 只读 · run 1`。
- 英文：`btest · not started · surface · readonly`；running `btest · Voyage · surface · readonly · run 1`。
- 选项名与取值的映射在模式卡里也写一条（§3.2：`深度` = `chain`、`广度` = `surface`、`只读` = `readonly`、`允许写` = `write`），模型读到的文案与 run 取值同源。
- 取值来源：**无 run ⇒ 两个开关的当前值；有 run ⇒ 本 run 的实际值**（显式参数压过开关时，行上显示实际跑的档位，不是开关的位置）——否则 run 进行中用户会读到一个与正在发生的事不一致的档位。
- **中 run 点击的语义（写死）**：点击只改会话开关的当前值，**只对下一次 run 生效**；本 run 的 `traversal` / `mode` 保持起 run 时的定值（返回项 1 与报告首行可核）。有 run 时行文显示本 run 的实际值 ⇒ 点完行文不变是预期行为，不是「点了没反应」。

**默认值与状态归属**：

- 遍历初始 = `btest.traversal`（键不存在 ⇒ `广度` = 内置 `surface`，与既有行为一致）。
- **写初始（唯一权威表述；§3.3 的优先级段与 ③ 档只引用本句）**：写开关在 `BtestState` 里的字段**可空**（`bool? _write`，`lib/browser/btest/btest_mode.dart:236`）；`btest.mode` 键不存在 ⇒ **开关保持未点选**（`writePicked` = false）。
  取值与状态行显示时解析 `btest.readonly`：true ⇒ `只读` / false ⇒ `允许写`（`btest.readonly` 缺省 = true，fail-closed）。点过一次以后 `_write` 有值，`btest.readonly` 不再参与。
- **与设置页「默认只读」的关系**：它是**未点选时的兜底**，不是覆盖开关的设置——`btest.mode` 一旦被第一次点选写入并持久化，此后任何会话都读它，设置页「默认只读」对取值与显示都不再有影响。
- **复位路径（唯一一条）**：删 `settings.json` 里的 `btest.mode` 键（明文 JSON，`User/settings.json`，`lib/settings/user_settings.dart:10`；`update(key, null)` 即删键，`:26-27`），重开会话 ⇒ 写开关回到未点选，「默认只读」重新生效。设置页不为它新增控件（§8）。
- 两个开关的当前值是会话状态：字段落 `BtestState`（`lib/browser/btest/btest_mode.dart:221`），`lib/chat/chat_session.dart` 只留访问器转发（`setBtest` 旁，`:190-214`）；跨重启靠下面三个键，不靠内存。
- **测试如何控制设置档**：两条既有夹具，不新造。① 读路径（缺省解析 / 未点选）用 `BtestSettings.values` 静态注入（`lib/browser/btest/btest_mode.dart:33`；`test/browser/btest_policy_test.dart:25` setUp 赋值、`:48` 置 `null` 还原，`test/chat/composer_btest_status_test.dart:16` / `:24` 同形）。
  ② 写路径（#43 要断言 `settings.json` 内容）用 `SettingsFiles.instance` 指向临时目录（可替换，`lib/settings/user_settings.dart:85-88`），真读写走 `settings.update`（`test/settings/browser_page_test.dart:104` 同形）。
- 切回 normal 时状态行整体消失，两个开关不单独显示。

**持久化（F11：全局设置，跨重启）**

| 键 | 类型 | 缺省（键不存在 / 值非法） | 写入点 |
|---|---|---|---|
| `btest.on` | bool | `false`（= 关） | 切进 btest ⇒ `true`；切到 normal / plan ⇒ 删键（写 `null`） |
| `btest.traversal` | string：`chain` / `surface` | `surface`（= `广度`） | 点「遍历」⇒ 取值的英文名（`chain` / `surface`） |
| `btest.mode` | string：`readonly` / `write` | 键不存在 ⇒ 开关未点选（见上「写初始」一句） | 点「写」⇒ `write` / `readonly` |

三个键与既有 `btest.allowHosts` / `btest.prodHosts` / `btest.readonly` / `btest.qaRoot` 同处（`BtestSettings`，`lib/browser/btest/btest_mode.dart:15-88`），读写都走它，不新增文件。

- **读（会话打开）**：落 `BtestState.fromSettings`（`lib/browser/btest/btest_mode.dart`）——取（或建）该会话的 `BtestState`，把三键直写进私有字段成为初值：`on` 与 `_traversal` 一定落实值；`_write` 只在 `btest.mode` 存在时落实值，不存在 ⇒ 保持未点选（见上「写初始」一句）。键缺失或值非法 ⇒ 回落缺省；非法值不报错、不阻断、不改写；读取本身不写任何键（不经 setter）。
- **会话层只转发**：`_openBtest`（`lib/chat/chat_session.dart:158-162`）只剩一行 `BtestState.fromSettings(...)` 调用，不直接读设置；`setBtest` / `setBtestTraversal` / `setBtestWrite`（`:172-214`）只转发到 `BtestState` 的字段 / setter，不直接写设置。`BtestMode.settingKey`（`btest`）随之无引用，删掉。
- **写（每次改值）**：落 `BtestState` 的三个 setter（`set on` / `set traversal` / `set write`，`lib/browser/btest/btest_mode.dart:227-252` 现址）——各写自己的键（`on` ⇒ `true` / 删键 `null`；遍历 ⇒ `chain` / `surface`；写 ⇒ `write` / `readonly`）；删键用 `null`（`SettingsFiles.update` 的 null 语义，`lib/settings/user_settings.dart:26-27`）。
- **失败口径**：`unawaited(settings.update(key, value).catchError((Object error) { debugPrint('btest.<key> not kept: $error'); }))`——**显式闭包**，与 `ColorThemeSettings.storeColorTheme`（`lib/settings/user_settings.dart:160-166`）同一形态；写失败只留一条 `debugPrint`，界面与本次会话照常（内存值已改），下一会话读到旧值。
- **缺省行为不变**：三个键都不存在（全新用户）= 关、`广度`、`btest.readonly` 缺省 → 只读，与今天的表现一致。

**为什么业务线不做成下拉**：`line` 来自用户句子（如「跑航次线」），模型的上下文里已有；下拉要先知道 `repoRoot` 才能列出 `<qaRoot>/<仓名>/*.md`，会逼用户先说仓、再选线——多一步有交互成本的操作，换不到信息。

## 10. 未核实项与上抛项

1. **[上抛·待裁] 每次 run 起始的一行提醒**（"先读返回项 2 的绝对路径"）是否算"重复注入"。本设计按"不算"处理（它不是模式卡，约 2 行）；若要求严格零重复，改为不注入，代价 = 漂移兜底只剩 run 闸与 `btest_run_end` 检查表。**不阻塞本批实施**：它是一行附加注入，不参与任何判据；裁否时删这一行即可，工具面、检查表、验收读数都不动。
2. **自动放行应答点（已实读，2026-10-22）**：内核审批点 `_serverRequest`（`lib/kernel/thincoder/thincoder_kernel.dart:1040-1080`）**拿得到工具名**（`toolCall['title']`）、**拿不到结构化参数**（只有 `content` 预览文本）⇒ 它只负责在 btest on 时对 browser 组答 allow、压掉审批卡；
   放行 / 拒绝判据全部落在浏览器工具的 `run` 包装（`lib/browser/browser_tools.dart:115-130`，name + arguments 都在；§3.7 落点段）。
   **残余未核实**：内核是否对 MCP 工具发 `session/request_permission`（外仓 `thincoder/` 不在本机）。**两个分支下 btest 的读数相同**——发请求 ⇒ 钩子答 allow（零卡）；不发 ⇒ 无请求（零卡）。用例 #1 因此无条件成立；写动作的"禁止"不依赖这一层（规则 B 已在工具 `run` 层硬拒绝，§3.7）。
3. **unverified**：`HostMcpServer` 是否按会话暴露工具列表（决定 btest 工具会不会对普通会话可见）；实施前实读 `lib/host_tools/host_mcp_server.dart`。当前设计按"全局注册 + 会话级判据"处理，普通会话调用会被拒。
4. **已核实（2026-10-23 实读）`HostToolCall.cwd` 的 thincoder 来源链**：`lib/kernel/thincoder/thincoder_kernel.dart:353` 发放 grant（`HostMcpServer.issue(_sessionId ?? '', _cwd)`）
   → `:231` `_cwd = _context.cwd ?? _context.resume?.cwd ?? '.'` → `lib/host_tools/host_mcp_server.dart:186` 构造 `HostToolCall(cwd: grant.cwd, …)`。
   结论：btest 路径会填 `cwd`，分支 2 / 3 可达；链尾 `'.'`（任何非绝对路径同理）⇒ 判「工作区根不可得」，落分支 4 并在返回项 2 的「降级原因」里点名（§3.4「链尾是 `'.'`」），不静默退成兜底。
   `HostToolCall` 的另外两处构造不改 `cwd` 来源：`lib/host_tools/host_tools.dart:218` 把入参 `call.cwd` 原样转给 `tool.run`；`lib/kernel/claude_code/claude_code_kernel.dart:1766` 是控制通道构造（`cwd: _cwd`）。
5. **unverified**：业务仓 `v2-booking` 的 dev 域名与生产域名清单，由用户在设置页填；设计不写死域名。
6. **[上抛·知会] 拆分登记 SPLIT-1…6**（§4）：设计位无台账写权，登记行由主编排方落（挂 #149 的后续批）。SPLIT-5 / SPLIT-6 本批落地，SPLIT-1…4 留登记。
7. **unverified：强来源的覆盖率**——业务设计档里有多少节写的是期望行为而非实现方式，本批未逐档核实。设计不假设覆盖率高：找不到强来源按 §3.4 硬规则 2 降级到「中」或标 `无权威来源`；首个 run 的「需要用户补规则的清单」就是覆盖率读数。
8. **已裁定（不再待裁）：`browser_evaluate` 的 `readOnly` 参数**——该工具的 schema 只有 `tabId` / `expression`（`lib/browser/browser_tools.dart:297-303`），既有只读轮规则此前无法落地；主 agent 2026-10-23 00:42 改判为**新增该参数、按设计实现**（批档 §1「裁定改判」），§5 已实现（`browser_tools.dart` 增 `readOnly`）。**不阻塞本批实施**：退回「不补」只影响只读轮对 evaluate 的宽度，工具面与其余判据不动。
9. **[上抛·待裁] 「按文字找不到可点目标」判不了**：宿主只看到调用参数，看不到那个元素当时有没有可见文字 ⇒ 替代 = ref / `selector` 兜底计数（§3.3 检查表 4-③）+ 报告步骤列写理由 + `browser_history` 的 clicks 对账（`lib/browser/browser_history.dart:537-547`）；代价 = 这条靠走查，不是硬闸。
10. **unverified：权重表的条数**——聚类读数（924 条 → 八类 58 / 52 / 40 / 35 / 31 / 24 / 22 / 20）来自主 agent 对 `issues-v2dev.json` 的实测（2026-10-23），设计位未复算；语料重跑后数字可变——权重表是数据（人可改），不是判据。
11. **设计已定：权重表的两条补充语义**——「`已修` 的类排到生效序末尾（仍摸一次）」与「AI 只追加标记、不改条数」。**理由**：不把已修类排末尾，权重表的排序就退化成「永远先查修好的地方」，与「别忽略没修的地方」相反；允许 AI 改条数，历史密度就不再是可复核的读数（KD-24）。**代价**：`已修` 标记是人的判断，写错一个类名就会让该类的降级失效——所以按 §3.9 逐字匹配 + 匹配不上打一行 warning 点名，让漂移看得见。
12. **设计已定：报告两列**——「判定」（`预期不符` / `待确认`）与「建议」（run 之后研判回填），以及 `unconfirmedDiffs[].kind` 的两值（`diff` / `pending`）（KD-26）。**理由**：判定是「算不算缺陷」、建议是「倾向怎么判」，两者混在一格时用户看不出哪一格是锚点；`kind` 两值让载荷与三尾注一一对应。**代价**：报告表宽 13 列（含行号），窄屏要横向滚；`待确认` 行的建议在研判回来之前是空档（写 `待研判 · <原因>`，§3.10）。
13. **已裁定（2026-10-23 06:55，主 agent）：SPLIT-5 到期，本批先拆后加**。`btest_mode.dart` 实测 1131 行（2026-10-23 06:58 复核），已越过登记的 1100 触发线。本批第一步按 SPLIT-5 抽 run 生命周期（两档，拆法见 §4），第二步才落 F11 的三个键（拆后 ≤ +40）。>800 不设例外通道。
