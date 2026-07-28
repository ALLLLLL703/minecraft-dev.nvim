local loaded, matrix = pcall(dofile, vim.fs.joinpath(vim.fn.getcwd(), "test", "build_matrix.lua"))
local should_quit = vim.env.MINECRAFT_DEV_MATRIX_NO_QUIT ~= "1"
if not loaded then
	print("Failed to load MinecraftDev build matrix: " .. tostring(matrix))
	if should_quit then vim.cmd("cquit 1") end
	if not should_quit then error(matrix) end
	return
end
local ran, report = pcall(matrix.run)
if not ran then
	print("MinecraftDev build matrix error: " .. tostring(report))
	if should_quit then vim.cmd("cquit 1") end
	if not should_quit then error(report) end
	return
end

print(string.format("MinecraftDev build matrix: %d passed, %d failed", #report.cases - #report.failed, #report.failed))
print("Report: " .. report.report_path)
if #report.failed > 0 then
	for _, result in ipairs(report.failed) do print(string.format("- %s: %s", result.name, result.status)) end
	if should_quit then vim.cmd("cquit 1") end
	if not should_quit then error("MinecraftDev build matrix failed; report: " .. report.report_path) end
	return
end
if should_quit then vim.cmd("qa") end
