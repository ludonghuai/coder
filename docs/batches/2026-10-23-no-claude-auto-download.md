# 2026-10-23 · 去掉 Claude Code 自动下载
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-23 · 来源 = 用户 2026-10-23 02:52「把那个自动下载claude code给我删掉」；上游 1.6.0 把「第一次开对话时自动下载 Claude Code CLI」设为默认行为，与本 fork「thincoder 为默认内核」的取向冲突。
> 台账 = #157（kernel · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
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

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
