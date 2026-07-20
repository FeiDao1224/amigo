# Pet Animation System

## Runtime Model

- `PetRuntime.swift` owns the selected character, current frames, frame rate, direction, bubble state, and fallback motion.
- `PetView.swift` renders generated frames first, then a static transparent PNG, then the placeholder pet.
- `SpriteGen.swift` owns the generation pipeline: image edit request, 3x3 slicing, edge-connected white removal, centroid and baseline registration, then `frame-0...8.png` persistence.
- `PetImages.swift` installs bundled starter characters and frames into `~/Library/Application Support/Amigo/pets/` on first launch.

## Asset Contract

```
Assets/pets/<character>.png
Assets/pets/generated/<character>/<action>/frame-0.png
~/Library/Application Support/Amigo/pets/<character>.png
~/Library/Application Support/Amigo/pets/generated/<character>/<action>/frame-0.png
```

The package script copies `Assets/pets/` into the app bundle. User-created content always lives under Application Support and is never written back into the repository.

## Playback Contract

- Built-in actions are `work`, `phone`, `think`, `idle`, `walk`, and `sleep`, defined by `PetAnimAction`.
- Bundled starter frames ship for `work`, `phone`, `think`, `idle`, and `walk`; `sleep` has no bundled frames and falls back to the current frames until the user generates it.
- Generated clips use a 3x3 sheet and produce nine frames.
- Frame rate is calculated from `PetAnimAction.loopSeconds`, capped at 20 fps, so older four-frame clips remain compatible.
- Missing frames fall back to the static character image and, for dragging, procedural movement.
- Registration aligns the alpha centroid horizontally and the base vertically to reduce visible shaking.

## Generation Notes

The model can still produce invalid poses or inconsistent frames. `dropOutlierFrames` discards frames whose alpha bounding box deviates from the median height, which catches most clipped or collapsed frames, but the pipeline does not verify orientation or score character similarity. Treat a generated clip as user-reviewable output, not as an automatically trusted asset.
