# 2026-10-20 · thincoder：@ 文件补全 + 模式切换失败的可见提示
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 23:43「好，把前两个做了吧」——① thincoder `@` 文件补全 ② #12 plan 静默拒绝补提示。
> 台账 = #12（模式提示）· #120（@ 补全）（thincoder-adapter · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-21
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**条目**：#120 thincoder 未实现 `SuggestsFiles`（`@` 菜单无建议）+ #12 模式切换失败只有日志、无可见提示。

**披露（轻渠道 · 细节面 + 缺陷修）**：本笔 = 轻渠道（`@` 菜单机制已备 = 细节面；模式静默拒绝 = 缺陷修）｜改动：① `ThincoderKernel` 实现 `SuggestsFiles`，新增 `lib/kernel/thincoder/thincoder_suggestions.dart`（本地列目录 + 2s 缓存 + 子序列匹配 + 排序；跳过 `.git`/`node_modules`/`build` 等与 dot 目录）② `_setModeOf` 失败时 `emit` 一条 `NoticeItem(error)`（与模型切换失败同形，`thincoder_choices.dart:111` 先例）｜触达：composer `@` 菜单（thincoder 会话）、模式选择失败路径｜回滚 = 还原两档 + 删新档。

**设计依据**：`chat_session.dart:545-551` 的能力门（`_kernel is SuggestsFiles` ⇒ 有权；否则菜单无建议）；`FileSuggestion` 约定（`kernel_types.dart:94`：相对项目、目录带尾 `/`）；Claude 侧先例 = 向 SDK 要（`claude_code_kernel.dart:1377`），thincoder 内核与项目同机 ⇒ 自己列。

**读数**：`test/kernel/thincoder_suggestions_test.dart` **6/6 绿**（相对路径/目录尾斜杠、名字与路径两种匹配、跳过项、缓存窗口、非目录、无匹配）；`test/kernel/thincoder_kernel_test.dart` **141/141 绿**（接口实现未破既有行为）；`test/chat` **540/540 绿**；`analyze`（thincoder 内核面）No issues。

**范围外观察（已入账 #119）**：`test/kernel/thincoder_fixtures_test.dart` 13 红（夹具缺 A1 起的 `turnId`）+ `dart_core_e2e_test` 1 红——stash 两态对照确认与本笔无关。

> 不适用：§2 —— 轻渠道轮（缺陷修 + 细节面），父侧直接执行，无设计段；设计依据见本段「设计依据」行。
> 不适用：§3 —— 轻渠道轮，无独立评审段。
> 不适用：§4 —— 轻渠道轮，批准 = 用户 2026-10-20 23:43「好，把前两个做了吧」（逐笔披露见本段「披露」行）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**验收读数**

| 项 | 命令 | 结果 |
|---|---|---|
| `@` 建议（新档） | `flutter test test/kernel/thincoder_suggestions_test.dart` | **6/6 绿** |
| thincoder 内核非回归 | `flutter test test/kernel/thincoder_kernel_test.dart` | **141/141 绿** |
| 聊天面非回归 | `flutter test test/chat` | **540/540 绿** |
| 静态 | `flutter analyze`（thincoder 内核面 + 新测试） | No issues |

**待用户走查**：重启 dev 实例后在 thincoder 会话输入 `@` 看建议是否出现；在工程模式点 plan 看是否出一条可见提示（原为静默）。

**提交**：`5f9df260`。

**范围外（已入账）**：#119 `thincoder_fixtures_test` 13 红（夹具缺 A1 起携带的 `turnId`）+ `dart_core_e2e_test` 1 红，两态对照确认与本笔无关。

**用户真机走查（2026-10-21 00:25–01:00）**

- `@` 菜单：thincoder 会话输入 `@` 出文件列表；`@comp` 有结果（宿主索引满 50 条，`C:\Users\\xinbo\repos` 下 comp*.json 为真实文件）⇒ **#120 的增量成立**（内核侧清单并入；菜单本身原本就有宿主索引来源，表述已在 #120 更正）。
- 模式提示：工程模式点 plan 收到可见提示 `The mode was not switched to plan: JSON-RPC -32602: plan mode is disabled in engineering mode — …` ⇒ **#12 修复成立**（原为静默）。
- 附带核销：`#121` 回退真机验证通过（同轮走查）。
- 结论：两笔 `在途 → 待核销 → 已核销`，本批收口。
