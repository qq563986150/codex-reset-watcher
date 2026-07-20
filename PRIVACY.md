# 隐私说明 / Privacy

## 中文

Codex 额度雷达是本地运行的 PowerShell/WPF 工具，不包含独立服务端，也不会建立用户数据库。

- 本机额度通过本地 Codex `app-server` 读取。
- 请求 `account/read` 时明确设置 `refreshToken=false`，脚本不会读取或上传刷新令牌。
- 公告内容从公开的 `codex-resets.com` 页面获取。
- 翻译和分析通过本机已安装的 Codex CLI 执行。
- 缓存、窗口位置和通知状态保存在 `%LOCALAPPDATA%\CodexResetWatcher`。
- 项目不会主动收集账号、对话、浏览记录、密码或支付信息。

删除 `%LOCALAPPDATA%\CodexResetWatcher` 即可清除本项目生成的本地数据。

## English

Codex Reset Watcher is a local PowerShell/WPF utility with no standalone backend or user database. Local quota data is read from the Codex app-server, public announcements are fetched from `codex-resets.com`, and translation/analysis runs through the locally installed Codex CLI. Generated cache and UI state are stored under `%LOCALAPPDATA%\CodexResetWatcher` and can be removed at any time.
