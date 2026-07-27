local M = {}
local notify = require("minecraft-dev.util.notify")

local WRAPPER_VERSION = "8.10.2"
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
function M.generate_gradlew(project_path, system)
	if vim.fn.executable("gradle") ~= 1 then
		notify.notify(vim.log.levels.ERROR, { "gradle", "missing" })
		return
	end

	notify.notify(vim.log.levels.INFO, { "gradle", "generating" })
	local wrapper_project = vim.fn.tempname()
	vim.fn.mkdir(wrapper_project, "p")
	vim.fn.writefile({}, wrapper_project .. "/settings.gradle")
	local run_system = system or vim.system

	run_system({ "gradle", "wrapper", "--gradle-version", WRAPPER_VERSION }, { cwd = wrapper_project }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.fn.delete(wrapper_project, "rf")
				notify.notify(vim.log.levels.ERROR, { "gradle", "failed" }, result.stderr or "")
				return
			end
			local ok, err = copy_wrapper(wrapper_project, project_path)
			vim.fn.delete(wrapper_project, "rf")
			if not ok then
				notify.notify(vim.log.levels.ERROR, { "gradle", "failed" }, err or "")
				return
			end
			notify.notify(vim.log.levels.INFO, { "gradle", "success" })
		end)
	end)
end

return M
