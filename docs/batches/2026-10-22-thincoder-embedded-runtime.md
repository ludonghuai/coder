# 2026-10-22 · thincoder-embedded-runtime
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-22 · 来源 = 用户 2026-10-22 01:06「用户内置thincoder开吧」；前情 = 批 17 于 2026-10-21 19:14 被取消（设计档 §26 已完成但未评审），同日 03:53–03:57 的诉求与 03:58 的 B1 例外批准仍有效。
> 台账 = #140（thincoder-adapter · 归批）。前情 = docs/batches/2026-10-21-thincoder-embedded-runtime.md §1（已收口 2026-10-21，用户取消）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-22
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论（主 agent）

**重开（用户 2026-10-22 01:06 逐字：「用户内置thincoder开吧」）**

前情 = 批 17（`docs/batches/2026-10-21-thincoder-embedded-runtime.md`）于 2026-10-21 19:14 被用户取消、已收口冻结；当时**设计已完成但未评审**（设计档 §26，14 小节，机检 PASS），代码零改。

**原始诉求与裁定（仍有效，取自前档 §1）**

| # | 决策 | 依据 |
|---|---|---|
| 1 | 发行版内置 thincoder 副本；用户终端那份不碰、不接管、不改 PATH | 用户 2026-10-21「baocode 我们偷偷运行自己的版本」 |
| 2 | **屏蔽 PATH**：内置副本存在时只认内置 + 用户显式路径 | 用户「他们的就自动屏蔽了」 |
| 3 | **独立数据目录**（`THINCODER_CONFIG_DIR`） | 用户「单独吧，安全」 |
| 4 | **开发环境零变化**；开发环境与终端互通（无内置副本 ⇒ 共用 `~/.thincoder`） | 用户 03:57 / 23:47 |
| 5 | 构建源 = 本仓 `thincoder/` 工作树当前 HEAD | 主 agent 默认 |
| 6 | 外仓 `THINCODER_CONFIG_DIR`（6 档 8 处，≈+30/−7）= **B1 例外已获批准 2026-10-21 03:58** | 用户「外仓可以」 |

**新增的上下文（重开后与批 17 设计相比的变化）**
- 批 18 已落地：应用读 GitHub 清单、自有公钥验签；发版走 `tool/publish_release.dart`。**安装包体积变化会自然反映到清单的 `size`**，发版流程不需改。
- 批 19 已落地：设置页写「内核实际使用的配置」——`THINCODER_CONFIG_DIR` 有值时写它，否则写 `~/.thincoder`。**本批落地后，模型页会自动写到内置副本的私有目录**（设计档 §27.2 已预留该缝）。
- 现网：`v1.6.0` 已发布（安装包 22,022,549 B），用户点「检查更新」已验通。

**设计档现状**：§26（`docs/design/thincoder-adapter.md:3555` 起，14 小节）在位；本批需**先评审**（批 17 未评审过），评审通过后再实施。

**待用户点头**：设计评审点火（firing 权在用户）。

**用户再确认（2026-10-22 01:06 逐字：「但是只做发行版」）**

即：内置运行时只存在于**打包产物**，`flutter run` / 本仓测试 / 本机调试一律走今天的行为（设置路径 → PATH），且开发环境与终端共用 `~/.thincoder`（互通）。

与既有口径一致，设计已按此写：
- 设计档 §26.6「开发环境不受影响（如何保证）」：唯一判据 = **内置目录在不在**，不引入 release 分支、不新增开发开关。
- 需求档 F23 边界（`:168`，用户 2026-10-21 03:57 原话「不要影响到我们的开发环境，只有发行版才这样做，打包的时候！」）+ 边界（`:169`，23:47「开发这边保留终端和 baocode 互通」）。
- 写法：`lib/**` 不硬编码安装目录；内置副本只由 `tool/build_windows.dart` / `tool/baocode.iss` 打进包。

**体积获批（用户 2026-10-22 01:06 逐字：「接受安装包变大」）**

安装包 21.0 MB → 约 50–60 MB（未压缩增加 ≈92.5 MB：`node.exe` 85.7 MB + thincoder 源码树 6.8 MB）。这是本批唯一的硬代价，用户已明确接受。实施后以实测体积回填 §6，并在发布说明里写明下载体积。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（评审 12 条已落地 §26（修正轮 2026-10-22））
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

**本批条目（覆盖；回指需求档 F23）**

| # | 需求判据 | 设计落点 | 本批交付 |
|---|---|---|---|
| 1 | 功能点 ① 内置副本优先且屏蔽 PATH | §26.1 / §26.3 / §26.4 | 是 |
| 2 | 功能点 ② 独立数据目录（`THINCODER_CONFIG_DIR`，**仅内置分支**） | §26.1 数据目录行 / §26.5 / §26.6 | 是（注入面） |
| 3 | 功能点 ③ 开发环境不受影响（`flutter run` 走 PATH） | §26.3 四格表 / §26.6 | 是 |
| 4 | 功能点 ④ 设置里显式路径优先 | §26.3 / §26.4（显式分支原样） | 是（保持现状） |
| 5 | 功能点 ⑤ 安装包随附 LICENSE 与版权声明 | §26.8（`LICENSE` + `THIRD-PARTY-NOTICES.txt`） | 是（不接关于页） |
| 6 | 边界 `:168` 开发环境零变化 | §26.6 | 是 |
| 7 | 边界 `:169` 开发环境与终端互通（无内置不注入） | §26.5 / §26.6 / §26.12 ⑤ | 是 |
| 8 | 验收 ① 干净机可用 | §26.8 / §26.12 ① | 是（验收需外仓批齐，§26.13） |
| 9 | 验收 ② 启动行点名内置、不出现 PATH 候选 | §26.3 机检判据 / §26.7 / T113 | 是 |
| 10 | 验收 ③ `~/.thincoder` 文件数与 mtime 不变 | §26.5 / §26.12 ③ / T116 | **前置 = 外仓批已落地**（本批只交付注入面） |
| 11 | 验收 ④ 显式坏路径明确报错、不回落 | §26.4 / T114 | 是 |
| 12 | 验收 ⑤ `flutter run` 走 PATH、行为与今天一致 | §26.6 / §26.12 ⑤ / T112 · T112a · T115b | 是 |

**不在本批（明确排除）**：外仓 `thincoder/` 的 `thincoderHome()` 与 8 处改调（独立外仓批；6 档 8 处 / ≤ +30 / −7）· macOS 真机验证（U7）· 「关于」页的许可引用面（功能点 ⑤ 只要求随附）· 单文件 SEA（D107）· 内置副本独立升级 · 活会话跨端（#36）· 本轮不改任何代码。

**受影响文件（本仓，§26.9）**：① `thincoder_locator.dart` 227 → ≤ +80 · ② `thincoder_transport.dart` 87 → ≤ +8 · ③ `thincoder_process_io.dart` 207 → ≤ +10 · ④ `tool/build_windows.dart` 425 → ≤ +90 · ⑤ `tool/baocode.iss` 342 → ≤ +3 · ⑥ `tool/build_macos.dart` 631 → ≤ +45 · ⑦ `test/kernel/thincoder_locator_test.dart` 新增 → ≤ +190 · ⑧ `test/kernel/thincoder_kernel_test.dart` 4299 → ≤ +60 · ⑨ `lib/platform/data_dir.dart` 423 → ≤ +4。
零改动：`thincoder_kernel.dart` · `thincoder_protocol.dart` · `thincoder_process.dart` · `child_process_registry.dart` · 聊天 UI · `candidates()`。

**测试覆盖（§26.11）**：T112 / T112a（无内置：Windows ∥ macOS）· T112b（半残态 ⇒ 视作无内置）· T113 / T113a（内置：Windows ∥ macOS）· T113b（内置跑不起来 ⇒ 明确失败态）· T114（显式坏路径）· T115a / T115b（注入 ∥ 不注入）· T116（真机 `~/.thincoder` 不变）· T117（版本常量两道比对）· T117a（注册表按 `thincoder` 类别登记）。

**关键决策（§26.10）**：D107 源码树形态 · D108 内置位置 = 安装目录 · D109 判据 = 「内置在不在」 · D110 坏路径不回落 · D111 env 注入 · D112 外仓 6 档 8 处（批准面 = 实测面）。

**修正轮（2026-10-22，评审 12 条全部落地）**：🔴 注入条件化（§26.5 两支 + T115a/b + §26.6 + §26.12 ⑤）· 🔴 macOS 派生规则（§26.4 `runtimeRootOf` + T112a / T113a + U7）· 🟡 批准面（§26.5 / D112）· 🟡 验收 ③ 前置（§26.12 ③ / §26.13）· 🟡 `data_dir.dart` 入库（§26.9 ⑨，U12 随之关闭）· 🟡 体量立场（§26.9）· 🟡 两条边界用例（T112b / T113b）· 🟡 进程注册表（§26.4 / T117a）· 🔵 「8 处」统一 · 🔵 版本常量 `_thincoderVersion`（§26.8 / T117）· 🔵 「关于」面写死（§26.8）· 🔵 delta 统一 `≤ +N`（§26.9）。

**上抛项**：无。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

### 设计评审（§26 内置运行时 F23 ∥ 需求档 F23）

评审面：`docs/design/thincoder-adapter.md` §26（`:3555-3787`）+ 需求档 F23（`docs/requirements/thincoder-adapter.md:162-169`）。
方法论面：设计档在场（既有设计档新增一节，未另立新档）· 最近先例行 `:3561-3566`（对齐 3 / 偏离 1，均带理由）· survey 证据行 `:3568` 均在场。

| # | 类别 | 严重度 | 问题 | 建议 |
|---|------|--------|------|------|
| 1 | Requirements | 🔴 | `THINCODER_CONFIG_DIR` 无条件注入：§26.5 注入点写在 `ThincoderLocator.launch`（`:3654`「里写 `environment['THINCODER_CONFIG_DIR'] = <私有目录>`」），T115 明写「任意 `launch()`（含内置与 PATH 两种）」（`:3753`）；需求档 F23 边界要求「没有内置副本时不注入 `THINCODER_CONFIG_DIR`」（`docs/requirements/thincoder-adapter.md:169`）与「开发环境零变化 … 一律按今天的行为」（`:168`）。照此实施 ⇒ `flutter run` 下内核改读私有目录、终端会话不可见（A3 互通面失效），并与 §27.2 的前提（`:3840`/`:3845`）冲突；§26 回指只引 `:168`（`:3557`），未覆盖 `:169`。 | 注入拆两支（内置 ⇒ 注入；PATH ⇒ 不注入，判据 = 同一「内置在不在」）；T115 拆成两条断言；§26.6 补「开发环境不注入」一条并补 `:169` 回指；§26.12 ⑤ 机制列显式写「不注入」。 |
| 2 | Feasibility | 🔴 | macOS 内置位置的派生规则缺失：§26.4 判定取自 `p.dirname(Platform.resolvedExecutable)` + `runtime/thincoder/bin/thincoder.cjs`（`:3634`，§26.6 `:3678` 复述），§26.8 却把 macOS runtime 放 `BaoCode.app/Contents/Resources/runtime/`（`:3703`）。两者仅在「可执行文件目录 == Contents/Resources」时一致；按 macOS 包结构该探测落在 `Contents/MacOS/runtime/…` ⇒ 内置永远探测不到、静默走 PATH（F23 ① 在 macOS 不成立）。U7（`:3781`）只登记 codesign / 双架构 / 执行位；单缝 `executableDirectoryOverride` 也表达不了「runtime 不在可执行文件目录下」。 | §26.4 写明按平台的派生规则（Windows：`dirname(exe)/runtime`；macOS：`dirname(exe)/../Resources/runtime`）并收进同一 override 缝；T112/T113 各补一条 macOS 形态；U7 增列该派生规则未真机验证。 |
| 3 | Requirements（批准面） | 🟡 | 外仓改动面超出需求档记录的批准规模：需求档写「约 3–5 行」（`docs/requirements/thincoder-adapter.md:167`），本档实测 6 档 8 处、≈ +30 / −7（`:3647`、`:3733`、D112 `:3744`）。实测理由充分，但批准面仍是旧数字。 | §26.5 / D112 记一句「批准面 = 实测 6 档 8 处（原估 3–5 行不足）」并同步需求档对照数字，或按 B1 口径就实测面再确认一次。 |
| 4 | Acceptance | 🟡 | 验收 ③ 本批不可达：§26.12 ③ 的机检是 T116（真机发行版，`:3763`/`:3754`），而外仓改动「本批不实施」（`:3722`）⇒ 注入的 env 尚无读取方，`~/.thincoder` 仍被写。验收表未写先后依赖。 | §26.12 ③ 补「前置 = 外仓批已落地；本批只交付注入面 + T115」，并在 §26.13 写明 F23 收口需两批齐。 |
| 5 | Clarity（受影响文件） | 🟡 | §26.9 缺数据目录访问器所在档：注入依赖「`DataDirectory.current` 已有 …访问器名实施首轮核，U12」（`:3654`、U12 `:3786`），但本仓表（`:3709-3718`）无 `lib/platform/data_dir.dart`（或 AppPaths）行，`零改动`（`:3720`）也未列 ⇒ 若首轮需新增/改访问器，改动落在登记表外（E2）。 | §26.9 补一行（现值 / delta ≤ +K），或显式列入「零改动」并给出「复用既有访问器」的证据，与 U12 处置同步。 |
| 6 | Size annotation | 🟡 | 被改的 `test/kernel/thincoder_kernel_test.dart` 现值 4299 行（`:3718`）已在 >800 硬顶之上，本批 +40，但 §26 全节无体量立场 / 缝候选 / 拆分方案引用；同一档在 §27.9（`:3998`）与 §5.2（`:339`）有此条。 | §26.9 末补一条体量立场（沿用 §5.2 四组拆法，只加用例、不动结构，触发 = 独立拆分批立项），写法对齐 §27.9。 |
| 7 | Acceptance（边界） | 🟡 | §26.4 要求两个产物同时在位（`:3634`），§26.11 只有「两者都在」（T113）与「无 runtime」（T112）两态：半残态（只 cjs ∥ 只 node.exe）与 `versionOf(arguments)` 失败（node.exe 在但跑不起来 ⇒ `status()` 报什么）无用例。 | 补两条：半残态 ⇒ 视作无内置、走 PATH 且 `candidates()` 被调用；内置在但 `--version` 失败 ⇒ 明确 status 与提示、不崩不静默回落。 |
| 8 | Clarity / Feasibility | 🟡 | 内置情形 spawn 的可执行文件变成 `node.exe`（`:3577`、`:3636`），设计未说子进程注册表 / `reapThincoderProcesses()` / `stopThincoderProcesses()`（§5.2 ⑥ `:304`、D16 `:364`）如何识别该进程；§26.9「零改动」把这类接线排除在外（相关实现档不在评审范围，`unverified`）。 | §26.4 或 §26.9 增一句：注册表仍以 `thincoder` 类别登记（键不取可执行文件名），内置下 reap/stop 仍命中；必要时补一条断言。 |
| 9 | Document consistency | 🔵 | 数字漂移：§26.12 ③ 写「外仓 10 处改调」（`:3763`），§26.5 / §26.9 / D112 均 8 处 / 6 档（`:3647`、`:3733`、`:3744`）。 | 统一为 8 处（或重数后统一）。 |
| 10 | Feasibility | 🔵 | 版本一致性校验自指：比对「产物 `--version`」与复制来源同一份 `package.json.version`（`:3696` vs `:3695`）⇒ 除拷贝损坏外恒等，兑不了对齐 ②「包里的东西不是脚本预期的就停」（`:3563`）。 | 预期版本做成常量（形同 `_nodeRelease`）再比对，或对源码树取哈希。 |
| 11 | Clarity | 🔵 | 「由「关于」面引用」（`:3698`）无落点：§26.9 本仓表无「关于」页行，`零改动`（`:3720`）未列。 | 补「关于」页一行，或改句为「本批不接关于面，许可随附即满足需求 ⑤」。 |
| 12 | Size annotation（形式） | 🔵 | §26.9 的 delta 一律 `≈ +N`（`:3711-3718`），与 §5.2 的 `≤ N 行` 上界口径不一致 ⇒ 实施后无可比对的上界。 | 统一为 `≤ +N`（或「结构不变」），与 §5.2 核查口径一致。 |

计数：🔴 2 · 🟡 5 · 🔵 5（共 12）

VERDICT: changes-required

### 轮次 2（评审子代理）

### 第二轮核对（§26 内置运行时 F23）

核对面：`docs/design/thincoder-adapter.md` §26（`:3555-3822`）+ `docs/requirements/thincoder-adapter.md` F23（`:162-169`）。全部 12 条上一轮条目均按当前文件状态逐条复核。

| 轮1# | 严重度 | 状态 | 本轮证据（行内容摘录） |
|---|---|---|---|
| 1 | 🔴 | Fixed | §26.5 注入点改为「仅内置分支」（`:3664`「**注入点（本仓，仅内置分支）**」）；PATH/显式分支「不新增键」（`:3667`「`THINCODER_CONFIG_DIR` 不写、不删、不改」）；§26.6 增「开发环境不注入」（`:3694`）；用例拆 T115a/T115b（`:3782-3783`）；回指补齐 `:169`（`:3557`）；验收 ⑤ 机制列写「不注入」（`:3796`） |
| 2 | 🔴 | Fixed | 平台规则收进纯函数 `runtimeRootOf(executableDirectory, {bool? isMac})`（`:3635`），macOS 规则 `<exe 目录>/../Resources/runtime`（`:3637`），与 §26.8 入包位置互指（`:3725`）；补 T112a/T113a（`:3776`/`:3779`）；U7 扩到 `runtimeRootOf` 的 macOS 分支（`:3817`） |
| 3 | 🟡 | Fixed | 「批准面 = 这个实测面」（`:3657`）+ D112（`:3769`）；需求档 `:167` 已同步为「6 档 8 处调用点，≈ +30/−7 行」 |
| 4 | 🟡 | Fixed | 验收 ③ 增「**前置 = 外仓批已落地**」（`:3794`）+ §26.13「收口依赖：F23 需两批齐」（`:3802`） |
| 5 | 🟡 | Fixed | §26.9 补第 ⑨ 行 `lib/platform/data_dir.dart` 423「`thincoderDataDir` 只读访问器」（`:3741`） |
| 6 | 🟡 | Fixed | §26.9 末补体量立场（`:3744`：4299 行、只加用例、缝候选沿用 §5.2、触发 = 独立拆分批） |
| 7 | 🟡 | Fixed | T112b 半残态（`:3777`）+ T113b「内置在但跑不起来」（`:3780`） |
| 8 | 🟡 | Fixed | §26.4 增「**进程注册表不变**」（`:3644`，类别登记 + 键为 pid + 逐字命令行 + `recognizes` 判据）+ T117a（`:3786`） |
| 9 | 🔵 | Fixed | 「外仓 6 档 8 处改调」（`:3794`；另 `:3656`/`:3758`/`:3769`/`:3804` 一致），旧「10 处」已无 |
| 10 | 🔵 | Fixed | 版本校验改对常量（`:3712-3715`：`_thincoderVersion` + 两道比对，并明写「只拿 ② 与源码树自比是恒等判据」）+ T117（`:3785`） |
| 11 | 🔵 | Fixed | 「**本批不接「关于」页**」（`:3720`）+ §26.13 不做清单（`:3800`） |
| 12 | 🔵 | Fixed | §26.9 delta 统一 `≤ +N` + 口径说明（`:3745`） |

**本轮新发现（均为 🔵，不阻塞）**

| # | 文件 | 严重度 | 状态 | 说明 |
|---|---|---|---|---|
| N1 | design §26.5 | 🔵 | New | `:3677`「具体文件名未逐档核实，U11」→ §26.14 中 U10 才是 token 文件名（`:3820`），U11 是 SEA 整链（`:3821`），交叉引用错位（U12 收进 §26.9 ⑨ 后重排遗留） |
| N2 | design §26.13 | 🔵 | New | `:3804` 把验收 ① 整条归「前置于外仓批」，但 §26.12 ① 的主检（干净机走查 + 启动行）本批即可验，仅「私有目录真有写」子断言需外仓批 |
| N3 | design 头部 | 🔵 | New | `:5` 的分批索引止于「批 16」，未含批 17（§26）；§6 分批对照表 `:398` 已含 F23 → §26，属索引滞后 |

**计数**：轮1 条目 12（🔴 2 / 🟡 5 / 🔵 5）＝ Fixed 12 · New 3（全 🔵）· 未解决 🔴 0。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（主 agent 记录）

**用户 2026-10-22 01:16 逐字：「批准，评审」。**

范围 = `docs/design/thincoder-adapter.md` §26（4061 行版，评审修正后）+ 需求档 F23。

批准前已完成：评审轮 1 = changes-required（🔴 2 / 🟡 5 / 🔵 5，见 §3，未签发 token）→ 修正轮（eng-designer #24）落地 12 条 → 主 agent 核验（注入「仅内置分支」+「无内置不新增键」；`runtimeRootOf` 的 Windows/macOS 规则；T112a/T113a/T115a/T115b/T117a 在册；设计档 4061 行）。

机械前提：token 只能由通过的评审签发 ⇒ 仍需第二轮（只核那 12 条落地 + 明显新问题）。

## §5 实施记录（eng-coder）
**状态行**：✅ 实施完成 2026-10-22（本仓批（locator / 注入面 / data_dir / 打包 / 用例）；外仓批见上）



**外仓批实施完成**：`D:\baocode\thincoder`（嵌套独立仓）的 `THINCODER_CONFIG_DIR` 支持，按设计档 §26.5 / §26.9 外仓表；提交 `ae3a9b96`（本批唯一提交，未推 remote）。

**改动表（6 档 8 处 = 批准面；行数 = `git diff --numstat HEAD~1 HEAD`）**

| # | 档 | 一句话 | 行数 |
|---|---|---|---|
| ① | `thincoder-core/home.mjs`（新） | `thincoderHome(env = process.env)` = `env.THINCODER_CONFIG_DIR?.trim() \|\| join(homedir(), ".thincoder")`；原样使用、不展开 `~` | 净增 16（上界 18） |
| ② | `thincoder-core/config-io.mjs` | `configDir` 改调（`:32`），`:33` `configPath` 随动；`node:os` import 换 `home.mjs` | 2+/2−（净 0） |
| ③ | `thincoder-core/log.mjs` | `logsDir()` 改调（`:58`）；头注 / 目录注释同步 | 4+/4−（净 0） |
| ④ | `thincoder-core/agent/dispatch-gates.mjs` | `ERRORS_DIR` 改调（`:21`）；头注 / 函数注释同步 | 4+/4−（净 0） |
| ⑤ | `thincoder-core/skills.mjs` | `:94` / `:136` / `:217` / `:226` 四处改调；用户层注释同步 | 6+/6−（净 0） |
| ⑥ | `thincoder-core/agent/helpers.mjs` | `:403` 用户级 AGENTS.md 改调；注释同步 | 3+/3−（净 0） |
| ⑦ | `docs/batches/2026-10-22-config-dir.test.mjs`（新） | 零留存批次测试档 T-HOME-0/1/2（随本批收口删除） | +163 |

合计 198+/19−；代码面净增 16 行（≤ 设计上界 +30）。删除数比设计表 −7 多 12 行 = 5 个已无用的 `node:os` import + 7 行 1:1 注释替换（把 `~/.thincoder` 注释改成 `thincoderHome()` 口径），净增 0 —— 披露，不属扩面。

**两条读数（子进程 + 假 HOME = `<tmp>/home`；8 处 = configDir · configPath（随动）· logsDir · tool-errors · skills 四处 · 用户 AGENTS.md）**

- 不设变量：`<home>\.thincoder` · `<home>\.thincoder\config.json` · `<home>\.thincoder\logs` · `<home>\.thincoder\tool-errors\2026-10-22\…-probe.log`（真写一次再找落地档）· skills 四处从 `<home>\.thincoder\skills\probe.md` 命中（异步 / 同步两面对称）· `<home>\.thincoder\AGENTS.md` —— 与改动前 `join(homedir(), ".thincoder", …)` 逐字同值（T-HOME-1 断言）。
- 设了变量（`<tmp>/private`）：8 处全落 `<tmp>\private\…`；`<home>\.thincoder` 下 tool-errors 零落盘、诱饵 skill（`decoy-only`）与诱饵 AGENTS.md 零读（T-HOME-2 断言）。

**验证（命令 + 结果）**

- `node --test docs/batches/2026-10-22-config-dir.test.mjs` ⇒ 3/3 pass。
- 红-绿对（评审修复轮的仪器证明）：临时把 `skills.mjs:94` 改回 `join(homedir(), ".thincoder", "skills")` ⇒ T-HOME-2 红（`actual: ['decoy-only']` / `expected: ['probe']`，失败文案 = 诱饵 skill）；`git checkout` 还原 ⇒ 绿。
- 既有 4 个批次测试档（`2026-10-19-acp-image-prompt` / `2026-10-20-cleanup-defects` / `2026-10-20-rewind` / `2026-10-20-session-governance-a1`，一条 `node --test` 并列）⇒ 26/26 pass。
- `thincoder-core` 的 `npm test` ⇒ 空清单绿（`test/run.mjs` 明示零用例即绿，非本批证据面）。
- 未跑：desktop / vscode / server 测试集——改动只碰 core 六档，其余端零改；core 的测试目录零用例留存。

**评审轮次与终态**

- 内部 explore 审计 1 轮：唯一 FAIL = 验收 ⑥ 未提交（审计时点事实，已在轮内提交）；其余逐条 PASS；另点名清单外提示串 / 文档面滞后（不修，见下）。
- 独立代码评审 2 轮：轮 1 changes-required（🟡 must-fix 1 = 诱饵 skill 与真件同名 ⇒ `skills.mjs:94/:217` 列表面断言恒真；🟡 optional 2 = 文档面滞后；🔵 2 = 取值时点未写明、T-HOME-2 缺假 HOME 卫）→ 修复（诱饵改独名 `decoy-only`、`home.mjs` 时点注释、T-HOME-2 补卫）→ 轮 2 pass（3 条修复核对 Fixed、无新问题；2 条文档面按 R7a/R7e 关闭为协调项）。
- 终态：clean。

**清单外发现（点名不修，主 agent 定）**

1. 纯文案面（不是路径计算）：`thincoder-core/provider/core.mjs:44-46` / `:127` · `memory/memory-tool.mjs:140` / `:189` · `agent-tools/consult.mjs:422` · `thincoder-cli/src/acp/handlers-session.mjs:180` · `thincoder-cli/bin/thincoder.mjs:156` · `bench/lib/*` / `bench/probe.mjs` —— 错误提示写死 `~/.thincoder/config.json`，设了变量后指向旧路径。
2. 文档面：`thincoder/docs/core/design/CONFIG.md:23`、`LOGGING.md:88` 仍写单一 `~/.thincoder` 根；`API-CONTRACT.md` 生成区缺 `thincoder-core/home.mjs` 行（外仓跑一次 `node scripts/api-contract.mjs --write` 可收口）；`thincoder-cli/src/crash-reports.mjs:33` 注释同旧（路径本身随 `configDir`）。
3. 无第 9 处路径绕过：`homedir()` / `expandHome(` / `process.env.HOME` 全仓扫，除 `expand-home.mjs`、`ssh-transport.mjs:91`（用户入参 `~` 展开）外零命中；会话 / ledger / traces / memory / peers / browser profile / crash-reports 均派生自 `configDir`（实测 import 点）。

**未验项（单列）**

- macOS：本批无平台分支，未触及。
- 外仓全量测试面：只有 4 个现存批次档 + 空清单 `npm test`，没有常驻测试集可跑（零留存纪律）。
- 「内置副本注入后真机不写用户 `~/.thincoder`」（T116）：属主仓批 + 真机走查，不在外仓批。

**实施完成（本仓批）** — 范围 = 设计档 §26 的本仓部分（locator 顺序 / 内置探测 / `runtimeRootOf` / 仅内置分支注入 / 打包脚本 / `data_dir` 访问器 / 用例）。`thincoder/**` 未触碰（外仓另一支，见上）。

**改动表**（行数 = 实测；`+a/−d` 取自 `git diff --numstat`）

| # | 档 | 一句话 | 行数 |
|---|---|---|---|
| ① | `lib/kernel/thincoder/thincoder_locator.dart` | `ThincoderBuild`（display / executable / arguments）+ `runtimeRootOf`（Windows `<exe目录>/runtime`、macOS `<exe目录>/../Resources/runtime`，`isMac` 可注入）+ `builtinBuild`（cjs 与 node 两件都在才算）+ 解析顺序（显式坏即抛 → 内置 → PATH，有内置不构造 candidates）+ 仅内置分支注入 `THINCODER_CONFIG_DIR` + `environment()` + 启动行 + `versionOf(arguments)` + 内置跑不起来的失败态 | 227 → 379（+152） |
| ② | `lib/kernel/thincoder/thincoder_transport.dart` | `ThincoderLaunch.arguments`（默认 `['acp']`），`withEnvironment` 携带 | 87 → 94（+7） |
| ③ | `lib/kernel/thincoder/thincoder_process_io.dart` | `Process.start` 透传 `launch.arguments` | 207（+1/−1） |
| ④ | `lib/platform/data_dir.dart` | `thincoderDataDir`（`<path>/runtime-data/thincoder`）+ `items` 加 `runtime-data` | 423 → 428（+6） |
| ⑤ | `tool/build_windows.dart` | `_nodeVersion` / `_nodeSha256` / `_thincoderVersion` + `_nodeExe`（下载 → 哈希校验 → 解压）+ `_putRuntime`（node.exe、源码树、core → `node_modules\@thincoder\core`、notices）+ 源码版本与产物 `--version` 双检常量 + 必检项 | 425 → 608（+183） |
| ⑥ | `tool/baocode.iss` | `[Files]` 注释补 `runtime\`（递归 Source 已覆盖，未新增文件行） | 342 → 344（+5/−2） |
| ⑦ | `tool/build_macos.dart` | 同改点落 `Contents/Resources/runtime/`；node 取 darwin 两架构 lipo 成一个通用二进制；`_executables` 纳入 node；`signApp` 签 node（ad hoc 即 `--sign -`） | 631 → 838（+191/−2） |
| ⑧ | `test/kernel/thincoder_locator_test.dart` | 新增 10 用例：T112 / T112a / T112b / T113 / T113a / T113b / T114 / T115a / T115b / T117a | 新增 426 |
| ⑨ | `test/kernel/thincoder_kernel_test.dart` | 末尾加一组：启动行读真实 events.log + 宿主侧 T115a/T115b + 设置页同源断言 | 4688 → 4813（+126；设计档现值 4299 是批 19 前读数，实际基线 4688） |
| ⑩ | `lib/kernel/thincoder/thincoder_config_file.dart`（**清单外**） | `thincoderEnvironment` 默认值 `ClaudeEnvironment.of` → `ThincoderLocator.environment` | 30 → 33（+9/−6） |

**验收读数**

- ① `flutter analyze`（全工程）⇒ 8 条 info/warning，全部在未改文件；改动面 0 error / 0 新增 warning。
- ② `flutter test test\kernel\thincoder_locator_test.dart test\kernel\thincoder_kernel_test.dart` ⇒ 160 通过（10 + 150）；连 `test\settings\thincoder_models_page_test.dart` 一起 171 通过。T112 / T112a / T112b / T113 / T113a / T113b / T114 / T115a / T115b / T117a 逐条在册；T112a 的 macOS 候选表半条在 Windows 宿主上跳过（U7）。
- ③ T115b：无内置（PATH 组 + 有效 `thincoder.path` 组）`launch().environment` 不含 `THINCODER_CONFIG_DIR`，整表 == `ClaudeEnvironment.of()`；另断言 `ThincoderLocator.environment()` 与之同值（设置页写的文件 = CLI 读的文件）。
- ④ `runtimeRootOf` 纯函数、`isMac` 可注入；Windows / macOS 两形态都有用例（macOS 形态在 Windows 上只验规则，真机包结构归 U7）。
- ⑤ events.log：内置 ⇒ `launch: builtin <cjs 绝对路径>`；PATH ⇒ `launch: path <exe>`（内核测试读真实 events.log，各 1 行）。
- ⑥ `dart run tool\build_windows.dart --skip-build --remote-built --stock-engine` ⇒ `Release\runtime\` 就位：`node\node.exe` 89,894,400 B、`thincoder\{bin,src,package.json,LICENSE,node_modules\@thincoder\core}\` 共 472 文件、`THIRD-PARTY-NOTICES.txt`；产物 `node.exe …\thincoder.cjs --version` = 0.12.76 = `_thincoderVersion` = 源码树 `package.json` version；ISCC 日志逐条压缩 runtime 四件（node.exe / thincoder.cjs / LICENSE / notices）；安装包 44,931,377 B（发布版 22,022,549 B，+22.9 MB，回填 U8）。
  - 本机 `--skip-build` 先触发既有引擎哈希门（bundle 的 flutter_windows.dll = `7b03…`，既非 `_stockEngineSha256` 也非 `_patchedEngineSha256`）⇒ 需加 `--stock-engine` 才走通；与本批无关，属既有环境状态。
  - 负向：`_thincoderVersion` 改 0.12.99 再跑 ⇒ 脚本 `_fail` 并打印两侧值（0.12.76 / 0.12.99），已改回 0.12.76。
- ⑦ 未触碰 `thincoder/**`；PATH / 显式分支 environment 逐字不变；ACP 协议零改动。

**偏离与清单外改动**

1. **清单外 ⑩** `lib/kernel/thincoder/thincoder_config_file.dart`：注入的私有目录在本仓唯一的配置写面没有消费方（设置 → 模型页会写 `~/.thincoder/config.json`，与内置 CLI 读的私有目录分叉），§27.2 明写这一步归 F23；不改则本批目标「装完即用」断在配 provider 这一步。改法 = 默认值指向 `ThincoderLocator.environment`（与 `launch()` 共用 `_withDataFolder`），页面与子进程同源。
2. 启动行落点与形：任务书钉 `launch: builtin <cjs>` / `launch: path <exe>`，实现在 `ThincoderLocator.launch`（设计 §26.7 / §26.9③ 原写 `launch <display> → <exe> <args>` 在 process_io；process_io 无分支信息）；验收 ⑤ 已覆盖。
3. `locate()` 仍返回 `String`（要运行的程序：内置时 = node），`ThincoderBuild` 由新 `locateBuild()` 给出；设计 §26.4「locate() 返回 ThincoderBuild」按此拆。
4. macOS 打包把两架构 node lipo 成一个通用 `runtime/node/node`（设计允许「双架构都带」），随既有 `ditto --arch` 瘦身，保住 locator 的单路径契约；签名沿用 `signing.sign`（ad hoc 即 `--sign -`），比设计字面更严格。
5. `data_dir.dart` 净增 5 行（§26.9 ⑨ 上界 +4，其中 3 行是文档）。
6. 各档行数超 §26.9 上界（locator +152 vs ≤+80、build_windows +183 vs ≤+90、build_macos +191/−2 vs ≤+45、locator 测试 +426 vs ≤+190、kernel 测试 +126 vs ≤+60、data_dir +5 vs ≤+4）；多出部分为文档注释、测试夹具与设计本身要求的 node 下载 / lipo / 签名机件，无结构改动、无语义越面。

**轮次与终态**

- 内部 explore 分歧审计：1 轮（0 must-fix / 2 should-fix / 5 note）；已落地两条陈旧注释修复（`config-io.mjs` 坐标、macOS 注释措辞）。
- 内部 advisor 代码评审：轮 1 changes-required（1 🔴：注入无消费方）→ 修复（清单外 ⑩）→ 轮 2 pass，判定无新问题。
- 终态：clean。
- 本机不可验项单列：macOS `_putRuntime` / lipo / 签名 / `runtimeRootOf` 真机包结构（U7）、真机 `~/.thincoder` 不变（T116，前置 = 外仓批）。

## §6 验证与收口（父代理）

## 验证与收口（主 agent）

**两支交付**
| 支 | 提交 | 读数 |
|---|---|---|
| 外仓 `thincoder/` | `ae3a9b96`（本机，未推上游） | `home.mjs` 16 行 + 8 处跟随；批次测试 **3/3**、既有批次档 **26/26**；不设变量 8 条路径逐字同今天、设了全落变量目录（T-HOME-1/2 + 红-绿对） |
| 本仓 | `c572c6a9`（已推 `mine/main`） | 11 档；`flutter test` locator+kernel **160 通过**、并入模型页共 **171**；`dart analyze` 改动面 **No issues found** |

**打包实测（2026-10-22 01:53）**
| 项 | 读数 |
|---|---|
| 安装包 | **42.9 MiB（44,931,377 B）** —— 设计估 50–60 MB，**实测更低**（发布版 22,022,549 B，增 22.9 MB） |
| `Release\runtime\node\node.exe` | 85.73 MB ✅ |
| `runtime\thincoder\` | `bin\thincoder.cjs` / `LICENSE` / `src` / `package.json` ✅ · `node_modules\@thincoder\core` **347 文件** ✅ |
| `runtime\THIRD-PARTY-NOTICES.txt` | 在位 ✅ |
| 冒烟 | `runtime\node\node.exe runtime\thincoder\bin\thincoder.cjs --version` ⇒ **`0.12.76`**，与常量一致 ✅ |
| 版本双检负向 | `_thincoderVersion` 改 `0.12.99` ⇒ 脚本 `_fail` 并打印两侧值（eng-coder 实跑，已改回） |

**未验项（如实记）**
- **macOS 全链**：lipo / codesign / `Contents/Resources/runtime` 包结构本机无 Mac（U7）。
- **T116 真机**：「发行版不写用户 `~/.thincoder`」需外仓批 + 真机安装走查；本批只交付注入面（§26.12 ③ 前置已写明）。
- **安装后整机走查**：未在本机静默安装（会覆盖既有安装的卸载项）；以 runtime 落位 + `--version` + `acp` 冒烟 + ISCC 日志替代。

**上抛待裁（eng-coder 发现的设计空隙，主 agent 记录）**
发行版 + 用户在设置里填了**有效** `thincoder.path` 时，当前实现仍注入私有 `THINCODER_CONFIG_DIR`、启动行仍写 `builtin`（判据 = 「内置副本存在」，与需求 `:169` 的字面口径一致；§26.3 四格表缺这一格）。若裁定「显式路径应完全按用户那份走（读 `~/.thincoder`）」，需改 `thincoder_locator.dart:139` 与 `:133` 两处判据并补用例 ⇒ 台账 **#141**。

**doc-check gate**：本批文档改动（设计档 §26 / 需求档 F23 / 本档）在评审与收口轮机检均 PASS；收口轮无新增文档改动。
