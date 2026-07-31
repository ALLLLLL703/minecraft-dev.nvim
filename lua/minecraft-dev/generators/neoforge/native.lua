local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local gradle = require("minecraft-dev.util.gradle")
local path = require("minecraft-dev.util.path")
local run_metadata = require("minecraft-dev.util.run_metadata")
local templates = require("minecraft-dev.generators.neoforge.templates")
local version = require("minecraft-dev.version")
local version_data = require("minecraft-dev.generators.neoforge.version_data")

local M = {}

local function quote(value)
	return vim.json.encode(tostring(value or ""))
end

local function at_least(actual, expected)
	return (version.compare(actual, expected) or -1) >= 0
end

local function render(template_name, values)
	return (
		templates.read(template_name):gsub("%${([A-Z][A-Z0-9_]*)}", function(key)
			local value = values[key]
			assert(value ~= nil, "missing NeoForge template value " .. key)
			return tostring(value)
		end)
	)
end

local function author_text(authors)
	if type(authors) == "table" then
		return table.concat(authors, ", ")
	end
	return type(authors) == "string" and authors or ""
end

local function toml_basic(value)
	local escaped = tostring(value or "")
		:gsub("\\", "\\\\")
		:gsub('"', '\\"')
		:gsub("\b", "\\b")
		:gsub("\t", "\\t")
		:gsub("\n", "\\n")
		:gsub("\f", "\\f")
		:gsub("\r", "\\r")
	return escaped:gsub("[%z\1-\7\11\14-\31\127]", function(character)
		return string.format("\\u%04X", string.byte(character))
	end)
end

local function property_value(value)
	return toml_basic(value):gsub("\\", "\\\\")
end

local function kotlin_versions(minecraft)
	if at_least(minecraft, "1.21") then
		return "5.3.0", "2.0.0"
	end
	if at_least(minecraft, "1.20.6") then
		return "5.2.0", "2.0.0"
	end
	return "5.0.0", "1.9.23"
end

local function config_template(minecraft)
	if at_least(minecraft, "1.21.3") then
		return "Config_1_21_3.java"
	end
	if at_least(minecraft, "1.21") then
		return "Config_1_21.java"
	end
	return "Config_1_20.java"
end

local function moddev_configuration(spec)
	local data_method = at_least(spec.minecraft_version, "1.21.4") and "clientData()" or "data()"
	local parchment = spec.parchment_version
			and string.format(
				[[
    parchment {
        minecraftVersion = %s
        mappingsVersion = %s
    }
]],
				quote(spec.parchment_minecraft_version or spec.minecraft_version),
				quote(spec.parchment_version)
			)
		or ""
	return string.format(
		[[neoForge {
    version = project.neo_version
%s
    runs {
        client { client(); systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id }
        server { server(); programArgument '--nogui'; systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id }
        gameTestServer { type = 'gameTestServer'; systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id }
        data {
            %s
            programArguments.addAll '--mod', project.mod_id, '--all', '--output', file('src/generated/resources/').absolutePath, '--existing', file('src/main/resources/').absolutePath
        }
        configureEach { logLevel = org.slf4j.event.Level.DEBUG }
    }
    mods { "${mod_id}" { sourceSet(sourceSets.main) } }
}
]],
		parchment,
		data_method
	)
end

local function neogradle_configuration()
	return [[runs {
    configureEach {
        systemProperty 'forge.logging.console.level', 'debug'
        modSource project.sourceSets.main
    }
    client { systemProperty 'forge.enabledGameTestNamespaces', project.mod_id }
    server { systemProperty 'forge.enabledGameTestNamespaces', project.mod_id; programArgument '--nogui' }
    gameTestServer { systemProperty 'forge.enabledGameTestNamespaces', project.mod_id }
    data {
        programArguments.addAll '--mod', project.mod_id, '--all', '--output', file('src/generated/resources/').absolutePath, '--existing', file('src/main/resources/').absolutePath
    }
}
]]
end

local function build_values(spec, java_version)
	local modern = at_least(spec.minecraft_version, "1.21")
	local kotlin = spec.language == "kotlin"
	local kff, kotlin_version = kotlin_versions(spec.minecraft_version)
	return {
		GRADLE_PLUGIN = modern
				and string.format("    id 'net.neoforged.moddev' version %s\n", quote(spec.moddev_version))
			or string.format("    id 'net.neoforged.gradle.userdev' version %s\n", quote(spec.neogradle_version)),
		KOTLIN_PLUGIN = kotlin
				and string.format("    id 'org.jetbrains.kotlin.jvm' version %s\n", quote(kotlin_version))
			or "",
		MOD_VERSION = quote(spec.plugin_version or "1.0.0"),
		GROUP_ID = quote(spec.group_id),
		MOD_ID_QUOTED = quote(spec.artifact_id),
		KOTLIN_REPOSITORY = kotlin and [[    maven {
        name = 'Kotlin for Forge'
        url = 'https://thedarkcolour.github.io/KotlinForForge/'
        content { includeGroup 'thedarkcolour' }
    }
]] or "",
		JAVA_VERSION = java_version,
		KOTLIN_TOOLCHAIN = kotlin and string.format("kotlin.jvmToolchain(%d)\n", java_version) or "",
		NEOFORGE_CONFIGURATION = modern and moddev_configuration(spec) or neogradle_configuration(),
		NEOFORGE_DEPENDENCY = modern and "" or '    implementation "net.neoforged:neoforge:${neo_version}"\n',
		KFF_DEPENDENCY = kotlin
				and string.format("    implementation 'thedarkcolour:kotlinforforge-neoforge:%s'\n", kff)
			or "",
		IDE_SYNC_TASK = modern and "neoForge.ideSyncTask generateModMetadata\n" or "",
	}
end

local function metadata_values(spec)
	local urls = ""
	if type(spec.update_url) == "string" and spec.update_url ~= "" then
		urls = urls .. 'updateJSONURL="${mod_update_url}"\n'
	end
	if type(spec.website) == "string" and spec.website ~= "" then
		urls = urls .. 'displayURL="${mod_website}"\n'
	end
	return {
		MOD_LOADER = quote(spec.language == "kotlin" and "kotlinforforge" or "javafml"),
		OPTIONAL_URLS = urls,
		MIXIN_ENTRY = spec.use_mixins
				and string.format("[[mixins]]\nconfig=%s\n\n", quote(spec.artifact_id .. ".mixins.json"))
			or "",
	}
end

local function mixin_config(spec, java_version)
	local config = {
		required = true,
		minVersion = "0.8",
		package = spec.package_name .. ".mixin",
		compatibilityLevel = "JAVA_" .. tostring(java_version),
		mixins = {},
		client = { "ExampleMixin" },
		injectors = { defaultRequire = 1 },
		overwrites = { requireAnnotations = true },
	}
	if not at_least(spec.minecraft_version, "1.20.2") then
		config.refmap = spec.artifact_id .. ".refmap.json"
	end
	return vim.json.encode(config) .. "\n"
end

local function pack_metadata(spec)
	local pack_format = at_least(spec.minecraft_version, "1.21.4") and 46
		or at_least(spec.minecraft_version, "1.21.2") and 42
		or at_least(spec.minecraft_version, "1.21") and 34
		or 32
	return vim.json.encode({ pack = { description = spec.artifact_id .. " resources", pack_format = pack_format } })
		.. "\n"
end

local function license_text(spec)
	return "SPDX-License-Identifier: "
		.. tostring(spec.license or "All Rights Reserved")
		.. "\nCopyright (c) "
		.. author_text(spec.authors)
		.. "\n"
end

---@param project_path string
---@param spec table
---@return table
function M.run(project_path, spec)
	local ctx = context.collect(spec)
	ctx.path = project_path
	ctx.package_path = ctx.package:gsub("%.", "/")
	local source_root = spec.language == "kotlin" and "src/main/kotlin" or "src/main/java"
	local source_dir = path.join(ctx.path, source_root, ctx.package_path)
	local resources = path.join(ctx.path, "src/main/resources")
	local template_metadata = path.join(ctx.path, "src/main/templates/META-INF")
	fs.mkdir(source_dir)
	fs.mkdir(resources)
	fs.mkdir(template_metadata)

	local derived =
		version_data.derive(spec.minecraft_version, spec.loader_version, spec.neogradle_version, spec.moddev_version)
	local java_version = version.required_java(spec.minecraft_version)
	local source_values = {
		PACKAGE = spec.package_name,
		MAIN_CLASS = spec.main_class,
		MOD_ID_QUOTED = quote(spec.artifact_id),
	}
	if spec.language == "kotlin" then
		fs.write_file(path.join(source_dir, spec.main_class .. ".kt"), render("Main.kt", source_values))
		local block_dir = path.join(source_dir, "block")
		fs.mkdir(block_dir)
		fs.write_file(path.join(block_dir, "ModBlocks.kt"), render("ModBlocks.kt", source_values))
	else
		fs.write_file(path.join(source_dir, spec.main_class .. ".java"), render("Main.java", source_values))
		fs.write_file(
			path.join(source_dir, "Config.java"),
			render(config_template(spec.minecraft_version), source_values)
		)
	end
	if spec.use_mixins then
		local mixin_dir = path.join(ctx.path, "src/main/java", ctx.package_path, "mixin")
		fs.mkdir(mixin_dir)
		fs.write_file(path.join(mixin_dir, "ExampleMixin.java"), render("ExampleMixin.java", source_values))
		fs.write_file(path.join(resources, spec.artifact_id .. ".mixins.json"), mixin_config(spec, java_version))
	end

	fs.write_file(path.join(ctx.path, "build.gradle"), render("build.gradle", build_values(spec, java_version)))
	fs.write_file(path.join(ctx.path, "settings.gradle"), [[pluginManagement {
    repositories { mavenLocal(); gradlePluginPortal(); maven { url = 'https://maven.neoforged.net/releases' } }
}
plugins { id 'org.gradle.toolchains.foojay-resolver-convention' version '0.8.0' }
rootProject.name = ]] .. quote(spec.artifact_id) .. "\n")
	local loader_range = spec.language == "kotlin" and "[5,)"
		or at_least(spec.minecraft_version, "1.21") and "[4,)"
		or "[2,)"
	local properties = {
		"org.gradle.jvmargs=-Xmx2G",
		"org.gradle.daemon=false",
		"minecraft_version=" .. derived.minecraft,
		"minecraft_version_range=[" .. derived.minecraft .. "," .. derived.minecraftNext .. ")",
		"neo_version=" .. derived.neoforge,
		"neo_version_range=[" .. derived.neoforgeSpec .. ",)",
		"loader_version_range=" .. loader_range,
		"mod_id=" .. spec.artifact_id,
		"mod_name=" .. property_value(spec.plugin_name or spec.artifact_id),
		"mod_license=" .. property_value(spec.license or "All Rights Reserved"),
		"mod_version=" .. (spec.plugin_version or "1.0.0"),
		"mod_group_id=" .. spec.group_id,
		"mod_authors=" .. property_value(author_text(spec.authors)),
		"mod_description=" .. property_value(spec.description or ""),
		"mod_update_url=" .. property_value(spec.update_url or ""),
		"mod_website=" .. property_value(spec.website or ""),
	}
	if spec.parchment_version then
		local prefix = at_least(spec.minecraft_version, "1.21") and "neoForge.parchment."
			or "neogradle.subsystems.parchment."
		table.insert(
			properties,
			prefix .. "minecraftVersion=" .. (spec.parchment_minecraft_version or spec.minecraft_version)
		)
		table.insert(properties, prefix .. "mappingsVersion=" .. spec.parchment_version)
	end
	fs.write_file(path.join(ctx.path, "gradle.properties"), table.concat(properties, "\n") .. "\n")
	fs.write_file(
		path.join(template_metadata, "neoforge.mods.toml"),
		render("neoforge.mods.toml", metadata_values(spec))
	)
	local lang_dir = path.join(resources, "assets", spec.artifact_id, "lang")
	fs.mkdir(lang_dir)
	fs.write_file(path.join(lang_dir, "en_us.json"), render("en_us.json", { MOD_ID = spec.artifact_id }))
	fs.write_file(path.join(resources, "pack.mcmeta"), pack_metadata(spec))
	fs.write_file(path.join(ctx.path, "LICENSE.txt"), license_text(spec))
	run_metadata.write(ctx.path, {
		{ type = "gradle", name = "NeoForge Client", args = { "runClient" } },
		{ type = "gradle", name = "NeoForge Server", args = { "runServer" } },
		{ type = "gradle", name = "NeoForge Data", args = { "runData" } },
		{ type = "gradle", name = "Build", args = { "build" } },
	})
	local gradle_version = at_least(spec.minecraft_version, "1.21") and "8.8" or "8.14"
	return gradle.generate_gradlew(ctx.path, nil, gradle_version)
end

return M
