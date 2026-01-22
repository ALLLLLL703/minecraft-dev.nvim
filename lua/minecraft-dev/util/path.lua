local M = {}

local sep = package.config:sub(1, 1)

function M.join(...)
	local parts = { ... }
	return table.concat(parts, sep)
end

---comment
---@param path string
---@return boolean
function M.is_absolute(path)
	if sep == "\\" then
		return path:match("^%a:[\\/]") or path:match("^\\\\")
	else
		return path:sub(1, 1) == "/"
	end
end

---comment
---@param path string
---@return string
function M.dirname(path)
	local s, e = path:match("(.*)[/\\][^/\\]+$")
	if s then
		return s
	else
		return "."
	end
end

return M
