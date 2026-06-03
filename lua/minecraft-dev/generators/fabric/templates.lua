local path_util = require("minecraft-dev.util.path")
local template = require("minecraft-dev.util.template")

local M = {}

local LANGUAGE_SPECIFIC_FILES = {
	["Main.java"] = true,
	["Client.java"] = true,
	["Data.java"] = true,
	["Mixin.java"] = true,
	["Main.kt"] = true,
	["Client.kt"] = true,
	["Data.kt"] = true,
	["Mixin.kt"] = true,
}

---@param sub_path string
---@param lang ProgrammingLanguage
---@return string
function M.read(sub_path, lang)
	local archetype_path = "archetype/fabric_gradle"
	if lang == "kotlin" and LANGUAGE_SPECIFIC_FILES[sub_path] then
		archetype_path = path_util.join(archetype_path, "kotlin")
	end

	return template.read_runtime_file(path_util.join(archetype_path, sub_path))
end

return M
