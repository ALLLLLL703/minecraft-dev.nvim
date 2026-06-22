package %s

import org.bukkit.plugin.java.JavaPlugin

class %s : JavaPlugin() {
    override fun onEnable() {
        logger.info("%s enabled!")
    }

    override fun onDisable() {
        logger.info("%s disabled!")
    }
}
