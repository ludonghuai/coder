# 对话重绘边界与出帧时机（chat-raster-repaint）设计档

> 板块：对话渲染（chat-streaming）· 范围仓：baocode。
> 配对需求档：`docs/requirements/chat-streaming.md`（F5 · F6 · F7 · N3 · N4，测量纪律 N2）。
> 状态：设计稿 v2 · 2026-10-26 · 行号 = 编制日快照（实施按符号定位）。
> 与前档分工：`docs/design/chat-streaming.md` 管 F1–F4（增量重建边界 / 折叠 / markdown 节流）；本档管 F5 重绘范围 · F6 出帧时机 · F7 内核进程复用 · N3 DPR 留痕 · N4 停顿看门狗。

## 1. 模块目标与范围

**一句话**：长会话流式时，一帧的光栅化代价只跟真正变了的那一块走，不跟画布大小走；窗口看不见时不付这份代价；切会话不再等一次冷启动；界面线程被堵住时，应用自己留下读数。

**本批交付**：F5 重绘边界 · F6 不可见时不出帧 · F7 切会话复用内核进程（A 案）· N3 DPR 变化留痕 · N4 停顿看门狗。N2 是贯穿这五项的测量纪律。

**本批不做**：列表虚拟化 / 分段上限 / 数据分页（需求档 §4）· 换渲染引擎 · 数据模型与内核事件形态 · 视觉与交互形态改动 · F7 的 B 案（会话常驻内核）。

## 2. 事实基线（改前读数，动代码前按 N2 复量）

| 项 | 读数（2026-10-26，Release 1.7.2+19） | 来源 |
|---|---|---|
| F5 帧 | 70 分钟 4 条 `raster 340–350 ms`（build 0–9 ms），四条全在流式中 | 批档 §1 |
| F5 规模 | 会话 1060–1205 条、渲染对象 6163–6589、窗口 3840×2088@1.5（逻辑 2560×1392） | 批档 §1 |
| F6 状态 | 四条慢帧中 3 条 `lifecycleState == inactive`；10 分钟内失焦→聚焦 4 次 | 批档 §1 |
| F7 进程 | 当日 38 次 `launch: builtin` · 34 次 `warm miss` · **0 次 warm hit**；launch→handshake 中位 569 ms；01:16–01:19 13 次启动 | 需求档 F7 |
| N3 DPR | 三显示器、同时有 1.5 与 2.25；日志 view 0 恒 `@1.5`，无 DPR 变化行 | 需求档 N3 |
| N4 停顿 | 2026-10-25 22:00–23:15 用户三次报卡，同期 `[slow]` **零条**、`errors.log` 零条；Windows 事件 / 崩溃转储 / 内存耗尽 / GPU TDR 全空 | 需求档 N4 |

**读数面现成的东西**（`lib/diagnostics/frame_watch.dart`）：

- `_timings` 只在 `rasterDuration ≥ 250 ms` 时写 `[slow]` 行（`:96-106`），行内带 `build`。
- 状态行 `_state()`（`:126-157`）已给 semantics 节点数、render object 数、在显示的会话、RSS、`lifecycleState` —— N4 直接复用它（§3.5）。
- 没有 100 ms 档 ⇒ F5 的「超预算帧数」要另给读法（§4.3）。

## 3. 做法与理由

### 3.1 F5：重绘的代价在「列表外面那一层」——先量，再按判据改

**已核的负事实**：行级重绘边界已经存在。`SuperListView.builder` 的 `addRepaintBoundaries` 默认 `true`（`super_sliver_list-0.4.1/lib/src/super_sliver_list.dart:406`），调用点没关（`lib/chat/chat_history_view.dart:2642`）。
⇒ 「补行级 `RepaintBoundary`」不是本批的修法；慢帧不可能是「整表逐行重绘」。

**结构性嫌疑（待绘制面确认）**：整个列表被 `EdgeFadeMask` 包住（`lib/chat/chat_history_view.dart:2620`，实现在 `lib/chat/widgets/edge_fade_mask.dart:92` 的 `RenderEdgeFadeMask`）。
它罩住的是**整块列表区域**；若它的 `paint` 走 `saveLayer` ∥ 着色器覆盖全区域，那么任何一行重绘都会让整块区域重新合成——与「raster 340 ms、build 0–9 ms」同形：构建没变，合成面积是整块画布。

**决策规则（写死，实施不另裁）**：

1. 先量：大会话（≥1000 条）流式回放，在 `tool/perf` 场景里取 `FrameTiming.rasterDuration`（同窗口、同机器，N2），并在 `RenderEdgeFadeMask.paint` 前后加临时 `debugPrint`/帧计时（只在本轮诊断，收口前删）。
2. 判据：若慢帧的绘制耗时集中在 `RenderEdgeFadeMask` 的合成 ⇒ 改法 = 把整块遮罩换成**两条固定高度的边缘渐变带**（上 ∥ 下各一条、只覆盖边缘几十像素，各自独立 `RepaintBoundary`），列表主体不再被任何全区域层罩住。
3. 若慢帧不集中在遮罩 ⇒ 在行内定位（行内是否还有全宽 `saveLayer`：`_Appear` 的 `FadeTransition`（`:3695`）只在出现动画的 260 ms 内存在，`_HeightMotion` 的 `pushClipRect`（`:3882`）只在高度动画期间存在）——按「谁的全区域 `saveLayer` 在流式帧上」逐个收窄。
4. 验收口径不变（§7 A / B）。

**为什么按这个顺序**：需求 N2 的「测量先行」；慢在光栅化已实测，而「哪一层在合成」只能从运行时的绘制面取，不靠读代码猜。

### 3.2 F6：不可见时不重建、不出帧，切回一次追平

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
- **残余帧源（一并关掉）**：`MarkdownView` 的 50 ms trailing 计时器（`docs/design/chat-streaming.md` §3.6）。失焦前已排上的那一次会在失焦后落成一帧——同一 gate 在 `MarkdownView` 生效（§4.2）。
- **可见性判据取「失焦」而不是「被遮挡」**：需求档 F6 原文即 `lifecycle inactive`。并排使用（可见但未聚焦）时画面停在失焦那一刻，聚焦后一次到位——这是本批唯一一处用户可见行为变化，登记 §10 与 §12。

### 3.3 F7：切会话复用内核进程 —— A 案（预热复活），只动 workspace 层

**已核事实（三条）**：

- 预热池 `ThincoderWarm` 按 `(cwd, files)` 至多持一个进程、ttl 10 分钟（`lib/kernel/thincoder/thincoder_warm.dart:42`、`:141-144`）；`take()` 把进程整体交出去后池即清空（`:147-153` 的 `_forget(close: false)`）。
- **全仓只有一处预热调用**：`lib/workspace/workspace.dart:453`（打开项目时 `warm(path, files: true)`）。取走之后再无预热 ⇒ 第一个会话之后池恒空 ⇒ 与实测「34 次 miss · 0 次 hit」同形。
- 内核每次起进程前先问池（`lib/kernel/thincoder/thincoder_lifecycle.dart:22` 的 `takeWhenReady`），取不到才自己起（`:26`）。这一处**本批不改**。

**做法（`lib/workspace/**`，`lib/kernel/**` 零改动）**：
在 workspace 已有的会话监听里（`_listen` → `_sync`，`lib/workspace/workspace.dart:2300` / `:2308`）补一处再预热：当该会话的内核到达 `KernelHealth.ready`（`ChatSession.health`，`lib/chat/chat_session.dart:402`）时，调 `_warmThincoder(thread.project.path)`。

**为什么挂在 `ready` 上，而不是打开会话时**：`ready` 之前 take 一定已经发生——take 在 `thincoder_lifecycle.dart:22`，`_setHealth(KernelHealth.ready)` 在 `:70`，先 take 后 ready 的顺序由内核保证。挂在「打开会话」那一刻会与 take 赛跑：`warm()` 撞上「同一 key 已持有」直接返回（`thincoder_warm.dart:96-99`），紧接着 take 把池清空，这一轮白预热。

**为什么不防重复触发**：`warm()` 对同一 key 在「已持有 ∥ 正在起」时是空操作（`:96-99`），失败后有 60 s 冷却（`:100-103`）。所以每个 take 之后恰好补起一个进程；会话事件再多也只起一次。

**不变量（写死）**：

- 只有首选内核是 thincoder 且路径非远端才预热——沿用 `_warmThincoder` 既有两条判据（`:449-452`），不改签名、不改判据，只多一个调用点。
- 池里至多一个进程：`warm()` 的「一次一个」语义（`:104-116`）保证。
- 进程不常驻：ttl 到点自行释放（`:227-229` 的 `drop('ttl')`），空转上限 10 分钟。

**能拿到什么、拿不到什么**（按 `launch: builtin` 同口径）：

| 口径 | 改前 | A 案后 |
|---|---|---|
| 切到下一会话是否等握手 | 等：launch→handshake 中位 569 ms | 不等：`timing: warm hit <ms>` 一行为准，通常 < 10 ms |
| `warm hit` 次数 | 0 | 随切换增长（每开一个新会话 ≥ 1） |
| `launch: builtin` 行数 | 38 次/时段 | **不降**：预热自己也是一次启动（`thincoder_warm.dart:198` → `ThincoderLocator.launch`，日志在 `thincoder_locator.dart:131-134`） |

⇒ 需求档 F7 的「进程启动次数 ≤ 1（首次）」这条判据 **A 案不满足**，它只有 B 案（会话保住自己的内核）能满足，留待后续批次。本批的判据见 §7 F。

**残余失手（已知，不修）**：池在 ttl 到点后自行释放；若此后该项目 10 分钟内没有任何会话事件，下一次切会话是 warm miss——回暖由下一次会话活动触发，不由定时器触发。
刻意不设定时回暖：那会让每个打开过的项目永久常驻一个 Node 进程，而实测里没有这种需求的证据。

### 3.4 N3：DPR 变化留痕

**机制**：一个小的观察者监听 `View.of(context).devicePixelRatio`（build 时读）与 `MediaQuery` 的 `devicePixelRatio`，值变化时写一行事件日志：`[viewport] dpr <旧> -> <新> size <逻辑宽×高>`。时间戳由 `appEvent` 既有前缀给出。

**落点**：`lib/diagnostics/viewport_watch.dart`（新档），由 `BaoCodeApp.build` 旁挂载一次；既有媒体查询消费方（`lib/main.dart:872` 的 `PixelSnappedTextScaler`）不动。

**判据**：真机重现一次「放大再缩回」时，日志给出两次变化（如 `1.5 -> 2.25` / `2.25 -> 1.5`）及时刻与当时尺寸；不出现 ⇒ 这条假设被排除，按读到的结论另报。

### 3.5 N4：停顿看门狗（UI isolate 心跳）

**为什么需要**：界面线程被同步工作堵住时**连一帧都产不出**，`[slow]` 只在「画出一帧且超时」时记 ⇒ 这一类停顿零记录。实测佐证：2026-10-25 22:00–23:15 用户三次报卡，同期 `[slow]` 零条。

**落点**：`lib/diagnostics/stall_watch.dart`（新档），与 `FrameWatch` 同处挂载（`lib/main.dart:155-158` 的 `if (!kIsWeb)` 块内加一行）。

**机制**（形状照 `FrameWatch`，`lib/diagnostics/frame_watch.dart:31-41`）：

```text
Timer.periodic(250 ms)：
  实测间隔 = 单调时钟（Stopwatch）两次触发之差
  gap = 实测间隔 − 250 ms          // 超出周期的那一段
  gap >= 400 ms ⇒ appEvent('stall', 'gap <gap> ms; <界面状态>')
```

**为什么 gap 定义成「超出周期」，不是「两次触发的原始间隔」**：周期计时器被堵住后，下一拍要等界面线程放开才排上，原始间隔 ≈ 周期 + 阻塞时长（800 ms 阻塞 ⇒ 实测 1000–1050 ms）；而需求档 N4 的验收窗口是 700–1000 ms（`docs/requirements/chat-streaming.md:52`，构造 800 ms 阻塞）。
取超出量 ⇒ 读数落在 750–800 ms，正好在窗口内，且这个数可以直接读作「界面线程被占住了多久」。

**周期 250 ms / 阈值 400 ms（采需求建议值）**：阈值必须大于周期，否则计时器自身的排程抖动就会触发；400 = 250 + 150 ms 余量。周期再长丢分辨率（一次 400 ms 的卡顿可能整个落在两拍之间），再短只是多几次空转（4 次/秒的计时器成本在微秒级）。

**与 F6 的关系：心跳不停，两者不互相牵连**——

- F6 关的是**帧**（`WindowVisible` 为假时不重建、不出帧，§4.1）；N4 是**计时器**，只写一行日志，不 `setState`、不请求帧，因此它不会把 F6 关掉的帧重新叫起来。
- 反过来，N4 不接 `WindowVisible`：失焦期间的停顿正是要量的东西（实测四条慢帧中 3 条 `inactive`）。若心跳随可见性停，失焦期的停顿就永远看不到——那正是把用户的「莫名其妙卡住」留给下一次猜。
- **一处刻意的盲区**：`lifecycleState` 为 `hidden` ∥ `paused` 时不写行（最小化 / 系统挂起）。这两种状态下进程本就不跑界面线程，而机器睡眠会造出一个几十分钟的假 gap，撞掉验收里的「1 小时零误报」。代价写明：最小化期间的停顿不测。

**行里带什么**：`gap` + `FrameWatch` 已有的状态行（semantics、render objects、在显示的会话、内存、`lifecycleState`，`frame_watch.dart:126-157`）。
做法：把那一段从 `FrameWatch` 的私有方法提成档内共享函数，两处调用——一处定义（D2），`[stall]` 与 `[slow]` 的字段因此可直接对读。

**不刷屏**：一次同步阻塞只让计时器迟一拍（periodic 计时器按回调重排，不补拍），所以一次卡顿 = 一行；再加每轮上限 200 行（照 `FrameWatch._most`，`frame_watch.dart:44`），慢性卡顿也不会把日志写满。

**测量的边界（写明）**：小于 400 ms 的停顿测不到（测量粒度就是周期）；停顿恰好跨拍时读数会少一拍以内。

## 4. 接口契约

### 4.1 可见性 gate（`lib/chat/window_visible.dart`）

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
- **N4 不是它的消费者**（§3.5）：心跳不随可见性停。

### 4.2 `MarkdownView` 的计时器 gate

- 不可见时：取消待决 trailing 计时器、置 `_parseWhenVisible = true`，不 `setState`。
- 变可见：`_parseWhenVisible` ⇒ 立即解析最新 `widget.data`（与 `dispose` 后重建同一语义，最终态由同一解析函数产出）。
- 非流式四处调用（`assistant_text.dart` / `notice_row.dart` / `plan_card.dart` / stash 预览）数据不变 ⇒ 不进该分支，零行为变化。

### 4.3 「超预算帧数」的读法（F5 验收）

- 阈值 = **100 ms**（需求档建议值）。一帧光栅化超过 100 ms 即用户可感知的掉帧。
- 设备面：`FrameTiming.rasterDuration`，与 `FrameWatch._timings` 同一回调面（`lib/diagnostics/frame_watch.dart:96`）；场景 = `tool/perf` 的大会话流式回放。
- 测试面：`tester` 拿不到真实 GPU 计时 ⇒ 断言结构（流的最近 `RepaintBoundary` 落在行内、列表主体不再被全区域层罩住）+ 重建计数（F1 的既有读数不回退）。
- 改前 / 改后同场景、同窗口、同机器（N2）。

### 4.4 停顿看门狗（`lib/diagnostics/stall_watch.dart`）

```dart
/// UI isolate 的心跳：两拍之间超出周期的部分达到 [threshold] 时，
/// 写一行 `stall`（gap + 当时的界面状态）。
/// 不可见时照常跳（§3.5）；hidden ∥ paused 不写行。
final class StallWatch {
  StallWatch({Duration period, Duration threshold, DateTime Function()? now, void Function(String) write});

  void start();
  void stop();
}
```

- 参数与写出面可注入（构造注入，照 `ThincoderWarm` 的形状 `thincoder_warm.dart:37-47`），测试用注入实例、不动静态入口。
- 单调时钟优先：注入面默认 `Stopwatch`（照 `FrameWatch` 的 `_clock`，`frame_watch.dart:49`），不用墙上时钟（系统时间跳变会造出假 gap）。
- 挂载：`StallWatch(...).start()` 在 `lib/main.dart:155-158` 的块内调用一次。

### 4.5 F7 的再预热挂点（`lib/workspace/workspace.dart`）

```dart
// _sync 内，既有逻辑之后：
if (thread.session.health == KernelHealth.ready) {
  _warmThincoder(thread.project.path);   // 幂等：已持有同一 key 时是空操作
}
```

- `_warmThincoder` 不改签名与判据（`:448-454`），只多一个调用点。
- 只读内核侧 API（`ThincoderWarm.instance.warm` · `ChatSession.health`）：`lib/kernel/**` 零改动。

## 5. 受影响文件清单（行数 = 编制日实测，`find /c` 计数）

| # | 坐标 | 改动 | 现行 | 预期增量 | 结论 |
|---|---|---|---|---|---|
| ① | `lib/chat/chat_history_view.dart` | F6 的 gate：`_rebuild()` 包住三个帧源 + `WindowVisible` 挂载 + 恢复时一次全量 | 3922 | ≤ +40 | 超 800 档：不动行结构；沿用既有拆分预案，本批不触发 |
| ② | `lib/chat/widgets/edge_fade_mask.dart` | F5：整块遮罩 → 两条固定高度边缘渐变带（§3.1 判据成立时） | 293 | ≤ +30 | 未超档 |
| ③ | `lib/chat/widgets/markdown_view.dart` | 计时器 gate（§4.2） | 1076 | ≤ +20 | 超 800 档：只加 gate 字段与一个分支 |
| ④ | `lib/chat/window_visible.dart` | **新档**：一个观察者 + 静态查询 | 0 | +≈50 | 新档，<500 |
| ⑤ | `lib/diagnostics/viewport_watch.dart` | **新档**：DPR 留痕（§3.4） | 0 | +≈40 | 新档，<500 |
| ⑥ | `lib/diagnostics/stall_watch.dart` | **新档**：停顿看门狗（§3.5 · §4.4） | 0 | +≈90 | 新档，<500 |
| ⑦ | `lib/diagnostics/frame_watch.dart` | 状态行提成档内共享函数（§3.5） | 158 | +≈6 | 未超档 |
| ⑧ | `lib/main.dart` | 挂 `ViewportWatch` + `StallWatch.start()`（两行） | 919 | +2 | 超 800 档：只加挂载行 |
| ⑨ | `lib/workspace/workspace.dart` | F7 再预热挂点（§4.5） | 3027 | ≤ +8 | 超 800 档：只加一个分支 |
| ⑩ | `test/diagnostics/stall_watch_test.dart` | **新档**：N4 的用例（§8 T9–T13） | 0 | +≈120 | 新档，<500 |
| — | `lib/kernel/**` | **本批零改动**（F7 走 A 案，§3.3） | — | 0 | — |
| — | `test/chat/chat_history_rebuild_test.dart` | 零改动，重跑取 A1/A4 不回退 | 507 | 0 | — |

## 6. 关键决策记录

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | F5 修法 = **收窄全区域合成层**，不是加行级边界 | 行级 `RepaintBoundary` 已由 sliver delegate 默认加上（`super_sliver_list` :406，调用点未关）⇒ 再加一层是空转 |
| D2 | F5 先量绘制面再定改点，判据写死（§3.1 规则 2 / 3） | 需求 N2「测量先行」；「哪一层在合成」只能从运行时取 |
| D3 | F6 = **重建 gate（视图 + markdown 计时器）**，不是降帧率 | 不可见时唯一正确的帧数是 0；降帧仍付同样的单帧光栅化代价 |
| D4 | F6 可见性判据 = `lifecycleState`，与 `lib/main.dart:628-631` 同形 | 与需求档 F6 原文一致；不新造「被遮挡」探测 |
| D5 | F7 修法 = **A 案：take 之后补预热**，只动 workspace 层 | 池只有 take 没有补（§3.3），补上即命中；被否 B 案（会话常驻内核）改动面在 `lib/kernel/**`，且每个会话常驻一个 Node 进程 |
| D6 | F7 的验收口径按 A 案收窄：`warm hit` > 0 且随切换增长 | A 案不减少 `launch: builtin` 行数（预热自己也是一次启动），要求「≤ 1」只有 B 案能达标 ⇒ 该条留待后续批次 |
| D7 | N4 心跳**不接** F6 的可见性 gate | 失焦期的停顿正是要量的（3/4 慢帧 `inactive`）；且心跳只写日志、不请求帧，不会与 F6 打架 |
| D8 | N4 的 `gap` = 实测间隔 − 周期 | 需求验收窗口是 700–1000 ms；取原始间隔会读成 1000–1050 ms，落在窗口外 |
| D9 | N4 的状态行与 `FrameWatch._state()` 共用一份 | 一处定义（D2）；`[stall]` 与 `[slow]` 字段可直接对读 |
| D10 | N3 = **新增一行日志**，不改媒体查询链路 | 先量后定；DPR 是既有事实，缺的只是留痕 |

**最近先例（对齐 ∥ 偏离）**：

- 对齐：重绘边界在本仓是既有做法（`lib/chat/agent_view.dart:67` 的 `RepaintBoundary(child: child)`）——本批不是引入新机制，而是收窄既有的全区域层。
- 对齐：生命周期判据照 `lib/main.dart:628-631` 的 `null || resumed`。
- 对齐：诊断留痕照 `FrameWatch` 的形状（`lib/diagnostics/frame_watch.dart`：`appEvent` 写一行，不碰业务；构造注入时钟），N3 / N4 两块都走这个形状。
- 对齐：F7 的再预热沿用 workspace 已有的 `_warmThincoder`（`lib/workspace/workspace.dart:448`），只加调用点，不新造预热入口。
- 偏离：`MarkdownView` 目前对窗口状态无感知（只有 50 ms 节流计时器，`docs/design/chat-streaming.md` §3.6）。偏离理由 = 它是失焦后残余帧的唯一来源，不关掉达不到 F6 的「帧数 0」；守门 = §8 的 T3。
- 偏离：N4 是全仓第一个「按计时器测界面线程」的探针（`[slow]` 按帧、`AppEventWatch` 按事件）。偏离理由 = 被堵住的线程产不出帧，只有计时器看得见；守门 = §8 T9–T13。

**公开源调查**（`index.publicRepos` 为空：本仓无独立上游文档仓）：

- 已核的第一手来源：`super_sliver_list-0.4.1` 的构造函数默认值（本机 pub cache，`lib/src/super_sliver_list.dart:406`）。
- 已核的本仓坐标：`lib/chat/widgets/edge_fade_mask.dart`（遮罩实现）· `lib/diagnostics/frame_watch.dart`（诊断形状）· `lib/kernel/thincoder/thincoder_warm.dart`（池语义）。
- **未核（`unverified`）**：Flutter 引擎侧「Impeller 下全区域 `saveLayer` 的合成代价」；`AppLifecycleState.hidden` 在 Windows 最小化时的具体映射。
- 两条未核项都不影响判据：前者的证据或否证就是 §3.1 判据 1 的实测；后者由 N4 行内自带的状态字段在第一次真机读数里定。

## 7. 验收对照（回指需求档 F5 / F6 / F7 / N3 / N4 + N2）

| 需求 | 落点 | 机检判据 |
|---|---|---|
| F5 超预算 raster 帧 → 0 | §3.1 · §4.3 | A：`tool/perf` 大会话流式回放，`rasterDuration > 100 ms` 的帧数 = 0（改前读数并列批档 §6）；总帧数与改前同量级（±20%） |
| F5 重绘范围不随界面大小 / 历史增长 | §3.1 | B：组件测试断言流式行最近的重绘边界在行内、列表主体无全区域合成层；另 20 / 200 回合两跑，流式帧的 `ChatItemView` 重建数逐项相等（既有 A1 口径不回退） |
| F6 不可见期帧数 = 0，切回一帧追平 | §3.2 · §4.1 · §4.2 | C：模拟 `inactive` 后回放 120 个增量 ⇒ `ChatItemView` 重建 0 次、`MarkdownView` 解析 0 次；恢复 `resumed` ⇒ 恰 1 次重建，可见文本 == 全文；设备面：失焦 60 秒 `FrameTiming` 帧数 0（或仅 1 帧残余尾帧） |
| F7 切会话不等冷启动 | §3.3 · §4.5 | F：同一项目内连开 3 个已列出的会话 ⇒ 第 2、3 次日志出现 `timing: warm hit <ms>` 且值 < 200；`warm hit` 计数 > 0 且随切换增长；`launch: builtin` 行数并列报告（A 案不降，§3.3） |
| N3 DPR 留痕 | §3.4 | D：模拟 DPR 1.5 → 2.25 → 1.5，事件日志出现两行 `[viewport] dpr 1.5 -> 2.25` / `2.25 -> 1.5`，各带尺寸；真机重现一次即定论 |
| N4 停顿必须留读数 | §3.5 · §4.4 | G：构造 800 ms 同步阻塞 ⇒ 恰一行 `[stall]`，gap ∈ 700–1000 ms；无阻塞连续 1 小时 0 行；`hidden` / `paused` 状态 0 行 |
| N2 同法可比 | §2 · §4.3 | E：改前读数在动代码前量，改后同场景复量，两次并列写批档 §6 |

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
| T13 | 最小化 / 挂起（边界） | `hidden` ∥ `paused` + 800 ms 阻塞 | 0 行（刻意盲区，§3.5） |
| T14 | 连续开已列出的会话（设备） | 同项目连开 3 个会话，读日志 | 第 2、3 次 `timing: warm hit` 且 < 200 ms；`launch: builtin` 行数并列报告 |

## 9. 边界与失败面

- 不改列表实现、不做分段上限（需求档 §4）；不换渲染引擎（Impeller 保持）。
- 不改数据模型与 `KernelEvent`；**`lib/kernel/**` 本批零改动**（F7 走 A 案，只读其公开 API）。
- F7 的「进程启动次数 ≤ 1」不在本批达成（§3.3 表，判据见 §7 F）；B 案另立批。
- N4 不测最小化 / 挂起期间的停顿（§3.5 刻意盲区）；小于周期的停顿测不到。
- 失败面（F6）：gate 误判「不可见」⇒ 画面停更，聚焦即恢复；误判「可见」⇒ 回到今天的行为（有帧、慢）。两向都不丢内容。`WindowVisible` 拿不到状态（`lifecycleState == null`）⇒ 按可见处理（与 `lib/main.dart:628-631` 同）。
- 失败面（F7）：补预热失败 ⇒ 池空，下一次切会话退回今天的行为（warm miss + 569 ms），无新错误面；冷却 60 s 内不再重试（`thincoder_warm.dart:100-103`）。
- 失败面（N4）：写入面自身抛错 ⇒ 吞掉并计数，不把看门狗变成新的崩溃源；每轮 200 行上限之后静默。

## 10. UI / 交互决定

- 视觉零变化（F5 的边缘渐变在形态上等价：从整块遮罩换成边缘带，判据 = 改前 / 改后同窗口截图逐像素比对边缘带区域）。
- F6 带来的可见行为变化：**窗口失焦期间画面停止更新**，聚焦后一次到位；并排使用（可见但未聚焦）时可见此现象。这条交 §12 第 1 项等用户确认。
- F7 的用户可见结果 = 切会话更快，无视觉与交互形态变化。
- N3 / N4 只加日志，无 UI。
- 无新设置项、无新 l10n 键。

## 11. 集成测试设计

**本仓现状**：没有集成测试索引档（`test/` 下无索引），也没有可运行的集成套件（2026-10-26 复查：无匹配）⇒ 既有欠账，本批不新造索引，只登记增量。

- **本变更改动的业务可观察结果**：流式时界面是否跟手（帧耗时）· 失焦切回是否一次到位 · 切会话是否还要等冷启动。三者都没有用户可见入口的自动化路径（分别需要真机 GPU 计时、真实生命周期事件、真 Node 进程）。
- **新增 / 改写的集成用例**：无（无可从用户入口驱动的业务场景；判据是设备读数与组件测试）。
- **本批交付的验证面**：组件测试（§8 T1–T13）+ 设备读数（§7 A / C / D / F / G）+ 真机走查一次（长会话流式、失焦切回、连切会话）。
- **欠账登记（交父代理入台账）**：本仓缺集成测试索引与套件（0 / 50–100），非本批引入。

## 12. 未决项（交评审与用户）

1. **F6 的可见行为变化**（§10）：失焦即停更，需用户确认；确认落在批档 §4。
2. **需求档与 A 案的验收口径差**（§3.3 表）：需求档 F7 的「进程启动次数 ≤ 1（首次）」本批不达成，判据收窄为 `warm hit` 增长。需求档那一行需主 agent 同步（设计侧不改需求档）。
3. **需求档 §5「验收（本批整体）」只覆盖 F1–F3 与 F5 / F6**，F7 / N3 / N4 未列入该清单（需求档 `docs/requirements/chat-streaming.md:69-74`）。本批的验收以本档 §7 为准，需求档那一段需主 agent 补齐。
