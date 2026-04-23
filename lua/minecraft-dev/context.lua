local M = {}
---@class ProjectContext
---@field groupId string
---@field artifactId string,
---@field main string
---@field package string
---@field path? string
---@field lang? ProgrammingLanguage
---@field version? string
---@field package_path? string

---@type ProjectContext
DefaultProjectContext = {
	groupId = "com.example",
	artifactId = "demo",
	main = "Main",
	lang = "java",
	version = "1.21.11",
	package = "com.example.demo",
}

---@type ProjectContext
local prompt_lines = {
	groupId = "groupId?",
	main = "main class name?",
	artifactId = "artifactId?",
	package = "",
}

---@param prompt string
---@param default string
---@param completion string | vim.lsp.inline_completion.Completor
---@return any
local function ui_input_sync(prompt, default, completion)
	local co = coroutine.running()
	vim.ui.input({ prompt = prompt, default = default, completion = completion or nil }, function(input)
		coroutine.resume(co, input)
	end)
	return coroutine.yield()
end

---@param input string
---@param default string
---@return string
function Not_empty_or(input, default)
	if input == nil or input:match("^%s*$") then
		return default
	end
	return input
end

---@return ProjectContext
function M.collect()
	local groupId = ""
	vim.ui.input({ default = DefaultProjectContext.groupId, prompt = prompt_lines.groupId }, function(input)
		groupId = Not_empty_or(input, DefaultProjectContext.groupId)
	end)
	local artifactId = ""
	vim.ui.input({ default = DefaultProjectContext.artifactId, prompt = prompt_lines.artifactId }, function(input)
		artifactId = Not_empty_or(input, DefaultProjectContext.artifactId)
	end)
	local main = ""
	vim.ui.input({ default = DefaultProjectContext.main, prompt = prompt_lines.main }, function(input)
		main = Not_empty_or(input, DefaultProjectContext.main)
	end)

	return {
		groupId = groupId,
		artifactId = artifactId,
		main = main,
		package = groupId .. "." .. artifactId,
	}
end

return M
