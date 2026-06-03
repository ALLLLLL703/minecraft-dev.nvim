local notify = require("minecraft-dev.util.notify")
local template = require("minecraft-dev.util.template")

local M = {}

---@class FabricVersionData
---@field loom_version string
---@field fabric_api string|string[]
---@field loader string
---@field yarn string?

---@return FabricVersionData
function M.default_data()
	return vim.deepcopy(require("minecraft-dev").config.defaults.fabric.version_data)
end

---@param version string
---@return FabricVersionData
function M.read(version)
	local runtime_path = "data/fabric/versions/" .. version .. ".json"
	local files = vim.api.nvim_get_runtime_file(runtime_path, true)
	if #files == 0 then
		notify.notify(vim.log.levels.WARN, { "data", "version_file_missing" }, version)
		return M.default_data()
	end

	local ok, content = pcall(template.read_runtime_file, runtime_path)
	if not ok then
		notify.notify(vim.log.levels.WARN, { "data", "version_file_open_failed" }, version)
		return M.default_data()
	end

	notify.debug({ "data", "reading_json" }, files[1])
	return vim.fn.json_decode(content)
end

return M
