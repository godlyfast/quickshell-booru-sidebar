#!/usr/bin/env bash
# Regression test for the "danbooru pic lo quality" bug.
#
# Root cause: cdn.donmai.us returns 403 to browser-style (Mozilla/*) User-Agents on
# /original/ (full-res) paths, but 200 to plain/absent UAs. /180x180/ thumbnails are
# unaffected, so the low-res preview always loads while every hi-res upgrade silently
# 403s -> the card stays "low quality". Grabber (and any -A 'Mozilla/...' curl) hits
# this; the fix downloads danbooru hi-res via curl with an EMPTY User-Agent.
#
# This guards the invariant against future regressions (e.g. someone re-adding a
# browser UA to the danbooru hi-res path, or the CDN policy shifting again).
#
# Network test: requires internet + a reachable danbooru. Fetches a live post each
# run so the asserted URL never goes stale. Exit 0 = pass, 1 = regression, 2 = skip.
set -uo pipefail

BROWSER_UA='Mozilla/5.0 BooruSidebar/1.0'   # what Grabber / the old code sent
APP_HIRES_UA=''                              # what the fixed danbooru path sends

echo "[danbooru-hires-ua] fetching a live post..."
J=$(curl -s --max-time 20 "https://danbooru.donmai.us/posts.json?tags=order:rank&limit=1")
FURL=$(printf '%s' "$J" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin)[0]; print(d.get('file_url',''))
except Exception:
    print('')" 2>/dev/null)

if [ -z "$FURL" ] || [[ "$FURL" != *"/original/"* ]]; then
    echo "[danbooru-hires-ua] SKIP: could not obtain an /original/ file_url (network/API issue)"
    exit 2
fi
echo "[danbooru-hires-ua] file_url=$FURL"

code() { curl -4 -s -o /dev/null --max-time 30 -w "%{http_code}" "$@"; }

browser_code=$(code -A "$BROWSER_UA" "$FURL")
app_code=$(code ${APP_HIRES_UA:+-A "$APP_HIRES_UA"} "$FURL")

echo "[danbooru-hires-ua] browser UA -> $browser_code   app hi-res UA -> $app_code"

fail=0
# The fix's invariant: the app's hi-res UA MUST succeed.
if [ "$app_code" != "200" ]; then
    echo "[danbooru-hires-ua] FAIL: app hi-res UA got $app_code (expected 200). Hi-res download is broken."
    fail=1
fi
# Sanity: confirms the 403-on-browser-UA condition that motivated the fix still holds.
# (If danbooru ever stops blocking browser UAs, the fix is harmless but this note flags it.)
if [ "$browser_code" = "200" ]; then
    echo "[danbooru-hires-ua] NOTE: browser UA now also returns 200 (CDN policy relaxed); fix remains safe."
fi

if [ "$fail" -eq 0 ]; then
    echo "[danbooru-hires-ua] PASS"
fi
exit "$fail"
