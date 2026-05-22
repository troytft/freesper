# Freesper

## Preview build for a tester

A preview build is **not a release**: it is not notarized by Apple and is
signed ad-hoc. It is only good for handing the app to someone you know so
they can test it.

Build:

```
make preview-build
```

The resulting archive is `dist/Freesper.zip`. That is what you send to the
tester.

### What the tester needs to do

Since the build is not notarized, macOS will block it on first launch —
this is expected.

1. Unpack `Freesper.zip` and move `Freesper.app` to Applications.
2. Remove the quarantine attribute — run in Terminal:

   ```
   xattr -cr /Applications/Freesper.app
   ```

   After that the app opens with a regular double click.

If you skip step 2, macOS will show "cannot be opened because the developer
cannot be verified". In that case: **System Settings → Privacy & Security**,
scroll down to the message about Freesper and click **"Open Anyway"**.

### Microphone access

On first use Freesper will request microphone access — you need to allow it.
To check or grant it manually: **System Settings → Privacy & Security →
Microphone**.

Each new preview build has a new ad-hoc signature, so **after updating the
app macOS may reset the microphone permission** — in that case you need to
grant it again in the same settings section.

### First launch

On first launch Freesper downloads speech recognition models — an internet
connection is required, and the download may take a while.

### Requirements

- macOS 14.0 or newer
- Apple Silicon Mac (M1 and newer)
