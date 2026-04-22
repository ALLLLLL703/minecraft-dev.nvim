local M = {}

---@param path string
function M.mkdir(path)
	vim.fn.mkdir(path, "p")
end

---@param path string
---@param content string
function M.write_file(path, content)
	local f = io.open(path, "w")

	if not f then
		error("Could not open file " .. path .. " for writing")
	end

	f:write(content)
	f:close()
end

return M
