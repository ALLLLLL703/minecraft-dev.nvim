local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local gradle = require("minecraft-dev.util.gradle")
local path = require("minecraft-dev.util.path")
local run_metadata = require("minecraft-dev.util.run_metadata")
local templates = require("minecraft-dev.generators.forge.templates")
local version = require("minecraft-dev.version")
local version_data = require("minecraft-dev.generators.forge.version_data")

local M = {}

local function quote(value)
	return vim.json.encode(tostring(value or ""))
end

local function at_least(actual, expected)
	return (version.compare(actual, expected) or -1) >= 0
end

local function render(template_name, values)
	return (templates.read(template_name):gsub("%${([A-Z][A-Z0-9_]*)}", function(key)
		local value = values[key]
		assert(value ~= nil, "missing Forge template value " .. key)
		return tostring(value)
	end))
end

local function main_template(minecraft)
	for _, boundary in ipairs({
		{ "1.20.6", "Main_1_20_6.java" },
		{ "1.20", "Main_1_20.java" },
		{ "1.19.3", "Main_1_19_3.java" },
		{ "1.19", "Main_1_19.java" },
		{ "1.18", "Main_1_18.java" },
		{ "1.17", "Main_1_17.java" },
		{ "1.16", "Main_1_16.java" },
	}) do
		if at_least(minecraft, boundary[1]) then return boundary[2] end
	end
	error("unsupported Forge Minecraft version " .. minecraft)
end

local function pack_metadata(spec)
	local minecraft = spec.minecraft_version
	local pack_format = at_least(minecraft, "1.21") and 34
		or at_least(minecraft, "1.20.5") and 32
		or at_least(minecraft, "1.20.3") and 22
		or at_least(minecraft, "1.20.2") and 18
		or at_least(minecraft, "1.20") and 15
		or at_least(minecraft, "1.19.4") and 12
		or at_least(minecraft, "1.19") and 10
		or at_least(minecraft, "1.18.2") and 9
		or at_least(minecraft, "1.18") and 8
		or at_least(minecraft, "1.17") and 7
		or at_least(minecraft, "1.16.2") and 6
		or 5
	local pack = { description = spec.artifact_id .. " resources", pack_format = pack_format }
	if at_least(minecraft, "1.19.4") and not at_least(minecraft, "1.20") then
		pack["forge:server_data_pack_format"] = 12
	elseif at_least(minecraft, "1.19.3") and not at_least(minecraft, "1.19.4") then
		pack["forge:resource_pack_format"] = 12
		pack["forge:data_pack_format"] = 10
	elseif at_least(minecraft, "1.19") and not at_least(minecraft, "1.19.3") then
		pack["forge:resource_pack_format"] = 8
		pack["forge:data_pack_format"] = 9
	end
	return vim.json.encode({ pack = pack }) .. "\n"
end

local function author_text(authors)
	if type(authors) == "table" then return table.concat(authors, ", ") end
	return type(authors) == "string" and authors or ""
end

local function metadata(spec, derived)
	local lines = {
		'modLoader="javafml"',
		'loaderVersion="[' .. derived.forgeSpec .. ',)"',
		"license=" .. quote(spec.license or "All Rights Reserved"),
		"",
		"[[mods]]",
		"modId=" .. quote(spec.artifact_id),
		"version=" .. quote(spec.plugin_version or "1.0.0"),
		"displayName=" .. quote(spec.plugin_name or spec.artifact_id),
	}
	if type(spec.update_url) == "string" and spec.update_url ~= "" then table.insert(lines, "updateJSONURL=" .. quote(spec.update_url)) end
	if type(spec.website) == "string" and spec.website ~= "" then table.insert(lines, "displayURL=" .. quote(spec.website)) end
	table.insert(lines, "authors=" .. quote(author_text(spec.authors)))
	table.insert(lines, "description=" .. quote(spec.description or ""))
	vim.list_extend(lines, {
		"",
		"[[dependencies." .. quote(spec.artifact_id) .. "]]",
		'modId="forge"',
		"mandatory=true",
		'versionRange="[' .. derived.forgeSpec .. ',)"',
		'ordering="NONE"',
		'side="BOTH"',
		"",
		"[[dependencies." .. quote(spec.artifact_id) .. "]]",
		'modId="minecraft"',
		"mandatory=true",
		'versionRange="[' .. derived.minecraft .. ',' .. derived.minecraftNext .. ')"',
		'ordering="NONE"',
		'side="BOTH"',
	})
	return table.concat(lines, "\n") .. "\n"
end

local function mixin_config(spec, java_version)
	return vim.json.encode({
		required = true,
		minVersion = "0.8",
		package = spec.package_name .. ".mixin",
		compatibilityLevel = "JAVA_" .. tostring(java_version),
		refmap = spec.artifact_id .. ".refmap.json",
		mixins = {},
		client = { "ExampleMixin" },
		injectors = { defaultRequire = 1 },
	}) .. "\n"
end

local function license_text(spec)
	local license = spec.license or "All Rights Reserved"
	local owner = author_text(spec.authors)
	if license ~= "MIT" then return "SPDX-License-Identifier: " .. license .. "\nCopyright (c) " .. owner .. "\n" end
	return string.format([[MIT License

Copyright (c) %s

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]], owner)
end

local function build_values(spec, java_version)
	local use_mixins = spec.use_mixins == true
	local merged_sources = at_least(spec.minecraft_version, "1.20.3")
	local modern_runtime = at_least(spec.minecraft_version, "1.20.6")
	local mappings = spec.parchment_version
		and string.format("channel: 'parchment', version: %s", quote(spec.parchment_version .. "-" .. spec.minecraft_version))
		or string.format("channel: 'official', version: '%s'", spec.minecraft_version)
	return {
		MIXIN_BUILDSCRIPT = use_mixins and [[buildscript {
    repositories { maven { url = 'https://repo.spongepowered.org/repository/maven-public/' }; mavenCentral() }
    dependencies { classpath 'org.spongepowered:mixingradle:0.7-SNAPSHOT' }
}

]] or "",
		PARCHMENT_PLUGIN = spec.parchment_version and "    id 'org.parchmentmc.librarian.forgegradle' version '1.+'\n" or "",
		MIXIN_APPLY = use_mixins and "apply plugin: 'org.spongepowered.mixin'\n" or "",
		GROUP_ID = quote(spec.group_id),
		MOD_VERSION = quote(spec.plugin_version or "1.0.0"),
		MOD_ID_QUOTED = quote(spec.artifact_id),
		JAVA_VERSION = java_version,
		MAPPINGS = mappings,
		REOBF_PROPERTY = modern_runtime and "    reobf = false\n" or "",
		RUN_MODS = merged_sources and "" or string.format("            mods { %s { source sourceSets.main } }\n", quote(spec.artifact_id)),
		MIXIN_BLOCK = use_mixins and string.format([[mixin {
    add sourceSets.main, '%s.refmap.json'
    config '%s.mixins.json'
}
]], spec.artifact_id, spec.artifact_id) or "",
		MINECRAFT_VERSION = spec.minecraft_version,
		FORGE_VERSION = spec.loader_version,
		MIXIN_DEPENDENCY = use_mixins and "    annotationProcessor 'org.spongepowered:mixin:0.8.5:processor'\n" or "",
		MODERN_DEPENDENCY = modern_runtime and "    implementation('net.sf.jopt-simple:jopt-simple:5.0.4') { version { strictly '5.0.4' } }\n" or "",
		AUTHORS = quote(author_text(spec.authors)),
		REOBF_JAR = modern_runtime and "" or "    finalizedBy 'reobfJar'\n",
		MERGED_SOURCES = merged_sources and [[sourceSets.each {
    def merged = layout.buildDirectory.dir("sourcesSets/$it.name")
    it.output.resourcesDir = merged
    it.java.destinationDirectory = merged
}
]] or "",
	}
end

---@param project_path string
---@param spec table
---@return table
function M.run(project_path, spec)
	local ctx = context.collect(spec)
	ctx.path = project_path
	ctx.package_path = ctx.package:gsub("%.", "/")
	local source_dir = path.join(ctx.path, "src/main/java", ctx.package_path)
	local resources = path.join(ctx.path, "src/main/resources")
	local metadata_dir = path.join(resources, "META-INF")
	fs.mkdir(source_dir)
	fs.mkdir(metadata_dir)

	local derived = version_data.derive(spec.minecraft_version, spec.loader_version)
	local java_version = version.required_java(spec.minecraft_version)
	local values = {
		PACKAGE = spec.package_name,
		MAIN_CLASS = spec.main_class,
		MOD_ID_QUOTED = quote(spec.artifact_id),
	}
	local injection = (version.compare(spec.loader_version, "52.0.9") or -1) >= 0
		or ((version.compare(spec.loader_version, "50.1.17") or -1) >= 0 and (version.compare(spec.loader_version, "51.0.0") or -1) < 0)
	values.CONTEXT_PARAMETER = injection and "FMLJavaModLoadingContext context" or ""
	values.EVENT_BUS = injection and "context.getModEventBus()" or "FMLJavaModLoadingContext.get().getModEventBus()"
	values.REGISTER_CONFIG = not at_least(spec.minecraft_version, "1.20.1") and ""
		or injection and "context.registerConfig(ModConfig.Type.COMMON, Config.SPEC);"
		or "ModLoadingContext.get().registerConfig(ModConfig.Type.COMMON, Config.SPEC);"

	fs.write_file(path.join(source_dir, spec.main_class .. ".java"), render(main_template(spec.minecraft_version), values))
	if at_least(spec.minecraft_version, "1.20.1") then
		local config_template = at_least(spec.minecraft_version, "1.21") and "Config_1_21.java" or "Config_1_20.java"
		fs.write_file(path.join(source_dir, "Config.java"), render(config_template, values))
	end
	if spec.use_mixins then
		local mixin_dir = path.join(source_dir, "mixin")
		fs.mkdir(mixin_dir)
		fs.write_file(path.join(mixin_dir, "ExampleMixin.java"), render("ExampleMixin.java", values))
		fs.write_file(path.join(resources, spec.artifact_id .. ".mixins.json"), mixin_config(spec, java_version))
	end

	fs.write_file(path.join(ctx.path, "build.gradle"), render("build.gradle", build_values(spec, java_version)))
	fs.write_file(path.join(ctx.path, "settings.gradle"), [[pluginManagement {
    repositories { gradlePluginPortal(); maven { url = 'https://maven.minecraftforge.net/' }; maven { url = 'https://repo.spongepowered.org/repository/maven-public/' } }
}
plugins { id 'org.gradle.toolchains.foojay-resolver-convention' version '0.8.0' }
rootProject.name = ]] .. quote(spec.artifact_id) .. "\n")
	fs.write_file(path.join(ctx.path, "gradle.properties"), table.concat({
		"org.gradle.jvmargs=-Xmx3G", "org.gradle.daemon=false",
		"minecraft_version=" .. derived.minecraft,
		"minecraft_version_range=[" .. derived.minecraft .. "," .. derived.minecraftNext .. ")",
		"forge_version=" .. derived.forge,
		"forge_version_range=[" .. derived.forgeSpec .. ",)",
		"loader_version_range=[" .. derived.forgeSpec .. ",)",
	}, "\n") .. "\n")
	fs.write_file(path.join(metadata_dir, "mods.toml"), metadata(spec, derived))
	fs.write_file(path.join(resources, "pack.mcmeta"), pack_metadata(spec))
	fs.write_file(path.join(ctx.path, "LICENSE.txt"), license_text(spec))
	run_metadata.write(ctx.path, {
		{ type = "gradle", name = "Forge Client", args = { "runClient" } },
		{ type = "gradle", name = "Forge Server", args = { "runServer" } },
		{ type = "gradle", name = "Forge Data", args = { "runData" } },
		{ type = "gradle", name = "Build", args = { "build" } },
	})
	return gradle.generate_gradlew(ctx.path, nil, "8.8")
end

return M
