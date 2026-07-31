package ${PACKAGE};

import com.mojang.logging.LogUtils;
import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.event.server.ServerStartingEvent;
import net.minecraftforge.eventbus.api.SubscribeEvent;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;
import org.slf4j.Logger;

@Mod(${MOD_ID_QUOTED})
public final class ${MAIN_CLASS} {
    public static final String MODID = ${MOD_ID_QUOTED};
    private static final Logger LOGGER = LogUtils.getLogger();

    public ${MAIN_CLASS}() {
        FMLJavaModLoadingContext.get().getModEventBus();
        MinecraftForge.EVENT_BUS.register(this);
        LOGGER.info("Loading {}", MODID);
    }

    @SubscribeEvent
    public void onServerStarting(ServerStartingEvent event) {}
}
