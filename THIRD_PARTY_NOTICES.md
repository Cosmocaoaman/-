# 第三方来源

本仓库保留上游源码中的许可证和版权声明；根目录许可证仅适用于本地新增代码与文档，不覆盖第三方组件。

- librime：`librime/LICENSE`（BSD-3-Clause）。
- glog、googletest、leveldb、marisa-trie、OpenCC、yaml-cpp 及其随附依赖：见 `librime/deps` 内各组件的 LICENSE/COPYING 文件，准确来源提交见 `upstream-lock.json`。
- Boost 1.92.0：准备脚本下载，Boost Software License 1.0，见下载源码中的 `LICENSE_1_0.txt`。
- Weasel 0.17.4 官方前端和标准词典：准备脚本从官方 Release 下载，保留解压后的 `LICENSE.txt` 等声明；Weasel 为 GPL-3.0，词典与附带组件遵循各自声明。前端源码来源为 https://github.com/rime/weasel，安装包对应标签为 `0.17.4`。

如果再次分发打包后的前端/引擎二进制，应一并保留版权、许可证与相应源码获取方式。开发仓库不包含第三方模型权重；将来接入模型时需另外记录其许可证。
