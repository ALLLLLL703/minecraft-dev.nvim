local command_args = require("minecraft-dev.command_args")
local config = require("minecraft-dev.config")
local metadata = require("minecraft-dev.generators.fabric.metadata")
local paper_templates = require("minecraft-dev.generators.paper.templates")
local platforms = require("minecraft-dev.platforms")
local project = require("minecraft-dev.project")
local custom_templates = require("minecraft-dev.custom")
local custom_evaluator = require("minecraft-dev.custom.evaluator")
local fabric_version_data = require("minecraft-dev.generators.fabric.version_data")
local gradle = require("minecraft-dev.util.gradle")

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
	vim.fn.delete(template_root, "rf")
	vim.fn.delete(destination, "rf")
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
			{ type = "add_gradle_run", name = "Build", tasks = { "build" } },
			{ type = "add_maven_run", name = "Package", goals = { "package" } },
		},
	}))
	local result, err = generate_template({ provider = "local", source = template_root, directory = destination })
	assert_truthy(result ~= nil, "run config finalizers should complete")
	assert_equal(err, nil, "run config finalizers should not return an error")
	local runs = vim.json.decode(read_file(destination .. "/.nvim/minecraft-dev-runs.json"))
	assert_equal(runs[1].type, "gradle", "Gradle run finalizer should persist its type")
	assert_equal(runs[1].args, { "build" }, "Gradle run finalizer should persist tasks")
	assert_equal(runs[2].type, "maven", "Maven run finalizer should persist its type")
	assert_equal(runs[2].args, { "package" }, "Maven run finalizer should persist goals")
	assert_equal(imported_root, destination, "import finalizers should receive the committed destination")
	vim.api.nvim_del_augroup_by_id(import_group)
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

local function test_fabric_online_version_parser()
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
		velocity = { dependency = "velocity-api", pom_marker = "annotationProcessorPaths", source_marker = "@Plugin" },
		sponge = { dependency = "spongeapi", metadata = "src/main/resources/META-INF/sponge_plugins.json" },
	}
	for platform, expectation in pairs(expectations) do
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local ok, err = generate_project({
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
	local client_ok, client_err = generate_project(generation_spec)
	assert_equal(client_ok, true, "client-only Fabric Kotlin generation should succeed")
	assert_equal(client_err, nil, "client-only Fabric Kotlin generation should not return an error")
	assert_equal(vim.fn.filereadable(client_directory .. "/src/client/kotlin/com/example/example/mixin/ExampleModMixin.kt"), 1, "client-only mixins should use the client source set")
	assert_equal(vim.fn.filereadable(client_directory .. "/src/main/kotlin/com/example/example/mixin/ExampleModMixin.kt"), 0, "client-only mixins should not use the main source set")
	vim.fn.delete(client_directory, "rf")
	gradle.generate_gradlew = original_generate_gradlew
	vim.fn.input = original_input
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

local function run()
	require("minecraft-dev").setup()
	test_command_parse_success()
	test_command_parse_failure()
	test_platform_registry()
	test_architectury_generation()
	test_custom_v3_local_template()
	test_custom_template_discovery()
	test_custom_velocity_directives()
	test_custom_archive_provider()
	test_custom_remote_provider()
	test_custom_property_derivations()
	test_custom_run_config_finalizers()
	test_custom_finalizer_failure_cleanup()
	test_custom_finalizer_cancellation()
	test_fabric_online_version_parser()
	test_forge_family_generation()
	test_additional_plugin_platforms()
	test_gradle_wrapper_generation_isolated_from_project()
	test_spigot_maven_generation()
	test_paper_manifest_generation()
	test_project_validation()
	test_project_generation_results()
	test_noninteractive_paper_generation()
	test_noninteractive_fabric_generation()
	test_noninteractive_fabric_kotlin_generation()
	test_config_normalize_legacy_debug()
	test_config_normalize_nested_override()
	test_resolve_path_with_default()
	test_fabric_metadata_client_only()
	test_fabric_metadata_mixins()
	test_paper_kotlin_templates()
	test_paper_gradle_project_version()
	print("test_refactor.lua: ok")
end

run()
