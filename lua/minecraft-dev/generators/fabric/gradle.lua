---@diagnostic disable: unused-function
local M = {}
local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local path_util = require("minecraft-dev.util.path")
local version_util = require("minecraft-dev.version")
local gradle_util = require("minecraft-dev.util.gradle")
local choices = require("minecraft-dev.util.make_your_choice")
local lang = "java"
local DEFAULT_VERSION = "1.21"

---@class  FabricDefaultVersionData
---@field loom_version string
---@field fabric_api string
---@field loader string
---@field yarn string?
local default_value = {
	loom_version = "1.16-SNAPSHOT",
	fabric_api = "0.146.0+",
	loader = "0.19.2",
	yarn = nil,
}
local prompt_line = {
	loom_version = "loom version?",
}
---nothing
---@param sub_path string
---@param lang_? string
---@return string
local function read_template(sub_path, lang_)
	lang_ = lang_ or "java"
	local archetype_path = "archetype/fabric_gradle"
	if lang_ == "kotlin" then
		archetype_path = path_util.join(archetype_path, "kotlin")
	end

	local files = vim.api.nvim_get_runtime_file(path_util.join(archetype_path, sub_path), true)
	if #files == 0 then
		error("Template file not found" .. sub_path)
	end

	---@type file*?
	local file = io.open(files[1], "r")
	if not file then
		error("Failed to open template file" .. sub_path)
	end
	if require("minecraft-dev").config.debug then
		vim.notify("Reading template file: " .. files[1])
	end
	local content = file:read("*a")
	file:close()
	return content
end

---@param version string
---@return FabricDefaultVersionData
local function read_json_to_version_info(version)
	local json_dir = "data/fabric/versions"
	local files = vim.api.nvim_get_runtime_file(path_util.join(json_dir, version .. ".json"), true)
	if #files == 0 then
		vim.notify(
			"Data json file for version " .. version:lower() .. " not found\nusing default...",
			vim.log.levels.ERROR
		)
		return default_value
	end

	---@type file*?
	local file = io.open(files[1], "r")
	if not file then
		vim.notify("error on open file " .. version .. ".json\n using default", vim.log.levels.ERROR)
		return default_value
	end

	if require("minecraft-dev").config.debug then
		vim.notify("Reading json data file: " .. files[1])
	end

	local content = file:read("*a")
	file:close()
	return vim.fn.json_decode(content)
end

---@param project_path string
---@param version string
function M.generate(project_path, version)
	local mc_version = version or DEFAULT_VERSION
	choices.which_language(function(select_value)
		lang = select_value
		if version_util.resolve_family(version) == "v1_13_plus" then
			if lang == "java" then
				M.generate_higher_java(project_path, mc_version)
				return
			elseif lang == "kotlin" then
				M.generate_higher_kotlin(project_path, mc_version)
				return
			end
		end
		vim.notify("lower version not support", vim.log.levels.ERROR)
	end)
end

---@param ctx ProjectContext
local function generate_basic(ctx)
	local json_data_table = read_json_to_version_info(ctx.version)
	local resources_dir = path_util.join(ctx.path, "src/main/resources")
	fs.mkdir(resources_dir)
	local resources_client_dir = path_util.join(ctx.path, "src/client/resources")
	fs.mkdir(resources_client_dir)

	local build_gradle_content = read_template("build.gradle")
	fs.write_file(path_util.join(ctx.path, "build.gradle"), string.format(build_gradle_content))
	local fabric_loom_version =
		Not_empty_or(vim.fn.input(prompt_line.loom_version, default_value.loom_version), default_value.loom_version)

	local gradle_properties_content = read_template("gradle.properties")

	fs.write_file(
		path_util.join(ctx.path, "gradle.properties"),
		string.format(
			gradle_properties_content,
			ctx.version,
			json_data_table.loader,
			ctx.groupId,
			ctx.artifactId,
			json_data_table.fabric_api[1],
			fabric_loom_version,
			json_data_table.yarn
		)
	)

	local settings_gradle_content = read_template("settings.gradle")
	fs.write_file(path_util.join(ctx.path, "settings.gradle"), string.format(settings_gradle_content))

	local fabric_mod_json_content = read_template("fabric.mod.json")
	fs.write_file(
		path_util.join(resources_dir, "fabric.mod.json"),
		string.format(
			fabric_mod_json_content,
			ctx.artifactId,
			ctx.artifactId,
			ctx.package,
			ctx.main,
			ctx.package,
			ctx.main,
			ctx.package,
			ctx.main,
			ctx.version
		)
	)
end

---@param project_path string
---@param version string
function M.generate_higher_kotlin(project_path, version)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect()
	ctx.path = path
	ctx.version = version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = "kotlin"

	local src_dir = path_util.join(ctx.path, "src/main/kotlin")
	fs.mkdir(src_dir)
	local src_client_dir = path_util.join(ctx.path, "src/client/kotlin")
	fs.mkdir(src_client_dir)
	local package_client_dir = path_util.join(src_client_dir, ctx.package_path)
	fs.mkdir(package_client_dir)
	local package_main_dir = path_util.join(src_dir, ctx.package_path)
	fs.mkdir(package_main_dir)

	generate_basic(ctx)
	local kotlin_client_content = read_template("Client.kt", ctx.lang)
	fs.write_file(
		path_util.join(package_client_dir, ctx.main .. "Client.kt"),
		string.format(kotlin_client_content, ctx.package, ctx.main)
	)

	local kotlin_server_content = read_template("Main.kt", ctx.lang)
	fs.write_file(path_util.join(package_main_dir, ctx.main .. ".kt"), kotlin_server_content)

	gradle_util.generate_gradlew(ctx.path)
	vim.notify("Generate fabric mod proeject successfully")
end

---the function that generate higher version of fabric gradle template
---@param project_path string
---@param version string
function M.generate_higher_java(project_path, version)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect()
	ctx.path = path
	ctx.version = version
	ctx.package_path = ctx.package:gsub("%.", "/")
	ctx.lang = "java"

	local src_client_dir = path_util.join(ctx.path, "src/client/java", ctx.package_path)
	fs.mkdir(src_client_dir)
	local src_dir = path_util.join(ctx.path, "src/main/java", ctx.package_path)
	fs.mkdir(src_dir)

	generate_basic(ctx)

	local client_java_content = read_template("Client.java")
	local data_java_content = read_template("Data.java")
	fs.write_file(
		path_util.join(src_client_dir, M.upper_first_letter(ctx.main) .. "DataGenerator.java"),
		string.format(data_java_content, ctx.package, ctx.main)
	)

	fs.write_file(
		path_util.join(src_client_dir, M.upper_first_letter(ctx.main) .. "Client.java"),
		string.format(client_java_content, ctx.package, ctx.main)
	)

	local main_java_content = read_template("Main.java")
	fs.write_file(
		path_util.join(src_dir, M.upper_first_letter(ctx.main) .. ".java"),
		string.format(main_java_content, ctx.package, ctx.main)
	)

	gradle_util.generate_gradlew(ctx.path)

	vim.notify("Generate fabric mod proeject successfully")
end

---@param str string
---@return string
function M.upper_first_letter(str)
	return (str:gsub("^%l", string.upper))
end

return M
