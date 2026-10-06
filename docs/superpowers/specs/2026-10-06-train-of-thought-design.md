# Train of Thought — design

A tiny pixel-art train chugs along the bottom of your screen while you stay
in one app. Every few minutes it gains a car. Switch apps or get a
notification and it derails.

This is the design the first version was built from. It records the rules,
the decisions behind them, and what was deliberately left out.

## Purpose

Single-tasking is hard to *feel*. Timers nag; blockers punish. Train of
Thought makes the cost of a context switch visible and a little bit
heartbreaking, and makes a long unbroken stretch of work something you can
look at, and show off.

Success looks like:

- You glance down, see eleven cars, and decide the Slack ping can wait.
- Someone screenshots a 30-car train and posts it.
- Zero configuration needed. It does the right thing on first launch.

## Non-goals

- Blocking anything. The train never stops you from switching; it just
  derails.
- Time tracking, reports, charts, accounts, sync.
- Cross-platform. This is a Mac app and uses Mac-only APIs on purpose.
- A website or a backend. There is no network code at all.

## The rules of the railway

These are the product. Everything else serves them.

1. **One app, one train.** A train belongs to the app that was frontmost
   when it left the station. `Session.app` is a bundle identifier.
2. **A car couples every N minutes** (default 5, configurable 1–30). Car
   kinds cycle for variety; every sixth car (each half hour) is gold.
3. **Switching apps derails the train**, but only after a grace period
   (default 5 s, configurable 0–15 s). Come back inside the grace and the
   train wobbles instead: a *near miss*. While you are away the train
   brakes (track and smoke freeze) so you can see the clock is ticking.
4. **A notification banner derails the train.** Detection uses the
   Accessibility API to watch Notification Center's windows. It needs the
   Accessibility permission; without it the rule is simply off and the menu
   says so. Turning on a macOS Focus suppresses banners, so Focus plus Train
   of Thought means only *you* can derail it.
5. **Some apps are passengers, not destinations.** Spotlight, Raycast,
   Alfred, 1Password, system security prompts, Control Center and Train of
   Thought's own windows never derail anything. You can add your own
   *crew*: apps that ride along with the train (for example a terminal
   alongside your editor).
6. **Stepping away is not a derail.** Lock screen, sleep, screensaver or
   ten minutes without input *parks the train at the station*. Come back
   to the same app and it departs again with all its cars. Come back to a
   different app and the old train is retired cleanly (it still counts) and
   a new one leaves. Nothing is wrecked because nothing was moving.
7. **Pause means pause.** From the menu bar you can pause; the overlay hides
   and nothing can derail.

## Architecture

Two Swift targets, no dependencies.

```
Sources/
  TrainCore/           pure Swift, no AppKit. Tested.
    Engine.swift       state machine: events in, effects out
    Rules.swift        passengers, grace, car kinds, milestones
    Stats.swift        runs, best run, totals; Codable
    ShareText.swift    the emoji train for the clipboard
  TrainOfThought/      the app
    App.swift          NSApplication bootstrap, AppDelegate, wiring
    Overlay/           NSPanel + Core Animation scene + pixel sprites
    Sensors/           focus (NSWorkspace), notifications (AX), idle, sleep/lock
    MenuBar/           status item and menu
    Settings/          SwiftUI settings window, Preferences (UserDefaults)
    Audio/             synthesized 8-bit toot (no audio files)
Tests/TrainCoreTests/  XCTest for the core
```

### Engine

`Engine` is a value-type state machine. The app feeds it events with a
timestamp; it returns effects. It never reads the clock, never touches
AppKit, and is fully deterministic, which is what makes the rules testable.

```
enum Event  { appActivated(App), notification, tick, pause, resume,
              stationArrive(reason), stationDepart(App) }
enum Effect { sessionStarted(App), carAdded(Car), derailed(Wreck),
              nearMiss, braking(toward: App), brakesReleased,
              parked(Run), retired(Run), paused, resumed }
```

States: `idle` (paused or nothing frontmost), `running(Session, pending:
PendingDerail?)`, `parked(Session, reason)`.

Cars are added on `tick`, based on `now - session.lastCarAt >= interval`.
Ticks come once a second from the app, so a car is at most a second late.
Only one car per tick: if the Mac was asleep without the engine being told,
cars do not pile up.

### Sensors

- **FocusSensor**: `NSWorkspace.didActivateApplicationNotification`.
  Emits `appActivated`. Also emits the current frontmost app at startup.
- **NotificationSensor**: finds the `com.apple.notificationcenterui`
  process, attaches an `AXObserver` for `kAXWindowCreated`, and also polls
  the window count once a second as a fallback (AX notifications on this
  process are not perfectly reliable). Emits `notification` when the count
  goes from zero to non-zero. Requires `AXIsProcessTrusted()`.
- **IdleSensor**: `CGEventSource.secondsSinceLastEventType` once a second.
  Emits `stationArrive(.idle)` after the threshold and `stationDepart` on
  the next input.
- **PowerSensor**: `NSWorkspace` sleep/wake, screens-sleep, and the
  distributed notifications `com.apple.screenIsLocked` /
  `com.apple.screenIsUnlocked` for the lock screen.

### Overlay

A borderless, non-activating `NSPanel` the full width of the main screen,
64 pt tall, sitting on `visibleFrame.minY` so it rides just above the Dock.
`ignoresMouseEvents`, joins all Spaces, shows over full-screen apps,
`.statusBar` level. It has no text.

The scene is Core Animation, not SwiftUI, on purpose: a looping
`CAKeyframeAnimation` for wheels and track, a `CAEmitterLayer` for smoke,
spring animations for coupling, keyframe groups for the wreck. Once set up,
animations run on the render server and the app's CPU time is roughly zero.

Sprites are ASCII art in `Sprites.swift`, one character per pixel, rendered
to `CGImage` at 3× with nearest-neighbour scaling. Adding a car kind is a
new string array and one line in the palette; that is the main
contribution path.

Layout: the locomotive leads on the right, cars trail to the left. The
train grows to the right as cars couple, until the locomotive reaches the
right margin, after which the tail runs off the left edge. The menu bar
always shows the true count.

### Menu bar

A status item with a train glyph and the car count. Menu: current run,
best run, *Copy train*, Pause/Resume, Show train on screen, Settings,
GitHub, Quit.

*Copy train* puts this on the clipboard:

```
🚂🚃🚃🚃🚃🚃🚃🚃  7 cars · 35 min in Xcode
https://github.com/vsahasi/train-of-thought
```

### Persistence

`Preferences` wraps `UserDefaults`. `Stats` is JSON at
`~/Library/Application Support/Train of Thought/stats.json`: best run,
totals, and the last 500 runs. Nothing leaves the machine.

### Build

Swift Package Manager, macOS 13+, Swift 5.8 syntax. `swift build` and
`swift test` with Xcode; `make` uses `swiftc` directly for machines with
only Command Line Tools. `Scripts/bundle.sh` assembles the `.app`, with the
icon generated from the locomotive sprite. GitHub Actions builds on every
push and attaches a zip to tagged releases. The app is unsigned; the README
explains the right-click-Open dance.

## Decisions worth recording

- **Grace period defaults to 5 s, not 0.** Forest-style strictness works
  on a phone where switching is deliberate. On a Mac, ⌘-Tab misfires are
  constant. A near-miss wobble keeps the tension without the rage-quit.
- **Station, not derail, for lock/sleep/idle.** A derail should be
  something you *did*. Walking to a meeting is not that.
- **Switching at the station retires the train silently.** The alternative
  (derail on return) punished people for stepping away.
- **Notification detection is best-effort and off without permission.** No
  Full Disk Access, no reading the notification database.
- **The overlay has no words.** The train is the message.
- **No SwiftUI in the overlay.** A `TimelineView` at 60 fps for an
  always-on overlay costs real CPU and battery. Core Animation costs none.
- **Sound is off by default** and synthesized at runtime so the repo ships
  no binary assets.

## Left out, deliberately

Streaks, daily goals, charts, a website, Homebrew tap (until there is a
signed build), per-window tracking, URL/tab-level tracking in browsers,
multi-monitor trains, iOS.
