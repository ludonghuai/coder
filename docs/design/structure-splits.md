# 结构拆分：越界档的拆分设计

> 板块：结构治理（跨板块）。状态：设计待复审（2026-10-23）。
> 台账：#150（SPLIT-1…4）· #22（kernel 超预算）· #72（step_folds 边界并集段）。
> 需求来源：用户 2026-10-23 07:21「开」——先拆已越界的档，再拆 #150 的四个 >800 档。

## 1 目标与范围

**模块目标**：把五个越界档按职责拆成多个文件，每档回到自己的行数界内，行为零变化、调用方零改动。

**功能点（每条可验证）**

1. `thincoder_kernel.dart` 拆到 ≤500 行（本批目标；设计 ㉓ 的 ≤1345 预算同时满足）。
2. `step_folds.dart` 按 #72 抽「边界并集段」后 ≤500 行。
3. `composer.dart` 拆到 ≤800 行。
4. `chat_session.dart` 拆到 ≤800 行。
5. `chat_models.dart` 拆到 ≤800 行（只需搬出 ≥40 行的一段）。
6. 被搬符号的签名与可见性逐字不变；其他文件不改一行。

**边界（本设计不做）**

- 不改任何行为：不重命名、不合并语句、不调换调用顺序、不新增分支。
- 不动任何测试档；不为拆分新增用例。
- 不动 `lib/ide/**`（含 `ide_scm_view.dart`，#47 另批）与 `lib/browser/btest/**`（#55 在飞）。
- 不重构 `composer.dart` 与 `chat_session.dart` 的 btest 状态面（#55 所有，见 §4.3 / §4.4）。
- 不把字段提升为公开、不拆协作类（那会改可见性或生命周期）。

**依赖**：`docs/design/thincoder-adapter.md` §18.4（会话面缝登记）与 §21.3（`part` 先例）；`docs/design/browser-biz-test.md` §4（SPLIT-1…4 缝表）；台账 #22 / #72 / #150 / #153。

**台账结案对照（本批做完后各条能否关）**

| 台账 | 条目 | 本批达成条件 | 结案 |
|---|---|---|---|
| #22 | kernel 1453 > 设计 ㉓ 预算 1345 | §4.1 落完、主档 ≤500（蕴含 ≤1345）；读数 = §5 第 2 步行数命令 | 达标记：实施后由父侧核销 |
| #72 | step_folds 边界并集段 | §4.2：`_TurnBoundary` + `_boundaries` 出档到 `step_folds_boundaries.dart`，主档 ≤500 | 达标记：实施后由父侧核销 |
| #150 | 四个 >800 档：composer · thincoder_kernel · chat_session · chat_models | 对应批档 §2 四行：kernel = 行 1（§4.1）· composer = 行 3（§4.3）· chat_session = 行 4（§4.4）· chat_models = 行 5（§4.5） | **不结案**：四个只落三个；`ide_scm_view.dart`（批档 §2 行 6）归 #47，不在本批；四个全落才关 |
| #153 | btest 四个新档超设计预算（mode 787 / policy 375） | 本批不动 `lib/browser/btest/**`（#55 在飞） | 不结案：随 btest 面下一动另批 |

**先例与勘察（设计依据）**

- **最近先例**：`lib/kernel/thincoder/thincoder_choices.dart` —— `part of 'thincoder_kernel.dart'` + 顶层函数 `_modeOf(ThincoderKernel kernel)` + 内核类里一行委托。坐标：`docs/design/thincoder-adapter.md` §21.3（`:2513-2518`）。本设计所有 `part` 段沿用这一形态；未偏离。
- **为什么不是 btest 三档**：`btest_run_state.dart` / `btest_run_end.dart` / `btest_status_switches.dart` 属 #55（在飞：文件已在工作树、未提交），形态未定，不作为先例——设计引用只指向稳定的先例。
- **勘察（设计档）**：读 `docs/design/thincoder-adapter.md` §18.4（`:1683` 会话面缝候选：回合生命周期 + 队列整段出档）与 §21.3（`:2513-2518` part 形态与「类成员不能跨 part ⇒ 一行委托」）。
- **勘察（登记面）**：读 `docs/design/browser-biz-test.md` §4（`:638-659` 的 SPLIT-1…4 缝表与命名）与台账 #22 / #72 / #150 / #153。
- **结论**：有先例可直接沿用；SPLIT-2 的审批面、SPLIT-3 的 `session/mode_state.dart` 作为命名与一段切法保留。

## 2 现状基线（2026-10-23 实测）

行数口径 = 行尾换行符个数（与 `wc -l` 同口径）；括号内为批档 §1 的基线，差 1 行来自「末行计入」的口径差。

| 档 | 本设计实测 | 批档 §1 | 界 | 超出 |
|---|---|---|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | **1461**（1453） | 1453 | 1345（设计 ㉓）· 本批目标 500 | 超 116 / 961 |
| `lib/chat/step_folds.dart` | **500**（501） | 501 | 500 | 口径差 1；按批档口径超 1 |
| `lib/chat/composer/composer.dart` | **2466**（2467） | 2467 | 800 | 超 1666 |
| `lib/chat/chat_session.dart` | **1492**（1493） | 1493 | 800 | 超 692 |
| `lib/chat/chat_models.dart` | **839**（840） | 840 | 800 | 超 39 |

工作树在飞改动（非计数口径）：kernel +28/−1 与 chat_session +8（#50）；composer 现读 2346（#55 已把 btest 状态行段出档到 `lib/browser/btest/btest_status_switches.dart`，未提交）。本设计的行数与坐标按设计时实测计；实施以符号名为锚、行号为辅助。

**开工前置**：见 §5 行 0 的两极口径（当前态 ∥ 每步开工前）。

## 3 机制选型

### 3.1 决定选型的两条 Dart 事实

1. **类体不能跨档**：一个 `class` 的成员必须写在一个文件里。跨档只能把「方法体」搬到同库顶层函数，类里留一行委托——§21.3 已用此形态（`_modeOf(this)`）。
2. **私有标识符是库级私有**：`_slot` / `_turn` / `_controller` / `_kernel` 只有在同一 library（`part of`）里可见；`export` 只重导出公开名。

### 3.2 选型表（同一档只用一种机制）

| 档 | 机制 | 理由 |
|---|---|---|
| kernel | `part` | 已有 `part 'thincoder_choices.dart'`（`:30`）；九段都要读私有字段 |
| step_folds | `part` | 边界段读 `_items`；新档必须是同库 |
| composer | `part` | `ChatComposerState` 私有成员 + 私有 widget 类（`_SendButton` 等）都不能 export |
| chat_session | `part` | 全部投影读 `_kernel` / `_transcript` / `_btest` |
| chat_models | 新档 + `export` | 被搬段不引用任何私有成员 ⇒ 可独立成 library（只依赖 `package:path`）：新代码可只 import 它，边界由编译器强制（独立 library 看不到 `chat_models.dart` 的私有成员）；`export` 让原路径的 136 个调用方零改动 |

### 3.3 搬运形态（所有 `part` 段唯一形态）

- **新档落点与命名**：与 owner 同级的用 `<owner>_<face>.dart`（kernel · composer）；owner 有专属子目录的用 `<face>.dart` 落在该子目录（chat_session ⇒ `lib/chat/session/`）。
- **首行** `part of '<相对路径>';`：同级写 `part of '<owner>.dart';`；子目录写 `part of '../<owner>.dart';`（例：`lib/chat/session/mode_state.dart` 首行 `part of '../chat_session.dart';`）。
- 内容 = 顶层私有函数 `<name>Of(Owner owner, …)`；owner 类里留**一行委托**，签名与可见性逐字不变；`static` 方法写成 `static X _x(…) => _xOf(…)`。
- **原名已以 `Of` 结尾时**：委托函数写成 `<name>OfOf`，原名与签名一律不动。实例：`_dropModelOf` ⇒ `_dropModelOfOf`（`lib/kernel/thincoder/thincoder_kernel.dart:323` / `lib/kernel/thincoder/thincoder_turns.dart:178`）。
  另一实例：`_dropTitleOf` ⇒ `_dropTitleOfOf`（`lib/kernel/thincoder/thincoder_kernel.dart:350` / `lib/kernel/thincoder/thincoder_title.dart:33`）。
  理由：原名是行为名，削成 `_dropModel` 会改签名（违反 §1 功能点 6）；双 `Of` 只是委托函数的机械后缀，可逐条核对。
- 搬动只做三件事：① 函数体移到新档；② 对 owner 成员的引用加 `owner.` 前缀；③ 原位置换成一行委托。
- **字段与后备存储留 owner**：类字段（含 `static const`、`late final`、后备集合）不能跨档；缝表点名的字段只搬读它的投影方法，字段本身不动。
- **注解随委托逐字保留**：`@override` / `@protected` / `@visibleForTesting` 等注解跟着委托行，一个不改。
- **缝的判据**：缝表点名的符号必须是本源档的声明；import 进来的名字不算缝，不能写进搬出清单。
- part 档之间不互相 `import`；共用符号仍由 owner 档持有。

### 3.4 被否方案

| 方案 | 被否理由 |
|---|---|
| 有私有耦合的档用「新档 + export」 | 私有成员不可见，只能提升可见性 ⇒ 违反功能点 6 |
| 拆成协作类（组合 + 回调） | 要新增字段、改构造与生命周期 = 语义面改动，不是纯搬运 |
| `extension` 承载私有方法（btest SPLIT-5 用过的形态） | 那只对公开成员成立；私有成员配隐式 `this` 不是已验证形态，风险高于收益 |
| 只抽登记缝（SPLIT-2 审批面 108 行等） | 算术上到不了目标：kernel 要搬 ≥960 行、composer 要搬 ≥1660 行 |
| 顺手重构（改名 / 合并逻辑 / 调顺序） | 行为零变化是硬约束 |

## 4 每档缝表

### 4.1 kernel（1461 → 目标 ≤500）

**实测（2026-10-23，第 2 步已落，`part` ×9）**：主档 **480**（≤500）· 九档 170 / 111 / 187 / **279** / 84 / 131 / 117 / 48 / 98（最大 279 ≤500）· 53 个成员出档、53 条委托共 **113** 行 · 逐块比对 `diffs: 0` · 反推校验 233 / 233 非空行一致。

委托实测 ≈2.13 行/成员（113 ÷ 53；`owner.` 前缀与折行所致）。原估「≈45 行委托」按一成员一行计，低估一倍有余；§4.4 的 chat_session 预算按同一实测口径重算。

拆分前现状（下列坐标均为拆分前口径）：import 26（`:1-28`：26 条 import + 分组空行 `:5` / `:9`）· `part` 指令 1（`:30`）· `class ThincoderKernel` `:42-1386`（1345）· 顶层函数 `:1388-1461`（74）。

| # | 段 | 搬什么符号（点名） | 现坐标 | 搬出 | 新档（估） |
|---|---|---|---|---|---|
| 1 | 启动与握手 | `_ensureStarted` `_launch` `_openSession` `_applyStartMode` `_handshake` `_fail` | `:239-369` `:469-504` | ≈167 | `thincoder_lifecycle.dart` ≈200 |
| 2 | 记录与恢复 | `_openRecord` `_pickUp` `_pickUpKept` `_openNew` | `:370-468` | 99 | `thincoder_records.dart` ≈110 |
| 3 | 释放与收尾 | `_teardown` `_closeSession` `prepare` `restart` `release` `_canClose` `_releaseWhenIdle` `dispose` `_exited` `_sayWaiting` | `:505-646` `:1171-1218` | ≈190 | `thincoder_release.dart` ≈220 |
| 4 | 回合生命周期与队列 | `send` `_drain` `_deliver` `_beginTurn` `_turnReport` `_dropModelOf` `_endTurn` `cancel` `cancelQueued` `sendQueuedNow` `canRevertNow` | `:647-929` | 283 | `thincoder_turns.dart` ≈320 |
| 5 | 改名与标题 | `renameConfirmed` `rename` `_dropTitleOf` + 顶层 `_pumpTitle` | `:930-958` `:1388-1435` | ≈77 | `thincoder_title.dart` ≈90 |
| 6 | 回退 | `revertPlan` `applyRevert` `_revertFailed` `rewind` `_rewindFailed` + 顶层 `_planOf` `_revertFiles` `_revertSkips` `_revertFailures` | `:959-1054` `:1436-1461` | ≈122 | `thincoder_revert.dart` ≈140 |
| 7 | 服务端请求与审批（SPLIT-2） | `_serverRequest` `answer` `_resolveApprovals` `_isBrowserTool` | `:1055-1162` | 108 | `thincoder_requests.dart` ≈130 |
| 8 | 事件接收 | `_receive` `_noteFirstFrame` `_notification` `_content` `_turnKey` | `:1163-1170` `:1219-1234` `:1235-1259` | ≈49 | `thincoder_inbound.dart` ≈60 |
| 9 | 图像与上下文工具 | `_contexts` `_imageExtension` `_runId` `_letters` `_random`（`imageMaxBytes` / `turnMaxBytes` 为 `static const` 字段，留 owner） | `:1288-1387` | ≈100 | `thincoder_images.dart` ≈115 |

- **实测留档（主档 480 ≤500）**：import 26 · `part` 指令 10（含既有 `thincoder_choices`）· 类头/构造/字段/getter · 选择面接线 · 53 条委托 113 行；另含段间空行与指路注释。
- 九个 part 档每个 ≤500（实测最大 `thincoder_turns.dart` **279**）。
- **对外暴露**（part 档不是 import 目标，下列每一项仍从原路径 `lib/kernel/thincoder/thincoder_kernel.dart` 可见）：

| 组 | 公开成员 |
|---|---|
| 状态与只读 | `descriptor` `health` `sessionId` `pendingModel` `pendingTitle` `stopped` `loadingHistory` `hasEarlierHistory` `loadingEarlier` `loadEarlier` `contextWindow` |
| 生命周期 | `prepare` `restart` `release` `dispose` |
| 回合 | `send` `cancel` `cancelQueued` `sendQueuedNow` `canRevertNow` `renameConfirmed` `rename` |
| 回退与审批 | `revertPlan` `applyRevert` `rewind` `answer` |
| 选择面 | `mode` `permission` `model` `effort` `suggestFiles` |
| 常量 | `imageMaxBytes` `turnMaxBytes` |
| 构造与接口 | 构造函数与 `:42` 行 `implements` 清单里的能力接口 |

调用方 = `lib/kernel/kernel_registry.dart:6` · `lib/kernel/mock/mock_kernels.dart:8` · 测试档 5 个（import 反推，见 §5 第 2 步）；**import 路径不变，调用方零改动**。

### 4.2 step_folds（500 → ≤500，#72 边界并集段）

现状：`_TurnBoundary` `:35-44` · `StepFolds` `:45-395` · 自由函数与 `StepTally` `:396-500`。

| 段 | 搬什么符号 | 现坐标 | 搬出 | 新档 |
|---|---|---|---|---|
| 边界并集段（#72） | `_TurnBoundary` · `_boundaries`（窗口合并：消息边界并入回合标记，`merged where they meet`，方法注释 `:281-283`） | `:35-44` `:284-321` | ≈42 | `lib/chat/step_folds_boundaries.dart`（part）≈45 |

- 主档 500 − 42 + 1 行委托 + 1 行 `part` ⇒ **≈460 ≤500**。
- `_rescan`（`:191-279`）留在主档：它消费 `windows`，搬它就要拆函数体，超出「整方法搬运」。
- 被否的替代：把 `isQuickStep` / `standsOutOfWork` / `isUnderWay` / `mergeThoughts` / `StepTally` / `commandAction`（`:396-500`，105 行）整段抽走——算术上也能达标，但 #72 登记的是边界段，抽这批等于 #72 不结案。
- **对外暴露**（沿用 `lib/chat/step_folds.dart` 原路径，调用方零改动）：

| 组 | 公开成员 |
|---|---|
| 折叠模型 | `StepFoldKind` `StepFold` `StepRow` `StepFolds` |
| 判据函数 | `isQuickStep` `standsOutOfWork` `isUnderWay` `mergeThoughts` |
| 步骤计数 | `StepAction` `StepTally` `commandAction` |

调用方 = `lib/chat/chat_history_view.dart:33` · `lib/chat/widgets/fold_line.dart:7` · `test/chat/step_folds_test.dart` · `test/chat/fold_view_test.dart`。

### 4.3 composer（2466 → ≤800）

约束：`ChatComposerState`（`:133-2179`，约 2046 行）不能跨档 ⇒ 搬方法体、留一行委托。

| # | 段 | 搬什么符号（点名） | 现坐标 | 搬出 | 新档（估） |
|---|---|---|---|---|---|
| 1 | 工具栏与小部件 | `_buildToolbar` · `ComposerPermissionSwitch` · `_PolishButton` · `_ContextRing` · `_RingPainter` · `_SendButton` | `:2051-2460` | ≈410 | `composer_toolbar.dart` ≈420 |
| 2 | 编辑面（图片/文件/草稿） | `_initialPool` `_createController` `_paste` `_nextPastedNumber` `_references` `_referredImages` `_addImages` `_numbered` `insertFiles` `_copyToHost` `_picturesIn` `_insertTags` `_canSend` `_takeDraftFiles` `_takeDraftMessage` `_saveDraft` `_handleDraftChanged` `_inAtom` `_shownOfText` `_ShownOfText` `_hasWords` `_handleEditorChanged` | `:201-898` 内 | ≈450 | `composer_editing.dart` ≈460 |
| 3 | 菜单与键盘 | `_suggestion` `_suggestionKey` `_suggestionKeyContext` `_lookups` `_lookUpFiles` `_padTrailingTokens` `_findTrigger` `_caretX` `_closeMenu` `_menuOwner` `_menuRegistered` `_syncMenuRegistration` `_moveHighlight` `_accept` `_handleKey` `_caretAtStart` `_caretAtEnd` `chatContextKey` `chatCommands` `chatComposing` `_nextMode` `_buildMenu` | `:616-628` `:899-1143` `:1695-1706` | ≈330 | `composer_menu.dart` ≈340 |
| 4 | 指针与拖放 | `_attachContext` `_ghostAt` `_ghost` `_ghostFiles` `_ghosting` `_dropOffset` `_dropStashes` `_showGhost` `_hideGhost` `_removeGhost` `_editGhost` `fileDragOver` `fileDragLeave` `fileDrop` `_dropFiles` `_menuPressAt` `_handleMenuPointerDown` `_handleMenuPointerUp` `_showContextMenu` `_selectAll` `_clickSlop` `_clickDownAt` `_clickWindow` `_clickUpAt` `_clickOnSelection` `_secondClick` `_handleClickDown` `_handleClickUp` | `:1144-1286` `:1754-1882` | ≈330 | `composer_pointer.dart` ≈340 |
| 5 | 生命周期与视图 | `initState` `didUpdateWidget` `_handleSettingsChanged` `dispose` `focus` `didChangeDependencies` `_isComposing` `_handleFocusChanged` `editorScrollPosition` `_editor` `_shownBuilt` `_editorColors` `build` `_built` `_builtFrom` `_hovers` `_buildInputs` `_buildBox` `_buildEditor` `_buildEditorBody` `_maxEditorHeight` `_buildMarkdownEditor` | `:342-392` `:642-687` `:1507-1753` `:1883-1931` | ≈360 | `composer_view.dart` ≈370 |
| 6 | 消息与提交 | `_polishText` `_polish` `_buildMessage` `_editorContext` `_dismissEditorContext` `_showsStop` `_submit` `_acceptSuggestion` `_historyAt` `_historyDraft` `_historyShown` `_recalling` `_sentPrompts` `_leaveHistory` `_showPrompt` | `:629-641` `:1287-1506` | ≈230 | `composer_message.dart` ≈240 |

- **「搬出」为指示值**（按点名方法与坐标区间估）：坐标只用于定位，不参与加总；判据以行数门为准（主档 ≤800、新档 ≤500）。
- **不在本批**：`_buildBtestStatus`（`:1932` 起）与 `_btestSwitch`（`:2031-2050`）归 #55（在飞实施轮）；工作树中该段已由 #55 搬出（未提交），本步实施时按符号名定位。本批不碰 `lib/browser/btest/**`、不重构 btest 状态面。
- **留在主档**：import（50）· `_Trigger`（`:54-82`，30）· `ChatComposer` 构造与字段（`:84-130`，50）· State 字段与共享助手 `_rankOthers`（`:136-200`，65）· 约 65 行委托 · btest 段 119 ⇒ **估 379–520 行 ≤800**（下界 = 上列各项之和）。
- **对外暴露**：`ChatComposer` · `ChatComposerState` · `ComposerPermissionSwitch`。调用方 = `lib/chat/chat_screen.dart:35` · `lib/chat/chat_history_view.dart:27` · `test/composer_test.dart` · `test/kernel_ui_test.dart`。
- **风险**：State 方法体里 `setState` / `context` / `widget` / `mounted` 改成 `state.setState` 等，指向同一对象，行为不变；`build` 仍在 State 内，子树与重建时机不变。

### 4.4 chat_session（1492 → ≤800）

现状：自由类 `:30-105` · `ChatSession` `:106-1490`（约 1385 行）。

| # | 段 | 搬什么符号（点名） | 现坐标 | 搬出 | 新档（估） |
|---|---|---|---|---|---|
| 1 | 模式与设置投影（SPLIT-3） | `KernelChoice` `ModelSettingChoice` + `kernelLocked` `_kernelOptions` `kernelChoice` `setKernel` `_readSwitch` `models` `switchRestarts` `pendingModel` `_btestId` `_btestOption` `modes` `permissions` `modelSettings` `_modelSettings`（字段，留 owner） `selected` `_choice` | `:52-105` `:497-658` | ≈210 | `lib/chat/session/mode_state.dart` ≈220 |
| 2 | 内核能力投影 | `health` `loadingHistory` `hasEarlierHistory` `loadingEarlier` `loadEarlier` `sessionId` `stopped` `restart` + `commands` `suggestFiles` `context` `stats` `refreshUsage` `usageLimitResetsAt` `usageLimitApplies` `continuesAfterLimit` `acceptsImages` `acceptsEditorContext` `promptSuggestion` `mcpServers` `refreshMcpServers` `setMcpServerEnabled` `reconnectMcpServer` `authenticateMcpServer` `canEditMessages` `canQueue` `canRename` `renameConfirmed` `ownsTitle` `pendingTitle` `canFork` `fork` | `:433-472` `:659-811` | ≈230 | `lib/chat/session/kernel_proxy.dart` ≈240 |
| 3 | 转写投影 | `isStreaming` `isUnprompted` `canSend` `pendingInteraction` `awaitingPlan` `canStartPlan` `startPlan` `lastTurnEndSeq` `lastReply` `lastTurnInterrupted` `lastTurnUnprompted` `itemCount` `itemAt` `_statusVisible` `tasks` `terminalTasks` `stopTask` `canStopTasks` `moveToBackgroundAt` `moveToBackgroundOf` `commandOf` `stopAt` `stopOf` `_runningTask`（字段，留 owner） `todos` `goal` `_dismissedGoal`（字段，留 owner） `dismissGoal` `setGoal` `clearGoal` | `:812-1079` | ≈240 | `lib/chat/session/transcript_proxy.dart` ≈250 |
| 4 | 文件改动与回退投影 | `root` `fileChanges` `filesSeen` `_filesSeen`（字段，留 owner） `_pendingEdits`（私有 getter，留 owner） `keepAllChanges` `keepChanges` `undoAllChanges` `revertTurn` `canPlanRevert` `plansReverts` `revertPlan` `applyRevert` `undoChanges` `originalOf` | `:1080-1244` | ≈133 | `lib/chat/session/file_edits.dart` ≈143 |
| 5 | 路径助手 | `paths` `_absolute` | `:1132-1148` | ≈17 | `lib/chat/session/file_paths.dart` ≈25 |
| 6 | 发送上下文助手 | `lastImageNumber` `_editorNotes` `_contexts` | `:1250-1269` `:1286-1295` `:1297-1307` | ≈41 | `lib/chat/session/send_contexts.dart` ≈50 |
| 7 | 会话命令 | `stop` `answer` `rename` `discardChanges` | `:1452-1475` | ≈21 | `lib/chat/session/session_commands.dart` ≈30 |
| 8 | 内核连接与视图挂载 | `_connect` `_dropWarm` `attach` `detach` | `:232-241` `:250-255` `:476-493` | ≈33 | `lib/chat/session/lifecycle.dart` ≈42 |

- 八个新档首行 `part of '../chat_session.dart';`（§3.3）；`lib/chat/session/` 为 chat_session 的专属子目录。
- 「搬出」为指示值（按点名方法与坐标区间估）；坐标只用于定位，不参与加总；判据以行数门为准（主档 ≤800、新档 ≤500）。
- **委托行数口径（按 kernel 实测）**：kernel 53 个成员 ⇒ 113 行委托（≈2.13 行/成员）；chat_session 点名 **101** 个成员（第 1–8 段：15 / 31 / 29 / 13 / 2 / 3 / 4 / 4；字段与留 owner 的私有 getter 不计）⇒ **≈215 行委托**。
- **搬出合计**：210 + 230 + 240 + 133 + 17 + 41 + 21 + 33 = **925**。
- **算式**：1492 − 925 + 215 = **≈782 ≤ 800，余量 ≈18**。
- **旧四段口径为什么不达标**：90 成员按旧假设 ≈190 行 ⇒ 1492 − 830 + 190 = **852 > 800**（超 ≈52）——kernel 实测 53 成员 → 113 行，一成员一行的假设被推翻。
- **段 5 不产生新余量，段 6–8 才产生**：`paths` / `_absolute` 的 17 行本在第 4 段的 ≈150 内（切出后第 4 段 ≈133 + 段 5 ≈17），进计划只是固定落点；净减来自段 6 / 7 / 8：(41 − 6) + (21 − 9) + (33 − 9) = **71 行**。
- **段 5–8 的取舍**：都落在下方「不在本批」清单之外，职责各自单一（路径拼法 · 发送上下文 · 会话命令 · 连接与挂载）；字段 `_toldEditor` / `_toldOfEditor` / `_views` / `_warm` / `_subscription` 一并留 owner（§3.3 字段规则）。
- **余量管理**：余量 ≈18；若实测仍越界，按 §7 边界行继续切（owner 档补一条 `part` 指令），不改目标、不换机制。
- **不在本批**：btest 状态面（`:156-216`，归 #55）· 事件应用与回合标记（`_apply` `_cutsAtMessage` `_markTurn` `:257-353`，事件顺序敏感，合并批 #145 已记录 `_apply` 顺序风险，不搬）· 审查面（`:354-412`）· `send`/队列/编辑（`:1319-1452`）· `dispose`。
- **对外暴露**（沿用 `lib/chat/chat_session.dart` 原路径，调用方零改动）：

| 组 | 公开成员 |
|---|---|
| 会话 | `ChatSession` |
| 消息 | `ComposerMessage` |
| 选择面类型 | `KernelChoice` `ModelSettingChoice` |
| 回调类型 | `ChangeReviewOpener` |

调用方（18 档）：

| 文件 | 行 |
|---|---|
| `lib/chat/chat_feed.dart` | 4 |
| `lib/chat/chat_history_view.dart` | 26 |
| `lib/chat/chat_screen.dart` | 30 |
| `lib/chat/composer/composer_picker.dart` | 17 |
| `lib/chat/composer/session_model_picker.dart` | 15 |
| `lib/chat/stop_confirmation.dart` | 5 |
| `lib/chat/panels/revert_dialog.dart` | 10 |
| `lib/chat/side_panel/side_panel_view.dart` | 51 |
| `lib/chat/widgets/plan_start.dart` | 4 |
| `lib/ide/ide_agent_changes.dart` | 4 |
| `lib/ide/ide_agent_edits.dart` | 15 |
| `lib/link/workspace_bridge.dart` | 9 |
| `lib/search/conversation_search.dart` | 8 |
| `lib/settings/pages/thincoder_models_page.dart` | 5 |
| `lib/workspace/agent_title.dart` | 8 |
| `lib/workspace/chat_branch_bar.dart` | 13 |
| `lib/workspace/workspace.dart` | 10 |
| `lib/workbench.dart` | 24 |

### 4.5 chat_models（839 → ≤800）

| 段 | 搬什么符号 | 现坐标 | 搬出 | 新档 |
|---|---|---|---|---|
| 编辑器上下文数据面 | `EditorContext` · `TextContext`（含 `maxSelectedText`、`note` / `editorNote` 的提示词渲染） | `:54-161` | ≈108 | `lib/chat/editor_context.dart`（新 library + `export`）≈110 |

- 主档 839 − 108 + `import` / `export` 两行 ⇒ **≈733 ≤800**（余量 67）。
- 选它的理由：全档最内聚的一段——一个概念（发消息时的编辑器上下文）加它的提示词渲染；唯一依赖 `package:path`，不反向依赖 `chat_models.dart`（无循环）。
- **取代 SPLIT-4 的旧缝**：登记是「模式 / run 模型抽 `chat/btest_models.dart`」，但该缝的前提（btest 模型字段落在本档）未成立——本档顶层声明清单（`grep` 全档声明索引）里没有任何 btest 类型，缝上无料可搬。本设计以编辑上下文数据面取代它；SPLIT-4 的旧登记行须在实施后改指本档（§9 项 5）。
- **对外暴露**：全部公开数据类型不变；`EditorContext` / `TextContext` 经 `chat_models.dart` 的 `export` 继续可见。
  提到 `chat_models.dart` 的 136 个文件（`git grep -l -- lib test`，2026-10-23 实测）零改动。

### 4.6 受影响档总表（一处分账）

| 档 | 现行 | 搬出 | 搬入（委托） | 预期 | 界 | 新档（个数 · 最大估行） |
|---|---|---|---|---|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | 1461 | 1114 | 113 | **480**（实测） | ≤500 | 9 档 · 最大 `thincoder_turns.dart` 279（实测） |
| `lib/chat/step_folds.dart` | 500 | 42 | 2 | ≈460 | ≤500 | 1 档 · ≈45 |
| `lib/chat/composer/composer.dart` | 2466 | 2110 | 65 | ≈421 | ≤800 | 6 档 · 最大 `composer_editing.dart` ≈460 |
| `lib/chat/chat_session.dart` | 1492 | 925 | 215 | **≈782** | ≤800（余量 ≈18） | 8 档 · 最大 `transcript_proxy.dart` ≈250 |
| `lib/chat/chat_models.dart` | 839 | 108 | 2 | ≈733 | ≤800 | 1 档 · ≈110 |

- 「搬出」为指示值（按点名方法与坐标区间估）；预期 = 现行 − 搬出 + 搬入。kernel 行是实测值（第 2 步已落）；其余按指示值，判据以行数门为准。
- 新档判据：每个新档 ≤500（>500 需复核并写明单一职责）；本批所有新档的估值都 ≤460。

## 5 排程与验证（一次一批只动一档）

**步序理由**（按验证价值，不按风险升序）：第 1 步用最小档（step_folds，42 行、1 个 part）证明 `part` 形态成立；第 2 步尽早做最硬的 kernel（搬出 1114 行、9 个 part），把最大的返工余量留在前面；第 3 步 chat_models 是唯一的 `export` 形态，单独一步验证第二条机制；第 4 步 chat_session 余量 ≈18，此时形态经验已齐；第 5 步 composer 改动面最大（≈2110 行）且要等 #55 落地，排末。

| 步 | 档 | 机制 | 验证读数（命令 + 判据） | 回滚（已提交 ∥ 未提交） |
|---|---|---|---|---|
| 0 | 前置 | — | ① 当前态：kernel 与 chat_session 有 #50 的在飞改动（已交付待提交）、composer 与 `lib/browser/btest/**` 有 #55 的在飞改动，第 2 / 4 / 5 步在各自 commit 前不启动；② 每步开工前：该步目标档 `git status` 必空；先跑该步测试集并记录基线（红项逐条记入本步记录，判据见下方测试门） | — |
| 1 | step_folds | part ×1 | `flutter analyze` = 0 issue；`flutter test --no-pub test/chat/step_folds_test.dart test/chat/fold_view_test.dart` 过测试门；主档 ≤500（`node -e` 计数） | `git revert` ∥ `git restore` + 删新档 |
| 2 | kernel | part ×9 | `flutter analyze` = 0 issue；`flutter test --no-pub test/kernel/thincoder_kernel_test.dart test/kernel/rename_confirmed_test.dart test/kernel/thincoder_fixtures_test.dart test/chat/thincoder_commands_test.dart test/composer_test.dart` 过测试门（= `grep -l thincoder_kernel.dart test/` 反推的 5 档全集）；主档 ≤500 | `git revert` ∥ `git restore` + 删新档 |
| 3 | chat_models | export | `flutter analyze` = 0 issue；`flutter test --no-pub test/chat test/kernel` 过测试门；主档 ≤800 | `git revert` ∥ `git restore` + 删新档 |
| 4 | chat_session | part ×8 | `flutter analyze` = 0 issue；`flutter test --no-pub test/chat test/kernel_ui_test.dart` 过测试门；主档 ≤800 | `git revert` ∥ `git restore` + 删新档 |
| 5 | composer | part ×6 | `flutter analyze` = 0 issue；`flutter test --no-pub test/chat test/composer_test.dart test/kernel_ui_test.dart` 过测试门；主档 ≤800 | `git revert` ∥ `git restore` + 删新档 |

- **行数读数命令**（Windows / POSIX 通用）：`node -e "console.log(require('fs').readFileSync('<档>','utf8').match(/\n/g).length)"`。
- **测试门（基线本红时）**：基线与本步后**各跑一次同一条命令**；判据 = **红项集合逐条一致（同名、同数量）且无新增失败**；基线为绿时判据即全绿。先例读数：本批第 3 步同命令两次 `+872 -4`，红项逐条一致。
  现行红基线（2026-10-23）：`test/composer_test` 2 项（mode picker / Shift+Tab）· `test/chat` 4 项（Windows 分隔符与 preview 保存）· `test/ide` 53 项（Windows 路径族；父侧读数，本设计未复跑）。字面「全绿」在这三条测试面上不可达。
- **每一步的提交只含**：目标档 + 本步新档。`git diff --name-only <sha>^ <sha>` 里出现 `test/` 或其他 `lib/` 文件 ⇒ 该步不成立，停。
- **中途放弃（未提交）**：`git restore <目标档>` + 删除本步新档，工作树回到本步开工前；不留半成品提交。
- **步骤之间无代码依赖**：五档互不引用对方的 part 档，任何一步都可单独回滚；顺序只决定风险暴露的先后。

## 6 验收对照（回指 §1 功能点）

| # | 功能点 | 判据（机检） |
|---|---|---|
| 1 | kernel ≤500 | 换行符计数 ≤500；analyze 0 issue；kernel 调用方 5 档过测试门（§5 第 2 步，import 反推） |
| 2 | step_folds ≤500 | 计数 ≤500；`step_folds_test` + `fold_view_test` 过测试门 |
| 3 | composer ≤800 | 计数 ≤800；`test/chat` + `composer_test` + `kernel_ui_test` 过测试门 |
| 4 | chat_session ≤800 | 计数 ≤800；`test/chat` + `kernel_ui_test` 过测试门 |
| 5 | chat_models ≤800 | 计数 ≤800；`test/chat` + `test/kernel` 过测试门 |
| 6 | 签名/可见性不变、调用方零改动 | 提交的文件集 ⊆ {目标档, 本步新档}；`git diff --name-only` 无 `test/`；analyze 0 issue |

- **测试门定义**见 §5「测试门（基线本红时）」：基线与本步后同命令各一次，红项集合逐条一致、无新增失败；基线为绿时即全绿。

## 7 案例表

| 类型 | 场景 | 输入 | 期望 |
|---|---|---|---|
| 正常 | 按缝表搬一段 | 目标档 + 新 part 档 | analyze 0 issue；该面过测试门（§5）；主档行数下降量 ≈ 段跨度 − 委托行数 |
| 正常 | 五档全部落完 | 五个提交 | 五档各自 ≤500 / ≤500 / ≤800 / ≤800 / ≤800 |
| 边界 | 某段搬完主档仍超界 | — | 由 owner 档再补一条 `part` 指令、把该段的一部分再切出去；不改目标、不换机制 |
| 边界 | btest 状态行段已由 #55 搬走 | composer 原 `:1932-2050` | 本批跳过该段（已不在本档）；主档再少 ≈119 行，仍达标 |
| 边界 | 被搬符号只被本档使用 | 如 `_inAtom` | 照搬；私有符号不需对外承诺 |
| 错误 | analyze 报「private member not defined」 | part 档 | `part of` 路径/归属写错；修指令，**不得**把成员改公开 |
| 错误 | 有人 `import` 了 part 档 | — | 撤回该 import；调用方只 import owner 档 |
| 错误 | 某测试需要改才能绿 | — | 停：说明不是纯搬运，回设计轮 |

## 8 关键决策记录

| # | 决策 | 被否方案与理由 |
|---|---|---|
| KD-1 | 有私有耦合的段一律 `part`；无私有耦合、可独立成 library 的公开数据段用「新档 + `export`」（本批仅 chat_models 一段）；其余 `part` | 判据见 §3.2 / §3.3；「无私有耦合」本身不排斥 part，export 的额外价值是独立 library 与编译器强制的边界 |
| KD-2 | 搬运用「顶层函数 + 一行委托」（§21.3 形态），不用协作类、不用 extension | 协作类改生命周期；extension 对私有成员不是已验证形态 |
| KD-3 | kernel 目标 ≤500（严于设计 ㉓ 的 ≤1345） | ≤500 蕴含 ≤1345，两个界同时满足；按批档 §1 的「先拆」口径取严 |
| KD-4 | chat_models 以编辑上下文数据面取代 SPLIT-4 的旧缝 | 旧缝无料（本档无 btest 类型，§4.5）；选最内聚且有 ≥40 行余量的一段；旧登记行由父侧改指本档（§9 项 5） |
| KD-5 | composer 不重构 btest 状态面 | #55 所有；两种先后顺序下本批都达标 |
| KD-6 | 五步各自独立提交、独立回滚 | 一次动五档 = 回滚粒度太粗（批档 §1 约束 2） |
| KD-7 | 不新增、不修改任何测试 | 拆分若需改测试，说明行为变了 ⇒ 停 |

## 9 开放项

1. **#72 的台账原文未能取到**（ledger 读取被截断）。本设计按代码定位边界段：`_boundaries` 的注释 `:281-283` 写的「merged where they meet」即并集语义。若 #72 的定义不同，实施前先对齐。
2. **SPLIT-1 的余下缝不足以达标**：登记写法是「内核模式选择区整段抽 `composer/mode_selector.dart`」，而模式/模型选择器已在 `composer/session_model_picker.dart` 与 `pickers_row.dart`；按该缝只搬几十行到不了 ≤800。本设计的六段切法取代它。`docs/design/browser-biz-test.md` 的登记行（`:643`）需在实施后由父侧改档，指向本档。
3. **kernel 的九段是提议**：若实施时某段跨度过碎（如 `thincoder_inbound.dart` ≈60 行），可与相邻段合并；合并后仍须 ≤500 且每段职责单一。
4. **composer 六档偏多**：若评审要求收敛档数，`composer_message.dart` 可并入 `composer_editing.dart`（合并 ≈680 行）。该档越 500 复核线但 < 800 硬界；保留此选项的前提是实施前复核判「编辑面 + 提交面 = 一条消息从输入到发出的同一职责」。
   依据：`_submit`（`:1474-1501`）直呼 `_saveDraft`（`:1500`），而 `_saveDraft` / `_takeDraftFiles` / `_takeDraftMessage` 都在编辑面 ⇒ 拆开会把 draft 的写方与消费方分到两档。复核不通过就维持六段。
5. **SPLIT-4 的旧缝前提不成立**：登记缝 `chat/btest_models.dart` 在本档无料（§4.5）。本设计以编辑上下文数据面取代它；`docs/design/browser-biz-test.md` 的 SPLIT-4 登记行（`:646`）需在实施后由父侧改档，指向本档 §4.5。
