local loaded, matrix = pcall(dofile, vim.fs.joinpath(vim.fn.getcwd(), "test", "build_matrix.lua"))
if not loaded then
	print("Failed to load MinecraftDev build matrix: " .. tostring(matrix))
	vim.cmd("cquit 1")
	return
end
local ran, report = pcall(matrix.run)
if not ran then
	print("MinecraftDev build matrix error: " .. tostring(report))
	vim.cmd("cquit 1")
	return
end

print(string.format("MinecraftDev build matrix: %d passed, %d failed", #report.cases - #report.failed, #report.failed))
print("Report: " .. report.report_path)
if #report.failed > 0 then
	for _, result in ipairs(report.failed) do print(string.format("- %s: %s", result.name, result.status)) end
	vim.cmd("cquit 1")
	return
end
vim.cmd("qa")
