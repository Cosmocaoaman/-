# 构建与开发入口

本目录是唯一正式开发仓库。环境准备、构建和启动请参阅 [README.md](README.md)。

已有本地 .build-tools 可继续使用；新克隆请先运行 scripts/setup.ps1。
修改 C++ 后，运行 dev.ps1 可自动构建、测试并更新 Windows 中已安装的小狼毫。

一键命令（包含启动 MOCK）：

.\dev.cmd -StartMock

使用真实模型时省略 -StartMock。参数、备份和恢复说明见 README。
