local M = {}
local architectury_versions = require("minecraft-dev.generators.architectury").versions

local function project_spec(overrides)
	return vim.tbl_extend("force", {
		group_id = "dev.minecraft",
		artifact_id = "matrixproject",
		package_name = "dev.minecraft.matrixproject",
		main_class = "MatrixProject",
		plugin_version = "1.0.0",
	}, overrides)
end

M.cases = {
	{
		name = "paper-java-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1" },
		spec = project_spec({ platform = "paper", build_system = "gradle", minecraft_version = "1.21.8", language = "java" }),
	},
	{
		name = "paper-kotlin-maven",
		toolchain = { jdk = 21, maven = true },
		spec = project_spec({ platform = "paper", build_system = "maven", minecraft_version = "1.21.8", language = "kotlin" }),
	},
	{
		name = "spigot-calendar-java-gradle",
		toolchain = { jdk = 25, gradle = "9.5.0" },
		spec = project_spec({ platform = "spigot", build_system = "gradle", minecraft_version = "26.1.2", language = "java" }),
	},
	{
		name = "spigot-calendar-kotlin-gradle",
		toolchain = { jdk = 25, gradle = "9.5.0", kotlin = "2.4.10" },
		spec = project_spec({ platform = "spigot", build_system = "gradle", minecraft_version = "26.1.2", language = "kotlin" }),
	},
	{
		name = "spigot-calendar-java-maven",
		toolchain = { jdk = 25, maven = true },
		spec = project_spec({ platform = "spigot", build_system = "maven", minecraft_version = "26.1.2", language = "java" }),
	},
	{
		name = "spigot-calendar-kotlin-maven",
		toolchain = { jdk = 25, maven = true, kotlin = "2.4.10" },
		spec = project_spec({ platform = "spigot", build_system = "maven", minecraft_version = "26.1.2", language = "kotlin" }),
	},
	{
		name = "spigot-kotlin-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1", kotlin = "2.1.20" },
		spec = project_spec({ platform = "spigot", build_system = "gradle", minecraft_version = "1.21.11", language = "kotlin" }),
	},
	{
		name = "velocity-java-maven",
		toolchain = { jdk = 21, maven = true },
		spec = project_spec({ platform = "velocity", build_system = "maven", minecraft_version = "3.5.0-SNAPSHOT", language = "java" }),
	},
	{
		name = "velocity-java-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1" },
		spec = project_spec({ platform = "velocity", build_system = "gradle", minecraft_version = "3.5.0-SNAPSHOT", language = "java" }),
	},
	{
		name = "velocity-kotlin-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1", kotlin = "2.1.20" },
		spec = project_spec({ platform = "velocity", build_system = "gradle", minecraft_version = "3.5.0-SNAPSHOT", language = "kotlin" }),
	},
	{
		name = "velocity-kotlin-maven",
		toolchain = { jdk = 21, maven = true, kotlin = "2.1.20" },
		spec = project_spec({ platform = "velocity", build_system = "maven", minecraft_version = "3.5.0-SNAPSHOT", language = "kotlin" }),
	},
	{
		name = "velocity-kotlin-ap-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1", kotlin = "2.1.20" },
		spec = project_spec({ platform = "velocity", build_system = "gradle", minecraft_version = "3.5.0-SNAPSHOT", language = "kotlin", use_annotation_processor = true }),
	},
	{
		name = "velocity-kotlin-ap-maven",
		toolchain = { jdk = 21, maven = true, kotlin = "2.1.20" },
		spec = project_spec({ platform = "velocity", build_system = "maven", minecraft_version = "3.5.0-SNAPSHOT", language = "kotlin", use_annotation_processor = true }),
	},
	{
		name = "bungeecord-java-gradle",
		toolchain = { jdk = 17, gradle = "8.12.1" },
		spec = project_spec({ platform = "bungeecord", build_system = "gradle", minecraft_version = "1.21-R0.3", language = "java" }),
	},
	{
		name = "bungeecord-kotlin-gradle",
		toolchain = { jdk = 17, gradle = "8.12.1", kotlin = "2.1.20" },
		spec = project_spec({ platform = "bungeecord", build_system = "gradle", minecraft_version = "1.21-R0.3", language = "kotlin" }),
	},
	{
		name = "bungeecord-java-maven",
		toolchain = { jdk = 17, maven = true },
		spec = project_spec({ platform = "bungeecord", build_system = "maven", minecraft_version = "1.21-R0.3", language = "java" }),
	},
	{
		name = "bungeecord-kotlin-maven",
		toolchain = { jdk = 17, maven = true, kotlin = "2.1.20" },
		spec = project_spec({ platform = "bungeecord", build_system = "maven", minecraft_version = "1.21-R0.3", language = "kotlin" }),
	},
	{
		name = "waterfall-java-gradle",
		toolchain = { jdk = 17, gradle = "8.12.1" },
		spec = project_spec({ platform = "waterfall", build_system = "gradle", minecraft_version = "1.21", waterfall_version = "1.21-R0.5-SNAPSHOT", language = "java" }),
	},
	{
		name = "waterfall-kotlin-gradle",
		toolchain = { jdk = 17, gradle = "8.12.1", kotlin = "2.1.20" },
		spec = project_spec({ platform = "waterfall", build_system = "gradle", minecraft_version = "1.21", waterfall_version = "1.21-R0.5-SNAPSHOT", language = "kotlin" }),
	},
	{
		name = "waterfall-java-maven",
		toolchain = { jdk = 17, maven = true },
		spec = project_spec({ platform = "waterfall", build_system = "maven", minecraft_version = "1.21", waterfall_version = "1.21-R0.5-SNAPSHOT", language = "java" }),
	},
	{
		name = "waterfall-kotlin-maven",
		toolchain = { jdk = 17, maven = true, kotlin = "2.1.20" },
		spec = project_spec({ platform = "waterfall", build_system = "maven", minecraft_version = "1.21", waterfall_version = "1.21-R0.5-SNAPSHOT", language = "kotlin" }),
	},
	{
		name = "sponge-java-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1" },
		spec = project_spec({ platform = "sponge", build_system = "gradle", minecraft_version = "11.0.0", language = "java", license = "MIT" }),
	},
	{
		name = "sponge-kotlin-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1", kotlin = "2.1.20" },
		spec = project_spec({ platform = "sponge", build_system = "gradle", minecraft_version = "11.0.0", language = "kotlin", license = "MIT" }),
	},
	{
		name = "sponge-java-maven",
		toolchain = { jdk = 21, maven = true },
		spec = project_spec({ platform = "sponge", build_system = "maven", minecraft_version = "11.0.0", language = "java", license = "MIT" }),
	},
	{
		name = "sponge-kotlin-maven",
		toolchain = { jdk = 21, maven = true, kotlin = "2.1.20" },
		spec = project_spec({ platform = "sponge", build_system = "maven", minecraft_version = "11.0.0", language = "kotlin", license = "MIT" }),
	},
	{
		name = "fabric-java-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1", loom = "1.10-SNAPSHOT" },
		spec = project_spec({
			platform = "fabric",
			build_system = "gradle",
			minecraft_version = "1.21.1",
			language = "java",
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
		}),
	},
	{
		name = "fabric-kotlin-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1", loom = "1.10-SNAPSHOT", kotlin = "2.4.10" },
		spec = project_spec({
			platform = "fabric",
			build_system = "gradle",
			minecraft_version = "1.21.1",
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
		}),
	},
	{
		name = "fabric-java-yarn-no-api",
		toolchain = { jdk = 21, gradle = "8.12.1", loom = "1.10.5" },
		spec = project_spec({
			platform = "fabric",
			build_system = "gradle",
			minecraft_version = "1.21.1",
			language = "java",
			side = "both",
			use_official_mappings = false,
			yarn_version = "1.21.1+build.3",
			use_fabric_api = false,
			split_sources = false,
			generate_datagen = false,
			use_mixins = true,
			fabric_version_data = {
				loader = "0.16.14",
				fabric_api = "0.116.15+1.21.1",
				yarn = nil,
				kotlin_loader = "1.13.13+kotlin.2.4.10",
				loom_version = "1.10.5",
				gradle_version = "8.12.1",
			},
		}),
	},
	{
		name = "fabric-kotlin-26.1-split",
		toolchain = { jdk = 25, gradle = "9.6.1", loom = "1.17.17", kotlin = "2.4.10" },
		spec = project_spec({
			platform = "fabric",
			build_system = "gradle",
			minecraft_version = "26.1.2",
			language = "kotlin",
			side = "both",
			use_official_mappings = true,
			use_fabric_api = true,
			split_sources = true,
			generate_datagen = true,
			use_mixins = true,
			client_mixins = true,
			fabric_version_data = {
				loader = "0.19.3",
				fabric_api = "0.155.2+26.1.2",
				kotlin_loader = "1.13.13+kotlin.2.4.10",
				loom_version = "1.17.17",
				gradle_version = "9.6.1",
			},
		}),
	},
	{
		name = "forge-java-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1" },
		spec = project_spec({
			platform = "forge",
			build_system = "gradle",
			minecraft_version = "1.21.1",
			language = "java",
			artifact_id = "matrixmod",
			package_name = "dev.minecraft.matrixmod",
			loader_version = "52.1.0",
			parchment_version = "2024.11.17",
			use_mixins = true,
		}),
	},
	{
		name = "neoforge-java-gradle",
		toolchain = { jdk = 21, gradle = "8.12.1" },
		spec = project_spec({
			platform = "neoforge",
			build_system = "gradle",
			minecraft_version = "1.21.1",
			language = "java",
			artifact_id = "matrixmod",
			package_name = "dev.minecraft.matrixmod",
			loader_version = "21.1.209",
			parchment_version = "2024.11.17",
			use_mixins = true,
		}),
	},
	{
		name = "architectury-java-gradle",
		toolchain = { jdk = 21, gradle = architectury_versions.gradle, loom = architectury_versions.loom },
		spec = project_spec({
			platform = "architectury",
			build_system = "gradle",
			minecraft_version = "1.20.1",
			language = "java",
			artifact_id = "matrixmod",
			package_name = "dev.minecraft.matrixmod",
			fabric_loader_version = "0.16.14",
			fabric_api_version = "0.92.6+1.20.1",
			forge_version = "47.4.0",
			architectury_api_version = "9.2.14",
		}),
	},
}

function M.classify_failure(output, timed_out)
	if timed_out then return "timeout" end
	local text = (output or ""):lower()
	for _, marker in ipairs({
		"could not resolve host",
		"unknownhostexception",
		"network is unreachable",
		"connection timed out",
		"connection refused",
		"read timed out",
		"connection reset",
		"failed to connect",
		"temporary failure in name resolution",
		"could not transfer artifact",
		"test of distribution url",
	}) do
		if text:find(marker, 1, true) then return "network_failure" end
	end
	for _, marker in ipairs({
		"could not resolve all files",
		"could not resolve dependencies",
		"could not resolve plugin artifact",
		"dependencyresolutionexception",
	}) do
		if text:find(marker, 1, true) then return "dependency_resolution_failed" end
	end
	if text:match("could not find [%w_.-]+:[%w_.-]+:[%w_.+-]+") then return "dependency_resolution_failed" end
	return "build_failed"
end

function M.classify_process(process)
	if process.timed_out then return "timeout" end
	if process.start_failed then return "process_start_failed" end
	if process.code == 0 then return "passed" end
	local output = (process.stdout or "") .. "\n" .. (process.stderr or "")
	return M.classify_failure(output, false)
end

function M.classify_generation_error(err)
	if not err then return "generation_failed" end
	if err.code == "jdk_mismatch" then return "jdk_mismatch" end
	if err.code == "gradle_missing" or err.code == "tool_missing" then return "tool_missing" end
	if err.code == "gradle_wrapper_start_failed" or err.code == "process_start_failed" then return "process_start_failed" end
	if err.code == "tool_failure" then return "tool_failure" end
	if err.code == "timeout" then return "timeout" end
	if err.detail then
		local detail = type(err.detail) == "string" and err.detail or vim.inspect(err.detail)
		local classified = M.classify_failure(detail, false)
		if classified ~= "build_failed" then return classified end
	end
	return "generation_failed"
end

local function run_process(command, cwd, timeout_ms, env)
	local state = { done = false, timed_out = false }
	local handle
	local started, start_error = pcall(function()
		handle = vim.system(command, { cwd = cwd, text = true, env = env }, vim.schedule_wrap(function(result)
			state.result = result
			state.done = true
		end))
	end)
	if not started then return { code = -1, stderr = tostring(start_error), start_failed = true } end
	local timer = vim.uv.new_timer()
	timer:start(timeout_ms, 0, function()
		if state.done then return end
		state.timed_out = true
		handle:kill(15)
	end)
	vim.wait(timeout_ms + 10000, function() return state.done end, 100)
	timer:stop()
	timer:close()
	if not state.done then return { code = -1, stderr = "process did not exit after termination", timed_out = true } end
	state.result.timed_out = state.timed_out
	return state.result
end

local function java_home()
	if vim.env.MINECRAFT_DEV_JAVA_HOME and vim.env.MINECRAFT_DEV_JAVA_HOME ~= "" then
		return vim.env.MINECRAFT_DEV_JAVA_HOME
	end
	if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= "" then return vim.env.JAVA_HOME end
	local executable = vim.fn.exepath("java")
	local resolved = executable ~= "" and vim.uv.fs_realpath(executable) or nil
	return resolved and vim.fs.dirname(vim.fs.dirname(resolved)) or nil
end

function M.select_cases(requested)
	if not requested or requested == "" then return M.cases end
	local names = {}
	for _, value in ipairs(vim.split(requested, ",", { trimempty = false })) do
		local name = vim.trim(value)
		if name ~= "" then names[name] = true end
	end
	if vim.tbl_isempty(names) then return nil, { code = "matrix_cases_empty" } end
	local known = {}
	for _, case in ipairs(M.cases) do known[case.name] = true end
	local unknown = {}
	for name in pairs(names) do
		if not known[name] then table.insert(unknown, name) end
	end
	if #unknown > 0 then
		table.sort(unknown)
		return nil, { code = "matrix_cases_unknown", cases = unknown }
	end
	return vim.tbl_filter(function(case) return names[case.name] == true end, M.cases), nil
end

local function inside(base, candidate)
	base = vim.fs.normalize(base)
	candidate = vim.fs.normalize(candidate)
	return candidate == base or vim.startswith(candidate, base .. "/")
end

local function canonical_future_path(path)
	local suffix = {}
	local current = vim.fs.normalize(path)
	while not vim.uv.fs_lstat(current) do
		local parent = vim.fs.dirname(current)
		if parent == current then break end
		table.insert(suffix, 1, vim.fs.basename(current))
		current = parent
	end
	local stat = vim.uv.fs_lstat(current)
	local resolved = vim.uv.fs_realpath(current)
	if stat and stat.type == "link" and not resolved then
		return nil, { code = "matrix_path_unresolved_symlink", path = current }
	end
	resolved = resolved or current
	for _, segment in ipairs(suffix) do resolved = vim.fs.joinpath(resolved, segment) end
	return vim.fs.normalize(resolved), nil
end

function M.validate_report_path(root, report_path, cases)
	local report_lstat = vim.uv.fs_lstat(report_path)
	if report_lstat and report_lstat.type == "link" then
		return nil, { code = "matrix_report_symlink" }
	end
	local real_root, root_error = canonical_future_path(root)
	if not real_root then return nil, root_error end
	local real_report_path, report_error = canonical_future_path(report_path)
	if not real_report_path then return nil, report_error end
	for _, case in ipairs(cases) do
		if inside(vim.fs.joinpath(real_root, case.name), real_report_path) then
			return nil, { code = "matrix_report_inside_case", case = case.name }
		end
	end
	return true, nil
end

local function build_command(case, cache)
	if case.spec.build_system == "maven" then
		return { "mvn", "-B", "-ntp", "-Dmaven.repo.local=" .. cache.maven, "package" }
	end
	return { "./gradlew", "--gradle-user-home", cache.gradle, "build", "--no-daemon", "--console=plain" }
end

local function case_java_home(expected_jdk, default_home)
	if not expected_jdk then return default_home end
	local configured = vim.env["MINECRAFT_DEV_JAVA_" .. expected_jdk .. "_HOME"]
	if configured and vim.fn.isdirectory(configured) == 1 then return configured end
	local conventional = "/usr/lib/jvm/java-" .. expected_jdk .. "-openjdk"
	if vim.fn.isdirectory(conventional) == 1 then return conventional end
	return default_home
end

function M.run()
	local cases, selection_error = M.select_cases(vim.env.MINECRAFT_DEV_MATRIX_CASES)
	if not cases then error(vim.inspect(selection_error)) end
	local owns_root = not vim.env.MINECRAFT_DEV_MATRIX_ROOT or vim.env.MINECRAFT_DEV_MATRIX_ROOT == ""
	local root = owns_root and vim.fn.tempname() or vim.env.MINECRAFT_DEV_MATRIX_ROOT
	local report_path = vim.env.MINECRAFT_DEV_MATRIX_REPORT or (vim.fn.tempname() .. ".json")
	root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
	report_path = vim.fn.fnamemodify(report_path, ":p")
	vim.fn.mkdir(root, "p")
	local report_valid, report_error = M.validate_report_path(root, report_path, cases)
	if not report_valid then
		if owns_root then vim.fn.delete(root, "d") end
		error(vim.inspect(report_error))
	end
	local timeout_ms = tonumber(vim.env.MINECRAFT_DEV_MATRIX_TIMEOUT_MS) or 600000
	local generation_timeout_ms = tonumber(vim.env.MINECRAFT_DEV_MATRIX_GENERATION_TIMEOUT_MS) or 120000
	local keep_projects = vim.env.MINECRAFT_DEV_MATRIX_KEEP == "1"
	local cache = {
		gradle = vim.env.MINECRAFT_DEV_GRADLE_USER_HOME or vim.fn.expand("~/.gradle"),
		maven = vim.env.MINECRAFT_DEV_MAVEN_REPO or vim.fn.expand("~/.m2/repository"),
	}
	local jdk = java_home()
	vim.fn.mkdir(cache.gradle, "p")
	vim.fn.mkdir(cache.maven, "p")
	local report = {
		started_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		root = root,
		java_home = jdk,
		cache = cache,
		cases = {},
	}
	local env = {
		JAVA_HOME = jdk,
		PATH = vim.env.PATH,
		GRADLE_USER_HOME = cache.gradle,
	}
	local original_java_home = vim.env.JAVA_HOME
	local original_gradle_home = vim.env.GRADLE_USER_HOME
	local java_executable = jdk and vim.fs.joinpath(jdk, "bin", "java") or "java"
	local java_version = run_process({ java_executable, "-version" }, root, 15000, env)
	local java_output = (java_version.stdout or "") .. "\n" .. (java_version.stderr or "")
	local java_major = tonumber(java_output:match('version "1%.(%d+)')) or tonumber(java_output:match('version "(%d+)'))
	local gradle_version = run_process({ "gradle", "--version" }, root, 15000, env)
	local gradle_output = (gradle_version.stdout or "") .. "\n" .. (gradle_version.stderr or "")
	local maven_version = run_process({ "mvn", "--version" }, root, 15000, env)
	local maven_output = (maven_version.stdout or "") .. "\n" .. (maven_version.stderr or "")
	report.tools = {
		java = { executable = java_executable, major = java_major, output = java_output:sub(1, 1000) },
		gradle = {
			executable = vim.fn.exepath("gradle"),
			version = gradle_output:match("Gradle%s+([%w._+-]+)"),
			output = gradle_output:sub(1, 1000),
		},
		maven = {
			executable = vim.fn.exepath("mvn"),
			version = maven_output:match("Apache Maven%s+([%w._+-]+)"),
			output = maven_output:sub(1, 1000),
		},
	}
	local git_commit = run_process({ "git", "rev-parse", "HEAD" }, vim.fn.getcwd(), 15000, env)
	local git_status = run_process({ "git", "status", "--porcelain" }, vim.fn.getcwd(), 15000, env)
	report.source = {
		commit = git_commit.code == 0 and vim.trim(git_commit.stdout or "") or nil,
		dirty = git_status.code == 0 and vim.trim(git_status.stdout or "") ~= "" or nil,
		status = git_status.code == 0 and git_status.stdout or nil,
	}
	local cases_ok, cases_error = xpcall(function()
	for _, case in ipairs(cases) do
		local started_at = vim.uv.hrtime()
		local directory = vim.fs.joinpath(root, case.name)
		local spec = vim.deepcopy(case.spec)
		spec.directory = directory
		local selected_java_home = case_java_home(case.toolchain.jdk, jdk)
		local case_env = vim.tbl_extend("force", {}, env)
		local case_java_major
		local case_java_error
		if selected_java_home then
			case_env.JAVA_HOME = selected_java_home
			case_env.PATH = vim.fs.joinpath(selected_java_home, "bin") .. ":" .. vim.env.PATH
			local case_java = run_process({ vim.fs.joinpath(selected_java_home, "bin", "java"), "-version" }, root, 15000, case_env)
			local case_java_output = (case_java.stdout or "") .. "\n" .. (case_java.stderr or "")
			case_java_major = tonumber(case_java_output:match('version "1%.(%d+)')) or tonumber(case_java_output:match('version "(%d+)'))
			case_java_error = case_java.timed_out and { code = "timeout", detail = case_java_output }
				or (case_java.start_failed and { code = "process_start_failed", detail = case_java.stderr })
				or (case_java.code ~= 0 and { code = "tool_failure", detail = case_java_output })
			vim.env.JAVA_HOME = selected_java_home
		else
			case_java_error = { code = "tool_missing", executable = "java", expected_jdk = case.toolchain.jdk }
		end
		vim.env.GRADLE_USER_HOME = cache.gradle
		local operation
		if case_java_error then
			operation = { status = "failed", result = { error = case_java_error } }
		elseif case.toolchain.jdk and case_java_major ~= case.toolchain.jdk then
			operation = { status = "failed", result = { error = { code = "jdk_mismatch", expected = case.toolchain.jdk, actual = case_java_major } } }
		else
			vim.notify("[matrix] generating " .. case.name)
			operation = require("minecraft-dev.project").generate(spec)
		end
		if operation.status == "pending" then
			vim.wait(generation_timeout_ms, function() return operation.status ~= "pending" end, 100)
		end
		local result = { name = case.name, spec = case.spec, toolchain = case.toolchain, directory = directory, java_home = selected_java_home }
		if operation.status == "pending" then
			operation.cancel()
			vim.wait(10000, function() return operation.status ~= "pending" end, 100)
			result.status = "timeout"
		elseif operation.status ~= "generated" then
			result.error = operation.result and operation.result.error
			result.status = M.classify_generation_error(result.error)
		else
			local command = build_command(case, cache)
			result.command = command
			local executable = command[1] == "./gradlew"
				and vim.fn.filereadable(vim.fs.joinpath(directory, "gradlew")) == 1
				or vim.fn.executable(command[1]) == 1
			if not executable then
				result.status = "tool_missing"
				result.error = { executable = command[1] }
			else
				vim.notify("[matrix] building " .. case.name)
				local process = run_process(command, directory, timeout_ms, case_env)
				result.exit_code = process.code
				result.status = M.classify_process(process)
				if result.status ~= "passed" then
					local output = (process.stdout or "") .. "\n" .. (process.stderr or "")
					result.output = output:sub(-4000)
				end
			end
		end
		result.duration_ms = math.floor((vim.uv.hrtime() - started_at) / 1000000)
		table.insert(report.cases, result)
		vim.notify(string.format("[matrix] %s: %s", case.name, result.status))
	end
	end, debug.traceback)
	vim.env.JAVA_HOME = original_java_home
	vim.env.GRADLE_USER_HOME = original_gradle_home
	if not cases_ok then error(cases_error) end
	report.finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
	report.report_path = report_path
	report.failed = vim.tbl_filter(function(result) return result.status ~= "passed" end, report.cases)
	local report_ready, report_prepare_error = pcall(vim.fn.mkdir, vim.fs.dirname(report_path), "p")
	local report_written = report_ready and vim.fn.writefile({ vim.json.encode(report) }, report_path) == 0
	if not report_written then
		error(vim.inspect({ code = "matrix_report_write_failed", detail = report_prepare_error }))
	end
	if not keep_projects and #report.failed == 0 then
		for _, result in ipairs(report.cases) do vim.fn.delete(result.directory, "rf") end
		if owns_root then vim.fn.delete(root, "d") end
	end
	return report
end

return M
