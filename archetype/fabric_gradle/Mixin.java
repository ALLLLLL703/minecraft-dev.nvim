package %s;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(%s.class)
public class %s {

  @Inject(method = "%s", at = @At("HEAD"))
  private void minecraftDev$exampleInjection(CallbackInfo ci) {
    // Replace the target class and method with your own injection point.
  }
}
