local notify = require("minecraft-dev.util.notify")
local template = require("minecraft-dev.util.template")

local M = {}

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
	local kotlin_loader = release_version(kotlin_content)
	if not valid_kotlin_loader(kotlin_loader) then kotlin_loader = defaults.kotlin_loader end
	local loom_version = release_version(loom_content) or defaults.loom_version
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

---@param version string
---@param callback fun(data: FabricVersionData, err: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.resolve(version, callback, system)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
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
