#!/bin/bash
# Update the installed big-banner to the latest origin/main.
# Usage: update.sh [-f]   (-f skips the confirmation prompt)
set -euo pipefail

force=0
[ "${1:-}" = "-f" ] && force=1

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

# Builds from before --hash existed would treat it as message text and open a
# banner, so check --help first and assume such builds are behind main.
installed=""
if [ -x "$bin" ] && "$bin" --help 2>/dev/null | grep -q -- '--hash'; then
  installed=$("$bin" --hash)
fi

if [ "$installed" = "$remote" ]; then
  echo "Already up to date ($remote)."
  exit 0
fi

base=${installed%\*}
if [ -z "$installed" ]; then
  echo "Your build is out of date (it predates --hash)."
elif git cat-file -e "$base^{commit}" 2>/dev/null; then
  behind=$(git rev-list --count "$base..origin/main")
  if [ "$behind" -gt 0 ]; then
    echo "Your build is $behind commit(s) behind origin/main."
  else
    echo "Your build differs from origin/main."
  fi
  [ "$base" = "$installed" ] || echo "(it was built from a dirty tree)"
else
  echo "Your build is from an unknown commit."
fi
echo "Installed: ${installed:-unknown}"
echo "Latest:    $remote"

# A symlinked install means soft-install; a copied binary means hard-install.
if [ -L "$bin" ] || [ ! -e "$bin" ]; then
  target=soft-install
else
  target=hard-install
fi

if [ "$force" -eq 1 ]; then
  echo "Updating with 'make $target' (-f)."
else
  read -r -p "Update with 'make $target'? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Not updating."; exit 0 ;;
  esac
fi

git merge --ff-only origin/main
make "$target"
echo "Now at: $("$bin" --hash)"
