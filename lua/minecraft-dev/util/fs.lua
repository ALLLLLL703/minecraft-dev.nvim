local M = {}

function M.mkdir(path)
	vim.fn.mkdir(path, "p")
end

function M.write_file(path, content)
	local f = io.open(path, "w")

	if not f then
		error("Could not open file " .. path .. " for writing")
	end

	f:write(content)
	f:close()
end

return M
