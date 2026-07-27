local M = {}
local platforms = require("minecraft-dev.platforms")

local required_fields = {
	"platform",
	"build_system",
	"minecraft_version",
	"directory",
	"group_id",
	"artifact_id",
	"package_name",
	"main_class",
	"language",
}

local function validation_error(code, field)
	return { code = code, field = field }
end

local function is_java_identifier(value)
	return type(value) == "string" and value:match("^[%a_$][%w_$]*$") ~= nil
end

local function is_package_name(value)
	if type(value) ~= "string" or value == "" then
		return false
	end
	for segment in value:gmatch("[^.]+") do
		if not is_java_identifier(segment) then
			return false
		end
	end
	return not value:match("^%.") and not value:match("%.$") and not value:match("%.%.")
end

---@param spec table
---@return table?, table?
function M.validate(spec)
	if type(spec) ~= "table" then
		return nil, validation_error("invalid_spec")
	end

	for _, field in ipairs(required_fields) do
		if type(spec[field]) ~= "string" or spec[field] == "" then
			return nil, validation_error("missing_field", field)
		end
	end

	if not platforms.get(spec.platform) then
		return nil, validation_error("unsupported_platform", "platform")
	end
	if not platforms.supports(spec.platform, spec.build_system) then
		return nil, validation_error("unsupported_build", "build_system")
	end
	if not is_package_name(spec.group_id) or not is_package_name(spec.package_name) then
		return nil, validation_error("invalid_package", "package_name")
	end
	if not is_java_identifier(spec.main_class) then
		return nil, validation_error("invalid_main_class", "main_class")
	end
	if not spec.artifact_id:match("^[%w_.-]+$") then
		return nil, validation_error("invalid_artifact_id", "artifact_id")
	end
	if spec.language ~= "java" and spec.language ~= "kotlin" then
		return nil, validation_error("unsupported_language", "language")
	end

	return vim.deepcopy(spec), nil
end

---@param spec table
---@return boolean?, table?
function M.generate(spec)
	local normalized, err = M.validate(spec)
	if not normalized then
		return nil, err
	end

	local platform = platforms.get(normalized.platform)
	assert(platform ~= nil)
	local generator = require(platform.generator)
	generator.run(normalized.build_system, normalized.directory, normalized.minecraft_version, normalized)
	return true, nil
end

return M
