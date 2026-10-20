# forge 账户（Gitee 接入）设计档

> 板块：账户与代码托管（forge）· 范围仓：baocode。
> 配对需求档：`docs/requirements/forge-accounts.md`（用户 2026-10-16 已确认：令牌登录 · 功能面对齐 · 私有仓支持）。
> 本档 = 板块首篇，范围 = **Gitee 接入**（需求档 F1–F5；边界 B1–B3 全程沿用）。
> 状态：设计稿 · 2026-10-16 · 文内行号 = 编制日快照（实施按符号定位）；行号各档自用、跨档不对齐。

---

## 1. 模块目标与范围

需求档 §1 已定：账户页（设置 → 账号）与 forge 模块承载多代码托管平台的身份与协作面。本档把 **Gitee 落成第三家**，与 github / gitlab 同口径。

**交付面**：F1 令牌登录（账户页 Gitee 区块）· F2 身份（`me`）· F3 协作面（条目详情 / issues 列表 / 评论 / 关闭）· F4 私有仓 · F5 链接识别与图标。

**不做**：B1 浏览器 / 设备码登录 · B2 checks 类无对应面 · B3 不动既有两家行为（用户可见文案随第三家更新，见 §3.7 / §8）。

---

## 2. 做法与理由

### 2.1 做法一句话

新增 `ForgeKind.gitee` 一个 kind，按两家同形落三处：`forge_ref`（主机与链接解析）· `forge_api`（`GiteeApi`，Gitee OpenAPI v5）· `forge_accounts` + `accounts_page`（令牌登录、令牌页、作用域文案、图标）。

一条**共用面改动**：Gitee 的 issue 编号是字母数字字符串（实测 `"IKLL6H"`），`ForgeRef.number` 由 `int` 放宽为 `String`（两家行为不变，见 D1）——这是本批唯一触及两家的源码改动。

### 2.2 最近先例对照（对齐 ∥ 偏离及理由）

先例三元组：实现坐标 = 下表逐条（`file:line`）；匹配设计档章节 = 无——github / gitlab 两家接入早于本板块首篇，账户接入面的旧记载见 `docs/stash.md:141-142`；先例批次 = 无（`docs/batches/` 无 forge 板块批次）。

对齐（照抄形态，不另造）：

| 面 | 先例 | 照抄的形 |
|---|---|---|
| per-kind API | `GitHubApi` / `GitLabApi`（`lib/forge/forge_api.dart:227` / `:393`） | `GiteeApi extends ForgeApi`，面 = `me` / `item` / `issues` / `comment` / `close` |
| API 基址 | GitLab `_base => Uri.https(host, '/api/v4')`（`forge_api.dart:396`） | `Uri.https(host, '/api/v5')` |
| 主机表 | `publicForgeKind`（`lib/forge/forge_ref.dart:33-37`）· `ForgeKind.label` / `publicHost`（`:15-25`） | 加 gitee 臂（`gitee.com` / `www.gitee.com`） |
| 链接解析 | GitHub 臂（`forge_ref.dart:184-204`） | Gitee 臂 `<owner>/<repo>/(issues\|pulls)/<id>` |
| 令牌登录组件 | `ForgeTokenDialog`（`lib/settings/pages/accounts_page.dart:210`） | 复用不改：kind 参数传 gitee，host 默认 `gitee.com` |
| 令牌页 / 撤销页 | `forgeNewTokenPage`（`accounts_page.dart:166-176`）· `forgeRevokePage`（`:145-163`） | 加 gitee 臂（私人令牌页，登录与撤销同页） |
| 图标 | gitlab 的 SVG 资产臂（`lib/forge/forge_view.dart:29-40`） | `assets/branding/gitee.svg`，单色可着色，方形 viewBox |
| 错误面 | `forgeErrorMessage`（`forge_api.dart:51-62`）撞 `message` 键 | Gitee 错误体恒 `{"message": …}`，原样命中（实测） |

偏离（逐条给理由）：

1. **`ForgeRef.number` 类型放宽（`int` → `String`）** —— Gitee 现行 issue 编号即字符串，`int` 装不下（D1）。
2. **`GiteeApi.issues` 在 `filter ≠ all` 时先取一次 `me()`** —— 列表按归属过滤只能用 `assignee=<login>` / `creator=<login>`，Gitee 无 `@me`（D3）。
3. **issues 列表按「未关闭」口径发两次请求**（`state=open` + `state=progressing` 合并）—— 两家的「open」都是「未关闭」，Gitee 把它拆成两个开态（D4）。
4. **关闭 issue 走命名空间级端点**（`PATCH /repos/{owner}/issues/{number}`，`repo` 作参数）—— 与两家的 repo 级路径不同形，但这是官方文档与官方 MCP 客户端的共同写法（D5）。
5. **设备流两处 switch 加不可达臂**（抛 `ForgeException`）—— Gitee 无设备码流（B1），臂必须存在以保 switch 穷尽，且不得凭空造一个端点。

---

## 3. 接口契约

### 3.1 端点对位表（逐条带来源）

来源代号：

- **[D]** Gitee 官方 OpenAPI 文档（入口 `https://gitee.com/api/v5/swagger`；机器可读 `https://gitee.com/api/v5/doc_json`，标称 Gitee Open API 5.4.93，2026-10-16 取）。
- **[O]** Gitee 官方 OAuth 文档（`https://gitee.com/api/v5/oauth_doc`）。
- **[M]** Gitee 官方 MCP 客户端（`gitee.com/oschina/mcp-gitee`；认证头见 `utils/gitee_client.go`；端点见 `operations/issues/`、`operations/pulls/`——评论 PR = `operations/pulls/comment_pull.go`：`POST /repos/{owner}/{repo}/pulls/{number}/comments`，载荷 `{body}`）。
- **[P]** 本批实测探针（2026-10-16，无令牌公开读；命令与读数见 §9 末）。

base = `https://{host}/api/v5`（[D] `basePath=/api` + 路径前缀 `/v5`）。认证 = `Authorization: Bearer <token>`（[M] + [P]，见 §3.5）。

| # | 面 | 方法与路径 | 关键参数 | 返回模型 | 来源 |
|---|---|---|---|---|---|
| 1 | 身份 | `GET /user` | — | `UserDetail{login,name}` | [D] [M] [P] |
| 2 | 条目·issue | `GET /repos/{owner}/{repo}/issues/{number}` | `number` 字符串、区分大小写 | `Issue` | [D] [P] |
| 3 | 条目·PR | `GET /repos/{owner}/{repo}/pulls/{number}` | `number` 整数 | `PullRequest` | [D] [P] |
| 4 | issues 列表 | `GET /repos/{owner}/{repo}/issues` | `state` `sort=updated` `direction=desc` `per_page`（≤100）`assignee` `creator` `q` | `Issue[]` | [D] [P] |
| 5 | 评论·issue | `POST /repos/{owner}/{repo}/issues/{number}/comments` | `body` | `Note` | [D] [M] |
| 6 | 评论·PR | `POST /repos/{owner}/{repo}/pulls/{number}/comments` | `body` | `PullRequestComments` | [D] [M] |
| 7 | 关闭·issue | `PATCH /repos/{owner}/issues/{number}` | `repo`、`state=closed` | `Issue` | [D] [M] |

不取用（[D] 里有、本批不做）：创建 issue · PR 合并 / 关闭 / review · labels / 里程碑增删 · enterprises 面 · `/user/issues`（跨仓，装不进按仓列表）。

### 3.2 字段对位（→ `ForgeItem`）

**Issue**（端点 2 / 4）：

| ForgeItem | Gitee 字段 | 备注 |
|---|---|---|
| `ref.number` | `number` | **字符串**，例 `"IKLL6H"`、`"IDBSA"` [P] |
| `title` | `title` | |
| `state` | `state`：`open` / `progressing` → `ForgeState.open`；`closed` / `rejected` → `closed` | 枚举 [D]（列表端点 `state` 含 `rejected` 取值） |
| `body` | `body` | |
| `author` | `user.login` | [P] |
| `labels` | `labels[].name`、`labels[].color` | color 为 `rrggbb` 无 `#`（实测 `"fd6206"`）⇒ 补 `#` 前缀（同 GitHub 臂 `forge_api.dart:329-332`） |
| `assignees` | `assignee.login`（**单个**负责人） | 协作者 `collaborators` 不计入（列表义 = 负责人，同两家字段义） |
| `comments` | `comments`（数字） | [P] |
| `updated` | `updated_at` | ISO 8601 带时区（实测 `+08:00`）；`forge_api.dart:218-219` 同口径 |
| `checks` / `branch` | — | 恒 null（无 checks 面，B2） |

**PullRequest**（端点 3）：

| ForgeItem | Gitee 字段 | 备注 |
|---|---|---|
| `ref.number` | `number` | 整数（实测 `597`） |
| `title` / `body` / `author` / `labels` | 同 Issue 表 | |
| `state` | `merged_at != null` → merged；否则 `state == 'closed'` → closed；否则 `draft == true` → draft；否则 open | [D] `state` 枚举 `open/closed/merged`；[P] 实测 `draft` 布尔、`merged_at` |
| `assignees` | `assignees[].login` | [D] |
| `comments` | **恒 0**（推断） | PR 详情无评论数字段（[P] 两次探针均无 `comments` 键；样本 PR 无评论 ⇒ R10，A5 复核） |
| `updated` | `updated_at` | 同 Issue |
| `branch` | `head.ref` | `head` 实测是对象 `{ref,sha,user,repo,…}`（[D] 写作 string，以实测为准） |
| `checks` | — | 恒 null（D6） |

### 3.3 主机与链接解析（F5）

- `ForgeKind` 加 `gitee`：`label 'Gitee'`、`publicHost 'gitee.com'`。
- `publicForgeKind`：加 `gitee.com` | `www.gitee.com`（[P] 实测 www 302 → gitee.com；与两家含 www 同形）。
- `ForgeRepo.fromRemote`：gitee 与 github 同规约 —— 路径恰两段（Gitee 无子组）；`git@gitee.com:o/r.git` ⇒ `o/r`。
- `ForgeRef.parse` 加 Gitee 臂：`/{owner}/{repo}/issues/{编号}` → issue；`/{owner}/{repo}/pulls/{序号}` → pull。编号 = 非空字母数字、**区分大小写**；PR 序号 = 数字；尾随段与锚点忽略（同两家）。不识别 `/-/…`（非 Gitee 形）与 `/enterprises/…`。
- **`/-/` 臂的主机闸门收紧**：现判据 `known != ForgeKind.github`（`forge_ref.dart:171`）加入 gitee 后会把 gitee 主机的 `/-/…` 误判成 GitLab ⇒ 改为「主机未识别，或识别为 gitlab」才走此臂；对 github / gitlab 两家的判定结果不变（回归用例 G15）。
- `ForgeRef.url` / `tag`：Gitee 的 issue 与 PR 页面同形（`/issues/{id}`、`/pulls/{n}`），tag 用 `#`（Gitee 无 `!` 写法）。

### 3.4 账户页对位（F1 / F2）

| 面 | 现状坐标 | Gitee 落点 |
|---|---|---|
| 账户页描述 | `accounts_page.dart:37` / `:45`（`accountsDescription`，两处同键） | 改文含 Gitee —— 用户 2026-10-16 裁定（R9）；新文见 §3.7 清单第 1 行 |
| 令牌保管说明 | `accounts_page.dart:57`（`accountsKeptLocally`） | 改文含 Gitee —— 用户 2026-10-16「补gitee」扩裁；新文见 §3.7 清单第 2 行 |
| 主机行文案 | `accounts_page.dart:59-65`（`accountsGitHubHosts` / `accountsGitLabHosts`） | 加 `accountsGiteeHosts`：文案只承诺 `gitee.com` |
| 浏览器登录按钮 | `:68-75`（`canSignInFromBrowser` 为真才显示） | `canSignInFromBrowser(gitee, …) => false` ⇒ **不显示**（B1） |
| 令牌登录 | `:76-82` → `ForgeTokenDialog`（`:210`） | 复用不改：host 默认 `gitee.com`，粘贴令牌提交；错误行同两家 |
| 令牌创建链接 | `forgeNewTokenPage`（`:166-176`） | gitee 臂：`https://{host}/profile/personal_access_tokens`（[P] 未登录访问 307 → `/login?redirect_to_url=/profile/personal_access_tokens`，路由存在）；不带预填参数（是否支持未核实，见 R8） |
| 撤销链接 | `forgeRevokePage`（`:145-163`） | gitee 臂（仅 token 一形）：同一私人令牌页 |
| 作用域文案 | `:321-324`（两个 scopes 键） | 加 `accountsTokenGiteeScopes`（文本见 §3.6） |
| 图标 | `forge_view.dart:29-40`（gitlab 臂） | gitee 臂：`assets/branding/gitee.svg`（官方 logo 的单色 G 字形；16px 可辨为准，见 R7） |
| 账户行 / 登出 / 身份 | `:94-141` | 不改（`kind.label`、`canSignInFromBrowser` 两处已含 gitee） |

l10n：新增 2 键（`accountsGiteeHosts`、`accountsTokenGiteeScopes`）+ 5 键改文 + 扩裁① `settingsAccountsKeywords` 补词（清单与新文见 §3.7）同时落 `lib/l10n/app_en.arb` 与 `app_zh.arb`。
`lib/l10n/app_localizations*.dart` 由 `flutter gen-l10n`（`l10n.yaml`，`flutter pub get` 触发）重生成，**不手改**；`test/l10n_test.dart` 的 en/zh 键一致与非空两条校验随之通过。

### 3.5 认证、错误与限流口径

- **认证**：`Authorization: Bearer <token>`。依据 [M]（官方客户端写法）+ [P]：同一 `/user` 请求，无令牌 → `{"message":"登录失效，无权限访问该资源","code":40001}`；带不存在的令牌（请求头，或以 `access_token` 参数）→ `{"message":"401 Unauthorized: Access token does not exist"}`（401）。两者报错不同 ⇒ 令牌头被读取。
- **错误体**：恒为 `{"message": "..."}`（实测 401 / 404）⇒ `forgeErrorMessage`（`forge_api.dart:51-62`）的 `message` 臂命中；401 ⇒ `ForgeException.unauthorized`（`:44`）。
- **请求体**：写请求按 JSON（[M] 客户端 `Content-Type: application/json` 发 PATCH / POST）；`ForgeHttp.send` 的 `json` 参数即此形 ⇒ `GiteeApi` 无须改 `ForgeApi._call`（`forge_api.dart:193-216`）。
- **分页**：`page`（默认 1）+ `per_page`（默认 20、上限 100）[D]；本应用同两家口径只取第一页。
- **限流**：未认证 60/时（[P] 响应头 `x-ratelimit-limit: 60`，随请求递减）；认证后口径**未核实**（官方文档未见明页，见 R3）。请求量级：列表只在导入对话框内（350ms 防抖），条目状态刷新每 5 分钟一轮（`stash_forge.dart:47`）。
- **User-Agent**：官方 OAuth 文档提示取值令牌时无 UA 可能 403；应用已设 `BaoCode`（`forge_io.dart:12`），无需改动。

### 3.6 令牌作用域建议集（F1 / F4）

作用域名清单以官方 OAuth 文档为准 [O]：`user_info projects pull_requests issues notes keys hook groups gists enterprises`。

本面建议勾 5 个，每个对一处功能：

| 作用域 | 覆盖 |
|---|---|
| `user_info` | `GET /user`（F2 身份） |
| `projects` | 仓库读，含**私有仓**（F4） |
| `issues` | issue 读 + 关闭（F3） |
| `pull_requests` | PR 读（F3） |
| `notes` | 评论（F3） |

文案随实现落 `accountsTokenGiteeScopes`（en/zh 各一条）。私有仓所需作用域的细目未核实（R4，A5 走查确认）。

### 3.7 三家口径文案面（5 键改文 + 2 项同源扩裁）

**依据**：用户 2026-10-16 两次裁定 —— ① 账户页描述补 Gitee（R9）；② 「补gitee」：同口径（真实性与完整性）扩展到仍只提两家的用户可见文案；同源扩裁 2 项同属「补gitee」裁定（设置搜索索引串 · 内置 skill 文本）。**口径**：行为不动；凡陈述支持哪些托管平台的用户可见文案，随家数更新为三家（`GitHub, GitLab or Gitee` / 「GitHub、GitLab 或 Gitee」），句式不动、只改枚举。

**改文清单（5 键 = 已落 1 + 本轮 4）**：

1. `accountsDescription` —— R9 已落；落点 `lib/l10n/app_en.arb:6389` / `app_zh.arb:2409`；用点 `accounts_page.dart:37` / `:45`。
   - en：`Sign in to GitHub, GitLab or Gitee to see the state of the issues and pull requests linked in Stash, import issues as stashes, and reply to them once you confirm.`
   - zh：`登录 GitHub、GitLab 或 Gitee 后，Stash 中链接的 issue 和 PR 会显示最新状态，可以把 issue 导入为 Stash，并在你确认后回帖。`
2. `accountsKeptLocally` —— 本轮；落点 `lib/l10n/app_en.arb:6392` / `app_zh.arb:2412`；用点 `accounts_page.dart:57`。
   - en：`Tokens are kept in this computer's keychain and are sent only to the GitHub, GitLab or Gitee they are for. Nothing is posted without your confirmation.`
   - zh：`令牌只保存在本机钥匙串里，只会发给对应的 GitHub、GitLab 或 Gitee。未经你确认，不会发布任何内容。`
3. `stashImportNotALink` —— 本轮；落点 `lib/l10n/app_en.arb:6575` / `app_zh.arb:2477`；用点 `stash_forge_view.dart:772`。
   - en：`Not a GitHub, GitLab or Gitee issue or pull request link.`
   - zh：`不是 GitHub、GitLab 或 Gitee 的 issue / PR 链接。`
4. `stashImportNoRepos` —— 本轮；落点 `lib/l10n/app_en.arb:6590` / `app_zh.arb:2485`；用点 `stash_forge_view.dart:975`。
   - en：`No project has a GitHub, GitLab or Gitee remote. Paste an issue link above.`
   - zh：`没有项目的 Git 远程在 GitHub、GitLab 或 Gitee 上，可以在上面粘贴 issue 链接。`
5. `stashWelcomeTrack` —— 本轮；落点 `lib/l10n/app_en.arb:6624` / `app_zh.arb:2498`；用点 `stash_welcome.dart:141`。
   - en：`Cards show their conversations live, and the GitHub, GitLab or Gitee issues and pull requests they link to stay in sync.`
   - zh：`卡片上实时显示对话状态，链接的 GitHub、GitLab 或 Gitee issue 和 PR 也会同步状态。`

**同源扩裁（2 项 = 已落；非用户可见文案）**：

1. **`settingsAccountsKeywords`（设置搜索索引串）** —— 落点 `lib/l10n/app_en.arb:6388` / `lib/l10n/app_zh.arb:2408`；两档各补 `Gitee` 一词（en `GitHub GitLab Gitee sign in …` / zh `GitHub GitLab Gitee 登录 …`）。用途：设置搜索输入「Gitee」命中「账号」节；非用户可见文案，不入上列改文清单。
2. **`lib/stash/stash_skill.dart`（内置 skill 文本，产品文本面、非 `.arb`）** —— 落点 `:88`（front matter `issues` 字段说明：`GitHub/GitLab/Gitee`）/ `:98`（卡片链接说明：`GitHub, GitLab or Gitee`）；两处枚举各补 Gitee，句式不动。

**键集口径（实读两档 arb，`github|gitlab` 忽略大小写）**：入列 = 用户可见 ∧ 现文只提两家 ∧ Gitee 链路已可用。stash 面 3 键：2 键在导入对话框（`stashImportNotALink` / `stashImportNoRepos`）、1 键在欢迎页「看清进展」卡（`stashWelcomeTrack`）；`stashImportSignIn` 带 `{forge}` 参数（取 `kind.label`），三家自动成文，不在改文之列。

**落地与校验**：改文 5 键与扩裁① 落 `lib/l10n/app_en.arb` / `app_zh.arb` 两档，`lib/l10n/app_localizations*.dart` 由 `flutter gen-l10n` 重生成（不手改）；落文后 `flutter test test/l10n_test.dart` 须绿（en/zh 键一致 + 非空）。扩裁② 为 `stash_skill.dart` 文本替换，不涉 l10n 键集。同批不动的近邻键（各家主机行 / 作用域文案）见 §8。

---

## 4. 关键决策记录

**D1 `ForgeRef.number` 由 `int` 放宽为 `String`（三家共用，两家行为不变）**

- 事实：Gitee 现行 issue 编号是字母数字字符串 —— 实测 `y_project/RuoYi` `"IKLL6H"`、`mindspore/mindspore` `"IDLSUI"`、`oschina/git-osc` `"IDBSA"`；数字编号路径 404（`/issues/1` ⇒ `{"message":"Issue"}`）。PR 仍旧整数（`597`）[P]。
- 改法：字段类型放宽；GitHub / GitLab 的解析仍走「数字 → int → 串」以保持原行为（含前导零归一）；`tag` / `url` 的拼接不变（Dart 串插值两类型同形）。
- 影响面（核查口径 = 2026-10-16 全仓快照，`lib/**` 与 `test/**` 检索 `\.number\b` + `ForgeRef\(`）：
  - 读点：`forge_ref.dart:106` / `:145`（字段、相等）· `forge_api.dart:254` `:261` `:267` `:376` `:383` `:421` `:425` `:516` `:523`（路径拼接与透传）——全在改动集内；`lib/stash/**` 不读 `number`（同名异型：`StashSort.number`、`_RefKind.number` 非本字段）。
  - 构造点：`forge_ref.dart:172` / `:194`（parse）· `forge_api.dart:258`（转 pull，透传）· `:317` / `:455`（JSON `number` / `iid` 的 int 字面量 ⇒ 改 String）· `test/forge/forge_test.dart:159` `:194` `:219` `:311`（构造字面量）· 既有断言读点 `test/forge/forge_test.dart:60` / `:243`（int 字面量 ⇒ 改 String）。
- 备选（被拒）：① 保持 `int`、只支持数字编号 —— Gitee 现行 issue 几乎全为字符串编号 ⇒ F3 的 issue 面不可用；② 旁路加 `String id` 字段 —— 同物两形（number / id），相等、展示与 API 路径三处分裂。

**D2 主机与链接形态**（做法见 §3.3）

- 备选（被拒）：把 Gitee 链接按 GitLab 的 `/-/` 形兼容 —— Gitee 页面无此形（实测 issue 页为 `/issues/{id}`），凭空兼容无来源。

**D3 列表归属过滤用 `assignee=<login>` / `creator=<login>`**

- Gitee 参数取 username，无 `@me`（[D] 全文无 `@me`）⇒ `GiteeApi.issues` 仅 `filter ≠ all` 时先 `me()` 取 `login`，该实例内只取一次（`filter = all` 不发 `/user`）。
- `me()` 失败（令牌失效 401 等）⇒ `ForgeException` 直接传播：列表调用面已有 catch 与报错行（`stash_forge_view.dart:751-757` 落 `_listError`，`:993` 渲染），不降级为静默空列表。
- 备选（被拒）：官方 MCP 客户端用的 `filter=assigned` [M] —— 未见于 [D] 的仓库级端点参数，属未核实形态；`me()` 的代价只落在列表路径（低频），可接受。
- 实测注记：无令牌时 `assignee=` 被服务端忽略（同样输入返回未过滤结果）、`creator=` 生效 ⇒ `assignee` 的有效性只能带令牌验（R2，A5）。

**D4 issues 列表口径 = 未关闭（两次请求合并）**

- 事实：Gitee 的 `state=open` **不含** `progressing`（进行中）—— [P] 实测 mindspore：`state=open` 前 100 条全为 `open`，而 `state=all` 前 100 条含 4 条 `progressing`，其中 9 条 progressing 的创建时间晚于 open 列表最旧一条（本应入列而未入）；该仓 `state=progressing` 共 27 条。
- 做法：并发两请求 `state=open` + `state=progressing`（各 `per_page=50`、`sort=updated&direction=desc`），按 `updated` 合并取前 50；口径 = 未关闭，与两家一致（GitHub `is:open`、GitLab `state=opened`）。
- 备选（被拒）：① 只取 `state=open` —— 漏「进行中」（实测 mindspore 27 条）；② `state=all` + 客户端过滤 —— 翻页窗口被已关闭项挤占，活跃仓上未关闭项会被挤出首页。

**D5 关闭 issue 走命名空间级端点**

- [D]：`PATCH /repos/{owner}/issues/{number}`，参数 `repo` + `state=closed`；[M] 官方客户端同形（JSON 载荷）。与两家的 repo 级路径不同形。
- 写入路径无法无令牌实测（鉴权先于路由：任意路径 + 伪令牌一律 401，见 R1）⇒ 以 [D] + [M] 为准，A5 首验。
- 调用面仅 issue：`stash_forge.dart:302` 已判 `ref.kind == ForgeItemKind.issue` 才关（与 GitLab 现状同前提）。

**D6 Gitee 无 checks 面**：`ForgeItem.checks` 恒 null —— [D] 无对应端点；UI 不显示、不假装（B2）。

---

## 5. 受影响文件清单（行数 = 编制日快照 → 实施后实测，2026-10-16）

| 文件 | 行数 | 改动 |
|---|---|---|
| `lib/forge/forge_ref.dart` | 220 → 271 | `ForgeKind.gitee`（label / publicHost）· `publicForgeKind` · `fromRemote` 两段规约 · `parse` 加 Gitee 臂 + `/-/` 闸门收紧 · `number` 类型放宽 |
| `lib/forge/forge_api.dart` | 527 → 707 | 新 `GiteeApi`（`/api/v5`、Bearer）；两处 `number` 构造改字面量（`:317` / `:455`） |
| `lib/forge/forge_accounts.dart` | 439 → 450 | 三处 switch 加 gitee 臂（`apiFor` `:213-224`、`_signIn` `:281-284`、`canSignInFromBrowser` `:199-204`）；设备流两处 switch 加不可达臂（`:326-343`、`:389-404`） |
| `lib/forge/forge_view.dart` | 120 → 132 | `ForgeLogo` 加 gitee 臂 |
| `lib/settings/pages/accounts_page.dart` | 495 → 503 | 主机文案臂 · `forgeNewTokenPage` / `forgeRevokePage` 加 gitee 臂 · 作用域文案臂 |
| `assets/branding/gitee.svg` | 新（约 1.5 KB） | 官方 logo 的单色 G 字形（来源与形态见 §3.4 图标行）；资产已按目录声明（`pubspec.yaml:106` `assets/branding/`）⇒ `pubspec.yaml` 无须改 |
| `lib/l10n/app_en.arb` / `lib/l10n/app_zh.arb` | 6638 / 2505 → 6639 / 2506 | 各 +2 键（`accountsGiteeHosts`、`accountsTokenGiteeScopes`）+ 5 键改文 + 扩裁① `settingsAccountsKeywords` 补词（清单见 §3.7：R9 已落 1 键 + 本轮 4 键） |
| `lib/l10n/app_localizations*.dart` | 生成物（3 文件） | 由 `flutter gen-l10n` 重生成，不手改 |
| `lib/stash/stash_skill.dart` | 117 | 内置 skill 文本枚举补 Gitee（`:88` front matter `issues` 说明 · `:98` 卡片链接说明；扩裁②，见 §3.7；文本替换、行数不变） |
| `test/forge/forge_test.dart` | 518 → 475（拆包后） | 既有用例（ForgeRef / GitHubApi / GitLabApi / ForgeAccounts）留本档；既有断言（`:60` / `:243`）与构造字面量（`:159` `:194` `:219` `:311`）改 String（共 6 处）；Gitee 用例 G1–G15 落新档（实测 899 越 800 硬顶 ⇒ 触发拆包，见体量条） |
| `test/forge/forge_gitee_test.dart` | 新 → 452 | Gitee 用例 G1–G15（三组：`Gitee links` / `GiteeApi` / `Gitee account`） |
| `test/forge/fake_forge_http.dart` | 新 → 46 | 共用 `FakeForgeHttp`（拆包时自 `test/forge/forge_test.dart` 抽出；清单外新增，交付实测补录）；Dart import 不传递 ⇒ 六处消费者（两档 forge 单测 + 下列 4 档）各 1 行改指本档 |
| `test/stash/stash_forge_test.dart` | 182 | 1 行 import 改指 `test/forge/fake_forge_http.dart`（`:14`）—— 拆包连带（清单外，交付实测补录） |
| `test/stash/stash_forge_view_test.dart` | 241 | 同上（`:15`）—— 拆包连带 |
| `test/stash/stash_sidebar_test.dart` | 224 | 同上（`:22`）—— 拆包连带 |
| `test/settings/accounts_page_test.dart` | 130 | 同上（`:9`）—— 拆包连带 |

**测试覆盖**：单元用例两档 —— 既有用例留 `test/forge/forge_test.dart`（475 行，本项目既有 forge 单测所在，形态照两个 group）；Gitee 用例 G1–G15 落 `test/forge/forge_gitee_test.dart`（452 行；实测 899 越 800 硬顶 ⇒ 触发拆包，见体量条）；共用 fake 抽 `test/forge/fake_forge_http.dart`（46 行，六处消费者改指）。

命令 = `flutter test test/forge/forge_test.dart test/forge/forge_gitee_test.dart`（两档同跑）。`test/stash/*`、`test/settings/accounts_page_test.dart`、`test/l10n_test.dart` 不新增用例，须保持绿（其中 4 档各 1 行 import 改指，见文件表）。

**体量与拆包**（>800 行 = 硬顶；>500 行 = 主动拆分审阅带，逐档给结论）：

- `forge_api.dart` 527 → 707（>500、<800）⇒ **保留**（本批只追加 `GiteeApi` 一类，不动两家）；缝候选 = 按 kind 拆 `forge_api_github.dart` / `forge_api_gitlab.dart` / `forge_api_gitee.dart`；触发 = 越 800 硬顶。
- `accounts_page.dart` 495 → 503（本次跨过 500）⇒ **保留**（三处 switch 加臂 + 一行描述文案，不动结构）；缝候选 = 令牌路径段（`:199`）/ 浏览器设备流段（`:351`）两个段头；触发 = 越 800 硬顶或该档再落新功能面。
- `test/forge/forge_test.dart` + `test/forge/forge_gitee_test.dart`：拆包前实测 899（2026-10-16）**越 800 硬顶 ⇒ 触发成立、已按缝拆包** —— 既有用例（ForgeRef / GitHubApi / GitLabApi / ForgeAccounts）留 `test/forge/forge_test.dart`（475 行）、Gitee 用例 G1–G15 落新档 `test/forge/forge_gitee_test.dart`（452 行）；两档均 <500、<800。
- 无新增 >800 行文件；`forge_ref.dart`（271 行）、`forge_accounts.dart`（450 行）、`forge_view.dart`（132 行）、`fake_forge_http.dart`（46 行）均在 500 行以内。

---

## 6. 验收对照（回指需求档 §5）

| 需求 | 判据（机检 / 走查） |
|---|---|
| A1 登录 | 令牌登录可完成、无效令牌有明确报错 —— 单元：`signInWithToken(gitee, 'gitee.com', 't')` 打 `GET https://gitee.com/api/v5/user`，401 时抛 `ForgeException.unauthorized` 且不落库；走查：账户页 Gitee 行 → 令牌对话框 → 真实令牌登录成功 |
| A2 身份与读 | 身份显示正确、公开仓与私有仓条目可读 —— 单元：Issue / PR 两形解析（§7 G5–G8）、列表归属与失败路径（G9）；走查：公开仓与私有仓各一条 issue / PR 链接，状态正确；令牌失效时列表显示报错行（不静默空表） |
| A3 协作 | 评论 / 关闭在有权限时可用 —— 单元：请求方法与路径断言（G11、G12）；走查：真实令牌评论 + 关闭一条 issue |
| A4 零回退 | github / gitlab 用例与行为不回退 —— `flutter test test/forge/forge_test.dart test/forge/forge_gitee_test.dart` 两档同跑全绿（既有 group 只改字面量，不改语义；Gitee 用例 G1–G15（含 G15 `/-/` 闸门回归）落 `test/forge/forge_gitee_test.dart`） |
| A5 真机走查 | 真实 Gitee 令牌走 A1–A3，并看图标与作用域文案外观；回填 §9 未核实项 |

---

## 7. 用例表

（单元用例；输入 → 期望）

| # | 场景 | 输入 | 期望 |
|---|---|---|---|
| G1 | 链接解析·issue | `https://gitee.com/o/r/issues/IKLL6H` | kind = gitee，number `'IKLL6H'`，`url` 回形同址 |
| G2 | 链接解析·PR | `https://gitee.com/o/r/pulls/597/files` | number `'597'`，`url` = `https://gitee.com/o/r/pulls/597` |
| G3 | 解析边界 | `https://gitee.com/o/r/-/issues/1`；`https://gitee.com/o/r/issues/IKLL6H#note_1` | 前者 null；后者解析成功（锚点忽略） |
| G4 | 主机与远程 | `git@gitee.com:o/r.git`；`https://gitlab.com/g/s/app.git` | 前者 gitee / `o/r`；后者仍 gitlab / `g/s/app` |
| G5 | 身份 | `GET /user` → `{login,name}` | `ForgeUser`；请求头 `Authorization: Bearer t` |
| G6 | issue 详情 | `number:"IKLL6H"`、`state:"progressing"`、`assignee:{login}`、`labels:[{name,color:"fd6206"}]`、`comments:2` | state = open；assignees 取 login；label color `#fd6206`；checks = null |
| G7 | issue 详情·rejected | `state:"rejected"` | state = closed |
| G8 | PR 详情 | `state:"merged"` + `merged_at`；另例 `draft:true`；`head:{ref}` | merged / draft / branch 三处正确；checks = null |
| G9 | 列表·归属 | filter = assigned / created / all；`/user` 正常与 401 两形 | 查询串 `assignee=<login>` / `creator=<login>` / 两者皆无；`state=open` 与 `state=progressing` 两请求合并、按 updated 取前 50；`me()` 仅 filter ≠ all 时请求（all 时无 `/user`）；`/user` 401 ⇒ 抛 `ForgeException.unauthorized` 且不发列表请求 |
| G10 | 列表·搜索 | `query:'upload'` | 查询串 `q=upload` |
| G11 | 评论分路 | issue ref / pull ref + body | `POST …/issues/IKLL6H/comments` / `POST …/pulls/597/comments`，JSON `{body}` |
| G12 | 关闭 | issue ref | `PATCH /repos/{owner}/issues/IKLL6H`，JSON `{repo, state:'closed'}` |
| G13 | 错误面 | 401 `{"message":"401 Unauthorized: …"}` | `ForgeException.unauthorized`，message 取 `message` |
| G14 | 空能力 | PR 详情 | 不发任何 checks 请求；`checks == null` |
| G15 | `/-/` 闸门回归（零回退） | `https://gitlab.com/o/r/-/issues/1`；`https://github.com/o/r/-/issues/1` | 前者仍解析为 gitlab issue `1`；后者 null（github 主机不走 `/-/` 臂）——两条在闸门收紧前后结果相同 |

---

## 8. 边界（本批不做）

- **B1** 不做 Gitee 浏览器 / 设备码登录：Gitee 无设备码流（[O] 只有授权码与密码两式），OAuth 需注册应用 ⇒ 仅令牌登录；设备流 switch 的 gitee 臂不可达，抛 `ForgeException` 兜底，账户页不显示浏览器按钮。
- **B2** 不做无对应面：checks 不显示（D6）；不在本批做创建 issue、PR 合并 / 关闭 / review、labels 与里程碑增删。
- **B3** 不改既有两家行为：github / gitlab 的入口、路径与行为不动（`ForgeRef.number` 类型放宽是行为不变改动，D1）；**提及托管家数的用户可见文案随第三家更新** —— 清单见 §3.7（用户 2026-10-16 两次裁定：其一，账户页描述补 Gitee（R9）；其二，「补gitee」扩裁至同口径文案）。
- 不承诺自建 Gitee（私有化部署）的 API 路径：host 可手填，但只承诺 `gitee.com` 及其 `/api/v5`。
- 同批不动的近邻文案（各自只描述本家，非「家数」陈述）：`accountsGitHubHosts` · `accountsGitLabHosts` · `accountsTokenGitHubScopes` · `accountsTokenGitLabScopes`；`settingsAccountsKeywords` 为设置搜索索引串（非用户可见文案）—— 已裁定：补一词（见 §3.7 扩裁①）。

---

## 9. 风险与未核实清单

| # | 项 | 现状 | 处置 |
|---|---|---|---|
| R1 | 关闭 issue 的写路径 | [D] + [M] 一致（命名空间级）；无令牌无法实测（鉴权先于路由：伪令牌任意路径一律 401） | A5 首验；不通过则记回本档并核对 `access_token` 参数形态（R5） |
| R2 | `assignee=<login>` 是否真过滤 | 无令牌时被忽略（同输入的 `creator=` 生效） | A5：assigned 过滤下有 / 无指派两样本对照 |
| R3 | 认证后限流口径 | 未核实（官方文档未见明页）；未认证 60/时（实测响应头） | A5 观察 403 / 429；若吃紧，改装 `filter=` [M] 形态或加缓存 |
| R4 | 私有仓所需作用域细目 | 未核实（[O] 只列名不释义） | A5：私有仓读不到时核对勾选（建议集见 §3.6） |
| R5 | 令牌走 `access_token` 参数（兜底形态） | 未核实（各端点 [D] 都列该参数；本设计走 Bearer 头） | 仅在 Bearer 不通过时启用；以 A5 为准 |
| R6 | `www.gitee.com` | 实测 302 → gitee.com | 已按实测纳入（与两家同形） |
| R7 | 图标观感 | 资产取自官方 logo 的单色形 | A5 看 16px 辨识度；不清晰则换「圆 + G 挖空」形 |
| R8 | 私人令牌页是否接受预填参数 | 未核实（需登录） | 本批不带参数；A5 若发现可预填，另开一轮 |
| R9 | 账户页描述只提两家 | 已裁定：随第三家更新（用户 2026-10-16；「补gitee」扩裁至同口径文案） | 已落：`accountsDescription`（§5 实施）；扩裁 4 键的新文与落点见 §3.7，`.arb` 由后续实施轮落 |
| R10 | PR 详情 `comments` 数是否恒缺 | 两次探针（`y_project/RuoYi` PR 597、`mindspore/mindspore` PR 1）均无 `comments` 键；样本 PR 无评论，不能定论 | A5：取一条**有评论**的 PR 核对；有该字段 ⇒ 改读它（§3.2 行内改）；确认恒缺 ⇒ 保持显示 0 并回填 |

**实测留痕（[P]，2026-10-16，无令牌公开读）**：

- `GET /api/v5/repos/mindspore/mindspore/issues?state=open&per_page=100` ⇒ 100 条全 `open`；`?state=progressing` ⇒ 27 条；`?state=all` ⇒ 100 条含 4 条 `progressing`。
- `GET /api/v5/repos/y_project/RuoYi/issues/IKLL6H` ⇒ 200（`number:"IKLL6H"`）；`/issues/1` ⇒ 404 `{"message":"Issue"}`。
- `GET /api/v5/repos/y_project/RuoYi/pulls/597` ⇒ 200（`number:597`、`head` 为对象、无 `comments` 键）。
- `GET /api/v5/repos/mindspore/mindspore/pulls/1` ⇒ 200（同样无 `comments` 键；其 `pulls/1/comments` 为空 ⇒ 非反例，R10）。
- `GET /api/v5/user`：无令牌 ⇒ `{"message":"登录失效，无权限访问该资源","code":40001}`；`Authorization: Bearer bogus` ⇒ 401 `{"message":"401 Unauthorized: Access token does not exist"}`。
- 限流头：`x-ratelimit-limit: 60`（未认证）。
- `GET https://gitee.com/profile/personal_access_tokens` ⇒ 307 → `/login?redirect_to_url=/profile/personal_access_tokens`；`https://www.gitee.com/` ⇒ 302 → `https://gitee.com/`。

