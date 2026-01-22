local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local path_util = require("minecraft-dev.util.path")

local M = {}

local DEFAULT_VERSION = "1.21"

---function
---@param sub_path string
---@return string
local function read_template(sub_path)
	local files = vim.api.nvim_get_runtime_file("archetype/paper_maven/" .. sub_path, true)
	if #files == 0 then
		error("Template file not found: " .. sub_path)
	end

	local file = io.open(files[1], "r")
	if not file then
		error("Failed to open template file: " .. sub_path)
	end

	local content = file:read("*a")
	file:close()
	return content
end

function M.generate(project_path, version)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or DEFAULT_VERSION

	local ctx = context.collect()
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")

	local src_dir = path_util.join(path, "src/main/java", ctx.package_path)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local pom_template = read_template("pom.xml")
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	local plugin_template = read_template("plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	local main_template = read_template("Main.java")
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)

	vim.notify("Paper maven project generate at : " .. path .. "\n mc_version: " .. mc_version)
end

return M
