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

local function velocity_java_version(version)
	local major, minor = tostring(version or ""):match("^(%d+)%.(%d+)")
	major, minor = tonumber(major), tonumber(minor)
	if not major then return 21 end
	if major > 3 or (major == 3 and minor >= 5) then return 21 end
	if major == 3 and minor >= 3 then return 17 end
	return 11
end

local function uses_velocity_processor(spec, definition)
	if definition.kind ~= "velocity" then return false end
	if spec.language == "kotlin" then return spec.use_annotation_processor == true end
	return spec.use_annotation_processor ~= false
end

local function build_maven(ctx, spec, definition)
	local coordinate = string.format(definition.coordinate, ctx.version)
	local group, artifact, dependency_version = split_coordinate(coordinate)
	local kotlin = ""
	local kotlin_dependency = ""
	local source_directory = ""
	local java_version = definition.kind == "velocity" and velocity_java_version(ctx.version) or 21
	if spec.language == "kotlin" then
		source_directory = "\n    <sourceDirectory>src/main/kotlin</sourceDirectory>"
		local kapt = ""
		if uses_velocity_processor(spec, definition) then
			kapt = string.format([[
			<execution><id>kapt</id><goals><goal>kapt</goal></goals><configuration>
				<sourceDirs><sourceDir>src/main/kotlin</sourceDir><sourceDir>src/main/java</sourceDir></sourceDirs>
				<annotationProcessorPaths><annotationProcessorPath>
					<groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version>
				</annotationProcessorPath></annotationProcessorPaths>
			</configuration></execution>]], group, artifact, dependency_version)
		end
		kotlin = string.format([[
      <plugin>
        <groupId>org.jetbrains.kotlin</groupId>
        <artifactId>kotlin-maven-plugin</artifactId>
        <version>2.1.20</version>
		<executions>%s<execution><goals><goal>compile</goal></goals></execution></executions>
		<configuration><jvmTarget>%d</jvmTarget></configuration>
      </plugin>]], kapt, java_version)
		kotlin_dependency = [[
		<dependency><groupId>org.jetbrains.kotlin</groupId><artifactId>kotlin-stdlib-jdk8</artifactId><version>2.1.20</version></dependency>]]
	end
	local processor = ""
	if uses_velocity_processor(spec, definition) and spec.language == "java" then
		processor = string.format([[
		<configuration><annotationProcessorPaths><path>
			<groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version>
		</path></annotationProcessorPaths></configuration>]], group, artifact, dependency_version)
	end
	return string.format([[<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version>
   <properties><maven.compiler.release>%d</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
  <build>%s<plugins>
		<plugin><groupId>org.apache.maven.plugins</groupId><artifactId>maven-compiler-plugin</artifactId><version>3.13.0</version>%s</plugin>%s
    </plugins></build>
  <repositories><repository><id>platform</id><url>%s</url></repository></repositories>
  <dependencies>
		<dependency><groupId>%s</groupId><artifactId>%s</artifactId><version>%s</version><scope>provided</scope></dependency>
%s
  </dependencies>
</project>
]], ctx.groupId, ctx.artifactId, spec.plugin_version or "1.0.0", java_version, source_directory, processor, kotlin, definition.repository, group, artifact, dependency_version, kotlin_dependency)
end

local function build_gradle(ctx, spec, definition)
	local coordinate = string.format(definition.coordinate, ctx.version)
	local java_version = definition.kind == "velocity" and velocity_java_version(ctx.version) or 21
	local processor_enabled = uses_velocity_processor(spec, definition)
	local plugins = spec.language == "kotlin" and '    kotlin("jvm") version "2.1.20"' or '    java'
	if spec.language == "kotlin" and processor_enabled then plugins = plugins .. '\n    kotlin("kapt") version "2.1.20"' end
	local processor = processor_enabled and '\n    ' .. (spec.language == "kotlin" and "kapt" or "annotationProcessor") .. '("' .. coordinate .. '")' or ""
	local toolchain = spec.language == "kotlin" and "kotlin { jvmToolchain(" .. java_version .. ") }"
		or "java { toolchain.languageVersion.set(JavaLanguageVersion.of(" .. java_version .. ")) }"
	return string.format([[plugins {
%s
}
group = %s
version = %s
repositories { mavenCentral(); maven { url = uri(%s) } }
dependencies { compileOnly(%s)%s }
%s
]], plugins, quote(ctx.groupId), quote(spec.plugin_version or "1.0.0"), quote(definition.repository), quote(coordinate), processor, toolchain)
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

local function annotation_values(spec, kotlin)
	local values = {
		"id = " .. quote(spec.plugin_id or spec.artifact_id),
		"name = " .. quote(spec.plugin_name or spec.artifact_id),
		"version = " .. quote(spec.plugin_version or "1.0.0"),
	}
	if spec.description and spec.description ~= "" then table.insert(values, "description = " .. quote(spec.description)) end
	if spec.website and spec.website ~= "" then table.insert(values, "url = " .. quote(spec.website)) end
	if spec.authors and #spec.authors > 0 then
		local delimiters = kotlin and { "[ ", " ]" } or { "{ ", " }" }
		table.insert(values, "authors = " .. delimiters[1] .. table.concat(vim.tbl_map(quote, spec.authors), ", ") .. delimiters[2])
	end
	return table.concat(values, ",\n    ")
end

local function source_content(ctx, spec, kind)
	if spec.language == "kotlin" then
		if kind == "bungee" then
			return string.format("package %s\n\nimport net.md_5.bungee.api.plugin.Plugin\n\nclass %s : Plugin() {\n    override fun onEnable() { logger.info(\"Enabled\") }\n}\n", ctx.package, ctx.main)
		elseif kind == "velocity" and spec.use_annotation_processor == true then
			return string.format("package %s\n\nimport com.velocitypowered.api.plugin.Plugin\n\n@Plugin(\n    %s\n)\nclass %s\n", ctx.package, annotation_values(spec, true), ctx.main)
		elseif kind == "velocity" then
			return string.format("package %s\n\nclass %s\n", ctx.package, ctx.main)
		end
		return string.format("package %s\n\nimport org.spongepowered.plugin.builtin.jvm.Plugin\n\n@Plugin(%s)\nclass %s\n", ctx.package, quote(spec.plugin_id or ctx.artifactId), ctx.main)
	end
	if kind == "bungee" then
		return string.format("package %s;\n\nimport net.md_5.bungee.api.plugin.Plugin;\n\npublic final class %s extends Plugin {\n    @Override public void onEnable() { getLogger().info(\"Enabled\"); }\n}\n", ctx.package, ctx.main)
	elseif kind == "velocity" and spec.use_annotation_processor ~= false then
		return string.format("package %s;\n\nimport com.velocitypowered.api.plugin.Plugin;\n\n@Plugin(\n    %s\n)\npublic final class %s {}\n", ctx.package, annotation_values(spec), ctx.main)
	elseif kind == "velocity" then
		return string.format("package %s;\n\npublic final class %s {}\n", ctx.package, ctx.main)
	end
	return string.format("package %s;\n\nimport org.spongepowered.plugin.builtin.jvm.Plugin;\n\n@Plugin(%s)\npublic final class %s {}\n", ctx.package, quote(spec.plugin_id or ctx.artifactId), ctx.main)
end

local function velocity_metadata(ctx, spec)
	return vim.json.encode({
		id = spec.plugin_id or ctx.artifactId,
		name = spec.plugin_name or ctx.artifactId,
		version = spec.plugin_version or "1.0.0",
		main = ctx.package .. "." .. ctx.main,
		description = spec.description,
		authors = spec.authors,
		url = spec.website,
	}) .. "\n"
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
	elseif definition.kind == "velocity" and not uses_velocity_processor(spec, definition) then
		local resources = path.join(ctx.path, "src/main/resources")
		fs.mkdir(resources)
		fs.write_file(path.join(resources, "velocity-plugin.json"), velocity_metadata(ctx, spec))
	end
	return operation or true
end

return M
