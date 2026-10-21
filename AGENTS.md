# Agent Instructions

## Commit Style

I prefer functional commits. Each commit should represent a single, cohesive unit of work that makes logical sense independently. Avoid mixing unrelated changes into a single commit.

## Help Message

The `--help` / `-h` flag in `Sources/big-banner/main.swift` prints the canonical usage doc. **Keep it in sync with the actual flags at all times.** Whenever you add, remove, or rename a flag, update the help message in the same commit.

## Showing Your Work

After any change that affects how the banner looks (sizing, layout, themes, fonts), show it off rather than just reporting that it builds:

1. Run `make soft-install` so `~/bin/big-banner` points at a fresh release build.
2. Run `big-banner` once, after relinking, with lorem ipsum in every area (`--super`, `--sub`, and the main message) so the user can judge sizing and truncation. Run it in the background; it exits when the user presses a key.

## Main Text Size and Truncation

The main message is sized to fill the space left by the super/sub headers, but **must never go below 18pt**. If the text still doesn't fit at 18pt, don't shrink further: cap the number of lines to what fits and truncate with a trailing ellipsis (`.byTruncatingTail`). Super/sub headers stay independent of the main text size.
