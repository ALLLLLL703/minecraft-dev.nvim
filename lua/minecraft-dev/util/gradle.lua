local M = {}
local notify = require("minecraft-dev.util.notify")

local WRAPPER_VERSION = "8.12.1"
local WRAPPER_FILES = {
	"gradlew",
	"gradlew.bat",
	"gradle/wrapper/gradle-wrapper.jar",
	"gradle/wrapper/gradle-wrapper.properties",
}

local function copy_wrapper(source, target)
	vim.fn.mkdir(target .. "/gradle/wrapper", "p")
	for _, relative_path in ipairs(WRAPPER_FILES) do
		local ok, err = vim.uv.fs_copyfile(source .. "/" .. relative_path, target .. "/" .. relative_path)
		if not ok then return nil, err end
	end
	vim.uv.fs_chmod(target .. "/gradlew", 493)
	return true
end

---@param project_path string
---@param system? fun(command: string[], options: table, callback: fun(result: table))
---@param wrapper_version? string
function M.generate_gradlew(project_path, system, wrapper_version)
	local operation = { status = "pending", callbacks = {} }
	function operation.on_complete(callback)
		if operation.result then callback(operation.result) else table.insert(operation.callbacks, callback) end
		return operation
	end
	local function finish(result)
		if operation.status ~= "pending" then return end
		operation.status = result.status
		operation.result = result
		for _, callback in ipairs(operation.callbacks) do callback(result) end
		operation.callbacks = {}
	end
	function operation.cancel()
		if operation.status ~= "pending" or operation.cancel_requested then return end
		operation.cancel_requested = true
		if operation.handle then
			operation.handle:kill(15)
		else
			if operation.wrapper_project then vim.fn.delete(operation.wrapper_project, "rf") end
			finish({ status = "cancelled" })
		end
	end
	if vim.fn.executable("gradle") ~= 1 then
		notify.notify(vim.log.levels.ERROR, { "gradle", "missing" })
		finish({ status = "failed", error = { code = "gradle_missing" } })
		return operation
	end

	notify.notify(vim.log.levels.INFO, { "gradle", "generating" })
	local wrapper_project = vim.fn.tempname()
	operation.wrapper_project = wrapper_project
	vim.fn.mkdir(wrapper_project, "p")
	vim.fn.writefile({}, wrapper_project .. "/settings.gradle")
	local run_system = system or vim.system

	local started, handle = pcall(run_system, { "gradle", "wrapper", "--gradle-version", wrapper_version or WRAPPER_VERSION }, { cwd = wrapper_project }, function(result)
		vim.schedule(function()
			if operation.cancel_requested then
				vim.fn.delete(wrapper_project, "rf")
				operation.wrapper_project = nil
				finish({ status = "cancelled" })
				return
			end
			if operation.status ~= "pending" then vim.fn.delete(wrapper_project, "rf") return end
			if result.code ~= 0 then
				vim.fn.delete(wrapper_project, "rf")
				notify.notify(vim.log.levels.ERROR, { "gradle", "failed" }, result.stderr or "")
				finish({ status = "failed", error = { code = "gradle_wrapper_failed", detail = result.stderr } })
				return
			end
			local ok, err = copy_wrapper(wrapper_project, project_path)
			vim.fn.delete(wrapper_project, "rf")
			operation.wrapper_project = nil
			if not ok then
				notify.notify(vim.log.levels.ERROR, { "gradle", "failed" }, err or "")
				finish({ status = "failed", error = { code = "gradle_wrapper_copy_failed", detail = err } })
				return
			end
			notify.notify(vim.log.levels.INFO, { "gradle", "success" })
			finish({ status = "generated" })
		end)
	end)
	if not started then
		vim.fn.delete(wrapper_project, "rf")
		operation.wrapper_project = nil
		finish({ status = "failed", error = { code = "gradle_wrapper_start_failed", detail = handle } })
		return operation
	end
	operation.handle = handle
	return operation
end

return M
