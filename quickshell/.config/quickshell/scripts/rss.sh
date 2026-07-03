#!/usr/bin/env bash
# RSS news-ticker backend for the quickshell bar.
# Reads feed URLs from rss-feeds.txt (or default list), fetches with curl,
# caches parsed JSON per-feed, and outputs a merged/sorted JSON array of
# recent headlines. Each item: {title, link, source, published}.
set -uo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-rss"
FEED_FILE="$HOME/.config/quickshell/rss-feeds.txt"
TTL=900
NOW=$(date +%s)
mkdir -p "$CACHE_DIR" 2>/dev/null

# Track which cache files belong to the currently-configured feeds, so the
# merge step below ignores stale cache left over from feeds since removed.
EXPECTED_FILE=$(mktemp)
trap 'rm -f "$EXPECTED_FILE"' EXIT

# ─── read feed URLs ─────────────────────────────────────────────────
FEEDS=()
if [ -f "$FEED_FILE" ]; then
  while IFS= read -r line; do
    # Strip inline comments and trim whitespace
    line="${line%%#*}"
    line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$line" ] && FEEDS+=("$line")
  done < "$FEED_FILE"
fi

# Fallback defaults if no feeds configured
if [ ${#FEEDS[@]} -eq 0 ]; then
  FEEDS=(
    "https://itsfoss.com/feed/"
    "https://archlinux.org/feeds/news/"
    "https://www.phoronix.com/rss.php"
    "https://lwn.net/headlines/newrss"
    "https://www.omgubuntu.co.uk/feed"
    "https://www.cyberciti.biz/atom/atom.xml"
    "https://distrowatch.com/news/dw.rdf"
    "https://www.tecmint.com/feed/"
    "https://huggingface.co/blog/feed.xml"
    "https://simonwillison.net/atom/everything/"
    "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"
    "https://feeds.arstechnica.com/arstechnica/features/"
    "http://feeds.bbci.co.uk/news/world/rss.xml"
    "https://www.theguardian.com/world/rss"
    "https://www.aljazeera.com/xml/rss/all.xml"
    "https://rss.dw.com/rdf/rss-en-top"
  )
fi

# ─── ensure each feed is freshly cached (parsed JSON) ────────────────
for URL in "${FEEDS[@]}"; do
  [ -z "$URL" ] && continue
  HASH=$(printf '%s' "$URL" | sha1sum | cut -d' ' -f1)
  CACHE="$CACHE_DIR/$HASH.json"
  printf '%s\n' "$HASH" >> "$EXPECTED_FILE"

  # Check cache freshness
  FRESH=""
  if [ -f "$CACHE" ]; then
    AGE=$(( NOW - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
    [ "$AGE" -lt "$TTL" ] && FRESH=1
  fi

  if [ -z "$FRESH" ]; then
    TMPFILE=$(mktemp)
    if curl -s -m 10 -A "quickshell-rss/1.0" "$URL" > "$TMPFILE" 2>/dev/null; then
      RAW=$(cat "$TMPFILE" 2>/dev/null)
      if [ -n "$RAW" ]; then
        # Parse with feedparser and cache the result as JSON
        PARSED=$(URL="$URL" python3 -c '
import os, sys, json, time, calendar
from io import BytesIO
import feedparser

url = os.environ.get("URL", "")
raw = sys.stdin.buffer.read()
feed = feedparser.parse(BytesIO(raw))
result = {
    "_url": url,
    "_fetched": int(time.time()),
    "title": (feed.feed.get("title") or "").strip(),
    "items": []
}
for entry in feed.entries:
    pub = None
    if entry.get("published_parsed"):
        pub = calendar.timegm(entry.published_parsed)
    elif entry.get("updated_parsed"):
        pub = calendar.timegm(entry.updated_parsed)
    result["items"].append({
        "title": (entry.get("title") or "").strip(),
        "link": entry.get("link", ""),
        "published": pub
    })
json.dump(result, sys.stdout, ensure_ascii=False)
' <<< "$RAW" 2>/dev/null)
        if [ -n "$PARSED" ]; then
          printf '%s' "$PARSED" > "$CACHE"
        fi
      fi
    fi
    rm -f "$TMPFILE"
    # If curl failed and no cache existed, the feed is silently skipped.
  fi
done

# ─── merge all cached feeds, sort, cap, output ───────────────────────
EXPECTED_FILE="$EXPECTED_FILE" python3 << 'PYEOF'
import sys, json, os

cache_dir = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "quickshell-rss"
)

# Only merge cache files for feeds in the current config (handles removed
# feeds whose stale cache would otherwise linger forever).
expected = set()
expected_file = os.environ.get("EXPECTED_FILE", "")
if expected_file:
    try:
        with open(expected_file) as f:
            for line in f:
                line = line.strip()
                if line:
                    expected.add(line + ".json")
    except Exception:
        pass

all_items = []
seen = set()

try:
    entries = sorted(os.listdir(cache_dir))
except FileNotFoundError:
    entries = []

for fname in entries:
    if not fname.endswith(".json"):
        continue
    if expected and fname not in expected:
        continue
    path = os.path.join(cache_dir, fname)
    if not os.path.isfile(path):
        continue
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except Exception:
        continue

    source = (data.get("title") or "").strip()
    if not source:
        url = data.get("_url", "") or ""
        if "//" in url:
            source = url.split("/")[2]  # hostname fallback

    for item in data.get("items", []):
        title = (item.get("title") or "").strip()
        if not title:
            continue
        link = item.get("link") or ""
        key = title + "|" + link
        if key in seen:
            continue
        seen.add(key)
        all_items.append({
            "title": title,
            "link": link,
            "source": source,
            "published": item.get("published")
        })

# Newest-first; None/Null published sorts last.
all_items.sort(key=lambda x: (
    x["published"] is None,
    -(x["published"] or 0) if x["published"] else 0
))
all_items = all_items[:30]

json.dump(all_items, sys.stdout, ensure_ascii=False)
sys.stdout.write("\n")
PYEOF
