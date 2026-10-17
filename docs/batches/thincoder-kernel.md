# 2026-10-16 · thincoder 内核（本地）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-16 · 来源 = 用户 2026-10-16 会话裁定（thincoder 桌面适配，批 1 = 本地内核全链路）。
> 台账 = #1（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-16
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 讨论与裁定（2026-10-16 · 主 agent 记录）

**需求来源**：用户会话逐条裁定——「加上 thincoder 内核，Claude 保留，thincoder 为默认，需要和终端的 thincoder 相通；全做；thincoder 用户自己的事情；thincoder 的配置去用户电脑里面找……不改 thincoder 仓库」；「替代吧；一并对接 thincoder」；「baocode 是其它项目……保证两个东西更新的时候我们留足空间来拓展更新适配」。

**本批交付目标**：本地 thincoder 内核全链路（需求档 F1–F7、F10 + 扩展性 E1–E5）。

**关键事实（已核实坐标）**：
- 宿主内核抽象与默认机制：`lib/kernel/agent_kernel.dart`（接口 + 22 个能力接口）· `lib/kernel/kernel_registry.dart:29`（当前单内核）· `lib/workspace/workspace.dart:239-240`（默认 = 注册表首位）· `lib/chat/chat_session.dart:303-316`（内核选择器）· `:300`（对话开始即锁定内核）。
- 接入通道：`thincoder acp`（ACP v1 · stdio NDJSON）；握手 `thincoder/thincoder-cli/src/acp/client-caps.mjs:52-64`（协议版本协商 :18-21；能力如实声明、图片 false）；错误面 `acp/transport.mjs:14-20`。
- 与终端相通：`session/list` 直读持久槽（`acp/handlers-slots.mjs:42-62`）；配置多端共享 `~/.thincoder/config.json`。
- 图片替代：落 `<cwd>/.thincoder/tmp/` + 消息路径引用（ACP 不声明图片能力）。

**范围缺口处置**：ACP 不声明面（图片直传 / 多文件夹 / fork / 回退 / 后台任务 / 队列控制 / 账号用量 / 建议类 / 改名）→ 内核不声明、UI 自动隐；逐条见需求档 §5/§6。

**批次计划**：批 1 = 本批（本地内核）；批 2 = 远程 SSH；批 3 = Customize 对接 + 收尾。批界以设计为准。

**需求档**：`docs/requirements/thincoder-adapter.md`（待用户过目确认后进设计）。

### 实现期缺口与处置（2026-10-16 · 主 agent 记录）

- eng-coder #5 在接线实现中经两条独立评审 + 父侧源码复核确认一处设计覆盖缺口：`lib/workspace/workspace.dart` 的 load 回路用**跨内核合并的 `listed`** 做跳过判据（`:291-309`、`:314-320`）⇒ claude 列出过会话的项目整目录被跳过，thincoder 的 `session/list`（短命连接）永不执行——设计 §7 A3 / 批次 T9「终端建会话 → 桌面同项目可见可续」在同时有 claude 会话的项目上不成立（接线 ⑤ 系照设计文本实现，非实现偏差）。
- 处置：回设计面——**设计修正轮 2**（按内核判定重写 §5.2-⑤ + §14/§7/体量立场同步）；实现（⑤ 修正 + ①⑥⑦⑧⑨ + 接线测试）由续篇派单承接。`refresh()` 面不扩（§14「终端新会话实时同步」缺口保持）。
- 环境备注：本机无 Flutter / Dart SDK（双人复核，已核）；本批实现暂不能跑 `analyze` / 测试——实现照做，报告如实标「验证未跑」，SDK 就位后补跑（待用户裁定 SDK 处置）。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成 2026-10-16（首版 + 修正轮 1（#1–#9 落地；#10 不改）+ 修正轮 2（⑤ 按内核判定）+ 修正轮 3（A 段表外披露归位）+ 修正轮 4（失效措辞对齐 + A 段披露裁定三项落地）+ 修正轮 5（C 段评审裁定：跨重连口径 / A1 断言 / 上界快照同步）+ 修正轮 6（走查现场缺陷：`session/prompt` 超时裁定——显式无超时 + 兜底口径））
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 设计落点与依据

- 设计档：`docs/design/thincoder-adapter.md`（首版，2026-10-16）；需求档：`docs/requirements/thincoder-adapter.md`（已确认）。
- 对照基准：需求档 §5 能力映射表；先例 = `lib/kernel/claude_code/`（完整适配）∥ `lib/kernel/codex/`（薄内核）。
- 机制设计正文在设计档 §3（传输 / JSON-RPC 连接 / ACP 线形 / 会话生命周期 / 事件翻译）与 §4（F1–F7、F10 逐项）；本段只留任务分解、受影响文件与验收对照，不重复机制。

### 本批条目（覆盖）

- 覆盖：F1 · F2 · F3 · F4 · F5 · F6 · F7 · F10 + E1 · E2 · E3 · E4 · E5（需求档 §3/§4）。
- 不在本批：F8（批 2）· F9（批 3）· A7 · A8（设计档 §13 只留接口面）；边界 B1–B4 全部沿用。

### 批 1 任务分解（可派工表）

| # | 目标 | 落地坐标 | 验收 | 测试 |
|---|---|---|---|---|
| T1 | 适配层骨架 + 注册表接入（E1/E2/F1） | 新增 `lib/kernel/thincoder/`（`thincoder_kernel.dart` · `thincoder_transport.dart` · `thincoder_process{,_io,_stub}.dart` · `thincoder_protocol.dart`）；接线 ① `lib/kernel/kernel_registry.dart:29` | `KernelRegistry.all.first.id == 'thincoder'`；新会话默认 thincoder、可切 claude（A1/A2） | 新 `test/kernel/thincoder_kernel_test.dart`；`flutter test` 全量不回退 |
| T2 | 进程 + JSON-RPC 连接层（E4） | `thincoder_process_io.dart`（起 `thincoder acp`、逐行解码、退出消息、注册表）· `thincoder_protocol.dart`（id 配对 / 通知分流 / 反向请求应答 / `-32601` 未知方法 / 留痕 `appEvent`） | 握手成功；未知通知忽略、未知反向方法回 `-32601`（设计档 T1/T22） | kernel_test：握手 + 未知面 + 传输退出 |
| T3 | 会话生命周期与续接（F2/F3） | `thincoder_kernel.dart`（设计档 §3.5：new / load（重放）/ resume（不重放）/ close；`LoadsHistory`；组合 id `thincoder_session_ref.dart`） | T2/T3/T4；`sessionId` 组合形；未发言会话不落槽文件 | kernel_test：new / load 重放 / resume / close |
| T4 | 事件翻译（F3/F10） | `thincoder_kernel.dart`（设计档 §3.6：文本/思考/工具卡（kind 表）/用量/模式/配置） | T2/T5/T14；工具卡进行中→完成/失败 | kernel_test：事件序列断言 |
| T5 | 取消与异常收尾（F3） | `session/cancel`；在飞回合以 `stopReason:'cancelled'` 收尾；进程死 → interrupted + error + health failed | T10/T23 | kernel_test：取消 + 杀进程 |
| T6 | 审批弹窗（F4） | 反向请求 → `ApprovalRequest`（三值映射 approve_once / approve_always / reject；dispose 回 cancelled） | T6–T9；不卡 UI | kernel_test：三选项 + 超时路径 |
| T7 | 模式 / 模型 / 思考选择（F5） | 三个选择面（configOptions 驱动 + set_mode / set_config_option 回包后显示）；起点只吃 `settings['mode']`（D11） | T11–T13；不乐观假报 | kernel_test：选择往返 |
| T8 | 图片替代（F6） | 接线 ② `lib/kernel/agent_kernel.dart`（新增 `AcceptsImageFiles`）+ ③ `lib/chat/chat_session.dart:439`；落盘 `<cwd>/.thincoder/tmp/` + 路径行 + 阈值 | T15/T16；命名与终端一致 | kernel_test：落盘/阈值 + 既有 claude 图片路径不回退 |
| T9 | 会话目录（F2） | `thincoder_catalog.dart`（短命连接 + 串行队列）· 接线 ⑤ `lib/workspace/workspace.dart:319` | T17/T18；A3（终端建的会话可见可续） | 新 `test/kernel/thincoder_catalog_test.dart` |
| T10 | 定位与引导（F7） | `thincoder_locator.dart`（`thincoder.path` + PATH 探测 + 版本下限 0.12.74 + 引导文案） | T19–T21；应用不崩 | kernel_test：定位/版本比较 |
| T11 | 设置项（F7） | 接线 ⑦ `lib/settings/pages/general_page.dart:357-376` + ⑧ `lib/settings/app_settings.dart:58/95/140`、`lib/main.dart:338`（`thincoderStatus`） | 设置里可填路径、显示找到与否与版本 | 设置页 widget 测试（照 claude 行先例） |
| T12 | 进程收尾（F7 稳定性） | 接线 ⑥ `lib/main.dart:122-124`/`:552-559`（reap/stop）+ ⑩ `lib/platform/data_dir.dart:86-87` 注释 | 崩溃/强退后无残留进程 | kernel_test/人工：杀主进程后重启无残留 |
| T13 | 存量默认内核迁移（F1） | 接线 ④ `lib/workspace/workspace.dart:1897-1899`、`:2024`（`_kernelChosen` 标记：用户选过才作数） | T24/T25；A1 | `test/workspace/` 新用例：空档案默认 thincoder；带标记尊重选择 |
| T14 | mock 对端 + 固件 + 测试（A9/E5） | `thincoder_mock.dart` + `test/fixtures/thincoder/*.ndjson` + `test/kernel/thincoder_fixtures_test.dart`；接线 ⑨ `lib/kernel/mock/mock_kernels.dart`（不进 `all`，D18） | A9：五路径覆盖；固件可离线跑 | 上述三档 + 全量 `flutter test` |
| T15 | 端到端走查（A3–A6） | 真机（装了 thincoder 的机器）按需求档 A3/A4/A5/A6 走一遍 | 走查通过（截图/记录） | 人工走查 + 可选 `-t e2e-thincoder` 冒烟 |

### 受影响文件与测试覆盖

- 新增（全列，`lib/kernel/thincoder/` 单点）：设计档 §5.1 —— kernel / protocol / transport / process（io·stub·包装）/ catalog / session_ref / locator / mock；测试 = `test/kernel/thincoder_kernel_test.dart`、`thincoder_catalog_test.dart`、`thincoder_fixtures_test.dart`、`test/fixtures/thincoder/`。
- 修改（最小接线点集，逐点理由 = 设计档 §5.2）：① `kernel_registry.dart:29`；② `agent_kernel.dart`（`AcceptsImageFiles`）；③ `chat_session.dart:439`；④ `workspace.dart:1897-1899`+`:2024`；⑤ `workspace.dart:319`；⑥ `main.dart:122-124`+`:552-559`；⑦ `general_page.dart:357-376`；⑧ `app_settings.dart:58/95/140`+`main.dart:338`；⑨ `mock_kernels.dart`；⑩ `data_dir.dart:86-87`（注释）。
- 零改动：`lib/kernel/claude_code/**`；`thincoder/**`（B1）。

### 验收对照（回指需求档 §7/§3/§4）

| 需求条目 | 实施方案（任务） | 验证方式 |
|---|---|---|
| F1 默认内核 | T1 + T13；注册表首位 + 存量档案迁移 | 断言注册表首位 id；空档案建 workspace 默认 thincoder；带"用户选过"标记的档案尊重选择 |
| F2 终端相通 | T3 + T9；`session/list` 直读槽 + load/resume/delete | 终端建会话 → 桌面开同项目可见可续；桌面建的终端可见（同槽库天然）；删除后再列消失 |
| F3 全链路 | T3/T4/T5/T7；prompt/流式/工具卡/取消/plan | 走查 + kernel_test 事件序列；取消回 `cancelled` |
| F4 审批 | T6；三值映射 + 不卡 UI | 三选项各验一次；面板不答时不阻塞（服务端 5 分钟按拒） |
| F5 模式与模型 | T7；回包驱动显示 | 模式切 plan/normal；模型/思考 set 后以回报显示 |
| F6 图片替代 | T8；落盘 + 路径行 | 图落 `<cwd>/.thincoder/tmp/`（命名同终端）、正文含路径、agent 可读 |
| F7 检测与引导 | T10 + T11 + T12 | PATH 无 → 安装引导；`-32000` → 登录引导（服务端原文）；版本低 → 警告不阻断 |
| F10 用量 | T4；`usage_update` → UsageReported | 上下文读数 = used/size；配置只读 |
| E1 适配层单点 | T1；`lib/kernel/thincoder/` 自持 | 其它模块零 import thincoder 细节 |
| E2 增量为限 | 接线点 ①–⑩ 登记（设计档 §5.2） | 逐点可独立辨认；上游合并按清单核对 |
| E3 能力协商驱动 | T7；选择面由握手/回包驱动 | thincoder 扩 `configOptions` 候选即在 UI 亮（零 UI 改动） |
| E4 前向兼容 | T2；未知通知忽略、未知方法 `-32601`、协商留痕 | T22 用案；`appEvent('thincoder', …)` 日志可查 |
| E5 维护面 | 设计档 §12（升级核对与适配说明）+ T14（mock + 固件） | 照 §12 清单可执行；固件离线回归可跑 |
| A9 测试 | T14 | 五路径覆盖；既有测试（含 claude 面）不回退 |
| A10 扩展性 | 设计档 §5 + §12 | 改动点清单在场；实现与 §5 映射表一致（抽查） |

（A7/A8 = 批 2/批 3，不在本批；本批只留接口面，见设计档 §13。）

### 关键决策（完整 = 设计档 §6）

- D1 每会话一进程（单 cwd 服务端语义）；D3 JSON-RPC 连接层独立档（claude 的 ControlChannel 语义不合）。
- D5 会话记录 id = `<cwd>|<slot>` 组合（槽号跨项目重复；宿主按 id 去重，裸槽号会丢会话）。
- D6 catalog 不做跨项目枚举（`projects()` 空表）+ 接线 ⑤ 逐项目列；被否：读 thincoder 内部布局 / 刷新时逐项目起进程。
- D7 图片：不声明 `AcceptsImages`，新增 `AcceptsImageFiles` + 落盘路径引用（F6 原文）。
- D9 模型候选 = 上报项（ACP 无清单）；不读 config.json、不直连 provider `/models`。
- D11 会话起点只吃 mode（宿主 settings 面是 Claude 形，喂模型名会指错）。
- D17 存量档案迁移：旧版单内核无选择器 ⇒ 档案里的 `kernel` 值非用户选择（接线 ④）。
- D18 mock 内核不进 `MockKernels.all`（`test/flutter_test_config.dart:39` 全量替换 ⇒ 会改所有既有测试的默认内核）。

### 上抛项

- 〔知会〕**模型候选现实**：ACP v1 不暴露模型清单（清单在 thincoder 进程内拉 `/models`）⇒ 批 1 候选 = 上报项（当前一项），机制全程接通（E3 钩子）。若要"全量模型列表"，需另定面（涉 B3 口径：桌面代拉需用用户 key）——请父侧留痕，本批按需求档 §5 的 ACP 口径落地。
- 〔知会〕**存量档案默认内核迁移**（接线 ④/D17）：判据 = 旧版单内核（`kernel_registry.dart:29` 原只有 claude）+ 选择器需 ≥2 内核（`chat_session.dart:309`）⇒ 档案里的 `kernel` 值不可能是用户选择。不迁移则老用户升级后默认仍是 claude，违背 F1/A1 口径。请评审确认此判。
- 〔知会〕**已知缺口 / 开放项**（判定条件 = 设计档 §14）：模型候选（同第一条）· 拒绝理由无通道 · 代理面不注入 · 子代理信号忽略 · 变更审查无增量 · 终端新会话的实时同步（靠重开项目/重启）。

**首版交付记录**：设计完成（2026-10-16；设计档 `docs/design/thincoder-adapter.md` 首版；上抛两条〔知会〕待评审）

### 修正轮 1（2026-10-16 · 评审 §3 发现 #1–#9 落地；#10 不改）

设计档 `docs/design/thincoder-adapter.md` 逐号修正（行号 = 修正后位置）：

- #1 → §5.2（`:291` 起）：净增改 `≤ N 行` 上界式（逐点）+「体量立场」三条（`chat_session.dart` / `workspace.dart` 拆缝候选 + 本批不动结构；`thincoder_kernel.dart` 拆缝候选 + 触发条件）。
- #2 → §3.4（`:132`）：补两层超时关系（传输层默认 60s `acp/transport.mjs:42`；按方法覆写——审批 5 分钟 `bridge.mjs:319`、`fs/*` 30 秒 `bridge.mjs:143`/`:152`）；T9 期望不变。
- #3 → §12-C（`:432`）：补「baocode 侧能力面变 ⇒ 同步需求档 §5」方向（`AcceptsImageFiles` 行需求档已落）。
- #4 → §8：增 T26（dispose-在飞审批 → 回 cancelled + 进程收尾）、T27（单回合合计 >30 MB → 超阈项弃、其余照发）。
- #5 → §7 A3 行（`:334`）+ §8 表后注（`:379`）：反向前提 = 桌面侧至少发出一条消息（槽文件落盘）后终端可见/可续。
- #6 → §3.5（`:148`）+ §14-9（`:459`）：fork 后无新槽号通道 ⇒ 记录 id 不刷新、以服务端语义为准；判定条件 + 验收观察点（A3 走查）。
- #7 → §14-10（`:460`）：能力位首版按需求档 §5 固定面声明、版本告警兜底；将来按回包位收敛（E3）。
- #8 → §8 T15（`:365`）：A5 走查在无句尾指令条件下（普通模型）测，结论回写 D7。
- #9 → §2.2（`:48`）：先例文档坐标——先例无设计档可引（`docs/design/`、`docs/requirements/`、`docs/batches/` 无对应档；形态只由实现与扁平功能档承载）。

自检：#1–#9 逐号落地；行宽 <300（全文最大 287 字符，为既有行，非本轮新增）；无修订式残留；需求档三处口径一致（§2.2 超时 / §5 `AcceptsImageFiles` 行 / F6 句）抽查通过。

### 修正轮 2（2026-10-16 · 实现期缺口：load 跳过判据跨内核合并）

- 缺口（已核 · 两条独立评审 + 父侧源码复核）：`load()` 的跳过判据是跨内核合并集（`workspace.dart:291-309`、`:314-320`）⇒ claude 列出过会话的项目整目录被跳过，thincoder 的 `session/list`（短命连接）永不执行——设计档 §7 A3 / 本表 T9「终端建会话 → 桌面同项目可见可续」在同时有 claude 会话的项目上不成立（接线 ⑤ 系照设计文本实现，非实现偏差）。
- 修法（设计档 §5.2-⑤ 重写 + 新增「接线点 ⑤ 细则」段）：跳过判据**按内核**——选 ⓐ（`covered: Map<KernelDescriptor, Set<String>>` 覆盖表 + `_listKept` 收内核子集参数，缺省全量；`_openProject`/`_listWhenReached` 语义不变）；被否 ⓑ（每个已知项目全量 `_listKept`）：claude 逐项目重复整读。守卫（`:322-326`）采纳 + 修正为**逐内核**（「本轮没有触发逐目录列出」才清理）；代价 = 未列目录时清理整体推迟（设计档 §14-11 登记；有界、非数据损坏）。
- T9/⑤ 坐标与上界变更：⑤ 坐标 `workspace.dart:319` → `:291-326`（回路与守卫）+ `:422-439`（`_listKept`）；净增上界 `≤3 行` → `≤14 行`；体量立场随涉（`workspace.dart` 仍「本批不动结构」）。
- 设计档落点（行号 = 修正后）：§5.2-⑤ 行（`:282`）· 「接线点 ⑤ 细则」（`:291-298`）· 净增上界（`:301`）· 体量立场（`:306`）· §7 A3（`:344`）· §14-11（`:471`）· §5.1 补 `test/workspace/preferred_kernel_test.dart` 登记（`:271`）· §12-B.1 合并核对行（`:436`）· 变更记录（`:479`）。
- 实现（⑤ 修正 + ①⑥⑦⑧⑨ + 接线测试）由续篇派单承接；`refresh()` 面不扩（设计档 §14-6 保持不动）。

### 修正轮 3（2026-10-16 · A 段表外披露登记归位：events 档补录 + kernel / locator 行 + 体量立场）

A 段（eng-coder #6）实现期表外披露（批次档 §5：表外两档 + 决策表 #1·#7），经父侧裁定「收下 + 逐项登记」落设计档 `docs/design/thincoder-adapter.md`（行号 = 修正后位置）：

- §5.1 补 `thincoder_events.dart` 行（`:254`）：§3.6 事件翻译（`ThincoderEvents` + `ThincoderSink`：`emit` / `nextSeq` / `emitInfoChanged`）；拆自 kernel，出处 = 体量立场触发条件已执行。
- §5.1 `thincoder_kernel.dart` 行（`:253`）改两档形态一句：公开面照旧 + §3.6 翻译经 `ThincoderSink` 拆到 events 档；`thincoder_locator.dart` 行（`:262`）补「另含 `ThincoderStatus{Found,Missing,Failed}` + `thincoderStatus()`（接线 ⑦⑧ 消费）」。
- 体量立场 kernel bullet（`:308`）更新：触发已执行（拆分前实测 1168 行 ⇒ 拆出 events，外部形态不变）；残余 818 行（2026-10-16 快照）；续拆裁定 = **不续拆**（同两个 >800 既有档）；下一缝候选 = 选择面段（`_Choice` / `_ModelSetting` + mode/model/effort）；触发 = 独立拆分批立项（或下次触碰该档时顺拆）。
- 行数快照（2026-10-16 实测，`lib/kernel/thincoder/`）：kernel 818 · events 413 · protocol 186 · transport 88 · process_io 208 · process_stub 16 · process 19 · catalog 131 · session_ref 28 · locator 222 · mock 540。
- 纯文档面：`lib/` 与 `thincoder/` 零改动；设计档变更记录补一行（`:481`）。

自检：四项逐项落位；行宽 <300；无修订式残留；需求档零改动。

### 修正轮 4（2026-10-16 · 失效措辞与体量立场口径对齐）

设计档 `docs/design/thincoder-adapter.md` 逐处修正（行号 = 修正后位置；本轮起因 = 修正轮 3 的范围外发现 ②：§2.2 偏离 ③ 与 D2 旧措辞与已裁定事实不同步）：

- §2.2 偏离 ③（`:45`）：原「不拆独立 translator 档…超过 ~800 行再拆」（失效承诺）⇒ 改已执行口径——翻译档已按体量触发拆出 `thincoder_events.dart`；翻译随内核起步（先例 codex 内联），kernel 实测 1168 行越过 >800 行硬顶（体量立场 = §5.2 末段）。
- D2（`:317`）：同口径改写——拆分已执行；残余 818 行不续拆（触发与裁定出处 = 体量立场 §5.2 末段）。
- §12-4（`:429`）：同类失效引用——翻译指针「`thincoder_kernel.dart` 的翻译」⇒ `thincoder_events.dart`（拆分后 §3.6 翻译全在 events 档；`thincoder_events.dart:68` 的 `sessionUpdate` 分支，kernel 内零翻译代码，grep 复核）。
- 全档失效承诺扫描（`拆` / `~800` / `translator` 全档 grep）：除上述两处与 §12-4，无其它残留（`:306`/`:307` 的「本批不动结构」= 存量两档的现行裁定，非失效承诺）。
- 编号引用自查：设计档内无「§7 体量立场」式误引（体量立场实际位置 = §5.2 末段，`:304` 起；档内「§5.2 体量立场」引用 = 变更记录，口径正确）。批次档 §5（`:246`）仍带「设计档 §7 体量立场」误引 + 引文为修正轮 3 前旧文——§5 非本段，报告父侧处置。
- 设计档变更记录补一行（`:482`）；纯文档面：`lib/` 与 `thincoder/` 零改动；需求档零改动。

自检：逐处落位（读回核对）；行宽 <300（全档无 >300 行）；无修订式残留（失效承诺直接删除，非划线留存）。

### 修正轮 4 · 追加三项（2026-10-16 · A 段交付披露的父侧裁定落地：口径 / 登记级，不动实现）

- ① `session/close` best effort：口径 = 只写不等、随即进程退出（不设有界等待）；认领是否真释放不在此保证——落 §3.5 新 bullet（`:149`）+ 登记 §14-12（`:475`；判定条件 = 真机走查确认会话确已释放）。
- ② 「会话已不在」续接记录一路无兜底：处置定死（按一致性选「同兜底」）= `session/load` / `session/resume` 收 `-32602`（`gone`）⇒ 忘槽、起新会话（不留启动死结）——落 §3.5 新 bullet（`:150`）+ 登记 §14-13（`:476`；判定条件 = 终端删会话后、桌面打开该记录 ⇒ 起新会话、可发消息，不再永久启动失败）。被否：「保持失败直到用户另开」（同一情形两路处置不一，且留永久失败面）。实现随后续单。
- ③ 固件基准口径：初版固件 = 按服务端源码线形手工录制（非真进程录音）；真机重录执行点 = T15 端到端走查（重录后同步 README 措辞）——落 §12-7（`:434`）。
- 设计档变更记录补追加一行（`:487`）。
- 行号校正（本轮末快照）：本轮追加使设计档行号下移——本节早前块所引 D2 = `:319`、§12-4 = `:431`、变更记录轮 4 首行 = `:486`、体量立场 = `:306` 起（两 bullet = `:308` / `:309`）；批次档 §5 的「设计档 §7 体量立场」误引按内容定位（早前块所引 `:246` 随追加移位、不可靠）。纯文档面：`lib/` 与 `thincoder/` 零改动；需求档零改动。

自检：三项逐落位（读回核对）；行宽 <300；§14 新增 = 末两行（编号 12 / 13，既有引用不动）；无修订式残留。

### 修正轮 5（2026-10-16 · C 段代码评审三项裁定落地：跨重连口径 / A1 断言 / 上界快照 + 文案口径）

设计档 `docs/design/thincoder-adapter.md` 逐项修正（行号 = 修正后位置）：

- ① 跨重连口径（裁定 1）→ §3.5 新 bullet（`:151`）+ §14-13（`:477`）：兜底起的新会话在同一运行内跨 `release()` → `prepare()` 续接——记「记录槽已忘」标记，此后走保留槽路线（`session/resume`，不再重走 `session/load` 死槽）；判定条件更新（含重连腿）；实现随后续单（约 8 行）。
- ② A1 断言口径（裁定 2）→ §7 A1 行（`:346`）：断言改「描述符身份（`KernelRegistry.thincoder.id == 'thincoder'`）+ `MockKernels.thincoder ∉ MockKernels.all`」；首位事实由代码核（`kernel_registry.dart:40`，本轮读核）——`test/flutter_test_config.dart:39` 把全量测试的注册表整体替换 ⇒ `all.first` 断言写不出。
- ③ 上界快照同步 → §5.2 净增上界（`:305`）：① ≤10 → ≤11（成分含 2 条 import）· ⑦ ≤80 → ≤81（新行 widget）；其余不动。
- ④ 文案口径（裁定 3）→ §14 新增行 14（`:478`）：英文占位接受（本机无 `flutter gen-l10n`、生成档不可手改）；补齐窗口 = SDK 就位轮（补 arb 键 + 生成档重产 + 设置行改用 `context.l10n`）。
- 变更记录补一行（`:490`）。纯文档面：`lib/`、`test/**`、`thincoder/` 零改动；需求档零改动。

范围说明（未落项）：上抛项 3 的另一条事实「状态未就绪时无『检查中』占位」不在裁定 3 文面内 ⇒ 本轮未动（留父侧裁定）。

自检：四项逐项落位（读回核对）；行宽 <300（全文最大 294，为既有行）；无修订式残留；需求档零改动。

### 修正轮 6（2026-10-16 · 走查现场缺陷：`session/prompt` 误走连接缺省 60s ⇒ 长回合误报「no answer」+ 误标 interrupted）

本轮为补派；先核「裁定是否已在档内」：§3.4 该旁注现仅服务端反向请求超时、变更记录止于轮 5 ⇒ 裁定未落，本轮落全量。设计档 `docs/design/thincoder-adapter.md` 落一条裁定（行号 = 修正后位置）：

- 缺口（坐标 = 派单给定）：`thincoder_kernel.dart:462` 的 `session/prompt` 未传超时 ⇒ 走连接缺省 60s（`thincoder_protocol.dart:61`）；prompt 响应在回合结束才到达（`bridge.mjs:23-24`：resolve `{stopReason:'end_turn'}`）⇒ 真回合超 60s 触发 `done.future.timeout`（`thincoder_protocol.dart:98-104`），误报 `session/prompt got no answer`、回合被标 interrupted（agent 仍在工作）。
- 裁定 → §3.4 我方请求超时口径旁注两行（`:134-135`）：`session/prompt` **不受连接缺省 60s 约束**、显式不设超时（`ThincoderConnection.request` 区分「缺省（60s）」与「显式不设超时」），其余请求照旧；回合时长无上界。兜底 = `session/cancel`（服务端 `stopReason:'cancelled'` 收束在飞请求，F3）+ 进程/连接健康（进程死 / 传输结束 ⇒ 在飞请求随连接收束、回合 `TurnEnded(interrupted: true)`，§3.6）。被否「远大于回合尺度的上界」：只为悬挂态加猜测性截断，而两条兜底已给确定性出口。
- 变更记录补一行（`:494`）；实现修随后续单。纯文档面：`lib/` 零改动；需求档零改动；§3.5 / §14 等其它章节未动（同槽并发口径保持）。

自检：裁定落位（读回核对 L134/L135/L494）；新行单行 <300（实测 233 / 208 / 179，全档无 >300 行）；无修订式残留（D8，新行零划线）；需求档零改动。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | 体量/结构（criterion 8） | 🟡 | §5.2 给了各修改档行数与净增（`docs/design/thincoder-adapter.md:288`、`:289`），但 `chat_session.dart` 1085 与 `workspace.dart` 2770 已处 >800 行硬顶之上（`:288`），本档未携拆分计划或债务登记；新增 `thincoder_kernel.dart` 估 ~700 行（`:251`）落在 >500 主动拆分审阅带，现有立场只有"超过 ~800 行再拆"（`:45`），未给拆缝；净增以 `~N 行` 估计成形（`:289`），非 `≤±N` 上界。 | §5.2 末尾补三点：① 两个 >800 既有档各一行拆分计划（或显式"本批不动结构、债务登记"）；② ~700 行新档的主动拆分审阅结论（拆缝候选 + 触发条件）；③ 净增改写 `≤±N` 上界式，便于机械核对。 |
| 2 | 跨档一致性（R1/R7a） | 🟡 | 同一机制（服务端反向请求超时）两档数值不一：需求档 `docs/requirements/thincoder-adapter.md:50` 写"反向 RPC 有 60s 超时兜底"，设计档 `docs/design/thincoder-adapter.md:130` 写"服务端反向请求自带超时：审批 5 分钟、`fs/*` 30 秒"，T9 期望取后者（`:351` "服务端 5 分钟后按拒绝"）。可解释为传输层默认 vs 按方法覆写两层，但无一句点明层次；thincoder 源码不在评审范围，两处源码引用未核。 | 两档核对后统一口径：或把需求档 60s 标注为"传输层默认、按方法覆写"，或把设计档数字改为与源码一致的最终值；设计档加一句两层关系说明，T9 期望随最终值。 |
| 3 | 文档归属/维护点（criterion 7 · E5） | 🟡 | 设计新增宿主能力面 `AcceptsImageFiles`（`docs/design/thincoder-adapter.md:224`、接线点 ② `:276`），但需求档声明为"单一维护点"的 §5 能力映射表（`docs/requirements/thincoder-adapter.md:92`）无对应行；原表"图片 `AcceptsImages`"❌ 行（`:108`）配注释"❌ = 内核不声明该能力，UI 按既有机制自动隐藏（不是缺陷）"（`:117`），与 F6"粘贴图片落 `<cwd>/.thincoder/tmp/`（命名规则与终端一致）"（`:69`）在 UI 显隐上互相拉扯——新增一面是兼容两者的唯一解，但该裁决未登记回映射表；设计 §12 步骤 8（`:410`）只覆盖"thincoder 补能力"方向。 | 在 §5.2 或 §12 登记一行"需求档 §5 需增 `AcceptsImageFiles` 行（对位 F6 替代流；`AcceptsImages` 仍 ❌）"，并补 §12 的"baocode 侧能力面变更 ⇒ 同步 §5"方向。 |
| 4 | 验收覆盖（criterion 5） | 🟡 | §8 用例表未覆盖两处已定行为：F4"内核被 `dispose` 而审批在飞 ⇒ 回 `{outcome:{outcome:'cancelled'}}`"（`:210`）；F6"单项 ≤ 15 MB、单回合合计 ≤ 30 MB"（`:226`）的合计腿——T16 只覆盖单项（`:358` ">15 MB 单图"）。 | §8 增两行用例：① dispose-在飞审批 → 断言回 cancelled 且进程收尾；② 单回合合计 >30 MB → 断言超阈项弃、其余照发。 |
| 5 | 验收可验性（criterion 5） | 🟡 | A3 反向腿（需求档 `:131` "桌面建的会话在终端（同 cwd）可见、可继续"）在设计 §7 以"反向天然成立（同一槽库）"（`:326`）结案，但同档 `:144` 写明"未发过消息的会话**不落槽文件**" ⇒ 未发过消息的桌面会话不会出现在终端 `session/list`；按字面走查（新开桌面会话即去终端查）会得假失败。 | §7 A3 行与 §8 走查说明补一句前提：桌面侧至少发出过一条消息（槽文件落盘）后，终端可见/可续。 |
| 6 | 清晰性/边界（criterion 4） | 🟡 | 同槽并发只说"服务端按设计处理（空闲钉回 / 占用 fork 到新槽，`handlers-slots.mjs:104-126`）——桌面侧零特判"（`:146`），未交代 fork 后新槽号如何回流：§3.4 的 `session/load`/`session/resume` 结果面只有 `{configOptions}`（`:99`、`:100`），getter 固定为组合 id（`:145`）——若 fork 真发生，后续 prompt/cancel/delete 与目录 id 可能指向旧槽。 | §3.5 或 §14 补一位：fork 后以哪一来源刷新记录 id（如通知 `sessionId`），或写明"以服务端语义为准"的判定条件与验收观察点。 |
| 7 | E3 一致性 | 🔵 | "依据 `initialize` 回包"只落在三个选择面（`:215`）；能力位（`LoadsHistory`、`StartsPlans`、`AcceptsImages`）仍是适配层常量（`:193`、`:201`、`:224`）。旧版 `agentCapabilities.loadSession=false` 时仍声明历史载入；需求档 §5 为固定首版判定（✅），故非缺口，但判定条件未登记。 | 登记一句：首版按需求档 §5 固定面声明、版本告警兜底；将来按回包位收敛（E3）。 |
| 8 | F6/A5 可验性 | 🔵 | D7 决定不复刻终端句尾指令（`:228` "（桌面不知模型是否多模态，该指令属 thincoder 自己的提示面）"），理由成立；但 A5"agent 能读到该文件"（需求档 `:133`）的可验性取决于"仅给路径行时 agent 仍会读图"。 | A5 走查/T15 备注显式覆盖"无该指令"条件（如用普通模型走一遍），结论回写 D7。 |
| 9 | 先例对照（criterion 9） | 🔵 | §2.2 给了先例实现坐标与对齐/偏离理由（`:29`、`:35-46`），但未见"对应设计档章节 ∥ 先例批次"两个坐标位；本评审上下文无文档地图，无法判断先例是否有可引设计档章节。 | 补一行先例的文档坐标（claude 适配/薄内核落档位置与批界）；若确无，写明"先例无设计档可引"。 |
| 10 | 方法论/归属（维度降级） | 🔵 | 上下文无 AGENTS.md、无项目规范档、无文档地图（`docs/` 下 `design/`、`requirements/`、`batches/` 与扁平档并存，但范围内无地图可核）⇒ 方法论与文档归属按降级口径判：设计档与需求档成对互指（`docs/design/thincoder-adapter.md:4`）、档头含状态/范围/分批，未发现分片或重复描述。 | 若有文档地图/规范档，补进后续评审上下文；本项无阻断内容。 |

范围外备注（无严重度）：仓根可见 `PROJECT-MANIFEST.json` 与 `CLAUDE.md`（不在评审范围，未读）；若二者之一即文档地图/规范档，值得核一次。设计档自标"行号 = 编制日快照"，其源码行数（`docs/design/thincoder-adapter.md:288`）本评审未越范围逐档点核（未核）。

计数：🔴 0 · 🟡 6 · 🔵 4

VERDICT: pass

## §4 用户批准（主 agent）

### 用户批准（2026-10-16）

- 批准对象 = 需求档 `docs/requirements/thincoder-adapter.md` + 设计档 `docs/design/thincoder-adapter.md`（首版 + 修正轮 1），作为批 1 实现依据。
- 批准范围含两处随批接受的现实：① 模型候选 = thincoder 上报项（ACP v1 无清单；E3 钩子已留）；② 存量档案默认内核迁移判（主 agent 已核实同意：`lib/workspace/workspace.dart:1897-1899`/`:2024`/`:2194-2196` 佐证"旧档 `kernel` 值非用户选择"）。
- 下一步：实现（eng-coder），批 1 = 适配层单点 + 接线点 ①–⑩ + 测试。

## §5 实施记录（eng-coder）
**状态行**：实施完成（A/B/C 段 + 末修单 + 走查缺陷修复（session/prompt 显式不设超时）已落 · 本单三档 analyze 0 issue · thincoder_kernel_test 全绿（33 项；MSVC 已在，上一轮梗阻解除））



### 实施记录 · B 段（接线点 ②③④⑤⑩ + 宿主侧用例）（2026-10-16）

**范围与授权**（父侧裁定）：只做不依赖 A 段适配层的独立子面；①⑥⑦⑧⑨ 与设置页 thincoder 行用例留续篇派单，**不计本段未完成项**。A 段（`lib/kernel/thincoder/`）由重派单 #6 独立落地，本段零触碰。

**交付物与净增**（`git diff --numstat` 实测；净增 = 新增 − 删除；上界 = 设计档 §5.2）：

| 点 | 坐标（现状行号） | 改了什么 | 净增（上界） |
|---|---|---|---|
| ② | `lib/kernel/agent_kernel.dart:263-267` | 新增 `AcceptsImageFiles` 接口（4 行文档 + 声明） | +6（≤12） |
| ③ | `lib/chat/chat_session.dart:439-442` | `acceptsImages` 加 `\|\| _kernel is AcceptsImageFiles` + 两行 doc（两种机制） | +3（≤4） |
| ④ | `lib/workspace/workspace.dart:1042-1043`（注释）· `:1047-1049`（字段）· `:1904-1910`（`_restore`）· `:2035`（`_save`）· `:2207`（`_sync`） | `_kernelChosen` 标记：字段 / 档案 `kernel` 仅在选过时采纳 / 只写 `true` / 用户选择处置真；`preferredKernel` 注释同步为"选过的那份，或在售首位" | +10（≤10） |
| ⑤ | `lib/workspace/workspace.dart:314-321` + `:322-326` | `_folders` 本地目录也走 `_listKept`；`_forgetGone` 守卫改"未列即待列"（见决策表） | +2（≤3） |
| ⑩ | `lib/platform/data_dir.dart:86` | 注册表清单加 `thincoder` | 0（≤2） |
| — | `test/workspace/preferred_kernel_test.dart`（新，89 行） | 四条用例：默认＝列表首位且不写选择标记 / 用户选择跨运行生效 / 无标记旧档不跟随 / 选择的内核已不在候选内回落首位 | — |

**决策透明表**：

| # | 决定 | 依据 | 代价/风险 |
|---|---|---|---|
| 1 | ⑤ 连带改 `_forgetGone` 守卫：`!_folders.any(RemoteLocation.isRemote)` → `!_folders.any((folder) => !listed.contains(folder))` | 不改则 `_listKept` 异步列出的项目会话，其 pinned/archived/names/drafts/IDE 标签会被 `_forgetGone`（`:1690-1737`）当"已消失"清掉并落盘＝数据受损 | 存在"未被 catalog 列入的目录"时 `_forgetGone` 卫生清理整体推迟（有界、非数据损坏）；对纯 claude 老用户也是可见的行为变化 ⇒ 建议父侧登记技术待办 |
| 2 | ④ 的恢复判据用 if-case 守卫（`case final kernel? when _kernelChosen`）而非改条件式 | 无 Flutter/Dart SDK ⇒ 不能跑 `dart format`；此形态保持原行形态（零格式风险） | 无 |
| 3 | 测试以 `MockKernels.codex` + `claudeCode` 作替身，不引 thincoder 描述符 | ⑨ `MockKernels.thincoder` 属 A 依赖面（父侧裁定） | A1 的 thincoder 身份断言（`KernelRegistry.all.first.id == 'thincoder'`）留续篇 |
| 4 | 测试落点＝同目录新档 `test/workspace/preferred_kernel_test.dart` | 断言面（内核选择的持久化）与 `project_workspace_test.dart`（多文件夹工作区）不同题；任务书允许"同目录就近新档" | 设计档 §5.1「新增（全列）」未含此档＝文档漂移，请设计侧/父侧登记 |

**审计与代码评审轮次与终态**：

- 内部分歧审计（explore，1 轮）：0 阻断 / 0 应修 / 4 建议。表外改动：无（反查全仓 `thincoder` 字样，lib/ 下仅本段三处 + `data_dir.dart:86`）；注释与代码核对 4 处相符、1 处失准（`preferredKernel` 注释，已修）。
- 独立代码评审（advisor，type=code，1 轮）：**VERDICT changes-required**。发现：🔴 1（⑤ 的跳过判据跨内核合并，详见下「待裁项」）· 🟡 1（批次档 §1 状态行与 A 段落盘滞后：报告不改，父侧落笔时更新）· 🔵 3（测试 `addTearDown` / 补"选择的内核已不在候选内"用例 / `acceptsImages` 补 doc 行）。
- **fix round 1**：① `preferredKernel` 注释改"用户选的那份，或在售首位"（`:1042-1043`）；② 测试三处 `dispose()` 改 `addTearDown`（保留第二例中模拟重启的 `first.dispose()`）；③ 补第四用例（选择的内核已不在候选内 ⇒ 回落首位）；④ `acceptsImages` 补两行 doc 指向 `AcceptsImages` / `AcceptsImageFiles`。
- **终态**：`stalled` —— 唯一未闭项 = 🔴 一处（父侧已收，裁定**不在本段修**：走设计面 §14 登记 + 续篇派单/修正轮）；其余 clean（无静默简化、无表外改动、无未申报偏离）。

**待裁项（父侧已收 · 裁定不在本段修）**：⑤ 的跳过判据 `if (listed.contains(folder)) continue;`（`workspace.dart:315`）用的是**跨内核合并集**（`:292-309`）。Claude 的 catalog 列出本机所有有会话的项目（`claude_storage_io.dart:37-38` → `packages/bao_remote/lib/src/claude/claude_sessions.dart:119` 扫 `~/.claude/projects`），thincoder 的 `projects()` 恒为空表（`thincoder_catalog.dart:36`，D6）⇒ 项目只要在 claude 侧有会话就整目录被跳过，thincoder 的 `sessionsIn`（宿主唯一调用点 = `workspace.dart:427`）永不执行；`_forgetGone` 还会把该目录从 `_folders` 剔除（`:1695`），`_openProject` 仅对未知项目列（`:399`/`:415`），`refresh()` 只读 catalog（`:354`）⇒ 无补救路径。结果 = 设计档 §7 A3 / 批次档 T9「终端建会话 → 桌面同项目可见可续」在**有 claude 会话的项目**（= D17/F1 迁移目标人群的多数项目）不成立。代码与设计档 §5.2-⑤ 措辞逐字一致（属"验收未满足"，非实现偏差）；修法（按内核记账 + `_listKept` 收内核集，或迭代面改 `_projects`）超本段授权与 ⑤ 的 ≤3 行上界 ⇒ 父代理裁定不在本段修，由设计面处置。

**验证**：**验证未跑** —— 本机无 Flutter/Dart SDK（背景已复核裁定；未找 SDK、未装任何东西）。待跑命令：`flutter analyze` · `flutter test test/workspace/preferred_kernel_test.dart` · `flutter test`（全量；重点 `test/workspace/`、`test/kernel/`、`test/settings/`、与该面相关的 chat/composer 档）。**未**真跑 `thincoder acp` 会话（会写用户 `~/.thincoder` 槽库、耗额度，父侧明令禁止）。

**不在本段（留续篇/父侧）**：接线点 ①⑥⑦⑧⑨ 与设置页 thincoder 行用例 · 真机走查（T15 / A3–A6）· 可选 `-t e2e-thincoder` 冒烟标签 · A1 的 `KernelRegistry.all.first.id == 'thincoder'` 断言（受 `test/flutter_test_config.dart:39` 全局替换所限，需代码级核对兜底）。

### 实施记录 · A 段（适配层单点 `lib/kernel/thincoder/` + 测试与固件）（2026-10-16）

**范围与授权**：本段 = §2 任务书的 A 段（适配层单点 + 三个测试档 + 固件）。**零触碰任何既有档**：`git status` 里本段只新增 `lib/kernel/thincoder/**`、`test/kernel/thincoder_*.dart`、`test/fixtures/thincoder/**`；四个 `M` 档（`chat_session.dart` / `agent_kernel.dart` / `data_dir.dart` / `workspace.dart`）= B 段 ②③④⑤⑩。接线点 ①⑥⑦⑧⑨ 不在本段（B 段留续篇派单，父侧裁定）。

**交付物与行数**（实测 = 文件总行数；预估 = 设计档 §5.1）：

| 档 | 行数 | §5.1 预估 | 装什么 |
|---|---|---|---|
| `thincoder_kernel.dart` | 807 | ~700 | 生命周期 + 审批 + 选择面 + 图片落盘路径 + 通知入口 |
| `thincoder_events.dart` | 410 | —（表外，见下） | §3.6 事件翻译（拆分产出） |
| `thincoder_protocol.dart` | 185 | ~250 | JSON-RPC 配对 / 三向分流 / 反向请求 / `-32601` / `failAll` |
| `thincoder_transport.dart` | 87 | ~60 | `ThincoderTransport` + `ThincoderLaunch` + 退出消息 + `ThincoderUnavailable` |
| `thincoder_process_io.dart` | 207 | ~150 | 起 `thincoder acp` / 逐行解码 / stderr 尾巴 / 注册表 / `stopAll` |
| `thincoder_process_stub.dart` | 15 | ~15 | web：明示无进程 |
| `thincoder_process.dart` | 18 | ~25 | 条件导入包装 + 三个接线用函数 |
| `thincoder_catalog.dart` | 130 | ~150 | 短命连接 + 串行队列 + list/delete |
| `thincoder_session_ref.dart` | 27 | ~30 | 组合 id 组合/拆解 |
| `thincoder_locator.dart` | 221 | ~120 | `thincoder.path` + PATH 探测 + 版本比较 + 引导常量 + 设置行状态 |
| `thincoder_mock.dart` | 528 | ~350 | 脚本化 ACP 对端 + 固件回放入口 |
| 合计 | 2645 | ~1850 | |

测试与固件：`test/kernel/thincoder_kernel_test.dart` 827 · `thincoder_catalog_test.dart` 162 · `thincoder_fixtures_test.dart` 178；固件 `test/fixtures/thincoder/` 10 个场景（handshake / turn-stream / tools / approval / unknown / load-replay / cancel / process-death / auth-required / old-version）+ `README.md`（录法）。

**表外新增两档（如实披露，均有设计档出处）**：

- `thincoder_events.dart`（+410）：设计档 §5.2 末段体量立场的触发条件（当时文本） =「实测 >800 行（或翻译段 >250 行）⇒ 拆出 `thincoder_events.dart`，外部形态不变」。两个触发都命中（拆分前 kernel 1168 行）⇒ 按设计拆出。外部形态未变：`ThincoderKernel` 公开面照旧，翻译侧新开 `ThincoderSink`（`emit` / `nextSeq` / `emitInfoChanged`，内核用既有 `KernelEventSource` 即可满足）。**拆分后 kernel 仍 807 行**（超 ~800 指导线 7 行；非注释代码行 653），下一条缝 = 选择面段（`_Choice` / `_ModelSetting` + mode/model/effort）——披露，请父侧裁是否续拆。
- `test/fixtures/thincoder/README.md`：设计档 §12-7 要求「录法写在该目录的 README 一行」。

**决策透明表**：

| # | 决定 | 依据 | 代价/风险 |
|---|---|---|---|
| 1 | 拆分形态 = `ThincoderSink` 接口 + `ThincoderEvents` 类 | 设计只点了文件名与「外部形态不变」；形态由实施定 | 多一个公开类型；kernel 仍在 800 线上 |
| 2 | 模式显示取最近一次模式回报（`current_mode_update` / 会话回包的 `mode.currentValue`），**不**读选择面里的 `configOptions` 现值 | `session/set_mode` 回包只有 `{}` + 通知（设计 §3.4 表），configOptions 不随之刷新 ⇒ 读它会停在旧值 | 无（两条来源都汇进同一个 `mode` 字段） |
| 3 | 未知 `sessionUpdate` = 忽略，且**不改动对话状态**（不封口正在流式的项） | 设计 §3.6 原文「忽略」；封口会让未知变体切断正在流的文本 | 若将来新变体本应续写，会多一段/少一段（E4 兜底，留痕 `appEvent`） |
| 4 | 审批超时（T9）= 服务端自己五分钟后按拒绝；**适配层不设客户端超时** | 设计 §3.4 两层超时（审批 5 分钟在服务端侧） | 服务端若不超时，交互项挂到回合结束由 `_endTurn` 收口（面板不答不阻塞回合） |
| 5 | `release()` 在回合进行中延迟到回合结束再收 | 照 claude 内核先例（不中途截断在飞工作） | 无 |
| 6 | `session/list` 缺 `updatedAt` ⇒ epoch 0 | 设计未定；槽文件可能没时间 | 时间列显示 1970 那类值 |
| 7 | locator 额外给 `ThincoderStatus{Found,Missing,Failed}` + `thincoderStatus()` | 接线 ⑦⑧ 的设置行要「找到与否 + 版本」，照 `localClaudeStatus()` 形；设计 §5.1 只列了探测/比较/文案 | 表外 API（无既有档改动），供 B 段续篇消费 |
| 8 | 固件行格式（`server` / `client` / `turn` / `answer` / `cancel` / `expect`）自行定形 | 设计只要求「帧序列 + 期望客户端动作清单 + 离线可跑」；`client` 行 = 逐条对照内核真写出的帧（id 也照抄） | 格式是新的（无先例），已在目录 README 写清 |
| 9 | mock 的 load 重放用 `t7`，避开与在飞工具卡同 id | 只是 mock 的取样 | 范围外观察（见下） |
| 10 | 图片：阈值 15 MB / 30 MB、命名 `paste-<runId>-<i>.<ext>`、正文行 `[Attached images: p1 \| p2]`、`runId` = `Date.now().toString(36)` + 4 位随机 base36、**不**复制终端句尾 `read_image` 指令 | 设计 F6/D7 原文，与 `attachments.mjs` / `setup-reminders.mjs:255` 逐字对齐 | 无 |

**范围外观察（不阻断，登记备用）**：真服务端 `session/load` 的重放序列与在飞桥各自从 `t1` 起编号（`handlers-slots.mjs` 的重放 vs `bridge.mjs` 的在飞），同一会话内 load 之后的首个在飞工具卡可能与重放卡同 id（transcript 按 id 替换 ⇒ 视觉上替换掉一张重放卡）。按设计「`toolCallId` 作项 id」落地，未加前缀；若要规避，须另定 id 面（届时与设计面一起改）。

**验证**：**验证未跑**（同 B 段：本机无 Flutter/Dart SDK；未找 SDK、未装任何东西、未真跑 `thincoder acp`——会写用户 `~/.thincoder` 槽库并耗额度，父侧明令禁止）。待跑命令：`flutter analyze` · `flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_catalog_test.dart test/kernel/thincoder_fixtures_test.dart` · 全量 `flutter test`（重点 `test/kernel/`、`test/chat/`、`test/workspace/`）。**因此三个测试档的红绿与固件回放均未实测**；固件是**按服务端源码线形手工录制**（非真进程录音），升级核对时以真机重录为准（§12-7）。

**不在本段**：接线 ①⑥⑦⑧⑨ 与设置页 thincoder 行用例（B 段续篇）· 真机走查（T15 / A3–A6，含 A5「无句尾指令下 agent 仍读到文件」的结论回写 D7）· 可选 `-t e2e-thincoder` 冒烟标签 · A1 的注册表首位断言（⑨ 未落）。

### A 段 · 审计与代码评审轮次与终态（2026-10-16；接上一条 A 段记录）

**内部分歧审计（explore，1 轮，只读）**：5 条发现（0 阻断 / 3 应修 / 2 备注）+ 2 条覆盖备注；表外改动 0（机械并集 = `lib/kernel/thincoder/**` + `test/kernel/thincoder_*.dart` + `test/fixtures/thincoder/**`）。逐条处置（全部已修）：

| # | 发现 | 处置 |
|---|---|---|
| 1 | `optionsFrom` 走模式支路即 `return` ⇒ 模型/思考变更不发 `KernelInfoChanged`，宿主缓存的选择项不刷新（T12/T13 用户可见失效） | `reportMode` 改为返回「是否移动」，`config_option_update` 与 `current_mode_update` 两条来源统一发 `emitInfoChanged` |
| 2 | kernel 测试「面板不答」第二回合无人应答审批 ⇒ 断言必红 | 第二回合改为「答一次审批，再看两个 TurnEnded」 |
| 3 | catalog 删除用例三处错（注释与实现不符 / 复用已关闭的 mock ⇒ 60 s 挂 / 断言不可达） | mock 按真服务端对未知槽回 `-32602`（`handlers-slots.mjs:149/209`）；用例改「一新连接一看」+ `-32602` 吞掉路径单列 |
| 4 | 设计 §5.1 清单未含 `thincoder_events.dart`（🔵） | 父侧裁定：设计侧登记，不计本段留项 |
| 5 | `release()` 落在「起进程途中」时 `_releaseWanted` 无消费者 ⇒ 进程起来后无人收 | `_launch` 收尾兜底（`_releaseWanted && _turn == null` ⇒ close + teardown + idle） |
| 备注 | T19 内核级腿（起进程失败 ⇒ health failed + 引导文案）无用例 | 补用例（`ThincoderUnavailable` 起失败 ⇒ failed + 安装引导 + 发消息不崩 + 回合收尾） |

**独立代码评审（advisor，type=code，1 轮）**：**VERDICT changes-required** —— 1 阻断 / 2 应修（可选）/ 2 备注。

- 🔴 #1 **重连丢会话**：`release()` 后 `prepare()` 走 `session/new` 另起会话（`_slot` 只写不读），而设计 §3.5`:141`「槽号留在内存以备 resume」+ T4`:365`「release 后再 prepare → `session/resume`」+ 先例（`claude_code_kernel.dart:428` / `claude_code_transport.dart:251`）都要求续接 ⇒ 桌面自建会话每次 detach→attach 静默失忆、槽文件堆积。**fix round 1**：`_openSession` 拆三路（记录 `_openRecord` / 自己的会话 `_pickUpKept` / 新会话 `_openNew`）；自建会话重连走 `session/resume`，槽已被终端删（`-32602` ⇒ 新增 `ThincoderRpcError.gone`）则忘掉槽号改起新会话（不留启动死结）；补两条用例（自建会话 release→prepare 续接不重放 / 槽已删则新起且 health ready）。
- 🟡 #2（可选）`session/close` 只写不等、同拍杀进程 ⇒ best-effort 的 close 可能未被处理 → **不修（披露）**：加「有界等待」会引入此处无法实测的时序依赖；残余（认领是否真释放）交真机走查 + 设计侧登记（§14-9 旁）。
- 🟡 #3（可选）固件为源码线形手写（非真进程录音），README 措辞把 §12-7 的录制要求降级 → **不修（披露）**：重录需真机与真实会话（父侧明令禁跑），交 T15 走查时按 §12-7 重录并同步 README 那一行。
- 🔵 #4 审批缺 `approve_always` 时整体拒且无痕 → 已补 `appEvent` 留痕（拒绝方向保留：D19 固定三值，答一个服务端不认的 `optionId` 更糟）。
- 🔵 #5 设计 §5.1 清单/行数滞后 → 设计侧已登记（`:253-254` 含 events 行；`:308` 体量立场记「拆分已执行 + 不续拆」）。

**独立代码评审（advisor，type=code，第 2 轮 = 修复核验）**：**VERDICT pass** —— 🔴 0；上一轮 5 条逐一核验为 Fixed/Accepted；新增两条 🔵（非阻断，交父侧/设计侧）：

- 🔵 新 1 **记录未随修复更新**：A 段记录的行数是修复前快照（`:229` 的 `807`），且无 fix round 登记（B 段先例 `:208-213`）。**本段按报告时点重拍**：`thincoder_kernel.dart` 860 行（代码 689 + 注释 93 + 空 78）· `thincoder_events.dart` 412 · `thincoder_mock.dart` 560 · `thincoder_protocol.dart` 189 · 其余八档不变；11 档合计 2711 行（口径 = 末尾空行不计）。拆分立场不变：缝候选 = 选择面段 / 重连三路块，是否续拆按设计 `:308` 裁定（父侧已裁「不续拆 + 登记下一缝」）。
- 🔵 新 2 **「会话已不在」两条路处置不一**（非本轮修复引入，被修复显影）：保留槽一路按 `gone` 兜底新建，**续接记录一路无兜底**（`session/resume` / `session/load` 直接抛出 ⇒ 启动失败；健康 failed 后 `prepare()` 早退、`restart()` 重复同一失败）⇒ 终端删掉该会话后，对应桌面会话一直显示启动失败，只能另开会话。设计档未见对应规则（本轮检索无命中；§14 未逐条通读）。建议设计侧一句话定死处置（新会话 / 明确失败文案）。

**fix 后复核（可用的机械核对）**：14 个 Dart 档词法配平（括号/字符串/插值）全过；10 个固件 JSON 结构与行型全过；`!await` 形态以本仓 `lib/` 79 处先例佐证可编译。**仍未跑**：`flutter analyze` / `flutter test`（无 SDK，未装任何东西；未真跑 `thincoder acp`——父侧明令）。待跑命令同上条记录。

**终态：`clean`** —— 阻断项 0（唯一 🔴 已按设计修订并补用例，第 2 轮核验通过）；余项 = 2 条已 Accepted 的可选项（#2/#3，均带库内记录依据）+ 4 条 🔵（2 已修、2 交父侧/设计侧）；无表外文件改动、无未披露偏离。

**更正（同轮，2026-10-16）**：上条记录里「11 档合计 2711 行」是笔误——按同一口径实测合计 **2726 行**（逐档：130 · 412 · 860 · 221 · 560 · 18 · 207 · 15 · 189 · 27 · 87）；三个测试档合计 1305 行（939 · 188 · 178）；固件 11 个文件（10 场景 + README）。其余数字不变。

### 实施记录 · C 段（接线点 ①⑥⑦⑧⑨ + ⑤ 按修正轮 2 重做 + 设计 §3.5-② 的 `gone` 兜底 + 接线测试）（2026-10-16）

**范围与授权**（父侧裁定）：本段 = §2 任务书的 C 段 = B 段留项（①⑥⑦⑧⑨）+ ⑤ 按修正后设计重做 + 设计 §3.5-② 的 `gone` 兜底 + 接线测试（设置行用例 + gone 兜底用例 + A1/A2 可行断言）。零改动面已守：`lib/kernel/claude_code/**`、仓根 `thincoder/**`（另一仓检出）、`docs/**` 均零触碰（`git status` 核对）。

**交付物与净增**（`git diff --numstat` 实测；净增 = 新增 − 删除；⑤ 的净增 = 该档净增 26 − B 段已记 12 = 14；适配层三档为 A 段未跟踪档，按本段新增行计）：

| 点 | 坐标（现状行号） | 改了什么 | 净增（上界） |
|---|---|---|---|
| ① | `lib/kernel/kernel_registry.dart:5-6`（import）· `:31-38`（描述符）· `:40`（`_all`） | thincoder 描述符入册并写在在售首位；`create` 传 `ThincoderKernel(thincoder, context)`、`catalog: ThincoderCatalog()` | +11（≤10）**超 1 行**（两条 import 未计入口径） |
| ⑥ | `lib/main.dart:42`（import）· `:127`（reap）· `:563`（stop） | 启动回收 + 退出 `Future.wait` 停止 | +3（≤6） |
| ⑦ | `lib/settings/pages/general_page.dart:14`（import）· `:36-37`（页首档注）· `:60`（构造参数）· `:99-103`（字段）· `:384-399`（设置组）· `:742-796`（`_ThincoderPathSetting`） | 新增「thincoder」设置组：路径输入（`thincoder.path`，空 = PATH）+ 状态行（找到带版本 / 未找到 / 失败染红），形同 Claude Code 行；路径变即重读 | +81（≤80）**超 1 行** |
| ⑧ | `lib/settings/app_settings.dart:9`（import）· `:60`（构造参数）· `:99-101`（字段）· `:147`（传页）+ `lib/main.dart:43`（import）· `:159-163`（读 `thincoder.path` 回调）· `:347`（透传） | 设置回调注册 + 状态回调透传设置页 | ⑦⑧ 合计口径：app_settings +7（≤10）· main 侧 ⑧ 部分 +7（≤10，与 ⑥ 同档分计） |
| ⑨ | `lib/kernel/mock/mock_kernels.dart:8-9`（import）· `:34-45`（描述符） | `MockKernels.thincoder`（`start: ThincoderMock.start` / `launch: ThincoderMock.launch`），**不进 `all`**（D18） | +15（≤16） |
| ⑤ | `lib/workspace/workspace.dart:292-294` · `:298` · `:308` · `:319-331` · `:333-338` · `:432-438` | `covered: Map<KernelDescriptor, Set<String>>` 按内核记账；`_folders` 逐目录按「有 catalog ∧ 未被该内核覆盖」子集调 `_listKept(project, kernels: 子集)`（仍不等待）；守卫改「本轮触发过逐目录列出即不清理」；`_listKept` 收内核子集（缺省全量，`_openProject` / `_listWhenReached` 语义不变） | +14（≤14） |
| gone 兜底 | `lib/kernel/thincoder/thincoder_kernel.dart:217-278` | `session/load` / `session/resume` 收 `-32602`（`gone`）⇒ 忘槽 + `_openNew`（两路同处置）；抽 `_pickUp` 单点供三处（含原 `_pickUpKept`） | +13（设计 §3.5-② 新 bullet，无上界） |
| 表外 1 | `lib/kernel/thincoder/thincoder_locator.dart:53-60` | `thincoderStatusLine(ThincoderStatus)`：设置行文案（找到带版本 / 未找到 / 失败原因原样） | +10（表外，如实披露） |
| 表外 2 | `lib/kernel/thincoder/thincoder_mock.dart:33-37` | `ThincoderMock.launch`：脚本会话的 launch（不去机器上找真 CLI） | +6（表外，如实披露） |
| 测试 | `test/kernel/thincoder_kernel_test.dart`（+2 import · +1 记录 `gone` 兜底用例 · +1「注册内核」断言组）· `test/settings/settings_wiring_test.dart`（`start()` 增 `thincoderStatus` 形参 +1 设置行用例） | — | 新增约 110 行 |

**决策透明表**：

| # | 决定 | 依据 | 代价/风险 |
|---|---|---|---|
| 1 | 表外 1：状态行取词函数落 locator（`thincoderStatusLine`） | widget 内联 switch 会挤占 ⑦ 的 ≤80 上界；locator 本就是探测/文案之家（A 段先例） | 表外一处 API（+10 行），已披露 |
| 2 | 表外 2：`ThincoderMock.launch` 落 mock 档 | ⑨ 描述符要 `launch`；内联闭包会把 mock 档的 `ThincoderTransport` import 带进 ⑨ 且净增破 ≤16 | 表外一处 API（+6 行），已披露 |
| 3 | ⑦ 设置组不套内层 `SettingsCard` | `SettingsGroup` 自身已包一张卡；全仓 `SettingsGroup` 用法 11 处仅 general_page 的 Claude Code / IDE 两组套内层卡 | 与相邻 Claude 组的嵌套形略异（省 8 行，保住上界）；审计判「两先例都在」，父侧如要严格对齐可加回 |
| 4 | 文案英文直写、本轮不加 l10n 键 | 新增键要改 `lib/l10n/**` 5 档（含生成档；`flutter gen-l10n` 本机不可用）＝超 ⑦ 表外坐标；无 SDK 不宜手改生成档 | zh-cn 用户该行显示英文（与同页 Claude 行不一致）⇒ 上抛待裁（见上抛项 3） |
| 5 | gone 兜底抽 `_pickUp` 单点（load / resume / 自建会话重连三处共用） | 同一处置三处复用，避免三份重复 | 无 |
| 6 | ⑤ 的子集判据 = `kernel.catalog != null && !covered[kernel]!.contains(folder)` | 扫描失败的内核 `covered[kernel]` 恒空 ⇒ 该目录对其恒未覆盖，自然走逐目录列出（设计文本「扫描失败的内核不记覆盖」的直接结果，无需另记失败态） | 无 |

**审计与代码评审轮次与终态**：

- 内部分歧审计（explore，1 轮，只读）：**0 阻断 / 0 应修 / 2 建议 + 3 备注**。逐点一致性 ①⑤⑥⑦⑧⑨ + gone 兜底全部判「一致」（含 ⑤「确为按内核判定、非跨内核合并集」与「`_pickUp` 两路同处置」）；表外改动 0（mtime 全目录扫描 + 触碰面并集核对；`claude_code/**` 与 `thincoder/**` 零改动）；注释与代码抽查相符。建议两条＝⑦ 组是否套内层卡（见决策表 3）· 文案硬编码英文（见上抛项 3）。
- 独立代码评审（advisor，type=code，1 轮）：**VERDICT changes-required**。发现：**🔴 1 · 🟡 2 · 🔵 2**（逐条见下「上抛项」；🔵 两条＝体量上界需父侧按 numstat 终裁（本记录已补数）· ⑤ 行为无用例）。
- **fix round：0 次** —— 三条发现均落在本段授权外（设计面/口径面）：①既有用例期望与设计 ⑤ 守卫语义冲突（改用例＝动既有产品行为期望；改守卫＝超设计文本，且 §14-11 已把「清理整体推迟」登记为接受代价）；②gone 兜底后的重连口径设计未定（实现即新增未设计行为）；③文案 l10n 要改 5 档含生成档。三条均已写入上抛项（含修法与倾向）；本段未动 `test/workspace_test.dart`、未动 `lib/l10n/**`。
- **终态：`stalled`** —— 未闭项 = 上抛项 1（🔴）+ 2 / 3（🟡），均待父侧/设计侧裁定；其余 clean（无静默简化、无表外文件改动、无未申报偏离）。

**上抛项（待裁；均带事实、修法与倾向）**：

1. **🔴 既有用例 `test/workspace_test.dart:688`（"marks are dropped with the sessions gone…"）与 ⑤ 守卫语义冲突**（设计面）。事实（代码追踪，未实跑）：该用例第二次 `load` 的 `_folders` = `['/tmp/project', '/tmp/opened']`（`:695`），而 `FakeCatalog.projects()` 只覆盖 `/tmp/project`（`:51-55`）⇒ `/tmp/opened` 对唯一内核（claude）恒未覆盖 ⇒ `listedOneByOne = true`（`workspace.dart:326`）⇒ `_forgetGone` 不运行 ⇒ `:720` pinned / `:721` archived / `:723` names / `:725` folders 四条期望全部落空。即设计 §7 A9「既有测试不回退」的未闭项；B 段同语义（非本段引入），本段按修正轮 2 的 ⑤ 细则实现、未动该档（动它＝改既有产品行为期望，超本段授权）。修法二选一：**(A)** 把该用例期望改到新语义（最小；§14-11 已登记「清理整体推迟、`_folders` 不剪除」为接受代价）——需父侧授权改既有测试档；**(B)** 实现 §14-11 的判定条件变体「本轮触发的逐目录列出全部返回后再清理」（清理移入 `_listKept` 收尾）——恢复产品行为，但需 (i) 排除「宿主不可达而推迟」的目录（原码用 `RemoteLocation.isRemote` 拦过，否则误清远程标记）、(ii) ⑤ 上界 ≤14 放宽（+10~15 行）、(iii) 该用例的 `pumpLoaded`（`:81-101` 只 `await load` + 一次 pump）多半等不到异步清理 ⇒ 用例仍要补 pump。**倾向 A**（保住 ⑤ 字面形态与上界，§14-11 已认账）；若产品上要恢复清理则走 B（设计侧补一句 + 上界修订）。
2. **🟡 gone 兜底后的重连口径设计未定**（设计 §3.5/§14-13）。事实：兜底起的新会话只在**首次**启动生效——`_openRecord` 的槽恒取记录里的旧槽（`thincoder_kernel.dart:226`），而 `_loaded` 仍为 false ⇒ 该记录线程每次 `release()`→`prepare()` 都再 `session/load(旧槽)` → 再收 `-32602` → 再 `session/new`（用户在新会话里说过的话随进程关闭而丢；终端没删槽时不会发生）。修法（约 8 行）：记「记录槽已忘」（如 `_recordGone`），此后 `_openSession` 走 `_pickUpKept`（resume 本内核自己的会话、不重放）。**倾向**：设计侧先定一句口径再实现（现在实现＝新增未设计行为），或明示「兜底会话不跨重连」。
3. **🟡 ⑦ 文案口径（l10n）**（口径面）。事实：新行与状态行英文直写（`general_page.dart:768-770` / `:790-791`；`locator.dart:56-59`），同页 Claude 行走 l10n，`lib/l10n/**` 无 thincoder 键；另一差别＝状态未就绪时不显示「检查中」占位（Claude 行有）。修法：补 `app_en.arb` / `app_zh.arb` 键（形同 `claudePath*`：label / description / hint / checking / in-use / missing）+ `app_localizations*.dart` 三档（生成档，pub get 或 `flutter gen-l10n` 重产）+ 设置行改用 `context.l10n`（连带更新 `test/settings/settings_wiring_test.dart:399/:423` 的英文断言）。**倾向**：与 SDK 就位那一轮一起做（本机无 SDK，手改生成档不可验），或设计/需求档明示「thincoder 行英文占位」。
4. **🔵 A1 断言口径**（设计 §7 A1 与可实现面不一致，report-and-pass）：设计要求 `KernelRegistry.all.first.id == 'thincoder'`，但 `test/flutter_test_config.dart:39` 对全量测试把注册表换成 `MockKernels.all` ⇒ 该断言写不出；交付以 `KernelRegistry.thincoder.id == 'thincoder'` + `MockKernels.thincoder ∉ MockKernels.all` 兜底，A1 事实由代码核（`kernel_registry.dart:40`）。建议设计侧同步口径。
5. **🔵 ⑤ 的行为无用例**：本段测试覆盖 ①⑨⑦ 与 gone 兜底，无「claude 覆盖过的目录，thincoder 的 `sessionsIn` 仍须执行」的回归用例（B 段 🔴 的复现面）。建议随上抛项 1 的裁定一起补一条 workspace 级用例（两描述符：一个覆盖目录、另一个断言 `sessionsIn` 被调用）。

**验证**：**验证未跑** —— 本机无 Flutter/Dart SDK（未找 SDK、未装任何东西；未真跑 `thincoder acp`——会写用户 `~/.thincoder` 槽库并耗额度，父侧明令禁止）。可用的机械核对（已跑）：改动面 9 档 + 测试 2 档 + 邻接 1 档的词法配平（括号 / 字符串 / 注释）全过；行宽 ≤80（本段新行全过，未新增超宽行）；新增符号与既有调用点的型别逐一比对（`ThincoderLauncher` / `ThincoderTransportFactory` / `ThincoderCatalog` / `reapThincoderProcesses` / `stopThincoderProcesses`）。待跑命令：`flutter pub get` · `flutter analyze` · `flutter test test/kernel/thincoder_kernel_test.dart test/settings/settings_wiring_test.dart` · `flutter test`（全量；重点 `test/workspace_test.dart`（上抛项 1 的判定面）· `test/settings/` · `test/kernel/` · `test/chat/`）。

**不在本段**：真机走查（T15 / A3–A6）· `test/workspace_test.dart:688` 的期望处置（上抛项 1）· l10n 键与「检查中」占位（上抛项 3）· A2 的运行期断言（受同一注册表替换所限，机制由既有 `test/workspace/preferred_kernel_test.dart` 覆盖）。

### 实施记录 · 末修单（fix round：既有测试期望对齐 + ⑤ 回归用例 + §3.5 跨重连实现）（2026-10-16）

**范围与授权**（父侧裁定 = C 段上抛 1/2/5 的落地）：① 存量用例与 ⑤ 守卫新语义对齐（A9 口径调整；**父侧授权改既有测试档**）· ② 补 ⑤ 按内核判定的回归用例 · ③ 实现设计 §3.5`:151` 跨重连口径（兜底后记「记录槽已忘」，此后走保留槽路线）+ ④ 对应内核用例。**本单不做**：l10n 键（SDK 轮）· §14-11 的清理恢复变体（未触发）· 其它任何面 · docs。零触碰已守：`docs/**`、`thincoder/**`、`lib/l10n/**`、`lib/` 其余档。

**交付物与净增**（净增 = 新增 − 删除；tracked 档 = `git diff --numstat` 实测，untracked 档 = 逐编辑行数差计）：

| 号 | 坐标（现状行号） | 改了什么 | 净增 |
|---|---|---|---|
| ① | `test/workspace_test.dart:716-759` | 用例更名（「marks stay while sessions are still to be listed…」）+ 四条期望改「保留」语义（注释引 §14-11；「未列 ≠ 已消失」不变量保留） | 见下（同档合计） |
| ② | `test/workspace_test.dart:67-92`（新 `_DirectoryCatalog`）· `:113`（`pumpLoaded` 收 `kernels`）· `:805-854`（新用例） | ⑤ 回归用例：两内核（claude 覆盖 `/tmp/project`；`other` 的 `projects()` 恒空、`sessionsIn` 记账）⇒ `other.sessionsIn` 照被调、其会话在列 | 同档合计 **+93 / −9（净 +84）**（numstat 实测；五个 hunk 全属本轮） |
| ③ | `lib/kernel/thincoder/thincoder_kernel.dart:80-83`（字段 + 文档）· `:211`（`_openSession` 条件）· `:236`/`:249`（两处 gone 兜底置位）· `:222-227`（`_openRecord` 文档同步） | §3.5 跨重连：兜底时记 `_recordGone`；此后 `prepare()` 走 `_pickUpKept`（`session/resume` 本内核自己的会话），不再重走 `session/load` 死槽；保留槽再 gone 仍回落 `_openNew` | **+15 / −6（净 +9）**（设计「约 8 行」/ 任务书「~≤10 行」内） |
| ④ | `test/kernel/thincoder_kernel_test.dart:523-573` | 新用例：空架 ⇒ `load('3')` 收 `-32602` ⇒ 兜底 `new`（槽 1）⇒ 发消息 + `release()` + `prepare()` ⇒ `resume('1')` 成功、`load`/`new` 皆空、内容不重放 | +51（0 删除） |

**决策透明表**：

| # | 决定 | 依据 | 代价/风险 |
|---|---|---|---|
| 1 | `_recordGone` 实例级、不重置（`restart()` 不清） | 设计 §3.5`:151`「此后 `prepare()` 走保留槽路线」；`context.resume` 在实例生命周期内恒定 ⇒ 重置无正确场景 | 无 |
| 2 | 置位点 = `_openRecord` 两处兜底（load 路 + `_loaded` 路的 resume），不在 `_pickUp` 内部 | `_pickUp` 亦被 `_pickUpKept` 共用（自建会话 gone ≠「记录槽已忘」）；置位贴着「记录槽」语义 | 无 |
| 3 | 相位 2 四条期望取「保留」值（`folders` 亦不剪除），不新增相位补「清理实跑」断言 | 任务书明示「四条期望按新语义更新（清理推迟 = 预期行为）」+ §14-11 已认账；第三相位属范围外 | 本档暂无「清理实跑 ⇒ 标记掉落」用例（评审 🔵 #3 已记） |
| 4 | 内核用例先发一条消息、再 `shelf.add('1')`，模拟「发过消息才落槽」 | §3.5`:146`：未发过消息的会话不落槽文件 ⇒ 真机上兜底会话只有有内容才可能被下次进程找到；照真实语义建模 | 无 |
| 5 | ⑤ 回归用例用局部 `_DirectoryCatalog` + 档内既有 `claude` 描述符两内核 | 任务书「两内核用 FakeCatalog 形搭建」；`claude` 的 FakeCatalog 恒覆盖 `/tmp/project` ⇒ 承担「A 内核已列过」 | 无 |

**审计与代码评审轮次与终态**：

- 内部分歧审计（explore，1 轮，只读）：**代码面 0 阻断 / 0 应修 / 0 表外改动**；3 条备注 —— ① 流程项：本记录当时尚未落盘（随本记录补上）· ② 设计档「实现随后续单」措辞滞后（见上抛项 1）· ③ 本档「清理实跑」无覆盖（见上抛项 2）。逐条一致性 ①–④ 全判「完整」，并注明 ②④ 在改动前代码上会失败（真回归用例）；注释/代码逐条相符；`print(`/`debugPrint`/`TODO`/`FIXME`/`HACK` 零命中；mtime 扫描确认表外零改动（`thincoder/**`、`lib/l10n/**` 零触碰）。
- 独立代码评审（advisor，type=code，1 轮）：**VERDICT pass** —— 🔴 0；🟡 1（report-only，非 must-fix）；🔵 3（可选）。响应表：

| # | 严重度 | 发现 | 处置 |
|---|---|---|---|
| 1 | 🟡 report-only | 设计档 §3.5`:151` / §14-13`:477` 仍写「实现随后续单」；批次档 §5 C 段仍记「fix round：0 次」、上抛项未标已裁 ⇒ 文档状态滞后（R7a） | **不修（留父侧/设计侧）**：本单范围明示 docs 不做；随本记录上报 |
| 2 | 🔵 | 相位 1（坏 catalog 腿）未隔离 `complete` 守卫（同腿 `listedOneByOne` 亦真 ⇒ 守卫被删该断言仍绿） | **不修（留档建议）**：改结构超出本单「四条期望更新」授权面 |
| 3 | 🔵 | 本档无「`_forgetGone` 实跑 ⇒ 标记掉落」用例（原用例即唯一） | **不修（范围外）**：§14-11 代价的可选补覆盖，父侧需要时另派 |
| 4 | 🔵 | 内核用例未覆盖「兜底会话亦不在架 ⇒ `_pickUpKept` 再 gone ⇒ `_openNew`」腿 | **不修（已记）**：该出口 = `_pickUpKept` → `_pickUp`（`gone` 单点）→ `_openNew`，既有用例 `test/kernel/thincoder_kernel_test.dart:455` 已覆盖同一出口 |

- **fix round：0 次**（评审无 must-fix；上表 4 项均落在本单范围外，已逐条记处置）。
- **终态：`clean`** —— 三条目标全落；无静默简化、无表外文件改动、无未申报偏离。余项 = 1 条 report-only 🟡（文档同步，父侧）+ 3 条已记 🔵。

**上抛项（知会）**：

1. **文档层同步（父侧/设计侧）**：设计档 §3.5`:151` 与 §14-13`:477` 的「实现随后续单」已由本轮落地 ⇒ 规范面死句待清（改写为已实现口径 + 三坐标 `thincoder_kernel.dart:83`/`:211`/`:236`）；批次档 §5 C 段的「fix round：0 次」与上抛项 1/2/5 状态待随本记录更新。
2. **覆盖面的两条可选补强**（评审 🔵 #2/#3）：坏 catalog 腿的守卫隔离 · 「清理实跑」用例；均超出本单授权面。

**验证**：**验证未跑** —— 本机无 Flutter/Dart SDK（未找 SDK、未装任何东西；未真跑 `thincoder acp` —— 会写用户 `~/.thincoder` 槽库、耗额度，父侧明令禁止）。可用的机械核对（已跑）：三档词法配平（注释/字符串/插值/括号配对；对照两个未触碰档 + 一个人造反例，反例被正确报出）全过；三档改动新行 ≤80 列；全部改动区读回核对（注释与代码逐条相符）。待跑命令：`flutter pub get` · `flutter analyze` · `flutter test test/workspace_test.dart test/kernel/thincoder_kernel_test.dart` · `flutter test`（全量；重点 `test/workspace_test.dart`、`test/workspace/`、`test/kernel/`）。

### 实施记录 · SDK 轮（analyze 首次补跑：本批文件面告警清零）（2026-10-16）

**范围与授权**（父侧裁定）：只修本批 6 档（`lib/kernel/thincoder/` 五档 + `test/kernel/thincoder_kernel_test.dart`）的 analyze 条目，坐标钉死于派单；不做面外存量、不改行为语义（除第 4 条所必需的构造面补充）、不动其它文件、不改测试意图。

**逐条落地**（坐标 = 改后现状；改前读数 = 命令输出原文）：

| 号 | 坐标 | 改动 | 改前读数 | 改后 |
|---|---|---|---|---|
| 1 | `thincoder_mock.dart:81` | `final Set<String> _deleted = {}` ⇒ 补 `;` | `error - Expected to find ';' - :80:33` | 清 |
| 2 | `thincoder_events.dart:263-264` | `_tool(update['kind'], …)` ⇒ 取值收窄：`final kind = update['kind'];` + `kind is String ? kind : null`（保留「非 String ⇒ null ⇒ default 分支」语义，无 `as` 抛错面） | `error - The argument type 'Object?' can't be assigned to the parameter type 'String?' - :263:24` | 清 |
| 3 | `thincoder_kernel.dart:309` | `_applyStartMode` 的 `wanted` 用类型测试提升：`if (wanted is! String \|\| (wanted != 'plan' && wanted != 'normal')) return;`（`wanted` 实为 `String?`（`agent_kernel.dart:74` 的 `settings` 为 `Map<String, String>`），`!=` 比较不提升） | `error - The argument type 'String?' can't be assigned to the parameter type 'String' - :311:24` | 清 |
| 4 | `thincoder_mock.dart:26` + `:56` | 构造面接通：构造器补 `this.askPermission = false,`；字段 `bool askPermission = false;` ⇒ `bool askPermission;`（保持可变、默认 false）。既有消费点 `_prompt` 内 `askPermission && await _approve(update)`（`:363`）一字未动 ⇒ 四处用例的 `ThincoderMock(askPermission: true)` 类型闭合，用例意图未改 | 4 × `error - The named parameter 'askPermission' isn't defined - test/kernel/thincoder_kernel_test.dart:304/340/365/401` | 清 |
| 5 | `thincoder_events.dart:87` · `thincoder_locator.dart:200` · `thincoder_mock.dart:227` · `thincoder_protocol.dart:3` | 去多余 `this.`（`_ => mode,`）· 去多余字符串插值（`parseVersion(version ?? '')`）· 去多余 `!`（`_known.add(_slot)`）· 删未用 import（`thincoder_transport.dart`；余两 import 均被消费） | `info - unnecessary_this` · `info - unnecessary_string_interpolations` · `warning - unnecessary_non_null_assertion` · `warning - unused_import` | 清 |

**自跑命令与读数**（原文照录；SDK = `C:\Users\xinbo\repos\flutter`（3.47.5 / Dart 3.13.4））：

- 命令：`cd /d D:\baocode && set "PUB_HOSTED_URL=https://pub.flutter-io.cn" && set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn" && "C:\Users\xinbo\repos\flutter\bin\flutter.bat" analyze`
- 改前 1 轮：`22 issues found`——本批 6 档 = 7 error + 4 warning/info（error：events:263 · kernel:311 · mock:80 · test:304/340/365/401；warning/info：events:87 · locator:200 · mock:226 · protocol:4）；面外存量 11 条。
- 改后 1 轮：`11 issues found`——**本批 6 档 0 issue**；余 11 条全部面外（site_icons:2 · debug_editor_glue ×3 · side_panel_search_test ×2 · chat_split_test:16 · composer_test:911 · forge_test:33 · ide_units_test:365 · remote_project_test:673），按单不动。
- 计数口径偏差（如实登记）：派单写「7 error + 5 warning/info」「面外存量 10 条」；实测为 7 + 4 与面外 11（以上为命令原文计数，未折算口径）。

**测试实跑：受阻（机器级，非本单）**——`flutter test test/kernel/thincoder_kernel_test.dart` 不可跑，两路证据：

- 包 `packages/bao_editor`（`hook/build.dart` + `hook/windows_vswhere.dart`：Oniguruma/TextMate 原生库）与 `packages/bao_pty` 的 native assets build hook 需要 MSVC；本机无 VS（`C:\Program Files\Microsoft Visual Studio` 与 `Program Files (x86)` 两路均不存在）⇒ hook 抛 `Exception: vswhere.exe was not found next to the Visual Studio Installer.`，`Building native assets failed.`。
- 旁路尝试 `FLUTTER_NATIVE_ASSETS=false` 被工具直接拒绝：`Package(s) bao_editor bao_pty require the dart assets feature to be enabled.`（stable 通道下 `dart-data-assets` feature 不可用 ⇒ 无旁路；flutter_tools 侧闸 = `isolated/native_assets/native_assets.dart` 的 `_hookRunRequired`）。
- ⇒ 第 4 条四个用例只到 analyze 级类型闭合，运行绿未实测；实跑需装 VS Build Tools（用户级安装，超本单授权，留父侧/用户裁）。

**审计与代码评审轮次与终态**：

- 内部分歧审计（explore，1 轮，只读）：**0 偏差**——PARTIAL / SILENT-SIMPLIFICATION / DOC-DRIFT / OUT-OF-LIST 四类均无；mtime 扫描：本单痕迹 = 5 档 lib 一簇，`test/kernel/thincoder_kernel_test.dart` 未被触碰（第 4 条经构造面接通，与「不得改用例意图」一致）；`print(` / `debugPrint` / `TODO` / `FIXME` / `HACK` 于 6 档零命中。
- 独立代码评审（advisor，type=code，1 轮）：**VERDICT pass**（🔴 0；🟡 2 非 must-fix；🔵 2）。响应表：

| # | 严重度 | 发现 | 处置 |
|---|---|---|---|
| 1 | 🟡 report-only | 本修复轮未落档（§1 状态行仍「无 SDK」；§5 无本单记录） | **已办**：本记录即落档；§1 状态行为父侧留项 |
| 2 | 🟡 optional | `thincoder_kernel.dart:299` / `:459-460`：`session/new` 应答无 `sessionId` ⇒ `_slot` 空 ⇒ `_deliver` 静默 return（无 notice、无 TurnEnded） | **不修（超本单范围）**：改它 = 改行为语义，派单明禁；留父侧裁（修法建议：错误 notice + `_endTurn(interrupted: true)`） |
| 3 | 🔵 | 计数三处不一致、analyze 输出未入档 | **已办**：上「自跑命令与读数」段照录命令与前后计数（并登记口径偏差） |
| 4 | 🔵 | 该测试档自 A 段起从未实跑，本轮又受阻 | **不修（环境）**：留工具链就位轮实跑并回写 |

- **fix round：0 次**（评审无 must-fix；#2 属范围外，#1/#3/#4 为记录/环境项）。
- **终态：`clean`** —— 6 条目标全落；无表外代码改动、无未申报偏离；唯一未闭项 = 运行绿未实测（机器级阻塞）。

**面外观察（登记，未动）**：① 仓根 `.thincoder/tmp/` 内留 `fetch-flutter.mjs`（1162 B）与 `flutter_windows_3.47.5-stable.zip`（1933437428 B）——未进 `.gitignore`（`.gitignore` 无 `.thincoder` 行），非本单产物、早于本单改动；② `pubspec.lock` 与 `windows/flutter/generated_*` / `macos/Flutter/GeneratedPluginRegistrant.swift` 的 M 状态为 SDK 就位轮 flutter 运行所留（mtime 05:53，早于本单首笔改动）。二者均留父侧处置。

**验证口径**：自跑 = `flutter analyze` 两轮（改前 / 改后，读数如上）；`flutter test` = 环境受阻（如上，非本单）。未真跑 `thincoder acp`（父侧明令）。

### 实施记录 · 走查现场缺陷修复（`session/prompt` 显式不设超时）（2026-10-16）

**范围与授权**（父侧裁定）：设计档 `docs/design/thincoder-adapter.md:134-135`（修正轮 6 裁定）逐字兑现——协议层给出「显式不设超时」的表达、kernel 的 `session/prompt` 改用它、其余请求照旧。**本单不做**：动其它请求的超时口径 · 动连接缺省值 · 改设计/需求档 · 动三档以外的文件。零触碰已守：`docs/**`、`lib/` 其余档、`thincoder/**`。

**交付物与净增**（本轮逐编辑计数；三档均 untracked 新档，`git diff --numstat` 不示）：

| 点 | 坐标（现状行号） | 改了什么 | 净增 |
|---|---|---|---|
| ① 协议 | `lib/kernel/thincoder/thincoder_protocol.dart:66-76` · `:93-111` | 哨兵常量 `static const Duration noTimeout = Duration.zero`（注释写清：只给 `request` 的 per-call 参数；`session/prompt` 必须，因其答案随回合结束、回合无上界）；`request` 增分流 `if (timeout == noTimeout) return done.future;`——「缺省（60s）」与「显式不设超时」一处判开 | +14 |
| ② kernel | `lib/kernel/thincoder/thincoder_kernel.dart:462-469` | prompt 调用第三参 `ThincoderConnection.noTimeout` + 两行注释（回合无上界 ⇒ 不上连接钟） | +2（另 1 行改写：`});` ⇒ `}, ThincoderConnection.noTimeout);`） |
| ③ 测试 | `test/kernel/thincoder_kernel_test.dart:18`（import）· `:927-970`（新组 `thincoder connection`） | 假 sink 正例 + 对照：连接缺省 50 ms、应答 90 ms 后到达、`request` 传 `noTimeout` ⇒ 正常拿到结果；同参数不传 ⇒ 抛 `session/prompt got no answer` | +45 |

**决策透明表**：

| # | 决定 | 依据 | 代价/风险 |
|---|---|---|---|
| 1 | 机制 = 哨兵常量 `ThincoderConnection.noTimeout`（值 `Duration.zero`）承载在 `request` 第三参；未选命名参数 | 派单允许二选一（「哨兵值 / 或命名参数」）；哨兵在调用点自述，判断收在协议层一处；与 `request` 既有位置参形态一致（先例 `control_channel.dart:29` 亦位置参） | 哨兵与「合法零时长」同值 ⇒ 构造面 `timeout:` 传它语义反转（评审 🔵 #4；当前无调用点如此用） |
| 2 | 测试形态 = 协议层假 sink（正例 + 对照），未加 kernel 级守卫 | 派单钉死测试形态与落点；kernel 内部连接超时不可注入 ⇒ kernel 级腿要新增构造面注入缝（超本单授权面） | 调用点无回归覆盖（评审 🟡 #1）：删第三参全仓仍绿——已登记为上抛可选项 |
| 3 | 注释改动后复跑该测试档（不跑全量） | `CLAUDE.md`：改后只跑相关测试 | 无 |

**审计与代码评审轮次与终态**：

- 内部分歧审计（explore，1 轮，只读）：**0 阻断 / 0 应修**；四类偏差（PARTIAL / SILENT-SIMPLIFICATION / DOC-DRIFT / OUT-OF-LIST）均未发现；逐点一致性核「哨兵表达 / prompt 调用 / 其余请求照旧 / 对照断言方向」全过；mtime 扫描：代码面只碰本单三档（同窗口另有 docs 两档 mtime 14:10 = 前裁定轮文档面、早于本单代码写；需求档未动）；`print(` / `debugPrint` / `TODO` / `FIXME` / `HACK` 三档零命中；一处小瑕（对照腿注释措辞宽于代码）已修（见 fix round 1）。
- 独立代码评审（advisor，type=code，1 轮）：**VERDICT pass** —— 🔴 0 · 🟡 2（均非 must-fix）· 🔵 2。响应表：

| # | 严重度 | 发现 | 处置 |
|---|---|---|---|
| 1 | 🟡 optional | 回归用例只锁协议层哨兵语义，未锁 kernel 调用点（删第三参全仓仍绿） | **不修（披露）**：派单钉死测试形态（协议层假 sink）+ 授权面为三档；kernel 级腿需给 `ThincoderKernel` 加连接超时注入缝（改构造面，超设计裁定范围）⇒ 见上抛项 1 |
| 2 | 🟡 report-only | 设计档 `:494` / 批次档 `:194` 仍写「实现修随后续单」；§5 无本单记录 | **已办一半**：本记录即 §5 落档；设计档一侧 = 父侧/设计侧（本单明示不改设计档）⇒ 见上抛项 2 |
| 3 | 🔵 | 新用例依赖真实墙钟（50 / 90 ms） | **不修（披露）**：断言方向正确（无超时腿不会假红，超时腿本就不回包），慢机只变慢；改假时钟需引 `fake_async` 入该档，收益低——登记备用 |
| 4 | 🔵 | 哨兵与合法零时长同值 ⇒ 构造面 `timeout:` 传它 = 立即超时（语义反转） | **不修（披露）**：现无调用点如此用（构造点 `thincoder_catalog.dart:75` / `thincoder_kernel.dart:147` 均用缺省）；已登记决策表 #1，下一触碰该档时可补一句注释 |

- **fix round：1 次**（审计小瑕、非阻断、本单自修）：对照腿注释「an answer that comes too late is no answer」宽于代码（该腿根本不发应答）⇒ 改为「no answer within its 50 ms is no answer」；改后复跑 `thincoder_kernel_test.dart` 全绿（后随 advisor 评审 = pass）。
- **终态：`clean`** —— 🔴 0 / must-fix 0；余项 = 2 条已披露评审建议（🟡 #1 / 🔵 #3·#4 披露留档）+ 1 条父侧文档项（🟡 #2）。

**验证口径（自跑实跑）**：

- `"C:\Users\\xinbo\repos\flutter\bin\flutter.bat" analyze lib/kernel/thincoder/thincoder_protocol.dart lib/kernel/thincoder/thincoder_kernel.dart test/kernel/thincoder_kernel_test.dart` ⇒ 两轮均 `No issues found!`（改后第二轮 ran in 2.8s）。SDK = 3.47.5（本机 MSVC 已在，native assets 构建正常——SDK 轮「无 MSVC」的梗阻已解除）。
- `"C:\Users\\xinbo\repos\flutter\bin\flutter.bat" test test/kernel/thincoder_kernel_test.dart` ⇒ 改后两轮均 `All tests passed!`；末轮 `+33`（逐组：内核 25 + 本单新组 1 + 会话 id 1 + locator 5 + 注册内核 1 = 33），新用例行 = `thincoder connection a request told to wait is not cut off by the connection timeout`。
- 未跑全量 `flutter test`（`CLAUDE.md`：只跑相关测试）；未真跑 `thincoder acp`（会写用户 `~/.thincoder` 槽库，父侧明令）。

**上抛项（知会）**：

1. **kernel 级回归守卫（可选）**：若要锁「prompt 确实传了 `noTimeout`」，需给 `ThincoderKernel` 加连接超时注入缝（构造面新参 + 缺省仍 60s）、再补一条 kernel 级腿；超本单授权面，未做——请父侧定夺是否另派。
2. **文档层清理（父侧/设计侧）**：设计档 `docs/design/thincoder-adapter.md:494` 与批次档 `:194` 的「实现修随后续单」已由本单落地 ⇒ 规范面死句待改已实现口径（坐标 = protocol `:76`/`:111` + kernel `:469` + 用例 `:928`）。

## §6 验证与收口（父代理）

### 验证与收口（2026-10-16）

**验证面**

| 面 | 方式 | 读数 |
|---|---|---|
| 静态分析 | `flutter analyze`（Flutter 3.47.5 · Dart 3.13.4） | 本批文件面 **0 issue**；全仓余 11 条 = 既有存量（非本批，不扫） |
| 本批测试档 | `flutter test`（kernel/catalog/fixtures + workspace/preferred_kernel/settings_wiring） | 内核档 **33/33 全绿**（含「说了等就不被连接超时切断」新用例）；目录/夹具/工作区/首选内核绿；settings 档 4 条 = 机器级 teardown（见下） |
| 全量对照 | 本批树 vs 干净 HEAD 工作树（同机基线） | 通过 5808 ↔ 5753；红集合差 = +3/−0（1 新用例环境 teardown + 2 flaky）⇒ **零语义回退** |
| 走查（用户实机） | A1–A6 | A1 ✅ · A2 ✅ · A3 ✅（终端会话列于桌面且模型读入）· A4 ✅（60s 修复后长回合复验：无 got no answer、无误中断）· A5 ✅（粘图落盘 `paste-<runId>-<i>.png`，双图实证）· A6 ✅（设置行 in use 0.12.74） |

**走查现场缺陷（批内闭环）**：`session/prompt` 走连接缺省 60s 时钟 ⇒ 长回合误报 `-32603 session/prompt got no answer` + 回合错标 interrupted。修 = 协议层 `noTimeout` 哨兵 + prompt 调用显式不设超时（设计 §3.4 · 变更记录「修正轮 6」）+ 正反用例（90ms 应答 vs 50ms 缺省）；新构建复验通过。此为批内直修的现场缺陷，非新增语义。

**机器级说明（非本批）**：`settings_wiring` 4 条 teardown 删除临时目录失败（errno 32）——干净基线同样复现（其中 3 条为仓内既有用例），属本机/平台面；全量红集合除上述差集外与基线逐一一致。

**结算**

- 台账 #1（批 1 需求点）⇒ **已核销**（证据：本档 + §5 实现坐标）。
- 技术待办随批带：#4 #5 #6 #7 #8 #9 #10 #12，各挂触发条件；#11 复验一致、已撤回。
- 暂缓批复核：无。
- 环境注记：`pubspec.lock` 与 4 个平台生成档的改动 = Flutter 3.47.5 固有解算（干净基线复现），用户知悉、保留。

**跨仓指针**：thincoder 侧「模型清单 + 思考档位」= 用户裁定走 CLI 侧补（2026-10-16）；baocode 侧零改动（E3 钩子已备，设计 §14-1）。
