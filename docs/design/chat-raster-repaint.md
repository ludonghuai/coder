# 对话重绘边界与出帧时机（chat-raster-repaint）设计档

> 板块：对话渲染（chat-streaming）· 范围仓：baocode。
> 配对需求档：`docs/requirements/chat-streaming.md`（F5 · F6 · F7 · F8 · N3 · N4，测量纪律 N2）。
> 状态：设计稿 v3 · 2026-10-26 · 行号 = 编制日快照（实施按符号定位）。
> 与前档分工：`docs/design/chat-streaming.md` 管 F1–F4（增量重建边界 / 折叠 / markdown 节流）；本档管 F5 重绘范围 · F6 出帧时机 · F7 内核进程复用 · F8 进程创建不阻塞窗口线程 · N3 DPR 留痕 · N4 停顿看门狗。

## 1. 模块目标与范围

**一句话**：切会话不再付一次进程启动的冻结（F7），任何子进程的创建不再堵住窗口线程（F8）；长会话流式时一帧的光栅化代价只跟真正变了的那一块走（F5），窗口看不见时不付这份代价（F6）；卡顿时应用自己留下读数（N3 / N4）。

**本批主修**：F7（预热池多槽 + 用完放回）· F8（进程创建移出窗口线程）。
**本批次要**：F5 重绘边界 · F6 不可见时不出帧 · N3 DPR 留痕 · N4 停顿看门狗。
**N2** 是贯穿全批的测量纪律：改前读数在动代码前量，改后同场景复量。

**本批不做**：列表虚拟化 / 分段上限 / 数据分页（需求档 §4）· 换渲染引擎 · 数据模型与内核事件形态 · 视觉与交互形态改动 · 会话常驻内核（F7 的 B 案，进程仍随窗口离开而离开视图，只是不随之销毁）。

## 2. 事实基线（改前读数，动代码前按 N2 复量）

| 项 | 读数（2026-10-26，Release 1.7.2+19） | 来源 |
|---|---|---|
| F5 帧 | 70 分钟 4 条 `raster 340–350 ms`（build 0–9 ms），四条全在流式中；会话 1060–1205 条、渲染对象 6163–6589、窗口 3840×2088@1.5 | 需求档 F5 |
| F6 状态 | 四条慢帧中 3 条 `lifecycleState == inactive`；10 分钟内失焦→聚焦 4 次；失焦时 baocode 占 GPU 30.6–30.7% | 需求档 F6 |
| F7 进程 | 当日 38 次 `launch: builtin` · 34 次 `warm miss` · **0 次 warm hit**；launch→handshake 中位 569 ms；01:16–01:19 三分钟 13 次启动（最短间隔 0 秒） | 需求档 F7 |
| F8 冻结 | Windows 挂起看门狗 9 份报告：8 份窗口线程栈 = `ZwCreateUserProcess ← CreateProcessInternalW ← CreateProcessW ← app.so`，1 份 = `ZwQueryValueKey ← BasepQueryAppCompat`；报告首行 `The windows' thread took no message for 6 s`；周期约 4 分 52 s、每次约 6 s | 需求档 F8 |
| N3 DPR | 三显示器、同时有 1.5 与 2.25；日志 view 0 恒 `@1.5`，无 DPR 变化行 | 需求档 N3 |
| N4 停顿 | 2026-10-25 22:00–23:15 用户三次报卡，同期 `[slow]` **零条**、`errors.log` 零条；Windows 事件 / 崩溃转储 / 内存耗尽 / GPU TDR 全空 | 需求档 N4 |

**读数面现成的东西**（`lib/diagnostics/frame_watch.dart`）：

- `_timings` 只在 `rasterDuration ≥ 250 ms` 时写 `[slow]` 行（`:96-106`），行内带 `build`。
- 状态行 `_state()`（`:126-157`）已给 semantics 节点数、render object 数、在显示的会话、RSS、`lifecycleState` —— N4 直接复用它（§3.6）。
- 没有 100 ms 档 ⇒ F5 的「超预算帧数」要另给读法（§4.5）。

## 3. 做法与理由

### 3.1 F7：预热池多槽保留 + 用完放回（主修）

**已核事实（四条，坐标均实读）**：

- 池是**单槽**：`_wanted` 单键（`lib/kernel/thincoder/thincoder_warm.dart:73`）、`_connection` / `_transport` / `_handshake` 单份（`:78-81`）；换 key 时 `drop('project-switch')` 杀掉现进程（`:104-113`）。
- `take()` 把进程整体交出去后池即清空（`:129-153` 的 `_forget(close: false)`）——**池里没有「用过的进程」这条路**。
- **释放即销毁**：视图离开时 `_releaseWhenIdleOf` 调 `_closeSession()` + `_teardown()`（`lib/kernel/thincoder/thincoder_release.dart:100-116`），而 `_teardownOf` 关连接、关传输（`:7-27`）⇒ 进程结束；视图回来时 `prepareOf` 重新启动（`:60-68`）。
- ⇒ 每次切走再切回 = 一次新启动：`_launchOf` 先问池（`lib/kernel/thincoder/thincoder_lifecycle.dart:22`），池空则自己起并写 `launch: builtin`（`lib/kernel/thincoder/thincoder_locator.dart:131-134`）。预热池每次 take 后也不会被补，故 34 miss / 0 hit 同形。

**做法（三段，缺任一都达不到验收）**：

1. **多槽池**：`ThincoderWarm` 由单槽改为 `Map<ThincoderWarmKey, _Held>`，按 key 各持一个；启动串行（一条 `Future` 链，同一时刻只起一个进程）。
2. **用完放回**（`keep`）：视图离开、且没有进行中的回合 / 子代理 / 挂起窗口时（既有判据 `_canClose`，`thincoder_release.dart:90-94`），内核不再销毁进程，而是把 `(transport, connection, handshake)` 交回池（`ThincoderWarm.keep`）；下次切回同一项目直接 `take` 命中。
3. **take 之后补一个**（预热）：会话到达 `KernelHealth.ready` 时补一次 `warm`，使「池空」的窗口尽量短（首次打开一个新会话时仍有命中可用）。

**为什么必须是「放回」而不只是「多留几个预热」**：预热自己也是一次启动（`thincoder_warm.dart:198` → `_launchFor`，日志同一行 `thincoder_locator.dart:131`）。只做多槽预热，每切回一次仍新增一次启动，`launch: builtin` 随切换次数增长，达不到需求 F7「N ≥ 5 时增量 ≤ 1」。放回之后，切回的成本是一次 `take`（< 10 ms），零启动。

**槽数与上限（写死）**：

- 每 key 至多一个持有进程；池总上限 `maxHeld = 3`，满则淘汰 `heldAt` 最老的（`drop('capacity')`）。
- 3 的由来：一个 Node 内核实测约占 85 MB（2026-10-26 实测），3 个把池的上限压在约 255 MB；同时覆盖常见工作集（本机三显示器、2–3 个在开项目）。
- 每个槽各自 10 分钟 ttl（沿用 `:42` 的既有值），到点只丢该槽。

**不变量（写死）**：

- 只按 key 复用：`(cwd, files)` 相同才可交回同一会话；capabilities 与 handshake 由此固定（沿用 `:15` 的键定义）。
- 只放回「没有会话」的进程：放回发生在 `session/close` 之后、且 `_canClose` 为真；放回前把 `connection.onRequest` / `onNotification` 清空（`lib/kernel/thincoder/thincoder_protocol.dart:80-83` 是可空字段），下一个内核取走时自行装上（`thincoder_lifecycle.dart:35-36`）。
- MCP 授权在放回时撤销（与 `_teardownOf:8-11` 同），下一个会话自带新授权（`thincoder_lifecycle.dart:124-131`）。
- 进程已退出不进程池：池的监听照 `transport_exit` 丢弃（`:205-210`）。
- 池满、key 不符或传输已结束时，放回被拒 ⇒ 照旧关闭（业务门：不静默多留一个无人认领的进程）。

**workspace 侧的两处跟随改动**（`lib/workspace/workspace.dart`）：

- `_warmThincoder`（`:448-454`）由「切项目就 drop 旧进程」改为「不 drop，只预热本项目」；首选内核不是 thincoder 或远端路径时，丢**该项目**的槽（`dropProject(path)`），不碰别项目。
- `hideProject`（`:1301-1306`）的 `cwd == … drop('project-closed')` 换成 `dropProject(project.path)`。

### 3.2 F8：进程创建移出窗口线程（主修）

**已核事实**：

- 冻结发生在 `CreateProcessW` 内部（`ZwCreateUserProcess` 与 `BasepQueryAppCompat` 两组栈），且 `app.so` 在栈上是调用方 ⇒ 这次创建是 Dart 代码在**窗口线程**（Flutter 的 platform/UI 线程）上调起的。
- 应用内的进程创建全走 `dart:io`：`Process.start` 8 处、`Process.run` 19 处、`Process.runSync` 2 处（`lib/**` 全量检索，2026-10-26，共 29 处）。`dart:io` 的这些入口在**调用它的 isolate 的线程**上执行 `CreateProcessW`：UI isolate 上调就是窗口线程，Defender 扫描新起的 85 MB Node 时冻 6 秒。
- 内核启动路径两处：预热 `_hold`（`thincoder_warm.dart:195-198`）与内核自起（`thincoder_lifecycle.dart:26`），都在 UI isolate 上。
- `runSync`（`lib/kernel/thincoder/thincoder_config_store.dart:458` 的 `chmod`）连异步都绕不过：同步等待，直接堵住调用线程。

**做法：一个进程代理 isolate**（新档 `lib/platform/process_host.dart`）

- **全应用唯一的进程创建点**：一个长驻 isolate（`Isolate.spawn`，首次使用时起、随进程存活），只有它调 `Process.start` / `Process.run`。窗口线程只收发端口消息——`CreateProcessW` 因此落在代理 isolate 自己的线程上。
- **长驻进程**：代理持有 `Process` 对象，把 stdout / stderr 以字节块转给窗口线程侧；stdin 写入、kill、exitCode 走同一条消息通道（同一 `SendPort` 保序）。
- **一次性命令**：代理内跑完，一次性回传退出码与解码后的 stdout / stderr（编码按调用方给的，默认与 `Process.run` 相同）。
- **形状照仓库既有先例**：`lib/kernel/claude_code/dart_core_transport_io.dart:37` 用 `AgentIsolate.spawn` 把引擎放进独立 isolate、以端口说话——同一形状搬到一个只做进程创建与转发的代理上。

**失败面（业务门：显式失败，不静默回退）**：

- 代理起不来、消息通道断开、代理内 `Process.start` 抛错 ⇒ 调用方收到明确异常（`ProcessHostUnavailable` / 原 `ProcessException` 语义），由各调用点映射为既有错误类型（如 `ThincoderUnavailable`）。
- **绝不回退到窗口线程直连**：那会把 6 秒冻结放回来，且没人知道它回来了。

**迁移面（写死）**：

- 长驻 stdio 七处 → `ProcessHost.start`：thincoder 内核（`lib/kernel/thincoder/thincoder_process_io.dart:86`）· LSP（`lib/ide/lsp/lsp_process_io.dart:118`）· Claude CLI（`lib/kernel/claude_code/process_transport_io.dart:108`）· haiku 内核（`claude_haiku_io.dart:124`）· 调试适配器（`lib/debug/session/stream_debug_adapter.dart:56`）· MCP 探测（`lib/customize/mcp_probe_io.dart:73`）· 密钥库（`lib/models/secret_store_io.dart:36`）。
- 其余一次性调用（git、chmod、taskkill、reg.exe、ps、scutil、sysctl、open / xdg-open、版本探测、安装器 detached 启动、shell 命令）→ `ProcessHost.run`；`Process.runSync` 改异步，签名随调用点一起改。
- **机检守门**（防回归）：一条测试扫描 `lib/**`，除 `lib/platform/process_host_io.dart` 外不得出现 `Process.start(` / `Process.run(` / `Process.runSync(`。
- 条件导入照既有形状（`lib/kernel/thincoder/thincoder_process.dart:2-4` 的 stub / io 分档）：web 上代理不存在，`ProcessHost` 调用即失败，与今天无进程可起同义。

**为什么不是别的**：

- 不写原生线程插件：多一份 C++ 与 IPC，且每个平台各一份；isolate 是纯 Dart、跨桌面三平台同一份代码。
- 不靠「提前预热」绕开：预热本身就在窗口线程上调 `Process.start`，冻的还是窗口（现有 9 份报告正来自预热 / 启动）。
- 不逐点 `Isolate.run`：`Process` 对象不能跨 isolate 传递，长驻进程必须在代理里活着；只包 `Process.run` 会留下最贵的那一类。

**验收与 N4 的关系**：F8 的第二条验收读 `[stall]`（N4 的产出），所以 N4 必须先落地，否则 F8 只有挂起看门狗一条读数。

### 3.3 F5：重绘的代价在「列表外面那一层」——先量，再按判据改

**已核的负事实**：行级重绘边界已经存在。`SuperListView.builder` 的 `addRepaintBoundaries` 默认 `true`（`super_sliver_list-0.4.1/lib/src/super_sliver_list.dart:406`），调用点没关（`lib/chat/chat_history_view.dart:2642`）。
⇒ 「补行级 `RepaintBoundary`」不是本批的修法；慢帧不可能是「整表逐行重绘」。

**结构性嫌疑（待绘制面确认）**：整个列表被 `EdgeFadeMask` 包住（`lib/chat/chat_history_view.dart:2620`，实现在 `lib/chat/widgets/edge_fade_mask.dart:92` 的 `RenderEdgeFadeMask`）。
它罩住的是**整块列表区域**；若它的 `paint` 走 `saveLayer` ∥ 着色器覆盖全区域，那么任何一行重绘都会让整块区域重新合成——与「raster 340 ms、build 0–9 ms」同形：构建没变，合成面积是整块画布。

**决策规则（写死，实施不另裁）**：

1. 先量：大会话（≥1000 条）流式回放，在 `tool/perf` 场景里取 `FrameTiming.rasterDuration`（同窗口、同机器，N2），并在 `RenderEdgeFadeMask.paint` 前后加临时计时（只在本轮诊断，收口前删）。
2. 判据：若慢帧的绘制耗时集中在 `RenderEdgeFadeMask` 的合成 ⇒ 改法 = 把整块遮罩换成**两条固定高度的边缘渐变带**（上 ∥ 下各一条、只覆盖边缘几十像素，各自独立 `RepaintBoundary`），列表主体不再被任何全区域层罩住。
3. 若慢帧不集中在遮罩 ⇒ 在行内定位（行内是否还有全宽 `saveLayer`：`_Appear` 的 `FadeTransition`（`:3695`）只在出现动画的 260 ms 内存在，`_HeightMotion` 的 `pushClipRect`（`:3882`）只在高度动画期间存在）——按「谁的全区域 `saveLayer` 在流式帧上」逐个收窄。
4. 验收口径不变（§7 A / B）。

**为什么按这个顺序**：需求 N2 的「测量先行」；慢在光栅化已实测，而「哪一层在合成」只能从运行时的绘制面取，不靠读代码猜。

### 3.4 F6：不可见时不重建、不出帧，切回一次追平

**触发面**：`AppLifecycleState`，判据照既有先例 `null || resumed` 视为可见（`lib/main.dart:628-631` 的 `inFront()`）。

**机制**（落在 `ChatHistoryView` 的 State）：

```text
_handleSessionChanged：
  照常更新尾巴快照（判据随时可走快路径）
  WindowVisible.isVisible == false ⇒ _dirtyWhileHidden = true，return（不 setState、不 _liveTick++）
  否则 ⇒ 走今天的快路径 ∥ 全路径（不变）

didChangeAppLifecycleState(resumed)：
  _dirtyWhileHidden ⇒ 一次 _refold（全量）+ setState + _liveTick++；清标记
```

- **内容不丢是构造性的**：视图不缓存文本，build 时从 feed 读最新值；失焦期间的增量都在 `Transcript` 里，恢复后一次重建即最新态。
- **不重建 ⇒ 无帧**：本视图的帧源只有三个——`setState`、`_liveTick`（`docs/design/chat-streaming.md` §3.2）、`Steadiness` 的到点 `setState`（同档 §13-2，调用点 `lib/chat/chat_history_view.dart:225-229`）。三个入口都过同一道 gate（新增 `_rebuild()`，内部判可见性）。
- **残余帧源（一并关掉）**：`MarkdownView` 的 50 ms trailing 计时器（`docs/design/chat-streaming.md` §3.6）。失焦前已排上的那一次会在失焦后落成一帧——同一 gate 在 `MarkdownView` 生效（§4.4）。
- **可见性判据取「失焦」而不是「被遮挡」**：需求档 F6 原文即 `lifecycle inactive`。并排使用（可见但未聚焦）时画面停在失焦那一刻，聚焦后一次到位——这是本批唯一一处用户可见行为变化，登记 §10 与 §12。

### 3.5 N3：DPR 变化留痕

**机制**：一个小的观察者监听 `View.of(context).devicePixelRatio`（build 时读）与 `MediaQuery` 的 `devicePixelRatio`，值变化时写一行事件日志：`[viewport] dpr <旧> -> <新> size <逻辑宽×高>`。时间戳由 `appEvent` 既有前缀给出。

**落点**：`lib/diagnostics/viewport_watch.dart`（新档），由 `BaoCodeApp.build` 旁挂载一次；既有媒体查询消费方（`lib/main.dart:872` 的 `PixelSnappedTextScaler`）不动。

**判据**：真机重现一次「放大再缩回」时，日志给出两次变化（如 `1.5 -> 2.25` / `2.25 -> 1.5`）及时刻与当时尺寸；不出现 ⇒ 这条假设被排除，按读到的结论另报。

### 3.6 N4：停顿看门狗（UI isolate 心跳）

**为什么需要**：界面线程被同步工作堵住时**连一帧都产不出**，`[slow]` 只在「画出一帧且超时」时记 ⇒ 这一类停顿零记录。实测佐证：2026-10-25 22:00–23:15 用户三次报卡，同期 `[slow]` 零条。

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

- F6 关的是**帧**（`WindowVisible` 为假时不重建、不出帧，§4.3）；N4 是**计时器**，只写一行日志，不 `setState`、不请求帧，因此它不会把 F6 关掉的帧重新叫起来。
- 反过来，N4 不接 `WindowVisible`：失焦期间的停顿正是要量的东西（实测四条慢帧中 3 条 `inactive`）。若心跳随可见性停，失焦期的停顿就永远看不到。
- **一处刻意的盲区**：`lifecycleState` 为 `hidden` ∥ `paused` 时不写行（最小化 / 系统挂起）。机器睡眠会造出几十分钟的假 gap，撞掉验收里的「1 小时零误报」。代价写明：最小化期间的停顿不测。

**行里带什么**：`gap` + `FrameWatch` 已有的状态行（semantics、render objects、在显示的会话、内存、`lifecycleState`，`frame_watch.dart:126-157`）。做法：把那一段提成档内共享函数，两处调用——一处定义（D2），`[stall]` 与 `[slow]` 的字段因此可直接对读。

**不刷屏**：一次同步阻塞只让计时器迟一拍（periodic 计时器按回调重排，不补拍），所以一次卡顿 = 一行；再加每轮上限 200 行（照 `FrameWatch._most`，`frame_watch.dart:44`），慢性卡顿也不会把日志写满。

**测量的边界（写明）**：小于 400 ms 的停顿测不到（测量粒度就是周期）；停顿恰好跨拍时读数会少一拍以内。

## 4. 接口契约

### 4.1 预热池（`lib/kernel/thincoder/thincoder_warm.dart`）

```dart
/// key = (cwd, files)，与现在相同；每 key 一个槽，池总上限 maxHeld。
final class ThincoderWarm {
  /// 为 key 备一个进程；该 key 已有槽 ∥ 正在起 ⇒ 空操作。启动串行。
  Future<void> warm(String cwd, {required bool files});

  /// 把一个没有会话的活进程交回池（视图离开时由内核调用）。
  /// 同一 key 已有槽 ∥ 传输已结束 ⇒ 关闭它并返回 false（不静默多留）。
  bool keep(ThincoderWarmKey key, ThincoderWarmTake take);

  /// 取走 key 的槽；过期、已退出、key 不符 ⇒ null。
  ThincoderWarmTake? take(ThincoderWarmKey key);

  /// 等正在起的那个（至多 startup = 30 s），再 take。
  Future<ThincoderWarmTake?> takeWhenReady(ThincoderWarmKey key);

  /// 丢掉某项目的全部槽（项目被隐藏 ∥ 首选内核不再是 thincoder）。
  void dropProject(String cwd);

  /// 池总上限；满时淘汰 heldAt 最老的槽。
  static const maxHeld = 3;
}
```

- `ThincoderWarmTake` 形状不变（`thincoder_warm.dart:20-24`）：`connection` + `transport` + `handshake`。
- `keep` 的前提由调用方保证：`_canClose` 为真（`thincoder_release.dart:90-94`）、`session/close` 已发出、`connection.onRequest` / `onNotification` 已置空。
- 构造注入照旧（`start` / `launch` / `clock` / `schedule`，`:37-47`），测试用注入实例并 `finally` 还原 `instance`。

### 4.2 进程代理（`lib/platform/process_host.dart` + `process_host_io.dart` + `process_host_stub.dart`）

```dart
/// 一次进程创建的全部参数；字段与 dart:io 的同名参数同义。
final class ProcessSpec {
  const ProcessSpec(this.executable, this.arguments,
      {this.workingDirectory, this.environment, this.includeParentEnvironment = true,
       this.runInShell = false, this.mode = ProcessStartMode.normal});
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

abstract final class ProcessHost {
  /// 代理 isolate 懒启动一次，此后复用。
  static Future<HostedProcess> start(ProcessSpec spec);
  static Future<HostedRun> run(ProcessSpec spec,
      {Encoding stdoutEncoding = systemEncoding, Encoding stderrEncoding = systemEncoding});
  /// 应用退出：关掉代理持有的全部进程。
  static Future<void> stopAll();
}
```

- 代理内部：`Isolate.spawn(_serve)`；消息 id 对应一次请求；字节以 `Uint8List` 传递；`transport_exit` 语义与 `ThincoderExit` 无关，由各调用方自己按 exitCode 组消息。
- 失败：代理未起、通道断开、`ProcessException` ⇒ 抛 `ProcessHostUnavailable`（携带原始信息），调用点映射为既有错误类型。**不回退到窗口线程**。
- 生命周期：代理随应用活；`stopAll()` 在退出路径调用（`lib/kernel/thincoder/thincoder_process.dart:13` 的 `stopThincoderProcesses` 是其中一处，另有各调用方自己的清理）。

### 4.3 可见性 gate（`lib/chat/window_visible.dart`）

```dart
/// 窗口是否可见：可见 = 生命周期为 resumed，或还没有状态。
/// 供「不可见时不出帧」的帧源查询；翻转时通知。
abstract final class WindowVisible {
  static bool get isVisible;
  static Listenable get changed;
}
```

- 内部只注册一个 `WidgetsBindingObserver`（`start()` 由 `ChatHistoryView.initState` 调用一次即可，幂等），避免每个消费者各注册一次。
- 消费者两个：`ChatHistoryView`（重建 gate）· `MarkdownView`（计时器 gate）。两处的语义都是「不重建 = 不出帧」。
- **N4 不是它的消费者**（§3.6）：心跳不随可见性停。

### 4.4 `MarkdownView` 的计时器 gate

- 不可见时：取消待决 trailing 计时器、置 `_parseWhenVisible = true`，不 `setState`。
- 变可见：`_parseWhenVisible` ⇒ 立即解析最新 `widget.data`（与 `dispose` 后重建同一语义，最终态由同一解析函数产出）。
- 非流式四处调用（`assistant_text.dart` / `notice_row.dart` / `plan_card.dart` / stash 预览）数据不变 ⇒ 不进该分支，零行为变化。

### 4.5 「超预算帧数」的读法（F5 验收）

- 阈值 = **100 ms**（需求档建议值）。一帧光栅化超过 100 ms 即用户可感知的掉帧。
- 设备面：`FrameTiming.rasterDuration`，与 `FrameWatch._timings` 同一回调面（`frame_watch.dart:96`）；场景 = `tool/perf` 的大会话流式回放。
- 测试面：`tester` 拿不到真实 GPU 计时 ⇒ 断言结构（流的最近 `RepaintBoundary` 落在行内、列表主体不再被全区域层罩住）+ 重建计数（F1 的既有读数不回退）。
- 改前 / 改后同场景、同窗口、同机器（N2）。

### 4.6 停顿看门狗（`lib/diagnostics/stall_watch.dart`）

```dart
/// UI isolate 的心跳：两拍之间超出周期的部分达到 [threshold] 时，
/// 写一行 `stall`（gap + 当时的界面状态）。
/// 不可见时照常跳（§3.6）；hidden ∥ paused 不写行。
final class StallWatch {
  StallWatch({Duration period, Duration threshold, DateTime Function()? now, void Function(String) write});

  void start();
  void stop();
}
```

- 参数与写出面可注入（构造注入，照 `ThincoderWarm` 的形状 `thincoder_warm.dart:37-47`），测试用注入实例、不动静态入口。
- 单调时钟优先：注入面默认 `Stopwatch`（照 `FrameWatch` 的 `_clock`，`frame_watch.dart:49`），不用墙上时钟。
- 挂载：`StallWatch(...).start()` 在 `lib/main.dart:155-158` 的块内调用一次。

### 4.7 F7 的放回挂点（`lib/kernel/thincoder/thincoder_release.dart`）

```dart
// _releaseWhenIdleOf / disposeOf：本应 _teardown() 处
owner._closeSession();
owner._teardown(keep: true);   // 能放回就放回，否则与今天相同（关闭）

// _teardownOf(owner, {bool keep = false})：keep 且池接收时
final take = (connection: owner._connection!, transport: owner._transport!,
              handshake: owner._handshakeAnswer!);
owner._connection!.onRequest = null;
owner._connection!.onNotification = null;
if (!ThincoderWarm.instance.keep(key, take)) take.transport.close();
```

- `_handshakeAnswer` 是内核在 `_handshakeOf`（`thincoder_lifecycle.dart:144-159`）里顺手存下的握手原文，供放回使用（+1 个字段）。
- key 来自内核已有的 `_cwd` 与 `_context.files != null`（`thincoder_lifecycle.dart:22` 同式）。
- **不放回**的路径保持销毁：`restartOf`（显式重启，`thincoder_release.dart:70-74`）、`_exitedOf`（进程已走，`:142-179`）。

## 5. 受影响文件清单（行数 = 编制日实测）

| # | 坐标 | 改动 | 现行 | 预期增量 | 结论 |
|---|---|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_warm.dart` | 单槽 → 多槽 + `keep` + 上限淘汰 + `dropProject`（§3.1 · §4.1） | 242 | +≈90 / −≈40 | 未超档 |
| ② | `lib/kernel/thincoder/thincoder_release.dart` | `_teardown(keep:)` 与两处调用点（§4.7） | 187 | ≤ +35 | 未超档 |
| ③ | `lib/kernel/thincoder/thincoder_lifecycle.dart` | 握手原文留一份供放回（§4.7） | 170 | +2 | 未超档 |
| ④ | `lib/kernel/thincoder/thincoder_kernel.dart` | `_handshakeAnswer` 字段 | 480 | +3 | 未超档 |
| ⑤ | `lib/workspace/workspace.dart` | 不再切项目 drop；`hideProject` 用 `dropProject`；`ready` 补预热（§3.1） | 3027 | ≤ +12 / −3 | 超 800 档：只加分支，沿用既有拆分预案 |
| ⑥ | `lib/platform/process_host.dart` | **新档**：代理 isolate 的公共面（§4.2） | 0 | +≈60 | 新档 |
| ⑦ | `lib/platform/process_host_io.dart` | **新档**：`Process` 的真实代理（唯一创建点） | 0 | +≈220 | 新档 |
| ⑧ | `lib/platform/process_host_stub.dart` | **新档**：web 上无进程 | 0 | +≈20 | 新档 |
| ⑨ | `lib/kernel/thincoder/thincoder_process_io.dart` | `Process.start` → `ProcessHost.start`（§3.2） | 207 | +≈25 / −≈30 | 未超档 |
| ⑩ | `lib/ide/lsp/lsp_process_io.dart` | 同上 | 193 | +≈20 / −≈25 | 未超档 |
| ⑪ | `lib/kernel/claude_code/process_transport_io.dart` | 同上 | 269 | +≈15 / −≈20 | 未超档 |
| ⑫ | `lib/kernel/claude_code/claude_haiku_io.dart` | 同上 | 280 | ≤ +10 | 未超档 |
| ⑬ | `lib/debug/session/stream_debug_adapter.dart` | 同上 | 174 | ≤ +10 | 未超档 |
| ⑭ | `lib/customize/mcp_probe_io.dart` | 同上 | 261 | ≤ +10 | 未超档 |
| ⑮ | `lib/models/secret_store_io.dart` | 同上 | 276 | ≤ +10 | 未超档 |
| ⑯ | 一次性调用迁移（每处 1–3 行换 `ProcessHost.run`）：`lib/forge/forge_io.dart` 81 · `lib/ide/project_tools_io.dart` 356 · `lib/platform/shell_command_io.dart` 561 · `lib/platform/child_process_registry.dart` 197 · `lib/workspace/editor_launcher_io.dart` 65 · `lib/link/link_platform_io.dart` 228 · `lib/network/network_proxy_io.dart` 260 · `lib/remote/remote_binaries.dart` 442 · `lib/settings/data_dir_service.dart` 605 · `lib/update/installer_io.dart` 589 · `lib/kernel/claude_code/claude_onboarding_io.dart` 104 · `lib/kernel/thincoder/thincoder_locator.dart` 379 | `Process.run` → `ProcessHost.run`；`runSync` 改异步（`thincoder_config_store.dart` 496） | — | 合计 ≤ +60 / −25 | 逐处机械替换 |
| ⑰ | `lib/chat/chat_history_view.dart` | F6 gate：`_rebuild()` 包住三个帧源 + `WindowVisible` 挂载 + 恢复时一次全量 | 3922 | ≤ +40 | 超 800 档：只加 gate，不拆档 |
| ⑱ | `lib/chat/widgets/edge_fade_mask.dart` | F5：整块遮罩 → 两条固定高度边缘渐变带（§3.3 判据成立时） | 293 | ≤ +30 | 未超档 |
| ⑲ | `lib/chat/widgets/markdown_view.dart` | 计时器 gate（§4.4） | 1076 | ≤ +20 | 超 800 档：只加字段与一个分支 |
| ⑳ | `lib/chat/window_visible.dart` | **新档**：一个观察者 + 静态查询 | 0 | +≈50 | 新档 |
| ㉑ | `lib/diagnostics/viewport_watch.dart` | **新档**：DPR 留痕（§3.5） | 0 | +≈40 | 新档 |
| ㉒ | `lib/diagnostics/stall_watch.dart` | **新档**：停顿看门狗（§3.6 · §4.6） | 0 | +≈90 | 新档 |
| ㉓ | `lib/diagnostics/frame_watch.dart` | 状态行提成档内共享函数（§3.6） | 158 | +≈6 | 未超档 |
| ㉔ | `lib/main.dart` | 挂 `ViewportWatch` + `StallWatch.start()` | 919 | +2 | 超 800 档：只加挂载行 |
| ㉕ | `test/kernel/thincoder/thincoder_warm_test.dart` | **新档**：多槽 / 放回 / 淘汰 / 过期（§8 T15–T18） | 0 | +≈160 | 新档 |
| ㉖ | `test/platform/process_host_test.dart` | **新档**：代理往返（§8 T19–T20） | 0 | +≈120 | 新档 |
| ㉗ | `test/platform/no_window_thread_process_test.dart` | **新档**：守门扫描（§8 T21） | 0 | +≈50 | 新档 |
| ㉘ | `test/diagnostics/stall_watch_test.dart` | **新档**：N4 用例（§8 T9–T13） | 0 | +≈120 | 新档 |
| — | `test/chat/chat_history_rebuild_test.dart` | 零改动，重跑取 A1/A4 不回退 | 507 | 0 | — |

## 6. 关键决策记录

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | F7 = **多槽池 + 用完放回 + 接管后补预热** | 单槽 `drop('project-switch')` 是根因（`thincoder_warm.dart:104-113`）；只多留预热仍每切一次起一个进程（预热自己写 `launch: builtin`）⇒ 达不到「N ≥ 5 增量 ≤ 1」 |
| D2 | 放回只在 `_canClose` 为真时发生，且清空 `onRequest` / `onNotification` | 有回合 / 子代理 / 挂起窗口的进程不能带走；悬空回调会让下一个会话收到上一个会话的回调 |
| D3 | 池上限 `maxHeld = 3`、每槽 ttl 10 分钟 | 每进程约 85 MB ⇒ 池上限约 255 MB；ttl 沿用既有值，空转不超过 10 分钟 |
| D4 | F8 = **唯一进程代理 isolate**，不是每点 `Isolate.run` | `Process` 对象不能跨 isolate 传，长驻进程必须在代理里活；只包 `Process.run` 会留下最贵的启动 |
| D5 | 代理失败 **显式抛错，不回退窗口线程直连** | 回退把 6 秒冻结放回来且没人知道（业务门：失败要可见） |
| D6 | 全量迁移 26 处创建点 + 守门测试 | 需求 F8 说的是「任何子进程」；守门测试让这句话可机检，也防新代码写回 UI 线程 |
| D7 | F5 修法 = **收窄全区域合成层**，不是加行级边界 | 行级 `RepaintBoundary` 已由 sliver delegate 默认加上（`super_sliver_list` :406，调用点未关）⇒ 再加一层是空转 |
| D8 | F5 先量绘制面再定改点，判据写死（§3.3 规则 2 / 3） | 需求 N2「测量先行」；「哪一层在合成」只能从运行时取 |
| D9 | F6 = **重建 gate（视图 + markdown 计时器）**，不是降帧率 | 不可见时唯一正确的帧数是 0；降帧仍付同样的单帧光栅化代价 |
| D10 | F6 可见性判据 = `lifecycleState`，与 `lib/main.dart:628-631` 同形 | 与需求档 F6 原文一致；不新造「被遮挡」探测 |
| D11 | N4 心跳**不接** F6 的可见性 gate，`hidden` / `paused` 不写行 | 失焦期的停顿正是要量的（3/4 慢帧 `inactive`）；睡眠造成的假 gap 会撞掉「1 小时零误报」 |
| D12 | N4 的 `gap` = 实测间隔 − 周期 | 需求验收窗口是 700–1000 ms；取原始间隔会读成 1000–1050 ms，落在窗口外 |
| D13 | N4 的状态行与 `FrameWatch._state()` 共用一份 | 一处定义（D2）；`[stall]` 与 `[slow]` 字段可直接对读 |
| D14 | N3 = **新增一行日志**，不改媒体查询链路 | 先量后定；DPR 是既有事实，缺的只是留痕 |

**最近先例（对齐 ∥ 偏离）**：

- 对齐：isolate + 端口承载长驻工作在本仓已有先例——`lib/kernel/claude_code/dart_core_transport_io.dart:37` 的 `AgentIsolate.spawn`；F8 的代理是同一形状，只做进程创建与字节转发。
- 对齐：重绘边界在本仓是既有做法（`lib/chat/agent_view.dart:67` 的 `RepaintBoundary(child: child)`）——F5 不是引入新机制，而是收窄既有的全区域层。
- 对齐：生命周期判据照 `lib/main.dart:628-631` 的 `null || resumed`。
- 对齐：诊断留痕照 `FrameWatch` 的形状（`lib/diagnostics/frame_watch.dart`：`appEvent` 写一行，不碰业务；构造注入时钟），N3 / N4 两块都走这个形状。
- 对齐：F7 的补预热沿用 workspace 已有的 `_warmThincoder`（`lib/workspace/workspace.dart:448`），只加调用点，不新造预热入口。
- 偏离：`MarkdownView` 目前对窗口状态无感知（只有 50 ms 节流计时器，`docs/design/chat-streaming.md` §3.6）。偏离理由 = 它是失焦后残余帧的来源，不关掉达不到 F6 的「帧数 0」；守门 = §8 T3。
- 偏离：N4 是全仓第一个「按计时器测界面线程」的探针（`[slow]` 按帧、`AppEventWatch` 按事件）。偏离理由 = 被堵住的线程产不出帧，只有计时器看得见；守门 = §8 T9–T13。
- 偏离：进程创建从「谁用谁起」变为「一个代理统一起」（`dart:io` 的默认用法，全仓 29 处）。偏离理由 = 窗口线程冻结 6 秒（需求 F8 的 9 份报告）；守门 = §8 T21 的扫描与 F8-A 的挂起报告零新增。

**公开源调查**（`index.publicRepos` 为空：本仓无独立上游文档仓）：

- 已核的第一手来源：`super_sliver_list-0.4.1` 的构造函数默认值（本机 pub cache，`lib/src/super_sliver_list.dart:406`）。
- 已核的本仓坐标：`lib/kernel/thincoder/thincoder_warm.dart`（池语义）· `thincoder_release.dart`（释放路径）· `thincoder_protocol.dart`（连接的可空回调）· `lib/diagnostics/frame_watch.dart`（诊断形状）· `windows/runner/hang_watchdog.cpp`（冻结判据 `kHangMilliseconds = 6000`，`:24`）。
- **未核（`unverified`）**：Flutter 引擎侧「Impeller 下全区域 `saveLayer` 的合成代价」；`AppLifecycleState.hidden` 在 Windows 最小化时的具体映射；代理 isolate 在 Windows 上被 Defender 扫描时的实际耗时（设计结论只依赖「不在窗口线程」，不依赖耗时数值）。

## 7. 验收对照（回指需求档 F5 / F6 / F7 / F8 / N3 / N4 + N2）

| 需求 | 落点 | 机检判据 |
|---|---|---|
| F7 warm hit > 0 且随切换增长 | §3.1 · §4.1 | F7-A：同一项目内连开 3 个已列出的会话并来回切换 ⇒ 第 2 次起日志出现 `timing: warm hit <ms>`，计数随切换增长；单测 T15–T16 |
| F7 启动次数不随切换增长 | §3.1 | F7-B：同一组会话来回切换 5 次，`launch: builtin` 行（`thincoder_locator.dart:131-134`）增量 ≤ 1；改前 / 改后两次读数并列留档 |
| F7 切换可输入延迟 ≤ 200 ms | §3.1 | F7-C：同一操作路径计时，与改前中位 569 ms 对照；单测 T18 断言 take 路径不起进程 |
| F8 挂起报告零新增 | §3.2 | F8-A：同一操作路径下 `logs/hangs/hang-*.txt` 零新增（现有 9 份为基线） |
| F8 窗口线程无 > 500 ms 停顿 | §3.2 · §4.6 | F8-B：`[stall]` 无 gap > 500 ms 的行（依赖 N4 已落地） |
| F8 无窗口线程进程创建 | §3.2 | F8-C：T21 扫描 `lib/**`，除 `lib/platform/process_host_io.dart` 外零 `Process.start/run/runSync`；T19–T20 代理往返正确 |
| F5 超预算 raster 帧 → 0 | §3.3 · §4.5 | A：`tool/perf` 大会话流式回放，`rasterDuration > 100 ms` 的帧数 = 0（改前读数须已在动代码前量好，两次读数并列留档）；总帧数与改前同量级（±20%） |
| F5 重绘范围不随界面大小 / 历史增长 | §3.3 | B：组件测试断言流式行最近的重绘边界在行内、列表主体无全区域合成层；另 20 / 200 回合两跑，流式帧的 `ChatItemView` 重建数逐项相等（既有 A1 口径不回退） |
| F6 不可见期帧数 = 0，切回一帧追平 | §3.4 · §4.3 · §4.4 | C：模拟 `inactive` 后回放 120 个增量 ⇒ `ChatItemView` 重建 0 次、`MarkdownView` 解析 0 次；恢复 `resumed` ⇒ 恰 1 次重建，可见文本 == 全文；设备面：失焦 60 秒 `FrameTiming` 帧数 0（或仅 1 帧残余尾帧） |
| N3 DPR 留痕 | §3.5 | D：模拟 DPR 1.5 → 2.25 → 1.5，事件日志出现两行 `[viewport] dpr 1.5 -> 2.25` / `2.25 -> 1.5`，各带尺寸；真机重现一次即定论 |
| N4 停顿必须留读数 | §3.6 · §4.6 | G：构造 800 ms 同步阻塞 ⇒ 恰一行 `[stall]`，gap ∈ 700–1000 ms；无阻塞连续 1 小时 0 行；`hidden` / `paused` 状态 0 行 |
| N2 同法可比 | §2 · §4.5 | E：改前读数在动代码前量，改后同场景、同窗口、同机器复量，两次读数并列留档 |

## 8. 用例表

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 不可见期间流式（正常） | `inactive` + 120 个文本增量 + pump | 重建 0、解析 0、无帧；`_dirtyWhileHidden` 置起 |
| T2 | 恢复可见（边界） | 上述之后 `resumed` | 恰 1 次重建；可见文本 == 全文；无 pending timer |
| T3 | 不可见期间 markdown 尾帧（边界） | 失焦前 10 ms 内刚排上 trailing 计时器，随后 `inactive` | 计时器被取消、不 setState；恢复后解析一次 |
| T4 | 从头就不可见（边界） | 视图首帧时 `inactive` | 不起计时器、不出帧；恢复后一次到位 |
| T5 | 流式行重绘边界（正常） | 大会话 + 流式增量 | 该行最近的重绘边界在行内；列表主体无全区域合成层 |
| T6 | 高度动画期间增量（边界） | `_HeightMotion` 动画中 + 增量 | 允许动画期的额外合成；动画结束回到 T5 |
| T7 | DPR 变化（正常） | DPR 1.5→2.25→1.5 | 两行日志，值与时序正确；无变化时不写行 |
| T8 | 窗口不可见时 DPR 变化（边界） | `inactive` 中 DPR 变化 | 照写日志（留痕不依赖可见性） |
| T9 | 心跳无阻塞（正常） | 注入时钟，10 拍各 +250 ms | 0 行 `[stall]` |
| T10 | 一次 800 ms 同步阻塞（正常） | 一拍后注入 +1050 ms | 恰 1 行，`gap 800 ms`，带当时状态 |
| T11 | 阈值边界（边界） | 注入 +650 ms（gap = 400）与 +649 ms（gap = 399） | 前者写 1 行，后者 0 行 |
| T12 | 失焦期间阻塞（边界） | `inactive` + 800 ms 阻塞 | 照写 1 行（状态字段为 `inactive`）——心跳不随可见性停 |
| T13 | 最小化 / 挂起（边界） | `hidden` ∥ `paused` + 800 ms 阻塞 | 0 行（刻意盲区，§3.6） |
| T14 | 连续开已列出的会话（设备） | 同项目连开 3 个会话，读日志 | 第 2、3 次 `timing: warm hit` 且 < 200 ms；`launch: builtin` 行数并列报告 |
| T15 | 两项目交替预热（正常） | 依次 `warm` 项目 A、B，再 `take(A)` | A、B 两槽并存；`take(A)` 命中；B 仍持有（单测，注入 start） |
| T16 | 放回后再取（正常） | `keep(A)` 后 `take(A)` | 命中同一连接；`start` 调用计数不变（零新启动） |
| T17 | 池满淘汰（边界） | `maxHeld + 1` 个不同 key 依次 `keep` | 最早 `heldAt` 的槽被关闭并 `drop('capacity')`；其余可用 |
| T18 | 过期与进程已退出（边界） | 时钟推过 ttl；注入 `transport_exit` | `take` 返回 null 且不再等启动；槽被清 |
| T19 | 代理起一个进程（正常） | `ProcessHost.start` 起一个回显子进程 | stdout 收到回显；写入保序；`exitCode` 正确 |
| T20 | 代理执一次性命令（正常） | `ProcessHost.run('node', ['-e', ...])` | 退出码、stdout、stderr 与 `Process.run` 同值 |
| T21 | 守门扫描（正常） | 扫 `lib/**` 的 `Process.start(` / `Process.run(` / `Process.runSync(` | 除 `lib/platform/process_host_io.dart` 外 0 命中 |

## 9. 边界与失败面

- 不改列表实现、不做分段上限（需求档 §4）；不换渲染引擎（Impeller 保持）。
- 不改数据模型与 `KernelEvent` 形态；进程仍随视图离开而离开视图，但不再被销毁（F7 的「常驻会话内核」= B 案，不在本批）。
- 失败面（F7）：放回被拒、进程已退出、池满 ⇒ 关闭进程，下一次切回退回今天的行为（warm miss + 一次启动），无新错误面；启动失败沿用 60 s 冷却（`thincoder_warm.dart:100-103`）。
- 失败面（F8）：代理起不来 ⇒ 需要进程的功能显式报错（如 thincoder 启动失败提示），不静默回退；代理中途死亡 ⇒ 它持有的进程成为孤儿，由 `ChildProcessRegistry` 的既有回收处理（`lib/platform/child_process_registry.dart`）。
- 失败面（F6）：gate 误判「不可见」⇒ 画面停更，聚焦即恢复；误判「可见」⇒ 回到今天的行为。两向都不丢内容。`WindowVisible` 拿不到状态（`lifecycleState == null`）⇒ 按可见处理。
- 失败面（N4）：写入面自身抛错 ⇒ 吞掉并计数，不把看门狗变成新的崩溃源；每轮 200 行上限之后静默。

## 10. UI / 交互决定

- 视觉零变化（F5 的边缘渐变在形态上等价：从整块遮罩换成边缘带，判据 = 改前 / 改后同窗口截图逐像素比对边缘带区域）。
- F6 带来的可见行为变化：**窗口失焦期间画面停止更新**，聚焦后一次到位；并排使用时可见此现象。交 §12 第 1 项等用户确认。
- F7 的用户可见结果 = 切会话不再冻结 6 秒，无视觉与交互形态变化。
- F8 无界面变化；用户可感知的是不再出现 6 秒无响应。
- N3 / N4 只加日志，无 UI。
- 无新设置项、无新 l10n 键。

## 11. 集成测试设计

**本仓现状**：没有集成测试索引档（`test/` 下无索引），也没有可运行的集成套件（2026-10-26 复查：无匹配）⇒ 既有欠账，本批不新造索引，只登记增量。

- **本变更改动的业务可观察结果**：切会话是否还冻结 6 秒（F7 / F8）· 流式时是否跟手（F5）· 失焦切回是否一次到位（F6）。三者都没有用户可见入口的自动化路径（分别需要真实进程、真机 GPU 计时、真实生命周期事件）。
- **新增 / 改写的集成用例**：无（无可从用户入口驱动的业务场景；判据是设备读数与组件测试）。
- **本批交付的验证面**：组件与单测（§8 T1–T21）+ 设备读数（§7 F7-A/B/C · F8-A/B · A / C / D / G）+ 真机走查一次（连切会话、长会话流式、失焦切回）。
- **欠账登记（交父代理入台账）**：本仓缺集成测试索引与套件（0 / 50–100），非本批引入。

## 12. 未决项与需主 agent 同步的项

1. **F6 的可见行为变化**（§10）：失焦即停更，需用户确认；确认落在批档 §4。
2. **需求档 §4 边界与 F7 / F8 冲突**：`docs/requirements/chat-streaming.md` 的边界仍写「不改内核侧任何代码」，而 F7（`lib/kernel/thincoder/**`）与 F8（`lib/platform/**` + 各调用点）必须动这些目录。本档按 F7 / F8 的需求正文执行；需求档那一行需主 agent 改。设计侧不改需求档。
3. **需求档 §5「验收（本批整体）」未覆盖 F7 / F8 / N3 / N4**：该节现列 4 条，主要指向 F1–F3 与 F5 / F6。本批的验收以本档 §7 为准，需求档那一段需主 agent 补齐。
