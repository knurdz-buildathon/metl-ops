#!/usr/bin/env bash
# Diagnostic: inspect what CSS the metl-frontend container is actually shipping.
# Emits NDJSON lines to stdout so we can attribute findings to hypotheses.

set -u

emit() {
  printf '{"location":"diagnose-frontend-css.sh","message":"%s","data":%s,"timestamp":%s}\n' \
    "$1" "$2" "$(date +%s%3N 2>/dev/null || echo $(($(date +%s)*1000)))"
}

CONTAINER="metl-frontend"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  emit "container-missing" "{\"container\":\"$CONTAINER\"}"
  exit 1
fi

CSS_FILES=$(docker exec "$CONTAINER" sh -lc 'ls -1 /app/.next/static/css/ 2>/dev/null || true')
emit "css-files-listing" "{\"files\":\"$(printf '%s' "$CSS_FILES" | tr '\n' ',' )\"}"

if [ -z "$CSS_FILES" ]; then
  emit "css-dir-empty-or-missing" "{}"
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  SIZE=$(docker exec "$CONTAINER" sh -lc "wc -c < /app/.next/static/css/$f" | tr -d '[:space:]')
  HEAD=$(docker exec "$CONTAINER" sh -lc "head -c 400 /app/.next/static/css/$f" | tr -d '\r' | tr '\n' ' ' | sed 's/"/\\"/g')
  HAS_TAILWIND_IMPORT=$(docker exec "$CONTAINER" sh -lc "grep -c 'tailwindcss' /app/.next/static/css/$f || true")
  HAS_BG_CLASS=$(docker exec "$CONTAINER" sh -lc "grep -c '\.bg-' /app/.next/static/css/$f || true")
  emit "css-file-summary" "{\"file\":\"$f\",\"bytes\":$SIZE,\"contains_literal_tailwind_import\":$HAS_TAILWIND_IMPORT,\"bg_class_count\":$HAS_BG_CLASS,\"head\":\"$HEAD\"}"
done <<< "$CSS_FILES"
