local M = {}
local notify = require("minecraft-dev.util.notify")

function M.run(build_tool, path, version, spec)
	if build_tool == "gradle" then
		notify.notify(vim.log.levels.INFO, { "fabric", "generating_gradle" })
		return require("minecraft-dev.generators.fabric.gradle").generate(path, version, spec)
	elseif build_tool == "maven" then
		notify.notify(vim.log.levels.WARN, { "fabric", "maven_unsupported" })
	else
		notify.notify(vim.log.levels.ERROR, { "command", "unsupported_build" }, tostring(build_tool))
	end
end

return M
