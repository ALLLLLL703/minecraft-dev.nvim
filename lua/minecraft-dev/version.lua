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

	if major == 1 and minor >= 13 then
		return "v1_13_plus"
	elseif major == 1 and minor < 13 then
		return "v1_8"
	end
end
return M
