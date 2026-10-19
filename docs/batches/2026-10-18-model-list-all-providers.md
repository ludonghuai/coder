# 2026-10-18 · model-list-all-providers
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-10-18 · 来源 = 用户 2026-10-18 20:38「要改拉取所有模型」。
> 台账 = #66（thincoder-adapter · 归批）。前情 = 无（独立轮）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-10-18
<§1 模板占位：本批条目 / 关键判据 / 授权口径>

## 讨论与定界（2026-10-18 · 轻渠道轮）

### 来源与性质

- 用户 2026-10-18 20:38「要改拉取所有模型」——指 thincoder 会话的模型选择器只显示当前渠道的模型，要求与终端 `/model` 一样列出所有渠道。
- 性质 = **缺陷修复**（实现偏离已确认设计 F14/§17.3），不是新功能：设计档 §17.3-① 写的是「清单来源 = agent.config.providers……各渠道并发拉」，实现只拉了 `agent.provider`。走轻渠道（缺陷修复），不新开设计。

### 根因（实读）

- `thincoder-cli/src/acp/handlers-session.mjs:91-103` 的 `refreshModelChoices`：`const provider = agent?.provider`，只对**当前渠道**调 `getProviderModels` ⇒ 其它渠道的模型永不进 `configOptions.model.options[]`。
- 终端侧：`tui/model-picker.mjs:115` / `:271` 遍历 `agent.providers`（全量），按 `isDerivedProviderHidden`（`tui/provider-admin.mjs:26`）过滤派生无 key 渠道。
- 来源事实：核装配 `thincoder-core/agent/assemble.mjs:106-107` 对所有端都设 `agent.providers`（ACP 路径同经该装配）⇒ 设计档 §17.3 的「ACP 装配不设它」一句错误，随本轮更正。

### 改动面

- `thincoder/thincoder-cli/src/acp/handlers-session.mjs`：`refreshModelChoices` 改为遍历 `agent.providers`（过滤 `isDerivedProviderHidden`）→ 并发拉取 → 合并去重 → 保留当前 `provider:model` → 推一次 `config_option_update`；单渠道失败只记日志、不挡其它渠道。
- `thincoder/docs/batches/2026-10-18-model-list-all-providers.test.mjs`（新增，批内单测档，零留存）：多 provider 合并 / 单渠道失败 / 派生隐藏渠道不发请求 / 当前值保留。
- `docs/design/thincoder-adapter.md:1167`：单句更正 provider 来源（父侧小改，已标记）。
- 桌面侧零改动（`thincoder_events.dart` 已渲染 `options[]`）；不动 `thincoder-cli` 其它文件、不动浏览器通道。

### 验证与回滚

- 验证 = `node docs/batches/2026-10-18-model-list-all-providers.test.mjs`（本地假 `/models` 服务，零外网）+ `npm run lint`（`thincoder-cli`）。
- 回滚 = 还原 `handlers-session.mjs` 单档 + 删除本轮测试档；桌面与协议零影响。

### 轻渠道披露

**本轮 = 轻渠道**（缺陷修复）| change = `refreshModelChoices` 全渠道清单 + 设计档单句更正 | reach = thincoder CLI 模型清单投影，桌面零改动 | rollback = revertable。

### 落点与读数（2026-10-18 · 轻渠道轮）

- 代码：`thincoder/thincoder-cli/src/acp/handlers-session.mjs`——`refreshModelChoices` 改为遍历 `agent.providers`（过滤 `isDerivedProviderHidden`）→ 并发拉取 → 合并去重 → 保当前 `provider:model` → 推一次 `config_option_update`；单渠道失败只记日志。新增 import 一行。
- 设计档：`docs/design/thincoder-adapter.md:1167` 单句更正（父侧小改，已标记；provider 来源改为 `agent.providers`，核装配坐标 `thincoder-core/agent/assemble.mjs:106-107`）。
- 测试：`thincoder/docs/batches/2026-10-18-model-list-all-providers.test.mjs` → **2/2 passed**（全渠道投影 / 单渠道失败不挡其它 + 当前值保留 / 派生无 key 渠道不发请求）。
- Lint：`thincoder-cli` 的 `npm run lint` → **127 files OK**。
- `git status`（thincoder 仓）：本轮只新增/修改 `thincoder-cli/src/acp/handlers-session.mjs` 与 `docs/batches/2026-10-18-model-list-all-providers.test.mjs`；另两档 `docs/cli/**` 为本轮前既有改动。
- 未做：真机走查（app 当前跑的是已安装的 thincoder CLI，不是本地源码；需把 `thincoder.path` 指向本地构建或安装更新后的 CLI 才能看到全量模型）；收口链未跑（批次档与台账 #66 保持 open）。

### 独立代码评审（2026-10-18 · 第 1 轮）与修复

- VERDICT **changes-required**：🔴 候选面全渠道后，`applyConfigOption` 的 model 支只改 `agent.provider.name` / `.model` ⇒ `baseURL` / `apiKey` / `format` 留在旧渠道，跨渠道选中会静默错路由；`activeProvider` / `activeModel` 不同拍 ⇒ 落盘 / 恢复丢选择。🟡 批档指针跨仓（宿主档存在，评审在 thincoder 路径下解析不到）。🔵 写入面用例缺失 / 5s 定时器未清 / 链尾无 catch / baseURL 过滤未注释。
- 修复（全采纳）：`applyConfigOption` model 支整对象换（`agent.provider = { ...target }`）+ 同拍写 `activeProvider` / `activeModel` + `compactThresholdAuto` 时重算阈值；未知渠道 `false`；刷新链尾补 `.catch`；baseURL 过滤注释；测试补跨渠道选择与未知渠道拒、定时器清理；`thincoder/docs/cli/design/ACP-CLIENT.md` §5.3 同步；新增 `thincoder/docs/batches/2026-10-18-model-list-all-providers.md`（本仓自包含记录）。
- 读数：批内单测 **3/3 passed**（35ms，无 5s 挂尾）；`npm run lint` **127 files OK**。
- 待：第 2 轮复评验证修复；通过后落 §6 结算。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）

## 验证与收口（2026-10-18 · 父代理）

### 修复与复评

- 第 1 轮代码评审：changes-required（🔴 跨渠道写面只改名 / 🟡 批档指针 / 4 🔵）——全部采纳。
- 修复：`applyConfigOption` 的 model 支整对象换（`agent.provider = { ...target }`）+ 同拍 `activeProvider` / `activeModel` + `compactThresholdAuto` 重算；未知渠道 `false`；刷新链尾 `.catch`；baseURL 过滤注释；测试补写入面；`thincoder/docs/cli/design/ACP-CLIENT.md` §5.3 与 `thincoder/docs/batches/2026-10-18-model-list-all-providers.md` 同步。
- 第 2 轮复评：**pass**（5/5 引用经宿主核对）；上轮 6 项全 Fixed；新增 3 🔵 处置 = #7 按终端 M4 明示 `p:m` 语义不改（Not an issue）· #8 错误文案 / 注释更正（Fixed）· #9 `compactThresholdAuto` 分支补测（Fixed）。

### 机检读数（父代理实跑）

- `node docs/batches/2026-10-18-model-list-all-providers.test.mjs` → **4/4 passed**（37ms）。
- `cd thincoder-cli && npm run lint` → **127 files OK**。
- thincoder `git status`：本轮 = `M thincoder-cli/src/acp/handlers-session.mjs` · `M docs/cli/design/ACP-CLIENT.md` · 新增 `docs/batches/2026-10-18-model-list-all-providers.{md,test.mjs}`；另两处 `docs/cli/requirements/ACP-CLIENT.md` / `docs/cli/design/ACP-CLIENT.md` 为该仓本轮前既有改动（后者含本轮同步）。

### 落点

- 读：`refreshModelChoices` 遍历 `agent.providers`（过滤 `isDerivedProviderHidden`；缺 baseURL 不入候选）→ 并发拉 `/models` → 去重 → 保当前 `provider:model` → 推一次 `config_option_update`；单渠道失败只日志；链尾 `.catch`。
- 写：`applyConfigOption('model')` 整对象换 + `activeProvider` / `activeModel` + `compactThresholdAuto` 重算；未知渠道 `false`；错误文案改「unknown or invalid config option」。
- 文档：`docs/design/thincoder-adapter.md:1167` 来源句更正；`thincoder/docs/cli/design/ACP-CLIENT.md:273` 映射句同步；`thincoder/docs/batches/2026-10-18-model-list-all-providers.md` 自包含记录。

### 已知限制

- 运行中的 app 仍用全局 `thincoder 0.12.75`（`%APPDATA%\npm\thincoder.cmd`），未含本地源码修复 ⇒ 需 `npm link` 或把 `thincoder.path` 指向本地包装后才可见 / 可用；桌面侧零改动。
- 真机走查未做（需先让 app 用上本地 CLI）；ACP 层读/写两面的机检已覆盖。

### 台账与结算

- 台账 #66 结算（在途 → 待核销 → 已核销）。
- 未决计数：56（含 #68 新增）→ 55（#66 核销）；本轮触碰行 = #66（核销）、#68（新增）。
- 批次档冻结。
