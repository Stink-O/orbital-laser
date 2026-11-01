package dev.orbital;

import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.Level;

/** The remote opens the laser wheel (on the client). */
public class RemoteItem extends Item {
	/** Set by the client side of the mod: opens the wheel screen. */
	public static Runnable openWheel;

	public RemoteItem(Item.Properties properties) {
		super(properties);
	}

	@Override
	public InteractionResult use(Level level, Player player, InteractionHand hand) {
		if (level.isClientSide() && openWheel != null) {
			openWheel.run();
		}
		return InteractionResult.SUCCESS;
	}
}
