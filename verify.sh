#!/bin/sh
# verify.sh — the sound is a number you can check.
#
#   MERE=/path/to/mere.exe sh verify.sh   (or MERE=<mere checkout>)
#
# Three claims:
#
#   bytes     `render` writes raw PCM, and this script computes THE SAME
#             samples independently in Python — same formulas, same doubles,
#             same truncation — and compares byte for byte. 185,220 bytes of
#             agreement or a failure; no tolerance, no "sounds right".
#   deadline  `play` feeds a real (dummy-driver) audio queue chunk by chunk
#             through one fixed arena buffer. MERE_REGION_STATS must report
#             the default region under 4 KB after 2.1 s of audio: the
#             hot path allocates NOTHING per sample, which is the property
#             a hard-deadline loop actually needs.
#   absence   `midi` with no MIDI devices says so and exits cleanly — the
#             hardware mode's failure is a sentence, not a crash.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# MERE is the compiler (the convention most verify.sh files follow) or a mere
# checkout; either works. MERE_ROOT is the checkout when one can be found.
[ -n "${MERE:-}" ] || { echo "usage: MERE=/path/to/mere.exe (or a mere checkout) sh verify.sh" >&2; exit 2; }
if [ -d "$MERE" ]; then MERE_ROOT="$MERE"; M="$MERE/_build/default/bin/mere.exe"
else M="$MERE"; MERE_ROOT="$(cd "$(dirname "$MERE")/../../.." 2>/dev/null && pwd)"; fi
[ -x "$M" ] || { echo "verify: $M not found (dune build?)" >&2; exit 2; }
CC="${CC:-cc}"
command -v sdl2-config >/dev/null 2>&1 || { echo "verify: no sdl2-config — skipping" >&2; exit 0; }

PM_CFLAGS=""; PM_LIBS="-lportmidi"
if command -v brew >/dev/null 2>&1 && brew --prefix portmidi >/dev/null 2>&1; then
  PM_PREFIX="$(brew --prefix portmidi)"
  PM_CFLAGS="-I$PM_PREFIX/include"; PM_LIBS="-L$PM_PREFIX/lib -lportmidi"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$M" -c "$DIR/msynth.mere" > "$TMP/msynth.c" 2>"$TMP/err" \
  || { echo "FAIL verify: mere -c"; cat "$TMP/err"; exit 1; }
"$CC" -O2 -w $PM_CFLAGS "$TMP/msynth.c" $(sdl2-config --cflags --libs) $PM_LIBS -o "$TMP/msynth" 2>"$TMP/cc.err" \
  || { echo "verify: build needs portmidi + sdl2 — skipping"; cat "$TMP/cc.err" | head -3; exit 0; }

# --- bytes: render vs the independent oracle ---------------------------------
"$TMP/msynth" render "$TMP/melody.pcm" > /dev/null
python3 - "$TMP/melody.pcm" <<'PY' || { echo "FAIL verify: render differs from oracle"; exit 1; }
import math, sys
rate = 44100
attack, release = 441, 1323
dur = rate * 300 // 1000
melody = [60, 64, 67, 72, 67, 64, 60]
out = bytearray()
for n in melody:
    f = 440.0 * math.exp((n - 69) / 12.0 * math.log(2.0))
    for i in range(dur):
        env_a = i / attack if i < attack else 1.0
        left = dur - i
        env = env_a * left / release if left < release else env_a
        v = 8000.0 * env * math.sin(6.283185307179586 * f * i / 44100.0)
        s = int(v)
        s = max(-32768, min(32767, s))
        if s < 0: s += 65536
        out.append(s % 256); out.append(s // 256)
got = open(sys.argv[1], "rb").read()
assert bytes(out) == got, f"oracle {len(out)}B vs got {len(got)}B"
PY
echo "  ok | render: 185220 bytes, byte-identical to the oracle"

# --- deadline: the play loop allocates nothing per sample --------------------
out="$(SDL_AUDIODRIVER=dummy MERE_REGION_STATS=1 "$TMP/msynth" play 2>&1)"
echo "$out" | grep -q "^played$" || { echo "FAIL verify: play did not complete"; echo "$out"; exit 1; }
alloc="$(echo "$out" | sed -n 's/.*alloc_total=\([0-9]*\).*/\1/p')"
[ -n "$alloc" ] || { echo "FAIL verify: no region-stats line — meter gone"; exit 1; }
[ "$alloc" -gt 0 ] || { echo "FAIL verify: alloc_total=0 — the meter cannot see startup"; exit 1; }
[ "$alloc" -lt 4096 ] || {
  echo "FAIL verify: play allocated $alloc bytes — the deadline path is allocating"; exit 1; }
echo "  ok | play: 2.1s of audio, $alloc bytes of region traffic total"

# --- absence: no MIDI hardware is a sentence, not a crash ---------------------
# With a keyboard attached, midi mode runs forever (that is its job), so it is
# started in the background and given one second to say which world it is in.
SDL_AUDIODRIVER=dummy "$TMP/msynth" midi > "$TMP/midi.out" 2>&1 &
MIDI_PID=$!
sleep 1
kill "$MIDI_PID" 2>/dev/null; wait "$MIDI_PID" 2>/dev/null
midi_out="$(head -1 "$TMP/midi.out")"
case "$midi_out" in
  "no MIDI input"|"playing"*) echo "  ok | midi: '$midi_out'";;
  *) echo "FAIL verify: midi mode said '$midi_out'"; exit 1;;
esac

echo "verify: ok"
