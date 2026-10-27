# thincoder 内核适配 设计档

> 板块：内核适配（thincoder 桌面接入）· 范围仓：baocode。
> 配对需求档：`docs/requirements/thincoder-adapter.md`（用户已确认，2026-10-16）。
> 分批：**批 1 = 本地内核全链路**（需求档 F1–F7、F10 + 扩展性 E1–E5，本档详写）；批 2 = 远程 SSH（F8）；批 3 = Customize 对接（F9）；**批 4 = 子代理活动可见（F11，§15）**；**批 5 = 子代理内容归属（F12，§16）**；**批 6 = 审批自动档 + 模型清单与思考档位（F13 / F14，§17）**；**批 7 = 工作中发送的消息（F15，§18）**；**批 8 = 回合结束后继续关注后台子代理（F16，§19）**；**批 10 = 编辑器上下文注入 + agent 编辑走 IDE 原生 diff（F17 / F18，§20 / §21）**；**批 11 = 原生图片块 + 用量（F19 / F20，§22 / §23）**；**批 12 = F19 CLI 收口（真机 provider 面 / 槽文件剥离 / 挂起窗残余，§22.9–§22.12）**；**批 14 = 模型切换后置应用（F21，§24）**；**批 15 = 会话治理 A1：重命名 + 回合级文件回退（独立板块档 `session-governance`，本档只留 ACP 方法面指针）**；**批 16 = 交互响应（预热池 + 乐观就绪可见性 + 打点，F22，§25）**；**批 17 = 内置运行时（F23，§26）**；**批 18 = 模型配置面（F24，§27）**；**批 22 = 改名同步 + `/` 命令面对 thincoder 隐藏（F25 / F26，§28）**。
> 先例坐标对照基准：`lib/kernel/claude_code/`（完整适配）· `lib/kernel/codex/`（薄内核）。
> 状态：设计稿 · 2026-10-23 · 本文档中行号 = 编制日快照（实施时按符号定位）。

---

## 1. 模块目标与范围

**一句话**：在 baocode 里新增一个 thincoder 内核——经 `thincoder acp`（stdio NDJSON JSON-RPC）驱动用户终端安装的那套 thincoder，与终端共享配置与会话；新会话默认走 thincoder，Claude Code 保留为可选内核。

**批 1 交付面**：本地内核全链路（F1–F7、F10）+ 扩展性要求（E1–E5，本档即其载体之一）。
**批 1 不做**：远程 SSH 与 Customize 对位的落地细节（只留接口面，见 §13）；需求档 §6 边界 B1–B4 全部沿用。

---

## 2. 做法与理由

### 2.1 接入形态

每个会话对应一个 `thincoder acp` 子进程，进程 cwd = 项目目录（thincoder 单 cwd 模型：`session/new` 的 `cwd` 必须等于进程 cwd，`thincoder-cli/src/acp/handlers-session.mjs:179-181`）。
进程内 stdio 上走 NDJSON JSON-RPC 2.0：我方发请求（`initialize` / `session/*`），收响应与通知（`session/update`），并应答服务端的反向请求（`session/request_permission`、`fs/*`）。

会话身份 = 持久槽位号字符串（`handlers-slots.mjs:42-61`），槽位是"当前 cwd"的（一个项目一份槽库）——这正是"与终端相通"的原生来源：终端建的会话就在同一槽库里。

### 2.2 最近先例对照（对齐 ∥ 偏离及理由）

对齐（照抄形态，不另造）：

| 面 | 先例 | 我们照抄的形 |
|---|---|---|
| 传输抽象 | `claude_code_transport.dart:11-26` | `messages` 流 + `write` + `close` + `exited`；最后一条 = 退出消息 |
| 条件导入 IO/stub | `process_transport.dart:1-3`（`dart.library.io` 分支） | 同形：web 上明示"没有进程可用" |
| 事件源 | `agent_kernel.dart:375-393` `KernelEventSource`（seq + 同步流） | 直接用 |
| 选择项 | `claude_code_kernel.dart:3003-3030` `_Choice` | 同形（选项列表随内核状态读） |
| mock 传输 | `mock_claude_code_transport.dart:11-27`（住 lib，供测试与演示） | 同形 |

偏离（逐条给理由）：

1. **新增 JSON-RPC 连接层**（`thincoder_protocol.dart`）。claude 的 `ControlChannel`（`control_channel.dart`）按 subtype 应答、无 id 配对、不处理"服务端主动发起且要我们回包"的请求；ACP 三样都要 ⇒ 独立一层。codex 无此层（它的协议更简单）。
2. **会话目录是"活连接"而非"读盘"**。claude 的 catalog 读会话文件（`claude_storage_io.dart:33-84`）；thincoder 的 `session/list` 必须有一个在那个 cwd 里活着的进程 ⇒ catalog 起短命进程（见 D4/D5）。
3. **翻译档已按体量触发拆出**（`thincoder_events.dart`）。claude 的 translator 64 KB 是历史体量；thincoder 的 ACP→KernelEvent 翻译随内核起步（先例 = `codex_kernel.dart` 内联翻译），kernel 实测 1168 行越过 >800 行硬顶（体量立场 = §5.2 末段）。
4. **图片走"落盘 + 路径引用"而非协议能力**（需求档 F6；见 D7）。

先例的文档坐标：先例无设计档可引——claude 适配与 codex 薄内核在本仓无设计档 / 批次档（`docs/design/`、`docs/requirements/`、`docs/batches/` 下均无对应档；其形态只由实现与扁平功能档承载，如 `docs/ssh-remote-goal.md:16-17`、`docs/windows.md:26`）；先例批界无从对照，本对照以代码实现为准。

**公开资料调查（survey-evidence）**：ACP v1 schema（`agentclientprotocol.com/protocol/schema`，2026-10-19 取）——image 内容块、`usage_update` 与 `session/set_config_option` 的帧形相关，取用见 §22 / §23 / §24；外仓设计档（`thincoder/docs/**`，声明来源）与先例对照相关，取用见各节 survey 证据；其余断言无公开源相关，以代码实读为准。

---

## 3. 接口契约

### 3.1 架构与分层（`lib/kernel/thincoder/`，E1 单点）

```text
ThincoderKernel（AgentKernel + 四个能力面）
   │  KernelEvent 流（KernelEventSource）
   ├── ThincoderConnection（JSON-RPC：请求/响应配对 · 通知分流 · 反向请求应答）
   │        └── ThincoderTransport（抽象）—— ThincoderProcess（io）∥ ThincoderWebStub ∥ ThincoderMock（测试）
   ├── ThincoderSessionRef（会话 id 组合与拆解：`<cwd>|<slot>`）
   ├── ThincoderCatalog（SessionCatalog：短命连接做 list/delete）
   └── ThincoderLocator（PATH 探测 · 设置项路径 · 版本下限 · 引导文案）

外部只经 AgentKernel 接口交互；宿主接线点见 §5。
```

### 3.2 传输契约（照抄 claude 形）

```dart
abstract interface class ThincoderTransport {
  Stream<Map<String, Object?>> get messages; // 一行一 JSON 对象
  void write(Map<String, Object?> message);
  void close();
  Future<void> get exited;
}
class ThincoderLaunch { final String cwd; final String executable; final Map<String,String> environment; }
```

最后一条消息 = 退出消息（照抄 `ClaudeExit.message` 形）：`{'type': 'transport_exit', 'code': int, 'stderr': String, 'executable': String?}`。

起进程与环境（照抄 `process_transport_io.dart:85-139` 的做法）：`Process.start(executable, ['acp'], workingDirectory: cwd, environment: 登录 shell 环境, includeParentEnvironment: Platform.isWindows, runInShell: <npm shim 需 shell>)`。

子进程环境 = 登录 shell 环境（复用 `ClaudeEnvironment.of()`，`claude_environment.dart:1`）；**不注入** baocode 的 `NetworkProxy` 变量（thincoder 网络面归它自己；见 §14 登记）。

### 3.3 JSON-RPC 连接契约

- 我方请求 id = `"c1"`、`"c2"`…（避开服务端反向请求的 `rpc-N` 形态）。
- `Future<Map<String, Object?>> request(String method, [Map<String, Object?> params, {Duration? timeout}])`：超时抛 `ThincoderRpcError`。
- 入站三分流：响应（有 id、无 method，配对我们发出的）｜通知（有 method、无 id）｜反向请求（有 method、有 id，我们要回包）。
- 错误对象 `ThincoderRpcError { code, message, data? }`；错误码语义 = `transport.mjs:14-20`：`-32600` parse / `-32601` 方法不存在 / `-32602` 参数非法 / `-32603` 内部 / `-32000` 需要凭据。
- 反向请求应答器：`session/request_permission` → 审批流（§4 F4）；`fs/read_text_file` / `fs/write_text_file` → §21.1 的两个 handler（仅内核连接；catalog 不宣告能力位，D73）；其余未知方法 → 立即回 `-32601` 错误（"得体降级"：服务端不会干等它的超时）。
- **未知通知 / 未知 `sessionUpdate` 变体 / 已知通知里的未知字段**：忽略；协商与未知方法留痕走 `appEvent('thincoder', …)`（`lib/platform/event_log.dart:84`）（E4）。

### 3.4 ACP 线形（本适配用到的全部；逐条与 thincoder 源对位）

**请求（我方 → 服务端）**

| 方法 | params | 结果 / 通知 |
|---|---|---|
| `initialize` | `{protocolVersion: 1, clientCapabilities}`——内核连接 = `{fs: {readTextFile: true, writeTextFile: true}}`（§21.2），catalog 连接 = `{}`（D73） | `{protocolVersion, agentCapabilities, authMethods, agentInfo{name,version}}`（`client-caps.mjs:46-64`） |
| `session/new` | `{cwd, mcpServers（过门才带）}` | `{sessionId, configOptions}`（`handlers-session.mjs:163-243`） |
| `session/load` | `{sessionId, cwd, mcpServers（过门才带）}` | `{configOptions}`；**之前**逐条重放历史通知（`handlers-slots.mjs:64-138`） |
| `session/resume` | `{sessionId, cwd, mcpServers（过门才带）}` | `{configOptions}`；不重放（`handlers-slots.mjs:140-197`） |
| `session/list` | `{}` | `{sessions: [{sessionId, cwd, updatedAt?, title?}]}`（`handlers-slots.mjs:42-61`） |
| `session/delete` | `{sessionId}` | `{}`（`handlers-slots.mjs:199-223`） |
| `session/prompt` | `{sessionId, prompt: [{type:'text', text}], turnId?}`——原生路可含 image 块（§22：`{type:'image', mimeType, data}`；单 text 块 = 回退路）；`turnId?` = 回合标识（`session-governance` §3.1） | `{stopReason: 'end_turn' \| 'cancelled'}`（`handlers-session.mjs:245-263`） |
| `session/cancel` | `{sessionId}` | `{}` |
| `session/close` | `{sessionId}` | `{}`（未知会话也回 `{}`） |
| `session/set_mode` | `{sessionId, mode: 'plan'\|'normal'}` | `{}` + 通知 `current_mode_update{currentModeId}`（`:321-341`） |
| `session/set_config_option` | `{sessionId, configId, value}` | `{configOptions}` + 通知 `config_option_update{configOptions}`（`:292-319`） |
| `session/set_title` · `session/revert`（扩展方法） | 形状 / 错误面 / 队列归属见 `docs/design/session-governance.md` §3.1 | 同上（本档只留指针，D2） |

**通知（服务端 → 我方）：`session/update{ sessionId, update: { sessionUpdate, … } }`**

| sessionUpdate | 载荷 | 来源 |
|---|---|---|
| `agent_message_chunk` | `{content: {type:'text', text}}` | `bridge.mjs:236` |
| `agent_thought_chunk` | 同上 | `bridge.mjs:243` |
| `tool_call` | `{toolCallId, title, kind, status:'in_progress', rawInput, content}` | `bridge.mjs:275-282` |
| `tool_call_update` | `{toolCallId, status:'completed'\|'failed', content}`（REPLACE） | `bridge.mjs:287-291` |
| `usage_update` | `{used, size}` | `bridge.mjs:249-252` |
| `config_option_update` | `{configOptions: […]}`（全量数组） | `handlers-session.mjs:314-317` |
| `current_mode_update` | `{currentModeId}` | `:336-339` |
| `user_message_chunk` | `{content: {…}}`（仅 load 重放） | `bridge.mjs:413` |
| `session_info_update` | `_meta["thincoder.dev/subagent"]`（子代理信号；翻译 = §15.2）∥ `_meta["thincoder.dev/turn"]`（回合边界 / 窗开关；翻译 = §19.2） | `bridge.mjs:232` ∥ `acp/suspension.mjs`（批 8 新增） |

**反向请求（服务端 → 我方，须回包）**

| 方法 | params | 我方应答 |
|---|---|---|
| `session/request_permission` | `{sessionId, options:[{optionId,name,kind}], toolCall{toolCallId,title,content[]}}`（选项序 = approve_once / approve_always / reject，`bridge.mjs:49-54`） | `{outcome:{outcome:'selected', optionId}}` ∥ `{outcome:{outcome:'cancelled'}}` |
| `fs/read_text_file` | `{sessionId, path}` | `{content}`（仅内核连接；错误码 = §21.2） |
| `fs/write_text_file` | `{sessionId, path, content}` | `{}`（同上） |
| 其它未知方法 | — | `-32601` 错误（不挂） |

（服务端反向请求自带超时：传输层默认 60s（`acp/transport.mjs:42`），按方法覆写——审批 5 分钟（`bridge.mjs:319`）、`fs/*` 30 秒（`bridge.mjs:143`/`:152`）；超时或失败按拒绝处理——我们不回包也不会卡死它。）

（我方请求超时口径：`session/prompt` **不受连接缺省 60s 约束**——prompt 的响应在回合结束才到达（`bridge.mjs:23-24`）、回合时长无上界，任何有限上界都会在长回合触发「got no answer」误报与错标 interrupted。

实现形态 = `session/prompt` 调用显式不设超时（`ThincoderConnection.request` 区分「缺省（60s）」与「显式不设超时」），其余请求照旧。）

（`session/prompt` 的兜底 = 取消 / 进程健康（两者均已实现）：`session/cancel` ⇒ 服务端以 `stopReason:'cancelled'` 收束在飞请求（F3）；进程死 / 传输结束 ⇒ 在飞请求随连接收束、回合 `TurnEnded(interrupted: true)`（§3.6）。被否「远大于回合尺度的上界」：只为悬挂态加猜测性截断——上述两条兜底已给确定性出口。）

### 3.5 会话生命周期（状态机）

```text
无会话 ──prepare()/send()──▶ 起进程 → initialize → 建会话：
    · 没有续接记录            → session/new          （槽号 = 新认领）
    · 有续接记录、本内核未载入 → session/load         （重放历史；sessionId = 记录 id 原文）
    · 本内核已载入过（重连）   → session/resume       （不重放；避免历史重复进 transcript）
活跃 ──release()──▶ 无在飞回合且无活子代理时 session/close（best effort）+ 进程退出；否则延后到收尾那一刻（D64，§19.2）；槽号留在内存以备 resume
活跃 ──dispose()──▶ 同上 + 事件流关闭 + stopped 完成（进程真退出）
```

- 起会话时机 = `prepare()`（会话视图挂上时即起，与 claude 同形：`claude_code_kernel.dart:589-594`）。这样 F5 的模型/模式/思考选项在首条消息之前就位。
- 未发过消息的会话**不落槽文件** ⇒ 不会出现在终端 `session/list` 里（`session-slot-scan.mjs:199-217` 只认盘上槽文件）；只占一个槽号认领，`close` 时释放。
- `sessionId` getter = 组合 id `"<cwd>|<slot>"`（见 D5）；续接记录的情况下先取 `resume.id` 原文（同 claude `claude_code_kernel.dart:122`）。
- 同槽并发（终端也开着同一会话）：服务端按设计处理（空闲钉回 / 占用 fork 到新槽，`handlers-slots.mjs:104-126`）——桌面侧零特判；fork 后新槽号无回流通道（`session/load` 回包只有 `{configOptions}`）⇒ 记录 id 不刷新、后续 prompt / cancel / delete 以服务端语义为准（判定条件与验收观察点 = §14-9）。
- `release()` 的 `session/close` = **best effort**：只写不等、随即进程退出（不设有界等待——等待会引入本批无法实测的时序依赖）；认领是否真释放不在此保证（判定条件 = §14-12）。
- 会话已不在（终端删掉该会话）：`session/load` / `session/resume` 收 `-32602`（`gone`）⇒ 忘槽、起新会话（不留启动死结；判定条件 = §14-13）。
- 兜底起的新会话在同一运行内跨 `release()` → `prepare()` 续接：兜底时记「记录槽已忘」标记；此后 `prepare()` 走保留槽路线（`session/resume` 本内核自己的会话，不再重走 `session/load` 死槽）。实现已随末修单落地（净 +9 行；判定条件 = §14-13）。

### 3.6 事件翻译（ACP → KernelEvent）

| ACP | KernelEvent |
|---|---|
| `send()` 起回合（无在飞回合时） | `TurnStarted(turnId)` + `ItemUpserted(turnId, UserMessageItem(text: 实发文本))`；回合在飞时的发送入内核本地队列，到 `_endTurn` 才发（§18） |
| `agent_message_chunk` | 文本项：首块 `ItemUpserted(id, AssistantTextItem(''), streaming: true)`，其后 `TextDelta(id, offset, text)`；项 id = `"t<序号>.<块序号>"` 形态由适配层自定（本层自持 id 空间）。**带 `_meta` 归属标 ⇒ 入该子代理的谈话，不带 ⇒ 本行（主对话）**（§16.2） |
| `agent_thought_chunk` | 思考项：同上，`ThinkingItem(text, tokens: 已收字符数, startedAt)`（tokens 近似先例 = `codex_kernel.dart:296`）；归属标同上（§16.2） |
| `tool_call` | `ItemUpserted(toolCallId, …)`，按 kind 成形（表下）；**带 `_meta` 归属标 ⇒ 入该子代理 children，不带 ⇒ 主对话**（§16.2） |
| `tool_call_update` | 同 id 替换：`completed` → 状态 succeeded（终端项填 output=内容文本）、`failed` → failed；归属标同上（§16.2） |
| `usage_update` | `UsageReported(ContextUsage(window: size, used: used))` |
| `config_option_update` | 更新选择项 + `KernelInfoChanged` |
| `current_mode_update` | 更新模式选择项 + `KernelInfoChanged` |
| `user_message_chunk`（重放） | 用户项（连续块并入一项，遇其它类型封口）；重放帧不止此类——助手文本 / 工具帧同路还原（§16.1 重放面） |
| `session_info_update`（子代理 meta） | 子代理卡片 upsert + `TasksReported` 全量重报（§15.2） |
| `session_info_update`（turn meta） | 自动轮边界：start ⇒ `TurnStarted(unprompted: true)`（用户回合在飞 ⇒ 暂存）；end ⇒ `TurnEnded(interrupted: ok==false)`（暂存位非空 ⇒ 撤暂存、不成轮；`ok` 只认布尔 `false`）；watch ⇒ `_watching`（释放判据，不成事件）（§19.2） |
| 其余 / 未知 | 忽略（留痕见 §3.3） |

`tool_call` 按 ACP `kind` 成形的对照（`title` = 工具名，参数在 `rawInput`）：

| ACP kind | baocode 项 |
|---|---|
| `read` | `ToolCallItem(kind: read, target: 文件名, path: rawInput.path)` |
| `edit` / `delete` / `move` | `ToolCallItem(kind: edit, target: 文件名, path)` |
| `execute` | `TerminalItem(command: rawInput.command, output: '', status: running)` |
| `search` | `ToolCallItem(kind: grep, target: rawInput.pattern 类字段 ?? title)` |
| `fetch` | `ToolCallItem(kind: web, target: title)` |
| 其余 / 未知 | `ToolCallItem(kind: other, label: title, target: title)` |


回合结束：`session/prompt` 的响应到达 ⇒ `TurnEnded(turnId, interrupted: stopReason=='cancelled', worked: 本回合计时)`。
自动轮的边界不走应答：走 §19.2 的回合边界帧（批 8）。
运行中进程死亡 / 传输结束 ⇒ 在飞回合 `TurnEnded(interrupted: true)` + `NoticeItem(NoticeKind.error, …)` + 健康 failed（可重试）。

---

## 4. 能力映射与逐项落地（F1–F7、F10）

### F1 内核接入与默认

- 新增描述符 `id: 'thincoder'`，注册表 `_all = [thincoder, claudeCode]`（`lib/kernel/kernel_registry.dart:29`）⇒ 新会话默认 = 注册表首位（`workspace.dart:239-240`）。
- 原有"上次选的内核"粘性机制保留（`workspace.dart:1040-1042`、`:2194-2196`）：用户显式选过 claude 的新会话仍可继续选 claude。
- 存量档案迁移见 D17 + §5 接线点 ④（不迁移则老用户升级后默认仍是 claude，违背 F1/A1 口径）。

### F2 会话与终端相通

- 目录实现 = `ThincoderCatalog`：`sessionsIn(cwd)` 起短命连接 → `initialize` → `session/list` → `close`；`delete(id)` 同法走 `session/delete`（id 拆出 cwd，见 D5）。
- `projects()` 返回空表（D6）：ACP v1 无跨 cwd 枚举；由宿主既有"逐项目列"路径承接（`_listKept`，`workspace.dart:420-437`）+ 1 处接线（§5 接线点 ⑤）。
- 展示：`title`（可能为空串——旧槽无标题字段）与 `updatedAt`（ISO 8601 字符串）直接进 `SessionRecord`；标题空时沿用宿主"未命名"显示（`workspace.dart:508-510`）。
- 载入/恢复：目录项的打开路径走既有 `KernelContext.resume` → §3.5 的 `session/load`（历史重放填 transcript，`LoadsHistory` 期间为真）。
- 删除：走 `SessionCatalog.delete`（`workspace.dart:2679-2697` 既有调用点）。
- 重命名与回合级文件回退：见 `docs/design/session-governance.md`（D2 单源；本档只留方法面指针）。

### F3 对话全链路

- 发：`send()` → 确保会话 → `session/prompt`（文本块一份；`notes` 以空行分隔附于正文后）。流式中可继续发消息：声明 `QueuesMessages` ⇒ `canQueue` 为真、`canSend` 放开（`chat_session.dart:511` / `:544`）；队列语义见 §18。
- 收：§3.6 翻译；工具卡含"进行中 → 完成/失败"更新（`tool_call` / `tool_call_update` 的 REPLACE 语义）。
- 取消：`cancel()` → `session/cancel`；在飞 `session/prompt` 以 `stopReason:'cancelled'` 收尾 ⇒ `TurnEnded(interrupted: true)`。
- plan 模式：`set_mode` 可切（`SelectsMode`，见 F5）；**计划以对话文本呈现**——不声明 `StartsPlans`，不造计划卡（D8）。理由：thincoder 的 plan 模式产出一段计划文本并要求用户显式批准（`agent-tools/plan.mjs:108` 的提醒语），协议面无计划文件/计划对象；终端同形呈现。

### F4 审批弹窗

- 反向请求 `session/request_permission` → `InteractionRequested(ApprovalRequest)`：
  - `toolName` / `title` = `toolCall.title`（工具名，桥已剥子代理前缀）；
  - `preview` = `TextPreview`（`toolCall.content` 的文本块拼接——含参数 JSON 与危险命令标注）；
  - `alwaysAllowLabel` = 服务端 `approve_always` 选项的 `name`（"Approve for this session"）——**三选项映射**：一次 → `approve_once`；总是（= alwaysAllowLabel 行）→ `approve_always`；拒绝 → `reject`（`interaction_panel.dart:135-176` 固定三行，正好三值）。
- 无应答不卡 UI：面板未被答时 UI 照常；服务端 5 分钟超时按拒绝处理（`bridge.mjs:319`）。
- 内核被 `dispose` 而审批在飞 ⇒ 回 `{outcome:{outcome:'cancelled'}}`（服务端按拒绝，安全优先）。
- 拒绝理由文本（`ApprovalAnswer.message`）无 ACP 通道 ⇒ 不送（§14 登记）。

### F5 模式与模型

- 三个选择面全部**由握手/回包驱动**（E3），显示 = 最近一次回报：
  - 模式：`configOptions.mode`（`handlers-session.mjs:50-51`，值域 normal/plan）→ `SelectsMode`；`select()` → `set_mode`，显示等 `current_mode_update`（不乐观改）。
  - 模型：`configOptions.model`（`:43-47`：`currentValue` = `provider:model`，`options` = 运行期清单投影，批 6 起可多项；§17.3）→ `SelectsModel`；`select()` → `set_config_option('model', value)`，显示等 `config_option_update`。
  - 思考：`configOptions.thinking`（boolean）→ `SelectsEffort`（`ModelSetting.toggle = true`，先例 = `claude_code_kernel.dart:2878-2913` 的 `fast`）；`select()` → `set_config_option('thinking', on/off)`。
    批 6 起若同一回包带 `thinkingLevel`（select）⇒ 同一面改为档位列表（`toggle = false`），`select()` → `set_config_option('thinkingLevel', 档名 \| 'off')`（§17.3-③；无该项时逐字走今天的开关）。
- **模型候选**：批 1 候选 = 上报项（当前一项）。批 6 起 CLI 把运行期清单投影进 `configOptions.model.options[]`（§17.3）⇒ 桌面按既有 `options[]` 机制自动多项可切（E3 钩子点亮，桌面零改动）。
- 会话起点设置：只吃 `KernelContext.settings['mode']`（plan/normal）并在会话建立后应用；**忽略** model / effort / context / permission（宿主这套 settings 是 Claude 形：`workspace.dart:2473-2477` 塞的是 `ModelProviders` 的模型名，喂给 thincoder 会指错模型）——D11。

### F6 图片替代

- 内核**不声明** `AcceptsImages`（ACP 图片能力 false，`client-caps.mjs:55-59`，不虚报）；新增宿主能力面 `AcceptsImageFiles`（§5 接线点 ②）：语义 = "接收图片附件，但以落盘 + 路径引用交给 agent"。
- `send()` 内有图时：逐个写 `<cwd>/.thincoder/tmp/paste-<runId>-<i>.<ext>`（命名与终端同规则：`attachments.mjs:76,92`；runId = `Date.now().toString(36)+随机4位`；ext ∈ png/jpg/gif/webp），正文后附 `[Attached images: <p1> | <p2>]`（终端同款括号形，`setup-reminders.mjs:255`）。
- 阈值同终端口径：单项 ≤ 15 MB、单回合合计 ≤ 30 MB，超阈项弃并在会话内提示（`attachments.mjs:33-36`）。
- 落盘项也随 `UserMessageItem.images` 显示缩略图（图片在内存里，bubble 照常显示）；transcript 文本 = 实发文本（含路径行）——所见即所发。
- 不复制终端句尾的 `use the read_image tool …` 指令（桌面不知模型是否多模态，该指令属 thincoder 自己的提示面）——D7。
- **原生路见 §22（D82–D85）；F6 = 回退路**：握手能力位 `promptCapabilities.image === true` 时 prompt 直接携 image 块、不落盘（§22.1）；本节的落盘 + 路径行 = 旧 CLI / 未声明能力位时的回退形（§22.7-6）。

### F7 检测与引导

- 定位：设置项 `thincoder.path`（settings.json），空则按 PATH 探测（登录 shell 环境）；找到 → 执行；找不到 → 健康 failed，文案含 `npm install -g thincoder` 与 Node ≥24（`thincoder-cli/package.json:19-23` engines）。
- `-32000 authRequired`（`handlers-session.mjs:85-105`）→ 健康 failed，detail = **服务端 message 原文**（已可行动：指向 `~/.thincoder/config.json` 的 `providers[].apiKey` 与 `thincoder acp --login`）+ 我方前置一行"thincoder 未登录"。
- 版本下限：常量 `thincoderVerifiedVersion = '0.12.74'`（编制核对版本 = `thincoder-cli/package.json:3`）；`agentInfo.version` 低于下限 ⇒ 会话内 `NoticeItem(NoticeKind.warning)` 明示 + 设置行标注，**不阻断**（D13）。
- 不声明 `auth.terminal`（本批不做"在终端里执行登录"动作，声明即虚报）；`initialize.authMethods` 因此为 `[]`（`client-caps.mjs:28-37`）。
- 展示面：对话内健康横幅（`health_banner.dart:23-24` 既有机制）+ Settings → General 的 thincoder 行（路径 + 找到与否 + 版本，形同 Claude Code 行 `general_page.dart:357-376`）。

### F10 用量展示

- `usage_update{used,size}` → `UsageReported`；`ReportsContext.contextWindow` 在首个回报之前用 128 000（thincoder 未知模型兜底值，`bridge.mjs:252`；非虚构），此后以回报为准（`chat_session.dart:419-423` 取 transcript 的最近回报）。
- 模型与供应商配置在**会话内只读**（不改会话内投影）；编辑入口 = 设置 → 模型（thincoder）（F24 / §27）——只写 `providers[]` 与顶层 `defaultModel`，其它键逐字不动，密钥明文与 CLI 一致（0600 尽力而为）（B3 收窄后口径）。

**宿主工具通道（`host-tool-channel` 批；非 `AgentKernel` 能力面）**：`initialize` 回包的 `agentCapabilities.mcpCapabilities.http` 为真、且暴露组内有已注册工具时，内核在 `session/new` / `session/load` / `session/resume` 的 `mcpServers` 里带本机环回 MCP server（过门才带该键，不带空数组；线形见 §3.4）。

server 由 `HostMcpServer` 签发（127.0.0.1 系统选端口 + 每会话 Bearer 令牌，不落盘、不进 URL），`_teardown` 撤销；工具免审以 `_meta["baocode.dev/trusted"]` 信任位表达，由 CLI 侧消费（转发与信任位属对端仓轮，不在本档机制面）。需求面 = `docs/requirements/host-tool-channel.md`。

---

## 5. 受影响文件清单（E2）

### 5.1 新增（全列；`lib/kernel/thincoder/` 单点，E1）

| 文件 | 装什么 | 预估 |
|---|---|---|
| `thincoder_kernel.dart` | `ThincoderKernel`：生命周期 + 四个能力面（公开面照旧）；§3.6 翻译拆到 `thincoder_events.dart`（经 `ThincoderSink`） | ~700 行 |
| `thincoder_events.dart` | §3.6 事件翻译：`ThincoderEvents` + `ThincoderSink`（`emit` / `nextSeq` / `emitInfoChanged`）；拆自 kernel（体量立场触发条件已执行） | 413 行（2026-10-16 快照） |
| `thincoder_protocol.dart` | `ThincoderConnection`：JSON-RPC 配对 / 通知分流 / 反向请求应答 / 错误类型 | ~250 行 |
| `thincoder_transport.dart` | `ThincoderTransport` + `ThincoderLaunch` + 退出消息 | ~60 行 |
| `thincoder_process_io.dart` | 真进程：起 `thincoder acp`、逐行解码、退出、注册表 | ~150 行 |
| `thincoder_process_stub.dart` | web：明示无进程（照 `process_transport_stub.dart` 形） | ~15 行 |
| `thincoder_process.dart` | 条件导入包装（照 `process_transport.dart` 形） | ~25 行 |
| `thincoder_catalog.dart` | `ThincoderCatalog`：短命连接 + 串行队列 + list/delete | ~150 行 |
| `thincoder_session_ref.dart` | 会话 id 组合/拆解（`<cwd>|<slot>`，D5） | ~30 行 |
| `thincoder_locator.dart` | `thincoder.path` 解析 · PATH 探测 · 版本比较 · 引导文案常量；另含 `ThincoderStatus{Found,Missing,Failed}` + `thincoderStatus()`（接线 ⑦⑧ 消费） | ~120 行 |
| `thincoder_mock.dart` | 脚本化 ACP 对端（照 `mock_claude_code_transport.dart` 形）+ 固件回放入口 | ~350 行 |

测试（本仓惯例：单元/组件测试在 `test/`，`dart_test.yaml` 打标签；固件放 `test/fixtures/`）：

| 文件 | 覆盖 |
|---|---|
| `test/kernel/thincoder_kernel_test.dart` | 握手 / 会话 / 事件 / 审批 / 取消（mock 对端直驱） |
| `test/kernel/thincoder_catalog_test.dart` | list / delete / id 组合 |
| `test/kernel/thincoder_fixtures_test.dart` | 固件回放（`test/fixtures/thincoder/*.ndjson`） |
| `test/workspace/preferred_kernel_test.dart` | 内核选择的持久化（B 段随批；T13 面）：空档案默认 = 候选首位 · 用户选择跨运行生效 · 无标记旧档不跟随 · 所选内核不在候选内回落首位 |
| `test/flutter_test_config.dart` 的 e2e 标签（可选） | 真 thincoder 冒烟：`-t e2e-thincoder`（默认 skip，照 `dart_test.yaml:1-15` 形） |

### 5.2 修改（最小接线点集，逐点理由）

| # | 坐标 | 改动 | 理由 |
|---|---|---|---|
| ① | `lib/kernel/kernel_registry.dart:29` | `_all = [thincoder, claudeCode]` + 描述符 + import | F1（默认 + 可切换）；该档注释本就写"Another kernel is an adapter and a line here" |
| ② | `lib/kernel/agent_kernel.dart:261` 旁 | 新增 `AcceptsImageFiles` 接口（~10 行 + 文档） | F6：内核不声明 `AcceptsImages`（不虚报），但宿主得把图片交给它 |
| ③ | `lib/chat/chat_session.dart:439` | `acceptsImages` 判定加 `|| _kernel is AcceptsImageFiles` | F6：`send()` 在 `:959` 按此过滤图片、composer 在 `composer.dart:283/292/456` 按此采集——一处改、三处通 |
| ④ | `lib/workspace/workspace.dart:1897-1899`、`:2024` | 存量档案的 `kernel` 值只在"确实由用户选过"时生效：新增 `_kernelChosen` 标记（用户选择发生时置真，随档案写、随档案读） | F1/A1：旧版单内核（`kernel_registry.dart:29`）从未出现过选择器 ⇒ 档案里的 `kernel` 值不可能是用户选择（`chat_session.dart:309` 选择器需 ≥2 内核），不迁移则老用户默认仍是 claude |
| ⑤ | `lib/workspace/workspace.dart:291-326`（`load()` 回路与守卫）· `:422-439`（`_listKept`） | 跳过判据**按内核**：`projects()` 覆盖表 + `_listKept` 收内核子集参数（缺省全量）+ 守卫改「本轮没有触发逐目录列出」才清理（细则 = 「接线点 ⑤ 细则」） | F2：ACP 无跨 cwd 枚举（D6），"逐项目列"是唯一入口；跨内核合并集当判据会漏列——claude 有会话的项目整目录被跳过 ⇒ thincoder 的 `session/list` 永不执行，A3 不成立 |
| ⑥ | `lib/main.dart:122-124` · `:552-559` | `reapThincoderProcesses()` / `stopThincoderProcesses()` 各一行 | 进程收尾：崩溃/强退残留的 `thincoder acp` 不被下次启动清理会占着槽位与进程 |
| ⑦ | `lib/settings/pages/general_page.dart:357-376` | 新增 "thincoder" 设置组：路径输入 + 状态行（找到与否 + 版本） | F7"另设可指路径的设置项"；形同 Claude Code 行 |
| ⑧ | `lib/settings/app_settings.dart:58/95/140` · `lib/main.dart:338` | 透传 `thincoderStatus`（读 `thincoder.path` 的回调同 `main.dart:154-155` 追加一行） | ⑦ 的数据来源，照 `claudeStatus` 形 |
| ⑨ | `lib/kernel/mock/mock_kernels.dart:24-32` | 新增 `MockKernels.thincoder`，**不进 `all`** | 测试直用；`all` 不动（D18） |
| ⑩ | `lib/platform/data_dir.dart:86-87` 注释 | 注册表文件名清单加 `thincoder` | 文档一行；登记表出现新类别 |
| ⑪ | `lib/kernel/thincoder/thincoder_kernel.dart`（本批 1156 → 1195，+39） | 宿主工具通道接线：`_handshake` 记 `mcpCapabilities.http`（`:383`）；`_hostMcpServers()` 门 = `_httpMcp && HostTools.anyIn(exposedGroups)`（`:264`），过门才 `ensure()` + `issue()`（`:266`）；`session/new|load|resume` 带 `mcpServers`（`:356` / `:325`）；`_teardown` 撤令牌（`:405`） | 通道不走 `AgentKernel` 能力接口：内核按握手能力位向 CLI 提供环回 MCP server（宿主设计档 §7.1 ⑭） |
| ⑫ | `lib/kernel/thincoder/thincoder_events.dart`（本批 784 → 798，+14） | 宿主工具卡：`_tool` 的 `default` 分支经 `HostTools.named(title)` 还原 `kind` / `summary`，保留 `tool` / `input`（`:403-410`）；非宿主工具仍为 `other` 卡 | 可见面按注册表还原为宿主工具的既有卡形（宿主设计档 D10 / §7.1 ⑮） |

（`lib/kernel/claude_code/**` 零改动；`thincoder/**` 在本仓零改动——B1；

thincoder 侧的接口例外见 §16.1。）批 4 的改动点见 §15.4（同为最小接线点集）；

批 5 的改动面见 §16.4（本仓测试面 + out-of-repo 档）；批 6 见 §17.4（本仓适配层两面 + 宿主 1 档 composer 开关 + 两处测试面）；

批 8 见 §19.4（本仓 2 档（kernel + events）+ 固件 / 测试面；thincoder 侧 = out-of-repo 档）。

批 10 见 §20.4 / §21.3（本仓文件面；F18 含 `thincoder_kernel.dart` 拆分方案）。

批 11 见 §22.3 / §23.3（F19 桌面半 + F20；B1 例外面 = §22.2 表）；批 12 见 §22.12（F19 CLI 收口：core 3 档 + CLI 1 档；零留存单测档 = `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`；本仓零改动）。

批 14 见 §24.3（本仓适配层 2 档 + 宿主 2 档 + `agent_kernel.dart` 接口 1 档 + l10n 两源档 / 生成档 + 测试 2 档；CLI 零改动）。

**接线点 ⑤ 细则（按内核判定）**

- 做法（选 ⓐ；被否 ⓑ）：`load()` 第一回路按内核记账 `covered: Map<KernelDescriptor, Set<String>>`（内核 → 其 `projects()` 覆盖过的路径）；`_folders` 每个目录求「未覆盖内核子集」（有 catalog ∧ 未被该内核覆盖），子集非空才 `_listKept(project, kernels: 子集)`（仍不等待）。
- `_listKept` 加内核子集参数，缺省 = 全部内核：`_openProject`（`:415`）与 `_listWhenReached`（`:453`）用缺省，语义不变。
- 被否 ⓑ（每个已知项目全量 `_listKept`）：claude 被逐项目重复整读（`:420-421` 的代价面），且起进程数从「未覆盖内核」涨到「全部内核 × 全部项目」。
- 守卫（`:322-326`）——采纳 + 修正：方向采纳（无守卫则逐目录列出在途时 `_forgetGone`（`:1684-1740`）会把未及列出的会话的 pinned/archived/names/drafts 当「已消失」清掉并落盘 = 数据受损）；判据 = **逐内核**：本轮没有触发逐目录列出才清理（等价：每个目录都被每个有 catalog 的内核覆盖）——合并集不再胜任：按内核判定后，合并集已覆盖的目录同样有在途列出。
- 扫描失败的内核不记覆盖 ⇒ 其目录照走逐目录列出，`complete` 照旧拦清理（"what one failed to list is not gone" 不变）。
- 代价（登记 §14-11）：thincoder 的 `projects()` 恒空（D6）⇒ 只要 `_folders` 非空就有未覆盖内核 ⇒ 卫生清理整体推迟、`_folders` 不再被剪除（`:1695` 的剪除只在清理运行时发生）——每轮 load 逐目录再列（每目录一次短命连接，D4/D6 既定形态；这正是「终端建的会话下次打开可见」的来源）。后果有界、非数据损坏。

各修改文件当前行数（2026-10-16 快照，供评审核体量）：`kernel_registry.dart` 46 · `agent_kernel.dart` 423 · `chat_session.dart` 1087 · `workspace.dart` 2795 · `main.dart` 733 · `general_page.dart` 796 · `app_settings.dart` 268 · `mock_kernels.dart` 48 · `data_dir.dart` 409。

本批对上述各档的净增上界（`≤ N 行` 式；实施后按各档 diff 核，超出 ⇒ 核接线点范围）：① ≤11 行（含 2 条 import）· ② ≤12 行 · ③ ≤4 行 · ④ ≤10 行 · ⑤ ≤14 行 · ⑥ ≤6 行 · ⑦ ≤81 行（新行 widget，形同 `_ClaudePathSetting`）· ⑧ ≤10 行 · ⑨ ≤16 行 · ⑩ ≤2 行。

体量立场（>800 行既有档与测试档的拆分审阅）：

- **行数口径（总则）**：以下各行数 = 该条编制日的快照；跨节不互校（同一档在不同批的实测值不同属正常，例如本档与 §28.8 / §29.5 各记各的日期）；实施首轮以 `wc -l` 复核，冲突时以复核值为准。
- `chat_session.dart`（1087 行）处 >800 行硬顶之上：**本批不动结构**（只走接线 ③）；拆分单元（facet / review / send 三段，按现坐标钉住）与触发判据以 §29.5 为准；本批不拆。
- `chat_screen.dart`（1231 行）处 >800 行硬顶之上：**批 4 不动结构**（只走接线 ⑬，1 行改动 / 净增 0）；拆分缝候选 = `_ChatScreenState`（`:182`）之后的私有构件族（`:903`–`:1231`：标题栏布局 / 会话列渲染 / 底部切换 / 历史载入 / 面板槽）；触发 = 独立拆分批立项。
- `chat_models.dart`（719 → 806，2026-10-19 实测）：处 >800 行硬顶之上；本批只加 `EditorContext` / `UserMessageItem.contexts`（行级新增，不动结构）；拆分缝候选 = `EditorContext` 段（`:52`–`:131`）出档 `lib/chat/editor_context.dart`；触发 = 下一次结构级触碰或独立拆分批立项。
- `workspace.dart`（2795 行）处 >800 行硬顶之上：**本批不动结构**（只走接线 ④⑤；⑤ = `load()` 回路内改造 + `_listKept` 参数化，不新增文件、不拆类）；拆分缝候选 = The IDE's windows（`:727`）/ SSH hosts（`:1281`）/ Color theme（`:1858`）段（段头注释即缝）；触发 = 独立拆分批立项。
- `thincoder_kernel.dart`：>800 行触发已执行——拆分前实测 1168 行 ⇒ 拆出 `thincoder_events.dart`（§3.6 事件翻译段，外部形态不变）；编制日实测（2026-10-19）**1121** 行（§21.3 拆分已落）仍处 >800 线上：**续拆裁定 = 不续拆**（同其他 >800 行既有档；选择面缝已兑现，不再立新缝）。
  行数口径：与 §24.3 起点 1091 差 30 行（两批各记了当时的实测）；**实施首轮 `wc -l` 复核，以复核值为准**。
- `thincoder_events.dart`（799，2026-10-19 `wc -l` 实测）：<800 硬顶；批 11 的用量翻译面 ≤ +8 ⇒ ≤807 ⇒ **入 >800 名单**（行级新增，不动结构）；缝候选 = 子代理段（段头 `:436`）出档 `thincoder_agents.dart`（`part` 先例同 §21.3；段界由拆分批勘定——`_putSubagent` / `_card` 另有 `:682` / `:741` 调用点）；**拆分方案（分步 + 行数预算）见 §23.3**；触发 = 下一次结构级触碰或独立拆分批立项。
- **>500 且 <800 的档**（`thincoder_mock.dart` 668 · `kernel_types.dart` 615 · `context_usage_panel.dart` 530 等）：体量立场只跟 >800 硬顶——>500 层不立缝、不登记拆分候选；新增按行级计，不触发结构级裁定。`thincoder_kernel.dart`（会话治理 A1 后 1296）入 >800 名单，行级新增不续拆。
- `test/kernel/thincoder_kernel_test.dart`（3395，2026-10-19 实测）：在 >800 名单；只加用例、不动结构，缝候选沿用 §15.4 的四组拆法。

**实施读数（`host-tool-channel` 批，2026-10-18；本批起点 → 终点）**：`lib/kernel/thincoder/thincoder_kernel.dart` 1156 → 1195（+39，上界 ≤1196）· `lib/kernel/thincoder/thincoder_events.dart` 784 → 798（+14，上界 ≤798）· `test/kernel/thincoder_kernel_test.dart` 2629 → 2840（+211，超估算 +140，估算非上界）。三档现值见 §5.2 体量行。

---

## 6. 关键决策记录（含被否方案）

| # | 决策 | 理由 / 被否方案 |
|---|---|---|
| D1 | 每会话一个 `thincoder acp` 进程，cwd = 项目目录 | 服务端单 cwd 模型（`handlers-session.mjs:179-181`）；被否：一个进程跑多项目——`session/new` 会拒 |
| D2 | 翻译档按体量触发拆出 `thincoder_events.dart` | 随内核起步（先例 codex 内联）；kernel 实测 1168 行越过 >800 行硬顶 ⇒ 拆分已执行；残余 885 行不续拆（体量立场 = §5.2 末段） |
| D3 | JSON-RPC 连接层独立成档 | claude 的 `ControlChannel` 无 id 配对、不处理服务端主动请求；语义不合 |
| D4 | catalog 用短命连接（串行队列），不做常驻连接 | list/delete 是低频操作；常驻连接要管进程生命周期、崩溃恢复与闲置策略，成本不成比例 |
| D5 | 会话记录 id = `"<cwd>\|<slot>"`（组合 id），宿主 `SessionRecord.id` 与内核 `sessionId` 同形 | 槽号跨项目重复（每项目各自从 1 起）；宿主按 id 去重（`workspace.dart:490-496`）——裸槽号会把另一项目的会话误判"已列出"而丢弃。拆解按最后一个 `\|`（Windows 路径不容 `\|`） |
| D6 | `catalog.projects()` 返回空；靠宿主逐项目列（接线点 ⑤） | ACP 无跨 cwd 枚举；被否：读 `~/.thincoder/sessions/` 反查 cwd——读 thincoder 内部布局（需求档 F2 明写"走 session/list"）；被否：`projects()` 里对"记得的项目"逐个起进程——刷新（窗口聚焦）时进程风暴 |
| D7 | 图片：不声明 `AcceptsImages`；新增 `AcceptsImageFiles` + 落盘 + 路径行（= 回退路；原生路见 §22 / D82–D85） | 需求档 F6 原文；原生路随握手能力位（§22.1）；不复制终端 `read_image` 指令（桌面不知模型多模态性） |
| D8 | 不声明 `StartsPlans`，计划以对话文本呈现 | 协议面无计划对象/文件；终端同形；声明了就得造假计划卡 |
| D9 | 模型候选 = `configOptions.options`（当前一项）；不读 config.json、不直连 provider `/models` | 需求档 §5 口径就是 `set_config_option` + `config_option_update`；读 config.json 拿不到清单（渠道不携模型），直连 `/models` 要用户的 key、且要复刻三种渠道格式（`model-picker.mjs:294-319`）。E3 钩子：thincoder 填多候选即亮 |
| D10 | 思考 = `ModelSetting(toggle: true)` | 协议面 thinking 是 boolean；先例 = claude 的 `fast` |
| D11 | 会话起点只吃 `settings['mode']` | 宿主 settings 面是 Claude 形（`workspace.dart:2473-2477` 是 ModelProviders 的模型名），喂给 thincoder 会指错模型 |
| D12 | 认证引导 = 服务端 message 原文 + 我方一行前缀；不声明 `auth.terminal` | 声明了要有动作，本批不做终端登录动作；声明即虚报 |
| D13 | 版本下限 0.12.74，低于下限警告不阻断 | 能力面如实声明（`client-caps.mjs:52-64`）⇒ 旧版可能照常可用；"不静默降级"= 明示，非阻断 |
| D14 | 目录短命连接与内核长连接同源不同寿命，共用 locator 与传输实现 | 复用一套起进程逻辑，避免第二份环境/探测代码 |
| D15 | load / resume / new 三路判据 = §3.5 | load 重放会重复进 transcript ⇒ 只在"本内核从未载入过"时用 |
| D16 | 进程注册表复用 `ChildProcessRegistry`（文件名 `thincoder`） | 与 claude/lsp/pty 同机制；`data_dir.dart:86-87` 清单加一类 |
| D17 | 存量档案默认内核迁移（接线点 ④） | 旧版无选择器 ⇒ 档案值非用户选择；不迁移违背 F1/A1 口径。标记名与写法由实施定，语义 = "用户选过才作数" |
| D18 | mock 内核不进 `MockKernels.all` | `test/flutter_test_config.dart:39` 把全部 widget 测试的内核换成 `all`；进 `all`（尤其列入首位）会改所有既有测试的默认内核 ⇒ A9"既有测试不回退"风险 |
| D19 | 审批三值固定映射（approve_once / approve_always / reject） | 服务端选项固定三值（`bridge.mjs:50-54`）；面板固定三行（`interaction_panel.dart:139-143`） |
| D20 | `set_config_option` 失败不乐观改显示 | 需求档 F5"显示以 thincoder 回报为准（不乐观假报）" |

---

## 7. 验收对照（回指需求档 §7）

| 需求档 | 本档落点 | 说明 |
|---|---|---|
| A1 默认内核 | §4 F1 + 接线点 ①④ | 测试断言 = 描述符身份（`KernelRegistry.thincoder.id == 'thincoder'`）+ `MockKernels.thincoder ∉ MockKernels.all`；首位事实由代码核（`kernel_registry.dart:40`）——`test/flutter_test_config.dart:39` 把全量测试的注册表整体替换 ⇒ `all.first` 断言写不出。存档迁移场景另测 |
| A2 可选并存 | 接线点 ① + `chat_session.dart:303-316` 既有选择器 | claude 面零改，既有测试不回退 |
| A3 终端互通 | §4 F2 + §3.5（load 钉回/fork）+ §5.2-⑤ | 终端的会话 → 桌面开同项目可见可续——项目同时有 claude 会话同样列出（`load()` 按内核判定，不因 claude 覆盖而跳过 thincoder 的 `session/list`）；反向（桌面 → 终端）前提 = 桌面侧至少发出过一条消息（槽文件落盘，§3.5）之后，终端可见/可续 |
| A4 全链路走查 | §3.6 + F3/F4/F5/F10 | 文本/思考/工具卡/审批三选项/取消/plan 切换 |
| A5 图片替代 | §4 F6 | 命名与终端一致（`attachments.mjs:76,92`），agent 可读到文件 |
| A6 引导面 | §4 F7 | PATH 无 → 安装引导不崩；未登录 → 登录引导；版本低 → 警告 |
| A7 远程（批 2） | §13 | 本批只留接口面 |
| A8 Customize（批 3） | §13 | 本批只留接口面 |
| A9 测试 | §9 | mock 对端覆盖五路径；既有测试不回退（D18 决定） |
| A10 扩展性 | §5 + §12 | 改动点清单 + 升级核对说明（本档在场即载体） |
| F11 子代理活动可见（批 4） | §15（验收对照 = §15.6） | 真机走查 7 步：卡片 / 活动条 / 计数行 / 静默期；控制面不做（§15.8） |
| F12 子代理内容归属（批 5） | §16（验收对照 = §16.6） | thincoder 侧归属标（§16.1 逐行 diff：内容帧 + 工具帧）+ 本仓路由进只读视图（§16.2）；走查 §16.9；工具结果通道仍缺（§16.8-1） |
| F13 审批自动档（批 6） | §17.1（验收对照 = §17.6） | 服务端位 `autoApprove` 暴露 + 桌面右下角开关显示与切换（宿主 1 档 = `composer.dart` ㉗）；走查 §17.9②③④ |
| F14 模型清单与思考档位（批 6） | §17.3（验收对照 = §17.6） | 运行期清单投影进 `model.options[]` + `thinkingLevel` 档位面；模型面桌面零改动；走查 §17.9⑤⑥ |
| F15 工作中发送的消息（批 7） | §18（验收对照 = §18.5 · 用例 = §18.7） | 内核本地队列 + 声明 `QueuesMessages`：在跑时入队，回合结束依次发，撤回 / 立即发送 / 收束清队；宿主零改动（唯一触碰 = 设置页一句文案）；走查 §18.10 |
| F16 回合结束后继续关注后台子代理（批 8） | §19（验收对照 = §19.6 · 用例 = §19.7） | ACP 挂起窗（out-of-repo）+ `_meta["thincoder.dev/turn"]` 边界帧 + 桌面 unprompted 回合；走查 §19.10 |
| F17 编辑器上下文随消息注入（批 10） | §20（验收对照 = §20.6 · 用例 = §20.7） | 每消息快照（路径 + 光标行 + 选区）随 `session/prompt` 一个文本块；composer chip 可撤销 + 气泡摘要；开关 `chat.editorContext` 带设置 UI；走查 §20.9 |
| F18 agent 编辑走 IDE 原生 diff（批 10） | §21（验收对照 = §21.5 · 用例 = §21.6） | 内核 `initialize` 宣告 `fs` 两位 + 两个反向 RPC handler；脏缓冲拒绝写 + 只读 diff；干净 / 未打开落盘并发既有 `FileEdited`；根外拒绝 + 可见提示；走查 §21.9 |
| F19 原生图片块（批 11） | §22（验收对照 = §22.5 · 用例 = §22.6 · 真机 provider 面 = §22.9） | 握手 `promptCapabilities.image` ⇒ prompt 数组带原生 image 块（不落盘）；旧 CLI ⇒ 今天逐字；B1 例外面 = §22.2（**已裁 A**）；「模型能看图」判据 = T1 / T1b + 走查 S1；走查 §22.8 / §22.12 |
| F20 用量（批 11） | §23（验收对照 = §23.5 · 用例 = §23.6） | 回合 token = 本回合 `usage_update.used` 之和（turn footer）；会话累计 = 全会话之和（上下文面板）；成本无来源（§14-25）；走查 §23.8 |
| F21 模型切换后置应用（批 14） | §24（验收对照 = §24.5 · 用例 = §24.6） | 回合在飞时点模型 ⇒ 回合收尾自动重发；pill 标「回合结束后切换到 <目标>」；失败 = 旧模型 + 一条 error；走查 §24.8 |
| F22 交互响应（批 16） | §25（验收对照 = §25.10 · 用例 = §25.11） | 宿主侧：打开项目预热进程（领池即用）+ 乐观就绪可见（`NoticeItem` 等待面）+ 打点 8 类；CLI 侧瘦身归已批准的外仓批（§25.13 C′1–C′3）；走查 §25.14 |
| F23 内置运行时（批 17） | §26（验收对照 = §26.12 · 用例 = §26.11） | 发行版内置 `runtime\node\node.exe` + thincoder 源码树 + 私有数据目录（`THINCODER_CONFIG_DIR`）；开发环境按「内置目录在不在」自然分叉、零 release 常量；外仓 6 档 8 处改动归独立外仓批；走查 §26.14 |
| F24 模型配置面（批 18） | §27（验收对照 = §27.8 · 用例 = §27.7） | 模型清单仍由 CLI 投射（零新协议）；新增「设置 → 模型（thincoder）」页，写内核实际读的那份 `config.json`（只动 `providers[]` 与顶层 `defaultModel`，并发门零写 + 原子写 + 回读）；可见性 = 用户点「重开会话」 |

需求档条目覆盖（三方一致链）：F1–F7、F10–F24、E1–E5 全部有落点；F8/F9 只留接口（§13）；B1–B4 遵守，B3 由 F24 收窄（provider / key 的编辑面由 F24 承接，写入面只有 `providers[]` 与顶层 `defaultModel`）——
B1 默认不改 thincoder 仓，例外 = 经用户裁定的最小接口改动（F12 归属标 §16.1；F13 / F14 的 configOptions 投影 §17.1-① / §17.3-①②；

F16 的 ACP 挂起窗 + 回合边界帧 §19.3；F19 的 `promptCapabilities.image` + 图像块内容 §22.2——**B1 已裁 A**；
会话治理 A1 的 `session/set_title` / `session/revert` + 撤销栈回合化 / `prompt.turnId`——用户 2026-10-20 00:02 已准，落点见 `session-governance`）。

---

## 8. 用例表（正常 / 边界 / 错误）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 握手 | `initialize` 正常回包 v1 | health ready；协议版本与 agentInfo 版本留痕（`appEvent`） |
| T2 | 新会话 | prepare + send | `session/new` → 选项到位 → `session/prompt` → 流式文本/思考 → `end_turn` → TurnEnded |
| T3 | 续接 | `resume` 记录 + prepare | `session/load` 重放 → 项按序进 transcript；`loadingHistory` 期间为真、响应后为假 |
| T4 | 恢复（重连） | release 后再 prepare | `session/resume`（不重放）；无重复项 |
| T5 | 工具卡 | `tool_call` + `tool_call_update` | 卡先"进行中"后"完成/失败"；execute 形态出终端项 |
| T6 | 审批-一次 | request_permission → 选"一次" | 回 `{outcome:{outcome:'selected',optionId:'approve_once'}}` |
| T7 | 审批-总是 | 选 alwaysAllowLabel 行 | 回 `approve_always` |
| T8 | 审批-拒绝 | 选"拒绝" | 回 `reject`；理由文本不送（§14） |
| T9 | 审批-超时 | 面板不答 | 服务端 5 分钟后按拒绝；UI 全程可交互 |
| T10 | 取消 | 流式中 `cancel()` | `session/cancel` → prompt 回 `cancelled` → `TurnEnded(interrupted: true)` |
| T11 | 模式 | 选 plan | `set_mode` → `current_mode_update` → 选择项显示 plan |
| T12 | 模型 | 选中候选 | `set_config_option('model')` → `config_option_update` 后显示（不乐观） |
| T13 | 思考开关 | 拨开关 | `set_config_option('thinking')` → 回包后显示 |
| T14 | 用量 | `usage_update{used,size}` | 上下文读数 = used/size |
| T15 | 图片 | 有图回合 | 落盘 3 个文件、路径行入正文、transcript 文本 = 实发文本；A5 走查备注：在无句尾指令条件下（普通模型）验 agent 仍读到文件，结论回写 D7 |
| T16 | 图片超阈 | >15 MB 单图 | 该图弃 + 会话内提示；其余照发 |
| T17 | 目录列出 | 终端建的会话 | `session/list` 项进目录（含标题/时间）；空标题显示"未命名" |
| T18 | 目录删除 | 删一条 | `session/delete`；再列已消失 |
| T19 | 未安装 | PATH 无 thincoder | health failed + 安装引导文案；应用不崩 |
| T20 | 未登录 | `-32000` | health failed + 服务端原文（含 `thincoder acp --login`） |
| T21 | 版本低 | `agentInfo.version < 0.12.74` | 会话内 warning 提示；功能不阻断 |
| T22 | 未知方法/通知 | 服务端发未知 `sessionUpdate` / 未知反向方法 | 忽略 / 回 `-32601`；连接与回合不受影响 |
| T23 | 进程死 | 流式中杀进程 | 在飞回合 interrupted + error 提示 + health failed；`restart()` 可恢复 |
| T24 | 默认内核 | 空档案建 workspace | `preferredKernel.id == 'thincoder'` |
| T25 | 存量档案 | 档案带 `kernel:'claude-code'`（无选择标记） | 默认回到 thincoder（D17）；有标记则尊重用户选择 |
| T26 | 审批-在飞 dispose | 面板未答时内核被 `dispose` | 回 `{outcome:{outcome:'cancelled'}}`；进程按 §3.5 的 dispose 路径收尾（事件流关闭、stopped 完成） |
| T27 | 图片合计超阈 | 单回合多图、合计 >30 MB | 超阈项弃 + 会话内提示；其余照发（单项 ≤15 MB 判定同 T16） |

注（A3 反向走查前提）：桌面侧至少发出过一条消息（槽文件落盘，§3.5）后，终端（同 cwd）可见/可续；未发过消息的桌面会话不进终端 `session/list`。

---

## 9. 测试策略（A9 / E5）

- **mock ACP 对端**（`thincoder_mock.dart`）：一个进程内的脚本化服务端——按写入的请求回对应响应，并按脚本发通知/反向请求。覆盖五路径：握手 / 会话（new·load·resume·list·delete）/ 事件（文本·思考·工具卡·用量·模式·配置）/ 审批（三选项）/ 取消。被内核测试直驱（先例：`kernel_test.dart:4487` 直建 `CodexKernel(..., server)`）。
- **入站串行档（保真度）**：mock 默认在调用方栈上同步处理入站帧；`serialInbound: true` 时按 FIFO 逐个、各在独立的 turn 上处理（`thincoder_mock.dart:132-156`）——真实传输就是串行读帧、一帧不跑在上一帧的栈里（外仓 `transport.mjs:13-19` 的入站 FIFO）。内核测试的 `_Session` 默认用串行档（`thincoder_kernel_test.dart:53`）；默认值只留给不依赖时序的直驱用例。
- **固件**（`test/fixtures/thincoder/*.ndjson`）：每文件 = 一个场景的帧序列（服务端发出的行 + 期望客户端动作清单）；`thincoder_fixtures_test.dart` 逐帧回放并断言 transcript 结果。用途 = 离线回归：**thincoder 更新后先跑固件**（不装 thincoder 也能验协议面是否变形），变形 ⇒ 按 §12 清单核对。
- 真机冒烟（可选、默认 skip）：`-t e2e-thincoder` 起真 CLI 走一遍 A3/A4 的最短路径，照 `dart_test.yaml` 的 e2e 形。
- 既有测试不回退：`flutter test` 全量；特别关注 `test/kernel_test.dart`、`test/kernel_ui_test.dart`（D18 已避开默认内核面改动）。
- 队列面（批 7）：§18.7 用例（T63–T67）入 `thincoder_kernel_test.dart`；mock 加一个可变参数 `promptError`（T67③ 的失败面）。**不加固件**：本批不发新帧（还是 `session/prompt` / `session/cancel`），队列顺序由 T63 / T64 用 `requests()` 逐帧钉住；回放虽有发消息动作（`thincoder_fixtures_test.dart:102-106`），加 `queue.ndjson` 只会重复同一断言。既有固件保持绿 = 回归哨兵。
- 挂起面（批 8）：§19.7 的 T68–T76 入 `thincoder_kernel_test.dart`；固件新增 `digest-turn.ndjson`（`_check` 增 `unprompted` 键），既有 `subagent-digest.ndjson` 不改（旧 CLI 兼容哨兵）；thincoder 侧由 out-of-repo 轮按该仓惯例落单元测试档（`docs/batches/<batch>.test.mjs`）。
- 子代理面（批 4）：§15.7 用例入 `thincoder_kernel_test.dart`；固件新增 `subagent-*.ndjson`（`_shown` 增卡片行与 `tasks` 断言）——「先跑固件」口径不变。
- 子代理内容面（批 5）：§16.7 用例（T42–T50）入 `thincoder_kernel_test.dart`；固件新增 `subagent-content*.ndjson`（`_check` 增 `agents` 键）——「先跑固件」口径不变。thincoder 侧机制由 out-of-repo 轮的一次性探针钉形（§16.1：该仓测试清单为空，不向空清单塞档）。
- 选择面（批 6）：§17.7 用例（T51–T62）入 `thincoder_kernel_test.dart`，T61（形态面 widget）入 `test/composer_test.dart`（mock 加 `autoApprove` / `models` / `thinkingLevels` / `configError` 四个可选脚本参数，缺省 = 今天的形状；
  T61 的 thincoder 一半 = `ThincoderMock(autoApprove: false)` + 自建 descriptor，Claude 一半 = 既有 `pumpScreen`）；**不加固件**——回放没有「点选择器」的动作（`thincoder_fixtures_test.dart:84-125`），选项面在 kernel 测试断言；既有固件保持绿即回归。thincoder 侧机制同样由 out-of-repo 轮的一次性探针钉形（§17.1 / §17.3 的探针期望）。
- 上下文与 fs 面（批 10）：§20.7 / §21.6 的 T77–T92 入 `thincoder_kernel_test.dart` 与新增 `thincoder_files_test.dart` / `ide_kernel_files_test.dart`（另有 `test/chat/*` 两档）；**不加固件**——F17 的线形是既有 `session/prompt`（无新帧），F18 的反向请求由 mock `push` 直推（`thincoder_mock.dart:138-140`）；既有固件保持绿 = 回归哨兵。
- 图片与用量面（批 11）：§22.6 / §23.6 的 T93–T98 入 `thincoder_kernel_test.dart`（mock 增 `promptImage` 能力位开关，缺省 false = 今天）；**不加固件**——F19 的线形是既有 `session/prompt`（块数变、方法不变），F20 的 `usage_update` 帧形不变；既有固件保持绿 = 回归哨兵。
- 图片收口面（批 12）：本仓零新增（baocode 零改）；thincoder 侧单元测试档 = `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`（T1 / T1b / T2 / T3 / T4），跑法 `cd thincoder && node --test <该档>`；零留存（收口删除），不进该仓 `npm test`（只收 `test/**`）。
- 模型切换后置面（批 14）：§24.6 的 T100–T105 入 `thincoder_kernel_test.dart`（mock 的既有 `hold` / `configError` / `models` 直驱，零 mock 改动）；T106 宿主投影入 `test/chat/pending_model_test.dart`；**不加固件**——线形是既有 `session/set_config_option`（无新帧）；既有固件保持绿 = 回归哨兵。
- 交互响应面（批 16）：§25.11 的 T107–T111 入 `thincoder_kernel_test.dart`；T108 / T109 另有 `test/kernel/thincoder_warm_test.dart`（不启真进程，时钟与 transport 工厂可注入）。**不加固件**——线形是既有 `initialize` / `session/new` / `session/prompt`；既有固件保持绿 = 回归哨兵。批 16 见 §25。

---

## 10. 边界（本批不做）

- 需求档 B1–B4 全部沿用：B1 默认不改 `thincoder/`；例外 = 经用户裁定的最小接口改动（F12 归属标 §16.1；F13 / F14 的 configOptions 投影 §17.1-① / §17.3-①②；
  F16 的 ACP 挂起窗 + 回合边界帧 §19.3；会话治理 A1，见 `session-governance`）；❌ 各项不做（图片直传 / 多文件夹 / fork / 后台任务 / MCP 管理 / 账号用量 / 建议类 / `context` 与 `fast` 两个选择器档——指 context-size 与 fast 面；
  **回退 / 改名已由会话治理 A1 落地**）。
- `effort` 档位面**不在上条边界内**：多档随批 6 落地（§17.3-③，`thinkingLevel` 上报即有列表）。
- 本档新增不做：计划卡（D8）；终端登录动作（D12）；`checkpoint/*`·`memory/*`·`ledger/*`·`batch/*` 扩展族（不接）；审批「总是」= 会话级 auto（§17.1-④；与终端 `/auto` 同源），更细的作用域（按工具）不做。（子代理显示面 = 批 4、子代理内容归属 = 批 5 已接；边界见 §15.8 / §16.8。）
- 队列面（工作中发送的消息）= 批 7 设计已定（§18）；本批边界见 §18.9。
- 挂起面（回合结束后继续关注后台子代理）= 批 8 设计已定（§19）；本批边界见 §19.8（timer 唤醒 / 自动轮审批 / 重放边界 / 只停一轮不做）。
- `tool_call` 路由不发 `FileEdited`：ACP 的 `tool_call` / `tool_call_update` 不带 diff（`bridge.mjs:259-292`），无可靠增删行数 ⇒ 变更审查面板按既有快照面工作；`fs/write_text_file` 写路由发既有 `FileEdited`（§21.2 / D79）。登记 = §14-5。
- 图片面（F19）= 批 11 设计已定（§22）：原生块需 B1 例外（§22.2，**已裁 A**）；桌面半与 CLI 半一并实施；新 CLI 合入前生产行为 = 今天；边界见 §22.7。
- 用量面（F20）= 批 11 设计已定（§23）：成本无来源（§14-25）、终端无 `/usage` 命令（§14-26）；边界见 §23.7。
- 图片收口面（F19 CLI 半）= 批 12 设计已定（§22.9–§22.12）：core 3 档 + CLI 1 档属 B1 例外（依据 = §22.12 首段）；各节边界见 §22.9 / §22.10 / §22.11 末段。
- 模型切换后置面（批 14）= 设计已定（§24）：只对 thincoder 内核的 `model` configId；不做回合内生效、不做 provider 后置、不做等待态持久化；边界见 §24.7。
- 交互响应面（F22）= 批 16 设计已定（§25）：宿主侧 = 预热池 + 乐观就绪可见性 + 打点；CLI 侧瘦身归**已获批准**的外仓批（§25.13）；边界见 §25.12。批 16 见 §25。

---

## 11. UI / 交互决定（已落地项与 open 项）

- 已落地：内核选择器（既有，`chat_session.dart:303-316`，≥2 内核自动出现）；模型/模式/思考复用 composer 的既有选择器（`session_model_picker.dart`）；审批复用既有面板（三行固定，`interaction_panel.dart:135-176`）；健康横幅复用（`health_banner.dart`）；设置行新增 thincoder 组（接线点 ⑦）。
- open（本批不裁决，写得明确）：审批面板的"拒绝理由"输入框对 thincoder 无下游通道（面板照常显示输入框但文本被丢弃）——是否隐藏该输入框，属面板通用交互，另议（§14）。
- open：模型候选仅一项时，picker 仍显示（点开只有一个选项）——保持现状（诚实显示上报面），不特判。
- 已落地（批 4）：子代理卡片 / 活动条 / 会话状态全部复用既有面（§15.9）；无停止 / 转后台按钮（display-only，D22）。
- 已落地（批 5）：子代理卡片可点开只读视图（思考 / 正文 / 工具卡），活动条行同入口（§16.3）；仍无控制面（D22 不变）。
- 已落地（批 6）：审批自动档 = composer 右下角的拨动开关（胶囊 track + 圆 knob，开 = knob 在右、track 橙，关 = knob 在左、无填充；两档 ⇒ 右端开关，≥3 档仍是左簇菜单——Claude 的 UI 不动；§17.1-③）——本批唯一的宿主改动（`composer.dart` ㉗，+≤70）；思考面在 CLI 上报 `thinkingLevel` 时变为档位列表，否则仍是开关（§17.3-③）。无新 l10n 键：tooltip 文案来自内核选项（英文占位，§14-19），标题复用 `composerApprovalTitle`。
- 批 7 设计已定（§18）：工作中发送的消息 = 宿主既有队列面（队列面板 / 撤回 / 编辑 / 立即发送三动作），thincoder 内核声明 `QueuesMessages` 后自动生效，宿主零改动（§18.8）；唯一触碰 = 设置页「工作中发送的消息」的说明文案（D54）。
- 已落地（批 8，设计）：自动轮 = 宿主既有「无提示回合」面（不滚到底 / 完成不响铃 / 可停止 / 期间可排队）；无新组件、无新文案（§19.9）。
- 已落地（批 10，设计）：编辑器上下文 = composer 输入区下方的可撤销 chip + 已发消息气泡里的只读摘要（无新面板，§20.3）；agent 编辑的拒绝面 = 会话内 `NoticeItem(error)` + 编辑器只读 diff，不弹窗（§21.2 / D80）。
- 已落地（批 11，设计）：图片保持既有 composer / 气泡面（收图判据不变，D82）——原生块与回退对用户零新增可见面；用量 = turn footer 的「N tokens」（无 speed / cost）+ 上下文面板新增「本会话累计」一行（§23.1）。
- 已落地（批 14，设计）：模型切换的等待态 = 既有模型 pill 的 label 后缀 + tooltip（不新增控件 / 弹窗）；失败 = 会话内既有 error notice；等待态文案走 l10n（`modelsSwitchPending`），失败 notice 为内核口英文并登记 §14-28（§24.9）。
- 已落地（批 16，设计）：准备中的等待面 = 会话内既有 `NoticeItem`（宿主侧无 `starting` 呈现，§25.3-2），不新增控件 / 弹窗；预热池对用户不可见（D104）。批 16 见 §25。

---

## 12. 升级核对与适配说明（E5）

### A. thincoder 升级后（终端 `npm i -g thincoder` 或自动更新）

1. **先跑固件**：`flutter test test/kernel/thincoder_fixtures_test.dart`（离线，不装 thincoder 也跑）。红了 ⇒ 按下面逐条核对。
2. **看握手实况**（一条命令）：
   `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}' | thincoder acp`
   —— 核对：`protocolVersion` 仍含 1；`agentCapabilities.{loadSession, promptCapabilities, sessionCapabilities}` 键名与值；`agentInfo.version`；`authMethods` 形状。

   对照坐标：`thincoder-cli/src/acp/client-caps.mjs:46-64`。
3. **核对方法面**：`session/{new,load,resume,list,prompt,cancel,close,set_mode,set_config_option,delete}` 是否仍在、语义是否变（对照 `thincoder-cli/src/acp/handlers-session.mjs` / `handlers-slots.mjs`，与权威档 `thincoder/docs/cli/design/ACP-CLIENT.md` §2）。
4. **核对线形**：§3.4 四张表的字段名（`content.text` / `toolCallId` / `title` / `kind` / `rawInput` / `status` / `used` / `size` / `configOptions[].{id,name,type,currentValue,options[]}` / `currentModeId` /
`options[].optionId` / `session_info_update._meta["thincoder.dev/subagent"].{role,id,state,progress?,detail?}`（§15.2）/
`session_info_update._meta["thincoder.dev/turn"].{phase,kind?,ok?}`（§19.2）/

`agent_message_chunk`·`agent_thought_chunk`·`tool_call`·`tool_call_update` 的 `update._meta["thincoder.dev/subagent"].{role,id}`（§16.1））；

另外批 6 起的两个 id 与一项形状：`configOptions[].id` 值域含 `autoApprove`（boolean）与 `thinkingLevel`（select，值域 = `off` + 档位名）；`model.options[]` 可为多项（`provider:model`，运行期清单投影）——少了任何一项，桌面按「旧 CLI」降级（§17.3-④），不是错误。

批 12 起的存档线形：槽 JSON 的 `contextHistory` 与 `history` 都不再含 `image_url` / `data:image/`（§22.10 剥离；只剩占位文本 `[image omitted — stripped from the session archive]`）——批 12 前落盘的旧槽仍可能带图（不回扫）。

批 11 起的线形：`initialize` 回包的 `agentCapabilities.promptCapabilities.image`（true ⇒ `session/prompt.prompt[]` 可含 `{type:"image", data, mimeType}`；缺位 / false ⇒ 桌面只发 text 块）；`usage_update.cost` 仍不出现（CLI 不上报，§14-25）。
变了 ⇒ 改 `thincoder_protocol.dart` 的解析与 `thincoder_events.dart` 的翻译（§3.6 / §15.2），重录固件。
5. **核对错误面**：`-32000/-32601/-32602/-32603` 语义（`acp/transport.mjs:14-20`）；凭据门文案是否仍指向 `providers[].apiKey` 与 `thincoder acp --login`（`handlers-session.mjs:85-105`）。
6. **版本下限**：若新版本协议面有变 ⇒ 更新 `thincoderVerifiedVersion` 常量（`thincoder_locator.dart`）+ 本档 §3.4 + 固件；只有内部变化 ⇒ 只重录固件。
7. **重录固件**：拿真实进程录一遍（一次真实会话的帧，或手工 stdio 交互），落 `test/fixtures/thincoder/`；录法写在该目录的 README 一行。**基准口径**：初版固件 = 按服务端源码线形手工录制（非真进程录音；用途 = 离线回归哨兵）；真机重录的执行点 = T15 端到端走查（重录后同步 `test/fixtures/thincoder/README.md` 的措辞）。
8. **需求档 §5 核对**：thincoder 补的能力（如模型清单进 `configOptions.options[]`、`session_info_update` 之外的子代理面、`auth.terminal` 动作）⇒ 更新需求档 §5 → 本档 §4/§6 → 适配层小改（E3）。

### B. baocode 上游合并后

1. **核对接线点**（行号会漂，按符号核）：`KernelRegistry._all` 顺序（thincoder 首位）· `ChatSession.acceptsImages` · `Workspace` 的 `_preferredKernel` 持久化/恢复与 `_kernelChosen` · `Workspace.load` 的 `_folders` 列出回路（按内核判定，§5.2-⑤） · `main.dart` 的 reap/stop · `app_settings`/`general_page` 的 thincoder 行。
2. **核对宿主契约**：`AgentKernel` / `SessionCatalog` / `KernelChoiceSource` / `KernelEvent` 若变 ⇒ 按新语义核适配层（claude 内核 = 对照实现）；`KernelTurn.images` 语义变 ⇒ 核 F6。
3. **回归**：`flutter test`（含 claude 面）。

### C. 双侧联动的判据

需求档 §5 映射表是单一维护点：该表变 ⇒ 本档 §4/§6 与适配层同步；协议面变 ⇒ §3.4 + 固件同步；baocode 侧能力面变（宿主接口新增/改名，如 `AcceptsImageFiles`）⇒ 同步需求档 §5 与本档 §5.2 接线点。

---

## 13. 批 2 / 批 3 接口面（只留接口，不写落地）

- **批 2（F8 远程 SSH）**：接入点是"进程起在远端"。本批已留的缝：
  ① `ThincoderLaunch`（cwd + executable + environment）不假设本地——远端实现只需换 `ThincoderProcess.start` 的落地（走 `lib/remote/` 面，同 `ClaudeCatalog` 的 `_hostOf` 形）；
  ② catalog 的组合 id 里 cwd 用 `RemoteLocation` 形（`host:/path`）即可与本地区分（D5 的组合 id 天然承载）；
  ③ 会话记录 `cwd` 字段沿用宿主远端形。

  批 2 需新定：远端 thincoder 定位（远端 PATH/自装）、远端 `.thincoder/tmp/` 图片落盘、远端目录列出的拉取时机。
- **批 3（F9 Customize 对接）**：接入点是"读 thincoder 的定制面"。本批零改动、零接口预留（`CustomizationStore` 是 claude 形，thincoder 的定制面清单以源码核实为准），批 3 另立设计。

---

## 14. 开放问题 / 已知缺口（写真未知与判定条件）

| # | 事项 | 现状与判定条件 |
|---|---|---|
| 1 | 模型候选的来源与失败面 | 批 6 起 = 运行期清单投影（§17.3）：`model.options[]` 含各渠道清单（去重后 `provider:model`）；拉不到的渠道只报当前项、失败不缓存（下次会话再试）。终端「隐藏派生无 key 渠道」不搬到 ACP——这些渠道拉取失败，结果自然退化为当前项。判定条件：需要桌面把某渠道**排除**（而非失败）⇒ 另立过滤面（涉 B3 口径若读 key 状态） |
| 2 | 拒绝理由文本无通道 | `ApprovalAnswer.message` 丢弃（ACP outcome 无文本位）。判定条件：协议面出现携带文本的 outcome（或 `_meta` 扩展） |
| 3 | 代理面 | 不注入 baocode `NetworkProxy` 变量（Node 客户端是否读 env 代理未核实；thincoder 自带 config `proxy` 段）。判定条件：实测终端 thincoder 走系统/配置代理而桌面进程不走 ⇒ 补注入 |
| 4 | 子代理面的剩余边界 | 批 4 已接显示面（§15）、批 5 已接内容归属（§16）、批 8 已接 digest 回合边界（§19）。剩余不做与判定条件：停止与转后台控制 / 父子嵌套——逐条见 §15.8 / §16.8 |
| 5 | 变更审查面板无增量（`tool_call` 路由） | **已闭合（批 10；fs 写路由）**：`fs/write_text_file` 写成功发既有 `FileEdited(original: OriginalText(before))`，进 `ChangeReview`，Keep / Undo 语义不变（§21.2 / D79）；`tool_call` / `tool_call_update` 仍无 diff 来源（`bridge.mjs:259-292`）⇒ 该路由不发。判定条件：协议面给工具帧补 diff（`tool_call_update.content` 变体）⇒ 该路由也发 |
| 6 | 终端新会话的实时同步 | 窗口聚焦刷新（`workbench.dart:513`）时 thincoder 不重列（D6）。判定条件：用户要"开着桌面看终端建会话"⇒ 加"逐项目重列 + 节流"或 thincoder 补跨 cwd 枚举 |
| 7 | 会话 id 组合形与"半合法路径" | 拆解取最后一个 `\|`；Unix 路径可含 `\|`（罕见）。判定条件：出现歧义（同项目 id 拆错）⇒ 改分隔形（如 json 编码） |
| 8 | 版本下限的"下限" | 0.12.74 = 编制核对版本，非 thincoder 承诺的兼容下限。判定条件：用户裁定支持更旧版本 ⇒ 调常量与核对清单 |
| 9 | 同槽 fork 后记录 id 不刷新 | 同槽被占用时 `session/load` 服务端 fork 到新槽（`handlers-slots.mjs:104-126`），回包无新槽号通道（只有 `{configOptions}`）⇒ 桌面记录 id（D5）仍指旧槽，批 1 按"以服务端语义为准"落地。验收观察点（A3 走查）：终端与桌面同开一个会话 ⇒ 桌面侧 prompt 正常收尾、delete 后两侧列表一致、目录无重复项；观察到旧槽指向（delete 未生效 / 列表重复）⇒ 补"fork 后 id 回流"面（通道另定：通知或回包位） |
| 10 | 能力位声明取固定面（非回包驱动） | 首版按需求档 §5 固定面声明：`LoadsHistory` / `StartsPlans` 为真、`AcceptsImages` 不声明，不随 `initialize` 回包逐位翻转；回包位（`client-caps.mjs:52-64`）用于留痕与版本告警兜底（D13）——旧版 `loadSession=false` 时仍声明历史载入，由版本告警承接。判定条件：需要按回包位区分能力（如旧版隐藏历史载入）⇒ 逐位收敛（E3） |
| 11 | 「未列目录」时卫生清理整体推迟 | `_forgetGone` 只在本轮没有触发逐目录列出时运行（§5.2-⑤）：thincoder 的 `projects()` 恒空（D6）⇒ `_folders` 非空即有未覆盖内核 ⇒ pinned/archived/names/drafts 的清理整体推迟、`_folders` 不再被剪除（每轮逐目录再列）。有界、非数据损坏（只留旧标记，不误删）。判定条件：旧标记堆积 / 状态档见大，或要恢复清理 ⇒ 守卫改「本轮触发的逐目录列出全部返回后再清理」（清理移入 `_listKept` 收尾） |
| 12 | `session/close` best-effort 的残余 | close 只写不等、随即进程退出（§3.5）⇒ 认领是否真释放不保证；「有界等待」会引入本批无法实测的时序依赖 ⇒ 本批不做。判定条件：真机走查确认会话确已释放（残留 ⇒ 加有界等待） |
| 13 | 「会话已不在」（续接记录一路）的兜底 | 处置定死（§3.5）：`session/load` / `session/resume` 收 `-32602`（`gone`）⇒ 忘槽、起新会话（不留启动死结；两路同此处置）；兜底起的新会话跨 `release()` → `prepare()` 续接（同一运行内；记「记录槽已忘」标记，此后走保留槽路线，不重走 `session/load` 死槽）。实现已随末修单落地。判定条件：终端删掉会话后，桌面打开该记录 ⇒ 起新会话、可发消息；此后重连仍续接该会话，不再永久启动失败（真机走查 T15） |
| 14 | ⑦ 设置组文案英文占位 | 新行与状态行英文直写（`general_page.dart:768-770`/`:790-791`、`thincoder_locator.dart:56-59`）。键面口径 = 无 SDK ⇒ ARB 与生成档同拍手改、保持 `test/l10n_test.dart` 绿，SDK 就位轮 `flutter gen-l10n` 重产（同 §18.8）。本行 = 尚未建键 ⇒ 英文占位接受；补齐窗口 = SDK 就位轮（补 `app_en.arb` / `app_zh.arb` 键 + 生成档随 ARB 同拍 + 设置行改用 `context.l10n`）。判定条件：补齐后 zh-cn 该行显示中文、与同页 Claude Code 行一致 |
| 15 | 子代理状态文案英文占位 | 卡片 activity 与活动条详情 / 定格文英文直写（`queued` / `turn <n>/<maxTurns>` / `approval · <tool>` / `thincoder stopped`，§15.2）。同因 = §14-14（本机无 `flutter gen-l10n`）；补齐窗口 = SDK 就位轮（与 14 同轮补 `app_en.arb` / `app_zh.arb` + 生成档重产） |
| 16 | 子代理工具卡的归属与结果 | 归属已接（批 5）：工具帧带同一 `_meta`、本仓路由进 children（§16.1 / §16.2）。结果面仍缺：结果不经 ACP（`spawn-child.mjs:159-161`；`wrapChildCallbacks` 不包 `onToolResult`）⇒ 视图内工具卡停在 in_progress（不伪造终态，§16.8-1）。判定条件：补结果通道 ⇒ `tool_call_update` 路由自动闭合；输出通知另接 |
| 17 | 子代理内容不落盘 | 谈话表随进程（`endSubagents()` 清；§16.8-4）。重开桌面后卡片只剩状态、无 children。判定条件：需要事后回看 ⇒ 另立持久面（会话存档无此字段） |
| 18 | 「Approve for this session」名不副实 | **已闭合（桌面侧；批 6）**：面板选 always ⇒ 先答本次，同一回合写 `autoApprove=true` ⇒ 会话级承诺成立（§17.1-④；用户 2026-10-16 21:47 裁定）。服务端 `approve_always` 仍无记忆（`bridge.mjs:57-62`），桌面不再依赖它；残余判定条件见 §17.1-④ 两条（CLI 改名 / 摘掉、按工具会话级放行表） |
| 19 | 审批开关与档位标签英文占位 | 审批两项（`Ask` / `Auto`）、其 description（开关 tooltip 的第二句）与档位名（`effortLabel`）英文直写；`localizedKernelOption`（`kernel_option_text.dart:8-46`）只认 claude 元组，未知元组原样透出 ⇒ 英文占位接受。同因 = §14-14；补齐窗口 = SDK 就位轮（同轮补 `app_en.arb` / `app_zh.arb` 键 + 生成档重产） |
| 20 | 模型清单后台推送的落地面 | `refreshModelChoices` 是 fire-and-forget（§17.3-①）：落地时会话已关 / 已被 load·resume 替换 ⇒ 丢弃；`notify` 抛出（管道已断）⇒ 吞掉并记一行日志，不重试、不抛。判据 = 会话在册且同实例（`liveSession(id)?.agent === agent`，`acp.mjs` 的 ctx 包装传入）。判定条件：观察到清单在会话关闭后仍被推送 / 进程因未处理的拒绝退出 ⇒ 复核该判据 |
| 21 | timer 唤醒轮不在 ACP 面 | 挂起窗不接 `timerFace`（§19.3-①），且窗内轮与普通轮都带 `suspDriven:true`（§19.3-②）⇒ 桌面会话里到期的 timer 不在后台自起一轮，也不在工具轮收尾投递（`post-turn.mjs:23`）；到期件留在途（不出列、不丢），交付面为零（§19.8-1）。判定条件：桌面需要 timer 唤醒 ⇒ 接 `timerFace`（`suspension.mjs:173-205` 第四态）+ 边界帧 `kind:"timer"` |
| 22 | F17 重放里的 system-reminder 原文 | `session/load` 重放 `user_message_chunk` 文本；CLI 是否过滤机器行未核（`unverified`，§20.8-4）⇒ 本批不解析、不剥离。判定条件：走查看到重放消息里出现 system-reminder 正文 ⇒ 翻译层按固定前缀剥离（另立） |
| 23 | 同一文件并发写 | 不同文件各自落盘；同一文件由 CLI 工具调用串行 + `expectedText` 基线保护（后写发现基线变了 ⇒ `-32603`，§21.8-9）。判定条件：走查见到同一文件并发写丢更新 ⇒ `IdeKernelFiles` 加每路径串行队列 |
| 24 | F17 / F18 的 l10n 键与生成档 | 6 键（F17 4 + F18 2）在 `app_en.arb` / `app_zh.arb` 与生成档同拍在位——无 SDK ⇒ 生成档随 ARB 手改、保持 `test/l10n_test.dart` 绿（同 §18.8 / §14-14）；SDK 就位轮 `flutter gen-l10n` 重产。T82 只机检两源档（生成档由编译引用与控件走查覆盖）。判定条件：重产结果与手改逐键一致 |
| 25 | 成本无来源（F20） | CLI 从不上报 `usage_update.cost`（`bridge.mjs:254-261` 只发 used / size），core 无价目表 ⇒ 桌面不显示成本（不重算，D89）。判定条件：CLI 在 `usage_update.cost`（ACP 可选 `Cost{amount,currency}`）上报 ⇒ 桌面在会话面板与回合 footer 显示（字段按 ACP 形读） |
| 26 | 终端 `/usage` 不存在 / context% 非同一仪器 | 终端斜杠命令表无 `/usage`（`slash-commands.mjs:44-106`）；终端用量面 = 状态行累计 ↑prompt ↓completion + context%（`status-line.mjs:122-143`），其中 context% 是 `estimateTokens(history)` 估算（`render-loop.mjs:89-90`），与 ACP `usage_update.used` 不同仪器。本批对照口径 = token 合计（同 `onUsage` 源，D90）。判定条件：终端后续加 `/usage`（CLI 面）⇒ 按该命令输出补对照项 |
| 27 | F20 的 l10n 键与生成档 | 2 键（`turnTokensSpentHint` / `usageSessionTotal`）在两源档与生成档同拍在位——无 SDK ⇒ 生成档随 ARB 手改、保持 `test/l10n_test.dart` 绿（同 §18.8 / §14-14）；SDK 就位轮 `flutter gen-l10n` 重产。T96 只机检两源档。判定条件：重产结果与手改逐键一致 |
| 28 | F21 后置切换的失败文案英文占位 | 回合收尾重发失败 ⇒ 会话内 error notice 为内核口英文（含原始错误），形同 `thincoder stopped unexpectedly`；等待态文案已走 l10n（`modelsSwitchPending`，§24.2）。内核层无 l10n 面（`lib/kernel/**` 零 `l10n` 引用，2026-10-19 实测）。判定条件：`KernelContext` 携本地化回调（内核 l10n 面）⇒ 该 notice 改走键 |
| 29 | 批 16 的「准备中」等待面文案英文占位 | 会话内 `NoticeItem(warning, 'thincoder is starting…')`（§25.3-2）：宿主侧无 `starting` 呈现，故走内核口英文（形同 §14-28），无 l10n 键。判定条件：`KernelContext` 携本地化回调（内核 l10n 面就位）⇒ 改走键 |

---

## 15. 批 4：子代理活动可见（F11）

> 需求档 F11（批 4；用户 2026-10-16 拍板）。范围 = 本仓适配层翻译 + 既有子代理 UI 面接线；`thincoder/` 零改动（B1）。
> §14-4 的判定条件（「需要子代理活动展示时接」）本批达成——判定条件就地闭合；剩余边界逐条留判定条件（§15.8）。

### 15.1 做法与理由

一句话：把 thincoder 已在推的子代理信号（`session_info_update` 的 `_meta["thincoder.dev/subagent"]`）翻译成宿主**既有的**子代理面——对话里的子代理卡片（`AgentItem`）、活动条的后台任务（`KernelTask` / `TasksReported`）、会话状态（任务在跑 ⇒ 侧栏「运行中」、活动条「N 个子代理运行中」）；控制面（停止 / 转后台）不做：ACP v1 方法面无子代理级控制位（`session/{cancel,close}` 只有会话级）⇒ 纯显示态（D22）。

先例对照（照抄形态，不另造）：

| 面 | 先例 | 照抄的形 |
|---|---|---|
| 子代理卡片 | `claude_code_translator.dart` 的 Task 通路（`_agents` / `_agentCard` / `_putAgent`）→ `AgentItem` | 同事件形（`ItemUpserted` 按 id 原地替换）；字段只填有来源的 |
| 活动条任务 | 同档 `:1428-1441`（`_tasks` + `_reportTasks` → `TasksReported`） | 同形：全量重报；`KernelTaskKind.agent`；`background: true` |
| 终止面 | `RunsBackgroundTasks`（`agent_kernel.dart:202-208`） | **不声明**（无对应 ACP 能力）；显示与停止能力解耦 = 接线点 ⑫⑬ |
| 运行代号措辞 | thincoder 自己的面：VSC 块标题 `eng-coder#N`、通道键 `sub:${role}#${id}`（`thincoder-vscode/CHANGELOG.md:572` · `panel-subagent-relay.mjs:187`） | 同措辞：`<role>#<id>` |

偏离（逐条给理由）：

1. **身份 = `role#id`，不是工具调用 id**。信号不带 toolCallId（`bridge.mjs:71-78` 只投影 role / id / state / progress? / detail?）⇒ 卡片与任务都以 `subagent:<role>#<id>` 为记录 id；卡片 `AgentItem.id` = 同一记录 id（批 5 D35 起）⇒ 可点开该子代理的只读视图（`chat_history_view.dart:1464-1468` 按 `id != null` 给开启入口）；停止 / 转后台仍无动作（D22：任务无 `toolUseId`）。
2. **活动条显示与停止能力解耦**（接线点 ⑫）：ACP 无子代理控制位 ⇒ 不声明 `RunsBackgroundTasks`；而 `ChatSession.tasks` 原按该接口整体门控（`chat_session.dart:626-635`），会把 thincoder 的在跑子代理整个挡在活动条外 ⇒ 门控拆开：显示只看「有没有在跑的后台任务」，控制仍只看接口。
3. **children 有来源、其余五类无**：children = 该子代理的谈话（批 5 起由 §16.2 写入）；result / prompt / tokens / toolUses / model 无来源（子代理内容归属不在 ACP 契约内，thincoder/docs/cli/design/ACP-CLIENT.md §12.6；批 5 只补了内容帧与工具帧的归属标）⇒ 这五类不填；嵌套按最内段扁平展示（父链不承载，同 §12.6）。

### 15.2 信号翻译（ACP → 既有面）

**线形**：`session/update` 通知，`update.sessionUpdate = "session_info_update"`，载荷在 `update._meta["thincoder.dev/subagent"]`（发射 `bridge.mjs:228-232`；形状冻结 = thincoder/docs/cli/design/ACP-CLIENT.md §12.2）：

| 字段 | 域 | 缺席含义 |
|---|---|---|
| `role` | string（relay 最内段主体） | — |
| `id` | integer ≥ 0 | — |
| `state` | string（形态域开集；现发射集 8 名） | — |
| `progress` | `{turn,maxTurns}` ∥ `{position}` | 键缺席 = 无值（非零） |
| `detail` | string（queued 原因文 / approval 工具名） | 键缺席 = 无 |

（load 重放不产本通知——live-only。子代理表跨回合存活：`begin()` 不清理它。）

**身份与 id**：`role#id`（同一会话内）；卡片 / 任务的记录 id = `subagent:<role>#<id>`；显示名（卡片 description / 任务 description）= `<role>#<id>`。

**卡片字段**：description = 显示名；status 随状态机；`background: true`；`startedAt` = 首见时刻（D29）；`activity` = 状态行（下表）；`id` = 记录 id、children = 该子代理谈话（批 5 起，D35 / D33）；agentType / prompt / tokens / toolUses / model / result 不填（无来源）。

**状态机（state → 面）**：

| state | 卡片（AgentItem） | 活动条（KernelTask） | activity / summary 文 |
|---|---|---|---|
| 首见（任意 state） | 建卡（先 `closePiece()`，同 `_toolCall` 形：新项落位、其后文本另起段） | 见下各行 | — |
| `queued`（终态 / 已移除后 ⇒ 忽略，D31） | 不动（running） | **不建**（排队不进活动条；卡片承载） | `queued · <detail>` ∥ `queued` |
| `async`（终态 / 已移除后 ⇒ 忽略，D31） | 不动 | **建任务**（running；startedAt = 首见时刻） | 清空 |
| `turn` | 不动 | 确保在；summary 随 | `turn <n>/<maxTurns>`（单值取有者；皆无 ⇒ 不覆盖） |
| `approval` | 不动 | 同上 | `approval · <detail>` ∥ `approval` |
| `settled` | status = succeeded；duration = now − startedAt；activity 清空 | status = succeeded | 定格（「待消化」不改变「已完工」） |
| `done` | 幂等（已 succeeded） | 留表（不再 running） | — |
| `cancelled` | **ItemRemoved**（对齐 TUI「移除块」`subagent-blocks.mjs:43-44`） | 无（从未建）∥ 已建 ⇒ 移除（不残留 running） | — |
| `stopped` | status = failed；duration | status = failed | 定格 |
| 未知 state | 已有卡不动（保 running）；无卡则建 | 不动 | —（留痕） |

- 每次变动后 `TasksReported` 全量重报（同 Claude 形）；活动条只显示 `background && running`（`chat_session.tasks`），settled / done 后行即消失。
- `cancelled` 契约语义 = 排队取消（从未启动，出队即终态；thincoder/docs/cli/design/ACP-CLIENT.md §12.3）——
  上游唯一发射点 = queued 取消（`subagent-async.mjs:297`）；running 取消走 abort ⇒ `⟦ev⟧stopped` 冻结（同档 `:222-226`；TUI 守卫「cancelled 永不合法指向 running 块」`subagent-blocks.mjs:184-186`）⇒ 已建任务下收到属契约外失序：按终态移除处置（不残留 running；不判 failed——取消 ≠ 失败，D24 口径）。
- **终态 / 已移除后同键报告（契约外）**：一律忽略——卡片不回动（已移除的不重建）、活动条不复活（D31；判定条件 §15.8-7）。已定格（succeeded / failed）后：`queued` / `async` / `turn` / `approval` 四态忽略；卡片已移除（`cancelled` 墓碑）后：**不止四态——任何后续报告（含 `settled` / `stopped` / `done` / 未知态）同一忽略**。实现：墓碑集命中即直接返回（先于四态守卫，不落首见路径）。
- `progress` 只用 `turn` / `maxTurns`（`turn` / `approval` 态在场）；`{position}`（仅 `queued` 在场，队列位次）**不展示**——排队态由卡片承载（D23）、原因文已由 `detail` 承载，不新增文案形（D28 枚举不动）。
- 子代理的审批由父级审批面板承接（`session/request_permission`，桥剥前缀——F4 已接）；卡片只示 `approval` 状态与工具名，不另开面。
- **未知与坏载荷（E4）**：未知 state 保 live（不判定结束——不隐藏在跑的东西）；`_meta` 缺失 / 非映射 / `role`/`id` 类型不合 / 非本键的 `session_info_update`（如既有的 `_meta:{title}`）⇒ 忽略 + `appEvent('thincoder', …)` 留痕（§3.3 机制）。**绝不静默丢弃**。
- **进程退出**（崩溃 / 会话收束）：在跑的子代理全部定格 failed（卡片 duration 定格、任务 failed、summary = `thincoder stopped`）——同 Claude `endTasks` 形（`claude_code_translator.dart:1538-1548`）。不留「永远在跑」的卡片。

### 15.3 挂起态与 digest（回合结束后）

- **挂起态可见性（回合已结束 ≠ 无事发生）**：`session/prompt` 应答已回（`TurnEnded`）而后台子代理仍跑时——卡片继续 running（背景 hover 文案「Running in the background」）、活动条行继续在（计时每秒推进，`activity_strip.dart:110-121` 的 ticker）、侧栏该会话状态显示运行中（`workspace.dart:158-177` 的 `runsInBackground` / `shownStatus`）。**回合模型零改**：不延长回合、不发明边界。
- **挂起期再发消息（无在飞回合时）**：照常发送（`session/prompt` 无超时，§3.4）；服务端排队 / 合并后作答——桌面零特判。自动轮在飞时改走本地队列（§19.2 末条）。
- **digest（auto-turn）的到达形（批 8 起）**：子代理结算后主代理自起内部回合，其输出经 ACP 以 `session/update` 到达，并由**回合边界帧**（`_meta["thincoder.dev/turn"]`，§19.2）包住——桌面翻成宿主既有的**无提示回合**（`TurnStarted(unprompted: true)` / `TurnEnded`）。「正在续写」指示、可停止、结束即回「该你了」全部由既有面承接（§19.9）；自动轮期间发消息进本地队列（§19.2 末条）。
  旧 CLI 无此帧 ⇒ 无回合边界：文本 / 工具项照常入 transcript（`t<run>.<block>` 编号），下一次 `begin()` 或 `closePiece` 收束在飞项——兼容形见 §19.11。

### 15.4 受影响文件清单（E2 增量；编制日行数 = 2026-10-16 快照；实交栏 = 批 4 交付读数）

| # | 坐标 | 改动 | 实交 |
|---|---|---|---|
| ⑪ | `lib/kernel/thincoder/thincoder_events.dart`（413 行） | `session_info_update` 分支从忽略改为子代理翻译（§15.2）：`_subagents` 表 + 卡片 upsert + `TasksReported` 全量重报 + 未知 / 坏载荷留痕 + `endSubagents()`（进程退出定格）；修正轮加统一前置守卫 + `_removed` 墓碑集（D31） | 413 → 638（+225） |
| ⑫ | `lib/chat/chat_session.dart`（1087 行） | `tasks` 门控拆开（只看在跑的后台任务；空表 ⇒ null——消费者 `?? const []` / `?.isNotEmpty` 零改，逐点已核：`chat_screen.dart:489` · `workspace.dart:168` · `workspace_bridge.dart:388/760`）；新增 `canStopTasks`（= 内核实现 `RunsBackgroundTasks`） | +5 |
| ⑬ | `lib/chat/chat_screen.dart`（1231 行） | `:515` `onStopTask` 按 `canStopTasks` 取 null / 回调（不能停的内核不显示停止图标——原样是「点了没反应」的隐性缺陷，本批顺带修正） | 1 行改动（净增 0） |
| ⑭ | `lib/kernel/thincoder/thincoder_kernel.dart`（885 行） | 进程退出 / 会话收束路径调 `endSubagents()`（一行）+ 路径核对 | +3 |
| ⑮ | `test/fixtures/thincoder/`（新增 5 个 `.ndjson`） | `subagent-lifecycle` · `subagent-parallel-queued` · `subagent-cancelled-stopped` · `subagent-unknown` · `subagent-digest` | 新增 |
| ⑯ | `test/kernel/thincoder_fixtures_test.dart`（178 行） | `_shown` 增子代理卡片行；`expect` 增 `tasks` 键 | 178 → 191（+13） |
| ⑰ | `test/kernel/thincoder_kernel_test.dart`（1092 行） | §15.7 的 mock 直驱用例（T28–T41；`ThincoderMock.push` 推帧——`:117` 既有，零 mock 改动） | 1092 → 1537（+445） |
| ⑱ | `test/fixtures/thincoder/README.md` | 补录（表外）：`expect` 键清单补 `tasks` 一行（与固件 `_check` 键集一致） | +1 行 |

- `lib/kernel/thincoder/thincoder_mock.dart` **零改动**（`push` 已可推任意服务端帧）；`lib/kernel/claude_code/**` 零改动；`thincoder/**` 零改动（B1）。
- 体量：`thincoder_events.dart` 改后 638 < 800 行硬顶 ⇒ 不拆（下一缝候选 = 子代理段；触发 = 下次触碰该档）。
- 体量：`thincoder_kernel.dart`（885 行）本批 +3（⇒ 888）属接线级改动（一处 `endSubagents()` 调用 + 路径核对）⇒ **不触发顺拆**（「触碰」按结构级改动计，§5.2 触发句）；选择面段顺拆仍候独立拆分批立项。
- 体量（>800 行既有档）：`test/kernel/thincoder_kernel_test.dart`（1092 → 1537，+445）**批 4 不动结构**（用例增补）；缝候选 = 按 group 拆（`:1371` / `:1416` / `:1433` / `:1525` 起 connection / session ids / locator / the registered kernel 四组独立成档；先例 = `thincoder_catalog_test.dart` / `thincoder_fixtures_test.dart`）；触发 = 独立拆分批立项。
- 体量：`chat_screen.dart`（1231 行，1 行改动 / 净增 0）同处 >800 行线上：裁定见 §5.2 名单（结构不动 / 缝候选 / 触发）。

### 15.5 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D21 | 身份 `role#id`；记录 id `subagent:<role>#<id>`；卡片字段来源：`id` = 记录 id（D35）、children = 该子代理谈话（D33）；prompt / result / tokens / toolUses / model 无来源 | 信号无 toolCallId ⇒ 记录 id 由 `role#id` 合成；字段只填有来源的（无来源五类不填，§16.8-2）；无来源字段不另立展示面 |
| D22 | 不声明 `RunsBackgroundTasks`；停止 / 转后台不做 | ACP v1 无子代理级控制方法；不虚报能力位（E3 口径）。被否：`stopTask` → `session/cancel`——语义错位（会掐整个会话回合） |
| D23 | `queued` 只进卡片；`async` / `turn` 起进活动条 | 活动条语义 = 「运行中」（计数文案 `stripAgentsRunning`）；排队态由卡片承载。偏离 thincoder TUI（queued 即建 waiting 块）：桌面活动条与 TUI 面板职责不同（前者 = 在跑任务 + 计时） |
| D24 | `cancelled` ⇒ 移除卡片；`stopped` ⇒ failed 定格 | 对齐 TUI（cancelled 移除块；stopped 冻结） |
| D25 | `settled` 即 succeeded（不等 `done`） | 「结算完成」= 子代理已完工；`done` 只是消费面归档标记，幂等 |
| D26 | digest 的回合边界由 CLI 的回合边界帧界定，桌面起 unprompted 回合（§19.2 / D55–D66） | 边界必须来自服务端的确定信号。被否：静默期计时闭合（时序 hack）；被否：首个 chunk 合成回合（无收束信号 ⇒ `isStreaming` 永久为真） |
| D27 | 未知 state 保 live（不判定结束）＋留痕 | 开集域（E4）；宁可多示在跑，不可隐藏在跑 |
| D28 | 状态文案英文占位（`queued` / `turn <n>/<max>` / `approval · <tool>`） | 同 §14-14 口径（本机无 `flutter gen-l10n`）；登记 §14-15 |
| D29 | 计时口径 = 首见起算（含排队时间） | 与 thincoder 面板块同时起算（对齐）；单一时钟，卡片 / 任务同源 |
| D30 | 进程退出 ⇒ 在跑子代理定格 failed | 同 Claude `endTasks` 先例；不留永久 running |
| D31 | 终态 / 已移除后同键报告 ⇒ 忽略（契约外） | 上游报告以终态（succeeded / failed / 卡片已移除）收束；再现 = 契约外失序 ⇒ 显示面不回动（卡片不回动、活动条不复活）：已定格后四态（`queued` / `async` / `turn` / `approval`）同守；已移除（`cancelled` 墓碑）后任何后续报告（含 `settled` / `stopped` / `done` / 未知态）同一忽略——不按首见重建（幽灵卡）。跨进程重启的同键再现不在此列（进程收束清表后按新子代理从头起）。被否：按新子代理重建（无可判信号，误建幽灵卡） |

### 15.6 验收对照（回指需求档 F11）

| F11 条目 | 本档落点 | 判据 |
|---|---|---|
| ① 子代理卡片（出现 / 进度 / 完成） | §15.2 状态机 | 卡片随 state 出现、activity 推进、terminal 态定格（固件 + 真机走查） |
| ② 活动条运行代号与计时 | §15.2 任务行 + 既有 `activity_strip` | 行 = `<role>#<id>` + 每秒计时（`stripRunningElapsed`）+ 装填动效 |
| ③ 会话状态行「后台 N 个子代理运行中」 | 既有活动条计数行（>3 折叠）+ 侧栏 `shownStatus` | >3 个在跑 ⇒ 计数行；≤3 ⇒ 逐行；挂起期侧栏显示运行中 |
| ④ 长回合静默期活动指示 | 活动条行（与回合状态无关，挂起期照常）+ 运行中回合的 LiveStatusItem（既有） | 静默期行 / 计时 / 动效持续推进 |
| 真机走查 | 下述 7 步 | 逐条观察记录（截图 / 结论） |

**真机走查步骤**（A 段交付时执行）：

1. 装 `thincoder ≥ 0.12.74` 并登录；baocode 新建会话（内核 thincoder），选一个工程目录。
2. 发一条会让主代理**异步派子代理**的指令（如「用 subagent 并行查三块内容」）⇒ 回合先结束、子代理仍在跑。
3. 验 ①：卡片出现（`<role>#<id>`），activity 随 `turn` 推进；回合结束后卡片仍 running（hover「Running in the background」）；子代理等待审批时 activity = `approval · <工具名>`（无工具名 ⇒ `approval`）。
4. 验 ②④：活动条出现任务行（代号 + 计时每秒推进 + 装填动效）；静默期（无文本流）照常。
5. 验 ③：派 ≥4 个在跑（或 4 并行 + 排队）⇒ 活动条折叠出「N 个子代理运行中」计数行，展开见各行；侧栏该会话状态 = 运行中。
6. 结算后：卡片定格（时长显示）、活动条行消失；随后主代理自起一轮、答案到达（§19；transcript 正常追加，无卡死的运行指示）。
7. 若可复现：排队取消 ⇒ 卡片消失；会话停止 ⇒ 卡片 failed；首帧即终态 ⇒ 卡片直接定格、无残留 running；已建任务下 `cancelled`（契约外）⇒ 卡片与任务行一并移除。（难以复现 ⇒ 以固件用例 T39 / T40 兜底并注明。）

走查注：卡片若在回合中途创建、且该回合以「答案」收尾，会随后者折入「Worked for …」折行（既有折叠语义，展开可见）——回合结束后才到达的信号创建的卡片不在折内、常驻可见；两种都在预期内。

### 15.7 用例表（正常 / 边界 / 错误；固件场景同名）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T28 | 单子代理全生命 | queued → async → turn×2 → settled → done | 卡片 running（activity：queued / turn n/max）；async 后 tasks 含该任务；settled 定格 succeeded + duration；done 幂等 |
| T29 | 并行 + 排队 | 4 个 async 在跑 + 1 个 queued | tasks = 4（排队不含）；计数行在场（>3 折叠） |
| T30 | stopped | async → turn → stopped | 卡片 failed + duration；任务 failed |
| T31 | cancelled（排队取消） | queued → cancelled | 卡片 ItemRemoved；从未进 tasks |
| T32 | 未知 state | `state: "settling"`（虚构名） | 卡片保持 running；连接与回合不受影响；留痕 |
| T33 | 坏载荷 | `_meta` 非映射 / `role` 非串 / 无本键 | 忽略；零事件；留痕 |
| T34 | digest 文本无边界帧（旧 CLI 兼容形） | 回合结束后 `agent_message_chunk`（无 turn meta） | 文本入 transcript；无 TurnStarted / TurnEnded；activeTurn 保持 null |
| T35 | 挂起期任务保留 | TurnEnded 后 tasks 仍含 running 子代理 | 活动条不消失；再发消息照常 |
| T36 | 进程退出 | 子代理在跑时进程死 | 卡片 failed（summary `thincoder stopped`）；回合 interrupted；health failed |
| T37 | 非子代理 session_info_update | `_meta:{title}`（既有 unknown 场景） | 忽略（零回归） |
| T38 | 审批态 activity | async → turn → approval（detail = 工具名）→ approval（无 detail）→ settled | activity = `approval · <工具名>`；无 detail ⇒ `approval`；卡片 / 任务保持 running；settled 后定格 |
| T39 | 首帧即终态 | 首帧 = `settled` ∥ `stopped` | 建卡后即定格（succeeded + duration ≈ 0 / failed）；活动条无行（未建）；无残留 running |
| T40 | cancelled 于已建任务（契约外） | async → turn → cancelled | 卡片 ItemRemoved；任务行移除（无残留 running） |
| T41 | 终态 / 已移除后迟到报告（契约外，D31） | 已定格（`settled` / `stopped`）后同键再现 `queued` / `async` / `turn` / `approval`；卡片已移除（`cancelled`）后同键再现任何态（含 `settled` / `stopped` / `done` / 未知态） | 卡片不回动（已移除的不重建——含非四态）；活动条不复活（tasks 不变）；忽略 |

### 15.8 边界（批 4 不做）与登记（判定条件）

1. **digest 回合边界**：已闭合（批 8，§19）：CLI 发回合边界帧、桌面起 unprompted 回合（D26 随改写）。
2. **子代理内容归属**：批 5 已接（§16）——`_meta` 归属标（内容帧 + 工具帧）+ 卡片可点开只读视图（思考 / 正文 / 工具卡）；仍无 result / tokens / prompt（无来源）。
3. **控制面**：停止 / 转后台不做（D22）。判定条件：ACP 补子代理级 cancel / background 方法 ⇒ 声明 `RunsBackgroundTasks` + 接线点 ⑫⑬ 反转。
4. **父子嵌套**：扁平（最内段身份；父链不承载）。判定条件：协议面补 inner 链 ⇒ 卡片 children。
5. **顾问 / 评审（advisor）**：按 `role#id` 统一处理，不另设面（`role="advisor"` 也是子代理信号）。
6. `queued.kind`（slot / wait / depc）不接入机判（`detail` 原因文已在 activity 展示）。
7. **终态 / 已移除后同键报告（契约外）**：一律忽略，不回动任何面（D31）——已定格后四态（`queued` / `async` / `turn` / `approval`）同守；卡片已移除（`cancelled` 墓碑）后不止四态，任何后续报告（含 `settled` / `stopped` / `done` / 未知态）同一忽略（不按首见重建幽灵卡）。判定条件：thincoder 侧出现「同 id 重跑」的契约更新（重连 / 重放 / 重入队）⇒ 接续面重修（守卫反转：终态后报告按新子代理重建）。

### 15.9 UI / 交互决定（全部落地，无 open）

- 卡片 = 既有 `AgentStep`（`agent_step.dart:21`）：running = 装填动效 + shimmer + activity 行；完成 = meta 行（时长）；**可点**（有 chevron，批 5 起——§16.3）、无停止 / 转后台按钮（回调为 null 即不渲染，`:226-228`）。
- 活动条 = 既有 `ActivityStrip`：行 = 代号 + 计时 + 装填动效（`detail` 经 `agentOf` 命中才显示）；>3 个在跑折叠为计数行（既有 `_TasksHeader`）。行可点开该子代理的只读视图（`canOpenTask` 经 `agentOf` 按代号命中，批 5 起——§16.3）。
- 会话状态 = 侧栏 `shownStatus`（既有）：「回合已结束、子代理仍跑」显示运行中。
- 无新组件、无新 l10n 键（状态文案英文占位见 §14-15）。

---

## 16. 批 5：子代理内容归属（F12）

> 需求档 F12（批 5；用户 2026-10-16 裁定：允许动 thincoder 仓 · 走完整归属 · 保留拉代码能力）。
> 两半：**thincoder 侧**内容帧与工具帧带归属标（§16.1 钉死逐行 diff，由父侧 out-of-repo 轮执行）· **本仓**按标记路由进子代理只读会话（§16.2；UI 全复用既有面，§16.3）。

**最近先例（对齐 ∥ 偏离）**

先例 = 批 4 §15.2 / §15.9（本批承载面 = 批 4 建的卡片 / 活动条 / 只读视图）+ 实现坐标 `claude_code_translator.dart:419-423` `_putAgent`（children 聚合后原地 upsert）。

- **对齐**：children 承载子代理自己的条目、卡片按记录 id 原地替换（`_put` 同形）、只读面用既有 `SubagentFeed`——不新造 KernelEvent / 视图（E2）。
- **偏离 1 · children 条目由适配层自建（含工具卡）**：Claude 的 children 条目 id 来自协议（message id / tool_use id，按 `parent_tool_use_id` 分流）；thincoder 的内容帧不带条目 id（只有帧级 `role#id`）⇒ 条目按到达序自建（文本 / 思考片 + `toolCallId`），工具帧与内容帧同列。理由：工具帧若不入 children 会留在主对话（F12 ① 不成立）；另造条目 id 空间只为对齐先例 = 无收益。
- **偏离 2 · 256 字符节流**：Claude 的 children 随离散条目到达更新；thincoder 的内容是逐 chunk 增量，每次刷都重发整张卡片（含全部 children）= O(n²) 拷贝 + 同频重建 ⇒ 256 字符一刷 + 首块必刷（D34）。被否：每 chunk 刷；被否：定时器（无先例、固件不可断言）。
- **偏离 3 · 卡片 id 注入**：Claude 的 `AgentItem.id` = spawn 工具调用 id；thincoder 无 spawn 工具调用（卡片由 `session_info_update` 建）⇒ `AgentItem.id` = 记录 id `subagent:<role>#<id>`（一个标识两处用：记录键 + 开启入口），宿主 `id != null` 入口零改（D35）。

### 16.1 thincoder 侧：归属标（精确 diff · 可合并性）

一句话：两个内容回调与两个工具回调在 relay 前缀在场时，给同一条 `session/update` 带上 `update._meta["thincoder.dev/subagent"] = {role, id}`——与状态信号同键同源；内容面 / 工具面的可见字段与剥离语义零改。

**改动清单（一个代码档 + 五个文档位 + CHANGELOG；坐标 = 0.12.74 活树）**

| # | 坐标 | 改动 |
|---|---|---|
| a | `thincoder-cli/src/acp/bridge.mjs:67-78` | 抽出 `subagentIdentity(path)`（最内段 → `{role, id}`）；`subagentMetaPayload` 改用它（键序仍 role,id,state）；新增 `frameMeta(path)`（内容帧 / 工具帧共用） |
| b | `thincoder-cli/src/acp/bridge.mjs:236` | `agent_message_chunk` 加 `...frameMeta(path)` |
| c | `thincoder-cli/src/acp/bridge.mjs:243` | `agent_thought_chunk` 加 `...frameMeta(path)` |
| d | `thincoder-cli/src/acp/bridge.mjs:275-282` | `tool_call` 加 `...frameMeta(path)`（`path` = `:262` 已算的剥离结果） |
| e | `thincoder-cli/src/acp/bridge.mjs:287-291` | `tool_call_update` 加 `...frameMeta(parseRelayPath(name))`（归属按**原样名**解析；配对键是 `toolCallId` 计数器值，不是名——`bridge.mjs:108` `t${++toolSeq}`、`:286` `takeToolId(name, toolId) ?? toolCallId()`） |
| f | `thincoder/docs/cli/design/ACP-CLIENT.md` §5 表（`:171-172`） | 内容两行各补一句：relay 前缀在场 ⇒ 同通知带 `_meta` 归属标（§12.7）；文本面零改 |
| g | 同档 §7.2（`:314`） | 「工具卡 title 不带归属标」句改写：title 仍不带（显示面剥离），帧级 `_meta` 已带（§12.7） |
| h | 同档 §12.6（`:590`） | 「内容面归属不在本档」条改为指向 §12.7（该边界已闭合） |
| i | 同档 §12 尾（§12.6 之后） | 新增 `### 12.7 归属帧标（内容帧与工具帧）`：承载体 / 形状 / 规则 / 嵌套 / 重放面 / 结果面口径 |
| j | `thincoder/docs/cli/requirements/ACP-CLIENT.md:90-91` | R-A5.11 补一句：归属标（与「文本面剥离」并列，同键同源；含工具帧） |
| k | `thincoder-cli/CHANGELOG.md` 顶部 | 新增 `## [Unreleased]` + `### Added` 一行（内容见下） |

f–k 是契约档与需求档的**同拍义务**：代码改了而契约档不改，就是把一份说反的契约留在仓里（该仓对文档与代码同拍的通行做法）。

**代码 diff（逐字）**

```diff
--- a/thincoder-cli/src/acp/bridge.mjs
+++ b/thincoder-cli/src/acp/bridge.mjs
@@ -67,12 +67,21 @@
-/** 事件 token → `_meta["thincoder.dev/subagent"]` 载荷（§12.2 形状冻结——无值键缺席：
- *  progress/detail 键只在有值时在场；`state` = 事件名原文，形态域开集）。
- *  role/id = relay 前缀**最内段**（嵌套 `explore#1/eng-coder#2/…` ⇒ `eng-coder`/2——
- *  段形 `role#id` 由 parseRelayPath 保证）。 */
-function subagentMetaPayload(path, ev) {
+/** relay 前缀 → 子代理身份（§12.2 / §12.7 共用——最内段：嵌套
+ *  `explore#1/eng-coder#2/…` ⇒ `eng-coder`/2——段形 `role#id` 由 parseRelayPath 保证）。 */
+function subagentIdentity(path) {
   const inner = path.inner.length > 0 ? path.inner[path.inner.length - 1] : path.head
   const [role, id] = inner.split("#")
-  const meta = { role, id: Number(id), state: ev.name }
+  return { role, id: Number(id) }
+}
+
+/** 事件 token → `_meta["thincoder.dev/subagent"]` 载荷（§12.2 形状冻结——无值键缺席：
+ *  progress/detail 键只在有值时在场；`state` = 事件名原文，形态域开集）。 */
+function subagentMetaPayload(path, ev) {
+  const meta = { ...subagentIdentity(path), state: ev.name }
   if (ev.progress) meta.progress = ev.progress
   if (ev.detail) meta.detail = ev.detail
   return meta
 }
+
+/** §12.7：归属帧的标（内容帧 / 工具帧共用）——relay 前缀在场才带（`{role,id}`，无 state）；无前缀帧零变化。 */
+function frameMeta(path) {
+  return path ? { _meta: { [SUBAGENT_META_KEY]: subagentIdentity(path) } } : {}
+}
@@ -236 +245 @@
-      update("agent_message_chunk", { content: { type: "text", text: payload } })
+      update("agent_message_chunk", { content: { type: "text", text: payload }, ...frameMeta(path) })
@@ -243 +252 @@
-      update("agent_thought_chunk", { content: { type: "text", text: payload } })
+      update("agent_thought_chunk", { content: { type: "text", text: payload }, ...frameMeta(path) })
@@ -275,8 +284,9 @@
       update("tool_call", {
         toolCallId: id,
         title: shown,
         kind: inferToolKind(shown),
         status: "in_progress",
         rawInput: args ?? {},
         content: [contentBlock(JSON.stringify(args ?? {}))],
+        ...frameMeta(path),
       })
@@ -287,5 +296,6 @@
       update("tool_call_update", {
         toolCallId: id,
         status: "completed",
         content: [contentBlock(String(result ?? ""))],
+        ...frameMeta(parseRelayPath(name)),
       })
```

净增 11 行 + 2 行改写；不开新档、不动 import、不动 `package.json`。`SUBAGENT_META_KEY` 在 0.12.74 已存在（`bridge.mjs:65`）——diff 只复用，不引入新常量。

**新增 §12.7 的正文（逐字）**

```markdown
### 12.7 归属帧标（内容帧与工具帧）

- **承载体** = 两个内容变体 + 两个工具变体：`agent_message_chunk` / `agent_thought_chunk` / `tool_call` / `tool_call_update`；扩展位 = `update._meta["thincoder.dev/subagent"]`（与 §12.2 同键同源，载体级 `_meta`，schema 通用扩展位）。
- **形状**：`{ "role": "<relay 最内段主体>", "id": <integer ≥ 0> }`——**无 `state`**（归属标不承载状态；状态面仍只有 `session_info_update`，§12.3）。无值键缺席。
- **发射规则**（`bridge.mjs` 两个内容回调 + 两个工具回调）：`parseRelayPath` 命中 ⇒ 同一条通知带本标；未命中（主代理的帧）⇒ **零变化**（无 `_meta` 键）。
- **嵌套** = 最内段身份（与 §12.2 同规则）；父链不承载。
- **可见面零改**：内容 `content` 与工具 `title` / `kind` / `rawInput` / `status` 与今天逐字节相同——剥离语义照旧；不认本扩展的客户端忽略 `_meta`（`_meta` 通用条款「MUST NOT make assumptions」）即合规；协议版本 / `initialize` 形状 / 方法面零动。
- **重放面**（`replayHistory`，`bridge.mjs:389` 起）不加本标：重放走独立路径（不经过上面四个回调），还原来源 = 槽文件里的主会话历史（`agent.history`，`thincoder-core/session.mjs:200`）——逐条发 `user_message_chunk` / `agent_message_chunk` / `tool_call` / `tool_call_update`（`bridge.mjs:413` / `:436` / `:425` / `:441`）。
  子代理的流式内容只经 relay 回调到显示面（`spawn-child.mjs:147-164`），不写入主会话历史 ⇒ 重放不含子代理正文 / 思考 / 工具卡；主代理自己的工具卡（含 spawn 调用的结果文本）照旧还原——那是主对话自己的 tool result。
- **工具结果面**：子代理工具结果当前不经 ACP 转发（`onToolOutput` 不进桥；`wrapChildCallbacks` 不包装 `onToolResult`——`spawn-child.mjs:147-164`）⇒ 现网子代理只发 `tool_call`、不发 `tool_call_update`；更新侧同标已就位（结果通道就位即成对）。
```

**CHANGELOG 条目（逐字，落 `## [Unreleased]` → `### Added`）**

```
- **ACP 子代理归属标（§12.7）**：子代理的内容帧（`agent_message_chunk` / `agent_thought_chunk`）与工具帧（`tool_call` / `tool_call_update`）relay 前缀在场 ⇒ 同通知携
  `update._meta["thincoder.dev/subagent"] = {role,id}`（无 state）；可见面剥离语义零改（旧客户端忽略即合规）。
```

**安全底线逐条（为什么可合并）**

1. **可见面零改**：内容 `payload` / `content` 与工具 `title` / `kind` / `rawInput` / `status` 不动；不认扩展的客户端看到的东西与今天逐字节相同。
2. **状态路径行为零改**：`{...subagentIdentity(path), state: ev.name}` 的键序 = role,id,state（§12.3 的「字段序 = 发射侧单源」不变）；`progress` / `detail` 的追加逻辑逐行不动。
3. **无前缀帧零改**：`frameMeta(null)` 返回 `{}`，展开后通知形状与今天相同。
4. **重放面不动**：`replayHistory`（`bridge.mjs:389` 起；四个发射点 `:413` / `:425` / `:436` / `:441`）均不加标，历史重放零变化。
5. **嵌套**：最内段（与状态信号同源），§12.6 的「父链不承载」不变。
6. **工具帧同标、结果面不改**：`tool_call` / `tool_call_update` 与内容帧共用 `frameMeta`；子代理工具结果当前不经 ACP（`onToolOutput` 不进桥；`wrapChildCallbacks` 不包装 `onToolResult`——`spawn-child.mjs:147-164`）⇒ 现网只发 `tool_call`、不发 `tool_call_update`；本仓按「标了归属、无结果」展示（工具卡停在 in_progress），不伪造终态——见 §16.8-1。
7. **零格式化噪声**：不改注释排版、不重排既有行、不引依赖、不动版本号文件。

**版本口径（是否 0.12.75）**：**不预占号**。

该仓纪律 = 号在发布时定、开发期只挂 `[Unreleased]`
（`thincoder-cli/CHANGELOG.md:261` 的规则句：「号在发布时定、开发期不预占（CHANGELOG 挂 [Unreleased]）」）。
本轮落 `[Unreleased]`；发版时按连续号取号——若其间无其它发布，即为 0.12.75。

适配层**不加版本门**：归属能力按「`_meta` 键在场」探测（E3 / D13 口径），`thincoder_locator.dart:69` 的 `verifiedVersion` 仍 `0.12.74`，
不因本改动上调——旧版只是没有归属标（降级见 §16.2），不是能力不足。

**thincoder 侧验证（out-of-repo 轮执行，读数回本批 §5）**

1. 门禁：`node --check src/acp/bridge.mjs` · `npm run lint`（check-syntax 全树）· `npm test` · 仓根 `node scripts/doc-check.mjs --root .`。
   该仓测试清单 = 空且明文「零用例即绿」（`thincoder-cli/test/run.mjs:43-47`，2026-09-28 全清重置）⇒ **不向别人的空清单塞测试档**；本改动由下面的一次性探针 + 本仓固件（§16.7）双向钉形。
2. 一次性探针（**不落仓**；放 `thincoder-cli/.thincoder/tmp/probe.mjs`，跑完删）：

```js
// run from thincoder-cli/
import { buildAcpCallbacks } from "../src/acp/bridge.mjs"
const seen = []
const cb = buildAcpCallbacks({
  sessionId: "1", agent: {}, notify: (_m, p) => seen.push(p.update),
  request: async () => ({}), log: () => {},
})
cb.onToken("eng-coder#2/hello")
cb.onReasoning("explore#1/thinking")
cb.onToken("main text")
cb.onToken("eng-coder#2/⟦ev⟧turn\x1e3\x1e100\x1ellm\x1e")
cb.onToolCall("eng-coder#2/read", { path: "a.dart" })
cb.onToolResult("eng-coder#2/read", "ok")
cb.onToolCall("bash", { command: "ls" })
console.log(JSON.stringify(seen, null, 1))
```

   期望（逐条比对，`_meta` 在 update 级）：
   ① `agent_message_chunk` text `hello` + `_meta:{…:{role:"eng-coder",id:2}}`；
   ② `agent_thought_chunk` text `thinking` + `_meta:{…:{role:"explore",id:1}}`；
   ③ `agent_message_chunk` text `main text`，**无** `_meta`；

   ④ `session_info_update` + `_meta:{…:{role:"eng-coder",id:2,state:"turn",progress:{turn:3,maxTurns:100}}}`；
   ⑤ `tool_call` title `read`、kind `read`、status `in_progress` + `_meta:{…:{role:"eng-coder",id:2}}`；

   ⑥ `tool_call_update`（`toolCallId` = ⑤ 的 id）status `completed` + 同一 `_meta`；
   ⑦ `tool_call` title `bash`，**无** `_meta`。

**out-of-repo 轮执行顺序（给父侧）**

1. `cd D:\baocode\thincoder`（活树 0.12.74）→ 新建分支（如 `acp-subagent-content-meta`）。
2. `cd thincoder-cli && npm ci`（活树无 `node_modules`，实核）。
3. 落 a–e 代码 diff（按符号定位，行号会漂）。
4. 落 f–k 文档与 CHANGELOG。
5. 跑上面的门禁 + 探针，读数原样入批次档 §5。
6. 提交（**不发布**）；发布与否由用户裁定。
7. 走查前把桌面 `thincoder.path` 指到该检出的 shim（`npm link` 后取全局 `thincoder`，或直接指 `bin/thincoder.cjs`）——未发布版本照样能走查，因为适配层不按版本判能力。

### 16.2 本仓路由（翻译层 → 子代理只读会话）

一句话：内容帧与工具帧带归属标 ⇒ 改写进那条子代理的记录（`AgentItem.children`），主对话零混入；无标记 ⇒ 照旧进主对话。

**入口**：`thincoder_events.dart` 的 `update()` 里两条内容分支改走 `_content(update, piece)`、两条工具分支先过同一归属判定（`_owner(update)`），其余分支不动。`_owner` 按 `update._meta` 的四种形态判定（内容帧 / 工具帧共用，留痕集也共用）：

| `update._meta` 形态 | 处置 | 理由 |
|---|---|---|
| 无 `_meta` 键 | **主对话**（既有 `_chunk`） | 旧 CLI（0.12.74）与主代理的帧 |
| `_meta` 非映射 ∥ 无 `thincoder.dev/subagent` 键 | **主对话**（同上） | 不是本扩展的标记（别的扩展位），无从判归属 |
| 本键在场，`role` 不是非空串 ∥ `id` 不是非负整数 | **丢弃** + 留痕（每次运行至多一条） | 标了归属却点不出人；放进主对话正是要修的污染 |
| 本键在场且身份完整 | **归入** `subagent:<role>#<id>`（下表） | — |

**归入规则**

| 记录状态 | 处置 |
|---|---|
| 卡在场、在跑 | 追加到它的谈话 |
| 卡不存在（内容先于状态信号） | 先按「首见」建卡（`description = <role>#<id>`、`id = subagent:<role>#<id>`、`startedAt = now`、`background: true`、running），再追加 |
| 卡已定格（succeeded / failed） | 丢弃 + 留痕（每键至多一条；D31 同口径） |
| 键在 `_removed`（`cancelled` 墓碑） | 丢弃 + 留痕（每键至多一条；不按首见重建） |

**工具帧路由（`tool_call` / `tool_call_update`；与内容帧同判定）**

| 帧 | 处置 |
|---|---|
| `tool_call`（带标、身份完整） | 封该子代理的谈话片（等价主对话 `closePiece()`——只关它的片，不碰主对话在飞片）；`_tool(kind, title, raw)` 既有构造 ⇒ 追加进 children（卡不存在 ⇒ 同内容帧首见建卡）；`_childTools[toolCallId]` 记项位；卡片 upsert |
| `tool_call_update`（带标） | 按 `_childTools[toolCallId]` 原位替换（复用既有 `completed` → succeeded / `failed` → failed 的转换）；未命中（无调用帧 ∥ 调用帧无标）⇒ 丢弃（既有 `_toolUpdate` 同口径：无前项无可替换） |
| 无 `_meta` ∥ 非本键 | 走既有主对话路径（`_tools` / `_toolUpdate`，零改） |
| 本键坏身份 | 丢弃 + 留痕（与内容帧共用留痕集） |
| 卡已定格 ∥ 键在 `_removed` | 丢弃 + 留痕（每键至多一条；D31 口径） |

**键命名空间（`_childTools`）**：键 = 帧里的 `toolCallId`，由桥在会话内用单一计数器生成（`t1, t2, …`——`bridge.mjs:108`；同档注释 `:20`），不派生自 relay 名 ⇒ 子代理之间、子代理与主代理之间在同一连接内全局唯一，不会互撞。

**结果不回传的处置（判据）**：子代理工具结果不经 ACP（`onToolOutput` 不进桥、`wrapChildCallbacks` 不包 `onToolResult`——`spawn-child.mjs:147-164`），被归属的 `tool_call` 之后不会来 `tool_call_update` ⇒ 视图内工具卡停在 `in_progress`（`ToolStatus.running`、无结果行）。

**保持 `in_progress`，不按子代理终态改写**：结果与成败都未知，定格为 succeeded / failed 是编造；与批 1 起主对话的既存形态同形（本批只改归属、不改工具卡状态语义）。子代理定格后视图只去掉活动指示（`LiveStatusItem`），工具卡原样——走查按此观察（§16.9）；登记 §14-16。

**谈话表与流式**

- 每条子代理记录一份谈话表 `_Tape { _Piece? open; DateTime? since; StringBuffer text; List<ChatItem> items; int shown; }`；`items` 的末项 = 正在写的那片；工具卡入 `items` 前先封片 ⇒ children 与 items 同一条列表；工具卡入列即刷（结构项，不走字符节流）。
- 片语义与主对话同：text / thought 交替即分项（`AssistantTextItem` / `ThinkingItem`）；每片首块必落 `items`。
- **节流**：`static const _tapeFlush = 256`——首块必刷，其后「已写字符 − 已展示字符 ≥ 256」才刷；任何状态报告、回合收束、进程收束先刷。理由：每个 chunk 都重发卡片 = 每次拷贝该子代理全部已产出文本（O(n²) 拷贝 + 同频重建）；256 字符一刷把代价降到 1/64 量级，而视图滞后 ≤256 字符。被否：每 chunk 重发（代价）；被否：定时器节流（翻译层无定时器先例，且固件无法确定性断言）。
- **主对话的在飞片不受影响**：子代理内容与工具帧都不碰主的 `closePiece()` / `_pieceText`（主代理的文本流不因子代理插话 / 工具调用被切段）。
- 谈话表**跨回合存活**（与批 4 子代理表同）：`begin()` 不清；`endSubagents()` 先刷后清（连同 `_removed` 与留痕集）；`cancelled` 连表一并移除。

**卡片可点（D35）**：`AgentItem.id = 'subagent:<role>#<id>'`（= 记录 id）。宿主的开启入口按 `id != null` 出现（`chat_history_view.dart:1464-1468`），
`SubagentFeed` 按 id 找回卡片并读 `children`（`chat_feed.dart:67-111`）⇒ **UI 零改**。

停止 / 转后台仍不出现：`stopAt` / `moveToBackgroundAt` 走 `_runningTask(id)`，thincoder 任务无 `toolUseId` ⇒ 恒 null（D22 不变）。

**降级矩阵**

| 情形 | 桌面表现 |
|---|---|
| CLI 0.12.74（无归属标） | 与批 4 一致：子代理内容与工具卡进主对话；不报错、不提示、不留痕（每帧留痕会刷屏） |
| 新 CLI + 未升级的桌面 | 桌面忽略未知 `_meta`（本适配现状）⇒ 与今天一致 |
| 新 CLI + 新桌面 | F12 目标行为 |
| `session/load` 重放（任何 CLI 版本） | 重放帧不带归属标（§16.8-7）：还原的是主会话历史（用户块 / 助手文本 / 主代理工具卡），不含子代理流式内容与子代理工具卡 |

### 16.3 UI / 交互决定（全部落地）

- **卡片**：有 chevron、可点击 / 回车打开（既有 `AgentStep.onOpen`）；无停止 / 转后台按钮（§16.2 末）。
- **只读视图**：既有 `SubagentFeed` + `SubagentHeader`（返回 / 面包屑）+ 既有条目渲染；无输入框（`chat_screen.dart:787` 既有条件）；Esc 返回（既有）。
- **视图内容** = 该子代理的思考、正文与工具卡，按到达序；**无** prompt / result / tokens / toolUses / model（无来源，D21 残余）。运行中末尾是既有 `LiveStatusItem`。
- **视图内的工具卡**：= 协议 `tool_call` 的原样形态（`in_progress` / `ToolStatus.running`），无结果行（结果不回传，§16.8-1）；子代理定格后不改写为终态（不伪造成败）。走查按「终态后工具卡可仍显示进行时」观察，不视为缺陷。
- **活动条行同入口**：`agentOf`（`chat_session.dart:682-711`）按 description 命在跑的子代理 ⇒ 行可点开同一视图、`detailOf` 显示其 activity（既有语义，D35）。
- **卡片尾行的让位**：`AgentStep.latest()`（`agent_step.dart:91-98`）按「children 末项首行 → activity → prompt」取行 ⇒ 有内容后卡片尾行随其内容：末项是正文 ⇒ 该正文首行；末项是思考 ⇒ 既有 `thinkingTitle`（`Thought for Ns`，`chat_item_view.dart:162-171`）。
- 状态行（`turn n/max` / `approval · …`）在无内容时照旧出现，活动条 summary 始终是状态行。**既有宿主语义，不改**（D36；父侧 2026-10-16 已确认）——走查按此观察。
- 无新组件、无新 l10n 键（视图内文案全为既有）。

### 16.4 受影响文件清单（E2 增量；编制日行数 = 2026-10-16 快照）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ⑲ | `lib/kernel/thincoder/thincoder_events.dart`（638 行） | 内容帧与工具帧归属路由（§16.2）：`_content` / `_owner` 分发 / 谈话表 `_Tape` / 工具卡入列（`_childTools`）/ 节流 / 留痕集；卡片 `id` 由 `_openCard` 承载（`:665`）、`children` 由 `_card` 承载（`:550`）；`_putSubagent` 签名不变；`endSubagents` / `cancelled` 清表 | ≤ +140（⇒ ≤778） |
| ⑳ | `test/kernel/thincoder_kernel_test.dart`（1537 行） | T42–T50（§16.7），mock 直驱（`ThincoderMock.push` 既有，零 mock 改动） | 预估 ≤ +200（⇒ ≤1737）；实交 +308（⇒ 1845） |
| ㉑ | `test/kernel/thincoder_fixtures_test.dart`（191 行） | `_check` 增 `agents` 键 + `_children` 辅助（思考 / 正文 / 工具卡各一行） | ≤ +20 |
| ㉒ | `test/fixtures/thincoder/subagent-content.ndjson` · `subagent-content-legacy.ndjson` | 新增 2 个固件（带标〔内容 + 工具帧〕/ 不带标） | 新增 |
| ㉓ | `test/fixtures/thincoder/README.md` | `expect.agents` 键说明 + 两固件来源 | +3 |

- 零改动：`thincoder_kernel.dart`（`endSubagents()` 已在位，`:357`）· `lib/chat/**` · `lib/kernel/claude_code/**` · `thincoder_mock.dart` · `thincoder/`（嵌套独立仓；由 out-of-repo 轮在它自己的仓里改，§16.1）。
- 体量：`thincoder_events.dart` 638 → ≤778，仍 < 800 硬顶 ⇒ **本批不拆（显式裁定）**：该缝须在本批内保持完整——`_Tape` / `_childTools` 与 §15.2 的状态机同批耦合（首见建卡 / 定格 / 墓碑共用一张表），拆开本批要同时改两处结构。
  拆分触发 = 独立拆分批立项（判据 = 子代理段的下一次独立重构）；本批的归属路由不构成触发——本裁定只覆盖本批，交付后失效，此后按缺省触发口径办。`thincoder_kernel_test.dart` 已在 >800 名单（缝候选 = 按 group 拆，§15.4），本批只加用例、不动结构；实交 +308（⇒ 1845）仍在名单上（估算偏紧的用例面：T43 双代理 + 节流 / T45 五形 / T48 跨回合 + 进程 + 重启 / T50 五子场景），结构不动。
- out-of-repo 档：`thincoder-cli/src/acp/bridge.mjs`（0.12.74 活树实核 449 行，2026-10-16 只读读数）⇒ 净增 11 行 + 2 行改写后 ≈460 行，未触 500 / 800 两档；该档由 out-of-repo 轮在它自己的仓改，不在本仓受管文件表内，行数只按增量注记。

### 16.5 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D32 | 归属标 = 同键 `thincoder.dev/subagent`、载荷 `{role,id}`（无 state） | 需求档 F12 原文；同键 = 客户端一条解析路径、一处文法；无 state = 归属标不承载状态（内容帧 / 工具帧同此）。被否：新键（第二套契约面，双份维护） |
| D33 | 归入 `AgentItem.children`，不新造子代理会话模型 | `SubagentFeed` 读的就是 children（`chat_feed.dart:77-92`）+ 卡片 id 即可点开（`chat_history_view.dart:1464-1468`）⇒ UI 零改；先例 = Claude `_putAgent`（`claude_code_translator.dart:419-423`）。被否：新 KernelEvent / 新视图（宿主契约扩张，违背 E2） |
| D34 | 节流 = 256 字符一刷 + 首块必刷；冲刷触发 = 状态报告 / 回合收束 / 进程收束（§16.2），另 `closePiece()` 顺带也刷（`thincoder_events.dart:198`——主对话收束 / 换片时捎带，行为无害：有界、节流上界不变） | 每 chunk 重发 = O(n²) 拷贝 + 同频重建；首块必刷保证「点开即有内容」。被否：每 chunk 重发；被否：定时器（无先例 + 固件不可断言） |
| D35 | 卡片 `id` = 记录 id（可点）；活动条行随之可点 | 一个标识两处用（记录键 = 卡片 id）；宿主既有点击入口直接生效；D22 不受影响（停止仍需 `task.toolUseId`，恒空） |
| D36 | 卡片尾行让位 children（既有 `latest` 语义） | 不改全局 `AgentStep.latest`（Claude 面回归风险）；F12 ③「状态面不变」= 三个面（卡片 / 活动条 / 状态行）的存在与语义不变，不含「卡片尾行按 children 显示」这一既有行为：尾行变为内容（正文首行 ∥ `Thought for Ns`），状态行仍由活动条 summary 承载。**已确认（父侧 2026-10-16）：批 4 既有 `AgentStep.latest()` 语义照旧。** |
| D37 | 坏身份标记 = 丢弃 + 一次留痕 | 标了归属却点不出人的帧，放主对话 = 复现待修的污染；静默丢弃违背 E4 ⇒ 留痕（每次运行一条，防刷屏）。被否：fail-open 进主对话 |
| D38 | 旧 CLI 不报错、不加版本门 | 能力按键在场探测（E3）；版本门会把「没升级的终端」变成错误，而其退化结果就是现状 |

### 16.6 验收对照（回指需求档 F12）

| F12 条目 | 本档落点 | 判据 |
|---|---|---|
| ① 主对话无子代理内容与工具卡 | §16.2 路由 + T42 / T43 / T49 / T50 | 固件零混入；走查① |
| ② 卡片可点开，见该子代理的思考 / 正文 / 工具卡 | §16.3 + T42（`id` 与 children）+ T50 | 走查②；视图 = 既有 `SubagentFeed` |
| ③ 状态面（卡片 / 活动条 / 状态行）不变 | §16.2（状态路径零改）+ T28–T41 全绿 | 卡片状态 / 图标 / 活动条行 / 侧栏照旧；尾行让位 = D36（已确认），走查③确认 |
| ④ 无标记内容照旧进主对话 | §16.2 降级矩阵 + T44 + `subagent-content-legacy` 固件 | 旧 CLI 零报错零留痕 |
| 边界：不动 thincoder 其它行为、保留 pull | §16.1「安全底线逐条」+ 探针 | 内容 / 工具可见面与状态形状、重放面零改；无格式化噪声；diff 仅 5 处（1 辅助 + 4 调用点） |

### 16.7 用例表（正常 / 边界 / 错误；固件场景同名）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T42 | 单子代理内容归入 | `async` → 带标 thought → 带标 text | 主对话只有卡片；`children` = [thought, text]；`AgentItem.id = subagent:eng-coder#2` |
| T43 | 两子代理交错 + 节流 | A：一块 300 字；B：三块各 100 字；随后一条带标状态帧（如 `turn`） | 状态帧**前**读 children：A = 300（首块必刷；300 ≥ 256 已刷）；B = 100（首块必刷，其后累计 300 而差值 200 < 256 未刷）；状态帧**后**读 = 300（状态报告先冲刷）；两条记录互不串 |
| T44 | 无标记（旧 CLI） | text 无 `_meta` | 进主对话；children 空；零留痕（零回归） |
| T45 | 坏标记（四形） | `_meta` 非映射 / 无本键 / `role` 非串 / `id` 非整数 | 前两形进主对话（视作无标记）；后两形丢弃 + **每次运行至多一条**留痕；主对话零新增 |
| T46 | 内容先于状态 | 带标 text → `async` | 先建卡（running）再推进任务行；children 保留 |
| T47 | 已移除 / 已定格后内容 | `cancelled` → 带标 text；`settled` → 带标 text | 丢弃；卡片不回动、不复活；每键一条留痕 |
| T48 | 跨回合与进程收束 | 第二回合再出内容；随后进程死 | `begin()` 不清 children；卡片定格 failed 且 children 保留（表随后清空） |
| T49 | 主对话片不被截断 | `async`（建卡）→ 主文本 a → 带标 text → 主文本 b | 主文本仍在同一项（offset 连续，不因插话分项） |
| T50 | 工具帧归入 + 主对话零工具卡 + 坏标记四形 | `async` → 带标 `tool_call`（read）→ 带标 `tool_call_update`（completed）；主代理自身 `tool_call`（无标）；另一子代理带标 `tool_call`；坏标工具帧四形（同 T45） | 带标 call / update 只进该子代理 children（原位换成终态），主对话零出现；主代理工具卡照旧；三方 `toolCallId` 互不相撞（单计数器）；坏标前两形视作无标、后两形丢弃 + 留痕（同 T45）；已定格 / 已移除后丢弃 + 留痕（D31） |
| 固件 | `subagent-content` · `subagent-content-legacy` | 带标 / 不带标两种录制 | `expect.agents`（含 children 内工具卡）与 `expect.items` 逐行（§16.4 ㉑ 的 `agents` 键） |

### 16.8 边界（批 5 不做）与登记（判定条件）

1. **子代理工具帧的结果面**：归属已接（本批）——`tool_call` / `tool_call_update` 与内容帧同标、同路由（§16.2）；`tool_call_update` 侧现网不出现（结果不经 ACP）。
   剩余 = **结果面**：子代理工具结果不转发（`onToolOutput` 不进桥；`wrapChildCallbacks` 不包 `onToolResult`——`spawn-child.mjs:147-164`）⇒ 视图内工具卡停在 `in_progress`（不伪造终态：结果与成败均未知，§16.2）。判定条件：thincoder 补子代理工具结果转发（`tool_call_update` 走同标 ∥ ACP 面新增输出通知）⇒ `tool_call_update` 路由已就位自动闭合，输出通知另接一处。
2. **prompt / result / tokens / toolUses / model**：无来源（D21 的字段来源分组：这五类仍无来源；`id` / `children` 已由 D35 / D33 接）⇒ 只读视图只有思考 / 正文 / 工具卡。判定条件：协议面补这些字段。
3. **父子嵌套**：仍扁平（最内段身份；父链不承载）。判定条件同 §15.8-4。
4. **内容不落盘**：谈话表在内存，随进程（`endSubagents()` 清）。重开桌面 / 换内核后卡片只剩状态、无 children。判定条件：用户要「事后回看子代理内容」⇒ 另立持久面（会话存档无此字段）。
5. **长输出内存**：children 留驻该子代理本次会话的全部文本（同 Claude children 先例）；判定条件：实测大子代理会话内存显著 ⇒ 加上界（头 / 尾截断）。
6. **内容先建卡**：无状态信号时按 running 起、进程退出按 D30 定格 failed。判定条件：观察到幽灵 failed 卡 ⇒ 改「状态未到的内容不建卡」（丢弃 + 留痕）。
7. **`session/load` 重放面**：重放走 `replayHistory` 独立路径（`bridge.mjs:389` 起）、不加归属标；还原来源 = 主会话历史 ⇒ 只含用户块 / 助手文本 / 主代理自己的工具卡，不含子代理的流式正文 / 思考 / 工具卡（子代理内容只经 relay 回调到显示面，`spawn-child.mjs:147-164`，不写主会话历史）。判定条件：thincoder 若把子代理内容写入主会话历史（或重放改走四个回调）⇒ 重放帧按 §16.2 同一判定路由（`_owner` 已就位）。
   今日重放帧不带标 ⇒ `_owner` 的归属分支对重放不可达；上述判定条件触发时（重放帧带标），它们按 §16.2 同一判定路由——内容帧（含 `user_message_chunk`）在该子代理谈话里按正文渲染（谈话表不分角色，`thincoder_events.dart:710-715`），不还原为历史消息形态。

### 16.9 真机走查步骤（多子代理并发；A 段交付时执行）

1. 装含本改动的 CLI（本地 `npm link` 或发布版），`thincoder.path` 指对；登录；桌面新建 thincoder 会话。
2. 发一条并行派 2–3 个子代理、且主代理同时继续说话的指令（如「用三个 subagent 并行查三块内容，你同时总结进度」）。
3. 验①：整段流式期（≥2 分钟）主对话只出现主代理的正文 / 思考 / 工具卡 / 子代理卡片——子代理的正文、思考与工具卡**零混入**。
4. 验②：点任一子代理卡片（有 chevron）⇒ 打开只读视图，见该子代理自己的思考、正文与工具卡（运行中滚动跟随；工具卡无结果行，§16.8-1）；Esc / 返回回到原会话，会话继续流式。
5. 验③：卡片状态图标 / 活动条行 + 计时 / 侧栏「运行中」照旧；卡片与活动条行都**没有**停止 / 转后台按钮；卡片尾行随其内容（正文首行 ∥ `Thought for Ns`，D36），状态行仍在活动条 summary。
6. 验④：把 `thincoder.path` 指回 0.12.74（或卸载 link）重开一段 ⇒ 主对话照旧混入子代理内容与工具卡（= 现状），**不报错、不提示**。
7. 结算后：子代理视图仍可回看内容；活动条行消失；卡片定格（时长）。再点活动条行 / 卡片同入口可验 `agentOf` 命中一致。

---

## 17. 批 6：审批自动档 + 模型清单与思考档位（F13 / F14）

> 需求档 F13 / F14（批 6；用户 2026-10-16 20:07 裁定「开」；同日 21:09 二次裁定「和终端同源」⇒ 主线 = CLI 侧 `agent.autoApprove` 暴露成 config option，桌面只显示与切换服务端回报）。
> 两半：**thincoder 侧**（§17.1-① 与 §17.3-①② 的投影；父侧 out-of-repo 轮执行）· **本仓**（§17.1-③ 审批面 + §17.3-③ 档位面；适配层 + 宿主 1 档——composer 右下角的小开关，§17.4 ㉗）。P0（桌面内核自答）= 兜底，只留判据（§17.2）。

**最近先例（对齐 ∥ 偏离）**

先例 = F5 的三面（§4 F5：`mode` / `model` / `thinking` 全由回报驱动，D20 不乐观改）+ Claude 的审批面与 effort 列表（`claude_code_kernel.dart:2788-2798` 的 `permission`、`:2644-2670` 的 `_approvals`、`:2801-2818` 的档位列表：`toggle: false` + `effortLabel`）+ 批 5 §16.1 的 out-of-repo 写法（逐行 diff / 探针 / 门禁 / 不预占号）。

- **对齐**：新开关走宿主**现成的** `SelectsPermission`（`agent_kernel.dart:130-132`：「How the agent's actions are approved」），档位走现成的 `SelectsEffort` 列表形态——接口与事件都不新造（E2）；放置沿用 composer 工具条右端（`_ContextRing` 的位）。
- **偏离 1 · 「上报即显示」只对已接线的 configId 成立**：桌面读 `configOptions` 的面是**固定**的——`mode` / `model` / `thinking` 三处（`thincoder_kernel.dart:681-720`），`chat_session.dart:370-377` 也只收 `SelectsContextSize` / `SelectsEffort` / `SelectsFast` 三个接口；新 id 只进 `_events.options`（`thincoder_events.dart:169-188`），不产生任何 UI。
  故 F13 的桌面面 = 适配层实现 `SelectsPermission`（既有接口）+ 宿主 composer 一处放置（用户 2026-10-16 21:25 定形：右下角紧凑开关，不是左簇菜单 pill，§17.1-③）。需求档 F13 的「上报即显示开关」按此口径读：能力上报即点亮，需要适配层接线 + 宿主这一处开关。
- **偏离 2 · 思考档位 = 新 id 并行投影，不改 `thinking` 的形状**：§17.3-② 给判据（旧桌面按布尔读 `thinking`）。

### 17.1 F13 · 审批自动档（主线：服务端真值 + 桌面回报驱动）

一句话：CLI 把 `agent.autoApprove` 做成 `configOptions.autoApprove`（boolean）；桌面用 composer 右下角的小开关显示它、切换它。开着 ⇒ 核在审批阶段之前短路，请求根本不到桥 ⇒ 无面板、无逐次点头；关着 ⇒ 逐次问。

**① CLI 侧（thincoder 仓）**

关键事实：桥的 `onPermissionRequest`（`bridge.mjs:305-336`）**不需要**加「autoApprove 真 ⇒ 自答 approve」分支——核的 `dispatch.mjs:167-186` 已在审批阶段之前短路，判据行 `:177` 含 `agent.autoApprove`；只有进 `permPending` 的调用才走到 `onPermissionRequest`（`:187-198`）。

所以「开着不问客户端」在 0.12.74 已成立，缺的只是**把这个位暴露出来**；桥侧再加自答 = 死代码（D40）。旁证：子代理的工具问句也吃父的位（`subagent-actions.mjs:205`：`parent.autoApprove ? async () => true : askPermission`）。

改动清单（一个代码档 + 一个注释位 + 契约档/CHANGELOG；坐标 = 0.12.74 活树；模型清单与档位的装配改动见 §17.3）：

| # | 坐标 | 改动 |
|---|---|---|
| a | `thincoder-cli/src/acp/handlers-session.mjs:33-53` `sessionConfigOptions` | 尾部追加 `{ id: "autoApprove", name: "Auto-approve tools", type: "boolean", currentValue: agent?.autoApprove === true }`；档注释（`:36-39`）序改为 `model → thinking → thinkingLevel（有思考面时）→ mode → autoApprove`（终态；见 §17.3） |
| b | 同档 `:112-146` `applyConfigOption` | 新增 `case "autoApprove"`：非 boolean ⇒ `false`；否则 `agent.autoApprove = value` ⇒ `true` |
| c | `thincoder-cli/src/acp/bridge.mjs:305-309` | **仅注释一行**：autoApprove 真时请求已在核 `dispatch` 阶段短路（`dispatch.mjs:177`），本回调收不到——行为零改，防后来者在此加重复分支 |

代码 diff（逐字；行号按分支定位，会漂）：

```diff
--- a/thincoder-cli/src/acp/handlers-session.mjs
+++ b/thincoder-cli/src/acp/handlers-session.mjs
@@ -36,7 +36,7 @@
- *  model（在位时）→ thinking → mode。 */
+ *  model（在位时）→ thinking → thinkingLevel（有思考面时）→ mode → autoApprove。 */
@@ -50,6 +50,7 @@
   opts.push({ id: "mode", name: "Mode", type: "select", currentValue: agent?.planMode ? "plan" : "normal",
     options: [{ value: "normal", name: "Normal" }, { value: "plan", name: "Plan" }] })
+  opts.push({ id: "autoApprove", name: "Auto-approve tools", type: "boolean", currentValue: agent?.autoApprove === true })
   return opts
 }
@@ -138,6 +139,10 @@
     case "mode": {
       if (value !== "plan" && value !== "normal") return false
       agent.planMode = value === "plan"
       return true
     }
+    case "autoApprove": {
+      if (typeof value !== "boolean") return false
+      agent.autoApprove = value
+      return true
+    }
```

净增 5 行 + 1 行注释改写；不开新档、不动 import、不动 `package.json`。

**② 值从哪来、落到哪（「和终端同源」的判据）**

- **起点**：`agent.autoApprove` 默认 false（`thincoder-core/agent.mjs:55`）；`session/new` 直建会话、不读槽（`handlers-session.mjs:193-195`）⇒ 新会话默认关，与终端一致（终端新会话也默认关）。
- **终端 → 桌面**：`session/load` / `resume` 走 `applySession`（`handlers-slots.mjs:112` / `:177`）⇒ `agent.autoApprove = data.autoApprove ?? false`（`session-lifecycle.mjs:119`）⇒ 槽里开着，ACP 会话就开着，`configOptions` 如实报出。
- **桌面 → 终端**：`set_config_option` 只改内存（与 model / thinking 同口径，`:107-111`），落盘靠**既有的**回合末存档（`acp/session.mjs:111` `save(agent)` → `thincoder-core/session.mjs:155` 写 `autoApprove`）⇒ 终端下次打开同槽读到的就是它。**不新增写盘路径**。
  - 精度：开关后**没发消息就关窗口** ⇒ 不落盘（本回合没发生）。走查按「开关 → 发一条 → 再看终端」验（§17.9-④⑧）。
  - 同槽两窗口 = last-write-wins，各自内存态不互推（与今天终端两开一致）。

**③ 桌面侧（本仓；宿主 1 档 = composer 的右下角开关）**

- `ThincoderKernel` 增实现 `SelectsPermission`，`permission` 两项（`description` = tooltip 的第二句；`label` / `icon` 留在数据面，开关面不渲染——见下「无文字 label」）：

| id | label | 图标 | description | 备注 |
|---|---|---|---|---|
| `ask` | `Ask` | `Icons.front_hand_outlined` | `Ask before each tool call` | — |
| `auto` | `Auto` | `Icons.fast_forward_rounded` | `Tools run without asking — the same switch as /auto in the terminal` | `caution: true`（数据面语义 = 有风险；本面不取色，见下「颜色」） |

- `options` = `configOf('autoApprove') == null ? [] :` 上表两项 ⇒ **旧 CLI 无此项 ⇒ 空表 ⇒ `ChatSession.permissions == null`（`chat_session.dart:370-373`）⇒ composer 不出现该开关（零变化）**。
- `selected` = `configOf('autoApprove')['currentValue'] == true ? 'auto' : 'ask'` ⇒ **只读回报**（D20；点完等 `config_option_update`）。
- `select(id)` ⇒ `_config('autoApprove', id == 'auto')`（`thincoder_kernel.dart:807-819` 的 `_config` 已收 `Object?`，boolean 直传；回包 / 通知都经 `_events.optionsFrom` 刷新，`thincoder_events.dart:140-157`）。
- **写失败面**：`_config` 既有 `try/catch`（`thincoder_kernel.dart:808-818`）⇒ 服务端回错时显示保持回报值、零异常、连接与回合不受影响；留痕 = `appEvent('thincoder', …)`（`:817`），不新增路径。用例 T59。

**形态与放置（用户 2026-10-16 22:12 定形：拨动开关）**

- **通用规则，不特判内核**：`permission.options.length == 2` ⇒ **右下角拨动开关**（`selected.id == options[1].id` = 开，`options[0].id` = 关）；否则（≥3 项，如 Claude 的 5 档）⇒ 左簇既有 `ComposerPicker` 菜单——Claude 的 UI 逐字不动。0 项 ⇒ `permissions == null`（无控件）；1 项 ⇒ 走菜单（同今天）。
- **位置**：`_buildToolbar` 右端（`composer.dart:1869-1879`），`_ContextRing` 左侧、`SizedBox(2)` 邻接；无环（`context == null`）时同样贴发送钮左侧 2px。开关态下左簇跳过审批 pill（主 composer：左 = 模式 + 模型，与用户的截图一致）。放置与邻接不随形态改。
- **形状与几何**：track = 胶囊 **35 × 20**、圆角 **10**（= 高 / 2）；knob = 圆、**直径 16**，左右内缩 **2**。逐项照既有开关 `IdeSwitch`（`lib/ide/ide_switch.dart:44-84`）：宽 = 高 × 1.75（`:64`）、knob = 高 − 4（`:48`）、`padding: EdgeInsets.all(2)`（`:66`）、圆角 = 高 / 2（`:70`）、换位用 `alignment: value ? centerRight : centerLeft`（`:67`）。
  高取 20：在用户给的 18–20 内，且落在工具栏既有高度里（`_ContextRing` 23×22，`composer.dart:1990-1991`；发送钮 24×24，`:2102-2103`）。用户建议的 knob「高 − 6 / 内缩 3」按既有开关的「高 − 4 / 内缩 2」统一——同一个应用的两个开关不该有两套内缩。
- **态：位置即状态**。**关 = knob 在左、track 无填充**（`Colors.transparent` + 1px `AppColors.textFaint` 描边，`app_theme.dart:142`），knob `AppColors.textMuted`（`app_theme.dart:139`）。
  **开 = knob 在右、track 填充橙色**，knob `themeColors['button.foreground']`（既有填充按钮上的前景色，`ide_switch.dart:47`；同 `_SendButton` 的图标色，`composer.dart:2081`）。
  关态的 1px 描边只让「左」这个位置读得出来，不是状态信号——没有它，一颗灰圆看不出是开关。
- **颜色：橙 = `AppColors.autoTrack`，值 `0xFFE2B373`**（`app_theme.dart` 新增常量；取色自用户 2026-10-16 23:37 指定的参照图 pill 底色 `#E2B373`，逐像素实读）。早前借 `AppColors.claude`（`0xFFD97857`）作暖橙的方案已被该指示取代；其余橙都在别域，不跨域借（`stash_editor.dart:141` 标签色板、`extension_widgets.dart:462` 市场五星兜底）。
  被否 `caution` = `editorWarning.foreground`（`app_theme.dart:194-196`）：用户 2026-10-16 21:39 明确不要警示色——auto 是用户主动选的省事档，不是警告；拿警示色画开关，等于把「有风险」写在上面。

  被否 `button.background`：出厂两套主题都是蓝（`workbench_theme_initial_colors.dart:22` `#0078D4` / `:164` `#005FB8`）——不是橙，且随主题漂移。
  被否 `button.secondaryHoverBackground`：那套信号是「有没有底色」；换成 track + knob 后 track 要一个固定色相，主题灰每换主题就变。
- **动画**：位置与底色各一个 `AnimatedContainer`，**140ms · `Curves.easeOut`**——逐字照 `IdeSwitch`（外层 `ide_switch.dart:61-63`、knob `:72-74`）；在用户给的 150ms 上界内。
- **关态 hover**：track 才出底色 `themeColors['toolbar.hoverBackground']`（同 `_ContextRing` 的 hover，`composer.dart:1995-1999`）；开态恒为橙，hover 不变色。
- **无文字 label、无图标**（用户没要）：两项的 `label` / `icon` 留在数据面（T51 的断言面、≥3 档菜单面要用），本形态不渲染；宽度因此固定 35，不随文案长短变。
- **点击热区 = 整颗胶囊 35 × 22**（track 外上下各 1px，`GestureDetector` 包在外层）——与工具栏同高，满足用户「≥ 22」。
- **可访问面**：`Semantics(toggled: on, label: title)`，照 `IdeSwitch`（`ide_switch.dart:49-54`）——没有文字 label，开关态只能靠语义树说给读屏。
- **动作**：点即切到另一项（`onSelected(options.firstWhere((o) => o.id != selected.id))`）——无菜单、无键位（与 `_ContextRing` 同为点按面）；显示只认回报（D20）——点完 knob 不动，收到 `config_option_update` 后位置与颜色一起换。
- **tooltip** = `composerApprovalTitle(kernel.label)` + ` · ` + **点击后进入的那一项**的 description：关态即 `Tools run without asking — the same switch as /auto in the terminal`（与终端 `/auto` 同源的语义句来自选项描述，不新造文案、不特判内核）；开态即 `Ask before each tool call`（说的是点一下会到哪）。没有文字 label ⇒ tooltip 是唯一的文字语义面。
  l10n：**0 新键**——本机无 `flutter gen-l10n`（2026-10-16 实测），英文占位，登记 §14-19。
- **实现落点**：`composer.dart` 的 `ComposerPermissionSwitch`（公开类，供 widget 用例直取；现于 `:1911-1964`）画 track + knob；签名不动 = `ComposerPermissionSwitch({required KernelChoice permission, required String title})`，`permission` 已过 `localizedKernelOption`。
  `_buildToolbar` 的放置分支不动（`:1869-1879`：`permission != null && permission.options.length == 2`）。
- **可见性（用户要「一眼看出」）** = 右下角常驻 + **颜色即状态**（开 = 橙 track、knob 在右；关 = 无填充、knob 在左）+ tooltip 的同源语义句。

- **不做状态行 / 侧栏 AUTO 徽标**：宿主的状态文案由宿主从事件状态派生，内核没有「供给一个徽标」的面（新接口 = E2 的又一接线点）。判据 = 走查时若右下角开关仍不够醒目（用户没注意到）⇒ 再评估加面；在服务端真值这条主线上，常驻开关已承载该信息。
- **不做本地自答**（P0 见 §17.2）。

**④ 「Approve for this session」= 会话级 auto（本批做 · 桌面侧；用户 2026-10-16 21:47 裁定）**

事实：面板第二行的标签取自服务端 `approve_always` 的 `name`（`thincoder_kernel.dart:590` ← `bridge.mjs:52`「Approve for this session」），答复 `approve_always`（`thincoder_kernel.dart:598-617`）在服务端只换算成**本次** true（`bridge.mjs:57-62`，无任何记忆）⇒ 服务端没有「本会话记住」的位。终端同源（`dispatch.mjs:190-208` 单次 boolean）⇒ 偏差在服务端，不在桌面。

裁定：面板选 **always**（`approve_always`）⇒ 桌面**先答本次 approve**（该行字面兑现：本次放行已生效），**同一回合**追加一次 `set_config_option("autoApprove", true)`——写路径与右下角开关同一个 `_config('autoApprove', …)`（`thincoder_kernel.dart:807-819`）⇒ 本会话此后的工具请求不再弹（服务端短路，§17.1-①）。
选 once / reject ⇒ **不发该写**（行为与今天一致）。

做法（`answer`，`thincoder_kernel.dart:598-617`；diff，行号按分支定位；净增 4 行含注释）：

```diff
     request.answer({
       'outcome': {'outcome': 'selected', 'optionId': optionId},
     });
+    // "For this session" is the terminal's `/auto` switch, written too (D20).
+    if (optionId == 'approve_always') {
+      unawaited(_config('autoApprove', true));
+    }
```

`dart:async` 已在用（`:1`）；不新增写路径、不加能力预判——旧 CLI 的回错就走下面的失败面。

**语义（为什么是会话级）**：终端 `a` = 批量放行（本次询问族）；本口径 = **会话级 auto**——与终端 `/auto`、右下角开关同源（同一个 `agent.autoApprove`）。服务端 `approve_always` 无记忆，桌面也没有「本轮批量」的面 ⇒ 会话级是唯一诚实的解释。

**失败面**：写失败（RPC 错 / 旧 CLI 无 `autoApprove` 项）⇒ **不影响本次批准**（应答已发、工具照跑）、开关保持原状（在场时只认服务端回报，D20；旧 CLI 无此项 ⇒ 无开关）、零异常、连接与回合不受影响；留痕走 `_config` 既有 `appEvent`（`thincoder_kernel.dart:817`）。用例 T62。

判定条件（先到先做）：
- ① CLI 把该选项 `name` 改成「Approve once」或摘掉（协议面仍三值，只改名字）⇒ 桌面的 always 行**连同这个副作用一起撤**（「一次」的标签不能开全会话 auto）；
- ② 服务端加**按工具**的会话级放行表 ⇒ 与 auto 分清：**always = 记住这一种工具；auto = 全部不问**——两件事，别让一个开关兼职。

### 17.2 P0（兜底）：桌面内核自答 — 不做，只留判据

判据（一句）：**仅当 §17.1 的跨仓轮无法在用户要的时间窗内落地、且用户明确要先有自动档时**，才启用本地兜底——
内核在自己的反向请求入口（`thincoder_kernel.dart:556-595` `_serverRequest`）对 autoApprove 为真时直接回 `{outcome:{outcome:'selected',optionId:'approve_once'}}`、不发 `InteractionRequested`，开关仍借 `SelectsPermission` 显示。

**互斥**：§17.1 在位时开关的真值在服务端，本地再自答 = 同一件事两个真相（且服务端已不问，本地分支永不可达）⇒ 二者不并存；真启用时另立用例与走查。

### 17.3 F14 · 模型清单与思考档位

一句话：`configOptions.model.options[]` 从「当前一项」改为**运行期清单投影**（各渠道拉 `GET /models`，去重后 `provider:model`）；思考在布尔面之外**并行**投影一个档位面 `thinkingLevel`（select）。

桌面：模型面**不再零改动**（2026-10-18 轻渠道轮起按供应商分组 + 默认只展开当前组 + thincoder 隐藏「管理模型」页脚，批次档 #70；新增 `lib/kernel/thincoder/thincoder_options.dart`；原「按 `options[]` 渲染」的接线不变）；档位面给 `effort` 加一条读取分支。

**① CLI 侧：模型清单（`sessionConfigOptions` 是同步的 ⇒ 缓存 + 预取，不在投影里拉网络）**

- 缓存位 = `agent._modelChoices`（`{value,name}[]`，本会话一份）。
- 拉取时机 = **会话建好之后后台一次**（`defaultCreateSession` 里 fire-and-forget，`acp.mjs:81-84`）；落地后以 `config_option_update`（全量数组）推给客户端 ⇒ 桌面走既有路径刷新。**会话启动不等网络**（10s/渠道的上界不进首包）。被否：在 `sessionConfigOptions` 里拉（它是同步函数，且被四处响应 + 两处通知同源调用）。
- 三路会话同经该装配：`acp.mjs:100` 的缺省 `createSession` → `:116` 的 ctx 包装 → `handlers-session.mjs:195`（`session/new`）· `handlers-slots.mjs:99`（`session/load`）· `:169`（`session/resume`）⇒ 清单投影三路一致；注入式 `createSession` 的测试路径不经过（零网络）。
- 落地判据（fire-and-forget 的存活面，登记 §14-20）：落地时会话仍在册且仍是同一实例（`liveSession(id)?.agent === agent`，`acp.mjs` 把 `sessions` 的查取回调传进装配）——已关 / 已被 load·resume 替换 ⇒ 丢弃；`notify` 抛出（管道已断）⇒ 吞掉并记一行日志，不重试、不抛。
- 清单来源 = `agent.providers`（核装配对所有端统一设置：`thincoder-core/agent/assemble.mjs:106-107`；`agent.config.providersList` 同源）；按终端口径过滤 `isDerivedProviderHidden`（`tui/provider-admin.mjs:26`）。
- 每渠道：`getProviderModels(p, {signal: AbortSignal.timeout(10_000)})` + `dedupeModels`——**复用终端同一份实现**（`thincoder-cli/src/tui/model-catalog.mjs:38-47` 60s 缓存、失败不缓存；`:81-89` 按系列去重排序）⇒ 与终端 `/model` 同一取舍。各渠道并发拉；单个失败只记日志、不参与投影。
- 投影规则：`options` = 各渠道清单按 `config.providers` 序拼 `provider:model`；**当前会话的 `provider:model` 必在表内**（不在就补一条，防「拉不到 ⇒ 选不到自己」）。
- 失败面 = 拿不到的渠道只报当前项：整表为空（全失败 / 未配置）⇒ 退回今天的一项。
- 桌面：`model.options` 多项自动可切（批 1 起既有机制），`select` 发 `set_config_option('model', provider:model)`。

**② CLI 侧：思考档位（新 id，`thinking` 形状不动）**

- 为什么并行投影而不是把 `thinking` 改成 select：旧桌面把 `thinking` 的 `currentValue` 当布尔读（`thincoder_events.dart:191-194`，非 bool 一律 false）——把布尔换成串会让旧桌面在思考开着时显示关（**假报**，违 F5「显示以回报为准」）。⇒ `thinking` 原样保留（旧客户端用），新增 `thinkingLevel`（新客户端用）；两者改的是同一份 `agent.provider` 状态，投影自动一致。
- `thinkingLevel` = `{ id: "thinkingLevel", name: "Thinking effort", type: "select", currentValue, options }`
  - `options` = `[Off（有有效 off 路径时）] + effort 档`；档 = `providerSpec(agent.provider).reasoningEffortEnum ?? ["high", "max"]`，**剔掉 `"none"`**（`none` 与 `off` 同义、终端选择时归一，`cmd-think.mjs:113-118`——一个概念一个值）；`off` 只在 `thinkOffPath(spec)` 为真时给（单源 = `thincoder-core/think-off.mjs:22-26`）。
  - `currentValue`：思考为关形 ⇒ `"off"`（无 off 路径的族则取缺省档，不谎报 off）；否则 `agent.provider.reasoningEffort`，缺省按终端的开档规则取枚举首个非 `"none"`（`cmd-think.mjs:146`），再退 `"high"`；值不在 `options` 里 ⇒ 补一条（同模型清单规则）。
  - **只对有思考面的模型出这一项**（`spec.thinking === true`）；否则不出——偏离：终端 `/think` 是通用菜单，会给无思考面的模型也列档位；不替它造档位。
- `applyConfigOption("thinkingLevel", value)`：只接受 `"off"` 或本模型档位表内的值（否则 `false` ⇒ `-32602`）。`"off"` ⇒ 与 `thinking=false` 同形（`thinkOffShape(spec)` + 删 `reasoningEffort`，复用 `:125-136` 的既有写法）；否则 ⇒ 开形 `{ type: spec.thinkEnabledValue ?? "enabled" }` + `reasoningEffort = value`。
- **顺带修正（同一条投影）**：`thinking` 布尔对「服务端强制思考」族（`spec.thinkAlwaysOn`）今天可能报 false；终端口径是 ON（`cmd-think.mjs:27-28` 的 `thinkingOn()`：无 off 路径 ⇒ 恒真）⇒ 批 6 把 `thinking` 的 `currentValue` 改为 `spec.thinkAlwaysOn === true || (th != null && th.type !== "disabled")`，与终端对齐（旧桌面只多看到一次「开」，无回归）。

代码 diff（逐字；两个补丁合起来 = 批 6 的 thincoder 侧全量）

```diff
--- a/thincoder-cli/src/acp/handlers-session.mjs
+++ b/thincoder-cli/src/acp/handlers-session.mjs
@@ imports @@
-import { thinkOffShape } from "@thincoder/core/think-off.mjs"
+import { thinkOffShape, thinkOffPath } from "@thincoder/core/think-off.mjs"
 import { providerSpec } from "@thincoder/core/config.mjs"
+import { getProviderModels, dedupeModels } from "../tui/model-catalog.mjs"
@@ before sessionConfigOptions @@
+/** 运行期清单（§5.3）：投影同步、只读缓存；拉取在 `refreshModelChoices`（会话建好后一次）。 */
+function ensureValue(listed, current) {
+  if (!current) return listed
+  return listed.some((option) => option?.value === current) ? listed : [...listed, { value: current, name: current }]
+}
+
+function modelChoices(agent, current) {
+  return ensureValue(Array.isArray(agent?._modelChoices) ? agent._modelChoices : [], current)
+}
+
+/** 是否在思考（强制思考族恒真——终端同口径，`cmd-think.mjs` `thinkingOn`）。 */
+function thinkingOn(agent) {
+  const spec = providerSpec(agent?.provider ?? {})
+  const thinking = agent?.provider?.thinking
+  return spec.thinkAlwaysOn === true || (thinking != null && thinking.type !== "disabled")
+}
+
+function thinkingChoices(agent) {
+  const spec = providerSpec(agent?.provider ?? {})
+  if (spec.thinking !== true) return []
+  const off = thinkOffPath(spec) ? [{ value: "off", name: "Off" }] : []
+  const levels = (spec.reasoningEffortEnum ?? ["high", "max"]).filter((value) => value !== "none")
+  return [...off, ...levels.map((value) => ({ value, name: value }))]
+}
+
+function thinkingLevel(agent) {
+  const spec = providerSpec(agent?.provider ?? {})
+  const fallback = (spec.reasoningEffortEnum ?? []).find((value) => value !== "none") ?? "high"
+  if (!thinkingOn(agent)) return thinkOffPath(spec) ? "off" : fallback
+  const chosen = agent?.provider?.reasoningEffort
+  return typeof chosen === "string" && chosen && chosen !== "none" ? chosen : fallback
+}
@@ model 项 @@
-    opts.push({ id: "model", name: "Model", type: "select", currentValue: value, options: [{ value, name: value }] })
+    opts.push({ id: "model", name: "Model", type: "select", currentValue: value, options: modelChoices(agent, value) })
@@ thinking 与 mode 之间 @@
   const th = agent?.provider?.thinking
-  opts.push({ id: "thinking", name: "Thinking", type: "boolean", currentValue: th != null && th.type !== "disabled" })
+  opts.push({ id: "thinking", name: "Thinking", type: "boolean", currentValue: thinkingOn(agent) })
+  const levels = thinkingChoices(agent)
+  if (levels.length) {
+    const level = thinkingLevel(agent)
+    opts.push({ id: "thinkingLevel", name: "Thinking effort", type: "select", currentValue: level, options: ensureValue(levels, level) })
+  }
@@ applyConfigOption 尾（mode 支之后） @@
+    case "thinkingLevel": {
+      if (typeof value !== "string" || !agent.provider) return false
+      if (value !== "off" && !thinkingChoices(agent).some((option) => option.value === value)) return false
+      if (value === "off") {
+        agent.provider.thinking = thinkOffShape(providerSpec(agent.provider))
+        delete agent.provider.reasoningEffort
+      } else {
+        agent.provider.thinking = { type: providerSpec(agent.provider).thinkEnabledValue ?? "enabled" }
+        agent.provider.reasoningEffort = value
+      }
+      return true
+    }
@@ applyConfigOption 之后（新导出） @@
+/** 各渠道清单的后台拉取（`defaultCreateSession` 装配后调用一次；失败不缓存、不抛）。 */
+export function refreshModelChoices(agent, { notify, sessionId, log = () => {}, liveSession = null } = {}) {
+  const providers = Array.isArray(agent?.config?.providers) ? agent.config.providers : []
+  const signal = AbortSignal.timeout(10_000)
+  void Promise.all(providers.map(async (provider) => {
+    if (typeof provider?.name !== "string" || typeof provider?.baseURL !== "string" || !provider.baseURL) return null
+    try {
+      return { name: provider.name, models: dedupeModels(await getProviderModels(provider, { signal })) }
+    } catch (error) {
+      log(`[acp] models of ${provider.name} unavailable: ${error.message}`)
+      return null
+    }
+  })).then((lists) => {
+    if (typeof liveSession === "function" && liveSession(sessionId)?.agent !== agent) return
+    const choices = lists.filter(Boolean).flatMap((list) => list.models.map((model) => ({
+      value: `${list.name}:${model}`, name: `${list.name}:${model}`,
+    })))
+    if (!choices.length) return
+    const before = JSON.stringify(agent._modelChoices ?? [])
+    agent._modelChoices = choices
+    if (JSON.stringify(choices) === before) return
+    try {
+      notify("session/update", {
+        sessionId, update: { sessionUpdate: "config_option_update", configOptions: sessionConfigOptions(agent) },
+      })
+    } catch (error) {
+      log(`[acp] model list update dropped: ${error?.message ?? error}`)
+    }
+  }).catch((error) => log(`[acp] model list refresh failed: ${error?.message ?? error}`))
+}

--- a/thincoder-cli/src/acp.mjs
+++ b/thincoder-cli/src/acp.mjs
@@ import @@
-import { createRequireConfigured, createSessionHandlers, createSlotReleaser } from "./acp/handlers-session.mjs"
+import { createRequireConfigured, createSessionHandlers, createSlotReleaser, refreshModelChoices } from "./acp/handlers-session.mjs"
@@ defaultCreateSession @@
-export async function defaultCreateSession({ id, notify, request, log, clientCaps }) {
+export async function defaultCreateSession({ id, notify, request, log, clientCaps, liveSession = null }) {
   const agent = await assembleAgent({ excludeTools: ACP_EXCLUDED_TOOLS })
-  return createAcpSession({ id, agent, notify, request, log, clientCaps, onSecretInput: refuseSecretInput })
+  const session = createAcpSession({ id, agent, notify, request, log, clientCaps, onSecretInput: refuseSecretInput })
+  // 模型清单投影（§17.3）：后台拉取，落地后以 config_option_update 通知——会话启动不等网络。
+  refreshModelChoices(agent, { notify, sessionId: id, log, liveSession })
+  return session
 }
@@ buildAcpHandlers · ctx.createSession @@
-    createSession: (opts) => createSession({ ...opts, clientCaps: clientCaps.current }),
+    createSession: (opts) => createSession({ ...opts, clientCaps: clientCaps.current, liveSession: (sid) => sessions.get(String(sid)) }),
```

净增：`handlers-session.mjs` ≈ +60 行（3 个 helper + 2 个投影支 + 1 个导出）· `acp.mjs` ≈ +8 行（含落地判据接线）；不开新档、不动 `package.json`。**测试面约束**：`refreshModelChoices` 只挂在 `defaultCreateSession`（生产装配）——注入式 `createSession` 的测试路径零网络（既有 ACP 测试全是注入式）。

**③ 桌面侧：档位面（本仓）**

- `effort`（`thincoder_kernel.dart:711-731`）加分支：`configOf('thinkingLevel')` 在位且 `options` 非空 ⇒ 档位列表（`toggle == false`）；否则走既有布尔开关（逐字保留）。`selected` / `selectedFor` / `select` 用同一条判据。
- 标签 = `effortLabel`（`lib/models/model_provider.dart:267-272`）：词表 = `none` ⇒ `Disable`、`xhigh` ⇒ `X-High`；其余走兜底 = 首字母大写（`high` / `max` / `off` / `low` ⇒ `High` / `Max` / `Off` / `Low`）。与 Claude 的档位同一套显示形；描述留空（不复制 Claude 的英文说明，避免第二份副本）。
- **词表外的档名**（如 `low` / `medium` / `minimal`）同走兜底：首字母大写原样显示，不翻译、不映射——属 §14-19 的英文占位面（`localizedKernelOption` 只认 claude 元组，thincoder 的档名不本地化）。
- `_ModelSetting`（`:871-899`）的 `toggle` 从 `final bool` 改为可注入取值器（`bool Function()? toggles`）⇒ 同一面在两种 CLI 下分别是开关 / 列表（约 6 行）。
- 旧 CLI（无 `thinkingLevel`）⇒ 开关照旧（T57）；新 CLI ⇒ 列表（T56）。
- **写失败面**同 §17.1-③（同一条 `_config`）：服务端回错 ⇒ 档位显示不动、零异常、连接与下一回合不受影响；用例 T60。

**④ 兼容（逐条）**

| 组合 | 表现 |
|---|---|
| 旧 CLI（0.12.74，无新项）+ 新桌面 | `autoApprove` / `thinkingLevel` 缺席 ⇒ 无审批开关、思考仍是开关、模型一项（= 今天） |
| 新 CLI + 旧桌面 | 旧桌面只读 `mode` / `model` / `thinking` 三个 id ⇒ 新项被忽略；`thinking` 布尔未改形 ⇒ 无假报；`model.options[]` 多项走既有 `options` 机制 ⇒ **模型清单在旧桌面就已生效** |
| 新 CLI + 新桌面 | F13 / F14 目标行为 |

### 17.4 受影响文件清单（E2 增量；行数 = 2026-10-16 只读实测，`wc -l` 换行数）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ㉔ | `lib/kernel/thincoder/thincoder_kernel.dart`（899 行） | `implements SelectsPermission` + `permission` 面（F13，§17.1-③）· `effort` 读 `thinkingLevel`（F14，§17.3-③）· `_ModelSetting` 的 `toggle` 可注入 · `answer`：always ⇒ 同一回合 `_config('autoApprove', true)`（§17.1-④） | ≤ +66（⇒ ≤965） |
| ㉕ | `lib/kernel/thincoder/thincoder_mock.dart`（567 行） | 构造参数（`autoApprove` / `models` / `thinkingLevels` / `configError`，缺省 = 今天）· `_options()`（`:312-338`）增对应项 · `_configure`（`:289-308`）接受它们（`configError` 时对任意 id 回 `-32602`）· `_approve`（`:395-423`）在 auto 时**不发请求**（模拟 `:177` 短路）· T62 复用既有参数（`autoApprove` / `configError`），零增 | ≤ +55 |
| ㉖ | `test/kernel/thincoder_kernel_test.dart`（1845 行） | T51–T62（§17.7；T62 四个面） | ≤ +290 |
| ㉗ | `lib/chat/composer/composer.dart`（2069 行） | `ComposerPermissionSwitch`（右下角拨动开关：胶囊 track 35×20 + 圆 knob 16（再小会糊）、开 = knob 右 + 橙 track（`AppColors.autoTrack` `0xFFE2B373`）/ 关 = knob 左 + 无填充、只留 1px 淡描边；动画 140ms easeOut；hover / tooltip）+ `_buildToolbar` 放置分支（两档 ⇒ 右端；≥3 档仍左簇菜单） | ≤ +70（⇒ ≤2139；实交 2139） |
| ㉘ | `test/composer_test.dart`（2097 行） | T61（两档 ⇒ 开关 / 五档 ⇒ 菜单 / 点开关 ⇒ 第二项） | ≤ +90（⇒ ≤2187；实交 2184 = +87） |
| — | `test/fixtures/thincoder/*` | **不加**：固件回放没有「点选择器」的动作（`thincoder_fixtures_test.dart:84-125` 只有 `client` / `server` / `turn` / `answer` / `cancel` / `expect`），选项面在 kernel 测试里断言；既有固件保持绿 = 回归哨兵 | 0 |

- **宿主改动面 = 1 档**：`composer.dart`（右下角开关构件 + 放置分支，≤ +70；㉗）——用户 21:25 定的形只落在这一处。其余宿主档零改动：`agent_kernel.dart` · `chat_session.dart` · `composer_picker.dart` · `kernel_option_text.dart` · `interaction_panel.dart`——`SelectsPermission` 与 `SelectsEffort` 仍是既有接口，菜单渲染与档位列表仍是既有面。
- 体量（`composer.dart` 编制日 2069 行 / 实交 2139 行（+70）；`composer_test.dart` 2097 行）：两者都在 >800 名单，`composer.dart` 远在 >800 线之上——本批只加这一个控件（`ComposerPermissionSwitch` + 放置分支），不动结构、不删注释；缝候选 = 右下角固定组（`_ContextRing` / `_SendButton` / 本开关）整段出档，`composer_test.dart` = 按面分组（工具条 / 历史编辑 / 布局）；触发 = 下一次结构级触碰或独立拆分批立项。
- 零改动：`thincoder_events.dart`（`configOf` / `optionsOf` / `selected` 已是通用读面）· `lib/kernel/claude_code/**` · `lib/chat/**` 其它。
- 体量：`thincoder_kernel.dart` 899 行本就在 >800 硬顶之上。**本批不拆（显式裁定）**：本批对它是行级新增（两面 + 一个取值器），而拆分缝恰在同一区域（选择面 `:691-731` + 两个内部类 `:841-899`）——同日交付里动结构会把风险叠在风险上。
  **拆分触发 = F13/F14 两面定形之后的独立拆分批**（缝 = 选择面整段出档：`mode` / `model` / `effort` / `permission` 的构造 + `_Choice` / `_ModelSetting`；判据 = 下一次结构级触碰，或用户/评审要求）。本裁定只覆盖本批，交付后失效；拆分批已挂触发 ⇒ 下一批不得再在这两面上叠行（要动先立拆分批）。
- 体量（测试档）：`thincoder_kernel_test.dart` 1845 行仍在 >800 名单——**本批只加用例、不动结构**；缝候选沿用 §15.4 的四组拆法（connection / session ids / locator / the registered kernel 各自成档，组起点行号以 §15.4 为准）；触发 = 独立拆分批立项。
- out-of-repo 档：`thincoder-cli/src/acp/handlers-session.mjs`（0.12.74 活树 343 行，2026-10-16 只读实测；≈ +60）· `thincoder-cli/src/acp.mjs`（同实测 157 行；≈ +8）· `thincoder-cli/src/acp/bridge.mjs`（批 5 后 ≈460 行，仅注释一行）——按增量注记，不受本仓受管文件表约束。

**跨仓同拍的文档位与 CHANGELOG（给 out-of-repo 轮）**

| # | 坐标（0.12.74 活树） | 改动 |
|---|---|---|
| d | `thincoder/docs/cli/design/ACP-CLIENT.md:41`（方法表 `set_config_option` 行） | 「model / thinking / mode 分发」→「model / thinking / thinkingLevel / mode / autoApprove 分发（见 §5.3）」 |
| e | 同档 `:212-221`（§5.3 configOption 映射） | 表补两行（`thinkingLevel`：`"off"` ∥ 档名 ⇒ 开 / 关两形；`autoApprove`：boolean ⇒ `agent.autoApprove`，与会话槽同源）；`model` 行补一句 `options[]` = 运行期清单投影；表下补一段「清单投影：`agent._modelChoices` 缓存 / 会话装配后后台拉取一次 / 落地推 `config_option_update` / 拉不到的渠道只报当前项 / 失败不缓存」 |
| f | 同档 `:223-231`（§5.4 审批通道） | 补一句：`agent.autoApprove` 为真 ⇒ 审批在核 `dispatch` 阶段短路（`dispatch.mjs:177`），**不进** `onPermissionRequest`——ACP 面零改 |
| g | `thincoder/docs/cli/requirements/ACP-CLIENT.md:80-81`（R-A5.4） | 补一句：`configOptions` 可含 `autoApprove`（boolean）与 `thinkingLevel`（select）；`model.options[]` = 运行期清单投影（拉不到的渠道退化为当前项）——新项对旧客户端**忽略即合规** |
| h | `thincoder-cli/CHANGELOG.md` 顶部 `[Unreleased]` → `### Added` | 见下（逐字） |

```
- **ACP configOptions：审批自动档 + 运行期模型清单 + 思考档位**（ACP-CLIENT.md §5.3）：`configOptions` 增
  `autoApprove`（boolean，与会话槽同源——终端 `/auto` 与 ACP 客户端同一位）与 `thinkingLevel`（select，档位面；
  `thinking` 布尔面零改，旧客户端忽略即合规）；`model.options[]` 改为运行期清单投影（各渠道 `GET /models`，
  后台拉取 + `config_option_update` 推送；拉不到的渠道只报当前项）。
```

d–h 是**同拍义务**（该仓对文档与代码同拍的通行做法；批 5 §16.1 f–k 同例）：代码改了而契约档不改，就把一份说反的契约留在仓里。

**thincoder 侧验证（out-of-repo 轮执行，读数回本批 §5）**

1. **门禁**：`node --check src/acp/handlers-session.mjs` · `node --check src/acp.mjs` · `node --check src/acp/bridge.mjs` · `npm run lint`（check-syntax 全树）· `npm test` · 仓根 `node scripts/doc-check.mjs --root .`（既有 FAIL 口径不变）。
   该仓测试清单为空且明文「零用例即绿」（`thincoder-cli/test/run.mjs:43-47`）⇒ **不向空清单塞测试档**；本改动由下面的一次性探针 + 本仓固件/kernel 测试双向钉形。
2. **一次性探针**（不落仓；放 `thincoder-cli/.thincoder/tmp/probe-config-options.mjs`，跑完删）：

```js
// run from thincoder-cli/
import { sessionConfigOptions, applyConfigOption } from "../src/acp/handlers-session.mjs"
const tiers = { provider: { name: "p", model: "qwen3.8-max", thinking: { type: "enabled" }, reasoningEffort: "low" },
  planMode: false, autoApprove: false, config: { providers: [{ name: "p", baseURL: "http://127.0.0.1:1" }] } }
const always = { provider: { name: "p", model: "glm-5.3" }, planMode: false, autoApprove: true, config: { providers: [] } }
console.log(JSON.stringify(sessionConfigOptions(tiers), null, 1))
console.log(JSON.stringify(sessionConfigOptions(always), null, 1))
console.log(applyConfigOption(tiers, "autoApprove", true), tiers.autoApprove)
console.log(applyConfigOption(tiers, "autoApprove", "yes"))
console.log(applyConfigOption(tiers, "thinkingLevel", "high"), tiers.provider.thinking, tiers.provider.reasoningEffort)
console.log(applyConfigOption(tiers, "thinkingLevel", "off"), tiers.provider.thinking, tiers.provider.reasoningEffort)
console.log(applyConfigOption(tiers, "thinkingLevel", "bogus"))
```

   复现前提：`providerSpec` 只按 `provider.model` 取值（`model-specs.mjs:331-336`；

另有 `provider.context` 覆盖，不看 provider.name / 渠道类型）——fixture 的 `qwen3.8-max`（`model-specs.mjs:114`，effort 枚举 = `xhigh` / `medium` / `low`）与 `glm-5.3`（`:69`，`thinkAlwaysOn`）都是真实规格行，期望读数可自证。
   期望（逐条比对）：
   ① `tiers` 的 id 序 = `model` / `thinking` / `thinkingLevel` / `mode` / `autoApprove`；

   ② `tiers`：`thinking.currentValue === true`；`thinkingLevel.currentValue === "low"`，`options` 值 = `xhigh` / `medium` / `low`（该模型 `reasoningEffortEnum` 无 `none` 且 effort 族无 `"none"` ⇒ **无 Off 档**，`thinkOffPath` 判据）；`model.options` = 当前一项（无缓存）；

   ③ `always`（强制思考族、`thinking` 未设）：`thinking.currentValue === true`（D47）；`thinkingLevel` 无 Off 档、`currentValue` = 枚举首个非 `none`（`low`）；

   ④ `applyConfigOption("autoApprove", true)` ⇒ `true` 且 `agent.autoApprove === true`；`"yes"` ⇒ `false`（类型门）；
   ⑤ `"thinkingLevel":"high"` ⇒ `true`，`thinking` = `{type:"enabled"}`、`reasoningEffort === "high"`；

   ⑥ `"thinkingLevel":"off"` ⇒ `true`，`thinking === null`（effort 族 off 形，`think-off.mjs:14-16`）、`reasoningEffort` 已删；
   ⑦ `"thinkingLevel":"bogus"` ⇒ `false`（值域门）。

   行为面（autoApprove 真 ⇒ 桥收不到审批）不在单元探针里断言：代码证据 = `dispatch.mjs:167-186`，行为证据 = 走查 §17.9-③（真会话跑一次 `bash`，客户端侧零 `session/request_permission`）。
3. **分支与版本口径**：从活树 HEAD（`feat/acp-subagent-attribution`，含批 5 提交 03392521）新建 `acp-config-options`；两批改动文件不相交（批 5 = `bridge.mjs`、批 6 = `handlers-session.mjs` / `acp.mjs` / 文档），谁先合并都不冲突。
   版本**不预占号**：该仓纪律 = 号在发布时定、开发期只挂 `[Unreleased]`（`thincoder-cli/CHANGELOG.md:261`）；适配层不加版本门——能力按「选项 id 在场」探测（E3 / D13 口径），`thincoder_locator.dart:69` 的 `verifiedVersion` 不上调。
4. **执行顺序**：`cd D:\baocode\thincoder` → 新建分支 → `cd thincoder-cli && npm ci`（活树无 `node_modules`）→ 落 §17.1 + §17.3 的 diff（按符号定位）→ 落 d–h → 门禁 + 探针，读数原样入批次档 §5 → 提交（**不发布**）→ 走查前把桌面 `thincoder.path` 指到该检出的 shim。

### 17.5 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D39 | 自动档 = 服务端位 `agent.autoApprove`；桌面只显示与切换回报 | 「和终端同源」的唯一实现：终端 `/auto` 改的就是这个位，落槽、跨端一致（§17.1-②）。被否：桌面本地自答（P0）——两个真相，且与服务端短路并存时本地分支不可达 |
| D40 | 桥的权限路径**不改**（仅注释） | 核 `dispatch.mjs:177` 已在审批阶段之前短路，请求不到桥；改桥 = 死代码 + 同一判定两处写 |
| D41 | 开关落点 = 宿主审批面 `SelectsPermission` + composer 右下角拨动开关（两档时） | 宿主接口现成、语义正对（`agent_kernel.dart:130-132`）；右下角常驻、位置 + 颜色即状态（knob 右 + 橙 track = 开）⇒ 「一眼看出」（常驻 + 位置 + 颜色）；宿主代价 = composer 一档 +≤70 行（§17.4 ㉗）。被否：左簇菜单 pill（用户 2026-10-16 21:25 定形：两档要开菜单才看清状态）；被否：模式菜单（两个概念一个开关）；被否：设置页（要改宿主 + 不在工作面 + 作用域错） |
| D42 | 不加 AUTO 徽标 | 宿主没有「内核供给状态徽标」的面；右下角拨动开关 + 开态橙 track（常驻 + 位置 + 颜色）已满足「一眼看出」；加面 = E2 又一接线点 |
| D43 | `thinking` 布尔不动，新增 `thinkingLevel` | 旧桌面按布尔读 `thinking`（`thincoder_events.dart:191-194`）——改形 = 旧桌面假报 OFF。被否：把 `thinking` 改成 select |
| D44 | 档位只对有思考面的模型（`spec.thinking === true`） | 不替无思考面的模型造档位（与终端通用菜单的偏离，理由在此） |
| D45 | 模型清单 = 后台预取 + 缓存 + `config_option_update` 推送 | `sessionConfigOptions` 同步且被六处同源调用，不能在投影里拉网络；先包不等网络。被否：会话起点同步拉（慢 + 失败面扩到首包）；被否：新增 ACP 方法（协议面扩张，需求只要投影） |
| D46 | 「Approve for this session」= 会话级 auto（本批做 · 桌面侧） | 原判断：偏差在服务端措辞/语义（`bridge.mjs:52` + `:57-62`），非桌面独有 ⇒ 不改 CLI 的 `name`、不改协议。新裁定（用户 2026-10-16 21:47）：面板选 always ⇒ 先答本次 approve，同一回合写 `autoApprove=true`（与右下角开关同一写路径）⇒ 标签的会话级承诺成立；写失败不影响本次批准（§17.1-④）。被否：桌面本地记住「这一种工具」——服务端没有这个状态，桌面自演 = 两套真相；被否：只改标签不改行为——用户要的是真的开 auto |
| D47 | `thinking` 布尔补 `thinkAlwaysOn` 口径 | 终端对强制思考族恒报 ON（`cmd-think.mjs:27-28`）；ACP 面今天可能报 false = 与终端不一致，且 F14 的验收含「与终端一致」 |

### 17.6 验收对照（回指需求档 F13 / F14）

| 需求条目 | 本档落点 | 判据 |
|---|---|---|
| F13 桌面开 auto ⇒ 工具不再逐次弹审批 | §17.1-①②③（服务端短路 + 桌面开关） | T51 / T52；走查③ |
| F13 关 ⇒ 恢复逐次 | §17.1-③（`select` 回 false） | T53；走查③（后半） |
| F13 与终端同源 | §17.1-②（同一位、同一槽、同一存档点） | T51（`set_config_option` 载荷）+ 走查②④⑧ |
| F13 开着时一眼可见 | §17.1-③（右下角开关常驻 + 位置与颜色即状态） | T61（knob 在右 + track 橙 = 开；knob 在左 + 无填充 = 关）；走查②③ |
| （派生）审批面形态随选项数 | §17.1-③（两档 ⇒ 开关；≥3 档 ⇒ 菜单，Claude 不动） | T61 |
| （派生）面板 always = 会话级 auto | §17.1-④（先答本次，同一回合写 `autoApprove`） | T62：always ⇒ 一次 `approve_always` 应答 + 一次 `set_config_option('autoApprove', true)` + 后续不弹；once / reject ⇒ 零写；写失败 ⇒ 批准成立、开关不变 |
| F13 边界：不做逐工具白名单 | §17.8-1 | — |
| F14 模型清单与终端一致 | §17.3-①② · §17.3-④ | T55；走查⑤ |
| F14 切换生效（回报驱动） | §17.3-① 末 | T55；走查⑤ |
| （派生）写路径的错误面 | §17.1-③ / §17.3-③ / §17.1-④（D20：显示只认回报） | T59 / T60 / T62④：服务端回错 ⇒ 显示不动、零异常、连接与下一回合不受影响 |
| F14 thinking 档位与终端一致 | §17.3-②③ | T56 / T57；走查⑥ |
| 兼容：旧 CLI 行为不变 / 旧桌面忽略即合规 | §17.3-④ | T54 / T57；走查⑦ |

### 17.7 用例表（正常 / 边界 / 错误）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T51 | 审批面随回报出现 + 切换 | mock 报 `autoApprove=false` | `permission.options` = [ask, auto]；`auto.caution == true`；`selected == 'ask'`；`select('auto')` ⇒ 写出 `session/set_config_option{configId:'autoApprove', value:true}`（布尔，不是串）；UI 形（开关 / 菜单）见 T61 |
| T62 | 面板 always ⇒ 会话级 auto（紧接 T51） | mock 报 `autoApprove=false`；脚本首个工具发审批请求；`configError` 缺省 | ① 答 always ⇒ `mock.written` 里的答复 = `{outcome:'selected', optionId:'approve_always'}`（面板核销、工具照跑），同回合 `mock.requests('session/set_config_option')` = 1（configId `autoApprove`，value `true`）；回报 `autoApprove=true` ⇒ `permission.selected == 'auto'`；脚本的第二个工具 ⇒ 零 `session/request_permission`。② 答 once ⇒ 零 `set_config_option`。③ 答 reject ⇒ 零 `set_config_option`、答复 `reject`。④ `configError=true` 时答 always ⇒ 答复 `approve_always` 已发、工具照跑；`permission.selected == 'ask'`（回报值）；零异常 |
| T59 | 审批面写失败（T51 的错误面） | mock 报 `autoApprove=false` + `configError=true`（`set_config_option` 回 `-32602`） | `select('auto')` ⇒ 服务端错误：`permission` 显示仍 `ask`（等回报、不乐观改）；零异常；健康仍 ready、随后一个回合照常收尾。留痕 = `appEvent('thincoder', …)`（`thincoder_kernel.dart:817`）——测试不设 `EventLog.current` ⇒ 不落盘、不断言 |
| T52 | 自动开 ⇒ 无面板 + 工具照常 | mock `askPermission` + `autoApprove=true`（mock 按核的短路行为不发请求） | 事件流**零** `InteractionRequested`；工具卡与结果照常进 transcript；回合正常收尾 |
| T53 | 自动关 ⇒ 恢复逐次 | 同上但 `autoApprove=false` | `InteractionRequested` 出现；答「一次」⇒ `approve_once`；与 T6 同 |
| T54 | 旧 CLI（无 `autoApprove`） | mock 不报该项 | `session.permissions == null` ⇒ 无审批开关；面板路径与 T6 同（零回归） |
| T55 | 多模型清单 + 切换 | mock 报三项 `model.options`（两个渠道） | `model.options` = 3 项；选第二项 ⇒ `set_config_option('model', <value>)`；`selected` 等回报（不乐观改） |
| T56 | 档位面（新 CLI） | mock 报 `thinkingLevel`（off / high / max / low）+ `thinking=true` | `effort.toggle == false`；标签 = Off / High / Max / Low（`effortLabel`；`low` ⇒ `Low`）；`selected == 'high'`；选 `high` / `low` / `off` ⇒ 各发 `set_config_option('thinkingLevel', <值>)` |
| T60 | 档位面写失败（T56 的错误面） | mock 报 `thinkingLevel`（high / max）+ `configError=true`（服务端换模型后旧档不在表内） | `select('max')` ⇒ 服务端错误：`effort.selected` 不变（回报值）；零异常；连接与下一回合不受影响；留痕同 T59 |
| T57 | 旧思考面与强制思考族（边界） | ① mock 不报 `thinkingLevel`；② `thinkingLevels: ['high','max']` + `thinking: true` | ① `effort.toggle == true`、只有一个 `on`（= 今天）；② `thinkingLevel.options` 无 Off、`currentValue` 为某档；`thinking.currentValue == true` |
| T58 | 空档位表（错误面） | mock 报 `thinkingLevel` 但 `options: []` | 视作缺席 ⇒ 退回布尔开关（不出现空列表 / 死面）；零异常 |
| T61 | 审批开关的形态（widget） | ① thincoder mock `autoApprove=false`（两项）② Claude mock（五项，`pumpScreen`） | ① 右下角出现 `ComposerPermissionSwitch`：**关态** = `AnimatedContainer.alignment == Alignment.centerLeft`、`BoxDecoration.color == Colors.transparent`、knob 色 `AppColors.textMuted`；控件内零 `Text`、零 `Icon`（无 label）；左簇无审批 pill；点一次 ⇒ 交给第二项（`onSelected(options[1])`）⇒ 写出 `set_config_option('autoApprove', true)`；回报 `autoApprove=true` 后 = knob `Alignment.centerRight`、track `BoxDecoration.color == AppColors.autoTrack`、knob `button.foreground`——断言「位置 + 颜色」两项，不断言 caution 色。② 无开关；审批仍是左簇菜单（`Ask for approval` 的 `ComposerPicker`） |

注：T62 是 always 行的会话语义，紧接 T51；T59 / T60 是两条写路径的错误面，各紧接其成功面（T51 / T56）放置，便于对读；T61 是形态面的 widget 用例（`test/composer_test.dart`）；编号 = 登记序。

### 17.8 边界（批 6 不做）与登记（判定条件）

1. **逐工具白名单**：不做（需求档 F13 边界原文）；首版只有总开关。
2. **AUTO 徽标 / 状态行面**：不做（D42）。判定条件 = 走查时右下角开关不足以「一眼看出」⇒ 评估加宿主面。
3. **「Approve for this session」的服务端语义**：服务端仍无记忆、按工具会话级放行表不做；桌面侧已按 §17.1-④ 接成会话级 auto（先答本次 + 同一回合写 `autoApprove`）。判定条件 = §17.1-④ 两条（先到先做）。
4. **P0（桌面内核自答）**：不做（§17.2）；判据 = §17.2 那一句，且与 P1 互斥。
5. **模型清单的失败面**：拉不到的渠道只报当前项，失败不缓存（下次会话再试）；不做「桌面代拉 `/models`」（provider / key 的编辑面 = F24 §27，只写 `providers[]` 与 `defaultModel`；清单仍由 CLI 投射，与 D9 同口径）。
6. **档位面只覆盖有思考面的模型**（D44）：无 `spec` 行 / `thinking:false` 的模型没有 `thinkingLevel`，思考仍只有既有布尔开面。
7. **auto 不越过核的其它闸**：工程模式设计门与 D5 冻结窗在 `dispatch.mjs:142-165`，位于 autoApprove 短路（`:177`）**之前** ⇒ 自动档不越过它们（与终端同）；桌面不额外加闸（加一条终端没有的闸 = 两端分叉）。
8. **开关不落盘的情形**：切了没发消息就关窗口 ⇒ 槽里没写（§17.1-② 精度条）；不为此加写盘路径。
9. **强制思考族的布尔面**：D47 之后恒真（与终端一致）；`thinkingLevel` 无 Off 档 ⇒ 用户无从「关掉」——这是服务端事实，不是缺口。

### 17.9 真机走查步骤（P1 / F14 落地后执行）

1. 装含本批的 CLI（本地 `npm link` 或发布版），`thincoder.path` 指对；桌面新建 thincoder 会话。
2. **终端 → 桌面**：终端 `/auto` 打开 → 发一条 → 桌面开同槽会话（load / resume）⇒ 右下角（发送钮左侧、上下文环左边）出现拨动开关，**knob 在右、track 橙**。
3. **自动档生效（开关各点一次）**：桌面点开关打开（**knob 到右、track 橙**）→ 发一条会跑 `bash` 的消息 ⇒ **无审批面板**，工具卡正常完成；点开关关掉（**knob 回左、track 无填充**）→ 再发 ⇒ 面板照旧（三行）。
4. **反向同源**：桌面把 auto 打开 → 发一条 → 终端打开同槽 ⇒ `/auto` 显示 ON。
5. **模型清单**：终端 `/model` 的清单与桌面模型选择器逐项比对（同渠道、同模型名、同去重）；桌面选一个 ⇒ 该会话当前模型随动，终端 `/model` 的会话行同步。
6. **档位**：桌面切 Off / High / Max ⇒ 终端 `/think` 抬头显示同一档；切回 Off ⇒ 终端显示 OFF。
7. **旧 CLI 回退**：`thincoder.path` 指回 0.12.74 ⇒ 右下角无开关、左簇无审批 pill、思考面仍是开关、模型只一项，**不报错、不提示**。
8. **重启**：开关 + 发一条 → 关桌面重开 ⇒ auto 状态从槽恢复（与终端一致）。
9. **always 行 = 会话级 auto**：确认右下角是关态（knob 在左）→ 发一条会跑工具的消息 ⇒ 审批面板出现 → 点第二行「Approve for this session」⇒ 工具照跑（本次批准生效）；右下角随即转开态（**knob 到右、track 橙**）→ 再发一条工具消息 ⇒ **无审批面板**。终端开同槽 ⇒ `/auto` 显示 ON（与步 4 同源）。

## 18. 批 7：工作中发送的消息（F15）

> 需求档 F15（批 7；用户 2026-10-16 22:24 报告：thincoder 会话在代理工作中不能先写消息、等它说完自动发）。
> 一句结论：thincoder 内核**声明宿主既有的 `QueuesMessages`**，队列由**内核在本地持有**；在跑时 `send` 入队并显示为 `UserMessageItem(queued: true)`，回合结束（完成 / 取消 / 错误）后**依次**发出。
> 宿主与 CLI **零改动**；唯一的宿主触碰 = 设置页一句文案（§18.8 ①，D54）。

**最近先例（对齐 ∥ 偏离及理由）**

先例 = Claude 内核的队列（`claude_code_kernel.dart`：`send` 里 busy ⇒ `_queued.add` + 发 `UserMessageItem(queued: busy)`；`cancelQueued` / `sendQueuedNow`；进程退出清队）∥ 本仓宿主面（`transcript.dart:188-203`：`queued: true` 的项进队列表、转正时追加进对话；`queue_panel.dart` 的三个动作；`chat_session.dart:511` / `:544`）。

- **对齐**：队列项仍用 `UserMessageItem(queued: true)` 表示（宿主零改动）；撤回 = `ItemRemoved`；转正 = 以同 id 再发一次 `ItemUpserted`，`queued` 缺省 false。
- **偏离 1 · 队列在内核本地，不在协议端**：Claude 的 CLI 自己有异步消息队列（`cancel_async_message` 撤回、`priority` 决定顺序）；ACP 没有这个面——`session/prompt` 就是一趟回合，服务端只有一条 FIFO 串行链（`thincoder-cli/src/acp/session.mjs:31-49`），**没有撤回、没有改序、没有回合内注入**。
  ⇒ 撤回只能是本地判定（Claude 要问 CLI，`claude_code_kernel.dart:860-874`），改序也只能是本地重排。
- **偏离 2 · `duringTurn` 按 `afterTurn` 处理**：理由与判据见 §18.2-④。
- **偏离 3 · 不拿服务端 FIFO 当实现**：回合中直接写 `session/prompt` 也能得到「回合后依次」的顺序（服务端排队），但那样**撤回无门**（面板里的项撤不掉）、**改序无门**（写进服务端 FIFO 的那些撤不回来）⇒ 本地队列是唯一能同时兑现撤回与「立即发送」的形（D49）。

先例的文档坐标：与 §2.2 同一事实——Claude 适配与 codex 薄内核在本仓没有设计档 / 批次档，上列坐标全是实现坐标（`claude_code_kernel.dart` / `transcript.dart` / `queue_panel.dart` / `chat_session.dart`）。本节「对齐」按实现形态照抄，「偏离」逐条给理由；不引设计档不是漏项，是没有可引的。

### 18.1 做法：一处状态 + 四个入口

状态（`thincoder_kernel.dart:94-102` 一带）：

| 成员 | 含义 |
|---|---|
| `final List<KernelTurn> _queue` | 等待中的消息，**入队顺序**，头先发 |
| `KernelTurn? _next` | 「立即发送」点名的那条（`sendQueuedNow`），先于队头 |
| `final Set<String> _sent`（既有，`:96`） | `send` 的去重集（`:428`）：同一 id 只接一次。既有成员，**本批不动**；列在这里是因为新的 `send` 分支仍以它开头 |

入口（形状；实现按符号落）：

```dart
// send：在跑 ⇒ 入队并显示成队列项；没在跑 ⇒ 排水（队头先走）
void send(KernelTurn turn) {
  if (!_sent.add(turn.id)) return;
  _queue.add(turn);
  if (_turn != null) {
    emit(ItemUpserted(nextSeq, turn.id,
        UserMessageItem(text: turn.text, queued: true, images: turn.images)));
    return;
  }
  _drain();
}

// 排水：一趟只有一条 prompt（_turn 判空）；转正由 _deliver 开头那次 emit 完成
bool _drain() {
  if (_turn != null) return false;
  final next = _next ?? (_queue.isEmpty ? null : _queue.removeAt(0));
  _next = null;
  if (next == null) return false;
  _beginTurn(next.id);
  unawaited(_deliver(next));
  return true;
}
```

三个既有位置各插一处：

| 位置 | 插入 |
|---|---|
| `_endTurn`（`:518-531`，`emit(TurnEnded)` 之后、`_releaseWanted` 之前） | `if (_drain()) return;`（批 8 的暂存自动轮起轮行插在它之前，同一区间——§19.2「插入点」） |
| `_teardown`（`:351-371`，`_events.closePiece()` 之前） | 队列与 `_next` 逐项 `ItemRemoved`，然后清空 |
| 类声明（`:34-43`） | `implements` 末尾加 `QueuesMessages` |

**插入点的前置不变量**：`_turn = null` 在 `:513`——先于 `emit(TurnEnded)`（`:518-527`），也先于插入行（`_releaseWanted` 之前，`:528`）。⇒ 插入行执行时 `_turn` 必为 null，`_drain()` 首行的 `_turn != null` 守卫不会把这一趟挡回去。

这层先后是排水能起来的前提：`_turn` 若晚于插入行才清，`_drain()` 静默返回 false，队列停摆到下一次 `send` 才恢复。

插入行写成 `if (_drain()) return;`——提前 return **只**跳过其后的 `_releaseWanted` 分支（`:528-531`）；`_releaseWanted` 保持为真，等队列排空后那次 `_endTurn` 再判（那时 `_drain()` 返回 false，落到 `if (_releaseWanted) release();`）⇒ 排队期间进程不放（D53）。

**为什么挂在 `_endTurn`**：完成 / 取消 / 错误三条路都汇到它（`:487` 的应答、`:497` 与 `:462-473` 的失败、`:540` 与 `:662` 的本地收尾）⇒ 一处排水覆盖三种回合结束。

**为什么不撞服务端**：服务端在应答写出**之前**就把 `busy` 置回 false（`session.mjs:37` 的 `finally`，应答在其后返回）⇒ 应答到达时直接发下一条，与那条 FIFO 不冲突。

三条硬约束（用例钉住）：

1. **同一时刻只有一趟 prompt**：入队只在 `_turn != null` 时发生，排水只在 `_turn == null` 时发生；真正的时序要求是插入点处 `_turn` 已为 null（见上「插入点的前置不变量」）。
2. **先转正、后请求**：转正的 emit 在 `_deliver` 开头（`:438-444`）⇒ 即使随后请求失败，消息也已落在对话里（§18.2-⑤）。
3. **排水先于释放**：`_drain()` 起来一趟 ⇒ `_endTurn` 提前 return，`release()` 的既有分支（`:528-531`）被跳过 ⇒ 有排队消息时进程不提前放掉（D53）。

### 18.2 语义细则

**① 入队（在跑时 `send`）**

- 队列项 = `UserMessageItem(text, images, queued: true)`，id 就是 `KernelTurn.id`；**图片原样随行**（面板显示「N 张图片」，`queue_panel.dart:121-126`）——入队时不做 I/O、不判阈值（时机见②）。
- `mentions`（@文件）与 `notes` 留在内核的 `_queue` 里，**发出时**才照既有路径进 prompt（`_deliver` 的 `:480-485`）。
- 队列**不落盘**：重开桌面即丢（与 Claude 同；ACP 也没有「预登记消息」的面）。登记 §18.9-2。

**② 转正（发出）**

- 排水时 `_beginTurn(id)` + `_deliver(turn)`：`_deliver` 开头那次 `ItemUpserted(同 id, UserMessageItem(text, images))` 就是转正——宿主把该 id 从队列表移出、追加到对话尾（`transcript.dart:188-203`）。
- 顺序 = 入队顺序：对话里出现的顺序与用户打的顺序一致。
- **图片落盘与阈值判定在转正时执行**：`_deliver` 开头的 `_attachImages(turn)`（`:436`）就是 F6 的既有路径（= **回退路**；原生路见 §22 / D82–D85——能力位为 true 时不落盘、不发路径行）。⇒ 队列项预览 = 入队时的原样 N 张；实发时超阈项被弃，气泡里少于 N 张 + 一条 `dropped` warning（`:445-458`）⇒ **预览与实际可能不一致**，差异由那条提示交代——与首条发送同形（F6 的弃图只发生在发出那一刻）。
- **预览与实发正文的另一处差异**：面板预览 = `turn.text` + 「N 张图片」（`queue_panel.dart:120-126`）；转正正文还会拼 `notes`（空行分隔，`:911`）与图片路径行 `[Attached images: …]`（§4 F6 的落盘结果，`:941-943`）⇒ 面板与实发正文可能不完全一致。`notes` 按契约本就不展示（`kernel_types.dart:590-592`），路径行是内部细节 ⇒ 面板不改；用户可见的差异仍只有弃图（上一条提示交代）。

**③ 撤回 / 立即发送**

| 方法 | 队列里有 | 已发出 / 不在队列 | 备注 |
|---|---|---|---|
| `cancelQueued(id)` | 移出 + `ItemRemoved` ⇒ `true` | `false` | 纯本地，零 RPC；`_next` 上那条也能撤 |
| `sendQueuedNow(id)` | 移出 ⇒ 置 `_next`；在跑 ⇒ `cancel()`（当前回合停，回合结束后排水发它）；没在跑 ⇒ 立刻排水 | 忽略 | 其余项保持原顺序：那趟结束后队头照发；重复点另一条 ⇒ 前一条 `_next` 退回队头 |

`sendQueuedNow` 的语义与接口注释一致（`agent_kernel.dart:216-218`）：「抢在所有排在它前面的之前」。宿主面板因此天然一致：被点的那条离队，其余留在面板里、顺序不变。

**④ `duringTurn`（插入当前任务）**

- **ACP 面没有回合内注入通道**：`session/prompt` 是一趟完整回合（`handlers-session.mjs:329-348`），协议里没有「往在跑回合里塞一条文本」的方法；服务端的 FIFO 也是**排到下一趟**，不是插进这一趟。
- ⇒ 本内核**不读** `QueuedMessages.current()`（`queued_messages.dart:21`），两种取值一律按 `afterTurn`：排到当前回合之后、依次发。
- **判定条件（先到先做）**：thincoder 的 ACP 面出现「回合内注入」方法（例如 `session/inject`，或 `session/prompt` 新增一个入队语义的字段）⇒ 那时才读这个设置、按取值分派；在此之前写分支 = 死代码（D52）。
- 实际效果：设置页对 thincoder 会话只兑现 afterTurn（文案见 §18.8 ①，登记 §18.9-3）。

**⑤ 收束与失败面**

| 情形 | 队列 | 对话 / 提示 |
|---|---|---|
| 进程退出（`_exited` → `_teardown`） | 逐项 `ItemRemoved` 后清空 | 既有「thincoder stopped unexpectedly」（`:654-663`） |
| `restart()` / `dispose()` / 启动失败（`_fail`） | 同上（同经 `_teardown`） | 各自既有提示 |
| `release()` | 先排水（§18.1 约束 3），排水完队列已空；真到 teardown 时无项可清 | — |
| 发出去**失败**（`session/prompt` 回错 / 连接断 / 启动不了） | **不回队列** | 该消息**留在对话里**（转正已发生）+ 既有 `NoticeItem(error)`（`:462-473` / `:488-498`），回合标 interrupted；排水继续发下一条 |

**挂起态（回合已结束、后台子代理仍在跑）**：排水照发——与 §15.3「挂起期再发消息」同口径（`session/prompt` 无超时，服务端排队 / 合并后作答，桌面零特判）。

**失败面判据（为什么不回队列）**：三条一起定。

- **不丢文本**：进程随后退出时队列会被清掉（上表第一行）——消息若回到队列，文本会连着面板一起消失；留在对话里则一直在。
- **与今天同形**：首次发送失败就是「消息在对话里 + error 提示 + 回合 interrupted」，队列项复用同一条路径，没有第二套失败语义。
- **不造「暂停排水」状态**：回队列要回答「什么时候再试」——自动重试会打转（同一个错），不自动又要一个新状态位与一条新文案；收益只是省一次复制。

登记：失败后**没有一键重试**（消息留在对话里，可复制重发）。判定条件 = 走查或用户反馈出现「排队的消息发失败后找不回」⇒ 再评估「回队列 + 手动重试」。

### 18.3 兼容（三种组合）

| 组合 | 表现 |
|---|---|
| 任意版本的 thincoder CLI + 本批桌面 | 可排队。队列全在客户端，**不依赖对端能力**（E3：能力按接口在场判，不按版本判；`thincoder_locator.dart` 的 `verifiedVersion` 不上调） |
| Claude 会话 | 逐字不变（它自己的队列实现不动） |
| 没有 `QueuesMessages` 的内核 | 输入照旧禁用（`canSend` = `!isStreaming || canQueue`，`chat_session.dart:544`） |

**「旧行为 = 输入禁用」的裁定**：本批起 thincoder 会话**一律可排队**（这正是 F15 的目标）。宿主 `canSend` 只按接口在场判定，没有第三个档位；要保留旧形得加一个宿主开关——那是宿主改动，且与需求相反。

### 18.4 受影响文件清单（E2 增量；行数 = 2026-10-16 `wc -l` 实测）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ㉙ | `lib/kernel/thincoder/thincoder_kernel.dart`（958） | `implements QueuesMessages`（`:34-43`）· 队列状态（`:94-102` 一带）· `send` 改写（`:427-431`）· `_drain` 新增 · `cancelQueued` / `sendQueuedNow` 新增（`cancel()` 之后，`:535-550` 一带）· `_endTurn` 一行（`:527` 处）· `_teardown` 清队（`:351-371`） | ≤ +70（⇒ ≤1028） |
| ㉜ | `lib/kernel/thincoder/thincoder_mock.dart`（620） | 一个可变参数 `bool promptError`（缺省 false）+ `_prompt`（`:404-441`）开头一处：真 ⇒ 回 `-32603` 并完成 `finished` | ≤ +6（⇒ ≤626） |
| ㉝ | `test/kernel/thincoder_kernel_test.dart`（2133） | T63–T67（§18.7） | ≤ +170（⇒ ≤2303） |
| ㉞ | `lib/l10n/app_en.arb`（6642）· `app_zh.arb`（2509）· `app_localizations_en.dart`（9159）· `app_localizations_zh.dart`（8651） | 一句文案（`generalSettingsQueuedMessagesDescription`）——见 §18.8 ① | 各 1 行 |
| — | `test/kernel/thincoder_fixtures_test.dart`（211）· `test/fixtures/thincoder/*` | **不加**（判据见 §18.7 末） | 0 |
| — | 宿主其它档 | **零改动**：`agent_kernel.dart` · `chat_session.dart` · `transcript.dart` · `queue_panel.dart` · `composer.dart` · `general_page.dart` | 0 |
| — | thincoder 仓 | **零改动**：协议面没有新方法、没有新字段 | 0 |

- **体量**：`thincoder_kernel.dart` 958 行在 >800 名单。本批动的是**会话面**（`send` / `_deliver` / `_endTurn` / `_teardown`），不是 §17.4 裁定的选择面（`mode` / `model` / `effort` / `permission` + `_Choice` / `_ModelSetting`）⇒ 不触发「先立拆分批」那条；本批仍是行级新增，不动结构。
- **会话面缝候选（本条不动结构，只登记）**：`send` / `_deliver` / `_beginTurn` / `_endTurn` / `cancel` 一段（`:427-550`）+ 本批新增的队列状态与 `_drain`——「回合生命周期 + 队列」整段出档；`_teardown` 的清队一行留在生命周期面（`:351-371`），不进这条缝。与 §17.4 的选择面缝并列、两条不重叠；触发 = 下一次结构级触碰或独立拆分批立项。
- **测试档**：`thincoder_kernel_test.dart` 2133 行在 >800 名单；本批只加用例，缝候选沿用 §15.4 的四组拆法。
- **生成档（㉞ 后两项）**：`app_localizations_en.dart` / `app_localizations_zh.dart` 是 `flutter gen-l10n` 产物——按生成物处理、不进拆分档位（>800 行的拆分批口径不适用于生成物）；手改对象是 `app_en.arb` / `app_zh.arb`，生成档只同步值（本机无 `gen-l10n`，见 §18.8 ①）。

### 18.5 验收对照（回指需求档 F15）

| 需求条目（F15） | 本档落点 | 判据（机检 / 走查） |
|---|---|---|
| 流式中可发消息（输入不再禁用） | §18.1 `send` 分支 + §18.3 | T63①；`canQueue` / `canSend` 由接口在场放开（`chat_session.dart:511` / `:544`） |
| 进队列：队列面板可见、可撤回 / 编辑 | §18.1 + §18.2-①③；宿主 `transcript.queued` / `queue_panel` | 可见 + 撤回 = T63②③、T65；**编辑 = 宿主既有路径（`chat_session.dart:1036-1046`：撤回成功把文本与图片放回输入框），本批不改宿主 ⇒ 不机检**（内核侧只保证撤回到位，即 T65；走查 §18.10-5 覆盖） |
| 当前回合**正常结束**后自动依次发送 | §18.1 排水 + §18.2-② | T63④、T64 |
| 取消 / 错误结束也发（「回合结束」三态都算） | §18.1（`_endTurn` 是三条路的汇点） | T66（取消后立即发）、T67③（错误后继续） |
| 「插入当前任务」在 ACP 面不可达 ⇒ 按等回合结束处理并登记 | §18.2-④（D52）+ §18.9-1 | 无机检（协议事实 + 判定条件）；走查 9 |
| （派生）撤回只对未发出的项生效 | §18.2-③ | T65（已发出的返回 false） |
| （派生）立即发送 = 停当前 + 该项先发，其余保序 | §18.2-③ | T66 |
| （派生）进程收束 / 会话释放 / 断开 ⇒ 清队 | §18.2-⑤ + §18.1 | T67①② |
| （派生）发送失败不静默丢 | §18.2-⑤（D51） | T67③ |
| 兼容：thincoder 会话一律可排队；其它内核不受影响 | §18.3 | T63①；Claude 的既有用例不回退 |
| 设置页文案与能力一致 | §18.8 ①（D54） | `test/l10n_test.dart:107-123`（key 对齐 / zh 非空）；走查 9 |

### 18.6 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D48 | 队列在内核本地；`QueuesMessages` 由 thincoder 内核声明 | ACP 没有撤回 / 改序 / 注入的面（`acp/session.mjs:31-49`），撤回与「立即发送」只能本地做（§18 偏离 1·3） |
| D49 | 不拿服务端 FIFO 当实现 | 回合中直接写 prompt ⇒ 面板里的项撤不掉、改不了序；本地队列才能兑现面板的三个动作 |
| D50 | 转正 = 同 id 再发一次 `ItemUpserted`（`queued` 缺省 false） | 宿主 `_put` 的既有语义就是这样（`transcript.dart:188-203`）⇒ 零宿主改动；新造事件 = E2 又一接线点 |
| D51 | 发送失败：消息留在对话 + error 提示，**不回队列** | 见 §18.2-⑤ 三条判据；被否 = 回队列 + 手动重试（要「暂停排水」新状态，且进程随后退出会把文本一起抹掉） |
| D52 | `duringTurn` 按 `afterTurn`；内核不读该设置 | 无注入通道 ⇒ 读它是死分支；判定条件 = 协议出现注入方法 |
| D53 | 排队消息优先于进程释放 | 用户明确要让它们发出去；提前放掉 = 静默丢消息。实现 = `_drain()` 先于 `_releaseWanted` 分支 |
| D54 | 设置页文案修正（§18.8 ①） | 现值说「目前仅支持 Claude Code」（`app_zh.arb:928` / `app_en.arb:2207`）；本批之后 thincoder 也排队 ⇒ 那句话成了假话。被否 = 不改（UI 事实错，用户会以为 thincoder 不能用） |

### 18.7 用例表（T63–T67；`test/kernel/thincoder_kernel_test.dart`）

统一前提：`ThincoderMock()..hold = Completer<void>()`（把回合握在手里，`thincoder_kernel_test.dart:773` 同款；`hold` 可变 ⇒ 每趟可重握，`thincoder_mock.dart:76`）。

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T63 | 在跑时入队，回合结束转正 | `send('one')` → `settle` → `send('two', id: 'turn-2')` → `settle` | ① prompt 仍 1 条（在跑时不写第二条）；② `transcript.queued` = 1 项（id `turn-2`、`queued == true`）；③ 对话里只有 `user: one`；④ `agent.release()` 后 ⇒ prompt 2 条（第 2 条含 `two`）、`queued` 空、顺序 `one → two`、转正项 `queued == false` |
| T64 | 依次发（两项） | T63 前提下再 `send('three', id: 'turn-3')`，队列 = [2,3]；逐趟 `agent.release()` | 首趟结束 ⇒ 只发 `turn-2`（prompt 2 条，队列剩 1）；`turn-2` 结束 ⇒ 才发 `turn-3`（prompt 3 条）；三条 prompt 的文本顺序 = `one` / `two` / `three` |
| T65 | 撤回 | 队列 [2,3]；`cancelQueued('turn-3')` ⇒ `true`；再撤一次 ⇒ `false`；对已发出的 `turn-1` ⇒ `false` | `turn-3` 离队 + 一条 `ItemRemoved`；面板剩 1 项；零 RPC（prompt 与 `session/cancel` 计数不变）；两趟结束后 `turn-3` 从未被发；④ 见「`_next` 的两条边」 |
| T66 | 立即发送（越过队头） | 队列 [2,3]；`sendQueuedNow('turn-3')` | ① 写出一次 `session/cancel`；② 当前回合结束（`transcript.lastTurnInterrupted == true`）；③ 下一条 prompt 的文本是 `three`（先于 `two`）；④ `turn-3` 结束后才发 `turn-2`；对话顺序 `one → three → two`；⑤ `sendQueuedNow` 之后队列只剩 [2]；⑥ 见「`_next` 的两条边」 |
| T67 | 收束清队与失败面 | ① 队列 [2] 时 `agent.crash()`；② 队列 [2] 时 `kernel.restart()`；③ 队列 [2] 时把 `agent.promptError` 置真 | ①② 队列清空、各一条 `ItemRemoved`、对话里没有该项；③ 该消息**在对话里**（`user: two`）+ 一条 `notice error`、回合 interrupted、队列清空；随后关掉 `promptError` 再发一条 ⇒ 照常发出（没有重试环路） |

**符号（`release()` 两件事）**：本表的 `agent.release()` = mock 侧放行，完成 `hold`、回合照脚本走完（`thincoder_mock.dart:136-139`；测试里的实际调用形是 `s.agent.release()`，`thincoder_kernel_test.dart:766`）。§18.1 约束 3 与 §18.2-⑤ 的 `release()` 是内核生命周期方法，放的是进程（`thincoder_kernel.dart:401`）。用例表一律写限定形，不写裸 `release()`。

**`_next` 的两条边（T65 / T66 的子项）**

| 子项 | 输入 | 期望 |
|---|---|---|
| T65④ | 队列 [2,3]，先 `sendQueuedNow('turn-3')`（成为 `_next`）再 `cancelQueued('turn-3')` | 返回 `true` + 一条 `ItemRemoved`；回合结束后发出的是队头 `turn-2`（`turn-3` 从未发出） |
| T66⑥ | 在跑、队列 [2,3]：`sendQueuedNow('turn-3')` 后再 `sendQueuedNow('turn-2')` | 前一条 `_next` **退回队头**（队列 [3]）⇒ 排水先发 `two` 再发 `three`，对话顺序 `one → two → three` |

**固件（判据）**：不加。两条理由。

① 回放**有**发消息的动作（`{"turn": …}`，`thincoder_fixtures_test.dart:102-106`，且它不等回合结束）⇒「回放表达不了一次排队」不成立，本可写一个 `queue.ndjson`。

② 但固件的用处是「thincoder 更新后先跑固件」看**线形有没有动**（`test/fixtures/thincoder/README.md` 原话），而本批**不发任何新帧**（还是 `session/prompt` / `session/cancel`），队列顺序是纯客户端行为，T63 / T64 已用 mock 的 `requests()` 逐帧钉住 ⇒ 固件只会重复同一断言。既有固件保持绿 = 回归哨兵。

### 18.8 UI / 交互决定（宿主零改动 + 一处文案）

**① 设置页文案（D54；2 个 ARB + 2 个生成档，各 1 行）**

- `app_en.arb:2207` / `app_localizations_en.dart:3232-3233`：
  `When a message sent while the agent is still working is taken up. Applies to messages sent after a change. Joining the task is Claude Code only for now.`
- `app_zh.arb:928` / `app_localizations_zh.dart:3101-3102`：
  `Agent 还在工作时发出的消息何时被处理。更改对之后发送的消息生效；「插入当前任务」目前仅支持 Claude Code。`
- 理由：改前那句「目前仅支持 Claude Code」在本批之后是假的（thincoder 也排队）；改后两半都说对——计时选择对 thincoder 生效，「插入当前任务」仍只有 Claude。
- `test/l10n_test.dart:107-123` 只查 key 对齐与 zh 非空 ⇒ 改值不动测试。本机无 `flutter gen-l10n`（§17.1-③ 实测）⇒ ARB 与生成档同时手改，二者保持一致。

**② 其余全落地（零改动）**

- 输入：流式中可写可发（`canSend` 由接口在场放开，`chat_session.dart:544`）；发送键在「有内容」时显示发送、「空」时显示停止（`composer.dart:1318-1321` 的既有逻辑，Claude 同形）。
- 队列面板：宿主既有（`chat_screen.dart:876-887` → `queue_panel.dart`），撤回 / 编辑 / 立即发送三个动作都指向 `QueuesMessages` 的两个方法 + `editQueued`（`chat_session.dart:1028-1051`）；无新增文案、无新增键。
- 无 open 项。

### 18.9 边界（批 7 不做）与登记（判定条件）

1. **回合内注入（`duringTurn`）**：不做（D52）；判定条件见 §18.2-④。
2. **队列不落盘**：重开桌面即丢（与 Claude 同）。判定条件 = 用户反馈「排队的消息关窗口就没了」且希望保住 ⇒ 那是新面（要在会话槽里存草稿队列），另立批。
3. **设置项不按内核显隐**：「插入当前任务」对 thincoder 会话无效，只在文案里说明；不做「设置项按会话内核置灰」（宿主的设置页是全局页，拿不到会话的内核）。判定条件 = 设置页能拿到当前会话内核而误导仍在 ⇒ 再评估。
4. **失败后没有一键重试**：见 §18.2-⑤。
5. **队列项的编辑**：复用宿主既有路径（撤回成功后把文本与图片放回输入框，`chat_session.dart:1036-1046`）；不新造「面板内直接改字」。
6. **排队消息不另起项目快照**：宿主 `send` 只在 `!isStreaming` 时开快照，注释即写「Not one queued behind another」（`chat_session.dart:993-1008`）⇒ 这是宿主对队列的既有口径，两种内核一致，本批不动。
7. **不做队列的其它管理**：面板只有撤回 / 编辑 / 立即发送；不加「清空队列」「上下调整顺序」——接口没有，需求也没有。
8. **`KernelTurn.now`（立刻接管：停掉在跑的回合、越过队头）不兑现**：`send` 只按 `_turn != null` 入队，不读 `now`（`thincoder_kernel.dart:438-449`）；契约语义见 `kernel_types.dart:594-596`。
   本仓内主动要求「立刻」的只有 Claude 的目标路径：`chat_session.dart:788-793` 的 `setGoal` / `clearGoal`，入口是 `tool_call_row.dart:99` 的 `ToolKind.goal`；thincoder 翻译层不产出该 kind ⇒ 桌面内的 thincoder 会话没有触发 `now` 的路径。

   远端桥是唯一旁路：`workspace_bridge.dart:276-279` 把 peer 请求里的 `now` 原样转给会话（本仓内无客户端构造它）；真对 thincoder 会话发来 ⇒ 今天也按普通入队处理——同一降级。
   ACP 面没有「插队」语义（同 §18.2-④），`sendQueuedNow` 已是最近等价面。

   **判定条件**：thincoder 翻译层开始产出 `ToolKind.goal` 一类「立刻接管」的回合，或宿主 / 远端面出现对 thincoder 会话真正使用 `now` 的路径 ⇒ 重新评估；届时兑现 = `send` 见 `now` 直接置 `_next` + `cancel()`（与 `sendQueuedNow` 同一状态机）。

### 18.10 真机走查步骤

1. 桌面新建 thincoder 会话，`thincoder.path` 指到任一 0.12.x（本批**不依赖** CLI 版本）。
2. **入队**：发一条会长跑的消息（例如「跑一遍测试并总结」）→ 回合进行中在输入框再写一条 ⇒ 发送键是**发送**（不是停止）→ 回车 ⇒ 输入框清空，**对话里没有这条**，composer 上方出现队列面板「1 条排队中 · 当前任务结束后依次发送」。
3. **转正**：等首趟自然结束 ⇒ 无需任何点击，面板项消失、该消息出现在对话里（在首趟的回答之后），代理开始回答它。
4. **依次**：连发两条 ⇒ 面板两项；首趟结束 ⇒ 第二条先发，再第三条；对话顺序 = 打的顺序。
5. **撤回**：面板上点垃圾桶 ⇒ 该项消失（对话里始终没有它）；点另一项的铅笔 ⇒ 该项回到输入框可改。
6. **立即发送**：面板两项时点第二项的箭头 ⇒ 当前回合停下（该消息标「已中断」），被点的那条**先发**，剩下那条仍排在后面。
7. **空闲态不变**：回合不在跑时发消息，行为与今天逐字相同（不进面板）。
8. **收束**：队列里有消息时直接关掉应用再开 ⇒ 队列没了（登记 §18.9-2），对话里也没有那几条。
9. **设置**：设置 → 通用 → 工作中发送的消息改成「插入当前任务」→ thincoder 会话再发一条 ⇒ 仍是回合后依次（D52），并确认文案说的是「插入当前任务仅 Claude Code」。

---

## 19. 批 8：回合结束后继续关注后台子代理（F16）

> 需求档 F16（批 8；用户 2026-10-17 01:31 报告：后台评审 / 设计子代理结束后主 agent 停在「现在等评审报告回来」，要用户再问一句才继续）。
> 一句结论：**挂起驱动进 ACP 会话层**（复用核 `startSuspension`，与终端 / VSC / thincoder 桌面同一台状态机）；子代理结算 ⇒ 主代理**自起一轮**把结果说出来；这轮在桌面呈现为**宿主既有「无提示回合」**（`TurnStarted(unprompted: true)` / `TurnEnded`）——「正在续写」可见、可停止、结束即回「该你了」。
> 两半：**thincoder 仓** `thincoder-cli/src/acp/` 加挂起窗 + 回合边界扩展帧 + 窗开关帧（§19.3；out-of-repo 轮执行）· **本仓**把边界帧翻成既有 unprompted 回合、把窗开关帧翻成释放判据（§19.2；宿主与 UI 零改动）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：核驱动 `startSuspension`（`thincoder-core/agent/suspension.mjs:220-352`）三端同源——TUI `thincoder-cli/src/tui/suspension-drive.mjs:188-261` · thincoder 桌面 `thincoder-desktop/src/main/suspension-drive.mjs:240-287` · VSC `thincoder-vscode/src/extension/suspension.mjs:236-300`。本批 = 第四个装配面；状态机零改。
- 对齐 ②：自动轮的起止可见帧三端都发——TUI 起止行（`tui/suspension-drive.mjs:105-124`）、桌面 `ev:digest start|end`（`desktop/src/main/suspension-drive.mjs:175-185` · `turn-face.mjs:183-184`）、VSC `digest start|end`（`vscode/src/extension/suspension.mjs:195-225`）。本批把同一事实搬到 ACP 线上（§19.2）。
- 对齐 ③：宿主的「无提示回合」是**既有面**，先例 = Claude 内核——`claude_code_kernel.dart:805-811`（`TurnStarted(..., unprompted: true)`）与 `:1464-1469`（CLI 自起一轮、本端无在飞回合 ⇒ 起 unprompted 回合；注释逐字「the CLI took up a prompt of its own (a background task's notice, a scheduled one)」）。
  消费面已齐（均既有）：`kernel_event.dart:16-24` · `transcript.dart:61-67` · `chat_session.dart:538-544` · `chat_history_view.dart:1162-1194` · `attention_service.dart:137-146` · `star_prompt.dart:111-117` · `workspace.dart:158-177`。
- 偏离 ①：边界信号走 `_meta` 扩展，不新增 `sessionUpdate` 变体（D56）。
- 偏离 ②：自动轮不请求审批（D58）——与终端手动档 digest 同判（`tui/suspension-drive.mjs:100-112`），不是本批新立的口径。
- 偏离 ③：不接 `timerFace`（无宿主 timer 面；§14-21 登记）。

### 19.1 做法：一处驱动 ∥ 两处边界

```text
用户回合结束（session/prompt 应答写出后一个 macrotask）
   │ 池仍 live（poolLive(agent)，suspension.mjs:64-72）
   ▼
ACP 挂起窗（acp/suspension.mjs，本批新增）
   ├─ 建窗：先发窗开关帧 watch{on:true}（D65——先于本窗任何轮帧）
   ├─ pending 非空 ∥ 有未 drain 的上行 ask ⇒ 自起一轮（autoTurn）
   │     ├─ 起：发回合边界帧 start{kind}
   │     ├─ 注入 pending 结果（beginRun，run-start.mjs:39-65；_daSession=true）
   │     ├─ 模型答话 / 工具卡 → 既有 session/update 帧（agent_message_chunk / tool_call …）
   │     └─ 终：发回合边界帧 end{kind, ok}（try … finally 必发；抛错 ⇒ ok:false）
   └─ 池空 ⇒ 自然退出（挂起窗关）：发窗开关帧 watch{on:false}
       桌面：start ⇒ TurnStarted(unprompted: true)；end ⇒ TurnEnded
              watch ⇒ _watching（窗在 ⇒ 不释放进程；旧 CLI 无此帧 ⇒ 静默期兜底）
```

桌面侧用的全是既有事件面：`unprompted` 一位 + `TurnEnded` 一收——**不新造 KernelEvent、不改 UI**（E2）。

- 自动轮失败（模型 / 工具 / 注入抛错）不静默：`end{ok:false}` **必发**（`try … finally`），窗按核语义收窗（§19.3-②）；桌面据此收轮 = `TurnEnded(interrupted: true)`（§19.2 翻译表）。

### 19.2 回合边界帧（线上形与桌面翻译）

**线上形**（扩展契约；承 `_meta` 扩展位，同 `thincoder.dev/subagent` 先例，thincoder/docs/cli/design/ACP-CLIENT.md §12.1）：

```json
{ "sessionId": "<会话 id>",
  "update": { "sessionUpdate": "session_info_update",
    "_meta": { "thincoder.dev/turn": { "phase": "start", "kind": "digest" } } } }
{ "sessionId": "<会话 id>",
  "update": { "sessionUpdate": "session_info_update",
    "_meta": { "thincoder.dev/turn": { "phase": "end", "kind": "digest", "ok": true } } } }
{ "sessionId": "<会话 id>",
  "update": { "sessionUpdate": "session_info_update",
    "_meta": { "thincoder.dev/turn": { "phase": "watch", "on": true } } } }
{ "sessionId": "<会话 id>",
  "update": { "sessionUpdate": "session_info_update",
    "_meta": { "thincoder.dev/turn": { "phase": "watch", "on": false } } } }
```

| 字段 | 域 | 语义 |
|---|---|---|
| `phase` | `"start"` ∥ `"end"` ∥ `"watch"` | 自动轮开始 / 结束；`watch` = 挂起窗的开关（D65） |
| `kind` | string（开集；现发射 `digest` / `upstream`；仅 `start` / `end`） | 起因（digest = 结果消化；upstream = 子代理在等回复）；桌面只留痕，不分支 |
| `on` | boolean（仅 `watch`） | `true` = 挂起窗已开；`false` = 挂起窗已关 |
| `ok` | 任意（仅 `end`；只有布尔 `false` 有意义） | 该轮正常收尾：`false` = 中断 / 出错；缺省 / 非布尔 / 其它值 = 未中断 |

**窗开关帧（D65；`phase:"watch"`）**

- 发射点 = 挂起窗的建立 / 退出（`acp/suspension.mjs` 的 `createSuspensionWindow`）：`on:true` 在建窗时**先于本窗任何轮帧**发出；`on:false` 在窗 `done` 的收尾 `finally` 发——池空自然退出、`close()`、有轮在飞时的 `cancel()` 中止、窗内异常，四径同达。
- 先于轮帧的理由：`startSuspension` 的循环在同步段就可能起消化轮（`carrier._pendingAsyncResults` 在建窗时已非空 ⇒ `runTurn` 同步被调用、`start` 帧当场发出），窗帧若放在 `startSuspension` 返回之后发，序就倒了。
- 建窗失败（`startSuspension` 同步抛错）：已发的 `on:true` 由 `catch` 补一条 `on:false`（配对不悬空），再把异常上抛。
- 至多一对（同一窗至多一条 `on:true`、一条 `on:false`）；`off` 只在 `on` 之后发。
- 桌面用途 = `_watching`（释放判据，§19.2「释放规则」）；不造回合、不进 transcript、无可见面。
- 旧客户端：不认 `watch` ⇒ 忽略即合规（`_meta` 通用条款）。
- 旧 CLI：无 `watch` ⇒ `_watching` 恒假，释放回到静默期兜底（§19.8-10 / §19.11）。

**命名与取值层（本仓）**

- `_turnKey` = 常量 `"thincoder.dev/turn"`（`thincoder_kernel.dart` 类内 `static const`，与 `thincoder_events.dart:90` 的 `_subagentKey` 同形）。`_notification` 见 `session_info_update` 且 `_meta` 带本键 ⇒ 交 `_turnReport` 处置，不再进 `_events.update`（子代理翻译不读本键；不拦会逐帧落一条「a subagent report to leave alone」E4 日志）。
- `_turnUnprompted` = 内核侧「本轮是自动轮」位：`_beginTurn(id, unprompted: …)` 写入（用户回合缺省 false）。翻译表里「自动轮在飞 ∥ 用户回合在飞」与「`end` 是否本轮的收尾」都以它判定。
- `lastTurnUnprompted` = 宿主**既有** `Transcript` 字段（`transcript.dart:63`，由 `TurnStarted.unprompted` 喂，`kernel_event.dart:17` 既有参）——本批不新增、不改宿主；T68 / T73 断言读 `s.transcript.lastTurnUnprompted`（宿主层），不读内核私有位。
- `_watching` = 挂起窗在线位（D65）：`watch{on:true}` 置真、`watch{on:false}` 置假；`_teardown()` 清假。只这两处清——`prepare()` 不清：窗在不在是服务端事实，视图回来不改变它；`attach()` 是引用计数（`chat_session.dart:302-309`），若每次附加都清位，「离开 → 回来 → 再离开」的同一窗内下一次释放就失去窗开位（§19.8-13）。`on` 非布尔 ⇒ 忽略 + 留痕，**状态不动**（另一条窗帧总会到；不动比猜方向安全）。

- 发射点 = ACP 挂起窗的自动轮执行器：**轮起即发 start、轮收即发 end**（D61）。
- 只在**自动轮**发；用户回合（`session/prompt`）的边界 = 应答本身，不发。
- 旧客户端：不认本键 ⇒ 忽略即合规（`_meta` 通用条款）；批 7 桌面会把两帧记成 E4 日志「a subagent report to leave alone」，显示零变化。
- 旧 CLI：无本帧 ⇒ 桌面零 unprompted 回合，行为 = 今天（§19.11）。

**桌面翻译**（`thincoder_kernel.dart`，新增 `_turnReport`）：

| 帧 | 当前状态 | 处置 |
|---|---|---|
| `start` | 无在飞回合 | `_beginTurn('auto:<n>', unprompted: true)`（`_autoTurns` 计数；id 唯一即可） |
| `start` | 用户回合在飞 · 暂存位空 | **暂存** `_pendingAuto`（kind 留痕）；该回合 `TurnEnded` 后立刻起（D57） |
| `start` | 自动轮在飞 ∥ 用户回合在飞且暂存位已占 | 契约外：忽略 + `appEvent` 留痕（不覆盖已暂存的那轮） |
| `end` | 自动轮在飞 | `_endTurn(interrupted: ok == false)`；`ok` 非布尔也收轮（D63） |
| `end` | 用户回合在飞 · 暂存位非空 | **撤暂存** + 留痕（带 kind）：该轮 `end` 已到，不在桌面成轮（D62） |
| `end` | 无在飞回合 ∥ 用户回合在飞且暂存位空 | 契约外：忽略 + 留痕 |
| `watch` | — | `_watching = on`（布尔；非布尔 ⇒ 忽略 + 留痕，状态不动）；`on:false` ⇒ 再跑一次释放判定（`_releaseWhenIdle()`） |
| 其它 `phase` / `_meta` 坏形 | — | 忽略 + 留痕（E4） |

**`ok` 的宽容方向（D63）**：收轮的唯一信号是 `end` 本身，`ok` 只是中断标记。把「`ok` 非布尔」当坏帧忽略 ⇒ 在飞自动轮永不收（永久「正在续写」、队列永不排水），正是本批要消灭的停住态；按未中断收只丢一个中断标记。两个方向的代价不对称 ⇒ 取宽容。CLI 侧 `try … finally` 恒发布尔（§19.3-②），非布尔只可能来自别的写入者。

- 暂存的必要性（D57）：CLI 在应答写出后才起挂起窗（§19.3-①），但桌面可能**同批**收到应答与 `start` 两帧——应答的 `TurnEnded` 在微任务里，`start` 的通知先到。暂存到该回合结束再起：不丢 `stopReason`，也不误结束活回合。
- 暂存位的收尾（D62）：帧不带回合 id，配对只能按状态——挂起窗串行，同一时刻至多一个自动轮 ⇒ 暂存位非空 = 「该轮报过 `start`、还没起」，同一用户回合里到的 `end` 就是它的收尾，处置 = **撤暂存**：
  该轮在桌面不成轮（零 `TurnStarted(unprompted)`、零第二个 `TurnEnded`，`activeTurn` 仍是用户回合）。代价：那轮内容照样入 transcript，只是搭在用户回合的分组里（`lastTurnUnprompted` 保持 false）；
  用户回合收尾时暂存位已空 ⇒ `_drain()` 照常排水。撤暂存时 `auto:<n>` 的号照旧消耗（id 只需唯一，不要求连续）。
- `_pendingAuto` 在 `_teardown` 清（进程死 / 重启不留幽灵自动轮）。
- 自动轮 id = 客户端自持（`auto:1`、`auto:2`…），与用户 turn id 不冲突；item id 空间随 `_beginTurn` 的 `_events.begin()` 前进（`t<run>.<block>`）。
- 自动轮期间 `send` = 进本地队列（§18：`_turn != null` 分支），结束帧 `TurnEnded` 后由 `_drain()` 发出——与今天「挂起期直接写服务端 FIFO」的差别 = 队列面板可见、可撤回；§15.3「挂起期再发消息」已按此加「无在飞回合时」的限定。

**插入点（`_endTurn`；D57 的落点）**

暂存的自动轮在 `_endTurn` 里 `emit(TurnEnded)`（`:583-592`）之后、`if (_drain()) return;`（`:602`）之前起：

```dart
if (_pendingAuto != null) {
  final pending = _pendingAuto!;
  _pendingAuto = null;
  _beginTurn(pending.id, unprompted: true);
  return;
}
```

- 先起自动轮 ⇒ 本趟不排水、不释放：`_turn` 已非空（`_drain()` 即便被调到也返回 false；`release()` 的自守卫 `:417-426` 同样只置 `_releaseWanted`）⇒ 队列与释放都等自动轮收尾那次 `_endTurn` 再判（D53 的既有形不变）。
- 与 §18.1 的排水同一区间（`emit(TurnEnded)` 后、`_releaseWanted` 前）：有暂存自动轮 ⇒ 起轮并 return；没有 ⇒ `if (_drain()) return;` 照旧。
- 起轮行的 id = 暂存时的 `auto:<n>`；kind 只留痕（`appEvent`）。

**释放规则（D64 / D65 / D66）：子代理与挂起窗在 ⇒ `release()` / `dispose()` 都要延后**

缺口（2026-10-17 07:03 用户报告「切换对话好像会丢失子代理」）：最后一个视图离开 ⇒ `ChatSession.detach()` 的微任务调 `_kernel.release()`（`chat_session.dart:313-318`）；内核只在 `_turn != null || _starting != null` 时延后（`thincoder_kernel.dart:417-426`）。

挂起窗内无轮、后台池 live 时 `_turn == null` ⇒ 立即 `_closeSession()` + `_teardown()`（`:427-429`）⇒ 子进程被杀（`thincoder_process_io.dart:186-190` 的 `close()` = kill）⇒ 后台子代理随池清场。

- **谓词（桌面可判）**：`_turn != null || _starting != null || _events.hasLiveSubagents || _watching`。
- **窗开着本身是确定信号（D65）**：CLI 在窗进 / 出各发一条 `watch` 帧（§19.2「窗开关帧」）⇒ `_watching` 为真期间 `_canClose` 恒假，释放等窗关帧，不再赌时序。只按「有活着的子代理」判是间接的：最后一个子代理 settle 与消化轮 `start` 之间没有卡片可看（`hasLiveSubagents` 已假、`_turn` 还没起），静默期（一个 macrotask）只能盖住这一段——走查第二次缺陷（2026-10-17 08:26 用户「子代理结束的时候我切换了其它窗口项目，就会丢失」）就是帧分批一慢、落在静默期外被触发。
- **静默期保留（D65）**：旧 CLI 无 `watch` 帧 ⇒ `_watching` 恒假 ⇒ 释放走今天的一个 macrotask 兜底；新 CLI 下静默期照跑（同一段代码），但窗开着时先被 `_watching` 挡住，窗关帧到了才轮得到它——一条路径同时覆盖新旧 CLI。
- 新增 `ThincoderEvents.hasLiveSubagents` = `_subagents`（`thincoder_events.dart:61`）里有卡片 `status == running`。`queued` / `async` / `turn` / `approval` 都建成 running（`AgentItem` 缺省值，`chat_models.dart:213`）；`settled` / `stopped` / `done` 落 succeeded / failed；`cancelled` 删卡；未知态保持原状（按忙算，保守）。
- `_tasks` 不参与：queued 不上 strip（`thincoder_events.dart:451-457`），卡片才是全量。

**兑现点（三处）**

1. 轮末既有兑现（`_endTurn` 尾，`thincoder_kernel.dart:600-606`）：`emit(TurnEnded)` → 暂存自动轮 → `_drain()` → 本规则；自动轮收尾同样在此判。
2. 最后一个子代理离开 running / queued：每条 `session/update` 交 `_events.update` 之后（`_notification`，`:813`）跑一次「`_releaseWanted` 且空闲 ⇒ 起静默期」。
3. 窗关帧（`_turnReport` 的 `watch{on:false}` 分支）：置假后跑 `_releaseWhenIdle()`——`release()` / `dispose()` 在窗开期间一直没兑现，由这一帧把它放行。
   静默期 = 一个 macrotask（`Timer.run`），到点仍空闲（无轮 / 无启动 / 无 live 子代理 / 窗不在）⇒ `_closeSession()` + `_teardown()` + idle，即 `release()` 的关闭段。`prepare()`（视图回来）与 `_teardown()` 取消它（`_releaseWanted` 同时清）。

```dart
bool get _canClose => _turn == null &&
    _starting == null &&
    !_events.hasLiveSubagents &&
    !_watching;

@override
void release() {
  if (_disposed) return;
  if (_transport == null && _starting == null) return;
  _releaseWanted = true;
  _releaseWhenIdle();
}

@override
void dispose() {
  if (_disposed) return;
  _disposed = true;
  // What waited goes with the session: it was never sent.
  for (final turn in [..._queue, ?_next]) emit(ItemRemoved(nextSeq, turn.id));
  _queue.clear();
  _next = null;
  _pendingAuto = null;
  closeEvents(); // the host's surface goes at once (D66)
  if (_canClose) {
    _closeSession();
    _teardown();
    return;
  }
  // Work is still in the process: its turns are saved as they end, so the
  // session over is not the work cut short — same predicate, same silence
  // (D66).
  _releaseWanted = true;
  _releaseWhenIdle();
}

void _releaseWhenIdle() {
  if (!_releaseWanted || !_canClose) return;
  if (_transport == null && _starting == null) {
    _releaseWanted = false;
    return;
  }
  _releaseCheck ??= Timer(Duration.zero, () {
    _releaseCheck = null;
    if (!_releaseWanted || !_canClose) return;
    _releaseWanted = false;
    _closeSession();
    _teardown();
    _setHealth(KernelHealth.idle);
  });
}
```

- `_endTurn` 尾：`if (_releaseWanted) { … }` 整段换成 `_releaseWhenIdle();`（`_drain()` 起轮后已 return，不到这里）。
- `_notification`：`_events.update(update);` 之后加 `_releaseWhenIdle();`；但带 `_turnKey` 的帧在早返回前就被拦下（`:837-842`）——`watch{on:false}` 的放行由 `_turnReport` 的 watch 分支自己跑，不靠本行。
- 新增字段 `Timer? _releaseCheck`（静默期计时）与 `bool _watching`（窗在线位）；`prepare()`（`:409-418`）取消计时、清 `_releaseWanted`（视图回来 ⇒ 释放作废，下一轮释放按届时状态重判），**不清 `_watching`**（窗状态是服务端事实；`attach()` 引用计数下清位会让「离开 → 回来 → 再离开」丢窗开位——§19.8-13）；`_watching` 只由 `watch{on:false}`（四条退径都发）与 `_teardown()` 清（进程不在则窗也不在）。
- `_releaseWhenIdle` 同 `release()` 的空手守卫：`_transport == null && _starting == null` ⇒ 清 `_releaseWanted`、不排计时（进程已不在就没得释放）。
- **`_disposed` 从 `_releaseWhenIdle` 的两个守卫里去掉（D66）**：`dispose()` 也走这条关会话路径（否则延后永远兑现不了）；`release()` 自己的首行 `if (_disposed) return;` 挡住「disposed 之后的释放请求」。
- **`send()` 首行加 `if (_disposed) return;`**：disposed 后不再入队 / 起轮——`_deliver` 的 disposed 早退（`:506`）会 return 而不收轮，`_turn` 会留在非空，延后收场下将永久挡住关闭。
- `release()` 因此**恒晚一个 macrotask 关会话**（含空闲释放）；既有用例经 `settle()`（`pumpEventQueue`；`test_api-0.7.12/lib/src/scaffolding/utils.dart:16-19` 逐轮 `Future(…)` = 0ms 计时）泵过 0ms 定时器，断言预期不变——以实现轮实跑为准。
- `dispose()` 的代价（D66）：对象已 `disposed`（`_ensureStarted` 拒新启动、宿主事件面已关），关闭由 `_releaseCheck` 计时器持有，`stopped` 晚一拍兑现；在飞的轮 / 子代理继续跑完，关闭时 `_setHealth(idle)` 落在已 disposed 的对象上（无监听者，无害）。

**静默期为什么保留（旧 CLI 兜底）**：新 CLI 由窗帧接管（D65）——窗在 ⇒ 不关，窗关帧到了才放行，不再赌时序。
旧 CLI 没有窗帧：最后一个子代理 settle 的同一窗唤醒里，消化轮的 `start` 紧随其后（`async-settle.mjs:306` 先发 `⟦ev⟧settled`、`:311` 才唤醒；`acp/suspension.mjs` 的窗循环（`startSuspension` 的 `runTurn` 包装）发 start），

settled 那一刻关会话 = 杀进程 ⇒ 消化轮被截、报告丢失（F16 的反面）。一个 macrotask 让同批在飞的帧先落地：`start` 一到 `_turn != null` ⇒ 本次不关，转由兑现点 1 在轮收尾后关；同批覆盖「一轮消化收尾、下一轮已在窗里」（两个子代理先后结算）。
新 CLI 下静默期仍跑，但在窗开期间被 `_watching` 先挡住——它退化成「窗关后的一个 macrotask」，不再是判据本身。

- **静默期不造回合边界**：边界仍只由帧界定（D26 的禁忌不变）——它只决定「关会话」的执行时机。
- **`dispose()` 也按同一判据延后（D66）**：骨架见上，决策见 §19.5 D66。`restart()`（`:420-425`）与 `_launch` 尾的既有兑现（`:202-207`；启动中没有卡片可 live）不动。
- **代价与边界**（逐条登记 §19.8-10 / -11 / -12 / -13 / -14）：静默期在旧 CLI 上是唯一判据；后台 bash / browser / ssh 任务没有子代理帧 ⇒ 看不见，切走仍按今天释放；切走再切回的卡片 = 终态快照，不重建；`on:false` 帧若丢失（进程仍活着、帧未出线）⇒ `_watching` 停在真、释放不兑现，留到该会话下一次 `_teardown()`（判定条件见 §19.8-13）；`dispose()` 在卡片卡 running 时无上界兜底。

### 19.3 ACP 挂起窗（thincoder 仓；装配与收束）

**① 入口与装配**（`thincoder-cli/src/acp/session.mjs`；窗体新档 `acp/suspension.mjs`）

- 入口 = 每个用户回合收尾（`run()` 的 finally，`:31-50`）：先 `save(agent)`，再 `setImmediate(enterSuspension)`——**一个 macrotask** 保证 `session/prompt` 应答先出线（D60）。
- 闸三条：`closed` · `busy`（下一轮已开）· `poolLive(agent)` 假 ⇒ 不进。
- ctx 装配表：

| ctx 位 | ACP 装配 | 先例 |
|---|---|---|
| `carrier` | 会话的 `agent`（池 / pending / `_daSession` 都在它身上） | TUI `:208` · 桌面 `:252` |
| `inputQueue` | 窗内输入队（prompt 富条目 `{text, done}`） | 桌面 `entry.pending` `:253` |
| `runTurn` | 自动轮 / 用户唤醒轮两分发（②） | TUI `driveTurn` `:155-159` |
| `takeInput` | 不传（缺省 `shift`；ACP 无合并批 / 斜杠） | TUI `:164-170` |
| `injectResidual` | 核注入器（consult / 子代理两族分发） | 桌面 `:114-124` |
| `timerFace` | **不传**（§14-21） | 三端都传 |
| `hooks.*` | 全不传（ACP 无渲染面；卡片定格走帧 / 进程退出） | TUI `:220-225` |
| `abortSignal` | 窗控制器（`cancel` / `close` 触发） | TUI `:193` |

- 起身时 `agent._sessionAbort = controller`、`agent._sessionSignal = controller.signal`（桌面 `:249-250` 同形）：窗内 spawn 的子代理链到会话信号，中止时逐条 `⟦ev⟧stopped`（§15.2 的定格来源）。
- `session/cancel` 的射程（D59）：有轮在飞 ⇒ abort（在飞轮 `end{ok:false}` 后退出，池按核 abort 清场）；空闲 ⇒ 零动作（不杀后台池）。
- `session/close` / load·resume·new 替换旧实例 ⇒ `close()`（无条件 abort）：4 处调用点 `cancel()` 改 `close()`，净 0 行——`handlers-session.mjs:306` / `:367`、`handlers-slots.mjs:95` / `:165`。
- **窗开关帧（D65）在窗体里发**（`session.mjs` 零改）：建窗即 `watch{on:true}`（先于本窗任何轮帧——`startSuspension` 的循环在同步段就可能起消化轮）；退出在窗 `done` 的 `finally` 发 `watch{on:false}`（四径同达）；建窗失败由 `catch` 补 `on:false` 再上抛（§19.2「窗开关帧」）。

**② 两种轮**

| 轮 | 何时 | 调用 | 帧 | 应答 |
|---|---|---|---|---|
| 自动轮 | pending 非空 ∥ 上行 ask | `run(agent, "", digestCallbacks, {signal, autoTurn: true, upstreamTurn: <本轮是上行 ask>, suspDriven: true})` | start / end | 无（无请求） |
| 用户唤醒轮 | 挂起期 `session/prompt` 到达 | `run(agent, text, callbacks, {signal, suspDriven: true})` | 不发（应答即边界） | 该 prompt 的应答 |

- **普通用户回合（窗外）同带 `suspDriven: true`**（`session.mjs:106-109`：`runNormal` 的 `execTurn(input, { suspDriven: true })`；窗内两型轮由窗包装补同旗，`suspension.mjs:100-102`）：与终端同源（TUI 恒传 `tui/agent-turn.mjs:194`）。
  不传 ⇒ 用户回合进行中结算的子代理条目被该轮在回合尾收走（核 `run-stages.mjs:283` 的 fallback：直接注入并出池）⇒ 回合尾 `poolLive` 假、不开窗、桌面无自动续轮——F16 症状的最窄实例。
  影响面：用户回合的工具轮收尾不再注入到期 timer（`post-turn.mjs:23`）；交付面与判定条件见 §19.8-1。
- `digestCallbacks` = `{...callbacks, onPermissionRequest: undefined}`（D58）；`question` / secret 面本就无（装配期剔除 / 拒件）。
- **回调缺席时的判决 = 直接拒绝**（D58）：需审批的工具调用不再挂起等面板，按拒绝答复模型；与终端手动档 digest 同判。ACP 桥侧「无回调 ⇒ 拒绝」的真实实现本仓不可读（`unverified`）——out-of-repo 轮先核对该位，W5② 钉住；若实际是放行 ⇒ 停，回主 agent（静默越权不落档）。
- **自动轮失败**（模型 / 工具 / 注入抛错）：`try … finally { emit(end, ok: false) }` **必发收尾帧**，异常再上抛给窗执行器（窗随核语义收窗；下一次回合尾再进窗）。`end` 若漏发，桌面 `activeTurn` 永不收 ⇒ 永久「正在续写」，正是本批要消灭的停住态。
- **upstream 轮的返回路**：模型在 `upstreamTurn` 轮的答话 = 对该 ask 的回复，经核 consult 注入面回给等着的子代理（核侧具体注入入口名本仓不可读，`unverified`；out-of-repo 轮按核现有注入面接线，W7 钉住）。桌面侧只收文本——本仓内核没有「回复子代理」的请求面，答话就是普通消息。
- 用户唤醒轮失败：先拒该 prompt 的应答、再上抛（窗随核语义收窗；下一次回合尾再进窗）——与桌面 / VSC 同形。
- 每轮 finally `save(agent)`（TUI `agent-turn.mjs:360-365` 同口径）：消化轮的答话落槽，`session/load` 可见。

**③ 挂起期的 prompt**：`run(input)` 见窗 ⇒ `handle.pushInput({text, done})` + `wake()`；返回 `done` 的 promise（`session/prompt` 照旧等它）。核输入优先序 = 窗内第 1 步（`suspension.mjs:251-269`）：自动轮在飞 ⇒ 排在这轮之后；空闲 ⇒ 立刻开用户轮。
- 窗退出残余（idle）：`residualInput` 逐条按普通回合补发（VSC `resumeResidual` 形；竞态兜底）。
- 窗中止残余：逐条以待答 `AbortError` 拒 ⇒ `session/prompt` 回 `{stopReason:'cancelled'}`。

**④ 收束**

| 事件 | 挂起窗 | 桌面 |
|---|---|---|
| 池空 | 自然退出（`watch{on:false}` 随 `done` 的 finally 出线）；`finishSuspension(idle)` 注入残余 | 最后一轮 `end` ⇒ `TurnEnded`；卡片已 settled；窗关帧 ⇒ `_watching` 假 ⇒ 静默期后释放 |
| `session/cancel`（轮在飞） | abort（`watch{on:false}`）⇒ 在飞轮 `end{ok:false}` ⇒ 核 abort 清场 | `TurnEnded(interrupted: true)` + 存活子代理的 `stopped` 帧 ⇒ 卡片 failed |
| `session/close` | `close()` ⇒ 同上（`watch{on:false}`；进程若先行退出则帧可能未出线——`_teardown()` 清 `_watching`） | 会话已关（进程随后退出） |
| 进程退出 / 管道断 | 随进程消失（无窗关帧） | 既有 `_exited`：在飞轮 interrupted + 通知；`_teardown()` 清 `_watching` |

### 19.4 受影响文件清单（E2 增量；行数 = 2026-10-17 只读实测）

**本仓（baocode）**

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ㉟ | `lib/kernel/thincoder/thincoder_kernel.dart`（1113） | 回合边界翻译：`_turnKey` · `_autoTurns` / `_turnUnprompted` / `_pendingAuto` · `_beginTurn` 加 `unprompted` 参 · `_endTurn` 起暂存自动轮（`emit(TurnEnded)` 后、`_drain()` 前）· `_notification` 拦截 · `_turnReport` · `_teardown` 清暂存 · 释放延后（D64） · **窗开关帧翻译（`_watching` / `_canClose` / `dispose()` 延后——D65 / D66）**（细见 §19.2） | ≤ +45（⇒ ≤1072）；实交 +43（⇒ 1070）· 修正轮 2 ≤ +12（⇒ ≤1082）· 修正轮 3 ≤ +35（⇒ ≤1114）· **修正轮 4 ≤ +35（⇒ ≤1148）** |
| ㊱ | `test/kernel/thincoder_kernel_test.dart`（2570） | T68–T76（§19.7） | ≤ +170（⇒ ≤2473）；实交 +168（⇒ 2471）· 修正轮 2 ≤ +45（⇒ ≤2516）· 修正轮 3 ≤ +60（⇒ ≤2576）· **修正轮 4 ≤ +60（⇒ ≤2630）** |
| ㊲ | `test/fixtures/thincoder/digest-turn.ndjson`（新增） | 新线形场景（start / 文本 / end） | 9 行（原估 ~15） |
| ㊳ | `test/kernel/thincoder_fixtures_test.dart`（211） | `_check` 增 `unprompted` 键 | +3 |
| ㊴ | `test/fixtures/thincoder/README.md` | `expect` 键清单补 `unprompted`；一句回合边界说明 | +3（32 → 35；原估 +2） |
| ㊵ | `lib/kernel/thincoder/thincoder_events.dart`（778） | `hasLiveSubagents` getter（D64：卡片里有无 `status == running`；细见 §19.2） | ≤ +6（⇒ ≤784；仍 <800） |
| — | 其余本仓档 | **零改动**：`thincoder_mock.dart` · `chat_session.dart`（`detach()` 照旧只调 `release()`——延后在核内） · `chat_history_view.dart` · `workspace.dart` · `attention_service.dart` · `tips/**` · `l10n/**` | 0 |

**thincoder 仓（out-of-repo 轮执行；该仓自己的批次档 + 单元测试随档）**

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `thincoder-cli/src/acp/suspension.mjs`（新增） | 挂起窗：输入队 · 自动 / 用户轮分发 · 边界帧 · **窗开关帧** · cancel / close · 残余 | 新增 ~150 + 窗开关帧 ~15 |
| ② | `thincoder-cli/src/acp/session.mjs`（55） | 回合执行器抽 `execTurn`（含 save）· 回合尾进窗 · 挂起期 prompt 路由 · `cancel` / `close` | +65（⇒ ~120） |
| ③ | `thincoder-cli/src/acp/handlers-session.mjs`（427） | `cancel()` ⇒ `close()` 两处（`:306` new 替换、`:367` close） | 净 0 |
| ④ | `thincoder-cli/src/acp/handlers-slots.mjs`（226） | `cancel()` ⇒ `close()` 两处（`:95` load、`:165` resume） | 净 0 |
| ⑤ | `thincoder/docs/cli/design/ACP-CLIENT.md`（641） | §12.8「回合边界扩展契约」（§19.2 的线上形 + 兼容句；**含 `watch` 行**）+ §3.2 会话层一句（挂起窗） | +~45 |
| ⑥ | `thincoder/docs/core/design/AGENT-LOOP-ASYNC-POOL.md` | `:442`「CLI headless / ACP ❌ 不支持」行改「ACP 已支持（ACP-CLIENT §12.8）」 | 1 行 |
| ⑦ | `thincoder/docs/batches/2026-10-17-acp-suspension.md` + 同名 `.test.mjs` | 该仓批次档（§1–§6）+ 单元测试档（假 run 直驱 `createAcpSession`；该仓惯例 = 测试档随批次档） | 新增 |

- **体量**（2026-10-17 修正轮 3 后实测 + 修正轮 4 预估）：`thincoder_kernel.dart` 1113 行（修正轮 4 ≤ +35 ⇒ ≤1148）在 >800 名单；本批 = 会话面行级新增，不动结构 ⇒ 不触发「先立拆分批」；会话面缝候选（§18.4 所列）**追加** `_turnReport` / 释放延后 / 窗开关与 `dispose` 延后三条，触发不变。`thincoder_events.dart` 784（<800；批 11 后 ⇒ ≤807 入名单，见 §5.2）。
  `session.mjs` 与新增档均 <500 行。测试档 2570 在 >800 名单：只加用例，缝候选沿用 §15.4。
- **out-of-repo 边界**：上述 ①–⑦ 由父侧另起 out-of-repo 轮，在 thincoder 仓写它自己的批次档与测试（本仓只出设计，不写外仓文件）。

### 19.5 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D55 | 挂起驱动住在 ACP 会话层（CLI 内），不在桌面 | 池 / pending / `_daSession` 都在子进程的 agent 上，桌面拿不到；核状态机 `startSuspension` 直接复用（三端同源）。被否：桌面定时问「好了没」——无信号源且与终端不同形；被否：桌面按文本猜回合——D26 已否 |
| D56 | 回合边界 = `session_info_update` 的 `_meta["thincoder.dev/turn"]`；不新增 `sessionUpdate` 变体、不加版本门 | ACP v1 无无提示回合的位置；`_meta` 是协议自带扩展位（thincoder/docs/cli/design/ACP-CLIENT.md §12.1 先例）；未知变体对严格客户端是未知枚举，`_meta` 忽略即合规（E4 / E3）。被否：桌面按首个 chunk 合成回合（无收束信号，D26）；被否：新变体 `turn_started` / `turn_ended`（协议面越界） |
| D57 | `start` 在用户回合在飞时**暂存**，由该回合 `TurnEnded` 起点；不从信号强制结束回合 | 应答与 `start` 可能同批到达（应答的 `TurnEnded` 在微任务里）；暂存不丢 `stopReason`、不误结束活回合。被否：按信号强制结束用户回合（取消态会丢 interrupted 标记） |
| D58 | 自动轮剥 `onPermissionRequest`（手动档不弹审批）；回调缺席 ⇒ **直接拒绝** | 与终端 D-S7 同判（`tui/suspension-drive.mjs:100-112` 置 null）；无人值守的轮不得挂起等一个没人应答的面板（5 分钟超时也按拒绝）。回调缺席的判决 = 拒绝 ⇒ 自动轮不会静默越权执行需审批的工具。桥侧实现本仓不可读（`unverified`），W5② 钉住。ACP 其余交互位本就无面。被否：照常问审批（与终端不同形）；被否：缺席按放行（静默越权） |
| D59 | `session/cancel` 射程 = 有轮在飞才 abort；空闲时零动作。`session/close` 无条件 abort | cancel 的协议语义 = 停「当前工作」；空闲窗没有工作可停，杀后台池会误伤在跑的兄弟任务。close = 会话收束，必须清场（终端 Ctrl+C 同形） |
| D60 | 进窗点 = 回合尾 + 一个 macrotask（`setImmediate`） | 应答必须先出线（否则自动轮帧与用户回合的收尾同批，客户端会把它们并进用户回合）；不需要应答确认（客户端按 D57 暂存兜住同批） |
| D61 | 自动轮 start 帧**轮起即发**（eager），不按首个输出帧惰性发 | 三端先例（VSC / 桌面 / TUI 都在轮起发边界帧）；「正在续写」指示从轮起可见；空轮无项可显示，残影只有罕见的未读徽标（§19.8-7）。被否：惰性 start（要在出站面拦首个帧，且早失败时没有任何可见面） |
| D62 | 暂存中的自动轮在自己的 `end` 到达时**撤暂存**（该轮在桌面不成轮），不起-再-收 | 帧无回合 id，配对只能按状态：挂起窗串行 ⇒ 同一时刻至多一个自动轮，暂存位非空 = 「报过 `start`、还没起」⇒ 同一用户回合里到的 `end` 就是它的收尾。撤暂存不造空轮、不造一对没人看的边界帧，实现面只多一个分支。代价写清：那轮内容仍入 transcript，只是搭在用户回合的分组里、`lastTurnUnprompted` 保持 false。被否：先起后收（用户回合收尾时起一个随即收的 0 项轮）——桌面多一对幽灵边界，`interrupted` 还要按一个早已过去的 `ok` 补标，空回合的未读残影（§19.8-7）从稀有变常规；被否：帧里加回合 id（外仓协议面扩字段，批 8 契约已定形，收益只在这一条罕见错序） |
| D63 | 自动轮在飞时收到的 `end` **一律收轮**；`ok` 只认布尔 `false`（缺省 / 非布尔 / 其它值 ⇒ 按未中断收） | `end` 是唯一的收轮信号；把 `ok` 坏形当坏帧忽略 ⇒ 在飞轮永不收 = 永久「正在续写」+ 队列永不排水（本批要消灭的停住态）。误判方向取「未中断」：只丢一个中断标记，不丢回合边界。CLI 侧恒发布尔（§19.3-②），非布尔只可能来自别的写入者。被否：`ok` 坏形 ⇒ 忽略整帧（缺口原文，失败态不可恢复）；被否：`ok` 坏形 ⇒ 按中断收（把「不知道」标成「出错」） |
| D64 | `release()` 的延后判据加上「有活着的子代理」（`_turn != null || _starting != null || _events.hasLiveSubagents`）；关会话在一个 macrotask 的**静默期**后兑现（轮末 + 每帧 + 窗关帧三处） | 后台池 live 期间窗一直开着，卡片 running 是可用且直接的忙相（窗开关帧由 D65 补上后成为主信号）。静默期 = 旧 CLI 的时序兜底：最后一个子代理 settle 的同一窗唤醒里，消化轮 `start` 紧随其后（`async-settle.mjs:306` 先发 settled、`:311` 才唤醒；`acp/suspension.mjs:66-67` 发 start），当场关 = 杀进程 ⇒ 消化轮被截、报告丢失（F16 的反面）。静默期只决定关闭时机，不造回合边界（D26 不变）。被否：最后一个离开即关（丢消化轮）；被否：按卡片终态判「有没有消化轮要来」（窗可能不在 ⇒ 结果留池等下一回合，仍会永等）；被否：秒级长计时（无信号依据，把释放拖成计时行为） |
| D65 | 挂起窗进 / 出各发一条 `watch` 帧（同一 `_meta` 键，`phase:"watch"` + 布尔 `on`）；`_canClose` 加 `!_watching`；静默期降为旧 CLI 兜底 | 走查第二次缺陷（2026-10-17 08:26 用户：「子代理结束的时候我切换了其它窗口项目，就会丢失」）根因 = 释放靠时序：最后一个子代理 settle 与消化轮 `start` 之间桌面没有卡片可看（`hasLiveSubagents` 已假、`_turn` 还没起），一个 macrotask 的静默期正是这一段；机器 / 帧分批一慢就落在静默期外。窗进 / 出是 CLI 自己确知的事实 ⇒ 变成确定信号，释放不再赌时序。旧 CLI 无此帧 ⇒ `_watching` 恒假，静默期照旧（§19.8-10 / §19.11）。被否：加长静默期（仍是时序，慢机器仍丢，且拖慢所有释放）；被否：桌面轮询窗状态（无请求面）；被否：把窗开关并进 `start` / `end`（有轮才有帧，空窗那段表达不了——正是要判的那段）；被否：按卡片终态推断（D64 已否） |
| D66 | `dispose()` 也按同一谓词延后收场（同兑现点、同静默期）；`closeEvents()` 立即关 | `dispose()` 今天无条件 `_closeSession()` + `_teardown()`（`thincoder_kernel.dart:467-472`）⇒ 切项目窗口 / 收起会话 = 杀在跑的子代理与窗里的消化轮；会话存档按回合落盘（`session.mjs` 每轮 `save`）⇒ 延后让最后一轮落盘，用户回来还能看到。代价：对象已 `disposed`（`_ensureStarted` 拒新启动、宿主事件面已关）；关闭由计时器持有，`stopped` 晚一拍兑现；`_disposed` 从 `_releaseWhenIdle` 的守卫里去掉，改由 `release()` 自己的首行守卫挡。`closeEvents()` 立即：宿主已取消订阅，`emit` 有 `isClosed` 守卫（`agent_kernel.dart:403`），翻译层（`ThincoderEvents`）不依赖事件流仍继续收帧到进程收场。被否：`dispose()` 照旧立即关（本条缺陷）；被否：dispose 不关、等下次启动再收（进程泄漏、无兑现点） |

### 19.6 验收对照（回指需求档 F16）

| F16 条目 | 本档落点 | 判据 |
|---|---|---|
| 回合结束后继续关注后台子代理：子代理结算后主 agent 自起一轮 | §19.1 + §19.3-①② | 走查 2–4；CLI 单测 W1（回合尾进窗、消化轮被调用） |
| 看见其报告、回到「该用户批准 / 下一步」 | §19.2（`TurnEnded` → 宿主既有 unread / needsInput 面） | T68；走查 4（切走再回看：未读徽标在） |
| 终端与桌面同形 | §19.3（同一核状态机）+ §19.2（同一帧） | 走查 9（两侧同场景对照）；upstream 轮的起止与回注 = W7 |
| 不刷新、不靠用户发话 | 无用户消息的自动轮（`unprompted`） | T68（transcript 只有 `text:`，无 `user:`） |
| （派生）自动轮可见：运行中 / 可停止 / 结束 | §19.2 + D61–D63 + `cancel()` 既有面 | T68 / T71（② = 失败收尾）/ T73 / T74①②（错序与坏 `ok` 都不造永不收的轮） |
| （派生）自动轮期间发消息 | §19.7 T70（接 §18 本地队列） | T70 |
| （派生）收束：关闭 / 取消 / 进程退出 | §19.3-④ | T72 + W3 / W4 / W6（自动轮抛错 ⇒ `end{ok:false}`） |
| （派生）切走视图 / 切走项目窗口不丢后台子代理 | §19.2「释放规则」（D64 / D65 / D66） | T75①–③（卡片忙 ⇒ 不写 `session/close`）· T76①–③（窗帧 ⇒ 释放确定；旧 CLI 兜底；`dispose()` 延后）· W8（窗进 / 出各一帧） |
| （派生）旧 CLI 兼容（静默 = 今天） | §19.11 | 既有 `subagent-digest` 固件保持绿（不改）+ 走查 8 |

### 19.7 用例表（T68–T76 本仓；W1–W10 thincoder 仓）

**本仓**（`test/kernel/thincoder_kernel_test.dart`；mock `push` 直推边界帧，零 mock 改动）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T68 | 自动轮全形 | `start{kind:digest}` → 文本块 → `end{ok:true}` | `TurnStarted(unprompted: true)`；文本入 transcript 且无 `user:` 项；`transcript.lastTurnUnprompted == true`；`transcript.lastTurnInterrupted == false`；`activeTurn == null` |
| T69 | 应答与 start 同批（D57） | ① `hold` 下 `send('one')`；用户回合在飞时 push `start`；`release` | ① 用户回合按应答收尾（`TurnEnded` 一条）；start 暂存 → 随该 `TurnEnded` 起点（第二个 `TurnStarted`，unprompted）；无丢帧、无重复 `TurnEnded`；② = 有排队消息的同批形，见下「补项」 |
| T70 | 自动轮期间发消息（接 §18） | `start` → `send('two')` → `end` | 在飞时 `two` 进队列（`transcript.queued` 1 项、prompt 仍 1 条）；`end` 后 `session/prompt` 第二条 = `two` |
| T71 | 取消自动轮 | `start` → `cancel()` → `end{ok:false}` | 写出 `session/cancel`；`TurnEnded(interrupted: true)`；`activeTurn == null`；② = 非本端 `cancel()` 来源的失败收尾，见下「补项」 |
| T72 | 自动轮中进程死 | `start` → 文本 → `crash()` | `TurnEnded(interrupted: true)` + `notice error` + health failed（既有路径） |
| T73 | 空自动轮 | `start` → `end{ok:true}` | 零项；`transcript.lastTurnUnprompted == true`；`activeTurn == null`；无幽灵卡片 / 无文本 |
| T74 | 坏形 / 乱序（E4） | `_meta` 非映射 · `phase` 未知 · 用户回合在飞（暂存位空）时 `end` · 自动轮在飞时第二个 `start` | 忽略 + 各留痕一条；回合状态不变 |
| T75 | 切走视图时后台还在（D64） | ① push `signal('a', 1, 'queued')` → `release()` → settle；② 续 ① push `signal('a', 1, 'settled')` → settle | ① 零 `session/close`、`health` 仍 ready（queued 也算忙）；② 静默期到点：`session/close` 一条、`health` idle；`await s.kernel.stopped` 兑现 |
| T76 | 切走项目窗口不丢后台子代理（D65 / D66） | ① 窗开着就等窗关；② 旧 CLI 无窗帧；③ `dispose()` 时有 live 子代理 | 见下「补项」T76①–③ |

**补项（T69② / T71② / T74① / T74② / T75② / T75③ / T76①–③）**

| 子项 | 输入 | 期望 |
|---|---|---|
| T69② | 用户回合在飞时 `send('two')`（进队列）+ push `start`，然后 `release` | 暂存自动轮先起（`two` 不随用户回合发出，prompt 仍 1 条）；自动轮 `end` 后 `two` 才发出（prompt 第 2 条）——§19.2「插入点」 |
| T71② | `start` → `end{ok:false}`（非本端 `cancel()` 来源） | 零 `session/cancel`；`TurnEnded(interrupted: true)`、`activeTurn == null`、`transcript.lastTurnInterrupted == true` |
| T74① | 暂存 + 同回合 `end`（D62） | `hold` 下 `send('one')`；用户回合在飞时 push `start{kind:digest}`，同一回合内再 push `end{ok:true}`；`release` | 桌面只见用户回合一对边界（`TurnStarted` 1 / `TurnEnded` 1）；无 `auto:` 轮、无第二个 `TurnEnded`；`release` 后 `activeTurn == null`、`lastTurnUnprompted == false`；该 `end` 留痕一条；随后 `send('two')` 直接写出 `session/prompt`（无在飞轮挡路） |
| T74② | `ok` 非布尔（D63） | 两条独立会话：① `start` → `end{ok:"false"}`；② `start` → `end`（键缺席） | 两次都**收轮**：`TurnEnded(interrupted: false)`、`activeTurn == null`、`lastTurnInterrupted == false`；① 另留痕一条 |
| T75② | 消化轮紧跟着来（D64） | 续「`async` 卡片 + `release()`」（零 close）→ 同一批 push `settled` + `turn('start')` → settle → push `turn('end')` → settle | 静默期到点仍零 close（`activeTurn == 'auto:1'`）；`end` 后的静默期才关：`session/close` 一条、`activeTurn == null` |
| T75③ | 切回取消延后（D64） | `async` 卡片 + `release()` → `prepare()` → push `settled` → settle | 零 `session/close`、`health` ready（视图回来 ⇒ 释放作废） |
| T76① | 窗开着就等窗关（D65） | push `watch{on:true}` → push `signal('a', 1, 'async')` → `release()` → settle（零 close）→ push `signal('a', 1, 'settled')` → settle（零 close）→ push `turn start{kind:digest}` → settle（`activeTurn == 'auto:1'`、零 close）→ push `turn end{ok:true}` → settle（零 close，`_watching` 仍真）→ push `watch{on:false}` → settle | 窗开期间零 `session/close`（含卡片已 settled、消化轮未起的空档）；窗关帧后的静默期到点：`session/close` 一条、`health` idle、`stopped` 兑现 |
| T76② | 旧 CLI 无窗帧 ⇒ 静默期兜底（D65） | 同 T76① 但**不发** `watch` 帧：`async` 卡片 + `release()` → 同批 push `settled` + `turn start` → settle → push `turn end` → settle | 行为 = T75②（静默期让同批帧落地；消化轮在飞 ⇒ 轮末才关）；无窗帧时 `_watching` 恒假 |
| T76③ | `dispose()` 延后（D66） | push `watch{on:true}` + `signal('a', 1, 'async')` → `dispose()` → settle（零 close；此后 `send` 不入队）→ push `signal('a', 1, 'settled')` + `watch{on:false}` → settle | `dispose()` 不立即 `session/close`；窗关 + 空闲后的静默期到点：`session/close` 一条、`stopped` 兑现；`stopped` 在 dispose 时不兑现 |

**thincoder 仓**（`docs/batches/2026-10-17-acp-suspension.test.mjs`；假 run / 假 agent 直驱 `createAcpSession`）

| # | 场景 | 期望 |
|---|---|---|
| W1 | 回合尾进窗 + 消化轮 | 池 1 项 running：prompt 应答后（微任务）`run` 第二次被调用 = `("", {autoTurn:true, suspDriven:true})`；出站见 `start` / `end` 两帧；池清后窗退出 |
| W2 | 挂起期 prompt | 窗在 + 假池 live：`session/prompt` 的输入进窗队；用户轮被调用；应答按该轮结果返回 |
| W3 | cancel | 轮在飞时 `cancel()` ⇒ 窗 abort、`end{ok:false}`、在飞轮中止；排队 prompt 应答 = `cancelled`；空闲时 `cancel()` ⇒ 零 abort |
| W4 | close | `close()` ⇒ 窗无条件 abort、池清场、后续 `run()` 正常 |
| W5 | 手动档审批剥离与缺席判决 | 假 `autoApprove=false`：① 消化轮收到的 callbacks 无 `onPermissionRequest`；用户轮的有；② 假 agent 在自动轮里对需审批工具发反向请求 ⇒ 判决 = 拒绝（工具不执行），不是放行 |
| W6 | 自动轮抛错 | 假 run 在自动轮抛错：出站必见 `end{ok:false}`；窗按核语义收窗（无在飞轮残留）；下一次回合尾照常再进窗 |
| W7 | upstream 轮 | 假池有未 drain 的上行 ask：`run` 以 `upstreamTurn: true` 被调用；答话经核注入面回给等着的子代理（假 agent 断言注入被调用）；出站见 `start` / `end` 两帧 |
| W8 | 窗开关帧（D65） | ① 建窗时 `_pendingAsyncResults` 非空（消化轮同步起）⇒ 出站第一帧是 `watch{on:true}`，其后的 `start` 在它之后；② 窗自然退出 ⇒ 恰一条 `watch{on:false}`，在最后一个 `end` 之后；③ 轮在飞时 `close()` ⇒ `watch{on:false}` 仍出站（至多一对，不重发） |
| W9 | 窗内两型轮的 `suspDriven` | 窗内自动轮与用户唤醒轮核收到的 opts 均 `suspDriven === true`（自动轮另带 `autoTurn:true`）；核据此把已结算条目留池给窗消化（`run-stages.mjs:283`），而不是本轮回退自收 |
| W10 | 普通回合（窗外）的 `suspDriven` | 窗外 `session/prompt` 起的普通回合核收到 `suspDriven === true`、`autoTurn:false`；普通回合不发回合边界帧。留池的核侧语义由 `run-stages.mjs:283` 保证（单测按 opts 断言）——与 TUI 同源（`tui/agent-turn.mjs:194`） |

W 侧判据不变：CLI 的 `end` 恒发布尔 `ok`（成功 = true；抛错 = false，`try … finally`）——D63 的宽容是客户端防御，不进 W 的判据。

**固件**：新增 `test/fixtures/thincoder/digest-turn.ndjson`（新线形：`start` → 文本 → `end`；`expect` 含 `unprompted: true`）；既有 `subagent-digest.ndjson` **不改**——它就是「旧 CLI 无信号」的兼容哨兵（§19.11）。

### 19.8 边界（批 8 不做）与登记（判定条件）

1. **timer 唤醒轮不接**：无 `timerFace`（§19.3-①）。窗内轮与普通轮都带 `suspDriven:true`（§19.3-②）后，核在工具轮收尾不再注入到期 timer（`core/agent/post-turn.mjs:23`：`suspDriven && timerWakeEnabled` ⇒ 到期件留在途、零出列）；ACP 无 `timerFace`、无空闲闩 ⇒ 没有交付面，也没有「下一个非驱动的工具轮」可顺延（本批之后 ACP 的每条轮都经 `execTurn` 带旗）。到期件不丢、不出列，直到接 `timerFace`（或 `timerWake` 显式关 ⇒ 核回退面逐字注入）。判定条件：桌面需要 timer 唤醒（终端 `pendingTimerDeadline` / `deliverExpiredTimers` 对位）⇒ 接 `timerFace`（`suspension.mjs:173-205` 第四态）并给 `kind:"timer"`。
2. **自动轮不请求审批**（D58）。判定条件：产品要「自动轮也能请求审批」⇒ 去掉剥离 + 明确无人应答的兜底（反向请求 5 分钟超时按拒绝）。
3. **自动轮在重放（session/load）里没有回合边界**：重放只还原消息（`bridge.mjs:402-461`），不合成回合——与今天一致。判定条件：需要在重放里也分组 ⇒ 扩展重放面（另立）。
4. **取消自动轮 = 停整个后台会话**（D59）：窗 abort 后核清场，存活子代理中止。不做「只停这一轮、后台继续」——核驱动只有会话级 abort；判定条件：核提供回合级 abort 缝。
5. **自动轮不生成会话标题**：ACP 本就不生成（`ensureSessionTitle` 只在 TUI 面）。
6. **自动轮的问答面**：`question` 工具装配期已剔除、secret 拒件——自动轮没有问答面（与 2 同源）。
7. **空自动轮**：起止帧照发（D61），无项可显示；罕见的零输出失败会在侧栏留一个未读徽标而无新内容。判定条件：走查反复观察到「徽标在、没内容」⇒ 宿主侧对空回合抑制未读（宿主改动，另立）。
8. **旧桌面 + 新 CLI**：本键的帧（`start` / `end` / `watch`）进旧翻译层 ⇒ E4 日志（`thincoder_events.dart:429-431` 形），显示零变化——登记；不做版本门（E3）。
9. **进程强杀**：挂起随进程消失；后台 bash 树可能残留（与终端硬退同形）——沿用 §14-12 口径，不新增机制。
10. **静默期只在旧 CLI 上是唯一判据**（D65）：新 CLI 有窗开关帧 ⇒ 释放由窗关帧确定（§19.2「释放规则」）；旧 CLI 无此帧 ⇒ `_watching` 恒假，
    仍靠一个 macrotask 让 `settled` 与消化轮 `start` 同批帧落地（`async-settle.mjs:306` → `:311` → 窗循环（`startSuspension` 的 `runTurn` 包装））；
    `start` 若晚于一个 macrotask 才到（帧分两次读入）⇒ 该轮消化被截。判定条件：旧 CLI 下走查见到「子代理卡片已 settled、对话里没有消化文本」⇒ 要求升级 CLI（能力按帧在场判定，不加版本门）；
    新 CLI 下同一现象 ⇒ 按窗帧链路复查（窗关帧是否先于最后一条 `end`，W8②）。
11. **释放延后只覆盖子代理面**：后台 bash / browser / ssh 任务没有 `⟦ev⟧` 帧（`thincoder-core/agent-tools` 三族零发射）⇒ 桌面看不见，切走仍按今天直接释放、随进程消失。判定条件：用户报告「切走丢了后台 bash / 浏览器 / SSH」⇒ 给三族补状态帧，再把谓词扩到它们。
12. **切走再切回：子代理卡片 = 终态快照，不重建**：释放时 `_teardown` 调 `_events.endSubagents()`（`thincoder_events.dart:504-531`，清 `_subagents` / `_tasks`）；再开是 `session/resume`（`_loaded` 后不再 `session/load` 重放，`thincoder_kernel.dart:256-262`）⇒ 重放只有消息，卡片停在终态、不再随新会话更新。
    判定条件：产品要求切回后卡片仍可点开 / 看子代理详情 ⇒ 把子代理状态搬进会话存档并在重放面合成卡片（外仓 + 设计另立）。
13. **`prepare()` 不清 `_watching`（裁定）**：窗在不在是服务端事实，视图回来不改变它；`attach()` 是引用计数（`chat_session.dart:302-309`），`prepare()` 每次附加都会被调到，若在此清位，
    「离开 → 回来 → 再离开」的同一窗内（窗一直开着、期间没有新帧）下一次 `release()` 就失去 `!_watching` 这一位，退回静默期兜底（与 10 同一段时序）——正是本批要消灭的东西。

    故 `_watching` 只由 `watch{on:false}`（四条退径都发）与 `_teardown()` 清。代价：`on:false` 帧若丢失（进程仍活着、帧未出线），`_watching` 停在真 ⇒ 桌面判忙、进程不释放，直到该会话下一次 `_teardown()`。
    判定条件：走查见到「窗早已退出（无子代理、无在飞轮）而桌面仍判忙」⇒ 说明 `on:false` 帧丢了，按 E4 留痕补（帧链路日志），并核 CLI 出站面（W8②）。
14. **`dispose()` 延后无上界兜底**：谓词与 `release()` 同一套；卡片卡在 running（CLI 已无对应池项、不再发帧）⇒ 进程不释放（今天 dispose 立即杀）。判定条件：走查 / 现场见到「已关闭的会话进程残留」⇒ 给 release / dispose 共享一个上界（秒级计时），或按卡片 `updatedAt` 判超时。

### 19.9 UI / 交互决定（全部落地，无 open）

- 自动轮 = 宿主既有「无提示回合」：侧栏运行中（`workspace.dart:158-177`）、**不**自动滚到底（`chat_history_view.dart:1162-1194` 的 `sent` 判定）、完成不响铃（`attention_service.dart:137-146`）、不计入 tips（`star_prompt.dart:111-117`）。
- 「正在续写」指示 = 既有流式指示（`isStreaming` = `activeTurn != null`，`chat_session.dart:538`）；无新组件、无新文案、无新 l10n 键。
- 自动轮可停止：composer 停止键 → `cancel()`（`thincoder_kernel.dart:567-583`）⇒ `session/cancel`（§19.3-①）。
- 自动轮期间可排队发消息：§18 既有面（排水在 `_endTurn`，`:540-565`）。
- 切走再切回：子代理卡片保留终态（不再更新、不重建——§19.8-12）；会话文本照常（主机 transcript 持有）。释放延后与窗开关帧没有任何新可见面（窗帧只进内核判据 `_watching`，不进 transcript、不留 E4 日志）。
- `dispose()` 延后：会话关掉后界面不在了，没有新的运行中状态要展示；宿主已取消订阅（`chat_session.dart:1110-1111`），延后期间只影响进程何时退出。
- 无 open 项。

### 19.10 真机走查步骤（A 段交付时执行）

1. 装含本批的 CLI + 桌面；新建 thincoder 会话，选一个工程目录。
2. 发一条会让主代理**异步派子代理 / 评审**的指令 ⇒ 用户回合先结束、子代理卡片仍 running。
3. 验「自起一轮」：子代理结算 ⇒ 无需用户操作，主代理自动开始说话（新文本出现在用户回合之后，`user:` 项不增加）。
4. 验「回来要下一步」：切到别的会话再切回 ⇒ 该会话显示未读（无铃声）；结束态可输入。
5. 验「正在续写」：自动轮进行中侧栏该会话 = 运行中；输入框可写，发送进队列面板（§18）。
6. 验「可停止」：自动轮进行中点停止 ⇒ 文本停、轮标中断；后台子代理卡片定格（`stopped`）。
7. 验收束（视图）：自动轮进行中关掉该会话视图 ⇒ 自动轮结束后进程按既有 release 语义释放；重新打开无「永远在跑」的卡片。
8. 验收束（项目窗口 / 会话关闭）：子代理 running 时切到其它项目窗口（会话被 `dispose()`），停留到子代理结束再回来 ⇒ **有**消化文本（无窗帧时代会丢）；重新打开无「永远在跑」的卡片。
9. 兼容：把 `thincoder.path` 指到旧版（无本批信号）⇒ 与今天一致：结算后文本照常到达、无自动轮、无新提示；释放回到静默期兜底（§19.11）。
10. 同场景对照终端：终端里子代理结算后同样自起一轮——两侧消息内容与顺序同形（不要求逐字相同）。

### 19.11 兼容（三种组合）

| 组合 | 表现 |
|---|---|
| 新 CLI + 新桌面 | 自动轮可见（unprompted）、可停止、结束即「该你了」；窗开关帧让释放不再依赖时序 |
| 新 CLI + 旧桌面（批 7） | 本键的帧（`start` / `end` / `watch`）被 E4 忽略并记日志；文本照常入 transcript——显示 = 今天（§19.8-8） |
| 旧 CLI + 新桌面 | 无边界帧 ⇒ 无自动轮；无窗帧 ⇒ `_watching` 恒假，释放回到静默期兜底（§19.8-10）；文本照常到达 = 今天（既有 `subagent-digest` 固件即此形的哨兵） |

- 释放延后（D64 / D65）只看子代理帧与窗帧：旧 CLI 也有子代理帧（F11 起）⇒ 同样延后；旧 CLI 没有挂起窗 ⇒ 延后只是把「有子代理在跑」的会话留到子代理结束，无副作用。

不加版本门（E3）：能力按帧在场判定；`thincoder_locator.dart` 的 `verifiedVersion` 不上调。

---

## 20. 编辑器上下文随消息注入（F17）

> 需求档 F17（用户 2026-10-17 21:16 裁定「先把 IDE 完善」）：发消息时把当前编辑器上下文随消息带上——打开文件路径 + 光标行 + 选区（若有），用户不必手动 `@`；注入可见可撤销，开关是配置项且有设置 UI，默认开。
> 一句结论：**上下文 = 宿主既有 `OpenEditor` 快照的每消息快照**，以一个文本块（`<system-reminder>` 摘要 + 选中文本）随 `session/prompt` 携带；界面 = 输入框下方一个可撤销 chip + 已发消息里的摘要；开关 = `chat.editorContext`（默认开）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：采集 = 宿主既有 `OpenEditor.at`（`lib/chat/open_editor.dart:17-42`；活动文档 + 编辑器选区由 `ide_workbench.dart:769-775` 构造），语义不动。
- 对齐 ②：传输 = `KernelTurn.notes` 先例（`lib/kernel/kernel_types.dart:580-605`）；thincoder 今日把 notes 以空行附在正文后（`thincoder_kernel.dart:1077-1080`），`session/prompt` 仍是一个文本块（`thincoder_kernel.dart:613-618`）。
- 对齐 ③：设置项形制 = `PromptSuggestions`（`lib/kernel/prompt_suggestions.dart:6-17`；`main.dart:169-171` 接线）与设置页 `SettingsSwitchRow`（`general_page.dart:362-405`）。
- 对齐 ④：chip 形制 = composer 既有 token chip（`composer_embeds.dart:422-540`）与 `UserMessageItem.images` 的呈现先例（`user_message_bubble.dart:33-43`）。
- 偏离 ①：thincoder **每条消息都带**；Claude 是「编辑器变化才告知」（`chat_session.dart:1039-1051`，`test/chat/open_editor_test.dart:86-137` 钉住）——需求原文是「发消息时把当前编辑器上下文随消息带上」，不是「变化时」。
- 偏离 ②：不用 `resource_link`（D67）。
- 偏离 ③：上下文不进消息正文的显示（wire 有、气泡只显示摘要 chip）——D68。

**survey 证据**：本仓设计档 §3.4 / §4 F3；外仓 CLI 设计档 §2.1（`session/prompt` 接受 `text` / `resource_link`）。
`thincoder-cli/src/acp/resource-link.mjs:77-104`（`resource_link` 由 CLI 读**磁盘**并内联，选区文法 `#L<a>-<b>`）与 `:114-124`（`buildPromptText` 只取**首个** text 块，再拼 resource_link 段）。

结论：自动上下文用文本块；`resource_link` 读盘、整文件内联，不适合每条消息的自动注入。

### 20.1 做法：一次快照 ∥ 三处可见

```text
composer 提交（openEditor()：活动文档 + 光标 / 选区）
  │  设置开 ∧ 未点 ×
  ▼
ChatSession.send → KernelTurn.contexts（按规范绝对路径去重，一条）
  ▼
ThincoderKernel._deliver → 一个 text 块：
   <用户正文>\n\n<system-reminder>…路径 … 光标行 … 选区行 … 选中文本 …</system-reminder>
  ▼
CLI buildPromptText（首个 text 块）→ 模型
界面：输入框下方 chip（可 ×）· 已发消息气泡里的摘要 · 队列项沿用同一 UserMessageItem
```

- 采集点唯一 = `ChatSession.send`（与 `notes` 同处）；composer 只把 `OpenEditor?` 交给它（既有 `editor:` 回调，`composer.dart:1495`）。
- 去重键 = `EditorContext.dedupeKey`（= `p.normalize(p.absolute(path))`，平台路径上下文；单一出处见 §20.2）；同一回合同一路径只出一条。今天只有一个活动编辑器 ⇒ 恒一条；去重是防多来源（多分栏 / 多窗口）的不变量，用例直接喂重复项。
- 开关：`chat.editorContext`，缺省 / 非 `false` = 开（照 `PromptSuggestions.enabled` 形：关时写 `false`）；每条消息发送时读一次。
- 撤销：composer 里点 × ⇒ 本条草稿不再带上下文；撤销态绑定当前 `OpenEditor` 快照——路径 / 光标行 / 选区一变，chip 重新出现（新上下文 = 新提议）。发送后草稿清空，下一句按当时编辑器状态重新给出。
- 没有活动编辑器（`OpenEditor` 为 null：未打开文件 / 未命名文档 / 打开失败，`ide_workbench.dart:769-773`）⇒ 不注入、无 chip；thincoder 不发「没有打开文件」这类反向告知（那是 Claude notes 的语义，`OpenEditor.closedNote`）。
- 有文件但无光标（`OpenEditor.line == null`：编辑器状态未挂载 / 选区无效，`open_editor.dart:22`；媒体文档，`ide_workbench.dart:772`）⇒ 仍注入，`editorNote` 只写路径、chip 只写文件名。媒体文档不过滤——路径照带，光标行 / 选区为空（需求「路径恒带、光标行与选区若有」）。
- 上下文不进 `UserMessageItem.text`：`text` = 用户输入原样；`contexts` 单独字段供 chip；wire 文本由 thincoder 内核拼（D68）。

### 20.2 契约（数据形与线上形）

**宿主类型**（`lib/chat/chat_models.dart`）

```dart
class EditorContext {
  const EditorContext(this.path, {this.line, this.selectedLines, this.selectedText});
  final String path;               // 绝对路径
  final int? line;                 // 光标行，1 基；null = 有文件无光标（编辑器状态未挂载 / 选区无效 / 媒体文档）
  final (int, int)? selectedLines; // 选区首末行，1 基闭区间
  final String? selectedText;      // 选区文本（上限同 OpenEditor.maxSelectedText）
  String get note;                 // 既有形（Claude 用；有选区时不提光标行，逐字保持）
  String get editorNote;           // thincoder 形：有光标行则恒带（有选区也带）+ 选区行区间；line == null ⇒ 只写路径
  String get name;                 // 文件名，chip 用（line == null 时 chip 只写文件名）
  String get dedupeKey;            // 规范绝对路径（p.normalize(p.absolute(path))）：去重键的单一出处
}
```

- `line == null` 的形（有文件无光标）：`editorNote` 只写 `The user has <path> open in the editor.`（无 cursor / 选区段）；chip 只写文件名。`note`（Claude 形）无选区时本就只写路径，文案不动。
- 去重键 = `EditorContext.dedupeKey`（规范绝对路径，单一出处）：宿主采集（`ChatSession._contexts`）与内核防御（`ThincoderKernel._contexts`）两个去重点都取它；同一回合同一 `dedupeKey` 只出一条（§20.1 / D71）。
- `KernelTurn.contexts: List<EditorContext>`（缺省 `const []`；`kernel_types.dart`）。
- `UserMessageItem.contexts: List<EditorContext>`（缺省 `const []`；内核发出用户消息时带上，气泡显示）。
- `OpenEditor` 保留为编辑器快照，新增 `EditorContext toContext()`；`OpenEditor.note` 委托 `toContext().note`（Claude 文案与既有测试逐字不变）；thincoder 用 `editorNote`（有光标行则恒带，无光标行只写路径）。
- `AcceptsEditorContext` 标记接口（`agent_kernel.dart`，照 `AcceptsImageFiles` 形）：thincoder 实现；其它内核不实现，行为不变。

**线上形（`session/prompt` 的 `prompt` 数组，只有一个 text 块）**

```json
[{"type": "text",
  "text": "<用户正文>\n\n<system-reminder>The user has /p/a.dart open in the editor, the cursor on line 10; the user selected lines 3-5 of /p/a.dart in the editor:\n<选中文本>\n\nThis may or may not be related to the current task.</system-reminder>"}]
```

- 有光标行时恒带（有选区也带）；选区行区间写成 `a-b`；`line == null` ⇒ 只写路径段（§20.1）。
- 选中文本上限 = `OpenEditor.maxSelectedText`（10 000 字符）；超出截断并注明 `[N more characters selected, not shown: read the file for them]`（与既有 note 逐字相同，`open_editor.dart:72-79`）。
- `editorNote` 与既有 `note` 的差别：有选区时也写明光标行（需求「光标行 + 选区」两者都要；`note` 的既有文案不动）；`line == null` 时两者都只写路径。
- 一个回合只有一个 text 块；thincoder 不再使用 `KernelTurn.notes`（D69）。`notes` 字段保留给其它内核。
- 不用 `resource_link`：CLI 会读**磁盘**并内联选中行（`resource-link.mjs:77-104`），编辑器里有未保存修改时是旧文本；且整文件 / 2000 行上限的成本摊在每条消息上。用户手动 `@` 仍走 `resource_link`（F8），不受影响。

### 20.3 设置与 UI（全部落地，无 open）

- 设置项 `chat.editorContext`（boolean；缺省开，关写 `false`），形同 `chat.promptSuggestions`（`prompt_suggestions.dart:6-17`；`main.dart:169-171` 接线）。新档 `lib/chat/editor_context_setting.dart`：`settingKey` / `enabled(Object?)` / `current` / `changes`（形同 `ComposerPolishSetting`）。
- 设置 UI：设置 → 通用 → 「随消息带上编辑器上下文」一行开关（`SettingsSwitchRow`，`general_page.dart:362-405` 形）；描述说明「文件路径、光标行与选区；每条消息一次；可在输入框下方的 chip 上撤销」。
- 输入框 chip：位于 composer 盒内输入区下方（`ComposerImages` 与 `_buildToolbar()` 之间、工具条上方，`composer.dart:1617-1627`）；形如 `a.dart · 行 10` / `a.dart · 行 3–5`，右侧 ×；无光标行只写文件名（`a.dart`）。
  只在 `session.acceptsEditorContext ∧ 设置开 ∧ 有 OpenEditor ∧ 未撤销` 时显示。样式复用 `ComposerTokenChip` 的圆角 / 字号（`composer_embeds.dart:422-540`），不自造外观。
- chip 的 × 对读屏是一个有名字的按钮：`Semantics(button: true, label: l10n.editorContextDismiss)`，悬停提示同文（`IdeHover`，`excludeFromSemantics: true` 避免重复朗读；`editor_context_chip.dart:58-67`）。理由：图标单独对读屏既不成按钮、也没有名字；文案走专用键（en「Dismiss Editor Context」/ zh「关闭编辑器上下文」），不复用通用「关闭」——读屏要能说出关掉的是编辑器上下文。
- 已发消息：`UserMessageBubble` 文本上方一行同款小 chip（只读、无 ×），显示 `文件名 · 行 / 行区间`；不展开选中文本。`chat_item_view.dart:63` 与 `chat_history_view.dart:1741` 把 `contexts` 传进气泡。
  已发消息打开态（`UserMessageViewer`）同样渲染只读 chip（文本上方、无 ×；`user_message_bubble.dart:306-308` / `:384-388`，数据 = `chat_history_view.dart:411` 的 `_editingContexts`）；可编辑打开态见 §20.8-3。
- 撤销语义：× 只作用于当前草稿（绑定当前 `OpenEditor` 快照）；编辑器状态一变，chip 回来。发送后下一次按新状态重新给出。
- 队列项：`UserMessageItem` 同一字段 ⇒ 转正后的气泡一致；本批不改 `queue_panel.dart` 的行内布局（chip 在转正后的气泡里出现）——登记 §20.8-5。
- 没有打开文件 / 未命名文档：无 chip、无提示（沉默是正确形态：没有上下文可带）；有文件无光标（含媒体文档）⇒ chip 只写文件名。

### 20.4 受影响文件清单（E2 增量；行数 = 2026-10-19 只读实测）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `lib/chat/chat_models.dart`（719） | 新增 `EditorContext`（path / line / selectedLines / selectedText / note / editorNote / name / dedupeKey）；`UserMessageItem.contexts` + `copyWith` 随带 | ≤ +60（⇒ ≤779）；实交 +87（⇒ 806） |
| ② | `lib/chat/open_editor.dart`（101） | `toContext()`；`note` 委托 `EditorContext.note`（Claude 文案逐字不变）；thincoder 用 `editorNote` | ≤ +12（⇒ ≤113）；实交 −14（⇒ 87；`note` / 截断委托进 `EditorContext`） |
| ③ | `lib/kernel/kernel_types.dart`（606） | `KernelTurn.contexts`（缺省 `const []`） | ≤ +8（⇒ ≤614） |
| ④ | `lib/kernel/agent_kernel.dart`（435） | `AcceptsEditorContext` 标记接口（文档 + 空接口） | ≤ +10（⇒ ≤445） |
| ⑤ | `lib/chat/chat_session.dart`（1188） | `acceptsEditorContext` getter（= `_kernel is AcceptsEditorContext`，同 `acceptsImages` 形）；`send(..., bool editorContext = true)`；按 getter + 设置 + 撤销构建 `contexts`（去重）；非该内核仍走 `_editorNotes` | ≤ +30（⇒ ≤1218） |
| ⑥ | `lib/chat/composer/composer.dart`（2363） | 输入区下方的 chip 行（新组件）+ 撤销态 + 传 `editorContext` | ≤ +25（⇒ ≤2388）；实交 +43（⇒ 2406） |
| ⑦ | `lib/chat/composer/editor_context_chip.dart`（新增） | chip 组件（文件图标 + 摘要 + ×；无 × 时只读） | ~90（实交 98） |
| ⑧ | `lib/chat/widgets/user_message_bubble.dart`（1104） | `contexts` 可选参数 + 文本上方 chip 行 | ≤ +35（⇒ ≤1139） |
| ⑨ | `lib/chat/widgets/chat_item_view.dart`（285）· `lib/chat/chat_history_view.dart`（3685） | 两处把 `contexts` 传进气泡；已发消息打开态经 `_editingContexts` 传入 viewer（`chat_history_view.dart:411` / `:629` / `:1458` / `:1845`） | 各 ≤ +2；实交 +2（⇒ 287）/ +5（⇒ 3690：第二波 +1 + 收尾修复 +4） |
| ⑩ | `lib/chat/editor_context_setting.dart`（新增） | `chat.editorContext` 的 key / 缺省 / current / changes | ~25 |
| ⑪ | `lib/settings/pages/general_page.dart`（855） | 设置 → 通用一行开关 | ≤ +12（⇒ ≤867） |
| ⑫ | `lib/main.dart`（797） | `EditorContextSetting.current` / `changes` 接线 | ≤ +5（⇒ ≤802） |
| ⑬ | `lib/l10n/app_en.arb`（6995）· `app_zh.arb`（2700） | 4 个键（设置标题 / 描述 / chip 行 / 行区间）；生成档 `app_localizations_*.dart` 与两源档同拍在位（无 SDK ⇒ 手改，保持 `test/l10n_test.dart` 绿；SDK 就位轮重产——§18.8 / 登记 §14-24） | 各 +4 |
| ⑭ | `lib/kernel/thincoder/thincoder_kernel.dart`（1196） | `implements AcceptsEditorContext`；`_deliver` 用 `turn.contexts` 拼 note、不再用 `notes`；`UserMessageItem.contexts` 带上 | ≤ +14（⇒ ≤1210；另见 §21.3 拆分后净降）；实交 +20（⇒ 1216；第三波拆分后 ≤1148） |
| ⑮ | `test/chat/open_editor_test.dart`（139） | `toContext` / note 委托 / 摘要不回归 | ≤ +45（⇒ ≤184） |
| ⑯ | `test/chat/editor_context_chip_test.dart`（新增） | chip 可见 / × 撤销 / 编辑器变化后回来 / 设置关 / 内核不接受 / 已发消息打开态（只读 chip） | ~80（实交 318，6 例） |
| ⑰ | `test/kernel/thincoder_kernel_test.dart`（2859） | T77–T82（§20.7）；只加用例、不动结构（缝候选 = §15.4 的四组拆法：connection / session ids / locator / the registered kernel） | ≤ +130（⇒ ≤2989）；实交 +229（⇒ 3088） |

- **体量**：`thincoder_kernel.dart` 的净增在 §21.3 的拆分里一并核（拆分后 ≤1148）；本节的 +14 是拆分前的参考上界。新增档均 <300 行。`composer.dart` 在 >800 名单（实交 2406），本批只加一段 chip 行与撤销态（行级新增，不动结构；缝候选沿用 §17.4 的右下角固定组；触发同 §17.4，不因本批变化）。
- **体量（`chat_history_view.dart`，3685，2026-10-19 `wc -l` 实测）**：在 >800 名单；本批行级 +5（⇒ 3690；传参 / 打开态状态位 / viewer 接线，不动结构）；缝候选 = 会话列渲染段 / 历史载入段分开成档（段界由拆分批勘定）；触发 = 独立拆分批立项。同表的 `chat_item_view.dart`（285）< 800，不入名单。
- **零改动**：`queue_panel.dart` · Claude / Codex 内核 · thincoder 仓（协议面零改：仍只发 text 块） · 固件。

### 20.5 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D67 | 自动上下文用**一个文本块**（system-reminder 摘要 + 选中文本），不用 `resource_link` | 编辑器缓冲可能未保存，`resource_link` 由 CLI 读盘（`resource-link.mjs:77-104`）⇒ 会送旧内容；整文件 / 2000 行上限的成本不应摊在每条消息上；文本块还能逐字复用既有 note 形态与上限。被否：`resource_link` + `#L<a>-<b>`（路径 / 行区间天然可机检，但内容来自磁盘）；被否：两者都带（同一文件两处内容，重复注入） |
| D68 | 显示与线上分离：`KernelTurn.contexts` 驱动 chip；wire note 由 thincoder 内核拼；`UserMessageItem.text` 不含 note | 需求「可见可撤销、不静默塞正文」；`text` 保持用户原样 ⇒ 编辑 / 重发 / 查找 / 标题生成都不受污染。被否：把 note 拼进消息正文并在气泡里显示（旧行为，正文被机器文本污染） |
| D69 | thincoder **每条消息都带**；开关关 = 完全不带（也不发「没有打开文件」） | 需求原文「发消息时把当前编辑器上下文随消息带上」；Claude 的「变化才告知」是另一套语义，保持不动。被否：沿用变化才告知（用户每一句都期望带上当前状态）；被否：关开关时发 closedNote（反向噪音） |
| D70 | 撤销 = 草稿级、绑定当前编辑器快照；不做会话级「永久关闭」 | 「可撤销」针对这一条消息；永久关闭是设置项的职责。快照一变 chip 回来，避免旧状态被静默沿用。实现形：composer State 持 `_dismissedEditor`（当前 `OpenEditor` 快照，`composer.dart:172`）；发送后复位（`:1528`）；快照一变即重新出现。被否：撤销后直到设置改回都不再出现（用户失去上下文却看不出原因） |
| D71 | 去重键 = 规范绝对路径，同回合同路径一次；`@`-mention 不算重复 | 需求「同一文件同一回合只带一次」按**自动上下文集合**判；用户显式 `@` 是另一来源（resource_link），两者语义不同。被否：按 mention 字符串做模糊匹配（相对 / 绝对 / 文件夹三种形态，误判面大） |
| D72 | 只取当前活动编辑器（单文件、单选区） | 需求是「当前编辑器上下文」；多分栏 / 多窗口的上下文选择没有产品定形，先不做。判定条件：产品要「所有打开文件都带」⇒ 在采集点扩为多来源 + 去重（本批已把去重键定好） |

### 20.6 验收对照（回指需求档 F17）

| 需求条目（F17） | 本档落点 | 判据（机检 / 走查） |
|---|---|---|
| 打开 `a.dart` 第 10 行、选中 3–5 行 ⇒ 发消息 ⇒ prompt 含路径与行区间 | §20.1 / §20.2 | T77：`session/prompt` 的 text 块含 `/p/a.dart`、`cursor on line 10`、`lines 3-5` |
| 关掉开关 ⇒ 不含 | §20.3 设置项 + §20.1 开关 | T78：`chat.editorContext=false` ⇒ prompt 无该文本；T82：设置页写入 |
| 未打开文件 ⇒ 不含 | §20.1 无文件 | T79：`OpenEditor` 为 null ⇒ prompt 与今天逐字一致 |
| 同一文件同一回合只带一次 | §20.1 去重 | T80：重复输入 ⇒ 一条 note |
| 注入可见可撤销（chip / 摘要） | §20.3 composer chip + 气泡 chip | T81：chip 显示；点 × ⇒ 本条 prompt 无上下文；编辑器变化 ⇒ chip 回来 |
| 开关是配置项 ⇒ 有设置 UI；默认开 | §20.3 | T82：设置行存在、缺省开、关写 `false`；`test/l10n_test.dart` 键对齐 |
| （派生）可见内容与实发一致 | §20.2（note 由同一 `EditorContext` 生成） | T77 与 T81 同源；走查 2–4 |
| （派生）有文件无光标 ⇒ 路径仍带、不编造光标行 | §20.1 / §20.2（`line == null`） | T79②：system-reminder 只含路径；chip 只写文件名 |

### 20.7 用例表（T77–T82，`test/kernel/thincoder_kernel_test.dart` + `test/chat/*`）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T77 | 全形：光标 + 选区 + 选中文本 | `KernelContext(cwd:'/p')`；`EditorContext('/p/a.dart', line: 10, selectedLines: (3,5), selectedText: 'x\ny\nz')`；发一条消息 | 请求 `session/prompt` 的 prompt 单块 text；含 `/p/a.dart`、`cursor on line 10`、`lines 3-5`、`x\ny\nz`、`<system-reminder>` 包裹；`transcript` 用户项 `text` 仍是用户原文、`contexts` 一条 |
| T78 | 开关关 | `EditorContextSetting.current = () => false`；同 T77 | prompt 单块 text = 用户原文（无 system-reminder）；气泡无 chip |
| T79 | 无打开文件 | `editor: () => null` | prompt 与今天逐字一致；无 chip |
| T79② | 有文件无光标 | `editor: () => OpenEditor('/p/a.dart')`（`line == null`） | system-reminder 只含 `/p/a.dart`（无 `cursor on line` / `lines` 段）；chip 只写 `a.dart`；`contexts` 一条 |
| T80 | 同文件一次 | 构造器喂两条同路径 `EditorContext` | 只生成一条 note（去重）；`UserMessageItem.contexts` 一条 |
| T81 | 撤销 | composer chip 点 × ⇒ 发送 | `session.send(..., editorContext: false)`；prompt 无上下文；`OpenEditor` 变化后 chip 重现 |
| T81② | 已发消息打开 | 携带 `contexts` 的已发消息点开（thincoder 会话 `canEditMessages == false` ⇒ 恒走只读 `UserMessageViewer`） | 文本上方同款 chip 行可见、无 ×；无 Dismiss 语义按钮 |
| T82 | 设置项 | 设置 → 通用关闭 ⇒ `settings.json` | 写入 `chat.editorContext=false`；缺省（不写）为开；`l10n`：`app_en.arb` / `app_zh.arb` 两源档均含这 4 个键（生成档不机检；可跑判据与不可跑回落 = §20.4 ⑬ / §14-24） |

- 既有 `test/chat/open_editor_test.dart:44-83` 的 note 文案断言保持绿（委托后逐字不变）；Claude 的「变化才告知」用例（`:86-137`）保持绿。

### 20.8 边界（本批不做）与登记（判定条件）

1. **不做全工作区索引注入 / 符号级引用解析**：只带当前活动编辑器的一个文件（需求边界）。
2. **`@`-mention 与自动上下文不互斥**：同一文件可能既被 `@` 又被自动带上——两处是不同来源；「同一文件同一回合只带一次」按自动上下文集合判（D71）。判定条件：产品要求「@ 过就不再自动带」⇒ 在 `ChatSession.send` 解析 `message.mentions` 的路径后跳过同名项。
3. **可编辑打开态无 chip**：`contexts` 只由 `AcceptsEditorContext` 内核产生（现只有 thincoder，`chat_session.dart:1088`），而 thincoder 不实现 `RewindsConversation`（`chat_session.dart:586`）⇒ 携带 `contexts` 的会话 `canEditMessages == false`，已发消息打开恒走只读 `UserMessageViewer`；
  可编辑的 `ChatComposer` 分支（`chat_history_view.dart:1849`）拿不到非空 `contexts`，故编辑层不渲染 chip（不发明交互）。判定条件：出现既实现 `RewindsConversation` 又带 `contexts` 的内核 ⇒ 编辑层补只读 chip 行。
4. **重放不重建 chip**：`session/load` 只重放 `user_message_chunk` 文本；若 CLI 把 note 存进了会话历史，重放文本里会看到 `<system-reminder>` 原文（本批不解析、不剥离）。`unverified`：CLI 的 `saveSession` 机器行过滤只在 TUI 面读到（`bridge.mjs:399-400` 的注释），ACP 路径是否过滤未核。判定条件：走查看到重放消息里出现 system-reminder 正文 ⇒ 在翻译层按固定前缀剥离，只显示用户文本（另立）。
5. **队列面板行内不显示 chip**：输入框 chip 的撤销态不进队列项；转正后的气泡显示 `contexts`。判定条件：产品要求队列里也能看到上下文 ⇒ `queue_panel.dart` 行内加摘要（宿主改动）。
6. **Claude / Codex 内核行为不变**：Claude 仍按「编辑器变化才告知」（`chat_session.dart:1039-1051`）；本批只让 thincoder 走新路径。判定条件：要把同一形态推广到 Claude ⇒ 另立（会改 Claude 的既有语义与用例）。

### 20.9 真机走查步骤

1. 打开项目，在编辑器打开 `a.dart`，光标停在第 10 行 ⇒ 输入框下方出现 chip `a.dart · 行 10`。
2. 发一条消息 ⇒ 气泡里同一 chip；模型答话能引用该文件 / 行（不要求逐字）。
3. 选中第 3–5 行 ⇒ chip 变 `a.dart · 行 3–5`；再发一条 ⇒ 气泡 chip 同行区间。
4. 点 chip 的 × ⇒ chip 消失；发消息 ⇒ 气泡无 chip、prompt 无 system-reminder；移动光标 ⇒ chip 回来。
5. 设置 → 通用关掉「随消息带上编辑器上下文」⇒ chip 消失、发消息不带；重开 ⇒ 回来。
6. 打开图片（媒体文档）⇒ chip 只写文件名、消息只带路径（无光标行 / 选区）；打开文本文件但编辑器状态未挂载（有路径、无光标行）⇒ 同形；未命名文档 / 没有打开文件 ⇒ 无 chip、消息不带上下文。
7. 对照：thincoder 终端没有自动上下文（只 `@`）；桌面是增量，终端行为不变。
8. 点开一条已发消息（展开态）⇒ 摘要 chip 可见、无 ×。

## 21. agent 编辑走 IDE 原生 diff（F18）

> 需求档 F18（用户 2026-10-17 21:16 同裁定）：桌面宣告 `fs.readTextFile` / `fs.writeTextFile` 能力并在内核请求时执行——agent 的读写经桌面文件模型，已打开的文件在编辑器里表现为可见、可审阅的变更；项目根外拒绝并有可见提示。
> 一句结论：**能力位只在内核的 `initialize` 宣告**；两个反向 RPC 由新档 `ThincoderFiles` 处理，读写经宿主新接口 `KernelFiles` 落到 IDE 的打开文档 / 文件服务；**有未保存缓冲 ⇒ 拒绝写入**（不落盘、不动缓冲）并给出可审阅的只读 diff + 会话内提示；成功的写入落盘并复用既有 `FileEdited` 变更审查面。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：反向 RPC 分发 = 既有 `_serverRequest`（`thincoder_kernel.dart:772-811`；未知方法回 `-32601`，`thincoder_protocol.dart:167-174`）。
- 对齐 ②：能力门控 = CLI 侧已备好（`bridge.mjs:102-105` 快照能力位；`:149-165` `readBuffer` / `writeBuffer`；`:347-387` 工具路由）；未宣告 ⇒ 回落本地写盘（外仓设计档 §11.4 G3）。本批只补客户端这一半。
- 对齐 ③：变更审查面 = `FileEdited` → `ChangeReview.report`（`chat_session.dart:298-309`；`lib/chat/review/change_review.dart`）；编辑器内 hunks = `IdeAgentEdits`（`lib/ide/ide_agent_edits.dart:88-184`）。本批不新造事件、不改审查语义。
- 对齐 ④：打开文档模型 = `IdeWorkspace`（`ide_workspace.dart:45-215` 文档 / 脏标记；`:764-794` `reload` 保留未保存缓冲；`:629-682` `openDiff`；`:502` / `:507-512` 文档与模型读取）。
- 对齐 ⑤：宿主能力面注入 = `KernelContext.workspace` 先例（`agent_kernel.dart:54-75`）与 `AcceptsImageFiles` 标记（`:260-267`）。
- 偏离 ①：**不**把 `fs` 能力宣告进 `thincoder_catalog.dart`（短命 list/delete 连接没有 prompt / 工具，宣告即虚报；E3）。
- 偏离 ②：脏缓冲不写盘、不改缓冲（D76）——不复刻「写盘后靠文件监视静默重载」的旧路。
- 偏离 ③：内核不直接 import IDE 层；宿主桥 `KernelFiles` 由 IDE 侧实现（E1 / E2）。

**survey 证据**：外仓 `thincoder-cli/src/acp/bridge.mjs:347-387`（只有 `write` / `edit` 走 `fs/*`；

`read` / `delete` / `apply_patch` 保持本地）、`:102-105`（`clientCaps?.fs?.readTextFile === true` / `writeTextFile === true`）、`:152` / `:161`（每次调用 30 s 超时）。
外仓设计档 §2.2（`read` 仅 edit 桥读回）与 §11.4 G3（能力位默认 false，未宣告回落本地）。
结论：能力位与两个 handler 就位即接通；写成功必须落盘（CLI 的 `read` 工具读盘）。

### 21.1 做法：能力位 ∥ 两个 handler ∥ 一处宿主桥

```text
CLI toolRouter（bridge.mjs:357-387）
  write → fs/write_text_file {sessionId, path, content}       （全量内容，无回读）
  edit  → fs/read_text_file {path} → computeEditEntry → fs/write_text_file
  read / delete / apply_patch → 本地（不路由）
        │ 能力门：initialize 快照（bridge.mjs:102-105）
        ▼
桌面 initialize：clientCapabilities.fs = {readTextFile: true, writeTextFile: true}
        ▼
ThincoderKernel._serverRequest → ThincoderFiles（新档）
        ├─ 路径限定：cwd + workspace folders（realpath 比较）
        ├─ read  → KernelFiles.readText(path) → {content}
        └─ write → KernelFiles.writeText(path, content)
                    ├─ 打开且有未保存缓冲 ⇒ blocked（不落盘、不动缓冲）
                    │     + 只读 diff（缓冲 vs agent 内容）+ 会话内 error 提示
                    └─ 其余 ⇒ 落盘（expectedText 基线）+ 重载打开文档
        ▼
写成功 ⇒ emit FileEdited(FileChange, original: OriginalText(before)) → 既有审查面
```

- 能力位：`initialize` 在 `KernelContext.files != null` 时把 `clientCapabilities` 从 `{}` 改为 `ThincoderFiles.capabilities`（`{'fs': {'readTextFile': true, 'writeTextFile': true}}`；`thincoder_kernel.dart:210-212`），宿主没给文件桥时保持 `{}`（E3 不虚报）。`thincoder_catalog.dart:78-80` **保持 `{}`**（D73）。
- 分发：`_serverRequest` 在 `session/request_permission` 之外接 `fs/read_text_file` / `fs/write_text_file`，其余仍回 `-32601`（E4 不变）。
- handler 的 `sessionId` 只用于留痕（CLI 传当前槽号），不改变路由；`path` 按 cwd 解析相对路径。
- 超时：CLI 侧每次 30 s；handler 在本地决策完即回，**不等用户**（D76）。
- 宿主桥 = `IdeKernelFiles`（`KernelContext.files` 的 IDE 侧实现，D78）；查找打开文档用 `IdeWorkspace.openWorkspaces` 注册表（静态 `Set`；与实例方法 `open(String path)` 区分）。

### 21.2 契约（线形、限定、读写、错面）

**能力位与线形（逐字对 ACP）**

```json
// initialize params（仅内核连接）
{"protocolVersion": 1,
 "clientCapabilities": {"fs": {"readTextFile": true, "writeTextFile": true}}}

// 反向请求（服务端 → 我方）
{"method": "fs/read_text_file",  "params": {"sessionId": "<槽号>", "path": "<路径>"}}
{"method": "fs/write_text_file", "params": {"sessionId": "<槽号>", "path": "<路径>", "content": "<全文>"}}
```

- **宣告条件**：`clientCapabilities.fs` 只在 `KernelContext.files != null` 时出现；宿主没给文件桥 ⇒ `clientCapabilities` = `{}`（E3 不虚报；catalog 连接同样 `{}`，D73）。生产装配四点都给了 `files`（§21.3 ⑦）。
- 读结果：`{"content": "<文本>"}`（CLI 取 `read?.text ?? read?.content`，`bridge.mjs:153`；按 ACP schema 用 `content`）。
- 写结果：`{}`。
- 错误：JSON-RPC error；CLI 把它包成工具结果 `Error: fs/… failed: <message>`（`bridge.mjs:155` / `:163` / `:369`），模型看得见。本档约定：`-32602` = 参数 / 路径非法（项目根外、缺 path）；`-32603` = IO 失败 / 未保存缓冲拒绝。
- 两个方法名是 **snake_case**（`fs/read_text_file` / `fs/write_text_file`）；`fs.readTextFile` / `fs.writeTextFile` 只是**能力位名**（`bridge.mjs:104-105`）。实现不得把两者混用。

**路径限定（单一权威 = 内核 handler）**

- 允许根 = `cwd()` + `folders()`（`KernelContext.workspace()?.folders`）：**每个请求现读**，会话中途加入 / 移除的工作区文件夹即时生效（§21.8-12）。
- 单一入口 `_allowed`：`path` 缺失 / 非字符串 ⇒ `-32602`（只回协议错，不发会话提示）；否则 `path = _canonical(_absolute(raw))`（相对路径接 `cwd()`）。
  每个根同样以 `_canonical(_absolute(root))` 规范化后与它比较（平台 `p.Context` 的 `equals` / `isWithin`；Windows 大小写不敏感由 context 处理）；命中 ⇒ 返回规范路径，否则发提示并返回 null（拒绝已在 `_allowed` 内发出，两个 handler 见 null 直接 return）。
- `_canonical` = `resolveSymbolicLinksSync()`；路径不存在 ⇒ 解析最近存在祖先的 realpath 再拼回其余段——`..` 逃逸与「不存在的文件」按同一规则判定。
- 根外 / `..` 逃逸 / 符号链接逃逸 ⇒ `-32602`，并：
  - `ItemUpserted(nextSeq, 'fs:<n>', NoticeItem(NoticeKind.error, '…项目外路径…'))`（会话内可见）；
  - `appEvent('thincoder', 'fs: refused a path outside the project: …')`（日志）。
- 宿主桥再做一次「在某个打开工作区根内」的检查（防御面；同一进程内不是安全边界，但不让错误路径落到文件服务），并按同口径规范化请求路径与工作区根（§21.8-10）。

**读（`fs/read_text_file`）**

- 文件在任一打开的 `IdeWorkspace` 里 ⇒ 返回**编辑器当前文本**（含未保存修改）——edit 桥必须基于用户看到的文本算 diff（D75）。同一路径在多窗口打开 ⇒ 取**先打开者**（注册顺序；写侧脏检查覆盖全部持有者，§21.8-11）。
- 未打开 ⇒ 用该根所属工作区的 `files.read(path)`（`ide_workspace.dart:443`；本地或远端宿主各自的文件服务）；没有打开工作区 ⇒ `IdeFileService(root).read(path)`（本地）。
- 二进制 / 超限 / 不可读 ⇒ `-32603`，消息取文件服务异常的可读文本（`IdeBinaryFileException` / `IdeFileTooLargeException` / `IdeFileNotFoundException`，`file_service.dart:96-109` 的既有本地化源）。
- 远端根且无打开工作区 ⇒ `-32603`「remote project has no open workspace」（登记 §21.8-4）。

**写（`fs/write_text_file`）** ——三态决策（D76 / D77）

| 目标文件状态 | 处置 | 返回 |
|---|---|---|
| 在任一打开的 `IdeWorkspace` 里、且该文档 `dirty`（有未保存缓冲） | **不落盘、不改缓冲**；打开只读 diff（左 = 编辑器当前文本，右 = agent 内容）+ 会话内 error 提示；`appEvent` 留痕 | `-32603`「the file has unsaved changes in the editor; the write was not applied」 |
| 打开但干净 ⇒ 落盘（`files.write(path, content, expectedText: before)`，`file_service.dart:29-31` 的基线保护）；再对每个含该路径的工作区 `reload([该工作区拼写])`（干净文档更新 `text` + `savedText`，`ide_workspace.dart:764-794`；拼写见 §21.8-10） | 写成功 | `{}` |
| 未打开 ⇒ 落盘（同上，无 `reload`） | 写成功 | `{}` |

- **为什么脏缓冲必须拒绝**：CLI 的独立 `read` 工具读**磁盘**（`bridge.mjs:386`「read-only tools … stay local」）。任何「成功」若不落盘，模型随后 `read` 会看到旧内容——前后矛盾。而要落盘就得把用户未保存的文本一并写下去（静默替用户保存）或覆盖它（数据丢失）。两条都不可接受 ⇒ 唯一安全解是拒绝 + 可审阅 diff（D76）。
- 写成功的 `FileEdited`：`FileChange(path, added, removed, kind: before == null ? added : modified)`，`original: OriginalText(before)`；行数用行级 LCS 计（与本仓 Claude 翻译层的 diff 计数同形）。这直接进既有 `ChangeReview.report`（`chat_session.dart:305-306`），Keep / Undo 语义不变（D79）。
- 只读 diff：`workspace.openDiff(path, label: <l10n「Agent's change (not applied)」>, original: () async => 当前编辑器文本, modified: () async => content)`（`ide_workspace.dart:629-682`；`modified != null` ⇒ `readRevision` 置位 ⇒ 右侧只读，`:196`）。`unawaited` 打开，不阻塞应答；没有打开工作区时只发提示。
- 提示：写入拒绝与根外拒绝都发 `NoticeItem(NoticeKind.error, …)`（会话内可见）；不做弹窗（D80）。

### 21.3 受影响文件清单与 `thincoder_kernel.dart` 拆分方案（E2；行数 = 2026-10-19 `wc -l` 实测）

**拆分方案（硬要求：实现后 ≤1148 行）**

| 步 | 动作 | 迁移面 | 行数 |
|---|---|---|---|
| 1 | 新档 `thincoder_choices.dart`，以 `part of 'thincoder_kernel.dart'` 接入（先例 `lib/browser/browser_actions.dart:1`） | 选择面：`_Choice` / `_ModelSetting`、全部选项 / 取值闭包与六个顶层 helper（`_modeOf` / `_permissionOf` / `_modelOf` / `_effortOf` / `_setModeOf` / `_configOf`）。**`part` 不能给类加成员** ⇒ 四个 `@override` 字段（`mode` / `permission` / `model` / `effort`）与 `_setMode` / `_config` 留在内核类体，各一行委托（`late final mode = _modeOf(this);` 等） | 实交 203（原估 ~194） |
| 2 | 新档 `thincoder_files.dart`（普通 library） | `ThincoderFiles`：能力位常量、两个 handler、路径限定（`_allowed`）、`KernelFiles` 调用、`FileEdited` / `NoticeItem` 发射回调 | 实交 210（原估 ~170） |
| 3 | 内核接线 | `implements AcceptsEditorContext` · 能力位（条件宣告） · `_serverRequest` 分发 · `_deliver` 用 `contexts` · `part` 指令与 `_files` | 实交 +42（1216 − 203 + 42 ⇒ 1055；含第一波已交的 `implements` / `_deliver` 与第三波的委托壳） |
| — | **预算** | 1055 ≤ 1148（§5.2 的预算）；余量 93 行 | ✅ |

- 选择面是 §5.2 已登记的「下一缝候选」；本批为 F18 handler 腾预算而**兑现**该缝（结构级触碰，符合「先立拆分批」口径）。`part` 保持私有成员访问，公开面零变；类成员不能跨 `part` ⇒ 选择面的四个能力字段与两个转发壳以一行委托留在内核（见步 1）。
- 新档均 <300 行；`thincoder_events.dart`（799）不动。
- 批 11（F19·F20）的增量预算见 §22.3 体量条（拆分已落，kernel 基线 1055）。

**本仓文件表**

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_kernel.dart`（1216） | 能力位（仅 `KernelContext.files != null` 时宣告）· `_serverRequest` 分发（`fs/*` 先交 `ThincoderFiles`）· `_deliver` 用 `turn.contexts` · `implements AcceptsEditorContext` · 选择面移出（拆分步 1；四个字段 + 两个转发壳留类体） | 实交 净 −161（⇒ 1055；拆分见上） |
| ② | `lib/kernel/thincoder/thincoder_choices.dart`（新增） | 选择面（`part`）：`_Choice` / `_ModelSetting`、选项 / 取值闭包、六个顶层 helper | 实交 203 |
| ③ | `lib/kernel/thincoder/thincoder_files.dart`（新增） | `ThincoderFiles`：能力位常量 · `fs/read_text_file` / `fs/write_text_file` · 路径限定（`_allowed`） · 错误码 · `FileEdited` / `NoticeItem` | 实交 210 |
| ④ | `lib/kernel/agent_kernel.dart`（438） | `KernelFiles` 接口 + `KernelFilesException` + `KernelContext.files` | ≤ +45（⇒ ≤483） |
| ⑤ | `lib/ide/ide_kernel_files.dart`（新增） | `IdeKernelFiles implements KernelFiles`：打开文档优先 · 脏缓冲检测 · 只读 diff · 文件服务读写 · 远端根拒绝 | 实交 201 |
| ⑥ | `lib/ide/ide_workspace.dart`（1243） | `static final Set<IdeWorkspace> openWorkspaces`（构造登记 / `dispose` 注销，`:218` / `:1199`；与实例方法 `open(String path)` 同名会遮蔽，故用 `openWorkspaces`）；`documentOf(path)` 小取值器（或直接用 `documents`） | ≤ +14（⇒ ≤1257） |
| ⑦ | `lib/workspace/workspace.dart`（2828） | 四处 `KernelContext(...)`（`:541` / `:578` / `:2553` / `:2596`）加 `files: IdeKernelFiles(l10n: l10n)`（带 l10n 回调，非 const） | ≤ +4（⇒ ≤2832）；实交 +6（⇒ 2834，超 2 行） |
| ⑧ | `lib/kernel/thincoder/thincoder_catalog.dart`（131） | **零改动**（能力位保持 `{}`，D73） | 0 |
| ⑨ | `lib/l10n/app_en.arb`（7026）· `app_zh.arb`（2703） | 2 键：只读 diff 标题 / 未保存缓冲提示；生成档与两源档同拍在位（无 SDK ⇒ 手改，保持 `test/l10n_test.dart` 绿；SDK 就位轮重产——§18.8 / 登记 §14-24） | 各 +2 |
| ⑩ | `test/kernel/thincoder_files_test.dart`（新增） | handler 直测：限定 / 读 / 写三态 / 错误码 / `FileEdited`（假 `KernelFiles`） | ~150（实交 260，10 例） |
| ⑪ | `test/ide/ide_kernel_files_test.dart`（新增） | 桥：打开文档优先 / 脏缓冲拒绝 / 干净写入 + 重载 / 远端拒绝（假工作区 + 假文件服务） | ~90（实交 234，11 例：10 + 链接根） |
| ⑫ | `test/kernel/thincoder_kernel_test.dart`（3088） | T83–T92（§21.6）：push 反向请求、断言响应与事件；只加用例、不动结构（缝候选同 §15.4 的四组拆法） | 实交 +307（⇒ 3395；开工前上界 ≤+180 超 126——T83–T90 需真实临时目录 + `IdeWorkspace` 夹具）。该档后续预算以 3395 起算（基数按第三波开工实测重定） |

- **零改动**：`thincoder_mock.dart`（用 `push` 直推反向请求即可，无需新脚本位）· `thincoder_protocol.dart`（分发已够）· 既有变更审查档 · thincoder 仓（能力门控与两个方法已备）。
- **out-of-repo**：零。本批不写 thincoder 仓。

### 21.4 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D73 | `fs` 能力位只在内核连接宣告；`thincoder_catalog.dart` 保持 `{}` | catalog 只做 list / delete 的短命连接，没有 prompt、没有工具 ⇒ 不会有 `fs/*` 请求；宣告即虚报（E3 / D12 同口径）。被否：两处都宣告（虚假能力位；catalog 也不实现 handler） |
| D74 | 路径限定在内核 handler 做（单一权威）；宿主桥再查一次打开工作区根 | 内核知道 `cwd` + 工作区 folders；桥不知道会话根。二次检查是防御面，不是安全边界（同进程）。被否：只在桥里查（会话根丢失，多项目窗口会放宽到所有打开根） |
| D75 | `fs/read_text_file` 返回**编辑器当前文本**（含未保存）；CLI 自己的 `read` 工具保持读盘（协议事实） | edit 桥必须基于用户看到的文本算 diff，否则会把用户未保存的修改算成「要删掉的行」。被否：读盘（edit 会覆盖用户未保存内容）；被否：读盘但脏时拒绝读（edit 直接失败，无法在缓冲上工作） |
| D76 | 脏缓冲 ⇒ **拒绝写**（不落盘、不动缓冲）+ 只读 diff + 会话内 error | 写成功必须落盘（CLI `read` 工具读盘）；落盘要么静默保存用户未保存的文本、要么覆盖它——都不可接受。拒绝是唯一不丢数据且前后一致的选择；可审阅 diff 满足「呈现可审阅变更」。被否：写盘（静默保存 / 用户后续保存再覆盖 agent 内容）；被否：全量内容套进缓冲（覆盖用户未保存内容）；被否：弹窗等用户选择（CLI 30 s 超时，且没有反向等待通道） |
| D77 | 干净 / 未打开 ⇒ 落盘 + 对打开文档 `reload`；两者都发 `FileEdited` | 复用 `IdeWorkspace.reload`（干净文档更新、脏文档保留——本路径已保证无脏文档）；`FileEdited` 让既有 Keep / Undo 原样工作。被否：只写盘不更新模型（等文件监视 100 ms 后重载，慢且可能被自动保存抢先）；被否：只更新模型不写盘（`read` 工具会看到旧内容） |
| D78 | 宿主桥 = `KernelContext.files`（通用接口）+ `IdeKernelFiles`（IDE 侧实现）+ `IdeWorkspace.openWorkspaces` 注册表 | 内核不 import IDE（E1）；多窗口 / 多工作区都能找到打开文档；测试可注入假桥。被否：内核直接 `dart:io`（绕过编辑器模型，脏缓冲不可见）；被否：Workbench 全局单例（多窗口覆盖不全） |
| D79 | 写成功复用 `FileEdited` + `OriginalText(before)`，不新增事件、不改审查语义 | 既有 `ChangeReview` / `IdeAgentEdits` 直接工作；需求「与既有变更审查面一致」。被否：新事件 `FileWritten`（宿主与审查面都要改，E2 违规） |
| D80 | 拒绝面 = 会话内 `NoticeItem(error)` + `appEvent`；不做弹窗 | 拒绝是工具结果的一部分（模型能读）；会话内提示是既有可见面（`thincoder_kernel.dart:578-591` 的图片丢弃同形）。被否：模态弹窗（阻断、且反向请求没有等待用户的面） |
| D81 | 脏缓冲的只读 diff 不提供「应用」按钮 | 需求只要求「可审阅」；应用 = 用户保存 / 放弃自己的缓冲后让 agent 重试。被否：就地三方合并（范围爆炸，且本批不改审查语义） |

### 21.5 验收对照（回指需求档 F18）

| 需求条目（F18） | 本档落点 | 判据（机检 / 走查） |
|---|---|---|
| 桌面宣告 `fs.readTextFile` / `fs.writeTextFile` 能力 | §21.2 能力位 | T87：带 `files` 的会话 `initialize` 的 `clientCapabilities.fs` 两位皆 true，无 `files` ⇒ `{}`；catalog 的 initialize 仍为 `{}`（T87②） |
| 已打开且有未保存缓冲 ⇒ 写入请求落到桌面侧，不走本地落盘竞争 | §21.1 / §21.2 写三态 | T87（内核 `initialize` 的 `fs` 两位皆 true）+ CLI 侧门控（`bridge.mjs:102-105` 快照能力位 ⇒ 宣告即走桌面路由）+ 走查 2（脏缓冲下写请求到达桌面、回 `-32603`、缓冲与磁盘不变、只读 diff 弹出）；T83 只钉桌面 handler 的拒绝行为（`push` 直推绕过能力门） |
| 编辑器呈现可审阅变更 | §21.2 只读 diff | T84：桥调用 `openDiff`（假工作区记录调用：original = 当前文本，modified = agent 内容）；会话内 `NoticeItem(error)` 一条 |
| 不覆盖用户未保存内容 | §21.2 写三态 + D76 | T83：模型文本 / `savedText` / 磁盘均不变 |
| 未打开文件 ⇒ 写入后磁盘内容与 agent 所述一致 | §21.2 写三态（未打开行） | T85：临时目录写后 `readAsString` == content |
| 越界路径（项目外）⇒ 拒绝并有可见提示 | §21.2 路径限定 | T86：`/outside/x` ⇒ `-32602` + `NoticeItem(error)` 一条；文件未被创建 |
| （派生）edit 桥基于编辑器缓冲 | §21.2 读 | T88：打开文档（含未保存）⇒ 响应 `content` == 模型文本 |
| （派生）干净打开文件写后模型同步 | §21.2 写三态（干净行） | T89：写后模型 `text` == content、`isDirty` 假 |
| （派生）变更审查面不变 | §21.2 `FileEdited` | T90：写后 `FileEdited` 一条，`change.path` / `original` 正确；`ChangeReview` 既有用例不回退 |
| （派生）未知方法仍得体降级 | §21.1 分发 | T91：`fs/something_else` ⇒ `-32601` |
| （派生）二进制 / 超限读错误面 | §21.2 读 | T92：假桥抛 `IdeBinaryFileException` ⇒ `-32603` + 可读消息 |

### 21.6 用例表（T83–T92，`test/kernel/thincoder_kernel_test.dart` + 新档）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T83 | 脏缓冲拒绝写 | `_Session(context: KernelContext(cwd:'/p', files: fake))`；fake 报某路径 `blockedByUnsavedBuffer`；`agent.push` 一条 `fs/write_text_file` 请求 | 响应 `error.code == -32603`；`fake.writes` 空；`transcript` 有一条 error `NoticeItem`；无 `FileEdited` |
| T84 | 可审阅变更 | fake 记录 `openDiff` 调用（或桥直测） | `openDiff` 的 `original` 读到当前缓冲文本、`modified` 读到 agent 内容；模型文本不变 |
| T85 | 未打开文件写 | 临时目录；fake 走真实文件服务；push 一条 `fs/write_text_file` | 响应 `{}`；磁盘内容 == content；`FileEdited` 一条 |
| T86 | 项目根外 | `path: '/outside/x'` | 响应 `-32602`；`/outside/x` 不存在；error `NoticeItem` 一条；`appEvent` 一条 |
| T87 | 能力位 | 起会话（`KernelContext(files: fake)`） | ① 内核 `initialize` 的 `clientCapabilities.fs == {'readTextFile': true, 'writeTextFile': true}`；无 `files` 的会话 ⇒ `{}`；② `ThincoderCatalog` 的 `initialize` 仍为 `{}` |
| T88 | 读走缓冲 | fake 的 `readText` 返回缓冲文本；push `fs/read_text_file` | 响应 `{'content': '<缓冲文本>'}` |
| T89 | 干净打开写 | 假工作区干净文档；push 写 | 响应 `{}`；模型 `text` == content、`savedText` == content；`FileEdited` 一条 |
| T90 | 变更面 | 同 T89 | `FileEdited.change.path` == 路径；`original` 是 `OriginalText(before)`；`turnId` 为当前回合（无回合时 null） |
| T91 | 未知方法 | push `fs/something_else` | 响应 `-32601`（既有路径）；零 handler 调用 |
| T92 | 读错误面 | fake 抛二进制 / 超限异常 | 响应 `-32603`，message 含可读原因；无 `FileEdited` |

- 测试手段：`ThincoderMock.push()` 直推反向请求（`thincoder_mock.dart:138-140`），响应在 `mock.written` 里按 id 取（`thincoder_protocol.dart:176-186`）；`KernelFiles` 用测试假件（`KernelContext(files: …)`），IDE 桥用假 `IdeWorkspace` / 假 `IdeFileService` 直测（`test/ide/ide_kernel_files_test.dart`）。

### 21.7 测试策略与机检命令

- 单测（本批）：`flutter test test/kernel/thincoder_files_test.dart test/ide/ide_kernel_files_test.dart test/kernel/thincoder_kernel_test.dart test/chat/open_editor_test.dart test/chat/editor_context_chip_test.dart`；静态检查：`flutter analyze`。
- 固件：不加（线形无新增；FS 请求由 mock `push` 直推）。
- 集成测试：本批不新增业务场景；收口时按仓库既有集成门跑一次（面不受影响）。
- 验收命令（逐条）：
  - T87：`expect((agent.requests('initialize').single['params'] as Map)['clientCapabilities'], {'fs': {'readTextFile': true, 'writeTextFile': true}})`。
  - T83 / T86：从 `agent.written` 里按请求 id 找 `error`；检查 `transcript` 的 `NoticeItem`。
  - T85：`Directory.systemTemp.createTempSync()` 写后 `File(path).readAsStringSync() == content`。

### 21.8 边界（本批不做）与登记（判定条件）

1. **不做任意路径写入**：只允许 `cwd` + 工作区 folders 之内（需求边界）；根外用 `-32602` + 可见提示。
2. **不代管二进制大文件**：`fs/read_text_file` 遇二进制 / 超限按文件服务异常回 `-32603`；`fs/write_text_file` 只写文本（`content` 必须是字符串，非法 ⇒ `-32602`）。判定条件：产品要「agent 改二进制」⇒ 另立（需新的字节面，协议无）。
3. **不改既有变更审查面语义**：只发既有 `FileEdited`；Keep / Undo / hunks 不动（D79）。
4. **不做远端项目的 fs 桥**：thincoder 进程是本地进程；远端根且无打开工作区 ⇒ 拒绝并在会话内提示。判定条件：thincoder 支持远端会话 ⇒ 把 `KernelFiles` 实现换成 `IdeHostFiles`（`file_service.dart:56-68` 已有远端文件面）。
5. **不路由 `apply_patch` / `delete` / `read` 工具**：CLI 侧保持本地（`bridge.mjs:386`）；本批只接 `write` / `edit` 两条既有路由。
6. **脏缓冲不自动保存、不合并、不提供应用按钮**（D76 / D81）：用户保存或放弃自己的缓冲后让 agent 重试；只读 diff 供审阅。
7. **不接 `terminal/*`**：CLI 侧明确不支持（外仓设计档 §2.2）。
8. **`security` 面**：路径限定是「项目根内」的产品约束，不是安全沙箱（同一用户进程、同一权限）；不做审批弹窗（写工具本身走既有审批面）。
9. **并发写**：两个写请求同时到（不同文件）各自落盘；同一文件由 CLI 串行（tool 调用串行）+ `expectedText` 基线保护（后写发现基线变了 ⇒ `-32603`）。判定条件：走查见到「同一文件并发写丢更新」⇒ 在 `IdeKernelFiles` 加每路径串行队列（本批不改）。
10. **符号链接根（非 Windows）**：请求路径与每个允许根都按 realpath 规范化后比较（不存在路径按最近存在祖先）；桥侧同口径——`IdeKernelFiles` 先规范化请求路径与各工作区根，命中后按该工作区自己的拼写（根 + 相对段）回传文件服务与 `reload`。经链接打开的根（macOS `/var` 等）因此仍能找到打开文档与未保存缓冲。Windows 未复现该类根。判定条件：非 Windows 走查见到「内核已放行、桥侧找不到打开文档 / 脏缓冲未被拦住」⇒ 内核与桥的规范口径分叉，按本条修。
11. **多窗口同一路径**：打开文档的读取取**先打开者**（`IdeWorkspace.openWorkspaces` 的注册顺序）；写侧脏检查覆盖全部持有者（任一脏 ⇒ 拒绝），写成功后对每个持有者 `reload`。判定条件：产品要求「活动窗口优先」⇒ 注册表改按活动窗口排序（本批不做）。
12. **工作区 folders 现读（不冻结）**：允许根每个请求现读 `KernelContext.workspace()?.folders`——会话中途加入 / 移除的工作区文件夹即时生效。判定条件：产品要求「根集合随会话启动冻结」⇒ 在 `ThincoderFiles` 构造时快照并补用例（本批不做）。

### 21.9 真机走查步骤

1. 新建 thincoder 会话，打开项目；在编辑器打开 `a.dart`，**改一行但不保存**（脏缓冲）。
2. 让 agent「把 a.dart 的第 X 行改成 Y」⇒ 编辑器弹出只读 diff（左 = 你的缓冲，右 = agent 内容）；会话里一条 error 提示；你的缓冲与磁盘都没变；agent 的答话说明写入未应用。
3. 保存（或放弃）你的修改，再让 agent 重试 ⇒ 写入成功；编辑器显示新文本；变更面板出现该文件，Keep / Undo 可用。
4. 让 agent 改一个**没打开**的文件 ⇒ 保存后 `cat` 内容与 agent 所述一致；变更面板列出。
5. 让 agent 写项目外路径（如 `/tmp/x` 或 `C:\Windows\x`）⇒ 工具结果 error + 会话内提示；文件未创建。
6. 让 agent 用 `edit` 工具改一个**干净但打开**的文件 ⇒ 走 `fs/read_text_file` + `fs/write_text_file`；编辑器同步更新、无脏标记残留。
7. 用终端 thincoder 对照：终端没有 IDE 能力位 ⇒ 编辑直接落盘（桌面看不到 diff）——本批是桌面独有能力。
8. 关闭全部 IDE 窗口后再让 agent 改文件 ⇒ 直接落盘（无打开缓冲可保护）；无 diff 可开，行为与终端一致。

### 21.10 未核实 / 实现期确认项

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| 1 | 脏缓冲拒绝后，CLI 是否把 `-32603` 原文完整回给模型 | `bridge.mjs:369` 包一层 `Error: fs/write_text_file failed: <message>`，已读；模型呈现未走查 | 走查 2 确认；不影响设计 |
| 2 | `IdeFileService.write(expectedText:)` 的冲突异常类型 | 接口注释（`file_service.dart:29-31`）说「拒绝基线变化」，具体异常未读实现 | 实现期读 `file_service_io.dart`，映射到 `-32603` 的可读消息 |
| 3 | `openDiff(modified:)` 的右侧是否稳定只读 | `IdeDocument.readOnly = readRevision != null`（`ide_workspace.dart:196`）已读；diff 编辑器库内行为未走查 | T84 / 走查 2 确认 |
| 4 | thincoder 会话是否可能跑在远端项目 | 本仓 `RemoteLocation` 存在；thincoder 起进程用本地 `cwd` | 实现期确认；远端根按 §21.8-4 拒绝 |
| 5 | 同一文件并发写的实际顺序 | CLI 工具调用串行（`toolRouter` 在 turn 内）；桌面 handler 无队列 | 按 §21.8-9 登记；出现丢更新再加队列 |
| 6 | `saveSession` 对 system-reminder 的过滤（F17 重放） | 只在 TUI 面读到（`bridge.mjs:399-400` 注释）；ACP 路径未核 | 按 §20.8-4 登记；走查确认 |


---

## 22. 原生图片块（F19）

> 需求档 F19（用户 2026-10-19 01:21「原生图片块…提上日程」）：图片以 ACP 原生 image 内容块随 `session/prompt` 发送，模型直接看图；CLI 不支持 image 时回退既有路径（落盘 + 路径行），行为同今天。
> 一句结论：**桌面按握手能力位分两路**——`agentCapabilities.promptCapabilities.image === true` ⇒ prompt 数组 = 一个 text 块 + 逐图 image 块（base64，不落盘）；否则 = 今天逐字不变（`_attachImages` 落盘 + 路径行）。**原生路需动 `thincoder/` 仓（B1 例外，已裁定：用户 2026-10-19 01:37「运行改thincoder仓库」）**；桌面半可单独落地（旧 CLI 下零可见变化）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：原生图片 = Claude 内核既有形（`claude_code_kernel.dart:929-945`：逐图 `text [Image #N]` + `image` 块 base64 + 媒体类型）——本批照抄「image 块携原始字节」的形，不照抄其外层 envelope。
- 对齐 ②：能力位探测 = 既有握手读取（`thincoder_kernel.dart:378-391` 读 `agentCapabilities.mcpCapabilities.http`；本批同点读 `promptCapabilities.image`）。
- 对齐 ③：限额与丢弃 = 既有 `_attachImages`（`:1096-1134`：单项 15 MB / 回合 30 MB / 扩展名白名单，超阈弃 + `NoticeItem(warning)`）——原生路复用同一判据，只把「落盘」换成「直接进块」。
- 对齐 ④：线形 = ACP v1 `ContentBlock::Image`（schema：`{type:"image", data:<base64>, mimeType, uri?}`；`PromptCapabilities.image` 默认 false，启用才可发）。
- 偏离 ①：原生路**不**发 `[Attached images: …]` 路径行（无落盘文件）；正文里已有的 `[Image #N]` 行内标记由 composer 写入（`composer.dart:609`），照发。
- 偏离 ②：内核**不**声明 `AcceptsImages`（编译期能力不随握手变；宿主侧仍以 `AcceptsImageFiles` 判「收图」）——D82。
- 偏离 ③：非多模态模型的降级**不在桌面做**（桌面不读 provider 规格，E3）：CLI 侧 `stripImagesForTextModel`（`provider/core.mjs:133` / `normalize.mjs:100-121`）已把图块替换为 `[image omitted — this model does not support image input]`，如实可见。

**survey 证据**：ACP v1 schema（agentclientprotocol.com/protocol/schema，2026-10-19 取）：`ImageContent.required = ["data","mimeType"]`、判别值 `type:"image"`；`PromptCapabilities.image` 默认 false、「Requires the image prompt capability when included in prompts」。

外仓（2026-10-19 实读）：`client-caps.mjs:59-61`（`promptCapabilities.image: true`——已接原生 image 块；audio / embeddedContext 仍 false）；`handlers-session.mjs:374-395`（`session/prompt` 走 `buildPromptContent`：有图 ⇒ `session.run({text, images})`，无图 ⇒ 单串）；

`resource-link.mjs:144-171`（`buildPromptContent`：text = 首个合法 text 块 + resource_link 内联；images = 按数组序的合法 image 块，mimeType 白名单 + 单图 / 回合限额，畸形 ∥ 超阈弃 + 日志）；`session.mjs:78-90`（`execTurn` 透传到 `runAgent`）；

`thincoder-core/agent/setup.mjs:53-57`（`input` 可为 `{text, images}`——检索只取 `input.text`）· `:188-199`（`pushReal` 的 content = text part + `image_url` parts；只发图 ⇒ 不发空 text）；
`bridge.mjs:406-414`（重放跳过 image 块 + 日志）；`suspension.mjs:96-101` / `:154-170`（窗内轮透传富对象——批 11 ⑤ 已落）。

结论：**原生图 = CLI 侧三层改动**（能力声明 + 内容构造 + 富输入透传）；批 11 CLI 半已落（§22.2 表 ①–⑤）；桌面半（能力位探测 + 两路分支）纯客户端、可独立验收。

### 22.1 做法：能力位 ∥ 两路 prompt ∥ 一处回退

```text
initialize 回包 agentCapabilities.promptCapabilities.image == true ?
  ├─ 是（新 CLI）⇒ _deliver：prompt = [ {type:"text", text: 正文+编辑器 note} ,
  │                                      {type:"image", mimeType, data: base64} × N ]
  │                  不落盘；限额同今天（15 MB/图 · 30 MB/回合）
  └─ 否 / 缺位（旧 CLI）⇒ 今天逐字：_attachImages 落盘 <cwd>/.thincoder/tmp/paste-… +
                         正文尾附 [Attached images: …] + 单 text 块（T94 钉住）
```

- 能力位读取点 = `_handshake`（`thincoder_kernel.dart:378-391`）；存 `bool _nativeImages`（缺省 false = 旧形）。
- 分支点 = `_deliver`（`:567-644`）：`_nativeImages` 时用 `_nativePrompt(turn)`（新私有方法）替代 `_attachImages`；两路共用同一限额判据（单项 15 MB / 回合 30 MB / 扩展名白名单）与同一丢弃计数 + `NoticeItem(warning)`（文案同今天，`:596-600`）。
- 原生路不写盘：不建 `.thincoder/tmp/`、不产生路径行；`UserMessageItem.images` 仍是校验后的图片（气泡照常显示）。
- 文本 = 用户正文 + 编辑器上下文 note（§20 既有拼接），无图片路径行。
- 图片块顺序 = `turn.images` 顺序；正文里的 `[Image #N]` 行内标记保留（模型可按号对图）。
- 回退判据 = **能力位在场且为 true**；其余一切（旧 CLI / 未声明 / 字段畸形）⇒ 今天路径，逐字不变（需求「CLI 不支持时回退既有路径且行为同今天」）。

### 22.2 契约（线形、限额、错面）

**线上形（`session/prompt` 的 `prompt` 数组，原生路）**

```json
[{"type": "text", "text": "<用户正文>\n\n<system-reminder>…编辑器上下文…</system-reminder>"},
 {"type": "image", "mimeType": "image/png", "data": "<base64>"}]
```

- `mimeType` 取 `ImageAttachment.mediaType`（白名单 png/jpeg/gif/webp，`_imageExtension` 同源判据）；`data` = 原始字节 base64（无 data URL 前缀）。
- 块序 = 图序；text 块恒在首位（CLI 侧取首个合法 text 块作检索文本）。
- 只发图、无正文：text 块 = 编辑器 note；两者都空 ⇒ 不发空 text 块（CLI 现行 `-32602` 判据是「无 text 且无 resource_link」，B1 侧扩为「…且无图」）。
- 限额：单项 ≤ 15 MB（`imageMaxBytes`，`:1074`）、回合合计 ≤ 30 MB（`turnMaxBytes`，`:1077`）；超阈项弃并计数。

**CLI 半（B1 最小改动面；已裁定 A：用户 2026-10-19 01:37）**

| # | 文件 | 改动 | 量 |
|---|---|---|---|
| ① | `thincoder-cli/src/acp/client-caps.mjs:55-63` | `promptCapabilities.image: true`（注释改述：image 已接；audio / embeddedContext 仍 false） | +1 / 1 行改 |
| ② | `thincoder-cli/src/acp/resource-link.mjs` | 新增 `buildPromptContent(blocks, {cwd})` → `{ text, images }`：text = 既有 `buildPromptText` 结果；images = `type:"image"` 块按序，`mimeType` 白名单 + base64 解码 + 15 MB/图 ∥ 30 MB/回合（直引 `attachments.mjs:31-36` 常量）；畸形 / 超阈 ⇒ 弃 + 一行日志 | ≈ +45 |
| ③ | `thincoder-cli/src/acp/handlers-session.mjs:374-393` | 改用 `buildPromptContent`；有图 ⇒ `session.run({ text, images })`，无图 ⇒ 仍传字符串（零行为变化）；空判据扩为「无 text ∧ 无 resource_link ∧ 无图」 | ≈ +8 |
| ④ | `thincoder-core/agent/setup.mjs:53-57` / `:188-199` | `input` 可为 `{ text, images }`：`docSearch` / `memorySearch` 用 `input.text`；`pushReal` 的 content = `[{type:"text", text}] + image_url parts`（`data:<mime>;base64,<b64>`）；多模态退化交 `provider/core.mjs:133` 既有剥除 | ≈ +12 |
| ⑤ | `thincoder-cli/src/acp/suspension.mjs:96-101` / `:154-170` | 窗内轮透传富对象（只留 `.text` 的旧形会让窗内到达的图静默丢） | ≈ +4 |
| ⑥ | `thincoder/docs/cli/design/ACP-CLIENT.md` | `promptCapabilities` 事实行改 true（能力位表）；`session/prompt` 内容块说明补 image 块（块形；空判据扩为「无 text ∧ 无 resource_link ∧ 无图」） | 文档面 |
| ⑦ | `thincoder-cli/CHANGELOG.md` 顶部 | 新增 `## [Unreleased]` + `### Added` 一行（原生 image 块随 prompt 发送；能力位转 true） | 文档面 |
| ⑧ | 该仓测试档 | `buildPromptContent` 单测（白名单 / 超阈 / 混块）+ 一轮带图 prompt 到达 `runAgent` 的输入形 | 测试面另计 |

- 合计 ≈ +70 行 + 测试；单点新增、可上游合并（无格式噪声）。
- ⑥–⑦ 是契约档与 CHANGELOG 的**同拍义务**：代码改了而契约档不改，就是把一份说反的契约留在仓里（该仓对文档与代码同拍的通行做法；形同 §16.1 f–k）。
- **替代方案（已查实不可行）**：`resource_link` 指向图片 ⇒ CLI 读盘按文本处理（NUL ⇒ `binary (NUL byte)` 标记，`resource-link.mjs:84`），不产生图像 part；`embeddedContext`（Resource 块）⇒ CLI 声明 false 且未实现。
- **不做 B1 的后果**：F19 实质验收（模型直接看图）不成立；桌面半照常可落（能力位探测 + 分支 + 回退），但恒走旧路——与今天零差异。

### 22.3 桌面半受影响文件清单（E2 增量；行数 = 2026-10-19 `wc -l` 实测）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_kernel.dart`（1055） | `_handshake` 读 `promptCapabilities.image`；`_deliver` 原生分支 / `_nativePrompt`；限额判据复用 | ≤ +30（⇒ ≤1085） |
| ② | `test/kernel/thincoder_kernel_test.dart`（3395） | T93–T95（§22.6）；mock 增 `promptImage` 能力位开关（缺省 false = 今天） | ≤ +163（⇒ ≤3558；T95② 于实施期补入，+53） |
| ③ | `lib/kernel/thincoder/thincoder_mock.dart`（632） | `initialize` 回包按构造参数给 `promptCapabilities.image`（缺省 false） | ≤ +6（⇒ ≤638） |

- **体量**：`thincoder_kernel.dart` 在 >800 名单（§5.2 体量立场 = 不续拆）。§21.3 的拆分（批 10 第三波）已落：基线 **1055**；本批 +36（§22 + ≤30、§23 + ≤6）⇒ ≤1091，余量 57（§21.3「实现后 ≤1148」）。
- **>500 层**：`thincoder_mock.dart`（632 → ≤638）在 >500 且 <800 区间——体量立场只跟 >800（§5.2 末段），不立缝。
- **零改动**：宿主层（`AcceptsImageFiles` 不变，D82）· `chat_session.dart` / composer（收图判据不变）· Claude / Codex 内核 · `thincoder_events.dart` · 固件。

### 22.4 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D82 | 能力位随握手（`promptCapabilities.image`），**不**按编译期接口翻牌；内核仍只声明 `AcceptsImageFiles` | 同一内核连新旧 CLI 都可能；编译期 `AcceptsImages` 会在旧 CLI 上虚报（E3）。宿主只需「收图」一个判据（composer / `ChatSession.acceptsImages`），行为差异留在内核。被否：新增 `AcceptsImages`（宿主判据两处、且旧 CLI 下假报） |
| D83 | 原生路**不落盘**、不发路径行 | 需求「不再只依赖落盘路径告知」；落盘只会多一份无主副本（终端按 3 天窗扫除 `.thincoder/tmp`，`attachments.mjs:14-17`）。被否：两路都发（重复内容、模型两处引用同一图） |
| D84 | 非多模态模型退化交 CLI（`stripImagesForTextModel`），桌面不做视觉判据 | 桌面不读 provider 规格；CLI 每次请求前统一剥图并留 `[image omitted — …]` 可见文本（`provider/core.mjs:133` / `normalize.mjs:100-121`）。被否：桌面按模型名判视觉（模型清单不可靠、且要维护规格副本） |
| D85 | 回退判据 = 能力位在场且为 true；其余一律今天路径 | 需求「CLI 不支持时回退既有路径且行为同今天」；能力位 = 协议唯一权威（ACP：omitted ⇒ UNSUPPORTED）。被否：按版本号判（E3 不加版本门） |
| D86 | B1 例外面 = 5 档 ≈ +70 行（§22.2 表）；替代通道已查实不可行 | 不改 CLI ⇒ 图块到不了模型（`buildPromptText` 丢块、`run` 只收文本）。被否：桌面自建第二条旁路（协议无通道） |

### 22.5 验收对照（回指需求档 F19）

| 需求条目（F19） | 本档落点 | 判据（机检 / 走查） |
|---|---|---|
| 发送图片 ⇒ `session/prompt` 的 prompt 数组含原生 image 块（与 text 并存） | §22.1 / §22.2 | T93：prompt = 1 text 块 + N image 块；`type` / `mimeType` / `data` 逐值（base64 解码 == 原字节）；正文无 `[Attached images:` |
| 模型回答能引用图片内容 | §22.1（CLI 半）· §22.9（真机 provider 面） | T1 / T1b（块形逐值；provider body 无 `image_url`）+ 走查 2（桌面）∥ S1（终端 Claude 族，问图中内容） |
| CLI 不支持 image 时回退既有路径且行为同今天 | §22.1 回退判据 | T94：mock 不声明 image ⇒ prompt 单 text 块、含 `[Attached images: <路径>]`、文件已落盘（今天形） |
| （派生）限额与丢弃不回归 | §22.2 限额 | T95① / T95②：超阈图（单图 ∥ 回合合计）⇒ 不进块 + `NoticeItem(warning)`；其余照发 |
| （派生）桌面半不依赖 CLI 改动可验 | §22.3 ② | T93–T95 全在 mock 层（`promptImage` 开关），不装真 CLI |

### 22.6 用例表（T93–T95，`test/kernel/thincoder_kernel_test.dart`）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T93 | 原生路（新 CLI） | `ThincoderMock(promptImage: true)`；`KernelTurn(text:'看图', images:[png 3 字节])`；`KernelContext(cwd: 临时目录)` | `session/prompt.prompt` == `[{type:'text', text: 含'看图'}, {type:'image', mimeType:'image/png', data: base64}]`；text 不含 `[Attached images:`；`UserMessageItem.images` 一条；`<cwd>/.thincoder/tmp` 不存在 |
| T94 | 回退路（旧 CLI） | `ThincoderMock()`（缺省 image:false）；同图 | prompt 单 text 块，含 `[Attached images: <cwd>/.thincoder/tmp/paste-…]`；文件存在且字节一致（今天形） |
| T95① | 原生路超阈（单图） | `promptImage:true`；一张 15 MB+1 字节 + 一张合法 | 只有合法图进块；`NoticeItem(warning)` 一条（文案同今天）；丢弃计数 1 |
| T95② | 原生路超阈（回合合计） | `promptImage:true`；三张 [15 MB, 14 MB, 2 MB]（每张合法，合计 31 MB > 30 MB） | 前两张进块、第三张被弃（回合合计判据）；`NoticeItem(warning)` 一条（文案同今天）；丢弃计数 1 |

- 既有 T15 / T16 / T27（图片替代 / 超阈 / 合计超阈）保持绿 = 回退路不回归。

### 22.7 边界与登记（判定条件）

1. **不做图片编辑 / OCR / 远程项目图片**（需求边界）。
2. **不改 Claude / Codex 内核图片面**（需求边界）。
3. **重放不带图**：CLI `session/load` 重放跳过 image 块（`bridge.mjs:406-414`，日志一行）⇒ 桌面切回时气泡图仍在（宿主自持 transcript）；终端侧历史里的图不重放。判定条件：产品要求重放也带图 ⇒ CLI 侧补 `user_message_chunk` 的 image 块（另立）。
4. **挂起窗内的图**：窗内轮已透传富对象（批 11 ⑤ 已落：`suspension.mjs:96-101` / `:154-170`）；窗退 idle 的残余补发径现按富对象补发（§22.11，批 12 已落）。判定条件：走查见到窗退 idle 后补发的回合丢图 ⇒ §22.11 未生效，按该节判据补。
5. **不做视觉能力探测**：非多模态模型的退化在 CLI（D84）；桌面不发「模型不支持图」提示（CLI 的 `[image omitted — …]` 文本是唯一可见面）。
6. **B1 已裁（A）**：桌面半与 CLI 半一并实施；新 CLI 合入前生产行为 = 今天（旧 CLI 恒 false），T93–T95 以 mock 能力位驱动。
7. **CLI 会话存档里的图块（口径 = 剥离；落地 = §22.10 / 批 12）**：CLI 按回合保存会话（`thincoder-cli/src/acp/session.mjs:111` 每回合 `save`）。人读线已剥图（`slimForDisplay`，`session-segments.mjs:35-39`）。
   机器线 `contextHistory`（`thincoder-core/session.mjs:144`，进槽 `:199-200`）原样进槽 ⇒ 原生路经 `pushReal` 入 `agent.history` 的 base64 图随每回合整写槽 JSON（单回合可达 30 MB × 4/3 ≈ 40 MB）。

   **口径 = 剥离**：存档前丢 `image_url` parts、只留 text 与 `[Image #N]` 行内标记（与重放跳过同判据，`bridge.mjs:406-414`）；落地设计 = §22.10（`stripImagesForArchive`，单入口 = 核 `saveSession`）。
   判定条件：带图回合后槽文件仍随图膨胀 / `save` 报错或变慢 ⇒ 剥离未生效，按 §22.10 补。
8. **握手完成前的首条消息走回退路**：能力位在 `_deliver` 开头快照（`final native = _nativeImages`，`thincoder_kernel.dart:592`），握手在 `_ensureStarted()`（`:629`）才发生 ⇒ 冷启动首条消息（含图）在握手完成前发出时，即使 CLI 支持 image 也走回退路（落盘 + 路径行）。回退安全、窗口窄（仅首条）。判定条件：走查见到冷启动首条图走回退路而 CLI 已声明 image ⇒ 评估把附件判定移到 `_ensureStarted()` 之后（改变消息即时回显时机）⇒ 单独立项。
9. **全部图被弃 + 无正文 ⇒ 空 `prompt` 数组**：原生路图全被弃（超阈 / 畸形）且正文为空 ⇒ 无 text 块、无 image 块 ⇒ `prompt` 数组为空（`thincoder_kernel.dart:650-659`）⇒ CLI 按空判据回 `-32602`；回退路同场景同样发不出有效文本（无路径行、正文为空）。判定条件：走查见到用户未发出任何图却收到参数错 ⇒ 桌面补空判据（无有效内容 ⇒ 本地 error 提示，不发请求）。

### 22.8 真机走查步骤

1. 装含 B1 的 CLI + 桌面；新建 thincoder 会话，选视觉模型。
2. 发一张截图 + 一句「这张图里是什么」⇒ 模型直接答出图中内容（不调 `read_image`）。
3. 换非视觉模型 ⇒ 同一张图：模型看到 `[image omitted — this model does not support image input]`，不崩。
4. 把 `thincoder.path` 指回旧版 ⇒ 发图：与今天一致（落盘 + `[Attached images: …]`，模型可 `read_image`）。
5. 对照终端：终端贴图走 `read_image <path>`（`clipboard.mjs:188-223`），桌面原生路是增量——终端行为不变。
6. 超阈图（>15 MB）⇒ 会话内 warning 一条，其余图照发。

### 22.9 真机 provider 面（`image_url` 与 tool 消息 → Anthropic 原生块）

> 回指：需求档 F19「模型回答能引用图片内容」。核内历史是 OpenAI 形（`{type:"image_url",image_url:{url:"data:<mime>;base64,<b64>"}}`），`format:"anthropic"` 时原样下发 ⇒ Anthropic 收到未知 part，图到不了模型；既有 `read_image` 同病（`provider/anthropic.mjs:41-49` 只抽 system，其余消息原样进 `body.messages`）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：转换点 = transport 边界，同 `provider/google.mjs:53-61`（`image_url` → `inlineData{mimeType,data}`）与 `provider/responses-request.mjs:100-104`（→ `input_image`）；copy-on-write 形同。设计档对位 = 核 PROVIDER 设计档 §6.8（消息块形按 Anthropic 原生块下发；tool 块同节）。
- 对齐 ②：不可转换的图 ⇒ 原位换可见文本（`normalize.mjs:100-121` 的 `[image omitted — …]` 形），不静默删 part。
- 对齐 ③：`read_image` 的图 = 同一 user 消息 parts（`agent/record-results.mjs:54-69` 注入 `[{type:"text"}, ...images]`）⇒ 本转换一次，工具面与原生图两路同享（工具面零改）。
- 偏离 ①：google 对解析失败的 data URL 静默丢 part；本处在丢弃时留一行 `logEvent`（真机排障要能看见「哪一单丢了几张」）。被否：静默丢（无痕）。

**survey 证据**：Anthropic 官方 TypeScript SDK 类型定义（`@anthropic-ai/sdk` latest · `resources/messages/messages.d.ts` · 2026-10-19 经 unpkg 取）逐字——

`ImageBlockParam { type:'image'; source: Base64ImageSource | URLImageSource | FileImageSource }`；`Base64ImageSource { type:'base64'; media_type: 'image/jpeg'|'image/png'|'image/gif'|'image/webp'; data: string }`。

官方文档站（docs.anthropic.com / platform.claude.com）本机 region-blocked，未取到页面；**未对真 API 实测（unverified）**。

同仓实测：`provider/core.mjs:128-140`（分派前剥图——`stripImagesForTextModel` 只留 `multimodal` 的栅格 data URL；`capHistoryImages` 32 MB 预算）· `provider/normalize.mjs:11`（`RASTER_IMAGE_URL` 四型，含别名 `image/jpg`）· `provider/anthropic.mjs:52-59`（`body.messages = chatMessages` 原样）。

**做法**：`anthropic.mjs` 新增导出纯函数 `convertMessages(messages)`；`chat()` 以它生成 `body.messages`。

- `content` 字符串 ⇒ 原样；数组 ⇒ 逐 part：`text` 原样；`image_url` 按 data URL 形状转换；其余 part 原样。
- 转换 = `{type:"image",source:{type:"base64",media_type,data}}`；`data` = data URL 逗号后原文（不解码 / 不重编码）；`media_type` = mime，`image/jpg` 归一为 `image/jpeg`（核内放行该别名，Anthropic 只收四型）。
- 不可转换（非 data URL / 白名单外 mime / payload 为空 / 形状不符）⇒ 该 part 原位换 `{type:"text",text:"[image omitted — unsupported image source for the Anthropic transport]"}`，并 `logEvent("llm:image-drop", {transport:"anthropic", count})` 一行（每请求至多一行，count = 本请求丢弃数）。
  **二选一写死 = 丢弃换占位**（保留原样 = 整单 400，模型仍看不到图）。
- copy-on-write：无 `image_url` ⇒ 原数组 / 原消息引用返回；有 ⇒ 只重建涉及对象（`agent.history` 零触）。占位保证 `content` 不为空数组。
- `provider/rate.mjs` 的 `estimateText` part 判据补 `type:"image"`（同计 85 tokens）：转换先于 `estimateRequestTokens(body)`，不补则图从限流估算里消失。

**工具消息（同一 `convertMessages`）**：assistant 的 `tool_calls` ⇒ `tool_use` 块（`id` / `function.name` / `function.arguments` 解成对象；坏 JSON 或非对象 ⇒ `{}`）；

`role:"tool"` ⇒ 一条 user 消息里的 `tool_result` 块（`tool_call_id` → `tool_use_id`，content 串原样、非串 `JSON.stringify`）；相邻的 `role:"tool"` 合进同一条 user 消息（Anthropic 的 user/assistant 交替）。
copy-on-write：无图、无工具 ⇒ 原数组引用；命中只重建该消息对象（`anthropic.mjs:36-109`）。

tool 块形按官方 SDK 类型定义与核 PROVIDER 设计档 §6.8 写死，**未对真 API 实测（unverified）**；判定条件 = 真机 Claude 族多轮工具会话（`tool_use` → `tool_result` 往返）不出现 4xx、工具照跑。

**契约（`messages[i].content[j]` 的块形）**

```json
{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "<base64>"}}
```

- 转换只发生在消息块形上：role / 条数 / 其它字段零改；未命中（无图、无工具）的消息原引用返回，入参数组与 `agent.history` 不被修改。

**决策**

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D91 | 转换点住 anthropic transport（`convertMessages`），不进 `normalize.mjs` 共用层 | 两个 in-repo 先例都在 transport 边界转换；共用层会把 OpenAI 形当成「已归一」的假前提，三个 transport 的块形互相污染。被否：normalize 统一转（改坏 OpenAI / Google 通路） |
| D92 | 不可转换 ⇒ 丢弃换文本占位 + 一行 `logEvent`；不保留原样 | 保留 = 整单 400（图仍不可见）；占位与 `stripImagesForTextModel` 同形，模型可见「有一张图没进去」。被否：静默删 part（消息可能变空 / 语义无痕）；被否：转 `source.type:"url"`（依赖 Anthropic 侧抓取，未验证；历史里只有 data URL） |

**验收**

| 判据 | 手段 |
|---|---|
| 图像块逐值正确（png / jpg 别名归一） | T1（纯函数）+ T1b（假服务器抓 `POST /v1/messages` body） |
| 坏源 ⇒ 占位 + 一行日志、消息不空 | T1 |
| copy-on-write 两半边：无图 ⇒ 原引用返回；有图 ⇒ 入参数组与 `agent.history` 引用 / 内容均不变，只有返回的新数组含 image 块 | T1 |
| 真机 Claude 族能看图 | 走查 S1（发图提问） |
| tool 消息逐形正确（`tool_calls` ⇒ `tool_use`；`role:"tool"` ⇒ `tool_result`；相邻结果合并） | T1c；真 API 面未实测，判定条件见 §22.9「工具消息」 |

**用例**

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 纯函数逐形 | user 消息含 `text` + `data:image/png;base64,AAAA`；`data:image/jpg;base64,AAAA`（别名）；`https://x/y.png`；`data:image/bmp;base64,AA`；另备无图数组一条 | png ⇒ `{type:"image",source:{type:"base64",media_type:"image/png",data:"AAAA"}}`；jpg 别名 ⇒ `image/jpeg`（data 同 `AAAA`）；后两例 ⇒ text 占位、丢弃计数 2；text part 原位原样；有图输入：返回数组 ≠ 入参数组 ∧ 入参数组与 `agent.history` 的引用 / 内容均不变；无图数组 === 原引用 |
| T1b | provider 级 body | 本地假 Anthropic SSE 服务；`chat()` 带一张图 | 收到的 `body.messages[0].content[1]` 逐值 = image 块；body 序列化不含 `image_url` |
| T1c | tool 消息逐形 | assistant 带 `tool_calls`（arguments 为合法 JSON / 坏 JSON）；两条相邻 `role:"tool"`；无工具消息 | `tool_use` 块的 `input` 为对象（坏 JSON ⇒ `{}`）；两条相邻结果合进同一条 user 消息、顺序不变；`tool_call_id` → `tool_use_id`；无工具消息 === 原引用 |

**边界（本节不做）**：不改 `stripImagesForTextModel` / `capHistoryImages` 判据 · 不做 URL 图源 / 缩放 / 转码 / 去重 · 不做图像 token 精算（85/块沿用粗估）· 不改 Google / responses 两 transport。

### 22.10 槽文件剥离（存档机器线只丢图）

> 回指：批 11 §22.7-7 的既定口径（剥离）+ 台账 #87。原生图经 `pushReal` 入 `agent.history`；CLI / 桌面 / TUI 每回合 `saveSession` 把机器线整写槽 JSON（`thincoder-cli/src/acp/session.mjs:111` 每回合 `save`；单回合 ≤30 MB 原始字节 ×4/3 ≈ 40 MB）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：人读线先例 `session-segments.mjs:35-39`（`slimForDisplay`：多模态 user 保留 text、丢 `image_url`）——同一口径搬到机器线。
- 对齐 ②：占位形 = `normalize.mjs:86-98`（`stripRejectedImages`：坏图原位换文本，消息不空）。
- 偏离 ①：**不复用** `slimForDisplay`——它同时截断 tool args（300 字符）与 tool content（500 字符），机器线其余部分须逐字节保持（恢复前缀缓存契约，`session.mjs:134-141`）。被否：直接复用（恢复后上下文静默缩水）。
- 偏离 ②：不在 CLI 的 `save` 调用点过滤——只覆盖 ACP，TUI / 桌面的 `saveSession` 漏；且该档载他批未提交改动（对齐步骤见 §22.12）。被否：调用点过滤。

**survey 证据**：外仓档 `thincoder/docs/core/design/SESSION.md`（双线结构 = `history` 人读 / `contextHistory` 机读；`slimForDisplay` 人读线丢 `image_url`；

机读线保留 transient——`:119-139`，决策 D-SE6 / D-SE7 / D-SE8 `:1010-1012`）；

`thincoder/docs/cli/design/ACP-CLIENT.md` §6.3（每回合末存档）；`thincoder/docs/core/design/API-CONTRACT.md:1815`（`saveSession` 出口坐标）。结论：剥离只该动机读线、人读线已有先例——本节断言与上列档一致；同仓代码实读见上文先例坐标（`session.mjs:134-147` · `session-segments.mjs:35-39` · `normalize.mjs:86-98`）。

**做法**：`thincoder-core/session.mjs` 导出纯函数 `stripImagesForArchive(messages)`（`:77-88`），`saveSession` 的机器线生成点（`:144`）用它；占位常量 `IMAGES_STRIPPED_PLACEHOLDER` 单源住 `session-segments.mjs:33`，人读线 `slimForDisplay` 与机器线同用（`:38-45`），`session.mjs:73-74` import + re-export 保既有 import 面。

- 只丢 `type === "image_url"` 的 part；text（含 composer 的 `[Image #N]` 行内标记）与其余 part 原样。
- copy-on-write：未命中消息原引用；命中只重建该消息对象（`agent.history` / `_fullHistory` 零触）。
- 丢后 `content` 为空数组（只含图的 user 消息）⇒ 换单 text part `IMAGES_STRIPPED_PLACEHOLDER`（`[image omitted — stripped from the session archive]`）；人读线对同一消息同给这个占位（`slimForDisplay`），两线同文。
- 两条线都在源头剥图（人读 `slimForDisplay` / 机器 `stripImagesForArchive`）；未绑定模式（`legacyHistory`）同样已剥；槽写面两条路（`saveProjectedSlot` / `writeSessionFile`）同收一个 `contextHistory`，改在生成点 ⇒ 两路同效。
- 恢复语义：重开 / 恢复后不再持有旧图（模型见占位文本），与 §22.7-3「重放不带图」同口径；活会话内存历史不动。

**决策**

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D93 | 剥离住核 `saveSession` 的机器线生成点（单入口：CLI / 桌面 / TUI 同享） | 三端都走 `saveSession`（桌面 `session-io.mjs:40` 直调）；调用点过滤只覆盖一端且碰他批在改的档。被否：CLI save 调用点过滤；被否：复用 `slimForDisplay`（截断机器线） |

**验收**

| 判据 | 手段 |
|---|---|
| 槽 JSON 的 `contextHistory` 无 `image_url` / `data:image/`，text 与 `[Image #N]` 在 | T3（`_setSessionsDirForTest` 临时目录 + `saveSession` + 读槽） |
| 机器线其余内容逐字节保持（tool args / content 不截断） | T2（纯函数：只丢图 part、顺序不变） |
| 活会话图不丢（copy-on-write） | T2 / T3：`agent.history` 原引用仍含图 |
| 只含图的消息两线都见占位（无空 `content`） | 行为检查：`slimForDisplay` / `stripImagesForArchive` 各喂只含图消息 ⇒ 单 text 占位、两线同文 |
| 每回合写盘不随图膨胀 | S2：带图回合后槽 JSON 的 `data:image/` 计数 = 0，文件字节数与无图回合同量级 |

**T3 两键来源**：`contextHistory` = 机器线单入口（`saveSession` 的 `:144` 生成，`stripImagesForArchive` 用它）；

`history` = 人读线——绑定态由 `saveProjectedSlot` 从记录存储段拼（段 = `slimForDisplay(m)`，`session-store.mjs:339`），
未绑定时 `writeSessionFile(p, { history: legacyHistory(agent) })`（`session.mjs:64-69` / `:200`）；两路都在源头剥图 ⇒ `history` 的断言 = 零回归哨兵。

**用例**

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T2 | 纯函数 | 含 `[Image #1]` text + 图 part 的 user 消息；只含图的消息；无图消息 | 图 part 消失、text 顺序不变；只含图 ⇒ 单 text 占位；无图消息 === 原引用；原数组未被改 |
| T3 | 槽写面 | `_setSessionsDirForTest(临时目录)`；history / `_fullHistory` 带一张 data URL 图；`saveSession(agent)` | 槽文件 `contextHistory` / `history` 均不含 `image_url` / `data:image/`；`[Image #1]` 在场；`agent.history[0].content` 仍含图；`_resetSessionsDirForTest()` 收尾 |

**边界**：只丢 `image_url` parts · 不删消息（空 ⇒ 占位，人读线与机器线同文）· 两线剥图都在源头（人读 `slimForDisplay` / 机器 `stripImagesForArchive`）· VSC 面同口径（`thincoder-vscode/src/extension/panel-session-write.mjs:83` 的机器线过 `stripImagesForArchive`；`session-io.mjs:57` re-export 核面）· 不做旧槽回扫（已落盘的旧图不回收）。

### 22.11 挂起窗残余输入（idle 竞态补发保图）

> 回指：F19 + 批 11 §22.7-4 的残余口。窗内到达 prompt 的主径已闭合（批 11 ⑤：窗内轮透传 `{text, images}`，`suspension.mjs:96-101` / `:154-170`）；**窗退 idle 的残余补发径**现按富对象补发（本节 `residualTurnInput`，批 12 已落）——`submit` 放进 `residualInput` 的条目仍带 `images`，入参形取之。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：富对象入参 = 窗内轮（`suspension.mjs:96-101`）与 `setup.mjs:53-57` 的 `{text, images}` 消费形；判据同（有图 ⇒ 富对象，无图 ⇒ 字符串）。
- 对齐 ②：残余逐条补发 = 既有循环（逐条 `runNormal`、逐条应答 `done`）——只改入参形，不改调度。
- 偏离：无。字符串路径逐字零变。

**survey 证据**：外仓档 `thincoder/docs/cli/design/ACP-CLIENT.md` §12.8（挂起窗回合边界契约：`done` 载荷带原始错误、`submit` 以原始错误拒绝、窗关残余以取消形应答；**无**「窗退 idle 残余补发」措辞）与本档 §19（窗内轮富对象透传 = 批 11 ⑤）；

`thincoder/docs/core/design/AGENT-LOOP.md:78` / `:92`（核 `startSuspension` 句柄 `{pushInput, wake, done}`；退出回执 `{reason, residualInput}`）。结论：idle 残余补发的入参形无外部档约束 ⇒ 断言以代码实读为准（`thincoder-cli/src/acp/session.mjs:72-78` · `suspension.mjs:96-101` / `:154-170` · `setup.mjs:53-57`）。

**做法**：`thincoder-cli/src/acp/session.mjs` 新增导出纯函数 `residualTurnInput(item)`；idle 残余循环用它（现 `thincoder-cli/src/acp/session.mjs:72-78` 的 `else` 支）：

```js
for (const item of residual) {
  const input = residualTurnInput(item)
  if (input !== null) runNormal(input).then(() => item?.done?.({ ok: true }), () => item?.done?.({ ok: false }))
}
```

- 空条目（`{}` / `{text:""}`）⇒ `null` 支：不补发、也不应答（入参形变，调度不变）。

- 映射：字符串 ⇒ 原串（空串 ⇒ `null`——同空残余项）；对象且 `images` 非空 ⇒ `{ text: String(item.text ?? ""), images }`（text 空也发——只发图合法）；对象只有 text ⇒ 该串（空串 ⇒ `null`）；两者皆无 ⇒ `null`（保持今天：不补发、不应答）。
- 中止径（`reason === "aborted"`）零改：逐条以 `AbortError` 取消应答。
- 窗内轮 / 普通队列 / 字符串 prompt 零改。

**决策**

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D94 | 残余补发按富对象透传（图照发），不做「只补文本 + 日志」 | 图是用户输入的一部分；静默丢与窗内轮口径不一致（同一会话两种行为）。富形已被 `runAgent` / `setup.mjs` 接收（批 11 实测）。被否：丢图 + 日志（用户可见面为零） |

**验收**

| 判据 | 手段 |
|---|---|
| 残余含图 ⇒ 补发回合入参为富对象；纯文字 ⇒ 字符串 | T4 |
| 空残余项保持今天（不补发 / 不应答） | T4（`null` 支） |
| 窗内轮 / 中止径不回归 | 代码核（`suspension.mjs` 零改）+ 批 11 单测面不触 |

**用例**

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T4 | 映射逐形 | `"hi"`；`""`；`{text:"hi"}`；`{text:"看图",images:[{…}]}`；`{text:"",images:[{…}]}`；`{}`；`{text:""}` | 依次 = `"hi"`、`null`、`"hi"`、`{text:"看图",images}`、`{text:"",images}`、`null`、`null` |

**边界**：只改 idle 残余补发径 · 不合并 / 不重排残余（逐条）· 图随回合入 history，随后由 §22.10 从存档剥离 · 不做窗内图持久化 / 重放。

### 22.12 本批（批 12）受影响文件、行数预算与测试策略

**B1 依据（core / CLI 改动在例外内）**：用户 2026-10-19 01:37「运行改thincoder仓库」已概准 B1 例外（范围仓 = `thincoder/`，保持上游可合并）；

需求档 F19「依赖」行的现行口径 = 批 11 CLI 侧 5 档 ≈ +70 行 + 批 12 的 core/CLI 4 档 ≈ +64（同裁，out-of-repo 轮）。
本批落其中 4 档 = core 3（`anthropic.mjs` / `rate.mjs` / `session.mjs`）+ CLI 1（`acp/session.mjs`），逐档见下表；批 11 的 CLI 半 5 档已交，本批零改。

**受影响文件（行数 = 2026-10-19 `wc -l` 实测）**

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `thincoder-core/provider/anthropic.mjs`（239） | `convertMessages` + `chat()` 调用 + `logEvent` import | ≤ +36（⇒ ≤275） |
| ①' | `thincoder-core/provider/rate.mjs`（168） | `estimateText` part 判据加 `type:"image"` | 1 行改（净增 0） |
| ② | `thincoder-core/session.mjs`（275） | `stripImagesForArchive` + `:144` 调用（占位常量住 `session-segments.mjs`） | ≤ +16（⇒ ≤291） |
| ③ | `thincoder-cli/src/acp/session.mjs`（180） | `residualTurnInput` + idle 残余循环（现 `:72-78`） | ≤ +12（⇒ ≤192） |
| ④ | `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`（新增） | T1 / T1b / T2 / T3 / T4 | ~+150（零留存） |
| ⑤ | 核的 PROVIDER 设计档 §6.8 · `thincoder-core/CHANGELOG` `[Unreleased]` · `thincoder-cli/CHANGELOG` `[Unreleased]` | 事实行 + 条目（同拍义务） | 文档面 |

- 四档均 <500 行，无拆分议题。零改动：`session-store.mjs` · `normalize.mjs` · `google.mjs` · `responses-request.mjs` · `suspension.mjs` · `agent/setup.mjs` · `agent/record-results.mjs` · `agent/image-heal.mjs` · baocode `lib/**`。
- **开工前对齐（③ 必做；② 所在档现干净）**：
  1. `cd thincoder && git status --porcelain -- thincoder-cli/src/acp/session.mjs`（现 = ` M`）+ `git diff -- <该档>` 存基线；diff 摘要落批档 §5。
  2. 只改 `trackWindow` 的 idle 残余支（现 `:72-78`）与文件头部新增导出函数；不重排 / 不删他批注释 / 不整档格式化。
  3. 写后 `git diff -- <该档>` 逐 hunk 核对 = 基线 hunk + 本批 hunk；基线零变化。提交面由父侧裁定（不 `checkout` / 不 `add -A`）。
  4. `thincoder-core/session.mjs` 现无未提交改动；开工时若出现改动，按同法先对齐。
- **UI**：无新增 UI 面；有模型面行为变更（§22.9 使终端 Claude 族图从「到不了模型」变为真发出 image 块；§22.10 使重开会话后模型见占位文本）。桌面零改；CLI 日志面一行；无 UI 决策项。

**测试策略**

- 单元测试档 = `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs`（该仓惯例：随批次档、零留存、不进任何门）；跑法 `cd thincoder && node --test docs/batches/2026-10-19-f19-cli-closure.test.mjs`；收口删除。
- `npm test`（`test/run.mjs`）只收 `test/**`——本档不进，读数保持「空清单 = 绿」（该仓既有面）。
- 集成测试：无业务场景变更（baocode 零改；ACP 只在窄竞态下补图）⇒ 不新增、不修既有无。
- T3 的测试缝 = `session-slots.mjs` 既有 `_setSessionsDirForTest` / `_resetSessionsDirForTest`（不碰真实会话目录）。

**真机走查（S1–S4）**

- S1（①）：Claude 族 provider（`format:"anthropic"`）+ 视觉模型；发一张截图 + 「这张图里是什么」⇒ 答出图中内容、不调 `read_image`；同一会话再跑一轮工具调用 ⇒ `tool_use` / `tool_result` 往返不 4xx、工具照跑（tool 转换的真 API 面未实测，见 §22.9）。
- S2（②）：同一会话再发一张图 ⇒ 回合尾 `saveSession` 后槽 JSON 无 `data:image/`、`[Image #N]` 在；槽文件字节数与无图回合同量级；重开会话模型见占位文本、不崩。
- S3（③）：挂起窗在（后台子代理 live）时发一条带图 prompt 并留在残余；窗退 idle ⇒ 补发回合的 user 消息 content 含 image 块（日志 / 断点核 `pushReal` 入参）。
- S4（终端侧对照）：同一 CLI 在终端会话让模型 `read_image <path>` 一张图（终端贴图走该工具）⇒ 回合成功、答出图中内容（工具结果的 image 块与原生图同源，均经 §22.9 转换）；日志见 4xx 且带核 PROVIDER 设计档 §6.26 的全剥注记 ⇒ 命中限额自愈（重发一次仍失败 ⇒ 按 U2 记录、另立缩放）。

**未核实 / 需裁**

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U1 | Anthropic 真 API 对转换块形的接受 | 块形 = 官方 SDK 类型定义逐字；未对真 API 实测 | S1 判；失败 ⇒ 按真实错误修形，不改判据 |
| U2 | Anthropic 单图字节 / 像素上限 | 官方文档 region-blocked，未取到一手来源（unverified） | 超限走核 PROVIDER 设计档 §6.26 自愈（4xx + 史含图 ⇒ 全剥 + 注记 + 重发一次）；走查见二次失败 ⇒ 另立缩放 |
| U5 | 需求档 F19 事实行的现行原文 = 「CLI 的 provider vision = `anthropic.mjs` 的 `image_url` 未转 image 块（批 12 的 #85 修）」 | 该事实已指向本批 §22.9（批 11 的 provider vision 待查句已不在盘） | 已闭合、本批不需再动需求档（判据 = §22.9 的 T1 / T1b + S1） |


---

## 23. 用量（F20）

> 需求档 F20（同上）：桌面展示 thincoder 会话的用量——按回合与会话的 token、上下文占用，与终端状态行 ↑+↓ 口径对齐（终端无 `/usage`；context% 不作对照）；成本本批不做。
> 一句结论：**数据源 = ACP `usage_update`（CLI 逐请求上报 `used = prompt+completion`、`size = 上下文窗口`）**；回合用量 = 本回合各条 `used` 之和（喂 turn footer），会话累计 = 全会话之和（上下文面板新增一行），上下文占用沿用今天（最新一条 `used/size`）。**成本本批不做**（CLI 无价目表、从不上报 `cost`；登记 §14-25）。「与终端同口径」= 同一 `onUsage` 来源的 token 合计（终端状态行 ↑+↓）；终端无 `/usage` 命令（登记 §14-26）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：回合用量 = 既有 `TurnEnded.usage`（`kernel_event.dart:34-52`）+ turn footer（`turn_footer.dart:121-148`，Claude 已有 tokens / speed / cost）——本批只把 thincoder 的 `usage` 填上，不新造展示面。
- 对齐 ②：上下文占用 = 既有 `UsageReported` / `ContextUsage` / `ContextUsagePanel`（`thincoder_events.dart:421-434`；`kernel_types.dart:126-140`；`context_usage_panel.dart:50-167`）——F10 已接，本批不改语义。
- 对齐 ③：会话累计 = 面板里新增一行（形同既有 `_Legend` 行，`context_usage_panel.dart:141-153`）。
- 偏离 ①：**不**在桌面重算成本（无价目表、B3 不代管账号 / 账单用量）——成本缺席并在登记里给判定条件。
- 偏离 ②：**不**把终端 context%（`estimateTokens(history)` 估算，`render-loop.mjs:89-90`）当对照口径——不同仪器；对照只对 token 合计（同 `onUsage` 源）。

**survey 证据**：外仓 `bridge.mjs:254-261`（每条 `onUsage` 发一条 `usage_update`：`used = prompt_tokens + completion_tokens`、`size = providerSpec(agent.provider).context`）；

`tool-events.mjs:413-418`（终端把同一回调的 prompt / completion / cacheHit / cacheMiss / reasoning 累加进 `state.tokens`）；`status-line.mjs:122-143`（状态行累计 ↑prompt ↓completion + hit% + context%）；

`render-loop.mjs:89-90` 与 `status-line.mjs:139-143`（context% 分子 = `estimateTokens(agent.history)`，估算）；`slash-commands.mjs:44-106`（**无 `/usage` 命令**）；
core 无价目表（全仓唯一 `cost` 是 web-deepseek 的按次计费常量 `tools/web-deepseek.mjs:29`）。

ACP v1 schema：`UsageUpdate.required = ["used","size"]`，`cost?: Cost{amount,currency}`「Cumulative session cost」（可选）。
结论：token 合计可从 `usage_update` 精确累计（与终端同源）；上下文占用沿用最新快照；成本无来源。

### 23.1 做法：两条累计 ∥ 三个落点

```text
CLI onUsage（每 LLM 请求一次）→ usage_update {used, size}
  ▼ ThincoderEvents._usage
  ├─ 回合累计 _turnSpent += used ──► _endTurn ⇒ TurnEnded.usage = TurnUsage(spentTokens)
  │                                    ⇒ turn footer「N tokens」（回合用量）
  ├─ 会话累计 _spent += used ──────► ContextUsage.sessionSpent
  │                                    ⇒ ContextUsagePanel 新增「本会话累计」一行
  └─ 快照（今天）used / size ───────► UsageReported(ContextUsage)（上下文占用，F10 不变）
```

- 回合边界 = `_beginTurn`（`thincoder_kernel.dart:646-652` 的 `_events.begin()` 处清 `_turnSpent`）；回合收尾 = `_endTurn`（`:694-712`）填 `TurnEnded.usage`。
- 回合外的 `usage_update`（无在飞回合）只进会话累计（不回填任何回合）。
- **无提示轮的口径**：自动轮自成回合（§19.2 表 `start`（无在飞回合）行：`_beginTurn('auto:<n>', unprompted: true)`）⇒ 其 `usage_update` 计入**自己的** `TurnEnded.usage`（`_beginTurn` 已清 `_turnSpent`）。
  D62 的撤暂存轮在桌面不成轮（§19.2 表 `end`（暂存位非空）行）⇒ 该轮用量落在在飞用户回合内、并进该回合的 `_turnSpent`（不另开回合、不回填已收回合）。
  用例：**不补**——两条边由既有回合边界决定，T96 / T98 已覆盖「回合内 / 回合外」；走查见归属错误 ⇒ 补 T99（自动轮自成回合 ∥ 撤暂存轮并入在飞回合各一条）。
- `speed` 保持缺省（不伪造：桌面只有字符数增量、非 token；Claude 的 `tokensPerSecond` 来自其 CLI 结果面）。
- 面板显示：会话累计行（`_format` 同源，`context_usage_panel.dart:44-48`）；无 `sessionSpent`（Claude 等）⇒ 不显示（负向锁：零字节注入）。`ContextUsage` 其它构造点（`chat_session.dart:516`、`mock_conversation.dart:10`）零改（缺省 null）。

### 23.2 契约（数据形）

```dart
class TurnUsage {                      // lib/chat/chat_models.dart:133-159
  const TurnUsage({..., this.spentTokens});
  final int? spentTokens;              // 本回合 input+output 合计（内核只报合计时）
  int? get totalTokens => spentTokens ?? ((inputTokens == null && outputTokens == null)
      ? null : (inputTokens ?? 0) + (outputTokens ?? 0));
}

class ContextUsage {                   // lib/kernel/kernel_types.dart:126-140
  const ContextUsage({required this.window, required this.used,
                      this.segments = const [], this.sessionSpent});
  final int? sessionSpent;             // 本会话累计 token（同一来源的逐请求 used 之和）
}
```

- `usage_update.used` 语义（逐字对 CLI）：`used = prompt_tokens + completion_tokens`（该次请求）；合计 = 各条之和——**不重算**、不拆分（拆分行只有终端面有，ACP 线上无）。
- `size` = 上下文窗口（CLI 侧 `providerSpec.context`，随模型切换变）；桌面不猜窗口。
- 会话累计 = 随聊天会话存活：同一内核实例（一次聊天会话）内收到的全部 `usage_update.used` 之和（与终端 `state.tokens` 同源）；`restart()` / release 后重新 attach 不清零（`_spent` 只在内核构造时置 0，`thincoder_events.dart:45`）；新建聊天会话（新内核实例）从 0 起（终端进程重开同形：`tui-state.mjs:38` 初始化 0）。
- `cost` 不读（CLI 不发；§14-25）。

### 23.3 受影响文件清单与 `thincoder_events.dart` 拆分方案（E2 增量；行数 = 批 11 编制日（2026-10-19）快照——勿与 §24.3 的现值互校）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_events.dart`（799） | `_usage` 累加 `_spent` / `_turnSpent`；`begin()` 清 `_turnSpent`；`ContextUsage(sessionSpent:)`；`int get turnSpent` | ≤ +8（⇒ ≤807；入 >800 名单，见下） |
| ② | `lib/kernel/thincoder/thincoder_kernel.dart`（1055） | `_endTurn` 带 `usage: TurnUsage(spentTokens: _events.turnSpent)`（无用量 ⇒ null） | ≤ +6（⇒ ≤1091；与 §22.3 合计 ≤ +36） |
| ③ | `lib/kernel/kernel_types.dart`（610） | `ContextUsage.sessionSpent`（可选） | ≤ +4（⇒ ≤614） |
| ④ | `lib/chat/chat_models.dart`（806） | `TurnUsage.spentTokens` + `totalTokens` 取值 + 文档 | ≤ +8（⇒ ≤814；>800 名单，行级） |
| ⑤ | `lib/chat/widgets/turn_footer.dart`（348） | `_stats`：spent 无拆分时换新 hint 键 | ≤ +6（⇒ ≤354） |
| ⑥ | `lib/chat/panels/context_usage_panel.dart`（530） | 会话累计行（有值才显示） | ≤ +14（⇒ ≤544） |
| ⑦ | `lib/l10n/app_en.arb`（7026）· `app_zh.arb`（2703） | 2 键：`turnTokensSpentHint` / `usageSessionTotal`；生成档与两源档同拍（无 SDK ⇒ 手改，保持 `test/l10n_test.dart` 绿；§18.8 / 登记 §14-27） | 各 +2（⇒ 7028 / 2705） |
| ⑧ | `test/kernel/thincoder_kernel_test.dart`（3395） | T96–T98（§23.6） | ≤ +90（⇒ ≤3485；与 §22.3 合计 ≤ +253 ⇒ ≤3648） |

- **体量**：`thincoder_events.dart` 799 → ≤807 进入 >800 名单（缝候选 / 触发见 §5.2；拆分方案见下）；`chat_models.dart`（806）已在名单（§5.2），本批行级新增。
- **>500 层**：`kernel_types.dart`（610 → ≤614）· `context_usage_panel.dart`（530 → ≤544）在 >500 且 <800 区间——体量立场只跟 >800（§5.2 末段），不立缝。

**`thincoder_events.dart` 拆分方案（硬要求：拆后 ≤800；批 11 后 ≤807；先例形同 §21.3）**

| 步 | 动作 | 迁移面 | 行数 |
|---|---|---|---|
| 1 | 新档 `thincoder_agents.dart`，以 `part of 'thincoder_events.dart'` 接入 | 子代理段：段头 `:436` 起的子代理卡片 / 报告翻译；`_putSubagent` / `_card` 的调用点在 `:682` / `:741`，**不随迁**（段界由拆分批按段头 / 段尾注释勘定） | −N（拆分批实测；判据 N ≥ 32） |
| 2 | 拆后核读 | 两档 `wc -l` 实测：`thincoder_events.dart` ≤ 775（807 − 32；留 ≥25 行余量）；新档 < 300 | ✅ |
| — | **预算** | 判据 = 拆后 `thincoder_events.dart` ≤ 775；子代理段实测 < 32 行 ⇒ 缝沿段界向相邻段扩（段界重勘，仍以 ≤775 收束） | |

- 排期 = 独立拆分批（本批只行级 +8、不动结构）；拆分批开工时按实测段界核 N，结论回灌本节与 §5.2。
- **零改动**：`UsageReported` 事件与 `transcript.dart`（快照语义不变）· Claude / Codex 内核（`TurnUsage` 新字段缺省向后兼容）· 固件（`usage_update` 帧形不变）· `chat_session.dart`。

### 23.4 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D87 | 回合用量 = 本回合各条 `usage_update.used` 之和；会话累计 = 全会话之和 | 需求验收「会话级累计 = 各回合之和」；`used` = 该请求 prompt+completion（CLI 定义，`bridge.mjs:254-259`），求和即消耗合计 = 终端状态行 ↑+↓ 同源。被否：取回合最后一条 `used`（那是上下文快照、不是消耗，且与「累计 = 之和」矛盾） |
| D88 | 会话累计挂 `ContextUsage.sessionSpent`，不新增事件 / 接口 | 面板已有 `ContextUsage` 与 `stats` 两条数据路；加字段零新机制、Claude 面零影响（缺省 null）。被否：实现 `ReportsUsage`（`accountLimits` / `refreshUsage` 对 thincoder 是假面，E3）；被否：新事件 `SessionUsageReported`（宿主与翻译面双改，E2 违规） |
| D89 | 成本本批不做（无来源）；登记判定条件 | CLI 不上报 `cost`（`bridge.mjs:258-261` 只发 used/size），core 无价目表 ⇒ 桌面要显示只能自建价目表 = 重算（违「口径 = CLI 上报值，不重算」+ B3 不代管账号 / 账单用量）。被否：桌面按 provider 价目表估算（第二判据源） |
| D90 | 「与终端同口径」= 同一 `onUsage` 来源的 token 合计；context% 不作对照 | 终端 context% = `estimateTokens(history)` 估算（`render-loop.mjs:89-90`）、非 CLI 上报值；终端也无 `/usage` 命令 ⇒ 对照面 = 状态行累计 ↑+↓（同源）。被否：把 context% 差异当缺陷（不同仪器） |

### 23.5 验收对照（回指需求档 F20）

| 需求条目（F20） | 本档落点 | 判据（机检 / 走查） |
|---|---|---|
| 多回合 ⇒ 会话级累计 = 各回合之和 | §23.1 / §23.2 | T96：两回合 4 条 usage_update（100 / 50 + 70）⇒ 回合 150 / 70、`sessionSpent = 220`；面板显示 220 |
| 上下文占用随 `usage_update` 更新 | §23.1 快照路 | T97：最新一条 `used/size` 进 `ContextUsage`（今天形，F10 不回归） |
| 同一会话与终端读数一致（口径 = CLI 上报值，不重算） | §23.4 D90 | 走查 4：**逐回合 delta** 对照——同一批 turn 前（起算点）后各记一次终端状态行 ↑+↓，差值 == 桌面该批回合 footer 之和；两进程各持自己的累计（§23.2：累计随聊天会话存活，新建会话归零）⇒ 「一致」= 同源同算法，不是同数值；T96 = 机检侧（同源求和） |
| 按回合 token 可见 | §23.1 turn footer | T96：两回合 footer 各显示 150 / 70（`TurnUsage.spentTokens`） |
| 成本 / 上下文占用展示 | §23.4 D89 / F10 既有 | 成本本批不做（登记 §14-25）；上下文占用 = 既有面板（T97） |

### 23.6 用例表（T96–T98，`test/kernel/thincoder_kernel_test.dart`）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T96 | 两回合累计 | 回合 1 推两条 `usage_update`（used 100 / size 1000；used 50）⇒ `end_turn`；回合 2 推一条（used 70）⇒ `end_turn` | `TurnEnded` 的 `usage?.spentTokens` 序列 == `[150, 70]`；`UsageReported` 最后一条 `ContextUsage.sessionSpent == 220`、`window == 1000` |
| T97 | 快照语义不回归 | 单回合两条 usage_update（used 900 → 950，size 1000） | 最新 `ContextUsage.used == 950`、`window == 1000`；`sessionSpent == 1850`（两条之和） |
| T98 | 回合外用量 | 无在飞回合时推一条 used 30；再起回合推 used 20 ⇒ 收尾 | 会话累计 50；该回合 spent == 20（回合外的不回填） |

- 断言面：按既有测试手段（`_Session` / mock 直驱）取 `TurnEnded` 与 `UsageReported` 事件逐值断言；不新增固件（`usage_update` 帧形不变）。

### 23.7 边界（本批不做）与登记（判定条件）

1. **不做账号 / 账单用量**（B3，需求边界）。
2. **不改 CLI 的 usage 计算**（需求边界）：桌面只消费 `usage_update`。
3. **不做跨会话历史统计**（需求边界）：会话累计只随聊天会话存活，新建聊天会话从 0 起。
4. **成本不做**：§14-25。
5. **拆分行 input / output 不做**：ACP 线上只有合计（`used`）；终端的拆分来自 TUI 自己的 `onUsage` 字段（`prompt_tokens` / `completion_tokens`），ACP 未携。
6. **缓存命中 / 推理 token 不做**：同上，ACP 未携。
7. **重放不带 usage、重连不清零**：`session/load` 重放不带 usage；`restart()` / release 后重新 attach 不清会话累计（随聊天会话存活，`thincoder_events.dart:45`）；新建聊天会话（新内核实例）从 0 起。判定条件：产品要求跨聊天会话延续累计（桌面重启后仍接续）⇒ CLI 侧给会话级累计帧或重放 usage（另立）。

### 23.8 真机走查步骤

1. 新建 thincoder 会话，发两轮消息（每轮含工具调用，触发多次 LLM 请求）。
2. 每轮结束看 turn footer：出现「N tokens」（无 speed / cost）——N = 该轮请求的 `used` 之和。
3. 打开上下文面板：上下文占用随最新 `usage_update` 变；「本会话累计」= 各回合 footer 之和。
4. 同一会话在终端发两轮：**记起算点**（发前）与收尾（发后）的状态行 ↑prompt ↓completion，差值 == 桌面这两轮 footer 之和——逐回合 delta 对照（两进程各持自己的累计，不要求总量相等；口径 = CLI 上报值）。
5. 切模型（上下文窗口变）⇒ 面板 window 随 `size` 变（今天形）；累计不跳。

## 24. 模型切换后置应用（批 14；F5 具体化）

> 回指：需求档 F21（F5 的模型面具体化）——回合在飞时切换不丢，回合结束自动应用；显示以 thincoder 回报为准，不乐观假报。
> 一句结论：**客户端后置应用**。回合在飞（`_turn != null`）/ 暂存自动轮在 / 上一条写未答时点模型只记目标（last-wins；回合在飞时等待态可见）；回合收尾（`_endTurn`，且无暂存自动轮、无在飞写）在下一趟 prompt 之前重发 `session/set_config_option(model)`：成功 ⇒ 以回报换成新模型；失败 ⇒ 界面仍是旧模型 + 会话内一条可见 error。**CLI 零改**——入站 FIFO 是既有协议语义（`transport.mjs:13-19`），发送时机归客户端。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：显示只认回报（D20 / F5）——`model` 的 `selected` 读 `_events.selected('model')`（`thincoder_choices.dart:46-51`）；本批不改这条判据，等待目标只是附加状态。
- 对齐 ②：写路径与失败留痕复用既有 `_config` 的请求形与 `appEvent` 留痕（`thincoder_choices.dart:119-139`）。
- 对齐 ③：后置动作挂在 `_endTurn` 的收尾链——先例 = 批 7 的 `_drain()` 排水（§18.1）与批 8 的暂存自动轮（§19.2）；一处收尾覆盖完成 / 取消 / 错误三条结束路。
- 对齐 ④：可见状态住既有模型 pill 的 label 位（`session_model_picker.dart:44-58`）与既有 `tooltip`——不新增控件 / 弹窗。
- 偏离 ①：等待目标不显示成「已生效」——pill 主 label 仍是回报的模型（D20）。被否：把等待目标当 `selected`（失败要回滚，且等于先假装成功）。
- 偏离 ②：不改 CLI 的豁免表——把 `model` 放行会让写落在在飞回合里、改变该回合用的模型，语义未定；客户端等收尾再发，FIFO 自然不拦。被否：把 `model` 加进 `isInboundExempt`（CLI 行为变更，且回合内切换另立）。

**survey 证据**：外仓 `thincoder-cli/src/acp/transport.mjs:13-19` / `:31-40` / `:91-126`——入站 FIFO 串行；

豁免集 = `session/cancel` / `session/close` / `session/list` + `configId === "autoApprove"`；注释逐字「Every other configId (model / mode / thinkingLevel / …) stays queued」。
`handlers-session.mjs:425-452`：handler 同步、纯内存（`applyConfigOption`）；成功既回全量 `configOptions`，又派发 `config_option_update`（`:447-450`）。

本仓 `thincoder_protocol.dart:59-119`：连接缺省超时 60s；`session/prompt` 走 `noTimeout`，其余请求照缺省。

实测（2026-10-19 03:09，`events.log`）：回合在飞时点模型 ⇒ 写排在 prompt 之后、超 60s 被桌面丢弃（`-32603 … got no answer`）；1.1s 后迟到应答到（`an answer to no request of ours: id c6`）——CLI 在回合收尾时确实执行了那次写，同拍 `config_option_update` 也已发出；桌面显示会因此自愈，但切换时机不受用户掌握，超时窗口内也无任何可见状态。

ACP v1 schema：`session/set_config_option` 请求 `{sessionId, configId, value}`、响应 `{configOptions}`；`ConfigOptionUpdate` = 全量 `configOptions`（§3.4 已列）。

外仓设计档 `thincoder/docs/cli/design/ACP-CLIENT.md` §5.3（`:302-313` configOption 映射：`model` = 运行期清单投影 + last-write-wins 于内部状态）与 §3.1（`:92-103` FIFO 豁免判据 = 只有 `autoApprove`、其余 configId 留队）——相关且同向：本批的 last-wins / 后置应用跟 §5.3 同口径；§3.1 确认 `model` 不在豁免内（与 §24 的「CLI 零改」一致）。

结论：症结在发送时机，不在协议；客户端在回合收尾后重发 = 队列空闲时的一次普通写。

### 24.1 状态机与触发点

```text
点模型（ThincoderKernel.model.select）
  ▼ _selectModelOf(kernel, id)
  ├─ 同值且无待应用目标（id == selected('model') && _modelTarget == null）
  │     ⇒ 直接返回（不置目标、不发；旧 CLI 单项清单点它 = 这条）
  ├─ 等待态下点已生效模型（_modelDeferred && id == selected('model')）
  │     ⇒ _modelTarget = null + _modelDeferred = false + emitInfoChanged（取消等待，不发）
  ├─ 回合在飞（_turn != null）∥ 暂存自动轮在（_pendingAuto != null）
  │     ⇒ _modelTarget = id + _modelDeferred = true（last-wins）+ emitInfoChanged（pill 后缀可见；不发）
  ├─ 发送中（_modelSending）
  │     ⇒ _modelTarget = id（last-wins；不新发——在飞那条应答回来后再发）
  └─ 空闲
        ⇒ _modelTarget = id; _modelDeferred = false; _modelSending = true
              ▼ session/set_config_option {sessionId, configId:"model", value:id}
              ├─ 应答（全量 configOptions）⇒ _events.optionsFrom(应答) ⇒ 新模型
              ├─ 同拍 config_option_update ⇒ _events.optionsFrom（同源，幂等）
              └─ 错误 ∥ 60s 超时 ⇒ NoticeItem(error)（旧模型保持）+ appEvent 一行
              ▼ 应答 / 错误落地：_modelSending = false；目标已换（_modelTarget != 刚落地的值）⇒ 再发一次（last-wins）
```

| 态 | 进入 | `_modelTarget` | `_modelDeferred` | pill |
|---|---|---|---|---|
| 空闲 | 初始 / 成功 / 失败收束 / 同值早退 / `dispose` / `_teardown` | null | false | 回报的模型 |
| 等待回合 | 回合在飞或暂存自动轮在时点模型（再点覆盖；点已生效模型 = 取消） | 目标 id | true | 主 label + 「回合结束后切换到 <目标>」 |
| 发送中 | 空闲点选 ∥ 回合收尾触发 ∥ 发送中再点（只记目标） | 目标 id（到应答） | false | 主 label（应答到即换） |

触发点：

1. **回合收尾**：`_endTurn`（`thincoder_kernel.dart:745-780`）在 `_pendingAuto` 分支之前（`:768`；pump 自带 `_pendingAuto != null` 守卫，行为等价）、`_drain()` 之前（`:778`）调 `_pumpModelOf`（`_modelDeferred = false`、`_modelSending = true`）。线的顺序 = CLI 的入站顺序：配置行先写、下一趟 prompt 后写 ⇒ 下一回合起就用新模型。
2. **空闲点选**：直接走同一 pump（今天的行为，只是同一条路径）。
3. **应答落地时目标已换**：再发一次（last-wins 的兑现点；发送中再点就靠这条兑现）。

- 发送前置判据：`_turn == null && _pendingAuto == null && !_modelSending && !_releaseWanted`；不满足 ⇒ 只记目标（不新发）。`_pendingAuto` 非空时 `_endTurn` 先起自动轮、本轮不发；自动轮收尾再走同一触发。视图离开（`_releaseWanted`，`release()` 置位）⇒ 不补发：目标随收尾的 `_teardown` 清，与 §24.7-4 同口径（`thincoder_choices.dart:82-83`）。
- 发送位一次只有一条：`_modelSending` 在写发出时置真、应答 / 错误落地时置假。发送中再点只改 `_modelTarget`，由应答落地后的 last-wins 兑现（不叠第二条写；§24.6 T101②）。
- 同值早退：`id == _events.selected('model')` 且 `_modelTarget == null` ⇒ 不置目标、不发（旧 CLI 单项清单点当前项 = 这条；§24.6 T105）。
- 等待态下点**已生效**的模型（`_modelDeferred && id == selected('model')`）⇒ 清目标、不发（取消等待；`_Choice` 对 model 用 `always` 放开「同值不回调」的短路，让这次点击到达本判据）。
- 错误落地：`_modelSending = false`；清目标（含发送中记下的后点目标）+ 一条 error；不自动重试 ⇒ 后点目标要再生效须用户再点（D98 同口径）。
- 会话不在（`_connection == null || _slot == null`）⇒ 清目标、不发（今天 `_config` 的静默返回；等待态不留在无会话处）。
- `_teardown()` / `dispose()` ⇒ 清 `_modelTarget` / `_modelDeferred` / `_modelSending`（会话切换 / 关窗；§24.7-4）。
- 应答落地前校验连接身份（`identical(connection, _connection)`）：teardown 后到的应答不落状态、不发 error。

### 24.2 契约

```dart
/// lib/kernel/agent_kernel.dart：选模型时回合在飞、切换留到回合结束的内核。
abstract interface class DefersModelSwitch {
  /// 回合在飞时点下的模型，尚未生效；null = 无等待。
  String? get pendingModel;
}
```

- `ThincoderKernel` 增 `implements DefersModelSwitch`；getter = `_modelDeferred ? _modelTarget : null`（发送中不显示等待标记；应答到即按回报换模型）。
- 宿主投影（`lib/chat/chat_session.dart`）：

```dart
/// 回合在飞时点下、等回合结束生效的模型；null = 无。
String? get pendingModel => switch (_kernel) {
  final DefersModelSwitch kernel => kernel.pendingModel,
  _ => null,
};
```

- 可见文案（`lib/chat/composer/session_model_picker.dart`）：pill 的 label = 既有 `_label(...)` + `' · '` + `l10n.modelsSwitchPending(targetLabel)`；tooltip 有等待态时追加同句。目标 label 按 id 在 `model.options` 里取，取不到回落 id。
- 新 l10n 键（两源档 + 生成档）：

| 键 | en | zh |
|---|---|---|
| `modelsSwitchPending`（占位 `{model}`） | `Switches to {model} when this turn ends` | `回合结束后切换到 {model}` |

- 超时 = 连接缺省 **60s**（不新设常量）。判据：发送点只在「桌面无在飞回合、无暂存自动轮、无在飞写」（§24.1），CLI 入站链此时空闲、handler 同步纯内存（`handlers-session.mjs:426-451`）⇒ 正常一趟往返即答（毫秒级）；60s 只兜病理竞态（CLI 侧自动轮在帧与写之间起跑 ∥ 子代理消化轮占队列）。
  兜底：超时 / 错误 ⇒ 目标清空 + 一条 error notice；显示保持最后一次回报（从未乐观改过，无可回滚）。若 CLI 迟到执行并发出 `config_option_update`，通知照常应用（`thincoder_protocol.dart:124-134` 按方法分流、不配对我方请求 id）⇒ 显示自愈；error 文案只说「未确认」，不说「未生效」。**不自动重试**（同一竞态下重试只会再等一次 60s；用户可再点）。
- 失败文案 = 内核口英文、带原始错误（形同 `thincoder stopped unexpectedly`；登记 §14-28）；等待态文案是宿主文案 ⇒ 走 l10n。

### 24.3 受影响文件清单（E2 增量；行数 = 2026-10-19 实测）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_kernel.dart`（1091） | `implements DefersModelSwitch` + `pendingModel` getter；字段 `_modelTarget` / `_modelDeferred` / `_modelSending`；`model` 委托改 `_selectModelOf`；`_endTurn` 触发一行；`dispose` / `_teardown` 各清三字段 | ≤ +24（⇒ ≤1115；§21.3 预算 ≤1148，余量 33） |
| ② | `lib/kernel/thincoder/thincoder_choices.dart`（203） | `_Choice` 加 `always`（model 用）；`_modelOf.select` 改 `_selectModelOf`；新增 `_selectModelOf` / `_pumpModelOf`（状态机 + 同值早退 + 发送位 + last-wins 重发） | ≤ +70（⇒ ≤273；实交 273 = +70，来源 = 状态机 / pump / `always`；<500，不立缝） |
| ③ | `lib/kernel/agent_kernel.dart`（472） | 新增 `DefersModelSwitch` 接口（文档 + getter） | ≤ +10（⇒ ≤482） |
| ④ | `lib/chat/chat_session.dart`（1215） | `pendingModel` 投影（switch on interface） | ≤ +8（⇒ ≤1223；>800 名单，行级） |
| ⑤ | `lib/chat/composer/session_model_picker.dart`（170） | label 后缀 + tooltip 追加 + 目标 label 查找 | ≤ +18（⇒ ≤188） |
| ⑥ | `lib/l10n/app_en.arb`（7133）· `app_zh.arb`（2748） | 1 键 `modelsSwitchPending`（en 带 `@` 元数据与占位声明；zh 只值） | en +7 / zh +1 |
| ⑦ | `lib/l10n/app_localizations.dart`（16563）· `_en`（10120）· `_zh`（9569） | 生成档：抽象 getter + 两实现；无 SDK ⇒ ARB 与生成档同拍手改、保持 `test/l10n_test.dart` 绿，SDK 就位轮 `flutter gen-l10n` 重产（§18.8；登记 §14-14 / §14-24 / §14-27） | 各 +3 |
| ⑧ | `test/kernel/thincoder_kernel_test.dart`（3644） | T100–T105（§24.6）；mock 零改（既有 `hold` / `configError` / `models` 够用） | ≤ +215（⇒ ≤3859；>800 名单，只加用例） |
| ⑨ | `test/chat/pending_model_test.dart`（新增） | T106 宿主投影（`ChatSession.pendingModel`）：假内核 `implements AgentKernel, DefersModelSwitch` | ~ +60（新档，<300） |

> 行数复核口径：① 的 1091 为本批（批 14）编制日起点（2026-10-19 实测），与 §5.2 体量行的现值 1121 差 30 行（两批各记了当时的实测）——**实施首轮 `wc -l` 复核，以复核值为准**。

- **零改动**：`thincoder_protocol.dart` · `thincoder_events.dart`（`optionsFrom` / `selected` 已是通用读面）· `thincoder_mock.dart` · Claude / Codex 内核 · 固件（无新帧）· `thincoder/`（CLI 零改）。
- **体量**：`thincoder_choices.dart`（203 → ≤273）· `agent_kernel.dart`（472 → ≤482）· `session_model_picker.dart`（170 → ≤188）均 <500；`thincoder_kernel.dart` 在 >800 名单（§5.2 体量立场 = 不续拆），本批 +≤24 后 ≤1115 < 1148；`chat_session.dart` / 测试档在 >800 名单，本批只行级新增 / 加用例，不动结构。

### 24.4 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D95 | 客户端后置应用；CLI 的 FIFO 与豁免表零改 | 回合在飞时写会排在 prompt 之后（`transport.mjs:91-126`），没有有界应答；桌面知道回合何时结束（`_endTurn` 覆盖三条结束路）⇒ 时机是本端的事。被否：把 `model` 加进豁免表（回合内切换的模型归属未定，且改 CLI 违 B1 默认）；被否：放大 60s（回合时长无上界，切换落在不确定时刻且仍无可见状态） |
| D96 | 触发 = `_endTurn` 收尾、`_pendingAuto == null`、`_modelSending == false`、`_drain()` 之前 | 线的顺序 = CLI 的入站顺序：配置先于下一趟 prompt ⇒ 下一回合就用新模型；有暂存自动轮时先让它收尾，否则配置排在它后面。被否：`_drain()` 之后发（配置排在下一趟 prompt 后，切换推迟到再下一回合）；被否：起下一回合时发（同一问题） |
| D97 | 可见状态 = 模型 pill 的 label 后缀 + tooltip；等待目标不进 `selected` | 显示只认回报（F5 / D20）：把目标当已生效，失败就得回滚，且等于先假装成功。pill 是用户点选发生处，状态放这里不新增控件（§24.9）。被否：菜单里给等待目标打勾（假报）；被否：弹窗 / toast（本应用没有这种面，且打断无关） |
| D98 | 重发沿用连接缺省 60s；失败 = error notice + 保持旧模型；不自动重试 | 正常路径队列空闲、handler 同步纯内存 ⇒ 毫秒级应答；60s 只兜病理竞态。超时后若 CLI 迟到执行，`config_option_update` 让显示自愈 ⇒ 文案只说「未确认」。自动重试在同一竞态下只会再等一次 60s。被否：缩短到 10s（新常量无证据，病理竞态下更易误报）；被否：`noTimeout`（写卡住会永久占住发送位） |
| D99 | 状态住内核（`_modelTarget` / `_modelDeferred` / `_modelSending`），宿主只读投影 | 「回合在飞 / 暂存自动轮 / 连接在」全在内核；宿主按 `isStreaming` 轮询再补发会与自动轮、队列、teardown 竞态。被否：宿主定时器（重复判定 + 时序不可测） |

### 24.5 验收对照（回指需求档 F21 + 本批三条）

| 需求条目 | 本档落点 | 判据（机检 / 走查） |
|---|---|---|
| 回合在飞时点模型 ⇒ 记下目标，回合收尾自动重发并生效 | §24.1 / §24.2 | T100：在飞期间零 `set_config_option`；`pendingModel == 目标`；收尾后恰 1 条，`params = {sessionId, configId:"model", value:目标}`；`kernel.model.selected == 目标` |
| 等待期间二次改选 ⇒ last-wins | §24.1 触发点 3 | T101：① 等待态连点两个模型 ⇒ 收尾后只 1 条（后点目标）；② 发送中再点另一个 ⇒ 首条应答落地前零新增写、落地后恰再 1 条（value = 后点） |
| 失败 / 被丢弃不得假装成功：显示仍是旧模型 + 一条可见错误 | §24.1 失败面 / D98 | T102：`configError` ⇒ `selected` 仍是旧模型；恰 1 条 `NoticeItem(error)`；`pendingModel == null`；health ready |
| （派生）会话切换 / 关窗 ⇒ 清等待，不把 A 的模型设到 B | §24.1 / §24.7-4 | T103：① `dispose()` ⇒ `pendingModel == null`、放行后零写；② 视图离开 ⇒ `kernel.release()` ⇒ 收尾 teardown ⇒ 零补发、无 error |
| （派生）可见状态 = pill 后缀「回合结束后切换到 <目标>」 | §24.2 / §24.9 | 走查 2（label + tooltip）；T104 键面哨兵（两源档含 `modelsSwitchPending`）；T106 宿主投影（等待态非空 / 收尾归空 / 非接口内核恒 null） |
| （派生）旧 CLI 兼容：行为不变 | §24.1 同值早退 | T105：单项清单（`models` 未给 ⇒ 只有当前项）点它 ⇒ `requests('session/set_config_option')` 为空、无 notice；有清单的旧 CLI 走同一路径（不加版本门） |

### 24.6 用例表（T100–T106；T100–T105 = `test/kernel/thincoder_kernel_test.dart`，T106 = `test/chat/pending_model_test.dart`）

T99 已被 §23.1 预留给用量归属的补项（自动轮 ∥ 撤暂存轮），本批从 T100 起编号。

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T100 | 回合在飞时点模型 ⇒ 收尾重发 | `ThincoderMock(models: ['anthropic:claude-sonnet-5','b'])`；`hold = Completer()`；`send('go')`；点 `b` | 在飞期间 `requests('session/set_config_option')` 为空；`kernel.pendingModel == 'b'`；`kernel.model.selected` 仍是缺省模型；`agent.release()` 后 settle ⇒ 恰 1 条写，`params == {sessionId:'1', configId:'model', value:'b'}`；`selected == 'b'`；`pendingModel == null` |
| T101 | last-wins（① 等待态改选 ② 发送中改选） | ① `models: [缺省,'b','c']`；在飞点 `b` 再点 `c`；`agent.release()` 收尾。② 同清单；空闲点 `b`（写 1 在飞）⇒ 同拍再点 `c` | ① 收尾后只 1 条写，value = `'c'`；`selected == 'c'`。② 首条应答落地前仍只 1 条写（value `'b'`）；落地后恰再 1 条（value `'c'`），总计 2 条；`selected == 'c'`；`pendingModel == null` |
| T102 | 失败回显 + 可见错误 | `ThincoderMock(models: [缺省,'b'], configError: true)`；在飞点 `b`；收尾 | `selected` 仍是缺省；`pendingModel == null`；恰 1 条 error `NoticeItem`；health ready |
| T103 | 会话离开清等待 | ① 在飞点 `b` ⇒ `kernel.dispose()` ⇒ `agent.release()`。② 在飞点 `b` ⇒ `kernel.release()`（视图离开）⇒ `agent.release()` 放行回合 ⇒ 一个 macrotask | ① `pendingModel == null`；`requests('session/set_config_option')` 为空（放行后也不补发）。② `pendingModel == null`；`requests('session/set_config_option')` 为空；无 error `NoticeItem`（丢弃时可见面为零，§24.7-4） |
| T104 | l10n 键在两源档 | 读 `lib/l10n/app_en.arb` / `app_zh.arb` | 两档都含 `"modelsSwitchPending"`；zh 值含 `{model}`（形同 T82 的 ARB 直读） |
| T105 | 同值点击零写（旧 CLI 单项清单） | `ThincoderMock()`（`models` 未给 ⇒ 清单只有当前项 `anthropic:claude-sonnet-5`）⇒ 点它 | `requests('session/set_config_option')` 为空；`pendingModel == null`；无 `NoticeItem` |
| T106 | 宿主投影（`ChatSession.pendingModel`） | 测试档自建 descriptor：假内核 `implements AgentKernel, DefersModelSwitch`，`pendingModel` 先 `'b'` 再 `null`；另一内核不实现该接口 | 等待态 ⇒ `session.pendingModel == 'b'`；归空（收尾）⇒ `null`；非 `DefersModelSwitch` ⇒ 恒 `null`（负向锁）。投影只测投影——内核状态机 = T100–T103 |

- 不加固件：线形是既有 `session/set_config_option`，无新帧；既有固件保持绿 = 回归哨兵。
- 断言面：`_Session` 直驱内核（`events` / `items<NoticeItem>()` / `agent.requests(...)` / `kernel.pendingModel`），与 T51 / T63 同手段；T106 用 `ChatSession(kernel: descriptor)` + 假内核（形同 `turn_marks_test.dart` 的 `_Kernel`）。

### 24.7 边界（本批不做）与登记（判定条件）

1. **不改 CLI**：`transport.mjs` 的 FIFO / 豁免表零改；`thincoder/` 零改动（B1 默认）。
2. **只对 thincoder 内核的 `model`**：Claude 的 `ConfirmsModelSwitch`（切 provider 重启对话）语义不变；不扩大到 provider 切换后置。
3. **不做回合内生效**：在飞回合用旧模型跑完；目标从收尾后的下一回合起生效。
4. **不持久化等待态**：`dispose()` / `_teardown()` 即清；关窗 / 切会话 / 进程重启后不补发（不得把 A 会话的模型设到 B）。
   视图离开的退径同这条：视图离开 ⇒ `release()`（`thincoder_kernel.dart:493-504` 置 `_releaseWanted`）⇒ 回合收尾后一个 macrotask ⇒ `_closeSession()` + `_teardown()`（`:518-534`；

`_canClose`（`:508-512`）不计等待目标）⇒ 等待目标随 `_teardown` 清。
   若收尾那次写已在飞，其应答被连接身份校验丢弃（§24.1 末条）⇒ **用户可见面为零**（无 error、无 notice；pill 随视图一起消失）。
   不把 `_canClose` 绑到等待目标：写卡住时会把关窗拖到 60s 超时，与「等待态不持久」相抵。判定条件：视图离开后重开同一会话仍见等待态 ⇒ 该路径没清。
5. **不自动重试、不缩短超时**：见 D98。判定条件：现场见到收尾后一次写仍 60s 未答 ⇒ 取 `events.log` 与 CLI 侧 `agent.busy` 时序；确属队列竞态 ⇒ 评估收尾后延迟一个 macrotask 再发（本批不做）。
6. **不做「模型不支持视觉」的桌面判据**：非视觉模型的降级在 CLI（`stripImagesForTextModel`，§22.7-5）；本批只保证切换不丢。
7. **不改 `mode` / `thinking` 的写路径**：同一条 FIFO 语义同样适用，但本批只修用户报告的那一项。判定条件：现场见到 `mode` / `thinking` 在飞时切换被丢 ⇒ 按 §24.1 同一状态机扩 configId（另立）。

### 24.8 真机走查步骤

1. thincoder 会话，选一个**能看图**的模型（F19 原生链路已在）；发一条会跑一阵的消息（带工具调用 ∥ 长任务）。
2. 回合在飞时点另一个模型 ⇒ pill 仍显示旧模型 + 「回合结束后切换到 <目标>」；tooltip 同句；菜单里旧模型仍是勾选态；无弹窗。
3. 回合收尾 ⇒ pill 换成新模型；`events.log` 无 `set_config_option(model) failed`；此后第一条 `session/prompt` 已用新模型（终端同槽 `/model` 同值）。
4. 在飞时连点两个模型 ⇒ 只有后点那个生效（日志一条写）。
5. 切到视觉模型后发一张图 ⇒ 模型能看图（判据同 §22.8）；若切到非视觉模型发图 ⇒ CLI 的 `[image omitted — …]` 表现，不是「not support」崩溃。
6. 旧 CLI（模型清单只有当前一项）⇒ 点它零写、零报错（同值早退）。
7. 失败面不做真机（UI 构不出被拒的 model 值）；判据 = T102。

### 24.9 UI / 交互决定（全部落地，无 open）

- 位置 = 既有模型 pill（composer 左簇；plan 起始选择器同一组件）——不新增控件、不新增弹窗。
- 等待态 = pill label 追加 ` · 回合结束后切换到 <目标>`；tooltip 追加同句（原 tooltip = 「选择模型 (⌘.)」）。
- 主 label 仍是**已生效**模型（D20）；菜单勾选仍按回报（等待目标不勾选）。
- 点已生效模型 = 取消等待（有等待态时后缀随即消失）；无等待时点它 = 零写零反馈（§24.1 同值早退）。
- 失败 = 会话内既有 error notice（`NoticeRow` 的 error 样式），pill 回到旧模型；不弹窗、不 toast。
- 非 thincoder 内核 / 无等待 ⇒ label 与 tooltip 逐字不变（负向锁：零字节注入）。
- 文案走 l10n（`modelsSwitchPending`）；失败 notice 为内核口英文（登记 §14-28）。

## 25. 交互响应（批 16；F22）

> 回指：需求档 F22 + A11（用户 2026-10-21 00:45「我要机制的性能体验，响应做到和 claude code 内核一样强劲，反应灵敏！」）。
> 一句结论：**每次建会话的 1.5 s 不在装配，在属主探测**——`session/new` 1501 ms = `newSession`（认领槽）1358 ms
> （`tasklist` 658 + PowerShell CIM 633）+ `createSession`（含 `assembleAgent` 95 ms）138 ms + 余 ≈5 ms；模型目录早已后台（`acp.mjs:97-111` 的 `refreshModelChoices` 不 await）。
> ⇒ 宿主侧做两件事：把 364 ms 的进程起 + 握手**前移到打开项目**（预热池），把用户的可输入时刻与「准备中」**变成可见可测**（乐观就绪 + 打点）；
> 1.36 s 的属主探测与 138 ms 的装配都在 CLI，归**已获批准的外仓批**（§25.13 C′1–C′3），C′1 + C′2 落地后 A11④ 可达（`session/new` ≤400 ms 可期）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：**切内核温启动**（提交 `fe403e32`；`chat_session.dart:435-455` 的 `_warm` 表 + `:450-453` 挂视图即 `prepare()`）——本批的预热池是同一手法从「内核级」升到「进程级」：一个启动好、握过手的进程留着等下一位用户。不改动该路径，只加读数（§25.5）。
- 对齐 ②：**队列**（§18；`thincoder_kernel.dart:614-638` 的 `_queue` / `_drain`）——「首条消息排队」直接复用这条既有队列：`_drain` 起回合后 `_deliver` 先落用户气泡（`:653-663`）再 `await _ensureStarted()`（`:680`），排队与等待已是既有形，本批不新造队列、不改排水顺序。
- 对齐 ③：**挂起窗释放判据**（§19.2 D64 / D65；`thincoder_kernel.dart:558-584` 的 `_canClose` + 一个 macrotask 的 `_releaseWhenIdle`）——预热池不参与该判据：池里的进程没有会话、没有回合、没有子代理，`_canClose` 的四个条件本就不适用于它（它不在任何内核实例名下）。
- 对齐 ④：**可见面**——等待/失败沿用既有 `NoticeItem` 面与既有健康位（`KernelHealthStatus.starting`，`thincoder_kernel.dart:229`），不新增控件、不新增弹窗。
- 偏离 ①：**不做单进程多会话**（把同一 cwd 的多个聊天会话塞进一个 ACP 进程）——它只省 364 ms 的进程成本，对 1545 ms 的装配零作用（实测同进程第二次仍 1507 ms），却要改连接归属、`_teardown` 与释放语义（风险面远大于收益）。被否，判据见 §25.4。
- 偏离 ②：**宿主侧不重试、不轮询补发**——预热池只做「有就领、没有就照旧起」，不引入定时器补位（同 §24.4 D99 的立场：时序不可测的东西不进状态机）。

**survey 证据**：公开资料本批**未查**（`websearch` / `fetch` 未调起；本批无版本 / API / 协议精度问题需要外部核对，判据全部来自本仓与外仓代码实读）。
已查的仓内 / 外仓来源：本仓 `lib/kernel/thincoder/thincoder_kernel.dart`（生命周期 `:219-297` · `:301-431` · 释放 `:544-609` · 发送 `:614-693`）、

`lib/chat/chat_session.dart`（`attach` `:400-413` · 切内核 `:435-455` · `canSend` `:693` · `send` `:1189-1220`）、`lib/kernel/agent_kernel.dart`（`prepare` 语义）；
外仓 `thincoder/thincoder-cli/src/acp/handlers-session.mjs:285` 起（`session/new` 处理链）与已知事实行的实测计时（2026-10-21 00:47，直发 ACP 帧）。

实测分解（2026-10-21 00:55–00:58，本机直测、可复跑）：`session/new` 1501 ms = `newSession` 1358 + `createSession` 138 + 余 ≈5；
`assembleAgent` 95 ms（`git config user.name` 71 / `createMemory` 7 / `assembleBuiltinTools` 9 / `loadConfig` 5 / `syncDir` 1 / `discoverRules` 0）；

`process.kill(pid, 0)` = 0.19 ms/pid（死 pid 返 `ESRCH`，Windows 可用）。
结论：**无外部公开来源可引用，本节断言以上列代码坐标为准**；上面 00:47 的 1545 ms 是端到端读数，其构成见 00:55 分解——**装配只占 138 ms**。

### 25.1 三条方向的允许 / 禁止结论（含因果链）

| 方向 | 结论 | 因果链（实测数字 → 机制 → 省哪一段） |
|---|---|---|
| A 预热进程 | **做**（本仓） | `initialize` 364 ms 与用户输入无关 ⇒ 在**打开项目时**就 spawn + 握手（进程空闲、不建会话、不认领槽位，`thincoder_kernel.dart:301-319` 的会话建立根本不会跑）⇒ 用户点开会话那次 `initialize` 已经付过，只剩 `session/new`（1501 ms，构成 = 属主探测 1358 + 装配 138，见 §25.13） |
| B 乐观就绪 | **做**（本仓，主要是接线与可见性） | `canSend`（`chat_session.dart:693`）不含健康位 ⇒ 起进程期间输入本就可用；`send` → `_queue.add` → `_drain` → 用户气泡先落（`:653`）再等启动（`:680`）⇒ 「排队」已是既有形。本批补：可见的「准备中」面 + 「可输入时刻」打点 |
| C CLI 侧瘦身 | **只设计，不实施**（B1 已获用户批准 2026-10-21 00:53 · 独立外仓批，§25.13） | `session/new` 1501 ms 已分解：属主探测 1358 ms（`tasklist` 658 + CIM 633）+ 装配 138 ms（`assembleAgent` 95）+ manifest / activeSlot 各 1 ms；模型目录已在后台 ⇒ 可省的是**判活**（C′1 / C′2，≈1.29 s）与 `git config user.name`（C′3，71 ms）；宿主侧无任何接口能影响它 |

**每条的允许 / 禁止**：

- A 允许：预热池新档、`_launch` 的一次改造（领池 vs 照旧起）；禁止：改 `session/new` 的调用时机（仍在 `_openSession` 里、仍由 `prepare()` 驱动）、改 ACP 握手内容（能力位仍按 `_context.files` 决定）、让池里的进程持有会话或槽位。
- B 允许：`appEvent` 打点、`NoticeItem` 等待面、`prepare()` 之后的健康位呈现；禁止：改 `canSend` / `canQueue` / `_drain` / `_queue` 的语义（§18 与 F15 的验收面不动）、改回合归属、改审批与取消路径。
- C 允许：已批准的外仓批按 §25.13 的 C′1–C′3 实施（该仓自己的批次档 + 测试）；禁止：**本轮**改 `thincoder/` 任何文件、在宿主侧伪造「第二会话免装配」的读数。

### 25.2 预热进程（A）：一个池子，一位住户

```text
打开项目（默认内核 = thincoder）
  ▼ ThincoderWarm.warm(cwd, files)          新档 lib/kernel/thincoder/thincoder_warm.dart
  ├─ 已有住户（同 cwd 同能力位）⇒ 什么都不做
  └─ 无 ⇒ spawn `thincoder acp` → initialize → 存 {connection, handshake}（整条 `ThincoderConnection`，含 `initialize` 回包）
        · TTL 10 min（超时即关；池空）
        · 进程 exited ⇒ 池自清
        · 项目切换 / 关项目 ⇒ 关池
用户点开会话 → ChatSession.attach（chat_session.dart:400）→ ThincoderKernel.prepare（:526）
  ▼ _ensureStarted（:220）→ _launch（:226）
  ├─ ThincoderWarm.take(key) 命中 ⇒ 领走整条 ThincoderConnection（不新建连接、不握手）
  │     ⇒ 跳过 spawn（~90 ms）与 initialize（364 ms），从 _openSession（:254）起跑
  └─ 未命中 ⇒ 照今天：_start（:231）+ initialize（:243）
```

- **键** = `(cwd, hasFilesCapability)`：`initialize` 的 `clientCapabilities` 由 `_context.files` 决定（`thincoder_kernel.dart:249-251`），能力位不同则握手的宣告不同，不能混领；键不同 ⇒ 旧住户关掉、按需新起。
- **能力位的唯一取法**：键的位 = `files != null`，与内核同一表达式（`_context.files == null ? {} : ThincoderFiles.capabilities`）。
  workspace 侧在打开项目时用**它将交给内核的同一个 `files` 取值**推出这一位（`workspace.dart:549-556` / `:2567-2572` 的 `KernelContext(files: IdeKernelFiles(...))`；缺省恒非 null ⇒ 位 = true）。
  取不到（构造失败 / 尚未定）⇒ **不预热**（错过预热优于错领）；T108 钉住「warm 键 == 内核领池键」。
- **领池交的是连接，不是裸 transport**：`take()` 返回池里那条 `ThincoderConnection`（`thincoder_protocol.dart:58-64`：它持 `_write` / 请求表 / 回调，`transport.messages` 只有池侧订阅过一次）——
  `_launch` 领到后直接接管该连接（重接 `onRequest` / `onNotification`），**不再 `_start`、不再 `initialize`、不再订阅同一条流**；`_transport` 仍归内核，`release()` / `_teardown()` 关的仍是它。
- **池不认领槽位**：`initialize` 之后不调 `session/new`，故按 §3.5「未发过消息的会话不落槽文件」，池里的进程在终端 `session/list` 里不可见、也不占槽。
- **只有一个**：每 cwd 至多一位住户（第二个请求 `warm` 直接返回）；换项目 ⇒ 先关旧住户再起新的（不并行占两个 Node 进程）。
- **释放归池、不归内核**：内核 `release()` / `dispose()` / `_teardown()`（`:544-609`）语义零改——它关的是**自己领到的那条** transport；池里的住户不在任何内核名下，`_canClose` 的四个条件（回合 / 启动中 / 子代理 / 挂起窗）对它无意义。
- **重新预热**：`release()` 走完（`_releaseWhenIdle` 的 macrotask 收束，`:576-583`）后**不**立即补位（否则等于取消释放的收益）；补位只发生在**打开项目**与**项目切换**两个时刻（应用前后台生命周期驱动不进本批，见 §25.12-8）。
- **失败面**：预热的进程起不来（未装 / 未登录 / 版本过低）⇒ 池记一个**短时冷却**（60 s 内不再试），会话照今天的方式启动并给出既有引导（F7：`thincoder_kernel.dart:279-296` 的错误面）。预热失败**不产生用户可见通知**——用户还没做任何事，报错只会制造噪声。
- **为什么这样能达标**：用户的等待 = 打开会话 → 首帧。预热把 364 ms 移到打开项目那一侧（用户在那里本来就要等目录扫描）；`session/new` 的 1501 ms 仍在（属主探测 1358 + 装配 138），但它在 `attach → prepare` 时就开始了（今天也如此），用户打字的时间与它重叠 ⇒ 首帧只剩 `344 ms` 的量级（判据与上界见 §25.10）。

### 25.3 乐观就绪（B）：输入不等内核，等待必须可见

事实（实读）：`canSend => !isStreaming || canQueue`（`chat_session.dart:693`）——不含健康位；`isStreaming` = `_transcript.activeTurn != null`（`:687`）、
`canQueue` = `_kernel is QueuesMessages`（`:651`）⇒ starting 期间 `canSend` 为真（U6 已实读关闭）；`ThincoderKernel.send`（`:614`）入队即返回；

`_drain`（`:630`）先 `_beginTurn` 再 `_deliver`，而 `_deliver` 在 `await _ensureStarted()`（`:680`）之前就把用户气泡发出（`:653-663`）。
**所以「起进程期间不能输入」在当前代码里不成立**；需要补的是三件事：

1. **可输入时刻可测**：t0 = `timing: open`（`chat_session.dart:402` 的 attach）；落点 = 首个「发送可用」帧——`canSend == true` 且 composer 的发送键 `_canSend`（`composer.dart:655`）只看内容。
   两者都成立的**第一帧**发一次 `timing: input-ready`（配对口径同 §25.6 的 `first-frame`：起飞点只建一个 `Stopwatch`，落点读一次即弃）。
   若实施首轮发现 composer 另有健康门（未核实，§25.15 U1），该门按「内核声明什么、UI 显示什么」的既有原则放宽为**只看能否发送**，不看 ready。
2. **等待可见**：起进程 / 装配期间，首条消息的回合已经开着（`_beginTurn`）却没有内容帧 ⇒ 界面必须能说清「它在准备」。
   **唯一路径**（实读关闭 U2）：宿主侧没有任何消费 `KernelHealthStatus.starting` 的呈现（`lib/chat/panels/health_banner.dart:27-28` 的 `shows` 只在 `failed` 为真；全仓仅 `ready` / `failed` 比较）。

   ⇒ 发一条 `NoticeItem(NoticeKind.warning, 'thincoder is starting…')`，并在 `_setHealth(ready)` 处 `ItemRemoved` 撤掉（形同 `_teardown` 的清理先例 `:495-499`）。

**发点 = `_deliver`（`thincoder_kernel.dart:707`，回合等进程时），不在 `_setHealth(starting)`**：宿主 `kernelLocked = _transcript.length > 0`（`chat_session.dart:423-424`）会把这条 Notice 计成「会话已开始」⇒ `_apply` 的 `if (kernelLocked) _dropWarm()`（`:204`）会在每次起内核时丢掉温存内核，`setKernel` 也被挡住。代价：只打开不发送的那段没有等待行（实施实读）。

   文案按 §14-28 的惯例取**内核口英文**，登记 §14-29（本地化归既有的内核文案本地化项，不在本批）。
3. **失败可见**：起不来时既有 `_fail`（`:461-470`）+ `_deliver` 的错误 `NoticeItem`（`:681-693`）已经把回合收尾成 interrupted ⇒ 不新增路径；补一条断言即可（T107 ②）。

**禁止**（本批明确不做）：不把「未就绪」做成「发不出去」——即不允许任何路径在 `_turn == null` 且内核未 ready 时静默丢消息；不改队列排水顺序（§18.1）；不给 composer 加「等就绪」的禁用态。

### 25.4 会话装配复用（C 的宿主侧上界）：结论 = 宿主侧不可达

- **事实**：`session/new` 实测 1501 ms（2026-10-21 00:55，同进程两次相近）⇒ 成本按**会话**计，不按**进程**计；其构成 = `newSession`（认领槽）1358 ms（属主探测：`tasklist` 658 + CIM 633）+ `createSession`（含 `assembleAgent` 95 ms）138 ms + 余 ≈5 ms。
- **推论一**：进程复用（预热池）只能拿掉 364 ms 的进程与握手成本，**拿不掉** 1501 ms 的会话建立成本。
- **推论二**：即使把同一 cwd 的多个聊天会话塞进一个 ACP 进程（`session/new` 不关闭既有会话，`sessions.set` 并存；`agentCapabilities.sessionCapabilities` 已声明 list/resume/delete/close），每个新会话仍要付一次 `session/new` ⇒ 仍不满足「第二会话不付全量装配」。
- **修正（旧稿的「装配 = 1545 ms」不成立）**：装配只占 **138 ms**；1.29 s 是**属主探测**。所以可省的不是模型目录懒取（它早已后台，`acp.mjs:97-111`），而是**判活**（C′1 658 + C′2 633）⇒ 归已批准的外仓批。
- **结论**：A11 第 4 项（同项目第二个会话不付全量装配）**宿主侧不可达**，C′1 + C′2 落地后可达（判据 = `timing: session-new` ≤400 ms）。宿主侧本批交付的上界 = 第二会话省掉 364 ms（预热池命中）。
- **为什么不做单进程多会话**：收益 364 ms（与预热池相同、不叠加），代价是把连接的归属从「一个内核实例」改成「一个按 cwd 的共享连接」，`_teardown`（`:472-510`）会误杀别的会话、`release()`（`:544`）的释放判据要重写、`session/close` 的归属要重划——风险面与 §19 的挂起窗、§18 的队列、§24 的模型后置同时相交。**被否**（D102）。

### 25.5 切内核路径：只读数、只回归

- 既有实现：`_warm` 表（`chat_session.dart:440`）把离开的内核实例留着，切回时 `_connect` 复用同一实例，`prepare()`（`:450-453`）走 `_ensureStarted`（`thincoder_kernel.dart:220-224`）——进程与 `initialize` 都还在，**不再付 364 ms**；`session/new` 也不付（`_slot` 在内存，走 `session/resume`，`_pickUpKept :401-408`）。
- 本批**不改**这条路径。只加一处打点：`setKernel`（`:435`）记 `t0`，新内核在其自身 `_setHealth(ready)` 后由宿主落 `t1`（`chat_session.dart:466-471`）⇒ `timing: kernel-switch`（门槛 ≤200 ms，A11 第 3 项）。落点取宿主的理由：切回 `_warm` 保留内核时内核侧无 health 迁移，落点在内核会永不触发。
- 回归判据：T111（切走再切回，第二次 `prepare` 不产生新的 `initialize` 请求）。

### 25.6 打点表（供实施与走查共用）

打点一律 `appEvent('thincoder', …)`（`lib/platform/event_log.dart:84`），一条一行、只在状态迁移处发一次；热路径上不写日志、不 `stopwatch` 常驻（`Stopwatch` 只在起飞点创建、落点读一次即弃）。

| 事件名（`appEvent` 第二参前缀） | 触发点（`file:line`） | 门槛 / 期望读数 |
|---|---|---|
| `timing: open` | `chat_session.dart:402`（`attach` 里 `prepare()` 之前） | t0，无门槛 |
| `timing: input-ready <N>ms` | t0 = `timing: open`（`chat_session.dart:402`）；落点 = 首个「发送可用」帧（`canSend == true` 且 composer 发送键只看内容） | **≤300 ms**（A11 第 1 项） |
| `timing: warm hit <N>ms` / `warm miss` | `thincoder_kernel.dart:231`（领池处） | 命中 ⇒ 省 ≥300 ms；miss ⇒ 走原路 |
| `timing: session-new <N>ms` | `thincoder_kernel.dart:415`（`session/new` 前后） | 现状 1501 ms（属主探测 1358 + 装配 138；只读数，不改） |
| `timing: first-frame <N>ms` | 首个内容帧落点：`thincoder_kernel.dart` 的 `_notification` 分流入口（`:1140` 附近）与 `_deliver` 的 prompt 发出处（`:697` 之后）配对 | **≤600 ms**（A11 第 2 项） |
| `timing: kernel-switch <N>ms` | `chat_session.dart:445`（t0）/ `:466-471`（t1） | **≤200 ms**（A11 第 3 项）；t1 在宿主而非内核——切回 `_warm` 保留的内核时 `_ensureStarted` 走 `_running` 短路（`thincoder_kernel.dart:222`），**没有 health 迁移** |
| `warm: held` | 新档池内（`initialize` 回包落地、住户入池） | 只留痕（走查 §25.14-1） |
| `warm: dropped <reason>` | 新档池内（TTL / 进程退出 / 切项目） | 只留痕 |

- 配对口径：`first-frame` 的计时窗 = 「`session/prompt` 写出」→「第一条携带内容（文本 / 思考 / 工具卡）的 `session/update`」；纯状态帧（`usage_update` / `config_option_update`）不计入。
- 打点行数上限：每会话每次迁移一行；不得出现按帧打印。

### 25.7 语义不变表（逐条写「不变」的根据）

| 面 | 结论 | 根据 |
|---|---|---|
| 审批 | 不变 | 预热池的进程没有会话 ⇒ 不可能有 `session/request_permission`；领池后走同一 `_serverRequest`（`thincoder_kernel.dart:239` 接线不变） |
| 取消 | 不变 | `cancel` 路径与队列 / 回合绑定，本批零改（`_queue` / `_turn` / `_endTurn` 不动） |
| 队列（F15 / §18） | 不变 | `send` / `_drain` / `_deliver` 的排水顺序与 `queued: true` 标记零改；乐观就绪只是**复用**它（§25.3 事实行） |
| 回合归属 | 不变 | `_beginTurn` 仍由 `_drain` 唯一触发；自动轮（§19.2）与用户回合的判据零改 |
| 未读 | 不变 | 未读由宿主 `ChatSession` 侧按回合结束计算，本批不触 |
| 挂起窗（§19） | 不变 | `_canClose` 四条件零改；池里的住户不在 `_canClose` 的判定对象内（没有 `_transport` 字段持有） |
| 切内核 | 不变（只加读数） | §25.5；`_warm` 表与 `prepare()` 调用点零改 |
| 释放 | 不变 | `release()` / `dispose()` 关的仍是「自己领到的 transport」；领池后该 transport 已归内核，池不再持有（`take` = 移出） |
| 模型后置（§24） | 不变 | 触发点全在 `_endTurn` 之后，与启动路径无交 |

### 25.8 受影响文件清单（E2 增量；行数 = 2026-10-21 实测）

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_warm.dart`（新增） | 保温池：`warm(cwd, files)` / `take(key)` / `drop(reason)` / TTL / 冷却；进程退出监听；`handshake` 回包原样保存 | ~ +170（新档，<300） |
| ② | `lib/kernel/thincoder/thincoder_kernel.dart`（1353） | `_launch`（`:226-297`）拆出「领池 ∥ 起进程」两条入口；`_ensureStarted`（`:220`）不变签名；打点 4 处（`:229` / `:231` / `:270` / `:415`）；首个内容帧打点 1 处 | ≤ +55（⇒ ≤1408；>800 名单，本批只行级） |
| ③ | `lib/chat/chat_session.dart`（1324） | `attach`（`:402`）打 `timing: open`；`setKernel`（`:435`）打 `timing: kernel-switch` 起点与落点；`timing: input-ready` 落点一处 | ≤ +16（⇒ ≤1340；实测 = 两条读数的最小事实成本） |
| ④ | `lib/kernel/agent_kernel.dart`（530） | 无改（`prepare` 语义不变；等待面走 `NoticeItem`，不新增 `preparing` 投影——无消费者、无用例，U2 已实读关闭） | 0 |
| ⑤ | `lib/workspace/workspace.dart`（2940） | 打开项目处调 `ThincoderWarm.warm(...)`（默认内核为 thincoder 时）；项目切换 / 关闭调 `drop` | ≤ +12（⇒ ≤2952） |
| ⑥ | `lib/chat/composer/composer.dart`（2416） | 若 composer 存在健康门（未核实 U1）⇒ 只在「未 ready」时不禁用发送 | 0 ~ +6 |
| ⑦ | `test/kernel/thincoder_kernel_test.dart`（4299） | T107–T111（§25.11） | ≤ +318（⇒ 4617；>800 名单，只加用例） |
| ⑧ | `test/kernel/thincoder_warm_test.dart`（新增） | T108 / T109 的池单测（不启真进程：注入假 transport 工厂） | ~ +110（新档，<300） |

- **零改动**：`thincoder_protocol.dart` · `thincoder_events.dart` · `thincoder_mock.dart` · `thincoder/`（B1 默认，见 §25.13）· `lib/kernel/claude_code/**` · 审批 / 取消 / 队列代码面 · 固件（无新帧）。
- **体量**：新档 <300；`thincoder_kernel.dart` / `workspace.dart` / `chat_session.dart` / `composer.dart`（2416）已在 >800 名单（§5.2），本批只行级（+≤55 / +≤12 / +≤8 / 0~+6），不续拆。
- **拆分立场（一句话）**：`_launch` 拆分**不动任何缝候选**、拆分触发仍归独立拆分批（与本批体量无咬合）。
- **接缝待核**：`workspace.dart` 的「打开项目 / 解析默认内核」处的确切行号（`:239-240` 是默认内核的现值点）由实施首轮 `grep` 核定并回填本节。

### 25.9 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D100 | 预热池住在 `lib/kernel/thincoder/` 的独立档，键 = `(cwd, hasFilesCapability)`，只持一条进程 | `initialize` 的 `clientCapabilities` 由 `_context.files` 决定（`:249-251`），能力位不同的进程不能互领；E1 单点要求 thincoder 相关代码集中一档。被否：把池做成全局单例跨 cwd 共享（`session/new` 的 cwd 必须等于进程 cwd，跨项目领来也用不了） |
| D101 | 池的触发 = 打开项目（默认内核为 thincoder 时），不跟会话视图 | 视图打开那一刻与 `prepare()` 同时发生，预热没有提前量；打开项目才是唯一稳定比「点会话」更早的时刻。被否：跟 composer 聚焦（聚焦即打开会话，同时发生）；被否：应用启动即预热（用户可能一整天不用 thincoder，白占一个 Node 进程） |
| D102 | 不做单进程多会话（宿主侧） | 只省 364 ms（与池不叠加），却要改连接归属 / `_teardown` / 释放判据，且**仍不满足** A11 第 4 项（装配按会话计）。被否 |
| D103 | 乐观就绪不新造队列，复用 §18 / `_drain` | 既有 `send` → `_queue` → `_beginTurn` → 气泡先落（`:653`）→ `await _ensureStarted()`（`:680`）已经是「先接住、后送达」；新造队列会与 `canQueue` / 队列面板 / 撤回编辑三条面同时冲突。被否：宿主侧待发队列 |
| D104 | 预热失败静默（用户不可见）+ 60 s 冷却 | 用户还没做任何事，报错是噪声；冷却避免每次打开会话都重试一次注定失败的启动。被否：预热失败即弹既有引导（会在用户没打算用 thincoder 时打断） |
| D105 | 打点只在状态迁移处，一条一次 | 热路径（每帧 / 每个 `session/update`）写日志会把测量成本加进被测量对象（§25.6 末行）。被否：帧级计时（自伤） |
| D106 | A11 第 4 项判为「宿主侧不可达」，归**已批准的外仓批**（§25.13），不在宿主侧伪造读数 | 实测 `session/new` 1501 ms = 属主探测 1358 + 装配 138；宿主侧无接口能改它。被否：以「进程复用」冒充「装配复用」报绿；被否：按旧稿归因「装配 1545 ms」（2026-10-21 实测推翻，装配只占 138 ms） |

### 25.10 验收对照（回指需求档 F22 / A11）

| 需求判据（A11） | 本档落点 | 机制 | 判据（机检 / 走查） | 宿主侧可达成上界 |
|---|---|---|---|---|
| 新建会话 **≤300 ms 可输入** | §25.2 / §25.3 | 输入不看健康位（`chat_session.dart:693` 实读）+ 预热池把 364 ms 前移 | T107：`health == starting` 时 `send` 仍入队、用户气泡在首个内容帧之前出现；`appEvent timing: input-ready` ≤300 | ✅ 可达成（输入面与内核状态解耦） |
| **首帧 ≤600 ms** | §25.2 + §25.6 | 预热省 364 ms；`session/new` 1501 ms（属主探测 1358 + 装配 138）在 `attach → prepare` 即起跑，与用户打字重叠；首帧本体 344 ms | T110：注入假 transport 时 `first-frame` 事件读数 ≤600；真机走查 S1 连续 5 次取中位数 | ⚠️ 本批交付时**条件达成**（打字时间 ≥ 会话建立剩余时间；300 ms 内就发首条 ⇒ 下界 ≈ 1501 − 300 + 344 ≈ 1.5 s）；**外仓批 C′1+C′2 后无条件**：首帧 = 预热命中 0 + 装配 138 + 首帧 344 ≈ 482 ms |
| **切内核 ≤200 ms** | §25.5 | 既有 `_warm` 表 + `prepare()` 复用（`fe403e32`），不重启进程、不再 `session/new` | T111：切走再切回，第二次启动零 `initialize`、零 `session/new`；`timing: kernel-switch` ≤200 | ✅（既有机制，只加读数；若读数超线 ⇒ 按 §25.12-3 登记，不在本批改实现） |
| **同项目第二会话不付全量装配** | §25.4 / §25.13 | 宿主侧只能省 364 ms（池命中）；1.5 s 里 1358 ms 是属主探测（C′1 658 + C′2 633）、138 ms 是装配（C′3 71 在装配内）⇒ 只能由外仓批拿掉 | 走查 S2：同项目开第二个会话，读 `timing: warm hit` 与 `timing: session-new` —— 前者命中、后者**仍 ≈1500 ms** ⇒ 本批判「未达标，待外仓批」 | ❌ 本批不可达；**待外仓批（已批准）C′1+C′2 落地**，后判据 = `timing: session-new` ≤400 ms |

- **读数归属**：A11 的「真机 `appEvent` 计时」= §25.6 的事件行；走查取证 = `events.log` 里对应时间戳差分，不是手掐秒表。
- **诚实口径（2026-10-21 修正）**：①③ 可判过 = **宿主批交付**；② 本批条件过，**无条件面**归外仓批；④ 本批不可达，**归外仓批交付（已获批准，C′1+C′2 后可达）**——批档 §2 与交付报告都按这个口径写，不合并成一句「全部达标」。

### 25.11 用例表（T107–T111）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T107 | 乐观就绪不阻塞、不丢消息 | 假 transport 工厂延迟 800 ms 才返回握手；`agent.prepare()` 后立刻 `send('hi')`；另一条：工厂直接抛 `ThincoderUnavailable` | ① `health.status == starting` 期间 `agent.send` 不抛、`requests('session/prompt')` 为空；800 ms 后恰 1 条 `session/prompt`；用户 `UserMessageItem` 在首个内容帧之前出现；`timing: input-ready` 事件存在。② 启动失败 ⇒ 恰 1 条 error `NoticeItem` + `TurnEnded(interrupted: true)`，无悬挂回合 |
| T108 | 预热池命中不重复 spawn / 不重复握手 / 键一致 | `ThincoderWarm` 注入假工厂（注入点在**连接层**：池与内核共用同一工厂，返回真 `ThincoderConnection`），`warm('/p', files)` 完成后再 `ThincoderKernel.prepare()` | 假工厂的 spawn 调用次数 == 1；`initialize` 请求在**假 transport 层**只出现 1 次（池里那次）；**领用的连接上不再出现 `initialize`**；`session/new` 恰 1 条；`warm` 键 == 内核领池键（同一 `(cwd, files != null)`） |
| T109 | 池的失效与释放 | ① TTL 到期（**注入时钟**推进 10 min，不靠墙钟）；② 池进程 `exited`；③ 能力位不同（`files == null` vs 有）；④ `drop('project-switch')` | 四种情形 `take(key)` 均返回 null 且不抛；`warm: dropped <reason>` 各一行；旧 transport 均已 `close()` |
| T110 | 首帧打点口径 | 假 transport：`session/prompt` 应答前先推 `usage_update`（状态帧）再推 `agent_message_chunk`（内容帧） | `first-frame` 的时间起点 = prompt 写出时刻，落点 = 内容帧（`usage_update` 不计）；读数 ≤600（假时钟 344 ms） |
| T111 | 切内核温启动不回归 | 两个内核描述符；`setKernel(a→b→a)`（视图在） | `a` 的第二次 `prepare` 不产生新的 `initialize` / `session/new`；`timing: kernel-switch` 每个方向各一行 |

- 断言面：`_Session` / 假 transport（`ThincoderMock` 已有 `start` 注入口，形同 T100–T105）；池单测在 `test/kernel/thincoder_warm_test.dart`，不启真进程。
- **确定性**：时钟 / 定时器与 transport 工厂都可注入（构造参数或模块级 setter + `??` 生产缺省，用例 `finally` 复位）——T109 ① 的 TTL 用注入时钟推进，不依赖墙钟；T107 的 800 ms 延迟与 T110 的假时钟 344 ms 同源。
- 不新增固件：线形零改（仍是 `initialize` / `session/new` / `session/prompt`），既有固件保持绿 = 回归哨兵。

### 25.12 边界（本批不做）与登记（判定条件）

1. **本批不改 CLI**：`thincoder/` 零改；CLI 侧改动归**已获批准的外仓批**（§25.13 C′1–C′3，该仓自己的批次档与测试）。
2. **不做单进程多会话**：D102。
3. **切内核超线不改实现**：若 `timing: kernel-switch` 真机 >200 ms，登记判定条件 = 「同项目连续切两次、第二次仍 >200 ms ⇒ 取 `events.log` 与 `graph` 时序另立批」；本批只读数。
4. **本批不做首帧的无条件达标**：见 §25.10 的上界；外仓批（C′1+C′2）落地前 A11 第 2 项按「条件达成」记。
5. **不做预热池的跨进程复用**：池随应用进程存活；应用重启后首次打开项目重新预热。
6. **不做远端项目的预热**（F8 面）：远端 ACP 进程在 SSH 主机上，预热 = 在远端起进程，本批不做（判定条件：远端项目走查首帧明显偏慢 ⇒ 另立）。
7. **不把 `session/new` 挪到首条消息**：它在 `prepare()`（打开视图）时就起，这是今天的行为、也是首帧能达标的前提；挪到发送时才起会把 1.5 s 全压在首帧上。
8. **应用前后台生命周期驱动预热池 = 条件项（本批不做）**：进后台关池 / 回前台补位无承载档与用例，也不在 A11 验收路径上（已从 §25.2 删掉）。判定条件：现场见到「长时间在后台后回前台，首帧明显慢」⇒ 先核池是否已被 TTL 关掉；确认平台有可靠生命周期回调 ⇒ 另立批补 `WidgetsBindingObserver` 钩子 + 用例。

### 25.13 外仓（`thincoder/`）改动清单 = B1 已获用户批准（2026-10-21 00:53）· 独立外仓批（本批不实施）

> 依据：需求档 F22「依赖」行 + 用户 2026-10-21 00:53 逐字「允许修改thincoder仓库」⇒ B1 例外**已批准**，落点 = 独立外仓批（该仓自己的批次档 + 测试 + 提交）。
> 前提事实（2026-10-21 00:55–00:58 实测，可复跑）：`session/new` 1501 ms = `newSession`（认领槽）**1358 ms**
> （`probeOwnersAsync` → `batchAliveAsync` 的 `tasklist /FO CSV /NH` 658 + `probeCmdlinesAsync` 的 PowerShell `Get-CimInstance … ConvertTo-Json` 633）
> + `createSession`（含 `assembleAgent` 95 ms）**138 ms** + 余 ≈5 ms；`assembleAgent` 内：`git config user.name` 71 / `createMemory` 7 / `assembleBuiltinTools` 9 / `loadConfig` 5 / `syncDir` 1 / `discoverRules` 0；
> `loadManifest` 1 ms、`activeSlot` 1 ms；模型目录**已是后台**（`thincoder-cli/src/acp.mjs:97-111` 的 `defaultCreateSession` 不 await `refreshModelChoices`）⇒ 旧稿的 C1（模型目录懒取）**无收益，已撤**。
> 处理链起点：`thincoder-cli/src/acp/handlers-session.mjs:285` 起（`requireConfigured()` → `newSession(getCwd())` → `createSession({...})` → `sessions.set`）；`process.kill(pid, 0)` 实测 0.19 ms/pid（死 pid 返 `ESRCH`，Windows 可用）。

| # | 档 | 改动 | 预期收益 | 判定条件（做完怎么算成） |
|---|---|---|---|---|
| C′1 | `session/new` 的属主判活（Windows） | 批量判活改 `process.kill(pid, 0)` 查表（死 pid = `ESRCH`）；**保留「unknown ⇒ 不认领不判死」语义**与 `probeOwnersAsync` 的注入缝 | **≈658 ms** | 打点复测：`session/new` 降幅 ≥600 ms；unknown 分支有用例（非 `ESRCH` 错误不判死） |
| C′2 | `session/new` 的属主命令行 | `probeCmdlinesAsync` 只在「pid 复用需复核身份」时发；死属主清理移出 `session/new` 热路径（改懒清理 / 后台） | **≈633 ms** | 同会话首建与再建均不再跑全量 CIM；清理在后台完成且有留痕 |
| C′3 | `assembleAgent` 的 git 身份 | `git config user.name` 缓存或改读 `.git/config` | **≈71 ms** | 装配打点降幅 ≥50 ms；子仓库 / worktree 取到同名值 |

- 开工形式：另立 out-of-repo 批（该仓自己的批次档 + 测试），本仓只登记；**本批一行不写**。
- 收益排序已由实测给定（C′1 658 > C′2 633 ≫ C′3 71）：外仓批按此顺序做，每项落地后复测 `session/new`。
- 语义保留（C′1 硬约束）：「unknown ⇒ 不认领不判死」不变（`process.kill` 的 `EPERM` / 非 `ESRCH` 错误按 unknown）；`probeOwnersAsync` 的注入缝保留。

### 25.14 真机走查步骤

1. 打开项目（默认内核 = thincoder），等 3 s（让池预热完）⇒ `events.log` 有 `warm: held` 一行、无 `session/new`。
2. 点新建会话 ⇒ 输入框立刻可打字；`timing: input-ready` ≤300 ms；`timing: warm hit` 命中。
3. 立刻发一条消息（开视图后 1 s 内）⇒ `timing: first-frame` 读数；连做 5 次取中位数（A11 第 2 项）。
4. 同一项目再开第二个会话 ⇒ `timing: session-new` 仍 ≈1500 ms（记录为「待外仓批」，不当作缺陷瞒下）；`warm hit` 是否命中（取决于池是否已被第一个会话领走 ⇒ 第二个会话 miss 属预期）。
5. 切到 claude-code 再切回 ⇒ 输入可用；`timing: kernel-switch` ≤200 ms，第二次切回零 `initialize` / 零 `session/new`。
6. 关掉会话视图（`release`）⇒ 进程退出、池空（不补位）⇒ 下一次开会话付全量启动（spawn + `initialize` + `session/new`），属预期；与本步无关的 TTL 条件不计。

### 25.15 未核实 / 实现期确认项

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U1 | composer 是否存在「内核未 ready ⇒ 禁用发送」的健康门 | 未核实（`composer.dart:2126` 的 `enabled: _canSend` 只看内容；其它门未逐行核） | 实施首轮核；有 ⇒ 按 §25.3-1 放宽，无 ⇒ 本条作废 |
| U3 | `session/new` 1501 ms 的构成 | 已实测（2026-10-21 00:55）：属主探测 1358（`tasklist` 658 + CIM 633）+ 装配 138（`assembleAgent` 95）+ manifest / activeSlot 各 1 | 不再需要外仓批分解；MCP / embedding 合计 ≤43 ms（`createSession` 138 − `assembleAgent` 95），按 §25.13 顺序实施 |
| U6 | starting 期间 `isStreaming` 是否为真 | **已实读关闭**：`chat_session.dart:687` = `_transcript.activeTurn != null`；`canQueue` 在 `:651` | 不再需要实施首轮核；§25.3 事实行成立（starting 期间 `canSend` 为真） |
| U4 | 预热池的常驻内存开销 | 未测（一个 Node 进程的 V8 基线） | 实施首轮量一次 `process` 内存；超过 ~120 MB ⇒ 池改为按需预热（只保留开关） |
| U5 | `workspace.dart` 打开项目处的确切行号 | 未定位到行（`:239-240` = 默认内核现值点） | 实施首轮核定并回填 §25.8 |

## 26. 内置运行时（批 17；F23）

> 回指：需求档 F23 功能点 ①–⑤ / 验收 ①–⑤ + 两条边界——「开发环境零变化」（`docs/requirements/thincoder-adapter.md:168`）与「开发环境与终端互通」（`:169`）。
> 一句结论：发行版自带 `runtime\node\node.exe`（macOS 为 `runtime\node\node`）+ `runtime\thincoder\`（源码树，零构建）+ 私有数据目录；
> locator 顺序 = 显式 → 内置 → PATH，**内置存在即不构造 PATH 候选**；开发环境靠「内置目录在不在」自然分叉，不引入任何 release 分支；
> 私有数据目录只在**内置分支**注入，PATH / 显式分支的 environment 与今天逐字相同。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：**OpenSSH 随包**（`tool/build_windows.dart:71-80` 版本 + SHA-256 钉死、`:182-184` 入包、`:329-373` 下载一次缓存到 `build\openssh\`）——本批的 Node 运行时完全照此形：版本 + 哈希钉死、`build\node\` 缓存、入包前校验。
- 对齐 ②：**替换引擎的哈希校验**（`tool/build_windows.dart:294-324`）——「包里的东西不是脚本预期的就停」这条先例直接用于 `node.exe` 与 thincoder 源码树的版本一致性（§26.8）。
- 对齐 ③：**设置路径优先**（`thincoder_locator.dart:96-108`）——显式路径不存在即抛，今天已是「不回落」形，本批不动这一段，只在其后插入内置层。
- 偏离 ①：**不做单文件 SEA**——判据见 §26.2（入口动态 import、8+8 处 `import.meta.url` 资产读、注入需 postject、体积不省）。取等价形态「源码树 + 内嵌 node 目录」。

**survey 证据**：本轮**未调**公开检索（`websearch` / `fetch` 未发起）——Node SEA 在本机的可用性用 `node --help` 实测判定（§26.2 第 1 行），不依赖外部文档版本；
其余判据全部来自本仓与外仓实读（坐标见各节）。外仓构建源 = 本仓工作树 `thincoder/` 当前 HEAD，不拉上游最新（用户 2026-10-21 03:58 落定）。

### 26.1 决议与形态

| 面 | 决议 |
|---|---|
| 内置位置 | Windows：`<安装目录>\runtime\`（Inno 的 `{app}\runtime\`）；macOS：`BaoCode.app/Contents/Resources/runtime/`（§26.8）。理由：只读、与发版版本同生共死、升级整体替换、卸载带走；应用数据目录只放可变状态（配置 / 会话 / 日志），不混装二进制 |
| 内置组成 | `runtime\node\node.exe`（85.7 MB，实测；macOS 为 `runtime\node\node`）+ `runtime\thincoder\{bin,src,package.json,LICENSE,node_modules\@thincoder\core\}`（≈6.8 MB，实测）+ `runtime\THIRD-PARTY-NOTICES.txt` |
| 启动命令 | `runtime\node\node.exe runtime\thincoder\bin\thincoder.cjs acp`；`bin/thincoder.cjs:6` 的 `import("./thincoder.mjs")` 是运行期动态 import，源码树在位即可解析（实测可跑，§26.2） |
| 构建源 | 本仓工作树 `thincoder/` 当前 HEAD；版本一致性判据 = 产物 `--version` == 构建脚本常量 `_thincoderVersion` == `thincoder-cli\package.json` 的 `version`（今天三者同为 `0.12.76`，实测；常量形态见 §26.8） |
| 数据目录 | `THINCODER_CONFIG_DIR` → `<应用数据目录>\runtime-data\thincoder`（**仅内置分支注入**，§26.5） |

### 26.2 打包可行性 spike（实测，2026-10-21 04:05–04:08，本机 Node v24.11.1）

| # | 命令 / 读点 | 读数 | 结论 |
|---|---|---|---|
| 1 | `node -v` / `node --help \| findstr sea` | `v24.11.1`；含 `--experimental-sea-config` | SEA 的 blob 步骤本机可用（不等于整链可用） |
| 2 | `node thincoder-cli\bin\thincoder.cjs --version` | `0.12.76` | 源码树**零构建直接可跑**（`package.json:4` 的 "no build step" 成立） |
| 3 | `node …\bin\thincoder.cjs acp` | stderr `[acp] thincoder 0.12.76 — ACP v1 over stdio, waiting for initialize`，exit 0 | ACP 入口可跑 |
| 4 | `C:\Program Files\nodejs\node.exe` 大小 | `89,894,400` B = 85.7 MB | 内置 Node 的体积基线 |
| 5 | `dir /s /-c`：`thincoder-core` 与 `thincoder-cli\src` 逐目录 `File(s)` 合计 | 两树合计 ≈ 6.8 MB（其中一树 346 文件） | 压缩前总量 ≈ 92.5 MB |

**SEA 不选的判据（逐条带坐标）**

1. **入口是 CJS shim + 运行期动态 `import()`**（`thincoder-cli\bin\thincoder.cjs:6`）：SEA 的主脚本是单一 blob，动态 import 一个不在 blob 里的路径解析不了；要 SEA 必先 bundler 合成单文件，而上游明示零构建、无 bundler 依赖（`package.json:4`）。
2. **运行期读 `package.json`**：`thincoder-cli\src` 内 `import.meta.url` 命中 **8 处**：
   `src/acp.mjs:43` · `src/command-table.mjs:115` · `src/tui/cmd-upgrade.mjs:11` · `src/tui/input-face.mjs:44` ·
   `src/tui/render-frame.mjs:33` · `src/tui/update-notice.mjs:59` · `src/tui/wrapped-spawn.mjs:15` · `:26`；

   `thincoder-core` 同命令命中 **8 处**。SEA 里 `import.meta.url` 不指向文件系统，须改 `sea.getAsset` ⇒ 动上游 16 处，与「最小改动、上游可合并」冲突。
3. **注入步骤要 postject**（`npx postject … NODE_SEA_BLOB …`）：本机未安装，构建链需额外依赖与网络；源码树 + node 目录零外部工具。
4. **体积不省**：SEA = node.exe + blob，与直接带 node.exe 同量级（85.7 MB 已量到）。

⇒ **替代方案即主方案**：bundle = 源码树 + `node.exe` 目录，不做单文件。
将来若仍要 SEA，验证步骤（本批不执行）：`sea-config.json`（`main` = 打包后的单文件）→ `node --experimental-sea-config sea-config.json` → 按 Node 文档用 `postject` 把 blob 注入 node.exe（sentinel fuse 参数以该 Node 版本文档为准）→ `thincoder.exe --version` 与 `acp` 冒烟；任一步失败即回到本方案。

### 26.3 候选顺序与四格表

解析顺序：**① 显式 `thincoder.path` → ② 内置副本 → ③ PATH（仅当 ② 不存在）**。
「内置存在」时**不调用 `candidates()`**（连候选表都不构造），这是 PATH 屏蔽的实现形状。

| 情形 | 内置存在 | 显式设置 | 解析结果 | 是否探测 PATH |
|---|---|---|---|---|
| 发行版开箱 | 是 | 无 | 内置（`node.exe` + `bin\thincoder.cjs`） | 否 |
| 发行版 + 用户设了有效路径 | 是 | 有 | 显式路径（优先于内置） | 否 |
| 发行版 + 显式路径不存在 | 是 | 有（坏） | 抛 `ThincoderUnavailable` ⇒ 状态 `ThincoderFailed`（与今天同形，不回落到内置） | 否 |
| 开发 `flutter run` / `flutter test` | 否 | 无 | PATH 候选，顺序与今天**逐字相同** | 是 |
| 开发 + 显式设置 | 否 | 有 | 显式路径 | 否 |
| 发行版 runtime 被删（安装损坏） | 否 | 无 | 与开发同路走 PATH | 是 |

末行的取舍：**「内置在不在」是唯一判据**，不引入发行版常量（用户 2026-10-21 03:57「不要影响到我们的开发环境，只有发行版才这样做」）；安装损坏的用户得到今天的引导面，而不是一个无法自救的报错。

**「屏蔽 PATH」的机检判据（两条）**

1. 解析函数级：`candidatesOverride` 注入一个计数桩，内置存在时调用 `locateBuild()` ⇒ 桩调用次数 **0**（T113）；`locateBuild().display` 逐字 == 内置 cjs 的绝对路径，`locate()` == 内置 node 的绝对路径。
2. 行为级：`events.log` 的启动行点名绝对路径 `…\runtime\thincoder\bin\thincoder.cjs`（§26.7），且该会话的启动行不出现任何 PATH 候选串（`npm` 目录 / `thincoder.cmd`）。

### 26.4 locator 机制（本档改动面）

- 新增 `ThincoderBuild { display, executable, arguments }`：`display` = 状态行显示的构建（内置 = cjs 路径，PATH/显式 = 原可执行文件），`executable` + `arguments` = 真正 spawn 的东西（内置 = `node.exe` + `[cjs, 'acp']`）。
- `locateBuild()`（`thincoder_locator.dart:166-171`）插入一层并返回 `ThincoderBuild`；`locate()`（`:173-175`）签名不变、仍返回 `String`，取值 = `locateBuild().executable`（内置时是 node 的绝对路径，不是 cjs）：
  ```
  显式 → 现状（不存在即抛，不回落）
  内置存在 → ThincoderBuild(display: cjs, executable: node.exe, arguments: [cjs, 'acp'])
  否则 → 现状 candidates()（一行不改）
  ```
- 内置判定（平台规则在缝内）：可执行文件目录 = `executableDirectoryOverride ?? p.dirname(Platform.resolvedExecutable)`；runtime 根由纯函数 `runtimeRootOf(executableDirectory, {bool? isMac})`（`thincoder_locator.dart:266`）求：
  - Windows：`<exe 目录>\runtime`
  - macOS：`<exe 目录>/../Resources/runtime`（= `BaoCode.app/Contents/Resources/runtime`，与 §26.8 的入包位置对齐；包内可执行文件在 `Contents/MacOS/`，上一层才是 `Contents/`）
  **内置存在** = `<runtime 根>/thincoder/bin/thincoder.cjs` 与 node 可执行文件（Windows `<runtime 根>/node/node.exe`；macOS `<runtime 根>/node/node`）两者都在。
  `executableDirectoryOverride` 的语义不变 = 「可执行文件所在目录」，平台规则作用于其后；`isMac` 缺省 `Platform.isMacOS`，测试直传以覆盖 macOS 形态（T112a / T113a）。这是宿主事实，不是发行 / 开发开关（D109 不变）。
- `versionOf`（`thincoder_locator.dart:298`）加可选 `arguments`，内置情形跑 `<node> <cjs> --version`；`status()`（`:341`）用 `display` 进 `ThincoderFound.path`，于是设置页显示「In use: …\runtime\thincoder\bin\thincoder.cjs (0.12.76)」。
- **内置在但跑不起来**（node 存在、`--version` 返回 null）⇒ `status()` 报 `ThincoderFailed`，消息含内置 node 路径与「内置运行时无法启动」；不崩、**不改走 PATH**（判据只看文件在不在，「在」就是内置分支，见 §26.3 末行），T113b。
- `launch()`（`thincoder_locator.dart:127-141`）返回值携带 `arguments` 与分支后的 environment（§26.5：仅内置分支注入）；`throughShell`（`:373`）对 `.exe` / 绝对路径的 node 为 false，内置路径不再过 shell。
- `ThincoderLaunch`（`thincoder_transport.dart:40-68`）增 `arguments`（默认 `const [ThincoderLaunch.command]`），`withEnvironment` 同步携带。
- **进程注册表不变**：注册表按**类别**登记（`DataDirectory.current.processRegistryFile('thincoder')` ⇒ `state/thincoder-processes.json`，`thincoder_process_io.dart:48-50`）
  键是 pid + 逐字命令行，不取可执行文件名（`child_process_registry.dart:62-82` / `:111-127`）；`recognizes` = 命令行同时含 `thincoder` 与 `acp`（`thincoder_process_io.dart:205-206`）。
  内置命令行 `node.exe …\thincoder.cjs acp` 两条都成立 ⇒ `reapThincoderProcesses()` / `stopThincoderProcesses()` 仍命中（T117a）。

### 26.5 独立数据目录（外仓改动已获批准 2026-10-21 03:58「外仓可以」；本批不实施）

**外仓最小改动（+ 实测的必要扩展）**

- 新增 `thincoder-core/home.mjs`（≈18 行）：`thincoderHome(env = process.env)` = `env.THINCODER_CONFIG_DIR?.trim() || join(homedir(), ".thincoder")`。
- `config-io.mjs:32` → `export const configDir = thincoderHome()`；`:33` 的 `configPath` 自动随动。
- **实测发现（本批读数，不是预估）**：`~/.thincoder` 另有 **4 档 7 处**直接拼 `homedir()`，不随 `configDir`：
  `log.mjs:58`（日志目录，**写**）· `agent/dispatch-gates.mjs:21`（`tool-errors/`，**写**）· `skills.mjs:94` / `:136` / `:217` / `:226`（用户 skills，读；`:136` 是否写待实施首轮核）· `agent/helpers.mjs:403`（用户级 AGENTS 文件，读）。

  ⇒ 只改 `config-io.mjs:32` 时内置副本仍会写 `~/.thincoder/logs` 与 `~/.thincoder/tool-errors`，F23 验收 ③ 不达标。外仓改动 = 新增 1 档 + 5 档改调 `thincoderHome()`（**6 档 8 处调用点**），估 **≤ +30 / −7 行**。
- **批准面 = 这个实测面**：需求档原估「约 3–5 行」偏低；B1 例外按 6 档 8 处、≤ +30 / −7 行批准，需求档 `:167` 已同步为实测面。
- 其余路径全部派生自 `configDir`（实测坐标）：
  会话 `session-slots.mjs:89` · `session-gc.mjs:51` · `session-index.mjs:42` · `session-migrate.mjs:24`；
  ledger `ledger-db.mjs:29` · 检查点 `checkpoint.mjs:42` · traces `trace-store.mjs:53` · peers `peer-claims.mjs:40` · teams `assemble.mjs:33`；

  tool-results `helpers.mjs:156` / `bash-async.mjs:62` / `digest-budget.mjs:66` · memory `config-defaults.mjs:59` / `acp/ext.mjs:81`；
  crash reports `crash-reports.mjs:35` · ssh `ssh-transport.mjs:51` · 浏览器 profile `browser/launch.mjs:66`。

**注入点（本仓，仅内置分支）**：`ThincoderLocator.launch`（`thincoder_locator.dart:127-141`）先求一次内置判定（§26.4 的同一个结果），按它分两支：

- **有内置**：`environment['THINCODER_CONFIG_DIR'] = DataDirectory.current.thincoderDataDir`（= `<数据目录>/runtime-data/thincoder`，`lib/platform/data_dir.dart` 新增的只读访问器，§26.9 ⑨）；`Process.start`（`thincoder_process_io.dart:86-97`）原样透传 ⇒ 子进程启动前 env 就位，模块加载期读到的即私有目录。
- **无内置**（PATH / 显式路径）：environment **不新增键**——`THINCODER_CONFIG_DIR` 不写、不删、不改，其余键与今天逐字相同 ⇒ 内核读写用户 `~/.thincoder`，终端开的会话在 baocode 里能列、能打开、能续接（需求档 `:169`）。
- **同一份 environment 也供设置页的写面**：`ThincoderLocator.environment()`（`:147-148`）返回的就是 `launch()` 用的那一份（同一 `_withDataFolder`）；设置 → 模型页的默认环境来源引用它（`thincoder_config_file.dart:32-33`）⇒ 页面写的文件 == CLI 读的文件。

判据只有一条且与「内置在不在」同源（同一个内置判定，不新增开关、不看 `kReleaseMode`）；T115a / T115b 分别钉住两支。

**连带影响面**

| 面 | 今天 | 发行版（内置副本） |
|---|---|---|
| 配置 | `~/.thincoder/config.json` | `<数据目录>\runtime-data\thincoder\config.json` |
| 会话槽 | `~/.thincoder/sessions/` | 同上私有目录下 `sessions/` |
| token / 凭据 | `configDir` 域内（具体文件名未逐档核实，U11） | 同域，随 env 迁移 |
| 日志 | `~/.thincoder/logs/` | 私有目录下 `logs/` |
| 崩溃报告 / memory.db / ledger / checkpoints / traces / teams / tool-results / browser profile | `~/.thincoder/…` | 私有目录下同名子目录 |

**「用户 `~/.thincoder` 不被写」的机检读法**（会话前后各跑一次，两值逐字相同）：

```powershell
$p = Join-Path $HOME '.thincoder'
$a = @(Get-ChildItem -Recurse -Force $p -ErrorAction SilentlyContinue)
'{0} {1:o}' -f $a.Count, (($a | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime)
```

另一侧（私有目录）同命令 ⇒ 文件数 > 0 且 mtime 前进，证明写的是新目录而不是没写。

### 26.6 开发环境不受影响（如何保证）

- **唯一判据**：`runtime/thincoder/bin/thincoder.cjs` 在不在，由可执行文件目录按平台规则推出（§26.4：Windows `…/runtime`、macOS `…/../Resources/runtime`）。`flutter run` 的 Debug 产物、`flutter test` 的 tester、`dart run tool\*` 都没有 `runtime/` ⇒ 走 PATH 分支，候选列表代码一行不改。
- **开发环境不注入 `THINCODER_CONFIG_DIR`**：无内置时 environment 与今天逐字相同（不新增键），内核读写用户 `~/.thincoder` ⇒ 终端与 baocode 互通（需求档 `:169`）；注入只发生在内置分支，判据与内置判定同源（§26.5）。
- **不引入 release 分支**：无 `kReleaseMode` 判断、无编译期开关、无默认值变化（用户 2026-10-21 03:57 逐字约束；需求档 `:168`）。
- **`lib/**` 零硬编码安装目录**：安装目录只出现在「由可执行文件目录派生」这一处（`executableDirectoryOverride ?? p.dirname(Platform.resolvedExecutable)`），没有字面量 `Program Files` / `runtime\`。
- **测试覆盖**：T112 / T112a（无内置：Windows ∥ macOS ⇒ `candidates()` 与今天逐项相等、顺序不变）· T112b（半残态 ⇒ 视作无内置）· T113 / T113a（有内置：Windows ∥ macOS ⇒ 解析到内置且 `candidates()` 零调用）· T113b（内置在但跑不起来 ⇒ 明确失败态）。都用 `executableDirectoryOverride` 指向临时目录制造有/无 `runtime/` 两种世界；macOS 形态由 `runtimeRootOf` 的 `isMac` 直传（不真机，U7）。

### 26.7 启动与日志（可机检）

- `ThincoderProcess.start`（`thincoder_process_io.dart:81-103`）保持一条 spawn 路径；内置情形 `runInShell == false`（`.exe`），不再经 `cmd.exe`。
- 启动行：`appEvent('thincoder', 'launch: builtin <display>')` / `'launch: path <display>'`——分支标签与 `display` 都由内置判定给出，落点是 `ThincoderLocator.launch`（`thincoder_locator.dart:131-134`），不在 `thincoder_process_io.dart`（那里没有分支信息）；每次启动一行，落 `events.log`。这就是验收 ② 的读点。
- 设置页状态行沿用 `thincoderStatusLine`（`thincoder_locator.dart:55-60`）：`In use: <display> (<version>)`，用户能看出当前用的是内置还是自己设的路径，文案零改。

### 26.8 打包改动

**Windows（本机可验证）**

- `tool/build_windows.dart` 新增：
  1. `_nodeVersion = 'v24.11.1'` + `_nodeSha256`（`tool/build_windows.dart:102-103`，照 OpenSSH 先例 `:71-73`）：从 Node 官方下载 `node-v24.11.1-win-x64.zip` 到 `build\node\`，校验后取 `node.exe`。
  2. `_putRuntime(root, bundle)`：从工作树复制 `thincoder\thincoder-cli\{bin,src,package.json,LICENSE}` 与 `thincoder\thincoder-core\` 到 `bundle\runtime\thincoder\`，并把 core 放到 `runtime\thincoder\node_modules\@thincoder\core\`（`@thincoder/core` 的裸导入按 node 解析规则命中）；`node.exe` → `runtime\node\node.exe`；写 `runtime\THIRD-PARTY-NOTICES.txt`（thincoder / @thincoder/core 的 MIT 声明 + Node 的许可指向）。
  3. **版本一致性校验（对常量，不对来源自比）**：`_thincoderVersion = '0.12.76'`（形同 `_nodeVersion`）为预期值，两道都比它——
    ① 源码树 `thincoder-cli\package.json.version` == `_thincoderVersion`（构建源是预期的那份）；
    ② 产物 `node.exe runtime\thincoder\bin\thincoder.cjs --version` == `_thincoderVersion`（拷进去的能跑、且是预期版本）。
    任一不等 ⇒ `_fail` 并打印两侧值。只拿 ② 与源码树自比是恒等判据，兑不了对齐 ②「不是脚本预期的就停」。
  4. `_checkBundle` 必检项追加 `runtime\node\node.exe` · `runtime\thincoder\bin\thincoder.cjs` · `runtime\thincoder\LICENSE`。
- `tool/baocode.iss`：`[Files]` 的 `Source: "{#BundleDir}\*"; recursesubdirs`（`:97-98`）**已覆盖** `runtime\`，不需要新增文件行。
  改动 = ① `:90-96` 注释补 `runtime\`；② **不**把 thincoder 的 MIT 设为 `LicenseFile`（安装向导的许可页是 BaoCode 自己的）。
  许可随附 = `runtime\thincoder\LICENSE` + `runtime\THIRD-PARTY-NOTICES.txt` 两份文件随包（功能点 ⑤ 只要求随附，随附即满足）。
  **本批不接「关于」页**：关于页的许可引用不在本批范围（§26.9 本仓表无关于页行）。
- 体积：未压缩 ≈ 85.7 + 6.8 ≈ 92.5 MB；lzma2 后的增量实施轮实测回填（现值安装包 21.0 MB）。

**macOS（设计已给、未验证——本机不能验证）**

- `tool/build_macos.dart` 同改点：`_putRuntime` → `BaoCode.app/Contents/Resources/runtime/`（探测侧的平台规则见 §26.4：包内可执行文件在 `Contents/MacOS/`，runtime 在其上一层的 `Resources/`）；node 取 `node-v24.11.1-darwin-{arm64,x64}.tar.gz` 两架构各一份（`_nodeVersion` / `_nodeSha256`，`tool/build_macos.dart:84-85`），用 `lipo` 合成**一个**通用二进制 `runtime/node/node`（`:593-595`）——locator 的单路径契约不变，随后既有 `ditto --arch` 瘦身照走（`:251-257`）；签名沿用既有 `signing.sign`（`:261` 的 `signApp`、`:301` 的 dmg；ad hoc 即 `--sign -`），hardened runtime 下未签名的子进程会被拦；版本一致性校验同 Windows（对 `_thincoderVersion` 常量，两道都比）。

### 26.9 受影响文件清单（现值 = 2026-10-21 编制基线；实交 delta = 2026-10-22 读数）

**本仓**

| # | 坐标 | 现值（编制基线） | 改动 | 实交 delta |
|---|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_locator.dart` | 227 | `ThincoderBuild`、`locateBuild()`（`locate()` 仍返回 `String`）、`runtimeRootOf` 平台规则、内置探测、`versionOf(arguments)`、内置分支的 `--version` 失败态、仅内置分支的 env 注入、启动行 | +152 |
| ② | `lib/kernel/thincoder/thincoder_transport.dart` | 87 | `ThincoderLaunch.arguments`（默认 `[ThincoderLaunch.command]`），`withEnvironment` 同步 | +7 |
| ③ | `lib/kernel/thincoder/thincoder_process_io.dart` | 207 | `arguments` 透传（启动行不在此档，落点见 §26.7） | ±0（+1 / −1） |
| ④ | `tool/build_windows.dart` | 425 | Node 下载校验 + `_putRuntime` + `_thincoderVersion` 两道版本校验 + 必检项 | +183 |
| ⑤ | `tool/baocode.iss` | 342 | `:90-96` 注释补 `runtime\` | +5 / −2 |
| ⑥ | `tool/build_macos.dart` | 631 | 同改点（未验证） | +191 / −2 |
| ⑦ | `test/kernel/thincoder_locator_test.dart` | 新增 | T112–T115（含 a/b 变体）· T117a 的解析与注册表单测 | 426 |
| ⑧ | `test/kernel/thincoder_kernel_test.dart` | 4299 | 启动行断言 + T115a / T115b | +126 |
| ⑨ | `lib/platform/data_dir.dart` | 423 | `thincoderDataDir` 只读访问器（`data_dir.dart:126`）+ `items` 加 `runtime-data`（`:143-148` 是移动 / 清理的条目表，不登记则该目录不随数据夹迁移） | +5 |

- **零改动**：`thincoder_kernel.dart` · `thincoder_protocol.dart` · `thincoder_process.dart`（reap / stop 入口）· `lib/platform/child_process_registry.dart`（按类别登记，键不取可执行文件名，§26.4）· 聊天 UI · Claude 内核面 · `candidates()` 函数体。
- **体量立场（`test/kernel/thincoder_kernel_test.dart` 现 4967 行（2026-10-23 实测），在 >800 名单）**：本批只加用例（启动行断言 + T115a / T115b，+126），不动结构；缝候选沿用 §5.2 已记的测试档四组拆法；触发 = 独立拆分批立项（本批不拆）。
- **delta 口径**：上表 delta = 本批实交的增删行数（`git show` 的 numstat 读数）；现值 = 编制日基线行数，两者不相减、不互校。

**外仓 `thincoder/`（已批准；本批不实施，实施归独立外仓批）**

| # | 坐标 | 现值 | 改动 | delta |
|---|---|---|---|---|
| ① | `thincoder-core/home.mjs` | 新增 | `thincoderHome()` | ≤ +18 |
| ② | `thincoder-core/config-io.mjs` | 288 | `:32` 改调 `thincoderHome()` | ≤ +2 / −1 |
| ③ | `thincoder-core/log.mjs` | 215 | `:58` 改调 | ≤ +2 / −1 |
| ④ | `thincoder-core/agent/dispatch-gates.mjs` | 151 | `:21` 改调 | ≤ +2 / −1 |
| ⑤ | `thincoder-core/skills.mjs` | 234 | `:94` / `:136` / `:217` / `:226` 改调 | ≤ +4 / −2 |
| ⑥ | `thincoder-core/agent/helpers.mjs` | 491 | `:403` 改调 | ≤ +2 / −2 |

合计 ≤ **+30 / −7**（含新档 18 行；**6 档 8 处调用点**）。

### 26.10 关键决策记录

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D107 | 内置形态 = `node.exe` + thincoder 源码树目录，不做单文件 SEA | 判据四条（§26.2）：动态 import、16 处 `import.meta.url` 资产读、postject、体积不省。被否：SEA + bundler（要把上游改成单文件工程） |
| D108 | 内置位置 = 安装目录 `{app}\runtime\` | 只读、随版本替换、卸载带走；被否：应用数据目录（可写区放二进制，升级残留、多用户重复占盘） |
| D109 | 分叉判据 = 「内置在不在」，不引入 release 常量 | 用户 2026-10-21 03:57 逐字；被否：`kReleaseMode` 特判（开发/发行两套解析路径，测试只能覆盖一半） |
| D110 | 显式路径不存在 ⇒ 报错不回落内置 | 今天的形（`thincoder_locator.dart:97-107`）已如此；F23 验收 ④ 就是它 |
| D111 | 数据目录用 env 注入，不改上游默认 | 用户终端副本继续用 `~/.thincoder`，两侧零共享；被否：改 `configDir` 默认值（会改掉所有端的行为） |
| D112 | 外仓改动面 = 6 档 8 处调用点，不是 1 档 | 实测 4 档 7 处绕过 `configDir` 直写 `~/.thincoder`（§26.5）；**批准面 = 这个实测面**（需求档原估「约 3–5 行」偏低，需求档 `:167` 已同步为 6 档 8 处 / ≤ +30 / −7）；被否：只改 `config-io.mjs:32`（logs / tool-errors 仍写用户目录，验收 ③ 不达标） |

### 26.11 用例表（T112–T117，a/b 为变体）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T112 | 无内置（Windows 形态）⇒ 与今天逐字相同 | `executableDirectoryOverride` 指向无 `runtime\` 的临时目录；`PATH=/a;/b` | `candidates(env)` 逐项 == 今天（Windows：`/a\thincoder.cmd`、`/a\thincoder.exe`、`/b\…`、`%APPDATA%\npm\thincoder.cmd`、`.exe`，顺序不变）；`locate()` 返回首个存在的项；`launch().environment` 无 `THINCODER_CONFIG_DIR`（同 T115b） |
| T112a | 无内置（macOS 形态） | `runtimeRootOf('<tmp>/BaoCode.app/Contents/MacOS', isMac: true)`，该树下无 `Resources/runtime/`；`PATH=/a:/b` | runtime 根 == `<tmp>/BaoCode.app/Contents/Resources/runtime`；`candidates(env)` == macOS 今天那 5 类（PATH 各目录 `/thincoder`、`~/.local/bin/thincoder`、`/usr/local/bin/thincoder`、`/opt/homebrew/bin/thincoder`），顺序不变；`locate()` 走 PATH |
| T112b | 半残态 ⇒ 视作无内置 | 临时树只有 `runtime/thincoder/bin/thincoder.cjs`（无 node）；另一组只有 `runtime/node/node.exe`（无 cjs） | 两种都不算内置：`candidatesOverride` 计数桩**被调用**（次数 ≥1）、`locate()` 走 PATH；`launch().environment` 无 `THINCODER_CONFIG_DIR` |
| T113 | 内置存在（Windows 形态）⇒ 屏蔽 PATH | 临时目录造出 `runtime\thincoder\bin\thincoder.cjs` + `runtime\node\node.exe`；`candidatesOverride` 计数桩 | `locateBuild().display` == 该 cjs 绝对路径（`thincoder_locator_test.dart:225-228`）；桩调用次数 **0**；`launch().executable` 以 `node.exe` 结尾、`arguments == [cjs,'acp']`；`throughShell == false` |
| T113a | 内置存在（macOS 形态）⇒ 屏蔽 PATH | `<tmp>/BaoCode.app/Contents/MacOS/`（exe 目录）+ `Contents/Resources/runtime/thincoder/bin/thincoder.cjs` + `Contents/Resources/runtime/node/node`；`isMac: true`；计数桩 | `locateBuild().display` == `<…>/Contents/Resources/runtime/thincoder/bin/thincoder.cjs`、`locate()` == `<…>/Contents/Resources/runtime/node/node`（`thincoder_locator_test.dart:259-260`）；桩调用次数 **0**；`launch().executable` 以 `/node` 结尾、`arguments == [cjs,'acp']` |
| T113b | 内置在但跑不起来 ⇒ 明确失败态 | 内置两件都在位，但 `<runtime>/node/node.exe` 是退出码非 0 的桩（或不可执行文件） | `status()` ⇒ `ThincoderFailed`，消息含内置 node 路径与「内置运行时无法启动」；`locate()` 仍返回内置（判据只看文件在不在）；不抛未捕获异常；**不改走 PATH**（`candidates()` 零调用） |
| T114 | 显式坏路径不回落 | 设置 `thincoder.path = <不存在>`，且内置存在 | 抛 `ThincoderUnavailable`（`status()` ⇒ `ThincoderFailed`，消息含该路径）；不返回内置、不调 `candidates()` |
| T115a | 内置情形注入私有目录 | 内置存在（同 T113）；`DataDirectory.current` 指向临时数据目录 | `launch().environment['THINCODER_CONFIG_DIR'] == DataDirectory.current.thincoderDataDir`（== `<数据目录>/runtime-data/thincoder`）且 `p.isAbsolute` 为真 |
| T115b | 无内置 ⇒ 不注入 | 无内置（同 T112）；另一组设了有效 `thincoder.path` | `launch().environment` **不含** `THINCODER_CONFIG_DIR`；其余键集合与值逐个 == `ClaudeEnvironment.of()`（不新不删不改） |
| T116 | 用户 `~/.thincoder` 不被写（真机） | 发行版安装包；会话前后各跑 §26.5 的 PowerShell 读法 | 两次输出（文件数 + 最大 mtime）逐字相同；私有目录同读法文件数 > 0 且 mtime 前进 |
| T117 | 打包版本一致（对常量） | `dart run tool/build_windows.dart --skip-build`（runtime 已就位）；再把 `_thincoderVersion` 改成别的值跑一次 | 正常跑通过且产物 `--version` == `_thincoderVersion` == 源码树 `package.json.version`；改常量那次必须 `_fail` 并打印两侧值 |
| T117a | 注册表按 `thincoder` 类别登记、换 `node.exe` 仍命中 | 内置情形 `launch()` 起进程后读 `ThincoderProcess.registry.file` 与磁盘内容 | 文件路径以 `state/thincoder-processes.json` 结尾；条目 `pid` == 子进程 pid、`command` 同时含 `thincoder.cjs` 与 `acp`（`_isThincoder` 为真）；`stopThincoderProcesses()` 后该 pid 不再运行（POSIX 上另验 `reapThincoderProcesses()`；Windows 的 `_reap` 按 `child_process_registry.dart:57` 直接返回，回收走 `_live`） |

### 26.12 验收对照（回指 F23 验收 ①–⑤）

| 需求判据 | 本档落点 | 机制 | 机检 |
|---|---|---|---|
| ① 未装 node/npm/thincoder 的机器可用 | §26.1 / §26.8 | 安装包内含 node.exe + 源码树；`@` / Auto / rewind / 回退 / 队列本就在 CLI 侧（F1–F15） | 干净机走查 + T116 私有目录有写；`events.log` 启动行点名内置路径 |
| ② 启动行点名内置绝对路径、不出现 PATH 候选 | §26.3 / §26.7 | 内置存在 ⇒ 不调用 `candidates()`；启动行打绝对路径 | T113（桩零调用）+ `events.log` 读行 |
| ③ 用户 `~/.thincoder` 文件数与 mtime 不变 | §26.5 | 内置分支注入 `THINCODER_CONFIG_DIR` + 外仓 6 档 8 处改调；**前置 = 外仓批已落地**（本批只交付注入面，读取方在外仓） | T116（PowerShell 两读数逐字相同）；注入侧由 T115a 先钉 |
| ④ 显式坏路径明确报错、不静默回落 | §26.3 / §26.4 | 今天的 `:97-107` 分支原样保留，内置层插在其后 | T114 |
| ⑤ `flutter run` 走 PATH、行为与今天一致 | §26.6 | 无 `runtime/` ⇒ PATH 分支；**不注入** `THINCODER_CONFIG_DIR`；候选列表零改；无 release 常量 | T112 / T112a（候选逐项相等）+ T115b（环境逐键相同）+ 本仓 `flutter test` 全绿 |

### 26.13 边界（本批不做）与回滚单位

**不做**：接管用户终端 / 改 PATH / 写 `~/.thincoder` · 内置副本独立升级（随应用版本走） · 单文件 SEA（D107） · 活会话跨端（#36） · 上游发布流程 · macOS 的本机验证（见 §26.14） · 「关于」页的许可引用面（§26.8）。

**收口依赖：F23 需两批齐**

- 前置于外仓批：验收 ①（私有目录真有写）与 ③（用户 `~/.thincoder` 不变）——本批只交付注入面，读取方（`thincoderHome()` 的 8 处）与 T116 在外仓批。
- 本批内可验收：②（屏蔽 PATH + 启动行）· ④（显式坏路径不回落）· ⑤（`flutter run` 走 PATH、不注入、与今天一致，含需求档 `:169` 的互通面）。

**回滚单位（三处各自独立、互不依赖）**

1. **打包改动**（`build_windows.dart` / `baocode.iss` / `build_macos.dart`）：回退后安装包不含 `runtime\` ⇒ locator 自动走 PATH，其余行为不变。
2. **locator 改动**（`thincoder_locator.dart` / `thincoder_transport.dart` / `thincoder_process_io.dart`）：回退后解析回到「显式 → PATH」，即使包里仍带 `runtime\` 也不会被使用。
3. **外仓改动**（独立仓、独立提交）：回退后 `THINCODER_CONFIG_DIR` 被忽略，数据回到 `~/.thincoder`——**必须与内置副本同时回退**才安全（只回退外仓会在用户目录生成新会话，不破坏数据但会写用户目录）。

### 26.14 未验证项（单列，不静默省略）

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U7 | macOS 打包与派生规则（`codesign` 子进程、双架构 node、`Contents/Resources` 执行位、`runtimeRootOf` 的 macOS 分支） | **设计已给、未验证**（本机 Windows；`isMac: true` 的单测只证规则写法，不证真机包结构） | 实施轮在 Mac 上验证：`BaoCode.app/Contents/Resources/runtime/thincoder/bin/thincoder.cjs` 与 `…/runtime/node/node` 都在位且探测命中；签名被拦 ⇒ 按 §26.8 的 `codesign --force --sign -` 与 hardened runtime 排查；包结构不符 ⇒ 只改 §26.4 的 `runtimeRootOf` 一处 |
| U8 | 安装包体积增量 | 未打包实测（仅未压缩 ≈ 92.5 MB + 现值 21.0 MB） | 实施轮 `dart run tool/build_windows.dart` 后回填实际 MB |
| U9 | `skills.mjs:136` 是否写用户 skills 目录 | 未逐行核 | 外仓实施轮首轮核；写 ⇒ 同批改调 `thincoderHome()` |
| U10 | token / 凭据的具体文件名 | 未逐档核实（落在 `configDir` 域内） | 不影响设计（随 `configDir` 迁移）；实施轮核一次并补 §26.5 表 |
| U11 | SEA 整链（blob 注入 + 运行） | 未尝试（判据已足，D107） | 仅当将来要单文件时按 §26.2 步骤验 |

## 27. 模型配置面（批 18；F24）

> 回指：需求档 F24 功能点 ①–⑥ / 验收 ①–⑥ / 边界（`docs/requirements/thincoder-adapter.md:171-177`）。
> 一句结论：模型清单仍只由 CLI 投射（零新协议）；baocode 新增「设置 → 模型（thincoder）」页，
> 写入**内核实际读的那份** `config.json`（只动 `providers[]` 与顶层 `defaultModel`，原子写 + 回读），
> 保存后由用户点一次「重开会话」拿到新模型。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：**设置里的 thincoder 行**（`general_page.dart:443-458` 的 `SettingsGroup(title: 'thincoder')` + `:803-857` `_ThincoderPathSetting`）——同一板块的入口形、字面文案、状态行沿用这一形。
- 对齐 ②：**供应商表单控件**（`models_page.dart:2084-2173` 的 `_Field`，含 `obscure` 遮显参数）——本页四个输入框用同一控件形，密钥框 `obscure: true`。
- 对齐 ③：**原子写语义**（外仓 `thincoder-core/config-io.mjs:59-89` `writeConfigAtomic`：stat→read 序、mtime 冲突放弃、`.bak` 留现场、0600）——Dart 侧逐条照搬判据，不新造。
- 偏离 ①：**不加新协议**。现有 ACP 方法面（`handlers-session.mjs:2-5`）没有「重读配置」入口，`config_option_update` 只是现值通知；可见性靠重开会话（§27.6）。
- 偏离 ②：**原因串不随 `configOptions` 传输**——`sessionConfigOptions` 只 push model / thinking / thinkingLevel / mode / autoApprove 五类项，`model` 项在模型不可解析时直接缺席，条目上没有原因字段（`thincoder/thincoder-cli/src/acp/handlers-session.mjs:47-68`）；
  原因串只在 `session/new` 凭据门的 `AUTH_REQUIRED` 错误串里出现（`keyPresent && !ok` 一路，`st.reason` 逐字进 message，`:186-187`）。宿主侧也读不到它：`defaultModelReason` 只出现在 core（`model-ref.mjs:69-77`，被 `config.mjs:303` 消费），本仓 `lib/**` 零命中。
  故页面按**同一判据复述**两条串（§27.5 ④）；「CLI 是否另有投影面」= U13，已按本条实读闭合（§27.12）。
- 对齐 ④：**外仓 desktop / VSC 的 provider 编辑面**（坐标均在 `thincoder/` 仓内）——写面纪律 = 配置读写只经核 `config-io.mjs`、端侧零自写盘零形状构造、`provider:*` 四通道
  （`thincoder/thincoder-desktop/src/main/providers.mjs:1-31`；`thincoder/docs/desktop/design/SETTINGS.md:15` KD-10；`thincoder/docs/desktop/design/IPC.md:297-300` 的 `provider:list` / `save` / `remove` / `verify` 家族）。
  字段构造与遮罩口径对齐它：遮罩单点 `maskKey`、行面只回遮罩后值、明文 key 零下发；本页同形（末四位）。
- 偏离 ③：**Dart 侧自造 provider 形状与遮罩**。外仓的写面是「核唯一执行体（`writeConfigAtomic`）+ 端侧只给 mutate」（KD-10）；baocode 宿主没有 node 通道、且要在 CLI 子进程之外写用户配置，`config-io.mjs` 不可调（本批不改外仓）⇒ 条目形状与 `defaultModel` 复合串必须由宿主自己构造。遮罩判据仍照外仓口径（末四位），不新造第二套判据。

**survey 证据**：本轮未调公开检索（`websearch` / `fetch` 未发起）——判据全部来自本仓与外仓实读。

外仓 provider 口径以 `thincoder-core/config.mjs:1-12` 头注为单一来源；编辑面的写面纪律与遮罩判据以 `thincoder/thincoder-desktop/src/main/providers.mjs:1-31`、`thincoder/docs/desktop/design/SETTINGS.md:15`、`thincoder/docs/desktop/design/IPC.md:297-300` 为坐标（对齐 ④ / 偏离 ③）。

### 27.1 决议总表

| 面 | 决议 |
|---|---|
| 清单来源 | 沿用 ACP `configOptions.model` / `config_option_update`；`thincoder_choices.dart:46-53` 只投影，零改 |
| 设置页 | 新增 `SettingsSection.thincoderModels`（导航项「模型（thincoder）」，排在 `models` 之后）+ 新页 `lib/settings/pages/thincoder_models_page.dart` |
| 写入目标 | `THINCODER_CONFIG_DIR`（非空，来源 = `ThincoderLocator.environment`，§27.2）→ 否则 `~/.thincoder/config.json`；解析函数在 `lib/kernel/thincoder/thincoder_config_file.dart` |
| 写入形状 | stat `t0` → 读 → 解析 → 校验并合并 → 重取 `t1`（冲突则零写 + `config.json.bak-<ts>`）→ 临时文件 + 替换（失败回退直写）→ chmod → 回读断言 |
| 只动键 | `providers[]`（追加，或按 `name` 合并条目上的三个字段）与顶层 `defaultModel` |
| 可见性 | 保存后由用户点「重开会话」⇒ `ThincoderKernel.restart()`（`thincoder_kernel.dart:563-568`）；不自动重启 |
| 密钥 | 表单遮显；保存后只显示末四位；日志与 `events.log` 不出现 key |

### 27.2 写入目标解析（与 F23 同一判据）

新增 `lib/kernel/thincoder/thincoder_config_file.dart`（≈ 90 行）：

```dart
/// The directory the CLI reads its config from: THINCODER_CONFIG_DIR when
/// set, else ~/.thincoder (thincoder-core/config-io.mjs:32).
String resolveThincoderConfigDir(Map<String, String> environment) {
  final named = environment['THINCODER_CONFIG_DIR']?.trim() ?? '';
  return named.isNotEmpty
      ? named
      : p.join(AppPaths.home(environment), '.thincoder');
}

File thincoderConfigFile(Map<String, String> environment) =>
    File(p.join(resolveThincoderConfigDir(environment), 'config.json'));
```

- **环境来源**：`Future<Map<String, String>> Function() thincoderEnvironment`（`thincoder_config_file.dart:32-33`），默认 = `ThincoderLocator.environment`——就是 `launch()` 启动子进程用的那一份 environment（同一 `_withDataFolder`，§26.5），内置副本在 ⇒ 带着私有 `THINCODER_CONFIG_DIR`。页面与子进程因此读写同一个文件，解析函数零改。
- **判据一句话**：写的那份 == 子进程环境里解析出来的那份；不引入发行 / 开发开关。
- **与 CLI 逐字同判据（不展开 `~`）**：CLI 的 `thincoderHome` = `env.THINCODER_CONFIG_DIR?.trim() || join(homedir(), ".thincoder")`（`thincoder-core/home.mjs` 的形；今天是 `config-io.mjs:32`）——env 值原样使用、不做路径展开；本函数同形：给同一 environment，两侧算出同一个字符串。被否：多加一层 `~/` → 主目录展开（CLI 不展开 ⇒ 本档自己的判据在 shell 导出 `~/…` 时失效）。
- **两种初值**：目录不存在 ⇒ 读作空配置（`{}`），写时 `createSync(recursive: true)`；文件不存在 ⇒ 读作 `{}`，写时新建（与 `config-io.mjs:64-72` 的 `text === null ⇒ raw = {}` 同形）。
- **非法 JSON** ⇒ 拒绝写、原文件零改动（同 `config-io.mjs:68-71` 的 throw 语义，转成页面错误态）。
- **默认路径的取值**：内置副本在 ⇒ `<数据目录>/runtime-data/thincoder/config.json`；开发 / PATH / 显式路径 ⇒ `~/.thincoder/config.json`（§26.5 两支）。

### 27.3 写入形状（写前读 → 合并 → 并发门 → 原子写 → 回读）

新增 `lib/kernel/thincoder/thincoder_config_store.dart`（≈ 200 行）：

```dart
class ThincoderConfigStore {
  ThincoderConfigStore({required this.file});
  final File file;

  Future<ThincoderConfigDocument> read();   // 缺文件 ⇒ 空文档（exists == false）
  Future<ThincoderSaveResult> saveProvider({
    required String name,
    required String baseURL,
    required String apiKey,   // 空串 = 保留原值（编辑态）
    required String model,
  });
}
```

| # | 步骤 | 判据 |
|---|---|---|
| 1 | `t0 = file.statSync().modified`（文件缺失 ⇒ `null`） | stat 先于 read（安全方向，`config-io.mjs:60-64` 同序）；`t0` 是并发门的基线 |
| 2 | `readAsStringSync`；文件缺失 ⇒ 读作空配置（`{}`） | 与 `config-io.mjs:64-72` 的 `text === null ⇒ raw = {}` 同形 |
| 3 | 解析；非 Map / 非法 JSON ⇒ `invalidJson`，零写 | 页面错误态「配置文件不是合法 JSON：<path>」；本步不触碰磁盘 |
| 4 | 校验四个输入（§27.4；不满足 ⇒ `invalidField`，零写）→ 合并：`providers = raw['providers']`（非数组 ⇒ `[]`）；按 `name` 找条目。找到 ⇒ 只写 `baseURL`（去尾部 `/`，同 `config-io.mjs:152` 归一）与 `apiKey`（**空串 ⇒ 保留原值**），条目上其它键（`format` / `proxy` / `context` / `maxTokens`）原样保留，`model` 键若在则删（退役字段，`config-io.mjs:154` 运行期即删）；未找到 ⇒ 追加 `{name, baseURL, apiKey}`。最后 `raw['defaultModel'] = '$name:$model'` | 除 `providers` 与 `defaultModel` 外零键变动；所有校验都在写盘前完成 |
| 5 | 重取 `t1 = file.statSync().modified`（缺失 ⇒ `null`） | 与第 1 步同一读法；这是并发门的唯一判定点，位于任何写盘动作之前 |
| 6 | `t0 != t1` ⇒ **零写**：不建临时文件、不动目标文件，把**当前磁盘内容**复制为 `config.json.bak-<ts>` 后返回 `conflict`（同 `config-io.mjs:77-78`）；相等 ⇒ 继续第 7 步 | 并发改配置 ⇒ 提示重试、不吞对端新值；`.bak-<ts>` = 冲突现场，只在这一路产生副本 |
| 7 | 写同目录临时文件 `config.json.tmp-<pid>-<ts>`（内容 = `JSON.stringify(raw, null, 2) + '\n'`，UTF-8 无 BOM；`flush: true`）→ `rename` 覆盖目标；`rename` 抛（Windows 锁 / 跨卷）⇒ 删临时文件后直写目标 | 不留半截文件；序列化形状与 `config-io.mjs:83` 同形（2 空格缩进 + 末尾换行 + UTF-8） |
| 8 | POSIX：`Process.run('chmod', ['600', path])` 尽力而为，失败不阻断；Windows 跳过 | 与 `config-io.mjs:83-84` 同义 |
| 9 | 回读：重新 `read`，断言 `defaultModel == '$name:$model'` 且该条目存在、`apiKey` 与预期一致（编辑态留空 ⇒ 与原值相同）；不等 ⇒ `verifyFailed` | 回读断言失败按错误展示，不刷成成功态 |
| 10 | 成功 ⇒ 返回新文档，页面就地刷新列表 | 页面无需再读盘 |

**「其它键逐字不变」的可机检读法**

单测（T120）用规范化比较：删掉 `providers` 与 `defaultModel` 后，其余部分递归按键名排序、无空白地编码，前后逐字相等。

```dart
String rest(Map<String, dynamic> raw) {
  final copy = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>
    ..remove('providers')
    ..remove('defaultModel');
  return canonicalJson(copy); // 递归排序键名 + 无空白
}
// 断言：rest(before) == rest(after)
```

不依赖 Dart 的人工读法（保存前后各跑一次，两行输出逐字相同；`<config.json>` 替换为实际路径）：

```
node -e "const r=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));delete r.providers;delete r.defaultModel;console.log(JSON.stringify(r,null,1))" <config.json>
```

### 27.4 字段口径（以 `thincoder-core/config.mjs:1-12` 头注为准）

| 口径 | 证据 | 本设计的落法 |
|---|---|---|
| `providers[].apiKey` 是唯一密钥源，环境变量不是 | `config.mjs:11` | 表单只写 `providers[].apiKey` |
| `providers[].model` 已退役（渠道不携模型） | `config.mjs:3-6`；运行期删除 `config-io.mjs:153-154` | 「模型名」写进顶层 `defaultModel`，不写进 provider 条目 |
| `defaultModel` = 顶层 `"provider:model"` 复合串 | `config.mjs:6-8`；解析见 `model-ref.mjs` 的 `parseModelRef` | `defaultModel = '<name>:<model>'` |
| provider 条目的可选字段与格式判据 | `config-io.mjs:244-253`（`format` 缺省 `openai`，非 openai 才落键；`baseURL` 必填） | 表单不收 `format`；更新已有条目时保留其原值（§27.3 第 4 步） |
| 渠道名重复的处理 | `config-io.mjs:247`（`Name "…" is already in use`） | 同名 ⇒ 走「更新」分支，页面明示「将更新已有供应商」，不静默覆盖 |
| `name` 校验（新增 / 改名） | `config-io.mjs:149`（无名 / 空名条目在读取时被过滤）、`:169` / `:172`（`defaultModel` 在首个 `:` 处切开，切出的 provider 名不匹配 ⇒ 静默回退首渠道） | 保存前校验：trim 后非空、不含 `:`；不满足 ⇒ `invalidField`，零写（不落一个会被 CLI 过滤掉的条目） |
| `baseURL` 校验 | `config-io.mjs:248-249`（`baseURL` 必填）、`:152`（去尾部 `/`） | 保存前判 trim 后非空（不满足 ⇒ `invalidField`）；写盘前按 `:152` 去尾部 `/` |
| `model` 校验 | `defaultModel` 是 `"provider:model"` 复合串，解析在首个 `:` 处切开（`config-io.mjs:169` / `:172`）⇒ 缺 model 时文件里留下 `name:`，CLI 读作无模型 | 保存前判 trim 后非空，不满足 ⇒ `invalidField`、零写（否则 `defaultModel` 会写成 `name:`，页面还报「已保存」） |
| `providers` 非数组 | `config-io.mjs:149`（读侧按数组逐项处理） | 读到的 `providers` 非数组 ⇒ 合并时按 `[]` 处理，页面提示「providers 不是数组，已按空列表处理」 |

**「我们写的文件 CLI 读得进」怎么验证**（离线 + 真机两条）

1. **离线固件**：用本写入器产出 `config.json`，跑 `node -e "import('thincoder/thincoder-core/config-io.mjs').then(m=>console.log(JSON.stringify(m.resolveProviders())))"`，读回 `providers` 各字段与 `activeProvider` 与写入一致（T125）。
2. **真机**：写后开一个 thincoder 会话，ACP 首包的 `configOptions` 出现 `id: "model"` 项且 `currentValue == '<name>:<model>'`（判据 = `handlers-session.mjs:49-53` 的 push 条件成立）。无 CLI 环境时按 U14 处置。

### 27.5 UI 面：设置 → 模型（thincoder）

**导航接线**

- `SettingsSection` 增 `thincoderModels`（`settings_dialog.dart:26-43`），排在 `models` 之后（`SettingsCategory.preferences`，`:48-63`）。
- 图标（`:238-256`）用 `Codicons.serverProcess`；label / keywords（`:266-300`）与文案面归 #7 一次覆盖，本批取字面串「模型（thincoder）」，与 `general_page.dart:445` 的 `'thincoder'` 同形。
- `app_settings.dart:153-236` 增一个 case，返回 `ThincoderModelsSettingsPage`。

**页面结构**（`thincoder_models_page.dart`，≈ 420 行）

| 区 | 内容 | 显隐判据 |
|---|---|---|
| ① 配置位置 | 解析出的 `config.json` 绝对路径 + 「存在 / 新建」；只读一行 | 常显（这是「写到哪」的唯一说明） |
| ② 当前模型 | 活的 thincoder 会话投射的 `currentValue`（`thincoder_choices.dart:46-53` 同一投影）；无活会话 ⇒ 「打开一个 thincoder 会话后这里显示 CLI 给的模型」 | `probe() != null` |
| ③ 候选列表 | `configOptions.model` 的 `options`（CLI 后台拉到的清单）；拉到 ≤ 1 项 ⇒ 只出当前值一行 + 「刷新」按钮（重开会话） | 有活会话即显示（与 ② 同判据 `probe() != null`） |
| ④ 空态 | 两句引导：「添加一个供应商」/「在你自己的终端里配好后回来点刷新」，并显示原因串：无 provider ⇒ 「未配置任何 provider」；有 provider 无 `defaultModel` ⇒ 「defaultModel 未设置」 | `providers` 空，或 `defaultModel` 空 |
| ⑤ 供应商列表 | 每行：名字、baseURL、密钥末四位（`••••1234`）、模型（`defaultModel` 指向它时）；行操作「编辑」 | `providers` 非空 |
| ⑥ 添加 / 编辑表单 | 四个输入：名字、Base URL、API Key（`obscure: true`）、模型名；「保存」按钮 + 行内错误。编辑态密钥框留空 = 保留原值 | 点「添加供应商」或行「编辑」 |
| ⑦ 错误态 | 五种：`invalidJson` / `invalidField` / `conflict` / `ioError` / `verifyFailed`，各一句可读文案 + 路径；不吞异常 | 保存返回非 ok |

- **「设为默认」不做**：默认模型只在 ⑥ 保存时置位（`defaultModel = '<name>:<model>'`）——条目上无模型名可合成该串（`providers[].model` 已退役，§27.4），行级动作会变成一次隐式写盘。

- **密钥规则（敏感面）**：输入框 `obscure: true`（`models_page.dart:2164` 同形）；保存成功后输入框清空，行上只显示末四位；写入器与页面都不调 `appEvent` 带 key，`events.log` 不出现 key（边界见 §27.11）。
- **与会话内 pill 的关系**：设置页写磁盘，pill 显示会话内投影（§2 的 `SelectsModel`）——两者不同步是设计的正常态。因此保存成功后页脚固定一行：「已保存。重开会话后，模型选项才会更新。」+ 按钮「重开会话 thincoder」。

### 27.6 保存后的可见性闭环（三选一：重开会话）

| 候选 | 可行性（实读判据） | 结论 |
|---|---|---|
| 触发 `config_option_update` | 该通知只是**现值投影**（`sessionConfigOptions` 单源，`handlers-session.mjs:39-46`）；运行中的 agent 在 `session/new` 时已装配 `providers`（`handlers-session.mjs:98-105` 注释：清单来源 = `agent.providers`），不重读磁盘；ACP 方法面没有「重读配置」（`:2-5`），新造 = 改外仓（本批禁止） | ❌ |
| 下次会话生效 | 事实成立（每次 `session/new` 重新装配），但保存后当前会话零反馈，用户会以为没生效 | ❌ 不可感知 |
| **重开会话** | 现有入口 `ThincoderKernel.restart()`（`thincoder_kernel.dart:563-568`：`_teardown()` → `prepare()` = 新进程 + 新 `session/new`）；聊天面已有 `ChatSession.restart()`（`chat_session.dart:398`） | ✅ **选它** |

**交互定案**：保存成功后**不自动重启**——自动重启会掐断正在跑的回合，与 F21（回合在飞时切换不丢请求）的语义冲突；页面给一行提示 + 一个按钮。用户不点 ⇒ 新会话（切走再回来 / 新建）自然生效。

### 27.7 用例表（T118–T130）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T118 | 空配置读 | 文件不存在；目录不存在 | `read()` ⇒ `providers` 空、`defaultModel == null`、`exists == false`；不创建任何文件 |
| T119 | 新建供应商 | `{}` 起步 + 四字段 | 文件出现 `providers:[{name,baseURL,apiKey}]`、`defaultModel == "name:model"`；回读断言通过；无旧文件 ⇒ 无 `.bak` |
| T120 | 其它键逐字不变 | 预置 `{agent:{…}, subagentModels:{…}, providers:[{name:"x",apiKey:"k",format:"anthropic",proxy:true}], defaultModel:"x:m", $schema:"…"}` + 新增一条 | `rest(before) == rest(after)`；`x` 条目的 `format` / `proxy` 原样保留 |
| T121 | 更新已有供应商 | 同名条目 + 新 baseURL / apiKey / model | 条目数不变；三字段更新；条目上的 `model` 键若在则消失；`defaultModel` 更新 |
| T122 | 写失败（只读目录） | 目录只读（POSIX `chmod 0500`）/ 父路径不可建 | `ioError`；原文件字节不变、仍可读；无 `.tmp` 残留；不生成任何 `.bak` / `.bak-<ts>`（零写） |
| T123 | 非法 JSON | 文件内容 `{not json` | `invalidJson`；文件字节不变；零写；不生成任何 `.bak` / `.bak-<ts>` |
| T124 | 写入目标解析 | env `THINCODER_CONFIG_DIR=<tmp>`；另一组无该键 | 前者目标 == `<tmp>/config.json` 且 `~/.thincoder` 的 `modified` 前后相同；后者 == `~/.thincoder/config.json` |
| T125 | CLI 读得进（离线固件） | 写入器产物 + `node -e` 调 `resolveProviders()` | `providers` 各字段与写入一致、`activeProvider == name`（无 node 环境 ⇒ 记 U14） |
| T126 | 保存后的可见性（宿主链路） | 写入后 `restart()`（mock 对端） | 证明的是「翻译 / 投影 + `restart()` 后新会话拿到清单」：新会话 `configOptions` 出现 `id:"model"`、`currentValue == "name:model"`；候选含该值。**不**证明「文件 → CLI → ACP」；用例形 = `test`（`thincoder_kernel_test.dart:4553`），不是 `testWidgets`——`settle()` 在 `testWidgets` 下死锁（实测 10 分钟超时） |
| T127 | 密钥不回显 / 不落日志 | 保存后读页面状态与 `events.log` | 行上只有末四位；`events.log` 全文不含完整 key |
| T128 | 并发冲突（零写 + 留现场） | 首次 stat 之后、写盘之前从外部改写目标文件（stat 缝：第二次返回不同 mtime） | `conflict`；目标文件字节 == 对端写入内容（本次零写）；存在 `config.json.bak-<ts>` 且内容 == 冲突时的磁盘内容；无 `.tmp` 残留；无滚动 `config.json.bak` |
| T129 | 回读失败 | 写入成功后向读回缝注入被改写的内容（如丢掉 `defaultModel`） | `verifyFailed`；页面显示错误、不刷成成功态；文件内容 = 本次写入的内容（回读只核对、不回滚） |
| T130 | 字段校验（零写） | `name` 空 / `name` 含 `:` / `baseURL` 空 / `providers` 非数组 | 前三项 ⇒ `invalidField`，文件字节不变，无 `.bak` / `.bak-<ts>` / `.tmp`；末项 ⇒ 按 `[]` 合并后正常写盘，页面提示「providers 不是数组」 |

**可见性判据的分工**：`文件 → CLI → ACP` 这条链由 T125（离线固件，核 `resolveProviders` 读回）+ 真机（U14）证明；T126 的 mock 对端只覆盖宿主链路（翻译 / 投影 / `restart()`），两者不混成一条。

### 27.8 验收对照（回指 F24 验收 ①–⑥）

| 需求判据 | 本档落点 | 机制 | 机检 |
|---|---|---|---|
| ① 全新配置 ⇒ pill 不出现、设置页空态 + 原因串 | §27.2 / §27.5 ④ | 空文件读作 `{}` ⇒ 内核 `agent.provider.model` 空 ⇒ `handlers-session.mjs:51` 不 push model 项 | T118 + 真机开新配置会话看 pill 缺席（`thincoder_choices.dart:49-50` 空列表） |
| ② 填一个供应商 ⇒ 文件出现条目与 `defaultModel`，其它键逐字不变 | §27.3 | 读 → 合并 → 原子写 → 回读 | T119 / T120 / T121 |
| ③ 会话内 pill 出现该模型并可选中 | §27.6 | 重开会话 ⇒ 新 `session/new` 重新装配 providers | T126 + 真机点选一次 |
| ④ 写失败明确报错、不留半截文件：只读目录 / 非法 JSON / 字段不合法三路为零写（原文件字节不变、可读），并发冲突路零写且留 `config.json.bak-<ts>` 现场 | §27.3 第 3 / 4 / 6 / 7 / 9 步 | 非法 JSON 零写；字段不合法零写；并发冲突零写 + `config.json.bak-<ts>`；临时文件 + 替换；回读断言 | T122 / T123 / T130 / T128 / T129——三路零写由 T122 / T123 / T130 断言（无副本、无 `.tmp` 残留）；`.bak-<ts>` 现场只由冲突用例 T128 断言 |
| ⑤ `THINCODER_CONFIG_DIR` 指向临时目录 ⇒ 写临时目录，`~/.thincoder` mtime 不变 | §27.2 | 解析函数按 env 决定 | T124（`~/.thincoder` 的 `modified` 前后相同）+ 真机读法同 §26.5 的 PowerShell |
| ⑥ debug 与发行一致（无开关） | §27.2 | 解析函数零 `kReleaseMode`、零开关、零默认值分叉 | T124 在 `flutter test` 与真机走同一函数；`grep kReleaseMode` 该文件零命中 |

### 27.9 受影响文件清单（现值 = 编制基线；实交 delta = 2026-10-22 读数）

| # | 坐标 | 现值（编制基线） | 改动 | 实交 delta |
|---|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_config_file.dart` | 新增 | 解析函数 + 环境来源缝（默认 `ThincoderLocator.environment`，§27.2） | +30 |
| ② | `lib/kernel/thincoder/thincoder_config_store.dart` | 新增 | 读 / 合并 / 原子写 / 回读 | +496 |
| ③ | `lib/settings/pages/thincoder_models_page.dart` | 新增 | 七区页面（§27.5） | +579 |
| ④ | `lib/settings/settings_dialog.dart` | 841 | enum + 图标 + label + keywords 四点 | +10 |
| ⑤ | `lib/settings/app_settings.dart` | 290 | `buildPage` 一个 case + 依赖接线 | +32 |
| ⑥ | `test/kernel/thincoder_config_store_test.dart` | 新增 | T118–T125 · T128–T130 | +540 |
| ⑦ | `test/settings/thincoder_models_page_test.dart` | 新增 | 空态 / 错误态 / 遮显（T127） | +386 |
| ⑧ | `test/kernel/thincoder_kernel_test.dart` | 4299 | T126（宿主链路：写入后 `restart()`，末尾追加一个 `test`） | +70 |
| ⑨ | `lib/kernel/thincoder/thincoder_mock.dart` | 720 | 清单外：`currentModel` | +9 / −1 |
| ⑩ | `test/settings/settings_entry_test.dart` | 484 | 清单外：滚动 | +4 / −1 |

- **零改动**：`thincoder_choices.dart` · `thincoder_kernel.dart` · `chat_session.dart` · 外仓 `thincoder/**` 全部 · 需求档 · l10n 资源档（本批字面串，归 #7）。
- **体量立场（`settings_dialog.dart` 841 行，已过 >800 硬顶）**：本批只加四点（enum / 图标 / label / keywords），不动结构；缝候选 = `SettingsSection` 与页构造映射族（`settings_dialog.dart:26-43` / `:48-63` / `:238-256` / `:266-300`）；触发 = 独立拆分批立项（本批不拆）。
- **体量立场（`test/kernel/thincoder_kernel_test.dart` 现 4967 行（2026-10-23 实测），在 >800 名单）**：本批只在末尾追加一个 `test`（T126，+70），不动结构；缝候选沿用 §5.2 已记的测试档四组拆法；触发 = 下一次结构级触碰或独立拆分批立项（本批不拆）。

### 27.10 回滚单位（三处各自独立）

1. **UI**（`thincoder_models_page.dart` + `settings_dialog.dart` + `app_settings.dart` 接线）：回退后导航项与页面消失，配置文件零影响。
2. **写入器**（`thincoder_config_store.dart`）：回退后没有写盘路径，页面不能保存；磁盘内容不变。
3. **解析**（`thincoder_config_file.dart`）：回退后回到 `~/.thincoder` 硬路径；F23 实施前无行为差异。

### 27.11 边界（本批不做）

不建本地模型目录；不做多供应商并行探测；不自动重开会话；不改外仓。

- **密钥不进系统凭据库**：与 CLI 一致，明文在 `config.json`，0600 尽力而为。
- **不做滚动 `.bak`**：每次保存不产生额外明文副本，只在并发冲突时按先例留一份 `config.json.bak-<ts>`（同 `config-io.mjs:78`）。
- **不接管用户终端其它配置键**：写入面只有 `providers[]` 与 `defaultModel`。
- **不做供应商删除**：删除会牵出 `cascadeRemoveProvider` 的 `consultModels` / `subagentModels` / `advisor.provider` 连带面（`config-io.mjs:178-196`，属代理配置），本批不碰——用户仍可在终端删。

### 27.12 未验证项（单列，不静默省略）

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U13 | CLI 是否在别处把 `defaultModelReason` 投影给客户端（`session/new` 回包 / 通知） | **已闭合**（实读）：原因串**不**投影进 `configOptions`——`sessionConfigOptions` 只出 model / thinking / thinkingLevel / mode / autoApprove 五类项，`model` 项在模型不可解析时直接缺席，条目上没有原因字段（`thincoder/thincoder-cli/src/acp/handlers-session.mjs:47-68`）；原因串只出现在 `session/new` 凭据门的 `AUTH_REQUIRED` 错误串里（`keyPresent && !ok` 一路，`st.reason` 逐字进 message，`:186-187`；串的源头 = `thincoder-core/config.mjs:303` 的 `plan.reason ?? defaultModelReason(...)`） | 无宿主改动：页面继续按同判据复述两条串（§27.5 ④）。机检判据：`grep -n "reason" thincoder/thincoder-cli/src/acp/handlers-session.mjs` ⇒ `:47-68` 内零命中（其余命中 = `:163` / `:165` / `:166` / `:168` 的注释、`:187` 的 `AUTH_REQUIRED` 分支、`reasoningEffort` 族） |
| U14 | 「CLI 读得进我们写的配置」真机 | 未验证（本机无 CLI 会话在本批内跑） | T125 离线固件先挡；发行版走查再验一次（开新会话看 `configOptions.model`） |
| U15 | `app_settings` 取「活的 thincoder 会话」的现有访问器名 | 未逐行核（`workspace` 侧） | 实施首轮核定；本档只定缝形（`probe()` 返回 `KernelChoiceSource?`），不改语义 |
| U16 | Windows 上 Dart `File.rename` 覆盖已存在文件的语义 | 文档未核 | 实施首轮一条单测钉住；失败即走 §27.3 第 7 步的直写回退 |






## 28. 批 22：改名同步与 `/` 命令面（台账 #146）

> 回指：需求档 `docs/requirements/thincoder-adapter.md` §10 的 2026-10-22 19:37 裁定（「我们主要用的是thincoder，所以新功能要适配一下」）。
> 一句结论：改名同步由**内核在 `session/set_title` 确认后发 `SessionRenamed`**；`/` 命令面**对 thincoder 隐藏**——判据 = 内核是否提供命令源（实现 `ProvidesCommands`），与候选表是否为空无关：thincoder 没有源 ⇒ 行首 `/` 不弹面板；Claude 有源 ⇒ 命令表未到 / 表空 / 查询无匹配时面板都照开（T139 钉住）。

**最近先例（对齐 ∥ 偏离及理由）**

- 对齐 ①：**事件发在确认处**。Claude 内核只在 CLI 回话（`session_title_changed`）之后才发 `SessionRenamed`（`lib/kernel/claude_code/claude_code_kernel.dart:1696-1706`）；本批同形：`session/set_title` 成功后才发，失败不发。
- 偏离 ①：**不建 `_sentTitles` 队列**。Claude 的写入会自己回显，要用队列把回显认出来（`claude_code_kernel.dart:279-283`、`:1700-1705`）；thincoder 的写入是单通道串行（`_pumpTitle` 一次一条，`lib/kernel/thincoder/thincoder_kernel.dart:1374-1408`）、自己的写入不回显 ⇒ 一个 `_titleConfirmed` 短路就够，队列是多余的第二真相。
- 对齐 ②：**宿主现有的两条改名路不动顺序**（`lib/workspace/workspace.dart:2776-2789`）：没开的会话仍由 catalog 的 Future 驱动（`:2781-2788`）。

**survey 证据**：本轮未调公开检索（`websearch` / `fetch` 均未发起）——判据全部来自本仓实读与需求档 §10。

### 28.1 决议总表

| 面 | 决议 |
|---|---|
| 改名同步 | `ThincoderKernel._pumpTitle` 在 `session/set_title` 成功后 `emit(SessionRenamed(nextSeq, target))` |
| 失败路径 | 抛错 ⇒ 零事件、零列表改动；只留既有的 `error:title` 提示（`thincoder_kernel.dart:1402-1403`） |
| 列表更新时机 | 宿主对「内核会确认的改名」不再乐观改标题：等 `SessionRenamed` 到 `workspace._sync`（`workspace.dart:2270`）再改 |
| 「会不会被确认」的判据 | 新增能力接口 `ConfirmsRename.renameConfirmed`（只 thincoder 实现）；判据 = 槽在 ∧ 连接活着 ∧ 未在释放（§28.3）。判据为假 ⇒ 走今天的路径，故它误判只损失新行为、不丢标题 |
| catalog 路径 | 零改动：调用方 `await` 返回后自己 `_retitle`（`workspace.dart:2781-2788`），不需要事件 |
| `/` 命令面 | thincoder 不实现 `ProvidesCommands` ⇒ 无命令源（`ChatSession.hasCommandSource == false`，`chat_session.dart:440` / `kernel_proxy.dart:47`）⇒ 行首 `/` 不弹面板；判据 = 内核能力，不看候选表是否为空；Claude 有源 ⇒ 行为不变（T139） |
| 外仓 | 零改动（不改 `thincoder/`） |

### 28.2 现状实读（两条路今天怎么走）

| 面 | 今天的走法 | 坐标 |
|---|---|---|
| 开着的会话改名 | `workspace.rename` → `_retitle` → `session.rename` → `ThincoderKernel.rename` → `_pumpTitle` 发 `session/set_title` | `workspace.dart:2776-2779` · `chat_session.dart:1452-1454` · `thincoder_kernel.dart:922-937` · `:1391-1394` |
| 没开的会话改名 | `workspace.rename` → `catalog.rename` 发 `session/set_title`，`await` 返回后 `_retitle` | `workspace.dart:2781-2788` · `lib/kernel/thincoder/thincoder_catalog.dart:72-88` |
| 事件面 | `SessionRenamed` 定义在 `lib/kernel/kernel_event.dart:135-139`；全仓唯一发出点 `claude_code_kernel.dart:1704`；消费 `chat_session.dart:263-267` → `workspace.dart:2270` | — |
| 发射通道 | `emit` / `nextSeq` 在 `AgentKernel` 上（`lib/kernel/agent_kernel.dart:503` 即 `emit(KernelInfoChanged(nextSeq))`）；`ThincoderCatalog` 只持 `_connect`（`thincoder_catalog.dart:22-28`），**没有**发射通道 | — |

### 28.3 改名同步：在哪发事件（候选与选择）

| 候选 | 覆盖 | 判据 |
|---|---|---|
| **a) 内核发** | 开着的会话 ✅；没开的会话不需要（调用方已 await） | 确认点在 `_pumpTitle` 成功分支（`thincoder_kernel.dart:1391-1398`）——只有那里知道写入落地了 |
| b) 宿主在 `RenamesStoredSessions.rename` 返回后自己更新 | 只覆盖没开的会话（今天已如此，`workspace.dart:2781-2788`） | 开着的会话走 `RenamesSession`，`chat_session.rename` 返回 void（`:1452`），宿主拿不到确认；且回合进行中写入会被压后（`thincoder_kernel.dart:930-931`），确认晚于调用 |
| c) 两者 | 同一标题两个写入者 | catalog 路径调用方已 `await` 后 `_retitle`；且那一刻没有活内核，事件无从发 |

**选 a。** 理由一句话：确认点是内核的，事件的发射通道也只有内核有；catalog 的等待语义本身就是确认。

**三问答复（新名字 `renameConfirmed`）**

- `existing: none found`——检索范围：`grep -rn "renameConfirmed" lib test` 零命中（本轮实读）。同族既有件是「写入待确认」那条可见链：`DefersRename.pendingTitle`（`lib/kernel/agent_kernel.dart:340-344`）→ `ChatSession.pendingTitle`（`lib/chat/chat_session.dart:776-779`）→ `AgentThread.pendingTitle`（`lib/workspace/workspace.dart:126`），两个出口都已在用：侧栏改名框 `initial:`（`lib/sidebar/sidebar.dart:2991`）、聊天页改名框（`lib/chat/chat_screen.dart:509`）。
- **复用，不新造可见面**：`ThincoderKernel.pendingTitle` = `_titleDeferred ? _titleTarget : null`（`thincoder_kernel.dart:196`）——回合进行中改名被压后（`:930-933`）时，上面两个出口已经显示待写标题。本批不改它：新流程只决定「谁在什么时候改列表」，延期窗的显示仍归这条既有链。
- 分工一句话：`pendingTitle` 答「还没落地的标题是什么」（显示面），`renameConfirmed` 答「这次写入会不会被内核确认」（决定列表何时改）；两者不互替——前者不参与判据，后者不新增可见面。

**落点形状：一个只管确认的能力接口**

```dart
// lib/kernel/agent_kernel.dart（紧邻 RenamesSession，:314-316）
/// Confirms its own renames: what it writes comes back as a SessionRenamed,
/// and the host leaves the list to that event.
abstract interface class ConfirmsRename {
  /// Whether a rename made now would be written and confirmed by this kernel
  /// (now, or once the turn under way ends). True ⇒ the host does not change
  /// the list ahead of the event; false ⇒ it does (today's behaviour).
  bool get renameConfirmed;
}
```

**「默认 false」怎么来的（不用 `implements` 的直觉）**：Dart 的 `implements` 不继承任何实现，`abstract interface class` 上的具体成员也照样要求实现方自己写。

`extension ... on RenamesSession { bool get renameConfirmed => false; }` 也不行：静态类型是 `RenamesSession` 时，扩展成员**优先于**实现类自己的成员，而 `ChatSession` 正是按接口取用（`chat_session.dart:776-779` 的 `switch (_kernel)`）⇒ thincoder 的覆写会被看漏。

故取本仓既有的能力探针形（`canRename` = `_kernel is RenamesSession`，`chat_session.dart:770`；`pendingTitle` 的 `switch` 兜底，`:776-779`）：`ConfirmsRename` 只由 thincoder 实现，宿主 `_ => false` 兜底。

```dart
// lib/chat/chat_session.dart（canRename :770 旁）
bool get renameConfirmed => switch (_kernel) {
  final ConfirmsRename kernel => kernel.renameConfirmed,
  _ => false,
};
```

`ClaudeCodeKernel`（`claude_code_kernel.dart:109` 的 `RenamesSession`）不实现 `ConfirmsRename` ⇒ 恒走 `_ => false` ⇒ Claude 的改名路径一行不改（F25③ / F26② 的回归前提；§28.8 因此不列该档）。

**判据：能走到写入分支，且不会被释放吃掉**

```dart
// lib/kernel/thincoder/thincoder_kernel.dart
String? _titleConfirmed;                       // 最近一次被确认的标题

@override
bool get renameConfirmed => _slot != null && _running && !_releaseWanted;

@override
void rename(String title) {
  // 确认回来的同一个标题不再写一次（见 §28.4 的回显短路）。
  if (title.trim() == _titleConfirmed) return;
  …其余照旧（_pendingTitle / _titleTarget / 延后）…
}
```

`_pumpTitle` 成功分支（`thincoder_kernel.dart:1395-1398`）：

```dart
if (!identical(connection, kernel._connection)) return;
kernel._titleSending = false;
kernel._titleConfirmed = target;
kernel.emit(SessionRenamed(kernel.nextSeq, target));   // 新增：确认后才发
if (kernel._titleTarget != target) return unawaited(_pumpTitle(kernel));
kernel._dropTitleOf();
```

三项各有实读依据，少一项就有一格静默丢标题：

| 项 | 为什么必须在判据里 |
|---|---|
| `_slot != null` | 新会话还没 `session/new` 时写入落在 `_pendingTitle`（`thincoder_kernel.dart:924-927`），槽一到就补写（`:341-342`）——那时宿主走今天的路径即可 |
| `_running`（`_connection != null && health == ready`，`:228-229`） | **`_slot` 不随释放清掉**：`_teardown` 只置 `_connection = null`（`:509-510`），`_closeSession` 只发 `session/close`（`:542-551`）。只看 `_slot` 会把「槽在、连接没了」判成会被确认，而 `_pumpTitle` 走的是 no-connection 分支（`:1380-1387`）⇒ 提示 + `_dropTitleOf()`，标题丢了、事件也没有 |
| `!_releaseWanted`（`:162` / `:580`） | 释放已排上时 `_pumpTitle` 走释放旁路（`:1394-1402`）：待写标题作废，出既有 `The title was not confirmed: …` 提示（理由 = the session is closing）、零事件；判据为真时宿主列表保持旧值——有提示，不是静默 |

- 判据的方向是**保守**：它为真 ⇒ 不走丢弃分支，**除非释放已开始**（判据在改名前取样，视图随后离开时写入作废；那一路必出 `The title was not confirmed: …` 提示，不静默，见 §28.4 与 T138）；它为假 ⇒ 宿主退回今天的乐观路径（列表即改，内核照旧尝试写）。误判为真 = 一次静默丢失；误判为假 = 只是少了新行为 ⇒ 临界取严（健康未 ready、释放已排上都算假）。
- 判据看不出服务端拒绝：`session/set_title` 被拒仍算「会确认」，那一路按 §28.4 出提示、零事件、列表保持旧值——那是设计的失败面，不是静默丢失。

**宿主侧一处改动**（`workspace.dart:2776-2779`）：

```dart
Future<bool> rename(AgentThread thread, String title,
    {bool confirmed = false}) async {
  final trimmed = title.trim();
  if (trimmed.isEmpty || trimmed.length > 80) return false;
  if (trimmed == thread._title) return true;
  thread
    .._named = true
    .._wantsTitle = false;
  // 内核确认回来的标题：落地一次，且不再向内核要一遍（内核自己短路，§28.4）。
  if (confirmed) {
    _retitle(thread, trimmed);
    return true;
  }
  final record = thread.record;
  final byKernel = thread.isOpen && thread.session.canRename;
  if (record == null || byKernel) {
    // 内核会确认的改名：列表等 SessionRenamed 再改（§28.4）；它不会确认的
    // （释放窗 / 无活连接 / 会话还没槽），照今天的样子先改，写不进去内核自己出提示。
    if (byKernel && thread.session.renameConfirmed) {
      thread.session.rename(trimmed);
    } else {
      _retitle(thread, trimmed);
    }
    return true;
  }
  …catalog（`:2781-2789`）与宿主自存（`:2790-2794`）两路照旧…
}
```

**确认事件回到列表的路**：`SessionRenamed` → `chat_session._apply`（`:263-267`）→ `_renamed` → `workspace._sync`（`:2270`，调用改为 `rename(thread, title, confirmed: true)`）→ `_retitle` 落地。

`confirmed` 的归属只有 `workspace.rename` 一处：只有 `_sync`（`workspace.dart:2270`）传真，其余调用点走缺省假。`ChatSession.rename` 签名不动（`void rename(String title)`，`chat_session.dart:1452-1454`），它只把标题交给内核。

### 28.4 失败路径与回显短路

| 路 | 结果 | 判据 |
|---|---|---|
| `session/set_title` 成功 | `_titleConfirmed = target` → 发一条 `SessionRenamed(target)` | `thincoder_kernel.dart:1391-1398` |
| `session/set_title` 抛错 | **零事件**、列表保持旧值；对话里出现既有提示「The title was not confirmed: <error>」 | `thincoder_kernel.dart:1399-1407`（`:1402-1403` 的 `error:title` 项） |
| 新会话还没槽（`_slot == null`） | 标题存进 `_pendingTitle`，槽一到就补写；`renameConfirmed` 为假 ⇒ 宿主先改列表（今天的路径） | `thincoder_kernel.dart:924-927` / `:341-342` |
| 槽在、连接没了（视图已离开 / 已释放 / 释放已排上） | `renameConfirmed` 为假 ⇒ 宿主先改列表；内核走 no-connection 或释放旁路 ⇒ 出既有 `The title was not confirmed: …` 提示（理由 = no connection / the session is closing）并把待写标题丢掉；**列表与 CLI 到下一次成功改名才一致**（§28.9 登记该形状） | `thincoder_kernel.dart:1394-1411` / `:509-510` / `:530` |
| 改名被回合压后、释放随后排上（改名时判据为真，视图离开后回合才结束） | 宿主未改列表（判据为真）；回合结束 `_pumpTitle` 走释放旁路：**零事件**、待写标题作废，出 `error:title` 提示「… the session is closing」；列表保持旧值（= CLI 的旧值） | `thincoder_kernel.dart:933-951` / `:1394-1402` / `chat_session.dart:491` |
| 确认事件回到宿主后再 `rename` 同一标题 | 一次写入都不多发 | `rename` 开头 `title.trim() == _titleConfirmed` 短路（§28.3） |
| 没开的会话改名失败 | `catalog.rename` 抛错 ⇒ `workspace.rename` 返回 false，**零列表改动** | `workspace.dart:2782-2788` |

**UI 落点（已落地，不留 open）**：改名对话框在 `rename` 返回 true 时立即关闭；列表标题在**确认后**改；失败时列表保持旧标题，并在会话里收到那条错误提示。宿主不吃掉错误、也不先改后回滚。

**不做「失败回滚事件」**：失败不发任何 `SessionRenamed`（判据 2 的口径），列表不变靠的是「没确认就不改」这一步，而不是事后改回来。

### 28.5 `/` 命令面：结论与理由

**结论：thincoder 隐藏（行首 `/` 不弹面板）；Claude 侧行为不变。**

- 判据是**内核有没有命令源**，不是候选表满不满：`ChatSession.hasCommandSource`（`lib/chat/chat_session.dart:440`）的取值 = 内核是否实现 `ProvidesCommands`（探针 `lib/chat/session/kernel_proxy.dart:47`）。
- 组合器的面板开关读它（`lib/chat/composer/composer_editing.dart:442`）：`visible = commands.isNotEmpty || (trigger.start == 0 && state.widget.session.hasCommandSource)`。该表达式已在盘上；它读的 `ChatSession.hasCommandSource` 在合并中丢失，由 R1 恢复（§29.4）。
- `ThincoderKernel` 的 implements 列表（`thincoder_kernel.dart:42-57`）没有 `ProvidesCommands`；实现它的只有 Claude（`claude_code_kernel.dart:99`）与 Codex（`lib/kernel/codex/codex_kernel.dart:22`）。
- ⇒ thincoder 会话里行首 `/`（以及 `/pl` 这类查询）都不弹面板；`ChatSession.commands` 对无源内核恒 `[]`（`chat_session.dart:439`），所以不是「假装有」，也不是弹一个空壳。
- ⇒ Claude 会话有命令源：`/` 在**命令表未到 / 表空 / 查询无匹配**三个窗口里面板都照开（空壳 + no-results 说明），与批 22 之前一致；判据 = T139（F26②）。

**为什么否掉「对齐」方案**：宿主唯一的命令书写源是 Claude Code 的定制文件
（`lib/customize/customizations.dart:1-2` 的「skills, subagents, slash commands, rules」；读取面 `lib/customize/customization_store.dart:62-70`）。
那是 Claude Code 的定制面，不是 thincoder 的命令源；而 thincoder 的 ACP 面既没有命令清单，也没有执行 `/x` 的通道——

`lib/kernel/thincoder/**` 里 `command` 只作**终端命令**字段出现（`lib/kernel/thincoder/thincoder_events.dart:335-337`、`:392`）。
照搬过去会造出一个点了不生效、或把 `/x` 当普通文本发出去的菜单，正是「假装有」。

**已知行为（不是缺陷）**：thincoder 会话里输入 `/x` 不弹面板，发送后就是一条普通消息；CLI 收到什么由它自己解释。

### 28.6 验收对照（回指 F25 / F26 验收 ①–③）

| 判据 | 本档落点 | 机制 | 机检 |
|---|---|---|---|
| F25① thincoder 会话改名 ⇒ 列表项与标题都变新，不需要切换会话 | §28.3 / §28.4 | 确认后 `emit(SessionRenamed)`；`_sync` 以 `confirmed: true` 落地 | T131 / T134：`flutter test test/kernel/thincoder_kernel_test.dart` |
| F25② `session/set_title` 抛错 ⇒ 事件数 0、列表标题仍是旧值 | §28.4 | 失败分支只发既有 `error:title` 提示，零事件；释放旁路的作废同形（零事件 + 提示 + 列表旧值） | T132（`test/kernel/thincoder_kernel_test.dart`）/ T138（`test/kernel/rename_confirmed_test.dart`） |
| F25③ Claude 内核路径行为不变（回归） | §28.3 | `ClaudeCodeKernel` 不实现 `ConfirmsRename` ⇒ `renameConfirmed` 恒假 ⇒ 仍走 `_retitle`；`SessionRenamed` 的发出点（`claude_code_kernel.dart:1704`）与消费面零改动 | T135（`test/kernel/rename_confirmed_test.dart`） |
| F26① thincoder 会话里 `/` 不弹命令面板 | §28.5 | 内核无命令源（不实现 `ProvidesCommands`）⇒ 面板开关为假 ⇒ 行首 `/` 与 `/pl` 都不弹；判据不看候选表是否为空 | T133（能力接口 + `commands` 为空 ∧ `hasCommandSource == false` + 行首 `/` 与 `/pl` 的 `SuggestionMenu findsNothing`） |
| F26② Claude 内核会话里命令面板行为不变（回归） | §28.5 | 本批不动 `ProvidesCommands` 与 `_commandSuggestions`（`chat_screen.dart:624-641`）；面板开关只读内核能力（`composer_editing.dart:440-443`），表未到 / 表空 / 无匹配都照开 | T136（`flutter test test/chat/command_details_test.dart` 既有 Claude 用例全绿）+ T139（Claude 表空仍开面板，含 `/pl` 无匹配） |

**RTM 增量（本批不加行，索引仍是 3 / 50–100；4-1 由 §29.9 立、随 R2 落地）**

- 1-1 / 2-1 / 3-1 的既有断言一条不改：本批不触碰切换、失焦、流式三面的任何业务结果。
- 不加行的理由：本批改动的可观察结果是「改名在确认后落到列表标题，失败时保持旧值并出提示」；该结果跨的那一跳（`SessionRenamed` → `workspace._sync` → `_retitle`）已由 §28.7 的 T131 / T134 用真实 `Workspace` 与真实 `ChatSession`（mock 传输）驱动到机检。
- 再加一条集成用例只多一层侧栏 widget 读同一个 `AgentThread.title`，不产生新的组件间交互，也无生产问题的来路 ⇒ 不立项。

### 28.7 用例表（T131–T139）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T131 | 改名成功同步 | mock 传输 + 开着的 thincoder 会话；`rename('A')`；`session/set_title` 正常应答 | 事件流里恰一条 `SessionRenamed` 且 `title == 'A'`；`session.takeRenamed() == 'A'`；`_sync` 以 `confirmed: true` 落地标题；没有别的 `SessionRenamed` |
| T132 | 改名失败不发事件 | 同上，`session/set_title` 抛错 | 事件流里**零条** `SessionRenamed`；对话里出现 `error:title` 提示；`takeRenamed()` 为 null；线程标题仍是旧值 |
| T133 | 命令面对该内核为空（三处断言） | 内核层的 `ThincoderKernel` 实例 + widget 层的 thincoder `ChatScreen` | ① `expect(kernel, isNot(isA<ProvidesCommands>()))`；② `ChatSession.commands` 为空 ∧ `hasCommandSource == false`；③ 行首 `/` 与 `/pl` 后 `SuggestionMenu findsNothing`（面板不出现；开关见 `composer_editing.dart:440-443`） |
| T134 | 确认回来的标题不成环 | T131 之后再 `rename('A')` 一次（模拟 `workspace._sync` 的回写） | `session/set_title` 请求数不再增加；无第二条 `SessionRenamed`（内核 `_titleConfirmed` 短路） |
| T135 | Claude 不实现该能力 ⇒ 路径不变 | `test/kernel/rename_confirmed_test.dart`：一个 Claude 会话 | `expect(claudeKernel, isNot(isA<ConfirmsRename>()))`；`ChatSession.renameConfirmed == false`；`workspace.rename` 走 `_retitle`（列表即改，不等事件） |
| T136 | Claude 命令面板回归 | `flutter test test/chat/command_details_test.dart` | 该档既有 Claude 用例全绿（本批不改该档任何 Claude 断言）；`_commandSuggestions` 零改动 |
| T137 | 判据三态（含释放窗） | 同一 thincoder 内核：① `session/new` 完成；② `release()` 之后（视图离开，`_slot` 仍在）；③ 新会话还没 `session/new` | ① `renameConfirmed == true`；② `false`（连接已断 / `_releaseWanted` 真）；③ `false`（走 `_pendingTitle`）。②③ 两态下尚无 `session/set_title` 请求发出，宿主列表已先改（今天的路径） |
| T138 | 改名被回合压后、释放随后排上 | `test/kernel/rename_confirmed_test.dart`：开着的 thincoder 会话；回合在飞时 `rename('A')`，随后 `detach()`（置 `_releaseWanted`），再让回合结束 | 事件流**零条** `SessionRenamed`；`session/set_title` 请求零条；列表标题仍是旧值（`'go'`）；对话里恰一条 `error:title` 提示，含 `not confirmed` 与 `closing` |
| T139 | Claude 有命令源、表空仍开面板（三个窗口） | `test/chat/thincoder_commands_test.dart`：`FakeCli(answers: {'initialize': {}})` ⇒ 握手回包无 `commands`；Claude 会话开 `ChatScreen` | `kernel is ProvidesCommands`；启动前后 `session.commands` 均空 ∧ `hasCommandSource == true`；行首 `/` ⇒ `SuggestionMenu` 出现且 `matches` 为空；再输 `pl` ⇒ 面板仍在、`matches` 仍为空 |

侧栏那一跳（`SessionRenamed` → `_sync` → `_retitle`）由 T131 / T134 覆盖到机检；真机上再走一次：改名后侧栏立刻是新标题，失败时保持旧标题并出现错误提示。

### 28.8 受影响文件清单（行数 = 本轮实测）

| # | 坐标 | 现值（本轮实测） | 改动 | delta |
|---|---|---|---|---|
| ① | `lib/kernel/agent_kernel.dart` | 539 | `ConfirmsRename` 能力接口（紧邻 `RenamesSession`，`:314-316`） | ≈ +10 |
| ② | `lib/kernel/thincoder/thincoder_kernel.dart` | 480 | `implements ConfirmsRename` + `renameConfirmed` 委托一行（`:344`，判据实现在 `thincoder_title.dart`） | ≈ +2 |
| ②a | `lib/kernel/thincoder/thincoder_title.dart`（`part of 'thincoder_kernel.dart'`） | 84 | 判据 `renameConfirmedOf`（`:10`）+ `_titleConfirmed` 同标题短路（`renameOf` `:13-31`）+ `_pumpTitle` 成功分支发事件（`:38`）；`_pumpTitle` 按符号落在此档，不在上一行 | ≈ +10 |
| ③ | `lib/chat/chat_session.dart` | 794 | `renameConfirmed` 委托（`_ => false` 兜底，紧邻 `canRename` `:770`）+ 能力面 `hasCommandSource`（`:440`，+1 行，走 `_hasCommandsOf`）；`rename` 签名不动 | ≈ +5 |
| ④ | `lib/workspace/workspace.dart` | 2984 | `rename()` 增具名参数 `confirmed` + 确认分支 + `renameConfirmed` 分支（`:2766-2795`）；`_sync` 调用点传 `confirmed: true`（`:2270`） | ≈ +9 / −1 |
| ⑤ | `lib/chat/composer/composer_editing.dart` | 475 | 命令分支的面板开关（`:440-443`）：`visible = commands.isNotEmpty || (trigger.start == 0 && state.widget.session.hasCommandSource)` —— 行首 `/` 对有源内核恒开、对无源内核不开。判定已在盘上；缺的是它读的 `hasCommandSource`（合并中丢失，R1 恢复，§29.4） | 0（本档不改） |
| ⑥ | `lib/chat/session/kernel_proxy.dart` | 203 | `_hasCommandsOf`：`owner._kernel is ProvidesCommands`（`:47`） | +2 |
| ⑦ | `test/kernel/rename_confirmed_test.dart` | 新增 | T135 / T137 / T138（Claude 不实现该能力；判据在开会话 / 释放后 / 无槽三态；改名被回合压后、释放随后排上的可见丢失） | 193 |
| ⑧ | `test/kernel/thincoder_kernel_test.dart` | 4967 | T131–T134 追加到文件末尾 | ≈ +90 |
| ⑨ | `test/chat/thincoder_commands_test.dart` | 168 | T133（thincoder 无命令源：能力接口 / `commands` 空 ∧ `hasCommandSource == false` / 行首 `/` 与 `/pl` 不弹面板）+ T139（Claude 有命令源、表未到与表空仍开面板） | 新增 |

- **零改动（产品面）**：`lib/kernel/claude_code/claude_code_kernel.dart`（不实现 `ConfirmsRename`，不进改动面）· `lib/kernel/thincoder/thincoder_catalog.dart`（150——调用方已 `await` 后 `_retitle`，不需要事件通道）· `lib/kernel/kernel_event.dart`（`SessionRenamed` 已存在 `:135-139`）。
- **零改动（消费面）**：`lib/sidebar/sidebar.dart` 与 `lib/chat/chat_screen.dart` 的改名框（继续读既有 `pendingTitle`）· 外仓 `thincoder/**` 全部。
- **体量立场（`chat_session.dart` 794 行，本轮实测，< 800 硬顶）**：本批只加两个委托 getter（`renameConfirmed` / `hasCommandSource`，≈ +5），不动结构与既有成员；缝候选 = `ChatSession` 的横向委托面（改名 / 模型 / 权限 / 命令，`:437-452`）整段出档；本批不拆。
- **体量立场（`composer.dart` 2350 · `workspace.dart` 2984，均在 >800 名单）**：只在既有 `_handleEditorChanged` / `workspace.rename` 内改判据、加分支，不动结构；缝候选沿用 §17.4（composer 右下角固定组）与 §19.4（会话面）；触发 = 下一次结构级触碰或独立拆分批立项（本批不拆）。`thincoder_kernel.dart` 现 480 行（< 800），本批只在既有 `rename` / `_pumpTitle` 内加分支与字段。

### 28.9 边界（本批不做）

- 不在 catalog 路径发事件（没内核可发，调用方已 await）。
- 不做改名失败的「回滚事件」：失败只留既有错误提示，列表靠「没确认就不改」保持旧值。
- 不实现 `/` 命令面，不从 Claude Code 的定制文件合成命令表。
- 不解决跨客户端同步：终端里改同一会话的标题，本仓下一次刷新前不跟（超出本批）。
- 不改外仓 `thincoder/`；不动 btest 面（`lib/browser/btest/**`）。
- **释放窗内的改名：丢弃 + 可见提示，不跨释放保留标题**：视图离开后（或释放已排上、回合结束时）改名，`_slot` 仍在、连接已断或正在断开 ⇒ 内核把待写标题丢掉，并出既有 `The title was not confirmed: …` 提示（理由 = no connection / the session is closing），**零 `SessionRenamed`**；宿主按判据在改名前是否成立，决定列表是先改（假）还是保持旧值（真，随后收到提示）。要跨释放留住待写标题需新机制（`_pendingTitle` 只在无槽时用，`:924-927`），不在本批。
- **不把 `renameConfirmed` 扩成通用能力**：只有 thincoder 实现；Claude 走 `_ => false`（今天的路径），Codex 本就没有改名面。

### 28.10 未验证项（单列，不静默省略）

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U17 | thincoder CLI 是否会主动把标题变更通知宿主 | 本轮实读：内核侧只有发送侧三个字段（`thincoder_kernel.dart:144-146` 的 `_titleTarget` / `_titleDeferred` / `_titleSending`），没有接收面 | 本批按 `session/set_title` 的确认发，不依赖 CLI 通知；若日后出现该通知，翻译它即可，本档判据不变 |
| U18 | `test/kernel/thincoder_kernel_test.dart` 的现行行数 | **已闭合**：本轮实读 4967（`node -e` 计行，§28.8 ⑧ 的现值即此读数） | 实施轮按 diff 核 delta；不再引用 §27.9 的 4299 |

**将来触发条件（登记）**：需求 F26 功能点 ③——外仓 ACP 面提供命令清单与执行通道时，`/` 从「隐藏」改为「对齐」：那时 `ThincoderKernel` 实现 `ProvidesCommands`、`ChatSession.commands` 由空变实，T133 的断言（能力接口 / 无命令源 / 面板不出现）改成「候选非空 + 面板出现」，§28.5 的结论随之重写。当前无此通道（`thincoder_events.dart:335-337` / `:392` 的 `command` 是终端命令，不是 `/` 命令）。



---

## 29. 上游共存：ChatSession overlay 与宿主工具重接

### 29.1 方案与理由

目标是让上游 `ChatSession` 继续持有会话、内核、转写与审查状态，自有功能只通过独立 library 和一个 overlay 契约接入。`lib/chat/session/**` 不再以 `part of` 读取宿主私有成员。

采用「窄宿主接口 + 每会话 overlay 实例」。宿主只暴露 overlay 必需的公开读面与生命周期钩；自有状态集中在 overlay，不复制上游状态。上游文件只留下登记过的接线点，合并时不整档覆盖自有模块。

- **最近先例**：`docs/design/thincoder-adapter.md` §5.2 的最小接线点集与 §28.3 的能力探针。对齐点是「宿主只留接线、能力按接口探测」；偏离点是不再使用 `docs/design/structure-splits.md` §4.4 的 `part` 私有访问形态，因为拆文件并未形成模块隔离。
- **survey 证据**：`PROJECT-MANIFEST.json` 的 `index.publicRepos` 为空；已核 `docs/requirements/thincoder-adapter.md` §4 / §7、`docs/requirements/browser-biz-test.md` §3 / §5、`docs/requirements/host-tool-channel.md` §3 / §5、`docs/design/thincoder-adapter.md` §5.2 / §12 / §28、`docs/design/structure-splits.md` §4.4、`test/RTM.md`。没有其它公开文档源。
- **现状依据**：`lib/chat/chat_session.dart:69` 的 `ChatSession` 实现 `ChatFeed` / `MarksTurns` / `ChatSessionOverlayHost`；`lib/chat/session/*.dart` 八档均为独立 library，`part of` 0 处。上游的构造、事件、挂载、切内核、发送与释放路径按符号读同档，行号随上游改动漂移，不作判据。

**契约名的三问答复（本轮实读）**

- `ChatSessionOverlay`：`none found` —— 本轮 `grep -rn "ChatSessionOverlay" lib test` 零命中，`lib/chat/session/*.dart` 八档亦无契约档。最近邻是能力探针形（`RenamesSession` / `ConfirmsRename`，`lib/kernel/agent_kernel.dart:324`），但它只答能力有无、不持状态，故不复用。
- `ChatSessionOverlayHost`：`none found` —— 同上零命中。`existing but unusable` 的最近件 = `ChatSession` 本体（`lib/chat/chat_session.dart:100` 只实现 `ChatFeed`）：它以私有成员服务自己的 part 档，不能充当独立模块的公开宿主面。

### 29.2 接口契约

新增 `lib/chat/chat_session_overlay.dart`。契约档不 import `chat_session.dart`；session 实现档也只 import 契约，不反向 import 宿主。

`KernelChoice` / `ModelSettingChoice` 从 `chat_session.dart:46-84` 移到该契约档，宿主用 `export ... show` 保持原公开入口。这样 mode 包装不需要 import 宿主，也不会形成循环依赖。

```dart
abstract interface class ChatSessionOverlayHost {
  KernelContext get kernelContext;
  AgentKernel get agentKernel;
  Transcript get transcript;
  bool get canSend;
  void notifyListeners();
}

abstract interface class ChatSessionOverlay {
  List<ChatItem> get items;
  List<TurnMark> get turns;
  void addNotice(NoticeItem notice);

  bool get btestOn;
  BtestRun? get btestRun;
  BtestTraversal get btestTraversal;
  bool get btestWrite;
  void setBtest(bool on);
  void setBtestTraversal(BtestTraversal value);
  void setBtestWrite(bool on);
  KernelChoice? wrapModes(KernelChoice? base);

  void onEventBefore(ChatSessionOverlayHost host, KernelEvent event);
  void onEventAfter(
    ChatSessionOverlayHost host,
    KernelEvent event, {
    required bool changed,
    required bool sessionChanged,
  });
  void onAttach(ChatSessionOverlayHost host);
  void onDetach(ChatSessionOverlayHost host);
  void onKernelChanging(
    ChatSessionOverlayHost host,
    KernelDescriptor next,
  );
  bool cacheKernel(AgentKernel kernel);
  AgentKernel? restoreKernel(KernelDescriptor descriptor);
  void onKernelChanged(ChatSessionOverlayHost host);
  KernelTurn beforeSend(
    ChatSessionOverlayHost host,
    KernelTurn turn,
    OpenEditor? editor,
  );
  void onDispose(ChatSessionOverlayHost host);
}
```

`ChatSession` 实现 host 与 `MarksTurns`：现有 `kernelContext`、`canSend`、`notifyListeners` 直接满足；新增 `agentKernel` / `transcript` 两个只读投影。overlay 只读它们，不直接 `apply` 或替换上游状态。

构造器接受可选 `ChatSessionOverlay`，缺省创建 `BaocodeSessionOverlay`，字段静态类型仍是契约，因此测试假件与生产实现走同一组成员。`turns`、`addNotice`、btest 七成员和 `wrapModes` 必须留在契约里；否则宿主只有生命周期接口，无法投影 overlay 持有的状态。

| 上游接缝 | 接线 | 依据 |
|---|---|---|
| 构造与 `_connect` | 每会话持有一个 overlay；`restoreKernel` 在创建新内核前询问一次；失败缓存由 overlay 自行 dispose 并返回 null | `lib/chat/chat_session.dart:101-120`、`:155-158`；失败缓存规则来自 `lib/chat/session/lifecycle.dart:7-16` |
| `_apply` | `onEventBefore` 记录 apply 前位置；transcript apply 后、review 与 notify 前调用 `onEventAfter`；`SessionRenamed` / `FilesMayHaveChanged` 的既有早退不改 | `lib/chat/chat_session.dart:160-174`；turn 用例 `test/chat/turn_marks_test.dart:72-241` |
| `attach/detach` | 调用对应钩；视图计数、prepare、release 仍由上游执行 | `lib/chat/chat_session.dart:374-390` |
| `setKernel` | `onKernelChanging` 开计时；`cacheKernel` 决定旧内核是否保留；`restoreKernel` 可取回同 descriptor 缓存；切后 `onKernelChanged` 清 turn 状态并重绑 btest | `lib/chat/chat_session.dart:412-421`；启动约束 `lib/chat/session/mode_state.dart:65-88` |
| 切内核后的挂载 | 若 `_views > 0`，上游统一执行新内核 `prepare()` 与 `_startReview()`，再通知 | `lib/chat/session/mode_state.dart:79-85` 给出了不执行时新内核不启动的可复现路径 |
| `send` | 恢复 `editorContext = true` 参数；按能力与设置取 editor；构造 `KernelTurn` 后交 `beforeSend`，再交内核 | `lib/chat/chat_session.dart:1114-1150`；`lib/kernel/kernel_types.dart:584-613`；`lib/chat/editor_context_setting.dart:11-17` |
| `itemCount/itemAt` | transcript 后插入 `overlay.items`，最后才是 live status；`addNotice` 追加并通知 | `lib/chat/chat_session.dart:746`（`itemCount`）/ `:750`（`itemAt`）/ `:932`（`addNotice`）；`lib/chat/session/transcript_proxy.dart:20`（`cutsAtMessage`）/ `:36`（`markTurnOf`），该档 94 行；调用点 `lib/chat/panels/revert_dialog.dart:65-70` |
| `dispose` | 先 `onDispose` 清缓存与 btest 绑定，再执行既有释放 | `lib/chat/chat_session.dart:1252-1264`；`lib/browser/btest/btest_mode.dart:177-195` |
| 回退投影 | `revertTurn` 由宿主在 `_pendingEdits` 上实现；`canPlanRevert` / `plansReverts` / `revertPlan` / `applyRevert` 由独立 helper 读 `host.agentKernel` | `lib/chat/chat_session.dart:995-1002`；`lib/chat/session/file_edits.dart:98-124` |

`onEventAfter` 的两个读数不得合并：`changed` 表示 transcript 实际变化，驱动 turn marks；`sessionChanged = event is KernelInfoChanged || changed` 驱动 btest 重绑、kernelLocked 时清 warm 缓存、切换完成计时。既有 review 与 notify 顺序不变。

宿主公开成员只补调用方已经需要的投影：`hasCommandSource`、`acceptsEditorContext`、`renameConfirmed`、`ownsTitle`、`pendingTitle`、`pendingModel`、`canStopTasks`、btest 七成员、`turns`、回退五成员与 `addNotice`。

`acceptsImages` = `AcceptsImages || AcceptsImageFiles`。`modes` 只在上游基础 choice 非空时叠加 btest；`ChatSession` 实现 `MarksTurns`。其余上游已有实现不复制。

### 29.3 自有模块与状态归属

| 模块 | 职责 | 状态 owner |
|---|---|---|
| `lib/chat/session/overlay.dart` | `BaocodeSessionOverlay`，组合各 helper | warm kernels、turn marks、notices、btest、切换计时 |
| `lib/chat/session/kernel_proxy.dart` | 上游缺少的内核能力投影 | 无；读 `host.agentKernel` |
| `lib/chat/session/mode_state.dart` | btest option、`wrapModes`、pendingModel | btest 只在 overlay；pendingModel 直接读内核，无第二份状态 |
| `lib/chat/session/transcript_proxy.dart` | turn-mark 算法、`canStopTasksOf` 与 `cutsAtMessage` | 列表只在 overlay；算法只用 apply 前后读数 |
| `lib/chat/session/file_edits.dart` | 四个 `PlansReverts` 投影；`revertTurn` 留在宿主接缝 | 无；pending edits 与审查状态仍在上游 |
| `lib/chat/session/send_contexts.dart` | editor context 去重、btest 卡片上下文、已告诉文本枚举 | 去重是一次发送的局部状态 |
| `lib/chat/session/lifecycle.dart` | warm kernel 缓存、挂载与切换计时 | 缓存只在 overlay，dispose 必清空 |
| `lib/chat/session/file_paths.dart` | 删除；与上游 paths / absolute 重复 | 上游 |
| `lib/chat/session/session_commands.dart` | 删除；stop / answer / rename / discardChanges 与上游重复 | 上游 |

模块名的三问答复（本轮实读）：

- `BaocodeSessionOverlay`：`none found` —— 本轮 `grep -rn "BaocodeSessionOverlay" lib test` 零命中。`existing but unusable`（定名当天）= `lib/chat/session/**` 当时是八个 `part of` 寄生档：warm / turn marks / notices / btest 的状态与算法都在，形态却不能被独立 import；R1 已把这些算法改成独立 library，名字留给契约——契约要定的是宿主与 overlay 的分工，不是复用某个既有类型。
- `lib/chat/session/overlay.dart`：`none found` —— 该路径不在盘（本轮实读；该目录八档为 file_edits / file_paths / kernel_proxy / lifecycle / mode_state / send_contexts / session_commands / transcript_proxy）。⇒ 新建，不覆盖任何既有文件。
- `lib/browser/btest/btest_tool_gate.dart`：`existing but unusable` —— 判据在 `lib/browser/btest/btest_mode.dart:209` 的 `BtestGate`，`check`（`:223-256`）的签名已收 `HostToolCall`；不可直接用的部分 = `hosts` / `targeted` 的推导要读浏览器 tab 状态，而该状态在 `browser_tools.dart` 父库内，通用 `HostTools` 面不得出现这一特判（§29.4 ③）。

`KernelChoice` / `ModelSettingChoice` 只在 `chat_session_overlay.dart` 定义，`chat_session.dart` 负责 re-export。任何 session 文件不得出现 `part`、`part of`、对宿主的 import 或对 `ChatSession` 私有成员的访问。

上游继续持有 transcript、活动内核、review、视图计数、`_pendingEdits` 与 editor 已告诉标记；overlay 持有 warm kernels、turn marks、notices、btest 与切换计时。pendingModel 是内核 facet 的只读投影，不在这两处另存。

btest 使用 `BtestMode.of/bind/release` 的既有键机制（`lib/browser/btest/btest_mode.dart:127-205`）。overlay 首次接触会话时 `of(...)..fromSettings()`；sessionId 到达或改变时 `bind`；dispose 时 `release`。不在 composer、工具层或另一个单例复制第三份状态。

### 29.4 浏览器与 composer 接法

`lib/browser/browser_tools.dart` 迁到 `lib/host_tools/host_tools.dart` 的 `HostTool` / `HostTools` / `HostToolCall`。父库仍保留 `browser_tools.dart:20-27` 的 part 装配；只改父库 import、注册与调用包装，`browser_actions.dart` 与 `browser_debug_tools.dart` 零改动。

注册包装保留以下既有业务门：

1. 使用当前 `numbersAsSchemaSays` 做递归数字归一（`lib/browser/browser_tools.dart:133-165`），不退回只扫四个键的旧实现。
2. 注入 `description` schema；entry 工具补用户浏览器说明；`browser_navigate` 补 `detour`，`browser_evaluate` 补 `readOnly`。
3. `_all` 同时包含 `BtestTools.all`；包装时为每个工具设置 `group: 'browser'` 与 `kind: ToolKind.browser`，并保留 `picturesOnly`。现有 part 工具未声明 group，缺省空串不能暴露到 browser MCP 组。
4. 调用先过 btest，再做 tab watch / blocked / `BrowserRecords.acting`；无 tabId 的工具仍走原 `tool.run`。
5. 新 `lib/browser/btest/btest_tool_gate.dart` 独立封装 `_btest`、entry URL hosts、tab hosts。`BrowserTools` 只提供 `tabHost(tabId)` 回调；通用 `HostTools` 不出现 browser 特判。

btest gate 的真实判据仍由 `BtestGate.check` 决定（`lib/browser/btest/btest_mode.dart:207-256`）。无 btest 状态时不增加调用结果；有状态且无 run、违反 readonly 或 host 规则时明确拒绝，不静默放行。

composer 不需要另接一套状态：

- `composer_view.dart:186-194` 的七个 btest 缓存键与 `:233-237` 的状态行继续读 `ChatSession`。
- `btest_status_switches.dart:39-50` 继续区分 run 实际值与下次 run 开关；`:84-114` 继续调用 session setter。
- `composer_editing.dart:430-442` 已有 `hasCommandSource` 能力门，R1 恢复该 getter 即可，`composer.dart` 与此档均零改动。

### 29.5 受影响文件与执行轮次

行数为 2026-10-26 实读，delta 为实施预算。每轮不超过 15 个改动文件，单一改动面；未列的既有测试只运行、不修改，不计入改动档数。

#### R1 · ChatSession overlay（12 档）

| 文件 | 现行 | 预期 delta / 落点 |
|---|---:|---|
| `lib/chat/chat_session.dart:100,155,160,377,412,995,1114,1252` | 1266 | ≈ +160 / −60；§29.2 全部宿主接缝与 choice re-export |
| `lib/chat/chat_session_overlay.dart:1` | 新 | ≈ +170；choice 数据、host 与完整 overlay 契约 |
| `lib/chat/session/overlay.dart:1` | 新 | ≈ +260；每会话状态与契约实现 |
| `lib/chat/session/kernel_proxy.dart:1` | 204 | 收敛到 ≈90；只留缺失 facet |
| `lib/chat/session/transcript_proxy.dart:1` | 226 | 收敛到 ≈150；turns / canStopTasks / cutsAtMessage |
| `lib/chat/session/mode_state.dart:1` | 187 | 收敛到 ≈100；btest mode / pendingModel |
| `lib/chat/session/file_edits.dart:1` | 142 | 收敛到 ≈35；四个 PlansReverts 投影 |
| `lib/chat/session/lifecycle.dart:1` | 43 | ≈ +60；warm 与计时 helper |
| `lib/chat/session/send_contexts.dart:1` | 51 | ≈ +60；editor / btest contexts |
| `lib/chat/session/file_paths.dart:1` | 23 | 整档删除 |
| `lib/chat/session/session_commands.dart:1` | 22 | 整档删除 |
| `test/chat/session_overlay_test.dart:1` | 新 | ≈ +340；契约顺序、生命周期、发送、notice、facet 失败门 |

`chat_session.dart` 已超过 800 行。本批先把 fork 私有逻辑移入独立模块，不为总行数搬上游类；共享文件受 `docs/design/fork-deltas.md` 的净增预算约束。拆分单元按本档现坐标钉住：

| 拆分单元 | 现坐标 | 拆出后 |
|---|---|---|
| facet | 能力投影带，`canRename`（`:604`）起的横向委托（改名 / 模型 / 权限 / 命令） | 投影 helper，只读 host 契约 |
| review | `_startReview`（`:214`）· `_pendingEdits`（`:995`）· 回退面（`:923`–`:1031`） | 审查与回退出档；`revertTurn` 仍留宿主窄接缝（§29.2） |
| send | `send`（`:1114`）– `sendQueuedNow`（`:1189`） | 发送构造与排队出档 |

**触发判据**：上述三段任一段被本批以外的改动触碰（改任一线段即算）⇒ 立「chat_session 拆分」分批，按同一公开契约搬出该段，不恢复 `part`；未被触碰则不动。

**R1 净增的代价（≈ +160 / −60）**：

- `+160` 是留在上游类里的接缝与投影 —— §29.2 的九个宿主接缝、`agentKernel` / `transcript` 两个只读投影、choice re-export，以及 `hasCommandSource` / `renameConfirmed` 等委托。它们搬不出去：搬出就要读 `ChatSession` 私有成员，正是本批要结束的形态。
- `−60` 是搬进 overlay 的自有逻辑。净增 ≈ +100，在 `docs/design/fork-deltas.md` §3 对 `chat_session.dart` 的 ≤180 行预算内。

验收：

```text
flutter analyze --no-pub lib/chat
flutter test --no-pub test/chat/session_overlay_test.dart test/chat/turn_marks_test.dart test/chat/revert_flow_test.dart test/chat/pending_model_test.dart test/kernel/rename_confirmed_test.dart test/chat/thincoder_commands_test.dart test/chat/composer_btest_status_test.dart test/kernel/thincoder_kernel_test.dart test/kernel_ui_test.dart
```

禁改：SCM、browser、composer 产品文件、上游 picker、外仓。`composer_view.dart` 与 `btest_status_switches.dart` 的错误必须由 session API 恢复而消失，不得改 UI 迁就第二套状态。

#### R2 · browser 宿主工具重接（6 档）

| 文件 | 现行 | 预期 delta / 落点 |
|---|---:|---|
| `lib/browser/browser_tools.dart:12,70,81-165` | 711 | 净增 ≤150；HostTools 注册与调用包装 |
| `lib/browser/btest/btest_tool_gate.dart:1` | 新 | ≈ +90；btest 与目标 host 推导 |
| `test/browser/browser_numbers_test.dart:1` | 88 | 改为 `HostTools.handle` / `HostToolCall`，保留 schema 断言 |
| `test/browser/btest_tool_gate_test.dart:1` | 新 | ≈ +180；off / no-run / readonly / write / hosts |
| `test/RTM.md:9,49` | 54 | 新增 §4 与 4-1；总数 3 → 4 |
| `test/integration/btest_flows_test.dart:1` | 新 | ≈ +180；4-1 用户入口集成用例 |

验收：

```text
flutter analyze --no-pub lib/browser
flutter test --no-pub test/browser/browser_numbers_test.dart test/browser/btest_tool_gate_test.dart test/browser/browser_steps_test.dart test/chat/composer_btest_status_test.dart
```

R2 依赖 R1 已落地；`composer_btest_status_test.dart` 在 R1 前必因缺少 session 契约而失败。

禁改：`HostTools` 通用语义、`browser_actions.dart`、`browser_debug_tools.dart`、`host_mcp_server.dart` 的 exposedGroups / picturesOnly 规则、Claude 工具审批路径、SCM。btest 的单元拒绝用例必须断言拒绝原因包含工具名与未满足的门，不能只测 happy path。

两轮完成后由父侧执行全量 `flutter analyze --no-pub` 与集成套件；这是收口门，不分摊成每轮全量测试。

### 29.6 关键决策记录

| 决策 | 理由 / 被否方案 |
|---|---|
| 组合 overlay，不恢复 part，不包装替换 `ChatSession` | 保留现有调用方类型与构造入口；包装类会迫使全部消费者改类型，part 会继续耦合私有成员 |
| choice 类型归入契约档并由宿主 re-export | session 实现档无需 import 宿主；被否方案是允许循环 import，它会让独立模块边界再次失真 |
| `revertTurn` 留在宿主窄接缝，其它回退 facet 出档 | 它读取上游 `_pendingEdits`；为该一个 getter 暴露整份审查内部状态会更宽 |
| 缺省创建本仓 overlay，允许测试注入 | 不为每个构造点增加装配义务；测试仍能隔离钩与状态 |
| 删除与上游重复的 helper | 重复投影会形成第二真相；只保留上游没有的自有语义 |
| warm map 是内核对象缓存，不是进程预热池 | 只复用未开始会话切走的对象；kernelLocked 或 dispose 即清，不创建预热机制 |
| 通用 `HostTools` 不加 browser 特判 | 数字、schema、btest 与 tab 包装属于 browser 注册面 |
| 保留当前递归数字归一 | 它覆盖嵌套 step；旧四键转换会丢掉该能力 |
| composer 只验不改 | 命令源门与 btest UI 已在盘上；缺的是 session 契约，不是另一处 UI 修补 |

### 29.7 验收回溯

| 需求 | 判据 |
|---|---|
| B1 · `docs/requirements/thincoder-adapter.md` §4 E1/E2、§7 A10 | 自有 session 文件均可独立 import；共享档改动均登记；`part of '../chat_session.dart'` 为 0 |
| B2 · 同档 F25 / F26 与 §5 图片、编辑上下文映射 | 改名与命令源回归通过；`AcceptsImageFiles` 可发送图片；声明 `AcceptsEditorContext` 才携带 contexts；未声明者不携带 |
| B3 · `docs/requirements/browser-biz-test.md` §3 F1/F2/F9/F11、§5 第 1 / 7 项 | btest 切换、提示注入、两个开关与持久化使用同一 overlay；composer 定向测试通过 |
| B4 · `docs/requirements/host-tool-channel.md` §3 F1/F2/F3、§5 A1/A2/A3 | 浏览器工具经 HostTools 注册；开关与错误门明确；Claude 路径不变 |
| B5 · `test/RTM.md` §1 / §2 / §3 / §4 | 父侧收口运行 1-1、2-1、3-1、4-1，业务可观察结果不回退 |

每个单元验收指向本轮回合的改动面。集成套件只在父侧收口运行。

### 29.8 用例表

| 场景 | 输入 | 期望 |
|---|---|---|
| 契约注入 | 假 overlay + 构造、事件、切换、发送、dispose | 宿主只经契约读写；生命周期调用顺序与 §29.2 一致，无私有成员逃生口 |
| overlay 生命周期 | attach → 两次切内核 → detach → dispose | 缓存按契约复用；dispose 后缓存与 btest 绑定为空；无重复订阅 |
| turn marks | 依次发 TurnStarted / TurnEnded / HistoryPrepended / Rewound | `test/chat/turn_marks_test.dart:72-241` 的起点、时长、平移与裁剪全部一致 |
| 事件顺序 | transcript 改变事件与 KernelInfoChanged | turn 只在 changed 时变；btest / warm / 计时只在 sessionChanged 时走；review 与 notify 顺序不变 |
| btest 模式 | 选择 btest，再选普通 mode | 同一 overlay 状态；退出结束未关闭 run；composer 缓存键更新 |
| 发送上下文 | 同文件 editor、设置关闭、无能力内核、btest card | 按 `dedupeKey` 去重；设置或能力不满足时不带 editor context；btest 文本至多一次 |
| 回退失败 | 内核不实现 `PlansReverts` 却直接调用 | 明确抛 `UnsupportedError`，不退回另一套写入路径 |
| browser 数字门 | 数字字符串、非数字字符串、嵌套 step | 数字按 schema 转换；非数字保留并明确拒绝；嵌套行为不退化 |
| btest 工具门 | off / no-run / readonly / write / 无 tabId | off 结果不变；no-run 与 readonly 给可读拒绝；write 按规则；无 tabId 仍调用原工具 |
| host 推导 | entry URL、tab 当前 URL、未知 tab | 分别得到 URL host、tab host、未知 host；未知不伪造成允许 |

### 29.9 边界、UI 与 RTM

不改 `ide_scm_view.dart` 或其它 SCM 产品语义；#181 仍未裁定，本设计只保留接缝。不改上游 picker 布局、不恢复被覆盖的旧共享档、不改外仓、不为 overlay 添加配置项或新 UI 入口。

UI 保持现有入口：btest 仍位于 mode picker 与 composer 状态行；命令面板按能力显隐；改名、回退与通知沿用既有视图。无未落定的 UI 决策。

RTM 从 `test/RTM.md` 现有 3 行出发：

- **不改写 / 删除**：1-1、2-1、3-1 的业务断言不变；R1 不新增行。
- **新增 4-1**：「切换 btest 后，提示与浏览器门使用同一会话状态」。用户入口 = composer 的 mode picker；交互 = Composer ⇄ ChatSession overlay ⇄ BrowserTools / BtestGate。
- **4-1 断言**：切到 btest 后下一 turn 的 card 恰一次；readonly 写调用被拒且原因可读；切回普通模式后 off 文本恰一次；工具与 composer 读到同一 run / 开关状态。
- **回溯需求**：`docs/requirements/browser-biz-test.md` §3 F1/F2/F9/F11。落点 = `test/integration/btest_flows_test.dart`，标题以 `4-1` 开头。该用例有真实用户入口和业务结果，不是把单元断言提升成集成用例。

集成规模由 3 / 50–100 变为 4 / 50–100。没有其它新增行。
