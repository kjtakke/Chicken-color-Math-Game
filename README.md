# chicken-ant.sh

A terminal version of "I gave a chicken two rules and it made this": [Langton's Ant](https://en.wikipedia.org/wiki/Langton%27s_ant), extended to any number of colours. It's a single bash script with no dependencies, and it runs on the bash 3.2 that ships with macOS.

## How it works

The chicken walks on an endless grid. On every step it:

1. Looks at the colour of the cell it is standing on.
2. Turns the way that colour's rule says (left, right, straight on or U-turn).
3. Repaints the cell with the next colour in the cycle.
4. Steps forward one cell.

The classic two-colour game (rule `RL`) scribbles randomly for about 10,000 steps, then suddenly starts building a straight diagonal "highway" forever. Other rules grow symmetric shapes, triangles, filled squares or chaos.

## Running it

```sh
~/bin/chicken-ant.sh
```

Run it in a real terminal window, such as WezTerm, iTerm2 or Terminal.app. It needs a keyboard attached to the terminal, so it won't work through Claude Code's `!` prefix. The terminal must support 256 colours.

If it is started with `sh` or `zsh`, it restarts itself under bash.

## Menu

Use the arrow keys to move around the menu. WASD and h/j/k/l also work.

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select a row |
| ← / → | Change the value |
| Enter | Start (or change the selected value) |
| q | Quit |

| Setting | What it does |
| --- | --- |
| **Preset** | Loads a known rule: Classic chicken `RL`, Symmetric `LLRR`, Chaotic `RLR`, Square filler `LRRRRRLLR`, Triangle `RRLLLRLLLRRR`, Highway `LLRRRLRLRLLR` |
| **Colours** | Number of colours, 2 to 12 |
| **Speed** | 1 to 10, from one step per frame up to about 1,000 steps per frame |
| **Edges** | **Zoom out** (the view grows with the pattern) or **Wrap around** (the chicken comes back in on the opposite side) |
| **Zoom at** | How close to the edge the chicken can get before the view zooms out, in text rows (1 to 20; default 3, about 50px) |
| **Colour rules** | One row per colour: the turn the chicken makes when standing on that colour |

Changing the number of colours or any colour rule switches the preset to **Custom**. The rule string (for example `RLR`) appears at the bottom of the menu.

## During the game

| Key | Action |
| --- | --- |
| `+`, PageUp, ↑ or → | Faster |
| `-`, PageDown, ↓ or ← | Slower |
| Space | Pause or resume |
| `r` | Restart with the same rules |
| Esc or `q` | Back to the menu |

The status line shows the step count, the rule, the speed and the current zoom.

## Zooming

In **Zoom out** mode, the view zooms out when the chicken comes within the **Zoom at** margin of an edge. It keeps zooming out until the whole pattern fits, then re-centres on it.

- **Zoom 1/1:** each cell is a two-character square, and the chicken is drawn as 🐔.
- **Zoom 1/2 and further:** cells are drawn with half-block characters (`▀`), two per character. Each further zoom level halves the size again, up to 1/4096. The chicken appears as a small white dot.

Far out, each dot shows the colour of one cell from the block it covers, so fine detail is lost but the overall shape stays visible.

## Troubleshooting

**Arrow keys do nothing.** Run:

```sh
~/bin/chicken-ant.sh --keys
```

Press the arrow keys. The script prints the bytes your terminal sends for each key, and you can match them against what the script expects. Press `q` to exit.

**The 🐔 looks misaligned.** Your terminal draws the emoji at single width. The game still works; only the chicken marker is affected.

**It's slow at high speeds.** Bash is not fast. Expect roughly 3,000 to 5,000 steps per second, depending on the terminal size and zoom level.
