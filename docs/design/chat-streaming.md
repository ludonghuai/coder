# 对话流式渲染（chat-streaming）设计档

> 板块：对话渲染（chat-streaming）· 范围仓：baocode。
> 配对需求档：`docs/requirements/chat-streaming.md`（F1–F4 + N1）。
> 状态：设计稿 v4（v2 设计评审已过；§12 / §14-12 记实施偏差；§14 = #68 回合边界与折叠）· 2026-10-18 · 行号 = 各节标注时点的快照（实施按符号定位）。
> 前情：IDE 架构体检 E1（`docs/batches/2026-10-17-ide-health-audit.md` §1）。

---

## 1. 模块目标与范围

**一句话**：流式回复期间，每个文字增量只重建正在显示流式文本的那一行；外壳、历史行、折叠、图片收集、流式 markdown 的每增量成本不再随对话长度增长。

**本批交付**：F1 增量重建边界 · F2 折叠增量 + 图片集合缓存 · F3 流式 markdown 的解析上界 · N1 改前 / 改后同法读数。

**本批不做**：C 批（命令表 / 输入框 / 侧栏定时器，台账 #45）· E 批（结构拆分，台账 #47）· `packages/bao_editor` · 任何视觉 / 交互改动 · 数据模型与 `KernelEvent` 形态 · 新依赖 · 列表实现替换。

**体量纪律**：本批不动 `chat_history_view.dart` 的结构（不拆档）；新增逻辑落在三个既有文件，见 §4。

---

## 2. 做法与理由

### 2.1 今天的一帧

```text
KernelEvent → ChatSession._apply（chat_session.dart:158-168，一事件一次 notifyListeners）
  → 视图监听 _handleSessionChanged（chat_history_view.dart:1174）
      → _refold()：StepFolds.of 全量（:1185；step_folds.dart:65-167，O(条目总数)）
      → setState（:1214）
          → build（:2089）：_built = null（:2090）
          → _buildHistory（:2113）→ SuperListView.builder（:2214）
              → 对 cacheExtent 900（:2219）内的每个已建行跑 itemBuilder（:2229-2237）
              → 流式那条 markdown 整篇重解析（markdown_view.dart:83-98）
```

**图片集合不在每帧路径上**：`_images` 只作为 `ChatImages.all` 回调传入（`:2094-2095`），打开图库时按需调用一次（`content_image.dart:273`）；现状不是每帧 O(N)（§3.5、评审 #4）。

**关键事实（本批成立的前提）**：会话通知**不会**重建 `ChatHistoryView` 的父级——`chat_screen.dart:599-657` 把 `_buildBody()` 作为 `ListenableBuilder` 的 `child` 传入（`child` 不随 listenable 重建）。因此每增量的唯一入口就是视图自己的 `_handleSessionChanged`；F1 可以全部落在 `chat_history_view.dart` 内，不动 `chat_screen.dart`。

### 2.2 重建边界：把「一个增量」缩到一条

- 视图在 `_handleSessionChanged` 的最前面分类：**文字尾巴增量**（判据见 §3.1）→ `_folds.refreshTail(tail, _feed.itemAt(tail))` + `_liveTick.value++`，不 `setState`；其余 → 走今天那条全路径。
- 只有**实际渲染流式文本的那一行**的 `_buildItem(index)` 包在 `_LiveItem`（§3.2，独立 StatefulWidget）里；它监听 `_liveTick`，自行重建。思绪连跑合并到首行时，那一行是连跑起点（§3.1 的 `liveRow`），不是尾巴下标。
- 外壳（`ChatImages` / `Scrollbar` / `SelectionArea` / 骨架 `Stack` / `SuperListView` / 粘顶层 / 编辑器层 / 跳底按钮）不在每增量路径上。
- 滚动锚定不动：`_BottomAnchoredScrollPosition.applyContentDimensions`（:2462-2482）在 layout 里把 pixels 拉回 `maxScrollExtent`，与谁触发重建无关；行高变化照旧由 layout 传播。
- 粘顶 `_StickyFollower`（:2927-3010）、选择区 `_ItemSelectionScope`（:2494 起）语义不动：它们的输入不在文字增量里变。
- `_BeforeLayout`（:3329-3357）只在 list layout 时回调 `_forgetRowsLaidOut`，不在 build 路径上；行高变化照旧触发它，与谁重建无关。

### 2.3 最近先例对照（对齐 ∥ 偏离）

对齐（照抄形态）：

| 面 | 先例 | 照抄的形 |
|---|---|---|
| 输入不变就复用旧 widget | 折叠隐藏行记忆化（`chat_history_view.dart:1763-1793`） | 同一「输入 → widget」映射：相同就返回旧实例，Flutter 不再重建子树 |
| markdown 缓存 | 非流式整篇缓存（`markdown_view.dart:69-93`） | 保留该缓存，只在其外围加节流；不换解析路径 |
| 列表虚拟化 | `SuperListView.builder:2214` + `cacheExtent: 900`（:2219） | 零改动 |
| 计数方法 | 既建重建计数测试（`test/chat/chat_history_rebuild_test.dart:80-93`，`debugOnRebuildDirtyWidget`） | 同一钩子、同一断言形态 |
| 折叠的增量前提 | `StepFold.key` 注释「a run of steps grows at its end, never its start」（`step_folds.dart:24-27`） | 稳定点取「最后一条提示词」——增长只发生在尾部 |

偏离（逐条给理由）：

1. **新增折叠的增量入口 `StepFolds.extend`**：本仓无先例，`StepFolds.of` 一直是全量。理由见 §3.4：折叠结构只依赖条目类型与 `worked`，而尾部追加只影响最后一回合；先例注释本身已把这条前提写死。偏离的守门 = 与全量逐项对拍（§6-B2）。
2. **markdown 选节流而非按块缓存**：本仓唯一先例是整篇缓存，没有按块解析的既有面；块级切分要自己懂围栏代码、标签块、松散列表、缩进代码、表格与引用式链接定义（`markdown_view.dart:56-63` 共用文档级定义），切错的代价是渲染悄悄变形。节流复用同一条解析路径，最终态按构造等于一次性解析。理由与被否见 D6。

---

## 3. 接口契约

### 3.1 快路径判据（witness）

`_handleSessionChanged` 开头读取并比对以下 O(1) 事实（快照 `_tailSeen` 在每次通知末尾更新）：

```text
全部成立才是文字尾巴增量：
  itemCount == seen.count
  isStreaming == true == seen.streaming
  isUnprompted == seen.unprompted
  editing == null == seen.editing
  已前置条数（_session.prependedCount）== seen.prepended
  尾巴内容条目下标（_contentCount-1，:290-295）== seen.tailIndex
  该条目类型 == seen.tailKind（AssistantText ∥ Thinking）
  该条目文本长度 > seen.tailLength
```

**为什么它精确**（不是启发式）：

- 一次 `notifyListeners` 只对应一个已应用的 `KernelEvent`（`chat_session.dart:158-168`，`_apply` 每帧一条）。
- 会追加文字的只有 `TextDelta`；`Transcript._appendAt`（`transcript.dart:243-269`）只替换该 id 的条目，且是纯追加（`merged = current + 新段`），类型不变、条数不变、`worked` 不变。
- `StepFolds` 的结构只读类型 / `kind` / `status` / `background` / `worked`（`step_folds.dart:65-167`），以上全部不变 ⇒ 折叠结构不变。
- 任何其它事件：要么条数变（追加 / 删除 / 重放），要么流式位变（回合起止），要么尾巴文本不变（工具完成、状态行、用量、评审刷新）⇒ 判据失败，走全路径。
- 误判面：今日事件集不含「既给尾巴追加文字、又改了别处」的组合事件；若内核将来引入，witness 会**误通过**——快路径只重建 `liveRow`，别处的变更被吞掉，而且判据不失败就不会回全路径，当前无兜底。

**`liveRow`（实际渲染流式文本的行）**：尾巴条目下标 `tail = _contentCount-1`；`liveRow = _folds.rowOf(tail)`。`rowOf` 把被并进思绪连跑的条目映射到连跑首行（`step_folds.dart:86-89` 的 `_thoughtOf`），其余条目映射到自身。快路径只让 `liveRow` 这一行的 `_LiveItem` 重建。

为什么要这一步：

- 思绪连跑（≥2 条连续 `ThinkingItem`）只显示首行（`step_folds.dart:77-91`、`:184-190`）；被合并的后续条目 `rowAt` 返回 `item: false`，`_buildItem` 直接返回 `SizedBox`（`chat_history_view.dart:1810-1811`）。
- `itemBuilder` 先走 `_isHidden` → `_hiddenRow(index)`（`:2229-2232`）——`_LiveItem` 挂在尾巴下标上根本不会被构建，多段思绪流式时可见文本会停到下一次全路径。
- 挂在 `liveRow` 上才是「显示增量文本的那一行」。

失败面与兜底：判据失败一律回全路径（正确性优先）；判据本身只看 O(1) 字段，不扫历史。被否方案：给 `ChatSession` 加「本次变了哪条」的提示面（会动模型表面；判据已可精确判断，不需要）。

### 3.2 `_LiveItem` 契约

```dart
/// 实际渲染流式文本的那一行：只它监听修订号，只它重建。
class _LiveItem extends StatefulWidget {
  const _LiveItem({required this.revision, required this.live, required this.build});
  final ValueListenable<int> revision; // _liveTick
  final bool live;                     // index == liveRow
  final Widget Function() build;       // () => _buildItem(index)
}
```

- `live` 为假：`build` 直接返回 `build()`，不挂监听；为真：`initState` / `didUpdateWidget` 挂 `_liveTick` 监听，回调里 `setState`。
- 挂载位置：`itemBuilder` 的可见分支，`_row(index, gap: …, child: _LiveItem(…, build: () => _buildItem(index)))`（`chat_history_view.dart:2229-2237`）。对所有可见行恒包 `_LiveItem`（`live` 为假就不挂监听）：`live` 随 `liveRow` 移动时 widget 类型不换 ⇒ 该行子树 State（含 `MarkdownView` 缓存）不丢。
- `_hiddenRow` 分支（`:2230-2232`）不包：隐藏行不渲染文本；`rowOf` 保证 `liveRow` 落在可见行上（§3.1）。
- 选择器：`AnimatedBuilder` 被否（无动画，语义不符）；整表套 `ValueListenableBuilder` 被否（会重建列表，等于没改）；外壳级 `setState` 被否（就是今天的问题）。
- 每次快路径的重建集合 = 该 `_LiveItem` 子树（`_buildItem` → `ChatItemView` → `MarkdownView`）；`_row` / `ChatFindRow` / `ChatColumn` / `ChatImages` / `ScrollbarTheme` 不在内。

### 3.3 快路径不做什么（逐项，防漏）

不快路径做的事保持原样（全路径才做）：`setState`、`_refold`、`_images`、`_itemsCame` / `_appearing` / `_handoff`、`_scheduleStickyUpdate`、边雾 `_syncEdgeFades`、`_jumpToBottom`、编辑态重置、`_wantEarlier`。

- 它们的输入在文字增量里都不变：条数不变 ⇒ `_appearing` 无新增；`_wasLive` / `_prependedSeen` / `editing` 由判据保证不变；粘顶候选是用户消息，不在尾条。
- **例外（登记）**：查找栏打开时 `ChatFind._feedChanged`（`chat_find.dart:182`）仍会按自己的监听重算全量匹配并发通知——这是既有行为，本批不改也不加剧（§9-4）。

### 3.4 折叠增量：`StepFolds.extend`

新增 / 扩展（`lib/chat/step_folds.dart`）：

```dart
int get count;                                  // 当前条目数（视图判增删用）
int rowOf(int index);                           // 条目实际渲染所在行：被合并的思绪 → 连跑首行，否则自身
StepFolds extend(int count, ChatItem Function(int) itemAt, {required bool live});
void refreshTail(int index, ChatItem item);     // 更新折叠副本里的该条目，并丢掉覆盖它的思绪合并缓存
```

**实例语义（定死）**：`extend` **原地改，返回 `this`**（调用方不依赖返回值，签名保留只为链式可读）。`_merged` 是实例字段（`step_folds.dart:180`），原地改必须自清「≥ from 的合并项」；`refreshTail` 清「覆盖 index 的那一项」（`_merged.remove(rowOf(index))`）。选原地改而非新建实例：新建会丢掉 `< from` 的合并缓存，长对话里每个新条目都让可见思绪行重算一次。

**实施偏差（§12-2）**：`extend` 开头加 `assert(count >= _items.length)`；`StepFolds.none` 是共享单例、不可就地 grow。

**稳定点**：`from = min(最后一条非排队 UserMessageItem 的下标, 末尾思绪连跑起点, 末尾快步骤连跑起点)`。`[0, from)` 的数组 / 映射原样复用；`[from, count)` 用与全量相同的三段扫描重算。理由（即 §2.3 的先例注释）：追加只会在尾部接上连跑、或给最后一回合补内容；`UserMessageItem` 不是快步骤，连跑不跨提示词。**有回合账时**（§14）这一式里的「最后一条提示词」换成「最后一回合起点」，扫描边界同源；无账时即本式原文。

**实施偏差（§12-1）**：`[from, count)` 不是「只 append 新条目」——`extend` 先用 `_tailFrom(itemAt, count)` 求稳定点，再用 `itemAt` 重读 `start..count` 后 `_rescan`。回合结束时同下标条目会原地替换（提示词补 `worked`、状态行位置换成答案），只 append 会让 `fold_view_test` 两条既有用例红。代价 = 全路径增量时重读该回合（读次数 ≈ 该回合条目数，与历史总长无关）；A1 里的增量读数属快路径，与 `extend` 无关（§12-1）。

**算法**（与 `StepFolds.of` 同一套条件，只是起点不同）：

```text
extend(count, itemAt, live):
  新条目 append 到 _items（下标 ≥ 旧 count）
  from = min(最后一条非排队提示词, 末尾思绪连跑起点, 末尾快步骤连跑起点)
  清掉 ≥ from 的 _steps / _work / _thoughtOf / _thoughtRuns 条目 与 _merged 项
  _turnEnds：先删「最后一条提示词」的旧条目（答案增长会让收尾下标移动），再按尾部重算
  三段扫描（思绪连跑 / 快步骤连跑 / 最后一回合的工作与收尾）跑 [from, count)
  _liveEnd = live ? count-1（末尾是 LiveStatusItem 时）: null
  返回 this
```

**合法调用条件**（视图侧判，不满足就 `StepFolds.of` 全量）：

- **feed 未换**：`_folds` 来自当前 feed。`didUpdateWidget` 换 feed 时直接 `_refold()`（`chat_history_view.dart:477-494`，`:490`），而 `_refold` 是唯一入口（`:116-120`）——换 feed 一律走 `StepFolds.of` 全量，绝不 `extend`。否则新会话条目数 ≥ 旧 `_folds.count` 时会按「条数增长」复用上一会话的 `[0, from)` 折叠，折叠线与隐藏行错乱。
- `count >= folds.count` 且已前置条数未变（前置会给所有下标加偏移，`:1178` 的 `_shiftIndexes` 已处理 UI 侧）；
- 条数不变时：只有「流式位变了」才用 `extend`（回合起止，重算最后一回合）；其余同条数通知是「某处被替换」，位置未知 ⇒ 全量（保守，见 §9-1）；
- 条数增长：一律 `extend`。

**键与失效**：`StepFold.key = (kind, start)`（`step_folds.dart:26`），`_foldOpen` / `_unfoldedTurns` 都以它按下标记；追加不改变已有 fold 的 `start`，所以这些键在 `extend` 下不失效。前置（下标整体右移）由视图既有的 `_shiftIndexes`（`chat_history_view.dart:685-721`）先平移，再全量重算——键随平移继续有效。

**失效条件（内部缓存）**：`shownAt` 的思绪合并缓存（`step_folds.dart:180-190`）是唯一依赖文本的缓存。文字增量走快路径时调用 `refreshTail(tail, itemAt(tail))`：先更新折叠副本里的尾巴条目，再丢掉覆盖该下标的合并项——否则 `shownAt` 会拿 `of` 时捕获的旧条目重建合并文本，增量不显示。

**与全量的对拍判据**：对脚本历史逐步 append，每一步比较 `stepsAt` / `workAt` / `turnEndingAt` / `rowAt`（全开、全闭、混合三种）与 `shownAt` 文本——逐下标全等（§6-B2），脚本含「思绪连跑 1→2→3 条」。

### 3.5 图片集合缓存

**基线更正**：`_images` 只作为 `ChatImages.all` 回调传入（`chat_history_view.dart:2094-2095`），`ChatImages` 是 `updateShouldNotify => false` 的 `InheritedWidget`（`content_image.dart:264-266`），`all()` 只在打开图库时调用（`content_image.dart:273`）；全仓没有每帧调用点。**现状是按需一次 O(N)，不是每帧 O(N)**（评审 #4；需求档 §2 已同步改正）。

- 缓存值 = `foldImages(全部条目)`（`fold_line.dart:223-227`）；键 = `(itemCount, 末个内容条目的实例)`（末条 = `_contentCount-1`，跳过合成状态行）。**实施偏差**：实际只比较 `itemCount`，末条目实例仅记录（见 §12-4）。
- 防的是**重复按需收集**：每开一次图库今天都要重扫一遍全部条目；缓存命中时返回同一 `List` 实例，第二次起 0 次收集。
- **每次全路径会话通知无条件丢缓存**（同条数替换可能改任意一条的工具图片，位置未知）；`didUpdateWidget` 换 feed、`dispose` 同样丢。非会话原因的 `setState`（指针进出、边雾、粘顶下标、编辑层、折叠开关）不丢，缓存照常命中。
- 每文字增量：0 次收集（快路径不 build）；每新增一条：首次按需时 1 次（次数与历史长度无关，单次成本仍 O(N)，与今天同）。
- 失败面：若漏丢缓存，图片缩略图会停在旧集合；故「全路径通知即丢」是硬规则，不靠键猜。

### 3.6 流式 markdown：50ms 节流

只改 `MarkdownView.build`（`markdown_view.dart:83-93`），既有 `(data, style, themeColors, restyles)` 缓存保留。

```text
改动的数据到达（from != _builtFrom）：
  首次 / didChangeDependencies 之后 ⇒ 立即解析，记时刻
  旧文本是 widget.data 的前缀（同一消息在长）且距上次解析 < 50ms
        ⇒ 取消旧计时器，返回上次建好的 widget（旧文本），并排一个剩余时长的 Timer
        Timer 到点 ⇒ setState → 下一帧解析最新文本（trailing 必达）
  其余（旧文本不是新文本前缀：同一位置换了另一条消息 / 整篇替换）
        ⇒ 取消待决计时器，立即解析，记时刻
```

- **前缀条件（评审 #7）**：同一元素位换条目时（前置右移 `chat_history_view.dart:685-721`；编辑提交替换后续条目 `:1726-1738`；`ChatItemView` 以 `ValueKey(index)` 复用 `:1816`），窗口内返回上一条的 widgets 会显示错文本最多 50ms。加前缀条件后，换条目一律立即解析。
- 时钟 = `SchedulerBinding.instance.currentFrameTimeStamp`：只在帧内有效，且随 `tester.pump(duration)` 推进 ⇒ 测试可确定性计时。**该 SDK 依据不在本仓、本次未核（unverified）**；以 ⑥ 的计时前置用例为准（§8 第 0 步），用例不过 ⇒ 停并上报。
- 窗口 = 50ms（需求下限；不取更大，避免可感知的延迟）。
- 最终态保证：最后一次改动之后必有一次 trailing 解析 ⇒ 最终 widget 由「最终字符串 + 同一解析函数」产出，与一次性解析同构；`dispose` 取消计时器只影响即将消失的 State，下次 build 会从 `widget.data` 重解析。
- 解析次数上界：`⌈流式时长/50ms⌉ + 2`（首帧 + 尾帧各留 1）。
- **共享件影响面（评审 #6）**：`MarkdownView` 还用于 `assistant_text.dart:32`、`notice_row.dart:51`、`plan_card.dart:230`、`stash/stash_editor.dart:3469`。非流式三处 `data` 不变 ⇒ 命中既有缓存，零行为变化；stash 预览连续输入按 ≤50ms 限速、停顿后 trailing 必达（与对话同一上限，判定可接受）。被否：给 `MarkdownView` 加开关参数（改共享件接口、四处调用都要传，收益只是预览少合并 50ms）。
- 被否：按块缓存（要自写 markdown 感知的切分器：围栏、标签块、松散列表、缩进代码、表格、引用式链接定义；切错的代价是渲染变形，违背「不改视觉」）；被否：按帧数节流（帧率相关，120Hz 下窗口 <50ms）；被否：不节流。

### 3.7 数据流（改后）

```text
会话通知（一事件一次）
  ├─ 文字尾巴增量（§3.1）→ `refreshTail` + `_liveTick++` → `_LiveItem`（`liveRow` 那一行）→ `_buildItem` → `MarkdownView`（50ms 节流）
  └─ 其余 → _refold（extend ∥ 全量，§3.4）→ setState → build → 图片缓存（§3.5）→ _buildHistory → 列表
```

---

## 4 受影响文件清单（行数 = 实施后实测；基线 = 编制日实测）

> 口径：本表是上游 1.3.0 合并**前**的读数（编制日 / 实施后实测）；合并后工作树的现行值以 §14-4 为准，两表不互相回填。

| # | 坐标 | 改动 | 基线 | 实测 | 增量预算 | 结论 |
|---|---|---|---|---|---|---|
| ① | `lib/chat/chat_history_view.dart` | 快路径判据与快照 · `_liveTick` + `_LiveItem` · `liveRow` · `_refold` 调用规则（含换 feed） · 图片缓存 · `refreshTail` 调用 | 3358 | **3541** | ≤ +110（⇒ ≤3468）；不拆档（见下拆分计划） | 超 73 行（§12 记档） |
| ② | `lib/chat/step_folds.dart` | `count` / `rowOf` / `extend`（原地、尾部重算）/ `refreshTail` / 尾部三段扫描 | 353 | **435** | ≤ +120（⇒ ≤473，<500） | 在预算内 |
| ③ | `lib/chat/widgets/markdown_view.dart` | 50ms 节流 + trailing Timer + 计时字段 | 832 | **875** | ≤ +45（⇒ ≤877） | 在预算内（余 2 行） |
| ④ | `test/chat/chat_history_rebuild_test.dart` | F1 计数用例 + N1 脚本（短 / 长历史两跑） | 134 | **433** | ≤ +120（⇒ ≤254） | 超 179 行（含 A2/A3/B1/T3） |
| ⑤ | `test/chat/step_folds_test.dart` | 增量与全量逐项对拍 | 374 | **501** | ≤ +90（⇒ ≤464） | 超 37 行（B2 对拍） |
| ⑥ | `test/markdown_test.dart` | F3 解析上界 + 最终态一致 | 397 | **504** | ≤ +80（⇒ ≤477） | 超 27 行（C1/C2/C3/T10） |
| — | `lib/chat/chat_feed.dart` · `chat_session.dart` · `lib/kernel/transcript.dart` · `chat_screen.dart` | **零改动**（回合边界见 §14，另计） | — | — | 0 | — |
| — | 其余四个验收测试 | **零改动**，必须全绿 | — | — | 0 | — |

- 实测 = 实施后 `dart format` 后行数（2026-10-17，与批次档 §5-1 同源）。预算为设计期估算，四项超限已记档（§12），超限部分为验收用例与判据快照，功能未裁剪。
- 函数体量：单函数 ≤300 行（本批新增函数均远低于）。
- **拆档裁定与计划（评审 #10）**：`chat_history_view.dart` 编制日 3358 行、实施后 3541 行，仍在 800 行硬档之上。
  - 本批**不拆**：只做行为增量、不动 `_row` / `_buildItem` 的结构；新增 `_LiveItem` 约 30–40 行，只依赖 `ValueListenable<int>` 与传入的 `build` 回调，无 State 私有依赖，可独立搬走。
  - 拆分预案（不在本批执行，E 批台账 #47 启动时照此走）：首批候选 = 行细节层（`_row` / `_buildItem` / `_hiddenRow` / `_LiveItem` / 折叠行）移到 `lib/chat/history_rows.dart`，预算约 450–550 行，拆后 `chat_history_view.dart` 约 3000 行（按实施后 3541 行估）。
  - 触发条件 = E 批启动，或某批需要改动行结构（本批不触发）。需求档 §4「若必须拆，只拆本批需要的一小块并给预算」在此落实：本批不触发拆分。

---

## 5. 关键决策记录

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | 每增量的重建手段 = **视图内 `ValueNotifier<int>` 修订号 + 独立 StatefulWidget `_LiveItem`**；`live` = 实际渲染流式文本的行（思绪连跑 = 首行 `liveRow`）；外壳不进路径 | 只有显示新文本的那条需要新数据；`_LiveItem` 子树之外无 widget 更新，Flutter 自动跳过其余子树。被否：整表 `ValueListenableBuilder`（重建列表）；被否：外壳级 `setState`（现状）；被否：`AnimatedBuilder`（无动画，语义不符） |
| D2 | 快路径判据 = §3.1 的 O(1) witness；判据失败回全路径 | 一通知一事件 + `TextDelta` 纯追加 ⇒ 判据精确；不需要给 `ChatSession` / `Transcript` 加提示面（模型表面零动）。被否：模型侧变更提示（越界）；被否：按文本内容哈希全扫（O(L)） |
| D3 | 快路径**不**跑 `_refold` / `_images` / `_itemsCame` / 粘顶调度 / 边雾 / 跳底 | 这些输入在文字增量里不变（§3.3 逐项）；少一次就等于少一次全量。被否：保险起见全跑（等于没改） |
| D4 | 折叠增量 = `StepFolds.extend`（**原地改、返回 `this`**），稳定点 = 最后一条提示词与末尾连跑起点的最小值；**同一个 feed 才可用**，换 feed 一律 `StepFolds.of` 全量；前置 / 截断 / 同条数替换 ⇒ 全量 | 折叠结构只读类型与 `worked`；追加只影响最后一回合；原地改保留 `< from` 的合并缓存。被否：新实例（丢掉旧合并缓存，长对话每个新条目重算可见思绪行）；被否：按回合全缓存（要改公开访问器，风险大）；被否：惰性全量（仍是 O(N)/增量） |
| D5 | 图片集合 = **按需缓存**（键 `(itemCount, 末个内容条目实例)`；实施偏差：实际只比 `itemCount`，见 §12-4），防重复收集；**每次全路径会话通知无条件丢** | 现状只在开图库时按需收集一次 O(N)（基线已更正，§3.5），缓存消掉的是重复打开的重扫；同条数替换位置未知，键无法覆盖 ⇒ 用「会话变即丢」保正确 |
| D6 | markdown 选 **50ms 节流**（帧时间戳 + trailing Timer 必达），不选按块缓存；节流只在**旧文本是新文本前缀**时生效；共享件全局生效，stash 预览 ≤50ms 判为可接受 | 复用同一条解析路径 ⇒ 最终态按构造成立；前缀条件避免「同一行换条目」显示错文本；块级切分器要正确理解六类块结构与文档级链接定义，切错 = 渲染变形。被否：给 `MarkdownView` 加开关参数（改共享件接口）；被否：按帧数节流（帧率相关） |
| D7 | 量法 = 框架钩子 `debugOnRebuildDirtyWidget`（既有先例）+ 测试用 `ChatFeed` 的 `itemAt` 计数；**不在产品代码加计数钩子** | 两个信号在改前 / 改后都存在，同一测试文件可直接跑两版（N1 要求）；零产品面污染 |
| D8 | 不拆 `chat_history_view.dart`（本批）；拆分预案与预算见 §4 | 本批无结构改动；拆档 = E 批（范围外）。新增行数设计预算 ≤110（实施后 +183，超限记档见 §4 / §12） |
| D9 | 非流式 markdown 缓存策略不动；节流只作用于「数据变了要重建」的场合 | 非流式消息数据不变 ⇒ 命中缓存、零行为变化；不违背需求档 §4「不动非流式路径缓存」 |

---

## 6. 验收对照（回指需求档 F1–F3 + N1 + §5-3）

| 需求 | 落点 | 机检判据 |
|---|---|---|
| F1 增量只重建该重建的 | §2.2 · §3.1–3.3 | A1 计数：八类外壳 / 条目的重建次数；A2：20 / 200 回合逐项相等；A3：数据层、渲染节奏、终态（细则 §6.1） |
| F2 折叠与图片收集不随历史增长（次数）+ 对拍 | §3.4 · §3.5 | B1：增量期重建 / 条目读 / 图片收集；B2：`extend` 与 `of` 逐下标全等（细则 §6.1） |
| F3 流式 markdown 解析上界 + 最终态 | §3.6 | C1 解析上界（前置：§8 第 0 步）；C2 最终文本逐块相等；C3 无 pending timer（细则 §6.1） |
| N1 改前 / 改后同法读数 | §8 | D1：同一测试文件先在未改动代码上跑（红：A1/A2/B1/C1 给出改前数），再在实现后跑（绿）；两次读数写进批次档 §5 |
| 需求档 §5-3 真机走查 | §10 | W1（人工判据，非机检）：≥200 条长对话里流式跟手；记录会话条数与用户主观结论（写批次档 §5） |

### 6.1 判据细则

- **A1**：120 次文字增量回放（列表贴底，`liveRow` 在已建范围内），每次 `pump` 后计数：`ChatFindRow` 0、`SuperListView` 0、`SelectionArea` 0、`ChatColumn` 0、`ChatImages` 0、`ScrollbarTheme` 0、`ChatItemView` 恰 1、`MarkdownBlocks` ≤1。
  - **测量口径（实施偏差）**：回放用 bubble 消息样式（测试全局默认 sticky）。sticky 下布局结束后的粘顶候选重算会 `setState` 一次（实测第 72 个增量，20 / 200 回合一致），连带重建外壳 29 行；该 `setState` 由布局引起、不属增量路径（§3.3 已把粘顶调度排除）。改 bubble 后按本节原文测得严格 0（§12-3）。
- **A2**：20 回合与 200 回合历史下，每次增量的上述计数逐项相等。
- **A3**：① 数据层：§8 第 2 步的回放循环内，每次 `pump(8ms)` 后把 `MarkdownView.widget.data` 记入列表（只记录、不断言），循环后在汇总行之后逐条断言 == 当时最新全文；② 渲染层：回放期间 `MarkdownBlocks` 可见文本至少更新 5 次（节流允许合并）；③ 终态：回放后 `pump(50ms)` + `pumpAndSettle`，可见节点文本 == 一次性全文（逐块相等）。
- **B1**：① 同一回放，`ChatItemView` 之外无 `itemAt` 读增长——20 / 200 回合两次跑的 `itemAt` 调用总数逐次相等；② 增量期间图片收集 0 次；③ 无会话变更时从 `tester.widget<ChatImages>(…).all` 连续读两次：改前两次各 +N 次条目读，改后第一次 +N、第二次 +0（同一 List 实例）。
- **B2**：`StepFolds.extend` 与 `StepFolds.of` 逐下标全等（`stepsAt` / `workAt` / `turnEndingAt` / `rowAt` 三态 / `shownAt` 文本），脚本含思绪连跑 1→2→3 条、工作折叠、plan 卡、回合起止。
- **C1**：≥5000 字回复、200 个增量 × 8ms（共 1.6s）：`MarkdownBlocks` 重建次数 ≤ ⌈1600/50⌉+2 = 34，且 ≥5（流式中仍在更新）。
- **C2**：结算后该消息的 `MarkdownBlocks` 节点文本 == `MarkdownView.document(tags: true).parse(最终全文)` 的节点文本（逐块相等）。
- **C3**：`pumpAndSettle` 后无未决计时器（测试不报 pending timer）。

**既有测试通过面（必须全绿，零改动）**：

- `test/chat/chat_history_rebuild_test.dart` · `test/chat/history_scroll_test.dart` · `test/chat/fold_view_test.dart` · `test/chat/step_folds_test.dart`
- `test/sticky_message_test.dart` · `test/selection_scroll_test.dart` · `test/markdown_test.dart`（这三个在 `test/` 根下，与需求档 §5-2 的注明一致）。

---

## 7. 用例表

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 文字尾巴增量（正常） | 流式中，末条 `AssistantTextItem` 文本变长，notify + pump | 仅 `ChatItemView` 1 次重建；外壳 / 历史行 0；文本更新 |
| T2 | 流式开始 / 结束（边界） | `isStreaming` false→true（新回合）、true→false（回合收） | 走全路径一次：外壳重建 1；折叠按「起止」规则重算；不出现快路径 |
| T3 | 思绪增量（边界） | 末条 `ThinkingItem` 文本变长，且它已与上一条思绪合并成连跑（合并显示在连跑首行） | 快路径；重建的是连跑首行（`liveRow`）；首行合并文本含最新增量；折叠结构不变 |
| T4 | 同条数替换（边界） | 工具卡状态 running→succeeded（条数不变） | 全路径；折叠全量重算；图片缓存被丢（下次按需重收） |
| T5 | 尾部新增条目（正常） | 条数 +1（新工具卡 / 新文本块） | 全路径；折叠 `extend` 只重算最后一回合；无 O(历史) 折叠 |
| T6 | 前置历史（边界） | `HistoryPrepended`（条数增、下标整体右移） | 全路径 + 折叠全量 + `_shiftIndexes`；快路径不成立 |
| T7 | 编辑中 / 查找栏打开（边界） | `editing != null`；或 `_find.visible` | 编辑：快路径不成立（全路径）。查找：快路径成立，但查找自身仍全量重算匹配（既有行为，登记） |
| T8 | 节流尾帧（边界） | 最后一个增量距上次解析 <50ms，随后不再有增量 | trailing Timer 补一次解析；最终文本正确；无 pending timer |
| T9 | 切换会话（边界） | `didUpdateWidget` 换 feed，新会话条目数 ≥ 旧会话 | 折叠走 `StepFolds.of` 全量；不复用旧会话折叠；行内容为新会话，无错隐藏行 |
| T10 | 前置历史 / 编辑提交（边界） | `HistoryPrepended`（下标右移）或 `_submitEdit` 后同一 `ValueKey(index)` 换条目 | 全路径；markdown 立即解析（旧文本不是新文本前缀，不进节流窗口）；不显示上一版文本 |

---

## 8. 量法与基线流程（N1）

**脚本（写进 ④ 的测试文件，固定参数）**：

0. **计时前置用例（评审 #14，写在 ⑥ `test/markdown_test.dart`）**：一条最小用例在 build 里读 `SchedulerBinding.instance.currentFrameTimeStamp`，`pump(const Duration(milliseconds: 8))` × 7 后确认时间戳至少前进 50ms。该用例不过 ⇒ C1 的计时前提不成立，**停并上报**（不改用挂钟：测试里不可控）。
1. 造历史：`turn(n)` = 1 条用户消息 + 若干工具/文本步 + 1 条回答（复用既有重建测试的造法，`chat_history_rebuild_test.dart:59-66`）；短历史 20 回合，长历史 200 回合，两次跑同一段流式尾巴。
2. 回放：对末条 `AssistantTextItem` 追加 120 段固定文本（每段 8 字），每段 `notifyListeners()` + `await tester.pump(const Duration(milliseconds: 8))`；回放期间保持贴底；**循环内只累计计数与 A3 ① 的数据层快照，不写断言、不打印**——A3 ① 的比对挪到汇总行之后统一做，N1 的改前红跑因此不会被打断。
3. 计数器（全部既有面，产品零改动）：
   - 构建：`debugOnRebuildDirtyWidget`（先例 `chat_history_rebuild_test.dart:82-85`）按 widget 类型计 `ChatFindRow` / `ChatItemView` / `SuperListView` / `SelectionArea` / `ChatColumn` / `ChatImages` / `ScrollbarTheme` / `MarkdownBlocks`；
   - 条目读：测试用 `ChatFeed` 的 `itemAt` 计数（短 / 长两次跑同一实现，逐次比较）；
   - 解析：`MarkdownBlocks` 重建次数（每次 `MarkdownView._build` 必然产出新的 `MarkdownBlocks`，`markdown_view.dart:95-162`）。
4. 读数输出（评审 #5）：循环后**先** `debugPrint('F1 rows=… itemReads=… parses=…')`，并在 `addTearDown` 里再输出一次兜底（断言失败也留读数）；**之后**再做 `expect`。改前 / 改后共用同一段采集代码。

**基线顺序（硬要求）**：

1. 先写 ④⑤⑥ 三个测试（此时是红）：④ 在同一条未改代码上跑短 / 长两版，得到改前读数并记录（循环后汇总行先于断言 ⇒ 红也有数）；
2. 再实现 ①②③；
3. 再跑同三个测试（绿），记录改后读数；
4. 同一台机器、同一 Flutter SDK、同一命令（`flutter test test/chat/chat_history_rebuild_test.dart test/chat/step_folds_test.dart test/markdown_test.dart`）。

**不做**：不引入基准框架、不记时间戳到产品、不以「文件大小 / 代码行数」代替读数。

---

## 9. 边界（本批不做）与失败面

1. **工具密集回合仍按工具事件全路径重建**（同条数替换位置未知，D5/D4 保守）：事件率是人手级（每工具结果一次），不是 token 级（20–60 次/秒）。判定条件：真机走查若工具密集时仍涩 ⇒ 另立「按事件 id 定位变更条目」的模型提示面（本批不做）。
2. **单个超长回合**的 `extend` 成本 ∝ 该回合条目数（稳定点在最后一条提示词）：符合需求「只重算受影响的那一回合」，但不是 O(1)。
3. **图片收集**：现状是按需一次 O(N)（开图库时），本批加缓存后重复打开不再重扫；单次成本仍 O(N)，要消掉需按条目增量维护，本批不做。
4. **查找栏打开时**：`ChatFind` 仍按自己的监听全量重算匹配（`chat_find.dart:182,207-237`），每增量 O(N)——既有行为，本批不改也不加剧；F1 的读数在查找栏关闭下取。
5. **非流式 markdown 的整篇缓存**原样保留；节流只影响「数据变了」的重建。
6. **按块 markdown 缓存**不做（D6 被否）；若未来走该路线，需一个独立的 markdown 感知切分器与对拍测试，另立批次。
7. **结构拆分**不做（E 批）。
8. **事件形态 / 内核 / 依赖 / 列表实现**零改动；`ChatFeed` 接口本身不加方法（回合边界是独立的能力接口，见 §14）；`Transcript` 不加字段。
9. **多视图**：同一会话在主编排与子代理层各有一个视图（`chat_screen.dart:693` / `:824`），各自走同一判据；互不影响。
10. **文档地图**：本仓暂无文档地图 / AGENTS.md；若建立，登记「对话渲染板块」指向本档 + 配对需求档，C / E 批引用同一节，不另立重复档（评审 #15）。

---

## 10. UI / 交互决定（全部落地，无 open）

- 视觉零变化：粘顶、跨重建选择、滚动锚定、`cacheExtent: 900` 语义、边雾、跳底按钮、出现动画（`_Appear`）全部保持。
- 流式文字节奏：markdown 解析上限 20Hz（50ms），文字出现节奏略合并；这是需求 F3 明确允许的两案之一，判断线 = 真机走查主观确认（需求档 §5-3）。
- markdown 节流是共享件行为：非流式三处数据不变（缓存命中）；stash 预览连续输入按 ≤50ms 限速、trailing 必达，判为可接受（§3.6）。
- 无新增 UI、无新 l10n 键、无新设置项。
- 无 open 项。

---

## 11. 实现期核对清单（照做即可，不留决策）

1. `_handleSessionChanged`：先取 `liveChanged = _feed.isStreaming != _wasLive`，再做判据；快路径：`_folds.refreshTail(tail, _feed.itemAt(tail))` → `_liveTick.value++` → 更新快照 → `return`。快照在 `initState` / `didUpdateWidget` / 每次通知末尾都要重取。
2. `_refold` 的调用规则按 §3.4；`StepFolds.of` 仍是全量入口，`extend` 原地改并返回 `this`；**换 feed（`didUpdateWidget`）一律 `StepFolds.of` 全量**。
3. `liveRow = _feed.isStreaming ? _folds.rowOf(_contentCount - 1) : -1`；`_LiveItem` 包在 `itemBuilder` 的可见分支、`_row` 的 child 位置，`live: index == liveRow`；`_hiddenRow` 分支不包；`_liveTick` 在 `dispose` 里释放。
4. 图片缓存：全路径会话通知第一行置空；`_images()` 命中返回同一 List 实例（引用相等）。
5. markdown：节流只在「旧文本是新文本前缀」时生效，换条目立即解析；节流字段与 Timer 在 `dispose` 取消；`didChangeDependencies` 清缓存并取消待决计时。
6. 不改 `_hiddenRow`、`_BeforeLayout`、`_StickyFollower`、选择器与滚动控制器的任何一行。

---

## 12 实施偏差记录（实施后补记，2026-10-17）

四处实现与设计不一致；机制结论（快路径判据 / `_LiveItem` / 节流窗口）未变。行号 = 实施后坐标。

### 12-1 `extend` 重读最后一回合条目（§3.4）

- **原设计**：`[0, from)` 原样复用，`[from, count)` 只 append 新条目后按三段扫描重算。
- **实际做法**：`_tailFrom(itemAt, count)` 用 feed 求稳定点，再用 `itemAt` 重读 `start..count` 后 `_rescan`（`step_folds.dart:104-141`；`of → _rescan(0)` 与 `extend → _rescan(from)` 共用同一扫描，`:72`、`:171` 起）。
- **理由**：回合结束时同下标条目会被原地替换（提示词补 `worked`、状态行位置换成答案），只 append 会保留旧实例，`fold_view_test` 两条既有用例红。
- **代价（`extend`）**：只在全路径增量里发生（条数增长 / 回合起止，调用点 `chat_history_view.dart:1402`）：重读最后一回合，读次数 ≈ 该回合条目数，与历史总长无关。
- **读数（A1 的每增量 10 读）**：快路径逐帧重建那一行的读（`refreshTail` + 重建行），与 `extend` 无关；合并上游 1.3.0 后行构建另多 `_rowAt` / `_liveFooter` 各一读（`chat_history_view.dart:2022` / `:2024`，不在冲突块内、未改上游）。
  判据：A1 的增量是尾条 `AssistantTextItem` 变长，witness 成立 ⇒ 走快路径；条数不变、无回合起止 ⇒ `grow` 恒 false ⇒ `extend` 在 A1 里不可达。20 / 200 两跑逐次相等 ⇒ 与历史长度无关。

### 12-2 `extend` 的防御性断言（§3.4）

- **原设计**：合法调用条件由视图侧判（`count >= folds.count`），`extend` 内无断言。
- **实际做法**：`extend` 开头 `assert(count >= _items.length)`，并注明 `StepFolds.none` 是共享单例、不可就地 grow。
- **理由**：防御性收紧；调用方 `_refold` 已先判 `count >= _folds.count`，误用应在调试期立即暴露。
- **代价**：无运行时成本（`assert` 只在 debug 生效）。**它挡的是缩表，不挡共享单例**：`StepFolds.none` 的 `_items` 为空 ⇒ `assert(count >= _items.length)` 恒真（`step_folds.dart:60-68`），直接对 `none` 调 `extend` 拦不住，只会静默就地改脏共享的那一份。
- **可达性**：今天没有这条调用路径——产品侧只有 `_refold` 一处调 `extend`（`chat_history_view.dart:145`），视图首帧的 `_refold()`（`:608`）是全量 `StepFolds.of`，`none` 在首帧前已被换成实档（`:104` 初值 / `:147` 全量）；测试的三处调用也都在 `_fold(...)` 的实档上（`step_folds_test.dart:19-23`）。

### 12-3 A1 的测量口径 = bubble 样式（§6.1-A1）

- **原设计**：§6.1-A1 未指定消息样式；§8 回放 = 每段 `notifyListeners()` + `pump(8ms)`。
- **实际做法**：A1 在 bubble 消息样式下取数（测试全局默认 sticky）。
- **理由**：sticky 下布局结束后的粘顶候选重算会 `setState` 一次（实测第 72 个增量，20 / 200 回合一致），连带重建外壳 29 行；该 `setState` 由布局引起、不属增量路径（§3.3 已把粘顶调度排除在快路径外）。
- **代价 / 读数**：产品行为不变；sticky 下这一次外壳重建属布局噪声，不计入 A1。bubble 下按 §8 原文测得外壳计数严格 0。

### 12-4 图片缓存键只比 `itemCount`（§3.5 / D5）

- **原设计**：键 = `(itemCount, 末个内容条目的实例)`。
- **实际做法**：只比较 `itemCount`；末条目实例仅记录、不参与比较（`chat_history_view.dart:2222-2251`）。
- **理由**：比较末条目实例需要在每次命中多读一次 `itemAt`，与 B1③「第二次 +0 读」冲突。
- **代价 / 安全性**：正确性依赖「每次全路径通知无条件丢缓存」这条硬规则；若漏丢，缩略图停在旧集合（与 §3.5 失败面同一条）。

**体量**：①④⑤⑥ 超预算（实测见 §4 表）。超限部分是判据快照与验收用例（T3 / T10 / A2 / A3 / B1 / B2 / C1–C3），功能未裁剪；预算上限本身未改。

---

## 13 合并上游 1.3.0 的补记

合并上游 1.3.0 后，本档的机制多了两个成员：`_liveStart`（回合起点的条目下标）与 `Steadiness`（行「该不该显示」的稳态判定）。§3.1–§3.6 的机制结论不变；本节记它们与既有口径的关系。

### 13-1 `_liveStart` 与 `_liveRow` 的分工

- `_liveStart`：**条目下标**（feed 坐标）。`_refold` 每次重算：从 `itemCount-1` 反向找最后一条 `UserMessageItem(queued: false)`，取其 +1；没有提示词时为 null。`_isLive(index)` = `index >= _liveStart`。
- 消费者：`_rowAt` 的稳态门（`chat_history_view.dart:254`）、`_isExpanded` 的稳态门（`:734`）、`_replyStart()`（`:1351` 取它 −1 当提示词下标）。
- `_liveRow`：**行下标**（折叠坐标）。getter 现算：`_feed.isStreaming ? _folds.rowOf(_contentCount - 1) : -1`；只决定哪一行挂 `_LiveItem` 听 `_liveTick`（增量重建，§3.1–§3.2）。
- **两者不互推**：`_liveStart` 只由 feed 扫描派生，`_liveRow` 只由 `_folds.rowOf` / `_contentCount` 派生，不共享中间量、不互相赋值。口径不同是故意的：前者用 `itemCount`（含末尾 `LiveStatusItem`）覆盖整个回合，后者用 `_contentCount`（排除状态行）落在显示文字的行上。

### 13-2 稳态 tick 可致一帧外壳重建

`Steadiness`（`lib/chat/steadiness.dart:13-77`）的成熟 / 保持计时器到点后走 `onChange → if (mounted) setState(() {})`（`chat_history_view.dart:225-229`）——即一帧外壳重建。它**不属增量路径**（触发者是计时器，不是文字增量；增量本身不 `setState`），但增量帧若恰好落在 tick 帧上，A1 的六类外壳计数在该帧非 0。

**A1 回放不建条目，所以 A1 仍须严格 0**：`_rowAt` 只在 `_isLive(index) && isQuickStep(item)` 时问 `_steady`（`:254`）；`_isExpanded` 只在 `item is ThinkingItem` 时问（`:734`）。`_plainTextOf`（`:332`/`:340`）与 `_minimapRow`（`:2151`）只经这两道门进 `_steady`，不新增入口；A1 回放的唯一条目是 `AssistantTextItem` ⇒ 两道门都提前返回 ⇒ 零条目、零计时器、零 tick。

### 13-3 A4：区分「增量路径本身」与「稳态 tick」

- 用例 **A4**（`test/chat/chat_history_rebuild_test.dart`）：一条非排队 `UserMessageItem` + 一条 streaming `ThinkingItem`（`seconds` 省略），**bubble** 消息样式；`pumpWidget` → `pump()` → 120 ×（尾条 `ThinkingItem` 追加固定字数 → `notifyListeners()` → `pump(8ms)`），逐帧计六类外壳。
- 判据：非 0 外壳帧数 **== 1**，该帧下标 ∈ [36, 39]（300ms 成熟，±1 帧），其余帧 0 且 `ChatItemView` == 1；末尾卸载让 `_steady.dispose()` 取消未决计时器。
- 为什么需要它：只测 A1 全 0 无法排除「统计没看见 tick」；**A1 全 0 + A4 恰 1 帧**合起来才证明「外壳 0」是增量路径的属性。
- 为什么写死 bubble：sticky 下布局引起的粘顶重算会在第 72 个增量多一帧外壳重建（§6.1-A1 的测量口径），A4 的「== 1」会被它破坏。

### 13-4 A1 口径不变

§6.1-A1 与 §12-3 的口径照旧：bubble 样式、每段 `notifyListeners()` + `pump(8ms)`、无额外 settle 帧，六类外壳严格 0。合并不放宽、不引入新读数；A1 变红时先查回放 feed 是否被改出 live 快步骤 / streaming 思绪，再查快路径是否被绕开，按缺陷报，不改读数。

**读数**：A1 的每增量读数为 10（20 / 200 两跑逐次相等）；其中行构建的 `_rowAt` / `_liveFooter` 各一读属上游（`chat_history_view.dart:2022` / `:2024`，不在冲突块内、未改上游），不计入 `extend` 的代价，也不改变本口径（六类外壳仍严格 0）。

## 14 回合边界与折叠（unprompted 回合折走上一回合答案）

### 14-0 四个问题，四句回答

- **边界从哪来**：从内核已有的回合事件来——`TurnStarted(turnId, unprompted)` / `TurnEnded(turnId, interrupted, worked)`（`lib/kernel/kernel_event.dart:16-52`）。`ChatSession._apply`（`lib/chat/chat_session.dart:158-168`）是事件进 UI 的唯一入口，在那里记一份**回合账**：每回合的 `turnId`、起点条目下标、开这一回合的用户消息下标（unprompted 回合没有）、已结束回合的耗时。
  不新增事件、不改 `Transcript`、不改 `KernelEvent`。
- **折叠怎么用**：`StepFolds` 多收一个 `turns`（回合账），把「最后一条提示词 → 最后一条文本」的窗口换成「本回合起点 → 下一回合起点」；窗内规则逐字沿用今天的实现，只把下界从 `prompt` 换成窗起点。`worked` 与回合页脚的挂点从边界取。
- **旧会话 / 重放怎么退化**：账是内存投影。重放（`session/load`）只有条目、没有回合事件 ⇒ 账为空 ⇒ 折叠退回今天的提示词规则（不崩、不错行）。重载后第一个新回合起恢复正确；重载前的那段旧回合仍是今天的画面。
- **A1/A4 为何不回退**：快路径（文字尾条变长）不读账——`_tailGrew()`（`lib/chat/chat_history_view.dart:191-206`）与 `refreshTail`（`lib/chat/step_folds.dart:141-145`）都不碰 `turns`；A1/A4 的测试替身也不实现新能力接口（§14-3）。账只在 `_refold`（`chat_history_view.dart:138-153`）的全路径里读。

### 14-1 缺陷与事实基线（实读）

- work fold 以「最后一条非排队 `UserMessageItem(queued:false)` → 范围内最后一条 `AssistantTextItem`」为窗：`lib/chat/step_folds.dart:207-250`。窗内 `[prompt+1, answer)` 折成一行，`answer` 是窗内尾部「文本/思绪」连跑的最前一条文本（`:225-232`）。
- unprompted 回合没有新的用户消息：thincoder 的自动轮 `_beginTurn('auto:<n>', unprompted: true)`（定义 `lib/kernel/thincoder/thincoder_kernel.dart:634-640`；自动回合起点 `:661`；来源见 `docs/design/thincoder-adapter.md` §19.2）。它整回合的条目接在上一回合之后，回答成为最后一条文本 ⇒ 上一回合答案落进 `[prompt+1, answer)` 被折走。
- `AssistantTextItem` 只有 `text`（`lib/chat/chat_models.dart:121-125`），条目本身不带回合信息；`Transcript` 收到 `TurnEnded.worked` 时只写回「开这一回合的用户消息」的同 id 条目（`lib/kernel/transcript.dart:287-293`），自动回合没有这条消息可写 ⇒ 汇报轮今天**既不能自己折、又把上一回合的答案吞进自己的窗**。

### 14-2 规则（写死）

**边界（每个回合一条，升序）**：

1. 每条 mark 的 `start` 是一条边界。
2. 每条非排队用户消息（`UserMessageItem(queued:false)`）的下标也是一条边界。理由：旧会话 / 重放没有账；claude_code 的排队消息被取用时，提示词条目先落地、`TurnStarted` 后到（`lib/kernel/claude_code/claude_code_kernel.dart:1745-1758`），提示词下标比 mark 小一格，这条规则让它照旧是上一条回合的收尾。
3. 同下标的边界合并成一条：mark 优先（取 mark 的 `worked` 与 `prompt`）；两条都是 mark 时取**靠后**的（列表里较新的那条，R5）。
4. 越界（`start < 0` 或 `start > count`）、乱序的 mark 丢弃；不抛。`start == count` 是**合法的空边界**：`TurnStarted` 刚建的 mark 此刻 `start == count`（本回合第一条条目还没落地），它既是本回合的起点、也是上一回合的收口；丢掉它，刚结束的回合就成了「最后一条窗」，B 流式期间它的折叠被清掉（要等下一次非 live 的重扫才回来）——与 R4、本批要求①/⑤（§14-11）相抵（评审 #1）。

**窗**：回合 `t` 的范围 = `[b[t].start, b[t+1].start)`，最后一条到 `count`。`live` 时最后一条是进行中的回合，不折（等价于今天的 `if (live && t == prompts.length - 1) break;`）。边界落在 `count`（空边界）时，它自己的窗为空、不产生折；上一回合的窗在它处收口，照常折。

**窗内规则（逐字沿用 `step_folds.dart:211-250`，只换下界）**：

1. `worked` 取边界：mark 的 `worked`，或（无 mark 的旧路径）提示词条目的 `worked`。null ⇒ 本回合不折（与今天一致，含被打断的回合）。
2. `last = end - 1`；尾部是用户消息时回退（`while (last > start && itemAt(last) is UserMessageItem) last--;`）。
3. `last > start` ⇒ `_turnEnds[rowOf(last)] = 边界.prompt ?? start`（回合页脚的挂点：`chat_history_view.dart:274-294` 按 `itemAt(prompt)` 读 `worked` / `usage`；unprompted 回合的挂点不是用户消息 ⇒ 页脚自然为空，既有代码已判）。
4. `itemAt(last)` 必须是 `AssistantTextItem`，否则不折；`answer` = 从 `last` 往回、穿过思绪、取连跑最前一条文本，下界 `start`（今天的 `:225-232`）。
5. 折起点 = `start` 跳过开头的用户消息（任何 `UserMessageItem`，**不按 `queued` 过滤**）：边界合并后，回合自己那条提示词落在窗首（mark 与消息同下标时 mark 优先，窗仍从消息下标起），它不算 work；落在窗首的排队消息同样跳过。窗内有 `PlanItem` ⇒ 折起点移到它之后（下界 `start`，`step_folds.dart:260-265`）。
6. `[折起点, answer)` 里非思绪条目 < 2 ⇒ 不折（今天 `:243-247`）。

**一句话**：work fold 只折**本回合**、折到**本回合答案之前**；上一回合的答案不在本回合窗内，保持可见；单回合内「中间回答被折」不变。

### 14-3 接口契约

**回合账（新类型，`lib/chat/chat_models.dart`）**：

```dart
/// 一个回合，折叠看得到的那部分：内核给的回合 id、第一条条目的下标、
/// 开这一回合的用户消息下标（unprompted 回合为 null）、耗时（进行中
/// 或被打断为 null）。
typedef TurnMark = ({
  String turnId,
  int start,
  int? prompt,
  Duration? worked,
});
```

**能力接口（`lib/chat/chat_feed.dart`，与 `ChatFeed` 并列，不进 `ChatFeed`）**：

```dart
/// 知道自己的回合的会话：从内核的回合事件记下每回合从哪开始。
/// 只在折叠（全路径）时读，读完即弃；不实现它的 feed 按提示词折（今天的规则）。
abstract interface class MarksTurns {
  /// 升序；进行中的回合也在（最后一条）。读时只读、不缓存。
  ///
  /// 返回会话自持的同一 List 实例（不拷贝、也不包只读视图）：一次
  /// 全路径通知读一次，拷贝 = 每事件 O(回合数)。**调用方只读**——
  /// 不得增删、排序或长期持有；折叠在本次调用内读完即弃。
  List<TurnMark> get turns;
}
```

- 独立接口而非 `ChatFeed` 新方法：`implements` 要求实现所有成员，给 `ChatFeed` 加方法会连累 `SubagentFeed`（`chat_feed.dart:42`）与全部测试替身；独立接口是内核侧能力声明（`SelectsModel` / `RewindsConversation` / `StartsPlans`）的同一做法。
- `ChatSession` 声明 `implements ChatFeed, MarksTurns`，`turns` 返回自己持有的 `List<TurnMark>`（原地增改；`StepFolds` 只在本次调用内读，不持有）。**只读契约（评审 #10）**写在接口注释上，不包只读视图：缓存一个 `UnmodifiableListView` 要在换内核重建账时失效（多一处状态），每次现包 = 每次全路径一次分配；消费方只有 `_refold` 一处，注释约束足够。预算：只多注释行，无运行成本。

**会话侧记账规则（`ChatSession._apply`）**：记账只在 `_transcript.apply(event)` 返回 `true` 之后发生（`chat_session.dart:162`）——即 `if (event is KernelInfoChanged || _transcript.apply(event))` 的后一半。`KernelInfoChanged` 只走短路前半段：不调 `apply`、没有回合账动作；即便走到 `apply`，`transcript.dart:195-196` 也返回 `false`。重复 / 过期事件由 `apply` 返回 `false`（`transcript.dart:124`），同样不记。

| 事件 | 动作 |
|---|---|
| `TurnStarted(turnId, unprompted)` | 追加一条 mark：`turnId = turnId`、`start = _transcript.length`（此刻之后第一条条目的下标；可等于 `count`，是合法的空边界，见 §14-2 规则 4）、`prompt = unprompted ? null : (_transcript.indexOf(turnId) ?? start)`、`worked = null` |
| `TurnEnded(turnId, interrupted, worked)` | 从尾往前找第一条 `turnId` 相同的 mark，写 `worked = interrupted ? null : worked`；找不到 ⇒ 不改账（如该回合的 mark 已被回退裁掉） |
| `HistoryPrepended` | 先算 `moved = _transcript.prepended - _prependedSeen`，写回 `_prependedSeen = _transcript.prepended`，再把每条 mark 的 `start` / `prompt` 加 `moved`（只算真正插入的条数：`_prepend` 会滤掉已有 id，`transcript.dart:219-225`）。字段 `_prependedSeen`（int，初值 0）与视图侧同形（`chat_history_view.dart:786`）；换内核重建 `Transcript`（`prepended` 归 0）时一并归 0；`Rewound` 不改 `prepended`（`transcript.dart:45-47` 只增），无需同步 |
| `Rewound` | 截断点 = 应用后的 `_transcript.length`；从尾往前删「起点 ≥ 截断点」的 mark。剩下的最后一条 mark 只在**跨过且非消息点**时删：跨过 = 被删 mark 里最小的起点 > 截断点，或未删 mark 但砍掉了条目；消息点 = 截断点上是 `UserMessageItem`（下一回合的提示词，不算被截回合的）。消息点在 `apply` 前判，按 `itemId` 解析、缺省 `index`（`_cutsAtMessage`，`chat_session.dart:185-192`；裁剪分支 `:234-247`） |
| 换内核（`chat_session.dart:328-337` 重建 `Transcript`） | 清空 mark；`_prependedSeen = 0` |

`start` 为什么在 `TurnStarted` 那一刻取 `_transcript.length`：三个内核都在 `TurnStarted` 之后立刻发本回合第一条条目（thincoder `:522-538`、claude_code `:831-843`、codex `:159-168`），所以此刻的长度就是该回合第一条条目的下标；`prompt` 用 `indexOf(turnId)` 兜住「提示词先落地」的那一种（claude_code 排队取用）。

**为什么 `turnId` 进 mark**：`TurnEnded` 只带 `turnId`，按字面匹配就要把这个 id 记在 mark 上；`Transcript` 的回合面用同一个键（`_endedTurns` 去重、`_timeTurn` 写回，`transcript.dart:128` / `:287-293`）。同下标的两条 mark（R5）仍在折叠层按边界合并，id 不参与；回退裁掉 mark 后，迟到的 `TurnEnded` 按 id 找不到 ⇒ 不会写进别的回合（R8）。**被否**：不加字段、按「结束的是最后一条 mark」——回合串行下大多成立，但 mark 被裁掉后会静默写进上一回合的 mark，且与 `Transcript` 的 id 键不同套。

**折叠侧签名（`lib/chat/step_folds.dart`）**：

```dart
factory StepFolds.of(int count, ChatItem Function(int) itemAt,
    {required bool live, List<TurnMark> turns = const []});
StepFolds extend(int count, ChatItem Function(int) itemAt,
    {required bool live, List<TurnMark> turns = const []});
```

- 默认空 ⇒ 行为与今天逐下标相等（既有测试与全部测试替身零改动）。
- `_rescan(from, live:, turns:)` 先在 `[from, count]` 内求边界（提示词正扫 `[from, count)` + mark 反扫到 `start < from` 为止；`count` 只可能来自 mark——空边界），再按 §14-2 扫；`_tailFrom` 有账时用最后一条 mark 的 `start`（O(1)，可与 `count` 相等），无账时用今天的提示词反扫。
- **`_turnEnds` 的删除范围（评审 #13）**：§3.4 的「先删后重算」在有账时只删**本次将要重算的那条窗**的旧条目（该回合的收尾下标会随答案增长移动，旧键不删会留下错的回合页脚），更早回合的条目一律不碰。
  - `from == count`（空边界，重扫范围为空）时没有要重算的窗 ⇒ **不做任何删除**：此刻尾部属于上一回合、不在本次重算范围里，删了不会重建，回合页脚会消失到下一次全路径。
- `refreshTail` / `rowAt` / `mergeThoughts` / `StepFold` 的签名与行为不变：折出来的还是 `(kind, start, end, worked)`。

**视图侧（`_refold`）**：

```dart
final turns = switch (_feed) { final MarksTurns feed => feed.turns, _ => const <TurnMark>[] };
_folds = grow
    ? _folds.extend(count, _feed.itemAt, live: _feed.isStreaming, turns: turns)
    : StepFolds.of(count, _feed.itemAt, live: _feed.isStreaming, turns: turns);
```

**性能面（逐条回答「不因边界标记退化」）**：

- 文字尾条变长 ⇒ `_tailGrew()` 成立 ⇒ `refreshTail` + `_liveTick`，不 `_refold`、不读 `turns`。A1 的每增量计数按构造不变。
- 回合起止本来就落全路径：`_tailSeen` 的快照里已有 `streaming` / `unprompted`（`chat_history_view.dart:169-206`），`TurnStarted` 翻转 `isStreaming` ⇒ 判据不成立。
- **前提（评审 #12，写死）**：`TurnEnded` 也翻转 `isStreaming`（生产语义）——回合结束那一跳要走一次 `live=false` 的重扫，上一回合的折叠在这一跳产生。
  - 到 `TurnStarted(B)` 时 `_tailFrom` 只取 B 的 `start`（可与 `count` 相等），重扫范围里不再有上一回合的窗。
  - 已核：`isStreaming => _transcript.activeTurn != null`（`chat_session.dart:526`），`TurnEnded` 命中当前回合即清 `activeTurn`（`transcript.dart:141-143`），`apply` 返回 true 后通知视图（`chat_session.dart:162-167`）。
  - 实现轮前置核这条前提；核不到（实现或某内核让 `TurnEnded` 之后仍为 true）按缺陷上报——R13 的变体跑的就是这条前提为假的情形。
- 交给 `StepFolds` 的是账本身（同一 List 实例），不做拷贝；`extend` 只反扫 `[from, count)` 内的边界（一般 1–2 条）。`_rescan` 里既有的 `removeWhere` 成本不因本设计增大。
- `_turnFooter` / `turnEndingAt` / `_unfoldedTurns` / `_lastTurnWork` 的语义不变：`fold.start` 仍是键，追加不改已有回合的起点。

### 14-4 受影响文件清单（行数 = 设计期实测 2026-10-18；实施后读数见 §14-12）

| # | 坐标 | 改动 | 现行 | 预期增量 | 结论 |
|---|---|---|---|---|---|
| ① | `lib/chat/chat_models.dart` | 新增 `TurnMark`（含注释） | 713 | ≤ +8（⇒ ≤721） | 500–800 档，本批不触发拆分：只加一个类型别名，不动条目模型与构造点；拆分评审 = 保留（既有体量债按「不升级」处理，触发 = 改动条目模型） |
| ② | `lib/chat/chat_feed.dart` | 新增能力接口 `MarksTurns` | 154 | ≤ +18（⇒ ≤172） | 在 500 档内 |
| ③ | `lib/chat/chat_session.dart` | `implements MarksTurns`；`_apply` 内记账；`_prependedSeen`；`setKernel` 清空 | 1103 | ≤ +70（⇒ ≤1173） | 超 800 档：本批不动结构（全部是新增私有投影与一个 getter）；拆分预案见下表后（本批不触发） |
| ④ | `lib/chat/step_folds.dart` | `turns` 参数；边界并集；`_rescan` / `_tailFrom` / `_liveStart` 取边界 | 435 | ≤ +65（⇒ ≤500） | 500 档内，但**零余量**：落地实测达 500 即按「>500 行主动拆分审阅带」登记缝候选（边界并集段可独立成文件），收口后不得再往上加 |
| ⑤ | `lib/chat/chat_history_view.dart` | `_refold` 读账并传入（一处） | 3676 | ≤ +10（⇒ ≤3686） | 超 800 档：不在行结构 / 布局上动一行；沿用 §4 的拆分预案（首批行细节层），本批不触发 |
| ⑥ | `test/chat/step_folds_test.dart` | 新增「回合边界」用例组 + 有账/无账对拍 | 501 | ≤ +110（⇒ ≤611） | 测试档：结论见下表后「测试档口径」；本批不拆 |
| ⑦ | `test/chat/fold_view_test.dart` | 测试替身加 `MarksTurns`（空账默认）+ 两回合可见性用例 + **R13 跨回合增量用例（20 / 200 两跑）**；既有 102-110 用例不改 | 316 | ≤ +90（⇒ ≤406） | 测试档：同下；本批不拆 |
| ⑧ | `test/chat/turn_marks_test.dart` | **新档**：`ChatSession` 记账（起 / 止 / 前置 / 回退 / 换内核 / unprompted） | 0 | +≈120 | 新测试档（≈120 行，<500 档），不拆 |
| — | `test/chat/chat_history_rebuild_test.dart` | **零改动**，重跑取 A1/A4 读数 | 507 | 0 | — |
| — | `lib/kernel/**`（含 `transcript.dart`、`kernel_event.dart`）· `chat_session.dart` 以外的事件面 | **零改动** | — | 0 | — |

- **`chat_session.dart` 拆分预案（超 800 档；本批不执行）**：候选块 = 回合账投影（`_turns` / `_apply` 里的记账分支 / `turns` getter / `_prependedSeen`）；预算 = 约 90–130 行移到 `lib/chat/session_turns.dart`（拆成 mixin 还是独立协作者由拆分批定），拆后本档约 1000 行（1103 − 90…130）。
- 上述拆分的触发 = ① 台账「下一动先拆分（归批）」所指的那一批；② 任何**重构** `_apply` / 回合账结构的批——判据 = 该批 diff 挪动、拆分或改写 `_apply` 的既有分支，或改回合账的字段归属；只在既有分支里追加记账调用不算。本批在 `_apply` 追加 `_markTurn` 调用、既有分支不动（`chat_session.dart:167-181`）⇒ 不触发。
- **测试档口径**：体量档（>800 行 = 硬顶；>500 行 = 主动拆分审阅带，逐档给结论）对测试档同样适用——先例：`docs/design/thincoder-adapter.md:611`（>800 测试档给按 group 拆的缝候选）、`docs/batches/forge-gitee.md:228`（越 800 硬顶的测试档已拆包）。
- 本节测试档结论：⑥ 落地越 500（审阅带）⇒ 保留整档（用例按被测面分组），缝候选 = 越 800 时按 group 拆成文件；⑦、⑧ 落地均 <500 ⇒ 保留。落地读数见 §14-12。

### 14-5 关键决策记录（含被否）

**最近先例（对齐 ∥ 偏离）**：

- 对齐：内核侧按需声明能力、UI 只认声明了的那部分。接口实现坐标 = `lib/kernel/agent_kernel.dart:100-102`（`SelectsModel`）/ `:121-125`（`StartsPlans`）/ `:226-240`（`RewindsConversation`）；用法 = `chat_session.dart:341-345`（`SelectsModel`）/ `:496`（`RewindsConversation`）/ `:541-570`（`StartsPlans`）。
- 设计档章节 = `docs/design/thincoder-adapter.md` §4-F5（`:228`，`SelectsModel` 的协议映射）与 §4-F3 / §6-D8（`:212` / `:335`，`StartsPlans` 不声明的理由）；`RewindsConversation` 无设计档章节。
- 先例批次 = **无档**（本仓无该能力接口族的引入批）：`agent_kernel.dart` 的能力接口族为早期既有事实（`:100-102` / `:121-125` / `:226-240`）；最近的同形先例 = `AcceptsImageFiles`（`agent_kernel.dart:267`，按需声明能力的同一形状）。
- 偏离 = 无：折叠层仍是「按条目与边界扫描」的同一套做法，没有引入第二套数据源。

**公开源调查**：本仓无独立上游文档仓；相关第一手来源 = 本仓的回合事件面（`lib/kernel/kernel_event.dart:16-52`）与 thincoder 适配设计 `docs/design/thincoder-adapter.md` §19.2（unprompted 回合的来处）。ACP / thincoder 协议在 `session/load` 重放时是否给出回合边界：**未核（`unverified`）**；本设计不依赖它（重放退化见 §14-8-1）。

| # | 决策 | 理由 / 被否 |
|---|---|---|
| T1 | 边界 = **会话把回合账传给视图，再传给 `StepFolds`**（本批选定） | 事件面零改：起点、`unprompted`、`worked` 三个事实内核都已发（`kernel_event.dart:16-52`）；`worked` 的发出点已核 = `thincoder_kernel.dart:682-699` 的 `_endTurn`（unprompted 回合经 `:664-668` 走到它；`_turnStarted` 在 `_beginTurn` `:638` 设，自动回合同样非 null）；下标在 `TurnStarted` 那一刻由 `_transcript.length` 确定；独立能力接口 ⇒ 既有 feed 与测试替身不改。 |
| T2 | 被否：**新增一条边界标记条目**（feed / transcript 里可折叠层识别的项） | 内核不发它，只能在会话侧合成；一进 `_items` 就打乱 `idAt` / 编辑 / 回退 / 下标，重放没有它（同一会话两次打开折法不同）；还要在视图里给它一行或隐藏它，动到行结构，违反「不改折叠视觉形态」。 |
| T3 | 被否：**首项带回合标记**（`turnId` / `unprompted` 挂在条目上） | 要改所有可能开回合的条目类型与全部构造点（三个内核 + 测试）；「首项」在流式里由模型决定，语义要额外定义；重放同样没有标记（只有条目、没有回合事件），退化面与 T1 相同而改动面大一个数量级。 |
| T4 | 被否：**视图自己记边界**（监听 `isStreaming` / `isUnprompted` 翻转） | `ChatFeed` 只暴露这两个布尔（`chat_feed.dart:14-18`），拿不到 `worked` ⇒ 汇报轮折不了，不满足「汇报轮自己的 work 可折」。 |
| T5 | 被否：**按条目形状猜边界**（例如「答案后又出现工具卡」） | 单回合内本来就允许「答案 → 工具 → 答案」（`step_folds.dart:225-232` 的连跑规则就为它存在），与跨回合不可区分 ⇒ 会改掉既有单回合语义。 |
| T6 | 被否：**持久化回合边界**（重载后也正确） | 需要事件面：重放带回合事件，或条目带 `turnId`（`thincoder_events.dart:107-140` 的重放只有 `session/update` 条目）。本批不动事件面；给用户裁（§14-8-1）。 |
| T7 | 边界的**并集**里保留提示词（不只是账） | 旧会话、重放、子代理视图、测试替身都没有账；提示词是它们唯一的回合事实。并集让「有账的尾巴 + 无账的历史」在同一份折法里共存，且无账时逐下标等于今天。 |
| T8 | 账交给 `StepFolds` 时**不拷贝**，`StepFolds` 也**不持有** | 每次全路径通知都拷一份 = O(回合数) 每事件，长对话退化；不持有 ⇒ 不会拿到过期快照（会话只在 `_apply` 里改账，改了才通知）。 |
| T9 | 被打断的回合 `worked = null`（不折） | 与今天一致：`Transcript` 只在 `!interrupted && worked != null` 时把耗时写回提示词（`transcript.dart:151`），折叠据此跳过。 |

### 14-6 用例表

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| R1 | 正常：用户回合 + unprompted 汇报 | 用户回合（提示词·工具·中间文本·工具·答案一）+ 自动回合（工具·答案二），两条 mark | 上一回合的 work 折到**答案一之前**；答案一可见；汇报回合有一条自己的 work 折（`worked` 来自它的 mark）；答案二可见 |
| R2 | 正常：汇报回合没有工具步 | 自动回合只有一条 `AssistantTextItem` | 不折（非思绪条目 < 2）；答案可见 |
| R3 | 边界：连续两个 unprompted 回合 | 两条自动 mark，各自的工具 + 答案 | 各自折到各自答案之前；两条答案都可见；两个 `worked` 各归其回合 |
| R4 | 边界：用户回合未完成就回调 | 用户回合进行中（live），回调在它结束后才起（`_pendingAuto` 顺延，`thincoder_kernel.dart:662-667`） | live 期间不折；两回合结束后同 R1 |
| R5 | 边界：空自动轮 | 两条 mark 同下标（中间没有条目） | 合并成一条边界（取靠后者）；不产生第二个折 |
| R6 | 边界：旧会话 / 重放（无账） | mark 为空，条目照旧 | 与今天逐下标相等（提示词规则） |
| R7 | 边界：重放后又起一个新回合 | 旧条目无账 + 一条新 mark | 旧回合的窗在新 mark 处收口（旧回合答案可见）；新回合按 R1 |
| R8 | 边界：回退（`Rewound`） | 截断点落在某回合中间 | 跨过 / 之后的 mark 删除；剩下的照用；被裁回合迟到的 `TurnEnded` 按 `turnId` 找不到 ⇒ 不改账；不抛 |
| R9 | 边界：前置历史（`HistoryPrepended`） | 账上有 mark | 整体平移前置条数；折法不变 |
| R10 | 边界：claude_code 排队消息被取用 | 提示词先落地（下标 p），`TurnStarted` 后到（mark 起点 p+1） | p 自成一条空窗（不折）；回合本体从 p+1 起折；页脚仍挂在 p（`prompt` 由 `indexOf(turnId)` 给出） |
| R11 | 错误：坏形 mark | mark 越界（`start < 0` / `start > count`）/ 乱序 | 丢弃该条；其余照常；不抛（`start == count` 不是越界） |
| R12 | 错误：被打断的回合 | `TurnEnded(interrupted: true)` | 该回合不折（`worked` null）；其它回合不变 |
| R13 | 边界：跨回合边界的**增量**路径（评审 #1/#3；前提见 §14-3） | 真实顺序：A 回合的条目与 `TurnEnded(A, worked)` 已到位，再 `TurnStarted(B)`（此刻 `start == count`）→ B 的首条条目；每步经 feed 通知 + `pump`（`fold_view_test` 的替身同时实现 `MarksTurns`）；替身必须按生产语义翻转 `isStreaming`（`TurnStarted` → true、`TurnEnded` → false，评审 #12）；前史 20 / 200 回合各跑一次；另加一跑变体：`TurnEnded(A)` 不落 false，保持 true 到 `TurnStarted(B)` | 主跑：`TurnStarted(B)` 之后 A 的 work 折叠仍在（`WorkFoldLine` 找得到）、答案一可见；B 的窗从自己的起点开始（它首条落地后同 R1）；两跑逐项相等。变体：断言同主跑——`TurnEnded` 一跳 live 未变、条数未增 ⇒ 视图走全路径（`chat_history_view.dart:1394-1395`），A 的折叠最迟在 `TurnStarted(B)` 算对；变体红 ⇒ 实现把 A 的重算押在「`TurnEnded` 落 false」上（拿空范围的 `extend` 当重扫），按缺陷上报，退化 = A 的折叠停到下一次全路径 |

### 14-7 兼容矩阵

| 场景 | 账 | 折叠行为 |
|---|---|---|
| 本进程内发生的回合 | 有 | §14-2 新规则 |
| 会话开头的历史条目（前置 / 未经过回合事件） | 无 | 提示词边界（今天） |
| `session/load` 重放（`thincoder_kernel.dart:271-286`；重放只有 `session/update`） | 无 | 提示词边界（今天）；重载后第一个新回合起恢复正确 |
| 重载后又起新回合 | 新增 mark | 该回合的前一条（无账）提示词回合也在新 mark 处收口 |
| 停止的回合 | mark 在、`worked` null | 不折（今天） |
| 前置历史 | 有 | 平移 |
| 回退 | 有 | 裁剪 |
| 换内核 | 清空 | 提示词边界 |
| 子代理视图（`SubagentFeed`，不实现 `MarksTurns`） | 无 | 提示词边界（今天） |
| 回合刚起、还没有条目（mark 的 `start == count`） | 有（空边界） | 上一回合照常折；新回合不折（live，窗为空）；它第一条落地后从自己的起点折 |
| 坏形 / 空账 | — | 丢弃（`start == count` 不丢）/ 退回今天；不崩 |

### 14-8 边界（本批不做）与失败面

1. **重载不保留回合边界**。重放没有回合事件；协议侧是否给重放回合边界**未核（`unverified`）**。本批不为它改事件面。要让重载后也正确 = 给重放加回合事件、或给条目加 `turnId`（T6）⇒ **另立批、先给用户裁**。
2. 不改 unprompted 回合的语义（`TurnStarted(unprompted: true)` / 不自起轮 / 释放规则 / `_pendingAuto` 顺延）；不改 thincoder 仓。
3. 不改视觉形态：`WorkFoldLine` / `StepsFoldLine` 的文案与图标、展开交互、粘顶 / 选择区 / 滚动锚定都不动。副作用两处，都是本批要的：汇报回合**会新出现一条它自己的** Worked 行；它的答案下面**没有**回合页脚（`TurnFooter` 要一条用户消息承载 `worked` / `usage`，`chat_history_view.dart:274-294`）——本批不加。
4. 视图的 `_liveStart`（提示词派生，`chat_history_view.dart:145-152`）不动：它服务稳态门与「回复开头」滚动，与折叠边界是两件事。
5. 不改 `rowAt` / `refreshTail` / `mergeThoughts` / 快路径判据 / 图片缓存。
6. 不改需求档（配对条目 F4 已落盘）、内核、`Transcript`、`KernelEvent`。

**失败面（写死退化，不崩）**：`turns` 空 ⇒ 今天；mark 越界（`start < 0` / `start > count`）/ 乱序 ⇒ 丢该条（`start == count` 不是越界）；`worked` null ⇒ 该回合不折；提示词落在 mark 之后 ⇒ 该提示词是一条空窗（`last <= start` ⇒ 不折），不产生第二个折；视图读账时 feed 抛错不在设计内（账是普通 List）。

### 14-9 回滚

- **一行回滚**：`_refold` 不传 `turns`（`turns: const []`）⇒ 折叠立即回到今天的提示词规则；账与接口留着不消费，无残留行为。
- **整批回滚**：revert ①–⑤ 五个产品文件与 ⑥–⑧ 三个测试文件；账是内存投影，无数据迁移、无持久化残留。

### 14-10 UI / 交互决定（全部落地，无 open）

- 无新 UI、无新 l10n 键、无新设置项。
- 汇报回合新增一条它自己的 Worked 行（要的行为，不是新形态）。
- 汇报回合答案无回合页脚（边界，见 §14-8-3）。
- 展开 / 关闭、贴底规则、`_unfoldedTurns` 的既有行为不变。
- 无 open 项。

### 14-11 验收对照（回指本批要求）

| 本批要求（需求档 F4，`docs/requirements/chat-streaming.md:32-34`；用户 2026-10-18 报告：上一回合答案被折走） | 落点 | 机检判据 |
|---|---|---|
| ① 每回合（含 unprompted）有折叠可见边界；work 只折本回合、折到本回合答案前；上一回合答案可见 | §14-2 · §14-3 | A：`step_folds_test` 新用例（R1/R3）断言上一回合 `work.end == 答案一下标`、`rowAt(答案一).item == true` |
| ② 汇报落地后上一回合答案不被折走；汇报轮自己的 work 可折、答案保留 | §14-2 · §14-3 | B：`fold_view_test` 新用例同时找得到两条答案、`WorkFoldLine` 两条；C：`turn_marks_test` 断言账的起 / 止 / `worked` |
| ③ 单回合内「中间回答被折」不变 | §14-2 窗内规则 4–6 | F：`fold_view_test.dart:102-110` 不改且全绿 |
| ④ 保留既有性能读数与既有测试面 | §14-3 性能面 | E：`chat_history_rebuild_test` 零改动重跑，A1 六类外壳 0/0、`ChatItemView` 每增量恰 1；A4 非 0 恰 1 帧 @37；不同 ⇒ 判缺陷 |
| ⑤ 跨回合边界的**增量**路径：`TurnEnded(A)` → `TurnStarted(B)`（`start == count`）→ B 首条追加（评审 #1/#3） | §14-2 规则 4 · §14-6 R13 | G：`fold_view_test` 新用例（每步 notify + pump，20 / 200 回合各一跑）——A 的折叠在 `TurnStarted(B)` 之后仍在、答案一可见；两跑结果逐项相等 |

**机检细则**：A/B/C/G 见 §14-6 的 R1–R13；D（退化）= 有账与无账在同一份条目上逐下标对拍（`stepsAt` / `workAt` / `turnEndingAt` / `rowAt` 三态 / `shownAt`），无账一侧必须等于今天；E = 既有两个读数逐项相等（本批不新增读数、不改口径）。

### 14-12 实施偏差记录（实施后补记，2026-10-18）

实施结果对 §14 有三条要记：三处行数超预算（①）、`step_folds.dart` 压线与缝候选（②）、`Rewound` 的裁剪口径（③）；机制结论（边界并集 / 回合账 / 窗内规则）未变。行数 = 换行数实测（2026-10-18 工作树）。

**① 行数：三处超出预算；超出的来源都是评审修复或测试增量，无功能裁剪。**

| 文件 | 预算（§14-4） | 实测 | 结论 |
|---|---|---|---|
| `lib/chat/chat_models.dart` | ≤721 | 718 | 在预算内（余 3） |
| `lib/chat/chat_feed.dart` | ≤172 | 163 | 在预算内（余 9） |
| `lib/chat/chat_session.dart` | ≤1173 | **1187（+14）** | 超：+14 = 评审 🔴 修复的 `_cutsAtMessage`（`chat_session.dart:185-192`）与 `_apply` 的 `before` / `atMessage` 管线（`:171-174`） |
| `lib/chat/step_folds.dart` | ≤500 | **500（压线）** | 零余量，见 ② |
| `lib/chat/chat_history_view.dart` | ≤3686 | 3685 | 在预算内（余 1） |
| `test/chat/step_folds_test.dart` | ≤611 | **618（+7）** | 超：+7 = R11 乱序用例 + 块间空行 |
| `test/chat/fold_view_test.dart` | ≤406 | **477（+71）** | 超：+71 = R13 逐步行进用例机 + `TurnEnded` 不落 false 的变体 + fixture |
| `test/chat/turn_marks_test.dart` | 新增（§14-4 估 ≈120） | 243 | 新档，<500 档 |

**② `step_folds.dart` 落地 500 整。** 按 §14-4 ④ 的口径登记缝候选：边界并集段 = `_TurnBoundary`（`step_folds.dart:33-35`）+ `_boundaries`（`:281-321`），约 44 行（含注释），可独立成文件。触发 = 本档下一次要往里加行时先拆。**收口后不得再往上加。**

**③ `Rewound` 裁剪 = 跨过且非消息点。** §14-3 表的 `Rewound` 行已按实现改写。截断点落在下一回合的提示词上时，该提示词属下一回合、不属被截的回合 ⇒ 不删上一回合的 mark；判别用例 = `turn_marks_test` 的「a rewind at the next message keeps the turn before it」（`:203`，去掉 `!atMessage` 该用例变红）。实现坐标：`_cutsAtMessage`（`chat_session.dart:185-192`）+ `Rewound` 分支（`:234-247`）。

