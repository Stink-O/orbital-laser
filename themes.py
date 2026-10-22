"""The Orbital Laser themes: one entry per laser. Each says which shader theme to run, how it is announced, which sounds
it uses, and how it scars the world (what the ground turns into, the crater, the shaft, what sits at the bottom).
What each one leaves behind beyond the crater (glassing, rubble, flowers, floating rock) lives in strike.py.

To add a theme: add an entry here, a branch in orbital-laser-shader/shaders/strike.wgsl, sounds in
tools/sounds_themes.py, and a slot in the remote's menu (strike.py: MENU_SLOTS).
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Theme:
    key: str                 # also the sound prefix (the plasma set has none)
    index: int               # the shader's `theme` option
    title: str               # shown on the action bar and the remote
    color: str               # Minecraft text colour for the action bar
    blurb: str
    icon_model: str          # the item model its icon in the remote's menu wears
    scorch: tuple            # (radius, block, roughness, replace): what the ground around the crater turns into, in order
    bowl_r: int              # crater radius at the surface
    bowl_d: int              # crater depth
    bowl_rough: float
    shaft_r: int             # shaft radius at the mouth
    shaft_min: int           # the radius the funnel narrows to
    shaft_rough: float
    lining: tuple            # ((block, share), ...): what the crater walls fuse into, mottled by share
    bowl_floor: tuple        # (block, roughness, replace) laid on the bowl floor
    bottom: tuple            # ((radius, y_lo_offset, y_hi_offset, block), ...) at the bottom of the shaft
    particle_a: str          # thrown into the shaft as it deepens (format with {x} {y} {z} {r})
    particle_b: str

    def snd(self, role):
        """The sound event for a role (charge, lockon, fire, beam, rumble, accent, collapse, shutdown)."""
        if role == "collapse":
            return "collapse"                       # shared by every theme
        if self.key == "plasma":
            return "crackle" if role == "accent" else role
        return f"{self.key}.{role}"


PLASMA = Theme(
    key="plasma", index=0, title="PLASMA", color="aqua",
    blurb="A raging plasma beam and forked lightning. Leaves a crater fused into glass and obsidian, ringed with fire and rubble.",
    icon_model="orbital:plasma_icon",
    scorch=((46, "minecraft:blackstone", 0.15, "minecraft:grass_block"), (42, "minecraft:smooth_basalt", 0.15, "minecraft:sand"),
            (39, "minecraft:coarse_dirt", 0.15, "minecraft:dirt")),
    bowl_r=32, bowl_d=16, bowl_rough=0.14, shaft_r=9, shaft_min=3, shaft_rough=0.06,
    lining=(("minecraft:obsidian", 0.35), ("minecraft:black_stained_glass", 0.25), ("minecraft:tinted_glass", 0.15),
            ("minecraft:magma_block", 0.15), ("minecraft:smooth_basalt", 0.10)),
    bowl_floor=("minecraft:magma_block", 0.2, "minecraft:obsidian"),
    bottom=((3, 0, 0, "minecraft:magma_block"), (2, 1, 3, "minecraft:lava")),
    particle_a="particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.25 60 force",
    particle_b="particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 25 force",
)

GODLY = Theme(
    key="godly", index=1, title="GODLY", color="yellow",
    blurb="The clouds part and a pillar of light comes down. Leaves a consecrated crater of quartz and gold, a sigil in the ground, "
          "flowers blooming outwards and rock left hanging in the air.",
    icon_model="orbital:godly_icon",
    scorch=((42, "minecraft:smooth_quartz", 0.0, "minecraft:grass_block"), (38, "minecraft:smooth_quartz", 0.0, "minecraft:sand"),
            (36, "minecraft:calcite", 0.0, "minecraft:dirt")),
    bowl_r=28, bowl_d=14, bowl_rough=0.0, shaft_r=6, shaft_min=6, shaft_rough=0.0,
    lining=(("minecraft:smooth_quartz", 0.45), ("minecraft:calcite", 0.3), ("minecraft:gold_block", 0.12),
            ("minecraft:quartz_bricks", 0.13)),
    bowl_floor=("minecraft:gold_block", 0.0, "minecraft:smooth_quartz"),
    bottom=((4, 0, 0, "minecraft:gold_block"), (3, 1, 1, "minecraft:sea_lantern"), (1, 2, 8, "minecraft:glowstone")),
    particle_a="particle minecraft:end_rod {x} {y} {z} {r} 3 {r} 0.15 80 force",
    particle_b="particle minecraft:wax_on {x} {y} {z} {r} 2 {r} 0.5 40 force",
)

THEMES = (PLASMA, GODLY)
BY_KEY = {t.key: t for t in THEMES}
