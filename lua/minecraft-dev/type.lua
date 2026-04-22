---@enum ProgrammingLanguage
local ProgrammingLanguage = {
	kotlin = "kotlin",
	java = "java",
}

---@class MinecraftDevConfig
---@field debug boolean

---@class MinecraftDevConfigOpt
---@field debug? boolean

return {
	ProgrammingLanguage = ProgrammingLanguage,
}
