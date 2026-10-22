#!/usr/bin/env python3
"""Record a theme's strike as an MP4 (and build a reel from several).

    python3 tools/make_video.py record  THEME  X Y Z  [-o out.mp4]     fly a camera to the target, fire, record, encode
    python3 tools/make_video.py reel    a.mp4 b.mp4 ...  -o reel.mp4   join clips (adds nothing else)
    python3 tools/make_video.py selftest                              check the decoder and mixer on synthetic data

How it works (and why it is not a screen recording):
  * `horizon-ctl screenshot` returns each frame with the blue channel destroyed. The shader's capture mode (swz = 3, set
    by `strike.py --capture`) packs the picture into the two surviving channels: luma in red and one chroma component in
    green, alternating in a checkerboard. decode_frame() puts the picture back (chroma at half resolution, as video does).
  * The soundtrack is rebuilt from the same sound files the game plays, placed at the times strike.py reports with
    `--timeline`, so no audio is captured from your computer. Vanilla thunder/explosion layers are not in it.
  * Frames are grabbed as fast as the game hands them over and resampled to a constant frame rate.
Needs: numpy, Pillow and ffmpeg (libx264, aac). Spectator mode keeps the camera still; the game window must be visible (an
unlocked, unobstructed desktop session: a locked screen stops the game rendering).
"""
import argparse, json, math, os, re, shutil, subprocess, sys, tempfile, threading, time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))
from themes import BY_KEY, THEMES  # noqa: E402

FPS = 30
OUT_W, OUT_H = 1920, 1080


# ------------------------------------------------------------------------------------------------ decoding
def decode_frame(path_or_img):
    """Rebuild an RGB uint8 image from a capture-mode screenshot (luma in red, alternating chroma in green)."""
    a = np.asarray(Image.open(path_or_img).convert("RGBA") if not isinstance(path_or_img, np.ndarray) else path_or_img, dtype=np.uint32)
    w = a[..., 0] | (a[..., 1] << 8) | (a[..., 2] << 16)
    y = (w & 1023).astype(np.float32) / 1023.0
    c = ((w >> 10) & 1023).astype(np.float32) / 1023.0 * 2.0 - 1.0
    h, wd = y.shape
    yy, xx = np.mgrid[0:h, 0:wd]
    even = ((xx + yy) & 1) == 0                    # even pixels carry Co, odd pixels carry Cg
    pad = np.pad(c, 1, mode="edge")
    nb = (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]) * 0.25     # the other component, from the 4 neighbours
    co = np.where(even, c, nb)
    cg = np.where(even, nb, c)
    t = y - cg * 0.5
    g = cg + t
    b = t - co * 0.5
    r = b + co
    return (np.clip(np.dstack([r, g, b]), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def encode_frame(rgb):
    """The inverse of decode_frame, mirroring the shader: used to test the decoder."""
    f = rgb.astype(np.float32) / 255.0
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    y = g * 0.5 + (r + b) * 0.25
    co = r - b
    cg = g - (r + b) * 0.5
    h, wd = y.shape
    yy, xx = np.mgrid[0:h, 0:wd]
    chroma = np.where(((xx + yy) & 1) == 0, co, cg) * 0.5 + 0.5
    r10 = np.round(y * 1023).astype(np.uint32)
    g10 = np.round(chroma * 1023).astype(np.uint32)
    word = r10 | (g10 << 10)
    out = np.zeros((h, wd, 4), dtype=np.uint8)
    out[..., 0] = word & 255
    out[..., 1] = (word >> 8) & 255
    out[..., 2] = (word >> 16) & 255
    out[..., 3] = 255
    return out


# ------------------------------------------------------------------------------------------------ audio
def read_sound(path, sr=44100):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<f4")


def mix_soundtrack(timeline, sounds_dir, offset, length, sr=44100):
    """Mix the timeline's sounds (event names like 'godly.fire') into a stereo wav-ready array, `offset` seconds late."""
    n = int(length * sr)
    mix = np.zeros(n, dtype=np.float32)
    cache = {}
    for ev in timeline["sounds"]:
        name = ev["event"]
        rel = name.replace(".", "/") if "." in name else name
        f = Path(sounds_dir) / f"{rel}.ogg"
        if not f.is_file():
            continue
        if name not in cache:
            cache[name] = read_sound(f, sr)
        x = cache[name]
        pitch = float(ev.get("pitch", 1.0))
        if abs(pitch - 1.0) > 1e-3:                                    # playsound pitch changes speed and pitch together
            idx = np.arange(0, len(x) - 1, pitch)
            x = np.interp(idx, np.arange(len(x)), x).astype(np.float32)
        start = max(int((ev["t"] + offset) * sr), 0)
        if start >= n:
            continue
        seg = x[: n - start] * float(ev.get("volume", 1.0))
        mix[start: start + len(seg)] += seg
    peak = float(np.max(np.abs(mix))) or 1.0
    mix = np.tanh(mix / peak * 1.6) / np.tanh(1.6) * 0.89                  # soft limiter, about -1 dBFS
    return np.stack([mix, mix], axis=1)


def write_wav(path, stereo, sr=44100):
    import wave
    pcm = (np.clip(stereo, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------------------------------------ title cards
def card(theme, out_png, line2=None):
    """A 1920x1080 title card: the item, the name and the theme."""
    W, H = OUT_W, OUT_H
    bg = Image.new("RGB", (W, H), "#0D1117")
    d = ImageDraw.Draw(bg)
    font_file = HERE / "fonts" / "Barlow-Medium.ttf"
    big = ImageFont.truetype(str(font_file), 150)
    mid = ImageFont.truetype(str(font_file), 78)
    small = ImageFont.truetype(str(font_file), 40)
    col = {"aqua": "#29A3FF", "gold": "#FF8800", "dark_purple": "#B07CFF", "yellow": "#FFD35A"}.get(theme.color, "#FFFFFF")
    icon = Image.open(ROOT / "orbital-laser-mod/assets/orbital/textures/item/laser_designator.png").convert("RGBA").resize((256, 256), Image.NEAREST)
    bg.paste(icon, (W // 2 - 128, 150), icon)
    for text, font, y, fill in (("ORBITAL LASER", big, 450, "#E8EAED"), (theme.title, mid, 640, col), (line2 or theme.blurb, small, 780, "#9AA4AF")):
        box = d.textbbox((0, 0), text, font=font)
        d.text(((W - (box[2] - box[0])) / 2 - box[0], y), text, font=font, fill=fill)
    d.rectangle([0, H - 14, W // 2, H], fill="#29A3FF")
    d.rectangle([W // 2, H - 14, W, H], fill="#FF8800")
    bg.save(out_png)


# ------------------------------------------------------------------------------------------------ recording
def find_ctl(arg):
    for c in (arg, os.environ.get("HORIZON_CTL"), shutil.which("horizon-ctl"), ROOT / "horizon-ctl", ROOT.parent / "horizon-ctl"):
        if c and Path(c).is_file():
            return str(c)
    sys.exit("Can't find horizon-ctl (pass --ctl or set HORIZON_CTL).")


class Recorder(threading.Thread):
    def __init__(self, ctl_path, outdir):
        super().__init__(daemon=True)
        self.ctl, self.outdir, self.stop_flag = ctl_path, Path(outdir), threading.Event()
        self.frames = []                   # (timestamp, path)
        self.t0 = time.time()

    def run(self):
        i = 0
        while not self.stop_flag.is_set():
            p = self.outdir / f"f{i:05d}.png"
            ta = time.time()
            r = subprocess.run([self.ctl, "screenshot", str(p)], capture_output=True)
            tb = time.time()
            if r.returncode == 0 and p.exists():
                self.frames.append(((ta + tb) / 2 - self.t0, p))
                i += 1


def luma_of(path):
    a = np.asarray(Image.open(path).convert("RGBA"), dtype=np.uint32)
    return float(((a[::8, ::8, 0] | ((a[::8, ::8, 1] & 3) << 8)).astype(np.float32) / 1023.0).mean())


def record(args):
    theme = BY_KEY[args.theme]
    ctl = find_ctl(args.ctl)
    tx, ty, tz = args.x, args.y, args.z
    work = Path(tempfile.mkdtemp(prefix="orbital-video-"))
    frames_dir = work / "frames"
    frames_dir.mkdir()
    sh = lambda *a: subprocess.run([ctl, *a], capture_output=True, text=True)
    st = json.loads(sh("state").stdout or "{}")
    if "player" not in st:
        sys.exit("The game isn't running (or isn't rendering: a locked screen stops it). Start it with horizon-ctl launch.")
    sh("command", "gamemode spectator")
    cam = (tx, ty + 24, tz - 52)
    sh("tp", *(str(round(v, 1)) for v in cam))
    time.sleep(0.5)
    sh("look-at", str(tx), str(ty + 4), str(tz))
    time.sleep(0.8)
    pack = None
    for home in (os.environ.get("HORIZON_HOME"), str(Path.home() / ".local/share/horizon")):
        if home and (Path(home) / "shaderpacks/orbital-laser-shader/pack.toml").is_file():
            pack = Path(home) / "shaderpacks/orbital-laser-shader/pack.toml"
            break
    mtime0 = pack.stat().st_mtime if pack else 0
    rec = Recorder(ctl, frames_dir)
    rec.start()
    time.sleep(1.2)                                           # a little baseline before the strike
    tl = work / "timeline.json"
    cmd = [sys.executable, str(ROOT / "strike.py"), "--at", str(tx), str(ty), str(tz), "--theme", theme.key, "--capture",
           "--timeline", str(tl), "--ctl", ctl] + (["--no-terrain"] if args.no_terrain else [])
    proc = subprocess.Popen(cmd)
    # the shader clock starts ~0.4 s after strike.py rewrites pack.toml
    t_write = None
    while proc.poll() is None and t_write is None:
        if pack and pack.stat().st_mtime != mtime0:
            t_write = time.time()
        time.sleep(0.02)
    t_shader0 = (t_write or time.time()) + 0.4
    moves = [(4.2, ("look-at", str(tx), str(ty + 70), str(tz), "--over", "9")), (14.5, ("look-at", str(tx), str(ty + 6), str(tz), "--over", "7"))]
    for t, c in moves:                                        # tilt up to follow the beam into the sky, then back down to the crater
        delay = t_shader0 + t - time.time()
        if delay > 0:
            time.sleep(delay)
        sh(*c)
    proc.wait()
    time.sleep(1.0)
    rec.stop_flag.set()
    rec.join(timeout=30)
    sh("look-at", str(tx), str(ty + 4), str(tz))
    sh("command", "gamemode creative")
    frames = rec.frames
    print(f"{len(frames)} frames captured over {frames[-1][0] - frames[0][0]:.1f} s ({len(frames) / (frames[-1][0] - frames[0][0]):.1f} fps)")
    return finish(args, theme, frames, rec.t0, t_shader0, tl, work)


def finish(args, theme, frames, rec_t0, t_shader0, tl, work):
    """Turn captured frames + the timeline into an MP4 with a title card."""
    ts = np.array([f[0] for f in frames])
    # find the impact flash: the brightest jump in the luma of the captured frames
    lum = np.array([luma_of(f[1]) for f in frames])
    base = np.median(lum[: max(3, len(lum) // 10)])
    jump = np.where(lum > base * 1.5 + 0.05)[0]
    t_fire = ts[jump[0]] if len(jump) else (t_shader0 - rec_t0) + 4.0
    t_clip0 = t_fire - 4.0 - 0.6                              # start a little before the shader clock does
    t_clip1 = t_fire - 4.0 + 27.0
    n_out = int((t_clip1 - t_clip0) * FPS)
    sel = []
    for k in range(n_out):
        t = t_clip0 + k / FPS
        sel.append(frames[int(np.argmin(np.abs(ts - t)))][1])
    outdir = work / "out"
    outdir.mkdir()
    cache = {}
    for k, p in enumerate(sel):
        if p not in cache:
            img = Image.fromarray(decode_frame(p))
            cache = {p: img.resize((OUT_W, OUT_H), Image.LANCZOS)}
        cache[p].save(outdir / f"{k:05d}.jpg", quality=95)
    timeline = json.loads(Path(tl).read_text())
    sounds_dir = ROOT / "orbital-sounds" / "assets" / "orbital" / "sounds"
    audio = mix_soundtrack(timeline, sounds_dir, offset=(t_fire - 4.0) - t_clip0, length=n_out / FPS)   # the shader clock starts here
    wav = work / "audio.wav"
    write_wav(wav, audio)
    card_png = work / "card.png"
    card(theme, card_png)
    out = Path(args.output or ROOT / "docs" / "videos" / f"orbital-laser-{theme.key}.mp4")
    out.parent.mkdir(parents=True, exist_ok=True)
    enc = ["-c:v", "libx264", "-preset", "slow", "-crf", "19", "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
    intro = work / "intro.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-loop", "1", "-t", "2.4", "-i", str(card_png), "-f", "lavfi", "-t", "2.4",
                    "-i", "anullsrc=r=44100:cl=stereo", "-vf", f"fade=t=in:st=0:d=0.5,fade=t=out:st=1.9:d=0.5,fps={FPS}", *enc, str(intro)], check=True)
    body = work / "body.mp4"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", str(FPS), "-i", str(outdir / "%05d.jpg"), "-i", str(wav),
                    "-vf", "fade=t=in:st=0:d=0.4,fade=t=out:st=" + f"{n_out / FPS - 0.8:.2f}" + ":d=0.8", "-af", "afade=t=out:st=" + f"{n_out / FPS - 1.5:.2f}" + ":d=1.5",
                    "-shortest", *enc, str(body)], check=True)
    lst = work / "list.txt"
    lst.write_text(f"file '{intro}'\nfile '{body}'\n")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(out)], check=True)
    print("wrote", out, f"{out.stat().st_size / 1e6:.1f} MB")
    if not args.keep:
        shutil.rmtree(work, ignore_errors=True)
    else:
        print("kept", work)
    return out


def reel(args):
    work = Path(tempfile.mkdtemp(prefix="orbital-reel-"))
    lst = work / "list.txt"
    lst.write_text("".join(f"file '{Path(p).resolve()}'\n" for p in args.clips))
    out = Path(args.output)
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(out)], check=True)
    shutil.rmtree(work, ignore_errors=True)
    print("wrote", out, f"{out.stat().st_size / 1e6:.1f} MB")


def selftest(_):
    rng = np.random.default_rng(1)
    # a smooth test picture (video chroma is subsampled, so a smooth one should round-trip closely)
    h, w = 90, 160
    yy, xx = np.mgrid[0:h, 0:w]
    img = np.dstack([128 + 100 * np.sin(xx / 17.0), 128 + 100 * np.sin(yy / 13.0), 128 + 100 * np.cos((xx + yy) / 21.0)]).clip(0, 255).astype(np.uint8)
    back = decode_frame(encode_frame(img))
    err = np.abs(back.astype(int) - img.astype(int))
    print(f"decoder round trip on a smooth picture: mean error {err.mean():.2f}/255, 99th percentile {np.percentile(err, 99):.0f}")
    assert err.mean() < 2.0
    # sharp colour edges: luma is exact, so edges stay in place; only chroma smears by one pixel
    edge = np.zeros((40, 40, 3), np.uint8); edge[:, 20:] = (255, 140, 0)
    e2 = decode_frame(encode_frame(edge))
    print("edge pixel (just left/right of the boundary):", e2[20, 19], e2[20, 20], "(expected about 0,0,0 / 255,140,0)")
    # soundtrack placement: a sound at t=1 s must start at 1 s
    d = Path(tempfile.mkdtemp())
    t = np.arange(44100) / 44100.0
    import wave
    w_ = wave.open(str(d / "tone.wav"), "wb"); w_.setnchannels(1); w_.setsampwidth(2); w_.setframerate(44100)
    w_.writeframes((np.sin(2 * np.pi * 440 * t) * 20000).astype("<i2").tobytes()); w_.close()
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(d / "tone.wav"), "-c:a", "libvorbis", str(d / "tone.ogg")], check=True)
    mix = mix_soundtrack({"sounds": [{"t": 1.0, "event": "tone", "volume": 1.0, "pitch": 1.0}]}, d, 0.5, 4.0)
    first = int(np.argmax(np.abs(mix[:, 0]) > 0.05)) / 44100
    print(f"a sound scheduled at t=1.0 s with 0.5 s offset starts at {first:.3f} s (expected 1.500)")
    assert abs(first - 1.5) < 0.02
    print("selftest ok")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="what", required=True)
    r = sub.add_parser("record"); r.add_argument("theme", choices=[t.key for t in THEMES])
    r.add_argument("x", type=int); r.add_argument("y", type=int); r.add_argument("z", type=int)
    r.add_argument("-o", "--output"); r.add_argument("--ctl"); r.add_argument("--no-terrain", action="store_true"); r.add_argument("--keep", action="store_true")
    q = sub.add_parser("reel"); q.add_argument("clips", nargs="+"); q.add_argument("-o", "--output", required=True)
    sub.add_parser("selftest")
    a = ap.parse_args()
    {"record": record, "reel": reel, "selftest": selftest}[a.what](a)
