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
			source_scan_max_files = 1000,
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
		metadata = {
			diagnostics = true,
			source_scan_max_files = 1000,
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
			usages_title = "Minecraft translation usages",
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
			translation_usages_not_found = "No translation usages were found: %s",
			translation_missing = "Translation key does not exist in the default locale: %s",
			translation_format_missing = "Translation call is missing format arguments: %s",
			translation_format_superfluous = "Translation call has superfluous format arguments: %s",
			translation_deprecated_removed = "Translation key was removed in deprecated.json: %s",
			translation_deprecated_renamed = "Translation key was renamed in deprecated.json: %s",
			buffer_unloaded = "Translation buffer is not loaded.",
			failed = "Failed to sort Minecraft translations: %s",
		},
		metadata = {
			main_required = "Bukkit plugin manifest requires a main class.",
			main_duplicate = "Bukkit plugin manifest defines main more than once.",
			main_invalid = "Invalid Bukkit plugin main class: %s",
			main_unresolved = "Bukkit plugin main class was not found: %s",
			main_resolution_incomplete = "Could not fully scan project classes for Bukkit main: %s",
			main_abstract = "Bukkit plugin main class must be concrete: %s",
			main_wrong_type = "Bukkit plugin main class must implement org.bukkit.plugin.Plugin: %s",
			main_type_unverified = "Could not verify the Bukkit plugin superclass chain: %s",
			invalid_yaml = "Invalid Bukkit plugin YAML.",
			not_bukkit_manifest = "Current buffer is not plugin.yml or paper-plugin.yml.",
			parser_unavailable = "Required Tree-sitter parser is unavailable: %s",
			field_required = "Bukkit plugin manifest requires field: %s",
			field_duplicate = "Bukkit plugin manifest defines a field more than once: %s",
			field_scalar_required = "Bukkit plugin manifest field must be a non-empty scalar: %s",
			field_mapping_required = "Bukkit plugin manifest field must be a mapping: %s",
			field_sequence_required = "Bukkit plugin manifest field must be a sequence: %s",
			api_version_invalid = "Invalid Bukkit api-version; expected major.minor: %s",
			dependency_name_invalid = "Bukkit dependency name must be a non-empty scalar: %s",
			dependency_duplicate = "Bukkit dependency is listed more than once: %s",
			dependency_self = "Bukkit plugin cannot depend on itself: %s",
			paper_dependency_phase_invalid = "Paper dependency phase must be a mapping: %s",
			paper_dependency_invalid = "Paper dependency declaration must be a mapping: %s",
			paper_dependency_load_invalid = "Paper dependency load must be BEFORE, AFTER, or OMIT: %s",
			paper_dependency_boolean_invalid = "Paper dependency option must be boolean: %s",
			invalid_toml = "Invalid Forge/NeoForge mod manifest TOML.",
			not_forge_manifest = "Current buffer is not mods.toml or neoforge.mods.toml.",
			toml_field_required = "Forge/NeoForge mod manifest requires field: %s",
			toml_field_duplicate = "Forge/NeoForge mod manifest defines a field more than once: %s",
			toml_field_string_required = "Forge/NeoForge manifest field must be a non-empty string: %s",
			toml_field_type_invalid = "Forge/NeoForge manifest field has the wrong type; expected %s",
			toml_mods_required = "Forge/NeoForge manifest requires at least one [[mods]] table.",
			toml_mod_id_invalid = "Invalid Forge/NeoForge mod ID: %s",
			toml_mod_id_duplicate = "Forge/NeoForge mod ID is declared more than once: %s",
			toml_mod_id_required = "Place the cursor on a dependency owner or provide a mod ID.",
			toml_mod_id_unresolved = "Forge/NeoForge mod ID was not declared in this manifest: %s",
			toml_mod_source_unresolved = "No Java/Kotlin @Mod class declares this mod ID: %s",
			toml_mod_source_unverified = "Could not fully scan Java/Kotlin @Mod classes for mod ID: %s",
			toml_dependency_owner_unresolved = "Dependency table targets an undeclared mod ID: %s",
			toml_version_range_invalid = "Invalid Maven version range: %s",
			toml_display_test_invalid = "Unknown Forge displayTest value: %s",
			toml_ordering_invalid = "Unknown Forge dependency ordering: %s",
			toml_side_invalid = "Unknown Forge dependency side: %s",
			toml_logo_unresolved = "Forge/NeoForge logoFile was not found in resources: %s",
			toml_logo_required = "Place the cursor on a logoFile value.",
			fabric_root_invalid = "fabric.mod.json root must be an object.",
			invalid_json = "Invalid Minecraft metadata JSON.",
			not_fabric_manifest = "Current buffer is not fabric.mod.json.",
			fabric_field_required = "fabric.mod.json requires field: %s",
			fabric_field_duplicate = "fabric.mod.json defines a field more than once: %s",
			fabric_field_type_invalid = "fabric.mod.json field has the wrong type; expected %s",
			fabric_field_empty = "fabric.mod.json field must not be empty: %s",
			fabric_schema_first = "schemaVersion must be the first fabric.mod.json field.",
			fabric_schema_invalid = "Unsupported fabric.mod.json schemaVersion: %s",
			fabric_mod_id_invalid = "Invalid Fabric mod ID: %s",
			fabric_environment_invalid = "Invalid Fabric environment: %s",
			fabric_dependency_invalid = "Fabric dependency value must be a string or string array: %s",
			fabric_entrypoint_invalid = "Fabric entrypoint must be a string or object with a string value: %s",
			fabric_entrypoint_required = "Place the cursor on a Fabric entrypoint or provide one.",
			fabric_entrypoint_unresolved = "Fabric entrypoint class was not found: %s",
			fabric_entrypoint_unverified = "Could not fully scan Fabric entrypoint classes: %s",
			fabric_entrypoint_ambiguous = "Fabric entrypoint resolves to more than one class: %s",
			fabric_entrypoint_wrong_type = "Fabric entrypoint implements the wrong initializer type: %s",
			fabric_entrypoint_type_unverified = "Could not verify the Fabric entrypoint inheritance chain: %s",
			fabric_entrypoint_member_unresolved = "Fabric entrypoint method or field was not found: %s",
			fabric_entrypoint_member_private = "Fabric entrypoint method or field must be public: %s",
			fabric_entrypoint_method_parameters = "Fabric entrypoint method must have no parameters: %s",
			fabric_entrypoint_field_static = "Fabric entrypoint field must be static: %s",
			fabric_entrypoint_constructor_invalid = "Fabric entrypoint class requires an empty constructor: %s",
			fabric_resource_type_invalid = "Fabric resource reference must be a string: %s",
			fabric_resource_name_invalid = "Fabric resource filename has an invalid form: %s",
			fabric_resource_required = "Place the cursor on a Fabric resource reference.",
			fabric_resource_unresolved = "Fabric resource file was not found: %s",
			not_mixin_config = "Current buffer is not a Mixin JSON/JSON5 config.",
			mixin_root_invalid = "Mixin config root must be an object.",
			mixin_field_duplicate = "Mixin config defines a field more than once: %s",
			mixin_field_type_invalid = "Mixin config field has the wrong type; expected %s",
			mixin_package_required = "Mixin config requires a non-empty package.",
			mixin_package_invalid = "Invalid Mixin package name: %s",
			mixin_package_unresolved = "No local @Mixin classes exist under package: %s",
			mixin_package_unverified = "Could not fully scan @Mixin classes under package: %s",
			mixin_compatibility_invalid = "Invalid Mixin compatibilityLevel: %s",
			mixin_class_invalid = "Mixin list item must be a non-empty string: %s",
			mixin_class_duplicate = "Mixin class is listed more than once: %s",
			mixin_class_unresolved = "Mixin class was not found: %s",
			mixin_class_unverified = "Could not fully scan Mixin classes: %s",
			mixin_class_ambiguous = "Mixin class resolves to more than one declaration: %s",
			mixin_class_wrong_type = "Mixin config class must carry @Mixin: %s",
			mixin_plugin_invalid = "Mixin plugin must be a non-empty class name.",
			mixin_plugin_unresolved = "Mixin plugin class was not found: %s",
			mixin_plugin_ambiguous = "Mixin plugin resolves to more than one declaration: %s",
			mixin_plugin_wrong_type = "Mixin plugin must be concrete and implement IMixinConfigPlugin: %s",
			mixin_reference_required = "Place the cursor on a Mixin class/plugin reference or provide one.",
			mixin_reference_unresolved = "Mixin class/plugin reference was not found: %s",
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
	if
		type(translations.source_scan_max_files) ~= "number"
		or translations.source_scan_max_files < 1
		or translations.source_scan_max_files % 1 ~= 0
	then
		translations.source_scan_max_files = M.default_config.defaults.translations.source_scan_max_files
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
	if type(normalized.defaults.metadata) ~= "table" then
		---@diagnostic disable-next-line: inject-field, undefined-field
		normalized.defaults.metadata = vim.deepcopy(M.default_config.defaults.metadata)
	end
	local metadata = normalized.defaults.metadata
	if type(metadata.diagnostics) ~= "boolean" then
		metadata.diagnostics = true
	end
	if
		type(metadata.source_scan_max_files) ~= "number"
		or metadata.source_scan_max_files < 1
		or metadata.source_scan_max_files % 1 ~= 0
	then
		---@diagnostic disable-next-line: undefined-field
		metadata.source_scan_max_files = M.default_config.defaults.metadata.source_scan_max_files
	end
	return normalized
end

return M
