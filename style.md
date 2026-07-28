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

`generate` 接收完整规范，返回异步任务句柄或结构化错误。`:GmcPro` 保持兼容，并在无参数时进入向导。后续增加的字段不通过继续扩展位置参数表达。

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

## 当前实现切片：P0.3 生成结果

- `generate()`、`generate_async()` 和 `generate_template()` 返回可取消 operation，最终状态统一为 `generated`、`failed` 或 `cancelled`。
- 原生项目和官方模板都先写入目标同级 staging；wrapper、网络和 finalizer 全部成功后才迁移到目标目录。
- 取消只请求终止活动子进程；子进程退出并清理 staging 后才触发一次最终回调。
- 网络回退作为成功结果的 `warnings` 返回，不再同时表达“成功”和“错误”。

## 当前实现切片：P0.4 命令入口

- `:GmcPro` 的补全由平台注册表中的 command capability 派生，只列出位置参数可以完整生成的平台。
- Forge、NeoForge 和 Architectury 返回 `interactive_only`，通过无参数向导收集完整版本集合。
- `:GmcPro` 无参数与 `:MinecraftDevNew` 共用同一向导 operation，选择取消和主动取消均返回 `cancelled`。

## 当前实现切片：P0.5 构建矩阵

- 快速 Lua 回归只验证 runner 定义和故障分类；网络构建由 `test/integration_build_matrix.lua` 显式执行。
- 矩阵固定记录 JDK、Gradle/Maven、Minecraft、Loader/Loom 和语言组合，并复用用户级依赖缓存。
- 结果写入 JSON，包含 Git 指纹、命令和耗时；timeout、network、dependency、tool、generation 与 build failure 分开报告。
- 代表性矩阵覆盖 Paper、Velocity、Fabric Java/Kotlin、Forge、NeoForge 和 Architectury，以及 Maven/Gradle、Mixin/datagen。

## 当前实现切片：P1.1 Paper 版本语义

- 参考 `minecraft-dev/templates@40b091262cff4130b9f61bc25de6cb9e2439d745` 的 `bukkit/paper.mcdev.template.json`。
- 参考 `minecraft-dev/MinecraftDev@6da60db01112200c2b4c73795bdf18db17aa2023` 的 `PaperVersionCreatorProperty`、`ExtractPaperApiVersionPropertyDerivation` 和 `FetchPaperDependencyVersionForMcVersion`。
- `paper_versions` 通过 Paper Fill v3 API 异步加载，仅保留正式版本和 `1.18.2` 及以上版本，并按语义版本倒序交给 `vim.ui.select`；网络错误作为结构化向导失败返回，不降级为手输 JSON。
- Paper API 版本在 1.20.5 前派生 major/minor，1.20.5 起保留完整 Minecraft 版本；26.1 起依赖坐标按 Gradle/Maven 分别使用 `.build.+` 与 `[.build,)`。
- Java 版本派生与上游统一为 8/16/17/21/25，确保动态列表新增的 26.x 项目不会继续使用 Java 21。
- 网络实现复用现有 `curl` 与 `vim.system` 异步边界，不增加 HTTP 或 XML 依赖。版本响应解析和派生规则使用确定性 fixture 测试，另执行真实 Fill API 选择器检查。

## 当前实现切片：P1.1 Paper 构建插件选择

- `maven_artifact_version` 与 `gradle_plugin` 共用 descriptor `sourceUrl` 的异步 Maven metadata 加载，向导使用 `vim.ui.select` 选择版本，不再要求手工输入版本。
- `forceValue` 在属性展示前求值：普通属性直接采用强制值；Gradle 插件只锁定 enabled 状态，仍允许选择具体版本。
- 保持 `curl`/`vim.system` 生命周期与 Paper Fill selector 一致，并覆盖 metadata 成功、失败、取消、强制 Shadow 与 Gremlin 强制关闭 loader 场景。
- 已评估 `xml2lua`、SLAXML 和 Lua-Simple-XML-Parser；Maven metadata 只需读取重复的 `<version>` 文本节点，引入完整 XML 依赖会增加安装和运行时负担，因此使用不执行实体、不构建 DOM 的窄解析器。
- 使用实际上游 Paper descriptor 生成并构建最大 Gradle 组合：Kotlin、version catalog、Gremlin、run-paper、Shadow、paperweight-userdev、resource-factory、Paper manifest、bootstrap、EULA 和 run 配置；JDK 21 下 `./gradlew build` 通过。
