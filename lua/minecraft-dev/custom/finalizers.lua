local M = {}
local evaluator = require("minecraft-dev.custom.evaluator")
local fs = require("minecraft-dev.util.fs")

local function write_runs(project_root, runs)
	if #runs == 0 then return end
	local directory = vim.fs.joinpath(project_root, ".nvim")
	fs.mkdir(directory)
	fs.write_file(vim.fs.joinpath(directory, "minecraft-dev-runs.json"), vim.json.encode(runs) .. "\n")
end

local function command_for(finalizer, project_root)
	if finalizer.type == "run_gradle_tasks" then
		local wrapper = vim.fs.joinpath(project_root, "gradlew")
		local executable = vim.fn.filereadable(wrapper) == 1 and wrapper or "gradle"
		local command = { executable }
		for _, task in ipairs(finalizer.tasks or {}) do
			vim.list_extend(command, vim.split(task, "%s+", { trimempty = true }))
		end
		if vim.tbl_contains(command, "wrapper") and not vim.tbl_contains(command, "--gradle-version") then
			local properties = vim.fs.joinpath(project_root, "gradle", "wrapper", "gradle-wrapper.properties")
			if vim.fn.filereadable(properties) == 1 then
				local content = table.concat(vim.fn.readfile(properties), "\n")
				local version = content:match("gradle%-([%w%.+_-]+)%-%a+%.zip")
				if version then vim.list_extend(command, { "--gradle-version", version }) end
			end
		end
		return command
	elseif finalizer.type == "git_add_all" then
		return { "git", "add", "--all" }
	elseif finalizer.type == "git_init" then
		return { "git", "init", "-q" }
	end
end

function M.emit_imports(project_root, descriptors, properties)
	for _, descriptor in ipairs(descriptors or {}) do
		if (descriptor.type == "import_gradle_project" or descriptor.type == "import_maven_project")
			and (not descriptor.condition or evaluator.expression(properties, descriptor.condition))
		then
			vim.api.nvim_exec_autocmds("User", {
				pattern = "MinecraftDevProjectGenerated",
				data = { root = project_root, build_system = descriptor.type:match("import_(.+)_project") },
			})
		end
	end
end

---@param project_root string
---@param descriptors table[]
---@param properties table
---@param callback? fun(err: table?)
---@return table?, table?
function M.execute(project_root, descriptors, properties, callback)
	callback = callback or function() end
	local finalizers = {}
	local runs = {}
	for _, descriptor in ipairs(descriptors or {}) do
		if not descriptor.condition or evaluator.expression(properties, descriptor.condition) then
			if descriptor.type == "add_gradle_run" then
				table.insert(runs, { type = "gradle", name = descriptor.name or "Gradle", args = descriptor.tasks or {} })
			elseif descriptor.type == "add_maven_run" then
				table.insert(runs, { type = "maven", name = descriptor.name or "Maven", args = descriptor.goals or descriptor.tasks or {} })
			elseif descriptor.type == "import_gradle_project" or descriptor.type == "import_maven_project" then
				-- Emitted after staging is committed to the final destination.
			elseif descriptor.type == "run_gradle_tasks" or descriptor.type == "git_add_all" or descriptor.type == "git_init" then
				table.insert(finalizers, descriptor)
			else
				return nil, { code = "unknown_finalizer", type = descriptor.type }
			end
		end
	end
	write_runs(project_root, runs)
	if #finalizers == 0 then callback(nil) return true, nil end

	local operation = { handle = nil, status = "pending", callbacks = {} }
	function operation.on_complete(completion_callback)
		if operation.result then completion_callback(operation.result) else table.insert(operation.callbacks, completion_callback) end
		return operation
	end
	local function finish(result)
		if operation.status ~= "pending" then return end
		operation.status = result.status
		operation.result = result
		for _, completion_callback in ipairs(operation.callbacks) do completion_callback(result) end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if operation.handle then operation.handle:kill(15) else callback({ code = "cancelled" }); finish({ status = "cancelled" }) end
	end
	local function run(index)
		if operation.cancel_requested then return end
		if index > #finalizers then callback(nil); finish({ status = "generated" }); return end
		local command = command_for(finalizers[index], project_root)
		operation.handle = vim.system(command, { cwd = project_root, text = true }, vim.schedule_wrap(function(result)
			if operation.cancel_requested then callback({ code = "cancelled" }); finish({ status = "cancelled" }); return end
			if result.code ~= 0 then
				local err = { code = "finalizer_failed", type = finalizers[index].type, detail = result.stderr }
				callback(err)
				finish({ status = "failed", error = err })
				return
			end
			run(index + 1)
		end))
	end
	run(1)
	return operation, nil
end

return M
