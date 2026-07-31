package ${PACKAGE};

import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.eventbus.api.SubscribeEvent;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;
import net.minecraftforge.fmlserverevents.FMLServerStartingEvent;

@Mod(${MOD_ID_QUOTED})
public final class ${MAIN_CLASS} {
    public static final String MODID = ${MOD_ID_QUOTED};

    public ${MAIN_CLASS}() {
        FMLJavaModLoadingContext.get().getModEventBus();
        MinecraftForge.EVENT_BUS.register(this);
    }

    @SubscribeEvent
    public void onServerStarting(FMLServerStartingEvent event) {}
}
