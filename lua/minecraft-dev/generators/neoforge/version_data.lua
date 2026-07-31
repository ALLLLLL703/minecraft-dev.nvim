local version = require("minecraft-dev.version")

local M = {}

local USER_AGENT = "minecraft-dev.nvim (https://github.com/ALLLLLL703/minecraft-dev.nvim)"
local SOURCES = {
	neoforge = "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml",
	neogradle = "https://maven.neoforged.net/releases/net/neoforged/gradle/userdev/maven-metadata.xml",
	moddev = "https://maven.neoforged.net/releases/net/neoforged/moddev/net.neoforged.moddev.gradle.plugin/maven-metadata.xml",
}

local function version_parts(value)
	local core, suffix = tostring(value or ""):match("^([%d.]+)(.*)$")
	local parts = {}
	for part in tostring(core):gmatch("%d+") do
		table.insert(parts, tonumber(part))
	end
	return parts, suffix or ""
end

local function newer(left, right)
	local left_parts, left_suffix = version_parts(left)
	local right_parts, right_suffix = version_parts(right)
	for index = 1, math.max(#left_parts, #right_parts) do
		local difference = (left_parts[index] or 0) - (right_parts[index] or 0)
		if difference ~= 0 then
			return difference > 0
		end
	end
	if left_suffix == "" and right_suffix ~= "" then
		return true
	end
	if left_suffix ~= "" and right_suffix == "" then
		return false
	end
	return left_suffix > right_suffix
end

local function maven_versions(content)
	local seen = {}
	local values = {}
	for value in tostring(content or ""):gmatch("<version>%s*([^<]+)%s*</version>") do
		value = vim.trim(value)
		if value ~= "" and not seen[value] then
			seen[value] = true
			table.insert(values, value)
		end
	end
	table.sort(values, newer)
	return values
end

local function minecraft_for_neoforge(value)
	local major, minor = tostring(value):match("^(%d+)%.(%d+)%.")
	if not major then
		return nil
	end
	return "1." .. major .. (minor == "0" and "" or "." .. minor)
end

---@class NeoForgeVersionCatalog
---@field minecraft string[]
---@field neoforge table<string, string[]>
---@field neogradle string[]
---@field moddev string[]

---@param neoforge_content string
---@param neogradle_content string
---@param moddev_content string
---@return NeoForgeVersionCatalog?, table?
function M.parse_catalog_responses(neoforge_content, neogradle_content, moddev_content)
	local neoforge_by_minecraft = {}
	for _, neoforge in ipairs(maven_versions(neoforge_content)) do
		local minecraft = minecraft_for_neoforge(neoforge)
		if
			minecraft
			and (version.compare(minecraft, "1.20.5") or -1) >= 0
			and (version.compare(minecraft, "1.21.4") or 1) <= 0
		then
			neoforge_by_minecraft[minecraft] = neoforge_by_minecraft[minecraft] or {}
			table.insert(neoforge_by_minecraft[minecraft], neoforge)
		end
	end
	local minecraft = vim.tbl_keys(neoforge_by_minecraft)
	table.sort(minecraft, newer)
	for _, values in pairs(neoforge_by_minecraft) do
		table.sort(values, newer)
		while #values > 50 do
			table.remove(values)
		end
	end
	local neogradle = maven_versions(neogradle_content)
	local moddev = maven_versions(moddev_content)
	if #minecraft == 0 or #neogradle == 0 or #moddev == 0 then
		return nil, { code = "version_response_invalid", source = "neoforge" }
	end
	return { minecraft = minecraft, neoforge = neoforge_by_minecraft, neogradle = neogradle, moddev = moddev }, nil
end

---@param minecraft string
---@param neoforge string
---@param neogradle string
---@param moddev string
---@return table
function M.derive(minecraft, neoforge, neogradle, moddev)
	local minor = tonumber(minecraft:match("^1%.(%d+)"))
	local neo_major, neo_minor = neoforge:match("^(%d+)%.(%d+)")
	return {
		minecraft = minecraft,
		neoforge = neoforge,
		neogradle = neogradle,
		moddev = moddev,
		minecraftNext = minor and ("1." .. tostring(minor + 1)) or "1.?",
		neoforgeSpec = neo_major and (neo_major .. "." .. neo_minor) or neoforge,
	}
end

local function new_operation(callback)
	local operation = { status = "pending", callbacks = {}, handles = {} }
	function operation.on_complete(completion_callback)
		if operation.result then
			completion_callback(operation.result)
		else
			table.insert(operation.callbacks, completion_callback)
		end
		return operation
	end
	function operation.finish(value, err)
		if operation.status ~= "pending" then
			return
		end
		operation.status = err and err.code == "cancelled" and "cancelled" or err and "failed" or "generated"
		operation.result = { status = operation.status, error = err }
		callback(value, err)
		for _, completion_callback in ipairs(operation.callbacks) do
			completion_callback(operation.result)
		end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then
			return
		end
		operation.cancel_requested = true
		local killed = false
		for _, handle in pairs(operation.handles) do
			handle:kill(15)
			killed = true
		end
		if not killed then
			operation.finish(nil, { code = "cancelled" })
		end
	end
	return operation
end

local function curl_command(url)
	return {
		"curl",
		"--fail",
		"--location",
		"--silent",
		"--show-error",
		"--max-time",
		"10",
		"--header",
		"Accept: application/xml",
		"--header",
		"User-Agent: " .. USER_AGENT,
		"--url",
		url,
	}
end

---@param callback fun(catalog: NeoForgeVersionCatalog?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.load(callback, system)
	if type(callback) ~= "function" then
		return nil, { code = "callback_required" }
	end
	if vim.fn.executable("curl") ~= 1 and system == nil then
		return nil, { code = "curl_missing" }
	end
	local operation = new_operation(callback)
	local responses = {}
	local remaining = 0
	local terminal_error
	local run_system = system or vim.system
	local function stop_remaining()
		for _, request in pairs(operation.handles) do
			request:kill(15)
		end
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then
			return
		end
		operation.cancel_requested = true
		terminal_error = terminal_error or { code = "cancelled" }
		stop_remaining()
		if remaining == 0 then
			operation.finish(nil, terminal_error)
		end
	end
	for name, url in pairs(SOURCES) do
		remaining = remaining + 1
		local started, handle = pcall(
			run_system,
			curl_command(url),
			{ text = true },
			vim.schedule_wrap(function(result)
				operation.handles[name] = nil
				remaining = remaining - 1
				if operation.status ~= "pending" then
					return
				end
				if result.code ~= 0 and not terminal_error then
					terminal_error = operation.cancel_requested and { code = "cancelled" }
						or { code = "version_fetch_failed", source = name, detail = result.stderr }
					stop_remaining()
				end
				if result.code == 0 then
					responses[name] = result.stdout
				end
				if remaining == 0 then
					if terminal_error then
						operation.finish(nil, terminal_error)
					else
						local catalog, err =
							M.parse_catalog_responses(responses.neoforge, responses.neogradle, responses.moddev)
						operation.finish(catalog, err)
					end
				end
			end)
		)
		if not started then
			remaining = remaining - 1
			terminal_error = { code = "version_fetch_failed", source = name, detail = handle }
			stop_remaining()
			if remaining == 0 then
				operation.finish(nil, terminal_error)
			end
			return operation, nil
		end
		operation.handles[name] = handle
	end
	return operation, nil
end

---@param minecraft string
---@param callback fun(versions: string[]?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.load_parchment(minecraft, callback, system)
	if type(callback) ~= "function" then
		return nil, { code = "callback_required" }
	end
	if type(minecraft) ~= "string" or not minecraft:match("^%d+%.%d+%.?%d*$") then
		return nil, { code = "invalid_version", field = "minecraft_version" }
	end
	if vim.fn.executable("curl") ~= 1 and system == nil then
		return nil, { code = "curl_missing" }
	end
	local operation = new_operation(callback)
	local url = "https://maven.parchmentmc.org/org/parchmentmc/data/parchment-" .. minecraft .. "/maven-metadata.xml"
	local started, handle = pcall(
		system or vim.system,
		curl_command(url),
		{ text = true },
		vim.schedule_wrap(function(result)
			operation.handles.parchment = nil
			if operation.status ~= "pending" then
				return
			end
			if operation.cancel_requested then
				operation.finish(nil, { code = "cancelled" })
				return
			end
			if result.code ~= 0 then
				operation.finish(nil, { code = "version_fetch_failed", source = "parchment", detail = result.stderr })
				return
			end
			local values = maven_versions(result.stdout)
			operation.finish(
				#values > 0 and values or nil,
				#values == 0 and { code = "version_response_invalid", source = "parchment" } or nil
			)
		end)
	)
	if not started then
		operation.finish(nil, { code = "version_fetch_failed", source = "parchment", detail = handle })
		return operation, nil
	end
	operation.handles.parchment = handle
	return operation, nil
end

---@param minecraft string
---@param callback fun(value: table?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.resolve(minecraft, callback, system)
	if type(callback) ~= "function" then
		return nil, { code = "callback_required" }
	end
	local operation = new_operation(callback)
	local child, load_error
	function operation.cancel()
		if operation.status ~= "pending" then
			return
		end
		if child and child.cancel then
			child.cancel()
		else
			operation.finish(nil, { code = "cancelled" })
		end
	end
	child, load_error = M.load(function(catalog, err)
		if not catalog then
			operation.finish(nil, err)
			return
		end
		local neo = catalog.neoforge[minecraft]
		if not neo or not neo[1] then
			operation.finish(nil, { code = "unsupported_version", field = "minecraft_version", value = minecraft })
			return
		end
		operation.finish(M.derive(minecraft, neo[1], catalog.neogradle[1], catalog.moddev[1]))
	end, system)
	if load_error then
		operation.finish(nil, load_error)
	end
	return operation, nil
end

return M
