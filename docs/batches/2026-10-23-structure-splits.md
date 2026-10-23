# 2026-10-23 · 结构拆分：越界档先拆
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-23 · 来源 = 用户 2026-10-23 07:21「开」；台账 #22（kernel 1453 > 预算 1345）与 #150（四个 >800 档）。
> 台账 = #22 + #150（core · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 已定决定（2026-10-23 07:21）

- **已定决定**：先拆已越界的两个档（`thincoder_kernel.dart` 1453 > 预算 1345；`step_folds.dart` 501 > 500），再拆 #150 的四个 >800 档；**拆分是纯结构搬运，不改任何行为** · 用户原话：「开」· 时间：2026-10-23 07:21

## 实测基线（2026-10-23 07:24，node 计数手尾行）

| 档 | 现行 | 界 | 状态 |
|---|---|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | **1453** | 设计 ㉓ 预算 ≤1345 | **超 108 行** |
| `lib/chat/step_folds.dart` | **501** | 500 | **超 1 行** |
| `lib/chat/composer/composer.dart` | **2467** | 800 | 超 1667 |
| `lib/chat/chat_session.dart` | **1493** | 800 | 超 693 |
| `lib/chat/chat_models.dart` | **840** | 800 | 超 40 |
| `lib/ide/git/ide_scm_view.dart` | 4313 | 800 | 超 3513（#47 结构批已登记） |

## 约束

1. **行为零变化**：只搬代码，不改语义；每个被搬动的符号保持公开签名（`part` 或新档 + `export` 二选一，设计轮定）。
2. **一次一批只动一个档**：四个大档同一批拆 = 一次撞四个面，回滚粒度太粗。
3. **每档拆后 ≤500**（`step_folds` 按 #72 拆「边界并集段」后可回 500 以下）。
4. **测试档不动**（`thincoder_kernel_test.dart` 4814 行另议，见 #150 备注）。

## 更正（2026-10-23 07:26，主 agent 自纠）

本节上方的基线表与约束里，凡涉及 btest 三档的说法**以本段为准**：

- **SPLIT-5 / SPLIT-6 只有设计，没有实现**。设计档已批准「先拆后加」，实施轮 **#55** 尚未落盘：实测 `lib/browser/btest` 只有 5 档（`btest_mode` **1132** 行），`btest_run_state.dart` / `btest_run_end.dart` / `btest_status_switches.dart` **不存在**；`composer.dart` 的 `_buildBtestStatus` / `_btestSwitch` 仍在 `:1932-2050`。
- 因此本设计（#56）**不得**把 btest 三档当先例；先例改用 `thincoder_choices.dart`（`part` + 一行委托）。
- `composer.dart` 里 btest 状态行那一段**归 #55 所有，本批不动、不替它定缝**。
- 台账 #150 的同一句已同步更正。

**教训**：设计批准 ≠ 代码落地。把两者当同一件事写进台账，会让下一轮的人（包括我自己）按不存在的实现做判断。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（设计档 docs/design/structure-splits.md · 机检 PASS）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

| # | 条目 | 覆盖 |
|---|---|---|
| 1 | `thincoder_kernel.dart` 1461 → ≤500 | 是（设计 §4.1，九段） |
| 2 | `step_folds.dart` → ≤500（#72 边界并集段） | 是（设计 §4.2） |
| 3 | `composer.dart` 2466 → ≤800 | 是（设计 §4.3，六段） |
| 4 | `chat_session.dart` 1492 → ≤800 | 是（设计 §4.4，四段） |
| 5 | `chat_models.dart` 839 → ≤800 | 是（设计 §4.5，一段） |
| 6 | `ide_scm_view.dart` 4313（行数界之外） | **不在本批**（#47 另批） |

### 设计档落点

`docs/design/structure-splits.md`（新档，跨板块结构治理；八项齐：目标 / 基线 / 机制选型 / 缝表 / 排程 / 验收 / 案例 / 决策）。

### 机制设计（一句话）

有私有耦合的档（kernel · step_folds · composer · chat_session）用 `part` + 顶层函数 + 一行委托，
先例 = `thincoder_choices.dart`（`docs/design/thincoder-adapter.md` §21.3）；`chat_models` 的被搬段是纯公开声明 ⇒ 新档 + `export`。
同一档不混用。依据 = 两条 Dart 事实：类体不能跨档、私有标识符是库级私有（设计 §3.1）。

### 受影响文件与测试覆盖

- 新增档：kernel 9 · step_folds 1 · composer 6 · chat_session 4 · chat_models 1（逐个段名与符号见设计 §4）。
- 测试档零改动；每步验证命令与判据见设计 §5（`flutter analyze` + 该面测试；行数按换行符计数）。
- 不动面：`test/kernel/thincoder_kernel_test.dart` · `lib/ide/**` · `lib/browser/btest/**` ·
  composer 的 btest 状态行段（归 #55）· 两份既有设计档（只引用不改）。

### 验收对照

设计 §6 共六行，逐条回指设计 §1 的功能点；每条都给了机检判据（行数计数 / analyze / 测试档 / 提交文件集）。
本设计自身的机检读数 = `doc_check(mode:"gate", docs:["docs/design/structure-splits.md"])` 首行 `PASS`（0 条命中）。

### 关键决策

见设计 §8 的 KD-1…KD-7。最需评审的两条：
KD-3（kernel 取 ≤500，严于设计 ㉓ 的 ≤1345）· KD-4（chat_models 偏离 SPLIT-4 的 btest 缝——该缝无料，本档无 btest 类型）。

### 上抛项

1. **#72 台账原文未取到**（ledger 读取被截断）。边界段按代码注释定位 =
   `step_folds.dart:281-283` 的「merged where they meet」⇒ `_TurnBoundary` typedef（`:35-44`）+ `_boundaries`（`:284-321`）。
   实施前请主 agent 核对 #72 原文。
2. **SPLIT-1 的余下缝不足**：登记写法「内核模式选择区抽 `composer/mode_selector.dart`」到不了 ≤800；
   本设计以六段切法取代。`docs/design/browser-biz-test.md:643` 的登记行需在实施后由父侧改档指向本设计（设计位不改该档）。
3. **开工前置**：在飞批工作树未落（kernel +28/−1、chat_session +8）；拆分批每步开工前目标档须干净。
4. **前提更正已收（知会）**：SPLIT-5/6 只有设计、未落盘（#55 在飞）。本设计已按主 agent 07:26 的更正不引用 btest 三档作先例。

### 修正轮 1 前置口径（2026-10-23；与设计档 §5 行 0 同句）

设计档已按 §3 评审轮次 1 的 16 条（1 🔴 / 11 🟡 / 4 🔵）逐条处置。

① 当前态：kernel 与 chat_session 有 #50 的在飞改动（已交付待提交）、composer 与 `lib/browser/btest/**` 有 #55 的在飞改动，第 2 / 4 / 5 步在各自 commit 前不启动；② 每步开工前：该步目标档 `git status` 必空；先跑该步测试集并记录基线为绿。

### 修正轮 2（2026-10-23；第 4 步预算按 kernel 实测口径重算）

依据 = 第 2 / 3 步实施读数的设计漂移（委托行数假设偏乐观）与父侧第 2 修口径。设计档逐项处置，不改代码：

- **chat_session 预算重算（设计 §4.4 / §4.6）**：委托口径改按 kernel 实测 ≈2.13 行/成员（53 成员 → 113 行）。
  旧四段：1492 − 830 + 190 = **852 > 800**（超 ≈52）⇒ 不达标。段 5（`paths` / `_absolute` → `session/file_paths.dart`）从越界应对提升为计划内；
  另加段 6（发送上下文 ≈41）· 段 7（会话命令 ≈21）· 段 8（连接与挂载 ≈33）。新算式：1492 − 925 + 215 = **≈782 ≤ 800，余量 ≈18**。
  chat_session 新档 4 → 8；设计 §5 第 4 步机制列 `part ×4` → `part ×8`。
- **同轮一致性修**：设计 §4.4 把 `_pendingEdits` 的标注从「字段」改为「私有 getter」（`chat_session.dart:1150` 实为 getter，留 owner 不变）；§4.6 注补「kernel 行为实测值，其余为指示值」。
- **机检**：`doc_check(mode:"gate", docs:["docs/design/structure-splits.md"])` 首行 **PASS**（0 条命中）。首跑因 OfOf 行 321 字符 REFUSED，同轮拆行后复跑通过。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审：docs/design/structure-splits.md（全档 276 行）

算术核对（仅档内自洽性；`.dart` 坐标按评审范围未取证，标 `unverified`）：kernel 九段「搬出」1195 行（167+99+190+283+77+122+108+49+100）⇒ 1461−1195+45 委托 ≈311 ≤500 ✓；step_folds 500−42+2 ≈460 ✓；chat_models 839−108+2 = 733 ✓；composer 2466−2110+65 ≈421 ≤800 ✓；chat_session 1492−830+70 ≈732 ≤800 ✓（余量最窄，见 R7）。四个目标行数在九段/六段/四段划分下均可达成。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| R1 | Document ownership | 🔴 | SPLIT-4 的登记缝仍活在 `docs/design/browser-biz-test.md` §4（`chat/btest_models.dart`），而本档 §4.5 只写「偏离」不写「取代」：`docs/design/structure-splits.md:214`「偏离 SPLIT-4 的登记缝」；同处给的折中「若评审要求保留 SPLIT-4 的档名，可把 `editor_context.dart` 改名为 `chat_models_context.dart`，内容不变。」既不合本档自己的 `<owner>_<face>` 约定，也不等于登记的 `chat/btest_models.dart`，无法消除两处并存描述。对比 SPLIT-1：`:274`「本设计的六段切法取代它」「需在实施后由父侧改档，指向本档」——SPLIT-4 缺同等待遇 ⇒ 同一拆法在两张档里各说一套，且旧行无人改 | §4.5 加一句「取代 SPLIT-4 旧缝」，并在 §9 增一条与 `:274` 同形的开放项，点名 `docs/design/browser-biz-test.md` 的 SPLIT-4 登记行须改指本档；`:214` 的改名折中删去或改成指向该登记行改档 |
| R2 | Requirements / 前置口径 | 🟡 | 「干净」前置没分极：`:52`「拆分批开工前，目标档必须干净」读作整批总门槛（composer/chat_session 有在飞批 ⇒ 整批被挡），与 `:224` 逐步门槛「`git status --porcelain <目标档>` 为空；否则等父侧在飞批落地」及 `:233`「步骤之间无代码依赖」冲突；而 `:50` 的既知脏态（kernel +28/−1、chat_session +8）只作「非计数口径」交代，未写成「第 2/4 步在 commit 前被挡」 | 一句两极表述：①当前态——kernel/chat_session 有在飞改动（commit 前，对应步不启动）；②每步开工前——该步目标档必空。§2 与 §5 行 0 用同一措辞 |
| R3 | Clarity / 机制自洽 | 🟡 | §3.3 定死新档名「`<owner>_<face>.dart`」（`:73`「新档 = `<owner>_<face>.dart`，首行 `part of '<owner>.dart';`」），但 §4.4 四段全用子目录短名且未声明 `part of`：`:167` `lib/chat/session/mode_state.dart`，另 `kernel_proxy.dart` / `transcript_proxy.dart` / `edits.dart`。机制节与缝表互相矛盾，`edits.dart` 又过于泛用 | 二选一：把 §3.3 规则放宽为「`<face>.dart`，可落在 owner 同级或子目录」，或在 §4.4 改用 `chat_session_<face>.dart`；并在 §4.4 逐档写明 `part of 'chat_session.dart'` 与相对路径 |
| R4 | Feasibility / 搬运形态 | 🟡 | §3.3 的唯一形态只覆盖方法（`:73`「内容 = 顶层私有函数 `<name>Of(Owner owner, …)`」），而缝表点名了字段/私有 getter/常量：`:170` 含 `_filesSeen` `_modelSettings`/`_runningTask`/`_dismissedGoal`，`:104` 含 `imageMaxBytes` `turnMaxBytes`；字段的存储无法跨档，只能留 owner。另 `:151` 点名 `chatContextKey` `chatCommands` `chatComposing`，若其中有的本是 import 进来的全局名，「搬」就不成立。注解（`@override`/`@protected`）也没纳入「签名与可见性逐字不变」 | §3.3 补两条：①字段与后备存储留 owner，只搬投影方法（委托一行）；②`@override`/`@protected`/`@visibleForTesting` 等注解随委托逐字保留；并在 §3.3 加一句「缝表点名的符号必须是本源档的声明，import 来的名字不算缝」 |
| R5 | Requirements / 机制判据 | 🟡 | 「part vs export」的判据不自洽：`:69` 给 chat_models 选 export 的理由是「被搬段是纯公开数据声明，无私有耦合；`export` 保持原 import 路径 ⇒ 调用方零改动」——但 `part` 同样保持原 import 路径、同样调用方零改动，「无私有耦合」也不排斥 `part`。加上 KD-1（`:263`）的「有私有耦合 ⇒ part；纯公开段 ⇒ export」只把 part 当必要条件的逆否，实际判据退化为「作者选择」，评审无法据它复核 | 把真正的区分理由写出来（独立 library 可单独 import / 不扩大 owner 的 part 图 / 避开私有耦合随改动回归），或直接规定「同批一律 part，export 仅在需要单独 library 时例外」；KD-1 同步改写 |
| R6 | Scope / 顺序与回滚 | 🟡 | 顺序理由不成立：`:220` 称「顺序按风险升序，不按紧急度」，但第 2 步（`:226`）是本批最大单步改动（9 个 part、搬 1195 行），风险高于排在其后的 chat_models（108 行 export）与 chat_session；表内实际顺序是「最小档验证形态 → 最大档 → …」。另回滚列只覆盖「已完成的单提交 `git revert`」，未写中途放弃（未提交）怎么回 | 要么改述理由（先在小档验证 part 形态，再尽早做最硬的 kernel 以留返工余量；composer 因 #55 在飞排末），要么调整步序；回滚列补一格「中途放弃 = `git restore` 工作树，不留半成品提交」 |
| R7 | Acceptance / 行数预算 | 🟡 | chat_session 的余量最窄且委托行数被低估：`:172`「搬出 ≈830，加回约 70 行委托」——四段点名约 100 个成员（含两个类声明不需委托），按「一成员一委托」≈100 行 ⇒ 1492−830+100 ≈762，余量只剩 ≈38（vs 界 800）。若另有一段「搬出」估高 40 行即越界，而 §4.4 未自带越界应对 | §4.4 写明每段委托行数假设与合计（≈100 行）与由此得到的余量 ≈38，并把 §7 的「继续按段名切该段自身」在 §4.4 显式挂接（点名第 5 段候选，如 `edits.dart` 里的 `paths`/`_absolute` 与回退段拆开） |
| R8 | Affected-file size annotations | 🟡 | 没有一个统一的受影响档表：现行数在 §2（`:42` 表），搬出/预期散在各 §4.x，新档只有「≈N」估计，没有「现行 → 预期（≤±N）」的单行口径；评审/实施无法一处核对是否越档，新档也缺与 500 档的显式对照 | 加一张总表：档 · 现行行数 · 搬出 · 搬入（委托）· 预期 · 界 · 新档及其估行；新档列一并标注「新档 ≤500」判据 |
| R9 | Clarity / 缝表可核对性 | 🟡 | composer 缝表内部不自洽、坐标互相重叠：`:157` 说 State 字段「（`:136-200`，65）」留主档，而 `:150` 第二段称「`:190-898` 内」、`:151` 第三段坐标含 `:190-196` ⇒ 同一段 7–11 行被同时判「留」与「搬」。段估计与所列坐标区间也对不上：第三段区间合计 277 行却标「≈330」，第四段 272 标「≈330」，第五段 393 标「≈360」；`:157` 留档各项合计 379，仍写「估 380–520」。§4.4 同类：第二段 193 标「≈230」、第三段 268 标「≈240」 | 把各段「搬出」改为「所列坐标区间之和」或显式标注「指示值，以行数门为准」；修正 `:190-196` 与 `:136-200` 的重叠（把 `:190-196` 归到其中一边）；`:157` 的区间下界改成 379 |
| R10 | Requirements traceability | 🟡 | 台账只被引用、未被结案：`:4`「台账：#150（SPLIT-1…4）· #22（kernel 超预算）· #72（step_folds 边界并集段）」——档内从不点名 #150「四个 >800 档」是哪四个、本批之后 #150 是否收口；#153 只在 `:35`「与台账 #22 / #72 / #150 / #153」出现一次再无下文（语义悬空） | 加一列/一小节「结案对照」：#22/#72/#150/#153 各条 → 本批达成条件（如 #22 由 kernel ≤1345 达成、#72 由边界段出档达成）或「不结案」，并点名 #150 的四个 >800 档与 §2 四行的对应关系 |
| R11 | Acceptance / 测试面 | 🟡 | kernel 的测试面靠枚举而非推导，且与别处口径不一致：`:120` 写调用方含「测试档」（未点名），`:226` 却只列六个测试档；而 chat_session 的调用方是按档逐行枚举（`:186-204`）、chat_models 给了「136 个文件」。搬 1195 行的档用一份说不清来源的清单当验收门，漏档不会被发现 | 按 `:186-204` 的方式从 import 反推 kernel 的测试调用方并落成 §5 第 2 步的命令；`flutter test --no-pub` 改为按目录 + 名单双列，或直接 `flutter test --no-pub test/kernel` |
| R12 | Acceptance / 门值 | 🟡 | 验收门两处不一致、且无改动前基线：`:225` 各步判据是「`flutter analyze` = 0 issue」，`:244` 功能点 6 变成「`git diff --name-only` 无 `test/`；analyze 0 error」——error 与 issue 是两档门。另 §5 未要求在开工前先记录该步测试集为绿，若基线本就红，全绿门不可判 | §6 第 6 行改成与 §5 同值「0 issue」；§5 行 0 增加「先跑一遍该步测试集并记录基线为绿」 |
| R13 | Methodology（受限项） | 🔵 | 本次范围无 AGENTS.md、无项目标准档、无 document map：方法学合规（4 步流）只能按设计档自身形态判，文档归属只能按判据本身判。同时所有 `.dart` 行号/符号坐标、以及 `docs/design/thincoder-adapter.md` §18.4/§21.3、`docs/design/browser-biz-test.md` §4/`:643`、台账 #22/#72/#150/#153 的引用均在评审范围外，一律 `unverified`——本轮只核了档内算术与档内互证 | 无需改档；若需核坐标，另开一轮带源码/登记档范围的评审 |
| R14 | Clarity / 越界应对措辞 | 🔵 | `:252`「（part 档可再分）」措辞不准确：Dart 里 `part` 指令只能写在库根档，part 档只能有 `part of`（本条为语言规则，档内无取证，`unverified`）；再分缝的实操是「在 owner 档补一条 `part` 指令」 | 改成「由 owner 档再补一条 `part` 指令、把该段的一部分再切出去」，不改结论 |
| R15 | Scope / 结构档位 | 🔵 | `:276` 的收敛选项「可并入 `composer_editing.dart`（合并 ≈680 行，仍 <800）」只比 800 硬顶，未提 500 档：680 行落在「>500 需拆分复核」区间 | 若采纳合并，补一句该 680 行档的分档理由（或改与 `composer_message.dart` 之外的段合并），避免绕开 500 档 |
| R16 | Numeric drift | 🔵 | kernel 主档留档口径两处小数不一致：`:106`「`part` 指令（9）」未计已存在的 `:30` `part 'thincoder_choices.dart'`（实为 10 条）；`:92`「import 1–28」与 `:106`「import（27）」相差 1 行 | 统一为「part 指令 10（含既有 `thincoder_choices`）」与「import 27 + 1 空行」 |

计数：🔴 1 · 🟡 11 · 🔵 4 —— 共 16 条。

四个点名的复核结论：①**五档缝表能到目标行数**（kernel 九段 1195 行搬出，四条路径均达标；但 chat_session 余量最窄，见 R7，composer 缝表坐标互相重叠见 R9）。
②**机制选型判据不自洽**（§3.2 给 chat_models 的理由对 `part` 同样成立，见 R5）。
③**五步顺序与回滚粒度**：回滚粒度（一步一提交、提交文件集 ⊆ 目标档+新档）成立，但「风险升序」的说法被表自身否证，且缺中途放弃的回滚（见 R6）。
④两点待补均确认成立：(a) 前置未分极（R2）、(b) §4.3 缺「取代 SPLIT-1」的本地句、§4.5 的 SPLIT-4 只写「偏离」且旧登记行无人改（R1）。
### 轮次 2（评审子代理）

## 第 2 轮复核（#58 修正轮 → docs/design/structure-splits.md，311 行）

| # | Orig# | File | Severity | Status | Notes |
|---|-------|------|----------|--------|-------|
| 1 | R1 | docs/design/structure-splits.md | 🔴→ | Fixed | §4.5「**取代 SPLIT-4 的旧缝**」+「SPLIT-4 的旧登记行须在实施后改指本档（§9 项 5）」；§9 项 5 已镜像 SPLIT-1 项 2 的改档口径；KD-4 同步；旧「改名 chat_models_context.dart」折中已删 ⇒ 无未决 🔴 |
| 2 | R2 | 同上 | 🟡 | Fixed | §2 改指「见 §5 行 0 的两极口径」；§5 行 0 分①当前态（#50/#55 在飞，第 2/4/5 步 commit 前不启动）②每步开工前目标档 git status 必空 |
| 3 | R3 | 同上 | 🟡 | Fixed | §3.3 命名分两路（同级 `<owner>_<face>` / 子目录 `<face>`）+ `part of '../chat_session.dart'`；§4.4 四档名与规则一致（file_edits.dart 已去泛名） |
| 4 | R4 | 同上 | 🟡 | Fixed | §3.3 三条规则齐：字段留 owner、注解随委托、import 名不算缝；缝表已标「（字段，留 owner）」 |
| 5 | R5 | 同上 | 🟡 | Fixed | §3.2 chat_models 行给出真判据（独立 library + 编译器强制边界）；KD-1 明写「无私有耦合本身不排斥 part」 |
| 6 | R6 | 同上 | 🟡 | Fixed | 步序理由改为「按验证价值，不按风险升序」；回滚列拆已提交/未提交，§5 补「中途放弃」 |
| 7 | R7 | 同上 | 🟡 | Fixed | 委托行数假设 15/31/29/15≈90→按 100 计；主档 ≈762、余量 ≈38；越界应对点名第 5 段 `session/file_paths.dart` + owner 补 part 指令；§4.6 行 3 同值 |
| 8 | R8 | 同上 | 🟡 | Fixed | §4.6 总表 5 行；算式复核全通：311/460/421/762/733 |
| 9 | R9 | 同上 | 🟡 | Fixed | 第二段 `:201-898`、第三段删 `:190-196`（与 `:136-200` 重叠解除）；「坐标不参与加总」注；主档下界改 379 并注明「= 上列各项之和」 |
| 10 | R10 | 同上 | 🟡 | Fixed | 结案对照表已建（#22/#72/#150/#153 各有达成条件与结案口径）；表内 #150 一行有残留矛盾，另立 N1 |
| 11 | R11 | 同上 | 🟡 | Fixed | §4.1 写「测试档 5 个（import 反推）」；§5 第 2 步列出 5 档并注明 `grep -l thincoder_kernel.dart test/` 反推 |
| 12 | R12 | 同上 | 🟡 | Fixed | §6 项 6 改「analyze 0 issue」与 §5 各步同值；§5 行 0 增「先跑该步测试集并记录基线为绿」 |
| 13 | R14 | 同上 | 🔵 | Fixed | §7 边界行改「由 owner 档再补一条 part 指令、把该段的一部分再切出去」 |
| 14 | R15 | 同上 | 🔵 | Fixed | §9 项 4 已写「该档越 500 复核线但 < 800 硬界」+ 复核判据 |
| 15 | R16 | 同上 | 🔵 | Fixed | §4.1 现状改 import 26 + part 1（:30），留档改「part 指令（10，含既有 thincoder_choices）」 |
| 16 | (new) | docs/design/structure-splits.md:36 | 🟡 | New | #150 结案格自相矛盾：条目列点名四个档且达成条件把四个分别映射到 §4.1/§4.3/§4.4/§4.5，结案格却写「**不结案**：四个只落三个」并以 `ide_scm_view.dart` 作第四个——该档不在条目列的四个之内。要么四个都算本批（可结案），要么把 `ide_scm_view.dart` 写进条目列（不结案） |
| 17 | (new) | docs/design/structure-splits.md:201 | 🟡 | New（本轮发现，非修正引入） | chat_session 调用方「18 档」表漏 `lib/chat/composer/composer.dart:20: import '../chat_session.dart';`（另有 #55 在飞的 `lib/browser/btest/btest_status_switches.dart:3` 未计，可在表头注明「不含 #55 在飞档」）。功能上不破（import 路径不变），但这是「调用方零改动」的核对清单，应补全 |
| 18 | (residual R9) | docs/design/structure-splits.md:164 | 🔵 | New | 第三段坐标仍含 `:1695-1706`，落在第五段 `:1507-1753` 区间内（12 行重复归属）；有「坐标只用于定位」注，不阻塞，建议第三段删该窗口或第五段收窄 |
| 19 | (residual R16) | docs/design/structure-splits.md:119 | 🔵 | New | kernel 留档各项之和 26+10+197+28+45=306，与「估 310–360」下界差 5 行，且无 §4.3 那样的「下界 = 上列各项之和」注；建议对齐或补注 |

**本轮结论**：16 条旧项全部落地（R1 🔴 已解，11 🟡 + 4 🔵 已修）；新增 2 🟡（#150 结案格矛盾、调用方表漏 composer.dart）+ 2 🔵 残留。无未决 🔴。harness 指定的 `lib/chat/side_panel/file_preview.dart` 不在本设计受影响档集合内（其 import 块 :1-44 不引 `chat_session.dart` / `chat_models.dart` / `composer.dart` / kernel / step_folds），对本次设计评审无影响。

计数：🔴 0 · 🟡 2（新增）· 🔵 2（残留）
VERDICT: pass

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）

### 实施记录（eng-coder · 2026-10-23）

**范围**：设计 `docs/design/structure-splits.md` §4.2 第 1 步（台账 #72 边界并集段）。机制 = `part` + 一行委托（设计 §3.1 / §3.3），本步只用这一种机制。

**改动**

- `lib/chat/step_folds.dart`：新增 `part 'step_folds_boundaries.dart';`；`_TurnBoundary`（含 doc 注释）与 `_boundaries` 方法体搬出；原位置留一行委托 `_boundaries(...) => _boundariesOf(this, ...)` 加一行指路注释；类字段与后备存储未动。
- 新档 `lib/chat/step_folds_boundaries.dart`：首行 `part of 'step_folds.dart';`；含搬出的 typedef、顶层函数 `_boundariesOf(StepFolds folds, int from, int count, List<TurnMark> turns)`、3 行 face 抬头。

**验收读数（命令 + 结果）**

| 验收 | 命令 | 结果 |
|---|---|---|
| ① analyze 0 issue | `dart analyze lib/chat/step_folds.dart lib/chat/step_folds_boundaries.dart` | `No issues found!`（exit 0） |
| ② 测试全绿 | `flutter test --no-pub test/chat/step_folds_test.dart test/chat/fold_view_test.dart` | `+47: All tests passed!` |
| ③ 主档 ≤500 | `node -e` 换行符计数 | 460 |
| ④ 新档 ≤500 | 同上 | 56 |
| ⑤ 改动面 = 目标档 + 新档 | `git status --porcelain` / `git diff --name-only` | 本步增量 = `M lib/chat/step_folds.dart` + `?? lib/chat/step_folds_boundaries.dart`；无 `test/`、无其他 `lib/`（基线见下） |
| ⑥ 行为零变化 | 逐块比对脚本（对照 `git show HEAD:`） | 见下「逐块比对」 |
| ⑦ 新档首行 | 读取首行 | `part of 'step_folds.dart';`（同级形态） |
| 附：格式 | `dart format --output=none --show=changed` | `Formatted 2 files (0 changed)` |

**逐块比对（对照 HEAD 版 `lib/chat/step_folds.dart`）**

- typedef 块：原 3 行 → 新 3 行，逐字一致。
- `_boundaries` 方法块：原 41 行 → 新 46 行；差异只有三类：① 签名 `_boundaries(int from, int count, List<TurnMark> turns)` → `_boundariesOf(StepFolds folds, int from, int count, List<TurnMark> turns)`（1 行 → 6 行，多出 5 行）；② 3 处实例引用加前缀 `_items[` → `folds._items[`；③ 类成员 → 顶层函数缩进减 2。除此之外逐字一致（脚本判定 true）。
- 反推校验：HEAD 版主档 − 搬出块 + `part` 指令/空行 + 委托 2 行 + 指路 1 行 == 当前主档，逐字节一致（脚本判定 true）。

**工作树基线（开工前已存在，非本步改动）**
`M docs/batches/2026-10-22-browser-biz-test-mode.md` · `M docs/batches/2026-10-23-ledger-sweep.md` · `M lib/ide/git/git_repository.dart`
本步净增量 = 目标档 + 新档；判据 ⑤ 的字面条件被既有脏档占一格，故记录基线供父侧核。

- 设计 §4.2 估新档 `≈45`，实测 56（搬出内容 44 + part 头 1 + 空行 2 + 签名展开 5 + face 抬头 4）；主档估 `≈460`，实测 460。
- 设计 §4.2 的 `_TurnBoundary` 现坐标 `:35-44` 在实施基线上实为 `:33-35`（其后的 `class StepFolds` 注释不搬）；调用方清单把 `test/chat/fold_view_test.dart` 列为直连调用方，该档实为经 `chat_history_view` 的间接消费者。

**轮次与终态**

- 内部 explore 偏差审计：1 轮，VERDICT clean（无 partial / silent-simplification / doc-drift / out-of-list）。
- 内部 advisor 代码评审：1 轮，VERDICT pass（🔴 0 · 🟡 1 = 本节落盘 · 🔵 3）。🔵 之「新档 face 抬头」与「主档指路注释」已落地，并重跑 analyze / 测试 / 比对全绿；另两条为设计档漂移，已列上。
- 修正轮：1 次（评审后 🔵 落地），之后全部判据复跑通过。
- 终态：clean。

### 实施记录：结构拆分第 3 步（chat_models · 机制 = 新档 + export）

**范围**：设计 `docs/design/structure-splits.md` §4.5（chat_models 839 → ≤800，一段出档）。机制 = 新 library + `export`（设计 §3.2 / KD-1）；本步只用这一种机制，不用 `part`。

**改动**

- `lib/chat/chat_models.dart`：`EditorContext` + `TextContext`（含 doc 注释，HEAD `:52-159`，108 行）整块搬出；删 `import 'package:path/path.dart' as p;`（搬后本档无 `p.` 使用）；加 `import 'editor_context.dart';`（本档 `:30` `List<EditorContext>` 仍需解析）与 `export 'editor_context.dart';`（调用方经原路径继续可见）。
- 新档 `lib/chat/editor_context.dart`：唯一 import = `package:path`；3 行 face 抬头（沿用第 1 步新档形态）；108 行搬入内容逐字；不 import `chat_models.dart`（无循环）。

**验收读数（命令 + 结果）**

| 验收 | 命令 | 结果 |
|---|---|---|
| ① analyze 0 issue（改动面） | `dart analyze lib/chat/chat_models.dart lib/chat/editor_context.dart` | `No issues found!`（exit 0） |
| ① 附：全项目 analyze | `flutter analyze --no-pub` | `No issues found!`（7.7s，exit 0） |
| ② 测试基线（开工前，目标档 HEAD 干净） | `flutter test --no-pub test/chat test/kernel` | `+872 -4`：4 个红项见下（Windows 路径/环境既有） |
| ② 测试（本步后，同命令） | 同上 | `+872 -4`：**红项集合逐条一致**，无新增失败 |
| ② 附：被搬面定向 | `flutter test --no-pub test/chat/open_editor_test.dart test/chat/thincoder_commands_test.dart test/chat/user_message_selection_test.dart` | `+12: All tests passed!` |
| ③ 主档行数 | `node -e` 换行符计数（设计 §5 口径） | **732**（≤800；HEAD 839；设计估 ≈733） |
| ④ 新档行数 | 同上 | **114**（≤500；设计估 ≈110） |
| ⑤ export 行 | 读取 `chat_models.dart:5` | `export 'editor_context.dart';` |
| ⑤ 调用方零改动 | `git grep -l "chat_models.dart" -- lib test` + `git status --porcelain` | 137 档命中（含本档自身）⇒ 外部调用方 136；本步改动面 = `M lib/chat/chat_models.dart` + `?? lib/chat/editor_context.dart`，无任何调用方档被改 |
| ⑥ 签名/渲染逐字不变 | 逐块比对脚本（对照 `git show HEAD:`） | 见下「逐块比对」，`diffs: 0` |
| ⑦ 新档依赖 | 读取新档 import 清单 | 仅 `package:path`；无 `chat_models.dart`、无 `part of` |
| 附：格式 | `dart format --output=none --show=changed`（两档） | 新档 clean；主档在 HEAD 版即不 clean（对 HEAD 快照同命令 = `Changed`），故不跑 format（会重排既有代码，违反纯搬运）；首个 formatter 差异在既有 `TurnUsage`（现 `:81`），本步改动区（`:1-6`）无差异 |

**基线红项（开工前后逐条一致，既有且与本步无关）**

1. `test/chat/files_seen_test.dart`：`filesSeen is the same list while no file is new`（实际 `/p\a.dart` vs 期望 `/p/a.dart`，Windows 分隔符；被测在 `chat_session.dart:1114-1130`，本步未碰）
2. `test/chat/side_panel/side_panel_test.dart`：markdown preview 保存（macOS variant），期望字符串实际 null
3. `test/chat/side_panel/side_panel_test.dart`：drop 文件链接 `/p/docs\shot.png`（Windows 分隔符）
4. `test/kernel/dart_core_e2e_test.dart`：期望 `diff: color.txt +2`、实际为完整临时路径

**逐块比对（对照 HEAD 版 `lib/chat/chat_models.dart`）**

- 搬出块：HEAD `:52-159`（108 行）vs 新档 `:7-114`（108 行）逐行比对，`identical: true · diffs: 0`（LF 归一后；工作树 CRLF 由 `core.autocrlf=true` 决定，与全仓一致）。
- 反推校验：HEAD 全档 − `:52-160` − `package:path` import + `import`/`export` 两行 == 当前主档，732/732 行逐行一致（`diffs: 0`）。
- 签名面：`EditorContext(this.path, {line, selectedLines, selectedText})`、`static const maxSelectedText = 10000`、
  `name` / `dedupeKey` / `note` / `editorNote`、`TextContext({required String key, required this.name, required this.text}) : super(key)`
  与四个 `@override` 全部逐字保留；私有 `_lines` / `_selectedText` / `_reminder` 同迁，主档无残留引用（`grep` 无命中）。
- 行为面：`test/chat/open_editor_test.dart` 逐字钉住 `note` / `editorNote` / 截断渲染（`:45-116`），本步后全绿。

**工作树基线（开工前已存在，非本步改动）**：`M docs/batches/2026-10-22-browser-biz-test-mode.md` · `M docs/batches/2026-10-23-ledger-sweep.md` · `M lib/ide/git/git_repository.dart`。`git diff --name-only` 原文 = 上述 3 档 + `lib/chat/chat_models.dart`；本步新增文件只有 `lib/chat/editor_context.dart`。

**设计漂移（交父侧 / eng-designer 定位；实施不改文档）**

- 设计 §4.5 估主档 `≈733`，实测 **732**（搬出块后的分隔空行随块一并去掉，比「−108+2」少 1 行）；新档估 `≈110`，实测 **114**（多 3 行 face 抬头 + 2 行空行）。
- 设计 §4.5 记搬出块坐标 `:54-161`；实施基线（HEAD）实为 **`:52-159`**（doc 注释从 52 起、`TextContext` 收尾于 159），差 2 行——坐标按符号名定位，不影响结论。
- 设计 §4.5「136 个文件提到 chat_models.dart」：`git grep -l` 实测 137（含本档自身）⇒ 外部调用方 136，与设计一致。

**轮次与终态**

- 内部 explore 偏差审计：1 轮，VERDICT clean（四类偏差均未发现；该装配无 git/shell，行数与依赖方向由其独立读盘复核）。
- 内部 advisor 代码评审：第 1 轮 VERDICT changes-required —— 1 🟡 must fix（本步验收读数未落盘 + 红基线未交代）· 1 🟡 协调项（SPLIT-4 旧登记行待父侧改指，设计 §9 项 5 归父侧）· 1 🔵（`TextContext` / `dedupeKey` 无测试钉住，由逐块比对覆盖）。must fix 的处置 = 本节读数五项齐备，代码零改动。
- 修正轮：1 次（补本节读数，无代码改动）。
- 终态：见本节补记（advisor 第 2 轮复核后）。

**补记（advisor 第 2 轮复核后）**

- 内部 advisor 代码评审第 2 轮：VERDICT **pass**（code · 两档）。第 1 轮三项复核：①must-fix（读数未落盘 + 红基线未交代）→ **Fixed**（复核方逐项对读本节「验收读数」「逐块比对」与当前树，自洽）；②SPLIT-4 旧登记行改指 → **Accepted**（设计把执行权归父侧，本节「轮次与终态」已入账）；③`TextContext` / `dedupeKey` 无测试钉住 → **Fixed**（逐块比对 + 签名清单覆盖）。
- 第 2 轮新增 1 条 🟡 report-only（不阻塞，文档面）：设计 §5 行 0 ②「先跑该步测试集并记录基线为绿」与 §6 行 5「全绿」门值未含红基线口径。证据 = 本节「验收读数」表的基线/本步后两行（`+872 -4`，红集逐条一致）。建议父侧 / eng-designer 在收口前补一句「基线本红时，判据 = 同命令下红项集合逐条一致且无新增失败；全绿仅适用于基线为绿的档」。本步不改文档。
- 终态：**clean**（内部 explore 偏差审计 1 轮 clean · 内部 advisor 代码评审 2 轮，终判 pass · 修正轮 1 次 = 补本节读数，代码零改动 · 无未决 🔴）。

### 实施记录：结构拆分第 2 步（kernel · 机制 = part ×9）

**范围**：设计 `docs/design/structure-splits.md` §4.1 九段（台账 #22：kernel 1461 > 预算 1345，本批目标 ≤500）。机制 = `part` + 顶层函数 `<name>Of(ThincoderKernel owner, …)` + 类里一行委托（设计 §3.3）；字段与后备存储留 owner；注解随委托逐字保留；缝表点名的符号均为本源档声明。

**改动**

- `lib/kernel/thincoder/thincoder_kernel.dart`：1461 → **480** 行。`import` 26 条不动；`part` 指令 1 → 10（新增九条）；类头/构造/字段/getter 不动；
  53 个方法体出档，原位留 53 条一行委托（113 行），`@override` 等注解随委托保留；
  静态字段（`imageMaxBytes` `turnMaxBytes` `_letters` `_random` `_content` `_turnKey` `_startingId`）与共享助手（`_setHealth` `_running` `_cwd`）留 owner。
- 九个新档（同级，首行均为 `part of 'thincoder_kernel.dart';`，无 `import`、无跨 part 引用）：
  `thincoder_lifecycle.dart`（170）· `thincoder_records.dart`（111）· `thincoder_release.dart`（187）· `thincoder_turns.dart`（279）· `thincoder_title.dart`（84）· `thincoder_revert.dart`（131）· `thincoder_requests.dart`（117）· `thincoder_inbound.dart`（48）· `thincoder_images.dart`（98）。
- 顶层函数随段搬运：`_pumpTitle`（title）· `_planOf` / `_revertFiles` / `_revertSkips` / `_revertFailures`（revert）。
- 段内坐标覆盖、但设计点名清单未列的四个符号，按符号搬并记入漂移：`_hostMcpServers`（lifecycle）· `_revert`（revert）· `_attachImages` / `_nativePrompt`（images）——均为私有、且只被本段调用。

**验收读数（命令 + 结果）**

| 验收 | 命令 | 结果 |
|---|---|---|
| ① analyze 0 issue | `dart analyze`（全项目） | `No issues found!`（exit 0） |
| ① 附：改动面 | `dart analyze lib/kernel/thincoder/thincoder_kernel.dart` | `No issues found!` |
| ② 测试基线（开工前，目标档 HEAD 干净） | `flutter test --no-pub test/kernel/thincoder_kernel_test.dart test/kernel/rename_confirmed_test.dart test/kernel/thincoder_fixtures_test.dart test/chat/thincoder_commands_test.dart test/composer_test.dart` | `+230 -2`，2 个红项见下（`test/composer_test.dart` 既有） |
| ② 测试（本步后，同命令） | 同上 | `+230 -2`：**红项集合逐条一致，无新增失败** |
| ③ 主档行数 | `node -e` 换行符计数（设计 §5 口径） | **480**（≤500；设计估 ≈311） |
| ④ 九个新档行数 | 同上 | 170 / 111 / 187 / **279** / 84 / 131 / 117 / 48 / 98（最大 279 ≤500） |
| ⑤ 逐块比对（对照 `git show HEAD:`） | 令牌级比对脚本（归一化只允许三类差异：`<name>Of(owner, …)` 签名展开、`owner.`/`ThincoderKernel.` 前缀、缩进） | 53 个成员逐块 `diffs: 0`（无差异）；另：`${_version}` 一处因前缀加花括号，属前缀类 |
| ⑥ 反推校验 | HEAD 主档 − 1114 行搬出 + 9 条 `part` + 53 条委托 + 11 条指路注释 | 左 233 行 / 右 233 行（非空行），**0 处不一致**；53 条委托共 113 行 |
| ⑦ 改动面 | `git status --porcelain` / `git diff --name-only` | 增量 = `M lib/kernel/thincoder/thincoder_kernel.dart` + 9 个 `??` 新档；无 `test/`、无其他 `lib/`（基线见下）；根目录 `?? 300` 为开工前既存 0 字节空档（mtime 08:22，早于本步），未碰 |
| ⑧ 新档首行 | 逐档读取 | 九档均为 `part of 'thincoder_kernel.dart';`（同级形态） |
| 附：格式 | `dart format --output=none --show=changed`（十档） | 十档均为 `Changed`：差异全是 `owner.` 前缀把行推过 80 列后的重排（对照副本验证：仅换行/折行，无语义）；主档在 HEAD 版即非 format-clean，故不跑 format（会重排既有代码，违反纯搬运；第 3 步同口径） |

**基线红项（开工前后逐条一致，既有且与本步无关；`test/**` 未改一行）**

1. `test/composer_test.dart`：`mode picker opens on press, animates, and follows the mouse`（`:1283`，期望 `ComposerPicker` 下有 `Agent`，实得 0）
2. `test/composer_test.dart`：`Shift+Tab in the input goes through the modes`（`:1322`，期望 `['Ask','Plan','Agent']`，实得 `['Ask','Plan','surface']`）

**逐块比对（对照 HEAD 版 `lib/kernel/thincoder/thincoder_kernel.dart`）**

- 53 个成员逐块令牌比对：`diffs: 0`。每段的搬出内容与 HEAD 逐行一致，差异只在三类：签名展开为 `<name>Of(ThincoderKernel owner, …)`（多行签名展开出额外行）、实例引用加 `owner.` 前缀（`this` 参数改为 `owner`）、静态成员以 `ThincoderKernel.<name>` 访问、类成员 → 顶层函数缩进减 2。
- 三处「两条/三条语句写在同一行」经 `git show HEAD:` 逐行取证为 HEAD 原文，非本步引入：HEAD `:629` `_dropModelOf(); _dropTitleOf();` · `:954` `_titleTarget = null; _titleDeferred = false; _titleSending = false;` · `:1030` `_queue.clear(); _next = null;`（设计 §1 的「不合并语句」边界未破）。
- 反推校验：HEAD 全档 − 1114 行（53 成员 + 5 个顶层函数） + 9 条 `part` 指令 + 53 条委托（113 行） + 11 条指路注释 + 2 处分组注释 == 当前主档，左右各 233 个非空行，逐行一致（`diffs: 0`）。
- 行为面：`_ensureStarted` 的 `??=` 赋值、`_drain` 的队列取头、`_endTurn` 的 `_pumpModelOf` / `_pumpTitle` 调用顺序、`dispose` 的 `closeEvents` 位置、`rewind` 的 `-32602` / `-32002` 分支均逐字保留；委托不改变调用路径（`owner.method()` 与原 `this.method()` 同一对象）。

**工作树基线（开工前已存在，非本步改动）**：`M docs/batches/2026-10-22-browser-biz-test-mode.md` · `M docs/batches/2026-10-23-ledger-sweep.md` · `M lib/ide/git/git_repository.dart` · `?? 300`（0 字节空档）。`git diff --name-only` 原文 = 上述 3 档 + `lib/kernel/thincoder/thincoder_kernel.dart`；本步新增文件只有九个 `??` part 档。

**设计漂移（交父侧 / eng-designer 定位；实施不改文档）**

- **委托行数假设偏乐观**：设计 §4.1 `:119` 写「约 45 行委托 ⇒ 估 310–360 行」，实测 53 条委托 / 113 行（委托段 `:247`–`:477`，231 行），主档 480（估 ≈311）。`≤500` 门成立，但下一步 chat_session 余量仅 ≈38（设计 §4.4），按同一假设会低估 ⇒ 第 4 步预算需按实测口径重算。
- **坐标漂移 ≤5 行**（按符号名搬，结论不变）：段 1 设计 `:239-369` 实为 `:238-362` + `:466-503`（`_applyStartMode` / `_handshake` / `_fail` 在 466 起，不是 469）；
  段 2 `:370-468` 实为 `:364-464`（doc 注释从 364 起）；段 4 `:647-929` 实为 `:646-924`；段 5 `:930-958` 实为 `:926-956`；
  段 6 `:959-1054` 实为 `:958-1049`；段 7 `:1055-1162` 实为 `:1053-1159`；段 8 `:1219-1234` 实为 `:1218-1225`（doc 从 1218 起）。
- **点名符号不能搬**：段 9 点名的 `_letters` `_random`（与段 8 的 `_content` `_turnKey`）是类 `static` 字段 ⇒ 按设计 §3.3「字段与后备存储留 owner」留主档，搬出的函数以 `ThincoderKernel.<name>` 访问。
- **跨档行号引用失效**：`lib/kernel/thincoder/thincoder_warm.dart:12` 的 `clientCapabilities`（`thincoder_kernel.dart:249-251`）现指向委托行，真实代码在 `thincoder_lifecycle.dart:48`。设计 §1 禁止本步改别的档 ⇒ 父侧协调项。
- **设计 §5 第 2 步门值**：门写「5 档全绿」，而 `test/composer_test.dart` 基线本红 ⇒ 与第 3 步同一条口径问题，建议按批档 `:269` 的表述改为「红项集合逐条一致且无新增失败」。

**轮次与终态**

- 内部 explore 偏差审计：1 轮，VERDICT clean（四类偏差：无；九段落点逐条对齐；§5 记录缺口在收口前由本节补齐）。
- 内部 advisor 代码评审：第 1 轮 VERDICT changes-required —— 1 🟡 must fix（本步验收读数与红基线未落盘 + 门值「全绿」字面不可达）· 1 🟡 协调项（`thincoder_warm.dart:12` 行号引用失效，父侧）· 4 🔵（双 `Of` 命名、三处合并语句需取证、主档指路注释与落点不符、设计估值漂移）。
- 第 1 轮处置：①must-fix → **Fixed**（本节六项读数 + 基线红项逐条比对）；②协调项 → **Accepted**（设计禁止改别的档，列入本节漂移交父侧）；③合并语句 → **Fixed**（`git show` 取证为 HEAD 原文，记 `:629` / `:954` / `:1030`）；④指路注释 → **Fixed**（主档补两行：`// Exiting and the waiting line: see thincoder_release.dart.`、`// A revert can start now: see thincoder_turns.dart.`；主档 478 → 480，analyze 与 5 档测试已复跑）；⑤双 `Of` 命名与设计估值 → **Accepted**（设计侧事项，交父侧/eng-designer）。
- 修正轮：1 次（2 行注释 + 本节），之后 analyze / 测试 / 逐块比对 / 反推校验全部复跑通过。
- 终态：**clean**（审计 1 轮 clean · 代码评审 2 轮，终判 pass · 修正轮 1 次 · 无未决 🔴）。

**补记（advisor 第 2 轮复核后）**

- 内部 advisor 代码评审第 2 轮：VERDICT **pass**（code · 十档）。第 1 轮六项逐条复核：
  ①must-fix（本步读数与红基线未落盘）→ **Fixed**（本节八项读数 + 两条基线红项；盘上可核读数逐条吻合：主档 480、九档 170/111/187/279/84/131/117/48/98、首行九档 `part of`、`_exitedOf` / `_sayWaitingOf` / `canRevertNowOf` 落点、`clientCapabilities` 新址 `thincoder_lifecycle.dart:48`）；
  ②设计估值漂移 → **Accepted**（记入本节漂移；建议第 4 步按实测口径重算 chat_session 预算）；
  ③`thincoder_warm.dart:12` 行号引用失效 → **Accepted**（设计禁止本步改别的档，交父侧）；
  ④三处合并语句 → **Fixed**（HEAD `:629` / `:954` / `:1030` 逐行取证）；
  ⑤主档指路注释 → **Fixed**（补两行，主档 478 → 480，analyze 与 5 档测试已复跑）；
  ⑥双 `Of` 命名 → **Accepted**（设计侧命名例外）。
- 第 2 轮新增 1 条 🔵 report-only（不阻塞，记录面）：本节「三处」表述与树不完全对应——`thincoder_title.dart:62` 的 `kernel._titleDeferred = false; kernel._titleSending = true;` 是同形合并行，未被本节所列 HEAD `:629` / `:954` / `:1030` 的取证覆盖。该行第 1 轮未点名，非本步引入；建议父侧/设计侧做 HEAD 取证时补这一行。本步不改。
- 终态：**clean**（内部 explore 偏差审计 1 轮 clean · 内部 advisor 代码评审 2 轮，终判 pass · 修正轮 1 次 = 2 行注释 + 本节记录 · 无未决 🔴）。

### 实施记录：结构拆分第 4 步（chat_session · 机制 = part ×8）

**范围**：设计 `docs/design/structure-splits.md` §4.4 八段（`chat_session.dart` 1492 → ≤800，台账 #150 行 4）。
机制 = `part` + 顶层函数 `<name>Of(ChatSession owner, …)` + 一行委托（§3.3）；字段与后备存储留 owner；注解随委托逐字保留；缝均为本源档声明。

**改动**

- `lib/chat/chat_session.dart`：1492 → **793** 行。import 28 条不动；`part` 指令 0 → 8；
  `KernelChoice` / `ModelSettingChoice` 两个类整体搬出；98 个成员出档、原位留 98 条一行委托；
  7 处 `@override` 随委托保留（HEAD 11 个 `@override`，当前主档同为 11）。
- 八个新档（`lib/chat/session/`，首行均 `part of '../chat_session.dart';`）：
  `mode_state.dart` 186 · `kernel_proxy.dart` 201 · `transcript_proxy.dart` **225** ·
  `file_edits.dart` 141 · `file_paths.dart` 22 · `send_contexts.dart` 50 ·
  `session_commands.dart` 21 · `lifecycle.dart` 42。
- 按 §3.3 留 owner 的字段 / 私有 getter（缝表点名但字段不动）：`_kernelOptions`（late final）·
  `_btestId` / `_btestOption`（static const）· `_modelSettings` · `_filesSeen` · `_pendingEdits` ·
  `_runningTask` · `_dismissedGoal`；`prependedCount` 不在任何段，原位保留。
- **机制侧第四类差异（已入账）**：新增类内一行转发 `_notify()`（`chat_session.dart:776-778`）。
  四处搬出函数（`setKernel` / `dismissGoal` / `keepAllChanges` / `keepChanges`）要调
  `ChangeNotifier.notifyListeners`；它是 `@protected`（另带 `@visibleForTesting`），而 part 档顶层
  函数不是实例成员，直呼报 8 条 lint。`owner._notify()` 与原 `this.notifyListeners()` 同一实例同一调用。
  这是超出设计 §3.3「搬动只做三件事」的第四类形态，行为等价。

**验收读数（命令 + 结果）**

| 验收 | 命令 | 结果 |
|---|---|---|
| ① analyze 0 issue | `dart analyze`（全项目） | `No issues found!`（exit 0） |
| ② 测试基线（开工前，目标档干净） | `flutter test --no-pub test/chat test/kernel` | `+872 -4`，4 个红项见下 |
| ② 测试（本步后，同命令） | 同上 | `+872 -4`：**红项集合逐条一致，无新增失败** |
| ② 附：设计 §5 第 4 步字面门未合成一条命令；补跑其未被上条覆盖的档 | `flutter test --no-pub test/kernel_ui_test.dart` | `+31: All tests passed!` |
| ③ 主档行数 | `node -e` 换行符计数（设计 §5 口径） | **793**（≤800，余量 **7**；HEAD 1492；设计估 ≈782） |
| ④ 八档行数 | 同上 | 186 / 201 / **225** / 141 / 22 / 50 / 21 / 42（均 ≤500，最大 225） |
| ⑤ 逐块比对 | 令牌级脚本（对照 HEAD 快照；归一化只允许 `owner.` / `ChatSession.` 前缀、签名展开、缩进、`_notify`↔`notifyListeners`） | **100/100** 成员（98 成员 + 2 类）`bodyDiffs: 0`；声明面 91/98 逐字相等，另 7 条仅差已核的 `@override` 行位置（7 条委托的上一行均为 `@override`） |
| ⑥ 反推校验 | 行级 LCS 对 HEAD 快照 | `1492 − 810 + 111 = 793`，与当前主档逐行相等。111 条新增 = 98 委托 + 8 part 指令 + 3 行 `_notify` + 2 空行；707 条非空删除行**全部**落在搬出范围内（`strayRemoved: 0`；搬出范围内另有 7 个 `@override` 行由 LCS 匹配到委托的注解行） |
| ⑦ 改动面 | `git status --porcelain` / `git diff --name-only` | 增量 = `M lib/chat/chat_session.dart` + `?? lib/chat/session/`；无 `test/`、无其他 `lib/`（基线见下） |
| ⑧ 新档首行 | 逐档读取 | 八档均 `part of '../chat_session.dart';` |
| 附：格式 | `dart format --output=none` | 未对整档跑 format（HEAD 版主档即非 format-clean，跑 format 会重排既有代码，违反纯搬运；第 2 / 3 步同口径）。本步新写行有 >80 列者，属排版；主档余量 7 行，重排会加行并越过 800，故不改 |

**基线红项（开工前与本步后逐条一致，既有且与本步无关；`test/**` 未改一行）**

1. `test/chat/files_seen_test.dart`：`filesSeen is the same list while no file is new`（Windows 分隔符）
2. `test/chat/side_panel/side_panel_test.dart`：markdown preview 保存（macOS variant），期望 `'# Notes\n'`、实际 null
3. `test/chat/side_panel/side_panel_test.dart`：drop 文件链接（Windows 分隔符）
4. `test/kernel/dart_core_e2e_test.dart`：期望 `diff: color.txt +2`、实际为完整临时路径

注：本批开工前的记法是 `test/chat` 4 项 + `test/kernel` 1 项；本机实测为 3 + 1 = 4 项，按实测记账。

**工作树基线（开工前已存在，非本步改动）**

`M docs/batches/2026-10-22-browser-biz-test-mode.md` · `M docs/batches/2026-10-23-ledger-sweep.md` ·
`M docs/batches/2026-10-23-structure-splits.md` · `M docs/design/structure-splits.md` ·
`M lib/ide/git/git_repository.dart` · `M lib/kernel/thincoder/thincoder_warm.dart`。
开工时另有根目录 `?? 300`（0 字节空档）；本步未碰，收尾复查时已不在盘上（非本步删除，交父侧核）。

**设计漂移（交父侧 / eng-designer；实施不改文档）**

- **行数**：设计 §4.4 / §4.6 估 ≈782（余量 ≈18），实测 **793**（余量 7）。超出 11 行来自委托行数与段间空行；八档实测最大 225，反低于设计估 250。门仍成立。
- **缝表标注**：§4.4 第 3 段把 `_runningTask` 记作「字段，留 owner」，实为私有方法（`chat_session.dart:539`）；留 owner 的结论不变。
- **点名成员计数**：设计写 101 成员（15/31/29/13/2/3/4/4），其中 `_kernelOptions`（late final）、`_btestId` / `_btestOption`（static const）按 §3.3 留 owner ⇒ 委托 98 条。
- **`@protected` 转发形态**：设计 §3.3 未记载本步的 `_notify()` 形态（见上「改动」）。
- **测试门命令**：设计 §5 第 4 步字面写 `flutter test --no-pub test/chat test/kernel_ui_test.dart`；本步按任务书 AC ② 跑 `test/chat test/kernel`，并补跑 `test/kernel_ui_test.dart`（覆盖其差集）。

**轮次与终态**

- 内部 explore 偏差审计：1 轮，3 条（① 测试门覆盖差一条命令 → 已补跑；② `_notify` 第四类 → 本节入账；③ 设计未回填实测 → 已列漂移）；OUT-OF-LIST 0 条。
- 内部 advisor 代码评审：第 1 轮 **changes-required** —— 1 🟡 must fix（本节缺第 4 步读数）· 1 🟡（批档 §2 仍写「四段」，属 eng-designer 笔域）· 5 🔵（`file_paths.dart` 文档归位 · `_notify` 未记载 · 新写长行 · 设计数字漂移 · `_runningTask` 标注）。
- 修正轮 1：本节落盘；`file_paths.dart` 两段 doc 各归其位（`[path] absolute…` 移回 `_absoluteOf`）；其余按「不改他人笔域 / 不改设计档 / 重排会越 800 门」逐条处置；analyze、行数、逐块比对、测试门全部复跑。
- 终态：见本节补记（advisor 第 2 轮复核后）。

**补记（advisor 第 2 轮复核后）**

- 内部 advisor 代码评审第 2 轮：VERDICT **pass**（code · 复核面 `lib/chat/chat_session.dart` + `lib/chat/session/file_paths.dart` + 本档 §5）。第 1 轮七项逐条：
  ① must-fix（第 4 步读数未落盘）→ **Fixed**（本节 `:357` 起；读数与盘上 793 行、11 处 `@override`、`chat_session.dart:778` 逐条吻合）；
  ② 🟡 批档 §2 仍写「四段」→ **Accepted**（§2 属 eng-designer 笔域；请在 §6 收口前改 `:53` / `:69`）；
  ③ 🔵 `file_paths.dart` 文档归位 → **Fixed**（`[path] absolute…` 回到 `_absoluteOf`，档 23 → 22 行；纯注释，无行为面变化）；
  ④ 🔵 `_notify()` 未记载 → **Fixed**（本节 `:374-378` 入账，代码 `:776-777` 就地写明）；
  ⑤ 🔵 新写长行 → **Accepted**（重排约 10 行会越过 800 门，主档余量 7；lint 面不报列宽）；
  ⑥ 🔵 设计 ≈782 未回填 → **Accepted**（本节 `:414` 已列漂移，设计档归 eng-designer）；
  ⑦ 🔵 `_runningTask` 标注 → **Accepted**（本节 `:415` 已列漂移）。
- 第 2 轮新增 1 条 🔵（非阻塞，记录面）：本节上段把 `_runningTask` 列在「字段 / 私有 getter」小标题下，而 `:415` 已说明它是私有方法。本条补记即更正口径：`_runningTask` 为**私有方法，留 owner**。
- 终态：**clean**（内部 explore 偏差审计 1 轮 · 内部 advisor 代码评审 2 轮，终判 pass · 修正轮 1 次 = 本节落盘 + `file_paths.dart` 注释归位；无未决 🔴）。

### 实施记录：结构拆分第 5 步（composer · 机制 = part ×6）

**范围**：设计 `docs/design/structure-splits.md` §4.3 六段（`lib/chat/composer/composer.dart` 2350 → ≤800，台账 #150 行 3）。
机制 = `part` + 顶层函数 `<name>Of(ChatComposerState state, …)` + 类里一行委托（§3.3）；字段与后备存储留 owner；注解随委托逐字保留；`part` 档之间不互相 import。

**改动**

- `lib/chat/composer/composer.dart`：2350 → **556** 行（≤800，余量 244）。import 50 行不动；`part` 指令 0 → 6；
  类头/构造/字段/`_rankOthers` 不动；82 个方法体出档、原位留 82 条委托（78 条一行 + 4 条带 `super` 的生命周期委托）；
  11 处 `@override` 随委托保留。
- 六个新档（同级，首行均 `part of 'composer.dart';`，无 import）：
  `composer_toolbar.dart` **414** · `composer_editing.dart` **475** · `composer_menu.dart` **248** ·
  `composer_pointer.dart` **221** · `composer_view.dart` **345** · `composer_message.dart` **325**（均 ≤500，最大 475，余量 25）。
- 整体搬出的顶层声明：5 个小部件类 `ComposerPermissionSwitch` / `_PolishButton` / `_ContextRing` / `_RingPainter` / `_SendButton` → toolbar；
  `_ShownOfText` typedef → editing（与产出它的 `_shownOfText` 同档；主档保留其类型引用 `_ShownOfText? _shownBuilt`）。
- 按 §3.3 留 owner 的字段（缝表点名但字段不动）：`_suggestion` `_suggestionKey` `_lookups` `_menuOwner` `_menuRegistered`
  `_ghostAt` `_ghost` `_ghostFiles` `_ghosting` `_menuPressAt` `_clickDownAt` `_clickWindow` `_clickUpAt` `_clickOnSelection`
  `_secondClick` `_editor` `_shownBuilt` `_editorColors` `_built` `_builtFrom` `_hovers` `_historyAt` `_historyDraft` `_historyShown`
  `_recalling` `_menuKind` `_highlighted` `_menuX`，以及静态常量 `_fontSize` `_textStyle` `_lineHeight` `_minEditorHeight`
  `_maxEditorLines` `_maxImages` `_suggestionKeyContext` `_clickSlop`。
- **机制侧新增一行转发（`_notify` 同类，单列）**：`void _setState(VoidCallback fn) => setState(fn);`（`composer.dart:205`）。
  `State.setState` 是 `@protected`，part 顶层函数直呼报 `invalid_use_of_protected_member`；`state._setState(...)` 与原 `setState(...)` 同一实例同一调用。
  这是第 4 步 `_notify()` 先例的同一形态，行为等价。
- **super 调用留在类内**：`initState` / `didUpdateWidget` / `didChangeDependencies` / `dispose` 的 `super.*` 无法出现在顶层函数，
  故四条委托写成块体，`super` 保持原相对位置（前三条在前、`dispose` 在后），part 函数只承接其余函数体。
  顶层函数的 `didUpdateWidgetOf` 去掉 `covariant`（该修饰只对实例方法参数成立；类的委托签名逐字保留 `covariant ChatComposer oldWidget`）。
- `static bool _inAtom(...)` 的委托不带 owner：`=> _inAtomOf(text, offset)`。

**验收读数（命令 + 结果）**

| 验收 | 命令 | 结果 |
|---|---|---|
| ① analyze 0 issue | `dart analyze`（全项目） | `No issues found!`（exit 0） |
| ② 测试基线（任务书记法，开工前目标档 HEAD 干净） | `flutter test --no-pub test/chat test/composer_test.dart`（基线，父侧记） | 红项 5 条：`test/chat` 3 · `composer_test` 2（见下） |
| ② 测试（本步后，同命令） | 同上 | `+648 -5`：**红项集合逐条一致，无新增失败** |
| ② 附：设计 §5 第 5 步命令的差集 | `flutter test --no-pub test/kernel_ui_test.dart` | `+31: All tests passed!` |
| ③ 主档行数 | `node -e` 换行符计数（设计 §5 口径） | **556**（≤800；HEAD 2350；设计估 379–520） |
| ④ 六档行数 | 同上 | 414 / **475** / 248 / 221 / 345 / 325（均 ≤500） |
| ⑤ 逐块比对 | 令牌级脚本（对照 HEAD 快照；归一化只允许 owner 前缀、签名展开、缩进、`this`→`state`、`_setState`） | **82/82** 成员 `bodyDiffs: 0`；见下「逐块比对」 |
| ⑥ 反推校验 | 行级 LCS 对 HEAD 快照 + 新增行分类 | 309 行保留、1874 行删除（全部落在搬出块内，另 1 行为旧类尾 `}`）、97 行新增（分类见下），无未解释行 |
| ⑦ 改动面 | `git diff --name-only` / `git status --porcelain` | 本步增量 = `M lib/chat/composer/composer.dart` + 六个 `??` 新档；无 `test/`、无其他 `lib/`（基线见下） |
| ⑧ 新档首行 | 逐档读取 | 六档均 `part of 'composer.dart';`（同级形态） |
| 附：格式 | 未跑整档 `dart format` | HEAD 版主档即非 format-clean，整档重排会重排既有代码并改变逐行比对；第 2–4 步同口径 |

**基线红项（开工前与本步后逐条一致，既有且与本步无关；`test/**` 未改一行）**

1. `test/chat/files_seen_test.dart`：`filesSeen is the same list while no file is new`（Windows 分隔符）
2. `test/chat/side_panel/side_panel_test.dart`：markdown preview 保存（macOS variant）
3. `test/chat/side_panel/side_panel_test.dart`：drop 文件链接（Windows 分隔符）
4. `test/composer_test.dart`：`mode picker opens on press, animates, and follows the mouse`
5. `test/composer_test.dart`：`Shift+Tab in the input goes through the modes`

注：设计档 `:279` 记 `test/chat` 4 项（另含 `test/kernel` 1 项）；`test/chat` 单跑本机实测 3 项，批档 `:403` 已按 3 + 1 记账，本步按实测 3 + `composer_test` 2 = 5 记账。

**逐块比对（对照 HEAD 版 `lib/chat/composer/composer.dart`）**

- 82 个成员的函数体令牌比对：`diffs: 0`。差异只有已声明的几类：① 签名展开为 `<name>Of(ChatComposerState state, …)`（静态方法无 owner 参数）；
  ② 实例/静态引用加前缀 `state.` / `ChatComposerState.`；③ 类成员 → 顶层函数缩进减 2；④ `this` → `state`（含 `by: this`、`delegate: this`、`identical(…, this)`）；
  ⑤ `setState` → `state._setState`（上列入账的一行转发）；⑥ 四条生命周期委托的 `super` 留在类内（结构需要，行为位置不变）。
- 六个整体搬出的小部件类与 `_ShownOfText` typedef 与 HEAD 逐字一致（仅缩进不变；类在顶层，不减 2）。
- 逐段读数（成员数 / 令牌 diff）：toolbar 1/0 · editing 21/0（含 typedef）· view 16/0 · message 15/0 · menu 16/0 · pointer 17/0。

**反推校验**

`HEAD 非空行 2183 = 保留 309 + 删除 1874`；`当前主档非空行 406 = 保留 309 + 新增 97`。
删除行：1873 行全部落在 82 个成员块 + 6 个顶层块内，另 1 行是旧类尾 `}`（`HEAD:2062`，类闭合位置随其后类搬出而上移）。
新增 97 行 = 6 条 `part` 指令 + 78 条一行委托 + 4 条生命周期委托的调用行 + 1 行 `_setState` 转发 + 8 行注释
（`_setState` 文档 3 行 + 分档说明 5 行）；其余委托的 `@override` / 签名 / `super` 行均由 LCS 匹配为 HEAD 保留行。无未分类新增行。

**工作树基线（开工前已存在，非本步改动）**

`M docs/batches/2026-10-22-browser-biz-test-mode.md` · `M docs/batches/2026-10-23-ledger-sweep.md` ·
`M docs/design/browser-biz-test.md` · `M docs/design/structure-splits.md` · `M lib/ide/git/git_repository.dart` ·
`M lib/kernel/thincoder/thincoder_warm.dart`。本步净增量 = 目标档 + 六个新档。
开工前 `git status` 中作曲家档案为空；HEAD 快照 `git show HEAD:lib/chat/composer/composer.dart` 与本步对照副本逐字节一致。

**设计漂移（交父侧 / eng-designer；实施不改文档）**

- **缝 2 的四处草稿方法改落 message 档**：设计 §4.3 缝 2 点名 `_takeDraftFiles` `_takeDraftMessage` `_saveDraft` `_handleDraftChanged` → `composer_editing.dart`；
  若照字面执行，editing 为 547 行内容 + 头部/空行 ≈ 575 > 500。按设计 `:176`「判据以行数门为准（主档 ≤800、新档 ≤500）」把该四块（106 行）落在
  `composer_message.dart`（草稿 = 未发出的消息；`_submit` 直呼 `_saveDraft` 的写方/消费方因此同档）。六档档名与总数不变，主档搬出面不变。
- **`state.setState` 表述**：设计 §4.3 风险行写「`setState` … 改成 `state.setState` 等」；实际用一行 `_setState` 转发（`@protected` 不可从顶层函数直呼）。
- **尺寸估值**：设计估主档 379–520 / 委托 ≈65 行 / editing ≈460；实测主档 **556**、委托 **82** 条、editing **475**。
  按设计 `:110` 已记的实测口径（≈2.13 行/成员）重算即约 175 行委托；硬门全部成立。
- **测试基线计数**：设计 `:279` 记 `test/chat` 4 项，本机单跑为 3 项（第 4 项在 `test/kernel`），与批档 `:403` 的实测记账一致。

**轮次与终态**

- 内部 explore 偏差审计：1 轮，0 🔴 · 2 🟡 · 4 🔵。代码面全部达标（主档/六档行数、首行、btest 边界、seam 覆盖、无未限定成员引用）；
  2 条 🟡 = ①本节尚未落盘（本轮已补，即本段）②缝 2 改落（已在上「设计漂移」入账）；4 条 🔵 = 设计档的 `state.setState` 表述、尺寸估值、测试基线计数、`.thincoder/tmp/split5/` 校验脚本（gitignore 的临时区，不进 git 面）。
- 内部 advisor 代码评审：见下补记。
- 修正轮：1 次（analyze 首跑 8 条：四个生命周期 part 函数名与委托不匹配、`_inAtom` 静态成员经实例访问、两处字段初始化器改用 `_xOf(this)` 致委托未引用；同轮改为 `_initStateOf` 等四名、`ChatComposerState._inAtom`、字段初始化器保持 `_createController()` / `_initialPool()`；复跑 analyze 0 issue、测试门与比对全绿）。
- 终态：见下补记。

**补记（advisor 代码评审后）**

- 内部 advisor 代码评审：第 1 轮 **pass**（code · 七档）。0 🔴 · 1 🟡（报告项）· 3 🔵，均无代码 must-fix：
  ① 🟡 设计 §4.3 缝 2 仍点名四个草稿方法落 `composer_editing.dart`，实现落 `composer_message.dart`（设计 `:170` 的 `composer_editing.dart` 一侧 vs 代码 `composer_message.dart:222` 起）——
  **Accepted**（本步按设计 `:176`「判据以行数门为准」处置并在本节「设计漂移」入账；设计档归 eng-designer / 父侧收口前回填，代码不改）。
  ② 🔵 十个公开方法的委托助手无 `_` 前缀（`buildOf` / `focusOf` / `insertFilesOf` / `chatContextKeyOf` / `chatCommandsOf` / `chatComposingOf` /
  `fileDragOverOf` / `fileDragLeaveOf` / `fileDropOf` / `editorScrollPositionOf`），使 `composer.dart` 的公开命名面多出十个符号，与设计 §3.3「顶层私有函数」不一致 ——
  **Accepted**（kernel 第 2 步 `canRevertNowOf` 为同形先例；本轮改名会动 10 个委托与 10 个函数名并需全量复跑，收益不抵风险。建议父侧收口时在 §3.3 记一句口径，或另轮统一加 `_`）。
  ③ 🔵 设计估值漂移未回填（主档估 379–520 实测 556、委托估 ≈65 实测 82、message 估 ≈240 实测 325）—— **Accepted**（本节「设计漂移」已记账，设计档归父侧 / eng-designer）。
  ④ 🔵 六个新档未过 `dart format`（如 `composer_toolbar.dart:139` 两名同行）—— **Accepted**（批档已述理由：主档 HEAD 即非 format-clean，整档重排会改变逐行比对；六个 part 档可在另轮单独 format）。
- 内部 explore 偏差审计 1 轮 + advisor 1 轮 + 本节落盘，代码在审计后**零改动**（两轮的发现均为记录/文档面，无代码 must-fix）。
- 终态：**clean**（内部 explore 偏差审计 1 轮 · 内部 advisor 代码评审 1 轮，终判 pass · 无未决 🔴）。

## §6 验证与收口（父代理）
