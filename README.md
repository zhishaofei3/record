# Record

Record is a native macOS camera recorder built with SwiftUI and AVFoundation. It captures camera video and microphone audio, supports camera and microphone selection, offers `720p`, `1080p`, and `4K` presets with downgrade feedback, and exports `mp4` files.

## Features

- Native macOS SwiftUI desktop app
- Live camera preview during recording
- Camera and microphone device selection before recording
- Resolution presets: `720p`, `1080p`, `4K`
- `mp4` export with save path selection after recording stops
- Automatic Finder reveal after export completes

## Project Layout

- `Package.swift`: Swift Package entry point for `RecordCore` and `RecordApp`
- `Sources/RecordCore`: capture engine and recording domain contracts
- `Sources/RecordApp`: SwiftUI app shell and workspace UI
- `Tests/RecordCoreTests`: focused tests for resolution fallback and state transitions
- `scripts/generate_xcodeproj.rb`: regenerates the Xcode project

## Requirements

- macOS 14+
- Xcode 26.2+
- Swift 6.2+

## Run With Swift Package Manager

```bash
swift build
swift run RecordApp
```

## Run With Xcode

1. Regenerate the Xcode project if needed:

   ```bash
   ruby scripts/generate_xcodeproj.rb
   ```

2. Open `Record.xcodeproj`.
3. Select the `Record` scheme.
4. For local development, use the default Debug signing configuration, which is set up for local ad hoc signing.
5. Build and run on macOS. The app will request camera and microphone access on first launch.

## Signing Notes

- Debug builds use local signing so the app can run without a Developer ID certificate.
- Release builds expose `DEVELOPMENT_TEAM` and bundle settings in the Xcode project for later notarized distribution.
- This repository does not currently ship a notarization pipeline or App Store packaging flow.

## Verification Status

- `swift test` passes locally.
- `xcodebuild` validation is included in the development workflow.
- Real camera, export, and virtual-background verification still depend on running the app on a macOS machine with accessible camera and microphone hardware.
