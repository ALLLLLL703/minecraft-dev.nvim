local M = {}

---@class FabricGenerationOptions
---@field language ProgrammingLanguage
---@field side "client"|"server"|"both"
---@field generate_datagen boolean
---@field use_mixins boolean

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

	if options.side ~= "client" then
		entrypoints.main = { string.format("%s.%s", ctx.package, M.main_class_name(ctx, options)) }
	end

	if options.side ~= "server" then
		entrypoints.client = { string.format("%s.client.%s", ctx.package, M.client_class_name(ctx, options)) }
	end

	if options.generate_datagen then
		entrypoints["fabric-datagen"] = { string.format("%s.%s", ctx.package, M.datagen_class_name(ctx, options)) }
	end

	return entrypoints
end

---@param artifact_id string
---@param use_mixins boolean
---@return string[]?
function M.mixin_config_refs(artifact_id, use_mixins)
	if not use_mixins then
		return nil
	end

	return { artifact_id .. ".mixins.json" }
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

	local mixin_refs = M.mixin_config_refs(ctx.artifactId, options.use_mixins)
	if mixin_refs then
		append_array_property(lines, "mixins", mixin_refs, 1, false)
	end

	table.insert(lines, indent(1) .. quote("depends") .. ": {")
	table.insert(lines, indent(2) .. quote("fabricloader") .. ": " .. quote(">=0.15.0") .. ",")
	table.insert(lines, indent(2) .. quote("minecraft") .. ": " .. quote("~" .. ctx.version) .. ",")
	table.insert(lines, indent(2) .. quote("java") .. ": " .. quote(">=21") .. ",")
	table.insert(lines, indent(2) .. quote("fabric-api") .. ": " .. quote("*"))
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
function M.mixin_target_class(ctx, options)
	if options.side == "client" then
		return "net.minecraft.client.MinecraftClient"
	elseif options.side == "server" then
		return "net.minecraft.server.MinecraftServer"
	end

	return "net.minecraft.entity.Entity"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.mixin_target_method(ctx, options)
	if options.side == "client" then
		return "run"
	elseif options.side == "server" then
		return "runServer"
	end

	return "tick"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.mixin_package(ctx, options)
	return ctx.package .. ".mixin"
end

---@param ctx ProjectContext
---@return string
function M.mixin_class_name(ctx)
	return upper_first_letter(ctx.main) .. "Mixin"
end

---@param ctx ProjectContext
---@param options FabricGenerationOptions
---@return string
function M.build_mixins_json(ctx, options)
	local bucket = M.mixin_bucket(options.side)
	local lines = {
		"{",
		indent(1) .. quote("required") .. ": true,",
		indent(1) .. quote("package") .. ": " .. quote(M.mixin_package(ctx, options)) .. ",",
		indent(1) .. quote("compatibilityLevel") .. ": " .. quote("JAVA_21") .. ",",
	}

	append_array_property(lines, bucket, { M.mixin_class_name(ctx) }, 1, false)
	table.insert(lines, indent(1) .. quote("injectors") .. ": {")
	table.insert(lines, indent(2) .. quote("defaultRequire") .. ": 1")
	table.insert(lines, indent(1) .. "}")
	table.insert(lines, "}")

	return table.concat(lines, "\n")
end

return M
