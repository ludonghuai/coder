# 2026-10-23 · 去掉 Claude Code 自动下载
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-23 · 来源 = 用户 2026-10-23 02:52「把那个自动下载claude code给我删掉」；上游 1.6.0 把「第一次开对话时自动下载 Claude Code CLI」设为默认行为，与本 fork「thincoder 为默认内核」的取向冲突。
> 台账 = #157（kernel · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-23
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**本笔 = 轻通道**（缺陷修：实现与用户裁定相反）| 改动 = 会话启动不再下载 Claude Code CLI | 影响面 = `lib/kernel/claude_code/process_transport_io.dart:89` 一处调用 + 两条用户可见文案 | 回滚 = revert 单提交。

## 已定决定（2026-10-23 02:52）

- **已定决定**：去掉「第一次开对话时自动下载 Claude Code CLI」；会话启动时若没有可用的 CLI，就按「未安装」报出，**不联网下载**；设置页的显式安装按钮保留（手动仍是唯一安装路径）· 用户原话：「把那个自动下载claude code给我删掉」· 时间：2026-10-23 02:52

**为什么删**（可核对）：上游 1.6.0 的发布说明写「Claude Code CLI 成为默认内核：没装的话，第一次开对话时自动下载」；本 fork 的默认内核是 thincoder（`lib/kernel/kernel_registry.dart:40` 的 `[thincoder, claudeCode]`），一个默认不用的内核在后台自动下载二进制，属于未经请求的网络与磁盘行为。

## 关键判据

| # | 判据 | 读数方式 |
|---|---|---|
| 1 | 会话启动路径不再触发下载 | `process_transport_io.dart:89` 走 `locate(install: false)`；全文搜 `locate(` 只有设置页的显式 `install()` 仍为 `install: true` |
| 2 | 没有 CLI 时会话说清「未安装」 | 该路径抛 `ClaudeNotInstalled` 而不是 `ClaudeDownloadFailed` |
| 3 | 设置页文案不再承诺自动下载 | `claudePathMissing` 中英各一条改文 |

## 授权口径

轻通道（用户当场点名的行为，与裁定相反 ⇒ 按缺陷修处理）；不另走设计评审。范围仅本仓，不动 `thincoder/` 外仓。

## 段适用性声明（收口前补齐）

> 不适用：§2 —— 轻通道缺陷修（用户当场点名的行为，实现与裁定相反），不另走设计轮；判据与影响面见本段「关键判据」与「授权口径」，无需设计档。
> 不适用：§3 —— 无设计档，故无设计评审；改动面 = 一处调用 + 两条文案，已由主 agent 逐行复核并在 §6 记读数。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）

## 用户批准（2026-10-23 02:52）

用户原话：「把那个自动下载claude code给我删掉」——即批准本改动，且明确要求删除该行为。改动落地后于 2026-10-23 05:0x 合入 `463411bd`（"btest: the expect file moves to a QA root of its own" 一并提交，因同轮工作树共用）。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

## 验证与收口（主 agent，2026-10-23 06:50）

**改动落点**（实测读数，非引述）：

| 判据 | 命令 | 读数 |
|---|---|---|
| 会话启动不再下载 | `grep "LocalClaude.locate()" lib/**` | **0 处** |
| 启动路径改走不下载 | `grep "locate(install: false)" lib/**` | **2 处**（本笔 `process_transport_io.dart:89` + 既有的 `claude_haiku_io.dart:114`） |
| 手动安装仍在 | `grep "LocalClaude.install()" lib/**` | **1 处**（设置页的显式安装） |
| 文案不再承诺自动下载 | `grep "不会自动下载" lib/l10n/app_zh.arb` | **1 处**（中英各一条，`gen-l10n` 生成物已重生成） |
| 静态检查 | `dart analyze` | **No issues found!** |
| 构建 | `flutter run -d windows` | 构建成功、`Unhandled=0`（pid 47772 → 50492 两次构建均如此） |

**如实说明两条**：

1. **无自动化用例**：本笔改的是一个调用点的缺省实参（`install: true → false`）与两条文案，没有可断言的返回值；现有测试档不含 Claude CLI 安装路径。判据以上表的静态读数 + 构建为准，未新增测试（也避免了给一个"不再发生的行为"写测试）。
2. **提交归属**：改动与 btest 的 F3.2 同树，落在 `463411bd`；本批没有独立提交。回滚 = `git revert 463411bd` 的对应 hunk（或单行改回 `install: true`）。

**结账**：本批完成；台账 #157 同轮核销。
