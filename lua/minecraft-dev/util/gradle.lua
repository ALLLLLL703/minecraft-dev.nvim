local M = {}

---@param project_path string
function M.generate_gradlew(project_path)
	if not vim.fn.executable("gradle") then
		vim.notigy("Gradle is not installed or not in PATH", vim.log.levels.ERROR)
		return
	end

	vim.notify("Generating Gradle Wrapper...", vim.log.levels.INFO)

	vim.system({ "gradle", "wrapper" }, { cwd = project_path }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.notify("Failed to generate Gradle Wrapper: " .. (result.stderr or ""), vim.log.levels.ERROR)
				return
			end
			vim.notify("Gradle Wrapper generated successfully.", vim.log.levels.INFO)
		end)
	end)
end

return M
