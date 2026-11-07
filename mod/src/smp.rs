//! Small, versioned strike events. Only the firing client edits the world;
//! observers play the same seeded visual/sound timeline without edits.
use serde::{Deserialize, Serialize};
use std::cell::{Cell, RefCell};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Launch {
    pub laser: usize,
    pub block: [i32; 3],
    pub point: [f64; 3],
    pub origin: [f64; 3],
    pub seed: u32,
    pub approach: usize,
    pub arrival: usize,
    pub colour: usize,
    pub option: usize,
    pub elapsed: f32,
    pub dimension: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Packet {
    Hello,
    Start(Launch),
    /// A periodic heartbeat from the firing client while its strike runs: the same
    /// `Launch` with `elapsed` brought up to date. Lets an observer who missed the
    /// `Start` (a dropped packet, or one that arrived before they loaded in) catch
    /// up, and corrects drift on a long strike instead of only setting it up once.
    Sync(Launch),
    Stop,
    Denied,
}

impl Launch {
    pub fn valid(&self) -> bool {
        self.laser < crate::lasers::LASERS.len()
            && self.approach < crate::strike::APPROACHES.len()
            && self.arrival < crate::strike::ARRIVALS.len()
            && self.colour < crate::strike::COLOURS.len()
            && self.seed > 0 && self.seed <= 1_000_000
            && self.elapsed.is_finite() && self.elapsed >= 0.0
            && self.elapsed < crate::lasers::LASERS[self.laser].length
            && self.dimension.len() <= 128
            && self.point.iter().chain(self.origin.iter()).all(|v| v.is_finite() && v.abs() <= 30_000_000.0)
            && self.block.iter().all(|v| v.unsigned_abs() <= 30_000_000)
    }
    pub fn duration(&self) -> f32 { crate::lasers::LASERS[self.laser].length }
}

pub fn decode(data: &[u8]) -> Option<Packet> {
    if data.len() > 4096 { return None }
    let packet: Packet = serde_json::from_slice(data).ok()?;
    match &packet { Packet::Start(s) | Packet::Sync(s) if !s.valid() => None, _ => Some(packet) }
}

thread_local! {
    static REMOTE: RefCell<Option<Launch>> = const { RefCell::new(None) };
    static OBSERVER: Cell<bool> = const { Cell::new(false) };
    static OUT: RefCell<Vec<Packet>> = const { RefCell::new(Vec::new()) };
    /// The strike this client itself is firing right now, kept around only to fill in
    /// a fresh `elapsed` on each heartbeat; `None` once it is stopped or finishes.
    static OWN: RefCell<Option<Launch>> = const { RefCell::new(None) };
    /// Packets decoded off the wire but not yet handed to the running `Orbital`:
    /// `receive` has no way to reach it (it runs outside `Mod`'s own methods, wherever
    /// the host delivers network data), so it queues here for `tick` to drain, the
    /// same way `OUT` queues what `tick` has to send.
    static IN: RefCell<Vec<Packet>> = const { RefCell::new(Vec::new()) };
}
pub fn observer() -> bool { OBSERVER.with(Cell::get) }
pub(crate) fn set_observer(v: bool) { OBSERVER.with(|x| x.set(v)); }
pub(crate) fn take_remote() -> Option<Launch> { REMOTE.with(|x| x.borrow_mut().take()) }
pub(crate) fn set_remote(v: Launch) { REMOTE.with(|x| *x.borrow_mut() = Some(v)); }
pub(crate) fn emit(v: Packet) { OUT.with(|x| x.borrow_mut().push(v)); }
pub fn outgoing() -> Vec<Packet> { OUT.with(|x| std::mem::take(&mut *x.borrow_mut())) }
/// Remember the strike just started locally, so later ticks can heartbeat it.
pub(crate) fn set_own(v: Launch) { OWN.with(|x| *x.borrow_mut() = Some(v)); }
/// Stop heartbeating: the local strike was stopped or ran out.
pub(crate) fn clear_own() { OWN.with(|x| x.borrow_mut().take()); }
/// Called every so often (not every tick: that would be one packet a tick for no
/// gain) while a locally-fired strike runs. A no-op for observers, who never set `OWN`.
pub(crate) fn heartbeat(elapsed: f32) {
    OWN.with(|x| {
        if let Some(launch) = x.borrow_mut().as_mut() {
            launch.elapsed = elapsed;
            emit(Packet::Sync(launch.clone()));
        }
    });
}
/// Decode one message off the wire. However the host delivers `orbital:smp1`
/// bytes (a native-mod network hook today; a future `Mod` capability for a
/// plain wasm build), call this with the payload: it only decodes and queues,
/// since this has no way to reach a live `&mut Orbital` itself; the result is
/// picked up and acted on from `Orbital::tick`, which drains `incoming()`.
pub fn receive(data: &[u8]) {
    if let Some(packet) = decode(data) {
        IN.with(|x| x.borrow_mut().push(packet));
    }
}
pub(crate) fn incoming() -> Vec<Packet> { IN.with(|x| std::mem::take(&mut *x.borrow_mut())) }

#[cfg(test)]
mod tests {
    use super::*;
    fn launch() -> Launch {
        Launch { laser: 0, block: [0,64,0], point: [0.5,65.0,0.5], origin: [20.0,80.0,20.0],
            seed: 7, approach: 0, arrival: 0, colour: 0, option: 0, elapsed: 0.0,
            dimension: "minecraft:overworld".into() }
    }
    #[test] fn round_trip_and_invalid_inputs() {
        let s=launch();
        let raw=serde_json::to_vec(&Packet::Start(s.clone())).unwrap();
        assert!(matches!(decode(&raw),Some(Packet::Start(_))));
        assert!(decode(&vec![0;4097]).is_none());
        assert!(decode(b"garbage").is_none());
        let mut bad=s.clone(); bad.laser=usize::MAX; assert!(!bad.valid());
        let mut bad=s.clone(); bad.point[0]=f64::NAN; assert!(!bad.valid());
        let mut bad=s; bad.elapsed=bad.duration()+1.0; assert!(!bad.valid());
    }
    #[test] fn queues_are_drained_once() {
        outgoing(); emit(Packet::Hello); assert_eq!(outgoing().len(),1); assert!(outgoing().is_empty());
    }
    #[test] fn heartbeat_is_a_noop_without_an_own_strike() {
        outgoing();
        heartbeat(5.0);
        assert!(outgoing().is_empty());
    }
    #[test] fn heartbeat_updates_elapsed_on_the_own_launch() {
        outgoing();
        set_own(launch());
        heartbeat(3.5);
        match outgoing().as_slice() {
            [Packet::Sync(s)] => assert_eq!(s.elapsed, 3.5),
            other => panic!("expected one Sync packet, got {other:?}"),
        }
        clear_own();
        outgoing();
        heartbeat(9.0);
        assert!(outgoing().is_empty());
    }
    #[test] fn receive_queues_valid_packets_for_tick_to_drain() {
        incoming();
        receive(&serde_json::to_vec(&Packet::Start(launch())).unwrap());
        receive(b"garbage");
        receive(&serde_json::to_vec(&Packet::Stop).unwrap());
        let drained = incoming();
        assert_eq!(drained.len(), 2);
        assert!(matches!(drained[0], Packet::Start(_)));
        assert!(matches!(drained[1], Packet::Stop));
        assert!(incoming().is_empty());
    }
}
