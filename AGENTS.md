# Agent Instructions

## Commit Style

I prefer functional commits. Each commit should represent a single, cohesive unit of work that makes logical sense independently. Avoid mixing unrelated changes into a single commit.

## Help Message

The `--help` / `-h` flag in `Sources/big-banner/main.swift` prints the canonical usage doc. **Keep it in sync with the actual flags at all times.** Whenever you add, remove, or rename a flag, update the help message in the same commit.
