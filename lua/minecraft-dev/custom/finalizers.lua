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
		return vim.list_extend({ executable }, vim.deepcopy(finalizer.tasks or {}))
	elseif finalizer.type == "git_add_all" then
		return { "git", "add", "--all" }
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
				vim.api.nvim_exec_autocmds("User", { pattern = "MinecraftDevProjectGenerated", data = { root = project_root, build_system = descriptor.type:match("import_(.+)_project") } })
			elseif descriptor.type == "run_gradle_tasks" or descriptor.type == "git_add_all" then
				table.insert(finalizers, descriptor)
			else
				return nil, { code = "unknown_finalizer", type = descriptor.type }
			end
		end
	end
	write_runs(project_root, runs)
	if #finalizers == 0 then callback(nil) return nil, nil end

	local operation = { handle = nil, cancelled = false }
	function operation.cancel()
		operation.cancelled = true
		if operation.handle then operation.handle:kill(15) end
	end
	local function run(index)
		if operation.cancelled then return end
		if index > #finalizers then callback(nil) return end
		local command = command_for(finalizers[index], project_root)
		operation.handle = vim.system(command, { cwd = project_root, text = true }, vim.schedule_wrap(function(result)
			if operation.cancelled then return end
			if result.code ~= 0 then
				callback({ code = "finalizer_failed", type = finalizers[index].type, detail = result.stderr })
				return
			end
			run(index + 1)
		end))
	end
	run(1)
	return operation, nil
end

return M
