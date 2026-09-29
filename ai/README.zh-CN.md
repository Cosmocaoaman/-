# 本地 AI 开发目录

完整的环境准备、构建、启动、系统接入与协作方式见 [根目录 README](../README.md)。

- `scripts/mock_server.py`：固定输出测试服务，无真实模型。
- `rime-data`：AI 方案；标准词典由 `scripts/setup.ps1` 准备。
- `tests/run_integration.py`：Rime API 集成测试。
- `package.ps1`：组合官方 x86 前端与本地 x86 引擎，不注册输入法。
- `INTERFACE.md`：本地后端协议。

运行时、日志、个人词库、构建结果和模型均不在版本控制中。
