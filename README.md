# Rime Local AI：本地 AI 输入法开发基座

基于 Rime 的 Windows 本地补全实验项目。包含 **librime 完整源码基线、依赖源码、本地 AI 插件、拼音方案、MOCK 服务和集成测试**，供克隆后共同构建和开发。

当前后端是固定返回 `[MOCK]` 的协议测试服务，**不包含模型、微调权重或真实 AI 生成效果**。插件只发送当前尚未上屏的中文候选，不读取应用正文、剪贴板或已上屏历史。HTTP 固定访问 `127.0.0.1`，不使用云端回退。

## 下载与环境

支持 Windows 10/11 x64 主机，构建 x64 和 x86 引擎。插件使用 WinHTTP，暂不支持 Linux/macOS。准备：

- Visual Studio 2022 / Build Tools 2022：安装“使用 C++ 的桌面开发”、MSVC v143 x86/x64 和 Windows SDK。
- Python 3.11+（`python --version` 应可执行）。
- 7-Zip；Git for Windows（下载 ZIP 的用户不必安装 Git）。
- 首次准备依赖需要联网和数 GB 可用磁盘空间。

使用 **无空格的英文路径**，例如 `C:\dev\rime-ai`，避免上游批处理与路径编码问题。

```powershell
git clone https://github.com/Cosmocaoaman/-.git C:\dev\rime-ai
cd C:\dev\rime-ai
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-rime-x64.ps1
```

也可在 GitHub 点击 **Code → Download ZIP**，解压到上述路径，从 `setup.ps1` 开始。本仓库内的引擎及其依赖是普通源码文件，不需要 `git submodule update`。

准备脚本安装项目内的 CMake/Ninja，下载并校验 Boost 1.92.0 和官方 Weasel 0.17.4 安装包；**只解压安装包获取前端和标准词典，不注册系统输入法**。下载缓存位于 `.downloads`。如果 Python/7-Zip 不在 PATH，可给脚本传 `-Python`、`-SevenZip` 完整路径。

## 启动演示（不改系统输入法）

构建成功后，在第一个 PowerShell 窗口启动服务：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ai\start-mock.ps1
```

第二个窗口进入仓库运行：

```powershell
.\ai\demo-console.cmd
```

请在真实终端窗口内交互操作；上游 Windows 控制台使用 `_getch` 读取按键，不支持用管道重定向模拟输入。控制台中每行输入后按 Enter：

```text
nihao
{Control+Tab}
```

等一秒，再输入：

```text
{Control+Tab}
{Tab}
exit
```

第一次 `Ctrl+Tab` 请求补全，第二次查看结果；`Tab` / 空格 / Enter 确认，`Esc` 取消预览。输出中应包含 `[MOCK]`。MOCK 窗口按 Ctrl+C 停止服务。控制台输入法数据在 `ai/rime-data`，首次运行会编译词典。

当前需要第二次快捷键查看结果，不会自动显示 ghost text。输入变化后旧结果失效；超时或服务异常时可继续普通拼音输入。

## 测试与 x86 构建

先停止手动启动的 MOCK 或其他占用 `18080` 的服务，测试会自行启动后端：

```powershell
.\.venv\Scripts\python.exe .\ai\tests\run_integration.py --arch x64
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-rime-x86.ps1
.\.venv\Scripts\python.exe .\ai\tests\run_integration.py --arch x86
```

构建脚本运行上游 CTest；集成测试覆盖预览/确认/取消、输入变化丢弃旧结果、会话销毁、HTTP 错误、异常响应和超时。报告在 `ai/logs`。实际发布验证见 [VALIDATION.md](VALIDATION.md)。

| 产物 | 路径 |
|---|---|
| x64 DLL | `librime/dist/lib/rime.dll` |
| x86 DLL | `librime/dist-x86/lib/rime.dll` |
| x64 控制台 | `librime/build-x64/bin/rime_api_console.exe` |
| 集成探针 | `librime/build-{x64,x86}/bin/local_ai_probe.exe` |

## 小狼毫前端与系统使用

完成 x86 构建后可生成前端开发目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ai\package.ps1
```

输出在 `ai/dist/weasel-ai-dev`。它是**开发文件集合，不是自动注册的安装程序**。本版本官方 `WeaselServer.exe` 是 x86，必须搭配 x86 `rime.dll`，不能换成 x64 DLL。

需要在 Windows 应用中使用时：先通过 `.downloads/weasel-0.17.4.0-installer.exe` 正常安装官方小狼毫；退出小狼毫服务并备份原 DLL；将构建出的 x86 DLL 替换安装目录内的 `rime.dll`；将 `ai/rime-data/local_ai_pinyin.schema.yaml` 放到小狼毫用户目录，在 `default.custom.yaml` 的 `patch/schema_list` 中加入 `schema: local_ai_pinyin`（保留原方案）；重新部署、启动 MOCK，然后用 Win+空格切换小狼毫。小狼毫用户目录可从托盘菜单打开。

```yaml
# 合并到自己的 default.custom.yaml；不要覆盖已有 patch 或方案
patch:
  schema_list:
    - schema: luna_pinyin_simp
    - schema: local_ai_pinyin
```

恢复时退出服务，恢复原 DLL、移除新增方案并重新部署。系统安装需要相应权限，脚本不会自动替换你现有的输入法。应用兼容性与打字体验需自行验收。

## 代码与协作

| 位置 | 用途 |
|---|---|
| `librime/plugins/local-ai/local_ai.cc` | 异步请求、状态管理、候选与按键逻辑 |
| `librime/plugins/local-ai/probe.cc` | 真实 Rime API 集成验证 |
| `ai/scripts/mock_server.py` | 本地测试 HTTP 服务 |
| `ai/rime-data/local_ai_pinyin.schema.yaml` | 组件顺序、模型别名及端口 |
| `ai/INTERFACE.md` | 后端请求/响应约定 |
| `upstream-lock.json` | 上游及依赖的准确提交版本 |
| `CONTRIBUTING.md` | 分支、测试和提交约定 |

上游引擎基线为 `388911c517155eb09f7922db90771e31eaa71e54`。当前插件是新增模块，未修改上游引擎的已跟踪业务源码。为支持直接下载 ZIP，依赖源码已展开，保留各自许可证。未修改的 Weasel 前端源码不重复打包，其本地基线在锁定文件中记录；需要开发前端时，从 `https://github.com/rime/weasel.git` 克隆并检出该提交，按前端自身 `INSTALL.md` 构建。

真实模型服务应实现 `POST /v1/chat/completions`，返回短续写。停掉 MOCK 后在同一端口运行模型服务，并对应修改方案中的模型别名。模型下载、推理运行时、推理速度与生成质量不属于本次已验证范围，详见 [接口说明](ai/INTERFACE.md)。

## 常见问题

- 找不到 `cl`：安装 VS2022 C++ 工作负载；脚本通过 `vswhere` 初始化工具链。
- 找不到 CMake/Ninja/Boost/词典：先完整运行 `scripts/setup.ps1`。
- 端口已占用：停止自己启动的 MOCK/模型服务后再运行测试，不要同时运行两种架构测试。
- 没有 AI 候选：确认选择 AI 拼音方案、后端正常，且第二次按了 `Ctrl+Tab`。
- DLL 加载失败：检查 x86/x64 是否匹配；优先从生成的 `build-*/bin` 运行控制台。
- 移动目录后 CMake 报旧路径：清理该副本的 `build-x64`/`build-x86`（包含依赖中的同名构建目录）后重建，勿删除源文件。

许可证按组件适用，见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。个人词库、日志、模型和构建产物不提交。
