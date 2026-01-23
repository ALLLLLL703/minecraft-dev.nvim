local M = {}

function M.run(build, path, version)
	path = path or vim.fn.getcwd()

	if build == "maven" then
		require("minecraft-dev.generators.paper.maven").generate(path, version)
		return
	elseif build == "gradle" then
		require("minecraft-dev.generators.paper.gradle").generate(path, version)
		return
	end

	vim.notify("Unsupported build tool: " .. tostring(build), vim.log.levels.ERROR)
end

return M
