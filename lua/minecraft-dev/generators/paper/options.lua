local M = {}

---@param language? ProgrammingLanguage
---@param callback fun(language: ProgrammingLanguage)
function M.with_language(language, callback)
	if language then
		callback(language)
		return
	end
	require("minecraft-dev.util.make_your_choice").which_paper_language(callback)
end

return M
