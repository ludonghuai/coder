# 宿主工具通道 需求档

> 状态：已确认（用户 2026-10-18 20:08「对，一定要实现宿主工具通道」）
> 日期：2026-10-18
> 范围仓：baocode（本仓）。首篇 = 浏览器工具；通道本身与具体工具解耦。

## 1. 模块目标

让**任何内核**（首批 thincoder）都能调用宿主（baocode）提供的能力工具，与 Claude Code 的 SDK MCP 工具同权。首篇要解决：**thincoder 会话里 agent 也能用已连接的浏览器**——用户不必为了用浏览器而把会话切到 Claude Code。

## 2. 事实基线（已读）

- 宿主工具现状：浏览器工具的类型是上游 `ClaudeSdkTool`（`lib/kernel/claude_code/claude_sdk_tools.dart`，本仓为它加了 `group` 与 `picturesOnly` 两个字段），注册进 `HostTools`（自有档 `lib/host_tools/host_tools.dart`，以 `typedef HostTool = ClaudeSdkTool` 提供别名）；只有 Claude 内核把 SDK MCP server 交给 CLI（`lib/kernel/claude_code/claude_code_kernel.dart:512-516`、`:553`；`claude_code_transport.dart:249-282`）。
- thincoder 侧：`session/new` 只发空 `mcpServers`（`lib/kernel/thincoder/thincoder_kernel.dart:321-325`）；CLI 忽略非空 `mcpServers`——`thincoder/thincoder-cli/src/acp/handlers-session.mjs:266-267` 明写「MCP forwarding is M2 scope」。
- ACP 面：工具调用可由内核发起，标准反向请求只有 `fs/*` 与 `session/request_permission`（另有扩展族 `checkpoint/*`、`memory/*`、`ledger/*`、`batch/*`，见 `docs/requirements/thincoder-adapter.md` §2.2）；没有通用的「客户端工具声明」通道。
- 浏览器边界不变：只碰黄色「BaoCode」分组的标签页（`browser_extension/background.js:20-22`、`:361-393`），扩展 ID 白名单（`lib/browser/browser_bridge.dart:32`），`browser.enabled` 开关（`:41`、`:88-100`）。

## 3. 功能点

**F1 通道**：宿主工具以统一描述（名称 / 说明 / 输入 schema / 执行入口）暴露给内核；首批 = 浏览器工具集。通道与工具解耦：新增工具只改宿主注册表与一次能力声明。

**F2 thincoder 可用**：浏览器已连接且 `browser.enabled` 为开时，thincoder 会话的模型能看到并调用浏览器工具；调用落在同一 `BrowserTools` 实现上，共享标签页边界、登录态、侧栏跟随行为与 Claude 会话一致。

**F3 开关与回收**：`browser.enabled` 关闭、浏览器断开、扩展协议不兼容 ⇒ 工具不可见或调用被明确拒绝；不静默假装成功。

**F4 旧版兼容**：thincoder CLI 不支持该通道时，会话正常、工具不可见、无报错、无「假装可用」。Claude 会话现有工具路径零变化。

**F5 可扩展**：通道为后续宿主工具（图片、IDE 上下文等）留出统一接缝；本批不实现它们。

## 4. 边界（明确不做）

**B1** 首篇只做浏览器工具；图片、IDE 上下文、终端、文件系统等宿主能力不在本批。
**B2** 不扩大浏览器权限：共享标签页边界仍由扩展执行；宿主只暴露工具，不提供绕过分组/白名单的入口。
**B3** 不改变 Claude 内核的现有工具路径与审批语义。
**B4** 不要求改动与浏览器无关的 thincoder 行为；若通道必须动 thincoder 仓，改动保持上游可合并（用户已裁定「一定要实现」）。

## 5. 验收

- **A1 thincoder 全链路**：thincoder 会话、浏览器已连接、开关开 ⇒ 模型工具列表含浏览器工具；能打开共享标签页、读取标题/正文、完成一次点击或输入。
- **A2 边界**：未共享的标签页不可见；`browser.enabled` 关 ⇒ 工具不可见或调用被拒；扩展断开 ⇒ 调用失败有明确错误。
- **A3 Claude 回归**：Claude 会话的浏览器工具行为、审批与今天一致。
- **A4 旧 CLI**：把 `thincoder.path` 指到不支持该通道的旧版 ⇒ 会话正常、无工具、无报错。
- **A5 机检**：单元测试覆盖通道握手 / 工具清单 / 一次调用 / 开关关闭 / 旧版降级；thincoder mock 固件对拍。

## 6. 依赖

- **D1** ACP 客户端能力或会话参数（thincoder `session/new` 的 `mcpServers`，或等价的 ACP 扩展面）。
- **D2** 现有 `BrowserTools` / `BrowserBridge` / 浏览器扩展边界。
- **D3** thincoder CLI（可能需要实现 MCP forwarding 或新增 ACP 扩展；改动面由设计定）。
