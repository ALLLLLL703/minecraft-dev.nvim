# 项目生成能力对标方案

## 目标

在 Neovim 中语义对标 MinecraftDev 的项目生成功能。界面使用 `vim.ui.select`、`vim.ui.input` 和公开 Lua API，不复制 IntelliJ Wizard UI。生成结果必须是可导入、可构建的 Gradle 或 Maven 项目，而不是空目录或占位模板。

## 上游能力矩阵

参考 `minecraft-dev/MinecraftDev` 当前 `dev` 分支的 creator 与 platform 实现：

| 类别 | 平台 | 构建系统 | 主要选项 |
| --- | --- | --- | --- |
| 服务端插件 | Bukkit、Spigot、Paper | Gradle、Maven | Java/Kotlin、主类、描述、作者、网站、依赖、加载顺序 |
| 代理插件 | BungeeCord、Waterfall、Velocity | Gradle、Maven | Java/Kotlin、主类、描述、作者、依赖 |
| 服务端插件 | Sponge | Gradle、Maven | Java/Kotlin、API 版本、插件元数据 |
| 模组 | Fabric | Gradle | Java/Kotlin、Loader/API/Yarn、环境、Datagen、Mixin |
| 模组 | Forge | Gradle | Forge 版本、映射、Mixin、运行配置 |
| 模组 | NeoForge | Gradle | NeoForge 版本、ModDevGradle、Parchment、Mixin、运行配置 |
| 多加载器模组 | Architectury | Gradle | Fabric/Forge/NeoForge 子模块、公共模块、Loader 版本 |
| 自定义 | 远程/本地模板仓库 | 模板定义决定 | 属性、派生值、条件文件、验证、最终化步骤 |

## 架构

- `lua/minecraft-dev/platforms.lua`：平台注册表，集中声明平台、类别、合法构建系统和默认值；命令补全与分发共享该注册表。
- `lua/minecraft-dev/project.lua`：公开的非交互生成 API，负责验证规范、规范化公共字段并调用平台生成器。交互式命令只负责收集输入。
- `lua/minecraft-dev/wizard.lua`：异步串联 `vim.ui` 输入，不在 UI 回调中执行网络或构建任务。
- `lua/minecraft-dev/generators/common/`：构建文件、源码、许可证、Git 与 Gradle Wrapper 等跨平台能力。
- `lua/minecraft-dev/generators/plugin/`：数据驱动生成 Bukkit 系、代理系、Velocity 与 Sponge。
- `lua/minecraft-dev/generators/{forge,neoforge,architectury}/`：保留平台特有的深层实现。
- `lua/minecraft-dev/templates/`：仅保存稳定静态模板；版本数据通过平台官方 API 获取并允许配置覆盖。
- `lua/minecraft-dev/i18n.lua`：所有用户可见文本通过稳定键访问，兼容现有 `config.messages` 覆盖。
- `lua/minecraft-dev/util/job.lua`：网络、Gradle Wrapper 与 Git 操作通过 `vim.system` 异步执行。

## 公共接口

```lua
require("minecraft-dev").generate({
  platform = "paper",
  build_system = "gradle",
  minecraft_version = "1.21.8",
  directory = "/tmp/example",
  group_id = "com.example",
  artifact_id = "example",
  package_name = "com.example.example",
  main_class = "ExamplePlugin",
  language = "java",
})
```

`generate` 接收完整规范，返回异步任务句柄或结构化错误。`:GmcPro` 保持兼容，并在参数不足时进入向导。后续增加的字段不通过继续扩展位置参数表达。

## TDD 与场景验证

每个垂直阶段按一个公开行为测试、最小实现、再增加下一个行为的顺序推进：

1. 注册表驱动命令补全与非法平台/构建系统验证。
2. 通过非交互 API 在临时目录生成一个平台项目，断言目录、构建文件、元数据和入口源码。
3. 对每个构建系统运行语法或实际构建验证；网络受限时至少执行本地解析，并明确记录未执行项。
4. 验证交互取消、已有非空目录、无效包名和网络失败不会产生半成品项目。
5. 每次配置或命令注册改动后，执行 headless 测试以及带超时的 Neovim 正常启动检查。

## 阶段提交

1. 注册表、规范校验、公开 API 与现有 Paper/Fabric 适配。
2. Bukkit/Spigot/Paper 完整元数据与 Gradle/Maven。
3. BungeeCord/Waterfall/Velocity/Sponge。
4. Fabric 完整版本解析与高级选项。
5. Forge/NeoForge/Parchment。
6. Architectury 多模块。
7. 自定义模板仓库、Git/许可证/最终化步骤与完整文档。

每阶段必须通过测试和 Neovim 启动验证后独立提交并推送。

## 依赖决策

- 保留 Telescope 为可选 UI 增强；核心生成不依赖 Telescope。
- 使用 Neovim 0.12 内置 `vim.system`、`vim.fs` 和 `vim.json`，不为小型注册表或模板渲染增加 Lua 依赖。
- Gradle Wrapper 使用系统 Gradle或上游 wrapper 文件；Git 初始化使用系统 Git。缺失外部程序时返回可本地化错误。
- 模组平台优先采用官方版本 API 与官方构建插件，不引入不活跃的第三方生成器。

## 参考来源

- `minecraft-dev/MinecraftDev`：平台集合、向导字段、构建系统步骤与资源生成方式。
- Fabric Meta API 与 Fabric Example Mod：版本解析和 Gradle 项目结构。
- Paper/Velocity/Sponge 官方开发文档：依赖坐标和插件元数据。
- Forge/NeoForge/Architectury 官方 MDK 或示例项目：Gradle 插件、运行配置和多模块结构。

## 当前实现切片：P0.1 Fabric Kotlin

- 参考 `minecraft-dev/templates@40b091262cff4130b9f61bc25de6cb9e2439d745` 的 Fabric Kotlin DSL 模板。
- 参考 `FabricMC/fabric-language-kotlin` 官方 README 的依赖和 `adapter: "kotlin"` 入口协议。
- Kotlin 项目生成独立 `build.gradle.kts` 与 `settings.gradle.kts`，Java 项目保持现有 Groovy DSL。
- `FabricVersionData` 增加 Fabric Language Kotlin 版本；在线解析 Maven metadata，离线使用配置默认值。
- Kotlin 编译器版本从 `fabric-language-kotlin` 的 `+kotlin.<version>` 后缀派生，避免维护第二个平行版本。
- 通过公共 `project.generate()` 添加回归测试，并以 JDK 21 对 main/client/datagen/Mixin 全开项目执行真实 `gradlew build`。

## 当前实现切片：P0.2 Paper Gradle 版本

- Gradle `group` 使用 `group_id`，项目 `version` 使用 `plugin_version`，依赖版本继续使用 `minecraft_version`。
- `settings.gradle` 的项目名使用 `artifact_id`，因此默认归档名不会与项目版本串位。
- 未提供 `plugin_version` 时与插件元数据保持一致，使用 `1.0.0`。
