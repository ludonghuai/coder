# 对话流式渲染（chat-streaming）设计档

> 板块：对话渲染（chat-streaming）· 范围仓：baocode。
> 配对需求档：`docs/requirements/chat-streaming.md`（F1–F3 + N1）。
> 状态：设计稿 v3（v2 设计评审已过；§12 记 4 处实施偏差）· 2026-10-17 · 行号 = 各节标注时点的快照（实施按符号定位）。
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

**稳定点**：`from = min(最后一条非排队 UserMessageItem 的下标, 末尾思绪连跑起点, 末尾快步骤连跑起点)`。`[0, from)` 的数组 / 映射原样复用；`[from, count)` 用与全量相同的三段扫描重算。理由（即 §2.3 的先例注释）：追加只会在尾部接上连跑、或给最后一回合补内容；`UserMessageItem` 不是快步骤，连跑不跨提示词。

**实施偏差（§12-1）**：`[from, count)` 不是「只 append 新条目」——`extend` 先用 `_tailFrom(itemAt, count)` 求稳定点，再用 `itemAt` 重读 `start..count` 后 `_rescan`。回合结束时同下标条目会原地替换（提示词补 `worked`、状态行位置换成答案），只 append 会让 `fold_view_test` 两条既有用例红。代价 = 8 读/增量（与历史长度无关，20 / 200 两跑相同）。

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

| # | 坐标 | 改动 | 基线 | 实测 | 增量预算 | 结论 |
|---|---|---|---|---|---|---|
| ① | `lib/chat/chat_history_view.dart` | 快路径判据与快照 · `_liveTick` + `_LiveItem` · `liveRow` · `_refold` 调用规则（含换 feed） · 图片缓存 · `refreshTail` 调用 | 3358 | **3541** | ≤ +110（⇒ ≤3468）；不拆档（见下拆分计划） | 超 73 行（§12 记档） |
| ② | `lib/chat/step_folds.dart` | `count` / `rowOf` / `extend`（原地、尾部重算）/ `refreshTail` / 尾部三段扫描 | 353 | **435** | ≤ +120（⇒ ≤473，<500） | 在预算内 |
| ③ | `lib/chat/widgets/markdown_view.dart` | 50ms 节流 + trailing Timer + 计时字段 | 832 | **875** | ≤ +45（⇒ ≤877） | 在预算内（余 2 行） |
| ④ | `test/chat/chat_history_rebuild_test.dart` | F1 计数用例 + N1 脚本（短 / 长历史两跑） | 134 | **433** | ≤ +120（⇒ ≤254） | 超 179 行（含 A2/A3/B1/T3） |
| ⑤ | `test/chat/step_folds_test.dart` | 增量与全量逐项对拍 | 374 | **501** | ≤ +90（⇒ ≤464） | 超 37 行（B2 对拍） |
| ⑥ | `test/markdown_test.dart` | F3 解析上界 + 最终态一致 | 397 | **504** | ≤ +80（⇒ ≤477） | 超 27 行（C1/C2/C3/T10） |
| — | `lib/chat/chat_feed.dart` · `chat_session.dart` · `lib/kernel/transcript.dart` · `chat_screen.dart` | **零改动** | — | — | 0 | — |
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
8. **数据模型 / 事件形态 / 内核 / 依赖 / 列表实现**零改动：`ChatFeed` 接口不加方法，`ChatSession` / `Transcript` 不加字段。
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
- **代价 / 读数**：每增量重读最后一回合，实测 8 读/增量，与历史长度无关（B1① 20 / 200 两跑逐次相等）。

### 12-2 `extend` 的防御性断言（§3.4）

- **原设计**：合法调用条件由视图侧判（`count >= folds.count`），`extend` 内无断言。
- **实际做法**：`extend` 开头 `assert(count >= _items.length)`，并注明 `StepFolds.none` 是共享单例、不可就地 grow。
- **理由**：防御性收紧；调用方 `_refold` 已先判 `count >= _folds.count`，误用应在调试期立即暴露。
- **代价**：无运行时成本（`assert` 只在 debug 生效）；共享单例下误用会立即失败，而非静默改脏全局。

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

## 变更记录

- 2026-10-17 · 首版（F1–F3 + N1 设计：快路径判据 / `_LiveItem` / 折叠增量 / 图片缓存 / markdown 节流 / 量法与基线流程）。
- 2026-10-17 · v2：设计评审第 1 轮 15 条落档（liveRow 合并思绪 / A3 拆数据层与终态 / extend 同 feed 与原地语义 / 图片基线更正 / 读数先打印后断言 / MarkdownView 共享面 / 前缀条件 / 走查进验收 / 拆档预案 / 832 与四个 / 计数补三项 / 计时前置用例 / 文档地图备注）。
- 2026-10-17 · v3：实施偏差记档（§12：`extend` 重读最后一回合 / `assert` 与共享单例 / A1 bubble 口径 / 图片键只比 `itemCount`）；§4 表改实测（3541 / 435 / 875 / 433 / 501 / 504，四项超限记档）；§6.1-A1 补测量口径；机制结论未改。
