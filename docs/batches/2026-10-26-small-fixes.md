# 2026-10-26 · small-fixes
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 08:21「先小修，然后合并上游」；三条已核实的缺陷：#4 删除会话不清理 · #174 改名静默失败 · #175 设置页英文标题。
> 台账 = #4 #174 #175（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-26
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

本轮 = 轻量通道（缺陷修复）。三笔均可回退（单笔提交）。

- **已定决定**：走 A（轻量通道，父侧直改），不走完整链 · 用户原话：「先小修，然后合并上游」 · 时间：2026-10-26 08:21
- **笔 1（#4）**：`workspace.dart:351` 守卫恒假（`ThincoderCatalog.projects()` 恒返回空表）⇒ `_forgetGone` 永不执行。修法 = 只对「清单已确定」的内核做清理：守卫改为 `pending.any((k) => k.id != 'thincoder')`，且 `_forgetGone` 的 `titles` 排除 thincoder 线程（其清单按项目逐个补、此刻可能未回，不能被当成"已消失"）。
- **笔 2（#174）**：`workspace.dart:2809` `trimmed.length > 80 ⇒ return false`，两个调用方不看返回值 ⇒ 静默失败。修法 = 超长时给出与既有 `renameTitleTooLong` 一致的用户可见提示，不再无声返回。
- **笔 3（#175）**：`settings_dialog.dart:280` 的 `'Models (thincoder)'` 硬编码 ⇒ 改走 l10n（新增 `settingsSectionThincoderModels` 键，en/zh 两文 + 重生成）。
- 已有面：existing: `lib/workspace/workspace.dart:351` · name: `_forgetGone` · consumers: 会话清理（置顶/归档/命名/草稿）。
- 已有面：existing: `lib/settings/settings_dialog.dart:280` · name: `SettingsSection.thincoderModels` 的文案 · consumers: 设置页标题。
- 已查无：`renameTitleTooLong` 的既有文案键与展示路径需在笔 2 实读后对齐，不新造第二套提示。

> 不适用：§2 —— 轻量通道，三笔均为已核实缺陷的直改（无独立设计文档，设计即本节各笔条目与落点）。
> 不适用：§3 —— 轻量通道；独立复核以父侧 `advisor(type=code)` 完成（`reviewId 6c706c31`，**VERDICT: pass**，对三处可疑点逐一排除），结论记入 §6；code 评审无 batch 写入面。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

**批准**：用户 2026-10-26 08:21 逐字「先小修，然后合并上游」⇒ 批准本批三笔修复及其范围（#4 会话清理 · #174 改名提示 · #175 设置页标题）。实施以父侧直改 + 单笔提交方式进行，用户已知悉轻量通道选择。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

### 验证与收口（父代理，2026-10-26 08:55）

**提交**：`82c0eb5f`（三笔一笔提交，可单笔回退）。

**验证读数（实跑）**：

| 检查 | 命令 | 结果 |
|---|---|---|
| 静态面 | `flutter analyze --no-pub lib/workspace lib/workbench.dart lib/settings lib/l10n` | **No issues found** |
| 相关测试 | `flutter test --no-pub test/workspace_test.dart test/workspace test/settings` | 主体通过；13 条失败 |
| **旧债对照（关键）** | `git stash` 掉本批改动后复跑 `test/settings/jsonc_file_test.dart` + `data_dir_page_test.dart` | **同样 4 条失败** ⇒ 属既有失败（Windows 路径族 / macOS variant），**非本批引入** |

**独立复核**：`advisor(type=code)` 对三档全量重读（workspace 3019 行 · workbench 4793 行 · settings_dialog 850 行），**VERDICT: pass**，无遗留项；并对三处可疑点给出排除依据（可空 `content` 强解在 `save` 赋值之后 · 键位 `canRun` 过滤保证 map 命中 · `_grid.restore` 前已移除无线程 pane）。

**台账结算**：
- **#4 已核销**（守卫不再恒假；`_forgetGone` 排除 thincoder 线程）。
- **#174 已核销**（超长改名弹既有文案提示；`workspace_bridge` 无 UI 上下文的调用方仍静默，已记在核销证据里）。
- **#175 部分完成**（设置页标题已本地化；①模型配置两套 ②@ 索引两套 ③原子写两套仍未动，本行保持未决）。

**不适用**：§5 —— 轻量通道由父侧直改，无 eng-coder 实施段。

**遗留（已入队，不在本批）**：`lib/link/workspace_bridge.dart:320` 改名失败无提示（无 UI 上下文）· 上游合并（72 提交 / 16 冲突文件）· git fetch 风暴。
