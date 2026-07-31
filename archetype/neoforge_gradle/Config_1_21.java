package ${PACKAGE};

import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.neoforge.common.ModConfigSpec;

public final class Config {
    private static final ModConfigSpec.Builder BUILDER = new ModConfigSpec.Builder();
    private static final ModConfigSpec.ConfigValue<String> EXAMPLE_ITEM = BUILDER
        .define("exampleItem", "minecraft:iron_ingot", value -> value instanceof String name
            && BuiltInRegistries.ITEM.containsKey(ResourceLocation.parse(name)));
    static final ModConfigSpec SPEC = BUILDER.build();

    private Config() {}
}
