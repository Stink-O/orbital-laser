package dev.orbital;

import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.ItemUseAnimation;
import net.minecraft.world.item.ItemUtils;
import net.minecraft.world.level.Level;

/**
 * Hold right-click on a target for under a second and a strike comes down where the crosshair is: as many as you like, one
 * after another or at once, and as far as you can see (out past the loaded world, over a distance mod's terrain).
 */
public class DesignatorItem extends Item {
	private static final int HOLD_TICKS = 12;
	private static final double RANGE = 1000.0;

	public DesignatorItem(Item.Properties properties) {
		super(properties);
	}

	@Override
	public int getUseDuration(ItemStack stack, LivingEntity user) {
		return 72000;
	}

	@Override
	public ItemUseAnimation getUseAnimation(ItemStack stack) {
		return ItemUseAnimation.SPYGLASS;
	}

	@Override
	public InteractionResult use(Level level, Player player, InteractionHand hand) {
		return ItemUtils.startUsingInstantly(level, player, hand);
	}

	@Override
	public void onUseTick(Level level, LivingEntity user, ItemStack stack, int ticksRemaining) {
		if (level.isClientSide() || !(user instanceof ServerPlayer player)) {
			return;
		}
		int held = getUseDuration(stack, user) - ticksRemaining;
		if (held == 1) {
			player.sendSystemMessage(Component.literal("ACQUIRING TARGET…").withStyle(ChatFormatting.AQUA, ChatFormatting.BOLD), true);
		}
		if (held != HOLD_TICKS) {
			return;
		}
		FarTarget.Hit hit = FarTarget.pick(player, RANGE);
		if (hit == null) {
			player.sendSystemMessage(Component.literal("NO TARGET IN RANGE").withStyle(ChatFormatting.RED, ChatFormatting.BOLD), true);
			return;
		}
		Settings.Player s = Settings.of(player.getUUID());
		var bp = hit.block();
		if (!Strike.start(player, hit.point(), bp.getX(), bp.getY(), bp.getZ(), s.terrain)) {
			player.sendSystemMessage(Component.literal(s.laser.toUpperCase() + " is not available").withStyle(ChatFormatting.RED, ChatFormatting.BOLD), true);
		}
	}
}
