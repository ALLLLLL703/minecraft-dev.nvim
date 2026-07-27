local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local notify = require("minecraft-dev.util.notify")
local path_util = require("minecraft-dev.util.path")
local templates = require("minecraft-dev.generators.paper.templates")
local version_util = require("minecraft-dev.version")
local options = require("minecraft-dev.generators.paper.options")

local M = {}

---@param project_path string
---@param version string
function M.generate(project_path, version, language, spec)
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	options.with_language(language, function(selected_language)
		if version_util.resolve_family(mc_version) == "v1_13_plus" then
			M.generate_higher(project_path, mc_version, selected_language, spec)
			return
		end
		M.generate_lower(project_path, mc_version, selected_language, spec)
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
---@param template_path string
---@param src_dir string
local function write_main(ctx, lang, template_path, src_dir)
	if lang == "kotlin" then
		local main_template = templates.read("maven", "Main.kt", lang)
		local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
		fs.write_file(path_util.join(src_dir, ctx.main .. ".kt"), main_content)
		return
	end

	local main_template = templates.read("maven", template_path, lang)
	local main_content = string.format(main_template, ctx.package, ctx.main, ctx.main, ctx.main)
	fs.write_file(path_util.join(src_dir, ctx.main .. ".java"), main_content)
end

---@param project_path string
---@param version string
function M.generate_higher(project_path, version, language, spec)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local lang = language or require("minecraft-dev").config.defaults.paper.language

	local ctx = context.collect(spec)
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = lang

	local src_dir = source_root(ctx, lang)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local pom_template = templates.read("maven", "v1_13_plus/pom.xml", lang)
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	local plugin_template = templates.read("maven", "v1_13_plus/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	write_main(ctx, lang, "v1_13_plus/Main.java", src_dir)

	notify.notify(vim.log.levels.INFO, { "paper", "generated_maven" }, path, mc_version)
end

---@param project_path string
---@param version string
function M.generate_lower(project_path, version, language, spec)
	local path = project_path or vim.fn.getcwd()
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local lang = language or require("minecraft-dev").config.defaults.paper.language

	local ctx = context.collect(spec)
	ctx.path = path
	ctx.version = mc_version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = lang

	local src_dir = source_root(ctx, lang)
	fs.mkdir(src_dir)
	local resources_dir = path_util.join(path, "src/main/resources")
	fs.mkdir(resources_dir)

	local pom_template = templates.read("maven", "v1_8/pom.xml", lang)
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	local plugin_template = templates.read("maven", "v1_8/plugin.yml")
	local plugin_content = string.format(plugin_template, ctx.artifactId, ctx.package, ctx.main, ctx.version)
	fs.write_file(path_util.join(resources_dir, "plugin.yml"), plugin_content)

	write_main(ctx, lang, "v1_8/Main.java", src_dir)

	notify.notify(vim.log.levels.INFO, { "paper", "generated_maven" }, path, mc_version)
end
return M
