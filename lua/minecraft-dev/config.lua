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
	return normalized
end

return M
