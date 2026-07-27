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

---@param loader_content string
---@param yarn_content string
---@param api_content string
---@return FabricVersionData
function M.parse_responses(loader_content, yarn_content, api_content)
	local loaders = assert(decode(loader_content), "invalid Fabric loader response")
	local yarn = assert(decode(yarn_content), "invalid Yarn response")
	local api = assert(decode(api_content), "invalid Fabric API response")
	assert(loaders[1] and loaders[1].loader and loaders[1].loader.version, "Fabric loader response is empty")
	assert(api[1] and api[1].version_number, "Fabric API response is empty")
	return {
		loader = loaders[1].loader.version,
		yarn = yarn[1] and yarn[1].version or nil,
		fabric_api = api[1].version_number,
		loom_version = require("minecraft-dev").config.defaults.fabric.version_data.loom_version,
	}
end

---@class FabricVersionData
---@field loom_version string
---@field fabric_api string|string[]
---@field loader string
---@field yarn string?

---@return FabricVersionData
function M.default_data()
	return vim.deepcopy(require("minecraft-dev").config.defaults.fabric.version_data)
end

---@param version string
---@return FabricVersionData
function M.read(version)
	local cached = decode(read_path(cache_path(version)))
	if cached then
		cached._cached_at = nil
		return cached
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
	return vim.fn.json_decode(content)
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
---@return table?, table?
function M.resolve(version, callback)
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	if vim.fn.executable("curl") ~= 1 then callback(M.read(version), { code = "curl_missing" }) return nil, nil end
	local encoded_version = vim.uri_encode(version)
	local urls = {
		loader = "https://meta.fabricmc.net/v2/versions/loader/" .. encoded_version,
		yarn = "https://meta.fabricmc.net/v2/versions/yarn/" .. encoded_version,
		api = "https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%5B%22" .. encoded_version .. "%22%5D&loaders=%5B%22fabric%22%5D",
	}
	local operation = { handles = {}, cancelled = false }
	function operation.cancel()
		operation.cancelled = true
		for _, handle in pairs(operation.handles) do handle:kill(15) end
	end
	local responses = {}
	local remaining = 3
	local finished = false
	local function complete(name, result)
		if operation.cancelled or finished then return end
		if result.code ~= 0 then
			finished = true
			callback(M.read(version), { code = "version_fetch_failed", source = name, detail = result.stderr })
			return
		end
		responses[name] = result.stdout
		remaining = remaining - 1
		if remaining > 0 then return end
		local ok, data = pcall(M.parse_responses, responses.loader, responses.yarn, responses.api)
		if not ok then callback(M.read(version), { code = "version_response_invalid", detail = data }) return end
		write_cache(version, data)
		callback(data, nil)
	end
	for name, url in pairs(urls) do
		operation.handles[name] = vim.system({ "curl", "--fail", "--silent", "--show-error", "--max-time", "10", url }, { text = true }, vim.schedule_wrap(function(result) complete(name, result) end))
	end
	return operation, nil
end

return M
