# 项目生成上游差距与后续任务

## 审计范围

- 审计日期：2026-07-28。
- 上游插件：`minecraft-dev/MinecraftDev@6da60db01112200c2b4c73795bdf18db17aa2023`。
- 上游模板：`minecraft-dev/templates@40b091262cff4130b9f61bc25de6cb9e2439d745`。
- 本地入口：`lua/minecraft-dev/project.lua`、`lua/minecraft-dev/platforms.lua`、`lua/minecraft-dev/custom/`。
- 本文重点是项目生成。编辑器检查、代码洞察、NBT、Mixin 导航等非生成能力不在本轮范围内。

## 两条生成路径

本项目目前有两条相互独立的生成路径，后续任务不能混为一谈。

| 路径 | 入口 | 当前作用 | 主要风险 |
| --- | --- | --- | --- |
| 原生生成器 | `require("minecraft-dev").generate()`、`:GmcPro` | 本地 Lua 直接生成 Paper、Fabric、Forge 等项目 | 平台功能深度不一致，版本矩阵和错误语义不完整 |
| 官方模板生成器 | `generate_template()`、`:MinecraftDevNew` | 拉取并渲染 `minecraft-dev/templates` v1-v3 描述符 | 高级属性类型、派生、交互和 finalizer 仍只是兼容子集 |

## 当前基线

已经具备且不应重复开发的能力：

- 原生平台注册：Paper、Spigot、BungeeCord、Waterfall、Velocity、Sponge、Fabric、Forge、NeoForge、Architectury。
- Gradle/Maven 基础项目生成和 Java/Kotlin 基础源码生成。
- Fabric side、datagen、Mixin 和 Fabric Meta/Modrinth 版本刷新。
- Forge/NeoForge Parchment、Mixin 配置、Gradle runs。
- Architectury common/Fabric/Forge 三模块及 Shadow 打包链。
- 官方模板 local/archive/remote/builtin provider。
- v1-v3 descriptor、条件文件、路径表达式、部分属性派生、Velocity 指令和 finalizer。
- 官方仓库模板发现与 `:MinecraftDevNew` 基础向导。
- Paper、BungeeCord、Waterfall、Velocity、Sponge、Fabric、Forge、NeoForge、Architectury 已做过人工真实构建验证。

## P0：先修复生成可靠性

这些问题会直接产生错误项目、假成功或不可用命令，应优先于新增平台选项。

### P0.1 Fabric Kotlin 生成必须可构建

现状：Kotlin 只切换源码模板，公共 `archetype/fabric_gradle/build.gradle` 没有 Kotlin Gradle 插件、Kotlin stdlib 或 Fabric Language Kotlin。README 却声明支持 Kotlin。

- [x] Kotlin 项目生成 `build.gradle.kts` 或正确配置 Kotlin 的 Gradle 脚本。
- [x] 动态选择 Kotlin、Fabric Language Kotlin 和 Loom 的兼容版本。
- [x] Java 和 Kotlin 分别验证 main/client/datagen/Mixin 组合。
- [x] 用 JDK 21 执行生成项目的真实 `gradlew build`。

验收：Fabric Java、Fabric Kotlin 各至少一个高级选项全开的项目能够从空缓存构建。

### P0.2 修复 Paper Gradle 项目版本

现状：`lua/minecraft-dev/generators/paper/gradle.lua` 把 `artifact_id` 写入 Gradle `version`，而不是 `plugin_version`。模板第二个 `%s` 明确对应项目版本。

- [x] Java/Kotlin、1.13 前后模板都使用 `plugin_version`。
- [x] 未提供 `plugin_version` 时使用稳定默认值 `1.0.0`。
- [x] 添加生成内容断言和真实 Gradle 构建测试。

验收：生成项目的 `group`、`archivesName`、`version` 三者语义正确且互不串位。

### P0.3 统一生成成功、失败和取消语义

现状：`project.generate()` 调用生成器后无条件返回 `true`；Gradle wrapper、网络和部分生成错误发生在返回之后。Fabric 在线刷新还可能同时回传生成成功与 fetch error。

- [x] 定义统一结果：`generated`、`failed`、`cancelled`。
- [x] 所有生成器返回结构化错误，不以通知代替 API 结果。
- [x] `generate_async()` 覆盖所有平台，不只为 Fabric 特判。
- [x] wrapper、Git、网络、finalizer 完成后才报告最终成功。
- [x] 失败时清理 staging 目录，不留下半成品。

验收：调用者能可靠判断项目是否完整生成，失败项目不会污染目标目录。

### P0.4 修复 `:GmcPro` 暴露不可交互平台

现状：补全展示全部平台注册项，但 Forge、NeoForge、Architectury 依赖完整 `spec`；位置参数命令无法收集这些字段。

- [x] 参数不足时统一转入向导，或只补全命令真正支持的平台。
- [x] 最终合并 `:GmcPro` 与 `:MinecraftDevNew` 的入口语义。
- [x] 测试每个平台的选择、取消和无效输入。

验收：补全中出现的平台都能从命令完成生成，不出现 nil 字段异常。

### P0.5 建立可重复的真实构建矩阵

现状：真实构建已人工执行，但 `test/test_refactor.lua` 主要断言文件内容，无法在后续变更中阻止 Gradle/Maven 回归。

- [ ] 增加可选的网络集成测试层，不把慢构建塞进快速单元测试。
- [ ] 缓存 Maven/Gradle 依赖，并记录 JDK、Gradle、平台版本组合。
- [ ] 至少覆盖 Paper、Velocity、Fabric、Forge、NeoForge、Architectury。
- [ ] 覆盖 Java/Kotlin、Gradle/Maven、Mixin/datagen 等关键分支。
- [ ] 将超时、网络失败和依赖坐标失效区分报告。

验收：修改生成模板后，可以用一条命令复验所有代表性项目。

## P1：补齐上游平台生成能力

### P1.1 Paper

上游证据：`templates:bukkit/paper.mcdev.template.json`。

本地缺失：

- [ ] Paper Fill API 动态正式版本列表，最低版本策略和真实依赖版本派生。
- [ ] Gradle version catalog。
- [ ] `plugin.yml` 与 `paper-plugin.yml` 完整切换。
- [ ] Paper bootstrap 类。
- [ ] plugin loader，以及 Kotlin 项目选择 Java/Kotlin loader。
- [ ] Gremlin、run-paper、Shadow、paperweight-userdev、resource-factory 插件选项。
- [ ] run-paper 自动接受 EULA 和 `runServer` 运行配置。
- [ ] Gremlin、Kotlin、resource-factory 之间的 `forceValue` 规则。

验收：官方 Paper 描述符的每个可见选项都能通过 Neovim UI 设置，并生成等价文件集合。

### P1.2 Spigot 与通用 Bukkit

上游证据：`templates:bukkit/spigot.mcdev.template.json` 和旧式 `platform/bukkit/creator/`。

- [ ] 动态或维护式版本列表，支持新版本号 `26.1`。
- [ ] 从 MC 版本派生 `api-version`，不直接复制完整版本号。
- [ ] version catalog、Shadow、resource-factory。
- [ ] 评估是否保留独立通用 Bukkit 入口；当前官方仓库模板以 Paper/Spigot 为主。

验收：Spigot Java/Kotlin 的 Gradle/Maven 项目均可构建，manifest API version 正确。

### P1.3 Velocity

上游证据：`templates:velocity/.mcdev.template.json`。

- [ ] version catalog。
- [ ] 可选 annotation processor 和 `velocity-plugin.json` 路径。
- [ ] BuildConstants 模板生成。
- [ ] run-velocity、Shadow、resource-factory、idea-ext 插件。
- [ ] `runVelocity` 运行配置。
- [ ] 按 Velocity 3.0/3.3/3.5 派生 Java 11/17/21。

验收：annotation processor 开关、resource-factory 开关和运行插件组合均可构建。

### P1.4 BungeeCord、Waterfall、Sponge

上游证据：`templates:bungeecord/.mcdev.template.json`、`templates:sponge/.mcdev.template.json` 和旧式 Waterfall creator。

- [ ] Bungee Java 使用 Groovy Gradle、Kotlin 使用 Kotlin DSL 的上游行为。
- [ ] Bungee 默认 Java 8，不再统一硬编码 Java 21。
- [ ] Waterfall 使用真实平台版本选择器，避免把 Minecraft 版本当 API 版本。
- [ ] Sponge 按 API 8/9/10/11+ 派生 Java 16/17/17/21。
- [ ] Sponge Gradle 与 Maven 元数据生成策略分别对齐上游。

验收：每个平台至少覆盖 Java/Kotlin 与 Gradle/Maven 四种组合。

### P1.5 Fabric

上游证据：`templates:fabric/.mcdev.template.json` 和 `FabricVersionsCreatorProperty.kt`。

- [ ] MC 正式版/快照切换。
- [ ] Yarn 与 Mojang mappings 选择。
- [ ] Fabric API 可关闭。
- [ ] Kotlin Loader 版本选择。
- [ ] MC >= 1.18 时可拆分 client source set。
- [ ] 主 Mixin 与 client Mixin 分离。
- [ ] datagen 只在 Fabric API 启用时开放。
- [ ] 版本 API 无精确匹配时给出回退列表和警告。
- [ ] 修复 26.1 版本族、缓存 TTL、稳定版筛选和响应排序。

验收：官方 Fabric 描述符不需要手输 JSON，所有复合版本字段都由选择器产生。

### P1.6 Forge

上游证据：`templates:forge/.mcdev.template.json`。

- [ ] 动态 MC/Forge 兼容版本，限制 MC >= 1.16。
- [ ] 按 1.16、1.17、1.18、1.19、1.19.3、1.20、1.20.6+ 选择入口模板。
- [ ] MC 1.20.1+ 生成示例 `Config.java`，MC 1.21 使用新版模板。
- [ ] 生成可编译的示例 Mixin 类，不只生成空配置。
- [ ] 完整更新 URL、作者、网站和依赖元数据。
- [ ] 许可证文件和版本对应的 `pack.mcmeta`。
- [ ] `genIntellijRuns` 的 Neovim 等价运行任务。

验收：至少选择三个版本断点进行真实构建，并验证入口类差异。

### P1.7 NeoForge

上游证据：`templates:neoforge/.mcdev.template.json`。

- [ ] Kotlin 与 KotlinForForge。
- [ ] 动态 NeoForge、NeoGradle、ModDevGradle 和 Parchment 版本。
- [ ] MC >= 1.20.5 限制，MC 1.21+ 使用 ModDevGradle。
- [ ] `<1.21`、`1.21..<1.21.3`、`>=1.21.3` 三套 Config 模板。
- [ ] MC 1.21.4+ datagen 使用 `clientData()`。
- [ ] MC 1.20.2+ Mixin JSON 不写 refmap。
- [ ] 生成 `assets/<modid>/lang/en_us.json`。
- [ ] 使用 `src/main/templates/META-INF/neoforge.mods.toml` 及资源展开。

验收：Java/Kotlin 和三个版本断点均有生成测试，至少两个组合真实构建。

### P1.8 Architectury

上游证据：`templates:architectury/.mcdev.template.json`。

现状：本地原生生成器固定 common/Fabric/Forge，要求调用者自行提供兼容版本；上游按 MC 版本在 Forge 和 NeoForge 中二选一。

- [ ] 实现 `architectury_versions` 复合版本解析，不再由用户手工拼版本。
- [ ] MC <= 1.20.4 生成 Forge，MC >= 1.20.5 生成 NeoForge。
- [ ] settings、`enabled_platforms`、manifest 和源码目录随平台条件变化。
- [ ] Fabric API 与 Architectury API 均可关闭。
- [ ] 公共 Mixin、许可证、作者、网站和描述。
- [ ] NeoForge 模块真实构建验证。

验收：1.20.1 生成 Fabric+Forge，1.21.x 生成 Fabric+NeoForge，两者都能构建。

### P1.9 Multiloader

上游证据：`templates:multiloader/.mcdev.template.json`。

这是上游独立模板，不等同于 Architectury。

- [ ] 在官方模板向导中完整支持 Multiloader 复合属性。
- [ ] 评估是否加入原生 `multiloader` 平台注册项。
- [ ] 生成 common、Fabric、Forge、NeoForge 和 `buildSrc` convention plugins。
- [ ] 生成 SPI 接口、`Services`、平台 helper、服务注册文件和平台 Mixin。
- [ ] 执行 wrapper 与 `genIntellijRuns` finalizer。

验收：无需手写复合 JSON 即可生成上游 Multiloader 模板，并完成四模块构建。

## P1：补齐官方模板协议

上游模型：`MinecraftDev:src/main/kotlin/creator/custom/TemplateDescriptor.kt`。

### 属性系统

- [ ] 完整实现 `semantic_version`、`license`、`maven_artifact_version`、`gradle_plugin`。
- [ ] 完整实现 `paper_versions`、`fabric_versions`、`forge_versions`、`neoforge_versions`、`architectury_versions`、`parchment`。
- [ ] 实现 `remember`、`forceValue`、`warning`、`editable`、`nullIfDefault`。
- [ ] 实现 group/collapsible UI，而不是只 flatten。
- [ ] 实现 `limit`、`forceDropdown`、`maxSegmentedButtonsCount` 的 Neovim 等价行为。
- [ ] 校验 required property、descriptor schema、派生依赖顺序和未知类型。

### 派生系统

- [ ] `replace`。
- [ ] `select`。
- [ ] `suggestClassName`。
- [ ] `recommendJavaVersionForMcVersion`。
- [ ] `extractVersionMajorMinor`。
- [ ] `extractPaperApiVersion`。
- [ ] `fetchPaperDependencyVersionForMcVersion`。

验收：上游十个 descriptor 可直接交给向导，不出现“请手输 JSON”的降级流程。

### 文件与 finalizer

- [ ] 实现 `reformat` 的可配置格式化行为。
- [ ] 实现 `openInEditor`，生成后打开目标文件。
- [ ] 消费 `.nvim/minecraft-dev-runs.json`，提供列出和执行 Gradle/Maven run 的命令。
- [ ] 支持 `select` 语义，生成后选中默认 run。
- [ ] 为 import finalizer 提供稳定公开事件和文档。
- [ ] finalizer 失败、取消和超时必须进入统一生成结果。

验收：Paper/Velocity 的 Build 与 Run finalizer 在 Neovim 中可发现、可执行、可取消。

### Provider

- [ ] builtin 自动更新可配置，并支持打包模板回退。
- [ ] remote 支持 ZIP 内部路径和 `$version` 替换。
- [ ] remote 支持 None、Basic、Bearer、Git HTTP account、自定义 Header 认证。
- [ ] Git/ZIP 缓存增加 TTL、离线策略和 commit/tag 固定。
- [ ] 路径限制解析符号链接，防止 symlink 逃逸。
- [ ] 支持 `messages.properties` 和 locale-specific 消息。

验收：恶意 ZIP、恶意 symlink、认证失败、离线缓存和更新失败均有回归测试。

## P2：版本、JDK 与生成基础设施

- [ ] 建立统一版本服务，按平台返回 MC、API、Loader、构建插件和 Java 兼容组合。
- [ ] Java language level 与实际 JDK 选择分离。
- [ ] Gradle wrapper 版本由模板/平台版本矩阵决定，不使用单一全局值解决全部平台。
- [ ] `pack_format`、Mixin compatibility、loader requirement 由 MC 版本派生。
- [ ] 目标目录检查：存在、非空、可写、覆盖确认。
- [ ] 使用 staging 目录和原子移动，生成失败自动回滚。
- [ ] 修复 `group_id` 非法时错误字段错误报告为 `package_name`。
- [ ] 校验 Java 关键字、mod/plugin ID、side、URL、作者和依赖列表类型。
- [ ] 统一网络超时、重试、缓存和取消机制。

## P2：向导与文档

- [ ] 统一平台、构建系统、版本、语言、可选功能的异步向导。
- [ ] 支持返回上一步、生成摘要、覆盖确认、进度和取消。
- [ ] 记忆上次选择，但允许配置关闭。
- [ ] README 列出真实支持的平台、字段 schema、外部工具和 JDK 要求。
- [x] 更新 `:GmcPro` usage；当前文案仍只列 Fabric/Paper。
- [ ] 文档区分“原生生成器支持”和“官方模板协议支持”。

## 非项目生成的上游能力队列

这些能力由上游 `src/main/resources/META-INF/plugin.xml` 和对应 Kotlin 模块确认。本轮不展开实现任务，完成项目生成主线后应分别建立设计文档。

- [ ] Mixin：selector/descriptor 解析、注入点补全、目标导航、line marker、MixinExtras、配置文件引用和大量 inspections。
- [ ] MCP/mappings：ForgeGradle、Fabric Loom、VanillaGradle 数据导入，反混淆堆栈、源码反编译与附加。
- [ ] Access Transformer、Access Widener、Class Tweaker：语法高亮、补全、跳转和诊断。
- [ ] NBT/NBTT：二进制 NBT 读写、压缩格式选择、文本编辑、语法高亮、格式化和 folding。
- [ ] Minecraft 翻译：`.lang`/JSON key 补全、引用、重命名、查找使用、缺失/重复诊断和排序。
- [ ] 平台识别：根据依赖和 manifest 自动识别 Bukkit、Sponge、Forge、NeoForge、Fabric 等项目。
- [ ] 事件开发体验：listener 标记、事件处理器补全、事件代码生成、取消状态检查。
- [ ] 平台 inspections：Mixin、Sponge、Bukkit、Forge 等平台规则和快速修复。
- [ ] Adventure/Sponge 颜色预览和 Minecraft 颜色标记。

优先级建议：先做能复用现有 LSP/tree-sitter 的 manifest、Mixin JSON、AT/AW 补全与导航；NBT 编辑器和完整 Java inspections 属于独立大型项目。

## 不应误判为上游缺口

- Fabric Maven：本地存在未接入的 archetype 和旧 TODO，但当前上游 Fabric 模板只支持 Gradle。它可以作为额外功能，不应列为上游对标阻塞项。
- Waterfall：当前上游仓库模板没有独立 Waterfall；Waterfall 仅存在旧式向导。本地已有 Waterfall 原生生成器，属于额外兼容能力。
- 通用 Bukkit：上游新模板体系主要暴露 Paper 与 Spigot；是否保留 Bukkit 独立入口应单独决策。
- IntelliJ Project View、SDK 选择器和 IDE run configuration 无法一比一复制，应实现 Neovim 等价工作流，而不是模拟 IntelliJ UI。

## 推荐实施顺序

1. 完成 P0.1-P0.5，确保所有“支持”都能被自动证明。
2. 完整实现官方模板属性类型和派生系统，让上游十个模板先在 `:MinecraftDevNew` 可用。
3. 深化 Paper、Fabric、NeoForge、Architectury、Multiloader，这五项覆盖最多上游高级语义。
4. 补齐 Velocity、Forge、Sponge、BungeeCord/Waterfall、Spigot 的版本和插件选项。
5. 完成 provider 安全、run 执行器、统一向导和用户文档。

## 主要上游证据

- `minecraft-dev/templates:bukkit/paper.mcdev.template.json`
- `minecraft-dev/templates:fabric/.mcdev.template.json`
- `minecraft-dev/templates:forge/.mcdev.template.json`
- `minecraft-dev/templates:neoforge/.mcdev.template.json`
- `minecraft-dev/templates:architectury/.mcdev.template.json`
- `minecraft-dev/templates:multiloader/.mcdev.template.json`
- `minecraft-dev/templates:velocity/.mcdev.template.json`
- `minecraft-dev/MinecraftDev:src/main/kotlin/creator/custom/TemplateDescriptor.kt`
- `minecraft-dev/MinecraftDev:src/main/kotlin/creator/custom/types/`
- `minecraft-dev/MinecraftDev:src/main/kotlin/creator/custom/derivation/`
- `minecraft-dev/MinecraftDev:src/main/kotlin/creator/custom/finalizers/`
