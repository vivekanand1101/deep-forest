# Distributing Deep Forest

Deep Forest keeps application code and personal data separate. A copied `.app` bundle does not contain the sessions, plans, profiles, notes, or Planning Inbox items from the machine that built it.

## Data separation

On macOS, runtime data is stored per user at:

```text
~/Library/Application Support/DeepForest/DeepForest.store
```

This location is outside `DeepForest.app` and outside the Git repository.

Each friend who opens Deep Forest gets a new local database containing only the generic first-launch defaults:

- Work profile
- Study profile
- Generic starter lead measures

The following are not bundled or shared:

- Focus sessions and timer history
- Daily Plan blocks and notes
- Planning Inbox items
- Custom profiles or lead measures
- Exported JSON backups
- Settings from the build machine

Cloud synchronization is currently disabled, so different installations do not exchange data.

## Create a clean macOS archive

From the repository root:

```bash
./scripts/package-macos.sh 1.0.0
```

The script:

1. Regenerates the Xcode project from `project.yml`.
2. Creates a Release build for Apple Silicon and Intel Macs.
3. Copies only the application bundle into a staging directory.
4. Applies an ad-hoc signature with a complete resource seal.
5. Refuses to package the app if database-like runtime files are found inside it.
6. Creates `dist/DeepForest-1.0.0-macOS.zip`.
7. Prints the archive SHA-256 checksum and included architectures.

The `dist/` directory is ignored by Git.

## Installation instructions for friends

1. Download and unzip `DeepForest-1.0.0-macOS.zip`.
2. Drag `DeepForest.app` into `/Applications`.
3. On first launch, Control-click or right-click the app and choose **Open**.
4. Confirm **Open** in the macOS security prompt.

This build is ad-hoc signed, not notarized with an Apple Developer ID. Gatekeeper may therefore reject a normal double-click on first launch.

If macOS still blocks the app, and the archive came directly from a trusted sender, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/DeepForest.app
```

Then open the app again.

## GitHub distribution choices

The GitHub repository is currently private. To share through GitHub, either:

- Add each friend as a repository collaborator; or
- Make the repository public after confirming that source-code visibility is acceptable.

A GitHub Release can contain the clean ZIP produced by the packaging script. Repository visibility controls who can access releases.

## Signed and notarized distribution

For a standard double-click installation without Gatekeeper workarounds, use a paid Apple Developer account and:

1. Sign the Release build with a Developer ID Application certificate.
2. Submit the archive to Apple notarization.
3. Staple the notarization ticket to the app.
4. Recreate the ZIP and publish it.

Do not use the ad-hoc signing step in `scripts/package-macos.sh` for a Developer ID release; replace it with your production signing and notarization workflow.

## Never distribute these files

Do not send or upload:

```text
~/Library/Application Support/DeepForest/
```

Do not include exported backup JSON files unless they are intentionally being transferred to the same data owner.
