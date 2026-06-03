---@diagnostic disable: unused-function
local M = {}
local context = require("minecraft-dev.context")
local input_util = require("minecraft-dev.util.input")
local fs = require("minecraft-dev.util.fs")
local notify = require("minecraft-dev.util.notify")
local path_util = require("minecraft-dev.util.path")
local metadata = require("minecraft-dev.generators.fabric.metadata")
local options = require("minecraft-dev.generators.fabric.options")
local templates = require("minecraft-dev.generators.fabric.templates")
local version_util = require("minecraft-dev.version")
local gradle_util = require("minecraft-dev.util.gradle")
local version_data = require("minecraft-dev.generators.fabric.version_data")

---@param project_path string
---@param version string
function M.generate(project_path, version)
	local config = require("minecraft-dev").config
	local mc_version = version or config.defaults.fabric.version
	options.collect(function(generator_options)
		if version_util.resolve_family(mc_version) == "v1_13_plus" then
			if generator_options.language == "java" then
				M.generate_higher_java(project_path, mc_version, generator_options)
				return
			elseif generator_options.language == "kotlin" then
				M.generate_higher_kotlin(project_path, mc_version, generator_options)
				return
			end
		end
		notify.notify(vim.log.levels.ERROR, { "fabric", "lower_version_unsupported" })
	end)
end

---@param ctx ProjectContext
---@param generator_options FabricGenerationOptions
local function generate_basic(ctx, generator_options)
	local config = require("minecraft-dev").config
	local json_data_table = version_data.read(ctx.version)
	local resources_dir = path_util.join(ctx.path, "src/main/resources")
	fs.mkdir(resources_dir)
	if generator_options.side ~= "server" or generator_options.generate_datagen then
		local resources_client_dir = path_util.join(ctx.path, "src/client/resources")
		fs.mkdir(resources_client_dir)
	end

	local build_gradle_content = templates.read("build.gradle", ctx.lang)
	fs.write_file(path_util.join(ctx.path, "build.gradle"), string.format(build_gradle_content))
	local default_loom_version = json_data_table.loom_version or config.defaults.fabric.version_data.loom_version
	local fabric_loom_version = input_util.not_empty_or(
		vim.fn.input(config.prompts.fabric.loom_version, default_loom_version),
		default_loom_version
	)

	local gradle_properties_content = templates.read("gradle.properties", ctx.lang)
	local fabric_api = json_data_table.fabric_api
	if type(fabric_api) == "table" then
		fabric_api = fabric_api[1]
	end

	fs.write_file(
		path_util.join(ctx.path, "gradle.properties"),
		string.format(
			gradle_properties_content,
			ctx.version,
			json_data_table.loader,
			ctx.groupId,
			ctx.artifactId,
			fabric_api,
			fabric_loom_version,
			json_data_table.yarn
		)
	)

	local settings_gradle_content = templates.read("settings.gradle", ctx.lang)
	fs.write_file(path_util.join(ctx.path, "settings.gradle"), string.format(settings_gradle_content))

	fs.write_file(path_util.join(resources_dir, "fabric.mod.json"), metadata.build_mod_json(ctx, generator_options))

	if generator_options.use_mixins then
		fs.write_file(
			path_util.join(resources_dir, ctx.artifactId .. ".mixins.json"),
			metadata.build_mixins_json(ctx, generator_options)
		)
	end
end

---@param project_path string
---@param version string
---@param generator_options FabricGenerationOptions
function M.generate_higher_kotlin(project_path, version, generator_options)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect()
	ctx.path = path
	ctx.version = version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = "kotlin"

	local package_main_dir
	if generator_options.side ~= "client" then
		local src_dir = path_util.join(ctx.path, "src/main/kotlin")
		fs.mkdir(src_dir)
		package_main_dir = path_util.join(src_dir, ctx.package_path)
		fs.mkdir(package_main_dir)
	end

	local package_client_dir
	if generator_options.side ~= "server" or generator_options.generate_datagen then
		local src_client_dir = path_util.join(ctx.path, "src/client/kotlin")
		fs.mkdir(src_client_dir)
		package_client_dir = path_util.join(src_client_dir, ctx.package_path)
		fs.mkdir(package_client_dir)
	end

	generate_basic(ctx, generator_options)
	if generator_options.side ~= "server" then
		local kotlin_client_content = templates.read("Client.kt", ctx.lang)
		fs.write_file(
			path_util.join(package_client_dir, ctx.main .. "Client.kt"),
			string.format(kotlin_client_content, ctx.package, ctx.main)
		)
	end

	if generator_options.side ~= "client" then
		local kotlin_server_content = templates.read("Main.kt", ctx.lang)
		fs.write_file(
			path_util.join(package_main_dir, ctx.main .. ".kt"),
			string.format(kotlin_server_content, ctx.package, ctx.main)
		)
	end

	if generator_options.generate_datagen then
		local datagen_template = templates.read("Data.kt", ctx.lang)
		fs.write_file(
			path_util.join(package_client_dir, ctx.main .. "DataGenerator.kt"),
			string.format(datagen_template, ctx.package, ctx.main)
		)
	end

	if generator_options.use_mixins then
		local mixin_package_path = metadata.mixin_package(ctx, generator_options):gsub("%.", "/")
		local mixin_dir = path_util.join(ctx.path, "src/main/kotlin", mixin_package_path)
		fs.mkdir(mixin_dir)
		local mixin_template = templates.read("Mixin.kt", ctx.lang)
		fs.write_file(
			path_util.join(mixin_dir, metadata.mixin_class_name(ctx) .. ".kt"),
			string.format(
				mixin_template,
				metadata.mixin_package(ctx, generator_options),
				metadata.mixin_target_class(ctx, generator_options),
				metadata.mixin_class_name(ctx),
				metadata.mixin_target_method(ctx, generator_options)
			)
		)
	end

	gradle_util.generate_gradlew(ctx.path)
	notify.notify(vim.log.levels.INFO, { "fabric", "generated" })
end

---the function that generate higher version of fabric gradle template
---@param project_path string
---@param version string
---@param generator_options FabricGenerationOptions
function M.generate_higher_java(project_path, version, generator_options)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect()
	ctx.path = path
	ctx.version = version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = "java"

	local src_client_dir
	if generator_options.side ~= "server" or generator_options.generate_datagen then
		src_client_dir = path_util.join(ctx.path, "src/client/java", ctx.package_path)
		fs.mkdir(src_client_dir)
	end

	local src_dir
	if generator_options.side ~= "client" then
		src_dir = path_util.join(ctx.path, "src/main/java", ctx.package_path)
		fs.mkdir(src_dir)
	end

	generate_basic(ctx, generator_options)

	if generator_options.generate_datagen then
		local data_java_content = templates.read("Data.java", ctx.lang)
		fs.write_file(
			path_util.join(src_client_dir, metadata.datagen_class_name(ctx, generator_options) .. ".java"),
			string.format(data_java_content, ctx.package, ctx.main)
		)
	end

	if generator_options.side ~= "server" then
		local client_java_content = templates.read("Client.java", ctx.lang)
		fs.write_file(
			path_util.join(src_client_dir, metadata.client_class_name(ctx, generator_options) .. ".java"),
			string.format(client_java_content, ctx.package, ctx.main)
		)
	end

	if generator_options.side ~= "client" then
		local main_java_content = templates.read("Main.java", ctx.lang)
		fs.write_file(
			path_util.join(src_dir, metadata.main_class_name(ctx, generator_options) .. ".java"),
			string.format(main_java_content, ctx.package, ctx.main)
		)
	end

	if generator_options.use_mixins then
		local mixin_package_path = metadata.mixin_package(ctx, generator_options):gsub("%.", "/")
		local mixin_dir = path_util.join(ctx.path, "src/main/java", mixin_package_path)
		fs.mkdir(mixin_dir)
		local mixin_template = templates.read("Mixin.java", ctx.lang)
		fs.write_file(
			path_util.join(mixin_dir, metadata.mixin_class_name(ctx) .. ".java"),
			string.format(
				mixin_template,
				metadata.mixin_package(ctx, generator_options),
				metadata.mixin_target_class(ctx, generator_options),
				metadata.mixin_class_name(ctx),
				metadata.mixin_target_method(ctx, generator_options)
			)
		)
	end

	gradle_util.generate_gradlew(ctx.path)

	notify.notify(vim.log.levels.INFO, { "fabric", "generated" })
end

return M
