local M = {}

---@type MinecraftDevConfig
M.default_config = {
	logging = {
		debug = false,
	},
	defaults = {
		project = {
			group_id = "com.example",
			artifact_id = "demo",
			main_class = "Main",
		},
		command = {
			use_cwd_when_path_missing = true,
		},
		translations = {
			order = "ascending",
			default_locale = "en_us",
			indent = "  ",
			template_path = nil,
			diagnostics = true,
			source_diagnostics = true,
			source_calls = {
				"Component.translatable",
				"Component.translatableEscape",
				"Component.translatableEscaped",
				"I18n.get",
				"I18n.format",
				"StatCollector.translateToLocal",
				"StatCollector.translateToLocalFormatted",
			},
		},
		paper = {
			version = "1.21",
			language = "java",
		},
		fabric = {
			version = "1.21",
			language = "java",
			side = "both",
			generate_datagen = true,
			use_mixins = false,
			use_official_mappings = true,
			use_fabric_api = true,
			split_sources = true,
			client_mixins = true,
			cache_ttl = 24 * 60 * 60,
			version_data = {
				gradle_version = "9.6.1",
				loom_version = "1.16-SNAPSHOT",
				fabric_api = "0.146.0+",
				kotlin_loader = "1.13.13+kotlin.2.4.10",
				loader = "0.19.2",
				yarn = nil,
			},
		},
	},
	prompts = {
		translations = {
			select_translation = "Select Minecraft translation",
		},
		custom = {
			select_template = "Select Minecraft project template",
			directory = "Project directory: ",
			project_name = "Project name: ",
			property = "%s: ",
			property_json = "%s (JSON): ",
			group_id = "Group ID: ",
			artifact_id = "Artifact ID: ",
			project_version = "Project version: ",
		},
		project = {
			group_id = "groupId?",
			artifact_id = "artifactId?",
			main_class = "main class name?",
		},
		paper = {
			select_language = "Select language",
			telescope_title = "select Paper language",
		},
		fabric = {
			loom_version = "loom version?",
			select_language = "Select language",
			select_side = "Select environment side",
			show_snapshots = "Show Minecraft snapshots?",
			minecraft_version = "Select Minecraft version",
			loader_version = "Select Fabric Loader version",
			yarn_version = "Select Yarn mappings",
			use_official_mappings = "Use official Mojang mappings?",
			use_fabric_api = "Use Fabric API?",
			fabric_api_version = "Select Fabric API version",
			split_sources = "Split client sources?",
			client_mixins = "Generate a separate client Mixin?",
			generate_datagen = "Generate datagen entrypoint?",
			use_mixins = "Generate mixin config and example?",
			telescope_title = "select language",
		},
		forge = {
			minecraft_version = "Select Minecraft version",
			loader_version = "Select Forge version",
		},
		neoforge = {
			minecraft_version = "Select Minecraft version",
			loader_version = "Select NeoForge version",
			neogradle_version = "Select NeoGradle version",
			moddev_version = "Select ModDevGradle version",
			use_parchment = "Use Parchment mappings?",
			parchment_version = "Select Parchment mappings version",
		},
	},
	messages = {
		project = {
			generated = "Generated Minecraft project at %s",
		},
		custom = {
			list_failed = "Failed to list Minecraft templates: %s",
			generation_failed = "Failed to generate template: %s",
			generated = "Generated Minecraft project at %s",
			invalid_json = "Invalid JSON value for %s",
			property_failed = "Failed to load template property: %s",
		},
		command = {
			invalid_args = "Usage: GmcPro [platform build minecraft_version [path]]",
			unsupported_project = "Unsupported project type: %s",
			unsupported_build = "Unsupported build tool: %s",
			interactive_only = "%s requires the project wizard; run :GmcPro without arguments.",
			generation_failed = "Failed to start project generation: %s",
		},
		translations = {
			sorted = "Sorted Minecraft translations (%s).",
			invalid_order = "Unsupported translation sort order: %s",
			invalid_json = "Invalid translation JSON: %s",
			invalid_root = "Translation JSON must contain a root object.",
			invalid_value = "Translation value must be a string: %s",
			duplicate_key = "Translation file contains a duplicate key: %s",
			empty_key = "Translation key is empty at line %s.",
			invalid_lang = "Invalid legacy translation syntax at line %s.",
			not_translation_file = "Current buffer is not a Minecraft translation file: %s",
			missing_default = "Default locale translation file was not found: %s",
			missing_template = "Minecraft translation sorting template was not found: %s",
			whitespace_key = "Translation key contains whitespace at the start or end: %s",
			missing_default_key = "Translation key is not included in the default locale: %s",
			format_mismatch = "Translation format arguments do not match the default locale: %s",
			translation_key_required = "Place the cursor on a translation key or provide one explicitly.",
			translation_not_found = "Default locale translation was not found: %s",
			translation_missing = "Translation key does not exist in the default locale: %s",
			translation_format_missing = "Translation call is missing format arguments: %s",
			translation_format_superfluous = "Translation call has superfluous format arguments: %s",
			translation_deprecated_removed = "Translation key was removed in deprecated.json: %s",
			translation_deprecated_renamed = "Translation key was renamed in deprecated.json: %s",
			buffer_unloaded = "Translation buffer is not loaded.",
			failed = "Failed to sort Minecraft translations: %s",
		},
		reload = {
			success = "Successfully reloaded minecraft-dev!",
			module_reloaded = "%s reloaded",
		},
		template = {
			missing = "Template file not found: %s",
			open_failed = "Failed to open template file: %s",
			reading = "Reading template file: %s",
		},
		data = {
			version_file_missing = "Data json file for version %s not found; using defaults.",
			version_file_open_failed = "Failed to open version data for %s; using defaults.",
			reading_json = "Reading json data file: %s",
		},
		gradle = {
			missing = "Gradle is not installed or not in PATH",
			generating = "Generating Gradle Wrapper...",
			failed = "Failed to generate Gradle Wrapper: %s",
			success = "Gradle Wrapper generated successfully.",
		},
		paper = {
			generated_gradle_high = "Generated Paper Gradle project (1.13+) at %s",
			generated_gradle_low = "Generated Paper Gradle project (1.13-) at %s",
			generated_maven = "Generated Paper Maven project at: %s\nmc_version: %s",
		},
		fabric = {
			generating_gradle = "Generating Fabric project with Gradle",
			maven_unsupported = "Fabric Maven template is not supported yet",
			lower_version_unsupported = "Lower Minecraft versions are not supported for Fabric yet",
			generated = "Generated Fabric mod project successfully.",
			no_matching_yarn = "No Yarn mappings match Minecraft %s; showing fallback versions.",
			no_matching_api = "No Fabric API version matches Minecraft %s; showing fallback versions.",
		},
	},
}

---@param opts? MinecraftDevConfig | MinecraftDevConfigOpt
---@return MinecraftDevConfig
function M.normalize(opts)
	local normalized = vim.deepcopy(opts or {})

	if normalized.debug ~= nil then
		normalized.logging = normalized.logging or {}
		if normalized.logging.debug == nil then
			normalized.logging.debug = normalized.debug
		end
		normalized.debug = nil
	end

	normalized = vim.tbl_deep_extend("force", vim.deepcopy(M.default_config), normalized)
	if type(normalized.defaults.fabric.cache_ttl) ~= "number" or normalized.defaults.fabric.cache_ttl < 0 then
		normalized.defaults.fabric.cache_ttl = M.default_config.defaults.fabric.cache_ttl
	end
	if type(normalized.defaults.translations) ~= "table" then
		normalized.defaults.translations = vim.deepcopy(M.default_config.defaults.translations)
	end
	local translations = normalized.defaults.translations
	if not require("minecraft-dev.translations").is_order(translations.order) then
		translations.order = M.default_config.defaults.translations.order
	end
	if type(translations.default_locale) ~= "string" or not translations.default_locale:match("^[%w_%-]+$") then
		translations.default_locale = M.default_config.defaults.translations.default_locale
	end
	if type(translations.indent) ~= "string" or translations.indent == "" or translations.indent:find("[\r\n]") then
		translations.indent = M.default_config.defaults.translations.indent
	end
	if type(translations.template_path) ~= "string" or vim.trim(translations.template_path) == "" then
		translations.template_path = nil
	end
	if type(translations.diagnostics) ~= "boolean" then
		translations.diagnostics = true
	end
	if type(translations.source_diagnostics) ~= "boolean" then
		translations.source_diagnostics = true
	end
	if type(translations.source_calls) ~= "table" or not vim.islist(translations.source_calls) then
		translations.source_calls = vim.deepcopy(M.default_config.defaults.translations.source_calls)
	else
		for _, call in ipairs(translations.source_calls) do
			if type(call) ~= "string" or vim.trim(call) == "" then
				translations.source_calls = vim.deepcopy(M.default_config.defaults.translations.source_calls)
				break
			end
		end
	end
	return normalized
end

return M
