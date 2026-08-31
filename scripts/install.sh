#!/usr/bin/env bash
# Installs Moodle into Docker containers, following the official Moodle docs:
#   https://docs.moodle.org/500/en/Installing_Moodle
#   https://docs.moodle.org/500/en/Command_line_installation
#   https://docs.moodle.org/500/en/Security_recommendations
set -euo pipefail

# On Git Bash / MSYS, unix-style absolute paths passed as arguments to native
# Windows exes (like docker.exe) get silently rewritten to Windows paths
# (e.g. /var/www/moodledata -> C:/Program Files/Git/var/www/moodledata).
# This must be set before any docker/docker-compose invocation below.
export MSYS_NO_PATHCONV=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MOODLE_REPO="https://github.com/moodle/moodle.git"
VERSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --version=*)
      VERSION_OVERRIDE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "No .env file found." >&2
  echo "Copy .env.example to .env, adjust the credentials, then re-run this script." >&2
  exit 1
fi

set -a
source .env
set +a

MOODLE_VERSION="${VERSION_OVERRIDE:-${MOODLE_VERSION:-latest}}"
HTTP_PORT="${HTTP_PORT:-8080}"

resolve_branch() {
  local version="$1"

  if [[ "$version" == "main" ]]; then
    echo "main"
    return
  fi

  if [[ "$version" =~ ^MOODLE_[0-9]+_STABLE$ ]]; then
    echo "$version"
    return
  fi

  if [[ "$version" =~ ^[0-9]+$ ]]; then
    echo "MOODLE_${version}_STABLE"
    return
  fi

  if [[ "$version" == "latest" ]]; then
    echo "Looking up the latest stable Moodle branch from $MOODLE_REPO ..." >&2
    local branch
    branch=$(git ls-remote --heads "$MOODLE_REPO" \
      | grep -oE 'MOODLE_[0-9]+_STABLE' \
      | sort -u \
      | sort -V \
      | tail -n1)
    if [[ -z "$branch" ]]; then
      echo "Could not determine the latest stable branch automatically." >&2
      exit 1
    fi
    echo "$branch"
    return
  fi

  # Fall back to treating the value as a literal branch name.
  echo "$version"
}

MOODLE_BRANCH="$(resolve_branch "$MOODLE_VERSION")"
echo "Using Moodle branch: $MOODLE_BRANCH"

if [[ ! -d moodle || -z "$(ls -A moodle 2>/dev/null)" ]]; then
  echo "Cloning Moodle source ($MOODLE_BRANCH) ..."
  rm -rf moodle
  git clone --branch "$MOODLE_BRANCH" --depth 1 "$MOODLE_REPO" moodle
else
  echo "moodle/ already contains source, skipping clone."
fi

mkdir -p moodledata

echo "Building images ..."
docker compose build

echo "Starting database ..."
docker compose up -d db

echo "Waiting for database to become healthy ..."
until [[ "$(docker compose ps -q db | xargs docker inspect -f '{{.State.Health.Status}}')" == "healthy" ]]; do
  sleep 2
done

echo "Starting Moodle and cron containers ..."
docker compose up -d moodle cron

WWWROOT="http://localhost:${HTTP_PORT}"

# config.php can exist from a previous *failed* install attempt (e.g. it's
# written before the dataroot/DB setup steps that might still fail), so treat
# the DB actually containing Moodle's tables as the real "already installed" signal.
ALREADY_INSTALLED=false
if [[ -f moodle/config.php ]] && docker compose exec -T db \
    mariadb -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "SELECT 1 FROM mdl_config LIMIT 1;" >/dev/null 2>&1; then
  ALREADY_INSTALLED=true
fi

if [[ "$ALREADY_INSTALLED" == true ]]; then
  echo "Moodle is already installed (mdl_config found in the database), skipping installer."
else
  if [[ -f moodle/config.php ]]; then
    echo "Found an incomplete install (config.php exists but the database has no Moodle tables) — removing stale config.php and retrying."
    rm -f moodle/config.php
  fi
  echo "Running the Moodle CLI installer ..."
  docker compose exec -T moodle php admin/cli/install.php \
    --lang=en \
    --wwwroot="$WWWROOT" \
    --dataroot=/var/www/moodledata \
    --dbtype=mariadb \
    --dbhost=db \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASSWORD" \
    --fullname="$SITE_FULLNAME" \
    --shortname="$SITE_SHORTNAME" \
    --adminuser="$ADMIN_USER" \
    --adminpass="$ADMIN_PASSWORD" \
    --adminemail="$ADMIN_EMAIL" \
    --agree-license \
    --non-interactive
fi

echo "Applying recommended permissions ..."
# NOTE: permission changes must run *inside* the container — chmod/chown from
# the Windows host on a bind-mounted path here does not reliably propagate
# into the container's view of the filesystem via Docker Desktop.
docker compose exec -T moodle chown -R www-data:www-data /var/www/moodledata
docker compose exec -T moodle chmod -R 770 /var/www/moodledata
# config.php only needs to be readable by the webserver process — it is
# already outside the public/ webroot, so it is never served over HTTP.
docker compose exec -T moodle chmod 644 /var/www/html/config.php

cat <<EOF

Moodle is up at: $WWWROOT
Admin user:      $ADMIN_USER
Admin email:     $ADMIN_EMAIL

Cron runs automatically every 60 seconds in the 'cron' container.
EOF
