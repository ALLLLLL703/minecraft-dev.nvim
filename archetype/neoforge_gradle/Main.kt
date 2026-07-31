package ${PACKAGE}

import ${PACKAGE}.block.ModBlocks
import net.neoforged.fml.common.Mod
import thedarkcolour.kotlinforforge.neoforge.forge.MOD_BUS

@Mod(${MAIN_CLASS}.MOD_ID)
object ${MAIN_CLASS} {
    const val MOD_ID = ${MOD_ID_QUOTED}

    init {
        ModBlocks.REGISTRY.register(MOD_BUS)
    }
}
