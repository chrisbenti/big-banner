# big-banner

Fullscreen attention banner for macOS. Plays a sound, dims the screen, shows your message in giant text. Click or press Escape to dismiss.

```
big-banner "STAND UP"
big-banner --no-sheet "DRINK WATER"   # floating banner only, no dim
big-banner --no-bell "meeting soon"   # no sound
big-banner --super "BUILD FAILED" --sub "main @ c85d485" "DEPLOY BLOCKED"   # optional smaller lines above/below
big-banner --danger "PROD IS DOWN"   # themes: --primary (default), --secondary, --tertiary, --danger, --monochrome
big-banner --no-pause "heads up"      # don't pause media
```

## Install

Make sure ~/bin is on your path

```
make hard-install   # copies binary to ~/bin
# OR
make soft-install   # sym-links binary from build dir
```

### Download a prebuilt binary

Every push to `main` publishes a fresh binary to the `latest` release. Since the repo is public, no auth is needed:

```
mkdir -p ~/bin
curl -L https://github.com/chrisbenti/big-banner/releases/latest/download/big-banner -o ~/bin/big-banner

chmod +x ~/bin/big-banner
xattr -d com.apple.quarantine ~/bin/big-banner   # unquarantine, since it's unsigned
```

Or from the GitHub UI:

1. Go to the [latest release](https://github.com/chrisbenti/big-banner/releases/latest).
2. Under **Assets**, click `big-banner` to download it.
3. Move it into `~/bin` and make it executable:
   ```
   mkdir -p ~/bin
   mv ~/Downloads/big-banner ~/bin/big-banner
   chmod +x ~/bin/big-banner
   ```
4. Remove the quarantine flag, since the binary is unsigned (otherwise Gatekeeper will refuse to run it):
   ```
   xattr -d com.apple.quarantine ~/bin/big-banner
   ```

Make sure `~/bin` is on your `PATH` (e.g. `export PATH="$HOME/bin:$PATH"` in your `.zshrc`/`.bashrc`), then run it as `big-banner`.

## Claude Code integration

Claude Code [hooks](https://docs.claude.com/en/docs/claude-code/hooks) can fire a banner whenever Claude needs you (`Notification`) or finishes (`Stop`). The `--super`/`--sub` headers and themes make it easy to tell, at a glance, *which* session is talking and *what kind* of event it is:

- **Colors** distinguish the event. For example, `--secondary` for "needs your input" and `--primary` for "done" (or `--danger` for anything you really can't miss).
- **`--super`** carries the notification title.
- **`--sub`** carries the working directory, so you know which project is asking when you have several sessions open.
- **The main text** carries the message itself.

Hooks receive a JSON payload on stdin, so `jq` pulls out the pieces. Add these to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "in=$(cat); msg=$(jq -r '.message // \"Claude needs your input\"' <<<\"$in\"); title=$(jq -r '.title // empty' <<<\"$in\"); cwd=$(jq -r --arg h \"$HOME\" '.cwd // empty | if startswith($h) then \"~\" + .[($h|length):] else . end' <<<\"$in\"); big-banner --secondary --super \"$title\" --sub \"$cwd\" \"$msg\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "in=$(cat); title=$(jq -r '.title // empty' <<<\"$in\"); cwd=$(jq -r --arg h \"$HOME\" '.cwd // empty | if startswith($h) then \"~\" + .[($h|length):] else . end' <<<\"$in\"); big-banner --primary --super \"$title\" --sub \"$cwd\" \"Claude is done\""
          }
        ]
      }
    ]
  }
}
```

What the shell is doing:

- `in=$(cat)` reads the hook payload once so it can be queried several times.
- `.message` and `.title` come straight from the notification; the message falls back to a default if it's missing.
- The `cwd` filter swaps your home directory for `~` so the sub header stays short.

If you'd rather keep it minimal, the simplest version is just a message and a color:

```json
{ "type": "command", "command": "big-banner --secondary \"Claude needs your input\"" }
```

Swap in `--danger`, `--tertiary`, or `--monochrome` to give other events (e.g. a `PostToolUse` hook on a failing command) their own look.

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
