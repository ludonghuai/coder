# 2026-10-26 · fork-realign
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 23:02 逐字「好，按a做」；依据 = fork 融合审计（explore#16）+ 父侧复核。目标 = 把「上游 9 个文件被全局改名」压成「1 个上游文件加 6 行」，降低后续合并成本。。
> 台账 = #186（thincoder-adapter · 归批）。前情 = docs/batches/2026-10-26-upstream-merge-72.md §6（2026-10-26 合并批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 讨论与裁定（主 agent，2026-10-26 23:05）

- **已定决定**：采用 A 案 —— 恢复上游 `lib/kernel/claude_code/claude_sdk_tools.dart`，在其中给 `ClaudeSdkTool` 加 `group` / `picturesOnly` 两个带默认值的字段；`lib/host_tools/host_tools.dart` 只保留注册表 `HostTools` 并加 `typedef HostTool = ClaudeSdkTool;`；上游 9 档的 34 处 `HostTool(` 构造点改回 `ClaudeSdkTool(`。· 用户原话：「好，按a做」 · 时间：2026-10-26 23:02

**为什么做**（父侧实核读数）：

| 事实 | 读数 |
|---|---|
| 上游原名 | `ClaudeSdkTool` / `ClaudeSdkCall` / `ClaudeSdkTools`（`origin/main:lib/kernel/claude_code/claude_sdk_tools.dart`） |
| 我们分支现状 | `ClaudeSdkTool` **0 命中**（全被改成 `HostTool`） |
| `HostTool(` 构造点 | **12 档 34 处**，其中 9 档是上游档（`browser_actions` / `browser_debug_tools` / `browser_history` / `browser_inspect` / `browser_intercept` / `browser_sources` / `browser_tools` / `browser_watch` / `image_tools`） |
| 字段对照 | 上游 `ClaudeSdkTool` 与我们 `HostTool` 的 `name`/`description`/`inputSchema`/`run`/`kind`/`summary`/`files`/`alwaysLoad` **完全一致**；我们多 `group`（`host_tools.dart:79`）与 `picturesOnly`（`:83`），上游零命中 ⇒ 这两个是我们新增的 |

**对 thincoder 的影响（用户 23:01 问）**：**无**。thincoder 适配层只用注册表方法（`HostTools.named` / `anyIn` / `called` / `lookup`，见 `lib/kernel/thincoder/thincoder_events.dart:410`、`thincoder_lifecycle.dart:115`、`thincoder_requests.dart:113-115`），不引用类名；且 `typedef` 保证所有调用点源码不变。

**范围与红线**
1. 动上游档的只有 `claude_sdk_tools.dart` 一处（+2 字段），需登记并在设计里写明「净增 ≤6 行」。
2. `host_tools.dart` 保留 `HostTools` 注册表与 `typedef`；**不得**把注册表逻辑塞回上游档。
3. 9 个上游档只改构造点名（`HostTool(` → `ClaudeSdkTool(`），**不得**改其行为。
4. 我们自有代码（btest / host_mcp_server / thincoder）继续用 `HostTool` 别名，**零改动**。
5. 验收：`flutter analyze --no-pub` 0 error；`test/host_tools`、`test/browser`、`test/kernel/thincoder_*`、`test/platform` 全绿；全量失败数不得高于当前基线（+7107 ~31 −119）。

**不在本批**：D2（删 autofetch 整簇）、D3（`KernelChoice` 搬回）、D4（thincoder provider 面压薄）、登记表 12 处补登（另批 P0-3）。

### 订正：构造点计数口径（主 agent，2026-10-26 23:08）

前文写「上游 9 档的 34 处构造点」**有误**。父侧逐档实数为：

| 范围 | 处数 |
|---|---|
| 上游 9 档（`browser_actions` 7 · `browser_debug_tools` 7 · `browser_history` 1 · `browser_inspect` 3 · `browser_intercept` 1 · `browser_sources` 3 · `browser_tools` 6 · `browser_watch` 1 · `image_tools` 1） | **30** |
| 自有档（`btest_mode.dart` 2 · `host_tools.dart` 声明 1） | 3 |
| `claude_code_translator.dart:962` 对象模式 | 1 |
| **全仓合计** | **34** |

**设计与实施按「上游 9 档 30 处」计**；`btest_mode.dart` 继续用 `HostTool` 别名（红线 4，零改动），`translator` 那一处设计已划为本批不做。§2 的口径无需改。

### 设计评审裁决（主 agent，2026-10-26 23:15）

评审 `9010ee82` 结论 **pass**（🔴 0 · 🟡 9 · 🔵 5），令牌已签发。逐条裁决：**全部接受，一轮修完**（均为文档面，不动设计语义）。

| # | 级别 | 裁决 | 要修什么 |
|---|---|---|---|
| 1 | 🟡 | 接受 | 红线 4 标题「自有代码零改动」与 §7.3 改 `host_tools.dart` 冲突 → 写清适用范围（哪类自有文件在本次改动内） |
| 2 | 🟡 | 接受 | 红线 5 的 `+7107 / ~31 / −119` 三个数无量纲/来源 → 标注各衡量什么、取自哪次运行 |
| 3 | 🟡 | 接受 | `:117` 说 9 档保留 `HostTools.register` 等，但 §7.3 只给 2 档加 import → 逐档写明哪几档仍调 `HostTools.*` |
| 4 | 🟡 | 接受 | `claudeSdkImage` / `claudeSdkText` 两边等价性未记录 → 写进 §7.1/§7.2；不等价则只 re-export 类型 |
| 5 | 🟡 | 接受 | 8 个共享档无 §3 登记行（含 `image_tools.dart` 的自有接线）→ 按五字段补登或声明并入时点 |
| 6 | 🟡 | 接受 | §7.6 五例未映射到测试档 → 逐例标承载档 + 用例名，无覆盖则写明收口方式 |
| 7 | 🟡 | 接受 | `:26` 与 `:106`/`:127` 对同一机制两处描述（改后形态 vs 当前形态）→ 声明 §2 登记的是改后形态 |
| 8 | 🟡 | 接受 | `:182` 留下 26 处未读 → 设计阶段先核是否含「类定义在某档」，结论写进本节 |
| 9 | 🟡 | 接受 | 8 档过 500 行、3 档过 800 无拆分依据 → 补一句：本次结构不变、属存量债、按行数预算治理 |
| 10–14 | 🔵 | 接受 | 给出 `claude_sdk_tools.dart` 改后行数 · `约 189` 改成有界预算 · 定义 D8 · 先例补实现坐标 · 4919 行测试档记入后续拆分批次 |

**边界**：只改 `docs/design/fork-deltas.md` 与本档 §2，不改代码、不改 §7 的设计语义；改完自跑 `doc_check(gate)` 须 PASS。

**令牌**：`2f9d8cbd…`（短时有效）。实施轮待用户批准后派发；若令牌过期，走一轮复核评审重新签发（约 10 分钟），不硬用过期令牌。

### 上抛裁决（主 agent，2026-10-26 23:20）

**① 红线 5 的第三个数**：设计者是对的，我 §1 里写的 `−119` 是**推算值**（全量 `-128` 减去已删的 9 条 SCM 测试），不是实测。口径订正为：

- **实测基准**：`+7107 ~31 −128`（2026-10-26 全量实跑，333 s，见 `docs/batches/2026-10-26-upstream-merge-72.md` §6）
- **本轮门槛**：失败数 **≤ 128**、通过数 **≥ 7107**（不承诺 `−119`；不重跑全量前不拿推算值当判据）

**② `docs/design/host-tool-channel.md` 3 行**（`:260` `class HostTool {` · `:61` · `:415` 正名表述）：**授权另起一轮改**，不塞进本批（本批边界只含 `fork-deltas.md` 与本档；混入会让本批的评审对象再次变动）。已入台账（条件触发：实施前必须完成）。

**③ `claude_code_translator.dart:962` 对象模式**：本批不动，别名保证编译（§7.7 已记）。**知会，采纳。**

**④ 4919 行测试档拆分建议**：**采纳，入台账**（另批，不阻塞本批）。

### 实施前置（主 agent，2026-10-26 23:40）— 两件文档活，先于代码

用户 23:22「好，怎么做」⇒ 顺序确定为：**文档前置 → 复核评审 → 实施 → 另批删 autofetch → 进 main**。

**本轮的文档任务（不涉代码，实施前必须完成）**

1. **#187 · `docs/design/host-tool-channel.md` 三行**：`:260` 的 `class HostTool {`（A 案后该类不再定义于自有档）、`:61` 与 `:415` 把正名记成 `ClaudeSdkTool(s)→HostTool(s)`。改法 = 按 A 案改后的事实重述：`ClaudeSdkTool` 定义在上游档，`HostTool` 是自有档里的别名。
2. **#189 · `docs/design/fork-deltas.md` 登记表整顿**（按 kimi 复核版，**不是**主审的「补 12 行」）：
   - **删 1 行**：`:29` 的 `test/ide/git/scm_fetch_button_test.dart`（该档已 `git rm`）。
   - **补 4 行**：`lib/host_tools/host_mcp_server.dart`（自有资产，group/picturesOnly 消费在 `:238-246`/`:281-284`）· `lib/browser/browser_actions.dart` 的 `picturesOnly: true`（`:105`）· `lib/images/image_tools.dart` 的 `group: 'images'`（`:66`）· **`lib/ide/git/git_repository.dart:871-875` 空仓构建期修复**（下次整档取上游会丢，须登记）。
   - **不补**：`git_settings.dart` / `git_autofetch*.dart` / `git_pull.dart`（随 #184 删除，先登记再删无收益）。
   - **文案**：`:83` 的「八档」→ 实际七档。

**边界**：只改这两档；不改 `fork-deltas.md` §7（已过审的设计主体）；不动代码；改完自跑 `doc_check(gate)` 须 PASS。

### 第 0 步未完成的三件（主 agent 核盘，2026-10-27 00:00）

上一轮（#21）报告称「四项裁决已落地」，父侧逐条核盘结果：

| 应有 | 盘上实况 |
|---|---|
| #189 补 `browser_actions` 行 | ✅ 已有（`fork-deltas.md:58`） |
| #189 补 `image_tools` 行 | ✅ 已有（`:65`） |
| #189 补 `host_mcp_server` 行 | ❓ 未见独立行（仅在其他句子里出现） |
| #189 补 `git_repository.dart:871-875` 行 | ❌ **缺**（全文无 `git_repository` 命中） |
| #189 删 `scm_fetch_button_test.dart` 死行 | ❌ **仍在**（`:30`） |
| #187 改 `host-tool-channel.md` 三行 | ❌ **原样未动**（`:61` / `:260` / `:415` 仍是旧表述） |

**本轮只做这四件，别的一律不碰**（不重写 §7、不动 §2 其他段、不碰代码）：
1. `fork-deltas.md` 删 `:30` 的 `scm_fetch_button_test.dart` 行。
2. `fork-deltas.md` §2 或 §3 补一行 `lib/host_tools/host_mcp_server.dart`（自有资产；group/picturesOnly 消费在 `:238-246` / `:281-284`）。
3. `fork-deltas.md` §3 补一行 `lib/ide/git/git_repository.dart:871-875`（空仓构建期修复 `scheduleMicrotask(_notify)`；不登记则下次整档取上游会再丢一次）。
4. `host-tool-channel.md` 三行按 A 案改后事实重述：`ClaudeSdkTool` 定义在上游 `lib/kernel/claude_code/claude_sdk_tools.dart`，`HostTool` 是自有 `lib/host_tools/host_tools.dart` 里的别名；`:415` 的 D2 决策行同步。

### kimi 复核裁决（主 agent，2026-10-27 01:35）— 可实施，4 处必带进实施单

用户 01:13 给 key、01:14「重新审核一下186」。kimi（explore#35）结论：**能实施，无 🔴**；typedef 四种用法（构造 / 注解 / `is` / 对象模式）**依 Dart 规范全部成立**，§7.7 的「未实测前提」可以销掉。

**父侧已独立核实第 1 条**（最要紧的那条）：

| # | kimi 的发现 | 父侧核对 | 处置 |
|---|---|---|---|
| 1 | 七个浏览器工具档是 `part of 'browser_tools.dart'`，**自身无 import**；设计写「import 换上游路径 1:1」会让 part 档编译失败 | **成立**：`browser_actions` / `browser_debug_tools` / `browser_history` / `browser_inspect` / `browser_intercept` / `browser_sources` / `browser_watch` **七个全是 `part of`**；只有 `browser_tools` 与 `image_tools` 是独立库 | 设计 §7.3 改：**import 只落在 `browser_tools.dart` 与 `image_tools.dart` 两处**（各 +1 上游 import，保留原 `host_tools.dart` import）；其余七档**只改类型名，不碰 import** |
| 2 | 不能按子串替换：`HostTool`→`ClaudeSdkTool` 会把 `HostToolCall` 错成 `ClaudeSdkToolCall`、把 `HostTools` 错成 `ClaudeSdkTools` | 成立（`HostTools` 必须保留） | 实施纪律写死：**按标识符重命名**，三步分开：`HostToolCall → ClaudeSdkCall` · `HostTool → ClaudeSdkTool` · **`HostTools` 不动** |
| 3 | 30 个构造点之外还有类型引用；验收只数 `HostTool(` 会漏 | 成立：`HostToolCall` 全仓 18 处（九档内 4 处 + 自有档 14 处） | §7.5 判据改成**标识符级**：**九个上游档内 `HostTool` 与 `HostToolCall` 均 = 0**；自有档（btest / host_tools / host_mcp_server / claude_code_kernel）继续用别名，**不要求清零** |
| 4 | 现有测试用**合成工具**（`host_mcp_server_test.dart:11-24` 自造 `_tool`），若宽面编辑误删 `picturesOnly: true` / `group: 'images'`，测试仍绿 | 成立（该测试不经过真实注册路径） | 实施后**逐行核三处真值**：`browser_actions.dart:105` `picturesOnly: true` · `browser_tools.dart:116-117` 透传 · `image_tools.dart:66` `group: 'images'` —— 列为硬验收，不许只跑合成用例 |

**另有一处坐标错**：kimi 指出设计 `:147` 把 `HostToolCall` 的引用位置写成 `browser_actions.dart`，该档实为 0 处（真实在 `browser_tools` / `image_tools`）。

**派单**：以上五件（4 条 + 坐标错）派设计者一轮改 `fork-deltas.md` §7，改完即派实施。**令牌 `2f9d8cbd…` 有效至 11-03，无需重签。**

**订正（2026-10-27 01:38）**：上文「`HostToolCall` 全仓 18 处」口径有误——那是我只扫 `lib/` 的读数。设计者按 `\bHostToolCall\b` 扫 `lib/` + `test/` 实测 **38 处**（九档 4 + 自有 `lib/` 8 档 15 + 测试 10 档 19）。**判据不依赖总数**（判的是「九个上游档内两个名字均 = 0」），故不阻塞；此处按实测订正。

**§7.4 B 案那条「静态成员经 typedef 访问未实测」**：驳回 B 案的首因是违反「注册表留自有档」，该前提不承担驳回责任，本轮不动——**知会采纳**。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

### 2.1 本批覆盖的条目

| # | 条目 | 需求来源 | 设计落点 |
|---|---|---|---|
| 1 | 上游 `lib/kernel/claude_code/claude_sdk_tools.dart` 回仓，`ClaudeSdkTool` 加 `group` / `picturesOnly` 两字段（净增 ≤6 行，另有 1 个删除块 = 上游注册表类 `ClaudeSdkTools`） | 批 §1 红线 1 | `docs/design/fork-deltas.md` §7.1–7.3 |
| 2 | `lib/host_tools/host_tools.dart` 只留 `HostTools` 注册表 + `HostTool` / `HostToolCall` 两个 typedef + 上游符号 re-export | 批 §1 红线 2 | §7.2 |
| 3 | 9 个上游档的改名回退（构造点 30 处 + 类型引用 `HostToolCall` → `ClaudeSdkCall`），行为不动 | 批 §1 红线 3 | §7.3 |
| 4 | 自有代码（btest / host_mcp_server / thincoder / 测试档）零改动 | 批 §1 红线 4 | §7.3 表末 |
| 5 | 编译与测试验收 | 批 §1 红线 5 | §7.5 |

### 2.2 设计档落点

`docs/design/fork-deltas.md` §7「宿主工具类型的上游复原」9 项齐全：决策与理由 / 接口契约 / 受影响文件与行数 / 关键决策 / 验收对照 / 用例表 / 边界 / UI 与 open 项 / RTM delta。

同档内同步三处陈述：§2 的 `host_tools.dart` 行改为「注册表 + 两 typedef + re-export」；§3 新增 `claude_sdk_tools.dart` 行（净增 ≤6 行 + 1 删除块）；§4 的 `browser_actions.dart` / `browser_debug_tools.dart` 行改为「按第 7 节复原为 `ClaudeSdkTool` 形态」。

### 2.3 机制要点

- 类型身份：`typedef HostTool = ClaudeSdkTool;`、`typedef HostToolCall = ClaudeSdkCall;`，自有代码名字不变，编译面零改动。
- 注册表仍在自有档：`HostTools`（含 `byGroup` / `anyIn` / `lookup` / `named` 四个自有静态方法）逐字保留；上游 `ClaudeSdkTools` 类整段不取。
- 导入形式：9 档保留上游 import 行，另加自有 import（只有 `browser_tools.dart`、`image_tools.dart` 需要，各行 +1 行）。
- 净增 6 行算术：构造参数 2 行 + 字段 2 行 + 单行文档注释 2 行。

### 2.4 受影响文件

见 `docs/design/fork-deltas.md` §7.3：新建 1 档；`host_tools.dart` 264 → 183–185（净减 79–81）；`browser_tools.dart` 773 → 774、`image_tools.dart` 601 → 602。

其余 6 个上游档行数不变（改名 1:1）；测试档零改动。

### 2.5 验收对照

见 §7.5，五条判据（上游档只动新建档 · 注册表留自有档 · 9 档只改名字 · 自有档零改动 · 编译与测试）各一条机器判据。静态面：`git diff --numstat origin/main -- <新建档>` 增 ≤6 且删除块唯一；新建档内 `static final Map` 计数 = 0；9 档 `HostTool(` 计数 = 0 且 `ClaudeSdkTool(` = 30。

运行面：`flutter analyze --no-pub` 的 error 数 = 0（读命令尾行；与测试失败数不同量纲，分开判）；`flutter test test/host_tools test/browser test/kernel/thincoder_kernel_test.dart test/platform` 全绿。

全量 `flutter test --no-pub`：收尾行失败数 ≤ 128 且通过数 ≥ 7107。来源 = 父侧 2026-10-26 全量实跑（333 s）的 `+7107 ~31 -128`（`+` 通过 / `~` 跳过 / `-` 失败）。§1 写的 −119 在盘上无来源，按 −128 判，差异见 §2.8 #2。

### 2.6 关键决策

采用 A 案：注册表留自有档，上游档只加两字段。B 案（上游档整档回仓、注册表改名 `ClaudeSdkTools`、自有档只留 typedef）能把 9 档残留降到 0，但把注册表塞回上游档、违反批 §1 红线 2，且依赖「静态成员经 typedef 访问」这一未实测的 Dart 前提，故不采用；要清零另行裁定。C 案（保留改名现状）即本批要消除的成本。

### 2.7 上抛项

- **计数口径（已定）**：§1 订正（23:08）裁定按「上游 9 档 30 处」计 —— 7+7+1+3+1+3+6+1+1；另 4 处 = `lib/browser/btest/btest_mode.dart:264/336` 2 处、`lib/host_tools/host_tools.dart:41` 声明 1 处、`lib/kernel/claude_code/claude_code_translator.dart:962` 对象模式 1 处（全仓 34 处）。设计与实施按 30 处计，本项已收口。
- [上抛·待裁] **`host-tool-channel.md` 的 3 行要改**：26 行、32 处命中已逐条读完；其中 `host-tool-channel.md:260` 的 `class HostTool {` 是类定义写法，`:61` 与 `:415` 把注册面正名记成 `ClaudeSdkTool(s)` → `HostTool(s)` —— 这 3 行在本批后与现状相反（本批后 `HostTool` 是 typedef，类回 `claude_sdk_tools.dart`）。其余 23 行是注册表名与别名类型引用，仍成立。该档不在本轮改动面内（§1 边界只含 `fork-deltas.md` 与本档），已记在 `fork-deltas.md` §7.8 open；请父侧裁定是否另起一轮或授权本席改写。
- [上抛·知会] `claude_code_translator.dart:962` 的 `case HostTool(...)` 是对象模式而非构造点，本批不改（§7.7）；把它也复原成 `ClaudeSdkTool(...)` 属下一次精修，未排期。

### 2.8 设计评审整改（14 条，逐条落点）

评审 9010ee82（pass，🟡9 · 🔵5）按 §1 裁决「全部接受，一轮修完」。改动面 = `docs/design/fork-deltas.md` + 本档 §2，代码零改动。

| # | 落点（`docs/design/fork-deltas.md`） |
|---|---|
| 1 | §7.5 首条判据改题为「自有档零改动（`lib/host_tools/host_tools.dart` 除外）」，正文写清允许改动的自有档只有该档、其余四类零改动，与判据文件集同源；§7.4 A 行同口径 |
| 2 | §7.5「编译与测试」给量纲与比较式：analyze = error 数 0；全量 = 失败 ≤ 128 且通过 ≥ 7107，来源 = 父侧 2026-10-26 全量实跑（333 s）的 `+7107 ~31 -128`。**同轮发现**：§1 红线 5 写 `−119`，盘上唯一来源是 −128（`docs/batches/2026-10-26-upstream-merge-72.md:420`），本档按 −128 判 |
| 3 | §7.3 新增「`HostTools.` 引用」列，逐档给数：`browser_tools` 4 处（`:89/91/98/100`）· `image_tools` 2 处（`:46/48`）· 其余 7 档 0；§7.2 同一句改写 |
| 4 | §7.1 调查证据补等价性结论：两边 `claudeSdkImage` / `claudeSdkText` 签名与函数体逐字相同（自有 `host_tools.dart:87-97`，上游同段以 `:85` 收尾）⇒ re-export 不改 `run` 的返回值 |
| 5 | §3 补 8 行登记，五字段齐全：`browser_actions` · `browser_debug_tools` · `browser_history` · `browser_inspect` · `browser_intercept` · `browser_sources` · `browser_watch` · `image_tools` |
| 6 | §7.6 加「承载用例」列：`host_tools_test.dart:69` / `:295`、`host_mcp_server_test.dart:140` / `:196`。结论 = 五例全部有现有用例承载，测试档零改动、不新增用例 |
| 7 | §1 规则补一条：第 2 / 3 节登记的是改后形态，现状读数见 §7.3 的「现状行数」列 |
| 8 | §7.8 换成读后结论（26 行 / 32 处命中）：3 行须改（`:260` 的类定义写法、`:61` 与 `:415` 的正名记录），其余 23 行成立。该档在本轮改动面外 ⇒ 本档 §2.7 [上抛·待裁] |
| 9 | §7.3 补「体量立场」：8 档过 500 行、3 档过 800，均为上游共享档；本批结构不变、属存量债；不拆档的理由写明（拆档＝两处常驻 fork 差异，与「上游可优先合并」相抵） |
| 10 | §7.2 / §7.3 给 `claude_sdk_tools.dart` 改后行数 **91**（229 − 144（`:86`–`:229`）+ 6）；§3 该行同步 |
| 11 | §7.3 把「约 189」换成有界 **183–185 行**（净减 79–81；移出 `:14`–`:98` 共 85 行，加 import / export / 两 typedef 4–6 行） |
| 12 | §7.8 去掉无定义的「D8」，改成直述「旧句删除、不留改写痕迹」。D8 在本仓各设计档各有别义（`host-tool-channel.md:421` 是图片决策、`chat-streaming.md:251` 是不拆档决策），不能作跨档引用 |
| 13 | §7.1 最近先例补实现坐标：`lib/chat/chat_session.dart:32`（带 `show` 过滤的 re-export）+ `lib/chat/chat_models.dart:5` |
| 14 | §7.3 体量立场末句：`test/kernel/thincoder_kernel_test.dart`（4919）属存量债，本批零改动，拆分按后续拆分批 —— 建议父侧记一条台账行（本席无台账写权） |

**同轮顺手修的文档面（均在 `fork-deltas.md`）**：

- 新增「行数口径」一行：本表行数 = 按 `\n` 切分的元素数，`wc -l` 少 1。15 个读数逐一实测，与表中数全部差 1（同一口径），故不改数、只把口径写明。
- §7.5 标题去掉「回指批 §1 红线」、§7.4 去掉「违反批 §1 红线 2」、§7.7 去掉「结果写进批档 §5」：状态档不指批档（批档可整档删除），判据自带内容。
- 本人引入的一处坏字符（`` `:`14`–`:98` `` 多一个反引号）已在同轮修正。

**交付门**：`doc_check(mode:"gate")` 对 `docs/design/fork-deltas.md` = **PASS**（首跑 REFUSED 3 段过长，同轮拆段后复跑 PASS）。

### 2.9 §1 上抛裁决（2026-10-26 23:20）的落点

父侧 23:20 对 §2.7 的三项与一项知会作出裁决。本轮改动面仍 = `docs/design/fork-deltas.md` + 本档 §2，代码零改动。

| 项 | 裁决 | 落点（本轮已落） |
|---|---|---|
| ① 失败阈值口径 | 按实测 `+7107 ~31 −128` 判，不承诺 −119 | 无需改：`docs/design/fork-deltas.md` §7.5 与 §2.5 都已写「失败 ≤ 128 且通过 ≥ 7107」，来源写明父侧全量实跑 333 s |
| ② `host-tool-channel.md` 3 行 | 另起一轮改写，不塞进本批 | `docs/design/fork-deltas.md` §7.8 的 open 项改为「这 3 行的改写在单独一轮落地，不在本批改动面：本批不碰该档；该轮落地后本条撤除」。台账 #187（条件触发，复启句 = 「#186 实施前完成」）⇒ 本批实施须等该轮落地 |
| ③ `claude_code_translator.dart:962` 对象模式 | 知会，采纳 | 已在 §7.7 边界：本批不改，复原属下一次精修 |
| ④ 4919 行测试档拆分 | 采纳，入台账 | 已在 §7.3 末句「本批零改动，拆分按后续拆分批处理」；台账 #188（认账不排期） |

§2.7 的 [上抛·待裁] 项由本条收口。§2 是 append-only，原行按原样保留。

**同轮读数**（本轮实测，非沿用）：

- `docs/design/host-tool-channel.md` 的 `HostTool` 命中：**26 行 / 32 处**，与 §7.8 记的数一致。
- 3 行的坐标逐条读过：`:260` = `class HostTool {`；`:61` = 「注册面正名（`ClaudeSdkTool(s)` → `HostTool(s)`，文件迁 `lib/host_tools/`）」；`:415` = D2 决策行「注册面正名 `HostTools` / `HostTool` / `HostToolCall`」。
- 台账两行在盘：#187（`resume_when` = 「#186 实施前完成（否则实施后该档记录与代码相反）」）· #188（认账不排期）。

**交付门**：`doc_check(mode:"gate")` 对 `docs/design/fork-deltas.md` = `DOC-CHECK GATE: PASS`（0 段过长）。

### 2.10 文档前置轮（§1 23:40 两件文档活，2026-10-26）

改动面 = `docs/design/host-tool-channel.md` 3 行 + `docs/design/fork-deltas.md` 登记表；代码零改动。§2.8 / §2.9 已落的整改不重述。

**#187 · `host-tool-channel.md` 3 行按 A 案改后事实重述**

| 位置 | 改后形态 |
|---|---|
| §2.2 偏离第 2 条 | 注册表 `HostTools` 与 `HostTool` / `HostToolCall` 两 typedef 在 `lib/host_tools/`；类型类名保留上游原名，定义在 `lib/kernel/claude_code/claude_sdk_tools.dart` |
| §4.7 注册面代码块 | 类头改 `class ClaudeSdkTool`（注明所属上游档，只加末两字段）；块尾加自有档两行 typedef |
| §8 D2 | 决策改「注册面留自有档」；理由写搬注册表与搬类型名各自的合并代价 |

D2 原句末的「**提交拆分**：改名先以独立提交落地…」同轮删除：该改名方向本批回退，句子所指的提交拆分已无对象，按「失效表述删除、不留痕迹」处理。

**#189 · `fork-deltas.md` 登记表整顿（§1 23:40 第 2 件）**

| # | 项 | 处置 | 读数（本轮实测） |
|---|---|---|---|
| 1 | `scm_fetch_button_test.dart` | 第 2 节该行改为只留 `test/ide/git/git_autofetch_test.dart` | `test/ide/git/` 下无该档；`git_autofetch_test.dart` 在盘 |
| 2 | `lib/host_tools/host_mcp_server.dart` | 第 2 节新增行（自有资产） | `_offered` `:281-285` · `tools/list` 记组 `:246` · `tools/call` 拒组外 `:259-266` 三处读过 |
| 3 | `lib/ide/git/git_repository.dart` | 第 3 节新增行：空仓 / 未出生分支经 `scheduleMicrotask(_notify)` 通知，预算净增 ≤5 行 | `:871-875` = 4 行注释 + 1 行代码 |
| 4 | `browser_actions.dart` 的 `picturesOnly: true` | 已在盘：第 3 节该行早已登记 `:105`，不重复加行 | `:105` = `picturesOnly: true,` |
| 5 | `image_tools.dart` 的 `group: 'images'` | 已在盘：第 3 节该行早已登记 `:66` 与 `HostTools.unregister` `:46` / `register` `:48` | `:66` = `group: 'images',`；`:58` 今用 `HostTool(` 构造 |
| 6 | 「八档」→ 七档 | 第 6 节 `lib/chat/session/**` 行的档数改为七 | `lib/chat/session/` 实列 7 档：file_edits / kernel_proxy / lifecycle / mode_state / overlay / send_contexts / transcript_proxy |

§1 写的「补 4 行」实测 = 2 行新登记 + 2 行已在盘（第 4、5 项）：按坐标核过后不重复登记。

**连带一致性修正（越过「不改 §7」边界，请父侧确认）**：`fork-deltas.md` §7.8 的 open 项原文称这 3 行「本批后与现状相反」、「改写另有单独一轮、本批不碰该档」。§1 23:40 把 #187 划入本轮，改完后该表述与两档现状相反 ⇒ 改写为「关联档已对齐…本节无 open 项」。这是 §7 内唯一改动，只动定位陈述，不动设计语义。

**验收 / RTM**：本轮纯文档、无业务可观察结果变化，`fork-deltas.md` §7.9 的 RTM delta = none 不变；不新增集成用例，测试档零改动。

**交付门**：`doc_check(mode:"gate")` 对两档 = `DOC-CHECK GATE: PASS`（0 段过长）。首跑 REFUSED 1 段：`host-tool-channel.md:313` 的「grant 的会话键」段属存量、非本轮改动行；按同轮修正纪律拆成两段，文字零改动，复跑 PASS。

**上抛项**

- [上抛·待裁] `docs/requirements/host-tool-channel.md:13` 仍写「浏览器工具是 `HostTool`…（`lib/host_tools/host_tools.dart`；原 `ClaudeSdkTool(s)`，A 轮改名）」。本批后类名回上游、`HostTool` 只是自有档别名，该括号在实施后与代码相反。需求档改笔在主 agent，本席只报不改。建议改为：类型 = 上游 `ClaudeSdkTool`（`lib/kernel/claude_code/claude_sdk_tools.dart`），自有档以 `typedef HostTool` 提供别名，注册表 `HostTools` 在自有档。

### 2.11 kimi 复核五件 + §7.7 前提（设计修正轮，2026-10-27）

改动面 = `docs/design/fork-deltas.md` 一档；代码零改动。改的是实施面与判据的精度，§7 的设计语义（A 案、注册表留自有档、净增 ≤6 行）未变。来源 = §1「kimi 复核裁决」表的四件 + 坐标错一件；第六件 = 同节末句「§7.7 的『未实测前提』可以销掉」。

| # | 发现 | 落点（`fork-deltas.md` 现行行号） | 改法 | 本轮读数（实测） |
|---|---|---|---|---|
| 1 | 七个浏览器工具档是 `part of 'browser_tools.dart'`，自身无 import；「import 换上游路径 1:1」会让 part 档编译失败 | §7.2 `:136` · §7.3 `:147`–`:155` · §7.5 `:183` | 七档只改类型名、import 零改动；import 只落 `browser_tools.dart` 与 `image_tools.dart`，各 +1 行（恢复上游 `claude_sdk_tools.dart` import，保留自有 `host_tools.dart` import） | 逐档实读 `:1`：`browser_actions` / `browser_debug_tools` / `browser_history` / `browser_inspect` / `browser_intercept` / `browser_sources` / `browser_watch` 七个全是 `part of`。上游 `browser_tools.dart:12` 与 `image_tools.dart:12` 都是 `import '../kernel/claude_code/claude_sdk_tools.dart';`，现状 `browser_tools.dart:12` / `image_tools.dart:11` 是自有 import ⇒ 恢复上游行即与上游逐字相同、只多一行新增 |
| 2 | 不能按子串替换：`HostTool` → `ClaudeSdkTool` 会错改 `HostToolCall` / `HostTools` | §7.2 `:136` · §7.5 `:182` | 改写按标识符三步、次序固定：`HostToolCall` → `ClaudeSdkCall`、`HostTool` → `ClaudeSdkTool`、`HostTools` 不动；判据加一条「diff 不含 `ClaudeSdkToolCall` / `ClaudeSdkTools`」 | 九档 `HostTools` 引用 6 处（`browser_tools` 4 · `image_tools` 2）；子串误改会被该判据抓到 |
| 3 | 30 个构造点之外还有类型引用；只数 `HostTool(` 会漏 | §7.3 `:153` / `:155` / `:157` · §7.5 `:182` · `:185` | 判据改标识符级：九档内 `HostTool` 与 `HostToolCall` 均 = 0；自有档与测试档继续用别名、不清零 | 九档类型引用 7 处：`browser_tools.dart:72` `List<HostTool>` · `:136` `HostTool tool,` · `:138` `HostToolCall call,`；`image_tools.dart:58` 返回类型 `HostTool` · `:169` / `:262` / `:268` `HostToolCall`。合计改写 37 个标识符位 = 30 + 7 |
| 4 | 现有测试用合成工具，宽面误删 `picturesOnly` / `group` 时测试仍绿 | §7.5 `:184` 新增硬判据 | 三处真值逐行读回，不许只跑合成用例；理由写进判据（`test/host_tools/host_mcp_server_test.dart:11-24` 的 `_tool()` 自造带两字段的工具，不经过真实注册路径） | 三处本轮实读：`browser_actions.dart:105` = `picturesOnly: true,` · `browser_tools.dart:116` = `group: 'browser',` 且 `:117` = `picturesOnly: tool.picturesOnly,` · `image_tools.dart:66` = `group: 'images',` |
| 5 | 坐标错：`HostToolCall` 的引用被记在 `browser_actions.dart` | §7.3 `:147`（该档改为「类型引用 0 处」）· `:153` / `:155` | 按逐档实测改回真实位置 | `browser_actions.dart` 的 `HostToolCall` = 0；真实 4 处 = `browser_tools.dart:138` 一处 + `image_tools.dart:169` / `:262` / `:268` 三处 |
| 6 | §7.7 的「未实测 Dart 语义前提」可销掉 | §7.7 `:203`，尾段整段删除 | 改陈述句：`typedef` 是类型别名，构造调用、类型注解、`is` 判定与对象模式四种用法都按别名解析 | 删掉的是「实施时第一次编译即验证 + 若不成立就落回 `ClaudeSdkTool(...)`」那段兜底；首条边界仍写「本批不改 `claude_code_translator.dart:962`」 |

**§7 之外的一处一致面自修（按纪律逐条报）**：§3 `:43` 的 `browser_tools.dart` 行接缝名从 `HostTool` / `HostTools` / `HostToolCall` 改为 `ClaudeSdkTool` / `HostTools` / `ClaudeSdkCall`。依据 = 本档 §1 `:15` 的规则「第 2 / 3 节登记的是改后形态」：原行写的是改前形态，与本批改后的 §7.3 相反。只改类型名，登记内容与行数预算不动。

**同轮未动**：§7.4 `:172` 的 B 案行仍写「静态成员经 typedef 访问…本仓未实测」。B 案的驳回首因是违反「注册表留自有档」，该前提不承担驳回，本轮不改。

**交付门**：`doc_check(mode:"gate")` 对 `docs/design/fork-deltas.md` = PASS。首跑前自查发现一段 400 字超限（§7.3 表后的合计段），同轮拆成两段，文字零改动。

**上抛项**

- [上抛·待裁] **§1「kimi 复核裁决」表第 3 条的全仓总数与实测不符**：该行写「`HostToolCall` 全仓 18 处（九档内 4 处 + 自有档 14 处）」；本席按 `\bHostToolCall\b` 扫 `lib/` + `test/` 得 **38 处**，拆开 = 九档 4 处（`browser_tools` 1 · `image_tools` 3）+ 自有 `lib/` 8 档 15 处（`host_tools.dart` 5 · `host_mcp_server.dart` 2 · `btest_mode.dart` 2 · `btest_expect_file` / `btest_run_end` / `btest_run_state` / `btest_tool_gate` 各 1 · `claude_code_kernel.dart` 2）+ 测试 10 档 19 处（`btest_expect_file_test` 6 · `host_tools_test` 3 · `btest_policy` / `btest_tool_gate_test` 各 2 · 其余 5 档各 1）。「九档内 4 处」与实测一致；差异只在全仓总数，且设计不依赖总数（判据按「九档 = 0」）⇒ 未阻塞本批，请父侧订正 §1 口径或说明 18 的统计范围。复现 = 对 `lib/` 与 `test/` 逐个 `.dart` 扫 `\bHostToolCall\b` 计数。

**2.11 行号订正（同轮）**：2.11 表内的「现行行号」是在拆段之前记的 —— §7.3 的合计段从 400 字拆成两段时 +2 行，其后所有行号整体后移 2。落盘后按节名 + 内容复核的真值（行号只作定位）：

- §7.4：import 决策行 = `:176`，B 案行 = `:174`（记录里写的 `:172` 已失效）。
- §7.5：标识符级判据 = `:184`、import 面 = `:185`、三处真值 = `:186`、别名不清零 = `:187`（记录里写的 `:182`–`:185` 各后移 2）。
- §7.7：首条边界（`translator:962` 不改）= `:204`（记录里写的 `:203` 后移 1）。
- 与本轮记录一致、无需订正：§3 `:43`、§7.2 `:136`、§7.3 `:147` / `:153` / `:155` / `:157` / `:159`。

复核方式 = 按每行的唯一内容串逐条定位（`fork-deltas.md` 当前 321 行）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

评审对象：`docs/design/fork-deltas.md`（全文，193 行）。评审范围按调用声明限定在该文件，故文中对他档的行数/计数结论（`origin/main` 229 行、`HostTool(` 34 处、§7.3 各档行数）本轮一律按 `unverified` 处理；已核的是文档内部算术与自洽性：7+7+1+3+1+3+6+1+1=30 ✓、30+2+1+1=34 ✓、264−81+6=189 ✓、2+2+2=6 ✓。项目无 AGENTS.md、无项目标准档、无文档地图 ⇒ 方法学与文档归属两项按降级口径判定。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | 验收 / 需求覆盖 | 🟡 | 红线 4 标题与 §7.3 冲突：`docs/design/fork-deltas.md:156` 写「红线 4：自有代码零改动」，而 `:127` 把 §2 登记为自有的 `lib/host_tools/host_tools.dart` 从 264 行改到约 189 行（「移出 4 个声明（`HostToolCall`、`HostTool`、`claudeSdkImage`、`claudeSdkText`，约 −81 行）」）。机器判据的文件集把该档排除在外，标题却按全量理解；实施者按标题核对会判红线不成立。 | 把这条红线的适用范围写清（哪一类自有文件在本次改动内、哪一类必须零改动），使标题与其 `git status` 文件集一致。 |
| 2 | 验收 | 🟡 | `:157` 的「全量失败数不高于基线（+7107 / ~31 / −119）」三个数没有定义各衡量什么、取自哪次运行、比较式是什么；`analyze` 的 error 数与测试失败数量纲也不同，读者无法判定是否达标。 | 为每个数标注量纲、来源运行与比较式；否则该条不可机器判。 |
| 3 | 清晰度 | 🟡 | `:117` 说 9 个上游档「`HostTools.register` / `unregister` / `instruct` 保留（注册表归自有档）」，但 §7.3 只给 `browser_tools.dart`（`:134`）与 `image_tools.dart`（`:136`）加 import，其余七档写「import 换上游路径 1:1」（`:128`）——没有 `host_tools.dart` 的 import 就调不到 `HostTools.*`。两种读法导出的实施结果不同（多出未登记 import，或丢失注册调用）。 | 在 §7.3 逐档写明哪几档仍调用 `HostTools.*`、其余档是否只构造工具。 |
| 4 | 可行性 | 🟡 | `:116` 用上游符号 `show ClaudeSdkTool, ClaudeSdkCall, claudeSdkImage, claudeSdkText` 取代自有档的四个声明，而 `:105` / `:106` 只并列了两边同名符号的存在，未记下两处 `claudeSdkImage` / `claudeSdkText` 的签名与实现是否等价。若不等价，冻结的自有调用点（`:107` 点名的 `lib/browser/btest/btest_mode.dart:264/336` 2 处）语义会变，与红线 4 及 §7.8 的「无界面变化」结论冲突。 | 把两边这两个 helper 的签名/实现对照结论写进 §7.1 或 §7.2；不等价就只 re-export 类型，helper 留自有档。 |
| 5 | 文档归属 | 🟡 | 本设计改动的 8 个共享档没有 §3 登记行，其中 `lib/images/image_tools.dart` 明确保留自有接线「保留 `group: 'images'`」（`:136`）与 2 处 `HostTools.`；按本文档自己的规则 `:7`「先登记文件、块、类型、接缝和行数预算，再改代码」与 `:72`「表外发现自有块时先补第 3 节」，这类自有块应先登记。§7.3 只给文件与行数，缺「类型 / 接缝 / 行数预算」三项；browser_actions 与 browser_debug_tools 仅由 §4（`:66`）带过，其余六档无任何表行。 | 把这 8 档按 §3 的五个字段补齐（纯改名档可用「结构不变」作预算），或明确声明 §7.3 在本批实施后并入 §2/§3。 |
| 6 | 验收 | 🟡 | §7.6 的五个用例（`:163`–`:167`）没有映射到断言它们的测试档，而 `:138` 同时写「测试档零改动」。像 `:164`「正常 · 别名构造」与 `:166`「边界 · 纯图片工具」这类行为，回归时读者无法知道该看哪个文件哪条用例；§7.5 的验收只给到目录级运行。 | 为每个用例标出承载它的测试档与用例名；若无覆盖，写明本批以编译与定点手工核对收口。 |
| 7 | 文档归属 | 🟡 | 同一机制两处描述不一致：`:26` 把自有档 `lib/host_tools/host_tools.dart` 的块写成「`HostTool` / `HostToolCall` 两个 typedef 与上游符号 re-export」（改后形态），而 `:106` 与 `:127` 把它描述成现在仍在该档里的类声明（「`HostTool`（`:40-84`，多 `group` `:79`、`picturesOnly` `:83`）」）。表中没有标记区别「已登记的改后形态」与「当前形态」，按 §2 现读会与仓库现状相反。 | 在 §2 该行声明它登记的是改后形态（或加一列标记未实施），使表与 §7.3 的现状列可互证。 |
| 8 | 文档归属 | 🟡 | `:182` 主动留下未核项：「的 26 处 `HostTool` 表述未逐条读语义」，处置为实施时若发现再「按 D8 改那一句」。若该文档把 `HostTool` 描述成某档的类定义，改动后即同一机制两处不同描述（机制级矛盾），而本设计阶段无人核过。 | 设计阶段先核这 26 处是否含「类定义在某档」的表述并把结论写进本节；不能核就登记成有主的 open 项，而不是实施时顺带发现。 |
| 9 | 行数 / 结构 | 🟡 | §7.3 点到的 8 个档已过 500 行档、其中 3 个过 800（`browser_debug_tools.dart` 1786、`browser_sources.dart` 1566、`browser_inspect.dart` 1169），设计没有拆分计划，也没写这类上游共享档为何不适用拆分规则（本文档 `:10` 只把规则落到自有文件：「自有文件用「自有」标记，仍受既有结构拆分规则约束」）。这些档本次行数不变，属存量债（R3），不据此阻塞，但规则与豁免依据都缺一句。 | 在本节补一句：这些档本次结构不变、属存量债，并说明上游共享档按 §3 行数预算治理而不拆分（或给出拆分意见）。 |
| 10 | 清晰度 | 🔵 | `lib/kernel/claude_code/claude_sdk_tools.dart` 的改后行数不可算：`:115` 只给「上游 229 行 − `ClaudeSdkTools` 类整段（在文件尾）」与 +6，被删类段的行数全文未出现，`:126` 的期望变化只重复同一算式。 | 给出该段行数与改后文件行数，让 +6 预算与红线 1 的删除块判据可对账。 |
| 11 | 清晰度 | 🔵 | 受影响表以结果值代替预算：`browser_tools.dart`「⇒ 774」、`image_tools.dart`「⇒ 602」可核，但改得最多的自有档写「⇒ 约 189 行」（`:127`），「约」无上下界，−75 行的改动不成其为预算。 | 把该行改成有界的净增/净减（或「结构不变」），与 §1 的行数预算口径对齐。 |
| 12 | 清晰度 | 🔵 | `:182` 的处置引用「按 D8 改那一句」，本文档未定义 D8；同类引用（批 §1 红线、§29.2 / §29.5）都带所在文档，D8 没有。 | 给 D8 补所在批档编号或节号，使实施者能定位。 |
| 13 | 先例 | 🔵 | 「最近先例」（`:101`）的坐标是本文档 §3 的登记行「第 3 节 `lib/chat/chat_models.dart` 行的 `editor_context.dart` re-export」，不是已实现代码或先例批次；它证明形态一致，不证明该形态在本仓跑通过。 | 若 re-export 形态已在代码里成立，补一处实现坐标（档 + 符号）作先例，让「对齐」有可查落地实例。 |
| 14 | 备注 | 🔵 | `:138` 把「`test/kernel/thincoder_kernel_test.dart`（4919）」当主要回归面，而 `:10` 说自有文件仍受拆分规则约束；这是 R3 的存量债，本批不改该档。 | 在后续批次登记该测试档的拆分意见，本批不处理。 |

已通过的面（不另列条目）：设计档在位；最近先例行在（`:101`）；调查证据行在（`:103`–`:109`，含「查过，无外部相关来源」的显式记录）；受影响文件表在（`:122`–`:138`）且内部算术自洽；§7.9 集成测试设计从 `test/RTM.md` 出发，被破坏/冗余/缺失三项逐项给出，用的正是唯一可接受的理由（本批不改业务可观察结果、无新增真实场景）；未新增输入∥状态分支 ⇒ 分支来源（6b）不适用；§7.4 三案对照与 §7.7 边界把范围收紧，§7.6 覆盖正常/边界/错误三类；`:176` 把 Dart 别名的未实测语义前提显式标出并给了回落路径。

§3 未写入：工具「batch」在本回合可调用，本节即由它落盘。若父侧未见本节，以「§3 未写入」为准。

VERDICT: pass（无 🔴；🟡 9 项 · 🔵 5 项，均不阻塞）

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）

**状态行**：实施完成（审计 + 独立代码评审均 pass，修复轮 0；全量测试留父侧 §6）

### 5.1 交付摘要（新建 1 档 · 改 10 档）

设计 §7.3 的行数预算逐档命中：新档 91 行；`host_tools.dart` 264 → **185 行**（预算 183–185 的上界，净减 79）；`browser_tools.dart` 773 → **774**；`image_tools.dart` 601 → **602**；六个纯改名档行数不变。

| 文件 | 变化 | 读数（本轮实测） |
|---|---|---|
| `lib/kernel/claude_code/claude_sdk_tools.dart` | 新建：上游档逐字 + `group` / `picturesOnly`；注册表类 `ClaudeSdkTools` 不取 | `git diff --numstat origin/main` = **6 增 / 144 删**；删除块唯一（上游 `:86`–`:229`）；改后 **91 行** |
| `lib/host_tools/host_tools.dart` | 移出 4 个声明（`HostToolCall` / `HostTool` / `claudeSdkImage` / `claudeSdkText`）；留 `HostTools` 注册表逐字 + 两 typedef + import / export | `:14-15` re-export；`:17-18` 两 typedef；`abstract final class HostTools` 在 `:21` |
| 7 个 part 档（actions / debug_tools / history / inspect / intercept / sources / watch） | 只改标识符，import 零改动 | 逐档 diff 7/7 · 7/7 · 1/1 · 3/3 · 1/1 · 3/3 · 1/1（各 = 该档构造点数） |
| `lib/browser/browser_tools.dart` | +1 上游 import；构造点 6 + 类型引用 3 改名 | diff 10 增 / 9 删；`HostTools.` 4 处逐字保留 |
| `lib/images/image_tools.dart` | +1 上游 import；构造点 1 + 类型引用 4 改名 | diff 5 增 / 4 删；`HostTools.` 2 处逐字保留 |

设计 §7.5 八条判据的静态面实读（编译与测试见 5.4）：

| # | 判据 | 读数 |
|---|---|---|
| ① | 上游档只加两字段、增 ≤6、删除块唯一、91 行 | 6 / 144 / 唯一 / 91 ✓（见上表） |
| ② | 注册表留自有档 | 新档 `static final Map` = 0；`abstract final class HostTools` 在自有档 ✓ |
| ③ | 九档标识符级 = 0 | `HostTool` = 0 · `HostToolCall` = 0 · `ClaudeSdkTool(` = **30** · `HostTools` = **6**；九档 `git diff origin/main` 的 `+` 行内 `ClaudeSdkToolCall` = 0 · `ClaudeSdkTools` = 0 ✓ |
| ④ | 九档 import 面 | 七档 `:1` 仍为 `part of 'browser_tools.dart';`；两档各恰 +1 行，其余 import 逐字相同 ✓ |
| ⑤ | 三处真值逐行读回 | 内容全在原位，坐标为改前值 +1（见 5.3）✓ |
| ⑥ | 自有档与测试档别名不清零 | lib `HostToolCall` 13 行 + test 19 处；lib `HostTool(` 3 处 + test 9 处 ✓ |
| ⑦ | 自有档零改动（`host_tools.dart` 除外） | `git status --porcelain` = 10 M + 1 A，与 {`lib/browser/btest/**`, `lib/host_tools/host_mcp_server.dart`, `lib/kernel/thincoder/**`, `test/**`} 交集为空 ✓ |

合并面收益：九档相对上游的总差异从「121 增 / 57 删」降到「**87 增 / 21 删**」，其中 6 行是设计预期的注册表名 `HostTools.` 残留。

### 5.2 决策披露（越出设计逐字描述的每一处，逐条给理由）

| # | 改动 | 为什么 | 偏差级别 |
|---|---|---|---|
| 1 | 删 `host_tools.dart` 原 `import '../chat/chat_models.dart' show ToolCallItem, ToolKind;` | 该 import 的两个符号只被移出的 `HostTool` / `HostToolCall` 使用，留着会新增 `unused_import`。删后 185 行，仍在 §7.3 预算内 | 设计未逐个列 import，属必然连带；净减 79–81 的不变量未破 |
| 2 | 新档保留上游 `import 'dart:async';`（该档已无使用点） | 红线 1 要求删除块只有 `ClaudeSdkTools` 一段，删它会生第二个删除块。实测 analyze 未报 `unused_import`，故按设计保留且无代价 | 无偏差（先怀疑、后实测排除） |
| 3 | 两新字段各 1 行文档注释、与相邻成员之间无空行 | §7.2 的 +6 行算术 = 构造参数 2 + 字段 2 + 单行注释 2；加空行即 8 行，破「增 ≤6」的机器判据 | 按设计算术执行；代价 = 该处样式比同档其它成员更密 |
| 4 | `browser_tools.dart:13` / `image_tools.dart:13` 各新增 1 条 `unnecessary_import` info | 设计 §7.4 选定「恢复上游 import + 保留自有 import」；自有档 re-export 同四符号 ⇒ 直接 import 冗余。按设计执行 | 成本已披露，不改代码（见 5.5 未采纳项） |

### 5.3 真值坐标（设计 §7.5 写的是改前坐标）

| 目标 | 设计坐标 | 盘上实读 |
|---|---|---|
| `picturesOnly: true,` | `browser_actions.dart:105` | `:105` ✓（part 档，无 import 变动） |
| `group: 'browser',` | `browser_tools.dart:116` | `:117`（`:116` = 注释 `// group would not show there.`） |
| `picturesOnly: tool.picturesOnly,` | `browser_tools.dart:117` | `:118` |
| `group: 'images',` | `image_tools.dart:66` | `:67`（`:66` = `alwaysLoad: true,`） |

### 5.4 编译与测试读数

SDK = `D:\baocode\build\flutter-3475\flutter\bin\flutter.bat`（Flutter 3.47.5 / Dart 3.13.4，与 `.dart_tool/version` 一致；PATH 上的另一个 Flutter 与 `.dart_tool` 哈希不符，跑测试会报 `Invalid SDK hash`，故用本仓这份）。

- `flutter analyze --no-pub` → **0 error**；9 issues，其中本批新增 2 条 info（5.2 #4），其余 7 条落在未触及的 test 档。
- `flutter test --no-pub test/host_tools test/browser test/platform` → **All tests passed（+233 ~8）**。
- `flutter test --no-pub test/kernel/thincoder_kernel_test.dart test/images/image_tools_test.dart` → **All tests passed（+164）**。
- 全量 `flutter test --no-pub`：**本席未跑**。理由 = 项目 `CLAUDE.md:3` 只许跑改动相关档，且全量是父侧收尾门。§7.5 第 8 条第③项留给 §6（门槛：失败 ≤128 且通过 ≥7107）。

### 5.5 审计与评审轮次（终态 clean）

| 轮 | 类型 | 结论 |
|---|---|---|
| 1 | 内部偏离审计（explore，只读） | §7.5 八条 + §2.1 五条全 PASS；越清单改动 0、行为偏离 0；4 条发现全在文档坐标面 |
| 2 | 独立代码评审（advisor code） | VERDICT **pass**（🔴 0 · 🟡 3 · 🔵 2），无一标「批准前必修」 |
| 修复轮 | — | **0 轮**：无代码项可改；三条 🟡 是设计档 / 登记表文字与一处已披露的 lint 成本，改代码反会破红线 1 |

**未采纳的两条（理由留父侧裁）**：

- 评审 🔵「`host_tools.dart:1` 头注释仍在描述已移出的类型」：修它要删 4 行，落到 181 行、破 §7.3 的 183–185 预算。按设计留，改法并入下一轮调预算时处理。
- 评审 🟡「`unnecessary_import` 两行」：删掉即恢复本批要消除的常驻差异，故不删；该成本需在 §3 登记表加一句「禁随 lint 清扫删除」（eng-designer 面）。

### 5.6 文档面发现（本席不改，交父侧路由）

1. `docs/design/fork-deltas.md:186` 的三处真值坐标是改前值，逐档 +1（真值见 5.3）。
2. `docs/design/fork-deltas.md:187` 把 `host_tools.dart:41` 的 `HostTool(` 声明列为「逐字不变」，与同表 `:188` 及盘上相反 —— 该声明正是本批移出的那 4 个之一；九档外 `HostTool(` 现为 lib 3 处（`btest_mode.dart:264` / `:336`、`claude_code_translator.dart:962`）+ test 9 处，`HostToolCall` 为 lib 13 行 + test 19 处。
3. `docs/design/fork-deltas.md:65` / `:153` 的定位坐标是改前值（+1）：`image_tools.dart` 注册接线现为 `:47` / `:49`，`browser_tools.dart` 的 `List<ClaudeSdkTool>` 在 `:73`。
4. `docs/design/fork-deltas.md` §7.2 的「229 − 144 + 6 = 91」按内容行计；§7.1 的行数口径写「按 `\n` 切分计数」，按该口径上游读 230、改后读 92。两种口径差 1，建议 §7.1 口径行标明本条算术用内容行。

## §6 验证与收口（父代理）
