local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local path_util = require("minecraft-dev.util.path")
local templates = require("minecraft-dev.generators.paper.templates")
local version_util = require("minecraft-dev.version")
local options = require("minecraft-dev.generators.paper.options")
local bukkit_platform = require("minecraft-dev.generators.bukkit.platform")

local M = {}

---@param project_path string
---@param version string
function M.generate(project_path, version, language, spec)
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local result
	options.with_language(language, function(selected_language)
		if version_util.resolve_family(mc_version) == "v1_13_plus" then
			result = M.generate_higher(project_path, mc_version, selected_language, spec)
			return
		end
		result = M.generate_lower(project_path, mc_version, selected_language, spec)
	end)
	return result
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
	pom_template = bukkit_platform.transform_maven(pom_template, spec and spec.platform or "paper", ctx.version)
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	fs.write_file(
		path_util.join(resources_dir, bukkit_platform.manifest_name(spec)),
		bukkit_platform.build_manifest(ctx, spec)
	)

	write_main(ctx, lang, "v1_13_plus/Main.java", src_dir)

	return true
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
	pom_template = bukkit_platform.transform_maven(pom_template, spec and spec.platform or "paper", ctx.version)
	local pom_content = string.format(pom_template, ctx.groupId, ctx.artifactId, ctx.artifactId, ctx.version)
	fs.write_file(path_util.join(path, "pom.xml"), pom_content)

	fs.write_file(
		path_util.join(resources_dir, bukkit_platform.manifest_name(spec)),
		bukkit_platform.build_manifest(ctx, spec)
	)

	write_main(ctx, lang, "v1_8/Main.java", src_dir)

	return true
end
return M
