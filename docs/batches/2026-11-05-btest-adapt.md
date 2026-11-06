# 2026-11-05 · btest-adapt
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-11-05 · 来源 = 用户「btest model have some truble, i think it is useless, you help me」→「i join repos in project, please help me, make btest model useful. Adaptation work … finish the btest work」。
> 前情 = docs/batches/2026-10-22-browser-biz-test-mode.md（btest 本体）· docs/batches/2026-11-05-upstream-95.md（同日合并，本批在其上）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-05

**读了什么**：用户工作区 `C:\Users\xinbo\AppData\Roaming\baocode\workspaces\hnevofieco` 的两段 btest 会话（thincoder 槽 3 / 23）：185 条用户消息逐条读过，btest 工具调用与拒绝逐条列过（`.thincoder/tmp/slot-*.mjs`，只读）。撞墙读数与用户口径原话见设计档 `docs/design/browser-biz-test.md` §12 开头两段。

**本批改什么**（设计单源 = 设计档 §12，此处只列面）：

| # | 面 | 设计档 |
|---|---|---|
| 1 | run 之间浏览器工具照样可用（同一套主机判据，写开关定只读 / 写，不计数） | §12.1 |
| 2 | URL 入口只记录，收尾列出；`detour` 成可选备注 | §12.2 |
| 3 | 收尾 R4 只拦本轮新增的 case，起始索引里没走到的计数 | §12.3 |
| 4 | 原生下拉：`browser_type` 按选项文字 / 值选中（页面助手 v4）；evaluate 写值的拒绝文本说该怎么做 | §12.4 |
| 5 | 模式卡加用户口径 `[U1]`…`[U7]` 与 `[D12]`；上传分界改；run_start 列出预期文件旁的流程记录 | §12.5 |
| 6 | btest 开关按项目记（`btest.onIn`） | §12.6 |
| 7 | Shift+Tab 跳过 btest | §12.7 |
| 8 | thincoder `testMode`：btest 期间工程模式的门让开 | §12.8 · 外仓 `docs/batches/2026-11-05-btest-test-mode.md` |

**留着没动的**：R1（空轮）/ R2（issue 五字段）/ R3（声明场景逐行交代）/ R5（fail 有据）；写值脚本与 replay 的拒绝；allow / prod 两张主机表；规则 A；一次一个 run；卡的标记 `[btest-mode-card v1]`（理由见 §12.5 末条）。

**fork 登记**：`lib/browser/browser_page.dart`（新行）、`lib/browser/browser_tools.dart`（`detour` 语义）、`lib/chat/composer/composer.dart`（`btestModeId` import）、`test/composer_test.dart`（第四处期望调整）四行，见 `docs/design/fork-deltas.md` 第 3 节。`lib/browser/browser_actions.dart` 不改（第 4 节冻结面）。

**集成索引**：`test/RTM.md` 5-1 改写一处（收尾拒绝里不再有起始索引里没走到的 case，只计数），变更记录同步；行数不变。

## §2 批次任务与设计（eng-designer）
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
**状态行**：已收口 2026-11-05

### 读数（Flutter 3.47.5）

| 项 | 命令 | 结果 |
|---|---|---|
| btest 单测与集成 | `flutter test --no-pub test/browser/btest_{card,expect_file,policy,run_end,tool_gate}_test.dart test/chat/composer_btest_status_test.dart test/chat/session_overlay_test.dart test/integration/btest_flows_test.dart test/settings/browser_page_test.dart` | 全过 |
| composer | `flutter test --no-pub test/composer_test.dart` | 59 过；合并前记的两条已知挂（`docs/batches/2026-10-22-browser-biz-test-mode.md`「Shift+Tab in the input goes through the modes」「mode picker opens on press, animates, and follows the mouse」）这一批起都过 |
| thincoder 内核 | `flutter test --no-pub test/kernel/thincoder_kernel_test.dart` | 154 过（含两条新用例：btest 开 ⇒ prompt 前发 `testMode: true`，不变不重发，关 ⇒ `false`；没有这一项的 agent 什么也不发） |
| 会话切换计时 | `flutter test --no-pub test/integration/chat_flows_test.dart` | 主树 2 次全过（门槛附近的读数见 upstream-95 批 §6） |
| 静态 | `flutter analyze --no-pub` | 0 error；2 warning / 9 info 都是存量（同 upstream-95 批 §6） |
| 格式 | `dart format --output=none --set-exit-if-changed` 改过的 23 档 | 改前已经齐整的 15 档仍齐整；另 8 档改前就不齐（`btest_settings.dart`、`composer.dart`、`composer_menu.dart`、`thincoder_{choices,mock,turns}.dart`、`btest_expect_file_test.dart`、`thincoder_kernel_test.dart`），本批不整档重排 |
| 下拉 | headless Edge 探针 `.thincoder/tmp/cdp-select-probe.mjs` | 10 项全过（设计档 §12.4） |
| thincoder 实况 | `.thincoder/tmp/acp-probe-testmode.mjs` 对 `D:\baocode\thincoder` 起 `thincoder acp`（临时配置目录 + 假渠道，不发 prompt） | `session/new` 的 `configOptions` 有 `testMode`（现值 `false`）；设 `true` ⇒ 应答现值 `true`；设 `"yes"` ⇒ `-32602` |

### 用户环境（本批直接做的）

- `C:\Users\xinbo\AppData\Roaming\baocode\User\settings.json` 加 `btest.onIn: ["C:\\Users\\xinbo\\AppData\\Roaming\\baocode\\workspaces\\hnevofieco"]`：那个工作区的会话在新版里打开照旧是 btest。旧的 `btest.on: true` 留着（正在跑的旧版还读它），新版第一次写列表时删掉。
- thincoder 外仓 `D:\baocode\thincoder` 的 `main` 快进到 `c7674ae0`（在独立 worktree 里改、测完再快进，没动在跑的进程）。已开着的 `thincoder acp` 进程不重载代码。

### 生效要做的

1. 重新构建并重启 BaoCode（`page script v4`、新卡、新门都在 Dart 侧）。
2. 已经带着旧卡的会话：把 btest 关一次再开，下一条消息带新卡。
3. 重开会话后 thincoder 才有 `testMode`；旧进程上 BaoCode 什么也不发，台账门照旧。

### 未做 / 留给用户

- 临时目录 `D:\baocode-pre95`、`D:\thincoder-testmode` 已从 git 摘掉、内容已清，空目录被某个进程占着删不掉，可以手动删。
- 本批没有在用户的真实页面上跑一轮 btest（需要用户的浏览器会话与账号）；下拉只在本地页面上验过。
