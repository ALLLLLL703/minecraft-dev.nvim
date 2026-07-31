package ${PACKAGE};

import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.config.ModConfig;

@Mod(${MAIN_CLASS}.MOD_ID)
public final class ${MAIN_CLASS} {
    public static final String MOD_ID = ${MOD_ID_QUOTED};

    public ${MAIN_CLASS}(IEventBus modEventBus, ModContainer modContainer) {
        modContainer.registerConfig(ModConfig.Type.COMMON, Config.SPEC);
    }
}
