local notify = require("minecraft-dev.util.notify")
local template = require("minecraft-dev.util.template")

local M = {}

local USER_AGENT = "minecraft-dev.nvim (https://github.com/ALLLLLL703/minecraft-dev.nvim)"
local CATALOG_URLS = {
	fabric = "https://meta.fabricmc.net/v2/versions",
	api = "https://api.modrinth.com/v2/project/P7dR8mSH/version",
	loom = "https://maven.fabricmc.net/net/fabricmc/fabric-loom/maven-metadata.xml",
}

local function cache_path(version)
	return vim.fs.joinpath(vim.fn.stdpath("cache"), "minecraft-dev", "fabric", version .. ".json")
end

local function read_path(file_path)
	local handle = io.open(file_path, "r")
	if not handle then return nil end
	local content = handle:read("*a")
	handle:close()
	return content
end

local function decode(content)
	local ok, value = pcall(vim.json.decode, content or "")
	return ok and value or nil
end

local function release_version(content)
	local value = content and content:match("<release>%s*([^<]+)</release>")
	return value and vim.trim(value) or nil
end

local function valid_kotlin_loader(value)
	return type(value) == "string" and value:match("^[%w_.-]+%+kotlin%.[%w_.-]+$") ~= nil
end

local function version_parts(value)
	local numeric, suffix = tostring(value or ""):match("^(%d[%d%.]*)(.*)$")
	if not numeric then return nil end
	local parts = {}
	for part in numeric:gmatch("%d+") do table.insert(parts, tonumber(part)) end
	return parts, suffix:lower()
end

local function compare_versions(left, right)
	local left_parts, left_suffix = version_parts(left)
	local right_parts, right_suffix = version_parts(right)
	if not left_parts or not right_parts then return tostring(left) > tostring(right) and 1 or -1 end
	for index = 1, math.max(#left_parts, #right_parts) do
		local difference = (left_parts[index] or 0) - (right_parts[index] or 0)
		if difference ~= 0 then return difference end
	end
	if left_suffix == "" and right_suffix ~= "" then return 1 end
	if left_suffix ~= "" and right_suffix == "" then return -1 end
	if left_suffix == right_suffix then return 0 end
	local left_prefix, left_number, left_trailing = left_suffix:match("^(.-)(%d+)(%D*)$")
	local right_prefix, right_number, right_trailing = right_suffix:match("^(.-)(%d+)(%D*)$")
	if left_prefix and left_prefix == right_prefix and left_trailing == right_trailing and left_number ~= right_number then
		return tonumber(left_number) - tonumber(right_number)
	end
	return left_suffix > right_suffix and 1 or -1
end

local function sorted_versions(values, predicate)
	local output = {}
	local seen = {}
	for _, value in ipairs(values or {}) do
		if type(value) == "string" and value ~= "" and not seen[value] and (not predicate or predicate(value)) then
			seen[value] = true
			table.insert(output, value)
		end
	end
	table.sort(output, function(left, right) return compare_versions(left, right) > 0 end)
	return output
end

local function maven_versions(content, predicate)
	local versions = {}
	for version in tostring(content or ""):gmatch("<version>%s*([^<]+)%s*</version>") do
		table.insert(versions, vim.trim(version))
	end
	return sorted_versions(versions, predicate)
end

---@param loader_content string
---@param yarn_content string
---@param api_content string
---@param kotlin_content string
---@param loom_content string
---@return FabricVersionData
function M.parse_responses(loader_content, yarn_content, api_content, kotlin_content, loom_content)
	local loaders = assert(decode(loader_content), "invalid Fabric loader response")
	local yarn = assert(decode(yarn_content), "invalid Yarn response")
	local api = assert(decode(api_content), "invalid Fabric API response")
	local defaults = require("minecraft-dev").config.defaults.fabric.version_data
	table.sort(loaders, function(left, right)
		return compare_versions(left.loader and left.loader.version, right.loader and right.loader.version) > 0
	end)
	table.sort(yarn, function(left, right)
		if type(left.build) == "number" and type(right.build) == "number" and left.build ~= right.build then
			return left.build > right.build
		end
		return compare_versions(left.version, right.version) > 0
	end)
	table.sort(api, function(left, right) return compare_versions(left.version_number, right.version_number) > 0 end)
	local kotlin_loader = release_version(kotlin_content) or maven_versions(kotlin_content, valid_kotlin_loader)[1]
	if not valid_kotlin_loader(kotlin_loader) then kotlin_loader = defaults.kotlin_loader end
	local loom_version = release_version(loom_content) or maven_versions(loom_content)[1] or defaults.loom_version
	assert(loaders[1] and loaders[1].loader and loaders[1].loader.version, "Fabric loader response is empty")
	assert(api[1] and api[1].version_number, "Fabric API response is empty")
	assert(loom_version, "Fabric Loom response is empty")
	return {
		loader = loaders[1].loader.version,
		yarn = yarn[1] and yarn[1].version or nil,
		fabric_api = api[1].version_number,
		kotlin_loader = kotlin_loader,
		loom_version = loom_version,
		gradle_version = defaults.gradle_version,
	}
end

---@class FabricVersionCatalog
---@field game table[]
---@field loader string[]
---@field yarn table[]
---@field fabric_api table[]
---@field loom string[]

---@param fabric_content string
---@param api_content string
---@param loom_content string
---@return FabricVersionCatalog
function M.parse_catalog_responses(fabric_content, api_content, loom_content)
	local fabric = assert(decode(fabric_content), "invalid Fabric versions response")
	local api = assert(decode(api_content), "invalid Fabric API response")
	assert(type(fabric.game) == "table" and type(fabric.loader) == "table" and type(fabric.mappings) == "table", "Fabric versions response is incomplete")

	local game = {}
	local seen_games = {}
	for _, item in ipairs(fabric.game) do
		if type(item.version) == "string" and type(item.stable) == "boolean" and not seen_games[item.version] then
			seen_games[item.version] = true
			table.insert(game, { version = item.version, stable = item.stable })
		end
	end
	assert(#game > 0, "Fabric game versions response is empty")

	local loaders = {}
	for _, item in ipairs(fabric.loader) do table.insert(loaders, item.version) end
	loaders = sorted_versions(loaders)
	assert(#loaders > 0, "Fabric loader response is empty")

	local yarn = {}
	local seen_yarn = {}
	for _, item in ipairs(fabric.mappings) do
		if type(item.gameVersion) == "string" and type(item.version) == "string" and not seen_yarn[item.version] then
			seen_yarn[item.version] = true
			table.insert(yarn, { game_version = item.gameVersion, name = item.version, build = tonumber(item.build) or -1 })
		end
	end
	table.sort(yarn, function(left, right)
		if left.game_version ~= right.game_version then
			return compare_versions(left.game_version, right.game_version) > 0
		end
		if left.build ~= right.build then return left.build > right.build end
		return compare_versions(left.name, right.name) > 0
	end)

	local api_versions = {}
	local seen_api = {}
	for _, item in ipairs(api) do
		local valid_file = false
		for _, file in ipairs(type(item.files) == "table" and item.files or {}) do
			if type(file.filename) == "string" and file.filename:match("^fabric%-api%-.*%.jar$") then valid_file = true break end
		end
		if valid_file and type(item.version_number) == "string" and type(item.game_versions) == "table"
			and not seen_api[item.version_number]
		then
			seen_api[item.version_number] = true
			table.insert(api_versions, { game_versions = vim.deepcopy(item.game_versions), version = item.version_number })
		end
	end
	table.sort(api_versions, function(left, right) return compare_versions(left.version, right.version) > 0 end)
	assert(#api_versions > 0, "Fabric API response is empty")

	local loom = maven_versions(loom_content)
	assert(#loom > 0, "Fabric Loom response is empty")
	return {
		game = game,
		loader = loaders,
		yarn = yarn,
		fabric_api = api_versions,
		loom = loom,
	}
end

---@param catalog FabricVersionCatalog
---@param include_snapshots boolean
---@return string[]
function M.minecraft_versions(catalog, include_snapshots)
	local versions = {}
	for _, item in ipairs(catalog.game or {}) do
		if include_snapshots or item.stable then table.insert(versions, item.version) end
	end
	return versions
end

---@param catalog FabricVersionCatalog
---@param minecraft_version string
---@return table[], boolean
function M.yarn_versions(catalog, minecraft_version)
	local exact = {}
	for _, item in ipairs(catalog.yarn or {}) do
		if item.game_version == minecraft_version then table.insert(exact, item) end
	end
	return #exact > 0 and exact or vim.deepcopy(catalog.yarn or {}), #exact > 0
end

---@param catalog FabricVersionCatalog
---@param minecraft_version string
---@return string[], boolean
function M.fabric_api_versions(catalog, minecraft_version)
	local exact = {}
	local all = {}
	for _, item in ipairs(catalog.fabric_api or {}) do
		table.insert(all, item.version)
		if vim.tbl_contains(item.game_versions, minecraft_version) then table.insert(exact, item.version) end
	end
	return #exact > 0 and exact or all, #exact > 0
end

---@class FabricVersionData
---@field loom_version string
---@field gradle_version string
---@field fabric_api string|string[]
---@field kotlin_loader string
---@field loader string
---@field yarn string?

---@return FabricVersionData
function M.default_data()
	return vim.deepcopy(require("minecraft-dev").config.defaults.fabric.version_data)
end

local function with_defaults(data)
	local defaults = M.default_data()
	local merged = vim.tbl_deep_extend("force", defaults, data)
	if not valid_kotlin_loader(merged.kotlin_loader) then merged.kotlin_loader = defaults.kotlin_loader end
	for _, key in ipairs({ "loom_version", "gradle_version" }) do
		if type(merged[key]) ~= "string" or vim.trim(merged[key]) == "" then merged[key] = defaults[key] end
	end
	return merged
end

---@param version string
---@return FabricVersionData
function M.read(version)
	local cached = decode(read_path(cache_path(version)))
	if type(cached) == "table" and not vim.islist(cached) then
		cached._cached_at = nil
		return with_defaults(cached)
	end
	local runtime_path = "data/fabric/versions/" .. version .. ".json"
	local files = vim.api.nvim_get_runtime_file(runtime_path, true)
	if #files == 0 then
		notify.notify(vim.log.levels.WARN, { "data", "version_file_missing" }, version)
		return M.default_data()
	end

	local ok, content = pcall(template.read_runtime_file, runtime_path)
	if not ok then
		notify.notify(vim.log.levels.WARN, { "data", "version_file_open_failed" }, version)
		return M.default_data()
	end

	notify.debug({ "data", "reading_json" }, files[1])
	return with_defaults(vim.fn.json_decode(content))
end

local function write_cache(version, data)
	local target = cache_path(version)
	vim.fn.mkdir(vim.fs.dirname(target), "p")
	local handle = io.open(target, "w")
	if not handle then return end
	local cached = vim.deepcopy(data)
	cached._cached_at = os.time()
	handle:write(vim.json.encode(cached))
	handle:close()
end

local function cached_data(name)
	local cached = decode(read_path(cache_path(name)))
	if type(cached) ~= "table" or vim.islist(cached) then return nil, false end
	local cached_at = cached._cached_at
	cached._cached_at = nil
	local ttl = require("minecraft-dev").config.defaults.fabric.cache_ttl
	local fresh = M.cache_is_fresh(cached_at, os.time(), ttl)
	return cached, fresh
end

---@param cached_at any
---@param now number
---@param ttl any
---@return boolean
function M.cache_is_fresh(cached_at, now, ttl)
	return type(cached_at) == "number" and type(ttl) == "number" and ttl >= 0 and now - cached_at <= ttl
end

local function completed_operation(result)
	return {
		status = result.status,
		result = result,
		on_complete = function(callback) callback(result) end,
		cancel = function() end,
	}
end

---@param callback fun(catalog: FabricVersionCatalog?, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.load_catalog(callback, system)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	local cached, fresh = cached_data("catalog")
	if fresh and system == nil then
		callback(cached, nil)
		return completed_operation({ status = "generated" }), nil
	end
	if vim.fn.executable("curl") ~= 1 and system == nil then
		local err = { code = "curl_missing" }
		if cached then callback(cached, err) return completed_operation({ status = "generated", warnings = { err } }), nil end
		return nil, err
	end

	local operation = { handles = {}, status = "pending", callbacks = {} }
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
		for _, handle in pairs(operation.handles) do handle:kill(15) end
	end

	local responses = {}
	local remaining = vim.tbl_count(CATALOG_URLS)
	local request_error
	local run_system = system or vim.system
	local function complete(name, result)
		operation.handles[name] = nil
		remaining = remaining - 1
		if operation.cancel_requested then
			if remaining == 0 then
				local err = { code = "cancelled" }
				callback(nil, err)
				finish({ status = "cancelled", error = err })
			end
			return
		end
		if result.code == 0 then responses[name] = result.stdout
		elseif not request_error then request_error = { code = "version_fetch_failed", source = name, detail = result.stderr } end
		if remaining > 0 then return end

		if not request_error then
			local ok, catalog = pcall(M.parse_catalog_responses, responses.fabric, responses.api, responses.loom)
			if ok then
				write_cache("catalog", catalog)
				callback(catalog, nil)
				finish({ status = "generated" })
				return
			end
			request_error = { code = "version_response_invalid", detail = catalog }
		end
		if cached then
			callback(cached, request_error)
			finish({ status = "generated", warnings = { request_error } })
		else
			callback(nil, request_error)
			finish({ status = "failed", error = request_error })
		end
	end
	for name, url in pairs(CATALOG_URLS) do
		local command = {
			"curl", "--fail", "--silent", "--show-error", "--max-time", "10",
			"--header", "User-Agent: " .. USER_AGENT, "--url", url,
		}
		local ok, handle = pcall(run_system, command, { text = true }, vim.schedule_wrap(function(result) complete(name, result) end))
		if ok then operation.handles[name] = handle else complete(name, { code = 1, stderr = tostring(handle) }) end
	end
	return operation, nil
end

---@param version string
---@param callback fun(data: FabricVersionData, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.resolve(version, callback, system)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	local cached, fresh = cached_data(version)
	if fresh and system == nil then
		callback(with_defaults(cached), nil)
		return completed_operation({ status = "generated" }), nil
	end
	if vim.fn.executable("curl") ~= 1 then callback(M.read(version), { code = "curl_missing" }) return nil, nil end
	local encoded_version = vim.uri_encode(version)
	local urls = {
		loader = "https://meta.fabricmc.net/v2/versions/loader/" .. encoded_version,
		yarn = "https://meta.fabricmc.net/v2/versions/yarn/" .. encoded_version,
		api = "https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%5B%22" .. encoded_version .. "%22%5D&loaders=%5B%22fabric%22%5D",
		kotlin = "https://maven.fabricmc.net/net/fabricmc/fabric-language-kotlin/maven-metadata.xml",
		loom = "https://maven.fabricmc.net/net/fabricmc/fabric-loom/maven-metadata.xml",
	}
	local operation = { handles = {}, status = "pending", callbacks = {} }
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
		for _, handle in pairs(operation.handles) do handle:kill(15) end
	end
	local responses = {}
	local optional_sources = { kotlin = true, loom = true }
	local remaining = vim.tbl_count(urls)
	local required_error
	local run_system = system or vim.system
	local function complete(name, result)
		operation.handles[name] = nil
		remaining = remaining - 1
		if operation.cancel_requested then
			if remaining == 0 then finish({ status = "cancelled" }) end
			return
		end
		if result.code ~= 0 then
			if not optional_sources[name] and not required_error then
				required_error = { code = "version_fetch_failed", source = name, detail = result.stderr }
			end
		else
			responses[name] = result.stdout
		end
		if remaining > 0 then return end
		if required_error then
			callback(M.read(version), required_error)
			finish({ status = "generated", warnings = { required_error } })
			return
		end
		local ok, data = pcall(M.parse_responses, responses.loader, responses.yarn, responses.api, responses.kotlin, responses.loom)
		if not ok then
			local response_error = { code = "version_response_invalid", detail = data }
			callback(M.read(version), response_error)
			finish({ status = "generated", warnings = { response_error } })
			return
		end
		write_cache(version, data)
		callback(data, nil)
		finish({ status = "generated" })
	end
	for name, url in pairs(urls) do
		local ok, handle = pcall(run_system, { "curl", "--fail", "--silent", "--show-error", "--max-time", "10", url }, { text = true }, vim.schedule_wrap(function(result) complete(name, result) end))
		if ok then
			operation.handles[name] = handle
		else
			complete(name, { code = 1, stderr = tostring(handle) })
		end
	end
	return operation, nil
end

return M
