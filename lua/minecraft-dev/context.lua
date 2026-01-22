local M = {}

function M.collect()
	local groupId = vim.fn.input("Group Id: ", "com.example")
	local artifactId = vim.fn.input("Artifact Id: ", "demo")
	local main = vim.fn.input("Main class name", "Main")

	return {
		groupId = groupId,
		artifactId = artifactId,
		main = main,
		package = groupId .. "." .. artifactId,
	}
end

return M
