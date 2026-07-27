local command_args = require("minecraft-dev.command_args")
local config = require("minecraft-dev.config")
local metadata = require("minecraft-dev.generators.fabric.metadata")
local paper_templates = require("minecraft-dev.generators.paper.templates")
local platforms = require("minecraft-dev.platforms")
local project = require("minecraft-dev.project")

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

local function test_platform_registry()
	assert_equal(platforms.names(), { "fabric", "paper" }, "registry should expose implemented platforms in stable order")
	assert_equal(platforms.build_systems("fabric"), { "gradle" }, "Fabric should only advertise supported builds")
	assert_equal(
		platforms.build_systems("paper"),
		{ "gradle", "maven" },
		"Paper should advertise Gradle and Maven"
	)
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
