---@enum ProgrammingLanguage
local ProgrammingLanguage = {
	kotlin = "kotlin",
	java = "java",
}

---@class MinecraftDevConfig
---@field logging { debug: boolean }
---@field defaults { project: { group_id: string, artifact_id: string, main_class: string }, command: { use_cwd_when_path_missing: boolean }, translations: { order: "ascending"|"descending"|"like-default"|"template", default_locale: string, indent: string, template_path: string?, diagnostics: boolean, source_diagnostics: boolean, source_scan_max_files: integer, source_calls: string[] }, metadata: { diagnostics: boolean, source_scan_max_files: integer }, mappings: { paths: string[] }, mixin: { indent: string }, source_generation: { indent: string, source_root: string }, source_insight: { colors: boolean, event_diagnostics: boolean }, nbt: { python: string, timeout_ms: integer, max_input_bytes: integer, max_output_bytes: integer, max_depth: integer, max_tags: integer, max_array_length: integer, max_string_bytes: integer }, paper: { version: string, language: ProgrammingLanguage }, fabric: { version: string, language: ProgrammingLanguage, side: "client"|"server"|"both", generate_datagen: boolean, use_mixins: boolean, cache_ttl: number, version_data: { gradle_version: string, loom_version: string, fabric_api: string|string[], kotlin_loader: string, loader: string, yarn: string? } } }
---@field prompts { mappings: { select_mapping: string }, mixin: { find_title: string }, translations: { select_translation: string, usages_title: string }, custom: { select_template: string, directory: string, project_name: string, property: string, property_json: string, group_id: string, artifact_id: string, project_version: string }, project: { group_id: string, artifact_id: string, main_class: string }, paper: { select_language: string, telescope_title: string }, fabric: { loom_version: string, select_language: string, select_side: string, generate_datagen: string, use_mixins: string, telescope_title: string }, forge: { minecraft_version: string, loader_version: string } }
---@field messages table<string, table<string, string>>

---@class MinecraftDevConfigOpt
---@field debug? boolean
---@field logging? { debug?: boolean }
---@field defaults? { project?: { group_id?: string, artifact_id?: string, main_class?: string }, command?: { use_cwd_when_path_missing?: boolean }, translations?: { order?: "ascending"|"descending"|"like-default"|"template", default_locale?: string, indent?: string, template_path?: string, diagnostics?: boolean, source_diagnostics?: boolean, source_scan_max_files?: integer, source_calls?: string[] }, metadata?: { diagnostics?: boolean, source_scan_max_files?: integer }, mappings?: { paths?: string[] }, mixin?: { indent?: string }, source_generation?: { indent?: string, source_root?: string }, source_insight?: { colors?: boolean, event_diagnostics?: boolean }, nbt?: { python?: string, timeout_ms?: integer, max_input_bytes?: integer, max_output_bytes?: integer, max_depth?: integer, max_tags?: integer, max_array_length?: integer, max_string_bytes?: integer }, paper?: { version?: string, language?: ProgrammingLanguage }, fabric?: { version?: string, language?: ProgrammingLanguage, side?: "client"|"server"|"both", generate_datagen?: boolean, use_mixins?: boolean, cache_ttl?: number, version_data?: { gradle_version?: string, loom_version?: string, fabric_api?: string|string[], kotlin_loader?: string, loader?: string, yarn?: string? } } }
---@field prompts? { mappings?: { select_mapping?: string }, mixin?: { find_title?: string }, translations?: { select_translation?: string, usages_title?: string }, custom?: { select_template?: string, directory?: string, project_name?: string, property?: string, property_json?: string, group_id?: string, artifact_id?: string, project_version?: string }, project?: { group_id?: string, artifact_id?: string, main_class?: string }, paper?: { select_language?: string, telescope_title?: string }, fabric?: { loom_version?: string, select_language?: string, select_side?: string, generate_datagen?: string, use_mixins?: string, telescope_title?: string }, forge?: { minecraft_version?: string, loader_version?: string } }
---@field messages? table<string, table<string, string>>

return {
	ProgrammingLanguage = ProgrammingLanguage,
}
