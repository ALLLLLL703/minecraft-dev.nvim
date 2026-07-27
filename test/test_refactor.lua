local command_args = require("minecraft-dev.command_args")
local config = require("minecraft-dev.config")
local metadata = require("minecraft-dev.generators.fabric.metadata")
local paper_templates = require("minecraft-dev.generators.paper.templates")
local platforms = require("minecraft-dev.platforms")
local project = require("minecraft-dev.project")
local custom_templates = require("minecraft-dev.custom")
local custom_evaluator = require("minecraft-dev.custom.evaluator")

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s\nexpected: %s\nactual: %s", message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_truthy(value, message)
	if not value then
		error(message)
	end
end

local function test_command_parse_success()
	local parsed, err = command_args.parse("fabric gradle 1.21.11 ./demo")
	assert_equal(err, nil, "parse should not return an error for valid args")
	assert_truthy(parsed ~= nil, "parse should return args for valid input")
	assert_equal(parsed.project, "fabric", "project should be parsed")
	assert_equal(parsed.build_tool, "gradle", "build tool should be parsed")
	assert_equal(parsed.version, "1.21.11", "version should be parsed")
	assert_equal(parsed.path, "./demo", "path should be parsed")
end

local function test_command_parse_failure()
	local parsed, err = command_args.parse("fabric gradle")
	assert_equal(parsed, nil, "parse should fail on too few args")
	assert_equal(err, "invalid_args", "parse should report invalid args")
end

local function read_file(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function test_platform_registry()
	assert_equal(
		platforms.names(),
		{ "architectury", "bungeecord", "fabric", "forge", "neoforge", "paper", "spigot", "sponge", "velocity", "waterfall" },
		"registry should expose implemented platforms in stable order"
	)
	assert_equal(platforms.build_systems("fabric"), { "gradle" }, "Fabric should only advertise supported builds")
	assert_equal(
		platforms.build_systems("paper"),
		{ "gradle", "maven" },
		"Paper should advertise Gradle and Maven"
	)
end

local function test_architectury_generation()
	local gradle = require("minecraft-dev.util.gradle")
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() end
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = project.generate({
		platform = "architectury",
		build_system = "gradle",
		minecraft_version = "1.21.1",
		directory = directory,
		group_id = "com.example",
		artifact_id = "examplemod",
		package_name = "com.example.examplemod",
		main_class = "ExampleMod",
		language = "java",
		plugin_version = "1.0.0",
		fabric_loader_version = "0.16.14",
		fabric_api_version = "0.116.0+1.21.1",
		forge_version = "52.1.0",
		architectury_api_version = "13.0.8",
	})
	gradle.generate_gradlew = original_generate_gradlew
	assert_equal(ok, true, "Architectury generation should succeed")
	assert_equal(err, nil, "Architectury generation should not return an error")
	for _, module in ipairs({ "common", "fabric", "forge" }) do
		assert_equal(vim.fn.filereadable(directory .. "/" .. module .. "/build.gradle"), 1, module .. " build should exist")
	end
	local settings = read_file(directory .. "/settings.gradle")
	assert_truthy(settings:find("common", 1, true) ~= nil, "settings should include common module")
	assert_truthy(settings:find("fabric", 1, true) ~= nil, "settings should include Fabric module")
	assert_truthy(settings:find("forge", 1, true) ~= nil, "settings should include Forge module")
	assert_equal(vim.fn.filereadable(directory .. "/fabric/src/main/resources/fabric.mod.json"), 1, "Fabric metadata should exist")
	assert_equal(vim.fn.filereadable(directory .. "/forge/src/main/resources/META-INF/mods.toml"), 1, "Forge metadata should exist")
	vim.fn.delete(directory, "rf")
end

local function test_custom_v3_local_template()
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(template_root .. "/templates", "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(template_root .. "/templates/Main.java.ft", [[package ${PACKAGE};
#if ($ENABLED)
public class ${CLASS_NAME} {}
#else
final class Disabled {}
#end
]])
	template_fs.write_file(template_root .. "/optional.ft", "enabled=${ENABLED}\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = {
			{ name = "ENABLED", type = "boolean", default = true },
			{ name = "PACKAGE", type = "string", default = "com.example" },
			{ name = "CLASS_NAME", type = "string", default = "Example" },
		},
		files = {
			{ template = "templates/Main.java.ft", destination = "src/${PACKAGE}/${CLASS_NAME}.java" },
			{ template = "optional.ft", destination = "optional.txt", condition = "$ENABLED" },
		},
	}))

	local result, err = custom_templates.generate({
		provider = "local",
		source = template_root,
		directory = destination,
		properties = { PACKAGE = "dev.example", CLASS_NAME = "Demo" },
	})
	assert_truthy(result ~= nil, "custom v3 template should generate files")
	assert_equal(err, nil, "custom v3 template should not return an error")
	assert_equal(vim.fn.filereadable(destination .. "/src/dev.example/Demo.java"), 1, "templated destination should exist")
	local source = read_file(destination .. "/src/dev.example/Demo.java")
	assert_truthy(source:find("public class Demo", 1, true) ~= nil, "Velocity condition and variables should render")
	assert_equal(vim.fn.filereadable(destination .. "/optional.txt"), 1, "true file condition should generate file")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_velocity_directives()
	local rendered = custom_evaluator.render({ ENABLED = false, FALLBACK = true, ITEMS = { "a", "b" } }, [[#set ($PREFIX = "item")
#if ($ENABLED)
wrong
#elseif ($FALLBACK)
#foreach (${ITEM} in ${ITEMS})
${PREFIX}:${ITEM}
#end
#else
wrong
#end
]])
	assert_equal(rendered, "item:a\nitem:b\n", "Velocity set, elseif, and foreach directives should render")
end

local function test_forge_family_generation()
	local gradle = require("minecraft-dev.util.gradle")
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() end
	for _, platform in ipairs({ "forge", "neoforge" }) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = project.generate({
			platform = platform,
			build_system = "gradle",
			minecraft_version = "1.21.1",
			loader_version = platform == "forge" and "52.1.0" or "21.1.209",
			directory = directory,
			group_id = "com.example",
			artifact_id = "examplemod",
			package_name = "com.example.examplemod",
			main_class = "ExampleMod",
			language = "java",
			plugin_version = "1.0.0",
			license = "MIT",
			use_mixins = true,
			parchment_version = "2024.11.17",
		})
		assert_equal(ok, true, platform .. " generation should succeed")
		assert_equal(err, nil, platform .. " generation should not return an error")
		local build = read_file(directory .. "/build.gradle")
		assert_truthy(build:find("parchment", 1, true) ~= nil, platform .. " should honor Parchment mappings")
		assert_equal(vim.fn.filereadable(directory .. "/src/main/resources/examplemod.mixins.json"), 1, platform .. " should generate mixin config")
		local manifest = platform == "forge" and "mods.toml" or "neoforge.mods.toml"
		assert_equal(vim.fn.filereadable(directory .. "/src/main/resources/META-INF/" .. manifest), 1, platform .. " manifest should exist")
		vim.fn.delete(directory, "rf")
	end
	gradle.generate_gradlew = original_generate_gradlew
end

local function test_additional_plugin_platforms()
	local expectations = {
		bungeecord = { dependency = "bungeecord-api", metadata = "src/main/resources/bungee.yml" },
		waterfall = { dependency = "waterfall-api", metadata = "src/main/resources/bungee.yml" },
		velocity = { dependency = "velocity-api", source_marker = "@Plugin" },
		sponge = { dependency = "spongeapi", metadata = "src/main/resources/META-INF/sponge_plugins.json" },
	}
	for platform, expectation in pairs(expectations) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = project.generate({
			platform = platform,
			build_system = "maven",
			minecraft_version = platform == "velocity" and "3.5.0-SNAPSHOT" or "1.21",
			directory = directory,
			group_id = "com.example",
			artifact_id = "example",
			package_name = "com.example.example",
			main_class = "ExamplePlugin",
			language = "java",
			plugin_version = "1.0.0",
			authors = { "Alice" },
			license = "MIT",
		})
		assert_equal(ok, true, platform .. " Maven generation should succeed")
		assert_equal(err, nil, platform .. " Maven generation should not return an error")
		local pom = read_file(directory .. "/pom.xml")
		assert_truthy(pom:find(expectation.dependency, 1, true) ~= nil, platform .. " should use its API dependency")
		if expectation.metadata then
			assert_equal(vim.fn.filereadable(directory .. "/" .. expectation.metadata), 1, platform .. " metadata should exist")
		end
		if expectation.source_marker then
			local source = read_file(directory .. "/src/main/java/com/example/example/ExamplePlugin.java")
			assert_truthy(source:find(expectation.source_marker, 1, true) ~= nil, platform .. " source should contain metadata annotation")
		end
		vim.fn.delete(directory, "rf")
	end
end

local function test_spigot_maven_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = project.generate({
		platform = "spigot",
		build_system = "maven",
		minecraft_version = "1.21.8",
		directory = directory,
		group_id = "com.example",
		artifact_id = "example",
		package_name = "com.example.example",
		main_class = "ExamplePlugin",
		language = "java",
		plugin_version = "2.1.0",
		description = "Example plugin",
		authors = { "Alice", "Bob" },
		website = "https://example.com",
		prefix = "Example",
		load = "STARTUP",
		load_before = { "BeforeMe" },
		depend = { "RequiredPlugin" },
		soft_depend = { "OptionalPlugin" },
	})
	assert_equal(ok, true, "public API should generate a Spigot project")
	assert_equal(err, nil, "successful Spigot generation should not return an error")

	local pom = read_file(directory .. "/pom.xml")
	assert_truthy(pom:match("org%.spigotmc") ~= nil, "Spigot Maven project should use the Spigot group")
	assert_truthy(pom:match("spigot%-api") ~= nil, "Spigot Maven project should depend on spigot-api")
	assert_truthy(pom:match("hub%.spigotmc%.org") ~= nil, "Spigot Maven project should use the Spigot repository")

	local manifest = read_file(directory .. "/src/main/resources/plugin.yml")
	assert_truthy(manifest:match('version: "2%.1%.0"') ~= nil, "manifest should use the requested plugin version")
	assert_truthy(manifest:match('description: "Example plugin"') ~= nil, "manifest should include description")
	assert_truthy(manifest:match('authors: %[%"Alice%",%"Bob%"%]') ~= nil, "manifest should include authors")
	assert_truthy(manifest:match('load: "STARTUP"') ~= nil, "manifest should include non-default load order")
	assert_truthy(manifest:match('depend: %[%"RequiredPlugin%"%]') ~= nil, "manifest should include hard dependencies")
	assert_truthy(manifest:match('softdepend: %[%"OptionalPlugin%"%]') ~= nil, "manifest should include soft dependencies")
	vim.fn.delete(directory, "rf")
end

local function test_paper_manifest_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = project.generate({
		platform = "paper",
		build_system = "maven",
		minecraft_version = "1.21.8",
		directory = directory,
		group_id = "com.example",
		artifact_id = "example",
		package_name = "com.example.example",
		main_class = "ExamplePlugin",
		language = "java",
		paper_manifest = true,
		depend = { "RequiredPlugin" },
		soft_depend = { "OptionalPlugin" },
	})
	assert_equal(ok, true, "Paper manifest option should generate a project")
	assert_equal(err, nil, "Paper manifest generation should not return an error")
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/resources/paper-plugin.yml"),
		1,
		"Paper manifest option should write paper-plugin.yml"
	)
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/resources/plugin.yml"),
		0,
		"Paper manifest option should not also write plugin.yml"
	)
	local manifest = read_file(directory .. "/src/main/resources/paper-plugin.yml")
	assert_truthy(manifest:match("dependencies:") ~= nil, "Paper manifest should contain dependency sections")
	assert_truthy(manifest:match("server:") ~= nil, "Paper manifest dependencies should target server phase")
	assert_truthy(manifest:match('"RequiredPlugin":') ~= nil, "Paper manifest should include required plugin")
	assert_truthy(manifest:match('required: true') ~= nil, "hard dependency should be required")
	assert_truthy(manifest:match('"OptionalPlugin":') ~= nil, "Paper manifest should include optional plugin")
	assert_truthy(manifest:match('required: false') ~= nil, "soft dependency should be optional")
	vim.fn.delete(directory, "rf")
end

local function test_project_validation()
	local valid, err = project.validate({
		platform = "paper",
		build_system = "gradle",
		minecraft_version = "1.21.8",
		directory = "/tmp/example",
		group_id = "com.example",
		artifact_id = "example",
		package_name = "com.example.example",
		main_class = "ExamplePlugin",
		language = "java",
	})
	assert_truthy(valid ~= nil, "complete project specification should be valid")
	assert_equal(err, nil, "valid project specification should not return an error")

	local invalid, invalid_err = project.validate(vim.tbl_extend("force", valid, { package_name = "not-valid!" }))
	assert_equal(invalid, nil, "invalid package should be rejected")
	assert_equal(invalid_err.code, "invalid_package", "invalid package should return a structured error")

	local unsupported, unsupported_err = project.validate(vim.tbl_extend("force", valid, { build_system = "maven", platform = "fabric" }))
	assert_equal(unsupported, nil, "unsupported platform/build pair should be rejected")
	assert_equal(unsupported_err.code, "unsupported_build", "unsupported build should return a structured error")
end

local function test_noninteractive_paper_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local original_input = vim.fn.input
	vim.fn.input = function()
		error("non-interactive generation must not request input")
	end

	local ok, err = project.generate({
		platform = "paper",
		build_system = "maven",
		minecraft_version = "1.21.8",
		directory = directory,
		group_id = "com.example",
		artifact_id = "example",
		package_name = "com.example.example",
		main_class = "ExamplePlugin",
		language = "java",
	})
	vim.fn.input = original_input

	assert_equal(ok, true, "public API should generate a Paper project")
	assert_equal(err, nil, "successful generation should not return an error")
	assert_equal(vim.fn.filereadable(directory .. "/pom.xml"), 1, "Paper Maven generation should write pom.xml")
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/resources/plugin.yml"),
		1,
		"Paper generation should write plugin metadata"
	)
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/java/com/example/example/ExamplePlugin.java"),
		1,
		"Paper generation should write the requested main class"
	)
	vim.fn.delete(directory, "rf")
end

local function test_noninteractive_fabric_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local original_input = vim.fn.input
	local gradle = require("minecraft-dev.util.gradle")
	local original_generate_gradlew = gradle.generate_gradlew
	vim.fn.input = function()
		error("non-interactive generation must not request input")
	end
	gradle.generate_gradlew = function() end

	local ok, err = project.generate({
		platform = "fabric",
		build_system = "gradle",
		minecraft_version = "1.21.11",
		directory = directory,
		group_id = "com.example",
		artifact_id = "example",
		package_name = "com.example.example",
		main_class = "ExampleMod",
		language = "java",
		side = "both",
		generate_datagen = true,
		use_mixins = true,
		loom_version = "1.16-SNAPSHOT",
	})
	vim.fn.input = original_input
	gradle.generate_gradlew = original_generate_gradlew

	assert_equal(ok, true, "public API should generate a Fabric project")
	assert_equal(err, nil, "successful Fabric generation should not return an error")
	assert_equal(vim.fn.filereadable(directory .. "/build.gradle"), 1, "Fabric generation should write build.gradle")
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/resources/fabric.mod.json"),
		1,
		"Fabric generation should write mod metadata"
	)
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/java/com/example/example/ExampleMod.java"),
		1,
		"Fabric generation should write the requested main class"
	)
	assert_equal(
		vim.fn.filereadable(directory .. "/src/main/resources/example.mixins.json"),
		1,
		"Fabric generation should honor the mixin option"
	)
	vim.fn.delete(directory, "rf")
end

local function test_config_normalize_legacy_debug()
	local normalized = config.normalize({ debug = true })
	assert_equal(normalized.logging.debug, true, "legacy debug should map to logging.debug")
end

local function test_config_normalize_nested_override()
	local normalized = config.normalize({
		logging = { debug = false },
		defaults = {
			paper = { version = "1.20.6" },
		},
	})

	assert_equal(normalized.defaults.paper.version, "1.20.6", "nested defaults should override cleanly")
	assert_equal(normalized.defaults.paper.language, "java", "paper language default should stay intact")
	assert_equal(normalized.defaults.fabric.language, "java", "unrelated defaults should stay intact")
	assert_equal(normalized.prompts.paper.select_language, "Select language", "paper prompts should remain present")
	assert_equal(normalized.prompts.fabric.select_language, "Select language", "default prompts should remain present")
end

local function test_resolve_path_with_default()
	local resolved = command_args.resolve_path(nil, true)
	assert_equal(resolved, vim.fn.getcwd(), "resolve_path should fall back to cwd when enabled")
end

local function test_fabric_metadata_client_only()
	local ctx = {
		artifactId = "demo",
		package = "com.example.demo",
		main = "Main",
		version = "1.21.11",
	}
	local mod_json = metadata.build_mod_json(ctx, {
		language = "java",
		side = "client",
		generate_datagen = false,
		use_mixins = false,
	})

	assert_truthy(mod_json:match('"environment": "client"') ~= nil, "client mode should set client environment")
	assert_truthy(mod_json:match('"client"') ~= nil, "client mode should include client entrypoint")
	assert_truthy(mod_json:match('com%.example%.demo%.MainClient') ~= nil, "client entrypoint should match generated package")
	assert_truthy(mod_json:match('com%.example%.demo%.client%.MainClient') == nil, "client entrypoint should not add missing package")
	assert_truthy(mod_json:match('"main"') == nil, "client mode should omit main entrypoint")
	assert_truthy(mod_json:match('"fabric%-datagen"') == nil, "client mode should omit datagen when disabled")
end

local function test_paper_kotlin_templates()
	local gradle_template = paper_templates.read("gradle", "v1_13_plus/build.gradle.kts", "kotlin")
	local maven_template = paper_templates.read("maven", "v1_13_plus/pom.xml", "kotlin")
	local main_template = paper_templates.read("gradle", "Main.kt", "kotlin")

	assert_truthy(gradle_template:match('kotlin%("jvm"%)') ~= nil, "gradle kotlin template should apply Kotlin plugin")
	assert_truthy(maven_template:match("kotlin%-maven%-plugin") ~= nil, "maven kotlin template should apply Kotlin plugin")
	assert_truthy(main_template:match("class %%s : JavaPlugin%(%)") ~= nil, "kotlin main template should extend JavaPlugin")
end

local function test_fabric_metadata_mixins()
	local ctx = {
		artifactId = "demo",
		package = "com.example.demo",
		main = "Main",
		version = "1.21.11",
	}
	local mixins_json = metadata.build_mixins_json(ctx, {
		language = "java",
		side = "client",
		generate_datagen = true,
		use_mixins = true,
	})

	assert_truthy(mixins_json:match('"client"') ~= nil, "client mixin config should use client bucket")
	assert_truthy(mixins_json:match('"MainMixin"') ~= nil, "mixin config should include generated class name")
	assert_equal(metadata.main_class_name(ctx, { language = "java" }), "Main", "java main class should stay capitalized")
	assert_equal(metadata.client_class_name(ctx, { language = "java" }), "MainClient", "java client class should derive from main class")
end

local function run()
	require("minecraft-dev").setup()
	test_command_parse_success()
	test_command_parse_failure()
	test_platform_registry()
	test_architectury_generation()
	test_custom_v3_local_template()
	test_custom_velocity_directives()
	test_forge_family_generation()
	test_additional_plugin_platforms()
	test_spigot_maven_generation()
	test_paper_manifest_generation()
	test_project_validation()
	test_noninteractive_paper_generation()
	test_noninteractive_fabric_generation()
	test_config_normalize_legacy_debug()
	test_config_normalize_nested_override()
	test_resolve_path_with_default()
	test_fabric_metadata_client_only()
	test_fabric_metadata_mixins()
	test_paper_kotlin_templates()
	print("test_refactor.lua: ok")
end

run()
