# 2026-10-16 · thincoder 接口扩展：审批自动档 + 模型清单（批 6）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-16 · 来源 = 用户 2026-10-16 20:07 裁定「开」（需求档 F13 审批自动档 + F14 模型清单与思考档位；同实现面合批）。
> 台账 = #16 #17（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-17
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

- **开批**（2026-10-16 20:07 用户裁定「开」；21:08-21:09 加急）：F13 审批自动档 + F14 模型清单与思考档位，同实现面合批（台账 #16 #17）。
- **用户口径**（21:09 原话）：「每次都得点，开启一个自动批准的开关之类的，**和终端同源**」——auto 必须 = 终端 `/auto` 的同一机制（CLI 的 `agent.autoApprove`），不是桌面自演；且开关要**持续可见**。21:08「迫切」⇒ 本批优先、其余（F14 / 模型清单）随行。
- **机制裁定的结果（设计期实读，与本批初设不同）**：核的审批短路已在 `dispatch.mjs:167-186`（判据行 `:177` 含 `agent.autoApprove`）⇒ 「开着不问客户端」在 0.12.74 已成立，**桥零改**；CLI 侧改动收窄为「只暴露位」（`handlers-session.mjs` 两处，净增 5 行）+ 桥一行防重复注释。桌面选项 UI 不通用（固定三面）⇒ 桌面面 = 适配层实现既有 `SelectsPermission`（宿主零改动）。
- **父侧裁定**：① 需求档 F13/F14 口径按实读改（「适配层实现既有审批面」/「模型面零改动、档位面加一条 effort 分支」）——已改；② 体量：`thincoder_kernel.dart` 889 → ≤950 行，**本批不拆**（缝与触发已写）；③ 分支：在 `feat/acp-subagent-attribution` 上**叠一笔提交**（一个分支、两次提交、用户一次合并），不另起分支；④ P0（桌面内核自答）保持兜底、不做。
- **前情**：批 5（子代理内容归属）已收口（同板块，`docs/batches/thincoder-subagent-attribution.md`）；本批的 thincoder 侧改动叠在其分支之上。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（语义修正轮 + ㉗ 体量追加：面板 always ⇒ 会话级 auto（用户 2026-10-16 21:47 裁定；零代码））
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖 · 每条可验）**

| # | 条目（回指需求档） | 判据 | 设计落点 |
|---|---|---|---|
| 1 | F13 自动档 = 服务端位（终端 `/auto` 同源）：CLI 把 `agent.autoApprove` 暴露为 `configOptions.autoApprove`（boolean），`set_config_option` 可写 | 探针 ①④；id 序含 `autoApprove`；`applyConfigOption('autoApprove', true) === true`、字符串入参 ⇒ false | §17.1-① |
| 2 | F13 开着 ⇒ 不弹审批（请求根本不到客户端） | 代码证据 `dispatch.mjs:167-186`（判据行 `:177`）；行为证据 = 走查③（真会话跑一次 `bash`，客户端侧零 `session/request_permission`） | §17.1-① 关键事实 · §17.8-7 |
| 3 | F13 桌面面上报即显示、可切换、开着时持续可见 | T51（两项 / `select` 发布尔 / `caution`）；走查②③ | §17.1-③ |
| 4 | F13 关 ⇒ 恢复逐次 | T53；走查③（后半） | §17.1-③ |
| 5 | F14 模型清单 = 运行期清单投影（各渠道 `GET /models`、去重后 `provider:model`、当前项必在） | T55（多项 + 切换 + 回报驱动）；走查⑤ | §17.3-①② |
| 6 | F14 思考档位：新 id `thinkingLevel`（`off` + 档），`thinking` 布尔形状不动（旧桌面不假报） | 探针 ②③⑤⑥⑦；T56 / T57 / T58 | §17.3-②③ |
| 7 | 兼容：旧 CLI 零新面；旧桌面忽略新项即合规 | T54 / T57；走查⑦ | §17.3-④ |
| 8 | thincoder 侧最小可合并：改动面 = 1 代码档 + 1 装配档 + 1 行注释 + 4 文档位 + CHANGELOG；不预占号 | 设计 §17.1 / §17.3 的逐字 diff + §17.4 文档位 d–h；门禁与探针读数入 §5 | §17.1 · §17.3 · §17.4 |

**不属本批（有判定条件）**：P0（桌面内核自答）= 兜底，只留一句判据、不做（§17.2 / §17.8-4）；逐工具白名单（需求档 F13 边界原文）；AUTO 徽标 / 状态行面（§17.8-2）；「Approve for this session」的标签与语义（§17.8-3 / §14-18）。

**设计档落点**：`docs/design/thincoder-adapter.md` §17（新增 17.1–17.9）+ 随改 §4 F5 · §5.2 · §7 · §9 · §10 · §11 · §12-A-4 · §14-1 · §14-18/-19 · 变更记录。验收对照 = §17.6；用例 = §17.7（T51–T58）；走查 = §17.9（8 步）。

**机制设计（各一句话）**

- F13：CLI 暴露 `autoApprove`（`applyConfigOption` 落 `agent.autoApprove`）；核的审批短路在 `dispatch.mjs:177` 已存在 ⇒ **桥零改**（仅注释一行）；桌面在适配层实现既有的 `SelectsPermission`（宿主零改动），显示与切换全部回报驱动（D20），开着时 pill 名 + 警示色常驻可见。
- F14：`model.options[]` = 会话建好后后台预取 + `agent._modelChoices` 缓存 + `config_option_update` 推送（`sessionConfigOptions` 保持同步）；新增 `thinkingLevel` 与 `thinking` **并行**投影（`thinking` 形状不动）；桌面 `effort` 面在有档位上报时变列表（`effortLabel`），否则逐字走既有开关。

**受影响文件与测试覆盖（E2）**

| # | 文件（编制日行数） | 改动 | 增量 |
|---|---|---|---|
| ㉔ | `lib/kernel/thincoder/thincoder_kernel.dart`（889） | `implements SelectsPermission` + `permission` 面；`effort` 读 `thinkingLevel`；`_ModelSetting.toggle` 可注入 | ≤ +60（⇒ ≤950） |
| ㉕ | `lib/kernel/thincoder/thincoder_mock.dart`（568） | `autoApprove` / `models` / `thinkingLevels` 三个可选脚本参数；`_options` / `_configure` / `_approve`（auto 时不发请求，模拟核短路） | ≤ +45 |
| ㉖ | `test/kernel/thincoder_kernel_test.dart`（1846） | T51–T58 | ≤ +200 |
| — | `test/fixtures/thincoder/*` | 不加（回放无「点选择器」动作；选项面在 kernel 测试断言） | 0 |

宿主零改动：`agent_kernel.dart` · `chat_session.dart` · composer 族（`composer.dart` / `composer_picker.dart` / `kernel_option_text.dart`）· `interaction_panel.dart`；`thincoder_events.dart` 零改动。
out-of-repo（父侧轮）：`thincoder-cli/src/acp/handlers-session.mjs` · `src/acp.mjs` · `src/acp/bridge.mjs`（仅注释）+ 契约档 / 需求档 / CHANGELOG（§17.4 d–h）。

**验收对照（需求档 ↔ 本档）**：设计 §17.6 九行逐条给判据；三方一致链 = 上表 #1–#8 ↔ 需求档 F13 / F14 ↔ 设计 §17.6（条目名同源，不另起名）。

**关键决策（全文 §17.5）**：D39 自动档走服务端位（否 P0 本地自答）· D40 桥零改（核已短路）· D41 落点 = 宿主审批面 · D42 不加徽标 · D43 `thinking` 不改形（新 id 并行）· D44 档位只对有思考面的模型 · D45 清单预取 + 推送 · D46「always」本批不改 · D47 强制思考族布尔对齐终端。

**上抛项（待主 agent / 用户）**

1. 需求档 F13 现文「桌面走 E3（上报即显示开关）」；实读结论：桌面选项 UI **不通用**（固定三面：mode / model / thinking），新 id 要适配层一行接线（§17 偏离 1）。需求档 = 主 agent 的笔，请改一句：「桌面在适配层实现既有审批面显示 / 切换该位（宿主零改动）」。
2. 需求档 F14 现文「桌面零改动（E3：上报几项显示几项）」：模型面成立；思考档位需要 `effort` 面一条读取分支（§17.3-③）。建议改为「模型面零改动；档位面 = 适配层给 effort 面加上报分支」。
3. 体量：`thincoder_kernel.dart` 已 889 行（>800），本批 +≤60 ⇒ ≤950；裁定「本批不拆」，拆分触发已写（§17.4）。请设计评审 / 用户确认接受与否。
4. 分支口径：从 `feat/acp-subagent-attribution` HEAD（含批 5 提交 03392521）新建 `acp-config-options`；两批改动文件不相交。若父侧希望同分支执行，diff 不变，仅分支名不同。

**订正（2026-10-16 · 设计评审修正轮 1：#1–#12 落地；零代码）**

- ㉔ `thincoder_kernel.dart` 行数 889 → **899**（2026-10-16 只读实测，`wc -l`）；净增上界 ≤+60 ⇒ **≤959**（原 ≤950 随基数同步）。
- ㉕ `thincoder_mock.dart` 568 → **567**；新增第四个脚本参数 `configError`（错误面用例用）；增量 ≤+45 → **≤+55**。
- ㉖ 测试档 1846 → **1845**；用例 T51–T58 → **T51–T60**（+T59 / T60 = 两条写路径的错误面）；增量 ≤+200 → **≤+230**。
- out-of-repo：`acp.mjs` **157 行**（实测）、增量 +5 → **≈+8**（落地存活判据接线）；`handlers-session.mjs` 344 → **343 行**（同实测口径）。
- 新增 **§14-20**（模型清单后台推送的落地面：在册且同实例 ⇒ 推；已关 / 已替换 ⇒ 丢弃；`notify` 抛出 ⇒ 吞掉不抛）。
- §10 边界行自洽：`context` / `fast` = context-size / fast 选择器两面；`effort` 多档随批 6 落地（不在该边界内）。
- §17.4 补两行：kernel「拆分批已挂触发，下一批不得再叠行」；测试档体量行（仍在 >800 名单、缝沿用 §15.4 四组拆法、触发 = 独立拆分批；本批只加用例不动结构）。

**订正（2026-10-16 · 形态修正轮 2：审批自动档改到 composer 右下角小开关；用户 21:25 定形；零代码）**

- ㉗ 新增宿主档 `lib/chat/composer/composer.dart`（2069 行）：`ComposerPermissionSwitch`（图标 + 选中项 label + caution + hover + tooltip）+ `_buildToolbar` 放置分支；增量 ≤ +50（⇒ ≤2119）。
- ㉘ `test/composer_test.dart`（2097 行）：T61（两档 ⇒ 开关 / 五档 ⇒ 菜单 / 点开关 ⇒ `onSelected` 第二项）；增量 ≤ +70（⇒ ≤2167）。
- 「宿主零改动」口径作废：改为「宿主动 1 档（composer 的开关）+ 适配层」——设计 §17.1-③ / §17.4 / §17.5 D41 / §17.6 / §5.2 / §7 / §9 / §11 已同步。
- 通用规则：`permission.options.length == 2` ⇒ 右下角开关（on = 第二项、off = 第一项）；≥3 档 ⇒ 左簇菜单（Claude 5 档不动）；位置 = `_ContextRing` 左侧、`SizedBox(2)` 邻接，高 22。
- 审批两项 label 收短：`Ask` / `Auto`（开关文案 = 选中项 label；开态 = 用户截图的 `Auto` + 警示色）；description 不动（tooltip 第二句 = 点击后进入的那一项的 description）。
- l10n：0 新键——tooltip = 既有 `composerApprovalTitle` + 选项 description（英文占位，§14-19；本机无 `flutter gen-l10n`）；补齐窗口同 §14-19（SDK 就位轮）。
- 用例号：新增 T61（`test/composer_test.dart`）；T51 / T54 / T59 仍是数据面，UI 形见 T61。走查②③⑦按右下角开关改写（§17.9）。
- 本订正块替代 §2 前文相应表述（㉔–㉖ 不变；T51–T60 不变；「宿主零改动」句以本块为准）；设计档落点 = §17。

**订正（2026-10-16 · 形态修正轮 3：审批开关不用警示色，改「填充 pill / 纯文字」；用户 21:39 改形；零代码）**

- 设计 §17.1-③ 颜色条改写：**开 = 填充 pill**（底色 `button.secondaryHoverBackground`，图标 / 文字 `AppColors.text` 正常前景色，无描边）；**关 = 无底色**（透明，图标 / 文字 `AppColors.textMuted`）。开 / 关的差别只在「有没有底色」，`selected.caution` 在本面不再参与取色；数据面仍保留 `caution: true`（= 有风险语义），T51 断言不变。
- 同节随同步（同一节自洽）：选项表备注去「警示样式」；hover 句按开关态拆分（关态 hover = `toolbar.hoverBackground`，开态底色固定、hover 不变色）；「可见性」句改「开态填充 pill（关态纯文字）」。
- T61（`test/composer_test.dart`）断言改「开 = 有填充 / 关 = 无填充」+ 两个前景色；§17.6「一眼可见」行判据改 T61（去掉 `caution` 数据面）；§11 一句改「开态填充 pill、关态纯文字」；变更记录 +1 行。
- 受影响文件与增量不动（㉗ `composer.dart` ≤+50 / ㉘ `composer_test.dart` ≤+70，读数同轮 2）；tooltip / 动作 / 放置 / 尺寸不变。
- 口径更正（实读）：宿主无 `AppColors.foreground`——设计写 `AppColors.text`（`app_theme.dart:136`，值 = 主题 `foreground`）；`button.secondaryHoverBackground` 是既有 emphasized chip 的 hover / 展开色（静态底 = `button.secondaryBackground`，`composer_picker.dart:778-781`），本开关常驻用它作填充即达到参照图效果。
- 改动落点：`docs/design/thincoder-adapter.md:1076` / `:1087` / `:1088` / `:1094` / `:437` / `:1372` / `:1395` / `:1454`。
- 披露（按本单「不动其它章节」未改，待父侧裁定是否一扫）：§17.4 ㉗（`:1285`）仍写「+ caution」；§17.5 D41（`:1357`）「开态 caution」、D42（`:1358`）「右下角开关 + 警示色」；§17.9 走查②（`:1414`）③（`:1415`）「警示色」。

**订正（2026-10-16 · 语义修正轮：面板 always ⇒ 会话级 auto；用户 21:47 裁定；零代码）**

- **裁定**（用户 2026-10-16 21:47，对照终端 y/a/n 询问）：「每次询问的时候，也会问是否开 auto —— 我们也可以这样子做」⇒ 面板「Approve for this session」要真的把会话转到免审批。§17.1-④ 从「本批不改」改为**本批做（桌面侧）**。
- **本批条目 +1（F13 派生 · 桌面侧）**：面板选 always（`approve_always`）⇒ 先答本次 approve，**同一回合**追加一次 `set_config_option("autoApprove", true)`（写路径与右下角开关同一个 `_config('autoApprove', …)`）；失败（RPC 错 / 旧 CLI）⇒ 不影响本次批准、开关保持原状、零异常；选 once / reject ⇒ 零写。判据 = T62；设计落点 = §17.1-④。
- **语义**：终端 `a` = 批量放行（本次询问族）；本口径 = 会话级 auto（与终端 `/auto`、右下角开关同源）。为什么是会话级：服务端 `approve_always` 无记忆（`bridge.mjs:57-62`）、桌面无「本轮批量」面 ⇒ 会话级是唯一诚实的解释。
- **§2 前文两句按本块改**：「不属本批」里的「Approve for this session」的标签与语义改入本批（桌面侧）；「关键决策」摘要里的 D46「always」本批不改 → **always 行接会话级 auto（桌面侧）**，服务端仍不改。
- **用例**：+T62（紧接 T51；四个面 = always / once / reject / set 失败）；走查 +§17.9-9。
- **受影响文件**：㉔ kernel 增量 ≤+60 → **≤+66（⇒ ≤965）**（`answer` 分支，+6 行含注释）；㉖ 测试档 T51–T60 → **T51–T62**，增量 ≤+230 → **≤+290**；㉕ mock **零增**（既有 `autoApprove` / `configError` 参数够用）。
- **设计档落点**：§17.1-④ / §17.5 D46 / §17.6（+派生行；错误面 +T62④）/ §17.7（+T62）/ §17.8-3 / §17.9（+步 9）/ §10 / §9 / §14-18（已闭合）/ §17.4 ㉔㉕㉖ / 变更记录。
- **上抛（需求档 = 主 agent 的笔）**：F13 建议补一句验收「面板选 always ⇒ 会话级 auto 开（T62）」。
- **坐标订正（现场实读）**：`thincoder_kernel.dart` 现为 900 行；标签行 = `:588`、答复 = `:595-611`（设计原引 577 / 591-596 为旧快照，§17.1-④ 已按当前树改写）。
- **未做**：不改 CLI（`approve_always` 的服务端语义与 `name` 都不动）、不改协议、零代码。

**补记（2026-10-16 · 同轮实读：代码面并行落地）**

- `thincoder_kernel.dart` 现 **959 行**（批 6 其余改动已落）；`alwaysAllowLabel` = `:590`、`answer` = `:598-617`、`_config` = `:807-819`、`appEvent` = `:817`——上段「900 行 / 588 / 595-611」为旧快照，按本补记为准。
- 本单的行为**已在树内**：`answer` 末尾 4 行（注释一行 + `if (optionId == 'approve_always') { unawaited(_config('autoApprove', true)); }`）——与 §17.1-④ 语义一致；设计 diff 已按落地形对齐。实施读数与门禁以 §5 为准。

**追加（2026-10-16 · 父侧裁定，并进本轮；零代码）**

- **§17.4 ㉗ 增量改写**：`composer.dart` ≤+50（⇒ ≤2119）→ **≤+70（⇒ ≤2139；实交 2135 = +66）**。eng-coder 实测 2135（+66）；按 §17.1-③ 的形态（公开类 + IdeHover/HoverBuilder + 放置分支 + 两档判定 + localized）下限约 2123，原 +50 低估 10–16 行。纪律 = 结构不动、不删注释。
- **§17.4 体量/拆分行**：`composer.dart` 已 2135 行、远在 >800 线之上（仍在 >800 名单）；本批只加这一个控件；缝候选 = 右下角固定组（`_ContextRing` / `_SendButton` / 本开关）**整段出档**；触发 = 下一次结构级触碰或独立拆分批立项。
- **变更记录 +1 行**（设计档 `:1484`）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（批 6：F13 审批自动档 + F14 模型清单与思考档位）

| # | 类别 | 严重度 | 问题 | 建议 |
|---|------|--------|------|------|
| 1 | 文档状态一致性 | 🟡 | 变更记录声明改了 §10（`docs/design/thincoder-adapter.md:1409`「§10（例外口径；`effort 多档` 随批 6 落地）」），但 §10 正文无此句：`:422` 仍把「改名 / `context`·`fast` 档）」列为不做，规范面无从判读 `SelectsEffort` 档位面是否属该边界 | §10 边界行按批 6 现状改一处：注明 `context`·`fast` 指 context-size / fast 选择器（不含 `effort` 档位面），并落「`effort` 多档随批 6 落地」例外；或删掉变更记录里未落地的半句 |
| 2 | 受影响文件体量 | 🟡 | §17.4 ㉖ 给了测试档当前行数与增量（`:1257`「（1846 行）」/ ≤ +200），但无「>800 名单」体量裁定；同一档在批 4 / 批 5 都写过（`:934`「已在 >800 名单（缝候选 = 按 group 拆，§15.4）」） | 在 §17.4 补体量行：仍在 >800 名单、缝候选沿用 §15.4 四组拆法、触发 = 独立拆分批立项（或本批只加用例、不动结构） |
| 3 | 验收覆盖 / 标签 | 🟡 | §17.3-③ 把档位标签定为 `effortLabel`（`:1239`「High / X-High / Max / Off」）并称与 Claude 同一套词；同节探针期望却给 `low` / `medium` / `xhigh`（`:1308`「`options` 值 = `xhigh` / `medium` / `low`」）——词表外值按 §14-19 原样透出；T56 只挑「（off / high / max）」（`:1356`）⇒ 词表外值无验收用例 | 写清词表外档名的显示规则，并给 T56 补一档词表外值（如 `low`），使验收与探针期望一致 |
| 4 | 验收 / 错误条件 | 🟡 | 两条新写路径只有成功面用例（T51 / T56）；D20 说「不乐观改显示」（`:1076`「点完等 `config_option_update`」），但没有「服务端回 false ⇒ -32602 / 超时」时期望什么（显示不动？留痕？）的用例或登记 | 补错误面用例：`set_config_option` 回错误 ⇒ 选项显示保持回报值、零异常、连接不受影响；并注明是否留痕 |
| 5 | 体量裁定（已知） | 🔵 | `thincoder_kernel.dart` 889 → ≤950（`:1255`）在 >800 硬顶之上；`:1262`「**本批不拆（显式裁定）**」+ `:1263`「**拆分触发 = F13/F14 两面定形之后的独立拆分批**」= 缝与触发写全。按审前裁定不重审，仅记：本条在「缝/触发在场」意义下合规 | 交付后按该触发执行独立拆分批（缝 = 选择面整段出档），下一批不得再叠行 |
| 6 | 数字漂移 | 🔵 | 同档内 kernel 行数两说：`:317`「残余 885 行（2026-10-16 快照；批 4 +3 ⇒ 888）」vs `:1255` 的 889；测试档两说：`:927`「实交 +308（⇒ 1845）」vs `:1257` 的 1846 | 按实施前实测刷成同一读数（并同步 §15.4 ⑭ 的 885） |
| 7 | 受影响文件注记 | 🔵 | out-of-repo 表只给 `handlers-session.mjs` 当前行数（`:1264`「0.12.74 活树 344 行」）；`thincoder-cli/src/acp.mjs` 只有增量（`:1234`「`acp.mjs` +5 行」），当前行数缺 | 补 `acp.mjs` 活树当前行数（或注明其体量档） |
| 8 | 探针可复现性（unverified） | 🔵 | 探针 fixture 用合成供应商名（`:1294`「provider: { name: "p", model: "qwen3.8-max"」），期望却断言具体档位枚举（`:1308`）与强制思考族（`:1309`）；枚举来自 `providerSpec(agent?.provider)`（`:1146`/`:1160`），设计未写它按哪个字段取值 ⇒ 期望读数能否复现属 unverified | 注明 `providerSpec` 取值键（provider.name ∥ model ∥ 渠道类型），或把 fixture 换成真实 provider/model 对象 |
| 9 | 文档卫生 | 🔵 | 规范面留流程性批注：`:1018`「关键事实（**纠正原方向的一处假设**）」——被纠正的假设在档内不存在，读者会去翻旧设想 | 直接陈述事实（谁在审批阶段之前短路），沿革留变更记录 |
| 10 | 用例可写性 | 🔵 | T57② 写「mock 报 `thinkAlwaysOn` 的 `thinking`（无 off 档）」（`:1357`），`thinkAlwaysOn` 却是 CLI 侧 `providerSpec` 属性；mock 新参数只有 `autoApprove` / `models` / `thinkingLevels`（`:1256`） | 改写成 mock 参数层输入（如 `thinkingLevels: ['high','max']` + `thinking: true`） |
| 11 | 健壮性（未登记） | 🔵 | `refreshModelChoices` fire-and-forget（`:1106`），落地后直接 `notify("session/update", {`（`:1212`）——未写会话已 close / 进程退出后落地怎么办 | 明确落地时的会话存活判据（失效即丢弃且不抛），登记 §14 一条 |
| 12 | 覆盖陈述（unverified） | 🔵 | 模型清单拉取点只写 `defaultCreateSession`（`:1106`），未说明 `session/load` / `session/resume`（§3.5 续接主路）是否同经该装配 ⇒ 「清单与终端一致」在这两路上是否成立属 unverified | 一句话写清 load / resume 是否走同一工厂；若不经过，按旧 CLI 降级口径登记 |

计数：🔴 0 · 🟡 4 · 🔵 8。无 🔴 —— 需求覆盖（F13/F14 均有落点 + 验收对照 + 走查）、可行性、先例行（`:1003-1010` 对齐 ∥ 偏离）、文档归属（改 §17 本体，未新开档）均通过。

VERDICT: pass

## §4 用户批准（主 agent）

- **用户批准**（2026-10-16 21:42「批准」）：设计 §17（F13 审批自动档 + F14 模型清单与思考档位）及形态定稿（**composer 右下角 `Ask` / `Auto` 小开关**：开 = 填充 pill、关 = 纯文字；`selected.caution` 不参与取色；Claude 5 档菜单不动）通过。
- **批准前的链路**：设计评审 pass（0🔴 / 4🟡 / 8🔵）→ 修正轮 #39（11 条）→ 形态轮 #40（右下角开关 + 宿主一档口径）→ 改色轮 #41（填充 pill / 纯文字）→ 扫尾轮 #42（5 处残留）→ 父侧机械折行两处（`:1088` / `:1456`）。
- **实施分两轮**：① 本仓轮 = eng-coder（`thincoder_kernel.dart` 审批面 + 档位读 `thinkingLevel` + `thincoder_mock.dart` 四参数 + **`composer.dart` 右下角开关** + 用例 T51–T61）；② 跨仓轮 = 父侧直接执行（thincoder `handlers-session.mjs` / `acp.mjs` 暴露位 + 清单投影 + 存活判据 + 探针 + 门禁 + `ACP-CLIENT.md` / `CHANGELOG`）。
- **走查前置**：跨仓轮落地（新 CLI 形状）+ 本仓轮构建后，按 §17.9 八步走查（重点 ②③④⑦）。

## §5 实施记录（eng-coder）
**状态行**：实施完成 2026-10-16（含形态修正轮 4；审计 CLEAN / 评审 pass，终态 clean）



### 实施记录（eng-coder）

**范围**：§17 F13 审批自动档（内核 `permission` 两档 + composer 双档开关）+ F14 模型清单 / 思考档位读取面；含用户 2026-10-16 21:47 追加的「答 "Approve for this session" 时同一次处理里再写 `set_config_option('autoApprove', true)`」。

**落点与读数**（口径 = PowerShell `(Get-Content).Count`，与既有基线同口径）：

| 文件 | 基线 | 实交 | 上界（含裁定） |
|---|---|---|---|
| `lib/kernel/thincoder/thincoder_kernel.dart` | 903 | **958** | 959 |
| `lib/kernel/thincoder/thincoder_mock.dart` | 567 | **620** | 622 |
| `lib/chat/composer/composer.dart` | 2069 | **2138** | 2139（原 2119，父侧裁定改 ≤+70） |
| `test/kernel/thincoder_kernel_test.dart` | 1845 | **2133** | 2145（原 2075，父侧裁定改 ≤+300） |
| `test/composer_test.dart` | 2097 | **2183** | 2187（原 2167，父侧裁定改 ≤+90） |

**决策透明表**：

| 决策 | 依据 | 结果 |
|---|---|---|
| composer 终读 2138（非 2135） | 自审发现 3 处新增行超本仓 81 列：左簇判据折行、tooltip 三元折行、文字样式抽局部；净 +3 | 折行后仍 ≤2139；父侧记录里的 2135 需刷为 2138 |
| 测试档超原上界不压行 | 用户 21:47 追加 T62（always/once/reject/写失败四面）+ T61 自带两档 thincoder 描述符 harness | 父侧裁定 ≤2145 / ≤2187；断言一条未删 |
| `_ModelSetting` 构造参数改 `this._toggles` | analyzer `prefer_initializing_formals`（info，会破坏 analyze 清零） | 具名实参仍写 `toggles:`（Dart 初始化形参去掉下划线），行为不变 |
| 旧 CLI 答 always 仍发 autoApprove 写 | 用户 21:47 + 设计「不加能力预判」 | 失败只走 `_config` 的 catch（`appEvent`），不影响本次批准、开关不动（T62④） |
| 开关开态判据用 `options[1]` | 设计 §17.1-③ 逐字 | 仅双档调用点使用；未加构造断言（评审 #3，见下） |
| `pubspec.lock` 改动还原 | `flutter pub get` 把镜像地址统一改写成 pub.dev（环境副作用，非本单改动） | `git checkout -- pubspec.lock` 还原，`git status` 无残留 |

**验证读数**：

- `flutter test test/kernel/thincoder_kernel_test.dart test/composer_test.dart` → **117 passed**（kernel 63 / composer 54），0 failed。
- `flutter analyze lib/kernel/thincoder lib/chat/composer test/kernel test/composer_test.dart` → 仅 1 条**先存** warning：`test/composer_test.dart:997` 的 `clipboardPaste` experimental（既有代码，本批未触碰）；本批新增代码零 issue。
- 回归：`test/kernel/thincoder_fixtures_test.dart` + `test/kernel/thincoder_catalog_test.dart` → **27 passed**。
- 零改动核对：`git status --short` 仅 `M lib/chat/composer/composer.dart`、`M test/composer_test.dart`（其余为本单前既有未跟踪项）；`lib/kernel/claude_code/**` 无修改；`thincoder_events.dart` 内无 `autoApprove` / `thinkingLevel` / F13 / F14 新增面；`thincoder/**` **本单未写**（该目录的变更是父侧跨仓轮已落地的内容，审计已核对归属）。

**审计与评审轮次**：

- 内部 explore 偏差审计：**1 轮，CLEAN**（PARTIAL / SILENT-SIMPLIFICATION / DOC-DRIFT / OUT-OF-LIST 四类零命中）。
- 内部 advisor code review：**1 轮，verdict = pass**；1 条 🟡（可选：T62① 未直接断言「面板核销 / 工具照跑」）+ 6 条 🔵（判据重复、公开构件契约断言、mock 空表 `currentValue: null`、两连空行、存量 >81 列行、记录读数漂移）。
- 处置：按父侧「按现状收口」不再改码；7 条逐条处置写进交付报告，无 must-fix。
- 自修轮次：**1 轮**（自审：3 处 >81 列折行 + `_ModelSetting` analyzer info + `ChatSession(kernels:)` 测试装配）。
- **终态：clean（0 must-fix）**。

### 形态修正轮 4（拨动开关；用户 2026-10-16 22:12 定形）

**范围**：只动 `ComposerPermissionSwitch` 的形态与 T61 断言；面 / 语义 / 放置 / 内核 / mock / 左簇菜单 / Claude 面零改动。最终 `git status` 仅两档：`M lib/chat/composer/composer.dart`、`M test/composer_test.dart`（其余为单前既有未跟踪项）。

**改动表**

| 文件 | 位置 | 改动 | 行数（前 → 后） |
|---|---|---|---|
| `lib/chat/composer/composer.dart` | `:1910-1965` | 旧形（图标 + 选中项 label + 填充 pill，55 行）→ 拨动开关：track 35×20 / 圆角 10、knob 圆 16 内缩 2、`margin` 上下各 1 ⇒ 热区 35×22（`HitTestBehavior.opaque`）、两层 `AnimatedContainer` 140ms · easeOut、`alignment` centerLeft↔centerRight、开 = `AppColors.claude` track + `button.foreground` knob / 关 = 透明 track + 1px `AppColors.textFaint` 描边 + `textMuted` knob、无 Icon/Text、`Semantics(toggled, label)`、tooltip = title · 点击后那一项的 description；`_buildToolbar` 放置与两档判定不动 | 2138 → **2139**（≤2139） |
| `test/composer_test.dart` | `:489-570` | T61 断言改「位置 + 颜色」：关态 `centerLeft` / `Colors.transparent` / `textMuted`；零 `Text` / 零 `Icon`；点一次 ⇒ `set_config_option('autoApprove', true)`；回报后 `centerRight` / `AppColors.claude` / `button.foreground`；五档 ⇒ 无开关、`Ask for approval` 仍在 `ComposerPicker` | 2183 → **2184**（≤2187） |

**验证读数**

- `flutter test test/composer_test.dart` → **54 passed**，0 failed（T61 在内；最终注释改后再跑 `--no-pub` 同样 54 passed）。
- `flutter analyze lib/chat/composer test/composer_test.dart` → 仅 1 条**先存** warning：`test/composer_test.dart:998` 的 `clipboardPaste` experimental（既有代码，随本轮 +1 行位移）；本单新增代码 0 issue。
- 行数（逐行计数）：`composer.dart` **2139**（上界 2139）· `composer_test.dart` **2184**（上界 2187）；新增区段无 >81 列行。
- `pubspec.lock` 因 `flutter pub get` 的镜像改写副作用被还原（`git checkout -- pubspec.lock`）；最终 `git status` 无残留。

**决策透明表**

| 决策 | 依据 | 结果 |
|---|---|---|
| `next` 用 `options[on ? 0 : 1]` | 本控件只在两档时构造（`_buildToolbar` 判 `length == 2`）；`on` 本身按 `options[1]` 定义 ⇒ 另一项即另一下标 | 与旧 `firstWhere` 在两档下等价；省一行且不引入新假设 |
| tooltip 用 `[title, next.description].where(isNotEmpty).join(' · ')` | 设计句 = title + ` · ` + 点击后那一项的 description；旧形在空 description 时只显示 title | 行为保持；单行 ≤80 列 |
| 两参数压一行（构造器 `:1914`、`:1932`、`:1939`、`:1953`） | 展开成一行一参数为 +4 行（⇒ 2143）越过 ≤2139 硬上界；不删注释、不减语义 | 披露：排版偏离本档同类 widget；评审排版建议记为未采纳（行数原因） |
| 未加尺寸 / 动画断言 | 设计 §17.7 T61 口径 = 「位置 + 颜色」，本轮按此逐条落 | 评审 #1（🟡 可选）不采纳；形态回归哨兵缺失记为本轮已知余量 |

**审计与评审轮次**

- 内部 explore 偏差审计：**1 轮，CLEAN**（PARTIAL / SILENT-SIMPLIFICATION / DOC-DRIFT / OUT-OF-LIST 四类零命中）。
- 内部 advisor code review：**1 轮，verdict = pass**（0 🔴；1 条 🟡 可选 = 几何/动画无断言；5 条 🔵 = 字段注释归属、压行排版、测试按位置取 `AnimatedContainer`、设计档坐标 `:1911-1964` 漂移、读数漂移）。
- 处置：🔵 注释归属已改为合并描述（不增行）；其余 🔵 / 🟡 按行数上界与设计口径保留，逐条理由见交付报告。
- 自修轮次：**1 轮**（评审后注释措辞）。
- **终态：clean（0 must-fix）**。

**披露（归父侧 / 设计层）**

- 设计档坐标与读数随本形漂移：§17.1-③ 落点 `:1911-1964` → 现 `:1911-1965`；§17.4 ㉗/㉘ 与体量行的「实交 2135 / 2183」为改形前读数，现为 2139 / 2184——设计档由 eng-designer 的笔刷新。
- 批次档 §2 无独立「形态修正轮 4」块（记录只在设计档变更记录 `:1495-1497`）；本轮按父侧单据 + 设计 §17.1-③ 执行。

## §6 验证与收口（父代理）

**交付面**：F13 审批自动档（右下角拨动开关 + 面板 always ⇒ 会话级 auto）+ F14 模型清单与思考档位（CLI 投影 + 桌面档位面）。

**验证读数（父侧实跑）**

| 面 | 读数 |
|---|---|
| 本仓测试 | `flutter test test/kernel/thincoder_kernel_test.dart test/composer_test.dart test/kernel/thincoder_fixtures_test.dart` ⇒ **135 passed**（kernel 63 / composer 54 / 固件 18；形态改形后 composer 54 单独复跑仍绿） |
| analyze | 本批 0 issue；剩 1 条**先存** warning（`test/composer_test.dart:998` `clipboardPaste` experimental，既有代码）——不在本批范围，登记为存量 |
| 行数 | kernel 958/959 · mock 620/622 · composer **2139/2139** · composer_test 2184/2187 · kernel_test 2133/2145 |
| thincoder 侧（跨仓轮） | 探针 **19/19**（一次性，跑完即删）· `npm run lint` 126 files OK · `node --check` 三档 OK · 提交 `a2ca3ef0`（分支 `feat/acp-subagent-attribution`）· `handlers-session.mjs` 344→427（+83，超设计估 ≈+60——多出的 = 三个 helper + 落地判据，已在设计 §17.4 按实交注记） |
| 真机走查 | 用户 2026-10-17 01:11「可以的」：开关形态/颜色（`#E2B373`）+ 开态不弹审批 + always 真生效（§17.9 ②③④⑨） |

**集成测试**：本批未跑集成套件——该面以用户真机走查为唯一验收（同一会话内跑 `bash`、看审批与开关联动）；单元用例面 = `test/kernel/thincoder_kernel_test.dart`（T51–T62）+ `test/composer_test.dart`（T61），随仓长期保留。

**流程记录**：设计 §17（4 轮形态修正 + 1 轮语义修正）· 设计评审全过 0 🔴 · 实现 1 轮（#43，内部审计/代码评审各 1 轮，终态 clean）· 形态修 1 轮（#48）· 跨仓轮 1 轮（父侧 out-of-repo）。

**结算前核对**：台账 #16（模型清单）· #17（审批自动档）核销；需求档 F13 / F14 验收句与实况一致（含 21:47 追加的 always 语义）；设计档无未决 🔴；批次档 §2/§4/§5 状态行就位。

**暂缓批复核**：无。

**未决（保留指针）**：① 存量 analyze warning（`clipboardPaste`）——如需清零另起一笔；② 设计档有 5 行 >300 字符（§17 表格行，`read` 口径）——属全仓既有 doc-check 债的一部分，不单独处理。

**状态**：已收口 2026-10-17。
