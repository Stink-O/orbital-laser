"""Regenerate the Orbital Laser sound effects (orbital-sounds/assets/orbital/sounds/**.ogg + sounds.json).

Every sound is synthesized from scratch (band-limited noise, pitched sweeps, additive tones and formants, convolution
reverb built from a synthetic impulse response): no samples, nothing to license. Needs numpy and ffmpeg (with libvorbis).

    python3 tools/synth_sounds.py [OUT_DIR] [--only plasma godly]     # default OUT_DIR: ../orbital-sounds

Plasma's names have no prefix; the others' events are `<theme>.<name>`, files sounds/<theme>/.
"""
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import soundlib
import sounds_plasma
import sounds_themes

ap = argparse.ArgumentParser()
ap.add_argument("out", nargs="?", default=str(Path(__file__).resolve().parent.parent / "orbital-sounds"))
ap.add_argument("--only", nargs="*", choices=["plasma", *sounds_themes.THEMES])
args = ap.parse_args()

soundlib.init(args.out)
if not args.only or "plasma" in args.only:
    sounds_plasma.build()
sounds_themes.build_all(set(args.only) if args.only else None)

events = {n: f"orbital:{n}" for n in sounds_plasma.NAMES}
for th in sounds_themes.THEMES:
    for n in sounds_themes.names(th):
        events[f"{th}.{n}"] = f"orbital:{th}/{n}"
sounds = {ev: {"sounds": [{"name": name, "attenuation_distance": 256}], "subtitle": f"subtitles.orbital.{ev}"} for ev, name in events.items()}
json.dump(sounds, open(args.out + "/assets/orbital/sounds.json", "w"), indent=2)
json.dump({"pack": {"description": "Orbital laser sound design", "min_format": 84, "max_format": 99, "pack_format": 84}},
          open(args.out + "/pack.mcmeta", "w"), indent=2)
print("events:", len(events))
