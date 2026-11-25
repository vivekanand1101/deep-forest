# Deep Forest

Deep Forest is a private, Apple-native deep-work tracker for macOS and iOS. Completed focus sessions grow a weekly forest, while profiles, lead measures, Daily Plan blocks, and a Planning Inbox help turn intentions into scheduled work.

## Features

- Native SwiftUI apps for macOS and iOS 17+
- Persistent countdown timer that survives relaunches
- Work and Study profiles with configurable durations and weekly goals
- Manual session logging, partial-session logging, and distraction tracking
- Daily depth cap and end-of-day shutdown ritual
- Daily Plan with reusable block types, custom blocks, ordering, completion undo, and notes
- Global Planning Inbox with editable Markdown, clickable links, and formatted previews
- Weekly procedural forest and archive views
- Lead-measure counters stored as append-only events
- JSON backup and restore
- macOS menu-bar timer controls
- iOS WidgetKit target

## Requirements

- macOS 14 or later for the macOS app
- iOS 17 or later for the iOS app
- Xcode 15 or later
- [Homebrew](https://brew.sh/) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

The project currently uses Swift 5.9 language mode and SwiftData. It has also been built successfully with Xcode 26.3.

## Quick start

### 1. Clone the repository

```bash
git clone git@github.com:vivekanand1101/deep-forest.git
cd deep-forest
```

### 2. Install XcodeGen

```bash
brew install xcodegen
```

### 3. Generate the Xcode project

```bash
xcodegen generate
```

`DeepForest.xcodeproj` is generated from `project.yml` and is intentionally not committed.

### 4. Open the project

```bash
open DeepForest.xcodeproj
```

### 5. Run an app target

In Xcode, select one of these schemes:

- `DeepForest-macOS`
- `DeepForest-iOS`

Choose a compatible Mac, iPhone, or iOS Simulator destination and press **Run**.

## Signing and bundle identifiers

Simulator and unsigned macOS builds do not require an Apple Developer account. Running on a physical iPhone or producing a signed distribution build does.

For signed builds:

1. Open the generated project in Xcode.
2. Select each target under **Signing & Capabilities**.
3. Choose your Apple development team.
4. If the existing identifiers are unavailable, replace the bundle identifiers in `project.yml`:
   - `com.vivek.deepforest`
   - `com.vivek.deepforest.mac`
   - `com.vivek.deepforest.widget`
5. Run `xcodegen generate` again after changing `project.yml`.

The current entitlements are intentionally empty. CloudKit and App Group synchronization are not required to run the main apps. SwiftData is local-only in the current implementation.

## Command-line builds

Generate the project before running these commands.

### macOS

```bash
xcodebuild \
  -project DeepForest.xcodeproj \
  -scheme DeepForest-macOS \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### iOS Simulator

```bash
xcodebuild \
  -project DeepForest.xcodeproj \
  -scheme DeepForest-iOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Data storage

Deep Forest uses SwiftData with an explicit local store.

On macOS, the database is stored at:

```text
~/Library/Application Support/DeepForest/DeepForest.store
```

The app does not commit or upload this data to the repository. Use **Settings → Export Backup** before deleting the app data or making destructive local changes.

To reset local macOS data during development, quit Deep Forest and remove the `DeepForest` application-support directory:

```bash
rm -rf "$HOME/Library/Application Support/DeepForest"
```

This permanently deletes local sessions, profiles, plans, and inbox items unless they were exported first.

## Sharing with friends

Personal data is not stored inside the app bundle or repository. Every installation creates its own local SwiftData store and starts with generic defaults.

Create a clean macOS ZIP with:

```bash
./scripts/package-macos.sh 1.0.0
```

See [DISTRIBUTION.md](DISTRIBUTION.md) for data-separation guarantees, friend installation instructions, Gatekeeper details, GitHub sharing options, and production signing/notarization guidance.

## Backups

The current JSON backup format is version 4 and includes:

- Profiles and lead measures
- Deep-work sessions
- Daily Plan block types and blocks
- Daily notes
- Planning Inbox items

Backup versions 2 and 3 remain importable. Version 1 is not supported.

## Project structure

```text
DeepForestApp/       Main macOS and iOS SwiftUI application
DeepForestWidget/    iOS WidgetKit extension
Shared/Models/       SwiftData models
Shared/Store/        Statistics, backup, and widget snapshot helpers
Shared/Views/        Shared forest rendering
project.yml          XcodeGen source of truth
scripts/              Clean distribution packaging tools
DISTRIBUTION.md       Sharing, privacy, signing, and installation guide
```

## Development workflow

After adding files, targets, capabilities, or build settings:

1. Update `project.yml`.
2. Regenerate the project:

   ```bash
   xcodegen generate
   ```

3. Build both app schemes before pushing changes.

Do not edit `DeepForest.xcodeproj/project.pbxproj` directly because the generated project can be replaced at any time.

## Troubleshooting

### Xcode cannot find a scheme

Regenerate the project:

```bash
rm -rf DeepForest.xcodeproj
xcodegen generate
```

### Signing fails

Choose a development team and use bundle identifiers owned by that team. For simulator-only builds, use `CODE_SIGNING_ALLOWED=NO` as shown above.

### The app cannot open its SwiftData store

Quit all Deep Forest processes and restore a backup. During development, you can reset the local store using the command in the **Data storage** section.

### XcodeGen is not found

```bash
brew install xcodegen
```

Then verify:

```bash
xcodegen --version
```

## Privacy

Deep Forest does not include an account system or analytics SDK. The current persistence implementation stores data locally on the device. Cloud synchronization is not enabled.
