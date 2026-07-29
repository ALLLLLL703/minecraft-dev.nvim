local version_util = require("minecraft-dev.version")

local M = {}

---@class FabricGenerationOptions
---@field language ProgrammingLanguage
---@field side "client"|"server"|"both"
---@field generate_datagen boolean
---@field use_mixins boolean
---@field client_mixins boolean
---@field split_sources boolean
---@field use_fabric_api boolean
---@field use_official_mappings boolean
---@field target_java_version integer
---@field loom_version? string
---@field gradle_version? string
---@field kotlin_loader_version? string
---@field version_data? FabricVersionData

---@param side "client"|"server"|"both"
---@return string
function M.environment_name(side)
	if side == "client" then
		return "client"
	elseif side == "server" then
		return "server"
	end

	return "*"
end

---@param class_name string
---@return string
local function upper_first_letter(class_name)
	return (class_name:gsub("^%l", string.upper))
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.main_class_name(ctx, options)
	if options.language == "java" then
		return upper_first_letter(ctx.main)
	end

	return ctx.main
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.client_class_name(ctx, options)
	return M.main_class_name(ctx, options) .. "Client"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.datagen_class_name(ctx, options)
	return M.main_class_name(ctx, options) .. "DataGenerator"
end

---@param value string
---@return string
local function quote(value)
	return vim.fn.json_encode(value)
end

---@param level integer
---@return string
local function indent(level)
	return string.rep("\t", level)
end

---@param lines string[]
---@param key string
---@param values string[]
---@param level integer
---@param is_last boolean
local function append_array_property(lines, key, values, level, is_last)
	table.insert(lines, indent(level) .. quote(key) .. ": [")
	for index, value in ipairs(values) do
		local suffix = index < #values and "," or ""
		table.insert(lines, indent(level + 1) .. quote(value) .. suffix)
	end
	local suffix = is_last and "" or ","
	table.insert(lines, indent(level) .. "]" .. suffix)
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return table<string, string[]>
function M.entrypoints(ctx, options)
	local entrypoints = {}
	local function value(class_name)
		if options.language == "kotlin" then return { adapter = "kotlin", value = class_name } end
		return class_name
	end

	if options.side ~= "client" then
		entrypoints.main = { value(string.format("%s.%s", ctx.package, M.main_class_name(ctx, options))) }
	end

	if options.side ~= "server" then
		local client_package = options.language == "kotlin" and ctx.package .. ".client" or ctx.package
		entrypoints.client = { value(string.format("%s.%s", client_package, M.client_class_name(ctx, options))) }
	end

	if options.generate_datagen then
		entrypoints["fabric-datagen"] = { value(string.format("%s.%s", ctx.package, M.datagen_class_name(ctx, options))) }
	end

	return entrypoints
end

---@param artifact_id string
---@param options FabricGenerationOptions
---@return table[]?
function M.mixin_config_refs(artifact_id, options)
	if not options.use_mixins then return nil end
	local refs = {}
	if options.side ~= "client" or not options.client_mixins then table.insert(refs, artifact_id .. ".mixins.json") end
	if options.client_mixins then
		table.insert(refs, { config = artifact_id .. ".client.mixins.json", environment = "client" })
	end
	return refs
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.build_mod_json(ctx, options)
	local lines = {
		"{",
		indent(1) .. quote("schemaVersion") .. ": 1,",
		indent(1) .. quote("id") .. ": " .. quote(ctx.artifactId) .. ",",
		indent(1) .. quote("version") .. ": " .. quote("${version}") .. ",",
		indent(1) .. quote("name") .. ": " .. quote(ctx.artifactId) .. ",",
		indent(1) .. quote("environment") .. ": " .. quote(M.environment_name(options.side)) .. ",",
		indent(1) .. quote("entrypoints") .. ": {",
	}

	local entrypoints = M.entrypoints(ctx, options)
	local ordered_keys = {}
	if entrypoints.main then
		table.insert(ordered_keys, "main")
	end
	if entrypoints.client then
		table.insert(ordered_keys, "client")
	end
	if entrypoints["fabric-datagen"] then
		table.insert(ordered_keys, "fabric-datagen")
	end

	for index, key in ipairs(ordered_keys) do
		append_array_property(lines, key, entrypoints[key], 2, index == #ordered_keys)
	end
	table.insert(lines, indent(1) .. "},")

	local mixin_refs = M.mixin_config_refs(ctx.artifactId, options)
	if mixin_refs then
		table.insert(lines, indent(1) .. quote("mixins") .. ": [")
		for index, ref in ipairs(mixin_refs) do
			local suffix = index < #mixin_refs and "," or ""
			table.insert(lines, indent(2) .. (type(ref) == "table" and vim.json.encode(ref) or quote(ref)) .. suffix)
		end
		table.insert(lines, indent(1) .. "],")
	end

	table.insert(lines, indent(1) .. quote("depends") .. ": {")
	local dependencies = {
		{ "fabricloader", ">=" .. tostring(options.loader_version or "0.15.0") },
		{ "minecraft", ctx.version },
		{ "java", ">=" .. tostring(options.target_java_version or version_util.required_java(ctx.version)) },
	}
	if options.language == "kotlin" then
		table.insert(dependencies, 2, { "fabric-language-kotlin", ">=" .. options.kotlin_loader_version })
	end
	if options.use_fabric_api ~= false then table.insert(dependencies, { "fabric-api", "*" }) end
	for index, dependency in ipairs(dependencies) do
		local suffix = index < #dependencies and "," or ""
		table.insert(lines, indent(2) .. quote(dependency[1]) .. ": " .. quote(dependency[2]) .. suffix)
	end
	table.insert(lines, indent(1) .. "}")
	table.insert(lines, "}")

	return table.concat(lines, "\n")
end

---@param side "client"|"server"|"both"
---@return "client"|"mixins"
function M.mixin_bucket(side)
	if side == "client" then
		return "client"
	end

	return "mixins"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.mixin_target_class(ctx, options, client)
	if client or options.side == "client" then
		return options.use_official_mappings ~= false and "net.minecraft.client.Minecraft" or "net.minecraft.client.MinecraftClient"
	elseif options.side == "server" then
		return "net.minecraft.server.MinecraftServer"
	end
	return options.use_official_mappings ~= false and "net.minecraft.world.entity.Entity" or "net.minecraft.entity.Entity"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.mixin_target_method(ctx, options, client)
	if client or options.side == "client" then
		return "run"
	elseif options.side == "server" then
		return "runServer"
	end

	return "tick"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.mixin_package(ctx, options, client)
	return ctx.package .. (client and ".mixin.client" or ".mixin")
end

---@param ctx ProjectContext
---@return string
function M.mixin_class_name(ctx, client)
	return upper_first_letter(ctx.main) .. (client and "ClientMixin" or "Mixin")
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.build_mixins_json(ctx, options, client)
	local bucket = client and "client" or M.mixin_bucket(options.side)
	local lines = {
		"{",
		indent(1) .. quote("required") .. ": true,",
		indent(1) .. quote("package") .. ": " .. quote(M.mixin_package(ctx, options, client)) .. ",",
		indent(1) .. quote("compatibilityLevel") .. ": " .. quote("JAVA_" .. tostring(options.target_java_version or version_util.required_java(ctx.version))) .. ",",
	}

	append_array_property(lines, bucket, { M.mixin_class_name(ctx, client) }, 1, false)
	table.insert(lines, indent(1) .. quote("injectors") .. ": {")
	table.insert(lines, indent(2) .. quote("defaultRequire") .. ": 1")
	table.insert(lines, indent(1) .. "}")
	table.insert(lines, "}")

	return table.concat(lines, "\n")
end

return M
