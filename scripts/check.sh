#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v lua-language-server >/dev/null 2>&1; then
  echo "lua-language-server not found in PATH." >&2
  exit 127
fi

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

run_check() {
  lua-language-server --check="$root_dir" >"$tmpfile" 2>&1
}

format_output() {
  sed $'s/\x1b\\[[0-9;]*[mK]//g' "$tmpfile" \
    | tr -d '\r' \
    | sed '/>>/d;/Initializing /d;/Diagnosis complete/d' \
    | awk 'NF'
}

if run_check; then
  if [[ -s "$tmpfile" ]]; then
    format_output
  else
    echo "lua-language-server check completed without diagnostics."
  fi
else
  format_output
  exit 1
fi
