# Chrome Dino — Terminal Edition

A frame-accurate re-implementation of the **Chrome offline T-Rex game** that runs entirely inside a
terminal window. Pure PowerShell — no modules, no external binaries, no dependencies.

Every pixel is drawn with **Braille Unicode characters**: one character cell is a 2×4 dot block, so a
single character holds 8 "pixels" of the game world.

```
            ⣀⣀⡀
            ⣯⣿⡿
        ⣀⣀⣀⣴⣿⡿
        ⢸⡿⠿⣿⡟⠁
⠤⠤⠤⠤⠤⠤⠤⠤⠼⠧⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤⠤
```

---

## Features

- **Dot-matrix renderer.** 1 dot = 3×3 logical pixels; one character = 2×4 dots. The default
  900×150 logical canvas becomes 150 columns × 13 rows with no aspect distortion (dots are square).
- **Physics ported frame by frame** from the Chromium source — jump velocity, gravity, min/max jump
  height, speed ramp, obstacle gap formula, collision boxes, score rounding.
- **Full obstacle set**: small / large cacti (1–3 unit clusters, including *mixed-size* clusters),
  and pterodactyls at three flight altitudes (duck the low one, jump the high one, ignore the middle one).
- **Hold-to-jump-higher**, short-tap small hops, and fast-fall by pressing ↓ while airborne
  (you stay ducking when you land, exactly like the original's auto-repeat behaviour).
- **Rising difficulty**: speed ramps 6 → 20, obstacle spacing tightens as speed increases,
  pterodactyls only appear from the third sky act onward.
- **Three sky acts**, cycling by distance: night with sparse clouds and few stars → daybreak with
  inverted colours → a starry night with a crescent moon and shooting stars.
  Transitions are a bottom-to-top curtain in four layers (grey + dots → grey → target colour + dots → target colour).
- **Graceful glyph fallback.** On startup the script probes the console for `⠂`-range Braille,
  `▀`, `▄` and `█`, then picks braille / block / ASCII rendering automatically — no more `?` soup on
  a GBK code page.
- **Runs on both PowerShell 5.1 and PowerShell 7+** from a single file.
- **30 built-in assertions** (`-Simulate`) plus a bot playthrough, a glyph-fallback self-test and a
  performance benchmark (`-Dump`).

## Requirements

| | |
| --- | --- |
| OS | Windows 10 / 11 |
| Shell | Windows PowerShell 5.1 **or** PowerShell 7+ |
| Terminal | at least **151 columns × 15 rows** |
| Font | ideally one that contains Braille (Cascadia Mono, Consolas). Any other font still works via the fallback modes |

## Quick start

**Option A — double click**

```
ChromeDino.cmd
```

**Option B — run the script directly**

```powershell
pwsh -ExecutionPolicy Bypass -File .\ChromeDino.ps1
# or, on a machine with only Windows PowerShell:
powershell -ExecutionPolicy Bypass -File .\ChromeDino.ps1
```

If the window is too narrow the script says so instead of drawing garbage — resize until it fits.

## Controls

| Key | Action |
| --- | --- |
| `Space` / `↑` / `W` | Jump — **hold** to jump higher, tap for a short hop |
| `↓` / `S` | Duck. While airborne it triggers a fast-fall, and you keep ducking on landing |
| `Enter` | Restart (fires on key **release**, like the original) |
| `Esc` | Quit |

## Rendering modes

```powershell
.\ChromeDino.ps1 -Render auto      # default: probe the console and pick the best mode
.\ChromeDino.ps1 -Render braille   # U+2800..U+28FF, 8 dots per cell  (sharpest)
.\ChromeDino.ps1 -Render block     # ▀ ▄ █ half blocks
.\ChromeDino.ps1 -Render ascii     # #
.\ChromeDino.ps1 -Ascii            # shortcut for -Render ascii
.\ChromeDino.ps1 -NoColor          # do not touch colours (for odd terminals / piping)
```

`auto` probes each glyph individually, so a code page that has `█` but not `▀` (GBK, for example)
downgrades cleanly instead of printing `?` for half the screen.

## Command-line options

| Option | Meaning |
| --- | --- |
| `-CanvasWidth <px>` | Logical canvas width, default `900`. The game world scales with it; physics do not change |
| `-Render <mode>` | `auto` / `braille` / `block` / `ascii` |
| `-Ascii` | Force ASCII rendering |
| `-NoColor` | Leave console colours alone |
| `-FocusOnly` | Only accept input while the console window is focused |
| `-Simulate` `-SimulateFrames <n>` | Run the assertion suite (deterministic seed) and exit |
| `-Dump` `-DumpFrames <n>` | Bot playthrough, per-frame snapshots, sprite dot-art previews, glyph self-test, benchmark |
| `-GlyphTest` | Print glyph samples through the host channel (useful when the in-game output looks wrong) |

## How faithful is it?

The constants and formulas were extracted from the Chromium game source, not guessed
(see [`CHROMIUM-DINO-REFERENCE.md`](CHROMIUM-DINO-REFERENCE.md)).

| Behaviour | Value / check |
| --- | --- |
| Initial jump velocity | `-10`, plus `speed / 10` at take-off |
| Gravity | `0.6` per frame |
| Jump height clamp | `maxJumpHeight = 30`, min jump height `93 - 30 = 63` |
| Position update | `yPos += Floor(jumpVelocity * framesElapsed + 0.5)` — JS `Math.round` reimplemented by hand, because PowerShell's `[Math]::Round` uses banker's rounding and drifts by a frame |
| Airtime | 35 frames; peak `yPos = 2` when held, `31` on a tap |
| Jump trace (first 35 frames) | `82,72,63,54,46,38,31,25,20,16,12,9,6,4,3,2,2,2,3,5,7,10,13,17,22,27,33,39,46,54,62,71,80,90,93` |
| Speed | starts at `6`, `+0.0007` per frame, caps at `20` (~5.6 minutes) |
| Score | `round(ceil(distanceRan) * 0.025)` → 40 px per point |
| Milestone flash | every 100 points, 250 ms on/off, 3 iterations |
| Obstacle gap | `minGap = round(width * speed + type.minGap * 0.6)`, `maxGap = round(minGap * 1.5)` |
| Pterodactyl | from `speed >= 8.5`, only from the third sky act |
| Collision | same box sets as the original, including the `+1 / -2` insets and the duck child box `(1, 18, 55, 25)` clipped to 42 px by the outer box |
| Restart | fires on key release, not key press |

## Performance

Measured on the same machine, 150 columns × 13 rows, per frame (60 fps budget = 16.67 ms):

| Shell | Logic | Render | Total |
| --- | --- | --- | --- |
| PowerShell 7.6 | 0.04 ms | 2.80 ms | **2.84 ms** |
| Windows PowerShell 5.1 | 0.20 ms | 8.75 ms | **8.95 ms** |

The renderer keeps a small `Sub` dot buffer and only repaints *dirty column ranges* per character row,
which is why plain PowerShell keeps up. 5.1's older script engine is roughly 3× slower but still fits
the frame budget.

## Self-tests

```powershell
.\ChromeDino.ps1 -Simulate -SimulateFrames 20000
```

30 assertions, all passing on both shells, covering the exact jump trace, hold-vs-tap peak height,
the speed ramp, gap bounds, duplicate-type limits, mixed-size clusters, pterodactyl gating, score
rounding, and collision geometry (duck hit / duck miss / standing hit, box rewrites for `size > 1`).

`-Dump` additionally plays the game with a scripted bot for N frames and prints glyph-fallback and
benchmark results.

## Known deviations from the original

These are deliberate; everything else is meant to match.

- Logic runs on a fixed 16.67 ms step with a 5-step catch-up cap (Chrome uses an unclamped `deltaTime`).
- No sound, and the high score lives in memory only.
- The three-act weather system, the colour-curtain transition, and the maximum speed of 20 with a
  speed-dependent density factor are additions/tuning beyond the original.
- Blinking happens while running as well as while idle.
- Obstacle clusters may mix small and large cacti (the original tiles one sprite); collision boxes are
  built per unit so the hitboxes still match the art.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Everything looks like `?` or blocks | The console code page lacks the glyphs. The script switches the console to UTF-8 on startup; if the font itself is missing Braille, run with `-Render block` or `-Render ascii` |
| "terminal is too narrow" | Resize to at least 151 columns × 15 rows, or lower `-CanvasWidth` |
| Script refuses to run | Use `ChromeDino.cmd`, or run with `-ExecutionPolicy Bypass` |
| Chinese text in the script is mojibake | The file lost its UTF-8 BOM — PowerShell 5.1 needs it. Re-save as "UTF-8 with BOM" |
| Window closes before you can read the score | The launcher uses `pause`; when running manually, the score is printed before exit |

## License

[MIT](LICENSE).

## Disclaimer

This is an unofficial fan re-implementation for fun and for learning how the original ticks. It is not
affiliated with, endorsed by, or connected to Google or the Chromium project. "Chrome Dino" / "T-Rex
Runner" refers to the game bundled with Google Chrome; all artwork here was drawn from scratch as text
dot-matrix bitmaps, and the numeric constants were taken from the publicly available Chromium source
for accuracy.
