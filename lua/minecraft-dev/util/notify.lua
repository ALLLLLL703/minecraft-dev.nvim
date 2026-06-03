local M = {}

---@param path string[]
---@return string
local function resolve_message(path)
	local messages = require("minecraft-dev").config.messages or {}
	local current = messages

	for _, segment in ipairs(path) do
		current = current[segment]
		if current == nil then
			return table.concat(path, ".")
		end
	end

	return current
end

---@param path string[]
---@param ... any
---@return string
function M.message(path, ...)
	local template = resolve_message(path)
	if select("#", ...) == 0 then
		return template
	end

	return string.format(template, ...)
end

---@param level integer
---@param path string[]
---@param ... any
function M.notify(level, path, ...)
	vim.notify(M.message(path, ...), level)
end

---@param path string[]
---@param ... any
function M.debug(path, ...)
	local config = require("minecraft-dev").config
	if config.logging and config.logging.debug then
		vim.notify(M.message(path, ...), vim.log.levels.DEBUG)
	end
end

return M
