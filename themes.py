"""The Orbital Laser themes: one entry per look. Each says which shader theme to run, how it is announced, which sounds
it uses, and how it scars the world (what the ground turns into, the crater, the shaft, what sits at the bottom).

To add a theme: add an entry here, a branch in orbital-laser-shader/shaders/strike.wgsl, and sounds in tools/sounds_themes.py.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Theme:
    key: str                 # also the sound prefix (the plasma set has none)
    index: int               # the shader's `theme` option
    title: str               # shown on the action bar and the remote
    color: str               # Minecraft text colour for the action bar
    blurb: str
    scorch: tuple            # (radius, block, roughness, replace): what the ground around the crater turns into, in order
    scorch2: tuple           # same shape, applied after the first set has landed (e.g. crying obsidian on obsidian)
    bowl_r: int              # crater radius at the surface
    bowl_d: int              # crater depth
    bowl_rough: float
    shaft_r: int             # shaft radius at the mouth
    shaft_min: int           # the radius the funnel narrows to
    shaft_rough: float
    bowl_floor: tuple        # (block, roughness, replace) laid on the bowl floor
    bottom: tuple            # ((radius, y_lo_offset, y_hi_offset, block), ...) at the bottom of the shaft
    particle_a: str          # thrown into the shaft as it deepens (format with {x} {y} {z} {r})
    particle_b: str
    pillars: bool = False    # godly: eight quartz pillars crowned with glowstone around the crater
    blessing: bool = False   # godly: players nearby get regeneration and absorption
    sound_prefix: str = ""

    def snd(self, role):
        """The sound event for a role (charge, lockon, fire, beam, rumble, accent, collapse, shutdown)."""
        if role == "collapse":
            return "collapse"                       # shared by every theme
        if self.key == "plasma":
            return "crackle" if role == "accent" else role
        return f"{self.key}.{role}"


PLASMA = Theme(
    key="plasma", index=0, title="PLASMA", color="aqua",
    blurb="Blue-white plasma, forked lightning, dark smoke.",
    scorch=((34, "minecraft:blackstone", 0.15, "minecraft:grass_block"), (30, "minecraft:smooth_basalt", 0.15, "minecraft:sand"),
            (27, "minecraft:coarse_dirt", 0.15, "minecraft:dirt")),
    scorch2=(), bowl_r=20, bowl_d=12, bowl_rough=0.14, shaft_r=9, shaft_min=3, shaft_rough=0.06,
    bowl_floor=("minecraft:magma_block", 0.2, "minecraft:stone"),
    bottom=((3, 0, 0, "minecraft:magma_block"), (2, 1, 3, "minecraft:lava")),
    particle_a="particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.25 60 force",
    particle_b="particle minecraft:lava {x} {y} {z} {r} 1 {r} 0 25 force",
)

INFERNO = Theme(
    key="inferno", index=1, title="INFERNO", color="gold",
    blurb="A column of fire: ember storm, glowing cracks, black smoke.",
    scorch=((34, "minecraft:netherrack", 0.18, "minecraft:grass_block"), (30, "minecraft:soul_sand", 0.15, "minecraft:sand"),
            (27, "minecraft:magma_block", 0.3, "minecraft:dirt")),
    scorch2=(), bowl_r=22, bowl_d=12, bowl_rough=0.2, shaft_r=10, shaft_min=3, shaft_rough=0.1,
    bowl_floor=("minecraft:magma_block", 0.25, "minecraft:stone"),
    bottom=((4, 0, 0, "minecraft:magma_block"), (3, 1, 6, "minecraft:lava")),
    particle_a="particle minecraft:flame {x} {y} {z} {r} 3 {r} 0.3 90 force",
    particle_b="particle minecraft:soul_fire_flame {x} {y} {z} {r} 2 {r} 0.1 30 force",
)

VOID = Theme(
    key="void", index=2, title="VOID", color="dark_purple",
    blurb="A dark beam that tears a black hole: lensing, spiral arms, stars.",
    scorch=((36, "minecraft:blackstone", 0.15, "minecraft:grass_block"), (32, "minecraft:blackstone", 0.15, "minecraft:sand"),
            (26, "minecraft:obsidian", 0.15, "minecraft:dirt"), (20, "minecraft:obsidian", 0.18, "minecraft:grass_block")),
    scorch2=((13, "minecraft:crying_obsidian", 0.3, "minecraft:obsidian"),),
    bowl_r=24, bowl_d=16, bowl_rough=0.1, shaft_r=8, shaft_min=4, shaft_rough=0.02,
    bowl_floor=("minecraft:crying_obsidian", 0.2, "minecraft:stone"),
    bottom=((4, 0, 0, "minecraft:crying_obsidian"), (2, 1, 1, "minecraft:amethyst_block")),
    particle_a="particle minecraft:reverse_portal {x} {y} {z} {r} 3 {r} 0.4 80 force",
    particle_b="particle minecraft:portal {x} {y} {z} {r} 2 {r} 0.6 60 force",
)

GODLY = Theme(
    key="godly", index=3, title="GODLY", color="yellow",
    blurb="Halo rings, giant wings, pillars of light, a golden sigil.",
    scorch=((30, "minecraft:quartz_block", 0.0, "minecraft:grass_block"), (26, "minecraft:smooth_quartz", 0.0, "minecraft:sand"),
            (17, "minecraft:gold_block", 0.0, "minecraft:dirt")),
    scorch2=(), bowl_r=16, bowl_d=10, bowl_rough=0.0, shaft_r=6, shaft_min=6, shaft_rough=0.0,
    bowl_floor=("minecraft:gold_block", 0.0, "minecraft:stone"),
    bottom=((4, 0, 0, "minecraft:gold_block"), (3, 1, 1, "minecraft:sea_lantern"), (1, 2, 8, "minecraft:glowstone")),
    particle_a="particle minecraft:end_rod {x} {y} {z} {r} 3 {r} 0.15 80 force",
    particle_b="particle minecraft:wax_on {x} {y} {z} {r} 2 {r} 0.5 40 force",
    pillars=True, blessing=True,
)

THEMES = (PLASMA, INFERNO, VOID, GODLY)
BY_KEY = {t.key: t for t in THEMES}
