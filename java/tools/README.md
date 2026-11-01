# Tools

These regenerate and check the screen shaders. You do **not** need them to build the mod: the generated shaders are checked in.

The original mod's shaders are written in WGSL for Horizon's renderer. Minecraft needs GLSL, so `build_shader.py` assembles
each one, adjusts it for Minecraft (see its header for each step), converts it with `wgsl2glsl` (which uses
[naga](https://github.com/gfx-rs/wgpu)), and writes `src/client/resources/assets/orbital/shaders/post/NAME.fsh`.

## Regenerate a shader

You need Python 3, [Rust](https://rustup.rs), and a checkout of the original mod:

```sh
git clone https://github.com/Stink-O/orbital-laser ../orbital-laser        # anywhere you like

cargo build --release --manifest-path tools/wgsl2glsl/Cargo.toml
python tools/build_shader.py strike  --orbital-laser ../orbital-laser
python tools/build_shader.py payload --orbital-laser ../orbital-laser
python tools/build_shader.py nuke    --orbital-laser ../orbital-laser
```

`strike` covers Plasma, Godly, Black Hole, Meteor Storm and Mothership. Do not edit the `.fsh` files by hand: change
`build_shader.py` and regenerate. `tools/work/` (scratch files) and `tools/wgsl2glsl/target/` are git-ignored.

## Check that Minecraft's compiler accepts a shader

`ShaderCheck.java` compiles shader files with shaderc, with the options Minecraft 26.3 uses (Vulkan target, automatic uniform
binding), and prints the compiler's errors, so a shader can be checked without starting the game. It needs LWJGL's core and
shaderc jars (version 3.4.3) and their native jars for your system, all of which Gradle downloads into its cache when you
build the mod (look under `~/.gradle/caches/modules-2/files-2.1/org.lwjgl`):

```sh
java --enable-native-access=ALL-UNNAMED -cp "<lwjgl jars separated by : (or ; on Windows)>" tools/ShaderCheck.java \
     src/client/resources/assets/orbital/shaders/post/strike.vsh src/client/resources/assets/orbital/shaders/post/strike.fsh
```

Minecraft's OpenGL 3.3 path adds its own limits (it rejects, for example, GLSL functions newer than 3.30), so a shader that
passes here can still need a fix; the game's `latest.log` has the driver's message.
