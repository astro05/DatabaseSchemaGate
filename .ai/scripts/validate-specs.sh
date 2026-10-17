#!/usr/bin/env bash
# Lints specs/: metadata, mandatory sections, index registration/status drift,
# and the Verification Matrix. Exits 1 on any error. Usage: bash .ai/scripts/validate-specs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPECS="$ROOT/specs"
INDEX="$SPECS/SPEC-INDEX.md"
errors=0
warnings=0

err()  { echo "ERROR  $1: $2"; errors=$((errors + 1)); }
warn() { echo "WARN   $1: $2"; warnings=$((warnings + 1)); }
trim() { local s="${1//$'\r'/}"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# Value of a "| Field | Value |" metadata row.
field() {
  awk -F'|' -v k="$2" '{ gsub(/^[ \t]+|[ \t\r]+$/, "", $2) } $2 == k { v = $3; gsub(/^[ \t]+|[ \t\r]+$/, "", v); print v; exit }' "$1"
}

SECTIONS=(
  "## Metadata"
  "## 1. Problem Statement & Motivation"
  "## 2. Architectural Boundaries & Data Flow"
  "## 3. Data Schemas & API Contracts"
  "## 4. Error Modes, Invariants & Edge Cases"
  "## 5. Verification Matrix"
)

[ -f "$INDEX" ] || { echo "ERROR  specs/SPEC-INDEX.md missing. First use in this project: run .ai/skills/init-project/SKILL.md"; exit 1; }

shopt -s nullglob
dirs=("$SPECS"/[0-9][0-9][0-9]-*/)
[ ${#dirs[@]} -gt 0 ] || warn "specs" "no spec folders found"

for dir in "${dirs[@]}"; do
  dir="${dir%/}"
  rel="${dir#"$ROOT"/}"
  spec="$dir/spec.md"
  [ -f "$spec" ] || { err "$rel" "missing spec.md"; continue; }
  [ -f "$dir/changelog.md" ] || err "$rel" "missing changelog.md"

  for f in ID Title Status Version Author Dependencies "Last Updated"; do
    [ -n "$(field "$spec" "$f")" ] || err "$rel" "metadata field '$f' missing or empty"
  done

  id="$(field "$spec" ID)"
  status="$(field "$spec" Status)"
  num="$(basename "$dir")"; num="${num%%-*}"
  [ "$id" = "SPEC-$num" ] || err "$rel" "ID '$id' does not match folder (expected SPEC-$num)"
  case "$status" in
    Draft|Approved|Deprecated) ;;
    *) err "$rel" "invalid Status '$status' (Draft|Approved|Deprecated)" ;;
  esac

  for s in "${SECTIONS[@]}"; do
    grep -qF -- "$s" "$spec" || err "$rel" "missing section '$s'"
  done

  # Index registration and status drift.
  idx_status="$(awk -F'|' -v id="$id" '{ for (i = 2; i <= NF; i++) gsub(/^[ \t]+|[ \t\r]+$/, "", $i) } $2 == id { print $4; exit }' "$INDEX")"
  if [ -z "$idx_status" ]; then
    err "$rel" "$id not registered in SPEC-INDEX.md"
  elif [ "$idx_status" != "$status" ]; then
    err "$rel" "status drift: spec says '$status', SPEC-INDEX says '$idx_status'"
  fi

  # Verification Matrix rows: | AC-NN | criterion | covers | test ref | status |
  rows="$(awk -F'|' '$2 ~ /^[ \t]*AC-[0-9]+[ \t]*$/' "$spec")"
  if [ -z "$rows" ]; then
    if [ "$status" = Approved ]; then err "$rel" "no AC rows in Verification Matrix"; else warn "$rel" "no AC rows yet"; fi
    continue
  fi

  total=0; verified=0
  while IFS='|' read -r _ ac _ _ ref st _; do
    ac="$(trim "$ac")"; ref="$(trim "${ref//\`/}")"; st="$(trim "$st")"
    total=$((total + 1))
    case "$st" in
      Verified) verified=$((verified + 1)) ;;
      Pending|Failing) ;;
      *) err "$rel" "$ac has invalid status '$st' (Pending|Verified|Failing)" ;;
    esac
    if [ -z "$ref" ] || [ "$ref" = TBD ] || [ "$ref" = "—" ] || [ "$ref" = "-" ]; then
      if [ "$status" = Approved ] || [ "$st" = Verified ]; then err "$rel" "$ac has no test reference"; fi
    elif [ ! -e "$ROOT/${ref%%::*}" ]; then
      if [ "$st" = Verified ]; then err "$rel" "$ac marked Verified but '${ref%%::*}' does not exist"
      else warn "$rel" "$ac test '${ref%%::*}' does not exist yet"; fi
    fi
  done <<< "$rows"

  if [ "$status" = Approved ] && grep -nE '\b(TBD|TODO)\b' "$spec" >/dev/null; then
    err "$rel" "Approved spec still contains TBD/TODO (lines: $(grep -nE '\b(TBD|TODO)\b' "$spec" | cut -d: -f1 | paste -sd, -))"
  fi

  echo "INFO   $rel: $id $status coverage $verified/$total"
done

echo "---"
echo "$errors error(s), $warnings warning(s)"
[ "$errors" -eq 0 ]
