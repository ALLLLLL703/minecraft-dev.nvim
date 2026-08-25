local command_args = require("minecraft-dev.command_args")
local command = require("minecraft-dev.command")
local completion = require("minecraft-dev.completion")
local config = require("minecraft-dev.config")
local metadata = require("minecraft-dev.generators.fabric.metadata")
local paper_templates = require("minecraft-dev.generators.paper.templates")
local platforms = require("minecraft-dev.platforms")
local project = require("minecraft-dev.project")
local custom_templates = require("minecraft-dev.custom")
local custom_evaluator = require("minecraft-dev.custom.evaluator")
local custom_property_values = require("minecraft-dev.custom.property_values")
local fabric_version_data = require("minecraft-dev.generators.fabric.version_data")
local forge_version_data = require("minecraft-dev.generators.forge.version_data")
local neoforge_version_data = require("minecraft-dev.generators.neoforge.version_data")
local plugin_version_data = require("minecraft-dev.generators.plugin.version_data")
local gradle = require("minecraft-dev.util.gradle")
local version = require("minecraft-dev.version")

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

local function test_command_entrypoints()
	local command_platforms = { "bungeecord", "fabric", "paper", "spigot", "sponge", "velocity", "waterfall" }
	assert_equal(platforms.command_names(), command_platforms, "command registry should only expose positional-compatible platforms")
	assert_equal(completion.complete("", "GmcPro "), command_platforms, "first argument completion should expose command platforms")
	assert_equal(completion.complete("pa", "GmcPro pa"), { "paper" }, "platform completion should filter by argument lead")
	assert_equal(completion.complete("", "GmcPro paper "), { "gradle", "maven" }, "second argument completion should expose platform builds")
	assert_equal(completion.complete("pa", "GmcPro pa gradle", 9), { "paper" }, "completion should use the cursor position when editing mid-line")

	local generator_modules = {}
	for _, platform_name in ipairs(command_platforms) do
		generator_modules[platforms.get(platform_name).generator] = true
	end
	local originals = {}
	local calls = {}
	local minecraft_dev = require("minecraft-dev")
	local project_context = require("minecraft-dev.context")
	local original_generate = minecraft_dev.generate
	local original_collect_context = project_context.collect
	minecraft_dev.generate = function(spec)
		calls[spec.platform] = { build = spec.build_system, path = spec.directory, version = spec.minecraft_version }
		return { status = "generated" }
	end
	project_context.collect = function()
		return { groupId = "com.example", artifactId = "command-test", package = "com.example.command", main = "CommandTest" }
	end
	for module in pairs(generator_modules) do
		originals[module] = package.loaded[module] or false
		package.loaded[module] = {
			run = function(build, path, version, _, platform_name)
				calls[platform_name] = { build = build, path = path, version = version }
				return true
			end,
		}
	end
	for _, platform_name in ipairs(command_platforms) do
		local build = platforms.build_systems(platform_name)[1]
		local result = command.dispatch(string.format("%s %s 1.21.1 /tmp/%s", platform_name, build, platform_name))
		assert_equal(result.status, "started", platform_name .. " should start from positional command arguments")
		assert_equal(calls[platform_name].build, build, platform_name .. " should dispatch its selected build")
	end
	for module, original in pairs(originals) do package.loaded[module] = original ~= false and original or nil end
	minecraft_dev.generate = original_generate
	project_context.collect = original_collect_context
	local spigot_directory = vim.fn.tempname()
	vim.fn.mkdir(spigot_directory, "p")
	local original_input = vim.fn.input
	local input_values = { "com.example", "spigot-command", "SpigotCommand" }
	vim.fn.input = function() return table.remove(input_values, 1) end
	local spigot_result = require("minecraft-dev.generators.paper.maven").generate(
		spigot_directory,
		"1.21.1",
		"java",
		nil,
		"spigot"
	)
	vim.fn.input = original_input
	assert_equal(spigot_result, true, "interactive Spigot command generation should complete")
	local spigot_pom = table.concat(vim.fn.readfile(spigot_directory .. "/pom.xml"), "\n")
	assert_truthy(spigot_pom:find("spigot-api", 1, true) ~= nil, "Spigot command generation should preserve its platform")
	vim.fn.delete(spigot_directory, "rf")

	for _, platform_name in ipairs({ "architectury", "forge", "neoforge" }) do
		local result = command.dispatch(platform_name .. " gradle 1.21.1 /tmp/example")
		assert_equal(result.status, "failed", platform_name .. " positional dispatch should fail cleanly")
		assert_equal(result.error.code, "interactive_only", platform_name .. " should direct callers to the wizard")
	end
	assert_equal(command.dispatch("paper").error.code, "invalid_args", "partial positional arguments should remain invalid")
	assert_equal(command.dispatch("unknown gradle 1.21.1").error.code, "unsupported_project", "unknown platforms should remain structured")
	assert_equal(command.dispatch("fabric maven 1.21.1").error.code, "unsupported_build", "invalid platform builds should remain structured")
	assert_equal(command.dispatch("paper gradle 1.21.1 /tmp/example extra").error.code, "invalid_args", "surplus positional arguments should be rejected")

	local wizard_module = "minecraft-dev.custom.wizard"
	local original_wizard = package.loaded[wizard_module]
	local wizard_count = 0
	package.loaded[wizard_module] = {
		run = function()
			wizard_count = wizard_count + 1
			return { status = "cancelled", result = { status = "cancelled" } }
		end,
	}
	assert_equal(command.dispatch("").status, "cancelled", "empty GmcPro dispatch should preserve wizard cancellation")
	command.setup()
	vim.cmd("GmcPro")
	vim.cmd("MinecraftDevNew")
	assert_equal(wizard_count, 3, "GmcPro and MinecraftDevNew should share the same wizard entrypoint")
	package.loaded[wizard_module] = original_wizard
end

local function test_wizard_cancellation()
	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_select = vim.ui.select
	local callback_count = 0
	minecraft_dev.list_templates = function(options)
		options.callback({ {
			label = "Paper",
			group = "plugin",
			descriptor = "paper/.mcdev.template.json",
			definition = { properties = {} },
		} }, nil)
		local result = { status = "generated" }
		return { status = "generated", result = result, on_complete = function(completion_callback) completion_callback(result) end }
	end
	vim.ui.select = function(_, _, select_callback) select_callback(nil) end
	local cancelled = wizard.run(function(result)
		callback_count = callback_count + 1
		assert_equal(result.status, "cancelled", "wizard callback should preserve selection cancellation")
	end)
	assert_equal(cancelled.status, "cancelled", "wizard selection cancellation should be final")
	vim.wait(1000, function() return callback_count == 1 end, 10)
	assert_equal(callback_count, 1, "wizard selection cancellation should callback exactly once")

	local list_child = { callbacks = {} }
	function list_child.on_complete(completion_callback) table.insert(list_child.callbacks, completion_callback) end
	function list_child.cancel() list_child.cancelled = true end
	minecraft_dev.list_templates = function() return list_child end
	local active = wizard.run()
	active.cancel()
	assert_equal(active.status, "pending", "wizard cancellation should wait for active provider exit")
	assert_equal(list_child.cancelled, true, "wizard cancellation should cancel template discovery")
	for _, completion_callback in ipairs(list_child.callbacks) do completion_callback({ status = "cancelled" }) end
	assert_equal(active.status, "cancelled", "wizard cancellation should finish after provider exit")

	local list_callback
	local generation_child = { callbacks = {} }
	function generation_child.on_complete(completion_callback) table.insert(generation_child.callbacks, completion_callback) end
	function generation_child.cancel() generation_child.cancelled = true end
	minecraft_dev.list_templates = function(options)
		list_callback = options.callback
		return { status = "pending", on_complete = function() end, cancel = function() end }
	end
	local original_generate_template = minecraft_dev.generate_template
	minecraft_dev.generate_template = function(options)
		generation_child.template_callback = options.callback
		return generation_child
	end
	local input_values = { vim.fn.tempname(), "wizard-project" }
	local original_input = vim.ui.input
	vim.ui.select = function(items, _, select_callback) select_callback(items[1]) end
	vim.ui.input = function(_, input_callback) input_callback(table.remove(input_values, 1)) end
	local notify_module = require("minecraft-dev.util.notify")
	local original_notify = notify_module.notify
	local error_notifications = 0
	notify_module.notify = function(level, ...)
		if level == vim.log.levels.ERROR then error_notifications = error_notifications + 1 end
		return original_notify(level, ...)
	end
	local generating = wizard.run()
	list_callback({ {
		label = "Paper",
		group = "plugin",
		descriptor = "paper/.mcdev.template.json",
		definition = { properties = {} },
	} }, nil)
	assert_equal(generating.status, "pending", "wizard should remain pending during template generation")
	generating.cancel()
	assert_equal(generation_child.cancelled, true, "wizard cancellation should cancel template generation")
	local cancelled_result = { status = "cancelled" }
	generation_child.template_callback(cancelled_result)
	for _, completion_callback in ipairs(generation_child.callbacks) do completion_callback(cancelled_result) end
	assert_equal(generating.status, "cancelled", "wizard should preserve template generation cancellation")
	assert_equal(error_notifications, 0, "template cancellation should not emit a failure notification")
	notify_module.notify = original_notify
	minecraft_dev.generate_template = original_generate_template
	vim.ui.input = original_input
	minecraft_dev.list_templates = original_list_templates
	vim.ui.select = original_select
end

local function read_file(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function test_command_platform_generation()
	local paper_options = require("minecraft-dev.generators.paper.options")
	local fabric_options = require("minecraft-dev.generators.fabric.options")
	local original_with_language = paper_options.with_language
	local original_collect = fabric_options.collect
	local original_generate_gradlew = gradle.generate_gradlew
	local original_input = vim.fn.input
	local original_resolve_waterfall = plugin_version_data.resolve_waterfall_version
	paper_options.with_language = function(_, callback) callback("java") end
	fabric_options.collect = function(_, callback)
		callback({ language = "java", side = "both", generate_datagen = true, use_mixins = true })
	end
	gradle.generate_gradlew = function() return true end
	plugin_version_data.resolve_waterfall_version = function(_, callback)
		callback("1.21-R0.5-SNAPSHOT", nil)
		local operation = { status = "generated", result = { status = "generated" }, cancel = function() end }
		function operation.on_complete(completion) completion(operation.result) return operation end
		return operation, nil
	end

	local cases = {
		{ platform = "paper", build = "maven", version = "1.21.1", file = "pom.xml", marker = "paper-api", metadata = "src/main/resources/plugin.yml" },
		{ platform = "spigot", build = "maven", version = "1.21.1", file = "pom.xml", marker = "spigot-api", metadata = "src/main/resources/plugin.yml" },
		{ platform = "bungeecord", build = "maven", version = "1.21", file = "pom.xml", marker = "bungeecord-api", metadata = "src/main/resources/bungee.yml" },
		{ platform = "waterfall", build = "maven", version = "1.21", file = "pom.xml", marker = "waterfall-api", metadata = "src/main/resources/bungee.yml" },
		{ platform = "velocity", build = "maven", version = "3.5.0-SNAPSHOT", file = "pom.xml", marker = "velocity-api" },
		{ platform = "sponge", build = "maven", version = "12.0.0", file = "pom.xml", marker = "spongeapi", metadata = "src/main/resources/META-INF/sponge_plugins.json" },
		{ platform = "fabric", build = "gradle", version = "1.21.1", file = "build.gradle", marker = "fabric-api", metadata = "src/main/resources/fabric.mod.json" },
	}
	for _, case in ipairs(cases) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local input_values = { "com.example", "commandtest", "CommandTest" }
		vim.fn.input = function() return table.remove(input_values, 1) end
		local result = command.dispatch(string.format("%s %s %s %s", case.platform, case.build, case.version, directory))
		assert_equal(result.status, "started", case.platform .. " command generation should start")
		if type(result.operation) == "table" and result.operation.status == "pending" then vim.wait(1000, function() return result.operation.status ~= "pending" end, 10) end
		assert_truthy(read_file(directory .. "/" .. case.file):find(case.marker, 1, true) ~= nil, case.platform .. " command generation should use its platform dependency")
		if case.platform == "waterfall" then
			assert_truthy(read_file(directory .. "/pom.xml"):find("<version>1.21-R0.5-SNAPSHOT</version>", 1, true) ~= nil, "Waterfall command should resolve Minecraft versions to API versions")
		end
		if case.metadata then
			assert_equal(vim.fn.filereadable(directory .. "/" .. case.metadata), 1, case.platform .. " command generation should write metadata")
		end
		vim.fn.delete(directory, "rf")
	end

	paper_options.with_language = original_with_language
	fabric_options.collect = original_collect
	gradle.generate_gradlew = original_generate_gradlew
	plugin_version_data.resolve_waterfall_version = original_resolve_waterfall
	vim.fn.input = original_input
end

local function test_build_matrix_definition()
	local matrix = dofile(vim.fs.joinpath(vim.fn.getcwd(), "test", "build_matrix.lua"))
	assert_equal(matrix.classify_failure("connection timed out", false), "network_failure", "matrix should classify network failures")
	assert_equal(matrix.classify_failure("Connection refused", false), "network_failure", "matrix should classify refused connections")
	assert_equal(matrix.classify_failure("Read timed out", false), "network_failure", "matrix should classify read timeouts")
	assert_equal(matrix.classify_failure("Temporary failure in name resolution", false), "network_failure", "matrix should classify DNS failures")
	assert_equal(matrix.classify_failure("Could not transfer artifact example:demo:jar:1.0", false), "network_failure", "matrix should classify Maven transfer failures")
	assert_equal(matrix.classify_failure("Test of distribution url failed", false), "network_failure", "matrix should classify wrapper download failures")
	assert_equal(matrix.classify_failure("Could not find example:missing:1.0", false), "dependency_resolution_failed", "matrix should classify missing dependencies")
	assert_equal(matrix.classify_failure("Could not find method example()", false), "build_failed", "matrix should not classify DSL errors as dependency failures")
	assert_equal(matrix.classify_failure("compiler error", false), "build_failed", "matrix should preserve ordinary build failures")
	assert_equal(matrix.classify_failure("", true), "timeout", "matrix should classify explicit timeouts")
	assert_equal(matrix.classify_process({ code = 0, timed_out = true }), "timeout", "matrix should prioritize timeout over exit code")
	assert_equal(matrix.classify_process({ code = -1, start_failed = true }), "process_start_failed", "matrix should classify process startup failures")
	assert_equal(matrix.classify_process({ code = 0 }), "passed", "matrix should classify successful processes")
	assert_equal(matrix.classify_generation_error({ code = "timeout" }), "timeout", "matrix should classify Java probe timeouts")
	assert_equal(matrix.classify_generation_error({ code = "gradle_wrapper_start_failed" }), "process_start_failed", "matrix should classify wrapper startup failures")
	assert_equal(matrix.classify_generation_error({ code = "gradle_wrapper_failed", detail = "connection refused" }), "network_failure", "matrix should classify generation-stage network failures")
	local subset, subset_error = matrix.select_cases("paper-java-gradle,fabric-kotlin-gradle")
	assert_equal(subset_error, nil, "valid matrix filters should not return an error")
	assert_equal(#subset, 2, "valid matrix filters should select requested cases")
	local unknown_cases, unknown_error = matrix.select_cases("does-not-exist")
	assert_equal(unknown_cases, nil, "unknown matrix filters should be rejected")
	assert_equal(unknown_error.code, "matrix_cases_unknown", "unknown matrix filters should return a structured error")
	local empty_cases, empty_error = matrix.select_cases(",,,")
	assert_equal(empty_cases, nil, "empty matrix filters should be rejected")
	assert_equal(empty_error.code, "matrix_cases_empty", "empty matrix filters should return a structured error")
	local whitespace_cases, whitespace_error = matrix.select_cases("   ")
	assert_equal(whitespace_cases, nil, "whitespace matrix filters should be rejected")
	assert_equal(whitespace_error.code, "matrix_cases_empty", "whitespace matrix filters should return matrix_cases_empty")
	local mixed_cases, mixed_error = matrix.select_cases("paper-java-gradle,   ")
	assert_equal(mixed_error, nil, "trailing whitespace entries should be ignored")
	assert_equal(#mixed_cases, 1, "mixed whitespace filters should preserve valid cases")
	local report_valid, report_error = matrix.validate_report_path("/tmp/matrix", "/tmp/matrix/paper-java-gradle/report.json", matrix.cases)
	assert_equal(report_valid, nil, "reports inside case directories should be rejected")
	assert_equal(report_error.code, "matrix_report_inside_case", "report collisions should return a structured error")
	assert_equal(matrix.validate_report_path("/tmp/matrix", "/tmp/matrix-report.json", matrix.cases), true, "reports outside case directories should be accepted")
	local report_root = vim.fn.tempname()
	local report_alias = vim.fn.tempname()
	vim.fn.mkdir(report_root .. "/paper-java-gradle", "p")
	assert_truthy(vim.uv.fs_symlink(report_root .. "/paper-java-gradle", report_alias) ~= nil, "report alias fixture should be created")
	local alias_valid, alias_error = matrix.validate_report_path(report_root, report_alias .. "/report.json", matrix.cases)
	assert_equal(alias_valid, nil, "symlinked reports inside case directories should be rejected")
	assert_equal(alias_error.code, "matrix_report_inside_case", "symlinked report collisions should remain structured")
	local nested_valid, nested_error = matrix.validate_report_path(report_root, report_alias .. "/not-created/report.json", matrix.cases)
	assert_equal(nested_valid, nil, "reports below unresolved symlink suffixes should be rejected")
	assert_equal(nested_error.code, "matrix_report_inside_case", "unresolved symlink suffixes should remain structured")
	local report_target = report_root .. "/paper-java-gradle/report-target.json"
	local report_link = vim.fn.tempname()
	vim.fn.writefile({ "report" }, report_target)
	assert_truthy(vim.uv.fs_symlink(report_target, report_link) ~= nil, "report file symlink fixture should be created")
	local linked_valid, linked_error = matrix.validate_report_path(report_root, report_link, matrix.cases)
	assert_equal(linked_valid, nil, "report file symlinks should be rejected")
	assert_equal(linked_error.code, "matrix_report_symlink", "report file symlinks should return a structured error")
	vim.fn.delete(report_link)
	local dangling_link = vim.fn.tempname()
	assert_truthy(vim.uv.fs_symlink(report_root .. "/missing-report.json", dangling_link) ~= nil, "dangling report symlink fixture should be created")
	local dangling_valid, dangling_error = matrix.validate_report_path(report_root, dangling_link, matrix.cases)
	assert_equal(dangling_valid, nil, "dangling report symlinks should be rejected")
	assert_equal(dangling_error.code, "matrix_report_symlink", "dangling report symlinks should return a structured error")
	vim.fn.delete(dangling_link)
	local future_root = vim.fn.tempname()
	local future_alias = vim.fn.tempname()
	vim.fn.mkdir(future_root, "p")
	assert_truthy(vim.uv.fs_symlink(future_root .. "/paper-java-gradle", future_alias) ~= nil, "future case alias fixture should be created")
	local future_valid, future_error = matrix.validate_report_path(future_root, future_alias .. "/reports/result.json", matrix.cases)
	assert_equal(future_valid, nil, "dangling report ancestors should be rejected")
	assert_equal(future_error.code, "matrix_path_unresolved_symlink", "dangling report ancestors should remain structured")
	vim.fn.delete(future_alias)
	vim.fn.delete(future_root, "rf")
	vim.fn.delete(report_alias)
	vim.fn.delete(report_root, "rf")
	local covered_platforms = {}
	local covered_languages = {}
	local covered_builds = {}
	for _, case in ipairs(matrix.cases) do
		covered_platforms[case.spec.platform] = true
		covered_languages[case.spec.language] = true
		covered_builds[case.spec.build_system] = true
		assert_truthy(case.toolchain and case.toolchain.jdk, case.name .. " should record its JDK")
		if case.spec.platform == "architectury" then
			assert_equal(case.toolchain, require("minecraft-dev.generators.architectury").versions and {
				jdk = 21,
				gradle = require("minecraft-dev.generators.architectury").versions.gradle,
				loom = require("minecraft-dev.generators.architectury").versions.loom,
			}, "Architectury matrix metadata should derive from generator versions")
		end
	end
	for _, platform_name in ipairs({ "paper", "velocity", "fabric", "forge", "neoforge", "architectury" }) do
		assert_equal(covered_platforms[platform_name], true, "build matrix should cover " .. platform_name)
	end
	assert_equal(covered_languages.java, true, "build matrix should cover Java")
	assert_equal(covered_languages.kotlin, true, "build matrix should cover Kotlin")
	assert_equal(covered_builds.gradle, true, "build matrix should cover Gradle")
	assert_equal(covered_builds.maven, true, "build matrix should cover Maven")
	local fabric_options_covered = false
	local forge_versions_covered = {}
	for _, case in ipairs(matrix.cases) do
		if case.spec.platform == "fabric" and case.spec.use_mixins and case.spec.generate_datagen then
			fabric_options_covered = true
		end
		if case.spec.platform == "forge" then forge_versions_covered[case.spec.minecraft_version] = true end
	end
	assert_equal(fabric_options_covered, true, "build matrix should cover Fabric Mixin and datagen")
	assert_equal(vim.tbl_count(forge_versions_covered) >= 3, true, "build matrix should cover at least three Forge version breakpoints")
end

local function generate_project(spec)
	local operation = project.generate(spec)
	if operation.status == "pending" then vim.wait(1000, function() return operation.status ~= "pending" end, 10) end
	assert_truthy(operation.status ~= "pending", "project generation should complete")
	if operation.status == "generated" then return true, nil end
	return nil, operation.result and operation.result.error
end

local function generate_template(options)
	local operation = custom_templates.generate(options)
	if operation.status == "pending" then vim.wait(10000, function() return operation.status ~= "pending" end, 20) end
	assert_truthy(operation.status ~= "pending", "template generation should complete")
	if operation.status == "generated" then return operation.result, nil end
	return nil, operation.result and operation.result.error
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
	local wrapper_version
	gradle.generate_gradlew = function(_, _, version) wrapper_version = version return true end
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = generate_project({
		platform = "architectury",
		build_system = "gradle",
		minecraft_version = "1.20.1",
		directory = directory,
		group_id = "com.example",
		artifact_id = "examplemod",
		package_name = "com.example.examplemod",
		main_class = "ExampleMod",
		language = "java",
		plugin_version = "1.0.0",
		fabric_loader_version = "0.16.14",
		fabric_api_version = "0.92.6+1.20.1",
		forge_version = "47.4.0",
		architectury_api_version = "9.2.14",
	})
	gradle.generate_gradlew = original_generate_gradlew
	assert_equal(ok, true, "Architectury generation should succeed")
	assert_equal(err, nil, "Architectury generation should not return an error")
	assert_equal(wrapper_version, "8.10.1", "Architectury should use a Loom-compatible Gradle version")
	for _, module in ipairs({ "common", "fabric", "forge" }) do
		assert_equal(vim.fn.filereadable(directory .. "/" .. module .. "/build.gradle"), 1, module .. " build should exist")
	end
	assert_equal(vim.fn.filereadable(directory .. "/forge/gradle.properties"), 1, "Forge module should declare its Loom platform")
	assert_truthy(read_file(directory .. "/forge/gradle.properties"):find("loom.platform=forge", 1, true) ~= nil, "Forge module should select Forge Loom")
	for _, module in ipairs({ "fabric", "forge" }) do
		local build = read_file(directory .. "/" .. module .. "/build.gradle")
		assert_truthy(build:find("compileClasspath.extendsFrom common", 1, true) ~= nil, module .. " should compile against common sources")
		assert_truthy(build:find("shadowCommon(project", 1, true) ~= nil, module .. " should bundle transformed common sources")
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
	template_fs.write_file(template_root .. "/build.gradle.kts.ft", [[tasks.processResources {
    filesMatching("plugin.json") {
        expand("version" to project.property("version"))
    }
}
val untouched = mapOf("count" to project.property("count"))
]])
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
			{ template = "build.gradle.kts.ft", destination = "build.gradle.kts" },
		},
	}))

	local result, err = generate_template({
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
	assert_truthy(read_file(destination .. "/build.gradle.kts"):find('to (project.property("version") as String)', 1, true) ~= nil, "Kotlin DSL property map values should be non-null for Gradle 9")
	assert_truthy(read_file(destination .. "/build.gradle.kts"):find('"count" to project.property("count")', 1, true) ~= nil, "Kotlin DSL property normalization should remain scoped to expand maps")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_paper_version_values()
	local response = vim.json.encode({
		versions = {
			legacy = { "1.18.1", "1.18.2" },
			modern = { "1.21.11-pre1", "1.21.11", "26.1", "1.21.11" },
		},
	})
	local versions, parse_error = custom_property_values.parse_paper_versions(response)
	assert_equal(parse_error, nil, "valid Paper Fill responses should parse")
	assert_equal(versions, { "26.1", "1.21.11", "1.18.2" }, "Paper versions should be stable, supported, unique, and newest first")
	assert_equal(select(2, custom_property_values.parse_paper_versions("{}")), { code = "property_response_invalid", property_type = "paper_versions" }, "invalid Paper responses should be structured")

	local captured_command
	local resolved
	local operation, load_error = custom_property_values.load({ type = "paper_versions" }, function(values, err)
		resolved = { values = values, err = err }
	end, function(command, _, callback)
		captured_command = command
		callback({ code = 0, stdout = response, stderr = "" })
		return { kill = function() end }
	end)
	assert_equal(load_error, nil, "Paper version loading should start with an injected system runner")
	vim.wait(1000, function() return resolved ~= nil end, 10)
	assert_equal(operation.status, "generated", "Paper version loading should complete")
	assert_equal(resolved.values, versions, "Paper version loading should return parsed versions")
	assert_equal(resolved.err, nil, "Paper version loading should not return an error")
	assert_truthy(table.concat(captured_command, " "):find("User-Agent: minecraft-dev.nvim", 1, true) ~= nil, "Paper Fill requests should identify the plugin")

	local failed
	local failed_operation = custom_property_values.load({ type = "paper_versions" }, function(values, err)
		failed = { values = values, err = err }
	end, function(_, _, callback)
		callback({ code = 22, stdout = "", stderr = "HTTP 503" })
		return { kill = function() end }
	end)
	vim.wait(1000, function() return failed ~= nil end, 10)
	assert_equal(failed_operation.status, "failed", "Paper version HTTP failures should complete as failed")
	assert_equal(failed.err.code, "property_fetch_failed", "Paper version HTTP failures should remain structured")

	local process_callback
	local killed = false
	local cancelled
	local cancelled_operation = custom_property_values.load({ type = "paper_versions" }, function(_, err)
		cancelled = err
	end, function(_, _, callback)
		process_callback = callback
		return { kill = function() killed = true end }
	end)
	cancelled_operation.cancel()
	assert_equal(killed, true, "Paper version cancellation should terminate curl")
	process_callback({ code = 143, stdout = "", stderr = "terminated" })
	vim.wait(1000, function() return cancelled ~= nil end, 10)
	assert_equal(cancelled_operation.status, "cancelled", "Paper version cancellation should complete after curl exits")
	assert_equal(cancelled.code, "cancelled", "Paper version cancellation should remain structured")

	local metadata = [[<metadata><versioning><versions>
<version>2.0.0-beta.9</version><version>2.0.0-beta.10</version><version>-</version>
<version>1.0.0</version><version>2.0.0</version><version>3.0.0</version>
</versions></versioning></metadata>]]
	local maven_versions, metadata_error = custom_property_values.parse_maven_versions(metadata, 3)
	assert_equal(metadata_error, nil, "valid Maven metadata should parse")
	assert_equal(maven_versions, { "3.0.0", "2.0.0", "2.0.0-beta.10" }, "Maven versions should use semantic qualifier order and descriptor limits")
	assert_equal(select(2, custom_property_values.parse_maven_versions(metadata, -1)).code, "property_limit_invalid", "negative Maven version limits should fail structurally")
	local invalid_source_operation, invalid_source_error = custom_property_values.load({
		type = "gradle_plugin",
		parameters = { sourceUrl = "--config=/tmp/curl.conf" },
	}, function() end, function() error("invalid source should not start curl") end)
	assert_equal(invalid_source_operation, nil, "option-like Maven metadata URLs should be rejected")
	assert_equal(invalid_source_error.code, "property_source_invalid", "invalid Maven metadata URLs should fail structurally")
	local maven_command
	local maven_result
	local maven_operation, maven_error = custom_property_values.load({
		type = "gradle_plugin",
		parameters = { sourceUrl = "https://repo.example/plugin/maven-metadata.xml" },
	}, function(values, err)
		maven_result = { values = values, err = err }
	end, function(command, _, callback)
		maven_command = command
		callback({ code = 0, stdout = metadata, stderr = "" })
		return { kill = function() end }
	end)
	assert_equal(maven_error, nil, "Gradle plugin metadata loading should start")
	vim.wait(1000, function() return maven_result ~= nil end, 10)
	assert_equal(maven_operation.status, "generated", "Gradle plugin metadata loading should complete")
	assert_equal(maven_result.values[1], "3.0.0", "Gradle plugin metadata loading should return the newest version")
	assert_equal(maven_command[#maven_command], "https://repo.example/plugin/maven-metadata.xml", "Gradle plugin loading should use descriptor sourceUrl")
	local kotlin_result
	custom_property_values.load({
		type = "maven_artifact_version",
		parameters = {
			sourceUrl = "https://repo.example/fabric-language-kotlin/maven-metadata.xml",
			rawVersionFilter = "$version.contains('+kotlin.')",
		},
	}, function(values) kotlin_result = values end, function(_, _, callback)
		callback({
			code = 0,
			stdout = "<metadata><versioning><versions><version>2.4.10</version><version>1.13.13+kotlin.2.4.10</version></versions></versioning></metadata>",
			stderr = "",
		})
		return { kill = function() end }
	end)
	vim.wait(1000, function() return kotlin_result ~= nil end, 10)
	assert_equal(kotlin_result, { "1.13.13+kotlin.2.4.10" }, "Maven property loading should honor the Fabric Kotlin raw version filter")
end

local function test_custom_paper_build_option_wizard()
	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_generate_template = minecraft_dev.generate_template
	local original_load = custom_property_values.load
	local original_input = vim.ui.input
	local original_select = vim.ui.select
	local generated_properties
	local loaded = {}
	local inputs = { "/tmp/paper-build-options", "paper-build-options" }
	local plugin_parameters = { sourceUrl = "https://repo.example/maven-metadata.xml" }

	minecraft_dev.list_templates = function(options)
		options.callback({ {
			label = "Paper",
			group = "plugin",
			descriptor = "bukkit/paper.mcdev.template.json",
			definition = { properties = {
				{ name = "LANGUAGE", type = "string", options = { "Java", "Kotlin" } },
				{ name = "KOTLIN_VERSION", type = "maven_artifact_version", parameters = plugin_parameters },
				{ name = "GREMLIN_PLUGIN", type = "gradle_plugin", parameters = plugin_parameters },
				{
					name = "SHADOW_PLUGIN", type = "gradle_plugin", parameters = plugin_parameters,
					forceValue = { condition = "$LANGUAGE == 'Kotlin' || $GREMLIN_PLUGIN.enabled", value = "true" },
				},
				{
					name = "INCLUDE_PLUGIN_LOADER", type = "boolean", default = false,
					forceValue = { condition = "$GREMLIN_PLUGIN.enabled", value = "false" },
				},
				{ name = "IDEA_EXT_PLUGIN", type = "gradle_plugin", visible = false, parameters = plugin_parameters },
			} },
		} }, nil)
		return { status = "generated", cancel = function() end }
	end
	minecraft_dev.generate_template = function(options)
		generated_properties = options.properties
		local result = { status = "generated" }
		options.callback(result)
		return { status = "generated", result = result, cancel = function() end }
	end
	custom_property_values.load = function(descriptor, callback)
		table.insert(loaded, descriptor.name)
		callback({ "3.0.0", "2.0.0" }, nil)
		return { status = "generated", cancel = function() end }, nil
	end
	vim.ui.input = function(_, callback) callback(table.remove(inputs, 1)) end
	vim.ui.select = function(items, _, callback)
		if type(items[1]) == "table" then callback(items[1])
		elseif items[1] == "Java" then callback("Kotlin")
		elseif type(items[1]) == "boolean" then callback(true)
		else callback(items[1]) end
	end

	local operation = wizard.run()
	minecraft_dev.list_templates = original_list_templates
	minecraft_dev.generate_template = original_generate_template
	custom_property_values.load = original_load
	vim.ui.input = original_input
	vim.ui.select = original_select

	assert_equal(operation.status, "generated", "Paper build option wizard should generate")
	assert_equal(loaded, { "KOTLIN_VERSION", "GREMLIN_PLUGIN", "SHADOW_PLUGIN", "IDEA_EXT_PLUGIN" }, "build options should load visible and hidden descriptor metadata without manual version input")
	assert_equal(generated_properties.KOTLIN_VERSION, "3.0.0", "Kotlin metadata version should be selected")
	assert_equal(generated_properties.GREMLIN_PLUGIN, { enabled = true, version = "3.0.0" }, "Gremlin should retain its selected version")
	assert_equal(generated_properties.SHADOW_PLUGIN, { enabled = true, version = "3.0.0" }, "Kotlin and Gremlin should force Shadow enabled while preserving version selection")
	assert_equal(generated_properties.INCLUDE_PLUGIN_LOADER, false, "Gremlin should force the custom plugin loader off")
	assert_equal(generated_properties.IDEA_EXT_PLUGIN, { enabled = false, version = "3.0.0" }, "hidden Gradle plugins should retain an automatically resolved version")

	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	local template_fs = require("minecraft-dev.util.fs")
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	template_fs.write_file(template_root .. "/plugin.ft", [[${SHADOW_PLUGIN.enabled}|${SHADOW_PLUGIN.version}|${USE_BUILD_CONSTANTS_TEMPLATING}
#if ($AUTHORS)
authors
#end
#if ($LOAD_AT != "POSTWORLD")
load=$LOAD_AT
#end
]])
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = {
			{ name = "LANGUAGE", type = "string" },
			{ name = "USE_ANNOTATION_PROCESSOR", type = "boolean", default = false },
			{ name = "USE_BUILD_CONSTANTS_TEMPLATING", type = "boolean", default = "USE_ANNOTATION_PROCESSOR" },
			{ name = "AUTHORS", type = "inline_string_list", default = "", nullIfDefault = true },
			{ name = "LOAD_AT", type = "string", default = "POSTWORLD", nullIfDefault = true },
			{
				name = "SHADOW_PLUGIN", type = "gradle_plugin",
				forceValue = { condition = "$LANGUAGE == 'Kotlin'", value = "true" },
			},
		},
		files = { { template = "plugin.ft", destination = "plugin.txt" } },
	}))
	local result, err = generate_template({
		provider = "local",
		source = template_root,
		directory = destination,
		properties = { LANGUAGE = "Kotlin", AUTHORS = "", SHADOW_PLUGIN = { enabled = true, version = "3.0.0" } },
	})
	assert_truthy(result ~= nil, "forced Gradle plugin fixture should generate")
	assert_equal(err, nil, "forced Gradle plugin fixture should not fail")
	assert_equal(read_file(destination .. "/plugin.txt"), "true|3.0.0|false", "forceValue and bare default references should render correctly")
	assert_equal(result.properties.USE_BUILD_CONSTANTS_TEMPLATING, false, "bare defaults should reference an earlier property")
	assert_equal(result.properties.AUTHORS, nil, "empty optional inline lists should normalize to nil")
	assert_equal(result.properties.LOAD_AT, nil, "nullIfDefault should omit non-empty defaults from template values")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_hidden_group_visibility()
	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_generate_template = minecraft_dev.generate_template
	local original_load = custom_property_values.load
	local original_input = vim.ui.input
	local original_select = vim.ui.select
	local inputs = { "/tmp/velocity-maven", "velocity-maven" }
	local loaded = {}
	minecraft_dev.list_templates = function(options)
		options.callback({ {
			label = "Velocity",
			definition = { properties = {
				{ name = "BUILD_SYSTEM", type = "string", options = { "Maven", "Gradle" } },
				{
					visible = { condition = "$BUILD_SYSTEM == 'Gradle'" },
					groupProperties = { {
						name = "IDEA_EXT_PLUGIN", type = "gradle_plugin", visible = false,
						parameters = { sourceUrl = "https://repo.example/maven-metadata.xml" },
					} },
				},
			} },
		} }, nil)
		return { status = "generated", cancel = function() end }
	end
	minecraft_dev.generate_template = function(options)
		local result = { status = "generated" }
		options.callback(result)
		return { status = "generated", result = result, cancel = function() end }
	end
	custom_property_values.load = function(descriptor, callback)
		table.insert(loaded, descriptor.name)
		callback({ "1.0.0" }, nil)
		return { status = "generated", cancel = function() end }, nil
	end
	vim.ui.input = function(_, callback) callback(table.remove(inputs, 1)) end
	vim.ui.select = function(items, _, callback)
		if type(items[1]) == "table" then callback(items[1]) else callback(items[1]) end
	end

	local operation = wizard.run()
	minecraft_dev.list_templates = original_list_templates
	minecraft_dev.generate_template = original_generate_template
	custom_property_values.load = original_load
	vim.ui.input = original_input
	vim.ui.select = original_select

	assert_equal(operation.status, "generated", "Maven custom wizard should generate")
	assert_equal(loaded, {}, "properties in an invisible Gradle group should not load metadata for Maven")
end

local function test_custom_paper_version_wizard()
	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_generate_template = minecraft_dev.generate_template
	local original_load = custom_property_values.load
	local original_input = vim.ui.input
	local original_select = vim.ui.select
	local generated_properties
	local inputs = { "/tmp/paper-wizard", "paper-wizard" }
	local selections = {}
	local pending_version_selection

	minecraft_dev.list_templates = function(options)
		options.callback({ {
			label = "Paper",
			group = "plugin",
			descriptor = "bukkit/paper.mcdev.template.json",
			definition = { properties = { { name = "MC_VERSION", type = "paper_versions" } } },
		} }, nil)
		return { status = "generated", cancel = function() end }
	end
	minecraft_dev.generate_template = function(options)
		generated_properties = options.properties
		local result = { status = "generated" }
		options.callback(result)
		return { status = "generated", result = result, cancel = function() end }
	end
	custom_property_values.load = function(_, callback)
		callback({ "26.1", "1.21.11" }, nil)
		return { status = "generated", cancel = function() end }, nil
	end
	vim.ui.input = function(_, callback) callback(table.remove(inputs, 1)) end
	vim.ui.select = function(items, _, callback)
		table.insert(selections, vim.deepcopy(items))
		if type(items[1]) == "table" then callback(items[1])
		elseif pending_version_selection == false then pending_version_selection = callback
		else callback(items[2]) end
	end

	local operation = wizard.run()
	inputs = { "/tmp/paper-wizard-cancel", "paper-wizard-cancel" }
	pending_version_selection = false
	local cancelling = wizard.run()
	local picker_status = cancelling.status
	cancelling.cancel()
	local cancelled_status = cancelling.status
	pending_version_selection("26.1")
	local late_callback_status = cancelling.status
	minecraft_dev.list_templates = original_list_templates
	minecraft_dev.generate_template = original_generate_template
	custom_property_values.load = original_load
	vim.ui.input = original_input
	vim.ui.select = original_select

	assert_equal(operation.status, "generated", "Paper wizard should generate after selecting a fetched version: " .. vim.inspect(selections))
	assert_equal(generated_properties.MC_VERSION, "1.21.11", "Paper wizard should pass the selected Fill version to generation")
	assert_equal(picker_status, "pending", "Paper wizard should remain pending while the version picker is open")
	assert_equal(cancelled_status, "cancelled", "Paper wizard cancellation should finish after version loading has completed")
	assert_equal(late_callback_status, "cancelled", "late picker callbacks should not revive a cancelled Paper wizard")
end

local function test_custom_paper_derivations()
	local template_root = vim.fn.tempname()
	local template_fs = require("minecraft-dev.util.fs")
	vim.fn.mkdir(template_root, "p")
	template_fs.write_file(template_root .. "/values.ft", "${API_VERSION}|${DEPENDENCY_VERSION}|${JAVA_VERSION}\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = {
			{ name = "MC_VERSION", type = "paper_versions" },
			{ name = "BUILD_SYSTEM", type = "string" },
			{ name = "API_VERSION", type = "semantic_version", derives = { parents = { "MC_VERSION" }, method = "extractPaperApiVersion" } },
			{ name = "DEPENDENCY_VERSION", type = "string", derives = { parents = { "MC_VERSION", "BUILD_SYSTEM" }, method = "fetchPaperDependencyVersionForMcVersion" } },
			{ name = "JAVA_VERSION", type = "integer", default = 17, derives = { parents = { "MC_VERSION" }, method = "recommendJavaVersionForMcVersion", default = 17 } },
		},
		files = { { template = "values.ft", destination = "values.txt" } },
	}))
	local cases = {
		{ version = "1.16.5", build = "Gradle", expected = "1.16|1.16.5-R0.1-SNAPSHOT|8" },
		{ version = "1.17.1", build = "Gradle", expected = "1.17|1.17.1-R0.1-SNAPSHOT|16" },
		{ version = "1.20.4", build = "Gradle", expected = "1.20|1.20.4-R0.1-SNAPSHOT|17" },
		{ version = "1.20.5", build = "Gradle", expected = "1.20.5|1.20.5-R0.1-SNAPSHOT|21" },
		{ version = "1.21.11", build = "Gradle", expected = "1.21.11|1.21.11-R0.1-SNAPSHOT|21" },
		{ version = "26.1", build = "Gradle", expected = "26.1|26.1.build.+|25" },
		{ version = "26.1", build = "Maven", expected = "26.1|[26.1.build,)|25" },
	}
	for _, case in ipairs(cases) do
		local destination = vim.fn.tempname()
		vim.fn.mkdir(destination, "p")
		local result, err = generate_template({
			provider = "local",
			source = template_root,
			directory = destination,
			properties = { MC_VERSION = case.version, BUILD_SYSTEM = case.build },
		})
		assert_truthy(result ~= nil, "Paper derivation fixture should generate")
		assert_equal(err, nil, "Paper derivation fixture should not fail")
		assert_equal(read_file(destination .. "/values.txt"), case.expected, "Paper derivations should match upstream version boundaries")
		vim.fn.delete(destination, "rf")
	end
	vim.fn.delete(template_root, "rf")
end

local function test_custom_velocity_java_derivation()
	local template_root = vim.fn.tempname()
	local template_fs = require("minecraft-dev.util.fs")
	vim.fn.mkdir(template_root, "p")
	template_fs.write_file(template_root .. "/java.ft", "${JAVA_VERSION}\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = {
			{ name = "VELOCITY_VERSION", type = "semantic_version" },
			{
				name = "JAVA_VERSION", type = "integer", default = 17,
				derives = { parents = { "VELOCITY_VERSION" }, default = 8, select = {
					{ condition = "$VELOCITY_VERSION.compareTo($semver.release(3, 5)) >= 0", value = 21 },
					{ condition = "$VELOCITY_VERSION.compareTo($semver.release(3, 3)) >= 0", value = 17 },
					{ condition = "$VELOCITY_VERSION.compareTo($semver.release(3)) >= 0", value = 11 },
				} },
			},
		},
		files = { { template = "java.ft", destination = "java.txt" } },
	}))
	for _, case in ipairs({ { version = "3.0.0", java = "11" }, { version = "3.3.0-SNAPSHOT", java = "17" }, { version = "3.5.0-SNAPSHOT", java = "21" } }) do
		local destination = vim.fn.tempname()
		vim.fn.mkdir(destination, "p")
		local result, err = generate_template({ provider = "local", source = template_root, directory = destination, properties = { VELOCITY_VERSION = case.version } })
		assert_truthy(result ~= nil, "Velocity Java derivation fixture should generate")
		assert_equal(err, nil, "Velocity Java derivation should not fail")
		assert_equal(read_file(destination .. "/java.txt"), case.java, "Velocity version should derive its required Java boundary")
		vim.fn.delete(destination, "rf")
	end
	vim.fn.delete(template_root, "rf")
end

local function test_custom_template_discovery()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/nested", "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(root .. "/.mcdev.template.json", vim.json.encode({ version = 3, label = "Root", group = "mod" }))
	template_fs.write_file(root .. "/nested/paper.mcdev.template.json", vim.json.encode({ version = 3, label = "Paper", group = "plugin" }))
	local templates, err = custom_templates.list({ provider = "local", source = root })
	assert_equal(err, nil, "local template discovery should not return an error")
	assert_equal(#templates, 2, "template discovery should find default and named descriptors")
	assert_equal(templates[1].label, "Root", "template discovery should preserve labels")
	assert_equal(templates[2].descriptor, "nested/paper.mcdev.template.json", "template discovery should return relative descriptor path")
	vim.fn.delete(root, "rf")
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
	assert_equal(
		custom_evaluator.render({ ENABLED = true, VERSION = "1.13.8+kotlin.2.2.21" }, 'plugin #if ($ENABLED)yes#else no#end ${VERSION.toString().split("kotlin.")[1]}'),
		"plugin yes 2.2.21",
		"inline conditions and chained string methods should render"
	)
	assert_equal(
		custom_evaluator.render({ LANGUAGE = "Java", CATALOG = true }, [[#if ($LANGUAGE == 'Kotlin')
kotlin version #if ($CATALOG) catalog #else literal #end
#elseif ($LANGUAGE == 'Java')
java
#end
]]),
		"java\n",
		"inline conditions should not consume surrounding block directives"
	)
	assert_equal(
		custom_evaluator.render({ AUTHORS = { "Alice", "Bob" } }, '${AUTHORS.toString(", ", "[", "]")}|${AUTHORS.toStringQuoted()}|${version}|$description'),
		'[Alice, Bob]|"Alice", "Bob"|${version}|$description',
		"StringList methods should render while build-system placeholders remain intact"
	)
	assert_equal(
		custom_evaluator.render({ AUTHORS = { "Alice", "Bob" } }, [[${AUTHORS.toString('", "', '"', '"')}]]),
		'"Alice", "Bob"',
		"StringList arguments should close with their matching quote delimiter"
	)
	assert_equal(custom_evaluator.render({ DESCRIPTION = "present" }, "value#if ($DESCRIPTION), description#end"), "value, description", "truthy inline conditions should render without else")
	assert_equal(custom_evaluator.render({ DESCRIPTION = nil }, "value#if ($DESCRIPTION), description#end"), "value", "false inline conditions should render without else")
	assert_equal(custom_evaluator.expression({}, '$LOAD_AT != "POSTWORLD"'), false, "missing values should not differ from ordinary defaults")
	assert_equal(custom_evaluator.expression({}, "$VALUE != $null"), false, "missing values should equal explicit null")
	assert_equal(custom_evaluator.expression({ VALUE = "set" }, "$VALUE != $null"), true, "present values should differ from explicit null")
	assert_equal(
		custom_evaluator.render({}, "#if (!$GRADLE_VERSION)\n#set ($GRADLE_VERSION = \"8.8\")\n#end\n${GRADLE_VERSION}\n"),
		"8.8\n",
		"set directives in selected conditions should update following template content"
	)
	assert_equal(
		custom_evaluator.render({
			FIRST = false,
			SECOND = true,
			VERSIONS = { forge = "52.1.0" },
		}, "#set ($SELECTED = $FIRST ||\n    ($SECOND && ${VERSIONS.forge.compareTo($semver.parse(\"52.0.9\"))} >= 0))\n#if ($SELECTED)\nselected\n#end\n"),
		"selected\n",
		"multiline directives should be joined before Velocity evaluation"
	)
end

local function test_custom_archive_provider()
	if vim.fn.executable("zip") ~= 1 or vim.fn.executable("unzip") ~= 1 then return end
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	local archive = vim.fn.tempname() .. ".zip"
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(template_root .. "/hello.ft", "hello ${NAME}\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = { { name = "NAME", type = "string", default = "world" } },
		files = { { template = "hello.ft", destination = "hello.txt" } },
	}))
	assert_equal(vim.system({ "zip", "-qr", archive, "." }, { cwd = template_root }):wait().code, 0, "archive fixture should be created")
	local result, generation_error = generate_template({
		provider = "archive",
		source = archive,
		directory = destination,
		properties = { NAME = "archive" },
	})
	assert_truthy(result ~= nil, "archive provider should generate files")
	assert_equal(generation_error, nil, "archive provider should not return an error")
	assert_equal(read_file(destination .. "/hello.txt"), "hello archive", "archive template should render")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
	vim.fn.delete(archive)
end

local function test_custom_remote_provider()
	if vim.fn.executable("git") ~= 1 then return end
	local repository = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(repository, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(repository .. "/remote.ft", "remote ${NAME}\n")
	template_fs.write_file(repository .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = { { name = "NAME", type = "string", default = "template" } },
		files = { { template = "remote.ft", destination = "remote.txt" } },
	}))
	assert_equal(vim.system({ "git", "init", "-q" }, { cwd = repository }):wait().code, 0, "remote fixture should initialize")
	assert_equal(vim.system({ "git", "add", "." }, { cwd = repository }):wait().code, 0, "remote fixture should stage")
	assert_equal(vim.system({ "git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "fixture" }, { cwd = repository }):wait().code, 0, "remote fixture should commit")
	local source = "file://" .. repository
	local result, generation_error = generate_template({
		provider = "remote",
		source = source,
		directory = destination,
		properties = { NAME = "provider" },
	})
	assert_truthy(result ~= nil, "remote provider should generate files")
	assert_equal(generation_error, nil, "remote provider should not return an error")
	assert_equal(read_file(destination .. "/remote.txt"), "remote provider", "remote template should render")
	local cache = vim.fs.joinpath(vim.fn.stdpath("cache"), "minecraft-dev", "templates", vim.fn.sha256(source))
	vim.fn.delete(cache, "rf")
	vim.fn.delete(repository, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_property_derivations()
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(template_root .. "/main.ft", "${MAIN_CLASS.packageName}:${MAIN_CLASS.className}:${MAIN_CLASS.withSubPackage('client').path}:${JAVA_VERSION}:${PLUGIN.enabled}\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		properties = {
			{ name = "PROJECT_NAME", type = "string", default = "Demo Project" },
			{
				name = "MOD_ID", type = "string", validator = "[a-z][a-z0-9-_]{1,63}",
				derives = { parents = { "PROJECT_NAME" }, method = "replace", parameters = { regex = "[^a-z0-9-_]+", replacement = "_", lowercase = true } },
			},
			{ name = "BUILD_COORDS", type = "build_system_coordinates" },
			{ name = "MAIN_CLASS", type = "class_fqn", derives = { parents = { "BUILD_COORDS", "MOD_ID" }, method = "suggestClassName" } },
			{ name = "PLUGIN", type = "gradle_plugin", default = "$JAVA_VERSION == 21" },
			{
				name = "JAVA_VERSION", type = "integer",
				derives = { select = { { condition = "$MC_VERSION.compareTo($mcver.MC1_20_5) >= 0", value = 21 } }, default = 17 },
			},
		},
		files = { { template = "main.ft", destination = "main.txt" } },
	}))
	local result, err = generate_template({
		provider = "local",
		source = template_root,
		directory = destination,
		properties = {
			BUILD_COORDS = { groupId = "dev.example", artifactId = "demo", version = "1.0.0" },
			MC_VERSION = "1.21.1",
		},
	})
	assert_truthy(result ~= nil, "derived custom properties should generate")
	assert_equal(err, nil, "derived custom properties should not return an error")
	assert_equal(read_file(destination .. "/main.txt"), "dev.example.demo:DemoProject:dev/example/demo/client/DemoProject:21:true", "official derivations and semantic conditions should resolve")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_run_config_finalizers()
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	local imported_root
	local import_group = vim.api.nvim_create_augroup("MinecraftDevTestImport", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = import_group,
		pattern = "MinecraftDevProjectGenerated",
		callback = function(args) imported_root = args.data.root end,
	})
	template_fs.write_file(template_root .. "/empty.ft", "project\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		files = { { template = "empty.ft", destination = "README.txt" } },
		finalizers = {
			{ type = "import_gradle_project" },
			{ type = "run_gradle_tasks", tasks = { "genIntellijRuns" } },
			{ type = "add_gradle_run", name = "Build", tasks = { "build" } },
			{ type = "add_maven_run", name = "Package", goals = { "package" } },
		},
	}))
	local result, err = generate_template({
		provider = "local",
		source = template_root,
		directory = destination,
		properties = { VERSIONS = { minecraft = "1.21.1", forge = "52.1.0" } },
	})
	assert_truthy(result ~= nil, "run config finalizers should complete")
	assert_equal(err, nil, "run config finalizers should not return an error")
	local runs = vim.json.decode(read_file(destination .. "/.nvim/minecraft-dev-runs.json"))
	assert_equal(runs[1].args, { "runClient" }, "genIntellijRuns should map the Forge client run to Neovim metadata")
	assert_equal(runs[2].args, { "runServer" }, "genIntellijRuns should map the Forge server run to Neovim metadata")
	assert_equal(runs[3].args, { "runData" }, "genIntellijRuns should map the Forge data run to Neovim metadata")
	assert_equal(runs[4].type, "gradle", "Gradle run finalizer should persist its type")
	assert_equal(runs[4].args, { "build" }, "Gradle run finalizer should persist tasks")
	assert_equal(runs[5].type, "maven", "Maven run finalizer should persist its type")
	assert_equal(runs[5].args, { "package" }, "Maven run finalizer should persist goals")
	assert_equal(imported_root, destination, "import finalizers should receive the committed destination")
	vim.api.nvim_del_augroup_by_id(import_group)
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_wrapper_version_finalizer()
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(template_root .. "/wrapper.ft", "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.8-bin.zip\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		files = { { template = "wrapper.ft", destination = "gradle/wrapper/gradle-wrapper.properties" } },
		finalizers = { { type = "run_gradle_tasks", tasks = { "wrapper" } } },
	}))
	local original_generate_gradlew = gradle.generate_gradlew
	local wrapper_version
	gradle.generate_gradlew = function(_, _, version)
		wrapper_version = version
		local result = { status = "generated" }
		return { status = "generated", result = result, on_complete = function(callback) callback(result) end, cancel = function() end }
	end
	local result, err = generate_template({ provider = "local", source = template_root, directory = destination })
	gradle.generate_gradlew = original_generate_gradlew
	assert_truthy(result ~= nil, "Gradle wrapper finalizer fixture should generate")
	assert_equal(err, nil, "Gradle wrapper finalizer fixture should not fail")
	assert_equal(wrapper_version, "8.8", "wrapper finalizers should preserve the template Gradle version")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function test_custom_finalizer_failure_cleanup()
	if vim.fn.executable("git") ~= 1 then return end
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(template_root .. "/README.ft", "staged\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		files = { { template = "README.ft", destination = "README.txt" } },
		finalizers = { { type = "git_add_all" } },
	}))
	local callback_count = 0
	local operation = custom_templates.generate({
		provider = "local",
		source = template_root,
		directory = destination,
		callback = function(result)
			callback_count = callback_count + 1
			assert_equal(result.status, "failed", "custom callback should receive finalizer failure")
		end,
	})
	assert_equal(operation.status, "pending", "external finalizers should keep generation pending")
	vim.wait(5000, function() return operation.status ~= "pending" end, 20)
	assert_equal(operation.status, "failed", "failed finalizers should fail template generation")
	assert_equal(operation.result.error.code, "finalizer_failed", "finalizer errors should remain structured")
	assert_equal(vim.fn.filereadable(destination .. "/README.txt"), 0, "failed finalizers should not pollute the destination")
	vim.wait(1000, function() return callback_count == 1 end, 10)
	assert_equal(callback_count, 1, "custom generation callback should run exactly once")
	local git_destination = vim.fn.tempname()
	vim.fn.mkdir(git_destination, "p")
	local generated, generation_error = generate_template({
		provider = "local",
		source = template_root,
		directory = git_destination,
		use_git = true,
	})
	assert_truthy(generated ~= nil, "USE_GIT should initialize staging before git finalizers")
	assert_equal(generation_error, nil, "initialized Git finalizers should complete")
	assert_equal(vim.fn.isdirectory(git_destination .. "/.git"), 1, "Git initialization should be committed with the project")
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
	vim.fn.delete(git_destination, "rf")
end

local function test_custom_finalizer_cancellation()
	local template_root = vim.fn.tempname()
	local destination = vim.fn.tempname()
	vim.fn.mkdir(template_root, "p")
	vim.fn.mkdir(destination, "p")
	local template_fs = require("minecraft-dev.util.fs")
	template_fs.write_file(template_root .. "/README.ft", "staged\n")
	template_fs.write_file(template_root .. "/.mcdev.template.json", vim.json.encode({
		version = 3,
		files = { { template = "README.ft", destination = "README.txt" } },
		finalizers = { { type = "run_gradle_tasks", tasks = { "build" } } },
	}))
	local original_system = vim.system
	local process_callback
	local killed = false
	vim.system = function(_, _, callback)
		process_callback = callback
		return { kill = function() killed = true end }
	end
	local callback_count = 0
	local operation = custom_templates.generate({
		provider = "local",
		source = template_root,
		directory = destination,
		callback = function(result)
			callback_count = callback_count + 1
			assert_equal(result.status, "cancelled", "custom callback should receive cancellation")
		end,
	})
	vim.system = original_system
	operation.cancel()
	assert_equal(operation.status, "pending", "custom cancellation should wait for the finalizer process")
	assert_equal(killed, true, "custom cancellation should terminate the finalizer process")
	process_callback({ code = 143, stderr = "cancelled" })
	vim.wait(1000, function() return operation.status == "cancelled" end, 10)
	assert_equal(operation.status, "cancelled", "custom cancellation should finish after process exit")
	assert_equal(vim.fn.filereadable(destination .. "/README.txt"), 0, "cancelled finalizers should not pollute the destination")
	vim.wait(1000, function() return callback_count == 1 end, 10)
	assert_equal(callback_count, 1, "cancelled custom generation should callback exactly once")
	local replacement_callback
	vim.system = function(_, _, callback)
		replacement_callback = callback
		return { kill = function() end }
	end
	local replaced_operation = custom_templates.generate({ provider = "local", source = template_root, directory = destination })
	vim.system = original_system
	local replacement_target = vim.fn.tempname()
	vim.fn.mkdir(replacement_target, "p")
	vim.fn.delete(destination, "d")
	assert_truthy(vim.uv.fs_symlink(replacement_target, destination) ~= nil, "custom runtime symlink replacement should be created")
	replacement_callback({ code = 0, stderr = "" })
	vim.wait(1000, function() return replaced_operation.status ~= "pending" end, 10)
	assert_equal(replaced_operation.status, "failed", "custom runtime symlink replacement should fail commit")
	assert_equal(replaced_operation.result.error.code, "destination_changed", "custom runtime symlink replacement should remain structured")
	vim.fn.delete(destination)
	vim.fn.mkdir(destination, "p")
	vim.fn.delete(replacement_target, "rf")
	local invalid_destination = custom_templates.generate({
		provider = "local",
		source = template_root,
		directory = "/proc/minecraft-dev-test/project",
	})
	assert_equal(invalid_destination.status, "failed", "uncreatable destinations should return a failed operation")
	assert_equal(invalid_destination.result.error.code, "destination_prepare_failed", "destination preparation failures should remain structured")
	if vim.fn.executable("unzip") == 1 then
		local missing_archive = custom_templates.generate({ provider = "archive", directory = vim.fn.tempname() })
		assert_equal(missing_archive.status, "failed", "missing archive sources should fail immediately")
		assert_equal(missing_archive.result.error.code, "source_missing", "missing archive sources should return source_missing")
	end
	local symlink_target = vim.fn.tempname()
	local symlink_destination = vim.fn.tempname()
	vim.fn.mkdir(symlink_target, "p")
	assert_truthy(vim.uv.fs_symlink(symlink_target, symlink_destination) ~= nil, "custom symlink fixture should be created")
	local symlink_result = custom_templates.generate({ provider = "local", source = template_root, directory = symlink_destination })
	assert_equal(symlink_result.status, "failed", "custom symlink destinations should be rejected")
	assert_equal(symlink_result.result.error.code, "destination_symlink", "custom symlink rejection should remain structured")
	vim.fn.delete(symlink_destination)
	vim.fn.delete(symlink_target, "rf")

	if vim.fn.executable("git") == 1 then
		local remote_source = "file:///minecraft-dev-cancel-" .. tostring(vim.uv.hrtime())
		local remote_destination = vim.fn.tempname()
		vim.fn.mkdir(remote_destination, "p")
		local remote_process_callback
		local remote_killed = false
		vim.system = function(_, _, callback)
			remote_process_callback = callback
			return { kill = function() remote_killed = true end }
		end
		local remote_callback_count = 0
		local remote_operation = custom_templates.generate({
			provider = "remote",
			source = remote_source,
			directory = remote_destination,
			callback = function(result)
				remote_callback_count = remote_callback_count + 1
				assert_equal(result.status, "cancelled", "remote callback should receive cancellation")
			end,
		})
		vim.system = original_system
		remote_operation.cancel()
		assert_equal(remote_operation.status, "pending", "remote cancellation should wait for Git exit")
		assert_equal(remote_killed, true, "remote cancellation should terminate Git")
		remote_process_callback({ code = 143, stderr = "cancelled" })
		vim.wait(1000, function() return remote_operation.status == "cancelled" and remote_callback_count == 1 end, 10)
		assert_equal(remote_operation.status, "cancelled", "remote generation should settle after Git exits")
		local cache_root = vim.fs.joinpath(vim.fn.stdpath("cache"), "minecraft-dev", "templates", vim.fn.sha256(remote_source))
		for name in vim.fs.dir(vim.fs.dirname(cache_root)) do
			assert_truthy(not vim.startswith(name, vim.fs.basename(cache_root) .. ".clone-"), "cancelled clone should remove its temporary cache")
		end
		vim.fn.delete(remote_destination, "rf")
	end
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
end

local function fabric_catalog_fixture()
	return fabric_version_data.parse_catalog_responses(
		vim.json.encode({
			game = {
				{ version = "26.1.2", stable = true },
				{ version = "26.2-snapshot-1", stable = false },
				{ version = "1.21.1", stable = true },
			},
			loader = { { version = "0.16.0-rc.9" }, { version = "0.16.0-rc.10" }, { version = "0.16.9" }, { version = "0.19.3" } },
			mappings = {
				{ gameVersion = "1.20.1", version = "1.20.1+build.2", build = 2 },
				{ gameVersion = "1.21.1", version = "1.21.1+build.1", build = 1 },
				{ gameVersion = "1.21.1", version = "1.21.1+build.3", build = 3 },
			},
		}),
		vim.json.encode({
			{
				version_number = "0.115.0+1.21.1",
				game_versions = { "1.21.1" },
				files = { { filename = "fabric-api-0.115.0+1.21.1.jar" } },
			},
			{
				version_number = "0.116.15+1.21.1",
				game_versions = { "1.21.1" },
				files = { { filename = "fabric-api-0.116.15+1.21.1.jar" } },
			},
			{
				version_number = "0.155.2+26.1.2",
				game_versions = { "26.1", "26.1.1", "26.1.2" },
				files = { { filename = "fabric-api-0.155.2+26.1.2.jar" } },
			},
		}),
		"<metadata><versioning><versions><version>1.16-SNAPSHOT</version><version>1.17.17</version></versions></versioning></metadata>"
	)
end

local function test_custom_fabric_version_wizard()
	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_generate_template = minecraft_dev.generate_template
	local original_load_catalog = fabric_version_data.load_catalog
	local original_property_load = custom_property_values.load
	local original_input = vim.ui.input
	local original_select = vim.ui.select
	local generated_properties
	local inputs = { "/tmp/fabric-wizard", "fabric-wizard" }
	local input_count = 0
	local catalog = fabric_catalog_fixture()
	local catalog_warning = { code = "version_fetch_failed", source = "api" }
	local include_kotlin = false

	minecraft_dev.list_templates = function(options)
		local properties = { { name = "VERSIONS", type = "fabric_versions" } }
		if include_kotlin then
			table.insert(properties, { name = "KOTLIN_LOADER_VERSION", type = "maven_artifact_version", parameters = { sourceUrl = "https://repo.example/kotlin.xml" } })
		end
		options.callback({ {
			label = "Fabric",
			group = "mod",
			descriptor = "fabric/.mcdev.template.json",
			definition = { properties = properties },
		} }, nil)
		return { status = "generated", cancel = function() end }
	end
	minecraft_dev.generate_template = function(options)
		generated_properties = options.properties
		local result = { status = "generated" }
		options.callback(result)
		return { status = "generated", result = result, cancel = function() end }
	end
	fabric_version_data.load_catalog = function(callback)
		callback(catalog, catalog_warning)
		return { status = "generated", cancel = function() end }, nil
	end
	vim.ui.input = function(_, callback)
		input_count = input_count + 1
		callback(table.remove(inputs, 1))
	end
	vim.ui.select = function(items, select_options, callback)
		local picker_prompt = select_options.prompt
		if type(items[1]) == "table" and items[1].definition then callback(items[1])
		elseif picker_prompt == require("minecraft-dev").config.prompts.fabric.show_snapshots then callback(false)
		elseif picker_prompt == require("minecraft-dev").config.prompts.fabric.minecraft_version then callback("1.21.1")
		elseif picker_prompt == require("minecraft-dev").config.prompts.fabric.use_official_mappings then callback(false)
		elseif picker_prompt == require("minecraft-dev").config.prompts.fabric.use_fabric_api then callback(true)
		else callback(items[1]) end
	end

	local operation = wizard.run()
	local first_input_count = input_count
	include_kotlin = true
	catalog_warning = nil
	inputs = { "/tmp/fabric-wizard-cancel", "fabric-wizard-cancel" }
	local kotlin_cancelled = false
	custom_property_values.load = function(_, callback)
		local child = { status = "pending" }
		function child.cancel()
			kotlin_cancelled = true
			child.status = "cancelled"
			callback(nil, { code = "cancelled" })
		end
		return child, nil
	end
	local cancelling = wizard.run()
	assert_equal(cancelling.status, "pending", "Fabric wizard should wait for Kotlin metadata after a synchronous catalog selection")
	cancelling.cancel()
	minecraft_dev.list_templates = original_list_templates
	minecraft_dev.generate_template = original_generate_template
	fabric_version_data.load_catalog = original_load_catalog
	custom_property_values.load = original_property_load
	vim.ui.input = original_input
	vim.ui.select = original_select

	assert_equal(operation.status, "generated", "Fabric wizard should generate without a JSON property prompt")
	assert_equal(operation.result.warnings, { { code = "version_fetch_failed", source = "api" } }, "stale Fabric catalog warnings should reach the final wizard result")
	assert_equal(first_input_count, 2, "Fabric versions should only require directory and project name text input")
	assert_equal(generated_properties.VERSIONS.minecraftVersion, "1.21.1", "Fabric selector should retain the selected Minecraft version")
	assert_equal(generated_properties.VERSIONS.loader, "0.19.3", "Fabric selector should sort and select the newest Loader")
	assert_equal(generated_properties.VERSIONS.yarn.name, "1.21.1+build.3", "Fabric selector should select matching Yarn mappings")
	assert_equal(generated_properties.VERSIONS.fabricApi, "0.116.15+1.21.1", "Fabric selector should select the newest matching Fabric API")
	assert_equal(generated_properties.VERSIONS.useOfficialMappings, false, "Fabric selector should preserve the mappings choice")
	assert_equal(kotlin_cancelled, true, "Fabric wizard cancellation should reach a later Kotlin metadata request")
	assert_equal(cancelling.status, "cancelled", "Fabric wizard should settle as cancelled after terminating Kotlin metadata")
end

local function test_fabric_online_version_parser()
	local catalog = fabric_catalog_fixture()
	assert_equal(fabric_version_data.minecraft_versions(catalog, false), { "26.1.2", "1.21.1" }, "stable Fabric versions should exclude snapshots and retain API order")
	assert_equal(fabric_version_data.minecraft_versions(catalog, true)[2], "26.2-snapshot-1", "snapshot selection should expose unstable Minecraft versions")
	assert_equal(catalog.loader, { "0.19.3", "0.16.9", "0.16.0-rc.10", "0.16.0-rc.9" }, "Fabric loaders should use numeric prerelease sorting")
	local yarn, yarn_exact = fabric_version_data.yarn_versions(catalog, "1.21.1")
	assert_equal(yarn_exact, true, "matching Yarn versions should be marked exact")
	assert_equal(yarn[1].name, "1.21.1+build.3", "matching Yarn versions should use descending build order")
	local fallback_yarn, fallback_yarn_exact = fabric_version_data.yarn_versions(catalog, "26.1.2")
	assert_equal(fallback_yarn_exact, false, "missing Yarn versions should be marked as fallback")
	assert_equal(#fallback_yarn, 3, "missing Yarn versions should expose the complete fallback list")
	assert_equal(fallback_yarn[1].name, "1.21.1+build.3", "Yarn fallback versions should sort by game version before build number")
	local api, api_exact = fabric_version_data.fabric_api_versions(catalog, "1.21.1")
	assert_equal(api_exact, true, "matching Fabric API versions should be marked exact")
	assert_equal(api[1], "0.116.15+1.21.1", "Fabric API versions should be sorted newest first")
	assert_equal(fabric_version_data.cache_is_fresh(100, 160, 60), true, "Fabric cache should remain fresh at the TTL boundary")
	assert_equal(fabric_version_data.cache_is_fresh(100, 161, 60), false, "Fabric cache should expire after the configured TTL")
	local catalog_cache = vim.fs.joinpath(vim.fn.stdpath("cache"), "minecraft-dev", "fabric", "catalog.json")
	local cache_existed = vim.fn.filereadable(catalog_cache) == 1
	local cache_backup = cache_existed and vim.fn.readfile(catalog_cache) or nil
	vim.fn.mkdir(vim.fs.dirname(catalog_cache), "p")
	local fresh_cache = vim.deepcopy(catalog)
	fresh_cache._cached_at = os.time()
	vim.fn.writefile({ vim.json.encode(fresh_cache) }, catalog_cache)
	local fresh_catalog
	local fresh_operation = fabric_version_data.load_catalog(function(value, err)
		fresh_catalog = { value = value, err = err }
	end)
	assert_equal(fresh_operation.status, "generated", "fresh Fabric catalog caches should skip network refresh")
	assert_equal(fresh_catalog.err, nil, "fresh Fabric catalog caches should not warn")
	assert_equal(fresh_catalog.value.loader[1], "0.19.3", "fresh Fabric catalog caches should preserve parsed values")

	local stale_cache = vim.deepcopy(catalog)
	stale_cache._cached_at = os.time() - require("minecraft-dev").config.defaults.fabric.cache_ttl - 1
	vim.fn.writefile({ vim.json.encode(stale_cache) }, catalog_cache)
	local stale_requests = {}
	local stale_result
	local stale_operation = fabric_version_data.load_catalog(function(value, err)
		stale_result = { value = value, err = err }
	end, function(_, _, callback)
		table.insert(stale_requests, callback)
		return { kill = function() end }
	end)
	assert_equal(#stale_requests, 3, "expired Fabric catalogs should refresh every required source")
	for _, request_callback in ipairs(stale_requests) do request_callback({ code = 22, stderr = "offline" }) end
	vim.wait(1000, function() return stale_result ~= nil end, 10)
	assert_equal(stale_operation.status, "generated", "expired Fabric catalogs should fall back to stale data on network failure")
	assert_equal(stale_result.err.code, "version_fetch_failed", "stale Fabric catalog fallback should preserve the refresh warning")
	assert_equal(stale_result.value.loader[1], "0.19.3", "stale Fabric catalog fallback should return cached values")

	vim.fn.writefile({ "{" }, catalog_cache)
	local corrupt_requests = {}
	local corrupt_result
	local corrupt_operation = fabric_version_data.load_catalog(function(value, err)
		corrupt_result = { value = value, err = err }
	end, function(_, _, callback)
		table.insert(corrupt_requests, callback)
		return { kill = function() end }
	end)
	for _, request_callback in ipairs(corrupt_requests) do request_callback({ code = 22, stderr = "offline" }) end
	vim.wait(1000, function() return corrupt_result ~= nil end, 10)
	assert_equal(corrupt_operation.status, "failed", "corrupt Fabric catalogs should not be used as stale fallback")
	assert_equal(corrupt_result.value, nil, "corrupt Fabric catalogs should not return data")
	if cache_existed then vim.fn.writefile(cache_backup, catalog_cache) else vim.fn.delete(catalog_cache) end
	local parsed = fabric_version_data.parse_responses(
		vim.json.encode({ { loader = { version = "0.19.3", stable = true } } }),
		vim.json.encode({ { version = "1.21.1+build.3" } }),
		vim.json.encode({ { version_number = "0.116.14+1.21.1" } }),
		"<metadata><versioning><release> 1.13.13+kotlin.2.4.10 </release></versioning></metadata>",
		"<metadata><versioning><release>1.15.2</release><versions><version>1.15.2</version><version>1.16-SNAPSHOT</version></versions></versioning></metadata>"
	)
	assert_equal(parsed.loader, "0.19.3", "online parser should select loader version")
	assert_equal(parsed.yarn, "1.21.1+build.3", "online parser should select latest Yarn mapping")
	assert_equal(parsed.fabric_api, "0.116.14+1.21.1", "online parser should select latest Fabric API")
	assert_equal(parsed.kotlin_loader, "1.13.13+kotlin.2.4.10", "online parser should select released Fabric Language Kotlin")
	assert_equal(parsed.loom_version, "1.15.2", "online parser should select released Fabric Loom")
	assert_equal(parsed.gradle_version, "9.6.1", "online Fabric versions should use the compatible Gradle wrapper")
	local fallback = fabric_version_data.parse_responses(
		vim.json.encode({ { loader = { version = "0.19.3" } } }),
		vim.json.encode({}),
		vim.json.encode({ { version_number = "0.116.14+1.21.1" } }),
		"<metadata><versioning><release>garbage+kotlin.</release></versioning></metadata>",
		nil
	)
	assert_equal(fallback.kotlin_loader, config.default_config.defaults.fabric.version_data.kotlin_loader, "Kotlin metadata failure should use configured fallback")
	assert_equal(fallback.loom_version, config.default_config.defaults.fabric.version_data.loom_version, "Loom metadata failure should use configured fallback")
	local bundled = fabric_version_data.read("1.14.4")
	assert_truthy(bundled.kotlin_loader ~= nil, "bundled Fabric versions should inherit the Kotlin fallback")
	assert_truthy(bundled.loom_version ~= nil, "bundled Fabric versions should inherit the Loom fallback")
	assert_truthy(bundled.gradle_version ~= nil, "bundled Fabric versions should inherit the Gradle fallback")
	local invalid_cache_version = "minecraft-dev-invalid-cache-test"
	local invalid_cache_path = vim.fs.joinpath(vim.fn.stdpath("cache"), "minecraft-dev", "fabric", invalid_cache_version .. ".json")
	vim.fn.mkdir(vim.fs.dirname(invalid_cache_path), "p")
	vim.fn.writefile({ vim.json.encode({ kotlin_loader = "invalid", loom_version = "", gradle_version = "" }) }, invalid_cache_path)
	local normalized_cache = fabric_version_data.read(invalid_cache_version)
	assert_equal(normalized_cache.kotlin_loader, config.default_config.defaults.fabric.version_data.kotlin_loader, "invalid cached Kotlin versions should use configured fallback")
	assert_equal(normalized_cache.loom_version, config.default_config.defaults.fabric.version_data.loom_version, "empty cached Loom versions should use configured fallback")
	assert_equal(normalized_cache.gradle_version, config.default_config.defaults.fabric.version_data.gradle_version, "empty cached Gradle versions should use configured fallback")
	vim.fn.writefile({ vim.json.encode("invalid") }, invalid_cache_path)
	local scalar_cache = fabric_version_data.read(invalid_cache_version)
	assert_equal(scalar_cache.kotlin_loader, config.default_config.defaults.fabric.version_data.kotlin_loader, "scalar Fabric cache data should be ignored")
	vim.fn.delete(invalid_cache_path)

	local pending_requests = {}
	local version_callback_count = 0
	local resolve_operation = fabric_version_data.resolve("1.21.1", function() version_callback_count = version_callback_count + 1 end, function(_, _, callback)
		local request = { callback = callback, killed = false }
		function request.kill() request.killed = true end
		table.insert(pending_requests, request)
		return request
	end)
	resolve_operation.cancel()
	assert_equal(resolve_operation.status, "pending", "version cancellation should wait for curl processes to exit")
	for _, request in ipairs(pending_requests) do
		assert_equal(request.killed, true, "version cancellation should terminate every curl process")
		request.callback({ code = 143, stderr = "cancelled" })
	end
	vim.wait(1000, function() return resolve_operation.status == "cancelled" end, 10)
	assert_equal(resolve_operation.status, "cancelled", "version cancellation should finish after every curl exits")
	assert_equal(version_callback_count, 0, "cancelled version resolution should not continue generation")
	local spawn_failure_count = 0
	local failed_spawn = fabric_version_data.resolve("1.21.1", function(_, err)
		spawn_failure_count = spawn_failure_count + 1
		assert_equal(err.code, "version_fetch_failed", "curl startup failures should use the fallback error contract")
	end, function() error("cannot start curl") end)
	assert_equal(failed_spawn.status, "generated", "curl startup failures should settle after fallback data is returned")
	assert_equal(spawn_failure_count, 1, "curl startup failures should callback exactly once")

	local catalog_requests = {}
	local catalog_cancelled
	local catalog_operation = fabric_version_data.load_catalog(function(_, err) catalog_cancelled = err end, function(_, _, callback)
		local request = { callback = callback, killed = false }
		function request.kill() request.killed = true end
		table.insert(catalog_requests, request)
		return request
	end)
	catalog_operation.cancel()
	for _, request in ipairs(catalog_requests) do
		assert_equal(request.killed, true, "catalog cancellation should terminate every Fabric request")
		request.callback({ code = 143, stderr = "cancelled" })
	end
	vim.wait(1000, function() return catalog_operation.status == "cancelled" end, 10)
	assert_equal(catalog_cancelled.code, "cancelled", "catalog cancellation should use the structured cancellation contract")
end

local function test_forge_family_generation()
	local gradle = require("minecraft-dev.util.gradle")
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() return true end
	for _, platform in ipairs({ "forge", "neoforge" }) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
			platform = platform,
			build_system = "gradle",
			minecraft_version = "1.21.1",
			loader_version = platform == "forge" and "52.1.0" or "21.1.209",
			moddev_version = platform == "neoforge" and "2.0.143" or nil,
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
		assert_truthy(build:find("\\n", 1, true) == nil, platform .. " Gradle script should not contain escaped newlines")
		if platform == "forge" then
			assert_truthy(read_file(directory .. "/settings.gradle"):find("repo.spongepowered.org", 1, true) ~= nil, "Forge Mixins should configure the Sponge plugin repository")
		end
		assert_equal(vim.fn.filereadable(directory .. "/src/main/resources/examplemod.mixins.json"), 1, platform .. " should generate mixin config")
		local manifest_path = platform == "forge" and "/src/main/resources/META-INF/mods.toml"
			or "/src/main/templates/META-INF/neoforge.mods.toml"
		assert_equal(vim.fn.filereadable(directory .. manifest_path), 1, platform .. " manifest should exist")
		vim.fn.delete(directory, "rf")
	end
	gradle.generate_gradlew = original_generate_gradlew
end

local function forge_catalog_fixture()
	local coordinates = {
		"1.16.5-36.2.42",
		"1.17.1-37.1.1",
		"1.18.2-40.2.21",
		"1.19.2-43.4.20",
		"1.19.3-44.1.23",
		"1.20.1-47.4.10",
		"1.21.1-52.1.0",
		"1.21.11-61.1.14",
		"1.15.2-31.2.57",
		"invalid",
	}
	for index = 1, 55 do table.insert(coordinates, "1.20.1-47.3." .. tostring(index)) end
	local versions = {}
	for _, coordinate in ipairs(coordinates) do table.insert(versions, "<version>" .. coordinate .. "</version>") end
	return "<metadata><versioning><versions>" .. table.concat(versions) .. "</versions></versioning></metadata>"
end

local function test_forge_version_data_and_wizard()
	local catalog, parse_error = forge_version_data.parse(forge_catalog_fixture())
	assert_equal(parse_error, nil, "valid Forge Maven metadata should parse")
	assert_equal(catalog.minecraft, { "1.21.1", "1.20.1", "1.19.3", "1.19.2", "1.18.2", "1.17.1", "1.16.5" }, "Forge Minecraft versions should be supported and newest first")
	assert_equal(#catalog.forge["1.20.1"], 50, "Forge candidates should retain the upstream 50-version limit")
	assert_equal(catalog.forge["1.20.1"][1], "47.4.10", "Forge candidates should use numeric descending order")
	assert_equal(forge_version_data.derive("1.20.6", "50.1.17"), {
		minecraft = "1.20.6", forge = "50.1.17", minecraftNext = "1.21", forgeSpec = "50",
	}, "Forge model fields should match the upstream derivations")
	assert_equal(select(1, forge_version_data.parse("<metadata/>")), nil, "empty Forge metadata should fail")

	local process_callback
	local requested_command
	local killed = false
	local cancelled
	local operation = forge_version_data.load(function(_, err) cancelled = err end, function(command, _, callback)
		requested_command = command
		process_callback = callback
		return { kill = function() killed = true end }
	end)
	operation.cancel()
	assert_equal(killed, true, "Forge cancellation should terminate curl")
	process_callback({ code = 143, stderr = "cancelled" })
	vim.wait(1000, function() return operation.status == "cancelled" end, 10)
	assert_equal(cancelled.code, "cancelled", "Forge cancellation should remain structured")
	assert_truthy(table.concat(requested_command, " "):find("https://maven.minecraftforge.net/", 1, true) ~= nil, "Forge versions should use the canonical Maven endpoint")
	assert_truthy(vim.tbl_contains(requested_command, "--location"), "Forge metadata requests should follow redirects")
	local reentrant_callback
	local reentrant_count = 0
	local reentrant_operation
	reentrant_operation = forge_version_data.load(function()
		reentrant_count = reentrant_count + 1
		reentrant_operation.cancel()
	end, function(_, _, callback)
		reentrant_callback = callback
		return { kill = function() end }
	end)
	reentrant_callback({ code = 0, stdout = forge_catalog_fixture(), stderr = "" })
	vim.wait(1000, function() return reentrant_operation.status ~= "pending" end, 10)
	assert_equal(reentrant_operation.status, "generated", "Forge version callbacks should observe the terminal operation state")
	assert_equal(reentrant_count, 1, "Forge version callback re-entry should not complete twice")

	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_generate_template = minecraft_dev.generate_template
	local original_load = forge_version_data.load
	local original_input = vim.ui.input
	local original_select = vim.ui.select
	local generated_properties
	local input_count = 0
	local inputs = { "/tmp/forge-wizard", "forge-wizard" }
	minecraft_dev.list_templates = function(options)
		options.callback({ {
			label = "Forge", group = "mod", descriptor = "forge/.mcdev.template.json",
			definition = { properties = { { name = "VERSIONS", type = "forge_versions", limit = 3 } } },
		} }, nil)
		return { status = "generated", cancel = function() end }
	end
	minecraft_dev.generate_template = function(options)
		generated_properties = options.properties
		local result = { status = "generated" }
		options.callback(result)
		return { status = "generated", result = result, cancel = function() end }
	end
	forge_version_data.load = function(callback)
		callback(catalog, nil)
		return { status = "generated", cancel = function() end }, nil
	end
	vim.ui.input = function(_, callback) input_count = input_count + 1 callback(table.remove(inputs, 1)) end
	vim.ui.select = function(items, options, callback)
		if type(items[1]) == "table" then callback(items[1])
		elseif options.prompt == require("minecraft-dev").config.prompts.forge.minecraft_version then callback("1.20.1")
		else callback(items[1]) end
	end
	local wizard_operation = wizard.run()
	minecraft_dev.list_templates = original_list_templates
	minecraft_dev.generate_template = original_generate_template
	forge_version_data.load = original_load
	vim.ui.input = original_input
	vim.ui.select = original_select
	assert_equal(wizard_operation.status, "generated", "Forge wizard should generate without JSON input")
	assert_equal(input_count, 2, "Forge versions should only require directory and project name text input")
	assert_equal(generated_properties.VERSIONS.minecraft, "1.20.1", "Forge wizard should retain the selected Minecraft version")
	assert_equal(generated_properties.VERSIONS.forge, "47.4.10", "Forge wizard should select the newest compatible Forge")
end

local function neoforge_metadata_fixture(values)
	local versions = {}
	for _, value in ipairs(values) do table.insert(versions, "<version>" .. value .. "</version>") end
	return "<metadata><versioning><versions>" .. table.concat(versions) .. "</versions></versioning></metadata>"
end

local function test_neoforge_version_data_and_wizard()
	local catalog, parse_error = neoforge_version_data.parse_catalog_responses(
		neoforge_metadata_fixture({ "21.4.1-beta", "20.6.139", "21.4.156", "21.1.209", "21.5.1", "20.4.200" }),
		neoforge_metadata_fixture({ "7.0.168", "7.1.38" }),
		neoforge_metadata_fixture({ "2.0.116", "2.0.143" })
	)
	assert_equal(parse_error, nil, "valid NeoForge Maven metadata should parse")
	assert_equal(catalog.minecraft, { "1.21.4", "1.21.1", "1.20.6" }, "NeoForge should expose only the supported Minecraft range")
	assert_equal(catalog.neoforge["1.21.4"], { "21.4.156", "21.4.1-beta" }, "NeoForge releases should sort before prereleases")
	assert_equal(catalog.neogradle[1], "7.1.38", "NeoGradle versions should sort newest first")
	assert_equal(catalog.moddev[1], "2.0.143", "ModDevGradle versions should sort newest first")
	assert_equal(neoforge_version_data.derive("1.21.4", "21.4.156", "7.1.38", "2.0.143"), {
		minecraft = "1.21.4", neoforge = "21.4.156", neogradle = "7.1.38", moddev = "2.0.143",
		minecraftNext = "1.22", neoforgeSpec = "21.4",
	}, "NeoForge model fields should match upstream derivations")
	assert_equal(select(1, neoforge_version_data.parse_catalog_responses("<metadata/>", "<metadata/>", "<metadata/>")), nil, "empty NeoForge metadata should fail")
	local requests = {}
	local cancellation_count = 0
	local cancelled_operation = neoforge_version_data.load(function(_, err)
		cancellation_count = cancellation_count + 1
		assert_equal(err.code, "cancelled", "NeoForge cancellation should remain structured")
	end, function(_, _, callback)
		local request = { callback = callback, killed = false }
		function request.kill() request.killed = true end
		table.insert(requests, request)
		return request
	end)
	cancelled_operation.cancel()
	assert_equal(cancelled_operation.status, "pending", "NeoForge cancellation should wait for every curl process")
	for index, request in ipairs(requests) do
		assert_equal(request.killed, true, "NeoForge cancellation should terminate every metadata request")
		request.callback({ code = 143, stderr = "cancelled" })
		vim.wait(1000, function() return index < #requests or cancelled_operation.status == "cancelled" end, 10)
		if index < #requests then assert_equal(cancelled_operation.status, "pending", "NeoForge cancellation should not finish after only one child exits") end
	end
	assert_equal(cancelled_operation.status, "cancelled", "NeoForge cancellation should settle after all curl processes exit")
	assert_equal(cancellation_count, 1, "NeoForge cancellation should callback exactly once")
	local failed_requests = {}
	local failure_error
	local failed_operation = neoforge_version_data.load(function(_, err) failure_error = err end, function(_, _, callback)
		local request = { callback = callback, killed = false }
		function request.kill() request.killed = true end
		table.insert(failed_requests, request)
		return request
	end)
	failed_requests[1].callback({ code = 22, stderr = "not found" })
	vim.wait(1000, function() return failed_requests[2].killed and failed_requests[3].killed end, 10)
	assert_equal(failed_operation.status, "pending", "NeoForge failures should wait for remaining curl processes")
	failed_operation.cancel()
	failed_requests[2].callback({ code = 143, stderr = "cancelled" })
	failed_requests[3].callback({ code = 143, stderr = "cancelled" })
	vim.wait(1000, function() return failed_operation.status == "failed" end, 10)
	assert_equal(failure_error.code, "version_fetch_failed", "cancellation after a fetch failure should preserve the first terminal cause")

	local parchment_callback
	local parchment_command
	local parchment_values
	local parchment_operation = neoforge_version_data.load_parchment("1.21.4", function(values) parchment_values = values end, function(command, _, callback)
		parchment_command = command
		parchment_callback = callback
		return { kill = function() end }
	end)
	parchment_callback({ code = 0, stdout = neoforge_metadata_fixture({ "2024.04.29-nightly-SNAPSHOT", "2025.03.23" }), stderr = "" })
	vim.wait(1000, function() return parchment_operation.status ~= "pending" end, 10)
	assert_equal(parchment_values, { "2025.03.23", "2024.04.29-nightly-SNAPSHOT" }, "Parchment versions should include exact-version snapshots and sort newest first")
	assert_truthy(table.concat(parchment_command, " "):find("Accept: application/xml", 1, true) ~= nil, "Parchment requests should force raw XML responses")
	assert_truthy(table.concat(parchment_command, " "):find("maven.parchmentmc.org", 1, true) ~= nil, "Parchment should use the public repository containing 1.20.5 metadata")
	local parchment_selector = require("minecraft-dev.custom.parchment")
	local original_parchment_select = vim.ui.select
	local disabled_parchment
	vim.ui.select = function(_, _, callback) callback(false) end
	local disabled_operation = parchment_selector.select(
		{ parameters = { minecraftVersionProperty = "VERSIONS" } },
		{ VERSIONS = { minecraft = "1.20.5" } },
		function(value) disabled_parchment = value end
	)
	vim.ui.select = original_parchment_select
	assert_equal(disabled_operation.status, "generated", "Parchment should be explicitly disableable")
	assert_equal(disabled_parchment, { use = false, minecraftVersion = "1.20.5" }, "disabled Parchment should retain its Minecraft version")

	local minecraft_dev = require("minecraft-dev")
	local wizard = require("minecraft-dev.custom.wizard")
	local original_list_templates = minecraft_dev.list_templates
	local original_generate_template = minecraft_dev.generate_template
	local original_load = neoforge_version_data.load
	local original_load_parchment = neoforge_version_data.load_parchment
	local original_input = vim.ui.input
	local original_select = vim.ui.select
	local generated_properties
	local inputs = { "/tmp/neoforge-wizard", "neoforge-wizard" }
	minecraft_dev.list_templates = function(options)
		options.callback({ {
			label = "NeoForge", group = "mod", descriptor = "neoforge/.mcdev.template.json",
			definition = { properties = {
				{ name = "VERSIONS", type = "neoforge_versions" },
				{ name = "PARCHMENT", type = "parchment", parameters = { minecraftVersionProperty = "VERSIONS" } },
			} },
		} }, nil)
		return { status = "generated", cancel = function() end }
	end
	minecraft_dev.generate_template = function(options)
		generated_properties = options.properties
		local result = { status = "generated" }
		options.callback(result)
		return { status = "generated", result = result, cancel = function() end }
	end
	neoforge_version_data.load = function(callback) callback(catalog); return { status = "generated", cancel = function() end }, nil end
	neoforge_version_data.load_parchment = function(_, callback) callback({ "2025.03.23" }); return { status = "generated", cancel = function() end }, nil end
	vim.ui.input = function(_, callback) callback(table.remove(inputs, 1)) end
	vim.ui.select = function(items, options, callback)
		if type(items[1]) == "table" then callback(items[1])
		elseif options.prompt == require("minecraft-dev").config.prompts.neoforge.minecraft_version then callback("1.21.4")
		else callback(items[1]) end
	end
	local wizard_operation = wizard.run()
	minecraft_dev.list_templates = original_list_templates
	minecraft_dev.generate_template = original_generate_template
	neoforge_version_data.load = original_load
	neoforge_version_data.load_parchment = original_load_parchment
	vim.ui.input = original_input
	vim.ui.select = original_select
	assert_equal(wizard_operation.status, "generated", "NeoForge wizard should generate without JSON input")
	assert_equal(generated_properties.VERSIONS.neoforge, "21.4.156", "NeoForge wizard should retain the selected loader")
	assert_equal(generated_properties.VERSIONS.moddev, "2.0.143", "NeoForge wizard should retain the selected ModDevGradle version")
	assert_equal(generated_properties.PARCHMENT.version, "2025.03.23", "NeoForge wizard should select Parchment mappings")
end

local function test_neoforge_versioned_generation()
	local original_generate_gradlew = gradle.generate_gradlew
	local wrapper_versions = {}
	gradle.generate_gradlew = function(_, _, wrapper_version)
		table.insert(wrapper_versions, wrapper_version)
		return true
	end
	local cases = {
		{ minecraft = "1.20.6", loader = "20.6.139", neogradle = "7.1.38", language = "java", plugin = "net.neoforged.gradle.userdev", config = "new ResourceLocation(name)", data = "programArguments.addAll", pack = 32 },
		{ minecraft = "1.21.1", loader = "21.1.209", moddev = "2.0.143", language = "java", plugin = "net.neoforged.moddev", config = "ResourceLocation.parse(name)", data = "data()", pack = 34 },
		{ minecraft = "1.21.3", loader = "21.3.93", moddev = "2.0.143", language = "java", plugin = "net.neoforged.moddev", config = "getValue(ResourceLocation.parse", data = "data()", pack = 42, metadata_edge = true },
		{ minecraft = "1.21.4", loader = "21.4.156", moddev = "2.0.143", language = "java", plugin = "net.neoforged.moddev", config = "getValue(ResourceLocation.parse", data = "clientData()", pack = 46 },
		{ minecraft = "1.20.6", loader = "20.6.139", neogradle = "7.1.38", language = "kotlin", plugin = "net.neoforged.gradle.userdev", data = "programArguments.addAll", pack = 32 },
	}
	for _, case in ipairs(cases) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
			platform = "neoforge", build_system = "gradle", minecraft_version = case.minecraft,
			directory = directory, group_id = "com.example", artifact_id = "examplemod",
			package_name = "com.example.examplemod", main_class = "ExampleMod", language = case.language,
			loader_version = case.loader, neogradle_version = case.neogradle, moddev_version = case.moddev,
			plugin_version = "1.0.0", plugin_name = case.metadata_edge and 'Example "Mod"' or nil,
			description = case.metadata_edge and "first\nsecond '''\1" or nil,
			update_url = case.metadata_edge and "https://example.invalid/$channel.json" or nil,
			website = case.metadata_edge and "https://example.invalid/${project}" or nil,
			license = "MIT", authors = case.metadata_edge and { "Example\\Author" } or { "Example" }, use_mixins = true,
		})
		assert_equal(ok, true, "NeoForge " .. case.minecraft .. " " .. case.language .. " generation should succeed")
		assert_equal(err, nil, "NeoForge generation should not return an error")
		local build = read_file(directory .. "/build.gradle")
		assert_truthy(build:find(case.plugin, 1, true) ~= nil, "NeoForge should select the correct Gradle plugin")
		assert_truthy(build:find(case.data, 1, true) ~= nil, "NeoForge should select the correct datagen DSL")
		assert_equal(vim.fn.filereadable(directory .. "/src/main/templates/META-INF/neoforge.mods.toml"), 1, "NeoForge metadata should remain a resource template")
		assert_equal(vim.fn.filereadable(directory .. "/src/main/resources/assets/examplemod/lang/en_us.json"), 1, "NeoForge should generate English translations")
		assert_truthy(not read_file(directory .. "/src/main/resources/examplemod.mixins.json"):find("refmap", 1, true), "NeoForge 1.20.5+ Mixins should omit refmaps")
		assert_equal(vim.json.decode(read_file(directory .. "/src/main/resources/pack.mcmeta")).pack.pack_format, case.pack, "NeoForge should use the Minecraft resource pack format")
		if case.metadata_edge then
			local properties = read_file(directory .. "/gradle.properties")
			assert_truthy(properties:find("mod_description=first\\\\nsecond", 1, true) ~= nil, "NeoForge metadata should keep multiline descriptions on one properties line")
			assert_truthy(properties:find("\\\\u0001", 1, true) ~= nil, "NeoForge metadata should encode forbidden TOML control characters")
			assert_truthy(read_file(directory .. "/src/main/templates/META-INF/neoforge.mods.toml"):find('description="${mod_description}"', 1, true) ~= nil, "NeoForge descriptions should expand into escaped TOML basic strings")
			assert_truthy(read_file(directory .. "/src/main/templates/META-INF/neoforge.mods.toml"):find('${mod_update_url}', 1, true) ~= nil, "NeoForge URLs should be expanded from property values rather than nested template text")
		end
		if case.language == "java" then
			assert_truthy(read_file(directory .. "/src/main/java/com/example/examplemod/Config.java"):find(case.config, 1, true) ~= nil, "NeoForge should select the matching Config template")
		else
			assert_equal(vim.fn.filereadable(directory .. "/src/main/kotlin/com/example/examplemod/ExampleMod.kt"), 1, "Kotlin NeoForge should generate a Kotlin entrypoint")
			assert_truthy(build:find("kotlinforforge-neoforge:5.2.0", 1, true) ~= nil, "Kotlin NeoForge should use the compatible KotlinForForge version")
			assert_equal(vim.fn.filereadable(directory .. "/src/main/java/com/example/examplemod/mixin/ExampleMixin.java"), 1, "Kotlin NeoForge Mixins should remain Java sources")
		end
		vim.fn.delete(directory, "rf")
	end
	assert_equal(wrapper_versions, { "8.14", "8.8", "8.8", "8.8", "8.14" }, "NeoForge should use Gradle versions compatible with each plugin family")
	gradle.generate_gradlew = original_generate_gradlew
end

local function test_forge_versioned_generation()
	local original_generate_gradlew = gradle.generate_gradlew
	local wrapper_versions = {}
	gradle.generate_gradlew = function(_, _, wrapper_version)
		table.insert(wrapper_versions, wrapper_version)
		return true
	end
	local cases = {
		{ minecraft = "1.16.5", forge = "36.2.42", marker = "LogManager", pack = 6 },
		{ minecraft = "1.17.1", forge = "37.1.1", marker = "fmlserverevents", pack = 7 },
		{ minecraft = "1.18.2", forge = "40.2.21", marker = "LogUtils", pack = 9 },
		{ minecraft = "1.19.2", forge = "43.4.20", marker = "DeferredRegister", pack = 10 },
		{ minecraft = "1.19.3", forge = "44.1.23", marker = "CreativeModeTabEvent", pack = 10 },
		{ minecraft = "1.20", forge = "46.0.14", marker = "ModLoadingContext", pack = 15 },
		{ minecraft = "1.20.1", forge = "47.4.10", marker = "ModLoadingContext.get()", pack = 15 },
		{ minecraft = "1.20.6", forge = "50.1.17", marker = "FMLJavaModLoadingContext context", pack = 32 },
		{ minecraft = "1.21.1", forge = "52.1.0", marker = "FMLJavaModLoadingContext context", pack = 34 },
	}
	for _, case in ipairs(cases) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
			platform = "forge", build_system = "gradle", minecraft_version = case.minecraft,
			loader_version = case.forge, directory = directory, group_id = "com.example",
			artifact_id = "examplemod", package_name = "com.example.examplemod", main_class = "ExampleMod",
			language = "java", plugin_version = "1.0.0", plugin_name = "Example Mod", license = "MIT",
			authors = { "Alice", "Bob" }, website = "https://example.com", update_url = "https://example.com/update.json",
			description = "Example ${description}", use_mixins = true,
		})
		assert_equal(ok, true, "Forge " .. case.minecraft .. " generation should succeed")
		assert_equal(err, nil, "Forge " .. case.minecraft .. " generation should not return an error")
		local source = read_file(directory .. "/src/main/java/com/example/examplemod/ExampleMod.java")
		assert_truthy(source:find(case.marker, 1, true) ~= nil, "Forge " .. case.minecraft .. " should select its entry template")
		local pack = vim.json.decode(read_file(directory .. "/src/main/resources/pack.mcmeta"))
		assert_equal(pack.pack.pack_format, case.pack, "Forge " .. case.minecraft .. " should select its pack format")
		if (version.compare(case.minecraft, "1.20.3") or -1) < 0 then
			assert_truthy(read_file(directory .. "/build.gradle"):find('mods { "examplemod" {', 1, true) ~= nil, "Forge run mod IDs should be quoted Groovy names")
		end
		local expects_config = (version.compare(case.minecraft, "1.20.1") or -1) >= 0
		assert_equal(vim.fn.filereadable(directory .. "/src/main/java/com/example/examplemod/Config.java"), expects_config and 1 or 0, "Forge Config should follow its version boundary")
		assert_equal(vim.fn.filereadable(directory .. "/src/main/java/com/example/examplemod/mixin/ExampleMixin.java"), 1, "Forge should generate a Mixin source")
		assert_equal(vim.fn.filereadable(directory .. "/LICENSE.txt"), 1, "Forge should generate a license file")
		local runs = vim.json.decode(read_file(directory .. "/.nvim/minecraft-dev-runs.json"))
		assert_equal(#runs, 4, "Forge should generate client, server, data, and build runs")
		if case.minecraft == "1.21.1" then
			assert_truthy(read_file(directory .. "/src/main/java/com/example/examplemod/Config.java"):find("ResourceLocation.parse", 1, true) ~= nil, "Forge 1.21 should use the new Config API")
			local manifest = read_file(directory .. "/src/main/resources/META-INF/mods.toml")
			for _, marker in ipairs({ "updateJSONURL", "displayURL", 'authors="Alice, Bob"', 'description="Example ${description}"', 'modId="minecraft"', 'versionRange="[1.21.1,1.22)"' }) do
				assert_truthy(manifest:find(marker, 1, true) ~= nil, "Forge metadata should include " .. marker)
			end
		end
		vim.fn.delete(directory, "rf")
	end
	local original_resolve = forge_version_data.resolve
	forge_version_data.resolve = function(minecraft, callback)
		callback(forge_version_data.derive(minecraft, "47.4.10"), nil)
		return { status = "generated", cancel = function() end }, nil
	end
	local resolved_directory = vim.fn.tempname()
	vim.fn.mkdir(resolved_directory, "p")
	local resolved_ok, resolved_error = generate_project({
		platform = "forge", build_system = "gradle", minecraft_version = "1.20.1",
		directory = resolved_directory, group_id = "com.example", artifact_id = "resolvedmod",
		package_name = "com.example.resolvedmod", main_class = "ResolvedMod", language = "java",
	})
	forge_version_data.resolve = original_resolve
	assert_equal(resolved_ok, true, "Forge generation should resolve an omitted loader version")
	assert_equal(resolved_error, nil, "Forge automatic version resolution should not fail")
	assert_truthy(read_file(resolved_directory .. "/build.gradle"):find("1.20.1-47.4.10", 1, true) ~= nil, "resolved Forge coordinates should reach the build")
	vim.fn.delete(resolved_directory, "rf")
	gradle.generate_gradlew = original_generate_gradlew
	local expected_wrappers = {}
	for _ = 1, #cases + 1 do table.insert(expected_wrappers, "8.8") end
	assert_equal(wrapper_versions, expected_wrappers, "Forge should use its supported wrapper version")
end

local function test_additional_plugin_platforms()
	local expectations = {
		bungeecord = { dependency = "bungeecord-api", metadata = "src/main/resources/bungee.yml" },
		waterfall = { dependency = "waterfall-api", metadata = "src/main/resources/bungee.yml" },
		velocity = { dependency = "velocity-api", pom_marker = "annotationProcessorPaths", source_marker = "@Plugin" },
		sponge = { dependency = "spongeapi", metadata = "src/main/resources/META-INF/sponge_plugins.json" },
	}
	for platform, expectation in pairs(expectations) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local platform_version = platform == "velocity" and "3.5.0-SNAPSHOT"
			or platform == "sponge" and "11.0.0"
			or platform == "bungeecord" and "1.21-R0.3"
			or "1.21"
		local ok, err = generate_project({
			platform = platform,
			build_system = "maven",
			minecraft_version = platform_version,
			waterfall_version = platform == "waterfall" and "1.21-R0.5-SNAPSHOT" or nil,
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
		assert_truthy(pom:find("\\n", 1, true) == nil, platform .. " POM should not contain escaped newlines")
		if expectation.pom_marker then
			assert_truthy(pom:find(expectation.pom_marker, 1, true) ~= nil, platform .. " POM should configure annotation processing")
		end
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

local function test_waterfall_version_resolution()
	local metadata = [[<metadata><versioning><versions>
<version>1.20-R0.3-SNAPSHOT</version>
<version>1.21-R0.4-SNAPSHOT</version>
<version>1.21-R0.5-SNAPSHOT</version>
<version>26.1-R0.1-SNAPSHOT</version>
</versions></versioning></metadata>]]
	local selected
	local operation, err = plugin_version_data.resolve_waterfall_version("1.21", function(value, resolve_error)
		selected = { value = value, error = resolve_error }
	end, function(command, _, callback)
		assert_truthy(command[#command]:find("waterfall-api/maven-metadata.xml", 1, true) ~= nil, "Waterfall should load its API metadata")
		callback({ code = 0, stdout = metadata, stderr = "" })
		return { kill = function() end }
	end)
	assert_equal(err, nil, "Waterfall version resolution should start")
	assert_truthy(vim.wait(1000, function() return selected ~= nil end, 10), "Waterfall version resolution should finish")
	assert_equal(operation.status, "generated", "Waterfall version resolution should succeed")
	assert_equal(selected, { value = "1.21-R0.5-SNAPSHOT" }, "Waterfall should select the newest matching API version")
	local missing, missing_error = plugin_version_data.select_waterfall_version({ "1.21-R0.5-SNAPSHOT" }, "1.19")
	assert_equal(missing, nil, "unknown Waterfall Minecraft versions should not be guessed")
	assert_equal(missing_error.code, "waterfall_version_not_found", "unknown Waterfall versions should fail structurally")
	assert_equal(plugin_version_data.select_waterfall_version({ "1.21-R0.5-SNAPSHOT" }, "1.21.1"), "1.21-R0.5-SNAPSHOT", "patch Minecraft versions should use their Waterfall major/minor family")
	assert_equal(plugin_version_data.select_waterfall_version({ "1.15-SNAPSHOT" }, "1.15"), "1.15-SNAPSHOT", "legacy Waterfall versions without R identifiers should resolve")
	assert_equal(plugin_version_data.select_waterfall_version({ "26.1-R0.1-SNAPSHOT" }, "26.1"), "26.1-R0.1-SNAPSHOT", "calendar Waterfall versions should retain their full family")
	assert_equal(plugin_version_data.select_waterfall_version({ "26.1-R0.1-SNAPSHOT" }, "26.1.1"), "26.1-R0.1-SNAPSHOT", "calendar patch versions should use their Waterfall major/minor family")
end

local function test_waterfall_resolution_lifecycle()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local original_system = vim.system
	local process_callback
	local killed = false
	vim.system = function(_, _, callback)
		process_callback = callback
		return { kill = function() killed = true end }
	end
	local callback_count = 0
	local operation = project.generate({
		platform = "waterfall", build_system = "maven", minecraft_version = "1.21",
		directory = directory, group_id = "com.example", artifact_id = "waterfall-cancel",
		package_name = "com.example.waterfall", main_class = "WaterfallPlugin", language = "java",
	}, function() callback_count = callback_count + 1 end)
	vim.system = original_system
	operation.cancel()
	assert_equal(operation.status, "pending", "Waterfall cancellation should wait for the metadata process")
	assert_equal(killed, true, "Waterfall cancellation should terminate metadata loading")
	assert_equal(vim.fn.filereadable(directory .. ".minecraft-dev.lock"), 1, "Waterfall cancellation should retain the generation lock until curl exits")
	process_callback({ code = 143, stdout = "", stderr = "cancelled" })
	vim.wait(1000, function() return operation.status == "cancelled" end, 10)
	assert_equal(operation.status, "cancelled", "Waterfall cancellation should finish after curl exits")
	assert_equal(callback_count, 1, "Waterfall cancellation should callback once")
	assert_equal(vim.fn.filereadable(directory .. ".minecraft-dev.lock"), 0, "Waterfall cancellation should release its lock after curl exits")

	local original_resolve = plugin_version_data.resolve_waterfall_version
	plugin_version_data.resolve_waterfall_version = function() return nil, { code = "curl_missing" } end
	local failed = project.generate({
		platform = "waterfall", build_system = "maven", minecraft_version = "1.21",
		directory = directory, group_id = "com.example", artifact_id = "waterfall-failed",
		package_name = "com.example.waterfall", main_class = "WaterfallPlugin", language = "java",
	})
	plugin_version_data.resolve_waterfall_version = original_resolve
	assert_equal(failed.status, "failed", "Waterfall resolver startup failures should fail generation")
	assert_equal(failed.result.error.detail.code, "curl_missing", "Waterfall resolver startup errors should retain their context")
	vim.fn.delete(directory, "rf")
end

local function test_proxy_and_sponge_generation_modes()
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() return true end
	for _, platform in ipairs({ "bungeecord", "waterfall", "sponge" }) do
		for _, language in ipairs({ "java", "kotlin" }) do
			for _, build_system in ipairs({ "gradle", "maven" }) do
				local directory = vim.fn.tempname()
				vim.fn.mkdir(directory, "p")
				local version_value = platform == "sponge" and "11.0.0"
					or platform == "bungeecord" and "1.21-R0.3"
					or "1.21"
				local ok, generation_error = generate_project({
					platform = platform, build_system = build_system, minecraft_version = version_value,
					waterfall_version = platform == "waterfall" and "1.21-R0.5-SNAPSHOT" or nil,
					directory = directory, group_id = "com.example", artifact_id = platform .. "-test",
					package_name = "com.example.plugin", main_class = "ExamplePlugin", language = language,
					plugin_version = "1.2.3", plugin_name = "Example", authors = { "Alice" }, license = "MIT",
				})
				assert_equal(ok, true, platform .. " " .. language .. " " .. build_system .. " should generate")
				assert_equal(generation_error, nil, platform .. " generation should not fail")
				local groovy = build_system == "gradle" and platform ~= "sponge" and language == "java"
				local build_file = build_system == "maven" and "pom.xml" or groovy and "build.gradle" or "build.gradle.kts"
				local build = read_file(directory .. "/" .. build_file)
				if language == "kotlin" then
					local packaging_marker = build_system == "maven" and "maven-shade-plugin" or "shadow"
					assert_truthy(build:find(packaging_marker, 1, true) ~= nil, platform .. " Kotlin builds should package the Kotlin runtime")
				end
				if platform == "sponge" then
					local java_marker = build_system == "maven"
						and (language == "kotlin" and "<jvmTarget>21</jvmTarget>" or "<maven.compiler.release>21</maven.compiler.release>")
						or "val javaTarget = 21"
					assert_truthy(build:find(java_marker, 1, true) ~= nil, "Sponge should derive Java 21 for API 11")
					assert_equal(vim.fn.filereadable(directory .. "/src/main/resources/META-INF/sponge_plugins.json"), build_system == "maven" and 1 or 0, "only Sponge Maven should write static metadata")
				else
					local java_marker = build_system == "maven"
						and (language == "kotlin" and "<jvmTarget>1.8</jvmTarget>" or "<maven.compiler.release>8</maven.compiler.release>")
						or language == "kotlin" and "jvmToolchain(8)" or "JavaVersion.VERSION_1_8"
					assert_truthy(build:find(java_marker, 1, true) ~= nil, platform .. " should target Java 8")
					if platform == "waterfall" then
						local version_marker = build_system == "maven" and "<version>1.21-R0.5-SNAPSHOT</version>"
							or "waterfall-api:1.21-R0.5-SNAPSHOT"
						assert_truthy(build:find(version_marker, 1, true) ~= nil, "Waterfall should consume the selected API version")
					end
				end
				vim.fn.delete(directory, "rf")
			end
		end
	end
	for _, boundary in ipairs({ { version = "8.2.0", java = 16 }, { version = "9.0.0", java = 17 }, { version = "10.0.0", java = 17 }, { version = "11.0.0", java = 21 } }) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok = generate_project({
			platform = "sponge", build_system = "maven", minecraft_version = boundary.version,
			directory = directory, group_id = "com.example", artifact_id = "sponge-boundary",
			package_name = "com.example.sponge", main_class = "SpongePlugin", language = "java",
		})
		assert_equal(ok, true, "Sponge Java boundary project should generate")
		local pom = read_file(directory .. "/pom.xml")
		assert_truthy(pom:find("<maven.compiler.release>" .. boundary.java .. "</maven.compiler.release>", 1, true) ~= nil, "Sponge API should derive its Java boundary")
		vim.fn.delete(directory, "rf")
	end
	gradle.generate_gradlew = original_generate_gradlew
end

local function test_velocity_generation_modes()
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() return true end
	for _, case in ipairs({
		{ build = "gradle", language = "java", marker = "JavaLanguageVersion.of(21)", source = "src/main/java/com/example/velocity/VelocityPlugin.java", annotation = true },
		{ build = "maven", language = "java", marker = "<maven.compiler.release>21</maven.compiler.release>", source = "src/main/java/com/example/velocity/VelocityPlugin.java", annotation = true },
		{ build = "gradle", language = "kotlin", marker = "jvmToolchain(21)", source = "src/main/kotlin/com/example/velocity/VelocityPlugin.kt", annotation = false },
		{ build = "maven", language = "kotlin", marker = "<jvmTarget>21</jvmTarget>", source = "src/main/kotlin/com/example/velocity/VelocityPlugin.kt", annotation = false },
		{ build = "gradle", language = "kotlin", marker = 'kapt("com.velocitypowered:velocity-api:3.5.0-SNAPSHOT")', source = "src/main/kotlin/com/example/velocity/VelocityPlugin.kt", annotation = true, use_annotation_processor = true },
		{ build = "maven", language = "kotlin", marker = "<goal>kapt</goal>", source = "src/main/kotlin/com/example/velocity/VelocityPlugin.kt", annotation = true, use_annotation_processor = true },
	}) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
			platform = "velocity", build_system = case.build, minecraft_version = "3.5.0-SNAPSHOT",
			directory = directory, group_id = "com.example", artifact_id = "velocity-test",
			package_name = "com.example.velocity", main_class = "VelocityPlugin", language = case.language,
			plugin_version = "1.2.3", authors = { "Alice" }, use_annotation_processor = case.use_annotation_processor,
		})
		assert_equal(ok, true, "Velocity " .. case.language .. " " .. case.build .. " should generate")
		assert_equal(err, nil, "Velocity generation should not fail")
		local build = read_file(directory .. "/" .. (case.build == "gradle" and "build.gradle.kts" or "pom.xml"))
		assert_truthy(build:find(case.marker, 1, true) ~= nil, "Velocity build should use its Java boundary")
		local source = read_file(directory .. "/" .. case.source)
		assert_equal(source:find("@Plugin", 1, true) ~= nil, case.annotation, "Velocity annotation mode should match the language")
		if case.language == "kotlin" and case.annotation then
			assert_truthy(source:find('authors = [ "Alice" ]', 1, true) ~= nil, "Kotlin Velocity annotations should use Kotlin array syntax")
		end
		assert_equal(vim.fn.filereadable(directory .. "/src/main/resources/velocity-plugin.json"), case.annotation and 0 or 1, "Velocity JSON metadata should complement annotation processing")
		vim.fn.delete(directory, "rf")
	end
	for _, boundary in ipairs({ { version = "3.0.0", java = 11 }, { version = "3.3.0", java = 17 }, { version = "3.5.0", java = 21 } }) do
		for _, build_system in ipairs({ "gradle", "maven" }) do
			local directory = vim.fn.tempname()
			vim.fn.mkdir(directory, "p")
			local ok, err = generate_project({
				platform = "velocity", build_system = build_system, minecraft_version = boundary.version,
				directory = directory, group_id = "com.example", artifact_id = "velocity-boundary",
				package_name = "com.example.velocity", main_class = "VelocityPlugin", language = "java",
			})
			assert_equal(ok, true, "Velocity Java boundary project should generate")
			assert_equal(err, nil, "Velocity Java boundary generation should not fail")
			local build = read_file(directory .. "/" .. (build_system == "gradle" and "build.gradle.kts" or "pom.xml"))
			local marker = build_system == "gradle" and "JavaLanguageVersion.of(" .. boundary.java .. ")"
				or "<maven.compiler.release>" .. boundary.java .. "</maven.compiler.release>"
			assert_truthy(build:find(marker, 1, true) ~= nil, "native Velocity generation should derive each Java boundary")
			vim.fn.delete(directory, "rf")
		end
	end
	gradle.generate_gradlew = original_generate_gradlew
end

local function test_gradle_wrapper_generation_isolated_from_project()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local function fake_system(command, options, callback)
		assert_equal(command, { "gradle", "wrapper", "--gradle-version", "8.12.1" }, "wrapper should use the compatible Gradle version")
		assert_truthy(options.cwd ~= directory, "wrapper should be generated outside the target project")
		vim.fn.mkdir(options.cwd .. "/gradle/wrapper", "p")
		vim.fn.writefile({ "#!/bin/sh" }, options.cwd .. "/gradlew")
		vim.fn.writefile({}, options.cwd .. "/gradlew.bat")
		vim.fn.writefile({}, options.cwd .. "/gradle/wrapper/gradle-wrapper.jar")
		vim.fn.writefile({ "distributionUrl=gradle-8.12.1-bin.zip" }, options.cwd .. "/gradle/wrapper/gradle-wrapper.properties")
		callback({ code = 0, stderr = "" })
	end

	gradle.generate_gradlew(directory, fake_system)
	assert_truthy(vim.wait(1000, function()
		return vim.fn.filereadable(directory .. "/gradle/wrapper/gradle-wrapper.properties") == 1
	end, 10), "wrapper files should be copied into the target project")
	local start_failed = gradle.generate_gradlew(directory, function() error("cannot start Gradle") end)
	assert_equal(start_failed.status, "failed", "Gradle startup errors should return a failed operation")
	assert_equal(start_failed.result.error.code, "gradle_wrapper_start_failed", "Gradle startup errors should remain structured")
	vim.fn.delete(directory, "rf")
end

local function test_spigot_maven_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = generate_project({
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
	assert_truthy(pom:match("<version>2%.1%.0</version>") ~= nil, "Spigot Maven project should use the requested project version")

	local manifest = read_file(directory .. "/src/main/resources/plugin.yml")
	assert_truthy(manifest:match('version: "2%.1%.0"') ~= nil, "manifest should use the requested plugin version")
	assert_truthy(manifest:match('description: "Example plugin"') ~= nil, "manifest should include description")
	assert_truthy(manifest:match('authors: %[%"Alice%",%"Bob%"%]') ~= nil, "manifest should include authors")
	assert_truthy(manifest:match('load: "STARTUP"') ~= nil, "manifest should include non-default load order")
	assert_truthy(manifest:match('depend: %[%"RequiredPlugin%"%]') ~= nil, "manifest should include hard dependencies")
	assert_truthy(manifest:match('softdepend: %[%"OptionalPlugin%"%]') ~= nil, "manifest should include soft dependencies")
	vim.fn.delete(directory, "rf")
end

local function test_spigot_calendar_generation()
	assert_equal(version.resolve_family("26.1.2"), "v1_13_plus", "calendar versions should use modern Bukkit templates")
	assert_equal(version.required_java("1.16.5"), 8, "Minecraft 1.16.5 should use Java 8")
	assert_equal(version.required_java("1.17.1"), 16, "Minecraft 1.17.1 should use Java 16")
	assert_equal(version.required_java("1.20.4"), 17, "Minecraft 1.20.4 should use Java 17")
	assert_equal(version.required_java("1.20.4-R0.1-SNAPSHOT"), 17, "dependency qualifiers should not change the Minecraft Java boundary")
	assert_equal(version.required_java("1.21.11"), 21, "Minecraft 1.21.11 should use Java 21")
	assert_equal(version.required_java("1.21.11-pre1"), 21, "prerelease suffixes should not cross the Java 25 boundary")
	assert_equal(version.required_java("26.1"), 25, "Minecraft 26.1 should use Java 25")
	assert_equal(version.required_java("invalid"), 21, "invalid versions should use the safe default Java version")

	local original_generate_gradlew = gradle.generate_gradlew
	local wrapper_versions = {}
	gradle.generate_gradlew = function(_, _, wrapper_version)
		table.insert(wrapper_versions, wrapper_version)
		return true
	end
	for _, case in ipairs({
		{ build_system = "gradle", language = "java", build_file = "build.gradle.kts", java_marker = "JavaLanguageVersion.of(25)" },
		{ build_system = "gradle", language = "kotlin", build_file = "build.gradle.kts", java_marker = "jvmToolchain(25)" },
		{ build_system = "maven", language = "java", build_file = "pom.xml", java_marker = "<java.version>25</java.version>" },
		{ build_system = "maven", language = "kotlin", build_file = "pom.xml", java_marker = "<java.version>25</java.version>" },
	}) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
			platform = "spigot",
			build_system = case.build_system,
			minecraft_version = "26.1.2",
			directory = directory,
			group_id = "com.example",
			artifact_id = "spigot-calendar",
			package_name = "com.example.spigot",
			main_class = "SpigotCalendar",
			language = case.language,
			plugin_version = "3.4.5",
		})
		assert_equal(ok, true, "Spigot calendar project should generate for " .. case.language .. " " .. case.build_system)
		assert_equal(err, nil, "Spigot calendar generation should not fail")
		local build = read_file(directory .. "/" .. case.build_file)
		assert_truthy(build:find("org.spigotmc", 1, true) ~= nil, "Spigot calendar project should use Spigot coordinates")
		assert_truthy(build:find(case.java_marker, 1, true) ~= nil, "Spigot calendar project should use Java 25")
		assert_truthy(build:find("3.4.5", 1, true) ~= nil, "Spigot calendar project should use plugin_version")
		if case.build_system == "gradle" and case.language == "kotlin" then
			assert_truthy(build:find('kotlin("jvm") version "2.4.10"', 1, true) ~= nil, "Spigot Java 25 Kotlin project should use a compatible Kotlin plugin")
			assert_truthy(build:find('id("com.gradleup.shadow") version "9.6.1"', 1, true) ~= nil, "Spigot Java 25 Kotlin project should use a compatible Shadow plugin")
		end
		local manifest = read_file(directory .. "/src/main/resources/plugin.yml")
		assert_truthy(manifest:find('api-version: "26.1"', 1, true) ~= nil, "Spigot calendar manifest should derive major.minor api-version")
		vim.fn.delete(directory, "rf")
	end
	gradle.generate_gradlew = original_generate_gradlew
	assert_equal(wrapper_versions, { "9.5.0", "9.5.0" }, "Spigot Java 25 Gradle projects should use a compatible wrapper")
end

local function test_paper_manifest_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = generate_project({
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
	local fabric = vim.tbl_extend("force", valid, { platform = "fabric", minecraft_version = "1.21.1" })
	local invalid_option, invalid_option_error = project.validate(vim.tbl_extend("force", fabric, { use_fabric_api = "yes" }))
	assert_equal(invalid_option, nil, "non-boolean Fabric options should be rejected")
	assert_equal(invalid_option_error, { code = "invalid_type", field = "use_fabric_api" }, "invalid Fabric option types should remain structured")
	local missing_yarn, missing_yarn_error = project.validate(vim.tbl_extend("force", fabric, { use_official_mappings = false }))
	assert_equal(missing_yarn, nil, "Yarn mappings should require an explicit version before 26.1")
	assert_equal(missing_yarn_error, { code = "missing_field", field = "yarn_version" }, "missing Yarn versions should remain structured")
	local invalid_api, invalid_api_error = project.validate(vim.tbl_extend("force", fabric, { fabric_api_version = "" }))
	assert_equal(invalid_api, nil, "empty Fabric API overrides should be rejected")
	assert_equal(invalid_api_error, { code = "invalid_version", field = "fabric_api_version" }, "invalid Fabric API versions should remain structured")
	local missing_api, missing_api_error = project.validate(vim.tbl_extend("force", fabric, {
		use_fabric_api = true,
		fabric_version_data = { loader = "0.16.14" },
	}))
	assert_equal(missing_api, nil, "explicit Fabric version data should include API coordinates when API is enabled")
	assert_equal(missing_api_error, { code = "missing_field", field = "fabric_api_version" }, "missing Fabric API versions should remain structured")
	local listed_api, listed_api_error = project.validate(vim.tbl_extend("force", fabric, {
		fabric_version_data = { loader = "0.16.14", fabric_api = { "0.116.15+1.21.1" } },
	}))
	assert_truthy(listed_api ~= nil, "Fabric API version lists should remain valid input")
	assert_equal(listed_api_error, nil, "Fabric API version lists should not fail validation")
	local invalid_data, invalid_data_error = project.validate(vim.tbl_extend("force", fabric, { language = "kotlin", fabric_version_data = "invalid" }))
	assert_equal(invalid_data, nil, "non-table Fabric version data should be rejected structurally")
	assert_equal(invalid_data_error, { code = "invalid_type", field = "fabric_version_data" }, "invalid Fabric version data should not throw")
	local forge = vim.tbl_extend("force", valid, { platform = "forge", minecraft_version = "1.20.1", artifact_id = "examplemod" })
	local dynamic_forge, dynamic_forge_error = project.validate(forge)
	assert_truthy(dynamic_forge ~= nil, "Forge should allow dynamic loader resolution")
	assert_equal(dynamic_forge_error, nil, "dynamic Forge validation should not fail")
	local old_forge, old_forge_error = project.validate(vim.tbl_extend("force", forge, { minecraft_version = "1.15.2" }))
	assert_equal(old_forge, nil, "Forge should reject Minecraft versions before 1.16")
	assert_equal(old_forge_error, { code = "unsupported_version", field = "minecraft_version" }, "old Forge versions should fail structurally")
	local invalid_forge, invalid_forge_error = project.validate(vim.tbl_extend("force", forge, { loader_version = "latest" }))
	assert_equal(invalid_forge, nil, "Forge should reject malformed explicit loader versions")
	assert_equal(invalid_forge_error, { code = "invalid_version", field = "loader_version" }, "malformed Forge versions should fail structurally")
	local long_mod_id, long_mod_id_error = project.validate(vim.tbl_extend("force", forge, { artifact_id = "a" .. string.rep("b", 64) }))
	assert_equal(long_mod_id, nil, "Forge should reject mod IDs longer than 64 characters")
	assert_equal(long_mod_id_error, { code = "invalid_mod_id", field = "artifact_id" }, "long Forge mod IDs should fail structurally")
	local future_forge, future_forge_error = project.validate(vim.tbl_extend("force", forge, { minecraft_version = "1.21.4" }))
	assert_equal(future_forge, nil, "Forge should reject versions requiring the unimplemented ForgeGradle 7 template")
	assert_equal(future_forge_error, { code = "unsupported_version", field = "minecraft_version" }, "future Forge versions should fail structurally")
	local unsafe_parchment, unsafe_parchment_error = project.validate(vim.tbl_extend("force", forge, { parchment_version = "2024.11.17'" }))
	assert_equal(unsafe_parchment, nil, "Forge should reject unsafe Parchment versions")
	assert_equal(unsafe_parchment_error, { code = "invalid_version", field = "parchment_version" }, "unsafe Parchment versions should fail structurally")
	local neoforge = vim.tbl_extend("force", valid, {
		platform = "neoforge", minecraft_version = "1.21.4", artifact_id = "examplemod", language = "kotlin",
	})
	local dynamic_neoforge, dynamic_neoforge_error = project.validate(neoforge)
	assert_truthy(dynamic_neoforge ~= nil, "NeoForge should allow Kotlin and dynamic version resolution")
	assert_equal(dynamic_neoforge_error, nil, "dynamic NeoForge validation should not fail")
	local old_neoforge, old_neoforge_error = project.validate(vim.tbl_extend("force", neoforge, { minecraft_version = "1.20.4" }))
	assert_equal(old_neoforge, nil, "NeoForge should reject Minecraft versions before 1.20.5")
	assert_equal(old_neoforge_error, { code = "unsupported_version", field = "minecraft_version" }, "old NeoForge versions should fail structurally")
	local future_neoforge, future_neoforge_error = project.validate(vim.tbl_extend("force", neoforge, { minecraft_version = "1.21.5" }))
	assert_equal(future_neoforge, nil, "NeoForge should reject versions outside the validated template range")
	assert_equal(future_neoforge_error, { code = "unsupported_version", field = "minecraft_version" }, "future NeoForge versions should fail structurally")
end

local function test_project_generation_results()
	local function spec(directory)
		return {
			platform = "paper",
			build_system = "gradle",
			minecraft_version = "1.21.8",
			directory = directory,
			group_id = "com.example",
			artifact_id = "result-test",
			package_name = "com.example.result",
			main_class = "ResultTest",
			language = "java",
		}
	end

	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function()
		local result = { status = "failed", error = { code = "gradle_wrapper_failed" } }
		return { status = "failed", result = result, on_complete = function(callback) callback(result) end }
	end
	local failed_directory = vim.fn.tempname()
	vim.fn.mkdir(failed_directory, "p")
	local callback_count = 0
	local failed = project.generate(spec(failed_directory), function(result)
		callback_count = callback_count + 1
		assert_equal(result.status, "failed", "public callback should receive the final failure")
	end)
	assert_equal(failed.status, "failed", "wrapper failure should fail project generation")
	assert_equal(failed.result.error.code, "gradle_wrapper_failed", "wrapper failure should preserve its error code")
	assert_equal(vim.fn.filereadable(failed_directory .. "/build.gradle.kts"), 0, "failed generation should not pollute the destination")
	vim.wait(1000, function() return callback_count == 1 end, 10)
	assert_equal(callback_count, 1, "public callback should run exactly once")

	local child = { status = "pending", callbacks = {} }
	function child.on_complete(callback) table.insert(child.callbacks, callback) end
	function child.cancel() child.cancelled = true end
	gradle.generate_gradlew = function() return child end
	local cancelled_directory = vim.fn.tempname()
	vim.fn.mkdir(cancelled_directory, "p")
	local cancelled = project.generate(spec(cancelled_directory))
	assert_equal(cancelled.status, "pending", "incomplete wrapper generation should remain pending")
	cancelled.cancel()
	assert_equal(cancelled.status, "pending", "cancel should wait for the child process to exit")
	assert_equal(child.cancelled, true, "project cancellation should cancel the active child operation")
	for _, completion_callback in ipairs(child.callbacks) do completion_callback({ status = "cancelled" }) end
	assert_equal(cancelled.status, "cancelled", "child exit should complete cancellation")
	assert_equal(vim.fn.filereadable(cancelled_directory .. "/build.gradle.kts"), 0, "cancelled generation should not pollute the destination")

	local changed_child = { status = "pending", callbacks = {} }
	function changed_child.on_complete(callback) table.insert(changed_child.callbacks, callback) end
	function changed_child.cancel() end
	gradle.generate_gradlew = function() return changed_child end
	local changed_directory = vim.fn.tempname()
	vim.fn.mkdir(changed_directory, "p")
	local changed = project.generate(spec(changed_directory))
	local competing = project.generate(spec(changed_directory))
	assert_equal(competing.status, "failed", "concurrent generation should fail while the destination lock is held")
	assert_equal(competing.result.error.code, "generation_in_progress", "concurrent generation should return a lock error")
	vim.fn.writefile({ "keep" }, changed_directory .. "/concurrent.txt")
	for _, completion_callback in ipairs(changed_child.callbacks) do completion_callback({ status = "generated" }) end
	assert_equal(changed.status, "failed", "destination changes during generation should fail commit")
	assert_equal(changed.result.error.code, "destination_changed", "destination changes should return a structured error")
	assert_equal(read_file(changed_directory .. "/concurrent.txt"), "keep", "destination changes should never be overwritten")
	local replacement_child = { callbacks = {} }
	function replacement_child.on_complete(completion_callback) table.insert(replacement_child.callbacks, completion_callback) end
	function replacement_child.cancel() end
	gradle.generate_gradlew = function() return replacement_child end
	local replaced_directory = vim.fn.tempname()
	local replacement_target = vim.fn.tempname()
	vim.fn.mkdir(replaced_directory, "p")
	vim.fn.mkdir(replacement_target, "p")
	local replaced = project.generate(spec(replaced_directory))
	vim.fn.delete(replaced_directory, "d")
	assert_truthy(vim.uv.fs_symlink(replacement_target, replaced_directory) ~= nil, "runtime symlink replacement should be created")
	for _, completion_callback in ipairs(replacement_child.callbacks) do completion_callback({ status = "generated" }) end
	assert_equal(replaced.status, "failed", "runtime symlink replacement should fail commit")
	assert_equal(replaced.result.error.code, "destination_changed", "runtime symlink replacement should remain structured")
	assert_equal(vim.uv.fs_lstat(replaced_directory).type, "link", "runtime symlink replacement should be preserved")

	local occupied_directory = vim.fn.tempname()
	vim.fn.mkdir(occupied_directory, "p")
	vim.fn.writefile({ "keep" }, occupied_directory .. "/existing.txt")
	local occupied = project.generate(spec(occupied_directory))
	assert_equal(occupied.status, "failed", "non-empty destinations should be rejected")
	assert_equal(occupied.result.error.code, "destination_not_empty", "occupied destinations should return a structured error")
	assert_equal(read_file(occupied_directory .. "/existing.txt"), "keep", "destination rejection should preserve existing files")

	local unsupported_spec = spec(vim.fn.tempname())
	unsupported_spec.platform = "fabric"
	unsupported_spec.minecraft_version = "1.12.2"
	local unsupported = project.generate(unsupported_spec)
	assert_equal(unsupported.status, "failed", "unsupported Fabric versions should fail generation")
	assert_equal(unsupported.result.error.code, "unsupported_version", "unsupported Fabric versions should return a structured error")

	local real_destination = vim.fn.tempname()
	local linked_destination = vim.fn.tempname()
	vim.fn.mkdir(real_destination, "p")
	assert_truthy(vim.uv.fs_symlink(real_destination, linked_destination) ~= nil, "symlink fixture should be created")
	local linked = project.generate(spec(linked_destination))
	assert_equal(linked.status, "failed", "symlink destinations should be rejected")
	assert_equal(linked.result.error.code, "destination_symlink", "symlink destinations should return a structured error")
	assert_equal(vim.uv.fs_lstat(linked_destination).type, "link", "destination rejection should preserve the symlink")
	local alias_child = { callbacks = {} }
	function alias_child.on_complete(completion_callback) table.insert(alias_child.callbacks, completion_callback) end
	function alias_child.cancel() alias_child.cancelled = true end
	gradle.generate_gradlew = function() return alias_child end
	local real_parent = vim.fn.tempname()
	local alias_parent = vim.fn.tempname()
	vim.fn.mkdir(real_parent, "p")
	assert_truthy(vim.uv.fs_symlink(real_parent, alias_parent) ~= nil, "parent alias fixture should be created")
	local aliased = project.generate(spec(alias_parent .. "/project"))
	local canonical = project.generate(spec(real_parent .. "/project"))
	assert_equal(canonical.status, "failed", "parent aliases should share one destination lock")
	assert_equal(canonical.result.error.code, "generation_in_progress", "alias lock conflicts should remain structured")
	aliased.cancel()
	for _, completion_callback in ipairs(alias_child.callbacks) do completion_callback({ status = "cancelled" }) end
	assert_equal(aliased.status, "cancelled", "aliased generation should cancel cleanly")

	local original_resolve = fabric_version_data.resolve
	local fetch_child = { callbacks = {} }
	function fetch_child.on_complete(completion_callback) table.insert(fetch_child.callbacks, completion_callback) end
	function fetch_child.cancel() fetch_child.cancelled = true end
	fabric_version_data.resolve = function() return fetch_child end
	local fabric_directory = vim.fn.tempname()
	vim.fn.mkdir(fabric_directory, "p")
	local fabric_spec = spec(fabric_directory)
	fabric_spec.platform = "fabric"
	fabric_spec.minecraft_version = "1.21.1"
	local fabric_callback_count = 0
	local fabric_cancelled = project.generate(fabric_spec, function(result)
		fabric_callback_count = fabric_callback_count + 1
		assert_equal(result.status, "cancelled", "Fabric callback should receive cancellation")
	end)
	fabric_cancelled.cancel()
	assert_equal(fabric_cancelled.status, "pending", "Fabric cancellation should wait for network processes")
	assert_equal(fetch_child.cancelled, true, "Fabric cancellation should cancel version resolution")
	for _, completion_callback in ipairs(fetch_child.callbacks) do completion_callback({ status = "cancelled" }) end
	vim.wait(1000, function() return fabric_cancelled.status == "cancelled" and fabric_callback_count == 1 end, 10)
	assert_equal(fabric_cancelled.status, "cancelled", "Fabric cancellation should settle after network exit")
	assert_equal(vim.uv.fs_lstat(fabric_directory .. ".minecraft-dev.lock"), nil, "Fabric cancellation should release its destination lock")
	fabric_version_data.resolve = original_resolve
	local stale_lock_path = vim.fn.tempname() .. ".lock"
	vim.fn.mkdir(stale_lock_path, "p")
	vim.fn.writefile({ "99999999" }, stale_lock_path .. "/pid")
	local recovered_lock, stale_lock_error = require("minecraft-dev.util.lock").acquire(stale_lock_path)
	assert_equal(recovered_lock, nil, "stale generation locks should require explicit cleanup")
	assert_equal(stale_lock_error.code, "stale_generation_lock", "stale locks should return an actionable structured error")
	vim.fn.delete(stale_lock_path, "rf")

	gradle.generate_gradlew = original_generate_gradlew
	vim.fn.delete(failed_directory, "rf")
	vim.fn.delete(cancelled_directory, "rf")
	vim.fn.delete(changed_directory, "rf")
	vim.fn.delete(replaced_directory)
	vim.fn.delete(replacement_target, "rf")
	vim.fn.delete(occupied_directory, "rf")
	vim.fn.delete(linked_destination)
	vim.fn.delete(real_destination, "rf")
	vim.fn.delete(alias_parent)
	vim.fn.delete(real_parent, "rf")
	vim.fn.delete(fabric_directory, "rf")
end

local function test_noninteractive_paper_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local original_input = vim.fn.input
	vim.fn.input = function()
		error("non-interactive generation must not request input")
	end

	local ok, err = generate_project({
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
	gradle.generate_gradlew = function() return true end

	local ok, err = generate_project({
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
		fabric_version_data = {
			loader = "0.18.4",
			fabric_api = "0.141.3+1.21.11",
			yarn = nil,
		},
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

local function test_noninteractive_fabric_kotlin_generation()
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local gradle = require("minecraft-dev.util.gradle")
	local original_generate_gradlew = gradle.generate_gradlew
	local original_input = vim.fn.input
	gradle.generate_gradlew = function() return true end
	vim.fn.input = function() error("non-interactive Fabric Kotlin generation must not request input") end

	local generation_spec = {
		platform = "fabric",
		build_system = "gradle",
		minecraft_version = "1.21.1",
		directory = directory,
		group_id = "com.example",
		artifact_id = "example",
		package_name = "com.example.example",
		main_class = "ExampleMod",
		language = "kotlin",
		side = "both",
		generate_datagen = true,
		use_mixins = true,
		fabric_version_data = {
			loader = "0.16.14",
			fabric_api = "0.116.0+1.21.1",
			kotlin_loader = "1.13.13+kotlin.2.4.10",
			loom_version = "1.10-SNAPSHOT",
			gradle_version = "8.12.1",
		},
	}
	local invalid, invalid_err = generate_project(vim.tbl_deep_extend("force", {}, generation_spec, {
		fabric_version_data = { kotlin_loader = "garbage+1.13.13+kotlin.2.4.10" },
	}))
	assert_equal(invalid, nil, "invalid Fabric Language Kotlin versions should be rejected")
	assert_equal(invalid_err.code, "invalid_version", "invalid Fabric Language Kotlin versions should return a structured error")
	local ok, err = generate_project(generation_spec)

	assert_equal(ok, true, "public API should generate a Fabric Kotlin project")
	assert_equal(err, nil, "successful Fabric Kotlin generation should not return an error")
	assert_equal(vim.fn.filereadable(directory .. "/build.gradle.kts"), 1, "Fabric Kotlin should use Kotlin Gradle DSL")
	assert_equal(vim.fn.filereadable(directory .. "/settings.gradle.kts"), 1, "Fabric Kotlin should use Kotlin settings DSL")
	local build = read_file(directory .. "/build.gradle.kts")
	assert_truthy(build:find('kotlin("jvm") version "2.4.10"', 1, true) ~= nil, "Fabric Kotlin should use the Kotlin version bundled by Fabric Language Kotlin")
	assert_truthy(build:find("fabric-language-kotlin:1.13.13+kotlin.2.4.10", 1, true) ~= nil, "Fabric Kotlin should depend on Fabric Language Kotlin")
	assert_truthy(build:find('val minecraftVersion = project.property("minecraft_version") as String', 1, true) ~= nil, "Fabric Kotlin resource expansion should use typed properties")
	local mod_json = vim.json.decode(read_file(directory .. "/src/main/resources/fabric.mod.json"))
	assert_equal(mod_json.entrypoints.main[1].adapter, "kotlin", "Fabric Kotlin main entrypoint should use the Kotlin adapter")
	assert_equal(mod_json.entrypoints.client[1].value, "com.example.example.client.ExampleModClient", "Fabric Kotlin client entrypoint should match its package")
	assert_equal(mod_json.depends["fabric-language-kotlin"], ">=1.13.13+kotlin.2.4.10", "Fabric Kotlin metadata should require Fabric Language Kotlin")
	local mixin = read_file(directory .. "/src/main/kotlin/com/example/example/mixin/ExampleModMixin.kt")
	assert_truthy(mixin:find("`minecraftDev$exampleInjection`", 1, true) ~= nil, "Fabric Kotlin mixin should escape its JVM method name")
	vim.fn.delete(directory, "rf")

	local client_directory = vim.fn.tempname()
	vim.fn.mkdir(client_directory, "p")
	generation_spec.directory = client_directory
	generation_spec.side = "client"
	generation_spec.client_mixins = false
	local client_ok, client_err = generate_project(generation_spec)
	assert_equal(client_ok, true, "client-only Fabric Kotlin generation should succeed")
	assert_equal(client_err, nil, "client-only Fabric Kotlin generation should not return an error")
	assert_equal(vim.fn.filereadable(client_directory .. "/src/client/kotlin/com/example/example/mixin/client/ExampleModClientMixin.kt"), 1, "client-only mixins should use a separate client package and source set")
	assert_equal(vim.fn.filereadable(client_directory .. "/src/main/kotlin/com/example/example/mixin/ExampleModMixin.kt"), 0, "client-only mixins should not use the main source set")
	vim.fn.delete(client_directory, "rf")
	gradle.generate_gradlew = original_generate_gradlew
	vim.fn.input = original_input
end

local function test_fabric_advanced_generation_options()
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() return true end
	local base = {
		platform = "fabric",
		build_system = "gradle",
		group_id = "com.example",
		artifact_id = "advanced",
		package_name = "com.example.advanced",
		main_class = "AdvancedMod",
		plugin_version = "1.0.0",
		side = "both",
		use_mixins = true,
	}

	local yarn_directory = vim.fn.tempname()
	vim.fn.mkdir(yarn_directory, "p")
	local yarn_ok, yarn_err = generate_project(vim.tbl_extend("force", vim.deepcopy(base), {
		directory = yarn_directory,
		minecraft_version = "1.21.1",
		language = "java",
		use_official_mappings = false,
		yarn_version = "1.21.1+build.3",
		use_fabric_api = false,
		split_sources = false,
		client_mixins = true,
		generate_datagen = true,
		fabric_version_data = {
			loader = "0.16.14",
			fabric_api = "0.116.15+1.21.1",
			yarn = nil,
			loom_version = "1.10.5",
			gradle_version = "8.12.1",
		},
	}))
	assert_equal(yarn_ok, true, "Yarn Fabric generation should succeed")
	assert_equal(yarn_err, nil, "Yarn Fabric generation should not return an error")
	local yarn_build = read_file(yarn_directory .. "/build.gradle")
	assert_truthy(yarn_build:find("net.fabricmc:yarn:${project.yarn_version}:v2", 1, true) ~= nil, "Yarn projects should declare the selected mappings")
	assert_truthy(yarn_build:find("fabric-api", 1, true) == nil, "Fabric API should be removable from native projects")
	assert_truthy(yarn_build:find("splitEnvironmentSourceSets", 1, true) == nil, "split source configuration should be optional")
	assert_truthy(yarn_build:find("configureDataGeneration", 1, true) == nil, "datagen should be disabled when Fabric API is disabled")
	assert_equal(vim.fn.filereadable(yarn_directory .. "/src/main/java/com/example/advanced/AdvancedModClient.java"), 1, "unsplit client sources should use the main source set")
	local yarn_metadata = vim.json.decode(read_file(yarn_directory .. "/src/main/resources/fabric.mod.json"))
	assert_equal(yarn_metadata.depends["fabric-api"], nil, "Fabric metadata should omit disabled Fabric API")
	assert_equal(yarn_metadata.entrypoints["fabric-datagen"], nil, "Fabric metadata should omit datagen when API is disabled")
	vim.fn.delete(yarn_directory, "rf")

	local modern_directory = vim.fn.tempname()
	vim.fn.mkdir(modern_directory, "p")
	local modern_ok, modern_err = generate_project(vim.tbl_extend("force", vim.deepcopy(base), {
		directory = modern_directory,
		minecraft_version = "26.1.2",
		language = "kotlin",
		use_official_mappings = false,
		use_fabric_api = true,
		split_sources = true,
		client_mixins = true,
		generate_datagen = true,
		fabric_version_data = {
			loader = "0.19.3",
			fabric_api = "0.155.2+26.1.2",
			yarn = nil,
			kotlin_loader = "1.13.13+kotlin.2.4.10",
			loom_version = "1.17.17",
			gradle_version = "9.6.1",
		},
	}))
	assert_equal(modern_ok, true, "26.1 Fabric generation should succeed without Yarn")
	assert_equal(modern_err, nil, "26.1 Fabric generation should not return an error")
	local modern_build = read_file(modern_directory .. "/build.gradle.kts")
	assert_truthy(modern_build:find('id("net.fabricmc.fabric-loom") version "1.17.17"', 1, true) ~= nil, "26.1 should use the renamed Loom plugin")
	assert_truthy(modern_build:find("modImplementation", 1, true) == nil, "26.1 should use implementation dependency configurations")
	assert_truthy(modern_build:find("mappings(", 1, true) == nil, "26.1 should not emit a Yarn or legacy mappings dependency")
	assert_truthy(modern_build:find("val targetJavaVersion = 25", 1, true) ~= nil, "26.1 should target Java 25")
	assert_equal(vim.fn.filereadable(modern_directory .. "/src/main/resources/advanced.mixins.json"), 1, "split projects should retain a main Mixin config")
	assert_equal(vim.fn.filereadable(modern_directory .. "/src/client/resources/advanced.client.mixins.json"), 1, "split projects should generate a client Mixin config")
	assert_equal(vim.fn.filereadable(modern_directory .. "/src/client/kotlin/com/example/advanced/mixin/client/AdvancedModClientMixin.kt"), 1, "split projects should generate a separate client Mixin source")
	assert_truthy(read_file(modern_directory .. "/src/main/kotlin/com/example/advanced/mixin/AdvancedModMixin.kt"):find("net.minecraft.world.entity.Entity", 1, true) ~= nil, "26.1 should use the effective Mojang mappings for generated Mixins")
	local modern_metadata = vim.json.decode(read_file(modern_directory .. "/src/main/resources/fabric.mod.json"))
	assert_equal(modern_metadata.depends.java, ">=25", "26.1 metadata should require Java 25")
	assert_equal(modern_metadata.mixins[2].environment, "client", "client Mixin metadata should be environment-scoped")
	vim.fn.delete(modern_directory, "rf")

	local minecraft_dev = require("minecraft-dev")
	local original_side = minecraft_dev.config.defaults.fabric.side
	minecraft_dev.config.defaults.fabric.side = "server"
	local server_directory = vim.fn.tempname()
	vim.fn.mkdir(server_directory, "p")
	local server_spec = vim.tbl_extend("force", vim.deepcopy(base), {
		directory = server_directory,
		minecraft_version = "1.21.1",
		language = "java",
		use_fabric_api = false,
		fabric_version_data = {
			loader = "0.16.14",
			loom_version = "1.10.5",
			gradle_version = "8.12.1",
		},
	})
	server_spec.side = nil
	local server_ok, server_err = generate_project(server_spec)
	minecraft_dev.config.defaults.fabric.side = original_side
	assert_equal(server_ok, true, "configured server-side Fabric defaults should generate")
	assert_equal(server_err, nil, "configured server-side Fabric defaults should not fail")
	assert_equal(vim.fn.isdirectory(server_directory .. "/src/client"), 0, "server-side defaults should not derive client sources or Mixins")
	vim.fn.delete(server_directory, "rf")
	gradle.generate_gradlew = original_generate_gradlew
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
			fabric = { cache_ttl = -1 },
		},
	})

	assert_equal(normalized.defaults.paper.version, "1.20.6", "nested defaults should override cleanly")
	assert_equal(normalized.defaults.paper.language, "java", "paper language default should stay intact")
	assert_equal(normalized.defaults.fabric.language, "java", "unrelated defaults should stay intact")
	assert_equal(normalized.defaults.fabric.cache_ttl, config.default_config.defaults.fabric.cache_ttl, "invalid Fabric cache TTLs should restore the configured default")
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
	assert_truthy(mod_json:match('com%.example%.demo%.MainClient') ~= nil, "Java client entrypoint should match generated package")
	assert_truthy(mod_json:match('com%.example%.demo%.client%.MainClient') == nil, "Java client entrypoint should not add a Kotlin-only package")
	assert_truthy(mod_json:match('"main"') == nil, "client mode should omit main entrypoint")
	assert_truthy(mod_json:match('"fabric%-datagen"') == nil, "client mode should omit datagen when disabled")
end

local function test_paper_kotlin_templates()
	local gradle_template = paper_templates.read("gradle", "v1_13_plus/build.gradle.kts", "kotlin")
	local legacy_gradle_template = paper_templates.read("gradle", "1.13-/build.gradle", "kotlin")
	local maven_template = paper_templates.read("maven", "v1_13_plus/pom.xml", "kotlin")
	local main_template = paper_templates.read("gradle", "Main.kt", "kotlin")

	assert_truthy(gradle_template:match('kotlin%("jvm"%)') ~= nil, "gradle kotlin template should apply Kotlin plugin")
	assert_truthy(legacy_gradle_template:match("org%.jetbrains%.kotlin%.jvm") ~= nil, "legacy Gradle Kotlin template should apply Kotlin plugin")
	assert_truthy(maven_template:match("kotlin%-maven%-plugin") ~= nil, "maven kotlin template should apply Kotlin plugin")
	assert_truthy(main_template:match("class %%s : JavaPlugin%(%)") ~= nil, "kotlin main template should extend JavaPlugin")
end

local function test_paper_gradle_project_version()
	local original_generate_gradlew = gradle.generate_gradlew
	gradle.generate_gradlew = function() return true end
	local cases = {
		{ minecraft_version = "1.12.2", language = "java", build_file = "build.gradle" },
		{ minecraft_version = "1.12.2", language = "kotlin", build_file = "build.gradle" },
		{ minecraft_version = "1.21.8", language = "java", build_file = "build.gradle.kts" },
		{ minecraft_version = "1.21.8", language = "kotlin", build_file = "build.gradle.kts" },
	}
	for _, case in ipairs(cases) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
			platform = "paper",
			build_system = "gradle",
			minecraft_version = case.minecraft_version,
			directory = directory,
			group_id = "com.example",
			artifact_id = "paper-version-test",
			package_name = "com.example.paper",
			main_class = "PaperVersionTest",
			language = case.language,
			plugin_version = "2.3.4",
		})
		assert_equal(ok, true, "Paper Gradle generation should succeed")
		assert_equal(err, nil, "Paper Gradle generation should not return an error")
		local build = read_file(directory .. "/" .. case.build_file)
		assert_truthy(build:find('group = "com.example"', 1, true) ~= nil, "Paper Gradle group should use group_id")
		assert_truthy(build:find('version = "2.3.4"', 1, true) ~= nil, "Paper Gradle version should use plugin_version")
		assert_truthy(build:find(case.minecraft_version .. "-R0.1-SNAPSHOT", 1, true) ~= nil, "Paper API dependency should use minecraft_version")
		assert_truthy(read_file(directory .. "/settings.gradle"):find('rootProject.name = "paper-version-test"', 1, true) ~= nil, "Paper Gradle archive name should use artifact_id")
		vim.fn.delete(directory, "rf")
	end

	local default_directory = vim.fn.tempname()
	vim.fn.mkdir(default_directory, "p")
	generate_project({
		platform = "paper",
		build_system = "gradle",
		minecraft_version = "1.21.8",
		directory = default_directory,
		group_id = "com.example",
		artifact_id = "paper-version-default",
		package_name = "com.example.paper",
		main_class = "PaperVersionDefault",
		language = "java",
	})
	assert_truthy(read_file(default_directory .. "/build.gradle.kts"):find('version = "1.0.0"', 1, true) ~= nil, "Paper Gradle version should default to 1.0.0")
	vim.fn.delete(default_directory, "rf")
	gradle.generate_gradlew = original_generate_gradlew
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
	assert_equal(metadata.mixin_target_class(ctx, { side = "client" }), "net.minecraft.client.Minecraft", "client mixin should use Mojmap class names")
	assert_equal(metadata.mixin_target_class(ctx, { side = "server" }), "net.minecraft.server.MinecraftServer", "server mixin should use Mojmap class names")
	assert_equal(metadata.mixin_target_class(ctx, { side = "both" }), "net.minecraft.world.entity.Entity", "common mixin should use Mojmap class names")
	assert_equal(metadata.main_class_name(ctx, { language = "java" }), "Main", "java main class should stay capitalized")
	assert_equal(metadata.client_class_name(ctx, { language = "java" }), "MainClient", "java client class should derive from main class")
end

local function test_translation_json_sorting()
	local translations = require("minecraft-dev.translations")
	local normalized = config.normalize({ defaults = { translations = { order = "unknown", default_locale = "../en_us", indent = "\n", template_path = false } } })
	assert_equal(normalized.defaults.translations.order, "ascending", "invalid default sort order should normalize")
	assert_equal(normalized.defaults.translations.default_locale, "en_us", "empty default locale should normalize")
	assert_equal(normalized.defaults.translations.indent, "  ", "multiline indentation should normalize")
	assert_equal(normalized.defaults.translations.template_path, nil, "invalid template path should normalize")
	assert_equal(
		config.normalize({ defaults = { translations = false } }).defaults.translations,
		config.default_config.defaults.translations,
		"non-table translation defaults should normalize"
	)
	local content = '{\n\t"item.demo.z": "Zed",\n\t"block.demo.a": "A\\nline",\n\t"item.demo.a": "Quoted \\\"value\\\""\n}\n'

	local ascending, ascending_error = translations.sort_content(content, { order = "ascending" })
	assert_equal(ascending_error, nil, "valid translation JSON should sort without an error")
	assert_equal(
		ascending,
		'{\n\t"block.demo.a": "A\\nline",\n\t"item.demo.a": "Quoted \\\"value\\\"",\n\t"item.demo.z": "Zed"\n}\n',
		"ascending translation sorting should preserve indentation, escaping, and trailing newline"
	)

	local descending = assert(translations.sort_content(content, { order = "descending" }))
	assert_equal(
		descending,
		'{\n\t"item.demo.z": "Zed",\n\t"item.demo.a": "Quoted \\\"value\\\"",\n\t"block.demo.a": "A\\nline"\n}\n',
		"descending translation sorting should reverse dotted-key order"
	)

	local like_default = assert(translations.sort_content(content, {
		order = "like-default",
		default_content = '{ "item.demo.a": "A", "block.demo.a": "B" }',
	}))
	assert_equal(
		like_default,
		'{\n\t"item.demo.a": "Quoted \\\"value\\\"",\n\t"block.demo.a": "A\\nline",\n\t"item.demo.z": "Zed"\n}\n',
		"default-locale sorting should follow known keys and append unknown keys ascending"
	)

	assert_equal(assert(translations.sort_content("{}", { order = "ascending" })), "{}", "empty objects should remain valid JSON")
	assert_equal(select(2, translations.sort_content("[]", { order = "ascending" })).code, "invalid_root", "arrays should be rejected")
	assert_equal(select(2, translations.sort_content('{"key": 1}', { order = "ascending" })).code, "invalid_value", "non-string translation values should be rejected")
	assert_equal(select(2, translations.sort_content("{", { order = "ascending" })).code, "invalid_json", "malformed JSON should be structured")
	assert_equal(select(2, translations.sort_content('{"key": "A", "key": "B"}', { order = "ascending" })).code, "duplicate_key", "duplicate keys should be rejected without data loss")
	assert_equal(select(2, translations.sort_content("{}", { order = "unknown" })).code, "invalid_order", "unknown ordering should be rejected")
	assert_equal(select(2, translations.sort_content("{}", { order = "like-default" })).code, "missing_default", "like-default should require a default locale")
end

local function test_translation_lang_and_template_sorting()
	local translations = require("minecraft-dev.translations")
	local content = "# Zed\nitem.demo.z=Zed\n\n# Alpha\nitem.demo.a=Alpha\n"
	assert_equal(
		assert(translations.sort_content(content, { format = "lang", order = "ascending" })),
		"# Alpha\nitem.demo.a=Alpha\n\n# Zed\nitem.demo.z=Zed\n",
		"legacy lang sorting should move attached comments and preserve blank separators"
	)
	assert_equal(
		assert(translations.sort_content(content, { format = "lang", order = "like-default", default_content = "item.demo.z=Z\nitem.demo.a=A\n" })),
		content,
		"legacy lang files should follow a legacy default locale"
	)

	local templated = assert(translations.sort_content(
		"item.demo.z=Z\nblock.demo.a=A\nmisc.demo.x=X\nitem.demo.a=A\n",
		{ format = "lang", order = "template", template_content = "block.!+.a\n\n# Items\nitem.*" }
	))
	assert_equal(
		templated,
		"block.demo.a=A\n\n# Items\nitem.demo.a=A\nitem.demo.z=Z\nmisc.demo.x=X\n",
		"project template sorting should apply quantifiers, layout, and ascending fallback"
	)
	assert_equal(
		assert(translations.sort_content('{"item.z":"Z","block.a":"A","item.a":"A"}', {
			order = "template",
			template_content = "block.*\n\nitem.*",
		})),
		'{\n  "block.a": "A",\n\n  "item.a": "A",\n  "item.z": "Z"\n}',
		"JSON template sorting should preserve template group spacing"
	)
	assert_equal(
		assert(translations.sort_content('{"z":"Z","a":"A"}', { order = "template", template_content = "" })),
		'{\n  "a": "A",\n  "z": "Z"\n}',
		"an empty project template should fall back to ascending without adding layout"
	)

	assert_equal(select(2, translations.sort_content("key=value\nkey=again", { format = "lang" })).code, "duplicate_key", "legacy duplicate keys should be rejected")
	assert_equal(select(2, translations.sort_content(" =value", { format = "lang" })).code, "empty_key", "blank legacy keys should be rejected")
	assert_equal(select(2, translations.sort_content("not-an-entry", { format = "lang" })).code, "invalid_lang", "unknown legacy syntax should fail safely")
	assert_equal(select(2, translations.sort_content("key=value", { format = "lang", order = "template" })).code, "missing_template", "template ordering should require template content")
end

local function test_translation_buffer_and_command()
	local minecraft_dev = require("minecraft-dev")
	local translation_root = vim.fn.tempname()
	local translation_directory = translation_root .. "/src/main/resources/assets/demo/lang"
	vim.fn.mkdir(translation_directory, "p")
	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buffer, translation_directory .. "/fr_fr.json")
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "{", '  "item.demo.z": "Z",', '  "item.demo.a": "A"', "}" })
	vim.bo[buffer].filetype = "json"
	vim.bo[buffer].eol = true

	local result = minecraft_dev.sort_translations({ buffer = buffer, order = "ascending" })
	assert_equal(result.status, "sorted", "public API should sort a Minecraft translation buffer")
	assert_equal(
		vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
		{ "{", '  "item.demo.a": "A",', '  "item.demo.z": "Z"', "}" },
		"buffer sorting should replace the current translation content"
	)
	assert_truthy(vim.bo[buffer].eol, "buffer sorting should preserve end-of-line state")
	vim.fn.writefile({ "{", '  "item.demo.z": "Z",', '  "item.demo.a": "A"', "}" }, translation_directory .. "/en_us.json")
	local default_result = minecraft_dev.sort_translations({ buffer = buffer, order = "like-default" })
	assert_equal(default_result.status, "sorted", "public API should read the sibling default locale")
	assert_equal(
		vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
		{ "{", '  "item.demo.z": "Z",', '  "item.demo.a": "A"', "}" },
		"like-default buffer sorting should follow the sibling en_us order"
	)
	vim.fn.delete(translation_directory .. "/en_us.json")
	assert_equal(
		minecraft_dev.sort_translations({ buffer = buffer, order = "like-default" }).error.code,
		"missing_default",
		"missing sibling default locale should return a structured error"
	)

	local lang_buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(lang_buffer, translation_directory .. "/fr_fr.lang")
	vim.api.nvim_buf_set_lines(lang_buffer, 0, -1, false, { "item.demo.z=Z", "item.demo.a=A" })
	vim.bo[lang_buffer].eol = true
	vim.fn.writefile({ "item.demo.z=Z", "item.demo.a=A" }, translation_directory .. "/en_us.lang")
	assert_equal(
		minecraft_dev.sort_translations({ buffer = lang_buffer, order = "ascending" }).status,
		"sorted",
		"public API should sort legacy Minecraft translation buffers"
	)
	assert_equal(
		vim.api.nvim_buf_get_lines(lang_buffer, 0, -1, false),
		{ "item.demo.a=A", "item.demo.z=Z" },
		"legacy buffer sorting should replace content without converting its format"
	)
	local template_path = translation_root .. "/minecraft_localization_template.lang"
	vim.fn.writefile({ "item.demo.z", "item.demo.a" }, template_path)
	assert_equal(
		minecraft_dev.sort_translations({ buffer = lang_buffer, order = "template", template_path = template_path }).status,
		"sorted",
		"public API should load a project sorting template"
	)
	assert_equal(
		vim.api.nvim_buf_get_lines(lang_buffer, 0, -1, false),
		{ "item.demo.z=Z", "item.demo.a=A" },
		"buffer template sorting should follow the configured project template"
	)

	local ordinary = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(ordinary, vim.fn.tempname() .. "/settings.json")
	vim.api.nvim_buf_set_lines(ordinary, 0, -1, false, { "{}" })
	assert_equal(
		minecraft_dev.sort_translations({ buffer = ordinary }).error.code,
		"not_translation_file",
		"public API should reject JSON outside a Minecraft lang directory"
	)

	assert_truthy(vim.fn.exists(":MinecraftDevSortTranslations") == 2, "setup should register the translation sorting command")
	assert_equal(
		vim.fn.getcompletion("MinecraftDevSortTranslations d", "cmdline"),
		{ "descending" },
		"translation command completion should expose supported ordering modes"
	)
	assert_equal(vim.fn.getcompletion("MinecraftDevSortTranslations t", "cmdline"), { "template" }, "command completion should expose template ordering")
	local original_notify = vim.notify
	local command_error
	vim.notify = function(message, level)
		if level == vim.log.levels.ERROR then command_error = message end
	end
	vim.api.nvim_set_current_buf(ordinary)
	vim.cmd("MinecraftDevSortTranslations")
	vim.notify = original_notify
	assert_truthy(
		type(command_error) == "string" and command_error:find("not a Minecraft translation", 1, true) ~= nil,
		"translation command should report a localized error for ordinary JSON"
	)
	vim.api.nvim_set_current_buf(buffer)
	vim.cmd("MinecraftDevSortTranslations descending")
	assert_equal(
		vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
		{ "{", '  "item.demo.z": "Z",', '  "item.demo.a": "A"', "}" },
		"translation command should apply the selected ordering to the current buffer"
	)

	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.api.nvim_buf_delete(lang_buffer, { force = true })
	vim.api.nvim_buf_delete(ordinary, { force = true })
	vim.fn.delete(translation_root, "rf")
end

local function test_translation_file_diagnostics()
	local minecraft_dev = require("minecraft-dev")
	local normalized = config.normalize({ defaults = { translations = { diagnostics = "yes" } } })
	assert_equal(normalized.defaults.translations.diagnostics, true, "invalid translation diagnostic config should normalize")

	local translation_root = vim.fn.tempname()
	local translation_directory = translation_root .. "/src/main/resources/assets/demo/lang"
	vim.fn.mkdir(translation_directory, "p")
	vim.fn.writefile({ "dup=Default", " bad=Bad %s", "missing=Missing %s" }, translation_directory .. "/en_us.lang")
	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buffer, translation_directory .. "/fr_fr.lang")
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
		"dup=First",
		"dup=Second",
		" bad=Bad %d",
		"extra=Extra",
		"broken",
	})
	local result = minecraft_dev.diagnose_translations({ buffer = buffer })
	assert_equal(result.status, "diagnosed", "public API should diagnose a legacy translation buffer")
	local by_code = {}
	for _, diagnostic in ipairs(result.diagnostics) do by_code[diagnostic.code] = diagnostic end
	assert_equal(by_code.duplicate_key.lnum, 1, "duplicate diagnostics should point at the later entry")
	assert_equal(by_code.whitespace_key.lnum, 2, "whitespace diagnostics should point at the key")
	assert_equal(by_code.invalid_lang.lnum, 4, "incomplete legacy entries should be errors at their line")
	assert_equal(by_code.missing_default_key.lnum, 3, "locale-only keys should be compared with the sibling default locale")
	assert_equal(by_code.format_mismatch.lnum, 2, "format signatures should match the default locale")

	local namespace = require("minecraft-dev.translation_diagnostics").namespace()
	assert_equal(#vim.diagnostic.get(buffer, { namespace = namespace }), #result.diagnostics, "diagnostics should be published in an isolated namespace")

	vim.fn.writefile({ "{", '  "same": "Value %s"', "}" }, translation_directory .. "/en_us.json")
	local json_buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(json_buffer, translation_directory .. "/de_de.json")
	vim.api.nvim_buf_set_lines(json_buffer, 0, -1, false, {
		"{",
		'  "same" : "Value %d",',
		'  "extra": "Extra",',
		'  "same": "Again %s"',
		"}",
	})
	local json_result = minecraft_dev.diagnose_translations({ buffer = json_buffer })
	local json_by_code = {}
	for _, diagnostic in ipairs(json_result.diagnostics) do json_by_code[diagnostic.code] = diagnostic end
	assert_equal(json_by_code.duplicate_key.lnum, 3, "JSON duplicate diagnostics should use the second property position")
	assert_equal(json_by_code.missing_default_key.lnum, 2, "JSON locale-only keys should point at their property")
	assert_equal(json_by_code.format_mismatch.lnum, 1, "JSON format mismatches should use the property position")
	assert_equal(
		require("minecraft-dev.translations").inspect_content('{"key": 2}', "json").issues[1].code,
		"invalid_value",
		"JSON inspection should reject non-string translation values"
	)

	minecraft_dev.setup()
	local first_autocmd_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevTranslations" })
	minecraft_dev.setup()
	assert_equal(#vim.api.nvim_get_autocmds({ group = "MinecraftDevTranslations" }), first_autocmd_count, "repeated setup should not duplicate translation autocmds")

	local ordinary = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(ordinary, translation_root .. "/notes.txt")
	vim.diagnostic.set(namespace, ordinary, { { lnum = 0, col = 0, message = "stale" } })
	assert_equal(minecraft_dev.diagnose_translations({ buffer = ordinary }).status, "skipped", "ordinary buffers should be skipped")
	assert_equal(#vim.diagnostic.get(ordinary, { namespace = namespace }), 0, "skipped buffers should clear only plugin diagnostics")

	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.api.nvim_buf_delete(json_buffer, { force = true })
	vim.api.nvim_buf_delete(ordinary, { force = true })
	vim.fn.delete(translation_root, "rf")
end

local function test_translation_index_navigation_and_completion()
	local minecraft_dev = require("minecraft-dev")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/.git", "p")
	local demo_lang = root .. "/src/main/resources/assets/demo/lang"
	local other_lang = root .. "/src/main/resources/assets/other/lang"
	local broken_lang = root .. "/src/main/resources/assets/broken/lang"
	vim.fn.mkdir(demo_lang, "p")
	vim.fn.mkdir(other_lang, "p")
	vim.fn.mkdir(broken_lang, "p")
	vim.fn.writefile({ "item.demo.z=Zed", "item.demo.a=Alpha" }, demo_lang .. "/en_us.lang")
	vim.fn.writefile({ '{"item.other.a":"Other"}' }, other_lang .. "/en_us.json")
	vim.fn.writefile({ "{" }, broken_lang .. "/en_us.json")

	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buffer, demo_lang .. "/fr_fr.lang")
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "item.demo.a=Un alpha" })
	local indexed = minecraft_dev.list_translation_keys({ buffer = buffer, root = root, prefix = "item." })
	assert_equal(indexed.status, "indexed", "public API should index default translation files")
	assert_equal(indexed.keys, { "item.demo.a", "item.demo.z", "item.other.a" }, "translation keys should be unique and dotted-key sorted")
	assert_equal(#indexed.warnings, 1, "a malformed default locale should not block valid namespaces")

	local completion = minecraft_dev.complete_translations({ buffer = buffer, root = root, prefix = "item." })
	local completion_words = {}
	for _, item in ipairs(completion.items) do table.insert(completion_words, item.word) end
	assert_equal(completion_words, { "item.demo.z", "item.other.a" }, "completion should exclude keys already present in the current locale")
	assert_truthy(completion.items[1].menu:find("en_us", 1, true) ~= nil, "completion should identify the default locale")

	local explicit = minecraft_dev.goto_translation({ buffer = buffer, root = root, key = "item.demo.z", open = false })
	assert_equal(explicit.status, "found", "explicit translation navigation should resolve a default entry")
	assert_equal(explicit.locations[1].path, demo_lang .. "/en_us.lang", "navigation should retain the source file")
	assert_equal(explicit.locations[1].lnum, 0, "navigation should retain the entry line")
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_win_set_cursor(0, { 1, 3 })
	local current = minecraft_dev.goto_translation({ buffer = buffer, root = root, open = false })
	assert_equal(current.key, "item.demo.a", "navigation should infer the key under the cursor")

	local original_omnifunc = vim.bo[buffer].omnifunc
	vim.cmd("doautocmd BufEnter")
	assert_equal(vim.bo[buffer].omnifunc, original_omnifunc, "translation completion should not replace LSP omnifunc")
	assert_equal(vim.bo[buffer].completefunc, "v:lua.MinecraftDevTranslationComplete", "translation buffers should receive an opt-in completefunc")
	assert_truthy(vim.fn.exists(":MinecraftDevGotoTranslation") == 2, "setup should register translation navigation")
	assert_equal(
		vim.fn.getcompletion("MinecraftDevGotoTranslation item.demo.z", "cmdline"),
		{ "item.demo.z" },
		"translation navigation command completion should use the project index"
	)
	minecraft_dev.setup()
	local first_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevTranslationIndex" })
	minecraft_dev.setup()
	assert_equal(#vim.api.nvim_get_autocmds({ group = "MinecraftDevTranslationIndex" }), first_count, "translation index setup should be idempotent")

	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.fn.delete(root, "rf")
end

local function test_translation_source_diagnostics_and_navigation()
	local minecraft_dev = require("minecraft-dev")
	local normalized = config.normalize({ defaults = { translations = { source_diagnostics = "yes", source_scan_max_files = 0, source_calls = false } } })
	assert_equal(normalized.defaults.translations.source_diagnostics, true, "invalid source diagnostic config should normalize")
	assert_equal(normalized.defaults.translations.source_scan_max_files, 1000, "invalid source scan limit should normalize")
	assert_equal(normalized.defaults.translations.source_calls, config.default_config.defaults.translations.source_calls, "invalid source calls should normalize")

	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/.git", "p")
	local lang = root .. "/src/main/resources/assets/demo/lang"
	local deprecated_lang = root .. "/src/main/resources/assets/minecraft/lang"
	vim.fn.mkdir(lang, "p")
	vim.fn.mkdir(deprecated_lang, "p")
	vim.fn.writefile({ "item.ok=Hello %s", "item.none=No args" }, lang .. "/en_us.lang")
	vim.fn.writefile({ "item.ok=Bonjour %s" }, lang .. "/fr_fr.lang")
	vim.fn.writefile({ "{" }, lang .. "/es_es.json")
	vim.fn.writefile({ '{"removed":["item.removed"],"renamed":{"item.old":"item.new"}}' }, deprecated_lang .. "/deprecated.json")

	local java = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(java, root .. "/src/main/java/Demo.java")
	vim.bo[java].filetype = "java"
	vim.api.nvim_buf_set_lines(java, 0, -1, false, {
		"class Demo { void test(String dynamic) {",
		'  Component.translatable("item.missing");',
		'  Component.translatable("item.ok");',
		'  Component.translatable("item.none", 1);',
		'  Component.translatable("item.removed");',
		'  Component.translatable("item.old");',
		'  I18n.format("item.ok", "ok");',
		'  String.format("item.missing");',
		"  Component.translatable(dynamic);",
		"} }",
	})
	local result = minecraft_dev.diagnose_translation_usages({ buffer = java, root = root })
	assert_equal(result.status, "diagnosed", "public API should diagnose Java translation calls")
	local by_code = {}
	for _, diagnostic in ipairs(result.diagnostics) do by_code[diagnostic.code] = diagnostic end
	assert_equal(by_code.translation_missing.lnum, 1, "missing source keys should point at the string literal")
	assert_equal(by_code.translation_format_missing.lnum, 2, "missing format arguments should be diagnosed")
	assert_equal(by_code.translation_format_superfluous.lnum, 3, "superfluous format arguments should be diagnosed")
	assert_equal(by_code.translation_deprecated_removed.lnum, 4, "removed keys should be diagnosed")
	assert_equal(by_code.translation_deprecated_renamed.lnum, 5, "renamed keys should be diagnosed")
	assert_equal(#result.references, 6, "unrelated format calls and dynamic keys should be ignored")

	local namespace = require("minecraft-dev.translation_source").namespace()
	assert_equal(#vim.diagnostic.get(java, { namespace = namespace }), #result.diagnostics, "source diagnostics should use an isolated namespace")
	vim.api.nvim_set_current_buf(java)
	vim.api.nvim_win_set_cursor(0, { 3, 30 })
	local target = minecraft_dev.goto_translation({ buffer = java, root = root, open = false })
	assert_equal(target.key, "item.ok", "source navigation should infer the translation string under the cursor")
	assert_equal(target.locations[1].path, lang .. "/en_us.lang", "source navigation should reuse the default locale index")

	local kotlin = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(kotlin, root .. "/src/main/kotlin/Demo.kt")
	vim.bo[kotlin].filetype = "kotlin"
	vim.api.nvim_buf_set_lines(kotlin, 0, -1, false, { 'fun test() { Component.translatable("item.missing") }' })
	local kotlin_result = minecraft_dev.diagnose_translation_usages({ buffer = kotlin, root = root })
	assert_equal(kotlin_result.diagnostics[1].code, "translation_missing", "Kotlin call expressions should be recognized")
	assert_equal(
		minecraft_dev.diagnose_translation_usages({ buffer = java, root = root, language = "missing-parser" }).error.code,
		"parser_unavailable",
		"missing parsers should return a structured skipped result"
	)

	local usages = minecraft_dev.find_translation_usages({ buffer = java, root = root, key = "item.ok", open = false })
	assert_equal(usages.status, "found", "public API should find translation references across file types")
	assert_equal(#usages.locations, 4, "usages should include two locales and two Java calls")
	assert_equal(usages.locations[1].kind, "source", "usage locations should be stably sorted by path and position")
	assert_equal(usages.warnings[1].code, "invalid_translation_file", "damaged locale files should be isolated as warnings")
	vim.api.nvim_set_current_buf(java)
	vim.api.nvim_win_set_cursor(0, { 3, 30 })
	local inferred = minecraft_dev.find_translation_usages({ buffer = java, root = root, open = false })
	assert_equal(inferred.key, "item.ok", "usage lookup should infer a source key under the cursor")
	local translation_buffer = vim.fn.bufadd(lang .. "/en_us.lang")
	vim.fn.bufload(translation_buffer)
	vim.api.nvim_set_current_buf(translation_buffer)
	vim.api.nvim_win_set_cursor(0, { 1, 2 })
	local translation_inferred = minecraft_dev.find_translation_usages({ buffer = translation_buffer, root = root, open = false })
	assert_equal(translation_inferred.key, "item.ok", "usage lookup should infer a translation entry under the cursor")
	vim.api.nvim_buf_set_lines(translation_buffer, -1, -1, false, { "item.unsaved=Only in buffer" })
	local unsaved = minecraft_dev.find_translation_usages({ buffer = translation_buffer, root = root, key = "item.unsaved", open = false })
	assert_equal(#unsaved.locations, 1, "usage lookup should include unsaved translation buffer entries")
	local missing_usages = minecraft_dev.find_translation_usages({ buffer = java, root = root, key = "item.unknown", open = false })
	assert_equal(missing_usages.error.code, "translation_usages_not_found", "missing usage lookup should return a structured failure")
	local limited = minecraft_dev.find_translation_usages({ buffer = java, root = root, key = "item.ok", open = false, max_files = 1 })
	assert_equal(limited.warnings[1].code, "source_scan_limit", "bounded source scans should report truncation")
	assert_truthy(vim.fn.exists(":MinecraftDevFindTranslationUsages") == 2, "setup should register translation usage lookup")
	vim.api.nvim_set_current_buf(java)
	vim.cmd("MinecraftDevFindTranslationUsages item.ok")
	assert_equal(#vim.fn.getqflist(), 4, "usage command should publish all locations to quickfix")
	vim.cmd("cclose")

	minecraft_dev.setup()
	local first_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevTranslationSource" })
	minecraft_dev.setup()
	assert_equal(#vim.api.nvim_get_autocmds({ group = "MinecraftDevTranslationSource" }), first_count, "source diagnostic setup should be idempotent")

	vim.api.nvim_buf_delete(java, { force = true })
	vim.api.nvim_buf_delete(kotlin, { force = true })
	vim.fn.delete(root, "rf")
end

local function test_bukkit_manifest_main_references()
	local minecraft_dev = require("minecraft-dev")
	local normalized = config.normalize({ defaults = { metadata = { diagnostics = "yes", source_scan_max_files = 0 } } })
	assert_equal(normalized.defaults.metadata.diagnostics, true, "invalid metadata diagnostics config should normalize")
	assert_equal(normalized.defaults.metadata.source_scan_max_files, 1000, "invalid metadata scan limit should normalize")

	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/.git", "p")
	local java = root .. "/src/main/java/test"
	local kotlin = root .. "/src/main/kotlin/test"
	local resources = root .. "/src/main/resources"
	vim.fn.mkdir(java, "p")
	vim.fn.mkdir(kotlin, "p")
	vim.fn.mkdir(resources, "p")
	vim.fn.writefile({ "package test;", "import org.bukkit.plugin.java.JavaPlugin;", "public abstract class Base extends JavaPlugin {}" }, java .. "/Base.java")
	vim.fn.writefile({ "package test;", "public final class Good extends Base {}" }, java .. "/Good.java")
	vim.fn.writefile({ "package test;", "public final class Bad {}" }, java .. "/Bad.java")
	vim.fn.writefile({ "package test;", "import org.bukkit.plugin.java.JavaPlugin;", "public abstract class AbstractPlugin extends JavaPlugin {}" }, java .. "/AbstractPlugin.java")
	vim.fn.writefile({ "package test;", "public final class Unknown extends ExternalBase {}" }, java .. "/Unknown.java")
	vim.fn.writefile({ "package test", "import org.bukkit.plugin.java.JavaPlugin", "class KGood : JavaPlugin()" }, kotlin .. "/KGood.kt")
	local manifest_path = resources .. "/plugin.yml"
	vim.fn.writefile({ "name: Demo", "main: test.Good", "version: 1.0" }, manifest_path)
	local manifest = vim.fn.bufadd(manifest_path)
	vim.fn.bufload(manifest)
	vim.bo[manifest].filetype = "yaml"

	local result = minecraft_dev.diagnose_bukkit_manifest({ buffer = manifest, root = root })
	assert_equal(result.status, "diagnosed", "plugin.yml should receive Bukkit main diagnostics")
	assert_equal(#result.diagnostics, 0, "local inheritance chains ending in JavaPlugin should be valid")
	local completion = minecraft_dev.complete_bukkit_main({ buffer = manifest, root = root })
	local words = vim.tbl_map(function(item) return item.word end, completion.items)
	assert_truthy(vim.tbl_contains(words, "test.Good"), "Java Bukkit main classes should complete")
	assert_truthy(vim.tbl_contains(words, "test.KGood"), "Kotlin Bukkit main classes should complete")
	assert_truthy(not vim.tbl_contains(words, "test.AbstractPlugin"), "abstract Bukkit classes should not complete")
	local target = minecraft_dev.goto_bukkit_main({ buffer = manifest, root = root, open = false })
	assert_equal(target.locations[1].path, java .. "/Good.java", "Bukkit main goto should resolve the class declaration")
	local truncated = minecraft_dev.diagnose_bukkit_manifest({ buffer = manifest, root = root, max_files = 1 })
	assert_equal(truncated.diagnostics[1].code, "main_resolution_incomplete", "bounded class scans should not report false unresolved errors")
	local paper_path = resources .. "/paper-plugin.yml"
	vim.fn.writefile({ "name: Demo", "version: '1.0'", "main: 'test.KGood'" }, paper_path)
	local paper = vim.fn.bufadd(paper_path)
	vim.fn.bufload(paper)
	vim.bo[paper].filetype = "yaml"
	assert_equal(#minecraft_dev.diagnose_bukkit_manifest({ buffer = paper, root = root }).diagnostics, 0, "paper-plugin.yml and quoted Kotlin main classes should be supported")

	local function diagnostic_for(main)
		vim.api.nvim_buf_set_lines(manifest, 0, -1, false, main and { "name: Demo", "main: " .. main } or { "name: Demo" })
		return minecraft_dev.diagnose_bukkit_manifest({ buffer = manifest, root = root }).diagnostics[1]
	end
	assert_equal(diagnostic_for("test.Missing").code, "main_unresolved", "missing main classes should be diagnosed")
	assert_equal(diagnostic_for("test.Bad").code, "main_wrong_type", "non-plugin main classes should be diagnosed")
	assert_equal(diagnostic_for("test.AbstractPlugin").code, "main_abstract", "abstract main classes should be diagnosed")
	assert_equal(diagnostic_for("test.Unknown").code, "main_type_unverified", "unknown external parent chains should warn without a false error")
	assert_equal(diagnostic_for(nil).code, "main_required", "missing main fields should be diagnosed")

	local unsaved = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(unsaved, java .. "/Unsaved.java")
	vim.bo[unsaved].filetype = "java"
	vim.api.nvim_buf_set_lines(unsaved, 0, -1, false, { "package test;", "import org.bukkit.plugin.java.JavaPlugin;", "public final class Unsaved extends JavaPlugin {}" })
	local unsaved_words = vim.tbl_map(function(item) return item.word end, minecraft_dev.complete_bukkit_main({ buffer = manifest, root = root }).items)
	assert_truthy(vim.tbl_contains(unsaved_words, "test.Unsaved"), "class completion should include unsaved source buffers")
	assert_equal(
		minecraft_dev.diagnose_bukkit_manifest({ buffer = manifest, root = root, language = "missing-parser" }).error.code,
		"parser_unavailable",
		"missing YAML parsers should return a structured skipped result"
	)

	vim.api.nvim_set_current_buf(manifest)
	vim.cmd("doautocmd BufEnter")
	assert_equal(vim.bo[manifest].completefunc, "v:lua.MinecraftDevBukkitMainComplete", "Bukkit manifests should receive main completion")
	assert_truthy(vim.fn.exists(":MinecraftDevGotoBukkitMain") == 2, "setup should register Bukkit main navigation")
	minecraft_dev.setup()
	local first_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevBukkitMetadata" })
	minecraft_dev.setup()
	assert_equal(#vim.api.nvim_get_autocmds({ group = "MinecraftDevBukkitMetadata" }), first_count, "metadata setup should be idempotent")

	vim.api.nvim_buf_delete(manifest, { force = true })
	vim.api.nvim_buf_delete(paper, { force = true })
	vim.api.nvim_buf_delete(unsaved, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestBukkitManifestStructureAndDependencies()
	local minecraft_dev = require("minecraft-dev")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/.git", "p")
	local java = root .. "/src/main/java/test"
	local resources = root .. "/src/main/resources"
	vim.fn.mkdir(java, "p")
	vim.fn.mkdir(resources, "p")
	vim.fn.writefile({ "package test;", "import org.bukkit.plugin.java.JavaPlugin;", "public final class Good extends JavaPlugin {}" }, java .. "/Good.java")

	local function manifest_buffer(name, lines)
		local path = resources .. "/" .. name
		vim.fn.writefile(lines, path)
		local buffer = vim.fn.bufadd(path)
		vim.fn.bufload(buffer)
		vim.bo[buffer].filetype = "yaml"
		return buffer
	end
	local plugin = manifest_buffer("plugin.yml", {
		"name: Demo",
		"name: Duplicate",
		"version: true",
		"main: test.Good",
		"api-version: latest",
		"depend: [Demo, Vault, Vault, { bad: value }]",
		"commands: []",
		"permissions: invalid",
	})
	local parsed = require("minecraft-dev.yaml_tree").parse_buffer({ buffer = plugin })
	assert_equal(parsed.status, "parsed", "YAML Tree-sitter model should parse Bukkit manifests")
	assert_equal(#parsed.document.by_key.name, 2, "YAML model should preserve duplicate mapping keys")
	local result = minecraft_dev.diagnose_bukkit_manifest({ buffer = plugin, root = root })
	local by_code = {}
	for _, item in ipairs(result.diagnostics) do by_code[item.code] = item end
	for _, code in ipairs({
		"field_duplicate",
		"field_scalar_required",
		"api_version_invalid",
		"dependency_self",
		"dependency_duplicate",
		"dependency_name_invalid",
		"field_mapping_required",
	}) do
		assert_truthy(by_code[code] ~= nil, "plugin.yml structure should diagnose " .. code)
	end

	local paper = manifest_buffer("paper-plugin.yml", {
		"name: Demo",
		"version: '1.0'",
		"main: test.Good",
		"api-version: '1.21'",
		"dependencies:",
		"  bootstrap: []",
		"  server:",
		"    Demo:",
		"      load: SIDEWAYS",
		"      required: 'yes'",
		"      join-classpath: 1",
	})
	local paper_result = minecraft_dev.diagnose_bukkit_manifest({ buffer = paper, root = root })
	local paper_codes = {}
	for _, item in ipairs(paper_result.diagnostics) do paper_codes[item.code] = item end
	for _, code in ipairs({
		"paper_dependency_phase_invalid",
		"dependency_self",
		"paper_dependency_load_invalid",
		"paper_dependency_boolean_invalid",
	}) do
		assert_truthy(paper_codes[code] ~= nil, "paper-plugin.yml dependencies should diagnose " .. code)
	end

	vim.api.nvim_buf_set_lines(paper, 0, -1, false, {
		"name: Demo",
		"version: '1.0'",
		"main: test.Good",
		"dependencies:",
		"  bootstrap:",
		"    RegistryPlugin:",
		"      load: BEFORE",
		"      required: true",
		"      join-classpath: false",
		"  server:",
		"    Vault:",
		"      load: AFTER",
		"      required: false",
	})
	assert_equal(#minecraft_dev.diagnose_bukkit_manifest({ buffer = paper, root = root }).diagnostics, 0, "valid Paper dependency phases should pass")
	vim.api.nvim_buf_set_lines(plugin, 0, -1, false, { "name: [" })
	assert_equal(minecraft_dev.diagnose_bukkit_manifest({ buffer = plugin, root = root }).error.code, "invalid_yaml", "malformed YAML should fail structurally")

	vim.api.nvim_buf_delete(plugin, { force = true })
	vim.api.nvim_buf_delete(paper, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestForgeManifestMetadata()
	local minecraft_dev = require("minecraft-dev")
	local root = vim.fn.tempname()
	local resources = root .. "/src/main/resources"
	local metadata = resources .. "/META-INF"
	local java = root .. "/src/main/java/test"
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(metadata, "p")
	vim.fn.mkdir(java, "p")
	vim.fn.writefile({
		"package test;",
		"import net.minecraftforge.fml.common.Mod;",
		'@Mod("examplemod")',
		"public final class ExampleMod {}",
	}, java .. "/ExampleMod.java")
	vim.fn.writefile({
		"package test;",
		"import net.minecraftforge.fml.common.Mod;",
		"@Mod(ConstantMod.MODID)",
		"public final class ConstantMod { public static final String MODID = \"constantmod\"; }",
	}, java .. "/ConstantMod.java")
	vim.fn.writefile({
		"package test",
		"import net.neoforged.fml.common.Mod",
		'@Mod("kotlinmod")',
		"class KotlinMod",
	}, java .. "/KotlinMod.kt")
	vim.fn.writefile({ "png" }, resources .. "/example.png")
	local path = metadata .. "/mods.toml"
	vim.fn.writefile({
		'modLoader="javafml"',
		'loaderVersion="[52,)"',
		'license="MIT"',
		"showAsResourcePack=false",
		"[[mods]]",
		'modId="examplemod"',
		'version="${file.jarVersion}"',
		'displayTest="MATCH_VERSION"',
		'logoFile="example.png"',
		"[[mods]]",
		'modId="constantmod"',
		"[[mods]]",
		'modId="kotlinmod"',
		"[[dependencies.examplemod]]",
		'modId="forge"',
		"mandatory=true",
		'versionRange="(,51],[52,)"',
		'ordering="NONE"',
		'side="BOTH"',
	}, path)
	local buffer = vim.fn.bufadd(path)
	vim.fn.bufload(buffer)
	vim.bo[buffer].filetype = "toml"
	local valid = minecraft_dev.diagnose_forge_manifest({ buffer = buffer })
	assert_equal(valid.status, "diagnosed", "mods.toml should be parsed")
	assert_equal(#valid.diagnostics, 0, "valid Forge metadata should pass")
	assert_equal(#valid.document.tables, 4, "TOML model should preserve array tables")
	assert_equal(minecraft_dev.goto_forge_mod({ buffer = buffer, mod_id = "examplemod", open = false }).status, "found", "dependency owner should resolve to a declared mod")
	assert_equal(minecraft_dev.goto_forge_mod({ buffer = buffer, mod_id = "constantmod", open = false }).status, "found", "Java constant @Mod IDs should resolve")
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_win_set_cursor(0, { 14, 16 })
	local owner_jump = minecraft_dev.goto_forge_mod({ buffer = buffer, open = false })
	assert_equal(owner_jump.target, "manifest", "dependency header navigation should target the manifest declaration")
	assert_equal(owner_jump.status, "found", "dependency header owner should resolve")

	local completion = minecraft_dev.complete_forge_manifest({
		buffer = buffer,
		prefix = "MAT",
		row = 7,
		col = #'displayTest="MAT',
		line = 'displayTest="MAT',
	})
	assert_equal(completion.items[1].word, "MATCH_VERSION", "known Forge values should complete")
	assert_truthy(completion.items[1].info:find("compatibility", 1, true) ~= nil, "completion should include field documentation")
	local mod_completion = minecraft_dev.complete_forge_manifest({
		buffer = buffer,
		prefix = "kotlin",
		row = 5,
		col = #'modId="kotlin',
		line = 'modId="kotlin',
	})
	assert_equal(mod_completion.items[1].word, "kotlinmod", "Java/Kotlin @Mod IDs should complete")
	vim.api.nvim_win_set_cursor(0, { 9, 12 })
	assert_equal(minecraft_dev.goto_forge_logo({ buffer = buffer, open = false }).status, "found", "logoFile should resolve from the resource root")

	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
		'modLoader="javafml"',
		'loaderVersion="[52,"',
		"[[mods]]",
		'modId="Invalid Id"',
		'modId="duplicate"',
		'displayTest="INVALID"',
		'logoFile="missing.png"',
		"logoBlur=\"true\"",
		"[[dependencies.unknown]]",
		'modId="forge"',
		'versionRange="(1"',
		'ordering="FIRST"',
		'side="UP"',
	})
	local invalid = minecraft_dev.diagnose_forge_manifest({ buffer = buffer })
	local codes = {}
	for _, item in ipairs(invalid.diagnostics) do codes[item.code] = item end
	for _, code in ipairs({
		"toml_field_required",
		"toml_field_duplicate",
		"toml_field_type_invalid",
		"toml_mod_id_invalid",
		"toml_dependency_owner_unresolved",
		"toml_version_range_invalid",
		"toml_display_test_invalid",
		"toml_ordering_invalid",
		"toml_side_invalid",
		"toml_logo_unresolved",
	}) do
		assert_truthy(codes[code] ~= nil, "invalid Forge metadata should diagnose " .. code)
	end

	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'modLoader="javafml"', 'loaderVersion="[1,)"', 'license="MIT"', "[[mods]]", 'modId="${mod_id}"' })
	assert_equal(#minecraft_dev.diagnose_forge_manifest({ buffer = buffer }).diagnostics, 0, "build placeholders should remain valid")
	vim.api.nvim_buf_set_name(buffer, metadata .. "/neoforge.mods.toml")
	assert_equal(#minecraft_dev.diagnose_forge_manifest({ buffer = buffer }).diagnostics, 0, "neoforge.mods.toml should share metadata support")
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "modLoader=[" })
	assert_equal(minecraft_dev.diagnose_forge_manifest({ buffer = buffer }).error.code, "invalid_toml", "malformed TOML should fail structurally")
	assert_equal(require("minecraft-dev.forge_metadata").inspect({ buffer = buffer, language = "missing_toml_parser" }).error.code, "parser_unavailable", "missing TOML parser should be isolated")

	minecraft_dev.setup()
	local first_autocmd_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevForgeMetadata" })
	minecraft_dev.setup()
	local autocmds = vim.api.nvim_get_autocmds({ group = "MinecraftDevForgeMetadata" })
	assert_equal(#autocmds, first_autocmd_count, "Forge metadata setup should be idempotent")
	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestFabricManifestMetadata()
	local minecraft_dev = require("minecraft-dev")
	local root = vim.fn.tempname()
	local resources = root .. "/src/main/resources"
	local java = root .. "/src/main/java/test"
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(resources, "p")
	vim.fn.mkdir(java, "p")
	vim.fn.writefile({
		"package test;",
		"import net.fabricmc.api.ModInitializer;",
		"public final class Good implements ModInitializer {",
		"  public void handle() {}",
		"  private void hidden() {}",
		"  public void withArg(String value) {}",
		"}",
	}, java .. "/Good.java")
	vim.fn.writefile({
		"package test;",
		"import net.fabricmc.api.ClientModInitializer;",
		"public final class Client implements ClientModInitializer {}",
	}, java .. "/Client.java")
	vim.fn.writefile({ "package test;", "public final class Bad {}" }, java .. "/Bad.java")
	vim.fn.writefile({
		"package test;",
		"public final class Container {",
		"  public static Good initializer = new Good();",
		"  public static Bad wrong = new Bad();",
		"  public Good instance = new Good();",
		"}",
	}, java .. "/Container.java")
	vim.fn.writefile({
		"package test;",
		"public final class BadCtor {",
		"  public BadCtor(String value) {}",
		"  public void handle() {}",
		"}",
	}, java .. "/BadCtor.java")
	vim.fn.writefile({
		"package test",
		"import net.fabricmc.api.ModInitializer",
		"class KGood : ModInitializer",
	}, java .. "/KGood.kt")
	vim.fn.writefile({ "{}" }, resources .. "/demo.mixins.json")
	vim.fn.writefile({ "accessWidener v2 named" }, resources .. "/demo.accesswidener")
	vim.fn.writefile({ "png" }, resources .. "/icon.png")
	vim.fn.writefile({ "MIT License" }, root .. "/LICENSE")
	local path = resources .. "/fabric.mod.json"
	vim.fn.writefile({
		"{",
		'  "schemaVersion": 1,',
		'  "id": "demo-mod",',
		'  "version": "1.0.0",',
		'  "environment": "*",',
		'  "license": "MIT",',
		'  "entrypoints": {',
		'    "main": ["test.Good", "test.Good::handle", "test.Container::initializer", {"value": "test.KGood", "adapter": "kotlin"}],',
		'    "client": ["test.Client"]',
		"  },",
		'  "mixins": ["demo.mixins.json"],',
		'  "accessWidener": "demo.accesswidener",',
		'  "icon": "icon.png",',
		'  "depends": {"fabricloader": ">=0.16", "minecraft": ["1.21", "1.21.1"]}',
		"}",
	}, path)
	local buffer = vim.fn.bufadd(path)
	vim.fn.bufload(buffer)
	vim.bo[buffer].filetype = "json"
	local valid = minecraft_dev.diagnose_fabric_manifest({ buffer = buffer })
	assert_equal(valid.status, "diagnosed", "fabric.mod.json should be parsed")
	assert_equal(#valid.diagnostics, 0, "valid Fabric metadata should pass")
	assert_equal(#valid.entrypoints, 5, "simple, method, field, and object entrypoints should be indexed")
	assert_equal(minecraft_dev.goto_fabric_entrypoint({ buffer = buffer, value = "test.KGood", open = false }).status, "found", "Kotlin Fabric entrypoint should resolve")
	local completed = minecraft_dev.complete_fabric_entrypoints({ buffer = buffer, entrypoint_type = "main", prefix = "test." })
	local completion_words = {}
	for _, item in ipairs(completed.items) do completion_words[item.word] = true end
	assert_truthy(completion_words["test.Good"] and completion_words["test.KGood"], "main entrypoint completion should include Java and Kotlin initializers")
	assert_truthy(not completion_words["test.Client"], "main entrypoint completion should filter wrong initializer types")
	local resource_completion = minecraft_dev.complete_fabric_resources({ buffer = buffer, kind = "mixin", prefix = "demo" })
	assert_equal(resource_completion.items[1].word, "demo.mixins.json", "Fabric resource completion should filter by reference kind")
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_win_set_cursor(0, { 13, 12 })
	assert_equal(minecraft_dev.goto_fabric_resource({ buffer = buffer, open = false }).status, "found", "Fabric icon should resolve from resources")
	vim.api.nvim_win_set_cursor(0, { 6, 15 })
	local license_jump = minecraft_dev.goto_fabric_resource({ buffer = buffer, open = false })
	assert_equal(license_jump.status, "found", "Fabric license should resolve to the project LICENSE file")

	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
		"{",
		'  "id": "Bad Id",',
		'  "schemaVersion": 2,',
		'  "id": "duplicate",',
		'  "version": 1,',
		'  "environment": "both",',
		'  "entrypoints": {"main": ["test.Bad", "test.Missing", "test.Good::hidden", "test.Good::withArg", "test.Good::missing", "test.BadCtor::handle", "test.Container::wrong", "test.Container::instance"]},',
		'  "mixins": [{"environment": "sideways"}, "missing.json"],',
		'  "accessWidener": "missing.txt",',
		'  "depends": {"minecraft": 1}',
		"}",
	})
	local invalid = minecraft_dev.diagnose_fabric_manifest({ buffer = buffer })
	local codes = {}
	for _, item in ipairs(invalid.diagnostics) do codes[item.code] = item end
	for _, code in ipairs({
		"fabric_field_duplicate",
		"fabric_field_type_invalid",
		"fabric_schema_first",
		"fabric_schema_invalid",
		"fabric_mod_id_invalid",
		"fabric_environment_invalid",
		"fabric_dependency_invalid",
		"fabric_entrypoint_wrong_type",
		"fabric_entrypoint_unresolved",
		"fabric_entrypoint_member_private",
		"fabric_entrypoint_method_parameters",
		"fabric_entrypoint_member_unresolved",
		"fabric_entrypoint_constructor_invalid",
		"fabric_entrypoint_field_static",
		"fabric_resource_type_invalid",
		"fabric_resource_name_invalid",
		"fabric_resource_unresolved",
	}) do
		assert_truthy(codes[code] ~= nil, "invalid Fabric metadata should diagnose " .. code)
	end

	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "{" })
	assert_equal(minecraft_dev.diagnose_fabric_manifest({ buffer = buffer }).error.code, "invalid_json", "malformed Fabric JSON should fail structurally")
	assert_equal(require("minecraft-dev.fabric_metadata").inspect({ buffer = buffer, language = "missing_json_parser" }).error.code, "parser_unavailable", "missing JSON parser should be isolated")
	minecraft_dev.setup()
	local first_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevFabricMetadata" })
	minecraft_dev.setup()
	assert_equal(#vim.api.nvim_get_autocmds({ group = "MinecraftDevFabricMetadata" }), first_count, "Fabric metadata setup should be idempotent")
	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestMixinConfigMetadata()
	local minecraft_dev = require("minecraft-dev")
	local root = vim.fn.tempname()
	local java = root .. "/src/main/java/test/mixin"
	local resources = root .. "/src/main/resources"
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(java, "p")
	vim.fn.mkdir(resources, "p")
	vim.fn.writefile({
		"package test.mixin;",
		"import org.spongepowered.asm.mixin.Mixin;",
		"@Mixin(Object.class)",
		"public final class DemoMixin {}",
	}, java .. "/DemoMixin.java")
	vim.fn.writefile({
		"package test.mixin",
		"import org.spongepowered.asm.mixin.Mixin",
		"@Mixin(Any::class)",
		"class ClientMixin",
	}, java .. "/ClientMixin.kt")
	vim.fn.writefile({ "package test.mixin;", "public final class NotMixin {}" }, java .. "/NotMixin.java")
	vim.fn.writefile({
		"package test.mixin;",
		"import org.spongepowered.asm.mixin.extensibility.IMixinConfigPlugin;",
		"public final class Plugin implements IMixinConfigPlugin {}",
	}, java .. "/Plugin.java")
	local path = resources .. "/demo.mixins.json"
	vim.fn.writefile({
		"{",
		'  "required": true,',
		'  "minVersion": "0.8",',
		'  "package": "test.mixin",',
		'  "plugin": "test.mixin.Plugin",',
		'  "compatibilityLevel": "JAVA_21",',
		'  "mixins": ["DemoMixin"],',
		'  "client": ["ClientMixin"]',
		"}",
	}, path)
	local buffer = vim.fn.bufadd(path)
	vim.fn.bufload(buffer)
	vim.bo[buffer].filetype = "json"
	local valid = minecraft_dev.diagnose_mixin_config({ buffer = buffer })
	assert_equal(valid.status, "diagnosed", "Mixin config should be parsed")
	assert_equal(#valid.diagnostics, 0, "valid Java/Kotlin Mixin config should pass")
	assert_equal(#valid.mixins, 2, "common and client Mixin lists should be indexed")
	assert_equal(minecraft_dev.goto_mixin_reference({ buffer = buffer, value = "DemoMixin", open = false }).status, "found", "package-relative Mixin class should resolve")
	assert_equal(minecraft_dev.goto_mixin_reference({ buffer = buffer, value = "test.mixin.Plugin", kind = "plugin", open = false }).status, "found", "Mixin plugin should resolve")
	assert_equal(minecraft_dev.complete_mixin_config({ buffer = buffer, kind = "mixin", prefix = "Demo" }).items[1].word, "DemoMixin", "Mixin completion should use package-relative names")
	assert_equal(minecraft_dev.complete_mixin_config({ buffer = buffer, kind = "plugin", prefix = "test" }).items[1].word, "test.mixin.Plugin", "Mixin plugin completion should require the plugin interface")
	assert_equal(minecraft_dev.complete_mixin_config({ kind = "compatibilityLevel", prefix = "JAVA_21" }).items[1].word, "JAVA_21", "Mixin compatibility levels should complete")

	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
		"{",
		'  "required": "true",',
		'  "package": "bad package",',
		'  "compatibilityLevel": "21",',
		'  "mixins": ["NotMixin", "Missing", "NotMixin"],',
		'  "plugin": "test.mixin.NotMixin"',
		"}",
	})
	local invalid = minecraft_dev.diagnose_mixin_config({ buffer = buffer })
	local codes = {}
	for _, item in ipairs(invalid.diagnostics) do codes[item.code] = item end
	for _, code in ipairs({
		"mixin_field_type_invalid",
		"mixin_package_invalid",
		"mixin_package_unresolved",
		"mixin_compatibility_invalid",
		"mixin_class_duplicate",
		"mixin_class_unresolved",
		"mixin_plugin_wrong_type",
	}) do
		assert_truthy(codes[code] ~= nil, "invalid Mixin config should diagnose " .. code)
	end
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "{" })
	assert_equal(minecraft_dev.diagnose_mixin_config({ buffer = buffer }).error.code, "invalid_json", "malformed Mixin JSON should fail structurally")
	assert_equal(require("minecraft-dev.mixin_metadata").inspect({ buffer = buffer, language = "json5" }).error.code, "parser_unavailable", "missing JSON5 parser should be isolated")
	minecraft_dev.setup()
	local first_count = #vim.api.nvim_get_autocmds({ group = "MinecraftDevMixinMetadata" })
	minecraft_dev.setup()
	assert_equal(#vim.api.nvim_get_autocmds({ group = "MinecraftDevMixinMetadata" }), first_count, "Mixin metadata setup should be idempotent")
	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestNbtEditing()
	local nbt = require("minecraft-dev.nbt")
	assert_equal(vim.fn.exists(":MinecraftDevEditNbt"), 2, "NBT edit command should be registered")
	assert_equal(vim.fn.exists(":MinecraftDevSaveNbt"), 2, "NBT save command should be registered")
	assert_equal(vim.fn.exists(":MinecraftDevReloadNbt"), 2, "NBT reload command should be registered")
	local document = vim.json.encode({
		type = "compound",
		name = "Level",
		value = {
			{ type = "byte", name = "byte", value = -7 },
			{ type = "short", name = "short", value = 32000 },
			{ type = "int", name = "int", value = 123456 },
			{ type = "long", name = "long", value = "9223372036854775807" },
			{ type = "float", name = "float", value = 1.5 },
			{ type = "double", name = "double", value = -2.25 },
			{ type = "string", name = "string", value = "hello\0😀" },
			{ type = "byte_array", name = "bytes", value = { -1, 0, 127 } },
			{ type = "int_array", name = "ints", value = { -1, 0, 2147483647 } },
			{ type = "long_array", name = "longs", value = { "-1", "9223372036854775807" } },
			{
				type = "list",
				name = "list",
				element_type = "compound",
				value = { { type = "compound", value = { { type = "string", name = "id", value = "minecraft:stone" } } } },
			},
		},
	})

	for _, compression in ipairs({ "none", "gzip", "zlib" }) do
		local encoded = nbt.encode_text(document, { compression = compression })
		assert_equal(encoded.status, "encoded", compression .. " NBT should encode")
		local decoded = nbt.decode_bytes(encoded.bytes)
		assert_equal(decoded.status, "decoded", compression .. " NBT should decode")
		assert_equal(decoded.compression, compression, compression .. " should be detected")
		local root = vim.json.decode(decoded.text)
		assert_equal(root.name, "Level", "root name should survive NBT round trip")
		assert_equal(root.value[4].value, "9223372036854775807", "64-bit longs should stay lossless")
		assert_equal(root.value[7].value, "hello\0😀", "modified UTF-8 strings should stay lossless")
	end

	assert_equal(nbt.decode_bytes(string.char(99, 0, 0)).error.code, "unknown_tag", "unknown tags should fail structurally")
	assert_equal(nbt.decode_bytes(string.char(10, 0)).error.code, "malformed", "truncated NBT should fail structurally")
	assert_equal(nbt.decode_bytes(string.rep("x", 9), { max_input_bytes = 8 }).error.code, "size_limit", "input size limits should be enforced before decoding")
	local too_deep = { type = "compound", name = "", value = {} }
	local cursor = too_deep
	for index = 1, 4 do
		local child = { type = "compound", name = tostring(index), value = {} }
		table.insert(cursor.value, child)
		cursor = child
	end
	assert_equal(nbt.encode_text(vim.json.encode(too_deep), { max_depth = 3 }).error.code, "depth_limit", "NBT depth limits should be enforced")
	assert_equal(nbt.encode_text(document, { max_tags = 1 }).error.code, "tag_limit", "NBT tag count limits should be enforced")
	assert_equal(nbt.encode_text(document, { max_array_length = 1 }).error.code, "array_limit", "NBT array limits should be enforced")
	assert_equal(nbt.encode_text(document, { max_string_bytes = 2 }).error.code, "string_limit", "NBT string limits should be enforced")

	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local path = root .. "/level.dat"
	local initial = nbt.encode_text(document, { compression = "zlib" })
	local uv = vim.uv or vim.loop
	local fd = assert(uv.fs_open(path, "w", 384))
	assert_equal(uv.fs_write(fd, initial.bytes, 0), #initial.bytes, "NBT fixture should be written as binary")
	uv.fs_close(fd)
	local opened = nbt.open({ path = path, sync = true })
	assert_equal(opened.status, "opened", "NBT should open into an editable buffer")
	assert_equal(vim.bo[opened.buffer].buftype, "acwrite", "NBT text view should use an acwrite buffer")
	assert_equal(nbt.open({ path = path, sync = true }).buffer, opened.buffer, "opening an active NBT view should reuse it")
	local edited = vim.json.decode(table.concat(vim.api.nvim_buf_get_lines(opened.buffer, 0, -1, false), "\n"))
	edited.value[7].value = "changed"
	vim.api.nvim_buf_set_lines(opened.buffer, 0, -1, false, vim.split(vim.json.encode(edited), "\n", { plain = true }))
	assert_equal(nbt.reload_buffer({ buffer = opened.buffer, sync = true }).error.code, "modified_buffer", "reload should protect unsaved NBT edits")
	vim.api.nvim_buf_set_lines(opened.buffer, 0, -1, false, { "{" })
	assert_equal(nbt.save_buffer({ buffer = opened.buffer }).error.code, "invalid_text", "invalid NBT text should not save")
	vim.api.nvim_buf_set_lines(opened.buffer, 0, -1, false, vim.split(vim.json.encode(edited), "\n", { plain = true }))
	local saved = nbt.save_buffer({ buffer = opened.buffer })
	assert_equal(saved.status, "saved", "edited NBT should save")
	local reloaded = nbt.reload_buffer({ buffer = opened.buffer, sync = true })
	assert_equal(reloaded.status, "reloaded", "NBT text view should reload")
	assert_equal(vim.json.decode(table.concat(vim.api.nvim_buf_get_lines(opened.buffer, 0, -1, false), "\n")).value[7].value, "changed", "saved NBT should reload edited values")
	local stat = assert(uv.fs_stat(path))
	fd = assert(uv.fs_open(path, "r", 384))
	local saved_bytes = assert(uv.fs_read(fd, stat.size, 0))
	uv.fs_close(fd)
	assert_equal(nbt.decode_bytes(saved_bytes).compression, "zlib", "save should preserve compression")
	assert_equal(bit.band(assert(uv.fs_stat(path)).mode, 511), 384, "atomic save should preserve file permissions")
	assert_equal(#vim.fn.glob(path .. ".minecraft-dev.*.tmp", false, true), 0, "atomic save should not leave temporary files")
	vim.api.nvim_buf_delete(opened.buffer, { force = true })
	vim.fn.delete(root, "rf")

	local cancelled = false
	local helper = vim.fn.tempname()
	vim.fn.writefile({ "exec sleep 10" }, helper)
	local pending = nbt.decode_async("", { python = "/bin/sh", helper_path = helper }, function(result)
		cancelled = result.status == "cancelled"
	end)
	assert_equal(pending.status, "pending", "asynchronous NBT decode should return a cancellable handle")
	pending.cancel()
	vim.wait(1000, function() return cancelled end)
	assert_truthy(cancelled, "cancelled NBT decoding should report cancellation")
	local timed_out = false
	nbt.decode_async("", { python = "/bin/sh", helper_path = helper, timeout_ms = 10 }, function(result)
		timed_out = result.status == "failed" and result.error.code == "timeout"
	end)
	vim.wait(1000, function() return timed_out end)
	assert_truthy(timed_out, "timed-out NBT decoding should report timeout")
	vim.fn.delete(helper)
end

function _G.MinecraftDevTestMappingsAndAccessRules()
	local mappings = require("minecraft-dev.mappings")
	for _, command in ipairs({
		"MinecraftDevLookupMapping",
		"MinecraftDevGotoAccessTarget",
		"MinecraftDevCopyAt",
		"MinecraftDevCopyAw",
		"MinecraftDevCopyCoremodTarget",
		"MinecraftDevCopyMixinTarget",
	}) do
		assert_equal(vim.fn.exists(":" .. command), 2, command .. " should be registered")
	end
	local standard = table.concat({
		"CL: test/Example a/b",
		"FD: test/Example/count a/b/f_1_",
		"MD: test/Example/run (I)Ljava/lang/String; a/b/m_1_ (I)Ljava/lang/String;",
	}, "\n")
	local inspected = mappings.inspect({ content = standard, format = "srg" })
	assert_equal(inspected.status, "indexed", "standard SRG should parse")
	assert_equal(#inspected.entries, 3, "standard SRG should index class, field, and method")
	assert_equal(mappings.lookup({ content = standard, format = "srg", query = "run" }).matches[1].target_name, "m_1_", "named method should map to SRG")
	assert_equal(mappings.lookup({ content = standard, format = "srg", query = "m_1_" }).matches[1].source_name, "run", "SRG lookup should be bidirectional")
	local tsrg = table.concat({
		"test/Example a/b",
		"\tcount f_1_",
		"\trun (I)Ljava/lang/String; m_1_",
	}, "\n")
	assert_equal(#mappings.inspect({ content = tsrg, format = "tsrg" }).entries, 3, "TSRG should index class and members")
	assert_equal(mappings.lookup({ query = "missing", paths = {} }).error.code, "mapping_unavailable", "lookup without mapping files should fail structurally")

	local root = vim.fn.tempname()
	local java_dir = root .. "/src/main/java/test"
	local resources = root .. "/src/main/resources/META-INF"
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(java_dir, "p")
	vim.fn.mkdir(resources, "p")
	local java_path = java_dir .. "/Example.java"
	vim.fn.writefile({
		"package test;",
		"public class Example {",
		"  private int count;",
		"  public String run(int value) { return String.valueOf(value); }",
		"}",
	}, java_path)
	local java_buffer = vim.fn.bufadd(java_path)
	vim.fn.bufload(java_buffer)
	vim.bo[java_buffer].filetype = "java"

	local targets = require("minecraft-dev.jvm_targets")
	assert_equal(targets.copy({ buffer = java_buffer, member = "run", format = "at", clipboard = false }).text, "test.Example run(I)Ljava/lang/String;", "AT target should use dotted owner and JVM descriptor")
	assert_equal(targets.copy({ buffer = java_buffer, member = "run", format = "aw", clipboard = false }).text, "accessible method test/Example run (I)Ljava/lang/String;", "AW target should use internal owner and JVM descriptor")
	local coremod = vim.json.decode(targets.copy({ buffer = java_buffer, member = "run", format = "coremod", clipboard = false }).text)
	assert_equal(coremod.target, "METHOD", "coremod method target should be structured")
	assert_equal(coremod.methodDesc, "(I)Ljava/lang/String;", "coremod target should preserve method descriptor")
	assert_equal(targets.copy({ buffer = java_buffer, member = "run", format = "mixin", clipboard = false }).text, "Ltest/Example;run(I)Ljava/lang/String;", "Mixin target should use canonical owner syntax")

	local rules = require("minecraft-dev.access_rules")
	local at_path = resources .. "/accesstransformer.cfg"
	vim.fn.writefile({
		"public test.Example count",
		"public test.Example count",
		"public-f test.Example run(I)Ljava/lang/String;",
		"invalid test.Example",
	}, at_path)
	local at_buffer = vim.fn.bufadd(at_path)
	vim.fn.bufload(at_buffer)
	local diagnosed_at = rules.diagnose_buffer({ buffer = at_buffer, format = "at" })
	local at_codes = {}
	for _, item in ipairs(diagnosed_at.diagnostics) do at_codes[item.code] = true end
	assert_truthy(at_codes.access_rule_duplicate, "duplicate AT entries should diagnose")
	assert_truthy(at_codes.access_modifier_invalid, "invalid AT modifiers should diagnose")
	assert_equal(rules.complete({ buffer = at_buffer, format = "at", line = "pub", prefix = "pub" }).items[1].word, "public", "AT modifiers should complete")
	assert_equal(rules.complete({ buffer = at_buffer, format = "at", line = "public test.Ex", prefix = "test.Ex" }).items[1].word, "test.Example", "AT owners should complete from local source")
	assert_equal(rules.complete({ buffer = at_buffer, format = "at", line = "public test.Example ru", prefix = "ru" }).items[1].word, "run(I)Ljava/lang/String;", "AT methods should complete with descriptors")
	assert_equal(rules.goto_target({ buffer = at_buffer, format = "at", row = 2, open = false }).member.name, "run", "AT method target should navigate to source")

	local aw_path = resources .. "/demo.accesswidener"
	vim.fn.writefile({
		"accessWidener v2 named",
		"accessible field test/Example count I",
		"accessible field test/Example count I",
		"mutable method test/Example run (I)Ljava/lang/String;",
	}, aw_path)
	local aw_buffer = vim.fn.bufadd(aw_path)
	vim.fn.bufload(aw_buffer)
	local diagnosed_aw = rules.diagnose_buffer({ buffer = aw_buffer, format = "aw" })
	local aw_codes = {}
	for _, item in ipairs(diagnosed_aw.diagnostics) do aw_codes[item.code] = true end
	assert_truthy(aw_codes.access_rule_duplicate, "duplicate AW entries should diagnose")
	assert_truthy(aw_codes.access_kind_invalid, "invalid AW access/kind combinations should diagnose")
	assert_equal(rules.complete({ buffer = aw_buffer, format = "aw", line = "accessible field test/Example co", prefix = "co" }).items[1].word, "count", "AW fields should complete from local source")
	assert_equal(rules.goto_target({ buffer = aw_buffer, format = "aw", row = 1, open = false }).member.name, "count", "AW field target should navigate to source")

	local coremod_path = resources .. "/coremods.js"
	vim.fn.writefile({
		"const first = { target: { target: 'METHOD', class: 'test.Example', methodName: 'run', methodDesc: '(I)Ljava/lang/String;' } };",
		"const second = { target: { target: 'METHOD', class: 'test.Example', methodName: 'run', methodDesc: '(I)Ljava/lang/String;' } };",
	}, coremod_path)
	local coremod_buffer = vim.fn.bufadd(coremod_path)
	vim.fn.bufload(coremod_buffer)
	local diagnosed_coremod = rules.diagnose_buffer({ buffer = coremod_buffer, format = "coremod" })
	assert_equal(diagnosed_coremod.diagnostics[1].code, "access_rule_duplicate", "duplicate coremod targets should diagnose")
	assert_equal(rules.goto_target({ buffer = coremod_buffer, format = "coremod", row = 0, open = false }).member.name, "run", "coremod method target should navigate to source")

	vim.api.nvim_buf_delete(at_buffer, { force = true })
	vim.api.nvim_buf_delete(aw_buffer, { force = true })
	vim.api.nvim_buf_delete(coremod_buffer, { force = true })
	-- The distribution Java ftplugin cleanup references an optional SpotBugs augroup.
	vim.api.nvim_create_augroup("java_spotbugs", { clear = false })
	vim.api.nvim_create_augroup("java_spotbugs_post", { clear = false })
	vim.api.nvim_buf_delete(java_buffer, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestMixinSourceActions()
	local minecraft_dev = require("minecraft-dev")
	assert_equal(vim.fn.exists(":MinecraftDevFindMixins"), 2, "Mixin finder command should be registered")
	assert_equal(vim.fn.exists(":MinecraftDevGenerateMixinMember"), 2, "Mixin generation command should be registered")
	local root = vim.fn.tempname()
	local target_dir = root .. "/src/main/java/test"
	local mixin_dir = root .. "/src/main/java/test/mixin"
	local kotlin_dir = root .. "/src/main/kotlin/test/mixin"
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(target_dir, "p")
	vim.fn.mkdir(mixin_dir, "p")
	vim.fn.mkdir(kotlin_dir, "p")
	local target_path = target_dir .. "/Example.java"
	vim.fn.writefile({
		"package test;",
		"public class Example<T> {",
		"  private final int count = 0;",
		"  private void hidden() {}",
		"  public String run(int value) { return String.valueOf(value); }",
		"  public void interfaceMethod(String input) {}",
		"  public T mystery(T value) { return value; }",
		"}",
	}, target_path)
	local mixin_path = mixin_dir .. "/ExampleMixin.java"
	vim.fn.writefile({
		"package test.mixin;",
		"import org.spongepowered.asm.mixin.Mixin;",
		"import org.spongepowered.asm.mixin.Implements;",
		"import org.spongepowered.asm.mixin.Interface;",
		"import test.Example;",
		"@Mixin(Example.class)",
		"@Implements(@Interface(iface = Runnable.class, prefix = \"iface$\"))",
		"public class ExampleMixin {",
		"}",
	}, mixin_path)
	vim.fn.writefile({
		"package test.mixin",
		"import org.spongepowered.asm.mixin.Mixin",
		"import test.Example",
		"@Mixin(Example::class)",
		"class KotlinExampleMixin",
	}, kotlin_dir .. "/KotlinExampleMixin.kt")
	vim.fn.writefile({
		"package test.mixin;",
		"import org.spongepowered.asm.mixin.Mixin;",
		"@Mixin(targets = {\"test.Example\"})",
		"public class StringTargetMixin {}",
	}, mixin_dir .. "/StringTargetMixin.java")
	local target_buffer = vim.fn.bufadd(target_path)
	vim.fn.bufload(target_buffer)
	vim.bo[target_buffer].filetype = "java"
	local mixin_buffer = vim.fn.bufadd(mixin_path)
	vim.fn.bufload(mixin_buffer)
	vim.bo[mixin_buffer].filetype = "java"

	local actions = require("minecraft-dev.mixin_actions")
	local found = actions.find_mixins({ buffer = target_buffer, target = "test.Example", open = false })
	assert_equal(found.status, "found", "Mixin target search should complete")
	assert_equal(#found.matches, 3, "class literal, Kotlin, and string @Mixin targets should be indexed")
	assert_equal(actions.generate({ source_buffer = target_buffer, kind = "shadow", member = "hidden" }).error.code, "mixin_source_ambiguous", "implicit generation should fail on multiple matching Mixins")
	local empty_root = root .. "/empty"
	vim.fn.mkdir(empty_root .. "/.git", "p")
	assert_equal(actions.generate({ source_buffer = target_buffer, root = empty_root, kind = "shadow", member = "hidden" }).error.code, "mixin_source_unresolved", "incomplete projects should fail without changing source")
	vim.bo[mixin_buffer].modifiable = false
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "shadow", member = "hidden" }).error.code, "mixin_buffer_readonly", "read-only Mixin buffers should fail structurally")
	vim.bo[mixin_buffer].modifiable = true

	local pristine_mixin = table.concat(vim.api.nvim_buf_get_lines(mixin_buffer, 0, -1, false), "\n")
	local generated = actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "accessor_getter", member = "count" })
	assert_equal(generated.status, "generated", "field accessor getter should generate")
	local text = table.concat(vim.api.nvim_buf_get_lines(mixin_buffer, 0, -1, false), "\n")
	assert_truthy(text:find("@org.spongepowered.asm.mixin.gen.Accessor", 1, true) ~= nil, "accessor annotation should be fully qualified")
	assert_truthy(text:find("int getCount()", 1, true) ~= nil, "getter signature should use the source field type")
	vim.api.nvim_buf_call(mixin_buffer, function() vim.cmd("silent undo") end)
	assert_equal(table.concat(vim.api.nvim_buf_get_lines(mixin_buffer, 0, -1, false), "\n"), pristine_mixin, "one undo should revert one isolated generated member")
	vim.api.nvim_buf_call(mixin_buffer, function() vim.cmd("silent redo") end)
	local before_duplicate = text
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "accessor_getter", member = "count" }).error.code, "mixin_member_duplicate", "duplicate accessor generation should fail")
	assert_equal(table.concat(vim.api.nvim_buf_get_lines(mixin_buffer, 0, -1, false), "\n"), before_duplicate, "duplicate generation must not change the buffer")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "accessor_setter", member = "count" }).status, "generated", "field accessor setter should generate")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "invoker", member = "run" }).status, "generated", "method invoker should generate")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "shadow", member = "hidden" }).status, "generated", "shadow fallback should generate")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "overwrite", member = "run" }).status, "generated", "overwrite fallback should generate")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "soft_implements", member = "interfaceMethod", prefix = "iface$" }).status, "generated", "soft-implements fallback should generate")
	text = table.concat(vim.api.nvim_buf_get_lines(mixin_buffer, 0, -1, false), "\n")
	for _, expected in ipairs({ "setCount", "callRun", "@org.spongepowered.asm.mixin.Shadow", "@org.spongepowered.asm.mixin.Overwrite", "iface$interfaceMethod" }) do
		assert_truthy(text:find(expected, 1, true) ~= nil, "generated Mixin source should contain " .. expected)
	end

	local unchanged_target = table.concat(vim.api.nvim_buf_get_lines(target_buffer, 0, -1, false), "\n")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = target_buffer, kind = "shadow", member = "hidden" }).error.code, "not_mixin_source", "generation should reject a non-Mixin target buffer")
	assert_equal(table.concat(vim.api.nvim_buf_get_lines(target_buffer, 0, -1, false), "\n"), unchanged_target, "failed generation must not change a non-Mixin buffer")
	assert_equal(actions.generate({ source_buffer = target_buffer, target_buffer = mixin_buffer, kind = "invoker", member = "mystery" }).error.code, "descriptor_unresolved", "unresolved generic descriptors should fail closed")

	vim.api.nvim_create_augroup("java_spotbugs", { clear = false })
	vim.api.nvim_create_augroup("java_spotbugs_post", { clear = false })
	vim.api.nvim_buf_delete(target_buffer, { force = true })
	vim.api.nvim_buf_delete(mixin_buffer, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestSourceGeneration()
	local minecraft_dev = require("minecraft-dev")
	assert_equal(vim.fn.exists(":MinecraftDevGenerateEventListener"), 2, "event listener command should be registered")
	assert_equal(vim.fn.exists(":MinecraftDevGenerateMinecraftClass"), 2, "Minecraft class command should be registered")
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(root .. "/src/main/java/test", "p")
	vim.fn.mkdir(root .. "/src/main/kotlin/test", "p")

	local java_path = root .. "/src/main/java/test/Listeners.java"
	vim.fn.writefile({ "package test;", "public class Listeners {", "}" }, java_path)
	local java_buffer = vim.fn.bufadd(java_path)
	vim.fn.bufload(java_buffer)
	vim.bo[java_buffer].filetype = "java"
	local original_java = table.concat(vim.api.nvim_buf_get_lines(java_buffer, 0, -1, false), "\n")
	local generated = minecraft_dev.generate_event_listener({
		buffer = java_buffer,
		platform = "bukkit",
		event = "org.bukkit.event.player.PlayerJoinEvent",
		name = "onPlayerJoin",
		priority = "HIGH",
		ignore_cancelled = true,
	})
	assert_equal(generated.status, "generated", "Bukkit Java listener should generate")
	local java_text = table.concat(vim.api.nvim_buf_get_lines(java_buffer, 0, -1, false), "\n")
	assert_truthy(java_text:find("implements org.bukkit.event.Listener", 1, true) ~= nil, "Bukkit listener should implement Listener")
	assert_truthy(java_text:find("@org.bukkit.event.EventHandler(priority = org.bukkit.event.EventPriority.HIGH, ignoreCancelled = true)", 1, true) ~= nil, "Bukkit listener options should render")
	assert_truthy(java_text:find("public void onPlayerJoin(org.bukkit.event.player.PlayerJoinEvent event)", 1, true) ~= nil, "Java listener signature should render")
	local before_duplicate = java_text
	assert_equal(minecraft_dev.generate_event_listener({ buffer = java_buffer, platform = "bukkit", event = "org.bukkit.event.player.PlayerJoinEvent", name = "onPlayerJoin" }).error.code, "event_listener_duplicate", "duplicate listener should fail")
	assert_equal(table.concat(vim.api.nvim_buf_get_lines(java_buffer, 0, -1, false), "\n"), before_duplicate, "duplicate listener failure must not edit")
	vim.api.nvim_buf_call(java_buffer, function() vim.cmd("silent undo") end)
	assert_equal(table.concat(vim.api.nvim_buf_get_lines(java_buffer, 0, -1, false), "\n"), original_java, "one undo should revert listener and interface edits")

	local kotlin_path = root .. "/src/main/kotlin/test/VelocityListeners.kt"
	vim.fn.writefile({ "package test", "class VelocityListeners {", "}" }, kotlin_path)
	local kotlin_buffer = vim.fn.bufadd(kotlin_path)
	vim.fn.bufload(kotlin_buffer)
	vim.bo[kotlin_buffer].filetype = "kotlin"
	assert_equal(minecraft_dev.generate_event_listener({ buffer = kotlin_buffer, platform = "velocity", event = "com.example.ConnectEvent", name = "onConnect", order = "LAST" }).status, "generated", "Velocity Kotlin listener should generate")
	local kotlin_text = table.concat(vim.api.nvim_buf_get_lines(kotlin_buffer, 0, -1, false), "\n")
	assert_truthy(kotlin_text:find("@com.velocitypowered.api.event.Subscribe(order = com.velocitypowered.api.event.PostOrder.LAST)", 1, true) ~= nil, "Velocity order should render")
	assert_truthy(kotlin_text:find("fun onConnect(event: com.example.ConnectEvent)", 1, true) ~= nil, "Kotlin listener signature should render")
	local kotlin_single_path = root .. "/src/main/kotlin/test/KotlinBukkit.kt"
	vim.fn.writefile({ "package test", "class KotlinBukkit(val name: String) {}" }, kotlin_single_path)
	local kotlin_single_buffer = vim.fn.bufadd(kotlin_single_path)
	vim.fn.bufload(kotlin_single_buffer)
	vim.bo[kotlin_single_buffer].filetype = "kotlin"
	assert_equal(minecraft_dev.generate_event_listener({ buffer = kotlin_single_buffer, platform = "bukkit", event = "org.bukkit.event.Event", name = "handle" }).status, "generated", "single-line Kotlin class listener should generate")
	local kotlin_single_text = table.concat(vim.api.nvim_buf_get_lines(kotlin_single_buffer, 0, -1, false), "\n")
	assert_truthy(kotlin_single_text:find(") : org.bukkit.event.Listener {", 1, true) ~= nil, "Kotlin constructor type colon must not be mistaken for a superclass list")
	assert_truthy(kotlin_single_text:find("fun handle(event: org.bukkit.event.Event)", 1, true) ~= nil, "single-line Kotlin listener should remain inside the class")

	for platform, expected in pairs({
		bungeecord = "@net.md_5.bungee.event.EventHandler(priority = net.md_5.bungee.event.EventPriority.HIGHEST)",
		forge = "@net.minecraftforge.fml.common.Mod.EventHandler",
		neoforge = "@net.neoforged.bus.api.SubscribeEvent",
		sponge = "@org.spongepowered.api.event.Listener(order = org.spongepowered.api.event.Order.LAST)",
	}) do
		local path = root .. "/src/main/java/test/" .. platform .. ".java"
		vim.fn.writefile({ "package test;", "class Generated {", "}" }, path)
		local buffer = vim.fn.bufadd(path)
		vim.fn.bufload(buffer)
		vim.bo[buffer].filetype = "java"
		local options = { buffer = buffer, platform = platform, event = "com.example.Event", name = "handle" }
		if platform == "bungeecord" then options.priority = "HIGHEST" end
		if platform == "forge" then options.forge_kind = "fml" end
		if platform == "sponge" then options.order = "LAST" end
		assert_equal(minecraft_dev.generate_event_listener(options).status, "generated", platform .. " listener should generate")
		assert_truthy(table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"):find(expected, 1, true) ~= nil, platform .. " annotation should render")
		vim.api.nvim_buf_delete(buffer, { force = true })
	end

	vim.bo[java_buffer].modifiable = false
	assert_equal(minecraft_dev.generate_event_listener({ buffer = java_buffer, platform = "neoforge", event = "com.example.Event", name = "other" }).error.code, "source_buffer_readonly", "read-only listener target should fail")
	vim.bo[java_buffer].modifiable = true
	assert_equal(minecraft_dev.generate_event_listener({ buffer = java_buffer, platform = "unknown", event = "com.example.Event", name = "other" }).error.code, "event_platform_invalid", "unknown listener platform should fail")
	assert_equal(minecraft_dev.generate_event_listener({ buffer = java_buffer, platform = "bukkit", event = "com.example.Event", name = "other", priority = "IMPOSSIBLE" }).error.code, "event_option_invalid", "invalid priority should fail")
	assert_equal(minecraft_dev.generate_event_listener({ buffer = java_buffer, platform = "bukkit", event = "bad event", name = "other" }).error.code, "event_class_invalid", "invalid event class should fail")
	local original_get_parser = vim.treesitter.get_parser
	vim.treesitter.get_parser = function(buffer, language)
		if buffer == java_buffer and language == "java" then error("missing parser") end
		return original_get_parser(buffer, language)
	end
	assert_equal(minecraft_dev.generate_event_listener({ buffer = java_buffer, platform = "neoforge", event = "com.example.Event", name = "other" }).error.code, "parser_unavailable", "missing source parser should fail structurally")
	vim.treesitter.get_parser = original_get_parser

	local forge_old = minecraft_dev.generate_minecraft_class({ root = root, platform = "forge", kind = "block", class_name = "test.block.OldBlock", minecraft_version = "1.16.5", open = false })
	assert_equal(forge_old.status, "generated", "legacy Forge class should generate")
	assert_truthy(table.concat(vim.fn.readfile(forge_old.path), "\n"):find("net.minecraft.block.Block", 1, true) ~= nil, "legacy Forge class should use pre-1.17 package")
	local forge_new = minecraft_dev.generate_minecraft_class({ root = root, platform = "forge", kind = "packet", class_name = "test.network.SyncPacket", minecraft_version = "1.18.2", open = false })
	assert_truthy(table.concat(vim.fn.readfile(forge_new.path), "\n"):find("net.minecraftforge.network.NetworkEvent", 1, true) ~= nil, "modern Forge packet should use 1.18 template")
	local fabric = minecraft_dev.generate_minecraft_class({ root = root, platform = "fabric", kind = "status_effect", class_name = "test.effect.DemoEffect", open = false })
	assert_truthy(table.concat(vim.fn.readfile(fabric.path), "\n"):find("extends StatusEffect", 1, true) ~= nil, "Fabric status effect should generate")
	local neoforge = minecraft_dev.generate_minecraft_class({ root = root, platform = "neoforge", kind = "item", class_name = "test.item.DemoItem", open = false })
	assert_truthy(table.concat(vim.fn.readfile(neoforge.path), "\n"):find("net.minecraft.world.item.Item", 1, true) ~= nil, "NeoForge item should generate")
	assert_equal(minecraft_dev.generate_minecraft_class({ root = root, platform = "forge", kind = "block", class_name = "test.block.OldBlock", minecraft_version = "1.16.5", open = false }).error.code, "minecraft_class_exists", "existing Minecraft class should not be overwritten")
	assert_equal(minecraft_dev.generate_minecraft_class({ root = root, platform = "fabric", kind = "packet", class_name = "test.Bad", open = false }).error.code, "minecraft_class_kind_invalid", "unsupported platform class kind should fail")
	assert_equal(minecraft_dev.generate_minecraft_class({ root = root, source_root = "../outside", platform = "fabric", kind = "block", class_name = "test.Bad", open = false }).error.code, "minecraft_source_root_invalid", "class generation should reject source roots outside the project")

	vim.api.nvim_create_augroup("java_spotbugs", { clear = false })
	vim.api.nvim_create_augroup("java_spotbugs_post", { clear = false })
	vim.api.nvim_buf_delete(java_buffer, { force = true })
	vim.api.nvim_buf_delete(kotlin_buffer, { force = true })
	vim.api.nvim_buf_delete(kotlin_single_buffer, { force = true })
	vim.fn.delete(root, "rf")
end

function _G.MinecraftDevTestSourceInsight()
	local minecraft_dev = require("minecraft-dev")
	assert_equal(vim.fn.exists(":MinecraftDevRefreshSourceInsight"), 2, "source insight refresh command should be registered")
	assert_equal(vim.fn.exists(":MinecraftDevDiagnoseEventListeners"), 2, "event listener diagnostics command should be registered")
	local root = vim.fn.tempname()
	local source = root .. "/src/main/java/test"
	vim.fn.mkdir(root .. "/.git", "p")
	vim.fn.mkdir(source, "p")
	local path = source .. "/Insight.java"
	vim.fn.writefile({
		"package test;",
		"import org.bukkit.ChatColor;",
		"import org.bukkit.event.EventHandler;",
		"import org.bukkit.event.Listener;",
		"class MissingListener {",
		"  @EventHandler public void onEvent(org.bukkit.event.Event event) {}",
		"  String color = ChatColor.RED.toString();",
		"}",
		"class GoodListener implements Listener {",
		"  @EventHandler public void onEvent(org.bukkit.event.Event event) {}",
		"  String ignored = Palette.RED.toString();",
		"}",
	}, path)
	local buffer = vim.fn.bufadd(path)
	vim.fn.bufload(buffer)
	vim.bo[buffer].filetype = "java"
	local refreshed = minecraft_dev.refresh_source_insight({ buffer = buffer, root = root })
	assert_equal(refreshed.status, "refreshed", "source insight should refresh")
	assert_equal(#refreshed.highlights, 1, "only imported Minecraft color classes should highlight")
	assert_equal(refreshed.highlights[1].name, "RED", "Minecraft color name should be reported")
	assert_equal(refreshed.highlights[1].color, "#FF5555", "Minecraft standard red should use the upstream color")
	assert_equal(#refreshed.diagnostics, 1, "only the class missing Listener should diagnose")
	assert_equal(refreshed.diagnostics[1].code, "listener_interface_missing", "missing Listener should use a stable code")
	assert_equal(minecraft_dev.diagnose_event_listeners({ buffer = buffer, root = root }).diagnostics[1].platform, "bukkit", "Bukkit handler import should select Bukkit Listener")

	local kotlin_path = root .. "/src/main/kotlin/test/Bungee.kt"
	vim.fn.mkdir(root .. "/src/main/kotlin/test", "p")
	vim.fn.writefile({
		"package test",
		"import net.md_5.bungee.event.EventHandler",
		"class Bungee {",
		"  @EventHandler fun onEvent(event: com.example.Event) {}",
		"}",
	}, kotlin_path)
	local kotlin_buffer = vim.fn.bufadd(kotlin_path)
	vim.fn.bufload(kotlin_buffer)
	vim.bo[kotlin_buffer].filetype = "kotlin"
	local kotlin_diagnostics = minecraft_dev.diagnose_event_listeners({ buffer = kotlin_buffer, root = root })
	assert_equal(kotlin_diagnostics.diagnostics[1].platform, "bungeecord", "Kotlin BungeeCord handlers should diagnose")

	local source_insight = require("minecraft-dev.source_insight")
	source_insight.setup()
	local first_group = vim.api.nvim_create_augroup("MinecraftDevSourceInsight", { clear = false })
	source_insight.setup()
	assert_equal(vim.api.nvim_create_augroup("MinecraftDevSourceInsight", { clear = false }), first_group, "source insight setup should be idempotent")

	vim.api.nvim_create_augroup("java_spotbugs", { clear = false })
	vim.api.nvim_create_augroup("java_spotbugs_post", { clear = false })
	vim.api.nvim_buf_delete(buffer, { force = true })
	vim.api.nvim_buf_delete(kotlin_buffer, { force = true })
	vim.fn.delete(root, "rf")
end

local function run()
	require("minecraft-dev").setup()
	test_command_parse_success()
	test_command_parse_failure()
	test_command_entrypoints()
	test_wizard_cancellation()
	test_command_platform_generation()
	test_build_matrix_definition()
	test_platform_registry()
	test_architectury_generation()
	test_custom_v3_local_template()
	test_custom_paper_version_values()
	test_custom_paper_build_option_wizard()
	test_custom_hidden_group_visibility()
	test_custom_paper_version_wizard()
	test_custom_paper_derivations()
	test_custom_velocity_java_derivation()
	test_custom_template_discovery()
	test_custom_velocity_directives()
	test_custom_archive_provider()
	test_custom_remote_provider()
	test_custom_property_derivations()
	test_custom_run_config_finalizers()
	test_custom_wrapper_version_finalizer()
	test_custom_finalizer_failure_cleanup()
	test_custom_finalizer_cancellation()
	test_custom_fabric_version_wizard()
	test_fabric_online_version_parser()
	test_forge_family_generation()
	test_forge_version_data_and_wizard()
	test_neoforge_version_data_and_wizard()
	test_neoforge_versioned_generation()
	test_forge_versioned_generation()
	test_additional_plugin_platforms()
	test_waterfall_version_resolution()
	test_waterfall_resolution_lifecycle()
	test_proxy_and_sponge_generation_modes()
	test_velocity_generation_modes()
	test_gradle_wrapper_generation_isolated_from_project()
	test_spigot_maven_generation()
	test_spigot_calendar_generation()
	test_paper_manifest_generation()
	test_project_validation()
	test_project_generation_results()
	test_noninteractive_paper_generation()
	test_noninteractive_fabric_generation()
	test_noninteractive_fabric_kotlin_generation()
	test_fabric_advanced_generation_options()
	test_config_normalize_legacy_debug()
	test_config_normalize_nested_override()
	test_resolve_path_with_default()
	test_fabric_metadata_client_only()
	test_fabric_metadata_mixins()
	test_paper_kotlin_templates()
	test_paper_gradle_project_version()
	test_translation_json_sorting()
	test_translation_lang_and_template_sorting()
	test_translation_buffer_and_command()
	test_translation_file_diagnostics()
	test_translation_index_navigation_and_completion()
	test_translation_source_diagnostics_and_navigation()
	test_bukkit_manifest_main_references()
	_G.MinecraftDevTestBukkitManifestStructureAndDependencies()
	_G.MinecraftDevTestBukkitManifestStructureAndDependencies = nil
	_G.MinecraftDevTestForgeManifestMetadata()
	_G.MinecraftDevTestForgeManifestMetadata = nil
	_G.MinecraftDevTestFabricManifestMetadata()
	_G.MinecraftDevTestFabricManifestMetadata = nil
	_G.MinecraftDevTestMixinConfigMetadata()
	_G.MinecraftDevTestMixinConfigMetadata = nil
	_G.MinecraftDevTestNbtEditing()
	_G.MinecraftDevTestNbtEditing = nil
	_G.MinecraftDevTestMappingsAndAccessRules()
	_G.MinecraftDevTestMappingsAndAccessRules = nil
	_G.MinecraftDevTestMixinSourceActions()
	_G.MinecraftDevTestMixinSourceActions = nil
	_G.MinecraftDevTestSourceGeneration()
	_G.MinecraftDevTestSourceGeneration = nil
	_G.MinecraftDevTestSourceInsight()
	_G.MinecraftDevTestSourceInsight = nil
	print("test_refactor.lua: ok")
end

run()
