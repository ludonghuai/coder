# Git 系统代理（ide-git）设计档

> 板块：IDE 的 Git 面（`lib/ide/git/**` + `packages/bao_remote` 的 git 执行）· 需求档：`docs/requirements/ide-git.md` · 范围仓：baocode。
> 本档只写**本仓 Git 面现在是什么样**。git 子进程的代理继承是它承载的机制；SCM 面板 / 获取 / 拉取采用上游形态（Fetch 与 Pull 是两个动作，没有自动获取）。

## 1. 模块目标与范围

BaoCode 的 git 子进程自动跟随 Settings → Network 解析出的系统代理，用户不用手配 `git config http.proxy`。
范围 = 本机 `runGit` 的子进程环境 + `lib/main.dart` 的那一处接线。

**不做的事**：不做后台自动获取；仓库头的获取按钮只 fetch，不把远端合入当前分支——SCM 面与上游同形。

## 2. 做法与理由

### 2.1 做法一句话

`main.dart` 启动网络代理之后注入一个闭包；`runGit` 每组装一次子进程环境就求值一次，把 `ProxyRoute.environment` 的变量交给 `Process.run`。git 自己的 `http.proxy` 配置优先于环境变量。

### 2.2 最近先例对照（对齐 ∥ 偏离及理由）

**先例来源声明**：`docs/design/` 其余四档（chat-streaming / forge-accounts / host-tool-channel / thincoder-adapter）都没有「git 子进程环境」的同形章节；本节的实现坐标是唯一先例来源。

**本节写的都是现态**：代理面（环境注入、超时档、设置键）早已落地，本批（删自动获取簇）对它零改动。本批动到哪些档，只看 §5 一张表。

| 面 | 先例 | 照抄的形 |
|---|---|---|
| 系统代理读取 | `lib/network/network_proxy_io.dart:228-256`（`readSystemProxy`：Windows `reg.exe`）；`lib/network/proxy_settings.dart:457-513`（`ProxyEnable` / `ProxyServer` / `ProxyOverride`） | 直接复用，不重写 WinINET / macOS `scutil` 读取 |
| 子进程环境口径 | `lib/network/proxy_settings.dart:294-313`（`ProxyRoute.environment`：大小写两套变量 + `NO_PROXY`） | git 子进程用同一份 env（`off` 清空、`system` 回退环境变量） |
| 环境注入点 | `packages/bao_remote/lib/src/git/git_runner.dart`（`runGit` / `_runLimited` 两处 `Process` 调用） | 两处都走同一个 `gitProcessEnvironmentMap()`，远端 host 不注入（null） |

对齐：上游 VS Code 的 git 扩展把 Fetch 与 Pull 分成两个动作、没有自动获取（`extensions/git/src/commands.ts`，2026-10-19 读）——本仓的 SCM 面与它同形，不另造。

偏离（逐条给理由）：

1. **代理走环境变量，不走 `-c http.proxy`**。`ProxyRoute.environment` 已是 app 与 Claude Code 共用的口径（`lib/network/network_proxy_io.dart:134-135`）；`-c` 会把代理（可能带凭据）写进进程命令行。
   代价：git 自己的 `http.proxy` 配置优先于环境变量（`Documentation/config/http.adoc` 逐字：`http.proxy` overrides `http_proxy`/`https_proxy`/`all_proxy` 环境变量）——用户显式配的 gitconfig 保持优先。
2. **网络命令超时 300 秒，其余 60 秒**（现态）。落在 `packages/bao_remote/lib/src/git/git_runner.dart:40-76`：`gitLocalTimeout` 60 秒、`gitRemoteTimeout` 300 秒，`gitTimeoutFor(arguments)` 取 argv 里第一个非全局项选档（`-c` / `-C` 的值跳过）。理由：大仓 / 慢代理下一次 fetch 可能超过 60 秒，被杀了就永远成功不了；本地与远端 host 同时受益。`merge` 也列放宽档：它不联网，但大量写工作树，被 60 秒杀掉会留下半合并（`MERGE_HEAD` / 冲突标记），收拾代价高于一次慢合并。

### 2.3 公开资料调查（survey-evidence）

| 来源 | 取了什么 | 用在哪 |
|---|---|---|
| Dart `Process.run` API（`api.flutter.dev/flutter/dart-io/Process/run.html`，2026-10-19 读） | `environment` 覆盖父进程；`includeParentEnvironment` 默认 `true`，父环境合并、传入项优先。 | 只传增量代理变量，其余环境（PATH、`HOME`、凭据配置）照旧继承。 |
| git `Documentation/config/http.adoc`（同一日读） | `http.proxy` 覆盖 `http_proxy` / `https_proxy` / `all_proxy` 环境变量。 | §3.4 的优先级：gitconfig 显式项 > 应用注入的环境变量 > 直连。 |
| VS Code `extensions/git/src/commands.ts` + `package.json`（`raw.githubusercontent.com/microsoft/vscode/main`，2026-10-19 读） | `git.fetch` 只 fetch、`git.pull` 拉取，是两个命令；`git.autofetch` 是上游自己的后台开关。 | 本仓 SCM 面与上游同形；本仓不提供自动获取（用户裁定）。 |
| 本仓 WinINET 读取（`lib/network/proxy_settings.dart:457-513`、`lib/network/network_proxy_io.dart:236-243`） | `reg.exe query HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`，读 `ProxyEnable` / `ProxyServer` / `ProxyOverride`；`<local>` 映射为 simple-hostnames 绕过。 | 不新增注册表代码；`ProxyRoute` 现成。 |

## 3. 接口契约

### 3.1 分层与数据流

```text
main.dart（startNetworkProxy 之后）
  └─ setGitProcessEnvironment(() => NetworkProxy.instance.current.environment)   ← 1 行接线；闭包每次 spawn 求值（§3.4）

runGit（packages/bao_remote/lib/src/git/git_runner.dart）
  └─ environment: gitProcessEnvironmentMap() = {GIT_TERMINAL_PROMPT, GIT_EDITOR, GIT_OPTIONAL_LOCKS} + 注入项

IdeGitRepository（lib/ide/git/git_repository.dart）
  └─ _operate：一次操作 = 入队 → 执行 → 末尾一次强制 status 刷新（所有写操作共用）
```

### 3.2 设置键（settings.json）

Git 面**不新增键**，也不读自己的键：

- 代理复用 Settings → Network 的 `http.proxyMode` / `http.proxy`（`lib/network/proxy_settings.dart:21-24`），与 app、Claude Code 同一份。
- 用户 settings.json 里若残留 `git.autofetch` / `git.autoPull` / `git.autofetchPeriod`，本产品**不再读它们**，文件保持原样（不迁移、不清洗；未读键无害，改用户数据超出本批权限）。

### 3.3 git 命令与超时

| 用途 | argv（`runGit` 会前置 `--no-optional-locks -c core.fsmonitor=false`） | 备注 |
|---|---|---|
| fetch（既有） | `fetch <remote> --tags`；`fetch --all --tags` | 作用域 = 单仓全部 remote；工作区全仓遍历由视图逐仓调用本行 |
| 超时策略 | `runGit` 按命令名：放宽档 = `fetch` / `pull` / `push` / `ls-remote` / `clone` / `submodule` / `merge` ⇒ 300 秒；其余 60 秒 | 纯函数 `gitTimeoutFor(arguments)`，可单测 |

`IdeGitService` 现在没有 `fastForward` / `merging` / `abortMerge` / `changedPaths`：它们随自动获取与「获取 = 真拉取」一起删除（消费者只剩被删的那条拉取链）。`merge(ref)` 保留——`git_branch_actions.dart:146` 仍在用。

### 3.4 代理继承契约

- **注入点**（现态，本批零改动）：`packages/bao_remote/lib/src/git/git_runner.dart` 的 `setGitProcessEnvironment(Map<String, String> Function()? value)`；`runGit` 与 `_runLimited` 都用 `gitProcessEnvironmentMap()` 作 `environment`。`null` = 不注入（远端 host 的 server 进程即如此）。
- **变量**：直接返回 `ProxyRoute.environment` 的键（`HTTP_PROXY` / `http_proxy` / `HTTPS_PROXY` / `https_proxy` / `NO_PROXY` / `no_proxy`，`ALL_PROXY` 两种拼写在 `off` 时清空）。值域：
  - `http.proxyMode = system`：系统代理（WinINET / macOS `scutil`）；系统无代理时回退 app 进程的环境变量；两者都无 ⇒ 空 map（让 git 继承父环境）。
  - `http.proxyMode = manual`：`http.proxy` 的 URL（`ProxyServer.url`，含 userinfo）。
  - `http.proxyMode = off`：变量置空串 ⇒ git 直连（覆盖继承来的代理变量）。
- **优先级**（自上而下）：`~/.gitconfig` 的 `http.proxy` > 应用注入的环境变量 > 父进程环境 > 直连（§2.2 偏离 1）。
- **生效时机（每次 spawn 求值）**：注入的是闭包；`runGit` 每组装一次子进程环境就同步读 `NetworkProxy.instance.current.environment`（`current` 是同步 getter，`lib/network/network_proxy_io.dart:46`），值 = `NetworkProxy` 最近一次解析的结果。
  - Settings → Network 改 `http.proxyMode` / `http.proxy`：变更监听触发重解析（`network_proxy_io.dart:50-61`），重解析完成后**下一次 spawn 即用新值**（在途的那次仍用旧值）。
  - 系统代理在运行中变更：要等 `resolve()` 再次执行——app 客户端 10 秒老化重读（`connectionMaxAge`，`network_proxy_io.dart:43-46` / `:124-129`）、Settings → Network 的 Refresh（`currentProxyRoute()`，`:258`）或重启 app；即需求档的「重启生效」。
- **范围**：只影响本机 `runGit`；远端工作区的 git 在 host 上跑，用它自己的环境（§10）。

## 4. 仓库扫描的失败面（侧栏 Sources）

侧栏按 `git.autoRepositoryDetection` 找项目文件夹下的仓库（`lib/ide/git/repository_scan.dart`）。这一面是现态，本批不动；实现在 `lib/workbench.dart:3763-3819`（`_scanWarned` 所在的那组方法）。

- 扫描失败时记一条 `appEvent('sidePanel', 'repository scan failed: …')`；本轮面板不列仓库，30 秒后自动重试，不是永久放弃。
- 同一位置只提示一次 warning（键 `scmScanFailed`：「暂时无法扫描这里的仓库，稍后自动重试。」/ "Can't look for repositories here right now; trying again shortly."）；一次成功即清提示标记（`_scanWarned`）。
- 理由：失败若静默，面板的「没有仓库」会被用户当成事实；重试成功后面板照常列出，不需要用户动作。

## 5. 受影响文件清单（本批）

行数 = 2026-10-27 实测（`\n` 计数，等价 `wc -l`：末行换行不另算一行）。

| # | 坐标（实测） | 改动 | 预算后 |
|---|---|---|---|
| ① | `lib/ide/git/git_autofetch.dart`（300） | 整档删除：设置解析 / `decideAutoPull` / 失败分类 / issue 模型 | 0 |
| ② | `lib/ide/git/git_autofetch_engine.dart`（410） | 整档删除：`IdeGitAutoFetch`（定时器 / 触发面 / 并发池 / 去重通知） | 0 |
| ③ | `lib/ide/git/git_pull.dart`（52） | 整档删除：`IdeGitPullMode` / `IdeGitPullOutcome` / `IdeGitPullVeto` / `ideGitPullIssue` | 0 |
| ④ | `lib/settings/pages/git_settings.dart`（112） | 整档删除：三个假控件（两个开关 + 周期下拉） | 0 |
| ⑤ | `lib/settings/pages/general_page.dart`（844） | 删 `:487`（`GitSettingsGroup` 挂载）与该 import | ~842 |
| ⑥ | `lib/ide/git/git_repository.dart`（1007） | 删 `lastFetchAt`（`:86-89`）· `autoFetchIssue`（`:91-99`）· `_markFetched`（`:101-106`）及其三处调用（`sync` / `fetch` / `pull`）· `clock` 字段与构造参数（只为 `lastFetchAt` 存在）· `pullFromUpstream`（`:688-747`）· `fastForward`（`:749-755`）· 两个 import（`:20` / `:22`）；`_enqueue` / `_operate` 回退成上游 `Future<void>` 形态——两者现为 `Future<…>` 泛型，只为承载 `pullFromUpstream` 的返回值；拉取链删掉后没有返回值可带，签名回上游 | ~903 |
| ⑦ | `lib/ide/git/git_service.dart`（1704） | 删 `fastForward`（`:788`）· `merging`（`:806`）· `abortMerge`（`:817`）· `changedPaths`（`:825`）——消费者只有被删的那条拉取链 | ~1654 |
| ⑧ | `lib/l10n/app_en.arb`（9170）/ `app_zh.arb`（3405） | 删 21 键（两档同名）及其 `@` 元数据（`@` 块在 en 模板档）：`scmFetchAndPullAll` · `scmFetchAndPull` · `scmBehindCommits` · `generalSettingsGit` · `generalSettingsGitAutofetch` · `generalSettingsGitAutofetchDescription` · `generalSettingsGitAutoPull` · `generalSettingsGitAutoPullDescription` · `generalSettingsGitAutofetchPeriod` · `gitPeriodMinutes` · `gitLastFetched` · `gitAutoFetchDirty` · `gitAutoFetchDiverged` · `gitAutoFetchLimit` · `gitAutoFetchBuffered` · `gitAutoFetchFilesMore` · `gitAutoFetchNetwork` · `gitAutoFetchProxy` · `gitAutoFetchAuth` · `gitAutoFetchConflict` · `gitAutoFetchOther`（实测坐标 en `:8893-9049` / zh `:3349-3381`） | ~9099 / ~3374 |
| ⑨ | `lib/l10n/app_localizations.dart`（20505）/ `_en.dart`（12579）/ `_zh.dart`（11913） | `flutter gen-l10n` 重新生成（不手改） | 生成物 |
| ⑩ | `test/ide/git/git_autofetch_test.dart`（1104）· `test/ide/git/git_pull_real_test.dart`（362） | 被测对象删除 ⇒ 同批删 | 0 |
| ⑪ | `docs/requirements/ide-git.md`（29） | 已按删除后的现态改写（本批内由主 agent 完成）：标题「Git 系统代理（ide-git）需求」，§2 只留代理继承与复用既有设置两条，§4 两条验收 | 29（无残项） |
| ⑫ | `docs/design/ide-git.md`（214） | 本档：按删除后的现态重写（只留系统代理与仓库扫描两面） | 本档 |

删除面判据 = **无消费者**（本批编制时 grep 读数，按 `lib/**/*.dart` 全量）：

- `lastFetchAt` / `autoFetchIssue` / `pullFromUpstream` / `ideGitAutoFetch*` 的命中只剩定义处与被删测试档。
- `merging` / `abortMerge` / `changedPaths` / `fastForward` 的命中只在 `git_repository.dart` 的 `pullFromUpstream` 与被删的 `fastForward` 包装里。
- 实施首轮以同一 grep 复核一次；命中不在预期内 ⇒ 停下报告，不自行扩大删除面。

### 5.1 体积档的缝与触发（>500 / >800）

`lib/l10n/*.arb` 是本地化资源、`app_localizations*.dart` 是 `flutter gen-l10n` 的生成物（权威是生成器，手改会被下次生成覆盖）——两者不属源码行数档，行数档判的是人能自由重排的源码；`test/**` 不属源码行数档（单测随批删）。

| 档（编制时 → 实施后） | 档位 | 本批碰法 | 缝（拆出点） | 触发 |
|---|---|---|---|---|
| `lib/ide/git/git_service.dart`（1704 → ~1654） | >800 | 只删 4 个方法 | 历史 / 图查询命令段 ⇒ `git_history_service.dart` | 存量债：下次碰历史命令段 |
| `lib/ide/git/git_repository.dart`（1007 → ~903） | >800 | 删状态字段与拉取核心；回退两个泛型 | 图加载段（`loadMoreGraph` / `_reloadGraph` / `_loadGraph`）⇒ `git_repository_graph.dart` | 存量债：下次碰图段 |
| `lib/settings/pages/general_page.dart`（844 → ~842） | >800 | 只删 2 行 | IDE 设置分组段 ⇒ `ide_settings_group.dart` | 存量债：下次碰 IDE 设置分组，或文件 >900 行 |

`git_repository.dart` 删完仍 >800：拆图段是独立一轮的事，本批不拆（拆了会把一次删除跨两个文件，评审面变大）。

## 6. 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | 代理 = 环境变量注入 `runGit` | 复用 `ProxyRoute.environment`，与 Claude Code 同口径；不进命令行。被否：`-c http.proxy`（凭据进 argv，且盖掉用户 gitconfig）；新增 `git.proxy` 设置（复用网络页即可） |
| D2 | `runGit` 按命令名给 300 秒（放宽档），其余 60 秒 | 慢代理 / 大仓下 60 秒必杀；策略在 runner 内，本地与远端 host 同时生效。被否：全局放宽（status 卡死 5 分钟）；给协议加 timeout 字段（跨仓面变大） |
| D3 | 删除而非保留空壳：引擎档、三个设置控件、l10n 键、仓库侧残留一并删 | 引擎的唯一构造点已随合并消失；控件写设置但无人消费 ⇒ 假开关，留着比删掉更误导。被否：保留设置项与引擎档「以后可能再用」（死代码要每批重新认一遍，且假开关一直在） |
| D4 | 仓库侧残留一并删，含 `service.merging` / `abortMerge` / `changedPaths` / `fastForward` | 判据 = 无消费者；只删引擎会留下一层没人用的拉取原语。被否：只删引擎与设置页（残留仍在，下一批还要认一遍） |
| D5 | l10n 删键 + `flutter gen-l10n` 重新生成，`arb` 与生成物同批 | 键无消费者 = 死文案；只删调用不删键会留下永不出现的字符串。被否：只删调用点 |
| D6 | 用户 settings.json 里的 `git.autofetch` 等三键不动、不迁移 | 未读键无害；删用户数据超出本批权限。被否：启动时清洗（写用户配置文件，风险大于收益） |
| D7 | 需求档 / 设计档删失效三节，系统代理面保留 | 失效表达式删除、不留尸体；代理是本档现在唯一的机制。被否：保留章节加「已废弃」标注 |
| D8 | 每删一组单独提交 | 单笔可回退（A 引擎 / B 控件 + 挂载 / C 仓库侧 / D 测试档 / E l10n / F 文档），任何一组出问题只回退那一笔 |
| D9 | `git_service.dart` / `git_repository.dart` / `general_page.dart` 删后仍 >800 行，本批不拆 | 拆会把一次删除跨两个档，评审面变大；三档是存量债，缝与触发点见 §5.1。被否：本批顺手拆图段 / 历史命令段（把删除批与结构批混成一笔，回退粒度也糊了） |

## 7. 验收对照（回指本批 §2 条目）

| 条目 | 设计落点 | 机检 | 走查 |
|---|---|---|---|
| §2-1 A 组（引擎与设置档） | §5 ①②③④ | `lib/ide/git/git_autofetch.dart`、`git_autofetch_engine.dart`、`git_pull.dart`、`lib/settings/pages/git_settings.dart` 四个路径在盘上不存在；`flutter analyze` 零 error（无未解析 import） | — |
| §2-2 B 组（假控件） | §5 ⑤ | `grep -n "GitSettingsGroup" lib/` 零命中；`general_page.dart` 无该 import | 设置 → General 打开后 Items 里没有 Git 分组 |
| §2-3 C 组（仓库侧残留） | §5 ⑥⑦ | `grep -nE "lastFetchAt|autoFetchIssue|pullFromUpstream|ideGitPull" lib/` 零命中；`grep -n "service.fastForward\|service.merging\|service.abortMerge\|service.changedPaths" lib/` 零命中；`git_repository.dart` 的 `_enqueue` / `_operate` 签名回到 `Future<void>`（`_enqueue({bool background})` / `_operate(Future<void> Function())`） | — |
| §2-4 D 组（测试档） | §5 ⑩ | 两个测试档路径不存在；`flutter analyze` 不报「没找到被 import 的档」 | — |
| §2-5 E 组（l10n） | §5 ⑧⑨ | 两个 `arb` 与三个生成档里 `grep -c "gitAutoFetch\|gitLastFetched\|gitPeriodMinutes\|generalSettingsGit\|scmFetchAndPull\|scmBehindCommits"` = 0；`flutter gen-l10n` 退出 0 | — |
| §2-6 F 组（文档） | §5 ⑪⑫ | 需求档规范面（§1–§5）`grep -ci autofetch` = 0 且无「获取 / 拉取」节（出处行在档头，不属规范面）；本档 `grep -ni autofetch` 的每一行都属三类之一——删除清单（§5 ①②⑥⑧⑩⑪ 与表后判据）· 旧设置键名（§3.2 / §6-D6 / §7 / §8-B1·E2）· 上游键说明（§2.3），无一行把 autofetch 写成活机制；`doc_check(mode:"gate")` 首行 PASS | — |
| §2-7 保留面不动 | §3.4；§4 | `git_repository.dart` 的 `scheduleMicrotask(_notify)` 空仓修复仍在（`_loadGraph` 内）；`setGitProcessEnvironment` / `gitProcessEnvironmentMap()` 与 `ProxyRoute.environment` 的变量集未改；`ide_scm_view.dart` / `ide_git_log_view.dart` / `ide_git_commit_panel.dart` 零改动（`git diff --stat` 里不出现） | — |
| §2-8 用户旧设置不炸 | §3.2 | — | settings.json 写入 `{"git.autofetch": false}` 后启动，设置页与 SCM 面正常，无异常日志 |

**实施与收口的运行检查**：`flutter analyze`（全仓，零 error）+ `flutter test test/ide/git/`（删后目录内 41 个测试档 + 夹具 `fake_git.dart`，绿的才收）。本批自己的两个测试档随批删，不留可执行产物。

## 8. 用例表（正常 / 边界 / 错误）

删除批没有新增业务行为，用例检查的是「删对了」与「该留的还在」：

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| N1 | 设置页打开 | Settings → General | 无 Git 分组；IDE / 其它分组照常；无异常日志 |
| N2 | 仓库日常操作 | 改一个文件 → stage → commit → push | 三步都成功；`_operate` 的忙碌计数与末尾强制刷新行为不变 |
| N3 | Fetch / Pull / Sync Changes | 上游有新提交 | 三个按钮各自的动作与上游形态一致（fetch 只 fetch；pull 拉取；sync 拉取后推送） |
| N4 | 代理仍生效 | 系统代理开、`~/.gitconfig` 无 `http.proxy` | 手动 Fetch 能通（`gitProcessEnvironmentMap()` 含 `HTTPS_PROXY` / `http_proxy`） |
| B1 | 用户 settings.json 带旧键 | `{"git.autofetch": false, "git.autoPull": false}` | 正常启动；三个键不被读取；文件保持原样 |
| B2 | 空仓 | `git init` 后立刻打开 Graph | 不抛 `setState during build`（`scheduleMicrotask(_notify)` 修复仍在） |
| B3 | 无消费者判据 | §7 表里的 grep 项 | 全部零命中 |
| E1 | 删多了的防线 | 实施首轮按 §5 的 grep 复核 | 出现预期外的消费者 ⇒ 停手报告，不自行扩大删除面 |
| E2 | l10n 漏删 | `flutter gen-l10n` 后查生成档 | 无 `gitAutoFetch*` 等键；分析器不报未用成员 |

## 9. 集成测试设计（对 `test/RTM.md` 的增量）

本批是纯删除：没有新的用户入口、没有新的跨组件交互、没有业务可观察结果被改写。按入口判据（真实业务场景 ∥ 生产真出过的问题）：

- **生产真出过的问题**：设置页三个控件点了没反应（假开关）。它在删除后不再存在，可断言的只剩「设置页没有该分组」——这是设置页自身的形态，不是跨组件交互，不立集成行。
- **业务场景**：本批不产生。
⇒ 对 `test/RTM.md` 的 delta = **零行**（不改写、不删、不加）。

`test/RTM.md` 已逐行核对（修轮实读）：66 行、四个业务故事各一条用例（1-1 切会话 / 2-1 失焦 / 3-1 大会话流式 / 4-1 btest），档内记规模窗 4 / 50–100（`test/RTM.md:9`）；对全档检索 `git|scm|fetch|获取|仓库|拉取`（不区分大小写）零命中 ⇒ git 面没有既有行：既没有本批会破的行，也没有冗余行可删。

## 10. 边界（本批不做）

- 不删 `git_repository.dart` 的空仓 `scheduleMicrotask(_notify)` 修复——与自动获取无关，删了会让 `git init` 后立刻用挂掉。
- 不动系统代理面（`§3.4` 全节零改动）；不动上游 SCM 三档（`ide_scm_view.dart` / `ide_git_log_view.dart` / `ide_git_commit_panel.dart`）。
- 不做用户 settings.json 的数据迁移 / 清洗。
- 不拆 `git_service.dart` / `git_repository.dart` / `general_page.dart` 的 >800 行档（§5.1：存量债，按触发点下次碰时拆）。
- 不补替代功能：本产品不提供「自动关注远端新提交」的形态；要重新实现，那是另一个需求。
- 不改远端 host 的 git 行为；不改 `packages/bao_remote` 的代理注入契约。

### 10.1 未核实与判定条件

| # | 未核实点 | 判定条件 |
|---|---|---|
| U1 | `test/ide/git/` 下其余测试档是否引用了被删符号（本轮只核了两个待删档与 fake 夹具的表面用法） | 实施首轮 `flutter analyze` + `flutter test test/ide/git/`：报未解析符号 ⇒ 该档随即修正（引用删除面），失败原因写进实施记录 |
| U2 | `_enqueue` / `_operate` 回退成 `Future<void>` 后，是否还有调用点依赖返回值 | 实施首轮把两个方法的泛型去掉后 `flutter analyze`：报错 ⇒ 保留该调用点的泛型并记录（不走第二条路径） |

## 11. UI / 交互决定（全部落地，无 open）

1. **设置 → General**：不再有 Git 分组（`自动获取远端更新` / `自动拉取` / `获取周期` 三行一并消失）。其余分组与行序不变；不留下空分组或占位说明。
2. **SCM 面板 / 仓库头 / 日志视图**：保持上游形态，本批零改动。仓库头的获取按钮只 fetch，仓库头不带待拉取计数、不带「上次成功」时间。
3. **状态栏 branch 项**：回到上游形态（分支名 + checkout 行为），不带待拉取数与时间。
4. **无新提示**：不弹「自动获取已移除」之类的通知；删除本身就是答案。
5. **旧设置残留**：界面上不显示、不解释。
