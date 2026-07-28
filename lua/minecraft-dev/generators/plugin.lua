local M = {}
local context = require("minecraft-dev.context")
local fs = require("minecraft-dev.util.fs")
local gradle = require("minecraft-dev.util.gradle")
local path = require("minecraft-dev.util.path")

local definitions = {
	bungeecord = {
		repository = "https://oss.sonatype.org/content/groups/public/",
		coordinate = "net.md-5:bungeecord-api:%s",
		kind = "bungee",
	},
	waterfall = {
		repository = "https://repo.papermc.io/repository/maven-public/",
		coordinate = "io.github.waterfallmc:waterfall-api:%s-SNAPSHOT",
		kind = "bungee",
	},
	velocity = {
		repository = "https://repo.papermc.io/repository/maven-public/",
		coordinate = "com.velocitypowered:velocity-api:%s",
		kind = "velocity",
	},
	sponge = {
		repository = "https://repo.spongepowered.org/maven/",
		coordinate = "org.spongepowered:spongeapi:%s",
		kind = "sponge",
	},
}

local function split_coordinate(coordinate)
	return coordinate:match("^([^:]+):([^:]+):(.+)$")
end

local function quote(value)
	return vim.json.encode(value)
end

local function build_maven(ctx, spec, definition)
	local coordinate = string.format(definition.coordinate, ctx.version)
	local group, artifact, dependency_version = split_coordinate(coordinate)
	local kotlin = ""
	local source_directory = ""
	if spec.language == "kotlin" then
		source_directory = "\n    <sourceDirectory>src/main/kotlin</sourceDirectory>"
		kotlin = [[
      <plugin>
        <groupId>org.jetbrains.kotlin</groupId>
        <artifactId>kotlin-maven-plugin</artifactId>
        <version>2.0.20</version>
        <executions><execution><goals><goal>compile</goal></goals></execution></executions>
      </plugin>]]
	end
	local processor = ""
	if definition.kind == "velocity" then
		processor = string.format([[
		<configuration><annotationProcessorPaths><path>
			<groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version>
		</path></annotationProcessorPaths></configuration>]], group, artifact, dependency_version)
	end
	return string.format([[<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version>
  <properties><maven.compiler.release>21</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
  <build>%s<plugins>
		<plugin><groupId>org.apache.maven.plugins</groupId><artifactId>maven-compiler-plugin</artifactId><version>3.13.0</version>%s</plugin>%s
    </plugins></build>
  <repositories><repository><id>platform</id><url>%s</url></repository></repositories>
  <dependencies>
		<dependency><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version><scope>provided</scope></dependency>
  </dependencies>
</project>
]], ctx.groupId, ctx.artifactId, spec.plugin_version or "1.0.0", source_directory, processor, kotlin, definition.repository, group, artifact, dependency_version)
end

local function build_gradle(ctx, spec, definition)
	local coordinate = string.format(definition.coordinate, ctx.version)
	local plugins = spec.language == "kotlin" and '    kotlin("jvm") version "2.0.20"' or '    java'
	local processor = definition.kind == "velocity" and '\n    annotationProcessor("' .. coordinate .. '")' or ""
	return string.format([[plugins {
%s
}
group = %s
version = %s
repositories { mavenCentral(); maven { url = uri(%s) } }
dependencies { compileOnly(%s)%s }
java { toolchain.languageVersion.set(JavaLanguageVersion.of(21)) }
]], plugins, quote(ctx.groupId), quote(spec.plugin_version or "1.0.0"), quote(definition.repository), quote(coordinate), processor)
end

local function bungee_manifest(ctx, spec)
	local lines = {
		"name: " .. quote(spec.plugin_name or ctx.artifactId),
		"main: " .. quote(ctx.package .. "." .. ctx.main),
		"version: " .. quote(spec.plugin_version or "1.0.0"),
	}
	if spec.authors and #spec.authors > 0 then table.insert(lines, "author: " .. quote(table.concat(spec.authors, ", "))) end
	if spec.description and spec.description ~= "" then table.insert(lines, "description: " .. quote(spec.description)) end
	if spec.depend and #spec.depend > 0 then table.insert(lines, "depends: " .. vim.json.encode(spec.depend)) end
	if spec.soft_depend and #spec.soft_depend > 0 then table.insert(lines, "softDepends: " .. vim.json.encode(spec.soft_depend)) end
	return table.concat(lines, "\n") .. "\n"
end

local function annotation_values(spec)
	local values = {
		"id = " .. quote(spec.plugin_id or spec.artifact_id),
		"name = " .. quote(spec.plugin_name or spec.artifact_id),
		"version = " .. quote(spec.plugin_version or "1.0.0"),
	}
	if spec.description and spec.description ~= "" then table.insert(values, "description = " .. quote(spec.description)) end
	if spec.website and spec.website ~= "" then table.insert(values, "url = " .. quote(spec.website)) end
	if spec.authors and #spec.authors > 0 then table.insert(values, "authors = { " .. table.concat(vim.tbl_map(quote, spec.authors), ", ") .. " }") end
	return table.concat(values, ",\n    ")
end

local function source_content(ctx, spec, kind)
	if spec.language == "kotlin" then
		if kind == "bungee" then
			return string.format("package %s\n\nimport net.md_5.bungee.api.plugin.Plugin\n\nclass %s : Plugin() {\n    override fun onEnable() { logger.info(\"Enabled\") }\n}\n", ctx.package, ctx.main)
		elseif kind == "velocity" then
			return string.format("package %s\n\nimport com.velocitypowered.api.plugin.Plugin\n\n@Plugin(\n    %s\n)\nclass %s\n", ctx.package, annotation_values(spec), ctx.main)
		end
		return string.format("package %s\n\nimport org.spongepowered.plugin.builtin.jvm.Plugin\n\n@Plugin(%s)\nclass %s\n", ctx.package, quote(spec.plugin_id or ctx.artifactId), ctx.main)
	end
	if kind == "bungee" then
		return string.format("package %s;\n\nimport net.md_5.bungee.api.plugin.Plugin;\n\npublic final class %s extends Plugin {\n    @Override public void onEnable() { getLogger().info(\"Enabled\"); }\n}\n", ctx.package, ctx.main)
	elseif kind == "velocity" then
		return string.format("package %s;\n\nimport com.velocitypowered.api.plugin.Plugin;\n\n@Plugin(\n    %s\n)\npublic final class %s {}\n", ctx.package, annotation_values(spec), ctx.main)
	end
	return string.format("package %s;\n\nimport org.spongepowered.plugin.builtin.jvm.Plugin;\n\n@Plugin(%s)\npublic final class %s {}\n", ctx.package, quote(spec.plugin_id or ctx.artifactId), ctx.main)
end

local function sponge_metadata(ctx, spec)
	local contributors = vim.tbl_map(function(author) return { name = author } end, spec.authors or {})
	return vim.json.encode({
		loader = { name = "java_plain", version = "1.0" },
		license = spec.license or "All-Rights-Reserved",
		plugins = { {
			id = spec.plugin_id or ctx.artifactId,
			name = spec.plugin_name or ctx.artifactId,
			version = spec.plugin_version or "1.0.0",
			entrypoint = ctx.package .. "." .. ctx.main,
			description = spec.description or "",
			contributors = contributors,
		} },
	}) .. "\n"
end

function M.run(build_system, project_path, platform_version, spec, platform_name)
	local platform = platform_name or (spec and spec.platform)
	local definition = assert(definitions[platform], "unsupported plugin platform: " .. tostring(platform))
	if not spec then
		local collected = context.collect()
		spec = {
			platform = platform, group_id = collected.groupId, artifact_id = collected.artifactId,
			package_name = collected.package, main_class = collected.main, language = "java",
			plugin_version = "1.0.0",
		}
	end
	local ctx = context.collect(spec)
	ctx.path = project_path or vim.fn.getcwd()
	ctx.version = platform_version
	ctx.package_path = ctx.package:gsub("%.", "/")
	local language_dir = spec.language == "kotlin" and "kotlin" or "java"
	local extension = spec.language == "kotlin" and ".kt" or ".java"
	local source_dir = path.join(ctx.path, "src/main", language_dir, ctx.package_path)
	fs.mkdir(source_dir)
	fs.write_file(path.join(source_dir, ctx.main .. extension), source_content(ctx, spec, definition.kind))
	local operation
	if build_system == "maven" then
		fs.write_file(path.join(ctx.path, "pom.xml"), build_maven(ctx, spec, definition))
	else
		fs.write_file(path.join(ctx.path, "build.gradle.kts"), build_gradle(ctx, spec, definition))
		fs.write_file(path.join(ctx.path, "settings.gradle.kts"), "rootProject.name = " .. quote(ctx.artifactId) .. "\n")
		operation = gradle.generate_gradlew(ctx.path)
	end
	if definition.kind == "bungee" then
		local resources = path.join(ctx.path, "src/main/resources")
		fs.mkdir(resources)
		fs.write_file(path.join(resources, "bungee.yml"), bungee_manifest(ctx, spec))
	elseif definition.kind == "sponge" then
		local resources = path.join(ctx.path, "src/main/resources/META-INF")
		fs.mkdir(resources)
		fs.write_file(path.join(resources, "sponge_plugins.json"), sponge_metadata(ctx, spec))
	end
	return operation or true
end

return M
