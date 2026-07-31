local template = require("minecraft-dev.util.template")

local M = {}

---@param sub_path string
---@return string
function M.read(sub_path)
	return template.read_runtime_file("archetype/forge_gradle/" .. sub_path)
end

return M
