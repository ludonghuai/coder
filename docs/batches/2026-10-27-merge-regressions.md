# 2026-10-26 · merge-regressions
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 23:50「现在做」；来源 = kimi 合并审查（explore#24）查出的 6 组静默丢失，父侧已 grep 核实其中 4 组。
> 台账 = #190（thincoder-adapter · 归批）。前情 = docs/batches/2026-10-27-fork-realign.md §1（2026-10-26 文档前置）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 本批：修合并静默丢失的 6 组行为（2026-10-26 23:50）

- **已定决定**：走轻量通道（缺陷修复，源 = `main`/`26c969aa` 上的原实现 + 需求档/设计档要求），父侧直改，逐项验证后单笔提交 · 用户原话：「现在做」 · 时间：2026-10-26 23:50

**来源**：kimi 合并审查（explore#24）。父侧已 grep 核实 ①③④⑤⑥ 五组，②（命令面板 Rename Agent）待核。

| # | 丢失的行为 | 现状证据（父侧实读） | 源（要恢复成什么） | kimi 建议 |
|---|---|---|---|---|
| 1 | 在飞回合选模型后，pill/tooltip 显示「回合结束后切换到 X」 | `session_model_picker.dart` 内 `pendingModel` **零命中** | `main:session_model_picker.dart` 的 `_nameOf` + label/tooltip 后缀 | 恢复 label 后缀、tooltip 与目标名查找 |
| 2 | 命令面板可搜索并执行 Rename Agent | 待核（`workbench.dart:1287-1307` 只读窗口命令） | `main:workbench.dart` 的 `_paletteActions` 合并聊天命令源 | 恢复 `ChatKeys.targetsOf → commandsOf` 命令源与面板项 |
| 3 | 侧栏仓库扫描失败后 30 秒重试 + 日志 + 提示一次 | `workbench.dart` 内 `_sidePanelRetry` / `scmScanFailed` **零命中** | `main:workbench.dart` 的 `_sidePanelRetryAt` / `_sidePanelRetryTimer` / `_scanWarned`；设计 `docs/design/ide-git.md:237-241` 有明文要求 | 恢复重试、日志与一次性提示 |
| 4 | chord 第二键只在持有前缀的当前窗口生效 | `ide_workbench.dart:3357-3365` 不检查窗口；`:3377-3381` 只检查应用生命周期 | `main:ide_workbench.dart` 的 `_onChordKey` + `_holdsKeys` 守卫 | 接回焦点/路由守卫，**不整段回退上游按键实现** |
| 5 | 文档关闭 / diff 重建时，空控制器不崩 | `ide_editor.dart` 三处 `_nativeController!`（`:1964` / `:2639` / `:2653`） | 既有修复 `docs/batches/2026-10-17-ide-stability-guards.md:45`：控制器为 null 时返回 `SizedBox.expand` | 恢复局部 controller + null 守卫 |
| 6 | 回退文件后，变更审查列表立即刷新 | `chat_session.dart` 内 `ChangesReverted` **零命中** | `main:chat_session.dart` 的 `_reviewEvent` 里 `ChangesReverted → review.observe()`；`change_review.dart:401-402` 的语义 | 恢复该事件分支 |

**红线**：只恢复这 6 组行为，不改上游结构、不动 SCM 语义（#181 已裁定接受上游）、不动 autofetch（#184 另批删）。每项一条提交或一组提交，便于单笔回退。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
