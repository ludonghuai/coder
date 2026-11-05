# 2026-11-04 · thincoder-runtime-0.12.81
> 六段 append-only，一段一作者：§1 讨论（主 agent）· §2 批次任务与设计（eng-designer）· §3 设计评审（评审子代理）· §4 用户批准（主 agent）· §5 实施记录（eng-coder）· §6 验证与收口（父代理）。
> 编制：主 agent · 2026-11-04 · 来源 = 用户 2026-11-04「I noticed that the thincoder code hasn't been pulled yet. Could you take over the project from here and see what needs to be adjusted?」；`thincoder/` 合完上游 58 个（0.12.81）之后，baocode 这一侧要跟的事。
> 前情 = docs/batches/2026-11-04-thincoder-out-of-repo-58.md（已收口）。
## §1 讨论（主 agent）
**状态行**：已收口 2026-11-04

### 本批：baocode 跟上 thincoder 0.12.81

按 `docs/design/thincoder-adapter.md` §12 A 的升级核对清单逐条走，结论是只有打包脚本的版本常量要改。

**要改的（2 处）**

- `tool/build_windows.dart` 的 `_thincoderVersion`：`0.12.80` → `0.12.81`。
- `tool/build_macos.dart` 的 `_thincoderVersion`：`0.12.79` → `0.12.81`。这一档上一次就漏改了：1.7.2（`0a5bac69`）时两档同为 0.12.79，10-26 工作树到 0.12.80 时（`ad3ff87f`）只改了 Windows 那档。两档的两道版本校验（源码树 `package.json` 与拷进去的 `--version`）比的都是这个常量，不改的话打包会停在第一道。
- 顺带把这一步补进 §12 A（第 9 条），免得下次又只改一档。

**不用改的（逐条理由）**

| §12 A | 核对 | 结论 |
|---|---|---|
| 1 先跑固件 | `flutter test test/kernel/thincoder_fixtures_test.dart` 等四档 | 49 过 / 0 挂；另 `thincoder_kernel_test.dart` 152 过 / 0 挂 |
| 2 握手实况 | 合并后的 CLI 回 `initialize` | `protocolVersion` 1；`loadSession`、`promptCapabilities`、`sessionCapabilities`、`mcpCapabilities.http` 的键与值和 §3.4 一致；`authMethods` 空；版本 0.12.81 |
| 3 方法面 | 上游在 ACP 层只改了 `bridge.mjs`、`read-data.mjs`、`resource-link.mjs` 三档 | `client-caps.mjs`、`handlers-session.mjs`、`handlers-slots.mjs`、`transport.mjs` 上游没碰，我们发的方法都在、语义不变；实况走过 `session/new` / `set_config_option` / `set_mode` / `list` / `close` |
| 4 线形 | 适配层读的字段 | 没变。上游的改动落在我们不读的面上：编辑桥的回执文字（我们原样显示，不解析）、`ledger/count` 的 `evidenceOversize` 改名 `evidenceTooLong`（我们不接 `ledger/*`，§10）、`ssh` 的 `put` / `get`（kind 是 `other`，走通用卡片与审批）、子代理角色多了 `tester`（我们不写死角色名） |
| 5 错误面 | 无渠道时的 `session/new` | `-32000`，文案仍指向 `providers[].apiKey` 与 `thincoder acp --login` |
| 6 版本下限 | `ThincoderLocator.verifiedVersion` | 留在 `0.12.74`：协议面没变，按本条只在协议面变时才改 |
| 7 重录固件 | — | 不重录：线形没变，固件仍是按源码线形手录的那一版 |
| 8 需求档 §5 | — | 不涉及：这批上游没有给 ACP 补新能力 |

**内置副本的拷贝面**：上游没有在 `thincoder-cli` 的 `bin` / `src` 之外加运行期文件，也没有新增 npm 依赖（两档 `package.json` 只改了版本号，CLI 对 core 的依赖跟到 `^0.11.1`）。照 `_putRuntime` 的布局在临时目录拼一份（CLI 四项 + `node_modules/@thincoder/core` 实拷），`--version` 报 0.12.81，`initialize` 回包与上面一致。

**没做的**

- macOS 打包本机跑不了，`tool/build_macos.dart` 只改了常量，没有实跑。
- `-t e2e-thincoder` 这个真机冒烟标签在 `dart_test.yaml` 里不存在（§9 写了它），本批没有补。

## §2 批次任务与设计（eng-designer）
**状态行**：（eng-designer 写入时更新）
<§2 模板占位：本批条目（覆盖） / 设计档落点 / 机制设计 / 受影响文件与测试覆盖 / 验收对照 / 关键决策 / 上抛项>
## §3 设计评审（评审子代理）
## §4 用户批准（主 agent）
## §5 实施记录（eng-coder）
## §6 验证与收口（父代理）
**状态行**：已收口 2026-11-04

- 两档常量与 `thincoder/thincoder-cli/package.json` 的 `version` 同为 `0.12.81`。
- Windows 打包的两道校验在临时目录复现：源码树版本 0.12.81，拷出的运行时 `--version` 0.12.81。
