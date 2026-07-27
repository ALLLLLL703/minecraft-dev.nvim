local M = {}
local input_util = require("minecraft-dev.util.input")

---@class ProjectContext
---@field groupId string
---@field artifactId string,
---@field main string
---@field package string
---@field path? string
---@field lang? ProgrammingLanguage
---@field version? string
---@field package_path? string

---@param spec? table
---@return ProjectContext
function M.collect(spec)
	if spec then
		return {
			groupId = spec.group_id,
			artifactId = spec.artifact_id,
			main = spec.main_class,
			package = spec.package_name,
		}
	end

	local config = require("minecraft-dev").config
	local defaults = config.defaults.project
	local prompts = config.prompts.project

	local groupId = input_util.not_empty_or(vim.fn.input(prompts.group_id, defaults.group_id), defaults.group_id)

	local artifactId = input_util.not_empty_or(
		vim.fn.input(prompts.artifact_id, defaults.artifact_id),
		defaults.artifact_id
	)
	local main = input_util.not_empty_or(vim.fn.input(prompts.main_class, defaults.main_class), defaults.main_class)

	return {
		groupId = groupId,
		artifactId = artifactId,
		main = main,
		package = groupId .. "." .. artifactId,
	}
end

return M
