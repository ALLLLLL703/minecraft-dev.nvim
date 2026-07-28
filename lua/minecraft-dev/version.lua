local M = {}

---@param mc_version string
---@return "v1_13_plus" | "v1_8" | nil
function M.resolve_family(mc_version)
	if not mc_version then
		return "v1_13_plus"
	end
	local major, minor = mc_version:match("^(%d+)%.(%d+)")
	major = tonumber(major)
	minor = tonumber(minor)

	if major > 1 or (major == 1 and minor >= 13) then
		return "v1_13_plus"
	elseif major == 1 and minor < 13 then
		return "v1_8"
	end
end

local function compare(version, expected)
	local function core_parts(value)
		local major, minor, patch = value:match("^(%d+)%.(%d+)%.?(%d*)")
		if not major then return nil end
		return { tonumber(major), tonumber(minor), tonumber(patch) or 0 }
	end
	local actual_parts = core_parts(version)
	local expected_parts = core_parts(expected)
	if not actual_parts or not expected_parts then return nil end
	for index = 1, math.max(#actual_parts, #expected_parts) do
		local difference = (actual_parts[index] or 0) - (expected_parts[index] or 0)
		if difference ~= 0 then return difference end
	end
	return 0
end

---@param version string
---@return integer
function M.required_java(version)
	if type(version) ~= "string" then return 21 end
	local earliest_comparison = compare(version, "1.16.5")
	if earliest_comparison == nil then return 21 end
	if earliest_comparison <= 0 then return 8 end
	if compare(version, "1.17.1") <= 0 then return 16 end
	if compare(version, "1.20.4") <= 0 then return 17 end
	if compare(version, "1.21.11") <= 0 then return 21 end
	return 25
end

---@param version string
---@param expected_major integer
---@param expected_minor integer
---@return boolean
function M.at_least(version, expected_major, expected_minor)
	local major, minor = version:match("^(%d+)%.(%d+)")
	major = tonumber(major)
	minor = tonumber(minor)
	if not major or not minor then
		return false
	end
	return major > expected_major or (major == expected_major and minor >= expected_minor)
end

return M
