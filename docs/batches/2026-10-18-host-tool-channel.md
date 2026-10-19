# 2026-10-18 · host-tool-channel
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-18 · 来源 = 用户 2026-10-18 20:08「对，一定要实现宿主工具通道」。
> 台账 = #55（host-tool-channel · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-18
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-18）

### 来源与授权

- 用户 2026-10-18 20:08「对，一定要实现宿主工具通道」——本批 = 该机制的首次设计（不写实现）。
- 前情 = 无（独立批）。

### 本批是什么

- 机制设计：让宿主工具（首批浏览器工具）对 thincoder 内核可见、可调用；通道与具体工具解耦，为后续宿主工具留统一接缝。
- 设计交评审、用户批准后才进实现；本批不写产品代码。

### 已知事实（实读）

- 浏览器工具 = `ClaudeSdkTool`，只注册进 `ClaudeSdkTools`（`lib/browser/browser_tools.dart:70-98`）；Claude 内核把 SDK MCP server 交给 CLI（`lib/kernel/claude_code/claude_code_kernel.dart:512-516`、`:553`）。
- thincoder `session/new` 只发空 `mcpServers`（`lib/kernel/thincoder/thincoder_kernel.dart:321-325`）；CLI 忽略非空（`thincoder/thincoder-cli/src/acp/handlers-session.mjs:266-267`「MCP forwarding is M2 scope」）。
- ACP 无通用客户端工具声明；反向请求只有 `fs/*` 与 `session/request_permission`。
- 浏览器边界：黄色「BaoCode」分组 + 扩展 ID 白名单 + `browser.enabled` 开关（`lib/browser/browser_bridge.dart:32`、`:41`、`:88-100`）。

### 范围

- 需求档 `docs/requirements/host-tool-channel.md` 的 F1–F5 · B1–B4 · A1–A5。

### 范围外

- 不实现图片 / IDE 上下文 / 终端 / 文件系统工具；不改浏览器边界；不改 Claude 工具路径；不在本批写 thincoder 代码（设计只出方案，实施按设计另派）。

### 批准后父侧文档落点（2026-10-18）

- `docs/requirements/thincoder-adapter.md` ⑳ 已由父侧补：§2.2 宿主工具通道一行、§5 注一行、B1 例外状态一行（记用户 20:08 + 20:40 两次原话）。
- `docs/design/thincoder-adapter.md` ⑲（§5.2 改动点清单 / 体量立场 / 能力映射面）待 B 轮读数后由 eng-designer 落。
- 实施分两轮：A = 机械改名 + `HostTools` 注册表（eng-coder #3）；B = `HostMcpServer` + thincoder 接线 + 测试（eng-coder #4，按 `browser_tools.dart` 重叠排队）。外仓 thincoder 轮随后由父侧另起。

### A 轮（机械改名）父侧核验（2026-10-18）

- 读数：`flutter test test/host_tools/host_tools_test.dart` → **13/13 passed**；`ClaudeSdk` 在 `**/*.dart` **零命中**；旧档 `lib/kernel/claude_code/claude_sdk_tools.dart` 已删、新档 `lib/host_tools/host_tools.dart` 在（252 行）；`handle` 的 initialize / tools/list / tools/call / 取消 / `called()` 逐段实读未变。
- 清单外 7 档：5 个 live/测试档 import 编译必需 + `chat_models.dart` / `claude_code_transport.dart` 两处注释死指针；均净 0，按「期望触面 ≠ 授权边界」披露后准许。
- 设计漂移（交 ⑲ / 收口）：① §7.1 ⑯ 与 §10 仍写 `test/kernel/claude_sdk_tools_test.dart`，实际迁到 `test/host_tools/host_tools_test.dart`；② §4.7 `picturesOnly` 未实现（B 轮任务书已含）；③ `docs/requirements/host-tool-channel.md:13` 的类型名已由父侧更新为 `HostTools`。
- B 轮 #4 已在 A 完成后自动启动（当前 running）。

### B 轮（功能半场）父侧核验（2026-10-18）

- 读数：`flutter test test/host_tools/host_mcp_server_test.dart test/kernel/thincoder_kernel_test.dart test/host_tools/host_tools_test.dart` → **115/115 passed**；`flutter analyze` 改动面 **0 issue**（全项目 11 条本批外既有提示）。
- `HostMcpServer` 实读 328 行：127.0.0.1 环回、Bearer 令牌（32 字节随机、不落盘）、组白名单 `{'browser'}`、`picturesOnly` 排除、图片折行、1 MiB → 413、取消转交、ping、错误映射、`revoke` / `shutdown`；内核侧门 `mcpCapabilities.http`（`thincoder_kernel.dart:383`）、`_servers` 发 grant（`:264-268`）、请求带 `mcpServers`、`_teardown` 撤令牌（`:403-405`）。
- 清单外 3 档（已批准）：`host_tools.dart` 的 `picturesOnly` / `named()`、`browser_actions.dart` 的 `picturesOnly: true`、`thincoder_mock.dart` 的 `httpMcp`。
- 遗留（非阻塞，已在报告披露）：新会话 grant 的 `sessionId` 为空 ⇒ `_calls` 键可能跨会话碰撞（**已记台账，归批**）；`'browser'` 字面量、`initialize.instructions` 取全体特性文本（今日只有 browser 调 `instruct`，无可见差异）—— 记录不修。
- 设计漂移（交 ⑲ 收口）：§7.1 ⑯ / §10 测试档路径仍写旧档；§7.1 ③ 把 `picturesOnly` 记在 `browser_tools.dart`（实际 `browser_actions.dart:105`）；§7.1 ⑱ 估 +140、实际 +211。
- 外仓 thincoder 轮（`mcpServers` 转发 + `permissionExempt`）未起 —— 本批的下一步，等用户点头。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（实施后收口（设计档 §16）已落；⑲ 面（thincoder-adapter §5.2 / 体量 / 能力映射）已落 · 2026-10-18）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 本批条目（覆盖）

设计档 = `docs/design/host-tool-channel.md`（514 行）。需求档 = `docs/requirements/host-tool-channel.md`（主 agent 笔，本批只读）。

| # | 需求 | 判定句 |
|---|---|---|
| 1 | **F1** 通道（统一描述：名称 / 说明 / 输入 schema / 执行入口） | 设计 §4.7 注册面 + §4.3 `tools/list` 线形 |
| 2 | **F2** thincoder 可用（可见 + 可调用，共享标签页边界一致） | A1 走查 2–4 + T11 |
| 3 | **F3** 开关与回收（不可见或明确拒绝，不假装成功） | T8 + 走查 5 / 7 |
| 4 | **F4** 旧版兼容（无工具、无报错） | T12 + 走查 6 |
| 5 | **F5** 可扩展（统一接缝） | `HostTool.group` + `exposedGroups`（本批只开 `browser`） |

### 明确不在本批

图片 / IDE 上下文 / 终端 / 文件系统工具（B1）；浏览器语义与扩展协议（B2）；Claude 路径行为（B3，只做类型改名）；thincoder 与浏览器无关的行为（B4）；本批不写产品代码；需求档改写（主 agent 笔）。

### 选型结论

**A2 采用**：ACP 标准 `mcpServers`（`session/new|load|resume`）+ baocode 进程内的环回 Streamable HTTP MCP server（127.0.0.1、系统选端口、每会话一枚 32 字节 Bearer 令牌）。

- **A1（stdio 子进程）被否**：第二个可执行体跨三平台打包 + 一条回连 IPC，两条本机面换零收益。
- **B（ACP 自造反向工具面）被否**：ACP 无「客户端工具」概念，官方答案就是「客户端自带 MCP server」（规格逐字）；自造面不可上游合并 ⇒ 长期 fork，且两侧新代码量不低于 A2。
- **C（混合）被否**：能力协商已由 ACP 的 `mcpCapabilities.http` 给出，声明面不需要自造。

### 机制要点（详见设计档）

- **能力协商**：内核在 `initialize` 宣告 `agentCapabilities.mcpCapabilities.http`；我方只在它为 true 且暴露组非空时发 `mcpServers`。旧 CLI 不看该键 ⇒ 我方不发 ⇒ 无工具、无报错、无 warn（F4）。
- **工具来源**：`HostTools`（由 `ClaudeSdkTools` 正名迁入 `lib/host_tools/`）仍是唯一真名面；Claude 面继续走 control 通道的 `handle`（语义零改），MCP 面按组暴露并复用同一份 `handle`。
- **审批**：宿主工具免审（与 Claude 面 `--allowedTools mcp__baocode` 同权）；thincoder 侧用 `_meta["baocode.dev/trusted"]` → 工具 `permissionExempt`，不改成 `readonly`（假契约 + 会流进只读子代）。主防线仍是扩展 ID 白名单 + 黄色分组 + `browser.enabled`。
- **图片**：thincoder 的 MCP 客户端把 image 块 `JSON.stringify` ⇒ 该面不出 `browser_screenshot`，混合答案里的图片折一行注记（宿主能力面差异，有证据、有判定条件）。
- **生命周期**：监听器活到进程退出（URL 被 CLI 进程持有，换端口会永久失联）；回收 = 组移出暴露集 + 调用明确拒绝 + 不发新令牌；令牌随 `_teardown` 撤。

### 受影响文件（估算；细表见设计档 §7）

本仓：新 `lib/host_tools/{host_tools,host_mcp_server}.dart`（~295 行）；`thincoder_kernel.dart` ≤ +40（1156 ⇒ ≤1196）；`thincoder_events.dart` ≤ +14（784 ⇒ ≤798）；浏览器工具 7 档机械改名 + `browser_tools.dart` ≤ +15；`image_tools.dart` +2；Claude 侧 2 档机械改名；测试新增 1 档 + 2 档增补（≤ +400）。
thincoder 仓（out-of-repo 轮）：新 `acp/mcp-forward.mjs`（~70）+ 6 档改动（~50）+ `dispatch.mjs` / `mcp.mjs`（各 +2）+ 该仓设计档与批次档。

### 验收对照（A1–A5）

| 条目 | 判据 |
|---|---|
| A1 | T11 + 走查 2–4（工具表 27 个 `baocode_browser_*`；open / click / type 生效） |
| A2 | 走查 3 / 5 / 7 + T8 |
| A3 | T16（Claude 面逐字段不变）+ 走查 6 |
| A4 | T12（不宣告能力 ⇒ 不发）+ 走查 6 |
| A5 | T1–T15 全绿；`test/fixtures/thincoder/` 不改 |

### 关键决策（D1–D11，全文见设计档 §8）

D1 选型 A2 · D2 注册面正名 `HostTools` · D3 `group` + 按组暴露 · D4 `mcpCapabilities.http` 门 · D5 宿主工具免审 · D6 每会话令牌（不落盘 / 不进 URL）· D7 监听器活到进程退出 · D8 图片面差异 · D9 策略文本走入口 description · D10 工具卡按注册表还原 · D11 不加 `AgentKernel` 能力接口。

### 上抛 / 发现

1. **[知会] 需求档五要素核对通过**（模块目标 / F1–F5 / B1–B4 / A1–A5 / D1–D3 齐全，可设计）。A1 的「工具列表含浏览器工具」按 B1 落为 27 个（`browser_screenshot` 不在 thincoder 面），有判定条件（设计档 §12-1）。
2. **[知会] 上游事实**：thincoder 的 ACP 侧目前不宣告 `mcpCapabilities`（`client-caps.mjs:52-64` 注释逐字「mcpCapabilities … 本批不做」），与其 ACP-CLIENT.md 的 G7 登记一致——本批的转发面正是该仓已登记、待做的 M2。
3. **[知会] 仓内既有档的两处纪律问题（不在本批范围，未改）**：`docs/design/thincoder-adapter.md` 末尾有「变更记录」段（与「设计/需求档不写历史」的裁定相抵）；`doc_check` 在 docs 下另有 41 条既有命中（裸 `ACP-CLIENT.md` / `AGENTS.md` 锚与 21 条超宽行），均非本批产物，交主 agent 归批清理。
4. **[待裁] 无**：设计档无 open 项；需要裁定的只有「D2 机械改名是否随批」与「D5 免审口径」两项，均已给出理由与被否方案，评审可直接判。

### §2 修正轮 1（评审 #1–#10、#12 落地；零代码）

- 设计档 `docs/design/host-tool-channel.md` 修正后读数 = 528 行（修正前 513）；行宽扫描仅余 2 条既有 >300（§2.3 调查表两行，非本轮产物）。
- 全文门语义统一为 `_httpMcp && HostTools.anyIn(exposedGroups)`（§4.2 / §5.1 / §5.3 / §14 / D4）。
- 本轮只改设计档；本仓与 `thincoder/` 产品代码、需求档、批次档 §1/§3/§4/§6 均未动（#11 已由父侧改需求档 `:15`）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

## 设计评审（docs/design/host-tool-channel.md）

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Clarity | 🟡 | 发/不发的门在档内有两种写法：`docs/design/host-tool-channel.md:150` 写「**且**暴露组非空时发」，而 `:276` 把 `exposedGroups` 定义为本批常量 `{'browser'}`、`:292` 的具体判据是 `HostTools.anyIn({'browser'}) && _httpMcp`（组内已注册工具非空）。按 `:150` 字面实现（集合非空）时，开关关后 unregister 仍满足「非空」⇒ 与 `:317` 的「开关关 ⇒ … ⇒ 暴露组空 ⇒ 新会话不发」相左，且 T13（`:447`）会红。 | 把 `:150` / `:317` / `:497` 的门统一表述为「暴露组内无已注册工具（`anyIn` 为假）」；`exposedGroups` 只表示组白名单常量，回滚语义另算一行。 |
| 2 | Clarity | 🟡 | `:301` 要求「应用退出时 `shutdown()` 关闭」，但 §7.1（`:345-364`）的受影响文件表没有任何一格承载该调用点（`lib/workbench.dart` 与 app 生命周期文件都不在表内）；`:288` 又把监听器的绑定画在 `BrowserTools.start()` 之下，启动/关闭两个接缝的落点都不在清单里。 | 在 §7.1 补上 `shutdown()` 的调用点（或声明「进程退出由 OS 回收，不设显式钩子」），并把 §5.1 起停图里的懒启动触发者写成具体文件。 |
| 3 | Document ownership | 🟡 | 本批改 `lib/kernel/thincoder/thincoder_kernel.dart` / `thincoder_events.dart`（`:360-361`），并在 ACP 面新增 `session/new|load|resume` 的 `mcpServers` 用法（`:140-152`），但 `docs/design/thincoder-adapter.md` 与 `docs/requirements/thincoder-adapter.md` 均未进受影响清单：E2「对宿主以增量为限：…改动可独立辨认」（`docs/requirements/thincoder-adapter.md:136`）、E5「§5 能力映射表…为双端适配的单一维护点」（`:143`）要求逐点登记；该仓 B1 例外的裁定记录（`:173` 口径）也未回写。 | 在清单里补一行「更新 `docs/design/thincoder-adapter.md` 的改动点清单/能力映射 + `docs/requirements/thincoder-adapter.md` §2.2 的 ACP 面用法」，并标明该批属 B1 例外。 |
| 4 | Scope | 🟡 | D2 把 `ClaudeSdkTool(s)` → `HostTool(s)` 并迁目录，波及 13+ 档（含 3337 行 `claude_code_kernel.dart`、1945 行 `claude_code_translator.dart`，`:358-359`），与本批功能面（通道）耦合在同一批；`docs/design/host-tool-channel.md:399` 自称机械改动，但与 `docs/requirements/thincoder-adapter.md:136` 的「改动可独立辨认，便于上游更新时合并」相左（评审面被改名噪声稀释）。 | 把改名拆成先行的一批（或独立提交/纯机械 diff），通道功能批只带接线；两批各自给读数（测试全绿 + 零行为断言）。 |
| 5 | Feasibility | 🟡 | `:89` 把「上游可合并性」判为「**高**」，依据只是 M2 转发面已登记；但 thincoder 侧 ⑦⑧（`:385-386`：`config.trusted` → `permissionExempt` → `dispatch.mjs` 免审短路）是**第二个上游面**，未在 `:67-71` 的公开资料调查与 `:89` 的可合并性评估里出现；`:236` 的信任标由客户端自述，档内未声明「client 即信任锚」。而 `:481` 仍写「**未决项**：无」。 | 把信任机制单列一条：说明信任锚 = 提交请求的客户端、给它的上游接受风险一句评估，并在 §12 登记一条判定条件（如「上游拒绝该位 ⇒ 回落到逐调用审批」）。 |
| 6 | Precedent | 🟡 | §2.2「最近先例对照」（`:45`）有实现坐标与偏离理由，但缺**先例批次**坐标：本批形态（外仓 ACP 扩面 + 本仓接线）在需求档里有明确批次先例（F12/F16 的 B1 例外批），表内未引任何一条。 | 在 §2.2 表内补一列／一行先例批次（外仓批次档坐标 + 该批的偏离裁定），使「照抄谁」可回溯。 |
| 7 | Clarity | 🔵 | `:347` 写明 `lib/host_tools/host_tools.dart`「迁自 `lib/kernel/claude_code/claude_sdk_tools.dart` 229 行」，但清单里没有该源文件的删除/清空行；`:500` 的回滚描述（「还原文件名与符号」）反证它是被移走。 | 受影响表补一行「删除 `lib/kernel/claude_code/claude_sdk_tools.dart`（迁出）」，让清单可对账。 |
| 8 | Numeric drift | 🔵 | `:94` 估「~260 行 server + ~70 行接线 + 测试」，而 §7.1 的接线是 ⑭ ≤+40 + ⑮ ≤+14 = 54（`:360-361`）；两处口径不一致。 | 统一为 54（或说明 70 含未列的小改动）。 |
| 9 | Acceptance | 🔵 | §4.3 已把 `413`（`:173`）与 `ping`（`:185`）写成线上契约，§10 用例表（`:428-439`）无对应；另 `:152` 要求 `session/load` / `session/resume` 也带 `mcpServers`，T11 只断言 `session/new`。 | 补 T-case（413 / ping / load 带 `mcpServers`）或把该三处从契约里降级为「不保证」。 |
| 10 | Size annotations | 🔵 | 体量立场（`:368-373`）只覆盖 `thincoder_kernel.dart`、`thincoder_events.dart`、大测试档与 ④–⑩；⑫⑬⑯（`:358-359`、`:362`）虽标「净 0」但无「未跨结构档」的显式句。`thincoder_kernel.dart` 的「**不动结构** ⇒ 不触发「先立拆分批」」（`:370`）对 >800 档读作豁免声明，宜改为指向既有缝计划。 | 用一句覆盖所有「净 0 / 机械改名」档，并把 >800 档的措辞改写成「按 `thincoder-adapter` §18.4/§19.4 的既有缝计划执行，触发条件不变」。 |
| 11 | Doc-state | 🔵 | `docs/requirements/host-tool-channel.md:15` 括注引 §2.2，但说「客户端反向请求只有 `fs/*` 与 `session/request_permission`」，而 `docs/requirements/thincoder-adapter.md:46` 还列了 `checkpoint/*`、`memory/*`、`ledger/*`、`batch/*` 扩展族；引文比被引处窄。 | 把该句限定为「标准反向请求」并注明扩展族不计，避免设计侧候选 B 的否决理由被读成引文失准。 |
| 12 | Sequencing | 🔵 | §15 走查（`:504-513`）是 A1/A2/A3 的主要判据，但它要求一个已含转发面与信任位的 thincoder 构建；档内未写该前置（§7.2「另行起 out-of-repo 轮」只说交付面，未说走查排序）。 | 在 §15 首行注明「走查前置：外仓批次已落地并可指 `thincoder.path`」，让 A 段交付时不必猜。 |

统计：🟡 6 · 🔵 6 · 🔴 0。

备注：项目无 AGENTS.md、无项目标准档、无文档地图（Document Map）⇒ 方法论合规与「文档归属」两项按评审准则与在范围的另两份档判定，非本仓既定规范；代码行号类断言（`:89`、`:236`、`:276` 等外仓/本仓坐标）未在评审范围内实读，仅作设计自述证据。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（2026-10-18）

- 用户 2026-10-18 20:40「好的，那就直接批准开工宿主通道」。
- 批准对象：设计档 `docs/design/host-tool-channel.md`（评审 pass + 修正轮 1 已核验）与批次档 §2 的任务。
- 实施分两轮（同一设计 token）：A = 机械改名 + `HostTools` 注册表；B = `HostMcpServer` + thincoder 内核接线 + 测试。外仓 thincoder 轮随后由父侧另起。
- 本批外仓面的 B1 例外：用户 2026-10-18 20:08「对，一定要实现宿主工具通道」+ 20:40 批准开工；保持上游可合并。

## §5 实施记录（eng-coder）

**状态行**：实施完成（A 轮机械改名 + B 轮功能半场 · 2026-10-18）

### 交付摘要（A 轮）

- 注册面正名并迁档：`lib/kernel/claude_code/claude_sdk_tools.dart`（229 行）→ `lib/host_tools/host_tools.dart`（252 行）。类型 `ClaudeSdkTool` → `HostTool`、`ClaudeSdkCall` → `HostToolCall`、`ClaudeSdkTools` → `HostTools`；`handle` 的 initialize / tools/list / tools/call / notifications/cancelled 与 `called()` 语义零改。
- 注册表 API 新增：`HostTool.group`（默认 `''`；注册值按任务书归 B 轮）、`HostTools.byGroup` / `anyIn` / `lookup`。
- 引用点：lib 侧 5 档（`browser_tools` / `image_tools` / `claude_code_kernel` / `claude_code_translator` + 2 处注释指针）、test 侧 6 档，import 全部改指 `host_tools.dart`。改名处数（HEAD 旧名出现）：77 × `ClaudeSdkTool(s)` + 12 × `ClaudeSdkCall` + 13 × `claude_sdk_tools` 路径/注释，跨 19 个既有档（含被迁测试档）。
- 测试：`test/kernel/claude_sdk_tools_test.dart`（157 行）迁为 `test/host_tools/host_tools_test.dart`（315 行）；保留原 5 个用例，补 T16 七条逐字段断言 + 分组 API 用例，共 13 例。
- 未做（按范围）：group 注册值（`browser` / `images`）、`picturesOnly`、`HostMcpServer`、thincoder 接线、浏览器行为、扩展协议、docs、`thincoder/`。

### 决策透明表

| # | 决策 | 依据 | 影响 |
|---|---|---|---|
| 1 | `HostTool.group` 默认 `''`，本轮不赋注册值 | 任务书「不改 `group` 的注册值（`browser` / `images` 的赋值在 B 轮）」；保持既有 28 个工具构造点零改动 ⇒ 零行为变化 | B 轮必须在 `browser_tools.dart` 包装器与 `ImageTools.tool()` 补组值，否则 `anyIn` 恒假、§4.2 门永不开 |
| 2 | `claudeSdkImage` / `claudeSdkText` 保留旧名 | 设计 §4.7 只正名三个类型，§10 T7 仍按旧名写断言 | 无行为影响；将来改名需同步设计引用 |
| 3 | 测试档迁到 `test/host_tools/`（设计 §7.1 ⑯ 仍写 `test/kernel/`） | 任务书明示「测试档迁到 `test/host_tools/host_tools_test.dart`」 | 设计 §7.1 ⑯ / §10 的路径需父侧对账；代码侧无缺陷 |
| 4 | 清单外 7 档（5 个测试档 + 2 处注释指针） | 5 档直接 import 被删档 / 用旧类型名，不更新即无法编译；2 处注释是被删档名的死指针 | 全部披露；除这 7 档外无其他改动 |
| 5 | 未加 `picturesOnly` | 任务书 A 轮 API 只列 group / byGroup / anyIn / lookup；该字段服务 MCP 面（D8 / §12-1） | B 轮补，且需与 `browser_screenshot` 打标同落 |

### 验证读数

- `flutter analyze`（本轮改动面 10 个路径项，覆盖任务书 15 档 + 清单外 7 档）：`No issues found!`（14.1s；复跑 4.8s）。
- `flutter test test/host_tools/host_tools_test.dart`：13 例全绿（含 T16）。
- `flutter test test/browser/`：23 例通过、6 例跳过（`BAO_BROWSER_LIVE` 未设，live 用例）、0 失败。
- `flutter test test/images/image_tools_test.dart`：12 例全绿。
- `dart format --output=none --set-exit-if-changed`（20 档）：0 changed。
- `git status --short`：本轮 = 任务书 15 档 + 清单外 7 档（见决策表 #4）；其余均为会话前既有未提交项（`docs/*`、`lib/chat/side_panel/side_panel_view.dart`、`linux/flutter/generated_*`、`PROJECT-MANIFEST.json` 等）。

### 审计与评审轮次（终态）

- 内部 explore 分歧审计（1 轮）：代码侧无偏差；指出设计 §7.1 ⑯ / §10 测试档路径漂移、§4.7 `picturesOnly` 未落、批次档 §5 空缺（本段即补）。
- 内部 advisor 代码评审（2 轮）：第 1 轮 `changes-required` —— 2 条 🔴「注册面未赋 group」（按任务书属 B 轮、经父侧复核为 scope 外）、2 条 🔵（头注释语法、测试状态清理）已修；第 2 轮复核 `pass`。
- 终态：`clean`（0 个未处置 fix round；B 轮待办见决策表 #1 / #5）。

### fix round

1. `lib/host_tools/host_tools.dart:1` 头注释补关系词（语法修正）。
2. `test/host_tools/host_tools_test.dart` 的 instructions 清理改 `addTearDown`（测试隔离）。
- 两处均为注释 / 测试隔离，无行为改动；复跑 analyze / test / format 全绿。

### B 轮 · 功能半场（2026-10-18）

#### 交付摘要

- 新 `lib/host_tools/host_mcp_server.dart`（329 行）：127.0.0.1:0 环回 Streamable HTTP MCP 端点；每请求一枚 32 字节随机令牌（base64url 去 padding = 43 字符，只走 `Authorization` 头，不落盘/不进 URL）；`revoke` 撤销（`_teardown` 调用）；复用 `HostTools.handle`；组过滤（`exposedGroups = {'browser'}`）+ `picturesOnly` 排除 + image 块折一行文本注记；错误映射 401 / 404 / 405 / 413、-32602 / -32601 / -32700；通知 202（`notifications/cancelled` 转交 handle 真取消）；请求体 1 MiB 上限；`ensure()` 懒绑定、失败记一条 appEvent 且会话照常；`shutdown()` 仅测试可见，不设应用退出钩子（D7）。
- 注册面：`HostTool.picturesOnly`（默认 false）+ `HostTools.named()`（ACP 名 `baocode_<tool>` → 注册表项）；`BrowserTools.register` 赋 `group: 'browser'`、透传 `picturesOnly`、五个入口工具（tabs/open/navigate/evaluate/act）description 补一句「the user's own browser」（D9）；`browser_screenshot` 标 `picturesOnly: true`；`ImageTools.tool` 赋 `group: 'images'`。
- 内核接线：`_handshake` 记 `mcpCapabilities.http`；`_hostMcpServers()` 门 = `_httpMcp && HostTools.anyIn(exposedGroups)`，过门才 `ensure()` + `issue()`；`session/new` / `session/load` / `session/resume` 带 `cwd` + `mcpServers`（不过门时省略该键，不带空数组）；`_teardown` 撤令牌。
- 工具卡：`ThincoderEvents._tool` 在 `other`/未知 kind 时经注册表还原 `kind` / `summary`，并保留 `tool` / `input`；`_replaced` 的完成态继续携带 `tool` / `input`；非宿主工具仍为 `other` 卡（零回归）。
- 测试：新 `test/host_tools/host_mcp_server_test.dart` 13 例（T1–T10、T10② 取消、T17、T18）；`test/kernel/thincoder_kernel_test.dart` 增 T11–T15，既有 6 处 `session/load|resume` 断言补 `cwd`、`session/new` 断言改为「不含 `mcpServers` 键」。

#### 决策透明表

| # | 决策 | 依据 | 影响 |
|---|---|---|---|
| 1 | 清单外三档：`HostTool.picturesOnly`、`browser_screenshot` 打标、`ThincoderMock.httpMcp`（默认 false） | 用户 2026-10-18 批准三档扩展；设计 §4.7 / §12-1；A 轮 §5 决策 #5 留 B 轮 | 已逐条披露；mock 既有用例零变化 |
| 2 | 开关关后的拒绝句：端点记住曾发放的工具名/组（`_given`），注册表已移除时按「本可暴露、已撤下」回设计指定的 off 句 | 设计 §5.2 / §4.3 / F3（审计发现 1） | 会话建立后关开关 = 明确拒绝，不落成 `No tool` |
| 3 | `notifications/cancelled` 不再止于 202：先转交 `HostTools.handle` 再回 202 | 设计 §4.6「宿主侧已实现」/ §12-3（审计发现 2） | 未来客户端发取消即真取消；T10② 覆盖 |
| 4 | `initialize.instructions` 仍取全体特性文本（经 handle） | 设计 §4.3 写「组内说明」，但 §2.2 要求复用 handle；今日仅 browser 调 `instruct` | 无可见差异；列为 latent（非暴露组将来 `instruct` 时需按组过滤） |
| 5 | 新会话的 grant `sessionId` 为 `''`（`mcpServers` 必须先于 session id 存在） | 设计 §4.2 三处请求同形；`HostToolCall.sessionId` 当前无消费方 | 已知限制；两个新会话并发时取消键可能碰撞（thincoder 当前不发取消） |
| 6 | 相对 import 深度统一为单级（`../chat` / `../platform`） | 实测 Dart 包 URI 把 `..` 钳在包根（`Uri.resolve` → `package:baocode/chat/...`），原双级可编译；统一成邻近文件写法 | 纯可读性，零行为 |
| 7 | D9 句子落在共享注册表，Claude 面 `tools/list` 的五个入口工具 description 也带该句 | 设计 §7.1 ③ 把该改动记在 `browser_tools.dart` | 字段与行为不变；A3/T16 断言不受影响 |
| 8 | `exposedGroups` 用可变 static Set（非 const） | §4.2 / §14 的「置空回滚」需运行时可置空；T8 依赖 | 白名单仍只在本批代码内赋值 |

#### 验证读数

- `dart --suppress-analytics analyze`（10 档改动面）：`No issues found!`
- `flutter test test/host_tools/host_mcp_server_test.dart test/kernel/thincoder_kernel_test.dart test/host_tools/host_tools_test.dart`：115 例全绿（13 + 89 + 13）。
- `flutter test test/browser test/images/image_tools_test.dart`：35 例通过、6 例跳过（`BAO_BROWSER_LIVE` 未设）、0 失败。
- 行数（`find /c /v ""`）：`thincoder_kernel.dart` 1195（≤1196）、`thincoder_events.dart` 798（≤798）、`browser_tools.dart` 689（≤690）、`image_tools.dart` 600（599+1）、`host_mcp_server.dart` 329、`host_mcp_server_test.dart` 353、`thincoder_kernel_test.dart` 2840（+211；超设计 §7.1 ⑱ 的 +140 估算，属估算非任务书上界）。
- `git status --short`：本轮 10 档 = 任务书 7 档 + 已批准 3 档（`host_tools.dart` / `browser_actions.dart` / `thincoder_mock.dart`）；其余为 A 轮与会话前既有项（`docs/*`、`lib/chat/*`、`linux/flutter/generated_*`、`PROJECT-MANIFEST.json` 等）。

#### 审计与代码评审轮次（终态）

- 内部 explore 分歧审计（1 轮）：🟡×1（开关关后拒绝句落成 `No tool`）、🔵×1（cancelled 未接）；T1–T18 覆盖、门/令牌/线形/组过滤/行数/清单外核对全过；无 PARTIAL、无未披露的清单外改动。
- 内部 advisor 代码评审（2 轮）：第 1 轮 `changes-required` —— 🔴×3（其中 2 条相对 import 深度经 `Uri.resolve` 实测为误报、仍统一为单级写法；1 条 `_replaced` 丢 `tool`/`input` 为真）、🟡×3、🔵×3；第 2 轮逐条复核 `pass`（3 条 🔴 全部 Fixed）。
- 终态：`clean`（0 个未处置 fix round；遗留 2 条 🟡 + 2 条 🔵 均为评审明确「非阻塞」的潜在面，理由见决策表 #4/#5 与评审记录）。

#### fix round

1. `_given` 记录已发放工具名/组；注册表已移除时回 off 句；T8 增「开关关」第二阶段（审计 🟡）。
2. `notifications/cancelled` 转交 `HostTools.handle`；新增 T10②（审计 🔵）。
3. `_replaced` 完成态携带 `tool` / `input`；T15 增完成态断言（评审 🔴）。
4. 相对 import 深度统一单级（评审 🔴 误报，规范化）。
5. 失败路径二次应答加保护（评审 🟡）；T14 的 `HttpOverrides` 用 `addTearDown` 还原（评审 🔵）。
- 复跑 analyze 与 115 例全绿。

#### 行数复核（`find /c /v ""` 口径）

- 新档：`host_mcp_server.dart` **328** 行、`host_mcp_server_test.dart` **352** 行（上文写 329 / 353 为编辑器末行计数，差 1 属口径）。
- 其余复核一致：kernel 1195、events 798、browser_tools 689、image_tools 600、host_tools 263、browser_actions 626、thincoder_mock 632、thincoder_kernel_test 2840。

## §6 验证与收口（父代理）

## 验证与收口（2026-10-18 · 父代理）

### A / B 两轮核验（父侧实跑 / 实读）

- A 轮：`flutter test test/host_tools/host_tools_test.dart` → **13/13**；`ClaudeSdk` 在 `**/*.dart` 零命中；旧档已删；`handle` 语义实读未变。
- B 轮：`flutter test test/host_tools/host_mcp_server_test.dart test/kernel/thincoder_kernel_test.dart test/host_tools/host_tools_test.dart` → **115/115**；`flutter analyze` 改动面 **0 issue**；`HostMcpServer` 328 行（环回 / 令牌 / 组过滤 / 图片折行 / 1 MiB / 取消）。
- 清单外 3 档已批准：`host_tools.dart` picturesOnly/named、`browser_actions.dart` 打标、`thincoder_mock.dart` httpMcp。

### 端到端 A1–A4（用户 2026-10-18 22:29 实测）

- app 的 thincoder 会话经宿主通道调用 `browser_tabs` / `browser_snapshot`（只读），读到用户共享标签页（51marine Master Data）并把内容回给模型；**无权限确认** ⇒ A1 / A2 / A3 通过。
- A4（坏服务不阻断）由 CLI 侧 T7 / T12 机检覆盖。
- 前提 = `npm link` 本地 CLI。

### 设计收口

- `docs/design/host-tool-channel.md` §16（#23）：三处漂移（测试档路径 / `picturesOnly` 定义处 / ⑱ +211）+ §7.1 实施读数 + §12 三项遗留。
- `docs/design/thincoder-adapter.md` ⑲（#24）：§5.2 补 ⑪/⑫ 两档 + 能力映射 ACP `mcpServers` 用法 + 实施读数。

### 遗留（在册，非阻塞）

- 台账 **#71**（新会话 sessionId 空）· `'browser'` 字面量 · `initialize.instructions` 全特性——均带判定条件（设计 §12）。
- 外仓 **#4**（回收 id 的 close 同键误关）另批。

### 结算

- 台账 **#55 已核销**；designToken 已消费（ccccd8b3）。
- 收口扫描：**#57 撤回**（「thincoder 会话浏览器工具不可用的产品提示」——通道已落地，前提消失）；**#56** 证据更新（HostTool 契约已落，locality / 允许列表 / 远端认证仍待）。
