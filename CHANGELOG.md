# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] — first public release

### Added

- Braille dot-matrix renderer: one character cell holds a 2×4 dot block, one dot is 3×3 logical
  pixels, so the default 900×150 world becomes 150 columns × 13 rows without aspect distortion.
- Dirty-column-range repainting: only the character rows and column ranges that actually changed are
  written, which keeps a pure-PowerShell renderer inside the 60 fps budget.
- Physics ported frame by frame from the Chromium source: jump velocity, gravity, min/max jump
  height, the JS `Math.round` position update, the 35-frame airtime, the speed ramp, the obstacle gap
  formula, the score formula and the collision box sets.
- Obstacles: small and large cacti in 1–3 unit clusters (including clusters that mix both sizes),
  plus pterodactyls at three flight altitudes, gated behind both a speed threshold and the third sky act.
- Controls: hold to jump higher, tap for short hops, fast-fall by pressing down while airborne and
  stay ducking on landing, restart on key release.
- Three sky acts cycling by distance, with a four-layer bottom-to-top colour curtain between them:
  grey + dots → grey → target colour + dots → target colour.
- Automatic glyph fallback: each of Braille, `▀`, `▄` and `█` is probed individually, and rendering
  degrades to block or ASCII mode when the console code page lacks glyphs.
- Console code page is switched to UTF-8 on startup so the in-game output and the host output agree.
- 30 assertion self-test (`-Simulate`), bot playthrough, glyph-fallback self-test and performance
  benchmark (`-Dump`).
- ASCII launcher (`ChromeDino.cmd`) that prefers Windows Terminal and falls back to
  Windows PowerShell 5.1.

### Compatibility

- Runs on Windows PowerShell 5.1 and PowerShell 7+ from the same file.
- The script must be saved as UTF-8 **with BOM**; PowerShell 5.1 otherwise misreads the non-ASCII text.

### Known deviations from the original game

- Fixed 16.67 ms logic step with a 5-step catch-up cap (the original uses an unclamped `deltaTime`).
- No sound; the high score is kept in memory only.
- Maximum speed is 20 (original: 13) with a speed-dependent obstacle density factor, plus the
  three-act weather cycle and colour curtain — additions beyond the original.
- The dinosaur blinks while running as well as while idle.
- Obstacle clusters may mix small and large cacti; collision boxes are generated per unit so the
  hitboxes still match the drawn art.
