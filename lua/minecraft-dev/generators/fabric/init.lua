local M = {}

---Todo
function M.run(build_tool, path, version)
	if build_tool == "gradle" then
		vim.notify("generating fabric mc project in gradle")
		require("minecraft-dev.generators.fabric.gradle").generate(path, version)
	elseif build_tool == "maven" then
		vim.notify("fabric template of maven is not supportted")
	end
end

return M
