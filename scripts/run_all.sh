#!/usr/bin/env bash
# Runs the numbered SQL files in database/ in order.
set -euo pipefail
cd "$(dirname "$0")/.."
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_USER="${MYSQL_USER:-root}"
ARGS=(-h "$MYSQL_HOST" -u "$MYSQL_USER")
[ -n "${MYSQL_PASSWORD:-}" ] && ARGS+=(-p"$MYSQL_PASSWORD")
for f in database/0[1-7]_*.sql; do
  echo "Running $f"
  mysql "${ARGS[@]}" < "$f"
done
echo "Build complete."
