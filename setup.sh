#!/usr/bin/env bash
# Loads SmartQueue from scratch. Run from the project directory.
# Usage:
#   ./setup.sh                  # root via the local socket, no password
#   MYSQL_PWD=secret ./setup.sh
#   MYSQL_USER=root MYSQL_HOST=127.0.0.1 ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_HOST="${MYSQL_HOST:-}"

if ! command -v "$MYSQL_BIN" >/dev/null 2>&1; then
  if [[ -x /opt/homebrew/opt/mysql@8.0/bin/mysql ]]; then
    MYSQL_BIN=/opt/homebrew/opt/mysql@8.0/bin/mysql
  elif [[ -x /usr/local/opt/mysql@8.0/bin/mysql ]]; then
    MYSQL_BIN=/usr/local/opt/mysql@8.0/bin/mysql
  else
    echo "mysql client not found. Install MySQL 8.0 and re-run." >&2
    exit 1
  fi
fi

args=(-u "$MYSQL_USER" --default-character-set=utf8mb4)
if [[ -n "$MYSQL_HOST" ]]; then
  args+=(-h "$MYSQL_HOST" --protocol=TCP)
fi

echo "Using $MYSQL_BIN as $MYSQL_USER"

# A second run would DROP the database and erase every patient registered since
# the sample load. That only happens when RESET_DATA=1 is set on purpose.
if [[ "${RESET_DATA:-}" != "1" ]]; then
  have="$("$MYSQL_BIN" "${args[@]}" -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='SmartQueue'" 2>/dev/null || true)"
  if [[ "${have:-0}" != "0" ]]; then
    echo "SmartQueue already exists, so registered patients were left untouched."
    echo "To throw them away and load the sample data again: RESET_DATA=1 ./setup.sh"
    exit 0
  fi
fi

for f in sql/01_schema.sql sql/02_seed_data.sql sql/03_functions.sql sql/04_procedures.sql \
         sql/05_triggers.sql sql/06_views.sql sql/07_events.sql sql/08_indexes.sql sql/09_roles.sql
do
  echo "==> $f"
  "$MYSQL_BIN" "${args[@]}" < "$f"
done

echo "==> event scheduler"
"$MYSQL_BIN" "${args[@]}" -e "SET GLOBAL event_scheduler = ON;" \
  || echo "Could not enable the event scheduler. Add event_scheduler=ON under [mysqld] and restart MySQL."

echo "SmartQueue is loaded. Optional: $MYSQL_BIN ${args[*]} < sql/10_tests.sql"
echo "Then: cd server && npm install && npm start"
