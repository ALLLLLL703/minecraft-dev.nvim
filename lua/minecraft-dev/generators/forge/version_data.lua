local version = require("minecraft-dev.version")

local M = {}

local METADATA_URL = "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"
local USER_AGENT = "minecraft-dev.nvim (https://github.com/ALLLLLL703/minecraft-dev.nvim)"

local function version_parts(value)
	local parts = {}
	for part in tostring(value or ""):gmatch("%d+") do table.insert(parts, tonumber(part)) end
	return parts
end

local function newer(left, right)
	local left_parts = version_parts(left)
	local right_parts = version_parts(right)
	for index = 1, math.max(#left_parts, #right_parts) do
		local difference = (left_parts[index] or 0) - (right_parts[index] or 0)
		if difference ~= 0 then return difference > 0 end
	end
	return tostring(left) > tostring(right)
end

---@class ForgeVersionCatalog
---@field minecraft string[]
---@field forge table<string, string[]>

---@param content string
---@return ForgeVersionCatalog?, table?
function M.parse(content)
	local forge_by_minecraft = {}
	for coordinate in tostring(content or ""):gmatch("<version>%s*([^<]+)%s*</version>") do
		local minecraft, forge = vim.trim(coordinate):match("^(1%.%d+%.?%d*)%-(%d[%d%.]*)$")
		if minecraft and forge
			and (version.compare(minecraft, "1.16") or -1) >= 0
			and (version.compare(minecraft, "1.21.1") or 1) <= 0
		then
			forge_by_minecraft[minecraft] = forge_by_minecraft[minecraft] or {}
			table.insert(forge_by_minecraft[minecraft], forge)
		end
	end

	local minecraft_versions = vim.tbl_keys(forge_by_minecraft)
	table.sort(minecraft_versions, newer)
	for minecraft, forge_versions in pairs(forge_by_minecraft) do
		local unique = {}
		local sorted = {}
		for _, forge in ipairs(forge_versions) do
			if not unique[forge] then unique[forge] = true table.insert(sorted, forge) end
		end
		table.sort(sorted, newer)
		while #sorted > 50 do table.remove(sorted) end
		forge_by_minecraft[minecraft] = sorted
	end
	if #minecraft_versions == 0 then return nil, { code = "version_response_invalid", source = "forge" } end
	return { minecraft = minecraft_versions, forge = forge_by_minecraft }, nil
end

---@param minecraft string
---@param forge string
---@return table
function M.derive(minecraft, forge)
	local minor = tonumber(minecraft:match("^1%.(%d+)"))
	return {
		minecraft = minecraft,
		forge = forge,
		minecraftNext = minor and ("1." .. tostring(minor + 1)) or "1.?",
		forgeSpec = forge:match("^(%d+)") or forge,
	}
end

---@param callback fun(catalog: ForgeVersionCatalog?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.load(callback, system)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	if vim.fn.executable("curl") ~= 1 and system == nil then return nil, { code = "curl_missing" } end

	local operation = { status = "pending", callbacks = {} }
	function operation.on_complete(completion_callback)
		if operation.result then completion_callback(operation.result) else table.insert(operation.callbacks, completion_callback) end
		return operation
	end
	local function finish(result)
		if operation.status ~= "pending" then return end
		operation.status = result.status
		operation.result = result
		for _, completion_callback in ipairs(operation.callbacks) do completion_callback(result) end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if operation.handle then operation.handle:kill(15)
		else
			local err = { code = "cancelled" }
			finish({ status = "cancelled", error = err })
			callback(nil, err)
		end
	end

	local command = {
		"curl", "--fail", "--location", "--silent", "--show-error", "--max-time", "10",
		"--header", "User-Agent: " .. USER_AGENT, "--url", METADATA_URL,
	}
	local run_system = system or vim.system
	local started, handle = pcall(run_system, command, { text = true }, vim.schedule_wrap(function(result)
		operation.handle = nil
		if operation.cancel_requested then
			local err = { code = "cancelled" }
			finish({ status = "cancelled", error = err })
			callback(nil, err)
			return
		end
		if result.code ~= 0 then
			local err = { code = "version_fetch_failed", source = "forge", detail = result.stderr }
			finish({ status = "failed", error = err })
			callback(nil, err)
			return
		end
		local catalog, parse_error = M.parse(result.stdout)
		finish(parse_error and { status = "failed", error = parse_error } or { status = "generated" })
		callback(catalog, parse_error)
	end))
	if not started then
		local err = { code = "version_fetch_failed", source = "forge", detail = handle }
		finish({ status = "failed", error = err })
		callback(nil, err)
		return operation, nil
	end
	operation.handle = handle
	return operation, nil
end

---@param minecraft string
---@param callback fun(value: table?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.resolve(minecraft, callback, system)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	local operation = { status = "pending", callbacks = {} }
	local child
	function operation.on_complete(completion_callback)
		if operation.result then completion_callback(operation.result) else table.insert(operation.callbacks, completion_callback) end
		return operation
	end
	local function finish(value, err)
		if operation.status ~= "pending" then return end
		operation.status = err and err.code == "cancelled" and "cancelled" or err and "failed" or "generated"
		operation.result = { status = operation.status, error = err }
		callback(value, err)
		for _, completion_callback in ipairs(operation.callbacks) do completion_callback(operation.result) end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" then return end
		if child and child.cancel then child.cancel() else finish(nil, { code = "cancelled" }) end
	end
	local load_error
	child, load_error = M.load(function(catalog, err)
		if not catalog then finish(nil, err) return end
		local forge_versions = catalog.forge[minecraft]
		if not forge_versions or not forge_versions[1] then
			finish(nil, { code = "unsupported_version", field = "minecraft_version", value = minecraft })
			return
		end
		finish(M.derive(minecraft, forge_versions[1]), nil)
	end, system)
	if load_error then finish(nil, load_error) end
	return operation, nil
end

return M
