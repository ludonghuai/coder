# 2026-10-26 · small-fixes
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 08:21「先小修，然后合并上游」；三条已核实的缺陷：#4 删除会话不清理 · #174 改名静默失败 · #175 设置页英文标题。
> 台账 = #4 #174 #175（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

本轮 = 轻量通道（缺陷修复）。三笔均可回退（单笔提交）。

- **已定决定**：走 A（轻量通道，父侧直改），不走完整链 · 用户原话：「先小修，然后合并上游」 · 时间：2026-10-26 08:21
- **笔 1（#4）**：`workspace.dart:351` 守卫恒假（`ThincoderCatalog.projects()` 恒返回空表）⇒ `_forgetGone` 永不执行。修法 = 只对「清单已确定」的内核做清理：守卫改为 `pending.any((k) => k.id != 'thincoder')`，且 `_forgetGone` 的 `titles` 排除 thincoder 线程（其清单按项目逐个补、此刻可能未回，不能被当成"已消失"）。
- **笔 2（#174）**：`workspace.dart:2809` `trimmed.length > 80 ⇒ return false`，两个调用方不看返回值 ⇒ 静默失败。修法 = 超长时给出与既有 `renameTitleTooLong` 一致的用户可见提示，不再无声返回。
- **笔 3（#175）**：`settings_dialog.dart:280` 的 `'Models (thincoder)'` 硬编码 ⇒ 改走 l10n（新增 `settingsSectionThincoderModels` 键，en/zh 两文 + 重生成）。
- 已有面：existing: `lib/workspace/workspace.dart:351` · name: `_forgetGone` · consumers: 会话清理（置顶/归档/命名/草稿）。
- 已有面：existing: `lib/settings/settings_dialog.dart:280` · name: `SettingsSection.thincoderModels` 的文案 · consumers: 设置页标题。
- 已查无：`renameTitleTooLong` 的既有文案键与展示路径需在笔 2 实读后对齐，不新造第二套提示。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
