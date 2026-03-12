# ShaderSelector V4

An easy framework for sending information to post processing shaders using commands in Minecraft.

## What is this used for?

This resource pack includes a framework that lets commands communicate with post processing shaders, along with a simple example demonstrating how to use it.

Here is a video showcasing the demonstration features:

https://github.com/user-attachments/assets/f54763f8-35a4-4a24-a893-06ca752d109a

If you want to try it out yourself, install the resource pack and run one of these commands:

```mcfunction
# Turn on greyscale
/particle entity_effect{color:-67174913} ~ ~1 ~

# Turn off greyscale
/particle entity_effect{color:-67175168} ~ ~1 ~

# Rotate screen by 90° (instant)
/particle entity_effect{color:-67175616} ~ ~1 ~

# Rotate screen back to normal (instant)
/particle entity_effect{color:-67175680} ~ ~1 ~

# Rotate screen to 180° (smooth with acceleration)
/particle entity_effect{color:-67175296} ~ ~1 ~

# Rotate screen back to normal (smooth)
/particle entity_effect{color:-67175424} ~ ~1 ~
```

The good thing about everything being controlled through particles is that the `/particle` command has an argument that lets you determine which players are able to see a particle.

> For a detailed guide (in Russian) on how everything works and how to write your own effects, see [GUIDE.md](GUIDE.md).

## How does this work?

At its core, this framework is structured around a persistent data buffer defined in the `transparency` post effect pipeline. This buffer saves inputs given through commands and processes them to produce interpolated output values. The number of channels and how they are used can be changed, but in the given example the data buffer looks like this:

```
Column:      0              1              2              3              4
          ┌──────────┬──────────────┬──────────────┬──────────────┬──────────────┐
Row 0:    │ GameTime │              │              │              │              │
          ├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
Row 1:    │ Input    │ Start time   │ Acceleration │ Speed        │ Value        │  (channel 1: greyscale)
          ├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
Row 2:    │ Input    │ Start time   │ Acceleration │ Speed        │ Value        │  (channel 2: rotation)
          └──────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

Each row is responsible for one "channel" which controls one effect. Within a row:

* **Column 0 (input)** — saves the last received input: whether there has been an input (red), the operation (green), and the target value (blue).
* **Column 1 (startTime)** — captures the GameTime (in seconds) from when the target value last changed on this channel.
* **Columns 2 and 3 (acceleration and speed)** — used internally to manage smooth interpolation of the output value.
* **Column 4 (output)** — the interpolated value that moves toward the target. How it moves depends on the operation.

Columns 1–4 each store a single 32-bit float with bits split across the RGBA components. Use `decodeColor(vec4 color)` from `shader_selector:utils.glsl` to read them, or the convenience function `readChannel(int channel)` from `shader_selector:data_reader.glsl`:

```glsl
float greyscale = readChannel(EXAMPLE_GREYSCALE_CHANNEL); // 0.0 – 1.0
float rotation = readChannel(EXAMPLE_ROTATION_CHANNEL);   // 0.0 – 1.0
```

### How is a new channel defined?

All a channel needs is space on the data buffer. The buffer size is set in the `targets` list of `assets/minecraft/post_effect/transparency.json`. In the example there are 2 channels plus the internal GameTime row, so `"height": 3` for both `data` and `data_swap` targets.

To add a channel:

1. In `marker_settings.glsl`, define a channel constant and add markers to `LIST_MARKERS`.
2. In `transparency.json`, increase `height` of `data` and `data_swap`.
3. In your shader, read the value with `readChannel(MY_CHANNEL)`.

### How do I give an input to a channel?

A "marker particle" is a particle whose color is recognized by the core shader, which then sends it to the post shader. Marker definitions live in `assets/shader_selector/shaders/include/marker_settings.glsl`.

A marker is defined by adding it to the `LIST_MARKERS` macro:

```glsl
ADD_MARKER(<channel>, <green>, <alpha>, <operation>, <rate>)
```

A particle with the color `(MARKER_RED, <green>, <any blue value>, <alpha>)` will be recognized as a marker targeting the specified channel. `MARKER_RED` (254) is constant across all markers.

The blue value of the particle becomes the "target value" written to the data buffer.

**The particle must use `entity_effect`** because it requires control over all 4 RGBA channels (including alpha). The color is specified as a packed ARGB integer:

```
ARGB = -67239936 + green * 256 + value
```

For example, to set greyscale (green=253) to 100% (value=255):
```
ARGB = -67239936 + 253 * 256 + 255 = -67174913
/particle entity_effect{color:-67174913} ~ ~1 ~
```

### Operations

The `<operation>` parameter controls how the channel's value follows the target:

| Op | Name | Behavior | Rate parameter |
|----|------|----------|----------------|
| 0 | Set | Instant. Speed reset to 0 | Not used (0.0) |
| 1 | Constant velocity | Linear motion toward target | Speed (units/second) |
| 2 | Cyclic constant velocity | Like 1, but wraps 0.0–1.0 via shortest path | Speed |
| 3 | Accelerated motion | Smooth acceleration/deceleration toward target | Acceleration (units/second²) |
| 4 | Cyclic accelerated | Like 3, but wraps 0.0–1.0 via shortest path | Acceleration |

**Overflow (cyclic operations):** Values wrap from 1.0 back to 0.0. To go from 0.9 to 0.1, the value adds 0.2 (wrapping through 1.0) rather than subtracting 0.8. Under overflow, the target is interpreted as `blue/256` instead of `blue/255`, so values like 0.5 (128/256) are represented exactly.

## Quick reference

### Example markers (from default config)

| Effect | green | op | rate | ARGB formula |
|--------|-------|----|------|--------------|
| Greyscale (smooth) | 253 | 1 | 0.1 | `-67175168 + value` |
| Rotation (instant) | 251 | 0 | 0.0 | `-67175680 + value` |
| Rotation (smooth cyclic) | 252 | 4 | 0.4 | `-67175424 + value` |

### Ready-to-use commands

| Action | Command |
|--------|---------|
| Greyscale ON | `particle entity_effect{color:-67174913} ~ ~1 ~` |
| Greyscale OFF | `particle entity_effect{color:-67175168} ~ ~1 ~` |
| Greyscale 50% | `particle entity_effect{color:-67175040} ~ ~1 ~` |
| Rotation SET 0° | `particle entity_effect{color:-67175680} ~ ~1 ~` |
| Rotation SET 90° | `particle entity_effect{color:-67175616} ~ ~1 ~` |
| Rotation SET 180° | `particle entity_effect{color:-67175552} ~ ~1 ~` |
| Rotation SMOOTH 180° | `particle entity_effect{color:-67175296} ~ ~1 ~` |
| Rotation SMOOTH 0° | `particle entity_effect{color:-67175424} ~ ~1 ~` |

## History

This framework is based on a [previous version](https://github.com/HalbFettKaese/ShaderSelectorV3). That version had been extracted into its own repository and popularized by [CloudWolfYT](https://github.com/CloudWolfYT) to create [ShaderSelectorV2](https://github.com/CloudWolfYT/ShaderSelectorV2). ShaderSelectorV3 was a complete rewrite, and V4 continues with these notable changes across versions:

* V2 used the post shader format from before Minecraft 1.21.2; V3 was developed in 24w38a (a 1.21.2 snapshot); V4 targets 26.1.
* The data sampler has a changed layout.
* Interpolation counts in real time instead of frames (`rate` is in `units/second` instead of `units/frame`).
* Every channel saves how much time passed since its target value was last changed.
* Apart from constant-rate interpolation, there is accelerated motion interpolation.
* Interpolation can use overflow (cyclic wrapping) for shortest-path transitions.
* Adding/editing a channel only requires changing `marker_settings.glsl` and adjusting the data buffer height in `transparency.json`.
* Added `readChannel()` convenience function via `data_reader.glsl`.
