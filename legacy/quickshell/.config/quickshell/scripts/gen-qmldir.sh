#!/usr/bin/env bash
# Regenerate qmldir files for the Quickshell config.
#
# Why: Quickshell resolves `pragma Singleton` files implicitly at runtime, so the
# bar does NOT need these qmldir files. But the Qt6 QML language server (qmlls6)
# refuses to resolve a singleton's members unless a real qmldir in the *source*
# directory declares it as a singleton — otherwise it floods every consumer with
# false "Member X not found on type Theme" warnings. Quickshell's own .qmlls.ini
# tooling generates these in a VFS using symlinks, but qmlls canonicalizes the
# symlinks back to the source dir and the fix is lost. Real qmldir files in the
# source tree are the only thing that actually works on this toolchain.
#
# Each generated qmldir lists every PascalCase *.qml in its directory as a type,
# prefixing `singleton ` for files that contain `pragma Singleton`. Listing every
# component (not just singletons) is required: once a qmldir exists, the directory
# becomes a strict module and bare-name sibling references would otherwise break
# at runtime ("X is not a type").
#
# Run this after adding/removing/renaming any *.qml component. See AGENTS.md.
#
# Usage: scripts/gen-qmldir.sh [config-root]   (default: the dir containing scripts/)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

generated=0
while IFS= read -r dir; do
  qmldir="$dir/qmldir"
  : > "$qmldir"
  for f in "$dir"/[A-Z]*.qml; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    type="${base%.qml}"
    if grep -q '^pragma Singleton' "$f"; then
      printf 'singleton %s %s\n' "$type" "$base" >> "$qmldir"
    else
      printf '%s %s\n' "$type" "$base" >> "$qmldir"
    fi
  done
  sort -o "$qmldir" "$qmldir"
  generated=$((generated + 1))
  printf 'wrote %s (%s entries)\n' "${qmldir#"$ROOT"/}" "$(wc -l < "$qmldir")"
done < <(find "$ROOT" -type f -name '[A-Z]*.qml' -printf '%h\n' | sort -u)

printf 'Done: %s qmldir file(s) generated.\n' "$generated"
