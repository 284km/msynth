# msynth

A synthesizer written in [Mere](https://github.com/merelang/mere), whose
deadline is audible.

```
msynth render <out.pcm>   the demo melody as raw s16le mono 44.1 kHz
msynth play               the same melody, out loud
msynth midi               live: play a MIDI keyboard through it
```

Three modes, one synthesis rule (sine voices, linear attack/release,
equal-temperament tuning). `render` writes the samples to a file, which is
what makes the sound checkable: `verify.sh` computes the same samples
independently and compares byte for byte. `play` pushes the same samples at
a real device through Mere's `audio_*` queue (SDL2, push model — the program
keeps the queue fed; the device never calls back). `midi` is the mode with a
hard deadline: notes arrive whenever a human plays them, and the queue must
never run dry while a key is held.

The real-time path allocates nothing per sample — 2.1 seconds of audio cost
2,304 bytes of region traffic total (startup strings), which `verify.sh`
holds as a bound. A hard-deadline loop needs exactly that property, and the
region model provides it with one fixed chunk buffer and no special
machinery.

## Build

```sh
brew install sdl2 portmidi   # or apt-get install libsdl2-dev libportmidi-dev
mere -c msynth.mere > msynth.c
cc -O2 -w msynth.c $(sdl2-config --cflags --libs) -lportmidi -o msynth
```

To play live, plug in a MIDI keyboard and run `msynth midi`.

## License

MIT
