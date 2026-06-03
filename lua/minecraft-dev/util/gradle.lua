local M = {}
local notify = require("minecraft-dev.util.notify")

---@param project_path string
function M.generate_gradlew(project_path)
	if not vim.fn.executable("gradle") then
		notify.notify(vim.log.levels.ERROR, { "gradle", "missing" })
		return
	end

	notify.notify(vim.log.levels.INFO, { "gradle", "generating" })

	vim.system({ "gradle", "wrapper" }, { cwd = project_path }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				notify.notify(vim.log.levels.ERROR, { "gradle", "failed" }, result.stderr or "")
				return
			end
			notify.notify(vim.log.levels.INFO, { "gradle", "success" })
		end)
	end)
end

return M
