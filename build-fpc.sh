#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_REL="${1:-ConsoleRadioPlayer/ConsoleRadioPlayer.dpr}"
PROJECT_REL="${PROJECT_REL#./}"
PROJECT_PATH="$ROOT/$PROJECT_REL"
OUT_DIR="${FPC_OUT_DIR:-$ROOT/Bin/linux}"
UNIT_DIR="${FPC_UNIT_DIR:-$ROOT/tmp/fpc/units}"
EXTRA_FLAGS=()

if [[ ! -f "$PROJECT_PATH" ]]; then
  printf 'Project not found: %s\n' "$PROJECT_REL" >&2
  exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-link)
      EXTRA_FLAGS+=("-Cn")
      ;;
    *)
      EXTRA_FLAGS+=("$1")
      ;;
  esac
  shift
done

mkdir -p "$OUT_DIR" "$UNIT_DIR"

cd "$ROOT"
fpc \
  -Mdelphi \
  -FuSource \
  -FuHeaders \
  -FE"$OUT_DIR" \
  -FU"$UNIT_DIR" \
  "${EXTRA_FLAGS[@]}" \
  "$PROJECT_REL"
