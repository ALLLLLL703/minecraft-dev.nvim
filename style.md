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

## 当前实现切片：P1.2 Spigot

- 官方 `spigot.mcdev.template.json` 的维护式版本列表已包含 `26.1`/`26.1.1`，并复用 P1.1 完成的 version catalog、Shadow、resource-factory、Kotlin metadata 和 `forceValue` 支持，不建立平行实现。
- 原生 Paper/Spigot 共享生成器将 major 大于 1 的 calendar version 视为现代版本，并按上游 Minecraft Java 边界派生 8/16/17/21/25 toolchain。
- Gradle 与 Maven、Java 与 Kotlin 模板消费同一 Java 派生；Maven 项目版本改为使用 `plugin_version`，与 manifest 和 Gradle 语义一致。
- Java 25 项目使用 Gradle 9.5.0；Kotlin 26.x 使用 Kotlin 2.4.10 与 Shadow 9.6.1，旧版本使用 Gradle 8.12.1、Kotlin 2.1.20 与 Shadow 8.3.5。
- 构建矩阵按 case 选择 JDK，Spigot 26.1.2 的 Java/Kotlin × Gradle/Maven 四组合均真实构建通过；1.21.11 Kotlin Gradle 兼容分支也构建通过。报告为 `/tmp/minecraft-dev-spigot-p12.json`、`/tmp/minecraft-dev-spigot-p12-gradle-fixed.json` 和 `/tmp/minecraft-dev-spigot-p12-old-kotlin.json`。
- 实际上游 Spigot descriptor 的 version catalog、Shadow 与 resource-factory 组合在 JDK 25 下构建通过，结果为 `/tmp/minecraft-dev-spigot-p12-descriptor.json`。
- 集成矩阵支持 `MINECRAFT_DEV_MATRIX_NO_QUIT=1`，连接到现有 Neovim 时不再执行 `qa`/`cquit`。

## 当前实现切片：P1.3 Velocity

- 官方 Velocity descriptor 复用 custom engine 的 version catalog、Gradle plugin metadata、条件文件和 run metadata；补齐裸属性默认引用与隐藏 idea-ext 自动版本解析。
- 行内 Velocity 条件只消费同一行的空格和制表符，避免内层 `#else` 错误截断外层块级条件。
- Velocity 3.0/3.3/3.5 分别派生 Java 11/17/21，并通过 descriptor fixture 固定边界。
- 原生 Java Velocity 默认使用 annotation processor；原生 Kotlin 默认使用显式 `velocity-plugin.json`，并允许显式启用 kapt/AP。Kotlin 注解数组使用 Kotlin 方括号语法，不复用 Java 花括号。
- 原生 Gradle/Maven 的 Kotlin toolchain、Java release 和插件元数据共享 Velocity 版本规则；默认 Java/Kotlin × Gradle/Maven 四组合真实构建通过，报告为 `/tmp/minecraft-dev-velocity-p13-native.json`；Kotlin AP 的 Gradle/Maven 构建报告为 `/tmp/minecraft-dev-velocity-p13-kotlin-ap-fixed.json`。
- 实际上游 descriptor 的 Java annotation processor + BuildConstants，以及 Kotlin resource-factory + Shadow/run-velocity/version catalog 组合在 JDK 21 下构建通过，报告为 `/tmp/minecraft-dev-velocity-p13-descriptor.json`。
- 保留 `generators/bukkit/` 为内部共享层，不新增语义不明确、上游新模板未公开的通用 Bukkit 平台入口。

## 当前实现切片：P1.4 BungeeCord、Waterfall、Sponge

- 参考 `minecraft-dev/templates@40b091262cff4130b9f61bc25de6cb9e2439d745` 的 BungeeCord 与 Sponge descriptor/build templates，以及 `minecraft-dev/MinecraftDev@6da60db01112200c2b4c73795bdf18db17aa2023` 的 `bungee-platforms.kt`。
- BungeeCord/Waterfall Java Gradle 输出 Groovy DSL，Kotlin 输出 Kotlin DSL；两种语言和 Maven 均以 Java 8 为目标。
- Waterfall 将 Minecraft 版本与 API 版本分离：显式 `waterfall_version` 直接使用，否则异步读取官方 Maven metadata 并选择对应 Minecraft 版本族的最新 API 版本。
- Sponge 按 API 8/9/10/11+ 派生 Java 16/17/17/21；Gradle 使用 SpongeGradle 生成插件元数据，Maven 保留静态 `META-INF/sponge_plugins.json`。
- 快速回归通过公开 `generate()` 覆盖 DSL、版本坐标、Java 边界和元数据分支；集成矩阵覆盖三个平台各自 Java/Kotlin × Gradle/Maven。
- 已检索 Lua/Neovim 项目生成依赖但未发现适合该仓库的维护型组件；版本读取复用现有 `vim.system` 和 Maven metadata 解析，不增加网络、XML 或构建 DSL 依赖。
- metadata operation 提供 `on_complete` 生命周期，Waterfall 取消会等待 curl 退出后再清理 staging 和锁；命令入口与 Lua API 共用同一解析路径。
- Kotlin Gradle/Maven 分别使用 Shadow/Shade 打包运行时；九个受影响组合回归构建通过，代表性产物均包含 `kotlin/Unit.class`。报告为 `/tmp/minecraft-dev-p14-kotlin-packaging.json`。
- 三个平台的原生 Java/Kotlin × Gradle/Maven 十二组合构建通过，首轮报告为 `/tmp/minecraft-dev-p14-proxy-sponge.json`，修复项报告为 `/tmp/minecraft-dev-p14-proxy-fixed.json`。
- 官方 BungeeCord/Sponge descriptor 八组合构建通过；wrapper finalizer 保留模板声明的 Gradle 8.8，结果记录于 `/tmp/minecraft-dev-p14-descriptors.json`、`/tmp/minecraft-dev-p14-descriptors-fixed2.json` 和 `/tmp/minecraft-dev-p14-sponge-descriptor-rerun.json`。

## 当前实现切片：P1.5 Fabric

- 参考 `minecraft-dev/templates@40b091262cff4130b9f61bc25de6cb9e2439d745` 的 Fabric descriptor、Gradle 模板和 metadata 模板，以及 `minecraft-dev/MinecraftDev@6da60db01112200c2b4c73795bdf18db17aa2023` 的 `FabricVersionsCreatorProperty`、`FabricVersionsModel`、`FabricVersions` 与 `FabricApiVersions`。
- `lua/minecraft-dev/generators/fabric/version_data.lua` 负责唯一的 Fabric 版本目录：并行读取 Fabric Meta、Modrinth Fabric API 和 Loom Maven metadata，显式排序 Loader、Yarn、API 与 Loom 候选，并保留 Fabric Meta 提供的 Minecraft 正式版/快照顺序。Fabric Language Kotlin 继续由仅 Kotlin 项目可见的 Maven property 独立加载，避免其故障阻塞 Java 项目。
- 版本目录缓存放在现有 `stdpath("cache")/minecraft-dev/fabric` 下；`defaults.fabric.cache_ttl` 控制新鲜度。新鲜缓存直接复用，网络失败时允许使用过期缓存并返回结构化 warning，不把回退伪装成精确在线结果。
- `fabric_versions` 由专用向导顺序选择是否显示快照、Minecraft、Loom、Loader、Yarn/Mojang mappings、Fabric API 开关及 API 版本，输出与上游模型同名的 `minecraftVersion`、`loom`、`loader`、`yarn`、`useFabricApi`、`fabricApi`、`useOfficialMappings` 字段，不再降级为手输 JSON。
- Yarn 或 Fabric API 没有当前 Minecraft 精确匹配时，选择器提供完整倒序候选并通过本地化 warning 明确告知用户；取消、请求失败和回退均沿用现有异步 child operation 生命周期。
- 原生 `fabric` spec 增加 `use_official_mappings`、`yarn_version`、`use_fabric_api`、`fabric_api_version`、`split_sources` 和 `client_mixins`；datagen 在 Fabric API 关闭时被规范化为 false，split sources 仅在 Minecraft 1.18+ 生效，client Mixin 仅在 split source set 且存在客户端环境时生成。
- Gradle 模板按选项条件输出 Yarn/Mojang mappings、Fabric API、datagen 与 split source sets。Minecraft 26.1+ 使用 `net.fabricmc.fabric-loom` 和 `implementation` 配置；较早版本保留 `fabric-loom`、`mappings` 与 `modImplementation`。
- metadata 的 Loader、Minecraft、Java、Fabric API 和 Kotlin 约束使用实际选中版本；主 Mixin 与 client Mixin 分别写入 main/client resources，并让源码包、配置 bucket 与 source set 一致。
- Gradle 9.6 将 Kotlin DSL 的 `project.property()` 暴露为 `Any?`，而上游 Fabric 模板直接把它放入 `expand` map 会编译失败；custom renderer 仅对 `.gradle.kts` 的实际 `expand(...)` 范围内、以字符串键引用 Gradle property 的 map pair 补充 `as String`，不修改缓存模板或绑定 Fabric 路径。
- 快速回归使用固定 Fabric Meta、Modrinth 和 Maven fixture，覆盖稳定版筛选、26.1、响应乱序、精确/回退选择、TTL、取消、官方 descriptor 选择器及原生 Java/Kotlin 生成。真实构建覆盖 Yarn/Mojang、API on/off、split/client Mixin/datagen 和 26.1 新 Loom 插件族。
- 原生 Java/Yarn/API-off 与 Kotlin/26.1/split 两组合真实构建通过，报告为 `/tmp/minecraft-dev-p15-fabric.json`；实际官方 Fabric descriptor 的 Java/Yarn 与 Kotlin/26.1 两组合构建通过，报告为 `/tmp/minecraft-dev-p15-fabric-descriptors.json`。
- 独立审查覆盖缓存、异步重入、26.1 mappings、client-only source set、顶层版本 override、warning 传播、fallback 排序、Kotlin DSL 转换和输入验证；修复后复审无 finding。
- 已评估 `rest.nvim` 和通用 Neovim async 库；`rest.nvim` 面向 HTTP 文件交互并引入 Tree-sitter/LuaRocks 依赖，通用 async 库也不会减少固定请求的解析与领域筛选逻辑。继续复用 Neovim 0.12 内置 `vim.system`、`vim.json`、`vim.fs` 和现有 curl 生命周期，不增加运行时依赖。

## 当前实现切片：P1.6 Forge

- 参考 `minecraft-dev/templates@40b091262cff4130b9f61bc25de6cb9e2439d745` 的 Forge descriptor、七套入口类、两套 Config、Gradle、metadata 与 pack 模板，以及 `minecraft-dev/MinecraftDev@6da60db01112200c2b4c73795bdf18db17aa2023` 的 `ForgeVersion`、`ForgeVersionsCreatorProperty` 和 `ForgeVersions`。
- `lua/minecraft-dev/generators/forge/version_data.lua` 负责 Forge Maven metadata 的纯解析、兼容版本分组、倒序排序、每个 Minecraft 版本最多 50 个 Forge 候选，以及可取消的异步加载；原生 API 未提供 `loader_version` 时也通过该模块解析所选 Minecraft 的最新兼容 Forge。
- P1.6 的动态目录限制在已由固定上游 ForgeGradle 6 模板覆盖的 Minecraft 1.16–1.21.1；实时 Maven 中需要 ForgeGradle 7、新事件总线或 26.x 版本模型的后续版本不显示为可生成项，避免产生无法构建的项目。
- `lua/minecraft-dev/custom/forge_versions.lua` 负责 `forge_versions` 的两级选择，输出上游同名的 `minecraft`、`forge`、`minecraftNext`、`forgeSpec` 字段；向导取消沿用 child operation 生命周期，不降级为手输 JSON。
- 原生 Forge 生成与 NeoForge 共享入口解耦：Forge 专属构建、metadata、pack format、入口模板和 Config 选择放入 `lua/minecraft-dev/generators/forge/native.lua`，现有 `generators/forge.lua` 只负责平台分发并保留 NeoForge 当前行为。
- 七个入口版本断点与 1.20.1/1.21 Config 使用 `archetype/forge_gradle/` 下的独立资源模板；生成器只做占位符替换和断点选择，不把完整 Java/Gradle 模板硬编码进 Lua。
- Forge Gradle 配置使用实际 Minecraft、Forge、Java、metadata、Mixin 和版本范围，生成可编译的示例 Mixin 类、许可证文件、版本化 `pack.mcmeta`，并写入 Neovim 可消费的 client/server/data/build Gradle run metadata，作为 `genIntellijRuns` 的编辑器等价行为。
- 快速回归覆盖 metadata 乱序与无效坐标、50 项限制、派生字段、选择取消、自动版本解析、七个入口断点、两套 Config、Mixin、完整 metadata、pack format 和 run metadata；构建矩阵至少覆盖 1.16.5、1.20.1、1.21.1 三个断点。
- 已检索 `xml2lua.nvim`、`maven.nvim` 与 Neovim XML 解析实现；引入完整 XML parser 或 Maven 插件只为提取固定 `<version>` 文本会扩大依赖和攻击面，且不能替代 Forge 兼容分组规则。继续复用内置 Lua、`vim.system`、`vim.fs`、`vim.json` 和现有 curl 生命周期，不增加依赖。
- 快速回归覆盖动态目录、50 项限制、取消与重入、官方向导、七套入口、1.20 精确边界、两套 Config、Mixin、metadata、许可证、pack format、run metadata、隔离 wrapper 和跨行 Velocity 指令；最终独立复审为 `No findings`。
- 原生 Forge 1.16.5/36.2.42、1.20.1/47.4.10、1.21.1/52.1.0 三版本构建报告为 `/tmp/minecraft-dev-p16-forge.json`；Parchment 复验报告为 `/tmp/minecraft-dev-p16-forge-final.json`，1.20.6/50.1.17 专用构造器边界报告为 `/tmp/minecraft-dev-p16-forge-1.20.6.json`，均通过。
- 实际官方 Forge descriptor 的 1.21.1/Mixin 项目通过隔离 wrapper 生成和真实构建，报告为 `/tmp/minecraft-dev-p16-forge-descriptor.json`；`genIntellijRuns` 被转换为 Neovim Client、Server、Data run，并保留模板声明的 Build run。
