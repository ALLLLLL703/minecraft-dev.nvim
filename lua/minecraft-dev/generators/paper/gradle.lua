local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local notify = require("minecraft-dev.util.notify")
local path_util = require("minecraft-dev.util.path")
local templates = require("minecraft-dev.generators.paper.templates")
local version_util = require("minecraft-dev.version")
local gradle_util = require("minecraft-dev.util.gradle")

local M = {}

--- generate entry
---@param project_path string
---@param version string
function M.generate(project_path, version)
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local family = version_util.resolve_family(mc_version)

	if family == "v1_13_plus" then
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

	local build_gradle_template = templates.read("gradle", "v1_13_plus/build.gradle.kts")
	fs.write_file(
		path_util.join(path, "build.gradle.kts"),
		string.format(build_gradle_template, ctx.groupId, ctx.artifactId, ctx.version)
	)

	local settings_gradle_template = templates.read("gradle", "v1_13_plus/settings.gradle")
	fs.write_file(path_util.join(path, "settings.gradle"), string.format(settings_gradle_template, ctx.artifactId))

	local plugin_template = templates.read("gradle", "v1_13_plus/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	local main_template = templates.read("gradle", "v1_13_plus/Main.java")
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)
	gradle_util.generate_gradlew(path)

	notify.notify(vim.log.levels.INFO, { "paper", "generated_gradle_high" }, path)
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

	local build_gradle_template = templates.read("gradle", "1.13-/build.gradle")
	fs.write_file(
		path_util.join(path, "build.gradle"),
		string.format(build_gradle_template, ctx.groupId, ctx.artifactId, ctx.version)
	)

	local settings_gradle_template = templates.read("gradle", "1.13-/settings.gradle")
	fs.write_file(path_util.join(path, "settings.gradle"), string.format(settings_gradle_template, ctx.artifactId))

	local plugin_template = templates.read("gradle", "1.13-/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	local main_template = templates.read("gradle", "1.13-/Main.java")
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)

	gradle_util.generate_gradlew(path)
	notify.notify(vim.log.levels.INFO, { "paper", "generated_gradle_low" }, path)
end
return M
