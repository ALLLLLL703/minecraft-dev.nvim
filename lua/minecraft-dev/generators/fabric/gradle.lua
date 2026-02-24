local M = {}
local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local path_util = require("minecraft-dev.util.path")
local version_util = require("minecraft-dev.version")
local gradle_util = require("minecraft-dev.util.gradle")

local DEFAULT_VERSION = "1.21"

---nothing
---@param sub_path string
local function read_template(sub_path)
	local files = vim.api.nvim_get_runtime_file(path_util.join("archetype/fabric_gradle", sub_path), true)
	if #files == 0 then
		error("Template file not found" .. sub_path)
	end

	---@type file*?
	local file = io.open(files[1], "r")
	if not file then
		error("Failed to open template file" .. sub_path)
	end
	vim.notify("Reading template file: " .. files[1])
	local content = file:read("*a")
	file:close()
	return content
end

---@param project_path string
---@param version string
function M.generate(project_path, version)
	local mc_version = version or DEFAULT_VERSION
	if version_util.resolve_family(version) == "v1_13_plus" then
		M.generate_higher(project_path, mc_version)
		return
	end
	vim.notify("lower version not support", vim.log.levels.ERROR)
end

---the function that generate higher version of fabric gradle template
---@param project_path any
---@param version any
function M.generate_higher(project_path, version)
	local path = project_path or vim.fn.getcwd()
	local ctx = context.collect()
	ctx.path = path
	ctx.version = version
	ctx.package_path = ctx.package:gsub("%.", "/")

	local src_client_dir = path_util.join(ctx.path, "src/client/java/", ctx.package_path, "client")
	fs.mkdir(src_client_dir)
	local src_dir = path_util.join(ctx.path, "src/main/java", ctx.package_path)
	fs.mkdir(src_dir)

	local resources_dir = path_util.join(ctx.path, "src/main/resources")
	fs.mkdir(resources_dir)

	local build_gradle_content = read_template("build.gradle")
	fs.write_file(path_util.join(ctx.path, "build.gradle"), string.format(build_gradle_content))

	local gradle_properties_content = read_template("gradle.properties")
	fs.write_file(
		path_util.join(ctx.path, "gradle.properties"),
		string.format(gradle_properties_content, ctx.version, ctx.version, ctx.groupId, ctx.artifactId, ctx.version)
	)

	local client_java_content = read_template("Client.java")
	local data_java_content = read_template("Data.java")
	fs.write_file(
		path_util.join(src_client_dir, M.upper_first_letter(ctx.artifactId) .. "DataGenerator.java"),
		string.format(data_java_content, ctx.package, M.upper_first_letter(ctx.artifactId))
	)

	fs.write_file(
		path_util.join(src_client_dir, M.upper_first_letter(ctx.artifactId) .. "Client.java"),
		string.format(client_java_content, ctx.package, M.upper_first_letter(ctx.artifactId))
	)

	local main_java_content = read_template("Main.java")
	fs.write_file(
		path_util.join(src_dir, M.upper_first_letter(ctx.artifactId) .. ".Java"),
		string.format(main_java_content, ctx.package, M.upper_first_letter(ctx.artifactId))
	)

	local settings_gradle_content = read_template("settings.gradle")
	fs.write_file(path_util.join(ctx.path, "settings.gradle"), string.format(settings_gradle_content))

	gradle_util.generate_gradlew(ctx.path)

	vim.notify("Generate fabric mod proeject successfully")
end

---@param str string
function M.upper_first_letter(str)
	return (str:gsub("^%l", string.upper))
end

return M
