# Parity with the Horizon version

What the Java port has against the Horizon version (the Rust mod on `main`, v0.5.8). Update this table with every
change. "Done" means it looks, sounds and plays the same.

The detailed, feature-by-feature version is [docs/PARITY-CHECKLIST.md](docs/PARITY-CHECKLIST.md).

**Status:** done · partial · missing

## Loaders

| Loader | Status |
|---|---|
| Fabric | partial (the starting point) |
| NeoForge | missing |
| Forge | missing |
| Quilt | missing (try the Fabric build first) |

## Lasers

| Laser | Visuals | Sound | World changes | Notes |
|---|---|---|---|---|
| Plasma | done | done | done | |
| Godly | done | done | done | |
| Black Hole | done | done | done | |
| Meteor Storm | done | done | done | |
| Mothership | done | done | done | |
| Downfall | missing (stand-in particles) | partial | partial (simplified) | its own pass not ported |
| Planet Killer | missing (stand-in particles) | partial | partial (simplified) | its own pass not ported |
| Crystal Bloom | missing (stand-in particles) | partial | partial (simplified) | its own pass not ported |
| Sinkhole | missing (stand-in particles) | partial | partial (simplified) | its own pass not ported |
| Payload | done | done | partial (simplified) | |
| Nuke | done | done | partial (simplified) | knockback missing |
| Rod from God | missing | missing | missing | new in 0.5.7 |
| Supercell | missing | missing | missing | new in 0.5.7 |
| Hurricane | missing | missing | missing | new in 0.5.8; carries the player (the fork's `world.carry-player`) |

The Sound and World changes columns for the four lasers marked "partial (simplified)" come from the port's own notes.
Check each against the Horizon version before marking it done.

## Features

| Feature | Status |
|---|---|
| Designator and Remote items, `/orbital` commands | done |
| Laser wheel (R) | partial: check the 0.5.7 layout (seed and lock seed, impact FX row, follow and knockback switches, STOP STRIKE) |
| Several strikes at once, `/orbital stop` | done |
| Far targets (distant terrain) | done |
| Distance-aware sound | done |
| Shader packs (Iris) | done |
| QUALITY FAST (half-size smoke) | missing |
| `/orbital shadow` | missing |
| Nuke and Rod knockback | missing |
| Impact frames (Kanada, Black Flash, Cinematic) | missing |
| Seed and LOCK SEED | missing |
| Follow camera | missing |
| Fly speed row | check |
| `/orbital approach`, `arrival`, `colour` (the ship lasers) | check |

## How to check parity

Fire the same laser, with the same seed and from the same distance, in the Horizon version and the Java one. Compare
the picture at the same moments (the Horizon version's `tools/preview.py` renders any moment offscreen) and the sound.
Note any difference here.
