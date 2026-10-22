# 分发与更新（distribution）需求

> 板块：分发渠道与自动更新（`tool/`、`lib/update/**`、GitHub Releases）· 范围仓：baocode。
> 状态：需求（用户 2026-10-21 23:24–23:33 提出「用户如何更新？」「我们不能发布在 github 上面吗」「自动更新也要做」）。
> 来源仓 = `ludonghuai/coder`（fork）；上游 `baocode-dev/baocode` 只读，本板块不改上游任何设置。

## 1. 模块目标

让拿到本 fork 构建的用户**能自己升级**，且升级指向本 fork 的版本，不被上游版本接管；分发渠道只用 GitHub，不新建 CDN/存储桶。

## 2. 功能点

**F1 发布渠道：GitHub Releases**
- 每次发版在 `ludonghuai/coder` 建一个 release，tag = `v<版本>`；安装包作为 release 资产上传。
- 附件下载走 GitHub 的稳定地址（`releases/download/<tag>/<file>`）；"最新一版"的地址用 `releases/latest/download/<file>`。
- 仓库可见性由用户决定；**公开是匿名下载的前提**（私有仓的资产需鉴权，用户侧不可用）。

**F2 自动更新：清单与安装包都放 release 资产**
- 应用默认清单地址改为 `https://github.com/ludonghuai/coder/releases/latest/download/latest.json`（每次发版覆盖同名资产，地址不变）。
- 清单里的下载地址指向同一 release 的安装包资产；两者同域（`github.com`），满足 URL 策略的同源判定。
- 更新流程保持现状：读清单 → 校验签名 → 下载 → 校验 SHA-256 → 安装。
- **只在发行版生效**：debug 构建不发起任何清单请求（今天由 `lib/update/installer_io.dart:20` 的 `!kReleaseMode && override.isEmpty ⇒ null` 保证；本板块保持这条，不为新渠道在开发侧加任何行为）。

**F3 自有签名密钥**
- 生成一对 Ed25519 密钥：私钥存仓库外（`~/.baocode-release/update-signing.key`，不进仓库、不进日志），公钥替换 `lib/update/update_signature.dart` 的 `updatePublicKey`。
- 私钥丢失 = 已安装用户无法再收到可信更新，只能手动重装 ⇒ 必须离线备份。

**F4 发版流水线：一条命令出三件**
- 构建（`tool/build_windows.dart`）→ 签名并生成 `latest.json`（`tool/release_manifest.dart`）→ 建 release 并上传安装包与 `latest.json`。
- 签名与上传所需的凭据只从环境变量取，不落盘到仓库。

**F5 URL 策略扩到 GitHub**
- 清单允许的下载域从「`baocode.dev` + 清单同源」扩到包含 GitHub 的两个必要域：清单与资产的 `github.com`、资产重定向后的 `objects.githubusercontent.com`。
- 判定仍以清单声明的 URL 为准，不放松到任意域。

## 3. 边界（明确不做）

- 不建自建对象存储/CDN；不做增量更新（每次整包）。
- 不改上游仓的任何设置、不发上游的 release、不碰上游密钥。
- 不做 macOS 签名与公证（本机无 Apple 账号）；macOS 资产暂不发布。
- 不做"强制升级"以外的运营能力（`minimumVersion` 沿用现有语义）。
- 不自动改仓库可见性（用户自管）。
- **开发环境零变化**：`flutter run` / 本仓测试不得因本板块多发一次网络请求、多读一次清单，或改变任何默认值；渠道差异只由“是不是发行构建”这一条自然分叉（沿用 `kReleaseMode` 既有判据，不新增开发开关）。

## 4. 验收（可机检）

1. **匿名可下**：不带任何凭据请求 `releases/latest/download/latest.json` 与安装包，均返回 200（公开仓前提下）。
2. **签名有效**：`latest.json` 用新公钥验证通过；用旧公钥（`updatePublicKey` 原值）验证失败。
3. **清单自洽**：`version` / `size` / `sha256` 与实际资产逐项一致（`tool/release_manifest.dart` 产出的值，用 `sha256sum` 复核）。
4. **策略放行**：清单里 GitHub 资产地址通过 `UpdateUrlPolicy` 判定（单测覆盖 `github.com` 与 `objects.githubusercontent.com` 两个域）。
5. **真机升级**：装 1.6.0 的机器点"检查更新"，能读到新版本、下载校验通过、安装完成后版本号变为新版。
6. **上游清单被拒**：把清单地址临时指回上游（`BAOCODE_UPDATE_URL`），因签名公钥不同，应用应报签名无效而不是安装。
7. **开发环境不发请求**：debug 构建下 `platformUpdates` 返回 null（不构造 `UpdateService`、不发任何清单请求）；单测覆盖。

## 5. 依赖

- **仓库公开**（用户侧操作）——否则 1 不成立。
- 密钥对生成（本机一次）。
- `lib/update/update_manifest.dart` 的 URL 策略、`lib/update/update_signature.dart` 的公钥常量、`lib/update/update_service.dart` 的下载页链接（可选）。
- 发版脚本新增"建 release + 上传"步骤（GitHub API，token 走环境变量）。
- 内置 thincoder（另一批次）不属本板块；本板块只解决"怎么把包装出去、用户怎么升级"。
