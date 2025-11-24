M = {}

function M.get_archetype_dir()
	local archetype_dir = vim.api.nvim_get_runtime_file("lua/minecraft-dev/archetype/", false)[1]
	if not archetype_dir then
		error("could not find the archetype source_dir")
		return nil
	end
	return archetype_dir
end

return M
