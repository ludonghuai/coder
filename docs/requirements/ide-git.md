# Git 系统代理（ide-git）需求

> 板块：IDE 的 Git 面（`lib/ide/git/**` + `packages/bao_remote` 的 git 执行）· 范围仓：baocode。
> 状态：已实现（2026-10-19；待真机走查）。
> 来源：用户逐字「系统代理和功能缺口你要给我做的完好完美稳定」（2026-10-19 02:01，与 autofetch 同段提出；autofetch / 获取 / ↓N 已于 2026-10-27 按用户裁定移除，SCM 面改用上游实现）。

## 1. 模块目标

BaoCode 启动的 git 子进程**自动跟随 Windows 系统代理**，用户不必手配 `git config http.proxy`。

## 2. 功能点

1. **系统代理自动继承**：git 子进程自动使用 Windows 系统代理（WinINET），无需用户手配 `git config http.proxy`；代理变更后重启 app 生效。
2. **复用既有设置，不新增设置项**：覆盖沿用 Settings→Network 的 `http.proxyMode` / `http.proxy`（已有 UI）。

## 3. 边界

- 代理只覆盖 git 子进程；不动其它网络面。
- 不处理 force-push 的历史改写；不做 submodule 递归更新。

## 4. 验收（可机检 / 走查）

1. 系统代理开（`127.0.0.1:7890`）而 `~/.gitconfig` 无 `http.proxy` ⇒ 手动 Fetch 能通（子进程继承系统代理）。
2. 代理改端口后重启 app ⇒ 新端口生效。

## 5. 依赖

- `packages/bao_remote` 的 `runGit`（子进程启动处）。
- Settings→Network 的 `http.proxyMode` / `http.proxy` 及其 UI。
