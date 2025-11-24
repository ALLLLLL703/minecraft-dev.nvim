local M = {}

function M.generate_basic(path) end

local function get_archetype_dir()
	local archetype_dir = vim.api.nvim_get_runtime_file("lua/minecraft-dev/archetype/", false)[1]
	if not archetype_dir then
		error("could not find the archetype source_dir")
		return nil
	end
	return archetype_dir
end

function M.handle_paper_maven(path)
	local root_src = "/src/main/java/"
	local groupId = vim.fn.input("GroupId:", "com.example")
	local artifactId = vim.fn.input("artifactId:", "artifact")
	local main_file = vim.fn.input("main file name:", "Main")
	---@type string projectId
	local projectId = groupId .. "." .. artifactId
	local second_src = projectId:gsub("%.", "/")
	local archetype_dir = get_archetype_dir()
	if not archetype_dir then
		return nil
	end

	local source_dir = "/src/main/resource/plugin.yml"
	local Mainid = groupId .. artifactId .. main_file
	local full_src = path .. root_src .. second_src

	vim.fn.mkdir(full_src, "p")
end

function M.handle_paper_gradle(path) end

function M.handle_paper(pkm, path)
	if not pkm then
		print("please specify maven or gradle")
		return nil
	end
	if not path then
		path = vim.fn.getcwd()
	end
	print(pkm)
	print(path)
	if pkm == "maven" then
		M.handle_paper_maven(path)
	end
end

return M
