# 2026-10-17 · ide-health-audit
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-17 · 来源 = 用户 2026-10-17 21:19「以专业架构师角度把 IDE 做得更稳定、更清晰、更高效」+ 三路只读体检（explore #86/#87/#88）。
> 台账 = #42（thincoder-adapter · 归批）。前情 = 无（独立批）。后续实施批的台账 = #43（A 稳定性）/ #44（B 流式）/ #45（C 重建范围）/ #46（D 重复机制）/ #47（E 结构）/ #48（F 文档）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-17
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 体检报告（三路只读 · 2026-10-17）

### 元信息

- 方法：三路只读静态核查（explore #86 稳定性 / #87 清晰度 / #88 效率），**未运行应用、未跑测试、未改任何文件**；量级一律标「推断」，只有代码常量可证者例外。
- 体量读数（主 agent 实测）：`lib/` 700 个 Dart 文件；>500 行 157 · >800 行 77 · >1200 行 44。最大值见 C 表。

### E 表 · 效率（#88）

| # | 收益 | 位置 | 症状 | 修法 | 实测/推断 |
|---|---|---|---|---|---|
| E1 | 高 | `chat_history_view.dart:2090`（触发 `:1214`） | 每个流式增量 `setState` + `build` 里 `_built = null` ⇒ 整树重算（含 `cacheExtent: 900` 内行），20–60 次/秒 | 不变的壳提出重建路径，只让流式那条重建 | 推断（常量可证） |
| E2 | 高 | `step_folds.dart:65-70` | 每个增量整体重算折叠（成本 ∝ 条目总数 N） | 只重算最后一个回合 | 推断 |
| E3 | 高 | `ide_workbench.dart:4675` | 整台工作台在 `ListenableBuilder(workspace)` 内，每次重建 `_allCommands()`（约 70 处 `IdeCommand` 构造） | 按状态版本缓存命令表 | 推断 |
| E4 | 中 | `composer.dart:374/:813-866` | 每次按键/光标移动：`toPlainText` + `toDelta` + 整框 `setState`；工具栏 `_polishText()` 再算一次 | 变化时算一次存起来 | 推断 |
| E5 | 中 | `chat_history_view.dart:2122` | 每次 build 遍历全部条目收集图片（`foldImages`，O(N)） | 按 itemCount + 末条身份缓存 | 推断 |
| E6 | 中 | `markdown_view.dart:83-98` | 流式中每条消息整篇重解析（长回复 O(L²)） | 按块缓存或 ≥50ms 节流 | 推断 |
| E7 | 中 | `chat_history_view.dart:1857-1874` | 可见折叠行每次重建都把整段折叠重新收集（work 2 次 / steps 2 次） | 每次 build 每段只收一次 | 推断 |
| E8 | 中 | `sidebar.dart:1777` | 拖动重排 `Timer.periodic(16ms)` 里 `jumpTo` + `refresh()`（每帧 setState） | 换 `Ticker`，仅落点变化时 setState | 推断（16ms 常量可证） |
| E9 | 低 | `paste_store_io.dart:11-26` · `data_dir.dart:413-421` | 发送时同步 sha256 + `existsSync` + `writeAsStringSync(flush:true)`；启动写-删探测，均在 UI isolate | 改异步（同档已有异步读） | 推断 |
| E10 | 低 | `main.dart:145-369` | 首帧前 7 步串行 await（设置 / 代理 / onboarding / 恢复 / 窗口 / 启动请求 / 快捷键） | 互不依赖的 `Future.wait` | 推断 |
| E11 | 低 | `ide_editor.dart:2232-2293` | 编辑器每次 build 现构造 `DiffEditorColors` / style / `parts` | 入参变化时算一次 | 未验证（实现在 `packages/bao_editor`） |

**确认不是问题**（同样有价值）：会话列表已虚拟化（`SuperListView.builder:2214`）· 侧栏 `ListView.builder` + `itemExtentBuilder:1298` · 折叠隐藏行已按实例记忆化（`:1763-1793`）· markdown 非流式有缓存 · 侧栏排序只在脏时重算 · 终端渲染走 `markNeedsPaint`、光标闪烁 500ms 级 · `workspace.notifyListeners` 里的 `jsonEncode` 有快照早退（`:2215`）。

### S 表 · 稳定性（#86）

| # | 级别 | 位置 | 症状 | 修法 |
|---|---|---|---|---|
| S1 | 🟡 | `app_windows.dart:903` / `:1048` | `_remove` 在 `await leaveFullScreen` 之后才摘除 ⇒ 期间任何通知重入同一关闭（重复 `host.close` / `_save` / `_quitIfNoneShows`） | 加在途集合，或把摘除提到首个 await 之前 |
| S2 | 🟡 | `ide_workbench.dart:2878` / `:2898` | chord 等待态只判应用级生命周期 ⇒ 在 A 窗按前缀键、切到 B 窗打字，执行的是 **A 窗命令** | 补窗口可见/焦点判断（`_onLateKey:2863` 已有同款） |
| S3 | 🟡 | `workbench.dart:3349/:3360/:3378` | 仓库扫描失败被静默吞掉且缓存置空 ⇒ **整场会话不再重试**，用户只见"没有仓库" | 失败项清出缓存 + 一条可见提示 |
| S4 | 🟡 | `thincoder_kernel.dart:988/:999` | 模型/模式回调 `unawaited(_config)` 直接 `_connection!`；释放后点即空断言（UI 表现"点了没反应"） | 入口判空返回或给提示 |
| S5 | 🔵 | `ide_editor.dart:2106/:2118` · `:2227` | `_surface()` 无条件 `_nativeController!`；diff 的 `modified` 回调绕过 build 的 null 守卫 | 判空返回 |
| S6 | 🔵 | `terminal_view.dart:643` · `terminal_panel.dart:410` | 菜单回调 `context.findRenderObject()! as RenderBox` | `case final RenderBox box` 不匹配就不弹 |
| S7 | 🔵 | `chat_session.dart:158` | `_apply` 无 `_disposed` 守卫却 `notifyListeners()`（同类 `_reviewChanged:210` 有） | 首行 `if (_disposed) return;` |

**排除项**：泄漏**未发现**（dispose 成对抽查：`terminal_view.dart:146/260`、`terminal_selection.dart:545`、`ide_workbench.dart:1449-1450`、`workbench.dart:693/711`、`chat_session.dart:1086`）；无退避自旋**未发现**；吞错仅 S3 一处真问题；强解引用仅 S5/S6 两处。

### C 表 · 清晰度（#87）

| # | 影响 | 位置 | 问题 | 建议 | 成本 |
|---|---|---|---|---|---|
| C1 | 高 | `workbench.dart:3506` · `ide_workbench.dart:1589` · `ide_workspace.dart:523` | "打开文件 / 打开到行"跨 4 层 ≥11 入口（图片/远程/只读/diff/聚焦各分支） | `OpenTarget {path,line,column,diff,readOnly}` + 唯一入口 | 1–2 天 |
| C2 | 高 | `kernel_types.dart:1/:3` · `claude_code_kernel.dart:7/:9-19` | kernel 层反向 import chat/settings/workspace + Flutter UI ⇒ 内核不可独立测试 | 纯 Dart `kernel_api`，图标/端口注入 | 2–3 天 |
| C3 | 高 | `claude_environment.dart:1` · `claude_haiku.dart:33` | Claude 适配器被当公共设施：env re-export 被 8 个非内核模块 import；haiku 被 7 个功能直调 | env 移 `platform/login_shell.dart`；摘要模型立端口 | env 1–2h；端口 1 天 |
| C4 | 中 | `ide_workbench.dart:643` · `ide_scm_view.dart:90` | 布尔设置读写两套且**优先级相反**（本地优先 vs 文件优先），SCM 版无清空/无监听 ⇒ 慢写回弹 | 抽 `ToggleSetting`（pending 本地优先 + 写后清 + 失败回滚） | 2–3h |
| C5 | 中 | `workspace.dart:2396` · `ide_workbench.dart:4672` | 单 `Workspace` notifier 承载 13 类状态 / 约 60 处 notify；IDE 与侧栏整树监听 | 先做 pane 脏检查（半天），再拆细粒度 notifier | 0.5–3 天 |
| C6 | 中 | `ide_workbench.dart:344` | `IdeWorkbenchState` 约 4.7k 行、10 类职责 | 第一刀 `WorkbenchSettingsStore`（643-752，约 110 行） | 0.5 天起 |
| C7 | 中 | `workbench.dart:225` · `workspace.dart:226` · `ide_scm_view.dart:81` · `chat_history_view.dart:84` | 同模式：状态机 + 持久化 + 整棵 widget 树塞进一个类 | 按已有段头切 collaborator | 每个 1–2 天 |
| C8 | 中 | `edit_step.dart:225` · `file_preview.dart:984` · `interaction_panel.dart:871` | `DiffLineType` 到前缀/颜色/背景映射写三份；行号/选区/80 行上限各自实现 | 抽 `DiffLinesView(lines,{numbers,selection,maxLines})` | 3–4h |
| C9 | 中 | `ide_workbench_keys.dart:142` · `workbench.dart:4098` | quick input 键表两份（IDE 版多 4 个 picker 变体）⇒ 聊天窗缺键无响应 | 共享 `quickInputCommands(quick)` | 1h |
| C10 | 中 | `ide_workbench.dart:4675/:2837` | 命令目录每 build 重建；每键又重建 9 组映射（同 E3） | 缓存 + 失效 | 2–3h |
| C11 | 中 | `docs/design/thincoder-adapter.md:144` / `:160` | 两处机制落后于实现（release / send），档内行号大面积漂移 | 改符号引用 | 30 分钟 |
| C12 | 低 | `repl_model.dart:154` | 公开接口抛 `UnimplementedError`（今天走不到，加 lazy 标即崩） | 实现为空操作或拆能力接口 | 30 分钟 |

### 体检自述的三条边界（不得当结论用）

- 未运行应用 / 未跑测试 / 未 profile：所有 UI 与性能结论为静态推断。
- `packages/bao_editor`（Monaco/TextMate 内核）未读 ⇒ E11 只到外壳。
- `test/` 未审 ⇒ 现有测试的断言强度未知。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

## 验证与收口（体检批 · 无实现）

### 交付物

1. **本档 §1** = 三路体检报告（E/S/C 三表 + 排除项 + 三条边界）。
2. **台账 6 行**（后续实施批）：#43 A 稳定性 · #44 B 流式 · #45 C 重建范围 · #46 D 重复机制 · #47 E 结构 · #48 F 文档。

### 核对方式（父代理实跑）

- 三探针均为 **explore（只读）**，报告自述「未改任何文件」；`git status` 复核：工作树只有本档与另两处已复核的文档改动，**零源码改动**。
- 抽查 4 条坐标与报告一致：`chat_history_view.dart:2090`（`_built = null`）、`app_windows.dart:1048`（`_remove`）、`ide_workbench.dart:4675`（`_allCommands()` 在 build 内）、`ide_scm_view.dart:90`（`_choice` 优先级）。
- 报告中的「确认不是问题」清单被作为**同等交付**保留（避免后续重复排查）。

### 结论（一句话）

底座干净（无泄漏、无自旋、无结构性不稳）；**效率只有一个真热点（流式整树重建）**；**清晰度的病根是"同一语义多套实现"**；结构债集中在 4 个巨型类与 kernel 边界。

### 排序建议（成本 × 风险 × 收益）

A（守卫，最便宜）→ B（流式，最可感）→ C（重建范围）→ F（文档，半小时）→ D（重复机制）→ E（结构，单独立项、渐进做）。

### 遗留

- 本批不含实现；实现按上表分批走「设计 → 评审 → 批准 → 实现」。
- 体检未覆盖 `packages/bao_editor` 与 `test/`——若 B 批要动编辑器/渲染，先补这一块的只读体检。
