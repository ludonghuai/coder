# 2026-10-20 · 自动拉取只在 IDE 视图打开时跑（引擎所有权上移）
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-20 · 来源 = 用户 2026-10-20 20:33 走查：「只开 baocode 没法拉远端，除非打开其它编辑器；刚启动也没搜」。
> 台账 = #115（ide-git · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

**条目**：#115 自动拉取只在 IDE 视图打开时跑（chat-only 布局零启动）。

**披露（轻渠道 · 缺陷修）**：本笔 = 轻渠道（实现与设计 §12.4「自动轮按周期跑」相抵）｜改动：引擎所有权从 `IdeWorkbench` 上移到常驻的主 `_WorkbenchState`（`workbench.dart`），repo 源 = IDE 空间（开时）+ 侧栏仓源（未开时），`documents` / `reload` / `paths` 由主 workbench 组合；IDE 侧实例删除（`ide_workbench.dart` 净删 40 行）｜触达：自动拉取的所属组件、冷启动的首次仓库发现｜回滚 = 还原两档（引擎回 IDE）。

**根因（实测）**：`IdeGitAutoFetch` 只在 `IdeWorkbench.initState` 创建（原 `:4785`）；chat-only 布局下 IDE 工作台从不构建 ⇒ 引擎从不 `start`（探针实测：重启后日志无 `[af] start`）。侧栏的 Git 页能列仓（自己扫），但没人按周期 fetch。

**改后读数（同一台机，chat-only 布局）**：
- 探针：`[af] start enabled=true` → 一次 `[af] empty`（项目尚未加载）→ 随后 30 条 `[af] round <root> busy=false`（15 个仓）
- **行为读数**：`repos\api` / `repos\docs` / `repos\video` 的 `.git/FETCH_HEAD` 全部刷新到 `20:47:51`——**没有打开任何其它编辑器**
- `flutter analyze`（git 面 + 两档）No issues；`test/ide/git` 全绿；`side_panel_workspace_test` 的 5 红 = #109 已知 Windows 平台红（逐名核对，非本笔）
- 探针已移除（引擎档回 HEAD）

**观察**：引擎随活动线程的项目走，单仓项目会按 `git.autoRepositoryDetection` 覆盖其子仓（本例 15 个）——与 Source Control 同口径，非新行为。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
