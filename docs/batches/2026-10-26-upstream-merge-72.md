# 2026-10-26 · upstream-merge-72
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-26 · 来源 = 用户 2026-10-26 08:21「先小修，然后合并上游」；小修批已于 09:00 收口，本批为其后继。分叉现状：领先 144 / 落后 72，merge-tree 试算 16 档冲突。。
> 台账 = #181（thincoder-adapter · 归批）。前情 = docs/batches/2026-10-26-small-fixes.md §6（已收口 2026-10-26）。
## §1 讨论（主 agent）
**状态行**：🔄 进行中（…）
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

### 讨论与策略（主 agent，2026-10-26 09:05，用户休息中，仅摆材料不动代码）

**用户原话**：「兼容的话会不会更好兼容上下游的更新了呢」「我之前将两者融合的太脏了」「先小修，然后合并上游」「kimi做完之后，让kimi来做接下来的任务落实吧」。

**现状读数**（父侧实跑）：`HEAD` 领先上游 144 / 落后 72；`git merge-tree --write-tree HEAD origin/main` 试算 **16 档冲突**；上一批记着 10-22（28 提交撞 13 处）与 10-26（6 提交撞 11 档后 abort）——**撞的总是同一批文件**。

**两份独立咨询，结论一致 = A（上游优先），且都要求「严格形态」**

| 来源 | 结论 | 独有论据 |
|---|---|---|
| deepseek-flash（#49，因 kimi 429 降级） | A | 冲突面与价值面错位：自有资产（thincoder 27 档 / btest 9 档 / session 8 档 / 三个看门狗 / 进程代理）**在 16 档冲突里一次都没出现**；冲突档内属我们的只有数百行 UI/接缝 |
| kimi（#50，k3.1-pro） | A | **这条原则需求档早已写明**：`docs/requirements/thincoder-adapter.md:197-207` 要求「thincoder 代码集中于独立模块，宿主既有文件只留可辨认的接线点」；并指出 `lib/chat/session/mode_state.dart:1` 仍是 `part of '../chat_session.dart'` ⇒ **拆 part 文件不等于隔离** |

**必须遵守的四条（两位共同点 + kimi 的补强）**
1. **不是 `--theirs` 一键了事**：共享档整档取上游，自有功能在**新的独立模块**里重接；`lib/kernel/thincoder/**`、`lib/browser/btest/**`、`lib/diagnostics/**`、`lib/platform/process_host*.dart` **绝不整档取上游**。
2. **l10n 只并集源档**（`app_en.arb` / `app_zh.arb`），生成档用 `flutter gen-l10n` 重生成，不手解冲突、不选边。
3. **测试归属分离**：上游的两个 SCM 测试档保持上游版；自有断言另建功能测试档（如 `scm_fetch_button_test.dart` / `git_autofetch_test.dart`）。
4. **落一张登记表**（flash 强调「没有这张表，A 两三次合并后会退化回 B」）：`docs/design/fork-deltas.md`，表 = 文件 / 我们的块 / 类型（修 bug · 功能 · 内核适配）/ 接缝 / 行数预算；规则 = 表外不许改上游档。**该档属设计面，由 eng-designer 写。**

**阻塞项（用户裁定前不得动 SCM 面）**：#181「获取 = fetch + merge」（2026-10-19 用户定）与上游 Fetch/Pull 分开的取舍。已入台账（条件触发），待裁。

**下一步（用户醒来后按序）**：① 裁定 #181 → ② 派 eng-designer 写 §2 任务书 + `fork-deltas.md` 框架 → ③ 用户发设计评审 → ④ 批准 → ⑤ 实施轮派 kimi（`kimi-code:k3.1-pro`；429 则降级 flash 并在此记录）。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
