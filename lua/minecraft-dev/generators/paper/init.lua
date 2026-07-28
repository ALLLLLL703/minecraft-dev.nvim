local M = {}
local notify = require("minecraft-dev.util.notify")

function M.run(build, path, version, spec)
	path = path or vim.fn.getcwd()

	if build == "maven" then
		return require("minecraft-dev.generators.paper.maven").generate(path, version, spec and spec.language, spec)
	elseif build == "gradle" then
		return require("minecraft-dev.generators.paper.gradle").generate(path, version, spec and spec.language, spec)
	end

	notify.notify(vim.log.levels.ERROR, { "command", "unsupported_build" }, tostring(build))
end

return M
