local M = {}
local property_values = require("minecraft-dev.custom.property_values")

local WATERFALL_METADATA_URL = "https://repo.papermc.io/repository/maven-public/io/github/waterfallmc/waterfall-api/maven-metadata.xml"

---@param versions string[]
---@param minecraft_version string
---@return string?, table?
function M.select_waterfall_version(versions, minecraft_version)
	if type(minecraft_version) ~= "string" or minecraft_version == "" then
		return nil, { code = "waterfall_minecraft_version_invalid" }
	end
	for _, version in ipairs(versions or {}) do
		if version == minecraft_version then return version, nil end
	end
	local major, minor = minecraft_version:match("^(%d+)%.(%d+)")
	local family = major and minor and (major .. "." .. minor) or minecraft_version
	local escaped_family = family:gsub("([^%w])", "%%%1")
	local prefix = "^" .. escaped_family .. "%-R"
	for _, version in ipairs(versions or {}) do
		if version:match(prefix) or version == family .. "-SNAPSHOT" then return version, nil end
	end
	return nil, { code = "waterfall_version_not_found", minecraft_version = minecraft_version }
end

---@param minecraft_version string
---@param callback fun(version: string?, error: table?)
---@param system? fun(command: string[], options: table, callback: fun(result: table)): table
---@return table?, table?
function M.resolve_waterfall_version(minecraft_version, callback, system)
	return property_values.load({
		type = "maven_artifact_version",
		limit = 200,
		parameters = { sourceUrl = WATERFALL_METADATA_URL },
	}, function(versions, err)
		if not versions then callback(nil, err) return end
		local selected, select_error = M.select_waterfall_version(versions, minecraft_version)
		callback(selected, select_error)
	end, system)
end

return M
