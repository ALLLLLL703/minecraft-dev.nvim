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
---@param spec? table
function M.generate(project_path, version, spec)
	local config = require("minecraft-dev").config
	local mc_version = version or config.defaults.fabric.version
	local function generate(generator_options)
		if version_util.resolve_family(mc_version) == "v1_13_plus" then
			if generator_options.language == "java" then
				return M.generate_higher_java(project_path, mc_version, generator_options, spec)
			elseif generator_options.language == "kotlin" then
				return M.generate_higher_kotlin(project_path, mc_version, generator_options, spec)
			end
		end
		notify.notify(vim.log.levels.ERROR, { "fabric", "lower_version_unsupported" })
	end

	if spec then
		return generate({
			language = spec.language,
			side = spec.side or config.defaults.fabric.side,
			generate_datagen = spec.generate_datagen == nil and config.defaults.fabric.generate_datagen
				or spec.generate_datagen,
			use_mixins = spec.use_mixins == nil and config.defaults.fabric.use_mixins or spec.use_mixins,
			loom_version = spec.loom_version,
			gradle_version = spec.gradle_version,
			kotlin_loader_version = spec.kotlin_loader_version,
			version_data = spec.fabric_version_data,
		})
	end
	return options.collect(generate)
end

---@param ctx ProjectContext
---@param generator_options FabricGenerationOptions
local function generate_basic(ctx, generator_options)
	local config = require("minecraft-dev").config
	local json_data_table = generator_options.version_data or version_data.read(ctx.version)
	local resources_dir = path_util.join(ctx.path, "src/main/resources")
	fs.mkdir(resources_dir)
	if generator_options.side ~= "server" or generator_options.generate_datagen then
		local resources_client_dir = path_util.join(ctx.path, "src/client/resources")
		fs.mkdir(resources_client_dir)
	end

	local explicit_loom_version = generator_options.loom_version ~= nil
	local default_loom_version = json_data_table.loom_version or config.defaults.fabric.version_data.loom_version
	local fabric_loom_version = generator_options.loom_version or json_data_table.loom_version
	if not fabric_loom_version then
		fabric_loom_version = input_util.not_empty_or(
			vim.fn.input(config.prompts.fabric.loom_version, default_loom_version),
			default_loom_version
		)
	end
	if not explicit_loom_version and not generator_options.gradle_version then
		generator_options.gradle_version = json_data_table.gradle_version
			or config.defaults.fabric.version_data.gradle_version
	end
	local kotlin_loader_version = generator_options.kotlin_loader_version
		or json_data_table.kotlin_loader
		or config.defaults.fabric.version_data.kotlin_loader
	generator_options.kotlin_loader_version = kotlin_loader_version
	if ctx.lang == "kotlin" then
		local kotlin_version = assert(kotlin_loader_version:match("%+kotlin%.(.+)$"), "invalid Fabric Language Kotlin version")
		local build_gradle_content = templates.read("build.gradle.kts", ctx.lang)
		fs.write_file(
			path_util.join(ctx.path, "build.gradle.kts"),
			string.format(build_gradle_content, kotlin_version, fabric_loom_version, kotlin_loader_version)
		)
	else
		local build_gradle_content = templates.read("build.gradle", ctx.lang)
		fs.write_file(path_util.join(ctx.path, "build.gradle"), string.format(build_gradle_content))
	end

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
			json_data_table.yarn,
			kotlin_loader_version
		)
	)

	local settings_name = ctx.lang == "kotlin" and "settings.gradle.kts" or "settings.gradle"
	local settings_gradle_content = templates.read(settings_name, ctx.lang)
	fs.write_file(path_util.join(ctx.path, settings_name), string.format(settings_gradle_content))

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
function M.generate_higher_kotlin(project_path, version, generator_options, spec)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect(spec)
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
		local source_set = generator_options.side == "client" and "client" or "main"
		local mixin_dir = path_util.join(ctx.path, "src", source_set, "kotlin", mixin_package_path)
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

	local operation = gradle_util.generate_gradlew(ctx.path, nil, generator_options.gradle_version)
	return operation
end

---the function that generate higher version of fabric gradle template
---@param project_path string
---@param version string
---@param generator_options FabricGenerationOptions
function M.generate_higher_java(project_path, version, generator_options, spec)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect(spec)
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
		local source_set = generator_options.side == "client" and "client" or "main"
		local mixin_dir = path_util.join(ctx.path, "src", source_set, "java", mixin_package_path)
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

	local operation = gradle_util.generate_gradlew(ctx.path, nil, generator_options.gradle_version)
	return operation
end

return M
