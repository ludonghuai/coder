# 2026-10-21 · thincoder-embedded-runtime
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-21 · 来源 = 用户 2026-10-21 03:53–03:57「让用户自己在终端用自己下载上游 thincoder；baocode 我们偷偷运行自己的版本」「单独吧，安全」「baocode 就直接嵌入我们的 thincoder，他们的就自动屏蔽了」。
> 台账 = #132（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-21
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论（主 agent）

**用户诉求（逐字，2026-10-21 03:53–03:57）**
1. 「我只是让用户自己在终端用自己下载上游thincoder；然后baocode我们偷偷运行自己的版本，让他们不认可也认可」
2. 「只是发行版这样做，我这里开发不需要这样子，都用自己的」
3. 「可以，单独吧，安全」
4. 「那我们的baocode就直接嵌入我们的thincoder，他们的就自动屏蔽了」
5. 「不要影响到我们的开发环境，只有发行版才这样做，打包带时候！！！」

**落定的决策**

| # | 决策 | 依据 |
|---|---|---|
| 1 | 发行版内置 thincoder 副本；用户终端那份不碰、不接管、不改 PATH | 用户 1 / 4 |
| 2 | **屏蔽 PATH**：内置副本存在时只认内置 + 用户显式路径 | 用户 4 |
| 3 | **独立数据目录**（`THINCODER_CONFIG_DIR`），用户 `~/.thincoder` 不被写 | 用户 3「单独吧，安全」 |
| 4 | **开发环境零变化**：无内置副本 ⇒ 照旧 设置路径 → PATH；禁 `kReleaseMode` 特判与开发开关 | 用户 2 / 5 |
| 5 | 内置副本构建源 = 本仓 `thincoder/` 工作树当前 HEAD | 主 agent 默认（与发版代码严格一致）；用户若改主意可随时推翻 |

**B1 例外（外仓）**：用户 2026-10-21 03:58「外仓可以」⇒ 批准 `THINCODER_CONFIG_DIR`（`thincoder-core/config-io.mjs:32` 的 `configDir` 读 env 覆盖，约 3–5 行）。

**本批不做**：不接管用户终端、不改 PATH、不写 `~/.thincoder`、不做活会话跨端（#36）、不让内置副本独立升级、不动上游发布流程。

**待定**：内置副本的**体积预算**（Node SEA 预计 +40–60 MB）用户尚未明确表态；设计需给出实测值，实施前由用户确认。

**用户取消（2026-10-21 19:14）**：逐字「算了不管了，取消安装包下载任务吧」⇒ 本批停止，不进入评审与实施。

未完成的面（如实记）：
- 设计档 §26 已写完（14 小节、机检门 PASS），但**不实施**；其 SEA 否选的四条判据与四格表作为将来参考保留在档。
- 外仓 `THINCODER_CONFIG_DIR`（6 档 8 处）**未动手**——工作树零改。
- 本仓 `thincoder_locator.dart` / `tool/build_windows.dart` / `tool/baocode.iss` **零改**。
- 台账 #132 撤回（已废弃）。

> 不适用：§3 —— 用户 2026-10-21 19:14 取消本批，设计评审未点火。
> 不适用：§4 —— 同上，未进入批准环节。

## §2 批次任务与设计（eng-designer）
**状态行**：✅ 设计完成 2026-10-21（F23 ①–⑤ 设计落 §26；打包 spike 已实测；外仓改动面 6 档 8 处（已批准）；SEA 不选、取等价形态；macOS 未验证）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

设计轮交付 · 批 17（F23 内置运行时）

**本批条目（覆盖）**
- F23 ①：内置副本优先且屏蔽 PATH（显式 → 内置 → PATH；内置存在即不构造 PATH 候选）。
- F23 ②：独立数据目录（`THINCODER_CONFIG_DIR` 注入，用户 `~/.thincoder` 零写）。
- F23 ③：开发环境零变化（`flutter run` / `flutter test` 走 PATH，行为逐字不变）。
- F23 ④：显式 `thincoder.path` 优先于内置；坏路径报错不回落。
- F23 ⑤：LICENSE（MIT）随安装包分发。

**明确不在本批**：实施（本仓 locator / 打包脚本 / 外仓改动）归后续实施轮；macOS 打包只给设计、本机不验证；不做单文件 SEA（D107）；不做内置副本独立升级；不接管用户终端 / 不改 PATH / 不写 `~/.thincoder`；不做活会话跨端（#36）。

**设计档落点**：`docs/design/thincoder-adapter.md` §26（26.1 形态 · 26.2 打包 spike 实测 · 26.3 候选顺序与四格表 · 26.4 locator 机制 · 26.5 数据目录 · 26.6 开发环境不受影响 · 26.7 启动与日志 · 26.8 打包改动 · 26.9 受影响文件 · 26.10 决策 D107–D112 · 26.11 用例 T112–T117 · 26.12 验收对照 · 26.13 边界与回滚 · 26.14 未验证）。

**机制设计（摘要）**
1. 内置形态 = `runtime\node\node.exe`（85.7 MB 实测）+ `runtime\thincoder\` 源码树（≈6.8 MB 实测，零构建直接可跑，`--version` = 0.12.76）+ LICENSE。
2. 解析顺序：显式设置 → 内置（`<exe 目录>\runtime\thincoder\bin\thincoder.cjs` 存在且 `runtime\node\node.exe` 存在）→ PATH。内置命中时不调用 `candidates()`（机检 = 计数桩零调用 + `events.log` 启动行点名内置绝对路径）。
3. 分叉判据只有「内置在不在」，无 `kReleaseMode`、无编译期开关、无默认值变化（用户 2026-10-21 03:57 逐字约束）。
4. 数据目录：宿主 `launch()` 注入 `THINCODER_CONFIG_DIR=<应用数据目录>\runtime-data\thincoder`；外仓 `configDir` 读 env。
5. 打包：Node v24.11.1 按 OpenSSH 先例版本 + SHA-256 钉死下载；`_putRuntime` 从工作树复制；`--version` 与 `thincoder-cli\package.json.version` 不等即 `_fail`（构建源 = 工作树 HEAD，用户 03:58 落定）。

**打包可行性（实测结论）**：源码树零构建可跑；SEA 不选（动态 import、16 处 `import.meta.url` 资产读、注入需 postject、体积不省），取等价形态「源码树 + 内嵌 node 目录」；SEA 的验证步骤写在 §26.2 备查。

**受影响文件与测试覆盖**
- 本仓：`thincoder_locator.dart`(227→≈+70) · `thincoder_transport.dart`(87→≈+8) · `thincoder_process_io.dart`(207→≈+10) · `tool/build_windows.dart`(425→≈+90) · `tool/baocode.iss`(342→≈+3) · `tool/build_macos.dart`(631→≈+45，未验证) · 新增 `test/kernel/thincoder_locator_test.dart`(≈+160) · `test/kernel/thincoder_kernel_test.dart`(4299→≈+40)。
- 外仓 `thincoder/`（已获批准，本批不实施）：新增 `thincoder-core/home.mjs`(≈18) + `config-io.mjs` / `log.mjs` / `dispatch-gates.mjs` / `skills.mjs` / `helpers.mjs` 共 6 档 8 处调用点，≈ +30 / −7。

**验收对照（F23 ①–⑤）**
- ① 未装 node/npm/thincoder 可用 → §26.1 / §26.8（干净机走查 + T116）。
- ② 启动行点名内置绝对路径、无 PATH 候选 → §26.7 + T113。
- ③ 用户 `~/.thincoder` 文件数与 mtime 不变 → §26.5 PowerShell 两读数 + T116。
- ④ 显式坏路径报错不回落 → T114（沿用今天 `:97-107`）。
- ⑤ `flutter run` 走 PATH 与今天一致 → T112 + 本仓 `flutter test`。

**关键决策**：D107 不做 SEA · D108 内置放安装目录 · D109 分叉判据 = 内置在不在 · D110 坏路径不回落 · D111 env 注入不改上游默认 · D112 外仓改动面 6 档 8 处（只改 config-io 不满足 F23 ③）。

**回滚单位（三处独立）**：① 打包改动（回退后无 `runtime\`，自动走 PATH）；② locator 改动（回退后回「显式 → PATH」）；③ 外仓改动（独立仓提交；须与内置副本同时回退，只回退外仓会恢复写 `~/.thincoder`）。

**[上抛·知会] 外仓改动面大于验收口径的「3–5 行」**：实测 `~/.thincoder` 另有 4 档 7 处绕过 `configDir` 直写（`log.mjs:58`、`agent/dispatch-gates.mjs:21`、`skills.mjs:94/:136/:217/:226`、`agent/helpers.mjs:403`），只改 `config-io.mjs:32` 时 logs / tool-errors 仍写用户目录 ⇒ F23 ③ 不达标。已按「可实施」写进 §26.5（外仓改动已获用户 03:58「外仓可以」），实施归外仓批。

**[上抛·知会] 单文件 SEA 判为不可行**，取「源码树 + 内嵌 node 目录」等价形态（验收 ② 允许「或等价」）；判据与将来验证步骤见 §26.2。

**未验证项（单列）**：macOS 打包（签名 / 双架构 / 执行位）· 安装包体积增量 · `skills.mjs:136` 写面 · token 文件名 · `DataDirectory` 私有子目录访问器名。

## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

## 验证与收口（主 agent）

**本批未交付任何代码**，因此无实施读数。收口依据 = 状态核对：

| 面 | 读数 |
|---|---|
| 本仓 `lib/**` | `git status` 无 `lib/` 改动 ⇒ 零改 |
| 外仓 `thincoder/` | 工作树零改（`THINCODER_CONFIG_DIR` 未动手） |
| 打包脚本 | `tool/build_windows.dart` / `tool/baocode.iss` 未动 |
| 设计档 | §26 已写完，机检门 PASS（content 留档供将来参考，不实施） |
| 台账 | #132 撤回（已废弃），撤回理由与重启条件已写入 |
| 未定项 | 体积（+92.5 MB 未压缩）、外仓扩面（6 档 8 处）随取消一并搁置 |
