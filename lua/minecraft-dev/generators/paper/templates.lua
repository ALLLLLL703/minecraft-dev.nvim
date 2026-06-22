local template = require("minecraft-dev.util.template")

local M = {}

local LANGUAGE_SPECIFIC_FILES = {
	["Main.java"] = true,
	["Main.kt"] = true,
	["build.gradle.kts"] = true,
	["pom.xml"] = true,
}

---@param build_tool "gradle"|"maven"
---@param sub_path string
---@param lang? ProgrammingLanguage
---@return string
function M.read(build_tool, sub_path, lang)
	local base_path = string.format("archetype/paper_%s", build_tool)
	local file_name = sub_path:match("[^/\\]+$") or sub_path
	if lang == "kotlin" and LANGUAGE_SPECIFIC_FILES[file_name] then
		base_path = string.format("%s/kotlin", base_path)
	end

	return template.read_runtime_file(string.format("%s/%s", base_path, sub_path))
end

return M
