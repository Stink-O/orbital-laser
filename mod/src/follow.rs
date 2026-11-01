//! The follow camera (`/orbital follow on`, the wheel's FOLLOW switch): as a Nuke or a Payload fires, the player is
//! made a spectator and moved every frame (`tp`, from the frame hook, so the camera moves at the frame rate, not the
//! tick's) along a path worked out from the bomb's own (`strike::bomb_path`, the one the pass draws it on):
//!
//! 1. a beat of the player's own view as it fires, then a cut to just behind and over the bomb, high in the sky
//!    where it shows (still there until it does);
//! 2. the chase: behind it and a little above, looking past it at the land it comes down on, all the way through its
//!    arc over into the dive;
//! 3. pulled back and out, well clear before it bursts, to a wide spot on the side it came down from (so the view
//!    turns only as far as from the dive to level), the burst low in the frame;
//! 4. held there, slowly backing off and tilting up as the cloud climbs;
//! 5. then the player put back where they stood, looking where they looked, in the game mode they were in.
//!
//! The game mode is kept on the player as a tag (`orbital_gm_*`), set by `execute if entity @s[gamemode=...]` as it
//! starts; with none found it goes back to creative.

use crate::strike::BombPath;

/// When each part starts and ends (strike seconds), and the distances, for the Nuke's bomb or the Payload's.
struct Shot {
    /// The cut from the player's view to the chase.
    cut: f64,
    /// The pull out to the wide spot.
    out: (f64, f64),
    /// When the player is put back.
    end: f64,
    /// The chase: this far behind the bomb (along its path), this far over it, looking at a point this far ahead.
    behind: f64,
    over: f64,
    ahead: f64,
    /// The wide spot: this far from the target (on the side the bomb came down from), this high over the higher of the
    /// target's ground and the player's feet, looking at this height over the target's ground; and how much further off,
    /// higher and higher it looks once the camera has backed off, `back` seconds after the burst.
    wide: f64,
    high: f64,
    look: f64,
    more: (f64, f64, f64),
    back: f64,
}

const NUKE: Shot = Shot {
    cut: 0.4,
    out: (8.6, 10.7),
    end: 40.0,
    behind: 34.0,
    over: 9.0,
    ahead: 25.0,
    wide: 430.0,
    high: 80.0,
    look: 95.0,
    more: (150.0, 45.0, 115.0),
    back: 22.0,
};
const PAYLOAD: Shot = Shot {
    cut: 0.4,
    out: (11.6, 13.4),
    end: 32.0,
    behind: 26.0,
    over: 7.0,
    ahead: 20.0,
    wide: 230.0,
    high: 45.0,
    look: 40.0,
    more: (80.0, 25.0, 70.0),
    back: 18.0,
};

/// The player's eyes over their feet.
const EYE: f64 = 1.62;

pub struct Follow {
    path: BombPath,
    shot: &'static Shot,
    /// Where the player stood and looked as it fired.
    feet0: [f64; 3],
    yaw0: f32,
    pitch0: f32,
    /// Level, from the target towards the wide spot, and the wide spot's height.
    u: [f64; 3],
    base: f64,
    /// The yaw last sent, so the next is sent the same way round (no jump from 180 to -180).
    last_yaw: f32,
}

fn add(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
}
fn sub(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    add(a, b, -1.0)
}
fn norm(a: [f64; 3]) -> [f64; 3] {
    let l = (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt();
    if l < 1e-9 { [0.0, 0.0, 1.0] } else { [a[0] / l, a[1] / l, a[2] / l] }
}
fn lerp(a: [f64; 3], b: [f64; 3], k: f64) -> [f64; 3] {
    add(a, sub(b, a), k)
}
/// 0 to 1 from `a` to `b`, eased in and out with no jerk at either end.
fn ease(a: f64, b: f64, t: f64) -> f64 {
    let x = ((t - a) / (b - a)).clamp(0.0, 1.0);
    x * x * x * (x * (6.0 * x - 15.0) + 10.0)
}
/// The way yaw and pitch look (the game's: yaw 0 looks along +z, 90 along -x; pitch 90 straight down).
fn dir_of(yaw: f32, pitch: f32) -> [f64; 3] {
    let (y, p) = (f64::from(yaw).to_radians(), f64::from(pitch).to_radians());
    [-y.sin() * p.cos(), -p.sin(), y.cos() * p.cos()]
}
fn yaw_pitch(d: [f64; 3]) -> (f32, f32) {
    let d = norm(d);
    ((-d[0]).atan2(d[2]).to_degrees() as f32, (-d[1].clamp(-1.0, 1.0).asin().to_degrees()) as f32)
}

impl Follow {
    /// A follow of `path`'s bomb, the player standing at `feet` looking `yaw`, `pitch` as it fires.
    pub fn new(path: BombPath, feet: [f64; 3], yaw: f32, pitch: f32) -> Follow {
        let shot = if path.big { &NUKE } else { &PAYLOAD };
        let g = path.ground;
        let base = g[1].max(feet[1]) + shot.high;
        let mut f = Follow { path, shot, feet0: feet, yaw0: yaw, pitch0: pitch, u: [0.0, 0.0, 1.0], base, last_yaw: yaw };
        // (the wide spot on the side the bomb comes down from, where the chase is as it pulls out; else the player's)
        let b = f.bomb(shot.out.0);
        let (dx, dz) = (b[0] - g[0], b[2] - g[2]);
        f.u = if dx.hypot(dz) > 1.0 { norm([dx, 0.0, dz]) } else { norm([feet[0] - g[0], 0.0, feet[2] - g[2]]) };
        f
    }
    /// Where the bomb is at strike time `t` (where it shows before then, where it bursts after).
    fn bomb(&self, t: f64) -> [f64; 3] {
        let p = &self.path.pts;
        let u = ((t - self.path.seen) / self.path.dt).clamp(0.0, (p.len() - 1) as f64);
        let i = (u.floor() as usize).min(p.len().saturating_sub(2));
        lerp(p[i], p[(i + 1).min(p.len() - 1)], u - i as f64)
    }
    /// The way it is going at `t`.
    fn heading(&self, t: f64) -> [f64; 3] {
        let t = t.clamp(self.path.seen + 0.2, self.path.hit);
        norm(sub(self.bomb(t), self.bomb(t - 0.2)))
    }
    /// The chase's eye and the way it looks at `t`.
    fn chase(&self, t: f64) -> ([f64; 3], [f64; 3]) {
        let s = self.shot;
        let (b, h) = (self.bomb(t), self.heading(t));
        let eye = add(add(b, h, -s.behind), [0.0, 1.0, 0.0], s.over);
        (eye, norm(sub(add(b, h, s.ahead), eye)))
    }
    /// The wide spot's eye and the way it looks at `t`, backing off after the burst.
    fn wide(&self, t: f64) -> ([f64; 3], [f64; 3]) {
        let s = self.shot;
        let k = ease(self.path.hit, self.path.hit + s.back, t);
        let g = self.path.ground;
        let r = s.wide + s.more.0 * k;
        let eye = [g[0] + self.u[0] * r, self.base + s.more.1 * k, g[2] + self.u[2] * r];
        let at = [g[0], g[1] + s.look + s.more.2 * k, g[2]];
        (eye, norm(sub(at, eye)))
    }
    /// Where the eye is and the way it looks at strike time `t`.
    pub fn pose(&self, t: f64) -> ([f64; 3], [f64; 3]) {
        let s = self.shot;
        if t < s.cut {
            return (add(self.feet0, [0.0, 1.0, 0.0], EYE), dir_of(self.yaw0, self.pitch0));
        }
        if t < s.out.0 {
            return self.chase(t);
        }
        if t < s.out.1 {
            let k = ease(s.out.0, s.out.1, t);
            let (ce, cd) = self.chase(t);
            let (we, wd) = self.wide(t);
            return (lerp(ce, we, k), norm(lerp(cd, wd, k)));
        }
        self.wide(t)
    }
    /// Whether it is over by strike time `t`.
    pub fn over(&self, t: f64) -> bool {
        t >= self.shot.end
    }
    /// The command that puts the camera where it is at `t`.
    pub fn tp(&mut self, t: f64) -> String {
        let (eye, d) = self.pose(t);
        let (mut yaw, pitch) = yaw_pitch(d);
        yaw += 360.0 * ((self.last_yaw - yaw) / 360.0).round();
        self.last_yaw = yaw;
        format!("tp @s {:.4} {:.4} {:.4} {:.3} {:.3}", eye[0], eye[1] - EYE, eye[2], yaw, pitch.clamp(-90.0, 90.0))
    }
    /// What starts it: the game mode kept as a tag, the player made a spectator.
    pub fn start() -> Vec<String> {
        let mut c = vec!["tag @s remove orbital_gm_survival".to_string(), "tag @s remove orbital_gm_adventure".to_string(), "tag @s remove orbital_gm_creative".to_string(), "tag @s remove orbital_gm_spectator".to_string()];
        for m in ["survival", "adventure", "creative", "spectator"] {
            c.push(format!("execute if entity @s[gamemode={m}] run tag @s add orbital_gm_{m}"));
        }
        c.push("gamemode spectator".into());
        c
    }
    /// What ends it: the player back where they stood, looking where they looked, in their game mode.
    pub fn finish(&self) -> Vec<String> {
        let [x, y, z] = self.feet0;
        let mut c = vec![
            format!("tp @s {x:.4} {y:.4} {z:.4} {:.3} {:.3}", self.yaw0, self.pitch0),
            "execute unless entity @s[tag=orbital_gm_survival] unless entity @s[tag=orbital_gm_adventure] unless entity @s[tag=orbital_gm_spectator] run gamemode creative".into(),
        ];
        for m in ["survival", "adventure", "spectator"] {
            c.push(format!("execute if entity @s[tag=orbital_gm_{m}] run gamemode {m}"));
        }
        for m in ["survival", "adventure", "creative", "spectator"] {
            c.push(format!("tag @s remove orbital_gm_{m}"));
        }
        c
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::strike::{Target, bomb_path};

    fn follow(key: &str, me: [f64; 3]) -> Follow {
        let target = Target { block: [100, 70, -40], point: [100.5, 71.0, -39.5] };
        Follow::new(bomb_path(key, &target, 211.0, me).expect("a bomb"), me, 30.0, 10.0)
    }

    #[test]
    fn smooth_and_clear_of_the_blast() {
        for key in ["nuke", "payload"] {
            let f = follow(key, [400.0, 72.0, -40.0]);
            let g = f.path.ground;
            // (it starts where the player stands, looking where they look)
            let (e, d) = f.pose(0.0);
            assert!((e[0] - 400.0).abs() < 1e-6 && (e[1] - 73.62).abs() < 1e-6);
            let (yaw, pitch) = yaw_pitch(d);
            assert!((yaw - 30.0).abs() < 0.01 && (pitch - 10.0).abs() < 0.01, "{yaw} {pitch}");
            // no jump from one frame to the next (at 60 fps), however fast it goes, and the view turns smoothly
            let dt = 1.0 / 60.0;
            let mut t = 0.0;
            let (mut pe, mut pd) = f.pose(0.0);
            let mut fastest: f64 = 0.0;
            while t < f.shot.end {
                t += dt;
                let (e, d) = f.pose(t);
                let step = (sub(e, pe)[0].powi(2) + sub(e, pe)[1].powi(2) + sub(e, pe)[2].powi(2)).sqrt();
                fastest = fastest.max(step);
                let turn = (d[0] * pd[0] + d[1] * pd[1] + d[2] * pd[2]).clamp(-1.0, 1.0).acos().to_degrees();
                // (but at the cut)
                if t - dt >= f.shot.cut {
                    assert!(step < 40.0, "{key} at {t}: {step} blocks in a frame");
                    assert!(turn < 1.5, "{key} at {t}: turned {turn} degrees in a frame");
                }
                (pe, pd) = (e, d);
            }
            // well clear of the blast from just before it bursts: past the flattened land
            let clear = if key == "nuke" { 400.0 } else { 200.0 };
            let (e, _) = f.pose(f.path.hit - 0.3);
            assert!((e[0] - g[0]).hypot(e[2] - g[2]) > clear, "{key}: {:?}", e);
            assert!(f.over(f.shot.end) && !f.over(f.shot.end - 1.0));
            // and in the chase, close behind the bomb, looking near it
            let t = (f.shot.cut + f.shot.out.0) / 2.0;
            let (e, d) = f.pose(t);
            let b = f.bomb(t);
            let to = norm(sub(b, e));
            assert!(((b[0] - e[0]).powi(2) + (b[1] - e[1]).powi(2) + (b[2] - e[2]).powi(2)).sqrt() < 50.0);
            assert!((to[0] * d[0] + to[1] * d[1] + to[2] * d[2]) > 0.9);
            let _ = fastest;
        }
    }

    #[test]
    fn puts_the_player_back() {
        let f = follow("nuke", [400.0, 72.0, -40.0]);
        let s = Follow::start();
        assert_eq!(s.last().map(String::as_str), Some("gamemode spectator"));
        let e = f.finish();
        assert!(e[0].starts_with("tp @s 400.0000 72.0000 -40.0000 30.000 10.000"));
        assert!(e.iter().any(|c| c.ends_with("run gamemode creative")));
    }
}

#[cfg(test)]
mod profile {
    use super::*;
    use crate::strike::{Target, bomb_path};
    /// The shot, a line every quarter second: where the eye is from the target, how far from the bomb, which way it
    /// looks, and its fastest move and turn a frame (60 fps) in that quarter (`cargo test --lib follow_profile -- --ignored --nocapture`).
    #[test]
    #[ignore]
    fn follow_profile() {
        for key in ["nuke", "payload"] {
            let target = Target { block: [100, 70, -40], point: [100.5, 71.0, -39.5] };
            let f = Follow::new(bomb_path(key, &target, 211.0, [400.0, 72.0, -40.0]).expect("a bomb"), [400.0, 72.0, -40.0], 30.0, 10.0);
            let g = f.path.ground;
            let dt = 1.0 / 60.0;
            let (mut pe, mut pd) = f.pose(0.0);
            let (mut ms, mut mt) = (0.0f64, 0.0f64);
            for i in 1..(f.shot.end / dt) as usize {
                let t = i as f64 * dt;
                let (e, d) = f.pose(t);
                ms = ms.max((sub(e, pe)[0].powi(2) + sub(e, pe)[1].powi(2) + sub(e, pe)[2].powi(2)).sqrt());
                mt = mt.max((d[0] * pd[0] + d[1] * pd[1] + d[2] * pd[2]).clamp(-1.0, 1.0).acos().to_degrees());
                (pe, pd) = (e, d);
                if i % 15 == 0 && t < 16.0 {
                    let b = f.bomb(t);
                    let (y, p) = yaw_pitch(d);
                    println!("{key} {t:5.2} eye {:6.0} {:5.0} {:6.0}  bomb at {:5.0}  look {y:6.1} {p:5.1}  max {ms:5.1} b/f {mt:4.2} deg/f", e[0] - g[0], e[1] - g[1], e[2] - g[2], (sub(b, e)[0].powi(2) + sub(b, e)[1].powi(2) + sub(b, e)[2].powi(2)).sqrt());
                    (ms, mt) = (0.0, 0.0);
                }
            }
        }
    }
}
