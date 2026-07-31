local M = {}
local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local forge_native = require("minecraft-dev.generators.forge.native")
local gradle = require("minecraft-dev.util.gradle")
local path = require("minecraft-dev.util.path")

local function quote(value)
	return vim.json.encode(value)
end

local function neoforge_build(spec)
	local parchment = spec.parchment_version and "\n" .. string.format([[    parchment {
        minecraftVersion = %s
        mappingsVersion = %s
    }]], quote(spec.minecraft_version), quote(spec.parchment_version)) or ""
	return string.format([[plugins {
    id 'java'
    id 'net.neoforged.moddev' version '2.0.116'
}
group = %s
version = %s
base { archivesName = %s }
java.toolchain.languageVersion = JavaLanguageVersion.of(21)
neoForge {
    version = %s%s
    runs {
        client { client() }
        server { server(); programArgument '--nogui' }
        data { data(); programArguments.addAll '--mod', %s, '--all', '--output', file('src/generated/resources/').absolutePath }
        configureEach { systemProperty 'forge.logging.console.level', 'debug' }
    }
    mods { %s { sourceSet sourceSets.main } }
}
sourceSets.main.resources { srcDir 'src/generated/resources' }
tasks.named('processResources', ProcessResources).configure {
    var replaceProperties = [mod_id: %s, mod_version: project.version, minecraft_version: %s, loader_version: %s]
    inputs.properties replaceProperties
    filesMatching(['META-INF/neoforge.mods.toml', 'pack.mcmeta']) { expand replaceProperties }
}
]], quote(spec.group_id), quote(spec.plugin_version or "1.0.0"), quote(spec.artifact_id), quote(spec.loader_version), parchment, quote(spec.artifact_id), spec.artifact_id, quote(spec.artifact_id), quote(spec.minecraft_version), quote(spec.loader_version))
end

local function main_source(spec, platform)
	local annotation = platform == "forge" and "net.minecraftforge.fml.common.Mod" or "net.neoforged.fml.common.Mod"
	return string.format([[package %s;

import %s;

@Mod(%s)
public final class %s {
    public %s() {
    }
}
]], spec.package_name, annotation, quote(spec.artifact_id), spec.main_class, spec.main_class)
end

local function mod_manifest(spec, platform)
	local loader = platform == "forge" and "javafml" or "javafml"
	local loader_range = platform == "forge" and "[1,)" or "[1,)"
	return string.format([=[modLoader=%s
loaderVersion=%s
license=%s

[[mods]]
modId=${mod_id}
version=${mod_version}
displayName=%s
description='''%s'''

[[dependencies.${mod_id}]]
modId=%s
type="required"
versionRange="[%s,)"
ordering="NONE"
side="BOTH"
]=], quote(loader), quote(loader_range), quote(spec.license or "All-Rights-Reserved"), quote(spec.plugin_name or spec.artifact_id), spec.description or "", platform == "forge" and "forge" or "neoforge", spec.loader_version)
end

local function mixin_json(spec)
	return vim.json.encode({
		required = true,
		package = spec.package_name .. ".mixin",
		compatibilityLevel = "JAVA_21",
		mixins = {},
		injectors = { defaultRequire = 1 },
	}) .. "\n"
end

function M.run(_, project_path, _, spec, platform_name)
	local platform = platform_name or spec.platform
	if platform == "forge" then return forge_native.run(project_path, spec) end
	local ctx = context.collect(spec)
	ctx.path = project_path
	ctx.package_path = ctx.package:gsub("%.", "/")
	local source_dir = path.join(ctx.path, "src/main/java", ctx.package_path)
	local resources = path.join(ctx.path, "src/main/resources")
	local metadata = path.join(resources, "META-INF")
	fs.mkdir(source_dir)
	fs.mkdir(metadata)
	fs.write_file(path.join(source_dir, ctx.main .. ".java"), main_source(spec, platform))
	fs.write_file(path.join(ctx.path, "build.gradle"), platform == "forge" and forge_build(spec) or neoforge_build(spec))
	fs.write_file(path.join(ctx.path, "settings.gradle"), "pluginManagement { repositories { gradlePluginPortal(); maven { url = 'https://maven.minecraftforge.net/' }; maven { url = 'https://maven.neoforged.net/releases' }; maven { url = 'https://repo.spongepowered.org/repository/maven-public/' } } }\nrootProject.name = " .. quote(ctx.artifactId) .. "\n")
	fs.write_file(path.join(ctx.path, "gradle.properties"), "org.gradle.jvmargs=-Xmx3G\norg.gradle.daemon=false\n")
	local manifest = platform == "forge" and "mods.toml" or "neoforge.mods.toml"
	fs.write_file(path.join(metadata, manifest), mod_manifest(spec, platform))
	fs.write_file(path.join(resources, "pack.mcmeta"), vim.json.encode({ pack = { description = spec.plugin_name or spec.artifact_id, pack_format = 34 } }) .. "\n")
	if spec.use_mixins then
		fs.write_file(path.join(resources, spec.artifact_id .. ".mixins.json"), mixin_json(spec))
	end
	return gradle.generate_gradlew(ctx.path)
end

return M
