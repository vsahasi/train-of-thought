# Contributing

The easiest and most welcome contribution is a new car.

## Drawing a car

Cars live in `Sources/TrainOfThought/Overlay/Sprites.swift`. A car is 20
pixels wide and 16 tall, one character per pixel:

```
....................
....................
....................
.KKKKKKKKKKKKKKKKKK.
KBBBBBBBBBBBBBBBBBBK
KBBBBBBKBBBBKBBBBBBK
KBBBBBBKBBBBKBBBBBBK
KBBBBBBKBbbBKBBBBBBK
KBBBBBBKBBBBKBBBBBBK
KBBBBBBKBBBBKBBBBBBK
KbbbbbbKbbbbKbbbbbbK
KKKKKKKKKKKKKKKKKKKK
.KSSSSSSSSSSSSSSSSK.
..KDDK........KDDK..
..KDQK........KDQK..
...KK..........KK...
```

- `.` is transparent. Letters are colours from `Pixel.Palette.standard`
  (`K` outline, `B`/`b` blue, `O`/`o` orange, `G`/`g` green, `P`/`p`
  purple, `N`/`n` wood, `W` white, `L` glass, `S`/`s` steel).
- Keep the bottom four rows as they are: that is the chassis and the
  wheels. A wheel is `KDDK` over `KDQK`; the `Q` is the hub highlight
  that gets animated around the wheel.
- Body colours get swapped for gold on every sixth car, so draw the body in
  one of the paired colours (`B`/`b`, `O`/`o`, …). Details drawn in `K`,
  `W` or `L` stay as they are.

Then:

1. Add a case to `CarKind` in `Sources/TrainCore/Rules.swift`. Cars cycle
   through the cases in order.
2. Map it in `Sprite.car(_:)`.
3. Run with a fast clock to watch it couple on:
   `make && TRAIN_CAR_SECONDS=3 "build/Train of Thought.app/Contents/MacOS/TrainOfThought"`
4. `make hero` to refresh the README animation, and include the new
   `assets/hero.svg` in your pull request.

## Everything else

- The rules of the railway live in `Sources/TrainCore` and are the only
  part of the app with tests. If you change a rule, change or add a test
  in `Tests/TrainCoreTests` first. `make test` runs them with or without
  Xcode.
- The overlay must stay wordless and must never need a permission.
- No dependencies, no network code, no analytics. The whole app is under
  two megabytes and should stay that way.
- The design document in `docs/superpowers/specs/` explains why things
  are the way they are. If you want to change a decision recorded there,
  open an issue first so we can talk about it.
