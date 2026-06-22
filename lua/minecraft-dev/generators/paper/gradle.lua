local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local notify = require("minecraft-dev.util.notify")
local path_util = require("minecraft-dev.util.path")
local templates = require("minecraft-dev.generators.paper.templates")
local version_util = require("minecraft-dev.version")
local gradle_util = require("minecraft-dev.util.gradle")
local choices = require("minecraft-dev.util.make_your_choice")

local M = {}

--- generate entry
---@param project_path string
---@param version string
function M.generate(project_path, version)
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	choices.which_paper_language(function(language)
		local family = version_util.resolve_family(mc_version)

		if family == "v1_13_plus" then
			M.generate_higher(project_path, mc_version, language)
			return
		end
		M.generate_lower(project_path, mc_version, language)
	end)
end

---@param ctx ProjectContext
---@param lang ProgrammingLanguage
---@return string
local function source_root(ctx, lang)
	local source_lang = lang == "kotlin" and "kotlin" or "java"
	return path_util.join(ctx.path, "src/main", source_lang, ctx.package_path)
end

---@param ctx ProjectContext
---@param lang ProgrammingLanguage
local function write_main(ctx, lang, template_path, src_dir)
	if lang == "kotlin" then
		local main_template = templates.read("gradle", "Main.kt", lang)
		local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
		fs.write_file(path_util.join(src_dir, ctx.main .. ".kt"), main_content)
		return
	end

	local main_template = templates.read("gradle", template_path, lang)
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)
end

---@param project_path string
---@param version string
function M.generate_higher(project_path, version, language)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local lang = language or require("minecraft-dev").config.defaults.paper.language
	local ctx = context.collect()
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = lang

	local src_dir = source_root(ctx, lang)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local build_gradle_template = templates.read("gradle", "v1_13_plus/build.gradle.kts", lang)
	fs.write_file(
		path_util.join(path, "build.gradle.kts"),
		string.format(build_gradle_template, ctx.groupId, ctx.artifactId, ctx.version)
	)

	local settings_gradle_template = templates.read("gradle", "v1_13_plus/settings.gradle")
	fs.write_file(path_util.join(path, "settings.gradle"), string.format(settings_gradle_template, ctx.artifactId))

	local plugin_template = templates.read("gradle", "v1_13_plus/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	write_main(ctx, lang, "v1_13_plus/Main.java", src_dir)
	gradle_util.generate_gradlew(path)

	notify.notify(vim.log.levels.INFO, { "paper", "generated_gradle_high" }, path)
end

---@param project_path string
---@param version string
function M.generate_lower(project_path, version, language)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local lang = language or require("minecraft-dev").config.defaults.paper.language
	local ctx = context.collect()
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = lang

	local src_dir = source_root(ctx, lang)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local build_gradle_template = templates.read("gradle", "1.13-/build.gradle", lang)
	fs.write_file(
		path_util.join(path, "build.gradle"),
		string.format(build_gradle_template, ctx.groupId, ctx.artifactId, ctx.version)
	)

	local settings_gradle_template = templates.read("gradle", "1.13-/settings.gradle")
	fs.write_file(path_util.join(path, "settings.gradle"), string.format(settings_gradle_template, ctx.artifactId))

	local plugin_template = templates.read("gradle", "1.13-/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	write_main(ctx, lang, "1.13-/Main.java", src_dir)

	gradle_util.generate_gradlew(path)
	notify.notify(vim.log.levels.INFO, { "paper", "generated_gradle_low" }, path)
end
return M
