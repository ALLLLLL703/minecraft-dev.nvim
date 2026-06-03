local notify = require("minecraft-dev.util.notify")

local M = {}

---@param runtime_path string
---@return string
function M.read_runtime_file(runtime_path)
	local files = vim.api.nvim_get_runtime_file(runtime_path, true)
	if #files == 0 then
		error(notify.message({ "template", "missing" }, runtime_path))
	end

	local file = io.open(files[1], "r")
	if not file then
		error(notify.message({ "template", "open_failed" }, runtime_path))
	end

	notify.debug({ "template", "reading" }, files[1])

	local content = file:read("*a")
	file:close()
	return content
end

return M
