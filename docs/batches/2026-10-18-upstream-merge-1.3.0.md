# 2026-10-18 · upstream-merge-1.3.0
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-18 · 来源 = 用户 2026-10-18 07:41「好，开合并分支」+ 07:44「A」；输入 = origin/main 24 个提交（release 1.3.0）与本地 15 个提交在 merge/upstream-1.3.0 上的两处冲突。
> 台账 = #52（chat-streaming · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：进行中（评审 pass，13 条已逐条落档；待用户批准）

## 讨论与定界（2026-10-18）

### 本批是什么

**一次合并**，不是新功能：`origin/main` 的 24 个提交（release 1.3.0）合入本地 15 个提交，在分支 `merge/upstream-1.3.0` 上解题。`main` 保持 66133c97，未受影响。

### 来源与授权

- 用户 07:41「好，开合并分支」→ 建分支并起合并；
- 用户 07:44「A」→ 选**合规链**（设计 → 评审 → 批准 → eng-coder），不走近路。

### 两处冲突（实读）

| # | 文件 | 性质 |
|---|---|---|
| ① | `lib/chat/chat_history_view.dart:135-230` | 两边各写一套 `_refold` 与相关成员：本地 = B 批快路径（`grow`/`extend`、`_watchTail`、`_tailGrew`、`_liveRow`）；上游 = `_liveStart` + `Steadiness` |
| ② | `lib/main.dart:179-193` | 两侧互不依赖的设置接线：`ThincoderPathSetting` ↔ `ClaudeCore` ⇒ 并集 |

### 关键判断（父代理实读）

- 上游**没有**做增量渲染（其 `_refold` 仍是全量 `StepFolds.of`）⇒ 我们的快路径与 `extend` 不是重复实现，合并后仍有价值。
- 上游新引入的 `Steadiness` 用 300/700ms 定时器驱动 `setState`——它与「每增量外壳 0」是两个来源，A1 的读数可能因此需要澄清口径（设计已给 A4 用例区分）。

### 范围外

- 不改回上游行为；不做合并之外的清理（上游两处可疑行为只报告，见 §2.14）。
- 不进 merge commit：`pubspec.lock` 的镜像 URL 翻转、`docs/requirements/thincoder-adapter.md`、未跟踪文档。
- 不做真机走查（合并无视觉/交互改动）。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（评审第 1 轮 pass，13 条已逐条落档；待用户批准）

### 2.1 条目（本批覆盖）

| 号 | 条目 | 机检判据 |
|---|---|---|
| E1 | 冲突①合成：`_refold` 保留 `grow`/`extend` 分支，**并**在其中之后跑上游的 `_liveStart` 重算；两侧成员全留 | §2.3 伪代码逐行落地；`flutter analyze` 干净；A1/A2 读数不变（§2.7） |
| E2 | `_liveStart` 与 `_liveRow` 的分工写死：`_liveRow` 只由 `_folds.rowOf`/`_contentCount` 派生、`_liveStart` 只由 feed 扫描派生，两者不互推 | §2.4 表；代码复核两者不互推；V4（`_LiveItem.live` 仍只由 `_liveRow` 决定） |
| E3 | `Steadiness.onChange → setState` 与「每增量外壳 0」的关系 + A1 口径裁定 | §2.5；A1 六类外壳逐帧 0；新用例 A4 恰 1 帧 |
| E4 | 冲突②并集落点 | §2.6；`flutter analyze` 干净；两侧符号都在 |
| E5 | 合并后的验证清单（可执行） | §2.7；命令与期望读数逐条可跑 |
| E6 | 回滚点与提交边界 | §2.8；单 merge commit；`main` 仍 66133c97 |

不覆盖：不改代码（eng-coder 的活）· 不改需求档 · 不改 `docs/design/chat-streaming.md` 的既有节（只在末尾新增 §13 合并补记，见 §2.5）· 不改回上游行为 · 不扩到合并之外的清理（另记台账）。

### 2.2 先例与调查

- **最近先例（对齐，不偏离）**：B 批 `docs/design/chat-streaming.md` §3.1（快路径判据）、§3.2（`_LiveItem`）、§3.4（`StepFolds.extend`）、§6.1-A1（逐帧计数口径）、§12-3（A1 的 bubble 口径）。本批不改快路径与折叠增量，只把它们与上游新成员合成。
- **上游这一侧的先例**：`Steadiness`（`lib/chat/steadiness.dart:13-77`）及其调用点 `_rowAt`（`chat_history_view.dart:251-267`）、`_isExpanded`（`:730-736`）、`clear()`（`:1396`）、`dispose()`（`:707`）、`_LiveItem.live`（`:2489`）。
- **调查（实读）**：`lib/chat/steadiness.dart`；`lib/chat/step_folds.dart`（`isQuickStep:331-345`、`refreshTail:141-145`、`rowAt:304-323`、`rowOf:100-102`）；
  `lib/chat/widgets/chat_item_view.dart:282-285`（`defaultExpanded`）；`test/chat/chat_history_rebuild_test.dart:132-185,339-379`；
  B 批批次档 §5-4 读数；`lib/main.dart` 的两侧符号来源（`main.dart:40` 导入 `claude_core_setting.dart`、
  `claude_path_setting.dart:52,56`、`thincoder_locator.dart:12`）。
- **公开资料**：工作目录内无独立文档仓；`Steadiness` / `_refold` 都是本仓代码，无外部 API / 版本问题需查 ⇒ **查过，无关**。

### 2.3 ① 冲突①的合成：`_refold`

**现状（实读）**：冲突块 `lib/chat/chat_history_view.dart:135-230`（96 行）。本地边 `:136-200` = `_refold({grow})` /
`_watchTail` / `_tailNow`（8 字段记录）/ `_tailGrew` / `_liveRow`；上游边 `:202-229` = `_refold()`（全量 `StepFolds.of`
之后再算 `_liveStart`）+ `int? _liveStart` + `late final Steadiness _steady`。
块外已合成、**不再动**：`_liveTick`（`:121`）、`_LiveItem`（`:3200-3248`）、快路径分支（`:1377-1385`）、
`_steady.clear()`（`:1396`）、`_isLive`（`:232`）、`shows` 的两个调用方法（`_rowAt` 的 `:261`/`:264`、`_isExpanded` 的 `:735`）、
`_steady.dispose()`（`:707`）、`_liveTick.dispose()`（`:722`）。

**合成规则（一句话）**：折叠走哪条分支与 `_liveStart` 无关 ⇒ 先按 `grow` 选分支（本地语义原样），再**无条件**跑上游的 `_liveStart` 重算，`extend` 分支也跑。

```dart
  /// Folds the history again: [grow] reads the last turn only (see
  /// [StepFolds.extend]); a full read otherwise. Either way, where the turn
  /// under way starts is read from the feed: a feed fact, not a fold's.
  void _refold({bool grow = false}) {
    final count = _feed.itemCount;
    if (grow && count >= _folds.count) {
      _folds.extend(count, _feed.itemAt, live: _feed.isStreaming);
    } else {
      _folds = StepFolds.of(count, _feed.itemAt, live: _feed.isStreaming);
    }
    _liveStart = null;
    if (!_feed.isStreaming) return;
    for (var index = count - 1; index >= 0; index--) {
      if (_feed.itemAt(index) case UserMessageItem(queued: false)) {
        _liveStart = index + 1;
        break;
      }
    }
  }

  /// Where the turn under way's items start; null when none is.
  int? _liveStart;

  /// What shows of the turn under way only while it lasts, steadied: a
  /// closed run's step under way, a thought open as it streams. What is
  /// done in a blink never shows, rather than flash; what showed stays a
  /// moment before it folds away.
  late final Steadiness _steady = Steadiness(
    onChange: () {
      if (mounted) setState(() {});
    },
  );
```

**块内成员顺序（行序）**：`_refold`（上面这版）→ `_watchTail` → `_tailNow` → `_tailGrew` → `_liveRow` → `_liveStart` → `_steady`；块尾直接接既有的 `_isLive`（`:232`，零改动）。理由：本地四个助手 + `_liveRow` 是一组（快路径），`_liveStart` + `_steady` 是上游一组，`_isLive` 紧贴它们的消费者位置。

**为什么 `extend` 分支也必须重算**：`extend` 之后 feed 可能已经长出新回合的第一条（`grow` 分支正是在条数增加或 live 位翻转时走），上一轮留下的 `_liveStart` 会指到旧回合 ⇒ `_isLive` 把新回合的条目不认作 live，`_steady` 不生效、`_replyStart()` 滚到错误位置。只在全量分支算 = 错。

**为什么快路径下 `_liveStart` 不必重算**：判据 `_tailGrew()`（`:181-196`）钉住了 `itemCount`、`isStreaming`、
`isUnprompted`、`editing`、`prepended`、尾下标、尾类型，只允许尾条文本变长（witness 八项与 `chat-streaming.md:76-84` 一致，`isUnprompted` 在 `:79`）。`_liveStart` 是（`itemCount`、`isStreaming`、
最后一条非排队 `UserMessageItem` 的下标）的函数；三者都不变（尾条类型不变 ⇒ 没有条目变成 / 不再是非排队提示词；
其余条目未动）⇒ 值不变。同理 `_liveRow`：`refreshTail`（`step_folds.dart:141-145`）只换 `_items[index]`
并丢合并文本缓存，不动 `_thoughtOf` ⇒ `rowOf(尾)` 不变。

**接口契约**：`_refold({bool grow = false})` 签名不变，两处无参调用（`:606`、`:644`）保持；`grow: true` 的调用点 =
全路径会话通知里的 `:1402`（`_refold(grow: moved == 0 && grew)`），`extend` 分支由它可达（条数增长或回合起止）。
`didUpdateWidget` 换 feed 仍走全量（`grow` 默认 false）；`_liveStart` / `_steady` / `_liveRow` 全为私有；
`_LiveItem`、`StepFolds`、`ChatSession`、transcript 零改动；无公开 API / 数据模型变化。

### 2.4 ② `_liveStart` 与 `_liveRow` 的分工

| 概念 | 坐标空间 | 数据源 | 消费者 | 更新时机 |
|---|---|---|---|---|
| `_liveStart` | **条目下标**（feed 坐标） | 从 `count-1` 反向找最后一条 `UserMessageItem(queued: false)`，取 +1 | `_isLive`（`:232`）→ `_rowAt` 的稳态门（`:254`）与 `_isExpanded` 的稳态门（`:734`）；`_replyStart()`（`:1351`）取它 −1 当提示词下标 | 每次 `_refold`（全路径），含 `extend` 分支 |
| `_liveRow` | **行下标**（折叠坐标） | `_feed.isStreaming ? _folds.rowOf(_contentCount - 1) : -1`（`:200`） | `_LiveItem.live`（`:2489`）——只决定哪一行听 `_liveTick` | 每次 build 现算（getter） |

**分工写死**：`_liveStart` 答「哪些条目属于本回合」（稳态门 + 回复开头滚动）；`_liveRow` 答「哪一行在显示流式文本」（增量重建）。**不互推**：用 `_liveStart` 推不出 `_liveRow`（思绪连跑时尾巴的 row = 连跑首行，不等于尾巴下标）；用 `_liveRow` 推不出 `_isLive`（行坐标答不了条目归属）。二者不共享中间量、不互相赋值——各自从各自的数据源派生。

**两处易错点（写死，落代码时照此）**：① `_liveRow` 用 `_contentCount`（`：439-444`，排除末尾 `LiveStatusItem`），`_liveStart` 用 `itemCount`（含状态行）——两个口径不同是**故意的**：前者要落在显示文字的行上，后者要覆盖整个回合。② `_liveRow` 只在 `_folds` 与 feed 同长时有意义；`_refold` 两条分支与 `refreshTail` 共同保证这一点，任何绕过它们直接改 feed 的写法都不许。

### 2.5 ③ `Steadiness.onChange → setState` 与「每增量外壳 0」

**事实（实读）**：
- `shows` 只在 build 路径上被问，两个方法：`_rowAt`（`:254-266`）与 `_isExpanded`（`:730-736`）。快路径重建的那一行也会问——`_buildItem` 内部调 `_rowAt`（`:2029`）与 `_isExpanded`（`:2043`）⇒ **稳态机制没有被快路径绕过**（这是对的：行「该不该显示」的变化不因快路径而停摆）。
- `_plainTextOf`（`:332`/`:340`）与 `_minimapRow`（`:2151`）也会问，但只经 `_rowAt` / `_isExpanded` 进 `_steady`，不新增入口：
  `_rowAt` 的稳态门是 `_isLive && isQuickStep(item)`（`:254`），`_isExpanded` 的门是 `item is ThinkingItem`（`:734`）。
  A1 回放的唯一条目是 `AssistantTextItem` ⇒ 两道门都在 `_steady.shows` 之前返回 ⇒ 这两个调用点**不建条目、不起计时器**（A1 变红时一并按此排查）。
- 计时器（`delay` 300ms / `hold` 700ms，`steadiness.dart:16-17`）在两帧之间到点；成熟回调走 `onChange` → `if (mounted) setState(() {})`（`:225-229`）。
- 视图 `setState` 就是外壳重建：`ChatFindRow` / `SuperListView` / `SelectionArea` / `ChatColumn` / `ChatImages` / `ScrollbarTheme` 都在那一帧重建。
- 快路径（`:1377-1385`）只做 `_folds.refreshTail` + `_liveTick.value++` 后 `return`，不 `setState`。

**裁定（两句，不许含糊）**：
1. **它不属于增量路径**：触发者是计时器（「某个折叠行该不该显示」的时间判定），不是文字增量；增量本身不 `setState`。
2. **但它会让 A1 变红**——只要 tick 落在被计数的那一帧：A1 数的是逐帧重建，tick 的 `setState` 在同一帧重建外壳 ⇒ 该帧六类计数非 0。「不属增量路径」不等于「A1 看不见它」。

**A1 口径（不变，写死）**：bubble 消息样式 + 每段 `notifyListeners()` + `pump(8ms)`，无额外 settle 帧；回放 feed
的本回合只有一条 `AssistantTextItem`（`test/chat/chat_history_rebuild_test.dart:140-145`）。在这个 feed 上：
`isQuickStep(AssistantTextItem)` 为假（`step_folds.dart:331-345`）⇒ `_rowAt` 在 `:254` 提前返回；
`_isExpanded` 只在 `ThinkingItem` 上问（`:734`）⇒ 回放里 `_steady` 一条也不建、一个计时器也不起
⇒ 六类外壳必须**严格 0**。**本合并不改这个口径，也不引入新读数**；B 批的改后读数（B 批批次档 §5-4）仍是本批的对照值。**归属**：本节的两个新成员（`_liveStart`、`Steadiness`）与 A1/A4 口径已补记到 `docs/design/chat-streaming.md` §13；此后以该节为准。

**机检区分办法（新用例 A4）**——落在 `test/chat/chat_history_rebuild_test.dart`，**不动**上游的 `steadiness_test.dart`：
- 场景：一条非排队 `UserMessageItem`（`_liveStart` 才非空、`_isLive` 才为真）+ 一条 streaming 思绪
  `ThinkingItem(text: 'Hm. ', tokens: 1)`（省略 `seconds` ⇒ `streaming` 为真，`chat_models.dart:157`；`defaultExpanded` 为真，`chat_item_view.dart:282-285`）。
  **消息样式写死 bubble**，与 A1 同置：sticky 下布局引起的粘顶重算会在第 72 个增量多一帧外壳重建（`chat-streaming.md:268`），A4-① 的「== 1」就不成立。
- 步骤：`pumpWidget(...)` → `await tester.pump()`（**不**用 `pumpAndSettle`：它按 100ms 步进，会越过 300ms 把 tick 吃掉）
  → 120 ×（**每帧把尾条 `ThinkingItem` 的文本追加固定 8 字**（换新实例、`seconds` 仍省略，与 A1 每段同构）
  → `notifyListeners()` → `pump(8ms)`），逐帧计数（沿用现有的 `_rebuiltType` / `debugOnRebuildDirtyWidget` 钩子）
  → 末尾 `pumpWidget(const SizedBox())` 卸载，让 `_steady.dispose()`（`:707`）取消未决计时器。
- 判据：**A4-①** 六类外壳「非 0 的帧数」== 1；**A4-②** 该帧下标 ∈ [36, 39]（8ms×38 = 304ms，容许 ±1 帧）；**A4-③** 其余帧六类 == 0 且 `ChatItemView` == 1，成熟帧 `ChatItemView` ≥ 1。
- 为什么能区分：若「增量路径」本身在重建外壳，非 0 帧会每帧都是（改前读数每增量外壳 27–31 行，B 批 §5-4）；若只有稳态 tick，就恰好一帧。**A1 全 0 + A4 恰 1 帧**两条合起来，才证明「外壳 0」是增量路径的属性，而不是统计没看见 tick。

**A1 变红时的处置（写死）**：**不放宽 A1**（把 0 改成 ≤1 等于删判据）。先查回放 feed 是否被改出 live 快步骤 / streaming 思绪；不是这个原因，就是快路径被绕开（`_tailGrew` 失守，或 `_refold` 被放回快路径），按缺陷报，不改读数。

**A2**：不受影响——两跑 feed 形状相同、`_steady` 都零条目，逐增量计数仍应逐项相等。

### 2.6 ④ 冲突②的并集落点

`lib/main.dart:179-193`（15 行，含 3 行标记）→ 12 行，两块的注释随各自的块保留：

```dart
    // Settings → General → Claude Code: the core sessions run on (BaoCode's
    // own, or the CLI), read as each agent starts. Unset, the CLI where it
    // is installed: looked for on the app's PATH, then the shell's.
    ClaudeCore.cliInstalled = localClaudeInstalled;
    unawaited(lookForLocalClaude());
    ClaudeCore.current = () =>
        ClaudeCore.parse(files.settings[ClaudeCore.settingKey]);
    // Settings → General → thincoder: the build to run, read as each agent
    // starts.
    ThincoderPathSetting.current = () => ThincoderPathSetting.parse(
      files.settings[ThincoderPathSetting.settingKey],
    );
```

**顺序与理由**：上游块在前——它直接接着上一行 `ClaudePathSetting`（`:177-178`，同一设置页「Claude Code：跑哪个 build」）；
本地块在后。**无依赖**：`ClaudeCore.current` / `ThincoderPathSetting.current` 都是给懒读闭包赋值；
唯一立即执行的是 `lookForLocalClaude()`（fire-and-forget，`claude_path_setting.dart:56`），`localClaudeInstalled`
是 tear-off（`:52`），顺序不影响结果。符号都在：`main.dart:40` 引 `claude_core_setting.dart`，`:51` 引
`thincoder_locator.dart`（`ThincoderPathSetting` 定义在 `thincoder_locator.dart:12`）。

### 2.7 ⑤ 合并后的验证清单

```bat
flutter analyze
flutter analyze lib/chat/chat_history_view.dart lib/main.dart test/chat/chat_history_rebuild_test.dart
flutter test test/chat/
flutter test test/chat/chat_history_rebuild_test.dart
flutter test test/chat/step_folds_test.dart
flutter test test/markdown_test.dart
flutter test test/sticky_message_test.dart test/selection_scroll_test.dart
flutter test test/chat/steadiness_test.dart test/chat/turn_footer_test.dart test/chat/item_appear_test.dart test/chat/live_selectable_text_test.dart test/chat/musing_cue_test.dart test/chat/history_scroll_test.dart test/chat/fold_view_test.dart
findstr /c:"<<<<<<<" lib\chat\chat_history_view.dart lib\main.dart
```

| # | 检查 | 期望读数 |
|---|---|---|
| V1 | `flutter analyze`（三个文件） | `No issues found` |
| V2 | 冲突标记 | 无输出（`findstr` 退出码 1） |
| V3 | `test/chat/` 全量 | 全绿（含上游七档与 B 批两档） |
| V4 | A1（F1-20 / F1-200） | 每次增量 `findRow`/`superList`/`selection`/`column`/`images`/`scrollbar` **0**、`item` **1**、`markdown` 0..1；`reads` 960（8/增量）、`readAll` 0、`dataOk=true`、`terminal=true`；`images 1645/0`（20）、`16405/0`（200）、`same=true` |
| V5 | A2 / B1① | `equal=true`、`readsEqual=true` |
| V6 | C1 / C2 / C3 | `parses=30`（≥5、≤34）、`terminal=true`、无 pending timer |
| V7 | A4（新） | 非 0 外壳帧数 1、下标 37（允许 36–39）、其余帧 0 |
| V8 | `test/markdown_test.dart` | 其余绿；3 条 Windows 路径分隔符红项（`/p/lib/a.dart` vs `\p\lib\a.dart`）与合并前**同一批** |
| V9 | `test/chat/step_folds_test.dart` | 全绿（`extend` 与 `of` 对拍不受合并影响） |
| V10 | `flutter analyze`（全仓） | `No issues found`（编译器面覆盖 179 个上游文件） |
| V11 | `test/sticky_message_test.dart` + `test/selection_scroll_test.dart` | 全绿（粘顶重算 / 选择区与新增稳态 `setState` 的邻接面） |

**V4 的 `reads` 口径**：来源 = B 批批次档 §5-4 的 A1 回放实测。A1 回放的增量 = 尾条 `AssistantTextItem` 变长 ⇒ 走快路径（witness + `refreshTail` + 重建行的 `itemAt`，合计 8 读/增量），**不含 `extend`**；`extend` 只出现在全路径增量（条数增长或回合起止，调用点 `:1402`），其重读代价不在 V4 的读数里。

**既有测试通过面（七个文件，零改动，同 `chat-streaming.md:279-280`）**：`test/chat/chat_history_rebuild_test.dart` ·
`test/chat/history_scroll_test.dart` · `test/chat/fold_view_test.dart` · `test/chat/step_folds_test.dart` ·
`test/sticky_message_test.dart` · `test/selection_scroll_test.dart` · `test/markdown_test.dart`（后三个在 `test/` 根下）。

不跑全量 `flutter test`：本批作者化的只有两个产品文件 + 既有测试文件里的 A4 用例，其余 179 个属上游原样；上游自身的全量绿不是本次合并的验收面，编译面由 V1（三个文件）与 V10（全仓）覆盖。

### 2.8 ⑥ 回滚点与提交边界

- **回滚**：合并未提交前 ⇒ `git merge --abort`（回到合并前，工作树干净）；已提交后 ⇒ 丢弃分支 `git branch -D merge/upstream-1.3.0`。两种情况 `main` 都仍是 **66133c97**，未受影响。
- **提交边界**：**一个 merge commit**（在 `merge/upstream-1.3.0` 上），内容 = ① 两处冲突解 + ② A4 用例。不拆成「先解冲突、再补用例」两个提交——合并的可验证性属于合并本身。不 amend 出第二个提交。
- **不进这个提交**：`pubspec.lock`（未暂存改动只是 hosted 镜像 URL `pub.flutter-io.cn` → `pub.dev` 的翻转，与上游依赖无关；`bao_agent` 这类 workspace 包本就不进 lock——`HEAD:pubspec.lock` 里同样没有 `bao_editor`）、`docs/requirements/thincoder-adapter.md`（未暂存，与本合并无关）、9 个未跟踪文档（本批次档 / 设计档 / `PROJECT-MANIFEST.json` 等）。
- `pubspec.yaml` 的上游改动（version 1.3.0+13、新增 `packages/bao_agent`）已随合并暂存，保持原样。

### 2.9 受影响文件清单

| # | 文件 | 现状行数 | 预期 | 说明 |
|---|---|---|---|---|
| ① | `lib/chat/chat_history_view.dart` | 3683（含冲突标记） | ≈3675（−8） | 冲突块 96 行 → 合成 88 行。**档位结论**：3683 行 > 800 行硬档，依既有 E 批 #47 拆档预案（`chat-streaming.md` §4）；本批不动行结构（只合成冲突块）、行数不增 ⇒ 不触发拆分 |
| ② | `lib/main.dart` | 787 | 784（−3） | 冲突 15 行 → 并集 12 行。**档位结论**：787 → 784（净 −3）、无结构变化 ⇒ 不触发拆分（>500 行主动拆分审阅档） |
| ③ | `test/chat/chat_history_rebuild_test.dart` | 433 | ≈473（+40） | A4 用例 |
| — | 其他 | — | 零改动 | B 批三档测试 + 上游七个测试文件（均在 `test/chat/`：`steadiness` · `turn_footer` · `item_appear` · `live_selectable_text` · `musing_cue` · `history_scroll` · `fold_view`）不改。与 `chat-streaming.md:279-280` 的七个必须全绿文件不是同一张清单，后者另含 `sticky_message` · `selection_scroll` · `markdown`（见 §2.7） |

行数为编制日实测（node 逐文件计行）；实施后实测值由 §5 记。

### 2.10 关键决策

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | `_liveStart` 与 `_liveRow` **并存，各喂各的消费者** | 两个坐标系、两个问题（条目归属 ∥ 显示行）。被否：用 `_liveStart` 推 `_liveRow`（思绪连跑时会把行算成尾巴下标，增量落到被合并隐藏的行上）；被否：用 `_liveRow` 推 `_isLive`（行坐标答不了条目归属） |
| D2 | `_refold` = 两个折叠分支**之后**无条件重算 `_liveStart` | `_liveStart` 是 feed 层事实，与折叠走哪条无关；`extend` 后 feed 可能已长出新回合。被否：只在全量分支算（`extend` 会留下上一轮的起点）；被否：快路径也算（判据已保证不变，白付 O(本回合)） |
| D3 | `_steady` **原样保留** `onChange → setState`，不改造 | 上游已发布，行为以它为准；改造属改上游语义且无收益（A1 的测量面本来就不含稳态）。被否：把 `onChange` 换成 `_liveTick++`（成熟时行结构要变，不是「只换一个字」）；被否：给 A1 放宽容忍（0 → ≤1 等于删判据） |
| D4 | A1 口径**不变**；另立 **A4** 专测稳态 tick | 一个读数只证一件事：A1 证「增量帧外壳 0」，A4 证「tick 恰一帧」。合起来才可区分；被否：把两者并成一条带容忍的读数（两项都失去机检意义） |
| D5 | 冲突② = **并集**，上游块在前、本地块在后 | 同页分组；两侧无依赖（懒读闭包 + fire-and-forget）。被否：只取一侧（任一侧都是功能丢失） |
| D6 | **一个 merge commit**，A4 用例同提交 | 合并的可验证性属于合并；拆两个提交会让「合并已提交」早于「合并已验证」 |

### 2.11 验收对照

| 条目 | 落点 | 机检（命令 / 读数见 §2.7） |
|---|---|---|
| E1 | §2.3 | V1、V2、V4、V5、V9 |
| E2 | §2.4 | 代码复核（两者不互推：`_liveRow` 只由 `_folds.rowOf`/`_contentCount` 派生、`_liveStart` 只由 feed 扫描派生）+ V4（`_LiveItem.live` 仍只由 `_liveRow` 决定） |
| E3 | §2.5 | V4（六类 0）与 V7（恰 1 帧）同时成立 |
| E4 | §2.6 | V1 + V2 |
| E5 | §2.7 | 命令可跑、读数可核 |
| E6 | §2.8 | `git log --oneline` 该分支只多一个 merge commit；`git rev-parse main` == 66133c97 |

### 2.12 用例表

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 文字增量（正常） | live 尾巴 `AssistantTextItem` 变长，notify + `pump(8ms)` | 快路径：外壳 0、`ChatItemView` 恰 1、文本更新；`_liveStart` 不重算 |
| T2 | 思绪增量（边界） | live 尾巴 `ThinkingItem(seconds: null)` 变长 | 快路径；重建连跑首行；`_isExpanded` 300ms 成熟 ⇒ 外壳恰 1 帧（A4） |
| T3 | 回合起止（边界） | `isStreaming` false→true / true→false | 全路径：`_refold` + `_liveStart` 重算；`_steady.clear()`（`:1396`） |
| T4 | 尾部新增条目（正常） | 条数 +1（新工具卡等） | 全路径；`extend` 只重算最后一回合 + `_liveStart` 重算 |
| T5 | 末尾状态行（边界） | 末条 `LiveStatusItem` | `_liveRow` 落在内容条目（`_contentCount` 排除状态行）；`_liveStart` 仍覆盖整回合 |
| T6 | 前置历史（边界） | `HistoryPrepended`，下标整体右移 | 全路径 + `_shiftIndexes` + `_liveStart` 重算；快路径不成立 |
| T7 | 无提示词的自主回合（边界） | 没有 `UserMessageItem(queued: false)` | `_liveStart` 为 null ⇒ `_isLive` 全假、稳态不参与；`_LiveItem` 仍按 `_liveRow` 重建 |
| T8 | 换会话（边界） | `didUpdateWidget` 换 feed | 全量 `_refold` + `_liveStart` 重算；`live` 跟随新 `_liveRow` |
| T9 | 编辑中（边界） | `editing != null` | 判据失败 ⇒ 全路径；`_liveStart` 重算 |
| T10 | 稳态 tick 与增量同帧（区分面） | 见 A4 | 120 帧里恰 1 帧外壳非 0，其余 0 |

### 2.13 边界（本批不做）

- 不改代码（eng-coder 的活）；不改需求档；不改 `docs/design/chat-streaming.md` 的既有节——只在末尾新增 §13（合并补记，见 §2.5），既有语义零改动。
- 不把上游行为改回本地版本：`_steady` 的 300 / 700ms 节奏、`onChange → setState`、`_liveStart` 的扫描写法全按上游。上游**没有**做增量渲染（`_refold` 仍是全量 `StepFolds.of`）⇒ 我们的快路径与 `extend` 仍是价值面，不是重复实现。
- 不扩到合并之外的清理：`didUpdateWidget` 换 feed 不清稳态、`_liveStart` 在无提示词回合退化为全表扫——只报告（§2.14），不动手。
- 不做真机走查：合并无视觉 / 交互改动；B 批 W1 走查仍挂台账。
- 无 `open` 项：本批没有未定的交互决策（视觉与交互两侧都按各自的现存实现保留）。

### 2.14 发现（报告，不自行修）

1. **`didUpdateWidget` 换 feed 不清稳态**（`chat_history_view.dart:629-649`，其中无 `_steady.clear()`）：旧会话的稳态条目会带进新会话，最长 700ms 内可能让某行多显示一会儿，未决的成熟计时器还会在新会话上触发一次 `setState`。上游行为，本批不改；建议主 agent 记一行台账（归批 / 条件）。
2. **`_liveStart` 的反向扫描在自主回合退化为 O(历史)**（上游写法，`:210-215`）：没有非排队提示词时（后台任务报告这类）每次全路径扫全表；正常回合只扫本回合。上游行为，本批不改。
3. **工作树里的合并外改动**：`pubspec.lock` 未暂存改动仅是镜像 URL 翻转；`docs/requirements/thincoder-adapter.md` 未暂存；9 个未跟踪文档。三者都不属本合并 ⇒ 不进 merge commit（§2.8）。
4. **`test/markdown_test.dart` 的 3 条 Windows 路径分隔符红项**是既有项（B 批已记），本合并不改该文件；V8 只要求「红项是同一批」。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（第 1 轮）

评审对象：合并方案（批次档 §2：`docs/batches/2026-10-18-upstream-merge-1.3.0.md`）· 参照档 `docs/design/chat-streaming.md`。评审范围仅这两份文档；文档内引用的代码行号与既有读数（B 批 §5-4）不在评审范围，未核（unverified）。无 AGENTS.md / 无文档地图 / 未声明项目规范档 ⇒ 方法与文档归属按本次评审条款判，已声明该限制。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|------|--------|------|------|
| 1 | 验收标准 | 🟡 | A4 用例未写消息样式。该测试文件全局默认 sticky（`docs/design/chat-streaming.md:268` 记「测试全局默认 sticky」，且同节记 sticky 下第 72 个增量会额外 `setState` 重建外壳 29 行）⇒ 按默认样式实现，A4-①「非 0 外壳帧数 == 1」与 A4-③「其余帧六类 == 0」不成立。 | 在 A4 场景里写死 bubble 消息样式（与 A1 口径同置），或按 sticky 的第 72 帧另立期望值。 |
| 2 | 清晰度 | 🟡 | A4 步骤只写「120 ×（`notifyListeners()` + `pump(8ms)`），逐帧计数」，未写每帧要追加尾条文本。按字面实现，判据（尾条文本变长）不成立 ⇒ 120 帧全走全路径，V7 不可达。 | 在 A4 步骤里写出增量形态（每段追加固定字数的 `ThinkingItem` 文本），与 A1 回放的「每段」同构。 |
| 3 | 验收标准 | 🟡 | §2.5 的「回放里 `_steady` 一条也不建」只排除了 `_rowAt` 与 `_isExpanded` 两个调用点，而同节自述「另外 `_plainTextOf`（`:332`）与 `_minimapRow`（`:2151`）也会问」（批次档 `:136`）；A1「六类外壳必须严格 0」的前提未闭合，且同节「A1 变红时的处置」会把这一成因误判为快路径被绕开。 | 补一句这两个调用点在 A1 回放 feed（单条 `AssistantTextItem`、bubble 样式）里为何不建 `_steady` 条目（或其不可达理由）；若不能排除，把它们写进 A1 变红时的排查顺序。 |
| 4 | 需求覆盖 | 🟡 | 验证清单（§2.7）跑 `test/chat/` 全量 + `test/markdown_test.dart`，未含 `test/sticky_message_test.dart` · `test/selection_scroll_test.dart`；而既有设计档把它们列入「必须全绿，零改动」（`chat-streaming.md:279-280`），二者正是粘顶重算 / 选择区与新增稳态 `setState` 的邻接面。§2.9 又写「B 批三档测试与上游七个测试文件不改」，与这七个文件的集合是否同一批未交代。 | 在 §2.7 补这两条测试命令（或把「七个测试文件」逐一列名并对照 `chat-streaming.md:279-280`）。 |
| 5 | 文档归属 | 🟡 | 合并带入的两个新成员（`_liveStart`、`Steadiness`）与 A1/A4 口径裁定只落在批次档，而归属该机制的规范面 `docs/design/chat-streaming.md` 被声明冻结（批次档 `:52`「不改 `docs/design/chat-streaming.md`（B 批已收口冻结）」）；该档 §6.1-A1 正是 A1 口径的归属节（`chat-streaming.md:267`）⇒ 规范面将缺这两个成员、稳态对 A1 的影响与 A4 区分用例，后续批次引 §3.1/§6.1 时看不到。 | 在归属档补一节（或 §12 式实施偏差/合并补记）记 `_liveStart` 与 `_liveRow` 的分工、稳态 tick 可致一帧外壳重建、A4 为区分用例；若仍不补，在 §2 写明口径与成员此后以哪份文档为准。 |
| 6 | 受影响文件体量标注 | 🟡 | 受影响文件表给了行数与增量，但没有档位结论：`lib/main.dart` 787 行（`787 | 784（−3）`）落在 >500 主动拆分审阅档，表内无档位/拆分结论；`chat_history_view.dart` 3683 行（>800 硬档）以引用既有 E 批预案「沿用 B 批裁定（`chat-streaming.md` §4 拆档预案，E 批 #47）」交代。 | 在 §2.9 表内补档位结论：main.dart 净 −3、无结构变化、不触发拆分；chat_history_view.dart 依既有 E 批预案、本批不动结构不触发（引用既有裁定，不另立拆分）。 |
| 7 | 验收标准 | 🟡 | E2 写「`_liveStart` 与 `_liveRow` 的分工写死，各有唯一消费者」（批次档 `:46`），但 §2.4 表同一行又给 `_liveStart` 列了两个消费者：`_isLive` 与「`_replyStart()`（`:1351`）取它 −1 当提示词下标」（批次档 `:126`）⇒ 该条目的机检判据「代码复核」按字面不可判。 | 把 E2 判据改成可判的形态（如「`_liveStart` 与 `_liveRow` 不互相派生：`_liveRow` 只由 `_folds.rowOf/_contentCount` 派生、`_liveStart` 只由 feed 扫描派生」），并去掉「唯一消费者」的措辞。 |
| 8 | 清晰度 | 🔵 | §2.3 复述快路径判据时列举的字段不含 `isUnprompted`（批次档 `:114` 钉住「`itemCount`、`isStreaming`、`editing`、`prepended`、尾下标、尾类型」），而归属档的 witness 八项里有 `isUnprompted == seen.unprompted`（`chat-streaming.md:80`）。结论不受影响（多钉一项只加强），但两处枚举不一致。 | 枚举与 `chat-streaming.md:73-85` 对齐，或注一句「witness 共八项，此处只列与 `_liveStart` 相关的七项」。 |
| 9 | 清晰度 | 🔵 | §2.3 只写「两处无参调用（`:606`、`:644`）保持」（批次档 `:120`），未指出哪个调用点传 `grow: true`；`extend` 分支的可达性只能从 T4/T5 的期望反推。 | 点名传 `grow: true` 的调用点（块外已合成的那处），使 E1 的 `extend` 分支可达性可核。 |
| 10 | 方法合规/文档状态 | 🔵 | §2.14-1 称「§1 仍是模板占位」（批次档 `:277`），但本档 `:8-36` 已有「讨论与定界」全文（来源、两处冲突、关键判断、范围外）⇒ 该发现已过期，可能引出对 §1 的重复补写。 | 更新或删去该条（§1 已有内容，只需在 §1 状态行与本批结束状态对齐）。 |
| 11 | 清晰度 | 🔵 | V4 写「`reads` 960（8/增量）」（批次档 `:203`），而归属档把「8 读/增量」归于 `extend` 的重读（`chat-streaming.md:370`「每增量重读最后一回合，实测 8 读/增量」）；A1 回放若全为文字尾巴增量则走快路径（`refreshTail` 一读）。该读数出自 B 批 §5-4，不在本次评审范围（unverified）。 | 给 V4 的每增量读数列出来源与口径（哪些增量走 `extend`、哪些走快路径），避免与 A1 的增量形态混用。 |
| 12 | 验收标准 | 🔵 | V1 只 analyze 两个 lib 文件 + 一个测试文件；本合并把 179 个上游文件带入树，§2.7 明确「不跑全量 `flutter test`」（批次档 `:210`），但未设全量 `flutter analyze` 作编译门。 | 考虑把全量 `flutter analyze` 加入 V 清单（一条命令，覆盖上游文件的编译面）。 |
| 13 | 文档卫生 | 🔵 | 批次档 `:70` 写「`shows` 的两处调用（`:261`、`:264`、`:735`）」——「两处」与三个坐标不一致（§2.5 计为两处方法三个调用点）；另 §2 的模板占位行仍留在 `:39`。 | 统一计数口径（两处方法 / 三个调用点），并删去已填满的模板占位行。 |

计数：🔴 0 · 🟡 7 · 🔵 6（共 13 条）

VERDICT: pass

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
**状态行**：实施完成 2026-10-18（两处冲突已解并 git add、A4 已落；V1–V11 已跑，V3/V4/V10 有已归因偏差（详见 5.5）；审计 clean、评审 pass、fix 0 轮）



### 5.1 落点（三个文件）

| # | 文件 | 内容 | 行数 |
|---|---|---|---|
| ① | `lib/chat/chat_history_view.dart` | 冲突块 135-230（96 行）→ 合成块 135-223（89 行）：`_refold` 保留 `grow`/`extend` 分支，其后**无条件**重算 `_liveStart`（`extend` 分支也跑）；块内顺序 `_refold` → `_watchTail` → `_tailNow` → `_tailGrew` → `_liveRow` → `_liveStart` → `_steady`；块外零编辑（块下全部坐标均匀 −7） | 3683 → 3676 |
| ② | `lib/main.dart` | 冲突块 179-193（15 行，含 3 行标记）→ §2.6 并集 12 行：`ClaudeCore` 块在前、`ThincoderPathSetting` 块在后 | 787 → 784 |
| ③ | `test/chat/chat_history_rebuild_test.dart` | A4 用例 425-497（73 行）：bubble 样式；1 条非排队 `UserMessageItem` + 1 条 `seconds` 省略的 `ThinkingItem`；`pumpWidget` → `pump()` → 120 ×（尾条追加 8 字 → `notifyListeners()` → `pump(8ms)`）逐帧计六类外壳与 `item`；判据 = 非 0 帧恰 1、下标 ∈ [36,39]、其余帧六类 0 且 `item == 1`、成熟帧 `item ≥ 1`；末尾 `pumpWidget(const SizedBox())` 卸载 | 433 → 508 |

- 已 `git add` 上述三档（含 A4 所在测试档，按 §2.8「一个 merge commit = 两处冲突解 + A4」）；未做 `git merge --abort`、未提交。
- 未动：`docs/**`（`docs/design/chat-streaming.md` §13 为实施前已有，未编辑）、`pubspec.lock`（跑 flutter 未改写，仍是既有 104 处镜像 URL 翻转）、`docs/requirements/thincoder-adapter.md`、9 个未跟踪文档。

### 5.2 决策透明

| # | 决策 | 依据 / 理由 |
|---|---|---|
| 1 | 合成块照抄 §2.3（含 `_refold` 的 doc 注释），不自行改写 | 方案把伪代码定死；逐行可对拍，审计与评审均核过 |
| 2 | `_liveStart` 重算放在两条折叠分支之后、无条件执行，`extend` 分支也跑 | §2.3：`_liveStart` 是 feed 层事实，`extend` 后 feed 可能已长出新回合 |
| 3 | 块内成员顺序按 §2.3（本地四助手 → `_liveRow` → `_liveStart` → `_steady`） | 快路径一组在前、上游一组在后；`_isLive` 仍紧贴消费者 |
| 4 | A4 判据拆成三条独立断言（非 0 帧数 / 下标区间 / 其余帧六类 + item） | §2.5 A4-①②③；一个读数只证一件事，不合并、不放宽 |
| 5 | 不修 `test/chat/` 的 35 条红项、不修 V10 的 11 条 analyze 项 | 全在未改动的上游文件；任务书禁止改上游行为，且不在本批清单 |
| 6 | V4 的 `reads` 偏差不改代码 | 成因在上游自动合成面的 `_buildItem`（`_rowAt`/`_liveFooter` 各多 1 读/增量），不在冲突块；改它等于改上游行为 |

### 5.3 实施与评审轮次

- **内部偏差审计**（explore，只读，1 轮）：**clean** —— §2.3 合成块逐行对拍一致；块外零编辑（块下坐标均匀 −7 佐证）；§2.6 逐字一致；A4 无简化（无 `pumpAndSettle`、bubble 写死、末尾卸载、判据未放宽）；无清单外改动。
- **advisor 代码评审**（1 轮）：**pass** —— 🔴 0 · 🟡 2（V4 期望读数 960 与实测 1200 的文档滞后；§5/§6 记录空缺，本段即补）· 🔵 2（「找最后一条提示词」三份实现；测试档行数预估 ≈473 vs 实测 508）。无 must-fix。
- **fix round**：0 轮（无 🔴、无 must-fix）。**终态：clean**。

### 5.4 机检读数（V1–V11，本机 Windows）

| # | 命令 | 读数 |
|---|---|---|
| V1 | `flutter analyze lib/chat/chat_history_view.dart lib/main.dart test/chat/chat_history_rebuild_test.dart` | `No issues found!`（首次 107.5s；A4 定稿后复跑 6.7s） |
| V2 | `findstr` 冲突标记（两档） | 无输出（无 `<<<<<<<` / `=======` / `>>>>>>>`） |
| V3 | `flutter test test/chat/` | **+441 −35**：35 条红项，见 5.5-① |
| V4 | A1（F1-20 / F1-200） | 六类外壳 `0/0`；`item` 120（per=1）；`markdown` 18（per 0..1）；`reads=1200 per=10`；`readAll=0`；`dataOk=true`；`terminal=true`；`images=1645/0`（20 回合）、`16405/0`（200）；`same=true`。**`reads` 与方案的 960（8/增量）不符，见 5.5-②** |
| V5 | A2 / B1① | `A2 equal=true B1 readsEqual=true` |
| V6 | C1 / C2 / C3（`test/markdown_test.dart`） | `C1 parses=30 C2 terminal=true`；该档绿 ⇒ 无 pending timer |
| V7 | A4（新） | `shells=[…0, 7@37, 0…]`、`item=[…1, 2@37, 1…]`：非 0 帧恰 1、下标 37 ∈ [36,39]、其余帧六类 0 且 `item == 1`、成熟帧 `item = 2 ≥ 1` |
| V8 | `flutter test test/markdown_test.dart` | +20 −3：3 条与 B 批同一批（`/p/lib/a.dart` vs `\p\lib\a.dart` 等 Windows 分隔符），其余绿 |
| V9 | `flutter test test/chat/step_folds_test.dart` | +27 全绿 |
| V10 | `flutter analyze`（全仓） | **11 issues（7 info / 4 warning）**，见 5.5-③ |
| V11 | `flutter test test/sticky_message_test.dart test/selection_scroll_test.dart` | +4 全绿 |

### 5.5 偏差与未做

① **V3 未达「全绿」**：35 条红项分布在 10 个测试档（`code_citation` 3 · `composer_files` 4 · `content_image` 1 · `file_tags` 4 · `open_editor` 1 · `file_link` 1 · `file_open` 1 · `side_panel_search` 5 · `side_panel_workspace` 5 · `side_panel` 10）。这 10 档 `git status` 全为零改动；失败值清一色 Windows 路径分隔符（断言 `/p/lib/a.dart`，实际 `\p\lib\a.dart`），原型落在 `test/chat/code_citation_test.dart:97` ↔ `lib/chat/widgets/code_citation.dart:51`（`p.normalize`/`p.join` 用平台默认上下文，测试档与产品档均与 HEAD 无差异）⇒ **判为既有环境类红**（B 批已记同类：`test/markdown_test.dart` 3 条 `p.normalize` 既有红）。**未做**：本机未跑合并前全目录基线（B 批只跑过七个文件；跑基线需另建 HEAD worktree，本批边界内未做）⇒ 「与合并前同一批」在 `test/chat/` 全目录上为 **unverified**，只对 `markdown_test` 的 3 条成立（B 批已记）。如需严格基线，请另派一轮。

② **V4 的 `reads` 偏差**：实测 1200（10/增量），方案期望 960（8/增量）。成因 = 上游自动合成面：`lib/chat/chat_history_view.dart:2022` `final row = _rowAt(index);` 经 `_shownAt` 多 1 读；`:2024` `final footer = _turnFooter(index) ?? _liveFooter(index);` 的 `_liveFooter`（`:301`）再多 1 读。A1 的增量仍走快路径（快路径分支与 witness 未动）⇒ 每增量恒定 10、`readAll=0`。未改代码（禁止改上游行为）。

③ **V10 未达「No issues found」**：11 issues，全部在上游带入/未改动的文件：`lib/icons/site_icons.dart:2` · `lib/ide/debug_editor_glue.dart:196/:250/:329` · `lib/ide/ide_code_find.dart:113` · `test/chat/side_panel/file_preview_agent_test.dart:1` · `test/chat/side_panel/side_panel_search_test.dart:5/:9` · `test/composer_test.dart:1003` · `test/ide/workbench/ide_units_test.dart:365` · `test/remote/remote_project_test.dart:811`（仅最后一档被合并改动，其余与 HEAD 无差异）。本批三档在 V1 为 `No issues found`。未改（清单外且属上游）。

④ **行数预估偏离**：A4 用例 73 行，测试档 433 → 508（§2.9 预估 ≈473 / +40）；两产品档与预期一致（3676 vs ≈3675、784 = 784）。

⑤ **未做**：真机走查（合并无视觉/交互改动，方案已定不做）；未写 §6（父代理段）；未动台账（子代理无写权）；未另记 §2.14 两条上游行为的台账行（建议父代理记）。

## §6 验证与收口（父代理）

## 验证与收口（2026-10-18 · 父代理独立复跑）

### 冲突解决复核（我逐行读，不靠转述）

- 冲突① `chat_history_view.dart:135-223`：两侧成员全在（`_refold({grow})` → `_watchTail` → `_tailNow` → `_tailGrew` → `_liveRow` → `_liveStart` → `_steady`）；`_refold` 合成正确——`grow`/`extend` 分支在前、**无条件**重算 `_liveStart` 在后；块外零改动。
- 冲突② `main.dart:179-190`：`ClaudeCore`（含 `lookForLocalClaude()`）在前、`ThincoderPathSetting` 在后，12 行并集。
- 两档 `findstr` 无冲突标记。

### 读数（父代理实跑）

| 项 | 读数 |
|---|---|
| A1（20 / 200 回合） | 六类外壳 **0 / 0** · `ChatItemView` 每增量 **1** · `MarkdownBlocks` 18 · **`reads` 1200（10/增量）** · 两跑逐次相等 |
| A2 / B1① | `equal=true` · `readsEqual=true` |
| A4（新） | 外壳非 0 **恰 1 帧 @ 下标 37**（允许 36–39）· 该帧 `item=2` · 其余帧 0 / 1 |
| 两档 analyze | 全量 analyze 的 11 条问题**无一**落在本批三档（全在上游/未改动文件） |
| `test/chat/` 全量 | +441 / **35 红**，抽验 `code_citation_test:97` = `/p/lib/a.dart` vs `\p\lib\a.dart` ⇒ Windows 路径分隔符类，与本合并无关 |

### 三处偏差（如实记录）

1. **A1 的每增量读 8 → 10**：上游行构建（`_rowAt` / `_liveFooter`）各多一读，不在冲突块内、未改上游；判据「与历史长度无关」仍成立（20/200 逐次相等）。
2. **`test/chat/` 全目录基线未在合并前跑** ⇒「35 红与合并前同一批」在目录层面为 **unverified**；证据是失败值全为路径分隔符、且涉及测试档与产品档 `git status` 零改动。
3. **全量 analyze 11 条**（7 info / 4 warning）全在上游带入或未改动文件；本批三档干净。

### 提交边界

- 进 merge commit：两冲突档 + A4 所在测试档 + 本批次档 + `docs/design/chat-streaming.md`（§13 与两处事实更正）。
- 不进：`pubspec.lock`（镜像 URL 翻转）· `docs/requirements/thincoder-adapter.md` · 未跟踪文档。
- `main` 仍 `66133c97`，合并只落 `merge/upstream-1.3.0`。
