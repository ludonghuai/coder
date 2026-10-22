# 2026-10-21 · github-releases-and-auto-update
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-21 · 来源 = 用户 2026-10-21 23:24「用户如何更新？」· 23:29「我这里做唯一更新源吗？我拉他们的改过之后继续发版」· 23:32「我们不能发布在 github 上面吗」· 23:33「好，你上传上去，我自己根据情况修改仓库的私有和公有情况」· 23:35「自动更新也要做」· 23:36「不改我们的开发这边，只在发行版这么做」。
> 台账 = #135（distribution · 归批）。前情 = 无（独立批）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论（主 agent）

**用户诉求（逐字）**
1. 「用户如何更新？」（23:24）
2. 「我这里做唯一更新源吗？我拉他们的改过之后继续发版这样子做」（23:29）
3. 「我们不能发布在 github 上面吗？发行安装包呢」（23:32）
4. 「好，你上传上去，我自己根据情况修改仓库的私有和公有情况」（23:33）
5. 「自动更新也要做」（23:35）
6. 「但是不改我们的开发这边，只在发行版这么做」（23:36）

**落定的决策**

| # | 决策 | 依据 |
|---|---|---|
| 1 | 渠道 = **GitHub Releases**（`ludonghuai/coder`），不建 R2/域名 | 用户 3 |
| 2 | 清单与安装包**同为 release 资产**，地址用 `releases/latest/download/…`（每次覆盖同名资产） | 主 agent（同域才过策略） |
| 3 | **自有签名密钥**：私钥仓外、公钥编译进应用 | 主 agent（防伪造更新） |
| 4 | **只在发行版生效**：debug 不读清单、不发请求 | 用户 6 |
| 5 | 仓库可见性 = **用户自管**；本批不碰上游任何设置 | 用户 2 / 4 |

**已实测的事实（不是推断）**
- `ludonghuai/coder` 当前 `private=true`（API 读），releases 0 → 本批只建流程，公开由用户决定。
- `v1.6.0` release 已建、安装包已上传：`https://github.com/ludonghuai/coder/releases/download/v1.6.0/BaoCode-1.6.0-setup.exe`（22,010,965 B）。建 release 时 GitHub 队列了一条 `Release#1` CI（无密钥必失败）→ 已发 cancel（202）。
- 签名私钥 `~/.baocode-release/update-signing.key` **不存在** ⇒ 需生成一对新密钥。
- 今天 debug 已有门：`lib/update/installer_io.dart:20` `if (!kReleaseMode && override.isEmpty) return null;` ⇒ 用户 6 的要求今天已成立，本批**保持并加测**，不加新开关。
- URL 策略：`lib/update/update_manifest.dart:30-74`（允许 `baocode.dev` 及其子域 + 清单同源）；GitHub 资产重定向到 `objects.githubusercontent.com`。

**待定（实施前需用户给）**
- 仓库公开时间（公开后验收 1「匿名可下」才成立）。
- 是否同时发便携 zip（体积翻倍，非必需）。

**签名密钥（已生成，2026-10-21 23:36）**

| 项 | 值 |
|---|---|
| 私钥文件 | `C:\Users\xinbo\.baocode-release\update-signing.key`（45 B = 32 字节 base64 + 换行） |
| 公钥（可公开） | `TTLrdC73SdSwOxlF/njyvEgLTc2EUEyg3cRnkEq3HB0=` |
| 生成方式 | `dart run tool/release_manifest.dart --generate-key <path>` |
| 取公钥 | 设环境变量 `BAOCODE_UPDATE_SIGNING_KEY=<path>` 后 `--public-key` |
| 处置 | 公钥替换 `lib/update/update_signature.dart:8` 的 `updatePublicKey`（实施轮）；私钥**不进仓库、不进日志、不进聊天**，需离线备份 |

用户裁定（23:35 逐字）：「我手动设置公开，这个不用你担心；密钥做」⇒ 仓库公开由用户自办，本批不碰可见性。

## §2 批次任务与设计（eng-designer）
**状态行**：设计完成（评审修正轮已落 15 条；设计档 389 行；§16 已改为结论）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>

## 本批条目（覆盖需求档 `docs/requirements/distribution.md`）

| # | 条目 | 需求 | 状态 |
|---|---|---|---|
| 1 | 发布渠道：tag `v<ver>`、资产名 `BaoCode-<ver>-setup.exe` + `latest.json`、地址走 `releases/latest/download` | F1 | 设计完成 |
| 2 | 清单与安装包同为 release 资产；`defaultManifestUrl` 改 GitHub；清单内链接写具体 tag | F2 | 设计完成 |
| 3 | 自有 Ed25519 密钥：生成、落点、换 `updatePublicKey`、私钥丢失后果 | F3 | 设计完成 |
| 4 | 发版：构建 → `release_manifest` 签名 → 新增 `tool/publish_release.dart` 建 release + 上传两件；凭据只走环境变量 | F4 | 设计完成 |
| 5 | URL 策略扩到 `github.com` + `objects.githubusercontent.com`，精确主机、不放任意域 | F5 | 设计完成 |
| 6 | 只在发行版：`installer_io.dart:20` 原样保留 + debug 零请求用例 | F2 边界 / 验收 7 | 设计完成 |

**明确不在本批**：对象存储 / CDN、增量更新、macOS 签名公证、仓库可见性变更、上游任何设置、`docs/release.md` 全文重写（见设计档 §13）。

## 设计档落点

`docs/design/distribution.md`（新建，≈300 行）。二选一理由：`docs/design/` 下每档对应一个业务板块（chat-streaming / forge-accounts / host-tool-channel / ide-git / session-governance / thincoder-adapter），分发板块此前无档；`docs/auto-update.md` 是应用侧更新机制的模块参考文档，不是本板块的设计载体，本批只对其做行级对齐（设计档 §9 ⑨）。

## 机制摘要（逐条给机制）

1. **渠道**：仓库常量 `updateRepository = 'ludonghuai/coder'`；tag = `v<marketing>`；资产固定名；清单地址 `…/releases/latest/download/latest.json`；清单里的资产地址写 `…/releases/download/v<ver>/<file>`（不用 latest，避免清单与资产错位）；同名覆盖 = 同 tag 内删同名资产再传。私有仓资产需鉴权（匿名 404）⇒ 验收 1 的前提是仓库公开，本批不调可见性 API。
2. **清单**：`lib/update/update_manifest.dart:9` 改为 `https://github.com/$updateRepository/releases/latest/download/latest.json`；`lib/update/update_signature.dart:8` 换生成的新公钥；`tool/release_manifest.dart` 的链接前缀由同一常量拼出（去掉 R2 用的 `?sha256=`），字段来源 title 见设计档 §4.3。
3. **签名**：`dart run tool/release_manifest.dart --generate-key "%USERPROFILE%\.baocode-release\update-signing.key"`（不覆盖已有）→ 打印的公钥写进 `updatePublicKey` → 再签名（工具 `:103-110` 会拒绝公私钥不配套）。协议 `baocode-update-v1` 五行不动。**连带后果**：现 release 上的 1.6.0 资产是换密钥前构建的（编译的是上游公钥），永远接不了我们的签名 ⇒ 换钥后重建并覆盖该资产，首个可更新时间点是 1.6.1。
4. **策略**：`UpdateUrlPolicy` 保留 https + 无端口 + 无 userInfo；主机白名单 = `baocode.dev`（含子域）+ `github.com` / `objects.githubusercontent.com`（精确匹配，子域不放）。四断言：两放（github.com、objects.githubusercontent.com）、两拒（evil.example、http://github.com），另有四条拒绝项（api.github.com、带端口、带 userInfo、`github.com.evil.example`）。
5. **重定向面（实测结论）**：策略只在清单解析期跑一次（`update_service.dart:395-399` → `update_manifest.dart:221`），校验对象是 JSON 里声明的 URL；下载走 `HttpClient.getUrl`（`update_io.dart:101` / `:197`），`_newClient` 未关 `followRedirects` ⇒ 用 SDK 默认跟随；`lib/update/` 无一处读 `response.redirects`。**⇒ 重定向目标不受校验**。处置 = **接受**：内容由 size → SHA-256 → Ed25519 钉死（`update_io.dart:112-134`），恶意重定向只能让下载失败，不能置换内容；加最终 URL 校验要改想与上游保持易合并的 `update_io.dart`，收益为零。白名单仍写 objects 域，是记录落点、为将来可能的重定向校验留位，不放宽今天的判定面。
6. **只在发行版**：`installer_io.dart:19-20` 原样保留（返回 null ⇒ `main.dart:527-530` 不构造 service / backend ⇒ 无请求）。唯一新增是 `platformUpdates` 的 `environment` 可选参数（默认真实环境），否则用例只能依赖开发者 shell 里是否设了 `BAOCODE_UPDATE_URL`，不算机检。不加任何 `kReleaseMode` 之外的渠道开关，`BAOCODE_UPDATE_URL` 语义不变。
7. **发版脚本**：新增 `tool/publish_release.dart`（`GITHUB_TOKEN` 环境变量；GET tags → 复用或 POST release → 删同名资产 → `uploads.github.com` 上传（setup 先、latest.json 后）→ 回读断言 size）；可重入 = 同 tag 复用 + 同名覆盖，重复执行结果恒为 1 release / 2 资产。另改 `.github/workflows/release.yml:30-33` 为只 `workflow_dispatch`：`v*` tag 一推就排上游 CI（需 R2 / 签名 secret，本 fork 无，收尾还会 `gh release delete/create`，`:602-603`）。

## 受影响文件（现值 → delta，行数 2026-10-21 实测）

| # | 文件 | 现值 | delta |
|---|---|---|---|
| ① | `lib/update/update_manifest.dart` | 264 | +14 / −7 |
| ② | `lib/update/update_signature.dart` | 61 | 0（只换 `:8` 常量值） |
| ③ | `lib/update/installer_io.dart` | 584 | +3 / −1 |
| ④ | `tool/release_manifest.dart` | 382 | +8 / −5 |
| ⑤ | `tool/publish_release.dart` | 新增 | ≈ +230 |
| ⑥ | `.github/workflows/release.yml` | 606 | +1 / −3 |
| ⑦ | `test/update/update_manifest_test.dart` | 234 | ≈ +30 |
| ⑧ | `test/update/installer_test.dart` | 407 | ≈ +30 |
| ⑨ | `docs/auto-update.md` | 571 | ≈ +12 / −8 |
| ⑩ | `docs/design/distribution.md` | 新增 | ≈ +300 |

零改动：`update_service.dart` · `update_io.dart` · `main.dart` · `build_windows.dart` · `baocode.iss`。无代码文件越 800 行。

## 验收对照（设计档 §12）

需求档验收 1–7 逐条有落点：1 匿名可下（公开后 curl，现不能验 U1）· 2 签名有效（T8：旧公钥拒、新公钥过）· 3 清单自洽（T4 + sha256sum）· 4 策略放行（T1）· 5 真机升级（走查，基线必须是换钥后重建的 1.6.0）· 6 上游清单被拒（走查一条）· 7 开发环境零请求（T5 / T6）。

## 关键决策（设计档 §10）

D1 GitHub Releases 为唯一渠道 · D2 清单写具体 tag、只有清单地址用 latest · D3 重定向不校验（接受）· D4 白名单两主机精确匹配 · D5 换钥后覆盖重建 1.6.0、首个可更新时间点 1.6.1 · D6 发版用 Dart 脚本不用 `gh` · D7 同 tag 同名覆盖不新建 tag · D8 停用上游 CI 的 tag 触发 · D9 `environment` 注入缝 · D10 不改签名协议。

## 回滚单位

策略（`update_manifest.dart`）· 密钥（`updatePublicKey`，私钥本身不回滚）· 发版脚本（`publish_release.dart` + `release.yml` 触发）· CI 触发（恢复 `push: tags`）——四处各自独立。

## 未验证项（设计档 §15）

U1 私有仓匿名下载（需公开后验）· U2 重定向实际主机名（私有仓取不到 302；不承重）· U3 真机升级全链路（需先有 1.6.1）· U4 上传上限与端点（GitHub 文档口径 <2 GB / `uploads.github.com`，二手转述，首跑核对）· U5 PAT 最小权限面 · U6 发版脚本 dry-run 与实际一致。

## 上抛项

1. **[上抛·待裁]** `docs/auto-update.md` 的对齐由谁落笔：它是应用侧模块文档，§6.2 的公钥值要等密钥生成后才写得准。我的倾向：设计席位在密钥生成后一次落（delta 见设计档 §9 ⑨）。
2. **[上抛·待裁]** 1.6.0 资产是否覆盖重建（D5）：倾向覆盖（本批前 releases 为 0，无对外用户）；若保留旧资产，则首个我们的版本直接发 1.6.1，旧 1.6.0 标注需手动重装。
3. **[上抛·待裁]** `minimumVersion` 取值：设计缺省 `--minimum-version 1.6.0`（不强制任何人），需用户确认。

### 评审修正轮（2026-10-21 · §3 的 15 条 finding）

设计档 364 → 389 行（`DOC-CHECK GATE: PASS`）。需求档未改：F4 标题「一条命令」与三条命令的差由设计档 §2.1 偏离 4 记录，需求档措辞归主 agent。本节只落 §3 的建议，未新增设计内容。

| # | 设计档位置 | 改动 |
|---|---|---|
| 1 🔴 | §3 :66-67 · §7.2 :231-240 · :241-244 · §15 :381 | 建 draft → 传两件 → PATCH 置非 draft；可重入段落改写；新增「已知窗口」+ U7 |
| 2 🟡 | §6 :191-195 · §2.1 :43-44 · §12 :343 · §16 :388 | 两段事实分开记；引用改 `docs/batches/2026-10-21-github-releases-and-auto-update.md §1` |
| 3 🟡 | §2.1 :46 · §1 :15 · §7.1 :202 · §12 :337 | 偏离 4 记三条命令的理由；标题与形态一致 |
| 4 🟡 | §7.2 :229 · :235 | 取消 `--allow-dirty`，脏树一律拒绝 |
| 5 🟡 | §7.2 :232 · §7.3 :249 | 上传统一为 `POST https://uploads.github.com/...?name=` |
| 6 🟡 | §9 :291 | `installer_io.dart` 584→586 的 >500 档判定留痕（不拆分） |
| 7 🟡 | §2.1 :35 · :37 | 补「对应设计档章节」（无既有可对照）与「先例批次」两轴 |
| 8 🟡 | §11 :317 | T1 改为两次独立 parse，各带一条 URL |
| 9 🟡 | §16 :385-389 · §6 :195 · §12 :343 | 三条上抛改为结论；第 2 条回填 §6 与 §12 验收 5 |
| 10 🟡 | §9 :287 · §13 :357 | `docs/release.md` +1/−0 横幅行（横幅本身在实施轮落） |
| 11 🔵 | §8 :257-260 | 改为「debug 构建恒为 false」，点名 `flutter run --release` 例外 |
| 12 🔵 | §6 :184 | 新增「私钥离线备份」行 |
| 13 🔵 | §9 :292 | 需求 §5 的可选下载页链接：本批不取用，给了理由 |
| 14 🔵 | §9 :273 · :286 | 现值列 2026-10-21 23:44 实测；⑩ 改实测 389 行 |
| 15 🔵 | §6 :183 · :185 · §7.1 :209 · :215 · :219 · :222 | 路径改单反斜杠；token 改 `set /p` 读入并在用后清空 |

§16 结论（原上抛项）：① `docs/auto-update.md` 对齐由设计席位在本批实施轮落；② 覆盖重建 `v1.6.0` 资产；③ 不传 `minimumVersion`。

### 文档对齐落地（2026-10-22 · 设计档 §16 第 1 条 / §9 ⑨ ⑪）

| 档 | 改动 | 读数 |
|---|---|---|
| `docs/auto-update.md` | 顶部与 §1 状态表：更新渠道改 GitHub Releases（`ludonghuai/coder`）、清单地址 `…/releases/latest/download/latest.json`；§3.1 加 `tool/publish_release.dart`；§5.1 目录布局改 release 资产，远程服务端仍 `dl.baocode.dev`；§5.2 示例链接改 `releases/download/v<ver>/…`、去 `?sha256=`；§5.3 允许主机加 `github.com` / `objects.githubusercontent.com`（精确，子域拒）；§5.4 改为发布顺序与同名覆盖；§5.5 去掉清 CDN 缓存；§6.2 公钥换 `TTLrdC7…HB0=`；§7 指向设计档 §7 并写明 tag 触发已停用；§8 / §10 / §12 / §13 的旧地址与旧流程说明同步 | 582 行；`+47 / −37` |
| `docs/release.md` | 顶部一行横幅：`v*` tag 不再触发 CI，发版见 `docs/design/distribution.md` §7 与 `docs/auto-update.md` 第 7 节；正文全文对齐另立批（设计档 §13）。门要求的整档行宽合规：7 条既有超长行按标点折行（纯格式，未改字） | 473 行；`+28 / −7` |

读数：`doc_check(gate, docs = 这两档)` = `DOC-CHECK GATE: PASS`（0 条命中）。

## §3 设计评审（评审子代理）

### 轮次 1（评审子代理）

**设计评审 · docs/design/distribution.md §1–§16（GitHub Releases 发版 + 自动更新）**

评审对象：`docs/design/distribution.md`（全 16 节，364 行）+ `docs/requirements/distribution.md`（F1–F5 / 边界 / 验收 1–7）。
上下文缺失（已按降级判定）：无 AGENTS.md、无项目规范文档、无文档地图 ⇒ 方法论合规按通用四步（需求→设计→评审→实施）判，文档归属维度降级为「在本次范围内可见的档间一致性」。

| # | Category | Severity | Issue | Suggestion |
|---|----------|----------|-------|------------|
| 1 | Feasibility / 错误路径 | 🔴 | 发版顺序把 release 在资产上传前就置为非 draft（`docs/design/distribution.md:214` `draft=false`），而档内自述「latest」取最新一个非 draft 的 release（`docs/design/distribution.md:59` `GitHub 取最新一个**非 draft、非 prerelease** 的 release`）；`latest.json` 最后上传（`docs/design/distribution.md:224` `失败可重入的前提：`latest.json` **最后**上传`）⇒ 从建 release 到清单上传之间，应用唯一清单地址 `releases/latest/download/latest.json`（:77-78）会 404；若该次发布中途失败（§15 U5 明言首跑 token 权限未实测，403 是现实路径），通道对已装用户持续 404 直到有人重跑。§7.2 的「可重入性」只证明了「清单不会指向不存在的安装包」，没覆盖「latest 指向没有清单的 release」。同名覆盖先删旧资产（:215）对当前 latest release 有同类窗口。 | 改为 create as draft（或 prerelease）→ 上传两件资产 → PATCH draft=false/prerelease=false 收尾，把结尾的 publish 步骤写进 §7.2 的步骤表；同名覆盖路径要么在文档承认并写明短窗口，要么先以临时名上传再 PATCH 资产名、最后删旧件；相应地把首跑核对项补进 §15（U6/U7）。 |
| 2 | 文档状态一致性 | 🟡 | `docs/design/distribution.md:183` 同时写「`现在 release 上的 `v1.6.0` 安装包是在换密钥**之前**构建的`」与「`§1 已记录本批之前 releases 为 0`」，两者不能并存（有 v1.6.0 资产 ⇒ release 计数不为 0）；且「§1」在本档内指本档 §1（模块目标与范围），批记录的 §1 才是被引对象——`:39` 同样用未加限定的「§1」，`:5` 才写明批次坐标。D5 与验收 5 的前提正建立在这条事实上。 | 先核定「本批开始前该仓的 release 计数与 v1.6.0 资产的有无」，只留一份可核对的陈述；引用一律写成 `docs/batches/2026-10-21-…md §1` 并同步 §12 验收 5 与 §16 第 2 条。 |
| 3 | 需求覆盖 | 🟡 | 需求 F4 的字面是「一条命令出三件」（`docs/requirements/distribution.md:29`），本档 §7.1 落成三条彼此独立的命令（`:191` / `:197` / `:203`），而 §1 仍自称「F4（一条发版命令）」（`:15`）；§2.1 的偏离清单没有这一条，于是标题与实际形态不一致。 | 要么加一个包装入口（单脚本串三步），要么在 §2.1 偏离表补一行说明三分的理由（凭据分两个环境变量、失败可单步重跑），并把 §1 的措辞改成与形态一致。 |
| 4 | 清晰度 | 🟡 | 参数契约只列 `--version/--setup/--manifest/--notes/--dry-run`（`:212`），但「提交保护」行引用了 `--allow-dirty`（`:218` `--allow-dirty` 可跳过`）；照参数表实现就不会有这个开关。 | 把 `--allow-dirty` 补进参数行，或干脆取消该开关（脏树一律拒绝发版）。 |
| 5 | 内部一致性 | 🟡 | 上传方法两处不同：步骤 3 写 `上传：`POST https://uploads.github.com`（`:216`），选型理由写「上传是单次 PUT 一个文件体」（`:229`）。实现只能选一个。 | 统一成 POST（带 `?name=` 的上传端点），把 `:229` 的 PUT 改成同一说法，并保留「不需要 multipart」的说明。 |
| 6 | 受影响文件行数口径 | 🟡 | `installer_io.dart` 现值 584（`:258`），改后 586——本就在 >500 档；§9 只核了 800 硬帽（`:268` `无代码文件越过 800 行（最大 `installer_io.dart` 584 + 3）`），没有按 >500「主动拆分评估」给结论。 | 在 §9 追加一句：584→586 只是加一个可选参数、不改结构，故本批不拆分（或给出拆分计划），把 >500 档的判定留痕。 |
| 7 | 最近先例 | 🟡 | §2.1（`:23` `### 2.1 最近先例（对齐 ∥ 偏离及理由）`）给了实现坐标 + 对齐形 + 逐条偏离理由，但缺「对应设计档章节」与「先例批次」两轴，先例只到 `文件:行`。 | 补这两轴：本仓既有设计档中同形的章节坐标（或明确声明「无既有设计档章节可对照」），以及最近一次同类批次的坐标。 |
| 8 | 清晰度 | 🟡 | T1 期望写「两条 `assetFor('windows-x64')` 均非 null」（`:293`），但清单的 platforms 是 map，不能出现两个 `windows-x64` 键；写法像「单清单双条目」。 | 改成两次独立 `UpdateManifest.parse`（各带一条 URL）各自断言，或用两个不同平台键 + 各自断言。 |
| 9 | 范围协调 | 🟡 | §16 三条未决留在档内（`:362` `的对齐由谁落笔`、`:363` `我的倾向是覆盖`、`:364` minimumVersion 取值）。第 2 条直接决定验收 5 的前提（§12 该行以「重建后的 1.6.0」为前提），第 1 条涉及 `docs/auto-update.md` 的归属（本仓无文档地图可核）。 | 实施前把三条收口成结论（各写定值 / 归属），并把第 2 条结论回填到 §6 与 §12 验收 5 的前提句，避免两处前提分叉。 |
| 10 | 语义悬空 | 🟡 | 本批停用 `release.yml` 的 tag 触发（§7.4），但 `docs/release.md` 继续描述那条流水线，且本批明确不碰（`:333` `该文档的全文对齐另立批`）⇒ 批后该档描述的是已停用的机制。 | 本批在 `docs/release.md` 顶部加一行「tag 触发已停用，发版见 `docs/design/distribution.md` / `docs/auto-update.md`」，全文对齐另立批；或把该对齐列为 §16 的上抛项。 |
| 11 | 事实精度 | 🔵 | §8 写 `` `flutter run` / `flutter test` 恒为 false ``（`:239`）；`flutter run --release` 下 `kReleaseMode` 为 true。 | 改为「debug 构建恒为 false」，或点名「`flutter run`（默认 debug）」。 |
| 12 | 需求细节 | 🔵 | 需求 F3 写「必须离线备份」（`docs/requirements/distribution.md:26`），§6 只给路径与丢失后果（`:181` `私钥丢失的后果`），备份没有落成一步。 | 在 §6 表格或 §7.1 首次发版前加「私钥离线备份」一步。 |
| 13 | 需求依赖 | 🔵 | 需求 §5 列为可选依赖的「`lib/update/update_service.dart` 的下载页链接（可选）」（`docs/requirements/distribution.md:59` `的下载页链接（可选）`），本档把该文件列零改动（`:267`），未说明这条是可选项不做还是保持原状。 | 在 §13 或 §9 的零改动行补一句结论（沿用上游地址 / 本批不改）与判断依据。 |
| 14 | 受影响文件行数口径 | 🔵 | 受影响文件表的行数无法在本次评审范围内复核（源码不在评审对象内，§9 现值均标为 2026-10-21 实测）；可核的那一行自身漂移：⑩ 记 ≈+300（`:265`），实际本档 364 行。 | 实施前实测刷新 §9 现值列，并把 ⑩ 改成实测值。 |
| 15 | 清晰度 / 可执行性 | 🔵 | §7.1 示例的密钥路径写成 `%USERPROFILE%\.baocode-release\\update-signing.key`（双反斜杠，`:176` 与 `:196`），`set GITHUB_TOKEN=<PAT>` 会把凭据留在 shell 历史（`:202` `set GITHUB_TOKEN=<PAT>`）。 | 统一成单反斜杠的规范路径；token 用不留历史的方式读入，或提示 `set` 后清理，保证示例可原样粘贴执行。 |

已核对通过项：设计档在位（§1–§16，状态「设计稿」）；survey 证据行在位（§2.2 明确列了仓内 / 文档 / 公开来源，并对「其余无公开来源依赖」作了显式声明，GitHub 上传口径自记为第三方转述并挂 U4 首跑核对）；需求 F1–F5 与验收 1–7 在 §12 逐行有落点；§5 的重定向安全结论与需求 F5「判定仍以清单声明的 URL 为准」一致；边界（§13）与需求 §3 逐条对应，未见范围蔓延。

计数：🔴 1 · 🟡 9 · 🔵 5。

VERDICT: changes-required

### 轮次 2（评审子代理）

### 第二轮核验（distribution.md，15 条落地 + 新问题）

范围说明：按 review-object declaration 只评审 `docs/design/distribution.md` 与 `docs/requirements/distribution.md`；Instructions 第 1 条点名的 `docs\requirements\thincoder-adapter.md` 与 declaration/文档清单不符（疑为残留），未纳入。

| # | Orig# | File | Severity | Status | Notes |
|---|-------|------|----------|--------|-------|
| 1 | 1 | docs/design/distribution.md | 🔴 | Fixed | :66 `建 release 时 `draft=true`，两件资产传完再 `PATCH` 置 `draft=false` / `prerelease=false``；:231 步骤 1 `**`draft=true`**、`prerelease=false`、`target_commitish=<HEAD sha>``；:233 PATCH 收尾；:241 顺序保证；:242 已知窗口（同 tag 覆盖）落成文字；:381 新增 U7 首跑核对。失败路径下 latest 停在旧 release，原 404 断言不再成立 |
| 2 | 2 | docs/design/distribution.md | 🟡 | Fixed | :191 两条事实分开记；:193 `本批开始前该仓 releases = 0（…§1）`；:194 `本批进行中已建 `v1.6.0` release 并上传了 `BaoCode-1.6.0-setup.exe``；引用改全路径（:44/:193/:388） |
| 3 | 3 | docs/design/distribution.md | 🟡 | Fixed | :15 `F4（发版流水线：构建 → 签名 → 发布三步，分开的理由见 §2.1 偏离 4）`；:46 偏离 4 记了「字面不成立」+ 被否方案；:337 验收表同步 |
| 4 | 4 | docs/design/distribution.md | 🟡 | Fixed | :229 `**没有 `--allow-dirty`**：脏树一律拒绝发版`；:235 不提供跳过开关 |
| 5 | 5 | docs/design/distribution.md | 🟡 | Fixed | :249 `上传是单次 `POST` 一个文件体`，与 :232 的 POST 一致 |
| 6 | 6 | docs/design/distribution.md | 🟡 | Fixed | :291 `本批**不拆分**、不预留拆分计划`（>500 档判定留痕） |
| 7 | 7 | docs/design/distribution.md | 🟡 | Fixed | :35 `**对应设计档章节**：无既有设计档章节可对照`；:37 `**先例批次**：无同类（发版）批次` |
| 8 | 8 | docs/design/distribution.md | 🟡 | Fixed | :317 `两次独立的 `UpdateManifest.parse`，各带一条 `windows-x64` URL`；期望改为「各自的 assetFor 非 null」 |
| 9 | 9 | docs/design/distribution.md | 🟡 | Fixed | :385 `## 16. 已裁定事项（结论）`，三条均已给结论（:387 auto-update.md 本批由设计席位落；:388 v1.6.0 覆盖重建；:389 不传 minimumVersion） |
| 10 | 10 | docs/design/distribution.md | 🟡 | Fixed | :287 ⑪ `顶部加一行横幅：「tag 触发已停用`（+1/−0）；:357 §13 同步 |
| 11 | 11 | docs/design/distribution.md | 🔵 | Fixed | :260 `**debug 构建恒为 false**`，并补「`flutter run --release` 下为 true」 |
| 12 | 12 | docs/design/distribution.md | 🔵 | Fixed | :184 `| 私钥离线备份 |` 生成后立刻离线复制 + 「删掉本机文件仍能发版才算备份成立」 |
| 13 | 13 | docs/design/distribution.md | 🔵 | Fixed | :292 写明 `update_service.dart` 下载页链接本批**不取用**及理由 |
| 14 | 14 | docs/design/distribution.md | 🔵 | Fixed | :273 `行数 = 2026-10-21 23:44 实测`；:286 ⑩ `389 行（修正轮后实测）` |
| 15 | 15 | docs/design/distribution.md | 🔵 | Unfixed（部分） | token 历史已修（:215 `set /p GITHUB_TOKEN=GitHub PAT:` + :222 说明）；路径仍是双反斜杠：:209 `set BAOCODE_UPDATE_SIGNING_KEY=%USERPROFILE%\.baocode-release\\update-signing.key`、:183 `%USERPROFILE%\.baocode-release\\update-signing.key`。功能上无害（Windows 折叠重复分隔符），故仍为 🔵 |
| 16 | (new) | docs/design/distribution.md | 🟡 | New | :69 「这样 `releases/latest/download/latest.json` 在任何时刻都解析得到」被本轮新增的窗口段自证为假：:242 `从删掉旧 `latest.json` 到新件传完之间，`releases/latest/download/latest.json` 会短暂 404`、:231 `此刻 `releases/latest` 仍指向旧 release`（首次发版 404）。建议把 :69 改成「除同 tag 覆盖与首次发版两个短窗口外」 |
| 17 | (new) | docs/design/distribution.md | 🟡 | New | draft 流的重入查漏：:231 只用 `GET /repos/{repo}/releases/tags/v<ver>` 找已有 release，而 draft 在发布前通常不在该端点返回（**unverified**：GitHub API 语义，本仓档内无证据）；若首跑在 draft 建好后失败（U5 自认 token 权限未验），重跑会再建一个同 tag draft，:239 `同一 tag 已存在 ⇒ **复用**该 release（不新建）` 不成立。建议步骤 1 增「列 draft 并按 tag_name 命中即复用」，或把该情形写进 §7.2 可重入性 + U 表 |
| 18 | (new) | docs/design/distribution.md | 🔵 | New | :231 括注「首次发版时没有旧 release，该地址 404」与 :194 事实不符（v1.6.0 release 本批已建）；结论不变（§6 已说明无持有本 fork 公钥的已装用户），仅措辞需改 |

**计数**：🔴 1（全部修复，0 剩余）· 🟡 9（8 修复 + 1 新）· 🔵 5（4 修复 + 1 未修 + 1 新）。
**结论**：原 15 条中 14 条已落地，1 条（🔵 #15 路径规范化）部分未落地；新增 3 条均为 🟡/🔵，无新 🔴。

VERDICT: pass

## §4 用户批准（主 agent）

## 用户批准（主 agent 记录）

**用户 2026-10-21 23:52 逐字：「批准」。**

范围 = 设计评审修正轮之后的 `docs/design/distribution.md`（389 行）+ 需求档 `docs/requirements/distribution.md`（F1–F5 + 验收 1–7）。

批准前已完成：
- 评审轮 1 = changes-required（🔴 1 / 🟡 9 / 🔵 5，见 §3），**未签发 token**。
- 修正轮（eng-designer #11）落地 15 条；主 agent 逐条核验：`draft=true`（`:66`）· `PATCH`（`:233`）· 已知窗口（`:67`）· 无跳过开关（`:235`）· >500 档判定（`:291`）· 私钥离线备份（`:184`）· 「debug 构建恒为 false」（`:260`）· U7（`:381`）· 偏离 4（`:46`）· 行数 389 实测一致。
- 主 agent 的三条裁定已写入设计档 §16：auto-update.md 由设计席位落 · 覆盖重建 v1.6.0 · 不传 `minimumVersion`。

**机械前提**：token 只能由通过的评审签发 ⇒ 仍需第二轮评审（只核 §3 的 15 条落地 + 明显新问题）。第二轮通过后即派 eng-coder。

## §5 实施记录（eng-coder）
**状态行**：实施完成（8 档 + 新增发版脚本；analyze 0 error；test/update 81 通过 2 跳过）



### 改动表（8 档 + 1 新增）

| # | 文件 | 改了什么 | 行数 |
|---|---|---|---|
| ① | `lib/update/update_manifest.dart` | 新常量 `updateRepository`；`defaultManifestUrl` 改 `…/releases/latest/download/latest.json`；新常量 `githubHosts`（精确两主机）+ `allows` 主判定；错误文案由同源 `allowedHosts` 拼出 | +25 / −12 |
| ② | `lib/update/update_signature.dart` | `updatePublicKey` 换本 fork 公钥 `TTLrdC7…HB0=`；payload 五行不动 | +1 / −1 |
| ③ | `lib/update/installer_io.dart` | `platformUpdates` 加可选 `environment`（缺省 `Platform.environment`，下游一并交给 Windows installer）；`!kReleaseMode && override.isEmpty ⇒ null` 原样 | +9 / −4 |
| ④ | `tool/release_manifest.dart` | `_releasesBase` 改 `https://github.com/$updateRepository/releases/download`，去 `?sha256=`（`_link` 只收 name）；头注释同步 | +14 / −14 |
| ⑤ | `tool/publish_release.dart` | 新增：① GET tags → 404 先列 `releases?per_page=100` 找同 tag draft 复用 → 否则 POST **draft=true**；② GET assets → 删同名 → 上传（setup 先、latest.json 后）；③ PATCH `draft=false/prerelease=false`；④ GET assets 回读断言 name + size，打印 `browser_download_url`。`--dry-run` 只打印计划；脏树拒绝并列路径；凭据只 `GITHUB_TOKEN` | 362 行（新增） |
| ⑥ | `.github/workflows/release.yml` | `on:` 去掉 `push.tags`，只留 `workflow_dispatch`（inputs 保留）；头注释 3 行说明 tag 推送在本 fork 不再触发 | +4 / −2 |
| ⑦ | `test/update/update_manifest_test.dart` | T1：两条 GitHub URL 各一次独立 `parse`；T2：六条拒绝（evil.example / http / api. / 带端口 / userInfo / 子域伪装）；原 baocode.dev 用例改名「受信主机」并保留为 T3 | +38 / −1 |
| ⑧ | `test/update/installer_test.dart` | T5/T6：`environment: const {}` ⇒ null；`BAOCODE_UPDATE_URL` ⇒ 非 null、`manifestUrl` 一致、平台键 | +31 / −0 |

改动面单独分析：`dart analyze lib/update tool/publish_release.dart tool/release_manifest.dart test/update` ⇒ `No issues found!`。

### 验收读数

| 验收 | 命令 | 读数 |
|---|---|---|
| ① analyze | `flutter analyze`（全仓） | 8 issues，**全部既有**且不在改动面（`lib/icons/site_icons.dart:2`、`lib/ide/` 3 条、`test/composer_test.dart:1023`、`test/remote/remote_project_test.dart:815`、`test/ide/workbench/ide_units_test.dart:365`）；0 error、0 新 warning |
| ② 测试 | `flutter test test\update` | `+81 ~2 : All tests passed!`（2 跳过 = macOS-only）。**前置**：shell PATH 需含 `chmod`（Git 的 `usr\bin`），见「未验项 2」 |
| ③ T1/T2 | 同上 | 放行：`github.com/ludonghuai/coder/releases/download/v1.6.1/…`、`objects.githubusercontent.com/…`；拒绝：`evil.example`、`http://github.com`、`api.github.com`、`github.com:8443`、`user@github.com`、`github.com.evil.example` |
| ④ T5/T6 | 同上 | `environment: const {}` ⇒ `platformUpdates` 为 null（于是无 service / backend / 请求）；带 `BAOCODE_UPDATE_URL` ⇒ 非 null、`manifestUrl` 等于该值、`platform` = `windows-x64`（本机） |
| ⑤a 无 token | `set "GITHUB_TOKEN="` + `dart run tool\publish_release.dart --dry-run --version 9.0.0 --setup … --manifest …` | `$GITHUB_TOKEN is not set: …` exit 1；token 门在构造 `HttpClient` 之前 ⇒ 未发任何请求 |
| ⑤b 脏树 | 同上 + `GITHUB_TOKEN=dummy` | 列出 11 条 `M` + 6 条 `??`（含本批全部改动），exit 1，末尾「Commit them, or put them aside, and run this again.」 |
| ⑤c 计划 | 脚本复制到 `.thincoder/tmp/plan/tool/`（干净嵌套 git 仓）跑 `--dry-run` | 打印完整计划、exit 0、无请求；顺序 = GET tags → (404) GET releases?per_page=100 → POST draft，GET assets → DELETE 同名 → POST setup → POST latest.json，PATCH，GET assets 回读；不给 `--version` 时从 pubspec 取到 `tag v1.6.0` |
| ⑥ 步骤序 | 代码实读 + ⑤c | `releaseFor`（tags → drafts → create draft）→ 删同名/上传（`files` 顺序 = setup, latest.json）→ `publish` PATCH → 回读断言 name + size |
| ⑦ CI | PyYAML `safe_load` | `on = {'workflow_dispatch': {'inputs': {'editions': …}}}`；无 `push`/`tags`；`check` 的 workflow_dispatch 分支（`:97-101`）仍在 ⇒ 手跑可用 |
| ⑧ docs | `git status --porcelain` | 本会话改动面无 `docs/**` |
| T4 | `BAOCODE_UPDATE_SIGNING_KEY=… dart run tool/release_manifest.dart --windows <fixture> --version 9.0.0 --manifest <tmp>/latest.json` | `url = https://github.com/ludonghuai/coder/releases/download/v9.0.0/BaoCode-9.0.0-setup.exe`、无 `?sha256=`、`size=90` = 实际、`sha256=a954990c…` = `certutil -hashfile`；签名闸（私钥公钥 == `updatePublicKey`）通过 ⇒ 新常量就是该私钥的公钥 |
| T8 | 一次性脚本 `.thincoder/tmp/t8/check.dart` | `new key verifies = true`、`old key verifies = false`（旧值 `iBSgPUxN…4II=`） |

### 与设计的差异（无行为偏差）

1. **行数 delta 与 §9 估算不同**：`update_manifest.dart` +25/−12（估 +14/−7）、`installer_io.dart` +9/−4（估 +3/−1）、`release_manifest.dart` +14/−14（估 +8/−5）、`release.yml` +4/−2（估 +1/−3）、`publish_release.dart` 362 行（估 ≈230）。原因 = 按仓风格的文档注释写全（新常量的用途、`--dry-run` 计划打印、HTTP 封装），行为面按 §4–§8 无偏离。
2. **`release.yml` 头注释 +3**（设计只列 `on:`）：文件头 5–19 行仍在描述 tag 触发，只改 `on:` 会留下「推 tag 就构建」的错误说明；按 §9 ⑪ 给 `docs/release.md` 加横幅的同一形态处理。
3. **`publish_release.dart` 三处设计未指定**：`--notes` 缺省 = 空 body（不强制）；`--setup`/`--manifest` 无缺省（设计只给 `--version`）；资产名取文件自身的名字（§7.2 `?name=<name>` 字面），脚本不校验是否符合 §3 的固定名。
4. **不发 `X-GitHub-Api-Version` 头**：设计未要求，值是版本字串（不能凭记忆断言）⇒ 用 GitHub 缺省。
5. **T6 的 `platform` 断言**：Windows 精确到 `windows-x64`，macOS/Linux 用 `macos-`/`linux-` 前缀。生产代码里 macOS 的 `translated` 走 sysctl，测试侧取不到值，写死任一侧会在 Rosetta 机器上假红。

### 未验项

1. **真实 GitHub 调用（T7 / U4 / U5 / U7）**：本批不碰 GitHub。同一 tag 连跑两次仍 1 release 2 资产、上传端点与上限、token 最小权限面、draft→PATCH 的实际效果均未实测；U6（计划与实际一致）只验了计划侧。
2. **`test\update` 需要 `chmod` 在 PATH**：本会话默认 PATH 没有（`where chmod` 为空）⇒ `installer_test.dart` 的 tearDown 抛 `ProcessException`，该文件 10 条全红（含未改动的既有用例，与本次改动无关）。把 `C:\Program Files\Git\usr\bin` 加进 PATH 后 `+81 ~2` 全绿。是否在仓的测试说明里写明由主 agent 定。
3. **全仓 `flutter test`** 未跑：本批验收只列 `test/update`，且仓内另有并发改动；父代理收口时按仓口径跑。

### 设计漏项（报告给父代理，未自行处理）

- 用户可见文案 `lib/l10n/app_zh.arb:1891` / `app_en.arb:4957` 的 `updatesSettingsDescription`（「BaoCode 会在 baocode.dev 上检查新版本。」）与 `lib/main.dart:524` 的注释在改后不再成立；两张 `.arb` 与生成档都不在 §9 受影响文件表里，措辞是产品决定 ⇒ 未改，交父代理裁定。

### 实施后的内部检查（自读交付协议）

#### 偏离审计（explore，1 轮，只读）

`VERDICT: divergences — 🔴 0 · 🟡 1 · 🔵 2`。三条都不是行为面：

- 🟡 用户可见文案与改后行为相反（`lib/l10n/app_zh.arb:1891` / `lib/l10n/app_en.arb:4957`）—— 本节「设计漏项」已自报，交父代理裁定措辞与归属。
- 🔵 `lib/main.dart:524` 注释仍写 `from baocode.dev` —— 同属设计列为零改动的档，未改。
- 🔵 `.thincoder/tmp/{t4,t8,plan}` 三个验证临时件不在 §9 表 —— 本轮验证用（T4 fixture、T8 验签脚本、⑤c 干净嵌套仓），产品面零影响，`.thincoder` 已被忽略；交付报告单列。

行为面结论：设计 §3 / §4 / §7.2 / §8 / §11 的机制与用例逐条对上（审计方给的通过项均带 `file:line`），无静默简化。

#### 代码审查（advisor，1 轮，type=code，对象 = 8 档 + 设计档）

`VERDICT: pass`（🟡 2 · 🔵 6，无 must-fix）。逐项处置：

| 审查项 | 处置 |
|---|---|
| 🟡 l10n 文案 / 🟡 设计 §9 ⑨⑪ 未落 | 不改：前者等产品措辞（交父代理），后者归设计席位（§16 第 1 条） |
| 🔵 `test/update/update_manifest_test.dart:68` 注释还在为已删除的 `?sha256=` 辩护 | 已改（修正轮 1） |
| 🔵 T6 的 `platform` 只用前缀断言（`installer_test.dart:218`） | 已改（修正轮 1）：收紧到本机平台键的精确集合 |
| 🔵 `--dry-run` 被 token 门（`:64`）与脏树闸（`:89`）挡在前 | **不改**：任务书验收 ⑤ 要求「无 `GITHUB_TOKEN` 时明确报错」⇒ token 门必须在 dry-run 之前；脏树闸按设计 §7.2「非空则拒绝」不设例外 |
| 🔵 不校验上传的 `latest.json` 属于该 tag（`:140` 只比 name+size） | 不改：设计留成人工（T7 / U6 / §16 第 3 条），加硬闸属新增语义，交设计席位 |
| 🔵 复用 release 时不更新 body（notes；`:267` 只 PATCH draft/prerelease） | 不改：§7.2 步骤表无该步 |
| 🔵 `release.yml` 头注释仍把推 tag 写成发版手段 | 不改（扩写超本批批准面）；已加 3 行 fork 说明，全文对齐归设计席位／另一批 |

#### 修正轮 1（自修，2 处，均在笔内）

1. `test/update/update_manifest_test.dart:67-70`：注释改为真实理由（「链接曾带缓存键，将来也可能再带」），用例体不动。
2. `test/update/installer_test.dart:216-226`：T6 的平台断言由前缀改为精确集合（`windows-x64` / `macos-arm64|x64` / `linux-x64|arm64`），既守「本机平台键」又避开 Rosetta 假红。

复验读数：`flutter test test\update` ⇒ `+81 ~2 : All tests passed!`；`dart analyze test\update lib\update tool\publish_release.dart tool\release_manifest.dart` ⇒ `No issues found!`。

**终态：clean**（偏离审计 1 轮 · 代码审查 1 轮 · 修正 1 轮；无 must-fix 遗留；发版侧真实读数归主 agent 首跑，见「未验项」）。

行数校正（修正轮 1 之后，`git diff --numstat` 实测）：`test/update/update_manifest_test.dart` +41/−4、`test/update/installer_test.dart` +30/−0；上方改动表 ⑦⑧ 是修正前的读数。其余六档不变（`update_manifest` +25/−12、`installer_io` +9/−4、`update_signature` +1/−1、`release_manifest` +14/−14、`release.yml` +4/−2、`publish_release` 362 行）。

## §6 验证与收口（父代理）
