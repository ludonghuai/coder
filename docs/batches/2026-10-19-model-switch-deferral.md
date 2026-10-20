# 2026-10-19 · 模型切换后置应用（回合在飞时不丢切换请求）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 03:22「不行，非视觉模型还是做不了这个图片识别这个活，显示not support」+ 03:25「切模型是怎么啦？」。
> 台账 = #94（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
**本批条目**：① 回合在飞时切模型（`session/set_config_option(model)`）被 CLI 的 FIFO 队列排到回合之后，60s 超时后请求被丢、模型未切；② 改为「后置应用」：回合在飞时记下目标模型，回合结束后自动重发，并在 UI 给一句可见状态；③ 切换失败/被丢弃时不得假装成功（显示仍是旧模型）。

**实测事实（2026-10-19）**：`events.log` 03:09:38 `set_config_option(model) failed: -32603: got no answer`；03:09:39.789 迟到答案 `id c6`（超时 60s，`thincoder_protocol.dart:61`）；CLI 侧根因 `thincoder/thincoder-cli/src/acp/transport.mjs:31-40`——豁免表只有 `session/cancel` / `session/close` / `session/list` + `autoApprove`，注释明写 model 一律排队。

**关键判据**：正在跑的回合用旧模型跑完（快照不变）；目标模型在回合结束后生效；用户可见「已排队 / 已生效 / 失败」；不得为修此项改 B1 口径（可选：CLI 豁免名单不动，纯客户端后置）。

**授权口径**：用户 2026-10-19 03:25「切模型是怎么啦？」+ 03:22「不行，非视觉模型还是做不了这个图片识别这个活，显示 not support」（本条是后者的根因）。
## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（实施回填）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

1. 回合在飞时点模型（`session/set_config_option(model)`）被 CLI 的入站 FIFO 排到回合之后，超 60s 被桌面丢弃 ⇒ 模型未确认切换（实测 2026-10-19 03:09，`events.log`；迟到应答证明 CLI 在回合收尾执行了该写）。
2. 改为客户端「后置应用」：回合在飞时只记目标（last-wins），回合收尾自动重发；等待态可见。
3. 失败 / 被丢弃不得假装成功：显示仍是旧模型 + 一条可见错误。

需求档对位 = F5（模型面：切换生效；显示以 thincoder 回报为准，不乐观假报）。需求档尚无本批功能点编号（F21）——上抛主 agent。

### 设计档落点

`docs/design/thincoder-adapter.md` 新节 §24「模型切换后置应用（批 14；F5 具体化）」，接 §23 之后；同拍随改：头部分批行、§5.2 指针、§7（F5 补行）、§9（测试面）、§10（边界）、§11（UI）、§14-28（失败文案英文占位登记）。

**落盘受阻（2026-10-19 03:33 环境事件）**：父侧 pull 前置 stash 了在飞工作（`stash@{0}`），工作树设计档回到 HEAD 版（2216 行、止于 §19；§20–§23 不在盘）；含 §20–§23 的 3140 行版在 stash 里；仓处 merge 中（unmerged `lib/settings/pages/general_page.dart`，分支 26/9 分叉）。设计内容已按 3140 行版写好（§24 全文见本轮设计输出），**未写入 merge 中的工作树**，避免与 stash 恢复相撞。恢复后由父侧重新派发落 §24。

### 机制设计（状态机判据表）

字段：`_modelTarget`（目标 id）· `_modelDeferred`（等待回合）· `_modelSending`（写请求在飞）。

| 态 | 进入 | pill | 动作 |
|---|---|---|---|
| 空闲 | 初始 / 成功 / 失败收束 / `dispose` / `_teardown` | 回报的模型 | — |
| 等待回合 | `_turn != null` 时点模型（再点覆盖；点已生效模型 = 取消等待） | 主 label +「回合结束后切换到 <目标>」 | 不发请求 |
| 发送中 | 空闲点选 ∥ 回合收尾触发 | 主 label（应答到即换） | 写 `set_config_option(model)` |

触发点：`_endTurn` 在暂存自动轮分支之后、`_drain()` 之前（配置行先写、下一趟 prompt 后写 ⇒ 下一回合用新模型）；应答回来时目标已换 ⇒ 再发一次（last-wins）；`_teardown` / `dispose` 清三字段。发送前置判据 = `_turn == null && _pendingAuto == null`；会话不在 ⇒ 清目标不发。

超时 = 连接缺省 60s（不新设常量；正常路径 CLI 队列空闲、handler 同步纯内存 ⇒ 毫秒级应答）。兜底：失败 ⇒ 目标清空 + error notice + 显示保持最后一次回报（从未乐观改过，无可回滚）；CLI 迟到执行时 `config_option_update` 让显示自愈；不自动重试。

CLI 零改：`transport.mjs:31-40` 的 FIFO / 豁免表不动（model 继续排队）。

### 受影响文件与测试覆盖（行数 = 2026-10-19 实测，stash 版工作树快照）

| 档 | 现状 → 预算 |
|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | 1091 → ≤1115（+≤24；§21.3 预算 ≤1148，余量 33） |
| `lib/kernel/thincoder/thincoder_choices.dart` | 203 → ≤263（+≤60；状态机与 pump；`_Choice.always`） |
| `lib/kernel/agent_kernel.dart` | 472 → ≤482（`DefersModelSwitch` 接口） |
| `lib/chat/chat_session.dart` | 1215 → ≤1223（`pendingModel` 投影） |
| `lib/chat/composer/session_model_picker.dart` | 170 → ≤188（label 后缀 / tooltip） |
| `lib/l10n/app_en.arb` · `app_zh.arb` | 7100 / 2725 → +7 / +1（`modelsSwitchPending`） |
| 生成档 3 档 | 各 +3（gen-l10n 或按 §18.8 口径手改） |
| `test/kernel/thincoder_kernel_test.dart` | 3644 → ≤3814（T100–T104） |

零改动：`thincoder_protocol.dart` · `thincoder_events.dart` · `thincoder_mock.dart` · Claude / Codex 内核 · 固件（无新帧）· `thincoder/`（CLI 零改）。
测试：T100 回合在飞点选 ⇒ 收尾重发；T101 last-wins；T102 失败回显 + error；T103 会话离开清等待；T104 两源档键。mock 零改（既有 `hold` / `configError` / `models`）。

### 验收对照

| 条目 | 判据 |
|---|---|
| 回合在飞切模型 ⇒ 回合结束生效 | T100：在飞期间零写；`pendingModel == 目标`；收尾后恰 1 条；`selected == 目标` |
| 二次改选 last-wins | T101：只 1 条，value = 后点目标 |
| 失败不假装成功 | T102：`selected` 仍是旧模型；恰 1 条 error `NoticeItem`；`pendingModel == null`；health ready |
| 会话切换 / 关窗清等待 | T103：`dispose()` 后 `pendingModel == null`；放行后零写 |
| 可见状态 | 走查 2（pill 后缀 + tooltip）；T104（两 arb 键含 `modelsSwitchPending`） |
| 真机 | §24.8：在飞切模型 ⇒ 收尾生效；切到视觉模型后发图能看图（视觉模型可在时；否则回指 F19 既有走查） |

### 关键决策（编号接现有最大 D94）

D95 客户端后置应用、CLI 零改 · D96 触发 = `_endTurn`、`_pendingAuto == null`、`_drain()` 之前 · D97 可见态 = pill 后缀 + tooltip，等待目标不进 `selected` · D98 重发沿用 60s、失败 = error + 保持旧模型、不自动重试 · D99 状态住内核、宿主只读投影。含被否：豁免 `model` / 放大超时 / 乐观显示 / 缩短到 10s / `noTimeout` / 宿主定时器（全文见 §24.4）。

### 上抛项

1. **[上抛·待裁] 环境**：merge 中 + `stash@{0}` 含在飞批次工作；设计档 §24 未落盘。请先完成 merge 并恢复 stash，再派发落 §24（不要在 HEAD 版上落）。
2. **[上抛·待裁] 需求档**：本批无功能点编号（F21）；请主 agent 在需求档落条目，使三链（批档 §2 / 设计 §24.5 / 需求档）对齐。
3. **[上抛·知会] 设计档既存问题（非本批，未动）**：文档末尾有 `## 变更记录` 章节（约 60 行；用户 2026-10-15 裁定设计/需求档不带 changelog）；§16 内有一处重复编号标题 `### 12.7 归属帧标`（应为 §16 系）。建议单独清理轮。

**落盘状态更新（2026-10-19 03:35）**：父侧已恢复 stash（无 `MERGE_HEAD`、HEAD = `6eadd429`）；设计档 §24 已落盘（3140 → 3315 行；§24 起 line 3086；§14-28 与 §5.2 / §7 / §9 / §10 / §11 指针同拍落盘）。上抛项 1 闭合；上抛项 2（需求档 F21）仍待主 agent。落盘后把 §24.3 的 l10n 行数读数刷为恢复后实测（en 7133 / zh 2748；生成档 16563 / 10120 / 9569）。

**读数更正（同上 03:35）**：本节文件表与「受影响文件」表的 arb 行以本更新为准——`app_en.arb` 7133 · `app_zh.arb` 2748（恢复后实测；原写 7100 / 2725 为 stash 版快照）；其余各档读数（1091 / 203 / 472 / 1215 / 170 / 3644）不变。

**实施回填（2026-10-19，#58 实现后；受影响文件表以下块为准）**

| 档 | 现状 → 预算（实交） |
|---|---|
| `lib/kernel/thincoder/thincoder_choices.dart` | 203 → ≤273（实交 273；+70 = 状态机 / pump / `_Choice.always`） |
| `test/kernel/thincoder_kernel_test.dart` | 3644 → ≤3844（T100–T105；find 复测实交 3843） |
| `test/chat/pending_model_test.dart` | 新增 ≈96（T106 宿主投影；<300 新档） |

- 原表 `thincoder_choices.dart` 行（≤263）与 kernel_test 行（≤3814、T100–T104）以本块为准；`agent_kernel.dart` 行原表已有（472 → ≤482，实交 480），不重列。表里其余行不动。
- 未改（本轮指令冻结）：arb / 生成档两行仍为设计期读数（本节「读数更正」记 en 7133 / zh 2748）；实交 = en 7141 / zh 2749 · 生成档 16569 / 10125 / 9574（各 +6）。是否刷新由父侧定。
- 设计档同拍回填（`docs/design/thincoder-adapter.md`）：§24.1 发送前置判据补 `_releaseWanted`（`thincoder_choices.dart:82-83`；视图离开后不补发，与 §24.7-4 同口径）· §24.1 触发点 1 改「`_pendingAuto` 分支之前」（`thincoder_kernel.dart:768`；pump 自带 `_pendingAuto` 守卫，行为等价；`_endTurn` 745-780、`_drain()` :778）· §24.3 ② 行补实交 273 = +70（来源 = 状态机 / pump / `always`）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 批 14 设计评审（§24 + 需求档 F21）

范围：`docs/design/thincoder-adapter.md` §24（design:3086–3253）+ `docs/requirements/thincoder-adapter.md` F21（requirements:144–148）。方法学限制：本会话无 AGENTS.md / 项目标准档 / 文档地图（Document ownership 判据降级，仅按档内互校）。

已核通过项：设计档在场且 §24 结构完整（状态机 / 契约 / 受影响文件 / D95–D99 / 验收对照 / T100–T104 / 边界 / 走查 / UI）；最近先例行（design:3091–3098）与 survey 行（design:3100–3105）均在；受影响文件 8 档全部带现值与 delta，抽查现值相符（kernel 1091/1092、choices 203、agent_kernel 472、chat_session 1215、session_model_picker 170、app_en.arb 7133、app_zh.arb 2748、kernel_test 3644）；实现前提代码实读成立（`_pendingAuto` :115、`_turn` :111、`_endTurn` :724–756、`_Choice` :143–170、`emitInfoChanged` → `KernelInfoChanged` → notifyListeners、mock 的 `models`/`hold`/`configError`/`requests` 齐备、`request()` 同步写出 :110、`_exited` 先 `_teardown` 后 `_endTurn` :914/:923）。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Clarity | 🟡 | §24.1 发送前置判据只写 `_turn == null && _pendingAuto == null`（design:3135），未含 `_modelSending`；状态表另立「发送中」态（design:3127），空闲支无条件走 pump（design:3115）⇒ 发送中再点会与在飞那次同拍发第二条；T101 只覆盖等待态改选（design:3217），机检不到此路 | 前置判据补 `!_modelSending`（发送中只记目标），T101 增一子例：发送中再点另一个 ⇒ 首条应答前零新增写、应答后恰一条、value = 后点 |
| 2 | Requirements / Clarity | 🟡 | 放开 `_Choice` 同值短路（design:3178、design:3139）后，空闲态点当前模型落进空闲支（design:3114–3115）⇒ 发一次同值 `set_config_option`；而 §24.5（派生）判「点它 = 同值取消、零写」（design:3208），机制无该早退、也无对应用例 | `_selectModelOf` 明写同值早退（`id == _events.selected('model')` 且无等待目标 ⇒ 不发不置目标），并给该行补机检（单项清单点它 ⇒ `requests('session/set_config_option')` 为空） |
| 3 | Acceptance | 🟡 | 需求 F21 标「验收（可机检）」，其中「UI 显示「已排队 → 已生效」」（requirements:146）在设计中只落走查 2 + T104 的 ARB 键存在性（design:3207）；宿主投影 `chat_session.dart`（design:3180，+8）与 pill 后缀无断言，T100–T104（design:3214–3220）全在内核层 | 补宿主侧断言（`ChatSession.pendingModel` 等待态非空、收尾后归空，`test/chat/*`）或 pill label 含 `modelsSwitchPending` 文案的控件断言；T104 保持键面哨兵 |
| 4 | Document ownership | 🟡 | l10n 生成档落法两处相抵：§24.3 ⑦「不可跑则按 §18.8 口径手改生成档并保持 `test/l10n_test.dart` 绿」（design:3183，并把 3 个生成档列为受影响面）vs 登记 §14-14 / §14-24 / §14-27「生成档只由 `flutter gen-l10n` 产出、不可手改」+「不可跑 ⇒ 英文占位回落」（design:546、design:556、design:559）。预存在分叉，§24 沿用 §18.8（design:1730 同口径） | 择一：把「不可手改」改写成「无 SDK 时手改并与 ARB 同拍、SDK 就位后重产」（三处登记同改），或 §24.3 ⑦ 改走英文占位并撤回生成档行 |
| 5 | Methodology | 🟡 | 变更记录停在批 12 修正轮 1（design:3313–3315），无批 14 / §24 落盘条目；抬头分批行已列批 14（design:5）、§7 已加 F21 行（design:391），历史面缺这一笔 | 补 2026-10-19 · 批 14 设计（F21）：新增 §24（状态机 / 契约 / 受影响文件 / D95–D99 / T100–T104 / 边界 / 走查 / UI），随改 §5.2 指针 · §7 · §9 · §10 · §11 · §14-28 · 需求档 F21 入档 |
| 6 | State-machine completeness | 🔵 | 清等待退径只列 `dispose()` / `_teardown()`（design:3137、design:3230）；「视图离开 ⇒ `release()` ⇒ 一个 macrotask 后 `_closeSession()` + `_teardown()`」未列：`_canClose`（`thincoder_kernel.dart:508-512`）不计等待目标，`_releaseWhenIdle`（`:518-534`）在收尾后才触发 ⇒ 在飞点选后切走视图，收尾那次写可能随 teardown 丢掉且无 error（应答被 `identical(connection, _connection)` 丢弃） | 把 release 明写进 §24.7-4 清单（或 `_modelDeferred` 时让 `_canClose` 为假），并写明丢弃时用户可见面为零 |
| 7 | Doc state | 🔵 | §5.2 批 14 指针写「本仓适配层 2 档 + 宿主 2 档 + l10n 两源档 / 生成档」（design:311），§24.3 实为 5 档代码 + l10n ⇒ 漏 `agent_kernel.dart`（design:3179） | 指针改「适配层 2 档 + 宿主机 2 档 + `agent_kernel.dart` 接口 1 档 + l10n 两源档 / 生成档」 |
| 8 | Doc state | 🔵 | 同日两处「实测」读数打架：§23.3 记 kernel 1055、arb 7026 / 2703（design:3017、design:3022），§24.3 记 1091 / 7133 / 2748（design:3177、design:3182）；抽查现值与 §24.3 一侧相符 | §23.3 读数与 budget 行按现值刷新，或标「批 11 编制日快照，勿与 §24.3 互校」 |
| 9 | Survey evidence | 🔵 | §24 survey 行只记外仓代码 / 本仓代码 / `events.log` 实测 / ACP schema（design:3100–3104），未记外仓设计档（如 `thincoder/docs/cli/design/ACP-CLIENT.md`）是否查过、有无相关条款；本档 §22.11 的 survey 行有这一半（design:2859） | survey 行补一句外仓档结论（「无相关条款」也要写）或实查到的条款坐标 |

计数：🔴 0 · 🟡 5 · 🔵 4

VERDICT: pass

§3 已写入（本条）。

## §4 用户批准（主 agent）

**用户批准（2026-10-19 03:47）**：逐字「批准」——批 14（F21 模型切换后置应用）设计批准；实现面 = §24.3 的 9 行（5 档代码 + 2 源 arb + 3 生成档 + 2 档测试）。

## §5 实施记录（eng-coder）
**状态行**：实施完成（T100–T106 全绿（124+22=146 passed）；analyze 10 档 clean；审计 clean / 评审 pass；终态 clean）



**交付摘要（2026-10-19）**
- 实现全落：① `agent_kernel.dart` +`DefersModelSwitch`（`pendingModel` getter）；② `thincoder_kernel.dart` 三字段 + `pendingModel` + `_endTurn` 触发 + `_dropModelOf`（`_teardown`/`dispose` 共用）+ `implements DefersModelSwitch`；③ `thincoder_choices.dart` `_Choice.always`（只对 model）+ `_selectModelOf`（同值早退 / 取消等待 / 在飞记目标 / 发送中只记目标 / 空闲发）+ `_pumpModelOf`（前置判据、last-wins、错误面）；④ `chat_session.dart` `pendingModel` 投影；⑤ `session_model_picker.dart` label 后缀 + tooltip（无等待时 tooltip 逐字不变）；⑥ 两源 arb `modelsSwitchPending`（en 带 `@` 元数据/占位声明，zh 只值）；⑦ 三生成档手改（抽象 getter + `_en`/`_zh` 实现，SDK 轮重产）；⑧ kernel test 新增组 `the model picked while a turn runs (F21)`（T100–T105）；⑨ 新增 `test/chat/pending_model_test.dart`（T106 宿主投影 + 负向锁）。CLI / `thincoder_protocol.dart` / `thincoder_events.dart` / `thincoder_mock.dart` 零改动。

**验证读数（本机 SDK `C:\Users\xinbo\repos\flutter\bin\flutter.bat`，`--no-pub`）**
- `flutter test --no-pub test\kernel\thincoder_kernel_test.dart test\chat\pending_model_test.dart` ⇒ **124 passed / 0 failed**（kernel 122 + T106 2；含 T100–T105）。
- `flutter test --no-pub test\l10n_test.dart` ⇒ **22 passed / 0 failed**。
- 三档同跑（kernel_test + pending_model_test + l10n_test）⇒ **146 passed / 0 failed**（最终复跑）。
- `flutter analyze --no-pub` 改动面 10 档 ⇒ **No issues found**。
- 实交行数（`find /c /v` 末读数）：kernel **1115**（≤1115）· choices **273**（设计 §24.3 ≤273；批档 §2 写 ≤263，见「读数更正」）· agent_kernel **480**（≤482）· chat_session **1222**（≤1223）· session_model_picker **182**（≤188）· kernel_test **3844**（≤3859）· pending_model_test **96**（<300）· app_en.arb **7141**（+8）· app_zh.arb **2749**（+1）· 生成档 **16569 / 10125 / 9574**（各 +6）。

**决策透明表（实交偏离 / 设计未列项）**

| # | 项 | 实交 | 理由 / 影响 |
|---|---|---|---|
| 1 | `_pumpModelOf` 前置判据多一条 `_releaseWanted` | `thincoder_choices.dart:82-83` | 设计 §24.1 只列 `_turn == null && _pendingAuto == null && !_modelSending`；T103②（§24.6）要求 `kernel.release()` 后放行回合零写 ⇒ 必须有该门。视图离开后目标随 `_teardown` 清，行为与 §24.7-4「不补发」一致。设计文字漏列，建议设计轮补一句。 |
| 2 | `_dropModelOf()` 住内核（`_teardown` / `dispose` 共用） | `thincoder_kernel.dart:736-741`，调用点 `:465`、`:557` | 两边各清三字段会与 choices 重复且超行预算；语义与设计「各清三字段」一致（多一次 `emitInfoChanged`，宿主即时刷新）。 |
| 3 | `_endTurn` 的 pump 调用点 | `thincoder_kernel.dart:768`（在 `if (_pendingAuto case final pending?) {` 之前） | 父侧本轮指令 =「`_turn = null` 后、`_pendingAuto` 分支前」；与设计 §24.1「分支之后」行为等价（pump 自带 `_pendingAuto != null` 守卫）。写序仍为配置先、下一趟 prompt 后。遗留：两处约束分散，后续改动需同时看。 |
| 4 | l10n 生成档手改 | 3 档各 +6 行（设计估 +3） | 按 §24.3 ⑦ / §18.8 口径（无 SDK 轮同拍手改）；生成档 getter 含 5 行 doc 注释块，故 +6 而非 +3。SDK 就位轮 `flutter gen-l10n` 重产核对。 |
| 5 | `modelsSwitchPending` en 增 8 行（设计估 +7） | `app_en.arb:4950-4957` | `@` 元数据块形同既有键（值 + 6 行占位声明 + 1 行键）⇒ +8；zh +1 如估。 |
| 6 | 失败 notice 固定 id `'error:model'` | `thincoder_choices.dart:110-117` | 重复失败替换同一条 notice（不叠条）；成功不自动删历史错误。设计未要求删除，保留记录。 |
| 7 | 同值早退下放内核 | `thincoder_choices.dart:58` | `_Choice.always` 只放开 model 的「同值不回调」，判据仍在内核（§24.1 第 1 条）；T105 机检零写。 |

**审计与代码评审轮次与终态**
- 内部偏差审计（explore，只读，1 轮）：**clean** —— T100–T106 逐条落到代码（非仅测试）；契约 / l10n / 预算 / 越界面全核；F21 符号全量扫描零清单外命中。审计观察项（无 tooltip 时 `null → ''`）已在交付前修正（见 fix round）。
- 内部代码评审（advisor code，1 轮）：**pass** —— 🔴 0 · 🟡 1（无 must-fix：批档 §2 与设计 §24.3/§24.6 的读数与用例号滞后，收口时刷）· 🔵 4（pump 调用点文字差异 / 取消释放后等待目标残留的极窄态 / deferred+sending 组合态的取消口径 / 记录层回填）。四条均非验收偏差；设计档与需求档非本角色写权，留父侧收口处置。
- 终态：**clean（converged）**。

**fix round（1 轮）**
- 审计观察项：`session_model_picker.dart` 无等待且调用方未给 tooltip 时，`[?tooltip, ...].join(' · ')` 把 `null` 变成 `''`（与 §24.9「非 thincoder / 无等待 ⇒ tooltip 逐字不变」的负向锁字面不符；可见文案不变，仅多一层空 `Semantics`）。修法：`waiting == null ? tooltip : [...]`；改后 182 行、analyze 干净。

**用例归属**
- T100–T105：`test/kernel/thincoder_kernel_test.dart` 新组 `the model picked while a turn runs (F21)`（T100 / T101① / T101② / T102 / T103① / T103② / T104 / T105）；mock 零改。
- T106：`test/chat/pending_model_test.dart`（新档）：假内核 `_DeferringKernel implements AgentKernel, DefersModelSwitch` + 非接口内核负向锁。
- 零改动面：CLI（`thincoder/**`）、`thincoder_protocol.dart`、`thincoder_events.dart`、`thincoder_mock.dart`、Claude / Codex 内核、设计档、需求档。

**未做 / 父侧事项**
- 真机走查 §24.8（在飞切模型 ⇒ 收尾生效；切视觉模型发图）未跑：需真实 thincoder CLI 与会话，按惯例留父侧收口。
- 批档 §2 的 T100–T104 / choices ≤263 / 缺 `agent_kernel.dart` 与 `pending_model_test.dart` 两行 = 设计期快照滞后（设计 §24.3/§24.6 为准）；请父侧在 §6 收口时同步（本角色不改 §2）。
- 集成测试：不新增（本波为内核状态机 + 宿主投影，三档 `flutter test` 已覆盖；集成面零改）。
- `git status --porcelain`：本波只把上述声明文件写入工作树；其余条目为工作树既有他批改动，未触碰。

## §6 验证与收口（父代理）

**验收读数（父侧复跑）**：`flutter test --no-pub test/kernel/thincoder_kernel_test.dart test/chat/pending_model_test.dart test/l10n_test.dart` ⇒ **146 passed / 0 failed**（含 T100–T106）；`flutter analyze --no-pub` 改动面 10 档 No issues；行数 = kernel 1115（≤1115）· choices 273 · agent_kernel 480 · chat_session 1222 · picker 182 · kernel_test 3844 · pending_model_test 96，全在 §24.3 预算内。

**真机（用户 2026-10-19 19:43 确认）**：回合在飞时切模型 ⇒ 回合结束自动生效；切后发图识别正常（配合稳定视觉模型）。

**设计回灌**：#60 已把 `_releaseWanted` 判据、pump 调用点顺序、§2 读数与 §24.3 ② 回填；实测与设计一致（`_modelSending` / 同值早退 / T105 / T106 全在位）。

**台账**：#94（回合在飞切模型 60s 超时）→ 已核销；派生登记 #96（deepseek-flash 视觉不稳）已按用户裁定撤回。

**状态**：已收口 2026-10-19。
