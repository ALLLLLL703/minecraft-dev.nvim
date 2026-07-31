local forge_native = require("minecraft-dev.generators.forge.native")
local neoforge_native = require("minecraft-dev.generators.neoforge.native")

local M = {}

function M.run(_, project_path, _, spec, platform_name)
	if (platform_name or spec.platform) == "forge" then return forge_native.run(project_path, spec) end
	return neoforge_native.run(project_path, spec)
end

return M
