# Contributing

Thanks for wanting to help. Issues and pull requests are both welcome.

## Getting set up

You only need the Xcode command-line tools (`xcode-select --install`).

```bash
git clone https://github.com/mohammaddanyal/dott-tap.git
cd dott-tap
./scripts/setup-signing.sh   # once: local signing so Accessibility survives rebuilds
./scripts/build-app.sh       # builds dist/Dott Tap.app and a DMG
```

The first release build can take several minutes. `swift build` (debug) is quicker
while you work.

## Where things live

| Folder | What's in it |
| --- | --- |
| `Sources/DottTap/Sensor` | Reading the motion sensor through IOKit HID |
| `Sources/DottTap/Detection` | Knock detection, screen/desk/palm classifier, gesture grouping |
| `Sources/DottTap/Engine` | Wiring, power policy, trackpad mode, phone remote |
| `Sources/DottTap/Actions` | Everything a knock can do |
| `Sources/DottTap/Effects` | On-screen reactions and the confirmation pill |
| `Sources/DottTap/UI` | Menu bar and settings window (SwiftUI) |

## Good first contributions

- Try it on your MacBook model and open a "Works on my Mac" issue.
- New actions: add a case to `ActionKind` and handle it in `ActionRunner`.
- New reactions in `Effects/Reactions.swift`.
- Translations of the settings window.

Please keep the sensor path cheap: no allocations or locks per sample in
`KnockDetector.process`, and nothing on the main thread until a knock is found.

`SwiftUI.@State` needs a compiler plugin that only ships with full Xcode, so views use
the small `Box` class with `@StateObject` instead. That keeps the project buildable with
just the command-line tools.
