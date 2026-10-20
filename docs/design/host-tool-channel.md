# 宿主工具通道 设计档

> 板块：内核适配（宿主工具）· 范围仓：baocode（本仓）；转发面在 thincoder 仓（out-of-repo 轮）。
> 配对需求档：`docs/requirements/host-tool-channel.md`（F1–F5 · B1–B4 · A1–A5）。
> 状态：已实施（注册面正名 + `HostMcpServer` + 内核接线落地）· 2026-10-18 · 行号 = 标注时点快照（实施后读数与偏差见 §16）。

---

## 1. 目标与范围

**一句话**：宿主（baocode）自有的工具——首批 = 浏览器工具——经 ACP 的标准 `mcpServers` 面交给任何内核；内核对它的获得方式与 Claude Code 的 SDK MCP 工具同权。

**本批交付面**：通道本身 + 浏览器工具在 thincoder 会话里可见可调用（F1 / F2 / F3 / F4 / F5 的接缝）。
**本批不做**：图片、IDE 上下文、终端、文件系统工具（B1）；不改浏览器边界（B2）；不改 Claude 路径（B3）；不改 thincoder 与浏览器无关的行为（B4）。

**事实基线**：需求档 §2 已列（工具注册面、`session/new` 的空 `mcpServers`、CLI 对非空的处理、扩展边界三件），本档不复述。本档只补设计依赖的**新增事实**：

- thincoder 核已有一个成熟的 MCP 客户端：stdio / http / ws 三种传输、工具展开、令牌合成、退避重连、取消信号、输出截断（`thincoder/thincoder-core/mcp.mjs:56-90`、`:145-176`、`:192-205`）。
- thincoder 的 MCP 工具默认 `readonly: false`（`thincoder-core/mcp.mjs:160`）⇒ 会走审批门（`thincoder-core/agent/dispatch.mjs:177` 的短路条件不含它）。
- thincoder 的 MCP 客户端**不读**服务端 `initialize` 的 `instructions`，也**不发** `notifications/cancelled`（`thincoder-core/mcp.mjs:207-231`；`mcp/transport-http.mjs:229`）。
- thincoder 自己有一个内建 `browser` 工具（它自己的自动化浏览器，`thincoder-core/tools/browser.mjs:132`）；与宿主浏览器工具并存。

---

## 2. 做法与理由

### 2.1 接入形态

```text
baocode（宿主，单进程）
  ├─ HostTools（注册表，唯一真名面）          ← 浏览器工具 / 图片工具注册在这
  ├─ Claude Code 面 = HostTools.handle()        ← 既有：CLI 的 control 通道（mcp_message）
  └─ HostMcpServer（新）                        ← 本批：环回 Streamable HTTP MCP 端点
        │  url + 每会话 Bearer 令牌，经 ACP `session/new|load|resume` 递给 CLI
        ▼
thincoder CLI（子进程）
  └─ 核 MCP 客户端（既有）：initialize → tools/list → 工具进 agent.tools（前缀 `baocode_`）
        │ 模型调用 → tools/call（HTTP）
        ▼
  宿主执行 → 结果 / 错误文本回给模型
```

两条面共用**一份工具定义**与**一个执行入口**（每工具的 `run`），差别只在传输：Claude 走 CLI 控制通道（零网络），ACP 内核走本机环回 HTTP（ACP 只能给 URL，见 §3）。

### 2.2 最近先例对照（对齐 ∥ 偏离及理由）

对齐（照抄形态，不另造）：

| 面 | 先例 | 我们照抄的形 |
|---|---|---|
| 进程内 MCP server 实现 | `lib/host_tools/host_tools.dart` 的 `handle`（initialize / tools/list / tools/call / notifications；迁自 `claude_sdk_tools.dart`，§16-1） | 同一份 `handle` 同时服务两种传输 |
| 本机认证监听 | `lib/browser/browser_bridge.dart:214-242`（loopback + 系统选端口 + 令牌）；`lib/models/proxy/model_proxy.dart:81-82`（loopback `HttpServer.bind`） | `127.0.0.1` + 端口 0 + 每会话令牌 |
| 工具名面 | Claude：`mcp__baocode__<name>`（`HostTools.server` 前缀，`lib/host_tools/host_tools.dart`）；thincoder MCP：`<server>_<name>`（`thincoder-core/mcp.mjs:145-155`） | 注册表键保持 `browser_open`，两面各自加前缀 |
| 工具卡成形 | `lib/kernel/thincoder/thincoder_events.dart:357-402`（按 ACP `kind` 造项） | 追加一条按宿主注册表取 `kind` / `summary` 的分支 |
| 能力位协商 | `docs/design/thincoder-adapter.md` §3.4（`initialize` 的 `agentCapabilities` 现状） | 只读 `mcpCapabilities.http`，不加版本门 |
| 外仓 ACP 扩面 + 本仓接线 | 批 5 / F12（`docs/requirements/thincoder-adapter.md:173`：B1 = 默认不改仓 + 经用户裁定的最小接口例外；`docs/batches/thincoder-subagent-attribution.md:85`）· 批 8 / F16（`docs/requirements/thincoder-adapter.md:211` 记裁原话；`docs/batches/thincoder-suspension.md:170`） | 外仓新档 + 本仓接线，各带批次档与测试；B1 例外见 §7.2 |

偏离（逐条给理由）：

1. **新档 `lib/host_tools/host_mcp_server.dart`**。Claude 的 SDK server 走 CLI 控制通道，不经网络；ACP 只接受 MCP 服务器的**连接参数**（URL 或命令），没有进程内注册面 ⇒ 必须有一个本机监听。Claude 路径零改动。
2. **注册面正名**（`ClaudeSdkTool(s)` → `HostTool(s)`，文件迁 `lib/host_tools/`）。同一注册表从此服务两个内核，旧名只说了一半；改名是机械改动（见 §7 与 D2）。
3. **加 `group` 字段**。注册表里已有浏览器与图片两组（`lib/images/image_tools.dart:44-50`）；MCP 面按组暴露，本批只开浏览器组（B1）。

### 2.3 公开资料调查（survey-evidence）

| 来源 | 取了什么 | 结论 |
|---|---|---|
| ACP v1 协议文档 `docs/protocol/v1/session-setup.mdx`（`raw.githubusercontent.com/agentclientprotocol/agent-client-protocol`，2026-10-18 读） | `session/new` / `session/load` / `session/resume` 三个请求都带 `mcpServers`；HTTP 传输须客户端先看 `agentCapabilities.mcpCapabilities.http`；逐字一句「Clients **MAY** use this ability to provide tools directly to the underlying language model by including their own MCP server.」 | **本批用法就是规格写的这一种**；旧内核不收即无工具，是合规降级 |
| ACP v1 schema `schema/v1/schema.json`（2026-10-18 取回；文件 ~200 KB，取回副本中段被工具截断） | `McpCapabilities.http` / `.sse` 两键在场（取回副本 :2507-2524）；`McpServer` 变体带 `_meta` 扩展位 | 能力位与 `_meta` 都是协议自带位置 |
| MCP 2025-06-18 schema `schema/2025-06-18/schema.json`（2026-10-18 取回） | `CallToolResult.isError` 逐字「errors that originate from the tool SHOULD be reported inside the result object, with `isError` set to true, _not_ as an MCP protocol-level error response」；`notifications/cancelled{requestId}`；`Tool.inputSchema`；`notifications/tools/list_changed` | 工具错误走结果体、协议错误走 JSON-RPC 错误——本批错误映射据此 |
| MCP 规范站页 `https://modelcontextprotocol.io/specification` | 未直接取（用上面的 schema 为一手） | 站点页不再引 |
| thincoder 自己的契约 `thincoder/docs/cli/design/ACP-CLIENT.md` | `:33`（`session/new` 行「忽略 `mcpServers` 并 warn」）、`:572`（G7 登记为未做面）、§12.1（`_meta` 扩展位） | 转发面是上游**已登记、待做**的项（M2），不是我们发明的面 |

---

## 3. 通道选型（核心决策）

### 3.1 候选

- **A1 · MCP 转发 + stdio 子进程**：baocode 另发一个 `baocode-mcp` 程序，CLI 起它做子进程；它再回连 app。
- **A2 · MCP 转发 + 环回 HTTP**：baocode 进程内起 Streamable HTTP MCP 端点；URL + 令牌经 `session/new` 递给 CLI。
- **B · ACP 自造反向工具面**：baocode 用自定义方法把工具描述递给 CLI（如 `session/new._meta`）；CLI 调用时发反向请求 `host/tools/call` 回来。
- **C · 混合**：声明走 ACP 扩展，调用走 MCP。

### 3.2 决策表

| 面 | A1 · stdio 子进程 | **A2 · 环回 HTTP（采用）** | B · ACP 自造反向面 | C · 混合 |
|---|---|---|---|---|
| 形态 | 第二个可执行体 + 双跳（CLI→子进程→app） | 进程内监听，一次 HTTP + 一次 JSON-RPC | 同一 stdio 管道上的请求/应答 | A2 的调用面 + B 的声明面 |
| 上游可合并性 | 中（转发面是 M2；多出的可执行体不是） | **高（转发面）· 中（信任位）**：转发面 = `thincoder/docs/cli/design/ACP-CLIENT.md:33` / `:572` 登记的 M2，且规格逐字允许（§2.3）；第二个上游面 = 信任位 `_meta` → `permissionExempt`（非标准扩展，接受风险与回落见 §12-11） | 低：ACP 无「客户端工具」概念，官方答案是「自带 MCP server」 | 低（同 B，且多一层） |
| 延迟 | 多一跳进程 IPC | 本机一次 HTTP（与 B 同量级；被浏览器动作本身掩盖） | 同一管道，最低 | 同 A2 |
| 进程 / 端口生命周期 | 新进程 + 新端口 + 双跳；打包 / 签名 / 路径全新 | 1 个环回监听（进程内），无新进程 | 无 | 同 A2 |
| 安全面 | 新进程 + 两个本机面 | 1 个**已认证**环回面（§4.3） | **无新网络面**（最省） | 同 A2 |
| 旧 CLI 降级 | 天然（能力位不在 ⇒ 不发） | 天然（同左） | 天然（未知 `_meta` / 方法被忽略） | 天然 |
| 成本（本仓，估算） | 最高（第二个可执行体跨三平台，未估） | ~260 行 server + 54 行接线（⑭ ≤40 + ⑮ ≤14，§7.1）+ 测试 | ~200 行客户端面 + 外仓 ~150 行 + 测试 | 两者之和 |
| 结论 | 被否 | **采用** | 被否 | 被否 |

### 3.3 结论与理由

**采用 A2**：

1. **它不是一个新协议**。ACP 规格逐字允许「客户端自带 MCP server 把工具给模型」；thincoder 侧要做的只是把它自己登记为待做的 M2 转发面做掉（`thincoder/docs/cli/design/ACP-CLIENT.md:33`、`:572`）。B 要在 ACP 之外发明一套客户端工具面，上游没有采用动机 ⇒ 长期 fork。
2. **服务端几乎免费**：`HostTools.handle`（`lib/host_tools/host_tools.dart`；编制日名 `ClaudeSdkTools.handle`，迁自 `claude_sdk_tools.dart`，§16-1）已经是一个完整的 MCP server（initialize / tools/list / tools/call / 取消），换一层传输即可复用，工具体系零复制。
3. **降级不需要协商代码**：旧 CLI 不宣告 `mcpCapabilities.http` ⇒ 我方不发 `mcpServers` ⇒ 无工具、无报错、无日志噪声（F4）。
4. **代价可控且可测**：新增一个已认证的环回监听（与 `BrowserBridge` 的既有做法同型），无新进程、无打包面。

**A1 被否**：第二个可执行体要跨三平台打包、签名、找路径，还要一条回连 app 的 IPC——两条本机面换来零收益。
**B 被否**：省下的只有一个本机端口，代价是自造协议（声明 / 调用 / 错误 / 取消 / 并发语义全要自定）、两侧新代码量不低于 A2、且不可上游合并。
**C 被否**：能力协商已由 ACP 的 `mcpCapabilities` 给出，声明面不需要自造；混合只增加面。

---

## 4. 接口契约

### 4.1 分层（本仓）

```text
lib/host_tools/host_tools.dart        HostTool / HostToolCall / HostTools（注册表 + MCP handle）
lib/host_tools/host_mcp_server.dart   HostMcpServer（环回 HTTP + 令牌 + 组暴露 + 错误映射）
lib/browser/browser_tools.dart        浏览器组注册（group: 'browser'）
lib/kernel/thincoder/thincoder_kernel.dart   能力位 → mcpServers；teardown 撤令牌
lib/kernel/thincoder/thincoder_events.dart   工具名 → 卡片（kind / summary 回注册表）
```

### 4.2 ACP 线形（本通道用到的全部）

**能力位（内核 → 我方；本批由 thincoder 侧新增）**

```json
{ "protocolVersion": 1,
  "agentCapabilities": { "mcpCapabilities": { "http": true, "sse": true }, "...": "其余不变" } }
```

我方只读 `agentCapabilities.mcpCapabilities.http`；缺键 / 非 true = 不支持（不猜、不加版本门）。

**会话请求（我方 → 内核）**

```json
{ "sessionId": "12",            // session/new 不带；load / resume 带
  "cwd": "D:\\proj",
  "mcpServers": [
    { "type": "http",
      "name": "baocode",
      "url": "http://127.0.0.1:52431/mcp",
      "headers": [ { "name": "Authorization", "value": "Bearer <43 字符 base64url>" } ],
      "_meta": { "baocode.dev/trusted": true } } ] }
```

| 规则 | 判据 |
|---|---|
| 发 `mcpServers` 的门 = `mcpCapabilities.http == true` **且**「暴露组内有已注册工具」（`HostTools.anyIn(exposedGroups)` 为真） | 两道门都在我方（内核适配层），不依赖 CLI 行为 |
| `exposedGroups` = 组白名单常量（`HostMcpServer.exposedGroups`，本批 `{'browser'}`） | 它只说「哪些组可暴露」，不表达「组内有没有工具」；有没有一律看 `anyIn` |
| 任一不满足 ⇒ 不发，不带该键（空数组同理） | 旧 CLI 连 warn 都不会打（现状 `handlers-session.mjs:266-268` 的日志只在收到非空时打）；「无工具」= `anyIn` 为假（未连接 / 开关关，§5.2–§5.3） |
| `session/load` / `session/resume` 同样带 `cwd` + `mcpServers` | ACP 规格要求三处都带（`session-setup.mdx`）；thincoder 的实现只读 `sessionId`（`handlers-slots.mjs:64-99`） |
| `_meta["baocode.dev/trusted"]` 只表达「这个 server 是提交请求的那一端自己的」 | 与 ACP 通用条款一致：不认的客户端忽略即合规；信任锚 = 客户端（§4.5） |
| 回滚语义（关通道） | 置空 `exposedGroups` ⇒ `anyIn` 恒假 ⇒ 任何内核都不再收到 `mcpServers`（§14） |

### 4.3 MCP 线形（宿主 server）

**传输与鉴权**

```text
POST http://127.0.0.1:<port>/mcp
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json, text/event-stream
```

| 情形 | 线上 |
|---|---|
| 正常请求 | `200 application/json` + JSON-RPC 响应体（**错误也用 200**：客户端只在 `!resp.ok` 时判成 `HTTP <status>`，`thincoder-core/mcp/transport-http.mjs:173-175`） |
| 通知（`notifications/initialized`、`notifications/cancelled`） | `202` 空体 |
| `GET /mcp` | `405`（客户端据此降级为纯 POST 模式，`transport-http.mjs:77-84`） |
| 无令牌 / 令牌不认 | `401` 空体 + `WWW-Authenticate: Bearer`（在解析 JSON 之前） |
| 其它路径 | `404` |
| 请求体 > 1 MiB | `413` |
| 会话标识 | 不发 `Mcp-Session-Id`：无状态，令牌即会话身份 |

**方法**

| 方法 | 请求 | 响应 |
|---|---|---|
| `initialize` | `{protocolVersion, capabilities:{}, clientInfo:{…}}` | `{protocolVersion: <回显>, capabilities:{tools:{}}, serverInfo:{name:"baocode",version:"1.0.0"}, instructions:<组内说明>}` |
| `notifications/initialized` | — | `202` |
| `tools/list` | `{}` | `{tools:[{name, description, inputSchema}]}`（暴露组内，去掉 `picturesOnly` 工具） |
| `tools/call` | `{name, arguments}` | `{content:[…], isError?}` |
| `notifications/cancelled` | `{requestId}` | `202`（本批不会收到；见 §12-3） |
| `ping` | `{}` | `{}` |
| 其它方法 | — | `200` + `{"jsonrpc":"2.0","id":…,"error":{"code":-32601,"message":"Method not found: …"}}` |

**工具条目与调用**

```json
{ "name": "browser_open",
  "description": "Opens a URL in a new tab of the user's browser, in the BaoCode tab group, …",
  "inputSchema": { "type": "object", "properties": { "url": {…}, "description": {…} }, "required": ["url"] } }
```

```json
// 调用
{ "jsonrpc": "2.0", "id": "7", "method": "tools/call",
  "params": { "name": "browser_open", "arguments": { "url": "https://example.com", "description": "Open the docs" } } }

// 成功
{ "jsonrpc": "2.0", "id": "7",
  "result": { "content": [ { "type": "text", "text": "Tab [12] Example — https://example.com" } ], "isError": false } }

// 工具失败
{ "jsonrpc": "2.0", "id": "7",
  "result": { "content": [ { "type": "text", "text": "<错误文句>" } ], "isError": true } }
```

**错误映射**

| 情况 | 线上 | 依据 |
|---|---|---|
| 工具抛错 | `result.isError:true` + 文本 = 错误文句 | MCP 规范逐字：工具错误放结果体（§2.3） |
| 未知工具 | 同上，文本 `No tool <name>.` | 与 Claude 面同句（`HostTools.handle` 的未知工具分支，`lib/host_tools/host_tools.dart`） |
| 组未暴露（开关关后仍调用） | 同上，文本 `BaoCode's browser tools are off (Settings → Browser).` | F3「调用被明确拒绝」 |
| `image` 内容块 | 换成一行文本注记（图片只对 Claude 面可见，见 §12-1） | thincoder 客户端把非 text 块 `JSON.stringify`（`thincoder-core/mcp.mjs:192-199`） |
| JSON 解析失败 / 参数非法 / 未知方法 | `-32700` / `-32602` / `-32601` | JSON-RPC 2.0 |

### 4.4 工具名与两面映射

| 面 | 模型看到的名字 | 证据 |
|---|---|---|
| Claude Code | `mcp__baocode__browser_open` | `HostTools.server` 前缀（`lib/host_tools/host_tools.dart`） |
| thincoder | `baocode_browser_open` | `thincoder-core/mcp.mjs:145-155`（`<server>_<tool>`，非字母数字换 `_`，截 64） |
| 会话里的工具卡 | `baocode_browser_open`（CLI 判 `kind:"other"`） | `thincoder-cli/src/acp/bridge.mjs:284-292` |
| 注册表键（唯一真名） | `browser_open` | `lib/browser/browser_tools.dart:92-130` |

工具卡还原：`thincoder_events.dart` 的 `_tool()` 在 `kind:"other"` 时，用 `HostTools.lookup(去前缀的名字)` 取注册表里的 `kind`（`browser`）与 `summary`（`browserStepSummary(name, input, output)`），造出与 Claude 面同形的浏览器步骤卡；查不到就按既有 `other` 卡（零行为变化）。

### 4.5 审批语义

**结论：宿主工具免审**（两面一致）。

- Claude 面本就免审：`--allowedTools mcp__baocode`（`claude_code_transport.dart:274-283`），理由逐字「they only do what the app does」（`:79-81`）。
- thincoder 面：MCP 工具默认 `readonly:false` ⇒ 走审批门（`thincoder-core/agent/dispatch.mjs:177`）。本批用 `_meta["baocode.dev/trusted"]` 让 CLI 给这批工具打 `permissionExempt: true`，加进同一条短路条件 ⇒ 免审。
- **信任锚 = 提交请求的客户端**：`baocode.dev/trusted` 只声明「该 MCP server 由提交这条 ACP 请求的客户端自己提供」——本机环回 + 每会话令牌已把 server 身份绑到本进程，宿主不再造第二套身份面。**上游接受风险**：该位是 thincoder 的非标准扩展面（第二个上游面，`thincoder-core/mcp.mjs:160` → `agent/dispatch.mjs:177`），上游可能拒收；判定条件见 §12-11（拒收 ⇒ 回落逐调用审批）。
- **不改成 `readonly: true`**：那是假契约（浏览器动作有外部后果），且只读子代工具表按它过滤（`thincoder-core/agent-tools/consult.mjs:276`）——浏览器工具会流进旁路咨询子代理。
- **planMode 不变**：planMode 门在审批门之前（`dispatch.mjs:61`），非只读工具照旧被拒。
- **主防线不变**（B2）：只有黄色「BaoCode」分组的标签页可达（`browser_extension/background.js:20-22`、`:361-393`），扩展 ID 白名单（`lib/browser/browser_bridge.dart:32`），`browser.enabled` 开关（`:39-41`、`:88-100`）。

被否：逐调用审批（每次点击都弹卡，与 Claude 面分叉）；`readonly:true`（见上）；放开 `autoApprove`（全局，越权面太大）。

### 4.6 返回 / 错误 / 取消 / 超时 / 并发

| 面 | 契约 |
|---|---|
| 返回 | MCP 内容块数组；文本即模型读到的内容。浏览器工具原有文本原样透传 |
| 错误 | 工具错误 = `isError:true` + 文本（模型能看见并自我纠正）；协议错误 = JSON-RPC error |
| 取消 | **不传到宿主**：thincoder 客户端把 `tools/call` 的等待按回合 abort 丢掉，但不发 `notifications/cancelled`（`thincoder-core/mcp.mjs:20-35`、`transport-http.mjs:229`）。回合取消 ⇒ 模型不再等；在飞的浏览器动作跑完，结果被丢弃。宿主侧已实现 `notifications/cancelled` 处理（零成本，供未来客户端使用） |
| 超时 | 客户端每次请求 120 s（`thincoder-core/mcp/helpers.mjs:6`）；握手 30 s（`:5`）。超过由 CLI 报工具错误（不静默成功）。宿主自身不设总超时，各工具自带上界（页面加载 20 s 等，`browser_tools.dart:511-517`） |
| 并发 | thincoder 同一批里的非只读工具**串行**执行（`thincoder-core/agent/dispatch.mjs:264-266`）；多会话 / 多桌面实例可并发，server 逐请求独立处理，标签页级顺序由浏览器层负责 |

### 4.7 宿主注册面

```dart
class HostTool {
  final String name, description;
  final Map<String, Object?> inputSchema;
  final Future<Object> Function(Map<String, Object?> input, HostToolCall call) run;
  final ToolKind? kind;
  final String Function(Map<String, Object?> input, String? output)? summary;
  final List<String> Function(String output)? files;
  final bool alwaysLoad;
  final String group;          // 新增：'browser' | 'images'
  final bool picturesOnly;     // 新增：答案只有图（MCP 面不出，见 §12-1）
}

abstract final class HostTools {
  // 既有语义零变（Claude 面）：register / unregister / instruct / called / any / servers / handle
  static List<HostTool> byGroup(String group);
  static bool anyIn(Set<String> groups);
  static HostTool? lookup(String name);   // 工具卡还原用
}
```

**组暴露**：`HostMcpServer.exposedGroups` = 组白名单常量（本批 `{'browser'}`）；「有没有可暴露的工具」一律用 `HostTools.anyIn(exposedGroups)` 判（§4.2），不从集合本身读。Claude 面的 `handle` 仍列**全部**工具（既有语义，A3 不变）；只有 MCP 面按组过滤，并跳过 `picturesOnly` 的工具（`browser_screenshot`）。

---

## 5. 机制与生命周期

### 5.1 起停

```text
workbench 启动
  └─ BrowserTools.start()（lib/workbench.dart:517）
        └─ bridge.used ⇒ register()：28 个工具进 HostTools（group: 'browser'）

thincoder 会话 prepare()
  ├─ 起进程 → initialize（记 mcpCapabilities.http）
  ├─ 门：_httpMcp && HostTools.anyIn(exposedGroups)（§4.2）
  │     ├─ 首次过门：HostMcpServer.ensure() 绑定 127.0.0.1:0（懒启动；幂等；失败记一条 appEvent，本次不带 mcpServers，会话照常）
  │     └─ HostMcpServer.issue(sessionId, cwd) → {url, headers, token}
  ├─ session/new | load | resume（带 cwd + mcpServers）
  │     └─ session/new 应答回会话 id ⇒ _openNew 调 HostMcpServer.rebind(token, 会话 id)（grant 的会话键从空串换成真 id）
  └─ CLI：connectMcpServer → initialize → tools/list → 工具进 agent.tools

会话结束 / 切换 / dispose
  └─ _teardown()（thincoder_kernel.dart:368-398）→ HostMcpServer.revoke(token)
```

监听器**活到进程退出**（D7）。**不设应用退出钩子**：进程退出由 OS 回收本机 socket（无持久状态要清）；`shutdown()` 只用于单元测试收尾（⑰），不接应用生命周期。懒启动触发者 = 上面 `prepare()` 的首次过门（`ThincoderKernel` 调 `HostMcpServer.ensure()`，不新增调用档）。

**grant 的会话键**：`session/new` 的 `mcpServers` 在会话有 id 之前发出 ⇒ grant 初值 `sessionId` 为空串（`thincoder_kernel.dart:297`）；应答带回会话 id 后，`_openNew` 用 `HostMcpServer.rebind(token, sessionId)` 回填
（`thincoder_kernel.dart:394-399`；`host_mcp_server.dart:93-100`）。宿主工具调用的 `HostToolCall.sessionId` 因此是真实会话 id；取消表以 `(sessionId, requestId)` 为键（`host_tools.dart:208`），两个新会话的同号请求不再互相取消。
`session/load` / `session/resume` 发出时 id 已知，不需要回填。

### 5.2 会话期的状态

| 状态 | 工具是否可见 | 调用结果 |
|---|---|---|
| 浏览器已连接 + 开关开 | 是（27 个；`browser_screenshot` 除外） | 正常 |
| 浏览器未连接（会话建立时） | 否（不发 `mcpServers`） | 不可调用 |
| 浏览器未连接（会话建立后断开） | 是（CLI 装配期固定） | `isError` + `No browser is connected: …`（既有文案自带指引，`browser_tools.dart:335-338`） |
| 开关关（会话建立时） | 否（不发） | 不可调用 |
| 开关关（会话建立后） | 是 | `isError` + `BaoCode's browser tools are off (Settings → Browser).` |
| 扩展协议不兼容 | 是 | `isError` + 既有文案（老扩展 / 新内核两种，`browser_tools.dart:325-334`） |
| 令牌已撤（会话已关） | — | `401` |

### 5.3 失效与回收

- 开关关 ⇒ `BrowserTools.unregister()` 把工具移出注册表（`browser_tools.dart:82-89`）⇒ 暴露组内无已注册工具（`anyIn` 为假）⇒ 新会话不发 `mcpServers`；旧会话调用走 §5.2 的明确拒绝。
- **监听器不随开关关闭**：URL 已被 CLI 进程持有；换端口会让那一侧的 MCP 客户端永久失联（客户端只在传输死亡时按同 URL 重连，`thincoder-core/mcp.mjs:111-134`）。回收面 = 组移出暴露集 + 调用拒绝 + 不再发新令牌；网络面本身只剩一个已认证的空壳（无任何可执行工具）。
- 令牌随会话撤（`_teardown`），撤后该 token 的请求一律 `401`。

---

## 6. 能力协商与兼容矩阵

| 组合 | 表现 |
|---|---|
| **新 baocode + 新 CLI**（宣告 `mcpCapabilities.http`） | 工具可见、免审、卡片与 Claude 同形；调用落到同一 `BrowserTools` 实现 |
| **新 baocode + 旧 CLI**（无该键；含 `thincoder.path` 指向旧版） | 我方不发 `mcpServers` ⇒ 会话正常、无工具、无报错、终端无 warn（A4） |
| **新 baocode + 旧 CLI（老代码收非空）** | 即便收到也只 warn 并忽略（`handlers-session.mjs:266-268`）——我方根本不发，这一段不会触发 |
| **baocode 有通道能力但宿主无工具**（浏览器未连 / 开关关） | 不发 ⇒ 无工具（与 Claude 面 `HostTools.servers` 同规则，`lib/host_tools/host_tools.dart`） |
| **Claude 会话** | 零变化：SDK MCP 路径照旧（`claude_code_kernel.dart:512-516`、`:550-554`、`:1683-1698`） |
| **浏览器扩展** | 零变化：协议号、消息面、分组、白名单都不动 |
| **多桌面实例** | 各自一个端口、各自令牌；浏览器只认一个（既有 `otherApp` 逻辑，`browser_tools.dart:320-324`） |

**版本门**：不加。能力按 `mcpCapabilities` 键在场判定（与既有 E3 口径一致）。

---

## 7. 受影响文件清单

### 7.1 本仓（baocode）

行数 = 编制日只读实测（换行数）；增量 = 设计预算 → 实施实测（实测 = 2026-10-18 工作树，换行数）。

| # | 坐标 | 改动 | 增量（预算 → 实测） |
|---|---|---|---|
| ① | `lib/host_tools/host_tools.dart`（新；迁自 `lib/kernel/claude_code/claude_sdk_tools.dart` 229 行） | 类型正名 `HostTool` / `HostToolCall` / `HostTools`；加 `group`；加 `byGroup` / `anyIn` / `lookup`；`handle` 语义零改 | ≤ +35（⇒ ≤264）；实测 +34（⇒ 263；含 `picturesOnly` / `named()`） |
| ①′ | `lib/kernel/claude_code/claude_sdk_tools.dart`（229） | **删除**（全部内容迁入 ①；Claude 面改经 `HostTools`，引用点见 ⑫ / ⑯） | 229 ⇒ 0 |
| ② | `lib/host_tools/host_mcp_server.dart`（新） | 环回监听、令牌发放 / 撤销、JSON-RPC 分发（复用 `HostTools.handle`）、组过滤、图片折文本、错误映射、1 MiB 上限 | ~+260；实测 328 |
| ③ | `lib/browser/browser_tools.dart`（675） | 注册面类型名（4 处 `ClaudeSdkTools` 调用 + 6 处 `ClaudeSdkTool`，机械）；注册带 `group: 'browser'`；入口工具（tabs / open / navigate / evaluate / act）description 补一句适用规则（D9）；透传 `picturesOnly`（`browser_tools.dart:112`；标记在 ④） | ≤ +15（⇒ ≤690）；实测 +14（⇒ 689） |
| ④ | `lib/browser/browser_actions.dart`（625） | 类型名（7 处，机械）；`browser_screenshot` 标 `picturesOnly: true`（`browser_actions.dart:105`，MCP 面不出，§12-1） | 预算净 0；实测 +1（⇒ 626） |
| ⑤ | `lib/browser/browser_debug_tools.dart`（1785） | 类型名（7 处，机械） | 净 0 |
| ⑥ | `lib/browser/browser_history.dart`（787） | 类型名（1 处） | 净 0 |
| ⑦ | `lib/browser/browser_inspect.dart`（1168） | 类型名（3 处） | 净 0 |
| ⑧ | `lib/browser/browser_intercept.dart`（476） | 类型名（1 处） | 净 0 |
| ⑨ | `lib/browser/browser_sources.dart`（1565） | 类型名（3 处） | 净 0 |
| ⑩ | `lib/browser/browser_watch.dart`（615） | 类型名（1 处） | 净 0 |
| ⑪ | `lib/images/image_tools.dart`（599） | 类型名（3 处，机械）+ `group: 'images'` | +2；实测 +1（⇒ 600） |
| ⑫ | `lib/kernel/claude_code/claude_code_kernel.dart`（3337） | 类型名（3 处引用，机械） | 净 0 |
| ⑬ | `lib/kernel/claude_code/claude_code_translator.dart`（1945） | 类型名（1 处） | 净 0 |
| ⑭ | `lib/kernel/thincoder/thincoder_kernel.dart`（1156） | `_handshake` 记 `mcpCapabilities.http`；`_openNew` / `_pickUp` 带 `cwd` + `mcpServers`；`_teardown` 撤令牌 | ≤ +40（⇒ ≤1196）；实测 +39（⇒ 1195） |
| ⑮ | `lib/kernel/thincoder/thincoder_events.dart`（784） | `_tool()` 加宿主工具名映射（kind / summary 回注册表） | ≤ +14（⇒ ≤798）；实测 +14（⇒ 798），其后他批 +1 ⇒ 799 |
| ⑯ | `test/host_tools/host_tools_test.dart`（迁自 `test/kernel/claude_sdk_tools_test.dart` 157 行） | 类型名（机械）+ T16（Claude 面零变化断言）+ 分组 API 用例；13 例 | 157 ⇒ 315（+158） |
| ⑰ | `test/host_tools/host_mcp_server_test.dart`（新） | T1–T10、T10②（取消转交）、T17、T18、T19；14 例 | ~+240；实测 352 |
| ⑱ | `test/kernel/thincoder_kernel_test.dart`（2629） | T11–T15；既有 `session/load` / `session/resume` 用例补 `cwd`、`session/new` 改为「不含 `mcpServers` 键」 | ≤ +140；实测 +211（⇒ 2840），其后他批 +6 ⇒ 2846 |
| ⑲ | `docs/design/thincoder-adapter.md`（2208） | §5.2 改动点清单补本批两档（⑭ / ⑮）+ 体量立场随本批读数；能力映射面补 ACP `mcpServers` 用法一行 | 文档；净 0 代码 |
| ⑳ | `docs/requirements/thincoder-adapter.md`（216） | §2.2 ACP 面用法补 `mcpServers` + 信任位；B1 例外（本批）状态句按 `:173` 口径登记；E5 的 §5 能力映射表为单一维护点，随本批补一行 | 文档；**主 agent 笔** |
| ㉑ | `lib/kernel/thincoder/thincoder_mock.dart`（632） | 测试对端的 `httpMcp` 开关（清单外，已批准） | ≤ +10（`httpMcp` 实测 +5） |

**生命周期接缝**：`HostMcpServer` 的懒绑定触发者 = `ThincoderKernel.prepare()` 首次过门时（§5.1；落在 ⑭ 内，不新增调用档）；关闭不设应用生命周期钩子——进程退出由 OS 回收 socket，`shutdown()` 只供单元测试收尾（⑰）。

**净增**：预算产品码 ≤ +366（①＋②＋③＋⑪＋⑭＋⑮）、测试 ≤ +400；实测产品码 +431、测试 +721（产品码含清单外已批准的 ④ +1，㉑ 未计；超出全部在测试档，见 §16）。机械改名净 0（⑤–⑩、⑫、⑬ 实测同基线）。

**体量立场**：

- `thincoder_kernel.dart`（1156，>800 名单）：本批 = 行级接线（能力位 + 三处请求 + 撤令牌）；体量与拆分按 `docs/design/thincoder-adapter.md` §18.4 / §19.4 的既有缝计划执行，触发条件不变。
- `thincoder_events.dart` 784 行（<800）：实施后 798（恰在预算上界），其后他批 +1 ⇒ 现 799，仍在线下；下一触碰先看余量，越线 ⇒ 先停，改按结构级改动报。
- `test/kernel/thincoder_kernel_test.dart` 2629 行在 >800 名单：只加用例；实测 +211（⇒ 2840，其后他批 +6 ⇒ 2846），超预算 +140 属估算偏差（估算非上界），缝候选沿用 `docs/design/thincoder-adapter.md` §15.4 的四组拆法。
- **净 0 / 机械改名档（⑤–⑩、⑫、⑬、⑯ 的改名部分）**：只替换类型名，行数与结构不变 ⇒ 不构成结构级触碰、不新增拆分档位；④ = 改名 + `picturesOnly: true`（+1）；⑫ / ⑬ 的 >800 状态不由本批处置。
- 新增两档（①②）均 <500 行（实测 263 / 328）；⑤–⑩ 的行数不上移。

### 7.2 thincoder 仓（out-of-repo 轮执行；该仓自己的批次档 + 单元测试随档）

| # | 坐标 | 改动 | 增量（估算） |
|---|---|---|---|
| ① | `thincoder-cli/src/acp/mcp-forward.mjs`（新） | ACP `mcpServers` 条目 → 核 config：`headers` / `env` 数组 → 对象、`_meta["baocode.dev/trusted"]` → `trusted`、形状校验与日志 | ~+70 |
| ② | `thincoder-cli/src/acp/handlers-session.mjs`（429） | `session/new` 读 `mcpServers` 传给 `createSession`；删「M2 scope」忽略日志 | +20 |
| ③ | `thincoder-cli/src/acp/handlers-slots.mjs`（225） | `session/load` / `session/resume` 同带 | +8 |
| ④ | `thincoder-cli/src/acp.mjs`（160） | `defaultCreateSession` 透传 `mcpServers` | +4 |
| ⑤ | `thincoder-cli/src/cli/make-agent.mjs`（140） | `assembleAgent({mcpServers})` 并入 `finalizeTools` 的服务器表（config 同名优先） | +12 |
| ⑥ | `thincoder-cli/src/acp/client-caps.mjs`（87） | `agentCapabilities` 加 `mcpCapabilities:{http:true,sse:true}` | +1 |
| ⑦ | `thincoder-core/mcp.mjs`（306） | `buildTools` 带 `permissionExempt: config.trusted === true` | +2 |
| ⑧ | `thincoder-core/agent/dispatch.mjs`（274） | 免审短路条件加 `|| tool.permissionExempt` | +2 |
| ⑨ | `thincoder/docs/cli/design/ACP-CLIENT.md`（818） | §2.1 行、转发面一节、§12 信任位、G7 关闭 | ~+55 |
| ⑩ | `thincoder/docs/batches/2026-10-18-…`（新）+ 同名 `.test.mjs` | 该仓惯例：批次档 + 单元测试 | 新增 |

**边界与 B1 例外**：以上由父侧另起 out-of-repo 轮，在 thincoder 仓写它自己的档与测试；本仓只出设计，不写外仓文件。本批外仓面属 `docs/requirements/thincoder-adapter.md:173` 的 B1 例外（接口面必要且最小的改动、保持上游可合并）；准入前提 = 用户明示（批 8 的 `docs/batches/thincoder-suspension.md:170` 同形），裁定原话随本批审批回写需求档 B1 状态句（主 agent 笔，见 ⑳）。

---

## 8. 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | 通道 = ACP 标准 `mcpServers` + 环回 HTTP MCP server | §3；规格逐字允许、上游已登记 M2 ⇒ 可合并 |
| D2 | 注册面正名 `HostTools` / `HostTool` / `HostToolCall`（文件迁 `lib/host_tools/`） | 同一注册表服务两个内核，旧名只说了一半；机械改名、零行为变化。**提交拆分**：改名先以独立提交（或独立 diff）落地，功能接线随后——评审面不被改名噪声稀释、上游合并可辨认（E2）；不另起批次；改名提交零行为变化，可单独复核 |
| D3 | 加 `group`，MCP 面按组暴露 | 注册表已有浏览器 / 图片两组；本批只开浏览器（B1），后续工具一行扩 |
| D4 | 能力位门：`mcpCapabilities.http == true` 且暴露组内有已注册工具（`anyIn`）才发 `mcpServers` | ACP 规格要求；旧 CLI 零感知（F4）；不发则不触发 CLI 的 warn 日志；门形统一见 §4.2 |
| D5 | 宿主工具免审（信任标 → `permissionExempt`） | 与 Claude 面同权；主防线是共享分组；信任锚 = 提交请求的客户端。**上游接受风险**：信任位是第二个上游面（非标准扩展），被判拒 ⇒ 回落逐调用审批（§12-11）。被否：逐调用审批（摩擦大、与 Claude 分叉）；`readonly:true`（假契约 + 流进只读子代） |
| D6 | 每会话一枚 32 字节随机令牌，经 ACP 请求递送 | 不落盘、不进 URL、不进环境变量（不出现在日志与进程参数里）；`_teardown` 即撤 |
| D7 | 监听器活到进程退出，不随开关关闭 | URL 已被 CLI 进程持有；换端口 = 该会话永久失联（客户端按同 URL 重连）。回收由「组移出 + 调用拒绝 + 不发新令牌」完成 |
| D8 | 图片：thincoder 面不出 `browser_screenshot`；混合答案里的 image 块折一行注记 | thincoder 客户端把 image 块 `JSON.stringify`（`mcp.mjs:192-199`）⇒ 送到模型是 base64 噪声；B1 明确图片不在本批 |
| D9 | 策略文本：`instructions` 照发；thincoder 面在入口工具 description 补一句 | thincoder 不读 `instructions`（`mcp.mjs:207-231` 只取 tools）；改其系统提示管线越 B4。判定条件见 §12-2 |
| D10 | 工具卡按注册表还原 kind / summary | 与 Claude 面同形；不改 CLI 的 `inferToolKind`（不属宿主工具的事） |
| D11 | 不加 `AgentKernel` 能力接口 | 能力接口是「UI 要显示的能力」；宿主工具投递是适配器内部管线（Claude 面同样没有这类接口）。加了只会多一层无人消费的契约 |

---

## 9. 验收对照（回指需求档 §5）

| 条目 | 本档落点 | 判据 |
|---|---|---|
| **A1** thincoder 全链路 | §4.2–§4.4、§5.1 | T11 + 走查 2–4：工具表含 27 个 `baocode_browser_*`；一次 `browser_open` + `browser_click` / `browser_type` 生效，侧栏跟随（`BrowserTools.lastTab` 既有路径） |
| **A2** 边界 | §4.5、§5.2、§12-5 | 走查 3（只见黄色分组）+ T8（组未暴露 ⇒ 明确拒绝）+ 走查 5（开关关）+ 走查 7（扩展断开 ⇒ 既有文案） |
| **A3** Claude 回归 | §4.4、§6、§7.1-⑯ | T16（`HostTools.handle` 的 initialize / tools/list / tools/call / 取消与改名前逐字段相同；`called('mcp__baocode__browser_open')` 命中）+ 走查 6 |
| **A4** 旧 CLI | §4.2 门、§6 | T12（mock 不宣告能力 ⇒ `session/new` 不带 `mcpServers`，会话正常）+ 走查 6 |
| **A5** 机检 | §10、§11 | T1–T15、T17、T18、T19 全绿（T16 归 A3）；`test/fixtures/thincoder/` 不改 |

---

## 10. 用例表（正常 / 边界 / 错误）

**宿主 server**（`test/host_tools/host_mcp_server_test.dart`；真 loopback 绑定 + 伪工具，不碰浏览器）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 鉴权 | 无 `Authorization` / 错令牌 / `GET /mcp` / `/other` | `401` / `401` / `405` / `404` |
| T2 | 握手 | `initialize{protocolVersion:"2024-11-05"}` | 同版本回显；`capabilities.tools` 在；`serverInfo.name == "baocode"`；`instructions` 含组说明 |
| T3 | 工具清单 | 注册伪工具（组 `browser`）+ 伪图片工具（组 `images`） | 只列 `browser` 组；名字与注册表一致；图片组不出现；`browser_screenshot` 不在 |
| T4 | 一次调用 | `tools/call{name, arguments}` | `content[{type:'text',text:<原样>}]`；无 `isError` |
| T5 | 工具失败 | 伪工具抛 `BrowserError('…')` | `isError:true`，文本 = 错误文句（不静默成功） |
| T6 | 未知工具 | `name:"nope"` | `isError:true`，文本 `No tool nope.` |
| T7 | 图片块 | 伪工具回 `[text, claudeSdkImage(…)]` | 响应只含 text + 一行注记，无 `image` 块 |
| T8 | 组关闭 | 暴露组置空后 `tools/list` + `tools/call` | `tools: []`；调用 `isError:true` + 「browser tools are off」 |
| T9 | 令牌撤销 | `revoke(token)` 后同令牌请求 | `401` |
| T10 | 协议错误 | 坏 JSON / 未知方法 | `-32700` / `-32601`（HTTP 200） |
| T17 | 请求体上界 | 超过 1 MiB 的请求体 | `413`（§4.3） |
| T18 | 心跳 | `ping{}` | `200` + `{}` |
| T19 | grant 回填 | `issue('', '/project')` 后 `rebind(token, 's2')`；用该 token 调工具 | 工具读到的 `HostToolCall.sessionId == 's2'`（`host_mcp_server_test.dart` 的 T19） |

**内核接线**（`test/kernel/thincoder_kernel_test.dart`；`ThincoderMock` 对端）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T11 | 新 CLI 全链 | mock `initialize` 回 `mcpCapabilities.http:true`；注册伪浏览器工具；`session/new` / `load` / `resume` 各走一次 | 三处请求的 `params.mcpServers` 恰一项且字段相同：`type:"http"`、`name:"baocode"`、`url` 指向存量监听（端口 = 实际绑定）、`headers[0] = Authorization: Bearer …`、`_meta["baocode.dev/trusted"] == true` |
| T12 | 旧 CLI 降级 | mock 的 `initialize` 不回 `mcpCapabilities` | `session/new` 不带 `mcpServers`；零错误、健康 ready、后续 prompt 正常 |
| T13 | 无工具 | 不注册任何工具（能力位真） | 不带 `mcpServers` |
| T14 | 撤令牌 | 建会话 → `release()` 触发 `_teardown` | 该会话令牌撤销（以 `HostMcpServer` 的撤销计数断言）；之后用旧令牌请求 ⇒ `401` |
| T15 | 工具卡 | push `tool_call{title:"baocode_browser_click", kind:"other", rawInput:{…}}` | 项为 `ToolCallItem(kind: ToolKind.browser)`，`target` = `browserStepSummary` 的输入行；非宿主工具仍按 `other`（零回归） |

**Claude 面回归**（`test/host_tools/host_tools_test.dart`；迁自旧档，13 例含 T16）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T16 | 既有语义零变 | `initialize` / `tools/list` / `tools/call` / `notifications/cancelled` / `called("mcp__baocode__browser_open")` | 与改名前逐字段相同；`tools/list` 仍列**全部**工具（不按组过滤） |

---

## 11. 测试策略

- **单元测试**（变更实施者写、跑、留一行读数）：上表 T1–T19。宿主 server 用真 loopback 绑定 + 伪工具（`BrowserBridge` 的测试先例 `test/browser/browser_bridge_test.dart` 同型），不依赖浏览器；内核接线用 `ThincoderMock`（`lib/kernel/thincoder/thincoder_mock.dart`），零真实进程。
- **固件**：`test/fixtures/thincoder/` 不改——本批不改任何 `session/update` 形状（工具卡仍是既有 `tool_call` / `tool_call_update`）。
- **不新增集成测试**：通道的业务观察点（工具可见 / 可调用 / 侧栏跟随）由走查覆盖；本仓集成面未受影响。
- **走查**（A 段交付时执行）：§15。

---

## 12. 边界（本批不做）与登记（判定条件）

1. **图片内容（B1）**：thincoder 面不出 `browser_screenshot`；混合答案里的 image 块折一行注记。判定条件：thincoder 的 MCP 客户端能把 image 块送到模型（`mcp.mjs:192-199` 的 `extractMcpText` 改）⇒ 去掉排除与折行两处。
2. **策略文本的单一来源（D9）**：`instructions` 只对读它的客户端生效；thincoder 面靠入口工具 description 的那一句。判定条件：CLI 读 `initialize.instructions` ⇒ 删 description 里的那一句（来源回到 `instructions`，一处）。
3. **取消不传到宿主（§4.6）**：回合取消后，在飞的浏览器动作跑完、结果丢弃。判定条件：出现 >30 s 的宿主工具动作，或走查见「取消后浏览器还在动」被用户视为问题 ⇒ 客户端补发 `notifications/cancelled`（服务端已实现）。
4. **单次调用 120 s 上界**：客户端硬编码（`mcp/helpers.mjs:6`）。判定条件：走查见「动作已完成却报 timeout」⇒ 拆小动作（工具面）或与上游讨论放宽（外仓）。
5. **中途开关 / 断连不改模型工具表**：CLI 在装配期固定工具表（与 Claude 面同形）；调用被明确拒绝，不假装可用。判定条件：产品要求「关了立刻消失」⇒ 接 `notifications/tools/list_changed`（客户端需支持）。
6. **监听器不随开关关闭（D7）**：见 §5.3。判定条件：安全评审要求关端口 ⇒ 关闭监听 + 撤所有令牌（代价：该会话工具调用变网络错误，需重建会话）。
7. **两个浏览器工具并存**：thincoder 自带 `browser`（它自己的自动化浏览器，`thincoder-core/tools/browser.mjs:132`）；宿主面是 `baocode_browser_*`（用户的真浏览器、只碰共享分组）。描述里写明「the user's browser」。判定条件：走查发现模型系统性选错 ⇒ 加强描述措辞（本文已写），或与 thincoder 讨论改名（外仓）。
8. **本机网络面**：只有 `127.0.0.1` + `Authorization` 一道门；不发 CORS 头（浏览器页面即便发起预检也拿不到响应）；无未认证端点。判定条件：出现「本机端口被非本机程序读取」的证据 ⇒ 加令牌轮换（短 TTL）或改用 Unix socket（Windows 无此路，`BrowserBridge` 已因同因走 loopback，`browser_bridge.dart:69-74`）。
9. **`session/new` 的阻塞预算**：MCP 连接在 CLI 装配期完成（握手 30 s 上限，`helpers.mjs:5`）；宿主 server 本地即时。判定条件：走查见会话创建明显变慢 ⇒ 改惰性连接（工具表先给、后台连）。
10. **多桌面实例**：各自端口、各自令牌，互不可见；浏览器只认一个实例（既有 `otherApp` 逻辑）。
11. **信任位的上游接受风险（D5）**：`_meta["baocode.dev/trusted"]` → `permissionExempt` 是 thincoder 侧的非标准扩展面（第二个上游面）。判定条件：上游拒收该位（评审 / 合并被拒）⇒ 回落逐调用审批（`dispatch.mjs:177` 的短路条件不扩；浏览器工具每次弹审批卡），信任位整条撤除，其余不变。
13. **`'browser'` 字面量（非阻塞）**：`host_mcp_server.dart:253`（`tool.group != 'browser'`）与 `:259`（`_given[name] == 'browser'`）用字面量判组，与 `exposedGroups` 常量（`:38`）各自成立；今天暴露组恒为 `{'browser'}`，无行为差异。判定条件：暴露组增加第二组或改名 ⇒ 两处改读 `exposedGroups`。
14. **`initialize.instructions` 取全体特性文本（非阻塞）**：`host_tools.dart:179-180` 把 `_instructions` 全表（按特性登记，`instruct` `:136-138`）拼进 `instructions`，不按 `exposedGroups` 过滤；今天只有浏览器特性登记文本，MCP 面读数无差异。判定条件：第二个特性开始 `instruct`（图片 / IDE / 终端）⇒ 按 `exposedGroups` 过滤。

**未决项**：无（以上每条都给判定条件）。

---

## 13. UI / 交互决定（全部落地，无 open）

- **零新界面、零新设置项、零新 l10n 键**：通道对用户不可见。
- 浏览器步骤卡：thincoder 会话里显示为**与 Claude 会话同形的浏览器步骤卡**（kind + summary 来自同一注册表，D10）；侧栏跟随、登录态、共享分组行为都走既有 `BrowserTools` 路径。
- **无审批卡**：宿主工具免审（D5）。若用户关掉 `browser.enabled`，模型调用得到的是明确拒绝文本（不是弹窗）。
- 设置 → 浏览器：文案与开关行为不变。
- 失败文案复用既有句子（未连接 / 扩展过旧 / 另一实例占用），新增一句「browser tools are off」。

---

## 14. 回滚

- **一行回滚（关通道）**：`HostMcpServer.exposedGroups` 置空 ⇒ `anyIn` 恒假 ⇒ 任何内核都不再收到 `mcpServers`，工具不可见、零报错；其余代码照旧。
- **整批回滚**：`git revert` 本批提交。无数据迁移、无配置迁移、无扩展协议变化、无持久状态（令牌只在内存），回滚后下一次启动即旧行为。
- **thincoder 侧**：转发面与 `permissionExempt` 都是**被动**的（只在客户端发 `mcpServers` / 打信任标时生效）；单独 revert 该仓提交 ⇒ 回到「忽略 `mcpServers`」的行为，本仓随之不再发。
- **Claude 路径**：本批对其只做类型改名（D2），回滚即还原文件名与符号。

---

## 15. 真机走查步骤（A 段交付时执行）

**走查前置**：thincoder 外仓批次已落地（含 `mcpServers` 转发与信任位）且 `thincoder.path` 可指向该构建（设置 → 通用）；本仓接线 = §7.1 ⑭⑮。

1. 装带扩展的 Chrome（或 Edge），用「BaoCode」按钮共享两个标签页。
2. 新建 thincoder 会话，发「用浏览器打开 example.com，告诉我标题」⇒ 出现浏览器步骤卡（**无审批弹窗**），浏览器里出现新共享标签页，侧栏跟随，回答里有标题。
3. 再发「列一下你能看到的标签页」⇒ `browser_tabs` 只列黄色分组的那几个（其它标签页不出现）。
4. 点击 / 输入：让它点页面上的一个链接并输入一段字 ⇒ 步骤卡逐条出现，页面随之变化。
5. 设置 → 浏览器 关 ⇒ 新建会话：模型工具表里没有 `baocode_browser_*`；旧会话再让它用浏览器 ⇒ 明确拒绝文案（不是假装成功）。
6. 兼容：把 `thincoder.path` 指到不含本批的旧版 ⇒ 会话正常、无工具、无报错（终端日志也不见 MCP 警告）。再切回 Claude 会话 ⇒ 浏览器工具与审批语义不变（A3）。
7. 断开扩展（关浏览器）⇒ 调用失败并带既有指引文案。
8. 退出应用 ⇒ 监听端口释放（`netstat -ano | findstr <port>` 无残留）；重开无残留令牌（新会话新令牌）。

---

## 16 实施偏差记录（实施后补记，2026-10-18）

三处设计与实现不一致 + 两处体量偏差；机制结论（能力门 / 契约 / 错误映射 / 边界）未变。行号 = 实施后坐标，行数 = 换行数实测（2026-10-18 工作树）。

**16-1 测试档路径** = `test/host_tools/host_tools_test.dart`。原设计 ⑯ 记 `test/kernel/claude_sdk_tools_test.dart`（157 行）；实施把整档迁到 `test/host_tools/`，补 T16 逐字段断言与分组 API 用例，共 13 例，旧档已删。§7.1 ⑯ / §10 已按实订正。

同批源码档迁移：`lib/kernel/claude_code/claude_sdk_tools.dart`（229 行）整档删除、内容迁入 `lib/host_tools/host_tools.dart`（§7.1 ① / ①′）；§2.2 / §3.3 / §4.3 / §4.4 / §6 里指向旧档行号的坐标已改指新档符号。

**16-2 `picturesOnly` 的定义处** = `browser_actions.dart:105`。原设计把它记在 `browser_tools.dart`；实际是 `browser_screenshot` 的注册项上打标（`browser_actions.dart:105`），`BrowserTools.register` 只透传（`browser_tools.dart:112`）。口径不变：MCP 面不出该工具（§4.3 / §12-1）。

**16-3 ⑱ 增量超估算**：预算 ≤ +140，实测 +211（⇒ 2840；其后他批 +6 ⇒ 2846）。超出 = 既有 `session/load` / `session/resume` 用例补 `cwd`、`session/new` 改为「不含 `mcpServers` 键」，加 T11–T15。估算非上界，800 / 500 两档均未破；该档拆缝按 §7.1 体量立场。

**16-4 ⑮ 压线**：784 ⇒ 798（恰在预算上界），其后他批 +1 ⇒ 799；仍 <800，无结构级触碰。
