# 2026-10-26 · upstream-merge-72
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 08:21「先小修，然后合并上游」；小修批已于 09:00 收口，本批为其后继。分叉现状：领先 144 / 落后 72，merge-tree 试算 16 档冲突。。
> 台账 = #181（thincoder-adapter · 归批）。前情 = docs/batches/2026-10-26-small-fixes.md §6（已收口 2026-10-26）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 讨论与策略（主 agent，2026-10-26 09:05，用户休息中，仅摆材料不动代码）

**用户原话**：「兼容的话会不会更好兼容上下游的更新了呢」「我之前将两者融合的太脏了」「先小修，然后合并上游」「kimi做完之后，让kimi来做接下来的任务落实吧」。

**现状读数**（父侧实跑）：`HEAD` 领先上游 144 / 落后 72；`git merge-tree --write-tree HEAD origin/main` 试算 **16 档冲突**；上一批记着 10-22（28 提交撞 13 处）与 10-26（6 提交撞 11 档后 abort）——**撞的总是同一批文件**。

**两份独立咨询，结论一致 = A（上游优先），且都要求「严格形态」**

| 来源 | 结论 | 独有论据 |
|---|---|---|
| deepseek-flash（#49，因 kimi 429 降级） | A | 冲突面与价值面错位：自有资产（thincoder 27 档 / btest 9 档 / session 8 档 / 三个看门狗 / 进程代理）**在 16 档冲突里一次都没出现**；冲突档内属我们的只有数百行 UI/接缝 |
| kimi（#50，k3.1-pro） | A | **这条原则需求档早已写明**：`docs/requirements/thincoder-adapter.md:197-207` 要求「thincoder 代码集中于独立模块，宿主既有文件只留可辨认的接线点」；并指出 `lib/chat/session/mode_state.dart:1` 仍是 `part of '../chat_session.dart'` ⇒ **拆 part 文件不等于隔离** |

**必须遵守的四条（两位共同点 + kimi 的补强）**
1. **不是 `--theirs` 一键了事**：共享档整档取上游，自有功能在**新的独立模块**里重接；`lib/kernel/thincoder/**`、`lib/browser/btest/**`、`lib/diagnostics/**`、`lib/platform/process_host*.dart` **绝不整档取上游**。
2. **l10n 只并集源档**（`app_en.arb` / `app_zh.arb`），生成档用 `flutter gen-l10n` 重生成，不手解冲突、不选边。
3. **测试归属分离**：上游的两个 SCM 测试档保持上游版；自有断言另建功能测试档（如 `scm_fetch_button_test.dart` / `git_autofetch_test.dart`）。
4. **落一张登记表**（flash 强调「没有这张表，A 两三次合并后会退化回 B」）：`docs/design/fork-deltas.md`，表 = 文件 / 我们的块 / 类型（修 bug · 功能 · 内核适配）/ 接缝 / 行数预算；规则 = 表外不许改上游档。**该档属设计面，由 eng-designer 写。**

**阻塞项（用户裁定前不得动 SCM 面）**：#181「获取 = fetch + merge」（2026-10-19 用户定）与上游 Fetch/Pull 分开的取舍。已入台账（条件触发），待裁。

**下一步（用户醒来后按序）**：① 裁定 #181 → ② 派 eng-designer 写 §2 任务书 + `docs/design/fork-deltas.md` 框架 → ③ 用户发设计评审 → ④ 批准 → ⑤ 实施轮派 kimi（`kimi-code:k3.1-pro`；429 则降级 flash 并在此记录）。

### 合并已落地于分支，现在要的是重接设计（主 agent，2026-10-26 18:35 起，19:15 更新）

**用户裁定**：18:15「让kimi来获取上游直接合并」· 19:14「继续做…让kimi设计合并」⇒ 合并操作已执行，语义重接交 kimi 设计。

**已完成的机械合并**（分支 `merge/upstream-20261026`，提交 `be89876a`；`main` 未动 = `26c969aa`；备份 `backup/pre-upstream-20261026`）：
- 上游 112 提交全部合入；17 档冲突按 A 策略解决：**共享档整档取上游**（含 `lib/ide/git/ide_scm_view.dart`、`lib/workbench.dart`、`lib/chat/chat_session.dart`、`lib/chat/composer/{composer_picker,session_model_picker}.dart`、`lib/ide/{ide_editor,ide_workbench}.dart`、`lib/browser/browser_tools.dart`、两个上游 SCM 测试档、`test/chat/side_panel/side_panel_test.dart`）。
- l10n：**键级并集**（`app_en.arb` 补回我们独有 139 键 · `app_zh.arb` 补回 78 键；同名沿用上游措辞），生成档由 `gen-l10n` 重生成。
- 上游最新已追平（`git rev-list --count 07643543..origin/main` = 0）。

**编译现状（实跑 `flutter analyze --no-pub`）：390 error = 333 in `lib/` + 57 in `test/`；另有 104 warning/info。**
`lib/` 侧集中在：
| 计数 | 档 |
|---|---|
| 76 | `lib/chat/session/kernel_proxy.dart` |
| 65 | `lib/chat/session/transcript_proxy.dart` |
| 42 | `lib/chat/session/mode_state.dart` |
| 35 | `lib/chat/session/file_edits.dart` |
| 15 | `lib/browser/browser_tools.dart`（上游已改写该档） |
| 11 | `lib/chat/session/send_contexts.dart` |
| 10 | `lib/browser/browser_debug_tools.dart` |
| 9 | `lib/browser/browser_actions.dart` |
| 9 | `lib/chat/session/lifecycle.dart` |
| 8 | `lib/chat/composer/composer_view.dart` |
| 7 | `lib/chat/session/file_paths.dart` |
| 7 | `lib/browser/btest/btest_status_switches.dart` |

**根因**：`lib/chat/session/**` 现为 `part of '../chat_session.dart'`，依赖上游 `ChatSession` 的私有成员；上游重写后全部断裂。这正是 kimi 在 #50 指出的「拆 part 不等于隔离」。

### 设计任务（交 eng-designer，模型 kimi）

1. **产出一份重接设计档**：把 `lib/chat/session/**` 从 `part of` 寄生体改成**可独立 import 的模块 + 一个 overlay 接口**（定义：ChatSession 暴露什么通用生命周期缝、我们注入什么、谁持有状态），并给出 `lib/browser/**` 三个档（browser_tools / browser_debug_tools / browser_actions）与 `composer_view.dart` 的接法。
2. **产出 `docs/design/fork-deltas.md` 登记表**：列 = 文件 / 我们的块 / 类型（修 bug · 功能 · 内核适配）/ 接缝 / 行数预算；规则 = **表外不许改上游档**。
3. **产出 §2 任务书**：按可执行轮次切分（每轮 ≤15 档、单一改动面），每轮写明落点 `file:line`、验收命令、禁改范围与后果。
4. **不得**把上游档改回去（`ide_scm_view.dart` 等保持上游版）；自有能力只经新模块与接缝存在。
5. 兼容既有裁定：`#181`（SCM 获取语义）**仍待用户裁定**，设计中按「留接缝、不预判」处理。

### 设计续作（主 agent，2026-10-26 19:56）

**上一轮 eng-designer（kimi）在 19:54 被 429 中断**（第 12 轮，已写 36 分钟）。用户 19:50 指示换第三个 key 继续设计；该 key 经直连探测 **HTTP 200 有额度**，已热应用到主 provider（`settings set providers.2.apiKey`，值不回显）。

**已落盘的进度（续作从此接着做，不重来）**：
- `docs/design/fork-deltas.md` —— **已写完，70 行**：规则（表外不许改上游档 · 自有档不得整档取上游 · l10n 只并键 · 上游测试与自有断言分档）+ 整档自有资产表（含 `lib/chat/session/**` 与 `lib/chat/chat_session_overlay.dart` 的接缝 `chat_session_overlay.dart`）。
- `docs/design/thincoder-adapter.md` —— 已修改（适配层设计面，增量待核）。
- **§2 仍为空** ⇒ 续作必须补齐 §2 任务书。

**续作要求**：① 复核 `docs/design/fork-deltas.md` 是否覆盖了 390 error 涉及的每个断点（`lib/chat/session/**` 7 档 · `lib/browser/**` 3 档 · `composer_view.dart` · `lib/browser/btest/**`）；② 写出 overlay 接口的具体形状（ChatSession 暴露什么 · 我们注入什么 · 谁持有状态）；③ 补齐 §2 任务书，按轮次切分、每轮 ≤15 档、写明落点与验收命令。

### 设计续作 2（主 agent，2026-10-26 20:35）— kimi 配额耗尽，降级 flash

**降级事实（明写，不静默）**：kimi 三个 key（`kimi-code` / `-2` / `-3`）在同一 5 小时窗口内全部 429，eng-designer #2 于 20:33 中断。按用户 08:40 规则「关键时刻用 kimi，其余 flash」，设计收尾轮降级 **`deepseek:deepseek-flash`**。

**已落盘**：设计主体 = `docs/design/thincoder-adapter.md` §29（29.1–29.9 完整：接口契约 `ChatSessionOverlayHost`/`ChatSessionOverlay`、模块归属、R1 12 档 / R2 6 档、验收命令、决策记录、用例表、RTM 4-1）。`docs/design/fork-deltas.md` 已写。
**未落盘**：批档 §2 任务书；文档门 40 处超长段落（kimi 已清 4 条，剩余 40 条的 `file:line` 已由父侧 `doc_check` 取到）。

**本轮授权（有界）**：只做两件事 —— ① 按 §1 先前五条边界，对 40 处段落做**机械换行**（只拆不改字，不碰 §29，跳过表格/代码块）；② 通过后按 §29.5 写 §2，只引用不复制。不得改设计语义、不得动代码。

### 状态订正（主 agent，2026-10-26 20:40）

前文两处已过时，此处订正（前文保留作为当时记录）：

- 「§2 仍为空 ⇒ 续作必须补齐」/「未落盘：批档 §2 任务书」 —— **已落盘**：§2 现有 B1–B5 五条、R1（12 档）/ R2（6 档）两轮、禁改范围与上抛，状态行「设计完成」。
- 「文档门 40 处超长段落」 —— **已清零**：40 段机械拆分（只多换行、未改字、§29 未动），`doc_check` 交付门 **PASS**（2 档 0 命中）。

**设计面就绪结论（父侧核验）**：设计主体 = `docs/design/thincoder-adapter.md` §29.1–29.9（接口契约 `ChatSessionOverlayHost`/`ChatSessionOverlay` · 模块归属表 · R1/R2 落点与验收命令 · 决策记录 · 用例表 · RTM 4-1）；登记表 = `docs/design/fork-deltas.md`；任务书 = 本档 §2。三者互相对上：§2 的 12 档与 6 档逐档指向 §29.5，未复制行数表。

**下一节点**：用户发设计评审（`advisor type=design`，`documents` = 上述两档，`batchDoc` = 本档）。

### 披露：父侧在本档做了 6 行纯路径修正（2026-10-26 20:42）

`doc_check` 交付门首跑 **REFUSED（锚 7 条）**：本档内 §1/§2 多处写了裸名 `fork-deltas.md` / `thincoder-adapter.md`，门要求指针可解析（裸名不跨目录解析）。父侧对 6 行做了**只补目录前缀**的修正（`docs/design/…`），**未改任何语义、未改 §2 的条目/轮次/判据**。复跑 **PASS（0 命中，3 档全清）**。

**这是父侧笔触到 §2 的一次，据实登记**：动的是指针写法，不是设计内容；若后续评审认为 §2 行文需改，仍由 eng-designer 修订。

### 设计评审裁决（主 agent，2026-10-26 20:47）

评审 `a18a06c9` 结论 **changes-required**（🔴 1 · 🟡 4 · 🔵 2，未签发设计令牌 ⇒ 实施保持封住）。逐条裁决，全部文档面，一轮修完：

| # | 裁决 | 要修什么（交 eng-designer） |
|---|---|---|
| 1 🔴 | **接受** | `docs/design/fork-deltas.md` §3 补 4 行：`lib/settings/pages/general_page.dart`（我们的块 = thincoder 设置组，类型 = 功能，接缝 = 设置页，预算 ≤+81）· `lib/chat/chat_screen.dart`（`canStopTasks` 单行接线，修 bug，≤+2）· `lib/kernel/mock/mock_kernels.dart`（thincoder 描述符，内核适配，≤+16）· `lib/platform/data_dir.dart`（路径接缝，修 bug，≤+2）。**或**把 §1 覆盖口径改成「§3 只登记 R1/R2 面、其余以设计档 §5.2 为准」——二选一，但必须只留一个出处。实核坐标：`general_page.dart:442`、`chat_screen.dart:603`、`mock_kernels.dart:34`。 |
| 2 🟡 | **接受** | §28.8 ② 补 `lib/kernel/thincoder/thincoder_title.dart`（`part of 'thincoder_kernel.dart'`，现值 ≈85，delta ≈+12），或把落点改写成「kernel + title(part)」，使 `_pumpTitle` 可按符号找到。 |
| 3 🟡 | **接受** | §29.1 / §29.3 给 5 个新名字各补三问答复（`ChatSessionOverlay` · `ChatSessionOverlayHost` · `BaocodeSessionOverlay` · `lib/chat/session/overlay.dart` · `lib/browser/btest/btest_tool_gate.dart`）。 |
| 4 🟡 | **接受** | §28.6 末补 RTM 增量一句（不改 1-1/2-1/3-1 且不加行 + 理由，或补一行用例），形制照 §29.9。 |
| 5 🟡 | **接受** | §29.5 把「后续另批」改成可核形状：拆分单元（facet / review / send）+ 触发判据（任一段被本批以外触碰即立拆分批）+ R1 净增的代价说明。 |
| 6 🔵 | **接受** | §28.5 / §28.8 ⑤ 坐标改为 `composer_editing.dart:442`，注明 `hasCommandSource` 由 R1 恢复。 |
| 7 🔵 | **接受** | §5.2 体量立场加总则：各行数 = 该节编制日快照、跨节不互校、实施首轮以 `wc -l` 复核。 |

**边界**：只改上述七处文档；不动 §29 的设计语义、不动代码、不改 `test/RTM.md` 实况数字。修完自跑 `doc_check(gate)` 须 PASS。

### 修轮核验（主 agent，2026-10-26 20:52）— 七条实测通过

| # | 核验点 | 实读 |
|---|---|---|
| 1 🔴 | 登记表补 4 行 | `docs/design/fork-deltas.md:41` chat_screen / `:45` data_dir / `:49` mock_kernels / `:52` general_page，类型与预算齐 |
| 2 🟡 | 拆出 part 档 | `thincoder-adapter.md:4387`（② 改为委托）/ `:4388`（②a `thincoder_title.dart` 84 行） |
| 3 🟡 | 三问答复 | `:4440`（OverlayHost none found）/ `:4534` `:4535` `:4536`（BaocodeSessionOverlay · overlay.dart · btest_tool_gate existing but unusable） |
| 4 🟡 | RTM 增量 | `:4360`「本批不加行，索引仍是 3 / 50–100；4-1 由 §29.9 立、随 R2 落地」+ 理由 |
| 5 🟡 | 拆分单元 + 触发 | `:4589`（facet / review / send 三段）/ `:4593`（触发判据：任一段被本批以外改动触碰即立拆分批） |
| 6 🔵 | 坐标订正 | `:4336` 已改 `composer_editing.dart:442`（另 `:4358` / `:4372` 同源引用一并订正） |
| 7 🔵 | 行数总则 | `:347`「各行数 = 该条编制日快照；跨节不互校；实施首轮以 `wc -l` 复核，冲突以复核值为准」 |

**本轮新发现的小瑕（未修，记在册）**：`thincoder-adapter.md:348` 写「只走接线 ⑬」，而 §5.2 表只到 ⑫（⑬ 定义在批 4 接线点表 `:684`）—— 指针写法问题，不影响语义，留待下一修轮或评审提出时一并处理。

**状态**：🔴 已清，等待用户发**第二轮设计评审**（验上表 + 抓明显新问题）以取得设计令牌。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（评审 7 条已修（设计档 §5.2 / §28.5 / §28.6 / §28.8 / §29.1 / §29.3 / §29.5 + fork-deltas §3 四行）；R1 / R2 的条目、落点与判据未变）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目与同源设计

本批把已合入的上游与自有能力重新接合，不回退共享上游文件。需求条目、设计验收与下表同源；权威设计为 `docs/design/thincoder-adapter.md` §29，共享文件登记为 `docs/design/fork-deltas.md`。

| 条目 | 覆盖需求 | 执行轮 | 完成判据 |
|---|---|---|---|
| B1 上游共存边界 | `docs/requirements/thincoder-adapter.md` §4 E1/E2、§7 A10 | R1 | session 自有档均可独立 import；私有宿主成员访问与 `part of '../chat_session.dart'` 清零；所有共享档接缝均登记 |
| B2 既有会话能力恢复 | 同档 F25/F26 与 §5 图片、编辑上下文映射 | R1 | 改名、命令源、图片与 editor context 的既有定向测试恢复；无能力内核不伪造上下文或回退入口 |
| B3 btest 同会话状态 | `docs/requirements/browser-biz-test.md` §3 F1/F2/F9/F11、§5 第 1 / 7 项 | R1 + R2 | composer、发送提示与浏览器工具门读同一 overlay 状态；开关、run 与持久化行为不回退 |
| B4 浏览器宿主工具重接 | `docs/requirements/host-tool-channel.md` §3 F1/F2/F3、§5 A1/A2/A3 | R2 | 浏览器与 btest 工具经 `HostTools` 注册；schema、数字归一、目标 host 与拒绝门保持；通用 HostTools 无 browser 特判 |
| B5 业务集成回溯 | `test/RTM.md` 既有 1-1 / 2-1 / 3-1 与新增 4-1 | R2 + 父侧收口 | 既有行业务断言不改；4-1 从 composer mode picker 进入并断言跨组件业务结果 |

### 执行轮、落点与禁改

- **R1 = ChatSession overlay，12 个改动档**。逐档 `file:line` 落点、现行行数、delta 与定向验收命令见设计 §29.5 R1；接口形状与调用顺序见 §29.2，状态 owner 见 §29.3。禁改 SCM、browser、composer 产品文件、上游 picker 与外仓；`composer_view.dart` / `btest_status_switches.dart` 只能由 session 契约恢复，不改 UI。
- **R2 = browser 宿主工具重接，6 个改动档**，须在 R1 完成后实施。逐档落点与验收命令见设计 §29.5 R2；注册与 gate 顺序见 §29.4。禁改 `HostTools` 通用语义、`browser_actions.dart`、`browser_debug_tools.dart`、宿主 MCP 暴露规则、Claude 审批路径与 SCM。
- 两轮都不新增配置项或 UI 入口；两轮合计的完整受影响面也不得分拆出第三个实施轮。每轮的测试只跑该轮改动面；全量 analyze 与集成套件由父侧收口运行。

### 明确不在本批

- `ide_scm_view.dart` 及其它 SCM 产品语义；#181「获取 = fetch + merge」仍待用户裁定，本批只保留接缝，不预判 Fetch/Pull。
- 被覆盖的旧共享档恢复、上游 picker 布局、外仓改动、上游测试改写、通用 HostTools 语义改动。
- 不为消除行数而再拆上游 `ChatSession` 类；共享文件只受 `docs/design/fork-deltas.md` 的净增预算与登记接缝约束。

### 关键决策与上抛

- 采用每会话组合 overlay：上游持有 transcript、活动内核、review 与视图计数；自有模块只经公开 host 与生命周期钩接入。理由与被否方案见设计 §29.1 / §29.6。
- 共享文件改动的唯一登记面是 `docs/design/fork-deltas.md`；实施遇到表外改动必须停下，先回设计登记，不得直接加接线。
- **[上抛·待裁]** #181 不在本批裁定；若实施需要改变 SCM 获取语义，立即停止该部分并回主 agent。
- 验证边界：本轮是设计续作，未重新运行 390-error 基线；该基线来自批档 §1 父侧实跑。R1/R2 的实施验收以设计 §29.5 的命令与实跑结果为准。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

设计评审（docs/design/thincoder-adapter.md + docs/design/fork-deltas.md，全文实读；抽检代码：test/RTM.md 3 行 / 54 行、chat_session.dart 1266 行、lib/chat/session 八档 `part of`、composer_editing.dart:442、thincoder_title.dart、PROJECT-MANIFEST.json:35 publicRepos 为空、§29.5 点名的测试档全在盘）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Document ownership | 🔴 | fork-deltas.md 与设计档对「哪些共享上游档携带 fork 块」给出两套口径：fork-deltas.md:7「表外不许改上游档」、:8「表外共享文件是只读上游面」，而 §3 表（:36-:49）无 general_page.dart / chat_screen.dart / mock_kernels.dart / data_dir.dart 行；设计档同时记录这些文件的自有块：:311（⑦ general_page +≤81）、:314（⑩ data_dir）、:313（⑨ mock_kernels）、:684（⑬ chat_screen）。实reader核：general_page.dart:442-450、chat_screen.dart:603、mock_kernels.dart:34-40 确有自有块 | 在 fork-deltas §3 补 4–5 行（文件 / 块 / 类型 / 接缝 / 行数预算），或把 §1 改成「§3 只覆盖该批面、其余接线以设计档 §5.2 为准」——两者取一，使两档不再各自定义同一张表 |
| 2 | Clarity（受影响档清册） | 🟡 | §28.8 漏 `lib/kernel/thincoder/thincoder_title.dart`（改名实现已在该 part 档：thincoder_title.dart:1 `part of 'thincoder_kernel.dart'`、:10 `renameConfirmedOf`、:38 `_pumpTitle`），而 §28.8②（:4380）把 `_pumpTitle` / `_titleConfirmed` 全记在 `thincoder_kernel.dart`（480 行）名下 | 表里补一行（现值 ≈85 / delta ≈ +12），或把 ② 的落点写成「thincoder_kernel.dart + thincoder_title.dart（part）」 |
| 3 | Existing-piece（criterion 11） | 🟡 | §29 未给新名字的三问答复（`ChatSessionOverlay` / `ChatSessionOverlayHost` / `BaocodeSessionOverlay` / `lib/chat/session/overlay.dart` / `lib/browser/btest/btest_tool_gate.dart`）；§28.3（:4203-4207）有该形，§29 没有 | 在 §29.1 / §29.3 各补一句 `existing: … ∥ none found: … ∥ existing but unusable: …`（例：btest 门可写「existing but unusable：`BtestGate.check` 判据在，调用包装住 browser_tools 父库」） |
| 4 | Integration-test design | 🟡 | 批 22（§28）未写它对 `test/RTM.md` 的增量：§21.7（:2640）/§22.12（:3036）都写了「本批不新增业务场景 + 原因」，§28 一句都没有，而 §28 改动了一个业务可观察结果（改名后侧栏/列表标题） | 在 §28.6 末尾补一句 RTM 增量（不改 1-1/2-1/3-1、不加行 + 理由，或补一行），与 §29.9 同形 |
| 5 | Scope / size plan（criterion 8 + 体量裁定） | 🟡 | §29.5（:4566）对 `chat_session.dart` 1266 → ≈1366（>800 硬顶）只写「先把 fork 私有逻辑移入独立模块，后续另批」，无触发判据、无立项名；R1 净增 ≈ +100 反而把它推高，与「>800 必拆」的硬口径之间只剩一句无判据的承诺 | 给出可核触发（例：「facet / review / send 三段中任一段被本批以外触碰 ⇒ 立拆分批」），并说明 R1 的 +160/−60 里哪部分是把上游类留在原档的代价 |
| 6 | Doc accuracy（坐标漂移） | 🔵 | §28.5（:4335）/§28.8 ⑤（:4383）把命令面板开关算在 `composer.dart:863-877`；该表达式实际在 `composer_editing.dart:442`，且 `ChatSession.hasCommandSource` 全仓只此一处消费者（该 getter 合并后尚未恢复）。§29.4（:4543）说对了，§28.5 说成既有面 | 把 §28.5 / §28.8 ⑤ 的坐标改为 `composer_editing.dart:442`，并注明 getter 由 R1 恢复 |
| 7 | Doc-state（数字漂移） | 🔵 | 同一档多处「本轮实测」互不一致：`chat_session.dart` :4381 记 794（10-23）/ :4553 记 1266（10-26）；`thincoder_kernel.dart` :4380 记 480 / :351、:354 记 1296。两值都能被日期解释，但档里没有跨节总则（§23.3 :3122 只在单节写了） | 在 §5.2 体量立场加一句总则：各行数 = 该节编制日快照、跨节不互校、实施首轮以 `wc -l` 复核为准 |

计数：🔴 1 · 🟡 4 · 🔵 2。抽检结论：§29.5 R1/R2 的行数标注与盘上实况相符（chat_session.dart 恰 1266；lib/chat/session 八档 `part of` 与 §29.1:4427 一致；R1/R2 验收点名的测试档全部存在，唯一新增档 `test/chat/session_overlay_test.dart` 尚未在盘）；§29.9 的 RTM 起点（3 行 / 54 行 / 新增 4-1 / 规模 3→4 在 50–100 窗内）与 `test/RTM.md:9`、`:49` 逐条对上；验收命令是改动面测试档清单而非全量套件（全量 analyze + 集成归父侧收口线），不构成「把发布门写成回合成本」。

VERDICT: changes-required

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
