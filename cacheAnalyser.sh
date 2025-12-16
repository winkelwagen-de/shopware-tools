#!/usr/bin/env bash
set -u

ROOT="${1:-var/cache}"
PROGRESS_EVERY=1000
SUMMARY_STEP=5        # Prozent
TOP_N=5

TMP="/var/tmp/cache_prefix_stream.$$.tmp"
: > "$TMP"
trap 'rm -f "$TMP"' EXIT

# IO-Priorität senken
if command -v ionice >/dev/null 2>&1; then
  if ! ionice -p $$ >/dev/null 2>&1; then
    exec ionice -c2 -n7 "$0" "$@"
  fi
fi

echo "Zähle Dateien…"
TOTAL=$(find "$ROOT" -type f | wc -l | tr -d ' ')
echo "Gefunden: $TOTAL Dateien"
echo

COUNT=0
START_TS=$(date +%s)
NEXT_SUMMARY_PERCENT=$SUMMARY_STEP

print_summary () {
  echo
  echo "Aktueller Zwischenstand (Top $TOP_N nach MB):"
  printf "%-45s %10s %12s\n" "PREFIX" "FILES" "MB"
  printf "%-45s %10s %12s\n" "---------------------------------------------" "----------" "------------"

  awk -F'\t' '
    { files[$1] += $2; bytes[$1] += $3 }
    END {
      for (p in files)
        printf "%s\t%d\t%.2f\n", p, files[p], bytes[p] / 1024 / 1024
    }
  ' "$TMP" |
    sort -t $'\t' -k3,3nr |
    head -n "$TOP_N" |
    awk -F $'\t' '{ printf "%-45s %10d %12.2f\n", $1, $2, $3 }'
}

while IFS= read -r -d '' file; do
  ((COUNT++))

  # -------- Progress alle 1000 Dateien ----------
  if (( COUNT % PROGRESS_EVERY == 0 )); then
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TS))
    RATE=$((COUNT / (ELAPSED + 1)))
    ETA=$(((TOTAL - COUNT) / (RATE + 1)))
    PERCENT=$((COUNT * 100 / TOTAL))

    printf "\r[%3d%%] %'d / %'d Dateien | %'d files/s | ETA ~%ds" \
      "$PERCENT" "$COUNT" "$TOTAL" "$RATE" "$ETA"
  fi

  # -------- Zwischenstand nur alle 5 % ----------
  CURRENT_PERCENT=$((COUNT * 100 / TOTAL))
  if (( CURRENT_PERCENT >= NEXT_SUMMARY_PERCENT )); then
    print_summary
    NEXT_SUMMARY_PERCENT=$((NEXT_SUMMARY_PERCENT + SUMMARY_STEP))
  fi

  size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file")

  {
    read -r _
    read -r key
  } < "$file"

  [[ -z "${key:-}" ]] && continue

  IFS='-' read -r a b c _ <<< "$key"
  if [[ -n "${c:-}" ]]; then
    prefix="$a-$b-$c"
  elif [[ -n "${b:-}" ]]; then
    prefix="$a-$b"
  else
    prefix="$a"
  fi

  printf "%s\t1\t%d\n" "$prefix" "$size" >> "$TMP"

done < <(find "$ROOT" -type f -print0)

echo
echo "===== FINALER STAND ====="
print_summary
