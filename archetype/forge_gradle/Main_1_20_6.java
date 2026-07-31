package ${PACKAGE};

import net.minecraftforge.eventbus.api.IEventBus;
import net.minecraftforge.fml.ModLoadingContext;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.config.ModConfig;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;

@Mod(${MAIN_CLASS}.MODID)
public final class ${MAIN_CLASS} {
    public static final String MODID = ${MOD_ID_QUOTED};

    public ${MAIN_CLASS}(${CONTEXT_PARAMETER}) {
        IEventBus modEventBus = ${EVENT_BUS};
        ${REGISTER_CONFIG}
    }
}
