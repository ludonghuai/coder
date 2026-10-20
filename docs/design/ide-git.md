# Git 自动拉取与系统代理（ide-git）设计档

> 板块：IDE 的 Git 面（`lib/ide/git/**` + `packages/bao_remote` 的 git 执行）· 需求档：`docs/requirements/ide-git.md` · 台账 #84 · 范围仓：baocode。
> 行数 = 换行数（`\n` 计数）实测（2026-10-19）。§5 = 此前各批的改动记录；本批（获取 = 真拉取、`↓N` 位置）的受影响文件与读数见 §12.7。

## 1. 模块目标与范围

远端出现新提交时，IDE 在工作区所有仓库上自动 fetch；本地干净且可快进时自动拉入；任何一步不满足就只显示远端提交数、不动工作树。git 子进程自动跟随系统代理。用户不再需要手动 Fetch / Pull 才能看到对方的提交。

本档覆盖需求 §2.1–§2.8 与 §4.1–§4.8（§12 = 获取 = 真拉取 / `↓N` 位置的增量）；§3 的边界项不做（见 §10）。

## 2. 做法与理由

### 2.1 做法一句话

一个工作台级的自动同步引擎：按周期 / 回到前台 / 仓库发现对工作区所有仓库并发 fetch；fetch 后用本地状态做「干净 + 可快进 + 远端改动与脏缓冲不相交」判定，满足则 `git merge --ff-only` 快进；网络失败静默重试，需用户动作的失败单次通知；git 子进程经 `runGit` 的环境注入口继承 Settings → Network 解析出的代理。

```text
IdeWorkbenchState（每个 IDE 工作区一个，Offstage 时仍活着）
  └─ IdeGitAutoFetch（新，lib/ide/git/git_autofetch_engine.dart）
       ├─ 定时器 / 前台恢复 / 仓库发现 / 设置变化  → 单轮调度（有界并发 4）
       ├─ 每仓：pullFromUpstream()（fetch → 现读 status → 否决/合并 → 待 reload 路径）→ workspace.reload(paths)
       ├─ 失败与跳过：按「根 + 问题键」去重；网络类静默
       └─ 读：workspace.repositories / documents；写：repository.lastFetchAt / autoFetchIssue
```

### 2.2 最近先例对照（对齐 ∥ 偏离及理由）

**先例来源声明**：`docs/design/` 的其余四档（chat-streaming / forge-accounts / host-tool-channel / thincoder-adapter）都没有「周期后台同步 + 多仓 git」的同形机制章节。⇒ **§2.2 的实现坐标是本设计的唯一先例来源**，形态来源 = §2.3 的 VS Code 公开定义。

对齐（照抄形态，不另造）：

| 面 | 先例 | 照抄的形 |
|---|---|---|
| 全仓遍历 | `lib/ide/git/ide_scm_view.dart:2017-2023`（`_fetchAll`：`Future.wait` 每仓 `git.fetch`） | 全仓遍历 + 单仓隔离；`repos` 工作区一次覆盖 |
| 操作后刷新 | `lib/ide/git/git_repository.dart:170-182`（`_operate`：操作后 `refresh(force: true)`） | `fetch` / `fastForward` 都走同一入口，状态与 Graph 跟随 |
| 系统代理读取 | `lib/network/network_proxy_io.dart:228-256`（`readSystemProxy`：Windows `reg.exe`）；`lib/network/proxy_settings.dart:457-513`（`ProxyEnable` / `ProxyServer` / `ProxyOverride`） | 直接复用，不重写 WinINET / macOS `scutil` 读取 |
| 子进程环境口径 | `lib/network/proxy_settings.dart:294-313`（`ProxyRoute.environment`：大小写两套变量 + `NO_PROXY`） | git 子进程用同一份 env（含 `off` 清空、`system` 回退环境变量） |
| 前台恢复 | `lib/ide/ide_workbench.dart:1070-1075`（`AppLifecycleListener(onResume: refresh)`） | 扩为 resume 触发一轮 fetch（仍保留原 status 刷新） |
| 设置行 | `lib/settings/pages/general_page.dart:469-509`（IDE 分组）；`lib/settings/pages/settings_widgets.dart:369`（`SettingsSwitchRow`）；`lib/settings/pages/settings_dropdown.dart:12`（`SettingsDropdown`） | 同样的行形与「默认值不写盘」写法（`general_page.dart:221-231`） |
| 脏缓冲 reload | `lib/ide/ide_workspace.dart:776-805`（`reload`：dirty 文档跳过、被删标记） | pull 成功后调 `workspace.reload(改动路径)`，不自造刷新 |
| 分支栏 | `lib/ide/ide_workbench.dart:4581-4604`（状态栏 branch 项）；`lib/ide/git/ide_scm_view.dart:2268-2277`（`_headLabel`） | `↓N` 与「上次成功时间」的现行落点：状态栏 branch 项（含 `↓N`）+ 仓库头获取按钮右侧（`_headLabel` 不含 `↓N`，§12.6 第 2 条） |

偏离（逐条给理由）：

1. **引擎放工作台，不放 `IdeScmViewState`**。视图随侧栏重建/卸载，定时器不能跟着视图生死；且多仓列表在 `IdeWorkspace`（`lib/ide/ide_workspace.dart:360-368`），不在视图里。工作台为每个 IDE 工作区常驻（`lib/workbench.dart:2479-2489` 的 `Offstage` + `TickerMode`；聊天模式下 `workbench.dart:2471-2475` 仍把各 IDE 面板留在树里），是唯一「工作区活着就活着」的挂点。
2. **快进用 `merge --ff-only`，不用 `git pull`**。fetch 已经拿到远端 ref，再 `pull` 会二次联网；`pull` 还受 `pull.rebase` / `pull.ff` 配置影响。
   `merge --ff-only` 语义逐字（`Documentation/merge-options.adoc`，2026-10-19 读）：「resolve the merge as a fast-forward when possible. When not possible, refuse to merge and exit with a non-zero status.」——不产生合并提交、不产生冲突、分叉时干净失败。
3. **代理走环境变量，不走 `-c http.proxy`**。`ProxyRoute.environment` 已是 app 与 Claude Code 共用的口径（`lib/network/network_proxy_io.dart:134-135`）；`-c` 会把代理（可能带凭据）写进进程命令行。
   代价：git 自己的 `http.proxy` 配置优先于环境变量（`Documentation/config/http.adoc` 逐字：`http.proxy` overrides `http_proxy`/`https_proxy`/`all_proxy` 环境变量）——用户显式配的 gitconfig 保持优先，本机 `~/.gitconfig` 现无该项。
4. **有界并发 4**。17 仓同时起 17 个 git 进程，代理与句柄都会抖；4 个 worker 足够跑满普通带宽。
5. **网络类失败不通知**（需求 §2.5 / §4.6）。只有认证、冲突、缓冲相交这类「需要用户动作」的才进通知中心。
6. **`↓N` 上状态栏与仓库头**。现有 Sync Changes 按钮在本地有改动时被 Commit 按钮顶掉（`lib/ide/git/ide_scm_view.dart:1889-1901`：`changes ? _commitButton : … _syncButton …`），脏树时看不到远端提交数——这正是用户抱怨的点，必须在别处常显。
7. **clean 含未跟踪文件**。需求 §2.2① 逐字「工作树干净（无未提交改动）」；`state.resources` 含未跟踪、不含 ignored（`lib/ide/git/git_model.dart:259-267`、`:542`），按字面取。保守：未跟踪文件与远端改动同名时 git 也会拒绝，提前拦住。
8. **网络命令超时 300 秒**（其余 60 秒）。`runGit` 现有 60 秒固定超时（`packages/bao_remote/lib/src/git/git_runner.dart:47`、`:117`、`:124`）；大仓 / 慢代理下一次 fetch 可能超过 60 秒，被杀了就永远成功不了。按命令名放宽，本地与远端 host 同时受益；本批把 `merge` 同列放宽档（理由与档位见 §3.3）。

### 2.3 公开资料调查（survey-evidence）

| 来源 | 取了什么 | 用在哪 |
|---|---|---|
| VS Code `extensions/git/package.json` + `package.nls.json`（`raw.githubusercontent.com/microsoft/vscode/main`，2026-10-19 读） | `git.autofetch`：boolean\|string，enum `true`/`false`/`"all"`，默认 `false`；描述「commits will automatically be fetched from the default remote … `all` will fetch from all remotes」。`git.autofetchPeriod`：number，默认 `180`；描述「Duration in seconds between each automatic git fetch, when `#git.autofetch#` is enabled」。 | 键名与单位照抄（period = 秒，默认 180）；默认开关按用户需求改为「开」；我们 fetch 所有 remote，字符串 `"all"` 视作开。 |
| Dart `Process.run` API（`api.flutter.dev/flutter/dart-io/Process/run.html`，2026-10-19 读） | `environment` 覆盖父进程；`includeParentEnvironment` 默认 `true`，父环境合并、传入项优先。 | 只传增量代理变量，其余环境（PATH、`HOME`、凭据配置）照旧继承。 |
| git `Documentation/merge-options.adoc`、`git-merge.adoc`（`raw.githubusercontent.com/git/git/master`，2026-10-19 读） | `--ff-only` 逐字同上；merge 在「local uncommitted changes overlap with files that … may need to update」时停止；index 与 HEAD 有差异时中止；全部已是祖先时输出 `Already up to date.` 并成功。 | `merge --ff-only` 的快进与拒绝语义；判定链之外的 git 兜底（§4.3）。 |
| git `Documentation/config/http.adoc`（同日读） | `http.proxy` 覆盖 `http_proxy` / `https_proxy` / `all_proxy` 环境变量。 | 代理优先级写进 §3.4：gitconfig 显式项 > 应用注入的环境变量 > 直连。 |
| 本仓 WinINET 读取（`lib/network/proxy_settings.dart:457-513`、`lib/network/network_proxy_io.dart:236-243`） | `reg.exe query HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`，读 `ProxyEnable` / `ProxyServer` / `ProxyOverride`；`<local>` 映射为 simple-hostnames 绕过。 | 不新增注册表代码；`ProxyRoute` 现成。 |

## 3. 接口契约

### 3.1 分层与数据流

```text
main.dart:157-163（startNetworkProxy 之后）
  └─ setGitProcessEnvironment(() => NetworkProxy.instance.current.environment)   ← 新，1 行接线；闭包每次 spawn 求值（§3.4）

IdeWorkbenchState
  ├─ IdeGitAutoFetch（新）— 定时器 / 调度 / 去重 / 写回 repository 状态
  │    ├─ repositories()  → IdeWorkspace.repositories（List<(String root, IdeGitRepository git)>）
  │    ├─ documents()     → 打开文档的 (path, dirty, isFile)
  │    ├─ reload(paths)   → IdeWorkspace.reload
  │    ├─ setting(key)    → UserSettings（widget.settings）
  │    └─ onNeedsAttention(issue) → 工作台按当前 l10n 格式化 → IdeNotifications.notify
  ├─ IdeGitRepository（既有）
  │    ├─ fetch()         既有，成功后记 lastFetchAt
  │    ├─ fastForward()   新，_operate(() => service.fastForward(upstream))
  │    ├─ incomingPaths()  已被 pullFromUpstream 取代，无调用点（路径清单在核内由 changedPaths 计算）
  │    ├─ pullFromUpstream() 新，一次操作完成 fetch → 判定/合并 → 待 reload 的路径（§12.2）
  │    └─ lastFetchAt / autoFetchIssue（新字段，notifyListeners 驱动 UI）
  └─ IdeGitService（既有）
       ├─ fetch({remote})            既有：fetch <remote> --tags / fetch --all --tags
       ├─ fastForward(ref)           新：merge --ff-only <ref>
       ├─ merge(ref)                 新（批 13）：merge --no-edit <ref>；失败取 stderr / stdout 原话（§12.2）
       ├─ merging()                  新（批 13）：rev-parse --verify -q MERGE_HEAD；无 MERGE_HEAD ⇒ false（§12.2）
       ├─ abortMerge()               新（批 13）：merge --abort；只回滚本函数发起的合并
       └─ changedPaths(from, to)     新：diff --name-only -z --no-renames <from> <to>；返回绝对路径（§3.3）

runGit（packages/bao_remote/lib/src/git/git_runner.dart）
  └─ environment: gitProcessEnvironmentMap() = {GIT_TERMINAL_PROMPT, GIT_EDITOR, GIT_OPTIONAL_LOCKS} + 注入项
```

### 3.2 设置键（settings.json）

| 键 | 类型 | 默认 | 解析 |
|---|---|---|---|
| `git.autofetch` | bool（兼容字符串 `"all"`） | `true` | 仅 `false` 关；`true` / `"all"` / 未设 = 开。总开关：关 ⇒ 周期与 auto-pull 全停（需求 §4.7「关掉即完全停止」；进程内的精确语义见 §4.6）。 |
| `git.autoPull` | bool | `true` | 仅 `false` 关；关 = 只 fetch 显示 `↓N`，不动工作树。 |
| `git.autofetchPeriod` | number（秒） | `180` | 数值且 >0；夹到 `[30, 3600]`；非数值 / ≤0 = 默认 180。 |

代理：**不新增键**。复用 Settings → Network 的 `http.proxyMode` / `http.proxy`（`lib/network/proxy_settings.dart:21-24`），与 app、Claude Code 同一份（需求 §2.3）。

### 3.3 新增 / 变更的 git 命令（argv 逐字）

| 用途 | argv（`runGit` 会前置 `--no-optional-locks -c core.fsmonitor=false`） | 备注 |
|---|---|---|
| fetch（既有） | `fetch <remote> --tags`；`fetch --all --tags` | 不变；失败时 refs 可能已部分更新，仍进入 auto-pull 判定（§4.3）。`fetch --all --tags` 的作用域 = **单仓全部 remote**；`git.fetchAll`（`_fetchAll`，`ide_scm_view.dart:2017-2023`）= **工作区全仓遍历**，逐仓调用本行（§12.3） |
| 远端改动文件（新） | `diff --name-only -z --no-renames HEAD <upstream>` | 输出 = 仓库根相对路径（`/` 分隔、`-z` 逐条）；`changedPaths` 拼成绝对路径（`pathContext.join(repositoryRoot(), path)`，归一化见 §4.3）；`--no-renames` 让重命名同时列出旧、新两路 |
| 快进（新） | `merge --ff-only <upstream>` | 不产生合并提交；分叉 / 本地重叠 / index 不齐 ⇒ 非 0 退出 |
| 合并（新，批 13） | `merge --no-edit <upstream>` | 按钮路径（§12.2 步骤 6）；可产生合并提交；冲突时写 `MERGE_HEAD`、非 0 退出；失败消息取 stderr、空则取 stdout（冲突摘要常在 stdout），截 500 字 |
| 合并中查询（新，批 13） | `rev-parse --verify -q MERGE_HEAD` | `merging()` 的契约：退出 0 ⇒ true；退出 1 且 stdout / stderr 皆空 ⇒ false（`-q` 本就静默）；stderr 非空 / 仓库不可读 / 其它非 0 ⇒ 抛 `IdeGitException`（§12.2 步骤 6） |
| 回滚合并（新，批 13） | `merge --abort` | 只在「合并前无 `MERGE_HEAD`、现在有」（含复查失败按「可能已开始合并」处理）时调用（D18）；自身失败的处置见 §12.2 步骤 6 / §12.3 |
| 超时策略（改） | `runGit` 按命令名：放宽档 = `fetch` / `pull` / `push` / `ls-remote` / `clone` / `submodule` / `merge` ⇒ 300 秒；其余 60 秒 | 纯函数 `gitTimeoutFor(arguments)`，可单测。`merge` 不联网，但大量写工作树，被 60 秒杀掉会留下半合并（`MERGE_HEAD` / 冲突标记），收拾代价高于一次慢合并 ⇒ 同列放宽档；`merge --ff-only` / `merge --no-edit` / `merge --abort` 命令名相同，同档（§12.7 ④） |

### 3.4 代理继承契约

- **注入点**：`packages/bao_remote/lib/src/git/git_runner.dart` 新增 `setGitProcessEnvironment(Map<String, String> Function()? value)`；`runGit` 与 `_runLimited` 都用 `gitProcessEnvironmentMap()` 作 `environment`。`null` = 不注入（远端 host 的 server 进程即如此）。
- **变量**：直接返回 `ProxyRoute.environment` 的 8 个键（`HTTP_PROXY` / `http_proxy` / `HTTPS_PROXY` / `https_proxy` / `NO_PROXY` / `no_proxy`，`ALL_PROXY` 两种拼写在 `off` 时清空）。值域：
  - `http.proxyMode = system`：系统代理（WinINET / macOS `scutil`）；系统无代理时回退 app 进程的环境变量；两者都无 ⇒ 空 map（让 git 继承父环境）。
  - `http.proxyMode = manual`：`http.proxy` 的 URL（`ProxyServer.url`，含 userinfo）。
  - `http.proxyMode = off`：8 个变量置空串 ⇒ git 直连（覆盖继承来的代理变量）。
- **优先级**（自上而下）：`~/.gitconfig` 的 `http.proxy` > 应用注入的环境变量 > 父进程环境 > 直连。理由见 §2.2 偏离 3；应用设置覆盖的是「系统代理」，不是用户的 git 配置。
- **生效时机（每次 spawn 求值）**：注入的是闭包；`runGit` 每组装一次子进程环境就同步读 `NetworkProxy.instance.current.environment`（`current` 是同步 getter，`lib/network/network_proxy_io.dart:46`），值 = `NetworkProxy` **最近一次解析**的结果。
  - Settings → Network 改 `http.proxyMode` / `http.proxy`：`follow` 的变更监听触发重解析（`network_proxy_io.dart:50-61`），重解析完成后**下一次 spawn 即用新值**（在途的那次仍用旧值）。
  - 系统代理在运行中变更：要等 `resolve()` 再次执行——app 客户端 10 秒老化重读（`connectionMaxAge`，`network_proxy_io.dart:43-46` / `:124-129`）、Settings → Network 的 Refresh（`currentProxyRoute()`，`:258`）或重启 app；即需求 §2.3 的「重启生效」。
- **范围**：只影响本机 `runGit`；远端工作区的 git 在 host 上跑，用它自己的环境（边界，见 §10）。

### 3.5 失败 / 跳过分类与通知口径

`ideGitFailureOf(Object error)` 只看 `IdeGitException` 的 message（`git_service.dart:95-100` 已把 stderr 截到 500 字），按首个命中分类：

| 类别 | 命中样例（不区分大小写） | 通知 | 界面 |
|---|---|---|---|
| `auth` | `authentication failed`、`could not read username`、`terminal prompts disabled`、`permission denied (publickey)`、`403`、`401`、`407`、`repository not found` | **一次 / 状态变化**（warning） | 分支栏 tooltip + 通知中心 |
| `conflict` | `would be overwritten`、`not possible to fast-forward`、`would clobber existing tag`、`unresolved conflict`、`not concluded your` | **一次 / 状态变化**（warning） | 同上 |
| `buffered`（跳过，非失败） | 判定链产生，带相交文件名 | **一次 / 状态变化**（warning，`source: 'Git'`） | 同名 tooltip |
| `network` | `could not resolve host`、`failed to connect`、`connection timed out`、`connection reset`、`unable to access`、`rpc failed`、`early eof`、`remote end hung up`、`did not respond within` | **不通知** | tooltip 写「网络不可用，自动重试中」 |
| `proxy` | `connect tunnel failed`、`proxy connect aborted` | **不通知**（网络类） | tooltip 写代理不可用 |
| `other` | `cannot lock ref`、`index.lock`、`not a git repository` 等 | **不通知** | tooltip 原文（截断） |

`dirty` / `diverged` / `limit` 是**跳过**，不算失败：不通知，只在 tooltip 写原因；`↓N` 常显（§11）。

### 3.6 状态模型

`IdeGitRepository`（`lib/ide/git/git_repository.dart`）新增：

```dart
DateTime? lastFetchAt;                 // 最近一次 fetch / fastForward / pull / sync 成功
IdeGitAutoFetchIssue? autoFetchIssue;  // 自动处理的最近一次跳过/失败；成功一轮清空
```

- `fetch` / `pull` / `sync` 成功时写 `lastFetchAt = clock()` 并 notify；`fetch` 失败不清旧值（「上次成功」语义）。
- 引擎每轮写 `autoFetchIssue`（同值不重复 notify）；UI 读这两个字段。
- 进程内状态，不落盘（重启后第一轮 fetch 在数秒内填上）。

`IdeGitAutoFetchIssue`（`git_autofetch.dart`）：`kind`（上表 + `dirty` / `diverged` / `limit`）、`paths`（相交文件，绝对路径；归一化见 §4.3）、`detail`（stderr 截断，仅 tooltip）；`key = kind + '\u0000' + paths.join()`；`needsAttention = auth || conflict || buffered`。

## 4. 机制与生命周期

### 4.1 触发面

| 触发 | 行为 |
|---|---|
| 周期 | **链式单次定时器**：一轮跑完后按 `autofetchPeriod` 再排下一轮；不重叠、不堆叠。启动后 3 秒跑第一轮（让扫描与首屏先完成）。 |
| 回到前台 | `AppLifecycleListener.onResume`（`lib/ide/ide_workbench.dart:1070-1075`）在原有 `refresh` 之外调 `runNow(resume)`；距上次开跑 <5 秒则跳过（防抖）。 |
| 仓库发现 | 引擎监听 `IdeWorkspace`（ChangeNotifier）：根集合新增时 2 秒后补一轮；扫描出 17 仓后不用等下一个周期。 |
| 设置变化 | `UserSettings` 通知：开关切换 ⇒ 起/停定时器（关 ⇒ 定时器取消且 `runNow` 直接返回）；period 变化 ⇒ 重排；`autoPull` 变化 ⇒ 下一轮生效。 |
| 手动获取 / Pull | 不是自动轮的触发。获取按钮 = 真拉取（fetch + merge，可产生合并提交；失败回滚），与自动轮共用 §12.2 的拉取核心；成功同样写 `lastFetchAt`。 |

### 4.2 单轮执行

1. 快照 `repositories()`，按 `git.service.root` 去重；`git.busy`（有前台操作）的仓本轮跳过，下轮再试。
2. 4 个 worker 分摊；每仓独立 `try/catch`，任何异常只影响该仓。
3. 每仓顺序：`fetch` →（`autoPull` 开则）判定 + 快进 → 写 issue / `lastFetchAt`。fetch 抛错也要进入 auto-pull 判定：refs 可能已被其它 remote 更新；判定读的是 fetch 之后现读的 `status`（§12.2 步骤 2），`behind > 0` 就说明上游 ref 是新的，快进安全；否则 behind 为 0，自然不动。这样「一个仓库挂了个坏 remote」不会让它永远不拉。
4. 单轮永不向定时器抛异常；`dispose` 后不再调度。

### 4.3 auto-pull 判定链（逐条）

每仓、每轮，按顺序：

1. `git.autofetch` 开（引擎门，每轮开跑前读一次）且 `git.autoPull` 开；否则不判定。每仓快进前再读一次 `git.autofetch`（步骤 8）。
2. 判定输入 = fetch 之后现读的 `status`（不是缓存 `state`，§12.2 步骤 2）：`state != null`、`head.branch != null`（非 detached）、`!head.unborn`、`head.upstream != null`；不满足 ⇒ 静默（无 upstream 是正常态）；`state` 读不到 ⇒ 记 `other` issue（不静默）。
3. `head.behind == 0` ⇒ 无事可做。
4. `head.ahead > 0` ⇒ **分叉**，跳过（`↓N` 仍显示）。
5. `state.didHitLimit` 或 `state.resources.isNotEmpty` ⇒ **脏树**（未跟踪计入，`git_model.dart:542`；ignored 不计，`:259-267`），跳过。
6. 取 `incoming` = 核心内 `service.changedPaths('HEAD', upstream)` 的结果（§12.2 步骤 4；`diff --name-only -z --no-renames`，返回**绝对路径**，归一化见下）；取 `dirtyPaths` = 打开的脏文档中位于该仓根下的路径；两者用同一路径空间比较。
7. `incoming ∩ dirtyPaths` 非空 ⇒ **缓冲**，跳过，记相交文件名（最多列 3 个）；保存 / 关闭后下一周期自动拉。
8. 否则 **快进**：先按仓重读 `git.autofetch`（不用本轮开始时的值）；为关 ⇒ 该仓本轮不发起 merge（语义见 §4.6）。仍开 ⇒ `merge --ff-only <upstream>`；成功 ⇒ `workspace.reload(incoming)`、清 issue、`lastFetchAt` 更新。
9. git 自己的兜底：判定后文件又被改（竞态）⇒ merge 拒绝（local changes / index 不齐）⇒ 记 `conflict`（需用户动作，通知一次）；分叉竞态 ⇒ `not possible to fast-forward`，同样记 `conflict`；`Already up to date` ⇒ 成功、无事发生。
10. 快进成功后复查一次脏缓冲（merge 期间用户开始编辑）：若有相交且仍脏 ⇒ 记 `buffered` 提示一次（该次 reload 已按既有语义跳过它）。

**执行面**：步骤 4–8 原样搬进共享拉取核心（`pullFromUpstream`，§12.2 步骤 4–6）；引擎侧只提供否决器（含「快进前按仓重读 `git.autofetch`」）并消费 `updated`。

**路径归一化（步骤 6 / 7 / 8 共用一套）**：

- `incoming` 的形态：`changedPaths` 用 `git.service.pathContext.join(repositoryRoot(), path)` 把仓库根相对路径拼成绝对路径并 `normalize`（`repositoryRoot()` 为 null ⇒ 空列表；步骤 2 已要求 `state != null`，正常不走）。
- `incoming` 的基准：**仓库顶层**而不是工作区根（工作区根可能是仓库子目录，`git_service.dart:103-110`）；`pathContext` 是 git 主机拼路径的上下文（本地 `p.context`、远端 host `p.posix`，`git_service.dart:69-75`）。
- `dirtyPaths`：`doc.path` 已是 `paths.normalize(paths.absolute(path))` 的绝对形（`ide_workspace.dart:536`）。
- 比较键：两边都过 `workspace.paths.normalize`；`paths.style == p.Style.windows` 时再统一 `toLowerCase()`（Windows 文件系统大小写不敏感，`normalize` 不折叠大小写）。
- 相交结果保留绝对路径（§3.6 的 issue `paths`）；通知 / tooltip 只显示 `basename`。
- `workspace.reload(incoming)` 传的就是这批绝对路径：`reload` 只做 `paths.normalize`、不做 `absolute`（`ide_workspace.dart:776-777`）⇒ 入参必须是绝对路径，相对路径匹配不上 `doc.path`（后者由 `normalize(absolute(path))` 生成，`:536` / `:568`）。

`decideAutoPull` 是纯函数（输入 head / clean / hitLimit / dirtyPaths / incomingPaths），返回 `(action, intersectingPaths)`；单测覆盖上表每一格。

### 4.4 pull 后刷新与 reload

- `merge --ff-only` 由 `_operate` 包住：成功后强制 `refresh(force: true)`，分支栏 `↓N` 归零、Graph 的远端 ref 更新（`git_repository.dart:404-454` 的 graph 读取用 `refs/remotes/<upstream>`）。
- `workspace.reload(incoming)` 按既有语义刷新已打开文件：dirty 文档跳过、被删文件标 `doc.deleted`（`ide_workspace.dart:776-805`）。不抢焦点、不弹模态。
- 判定链保证「脏缓冲相交」的仓根本不会 merge，所以常规路径下 reload 不会遇到脏文档；第 10 步的复查只为竞态兜底。

### 4.5 「上次成功时间」与可见面

| 面 | 内容 |
|---|---|
| 状态栏 branch 项（`lib/ide/ide_workbench.dart:4581-4604`） | 文本：`<branch>` + ` ↓N`（N>0）+ ` · HH:mm`（`lastFetchAt` 已知；非当天 `MM-DD HH:mm`）。tooltip 追加「上次成功：<时间>」与当前 issue 原因（若有）。点击仍是 Checkout to…。 |
| CHANGES 仓库头（多仓时，`lib/ide/git/ide_scm_view.dart:2165-2260`） | 分支标签只留 branch 与 `*` / `+` / `!`；`↓N` 紧贴「获取」按钮右侧（§12.6，窄宽时回落到分支名右侧）；行 tooltip 追加「上次成功」与 issue 原因。单仓时无仓库头，由状态栏承担。 |
| 通知中心 | 仅 `auth` / `conflict` / `buffered`，按「根 + 问题键」去重：同一问题只通知一次，问题变化或恢复后再次失败才再通知。`source: 'Git'`。 |
| 源控 / Graph | 分支栏与 Graph 的远端 ref 由 `_operate` 的强制刷新驱动，与手动 fetch 同一条链。 |

### 4.6 关闭与回收

- `git.autofetch` 关 = 完全停止：取消定时器；`runNow`（resume / 发现 / 设置触发）在引擎门直接返回，不再开新的一轮；进行中的一轮在**每仓快进前**按仓重读门（§4.3 步骤 8）⇒ 关闭后不再发起任何 merge（唯一会改工作树的动作）。已在跑的 fetch 不 kill（只更新远端 ref、不动工作树，最坏 300 秒超时自收），本轮剩余的 fetch 跑完即止，一律不进入快进。
- 工作台销毁 / 换工作区：引擎 `dispose()` 取消定时器、移除设置与工作区监听；已发出的 repo 操作自然结束。
- 同一进程内同一仓被多个工作台打开：引擎用静态 `Map<root, Future>` 做单飞（同进程只有一个 fetch 在跑）。条目在 Future 完成时（`whenComplete`，成功与失败都走）从表中移除；失败后下一次触发重新入表，不残留已完成的 Future。跨进程由 git 自身锁保证不损坏，失败按 `other` 静默重试。
- 进程级全局状态的测试还原：环境注入闭包在每个用例的 `tearDown` 里 `setGitProcessEnvironment(null)`；单飞表由 `@visibleForTesting` 的 `IdeGitAutoFetch.clearInFlight()` 在 `tearDown` 清空（用例内异常路径用 `finally`）——两个用例之间不串味。

### 4.7 仓库扫描的失败面（侧栏 Sources）

侧栏按 `git.autoRepositoryDetection` 找项目文件夹下的仓库（`lib/ide/git/repository_scan.dart`；入口 `workbench.dart:3527-3596`）。扫描本身失败时：

- 记一条 `appEvent('sidePanel', 'repository scan failed: …')`；本轮面板不列仓库，30 秒后自动重试（`_sidePanelRetryAt` + 重试定时器），不是永久放弃。
- 同一位置只提示一次 warning（新键 `scmScanFailed`：「暂时无法扫描这里的仓库，稍后自动重试。」/ "Can't look for repositories here right now; trying again shortly."）；一次成功即清提示标记（`_scanWarned`）。
- 理由：失败若静默，面板的「没有仓库」会被用户当成事实；重试成功后面板照常列出，不需要用户动作。

## 5. 受影响文件清单

编制时行数与预算增量 = 编制日读数；「实测」列已回填（2026-10-19 实测：新增档为文件行数，改动档为净增与当前行数）。本节是此前各批（autofetch / 代理 / 设置）的改动记录，§5.1 同属；本批（获取 = 真拉取、`↓N` 位置）的受影响文件与读数见 §12.7——两处口径同为换行数。

| # | 坐标（编制时行数） | 改动 | 预算增量 | 实测 | 结论 |
|---|---|---|---|---|---|
| ① | `lib/ide/git/git_autofetch.dart`（新） | 纯策略：设置解析 / `decideAutoPull` / 失败分类 / issue 模型 | ~170 | 300 | 超 130 |
| ② | `lib/ide/git/git_autofetch_engine.dart`（新） | `IdeGitAutoFetch`：定时器、触发面、并发池、去重通知、repo 状态写回 | ~210 | 389 | 超 179 |
| ③ | `lib/ide/git/git_service.dart`（613） | 新增 `fastForward(ref)`、`changedPaths(from, to)` | ~+35 ⇒ ~648 | +27（640） | 内 |
| ④ | `lib/ide/git/git_repository.dart`（477） | 新增 `lastFetchAt` / `autoFetchIssue` / `fastForward()` / `incomingPaths()`；`fetch` / `pull` / `sync` 成功记账 | ~+50 ⇒ ~527 | +44（521） | 内 |
| ⑤ | `packages/bao_remote/lib/src/git/git_runner.dart`（198） | `setGitProcessEnvironment` / `gitProcessEnvironmentMap()`；两处 `Process` 调用改用；`gitTimeoutFor` 超时策略 | ~+25 ⇒ ~223 | +57（255） | 超 32 |
| ⑥ | `lib/main.dart`（803） | `startNetworkProxy` 之后 1 行注入 | ~+3 ⇒ ~806 | +5（808） | 超 2 |
| ⑦ | `lib/ide/ide_workbench.dart`（5185） | 引擎创建 / 销毁；resume 触发；状态栏 branch 项加 `↓N` + 上次成功；`_gitChanged` 比较补 behind / lastFetchAt / issue | ~+55 ⇒ ~5240 | +96（5281） | 超 41 |
| ⑧ | `lib/ide/git/ide_scm_view.dart`（4099） | `_headLabel` 不含 `↓N`；`↓N` 紧贴获取按钮右侧；仓库头 tooltip 加上次成功与 issue（§12.6） | ~+20 ⇒ ~4119 | +19（4118） | 内 |
| ⑨ | `lib/settings/pages/git_settings.dart`（新） | 三个设置行（两个开关 + 周期下拉） | ~110 | 112 | 内 |
| ⑩ | `lib/settings/pages/general_page.dart`（867） | import + IDE 分组后插入 `GitSettingsGroup` | ~+2 ⇒ ~869 | +2（868） | 内 |
| ⑪ | `lib/l10n/app_en.arb`（7035） | 新增 19 键（设置、通知、tooltip） | ~+30 | ~69 行 / 19 键（7100） | 超（键 19 vs ~12） |
| ⑫ | `lib/l10n/app_zh.arb`（2706） | 同键中文 | ~+25 | +19（2725） | 内 |
| ⑬ | `lib/l10n/app_localizations.dart`（16306）/ `_en.dart`（9956）/ `_zh.dart`（9417） | `flutter gen-l10n` 重新生成（不手改） | ~+90 / ~+60 / ~+60 | +119 / +81 / +75（16425 / 10037 / 9492） | 超（含他批键；未手改） |
| ⑭ | `test/ide/git/fake_git.dart`（217） | 补 `merge` / `diff --name-only` 的可编程应答 | ~+12 ⇒ ~229 | +18（235） | 超 6 |
| ⑮ | `test/ide/git/git_autofetch_test.dart`（新） | 策略 + 引擎单测（随批删） | ~260 | 893 | 超 633（随批删） |
| ⑯ | `docs/design/ide-git.md`（新） | 本档（§1–§12） | 文档 | 621（2026-10-19 `wc -l` 实测） | — |

预算净增：手写产品码（①–⑫）~+735；l10n 生成产出（⑬）~+210；测试（⑭⑮）~+272。

超预算原因（按类归并，不逐档展开）：① ② 承担 §3.5 全表（25 条 stderr 词 / 9 类 kind / 每类文案与「等」截断）与 §4.3 十步链、四类触发及防抖 / 单飞 / 去重，预算未计注释与文案组装；⑤ 承担超时分类与按次求值注入；⑦ 多出换工作区 / 换 settings 重建引擎与两处 tooltip 组装；⑪ 的 19 键对应 §3.5 的 6+3 类与 §11 的设置 / 通知 / tooltip 各自文案；⑮ 覆盖 §9 清单 + §7 七行。⑬ 的超额含同仓其它在途改动（生成器全量重写，未手改）。

⑥ ⑩ ⑪ ⑫ ⑬ 是共享档：本次改动之前已有另一在途批的未提交改动，当前行数含那一部分，故「编制时行数 + 本次净增」不一定等于当前行数。

设置控件只读复用、不改：`lib/settings/pages/settings_widgets.dart:369`（`SettingsSwitchRow`）、`lib/settings/pages/settings_dropdown.dart:12`（`SettingsDropdown`）——`git_settings.dart` 只 import。

### 5.1 体积档的缝与触发（>500 / >800）

源码档按行数分档：本批改动后跨 500 的档、已在 >500 或 >800 的档，都给缝与触发。`lib/l10n/*.arb` 是本地化资源（按语言分档的数据文件），`app_localizations*.dart` 是 `flutter gen-l10n` 的生成物——两者不是 Dart 源码，不属源码行数档的对象。测试档（`test/**`）不属源码行数档：单测文件随批删除（§9），不进长期名单；本批唯一的 >800 测试档在表末单列处置。

| 档（编制时 → 实施后） | 档位 | 本批碰法 | 缝（拆出点） | 触发 |
|---|---|---|---|---|
| `lib/ide/git/git_service.dart`（613 → 640） | 500–800 | 新增 `fastForward` / `changedPaths`（+27），接在 fetch / pull 旁 | 历史 / 图查询命令段（`show` / `blame` / `log` / `fileLog` / `commitChanges`，380-613 一带）⇒ `git_history_service.dart` | 下次碰历史命令段，或文件 >700 行 |
| `lib/ide/git/git_repository.dart`（477 → 521） | 本批跨 500 | 同步 / 操作段新增 `fetch` / `pull` / `sync` 记账、`fastForward()`、`incomingPaths()`（+44） | 图加载段（`loadMoreGraph` / `_reloadGraph` / `_loadGraph`，397-455）⇒ `git_repository_graph.dart` | 下次碰图段，或文件 >600 行 |
| `lib/ide/git/ide_scm_view.dart`（4099 → 4118） | >800 | 只改 `_headLabel`（不含 `↓N`）与仓库头 tooltip（+19）；`↓N` 位置见 §12.6 | 仓库头/分支两个 widget（`_repositoryRow` 2165-2260、`_RepositoryBranch` 4070-4098）⇒ `scm_repository_row.dart` | 下次碰仓库头，或文件 >4300 行 |
| `lib/ide/ide_workbench.dart`（5185 → 5281） | >800 | 引擎接线 + 状态栏 branch 项（+96） | 状态栏构造（`_statusBar` 4573-4681）⇒ `ide_status_bar_items.dart` | 下次状态栏功能，或文件 >5400 行 |
| `lib/settings/pages/general_page.dart`（867 → 868） | >800 | 只加 1 个 import + 1 个 `GitSettingsGroup`（+2）；新设置行全在 `git_settings.dart`（⑨） | IDE 设置分组段（469-509 一带）⇒ `ide_settings_group.dart` | **存量债**：下次碰 IDE 设置分组，或文件 >900 行 |
| `lib/main.dart`（803 → 808） | >800 | 1 行代理注入（+5） | 启动接线块（157-163 一带）⇒ `bootstrap_network.dart` | 下次启动接线，或文件 >850 行 |
| `lib/ide/git/git_model.dart`（1278） | >800 | **不碰**（新字段在 repository） | — | — |
| `test/ide/git/git_autofetch_test.dart`（新，893） | 测试档（>800） | 45 条单测（§9） | 不拆 | **随批删除，不进长期名单**（单测零保留） |

本批不拆 500–800 两档的理由：新增方法都落在既有调用链（`fetch` / `pull` / `_operate`）旁，拆档会把一次操作跨两个文件、扩大评审面；按上表缝与触发留到下次碰该段时拆。

## 6. 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | 引擎 = 工作台级 `IdeGitAutoFetch`，独立于 SCM 视图 | 定时器不能随视图卸载；多仓列表在 workspace。被否：放 `IdeScmViewState`（侧栏重建即停） |
| D2 | 快进 = `fetch` + `merge --ff-only` | 一次联网、无合并提交、分叉干净失败（git 文档逐字，§2.3）。被否：`git pull --ff-only`（二次联网、受 pull 配置影响）；`git pull`（可能产生合并/冲突，违反需求 §3） |
| D3 | 代理 = 环境变量注入 `runGit` | 复用 `ProxyRoute.environment` 与 Claude Code 同口径；不进命令行。被否：`-c http.proxy`（凭据进 argv；且会盖掉用户 gitconfig）；新增 `git.proxy` 设置（需求明确复用网络页） |
| D4 | clean = `state.resources.isEmpty`（含未跟踪，ignored 不计） | 需求 §2.2① 字面；保守挡住「未跟踪文件被远端覆盖」的边角。被否：只算 tracked（与字面不符） |
| D5 | 网络类失败静默，认证 / 冲突 / 缓冲通知 | 需求 §2.5 / §4.6；后台重试天生会恢复，通知只会变成噪声。被否：所有失败都通知（每 3 分钟刷屏） |
| D6 | 脏缓冲相交 ⇒ **整仓本轮不拉**，提示相交文件名；保存 / 关闭后下轮自动拉；其余仓库照常 | 用户 2026-10-19 02:06 裁定 A：快进整仓原子，无法只跳文件；先拉会让磁盘与旧缓冲错位，保存时撞 `expectedText` 基线报冲突（`lib/ide/ide_workspace.dart:1169-1180`）。被否：B「照常快进、脏缓冲不重载」（留下上述隐患） |
| D7 | `↓N` 加到状态栏 branch 项与 CHANGES 仓库头 | 脏树时 Sync 按钮被 Commit 顶掉（`ide_scm_view.dart:1889-1901`），必须另设常显面；需求 §4.2 硬验收。被否：只靠 Sync 按钮 |
| D8 | 并发 4 | 17 进程同时起会抖；4 个 worker 够用。被否：无界 `Future.wait`（既有 `_fetchAll` 的形，17 仓时压力大） |
| D9 | `runGit` 按命令名给 300 秒（放宽档），其余 60 秒 | 慢代理 / 大仓下 60 秒必杀，autofetch 永远不成功；策略在 runner 内，本地与远端 host 同时生效。被否：全局放宽（status 卡死 5 分钟）；给协议加 timeout 字段（跨仓面变大）。批 13 把 `merge` 同列放宽档（写工作树，被杀代价更高；档位与理由见 §3.3） |
| D10 | autoPull 从属于 autofetch（总开关关 ⇒ 全停） | 需求 §4.7「关掉即完全停止」。被否：autoPull 独立触发自己 fetch（两个定时器、语义重叠） |
| D11 | 上次成功时间只在内存 | 需求只要求可见；重启后首轮（≤3 秒）即填。被否：落 storage（写盘与多窗口同步成本） |
| D12 | 单轮 fetch 失败后仍做 auto-pull 判定 | 多 remote 仓：一个坏 remote 不应让上游的新提交永远拉不下来；behind 来自已刷新的 ref，快进仍安全。被否：fetch 失败即中止该仓本轮 |
| D13 | 同进程同仓单飞；跨进程靠 git 锁 | 多窗口打开同一仓是正常态；fetch 幂等，merge 冲突面已被判定链挡住。被否：跨进程文件锁（机制过重） |
| D14 | 获取按钮 = 真拉取（`fetch` + `merge`，允许合并提交） | 用户 2026-10-19 03:31 裁定；获取要能真正把远端代码拉下来，分叉也要能合。被否：只 fetch（用户报告的缺陷）；只 `--ff-only`（分叉时永远拉不下来） |
| D15 | 按钮用 `fetch` + 显式 `merge`，不用 `git pull` | 与 D2 同源：不受 `pull.rebase` / `pull.ff` 配置影响，失败面可判。被否：`git pull`（用户配置会改变行为） |
| D16 | 拉取核心收在 `IdeGitRepository.pullFromUpstream`，按钮与自动轮共用一个函数（模式 + 否决器不同） | 两条路径各写一份正是本批缺陷的来源；共用后「fetch → 判定 → 合并 → reload」只有一处。被否：按钮另写一条拉取链 |
| D17 | 判定输入 = 拉取操作内 fetch 之后现读的 `status`；读不到 ⇒ issue / 错误 | 消灭「`state == null` 即静默返回」这一类出口；判定与本次 fetch 同源，不吃陈旧状态。被否：继续读缓存 `git.state` |
| D18 | 合并失败只在「合并前无 `MERGE_HEAD`、现在有」（含复查失败按「可能已开始合并」处理）时 `merge --abort` | 用户已有的合并不能被回滚；只有我们发起的合并在冲突后才回滚。被否：无条件 abort |
| D19 | `↓N` 的数字放进获取按钮内（宽屏）；窄宽回落到分支名右侧；分支标签不再带它 | 用户 2026-10-19 20:33 点名「把数字直接放进那个按键里面」（此前 03:22 要放在获取右边；独立徽标与按钮箭头重复，现合为一个按钮）。**单源的范围 = 仓库头内部**（分支标签 vs 按钮内，同一时刻只渲染一处）。状态栏的 `↓N` 是另一个面，照常保留（§12.6-2）。被否：保留按钮右侧的独立 `↓2`（两个箭头并排） |
| D20 | 多仓获取逐仓拉取（4 并发），失败逐仓通知 | 单仓失败不影响其它仓；17 仓同时起进程会抖（D8 同口径）。被否：`Future.wait` 全起；首个失败即中止整批 |
| D21 | 自动轮口径不变：脏树整仓不拉、仅 `--ff-only`、`↓N` 常显；`git.autoPull` 只管自动轮 | 用户 2026-10-19 03:31 裁定第 3、4 条；按钮与自动轮是两套口径，用例 T2–T4 / P3 互为对照。被否：把按钮的 merge 口径套到自动轮 |

## 7. 验收对照（回指需求档 §4）

> 本表 = 此前各批（需求 §4.1–§4.7）的对照；批 13（需求 §4.8）的增量见 §12.9。

| 需求 §4 | 设计落点 | 判据（机检 / 走查） |
|---|---|---|
| §4.1 新提交、干净、可快进 ⇒ 3 分钟内 `↓N` 且自动拉入、N 归零、文件更新 | §4.1 周期 / resume；§4.3 步骤 8；§4.4 | 单测：clean + behind>0 ⇒ 调 `merge --ff-only`、reload 收到路径。走查：另一 clone push，3 分钟内文件变化、`↓N` 出现后归零 |
| §4.2 有未提交改动 或 分叉 ⇒ 不自动拉，**分支栏显示 `↓N`** | §4.3 步骤 4/5；§11 状态栏与仓库头 | 单测：dirty / diverged ⇒ 无 `merge` 调用、issue 正确。走查：改一个文件后远端有新提交，状态栏显示 `main ↓N` |
| §4.3 远端改动与脏缓冲相交 ⇒ 该仓本轮不拉、提示文件名；保存 / 关闭后下轮自动拉；其余仓库照常 | §4.3 步骤 6/7/10；§11 通知 | 单测：相交 ⇒ 无 `merge`、issue 带文件名、通知一次；保存（doc.dirty=false）后第二轮调 `merge`。走查：两仓，一仓打开脏文件，另一仓照常拉 |
| §4.4 系统代理开、gitconfig 无 `http.proxy` ⇒ 手动 + 自动 fetch 都能通 | §3.4；§2.2 偏离 3 | 单测：`gitProcessEnvironmentMap()` 含 `HTTPS_PROXY` / `http_proxy`。走查：`~/.gitconfig` 无 `http.proxy`，Settings → Network 显示系统代理 `127.0.0.1:7890`，手动 Fetch 与自动 fetch 均成功 |
| §4.5 多仓：任一仓有新提交 ⇒ 该仓处理；一仓失败不影响其它仓 | §4.2；D12 | 单测：两仓一失败，另一仓仍 fetch + pull。走查：`repos` 工作区断开其中一个 remote |
| §4.6 网络断开 ⇒ 不通知；恢复后下一周期成功 | §3.5；§4.1 链式定时器 | 单测：network 失败 ⇒ `onNeedsAttention` 零调用；下一轮成功清 issue。走查：断网 1 个周期看通知中心无新增，恢复后下周期 `↓N` 出现 |
| §4.7 三个设置项都有 UI；关掉即完全停止 | §3.2；§4.6；§11 设置行 | 单测：autofetch=false ⇒ `runNow` 零 git 调用；一轮进行中关开关 ⇒ 其余仓在快进前停下（零 merge）。走查：Settings → General → Git 三个控件在；关 autofetch 后通知/网络均无 fetch，进行中的一轮不再产生新的 merge |
| §4.8（批 13 增量：获取 = 真拉取 / `↓N` 位置） | §12.9 | 见 §12.9 的 P1 / P5 / P3 / P4 / P6 / P6a / P9 与 W1–W4 |

**走查列状态（2026-10-19）**：未执行（无 GUI 会话），待收口。

## 8. 用例表（正常 / 边界 / 错误）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| N1 | 干净 + behind 2 | 无本地改动、无脏文档 | fetch；`merge --ff-only origin/main`；reload 两条路径；behind 归 0 |
| N2 | 干净 + behind 0 | 无新提交 | 只 fetch；无 merge、无 reload、无通知 |
| N3 | 多仓 17 个 | 3 仓有新提交 | 3 仓 merge；其余只 fetch；并发 ≤4 |
| N4 | 手动 Fetch | 系统代理开 | 子进程环境含代理变量；`lastFetchAt` 更新 |
| B1 | 无 upstream / detached / unborn | — | 静默跳过，无通知、无 `↓N` |
| B2 | 未跟踪文件 | `?? a.txt` | 判 dirty，不拉；状态栏 `↓N`；tooltip 写脏树 |
| B3 | 分叉 | ahead 1 / behind 2 | 判 diverged，不拉；`↓N` 仍显示 |
| B4 | 脏缓冲相交 | 打开 `a.dart` 改字未存；远端也改它 | 判 buffered；不 merge；通知列 `a.dart`；保存后下轮 merge |
| B5 | 脏缓冲不相交 | 脏 `b.dart`；远端改 `a.dart` | 正常 merge；`b.dart` 不动（reload 只碰 `a.dart`） |
| B6 | 状态命中上限 | `didHitLimit` | 判 limit，不拉 |
| B7 | period 边界 | 10 / 7200 / `"x"` | 30 / 3600 / 180 秒 |
| B8 | autofetch 关 | `false` | 定时器取消；`runNow` 零 git 调用；一轮进行中关闭 ⇒ 其余仓快进前停下（零 merge） |
| B9 | autoPull 关 | `false`，有 behind | fetch；`↓N` 显示；不 merge |
| B10 | 代理 off | `http.proxyMode=off` | 环境变量为空串；git 直连 |
| B11 | 运行中改设置 | period 60→600 | 定时器重排；不打断在跑的一轮 |
| B12 | 扫描后发现新仓 | 17 仓陆续出现 | 2 秒内补一轮，不等周期 |
| B13 | merge / rebase / cherry-pick 进行中 | 工作树有未合并 / 已暂存改动 | 步骤 5 判 dirty，静默跳过（tooltip 脏树）；工作树干净但 git 仍在中间态 ⇒ merge 被拒（`unresolved conflict` / `not concluded your`）⇒ 判 conflict、通知一次 |
| B14 | 工作区根是仓库子目录 | `root` 在仓库顶层之下，远端改的是上层文件 | `incoming` 以仓库顶层拼接为绝对路径；求交与 reload 用同一空间，reload 正常刷新 |
| B15 | Windows 大小写差异 | 远端路径 `Lib/A.dart`，打开文档 `lib/a.dart`（脏） | 归一化键（小写）判相交 ⇒ 不 merge、通知一次；不会因大小写差异误拉 |
| E1 | 网络不可达 | `Could not resolve host` | 无通知；tooltip 网络；下轮重试 |
| E2 | 认证失败 | `terminal prompts disabled` | 通知一次；下轮同错不再通知 |
| E3 | 代理不可用 | `CONNECT tunnel failed` | 无通知；tooltip 代理 |
| E4 | 快进竞态 | 判定后文件被改，merge 拒绝 | 判 conflict；通知一次；无数据丢失（reload 未跑） |
| E5 | 单个仓 git 缺失 | 该仓抛 `IdeGitException` | 该仓 skip；其余仓照常 |
| E6 | 标签被改写 | `would clobber existing tag` | 判 conflict，通知一次（需用户删旧标签） |
| E7 | 多窗口同仓 | 两窗口同时到周期 | 同进程单飞；跨进程失败按 other 静默重试 |

## 9. 测试策略

- **单元测试（随批删）**：`test/ide/git/git_autofetch_test.dart`
  - 策略：设置解析 / 夹取；`decideAutoPull` 覆盖 N1、B1–B6、E4；`ideGitFailureOf` 覆盖 E1–E3 / E6 与 B13 的样例 stderr（含 `unresolved conflict` / `not concluded your`）；`gitTimeoutFor` 命令分类（放宽档含 `merge`）。
  - 路径归一化：B14（仓库顶层 ≠ 工作区根）、B15（Windows 大小写差异）⇒ 求交命中、`reload` 收到绝对路径。
  - 引擎：`FakeGit`（`test/ide/git/fake_git.dart`）+ 记录的 documents/reload/setting 回调：N3、B4、B5、B8、B9、B13、E1、E2、E5；通知去重（同问题两轮只一次）。
  - 环境注入：`setGitProcessEnvironment` + `gitProcessEnvironmentMap()` 合并与清空；`tearDown` 里 `setGitProcessEnvironment(null)` + `clearInFlight()`（§4.6）。
- **不做**：不新增集成套（本仓 git 面没有既有集成套）；代理 / 断网 / 17 仓走查由交付前手工执行（§7 的走查列）。
- **回归**：`test/ide/git/git_operations_test.dart:76-115` 的既有 argv 断言不变（`fetch` / `pull` 未改）；新增命令只在新用例里断言。
- **远端 host 侧超时**：`runGit` 与 `gitTimeoutFor` 在 `packages/bao_remote` 内，本地与 host 共用同一份策略 ⇒ `gitTimeoutFor` 单测覆盖命令分类（放宽档含 `merge` 300 秒 / 其余 60 秒）；交付前走查一次远端工作区的 Fetch / Pull（成功、无超时回归），远端 `status` / `diff` / `log` 仍按 60 秒。

## 10. 边界（本批不做）

- 自动轮不自动提交、推送、rebase、解冲突、改历史；`merge --ff-only` 失败就停（需求 §3）。获取按钮的合并会按 Git 语义产生合并提交（用户点击触发，§12.3）。
- 不做 submodule 递归更新；gitlink 只随快进更新指针。
- 代理只覆盖本机 `runGit`；远端工作区的 git 用 host 自己的环境；app 的其它网络面不动。
- 不读 PAC / `AutoConfigURL`（与既有 Settings → Network 同一口径，`ProxyRoute.autoConfig` 只报状态）。
- 不做凭据输入 / 存储：`GIT_TERMINAL_PROMPT=0` 保持，认证失败只通知。
- 不持久化「上次成功时间」与 issue（重启即空，首轮填上）。
- 不改 `git.fetch --tags` 的既有语义；标签被改写按 conflict 通知，不自动处理。
- 不为单仓 SCM 视图新增仓库头（状态栏承担 `↓N` / 时间）；不改 Sync Changes 按钮的既有显示条件。
- 窗口从未打开过 IDE 时不跑引擎（没有 `IdeWorkspace` / `IdeWorkbench`）；首次打开后引擎开始，之后切回聊天仍继续（工作台处于 offstage 仍构建）。

### 10.1 未核实与判定条件

| # | 未核实点 | 判定条件（实施 / 走查时确认） |
|---|---|---|
| U1 | `AppLifecycleListener.onResume` 是否覆盖 Windows 的「Alt-Tab 回前台」（现有代码只把它当状态刷新用，`lib/ide/ide_workbench.dart:1070-1075`） | 走查：切走再切回，分支栏「上次成功」时间是否在数秒内更新；不触发也不影响 §4.1 的周期兜底（≤ period） |
| U2 | `git fetch --all` 在一个 remote 失败后是否继续处理其余 remote（git 版本差异；本设计两种行为都成立） | 走查：一个仓挂坏 remote、留好 upstream，看坏 remote 失败时 `behind` 是否仍能被好 remote 刷新并自动快进 |
| U3 | 300 秒网络超时是否足够本机最慢仓库（大仓 / 慢代理） | 首次实机跑一轮后看是否有 timeout；有则按实测上调（只改 `gitTimeoutFor` 一处） |

## 11. UI / 交互决定（全部落地，无 open）

1. **状态栏 branch 项**：文本 `main ↓2 · 02:15`（`↓N` 仅 N>0；时间仅 `lastFetchAt` 已知；非当天带月日）。tooltip：`<folder> (Git) - <branch>, 切换分支` + 换行「上次成功：<时间>」+ 当前 issue 原因。点击行为不变。
2. **CHANGES 仓库头**（多仓）：分支标签为 `main*`（`*`/`+`/`!` 语义不变）；待拉取提交数在获取按钮**内**（图标 + 数字同一按钮，§12.6；窄宽时徽标回落到分支名右侧，仓库头内同一时刻只渲染一处）；行 tooltip = 根路径 + 上次成功 + issue 原因。单仓无仓库头，看状态栏。
3. **通知中心**：仅 `auth` / `conflict` / `buffered`；warning 级、非 sticky、`source: 'Git'`；文案带仓库名（根目录名）与相交文件名（最多 3 个 + 「等」）；同一问题只一次。成功与网络失败不出通知。
4. **不打断**：无模态、不抢焦点、不自动切到 SCM 视图；auto-pull 成功无提示音 / 无 toast。
5. **设置 → General → Git 分组**（新 `GitSettingsGroup`，放在 IDE 分组之后）：
   - `自动获取远端更新`（开关，默认开；说明：每 3 分钟、回到前台时补一次，覆盖工作区所有仓库）。
   - `自动拉取`（开关，默认开；说明：仅在工作树干净、可快进、无未保存缓冲相交时拉取；否则只显示远端提交数）。
   - `获取周期`（下拉：1 / 2 / 3 / 5 / 10 / 15 / 30 分钟；默认 3 分钟；非预设值按实际分钟数显示）。控件 = `SettingsDropdown`（`lib/settings/pages/settings_dropdown.dart:12`：`current` 字符串 + `entries()` 返回 `IdeMenuEntry`；没有 `enabled` 参数，周期行也不需要灰显）。写入秒；选默认值写 `null`（默认不落盘）。
   - 关闭 `自动获取远端更新` 时，`自动拉取` 开关行 `enabled: false` 灰显（`SettingsSwitchRow` 支持）；周期行保持可改，重开后生效。行为上「完全停止」由引擎门保证。
6. **错误文案**：通知与 tooltip 一律走 l10n（en / zh 两源）；不把原始 stderr 直接给用户（tooltip 可带截断原文，仅英文技术细节）。

## 12. 获取 = 真拉取，`↓N` 在获取按钮右侧，自动轮的拉取修复

### 12.1 做法与理由

获取按钮不再是「只 fetch」：点击 = **真拉取** —— 先 fetch 拿到远端 ref，再把上游合入当前分支（允许产生合并提交）；本地修改与远端改动相交、或暂存改动落在远端同样改动的文件上时由 Git 在合并前拒绝（快进路径下不相交的暂存改动不被拒绝，见 P4），按钮把 Git 的原话报给用户，并保证工作树不留在半合并状态（失败时 `git merge --abort`）。自动轮保持 A 口径：脏树整仓不拉、`--ff-only` 快进、`↓N` 常显。

两条路径不再各写一份：拉取核心收在 `IdeGitRepository.pullFromUpstream`，自动轮传入「A 口径否决器」并按 `--ff-only` 合并，按钮传入 `merge` 模式且不否决。判定输入改为**拉取操作内、fetch 之后现读的 `status`**；读不到就记 issue（自动轮）或报错（按钮），不再有「`state` 为空 ⇒ 当作无事可做」的静默返回。

`↓N` 从分支名后移到「获取」按钮右侧（同一行动作组），分支标签只留分支名与 `*` / `+` / `!`；**仓库头内**同一时刻只渲染一处（窄宽时回落到分支名右侧）。状态栏 branch 项的 `↓N` 不动，两处并存（§12.6-2 的裁定）。

### 12.2 共用拉取核心（接口契约）

```dart
enum IdeGitPullMode { fastForwardOnly, merge }

/// 自动轮的否决器：拿到 fetch 之后的状态与上游改动文件，决定拉不拉、显示什么。
/// pull=false 时 issue 是跳过原因（无事可做 ⇒ null）。
typedef IdeGitPullVeto = ({bool pull, IdeGitAutoFetchIssue? issue}) Function(
  IdeGitState state,
  List<String> incoming,
);

class IdeGitPullOutcome {
  final String root;                  // 仓库顶层（脏缓冲复查用）
  final List<String> updated;         // 本次合并改动的绝对路径（reload）
  final IdeGitAutoFetchIssue? issue;  // 未拉的原因（自动轮）；null = 已拉或无事
}

IdeGitRepository.pullFromUpstream({
  required IdeGitPullMode mode,
  IdeGitPullVeto? veto,
}) → Future<IdeGitPullOutcome>
```

一次 `_operate`（同一队列、同一次 busy 周期、末尾一次强制刷新）：

1. `service.fetch()`。`merge` 模式失败即抛（按钮报原文）；`fastForwardOnly` 模式记下 fetch issue 继续（D12：坏 remote 不应让上游新提交永远拉不下来）。fetch 成功记 `lastFetchAt`。
2. `service.status()` —— **fetch 之后现读**。null / 抛错：`merge` 模式抛出；`fastForwardOnly` 模式记 `other` issue（detail = 原话），不合并。
3. `head.branch == null` / `upstream == null` / `unborn`：`merge` 模式抛「无可跟踪的上游」；自动轮按无事可做返回（保留 fetch issue）。
4. `incoming = service.changedPaths('HEAD', upstream)`（绝对路径）。
5. 否决器（仅自动轮）：`ideGitAutoPullBlocker` → `decideAutoPull`（脏树 / 分叉 / 命中上限 / 缓冲相交），再加「快进前按仓重读 `git.autofetch`」。`pull == false` ⇒ 返回 `issue = ideGitPullIssue(fetchIssue, vetoIssue)`。
6. 合并：
   - `merge` 模式：先 `merging()`（`rev-parse --verify -q MERGE_HEAD`）——退出 0 ⇒ true；退出 1 且 stdout / stderr 皆空 ⇒ false；stderr 非空 / 仓库不可读 / 其它非 0 ⇒ 抛 `IdeGitException`（§3.3）。已在合并中 ⇒ 抛错，**不 abort**（用户自己的合并不能被回滚）。然后 `service.merge(upstream)`（`merge --no-edit <upstream>`）。
   - **合并失败的回滚**：失败后复查 `merging()`——false ⇒ 直接抛合并原话（失败没留下合并状态）；true ⇒ `service.abortMerge()`，再抛合并原话。
   - **复查失败**：复查 `merging()` 自身抛错 ⇒ 按「可能已开始合并」处理——仍调 `service.abortMerge()`；抛给调用方的错误 = 合并原话 + 复查原话（两段拼接），**复查失败不得顶掉合并原话，也不得跳过 `abortMerge()`**；工作树可能仍留 `MERGE_HEAD` / 冲突标记（已知限制，同下条）；abort 也失败 ⇒ 错误再拼 abort 原话。
   - `fastForwardOnly` 模式：`service.fastForward(upstream)`（`merge --ff-only`，永不产生合并提交）；失败按现有分类记 issue。
   - **abort 失败**：`abortMerge()` 自身失败 ⇒ 不重试；抛给调用方的错误 = 合并原话 + abort 原话两段，工作树可能仍留 `MERGE_HEAD` / 冲突标记——这是已知限制，文案提示用户用 `git merge --abort` 收尾（§12.3）。
7. 成功 ⇒ 返回 `root` / `updated`；自动轮在引擎里 `reload(updated)` 并做 §4.3 第 10 步的迟到缓冲复查，按钮在视图里 `host.reload(updated)`。

`IdeGitService` 新增：`merge(ref)`（`merge --no-edit <ref>`；失败消息取 stderr、空则取 stdout，截 500 字——冲突摘要常在 stdout）、`merging()`、`abortMerge()`（`merge --abort`）。`ideGitPullIssue(fetch, pull)` 沿用原 `_reported` 的优先级：需要用户动作的一类压过跳过；同类取合并侧。

### 12.3 获取按钮 = 真拉取（失败不覆盖本地）

| 情况 | Git 的结果 | 按钮的反馈 |
|---|---|---|
| 干净、落后、可快进 | 快进 | 文件更新，`↓N` 归 0；无提示 |
| 已是最新 | `Already up to date.` 成功 | 无事发生；无提示 |
| 干净、分叉、无冲突 | 合并提交 | 文件更新，`↓N` 归 0；无提示 |
| 本地改动与远端改动相交 | 合并**前**拒绝（本地改动不被覆盖） | 错误通知：仓库名 + Git 原话；工作树原样 |
| 有暂存改动（index ≠ HEAD） | 快进路径：暂存改动落在远端同样改动的文件上 ⇒ 合并前拒绝；不相交的暂存改动不拒绝（本机 Git 实测，P4）。分叉走真合并 ⇒ 合并前拒绝 | 拒绝时同上（错误通知：仓库名 + Git 原话；工作树原样） |
| 分叉且冲突 | 合并停下、写 `MERGE_HEAD` | 立即 `merge --abort` 回滚；错误通知：仓库名 + Git 原话；无冲突标记、无 `MERGE_HEAD`。abort 自身失败 ⇒ 通知带两段原话、工作树可能留半合并（已知限制，§12.2 步骤 6） |
| 已有合并在进行 | 拒绝（我们先拒绝） | 错误通知；**不动**用户已有的合并 |
| 无上游 / detached / 无提交 | 拒绝 | 错误通知 |
| fetch 失败（网络 / 认证 / 代理） | 无合并发生 | 错误通知：Git 原话 |

- 按钮只走 `fetch` + `merge`，不读 `pull.rebase` / `pull.ff`；`git pull` 不在按钮路径上（D15）。
- 「不覆盖本地修改」由 Git 自身的合并前检查保证：相交即拒绝；未相交的本地改动在合并中被保留（`git-merge.adoc`：*It is possible to have modifications in the working tree as long as they do not overlap; the update will preserve them.*）。
- 回滚边界照 `git-merge.adoc`：相交改动、以及与远端改动相交的暂存改动，由 **git 的合并前检查**挡住，根本不会开始合并（不相交的暂存改动在快进路径下不被拒绝，P4 实测）；`--abort` 只处理**真冲突**（合并已开始、冲突已写入）这一个窗口。「合并开始时已有未提交改动、之后又被改过」的极端情形下 `--abort` 可能无法完全重建，此时错误带 abort 原话（§12.2 步骤 6）。用例 P6a 覆盖「不相交本地改动 + 冲突合并」：回滚后本地改动仍在。
- 多仓：获取按钮（`git.fetch` 命令，单仓）作用于该仓，走 `pullFromUpstream(merge)`；`git.fetchAll`（视图命令，`_fetchAll`，`ide_scm_view.dart:2017-2023`）= **工作区全仓遍历**，本批逐仓改为同一 `pullFromUpstream(merge)`（每仓 `fetch --all --tags` = 单仓全 remote，§3.3）。单仓失败不影响其它仓，每个失败仓一条错误通知（仓库名 + 原话），成功的仓照常拉下，不弹汇总；P9 覆盖这个全仓面。

### 12.4 自动轮：A 口径不变 + 静默路径清零

- 判定链（§4.3 步骤 2–8）原样保留：脏树（含未跟踪）整仓不拉、分叉不拉、命中上限不拉、脏缓冲相交不拉且提示文件名；只 `--ff-only`，永不产生合并提交。
- **判定输入**改为 `pullFromUpstream` 内 fetch 之后现读的 `status`；`git.state` 不再是判定输入。旧实现的静默出口：判定读缓存 `git.state`（`git_repository.dart:42` 的 `_state`，getter 在 `:62`），`git_autofetch_engine.dart:315-316` 在 `state == null` 时直接 `return null`；`git.busy` 门在 `:252`。`status` 读不到 ⇒ `other` issue（tooltip 可见），不再返回 null 当作「无事可做」。
- **`git.busy` 门保留**（不与用户的前台操作交错）；fetch 与合并同在一次 `_operate` 内 ⇒ 一轮开始后不会有用户操作插进这两步之间。观测到的两轮 fetch 都已完成（`FETCH_HEAD` 更新），说明当轮已越过 busy 门；busy 不是这两轮的成因。
- **轮内不重试**：每仓每轮最多一次 fetch + 一次合并；失败留到下一轮（周期 / 前台恢复 / 仓库发现）。`git.autofetch` 关 ⇒ 不发起合并（§4.6 不变）。
- `git.autoPull` 关 ⇒ 只 fetch，不调用合并（引擎不调用 `pullFromUpstream`，走既有 `git.fetch()`）。

### 12.5 最近先例与公开资料

**先例（本仓，照抄形态）**：

| 面 | 先例 | 照抄的形 |
|---|---|---|
| 判定链 | `git_autofetch.dart:154-198`（`ideGitAutoPullBlocker` / `decideAutoPull`） | 原样作为自动轮否决器，不改语义 |
| fetch → 合并 | `git_autofetch_engine.dart:265-378`（`_fetchAndPull` / `_fastForward`） | 顺序与失败分类照抄；状态改现读、合并步骤收进 repository |
| 全仓遍历与单仓隔离 | `lib/ide/git/ide_scm_view.dart:2017-2023`（`_fetchAll`） | 每仓独立 `try/catch`；新增 4 并发上限（沿用 `IdeGitAutoFetch.workers`） |
| 错误上报 | `ide_scm_view.dart:718-728`（`_report` / `_run`） | 按钮路径复用；多仓在消息前加仓库名 |
| 失败分类 | `git_autofetch.dart:240-249`（`ideGitFailureOf`） | 自动轮沿用；按钮直接抛原文（用户要原因原文） |

**公开资料**：

| 来源 | 取了什么 | 用在哪 |
|---|---|---|
| git `Documentation/git-merge.adoc`（`raw.githubusercontent.com/git/git/master`，2026-10-19 读） | `--abort`：*Abort the current conflict resolution process, and try to reconstruct the pre-merge state.*；*`git pull` and `git merge` will stop without doing anything when local uncommitted changes overlap with files that … may need to update*；*will also abort if there are any changes registered in the index relative to HEAD*；真合并 *modifications in the working tree … as long as they do not overlap; the update will preserve them*；`--abort` 等价于 `git reset --merge`（`MERGE_HEAD` 存在时）；`merge [--[no-]edit]`。 | §12.2 的合并前检查、失败回滚、「不覆盖本地修改」与 `merging()` 判定 |
| VS Code `extensions/git/src/commands.ts`（同上，2026-10-19 读） | `@command('git.pull')` → `await repository.pull(repository.HEAD)`；`git.fetch` 仍只 fetch。 | 「按钮 = 真拉取」的形态先例；与上游的唯一偏离是按钮标题沿用用户词汇「获取」（工具提示写明会拉取） |

偏离：上游把 Fetch 与 Pull 分成两个动作；本产品按用户裁定把「获取」定义为 fetch + merge（tooltip 与命令说明写明），`Pull` / `Sync Changes` 的既有语义不动。

### 12.6 UI / 交互决定（全部落地）

1. **计数位置**：多仓 CHANGES 的仓库头，动作组顺序 = `Commit` · `获取`（含计数）· `Refresh` · `...`；计数在获取按钮内（图标 + 数字同一按钮，宽度按数字实际绘制量出）；仅 `behind > 0` 时显示，tooltip 追加「N 个远端提交待拉取」。窄宽形态的 `↓N` 徽标（12px、`descriptionForeground`）见第 3 条。
2. **单源（范围 = 仓库头内部）**：`_headLabel` 不再含 `↓N`（只留分支名与 `*` / `+` / `!`），计数只在获取按钮内渲染；仓库头内同一时刻只有一处计数（按钮内与窄宽徽标两种形态互斥，见第 3 条）。状态栏 branch 项保留自己的 `↓N`——这是对需求 §2.1（`↓N` 常显）与 §2.8（分支标签后不重复）张力的裁定：§2.8 的「不再重复」作用在**仓库头内部**，仓库头与状态栏是两个不同的面，两处并存是本批的有意结果。`_headLabel` 的权威描述只在本条。
3. **窄宽回落**：`roomy = maxWidth >= 220` 不成立时动作组整组隐藏（获取在 `...` 菜单里），`↓N` 回落到分支名右侧；两种形态互斥，仓库头内同一时刻只渲染一处。
4. **按钮**：图标与标题「获取」不变；tooltip 改为「获取并拉取远端提交」；`git.busy` 时禁用——唯一的禁用符号 = `_InlineAction.onPressed`（改为可空 `VoidCallback?`，`ide_scm_view.dart:3430-3448`），`busy` 时传 null；底层 `IdeActionButton.onPressed` 本就可空（`lib/ide/ide_hover.dart:380`）。点击成功无 toast / 无提示音；失败一条 error 通知（仓库名 + Git 原话）。不抢焦点、不切视图；合并后按既有 `reload` 刷新已打开文件。
5. **命令**：`git.fetch`（单仓获取）= 该仓 `pullFromUpstream(merge)`；`git.fetchAll`（`_fetchAll`，`ide_scm_view.dart:2017-2023`）= 工作区全仓遍历，本批逐仓走同一拉取（每仓 `fetch --all --tags` = 单仓全 remote，§3.3）——P9 覆盖全仓面。`Pull` / `Sync Changes` 不动。
   l10n 新增 3 键（`scmFetchAndPullAll` / `scmFetchAndPull` / `scmBehindCommits`），en / zh 两源。
   - **单仓 `...` 菜单**（`_repositoryMenu`，`ide_scm_view.dart:2089`）：「获取」（`scmFetch`，`:2126-2129`）= 该仓 `pullFromUpstream(merge)`，与仓库头获取按钮同一动作；紧邻的「从所有远程获取」（`scmFetchFromAllRemotes`，`:2131-2134`）= 该仓全部 remote 的 `fetch --all --tags`，只 fetch、不合并。
   - **单仓菜单的并列规则**：**不加提示**——菜单项没有提示面（`IdeMenuAction` 只有 `label`，`lib/ide/ide_menu.dart:62-99`；加提示要扩菜单 API）；两项按动作区分，拉取项与仓库头按钮同名同义。
   - **工作区 `...` 菜单**（Changes 面板 `_moreActions`，`ide_scm_view.dart:2868`）：「从所有远程获取」（`:2931-2934`）= 全仓逐仓 fetch + merge（§12.3），会合并 ⇒ **改文案**：独立 l10n 键 `scmFetchAndPullAll`，文案「获取并拉取所有仓库」/ "Fetch and Pull All Repositories"；与单仓只 fetch 项不共用文案。**不加提示**（菜单项没有提示面），合并语义由文案承担。
   - **命令面板 / 快捷键同源**：`git.fetchAll` 的显示名取同一键 `scmFetchAndPullAll`（`command_titles.dart:190`），快捷键默认表的英文标题同文「Fetch and Pull All Repositories」（`workbench_keybindings.dart:537-540`）——菜单、命令面板、快捷键三处同名，命令面板不再出现只 fetch 的旧名。
6. **多仓结果**：逐仓失败通知，不合并成一条；失败仓的 `↓N` 保持显示，成功的仓归 0。

### 12.7 受影响文件与预算

行数 = 2026-10-19 换行数实测（工作树）。

| # | 坐标（实测） | 改动 | 预算增量 | 预算后 |
|---|---|---|---|---|
| ① | `lib/ide/git/git_pull.dart`（新） | `IdeGitPullMode` / `IdeGitPullOutcome` / `IdeGitPullVeto` / `ideGitPullIssue` | ~75 | ~75 |
| ② | `lib/ide/git/git_repository.dart`（521） | `pullFromUpstream`（一次 `_operate`：fetch → status → 否决 → 合并/快进 → 回滚） | +65 | ~586 |
| ③ | `lib/ide/git/git_service.dart`（640） | `merge(ref)` / `merging()` / `abortMerge()` | +30 | ~670 |
| ④ | `packages/bao_remote/lib/src/git/git_runner.dart`（255） | `gitTimeoutFor` 的放宽档加 `merge`（§3.3） | +1 | ~256 |
| ⑤ | `lib/ide/git/git_autofetch_engine.dart`（389） | `_fetchAndPull` 改用共用核心 + 否决器；`_fastForward` 的判定收进否决器；`_reported`（`:300-309`）移出为 `ideGitPullIssue`（同一实体，§12.2） | ±0（上限 400） | ≤400 |
| ⑥ | `lib/ide/git/ide_scm_view.dart`（4118） | 获取按钮走 `_pull`；`_fetchAll` 逐仓拉取；`_RepositoryBehind` 徽标；`_headLabel` 去掉 `↓N`；`_InlineAction.onPressed` 可空（禁用）；按钮 key | +80 | ~4198 |
| ⑦ | `lib/l10n/app_en.arb`（7133）/ `app_zh.arb`（2748） | 3 键：`scmFetchAndPullAll`（菜单 / 命令面板 / 快捷键标题）、`scmFetchAndPull`（获取按钮 tooltip）、`scmBehindCommits`（`↓N` tooltip） | +10 / +3 | 7143 / 2751 |
| ⑧ | `lib/l10n/app_localizations*.dart`（16563 / 10120 / 9569） | `flutter gen-l10n` 重新生成（不手改） | 生成 | — |
| ⑨ | `test/ide/git/fake_git.dart`（235） | `merge`（非 ff）/ `merge --abort` 的可编程应答（`rev-parse --verify -q MERGE_HEAD` 已由 `refs` 支撑，`:93-97`） | +25 | ~260 |
| ⑩ | `test/ide/git/git_autofetch_test.dart`（893） | 否决器 / 现读 status / busy / 轮内不重试（随批删） | +80 | ~973 |
| ⑪ | `test/ide/git/git_pull_real_test.dart`（新） | 真 git 夹具：T1 / P1–P8 / P6a / S1–S2（随批删）；T2–T10 归 ⑩（FakeGit，§12.8） | 362 | 362 |
| ⑫ | `test/ide/git/scm_fetch_button_test.dart`（新） | 布局 / 按钮 / 失败通知的 widget 用例（随批删） | ~140 | ~140 |
| ⑬ | `docs/design/ide-git.md` | 本节与 §1 / §2.1 / §2.2 / §3.1 / §3.3 / §4.1–§4.3 / §4.5 / §6 / §7 / §9 / §10 / §11 的语义更新 | 文档 | — |
| ⑭ | `lib/l10n/command_titles.dart`（599） | `git.fetchAll` 的命令面板标题 → `l10n.scmFetchAndPullAll`（`:190`） | 0（一行替换） | 599 |
| ⑮ | `lib/keybindings/workbench_keybindings.dart`（1355） | `git.fetchAll` 的默认英文标题 → `Fetch and Pull All Repositories`（`:537-541`） | 0（一行替换） | 1355 |

> ⑨–⑫ 是测试档，按「单测随批删」在收口时删除；⑪ 的夹具建在系统临时目录（bare origin + 两个 clone），不落仓。`lib/ide/git/git_autofetch.dart`（300）不改：issue 模型、否决器与失败分类原样复用。
> 评审输入限制：本轮评审输入无 AGENTS.md / 文档地图（仓内均无这两个文件）；本表行数为编制者换行数实测，未逐档 spot-check——实施首轮以 `wc -l` 复核，优先超档读数（`ide_scm_view.dart` 预算后 4198、`git_autofetch_test.dart` 预算后 973），不一致以复核值为准。
> ⑭ / ⑮ 的行数为 2026-10-19 `wc -l` 实测（599 · 1355），实施首轮同口径复核。

体积档：② 586（500–800，§5.1 的缝与触发不变：>600 时拆图段）；③ 670（500–800，>700 时拆历史段）；⑥ 4198（>800，>4300 时拆仓库头）。⑭ 599 / ⑮ 1355：净 0 的一行替换，不立新缝；`workbench_keybindings.dart` 1355 行为存量 >800 档，按 §5.1 体积档政策不续拆。本批不拆：改动都贴着既有调用链，拆档会把一次拉取跨三个文件。

### 12.8 用例表

**P = 获取按钮（真 git）**

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| P1 | 干净 + 落后、可快进 | clone + origin 前进 2 条 | 按钮拉下代码；HEAD 前进；`↓N` 归 0 |
| P2 | 已是最新 | 无新提交 | `Already up to date.` 成功；无变化、无提示 |
| P3 | 本地修改与远端改动相交 | 本地改 `a.txt`，远端也改 `a.txt` | 合并前拒绝；`a.txt` 保持本地文本；无 `MERGE_HEAD` |
| P4 | 暂存改动落在远端同样改动的文件上 | 可快进路径：`git add a.txt`（远端也改 `a.txt`）；不相交的暂存改动本机 Git 不拒绝（实测；分叉走真合并时 index ≠ HEAD 即拒绝） | 合并前拒绝；index 原样；无 `MERGE_HEAD` |
| P5 | 分叉、无冲突 | 本地 1 条 + 远端 1 条（不同文件） | 合并提交（2 个父）；文件都在 |
| P6 | 分叉且冲突 | 两边都改同一行 | 失败；无 `MERGE_HEAD`、无冲突标记；文本 = 本地；错误带 Git 原话 |
| P6a | 不相交本地改动 + 冲突合并 | 本地改 `b.txt`（不参与冲突）；两边改 `a.txt` 同一行 | 合并开始、冲突 ⇒ `merge --abort`；`b.txt` 的本地改动保留；无 `MERGE_HEAD`、无冲突标记；错误带 Git 原话 |
| P7 | 已有合并在进行 | 先制造 UU 状态 | 拒绝；**不动**既有合并（`MERGE_HEAD` 仍在，不 abort） |
| P8 | 无上游 / detached | 分支无 upstream | 错误通知；工作树不动 |
| P9 | 多仓、一仓失败 | 两仓：一仓正常、一仓无上游 | 正常仓拉下；失败仓一条错误通知（带仓库名）；另一仓不受影响 |
| P10 | 按钮忙碌 | 该仓有前台操作 | 按钮禁用（`onPressed = null`） |

**W = `↓N` 布局（widget）**

| # | 场景 | 期望 |
|---|---|---|
| W1 | 多仓、roomy、behind 2 | 动作组顺序 `Commit` · `获取` · `Refresh` · `...`；数字 `2` 在获取按钮内且不溢出按钮盒；行内无独立 `↓2` |
| W2 | 同一行分支标签 | 分支文本不含 `↓`（仓库头内单源） |
| W3 | behind 0 | 获取按钮内无计数 |
| W4 | 窄宽（<220） | 动作组不渲染；`↓N` 在分支名右侧；仓库头内只有一处 `↓N` |
| W5 | 状态栏 | branch 项仍为 `main ↓2`（不受仓库头影响；两处并存是 §12.6-2 的裁定） |

**S = service 契约（真 git）**

| # | 场景 | 期望 |
|---|---|---|
| S1 | 无合并进行 | `rev-parse --verify -q MERGE_HEAD` 退出 1、输出空 ⇒ `merging()` == false，不抛 |
| S2 | 合并进行中（P7 制造的 UU 状态） | `merging()` == true |

**T = 自动轮（真 git + FakeGit）**

| # | 场景 | 期望 |
|---|---|---|
| T1 | 干净 + behind 2，一轮 `runNow` | fetch + `merge --ff-only`；HEAD 前进；`updated` 含远端改动文件；behind 0 |
| T2 | 脏树（未跟踪文件） | 零 merge；issue = dirty；`↓N` 仍在 |
| T3 | 分叉 | 零 merge（不产生合并提交）；issue = diverged |
| T4 | 脏缓冲相交 | 零 merge；issue = buffered + 文件名；保存后下一轮 ff |
| T5 | status 读不到（注入失败） | issue = other（不为 null）；零 merge |
| T6 | `git.busy` | 本轮零 fetch（保留 busy 门） |
| T7 | `git.autoPull` 关 | 只 fetch；零 merge |
| T8 | 两仓、一仓 fetch 失败 | 另一仓仍判定并快进；失败仓 issue 按分类 |
| T9 | 缓存 `state` 与现读 status 不一致 | repository 先按 behind 0 载入 `state`；FakeGit 的 status 改为 behind 2 后跑一轮 | 仍发起 `merge --ff-only`（`callsTo('merge')` 非空）——判定读现读 status，不吃缓存 |
| T10 | fetch 成功但按 A 口径不拉 | 脏树（未跟踪文件）+ 远端 behind 2 | 零 merge；刷新后 `state.head.behind == 2`（状态栏 / 仓库头由此出现 `↓N`） |

### 12.9 验收对照（本批三件事 / 两条口径 / 一处改名）

| 条目 | 设计落点 | 判据（机检 / 走查） |
|---|---|---|
| ① 自动轮 fetch 到了却不快进 | §12.2 / §12.4；D17 | T1：真 git 一轮后 HEAD 前进、behind 0；T5：status 不可读 ⇒ issue ≠ null；T6：busy 门仍在；T9：缓存 `state` 与现读 status 不一致 ⇒ 仍合并；T10：fetch 成功但按 A 口径不拉 ⇒ behind 保留（`↓N` 出现） |
| ② `↓N` 移到获取按钮右侧 | §12.6；D19 | W1 / W2 / W3 / W4：动作组顺序断言、`_headLabel` 不含 `↓`、仓库头内单源（W5：状态栏照旧） |
| ③ 获取 = 真拉取（fetch + merge），失败可见且工作树不留半合并 | §12.2 / §12.3；D14–D16、D18 | P1 / P5：HEAD 前进、分叉产生合并提交；P3 / P4 / P6：错误通知含 Git 原话，工作树原样、无 `MERGE_HEAD`、无冲突标记；P6a：回滚后不相交的本地改动仍在；S1 / S2：`merging()` 无合并 ⇒ false、合并中 ⇒ true |
| ④ 自动轮 A 口径不变 | §12.4；D21 | T2 / T3 / T4 / T7：零合并提交；P3 的同场景下自动轮仍零 merge |
| ⑤ 多仓单仓失败不影响其它 | §12.3；D20 | P9：另一仓 HEAD 前进；失败仓通知带仓库名 |
| ⑥ 命令面板 / 快捷键不再出现只 fetch 的旧名 | §12.6-5 | 机检：两源 ARB 含 `scmFetchAndPullAll`；`command_titles.dart` 的 `git.fetchAll` 行取该键、`workbench_keybindings.dart` 的 `git.fetchAll` 标题为 `Fetch and Pull All Repositories`——三处同名 |

走查（交付前）：真机点一次获取（干净可快进）看文件更新与 `↓N` 归 0；制造一次冲突看错误与工作树回滚；多仓里断开一仓 remote 看其余仓照常。

### 12.10 边界（本批不做）

- 不做冲突解决界面：冲突一律回滚 + 报错，用户自行决定后再点。
- 不做 `pull --rebase` / 不读 `pull.rebase`；不改 `Pull` / `Sync Changes` 的既有语义。
- 不给自动轮加「脏树也拉」：A 口径不变。
- 不新增设置项；`git.autoPull` 仍只管自动轮。
- 不做定时器之外的轮内重试；不做失败后的立即补偿轮。
- 不改状态栏的 `↓N`；不改单仓无仓库头时的既有形态——单仓没有仓库头，`↓N` 由状态栏承担（需求 §2.8 的适用面是**多仓仓库头**，故单仓不新增「按钮右侧」位）。
- 不处理 submodule 递归；不改远端 host 的 git 行为。

