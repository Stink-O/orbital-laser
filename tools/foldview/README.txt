The Fold looked at with numbers: the real mod/shaders/fold_warp.wgsl offscreen over the real land of a save.
  warpview (src/): renders it from free cameras; warps any points through the shader's own world_warp (pts=1); counts crossing triangles (check=1).
    CARGO_TARGET_DIR=... cargo build --release --offline (no game, no sky pass, no entities).
  post=1 puts the real post pass (fold.wgsl) over the picture on the same depth, the far land past the save its land mirrored on; pbench=N times the pass; $WV_SUB=old=>new@@old=>new tries a change to the pass's source. warpview still has no sky or droplet before the pass, and free cameras (ox oy oz) don't work with post=1.
  land_from_save.py: reads a save's region files (read only) to an npz of columns.
  fv.py: Scene, warp(), sweep() (metrics per time and radius; `python3 fv.py` self-tests them on maps with known answers), KO (one term taken out at a time), sheet(), planmap(), xsec().
  plots.py: heatmaps. build_page.py, mkpage.py, page.html: the evidence page.
  pattern.py: the crease pattern's tables, here and in strike/fold.rs: `--to mod/shaders mod/src/strike/fold.rs` writes them, `--plan out.png` draws it. Scene(pattern=0|1|2): which of the three the warp folds on.
Lining up with a game clip: foldview's clock is the strike's. In a clip recorded round a 1.6 s hold of the designator (record, then press), strike time is about the clip's time minus 0.8 s: the bangs and the land's log lines both say so. The game here runs at fov 90, warpview at 70 (fov=90 to match).
