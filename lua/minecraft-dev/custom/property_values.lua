local M = {}

local PAPER_VERSIONS_URL = "https://fill.papermc.io/v3/projects/paper"
local USER_AGENT = "minecraft-dev.nvim (https://github.com/ALLLLLL703/minecraft-dev.nvim)"

local function version_parts(version)
	local parts = {}
	for part in version:gmatch("%d+") do table.insert(parts, tonumber(part)) end
	return parts
end

local function compare_versions(left, right)
	local left_parts = version_parts(left)
	local right_parts = version_parts(right)
	for index = 1, math.max(#left_parts, #right_parts) do
		local difference = (left_parts[index] or 0) - (right_parts[index] or 0)
		if difference ~= 0 then return difference end
	end
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

---@param descriptor table
---@param callback fun(values: string[]?, error: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.load(descriptor, callback, system)
	if descriptor.type ~= "paper_versions" then return nil, { code = "unsupported_property_values", property_type = descriptor.type } end
	if type(callback) ~= "function" then return nil, { code = "callback_required" } end
	if vim.fn.executable("curl") ~= 1 and system == nil then return nil, { code = "curl_missing" } end

	local operation = { status = "pending" }
	local run_system = system or vim.system
	local command = {
		"curl", "--fail", "--silent", "--show-error", "--max-time", "10",
		"--header", "User-Agent: " .. USER_AGENT, PAPER_VERSIONS_URL,
	}
	local ok, handle = pcall(run_system, command, { text = true }, vim.schedule_wrap(function(result)
		if operation.status ~= "pending" then return end
		if operation.cancel_requested then
			operation.status = "cancelled"
			callback(nil, { code = "cancelled" })
			return
		end
		if result.code ~= 0 then
			operation.status = "failed"
			callback(nil, { code = "property_fetch_failed", property_type = descriptor.type, detail = result.stderr })
			return
		end
		local values, parse_error = M.parse_paper_versions(result.stdout)
		operation.status = values and "generated" or "failed"
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
