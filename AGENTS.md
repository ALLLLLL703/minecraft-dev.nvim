# 仓库代理说明

- 每个任务开始前读取 `agent-instructions/PROJECT.md`，了解项目目标、边界和仓库地图。
- 每个任务都读取 `agent-instructions/GENERAL.md`。
- 每个任务都读取 `agent-instructions/MCP.md`，按任务类型选择 MCP、记录证据并执行回退。
- 每个任务都读取 `agent-instructions/COLLABORATION.md`；只有用户明确说明多个代理共享同一工作树时，才启用其中的协作流程。
- 修改源码、测试、模板或配置前读取 `agent-instructions/STYLE.md`。
- 实现、调试、测试、上游同步或 Git 操作涉及对应流程时，读取 `agent-instructions/WORKFLOW.md`。
- 编写实现计划前读取 `agent-instructions/PLAN.md`。
- 审查变更前读取 `agent-instructions/REVIEW.md`。
- 更深目录中的 `AGENTS.md`、`STYLE.md` 或 `DESIGN.md` 可补充本文件；冲突时以作用域更具体的规则为准。
- 同一规则只在一个说明文件中维护；其他文件应引用它，不得复制后形成多个事实来源。
