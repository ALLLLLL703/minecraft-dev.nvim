# MinecraftDev 上游功能对照

基线：`minecraft-dev/MinecraftDev@52a49b87f8b07751557a78969c07772b6d196119`（1.8.20）。

本表按用户可见能力归并上游 `plugin.xml`、`mcdev-kotlin.xml`、`mcdev-toml.xml`、`mcdev-yaml.xml` 和对应源码目录。完成状态只有三种：本插件已实现、由 Neovim/构建工具生态覆盖、IntelliJ 平台专属且不适用。当前项目的 `.nvim.lua` 仍明确禁用 Java/Kotlin LSP；下文提到 LSP 是跨项目的等价能力说明，不会修改这一项目级决定。

| 上游功能组 | 状态 | 本仓库结果或边界 |
| --- | --- | --- |
| Minecraft project creator | 已实现 | Paper、Spigot、BungeeCord、Waterfall、Velocity、Sponge、Fabric、Forge、NeoForge、Architectury；Gradle/Maven、Java/Kotlin 和版本解析均由 generators/project 实现 |
| Custom creator descriptors | 已实现 | v1-v3 descriptor、builtin/remote/local/archive provider、property derivation、finalizer、取消和 staging/lock 安全边界 |
| Translation sorting/editing | 已实现 | JSON、`.lang`、template 排序，默认 locale、format、deprecated、源码调用、引用、跳转、补全和 diagnostics |
| Bukkit/Paper metadata | 已实现 | `plugin.yml`/`paper-plugin.yml` 结构、依赖、main class、补全与跳转 |
| Forge/NeoForge metadata | 已实现 | `mods.toml`/`neoforge.mods.toml` schema、mod id、版本范围、依赖、资源、source reference |
| Fabric metadata | 已实现 | `fabric.mod.json` entrypoint、class/member、mixin/access widener/icon/license、补全与跳转 |
| Mixin config | 已实现 | JSON/JSON5 config、package/class/plugin/compatibility、side、注册、补全与跳转 |
| NBT editor | 已实现 | gzip/zlib/raw NBT、全部 tag、typed JSON、限制保护、取消、原压缩和权限保留的原子写回 |
| MCP mappings、AT、AW、coremod | 已实现 | SRG/TSRG/Tiny v2 双向查找；target 复制、补全、重复诊断与源码跳转 |
| Mixin source actions | 已实现 | target 查找、accessor/invoker/shadow/overwrite/soft-implements、精确 JVM descriptor 与失败不改 buffer |
| Event listener generation | 已实现 | Bukkit、BungeeCord、Forge、NeoForge、Velocity、Sponge 的 Java/Kotlin method、priority/order/cancelled 和 Listener interface |
| Minecraft class templates | 已实现 | Forge/Fabric/NeoForge 的 block/item/enchantment/effect/packet Java skeleton；Forge 按 1.17/1.18 边界选模板 |
| Chat color insight | 已实现 | Bukkit、BungeeCord、Sponge、Adventure/Kyori、mapped Minecraft 标准颜色引用使用 buffer extmark 高亮 |
| Listener source inspection | 已实现 | Bukkit/BungeeCord `@EventHandler` class 的本地继承链 Listener 诊断；未知外部继承链安全跳过 |
| Event/plugin/color gutter UI | 生态覆盖 | 上游 `ColorLineMarkerProvider`、`ListenerLineMarkerProvider`、`PluginLineMarkerProvider` 的可迁移颜色/Listener 语义已实现；点击式 gutter、Swing color picker 和 badge 由 Neovim statuscolumn、colorizer、icon 插件承担 |
| File icons、project-tree decorator | 生态覆盖 | `*FileIconProvider` 和 `MinecraftProjectViewNodeDecorator` 只扩展 IntelliJ Project View；Neovim 文件图标/文件树插件负责显示，不复制第二套图标系统 |
| Java/Kotlin declaration、reference、ordinary completion | 生态覆盖 | 类型检查、`gd`、rename、普通补全和 unused analysis 属于 Java/Kotlin LSP/编译器；本插件只提供 Minecraft metadata、mapping、event 和 Mixin 特有入口 |
| Bukkit event handler completion | 已实现/生态覆盖 | `MinecraftDevGenerateEventListener` 提供平台 method skeleton；事件 class 列表和继承解析属于 JVM classpath/LSP，不扫描 Gradle cache 猜类型 |
| Fabric entrypoint inspections/references | 已实现 | 对应 `FabricEntrypointsInspection` 和 unresolved resource/class reference 已进入 Fabric metadata diagnostics |
| Sponge injection/getter/logger inspections | IntelliJ 专属，不适用 | `SpongeInjectionInspection`、getter type/target、implicit usage 和 logger inspection 依赖完整 JVM PSI、resolved annotation target 与 dependency classpath；由编译器/LSP 检查，插件不在无 LSP 模式伪造类型解析 |
| Forge SideOnly/SimpleImpl inspections | IntelliJ 专属，不适用 | 依赖 IntelliJ Java data-flow、版本 Facet 和 resolved call graph，且覆盖旧 Forge API；编译器、现代 Forge API 和 JVM LSP 是等价检查面 |
| Entity data / cancelled-flow / stack-empty inspections | IntelliJ 专属，不适用 | `WrongEntityDataParameterClassInspection`、`IsCancelledInspection`、`StackEmptyInspection` 需要 resolved inheritance、控制流或字节码栈分析，不可由可靠的局部 Tree-sitter 语法判断替代 |
| Deep Mixin selector/injector inspections | IntelliJ 专属，不适用 | selector、injection point、local capture、MixinExtras expression/flow、shadow/overwrite target 检查依赖 IntelliJ PSI/UAST、反编译 bytecode、control-flow 和 library index；编译器、Mixin annotation processor、JVM LSP 提供构建期/类型层等价面 |
| Mixin completion/folding/Javadoc | 生态覆盖 | ordinary annotation/member completion 和 Javadoc 由 LSP；folding 由 Tree-sitter `foldexpr`；本插件保留 config/target/action 的 Minecraft 特有 completion，不覆盖 omnifunc |
| Mixin/MCP debugger integration | IntelliJ 专属，不适用 | `MixinPositionManager`、debugger class filter、mouse-ungrab session listener 和 run-configuration extension绑定 IntelliJ Java debugger；Neovim 使用 nvim-dap/DAP adapter，插件不修改调试器位置管理器 |
| MixinExtras flow diagram | IntelliJ 专属，不适用 | 上游 action 是基于 IntelliJ UAST/control-flow 的 Swing 图；没有可靠 bytecode/data-flow 输入时不生成近似图 |
| Facet、module detector、library kind | IntelliJ 专属，不适用 | `MinecraftFacet*`、`LibraryPresentationProviders` 和 module-root listener 是 IntelliJ Project Model；本插件用 filesystem root、manifest、Gradle/Maven 文件和显式配置识别上下文 |
| Gradle project resolver extensions | IntelliJ 专属，不适用 | MCP、VanillaGradle、Fabric Loom、Architectury resolver 注入 IntelliJ Gradle import；Neovim 直接使用 Gradle/Maven、LSP workspace 或生成后的项目文件 |
| Run configurations | 已实现/生态覆盖 | creator finalizer 和 generators 写出 `.nvim/minecraft-dev-runs.json`；实际执行由 terminal、task runner 或 nvim-dap 完成 |
| IDE settings/configurable pages | 生态覆盖 | 上游 `MinecraftConfigurable`/project settings 是 IntelliJ Settings UI；本插件使用可版本控制的 `setup()` 和项目级 `.nvim.lua` |
| Plugin update channels | IntelliJ 专属，不适用 | `PluginUpdater`/Configure Updates 操作 IntelliJ PluginManager；Neovim 插件管理器和本仓库 Git remote 管理版本 |
| IDE error reporter | IntelliJ 专属，不适用 | `ErrorReporter` 实现 IntelliJ ErrorReportSubmitter/collaboration API；Neovim 的日志、`:checkhealth` 与 issue tracker 是对应通道 |
| Registry keys、macros、notification groups | IntelliJ 专属，不适用 | 这些对象绑定 IntelliJ Registry、run configuration macro 和 Notification API；本插件使用 Lua config、structured results 与 `vim.notify` |

## 深层 Mixin 边界

上游 `platform/mixin` 不只是文本规则：其 handler、inspection、expression、debug 和 reference 层会读取已解析 Java PSI、依赖库 class、反编译方法 bytecode、局部变量表、控制流和 IntelliJ debugger position manager。仅靠当前 buffer 的 Tree-sitter 语法无法可靠回答 injector 是否命中、局部捕获 slot 是否正确或 MixinExtras expression 的运行时流向。

因此本插件实现可在 Neovim 内确定且可测试的部分：config、class target、JVM descriptor、mapping/access target、查找与安全生成；需要 classpath/bytecode/control-flow 的部分明确交给构建工具、Mixin annotation processor、可选 JVM LSP 和 DAP adapter。该边界避免在用户已关闭 Java/Kotlin LSP 的项目里扫描 Gradle cache、启动隐式 JVM 或产生伪 diagnostics。

## 编辑器 UI 边界

上游 color/listener/plugin line marker 中，颜色解析和 Listener 约束属于 Minecraft 语义，已迁移为 extmark 和 diagnostics。点击 gutter、Swing chooser、文件/模块图标、project tree decorator、settings dialog、folding presentation 属于宿主编辑器外观。本插件复用 Neovim extmark、diagnostic、Tree-sitter、statuscolumn、LSP 和插件管理生态，不复制 IntelliJ UI 框架。
