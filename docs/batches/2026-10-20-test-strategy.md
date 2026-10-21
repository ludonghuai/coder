# 2026-10-20 · 测试策略批：平台专属红与夹具依赖红的统一处置
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 21:11「按原计划继续走测试」；台账 #109（上游 Windows 平台红 22 条）+ #101（workbench 13 + lsp/install 15）。
> 台账 = #109 · #101（ide · 归批）。前情 = 无（独立批）。
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

**第二轮（21:32–21:50）**：探到一条**产品面决定**，按轻重缓急退回未改：

- 试改 `displayPath`（`lib/chat/composer/composer_files.dart:55`）让输入框 chip / `@` 引用在 Windows 也显示 `lib/main.dart`（现为 `lib\main.dart`）。改后 `side_panel_test` 10 红 → 9 红，但 `composer_files_test` **17/17 → 4 红**（该档四条断言旧契约：宿主拼写）。
- **撤回**（`git checkout` 还原，stash 已 drop，复跑 `composer_files_test` 17/17 绿）——显示口径是用户可见的产品决定，不由测试批顺手改。**待用户裁定**：聊天/输入框里的项目内路径显示 `/`（跨平台一致，与消息正文里的链接一致）还是 `\`（宿主拼写）。

**现状**：`test/chat` 17 红 = 8 条既有平台红（`code_citation` 3 · `composer_files` 4 · `content_image` 1，与本轮无关，两态对照已验）+ `side_panel_test` 9 条（差在内部路径断言与 diff CRLF）。

**第三轮（22:05–23:15）**：用户裁定 **A（路径显示 `/`）** 后落地，`test/chat` 全部转绿。

| 改动 | 读数 |
|---|---|
| `displayPath` 项目内相对路径统一 `/`（`lib/chat/composer/composer_files.dart:55`） | 输入框 chip / `@` 引用 / 回退对话框显示名；复制路径仍走 `paths.relative`（宿主拼写，粘终端正确） |
| `composer_files_test` 四条断言改新契约（`:292/:357/:405/:423/:433`） | **17/17 绿** |
| `side_panel_test`：`_q`（宿主拼写）+ 夹具 `_Files` 按宿主归一 + 输出路径 `_q` | **45/45 绿**（原 10 红） |
| `code_citation_test`：root/期望按宿主；一条着色用例在 Windows 上测不到目标 ⇒ 平台跳过 | **28/28 绿**（原 3 红；跳过 1 条已入账 #117） |
| `content_image_test`：项目内图片路径期望归一 | **绿**（原 1 红） |
| `ide_standalone_test`：临时文件 `p.join` | **15/15 绿**（原 1 红，且需 `import package:path`) |

**总读数**：`test/chat` **540/540 全绿**（本轮开始 17 红）；`test/ide/ide_standalone_test` 15/15；`test/ide/lsp/install` 12 绿 + 整档按平台跳过；`analyze`（test/chat + ide_standalone + composer_files）No issues。

**仍红（本批未处置）**：`test/ide/workbench` 14 条（`color_theme_picker` 10 · `explorer_exclude` 2 · `problems`/`tabs` 各 1）——首条断在「第二段 chord 没打开 `IdeQuickInput`」，根因未定；`macOS ⌘` 一条的键表读宿主、`debugDefaultTargetPlatformOverride` 覆盖不到。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
