//! A mod's post-processing pass (capability `render`, docs/mods.md): the mod's WGSL fragment shader, after
//! `mod_post.wgsl`, drawn over the world's own target (its colour and depth) into a picture of its own, which a
//! shader pack's post-processing or the copy onto the screen then takes in place of the world's.
//!
//! A pass may also be drawn in two stages (docs/mods.md, "A half-size stage"): with an `fs_half` and an `fs_join`
//! besides `fs_main`, `fs_half` is drawn into one or two RGBA16F pictures of half the width and height, and `fs_join`
//! (which reads them at bindings 6 and 7, declared by the pass itself) over the world in place of `fs_main`. A build
//! without the stages, or a pass without them, draws `fs_main` alone: the declarations are only the pass's, so the
//! same source compiles and runs on either.
//!
//! The source is compiled when its version changes, on a thread of its own so that a frame never waits for the driver
//! (`prepare`: a strike's frame does wait, and on macOS every one, where `BUILDING` needs the build inside the frame);
//! what was built is kept, so going back to a pass costs nothing. One that does not validate is logged and skipped until
//! the mod gives a new one. One the driver fails to build (wgpu's internal and out-of-memory errors: on Metal, its shader
//! compiler service dropping the connection on a large pass) is logged and skipped too, and tried again a few
//! seconds and then half a minute later, since the next try may work; never a device fault that ends the game.
//! `HORIZON_DEBUG_MOD_POST_FAIL=N` makes the first N builds fail that way, to try this on any machine.
//!
//! The mod's data (`render.set-data`) is a read-only storage buffer, `mod_data`: one word, 0,
//! until it gives some, uploaded again only when its version changes.
//!
//! A mod with capability `atlas` (docs/mods.md, "Block textures in a post pass") is also given the block sprite
//! arrays the terrain samples, as they are (animated layers at their current frame, mip levels as the Mipmap Levels
//! option leaves them): the first at binding 8, the terrain's sampler at 9 and the other seven arrays at 10 to 16
//! (a 1-layer stand-in where the game has fewer). As with bindings 6 and 7 the pass declares them itself, so a pass
//! that doesn't sample them compiles and runs everywhere; one that does is refused (logged) by a game without them,
//! or for a mod without the capability.
use bytemuck::{Pod, Zeroable};
use std::collections::HashMap;
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// What a mod's pass is given before its own source.
pub const PRELUDE: &str = include_str!("mod_post.wgsl");

/// The `Frame` uniform of `mod_post.wgsl`.
#[repr(C)]
#[derive(Clone, Copy, Default, Pod, Zeroable)]
pub struct FrameUniform {
    pub view: [[f32; 4]; 4],
    pub projection: [[f32; 4]; 4],
    pub inverse_view: [[f32; 4]; 4],
    pub inverse_projection: [[f32; 4]; 4],
    pub camera_position: [f32; 4],
    pub resolution: [f32; 4],
    pub time: [f32; 4],
    pub sun: [f32; 4],
    pub sky_color: [f32; 4],
    pub fog_color: [f32; 4],
    pub view_params: [f32; 4],
    pub mod_params: [[f32; 4]; 4],
    /// What `camera_position` (f32) leaves out of where the camera is: its rounding, far from the world's origin.
    pub camera_rest: [f32; 4],
}

/// The atlas's bindings: the first sprite array, the sampler, then the other arrays.
pub const ATLAS_ARRAY: u32 = 8;
pub const ATLAS_SAMPLER: u32 = 9;
pub const ATLAS_MORE: std::ops::RangeInclusive<u32> = 10..=16;
/// The sprite arrays the atlas bindings hold (terrain.wgsl's `SPRITE_ARRAYS` bindings).
pub const ATLAS_ARRAYS: usize = 8;

/// The half-size stage's format (both its pictures).
const HALF_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba16Float;

struct Output {
    size: [u32; 2],
    view: wgpu::TextureView,
    /// The half-size stage's pictures, made the first time a pass with one runs at this size.
    half: Option<[wgpu::TextureView; 2]>,
}

/// A pass's pipelines: `fs_main` alone, or the half-size stage (`fs_half`, writing `extra` + 1 pictures) and the
/// join over the world (`fs_join`).
enum Pipelines {
    Whole(wgpu::RenderPipeline),
    Split {
        half: wgpu::RenderPipeline,
        join: wgpu::RenderPipeline,
        extra: bool,
    },
}

/// How long after each driver failure a pass is tried again; once these are used up it waits for a new source.
const RETRY_AFTER: [Duration; 2] = [Duration::from_secs(5), Duration::from_secs(30)];

/// Why a pass's pipelines could not be made.
#[derive(Clone, Debug, PartialEq, Eq)]
enum Failure {
    /// The source is at fault: it does not validate, or wgpu refuses its pipelines (a validation error, such as a
    /// binding the layout lacks). The same source fails the same way, so it waits for a new one.
    Invalid(String),
    /// The driver failed to make them (wgpu's internal and out-of-memory errors). On Metal the shader compiler
    /// service can drop its connection (XPC_ERROR_CONNECTION_INTERRUPTED) on a large pass, more so while it is busy
    /// with the game's own pipelines at startup; the next try may work.
    Driver(String),
}

impl Failure {
    /// The failure the error scopes caught, if any (a validation error first: it is the source's fault).
    fn caught(
        validation: Option<wgpu::Error>,
        internal: Option<wgpu::Error>,
        out_of_memory: Option<wgpu::Error>,
    ) -> Option<Self> {
        match (validation, internal.or(out_of_memory)) {
            (Some(e), _) => Some(Self::Invalid(e.to_string())),
            (None, Some(e)) => Some(Self::Driver(e.to_string())),
            (None, None) => None,
        }
    }
}

/// A source's version and what became of it (`P`: its pipelines; generic so the bookkeeping is tested without a
/// device).
struct Built<P> {
    version: u64,
    state: State<P>,
}

enum State<P> {
    Ready(P),
    /// Invalid: skipped until the mod gives another source.
    Refused,
    /// The driver failed `failures` times, the last at `at`: tried again `RETRY_AFTER[failures - 1]` after it.
    Failed {
        failures: u32,
        at: Instant,
    },
}

impl<P> Built<P> {
    /// Whether `version` is to be built now: it is new, or it failed in the driver and its next try is due.
    fn due(built: Option<&Self>, version: u64, now: Instant) -> bool {
        match built {
            Some(b) if b.version == version => match b.state {
                State::Failed { failures, at } => RETRY_AFTER
                    .get(failures as usize - 1)
                    .is_some_and(|&wait| now >= at + wait),
                State::Ready(_) | State::Refused => false,
            },
            _ => true,
        }
    }

    /// What became of `version` after a build that came to `result` at `now`, `built` what it was before.
    fn after(built: Option<Self>, version: u64, result: Result<P, Failure>, now: Instant) -> Self {
        let failures = Self::failures(built.as_ref(), version);
        let state = match result {
            Ok(p) => State::Ready(p),
            Err(Failure::Invalid(_)) => State::Refused,
            Err(Failure::Driver(_)) => State::Failed {
                failures: failures + 1,
                at: now,
            },
        };
        Self { version, state }
    }

    fn ready(&self) -> Option<&P> {
        match &self.state {
            State::Ready(p) => Some(p),
            _ => None,
        }
    }

    /// The driver failures before this build (0 for a first try).
    fn failures(built: Option<&Self>, version: u64) -> u32 {
        match built {
            Some(Self {
                version: v,
                state: State::Failed { failures, .. },
            }) if *v == version => *failures,
            _ => 0,
        }
    }
}

/// What `validate` found in a pass: whether it has a half-size stage, and if so whether `fs_half` writes a second
/// picture (location 1).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Stages {
    Whole,
    Split { extra: bool },
}

/// A build under way on its own thread.
struct Build {
    version: u64,
    done: mpsc::Receiver<Result<Pipelines, Failure>>,
}

/// A pass's bind group layouts: the whole pass's (and the half-size stage's), and the join's (the same, and the
/// half-size stage's two pictures at 6 and 7).
struct Layouts {
    layout: wgpu::BindGroupLayout,
    pipeline_layout: wgpu::PipelineLayout,
    join_layout: wgpu::BindGroupLayout,
    join_pipeline_layout: wgpu::PipelineLayout,
}

pub struct ModPost {
    format: wgpu::TextureFormat,
    /// Without the atlas, and with it (bindings 8 to 16).
    layouts: [Layouts; 2],
    /// The block sprite arrays and their sampler, for a pass with the atlas (`set_atlas`).
    atlas: Option<([wgpu::TextureView; ATLAS_ARRAYS], wgpu::Sampler)>,
    /// Whether the pass in `built` was built with the atlas.
    built_atlas: bool,
    linear: wgpu::Sampler,
    nearest: wgpu::Sampler,
    uniform: wgpu::Buffer,
    /// `mod_data`, and the version of the mod's data in it (0: none, the one word 0).
    data: wgpu::Buffer,
    data_version: u64,
    /// The source's version, and its pipelines or why it has none.
    built: Option<Built<Pipelines>>,
    /// The other passes built so far, by version, and the builds under way.
    kept: HashMap<u64, Pipelines>,
    builds: Vec<Build>,
    /// Builds still to fail as the driver would (`HORIZON_DEBUG_MOD_POST_FAIL`).
    fail_builds: u32,
    output: Option<Output>,
    started: std::time::Instant,
    frames: u32,
}

impl ModPost {
    pub fn new(device: &wgpu::Device, format: wgpu::TextureFormat) -> Self {
        let fragment = |binding, ty| wgpu::BindGroupLayoutEntry {
            binding,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty,
            count: None,
        };
        let texture = |binding, sample_type| {
            fragment(
                binding,
                wgpu::BindingType::Texture {
                    sample_type,
                    view_dimension: wgpu::TextureViewDimension::D2,
                    multisampled: false,
                },
            )
        };
        let entries = [
            texture(0, wgpu::TextureSampleType::Float { filterable: true }),
            // (the Depth32Float depth bound as an unfilterable float texture, as mod_post.wgsl declares it: OpenGL can't
            // build a pass that reads a texture_depth_2d)
            texture(1, wgpu::TextureSampleType::Float { filterable: false }),
            fragment(
                2,
                wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
            ),
            fragment(
                3,
                wgpu::BindingType::Sampler(wgpu::SamplerBindingType::NonFiltering),
            ),
            fragment(
                4,
                wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
            ),
            fragment(
                5,
                wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: true },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
            ),
            texture(6, wgpu::TextureSampleType::Float { filterable: true }),
            texture(7, wgpu::TextureSampleType::Float { filterable: true }),
        ];
        let array = |binding| {
            fragment(
                binding,
                wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D2Array,
                    multisampled: false,
                },
            )
        };
        let atlas: Vec<_> = std::iter::once(array(ATLAS_ARRAY))
            .chain([fragment(
                ATLAS_SAMPLER,
                wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
            )])
            .chain(ATLAS_MORE.map(array))
            .collect();
        let layouts = |label, entries: &[wgpu::BindGroupLayoutEntry]| {
            let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some(label),
                entries,
            });
            let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some(label),
                bind_group_layouts: &[Some(&layout)],
                ..Default::default()
            });
            (layout, pipeline_layout)
        };
        let both = |with_atlas: bool| {
            let extra = if with_atlas { &atlas[..] } else { &[] };
            let whole: Vec<_> = entries[..6].iter().chain(extra).copied().collect();
            let join: Vec<_> = entries.iter().chain(extra).copied().collect();
            let (layout, pipeline_layout) = layouts("Horizon mod post", &whole);
            let (join_layout, join_pipeline_layout) = layouts("Horizon mod post join", &join);
            Layouts {
                layout,
                pipeline_layout,
                join_layout,
                join_pipeline_layout,
            }
        };
        let sampler = |label, filter| {
            device.create_sampler(&wgpu::SamplerDescriptor {
                label: Some(label),
                mag_filter: filter,
                min_filter: filter,
                address_mode_u: wgpu::AddressMode::ClampToEdge,
                address_mode_v: wgpu::AddressMode::ClampToEdge,
                ..Default::default()
            })
        };
        let uniform = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Horizon mod post frame"),
            size: std::mem::size_of::<FrameUniform>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        Self {
            format,
            layouts: [both(false), both(true)],
            atlas: None,
            built_atlas: false,
            linear: sampler("Horizon mod post linear", wgpu::FilterMode::Linear),
            nearest: sampler("Horizon mod post nearest", wgpu::FilterMode::Nearest),
            uniform,
            data: data_buffer(device, &[0]),
            data_version: 0,
            built: None,
            kept: HashMap::new(),
            builds: Vec::new(),
            fail_builds: std::env::var("HORIZON_DEBUG_MOD_POST_FAIL")
                .ok()
                .and_then(|n| n.trim().parse().ok())
                .unwrap_or(0),
            output: None,
            started: std::time::Instant::now(),
            frames: 0,
        }
    }

    /// The mod's data for `mod_data` (none: the one word 0), uploaded when its version is new: written into the
    /// buffer when it is the same size, else in a new buffer of its size (the bind group is made each frame).
    pub fn set_data(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        data: Option<(&[u32], u64)>,
    ) {
        let (words, version) = match data {
            Some((words, version)) if !words.is_empty() => (words, version),
            _ => (&[0u32][..], 0),
        };
        if version == self.data_version {
            return;
        }
        let bytes: &[u8] = bytemuck::cast_slice(words);
        if self.data.size() == bytes.len() as u64 {
            queue.write_buffer(&self.data, 0, bytes);
        } else {
            self.data = data_buffer(device, words);
        }
        self.data_version = version;
    }

    /// The block sprite arrays (each a `D2Array` view; the game's first, then the others or a 1-layer stand-in) and
    /// the sampler the terrain samples them with, for a pass with the atlas. Given again when the views change (the
    /// Mipmap Levels option).
    pub fn set_atlas(&mut self, arrays: &[wgpu::TextureView], sampler: &wgpu::Sampler) {
        let Some(first) = arrays.first() else {
            return;
        };
        let views = std::array::from_fn(|i| arrays.get(i).unwrap_or(first).clone());
        self.atlas = Some((views, sampler.clone()));
    }

    /// Compile `source` (without the prelude) if `version` is new, or if it failed in the driver and its next try
    /// is due; with the atlas's bindings when `atlas` (the mod has capability `atlas`). True when the pass can run;
    /// while it cannot, the frame is drawn without it.
    /// Whether the pass `version` can run this frame. Not yet built, it is built on a thread of its own and the frame
    /// goes on without it, unless `wait` (or on macOS, where a compiler crash has to fall inside the frame).
    pub fn prepare(
        &mut self,
        device: &wgpu::Device,
        version: u64,
        source: &str,
        atlas: bool,
        wait: bool,
    ) -> bool {
        self.prepare_at(device, version, source, atlas, wait || cfg!(target_os = "macos"), Instant::now())
    }

    fn prepare_at(
        &mut self,
        device: &wgpu::Device,
        version: u64,
        source: &str,
        atlas: bool,
        wait: bool,
        now: Instant,
    ) -> bool {
        if atlas && self.atlas.is_none() {
            return false;
        }
        // (the same source with the atlas or without is another pass: other layouts)
        if atlas != self.built_atlas {
            self.built = None;
            self.kept.clear();
            self.builds.clear();
            self.built_atlas = atlas;
        }
        self.finish_builds(version, wait, now);
        if Built::due(self.built.as_ref().filter(|b| b.version == version), version, now)
            && !self.kept.contains_key(&version)
            && !self.builds.iter().any(|b| b.version == version)
        {
            self.start_build(device, version, source, atlas);
            self.finish_builds(version, wait, now);
        }
        if let Some(pipelines) = self.kept.remove(&version) {
            self.keep_built();
            self.built = Some(Built {
                version,
                state: State::Ready(pipelines),
            });
        }
        self.built
            .as_ref()
            .is_some_and(|b| b.version == version && b.ready().is_some())
    }

    /// The pass in `built`, if it is ready, into `kept`.
    fn keep_built(&mut self) {
        if self.built.as_ref().is_some_and(|b| b.ready().is_some())
            && let Some(Built {
                version,
                state: State::Ready(pipelines),
            }) = self.built.take()
        {
            self.kept.insert(version, pipelines);
        }
    }

    /// Takes in the builds that have finished, waiting for `version`'s if `wait`. A failure counts only for the pass
    /// asked for now: another's is tried again when it is asked for.
    fn finish_builds(&mut self, version: u64, wait: bool, now: Instant) {
        let mut i = 0;
        while i < self.builds.len() {
            let b = &self.builds[i];
            let result = if wait && b.version == version {
                b.done.recv().map_err(|_| mpsc::TryRecvError::Disconnected)
            } else {
                b.done.try_recv()
            };
            let result = match result {
                Err(mpsc::TryRecvError::Empty) => {
                    i += 1;
                    continue;
                }
                Err(mpsc::TryRecvError::Disconnected) => {
                    Err(Failure::Driver("its build stopped".into()))
                }
                Ok(result) => result,
            };
            let done = self.builds.swap_remove(i).version;
            let before = Built::failures(self.built.as_ref(), done);
            match &result {
                Ok(_) if before > 0 => {
                    log::info!("Horizon: a mod's post pass compiled on try {}", before + 1);
                }
                Ok(_) => {}
                Err(Failure::Invalid(e)) => log::warn!(
                    "Horizon: a mod's post pass did not compile: {e}\n\
                     The pass is skipped until the mod gives another."
                ),
                Err(Failure::Driver(e)) => {
                    let tries = before + 1;
                    match RETRY_AFTER.get(before as usize) {
                        Some(wait) => log::warn!(
                            "Horizon: a mod's post pass did not compile/link in the driver (try {tries}): {e}\n\
                             The pass is skipped, and tried again in {} s.",
                            wait.as_secs()
                        ),
                        None => log::warn!(
                            "Horizon: a mod's post pass did not compile/link in the driver (try {tries}): {e}\n\
                             The pass is skipped until the mod gives another."
                        ),
                    }
                }
            }
            match result {
                Ok(pipelines) => {
                    self.kept.insert(done, pipelines);
                }
                Err(failure) if done == version => {
                    self.keep_built();
                    self.built = Some(Built::after(self.built.take(), done, Err(failure), now));
                }
                Err(_) => {}
            }
        }
    }

    /// Starts `version`'s build on a thread of its own.
    fn start_build(&mut self, device: &wgpu::Device, version: u64, source: &str, atlas: bool) {
        let fail = self.fail_builds > 0;
        self.fail_builds = self.fail_builds.saturating_sub(1);
        let layouts = &self.layouts[usize::from(atlas)];
        let (whole, join) = (layouts.pipeline_layout.clone(), layouts.join_pipeline_layout.clone());
        let (device, format, full) = (device.clone(), self.format, format!("{PRELUDE}\n{source}"));
        let (send, done) = mpsc::channel();
        // (naga walks a big pass deeply: the render thread's stack is no guide)
        let thread = std::thread::Builder::new()
            .name("mod post pass".into())
            .stack_size(64 << 20)
            .spawn(move || {
                let result = validate(&full)
                    .map_err(Failure::Invalid)
                    .and_then(|stages| Self::pipelines(&device, &whole, &join, format, &full, stages, fail));
                let _ = send.send(result);
            });
        match thread {
            Ok(_) => self.builds.push(Build { version, done }),
            Err(e) => log::warn!("Horizon: a mod's post pass was not built: {e}"),
        }
    }

    /// The pass's pipelines, made under error scopes for every kind of error: a pass whose bindings do not match the
    /// layout, or one the driver fails to compile, is an error to log, not a device fault (with no scope wgpu's
    /// default handler panics, which ends the game).
    fn pipelines(
        device: &wgpu::Device,
        whole: &wgpu::PipelineLayout,
        join: &wgpu::PipelineLayout,
        format: wgpu::TextureFormat,
        source: &str,
        stages: Stages,
        fail: bool,
    ) -> Result<Pipelines, Failure> {
        // popped in the reverse order
        let out_of_memory = device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
        let internal = device.push_error_scope(wgpu::ErrorFilter::Internal);
        let validation = device.push_error_scope(wgpu::ErrorFilter::Validation);
        let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Horizon mod post"),
            source: wgpu::ShaderSource::Wgsl(source.into()),
        });
        let target = |format| {
            Some(wgpu::ColorTargetState {
                format,
                blend: None,
                write_mask: wgpu::ColorWrites::ALL,
            })
        };
        let pipeline = |layout, entry, targets: &[Option<wgpu::ColorTargetState>]| {
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("Horizon mod post"),
                layout: Some(layout),
                vertex: wgpu::VertexState {
                    module: &module,
                    entry_point: Some("horizon_mod_post_vertex"),
                    compilation_options: Default::default(),
                    buffers: &[],
                },
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                fragment: Some(wgpu::FragmentState {
                    module: &module,
                    entry_point: Some(entry),
                    compilation_options: Default::default(),
                    targets,
                }),
                multiview_mask: None,
                cache: None,
            })
        };
        let pipelines = match stages {
            Stages::Whole => Pipelines::Whole(pipeline(
                whole,
                "fs_main",
                &[target(format)],
            )),
            Stages::Split { extra } => Pipelines::Split {
                half: pipeline(
                    whole,
                    "fs_half",
                    &[target(HALF_FORMAT), target(HALF_FORMAT).filter(|_| extra)],
                ),
                join: pipeline(
                    join,
                    "fs_join",
                    &[target(format)],
                ),
                extra,
            },
        };
        let validation = pollster::block_on(validation.pop());
        let internal = pollster::block_on(internal.pop());
        let out_of_memory = pollster::block_on(out_of_memory.pop());
        if let Some(failure) = Failure::caught(validation, internal, out_of_memory) {
            return Err(failure);
        }
        if fail {
            return Err(Failure::Driver(
                "HORIZON_DEBUG_MOD_POST_FAIL: a driver failure, as on Metal: \
                 Compilation failed due to an interrupted connection: XPC_ERROR_CONNECTION_INTERRUPTED"
                    .into(),
            ));
        }
        Ok(pipelines)
    }

    /// Draw the pass over the world's `color` and `depth` (`size` pixels), and return its picture. Call after
    /// `prepare` said it can run.
    #[allow(clippy::too_many_arguments)]
    pub fn run(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        color: &wgpu::TextureView,
        depth: &wgpu::TextureView,
        size: [u32; 2],
        mut frame: FrameUniform,
    ) -> &wgpu::TextureView {
        if self.output.as_ref().is_none_or(|o| o.size != size) {
            let view = picture(device, "Horizon mod post picture", size, self.format);
            self.output = Some(Output {
                size,
                view,
                half: None,
            });
        }
        let split = matches!(
            self.built.as_ref().and_then(Built::ready),
            Some(Pipelines::Split { .. })
        );
        let output = self.output.as_mut().expect("made above");
        if split && output.half.is_none() {
            // (half the width and height, rounded up: each of its pixels stands for two by two of the world's)
            let half = [size[0].div_ceil(2), size[1].div_ceil(2)];
            output.half = Some([
                picture(device, "Horizon mod post half", half, HALF_FORMAT),
                picture(device, "Horizon mod post half extra", half, HALF_FORMAT),
            ]);
        }
        let output = self.output.as_ref().expect("made above");
        let (w, h) = (size[0] as f32, size[1] as f32);
        frame.resolution = [w, h, 1.0 / w, 1.0 / h];
        frame.time[0] = self.started.elapsed().as_secs_f32();
        frame.time[1] = self.frames as f32;
        self.frames = self.frames.wrapping_add(1);
        queue.write_buffer(&self.uniform, 0, bytemuck::bytes_of(&frame));
        let mut entries = vec![
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(color),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: wgpu::BindingResource::TextureView(depth),
            },
            wgpu::BindGroupEntry {
                binding: 2,
                resource: wgpu::BindingResource::Sampler(&self.linear),
            },
            wgpu::BindGroupEntry {
                binding: 3,
                resource: wgpu::BindingResource::Sampler(&self.nearest),
            },
            wgpu::BindGroupEntry {
                binding: 4,
                resource: self.uniform.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 5,
                resource: self.data.as_entire_binding(),
            },
        ];
        let layouts = &self.layouts[usize::from(self.built_atlas)];
        if self.built_atlas
            && let Some((arrays, sampler)) = &self.atlas
        {
            let bindings = std::iter::once(ATLAS_ARRAY).chain(ATLAS_MORE);
            entries.extend(
                bindings
                    .zip(arrays)
                    .map(|(binding, view)| wgpu::BindGroupEntry {
                        binding,
                        resource: wgpu::BindingResource::TextureView(view),
                    }),
            );
            entries.push(wgpu::BindGroupEntry {
                binding: ATLAS_SAMPLER,
                resource: wgpu::BindingResource::Sampler(sampler),
            });
        }
        let group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Horizon mod post"),
            layout: &layouts.layout,
            entries: &entries,
        });
        let draw = |encoder: &mut wgpu::CommandEncoder,
                    targets: &[Option<&wgpu::TextureView>],
                    pipeline: &wgpu::RenderPipeline,
                    group: &wgpu::BindGroup| {
            let attachments: Vec<_> = targets
                .iter()
                .map(|t| {
                    t.map(|view| wgpu::RenderPassColorAttachment {
                        view,
                        depth_slice: None,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                            store: wgpu::StoreOp::Store,
                        },
                    })
                })
                .collect();
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Horizon mod post"),
                color_attachments: &attachments,
                ..Default::default()
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, group, &[]);
            pass.draw(0..3, 0..1);
        };
        match self.built.as_ref().and_then(Built::ready) {
            Some(Pipelines::Whole(pipeline)) => {
                draw(encoder, &[Some(&output.view)], pipeline, &group);
            }
            Some(Pipelines::Split { half, join, extra }) => {
                let [first, second] = output.half.as_ref().expect("made above");
                draw(
                    encoder,
                    &[Some(first), extra.then_some(second)],
                    half,
                    &group,
                );
                entries.extend([
                    wgpu::BindGroupEntry {
                        binding: 6,
                        resource: wgpu::BindingResource::TextureView(first),
                    },
                    wgpu::BindGroupEntry {
                        binding: 7,
                        resource: wgpu::BindingResource::TextureView(second),
                    },
                ]);
                let join_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
                    label: Some("Horizon mod post join"),
                    layout: &layouts.join_layout,
                    entries: &entries,
                });
                draw(encoder, &[Some(&output.view)], join, &join_group);
            }
            _ => {}
        }
        &output.view
    }
}

/// A picture a pass draws into and a later one reads.
fn picture(
    device: &wgpu::Device,
    label: &str,
    size: [u32; 2],
    format: wgpu::TextureFormat,
) -> wgpu::TextureView {
    device
        .create_texture(&wgpu::TextureDescriptor {
            label: Some(label),
            size: wgpu::Extent3d {
                width: size[0],
                height: size[1],
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT
                | wgpu::TextureUsages::TEXTURE_BINDING
                // (the tests read the pictures back)
                | if cfg!(test) {
                    wgpu::TextureUsages::COPY_SRC
                } else {
                    wgpu::TextureUsages::empty()
                },
            view_formats: &[],
        })
        .create_view(&Default::default())
}

/// A storage buffer holding `words` (at least one).
fn data_buffer(device: &wgpu::Device, words: &[u32]) -> wgpu::Buffer {
    use wgpu::util::DeviceExt;
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("Horizon mod post data"),
        contents: bytemuck::cast_slice(words),
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
    })
}

/// Parse and validate a whole pass (prelude included) before wgpu sees it, so a broken one is an error, not a
/// device fault; and find whether it has a half-size stage.
fn validate(source: &str) -> Result<Stages, String> {
    let module = naga::front::wgsl::parse_str(source).map_err(|e| e.emit_to_string(source))?;
    let info = naga::valid::Validator::new(
        naga::valid::ValidationFlags::all(),
        naga::valid::Capabilities::all(),
    )
    .validate(&module)
    .map_err(|e| e.emit_to_string(source))?;
    let entry = |name: &str| {
        module
            .entry_points
            .iter()
            .position(|e| e.name == name && e.stage == naga::ShaderStage::Fragment)
    };
    if entry("fs_main").is_none() {
        return Err("no `@fragment fn fs_main`".into());
    }
    let half = match (entry("fs_half"), entry("fs_join")) {
        (None, None) => return Ok(Stages::Whole),
        (Some(half), Some(_)) => half,
        _ => {
            return Err(
                "a half-size stage needs both `@fragment fn fs_half` and `fn fs_join`".into(),
            );
        }
    };
    // the half-size stage writes its pictures at locations 0 and (if it likes) 1, and cannot read them
    let locations = match &module.entry_points[half].function.result {
        Some(naga::FunctionResult {
            binding: Some(naga::Binding::Location { location, .. }),
            ..
        }) => vec![*location],
        Some(naga::FunctionResult { ty, binding: None }) => match &module.types[*ty].inner {
            naga::TypeInner::Struct { members, .. } => members
                .iter()
                .filter_map(|m| match m.binding {
                    Some(naga::Binding::Location { location, .. }) => Some(location),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        },
        _ => Vec::new(),
    };
    if !locations.contains(&0) || locations.iter().any(|&l| l > 1) {
        return Err("`fs_half` writes location 0 and at most location 1".into());
    }
    let uses = info.get_entry_point(half);
    for (handle, var) in module.global_variables.iter() {
        if !uses[handle].is_empty()
            && var
                .binding
                .as_ref()
                .is_some_and(|b| b.group == 0 && (b.binding == 6 || b.binding == 7))
        {
            return Err("`fs_half` reads the pictures it draws (bindings 6 and 7)".into());
        }
    }
    Ok(Stages::Split {
        extra: locations.contains(&1),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pass_reads_its_data() {
        // the prelude declares mod_data; a pass may read it (guarded by its length), or leave it alone
        let reads = "@fragment fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    \
            let n = arrayLength(&mod_data);\n    \
            let v = select(0.0, bitcast<f32>(mod_data[0]), n > 0u);\n    \
            return vec4<f32>(v, frame.mod_params[0].x, 0.0, 1.0);\n}\n";
        assert_eq!(validate(&format!("{PRELUDE}\n{reads}")), Ok(Stages::Whole));
        let ignores = "@fragment fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);\n}\n";
        validate(&format!("{PRELUDE}\n{ignores}")).unwrap();
        assert!(PRELUDE.contains("@group(0) @binding(5) var<storage, read> mod_data: array<u32>;"));
    }

    /// A pass with a half-size stage: `fs_main` for builds without it, `fs_half` into the half-size pictures,
    /// `fs_join` reading them (declared by the pass, so the same source compiles on a build whose prelude lacks them).
    const SPLIT: &str = "@group(0) @binding(6) var half_picture: texture_2d<f32>;\n\
        @group(0) @binding(7) var half_extra: texture_2d<f32>;\n\
        @fragment fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);\n}\n";

    #[test]
    fn a_pass_may_have_a_half_size_stage() {
        let one = "@fragment fn fs_half(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return vec4<f32>(in.uv, 0.0, 1.0);\n}\n\
            @fragment fn fs_join(in: StageIn) -> @location(0) vec4<f32> {\n    \
            let s = textureSampleLevel(half_picture, linear_sampler, in.uv, 0.0);\n    \
            return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0) * s.a + s;\n}\n";
        assert_eq!(
            validate(&format!("{PRELUDE}\n{SPLIT}{one}")),
            Ok(Stages::Split { extra: false })
        );
        let two = "struct Half {\n    @location(0) c: vec4<f32>,\n    @location(1) e: vec4<f32>,\n}\n\
            @fragment fn fs_half(in: StageIn) -> Half {\n    \
            return Half(vec4<f32>(0.0), vec4<f32>(depth_at(in.uv)));\n}\n\
            @fragment fn fs_join(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureLoad(half_extra, vec2<i32>(in.position.xy * 0.5), 0);\n}\n";
        assert_eq!(
            validate(&format!("{PRELUDE}\n{SPLIT}{two}")),
            Ok(Stages::Split { extra: true })
        );
        // fs_half alone, or one reading its own picture, is refused
        let alone = "@fragment fn fs_half(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return vec4<f32>(0.0);\n}\n";
        assert!(validate(&format!("{PRELUDE}\n{SPLIT}{alone}")).is_err());
        let reads = one.replace(
            "vec4<f32>(in.uv, 0.0, 1.0)",
            "textureLoad(half_picture, vec2<i32>(0), 0)",
        );
        assert!(validate(&format!("{PRELUDE}\n{SPLIT}{reads}")).is_err());
        // the prelude leaves the declarations to the pass
        // (its comments show them)
        assert!(
            !PRELUDE
                .lines()
                .any(|l| !l.trim_start().starts_with("//") && l.contains("@binding(6)"))
        );
    }

    #[test]
    fn a_driver_failure_is_tried_again_twice_an_invalid_pass_never() {
        let t0 = Instant::now();
        let driver = || Err(Failure::Driver("XPC_ERROR_CONNECTION_INTERRUPTED".into()));
        // a new source is due; a driver failure is tried again 5 s later, then 30 s after that, then not
        assert!(Built::<()>::due(None, 1, t0));
        let b = Built::after(None, 1, driver(), t0);
        assert!(b.ready().is_none());
        assert!(!Built::due(Some(&b), 1, t0 + Duration::from_secs(4)));
        let t1 = t0 + RETRY_AFTER[0];
        assert!(Built::due(Some(&b), 1, t1));
        let b = Built::after(Some(b), 1, driver(), t1);
        assert_eq!(Built::failures(Some(&b), 1), 2);
        assert!(!Built::due(Some(&b), 1, t1 + RETRY_AFTER[0]));
        let t2 = t1 + RETRY_AFTER[1];
        assert!(Built::due(Some(&b), 1, t2));
        let b = Built::after(Some(b), 1, driver(), t2);
        assert!(!Built::due(Some(&b), 1, t2 + Duration::from_secs(3600)));
        // ... until the mod gives another source, which starts afresh
        assert!(Built::due(Some(&b), 2, t2));
        assert_eq!(Built::failures(Some(&b), 2), 0);
        let b = Built::after(Some(b), 2, driver(), t2);
        assert_eq!(Built::failures(Some(&b), 2), 1);
        // a retry that works is ready and stays built
        let b = Built::after(Some(b), 2, Ok(()), t2 + RETRY_AFTER[0]);
        assert!(b.ready().is_some());
        assert!(!Built::due(Some(&b), 2, t2 + Duration::from_secs(3600)));
        // an invalid source is not tried again
        let b = Built::<()>::after(Some(b), 3, Err(Failure::Invalid("no fs_main".into())), t2);
        assert!(b.ready().is_none());
        assert!(!Built::due(Some(&b), 3, t2 + Duration::from_secs(3600)));
    }

    #[test]
    fn every_kind_of_wgpu_error_is_caught() {
        let error = |kind: &str| {
            let source: wgpu::ErrorSource = Box::new(std::io::Error::other(kind.to_string()));
            let description = kind.to_string();
            match kind {
                "validation" => wgpu::Error::Validation {
                    source,
                    description,
                },
                "internal" => wgpu::Error::Internal {
                    source,
                    description,
                },
                _ => wgpu::Error::OutOfMemory { source },
            }
        };
        assert_eq!(Failure::caught(None, None, None), None);
        assert_eq!(
            Failure::caught(None, Some(error("internal")), None),
            Some(Failure::Driver("internal".into()))
        );
        assert!(matches!(
            Failure::caught(None, None, Some(error("oom"))),
            Some(Failure::Driver(_))
        ));
        assert_eq!(
            Failure::caught(Some(error("validation")), Some(error("internal")), None),
            Some(Failure::Invalid("validation".into()))
        );
    }

    fn device() -> Option<wgpu::Device> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle());
        let adapter = pollster::block_on(instance.request_adapter(&Default::default())).ok()?;
        eprintln!("mod post GPU test: {}", adapter.get_info().name);
        pollster::block_on(adapter.request_device(&Default::default()))
            .ok()
            .map(|(device, _)| device)
    }

    /// With a real device: a pass wgpu refuses (one passing naga, but reading a binding the whole pass's layout
    /// lacks) and one the driver fails to build are logged and skipped, not wgpu's default handler's panic; the
    /// driver failure is built again when its retry is due, and runs once it builds.
    #[test]
    fn a_pass_that_fails_to_build_does_not_end_the_game() {
        let Some(device) = device() else {
            eprintln!("no GPU adapter: skipped");
            return;
        };
        let mut post = ModPost::new(&device, wgpu::TextureFormat::Rgba8Unorm);
        post.fail_builds = 0;
        let plain = "@fragment fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);\n}\n";
        assert!(post.prepare(&device, 1, plain, false, true));
        // binding 6 is only in the join's layout
        let unbound = SPLIT.replace(
            "return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);",
            "return textureLoad(half_picture, vec2<i32>(0), 0);",
        );
        validate(&format!("{PRELUDE}\n{unbound}")).unwrap();
        assert!(!post.prepare(&device, 2, &unbound, false, true));
        assert!(matches!(post.built.as_ref().unwrap().state, State::Refused));
        assert!(!post.prepare_at(
            &device,
            2,
            &unbound,
            false,
            Instant::now() + Duration::from_secs(60)
        ));
        // the driver fails twice, then builds
        post.fail_builds = 2;
        let t0 = Instant::now();
        assert!(!post.prepare_at(&device, 3, plain, false, true, t0));
        assert_eq!(post.fail_builds, 1);
        assert!(!post.prepare_at(&device, 3, plain, false, true, t0 + Duration::from_secs(1)));
        assert_eq!(
            post.fail_builds, 1,
            "not tried again before its retry is due"
        );
        let t1 = t0 + RETRY_AFTER[0];
        assert!(!post.prepare_at(&device, 3, plain, false, true, t1));
        assert_eq!(post.fail_builds, 0);
        assert!(post.prepare_at(&device, 3, plain, false, true, t1 + RETRY_AFTER[1]));
    }

    /// A pass with the atlas declares bindings 8 to 16 itself (the prelude only shows them in its comments), so it
    /// parses on every build; fs_half may sample the atlas too (only 6 and 7 are the stage's own pictures).
    const ATLAS: &str = "@group(0) @binding(8) var block_sprites: texture_2d_array<f32>;\n\
        @group(0) @binding(9) var block_sampler: sampler;\n\
        @group(0) @binding(10) var block_sprites_1: texture_2d_array<f32>;\n\
        @fragment fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    \
            let a = textureSampleLevel(block_sprites, block_sampler, in.uv, u32(frame.mod_params[0].x), 0.0);\n    \
            let b = textureSampleLevel(block_sprites_1, block_sampler, in.uv, 0u, 0.0);\n    \
            return select(a, b, frame.mod_params[0].y > 0.5);\n}\n";

    #[test]
    fn a_pass_may_declare_the_atlas() {
        assert_eq!(validate(&format!("{PRELUDE}\n{ATLAS}")), Ok(Stages::Whole));
        let half = "@fragment fn fs_half(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureSampleLevel(block_sprites, block_sampler, in.uv, 0u, 0.0);\n}\n\
            @fragment fn fs_join(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureSampleLevel(half_picture, linear_sampler, in.uv, 0.0);\n}\n";
        let decls: String = ATLAS.lines().take(3).map(|l| format!("{l}\n")).collect();
        assert_eq!(
            validate(&format!("{PRELUDE}\n{SPLIT}{decls}{half}")),
            Ok(Stages::Split { extra: false })
        );
        // the prelude declares none of them, and shows them
        for binding in [ATLAS_ARRAY, ATLAS_SAMPLER, 10, 16] {
            let decl = format!("@binding({binding})");
            assert!(
                !PRELUDE
                    .lines()
                    .any(|l| !l.trim_start().starts_with("//") && l.contains(&decl))
            );
        }
        assert!(
            PRELUDE
                .contains("//     @group(0) @binding(8) var block_sprites: texture_2d_array<f32>;")
        );
    }

    fn device_queue() -> Option<(wgpu::Device, wgpu::Queue)> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor::new_without_display_handle());
        let adapter = pollster::block_on(instance.request_adapter(&Default::default())).ok()?;
        eprintln!("mod post GPU test: {}", adapter.get_info().name);
        pollster::block_on(adapter.request_device(&Default::default())).ok()
    }

    /// With a real device: a pass with the atlas samples the sprite arrays it is given (a layer of the first, the
    /// second array), at the pixel a UV names; without the capability the same pass is refused, not a device fault;
    /// and a pass that doesn't use the atlas runs with it as without.
    #[test]
    fn a_pass_with_the_atlas_samples_the_block_sprites() {
        let Some((device, queue)) = device_queue() else {
            eprintln!("no GPU adapter: skipped");
            return;
        };
        use wgpu::util::DeviceExt;
        let texture = |label, size: u32, layers: u32, format, usage, pixels: &[u8]| {
            device.create_texture_with_data(
                &queue,
                &wgpu::TextureDescriptor {
                    label: Some(label),
                    size: wgpu::Extent3d {
                        width: size,
                        height: size,
                        depth_or_array_layers: layers,
                    },
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: wgpu::TextureDimension::D2,
                    format,
                    usage,
                    view_formats: &[],
                },
                wgpu::util::TextureDataOrder::LayerMajor,
                pixels,
            )
        };
        let array = |t: &wgpu::Texture| {
            t.create_view(&wgpu::TextureViewDescriptor {
                dimension: Some(wgpu::TextureViewDimension::D2Array),
                ..Default::default()
            })
        };
        let rgba8 = wgpu::TextureFormat::Rgba8Unorm;
        let sampled = wgpu::TextureUsages::TEXTURE_BINDING;
        // two 2x2 sprites in the first array: red; green on the left and blue on the right
        let (r, g, b, y) = (
            [255, 0, 0, 255],
            [0, 255, 0, 255],
            [0, 0, 255, 255],
            [255, 255, 0, 255],
        );
        let first: Vec<u8> = [r, r, r, r, g, b, g, b].concat();
        let first = texture("sprites", 2, 2, rgba8, sampled, &first);
        let second = texture("sprites 1", 2, 1, rgba8, sampled, &[y; 4].concat());
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            address_mode_u: wgpu::AddressMode::Repeat,
            address_mode_v: wgpu::AddressMode::Repeat,
            ..Default::default()
        });
        let mut post = ModPost::new(&device, rgba8);
        post.fail_builds = 0;
        // no atlas given yet: a pass with it waits
        assert!(!post.prepare(&device, 1, ATLAS, true, true));
        post.set_atlas(&[array(&first), array(&second)], &sampler);
        // without the capability the pass's bindings are not in the layout: refused, logged
        assert!(!post.prepare(&device, 1, ATLAS, false, true));
        assert!(matches!(post.built.as_ref().unwrap().state, State::Refused));
        // with it, built (the same version: another layout is another pass)
        assert!(post.prepare(&device, 1, ATLAS, true, true));
        let size = 4;
        let world = texture(
            "world",
            size,
            1,
            rgba8,
            sampled,
            &[[9, 9, 9, 255]; 16].concat(),
        );
        let depth = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("depth"),
            size: wgpu::Extent3d {
                width: size,
                height: size,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Depth32Float,
            usage: sampled | wgpu::TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        });
        let (world, depth) = (
            world.create_view(&Default::default()),
            depth.create_view(&Default::default()),
        );
        let draw = |post: &mut ModPost, params: [f32; 4]| -> Vec<[u8; 4]> {
            let mut frame = FrameUniform::default();
            frame.mod_params[0] = params;
            let mut encoder = device.create_command_encoder(&Default::default());
            let out = post
                .run(
                    &device,
                    &queue,
                    &mut encoder,
                    &world,
                    &depth,
                    [size, size],
                    frame,
                )
                .texture()
                .clone();
            let read = device.create_buffer(&wgpu::BufferDescriptor {
                label: None,
                size: 256 * u64::from(size),
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });
            encoder.copy_texture_to_buffer(
                out.as_image_copy(),
                wgpu::TexelCopyBufferInfo {
                    buffer: &read,
                    layout: wgpu::TexelCopyBufferLayout {
                        offset: 0,
                        bytes_per_row: Some(256),
                        rows_per_image: None,
                    },
                },
                wgpu::Extent3d {
                    width: size,
                    height: size,
                    depth_or_array_layers: 1,
                },
            );
            queue.submit([encoder.finish()]);
            read.slice(..).map_async(wgpu::MapMode::Read, |_| {});
            device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
            let data = read.slice(..).get_mapped_range().unwrap();
            (0..size as usize * size as usize)
                .map(|i| {
                    let at = i / size as usize * 256 + i % size as usize * 4;
                    [data[at], data[at + 1], data[at + 2], data[at + 3]]
                })
                .collect()
        };
        // layer 0 of the first array, everywhere red
        assert!(draw(&mut post, [0.0; 4]).iter().all(|&p| p == r));
        // layer 1: its left half green, its right half blue (u 0 to 1 across the picture)
        let one = draw(&mut post, [1.0, 0.0, 0.0, 0.0]);
        assert_eq!([one[0], one[1], one[2], one[3]], [g, g, b, b]);
        assert_eq!([one[12], one[15]], [g, b]);
        // the second array
        assert!(
            draw(&mut post, [0.0, 1.0, 0.0, 0.0])
                .iter()
                .all(|&p| p == y)
        );
        // a pass that doesn't use the atlas runs with it as without
        let plain = "@fragment fn fs_main(in: StageIn) -> @location(0) vec4<f32> {\n    \
            return textureSampleLevel(scene_color, linear_sampler, in.uv, 0.0);\n}\n";
        assert!(post.prepare(&device, 2, plain, true, true));
        assert!(
            draw(&mut post, [0.0; 4])
                .iter()
                .all(|&p| p == [9, 9, 9, 255])
        );
        assert!(post.prepare(&device, 2, plain, false, true));
        assert!(
            draw(&mut post, [0.0; 4])
                .iter()
                .all(|&p| p == [9, 9, 9, 255])
        );
    }
}
