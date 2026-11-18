//! `/orbital tune`: a laser's numbers set in the game, without a rebuild.
//!
//! A laser declares its knobs in `KNOBS` (laser, key, default, range, meaning, and for a shader knob its slot) and reads
//! them with `tune::get(laser, key)` (Rust: the value now, so a strike's plan takes it when it is made) or, in its pass,
//! `tune_knob(slot, default)` (strike.wgsl), which reads the block `send` puts at the end of `mod_data`:
//! `SLOTS` words (the slots' values as f32 bits) and then `MAGIC`. The block is added only for a laser with shader
//! knobs, and sent again as soon as one changes. A laser that declares none is untouched.
//!
//! `/orbital tune` lists the loaded laser's knobs, `/orbital tune KEY VALUE` sets one (clamped to its range),
//! `/orbital tune reset [KEY]` puts them back. Values are kept in the mod's storage (`STORE`), `laser.key=value` a line.
use crate::sdk::{log, render, storage};
use std::cell::{Cell, RefCell};

/// One number a laser lets the player set.
pub struct Knob {
    pub laser: &'static str,
    pub key: &'static str,
    pub default: f32,
    pub min: f32,
    pub max: f32,
    /// The word of the shader block it is written to (`tune_knob(slot, ...)` in the pass), or none: Rust only.
    pub slot: Option<u8>,
    pub help: &'static str,
}

/// Every laser's knobs. Add a laser's as a block of lines; keep slots below `SLOTS` and unique per laser.
pub static KNOBS: &[Knob] = &[
    // the Convergence: its land and its push take effect on the next strike; the pass's at once
    Knob { laser: "convergence", key: "crater", default: 84.0, min: 50.0, max: 120.0, slot: None, help: "the crater's radius, blocks (next strike)" },
    Knob { laser: "convergence", key: "depth", default: 42.0, min: 20.0, max: 70.0, slot: None, help: "the crater's depth, blocks (next strike)" },
    Knob { laser: "convergence", key: "turn", default: 220.0, min: 100.0, max: 248.0, slot: None, help: "how far out the land turns Nether and pale, blocks (next strike)" },
    Knob { laser: "convergence", key: "knock", default: 1.0, min: 0.0, max: 3.0, slot: None, help: "the blast's knockback, times (next strike)" },
    Knob { laser: "convergence", key: "jolt", default: 1.0, min: 0.0, max: 3.0, slot: None, help: "the camera jolts of the surges and the blast, times (next strike)" },
    Knob { laser: "convergence", key: "islands", default: 7.0, min: 0.0, max: 16.0, slot: None, help: "how many islands are left hanging in the sky (next strike)" },
    Knob { laser: "convergence", key: "glow", default: 1.0, min: 0.0, max: 3.0, slot: Some(0), help: "the columns' brightness (at once)" },
    Knob { laser: "convergence", key: "burst", default: 1.0, min: 0.5, max: 2.0, slot: Some(1), help: "the burst's size (at once)" },
    Knob { laser: "convergence", key: "flash", default: 1.0, min: 0.0, max: 2.0, slot: Some(2), help: "the blast's flash (at once)" },
    Knob { laser: "convergence", key: "haze", default: 1.0, min: 0.0, max: 3.0, slot: Some(3), help: "the haze and glow in the air (at once)" },
    Knob { laser: "convergence", key: "dusk", default: 1.0, min: 0.0, max: 1.5, slot: Some(4), help: "how far the day goes out while the worlds fight (at once)" },
    // the Earthquake: its plates and its push take effect on the next strike; the pass's and the warp's at once
    Knob { laser: "earthquake", key: "reach", default: 160.0, min: 100.0, max: 220.0, slot: None, help: "the plates' zone's radius, blocks (next strike)" },
    Knob { laser: "earthquake", key: "slip", default: 1.0, min: 0.3, max: 2.0, slot: None, help: "how far the plates slip along the faults, times (next strike)" },
    Knob { laser: "earthquake", key: "heave", default: 1.0, min: 0.0, max: 2.0, slot: None, help: "how far the plates rise and drop, times (next strike)" },
    Knob { laser: "earthquake", key: "pace", default: 1.0, min: 0.6, max: 1.6, slot: None, help: "how long each lurch takes, times (next strike)" },
    Knob { laser: "earthquake", key: "knock", default: 1.0, min: 0.0, max: 3.0, slot: None, help: "the shocks' knockback, times (next strike)" },
    Knob { laser: "earthquake", key: "jolt", default: 1.0, min: 0.0, max: 3.0, slot: None, help: "the camera jolts, times (next strike)" },
    Knob { laser: "earthquake", key: "dust", default: 1.0, min: 0.0, max: 3.0, slot: Some(0), help: "the dust along the faults (at once)" },
];

/// Shader slots in the block at the end of `mod_data` (keep strike.wgsl's TUNE_SLOTS in step).
pub const SLOTS: usize = 16;
/// The block's last word ("TUNE"): the pass reads the block only when it is there.
pub const MAGIC: u32 = 0x5455_4E45;
const STORE: &str = "tune";

thread_local! {
    static VALUES: RefCell<Option<Vec<(String, f32)>>> = const { RefCell::new(None) };
    static DIRTY: Cell<bool> = const { Cell::new(false) };
}

#[cfg(test)]
static TEST_KNOBS: &[Knob] = &[
    Knob { laser: "tunetest", key: "width", default: 4.0, min: 1.0, max: 10.0, slot: Some(0), help: "a test knob" },
    Knob { laser: "tunetest", key: "delay", default: 0.5, min: 0.0, max: 2.0, slot: None, help: "a Rust-only test knob" },
];

fn knobs() -> impl Iterator<Item = &'static Knob> {
    #[cfg(test)]
    let k = KNOBS.iter().chain(TEST_KNOBS.iter());
    #[cfg(not(test))]
    let k = KNOBS.iter();
    k
}

fn knob(laser: &str, key: &str) -> Option<&'static Knob> {
    knobs().find(|k| k.laser == laser && k.key == key)
}

fn with_values<R>(f: impl FnOnce(&mut Vec<(String, f32)>) -> R) -> R {
    VALUES.with(|v| {
        let mut v = v.borrow_mut();
        let vals = v.get_or_insert_with(|| {
            let text = storage::get(STORE).map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
            text.lines()
                .filter_map(|l| l.split_once('='))
                .filter_map(|(k, v)| v.trim().parse::<f32>().ok().filter(|x| x.is_finite()).map(|x| (k.trim().to_string(), x)))
                .collect()
        });
        f(vals)
    })
}

fn save(vals: &[(String, f32)]) {
    let text: String = vals.iter().map(|(k, v)| format!("{k}={v}\n")).collect();
    if let Err(e) = storage::set(STORE, text.as_bytes()) {
        log::write(log::Level::Warn, &format!("tune values not saved: {e}"));
    }
}

/// A knob's value: the one set (clamped to its range as it is now), else its default; 0 for a knob not declared.
pub fn get(laser: &str, key: &str) -> f32 {
    let Some(k) = knob(laser, key) else { return 0.0 };
    let id = format!("{laser}.{key}");
    with_values(|v| v.iter().find(|(n, _)| *n == id).map_or(k.default, |(_, x)| x.clamp(k.min, k.max)))
}

/// Whether a laser has knobs at all.
pub fn has_knobs(laser: &str) -> bool {
    knobs().any(|k| k.laser == laser)
}

fn line(k: &Knob) -> String {
    let v = get(k.laser, k.key);
    let mark = if v != k.default { " (set)" } else { "" };
    format!("{} = {v}{mark}  [{}..{}, default {}]  {}", k.key, k.min, k.max, k.default, k.help)
}

/// `/orbital tune [KEY VALUE | reset [KEY]]` for the loaded laser: the reply, or what was wrong.
pub fn command(laser: &str, a: Option<&str>, b: Option<&str>) -> Result<String, String> {
    match (a, b) {
        (None, _) => {
            let list: Vec<String> = knobs().filter(|k| k.laser == laser).map(line).collect();
            Ok(if list.is_empty() { format!("{laser} has no tune knobs") } else { format!("{laser}:\n{}", list.join("\n")) })
        }
        (Some("reset"), key) => {
            if let Some(key) = key
                && knob(laser, key).is_none()
            {
                return Err(format!("{laser} has no tune knob {key:?} (/orbital tune lists them)"));
            }
            let pre = format!("{laser}.");
            with_values(|v| {
                v.retain(|(n, _)| match key {
                    Some(key) => *n != format!("{pre}{key}"),
                    None => !n.starts_with(&pre),
                });
                save(v);
            });
            DIRTY.set(true);
            Ok(match key {
                Some(key) => format!("{laser} {key}: back to {}", get(laser, key)),
                None => format!("{laser}: every knob back to its default"),
            })
        }
        (Some(key), value) => {
            let Some(k) = knob(laser, key) else {
                return Err(format!("{laser} has no tune knob {key:?} (/orbital tune lists them)"));
            };
            let Some(value) = value else { return Ok(line(k)) };
            let x = value.parse::<f32>().ok().filter(|x| x.is_finite()).ok_or_else(|| format!("not a number: {value}"))?;
            let x = x.clamp(k.min, k.max);
            let id = format!("{laser}.{key}");
            with_values(|v| {
                match v.iter_mut().find(|(n, _)| *n == id) {
                    Some(e) => e.1 = x,
                    None => v.push((id, x)),
                }
                save(v);
            });
            DIRTY.set(true);
            Ok(format!("{laser} {key} = {x}{}", if k.slot.is_some() { "" } else { " (from the next strike)" }))
        }
    }
}

/// The words added to the end of `mod_data` for a laser with shader knobs: the slots, then `MAGIC`.
pub fn block(laser: &str) -> Option<[u32; SLOTS + 1]> {
    let mut w = [0u32; SLOTS + 1];
    let mut any = false;
    for k in knobs().filter(|k| k.laser == laser) {
        if let Some(s) = k.slot.filter(|&s| usize::from(s) < SLOTS) {
            w[usize::from(s)] = get(laser, k.key).to_bits();
            any = true;
        }
    }
    w[SLOTS] = MAGIC;
    any.then_some(w)
}

/// A knob changed since the last `send` (the pass's block is out of date).
pub fn dirty() -> bool {
    DIRTY.get()
}

/// `render::set_data` with the laser's knob block after its own words (only the words for a laser without one).
pub fn send(data: &[u32], laser: &str) {
    DIRTY.set(false);
    match block(laser) {
        Some(b) => {
            let mut all = Vec::with_capacity(data.len() + b.len());
            all.extend_from_slice(data);
            all.extend_from_slice(&b);
            render::set_data(&all);
        }
        None => render::set_data(data),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_set_clamp_reset() {
        assert_eq!(get("tunetest", "width"), 4.0);
        assert!(command("tunetest", Some("width"), Some("7.5")).is_ok());
        assert_eq!(get("tunetest", "width"), 7.5);
        command("tunetest", Some("width"), Some("99")).unwrap();
        assert_eq!(get("tunetest", "width"), 10.0);
        command("tunetest", Some("delay"), Some("-3")).unwrap();
        assert_eq!(get("tunetest", "delay"), 0.0);
        command("tunetest", Some("reset"), Some("width")).unwrap();
        assert_eq!(get("tunetest", "width"), 4.0);
        assert_eq!(get("tunetest", "delay"), 0.0);
        command("tunetest", Some("reset"), None).unwrap();
        assert_eq!(get("tunetest", "delay"), 0.5);
    }

    #[test]
    fn kept_in_storage() {
        command("tunetest", Some("width"), Some("3")).unwrap();
        // (a fresh start reads the stored values back)
        VALUES.with(|v| *v.borrow_mut() = None);
        assert_eq!(get("tunetest", "width"), 3.0);
        let stored = storage::get(STORE).map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
        assert!(stored.contains("tunetest.width=3"));
    }

    #[test]
    fn unknown_key_and_bad_value() {
        let e = command("tunetest", Some("nope"), Some("1")).unwrap_err();
        assert!(e.contains("no tune knob"));
        assert!(command("tunetest", Some("reset"), Some("nope")).is_err());
        assert!(command("tunetest", Some("width"), Some("wide")).is_err());
        assert_eq!(get("tunetest", "nope"), 0.0);
        assert!(command("rod", None, None).unwrap().contains("no tune knobs"));
    }

    #[test]
    fn block_only_for_shader_knobs() {
        assert!(block("rod").is_none());
        let b = block("tunetest").unwrap();
        assert_eq!(b[SLOTS], MAGIC);
        assert_eq!(f32::from_bits(b[0]), get("tunetest", "width"));
        assert!(!has_knobs("rod") && has_knobs("tunetest"));
    }
}
