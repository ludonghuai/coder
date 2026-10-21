# 2026-10-20 · thincoder：@ 文件补全 + 模式切换失败的可见提示
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 23:43「好，把前两个做了吧」——① thincoder `@` 文件补全 ② #12 plan 静默拒绝补提示。
> 台账 = #12（模式提示）· #120（@ 补全）（thincoder-adapter · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**条目**：#120 thincoder 未实现 `SuggestsFiles`（`@` 菜单无建议）+ #12 模式切换失败只有日志、无可见提示。

**披露（轻渠道 · 细节面 + 缺陷修）**：本笔 = 轻渠道（`@` 菜单机制已备 = 细节面；模式静默拒绝 = 缺陷修）｜改动：① `ThincoderKernel` 实现 `SuggestsFiles`，新增 `lib/kernel/thincoder/thincoder_suggestions.dart`（本地列目录 + 2s 缓存 + 子序列匹配 + 排序；跳过 `.git`/`node_modules`/`build` 等与 dot 目录）② `_setModeOf` 失败时 `emit` 一条 `NoticeItem(error)`（与模型切换失败同形，`thincoder_choices.dart:111` 先例）｜触达：composer `@` 菜单（thincoder 会话）、模式选择失败路径｜回滚 = 还原两档 + 删新档。

**设计依据**：`chat_session.dart:545-551` 的能力门（`_kernel is SuggestsFiles` ⇒ 有权；否则菜单无建议）；`FileSuggestion` 约定（`kernel_types.dart:94`：相对项目、目录带尾 `/`）；Claude 侧先例 = 向 SDK 要（`claude_code_kernel.dart:1377`），thincoder 内核与项目同机 ⇒ 自己列。

**读数**：`test/kernel/thincoder_suggestions_test.dart` **6/6 绿**（相对路径/目录尾斜杠、名字与路径两种匹配、跳过项、缓存窗口、非目录、无匹配）；`test/kernel/thincoder_kernel_test.dart` **141/141 绿**（接口实现未破既有行为）；`test/chat` **540/540 绿**；`analyze`（thincoder 内核面）No issues。

**范围外观察（已入账 #119）**：`test/kernel/thincoder_fixtures_test.dart` 13 红（夹具缺 A1 起的 `turnId`）+ `dart_core_e2e_test` 1 红——stash 两态对照确认与本笔无关。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
