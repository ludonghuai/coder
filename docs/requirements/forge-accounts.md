# 账户与代码托管（forge）需求档

> 状态：已确认（用户 2026-10-16 会话裁定：令牌登录 · 功能面对齐 · 私有仓支持）
> 日期：2026-10-16
> 范围仓：baocode（本仓）。
> 首篇：Gitee 接入（现有 GitHub / GitLab 之外的第三个 forge）。

## 1. 模块目标

账户页（设置 → 账号）与 forge 模块承载多代码托管平台的身份与协作面：以令牌登录平台，
读条目（issue / PR）· 列 issues · 评论 · 关闭。

本档首篇要解决：**在既有两家的基础上接入 Gitee**——与 github / gitlab 同口径（令牌登录、同功能面），
私有仓一并支持。

## 2. 事实基线（已核实；设计前提）

- forge 抽象：`lib/forge/forge_ref.dart`——`ForgeKind` 现为 github / gitlab（`:7`），主机解析 `publicForgeKind`（`:34-35`）；
  `lib/forge/forge_api.dart`——`GitHubApi`（`:227` 起）/ `GitLabApi`（`:393` 起），面 = `me` / `item` / `issues` / `comment` / `close`（GitHub 另带 checks）；
  `lib/forge/forge_accounts.dart`——按 kind 的 API 构造、端点、作用域、令牌交换；
  `lib/forge/forge_view.dart`——per-kind 图标。
- 账户页：`lib/settings/pages/accounts_page.dart`——按 kind 的主机表（`:59-64`）、令牌创建 URL（`:147-165`）、
  建令牌 URL 构造（含作用域，`:167-173`）、令牌登录组件（`:199` 起）、作用域文案（`:322-323`）。
- 既有两家均支持私有仓（令牌带对应作用域即可）。

## 3. 功能点

**F1 令牌登录**：账户页新增 Gitee 区块——粘贴个人令牌即登录（与两家令牌路径同形）；
建令牌链接指向 Gitee 个人令牌页，附所需作用域文案。

**F2 身份**：登录后显示 Gitee 账户身份（`me`）。

**F3 协作面**：条目详情（issue / PR）· issues 列表 · 评论 · 关闭——与两家同口径。
GitHub 的 checks 面 Gitee 无对应 ⇒ 不显示（空能力不假装）。

**F4 私有仓**：支持（同两家口径）。

**F5 链接与图标**：`gitee.com` 链接识别（`forge_ref` 解析）与 per-kind 图标，同两家形。

## 4. 边界（明确不做）

**B1 不做浏览器 / 设备码登录**：Gitee 第三方 OAuth 需注册应用，成本不成比例 ⇒ 仅令牌登录（用户裁定 2026-10-16）。
**B2 不做无对应面的能力**：checks / Actions 等 GitHub 专有面不显示、不假装。
**B3 不改既有两家行为**：github / gitlab 链路不动；**提及托管家数的用户可见文案随第三家更新**（用户 2026-10-16 两次裁定：R9 描述行 + 「补gitee」扩裁——清单 = 设计档 `docs/design/forge-accounts.md` §3.7：5 键改文 + 2 项同源扩裁）。

## 5. 验收

- **A1 登录**：账户页可完成 Gitee 令牌登录；无效令牌有明确报错。
- **A2 身份与读**：身份显示正确；公开仓与私有仓的条目可读。
- **A3 协作**：评论 / 关闭在有权限时可用。
- **A4 零回退**：既有 github / gitlab 测试与行为不回退。
- **A5 真机走查**：用真实 Gitee 令牌走一遍 A1–A3。

## 6. 依赖

- **D1** Gitee API v5（`/api/v5/…`）——端点与字段逐一对位在**设计档**完成（本档不预写未核实的端点）。
- **D2** 既有 forge 模块（只增不改语义）。
