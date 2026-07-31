package ${PACKAGE};

import net.minecraft.resources.ResourceLocation;
import net.minecraftforge.common.ForgeConfigSpec;

public final class Config {
    private static final ForgeConfigSpec.Builder BUILDER = new ForgeConfigSpec.Builder();
    public static final ForgeConfigSpec.BooleanValue LOG_REGISTRIES = BUILDER.define("logRegistries", true);
    static final ForgeConfigSpec SPEC = BUILDER.build();

    private Config() {}

    static ResourceLocation parseLocation(String value) {
        return ResourceLocation.parse(value);
    }
}
