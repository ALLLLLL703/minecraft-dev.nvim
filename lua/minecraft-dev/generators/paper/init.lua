local M = {}
local notify = require("minecraft-dev.util.notify")

function M.run(build, path, version)
	path = path or vim.fn.getcwd()

	if build == "maven" then
		require("minecraft-dev.generators.paper.maven").generate(path, version)
		return
	elseif build == "gradle" then
		require("minecraft-dev.generators.paper.gradle").generate(path, version)
		return
	end

	notify.notify(vim.log.levels.ERROR, { "command", "unsupported_build" }, tostring(build))
end

return M
