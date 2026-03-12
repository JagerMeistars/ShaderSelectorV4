# ShaderSelector V4 — Complete Guide

## What is this?

ShaderSelector is a resource pack framework for Minecraft that creates a bridge between datapacks and post-processing shaders. It lets you control visual effects (screen rotation, greyscale filter, and any others) directly from Minecraft commands, using colored particles as a data channel.

---

## Project Structure

```
shaderselector/
├── pack.mcmeta                                   # Pack metadata
└── assets/
    ├── minecraft/                                 # Vanilla file overrides
    │   ├── post_effect/
    │   │   └── transparency.json                  # Post-processing pipeline (pass order)
    │   └── shaders/core/
    │       ├── particle.vsh                       # Particle vertex shader (modified)
    │       └── particle.fsh                       # Particle fragment shader (modified)
    └── shader_selector/                           # Framework namespace
        └── shaders/
            ├── include/
            │   ├── marker_settings.glsl           # Marker definitions (channels, operations)
            │   ├── utils.glsl                     # Float <-> RGBA encoding/decoding
            │   └── data_reader.glsl               # Channel value reading utility
            └── post/
                ├── data.fsh                       # Core: marker processing and interpolation
                ├── shader.fsh                     # EXAMPLE: rotation and greyscale effects
                └── internal/
                    ├── blit.fsh                   # Simple texture copy
                    └── remove_particles.fsh       # Marker removal from particle render
```

---

## How It Works — Overview

### Concept

Minecraft provides no direct way to pass data from commands to shaders. ShaderSelector works around this by using **marker particles**: a command spawns an `entity_effect` particle with a special color (R=254, G=identifier, B=value, A=251), and the shader reads the particle's color to extract the data.

### Why `entity_effect`?

A marker is identified by all 4 color channels: R, G, B, and **A (alpha)**. All markers use `alpha=251`. Particles like `dust` don't allow setting alpha — it always starts at 1.0 (255). The `entity_effect` particle is the only standard type where all 4 RGBA components can be controlled.

### Data Flow

```
Datapack command
    │
    ▼
Spawn entity_effect particle with marker color (R=254, G=id, B=value, A=251)
    │
    ▼
particle.vsh: detects marker by color (R==254, G+A match),
              moves particle to a fixed screen position
    │
    ▼
particle.fsh: writes marker color (RGB + A=255) to particle buffer
    │
    ▼
data.fsh: reads marker from particle buffer, updates persistent data texture (5x3 pixels)
    │
    ▼
remove_particles.fsh: removes marker from display (player sees no artifacts)
    │
    ▼
shader.fsh (your effect): reads values from data texture via readChannel() and applies the effect
```

### Dual Marker Verification

The marker is checked in two places differently:

| Stage | File | What is checked | Purpose |
|-------|------|-----------------|---------|
| Vertex shader | `particle.vsh` | `iColor.r == 254` and `iColor.ga == ivec2(green, alpha)` | Identify marker among all particles, move to correct pixel |
| Data shader | `data.fsh` | `particleColor.rga == ivec3(254, green, 255)` | Read value from buffer (alpha=255 because particle.fsh forces A=255) |

---

## Key Files — Detailed Description

### 1. `marker_settings.glsl` — Marker Definitions

This is the main configuration file. Here you define **channels** (each channel = one controllable parameter) and **markers** (specific ways to affect a channel).

```glsl
// Define channels — each channel stores one float value (0.0 – 1.0)
#define EXAMPLE_GREYSCALE_CHANNEL 1
#define EXAMPLE_ROTATION_CHANNEL 2

// Define markers
// Format: ADD_MARKER(channel, green, alpha, op, rate)
#define LIST_MARKERS \
    ADD_MARKER(EXAMPLE_GREYSCALE_CHANNEL, 253, 251, 1, 0.1) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 251, 251, 0, 0.0) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 252, 251, 4, 0.4)
```

**ADD_MARKER Parameters:**

| Parameter | Description |
|-----------|-------------|
| `channel` | Channel number (row in data texture), starting from 1 |
| `green` | Green channel value of the marker (0–255). Unique identifier paired with `alpha` |
| `alpha` | Alpha channel value of the marker (0–255). Second identifier |
| `op` | Interpolation operation type (see section below) |
| `rate` | Speed (for op 1,2) or acceleration (for op 3,4) of interpolation |

> **Important:** A single channel can have multiple markers with different operations. For example, `EXAMPLE_ROTATION_CHANNEL` has two markers: one for instant set (op=0) and another for cyclic rotation with acceleration (op=4).

**`MARKER_RED` (254)** — the red channel value that identifies a particle as a marker rather than a regular particle.

### 2. Interpolation Operations (op)

When you send a value through a marker, it doesn't necessarily apply instantly. The system supports smooth interpolation:

| Op | Name | Behavior | Rate parameter |
|----|------|----------|----------------|
| **0** | Set | Instant value set. No animation | Not used (0.0) |
| **1** | Constant velocity | Linear motion toward target value at constant speed | Speed (units/tick) |
| **2** | Cyclic constant velocity | Like op=1, but value wraps in 0.0–1.0 range (shortest path) | Speed |
| **3** | Accelerated motion | Motion with acceleration (smooth ramp-up and slow-down) | Acceleration |
| **4** | Cyclic accelerated | Like op=3, but with 0.0–1.0 wrapping | Acceleration |

### 3. Data Texture (5x3 pixels)

All information is stored in a persistent texture of 5x3 pixels. Each pixel encodes a float via 4 RGBA bytes.

```
Column:      0              1              2              3              4
          ┌──────────┬──────────────┬──────────────┬──────────────┬──────────────┐
Row 0:    │ GameTime │              │              │              │              │  (time)
          ├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
Row 1:    │ Marker   │ Change time  │ Acceleration │ Speed        │ Value        │  (channel 1)
          ├──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
Row 2:    │ Marker   │ Change time  │ Acceleration │ Speed        │ Value        │  (channel 2)
          └──────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

- **Column 0:** Last seen marker (R=254, G=operation, B=target value)
- **Column 1:** Time of last marker change
- **Column 2:** Current acceleration
- **Column 3:** Current speed
- **Column 4:** Current interpolated value (what you read in your shader)

### 4. `utils.glsl` — Float Encoding

Shaders store float values in RGBA pixels (4 bytes = 32 bits):

```glsl
// Encodes a float into 4 RGBA bytes
vec4 encodeFloat(float value);

// Decodes RGBA back to float
float decodeColor(vec4 color);
```

### 5. `data_reader.glsl` — Reading Channels

A simple utility for reading the current channel value in your shader:

```glsl
// Returns the current interpolated channel value
float readChannel(int channel);
```

Usage:
```glsl
float greyscale = readChannel(EXAMPLE_GREYSCALE_CHANNEL); // 0.0 – 1.0
float rotation = readChannel(EXAMPLE_ROTATION_CHANNEL);   // 0.0 – 1.0
```

---

## Command Format for Sending Markers

### Marker Color

Each marker is a particle with a 4-component color:

| Color channel | Value | Description |
|---------------|-------|-------------|
| **R (red)** | Always **254** | Signature — "I am a marker" |
| **G (green)** | From `ADD_MARKER` | Marker identifier |
| **B (blue)** | 0–255 | Transmitted value |
| **A (alpha)** | From `ADD_MARKER` (251) | Second identifier |

### Particle Command

The `entity_effect` particle accepts color as a packed ARGB integer:

```
particle entity_effect{color:<ARGB_INT>} <x> <y> <z>
```

**ARGB Formula:**
```
ARGB = (A << 24) | (R << 16) | (G << 8) | B
```

For our markers (A=251, R=254):
```
ARGB = (251 << 24) | (254 << 16) | (green << 8) | value
     = -67175168 + (green - 253) * 256 + value     // for green ≈ 253
```

### Precomputed Base Values

For convenience — base ARGB values (without value, i.e. B=0):

| Marker | green | Base ARGB | Formula with value |
|--------|-------|-----------|--------------------|
| Greyscale | 253 | **-67175168** | `-67175168 + value` |
| Rotation (set) | 251 | **-67175680** | `-67175680 + value` |
| Rotation (cyclic) | 252 | **-67175424** | `-67175424 + value` |

> **How to use:** `-67175168 + value` — simply add the desired value (0–255) to the base number.

### Value Conversion

The blue channel (B) is an integer 0–255. The shader normalizes it:

| Operation | Shader formula | B=0 | B=128 | B=255 |
|-----------|----------------|-----|-------|-------|
| Op 0, 1, 3 (regular) | `B / 255.0` | 0.0 | 0.502 | 1.0 |
| Op 2, 4 (cyclic) | `B / 256.0` | 0.0 | 0.5 | 0.996 |

For rotation in degrees: `degrees = (B / 256.0) * 360.0`

| Degrees | B value | Formula |
|---------|---------|---------|
| 0° | 0 | `0 / 256 * 360` |
| 45° | 32 | `32 / 256 * 360` |
| 90° | 64 | `64 / 256 * 360` |
| 180° | 128 | `128 / 256 * 360` |
| 270° | 192 | `192 / 256 * 360` |

---

## Usage Examples

All examples below can be typed in chat, placed in command blocks, or used in datapack functions (`.mcfunction`).

> **Important:** The particle must be visible on the player's screen for at least 1 frame. Spawn it near the camera. The shader will detect the marker and remove it from rendering — the player won't see anything.

---

### Example 1: Greyscale Filter

Marker: `green=253`, `alpha=251`, `op=1` (constant velocity, rate=0.1).
Channel value smoothly moves toward target at speed 0.1/tick.

**Turn on (smoothly transition to full greyscale):**
```mcfunction
# B=255 -> target = 1.0 (100% greyscale)
# ARGB = -67175168 + 255 = -67174913
particle entity_effect{color:-67174913} ~ ~1 ~
```

**Turn off (smoothly restore color):**
```mcfunction
# B=0 -> target = 0.0 (0% greyscale, full color)
# ARGB = -67175168 + 0 = -67175168
particle entity_effect{color:-67175168} ~ ~1 ~
```

**Set to 50%:**
```mcfunction
# B=128 -> target ≈ 0.502
# ARGB = -67175168 + 128 = -67175040
particle entity_effect{color:-67175040} ~ ~1 ~
```

**Set to 25%:**
```mcfunction
# B=64 -> target ≈ 0.251
# ARGB = -67175168 + 64 = -67175104
particle entity_effect{color:-67175104} ~ ~1 ~
```

> **Behavior:** Since op=1 (constant velocity) with rate=0.1, the value doesn't jump instantly but smoothly crawls to the target. Transition speed is fixed — regardless of how far the current value is from the target.

---

### Example 2: Screen Rotation — Instant Set

Marker: `green=251`, `alpha=251`, `op=0` (set).
Value is set **instantly**, with no animation.

**Rotate 90°:**
```mcfunction
# B=64 -> 64/255 ≈ 0.251 -> 0.251 * 360 ≈ 90°
# ARGB = -67175680 + 64 = -67175616
particle entity_effect{color:-67175616} ~ ~1 ~
```

**Rotate 180°:**
```mcfunction
# B=128 -> 128/255 ≈ 0.502 -> ≈ 181°
# ARGB = -67175680 + 128 = -67175552
particle entity_effect{color:-67175552} ~ ~1 ~
```

**Rotate 45°:**
```mcfunction
# B=32 -> 32/255 ≈ 0.125 -> ≈ 45°
# ARGB = -67175680 + 32 = -67175648
particle entity_effect{color:-67175648} ~ ~1 ~
```

**Reset rotation (0°):**
```mcfunction
# B=0 -> 0°
# ARGB = -67175680
particle entity_effect{color:-67175680} ~ ~1 ~
```

> **Behavior:** Screen instantly rotates to the specified angle. No smoothing — snap and done.

---

### Example 3: Screen Rotation — Smooth Cyclic

Marker: `green=252`, `alpha=251`, `op=4` (cyclic accelerated, rate=0.4).
Value smoothly moves toward target with acceleration, wrapping through 0.0–1.0.

**Start rotation toward 180°:**
```mcfunction
# B=128 -> 128/256 = 0.5 -> 0.5 * 360 = 180°
# ARGB = -67175424 + 128 = -67175296
particle entity_effect{color:-67175296} ~ ~1 ~
```

**Start rotation toward 270°:**
```mcfunction
# B=192 -> 192/256 = 0.75 -> 270°
# ARGB = -67175424 + 192 = -67175232
particle entity_effect{color:-67175232} ~ ~1 ~
```

**Stop rotation (return to 0°):**
```mcfunction
# B=0 -> target = 0°
# ARGB = -67175424
particle entity_effect{color:-67175424} ~ ~1 ~
```

> **Behavior:** Screen smoothly accelerates and decelerates, arriving at the specified angle. Cyclic means when transitioning from 350° to 10°, it goes the shortest path (through 360°/0°) rather than backwards through 180°.

---

### Example 4: Combining Effects

Effects on different channels work **simultaneously and independently**. You can combine them:

**Enable greyscale + rotate 45°:**
```mcfunction
# Greyscale to maximum
particle entity_effect{color:-67174913} ~ ~1 ~
# Rotation to 45° instantly
particle entity_effect{color:-67175648} ~ ~1 ~
```

**Smooth greyscale + smooth rotation to 180°:**
```mcfunction
# Greyscale smoothly to 100%
particle entity_effect{color:-67174913} ~ ~1 ~
# Rotation smoothly to 180°
particle entity_effect{color:-67175296} ~ ~1 ~
```

**Turn off everything:**
```mcfunction
# Greyscale to 0
particle entity_effect{color:-67175168} ~ ~1 ~
# Rotation instantly to 0°
particle entity_effect{color:-67175680} ~ ~1 ~
```

---

### Example 5: Using in a Datapack

#### Datapack Structure

```
my_effects_datapack/
├── pack.mcmeta
└── data/
    └── my_effects/
        └── function/
            ├── greyscale_on.mcfunction
            ├── greyscale_off.mcfunction
            ├── spin_start.mcfunction
            ├── spin_stop.mcfunction
            └── reset_all.mcfunction
```

#### `pack.mcmeta`
```json
{
    "pack": {
        "pack_format": 75,
        "description": "Shader effects controller"
    }
}
```

#### `greyscale_on.mcfunction` — Smoothly enable greyscale
```mcfunction
# Enable greyscale filter (smooth transition)
# Spawn marker at player position (slightly ahead to ensure it's on screen)
execute as @a at @s run particle entity_effect{color:-67174913} ^ ^ ^2
```

#### `greyscale_off.mcfunction` — Smoothly disable greyscale
```mcfunction
# Disable greyscale filter (smooth transition back)
execute as @a at @s run particle entity_effect{color:-67175168} ^ ^ ^2
```

#### `spin_start.mcfunction` — Start rotation
```mcfunction
# Start smooth screen rotation toward 180°
execute as @a at @s run particle entity_effect{color:-67175296} ^ ^ ^2
```

#### `spin_stop.mcfunction` — Stop rotation
```mcfunction
# Stop rotation (smoothly return to 0°)
execute as @a at @s run particle entity_effect{color:-67175424} ^ ^ ^2
```

#### `reset_all.mcfunction` — Reset all effects
```mcfunction
# Greyscale -> 0 (smooth)
execute as @a at @s run particle entity_effect{color:-67175168} ^ ^ ^2
# Rotation -> 0° (instant)
execute as @a at @s run particle entity_effect{color:-67175680} ^ ^ ^2
```

#### Usage from chat
```
/function my_effects:greyscale_on
/function my_effects:greyscale_off
/function my_effects:spin_start
/function my_effects:spin_stop
/function my_effects:reset_all
```

---

### Example 6: Repeated Marker Sending (for continuous animation)

A marker only needs to be sent **once** — the value persists in the persistent texture between frames. However, if you want to **continuously change the value** (e.g., animate based on a timer), you can send markers every tick:

```mcfunction
# tick.mcfunction — called every tick
# Toggle greyscale based on time of day
execute store result score #time temp run time query daytime
execute if score #time temp matches 0..6000 as @a at @s run particle entity_effect{color:-67174913} ^ ^ ^2
execute if score #time temp matches 6001..12000 as @a at @s run particle entity_effect{color:-67175168} ^ ^ ^2
```

> **Note:** Sending the same marker with the same value repeatedly is harmless. The system checks whether the B value has changed, and if not — doesn't update the timestamp.

---

### Example 7: Computing ARGB for Any Marker

If you've added your own marker and want to compute the ARGB value:

```
ARGB (signed 32-bit) = ((251 - 256) * 16777216) + (254 * 65536) + (green * 256) + value
                      = -83886080 + 16646144 + green * 256 + value
                      = -67239936 + green * 256 + value
```

**Simplified formula:**
```
ARGB = -67239936 + green * 256 + value
```

**Examples:**
| green | value | ARGB |
|-------|-------|------|
| 253 | 0 | -67239936 + 64768 + 0 = **-67175168** |
| 253 | 255 | -67239936 + 64768 + 255 = **-67174913** |
| 251 | 0 | -67239936 + 64256 + 0 = **-67175680** |
| 252 | 128 | -67239936 + 64512 + 128 = **-67175296** |
| 250 | 100 | -67239936 + 64000 + 100 = **-67175836** |

---

## Reference Table: All Example Markers

| Effect | Action | green | op | Command (B=value) |
|--------|--------|-------|----|-------------------|
| Greyscale | Smooth to value | 253 | 1 | `entity_effect{color:}` where ARGB = `-67175168 + B` |
| Rotation | Instant set | 251 | 0 | `entity_effect{color:}` where ARGB = `-67175680 + B` |
| Rotation | Smooth with acceleration | 252 | 4 | `entity_effect{color:}` where ARGB = `-67175424 + B` |

**Commonly used ready-made values:**

| Action | ARGB | Command |
|--------|------|---------|
| Greyscale ON (100%) | -67174913 | `particle entity_effect{color:-67174913} ^ ^ ^2` |
| Greyscale OFF (0%) | -67175168 | `particle entity_effect{color:-67175168} ^ ^ ^2` |
| Greyscale 50% | -67175040 | `particle entity_effect{color:-67175040} ^ ^ ^2` |
| Rotation SET 0° | -67175680 | `particle entity_effect{color:-67175680} ^ ^ ^2` |
| Rotation SET 90° | -67175616 | `particle entity_effect{color:-67175616} ^ ^ ^2` |
| Rotation SET 180° | -67175552 | `particle entity_effect{color:-67175552} ^ ^ ^2` |
| Rotation SMOOTH 0° | -67175424 | `particle entity_effect{color:-67175424} ^ ^ ^2` |
| Rotation SMOOTH 90° | -67175360 | `particle entity_effect{color:-67175360} ^ ^ ^2` |
| Rotation SMOOTH 180° | -67175296 | `particle entity_effect{color:-67175296} ^ ^ ^2` |

---

## Writing Your Own Shader Effect

### Step 1: Define Channels

In `marker_settings.glsl`, add new channels and markers:

```glsl
// New channel
#define MY_BLUR_CHANNEL 3

// Add marker to LIST_MARKERS
#define LIST_MARKERS \
    ADD_MARKER(EXAMPLE_GREYSCALE_CHANNEL, 253, 251, 1, 0.1) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 251, 251, 0, 0.0) \
    ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 252, 251, 4, 0.4) \
    ADD_MARKER(MY_BLUR_CHANNEL, 250, 251, 1, 0.2)
```

> **Important:** When adding a new channel with number 3, you need to increase the data texture size. In `transparency.json`, change the height of `data` and `data_swap` from 3 to 4:
> ```json
> "data": {"width": 5, "height": 4, "persistent": true},
> "data_swap": {"width": 5, "height": 4}
> ```

### Step 2: Create the Shader

Create a file in `assets/shader_selector/shaders/post/`, e.g. `my_effect.fsh`:

```glsl
#version 330

uniform sampler2D MainSampler;   // Main image
uniform sampler2D DataSampler;   // Data texture with channel values

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

#moj_import <shader_selector:marker_settings.glsl>
#moj_import <shader_selector:utils.glsl>
#moj_import <shader_selector:data_reader.glsl>

in vec2 texCoord;
out vec4 fragColor;

void main() {
    // Read channel value (from 0.0 to 1.0)
    float blurAmount = readChannel(MY_BLUR_CHANNEL);

    // Apply effect
    vec4 color = texture(MainSampler, texCoord);

    // Example: simple offset blur
    vec2 offset = blurAmount * 5.0 / OutSize;
    vec4 blurred = (
        texture(MainSampler, texCoord + vec2(offset.x, 0.0)) +
        texture(MainSampler, texCoord - vec2(offset.x, 0.0)) +
        texture(MainSampler, texCoord + vec2(0.0, offset.y)) +
        texture(MainSampler, texCoord - vec2(0.0, offset.y))
    ) / 4.0;

    fragColor = mix(color, blurred, blurAmount);
}
```

### Step 3: Add a Pass to transparency.json

Add a new pass to the `passes` array (before the final blit):

```json
{
    "_comment": "My custom blur effect",
    "fragment_shader": "shader_selector:post/my_effect",
    "vertex_shader": "minecraft:core/screenquad",
    "inputs": [
        {
            "sampler_name": "Main",
            "target": "swap"
        },
        {
            "sampler_name": "Data",
            "target": "data"
        }
    ],
    "output": "final"
}
```

### Step 4: Command to Control the New Effect

```mcfunction
# Enable blur (green=250)
# ARGB = -67239936 + 250*256 + 255 = -67175681
execute as @a at @s run particle entity_effect{color:-67175681} ^ ^ ^2

# Disable blur
# ARGB = -67239936 + 250*256 + 0 = -67175936
execute as @a at @s run particle entity_effect{color:-67175936} ^ ^ ^2
```

> **Tip:** Pay attention to `target` in transparency.json — these are render target names. Your shader's input must be the output of the previous pass. Output should be one of the defined targets (`final`, `swap`, `swap2`). The last pass (blit) must write to `minecraft:main`.

---

## Example Breakdown: shader.fsh

The built-in example demonstrates two effects:

```glsl
void main() {
    // 1. SCREEN ROTATION
    float rotationAmount = readChannel(EXAMPLE_ROTATION_CHANNEL);  // 0.0–1.0
    float angle = radians(rotationAmount * 360.0);                 // 0–360 degrees

    // Apply rotation matrix to UV coordinates
    vec2 uv = (texCoord - 0.5) * OutSize;
    uv *= mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
    uv = uv / OutSize + 0.5;

    fragColor = texture(MainSampler, uv);

    // Outside screen bounds — show blurred version
    if (uv.x < 0. || uv.x > 1. || uv.y < 0. || uv.y > 1.) {
        fragColor = texture(BlurSampler, (uv - 0.5)*sqrt(0.5) + 0.5);
    }

    // 2. GREYSCALE FILTER
    vec3 greyscale = vec3(dot(fragColor.rgb, vec3(0.2126, 0.7152, 0.0722)));
    float greyscaleAmount = readChannel(EXAMPLE_GREYSCALE_CHANNEL);  // 0.0–1.0
    fragColor.rgb = mix(fragColor.rgb, greyscale, greyscaleAmount);  // Smooth blend
}
```

---

## Rendering Pipeline (transparency.json)

Passes execute sequentially:

| # | Shader | Purpose | Input | Output |
|---|--------|---------|-------|--------|
| 1 | `blit` | Copy data texture to swap | `data` | `data_swap` |
| 2 | `data` | Read markers from particles, update data | `data_swap` + `particles` | `data` |
| 3 | `remove_particles` | Remove markers from particle layer | `particles` | `swap` |
| 4 | `transparency` | Standard vanilla transparency pass | all layers | `final` |
| 5–10 | `box_blur` x6 | Multi-pass blur (for example) | `final`→`swap`→... | `swap2` |
| 11 | `shader` | Apply effects (example) | `final` + `data` + `swap2` | `swap` |
| 12 | `blit` | Output result to screen | `swap` | `minecraft:main` |

> Passes 1–4 are the **ShaderSelector core** — don't touch them. Passes 5–12 are examples that you can replace with your own effects.

---

## Debugging

`shader.fsh` has a built-in debug mode. Uncomment the line:

```glsl
#define DEBUG
```

This will display the data texture contents in the top-left corner of the screen (scaled 4x). Column 0 shows raw RGBA marker values, other columns show the fractional part of decoded float values.

---

## Limitations and Notes

1. **Number of channels** is limited by the data texture height. By default, 3 rows = 2 channels (row 0 is time). To add channels, increase `height` in `transparency.json`.

2. **Value range:** The marker's blue channel (0–255) is normalized:
   - For operations 0, 1, 3: `value / 255.0` (0.0–1.0)
   - For cyclic operations 2, 4: `value / 256.0` (so 256 values evenly cover the cycle, and 0 != 256/256)

3. **The particle must be visible** for at least 1 frame. If it's off-screen, the marker won't trigger. Use `^ ^ ^2` (2 blocks in front of camera) or `~ ~1 ~` (1 block above player).

4. **Multiple markers for the same channel** in one frame: the last one overwrites the previous.

5. **Persistence:** The data texture is preserved between frames (`"persistent": true`), so values don't reset. However, if the resource pack is reloaded, data is lost.

6. **DeltaTime:** The system automatically calculates delta time and skips updates if `deltaTime > 0.1` (lag/pause protection) or `deltaTime == 0` (two frames in one tick).

7. **A marker only needs to be sent once.** The value persists. Sending the same value again doesn't change state (checked via `previousColor.b == particleColor.b`).

---

## Quick Cheat Sheet

### Add a new controllable parameter:

1. In `marker_settings.glsl`: define `#define MY_CHANNEL N` and add `ADD_MARKER(...)` to `LIST_MARKERS`
2. In `transparency.json`: increase data texture `height` if needed
3. In your shader: `float value = readChannel(MY_CHANNEL);`
4. Compute ARGB: `-67239936 + green * 256 + value`
5. In datapack: `particle entity_effect{color:<ARGB>} ^ ^ ^2`

### Minimal shader:

```glsl
#version 330

uniform sampler2D MainSampler;
uniform sampler2D DataSampler;

#moj_import <shader_selector:marker_settings.glsl>
#moj_import <shader_selector:utils.glsl>
#moj_import <shader_selector:data_reader.glsl>

in vec2 texCoord;
out vec4 fragColor;

void main() {
    float myValue = readChannel(MY_CHANNEL);
    fragColor = texture(MainSampler, texCoord);
    // ... your effect using myValue ...
}
```

### Quick test from chat:

```
/particle entity_effect{color:-67174913} ~ ~1 ~    <- greyscale ON
/particle entity_effect{color:-67175168} ~ ~1 ~    <- greyscale OFF
/particle entity_effect{color:-67175616} ~ ~1 ~    <- rotation 90°
/particle entity_effect{color:-67175680} ~ ~1 ~    <- rotation 0°
/particle entity_effect{color:-67175296} ~ ~1 ~    <- smooth rotation 180°
/particle entity_effect{color:-67175424} ~ ~1 ~    <- smooth rotation 0°
```
