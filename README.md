<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Freesper icon">
</p>

# Freesper

Dictation for macOS. Speak, and the words appear in the app you're using.

- **Local.** All speech recognition runs on your Mac via NVIDIA Parakeet.
- **Free and open source.** No subscription, no account, no telemetry.
- **Native.** Built in Swift — low memory, quick to launch.

> This is an early personal project. There's no signed release yet, no auto-update, and many things you might expect are missing. If you want to try it, you'll build it yourself.

## Why

I used Whisper Flow for a long time and it was the best dictation experience I'd had. Two things kept frustrating me though: sometimes transcripts failed outright or took 30+ seconds, which defeats the point of dictation; and for longer thoughts the tool would heavily rewrite my text into a cleaner version of what it interpreted me as saying, sometimes losing the original point entirely.

Looking for alternatives, I came across NVIDIA Parakeet — local, near-instant, just transcription. The tradeoff is there's no automatic cleanup of misrecognized words, but I'd rather edit a faithful transcript than argue with a confident rewrite.

At that point cloud dictation stopped making sense to me, especially at $15/month. I tried the existing local apps but kept running into the same things: paywalls for basic features, feature bloat, or designs that just didn't feel cared for.

So Freesper is the smallest app I could build around Parakeet. No subscription, no account, no telemetry. Native Swift so it stays out of the way when idle. Few features on purpose — I'd rather it do one thing well than ten things halfway.

## Building from source

Requirements:

- macOS 14+ on Apple Silicon
- Xcode 26.3+
- [mise](https://mise.jdx.dev/) (`brew install mise`)
- An Apple Developer Team ID (free tier works)

Setup:

```
git clone https://github.com/troytft/freesper.git
cd freesper
make install
echo "TUIST_DEVELOPMENT_TEAM=XXXXXXXXXX" > .env
make dev
```

On first launch the app will ask for Microphone and Accessibility permissions.

## What's next

- Signed releases and auto-update so installing doesn't require Xcode.
- A visible "warming up the model" state on first run after idle.

There's a longer list of things I'm unsure about — sounds, history, dictionary, hands-free mode, statistics. If you have an opinion, open a discussion.

## License

See [LICENSE](LICENSE).
