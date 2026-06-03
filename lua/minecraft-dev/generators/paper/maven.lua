local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local notify = require("minecraft-dev.util.notify")
local path_util = require("minecraft-dev.util.path")
local templates = require("minecraft-dev.generators.paper.templates")
local version_util = require("minecraft-dev.version")

local M = {}

---@param project_path string
---@param version string
function M.generate(project_path, version)
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	if version_util.resolve_family(mc_version) == "v1_13_plus" then
		M.generate_higher(project_path, mc_version)
		return
	end
	M.generate_lower(project_path, mc_version)
end

---@param project_path string
---@param version string
function M.generate_higher(project_path, version)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version

	local ctx = context.collect()
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")

	local src_dir = path_util.join(path, "src/main/java", ctx.package_path)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local pom_template = templates.read("maven", "v1_13_plus/pom.xml")
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	local plugin_template = templates.read("maven", "v1_13_plus/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	local main_template = templates.read("maven", "v1_13_plus/Main.java")
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)

	notify.notify(vim.log.levels.INFO, { "paper", "generated_maven" }, path, mc_version)
end

---@param project_path string
---@param version string
function M.generate_lower(project_path, version)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version

	local ctx = context.collect()
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")

	local src_dir = path_util.join(path, "src/main/java", ctx.package_path)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local pom_template = templates.read("maven", "v1_8/pom.xml")
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	local plugin_template = templates.read("maven", "v1_8/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	local main_template = templates.read("maven", "v1_8/Main.java")
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)

	notify.notify(vim.log.levels.INFO, { "paper", "generated_maven" }, path, mc_version)
end
return M
