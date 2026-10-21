# thincoder 桌面适配 需求档

> 状态：已确认（用户 2026-10-16，会话裁定）
> 日期：2026-10-16
> 范围仓：baocode（本仓）。本适配不改 `thincoder/`（嵌套独立 git 仓）。
> 范围来源：用户 2026-10-16 会话逐条裁定（见 §10）。

## 1. 模块目标

在 baocode（现为「Claude Code 的桌面 UI」）中新增一个 **thincoder 内核**：

- 桌面端经 ACP 通道驱动用户终端里那套 thincoder（同一份配置、同一套会话）；
- 新会话默认用 thincoder，Claude Code 保留为可选内核；
- baocode 与 thincoder 各自演进时，把适配成本压在可维护的边界内（§4）。

一句话验收：**装好 thincoder 的机器上，打开 baocode 新会话，用的就是 thincoder；终端开的会话桌面能接着聊，反过来也一样。**

## 2. 事实基线（已核实；设计与验收的前提）

### 2.1 baocode 侧（宿主）

- 内核抽象 `lib/kernel/agent_kernel.dart`：`AgentKernel` 接口 + 22 个能力接口（模型/模式/审批/计划/用量/回退/fork/图片/MCP……）。
  语义：**内核实现什么能力，UI 就显示什么**；`KernelContext` 带 cwd / resume / settings。
- 注册表 `lib/kernel/kernel_registry.dart:29`：目前只有 `claudeCode` 一个内核；注释「Another kernel is an adapter and a line here」。
- 默认内核 = 注册表首位：`lib/workspace/workspace.dart:239-240`（`_preferredKernel = kernels.first`）。
- 内核选择器 UI 已存在：`lib/chat/chat_session.dart:303-316`，内核 ≥2 个且新会话时可换；
  对话开始后内核锁定（`:300`）——内核之间读不了对方的会话，故 thincoder 会话必须由 thincoder 自己的目录读。
- claude 通道先例：`lib/kernel/claude_code/claude_code_transport.dart`（起 `claude -p --input-format stream-json --output-format stream-json`）；
  远程按 cwd 路由（`lib/remote/remote_claude.dart`）。
- Customize 面板七类：plugins / mcps / skills / subagents / rules / commands / hooks（`lib/customize/customizations.dart`）。
- 现有文档面：`docs/*.md` 扁平功能档（中文）。

### 2.2 thincoder 侧（适配对象）

- 形态：npm 包 `thincoder`（Node ≥24），用户终端自装自配。
- 机读通道：`thincoder acp` —— ACP v1 服务端，stdio 上 NDJSON JSON-RPC 2.0（Zed / JetBrains 同款接入面）。
- 握手（`thincoder/thincoder-cli/src/acp/client-caps.mjs:52-64`）：`initialize` 返回
  `protocolVersion`（协商：同版本优先，否则取它支持的最新，`:18-21`）、
  `agentCapabilities`（`loadSession: true`；`promptCapabilities` 图片 **true（批 11 起；B1 例外）**、音频/内嵌上下文 false；
  `sessionCapabilities` = list/resume/delete/close）、
  `authMethods`（客户端宣告 `auth.terminal` 才有 terminal 登录项，实际执行 `thincoder acp --login`，`:28-37`）、
  `agentInfo {name, version}`。
- 方法面：`session/{new,load,resume,list,prompt,cancel,close,set_mode,set_config_option}`；
  通知 `session/update`（文本/思考/工具卡/用量/配置项/模式）；
  反向请求 `session/request_permission`、`fs/read_text_file`、`fs/write_text_file`；
  扩展族 `checkpoint/*`、`memory/*`、`ledger/*`、`batch/*`。
- 宿主工具通道（`host-tool-channel` 批）：客户端可在 `session/new|load|resume` 的 `mcpServers` 里带本机环回 MCP server（以 agent 宣告 `mcpCapabilities.http` 为门）；ACP 无通用客户端工具声明面，见 `docs/requirements/host-tool-channel.md`。
- 会话：id = 持久槽位号字符串；`session/list` 列的是**当前 cwd** 的槽（`acp/handlers-slots.mjs:42-62`）——
  终端写的会话同样在内，「与终端相通」原生成立；单 cwd 模型（`session/new` 的 cwd 必须等于进程 cwd，故一个项目一个 ACP 进程）。
- 审批：逐次 `session/request_permission`，选项 approve_once / approve_always / reject；无应答/取消 → 拒。
  反向 RPC 超时：传输层默认 60s（`acp/transport.mjs:42`），按方法覆写——审批 5 分钟（`bridge.mjs:319`）、`fs/*` 30 秒（`bridge.mjs:143`/`:152`）；不卡 agent 循环。
- 错误面：JSON-RPC 标准码齐全（`acp/transport.mjs:14-20`，含 `-32000 authRequired`）；未知方法得 `-32601`，不炸连接。
- 配置：`~/.thincoder/config.json`（多端共享单文件，终端与桌面同源）；会话槽库与日志同在 `~/.thincoder/`。
- 定制面（源码核实）：项目级 `<项目>/.thincoder/{skills,rules,tmp}`；用户级 `~/.thincoder/{skills,AGENTS.md,config.json,sessions,…}`；
  核内存在 MCP / hooks 模块（配置文件位置留设计核实）。
- 图片：ACP 明确不收（`client-caps.mjs:55-59`）；核内自己的做法 = 粘贴图落 `<cwd>/.thincoder/tmp/` 并在消息里引用路径。

## 3. 功能点

**F1 内核接入与默认**：新增 `thincoder` 内核进注册表并位列首位 ⇒ 新会话默认 thincoder；Claude 保留（新会话可切换）。

**F2 会话与终端相通**：内核会话目录走 `session/list`——当前项目列出全部持久槽（含终端创建的）；载入/恢复/删除可用；标题与更新时间展示。

**F3 对话全链路**：发消息 → 文本流 / 思考流 / 工具卡（含更新）→ 回合结束；运行中可取消；plan 模式可切、计划可见。

**F4 审批弹窗**：`session/request_permission` → 弹窗显示工具与参数；三选项（一次 / 总是 / 拒绝）映射到内核答复；无应答不卡 UI。

**F5 模式与模型**：`set_mode`（plan/normal）与 `set_config_option`（model / thinking）接入现有选项 UI；显示以 thincoder 回报为准（不乐观假报）。

**F6 图片替代**：粘贴图片落 `<cwd>/.thincoder/tmp/`（命名规则与终端一致），消息文本附文件路径；内核不声明 `AcceptsImages`；新增文件面接口 `AcceptsImageFiles` 承接（见 §5）。

**F7 检测与引导**：定位 `thincoder` 命令（PATH 探测，另设可指路径的设置项）；
未找到 → 引导（npm 安装 + Node ≥24）；`-32000 authRequired` → 引导 `thincoder acp --login`；
握手 `agentInfo.version` 低于验证下限 → 明确提示（不静默降级）。

**F8 远程 SSH 项目**：SSH 项目里 ACP 进程起在远端主机，会话与配置也在远端用户目录；与 Claude 远程路线同构（复用 `lib/remote/` 面）。

**F9 Customize 对接**：按 thincoder 实际定制面（skills / rules / AGENTS.md / MCP / hooks——逐类以源码核实为准）在 Customize 面板对位；无对应面的类别不显示。

**F10 用量展示**：上下文用量（usage_update）接入现有展示；模型与供应商配置只读（不代管）。

**F11 子代理活动可见**（批 4；用户 2026-10-16 拍板开批）：thincoder 主代理异步调子代理时，桌面可见其活动——
子代理卡片（出现 / 进度 / 完成）· 活动条运行代号与计时 · 会话状态行「后台 N 个子代理运行中」· 长回合静默期的活动指示。
载体 = thincoder 0.12.74 已在推的 `session_info_update` 子代理信号（`_meta["thincoder.dev/subagent"]`）。
范围 = 本仓适配层翻译 + 既有子代理 UI 面（不动 thincoder，B1 不变）。
验收 = 真机走查：长回合调子代理时，卡片 / 活动条 / 状态行随状态推进可见；静默期有活动指示。

**F12 子代理内容归属**（批 5；用户 2026-10-16 裁定：允许动 thincoder 仓 · 走完整归属 · 保留拉代码能力）：

- **接口（thincoder 侧，最小改动）**：子代理的**内容帧与工具帧**（`agent_message_chunk` / `agent_thought_chunk` / 工具调用与更新，relay 前缀在场）带
  `_meta["thincoder.dev/subagent"]`（至少 role / id；无 state）——与状态信号同键同源，改动最小、可上游合并。
- **本仓**：带该标记的内容与工具卡归入**对应子代理的只读会话**（照既有「子代理只读会话」先例，卡片可点开）；
  主对话只保留主代理的流，不再混入子代理的思考 / 正文切片。
- **验收**：多子代理并发走查——① 主对话无子代理内容与工具卡；② 点开卡片可见该子代理自己的思考 / 正文 / 工具卡；
  ③ 状态面（卡片 / 活动条 / 状态行）不变；④ 无标记内容照旧进主对话。
- **边界**：不动 thincoder 其它行为（保留上游 pull 能力：改动最小、无格式化噪声）；不做子代理控制面（沿用 D22）。

**F13 审批自动档**（批 6；用户 2026-10-16 裁定「开」）：终端 `/auto`（`agent.autoApprove`，免审批放行）对齐到桌面——
CLI 侧把 `autoApprove` 做成 config option（boolean，照 thinking 同款）+ ACP 权限路径尊重它（开着 ⇒ 自答放行、不问客户端）；
桌面在**适配层**实现既有审批面（显示 / 切换该位；开着时持续可见）；形态 = **composer 右下角的两档小开关**（宿主 1 档：`lib/chat/composer/composer.dart`；多档内核的菜单不动）。验收：桌面开 auto ⇒ 工具调用不再逐次弹审批；关 ⇒ 恢复逐次；面板选「Approve for this session」⇒ 会话级 auto 开（T62）。
边界：不做逐工具细粒度白名单（首版仅总开关）。

**F14 模型清单与思考档位**（批 6；设计 §14-1 判定条件转正；用户 2026-10-16 裁定「开」）：终端可选的完整模型列表进桌面选择器——
CLI 侧把运行期拉取的清单（`listModels`）投影进 `configOptions.model.options[]`（现只报当前一项，`handlers-session.mjs:46`）；
thinking 扩展为独立档位 id（`thinkingLevel`，布尔形状不动）；桌面：**模型面零改动**（E3），**档位面 = 适配层给 effort 面加一条上报分支**。
验收：桌面模型选择器与终端 `/model` 清单一致；切换生效；thinking 档位与终端一致。
边界：桌面不代管 provider / key（B3 不变）。

**F15 工作中发送的消息（队列）**（批 7；用户 2026-10-16 22:24 报告）：thincoder 会话在代理工作中**不能**先写消息、等它说完自动发——
宿主面齐备（`QueuesMessages` / 队列面板 / 设置项 `chat.queuedMessages` / `canQueue`），**Claude 内核已实现，thincoder 内核未声明** ⇒ 流式中输入框被禁用（`chat_session.dart:511` / `:544`；`composer.dart:1321`）。
验收：thincoder 会话流式中可发消息 ⇒ 进队列（队列面板可见、可撤回/编辑）；当前回合正常结束后**自动依次发送**；「插入当前任务」在 ACP 面不可达（无回合内注入通道）⇒ 按「等回合结束」处理并登记。

**F16 回合结束后继续关注后台子代理（挂起驱动）**（批 8；用户 2026-10-17 01:31 报告）：主 agent 必须"时刻看着"子 agent——评审 / 设计子代理真结束后，主 agent 要立刻醒来把结果告诉用户（该轮到用户发批准了），不能停在「等评审回来」那句话上等用户催。
事实（2026-10-17 实读）：终端面有这套——`thincoder-cli/src/tui/suspension-drive.mjs`（核 `@thincoder/core/agent/suspension.mjs` 的状态机；回合尾进挂起，池空退出，子代理结算 ⇒ `digestTurn` 自起回合）；**ACP 面零挂起机制**（`src/acp/session.mjs` 无 `suspension` / `digest` 引用）⇒ 桌面会话回合结束即静默，后台完成不会产生任何续话。
验收：桌面里开一个后台子代理 / 异步评审 ⇒ 主 agent 在它结束后**自起一轮**（看见其报告、回到用户要下一步）；终端与桌面同形；不刷新、不靠用户发话。
派生验收（2026-10-17 07:03 走查）：**切走对话不丢后台子代理**——视图归零触发的释放要等后台池空（设计 §19.2 D64）。
边界：timer 唤醒轮不接（判定条件见设计 §19.8-1）；自动轮不请求审批（D58）；重放（session/load）里不合成回合；自动轮空转不生成未读的抑制属宿主侧另立。
B1 例外状态：本批要动 `thincoder/`（ACP 挂起窗新档 + `session.mjs` 接线 + 四处 `cancel()`→`close()` + 契约档；约 +215 行，设计 §19.4）——**用户 2026-10-17 01:56 明示允许**（逐字：「可以动thincoder仓库」）；保持上游可合并，外仓轮写它自己的批次档与测试。



**F17 编辑器上下文随消息注入**（批 10；用户 2026-10-17 21:16 裁定「先把 IDE 完善」）：发消息时把**当前编辑器上下文**随消息带上——打开文件路径 + 光标行 + 选区（若有）；用户不必手动 `@`。
事实（2026-10-17 实读）：桌面 `initialize` 宣告 `clientCapabilities: {}`（`thincoder_kernel.dart:188` · `thincoder_catalog.dart:80`），无选区/文档面实现；CLI 侧 `session/prompt` 已收 `resource_link` 内容块（需求 F8 · R-A5.10）⇒ **纯客户端**可做，不动 CLI。
验收（可机检）：打开 `a.dart` 第 10 行、选中 3–5 行 ⇒ 发消息 ⇒ 到达内核的 prompt 含该文件路径与行区间；关掉开关 ⇒ 不含；未打开文件 ⇒ 不含；同一文件同一回合只带一次。
形态要求：注入**可见可撤销**（消息里一个 chip / 摘要，不静默塞正文）；开关是**配置项就必须有设置 UI**（产品铁律）；默认值与终端习惯对齐（默认开）。
边界：不做全工作区索引注入；不做符号级引用解析；不改 `thincoder/`。

**F18 agent 编辑走 IDE 原生 diff（`fs` 反向 RPC）**（批 10；同上裁定）：桌面宣告 `fs.readTextFile` / `fs.writeTextFile` 能力并在内核请求时执行——agent 的读写**经桌面文件模型**，已打开的文件在编辑器里表现为**可见、可审阅的变更**（与既有变更审查面一致）。
事实（2026-10-17 实读）：桌面未宣告两能力 ⇒ 按 CLI 需求 R-A5.5「未宣告 ⇒ 回落本地」，agent 编辑直接落盘，桌面只能事后看；CLI 侧桥已有门控分支（设计 §11.4 G3）⇒ 补上宣告与两个 handler 即接通。
验收（可机检）：agent 编辑一个**已打开且有未保存缓冲**的文件 ⇒ 内核的写入请求落到桌面侧（不走本地落盘竞争），编辑器呈现可审阅变更且不覆盖用户未保存内容；未打开文件 ⇒ 写入后磁盘内容与 agent 所述一致；越界路径（项目外）⇒ 拒绝并有可见提示。
**F19 原生图片块（ACP image 内容块）**（批 11；用户 2026-10-19 01:21「原生图片块…提上日程」）：把会话里的图片以 ACP 原生 image 内容块随 `session/prompt` 发送，模型直接看图；不再只依赖落盘路径告知。
事实（2026-10-19 实读）：桌面 `KernelTurn.images` 走「图片替代」——`thincoder_kernel.dart` 落 `<cwd>/.thincoder/tmp/` 并在 text 里给路径（F6/A5）；ACP `session/prompt` 的 prompt 数组当前只发一个 text 块；CLI `buildPromptText` 只取首个 text 块（`resource-link.mjs:114-124`）。
ACP schema v1 的 image 块形 = `{type:"image", mimeType, data}`（已查实）；CLI 的 provider vision = `anthropic.mjs` 的 `image_url` 未转 image 块（批 12 的 #85 修）。
验收（可机检）：发送一张图片 ⇒ `session/prompt` 的 prompt 数组含原生 image 内容块（与 text 块并存）；模型回答能引用图片内容；CLI 不支持 image 时回退既有路径替代且行为同今天。
边界：不做图片编辑 / OCR；不改 Claude 内核的图片面；不做远程项目图片；图片大小 / 格式限制沿用既有（F6/A5）。
依赖：ACP schema v1 image 块；CLI `buildPromptText` / bridge；provider vision；**B1 例外 = 允许**（用户 2026-10-19 01:37「运行改thincoder仓库」；批 11 CLI 侧 5 档 ≈ +70 行 + 批 12 的 core/CLI 4 档 ≈ +64（同裁），out-of-repo 轮，保持上游可合并）。

**F20 用量**（批 11；同上）：在桌面展示 thincoder 会话的用量——按回合与会话的 token、上下文占用；与终端状态行 ↑+↓ 口径对齐（终端无 `/usage`）；成本本批不做。
事实（2026-10-19 实读 + 设计调查）：ACP `usage_update {used,size}` 已翻译（设计 §3.4）；turn footer 有 tokens / speed / cost（上游 1.3.0）；无会话级汇总、无用量页。终端**没有 `/usage` 命令**；终端用量面 = 状态栏累计 ↑+↓ + context%（context% 为 `estimateTokens` 估算，与 ACP `usage_update.used` 不同仪器）；成本无来源（bridge 只发 used/size，core 无价目表；ACP cost 为可选字段）。
验收（可机检）：一个会话跑多回合 ⇒ 会话级累计 = Σ `usage_update.used` = 终端状态行 ↑+↓ 合计（口径 = CLI 上报值，不重算）；上下文占用显示 used/size（不与终端 estimateTokens 的 context% 对照）；成本本批不做（登记条件 = 协议面出现 cost 再显示）。
边界：不做账号 / 账单用量（B3）；不改 CLI 的 usage 计算；不做跨会话历史统计。
依赖：`usage_update`；turn footer 数据；终端状态行 ↑+↓（只读对照）。

**F21 模型切换后置应用**（批 14；用户 2026-10-19 03:25「切模型是怎么啦？」+ 03:22「不行，非视觉模型还是做不了这个图片识别这个活，显示not support」）：回合在飞时切换模型不丢请求——切换记为目标，回合结束后自动应用，等待 / 生效 / 失败均可见。
事实（2026-10-19 实测）：CLI 的 ACP 入站 FIFO 只豁免 `session/cancel` / `session/close` / `session/list` 与 `autoApprove`（`transport.mjs:31-40`），`model` 写入排在回合后；桌面 60s 超时（`thincoder_protocol.dart:61`）后丢弃（`events.log` 03:09:38 `got no answer` + 03:09:39 迟到 `id c6`）⇒ 模型未切、界面误以为已切 ⇒ 发图落到非视觉模型。
验收（可机检）：回合在飞时选另一个模型 ⇒ 当回合仍用旧模型跑完，回合结束自动切换，UI 显示「已排队 → 已生效」；切换失败 ⇒ 保持旧模型 + 一条错误、不假装成功；会话切换 / 关窗打断 ⇒ 待应用目标清空。
边界：不做非视觉模型自动借视觉子代理（用户 2026-10-19 03:30「E等一下」）；不改 CLI 的 FIFO 语义；不做 provider 级切换后置（除非证据要求）。
依赖：ACP `set_config_option`；回合边界事件（`TurnEnded`）；模型选择器状态位。

**F22 交互响应（与 Claude 内核同档）**（批 16；用户 2026-10-21 00:45「我要机制的性能体验，响应做到和 claude code 内核一样强劲，反应灵敏！」）：
打开 thincoder 会话、发消息、切内核的手感必须与 claude-code 内核同档——**用户不等进程、不等装配**。
事实（2026-10-21 实机计时，直发 ACP 帧到 `thincoder acp`）：进程启动 + `initialize` **364 ms**；`session/new` **1545 ms**
（同进程第二次 **1507 ms** ⇒ 每会话都付，非一次性预热）；`session/prompt` → 首帧 **344 ms**；一句话回合总 3913 ms。
`session/new` 的构成已逐层实测：**属主探测 ≈1.29 s**（`tasklist` 658 ms + PowerShell `Get-CimInstance` 633 ms）+ **装配 138 ms** + 其余 ≈5 ms。
对照：claude-code 内核是同进程 isolate（`lib/kernel/claude_code/dart_core_transport_io.dart:14` `AgentIsolate.spawn`），无进程、无管道。
⇒ 差距在**建会话的 1.9 秒**（0.37 起进程 + 1.29 扫全机进程表 + 0.14 装配），不在流式。
验收（可机检，真机 `appEvent` 计时为证）：新建 thincoder 会话 **≤300 ms 可输入**（输入框已可用，首条消息排队）；**首帧 ≤600 ms**；**切内核 ≤200 ms**；同一项目连开第二个会话时**不再付全量装配**。
边界：不改 Claude 内核路径；不做内核间会话迁移（B4）；不为性能牺牲既有正确性（审批 / 取消 / 队列语义不变）。
依赖：宿主侧预热与乐观就绪（本仓）；CLI 侧装配瘦身（`thincoder/`，**B1 例外已获用户批准 2026-10-21 00:53**——判活改 `process.kill`、命令行探测移出热路径、`git config` 缓存），
独立成外仓批次，保持上游可合并。


## 4. 扩展性要求（「双端更新留空间」）

**E1 适配层单点**：thincoder 相关代码集中一个模块（建议 `lib/kernel/thincoder/`），其余部分只经 `AgentKernel` 接口交互。

**E2 对宿主以增量为限**：对 baocode 既有文件的改动只限接线点，逐点登记（设计档列清单）；改动可独立辨认，便于上游更新时合并。

**E3 能力协商驱动**：内核能力声明与 UI 显隐依据 `initialize` 回包，不硬编码版本判能力；
thincoder 将来补能力 → 改能力映射表（§5）+ 适配层小改即可点亮。

**E4 前向兼容**：未知通知与未知字段安全忽略；未知方法（-32601）得体降级；协议版本协商结果留痕（日志）。

**E5 维护面**：本档 §5 能力映射表为双端适配的单一维护点；设计档附「thincoder / baocode 升级后的核对与适配说明」；
用 mock ACP 对端 + 固件支撑离线回归（thincoder 更新后先跑固件）。

## 5. 能力映射表（baocode 能力 ↔ ACP 面；首版判定）

| baocode 能力（`agent_kernel.dart`） | ACP 对应面 | 首版 |
|---|---|---|
| 基础：发 / 收 / 取消 / 健康 | `session/prompt` · `session/update` · `session/cancel` · 进程健康 | ✅ |
| 会话目录（列 / 载 / 续 / 删） | `session/{list,load,resume,delete,close}` | ✅（限当前项目 cwd） |
| 模型选择 `SelectsModel` | `set_config_option(model)` + `config_option_update` | ✅ |
| 模式选择 `SelectsMode` | `set_mode`（plan / normal） | ✅（两档） |
| 计划 `StartsPlans` | plan 模式 + 计划呈现 | ⚠️ 呈现形态由设计定 |
| 审批面 | 无全局档位；逐次 `request_permission` | ⚠️ 弹窗接入 ✅；档位选择器不做 |
| 思考档 `SelectsEffort` | `set_config_option(thinking)` | ⚠️ 仅开关 |
| 上下文用量 `ReportsContext` | `usage_update` | ✅ |
| 历史载入 `LoadsHistory` | `loadSession` + `session/load` | ✅ |
| 图片 `AcceptsImages` | `promptCapabilities.image: true`（批 11 起；B1 例外） | ✅ 原生 image 块（§22）；旧 CLI / 缺位 ⇒ F6 替代 |
| 图片文件面（接口 `AcceptsImageFiles`） | 图片落盘 `<cwd>/.thincoder/tmp/` + 消息附路径行（F6） | ✅ |
| 会话改名 `RenamesSession` | `session/set_title` | ✅ |
| fork（对话分叉） | 无 | ❌ |
| 对话回退（rewind：编辑已发消息） | `session/rewind`（会话治理 A2） | ✅ |
| 文件 / 回合级回退（`PlansReverts`：先出计划再执行） | `session/revert`（dryRun = 计划） | ✅（会话治理 A1） |
| 排队消息控制 `QueuesMessages` | 无（内核本地队列，回合尾排水） | ✅ |
| 后台任务控制 `RunsBackgroundTasks` | 无 | ❌ |
| 账号用量与限额 `ReportsUsage` | 无 | ❌ |
| 文件建议 `SuggestsFiles` | 无（桌面本地列目录，不向 agent 请求） | ✅ |
| 命令列表 / 提示建议 | 无 | ❌ |
| MCP 连接管理 `ManagesMcpServers` | 无（面板面走 F9 文件管理） | ❌ |
| `context` / `fast` 档 | 无 | ❌ |

注：❌ = 内核不声明该能力，UI 按既有机制自动隐藏（不是缺陷）；⚠️ = 部分可用，按本档口径落地。

宿主工具通道（浏览器等）不以 `AgentKernel` 能力接口出现：由客户端经 `mcpServers` 提供 MCP server，见 `docs/requirements/host-tool-channel.md`。

## 6. 边界（明确不做）

**B1 默认不改 thincoder 仓**——本适配默认落本仓；ACP 给不了的能力默认不通过改 thincoder 补。**例外**：接口面必要且最小的改动，经用户裁定、保持上游可合并（F12 / 批 5 先例：用户 2026-10-16「允许动仓，保留拉代码的能力」）。
**B1 例外状态**：`host-tool-channel` 批（2026-10-18）要动 `thincoder/`（MCP forwarding + `permissionExempt` 信任位；外仓约 +170 行）——用户 2026-10-18 20:08「对，一定要实现宿主工具通道」+ 20:40 批准开工；保持上游可合并。
**B2** 上表 ❌ 各项首版不做：多文件夹工作区、对话 fork、后台任务控制、MCP 连接管理、账号用量、命令列表、提示建议、`context`/`fast` 档、effort 多档。
**B3** 不代管 provider / key：thincoder 配置由用户终端自理，桌面端只读取使用。
**B4** 不做会话在两内核间迁移（内核会话格式不通；既有「对话开始即锁定内核」语义不变）。

## 7. 验收

- **A1 默认内核**：新建会话未经选择即为 thincoder（测试断言默认内核 id；UI 走查一致）。
- **A2 可选并存**：新会话内核选择器列出 thincoder（默认选中）与 claude-code；切到 claude-code 对话可用，既有 claude 测试不破。
- **A3 终端互通**：终端 thincoder 在某项目建的会话，桌面打开同项目后可见、可继续；桌面建的会话在终端（同 cwd）可见、可继续。
- **A4 全链路走查**：发消息 → 流式文本/思考/工具卡 → 审批弹窗（三选项各验一次）→ 回合完成；plan 模式可切、计划可见。
- **A5 图片替代**：粘贴图片 → 落 `<cwd>/.thincoder/tmp/`（命名与终端规则一致）→ agent 能读到该文件。
- **A6 引导面**：PATH 无 thincoder → 引导含安装命令且应用不崩；未登录 → 引导 `thincoder acp --login`；版本过低 → 明确提示。
- **A7 远程（批 2）**：SSH 项目新会话远端跑通全链路；远端会话与远端终端互通。
- **A8 Customize（批 3）**：对位类别可列出/打开/编辑生效；无对应面类别不显示。
- **A9 测试**：mock ACP 对端覆盖 握手 / 会话 / 事件 / 审批 / 取消 路径；相关既有测试（含 claude 面）不回退。
- **A10 扩展性**：设计档含既有文件改动点清单与升级核对说明；实现与 §5 映射表一致（抽查）。
- **A11 交互响应**：thincoder 会话新建 ≤300 ms 可输入、首帧 ≤600 ms、切内核 ≤200 ms（真机 `appEvent` 计时）；同项目第二个会话不付全量装配。


## 8. 依赖

- **D1** thincoder CLI（npm 自装；Node ≥24；验证下限版本在设计档写定）。
- **D2** baocode 既有内核机制（`AgentKernel`）——不改其语义，只用。
- **D3** 批 2：远端主机需有 thincoder（同上，自装）。

## 9. 实施分批（建议；批界以设计为准）

- **批 1** 本地内核全链路：F1–F7、F10 + E1–E5 全部。
- **批 2** 远程 SSH：F8。
- **批 3** Customize 对接：F9 + 收尾。
- **批 4** 子代理活动可见：F11。
- **批 5** 子代理内容归属：F12（含 thincoder 接口面最小改动）。
- **批 6** 审批自动档 + 模型清单与档位：F13、F14（含 thincoder 侧 `configOptions` 投影）。
- **批 7** 工作中发送的消息：F15（本仓内核本地队列，thincoder 零改动）。
- **批 8** 回合结束后继续关注后台子代理：F16（含 thincoder 侧 ACP 挂起窗 + 回合边界帧；B1 例外待裁定——见 F16 条目）。
- **批 9** ACP 取消 / 后台工作帧（thincoder CLI 轨；需求见该仓 ACP-CLIENT R-A6 / R-A7）。
- **批 10** 编辑器上下文 + agent 编辑走 IDE 原生 diff：F17、F18。
- **排期（2026-10-19 用户「先A后B」）**：**A = 批 11**（F19 原生图片块 + F20 用量）先行；**B = 批 2**（F8 远程 SSH）随后。

## 10. 裁定记录（用户逐字要点，2026-10-16）

- 2026-10-17 · B1 例外（批 8）：**「可以动thincoder仓库」**——允许为 F16 改 thincoder 仓（ACP 挂起窗 + 回合边界帧），保持上游可合并。
- 2026-10-19 · 用户 01:21：「原生图片块；远程SSH；用量这几个我们也要提上日程了」——三点入需求池：F8 远程 SSH（批 2，复用）· F19 原生图片块 · F20 用量；F19/F20 的正式条目与验收在各自批次启动时落。
- 2026-10-19 · 用户 01:37：「运行改thincoder仓库」——F19 的 B1 例外获准（方案 A）；CLI 侧另立 out-of-repo 轮，保持上游可合并。

- 2026-10-19 · 用户 19:45：「模型以后都用视觉型即可，大模型厂商也会逐渐做的综合全面」——图片/视觉面不为「非视觉模型」加提示（#96 撤回）；模型选型以视觉模型为准。

- 「加上 thincoder 内核，Claude 保留，thincoder 为默认，需要和终端的 thincoder 相通；全做；
  thincoder 用户自己的事情；thincoder 的配置去用户电脑里面找……我做出来桌面版之后只需要添加配置即可；不改 thincoder 仓库」。
- 「替代吧；一并对接 thincoder」（图片走替代方案；Customize 一并对接 thincoder 定制面）。
- 「baocode 是其它项目，thincoder 是运行终端……保证两个东西更新的时候我们留足空间来拓展更新适配」（§4）。
