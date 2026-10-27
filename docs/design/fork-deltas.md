# Fork delta 登记表

## 1 规则与覆盖口径

本表登记允许继续维护的自有资产，以及共享上游文件中可辨认的接线。目标 = 上游共享文件可优先合并，自有语义只在独立模块与登记接缝中存活。

- **表外不许改上游档**。确需新增接线时，先登记文件、块、类型、接缝和行数预算，再改代码。
- 本表不是历史 diff 的逐行镜像。表外共享文件是只读上游面；合并前仍须做全量 diff，对账发现自有块时先补表再解决冲突，不得凭「表外」推断没有自有块。
- 自有目录 / 文件不得因冲突整档取上游；共享文件不得把上游实现回退成旧 fork 版本。
- 「行数预算」约束共享文件的 fork 净增行；自有文件用「自有」标记，仍受既有结构拆分规则约束。
- 类型只用：**修 bug · 功能 · 内核适配**。
- l10n 只合并 `app_en.arb` / `app_zh.arb` 的键级并集；生成文件由 `flutter gen-l10n` 重产，不手解、不选边。
- 上游测试与自有断言分档；不为保留 fork 断言改写上游测试。
- 每次上游合并后按符号核对本表，不以旧行号判断接线是否仍在。

## 2 整档自有资产

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/kernel/thincoder/**` | ACP 内核、协议、目录、配置与进程适配 | 内核适配 | `AgentKernel` / `SessionCatalog` / `HostTools` | 自有 |
| `lib/browser/btest/**` | 浏览器业务测试模式、策略、run、状态 UI 与工具门 | 功能 | `ChatSessionOverlay`、`HostTool` | 自有 |
| `lib/diagnostics/**` | 帧、stall、hang 与诊断包 | 功能 | 应用启动与设置诊断入口 | 自有 |
| `lib/platform/process_host.dart`、`process_host_io.dart`、`process_host_stub.dart` | 非窗口线程进程创建 | 修 bug | `ThincoderProcess` 与诊断测试 | 自有 |
| `lib/chat/session/**` | ChatSession overlay 与独立 helper | 内核适配 | `chat_session_overlay.dart` | 自有 |
| `lib/chat/chat_session_overlay.dart` | 通用 overlay host 与生命周期契约 | 内核适配 | `ChatSession` 构造及生命周期钩 | 自有 |
| `lib/host_tools/host_tools.dart` | 跨内核宿主工具注册与调用通道 | 功能 | `HostTool` / `HostToolCall` / MCP | 自有 |
| `test/kernel/thincoder*_test.dart`、`test/diagnostics/**` | 自有内核与诊断断言 | 功能 | 对应独立模块 | 自有 |
| `test/ide/git/scm_fetch_button_test.dart`、`git_autofetch_test.dart` | 自有 SCM 断言，独立于上游测试 | 功能 | SCM 公共入口；#181 未裁定 | 自有 |
| `test/RTM.md`、`test/integration/**` | 本仓业务集成索引与用例 | 功能 | 用户入口与业务可观察结果 | 自有；50–100 行用例窗 |

## 3 共享上游文件的登记接缝

| 文件 | 我们的块 | 类型 | 接缝 | 行数预算 |
|---|---|---|---|---|
| `lib/chat/chat_session.dart` | overlay 装配、host 投影、生命周期钩、缺失能力投影 | 内核适配 | `docs/design/thincoder-adapter.md` §29.2 | 净增 ≤180 行 |
| `lib/chat/chat_feed.dart` | `MarksTurns` 只读接口 | 内核适配 | `ChatSession.turns` 与 folds | 净增 ≤16 行 |
| `lib/chat/chat_models.dart` | `TurnMark`、`NoticeItem` 与 editor context 数据形 | 内核适配 | overlay / `KernelTurn.contexts` | 每类 ≤30 行 |
| `lib/chat/composer/composer_editing.dart` | `hasCommandSource` 命令源门 | 内核适配 | `ChatSession.hasCommandSource` | 净增 ≤12 行 |
| `lib/chat/composer/composer_view.dart` | btest 缓存键与状态行挂点 | 功能 | `ChatSession` 的 btest 七成员 | 净增 ≤24 行 |
| `lib/browser/browser_tools.dart` | `HostTools` 注册包装、数字归一、description schema、btest gate、tab watch/blocked/acting | 功能 | `HostTool` / `HostTools` / `HostToolCall`；btest 经独立模块 | 净增 ≤150 行 |
| `lib/workspace/workspace.dart` | thincoder 目录、默认内核偏好、确认改名 | 内核适配 | `SessionCatalog`、`ConfirmsRename`、`SessionRenamed` | 新增净增 ≤40 行 |
| `lib/main.dart` | thincoder 进程 reap/stop 与状态设置接线 | 内核适配 | `ThincoderLocator` / process registry | 新增净增 ≤20 行 |
| `lib/kernel/kernel_registry.dart` | thincoder 为默认内核，Claude 保留 | 内核适配 | `_all = [thincoder, claudeCode]` | 净增 ≤12 行 |
| `lib/kernel/agent_kernel.dart` | fork 能力接口 | 内核适配 | `ConfirmsRename`、`AcceptsImageFiles`、`AcceptsEditorContext` 等 | 每个接口 ≤16 行 |
| `lib/kernel/kernel_types.dart` | `KernelTurn.contexts` 与回退数据形 | 内核适配 | overlay 发送与 `PlansReverts` | 每类 ≤40 行 |
| `lib/l10n/app_en.arb`、`app_zh.arb` | fork 文案键并集 | 功能 | ARB 源档；生成物零手改 | 只增所需键；同名不覆盖上游措辞 |
| `lib/settings/pages/thincoder_models_page.dart` | thincoder 模型配置页 | 功能 | 设置页导航与 CLI 配置文件 | 自有页面；共享导航接缝另计 |
| `lib/settings/app_settings.dart`、`settings/settings_dialog.dart` | thincoder 设置入口 | 功能 | `SettingsSection.thincoderModels` | 合计净增 ≤50 行 |

## 4 本批冻结的共享文件

以下文件保持上游实现，本批不为恢复旧 fork 行为而修改：

- `lib/ide/git/ide_scm_view.dart`；SCM「获取」语义仍待 #181 裁定。
- `lib/ide/ide_editor.dart`、`lib/ide/ide_workbench.dart`、`lib/workbench.dart`。
- `lib/chat/composer/composer_picker.dart`、`session_model_picker.dart`。
- `lib/chat/composer/composer.dart`、`composer_editing.dart`。后者已有命令源门，仅由 R1 恢复其调用的 getter。
- `lib/chat/composer/composer_view.dart`、`lib/browser/btest/btest_status_switches.dart`。两者只由 session 契约恢复而编译，不改 UI。
- `lib/browser/browser_actions.dart`、`browser_debug_tools.dart`。两者已是 `HostTool` 形态，只修父库。
- 上游 SCM 测试档与 `test/chat/side_panel/side_panel_test.dart`。

## 5 合并核对顺序

1. 先核第 2 节自有文件仍存在，未被共享档选边覆盖。
2. 对全量 diff 做自有块对账；表外发现自有块时先补第 3 节，再选冲突解法。
3. 核第 3 节每个接缝的符号与行为；行号只作定位参考。
4. 运行 `flutter analyze --no-pub`，把错误按登记模块归因；不得以整档回退消除冲突。
5. 重跑各模块定向测试；l10n 由源档重产；SCM 只跑对应独立断言。
6. 新出现的共享文件改动若没有行，停止实施并先登记。
