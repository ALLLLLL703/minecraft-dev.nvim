# MCP 使用规则

## 基本原则

- 按任务类型选择信号最强的 MCP，先进行一次聚焦尝试。
- 首选 MCP 不可用、调用失败或覆盖不足时立即使用对应回退，不在同一失败上循环。
- 回退不是阻塞条件；交付时说明采用的 MCP、证据来源以及回退原因。
- 本地文件读取、构建、测试数据准备和 Git 工作树操作仍使用本地工具，但插件测试的执行入口必须遵循下文的 Neovim MCP 规则。

## 路由表

| 任务 | 首选 | 回退 |
| --- | --- | --- |
| 函数、调用链、数据流、架构 |  codegraph cli | 本地搜索和读取 |
| 代码符号重命名 | LSP MCP semantic rename | 手动编辑后运行语言检查 |
| 文件诊断 | LSP MCP diagnostics | 编译器、类型检查器或 linter |
| 文件符号大纲 | LSP MCP document symbols | codebase-memory MCP，再本地读取 |
| 定义和引用 | LSP MCP definition/references | codebase-memory MCP，再本地搜索 |
| 库、API、SDK、CLI 文档 | Context7 | Open WebSearch |
| GitHub 仓库文件、提交、issue、PR、release | GitHub MCP | Open WebSearch，再使用 `gh` |
| 公共网页、当前信息和兼容问题 | Open WebSearch | 定向 HTTP 获取 |

## 代码与 LSP

- codegraph cli 用于宽范围代码发现、调用路径、数据流和架构分析；查找代码定义和关系时不得先用文本搜索。
- 使用 LSP MCP 前初始化正确的 workspace 和文档。语言服务器不可用、不支持目标语言或结果不足时，使用路由表中的回退。
- 重命名优先使用 LSP rename，应用前检查完整 workspace edit，应用后运行项目的编译、测试或 linter。
- LSP diagnostics 只代表编辑器状态；同步文件并获取诊断后，仍需使用项目常规验证流程确认变更。

## 远程 GitHub 与 MinecraftDev 上游

- 查看远程 `minecraft-dev/MinecraftDev` 及其 templates 仓库时必须先使用 GitHub MCP，不使用本地 `git`、网页搜索或 `gh` 代替首次尝试。
- 读取上游文件使用 GitHub MCP repository contents；定位远程实现使用 GitHub MCP code search；检查基线使用 commit、tag 或 release 工具。
- 上游同步和行为对标应记录仓库、ref 或 commit SHA，以及实际读取的文件路径。
- GitHub MCP 覆盖不足或失败时，按路由表回退，并说明失败原因。普通 Git 传输和本地工作树操作不受此条限制。

## Neovim 插件测试

- 所有插件测试通过项目配置的 Neovim MCP 在已连接的 Neovim 实例中执行，不手动启动额外 Neovim 实例。
- 测试前先调用 Neovim MCP health/status，确认连接正常且当前工作目录为本仓库。
- 使用 Neovim MCP command 从仓库根目录执行测试入口，并收集退出状态和输出；不得仅以 MCP 连接成功代替插件测试通过。
- 命令、配置、插件加载或启动路径变化后，还需通过同一实例验证插件可加载、用户命令可用且没有错误循环或 hit-enter 阻塞。
- Neovim MCP 不可用时停止测试并报告环境阻塞，不得违反本仓库工作流另起 Neovim 进程伪装验证结果。

## 文档与公开资料

- Context7 只用于库、工具和 API 文档，不用于任意网页研究。
- Neovim API 以目标版本的官方帮助和官方文档为准；Context7 不替代项目要求的官方 Neovim 资料核对。
- Open WebSearch 用于具体错误、兼容问题和当前解决方案；引用结论时保留来源证据。
