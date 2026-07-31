package ${PACKAGE};

import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.eventbus.api.IEventBus;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

@Mod(${MOD_ID_QUOTED})
public final class ${MAIN_CLASS} {
    public static final String MODID = ${MOD_ID_QUOTED};
    private static final Logger LOGGER = LogManager.getLogger();

    public ${MAIN_CLASS}() {
        IEventBus modEventBus = FMLJavaModLoadingContext.get().getModEventBus();
        MinecraftForge.EVENT_BUS.register(this);
        LOGGER.info("Loading {}", MODID);
    }
}
