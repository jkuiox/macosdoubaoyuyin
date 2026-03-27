# Repository Guidelines

## Project Structure & Module Organization
`yapyap/Sources/` contains all app logic for the macOS menu bar client: app startup, settings UI, audio capture, ASR networking, text injection, and overlay UI. `yapyap/Resources/` holds `Info.plist` and entitlements. `scripts/` contains local build helpers, `images/` stores README assets, and `project.yml` is the XcodeGen source of truth for the generated `yapyap.xcodeproj`.

## Build, Test, and Development Commands
Use `xcodegen generate -q` after changing `project.yml` to refresh the Xcode project. Use `open yapyap.xcodeproj` for local development in Xcode. Use `bash scripts/rebuild-and-open.sh` after code changes to rebuild, restart the app, and verify it launches. Use `bash scripts/bundle.sh` to produce a Release app bundle in `build/`; this script also runs `codesign`, so contributors may need to adjust the signing identity for their machine.

## Coding Style & Naming Conventions
Follow the existing Swift style: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for methods, properties, and enum cases. Keep files focused on one responsibility, matching the current module split such as `AudioEngine.swift` or `TextProcessor.swift`. Prefer native Apple frameworks over new dependencies. When adding user-facing copy, update the bilingual `L10n` definitions in `yapyap/Sources/SettingsStore.swift`.

## Testing Guidelines
There is no checked-in XCTest target yet, so manual verification is required. At minimum, smoke-test startup permissions, menu bar behavior, `fn` press-to-record flow, text insertion, and any changed settings. If you add automated tests, place them in a new `yapyapTests/` target and use names like `TextProcessorTests.swift`.

## Commit & Pull Request Guidelines
Recent history mixes short Chinese summaries with conventional prefixes like `fix:` and `refactor:`. Keep commit messages brief, imperative, and scoped to one change. Pull requests should describe the user-visible behavior change, list local verification steps, and include screenshots for settings or overlay UI changes. Call out any changes to permissions, entitlements, signing, or ASR configuration explicitly.

## Security & Configuration Tips
Do not commit real App Key or Access Key values. Keep machine-specific notes in ignored local files such as `*.local.md`, and avoid checking in generated `build/` output or Xcode user data.
