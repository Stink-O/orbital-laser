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
    match &packet { Packet::Start(s) if !s.valid() => None, _ => Some(packet) }
}

thread_local! {
    static REMOTE: RefCell<Option<Launch>> = const { RefCell::new(None) };
    static OBSERVER: Cell<bool> = const { Cell::new(false) };
    static OUT: RefCell<Vec<Packet>> = const { RefCell::new(Vec::new()) };
}
pub fn observer() -> bool { OBSERVER.with(Cell::get) }
pub(crate) fn set_observer(v: bool) { OBSERVER.with(|x| x.set(v)); }
pub(crate) fn take_remote() -> Option<Launch> { REMOTE.with(|x| x.borrow_mut().take()) }
pub(crate) fn set_remote(v: Launch) { REMOTE.with(|x| *x.borrow_mut() = Some(v)); }
pub(crate) fn emit(v: Packet) { OUT.with(|x| x.borrow_mut().push(v)); }
pub fn outgoing() -> Vec<Packet> { OUT.with(|x| std::mem::take(&mut *x.borrow_mut())) }
pub fn receive(data: &[u8]) {
    match decode(data) {
        Some(Packet::Start(s)) => crate::__mod_with(|m| m.network_start(s)),
        Some(Packet::Stop | Packet::Denied) => crate::__mod_with(|m| {
            set_observer(true);
            m.stop_strike();
        }),
        _ => {}
    }
}

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
}
