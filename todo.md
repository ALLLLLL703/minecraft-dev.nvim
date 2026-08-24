# MinecraftDev 功能补全总路线图

上游基线：`minecraft-dev/MinecraftDev@52a49b87f8b07751557a78969c07772b6d196119`（1.8.20）。

完成标准：每个上游能力必须归入“已实现”“由 Neovim/LSP 现有能力覆盖”或“IntelliJ 专属、不适用”之一；可迁移项只有在实现、文档、目标测试和已连接 Neovim MCP 场景均通过后才能勾选。

## 阶段 1：能力矩阵与边界

- [x] 固定上游提交，并通过 GitHub MCP 读取 `plugin.xml`、Kotlin/TOML/YAML 扩展声明和源码模块
- [x] 通过本地 CodeGraph 盘点当前公共 API、命令和项目生成路径
- [ ] 对每个功能组补齐源码级证据与最终状态
- [ ] 对 IntelliJ PSI、Facet、Project Model、IDE update/error reporter 能力写出不适用依据

### 功能组状态

| 功能组 | 当前状态 | Neovim 对标结果 |
| --- | --- | --- |
| Creator / 平台项目生成 | 已实现 | Paper、Spigot、BungeeCord、Waterfall、Velocity、Sponge、Fabric、Forge、NeoForge、Architectury、自定义 descriptor |
| Translation 排序 | 已实现 | JSON / `.lang` 的 ascending、descending、like-default、project template |
| Translation 编辑与诊断 | 已实现 | 重复项、空白 key、默认 locale 对齐、format 参数、deprecated key、跳转、补全与有界引用查找 |
| Bukkit / Forge / Fabric 元数据 | 待实现 | `plugin.yml`、`mods.toml`、`fabric.mod.json` 的结构诊断、补全与引用 |
| Mixin config 与源码智能 | 待实现 | config 诊断、target 跳转、查找 mixin、生成 accessor/overwrite/shadow/soft-implements |
| MCP mappings / AT / AW / coremod | 待实现 | 查映射、复制/跳转 Access Transformer、Access Widener、coremod target |
| NBT | 待实现 | 二进制 NBT 与文本视图互转、编辑、校验和安全写回 |
| Event / class generation | 待实现 | event listener、Minecraft class 和平台入口生成 |
| Color / line markers | 待分类 | 优先复用 LSP、Tree-sitter 和 Neovim highlight；仅补 Minecraft 语义差异 |
| Facet / IDE project model | 待分类 | 预期为 IntelliJ 专属；以文件系统、Gradle/Maven/LSP 能力替代 |
| IDE update / error reporter | 待分类 | 预期不适用；插件管理和崩溃上报由 Neovim 生态负责 |

## 阶段 2：Translations 完整能力

- [x] JSON ascending、descending、like-default 排序
- [x] `.lang` 文件识别、解析、排序和确定性写回
- [x] project template 解析与 `template` 排序模式
- [x] 保留 `.lang` 注释、空行和尾部换行
- [x] 重复 key、空白 key、无效行诊断与安全失败
- [x] 默认 locale 差异、format 参数和 deprecated key 诊断
- [x] translation key 跳转、引用查找和补全入口
- [x] README、配置和帮助文档
- [x] Neovim MCP 目标测试与完整快速回归

### P2.3：Translation 文件诊断（已完成）

- [x] 读取上游 `TranslationFileAnnotator` 与 inspection 语义
- [x] 确认 Neovim diagnostic/autocmd 官方 API 与依赖边界
- [x] 为 JSON / `.lang` 建立带位置的 entry 模型
- [x] 诊断重复 key、首尾空白、残缺 `.lang` 行和非法 value
- [x] 对非默认 locale 诊断默认文件缺失的 key 与 format 签名差异
- [x] 注册自动诊断生命周期与公开手动入口
- [x] 添加本地化、配置、README 和目标场景测试
- [x] 通过 LSP MCP、Neovim MCP 和静态检查

### P2.4：Translation 索引、跳转与补全（已完成）

- [x] 读取上游 index、reference、completion 和 usages 实现
- [x] 确认本地 filesystem/root API 与依赖边界
- [x] 建立项目 default locale 索引并隔离 namespace
- [x] 提供 key 列表、缺失 key completion 和精确位置
- [x] 实现当前 key / 显式 key 跳转与命令补全
- [x] 注册不覆盖 LSP omnifunc 的 `completefunc` 入口
- [x] 添加配置、消息、README 与场景测试
- [x] 通过 LSP MCP、Neovim MCP 和静态检查

### P2.5：源码 translation 调用点（已完成）

- [x] 读取上游 `TranslationIdentifier`、源码 inspections 与 deprecated 语义
- [x] 验证已连接 Neovim 的 Java / Kotlin parser 并确认当前 nvim-treesitter 安装 API
- [x] 用 Tree-sitter 识别受支持调用的首个常量字符串参数
- [x] 诊断缺失 key、缺少/多余 format 参数和 deprecated key
- [x] 让现有 goto 从 Java / Kotlin 字符串跳到 default locale
- [x] parser 缺失或动态 key 时安全跳过并返回结构化状态
- [x] 添加配置、消息、README 与 Java/Kotlin 场景
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

### P2.6：Translation 引用查找（已完成）

- [x] 汇总项目内所有 locale entry 与受支持 Java/Kotlin 常量调用
- [x] 从显式 key、translation entry 或源码调用推断查询 key
- [x] 提供结构化 locations 与 quickfix 命令入口
- [x] 隔离 parser 缺失、损坏 translation 文件和扫描上限 warnings
- [x] 添加 README、消息与多文件场景测试
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

## 阶段 3：项目元数据与配置文件

- [x] `plugin.yml` / `paper-plugin.yml` 结构、类引用和依赖诊断
- [ ] `mods.toml` / `neoforge.mods.toml` 结构、版本范围和 mod id 诊断
- [x] `fabric.mod.json` entrypoint、mixin config、资源路径和依赖诊断
- [x] Mixin JSON config package、class、required fields 和 compatibilityLevel 诊断
- [ ] 为确定字段提供补全、hover 或跳转入口
- [ ] 每种文件均添加 fixture、错误路径和 Neovim MCP 场景

### P3.1：Bukkit / Paper 主类引用（已完成）

- [x] 对齐上游 `PluginYmlInspection` 与 `PluginYmlReferenceContributor` 的 `main` 语义
- [x] 建立可复用的 Java / Kotlin 项目 class index 与本地继承链解析
- [x] 诊断缺少、无效、无法解析或非 Bukkit Plugin 的 `main`
- [x] 提供 main class completion、跳转和公开 Lua API
- [x] 为 `plugin.yml` / `paper-plugin.yml` 注册隔离 diagnostics 生命周期
- [x] 添加配置、消息、README 与 Java/Kotlin/无 parser 场景
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

### P3.2：Bukkit / Paper manifest 结构与依赖（已完成）

- [x] 固定 Paper 官方 `plugin.yml` / `paper-plugin.yml` 字段与依赖语义
- [x] 建立保留位置、类型和重复 key 的通用 YAML Tree-sitter 文档模型
- [x] 诊断必填字段、标量/映射/序列类型和 `api-version` 语法
- [x] 诊断 depend/softdepend/loadbefore 重复、自依赖与错误 item
- [x] 诊断 Paper bootstrap/server dependency 的 load/required/join-classpath
- [x] 添加配置消息、README 与两类 manifest 场景
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

### P3.3：Forge / NeoForge TOML metadata（已完成）

- [x] 通过 GitHub MCP 固定上游 schema、inspection、reference 与 completion 语义
- [x] 建立保留 table path、值类型与位置的 TOML Tree-sitter 文档模型
- [x] 诊断 mod id、字段类型、displayTest/ordering/side 枚举与依赖 table 目标
- [x] 提供 mod id 与 logoFile 的结构化跳转及上下文补全
- [x] 接入公开 API、配置消息、buffer diagnostics 生命周期和 README
- [x] 覆盖 Forge、NeoForge、placeholder、资源路径、parser 错误和 setup 幂等
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

### P3.4：Fabric mod JSON metadata（已完成）

- [x] 通过 GitHub MCP 固定上游 entrypoint、resource、license reference 与 inspection 语义
- [x] 通过 Context7 固定 Fabric 官方必填字段、类型、environment 与 resource 字段语义
- [x] 建立保留 object/array/value 位置和重复 key 的通用 JSON Tree-sitter 文档模型
- [x] 诊断必填字段、mod id、schemaVersion、字段类型、environment 和 dependency 值
- [x] 解析 entrypoint class/member，校验 initializer 类型、可见性、参数和构造器
- [x] 解析 mixin config、accessWidener、icon 与 LICENSE 资源引用
- [x] 提供 entrypoint/resource 跳转、补全、公开 API、命令、README 和使用文档
- [x] 覆盖 Java/Kotlin、object entrypoint、member syntax、资源错误、parser 错误和 setup 幂等
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

### P3.5：Mixin config JSON metadata（已完成）

- [x] 通过 GitHub MCP 固定上游 config model、package/plugin/class/compatibilityLevel reference 与 value inspection 语义
- [x] 识别 `mixins*.json` / JSON5 作用域并复用位置保真的 JSON 模型
- [x] 诊断 package、required、compatibilityLevel、mixins/client/server 与常用字段类型
- [x] 解析 package-relative Java/Kotlin Mixin class、plugin class 与本地继承/注解证据
- [x] 提供 Mixin class/plugin 跳转和按 package/side 过滤的补全
- [x] 接入公开 API、命令、README、namespace 与幂等 autocmd
- [x] 覆盖 Java/Kotlin、重复/错误字段、无法解析、parser 缺失和真实 Neovim buffer
- [x] 通过 LSP MCP、Neovim MCP 与静态检查

## 阶段 4：NBT 与资源编辑

- [ ] 确定维护型 NBT 依赖或记录自实现边界
- [ ] 读取 gzip、zlib 和未压缩二进制 NBT
- [ ] 提供可编辑文本表示和结构校验
- [ ] 原子、安全地写回原压缩格式
- [ ] 覆盖未知 tag、损坏输入、深度/大小限制和取消路径
- [ ] Neovim MCP 打开、编辑、保存和重载验证

## 阶段 5：Mixin、Mappings 与源码动作

- [ ] 盘点可由 JDTLS/Kotlin LSP/Tree-sitter 提供的语义，避免重复实现
- [ ] 实现 mapping lookup 与 SRG 名称查询
- [ ] 实现 AT/AW/coremod target 复制、跳转和重复项诊断
- [ ] 实现 Mixin target 查找与引用复制
- [ ] 实现 accessor、overwrite、shadow、soft-implements 的安全生成动作
- [ ] 实现可迁移的 event listener 与 Minecraft class 生成
- [ ] 为无 LSP、符号歧义、只读 buffer 和不完整项目添加失败场景

## 阶段 6：最终审计与收尾

- [ ] 对总矩阵逐行关闭，不保留“待分类”或“待实现”
- [ ] 运行全部快速测试和代表性集成场景
- [ ] 通过已连接 Neovim MCP 验证命令、buffer 状态、diagnostics、跳转和保存
- [ ] 审查公开 API、配置兼容、本地化和帮助文档
- [ ] 记录所有 IntelliJ 专属不适用项及其 Neovim 等价能力
- [ ] 检查目标 diff，不纳入用户已有的无关工作树修改

## 已完成验证

- P2.1 JSON translation：`test_refactor.lua: ok`、`translation smoke: ok`，Neovim MCP 健康且最终为 normal mode。
- P2.1 静态检查：生产 Lua 通过 Stylua check，目标 diff 通过 `git diff --check`。
- P2.2 `.lang` / template：Neovim MCP `test_refactor.lua: ok`，命令补全和真实 buffer 写回场景通过，最终为 normal mode。
- P2.2 静态检查：目标生产 Lua 通过 Stylua check，目标 diff 通过 `git diff --check`；LSP MCP 对 `translations.lua` 返回零诊断。
- P2.3 文件 diagnostics：JSON / `.lang` 位置、默认 locale、format、namespace 隔离和 autocmd 幂等场景均由 Neovim MCP 完整回归覆盖；核心三个 Lua 文件的 LSP MCP diagnostics 为零。
- P2.4 translation index：多 namespace、损坏文件隔离、completion 排除、光标/显式跳转、命令补全和 augroup 幂等场景通过 Neovim MCP；`translation_index.lua` 与公开入口的 LSP MCP diagnostics 为零。
- P2.5 source usage：Java/Kotlin call、非 translation 同名方法排除、动态 key 跳过、format 数量、deprecated key、源码 goto 和 parser 缺失场景通过 Neovim MCP；核心四个 Lua 模块的 LSP MCP diagnostics 为零。
- P2.6 usage lookup：所有 locale 与已加载/磁盘 Java/Kotlin source、两类光标推断、损坏文件隔离、扫描上限、稳定排序和 quickfix 场景通过 Neovim MCP；核心五个 Lua 模块的 LSP MCP diagnostics 为零，`command.lua` 仅保留本阶段外的既有 nil-check warnings。
- P3.1 Bukkit/Paper main：Java/Kotlin、本地继承链、抽象/错误/未知类型、未保存 buffer、扫描截断、quoted YAML、completion、goto、parser 缺失和 augroup 幂等通过 Neovim MCP；`jvm_index.lua`、`bukkit_metadata.lua`、配置和公开入口的 LSP MCP diagnostics 为零。
- P3.2 Bukkit/Paper manifest：通用 YAML Tree-sitter model、重复 key、字段类型、legacy dependency、自依赖、Paper bootstrap/server load/boolean 与 malformed YAML 场景通过 Neovim MCP；三个生产 Lua 模块的 LSP MCP diagnostics 为零，Stylua 与目标 diff 检查通过。
- P3.3 Forge/NeoForge TOML：Tree-sitter document model、schema/type/mod id/version range/enum/dependency owner diagnostics、Java/Kotlin `@Mod` 常量索引、manifest/source/logo 跳转、字段文档补全、placeholder 与 parser failure 场景通过 Neovim MCP；目标生产 Lua 的 LSP MCP diagnostics、Stylua 与 diff 检查通过。
- P3.4 Fabric mod JSON：Tree-sitter document model、required/schema/id/environment/dependency diagnostics、Java/Kotlin class/member entrypoint 规则、mixin/accessWidener/icon/license 引用、跳转与类型过滤补全场景通过 Neovim MCP；目标生产 Lua 的 LSP MCP diagnostics、Stylua 与 diff 检查通过。
- P3.5 Mixin config：JSON/JSON5 scope、field/package/compatibility diagnostics、Java/Kotlin `@Mixin` 与 plugin interface 索引、relative jump 和 mixin/plugin/package/compatibility completion 场景通过 Neovim MCP；目标生产 Lua 的 LSP MCP diagnostics、Stylua 与 diff 检查通过。
