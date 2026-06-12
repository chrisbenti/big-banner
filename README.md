# big-banner

Fullscreen attention banner for macOS. Plays a sound, dims the screen, shows your message in giant text. Click or press Escape to dismiss.

```
big-banner "STAND UP"
big-banner --no-sheet "DRINK WATER"   # floating banner only, no dim
big-banner --no-bell "meeting soon"   # no sound
big-banner --no-pause "heads up"      # don't pause media
```

## Install

```
make hard-install   # copies binary to ~/bin
```

---

## How media pausing works

By default, big-banner pauses whatever is playing when it opens, then resumes it when you dismiss. Disable with `--no-pause`.

### The detection problem

The obvious API — MediaRemote's `MRMediaRemoteGetNowPlayingInfo` / `…IsPlaying` — has been blocked for unsigned apps since macOS 15.4. This is an **entitlement restriction**, not a code-signing issue. The `com.apple.mediaremote.*` entitlements are provisioned by Apple and cannot be self-assigned. A Developer ID cert doesn't help.

### The solution: CoreAudio `DeviceIsRunningSomewhere`

Instead, we ask CoreAudio: "is any process actively sending audio to the default output device?" This is a public API with no entitlements, no TCC permission prompt, and no signing required:

```swift
kAudioDevicePropertyDeviceIsRunningSomewhere  // UInt32: 0 = silent, 1 = audio flowing
```

It answers the only question we actually need: **is something playing?** (Not what, not which app — just whether.)

One caveat: a muted video reads as not-playing. For this use case that's fine.

### The control: MediaRemote send-command

CoreAudio can detect audio but can't control the source app. To actually pause/resume, we use `MRMediaRemoteSendCommand` with `kMRPause`/`kMRPlay`. The send path was not restricted along with the read path and works universally — Music, Spotify, browser video, podcasts, anything.

We load it via `dlopen`/`dlsym` rather than linking directly to avoid a hard dependency on a private framework.

### The gate: `didPause`

```
open:    isAudioPlaying()? → send pause → set didPause = true
close:   didPause? → send play → reset didPause
```

Resume is strictly gated on `didPause`. If nothing was playing when the banner opened, closing it does nothing. No toggle desync, no starting something that wasn't already running.
