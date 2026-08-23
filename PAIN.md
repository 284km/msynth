# PAIN.md — what the audio shape forced

## P1 — the capability itself (mere v0.1.314)

Native audio output did not exist. The `audio_*` externs (SDL2 audio, push
model) were added for this consumer. The design point that mattered: audio
APIs usually hand the host a callback on a device thread, which for Mere
would mean a foreign thread calling back into the language — a boundary
design of its own. SDL_QueueAudio inverts the direction: the device drains a
queue and the program's job is to keep it fed. The deadline is unchanged;
who crosses the boundary is.

## P2 — there is no float power

`pow` is int^int. Equal temperament wants `2.0 ** (n/12)`, which had to be
spelled `exp (x * log 2.0)`. Fine — and byte-identical to the oracle
computing the same thing — but the spelling is a workaround, not a choice.
An `fpow`/float-`pow` overload is an upstream candidate when a second
consumer wants it.

## P3 — the predicted pain did not materialize (a result)

The design brief expected "a hard-deadline no-alloc hot path" to strain the
region model. It did not: one fixed arena chunk buffer, float math staying
in C doubles, and the whole 2.1-second playback touches the default region
for 2,304 bytes — all of it startup, none of it per sample. Writing s16le
via two `mem_set_u8` calls per sample (there is no little-endian 16-bit
writer) also cost nothing measurable at 44.1 kHz. The region model already
fits real-time audio without new machinery; that is a negative result worth
keeping.

## P4 — the checkable half of a sound

SDL's disk audio driver was measured rewriting queued samples (stereo
upmix, chunk padding), so "compare the driver's file" would have tested
SDL's resampler, not this synthesizer. The split that works: byte-exactness
lives in `render` against an independent oracle (same formulas, same
doubles, same truncation — 185,220 bytes, no tolerance), and the device
path is held to its queue contract headless (dummy driver).
