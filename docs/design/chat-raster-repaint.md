# 对话重绘边界与出帧时机（chat-raster-repaint）设计档

> 板块：对话渲染（chat-streaming）· 范围仓：baocode。
> 本档 = 该板块第二篇：首篇 `docs/design/chat-streaming.md` 管 F1–F4（增量重建边界 / 折叠 / markdown 节流）；本档管 F5 重绘范围 · F6 出帧时机 · F8 进程创建不阻塞窗口线程 · 删预热池（回到上游形态） · N3 DPR 留痕 · N4 停顿看门狗 · N5 挂起报告可见。
> 配对需求档：`docs/requirements/chat-streaming.md`（F5 · F6 · F8 · N2 · N3 · N4 · N5）。
> 状态：设计稿 v8 · 2026-10-26 · 行数 = 本轮逐档实测，17 个既有档逐行相符（口径见 §5 表头）。
> 集成索引：`test/RTM.md`（本批建立；三条用例落 `test/integration/chat_flows_test.dart`，§8.1）。

## 1. 模块目标与范围

**一句话**：任何子进程的创建不再堵住窗口线程（F8），切会话与启动时的 6 秒冻结随之消失；长会话流式时一帧的光栅化代价只跟真正变了的那一块走（F5），窗口看不见时不付这份代价（F6）；卡顿时应用自己留下读数并让已有的事故证据浮出来（N3 / N4 / N5）。

**本批主修**：F8（进程创建移出窗口线程）。
**本批次要**：F5 重绘边界 · F6 不可见时不出帧 · N3 DPR 留痕 · N4 停顿看门狗 · N5 挂起报告可见。
**N2** 是贯穿全批的测量纪律：改前读数在动代码前量，改后同场景复量。

**本批不做**：列表虚拟化 / 分段上限 / 数据分页 · 换渲染引擎 · 数据模型与内核事件形态 · 视觉与交互形态改动 · 不迁上游低频进程调用（`forge_io.dart` · `ide/lsp/**` · `mcp_probe_io.dart` 等，§3.1）。

## 2. 事实基线（改前读数，动代码前按 N2 复量）

| 项 | 读数（2026-10-26，Release 1.7.2+19） | 来源 |
|---|---|---|
| F5 帧 | 会话 1060–1205 条、渲染对象 6163–6589、窗口 3840×2088@1.5；四条慢帧全在流式中（`raster 340–350 ms`、`build 0–9 ms`） | 会话 / 渲染对象 / 窗口 = 需求档 F5；四条慢帧 = 设计自测（Release 跑测 70 分钟窗口，末条慢帧 2026-10-26 00:32:49，`events.log`） |
| F6 状态 | 四条慢帧中 3 条 `lifecycleState == inactive`；失焦时 baocode 占 GPU 30.6–30.7%（三次采样，系统总 ~40%，`dwm` 12.5%） | 需求档 F6 |
| F8 冻结 | Windows 挂起看门狗 9 份报告：8 份窗口线程栈 = `ZwCreateUserProcess ← CreateProcessInternalW ← CreateProcessW ← app.so`，1 份 = `ZwQueryValueKey ← BasepQueryAppCompat`；报告首行 `The windows' thread took no message for 6 s` | 9 份报告与 6 s = 需求档 F8；周期 4 分 52 s、每次约 6 s = 用户 2026-10-26 02:10 逐字 |
| N3 DPR | 三显示器、同时有 1.5 与 2.25；日志 view 0 恒 `@1.5`，无 DPR 变化行 | 需求档 N3 |
| N4 停顿 | 2026-10-25 22:00–23:15 三次报卡，同期 `[slow]` **零条**、`errors.log` 零条；Windows 事件 / 崩溃转储 / 内存耗尽 / GPU TDR 全空 | 需求档 N4 |
| N5 证据 | `%APPDATA%\baocode\logs\hangs\` 已有 9 份 `hang-*.txt` + `.dmp`（2026-10-25 20:54–23:44）；`events.log` 与 `errors.log` 零条提示它们存在 | 需求档 N5 |

**读数面现成的东西**（`lib/diagnostics/frame_watch.dart`）：

- `_timings` 只在 `rasterDuration ≥ slow`（默认 250 ms）时写 `[slow]` 行（`:96-106`），行内带 `build`。
- 状态行 `_state()`（`:126-157`）已给 semantics 节点数、render object 数、在显示的会话、RSS、`lifecycleState` —— N4 直接复用它（§3.6）。
- 没有 100 ms 档 ⇒ F5 的「超预算帧数」读法见 §4.4（`tool/perf` 的 `budgetMs`）。
- 挂起报告与诊断入口已有现成件：`listDiagnosticsLogs` 把 `hangs/` 的 `.txt` / `.dmp` 按名倒序列出（`lib/diagnostics/diagnostics_bundle.dart:41-63`，名序即时间序见 `:57`），`appEvent` 写 `[category]` 行（`lib/platform/event_log.dart:45-47`、`:84-85`）—— N5 复用这两处。

## 3. 做法与理由

### 3.1 F8：进程创建移出窗口线程（主修）

**已核事实**：

- 冻结发生在 `CreateProcessW` 内部（`ZwCreateUserProcess` 与 `BasepQueryAppCompat` 两组栈），且 `app.so` 在栈上是调用方 ⇒ 这次创建是 Dart 代码在**窗口线程**（Flutter 的 platform/UI 线程）上调起的。
- 应用内的进程创建全走 `dart:io`：`Process.start` 8 处、`Process.run` 23 处、`Process.runSync` 2 处，共 **33 处**（`lib/**` 逐行检索，2026-10-26；`thincoder_process.dart:9` 的 `ThincoderProcess.start` 是自有类的方法，不算创建点）。本批只迁其中会冻窗口的两处创建点（下），其余保持上游原样。`runSync` 的两处是 `lib/kernel/thincoder/thincoder_config_store.dart:458`（`_chmod`，调用点 `:301`，同步写路径里）与 `lib/update/installer_io.dart:95`（macOS 的 `_translated` 同步 getter）。
- 会冻窗口的进程创建有**三条**，全部在窗口线程上：
  1. 会话打开时的内核自起（`thincoder_lifecycle.dart:26` 的 `owner._start(...)`；预热池删除后这里就是直连，§3.2）；
  2. **启动 / 刷新时逐项目列会话**：`workspace.dart:345` 的 `unawaited(_listKept(project, …))` → `ThincoderCatalog.sessionsIn`（`lib/kernel/thincoder/thincoder_catalog.dart:39`）→ 同档 `:27-28` 的 `_start` = `startThincoderProcess(...)`——每列一个项目起一个进程、问完即关（`thincoder_catalog.dart:10-21` 的类注释：nothing stays running between refreshes）；
  3. **设置页的版本探测**：`thincoder_locator.dart:131-134` 的 `versionOf` 走 `Process.run`。
  1、2 的创建点是**同一处**：`thincoder_process_io.dart:86`（catalog 的 `_start` 经 `thincoder_process.dart:8-9` 走到同一个 `ThincoderProcess.start`）；3 的创建点是 `thincoder_locator.dart` 的 `Process.run`。审计（台账 #173）证明路径 2 与预热池并列：只修池，启动时逐项目起进程仍冻窗口。
- **一手来源（Dart SDK）**：`runtime/bin/process_win.cc` 的 `int Process::Start(...)` 直接构造 `ProcessStarter` 并同步调用 `const auto result = starter.Start();`；`ProcessStarter::Start()` 体内即 `BOOL result = CreateProcessW(...)`。⇒ 在 `Process::Start` 返回之前 `CreateProcessW` 已经跑完，中间没有交给任何其他线程。（源：`https://raw.githubusercontent.com/dart-lang/sdk/main/runtime/bin/process_win.cc`，2026-10-26 取。）
- **未核（`unverified`）**：`dart:io` 的 `Process.start` / `Process.run` native 入口是否在**调用方 isolate 的线程**上进入 `Process::Start`（本轮未打开 `runtime/bin/process.cc` 与 `io_natives.cc`）。这条不成立时结论也不变，见下。
- **代理方案不依赖上面那条**：F8 的验收读的是**窗口线程**（挂起报告与 `[stall]`）。会冻窗口的两处创建（下方迁移面 ① ②）搬进代理后，这两条链在窗口线程上不再剩 `Process.start`；其余 31 处按 D4 / D15 保持上游原样。

**做法：一个进程代理 isolate**（新档 `lib/platform/process_host.dart`）

- **本批迁移面内唯一的进程创建入口**：一个长驻 isolate（`Isolate.spawn`，首次使用时起、随进程存活），只有它调 `Process.start` / `Process.run`——**只接管 thincoder 的两条创建链**，其余上游 `Process.*` 仍在窗口线程（迁移面已写死）。窗口线程只收发端口消息——这两条链的 `CreateProcessW` 因此落在代理 isolate 自己的线程上。
- **长驻进程**：代理持有 `Process` 对象，把 stdout / stderr 以字节块转给窗口线程侧；stdin 写入、kill、exitCode 走同一条消息通道（同一 `SendPort` 保序）。
- **一次性命令**：代理内跑完，一次性回传退出码与解码后的 stdout / stderr（编码按调用方给的，默认与 `Process.run` 相同）。
- **形状照仓库既有先例**：`lib/kernel/claude_code/dart_core_transport_io.dart:37` 用 `AgentIsolate.spawn` 把引擎放进独立 isolate、以端口说话——同一形状搬到一个只做进程创建与转发的代理上。

**失败面（业务门：显式失败，不静默回退）**：

- 代理起不来、消息通道断开、代理内 `Process.start` 抛错 ⇒ 调用方收到明确异常（`ProcessHostUnavailable` / 原 `ProcessException` 语义），由各调用点映射为既有错误类型（如 `ThincoderUnavailable`）。
- **绝不回退到窗口线程直连**：那会把 6 秒冻结放回来，且没人知道它回来了。

**迁移面（写死，只迁会冻窗口的两处创建点）**：

- **① thincoder 起进程**（`lib/kernel/thincoder/thincoder_process_io.dart:86`）→ `ProcessHost.start`。同一处覆盖两条触发路径：会话打开（`thincoder_lifecycle.dart:26`）与启动 / 刷新时逐项目列会话（`thincoder_catalog.dart:27-28` 的 `_start`）。
- **② 版本探测**（`lib/kernel/thincoder/thincoder_locator.dart:131-134` 的 `versionOf`，走 `Process.run`）→ `ProcessHost.run`。设置页打开时触发，是可计时的冻结来源（F8-D）。
- **其余 `Process.*` 保持上游原样（本批零改动）**：`forge/forge_io.dart` · `ide/lsp/**` · `customize/mcp_probe_io.dart` · `ide/git/**` · `ide/terminal/**` · `installer_io.dart` · `child_process_registry.dart` 等。它们不在冻结链上；改动只会给未来上游合并制造冲突面。将来 N4 的 `[stall]` 指向哪条，再单独迁哪条。
- **机检守门**（路径级）：一条测试断言引入 `process_host` 的档集合恰为 {`thincoder_process_io.dart` · `thincoder_locator.dart` · `thincoder_process.dart` · 三个新档}；其中创建进程的两档（`thincoder_process_io.dart` / `thincoder_locator.dart`）内零 `\bProcess.start(` / `\bProcess.run(`；`thincoder_process.dart` 只 import 以挂 `stopAll()`、自身不创建进程；其余上游档不扫、允许照旧。
- 条件导入照既有形状（`lib/kernel/thincoder/thincoder_process.dart:2-4` 的 stub / io 分档）：web 上代理不存在，`ProcessHost` 调用即失败，与今天无进程可起同义。

**为什么不是别的**：

- 不写原生线程插件：多一份 C++ 与 IPC，且每个平台各一份；isolate 是纯 Dart、跨桌面三平台同一份代码。
- 不靠「提前预热」绕开：预热本身就是一次窗口线程上的 `Process.start`，冻的还是窗口；本批已删除预热池（§3.2），两条路径要一起关，只能把创建搬出窗口线程。
- 不逐点 `Isolate.run`：`Process` 对象不能跨 isolate 传递，长驻进程必须在代理里活着；只包 `Process.run` 会留下最贵的那一类。
- 不全量迁移：只有会冻窗口的两处创建才迁（上面「迁移面」）；其余 `Process.*` 保持上游原样——自造机制越少、上游文件改得越少，未来合并的成本越低（D15）。

**验收与 N4 的关系**：F8 的验收读 `[stall]`（N4 的产出），所以 N4 必须先落地，否则 F8 只有挂起看门狗一条读数。

### 3.2 删除预热池（回到上游形态）

**做什么**：删掉 `lib/kernel/thincoder/thincoder_warm.dart` 整档（242 行）与它的全部挂点；会话打开时直接起进程，视图离开时照旧关闭。

**为什么删而不是修**（需求档 §4 的「删除预热池」条）：池当日实读 **34 miss / 0 hit**（需求档 §4）；同段 `launch: builtin` 38 行、`launch→handshake` 中位 569 ms（设计自测：2026-10-26 01:12–02:20 的 `events.log`），净亏。

上游 Claude 内核的形态是每会话一个进程、用完关闭（`lib/kernel/claude_code/process_transport_io.dart:17` 的 `ProcessTransport` 就是一进程一会话），没有池也长期可用。F8 落地后池只剩「省一次准备中等待」的价值，而 TTL / 冷却 / 换 key 即杀这套生命周期要一直维护——删掉是把复杂度归零。

**挂点（逐处删净，全部在 §5 表内）**：

| 位置 | 今天做什么 | 删除后 |
|---|---|---|
| `lib/kernel/thincoder/thincoder_warm.dart` | 池本体 | 整档删除 |
| `thincoder_lifecycle.dart:22-26` | `takeWhenReady` + `timing: warm hit/miss` + `warm?.transport ??` | 直接 `owner._start(await owner._launchFor(owner._cwd))` |
| `thincoder_lifecycle.dart:33` / `:38-53` | `warm?.connection ??` 与 `warm != null` 的握手旁路 | 只剩一条路：新建 `ThincoderConnection` 并 `initialize` |
| `lib/kernel/thincoder/thincoder_kernel.dart:28` | `import 'thincoder_warm.dart'` | 删 import |
| `lib/workspace/workspace.dart:22` · `:443` · `:448-454` · `:1303` | import、`_warmThincoder(path)` 调用、预热方法、`hideProject` 的 `drop('project-closed')` | 四处全删 |
| `test/kernel/thincoder_warm_test.dart` | 池的用例 | 整档删除 |
| `test/kernel/thincoder_kernel_test.dart` | `pool()` 夹具（`:4312-4326`）、T108 / T108②、`_NoTimer`（`:4899-4909`）、T107① 的 `timing: warm miss` 断言（`:4370`） | 删除这些；T111 保留（见下） |

**删后链路（写死）**：

```text
打开会话：ChatSession.attach → prepare() → _ensureStarted → _launch
          → owner._start(await owner._launchFor(cwd))        // 经 §4.1 的 ProcessHost.start
          → initialize 握手 → _openSession（resume ∥ 拾回 ∥ 新建）→ ready
视图离开：chat/session/lifecycle.dart:40（_views == 0）→ kernel.release()
          → _releaseWanted = true → _releaseWhenIdle()
          → 无回合 / 无启动 / 无子代理 / 未在观察 ⇒ 一个宏任务后
            _closeSession() + _teardown()（关连接与传输，进程结束）→ idle
再次打开：同「打开会话」，再起一个进程
```

- **没有新增分支**：删后的路径就是池不存在时的那条；失败面沿用 `_launchOf` 的既有 `ThincoderUnavailable` / `_fail`（`thincoder_lifecycle.dart:79-96`），不新增默认值，也不静默回退到任何池。
- **`_releaseWhenIdle` 是唯一收尾**：池删掉后，「用完关闭」只由这一条路径负责；它今天就在（`thincoder_release.dart:100-116`），本批不动。

**不是删池的东西（防误删，逐条核过）**：`ChatSession._warm` 是**内核对象**缓存（`lib/chat/chat_session.dart:201-207`、`lib/chat/session/lifecycle.dart:8-22`、`lib/chat/session/mode_state.dart:69-71`），与进程池无关，保留。

`HoverTooltip.warmWindow`（`lib/chat/floating/hover_tooltip.dart:43`）、`OutputMeter.warmUp`（`lib/kernel/output_meter.dart:29`）、l10n 文案（`lib/l10n/app_localizations_en.dart:2646`）都只是同词，不动。

需求档 §5 第 4 条的 `grep` 模式是 `thincoder_warm|warm hit|warm miss|预热池`，不含单独的 `warm`——上面这些不命中，也不该被删。

**验收**：需求档 §5 第 4 条——`grep -rn "thincoder_warm\|warm hit\|warm miss\|预热池" lib/ test/` 零命中；无池仍能起会话（打开会话 ⇒ 起进程、能输入；关掉视图再打开 ⇒ 再起一个）。判据行见 §7 的「P」行，用例见 §8 T20。

### 3.3 F5：重绘的代价在「列表外面那一层」——先量，再按判据改

**已核的负事实**：行级重绘边界已经存在。`SuperListView.builder` 的 `addRepaintBoundaries` 默认 `true`（`super_sliver_list-0.4.1/lib/src/super_sliver_list.dart:406`），调用点没关（`lib/chat/chat_history_view.dart:2642`）。
⇒ 「补行级 `RepaintBoundary`」不是本批的修法；慢帧不可能是「整表逐行重绘」。

**结构性嫌疑（代码面已核，绘制面读数待取）**：整个列表被 `EdgeFadeMask` 包住（`lib/chat/chat_history_view.dart:2620`，实现在 `lib/chat/widgets/edge_fade_mask.dart:92` 的 `RenderEdgeFadeMask`）。

- **已核代码事实**：`RenderEdgeFadeMask.paint`（`edge_fade_mask.dart:262-291`）在有遮罩时走 `context.pushLayer(mask, super.paint, offset)`，`mask` 是 `ShaderMaskLayer`、`blendMode = BlendMode.dstIn`、`maskRect` 为整个 child 加 2 px 越界；且 `alwaysNeedsCompositing => _masked`（`:199`）。
- ⇒ 只要 `_masked` 为真，整块列表区域就是一个合成层：任何一行重绘都要重跑这层 `dstIn` 的全区域合成——与「raster 340 ms、build 0–9 ms」同形（构建没变，合成面积是整块画布）。
- 待测的是「慢帧是否真的耗在这一层」（规则 2 / 3 的读数），不是「这一层是否存在」。

**决策规则（写死，实施不另裁）**：

1. **先量基线**（不改任何代码）：大会话（≥1000 条）流式回放，跑 `tool/perf` 同一场景，读 §4.4 给的入口取「raster > 100 ms 的帧数」。这一步是 N2 的改前读数。
2. **再定位**（诊断插桩，与上一步分开）：在 `RenderEdgeFadeMask.paint` 前后加临时计时并写一行日志。它只加计时与输出、不改任何绘制决策，属诊断插桩而非改前读数；收口前删除，删前把读数抄进批档。与 N2 的「动代码前量」不冲突，因为验收读数来自第 1 步。
3. 判据：若慢帧的合成耗时集中在 `RenderEdgeFadeMask` ⇒ 改法 = 把整块遮罩换成**两条固定高度的边缘渐变带**（上 ∥ 下各一条、只覆盖边缘几十像素，各自独立 `RepaintBoundary`），列表主体不再被任何全区域层罩住。
4. **若慢帧不集中在这一层 ⇒ 按固定顺序收窄，每步之间重跑规则 1 的读数**（顺序即优先级，不跳步）：① `EdgeFadeMask` 的 `ShaderMaskLayer`（`:262-291`，已验证存在的全区域合成，先排除它自己）；② `_Appear` 的 `FadeTransition`（`chat_history_view.dart:3695`，仅出现动画 260 ms 内）；③ `_HeightMotion` 的 `pushClipRect`（`:3882`，仅高度动画期）；④ 其余合成层：流式帧上 `debugDumpLayerTree` 列出 `OffsetLayer` / `ShaderMaskLayer` / `ClipRectLayer`，按「覆盖面积 = 整块列表」逐个收窄。
   **终止条件**：某一步之后 raster 超预算帧数不再集中在同一层 ⇒ 停在该层，按 §7 A / B 验收。
   **四步走完 A 仍不成立** ⇒ 停手，另起一篇设计档再动结构，并在批档记一条「F5 未达成」的读数与已排除的候选层——不在本批边改边猜。
5. 验收口径不变（§7 A / B）。

**为什么按这个顺序**：需求 N2 的「测量先行」；慢在光栅化已实测，而「哪一层在合成」只能从运行时的绘制面取，不靠读代码猜。

### 3.4 F6：不可见时不重建、不出帧，切回一次追平

**触发面**：`AppLifecycleState`，判据照既有先例 `null || resumed` 视为可见（`lib/main.dart:628-631` 的 `inFront()` 是 `_startTelemetry` 内的局部闭包，不可复用；本批的做法见 §4.2）。

**机制的持有者只有一处（写死）**：`WindowVisible` 内部注册唯一的 `WidgetsBindingObserver`（§4.2）；`ChatHistoryView` 与 `MarkdownView` 都是**订阅者**，不各自注册观察者。

```text
WindowVisible（唯一观察者）
  didChangeAppLifecycleState(state)：可见性翻转 ⇒ notifyListeners

ChatHistoryView.initState：WindowVisible.start(); WindowVisible.changed.addListener(_onVisibleChanged)
ChatHistoryView.dispose：  WindowVisible.changed.removeListener(_onVisibleChanged)

_handleSessionChanged（既有入口）：
  照常更新尾巴快照（判据随时可走快路径）
  WindowVisible.isVisible == false ⇒ _dirtyWhileHidden = true，return（不 setState、不 _liveTick++）
  否则 ⇒ 走今天的快路径 ∥ 全路径（不变）

_onVisibleChanged（由 WindowVisible 在恢复可见时通知）：
  WindowVisible.isVisible && _dirtyWhileHidden ⇒ 一次 _refold（全量）+ setState + _liveTick++；清标记
```

- **内容不丢是构造性的**：视图不缓存文本，build 时从 feed 读最新值；失焦期间的增量都在 `Transcript` 里，恢复后一次重建即最新态。
- **不重建 ⇒ 无帧**：本视图的帧源只有三个——`setState`、`_liveTick`（首篇设计档的增量重建边界）与 `Steadiness` 的到点 `setState`（调用点 `lib/chat/chat_history_view.dart:249-253`）。三个入口都过同一道 gate（新增 `_rebuild()`，内部判可见性）。
- **残余帧源（改后复采 GPU 时按这张表逐个关）**：① `MarkdownView` 的 50 ms trailing 计时器（首篇 F3 的节流）；② 输入光标的闪烁（框架自带）；③ 带动画的控件（`_Appear` 260 ms、`_HeightMotion` 只在动画期）；④ 其它 `Steadiness` 消费者（`lib/chat/steadiness.dart:40-46` 的计时器）。
- **改后复采 GPU 的处置（写死，不静默接受）**：F6 验收 ② 是应用级读数，而机制只覆盖上面两处 ⇒ 按 §7 C 的方式复采；若 `GPU Engine` 不接近 0%，按上表逐个关掉剩余帧源（每关一个复采一次）；全部关掉仍不归零 ⇒ 上报「F6 未达成 + 已关帧源清单」，不记成达标。
- **跨档指针**：本节 gate 改写了首篇的两处机制（`MarkdownView` 的 50 ms 节流 = 首篇 F3、`ChatHistoryView` 的增量重建边界 = 首篇 F1）⇒ `docs/design/chat-streaming.md` 的 F1 / F3 章节各需补一句「可见性 gate 见本篇 §4.2 / §4.3」。首篇不在本批改动面内，指针登记在此。
- **可见性判据取「失焦」而不是「被遮挡」**：需求档 F6 原文即 `lifecycle inactive`。并排使用（可见但未聚焦）时画面停在失焦那一刻，聚焦后一次到位——这是本批唯一一处用户可见行为变化，登记 §10。

### 3.5 N3：DPR 变化留痕

**机制**：一个观察者实现 `WidgetsBindingObserver.didChangeMetrics()`，每次变化读**唯一来源** `WidgetsBinding.instance.platformDispatcher.views`（`View.of(context)` 与 `MediaQuery.devicePixelRatio` 都是它的派生，本档不各读一份）。

逐 view 记 `viewId` + `devicePixelRatio` + `physicalSize / dpr`，值变化时写一行 `[viewport] view <id> dpr <旧> -> <新> size <逻辑宽×高>`；时间戳由 `appEvent` 的既有前缀给出（`lib/platform/event_log.dart:47`）。

**落点（定点，一处）**：`lib/diagnostics/viewport_watch.dart`（新档），与 `FrameWatch` / `StallWatch` / `HangReports` 同一处挂载——`lib/main.dart:155-158` 的 `if (!kIsWeb)` 块内一行 `ViewportWatch.start()`。**不在 `BaoCodeApp.build` 旁另挂**（那要 context，且会把挂载点变成三处）。既有媒体查询消费方（`lib/main.dart:872` 的 `PixelSnappedTextScaler`）不动。

**判据**：真机重现一次「放大再缩回」时，日志给出两次变化（如 `1.5 -> 2.25` / `2.25 -> 1.5`）及时刻与当时尺寸；不出现 ⇒ 这条假设被排除，按读到的结论另报。

### 3.6 N4：停顿看门狗（UI isolate 心跳）

**为什么需要**：界面线程被同步工作堵住时**连一帧都产不出**，`[slow]` 只在「画出一帧且超时」时记 ⇒ 这一类停顿零记录。实测佐证：2026-10-25 22:00–23:15 三次报卡，同期 `[slow]` 零条。

**落点**：`lib/diagnostics/stall_watch.dart`（新档），与 `FrameWatch` 同处挂载（`lib/main.dart:155-158` 的 `if (!kIsWeb)` 块内加一行）。

**机制**（形状照 `FrameWatch`，`lib/diagnostics/frame_watch.dart:31-41`）：

```text
Timer.periodic(250 ms)：
  实测间隔 = 单调时钟（Stopwatch）两次触发之差
  gap = 实测间隔 − 250 ms          // 超出周期的那一段
  gap >= 400 ms ⇒ appEvent('stall', 'gap <gap> ms; <界面状态>')
```

**为什么 gap 定义成「超出周期」，不是「两次触发的原始间隔」**：周期计时器被堵住后，下一拍要等界面线程放开才排上，原始间隔 ≈ 周期 + 阻塞时长（800 ms 阻塞 ⇒ 实测 1000–1050 ms）；而需求档 N4 的验收窗口是 700–1000 ms。取超出量 ⇒ 读数落在 750–800 ms，正好在窗口内，且这个数可以直接读作「界面线程被占住了多久」。

**周期 250 ms / 阈值 400 ms（采需求建议值）**：阈值必须大于周期，否则计时器自身的排程抖动就会触发；400 = 250 + 150 ms 余量。周期再长丢分辨率（一次 400 ms 的卡顿可能整个落在两拍之间），再短只是多几次空转（4 次/秒的计时器成本在微秒级）。

**与 F6 的关系：心跳不停，两者不互相牵连**——

- F6 关的是**帧**（`WindowVisible` 为假时不重建、不出帧，§4.2）；N4 是**计时器**，只写一行日志，不 `setState`、不请求帧，因此它不会把 F6 关掉的帧重新叫起来。
- 反过来，N4 不接 `WindowVisible`：失焦期间的停顿正是要量的东西（实测四条慢帧中 3 条 `inactive`）。若心跳随可见性停，失焦期的停顿就永远看不到。
- **一处刻意的盲区**：`lifecycleState` 为 `hidden` ∥ `paused` 时不写行（最小化 / 系统挂起）。机器睡眠会造出几十分钟的假 gap，撞掉验收里的「1 小时零误报」。
  **复现路径（可执行，写进批档）**：最小化窗口 → 让机器睡眠 30 分钟 → 唤醒并恢复窗口 → 读 `events.log`：预期零 `[stall]` 行；若临时去掉该分支，同一路径会写出一行 gap ≈ 1,800,000 ms。代价写明：最小化期间的停顿不测。

**行里带什么**：`gap` + `FrameWatch` 已有的状态行（semantics、render objects、在显示的会话、内存、`lifecycleState`，`frame_watch.dart:126-157`）。做法：把那一段提成档内共享函数，两处调用——一处定义（D11），`[stall]` 与 `[slow]` 的字段因此可直接对读。

**不刷屏**：一次同步阻塞只让计时器迟一拍（periodic 计时器按回调重排，不补拍），所以一次卡顿 = 一行；再加每轮上限 200 行（照 `FrameWatch._most` 的既有上限），慢性卡顿也不会把日志写满。

**测量的边界（写明）**：小于 400 ms 的停顿测不到（测量粒度就是周期）；停顿恰好跨拍时读数会少一拍以内。

### 3.7 N5：挂起报告必须被看见

**为什么需要**：检测一直在跑，结果没人知道。`hangs/` 里 9 份带完整线程栈的报告躺了三个小时，同期 `events.log` / `errors.log` 零条提示（需求档 N5 事实基线）⇒ 缺的不是检测，是**把检测结果摆到人眼前的那一行**。

**落点**：`lib/diagnostics/hang_reports.dart`（新档，+≈70），启动时由 `lib/main.dart` 的 `if (!kIsWeb)` 块内调用一次（与 `FrameWatch` / `StallWatch` 同一处）。

**机制**：

```text
HangReports(logsDir).check()：
  报告目录 = <logsDir>/hangs              // 与 diagnostics_bundle.dart:59 同一处定义（提成共享函数）
  水位     = <logsDir>/hangs.seen 的第一行（上次看见的最新报告名）
  新报告   = hangs/hang-*.txt 中文件名 > 水位的那些   // 名序即时间序（diagnostics_bundle.dart:57）
  n > 0 ⇒ appEvent('hang', '$n new reports since <水位时间>（<报告目录>）')
  n == 0 ⇒ 零行（不误报）
  写完把最新文件名写回水位
```

- **只数 `.txt`**：一份挂起 = 一个 `hang-*.txt`，同名 `.dmp` 是它的转储，再数一次会把一份报告算成两份。
- **首次启动（无水位档）**：全部报告计为 new，`since` 写「首次启动」。这正是要看见的那 9 份；随后写水位，之后每次启动只报新增。
- **与 N4 互补**：N4 抓一切 > 400 ms 的窗口线程停顿；看门狗抓 > 6 s 且带线程栈。两条读数在同一份 `events.log` 里可直接对读。

**诊断入口的可点路径**：`lib/settings/pages/diagnostics_dialog.dart` 在文件计数行（`:166-174`）之后加一行报告目录路径 + 一个按钮，按钮文案复用既有 `l10n.revealInFileManager`，动作复用 `WindowControls.revealInFileManager(路径)`（既有用法 `lib/chat/chat_screen.dart:765-767`）⇒ 不新增 l10n 键。

**为什么不做成「启动弹窗」**：卡顿的形态是「发生了但没留下痕迹」，需要的是可查的证据而不是打断；一行日志 + 一个可点入口足够，且不会在每次启动时打断用户。

## 4. 接口契约

### 4.1 进程代理（`lib/platform/process_host.dart` + `process_host_io.dart` + `process_host_stub.dart`）

```dart
/// 一次进程创建的全部参数；字段与 dart:io 的同名参数同义。
final class ProcessSpec {
  const ProcessSpec(this.executable, this.arguments,
      {this.workingDirectory, this.environment, this.includeParentEnvironment = true,
       this.runInShell = false});
}

/// 代理持有的长驻进程：字节流与信号，语义与 dart:io 的 Process 同名成员相同。
final class HostedProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  void write(List<int> bytes);   // 经单一 SendPort，保序
  void closeStdin();
  void kill([ProcessSignal signal = ProcessSignal.sigterm]);
  Future<int> get exitCode;
}

final class HostedRun {
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// 代理的后端契约：真实实现 = 代理 isolate（`process_host_io.dart`）；
/// 假件 = 测试内联实现（T21 的必失败 spawn、集成用例 1-1 的计数假件）。
abstract interface class ProcessHostBackend {
  Future<HostedProcess> start(ProcessSpec spec);
  Future<HostedRun> run(ProcessSpec spec,
      {Encoding stdoutEncoding = systemEncoding, Encoding stderrEncoding = systemEncoding});
  Future<void> stopAll();
}

abstract final class ProcessHost {
  /// 默认后端 = 代理 isolate，懒启动一次，此后复用。
  static Future<HostedProcess> start(ProcessSpec spec);
  static Future<HostedRun> run(ProcessSpec spec,
      {Encoding stdoutEncoding = systemEncoding, Encoding stderrEncoding = systemEncoding});
  /// 应用退出：结束代理持有的 thincoder 进程（代理只持有 thincoder 的进程，§3.1）。
  static Future<void> stopAll();
  /// 测试注入面：装一个假件（集成用例 1-1 用），null 恢复默认的代理后端。
  static void useForTest(ProcessHostBackend? backend);
}
```

- 代理内部：`Isolate.spawn(_serve)`；消息 id 对应一次请求；字节以 `Uint8List` 传递；`transport_exit` 语义与 `ThincoderExit` 无关，由各调用方自己按 exitCode 组消息。
- 失败：代理未起、通道断开、`ProcessException` ⇒ 抛 `ProcessHostUnavailable`（携带原始信息），调用点映射为既有错误类型。**不回退到窗口线程**。
- 生命周期：代理随应用活；`stopAll()` 在退出路径调用（`lib/kernel/thincoder/thincoder_process.dart:13` 的 `stopThincoderProcesses`；该档因此 +3 行、新增 `import '../../platform/process_host.dart'`，进 §5 表 ③——**守门白名单必须含它**，见 §3.1）。迁入的只有 thincoder 的进程，没有 detached 启动——安装器留在上游原样（§3.1），代理不接管它。
- **代理死后重建一次，不重放用户请求**：代理 isolate 死亡后，下一次 `start` / `run` 重建代理再发请求；已发出的请求以 `ProcessHostUnavailable` 结束（重放会重复创建进程）。

### 4.2 可见性 gate（`lib/chat/window_visible.dart`）

```dart
/// 窗口是否可见：可见 = 生命周期为 resumed，或还没有状态。
/// 唯一持有 WidgetsBindingObserver；翻转时通知订阅者。
abstract final class WindowVisible {
  /// 注册观察者（幂等，多次调用只注册一次）。
  static void start();
  static bool get isVisible;
  static Listenable get changed;
}
```

- 内部只注册一个 `WidgetsBindingObserver`（`start()` 由 `ChatHistoryView.initState` 调用一次，幂等），避免每个消费者各注册一次。
- 消费者两个：`ChatHistoryView`（重建 gate）· `MarkdownView`（计时器 gate）。两处的语义都是「不重建 = 不出帧」。
- **N4 不是它的消费者**（§3.6）：心跳不随可见性停。
- **跨档指针**：本契约改写首篇 F1 的增量重建入口 ⇒ `docs/design/chat-streaming.md` 的 F1 章节需补一句（见 §3.4 末条）。

### 4.3 `MarkdownView` 的计时器 gate

- 不可见时：取消待决 trailing 计时器、置 `_parseWhenVisible = true`，不 `setState`。
- 变可见：`_parseWhenVisible` ⇒ 立即解析最新 `widget.data`（与 `dispose` 后重建同一语义，最终态由同一解析函数产出）。
- 订阅 `WindowVisible.changed`（`initState` 挂、`dispose` 摘），不自己注册观察者。
- 非流式四处调用（`assistant_text.dart` / `notice_row.dart` / `plan_card.dart` / stash 预览）数据不变 ⇒ 不进该分支，零行为变化。
- **跨档指针**：本节的 gate 改写首篇 F3 的节流机制 ⇒ `docs/design/chat-streaming.md` 的 F3 章节需补一句「可见性 gate 见本篇 §4.3」。

### 4.4 「超预算帧数」的读法（F5 验收）

- 阈值 = **100 ms**（需求档建议值）。一帧光栅化超过 100 ms 即用户可感知的掉帧。
- **改前计数的取值入口（现成，不需改代码）**：`tool/perf` 的探针本身按预算判 jank——`budgetMs` 在 `tool/perf/perf_probe.dart:71`，用于 `:261`；一帧的 build 或 raster 超过预算即计入 `frames.janky`（`:310-316`），同一次报告里 `frames.rasterMs` 给出逐帧 raster 的分布（`:265-267`、`:306`）。⇒ 同一场大会话流式回放，跑 `tool/perf` 并读 `frames.janky` 与 `frames.rasterMs` 即可；100 ms 档 = 把该场景的预算设为 100。
- 测试面：`tester` 拿不到真实 GPU 计时 ⇒ 断言结构（流的最近 `RepaintBoundary` 落在行内、列表主体不再被全区域层罩住）+ 重建计数（F1 的既有读数不回退）。
- 改前 / 改后同场景、同窗口、同机器（N2）。

### 4.5 停顿看门狗（`lib/diagnostics/stall_watch.dart`）

```dart
/// UI isolate 的心跳：两拍之间超出周期的部分达到 [threshold] 时，
/// 写一行 `stall`（gap + 当时的界面状态）。
/// 不可见时照常跳（§3.6）；hidden ∥ paused 不写行。
final class StallWatch {
  StallWatch({
    Duration period = const Duration(milliseconds: 250),
    Duration threshold = const Duration(milliseconds: 400),
    Duration Function()? elapsed,   // 单调时钟读数；默认内部 Stopwatch 的 elapsed
    void Function(String) write,    // 默认走 appEvent('stall', …)
  });

  void start();
  void stop();
}
```

- 参数与写出面可注入（构造注入），测试用注入实例、不动静态入口。
- **注入面只有一个：elapsed 源**（`Duration Function()`，默认内部 `Stopwatch` 的 `elapsed`，形状照 `FrameWatch` 的 `_clock`，`frame_watch.dart:49`）。不保留 `DateTime Function() now`——它给的是时刻、与 `Stopwatch` 类型不符，按它写用例会退回真实墙钟。
- **测试驱动器 = `tester.pump(Duration)`**：用例自己推进注入的 elapsed 源（每次 pump 前把读数加一拍）；不引 `fake_async`（`pubspec.yaml` 未声明该依赖）。
- 挂载：`StallWatch(...).start()` 在 `lib/main.dart:155-158` 的块内调用一次。`[stall]` 的写入面走 `appEvent`（`lib/platform/event_log.dart:84-85` 读 `EventLog.current`，`main.dart:147` 写它）⇒ 集成用例把 `EventLog.current` 接到临时目录、读「零行」，不需要新增导出面。

### 4.6 挂起报告（`lib/diagnostics/hang_reports.dart`）

```dart
/// 挂起报告目录：与诊断上传列目录处共用一处定义。
String hangsFolderOf(String logsDir);

/// 启动时看一次：把上次启动之后新增的挂起报告写成一行 `hang`。
/// 没有新的就什么都不写（不误报）。
final class HangReports {
  HangReports({
    required String logsDir,
    void Function(String category, String message)? write,  // 默认 appEvent
    DateTime Function()? now,
  });

  /// 返回写出的行数（0 = 无新报告，零输出）。
  int check();
}
```

- 水位档 `<logsDir>/hangs.seen`：第一行 = 上次看见的最新 `hang-*.txt` 文件名。
- 目录不存在 ⇒ 零行、零写入（「没有报告」本身就是正确答案）。
- 写水位失败 ⇒ 吞掉并返回已写的行数（下一次启动会再报一次同样的报告；宁可重复报，不可静默丢）。

## 5. 受影响文件清单

行数 = **2026-10-26 本轮逐档复量**（`wc -l` 同口径，数换行符）。符号定位优先于行号：行号是编制日快照。

| # | 坐标 | 改动 | 现行 | 预期增量 | 超档与拆分 |
|---|---|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_process_io.dart` | `Process.start` → `ProcessHost.start`（§3.1；两条触发路径共用的创建点） | 207 | +≈25 / −≈30 | 未超档 |
| ② | `lib/kernel/thincoder/thincoder_locator.dart` | `Process.run` → `ProcessHost.run`（含 `versionOf` 的版本探测，`:131-134`） | 379 | ≤ +4 / −3 | 未超档 |
| ③ | `lib/kernel/thincoder/thincoder_process.dart` | 退出路径挂 `ProcessHost.stopAll()` + 新增 `import '../../platform/process_host.dart'`（`:13` 的 `stopThincoderProcesses` 内，§4.1；守门白名单含此档，§3.1） | 18 | +≈3 | 未超档 |
| ④ | `lib/chat/chat_history_view.dart` | F6 gate：`_rebuild()` 包住三个帧源 + `WindowVisible` 订阅 + 恢复时一次全量 | 3922 | ≤ +40 | 超档，见 §5.1 |
| ⑤ | `lib/chat/widgets/edge_fade_mask.dart` | F5：整块遮罩 → 两条固定高度边缘渐变带（§3.3 判据成立时） | 293 | ≤ +30 | 未超档 |
| ⑥ | `lib/chat/widgets/markdown_view.dart` | 计时器 gate（§4.3） | 1076 | ≤ +20 | 超档，见 §5.1 |
| ⑦ | `lib/diagnostics/frame_watch.dart` | 状态行提成档内共享函数（§3.6） | 158 | +≈6 | 未超档 |
| ⑧ | `lib/diagnostics/diagnostics_bundle.dart` | `hangs` 目录拼接改用 `hangsFolderOf`（`:58-61`），一处定义 | 201 | +2 / −2 | 未超档 |
| ⑨ | `lib/settings/pages/diagnostics_dialog.dart` | N5：报告目录路径一行 + 既有「在文件管理器中显示」按钮（§3.7） | 284 | ≤ +14 | 未超档 |
| ⑩ | `lib/main.dart` | 挂 `ViewportWatch` + `StallWatch.start()` + `HangReports.check()` | 919 | +≈4 | 超档，见 §5.1 |
| ⑪ | `lib/platform/process_host.dart` | **新档**：代理 isolate 的公共面（§4.1） | 0 | +≈60 | 新档 |
| ⑫ | `lib/platform/process_host_io.dart` | **新档**：`Process` 的真实代理（唯一创建点） | 0 | +≈220 | 新档 |
| ⑬ | `lib/platform/process_host_stub.dart` | **新档**：web 上无进程 | 0 | +≈20 | 新档 |
| ⑭ | `lib/chat/window_visible.dart` | **新档**：一个观察者 + 静态查询（§4.2） | 0 | +≈50 | 新档 |
| ⑮ | `lib/diagnostics/viewport_watch.dart` | **新档**：DPR 留痕（§3.5） | 0 | +≈40 | 新档 |
| ⑯ | `lib/diagnostics/stall_watch.dart` | **新档**：停顿看门狗（§3.6 · §4.5） | 0 | +≈90 | 新档 |
| ⑰ | `lib/diagnostics/hang_reports.dart` | **新档**：挂起报告可见（§3.7 · §4.6） | 0 | +≈70 | 新档 |
| ⑱ | `test/platform/process_host_test.dart` | **新档**：代理往返（§8 T14–T15） | 0 | +≈120 | 新档 |
| ⑲ | `test/platform/no_window_thread_process_test.dart` | **新档**：守门扫描（§8 T16） | 0 | +≈50 | 新档 |
| ⑳ | `test/diagnostics/stall_watch_test.dart` | **新档**：N4 用例（§8 T9–T13） | 0 | +≈120 | 新档 |
| ㉑ | `test/diagnostics/hang_reports_test.dart` | **新档**：N5 用例（§8 T17–T19） | 0 | +≈90 | 新档 |
| ㉒ | `lib/kernel/thincoder/thincoder_warm.dart` | **整档删除**（§3.2） | 242 | 0 | — |
| ㉓ | `lib/kernel/thincoder/thincoder_lifecycle.dart` | 删 `takeWhenReady` / `timing: warm hit/miss` / 预热旁路，直接起进程（§3.2） | 170 | −≈14 | 未超档 |
| ㉔ | `lib/kernel/thincoder/thincoder_kernel.dart` | 删 `import 'thincoder_warm.dart'`（`:28`） | 480 | −1 | 未超档 |
| ㉕ | `lib/workspace/workspace.dart` | 删预热调用与 `_warmThincoder`（`:22` · `:443` · `:448-454` · `:1303`，§3.2） | 3027 | −≈12 | 超档，见 §5.1 |
| ㉖ | `test/kernel/thincoder_warm_test.dart` | **整档删除**（池的用例） | 284 | 0 | — |
| ㉗ | `test/kernel/thincoder_kernel_test.dart` | 删池夹具与用例（`pool()` `:4312-4326` · T108 · T108② · `_NoTimer` `:4899-4909` · T107① 的 `warm miss` 断言 `:4370`） | 4967 | −≈200 | 超档，见 §5.1 |
| ㉘ | `test/integration/chat_flows_test.dart` | **新档**：三条集成用例 1-1 / 2-1 / 3-1（`test/RTM.md` 三行，§8.1） | 0 | +≈160 | 新档 |
| — | `test/chat/chat_history_rebuild_test.dart` | 零改动，重跑取 A1/A4 不回退 | 507 | 0 | — |

**共 29 行**：14 个既有档改动 · 2 个整档删除（1 lib + 1 测试）· 7 个新 lib 档 · 5 个新测试档 · 1 行零改动。其中 F8 的迁移面只占 3 行（①–③）。

**现行列本轮逐档实测**（2026-10-26，`find /c /v ""` 同口径数换行符）：17 个既有档与本表逐行相符——207 · 379 · 18 · 3922 · 293 · 1076 · 158 · 201 · 284 · 919 · 242 · 170 · 480 · 3027 · 284 · 4967 · 507。实施首步不必再复量；届时数字若有变，先改本表再动代码。

### 5.1 超 800 行档的拆分方案

五档都在 800 行硬上限之上，本批只加分支、挂载行与删除；每个都写明下一次拆分的接缝（本批改动全部落在接缝之内，届时随之搬走）。

- **`lib/chat/chat_history_view.dart`（3922）**：本批只动 State 里的 gate（`_rebuild()` 与可见性订阅，`initState` / `dispose` 各一行）。接缝 = 行渲染这一组：`ChatItemView` 及其子 widget（`_Appear` `:3695`、`_HeightMotion` `:3882`）搬去 `lib/chat/widgets/chat_item_view.dart`；搬完本档只剩列表骨架、滚动锚定与选择区。
- **`lib/chat/widgets/markdown_view.dart`（1076）**：本批只加一个字段与计时器调度里的一个分支。接缝 = 解析与缓存这一组：块缓存与解析函数搬去 `lib/chat/widgets/markdown_blocks.dart`，`MarkdownView` 只剩调度与渲染。
- **`lib/main.dart`（919）**：本批只加三行挂载（`ViewportWatch.start()` · `StallWatch(...).start()` · `HangReports(...).check()`，都在 `:155-158` 的既有块内）。接缝 = 诊断挂载这一组：把这四件与 `FrameWatch` / `AppEventWatch` 的启动收进 `lib/diagnostics/start_diagnostics.dart` 的一次幂等调用，`main` 只留一行。
- **`lib/workspace/workspace.dart`（3027）**：本批只删四处预热挂点（§3.2）。接缝 = 项目开闭这一组：`_openProject`（`:422`）/ `hideProject`（`:1301`）/ `_unhide`（`:1308`）及其 `_save` 调用搬到 `lib/workspace/project_lifecycle.dart`；本批的删除全在接缝之内。
- **`test/kernel/thincoder_kernel_test.dart`（4967）**：本批只删池的夹具与用例（§3.2）。接缝 = 按能力分组：进程启动与握手 / 模型与设置 / 改名；第一组先拆到 `test/kernel/thincoder_start_test.dart`。

## 6. 关键决策记录

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | **删除预热池**（不修、不保留），回到上游形态：每会话一个进程、用完关闭 | 池 34 miss / 0 hit、净亏（需求档 §4）；上游 Claude 内核没有池也长期可用（`lib/kernel/claude_code/process_transport_io.dart:17` 的 `ProcessTransport`）；F8 落地后池只剩省一次等待的价值，而 TTL / 冷却 / 换 key 即杀这套生命周期要一直维护 |
| D2 | F8 = **唯一进程代理 isolate**，不是每点 `Isolate.run` | `Process` 对象不能跨 isolate 传，长驻进程必须在代理里活；只包 `Process.run` 会留下最贵的启动 |
| D3 | 代理失败 **显式抛错，不回退窗口线程直连** | 回退把 6 秒冻结放回来且没人知道（业务门：失败要可见） |
| D4 | **只迁会冻窗口的两处创建点**（thincoder 起进程 + 版本探测），其余 `Process.*` 保持上游原样 | 需求 F8 的冻结只由这两条链产生；全量迁移会把 30 多个上游文件卷进来，收益为零、合并冲突面很大。守门测试改为路径级（§8 T16） |
| D5 | F5 修法 = **收窄全区域合成层**，不是加行级边界 | 行级 `RepaintBoundary` 已由 sliver delegate 默认加上（`super_sliver_list` :406，调用点未关）⇒ 再加一层是空转 |
| D6 | F5 先量绘制面再定改点，判据写死（§3.3 规则 3 / 4） | 需求 N2「测量先行」；「哪一层在合成」只能从运行时取 |
| D7 | F6 = **重建 gate（视图 + markdown 计时器）**，不是降帧率 | 不可见时唯一正确的帧数是 0；降帧仍付同样的单帧光栅化代价 |
| D8 | F6 可见性判据 = `lifecycleState`，观察者只活在 `WindowVisible` | 与需求档 F6 原文一致；不新造「被遮挡」探测；观察者一处注册，消费者只订阅 |
| D9 | N4 心跳**不接** F6 的可见性 gate，`hidden` / `paused` 不写行 | 失焦期的停顿正是要量的（3/4 慢帧 `inactive`）；睡眠造成的假 gap 会撞掉「1 小时零误报」 |
| D10 | N4 的 `gap` = 实测间隔 − 周期 | 需求验收窗口是 700–1000 ms；取原始间隔会读成 1000–1050 ms，落在窗口外 |
| D11 | N4 的状态行与 `FrameWatch._state()` 共用一份 | 一处定义；`[stall]` 与 `[slow]` 字段可直接对读 |
| D12 | N3 = **新增一行日志**，不改媒体查询链路 | 先量后定；DPR 是既有事实，缺的只是留痕 |
| D13 | N5 = **启动扫一次 + 一行日志 + 诊断入口一个可点路径**，不弹窗 | 要的是可查的证据，不是打断；复用既有 `appEvent` 与 `revealInFileManager`，不新增 l10n 键 |
| D14 | N5 只数 `hang-*.txt`，`.dmp` 不另计 | 一份挂起带一个转储；两份都数会把一份报告算成两份 |
| D15 | F8 的迁移面收窄 = **兼容上游优先** | 用户 03:19「兼容的话会不会更好兼容上下游的更新了呢」——自造机制越少、改上游文件越少，合并成本越低；其余 `Process.*` 不在冻结链上（§3.1 迁移面）；将来 `[stall]` 指向它们时再单独迁 |

**最近先例（对齐 ∥ 偏离）**：

- 对齐：isolate + 端口承载长驻工作在本仓已有先例——`lib/kernel/claude_code/dart_core_transport_io.dart:37` 的 `AgentIsolate.spawn`；F8 的代理是同一形状，只做进程创建与字节转发。
- 对齐：重绘边界在本仓是既有做法（`lib/chat/agent_view.dart:67` 的 `RepaintBoundary(child: child)`）——F5 不是引入新机制，而是收窄既有的全区域层。
- 对齐（删池）：上游 Claude 内核的形态 = 每会话一进程、用完关闭（`lib/kernel/claude_code/process_transport_io.dart:17` 的 `ProcessTransport`）；删除预热池是把 thincoder 一侧对齐到同一形态，不是新机制。
- 对齐：生命周期监听照 `lib/main.dart:644` 的 `AppLifecycleListener(onResume: …)` 与 `:628-631` 的 `null || resumed` 判据。
- 对齐：诊断留痕照 `FrameWatch` 的形状（`lib/diagnostics/frame_watch.dart`：`appEvent` 写一行，不碰业务；构造注入时钟），N3 / N4 / N5 三块都走这个形状。
- 偏离：`MarkdownView` 目前对窗口状态无感知（只有 50 ms 节流计时器）。偏离理由 = 它是失焦后残余帧的来源，不关掉达不到 F6 的「帧数 0」；守门 = §8 T3。
- 偏离：N4 是全仓第一个「按计时器测界面线程」的探针（`[slow]` 按帧、`AppEventWatch` 按事件）。偏离理由 = 被堵住的线程产不出帧，只有计时器看得见；守门 = §8 T9–T13。
- 偏离：N5 是第一个「启动时读上次留下的报告」的诊断（既有诊断都是当次运行内的事件）。偏离理由 = 事故证据的价值在跨启动；守门 = §8 T17–T19。
- 偏离：进程创建从「谁用谁起」变为「一个代理统一起」（`dart:io` 的默认用法，全仓 33 处）。偏离理由 = 窗口线程冻结 6 秒（需求 F8 的 9 份报告）；守门 = §8 T16 的扫描与 F8-A 的挂起报告零新增。

**新公共面与日志标签的三问答案**：

| 新名字 | 在哪 · 叫什么 · 谁用 | 判定 |
|---|---|---|
| `ProcessHost`（§4.1） | 现在没有进程创建的公共面：各调用点直接 `Process.start`；`lib/platform/child_process_registry.dart` 只记 pid 供下次回收，自己还调 `Process.run('ps')`（`:179`） | `none found: lib/platform/** 下的进程相关件已逐一核对` ⇒ 新建 |
| `WindowVisible`（§4.2） | `lib/main.dart:628-631` 的 `inFront()` 是 `_startTelemetry` 里的局部闭包，出不了那个函数 | `existing but unusable: lib/main.dart:628 · name: "inFront" · failed on: 局部闭包，无导出面` ⇒ 新建 |
| `StallWatch`（§4.5） | `lib/diagnostics/frame_watch.dart:20` 的 `FrameWatch` 按帧计时；没有任何按周期测界面线程的探针 | `none found: lib/diagnostics/**` ⇒ 新建，形状对齐 `FrameWatch` |
| `ViewportWatch`（§3.5） | `lib/diagnostics/app_event_watch.dart` 记事件的产生，不观察 DPR；`lib/main.dart:872` 的 `PixelSnappedTextScaler` 是媒体查询消费方，不是观察者 | `none found: lib/diagnostics/** 与 lib/main.dart 的媒体查询消费面` ⇒ 新建 |
| `HangReports`（§4.6） | `lib/diagnostics/diagnostics_bundle.dart:41-63` 的 `listDiagnosticsLogs` 只**列**文件供上传，不判定新旧、不写日志 | `existing but unusable: lib/diagnostics/diagnostics_bundle.dart:41 · name: "listDiagnosticsLogs" · failed on: 无水位概念，且不写事件日志` ⇒ 新建（目录拼接复用它的同一处定义，§5 ⑧） |
| 标签 `[stall]` | 日志标签命名空间 = `appEvent(category, …)` 写 `[category]`（`lib/platform/event_log.dart:45-47`、`:84-85`），既有 `slow` / `semantics` / `window` / `theme` | 复用命名空间，新增一个 category |
| 标签 `[viewport]` | 同上 | 复用命名空间，新增一个 category |
| 标签 `[hang]` | 同上 | 复用命名空间，新增一个 category |

**公开源调查**（`index.publicRepos` 为空：本仓无独立上游文档仓）：

- 已核的第一手来源：`super_sliver_list-0.4.1` 的构造函数默认值（本机 pub cache，`lib/src/super_sliver_list.dart:406`）。
- 已核的第一手来源：Dart SDK 的 `runtime/bin/process_win.cc`（`https://raw.githubusercontent.com/dart-lang/sdk/main/runtime/bin/process_win.cc`，2026-10-26 取）——`Process::Start` 同步调用 `ProcessStarter::Start()`，后者体内即 `CreateProcessW`（§3.1）。
- 已核的本仓坐标：`lib/kernel/thincoder/thincoder_process_io.dart`（创建点）· `thincoder_catalog.dart`（列会话的进程唤起）· `lib/diagnostics/frame_watch.dart`（诊断形状）· `lib/diagnostics/diagnostics_bundle.dart`（挂起报告列目录与名序）· `windows/runner/hang_watchdog.cpp`（冻结判据 `kHangMilliseconds = 6000`）。
- **未核（`unverified`）**：`dart:io` 的 `Process.start` / `Process.run` native 入口进入 `Process::Start` 时所在的线程（未读 `runtime/bin/process.cc` 与 `io_natives.cc`；结论不依赖它，§3.1）；Flutter 引擎侧「Impeller 下全区域 `saveLayer` 的合成代价」；`AppLifecycleState.hidden` 在 Windows 最小化时的具体映射；代理 isolate 在 Windows 上被 Defender 扫描时的实际耗时（设计只依赖「不在窗口线程」）。

## 7. 验收对照（回指需求档 F5 / F6 / F8 / N2 / N3 / N4 / N5）

| 需求 | 落点 | 机检判据 |
|---|---|---|
| F8 挂起报告零新增 | §3.1 | F8-A：同一操作路径下 `logs/hangs/hang-*.txt` 零新增（现有 9 份为基线） |
| F8 窗口线程无 > 500 ms 停顿 | §3.1 · §4.5 | F8-B：`[stall]` 无 gap > 500 ms 的行（依赖 N4 已落地）。**本批验收档 = 500 ms**（需求档 F8 原文）；50 ms 是长期目标、本批无量具（N4 的粒度就是 250 / 400 ms，见 §3.6） |
| F8 会冻窗口的路径不再直连 | §3.1 | F8-C：T16——引入 `process_host` 的档集合恰为 {`thincoder_process_io.dart` · `thincoder_locator.dart` · `thincoder_process.dart` · 三个新 lib 档}；其中创建进程的两档内零 `\bProcess.start(` / `\bProcess.run(`，`thincoder_process.dart` 只 import 不创建；T14–T15 代理往返正确；其余上游档本批零改动 |
| F8 版本探测也在范围内（需求档 §5 第 3 条） | §3.1 · ② | F8-D：打开设置页（触发 `versionOf` 的版本探测，`thincoder_locator.dart:131-134`）期间 `[stall]` 无 > 500 ms 的行；该项与 F8-B 分两次读数（一次只跑一项，避免互相掩盖） |
| F8 多项目启动也在范围内（需求档 §5 第 3 条） | §3.1 · ① | F8-E：启动载入多个项目（`workspace.dart:345` 的 `_listKept` 逐项目唤起进程，经 ① 同一创建点）期间 `[stall]` 无 > 500 ms 的行，且 `logs/hangs/` 零新增；与 F8-B / F8-D 分开读数 |
| 删池完成（需求档 §4 · §5 第 4 条） | §3.2 | P：`grep -rn "thincoder_warm\|warm hit\|warm miss\|预热池" lib/ test/` 零命中；无池仍能起会话——打开一个会话 ⇒ 进程起、`initialize` 一次、能输入；关掉视图再打开 ⇒ 再起一个；`events.log` 无 `timing: warm …` 行 |
| F5 超预算 raster 帧 → 0 | §3.3 · §4.4 | A：`tool/perf` 大会话流式回放，预算 100 ms 下 `frames.janky` 中 raster 超预算的帧数 = 0（改前读数按 §3.3 第 1 步、§4.4 的入口在动代码前量好，两次读数并列留档）；总帧数与改前同量级（±20%）。规则 3 的分支不成立时按 §3.3 规则 4 的顺序收窄；四步走完仍不成立 ⇒ 另起设计档并记「F5 未达成」 |
| F5 重绘范围不随界面大小 / 历史增长 | §3.3 | B：组件测试断言流式行最近的重绘边界在行内、列表主体无全区域合成层；另 20 / 200 回合两跑，流式帧的 `ChatItemView` 重建数逐项相等（既有 A1 口径不回退）；视觉等价按 §10 的**整帧**比对 |
| F6 不可见期帧数 = 0，切回一帧追平 | §3.4 · §4.2 · §4.3 | C：模拟 `inactive` 后回放 120 个增量 ⇒ `ChatItemView` 重建 0 次、`MarkdownView` 解析 0 次；恢复 `resumed` ⇒ 恰 1 次重建，可见文本 == 全文；底部与中段滚动偏移不变（T2a / T2b）。设备面两条并列：① 失焦 60 秒 `FrameTiming` 帧数 0（或仅 1 帧残余尾帧）；② 失焦时 baocode 的 `GPU Engine` 占用接近 0%——同机同窗口、失焦前后各采样 3 次取均值，对照 §2 的 30.6–30.7%（需求档 F6 验收 ②）。② 不归零 ⇒ 按 §3.4 的帧源清单逐个关并复采，仍不归零则上报「F6 未达成」 |
| N3 DPR 留痕 | §3.5 | D：模拟 DPR 1.5 → 2.25 → 1.5，事件日志出现两行 `[viewport] view 0 dpr 1.5 -> 2.25` / `2.25 -> 1.5`，各带尺寸；无变化零行；真机重现一次即定论（需求档 §5 第 5 条的一次真机读数） |
| N4 停顿必须留读数 | §3.6 · §4.5 | G：构造 800 ms 同步阻塞 ⇒ 恰一行 `[stall]`，gap ∈ 700–1000 ms；无阻塞连续 1 小时 0 行；`hidden` / `paused` 状态 0 行（复现路径见 §3.6，需求档 §5 第 5 条的一次真机读数） |
| N5 挂起报告必须可见 | §3.7 · §4.6 | N5：预置一份新的 `hang-*.txt` 后启动 ⇒ `events.log` 恰一行 `[hang] 1 new reports since …`；无新报告时启动 ⇒ 0 行；诊断入口显示报告目录且按钮可打开（需求档 §5 第 5 条的一次真机读数；T17–T19） |
| 既有测试全绿（需求档 §5 第 6 条的七个路径） | §5 · §8 | H：逐条跑 `flutter test <file>`——`test/chat/chat_history_rebuild_test.dart` · `test/chat/history_scroll_test.dart` · `test/chat/fold_view_test.dart` · `test/chat/step_folds_test.dart` · `test/sticky_message_test.dart` · `test/selection_scroll_test.dart` · `test/markdown_test.dart` 全绿；读数逐档记进批档 |
| 真机走查一次 | §7 全表 | I：① 长对话（≥200 条）持续流式时滚动与打字跟手（用户主观确认）；② **会话来回切换 5 次，逐次计时，不出现 ≥ 1 秒的停顿**；③ 失焦再切回一次到位、无残影、无内容缺失 |
| N2 同法可比 | §2 · §4.4 | E：改前读数在动代码前量，改后同场景、同窗口、同机器复量，两次读数并列留档 |

## 8. 用例表

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 不可见期间流式（正常） | `inactive` + 120 个文本增量 + pump | 重建 0、解析 0、无帧；`_dirtyWhileHidden` 置起 |
| T2 | 恢复可见（边界） | 上述之后 `resumed` | 恰 1 次重建；可见文本 == 全文；无 pending timer |
| T2a | 恢复后底部锚定（边界） | 失焦前停在底部 + 恢复可见 | 仍在底部：末行底边与视口底边的偏移与失焦前相等（±1 px） |
| T2b | 恢复后中段偏移（边界） | 失焦前向上滚到中段（记 offset）+ 恢复可见 | 滚动偏移不变（±1 px）、无跳动；可见文本 == 全文 |
| T3 | 不可见期间 markdown 尾帧（边界） | 失焦前 10 ms 内刚排上 trailing 计时器，随后 `inactive` | 计时器被取消、不 setState；恢复后解析一次 |
| T4 | 从头就不可见（边界） | 视图首帧时 `inactive` | 不起计时器、不出帧；恢复后一次到位 |
| T5 | 流式行重绘边界（正常） | 大会话 + 流式增量 | 该行最近的重绘边界在行内；列表主体无全区域合成层 |
| T6 | 高度动画期间增量（边界） | `_HeightMotion` 动画中 + 增量 | 允许动画期的额外合成；动画结束回到 T5 |
| T7 | DPR 变化（正常） | DPR 1.5→2.25→1.5 | 两行日志，带 view id、值与时序正确；无变化时不写行 |
| T8 | 窗口不可见时 DPR 变化（边界） | `inactive` 中 DPR 变化 | 照写日志（留痕不依赖可见性） |
| T9 | 心跳无阻塞（正常） | 注入时钟，10 拍各 +250 ms | 0 行 `[stall]` |
| T10 | 一次 800 ms 同步阻塞（正常） | 一拍后注入 +1050 ms | 恰 1 行，`gap 800 ms`，带当时状态 |
| T11 | 阈值边界（边界） | 注入 +650 ms（gap = 400）与 +649 ms（gap = 399） | 前者写 1 行，后者 0 行 |
| T12 | 失焦期间阻塞（边界） | `inactive` + 800 ms 阻塞 | 照写 1 行（状态字段为 `inactive`）——心跳不随可见性停 |
| T13 | 最小化 / 挂起（边界） | `hidden` ∥ `paused` + 800 ms 阻塞 | 0 行（刻意盲区，§3.6） |
| T14 | 代理起一个进程（正常） | `ProcessHost.start` 起一个回显子进程 | stdout 收到回显；写入保序；`exitCode` 正确 |
| T15 | 代理执一次性命令（正常） | `ProcessHost.run('node', ['-e', …])` | 退出码、stdout、stderr 与 `Process.run` 同值 |
| T16 | 守门扫描（路径级，正常） | 扫 `lib/**`：谁 `import` 了 `process_host`；并对其中创建进程的两档扫词边界 `\bProcess.start(` / `\bProcess.run(`（跳过注释行） | 引入代理的档恰为 {`thincoder_process_io.dart` · `thincoder_locator.dart` · `thincoder_process.dart` · `process_host.dart` / `_io.dart` / `_stub.dart`}；前两档 0 直连，`thincoder_process.dart` 只 import 不创建进程（§4.1）；其余上游档本批零改动、允许照旧 |
| T17 | 预置一份新挂起报告（正常） | 临时 logs 目录 + 一份新 `hang-*.txt` + 水位为旧值 | 恰 1 行 `[hang] 1 new reports since …`；水位更新到该文件名 |
| T18 | 无新报告（边界） | 水位 = 最新文件名 | 0 行、0 新写入 |
| T19 | 首次启动（边界） | 无水位档 + 3 份 `hang-*.txt`（含 1 份 `.dmp`） | 1 行 `[hang] 3 new reports since 首次启动`（`.dmp` 不另计）；水位 = 最新 `.txt` |
| T20 | 删池后的开会话（正常） | 无预热池；打开一个会话；视图离开（`_views == 0`）；再打开 | 第一次：恰一次 `initialize` + 一次 `session/new`；离开后进程结束（`_teardown`）；再打开：再起一个进程、再握手一次；全程零 `timing: warm …` 行 |
| T21 | 代理起不来（错误） | 假件的 spawn 抛 `ProcessException` | 调用方收到 `ProcessHostUnavailable`（带原始信息），映射为既有错误类型；**不回退窗口线程**；`logs/hangs/` 零新增 |
| T22 | 代理中途死亡、留有子进程（错误） | 起一个长驻进程后 `Isolate.kill(immediate)` 代理；等 `ChildProcessRegistry.reaped` | 已发出的调用以 `ProcessHostUnavailable` 结束（不挂起）；下一次 `start` 重建一次代理再发（§4.1，不重放旧请求）；孤儿由注册表按 parent pid 回收（`lib/platform/child_process_registry.dart:52` → `:178` `psLookup` → `:194` `killPid`）；回收读数记进批档 |
| T23 | 通道断开（错误） | 代理 isolate 活着但接收端口不可达 | 已发出的请求以 `ProcessHostUnavailable` 结束（不静默丢）；下一次 `start` 重建一次代理再发；用户请求不自动重放 |

### 8.1 集成用例（编号 = `test/RTM.md` 的行号，逐字复用）

| 编号 | 场景 · 用户入口 | 输入 | 期望 |
|---|---|---|---|
| 1-1 | 来回切会话（侧栏连续点两个会话） | 假 `ProcessHost`（`useForTest`）+ 两个已载入会话；挂载应用；A→B→A→B→A | 五次切换各起一个进程（假件计 5 次 `start`）；每次切换后 300 ms 内历史行就位、输入可用；`EventLog.current` 接临时目录 ⇒ `[stall]` 0 行 |
| 2-1 | 失焦后切回（点别的窗口再点回） | 挂载应用；转 `inactive`；回放 120 个增量；转 `resumed` | 失焦期：`ChatItemView` 重建 0、`[stall]` 0 行、可见文本不变；恢复：恰 1 次重建、可见文本 == 全文、底部仍在底部（T2a / T2b 同断言） |
| 3-1 | 大会话流式（长会话发消息并滚动） | ≥1000 条历史 + 流式回放 120 增量 | 终态可见文本 == 全文；流式帧上列表主体无全区域合成层（`debugDumpLayerTree` 断言）；20 / 200 回合两种历史下每增量 1 次重建、逐项相等 |

## 9. 边界与失败面

- 不改列表实现、不做分段上限（需求档 §4）；不换渲染引擎（Impeller 保持）。
- 不改数据模型与 `KernelEvent` 形态；进程随视图离开而销毁（`lib/chat/session/lifecycle.dart:40` → `release` → `_releaseWhenIdle` → `_teardown`）——预热池删除后这是唯一的收尾路径，本批保留不动（§3.2）；会话常驻内核另批再议。
- 删池的代价（写明）：切回一个已释放的会话要重新起进程并握手（今天池 0 命中，走的也是这条路）；用户可见的只是既有的「thincoder is starting…」提示，F8 保证它不冻结窗口。
- 失败面（F8）：代理起不来 ⇒ `ProcessHostUnavailable`，映射为既有错误（如 thincoder 启动失败提示），不静默回退（T21）；代理中途死亡 ⇒ 它持有的进程成为孤儿，由 `ChildProcessRegistry` 的既有回收处理（`lib/platform/child_process_registry.dart:52` 的 `reaped` → `:178` 的 `psLookup` → `:194` 的 `killPid`，T22）；通道断开 ⇒ 已发出的请求以 `ProcessHostUnavailable` 结束、下一次调用重建一次代理（T23）。
- 失败面（F6）：gate 误判「不可见」⇒ 画面停更，聚焦即恢复；误判「可见」⇒ 回到今天的行为。两向都不丢内容。`WindowVisible` 拿不到状态（`lifecycleState == null`）⇒ 按可见处理。
- 失败面（N4）：写入面自身抛错 ⇒ 吞掉并计数，不把看门狗变成新的崩溃源；每轮 200 行上限之后静默。
- 失败面（N5）：`hangs/` 目录不存在 ⇒ 零行零写入（「没有报告」是正确答案，不是被吞掉的错误）；水位写失败 ⇒ 吞掉，下次启动重复报同一份（宁可重复，不可静默丢）；`EventLog.current` 未就绪 ⇒ `appEvent` 静默丢弃（既有语义），不写半行。

## 10. UI / 交互决定

- **F5 视觉零变化，比对范围 = 整帧**：判据 = 改前 / 改后同窗口截图**逐帧逐像素**比对，不比边缘带局部（整块遮罩若在中间区域也有着色，局部比对会把它排除）。不等价时的处置写死：① 先调带高与色标（各试一次）；② 仍不等价 ⇒ 回退整块遮罩，F5 记为未达成并上报，不静默接受一幅变了的画面。
- F6 带来的可见行为变化：**窗口失焦期间画面停止更新**，聚焦后一次到位；并排使用时可见此现象。需求档 F6 已定案（`docs/requirements/chat-streaming.md` 的 F6 条），实施按此执行；此处只作告知。
- F8 无界面变化；用户可感知的是切会话与启动时不再出现 6 秒无响应。
- 删池无界面变化：切回一个已释放的会话仍显示既有的「thincoder is starting…」提示（`_sayWaitingOf`，T107① 断言其文案）。
- N3 / N4 只加日志，无 UI。
- N5 在诊断入口（设置 → 关于/更新 → 诊断日志）加一行报告目录路径 + 一个按钮，按钮文案复用既有「在文件管理器中显示」（`l10n.revealInFileManager`），无新 l10n 键、无新设置项；不在启动时弹窗。

## 11. 集成测试设计

**索引档**：`test/RTM.md`——本批建立首版。一个业务故事一节、一行一条集成用例；行号在本档先定，用例标题逐字复用（`test('1-1 …')`）。
**套件**：`test/integration/chat_flows_test.dart`——本批新建，三条用例（1-1 / 2-1 / 3-1）。规模窗 50–100，当前 **3 / 50–100**（本批从 0 提到 3）。

**本变更改变的业务可观察结果（三个业务故事；每行点名组件间交互、断言到的业务结果、用户入口与回溯需求号）**：

| 行 | 组件间交互 | 断言到的业务结果 | 用户入口 | 回溯需求 | 用例 |
|---|---|---|---|---|---|
| 1-1 | `ChatHistoryView` ⇄ `ChatSession` ⇄ `ProcessHost`（假件） | 来回切 5 次，每次切换后 300 ms 内会话可用、各起一个进程；`[stall]` 0 行 | 侧栏会话列表连续点两个会话 | F8 · 删池 | §8.1 |
| 2-1 | `WindowVisible` ⇄ `ChatHistoryView` / `MarkdownView` ⇄ `Transcript` | 失焦期重建 0、`[stall]` 0 行、文本不变；恢复后恰 1 次重建、文本 == 全文、滚动与底部仍在原处 | 点别的窗口再点回 | F6 | §8.1 |
| 3-1 | `ChatHistoryView` ⇄ `EdgeFadeMask` ⇄ `MarkdownView` 节流 | 终态文本 == 全文；流式帧上列表主体无全区域合成层；20 / 200 回合下每增量重建数逐项相等 | 长会话里发一条消息并滚动 | F5 · F1 | §8.1 |

**为什么恰好是这三条**：三条都同时命中两条准入——产品真正需要的业务场景（切会话 / 失焦回来 / 长会话流式）与生产真正发生的问题（6 秒冻结 / 350 ms 慢帧 / 失焦空转）。真实设备读数（帧耗时、GPU、挂起报告）留在 §7，不进集成套件。

**既有行的处置**：本批是索引首版 ⇒ 无改写行、无删除行。
**本批交付的验证面**：集成用例 1-1 / 2-1 / 3-1（`test/integration/chat_flows_test.dart`）+ 组件与单测（§8 T1–T23）+ 设备读数（§7 F8-A/B/C/D/E · A / C / D / G / N5 · P）+ 真机走查一次（§7 I）。

## 12. 未决项与需主 agent 同步的项

1. **F6 的可见行为变化**：需求档 F6 已定案（失焦期间不出帧），本批按此实施；需向用户告知的只有一条可感知后果——并排使用时画面会在失焦期间停更，聚焦后一次到位（§10）。
2. **集成测试索引与套件 = 本批交付**：`test/RTM.md`（三个业务故事）+ `test/integration/chat_flows_test.dart`（三条用例）随本批落地；套件计数 **3 / 50–100**，其余欠账仍由台账承接。
3. **删池后的用例净减**：`test/kernel/thincoder_warm_test.dart`（284 行）整档删除，`thincoder_kernel_test.dart` 删池的夹具与用例（§5 ㉗）——这是删除面，不是覆盖下降；T111 保留（它测的是 `ChatSession` 的内核对象缓存，与进程池无关）。
4. **上游进程调用保持原样**：`forge/forge_io.dart` · `ide/lsp/**` · `customize/mcp_probe_io.dart` · `installer_io.dart` · `child_process_registry.dart` 等 `Process.*` 本批不动；将来 N4 的 `[stall]` 指向哪条再单独迁（§3.1 · D15）。
5. **F8 的 50 ms 长期目标本批无量具**：本批按 500 ms 验收档读（需求档 F8 原文已写明）；50 ms 要另配量具，不在本批。
