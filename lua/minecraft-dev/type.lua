---@enum ProgrammingLanguage
local ProgrammingLanguage = {
	kotlin = "kotlin",
	java = "java",
}

---@class MinecraftDevConfig
---@field logging { debug: boolean }
---@field defaults { project: { group_id: string, artifact_id: string, main_class: string }, command: { use_cwd_when_path_missing: boolean }, translations: { order: "ascending"|"descending"|"like-default"|"template", default_locale: string, indent: string, template_path: string? }, paper: { version: string, language: ProgrammingLanguage }, fabric: { version: string, language: ProgrammingLanguage, side: "client"|"server"|"both", generate_datagen: boolean, use_mixins: boolean, cache_ttl: number, version_data: { gradle_version: string, loom_version: string, fabric_api: string|string[], kotlin_loader: string, loader: string, yarn: string? } } }
---@field prompts { custom: { select_template: string, directory: string, project_name: string, property: string, property_json: string, group_id: string, artifact_id: string, project_version: string }, project: { group_id: string, artifact_id: string, main_class: string }, paper: { select_language: string, telescope_title: string }, fabric: { loom_version: string, select_language: string, select_side: string, generate_datagen: string, use_mixins: string, telescope_title: string }, forge: { minecraft_version: string, loader_version: string } }
---@field messages table<string, table<string, string>>

---@class MinecraftDevConfigOpt
---@field debug? boolean
---@field logging? { debug?: boolean }
---@field defaults? { project?: { group_id?: string, artifact_id?: string, main_class?: string }, command?: { use_cwd_when_path_missing?: boolean }, translations?: { order?: "ascending"|"descending"|"like-default"|"template", default_locale?: string, indent?: string, template_path?: string }, paper?: { version?: string, language?: ProgrammingLanguage }, fabric?: { version?: string, language?: ProgrammingLanguage, side?: "client"|"server"|"both", generate_datagen?: boolean, use_mixins?: boolean, cache_ttl?: number, version_data?: { gradle_version?: string, loom_version?: string, fabric_api?: string|string[], kotlin_loader?: string, loader?: string, yarn?: string? } } }
---@field prompts? { custom?: { select_template?: string, directory?: string, project_name?: string, property?: string, property_json?: string, group_id?: string, artifact_id?: string, project_version?: string }, project?: { group_id?: string, artifact_id?: string, main_class?: string }, paper?: { select_language?: string, telescope_title?: string }, fabric?: { loom_version?: string, select_language?: string, select_side?: string, generate_datagen?: string, use_mixins?: string, telescope_title?: string }, forge?: { minecraft_version?: string, loader_version?: string } }
---@field messages? table<string, table<string, string>>

return {
	ProgrammingLanguage = ProgrammingLanguage,
}
