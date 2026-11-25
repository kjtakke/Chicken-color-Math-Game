#!/usr/bin/env bash
# chicken-ant.sh - "I gave a chicken two rules" (Langton's Ant), generalised to n colours.
#
# Rules: the chicken looks at the colour of the cell it stands on, turns according to
# that colour's rule, changes the cell to the next colour in the cycle, then steps forward.
#
# Menu:  Up/Down select, Left/Right change, Enter start, q quit (WASD / hjkl also work)
# Debug: chicken-ant.sh --keys   shows what bytes your terminal sends
# Game:  Space pause, +/-, PageUp/PageDown or arrows change speed, r restart, Esc or q back to menu
# Works with bash 3.2 (macOS default) and newer.

# Re-run under bash if started with sh/zsh/etc.
if [ -z "$BASH_VERSION" ] || [ -n "$POSIXLY_CORRECT" ]; then exec bash "$0" "$@"; fi

# Always talk to the real terminal, even if stdin was redirected.
if [[ ! -t 0 ]]; then
  if { exec </dev/tty; } 2>/dev/null; then :; else echo "chicken-ant: needs an interactive terminal" >&2; exit 1; fi
fi

ESC=$'\e'

# Raw read of whatever bytes are waiting on the terminal (bypasses the shell's `read`).
raw_read() { dd bs=64 count=1 2>/dev/null; }

# --keys: show exactly what each key sends (for troubleshooting)
if [[ $1 == --keys ]]; then
  old=$(stty -g); stty -echo -icanon min 1 time 0
  trap 'stty "$old"; echo' EXIT
  echo "Press keys to see their bytes. Press q to quit."
  while :; do
    k=$(raw_read)
    printf '%s\n' "$(printf '%s' "$k" | od -An -c | tr -s ' ')"
    [[ $k == q ]] && exit 0
  done
fi

# Colour palette (256-colour background codes). Index 0 is the empty board colour.
PALETTE=(235 196 46 33 226 201 51 208 129 118 39 255)
CNAMES=(Black Red Green Blue Yellow Magenta Cyan Orange Purple Lime Sky White)
MAXC=${#PALETTE[@]}

# Turn options: L=left, R=right, N=no turn, U=U-turn (delta in quarter turns clockwise)
TCHARS=(L R N U)
TNAMES=("Left" "Right" "Straight" "U-turn")
TDELTA=(3 1 0 2)

PRESET_NAMES=("Custom" "Classic chicken" "Symmetric" "Chaotic" "Square filler" "Triangle" "Highway")
PRESET_RULES=("" "RL" "LLRR" "RLR" "LRRRRRLLR" "RRLLLRLLLRRR" "LLRRRLRLRLLR")

# Speed levels: steps per frame and delay per frame
SPEED_STEPS=(1 1 2 4 10 25 60 150 400 1000)
SPEED_DELAY=(0.30 0.10 0.05 0.03 0.02 0.01 0.01 0 0 0)

# Movement by direction 0=up 1=right 2=down 3=left
DX=(0 1 0 -1)
DY=(-1 0 1 0)

# State
N=2
RULE=(1 0)          # indices into TCHARS: colour0 -> R, colour1 -> L (classic)
PRESET=1
SPEED=5
SEL=0
EDGE=0              # 0 = zoom out at the edge, 1 = wrap around
MARGIN=3            # zoom-out margin in text rows (~16px each, so 3 = ~50px)
EDGE_NAMES=("Zoom out" "Wrap around")

STTY_SAVED=$(stty -g 2>/dev/null)

cleanup() {
  [[ -n $STTY_SAVED ]] && stty "$STTY_SAVED" 2>/dev/null
  printf '%s' "${ESC}[0m${ESC}[?25h${ESC}[2J${ESC}[H"
}
trap 'cleanup; exit 0' INT TERM
trap cleanup EXIT

rule_string() {
  local s="" i
  for ((i = 0; i < N; i++)); do s+=${TCHARS[RULE[i]]}; done
  printf '%s' "$s"
}

apply_preset() {
  local r=${PRESET_RULES[PRESET]} i ch j
  [[ -z $r ]] && return
  N=${#r}
  RULE=()
  for ((i = 0; i < N; i++)); do
    ch=${r:i:1}
    for j in 0 1 2 3; do [[ ${TCHARS[j]} == "$ch" ]] && RULE[i]=$j; done
  done
}

# Read one keypress into KEY. Arrow keys become up/down/left/right.
KEYBUF=""
read_key() {
  local more n=1
  if [[ -z $KEYBUF ]]; then
    stty -echo -icanon min 1 time 0 2>/dev/null
    KEYBUF=$(raw_read)
    [[ -z $KEYBUF ]] && { KEY=enter; return; }   # Enter (newline stripped by $(...))
    if [[ $KEYBUF == "$ESC" ]]; then
      # lone ESC: give the rest of an escape sequence 0.2s to arrive
      stty min 0 time 2 2>/dev/null
      more=$(raw_read)
      KEYBUF+=$more
      stty min 1 time 0 2>/dev/null
    fi
  fi
  case $KEYBUF in
    "${ESC}"[[O]A*) KEY=up; n=3 ;;
    "${ESC}"[[O]B*) KEY=down; n=3 ;;
    "${ESC}"[[O]C*) KEY=right; n=3 ;;
    "${ESC}"[[O]D*) KEY=left; n=3 ;;
    "${ESC}[1;"?A*) KEY=up; n=6 ;;      # modified arrows (Shift/Ctrl/Alt)
    "${ESC}[1;"?B*) KEY=down; n=6 ;;
    "${ESC}[1;"?C*) KEY=right; n=6 ;;
    "${ESC}[1;"?D*) KEY=left; n=6 ;;
    $'\r'* | $'\n'*) KEY=enter ;;
    " "*) KEY=space ;;
    [kKwW]*) KEY=up ;;                  # vim / WASD fallbacks
    [jJsS]*) KEY=down ;;
    [hHaA]*) KEY=left ;;
    [lLdD]*) KEY=right ;;
    [qQ]*) KEY=q ;;
    *) KEY=other ;;
  esac
  KEYBUF=${KEYBUF:n}
}

# ---------------------------------------------------------------- menu
# Rows: 0 preset, 1 colours, 2 speed, 3 edges, 4 margin, 5..5+N-1 colour rules, START, QUIT
FR=5   # first colour-rule row
menu_rows() { echo $((FR + N + 2)); }

draw_menu() {
  local out="${ESC}[H${ESC}[2J${ESC}[0m" r label val i
  out+=$'\n'"  ${ESC}[1m🐔  CHICKEN WITH RULES${ESC}[0m  (Langton's Ant, n colours)"$'\n'
  out+="  ${ESC}[2mOn each cell: turn by that colour's rule, repaint to the next colour, step forward.${ESC}[0m"$'\n\n'
  local rows=$(menu_rows)
  for ((r = 0; r < rows; r++)); do
    if ((r == 0)); then
      label="Preset"; val="${PRESET_NAMES[PRESET]}"
      ((PRESET > 0)) && val+=" (${PRESET_RULES[PRESET]})"
    elif ((r == 1)); then
      label="Colours"; val="$N"
    elif ((r == 2)); then
      label="Speed"; val="$((SPEED + 1))/10  ($(printf '%*s' $((SPEED + 1)) '' | tr ' ' '#')$(printf '%*s' $((9 - SPEED)) ''))"
    elif ((r == 3)); then
      label="Edges"; val="${EDGE_NAMES[EDGE]}"
    elif ((r == 4)); then
      label="Zoom at"; val="$MARGIN rows from edge (~$((MARGIN * 16))px)"
      ((EDGE == 1)) && val="(n/a when wrapping)"
    elif ((r < FR + N)); then
      i=$((r - FR))
      label="${ESC}[48;5;${PALETTE[i]}m    ${ESC}[0m $(printf '%-8s' "${CNAMES[i]}")"
      val="${TNAMES[RULE[i]]}"
    elif ((r == FR + N)); then
      out+=$'\n'
      label="▶ START"; val=""
    else
      label="✕ QUIT"; val=""
    fi

    if ((r == SEL)); then
      out+="  ${ESC}[1;33m›${ESC}[0m ${ESC}[7m"
    else
      out+="    "
    fi
    if [[ -n $val ]]; then
      if ((r >= FR && r < FR + N)); then
        out+="$label  ◀ $(printf '%-8s' "$val") ▶${ESC}[0m"$'\n'
      else
        out+="$(printf '%-10s' "$label")  ◀ $val ▶${ESC}[0m"$'\n'
      fi
    else
      out+=" $label ${ESC}[0m"$'\n'
    fi
    ((r == FR - 1)) && out+=$'\n'"    ${ESC}[2mColour rules (turn when standing on):${ESC}[0m"$'\n'
  done
  out+=$'\n'"  ${ESC}[2m↑/↓ select   ←/→ change   Enter start   q quit   Rule: $(rule_string)${ESC}[0m"$'\n'
  printf '%s' "$out"
}

menu_change() { # $1 = -1 or +1
  local d=$1 i
  if ((SEL == 0)); then
    PRESET=$(((PRESET + d + ${#PRESET_NAMES[@]}) % ${#PRESET_NAMES[@]}))
    ((PRESET == 0)) && PRESET=$(((PRESET + d + ${#PRESET_NAMES[@]}) % ${#PRESET_NAMES[@]}))
    apply_preset
  elif ((SEL == 1)); then
    N=$((N + d))
    ((N < 2)) && N=2
    ((N > MAXC)) && N=$MAXC
    for ((i = 0; i < N; i++)); do [[ -z ${RULE[i]} ]] && RULE[i]=$((i % 2 == 0 ? 1 : 0)); done
    PRESET=0
  elif ((SEL == 2)); then
    SPEED=$((SPEED + d))
    ((SPEED < 0)) && SPEED=0
    ((SPEED > 9)) && SPEED=9
  elif ((SEL == 3)); then
    EDGE=$((1 - EDGE))
  elif ((SEL == 4)); then
    MARGIN=$((MARGIN + d))
    ((MARGIN < 1)) && MARGIN=1
    ((MARGIN > 20)) && MARGIN=20
  elif ((SEL >= FR && SEL < FR + N)); then
    i=$((SEL - FR))
    RULE[i]=$(((RULE[i] + d + 4) % 4))
    PRESET=0
  fi
}

menu() {
  stty -echo -icanon min 1 time 0 2>/dev/null
  printf '%s' "${ESC}[?25l"
  while :; do
    draw_menu
    read_key
    local rows=$(menu_rows)
    case $KEY in
      up) SEL=$(((SEL - 1 + rows) % rows)) ;;
      down) SEL=$(((SEL + 1) % rows)) ;;
      left) menu_change -1 ;;
      right) menu_change 1 ;;
      enter)
        if ((SEL == FR + N)); then run_game; KEYBUF=""; stty -echo -icanon min 1 time 0 2>/dev/null
        elif ((SEL == FR + N + 1)); then exit 0
        else menu_change 1
        fi ;;
      q) exit 0 ;;
    esac
    rows=$(menu_rows)
    ((SEL >= rows)) && SEL=$((rows - 1))
  done
}

# ---------------------------------------------------------------- game
# The world is unbounded. Cells live in a sparse array keyed by (y+OFF)*SPAN + (x+OFF).
# The screen is a grid of "pixels": each character is 1 pixel wide and 2 pixels tall
# (drawn with the ▀ half block), which makes pixels roughly square.
#   Z=0   : 1 cell = 2x2 pixels (a 2-character square, chicken emoji shown)
#   Z>=1  : 1 pixel = B x B cells, B = 2^(Z-1)   (zoom 1/2, 1/4, 1/8 ...)
OFF=1048576
SPAN=2097152
ZMAX=12

# Visible area in cells for the current zoom level
view_cells() {
  if ((Z == 0)); then VW=$((PW / 2)); VH=$((PH / 2))
  else B=$((1 << (Z - 1))); VW=$((PW * B)); VH=$((PH * B)); fi
}

# Paint cell ($1,$2) with colour $3 into buf (or only into P when NODRAW=1)
paint_cell() {
  local dx=$(($1 - VX)) dy=$(($2 - VY)) px py t b
  ((dx < 0 || dy < 0 || dx >= VW || dy >= VH)) && return
  if ((Z == 0)); then
    buf+="${ESC}[$((dy + 1));$((dx * 2 + 1))H${ESC}[48;5;${COL[$3]}m  "
  else
    px=$((dx / B)); py=$((dy / B))
    P[py * PW + px]=$3
    ((NODRAW)) && return
    t=${P[(py & ~1) * PW + px]:-0}; b=${P[(py | 1) * PW + px]:-0}
    buf+="${ESC}[$((py / 2 + 1));$((px + 1))H${ESC}[38;5;${COL[t]};48;5;${COL[b]}m▀"
  fi
}

draw_chicken() {
  local dx=$((x - VX)) dy=$((y - VY)) px py t b
  ((dx < 0 || dy < 0 || dx >= VW || dy >= VH)) && return
  if ((Z == 0)); then
    c=${grid[(y + OFF) * SPAN + x + OFF]:-0}
    buf+="${ESC}[$((dy + 1));$((dx * 2 + 1))H${ESC}[48;5;${COL[c]}m🐔"
  else
    px=$((dx / B)); py=$((dy / B))
    t=${P[(py & ~1) * PW + px]:-0}; b=${P[(py | 1) * PW + px]:-0}
    if ((py % 2 == 0)); then
      buf+="${ESC}[$((py / 2 + 1));$((px + 1))H${ESC}[38;5;231;48;5;${COL[b]}m▀"
    else
      buf+="${ESC}[$((py / 2 + 1));$((px + 1))H${ESC}[38;5;231;48;5;${COL[t]}m▄"
    fi
  fi
}

# Clear the screen and redraw every visited cell at the current zoom
full_redraw() {
  local k ch px py t b
  local -a D
  P=()
  buf=""
  if ((Z == 0)); then
    for k in "${!grid[@]}"; do paint_cell $((k % SPAN - OFF)) $((k / SPAN - OFF)) ${grid[k]}; done
  else
    NODRAW=1
    for k in "${!grid[@]}"; do paint_cell $((k % SPAN - OFF)) $((k / SPAN - OFF)) ${grid[k]}; done
    NODRAW=0
    for k in "${!P[@]}"; do D[(k / PW / 2) * PW + k % PW]=1; done
    for ch in "${!D[@]}"; do
      px=$((ch % PW)); py=$((ch / PW * 2))
      t=${P[py * PW + px]:-0}; b=${P[(py + 1) * PW + px]:-0}
      buf+="${ESC}[$((py / 2 + 1));$((px + 1))H${ESC}[38;5;${COL[t]};48;5;${COL[b]}m▀"
    done
  fi
  printf '%s' "${ESC}[0m${ESC}[48;5;${COL[0]}m${ESC}[2J$buf"
  buf=""
}

# Zoom out until the whole pattern fits inside the margin, then re-centre on it
rezoom() {
  local bw=$((maxx - minx + 1)) bh=$((maxy - miny + 1)) mc
  while ((Z < ZMAX)); do
    Z=$((Z + 1)); view_cells
    mc=$((MP * B))
    ((bw + 2 * mc + 2 * B <= VW && bh + 2 * mc + 2 * B <= VH)) && break
  done
  ((Z >= ZMAX)) && MAXED=1
  VX=$(((minx + maxx - VW) / 2)); VY=$(((miny + maxy - VH) / 2))
  full_redraw
}

reset_world() {
  grid=(); P=(); steps=0; d=0; Z=0; B=1; MAXED=0; NODRAW=0
  view_cells
  if ((EDGE == 1)); then
    VX=0; VY=0; x=$((VW / 2)); y=$((VH / 2))
  else
    x=0; y=0; VX=$((-VW / 2)); VY=$((-VH / 2))
  fi
  minx=$x; maxx=$x; miny=$y; maxy=$y
  printf '%s' "${ESC}[0m${ESC}[48;5;${COL[0]}m${ESC}[2J"
}

run_game() {
  local cols lines ROWS PW PH MP VW VH VX VY Z B MAXED NODRAW x y d c i s steps buf k more paused=0 spf delay quit
  local minx maxx miny maxy dx dy
  local -a grid P COL TD
  cols=$(tput cols); lines=$(tput lines)
  ROWS=$((lines - 1)); PW=$cols; PH=$((ROWS * 2))
  ((PW < 8 || ROWS < 4)) && return

  # margin in pixels (1 row = 2 pixels tall = 2 chars wide), capped for small terminals
  MP=$((MARGIN * 2))
  ((MP > PH / 4)) && MP=$((PH / 4))
  ((MP > PW / 4)) && MP=$((PW / 4))

  for ((i = 0; i < N; i++)); do COL[i]=${PALETTE[i]}; TD[i]=${TDELTA[RULE[i]]}; done
  local rs=$(rule_string)

  printf '%s' "${ESC}[?25l"
  reset_world
  stty -echo -icanon min 0 time 0 2>/dev/null

  while :; do
    spf=${SPEED_STEPS[SPEED]}; delay=${SPEED_DELAY[SPEED]}
    if ((!paused)); then
      buf=""
      for ((s = 0; s < spf; s++)); do
        i=$(((y + OFF) * SPAN + x + OFF))
        c=${grid[i]:-0}
        d=$(((d + TD[c]) % 4))
        c=$(((c + 1) % N))
        grid[i]=$c
        paint_cell $x $y $c
        x=$((x + DX[d])); y=$((y + DY[d]))
        if ((EDGE == 1)); then
          x=$(((x + VW) % VW)); y=$(((y + VH) % VH))
        else
          ((x < minx)) && minx=$x; ((x > maxx)) && maxx=$x
          ((y < miny)) && miny=$y; ((y > maxy)) && maxy=$y
          if ((!MAXED)); then
            dx=$((x - VX)); dy=$((y - VY))
            if ((Z == 0)); then
              ((dx * 2 < MP || dy * 2 < MP || dx * 2 + 1 > PW - 1 - MP || dy * 2 + 1 > PH - 1 - MP)) && rezoom
            else
              ((dx < MP * B || dy < MP * B || dx / B > PW - 1 - MP || dy / B > PH - 1 - MP)) && rezoom
            fi
          fi
        fi
      done
      steps=$((steps + spf))
      draw_chicken
    else
      buf=""
    fi
    buf+="${ESC}[$((ROWS + 1));1H${ESC}[0m${ESC}[2K Step $steps | Rule $rs | Speed $((SPEED + 1))/10"
    if ((EDGE == 0)); then buf+=" | Zoom 1/$((1 << Z))"; ((MAXED)) && buf+=" (max)"; fi
    ((paused)) && buf+=" ${ESC}[1;33mPAUSED${ESC}[0m"
    buf+=" | ${ESC}[2mspace pause  +/- PgUp/PgDn speed  r restart  Esc menu${ESC}[0m"
    printf '%s' "$buf"

    # Non-blocking key read (dd, because bash 3.2's `read -n` forces blocking mode).
    # Several keys can arrive in one read, so walk through the whole buffer.
    k=$(raw_read)
    if [[ $k == "$ESC" ]]; then
      # lone Esc, or the start of an arrow sequence? wait 0.1s for the rest
      stty min 0 time 1 2>/dev/null; more=$(raw_read); stty min 0 time 0 2>/dev/null
      k+=$more
    fi
    quit=0
    while [[ -n $k ]]; do
      case $k in
        "${ESC}"[[O][AC]*) ((SPEED < 9)) && SPEED=$((SPEED + 1)); k=${k:3} ;;
        "${ESC}"[[O][BD]*) ((SPEED > 0)) && SPEED=$((SPEED - 1)); k=${k:3} ;;
        "${ESC}[5~"*) ((SPEED < 9)) && SPEED=$((SPEED + 1)); k=${k:4} ;;   # PageUp
        "${ESC}[6~"*) ((SPEED > 0)) && SPEED=$((SPEED - 1)); k=${k:4} ;;   # PageDown
        "${ESC}Ok"*) ((SPEED < 9)) && SPEED=$((SPEED + 1)); k=${k:3} ;;    # keypad +
        "${ESC}Om"*) ((SPEED > 0)) && SPEED=$((SPEED - 1)); k=${k:3} ;;    # keypad -
        "${ESC}["*) k=${k:2} ;;           # some other escape sequence: skip it
        "${ESC}"*) quit=1; break ;;       # Esc -> back to menu
        +* | =*) ((SPEED < 9)) && SPEED=$((SPEED + 1)); k=${k:1} ;;
        -* | _*) ((SPEED > 0)) && SPEED=$((SPEED - 1)); k=${k:1} ;;
        " "*) paused=$((!paused)); k=${k:1} ;;
        q* | Q*) quit=1; break ;;
        r* | R*) reset_world; k=${k:1} ;;
        *) k=${k:1} ;;
      esac
    done
    ((quit)) && break

    if ((paused)); then sleep 0.05
    elif [[ $delay != 0 ]]; then sleep "$delay"
    fi
  done
  printf '%s' "${ESC}[0m${ESC}[2J"
}

menu
