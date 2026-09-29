# 参与开发

1. Fork 仓库并按 README 准备环境，在独立分支上开发。
2. 尽量将插件修改放在 `librime/plugins/local-ai`，方案修改放在 `ai/rime-data`。
3. 修改插件后运行 x64 构建和集成测试；影响 Windows 前端或引擎 ABI 时同时验证 x86。
4. PR 写清楚问题、行为变化、验证命令和实际结果；未测试的内容明确标注。
5. 不提交个人输入记录、`*.userdb`、模型、DLL、日志、下载缓存或本机绝对路径。

这是包含上游源码快照的单仓库。依赖版本见 `upstream-lock.json`，不要在未知变更范围下直接更新全部依赖。升级时同时更新来源记录、许可证和验证结果。

如需复现故障，提供 Windows/VS 版本、架构、最小操作步骤和脱敏日志。不要上传日常输入文本或用户词库。

可继续推进的方向：真实模型适配、超时与长度策略、候选自动刷新、更多故障测试，以及各 Windows 应用中的 TSF 兼容性验证。

## 统一开发入口

首次克隆执行 .\dev.cmd -Setup -BuildOnly；日常代码验证执行 .\dev.cmd -BuildOnly。
更新自己已安装的小狼毫时执行 .\dev.cmd，模拟后端可加 -StartMock。
先运行 .\dev.cmd -Check 核对环境和安装路径；多份安装用 -InstallDir 指定。
使用前提、首次安装和回滚说明见 README 的协作者通用命令。

提交部署脚本修改时，同时运行 powershell -NoProfile -File .\tests\test-dev-environment.ps1。
