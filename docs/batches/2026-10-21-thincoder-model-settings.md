# 2026-10-21 · thincoder-model-settings
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-21 · 来源 = 用户 2026-10-21 23:38「还得想一下模型添加的问题…要留一个模型添加的地方，或者直接获取 thincoder 的模型，我可以保证我用户的电脑里面都有 thincoder」· 23:40「走 B 吧」。
> 台账 = #136（thincoder-adapter · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-22
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**三条上抛的裁定（主 agent，2026-10-21 23:45）**

| # | 上抛 | 裁定 | 理由 |
|---|---|---|---|
| ① | 需求 ⑥「显示 CLI 给的原因串」本机无法照字面实现（`defaultModelReason` 只在 core，ACP 面无投影） | **接受设计的替代**：宿主按同判据复述两句（「未配置任何 provider」/「defaultModel 未设置」），并把"原因串由谁生成"写进设计；**不为此改外仓** | 复述的两句话与 core 的两条判据一一对应；为两句话开外仓批次不划算。真要把串传出来，记入台账条件项（触碰 ACP 投影面时） |
| ② | F23 未实施 ⇒ 本批默认写 `~/.thincoder/config.json` | **接受** | 与既有裁定一致：写入目标 = 内核实际读的那份；F23 落地时只换环境来源，解析函数零改 |
| ③ | 本批不做供应商删除（会牵出 `cascadeRemoveProvider` 的 `consultModels` / `subagentModels` 连带面） | **接受：本批不做删除** | 删除是新增语义（连带面属另一个决定）；本批只要"能加、能改、能选"。若以后要删，另立条目 |

**设计位置**：`docs/design/thincoder-adapter.md` §27（`:3786`–`:3991`，27.1–27.12）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**状态行**：✅ 设计完成 · 2026-10-21

**本批覆盖（需求档 F24，`docs/requirements/thincoder-adapter.md:170-175`）**

| 需求条目 | 本批 | 判据（回指设计档 §27） |
|---|---|---|
| 功能点 ① 模型列表来自 CLI，不另建目录 | ✅ | §27.1 / §27.8 ①；`thincoder_choices.dart:46-53` 零改 |
| 功能点 ② 设置页「模型（thincoder）」：当前模型 + 候选 + 刷新 | ✅ | §27.5 ②③；新 `SettingsSection.thincoderModels` |
| 功能点 ③ 供应商编辑（名字 / Base URL / API Key / 模型名） | ✅ | §27.3 合并算法 + §27.5 ⑥ |
| 功能点 ④ 写入目标 = 内核实际读的那份（`THINCODER_CONFIG_DIR` → 否则 `~/.thincoder`） | ✅ | §27.2 解析函数 + 两种初值 |
| 功能点 ⑤ 写入安全（原子写、`.bak`、0600、回读） | ✅ | §27.3 九步 |
| 功能点 ⑥ 空态引导 + 原因串显示 | ✅（原因串按同判据复述，见知会 ①） | §27.5 ④ |
| 验收 ①–⑥ | ✅ 逐条对照 | §27.8 |
| 边界：不做本地模型目录 / 多供应商并行探测 / 密钥进凭据库 / 接管其它键 / 不改外仓 | ✅ 全部守住 | §27.11 |

**设计档落点**：`docs/design/thincoder-adapter.md` 新增 **§27 模型配置面（批 18；F24）**，节号 27.1–27.12（决议 / 解析 / 写入 / 字段口径 / UI / 可见性 / 用例 / 验收对照 / 受影响文件 / 回滚 / 边界 / 未验证项）。

**机制设计（六条要求逐条落点）**

1. **模型列表不另建**：清单仍来自 ACP `configOptions.model` 与 `config_option_update`；`thincoder_choices.dart:46-53` 只投影（文件零改）。「刷新」= 重开会话（现有入口 `ThincoderKernel.restart()`），不新造协议。
2. **设置页**：新页 `lib/settings/pages/thincoder_models_page.dart`（七区：配置位置 / 当前模型 / 候选 / 空态 / 供应商列表 / 表单 / 错误态）；导航项 `SettingsSection.thincoderModels` 排在 `models` 之后；密钥框 `obscure: true`，保存后只显示末四位。
3. **写入器**：`lib/kernel/thincoder/thincoder_config_store.dart` —— 写前 stat→read（`t0`）→ 解析（非法 JSON 零写）→ 只合并 `providers[]` 与顶层 `defaultModel` → `.bak` → 临时文件 + rename（失败回退直写）→ chmod 0600 尽力 → 冲突门（`t0 != t1` 放弃 + `.bak-<ts>`）→ 回读断言。「其它键逐字不变」机检 = 删两处键后规范化编码逐字相等（§27.3）。
4. **写入目标**：`lib/kernel/thincoder/thincoder_config_file.dart` 的 `resolveThincoderConfigDir(environment)`：`THINCODER_CONFIG_DIR` 非空 → 用它（展开 `~`），否则 `~/.thincoder`；目录 / 文件缺失都读作 `{}`。环境来源是一处缝（默认 `ClaudeEnvironment.of`，同 `thincoder_locator.dart:83`），F23 注入后换来源、解析函数零改 —— 同一判据。
5. **可见性闭环**：选「重开会话」。`config_option_update` 不可行（运行中 agent 不重读磁盘、ACP 无重读方法、新造方法 = 改外仓）；「下次会话生效」不可感知；`restart()` 是现有入口（`thincoder_kernel.dart:563-568`，`chat_session.dart:398`）。保存后**不自动重启**（会掐断在飞回合，与 F21 冲突），页面给提示 + 按钮。
6. **debug 一致**：解析只由 env 决定，零 `kReleaseMode`、零开关。

**受影响文件（现值 → delta，行数本轮实测）**：新增 `thincoder_config_file.dart`（≈90）· `thincoder_config_store.dart`（≈200）· `thincoder_models_page.dart`（≈420）· `test/kernel/thincoder_config_store_test.dart`（≈260，T118–T125）· `test/settings/thincoder_models_page_test.dart`（≈140，T127）；改 `settings_dialog.dart`（841 → ≈+15）· `app_settings.dart`（290 → ≈+12）。零改动：`thincoder_choices.dart`（285）· `thincoder_kernel.dart`（1409）· `chat_session.dart`（1340）· 外仓 `thincoder/**` · l10n 资源档（本批字面串，归台账 #7）。

**验收对照**：§27.8 六行表，逐条给落点 + 机制 + 机检编号（T118–T127）。

**关键决策**

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D113 | 宿主（Dart）写 `config.json`，不调 CLI 写 | ACP 方法面无配置写入口（`handlers-session.mjs:2-5`）；子进程一次性，无 IPC 写面 |
| D114 | 只合并 `providers[]` 与顶层 `defaultModel`，条目其它键保留 | F24 边界「只写这两面」；`format` / `proxy` / `context` 属用户既有配置 |
| D115 | 编辑态密钥留空 = 保留原值 | 密钥不回显（F24 边界 + 本批方法要求）；空串覆盖会把已存 key 抹掉 |
| D116 | 可见性 = 重开会话（用户点按钮） | §27.6 三选一表；自动重启与 F21 冲突 |
| D117 | 本批不做供应商删除 | 删除牵出 `cascadeRemoveProvider` 的 `consultModels` / `subagentModels` 连带面（`config-io.mjs:178-196`），属代理配置，超出 F24 |
| D118 | 原因串由宿主按同判据复述，不新增传输 | `defaultModelReason` 只在 core（`model-ref.mjs:69`、`config.mjs:303`），宿主侧零命中（见知会 ①） |

**测试覆盖**：T118 空配置读 · T119 新建 · T120 其它键逐字不变 · T121 更新已有 · T122 只读目录 · T123 非法 JSON · T124 目标解析（含 `~/.thincoder` mtime 不变）· T125 CLI 读得进（离线固件）· T126 重开会话后 model 项出现 · T127 密钥不回显 / 不落日志。

**[上抛·知会] ① 原因串的传输面**：需求 F24 功能点 ⑥ 写「显示 CLI 给的原因串」。实读 `defaultModelReason` 只存在于 core 并被 `config.mjs:303` 消费，CLI 的 ACP 面与宿主侧均无该串（`grep` 零命中）⇒ 宿主无法「拿到」CLI 的串，只能按同一判据复述两条文案（§27.5 ④）。不阻塞本批；若要把串真正从 CLI 传出来，属外仓改动，需另开批次。

**[上抛·知会] ② F23 尚未实施**：`THINCODER_CONFIG_DIR` 在 `lib/**` 零命中，故本批默认目标就是 `~/.thincoder/config.json`；F23 落地时按 §27.2 换环境来源即可，同一判据、无需改解析函数。

**[上抛·待裁] ③ 未验证项**（不影响本批实施）：U13 原因串是否另有 ACP 投影面 · U14 真机「CLI 读得进」 · U15 `app_settings` 取活会话的访问器名（缝形已定，只差名字）· U16 Windows 上 Dart `File.rename` 覆盖语义。

**第二轮评审 4 条非阻断项收口（小修正轮 · 2026-10-21 · 只改设计档，不写代码）**

| 评审# | 处置 | 落点（设计档现文） |
|---|---|---|
| 16 | 删规则：`name` 校验只留「trim 后非空 / 不含 `:`」（**不给预设名镜像表、不给同步判据 ⇒ 按下令删掉该子规则**）；T130 同步去掉「与预设名冲突」输入项与它对 `invalidField` 的计数 | `:3908`（校验行）· `:3968`（T130） |
| 17 | §27.9 补 ⑧ 行：`test/kernel/thincoder_kernel_test.dart` 现值 4299、T126 落它、delta ≈ +60；并补该档的体量立场（>800 名单：只末尾追加一个 `testWidgets`、不动结构；缝候选照 §5.2 已记的测试档四组拆法；触发 = 下一次结构级触碰或独立拆分批立项） | `:3994`（⑧ 行）· `:3998`（体量立场） |
| 18 | §27.8 ④ 行：判据列换成需求现文（三路零写 + 冲突留 `config.json.bak-<ts>` 现场）；落点列补第 4 步；机检列补 T130，并把「`.bak` 存在、原文件仍可读」的旧句换成「三路零写由 T122 / T123 / T130 断言、`.bak-<ts>` 只由 T128 断言」 | `:3979` |
| 20 | 两处 B3 旧义标签去掉（句子语义保留）：D9「要用户的 key（B3 张力）」→「要用户的 key」；D84「桌面不读 provider 规格（B3 / E3）」→「桌面不读 provider 规格」 | `:357` · `:2728` |

- **第 16 条的取舍理由（记在这里，不进设计档）**：预设名冲突拒收只发生在 CLI 的加条目路径；直接写 `providers[]` 时 CLI 读侧不查该条件 ⇒ 它不是我们写盘的必要条件（需求 F24 ③ 只要求「写 CLI 认识的条目」）。本仓无预设名表、不新造镜像表与同步判据。
- **设计档行数**：4024 → **4026**（+2：⑧ 行 + 体量立场行；其余四条为同行改写）。
- **机检**：`DOC-CHECK GATE: PASS`（0 条命中，1 档全清）。
- 受影响文件清单同步：本批**新增** `test/kernel/thincoder_kernel_test.dart`（4299 → ≈ +60），其余清单不变；该档不在原「零改动」名单内，无需改动零改动行。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（§27 模型配置面 / F24）

**核对口径**：设计档 §27（`docs/design/thincoder-adapter.md:3786-3998`）与需求档 F24（`docs/requirements/thincoder-adapter.md:171-177`）全文实读；为判「可行性 / 体量标注」两项，按 §27 自己给出的坐标做了定点核对（未做代码走查）。**无 AGENTS.md / 无项目标准档 / 无文档地图** ⇒ 方法论与文档归属两项按本档既有章法判，归属检查降级。

**定点核对读数**：`settings_dialog.dart` 841（:3974 一致）· `app_settings.dart` 290（:3975 一致）· `thincoder_kernel.dart` 1409（:3979 一致）· `thincoder_choices.dart` 实测 286（:3979 记 285）· `AppPaths.home` 在位（`lib/platform/app_paths.dart:1`）· `ClaudeEnvironment.of` 在 `thincoder_locator.dart:83`（与 :3836 一致）· `restart()` 在 `thincoder_kernel.dart:564`（与 :3812 一致）· `SettingsSection` 枚举 / `buildPage` case 面在位 · `AppSettings.workspace` 在位（`app_settings.dart:81`）· `_Field.obscure` 在 `models_page.dart:2164`（一致）· `configDir` / `writeConfigAtomic` / `resolveProviders` 在 `thincoder-core/config-io.mjs:32/59/146`（与 §27.4 一致）· `model` 项 push 条件在 `handlers-session.mjs:49-53`（一致）。⇒ 需求面与体量面**无阻塞性缺陷**。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|---|---|---|---|
| 1 | 文档归属 / 需求基线 | 🔴 | §4 F10 与 §10 仍写「桌面不写 config.json」（`:260`「模型/供应商配置只读：桌面不写 `~/.thincoder/config.json`」；`:399`「B1–B4 遵守」），§27.1 的写入目标正是同一份（`:3809`）。需求档同对矛盾在场：`:232`「桌面端只读取使用」/ `:80` / `:107` vs `:174`「写共享配置时**只写 provider/defaultModel 两个面**」 | 需求档把 B3 收窄为「不代管账号/账单用量」，明写 provider/key 编辑面由 F24 承接、写面仅 providers[] 与 defaultModel；同步改设计档 `:260` / `:399` / `:1511` / `:2999` / `:3084` / `:3109` 的 B3 措辞 |
| 2 | 可行性 / 写入形状 | 🔴 | §27.3 步骤序把并发门放在写之后：第 5 步已「`rename` 覆盖目标」（`:3867`），第 7 步才「写前重取 `t1`…`t0 != t1` ⇒ 不写」（`:3869`）⇒ 判据「并发改配置 ⇒ 提示重试，不吞对端新值」落空。先例顺序相反：`config-io.mjs:76` 取 t1 → `:77` 比对 → `:83` 才写 | 按先例重排：stat t0 → 读 → 解析 → 合并 → 重取 t1 → 冲突留 `.bak-<ts>` 零写 → 复制 `.bak` → 临时文件 + rename → chmod → 回读断言；编号即执行序 |
| 3 | 可行性 / 敏感面 | 🟡 | 第 4 步自造滚动 `config.json.bak`（`:3866`），先例只在冲突时写 `.bak-{ts}`（`config-io.mjs:50` / `:78`）；第 6 步 0600 只作用于 `path`（`:3868`）⇒ 每次保存多一份未收紧权限的明文 key 副本，与 `:3989`「明文在 `config.json`，0600 尽力而为」及 `:3797`「逐条照搬判据，不新造」不一致 | 二选一写明：只留冲突现场 `.bak-<ts>`；或保留滚动 `.bak` 但同写即 chmod 600 并把它写进敏感面边界 |
| 4 | 最近先例 | 🟡 | 先例表（`:3795-3797`）漏掉最贴近的一个：外仓已有 provider 编辑面（`thincoder-desktop/src/main/providers.mjs:5` 写面纪律、`docs/desktop/design/SETTINGS.md:15` KD-10「端侧零自写盘、零 provider 形状构造」、`IPC.md` 的 `provider:*` 族含遮罩钥）；survey 行把外仓口径限定为 `config.mjs:1-12`（`:3801`）⇒「Dart 自写盘 + 自造 provider 形状 + 自定遮罩」这一偏离无坐标无理由 | 把外仓 desktop/VSC 的 provider 面列入对齐/偏离表；对齐其字段构造与遮罩判据，或写明必须自造的理由（无 node 通道 / 跨进程写用户配置）；KD-10 的偏离须显式 |
| 5 | 需求覆盖 / 校验 | 🟡 | 四个输入无校验口径（`:3925` 只有「编辑态密钥框留空 = 保留原值」，`:3865` 只拒「`apiKey` 空」）；先例有校验（`config-io.mjs:246` / `:248-249` / `:247` 预设名冲突）。后果可机读：`name` 含 `:` ⇒ `defaultModel` 在首个冒号处切开（`config-io.mjs:169`）⇒ 静默回退首渠道（`:172`）；`name` 空 ⇒ 条目被过滤（`:149`），而 T119/T121 仍绿 | 补字段规则（name 非空且不含 `:`、不与预设名冲突；baseURL 非空归一；`providers` 非数组按 `[]`），⑦ 增 `invalidField`，T 表补对应用例 |
| 6 | 验收（错误路径） | 🟡 | ⑦ 列四种错误态（`:3926`），T118–T127 只机检 `invalidJson` / `ioError`；`conflict`、`verifyFailed` 无用例。AC ④ 的「`.bak` 存在、原文件仍可读」（需求 `:176`）无断言，且只读目录场景（T122）`.bak` 不可能生成 | 补冲突用例与回读失败用例；把「`.bak` 存在」挂到冲突用例，并说明只读目录 / 非法 JSON 两路是「零写」而非「留现场」 |
| 7 | 验收（可证性） | 🟡 | T126「保存后可见性」用 mock 对端（`:3953`）：mock 是脚本化对端，`configOptions` 由用例给出 ⇒ 只证明脚本，不证明「写进文件 ⇒ CLI 读出」 | 明写 T126 的覆盖面（翻译/投影 + `restart()` 宿主链路），文件 → CLI → ACP 链的判据归 T125 + 真机（U14），别混成一条 |
| 8 | 需求覆盖（F24 ②） | 🟡 | §27.5 ③ 显隐判据与同行内容自相矛盾：内容「拉不到 ⇒ 只有当前值一项 + 「刷新」按钮」（`:3922`），判据「候选数 > 1」⇒ 只有一项时整块隐藏、刷新动作永不可达 | 判据改「有活会话即显示」，候选 ≤1 时只出当前值行 + 「刷新」；或把刷新移到 ② 常显行 |
| 9 | 需求覆盖 / 档状态 | 🟡 | §7 一致链表（`:374-397`）只到 F22，`:399` 又断言「F1–F7、F10–F22、E1–E5 全部有落点」+「B1–B4 遵守」⇒ F23 / F24 无落点行，且 B 段断言与 #1 冲突 | §7 补 F23 / F24 两行（§26 / §27），B 段改成「B1–B4 遵守；B3 由 F24 收窄」 |
| 10 | 清晰度 / UI 机制 | 🟡 | ⑤ 行操作「设为默认」（`:3924`）无机制：`providers[].model` 已退役且第 3 步「`model` 键若在则删」（`:3865`）⇒ 条目上无模型名可合成 `'<name>:<model>'` | 二选一写死：去掉该动作（默认模型只由 ⑥ 保存时置位）；或动作 = 打开 ⑥ 预填、模型名仍由用户输入 |
| 11 | 内部判据冲突 | 🟡 | §27.2 多一层 CLI 没有的 `~` 展开（`:3827`），CLI 取值原样（`config-io.mjs:32`；§26.5 `:3641` 同形）⇒ 本档自己的判据（`:3837`「写的那份 == 子进程环境里解析出来的那份」）在 shell 导出 `~/…` 时失效 | 去掉 `~` 展开（逐字一致，最省）；或把展开写进外仓 `thincoderHome` 的同批改动并回填 §26.5 表 |
| 12 | 受影响文件体量标注 | 🟡 | `settings_dialog.dart` 841 行（本轮实读一致）已过 >800 硬顶，本批 +≈15（`:3974`），§27 无体量立场句——本档通例是给「结构不动 / 缝候选 / 触发」三件（`:3462`、`:670`） | §27.9 补一行体量立场：只加四点、不动结构；缝候选 = `SettingsSection` 与页构造映射族；触发 = 独立拆分批立项 |
| 13 | 清晰度（序列化） | 🔵 | 序列化形状未定：先例 `JSON.stringify(raw,null,2) + "\n"`（`config-io.mjs:83`），本档第 5 步只说临时文件 + rename（`:3867`），「逐字不变」机检又是规范化比较（`:3875-3885`） | 写明 2 空格缩进 + 末尾换行 + UTF-8（同 `config-io.mjs:83`） |
| 14 | 引用漂移 | 🔵 | 回指写 `docs/requirements/thincoder-adapter.md:170-175`（`:3788`）但验收在 `:176`；§27.5 引 `general_page.dart:801-857`（`:3795`）而 `_ThincoderPathSetting` 自 `:803` 起；`:3979` 记 `thincoder_choices.dart` 285、实测 286 | 区间改 `:171-177`；两处行号按实读回填；行数按 `wc -l` 复核 |

**计数**：🔴 2 · 🟡 10 · 🔵 2（共 14）

**VERDICT: changes-required**

### 轮次 2（评审子代理）

### 第二轮复核（设计 §27 + 需求 F24）

| # | Orig# | File | Severity | Status | Notes |
|---|-------|------|----------|--------|-------|
| 1 | 1 | docs/requirements/thincoder-adapter.md:232 | 🔴→closed | Fixed | B3 已收窄：「**B3** 不代管**账号 / 账单用量**：用量与限额只读、不代管；**provider / key 的编辑面由 F24 承接**——只写 `providers[]` 与顶层 `defaultModel`」；设计侧 :260 / :401 同步改写 |
| 2 | 2 | docs/design/thincoder-adapter.md:3872 | 🔴→closed | Fixed | 步骤序已改对：5=重取 t1（「这是并发门的唯一判定点，位于任何写盘动作之前」）→ 6=t0 != t1 ⇒ 零写 → 7=临时文件 + rename |
| 3 | 3 | docs/design/thincoder-adapter.md:4009 | 🟡 | Fixed | 「不做滚动 `.bak`：每次保存不产生额外明文副本，只在并发冲突时按先例留一份」；步骤 6 同义；T128 断言无滚动 `.bak` |
| 4 | 4 | docs/design/thincoder-adapter.md:3802 | 🟡 | Fixed | 补「对齐 ④」外仓 provider 编辑面 + 「偏离 ③」Dart 自造形状的理由；survey 行同步给坐标 |
| 5 | 5 | docs/design/thincoder-adapter.md:3908 | 🟡 | Fixed | 新增 name / baseURL / providers 非数组三类校验 + 步骤 4 零写 + T130 |
| 6 | 6 | docs/design/thincoder-adapter.md:3966 | 🟡 | Fixed | 补 T128 冲突 / T129 回读失败；§27.8 ④ 指向 T128；需求 :176 ④ 已改成三路零写 + 冲突留现场 |
| 7 | 7 | docs/design/thincoder-adapter.md:3964 | 🟡 | Fixed | T126 显式限定「**不**证明「文件 → CLI → ACP」」+ :3970 分工段 |
| 8 | 8 | docs/design/thincoder-adapter.md:3931 | 🟡 | Fixed | ③ 判据改「有活会话即显示（与 ② 同判据 `probe() != null`）」 |
| 9 | 9 | docs/design/thincoder-adapter.md:401 | 🟡 | Fixed | §7 补 F23 / F24 行；B 段改「B1–B4 遵守，B3 由 F24 收窄」 |
| 10 | 10 | docs/design/thincoder-adapter.md:3937 | 🟡 | Fixed | 「设为默认」不做 + 理由；⑤ 行操作只剩「编辑」 |
| 11 | 11 | docs/design/thincoder-adapter.md:3842 | 🟡 | Fixed | 判据改「不展开 `~`」并记被否方案 |
| 12 | 12 | docs/design/thincoder-adapter.md:3996 | 🟡 | Fixed | 补体量立场（结构不动 / 缝候选 / 触发） |
| 13 | 13 | docs/design/thincoder-adapter.md:3874 | 🔵 | Fixed | 步骤 7 写死序列化（2 空格 + 末尾换行 + UTF-8） |
| 14 | 14 | docs/design/thincoder-adapter.md:3790 | 🔵 | Fixed | 回指改 `:171-177`；`general_page.dart:803-857`；`thincoder_choices.dart`（286） |
| 15 | (new, 残 1) | docs/requirements/thincoder-adapter.md:107 | 🟡 | New | F14 边界仍写「桌面不代管 provider / key（B3 不变）」，是 B3 改写时漏改的一处（F10 :80 已改）；权威已在 B3 落定，属批 6 条目残句 |
| 16 | (new) | docs/design/thincoder-adapter.md:3908 | 🟡 | New | 新增校验「不与预设名冲突」未给来源：预设名单只在外仓，本档未写 Dart 侧从哪取（T130 同样要它） |
| 17 | (new) | docs/design/thincoder-adapter.md:3992 | 🟡 | New | T126 无用例归属文件：⑥ 只列 T118–T125 · T128–T130，⑦ 只列 T127；能承载它的 `thincoder_kernel_test.dart`（4299）未进清单也未进零改动 |
| 18 | (new) | docs/design/thincoder-adapter.md:3979 | 🔵 | New | §27.8 ④ 未含需求的第三路（字段不合法）与 T130；且仍引已被需求改掉的旧句「「`.bak` 存在、原文件仍可读」」 |
| 19 | (new) | docs/design/thincoder-adapter.md:3962 | 🔵 | New | T124 断言真实 `~/.thincoder` 的 mtime 前后相同（全局机器状态，目录不存在即 stat 抛）——建议把 HOME/USERPROFILE 指到临时目录 |
| 20 | (new) | docs/design/thincoder-adapter.md:357 | 🔵 | New | B3 旧义标签残留（:357「B3 张力」、:2728「B3 / E3」）：语义仍成立但标签已指向收窄后的规则 |

计数：🔴 0（前轮 2 条均已 Fixed）· 🟡 3 新增 · 🔵 3 新增；前轮 14 条全部 Fixed。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（主 agent 记录）

**用户 2026-10-22 00:02 逐字：「批准」。**

范围 = `docs/design/thincoder-adapter.md` §27（4026 行，两轮评审已过）+ 需求档 F24（`docs/requirements/thincoder-adapter.md:171-177`）。

批准前已完成：
- 评审轮 1 = changes-required（🔴 2 / 🟡 10 / 🔵 2，见 §3），未签发 token。
- 修正轮（eng-designer #13）落地 14 条；主 agent 核验：步骤表 10 步执行序（`:3860-3877`）、B3 五处口径、不做滚动 `.bak`（`:4009`）、去掉 `~` 展开（`:3842`）、T128–T130。
- 评审轮 2 = **pass**（新增 🟡 3 / 🔵 3）。
- 小修正轮（eng-designer #17）收掉 16 / 17 / 18 / 20：删「预设名冲突」子规则、补 T126 归属文件 + >800 体量立场、验收 ④ 补第 4 步与 T130、去掉两处 B3 旧标签；设计档 4024 → **4026**；机检门 PASS。
- 主 agent 核验：#17 报告的三条检索实测成立（`预设名` 0 命中、`B3 张力` / `B3 / E3` 0 命中、§27.9 ⑧ 行在 `:3994`）。

**实施范围**：8 个文件（3 新增源码 + 2 接线 + 3 测试档），设计 token 已随派单携带。

## §5 实施记录（eng-coder）

**状态行**：实施完成（内部审计 1 轮 + 代码评审 2 轮，终态 clean；余项 9 条按评审判可选并单列于 §5）

**交付清单（8 档 + 2 档清单外，逐条登记）**

| # | 文件 | 一句话 | 行数（实测） |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_config_file.dart` | 解析 CLI 读的那份 `config.json`：`THINCODER_CONFIG_DIR` trim 非空原样用（不展开 `~`），否则 `AppPaths.home/.thincoder`；环境缝 `thincoderEnvironment` 默认 `ClaudeEnvironment.of` | 新增 31 |
| ② | `lib/kernel/thincoder/thincoder_config_store.dart` | 十步写入器：stat t0 → 读 → 解析 → 校验+合并 → 重取 t1 → 冲突零写 + `bak-<ts>` → tmp + rename（失败直写）→ chmod 600 → 回读断言 | 新增 497 |
| ③ | `lib/settings/pages/thincoder_models_page.dart` | 七区页面：配置位置 / 当前模型 / 候选 / 空态 / 供应商列表 / 表单 / 错误态 | 新增 579 |
| ④ | `lib/settings/settings_dialog.dart` | 枚举 + 分类位 + `serverProcess` 图标 + label「Models (thincoder)」+ keywords 字面串 | +11 |
| ⑤ | `lib/settings/app_settings.dart` | `buildPage` 一个 case + 活会话探针 `thincoderModelSession()`（U15 落定） | +32 |
| ⑥ | `test/kernel/thincoder_config_store_test.dart` | T118–T125 · T128–T130 + 空模型拒绝 + U16 改名覆盖 | 新增 541 |
| ⑦ | `test/settings/thincoder_models_page_test.dart` | 空态 / 错误态 / 遮显（T127）/ 同名更新提示 / 编辑非默认供应商被拒 | 新增 387 |
| ⑧ | `test/kernel/thincoder_kernel_test.dart` | 末尾追加 T126（宿主链路：写入后 `restart()`） | +70 |
| ⑨ | `lib/kernel/thincoder/thincoder_mock.dart` | **清单外**：可选 `currentModel`，让脚本对端报出写入的 `defaultModel`（T126 所需） | +10 |
| ⑩ | `test/settings/settings_entry_test.dart` | **清单外**：导航多一项后先把列表滚到该档再断言次序 | +5 |

**与设计的对齐（要点）**：解析与 `config-io.mjs:32` 同判据、零 `~` 展开、零开关；写入判据序即执行序，冲突门在任何写盘动作之前；只动 `providers[]` 与顶层 `defaultModel`，条目其它键原样、`model` 键删除、空 key 保留原值；不做滚动 `.bak`；`providers` 非数组按 `[]` 并回给页面；页面五动作面齐全（无「设为默认」、无删除），密钥 `obscure` + 只显末四位，保存后只给一行提示 + 「Reopen thincoder session」，不自动重启。

**偏差与自裁决**

| # | 偏差 | 理由 |
|---|---|---|
| D1 | 页面活会话缝返回 `ThincoderModelSession`（内持 `ChatSession` 的 `KernelChoice` + `restart` + `listenable`），非设计的草拟形 `KernelChoiceSource?` | U15 本就写「实施首轮核定、不改语义」；可达访问器是 `ChatSession.models`（`KernelChoice`），内核侧 `ThincoderKernel.restart` 由 `ChatSession.restart` 转发 |
| D2 | T126 用 `test(...)` 而非 `testWidgets` | 该档内核用例统一 `test`；`settle()`（`pumpEventQueue`）在 `testWidgets` 下死锁（实测 10 分钟超时），改形后全绿 |
| D3 | 清单外改 `thincoder_mock.dart` | T126 需要脚本对端报出「写入后的 defaultModel」，否则只能断言 mock 的固定默认值 |
| D4 | 清单外改 `settings_entry_test.dart` | 多一个导航项把 `Data Directory` 挤出 800×600；断言前滚动，断言未删未弱 |
| D5 | 页面字面串取英文（「Models (thincoder)」等） | 本仓源码语言即英文、译文走 l10n（#7）；设计里的中文名是规格描述而非落盘字面 |
| D6 | `apiKey` 先 trim 再判空 | 设计要求只写「空串 = 保留原值」；只含空白的键按「留空」处理，防粘贴尾随空白写坏键 |
| D7 | `chmod` 用 `Process.runSync` | 同判据（尽力而为、失败不阻断），同步步骤无需 await |
| D8 | `model` 也纳入写前校验（trim 非空 ⇒ `invalidField`） | 设计 §27.3 第 4 步写「校验四个输入」；不校验会把 `defaultModel` 写成 `"name:"`，CLI 读作无模型（`handlers-session.mjs:51`）⇒ 模型 pill 消失。设计 §27.4 表需补该行（父级回填） |

**内部审计与评审轮次**

| 轮 | 面 | 结论 | 处置 |
|---|---|---|---|
| 审计 1 | explore：设计 §27 对照 | DEVIATIONS，无 blocker；1 条 should-fix（同名供应商须明示「将更新已有供应商」）+ keywords 缺口 | 已实现 `_nameNote` + 用例；keywords 补齐 |
| 评审 1 | advisor（code） | changes-required：1 条 must-fix（空模型 ⇒ `defaultModel` 写成 `"name:"` 且报 Saved.）+ 2 🟡 可选 + 7 🔵 | must-fix 当轮修复（校验 + store/page 两档用例） |
| 修正 1 | — | 同名提示、keywords、model 校验 | 落地并重跑 |
| 评审 2 | advisor（code） | **pass**：旧 10 条 = Fixed 1 / Unfixed 9（2 🟡 可选 + 7 🔵，全部零理由沉默）；New 0 | 余项按评审判为可选，单列于下 |

**终态：`clean`**（每轮都收敛，无 `stalled`）。

**验证读数（本机实测）**

| 检查 | 命令 | 读数 |
|---|---|---|
| 静态检查（改动面 10 档） | `flutter analyze <10 档>` | `No issues found!` |
| 静态检查（全项目） | `flutter analyze` | 8 条 issue，全在未触碰文件（改动前已在），改动面 0 新增 |
| 本批三档 | `flutter test test/kernel/thincoder_config_store_test.dart test/kernel/thincoder_kernel_test.dart test/settings/thincoder_models_page_test.dart` | 173 passed（store 14 / kernel 148 / page 11） |
| 邻接回归 | `thincoder_catalog/files/fixtures/suggestions/warm` + `settings/models_page` 六档 | 68 passed |
| T125 真跑外仓读侧 | store 用例内 `node` + `config-io.mjs:_setConfigPathForTest/resolveProviders` | exit 0，`activeProvider` 与四字段一致 |
| 既有红基线 | `settings_entry_test` / `settings_wiring_test` | 12/2 与 4/4 失败；把 `settings_dialog`+`app_settings` 还原到 HEAD 后实测同样 2/4 ⇒ 非本批引入 |

**余项（评审判可选，父级处置）**：§27.9 未登记⑨⑩两档与 T126 形制；表单无取消/关闭；无 HOME 时回退相对路径；T124 机器家目录断言在干净机器上恒真；T122 的 chmod 0500 在 root 下必红；读侧 `providersNotList` 保存前不显示；`rename` 会替换软链；§27.9 delta 估值与实交双向漂移；批次档 §2 第 4 条「展开 `~`」残句。

**未验项（单列）**：U14 真机「CLI 读得进」未验（本机未跑真 CLI 会话；T125 离线固件已挡）；本批未做真机 UI 走查（未跑 app），页面行为由 widget 用例覆盖；U13 复核结论 = 原因串**不投影**进 `configOptions`，只在 `session/new` 的 AUTH_REQUIRED 错误串里出现（key 在而 `defaultModel` 不可解析一路）⇒ 设计 §27.12 的「acp 面未见」措辞需父级回填。

**边界守线**：未写 `docs/**`；未碰外仓 `thincoder/**`；`thincoder_choices.dart` / `thincoder_kernel.dart` / `chat_session.dart` 零改动。

## §6 验证与收口（父代理）

## 验证与收口（主 agent）

**交付与复核**
| 面 | 读数 |
|---|---|
| 文件 | `thincoder_config_file.dart` 30 行 · `thincoder_config_store.dart` 495 · `thincoder_models_page.dart` 579 · store 测试 540 · page 测试 386（与报告逐档一致） |
| 测试（主 agent 复跑） | `test/kernel/thincoder_config_store_test.dart` + `thincoder_kernel_test.dart` + `test/settings/thincoder_models_page_test.dart` ⇒ **+173 全绿 · exit 0** |
| 静态检查 | 改动面 `flutter analyze` ⇒ No issues found |
| 提交 | `fc061374`（13 文件，+2642/−12） |
| 真机 | 用户 2026-10-22 00:29 在 dev 实例看到设置页与「添加 provider」（原话「我看到了添加provider」）；00:40 追问配置归属，答：写的是本机 `~/.thincoder/config.json`，新用户无该文件时按空配置渲染、页面给添加入口 |

**未走完的面（如实记）**
- **真机保存一次并核对文件**：未由用户执行（测试已覆盖 T119/T120/T121 的写盘与「其它键逐字不变」；真机走查留给下一次）。
- **U14「CLI 读得进」**：T125 离线固件已真跑外仓 `resolveProviders`；真机 CLI 会话未验。
- **设计档漂移 4 处**（`model` 校验行、§27.9 两档清单外文件、T126 用 `test` 非 `testWidgets`、delta 双向漂移）⇒ 转入台账 #139，下一次触碰该档时回填。

**评审余项 9 条**（表单无取消、无 HOME 回退、T124 机器家目录断言、chmod 0500 root 必红、读侧 `providersNotList` 保存前不显示、`rename` 替换软链等）：批档 §5 已单列，主 agent 裁定按「认账不排期」——不进本批，随 #139 的档面触碰一并处置。

**doc-check gate**：本批文档改动（设计档 §27 / 需求档 F24）两轮评审期间均 PASS；收口轮无新增文档改动。
