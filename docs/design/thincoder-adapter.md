# thincoder 内核适配 设计档

> 板块：内核适配（thincoder 桌面接入）· 范围仓：baocode。
> 配对需求档：`docs/requirements/thincoder-adapter.md`（用户已确认，2026-10-16）。
> 分批：**批 1 = 本地内核全链路**（需求档 F1–F7、F10 + 扩展性 E1–E5，本档详写）；批 2 = 远程 SSH（F8）；批 3 = Customize 对接（F9）；**批 4 = 子代理活动可见（F11，§15）**；**批 5 = 子代理内容归属（F12，§16）**；**批 6 = 审批自动档 + 模型清单与思考档位（F13 / F14，§17）**；**批 7 = 工作中发送的消息（F15，§18）**；**批 8 = 回合结束后继续关注后台子代理（F16，§19）**。
> 先例坐标对照基准：`lib/kernel/claude_code/`（完整适配）· `lib/kernel/codex/`（薄内核）。
> 状态：设计稿 · 2026-10-16 · 本文档中行号 = 编制日快照（实施时按符号定位）。

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
- 反向请求应答器：`session/request_permission` → 审批流（§4 F4）；`fs/read_text_file` / `fs/write_text_file` 与**一切未知方法** → 立即回 `-32601` 错误（"得体降级"：服务端不会干等它的超时）。
- **未知通知 / 未知 `sessionUpdate` 变体 / 已知通知里的未知字段**：忽略；协商与未知方法留痕走 `appEvent('thincoder', …)`（`lib/platform/event_log.dart:84`）（E4）。

### 3.4 ACP 线形（本适配用到的全部；逐条与 thincoder 源对位）

**请求（我方 → 服务端）**

| 方法 | params | 结果 / 通知 |
|---|---|---|
| `initialize` | `{protocolVersion: 1, clientCapabilities: {}}` | `{protocolVersion, agentCapabilities, authMethods, agentInfo{name,version}}`（`client-caps.mjs:46-64`） |
| `session/new` | `{cwd, mcpServers: []}` | `{sessionId, configOptions}`（`handlers-session.mjs:163-243`） |
| `session/load` | `{sessionId}` | `{configOptions}`；**之前**逐条重放历史通知（`handlers-slots.mjs:64-138`） |
| `session/resume` | `{sessionId}` | `{configOptions}`；不重放（`handlers-slots.mjs:140-197`） |
| `session/list` | `{}` | `{sessions: [{sessionId, cwd, updatedAt?, title?}]}`（`handlers-slots.mjs:42-61`） |
| `session/delete` | `{sessionId}` | `{}`（`handlers-slots.mjs:199-223`） |
| `session/prompt` | `{sessionId, prompt: [{type:'text', text}]}` | `{stopReason: 'end_turn' \| 'cancelled'}`（`handlers-session.mjs:245-263`） |
| `session/cancel` | `{sessionId}` | `{}` |
| `session/close` | `{sessionId}` | `{}`（未知会话也回 `{}`） |
| `session/set_mode` | `{sessionId, mode: 'plan'\|'normal'}` | `{}` + 通知 `current_mode_update{currentModeId}`（`:321-341`） |
| `session/set_config_option` | `{sessionId, configId, value}` | `{configOptions}` + 通知 `config_option_update{configOptions}`（`:292-319`） |

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
| `session_info_update` | `_meta["thincoder.dev/subagent"]`（子代理信号；翻译 = §15.2）∥ `_meta["thincoder.dev/turn"]`（自动轮边界；翻译 = §19.2） | `bridge.mjs:232` ∥ `acp/suspension.mjs`（批 8 新增） |

**反向请求（服务端 → 我方，须回包）**

| 方法 | params | 我方应答 |
|---|---|---|
| `session/request_permission` | `{sessionId, options:[{optionId,name,kind}], toolCall{toolCallId,title,content[]}}`（选项序 = approve_once / approve_always / reject，`bridge.mjs:49-54`） | `{outcome:{outcome:'selected', optionId}}` ∥ `{outcome:{outcome:'cancelled'}}` |
| `fs/*` · 其它 | — | `-32601` 错误（不挂） |

（服务端反向请求自带超时：传输层默认 60s（`acp/transport.mjs:42`），按方法覆写——审批 5 分钟（`bridge.mjs:319`）、`fs/*` 30 秒（`bridge.mjs:143`/`:152`）；超时或失败按拒绝处理——我们不回包也不会卡死它。）

（我方请求超时口径：`session/prompt` **不受连接缺省 60s 约束**——prompt 的响应在回合结束才到达（`bridge.mjs:23-24`）、回合时长无上界，任何有限上界都会在长回合触发「got no answer」误报与错标 interrupted。实现形态 = `session/prompt` 调用显式不设超时（`ThincoderConnection.request` 区分「缺省（60s）」与「显式不设超时」），其余请求照旧。）
（`session/prompt` 的兜底 = 取消 / 进程健康（两者均已实现）：`session/cancel` ⇒ 服务端以 `stopReason:'cancelled'` 收束在飞请求（F3）；进程死 / 传输结束 ⇒ 在飞请求随连接收束、回合 `TurnEnded(interrupted: true)`（§3.6）。被否「远大于回合尺度的上界」：只为悬挂态加猜测性截断——上述两条兜底已给确定性出口。）

### 3.5 会话生命周期（状态机）

```text
无会话 ──prepare()/send()──▶ 起进程 → initialize → 建会话：
    · 没有续接记录            → session/new          （槽号 = 新认领）
    · 有续接记录、本内核未载入 → session/load         （重放历史；sessionId = 记录 id 原文）
    · 本内核已载入过（重连）   → session/resume       （不重放；避免历史重复进 transcript）
活跃 ──release()──▶ session/close（best effort）+ 进程退出；槽号留在内存以备 resume
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
| `send()` 接受回合 | `TurnStarted(turnId)` + `ItemUpserted(turnId, UserMessageItem(text: 实发文本))` |
| `agent_message_chunk` | 文本项：首块 `ItemUpserted(id, AssistantTextItem(''), streaming: true)`，其后 `TextDelta(id, offset, text)`；项 id = `"t<序号>.<块序号>"` 形态由适配层自定（本层自持 id 空间）。**带 `_meta` 归属标 ⇒ 入该子代理的谈话，不带 ⇒ 本行（主对话）**（§16.2） |
| `agent_thought_chunk` | 思考项：同上，`ThinkingItem(text, tokens: 已收字符数, startedAt)`（tokens 近似先例 = `codex_kernel.dart:296`）；归属标同上（§16.2） |
| `tool_call` | `ItemUpserted(toolCallId, …)`，按 kind 成形（表下）；**带 `_meta` 归属标 ⇒ 入该子代理 children，不带 ⇒ 主对话**（§16.2） |
| `tool_call_update` | 同 id 替换：`completed` → 状态 succeeded（终端项填 output=内容文本）、`failed` → failed；归属标同上（§16.2） |
| `usage_update` | `UsageReported(ContextUsage(window: size, used: used))` |
| `config_option_update` | 更新选择项 + `KernelInfoChanged` |
| `current_mode_update` | 更新模式选择项 + `KernelInfoChanged` |
| `user_message_chunk`（重放） | 用户项（连续块并入一项，遇其它类型封口）；重放帧不止此类——助手文本 / 工具帧同路还原（§16.1 重放面） |
| `session_info_update`（子代理 meta） | 子代理卡片 upsert + `TasksReported` 全量重报（§15.2） |
| `session_info_update`（turn meta） | 自动轮边界：start ⇒ `TurnStarted(unprompted: true)`（用户回合在飞 ⇒ 暂存）；end ⇒ `TurnEnded(interrupted: ok==false)`（暂存位非空 ⇒ 撤暂存、不成轮；`ok` 只认布尔 `false`）（§19.2） |
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

### F7 检测与引导

- 定位：设置项 `thincoder.path`（settings.json），空则按 PATH 探测（登录 shell 环境）；找到 → 执行；找不到 → 健康 failed，文案含 `npm install -g thincoder` 与 Node ≥24（`thincoder-cli/package.json:19-23` engines）。
- `-32000 authRequired`（`handlers-session.mjs:85-105`）→ 健康 failed，detail = **服务端 message 原文**（已可行动：指向 `~/.thincoder/config.json` 的 `providers[].apiKey` 与 `thincoder acp --login`）+ 我方前置一行"thincoder 未登录"。
- 版本下限：常量 `thincoderVerifiedVersion = '0.12.74'`（编制核对版本 = `thincoder-cli/package.json:3`）；`agentInfo.version` 低于下限 ⇒ 会话内 `NoticeItem(NoticeKind.warning)` 明示 + 设置行标注，**不阻断**（D13）。
- 不声明 `auth.terminal`（本批不做"在终端里执行登录"动作，声明即虚报）；`initialize.authMethods` 因此为 `[]`（`client-caps.mjs:28-37`）。
- 展示面：对话内健康横幅（`health_banner.dart:23-24` 既有机制）+ Settings → General 的 thincoder 行（路径 + 找到与否 + 版本，形同 Claude Code 行 `general_page.dart:357-376`）。

### F10 用量展示

- `usage_update{used,size}` → `UsageReported`；`ReportsContext.contextWindow` 在首个回报之前用 128 000（thincoder 未知模型兜底值，`bridge.mjs:252`；非虚构），此后以回报为准（`chat_session.dart:419-423` 取 transcript 的最近回报）。
- 模型/供应商配置只读：桌面不写 `~/.thincoder/config.json`、不改 provider/key（B3）。

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

（`lib/kernel/claude_code/**` 零改动；`thincoder/**` 在本仓零改动——B1；thincoder 侧的接口例外见 §16.1。）批 4 的改动点见 §15.4（同为最小接线点集）；批 5 的改动面见 §16.4（本仓测试面 + out-of-repo 档）；批 6 见 §17.4（本仓适配层两面 + 宿主 1 档 composer 开关 + 两处测试面）；批 8 见 §19.4（本仓 1 档（kernel）+ 固件 / 测试面；thincoder 侧 = out-of-repo 档）。

**接线点 ⑤ 细则（按内核判定）**

- 做法（选 ⓐ；被否 ⓑ）：`load()` 第一回路按内核记账 `covered: Map<KernelDescriptor, Set<String>>`（内核 → 其 `projects()` 覆盖过的路径）；`_folders` 每个目录求「未覆盖内核子集」（有 catalog ∧ 未被该内核覆盖），子集非空才 `_listKept(project, kernels: 子集)`（仍不等待）。
- `_listKept` 加内核子集参数，缺省 = 全部内核：`_openProject`（`:415`）与 `_listWhenReached`（`:453`）用缺省，语义不变。
- 被否 ⓑ（每个已知项目全量 `_listKept`）：claude 被逐项目重复整读（`:420-421` 的代价面），且起进程数从「未覆盖内核」涨到「全部内核 × 全部项目」。
- 守卫（`:322-326`）——采纳 + 修正：方向采纳（无守卫则逐目录列出在途时 `_forgetGone`（`:1684-1740`）会把未及列出的会话的 pinned/archived/names/drafts 当「已消失」清掉并落盘 = 数据受损）；判据 = **逐内核**：本轮没有触发逐目录列出才清理（等价：每个目录都被每个有 catalog 的内核覆盖）——合并集不再胜任：按内核判定后，合并集已覆盖的目录同样有在途列出。
- 扫描失败的内核不记覆盖 ⇒ 其目录照走逐目录列出，`complete` 照旧拦清理（"what one failed to list is not gone" 不变）。
- 代价（登记 §14-11）：thincoder 的 `projects()` 恒空（D6）⇒ 只要 `_folders` 非空就有未覆盖内核 ⇒ 卫生清理整体推迟、`_folders` 不再被剪除（`:1695` 的剪除只在清理运行时发生）——每轮 load 逐目录再列（每目录一次短命连接，D4/D6 既定形态；这正是「终端建的会话下次打开可见」的来源）。后果有界、非数据损坏。

各修改文件当前行数（2026-10-16 快照，供评审核体量）：`kernel_registry.dart` 46 · `agent_kernel.dart` 423 · `chat_session.dart` 1087 · `workspace.dart` 2795 · `main.dart` 733 · `general_page.dart` 796 · `app_settings.dart` 268 · `mock_kernels.dart` 48 · `data_dir.dart` 409。
本批对上述各档的净增上界（`≤ N 行` 式；实施后按各档 diff 核，超出 ⇒ 核接线点范围）：① ≤11 行（含 2 条 import）· ② ≤12 行 · ③ ≤4 行 · ④ ≤10 行 · ⑤ ≤14 行 · ⑥ ≤6 行 · ⑦ ≤81 行（新行 widget，形同 `_ClaudePathSetting`）· ⑧ ≤10 行 · ⑨ ≤16 行 · ⑩ ≤2 行。

体量立场（三个 >800 行既有档 + 新档的拆分审阅）：

- `chat_session.dart`（1087 行）处 >800 行硬顶之上：**本批不动结构**（只走接线 ③）；拆分缝候选 = Facets（`:329`）/ Projections（`:510`）/ Commands（`:920`）段（段头注释即缝）；触发 = 独立拆分批立项。
- `chat_screen.dart`（1231 行）处 >800 行硬顶之上：**批 4 不动结构**（只走接线 ⑬，1 行改动 / 净增 0）；拆分缝候选 = `_ChatScreenState`（`:182`）之后的私有构件族（`:903`–`:1231`：标题栏布局 / 会话列渲染 / 底部切换 / 历史载入 / 面板槽）；触发 = 独立拆分批立项。
- `workspace.dart`（2795 行）处 >800 行硬顶之上：**本批不动结构**（只走接线 ④⑤；⑤ = `load()` 回路内改造 + `_listKept` 参数化，不新增文件、不拆类）；拆分缝候选 = The IDE's windows（`:727`）/ SSH hosts（`:1281`）/ Color theme（`:1858`）段（段头注释即缝）；触发 = 独立拆分批立项。
- `thincoder_kernel.dart`：>800 行触发已执行——拆分前实测 1168 行 ⇒ 拆出 `thincoder_events.dart`（§3.6 事件翻译段，外部形态不变）；残余 899 行（2026-10-16 只读实测，`wc -l`）仍处 >800 线上：**续拆裁定 = 不续拆**（同其他 >800 行既有档：本批不动结构）；
下一缝候选 = 选择面段（`_Choice` / `_ModelSetting` + mode/model/effort）；触发 = 独立拆分批立项（或下次触碰该档时顺拆——「触碰」按结构级改动计；行级接线不计，如批 4 +3，见 §15.4）。

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
| D7 | 图片：不声明 `AcceptsImages`；新增 `AcceptsImageFiles` + 落盘 + 路径行 | 需求档 F6 原文；不复制终端 `read_image` 指令（桌面不知模型多模态性） |
| D8 | 不声明 `StartsPlans`，计划以对话文本呈现 | 协议面无计划对象/文件；终端同形；声明了就得造假计划卡 |
| D9 | 模型候选 = `configOptions.options`（当前一项）；不读 config.json、不直连 provider `/models` | 需求档 §5 口径就是 `set_config_option` + `config_option_update`；读 config.json 拿不到清单（渠道不携模型），直连 `/models` 要用户的 key（B3 张力）且要复刻三种渠道格式（`model-picker.mjs:294-319`）。E3 钩子：thincoder 填多候选即亮 |
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

需求档条目覆盖（三方一致链）：F1–F7、F10–F16、E1–E5 全部有落点；F8/F9 只留接口（§13）；B1–B4 遵守——B1 默认不改 thincoder 仓，例外 = 经用户裁定的最小接口改动（F12 归属标 §16.1；F13 / F14 的 configOptions 投影 §17.1-① / §17.3-①②；F16 的 ACP 挂起窗 + 回合边界帧 §19.3）。

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
- **固件**（`test/fixtures/thincoder/*.ndjson`）：每文件 = 一个场景的帧序列（服务端发出的行 + 期望客户端动作清单）；`thincoder_fixtures_test.dart` 逐帧回放并断言 transcript 结果。用途 = 离线回归：**thincoder 更新后先跑固件**（不装 thincoder 也能验协议面是否变形），变形 ⇒ 按 §12 清单核对。
- 真机冒烟（可选、默认 skip）：`-t e2e-thincoder` 起真 CLI 走一遍 A3/A4 的最短路径，照 `dart_test.yaml` 的 e2e 形。
- 既有测试不回退：`flutter test` 全量；特别关注 `test/kernel_test.dart`、`test/kernel_ui_test.dart`（D18 已避开默认内核面改动）。
- 队列面（批 7）：§18.7 用例（T63–T67）入 `thincoder_kernel_test.dart`；mock 加一个可变参数 `promptError`（T67③ 的失败面）。**不加固件**：本批不发新帧（还是 `session/prompt` / `session/cancel`），队列顺序由 T63 / T64 用 `requests()` 逐帧钉住；回放虽有发消息动作（`thincoder_fixtures_test.dart:102-106`），加 `queue.ndjson` 只会重复同一断言。既有固件保持绿 = 回归哨兵。
- 挂起面（批 8）：§19.7 的 T68–T74 入 `thincoder_kernel_test.dart`；固件新增 `digest-turn.ndjson`（`_check` 增 `unprompted` 键），既有 `subagent-digest.ndjson` 不改（旧 CLI 兼容哨兵）；thincoder 侧由 out-of-repo 轮按该仓惯例落单元测试档（`docs/batches/<batch>.test.mjs`）。
- 子代理面（批 4）：§15.7 用例入 `thincoder_kernel_test.dart`；固件新增 `subagent-*.ndjson`（`_shown` 增卡片行与 `tasks` 断言）——「先跑固件」口径不变。
- 子代理内容面（批 5）：§16.7 用例（T42–T50）入 `thincoder_kernel_test.dart`；固件新增 `subagent-content*.ndjson`（`_check` 增 `agents` 键）——「先跑固件」口径不变。thincoder 侧机制由 out-of-repo 轮的一次性探针钉形（§16.1：该仓测试清单为空，不向空清单塞档）。
- 选择面（批 6）：§17.7 用例（T51–T62）入 `thincoder_kernel_test.dart`，T61（形态面 widget）入 `test/composer_test.dart`（mock 加 `autoApprove` / `models` / `thinkingLevels` / `configError` 四个可选脚本参数，缺省 = 今天的形状；
  T61 的 thincoder 一半 = `ThincoderMock(autoApprove: false)` + 自建 descriptor，Claude 一半 = 既有 `pumpScreen`）；**不加固件**——回放没有「点选择器」的动作（`thincoder_fixtures_test.dart:84-125`），选项面在 kernel 测试断言；既有固件保持绿即回归。thincoder 侧机制同样由 out-of-repo 轮的一次性探针钉形（§17.1 / §17.3 的探针期望）。

---

## 10. 边界（本批不做）

- 需求档 B1–B4 全部沿用：B1 默认不改 `thincoder/`；例外 = 经用户裁定的最小接口改动（F12 归属标 §16.1；F13 / F14 的 configOptions 投影 §17.1-① / §17.3-①②；F16 的 ACP 挂起窗 + 回合边界帧 §19.3）；❌ 各项不做（图片直传 / 多文件夹 / fork / 回退 / 后台任务 / MCP 管理 / 账号用量 / 建议类 / 改名 / `context` 与 `fast` 两个选择器档——指 context-size 与 fast 面）。
- `effort` 档位面**不在上条边界内**：多档随批 6 落地（§17.3-③，`thinkingLevel` 上报即有列表）。
- 本档新增不做：计划卡（D8）；终端登录动作（D12）；`checkpoint/*`·`memory/*`·`ledger/*`·`batch/*` 扩展族（不接）；审批「总是」= 会话级 auto（§17.1-④；与终端 `/auto` 同源），更细的作用域（按工具）不做。（子代理显示面 = 批 4、子代理内容归属 = 批 5 已接；边界见 §15.8 / §16.8。）
- 队列面（工作中发送的消息）= 批 7 设计已定（§18）；本批边界见 §18.9。
- 挂起面（回合结束后继续关注后台子代理）= 批 8 设计已定（§19）；本批边界见 §19.8（timer 唤醒 / 自动轮审批 / 重放边界 / 只停一轮不做）。
- `FileEdited` 事件不发：ACP 的 `tool_call` / `tool_call_update` 不带 diff（`bridge.mjs:259-292`），无可靠增删行数 ⇒ 变更审查面板按既有快照面工作（§14 登记）。

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
| 5 | 变更审查面板无增量 | 不发 `FileEdited`（无 diff 来源）。判定条件：协议面补 diff（`tool_call_update.content` 变体）或走 `fs/write_text_file` 路由（届时开 `fs` 能力位） |
| 6 | 终端新会话的实时同步 | 窗口聚焦刷新（`workbench.dart:513`）时 thincoder 不重列（D6）。判定条件：用户要"开着桌面看终端建会话"⇒ 加"逐项目重列 + 节流"或 thincoder 补跨 cwd 枚举 |
| 7 | 会话 id 组合形与"半合法路径" | 拆解取最后一个 `\|`；Unix 路径可含 `\|`（罕见）。判定条件：出现歧义（同项目 id 拆错）⇒ 改分隔形（如 json 编码） |
| 8 | 版本下限的"下限" | 0.12.74 = 编制核对版本，非 thincoder 承诺的兼容下限。判定条件：用户裁定支持更旧版本 ⇒ 调常量与核对清单 |
| 9 | 同槽 fork 后记录 id 不刷新 | 同槽被占用时 `session/load` 服务端 fork 到新槽（`handlers-slots.mjs:104-126`），回包无新槽号通道（只有 `{configOptions}`）⇒ 桌面记录 id（D5）仍指旧槽，批 1 按"以服务端语义为准"落地。验收观察点（A3 走查）：终端与桌面同开一个会话 ⇒ 桌面侧 prompt 正常收尾、delete 后两侧列表一致、目录无重复项；观察到旧槽指向（delete 未生效 / 列表重复）⇒ 补"fork 后 id 回流"面（通道另定：通知或回包位） |
| 10 | 能力位声明取固定面（非回包驱动） | 首版按需求档 §5 固定面声明：`LoadsHistory` / `StartsPlans` 为真、`AcceptsImages` 不声明，不随 `initialize` 回包逐位翻转；回包位（`client-caps.mjs:52-64`）用于留痕与版本告警兜底（D13）——旧版 `loadSession=false` 时仍声明历史载入，由版本告警承接。判定条件：需要按回包位区分能力（如旧版隐藏历史载入）⇒ 逐位收敛（E3） |
| 11 | 「未列目录」时卫生清理整体推迟 | `_forgetGone` 只在本轮没有触发逐目录列出时运行（§5.2-⑤）：thincoder 的 `projects()` 恒空（D6）⇒ `_folders` 非空即有未覆盖内核 ⇒ pinned/archived/names/drafts 的清理整体推迟、`_folders` 不再被剪除（每轮逐目录再列）。有界、非数据损坏（只留旧标记，不误删）。判定条件：旧标记堆积 / 状态档见大，或要恢复清理 ⇒ 守卫改「本轮触发的逐目录列出全部返回后再清理」（清理移入 `_listKept` 收尾） |
| 12 | `session/close` best-effort 的残余 | close 只写不等、随即进程退出（§3.5）⇒ 认领是否真释放不保证；「有界等待」会引入本批无法实测的时序依赖 ⇒ 本批不做。判定条件：真机走查确认会话确已释放（残留 ⇒ 加有界等待） |
| 13 | 「会话已不在」（续接记录一路）的兜底 | 处置定死（§3.5）：`session/load` / `session/resume` 收 `-32602`（`gone`）⇒ 忘槽、起新会话（不留启动死结；两路同此处置）；兜底起的新会话跨 `release()` → `prepare()` 续接（同一运行内；记「记录槽已忘」标记，此后走保留槽路线，不重走 `session/load` 死槽）。实现已随末修单落地。判定条件：终端删掉会话后，桌面打开该记录 ⇒ 起新会话、可发消息；此后重连仍续接该会话，不再永久启动失败（真机走查 T15） |
| 14 | ⑦ 设置组文案英文占位 | 新行与状态行英文直写（`general_page.dart:768-770`/`:790-791`、`thincoder_locator.dart:56-59`）；本机无 `flutter gen-l10n`、生成档不可手改 ⇒ 口径 = 英文占位接受；补齐窗口 = SDK 就位轮（补 `app_en.arb` / `app_zh.arb` 键 + 生成档重产 + 设置行改用 `context.l10n`）。判定条件：补齐后 zh-cn 该行显示中文、与同页 Claude Code 行一致 |
| 15 | 子代理状态文案英文占位 | 卡片 activity 与活动条详情 / 定格文英文直写（`queued` / `turn <n>/<maxTurns>` / `approval · <tool>` / `thincoder stopped`，§15.2）。同因 = §14-14（本机无 `flutter gen-l10n`）；补齐窗口 = SDK 就位轮（与 14 同轮补 `app_en.arb` / `app_zh.arb` + 生成档重产） |
| 16 | 子代理工具卡的归属与结果 | 归属已接（批 5）：工具帧带同一 `_meta`、本仓路由进 children（§16.1 / §16.2）。结果面仍缺：结果不经 ACP（`spawn-child.mjs:159-161`；`wrapChildCallbacks` 不包 `onToolResult`）⇒ 视图内工具卡停在 in_progress（不伪造终态，§16.8-1）。判定条件：补结果通道 ⇒ `tool_call_update` 路由自动闭合；输出通知另接 |
| 17 | 子代理内容不落盘 | 谈话表随进程（`endSubagents()` 清；§16.8-4）。重开桌面后卡片只剩状态、无 children。判定条件：需要事后回看 ⇒ 另立持久面（会话存档无此字段） |
| 18 | 「Approve for this session」名不副实 | **已闭合（桌面侧；批 6）**：面板选 always ⇒ 先答本次，同一回合写 `autoApprove=true` ⇒ 会话级承诺成立（§17.1-④；用户 2026-10-16 21:47 裁定）。服务端 `approve_always` 仍无记忆（`bridge.mjs:57-62`），桌面不再依赖它；残余判定条件见 §17.1-④ 两条（CLI 改名 / 摘掉、按工具会话级放行表） |
| 19 | 审批开关与档位标签英文占位 | 审批两项（`Ask` / `Auto`）、其 description（开关 tooltip 的第二句）与档位名（`effortLabel`）英文直写；`localizedKernelOption`（`kernel_option_text.dart:8-46`）只认 claude 元组，未知元组原样透出 ⇒ 英文占位接受。同因 = §14-14；补齐窗口 = SDK 就位轮（同轮补 `app_en.arb` / `app_zh.arb` 键 + 生成档重产） |
| 20 | 模型清单后台推送的落地面 | `refreshModelChoices` 是 fire-and-forget（§17.3-①）：落地时会话已关 / 已被 load·resume 替换 ⇒ 丢弃；`notify` 抛出（管道已断）⇒ 吞掉并记一行日志，不重试、不抛。判据 = 会话在册且同实例（`liveSession(id)?.agent === agent`，`acp.mjs` 的 ctx 包装传入）。判定条件：观察到清单在会话关闭后仍被推送 / 进程因未处理的拒绝退出 ⇒ 复核该判据 |
| 21 | timer 唤醒轮不在 ACP 面 | 挂起窗不接 `timerFace`（§19.3-①）⇒ 桌面会话里到期的 timer 不在后台自起一轮，等下一个用户回合边界才投递。判定条件：桌面需要 timer 唤醒 ⇒ 接 `timerFace`（`suspension.mjs:173-205` 第四态）+ 边界帧 `kind:"timer"` |

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
3. **children 有来源、其余五类无**：children = 该子代理的谈话（批 5 起由 §16.2 写入）；result / prompt / tokens / toolUses / model 无来源（子代理内容归属不在 ACP 契约内，ACP-CLIENT.md §12.6；批 5 只补了内容帧与工具帧的归属标）⇒ 这五类不填；嵌套按最内段扁平展示（父链不承载，同 §12.6）。

### 15.2 信号翻译（ACP → 既有面）

**线形**：`session/update` 通知，`update.sessionUpdate = "session_info_update"`，载荷在 `update._meta["thincoder.dev/subagent"]`（发射 `bridge.mjs:228-232`；形状冻结 = ACP-CLIENT.md §12.2）：

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
- `cancelled` 契约语义 = 排队取消（从未启动，出队即终态；ACP-CLIENT.md §12.3）——上游唯一发射点 = queued 取消（`subagent-async.mjs:297`）；running 取消走 abort ⇒ `⟦ev⟧stopped` 冻结（同档 `:222-226`；TUI 守卫「cancelled 永不合法指向 running 块」`subagent-blocks.mjs:184-186`）⇒ 已建任务下收到属契约外失序：按终态移除处置（不残留 running；不判 failed——取消 ≠ 失败，D24 口径）。
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
| D26 | digest 的回合边界由 CLI 的回合边界帧界定，桌面起 unprompted 回合（§19.2 / D55–D61） | 边界必须来自服务端的确定信号。被否：静默期计时闭合（时序 hack）；被否：首个 chunk 合成回合（无收束信号 ⇒ `isStreaming` 永久为真） |
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
| f | `docs/cli/design/ACP-CLIENT.md` §5 表（`:171-172`） | 内容两行各补一句：relay 前缀在场 ⇒ 同通知带 `_meta` 归属标（§12.7）；文本面零改 |
| g | 同档 §7.2（`:314`） | 「工具卡 title 不带归属标」句改写：title 仍不带（显示面剥离），帧级 `_meta` 已带（§12.7） |
| h | 同档 §12.6（`:590`） | 「内容面归属不在本档」条改为指向 §12.7（该边界已闭合） |
| i | 同档 §12 尾（§12.6 之后） | 新增 `### 12.7 归属帧标（内容帧与工具帧）`：承载体 / 形状 / 规则 / 嵌套 / 重放面 / 结果面口径 |
| j | `docs/cli/requirements/ACP-CLIENT.md:90-91` | R-A5.11 补一句：归属标（与「文本面剥离」并列，同键同源；含工具帧） |
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
- **重放面**（`replayHistory`，`bridge.mjs:389` 起）不加本标：重放走独立路径（不经过上面四个回调），还原来源 = 槽文件里的主会话历史（`agent.history`，`thincoder-core/session.mjs:184`）——逐条发 `user_message_chunk` / `agent_message_chunk` / `tool_call` / `tool_call_update`（`bridge.mjs:413` / `:436` / `:425` / `:441`）。
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

**版本口径（是否 0.12.75）**：**不预占号**。该仓纪律 = 号在发布时定、开发期只挂 `[Unreleased]`
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
- **桌面 → 终端**：`set_config_option` 只改内存（与 model / thinking 同口径，`:107-111`），落盘靠**既有的**回合末存档（`acp/session.mjs:44` `save(agent)` → `thincoder-core/session.mjs:139` 写 `autoApprove`）⇒ 终端下次打开同槽读到的就是它。**不新增写盘路径**。
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

判据（一句）：**仅当 §17.1 的跨仓轮无法在用户要的时间窗内落地、且用户明确要先有自动档时**，才启用本地兜底——内核在自己的反向请求入口（`thincoder_kernel.dart:556-595` `_serverRequest`）对 autoApprove 为真时直接回 `{outcome:{outcome:'selected',optionId:'approve_once'}}`、不发 `InteractionRequested`，开关仍借 `SelectsPermission` 显示。
**互斥**：§17.1 在位时开关的真值在服务端，本地再自答 = 同一件事两个真相（且服务端已不问，本地分支永不可达）⇒ 二者不并存；真启用时另立用例与走查。

### 17.3 F14 · 模型清单与思考档位

一句话：`configOptions.model.options[]` 从「当前一项」改为**运行期清单投影**（各渠道拉 `GET /models`，去重后 `provider:model`）；思考在布尔面之外**并行**投影一个档位面 `thinkingLevel`（select）。桌面：模型面**零改动**（既有 `model` 面就按 `options[]` 渲染，`thincoder_kernel.dart:693-697` + `thincoder_events.dart:179-188`）；档位面给 `effort` 加一条读取分支。

**① CLI 侧：模型清单（`sessionConfigOptions` 是同步的 ⇒ 缓存 + 预取，不在投影里拉网络）**

- 缓存位 = `agent._modelChoices`（`{value,name}[]`，本会话一份）。
- 拉取时机 = **会话建好之后后台一次**（`defaultCreateSession` 里 fire-and-forget，`acp.mjs:81-84`）；落地后以 `config_option_update`（全量数组）推给客户端 ⇒ 桌面走既有路径刷新。**会话启动不等网络**（10s/渠道的上界不进首包）。被否：在 `sessionConfigOptions` 里拉（它是同步函数，且被四处响应 + 两处通知同源调用）。
- 三路会话同经该装配：`acp.mjs:100` 的缺省 `createSession` → `:116` 的 ctx 包装 → `handlers-session.mjs:195`（`session/new`）· `handlers-slots.mjs:99`（`session/load`）· `:169`（`session/resume`）⇒ 清单投影三路一致；注入式 `createSession` 的测试路径不经过（零网络）。
- 落地判据（fire-and-forget 的存活面，登记 §14-20）：落地时会话仍在册且仍是同一实例（`liveSession(id)?.agent === agent`，`acp.mjs` 把 `sessions` 的查取回调传进装配）——已关 / 已被 load·resume 替换 ⇒ 丢弃；`notify` 抛出（管道已断）⇒ 吞掉并记一行日志，不重试、不抛。
- 清单来源 = `agent.config.providers`（**不是** `agent.providers`——后者是 TUI 会话字段，ACP 装配不设它；`cmd-config.mjs:76` / `make-agent.mjs:31-51`）。
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
| d | `docs/cli/design/ACP-CLIENT.md:41`（方法表 `set_config_option` 行） | 「model / thinking / mode 分发」→「model / thinking / thinkingLevel / mode / autoApprove 分发（见 §5.3）」 |
| e | 同档 `:212-221`（§5.3 configOption 映射） | 表补两行（`thinkingLevel`：`"off"` ∥ 档名 ⇒ 开 / 关两形；`autoApprove`：boolean ⇒ `agent.autoApprove`，与会话槽同源）；`model` 行补一句 `options[]` = 运行期清单投影；表下补一段「清单投影：`agent._modelChoices` 缓存 / 会话装配后后台拉取一次 / 落地推 `config_option_update` / 拉不到的渠道只报当前项 / 失败不缓存」 |
| f | 同档 `:223-231`（§5.4 审批通道） | 补一句：`agent.autoApprove` 为真 ⇒ 审批在核 `dispatch` 阶段短路（`dispatch.mjs:177`），**不进** `onPermissionRequest`——ACP 面零改 |
| g | `docs/cli/requirements/ACP-CLIENT.md:80-81`（R-A5.4） | 补一句：`configOptions` 可含 `autoApprove`（boolean）与 `thinkingLevel`（select）；`model.options[]` = 运行期清单投影（拉不到的渠道退化为当前项）——新项对旧客户端**忽略即合规** |
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

   复现前提：`providerSpec` 只按 `provider.model` 取值（`model-specs.mjs:331-336`；另有 `provider.context` 覆盖，不看 provider.name / 渠道类型）——fixture 的 `qwen3.8-max`（`model-specs.mjs:114`，effort 枚举 = `xhigh` / `medium` / `low`）与 `glm-5.3`（`:69`，`thinkAlwaysOn`）都是真实规格行，期望读数可自证。
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
5. **模型清单的失败面**：拉不到的渠道只报当前项，失败不缓存（下次会话再试）；不做「桌面代拉 `/models`」（B3：不代管 provider / key，与 D9 同口径）。
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
- **图片落盘与阈值判定在转正时执行**：`_deliver` 开头的 `_attachImages(turn)`（`:436`）就是 F6 的既有路径。⇒ 队列项预览 = 入队时的原样 N 张；实发时超阈项被弃，气泡里少于 N 张 + 一条 `dropped` warning（`:445-458`）⇒ **预览与实际可能不一致**，差异由那条提示交代——与首条发送同形（F6 的弃图只发生在发出那一刻）。
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
> 两半：**thincoder 仓** `thincoder-cli/src/acp/` 加挂起窗 + 一条回合边界扩展帧（§19.3；out-of-repo 轮执行）· **本仓**把边界帧翻成既有 unprompted 回合（§19.2；宿主与 UI 零改动）。

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
   ├─ pending 非空 ∥ 有未 drain 的上行 ask ⇒ 自起一轮（autoTurn）
   │     ├─ 起：发回合边界帧 start{kind}
   │     ├─ 注入 pending 结果（beginRun，run-start.mjs:39-65；_daSession=true）
   │     ├─ 模型答话 / 工具卡 → 既有 session/update 帧（agent_message_chunk / tool_call …）
   │     └─ 终：发回合边界帧 end{kind, ok}（try … finally 必发；抛错 ⇒ ok:false）
   └─ 池空 ⇒ 自然退出（挂起窗关）
       桌面：start ⇒ TurnStarted(unprompted: true)；end ⇒ TurnEnded
```

桌面侧用的全是既有事件面：`unprompted` 一位 + `TurnEnded` 一收——**不新造 KernelEvent、不改 UI**（E2）。

- 自动轮失败（模型 / 工具 / 注入抛错）不静默：`end{ok:false}` **必发**（`try … finally`），窗按核语义收窗（§19.3-②）；桌面据此收轮 = `TurnEnded(interrupted: true)`（§19.2 翻译表）。

### 19.2 回合边界帧（线上形与桌面翻译）

**线上形**（扩展契约；承 `_meta` 扩展位，同 `thincoder.dev/subagent` 先例，ACP-CLIENT.md §12.1）：

```json
{ "sessionId": "<会话 id>",
  "update": { "sessionUpdate": "session_info_update",
    "_meta": { "thincoder.dev/turn": { "phase": "start", "kind": "digest" } } } }
{ "sessionId": "<会话 id>",
  "update": { "sessionUpdate": "session_info_update",
    "_meta": { "thincoder.dev/turn": { "phase": "end", "kind": "digest", "ok": true } } } }
```

| 字段 | 域 | 语义 |
|---|---|---|
| `phase` | `"start"` ∥ `"end"` | 自动轮开始 / 结束 |
| `kind` | string（开集；现发射 `digest` / `upstream`） | 起因（digest = 结果消化；upstream = 子代理在等回复）；桌面只留痕，不分支 |
| `ok` | 任意（仅 `end`；只有布尔 `false` 有意义） | 该轮正常收尾：`false` = 中断 / 出错；缺省 / 非布尔 / 其它值 = 未中断 |

**命名与取值层（本仓）**

- `_turnKey` = 常量 `"thincoder.dev/turn"`（`thincoder_kernel.dart` 类内 `static const`，与 `thincoder_events.dart:90` 的 `_subagentKey` 同形）。`_notification` 见 `session_info_update` 且 `_meta` 带本键 ⇒ 交 `_turnReport` 处置，不再进 `_events.update`（子代理翻译不读本键；不拦会逐帧落一条「a subagent report to leave alone」E4 日志）。
- `_turnUnprompted` = 内核侧「本轮是自动轮」位：`_beginTurn(id, unprompted: …)` 写入（用户回合缺省 false）。翻译表里「自动轮在飞 ∥ 用户回合在飞」与「`end` 是否本轮的收尾」都以它判定。
- `lastTurnUnprompted` = 宿主**既有** `Transcript` 字段（`transcript.dart:63`，由 `TurnStarted.unprompted` 喂，`kernel_event.dart:17` 既有参）——本批不新增、不改宿主；T68 / T73 断言读 `s.transcript.lastTurnUnprompted`（宿主层），不读内核私有位。

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
| 其它 `phase` / `_meta` 坏形 | — | 忽略 + 留痕（E4） |

**`ok` 的宽容方向（D63）**：收轮的唯一信号是 `end` 本身，`ok` 只是中断标记。把「`ok` 非布尔」当坏帧忽略 ⇒ 在飞自动轮永不收（永久「正在续写」、队列永不排水），正是本批要消灭的停住态；按未中断收只丢一个中断标记。两个方向的代价不对称 ⇒ 取宽容。CLI 侧 `try … finally` 恒发布尔（§19.3-②），非布尔只可能来自别的写入者。

- 暂存的必要性（D57）：CLI 在应答写出后才起挂起窗（§19.3-①），但桌面可能**同批**收到应答与 `start` 两帧——应答的 `TurnEnded` 在微任务里，`start` 的通知先到。暂存到该回合结束再起：不丢 `stopReason`，也不误结束活回合。
- 暂存位的收尾（D62）：帧不带回合 id，配对只能按状态——挂起窗串行，同一时刻至多一个自动轮 ⇒ 暂存位非空 = 「该轮报过 `start`、还没起」，同一用户回合里到的 `end` 就是它的收尾，处置 = **撤暂存**：该轮在桌面不成轮（零 `TurnStarted(unprompted)`、零第二个 `TurnEnded`，`activeTurn` 仍是用户回合）。代价：那轮内容照样入 transcript，只是搭在用户回合的分组里（`lastTurnUnprompted` 保持 false）；用户回合收尾时暂存位已空 ⇒ `_drain()` 照常排水。撤暂存时 `auto:<n>` 的号照旧消耗（id 只需唯一，不要求连续）。
- `_pendingAuto` 在 `_teardown` 清（进程死 / 重启不留幽灵自动轮）。
- 自动轮 id = 客户端自持（`auto:1`、`auto:2`…），与用户 turn id 不冲突；item id 空间随 `_beginTurn` 的 `_events.begin()` 前进（`t<run>.<block>`）。
- 自动轮期间 `send` = 进本地队列（§18：`_turn != null` 分支），结束帧 `TurnEnded` 后由 `_drain()` 发出——与今天「挂起期直接写服务端 FIFO」的差别 = 队列面板可见、可撤回；§15.3「挂起期再发消息」已按此加「无在飞回合时」的限定。

**插入点（`_endTurn`；D57 的落点）**

暂存的自动轮在 `_endTurn` 里 `emit(TurnEnded)`（`:548-557`）之后、`if (_drain()) return;`（`:560`）之前起：

```dart
if (_pendingAuto != null) {
  final pending = _pendingAuto!;
  _pendingAuto = null;
  _beginTurn(pending.id, unprompted: true);
  return;
}
```

- 先起自动轮 ⇒ 本趟不排水、不释放：`_turn` 已非空（`_drain()` 即便被调到也返回 false；`release()` 的自守卫 `:418-421` 同样只置 `_releaseWanted`）⇒ 队列与释放都等自动轮收尾那次 `_endTurn` 再判（D53 的既有形不变）。
- 与 §18.1 的排水同一区间（`emit(TurnEnded)` 后、`_releaseWanted` 前）：有暂存自动轮 ⇒ 起轮并 return；没有 ⇒ `if (_drain()) return;` 照旧。
- 起轮行的 id = 暂存时的 `auto:<n>`；kind 只留痕（`appEvent`）。

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

**② 两种轮**

| 轮 | 何时 | 调用 | 帧 | 应答 |
|---|---|---|---|---|
| 自动轮 | pending 非空 ∥ 上行 ask | `run(agent, "", digestCallbacks, {signal, autoTurn: true, upstreamTurn: <本轮是上行 ask>, suspDriven: true})` | start / end | 无（无请求） |
| 用户唤醒轮 | 挂起期 `session/prompt` 到达 | `run(agent, text, callbacks, {signal, suspDriven: true})` | 不发（应答即边界） | 该 prompt 的应答 |

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
| 池空 | 自然退出；`finishSuspension(idle)` 注入残余 | 最后一轮 `end` ⇒ `TurnEnded`；卡片已 settled |
| `session/cancel`（轮在飞） | abort ⇒ 在飞轮 `end{ok:false}` ⇒ 核 abort 清场 | `TurnEnded(interrupted: true)` + 存活子代理的 `stopped` 帧 ⇒ 卡片 failed |
| `session/close` | `close()` ⇒ 同上 | 会话已关（进程随后退出） |
| 进程退出 / 管道断 | 随进程消失 | 既有 `_exited`：在飞轮 interrupted + 通知 |

### 19.4 受影响文件清单（E2 增量；行数 = 2026-10-17 只读实测）

**本仓（baocode）**

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ㉟ | `lib/kernel/thincoder/thincoder_kernel.dart`（1027） | 回合边界翻译：`_turnKey` · `_autoTurns` / `_turnUnprompted` / `_pendingAuto` · `_beginTurn` 加 `unprompted` 参 · `_endTurn` 起暂存自动轮（`emit(TurnEnded)` 后、`_drain()` 前）· `_notification` 拦截 · `_turnReport` · `_teardown` 清暂存（细见 §19.2） | ≤ +45（⇒ ≤1072）；实交 +43（⇒ 1070）· 修正轮 2 ≤ +12（⇒ ≤1082） |
| ㊱ | `test/kernel/thincoder_kernel_test.dart`（2303） | T68–T74（§19.7） | ≤ +170（⇒ ≤2473）；实交 +168（⇒ 2471）· 修正轮 2 ≤ +45（⇒ ≤2516） |
| ㊲ | `test/fixtures/thincoder/digest-turn.ndjson`（新增） | 新线形场景（start / 文本 / end） | 9 行（原估 ~15） |
| ㊳ | `test/kernel/thincoder_fixtures_test.dart`（211） | `_check` 增 `unprompted` 键 | +3 |
| ㊴ | `test/fixtures/thincoder/README.md` | `expect` 键清单补 `unprompted`；一句回合边界说明 | +3（32 → 35；原估 +2） |
| — | 其余本仓档 | **零改动**：`thincoder_events.dart` · `thincoder_mock.dart` · `chat_session.dart` · `chat_history_view.dart` · `workspace.dart` · `attention_service.dart` · `tips/**` · `l10n/**` | 0 |

**thincoder 仓（out-of-repo 轮执行；该仓自己的批次档 + 单元测试随档）**

| # | 坐标 | 改动 | 增量 |
|---|---|---|---|
| ① | `thincoder-cli/src/acp/suspension.mjs`（新增） | 挂起窗：输入队 · 自动 / 用户轮分发 · 边界帧 · cancel / close · 残余 | 新增 ~150 |
| ② | `thincoder-cli/src/acp/session.mjs`（55） | 回合执行器抽 `execTurn`（含 save）· 回合尾进窗 · 挂起期 prompt 路由 · `cancel` / `close` | +65（⇒ ~120） |
| ③ | `thincoder-cli/src/acp/handlers-session.mjs`（427） | `cancel()` ⇒ `close()` 两处（`:306` new 替换、`:367` close） | 净 0 |
| ④ | `thincoder-cli/src/acp/handlers-slots.mjs`（226） | `cancel()` ⇒ `close()` 两处（`:95` load、`:165` resume） | 净 0 |
| ⑤ | `thincoder/docs/cli/design/ACP-CLIENT.md`（641） | 新增 §12.8「回合边界扩展契约」（§19.2 的线上形 + 兼容句）+ §3.2 会话层一句（挂起窗） | +~40 |
| ⑥ | `thincoder/docs/core/design/AGENT-LOOP-ASYNC-POOL.md` | `:442`「CLI headless / ACP ❌ 不支持」行改「ACP 已支持（ACP-CLIENT §12.8）」 | 1 行 |
| ⑦ | `thincoder/docs/batches/2026-10-17-acp-suspension.md` + 同名 `.test.mjs` | 该仓批次档（§1–§6）+ 单元测试档（假 run 直驱 `createAcpSession`；该仓惯例 = 测试档随批次档） | 新增 |

- **体量**：`thincoder_kernel.dart` 1070 行在 >800 名单；本批 = 会话面行级新增（+43），不动结构 ⇒ 不触发「先立拆分批」；会话面缝候选（§18.4 所列）**追加** `_turnReport` 一条，触发不变。`session.mjs` 与新增档均 <500 行。测试档 2471 在 >800 名单：只加用例，缝候选沿用 §15.4。
- **out-of-repo 边界**：上述 ①–⑦ 由父侧另起 out-of-repo 轮，在 thincoder 仓写它自己的批次档与测试（本仓只出设计，不写外仓文件）。

### 19.5 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D55 | 挂起驱动住在 ACP 会话层（CLI 内），不在桌面 | 池 / pending / `_daSession` 都在子进程的 agent 上，桌面拿不到；核状态机 `startSuspension` 直接复用（三端同源）。被否：桌面定时问「好了没」——无信号源且与终端不同形；被否：桌面按文本猜回合——D26 已否 |
| D56 | 回合边界 = `session_info_update` 的 `_meta["thincoder.dev/turn"]`；不新增 `sessionUpdate` 变体、不加版本门 | ACP v1 无无提示回合的位置；`_meta` 是协议自带扩展位（ACP-CLIENT.md §12.1 先例）；未知变体对严格客户端是未知枚举，`_meta` 忽略即合规（E4 / E3）。被否：桌面按首个 chunk 合成回合（无收束信号，D26）；被否：新变体 `turn_started` / `turn_ended`（协议面越界） |
| D57 | `start` 在用户回合在飞时**暂存**，由该回合 `TurnEnded` 起点；不从信号强制结束回合 | 应答与 `start` 可能同批到达（应答的 `TurnEnded` 在微任务里）；暂存不丢 `stopReason`、不误结束活回合。被否：按信号强制结束用户回合（取消态会丢 interrupted 标记） |
| D58 | 自动轮剥 `onPermissionRequest`（手动档不弹审批）；回调缺席 ⇒ **直接拒绝** | 与终端 D-S7 同判（`tui/suspension-drive.mjs:100-112` 置 null）；无人值守的轮不得挂起等一个没人应答的面板（5 分钟超时也按拒绝）。回调缺席的判决 = 拒绝 ⇒ 自动轮不会静默越权执行需审批的工具。桥侧实现本仓不可读（`unverified`），W5② 钉住。ACP 其余交互位本就无面。被否：照常问审批（与终端不同形）；被否：缺席按放行（静默越权） |
| D59 | `session/cancel` 射程 = 有轮在飞才 abort；空闲时零动作。`session/close` 无条件 abort | cancel 的协议语义 = 停「当前工作」；空闲窗没有工作可停，杀后台池会误伤在跑的兄弟任务。close = 会话收束，必须清场（终端 Ctrl+C 同形） |
| D60 | 进窗点 = 回合尾 + 一个 macrotask（`setImmediate`） | 应答必须先出线（否则自动轮帧与用户回合的收尾同批，客户端会把它们并进用户回合）；不需要应答确认（客户端按 D57 暂存兜住同批） |
| D61 | 自动轮 start 帧**轮起即发**（eager），不按首个输出帧惰性发 | 三端先例（VSC / 桌面 / TUI 都在轮起发边界帧）；「正在续写」指示从轮起可见；空轮无项可显示，残影只有罕见的未读徽标（§19.8-7）。被否：惰性 start（要在出站面拦首个帧，且早失败时没有任何可见面） |
| D62 | 暂存中的自动轮在自己的 `end` 到达时**撤暂存**（该轮在桌面不成轮），不起-再-收 | 帧无回合 id，配对只能按状态：挂起窗串行 ⇒ 同一时刻至多一个自动轮，暂存位非空 = 「报过 `start`、还没起」⇒ 同一用户回合里到的 `end` 就是它的收尾。撤暂存不造空轮、不造一对没人看的边界帧，实现面只多一个分支。代价写清：那轮内容仍入 transcript，只是搭在用户回合的分组里、`lastTurnUnprompted` 保持 false。被否：先起后收（用户回合收尾时起一个随即收的 0 项轮）——桌面多一对幽灵边界，`interrupted` 还要按一个早已过去的 `ok` 补标，空回合的未读残影（§19.8-7）从稀有变常规；被否：帧里加回合 id（外仓协议面扩字段，批 8 契约已定形，收益只在这一条罕见错序） |
| D63 | 自动轮在飞时收到的 `end` **一律收轮**；`ok` 只认布尔 `false`（缺省 / 非布尔 / 其它值 ⇒ 按未中断收） | `end` 是唯一的收轮信号；把 `ok` 坏形当坏帧忽略 ⇒ 在飞轮永不收 = 永久「正在续写」+ 队列永不排水（本批要消灭的停住态）。误判方向取「未中断」：只丢一个中断标记，不丢回合边界。CLI 侧恒发布尔（§19.3-②），非布尔只可能来自别的写入者。被否：`ok` 坏形 ⇒ 忽略整帧（缺口原文，失败态不可恢复）；被否：`ok` 坏形 ⇒ 按中断收（把「不知道」标成「出错」） |

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
| （派生）旧 CLI 兼容（静默 = 今天） | §19.11 | 既有 `subagent-digest` 固件保持绿（不改）+ 走查 8 |

### 19.7 用例表（T68–T74 本仓；W1–W7 thincoder 仓）

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

**补项（T69② / T71② / T74① / T74②）**

| 子项 | 输入 | 期望 |
|---|---|---|
| T69② | 用户回合在飞时 `send('two')`（进队列）+ push `start`，然后 `release` | 暂存自动轮先起（`two` 不随用户回合发出，prompt 仍 1 条）；自动轮 `end` 后 `two` 才发出（prompt 第 2 条）——§19.2「插入点」 |
| T71② | `start` → `end{ok:false}`（非本端 `cancel()` 来源） | 零 `session/cancel`；`TurnEnded(interrupted: true)`、`activeTurn == null`、`transcript.lastTurnInterrupted == true` |
| T74① | 暂存 + 同回合 `end`（D62） | `hold` 下 `send('one')`；用户回合在飞时 push `start{kind:digest}`，同一回合内再 push `end{ok:true}`；`release` | 桌面只见用户回合一对边界（`TurnStarted` 1 / `TurnEnded` 1）；无 `auto:` 轮、无第二个 `TurnEnded`；`release` 后 `activeTurn == null`、`lastTurnUnprompted == false`；该 `end` 留痕一条；随后 `send('two')` 直接写出 `session/prompt`（无在飞轮挡路） |
| T74② | `ok` 非布尔（D63） | 两条独立会话：① `start` → `end{ok:"false"}`；② `start` → `end`（键缺席） | 两次都**收轮**：`TurnEnded(interrupted: false)`、`activeTurn == null`、`lastTurnInterrupted == false`；① 另留痕一条 |

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

W 侧判据不变：CLI 的 `end` 恒发布尔 `ok`（成功 = true；抛错 = false，`try … finally`）——D63 的宽容是客户端防御，不进 W 的判据。

**固件**：新增 `test/fixtures/thincoder/digest-turn.ndjson`（新线形：`start` → 文本 → `end`；`expect` 含 `unprompted: true`）；既有 `subagent-digest.ndjson` **不改**——它就是「旧 CLI 无信号」的兼容哨兵（§19.11）。

### 19.8 边界（批 8 不做）与登记（判定条件）

1. **timer 唤醒轮不接**：无 `timerFace`（§19.3-①）。判定条件：桌面需要 timer 唤醒（终端 `pendingTimerDeadline` / `deliverExpiredTimers` 对位）⇒ 接 `timerFace`（`suspension.mjs:173-205` 第四态）并给 `kind:"timer"`。
2. **自动轮不请求审批**（D58）。判定条件：产品要「自动轮也能请求审批」⇒ 去掉剥离 + 明确无人应答的兜底（反向请求 5 分钟超时按拒绝）。
3. **自动轮在重放（session/load）里没有回合边界**：重放只还原消息（`bridge.mjs:402-461`），不合成回合——与今天一致。判定条件：需要在重放里也分组 ⇒ 扩展重放面（另立）。
4. **取消自动轮 = 停整个后台会话**（D59）：窗 abort 后核清场，存活子代理中止。不做「只停这一轮、后台继续」——核驱动只有会话级 abort；判定条件：核提供回合级 abort 缝。
5. **自动轮不生成会话标题**：ACP 本就不生成（`ensureSessionTitle` 只在 TUI 面）。
6. **自动轮的问答面**：`question` 工具装配期已剔除、secret 拒件——自动轮没有问答面（与 2 同源）。
7. **空自动轮**：起止帧照发（D61），无项可显示；罕见的零输出失败会在侧栏留一个未读徽标而无新内容。判定条件：走查反复观察到「徽标在、没内容」⇒ 宿主侧对空回合抑制未读（宿主改动，另立）。
8. **旧桌面 + 新 CLI**：两帧进旧翻译层 ⇒ E4 日志（`thincoder_events.dart:429-431` 形），显示零变化——登记；不做版本门（E3）。
9. **进程强杀**：挂起随进程消失；后台 bash 树可能残留（与终端硬退同形）——沿用 §14-12 口径，不新增机制。

### 19.9 UI / 交互决定（全部落地，无 open）

- 自动轮 = 宿主既有「无提示回合」：侧栏运行中（`workspace.dart:158-177`）、**不**自动滚到底（`chat_history_view.dart:1162-1194` 的 `sent` 判定）、完成不响铃（`attention_service.dart:137-146`）、不计入 tips（`star_prompt.dart:111-117`）。
- 「正在续写」指示 = 既有流式指示（`isStreaming` = `activeTurn != null`，`chat_session.dart:538`）；无新组件、无新文案、无新 l10n 键。
- 自动轮可停止：composer 停止键 → `cancel()`（`thincoder_kernel.dart:567-583`）⇒ `session/cancel`（§19.3-①）。
- 自动轮期间可排队发消息：§18 既有面（排水在 `_endTurn`，`:540-565`）。
- 无 open 项。

### 19.10 真机走查步骤（A 段交付时执行）

1. 装含本批的 CLI + 桌面；新建 thincoder 会话，选一个工程目录。
2. 发一条会让主代理**异步派子代理 / 评审**的指令 ⇒ 用户回合先结束、子代理卡片仍 running。
3. 验「自起一轮」：子代理结算 ⇒ 无需用户操作，主代理自动开始说话（新文本出现在用户回合之后，`user:` 项不增加）。
4. 验「回来要下一步」：切到别的会话再切回 ⇒ 该会话显示未读（无铃声）；结束态可输入。
5. 验「正在续写」：自动轮进行中侧栏该会话 = 运行中；输入框可写，发送进队列面板（§18）。
6. 验「可停止」：自动轮进行中点停止 ⇒ 文本停、轮标中断；后台子代理卡片定格（`stopped`）。
7. 验收束：自动轮进行中关掉该会话视图 ⇒ 自动轮结束后进程按既有 release 语义释放；重新打开无「永远在跑」的卡片。
8. 兼容：把 `thincoder.path` 指到旧版（无本批信号）⇒ 与今天一致：结算后文本照常到达、无自动轮、无新提示。
9. 同场景对照终端：终端里子代理结算后同样自起一轮——两侧消息内容与顺序同形（不要求逐字相同）。

### 19.11 兼容（三种组合）

| 组合 | 表现 |
|---|---|
| 新 CLI + 新桌面 | 自动轮可见（unprompted）、可停止、结束即「该你了」 |
| 新 CLI + 旧桌面（批 7） | 两帧被 E4 忽略并记日志；文本照常入 transcript——显示 = 今天（§19.8-8） |
| 旧 CLI + 新桌面 | 无边界帧 ⇒ 无自动轮；文本照常到达 = 今天（既有 `subagent-digest` 固件即此形的哨兵） |

不加版本门（E3）：能力按帧在场判定；`thincoder_locator.dart` 的 `verifiedVersion` 不上调。

---

## 变更记录

- 2026-10-16 · 首版（批 1 设计：F1–F7、F10 + E1–E5 落地；批 2/3 只留接口面）。
- 2026-10-16 · 修正轮 1（评审发现 #1–#9）：§2.2 先例文档坐标 · §3.4 两层超时关系 · §3.5/§14-9 fork 后 id 处置 · §5.2 体量立场与净增上界 · §7/§8 走查前提与用例 T26/T27 · §12 反向同步行 · §14-10 能力位固定面登记。
- 2026-10-16 · 修正轮 2（实现期缺口：load 跳过判据跨内核合并 ⇒ 与 claude 同项目的 thincoder 会话漏列）：§5.2-⑤ 改按内核判定（`_listKept` 收内核子集、守卫按内核修正、代价说明）+ 净增上界与体量立场随涉 · §7 A3 补列出行 · §5.1 补 `preferred_kernel_test.dart` 登记 · §14-11「未列目录时清理推迟」。
- 2026-10-16 · 修正轮 3（A 段实现期表外披露登记归位）：§5.1 补 `thincoder_events.dart` 行（拆自 kernel）· `thincoder_kernel.dart` / `thincoder_locator.dart` 行与实况对齐 · 体量立场 kernel bullet（拆分已执行 + 不续拆 + 下一缝 = 选择面段）。
- 2026-10-16 · 修正轮 4（失效措辞与体量立场口径对齐）：§2.2 偏离 ③ 与 D2 改按已执行拆分口径（翻译档 = `thincoder_events.dart`；续拆裁定 = 不续拆） · §12-4 翻译指针随拆分校正（`thincoder_events.dart`）。
- 2026-10-16 · 修正轮 4 · 追加（A 段交付披露裁定落地）：§3.5 补 `session/close` best-effort 与「会话已不在」兜底两条口径（登记 §14-12 / §14-13） · §12-7 补固件基准口径（真机重录执行点 = T15 走查）。
- 2026-10-16 · 修正轮 5（C 段代码评审三项裁定落地：跨重连口径 / A1 断言 / 上界快照）：§3.5 与 §14-13 补「跨重连口径」（兜底后记「记录槽已忘」，走保留槽路线；实现随后续单）· §7 A1 断言改描述符身份 + 代码核口径 · §5.2 净增上界 ① ≤11（含 2 条 import）/ ⑦ ≤81 · §14-14 登记 ⑦ 设置组文案英文占位。
- 2026-10-16 · 修正轮 6（走查现场缺陷：`session/prompt` 未设超时 ⇒ 走连接缺省 60s，长回合误报「got no answer」+ 误标 interrupted）：§3.4 补我方请求超时口径——`session/prompt` 显式不设超时（回合时长无上界；兜底 = 取消 + 进程健康），其余请求照旧；实现修随后续单。
- 2026-10-16 · 批 4 设计（F11 子代理活动可见）：新增 §15（翻译表 / 挂起态与 digest / 受影响文件 / 关键决策 D21–D30 / 走查 7 步 / 用例 T28–T37 / 边界 / UI）；随改 §3.4 通知表（子代理信号指针）· §3.6 翻译表（新增行）· §5.2 尾（批 4 指针）· §7（F11 行）· §9（子代理测试面）· §10（原「仅忽略」句随批 4 撤）· §11（批 4 已落地行）· §12-A-4（核对形状补子代理 meta）· §14-4（判定条件闭合改写）· §14-15（文案英文占位登记）。
- 2026-10-16 · 批 4 修正轮 1（设计评审 #1–#8 落地）：§5.2 体量立场（`chat_screen.dart` 入 >800 名单 · 快照刷新为当前值 · kernel 触发句补「触碰按结构级改动计」）· §15.4（kernel +4 口径 · kernel_test 体量裁定 · ⑰ ≤ +115）· §15.2（`cancelled` 已建处置 + 契约坐标 · `{position}` 不展示）· §15.6（步 3 / 7 观察点）· §15.7（T38–T40）· §14-15（补 `thincoder stopped`）· §15 引言块去沿革指注。
- 2026-10-16 · 批 4 交付随修（实交读数落档 + 终态后契约外报告裁定）：§15.4 文件表与体量条按交付读数刷新（⑪ 608 · ⑫ +5 · ⑬ 1 行改动 / 净增 0 · ⑭ +3 · ⑯ 191 · ⑰ 1442 · 补录 ⑱ 固件 README）· §15.2（`queued` / `async` 行 + 终态后忽略口径）· §15.5 D31 · §15.7 T41 · §15.8-7 · §5.2 体量条读数（+3 / 888 · ⑬ 净增 0）。
- 2026-10-16 · 批 4 点修（守卫口径扩展 + 实交读数刷新）：§15.8-7 / §15.5 D31 口径扩展——卡片已移除（`cancelled` 墓碑）后同键任何迟到报告（含 `settled` / `stopped` / `done` / 未知态）⇒ 忽略（与四态口径并列一条统一规则）；§15.2 规则行与状态表 `queued` / `async` 行、§15.7 T41 随同步；§15.4 ⑪ / ⑰ 实交读数与缝坐标随守卫修正轮刷新（637 · 1524 · `:1358` 起）；零代码改动。
- 2026-10-16 · 批 5 设计（F12 子代理内容归属）：新增 §16（thincoder 侧 diff 钉死 / 本仓路由 / UI / 受影响文件 / D32–D38 / 用例 T42–T50 / 边界 / 走查）；随改 §3.6（内容帧归属标指针）· §7（F12 行）· §9（批 5 测试面）· §10（边界指针）· §11（卡片可点）· §12-A-4（核对形状）· §14-4（内容归属闭合）· §14-16/-17（登记）· §15.1 / §15.2 / §15.5（D21 拆条、卡片字段、偏离 1·3 按批 5 现状改写）
  · §15.8-2 / §15.9（批 4 边界与 UI 按现状改写）· §5.2（§16.4 指针）。
- 2026-10-16 · 批 5 审前修订（父侧内容核验 2 项）：§16.1 归属标扩到工具帧（`bridge.mjs:275-282` / `:287-291`，辅助 `contentMeta` → `frameMeta`，净增 11 行 + 2 行改写）· §16.2 工具帧路由与结果不回传判据 · §16.7 +T50
  · §16.8-1 / §14-16 改登记口径（归属已接 / 结果面缺）· §16.6 ①② 补工具卡、边界行 diff 处数 · D36 转已确认 · 随改 §3.6 工具两行 / §7 F12 行 / §9 用例号 / §11 / §15.8-2 / §12-A-4 / §16.9 走查①② / §16.4 ⑲⑳㉑㉒。
- 2026-10-16 · 批 5 设计评审修正轮 1（#1–#9 落地、#10 注记；零代码）：§15.1 偏离 1·3 · §15.2 卡片字段 · §15.5 D21（id / children 有来源；五类无来源）· §16 最近先例行（批 4 §15.2 / §15.9 ∥ `claude_code_translator.dart:419-423`）· §16.1 重放面重写 + `SUBAGENT_META_KEY` 既有定义 · §16.2 键命名空间 + 重放降级行
  · §16.4 本批不拆裁定 + `bridge.mjs` 行数 / 档位 · §16.7 T43 / T50 · §16.8-2 措辞 · §16.8-7 重放边界 · §3.6 重放帧口径 · §5.2 §16.4 指针。
- 2026-10-16 · 批 5 修正轮补笔（表外发现 1：B1 改写后的口径回灌；零代码）：§7 需求覆盖行补 F11 / F12，并把「无越界改动」改为「默认不改仓 + F12 最小接口例外（§16.1）」· §10 边界行同口径对齐。
- 2026-10-16 · 批 5 交付订正（按实现实况回读；零代码）：§16.4 ⑳ 记「预估 ≤ +200（⇒ ≤1737）→ 实交 +308（⇒ 1845）」（仍处 >800 名单，缝候选 = 按 group 拆（§15.4），本批不动结构）· ⑲ 措辞对齐实交（`_putSubagent` 签名不变；`id` 由 `_openCard` `:665` 承载、`children` 由 `_card` `:550` 承载）
  · D34 补 `closePiece()` 顺带冲刷（`:198`）· §16.8-7 补「带标重放帧按正文渲染」（今日不可达，判定条件同 §16.8-7）。
- 2026-10-16 · 批 6 设计（F13 审批自动档 + F14 模型清单与思考档位）：新增 §17（服务端位暴露的逐行 diff / 桌面审批面与档位面的最小接线 / 兼容矩阵 / D39–D47 / T51–T58 / 边界 / 走查）；
  随改 §4 F5（模型候选与档位面现状）· §5.2（§17.4 指针）· §7（F13/F14 行 + B1 例外口径）· §9（T51–T58 + 不加固件的理由）· §10（例外口径；`effort 多档` 随批 6 落地）· §11（审批 pill / 档位面）· §12-A-4（新 id 与多项清单）· §14-1（模型候选改现状）· §14-18/-19（登记）
- 2026-10-16 · 批 6 设计评审修正轮 1（#1–#12 落地；零代码）：§10 边界行改 `context` / `fast` 选择器口径并落 `effort` 多档例外 · §17.4 补测试档体量行 + 行数统一（`wc -l` 实测）
  行数：kernel 899 · mock 567 · test 1845 · `acp.mjs` 157（快照日 = 2026-10-16）；§17.3-③ `effortLabel` 词表外档名规则 + T56 补 `low` · §17.7 +T59 / T60（两条写路径的错误面）与 T57② 改 mock 参数面
  · §17.3-① 三路装配口径 + 落地存活判据（§14-20）· §17.1-① 去流程性批注 · 探针注 `providerSpec` 取值键 · §9 / §17.6 / §5.2 / §2 随同步
- 2026-10-16 · 批 6 形态修正轮 2（用户 21:25 定形：审批自动档 = composer 右下角的小开关）：§17.1-③ 改成右下角紧凑开关（两档 ⇒ 开关；≥3 档 ⇒ 左簇菜单，Claude 不动）· 审批两项 label 收短为 `Ask` / `Auto` · tooltip = 既有标题 + 另一项 description；
  §17.4 加 ㉗ `composer.dart`（≤ +50）/ ㉘ `composer_test.dart`（≤ +70）并落宿主一档口径 · §17.5 D41/D42 · §17.6（+形态派生行）· §17.7（+T61，T51/T54 随形）· §17.9 走查②③⑦ · §7 · §9 · §11 · §14-19 随同步；零代码
- 2026-10-16 · 批 6 形态修正轮 3（用户 21:39 改形：不用警示色，开关照参照图）：§17.1-③ 颜色条改「开 = 填充 pill（底色 `button.secondaryHoverBackground`，图标 / 文字 `AppColors.text`）/ 关 = 无底色（textMuted）」，`selected.caution` 不再参与取色；
  §17.1-③ 选项表备注与「可见性」句、hover 句随填充态同步 · T61 断言改「开 = 有填充、关 = 无填充」· §17.6「一眼可见」行判据改 T61 · §11 一句改「开态填充 pill、关态纯文字」；零代码
- 2026-10-16 · 批 6 形态修正轮 3 扫尾（零代码）：§17 残留的「警示色 / caution 取色」表述扫成新形态（开 = 填充 pill 有底色 / 关 = 纯文字无底色）——§17.4 ㉗ · §17.5 D41 / D42 · §17.9 走查②③；数据面 `caution: true`（T51）不动。
- 2026-10-16 · 批 6 语义修正轮（用户 21:47 裁定：面板「Approve for this session」真的开会话级 auto）：§17.1-④ 从「本批不改」改为本批做（桌面侧）——先答本次 approve，同一回合写 `set_config_option('autoApprove', true)`（与右下角开关同一写路径）；写失败不影响本次批准、开关不变；once / reject 零写
  · §17.5 D46 · §17.6（+派生行；错误面 +T62④）· §17.7（+T62，紧接 T51）· §17.9（+走查 9）· §17.8-3 · §10 · §9 · §14-18 改「已闭合（桌面侧）」 · §17.4 ㉔（≤+66）/ ㉕（T62 零增）/ ㉖（≤+290）；零代码
- 2026-10-16 · 批 6 语义修正轮 · 追加（父侧裁定，并进本轮；零代码）：§17.4 ㉗ `composer.dart` 增量 ≤+50（⇒ ≤2119）→ **≤+70（⇒ ≤2139；实交 2139 = +70）**——按 §17.1-③ 形态（公开类 + IdeHover/HoverBuilder + 放置分支 + 两档判定 + localized）下限约 2123，原 +50 低估 10–16 行；§17.4 体量行补「>800 名单 / 缝 = 右下角固定组整段出档 / 触发 = 下一次结构级触碰或独立拆分批」
- 2026-10-16 · 批 6 形态修正轮 4（用户 22:12 第 4 次定形：审批开关改**拨动开关**）：§17.1-③「形态与放置」整节重写——track 35 × 20 / 圆角 10 + knob 直径 16 / 内缩 2、左右换位（几何与 140ms · easeOut 动画逐项照 `lib/ide/ide_switch.dart:44-84`）；
  开 = track 橙 `AppColors.claude` `0xFFD97857`（`app_theme.dart:157`）+ knob `button.foreground`，关 = track 无填充（`Colors.transparent` + 1px `AppColors.textFaint` 描边）+ knob `AppColors.textMuted`；无文字 label / 无图标（tooltip 承载语义，`Semantics(toggled:)` 承载读屏）、热区 35 × 22
  · §17.1-③ 选项表引句与「可见性」句随形 · §17.6「一眼可见」判据改「位置 + 颜色即状态」· T61 断言改「knob 位置 + track 颜色」；零代码，实现待随后续实施轮改形
- 2026-10-16 · 批 6 颜色点改（用户 23:37 裁定：开态橙 = 参照图 "Fast Ide" 胶囊底色）：§17.1-③ 颜色条改 `AppColors.autoTrack`（`0xFFE2B373`，`app_theme.dart` 新增；截图逐像素取色）——取代上一条的 `AppColors.claude` 借色方案；§17.4 ㉗ 与 §17.7 T61 随同步；另修 §17.4 体量行的 2135/2139 读数打架（统一 2139）。零语义改动。
- 2026-10-16 · 批 7 设计（F15 工作中发送的消息）：新增 §18（内核本地队列 / 排水挂在 `_endTurn` / 四个入口 / 失败面与 `duringTurn` 判据 / 兼容矩阵 / D48–D54 / T63–T67 / 边界 / 走查）；
  随改 §4 F3（流式中可继续发、指 §18）· §7（F15 行 + 一致链补 F15）· §9（队列测试面与不加固件的判据）· §10（边界撤「队列控制」、加「队列面 = 批 7 设计已定」）· §11（批 7 设计已定）；零代码
- 2026-10-16 · 批 7 设计评审修正轮 1（评审 #1–#12 全落地；零代码）：§18.7 用例符号改 `agent.release()` + 符号注（#1）· §18.1 插入点前置不变量 + 约束 1 收紧（#2）· §18.5 编辑列标「宿主既有、本批不机检」（#3）· T65④ / T66⑥ 补 `_next` 两条边（#4）
  · §10 / §11 改状态中性措辞（#5）· 抬头分批补批 6 / 批 7（#6）· §18.1 状态表补 `_sent`（#7）· §18.2② 钉住图片落盘与阈值在转正（#8）· §18.2⑤ 挂起态回指 §15.3（#9）· §18 先例行回指 §2.2（#10）· §18.4 生成档归类（#11）· §18.4 会话面缝候选（#12）
- 2026-10-17 · 批 7 实现期登记（零代码）：§18.9-8 `KernelTurn.now` 不兑现 + 判定条件 · §18.2-② 补「预览 ≠ 实发正文」的另一源（`notes` / 图片路径行）。
- 2026-10-17 · 批 8 设计（F16 回合结束后继续关注后台子代理）：新增 §19（挂起窗装配 / 回合边界帧与桌面翻译 / 收束 / D55–D61 / T68–T74 + W1–W5 / 边界 / 走查 / 兼容）；
  随改 §3.4 通知表（turn meta）· §3.6 翻译表（新增行 + 自动轮边界一句）· §5.2 尾（§19.4 指针）· §7（F16 行 + 一致链）· §9（挂起测试面）· §10（B1 例外 + 边界指针）· §11（批 8 已落地行）· §12-A-4（核对形状补 turn meta）
  · §14-4（剩余边界改写）· §14-21（timer 登记）· §15.3（digest 到达形改写）· §15.5 D26（随改写）· §15.6 走查 6 · §15.7 T34（旧 CLI 形）· §15.8-1（闭合）；零代码；thincoder 侧 = out-of-repo 轮
- 2026-10-17 · 批 8 设计评审修正轮 1（#1–#5、#8、#9 落地；零代码）：§19.2 插入点钉死（`emit(TurnEnded)` 之后、`_drain()` 之前；暂存自动轮先起，队列 / 释放等自动轮收尾）+ `_turnKey` / `_turnUnprompted` / `lastTurnUnprompted` 的命名与取值层（#1 / #9）· §18.1 插入点一句随同步（#1）
  · §19.1 / §19.3-② 自动轮 `try … finally` 必发 `end{ok:false}` + W6 / T71②（#2）· D58 / §19.3-② / W5 回调缺席判决 = 拒绝（桥侧 `unverified`）（#3）· §19.3-② upstream 返回路 + W7（#4）· §15.3 挂起期发消息加「无在飞回合时」、§19.2 末条改为实际改动（#5）· §5.2 尾改「本仓 1 档（kernel）+ 固件 / 测试面」（#8）
- 2026-10-17 · 批 8 实现期修正轮 2（两处实现期设计缺口；零代码）：§19.2 暂存位与自己的 `end` 配对（**撤暂存**，该轮在桌面不成轮；暂存位已占的第二个 `start` 不覆盖）+ `ok` 宽容（自动轮在飞时 `end` 一律收轮，只认布尔 `false` = 中断）+ 翻译表与字段域随改 · §19.5 +D62 / D63（含被否）
  · §19.7 T74 行限定「暂存位空」+ 补项 T74① / T74② + W 侧「恒发布尔 `ok`」一句 · §19.6 判据补 T74①② · §3.6 turn meta 行随同步 · §19.4 实交读数回灌（㉟ 1070 / ㊱ 2471 / ㊲ 9 行 / ㊳ +3 / ㊴ +3；体量行同刷）

