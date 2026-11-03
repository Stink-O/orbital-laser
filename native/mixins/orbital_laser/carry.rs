// The fork's `world.carry-player` (its motion.rs `carry_step`, `carry_release`, `CarryState` and game/mods.rs
// `player_tick`), in the client library beside the local player's motion: the glue (in the game) asks a carry and
// reads the answer; a cancellable HEAD on the local player's tick (`carry_tick.rs`) carries them in place of their own
// motion while it holds.
use crate::motion::MotionWorld;
use crate::sprint::Keys;
use horizon_core::geometry::Vec3;
use std::cell::RefCell;
use std::ops::ControlFlow;

/// How many ticks running sneak must be held to break free of a carry (half a second), and the most of its motion
/// across they keep once let go (blocks a tick).
pub const CARRY_BREAK_TICKS: u8 = 10;
pub const CARRY_KEEP: f64 = 0.45;

/// What a carry keeps from tick to tick: whether one was asked the tick before, whether they broke free of it, for
/// how many ticks running they have held sneak, and the throw a push gave while it held them.
#[derive(Clone, Copy, Debug, Default)]
struct CarryState {
    asked: bool,
    free: bool,
    sneak: u8,
    throw: Option<Vec3>,
}
impl CarryState {
    fn holding(&self) -> bool {
        self.asked && !self.free
    }
}

/// The carry the mod asked for this tick (the move, and the view's turn in degrees), whether the last one asked for
/// held the player, what the carry keeps, and the turn of the view while it holds (degrees a tick).
#[derive(Default)]
struct Carry {
    asked: Option<(Vec3, f32)>,
    refused: bool,
    state: CarryState,
    turn: f32,
}

thread_local! {
    static CARRY: RefCell<Carry> = RefCell::new(Carry::default());
}

/// The mod's carry for the player's next tick.
pub fn ask(delta: [f32; 3], turn: f32) {
    let [x, y, z] = delta.map(f64::from);
    CARRY.with(|c| c.borrow_mut().asked = Some((Vec3::new(x, y, z), turn)));
}

/// A push while the carry holds them is its throw (pushes add up): true when taken so.
pub fn push(v: [f32; 3]) -> bool {
    CARRY.with(|c| {
        let mut c = c.borrow_mut();
        if !c.state.holding() {
            return false;
        }
        let [x, y, z] = v.map(f64::from);
        let v = Vec3::new(x, y, z);
        c.state.throw = Some(c.state.throw.map_or(v, |t| t.add_vector(v)));
        true
    })
}

/// Whether the last carry asked held the player (true when none was asked: the next holds).
pub fn carried() -> bool {
    CARRY.with(|c| !c.borrow().refused)
}

/// The view's turn while a carry holds them, degrees a tick.
pub fn turn() -> f32 {
    CARRY.with(|c| c.borrow().turn)
}

/// The world was left: no carry, nothing kept of one.
pub fn reset() {
    CARRY.with(|c| *c.borrow_mut() = Carry::default());
}

/// Before the mod's tick: a carry asked and never taken (the player sleeping, dead or riding, whose tick doesn't
/// move them) holds nobody.
pub fn untaken() {
    CARRY.with(|c| {
        let mut c = c.borrow_mut();
        if c.asked.take().is_some() {
            c.refused = false;
            c.turn = 0.0;
        }
    })
}

/// The local player's tick (a HEAD on it): carried by the mod's carry if one was asked and holds them (`Break`: their
/// own motion doesn't run), else their own motion (`Continue`).
pub fn player_tick(world: &mut MotionWorld<'_, '_, '_>, keys: Keys) -> ControlFlow<crate::Result<()>> {
    CARRY.with(|c| {
        let mut c = c.borrow_mut();
        let c = &mut *c;
        let asked = c.asked.take();
        let held = match carry_step(world, keys, asked.map(|(d, _)| d), &mut c.state) {
            Ok(held) => held,
            Err(e) => return ControlFlow::Break(Err(e)),
        };
        c.refused = asked.is_some() && !held;
        c.turn = asked.filter(|_| held).map_or(0.0, |(_, turn)| turn);
        if held { ControlFlow::Break(Ok(())) } else { ControlFlow::Continue(()) }
    })
}

/// One tick of a carry: `carry` the move asked for this tick (none: not carried). True when it held them: moved by
/// the carry through the collision move in place of their own motion (no gravity, no drag, their walking left out,
/// their fall distance kept at nothing, out of creative flight and any glide); false for the normal tick to run.
/// Only sneak held `CARRY_BREAK_TICKS` running lets go; once free they stay free until a tick with no carry asked.
/// Let go, they keep only a little of its motion and are put back into creative flight in the air, unless the mod
/// threw them (a push while carried): then exactly that, out of flight. A spectator is never carried.
fn carry_step(
    world: &mut MotionWorld<'_, '_, '_>,
    keys: Keys,
    carry: Option<Vec3>,
    state: &mut CarryState,
) -> crate::Result<bool> {
    let was_asked = std::mem::replace(&mut state.asked, carry.is_some());
    let Some(delta) = carry else {
        if was_asked && !state.free {
            match state.throw {
                Some(v) => {
                    world.player.velocity = v;
                    world.player.flying = false;
                    world.player.ground.on_ground = false;
                    world.player.fall_distance = 0.0;
                }
                None => carry_release(world),
            }
        }
        state.free = false;
        state.sneak = 0;
        state.throw = None;
        return Ok(false);
    };
    if !was_asked {
        state.free = false;
        state.sneak = 0;
        state.throw = None;
    }
    if state.free || world.player.spectator {
        return Ok(false);
    }
    state.sneak = if keys.shift { state.sneak.saturating_add(1) } else { 0 };
    if state.sneak >= CARRY_BREAK_TICKS {
        state.free = true;
        carry_release(world);
        return Ok(false);
    }
    // (held: out of creative flight and any glide, whatever the keys or the server said; the jump key's last state
    // kept so a double jump just after needs two fresh presses)
    let p = &mut *world.player;
    p.flying = false;
    p.fall_flying = false;
    p.jump_trigger_time = 0;
    p.was_jumping = keys.jump;
    p.shift_key_down = false;
    p.health.advance_clock();
    p.old_position = p.position;
    p.fall_distance = 0.0;
    p.velocity = delta;
    world.move_self(delta)?;
    world.player.fall_distance = 0.0;
    // (no longer swimming, stood up: carried through the air)
    world.player.swimming = false;
    world.update_player_pose()?;
    Ok(true)
}

/// Let go of a carry: a little of its motion kept (at most `CARRY_KEEP` blocks a tick across, a gentle drift up or
/// down), their fall distance nothing; back into creative flight when they may fly and are off the ground.
fn carry_release(world: &mut MotionWorld<'_, '_, '_>) {
    let p = &mut *world.player;
    let v = p.velocity;
    let across = (v.x * v.x + v.z * v.z).sqrt();
    let k = if across * 0.35 > CARRY_KEEP { CARRY_KEEP / across } else { 0.35 };
    p.velocity = Vec3::new(v.x * k, (v.y * 0.3).clamp(-0.3, 0.1), v.z * k);
    p.fall_distance = 0.0;
    if p.may_fly && !p.ground.on_ground {
        p.flying = true;
    }
}
