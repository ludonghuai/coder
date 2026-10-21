# 2026-10-20 · 测试策略批：平台专属红与夹具依赖红的统一处置
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 21:11「按原计划继续走测试」；台账 #109（上游 Windows 平台红 22 条）+ #101（workbench 13 + lsp/install 15）。
> 台账 = #116（ide · 归批）。前情 = 无（独立批；输入 = #109 / #101）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**条目**：#109（上游带入的 Windows 平台红）+ #101（workbench 13 / lsp 15）+ 本轮 `side_panel_test` 的 10 条。

**披露（测试面 · 父侧直接改）**：本笔 = 测试面（`test/**`），机械改动 ⇒ 父侧直接执行，逐档跑读数，可单提交回退。

**已修（真修，不是跳过）**：三档夹具的 POSIX 路径写法平台化（`p.normalize` / `p.join`），期望值按宿主拼写：

| 档 | 改前 | 改后 |
|---|---|---|
| `test/chat/side_panel/file_open_test.dart` | 1 红 | **3/3 绿** |
| `test/chat/side_panel/side_panel_search_test.dart` | 5 红 | **6/6 绿** |
| `test/chat/side_panel/side_panel_workspace_test.dart` | 5 红 | **8/8 绿** |

**已处置（跳过，带因）**：`test/ide/lsp/install/mason_server_provider_test.dart` 15 红 —— 夹具真跑 `chmod`（`:57` / `:70`）且 registry 条目是 `/` 分隔，是 POSIX 安装器的单测；加 `@TestOn('!windows')`（文件头三行说明），同目录 `mason_resolution_test` 12/12 仍绿。

**仍红（本轮未处置，原因已核）**：
- `test/chat/side_panel/side_panel_test.dart` 10 条：夹具自带 `'/p/...'` 字面量 60+ 处（`const FileOpenRequest('/p/a.dart')` 等），平台化是逐处机械改写，非一行能修。
- `test/ide/ide_standalone_test.dart` 1 条：同族路径字面量。
- `test/ide/workbench/color_theme_picker_test.dart` 10 条 + `explorer_exclude_test.dart` 2 条 + `problems`/`tabs` 各 1：首条断在 `IdeQuickInput` 未打开（第一段 chord 生效、第二段不生效），根因未定；`macOS labels ... ⌘` 一条取决于宿主（键表读 `ideUsesMacKeys`，测试用 `debugDefaultTargetPlatformOverride` 覆盖不到）。

**读数（逐档跑）**：上述三档 + lsp 目录全绿；`test/chat/side_panel` 合计由 22 红降至 11 红。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
