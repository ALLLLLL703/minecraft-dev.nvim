---@enum ProgrammingLanguage
local ProgrammingLanguage = {
	kotlin = "kotlin",
	java = "java",
}

---@class MinecraftDevConfig
---@field logging { debug: boolean }
---@field defaults { project: { group_id: string, artifact_id: string, main_class: string }, command: { use_cwd_when_path_missing: boolean }, paper: { version: string }, fabric: { version: string, language: ProgrammingLanguage, side: "client"|"server"|"both", generate_datagen: boolean, use_mixins: boolean, version_data: { loom_version: string, fabric_api: string|string[], loader: string, yarn: string? } } }
---@field prompts { project: { group_id: string, artifact_id: string, main_class: string }, fabric: { loom_version: string, select_language: string, select_side: string, generate_datagen: string, use_mixins: string, telescope_title: string } }
---@field messages table<string, table<string, string>>

---@class MinecraftDevConfigOpt
---@field debug? boolean
---@field logging? { debug?: boolean }
---@field defaults? { project?: { group_id?: string, artifact_id?: string, main_class?: string }, command?: { use_cwd_when_path_missing?: boolean }, paper?: { version?: string }, fabric?: { version?: string, language?: ProgrammingLanguage, side?: "client"|"server"|"both", generate_datagen?: boolean, use_mixins?: boolean, version_data?: { loom_version?: string, fabric_api?: string|string[], loader?: string, yarn?: string? } } }
---@field prompts? { project?: { group_id?: string, artifact_id?: string, main_class?: string }, fabric?: { loom_version?: string, select_language?: string, select_side?: string, generate_datagen?: string, use_mixins?: string, telescope_title?: string } }
---@field messages? table<string, table<string, string>>

return {
	ProgrammingLanguage = ProgrammingLanguage,
}
