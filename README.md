# moodle_docker_test

A Dockerized Moodle install for local testing, built directly from the official Moodle
documentation (rather than a third-party all-in-one image) so the setup stays transparent:

- [Installing Moodle](https://docs.moodle.org/500/en/Installing_Moodle)
- [Installation quick start](https://docs.moodle.org/500/en/Installation_quick_start)
- [Command line installation](https://docs.moodle.org/500/en/Command_line_installation)
- [PHP requirements](https://docs.moodle.org/500/en/PHP)
- [Cron](https://docs.moodle.org/500/en/Cron)
- [Security recommendations](https://docs.moodle.org/500/en/Security_recommendations)

## Stack

- **Database:** MariaDB
- **Web/PHP:** Apache + mod_php in one container (`docker/moodle/Dockerfile`)
- **Source:** cloned from `github.com/moodle/moodle.git` (Moodle's official mirror) into `./moodle` (bind-mounted, so upgrading
  later is a plain `git pull`)
- **Data:** `./moodledata`, kept outside the web root as Moodle's docs require
- **Cron:** a dedicated `cron` container runs `admin/cli/cron.php` every 60 seconds

## Prerequisites

- Docker Desktop (Windows), with Git Bash available for running the shell script
- Git

## Usage

```bash
cp .env.example .env
# edit .env: set real DB/admin passwords, site name, etc.

bash scripts/install.sh
```

This will:
1. Resolve the Moodle version to install (`MOODLE_VERSION` in `.env`, default `latest`, which
   auto-detects the newest `MOODLE_x_STABLE` branch)
2. Clone the Moodle source
3. Build and start the `db`, `moodle`, and `cron` containers
4. Run the official CLI installer (`admin/cli/install.php`) non-interactively
5. Apply recommended permissions to `moodledata`

The site will be available at `http://localhost:8080` (or whatever `HTTP_PORT` you set).

### Installing a specific version

```bash
bash scripts/install.sh --version 405   # MOODLE_405_STABLE (4.5, LTS)
bash scripts/install.sh --version 500   # MOODLE_500_STABLE
bash scripts/install.sh --version main  # development branch
```

Re-running `scripts/install.sh` is safe — it skips the clone/install steps if `moodle/` and
`moodle/config.php` already exist, and just (re)starts the containers.

## Useful commands

```bash
docker compose ps                 # container status
docker compose logs -f cron       # watch cron runs
docker compose exec moodle bash   # shell into the app container
docker compose down               # stop everything (data volumes are preserved)
```
