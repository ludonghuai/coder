# 2026-11-05 · thincoder-checkout-and-shell
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-11-05 · 来源 = 用户 2026-11-05 原话「ok,you can deal with issue. and i tell you that thincoder and baocode only used by myself, so thincoder -g install is nothing, i don't use it. you should make it useful」；对象 = 上一轮兼容性审读列出的 13 条。
> 前情 = docs/batches/2026-11-04-thincoder-runtime-0.12.81.md（已收口）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-05

### 本批：只修本机真会撞上的

**口径**：thincoder 与 BaoCode 只有用户本人用，`npm install -g` 那条路不算数；13 条里按本机实况筛，撞得上的才修。

**本机实况（只读取证）**

- 在跑的是 `D:\baocode\build\windows\x64\runner\Debug\baocode.exe`：开发构建，旁边没有 `runtime\`。所以 thincoder 走 PATH，落到 `%APPDATA%\npm\thincoder.cmd`（npm link 到 `D:\baocode\thincoder\thincoder-cli`），由 `cmd.exe /c` 起。
- `~/.thincoder/logs` 近两天：`POSIX-only construct(s) detected … Current shell is cmd.exe` 出现 **261 次**；「路径在项目外被拒」0 次（命中的两处都是测试名）。
- `state.json`：没有 `ssh://` 项目，`sshHosts` 为空；审批档是 `auto`。
- `~/.thincoder/config.json`：`shell` 未设（= cmd.exe）；渠道全是 OpenAI 格式（无 `format` 键）。
- 本机有 Node v24.11.1 与 `C:\Program Files\Git\bin\bash.exe`。

**要修的（3 条）**

| # | 问题 | 处置 |
|---|---|---|
| 1 | 代理的命令在 cmd.exe 里跑，模型写的是 POSIX（261 次提示） | 用户配置 `~/.thincoder/config.json` 的 `shell` 设为 Git Bash：与 thincoder 的 `/shell` 同一笔写（`thincoder-core/config-io.mjs` 的 `persistRaw`），只在未设时写。不改代码 |
| 2 | 开发构建靠全局 npm 链找 thincoder，且经 `.cmd` 垫片起：`Process.kill` 在 Windows 上只杀到 `cmd.exe` | `ThincoderLocator` 加「源码树里的 checkout」一档（内置之后、PATH 之前）：node 直接跑 `thincoder\thincoder-cli\bin\thincoder.cjs`。Settings → General → thincoder 也接受 `.cjs` / `.mjs` / `.js`，同样由 node 跑 |
| 3 | 应用带内置副本时，Settings 指定的 thincoder 也被注入 `THINCODER_CONFIG_DIR` | 只在选中的是内置副本时注入；`environment()`（设置页找 config.json 用）同判 |

设计档同步：`docs/design/thincoder-adapter.md` §26.3（解析顺序与表）、§26.10（D113 / D114）。

**不修的（逐条理由）**

| 上轮 # | 事项 | 为什么不修 |
|---|---|---|
| 1 | npm 上的 thincoder 是上游版、缺 BaoCode 用的扩展 | 用户不用 npm 安装 |
| 2 | SSH / WSL 项目默认起 thincoder 会失败 | 本机没有远程项目；改 `workspace.dart`（上游档）还会加 fork 增量 |
| 3 | `.cmd` 垫片下退出时 node 不死；Windows 不回收残留 | 第 2 条之后开发构建不再经垫片；本机现有 thincoder 进程的父进程都在，没有残留 |
| 5 | macOS 经符号链接打开的项目起不来会话 | 本机是 Windows |
| 6 | 模型设置页写不了 `format` | 现有渠道都是 OpenAI 格式 |
| 8 | 项目外的写入失败 | 日志里没有真实发生 |
| 9 | 审批 5 分钟超时后面板不消 | 审批档是 `auto`，很少弹 |
| 10–13 | Node 版本误读、盘根、大小写分店、图片落盘 | 本机 Node 24；没有盘根项目；fork 版原生收图 |

**红线**：只动 `lib/kernel/thincoder/thincoder_locator.dart`（fork 自有档，`docs/design/fork-deltas.md` 第 2 节 `lib/kernel/thincoder/**`）与两本文档；不动上游档；用户配置只加 `shell` 一个键。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
**状态行**：已收口 2026-11-05

- **checkout 一档**：临时用例（跑完即删，不入套件）从 `build\windows\x64\runner\Debug` 往上找，得到 `C:\Program Files\nodejs\node.exe` + `D:\baocode\thincoder\thincoder-cli\bin\thincoder.cjs acp`，`--version` 报 0.12.81；从临时目录找 ⇒ 无；从源码树 `launch` ⇒ 不带 `THINCODER_CONFIG_DIR`。5 条全过。
- **数据目录**：同批临时用例里，只有内置副本时 `launch()` 与 `environment()` 都带该变量；Settings 指向 checkout 的 `thincoder.cjs` 后两者都不带。
- **既有用例**：`thincoder_locator_test` / `thincoder_kernel_test` / `thincoder_fixtures_test` / `thincoder_catalog_test` / `thincoder_config_store_test` / `test/settings/thincoder_models_page_test.dart`，216 过 / 0 挂（Flutter 3.47.5）。`dart analyze` 该档无问题。
- **shell**：写后 `config.json` 的键为原有六个加 `shell`；thincoder 的 `loadConfig().shell` = Git Bash，`resolveShellIdentity` 判为 `posix`；照 `tools/bash.mjs` 的起法跑 `echo $((1+2))`、单引号分组、`>/dev/null`，退出码 0；node / npm / git 在其下可用。已开着的会话仍是 cmd.exe，新会话起才生效。
