# MustRest

A macOS pomodoro / break reminder app.

## Language

- [中文版 / Chinese](README-cn.md)

## Features

1. Reminds the user to take a break.
2. The overlay is full screen by default with background color `#B98278`. When the switch is on ("Full Screen Overlay") early exit is not allowed and the user must wait for the timer to finish; when off ("Allow Exit"), the "Exit" button in the overlay can end the current task early.
3. The overlay reminder shows the task name by default, e.g. "Eye Rest".
4. Default tasks:
   - Eye Rest: work 20 minutes, then 15 seconds of break.
   - Standing Break: work 1 hour, then 5 minutes of standing.
   - Exercise: work 2 hours, then 10 minutes of exercise.
5. These defaults can be customized in Settings.

6. On launch the app automatically starts the countdown; no need to manually click "Start" in the menu bar.

7. An "Auto Launch at Boot" switch is available in Settings: when enabled, the app launches automatically at computer boot and automatically starts the tasks.

8. Multiple tasks can run countdowns / breaks in parallel.

## Build

The project uses Swift Package Manager. System requirement: macOS 15 or later.

```bash
swift build
swift run MustRestApp
```

## Tests

```bash
swift test
```

## Project Structure

- `Sources/MustRest` - Core logic (tasks, timer engine, settings).
- `Sources/MustRestApp` - macOS app UI (menu bar, overlay reminder window, settings window).
- `Tests/MustRestTests` - Unit tests.

