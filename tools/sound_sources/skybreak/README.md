# Recordings used by tools/sounds_skybreak.py (the Sky Breaks' shudder glass)

All four are CC0 (public domain dedication) on Freesound, used here as the MP3 previews Freesound serves. Only the
Sky Breaks' `shudder` uses them: slices of their glass breaks, layered over synthesised body, air and echo. Every other
sound in orbital-sounds/ is synthesised.

| File | Title | Author | Source | Licence | Seconds used (onset, then dense crash + fade) |
|---|---|---|---|---|---|
| glass_hammer_721363.mp3 | LargeGlassHobSplashSheildSmashedByHammer01 | butt.chiara17 | https://freesound.org/s/721363/ | CC0 | 5.775-6.429 |
| glass_windows_487138.mp3 | R28-12-Glass Windows Break.wav | craigsmith | https://freesound.org/s/487138/ | CC0 | 0.109-1.163, 3.954-5.008, 7.659-8.413, 9.381-10.435 |
| glass_car_587928.mp3 | BROKEN CAR WINDOW.wav | thecommondanger | https://freesound.org/s/587928/ | CC0 | 0.562-0.806 (its first break, with whistles in it, is not used) |
| glass_pane_675853.mp3 | S41-12 Large pane of glass breaks; dull; sweetener.wav | craigsmith | https://freesound.org/s/675853/ | CC0 | 0.041-0.995 |

Each slice starts 4 ms before its break's onset and is faded out (over its last 0.07-0.3 s) where its dense crash ends,
before single pieces land one by one. The exact numbers are `BREAKS` in tools/sounds_skybreak.py.
