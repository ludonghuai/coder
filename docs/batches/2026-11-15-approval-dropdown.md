# 2026-11-15 · approval-dropdown
> 六段，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 每段只有一个作者：作者的段可 `append` 加内容、可就地改（`edit`，§4.19）；非作者一概拒。
> 编制：主 agent · 2026-11-15 · 来源 = 用户 2026-11-15 三条排队消息（同一诉求）：「把那个auto的按键也改成claude code模式的那个下拉框吧，有点像大一统王朝了」·「auto的按键删掉」·「改成claude模式的下拉框来替代按键」。
> 台账 = #246（— · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-15
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：输入框右下角的审批控件从「开关」改成「下拉框」

**已定决定**：删掉 auto 开关，改成与 Claude Code 模式一致的下拉框 · 用户原话：「把那个auto的按键也改成claude code模式的那个下拉框吧，有点像大一统王朝了」+「auto的按键删掉」+「改成claude模式的下拉框来替代按键」（三条同一诉求，一次处理）· 时间：2026-11-15 20:42

**现状（本轮实读）**：

- 控件是**开关**：`lib/chat/composer/composer_toolbar.dart` 里 35×20 的 `AnimatedContainer` + 圆点（`width: 35, height: 20`），两档靠 `permission.options[on ? 0 : 1]` 切换，`on = permission.selected.id == permission.options[1].id`。
- 数据面已经是「选项 + 当前值」：`KernelChoice permission`（`permission.options` / `permission.selected` / `permission.onSelected`），所以换形态不动内核契约。
- 模板在盘：`lib/chat/composer/composer_picker.dart` 的 `ComposerPicker`（`KernelChoiceKind` 分面）+ `composer/pickers_row.dart` 的 `PickersRow` 布局助手。

**边界**：不改内核能力契约（`SelectsPermission` 不动）；不改选项语义（两档仍是原来的两个 id）；不动其它 picker 的形态。

**下一步**：§2（设计席：落点、复用哪个 picker、受影响档、验收）→ 设计评审 → 批准 → eng-coder 实施。

### 评审轮 1 裁决（changes-required · 2🔴 + 2🟡 + 2🔵）

- **第 4 条（需求档 F13 冲突）= Not an issue**：设计席交付后本席已改需求档 F13——形态句换成「composer 左簇的审批药丸 + 菜单（既有 `ComposerPicker`；两档与多档内核同形）」，并带上用户原话；旧的文件坐标随句子一并清掉。设计席 §K 的 R1 上抛已作废。
- 其余 5 条全受理。

**修轮 1 定点（只改这五条，不扩面）**：

1. 🔴 **§17.1 补完就地改写**：删掉被否形态的每一句——③ 标题「宿主 1 档 = composer 的右下角开关」· 「`label` / `icon` 留在数据面，开关面不渲染——见下『无文字 label』」· 表行「本面不取色，见下『颜色』」· 一句话「桌面用 composer 右下角的小开关显示它、切换它」· 偏离 1「右下角紧凑开关，不是左簇菜单 pill」；删重复的两段「写失败面」；§17 头部的「composer 右下角的小开关，§17.4 ㉗」一并改。只留「药丸 + 菜单」一套说法。
2. 🔴 **验收与走查改成药丸形态**：§17.4 ㉘ 的 T61 行 · §17.6 的「服务端短路 + 桌面开关」与「写失败 ⇒ 批准成立、开关不变」两处 · §17.9 步 2 / 3 / 9（现写「knob 在右、track 橙」「点开关打开」）。改成：按药丸开菜单、选 `Auto`、读药丸的文案 / 图标 / 警示色。
3. 🟡 **档位结论改成如实**：现写「无文件跨档」，实测 `test/composer_test.dart` **2416 行**（越 >800 硬顶）；另两档 190 / 387 行、`composer.dart` 763 行（拆分已落，不新增跨档）。改成点名该档 + 带上已登记的缝方案与触发。
4. 🔵 `thincoder_choices.dart` 两处注释仍叫「approval switch」——在 §2 §D 加一行「仅注释」登记，或写明沿用旧名是本批取舍。
5. 🔵 三问里 `ComposerPicker` 的 where-it-lives 指向了使用点（`composer_toolbar.dart:58-74`）；类本身在 `composer_picker.dart`，改指该档，使用点保留为消费坐标。

**不动的**：本批三处代码改动、条目表、边界、RTM 增量结论（评审已核为零增量且理由成立）。

**另加一条（机检带回）**：§2 有 1 处「文字太长，难于阅读」命中（第 150 行，作者 = eng-designer）。修轮一并把它按「；」拆成短句或列表项，否则收口门会拦下。

### 评审轮 2 裁决（changes-required · 1🔴 + 1🔵）

- **第 1 条 🔴 受理，我判错了，评审对**：我上轮以为 §17.4 的增量表属「历史账」可不碰，但**本批自己已经把同表的 ㉘ 改成了药丸**——一表两行一说开关一说药丸，说不过去。§H 的豁免覆盖不到这里。
- **第 7 条 🔵 受理**：§17.9 步 8 漏在改写清单外。
- 第 2 / 3 / 5 / 6 条评为 Fixed、第 4 条 Accepted，均同意。

**修轮 2 定点（只改这几处，不扩面）**：

1. `§17.4 ㉗`：`ComposerPermissionSwitch` 那一格改成「批 6 加的右下角拨动开关，**批 24 已删**；审批面现为左簇审批药丸，见 §17.1-③」；㉗ 的「放置分支（两档 ⇒ 右端）」改为如实。
2. `§17.4` 正文「用户 21:25 定的形只落在这一处」：改成带日期的历史陈述 + 指向 2026-11-15 的新定形。
3. `§17.4` 体量句「本批只加这一个控件（`ComposerPermissionSwitch` + 放置分支）」：同上处理。
4. `§2 §B` 的跨节改写清单补上「§17.4 ㉗」。
5. `§17.9` 步 8「开关 + 发一条」：改成「按药丸选 `Auto` 后发一条」。

**不动的**：§17.1 / §17.5–§17.7 / §17.9 其余步、本批三处代码改动、条目表。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### A · 本批条目（覆盖）

| # | 条目 | 来源 |
|---|---|---|
| 1 | composer 的审批控件由「两档拨动开关」改为与 Claude Code 一致的下拉框（药丸 + 菜单）；两档内核与多档内核同形 | 用户 2026-11-15 三条排队消息（§1 已定决定） |

**不在本批**：

- 内核契约 `SelectsPermission` 不动。
- 选项语义不动：仍是 `ask` / `auto` 两个 id，仍写 `set_config_option('autoApprove', bool)`。
- 其它 picker（内核 / 模式 / 模型）的形态与位置不动。
- 审批弹窗（`request_permission` 三选项）与设置页不动。

### B · 设计档落点

- 机制所有者 = `docs/design/thincoder-adapter.md` §17.1 ③「形态与放置」——就地改写（开关 ⇒ 下拉框），不新建文档。
- 同节连带：§17 头部的「宿主 1 档」句、§17.1 的一句话与偏离 1、③ 的标题 / 选项表 / 数据面各句、④ 的写路径与失败面——被否形态的每一句删掉，只留「药丸 + 菜单」一套说法；③ 下逐字重复的两份「写失败面」只留数据面那一份。
- 跨节连带就地改写：同档 §5 的批 6 指针句、§6 的 F13 落地摘要行、§14-19 的 description 面、§17.2 的兜底显示句、§17.3 的旧 CLI 兼容行、§17.4 ㉗ 的开关行与 ㉘ 的 T61 行、§17.6 的两行、§17.9 步 2 / 3 / 7 / 8 / 9。
- §17.4 顶部加一行现状指针（台账 #247）：本表是批 6 的交付账，审批控件现状以 §17.1-③ 为准。
- 本轮实读为零改动：§17.5 决策表（D41 / D42 已是药丸口径）、§17.7 的 T61 行；`docs/design/structure-splits.md` 全文不出现该类名（拆档表只列 `_buildToolbar` 等五个符号）；`docs/design/fork-deltas.md` 的 `test/composer_test.dart` 行已按「审批药丸 + 菜单」登记。

### C · 机制设计

**一句话**：删掉 `ComposerPermissionSwitch`，把审批 pill 的显示条件从「档数 ≠ 2」放开成「有审批面就出 pill」。两档内核走的正是 Claude 五档今天走的那条既有路径（`lib/chat/composer/composer_toolbar.dart:58-74`）。

**最近先例（三问答复）**：

- where-it-lives = `lib/chat/composer/composer_picker.dart`（`class ComposerPicker` 所在档）· name: `"ComposerPicker"` · consumers: Claude 的审批菜单（5 档）、模式 picker、dock 的内核 picker；使用点 = `lib/chat/composer/composer_toolbar.dart:58-74`（左簇 `PickersRow` 的审批项）。
- 结论 = 复用既有件，零新组件。偏离点 = 无：本批不是新造形，是把一个既有分叉去掉。

**survey 证据**（`index.publicRepos` 为空，无其它公开文档源）：

- 需求档：`docs/requirements/thincoder-adapter.md` F13。
- 设计档：`docs/design/thincoder-adapter.md` §17.1 / §17.5–§17.7 · `docs/design/structure-splits.md` · `docs/design/fork-deltas.md`。
- 代码：`lib/chat/composer/composer_toolbar.dart` · `lib/chat/composer/composer_picker.dart` · `lib/kernel/thincoder/thincoder_choices.dart`。
- 测试：`test/composer_test.dart` T61 · `test/RTM.md`。

**改动三处（产品面）**：

1. `composer_toolbar.dart:58-59`：左簇条件 `permission != null && permission.options.length != 2` ⇒ `permission != null`。0 项时 `ChatSession.permissions` 本就为 null（旧 CLI 无 `autoApprove`）⇒ 不出版面，逐字今天；1 档今天已走菜单，不变。
2. `composer_toolbar.dart:90-100`：删右端的 `ComposerPermissionSwitch` 分支（连同其 `SizedBox(width: 2)`）。
3. `composer_toolbar.dart:135-189`：删 `ComposerPermissionSwitch` 整类。

**形态（全部沿用既有 picker 的内建行为，不新增参数）**

| 面 | 取值 |
|---|---|
| 药丸位置 | 左簇 `PickersRow` 内，模式 picker 之后、模型 picker 之前（Claude 的审批 pill 今天就在这里） |
| 药丸文案 | 选中项的 `label`（`Ask` / `Auto`）+ 其 `icon`（`thincoder_choices.dart:23-36`）；不传 `label:` ⇒ 走内建「取选中项文案」 |
| 菜单头 | `l10n.composerApprovalTitle(kernel.label)`（今天两档 / 五档共用同一句） |
| 菜单几何 | `menuWidth: 290`、`describes` 缺省 true（每行 label + 描述）、行高 40 —— 一个面一套几何，不为两档单独窄化 |
| 交互 | 按下即开、可拖到选项松手选中、↑↓ / Enter / Esc 驱动、点外面关闭（全部内建） |
| 选中 | `onSelected: permission.onSelected` 不变 ⇒ `KernelChoice.select(id)` ⇒ `_configOf(kernel, 'autoApprove', id == 'auto')`（`thincoder_choices.dart:43`）；显示只认回报 |
| 颜色 | `auto` 项的 `caution: true` 由 picker 内建的 `AppColors.caution` 取色；本批不改 |

**死常量**：`AppColors.autoTrack`（`lib/theme/app_theme.dart:169`）唯一消费者就是被删的开关。本轮全仓实读只有两处引用（`app_theme.dart:169` 与 `composer_toolbar.dart:168`）⇒ 一并删除，不留无用常量。

### D · 受影响文件清单

| 文件 | 改动 |
|---|---|
| `lib/chat/composer/composer_toolbar.dart` | 删类 `ComposerPermissionSwitch` + 右端放置分支；左簇条件去 `!= 2` |
| `lib/theme/app_theme.dart` | 删常量 `autoTrack` |
| `test/composer_test.dart` | 改写 T61（`:512-596`）为下拉框形态 |
| `lib/kernel/thincoder/thincoder_choices.dart` | **仅注释**：文件头「the approval switch」与 `_permissionOf` 的「/// The approval switch the agent reports (F13)」沿用旧名——数据面的概念仍是终端 `/auto` 那一位（boolean），不是界面形态；本批不动 |
| `docs/design/thincoder-adapter.md` | 设计档就地改写（§B）；`docs/design/structure-splits.md` 与 `docs/design/fork-deltas.md` 本轮实读为零改动 |

**档位结论（行数 = 本轮 `wc -l` 实读）**：

- **跨档一档**：`test/composer_test.dart` 2416 行，在 >800 硬顶之上。本批只改写 T61 一条用例、不动结构。
- **该档的缝方案与触发已登记**：按面分组（工具条 / 历史编辑 / 布局）；触发 = 下一次结构级触碰或独立拆分批立项（`docs/design/thincoder-adapter.md` §17.4 体量行，本批沿用不重登记）。
- **不跨档两档**：`composer_toolbar.dart` 190 行 · `app_theme.dart` 387 行，均在 500 行内；本批一减一删，不触档位。
- **本批零改动**：`composer.dart` 现 763 行（拆分已落、<800）。

### E · 验收对照（回指 §A 条目 1）

| # | 判据 | 机检 |
|---|---|---|
| A1 | 开关形态全仓消失 | `grep -rn "ComposerPermissionSwitch" lib test` 0 命中 |
| A2 | 两档（thincoder mock `autoApprove: false`）：左簇出审批 pill、读 `Ask`；同处无开关；按下开菜单见 `Ask` + `Auto` 两行及描述；选 `Auto` ⇒ 写出 `session/set_config_option {sessionId:'1', configId:'autoApprove', value:true}`；mock 回报 true 后 pill 读 `Auto` | T61（改写后） |
| A3 | 五档（Claude）逐字今天：pill 读 `Ask for approval`，无开关 | T61 后半 |
| A4 | 死常量清零 | `grep -rn "autoTrack" lib test` 0 命中 |
| A5 | 静态检查干净 | `flutter analyze --no-pub lib/chat lib/theme` |

**验收命令（改动面单测，非全量套件）**：`flutter test --no-pub test/composer_test.dart`

### F · 用例表（T61 改写后的场景）

| 场景 | 输入 | 期望 |
|---|---|---|
| 正常 · 切到 Auto | 两档 mock，按下 pill，点 `Auto` | 写 `autoApprove: true`；回报后 pill 文案 `Auto`、图标 `fast_forward_rounded`；菜单已关 |
| 正常 · 切回 Ask | 接上一步，开菜单点 `Ask` | 写 `autoApprove: false`；回报后 pill 文案 `Ask` |
| 边界 · 0 档 | 旧 CLI（mock `autoApprove: null`） | `permissions == null` ⇒ 左簇无 pill、右端无开关（一个控件都不出） |
| 边界 · 五档 | Claude mock（5 档） | pill 读 `Ask for approval`；菜单 5 行；无开关 |
| 错误 · 写失败 | 两档 mock `configError: true` | pill 保持服务端回报值（不乐观切换）、零异常、连接与回合不受影响（内核既有失败面，本批不新造） |

### G · UI / 交互决策（全部已定，无 `open`）

药丸位置、文案、菜单头、几何、交互、颜色见 §C 表；三问答复见 §C 首段。没有「讨论过但没写下来」的项。

### H · 边界（本批不做）

- 不为两档做窄菜单、不为两档换文案、不加「Auto 开着」的额外徽标。
- 不改 `ComposerPicker` 本体（一个参数都不加）。
- 不动设置页与审批弹窗；不动内核与选项语义。
- 不清理 `docs/design/thincoder-adapter.md` §17.4 其余增量行（本批只改 ㉗ 一行，见 §B；整表整理属另一轮的整理面）。

### I · 集成测试（RTM）增量

从 `test/RTM.md` 出发（现行 9 / 50–100；本轮实读该档 `审批|approval|permission` 零命中）：

- **改写的行**：无（没有既有行断言审批控件的业务结果）。
- **多余的行**：无。
- **缺失的行**：本批不加。判据两条：
  - 本批不改任何业务可观察结果——「开 auto ⇒ 不再逐次弹审批」由内核既有路径承载；本批只改**选它的手**（开关 → 下拉框）。
  - 起点是一次控件换形，不是新的业务场景，也不是新的生产问题。

### J · 关键决策记录（含被否）

| 决策 | 理由 / 被否方案 |
|---|---|
| 复用既有 `ComposerPicker`，不新写下拉 | 三问答复 = `existing`（§C）。被否：新写一个两档下拉 = 同一形态两套实现，主题 / 键盘 / 无障碍三面各要重做一遍 |
| 删 `ComposerPermissionSwitch` 整类 | 形态只剩一种，留类 = 死代码 + 两套形态并存。被否：保留类只在两档时用——那正是本批要消掉的分叉 |
| 去掉按档数分叉的判据 | 判据（`options.length != 2`）随开关消失而失去对象。被否：留着等「以后可能再要开关」= 为没出现的场景留路径 |
| 两档 pill 与五档同一几何（`menuWidth: 290`） | 一个面一套几何。被否：按档数算宽——无证据，且给两档造一条只走一次的布局分支 |
| 删 `AppColors.autoTrack` | 唯一消费者被删（本轮全仓实读两处）。被否：留着「以后可能再用」= 死常量 |
| 菜单头沿用 `composerApprovalTitle` | 两档 / 五档同一问句，不新造 l10n 键（本机无 `flutter gen-l10n`） |

### K · 上抛项

**[上抛·知会] N1**

- F13 的端到端验收（「桌面开 auto ⇒ 工具调用不再逐次弹审批」）在 `test/RTM.md` 没有对应行，今天只有 widget 级 T61 覆盖。
- 这不是本批造成的（批 6 落地时就如此），本席不擅自给集成套件加行；是否立项由主 agent 判断。

## §3 设计评审（评审子代理）
**状态行**：评审通过



### 轮次 1（评审子代理）

评审对象：`docs/batches/2026-11-15-approval-dropdown.md` §2 · `docs/design/thincoder-adapter.md` §17.1 / §17.6 / §17.7（连带核 §17 头部、§17.4 ㉗㉘、§17.9）。

已核实、认定可行的项（无问题）：

- 三处改动坐标与盘上代码一致：左簇 `if (permission != null && permission.options.length != 2)`、右端 `ComposerPermissionSwitch` 分支 + 其 `SizedBox(width: 2)`、整类住 `lib/chat/composer/composer_toolbar.dart`。
- `autoTrack` 全仓实读恰两处：`lib/theme/app_theme.dart` 的定义与开关内的唯一使用。
- `ComposerPicker` 的内建行为支持本批形态断言：`_buildPill` 取 `widget.label ?? widget.selected.label`，并按 `widget.selected.caution` 取 `AppColors.caution`。
- 同一内建行为另两项也对：`describes` 缺省真时 `_rowHeight` 为 40；`menuWidth` 可传。
- 0 档不出版面有据：`ChatSession._choice` 在 `options.isEmpty` 时返 null。
- `test/RTM.md` 现行「9 / 50–100」，且 `审批|approval|permission` 零命中 ⇒ §I 的读档与「不加行」判据成立。

| # | Category | Severity | Issue | Suggestion |
|---|---|---|---|---|
| 1 | Document ownership / Clarity | 🔴 | §17.1 同一机制两种写法并存，就地改写只加不减。新块「形态与放置（用户 2026-11-15 定形：下拉框）」说药丸读 label 与 icon，且按 caution 取色。同节旧句仍在：「`label` / `icon` 留在数据面，开关面不渲染——见下「无文字 label」」「本面不取色，见下「颜色」」——两条指路在 ③ 里已无对象。同节 ③ 标题仍写「宿主 1 档 = composer 的右下角开关」。一句话仍写「桌面用 composer 右下角的小开关显示它、切换它」。偏离 1 更写「右下角紧凑开关，不是左簇菜单 pill，§17.1-③」，与 ③ 正相反。另有两份逐字重复的「**写失败面**」段落。§17 头部「宿主 1 档——composer 右下角的小开关，§17.4 ㉗」指向 §17.4 ㉗ 的「`ComposerPermissionSwitch`（右下角拨动开关：胶囊 track 35×20」。药丸渲不渲 icon / caution 色、放右端还是左簇，两说不能同时成立；§17.7 的 T61 断言的是渲染。 | 把 §17.1 的就地改写做完整。删掉被否形态的每一句：③ 标题、label/icon 那句、caution 表行、一句话、偏离 1。同删重复的「写失败面」，只留「药丸 + 菜单」一套描述。§2 §B 的改写清单补上 §17 头部与 §17.1 的一句话 / 偏离 1 两处；否则计划本身覆盖不到这些残留。 |
| 2 | Acceptance criteria | 🔴 | 验收与走查行仍按被删的控件写，改后无法照做。§17.4 ㉘ 写「T61（两档 ⇒ 开关 / 五档 ⇒ 菜单 / 点开关 ⇒ 第二项）」。§17.7 的 T61 已改成「① 左簇审批 pill 读 `Ask`（选中项文案），右端无开关」。§17.6 仍写「§17.1-①②③（服务端短路 + 桌面开关）」，另有「写失败 ⇒ 批准成立、开关不变」，F13 的判据还指向走查。§17.9-③ 的操作是「点开关打开（**knob 到右、track 橙**）」。步 2 要求看到「右下角（发送钮左侧、上下文环左边）出现拨动开关，**knob 在右、track 橙**」。§2 的三处改动落地后，这几步无对象可看。 | 把 §17.4 ㉘、§17.6 两行、§17.9 步 2 / 3 / 9 一并改成药丸形态：按 pill 开菜单、选 `Auto`、读 pill 文案 / 图标 / 色。§2 §D 的改写面列上 §17.9，使「验收可执行」与 §17.7 的 T61 一致。 |
| 3 | Affected-file tier check | 🟡 | §2 §D 的结论句「档位结论：无文件跨档」与实测不符。`test/composer_test.dart` 本轮实测 2416 行，越 >800 硬顶，也在 >500 层之上。另两档实测均在 500 行内：`lib/chat/composer/composer_toolbar.dart` 190 行、`lib/theme/app_theme.dart` 387 行。`lib/chat/composer/composer.dart` 现 763 行，composer 的拆分已落，不构成本批新增跨档。同一结论句的后半「`test/composer_test.dart` 行级改写，不动结构」属实。 | 结论句改成如实。点名 `test/composer_test.dart` 在 >800 名单之上。带上已登记的缝方案与触发：§17 体量行已写「composer_test.dart = 按面分组（工具条 / 历史编辑 / 布局）」「触发 = 下一次结构级触碰或独立拆分批立项」。写明本批只改一条用例、不动结构。 |
| 4 | Requirements / doc-state | 🟡 | 需求档 F13 的形态句与设计相反，本批不改。§K 已登记为「[上抛·待裁] R1」。批档引其原文「形态 = **composer 右下角的两档小开关**」，同句的文件坐标也已过期。按设计层压需求层（D > F）的既有裁定，记作协调项。 | 设计侧无需再改。由 R1 的裁定决定是否把需求档的形态句与坐标一并改写。 |
| 5 | Clarity（源码注释） | 🔵 | 数据面还在用旧形态的名字。`lib/kernel/thincoder/thincoder_choices.dart` 头部写「the approval switch, the model, and how much it thinks (F13 / F14)」。`_permissionOf` 的注释写「/// The approval switch the agent reports (F13): the terminal's `/auto`.」。该档不在 §2 §D 的受影响清单里。 | 在 §2 §D 加一行「仅注释」的登记，或明写这两处注释沿用旧名是本批的取舍。 |
| 6 | Clarity（三问坐标） | 🔵 | §2 §C 的三问答复把 `ComposerPicker` 的 where-it-lives 写成「lib/chat/composer/composer_toolbar.dart:58-74 · name: "ComposerPicker"」。但那一段是审批 picker 的使用点。类本身住 `lib/chat/composer/composer_picker.dart`（「class ComposerPicker extends StatefulWidget」）。name 与 consumers 都对。 | where-it-lives 改指 `lib/chat/composer/composer_picker.dart`。使用点保留为消费坐标。 |

方法论限制（明记）：本轮无 AGENTS.md、无项目标准档、无 document map。文档归属只能按「同文档内一致 + 批档自述的落点」判。

计数：🔴 2 · 🟡 2 · 🔵 2。

VERDICT: changes-required

### 轮次 2（评审子代理）

轮 2 评审对象：只核轮 1 的 6 条落地与修轮引入的新问题。

范围 = `docs/batches/2026-11-15-approval-dropdown.md` §2 · `docs/design/thincoder-adapter.md` §17.1 / §17.4 / §17.6 / §17.7 / §17.9。

已核实修复（引本轮读到的文本）：

- 轮 1 第 1 条的 §17.1 侧全部落地。§17 头部写「宿主 1 档——composer 左簇的审批药丸 + 菜单，§17.1-③」。
- 一句话写「桌面用 composer 左簇的审批药丸显示它、用它的菜单切换它」。偏离 1 写「用户 2026-11-15 定形：左簇审批药丸 + 菜单」。
- ③ 标题写「宿主 1 档 = composer 左簇的审批药丸」。数据面句写「渲染见下「形态与放置」」。表行写「药丸按它取警示色，见下「态」」。
- 两条悬空指路已消；重复的「写失败面」只剩数据面那一份。
- 轮 1 第 2 条落地。§17.4 ㉘ 写「按药丸开菜单选 `Auto`」。§17.6 写「服务端短路 + 桌面审批药丸」与「写失败 ⇒ 批准成立、药丸不变」。
- §17.9 步 2 写「左簇（模式药丸之后、模型药丸之前）出现审批药丸」。步 3 写「按审批药丸开菜单、选 `Auto`」。步 9 写「药丸随即转 `Auto`（警示色）」。
- 轮 1 第 3 条落地。§2 §D 写「**跨档一档**：`test/composer_test.dart` 2416 行，在 >800 硬顶之上」，缝方案与触发同段登记。
- 轮 1 第 5 条落地。§2 §D 增「仅注释」行，写明两处注释沿用旧名。
- 轮 1 第 6 条落地。§2 §C 写「where-it-lives = `lib/chat/composer/composer_picker.dart`」。

未闭合（🔴 1 条）：轮 1 第 1 条的另一半在 §17.4 未动。

- ㉗ 仍写「`ComposerPermissionSwitch`（右下角拨动开关：胶囊 track 35×20」。
- 同节正文仍写「用户 21:25 定的形只落在这一处」。
- 同节体量句仍写「本批只加这一个控件（`ComposerPermissionSwitch` + 放置分支）」。
- 同表 ㉘ 已被本批改成药丸。两行同表同日签，一说开关、一说药丸。
- §17.5 D41 已写「被否：右下角拨动开关」，㉗ 仍把该形态当交付物。
- §2 §H 的「不清理 §17.4 的历史增量表」不覆盖此处。表内 ㉘ 已被本批更新，㉗ 点名的正是被删的类。

新引入（🔵 1 条）：§17.9 步 8 仍写「开关 + 发一条」。§2 §B 的改写清单列了步 2 / 3 / 7 / 9，漏了步 8。

| # | Orig# | File | Severity | Status | Notes |
|---|---|---|---|---|---|
| 1 | 1 | docs/design/thincoder-adapter.md | 🔴 | Unfixed | §17.1 侧已全部核实改净。§17.4 ㉗ + 正文句 + 体量句仍把右下角开关写成宿主改动面与用户定形。同表 ㉘ 已是药丸。 |
| 2 | 2 | docs/design/thincoder-adapter.md | 🔴 | Fixed | ㉘ / §17.6 两行 / §17.9 步 2 / 3 / 9 全改药丸形态。 |
| 3 | 3 | docs/batches/2026-11-15-approval-dropdown.md | 🟡 | Fixed | 档位结论点名 `test/composer_test.dart` 2416 行，并登记缝方案与触发。 |
| 4 | 4 | docs/batches/2026-11-15-approval-dropdown.md | 🟡 | Accepted | 已在需求档源头改（§1 记录）。需求档本轮不在评审范围，未复读。§K 的 R1 已撤。 |
| 5 | 5 | docs/batches/2026-11-15-approval-dropdown.md | 🔵 | Fixed | §D 增「仅注释」行。 |
| 6 | 6 | docs/batches/2026-11-15-approval-dropdown.md | 🔵 | Fixed | 三问改指 `composer_picker.dart`。 |
| 7 | (new) | docs/design/thincoder-adapter.md | 🔵 | New | §17.9 步 8 仍写「开关 + 发一条」，改写清单漏该步。 |

计数：剩余 🔴 1 · 🔵 1；已闭合 5 条（Fixed 4 · Accepted 1）。

VERDICT: changes-required

### 轮次 3（评审子代理）

轮 3 评审对象：只核轮 2 的 1🔴 + 1🔵 是否落地，不扩面。

范围 = `docs/design/thincoder-adapter.md` §17.4 ㉗与正文句 · §17.9 步 8 · `docs/batches/2026-11-15-approval-dropdown.md` §2。

已核实修复（引本轮读到的文本）：

- 轮 2 第 1 条 🔴 已闭合。§17.4 顶部新增一行指针：「本表是批 6 的交付账。审批控件的现状以 §17.1-③ 为准：右下角拨动开关已由批 24 删除」。
- ㉗ 现写「批 6 加的右下角拨动开关，**批 24 已删**」，并写明「审批面现为左簇审批药丸（§17.1-③），两档与多档同一条路径」。
- 正文句现写「那是用户 2026-10-16 21:25 定的形。用户 2026-11-15 重定形 = 左簇审批药丸 + 菜单」，落点改成「宿主改动面 = `lib/chat/composer/composer_toolbar.dart` 一处构件删除」。
- 体量句现写「批 6 只加这一个控件（`ComposerPermissionSwitch` + 放置分支）」，已带日期；另起一条「体量现态」，缝候选已去掉本开关。
- §2 §B 的连带清单补了「§17.4 ㉗ 的开关行」与「§17.9 步 2 / 3 / 7 / 8 / 9」；§H 收窄成「本批只改 ㉗ 一行」。
- 轮 2 第 7 条 🔵 已闭合。§17.9 步 8 现写「**重启**：按药丸选 `Auto` 后发一条」。
- 无回归：㉘ 仍写「按药丸开菜单选 `Auto`」；§17.6 仍写「桌面审批药丸」与「写失败 ⇒ 批准成立、药丸不变」；§17.9 步 2 / 3 / 9 仍是药丸形态。

| # | Orig# | File | Severity | Status | Notes |
|---|---|---|---|---|---|
| 1 | 1 | docs/design/thincoder-adapter.md | 🔴 | Fixed | §17.4 ㉗ / 正文句 / 体量句都改成「批 6 交付、批 24 删除」的历史陈述，现状指 §17.1-③。 |
| 2 | 2 | docs/design/thincoder-adapter.md | 🔴 | Fixed | ㉘ / §17.6 / §17.9 步 2 / 3 / 9 本轮复读仍是药丸形态，无回归。 |
| 3 | 3 | docs/batches/2026-11-15-approval-dropdown.md | 🟡 | Fixed | 档位结论仍是 `test/composer_test.dart` 2416 行 + 缝方案与触发。 |
| 4 | 4 | docs/batches/2026-11-15-approval-dropdown.md | 🟡 | Accepted | 需求档源头改（§1 记录）；该档不在评审范围，未复读。 |
| 5 | 5 | docs/batches/2026-11-15-approval-dropdown.md | 🔵 | Fixed | §D「仅注释」行仍在。 |
| 6 | 6 | docs/batches/2026-11-15-approval-dropdown.md | 🔵 | Fixed | 三问仍指 `composer_picker.dart`。 |
| 7 | 7 | docs/design/thincoder-adapter.md | 🔵 | Fixed | §17.9 步 8 已改成「按药丸选 `Auto` 后发一条」。 |

计数：剩余 🔴 0 · 🟡 0 · 🔵 0；闭合 7 条（Fixed 6 · Accepted 1）。

VERDICT: pass

## §4 用户批准（主 agent）

### 用户批准

- 2026-11-15 21:26 · 用户原话：**「发」**——依本席上一条的约定（「你说『发』，我立刻点评审轮 3；通过后不再问你，直接派实施」），该字同时构成本批实施的批准。
- **批准范围**：三处代码改动——删 `ComposerPermissionSwitch` 整类 · 左簇 pill 条件从「档数 ≠ 2」放开成「有审批面就出 pill」· T61 改写并改标题。不动内核契约、不动其它 picker、不加新参数。
- **可见结果**：输入框左簇的审批控件由右下角开关变成与 Claude Code 一致的下拉框；两档与多档同一条路径，代码净减少。

## §5 实施记录（eng-coder）

### 实施摘要

三处代码改动全部落地（批档 §2 §C）：

1. `lib/chat/composer/composer_toolbar.dart`：左簇条件 `permission != null && permission.options.length != 2` ⇒ `permission != null`。
2. 同档：右端 `ComposerPermissionSwitch` 分支（连同其 `SizedBox(width: 2)`）删除。
3. 同档：`ComposerPermissionSwitch` 整类删除（`class ComposerPermissionSwitch extends StatelessWidget` 起到底）。

另两档：

- `lib/theme/app_theme.dart`：删 `AppColors.autoTrack`（唯一消费者就是被删的开关；全仓 grep 已零命中）。
- `test/composer_test.dart`：T61 改写，标题逐字 `two approvals and five are one menu (T61)`；依据 `docs/design/thincoder-adapter.md`「two approvals and five are one menu (T61)」。

### 形态与数据面（逐条对设计档）

- 复用既有 `ComposerPicker`，零新组件、零新参数：位置在模式 picker 之后、模型 picker 之前；`menuWidth: 290`；`title: l10n.composerApprovalTitle(session.kernel.label)`；不传 `label:`（药丸取选中项文案 + 其 icon）；`onSelected: permission.onSelected` 不变。
- 0 档不出版面有据：`ChatSession._choice` 在空表时返 null（`lib/chat/chat_session.dart` 的 `if (options.isEmpty) return null;`），故左簇条件只需 `permission != null`。
- 两档与五档同一条路径：Claude 的审批药丸本就走这段，本批只是把两档并进来。

### 决定与披露

- **测试档顺带一处 import 替换**：`workbench_theme.dart` 在改写后唯一用点（`themeColors['button.foreground']`）消失，换成 `pickers_row.dart`（新断言用 `PickersRow` 定位左簇）。同档、原因单一，已在本报告披露。
- **批档 §F 行 5 的「连接与回合不受影响」未在 T61 断言**：那是内核既有失败面，设计档把它挂在 T59（内核级用例）；T61 只核「pill 保持回报值 + 零异常」两条，不新造回合路径。
- **`thincoder_choices.dart` 两处「switch」注释不动**：按 §2 §D 的「仅注释」登记，数据面概念仍是终端 `/auto` 那一位（boolean），不是界面形态。

### 验证读数（本轮实跑）

- `flutter analyze --no-pub lib/chat lib/theme` ⇒ `No issues found!`
- `flutter test --no-pub test/composer_test.dart --name "T61"` ⇒ 1 passed。
- `flutter test --no-pub test/composer_test.dart` ⇒ 58 条里 57 passed / 1 failed。
- 失败项 = `an edit stays open while another conversation is visited from the sidebar`：semantics-tree 检查抛 4 次（`Node N is not in the tree…`），非断言失败。**本轮实测为既有失败**：把本批三档回退到 HEAD 后单跑同一条，失败形态逐字相同；上游同步批 §5 也登记过同一行。
- `grep -rn "ComposerPermissionSwitch\|autoTrack" lib test` ⇒ 零命中（A1 / A4）。
- 行数：`composer_toolbar.dart` 190 ⇒ 120（`wc -l`）· `app_theme.dart` 383 · `composer_test.dart` 2416 ⇒ 2484。本批对该测试档的 diff = +124 / −55（`git diff --stat`）。

### 审计与评审

- **内部对齐审计**（只读 explore）1 轮：`AUDIT VERDICT: clean`。1 条 🔵 已修：§F 行 1 的「菜单已关」缺直接断言 ⇒ 补 `expect(find.text('Ask before each tool call'), findsNothing);`。
- **内部代码评审**（advisor，code）1 轮：0 🔴 / 1 🟡 / 2 🔵，`VERDICT: pass`。处置：
  - 🟡「`fork-deltas` 净增预算」：T61 由 85 行写到 154 行，而 `docs/design/fork-deltas.md` 该档登记的是「净增 ≤99 行（实测 +95 / −2，净增 93）」——本批的 +69 未计入，读数随之逼近/越顶。设计档不在本席笔下 ⇒ 转父代理派设计席重测并重新基线（或裁定收短用例，但 §F 列了五个场景，收短要先改任务书）。本席未改任何设计档。
  - 🔵「§F 行 5 的回合面」：见上「决定与披露」，不改。
  - 🔵「§5 为空」：即本段。
- **终态**：clean（0 🔴；🟡 作为设计档漂移上报，属设计席的笔）。

### 集成测试

- 本批零 RTM 增量（§2 §I 的判据成立：只换「选它的手」，不改业务可观察结果）。
- RTM 现 9 / 50–100。**不是集成测试验证过**——集成跑只在父侧收口发生。

## §6 验证与收口（父代理）

### 验证与收口

**父侧实跑（本席执行，2026-11-15 21:40）**：`flutter test test/composer_test.dart` ⇒ **58 passed / 1 failed**。

- 失败项 = `an edit stays open while another conversation is visited from the sidebar`（semantics-tree）。**既有失败，非本批引入**：已收口的批 `docs/batches/2026-11-15-upstream-sync-6.md` §5 就登记过同一行；coder 另用「三档回退 HEAD 后单跑」复现了同一形态。
- T61 单跑 ⇒ 1 passed；`grep -rn "ComposerPermissionSwitch\|autoTrack" lib test` ⇒ **零命中**。

**改动面与净效果**：

| 文件 | 变化 |
|---|---|
| `lib/chat/composer/composer_toolbar.dart` | 190 → **120 行**（删类 + 删右端分支 + 条件放开） |
| `lib/theme/app_theme.dart` | 删死常量 `AppColors.autoTrack` |
| `test/composer_test.dart` | T61 改写（85 → 154 行），标题逐字 `two approvals and five are one menu (T61)` |

**验收对照**：A1 形态全仓消失（grep 零命中）· A2 两档 = pill 读 `Ask`、菜单两行、选 `Auto` 写 `autoApprove: true` · A3 五档同一个 pill 读 `Ask for approval`、菜单五行 · A4 死常量清零 · A5 静态检查干净（`lib/chat` / `lib/theme` 零 issue）。

**集成窗**：本批零 RTM 增量，`test/RTM.md` 仍 **9 / 50–100**。**未经集成测试验证**——父侧收口这一次跑的就是唯一一次集成面之外的验证。

**未决项（已落台账）**：fork-deltas 的 `test/composer_test.dart` 行预算写「净增 ≤99 行」，本轮五个场景写完实际约 +162，越了该格写的上限。属设计档读数过期（任务书点名的五个场景没法收短），不是代码缺陷。

**暂缓批复核**：无。
