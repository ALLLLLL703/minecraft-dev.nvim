local M = {}
local uv = vim.uv or vim.loop

local KINDS = {
	forge = { block = true, item = true, enchantment = true, mob_effect = true, packet = true },
	neoforge = { block = true, item = true, enchantment = true, mob_effect = true, packet = true },
	fabric = { block = true, item = true, enchantment = true, status_effect = true },
}
local JAVA_KEYWORDS = {
	["abstract"] = true,
	["assert"] = true,
	["boolean"] = true,
	["break"] = true,
	["byte"] = true,
	["case"] = true,
	["catch"] = true,
	["char"] = true,
	["class"] = true,
	["const"] = true,
	["continue"] = true,
	["default"] = true,
	["do"] = true,
	["double"] = true,
	["else"] = true,
	["enum"] = true,
	["extends"] = true,
	["final"] = true,
	["finally"] = true,
	["float"] = true,
	["for"] = true,
	["goto"] = true,
	["if"] = true,
	["implements"] = true,
	["import"] = true,
	["instanceof"] = true,
	["int"] = true,
	["interface"] = true,
	["long"] = true,
	["native"] = true,
	["new"] = true,
	["package"] = true,
	["private"] = true,
	["protected"] = true,
	["public"] = true,
	["return"] = true,
	["short"] = true,
	["static"] = true,
	["strictfp"] = true,
	["super"] = true,
	["switch"] = true,
	["synchronized"] = true,
	["this"] = true,
	["throw"] = true,
	["throws"] = true,
	["transient"] = true,
	["try"] = true,
	["void"] = true,
	["volatile"] = true,
	["while"] = true,
}

local function failure(code, detail)
	return { status = "failed", error = { code = code, detail = detail or "" } }
end

local function split_class(value)
	if type(value) ~= "string" or value == "" then
		return nil
	end
	local segments = vim.split(value, ".", { plain = true })
	for _, segment in ipairs(segments) do
		if not segment:match("^[%a_$][%w_$]*$") or JAVA_KEYWORDS[segment] then
			return nil
		end
	end
	local name = table.remove(segments)
	return table.concat(segments, "."), name
end

local function at_least(version, major, minor)
	local found_major, found_minor = tostring(version or ""):match("^(%d+)%.(%d+)")
	if not found_major then
		return nil
	end
	found_major, found_minor = tonumber(found_major), tonumber(found_minor)
	return found_major > major or (found_major == major and found_minor >= minor)
end

local function class_file(package_name, imports, declaration)
	local lines = {}
	if package_name ~= "" then
		vim.list_extend(lines, { "package " .. package_name .. ";", "" })
	end
	for _, import in ipairs(imports) do
		table.insert(lines, "import " .. import .. ";")
	end
	if #imports > 0 then
		table.insert(lines, "")
	end
	vim.list_extend(lines, declaration)
	return table.concat(lines, "\n") .. "\n"
end

local function simple_class(package_name, name, base, constructor_type, parameter)
	local simple = base:match("([%w_$]+)$")
	return class_file(package_name, { base }, {
		"public class " .. name .. " extends " .. simple .. " {",
		"    public " .. name .. "(" .. constructor_type .. " " .. parameter .. ") {",
		"        super(" .. parameter .. ");",
		"    }",
		"}",
	})
end

local function enchantment(package_name, name, modern)
	local prefix = modern and "net.minecraft.world" or "net.minecraft"
	local imports = modern
			and {
				prefix .. ".entity.EquipmentSlot",
				prefix .. ".item.enchantment.Enchantment",
				prefix .. ".item.enchantment.EnchantmentCategory",
			}
		or {
			prefix .. ".enchantment.Enchantment",
			prefix .. ".enchantment.EnchantmentType",
			prefix .. ".inventory.EquipmentSlotType",
		}
	local args = modern and "Rarity rarity, EnchantmentCategory category, EquipmentSlot[] slots"
		or "Rarity rarity, EnchantmentType type, EquipmentSlotType[] slots"
	local values = modern and "rarity, category, slots" or "rarity, type, slots"
	return class_file(package_name, imports, {
		"public class " .. name .. " extends Enchantment {",
		"    public " .. name .. "(" .. args .. ") {",
		"        super(" .. values .. ");",
		"    }",
		"}",
	})
end

local function packet(package_name, name, platform, version)
	local modern = at_least(version, 1, 17)
	local newest = at_least(version, 1, 18)
	local buffer = modern and "FriendlyByteBuf" or "PacketBuffer"
	local buffer_import = modern and "net.minecraft.network.FriendlyByteBuf" or "net.minecraft.network.PacketBuffer"
	local event_import
	if platform == "neoforge" then
		event_import = "net.neoforged.neoforge.network.NetworkEvent"
	elseif newest then
		event_import = "net.minecraftforge.network.NetworkEvent"
	elseif modern then
		event_import = "net.minecraftforge.fmllegacy.network.NetworkEvent"
	else
		event_import = "net.minecraftforge.fml.network.NetworkEvent"
	end
	return class_file(package_name, { buffer_import, event_import, "java.util.function.Supplier" }, {
		"public class " .. name .. " {",
		"    public " .. name .. "() {",
		"    }",
		"",
		"    public " .. name .. "(" .. buffer .. " buffer) {",
		"    }",
		"",
		"    public void toBytes(" .. buffer .. " buffer) {",
		"    }",
		"",
		"    public void handle(Supplier<NetworkEvent.Context> context) {",
		"        context.get().enqueueWork(() -> {",
		"        });",
		"        context.get().setPacketHandled(true);",
		"    }",
		"}",
	})
end

local function render(options, package_name, name)
	local platform, kind = options.platform, options.kind
	if not KINDS[platform] or not KINDS[platform][kind] then
		return nil, failure("minecraft_class_kind_invalid", tostring(platform) .. ":" .. tostring(kind))
	end
	local modern = platform == "neoforge" or platform == "forge" and at_least(options.minecraft_version, 1, 17)
	if platform == "forge" and modern == nil then
		return nil, failure("minecraft_version_invalid", tostring(options.minecraft_version))
	end
	if kind == "block" then
		local base = platform == "fabric" and "net.minecraft.block.Block"
			or (modern and "net.minecraft.world.level.block.Block" or "net.minecraft.block.Block")
		return simple_class(
			package_name,
			name,
			base,
			platform == "fabric" and "Settings" or "Properties",
			platform == "fabric" and "settings" or "properties"
		)
	elseif kind == "item" then
		local base = platform == "fabric" and "net.minecraft.item.Item"
			or (modern and "net.minecraft.world.item.Item" or "net.minecraft.item.Item")
		return simple_class(
			package_name,
			name,
			base,
			platform == "fabric" and "Settings" or "Properties",
			platform == "fabric" and "settings" or "properties"
		)
	elseif kind == "enchantment" then
		return enchantment(package_name, name, platform ~= "fabric" and modern or false)
	elseif kind == "mob_effect" then
		if platform == "forge" and not modern then
			return nil, failure("minecraft_class_kind_invalid", "forge:mob_effect requires Minecraft 1.17+")
		end
		return class_file(
			package_name,
			{ "net.minecraft.world.effect.MobEffect", "net.minecraft.world.effect.MobEffectCategory" },
			{
				"public class " .. name .. " extends MobEffect {",
				"    public " .. name .. "(MobEffectCategory category, int color) {",
				"        super(category, color);",
				"    }",
				"}",
			}
		)
	elseif kind == "status_effect" then
		return class_file(
			package_name,
			{ "net.minecraft.entity.effect.StatusEffect", "net.minecraft.entity.effect.StatusEffectCategory" },
			{
				"public class " .. name .. " extends StatusEffect {",
				"    public " .. name .. "(StatusEffectCategory category, int color) {",
				"        super(category, color);",
				"    }",
				"}",
			}
		)
	elseif kind == "packet" then
		return packet(package_name, name, platform, options.minecraft_version or "1.18")
	end
end

local function within(root, path)
	return path == root or vim.startswith(path, root .. "/")
end

local function nearest_existing(path)
	local current = path
	while not uv.fs_stat(current) do
		local parent = vim.fs.dirname(current)
		if parent == current then
			return nil
		end
		current = parent
	end
	return uv.fs_realpath(current)
end

---@param options { root?: string, source_root?: string, platform: "forge"|"neoforge"|"fabric", kind: string, class_name: string, minecraft_version?: string, open?: boolean }
---@return table
function M.generate(options)
	options = options or {}
	local package_name, name = split_class(options.class_name)
	if not package_name then
		return failure("minecraft_class_name_invalid", tostring(options.class_name))
	end
	local source_root = options.source_root or require("minecraft-dev").config.defaults.source_generation.source_root
	if
		source_root:sub(1, 1) == "/"
		or source_root == ".."
		or source_root:match("^%.%./")
		or source_root:match("/%.%./")
		or source_root:match("/%.%.$")
	then
		return failure("minecraft_source_root_invalid", source_root)
	end
	local root = vim.fs.normalize(options.root or vim.fn.getcwd())
	local real_root = uv.fs_realpath(root)
	if not real_root then
		return failure("minecraft_source_root_invalid", root)
	end
	local content, render_error = render(options, package_name, name)
	if not content then
		return render_error or failure("minecraft_class_kind_invalid")
	end
	local directory = vim.fs.joinpath(root, source_root, (package_name:gsub("%.", "/")))
	local existing_parent = nearest_existing(directory)
	if not existing_parent or not within(real_root, existing_parent) then
		return failure("minecraft_source_root_invalid", directory)
	end
	local path = vim.fs.joinpath(directory, name .. ".java")
	if uv.fs_stat(path) then
		return failure("minecraft_class_exists", path)
	end
	local ok, mkdir_error = pcall(vim.fn.mkdir, directory, "p")
	if not ok then
		return failure("minecraft_class_write_failed", mkdir_error)
	end
	local fd, open_error = uv.fs_open(path, "wx", 420)
	if not fd then
		return failure(uv.fs_stat(path) and "minecraft_class_exists" or "minecraft_class_write_failed", open_error)
	end
	local written, write_error = uv.fs_write(fd, content, 0)
	uv.fs_close(fd)
	if not written or written ~= #content then
		uv.fs_unlink(path)
		return failure("minecraft_class_write_failed", write_error or "partial write")
	end
	if options.open ~= false then
		vim.cmd.edit(vim.fn.fnameescape(path))
	end
	return { status = "generated", path = path, class_name = options.class_name, bytes = written }
end

return M
