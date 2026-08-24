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
| Translation 编辑与诊断 | 待实现 | 重复项、空白 key、默认 locale 对齐、format 参数、deprecated key、跳转/引用 |
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
- [ ] 默认 locale 差异、format 参数和 deprecated key 诊断
- [ ] translation key 跳转、引用查找和补全入口
- [x] README、配置和帮助文档
- [x] Neovim MCP 目标测试与完整快速回归

## 阶段 3：项目元数据与配置文件

- [ ] `plugin.yml` / `paper-plugin.yml` 结构、类引用和依赖诊断
- [ ] `mods.toml` / `neoforge.mods.toml` 结构、版本范围和 mod id 诊断
- [ ] `fabric.mod.json` entrypoint、mixin config、资源路径和依赖诊断
- [ ] Mixin JSON config package、class、required fields 和 compatibilityLevel 诊断
- [ ] 为确定字段提供补全、hover 或跳转入口
- [ ] 每种文件均添加 fixture、错误路径和 Neovim MCP 场景

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
