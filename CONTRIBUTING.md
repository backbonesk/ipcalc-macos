# Contributing to IP Calc

Thanks for helping out! Bug reports, feature ideas and pull requests are all welcome.

## Reporting bugs and requesting features

Please use [GitHub issues](https://github.com/backbonesk/ipcalc-macos/issues). For bugs, include:

- the input you typed and what you expected to see
- your macOS version and the IP Calc version (select IP Calc in Finder → File → Get Info)

For calculation bugs, the exact input is usually all we need.

## Pull requests

- For larger changes, open an issue first so we can agree on the approach.
- Keep pull requests focused on one change.
- Add or update tests in `IPCalcKit/Tests` for anything that changes calculations or parsing,
  and make sure `swift test` passes.
- Match the style of the surrounding code.

## Building from source

Requirements: macOS 26, Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
cd IPCalcKit && swift test        # calculator logic and tests (no Xcode project needed)
xcodegen generate                 # creates IPCalc.xcodeproj from project.yml (not committed)
open IPCalc.xcodeproj             # build and run the "IPCalc" scheme
```

Or build and install from the command line:

```sh
scripts/release.sh                # runs the tests and builds into build/
scripts/install.sh                # installs that build into ~/Applications and starts it
```

Local builds are ad-hoc signed. Everything works in them except the Spotlight action: macOS only runs
App Intents from apps signed with an Apple Developer Team ID (it logs *"Unable to get teamId …
requiresValidatedBundle"*, and Spotlight shows *LinkDaemon.ProcessRegistry.Errors error 0*). To test
the action, build with your own team: `DEVELOPMENT_TEAM=<your team ID> scripts/release.sh`.

## Code layout

- `IPCalcKit/`: Swift package with the parsing and calculations. It builds a report that is
  structured for the UI and also renders as plain text. Fully covered by tests.
- `App/`:
  - `IPCalcApp.swift`: agent app (no Dock icon), menu bar icon and the non-activating floating panel
  - `HotKey.swift`: the global shortcut, using Carbon `RegisterEventHotKey` (works in the sandbox and
    needs no Accessibility permission)
  - `ContentView.swift`, `SearchField.swift`, `ReportView.swift`: the panel UI
  - `SettingsView.swift`, `Appearance.swift`: the Settings window and visual settings
  - `Intents.swift`: the Spotlight action
- `scripts/`: build, release and install scripts, and the app icon generator (`make-icon.swift`)
- `packaging/ip-calc.rb`: Homebrew cask template

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
