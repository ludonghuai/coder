# 2026-10-19 · 台账清理（缺陷批 · 测试债 · 文档卫生）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-19 · 来源 = 用户 2026-10-19 21:02「好，我们继续解决台账吧」——按台账 C 组（缺陷）+ D 组（测试债）+ E 组（文档卫生）顺序推进。
> 台账 = #100（ide-git · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-19
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**状态行**：🔄 进行中（轻渠道；缺陷批 6 笔已落，测试/文档两组待跑）

| # | 笔 | 披露 | 改动 | 验证 |
|---|---|---|---|---|
| 1 | #97 terminal 链接解析 | light · 缺陷修复 | `terminal_link_resolver.dart:88-93` 增 `on FormatException`（实测 `%E4` 抛 FormatException、`%zz` 才 ArgumentError）；用例补两条 | `terminal_link_resolver_test` 全绿（含新用例） |
| 2 | #98 命令面板标题 | light · 细节（文案） | `command_titles.dart:190` → `scmFetchAndPullAll`；`workbench_keybindings.dart:537-540` 英文标题改「Fetch and Pull All Repositories」 | `scm_repositories_test` 全绿（按命令 id 执行，不受标题影响） |
| 3 | #82 chip 读屏文案 | light · 细节（文案） | 新键 `editorContextDismiss`（en/zh）+ `editor_context_chip.dart:61/:67` 改用；ARB 按字节插入保 CRLF（`git diff --numstat` = 8/0、2/0） | `editor_context_chip_test` 断言随改，全绿 |
| 4 | #91 只含图 user 消息空气泡 | light · 缺陷修复 | `IMAGES_STRIPPED_PLACEHOLDER` 下移到 `session-segments.mjs`（单源），`slimForDisplay` 剥空后给占位；`session.mjs` 改为 import + re-export 保既有面 | 9 条行为检查（copy-on-write / 占位 / 无图同引用） |
| 5 | #89 VSC 机器线未剥图 | light · 缺陷修复 | `panel-session-write.mjs:83` 机器线过 `stripImagesForArchive`；`session-io.mjs:57` re-export 增补 | `node --check` 两档 + 行为检查 |
| 6 | #88 anthropic transport 不转 tool 消息 | light · 缺陷修复 | `anthropic.mjs` `convertMessages` 扩：assistant `tool_calls` → `tool_use`（坏 JSON ⇒ `{}`）、`role:"tool"` → user 里的 `tool_result`、相邻结果合并；图像转换与 copy-on-write 语义保持 | 14 条行为检查全过（未对真 API 实测，标 unverified） |

**未跑**：C 组余 #49（需定提示落点）、#80（需 IDE→chat 快照监听接线）、#71（niche）；D 组测试债 5 条；E 组文档卫生 5 条。

**D 组（测试债）进展**

| # | 笔 | 披露 | 改动 | 读数 |
|---|---|---|---|---|
| 7 | #90 `test/ide/git` 12 条基线红 | light · 测试夹具（工程工具面） | `fake_files.testRoot` 改 `p.absolute(...)`（补盘符，与工作区规范化一致）；`git_service_test` 夹具加 `core.autocrlf=false`/`core.eol=lf` 并把 `p.join(root,'lib/a.dart')` 拆成组件；`git_blame_test` 工作区根改绝对 | **182/182 全绿**（12 → 0） |
| 8 | #81 Windows 路径分隔符 8 条 | light · 测试断言 | `composer_files_test` / `file_tags_test` 用 `p.join`/`p.separator` 构造期望（含目录尾分隔符） | 23/23 全绿 |
| 9 | #77 open_editor Claude 用例 | light · 测试夹具 | `send` 辅助每轮推 `{'type':'result'}` 收束回合 | 4/4 全绿 |
| 10 | #83 thincoder fixtures 17 条 | light · 测试夹具 | 17 档 `session/new` 期望去 `mcpServers: []`（F4：无宿主工具省略）；`load-replay` 补 `cwd`；`unknown` 改用真正未知方法 | 19/19 全绿 |

**新发现（登记 #101）**：`test/ide/workbench` 13 条、`test/ide/lsp/install` 15 条既有红——已用 testRoot 相对/绝对两态对照确认与本轮无关；不阻塞本轮。

**未跑**：#28（mock 未模拟入站串行，需新增 mock 能力）；C 组余 #49/#80/#71；E 组文档卫生。

**C 组余 + E 组（文档卫生）进展**

| # | 笔 | 披露 | 改动 | 读数 |
|---|---|---|---|---|
| 11 | #71 grant 键碰撞 | light · 缺陷修复 | `HostMcpServer.rebind` + `_openNew` 建会话后回填 grant；新用例 T19 | `host_mcp_server_test` **14/14** |
| 12 | #49 扫描失败无提示 | light · 细节（可见面） | 失败时一次性 warning 通知（`_scanWarned`，成功后清）；新键 `scmScanFailed` + gen-l10n | analyze 干净；该路径无既有用例（已知缺口） |
| 13 | #53 文档卫生 | 机械式收正（用户 2026-10-15 裁定 + 已定规则回灌） | 删 `thincoder-adapter.md` / `forge-accounts.md` 的 `## 变更记录` 整节；`ide-git.md` D18/§3.3/§12.1/§12.3/P4 按实测收正；D19 按用户 20:33 新裁定改写；`### 12.7` 经核为引用块内容、非标题，不改 | doc_check 46 条（锚 22 / 宽 24），见 #63 |
| 14 | #74 chat-streaming 指针 | 机械式（D4） | 删 `:6` 前情批次档指针、`:569` 批次档引用；全档 `docs/batches/` 零命中 | — |
| 15 | #48 设计档机制漂移 | 机械式（回灌实装） | §3.5 release 补 D64 谓词；§3.6 `send()` 行补队列语义 | — |

**未做**：#35（外仓两处设计档措辞，`thincoder/` 为 gitignored 检出）、#63（doc_check 进 CI + 行号改符号引用 + 架构/开发 setup 两页）、#80（chip 预览实时，需 IDE→chat 快照 Listenable，建议独立批）、#28（mock 入站串行）。

| 16 | #28 mock 入站串行 | light · 测试夹具（保真度） | `ThincoderMock` 新增 `serialInbound`（默认关）：开时入站帧 FIFO 逐个在各自 turn 上处理（`Future.delayed(Duration.zero)` 分隔，`_drainInbound`）；`_Session` 默认 mock 改用串行档 | `thincoder_kernel_test` **122/122 全绿**（含 T10 取消 / 队列 / 挂起） |

**本轮全部条目至此落定**：C 组 9/9（#49/#71/#80 除外——#80 另批）、D 组 5/5、E 组 3/5（#35/#63 留）。进入收口链：§2 设计形式化（eng-designer）→ §3 评审（用户点火）→ §4 批准 → §6 结算。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（16 笔逐笔有落点或理由；3 档形式化完成；doc_check 46→46）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 2.1 本批条目（16 笔，均已实现；验证读数来自 §1）

| # | 笔 | 行为（已实现） | 验证读数 | 设计落点 |
|---|---|---|---|---|
| 1 | #97 | 终端链接解析：`fileUriToPath` 增 `on FormatException`（坏 UTF-8 转义 ⇒ 无链接，不崩） | `terminal_link_resolver_test` 全绿（含新 2 例） | **不落**（无 owning 设计档，见 §2.7） |
| 2 | #98 | 命令面板 / 快捷键的 `git.fetchAll` 标题 = 「获取并拉取所有仓库」 | `scm_repositories_test` 全绿（按命令 id 执行，不受标题影响） | `docs/design/ide-git.md` §12.6-5 |
| 3 | #82 | chip 的 × 读屏标签 = 专用键 `editorContextDismiss`（en/zh） | `editor_context_chip_test` 全绿 | `docs/design/thincoder-adapter.md` §20.3 |
| 4 | #91 | 占位常量单源 `session-segments.mjs`；`slimForDisplay` 剥空给占位（人读线不再出空 `content`） | 9 条行为检查 | `docs/design/thincoder-adapter.md` §22.10 |
| 5 | #89 | VSC `saveLines` 机器线过 `stripImagesForArchive`；`session-io.mjs` re-export 增补 | `node --check` 两档 + 行为检查 | `docs/design/thincoder-adapter.md` §22.10（边界） |
| 6 | #88 | anthropic `convertMessages` 转 tool 消息（`tool_calls` ⇒ `tool_use`、`role:"tool"` ⇒ `tool_result`、相邻结果合并） | 14 条行为检查（未对真 API 实测，unverified） | `docs/design/thincoder-adapter.md` §22.9 |
| 7 | #71 | `HostMcpServer.rebind` + `_openNew` 回填 grant 的会话 id | `host_mcp_server_test` 14/14（含 T19） | `docs/design/host-tool-channel.md` §5.1 / §10 |
| 8 | #49 | 侧栏仓库扫描失败：一次性 warning（`scmScanFailed`）+ 30 秒重试，成功后清标记 | analyze 干净；该路径无既有用例（已知缺口） | `docs/design/ide-git.md` §4.7 |
| 9 | #28 | `ThincoderMock.serialInbound`（FIFO 逐帧、各自 turn）；`_Session` 默认用串行档 | `thincoder_kernel_test` 122/122 | `docs/design/thincoder-adapter.md` §9 |
| 10 | #90 | 测试夹具：`test/ide/git` 12 条基线红清零（testRoot 绝对路径 / CRLF / 标题期望） | 182/182 全绿 | **不落设计档**（夹具 / 断言层） |
| 11 | #81 | 测试断言按主机分隔符构造期望 | 23/23 全绿 | 同上 |
| 12 | #77 | open_editor Claude 用例每轮推 `result` 收束回合 | 4/4 全绿 | 同上 |
| 13 | #83 | thincoder fixtures 17 条：`session/new` 去 `mcpServers: []` 等 | 19/19 全绿 | 同上 |
| 14 | #53 | 文档卫生：删两档 `## 变更记录`；ide-git 按实测收正 | doc_check 46 条（锚 22 / 宽 24），见 #63 | 设计档自身（父侧直改，§1 已记） |
| 15 | #74 | chat-streaming 删批次档指针 | `docs/batches/` 零命中 | 设计档自身（同上） |
| 16 | #48 | 设计档机制漂移回灌（§3.5 release / §3.6 send） | — | 设计档自身（同上） |

### 2.2 设计落点表（每笔 → `file:section`）

| 号 | 落点 | 落下的口径（现状 + 一句理由） |
|---|---|---|
| #98 | `docs/design/ide-git.md` §12.6-5 | 命令面板 / 快捷键与菜单同键同文（`scmFetchAndPullAll`）——三处用户可见名一致，标题不再与实际动作（全仓 fetch + merge）不符 |
| #82 | `docs/design/thincoder-adapter.md` §20.3 | chip × 的读屏名与悬停同文（专用键）；图标单独对读屏不成按钮、也没有名字 |
| #91 | `docs/design/thincoder-adapter.md` §22.10 | 占位常量单源住 `session-segments.mjs`，人读线与机器线同占位；边界改为「两线都在源头剥图」 |
| #89 | `docs/design/thincoder-adapter.md` §22.10 | VSC 机器线同口径（`panel-session-write.mjs:83` → `stripImagesForArchive`）；§22.12 的跨面差异登记 U4 删除 |
| #88 | `docs/design/thincoder-adapter.md` §22.9 | tool 消息转换逐形 +「未对真 API 实测（unverified）」与判定条件（真机多轮工具会话）；§22.12 U3 删除、S1 延伸多轮工具会话 |
| #71 | `docs/design/host-tool-channel.md` §5.1 / §10 | grant 的会话键在 `session/new` 应答后回填，取消键 `(sessionId, requestId)` 语义成立；T19 入用例表；§12-12 登记删除 |
| #49 | `docs/design/ide-git.md` §4.7（新增） | 扫描失败一次性 warning + 30 秒重试 + 成功清标记；静默失败会把「没有仓库」伪装成事实 |
| #28 | `docs/design/thincoder-adapter.md` §9 | mock 入站串行档的保真度（FIFO、各自 turn）与默认使用（`_Session`） |
| #97 | —（不落） | 五档对终端链接零引用；该面整体没有设计档，新建整档超出本轮范围（见 §2.7 上抛） |

### 2.3 机制设计（本轮只做形式化，无新机制）

- 设计档只写现状：§1 已实现的行为写成「行为 + 一句理由」，同一机制只在一处详述（D2），他处按 `doc:section` 引用。
- 已闭合的缺口不留残影（D8）：删 `thincoder-adapter.md` §22.12 的 U3 / U4、`host-tool-channel.md` §12-12（三条均已由实现闭合）；被其引用的正文句同步改写，不留「原缺口」转述。
- 同源收正（一致性面，随笔修）：`session.mjs` 的 `contextHistory` 行号 `:142` → `:144`（§22.7-7 / §22.10 / §22.12 三处）；占位常量地址改为 `session-segments.mjs`（§22.10 / §22.12）；§22.12 零改动清单移除 `session-segments.mjs`（它现承载占位常量）。
- 无代码改动、无新 UI 决策、无结构重排。

### 2.4 受影响文件与测试覆盖

| 文件 | 当前行数 | 本笔增量 |
|---|---|---|
| `docs/design/thincoder-adapter.md` | 3279 | +7 行（§9 / §20.3 / §22.9 / §22.10 / §22.12） |
| `docs/design/ide-git.md` | 615 | +9 行（§4.7 新增 8 行 + §12.6-5 1 行） |
| `docs/design/host-tool-channel.md` | 552 | 净 +1 行（+9 / −8：§5.1 / §10 / §7.1 / §9 / §11 / §12-12 删除） |

- 行宽：新增行全部 ≤300 字符（`doc_check` 零新增命中，见 §2.5）。
- 测试：本批无新增用例；验证面 = §1 读数（`terminal_link_resolver_test` / `editor_context_chip_test` / `host_mcp_server_test` 14/14 / `thincoder_kernel_test` 122/122 / `test/ide/git` 182/182 / fixtures 19/19 / composer 23/23 / open_editor 4/4）。#88 / #91 / #89 / #49 为行为检查（零留存）；#49 路径无既有用例（已知缺口）；#88 未对真 API 实测（unverified，判定条件入 §22.9）。

### 2.5 验收对照

| 验收项 | 判据 | 读数 |
|---|---|---|
| 逐笔有落点或明确理由 | §2.2 行数 = §2.1 行数 | 16 = 16（15 笔落 3 档 + 1 笔不落并给理由） |
| 设计档新增行无批号 / 历史 | 新增行 grep `批 N` / `#N` | 0 命中 |
| doc_check 零新增 | 改前 / 改后同参数（`D:\baocode`） | 46 → 46（锚 22 / 宽 24） |
| 设计档读者可核 | 新增 `file:line` 坐标逐条实读 | 已核（代码 / 测试档见 §2.2 与 §1） |

### 2.6 关键决策

| # | 决策 | 理由 |
|---|---|---|
| D-a | #49 落 `ide-git.md` §4.7 | 扫描本体在 `lib/ide/git/repository_scan.dart`，属该档板块（`lib/ide/git/**`）；侧栏只是显示面，五档没有独立的侧栏档 |
| D-b | #97 不落设计档 | `docs/design/` 五档对 `fileUriToPath` / 终端链接零引用——该面整体没有设计档；新建整档超出本轮形式化范围（上抛见 §2.7） |
| D-c | #88 标 unverified、不写「已验证」 | 未对真 API 实测；判定条件写死为真机 Claude 族多轮工具会话（`tool_use` → `tool_result` 往返不 4xx、工具照跑） |
| D-d | U3 / U4 / §12-12 整条删除，不留「已闭合」行 | 已闭合的登记是历史残影，会被后读者当现行缺口（D8）；现状由正文口径承载 |

### 2.7 未覆盖项与上抛

- **留台账**：#80（chip 预览实时，需 IDE→chat 快照 Listenable）· #35（外仓两处设计档措辞，`thincoder/` 为 gitignored 检出）· #63（doc_check 进 CI + 行号改符号引用 + 架构 / 开发 setup 两页）——不在本批。
- **上抛 · 待裁**：#97 缺 owning 设计档——IDE 终端（含链接解析）整体无需求档 / 设计档，五档 grep 零命中；建议单独立「IDE 终端」板块档（需求五要素 + 设计），本轮不新开档。
- **上抛 · 知会**：#49 的台账 board 标记为 `thincoder-adapter`，但落点按代码板块放进 `ide-git`；若板块归属要收正，请主 agent 在台账处理。
- **发现（不阻塞，未动）**：`thincoder-adapter.md` §22.12 的测试档指针 `thincoder/docs/batches/2026-10-19-f19-cli-closure.test.mjs` 已不在盘（零留存收口删除）——状态档引过程档属既有存量，宜并 #63 同族清理。

**§2.5 读数复算（修笔误）**：逐笔处置计数 = **8 笔落 3 档**（§2.2 前 8 行）+ **4 笔夹具 / 断言层明确不落**（#90 / #81 / #77 / #83）+ **3 笔设计档自身已生效**（#53 / #74 / #48，父侧直改）+ **1 笔无档待裁**（#97）= 16，与 §2.1 行数一致；§2.2 共 9 行（8 落 + 1 不落）。上文 §2.5 首行「15 笔落 3 档 / 16 = 16」为笔误，以本行为准。另：`:142` → `:144` 的改写落在三节四处（§22.7-7 一处 / §22.10 两处 / §22.12 一处），§2.3 的「三处」按节计。

### 修正轮 1（设计评审 #77 · changes-required：11 号逐条落点）

| 号 | 落点 `file:line` | 改动 | 回读 |
|---|---|---|---|
| 🔴1 | `docs/design/ide-git.md:533`（⑦）、`:540-541`（⑭ / ⑮）、`:545`（行数注）、`:599`（§12.9 标题）、`:608`（验收 ⑥）、`:513-514`（§12.6-5） | §12.7 补 `command_titles.dart`（599 行）/ `workbench_keybindings.dart`（1355 行）两行（0 增量，行数注同 §12.7 口径）；⑦ 改 3 键并列出 `scmFetchAndPullAll` / `scmFetchAndPull` / `scmBehindCommits`；§12.9 补 ⑥「命令面板 / 快捷键不再出现只 fetch 的旧名」（两源 ARB 键 + 两处调用点，三处同名机检） | 已回读；表 15 行（①–⑮） |
| 🟡2 | `ide-git.md:513-514` | §12.6-5 的键数句 2 → 3，与 §12.7 ⑦ 同步；键名句拆行以守住行宽 | 已回读 |
| 🟡3 | `ide-git.md:199` | §4.3 补「执行面」：步骤 4–8 搬进共享拉取核心（`pullFromUpstream`，§12.2 步骤 4–6）；引擎侧只提供否决器（含按仓重读 `git.autofetch`）并消费 `updated` | 已回读 |
| 🟡4 | `ide-git.md:42`、`:255`、`:281`、`:510` | 删四处失效修订句（「批 12 实现记录」/「批 13 移到」/「不再作为当前形态的依据」），只留当前形态 | 已回读；grep `本行是批` / `批 12 实现记录` / `不再作为当前形态` 零命中 |
| 🟡5 | `docs/design/host-tool-channel.md:377` | ㉑ 增量「清单外加档」→ `≤ +10（httpMcp 实测 +5）` | 已回读 |
| 🟡6 | `host-tool-channel.md:51`、`:53`、`:103`、`:218`、`:227`、`:339`、`:547` | 四处（另 :53 / :103 同族两处）改指 `lib/host_tools/host_tools.dart` 的符号（`handle` / `HostTools.server` / `HostTools.servers`），不再引已删档行号；迁移事实入 §16-1（`:547`） | 已回读；grep `claude_sdk_tools.dart:` 零命中 |
| 🟡7 | `docs/design/thincoder-adapter.md:307`、`:308`、`:333`、`:338` | ⑪ / ⑫ 与实施读数改「本批起点 → 终点」式；现在时读数只留 §5.2 一处（`thincoder_kernel.dart` 现 **1121** 行，2026-10-19 `wc -l` 实测——评审时的 1055 已随其后各批新增过期） | 已回读；grep `现 1195` / `现 799` 零命中；`1055` 仅存 §23.3 的批 11 快照行（自带「勿与 §24.3 现值互校」口径） |
| 🟡8 | `thincoder-adapter.md:3237`、`:3238`、`:3240`、`:3227` | T100 `release()` → `agent.release()`；T101① 补 `agent.release()` 收尾；T103 两处裸 `release()` → `agent.release()`；§24.5 的 T103 行 `release()` → `kernel.release()`（同族） | 已回读（与测试实际调用形 `s.agent.release()` / `s.kernel.release()` 一致） |
| 🔵9 | `ide-git.md:263` | ⑯ 实测 579 → 621（2026-10-19 `wc -l` 实测，含本轮修正） | 已回读 |
| 🔵10 | `ide-git.md:85` | `incomingPaths()` 注明「已被 `pullFromUpstream` 取代，无调用点」；代码侧 `lib/ide/git/git_repository.dart:432` 确无调用点（代码未动） | 已回读 |
| 🔵11 | `thincoder-adapter.md:50` | §2 补公开资料调查（survey-evidence）：ACP v1 schema 相关（取用见 §22 / §23 / §24）、外仓设计档相关；其余无公开源，以代码实读为准 | 已回读 |

**读数**：`doc_check`（`D:\baocode`）改前 46（锚 22 / 宽 24）→ 改后 46（同集合，零新增）；新增行全部 ≤300 字符（中途一处 334 已拆行修正）；被改写的既有表格长行沿用原状（doc_check 表格行豁免）。未改：代码 / 测试 / 需求档 / 他批档、批档 §1 / §3；§12.7 表 15 行；状态行保持「设计完成」。

### 修正轮 2（评审通过后 3 条落地）

| 号 | 落点 `file:line` | 改动 | 回读 |
|---|---|---|---|
| 1 | `docs/design/thincoder-adapter.md:333-334`（§5.2 体量行）· `:3208`（§24.3 表下） | 「现 **1121** 行（2026-10-19 `wc -l` 实测）」→「编制日实测（2026-10-19）**1121** 行」；§5.2 加续行「与 §24.3 起点 1091 差 30 行（两批各记了当时的实测）；实施首轮 `wc -l` 复核，以复核值为准」；§24.3 表下补同一口径（① 的 1091 = 本批编制日起点） | 已回读；两处 kernel 行数均带复核口；不猜哪个数对，差异声明给复核 |
| 2 | `docs/design/ide-git.md:193`（§4.3 步骤 6） | 「取 `incoming = incomingPaths()`」→「取 `incoming` = 核心内 `service.changedPaths('HEAD', upstream)` 的结果（§12.2 步骤 4）」；§3.1 的 `:85` 保留（该方法已被 `pullFromUpstream` 取代、无调用点） | 已回读；§4.3 已无 `incomingPaths()` 串；执行面与 §12.2 步骤 4 同指 |
| 3 | `docs/design/ide-git.md:547`（§12.7 体积档行） | 补「⑭ 599 / ⑮ 1355：净 0 的一行替换，不立新缝；`workbench_keybindings.dart` 1355 行为存量 >800 档，按 §5.1 体积档政策不续拆」 | 已回读 |

**读数**：`doc_check`（`D:\baocode`）改前 46（锚 22 / 宽 24）→ 改后 46（同集合，零新增）；改写 / 新增行宽 69–215（≤300）。`grep -n "incomingPaths()"` = `:85`（§3.1 历史说明）· `:251` / `:280`（§5 既往批次改动记录表内，按「不重排他节」未动）· `:447`（§12.2 步骤 4 的 `incoming = service.changedPaths(...)`，非 `incomingPaths()`）。`1121` 只剩 `:333` / `:3208` 两处，均带复核口。未改：代码 / 测试 / 需求档 / 他批档、§1 / §3；状态行仍「设计完成」。

**两处按档内实际落点收正（派工原文与档内事实不符，报备）**：① 派工点 3 写「按 §5.2 政策」——`ide-git.md` 无 §5.2，体积档政策在 §5.1（`:275`），按 §5.1 写；② 派工写「`workbench_keybindings.dart` 已在 >800 名单」——`ide-git.md` 的 >800 名单（§5.1 表）未含该档，改记其实测 1355 行与「存量 >800 档」。

**发现（不阻塞）**：§5.1（`:275`）字面要求「已在 >500 或 >800 的档，都给缝与触发」——⑭ 599 / ⑮ 1355 按父侧裁定记「不立新缝」，与该字面并存；若日后要给缝，另立拆分批。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

## 轮次 2：前表 11 条复验（1🔴 已闭合）+ 修正轮引入的新问题

| # | Orig# | 文件 | 严重度 | 状态 | 说明 |
|---|-------|------|--------|------|------|
| 1 | 1 | docs/design/ide-git.md | 🔴 | Fixed | 受影响文件表补 ⑭ `lib/l10n/command_titles.dart`（599）/ ⑮ `lib/keybindings/workbench_keybindings.dart`（1355），各记「0（一行替换）」；§12.6-5 改为「l10n 新增 3 键（`scmFetchAndPullAll` / `scmFetchAndPull` / `scmBehindCommits`）」；§12.7 ⑦ 改 3 键 +10/+3 ⇒ 7143/2751；§12.9 新增验收 ⑥（两源 ARB 含键 + 两处调用点标题）。四处落点齐全，原缺档/缺键/缺验收三项全闭。 |
| 2 | 2 | docs/design/ide-git.md | 🟡 | Fixed | 键数自相矛盾消除：§12.6-5 与 §12.7 ⑦ 同为 3 键且键名一致，与 §12.6-4 的按钮 tooltip 需求对得上。 |
| 3 | 3 | docs/design/ide-git.md | 🟡 | Fixed | §4.3 新增「执行面」段：步骤 4–8 明确搬进 `pullFromUpstream`，引擎只提供否决器并消费 `updated` ⇒ 层归属已写。 |
| 4 | 4 | docs/design/ide-git.md | 🟡 | Fixed | 四处修订式残留已删：§2.2 分支栏行、§5 ⑧、§5.1 ide_scm_view 行、§12.6-2 末尾，改指 §12.6 现行形态（无「批 12 实现记录」「不再作为当前形态的依据」字样）。 |
| 5 | 5 | docs/design/host-tool-channel.md | 🟡 | Fixed | §7.1 ㉑ 补增量「≤ +10（`httpMcp` 实测 +5）」，与 ①–⑳ 同形。 |
| 6 | 6 | docs/design/host-tool-channel.md | 🟡 | Fixed | 悬空坐标全部改指活档：§2.2 §4.3 §4.4 §6 引用 `lib/host_tools/host_tools.dart`，旧档只在 §7.1 ①′（删除行）与 §16-1（迁移记录）出现，符合「历史归记录面」。 |
| 7 | 7 | docs/design/thincoder-adapter.md | 🟡 | Unfixed（部分） | ⑪ 的「现 1195」已改为批时形「（本批 1156 → 1195，+39）」——该半条已闭；但体量行改填 `thincoder-adapter.md:333: - `thincoder_kernel.dart`：>800 行触发已执行——拆分前实测 1168 行 ⇒ 拆出 `thincoder_events.dart`…现 **1121** 行（2026-10-19 `wc -l` 实测` ，与 §24.3 起点 `thincoder-adapter.md:3197: ≤ +24（⇒ ≤1115；§21.3 预算 ≤1148，余量 33）` 的（1091）仍互斥，且终点 1115 < 现值 1121 ⇒ 预算终点低于起点。仍缺「唯一现值」。 |
| 8 | 8 | docs/design/thincoder-adapter.md | 🟡 | Fixed | T100/T101/T103 全部改限定形：`agent.release()`（mock 放行）与 `kernel.release()`（视图离开）分开写，与 §18.7「不写裸 `release()`」的规范一致，T100「恰 1 条写」不再有歧义。 |
| 9 | 9 | docs/design/ide-git.md | 🔵 | Fixed | §5 ⑯ 自指行数由 579 改为 `ide-git.md:263: 621（2026-10-19 `wc -l` 实测）`，与当前文件同量级（读回 621 行）。 |
| 10 | 10 | docs/design/ide-git.md | 🔵 | Fixed | §3.1 已定性：`ide-git.md:85: incomingPaths()  已被 pullFromUpstream 取代，无调用点` ⇒ 存活与否已答。（残留见新 #12） |
| 11 | 11 | docs/design/thincoder-adapter.md | 🔵 | Fixed | §2 补 doc 级 survey-evidence 行（ACP v1 schema / 外仓档 / 「其余断言无公开源相关」三分法），原缺项闭合。 |
| 12 | (new) | docs/design/ide-git.md | 🟡 | New | #10 的修正引入自相矛盾：§3.1 说该方法无调用点，§4.3 步骤 6 仍写 `ide-git.md:193: 6. 取 `incoming = incomingPaths()`` 。建议：该步改说「由核内 `service.changedPaths` 计算」（§12.2 步骤 4），或注明此步为概念步、执行面在核心。 |
| 13 | (new) | docs/design/ide-git.md | 🔵 | New | 新增两档未纳入体量口径：`ide-git.md:547: 体积档：② 586（500–800，§5.1 的缝与触发不变：>600 时拆图段）；③ 670（500–800，>700 时拆历史段）；⑥ 4198（>800，>4300 时拆仓库头）。` 未含 ⑭（599）/ ⑮（1355）；按 `ide-git.md:275: 源码档按行数分档：本批改动后跨 500 的档、已在 >500 或 >800 的档，都给缝与触发。` 同批 >800 的 `workbench_keybindings.dart` 应有一行「缝 / 触发」或明记「净 0 不立缝」。 |

计数：前表 11 条 → Fixed 10 · Unfixed 1（🟡，第 7 条部分）· 新增 2（1🟡 + 1🔵）。本轮 🔴 = 0，🟡 = 2，🔵 = 1。

审查边界：三档之外未取源文件（评审范围限定三档）；行数 spot-check 仅做档内互校，与设计自述的「未逐档 spot-check、实施首轮 `wc -l` 复核」一致。

VERDICT: pass

## §4 用户批准（主 agent）

**用户批准（2026-10-19 23:31）**：用户逐字「批准」。

批准对象：本轮 16 笔实现（缺陷 8 + 测试债 5 + 文档卫生 3）+ 三档设计形式化 + 两轮评审（R2 pass，🔴 0）。

裁决表状态：13 行（含 R2 新发现 2 条）全部 **Fixed**，无 Deferred、无驳回；`Dispatched` 已随修正轮 1/2 逐条收敛为 `Fixed`（落点见 §2 修正轮表与 §3 两轮记录）。

## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

**验收读数（父侧复跑）**

| 套件 | 读数 |
|---|---|
| `test/ide/git` | **182/182**（12 条基线红清零） |
| `composer_files_test` + `file_tags_test` | **23/23** |
| `open_editor_test` | **4/4** |
| `thincoder_fixtures_test` | **19/19** |
| `host_mcp_server_test` | **14/14**（含新 T19） |
| `thincoder_kernel_test`（mock 串行档） | **122/122** |
| `flutter analyze`（改动面） | 零新增 |
| `doc_check` | 46 → 46（同集合，零新增） |

**行为面**：C 组 8 笔（#97 链接解析 `FormatException`、#98 命令面板/快捷键标题、#82 chip 读屏键、#91 人读线占位、#89 VSC 机器线剥图、#88 anthropic tool 消息转换、#71 grant 回填、#49 扫描失败一次性提示）；D 组 5 笔（#90/#81/#77/#83 夹具与断言、#28 mock 串行档）；E 组 3 笔（#53 变更记录删除 + ide-git 四则收正 + D19 改写、#74 指针清零、#48 两处机制漂移）。

**评审**：R1 changes-required（1🔴+7🟡+3🔵）→ 修正轮 1（11 号）→ R2 **pass**（🔴 0；10 Fixed · 1 部分 · 2 新发现）→ 修正轮 2（3 号）→ 全部收敛 Fixed。

**诚实面（未闭合项）**：① #49 的通知无 widget 用例覆盖（路径无既有夹具），仅 analyze + 人工读码；② #88 未对真 API 实测（设计档已标 unverified + 判定条件）；③ 本轮无真机走查（改动以机检 + 读码为主，无可见面变化需要用户观感）。

**台账**：16 笔追认核销（#97/#98/#82/#91/#89/#88/#71/#49 · #90/#81/#77/#83/#28 · #53/#74/#48）；本轮行 #100 核销；新登记 #101（workbench/lsp 既有红）/ #102（IDE 终端板块档缺失）/ #103（`incomingPaths()` 死代码）；留账 #80（chip 预览实时）/ #35（外仓两档措辞）/ #63（doc_check 进 CI 等）。

**状态**：已收口 2026-10-19。
