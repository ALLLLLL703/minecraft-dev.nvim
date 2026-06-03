local M = {}

---@param input string?
---@param default string
---@return string
function M.not_empty_or(input, default)
	if input == nil or input:match("^%s*$") then
		return default
	end

	return input
end

return M
