local template = require("minecraft-dev.util.template")

local M = {}

---@param build_tool "gradle"|"maven"
---@param sub_path string
---@return string
function M.read(build_tool, sub_path)
	return template.read_runtime_file(string.format("archetype/paper_%s/%s", build_tool, sub_path))
end

return M
