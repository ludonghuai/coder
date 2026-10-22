# BaoCode 安装指南（Windows）

> 适用版本：1.6.0（安装包名 `BaoCode-1.6.0-setup.exe`）。
> 一句话：**下载 → 双击 → 过 SmartScreen → 装完打开 → 选一个文件夹**。要让 AI 真的能干活，还要做第 4 节那一步。

## 1. 下载

从发布页下载安装包：

```
https://github.com/ludonghuai/coder/releases/latest
```

页面里找 **Assets**，点 `BaoCode-1.7.0-setup.exe`（约 43 MB —— 从 1.7.0 起安装包**内置了 thincoder**，所以比旧版大；换来的是装完就能用，不必先装 Node）。

## 2. 安装

1. 双击 `BaoCode-1.6.0-setup.exe`。
2. Windows 会弹 **「Windows 已保护你的电脑」**（因为安装包没有购买代码签名证书，这是正常的）：
   - 点 **更多信息**
   - 点 **仍要运行**
3. 按向导下一步，装完点完成。
4. 如果启动时报缺少 `VCRUNTIME140.dll` 之类，装一次微软运行库：
   <https://aka.ms/vs/17/release/vc_redist.x64.exe>

安装位置默认在 `%LOCALAPPDATA%\Programs\BaoCode`，开始菜单里会有 **BaoCode**。

## 3. 第一次打开

1. 打开 BaoCode，点 **打开文件夹**（或 `Ctrl+K` 后输入路径），选一个你的代码目录。
2. 左边出现文件树、下面出现对话输入框，就说明起来了。

## 4. 让 AI 能用（重要，只做一次）

BaoCode 有两个内核，选一个用：

### 方式 A：thincoder 内核（推荐，终端同款）

1. **不用装任何东西**——安装包里已自带 thincoder（Node 运行时 + CLI 源码树）
2. 配一个供应商就能用：**设置 → 模型（thincoder）→ 添加 provider**，填 名字 / Base URL / API Key / 模型名，保存
3. 回到会话，顶部就能选到那个模型了

### 方式 B：Claude Code 内核

1. 在终端执行 `claude`，按提示登录一次。
2. 回到 BaoCode，在会话顶部把内核切到 **Claude Code**。

## 5. 没有模型可选怎么办

如果对话页顶部看不到模型、或者发消息提示没有模型，说明还没有可用的供应商：

1. **设置 → 模型（thincoder）→ 添加 provider**，填四项保存（页面顶部会显示配置文件的实际路径，想手改就按那个路径找）；
2. 保存后如果当前会话已经开着，页面上会出现「重新打开 thincoder 会话」的按钮，点一下生效；
3. 手改也行：按上面那个路径编辑 `config.json`，在 `providers` 里加一条：

   ```json
   {
     "providers": [
       { "name": "my-provider", "baseURL": "https://api.example.com/v1", "apiKey": "sk-..." }
     ],
     "defaultModel": "my-provider:gpt-4o"
   }
   ```

3. 改完重开 BaoCode 的会话。

## 6. 更新

- **自动**：装好之后，BaoCode 每次启动会检查发布页；有新版本会在设置里提示，点一下就能升级。
- **手动**：回发布页重新下载最新安装包，覆盖安装即可（设置和项目都保留）。

## 7. 卸载

**设置 → 应用 → 已安装的应用 → BaoCode → 卸载**。
你的项目文件不受影响；配置与缓存留在 `%APPDATA%\baocode`，要彻底清掉可以手动删。

## 8. 常见问题

| 现象 | 原因 | 怎么办 |
|---|---|---|
| 双击没反应 / 被 SmartScreen 拦住 | 安装包未签名 | 更多信息 → 仍要运行 |
| 启动报缺 DLL | 没装 VC++ 运行库 | 装 `vc_redist.x64.exe` |
| 会话里没有模型 | thincoder 没配供应商 | 见第 5 节 |
| 提示 `thincoder is not installed` | 内置运行时缺失（安装不完整）或手动指定了不存在的路径 | 重装一次（覆盖安装即可）；或在 **设置 → 通用 → thincoder** 清空路径 |
| 提示 thincoder 版本过旧 | 手动指定了自己那份且低于 0.12.74 | 清空那个路径回到内置那份，或 `npm i -g thincoder@latest` |
| 检查更新失败 | 网络到 GitHub 不通 | 稍后再试；或手动下载覆盖安装 |
