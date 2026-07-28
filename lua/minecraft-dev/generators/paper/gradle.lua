local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local path_util = require("minecraft-dev.util.path")
local templates = require("minecraft-dev.generators.paper.templates")
local version_util = require("minecraft-dev.version")
local gradle_util = require("minecraft-dev.util.gradle")
local options = require("minecraft-dev.generators.paper.options")
local bukkit_platform = require("minecraft-dev.generators.bukkit.platform")

local M = {}

--- generate entry
---@param project_path string
---@param version string
function M.generate(project_path, version, language, spec, platform_name)
	local mc_version = version or require("minecraft-dev").config.defaults.paper.version
	local operation
	options.with_language(language, function(selected_language)
		local family = version_util.resolve_family(mc_version)

		if family == "v1_13_plus" then
			operation = M.generate_higher(project_path, mc_version, selected_language, spec, platform_name)
			return
		end
		operation = M.generate_lower(project_path, mc_version, selected_language, spec, platform_name)
	end)
	return operation
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
function M.generate_higher(project_path, version, language, spec, platform_name)
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

	local build_gradle_template = templates.read("gradle", "v1_13_plus/build.gradle.kts", lang)
	build_gradle_template = bukkit_platform.transform_gradle(build_gradle_template, platform_name or (spec and spec.platform) or "paper", ctx.version)
	local plugin_version = spec and spec.plugin_version or "1.0.0"
	fs.write_file(
		path_util.join(path, "build.gradle.kts"),
		string.format(build_gradle_template, ctx.groupId, plugin_version, ctx.version)
	)

	local settings_gradle_template = templates.read("gradle", "v1_13_plus/settings.gradle")
	fs.write_file(path_util.join(path, "settings.gradle"), string.format(settings_gradle_template, ctx.artifactId))

	fs.write_file(
		path_util.join(resources_dir, bukkit_platform.manifest_name(spec)),
		bukkit_platform.build_manifest(ctx, spec)
	)

	write_main(ctx, lang, "v1_13_plus/Main.java", src_dir)
	local operation = gradle_util.generate_gradlew(path)

	return operation
end

---@param project_path string
---@param version string
function M.generate_lower(project_path, version, language, spec, platform_name)
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

	local build_gradle_template = templates.read("gradle", "1.13-/build.gradle", lang)
	build_gradle_template = bukkit_platform.transform_gradle(build_gradle_template, platform_name or (spec and spec.platform) or "paper", ctx.version)
	local plugin_version = spec and spec.plugin_version or "1.0.0"
	fs.write_file(
		path_util.join(path, "build.gradle"),
		string.format(build_gradle_template, ctx.groupId, plugin_version, ctx.version)
	)

	local settings_gradle_template = templates.read("gradle", "1.13-/settings.gradle")
	fs.write_file(path_util.join(path, "settings.gradle"), string.format(settings_gradle_template, ctx.artifactId))

	fs.write_file(
		path_util.join(resources_dir, bukkit_platform.manifest_name(spec)),
		bukkit_platform.build_manifest(ctx, spec)
	)

	write_main(ctx, lang, "1.13-/Main.java", src_dir)

	local operation = gradle_util.generate_gradlew(path)
	return operation
end
return M
