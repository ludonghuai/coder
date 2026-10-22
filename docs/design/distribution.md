# 分发与自动更新（GitHub Releases）设计档

> 板块：分发渠道与自动更新（`tool/`、`lib/update/**`、GitHub Releases）· 范围仓：baocode（fork `ludonghuai/coder`）；上游仓只读。
> 配对需求档：`docs/requirements/distribution.md`（F1–F5 / 边界 / 验收 1–7）。
> 批次：`docs/batches/2026-10-21-github-releases-and-auto-update.md` §2。
> 状态：设计稿（评审修正后）· 2026-10-21 · 行号 = 编制日快照，实施时按符号定位。
> 一句话：清单与安装包都作为本 fork 的 Release 资产发布，地址固定在 `releases/latest/download/…`；应用只认本 fork 的 Ed25519 公钥；debug 构建的行为一行不改。

---

## 1. 模块目标与范围

**一句话**：拿到本 fork 构建的用户能自己升级，且升级只指向本 fork 的版本；渠道只用 GitHub Releases，不新建 CDN 或存储桶。

**本批交付面**：F1（发布渠道）· F2（清单与安装包同为资产）· F3（自有签名密钥）· F4（发版流水线：构建 → 签名 → 发布三步，分开的理由见 §2.1 偏离 4）· F5（URL 策略扩到 GitHub）；外加"只在发行版生效"的保持与用例。

**本批不做**：对象存储 / CDN / 增量更新 / macOS 签名公证 / 仓库可见性变更 / 上游任何设置（需求档 §3）。

---

## 2. 做法与理由

### 2.1 最近先例（对齐 ∥ 偏离及理由）

**对齐**（照现有形态，不另造）：

| 面 | 先例 | 照抄的形 |
|---|---|---|
| 清单地址与 URL 白名单 | `lib/update/update_manifest.dart:30-58`（`UpdateUrlPolicy`：host 白名单 + 强制 https + 无端口 + 无 userInfo） | 同一个类加两个主机名，不新写校验器 |
| 发布工具 | `tool/release_manifest.dart`：`--generate-key` / `--public-key`（`:291-306`）、签名与写清单（`:167-190`、`:240-255`）、密钥路径走环境变量（`:73`） | 只用既有能力，不新写签名逻辑 |
| 构建产物 | `tool/build_windows.dart:1-34` 用法注释；产物 `build/installers/BaoCode-<ver>-setup.exe` | 发版脚本吃这个路径，不改构建 |
| 安装与验签 | `lib/update/update_io.dart:112-134`（大小 → SHA-256 → Ed25519，顺序固定） | 零改动 |
| debug 门 | `lib/update/installer_io.dart:19-20`（`!kReleaseMode && override.isEmpty ⇒ null`） | 原样保留，只加测试 |

**对应设计档章节**：无既有设计档章节可对照——`docs/design/` 下六档（chat-streaming / forge-accounts / host-tool-channel / ide-git / session-governance / thincoder-adapter）都是应用内功能面，没有发版 / 渠道 / 签名密钥的章节，本档是该板块的第一份。

**先例批次**：无同类（发版）批次；最近一次动 `tool/` 打包面的批次 = `docs/batches/2026-10-21-thincoder-embedded-runtime.md`（§2 受影响文件含 `tool/build_windows.dart` / `tool/baocode.iss`）。形态不同（打包 ≠ 发版），只借它「新增 Dart 工具、构建脚本零改」这一形。

**偏离**（逐条给理由）：

1. **清单里的下载链接前缀换掉**。`tool/release_manifest.dart:53` 的 `_releasesBase = 'https://dl.baocode.dev/releases'` 与 `:56-58` 的 `?sha256=` 查询串是给 R2 CDN 的缓存键用的。GitHub 资产地址是 `releases/download/v<ver>/<file>`，不需要缓存键（内容由 `size` / `sha256` / 签名钉死，换文件必然验签失败）。⇒ 链接由 `updateRepository` 常量拼出。
2. **新增 `tool/publish_release.dart`（建 release + 传两件资产）**。上游把这段放在 CI 里：`.github/workflows/release.yml:602-603` 用 `gh release create` 重建 release，靠 `:406-407` 的 R2 凭据与 `:516` 的签名密钥 secret。本 fork 没有这些 secret，且用户要在本机发版 ⇒ 落成一条本地命令（`GITHUB_TOKEN` 走环境变量）。
3. **停用 `release.yml` 的 tag 触发**（`:30-33` 的 `push: tags: ['v*']`）。发版脚本建 tag 的瞬间就会排一条上游 CI，它需要 R2 / 签名 secret（本 fork 无）⇒ 必然失败，而且收尾会 `gh release delete` + `gh release create`（`:602-603`）动我们刚建的 release。
建 `v1.6.0` 时 GitHub 就排过一条 `Release#1`、已 cancel（`docs/batches/2026-10-21-github-releases-and-auto-update.md §1`）。

4. **F4 落成三条命令，不做单个包装入口**。① 凭据天然分开：签名只要私钥（`BAOCODE_UPDATE_SIGNING_KEY`，本机文件），发布只要 `GITHUB_TOKEN`（网络凭据）；合成一条等于让签名那步也持有 PAT。② 单步可重跑：发版失败最常见在发布那步，重跑时不该再签一次名。代价 = 需求 F4 标题「一条命令」的字面不成立，按条目照实记（§12 F4 行）。被否：包装脚本串三步（多一层参数转发，且上一条的凭据隔离消失）。

### 2.2 survey 证据

- **仓内**：`lib/update/**`（manifest / signature / service / io / installer_io 全文实读）、`lib/main.dart:526-551`、`tool/release_manifest.dart`（全文）、`tool/build_windows.dart:1-60`。
- **仓内（续）**：`test/update/**`（目录与用例形态）、`.github/workflows/*.yml` 的 `on:` 段与 `release.yml` 的 secrets / release 步骤行。
- **仓内（文档）**：`docs/auto-update.md`、`docs/requirements/distribution.md`（均全文）、`PROJECT-MANIFEST.json`（文档检查口径）。
- **公开来源**：查了 GitHub Release 资产上传口径——每文件 < 2 GB、上传端点 `uploads.github.com`（第三方转述 GitHub 文档，未取一手页面 ⇒ 记为口径，首跑核对，§15 U4）。其余无公开来源依赖：本设计不含版本号 / 协议精度断言，`HttpClient` 重定向行为以本机 SDK 的默认值与本仓代码实读为准（§5）。

---

## 3. 渠道约定（F1）

| 项 | 约定 |
|---|---|
| 仓库 | `ludonghuai/coder`（常量 `updateRepository`，见 §4.1） |
| tag | `v<marketing 版本>`，例 `v1.6.1`（`AppVersion.marketing`，不带 `+build`） |
| 资产名 | `BaoCode-<marketing>-setup.exe` · `latest.json`（固定名，名里不带 tag） |
| 最新清单地址 | `https://github.com/ludonghuai/coder/releases/latest/download/latest.json` |
| 资产地址（写进清单） | `https://github.com/ludonghuai/coder/releases/download/v<ver>/<asset>`（**不写 `latest`**：清单里必须指到具体 tag，避免清单与资产错位） |
| "latest" 的含义 | GitHub 取最新一个**非 draft、非 prerelease** 的 release ⇒ 建 release 时 `draft=true`，两件资产传完再 `PATCH` 置 `draft=false` / `prerelease=false`（§7.2 步骤 1 / 3） |
| 同名覆盖 | 同一 tag 内 **删掉同名资产再上传**（`DELETE /releases/assets/{id}` + 上传）；不新建 tag、不新建 release；覆盖顺序与短窗口见 §7.2「已知窗口」 |
| 可见性 | 私有仓的 release 资产要鉴权（匿名请求 404）⇒ 验收 1「匿名可下」的前提是仓库**公开**；可见性由用户自管，本批不调用任何可见性 API |
| 每次发版 | 每个 release 都带自己的 `latest.json`（内容指向本 tag 的资产），这样 `releases/latest/download/latest.json` 在任何时刻都解析得到 |

**为什么清单必须放 release 资产而不是 raw 文件**：raw 链接带分支名，可被强推改写；release 资产的地址含不可变的 tag，且和安装包同域（`github.com`），满足 URL 同源判定。

---

## 4. 接口契约

### 4.1 常量（`lib/update/update_manifest.dart`）

```dart
/// 本 fork 的仓库：应用从它的 release 升级。
const updateRepository = 'ludonghuai/coder';

/// 应用读的清单：最新 release 里的 latest.json。
const defaultManifestUrl =
    'https://github.com/$updateRepository/releases/latest/download/latest.json';
```

- 仓库 slug 只此一处；`tool/release_manifest.dart` 已 `import` 本文件（`:47`），资产地址从同一常量拼出，不复制第二份。
- `manifestUrlVariable`（`BAOCODE_UPDATE_URL`，`:13`）语义零改：仍是"试用某个清单"的入口，仍让 debug 构建也能更新。

### 4.2 URL 策略（`UpdateUrlPolicy`，`lib/update/update_manifest.dart:30-58`）

改后形状（语义：https + 无端口 + 无 userInfo + 主机在白名单；`baocode.dev` 含子域，GitHub 两个域**精确匹配**）：

```dart
class UpdateUrlPolicy {
  const UpdateUrlPolicy({this.extraOrigins = const {}});

  /// 清单不是默认地址时，清单自己的 origin 也放行（本地试发版）。
  factory UpdateUrlPolicy.forManifest(Uri manifest) => /* 现形不改 */;

  static const domain = 'baocode.dev';

  /// release 资产用到的 GitHub 主机：清单与资产声明在 github.com，
  /// 重定向落在 objects.githubusercontent.com（重定向不校验，见 §5）。
  static const githubHosts = {'github.com', 'objects.githubusercontent.com'};

  final Set<String> extraOrigins;

  bool allows(Uri url) {
    if (url.hasScheme &&
        (url.scheme == 'http' || url.scheme == 'https') &&
        url.host.isNotEmpty &&
        extraOrigins.contains(url.origin)) {
      return true; // 现形保留：清单同源例外（含本地 http 测试）
    }
    if (url.scheme != 'https' || url.hasPort || url.userInfo.isNotEmpty) {
      return false;
    }
    final host = url.host.toLowerCase();
    return host == domain ||
        host.endsWith('.$domain') ||
        githubHosts.contains(host);
  }
}
```

- **不放松成"任意 https"**：`github.com` 的子域（`api.github.com`、`codeload.github.com`）不放行；`objects.githubusercontent.com` 的子域也不放行。
- 错误文案（现 `update_manifest.dart:222-224` 写着 "not an https link on baocode.dev"）改为点名全部允许的主机，取自同一常量，避免提示与实际判定不一致。
- `extraOrigins` 分支保留在第一位，`BAOCODE_UPDATE_URL` 的本地试发版路径（`http://127.0.0.1:8080`）零影响。

### 4.3 清单里每个字段从哪来（F2）

| 字段 | 来源 | 落点 |
|---|---|---|
| `version` | `pubspec.yaml` 或 `--version` | `tool/release_manifest.dart:113-115` |
| `url` | `https://github.com/$updateRepository/releases/download/v<ver>/<文件名>` | 本次改写 `:56-58` |
| `size` | 实际文件字节数 | `:171` |
| `sha256` | 实际文件 SHA-256（小写） | `:172` |
| `signature` | Ed25519 over `baocode-update-v1\n<version>\n<platform>\n<size>\n<sha256>\n` | `:173-179` |
| `notes` / `minimumVersion` | `--notes-en` / `--notes-zh` / `--minimum-version` | `:158-165` |

### 4.4 数据流（不变）

```
启动 → main._startUpdates()（lib/main.dart:526-551）
  → platformUpdates()（installer_io.dart:17）      debug 且无 override ⇒ null（:20）
  → UpdateService.start() → check()
      → backend.fetchManifest(manifestUrl)          github.com，TLS，≤1 MB
      → UpdateManifest.parse(policy: UpdateUrlPolicy.forManifest(manifestUrl))   ← 唯一一次策略判定（update_service.dart:395-399）
      → 版本比较 → 本平台 asset
      → backend.download()                          HttpClient.getUrl → 302 → objects.githubusercontent.com
      → 大小 → SHA-256 → Ed25519 验签 → 改名
      → installer.prepare() → 退出时 launch()
```

---

## 5. 重定向面：校验发生在哪一步（实测结论）

**事实（实读）**

1. 策略只在**清单解析期**跑一次：`update_service.dart:395-399` 把 `UpdateUrlPolicy.forManifest(manifestUrl)` 传进 `UpdateManifest.parse`，唯一的判定点是 `update_manifest.dart:221` 的 `if (!policy.allows(url))`，它看到的只是 JSON 里那段 URL 字符串。
2. 下载走 `HttpClient`：`update_io.dart:101` → `_fetch` → `:197` `client.getUrl(url)`；`_newClient()`（`:44-46`）只设 `connectionTimeout` 与 `userAgent`，**没有** `followRedirects = false` ⇒ 用 SDK 默认值（跟随，最多 5 跳）。
3. 全仓 `lib/update/` 没有任何一处读 `HttpClientResponse.redirects`，也没有在任何一步对最终 URL 再跑 `policy.allows`（`grep 'redirects' lib/update/` 为空）。

**结论**：策略校验的是**清单声明的 URL**；**重定向目标不受校验**。GitHub 的 `github.com/.../releases/download/...` 会 302 到 `objects.githubusercontent.com`（本机私有仓匿名取不到 302，主机名见 §15 U2），这条 302 沿默认跟随走过去，链路上不做主机检查。

**处置：接受（不加最终 URL 校验）。理由三条：**

1. **内容本来就与域名无关地钉死了**。下载完按顺序校验大小 → SHA-256 → Ed25519（`update_io.dart:112-134`），签名覆盖 `version / platform / size / sha256`（`update_signature.dart:20-27`）。重定向到任何域都只能拿到**不同的字节**，而不同字节过不了 SHA-256 与签名 ⇒ 恶意重定向的能力上限是"让这次下载失败"，不是"装进别人的程序"。
2. **加最终 URL 校验只增成本**：要在 `_fetch` 里读 `response.redirects` 并逐个跑策略，是 `lib/update/update_io.dart` 的实质改动，而这个文件是本 fork 想与上游保持易合并的部分；换来的安全性为零（第 1 条）。
3. **白名单仍写两个域**：`objects.githubusercontent.com` 进白名单不是今天链路的必需（声明 URL 只有 `github.com`），它记录的是"重定向会落在哪"，这样将来若真要做最终 URL 校验，策略表不用再改一次；它不会放宽任何今天的判定面（精确主机名，无子域）。

**这条事实写进用户可见的文档**（`docs/auto-update.md` 5.3 节已有的"重定向到其他域名由 SHA-256 与签名保证"一句就是它），本批把该句的主机名更新为 GitHub。

---

## 6. 密钥与签名（F3）

| 项 | 值 / 做法 |
|---|---|
| 私钥 | `%USERPROFILE%\.baocode-release\update-signing.key`（32 字节随机种子的 base64，一行）；**仓库外**，不进提交、不进日志 |
| 私钥离线备份 | 生成后立刻把私钥文件复制到离线介质（U 盘 / 密码器 / 纸质密码本），备份件与原件同等保密；**删掉本机文件仍能发版**才算备份成立（需求 F3 的「必须离线备份」） |
| 生成 | `dart run tool/release_manifest.dart --generate-key "%USERPROFILE%\.baocode-release\update-signing.key"`（`:291-306`，已存在则拒绝覆盖） |
| 公钥 | 生成时打印；把打印值写进 `lib/update/update_signature.dart:8` 的 `updatePublicKey`（现值为上游的 `iBSgPUxNeT4jvgaua22aN/jCDwG+ry8rGc17kMcU4II=`） |
| 一致性闸 | `tool/release_manifest.dart:103-110`：私钥的公钥 ≠ `updatePublicKey` 直接拒绝签名 ⇒ 顺序必须是「生成 → 换常量 → 签名」 |
| 签名覆盖 | `baocode-update-v1\n<version>\n<platform>\n<size>\n<sha256>\n`（`update_signature.dart:20-27`）**不改协议**；已装客户端只认这五行 |
| 私钥丢失的后果 | 已安装用户再也收不到可信更新（新清单的签名验不过），只能手动重装；私钥泄露的后果 = 持有者可让所有用户装他们的程序（仍需控制清单来源） |

**必须先说清的连带后果（不是可选项）**。事实两条，分开记：

- 本批开始前该仓 releases = 0（`docs/batches/2026-10-21-github-releases-and-auto-update.md §1`）。
- 本批进行中已建 `v1.6.0` release 并上传了 `BaoCode-1.6.0-setup.exe`（22,010,965 B）；这个包是在换密钥**之前**构建的，里面编译的是上游公钥 ⇒ 它永远只能接受上游私钥签的更新，而我们没有上游私钥。

因此本批的处置是：**换完公钥后重建 `v1.6.0` 的资产并覆盖上传**（结论已定，§16 第 2 条），让已发布的那一版自带本 fork 的公钥；**第一个可作为更新目标的版本是 1.6.1 起的版本**。本机若已装旧构建，需手动重装一次（只影响本机）。该结论同时是 §12 验收 5 的前提句。

---

## 7. 发版（F4）

### 7.1 发版三步（构建 → 签名 → 发布）

```sh
# 1) 构建（产物 build/installers/BaoCode-<ver>-setup.exe）
dart run tool/build_windows.dart --stock-engine

# 2) 签名并生成清单（私钥路径走环境变量；不传 --minimum-version，见 §16 第 3 条）
set BAOCODE_UPDATE_SIGNING_KEY=%USERPROFILE%\.baocode-release\update-signing.key
dart run tool/release_manifest.dart --windows build/installers/BaoCode-<ver>-setup.exe ^
  --notes-zh <文本或文件> --notes-en <文本或文件> --version <ver> ^
  --manifest build/installers/latest.json

# 3) 建 release（draft）→ 上传两件 → 置非 draft（§7.2）
set /p GITHUB_TOKEN=GitHub PAT:
dart run tool/publish_release.dart --version <ver> ^
  --setup build/installers/BaoCode-<ver>-setup.exe --manifest build/installers/latest.json ^
  --notes <文本或文件>
set GITHUB_TOKEN=
```

- `set /p` 从提示读入 PAT：值不进命令行、不进 shell 历史、不落盘（`set GITHUB_TOKEN=<PAT>` 会把凭据留在历史里）；第三步跑完 `set GITHUB_TOKEN=` 清空。
- 三条命令分开的理由见 §2.1 偏离 4。

### 7.2 `tool/publish_release.dart`（新增）

| 项 | 形态 |
|---|---|
| 参数 | `--version <ver>`（缺省取 `pubspec.yaml`）、`--setup <exe>`、`--manifest <latest.json>`、`--notes <文本或文件>`、`--dry-run`。**没有 `--allow-dirty`**：脏树一律拒绝发版（见下「提交保护」） |
| 凭据 | 环境变量 `GITHUB_TOKEN`；缺失即退出并说明。权限面：classic PAT 的 `repo`，或 fine-grained 对 `ludonghuai/coder` 的 `Contents: read and write`（首跑核对，§15 U5） |
| 步骤 1 · 建 release（draft） | `GET /repos/{repo}/releases/tags/v<ver>` → 200 则复用其 `id`（已发布的**不改回 draft**，走步骤 2 的覆盖路径）；404 则 `POST /repos/{repo}/releases`：`tag_name`、`name`、`body`（notes）、**`draft=true`**、`prerelease=false`、`target_commitish=<HEAD sha>`。此刻 `releases/latest` 仍指向旧 release（首次发版时没有旧 release，该地址 404——那时也没有任何已装用户持本 fork 公钥，§6） |
| 步骤 2 · 删同名 + 上传两件 | `GET /repos/{repo}/releases/{id}/assets` → 命中同名者 `DELETE /repos/{repo}/releases/assets/{asset_id}`；上传 `POST https://uploads.github.com/repos/{repo}/releases/{id}/assets?name=<name>`（`Content-Type: application/octet-stream`，body = 文件流），**先 setup，后 latest.json** |
| 步骤 3 · 收尾置非 draft | `PATCH /repos/{repo}/releases/{id}`：`draft=false`、`prerelease=false`（幂等；复用已发布的 release 时这一步无变化）⇒ `releases/latest` 从这一刻起指向新 release，此时两件资产已齐 |
| 步骤 4 | 回读 `GET .../assets`，逐件断言名字在、`size` 与本地文件字节数相等；打印每件的 `browser_download_url` |
| 提交保护 | 建 tag 前读 `git status --porcelain`：非空则**拒绝**并列出脏路径（「发布的内容不在任何提交里」），不提供跳过开关；tag 用 `target_commitish=HEAD`，保证 tag 指到构建的那次提交 |

**可重入性（重复执行不建重复 release）**

- 同一 tag 已存在 ⇒ **复用**该 release（不新建），资产**按名删旧再传**，最终恰好两件资产；重复执行任意多次结果相同。
- 上传中断（半截资产已在列表里）⇒ 下次执行走同一个"删同名再传"路径，不留残件。
- 顺序保证：两件资产齐备之后才 `PATCH` 置非 draft，且 `latest.json` 在资产里**最后**上传 ⇒ **清单不会指向不存在的安装包；latest 在资产齐备前仍指向旧 release**（首次发版时该地址 404，理由同步骤 1）。
- **已知窗口（同 tag 覆盖一个已发布的 release）**：已发布的 release 不能置回 draft（那会让 latest 整段断掉，比覆盖窗口更长），所以走步骤 2 的删旧再传——从删掉旧 `latest.json` 到新件传完之间，`releases/latest/download/latest.json` 会短暂 404。
把顺序钉成「setup 先覆盖、`latest.json` 最后覆盖」，窗口就只剩一次小文件上传的时长；应用侧的表现 = 那一刻的检查更新失败一次，下一次检查即恢复，不会装错东西（安装包地址由清单声明，清单未换 ⇒ 指的还是旧包）。
**被否**：「临时名上传 → PATCH 资产改名 → 删旧件」——同一 release 内资产名不能重复（否则本步骤的「删同名再传」没有存在理由），改名同样要先删旧件，窗口只从一次小文件上传缩到两次元数据调用，不值得多一条代码路径。
- 不做的事：不删 release、不改 tag 指向、不 force-push 任何分支。撤版 = 覆盖资产（回到旧内容并重传），与需求档 §3 的 `minimumVersion` 语义一致。

### 7.3 为什么用 Dart 脚本而不是 `gh`

`gh` 不是本仓既有依赖，且在 Windows 上多一层安装前提；`tool/` 已是 Dart 工具的家（`build_windows` / `release_manifest` / `bump_version` 都是）。上传是单次 `POST` 一个文件体（`POST https://uploads.github.com/repos/{repo}/releases/{id}/assets?name=<name>`），Dart 的 `HttpClient` 直接做，不需要 multipart。

### 7.4 上游 CI 的处置

`.github/workflows/release.yml:30-33` 以 `push: tags: ['v*']` 触发，收尾会 `gh release delete` + `gh release create`（`:602-603`），依赖 R2 与签名密钥 secret（`:406-407`、`:516`）。本 fork 不发 R2、不给这些 secret ⇒ 本批把触发改成**只 `workflow_dispatch`**（保留文件与 inputs，将来要用可手跑）。这是本仓自己的 CI 文件，不涉及上游仓设置；回滚 = 恢复 `on:` 段（§14 第 4 条）。

---

## 8. 只在发行版生效（F2 的"边界"条、验收 7）

**机制（零改动）**：`lib/update/installer_io.dart:19-20` 的 `if (!kReleaseMode && override.isEmpty) return null;`。返回 null ⇒ `main.dart:527-530` 直接 `return null` ⇒ **不构造 `UpdateService`、不构造 `IoUpdateBackend`、不发任何请求**。
`kReleaseMode` 是编译期常量，**debug 构建恒为 false**（`flutter test` 与默认 `flutter run` 都是 debug；`flutter run --release` 下为 true）。

**新增的唯一改动（可测性缝，不改语义）**：`platformUpdates` 增加可选参数 `Map<String, String>? environment`，内部 `environment ?? Platform.environment`（形同 `WindowsUpdateInstaller(environment:)` 已有做法，`installer_io.dart:157`）。理由：`Platform.environment` 在测试里改不了，不注入就只能依赖开发者 shell 是否恰好设了 `BAOCODE_UPDATE_URL`，那样的用例不算机检。

**用例（§11 T5 / T6）**：

- T5：`flutter test`（debug，`kReleaseMode == false`）+ `environment: const {}` ⇒ `platformUpdates(updatesDirectory: <临时目录>)` **为 null**；判据 = 拿不到 backend，所以"不发请求"由构造链本身保证（null 之下没有对象能发请求）。
- T6：同一 debug 环境 + `environment: {BAOCODE_UPDATE_URL: 'https://example.test/latest.json'}` ⇒ 非 null，且 `manifestUrl` == 该值、`platform` 是本机平台键。证明门是 `override.isEmpty`，本批没有新增任何开关。

**不做**：不加 `kReleaseMode` 之外的渠道开关，不改 `BAOCODE_UPDATE_URL` 的语义，不在 debug 下打印"更新已禁用"的额外日志。

---

## 9. 受影响文件清单（行数 = 2026-10-21 23:44 实测）

| # | 坐标 | 现值 | 改动 | delta |
|---|---|---|---|---|
| ① | `lib/update/update_manifest.dart` | 264 | `updateRepository` + 新 `defaultManifestUrl`；`githubHosts` 与 `allows` 的主机判定；错误文案点名全部主机 | +14 / −7 |
| ② | `lib/update/update_signature.dart` | 61 | 只换 `:8` 常量值（行数不变） | 0 |
| ③ | `lib/update/installer_io.dart` | 584 | `platformUpdates` 的 `environment` 可选参数 | +3 / −1 |
| ④ | `tool/release_manifest.dart` | 382 | 链接由 `updateRepository` 拼出（`:53`、`:56-58`）；去掉 `?sha256=`；头注释里的地址改为清单地址 | +8 / −5 |
| ⑤ | `tool/publish_release.dart` | 新增 | 建 / 复用 release、同名覆盖、上传、回读断言、`--dry-run` | ≈ +230 |
| ⑥ | `.github/workflows/release.yml` | 606 | `on:` 改为只 `workflow_dispatch`（保留 inputs） | +1 / −3 |
| ⑦ | `test/update/update_manifest_test.dart` | 234 | 策略四断言 + 额外拒绝项（§11 T1–T3） | ≈ +30 |
| ⑧ | `test/update/installer_test.dart` | 407 | debug 门与 override（§11 T5 / T6） | ≈ +30 |
| ⑨ | `docs/auto-update.md` | 571 | 服务端约定（5.1 / 5.2 示例）、策略（5.3）、密钥值（6.2）、发版步骤（第 7 节指向本档）按本档对齐 | ≈ +12 / −8 |
| ⑩ | `docs/design/distribution.md` | 新增 | 本档 | 389 行（修正轮后实测） |
| ⑪ | `docs/release.md` | 451 | 顶部加一行横幅：「tag 触发已停用：本 fork 发版见 `docs/design/distribution.md` 与 `docs/auto-update.md`」；全文对齐另立批（§13） | +1 / −0 |

- **零改动（明确）**：`lib/update/update_service.dart`（策略仍在 `:398` 构造）、`lib/update/update_io.dart`（仍跟随重定向，§5）、`lib/main.dart`、`tool/build_windows.dart`、`tool/baocode.iss`、`lib/update/update_settings.dart`。
- **跨文件上限**：无代码文件越过 800 行（最大 `installer_io.dart` 584 + 3）；`release.yml` 是 CI 配置，不进代码行数口径。`docs/auto-update.md` 只做行级替换，不拆档（文档行宽上限 300 字符，见 `PROJECT-MANIFEST.json` 的 `checkConfig.lineWidth`）。
- **>500 档判定（`installer_io.dart`）**：584 → 586 只是给 `platformUpdates` 加一个可选参数（`environment`），不改结构、不动既有分支 ⇒ 本批**不拆分**、不预留拆分计划；越 500 是既有状态，本批不处理（拆分另立批）。
- **零改动、但有结论的项**：需求 §5 列的「`update_service.dart` 的下载页链接（可选）」本批**不取用**：`update_service.dart:79` 的 `downloadPage` 仍指 `https://baocode.dev/download`（上游站点）。理由 = 它是可选项，本批不建下载页，改指一个还不存在的地址只会把用户送到 404；自建下载页落地后再改（另立批）。

---

## 10. 关键决策记录（含被否）

| # | 决策 | 理由 / 被否 |
|---|---|---|
| D1 | 渠道 = GitHub Releases（`ludonghuai/coder`），清单与安装包同域 | 同域才过 URL 策略；不建 CDN 是需求档边界。被否：raw 分支文件（地址可变、可被强推） |
| D2 | 清单里写**具体 tag** 的资产地址，只有 `defaultManifestUrl` 用 `latest/download` | 清单与资产必须严格对应同一版；`latest` 只用于"去哪儿拿清单"这一跳 |
| D3 | 重定向**不做**最终 URL 校验，只校验声明 URL | §5：内容由 size / SHA-256 / 签名钉死，校验重定向收益为零、改动落在想与上游保持易合并的文件上 |
| D4 | 白名单写两个 GitHub 主机（精确匹配，不含子域） | 记录重定向落点，未来若要校验重定向不必再改策略；`github.com` 的子域一个不放（`api.` / `codeload.` 都不需要） |
| D5 | 换公钥 ⇒ 重建并覆盖 `v1.6.0` 资产；首个可更新时间点是 1.6.1 | 旧资产用上游公钥编译，永远接不了我们的签名（§6）；本批前 releases 为 0，没有对外用户受影响 |
| D6 | 发版脚本 = `tool/publish_release.dart`，`GITHUB_TOKEN` 走环境变量 | 同 §7.3；被否：`gh`（非既有依赖）、CI 内发版（本 fork 无 R2 / 签名 secret） |
| D7 | 同一 tag 内"删同名再上传"实现同名覆盖 | 满足"地址不变"，且天然可重入；被否：每次发版新建 tag（地址变，用户手里的旧清单指向的资产必须永久留着，仓里 tag 无限膨胀） |
| D8 | `release.yml` 改 `workflow_dispatch` | §7.4：tag 一推就排必失败的上游 CI，收尾还会删建 release |
| D9 | `platformUpdates` 加 `environment` 可选参数 | 只为可测；`Platform.environment` 不可注入时，T5 会依赖开发者 shell，不算机检。被否：在测试里改进程环境（Dart 不支持）|
| D10 | 不改签名 payload 协议 | 已装客户端只认 `baocode-update-v1` 五行；改协议等于让所有已装版本拒绝新清单（`docs/auto-update.md` 12 节的迁移做法要两个版本） |

---

## 11. 用例表

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| T1 | 策略放行 GitHub 两域 | 两次独立的 `UpdateManifest.parse`，各带一条 `windows-x64` URL：① `https://github.com/ludonghuai/coder/releases/download/v1.6.1/BaoCode-1.6.1-setup.exe`；② `https://objects.githubusercontent.com/…` | 两次 `parse` 都不抛；各自的 `assetFor('windows-x64')` 非 null |
| T2 | 策略拒绝任意域与降级形态 | `https://evil.example/x.exe` · `http://github.com/x.exe` · `https://api.github.com/x.exe` · `https://github.com:8443/x.exe` · `https://user@github.com/x.exe` · `https://github.com.evil.example/x.exe` | 六条都抛 `UpdateManifestException`（`_invalid('https')`） |
| T3 | 旧渠道链接仍可用（回归） | `https://baocode.dev/x.exe` · `https://cdn.baocode.dev/x.exe` · `BAOCODE_UPDATE_URL` 同源 `http://127.0.0.1:8080/x.exe` | 均放行（现用例保持绿） |
| T4 | 清单工具产出 GitHub 链接 | `dart run tool/release_manifest.dart --windows <fixture> --version 9.0.0 --manifest <tmp>/latest.json`（用已有私钥） | 生成的 JSON 里 `platforms.windows-x64.url` 以 `https://github.com/ludonghuai/coder/releases/download/v9.0.0/` 开头；无 `?sha256=`；`size` / `sha256` 与实际文件一致 |
| T5 | debug 不发请求 | `flutter test`（`kReleaseMode == false`）+ `environment: const {}` | `platformUpdates(...)` 返回 null（于是没有 service、没有 backend、没有请求） |
| T6 | override 仍开 debug 的更新 | 同上 + `environment: {'BAOCODE_UPDATE_URL': 'https://example.test/latest.json'}` | 非 null；`manifestUrl` == 该值；`platform` == 本机平台键 |
| T7 | 发版脚本可重入（人工，§15 U5 首跑） | 同一版本连跑两次 `publish_release.dart` | 两次后仓库里该 tag 仍只有 1 个 release、2 件资产，`size` 与本地一致；第二次不出现新 release |
| T8 | 验签面（发版后一次性读数，不进常驻用例） | 用旧公钥字面量（`iBSgPUxNeT4jvgaua22aN/jCDwG+ry8rGc17kMcU4II=`）验新 `latest.json` 的签名 | `UpdateSignature.verify(...) == false`；用新公钥 == true |

- T1–T3 进 `test/update/update_manifest_test.dart`，T5–T6 进 `test/update/installer_test.dart`；T4 是命令读数（脚本不支持无密钥运行，故用本机已生成的私钥跑一次，结果记进 §5 实施记录）；T7 / T8 属发版面，不进 `flutter test`。

---

## 12. 验收对照（回指需求档 F1–F5 与验收 1–7）

| 需求判据 | 本档落点 | 机制 | 机检 / 走查 |
|---|---|---|---|
| F1 发布渠道 | §3、§7 | tag + 固定资产名 + `latest/download` + 同名覆盖 | T7（可重入）+ 发版后 `curl -sI` 两条地址 |
| F2 清单与安装包同为资产 | §3、§4.3 | 清单里写本 tag 资产地址；清单本身也是资产 | T4（工具产出）+ 发版后读 `latest.json` |
| F3 自有密钥 | §6 | `--generate-key` → 换 `updatePublicKey` → 签名闸（`:103-110`） | T8（旧公钥验不过、新公钥验得过） |
| F4 发版流水线（三步） | §7、§2.1 偏离 4 | 构建 → 签名 → `publish_release.dart` | T7；凭据只从 `GITHUB_TOKEN` / `BAOCODE_UPDATE_SIGNING_KEY` 取 |
| F5 URL 策略扩到 GitHub | §4.2、§5 | 精确主机白名单 + 其余判定不变 | T1 / T2 / T3 |
| 验收 1 匿名可下 | §3 可见性行 | 仓库公开 + 无鉴权地址 | 公开后 `curl -sI` 两条 200（现在不能验，§15 U1） |
| 验收 2 签名有效 | §6 | 新公钥验过、旧公钥拒 | T8 |
| 验收 3 清单自洽 | §4.3 | size / sha256 由工具从实际文件算 | T4 + `sha256sum` 复核 |
| 验收 4 策略放行 | §4.2 | 两个 GitHub 域 | T1 |
| 验收 5 真机升级 | §6 连带后果 | 装**重建后的** 1.6.0 → 发 1.6.1 → 点检查更新 → 装完版本号变 1.6.1 | 走查（§15 U3）；前提：基线必须是换公钥后重建并覆盖上传的 1.6.0（§16 第 2 条已定） |
| 验收 6 上游清单被拒 | §6 | `BAOCODE_UPDATE_URL=<上游清单>` ⇒ 签名验不过 | 走查一条：错误面是 "The download is not signed by BaoCode"，不安装 |
| 验收 7 开发环境不发请求 | §8 | `installer_io.dart:20` 保持不变 | T5 / T6 |

---

## 13. 边界（本批不做）

- 不建对象存储 / CDN；不做增量更新（每次整包）。
- 不做 macOS 签名与公证；macOS 资产本批不发布（清单里没有 macOS 键 ⇒ 那些平台的用户看到"已是最新"，与今天一致）。
- 不自动改仓库可见性，不调任何仓库设置 API。
- 不碰上游仓（不读它的 private key，不发它的 release，不改它的设置）。
- 不改签名 payload 协议（D10）。
- 不在 debug 下新增任何渠道分支或开关（§8）。
- 不重写 `docs/release.md`（上游 CI / R2 流程文档）：本 fork 已停用那条流水线（§7.4），本批只在它顶部加一行横幅（tag 触发已停用，发版见 `docs/design/distribution.md` 与 `docs/auto-update.md`；§9 ⑪），全文对齐另立批；本批只在 `docs/auto-update.md` 顶部把发版指向本档。
- 移动端 / Web 的更新面不在本批（`installer_stub.dart` 不变）。

---

## 14. 回滚单位（三处各自独立）

1. **URL 策略**（`update_manifest.dart`）：把 `githubHosts` 从判定里去掉、`defaultManifestUrl` 改回旧值 ⇒ 应用回到"只认 baocode.dev"，装过的用户继续从 GitHub 升不了级，但不会误装任何东西；`test/update/update_manifest_test.dart` 的 T1 会红，属预期。
2. **密钥**：`updatePublicKey` 换回旧值 ⇒ 新签名的清单全部验不过（更新停摆），已装的旧版本行为不变。**密钥本身不回滚**：私钥一旦用于对外发版就不能撤（旧客户端已经信任它）。
3. **发版脚本**（`tool/publish_release.dart` + `release.yml` 的触发）：独立于应用行为；删掉脚本、恢复 CI 触发，应用侧零影响，已发布的资产留在 GitHub 上。
4. **CI 触发**（`release.yml` 的 `on:`）：恢复 `push: tags: ['v*']` 即回到上游行为（每条 tag 排一条必失败的构建）。

---

## 15. 未验证项（单列，不静默省略）

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| U1 | 私有仓下 `releases/latest/download/latest.json` 匿名下载 | 预期 404（需要鉴权）；本机无 PAT，未实测 | 仓库公开后 `curl -sI` 两条地址；验收 1 以该读数为准 |
| U2 | release 资产重定向的实际主机名 | 未观测（私有仓匿名取不到 302）；候选 `objects.githubusercontent.com` / `release-assets.githubusercontent.com` | 不承重：重定向不校验（§5）；若将来要校验，先按首跑观测值校正白名单 |
| U3 | 真机升级全链路（装 1.6.0 → 读 1.6.1 → 装完版本变化） | 需先有换公钥后的 1.6.0 与一个 1.6.1，本机尚未产生 | 发 1.6.1 后按 §12 验收 5 走查；判据 = 安装完成、重启后版本号 = 1.6.1 |
| U4 | GitHub 资产上传上限与端点 | GitHub 文档口径：每文件 < 2 GB、端点 `uploads.github.com`（第三方转述，未取一手页面）；本机安装包 21 MB，远低于上限 | 首跑读数：上传成功 + 回读 `size` 一致即成立 |
| U5 | `GITHUB_TOKEN` 的最小权限面 | 未实测；classic `repo` 必然够，fine-grained `Contents: read and write` 待首跑 | 首跑遇 401 / 403 时按响应头校正，并把结论写进 §7.2 |
| U6 | 发版脚本的 dry-run 计划与实际请求一致 | 脚本未写 | 实施后 `--dry-run` 打印的 URL / 方法 / 资产名逐条核对一次 |
| U7 | draft → 上传 → PATCH 三步的实际效果 | 脚本未写 | 首跑读数：建 release 后 `GET /releases/latest` 仍指旧 release；两件资产齐后 PATCH 的结果里 `draft=false`；`curl -sI` 清单地址 200 |

---

## 16. 已裁定事项（结论）

1. **`docs/auto-update.md` 的对齐由设计席位在本批实施轮落**（不另立批）：§9 ⑨ 的 delta 就是这场对齐的清单（服务端约定 5.1 / 5.2、策略 5.3、密钥值 6.2、第 7 节指向本档）。
2. **v1.6.0 资产覆盖重建**（D5）：换钥后重建并覆盖同一 tag（§6 的处置即此）；依据 = 本批开始前该仓 releases = 0（`docs/batches/2026-10-21-github-releases-and-auto-update.md §1`）、现在仍私有、没有对外用户。
3. **不传 `minimumVersion`**：发版命令不带 `--minimum-version`（§7.1）⇒ 清单里没有该字段（`update_manifest.dart:258` 按空值省略）⇒ 应用侧 `isMandatory` 恒为 false（`update_service.dart:272`）⇒ 不强制任何已装用户。注意：工具会沿用本地同版本旧清单里的值（`release_manifest.dart:147-152`），要保证清单干净，发版前删掉 `build/installers/latest.json`。
