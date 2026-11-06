The Fold looked at with numbers: the real mod/shaders/fold_warp.wgsl offscreen over the real land of a save.
  warpview (src/): renders it from free cameras; warps any points through the shader's own world_warp (pts=1); counts crossing triangles (check=1).
    CARGO_TARGET_DIR=... cargo build --release --offline (no game, no sky pass, no entities).
  land_from_save.py: reads a save's region files (read only) to an npz of columns.
  fv.py: Scene, warp(), sweep() (metrics per time and radius; `python3 fv.py` self-tests them on maps with known answers), KO (one term taken out at a time), sheet(), planmap(), xsec().
  plots.py: heatmaps. build_page.py, mkpage.py, page.html: the evidence page.
