# 2026-10-16 · thincoder 队列消息
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-16 · 来源 = 用户 2026-10-16 22:24 报告（thincoder 会话工作中不能排队发消息）。
> 台账 = #19（thincoder-adapter · 归批）。前情 = docs/batches/thincoder-model-auto.md（进行中，批 6）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-17
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

- **开批**（2026-10-16 22:24 用户报告）：thincoder 会话在代理工作中**不能**先写消息、等它说完自动发。
- **根因**（父侧实读）：宿主队列面齐备（`agent_kernel.dart:200-218` `QueuesMessages` · `chat_session.dart:511/:544` 门控 · `composer.dart:1321` 禁用 · `chat/panels/queue_panel.dart` · 设置项 `chat.queuedMessages`），**Claude 内核已实现**（`claude_code_kernel.dart:739` / `:860-890`），**thincoder 内核未声明** `QueuesMessages` ⇒ `canQueue = false`。
- **范围**：适配层实现 `QueuesMessages`（本地队列 + 回合结束排水 + 撤回 / 立即发），**零 CLI 改动**；`duringTurn`（插入当前任务）在 ACP 无回合内注入通道 ⇒ 按「等回合结束」处理并登记判定条件。
- **父侧裁定**：
  ① 失败面按设计者的选择（**留在对话 + error 提示**，不回队列）——理由成立（进程退出会清队；与首条失败同形），判定条件就位；
  ② l10n 说明句「目前仅支持 Claude Code」本批后为假 ⇒ **认这 4 档增量**（`app_en.arb` / `app_zh.arb` 及两份生成档）；
  ③ 设计者就地修的 §4 F3 失效句（`thincoder-adapter.md:207`）与 §10 边界清单「队列控制」两条，**认**（本批直接推翻，就地改口径）；
  ④ 队列不落盘（重开桌面即丢）——认，登记 §18.9。
- **前情**：批 6（F13 auto + F14 模型清单/档位）进行中、未收口，见 `docs/batches/thincoder-model-auto.md`；本批与其无文件交叠（批 6 = kernel/mock/composer 面；本批 = kernel 队列面 + 4 档 l10n）。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（2026-10-16 · 设计档 §18（F15 队列）+ §4 F3 / §7 / §9 / §10 / §11 索引随改；零代码）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖）**

| # | 条目 | 来源 |
|---|---|---|
| 1 | F15：thincoder 会话流式中可发消息 ⇒ 进队列，队列面板可见、可撤回 / 编辑 | 需求档 F15（批 7） |
| 2 | 当前回合结束后自动**依次**发送（完成 / 取消 / 错误三态都算） | 需求档 F15 |
| 3 | 「插入当前任务」在 ACP 面不可达 ⇒ 按「等回合结束」处理并登记（含判定条件） | 需求档 F15 验收末句 |
| 4 | （派生）撤回 / 立即发送 / 收束清队 / 发送失败的语义 ═ 设计 §18.2 | 设计自定 |
| 5 | （派生）设置页「工作中发送的消息」文案修正，使之与本批能力一致 | 设计自定（D54；父侧可撤，见末「上抛 / 待裁」） |

**不覆盖**：队列落盘 · 回合内注入 · 面板内直接改字 · 清空队列 / 上下调序 · 设置项按会话内核显隐（逐条带判定条件，设计 §18.9）。

**设计档落点**：`docs/design/thincoder-adapter.md` §18（做法 / 语义细则 / 兼容 / 受影响文件 / 验收对照 §18.5 / 决策 D48–D54 / 用例 T63–T67 / UI / 边界 / 走查）。
索引随改：§4 F3（「流式中禁用输入」那句失效，改为「可继续发 + 指 §18」）· §7（F15 行 + 一致链补 F15）· §9（队列测试面）· §10（边界撤「队列控制」，另立一行「队列面 = 批 7 已接」）· §11（批 7 已落地）。

**机制一句话**：内核**本地**队列 + 声明既有 `QueuesMessages`；`send` 在跑时入队并发 `UserMessageItem(queued: true)`；`_endTurn` 末尾排水（`_next` 优先、其次队头），`_deliver` 开头那次 emit 即转正；`cancelQueued` 纯本地，`sendQueuedNow` = 置 `_next` + 停当前回合。
宿主零改动、thincoder 仓零改动、不依赖 CLI 版本。

**五条硬约束（评审请逐条对）**

1. 同一时刻只有一趟 `session/prompt`：入队只在 `_turn != null`，排水只在 `_turn == null`。
2. 先转正、后请求：转正 emit 在 `_deliver` 开头 ⇒ 请求失败时消息已在对话里。
3. 排水先于进程释放：`_drain()` 起来一趟即 `_endTurn` 提前 return，`release()` 分支被跳过。
4. 发送失败**不回队列**：消息留在对话 + 既有 error 提示，回合标 interrupted，排水继续下一条（不静默丢，也不打转）。
5. 进程退出 / 重启 / dispose / 启动失败 ⇒ 逐项 `ItemRemoved` 后清队。

**受影响文件（当前行数 → 增量；行数 = 2026-10-16 `wc -l` 实测）**

| 档 | 当前 | 增量 |
|---|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | 958 | ≤ +70（⇒ ≤1028） |
| `lib/kernel/thincoder/thincoder_mock.dart` | 620 | ≤ +6（`promptError` 一个可变参数，T67③ 用） |
| `test/kernel/thincoder_kernel_test.dart` | 2133 | ≤ +170（⇒ ≤2303） |
| l10n 4 档（`app_en.arb` / `app_zh.arb` / 两个生成档） | 6642 / 2509 / 9159 / 8651 | 各 1 行 |
| 宿主其它档、thincoder 仓、固件 | — | 0 |

体量：kernel 958 行在 >800 名单，本批动的是**会话面**（`send` / `_deliver` / `_endTurn` / `_teardown`），不是 §17.4 裁定的选择面 ⇒ 不触发「先立拆分批」；仍是行级新增、不动结构。

**测试覆盖**：T63 入队与转正（含「在跑时不写第二条 prompt」）· T64 依次（两项）· T65 撤回（在队 / 已发出 / 不存在）· T66 立即发送（停当前 + 该项先发、其余保序）· T67 收束清队三支（crash / restart / prompt 回错）。
固件**不加**：本批不发任何新帧（还是 `session/prompt` / `session/cancel`），队列顺序是纯客户端行为，T63 / T64 已用 mock 的 `requests()` 逐帧钉住（判据见设计 §18.7 末）。

**验收对照**：设计 §18.5 表逐条回指 F15 + 4 条派生项，每条给机检（T 号）或走查步号；另附兼容三种组合（设计 §18.3）。

**关键决策**：D48 队列在本地（ACP 无撤回 / 改序 / 注入面）· D49 不用服务端 FIFO 当实现 · D50 转正 = 同 id 重发 `ItemUpserted`（零宿主改动）· D51 失败不回队列 · D52 `duringTurn` 降级 afterTurn（带判定条件）· D53 排队消息优先于进程释放 · D54 设置页文案修正。

**一致性修正（就地修，逐条报）**：① §4 F3「`canQueue` 不声明 ⇒ 流式中输入框禁用」= 本批直接推翻，已改写；② §10 边界清单里的「队列控制」= 同一原因，已删并另立「队列面已接」一行。

**上抛 / 待裁**

- 无阻塞项（需求档 F15 五要素够设计：目标 / 功能点 / 边界 / 验收 / 依赖齐）。
- 知情 1（可撤）：条目 5 的文案修正超出「宿主零改动」的字面（4 个 l10n 档各 1 行）。不认可 ⇒ 删该行 + §18.8 ① 转登记，设计其余不动。
- 知情 2（前提更正）：简报写「回放无『发消息』动作」，实况不符——回放**有** `{"turn": …}`（`thincoder_fixtures_test.dart:102-106`）且不等回合结束。不加固件的结论不变，理由已换成「本批不发新帧」（设计 §18.7 末）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

评审对象：docs/design/thincoder-adapter.md §18（批 7：F15）及随改行 §4 F3 :207 · §10 :425/:428。计数：🔴 0 · 🟡 6 · 🔵 6。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|---|---|---|---|
| 1 | 清晰度 | 🟡 | T63④/T64 的 `release()` 与本文档既有生命周期方法 `release()` 同名：:1636「④ `release()` 后 ⇒ prompt 2 条」按生命周期读与 :144「活跃 ──release()──▶ session/close（best effort）+ 进程退出」及 :1566 冲突；按「放行 mock 的 hold」读才成立（:1632 的 `hold = Completer`） | 用例表改用 mock 侧真实符号（如 `hold.complete()`）或改名 `releaseHold()`；把「回合如何结束」写成可执行符号 |
| 2 | 清晰度 / 可行性 | 🟡 | `_endTurn` 插入点（:1517，`:518-531` 内、`emit(TurnEnded)` 之后、`_releaseWanted` 之前）未钉住「此处 `_turn` 已为 null」；而 `_drain()` 首行是 `if (_turn != null) return false`（:1503）⇒ 若 `_turn` 在更晚处才清空，排水静默返回 false、队列停摆（要等下一次 `send` 才恢复）。:1527 的约束 1「排水只在 `_turn == null` 时发生」在 `_drain` 守卫下是恒真句，不构成时序要求 | 在 §18.1 明写前置不变量：`_turn = null` 必须早于该插入行；并点明提前 return 只跳过 `_releaseWanted` 分支 |
| 3 | 验收 | 🟡 | §18.5 的「进队列：队列面板可见、可撤回 / 编辑」(:1607) 判据写 T63②③、T65，但 T65(:1638) 只驱动 `cancelQueued`；编辑路径（:1671 指 `chat_session.dart:1036-1046`）无任何用例、也未标注「宿主既有、非本批机检」 | 给编辑路径补一条断言，或在判据列显式标「宿主既有路径，本批不机检」 |
| 4 | 验收 | 🟡 | §18.2③ 写了两条无用例兜底的行为：`_next` 上那条也能 `cancelQueued`(:1548)；重复 `sendQueuedNow` 时「前一条 `_next` 退回队头」(:1549)。T65 / T66 均未覆盖 | 补两条（或并入 T65 / T66 的断言子项）——这两条正是 `_next` 状态机的边界 |
| 5 | 文档状态 | 🟡 | 本文档仍为设计稿（§18 待评审、无代码），但 :441「已落地（批 7）：工作中发送的消息 = 宿主既有队列面」与 :428「队列面（工作中发送的消息）= 批 7 已接（§18）」按本文档的用法（:427「批 4、批 5 已接」= 已交付）读作已交付，与 :1591 起的 `≤ +70` 估算口径不一致 | 收口前改为状态中性措辞（如「批 7 设计已定（§18）」），收口时再改「已落地」 |
| 6 | 文档状态 | 🟡 | 抬头 :5「分批：**批 1 = 本地内核全链路**…；**批 5 = 子代理内容归属（F12，§16）**」只列到批 5，§17（批 6）与 §18（批 7）未进分批枚举（批 6 已遗留同缺） | 随 §18 落档把批 6 / 批 7 补进该行（或改成指「本档批次见各节」） |
| 7 | 清晰度 | 🔵 | `send` 形状里用了 `_sent`(:1491 `if (!_sent.add(turn.id)) return;`)，但 §18.1 状态表(:1481-1484)只列 `_queue` / `_next`，㉙ 只写「队列状态（`:94-102` 一带）」 | 在状态表补一行（或注明 `_sent` = 既有去重集，本批不动） |
| 8 | 清晰度 | 🔵 | F6 的图片落盘与阈值（:235 落盘、:236「单项 ≤ 15 MB、单回合合计 ≤ 30 MB」超阈弃 + 提示）发生在入队时还是转正时未定；而队列项按「图片原样随行」预览(:1535)，两者不一致时面板 N 张与实发集合会对不上 | 明写：落盘 + 阈值判定在转正（`_deliver`）执行，或改为入队即判定并把弃图结果反映到队列项 |
| 9 | 清晰度 | 🔵 | 排水可能落在「回合已结束、后台子代理仍在跑」的挂起态（:582-583 已定「挂起期再发消息：照常发送」），§18 未回指该口径 | §18.1 / §18.2-⑤ 加一句指针：挂起态排水照发，服务端排队语义见 §15.3 |
| 10 | 先例检查 | 🔵 | §18 最近先例行(:1469)给的是实现坐标 ∥ 宿主面坐标，无设计档章节坐标；:48 已声明「先例无设计档可引」，但 §18 未回指，读者会以为漏项 | 先例行末尾加一句回指 §2.2 的「先例无设计档」声明 |
| 11 | 体量注记 | 🔵 | ㉞(:1594) 列了 `app_localizations_en.dart`（9159）/`app_localizations_zh.dart`（8651），有行数与增量但无档位归类；两者 >800 行，若不说明是生成物，会与 §5.2 的拆分口径打架 | 注明「生成档（gen-l10n 产物），按生成物处理、不入拆分档位；手改对象是 ARB，生成档仅同步值」 |
| 12 | 体量注记 | 🔵 | `thincoder_kernel.dart` 958 → ≤1028 仍在 >800 名单；本批遵守 §17.4 的「下一批不得在选择面叠行」裁定（:1599 明确改动面 = 会话面），但该裁定的下一缝（选择面）不覆盖本批触碰的会话面 | 登记一条会话面缝候选（队列 / 排水 / `_endTurn` 段），供下一次结构级触碰使用；不改变「本批不动结构」的裁定 |

out-of-scope note（不评严重度）：§17.4 ㉗「≤ +70（⇒ ≤2139；实交 2139）」与本节体量条「实交 2135 行（+66）」数字互斥（2069+66=2135）——属批 6 在途记录范围。另：无 AGENTS.md / 无文档地图 / 无项目标准档 ⇒ 方法论与文档归属两项判据降级；需求档 F15 原文不在本轮范围，覆盖度只能按 §18.5 自述核对。

VERDICT: pass

## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）

**状态行**：✅ 实施完成（2026-10-16）

**交付摘要（批 7 · F15 工作中发送的消息）**

- 内核 `lib/kernel/thincoder/thincoder_kernel.dart`：声明 `QueuesMessages`（`:44`）；本地队列 `_queue` / `_next`（`:99-101`）；`send` 去重后入队，在跑时发 `UserMessageItem(queued: true)`（id = `KernelTurn.id`，图片原样、零 I/O）、空闲走 `_drain()`（`:437-461`）；`_endTurn` 在 `emit(TurnEnded)` 之后、`_releaseWanted` 之前 `if (_drain()) return;`（`:560`）；`cancelQueued` / `sendQueuedNow`（`:582-620`，零 RPC，旧 `_next` 退回队头）；`_teardown` 逐项 `ItemRemoved` 后清队（`:373-377`）。失败面 = 转正已发生 + 既有 `NoticeItem(error)` + interrupted，不回队列，排水继续。
- mock `thincoder_mock.dart`：可变 `promptError`（`:72-73`），`_prompt` 开头回 `-32603` 并完成 `finished`（`:406-411`），净增 6 行。
- 测试 `test/kernel/thincoder_kernel_test.dart`：新增 `thincoder queue` 组 T63–T67（含 T65④ / T66⑥ 两条 `_next` 边）；既有能力断言翻转 `isNot(isA<QueuesMessages>())` → `isA<QueuesMessages>()`（`:292`）。68 用例。
- l10n 4 档：`app_en.arb:2207` · `app_zh.arb:928` · `app_localizations_en.dart:3233` · `app_localizations_zh.dart:3102`，取值与设计 §18.8 ① 逐字一致（改值，行数不变）。

**行数（起 → 交 / 上限）**

| 档 | 起 | 交 | 上限 |
|---|---|---|---|
| `thincoder_kernel.dart` | 958 | 1027 | ≤1028 |
| `thincoder_mock.dart` | 620 | 626 | ≤626 |
| `thincoder_kernel_test.dart` | 2133 | 2303 | ≤2303 |
| 4 个 l10n 档 | — | 各 1 行改值（行数不变） | 各 1 行 |

**测试 / 分析读数（本机 SDK `C:\Users\xinbo\repos\flutter\bin\flutter.bat`）**

- `flutter test test/kernel/thincoder_kernel_test.dart` → `+68: All tests passed!`
- `flutter test test/kernel/thincoder_fixtures_test.dart test/composer_test.dart` → `+72: All tests passed!`
- `flutter analyze lib/kernel/thincoder test/kernel/thincoder_kernel_test.dart` → `No issues found!`
- 追加 `flutter test test/l10n_test.dart` → `+22: All tests passed!`
- `flutter pub get` 触碰的 `pubspec.lock` 已 `git restore` 还原；`git status` 本批仅 7 档。

**逐条用例结果**

| # | 结果 | 钉住的判据 |
|---|---|---|
| T63 | ✅ | ①②③ 在跑时不写第二条 prompt、队列项 id / `queued == true`、对话仅 one；④ 放行后 prompt one→two、队列空、转正项 `queued == false` |
| T64 | ✅ | 逐趟放行：首趟止于 turn-2（队列剩 1），turn-2 止后才发 turn-3；prompt 顺序 one / two / three |
| T65 | ✅ | 撤回 true / 再撤 false / 已发出 false、一条 `ItemRemoved`、零 RPC（`written` 长度不变）、turn-3 从未发出；④ `_next` 上撤回 true + 一条 `ItemRemoved`（`['turn-3','turn-6']`），回合结束后只发队头 |
| T66 | ✅ | 一次 `session/cancel`、`lastTurnInterrupted == true`、three 先于 two、随后 two、对话 one→three→two、队列剩 [2]；⑥ 先点 6 再点 5 ⇒ 排水 five→six（旧 `_next` 退回队头） |
| T67 | ✅ | ① crash / ② restart：队列空 + 逐项 `ItemRemoved` + 对话无该项；③ `promptError`：消息留在对话（user: two）、恰好一条 error notice、interrupted、队列空；关掉后可照常发第三条 |

**决策 / 披露**

- 测试的 mock 剧本改用单步 `usage_update` 并逐趟重握 `hold`（设计给的机制），用于 T64 / T65④ / T66 的「一趟一放行」；语义与 §18.7 统一前提一致。
- 既有能力断言必须翻转，否则与本批能力矛盾（设计 §18.3 兼容行）。
- 未动宿主 `lib/chat/**`、未动 `thincoder/` 子目录、未改 `canQueue` / `canSend`、无 `duringTurn` 分支、无落盘、未加固件；设计文档未改（eng-designer 产权）。

**审计与代码评审轮次与终态**

- 内部探索审计（explore，只读，1 轮）：2 条测试断言偏弱（T65④ 缺 `ItemRemoved` 断言；T67③ 只判 last kind）→ 已修（T65④ 断言 `['turn-3','turn-6']`；T67③ 改「恰好一条」）。
- 独立代码评审（advisor code，1 轮，对照设计 §18）：`VERDICT: pass`；0 🔴 / 1 🟡（可选）/ 2 🔵（风格 / 文档）。
- fix round：1 轮（审计两条断言补齐 + T65④ 夹具恢复），之后全套复跑通过。
- 终态：`clean`（无阻塞项；1 条 🟡 上抛待裁）。

**上抛 / 待裁**

- [上抛·待裁] `KernelTurn.now`（`lib/kernel/kernel_types.dart:594-596` 的接口契约）在 thincoder 内核未兑现：本批 `send` 只按 `_turn != null` 入队，不看 `now`。今天唯一生产者是 Claude 的目标路径（`lib/chat/chat_session.dart:789` / `:793` + `lib/chat/widgets/tool_call_row.dart:99` 的 `ToolKind.goal`），thincoder 翻译层不产出该 kind ⇒ 不可达。处置三选一：兑现 / 设计 §18.9 登记判定条件 / 代码注一句；交父侧与设计者裁，本批不擅自加语义。
- [上抛·知会] 设计 §18.2-② 的「预览与实际不一致由提示交代」只覆盖弃图；转正正文还会拼 `notes` 与 `[Attached images: …]` 行（`thincoder_kernel.dart:911` / `:942`），面板预览只给 `turn.text` —— 建议设计档补半句（文档产权属设计者）。
- [上抛·知会] `lib/l10n/app_localizations.dart:5654` 的生成注释仍是旧英文串（不在本批 4 档范围；下次 `gen-l10n` 自然同步）。

## §6 验证与收口（父代理）

**交付面**：F15 工作中发送的消息——thincoder 会话流式中可发消息（入本地队列、面板可见、可撤回 / 编辑 / 立即发），回合结束（完成 / 取消 / 出错）依次自动发；CLI 零改动，宿主代码零改动（唯一触碰 = 设置页一句文案，4 档各 1 行）。

**验证读数（父侧实跑）**

| 面 | 读数 |
|---|---|
| 本仓测试 | `flutter test test/kernel/thincoder_kernel_test.dart test/kernel/thincoder_fixtures_test.dart test/l10n_test.dart` ⇒ **108 passed**（kernel 68 / 固件 18 / l10n 22）；composer 54 / 91 面另由实现轮与批 6 覆盖 |
| analyze | `flutter analyze lib/kernel/thincoder test/kernel/thincoder_kernel_test.dart` ⇒ No issues found |
| 行数 | kernel 958→**1027**（≤1028）· mock 620→**626**（≤626）· 测试 2133→**2303**（≤2303）· 4 个 l10n 档各改 1 行（行数不变） |
| 用例 | T63 入队与转正 · T64 依次两项 · T65 撤回（含 ④ `_next` 上撤回）· T66 立即发送（含 ⑥ 重复点名退回队头）· T67 收束清队 + 失败面——逐条 ✅ |
| 真机走查 | 用户 2026-10-17 01:11「可以的」：工作中再发一条 ⇒ 队列项（撤回 / 编辑 / 立即发）⇒ 本轮结束自动接着发 |

**集成测试**：本批未跑集成套件——该面以用户真机走查为唯一验收（真会话里「跑长回合 + 中途发消息 + 看自动续发」）；单元用例面 = `test/kernel/thincoder_kernel_test.dart`（T63–T67），随仓长期保留。

**流程记录**：设计 §18（首版 + 评审修正轮 12 条 + 交付后两条登记）· 设计评审 1 轮通过（0 🔴 / 6 🟡 / 6 🔵，12 条全收）· 实现 1 轮（#54，内部审计 1 轮 + 代码评审 1 轮 pass，终态 clean）。

**结算前核对**：台账 #19 核销；需求档 F15 验收句与实况一致（含 `duringTurn` 降级口径）；设计档 §18.9-8（`KernelTurn.now` 登记）与 §18.2-②（预览口径）就位；批次档 §2/§3/§5 状态行就位。

**暂缓批复核**：无。

**未决（保留指针）**：① `KernelTurn.now` 未兑现——台账 #20（trigger=条件），设计档 §18.9-8 给判定条件；② 队列不落盘（重开桌面即丢）——设计 §18.9-2 已登记；③ 远端桥可透传 `now`（`workspace_bridge.dart:276-279`）——同 ① 的条件面。

**状态**：已收口 2026-10-17。
