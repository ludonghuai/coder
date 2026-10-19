# 2026-10-18 · public-docs
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-18 · 来源 = 用户 2026-10-18 23:13「a+b」（README 更新范围 A+B）。
> 台账 = #75（docs · 归批）。前情 = 无（独立轻渠道轮）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-18 · 轻渠道轮）

### 轻渠道披露

**本轮 = 轻渠道**（细节面 · 对外文案）| change = app README（EN/CN）同步 ThinCoder 内核 + 宿主工具通道 + 模型菜单分组 | reach = 两份 README 的定位 / 功能 / 系统要求段；代码零改；JA/FR/ES 翻译与 release-notes 不在本轮 | rollback = revertable。

### 来源与范围

- 用户 2026-10-18 23:13「a+b」：A = Gitee 首页 `thincoder/README.md`（thincoder 仓独立轮，台账 #6）；B = 本仓 `README.md` / `README_CN.md`；C（发布说明）不做。
- 事实依据：内核注册表 = `claude-code` + `thincoder`（`lib/kernel/kernel_registry.dart:13` / `:32`）；宿主通道 = thincoder 会话可经环回 MCP 用 app 的浏览器工具（宿主批 §6，2026-10-18 实测 A1–A3）；模型菜单按供应商分组（轻渠道轮 #70）。
- 改动：① 标题 / 定位句（Claude Code 与 ThinCoder）；② Why 段（不实现 agent、运行 Claude Code 或 ThinCoder、浏览器工具经宿主通道）；③ 功能列表加「双内核」；④ 系统要求加 ThinCoder 可选（`npm i -g thincoder` / `thincoder.path`）。
- 验证：改后回读；两档行宽人工核（README 不在 `docs` scanDirs）；不跑代码测试（零代码改动）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
