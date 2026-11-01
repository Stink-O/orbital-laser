package dev.orbital;

import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;

/** The wheel tells the server which laser is loaded and whether terrain damage is on. */
public final class Net {
	private Net() {}

	public record SelectLaser(String key) implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<SelectLaser> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("select_laser"));
		public static final StreamCodec<RegistryFriendlyByteBuf, SelectLaser> CODEC =
				StreamCodec.composite(ByteBufCodecs.STRING_UTF8, SelectLaser::key, SelectLaser::new);

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	/**
	 * Server to client: a strike has started, so the client can draw its screen shader. What the original's pass is handed
	 * as `frame.mod_params`: the target, the hit block, the facing, the laser, a seed, the ship's choices, and how far into the
	 * strike it already is.
	 */
	public record StrikeFx(int laser, double tx, double ty, double tz, int bx, int by, int bz, float wing, float seed,
			int approach, int arrival, int colour, float offset, float length, float meX, float meY, float meZ)
			implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<StrikeFx> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("strike_fx"));
		public static final StreamCodec<RegistryFriendlyByteBuf, StrikeFx> CODEC = StreamCodec.of(
				(buf, v) -> {
					buf.writeInt(v.laser);
					buf.writeDouble(v.tx);
					buf.writeDouble(v.ty);
					buf.writeDouble(v.tz);
					buf.writeInt(v.bx);
					buf.writeInt(v.by);
					buf.writeInt(v.bz);
					buf.writeFloat(v.wing);
					buf.writeFloat(v.seed);
					buf.writeInt(v.approach);
					buf.writeInt(v.arrival);
					buf.writeInt(v.colour);
					buf.writeFloat(v.offset);
					buf.writeFloat(v.length);
					buf.writeFloat(v.meX);
					buf.writeFloat(v.meY);
					buf.writeFloat(v.meZ);
				},
				buf -> new StrikeFx(buf.readInt(), buf.readDouble(), buf.readDouble(), buf.readDouble(), buf.readInt(), buf.readInt(),
						buf.readInt(), buf.readFloat(), buf.readFloat(), buf.readInt(), buf.readInt(), buf.readInt(), buf.readFloat(),
						buf.readFloat(), buf.readFloat(), buf.readFloat(), buf.readFloat()));

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	/** Server to client: the table the Payload's and the Nuke's shaders read (the original's `mod_data`), as 32-bit words. */
	public record StrikeData(int[] words) implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<StrikeData> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("strike_data"));
		public static final StreamCodec<RegistryFriendlyByteBuf, StrikeData> CODEC = StreamCodec.of(
				(buf, v) -> {
					buf.writeVarInt(v.words.length);
					for (int w : v.words) {
						buf.writeInt(w);
					}
				},
				buf -> {
					int n = buf.readVarInt();
					int[] w = new int[n];
					for (int i = 0; i < n; i++) {
						w[i] = buf.readInt();
					}
					return new StrikeData(w);
				});

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	/** Server to client: a jolt of the camera, strength 0 to 1, fading out over `seconds`. */
	public record Shake(float strength, float seconds) implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<Shake> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("shake"));
		public static final StreamCodec<RegistryFriendlyByteBuf, Shake> CODEC =
				StreamCodec.composite(ByteBufCodecs.FLOAT, Shake::strength, ByteBufCodecs.FLOAT, Shake::seconds, Shake::new);

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	/** Server to client: a colour laid over the whole screen: rises over fadeIn, holds, falls over fadeOut. */
	public record Flash(int rgb, float alpha, float fadeIn, float hold, float fadeOut) implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<Flash> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("flash"));
		public static final StreamCodec<RegistryFriendlyByteBuf, Flash> CODEC = StreamCodec.composite(
				ByteBufCodecs.INT, Flash::rgb, ByteBufCodecs.FLOAT, Flash::alpha, ByteBufCodecs.FLOAT, Flash::fadeIn,
				ByteBufCodecs.FLOAT, Flash::hold, ByteBufCodecs.FLOAT, Flash::fadeOut, Flash::new);

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	/** Server to client: /orbital stop: every strike's visuals, shakes and tints go at once. */
	public record StopFx() implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<StopFx> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("stop_fx"));
		public static final StreamCodec<RegistryFriendlyByteBuf, StopFx> CODEC = StreamCodec.unit(new StopFx());

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	/** Server to client: open the wheel (/orbital wheel). */
	public record OpenWheel() implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<OpenWheel> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("open_wheel"));
		public static final StreamCodec<RegistryFriendlyByteBuf, OpenWheel> CODEC = StreamCodec.unit(new OpenWheel());

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}

	public record SetTerrain(boolean on) implements CustomPacketPayload {
		public static final CustomPacketPayload.Type<SetTerrain> TYPE = new CustomPacketPayload.Type<>(OrbitalMod.id("set_terrain"));
		public static final StreamCodec<RegistryFriendlyByteBuf, SetTerrain> CODEC =
				StreamCodec.composite(ByteBufCodecs.BOOL, SetTerrain::on, SetTerrain::new);

		@Override
		public CustomPacketPayload.Type<? extends CustomPacketPayload> type() {
			return TYPE;
		}
	}
}
