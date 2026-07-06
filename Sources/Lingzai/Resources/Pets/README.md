# Lingzai Pet Animation Assets

This folder is the Bundle resource entry for pixel pet animations.

## Folder Contract

```text
Pets/
  lazy_fish/
    profile.json
    idle_stand/
      frame_000.png
      frame_001.png
    desk_work/
    drink_coffee/
    eat_burger/
    play_phone/
    walk/
    lie_down/
    sleep/
    wave/
    shocked/
```

## 16bit Pixel Asset Spec

- Canvas: `160x192` transparent PNG.
- Style: 16bit pixel art.
- Scaling: nearest-neighbor only.
- Background: transparent.
- Frame naming: `frame_000.png`, `frame_001.png`, ascending without gaps.
- Each frame contains the full pet and any prop needed by that action.
- Do not split body parts into layers for the first version.
- Do not export white, checkerboard, or colored backgrounds.

## Required Actions

| Action ID | Frames | Loop |
| --- | ---: | --- |
| `idle_stand` | 6 | yes |
| `desk_work` | 8 | yes |
| `drink_coffee` | 6 | no |
| `eat_burger` | 6 | no |
| `play_phone` | 8 | yes |
| `walk` | 8 | yes |
| `lie_down` | 6 | no, hold last frame |
| `sleep` | 8 | yes |
| `wave` | 6 | no |
| `shocked` | 4 | no |

The current `lazy_fish` frames are prototype placeholders generated from the static pet image. Replace them with real Aseprite or image-model sprite frames using the same names and profile contract.
