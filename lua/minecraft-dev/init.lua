local M = {}
---@type MinecraftDevConfig | {}
M.config = {}

---@param opts? MinecraftDevConfigOpt | MinecraftDevConfig
function M.setup(opts)
	M.config = require("minecraft-dev.config").normalize(opts)
	require("minecraft-dev.command").setup()
	require("minecraft-dev.translation_diagnostics").setup()
	require("minecraft-dev.translation_index").setup()
	require("minecraft-dev.translation_source").setup()
	require("minecraft-dev.bukkit_metadata").setup()
	require("minecraft-dev.forge_metadata").setup()
	require("minecraft-dev.fabric_metadata").setup()
	require("minecraft-dev.mixin_metadata").setup()
	require("minecraft-dev.access_rules").setup()
end

---@param spec table
---@param callback? fun(result: table)
---@return table
function M.generate(spec, callback)
	return require("minecraft-dev.project").generate(spec, callback)
end

---@param spec table
---@param callback? fun(result: table)
---@return table
function M.generate_async(spec, callback)
	return require("minecraft-dev.project").generate_async(spec, callback)
end

---@param options table
---@return table
function M.generate_template(options)
	return require("minecraft-dev.custom").generate(options)
end

---@param options table
---@return table?, table?
function M.list_templates(options)
	return require("minecraft-dev.custom").list(options)
end

---@param options? { buffer?: integer, order?: string, default_path?: string, template_path?: string, template_content?: string }
---@return table
function M.sort_translations(options)
	return require("minecraft-dev.translations").sort_buffer(options)
end

---@param options? { buffer?: integer, default_path?: string }
---@return table
function M.diagnose_translations(options)
	return require("minecraft-dev.translation_diagnostics").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string }
---@return table
function M.list_translation_keys(options)
	return require("minecraft-dev.translation_index").list(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string }
---@return table
function M.complete_translations(options)
	---@diagnostic disable-next-line: param-type-mismatch
	return require("minecraft-dev.translation_index").complete(options)
end

---@param options? { buffer?: integer, root?: string, key?: string, open?: boolean }
---@return table
function M.goto_translation(options)
	return require("minecraft-dev.translation_index").goto_translation(options)
end

---@param options? { buffer?: integer, root?: string, language?: string }
---@return table
function M.diagnose_translation_usages(options)
	return require("minecraft-dev.translation_source").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, key?: string, open?: boolean, max_files?: integer }
---@return table
function M.find_translation_usages(options)
	return require("minecraft-dev.translation_usages").find(options)
end

---@param options? { buffer?: integer, root?: string, language?: string, max_files?: integer }
---@return table
function M.diagnose_bukkit_manifest(options)
	return require("minecraft-dev.bukkit_metadata").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string, max_files?: integer }
---@return table
function M.complete_bukkit_main(options)
	---@diagnostic disable-next-line: param-type-mismatch
	return require("minecraft-dev.bukkit_metadata").complete(options)
end

---@param options? { buffer?: integer, root?: string, main?: string, open?: boolean, max_files?: integer }
---@return table
function M.goto_bukkit_main(options)
	---@diagnostic disable-next-line: param-type-mismatch
	return require("minecraft-dev.bukkit_metadata").goto_main(options)
end

---@param options? { buffer?: integer, language?: string }
---@return table
function M.diagnose_forge_manifest(options)
	return require("minecraft-dev.forge_metadata").diagnose_buffer(options)
end

---@param options? { buffer?: integer, prefix?: string, row?: integer, col?: integer, line?: string }
---@return table
function M.complete_forge_manifest(options)
	return require("minecraft-dev.forge_metadata").complete(options)
end

---@param options? { buffer?: integer, root?: string, mod_id?: string, target?: "manifest"|"source", open?: boolean, max_files?: integer }
---@return table
function M.goto_forge_mod(options)
	return require("minecraft-dev.forge_metadata").goto_mod(options)
end

---@param options? { buffer?: integer, open?: boolean }
---@return table
function M.goto_forge_logo(options)
	return require("minecraft-dev.forge_metadata").goto_logo(options)
end

---@param options? { buffer?: integer, root?: string, language?: string, max_files?: integer }
---@return table
function M.diagnose_fabric_manifest(options)
	return require("minecraft-dev.fabric_metadata").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string, entrypoint_type?: string, max_files?: integer }
---@return table
function M.complete_fabric_entrypoints(options)
	return require("minecraft-dev.fabric_metadata").complete_entrypoints(options)
end

---@param options? { buffer?: integer, prefix?: string, kind?: "mixin"|"accessWidener"|"icon" }
---@return table
function M.complete_fabric_resources(options)
	return require("minecraft-dev.fabric_metadata").complete_resources(options)
end

---@param options? { buffer?: integer, root?: string, value?: string, open?: boolean, max_files?: integer }
---@return table
function M.goto_fabric_entrypoint(options)
	return require("minecraft-dev.fabric_metadata").goto_entrypoint(options)
end

---@param options? { buffer?: integer, open?: boolean }
---@return table
function M.goto_fabric_resource(options)
	return require("minecraft-dev.fabric_metadata").goto_resource(options)
end

---@param options? { buffer?: integer, root?: string, language?: string, max_files?: integer }
---@return table
function M.diagnose_mixin_config(options)
	return require("minecraft-dev.mixin_metadata").diagnose_buffer(options)
end

---@param options? { buffer?: integer, root?: string, prefix?: string, kind?: "mixin"|"plugin"|"package"|"compatibilityLevel", max_files?: integer }
---@return table
function M.complete_mixin_config(options)
	return require("minecraft-dev.mixin_metadata").complete(options)
end

---@param options? { buffer?: integer, root?: string, value?: string, kind?: "mixin"|"plugin", open?: boolean, max_files?: integer }
---@return table
function M.goto_mixin_reference(options)
	return require("minecraft-dev.mixin_metadata").goto_reference(options)
end

---@param options? { path?: string, sync?: boolean, callback?: fun(result: table) }
---@return table
function M.open_nbt(options)
	return require("minecraft-dev.nbt").open(options)
end

---@param options? { buffer?: integer }
---@return table
function M.save_nbt(options)
	return require("minecraft-dev.nbt").save_buffer(options)
end

---@param options? { buffer?: integer, sync?: boolean, force?: boolean, callback?: fun(result: table) }
---@return table
function M.reload_nbt(options)
	return require("minecraft-dev.nbt").reload_buffer(options)
end

---@param options { query?: string, content?: string, path?: string, paths?: string[], format?: string }
---@return table
function M.lookup_mapping(options)
	return require("minecraft-dev.mappings").lookup(options)
end

---@param options? { buffer?: integer, format?: "at"|"aw"|"coremod" }
---@return table
function M.diagnose_access_rules(options)
	return require("minecraft-dev.access_rules").diagnose_buffer(options)
end

---@param options? { buffer?: integer, format?: "at"|"aw", line?: string, prefix?: string, root?: string, max_files?: integer }
---@return table
function M.complete_access_rules(options)
	return require("minecraft-dev.access_rules").complete(options)
end

---@param options? { buffer?: integer, format?: "at"|"aw"|"coremod", row?: integer, root?: string, open?: boolean, max_files?: integer }
---@return table
function M.goto_access_target(options)
	return require("minecraft-dev.access_rules").goto_target(options)
end

---@param options { buffer?: integer, member?: string, row?: integer, format: "at"|"aw"|"coremod"|"mixin", access?: string, clipboard?: boolean }
---@return table
function M.copy_jvm_target(options)
	return require("minecraft-dev.jvm_targets").copy(options)
end

---@param options? { buffer?: integer, target?: string, root?: string, row?: integer, open?: boolean, max_files?: integer }
---@return table
function M.find_mixins(options)
	return require("minecraft-dev.mixin_actions").find_mixins(options)
end

---@param options { source_buffer?: integer, target_buffer?: integer, root?: string, kind: "accessor_getter"|"accessor_setter"|"invoker"|"shadow"|"overwrite"|"soft_implements", member: string, prefix?: string }
---@return table
function M.generate_mixin_member(options)
	return require("minecraft-dev.mixin_actions").generate(options)
end

function M.reload()
	local cur_config = vim.deepcopy(M.config)
	local notify = require("minecraft-dev.util.notify")
	for module, _ in pairs(package.loaded) do
		if module:match("^minecraft%-dev") then
			if cur_config.logging and cur_config.logging.debug then
				notify.debug({ "reload", "module_reloaded" }, module)
			end

			package.loaded[module] = nil
		end
	end
	require("minecraft-dev").setup(cur_config)

	notify.notify(vim.log.levels.INFO, { "reload", "success" })
end
return M
