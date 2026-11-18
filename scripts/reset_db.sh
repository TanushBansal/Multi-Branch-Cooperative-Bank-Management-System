#!/usr/bin/env bash
set -euo pipefail
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_USER="${MYSQL_USER:-root}"
ARGS=(-h "$MYSQL_HOST" -u "$MYSQL_USER")
[ -n "${MYSQL_PASSWORD:-}" ] && ARGS+=(-p"$MYSQL_PASSWORD")
mysql "${ARGS[@]}" -e "DROP DATABASE IF EXISTS CooperativeBank; CREATE DATABASE CooperativeBank;"
echo "Database reset."
