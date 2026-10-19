# 2026-10-18 · model-picker-groups
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-18 · 来源 = 用户 2026-10-18 21:00「就按照你说的做，不用显示api地址」。
> 台账 = #70（thincoder-adapter · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-18 · 轻渠道轮）

### 轻渠道披露

**本轮 = 轻渠道**（细节面 · 既有交互）| change = thincoder 模型选择器按供应商分组 + 默认只展开当前组 + 页脚修正 | reach = 仅 thincoder 模型选择器（Claude 分组与页脚不动）| rollback = revertable。

### 来源与形态

- 用户 20:55「模型列表太长，按供应商或 API 地址分类、二级列表」+ 21:00「按你说的做，不用显示 API 地址」。
- 形态（用户确认）：复用既有 `KernelOptionGroup`（`composer_picker.dart` 已支持分组 / 折叠 / 搜索，Claude 模型已用这一套）——thincoder 的模型选项按 `provider:model` 的首个冒号拆供应商，填 `group`；组标题 = 供应商名，模型行 label 去掉 `provider:` 前缀；默认只展开当前模型所在组，搜索（≥10 项自动出现）跨组过滤并展开全部；不做真正二级翻页（`submenuOf` 与 per-model 设置面互斥）。
- **API 地址不显示**（用户 21:00 定）：ACP 模型选项只带 `provider:model`，baseURL 需 CLI 补元数据；另议。

### 改动面（预计）

- `lib/kernel/thincoder/thincoder_events.dart`：`optionsOf` 对 `model` 项按首个冒号拆 provider，填 `group: KernelOptionGroup(provider, provider)`；label 去前缀。
- `lib/chat/composer/composer_picker.dart`：加 `startCollapsed` 开关（默认 false，Claude 行为不变）；true 时只展开当前选中项所在组；搜索仍展开全部。
- `lib/chat/composer/session_model_picker.dart`：thincoder 会话隐藏「管理模型」页脚（#67），Claude 不变。
- 测试：thincoder optionsOf 分组断言 + picker 默认折叠 / 页脚断言。

### 排序

- `lib/kernel/thincoder/thincoder_events.dart` 正被宿主通道 B 轮（eng-coder #4）写入 ⇒ 本轮 pen 等 B 报告落地后开始，避免同档并发。其余档届时同轮落。

### 关联

- 台账 #70（需求）· #67（页脚，并入本轮）。
- 既有面：`docs/design/thincoder-adapter.md` §17.3（F14 模型清单）；`composer_picker.dart:173-205`（分组 / 折叠 / 搜索）。

### Pen 1（模型选择器按供应商分组 + 页脚修正 · 2026-10-18）

- **改动**：`thincoder_events.dart` 的 `optionsOf` 改经 `thincoder_options.dart` 的 `thincoderOption`（新档，24 行）——`model` 项按首个冒号拆 provider，填 `KernelOptionGroup(provider, provider)`，行 label 去 `provider:` 前缀；`composer_picker.dart` 加 `startCollapsed` 开关（默认 false，Claude 不变），`initState` 只展开当前选项所在组；`session_model_picker.dart` 在 thincoder 会话传 `startCollapsed: true` 并隐藏「管理模型」页脚（#67）；`thincoder_kernel_test.dart` T55 补 group/label 断言。
- **读数**：`flutter test test/kernel/thincoder_kernel_test.dart test/composer_test.dart` → **144 passed**（kernel 89 + composer 55）；`flutter analyze` 5 档 → **No issues**。
- **行数**：`thincoder_events.dart` **799** · `thincoder_options.dart` **24**（新）· `composer_picker.dart` 1699 · `session_model_picker.dart` 170 · `thincoder_kernel_test.dart` 2846（`thincoder_events` 加分组后一度到 818、越 800 硬顶 ⇒ 选项映射抽到 `thincoder_options.dart`，回到 799；`composer_picker` 1699 为既有体量债，本轮 +11）。
- **回滚**：revert 上述 5 档（含新档 `thincoder_options.dart`）；无数据 / 协议变更。
- **待**：轻渠道轮收口链（设计定稿 → 独立评审 → 修复 → 用户批准 → 结算）。

### Pen 1 修正（评审后 · 2026-10-18）

- 独立代码评审（round 1，实例因 stale 无结论但发现可用）后已修三项：
  1. 🔴 `startCollapsed` 只在 `initState` 播种 ⇒ 清单后到（thincoder 首包只报当前一项、完整渠道清单随后经 `config_option_update` 推）时全组展开。改为 `_seenGroups` + `_collapseNewGroups`（`initState` 与 `didUpdateWidget` 都调）：新到的组默认折叠（当前组除外），用户手动展开/收起的状态保留。
  2. 模型行 label 丢弃 agent 上报的 `name`。`thincoderOption` 改为「`name` 去同 `provider:` 前缀」（无前缀的纯标题保持原样，空则退回 value 后半段）。
  3. 补测试：`test/chat/model_picker_test.dart` 两条（初始只展开当前组；后到的组同样折叠）+ `test/kernel/thincoder_kernel_test.dart` 的 name 断言。
- 读数：`flutter test test/chat/model_picker_test.dart test/kernel/thincoder_kernel_test.dart test/composer_test.dart` → **165 passed**。
- 未补：页脚隐藏的 widget 测试（`SessionModelPicker` 需整套会话 harness；该分支只是一行条件，视觉已由用户截图获批）——若评审坚持再补 harness。
- 设计档 §17.3 的「桌面模型面零改动」已改为现状（父侧小改，已标记）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

## 用户批准（2026-10-18）

- 用户 2026-10-18 22:29 发两张截图并说「你看这样可以吗？」「这个整合可以的」——截图一 = app 的 thincoder 会话经宿主通道用 `browser_tabs` / `browser_snapshot` 读到共享标签页；截图二 = 模型菜单按供应商分组、只展开当前组、无「管理模型」页脚。本批的模型选择器形态据此**获批**。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
