#!/usr/bin/env bash
# Fail when lib/oblodai/generated is not what the backend's generator makes of the gateway's contract.
#
# Regenerates into a temporary directory with the backend's tools/sdkgen (from
# services/core/api/openapi.json, checked against names.lock) and compares file by file, the method
# table of both READMEs included. The backend checkout is $OBLODAI_BACKEND, else ../oblodai-backend
# next to this repository. Without a backend
# that has tools/sdkgen the check is skipped, loudly; with --require it fails instead. Fix drift by
# regenerating (`make regenerate` here, or `make sdk` in the backend), never by hand.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
backend="${OBLODAI_BACKEND:-$root/../oblodai-backend}"
sdkgen="$backend/tools/sdkgen"
spec="$backend/services/core/api/openapi.json"

if [ ! -d "$sdkgen/cmd/sdkgen" ] || [ ! -f "$spec" ]; then
  message="no generator at $sdkgen (set OBLODAI_BACKEND to the backend checkout)"
  if [ "${1:-}" = "--require" ]; then
    echo "check_generated: $message" >&2
    exit 1
  fi
  echo "  (skipped: $message)"
  exit 0
fi
command -v go >/dev/null 2>&1 || { echo "check_generated: go is required to run tools/sdkgen" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The READMEs go along so the generator rewrites their method table; names.lock is checked frozen: a
# lock behind the API fails here instead of being extended.
cp README.md README.ru.md "$tmp/"
(cd "$sdkgen" && GOTOOLCHAIN="${GOTOOLCHAIN:-go1.26.6}" go run ./cmd/sdkgen \
  -spec "$spec" -lang ruby -out "$tmp" -lock "$root/names.lock" -frozen-lock)

stale=0
if ! diff -r "$tmp/lib/oblodai/generated" "$root/lib/oblodai/generated" >/dev/null; then
  diff -rq "$tmp/lib/oblodai/generated" "$root/lib/oblodai/generated" >&2 || true
  stale=1
fi
for doc in README.md README.ru.md; do
  if ! cmp -s "$tmp/$doc" "$root/$doc"; then
    echo "$doc: the method table differs" >&2
    stale=1
  fi
done
if [ "$stale" = 1 ]; then
  echo "check_generated: generated code is stale; regenerate with \`make regenerate\`" >&2
  exit 1
fi
echo "generated code matches $spec"
