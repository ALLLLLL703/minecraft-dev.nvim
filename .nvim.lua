-- Java and Kotlin language servers are intentionally disabled for this repository.
-- The integration tests create many short-lived JVM buffers and language-server
-- project imports can retain those temporary workspaces for the rest of the session.

local disabled_servers = {
	["jdtls"] = true,
	["jet_kotlin"] = true,
	["kotlin-lsp"] = true,
	["kotlin-language-server"] = true,
}

for name in pairs(disabled_servers) do
	pcall(vim.lsp.enable, name, false)
end

-- Java is normally started directly from ftplugin/java.lua through nvim-jdtls,
-- rather than vim.lsp.enable(), so disable that project import entrypoint too.
local ok, jdtls_attach = pcall(require, "config.lsp-relative.jdtls.attach2")
if ok then
	jdtls_attach.attach = function() end
end

local function stop_heavy_server(client)
	if client and disabled_servers[client.name] then
		client:stop(true)
	end
end

for _, client in ipairs(vim.lsp.get_clients()) do
	stop_heavy_server(client)
end

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("MinecraftDevDisableJvmLanguageServers", { clear = true }),
	callback = function(event)
		vim.schedule(function()
			stop_heavy_server(vim.lsp.get_client_by_id(event.data.client_id))
		end)
	end,
})
