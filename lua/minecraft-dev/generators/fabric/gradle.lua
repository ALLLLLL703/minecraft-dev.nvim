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

local function option(value, default)
	return value == nil and default or value
end

local function normalized_options(mc_version, values)
	local defaults = require("minecraft-dev").config.defaults.fabric
	local side = values.side or defaults.side
	local split_sources = version_util.at_least(mc_version, 1, 18) and option(values.split_sources, defaults.split_sources)
	local use_fabric_api = option(values.use_fabric_api, defaults.use_fabric_api)
	local use_mixins = option(values.use_mixins, defaults.use_mixins)
	local client_mixins = use_mixins and split_sources and side ~= "server"
		and (side == "client" or option(values.client_mixins, defaults.client_mixins)) or false
	return vim.tbl_extend("force", values, {
		side = side,
		use_official_mappings = version_util.at_least(mc_version, 26, 1)
			or option(values.use_official_mappings, defaults.use_official_mappings),
		use_fabric_api = use_fabric_api,
		split_sources = split_sources,
		generate_datagen = use_fabric_api and option(values.generate_datagen, defaults.generate_datagen) or false,
		use_mixins = use_mixins,
		client_mixins = client_mixins,
		target_java_version = version_util.required_java(mc_version),
	})
end

local function replace_tokens(content, values)
	for token, value in pairs(values) do
		local replacement = tostring(value or ""):gsub("%%", "%%%%")
		content = content:gsub("__" .. token .. "__", replacement)
	end
	return content
end

local function build_script(ctx, generator_options, versions, loom_version, kotlin_version, kotlin_loader_version)
	local kotlin = ctx.lang == "kotlin"
	local modern = version_util.at_least(ctx.version, 26, 1)
	local loader_configuration = modern and "implementation" or "modImplementation"
	local loom_block = ""
	if generator_options.split_sources then
		if kotlin then
			loom_block = [[loom {
    splitEnvironmentSourceSets()

    mods {
        register(project.property("archives_base_name") as String) {
            sourceSet("main")
            sourceSet("client")
        }
    }
}]]
		else
			loom_block = [[loom {
    splitEnvironmentSourceSets()

    mods {
        "${project.archives_base_name}" {
            sourceSet sourceSets.main
            sourceSet sourceSets.client
        }
    }
}]]
		end
	end
	local datagen_block = ""
	if generator_options.generate_datagen then
		datagen_block = [[fabricApi {
    configureDataGeneration {
        client = true
    }
}]]
	end
	local mappings = ""
	if not modern then
		if generator_options.use_official_mappings then
			mappings = kotlin and "    mappings(loom.officialMojangMappings())" or "    mappings loom.officialMojangMappings()"
		else
			assert(type(versions.yarn) == "string" and versions.yarn ~= "", "Yarn mappings are required")
			mappings = kotlin and [[    mappings("net.fabricmc:yarn:${project.property("yarn_version")}:v2")]]
				or [[    mappings "net.fabricmc:yarn:${project.yarn_version}:v2"]]
		end
	end
	local fabric_api = ""
	if generator_options.use_fabric_api then
		fabric_api = kotlin and [[    ]] .. loader_configuration .. [[("net.fabricmc.fabric-api:fabric-api:${project.property("fabric_api_version")}")]]
			or [[    ]] .. loader_configuration .. [[ "net.fabricmc.fabric-api:fabric-api:${project.fabric_api_version}"]]
	end
	local content = templates.read(kotlin and "build.gradle.kts" or "build.gradle", ctx.lang)
	return replace_tokens(content, {
		KOTLIN_VERSION = kotlin_version,
		KOTLIN_LOADER_VERSION = kotlin_loader_version,
		LOOM_PLUGIN = modern and "net.fabricmc.fabric-loom" or "fabric-loom",
		LOOM_VERSION = loom_version,
		JAVA_VERSION = generator_options.target_java_version,
		LOOM_BLOCK = loom_block,
		DATAGEN_BLOCK = datagen_block,
		MAPPINGS_DEPENDENCY = mappings,
		LOADER_CONFIGURATION = loader_configuration,
		FABRIC_API_DEPENDENCY = fabric_api,
	})
end

local function write_mixin_source(ctx, generator_options, client)
	local mixin_package = metadata.mixin_package(ctx, generator_options, client)
	local source_set = client and "client" or "main"
	local mixin_dir = path_util.join(ctx.path, "src", source_set, ctx.lang, (mixin_package:gsub("%.", "/")))
	fs.mkdir(mixin_dir)
	local extension = ctx.lang == "kotlin" and ".kt" or ".java"
	local mixin_template = templates.read(ctx.lang == "kotlin" and "Mixin.kt" or "Mixin.java", ctx.lang)
	fs.write_file(
		path_util.join(mixin_dir, metadata.mixin_class_name(ctx, client) .. extension),
		string.format(
			mixin_template,
			mixin_package,
			metadata.mixin_target_class(ctx, generator_options, client),
			metadata.mixin_class_name(ctx, client),
			metadata.mixin_target_method(ctx, generator_options, client)
		)
	)
end

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
		return generate(normalized_options(mc_version, {
			language = spec.language,
			side = spec.side,
			generate_datagen = spec.generate_datagen,
			use_mixins = spec.use_mixins,
			use_official_mappings = spec.use_official_mappings,
			use_fabric_api = spec.use_fabric_api,
			split_sources = spec.split_sources,
			client_mixins = spec.client_mixins,
			loom_version = spec.loom_version,
			gradle_version = spec.gradle_version,
			kotlin_loader_version = spec.kotlin_loader_version,
			fabric_api_version = spec.fabric_api_version,
			yarn_version = spec.yarn_version,
			version_data = spec.fabric_version_data,
		}))
	end
	return options.collect(mc_version, function(values) generate(normalized_options(mc_version, values)) end)
end

---@param ctx ProjectContext
---@param generator_options FabricGenerationOptions
local function generate_basic(ctx, generator_options)
	local config = require("minecraft-dev").config
	local json_data_table = generator_options.version_data or version_data.read(ctx.version)
	generator_options.loader_version = json_data_table.loader
	local resources_dir = path_util.join(ctx.path, "src/main/resources")
	fs.mkdir(resources_dir)
	if generator_options.split_sources and (generator_options.side ~= "server" or generator_options.generate_datagen) then
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
	local kotlin_version
	if ctx.lang == "kotlin" then
		kotlin_version = assert(kotlin_loader_version:match("%+kotlin%.(.+)$"), "invalid Fabric Language Kotlin version")
	end
	local build_name = ctx.lang == "kotlin" and "build.gradle.kts" or "build.gradle"
	local build_versions = vim.deepcopy(json_data_table)
	build_versions.yarn = generator_options.yarn_version or build_versions.yarn
	fs.write_file(
		path_util.join(ctx.path, build_name),
		build_script(ctx, generator_options, build_versions, fabric_loom_version, kotlin_version, kotlin_loader_version)
	)

	local gradle_properties_content = templates.read("gradle.properties", ctx.lang)
	local fabric_api = generator_options.fabric_api_version or json_data_table.fabric_api
	if type(fabric_api) == "table" then
		fabric_api = fabric_api[1]
	end
	local yarn = generator_options.yarn_version or json_data_table.yarn
	if type(yarn) == "table" then yarn = yarn.name or yarn[1] end
	local gradle_properties = replace_tokens(gradle_properties_content, {
		MINECRAFT_VERSION = ctx.version,
		LOADER_VERSION = json_data_table.loader,
		MAVEN_GROUP = ctx.groupId,
		ARCHIVES_NAME = ctx.artifactId,
		FABRIC_API_PROPERTY = generator_options.use_fabric_api and "fabric_api_version=" .. tostring(fabric_api) or "",
		LOOM_VERSION = fabric_loom_version,
		YARN_PROPERTY = not generator_options.use_official_mappings and "yarn_version=" .. tostring(yarn) or "",
		KOTLIN_LOADER_VERSION = kotlin_loader_version,
	})
	fs.write_file(
		path_util.join(ctx.path, "gradle.properties"),
		gradle_properties
	)

	local settings_name = ctx.lang == "kotlin" and "settings.gradle.kts" or "settings.gradle"
	local settings_gradle_content = templates.read(settings_name, ctx.lang)
	fs.write_file(path_util.join(ctx.path, settings_name), string.format(settings_gradle_content))

	fs.write_file(path_util.join(resources_dir, "fabric.mod.json"), metadata.build_mod_json(ctx, generator_options))

	if generator_options.use_mixins then
		if generator_options.side ~= "client" or not generator_options.client_mixins then
			fs.write_file(
				path_util.join(resources_dir, ctx.artifactId .. ".mixins.json"),
				metadata.build_mixins_json(ctx, generator_options, false)
			)
		end
		if generator_options.client_mixins then
			local client_resources = path_util.join(ctx.path, "src/client/resources")
			fs.mkdir(client_resources)
			fs.write_file(
				path_util.join(client_resources, ctx.artifactId .. ".client.mixins.json"),
				metadata.build_mixins_json(ctx, generator_options, true)
			)
		end
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
	local client_source_set = generator_options.split_sources and "client" or "main"

	local package_main_dir
	if generator_options.side ~= "client" then
		local src_dir = path_util.join(ctx.path, "src/main/kotlin")
		fs.mkdir(src_dir)
		package_main_dir = path_util.join(src_dir, ctx.package_path)
		fs.mkdir(package_main_dir)
	end

	local package_client_dir
	if generator_options.side ~= "server" or generator_options.generate_datagen then
		local src_client_dir = path_util.join(ctx.path, "src", client_source_set, "kotlin")
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
		if generator_options.side ~= "client" or not generator_options.client_mixins then
			write_mixin_source(ctx, generator_options, false)
		end
		if generator_options.client_mixins then write_mixin_source(ctx, generator_options, true) end
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
	local client_source_set = generator_options.split_sources and "client" or "main"

	local src_client_dir
	if generator_options.side ~= "server" or generator_options.generate_datagen then
		src_client_dir = path_util.join(ctx.path, "src", client_source_set, "java", ctx.package_path)
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
		if generator_options.side ~= "client" or not generator_options.client_mixins then
			write_mixin_source(ctx, generator_options, false)
		end
		if generator_options.client_mixins then write_mixin_source(ctx, generator_options, true) end
	end

	local operation = gradle_util.generate_gradlew(ctx.path, nil, generator_options.gradle_version)
	return operation
end

return M
