# 2026-11-16 · three-capabilities
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-16 · 来源 = 用户 2026-11-16 00:23「然后做什么」→ 本席建议批 A（三项一行接口）→ 用户 00:53「提交，开批」。
> 台账 = #255（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：三项「一行接口」能力声明（RevertsChanges / ConfirmsModelSwitch / AcceptsImages）

**来由**：用户 2026-11-15「能抄过来的都抄过来」→ 探子 #26 逐项判定 13 项差距 → 本批取其中三项：本仓可做、只改能力声明、运行时风险近零。

**逐项实读依据（#26 判定表，本轮未重查）**：

| 能力 | 现状 | 落点 |
|---|---|---|
| `RevertsChanges` | `thincoder_revert.dart` 的 `applyRevertOf` 已走 `session/revert`；`PlansReverts` 已声明；`chat_session.dart` 的 `undoAllChanges` 只取 `revertChanges(sinceTurn:)` | `thincoder_kernel.dart` implements 列表 + 一个方法转调 `applyRevertOf` |
| `ConfirmsModelSwitch` | `handlers-session.mjs` 的 `applyConfigOption` 只换 provider、不重启；UI 侧 `session_model_picker.dart` 拿到 `false` 就直接选 | implements + `switchRestarts` 恒 `false`（这是事实，不是妥协） |
| `AcceptsImages` | 图片两条路都已通（native 路 + 文件路），UI 的 `kernel_proxy.dart` 两个 marker 等价 | 只补能力名，UI 零变化 |

**硬约束（用户 2026-11-16 00:53 原话）**：**「不要关闭我现在的baocode，因为我在使用」**——本批不得重编、不得重启、不得结束任何正在运行的实例；验证只跑测试进程。

**边界**：不改任何行为（除「切模型不再多弹一次确认」这一项由 `switchRestarts` 为假带来）；不新建组件；不动面板与写入路径。

**下一步**：§2 设计 → 评审 → 批准 → 实施。

### 设计回来后的三条裁决

**① `AcceptsImages` 不落（采纳设计席判断）**

- 宿主判据的原文注释（`lib/chat/session/kernel_proxy.dart`）：「Whether pictures sent with a message are taken: **by the protocol** ([AcceptsImages]), or as files it is told of ([AcceptsImageFiles]).」——该标记断言的是「走协议路」。
- thincoder 走哪条路，由**握手能力位**决定；旧 CLI 发的是文件路径（§22.1 / D82）。
- 编译期标记不能随握手变化 ⇒ 声明它等于在旧 CLI 上说假话。
- 既有用例已把这一判断写死：`expect(s.kernel, isNot(isA&lt;AcceptsImages&gt;()));`。
- 宿主判据本就是「两者取或」，声明它换不来任何新判据。
- **本批条目从三条降为两条**；该能力另记台账 #256（条件：宿主把标记改成运行期能力位）。

**② §1 边界句订正（设计席知会，成立）**

- 原文写「除『切模型不再多弹一次确认』这一项由 `switchRestarts` 为假带来」——**错**。
- 宿主对非实现者的回落本就是 `_ =&gt; false`，今天**已经不弹**。
- 故条目 2 是**纯粹的清单对齐，零行为变化**，不需要任何豁免。

**③ §1 边界句补一条可见面**

- 条目 1 会让 `undoAllChanges` 从空值变为可用。
- 可见面 = 手机链路「全部撤销」（`workspace_bridge`）与窄标签栏的 `undoAll`（`ide_agent_edits`）。
- 对话页仍被计划路遮蔽。这是本批**唯一的可见面变化**（设计席已登记在 `design §32.10-5`）。

**实施轮两个首步读（`design §32.11`）**

- `ide_agent_edits.dart` 在 `canPlanRevert` 为假（在飞）时是否也接受 `undoAll`——若是则「在飞不回退」的门被打开，**停手回设计**。
- `thincoder_choices.dart` 有无同名成员。

### 评审轮 1 裁决（changes-required · 1🔴 + 5🟡 + 3🔵 ⇒ 9 条全受理）

**🔴 #1 是硬错，不是措辞问题。**

- `thincoder_choices.dart` 与 `thincoder_revert.dart` 首行都是 `part of &apos;thincoder_kernel.dart&apos;;`（评审轮实读）。
- part 档只能承载顶层声明，**不能给类加成员**。
- 现有帮手全为顶层形：`applyRevertOf(ThincoderKernel owner, …)`。
- 类成员只能写在 `thincoder_kernel.dart` 的类体，现有一行转调形是：
- `Future&lt;RevertOutcome&gt; applyRevert({required String sinceTurn}) =&gt;`
- `applyRevertOf(this, sinceTurn: sinceTurn);`

**修轮 5 定点（只改这九条，不扩面）**

- **#1**：受影响文件表改两行。① = implements 两项 + 两条一行转调成员（`revertChanges` / `switchRestarts`）。②③ = part 档的顶层帮手 `revertChangesOf` / `switchRestartsOf`。
- **#2**：`§32.1 ③` / `§32.9` 标题 / 批档 §2 上抛三处的「待裁」改为已裁结论 + 出处（批档 §1 ①），并撤掉「请裁决落 / 不落」。
- **#3**：补两个新名字的三问答复（形同 `design §31.12`）。已有读数：`lib/kernel/thincoder` 下两名字零命中 ⇒ `none found:`。接口成员在 `agent_kernel.dart`。
- **#4**：先例行的「29–38 行」改为点 part 文件名。
- **#5**：`§32.8` 的理由句改为判据口径——不改**既有用例断言的**业务可观察结果，且新增可见面无业务故事/生产记录 ⇒ 按准入不给行。
- **#6**：`§32.2` 的宿主门补全：先有 `if (_activeReview case final review?)` 支；kernel 支还要 `_pendingEdits.firstOrNull?.turnId` 非空。可见面说法同步加限制。
- **#7**：`§32.5` 结论加一句点名 `thincoder_kernel_test.dart` 在 >800 硬顶之上、立场记在 §5.2。
- **#8**：`§32.8` 写明「若收则该行号须先在 `test/RTM.md` 定行再写用例标题」。
- **#9**：留痕句改为「只在无会话路补一行」；`§32.4` 的「等价」改为「等价于去掉返回值，另加兜底」。

**不动的**：两条能力的取舍（`AcceptsImages` 仍不落）、`void` 面不外抛、`switchRestarts` 恒 `false`、T153–T155 的判据面。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）· 设计档落点 = `docs/design/thincoder-adapter.md` §32

| # | 条目（台账 #255） | 决议 | 落点 |
|---|---|---|---|
| 1 | `RevertsChanges` 声明 + 一把撤成员 | 落 | §32.1 ① / §32.4 |
| 2 | `ConfirmsModelSwitch` 声明（`switchRestarts` 恒 false） | 落 | §32.1 ② |
| 3 | `AcceptsImages` 只补能力名 | **不落**（§1 ① 已裁，采纳设计席判断） | §32.9 |

本批不新建设计档：同档已有 §22（图片两路）、§30（能力声明先例）、§32（本节）；一个能力面一个归属档，单点权威不另立副本。

### 机制设计（摘要，判据在 §32）

- ① `RevertsChanges`：`revertChanges({sinceTurn})` 转调既有 `applyRevertOf`，同一条 `session/revert`（`dryRun` 假）；失败走既有的可见 notice，`void` 面不外抛、只在无会话路补一行 `appEvent`（§32.1 ① / §32.4 / §32.6）。
- ② `ConfirmsModelSwitch`：`switchRestarts(model) => false`，事实是切 provider 不重启；宿主对非实现者今天已回落 `false`，故零行为变化（§32.2 第四行）。
- ③ `AcceptsImages`：不落。宿主的契约注释把该标记读作「by the protocol」，本内核是否走协议由握手能力位决定（旧 CLI 走落盘 + 路径行），编译期标记不能随握手变 ⇒ 在旧 CLI 上声明它就是说假话；宿主判据已是「两者取或」，声明它换不来任何新判据（§32.9）。

### 受影响文件与测试覆盖

见 §32.5（四处：`thincoder_kernel.dart` 的 implements 两项 + 两条一行转调成员、`thincoder_revert.dart` 的 `revertChangesOf`、`thincoder_choices.dart` 的 `switchRestartsOf`、`test/kernel/thincoder_kernel_test.dart` 的 T153–T155）。宿主六档零改动，Claude / Codex 内核零改动，外仓零改动。档位结论 = 无跨越（§32.5 末行；该测试档在 >800 名单内，只追加用例）。

### 验收对照（回指需求档 §5 与台账 #255）

| # | 判据 | 机检 |
|---|---|---|
| 1 | 一把撤经 `RevertsChanges` 走通同一条协议路 | T153 |
| 2 | 无会话可撤时失败可见、不静默、不外抛 | T154 |
| 3 | 切模型不重启被声明，宿主读法零变化 | T155 |
| 4 | 宿主与其它内核零回归 | 同一测试档既有用例不改而绿 |

变更面单元验收 = `flutter test --no-pub test/kernel/thincoder_kernel_test.dart`；全量与集成套件属父侧收口门，不在本批跑。

### 关键决策

见 §32.6（四条，含被否方案）。最要紧的一条：`RevertsChanges` 与 `PlansReverts` 并存不是重复——前者是一把撤（手机链路 / 窄标签栏），后者是先出计划的入口（对话页），且对话页那条被 `plans` 判据遮蔽。

### 上抛项

- **[上抛·知会] 条目 3 `AcceptsImages` 已裁 = 不落**（批档 §1 ①）：任务书原要「只补能力名」，代码的契约行与 D82 说声明它会在旧 CLI 上虚报（§32.9 两边原文）。判据 = 宿主判据已是「两者取或」、既有用例已写死 `isNot(isA<AcceptsImages>())`，声明它换不来新判据。要改判则须同轮改 `kernel_proxy.dart` 的读法与 D82 的口径，属另一轮。
- **[上抛·知会] §1 边界句的事实更正**：§1 写「除『切模型不再多弹一次确认』这一项由 `switchRestarts` 为假带来」——实测今天**已经不弹**：宿主对非实现者的回落是 `_ => false`（`lib/chat/chat_session.dart` 的 `bool switchRestarts(String model) => switch (_kernel) {` 之后第二臂），picker 拿到 false 即直接切。故条目 2 是零行为变化，与本批「不改任何行为」一致，无需豁免。
- **[上抛·知会] §1 边界句需补的一条**：条目 1 使 `undoAllChanges` 从空值变为可用，受影响的可见面 = 手机链路「全部撤销」与窄标签栏的 `undoAll`（`lib/link/workspace_bridge.dart` / `lib/ide/ide_agent_edits.dart` 的取用行）；前提是有 pending 编辑（`_pendingEdits.firstOrNull?.turnId` 非空）且不在评审态（`chat_session.dart` 的 `undoAllChanges` 两个门，§32.2 首行）；对话页仍走计划路。这是本批唯一的可见面变化，已登记在 §32.10-5。
- **[上抛·知会] 实施轮首步读**（§32.11 U1）：`ide_agent_edits.dart` 在 `canPlanRevert` 假时是否也接受 `undoAll`（可能打开「在飞可回退」的门，若是则停手回设计）。原第二个首步读（`thincoder_choices.dart` 有无同名成员）本轮已闭：该档 grep 零命中，答案与两个新名字的三问答复一并落在 `design §32.12`。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

**评审范围** = `docs/design/thincoder-adapter.md` §32 · 批档 §2。

**计数** = 🔴 1 · 🟡 5 · 🔵 3。

**评审轮实读（仅核对设计断言）**：`lib/kernel/agent_kernel.dart` · `thincoder_kernel.dart` · `thincoder_revert.dart`。

**实读续**：`thincoder_choices.dart` · `lib/chat/chat_session.dart` · `test/kernel/thincoder_kernel_test.dart` · `test/RTM.md`。

**#1 🔴 可行性 / 文件表** — §32.5 ③ 把 `switchRestarts` 记在 `thincoder_choices.dart`，② 未给 `revertChanges` 定档。

**#1 依据** — 两档首行均为 `part of 'thincoder_kernel.dart';`（实读），part 档只放顶层声明。

**#1 后果** — 类成员只能进 kernel 类体（现存全为 `x(...) => xOf(this, ...)`）⇒ 表按字面不可实现。

**#1 影响** — T153 / T155 恰要这两个成员在场。

**#1 建议** — ① = implements 两项 + 两条一行转调成员；②③ = part 档的 `revertChangesOf` / `switchRestartsOf`。

**#2 🟡 文档状态** — 批档 §1 已写「**① `AcceptsImages` 不落（采纳设计席判断）**」。

**#2 残留一** — §32 仍留「（§32.9，待裁）」「**不落**（§32.9，待裁）」；§32.9 标题仍是「### 32.9 待裁项」。

**#2 残留二** — 批档 §2 同项仍记「**不落，待裁**」并要求「**请裁决落 / 不落。**」。

**#2 定性** — 两边机制文字一致（都不落）⇒ 状态滞后，非机制冲突；建议换成已裁结论 + 出处。

**#3 🟡 既有件三问** — 缺 `existing:` / `none found:` 行的名字 = `revertChangesOf` / `switchRestarts`。

**#3 依据** — §32.11 U2 把同名成员核对推到实施轮（「实施轮首步确认无同名成员」）。

**#3 已核** — `lib/kernel/thincoder` 下两名字零命中（`none found`）；接口成员在 `lib/kernel/agent_kernel.dart`。

**#3 建议** — 补三问行（形同 §31.12），随即销掉 U2。

**#4 🟡 引用形** — §32 先例行 对齐 ② 写「（part 表见 `thincoder_kernel.dart` 的 29–38 行）」。

**#4 建议** — 行段随插入漂移 ⇒ 改点 part 文件名。

**#5 🟡 验收自洽** — §32.8 写「理由：本批不改任何业务可观察结果」。

**#5 相抵** — 同段又写「唯一可见面变化 = 手机链路与窄标签栏的「全部撤销」从「没有这条路」变为可用」。

**#5 建议** — 判据允许的唯一理由 = 不改既有用例断言的业务可观察结果、且不新增产品真正需要的情景。

**#6 🟡 判据准确度** — §32.2 首行写「`undoAllChanges` 只在 `_kernel is RevertsChanges` 时给出回调」。

**#6 实读** — `chat_session.dart` 的该 getter 先有 `if (_activeReview case final review?)` 支。

**#6 实读二** — kernel 支还要 `_pendingEdits.firstOrNull?.turnId` 非空。

**#6 建议** — 可见面说法补「有 pending 编辑（且不在评审态）」这一限制。

**#7 🔵 档位结论** — §32.5「四档均无档位跨越」经实测成立。

**#7 实测一** — `lib/kernel/thincoder/thincoder_kernel.dart` 497 行 · `thincoder_revert.dart` 132 行。

**#7 实测二** — `thincoder_choices.dart` 300 行 · `test/kernel/thincoder_kernel_test.dart` 5582 行。

**#7 实测三** — 函数档无 300+ 行单函数（kernel 档成员全是一行转调）。

**#7 建议** — 唯该测试档在 >800 硬顶之上（立场记在 §5.2），结论行加一句点名。

**#8 🔵 集成用例准入** — §32.8 对手机「全部撤销」不立行，留判定条件。

**#8 观察** — 该面在两个入口变为可用；是否算「产品真正需要的情景」是准入口径判断。

**#8 建议** — 收则该行号须先在 `test/RTM.md` 定行再写用例标题。

**#9 🔵 留痕精度** — 「只补一行 `appEvent`」在 RPC 失败路上是第二行。

**#9 依据** — `thincoder_revert.dart` 的 `_revertOf` 已写 `appEvent('thincoder', 'session/revert($turn) failed: $error');`。

**#9 另一** — 只有在「无会话」路（`throw StateError(...)` 之前只发 notice）缺这一行。

**#9 另二** — §32.4「行为等价于已有的 `applyRevert` 去掉返回值」不严格：新增兜底使其不等价。

**核过成立一** — 条目 2 零行为变化：宿主回落已是 `_ => false,`，首臂原文见 §32.2。

**核过成立二** — 条目 3 不落的前提成立：`AcceptsImageFiles` 已在 implements 列表内。

VERDICT: changes-required

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
