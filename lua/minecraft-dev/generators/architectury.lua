local M = {}
M.versions = { gradle = "8.10.1", loom = "1.6-SNAPSHOT" }
local fs = require("minecraft-dev.util.fs")
local gradle = require("minecraft-dev.util.gradle")
local path = require("minecraft-dev.util.path")

local function write(root, relative, content)
	local target = path.join(root, relative)
	fs.mkdir(vim.fs.dirname(target))
	fs.write_file(target, content)
end

local function quote(value)
	return vim.json.encode(value)
end

local function root_build(spec)
	return string.format([[plugins {
    id 'architectury-plugin' version '3.4-SNAPSHOT'
	id 'dev.architectury.loom' version '%s' apply false
}
architectury { minecraft = %s }
allprojects {
    group = %s
    version = %s
}
subprojects {
    apply plugin: 'dev.architectury.loom'
    apply plugin: 'architectury-plugin'
    apply plugin: 'maven-publish'
    base { archivesName = %s + '-' + project.name }
    repositories { mavenCentral(); maven { url = 'https://maven.architectury.dev/' } }
    dependencies { minecraft 'com.mojang:minecraft:%s'; mappings loom.officialMojangMappings() }
    java.toolchain.languageVersion = JavaLanguageVersion.of(21)
}
]], M.versions.loom, quote(spec.minecraft_version), quote(spec.group_id), quote(spec.plugin_version or "1.0.0"), quote(spec.artifact_id), spec.minecraft_version)
end

local function common_build(spec)
	return string.format([[architectury { common('fabric', 'forge') }
dependencies {
    modImplementation 'net.fabricmc:fabric-loader:%s'
    api 'dev.architectury:architectury:%s'
}
]], spec.fabric_loader_version, spec.architectury_api_version)
end

local function fabric_build(spec)
	return string.format([[plugins { id 'com.github.johnrengelman.shadow' version '7.1.2' }
architectury { platformSetupLoomIde(); fabric() }
configurations {
	common
	compileClasspath.extendsFrom common
	runtimeClasspath.extendsFrom common
	developmentFabric.extendsFrom common
	shadowCommon
}
dependencies {
    modImplementation 'net.fabricmc:fabric-loader:%s'
    modApi 'net.fabricmc.fabric-api:fabric-api:%s'
	modApi 'dev.architectury:architectury-fabric:%s'
	common(project(path: ':common', configuration: 'namedElements')) { transitive false }
	shadowCommon(project(path: ':common', configuration: 'transformProductionFabric')) { transitive false }
}
shadowJar { configurations = [project.configurations.shadowCommon]; archiveClassifier = 'dev-shadow' }
remapJar { inputFile.set(shadowJar.archiveFile); dependsOn shadowJar; archiveClassifier = null }
]], spec.fabric_loader_version, spec.fabric_api_version, spec.architectury_api_version)
end

local function forge_build(spec)
	return string.format([[plugins { id 'com.github.johnrengelman.shadow' version '7.1.2' }
loom { forge { } }
architectury { platformSetupLoomIde(); forge() }
configurations {
	common
	compileClasspath.extendsFrom common
	runtimeClasspath.extendsFrom common
	developmentForge.extendsFrom common
	shadowCommon
}
dependencies {
    forge 'net.minecraftforge:forge:%s-%s'
	modApi 'dev.architectury:architectury-forge:%s'
	common(project(path: ':common', configuration: 'namedElements')) { transitive false }
	shadowCommon(project(path: ':common', configuration: 'transformProductionForge')) { transitive false }
}
shadowJar { configurations = [project.configurations.shadowCommon]; archiveClassifier = 'dev-shadow' }
remapJar { inputFile.set(shadowJar.archiveFile); dependsOn shadowJar; archiveClassifier = null }
]], spec.minecraft_version, spec.forge_version, spec.architectury_api_version)
end

local function fabric_metadata(spec)
	return vim.json.encode({
		schemaVersion = 1,
		id = spec.artifact_id,
		version = "${version}",
		name = spec.plugin_name or spec.artifact_id,
		entrypoints = { main = { spec.package_name .. ".fabric." .. spec.main_class .. "Fabric" } },
		depends = { fabricloader = ">=" .. spec.fabric_loader_version, minecraft = "~" .. spec.minecraft_version, architectury = "*" },
	}) .. "\n"
end

local function forge_metadata(spec)
	return string.format([=[modLoader="javafml"
loaderVersion="[1,)"
license=%s

[[mods]]
modId=%s
version="${file.jarVersion}"
displayName=%s
description='''%s'''

[[dependencies.%s]]
modId="forge"
mandatory=true
versionRange="[%s,)"
ordering="NONE"
side="BOTH"
]=], quote(spec.license or "All-Rights-Reserved"), quote(spec.artifact_id), quote(spec.plugin_name or spec.artifact_id), spec.description or "", spec.artifact_id, spec.forge_version)
end

function M.run(_, project_path, _, spec)
	local root = project_path
	local package_path = spec.package_name:gsub("%.", "/")
	write(root, "settings.gradle", "pluginManagement { repositories { gradlePluginPortal(); maven { url = 'https://maven.architectury.dev/' }; maven { url = 'https://maven.fabricmc.net/' }; maven { url = 'https://maven.minecraftforge.net/' } } }\nrootProject.name = " .. quote(spec.artifact_id) .. "\ninclude 'common', 'fabric', 'forge'\n")
	write(root, "build.gradle", root_build(spec))
	write(root, "gradle.properties", "org.gradle.jvmargs=-Xmx3G\n")
	write(root, "common/build.gradle", common_build(spec))
	write(root, "fabric/build.gradle", fabric_build(spec))
	write(root, "forge/build.gradle", forge_build(spec))
	write(root, "forge/gradle.properties", "loom.platform=forge\n")
	write(root, "common/src/main/java/" .. package_path .. "/" .. spec.main_class .. ".java", string.format("package %s;\n\npublic final class %s {\n    public static void init() { }\n}\n", spec.package_name, spec.main_class))
	write(root, "fabric/src/main/java/" .. package_path .. "/fabric/" .. spec.main_class .. "Fabric.java", string.format("package %s.fabric;\n\nimport net.fabricmc.api.ModInitializer;\nimport %s.%s;\n\npublic final class %sFabric implements ModInitializer {\n    @Override public void onInitialize() { %s.init(); }\n}\n", spec.package_name, spec.package_name, spec.main_class, spec.main_class, spec.main_class))
	write(root, "forge/src/main/java/" .. package_path .. "/forge/" .. spec.main_class .. "Forge.java", string.format("package %s.forge;\n\nimport net.minecraftforge.fml.common.Mod;\nimport %s.%s;\n\n@Mod(%s)\npublic final class %sForge {\n    public %sForge() { %s.init(); }\n}\n", spec.package_name, spec.package_name, spec.main_class, quote(spec.artifact_id), spec.main_class, spec.main_class, spec.main_class))
	write(root, "fabric/src/main/resources/fabric.mod.json", fabric_metadata(spec))
	write(root, "forge/src/main/resources/META-INF/mods.toml", forge_metadata(spec))
	return gradle.generate_gradlew(root, nil, M.versions.gradle)
end

return M
