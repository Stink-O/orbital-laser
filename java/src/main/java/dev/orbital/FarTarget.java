package dev.orbital;

import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.level.chunk.status.ChunkStatus;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;

/**
 * Where the player is pointing, out as far as `range`: first an ordinary ray through what the server has loaded, and then, past
 * that (where only a distance mod such as Voxy shows the land), a march along the view line over the terrain's height, loading
 * the chunks it needs. So a target can be picked out on far terrain that is drawn but not loaded.
 */
public final class FarTarget {
	/** Chunks one pick may load or generate beyond what is loaded (a pick on far land is a small stall, not an endless one). */
	private static final int MAX_LOADS = 48;
	private static final double STEP = 24.0;

	private FarTarget() {}

	public record Hit(Vec3 point, BlockPos block) {}

	public static Hit pick(ServerPlayer player, double range) {
		ServerLevel level = (ServerLevel) player.level();
		Vec3 eye = player.getEyePosition();
		Vec3 look = player.getLookAngle();

		// 1. what the server has loaded
		var hit = level.clip(new ClipContext(eye, eye.add(look.scale(range)), ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player));
		if (hit.getType() == HitResult.Type.BLOCK) {
			return new Hit(hit.getLocation(), hit.getBlockPos());
		}

		// 2. beyond it: where the view line comes down to the ground
		int[] loads = {0};
		double prev = 0;
		for (double t = STEP; t <= range; t += STEP) {
			Vec3 p = eye.add(look.scale(t));
			double h = ground(level, (int) Math.floor(p.x), (int) Math.floor(p.z), loads);
			if (Double.isNaN(h)) {
				return null; // loaded all it may
			}
			if (p.y <= h) {
				double lo = prev, hi = t;
				for (int i = 0; i < 14; i++) {
					double mid = 0.5 * (lo + hi);
					Vec3 q = eye.add(look.scale(mid));
					double hq = ground(level, (int) Math.floor(q.x), (int) Math.floor(q.z), loads);
					if (!Double.isNaN(hq) && q.y <= hq) {
						hi = mid;
					} else {
						lo = mid;
					}
				}
				Vec3 q = eye.add(look.scale(hi));
				int x = (int) Math.floor(q.x), z = (int) Math.floor(q.z);
				double g = ground(level, x, z, loads);
				if (Double.isNaN(g)) {
					return null;
				}
				return new Hit(new Vec3(q.x, g, q.z), new BlockPos(x, (int) g - 1, z));
			}
			prev = t;
		}
		return null;
	}

	/** The height of the ground over a column (the first air over its highest block that stops movement, leaves left out). */
	private static double ground(ServerLevel level, int x, int z, int[] loads) {
		int cx = x >> 4, cz = z >> 4;
		if (!level.hasChunk(cx, cz)) {
			if (loads[0] >= MAX_LOADS) {
				return Double.NaN;
			}
			loads[0]++;
			level.getChunkSource().getChunk(cx, cz, ChunkStatus.FULL, true);
		}
		return level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
	}
}
