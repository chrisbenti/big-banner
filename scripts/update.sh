#!/bin/bash
# Update the installed big-banner to the latest origin/main.
set -euo pipefail

cd "$(dirname "$0")/.."

die() { echo "$*" >&2; exit 1; }

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || die "On branch '$branch', not main. Switch to main first."
[ -z "$(git status --porcelain)" ] || die "Working tree is dirty. Commit or stash first."

git fetch origin main --quiet

ahead=$(git rev-list --count origin/main..main)
[ "$ahead" -eq 0 ] || die "Local main is $ahead commit(s) ahead of origin/main. Push first."

remote=$(git rev-parse origin/main)
bin=$(command -v big-banner || true)
[ -n "$bin" ] || bin="$HOME/bin/big-banner"

installed=""
if [ -x "$bin" ]; then
  installed=$("$bin" --hash 2>/dev/null || true)
fi

if [ "$installed" = "$remote" ]; then
  echo "Already up to date ($remote)."
  exit 0
fi

echo "Installed: ${installed:-none}"
echo "Latest:    $remote"

# A symlinked install means soft-install; a copied binary means hard-install.
if [ -L "$bin" ] || [ ! -e "$bin" ]; then
  target=soft-install
else
  target=hard-install
fi

read -r -p "Update with 'make $target'? [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "Not updating."; exit 0 ;;
esac

git merge --ff-only origin/main
make "$target"
echo "Now at: $("$bin" --hash)"
