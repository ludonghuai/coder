# 2026-10-20 · 切换内核后新内核未启动（选择器消失）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 03:45 走查报告：新建项目默认 thincoder → 切到 Claude Code → 切回来，mode / 模型等组件消失。
> 台账 = #111（chat-streaming · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-20
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**条目**：#111 切换内核后新内核未启动 ⇒ 握手驱动面的选择器（mode / 模型等）消失。

**根因（代码实读）**：`lib/chat/chat_session.dart:376-380` 的 `attach()` 才调 `_kernel.prepare()`（启动进程 + 握手）；`:413-424` 的 `setKernel` 只 `unawaited(_subscription?.cancel())` + `_kernel.dispose()` + `_connect(descriptor)`，**不调 `prepare()`**——视图一直在（`_views` 仍为 1），不会再来一次 `attach()` ⇒ 新内核保持 idle、无握手 ⇒ thincoder 的 `configOptions` 为空 ⇒ `SelectsMode` / `SelectsModel` 的选项为空 ⇒ 选择器整组不渲染。

**披露（轻渠道 · 缺陷修）**：本笔 = 轻渠道（走查当场指出）｜改动：`chat_session.dart:413-431` 的 `setKernel` 在 `_views > 0` 时补 `_kernel.prepare()` + `_startReview()`（视图未离开，`attach` 不会再来）｜触达：内核切换路径｜回滚 = 删该 `if` 块（可逆）。

**读数**：`flutter analyze lib/chat/chat_session.dart` → No issues；`test/kernel_ui_test.dart` **30/30** 绿。

**收尾**：待重建后由用户复验「thincoder → claude → thincoder」三步后 mode / 模型仍在；通过则走收口链（本档 §2/§3/§5 不适用声明 + §6）。

> 不适用：§2 —— 轻渠道轮（父侧直改），无设计段；修法与读数见本 §1。
> 不适用：§3 —— 无设计评审段；行为由用户走查确认（2026-10-20 20:33「现在就好了」）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

**用户批准（2026-10-20 20:33）**：用户逐字「现在就好了」——切 thincoder → claude → 切回，选择器立即在。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**验收读数（父侧 + 用户走查）**

| 项 | 结果 |
|---|---|
| `flutter analyze`（`chat_session.dart`） | No issues |
| `test/kernel_ui_test.dart` | 30/30 绿 |
| 用户走查（thincoder → Claude → thincoder） | 选择器即时在（20:33「现在就好了」） |

**结算**：`lib/chat/chat_session.dart` 的 `setKernel` 补 `prepare()` + `_startReview()`（视图未离开时）；随后的温启动改进（`fe403e32`）把内核切换从「重启进程」变为「复用已启动实例」。提交 `dcc04d09` + `fe403e32`。
