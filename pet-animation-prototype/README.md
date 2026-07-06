# Lazy Fish animation prototype

This folder contains a first-pass animation preview made from the provided static character image.
The motion is transformation-and-prop based, so it is useful for judging style and Swift integration, not final production animation quality.

Actions:
- Idle / breathing
- Desk work
- Drink coffee
- Eat burger
- Play phone
- Walk
- Lie down
- Sleep
- Wave
- Focused work

Key files:
- source_transparent.png: source character with the white background removed
- pixel_static.png: pixel-style source character
- normal/gifs/*.gif: normal-style behavior previews
- pixel/gifs/*.gif: pixel-style behavior previews
- normal/contact_sheet.png and pixel/contact_sheet.png: quick overview
- normal/strips/*.png and pixel/strips/*.png: horizontal frame strips for app experiments

For a production Swift desktop pet, use the same action names as state IDs and swap GIF previews for APNG/WebP frame strips or a SpriteKit texture atlas.