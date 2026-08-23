# MinecraftDev 缺失功能对标与实现

## 阶段 1：建立能力差异

- [x] 通过本地代码图整理当前插件的公共功能与生成能力
- [x] 通过 GitHub MCP 固定 MinecraftDev 上游提交与功能目录
- [x] 对照两端能力，列出可移植、需 Neovim 适配和不适用的差异
- [x] 选择现代 JSON translation 排序作为首个完整缺失功能

## 阶段 2：设计实现切片

- [x] 把目标行为、模块边界、依赖决策和测试场景写入 `style.md`
- [x] 确认相关 Neovim 官方 API 行为
- [x] 为缺失行为添加可在旧实现上失败的场景测试

## 阶段 3：实现缺失功能

- [x] 完成公共 API 与最小完整实现
- [x] 同步命令入口、配置归一化和本地化消息
- [x] 更新 README 和 Lua API 示例

## 阶段 4：验证与收尾

- [x] 通过 Neovim MCP 运行 translation 目标场景测试
- [x] 通过 Neovim MCP 运行完整 `test/test_refactor.lua` 快速回归
- [x] 验证插件加载、用户命令、补全和 Neovim normal mode 状态
- [x] 检查目标 diff，不改动无关工作树内容
- [x] 记录上游证据、验证结果、兼容影响和剩余风险

## 验证记录

- 上游基线：`minecraft-dev/MinecraftDev@52a49b87f8b07751557a78969c07772b6d196119`。
- Neovim MCP：`test_refactor.lua: ok`、`translation smoke: ok`、连接健康且最终处于 normal mode。
- 静态检查：生产 Lua 文件通过 Stylua check，目标 diff 通过 `git diff --check`。
- LSP MCP：Lua workspace 初始化未在一分钟内返回，已按 MCP 回退规则停止等待；真实 Neovim 测试作为最终验证证据。
- 兼容边界：本阶段仅支持现代 JSON translation；旧版 `.lang`、项目排序模板、translation inspection/索引尚未实现。
