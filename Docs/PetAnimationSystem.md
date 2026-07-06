# Pet Animation System

## Current Project Read

- App structure: Swift Package executable using SwiftUI views hosted inside AppKit windows.
- Desktop window: `AppDelegate.swift` creates a transparent floating `NSPanel`, keeps it above the desktop, handles drag position, click-through hit testing, status item, and settings/chat windows.
- Existing pet view: `PetView.swift` renders bubble/input/pet body. Before this animation system, it loaded a static transparent PNG through `PetImages.image(_:)`, then applied procedural whole-image motion through `PetMotion`.
- Existing state: `PetRuntime.swift` owns high-frequency pet state, bubbles, selected character id, speech, file reaction, and feed actions.
- Existing static image fallback: `PetImages.swift` reads `~/Library/Application Support/Lingzai/pets/{name}.png`.

## New Files

- `Sources/Lingzai/PetAnimation.swift`: action enum, profile/config models, Bundle asset loader, frame clip cache, and `PetAnimator`.
- `Sources/Lingzai/Resources/Pets/lazy_fish/profile.json`: first animation profile.
- `Sources/Lingzai/Resources/Pets/lazy_fish/{action}/frame_000.png`: prototype pixel frames for the 10 fixed actions.
- `Sources/Lingzai/Resources/Pets/README.md`: 16bit pixel import spec.

## Modified Files

- `Package.swift`: processes `Sources/Lingzai/Resources` as Swift Package resources.
- `PetRuntime.swift`: owns a `PetAnimator`, loads the selected character, maps legacy `PetState` to `PetAction`, and exposes debug playback.
- `PetView.swift`: prefers animated frames when present, keeps old static PNG / code cat fallback, disables interpolation for pixel frames, and adds a right-click action debug menu.
- `AppDelegate.swift`: switches character changes through `PetRuntime.setCharacter(_:)`.

## Behavior Contract

- Missing profile or missing action frames do not crash the app.
- If a selected character has no animation profile, Lingzai keeps the old static PNG path.
- Loop actions repeat.
- Non-loop actions return to `idle_stand`, except actions marked `holdLastFrame`.
- Timer playback runs on the main run loop and is invalidated before replacement.
- UI frame updates are main-thread isolated.

## Next Step

Replace the prototype `lazy_fish` PNG frames with real 16bit pixel-art frames exported from Aseprite or an image model, keeping the same folder and filename contract.
