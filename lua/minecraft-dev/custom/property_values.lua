local M = {}

local PAPER_VERSIONS_URL = "https://fill.papermc.io/v3/projects/paper"
local USER_AGENT = "minecraft-dev.nvim (https://github.com/ALLLLLL703/minecraft-dev.nvim)"

local function parse_version(version)
	if type(version) ~= "string" then return nil end
	local base, suffix = version:match("^(%d[%d%.]*)(.*)$")
	if not base or base:sub(-1) == "." or base:find("..", 1, true) then return nil end
	local parts = {}
	for part in base:gmatch("%d+") do table.insert(parts, tonumber(part)) end
	if #parts == 0 or (suffix ~= "" and not suffix:match("^[%w%._%+%-]+$")) then return nil end
	return { parts = parts, suffix = suffix:lower() }
end

local function compare_versions(left, right)
	local left_version = assert(parse_version(left))
	local right_version = assert(parse_version(right))
	local left_parts = left_version.parts
	local right_parts = right_version.parts
	for index = 1, math.max(#left_parts, #right_parts) do
		local difference = (left_parts[index] or 0) - (right_parts[index] or 0)
		if difference ~= 0 then return difference end
	end
	local left_suffix = left_version.suffix
	local right_suffix = right_version.suffix
	if left_suffix == "" and right_suffix ~= "" then return 1 end
	if left_suffix ~= "" and right_suffix == "" then return -1 end
	local left_prefix, left_number = left_suffix:match("^(.-)(%d+)$")
	local right_prefix, right_number = right_suffix:match("^(.-)(%d+)$")
	if left_prefix and left_prefix == right_prefix and left_number ~= right_number then
		return tonumber(left_number) - tonumber(right_number)
	end
	if left_suffix ~= right_suffix then return left_suffix > right_suffix and 1 or -1 end
	return 0
end

---@param content string
---@return string[]?, table?
function M.parse_paper_versions(content)
	local ok, response = pcall(vim.json.decode, content or "")
	if not ok or type(response) ~= "table" or type(response.versions) ~= "table" then
		return nil, { code = "property_response_invalid", property_type = "paper_versions" }
	end
	local versions = {}
	local seen = {}
	for _, group in pairs(response.versions) do
		if type(group) == "table" then
			for _, version in ipairs(group) do
				if type(version) == "string"
					and version:match("^%d+%.%d+[%.%d]*$")
					and parse_version(version)
					and compare_versions(version, "1.18.2") >= 0
					and not seen[version]
				then
					seen[version] = true
					table.insert(versions, version)
				end
			end
		end
	end
	table.sort(versions, function(left, right) return compare_versions(left, right) > 0 end)
	if #versions == 0 then return nil, { code = "property_response_empty", property_type = "paper_versions" } end
	return versions, nil
end

---@param content string
---@param limit? integer
---@return string[]?, table?
function M.parse_maven_versions(content, limit)
	if type(content) ~= "string" or not content:find("<metadata", 1, true) then
		return nil, { code = "property_response_invalid", property_type = "maven_versions" }
	end
	limit = limit == nil and 50 or limit
	if type(limit) ~= "number" or limit <= 0 or limit % 1 ~= 0 then
		return nil, { code = "property_limit_invalid", property_type = "maven_versions" }
	end
	local versions = {}
	local seen = {}
	for version in content:gmatch("<version>%s*([^<]+)%s*</version>") do
		version = vim.trim(version)
		if parse_version(version) and not seen[version] then
			seen[version] = true
			table.insert(versions, version)
		end
	end
	table.sort(versions, function(left, right) return compare_versions(left, right) > 0 end)
	if #versions == 0 then return nil, { code = "property_response_empty", property_type = "maven_versions" } end
	local limited = {}
	for index = 1, math.min(#versions, limit) do limited[index] = versions[index] end
	return limited, nil
end

---@param descriptor table
---@param callback fun(values: string[]?, error: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.load(descriptor, callback, system)
	local maven_property = descriptor.type == "maven_artifact_version" or descriptor.type == "gradle_plugin"
	if descriptor.type ~= "paper_versions" and not maven_property then
		return nil, { code = "unsupported_property_values", property_type = descriptor.type }
	end
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	if vim.fn.executable("curl") ~= 1 and system == nil then return nil, { code = "curl_missing" } end
	local source_url = descriptor.type == "paper_versions" and PAPER_VERSIONS_URL
		or descriptor.parameters and descriptor.parameters.sourceUrl
	if type(source_url) ~= "string" or source_url == "" then
		return nil, { code = "property_source_missing", property_type = descriptor.type }
	end
	if not source_url:match("^https?://") then
		return nil, { code = "property_source_invalid", property_type = descriptor.type }
	end

	local operation = { status = "pending", callbacks = {} }
	function operation.on_complete(completion_callback)
		if operation.result then completion_callback(operation.result) else table.insert(operation.callbacks, completion_callback) end
		return operation
	end
	local function complete(status, err)
		operation.status = status
		operation.result = { status = status, error = err }
		for _, completion_callback in ipairs(operation.callbacks) do completion_callback(operation.result) end
		operation.callbacks = {}
	end
	local run_system = system or vim.system
	local command = {
		"curl", "--fail", "--silent", "--show-error", "--max-time", "10",
		"--header", "User-Agent: " .. USER_AGENT, "--url", source_url,
	}
	local ok, handle = pcall(run_system, command, { text = true }, vim.schedule_wrap(function(result)
		if operation.status ~= "pending" then return end
		if operation.cancel_requested then
			local err = { code = "cancelled" }
			complete("cancelled", err)
			callback(nil, err)
			return
		end
		if result.code ~= 0 then
			local err = { code = "property_fetch_failed", property_type = descriptor.type, detail = result.stderr }
			complete("failed", err)
			callback(nil, err)
			return
		end
		local parsed, values, parse_error = pcall(function()
			if descriptor.type == "paper_versions" then return M.parse_paper_versions(result.stdout) end
			return M.parse_maven_versions(result.stdout, descriptor.limit)
		end)
		if not parsed then
			local err = { code = "property_response_invalid", property_type = descriptor.type, detail = values }
			complete("failed", err)
			callback(nil, err)
			return
		end
		complete(values and "generated" or "failed", parse_error)
		callback(values, parse_error)
	end))
	if not ok then return nil, { code = "property_fetch_failed", property_type = descriptor.type, detail = tostring(handle) } end
	operation.handle = handle
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if operation.handle and operation.handle.kill then operation.handle:kill(15) end
	end
	return operation, nil
end

return M
