# 项目概览

## 目标

`minecraft-dev.nvim` 是面向 Neovim 0.12+ 的 Minecraft 开发插件。核心目标是在 Neovim 中语义对标 IntelliJ IDEA 的 `minecraft-dev/MinecraftDev`，提供可复用的 Lua API、交互式向导和可构建的 Minecraft 项目生成能力。

对标指能力、输入语义和生成结果兼容，不表示复制 IntelliJ Wizard、PSI、VFS 或 Gradle 导入架构。所有功能必须适配 Neovim 的运行模型，并保留适合脚本调用的非交互接口。

## 稳定边界

- `lua/minecraft-dev/`：插件公共 API、配置、命令、向导和运行时服务。
- `lua/minecraft-dev/platforms.lua`：平台、类别、构建系统和默认能力的集中注册表。
- `lua/minecraft-dev/project.lua`：非交互项目生成入口，负责规范化、验证和分发。
- `lua/minecraft-dev/generators/`：各平台生成器及共享生成能力。
- `lua/minecraft-dev/custom/`：MinecraftDev 模板描述符、表达式、provider 和 finalizer 兼容层。
- `lua/minecraft-dev/templates/` 与 `archetype/`：稳定模板和参考生成资源。
- `plugin/`：Neovim 加载入口与用户命令注册。
- `test/`：通过真实公共入口验证配置、命令、模板和项目生成行为。

## 上游与依赖

- 功能和行为的主要来源是 `minecraft-dev/MinecraftDev` 及其 templates 仓库；同步时应记录所依据的提交或版本。
- Neovim API 行为以项目目标版本的官方帮助和官方文档为准。
- Fabric、Paper、Forge、NeoForge、Architectury 等平台数据以对应官方文档、API、MDK 或示例为准。
- 核心能力优先使用 Neovim 内置 API。Telescope 等增强集成必须保持可选，并保留内置 UI 回退路径。

## 完成定义

生成器不能只创建目录或占位文件。交付的项目必须具有正确的源码、元数据和构建配置，并在当前环境允许时通过 Gradle/Maven 解析或实际构建验证。行为、测试和用户文档应在同一阶段保持一致。
