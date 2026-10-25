# Backup Configuration for Garage S3 and PostgreSQL

This document describes the manual backup configuration used on the `east-storage` and `west-storage` virtual machines in the distributed infrastructure project. The solution protects the two Garage S3 buckets (`product-images` and `monitoring-logs`) and the Patroni-managed PostgreSQL database (`shopdb`). S3 objects are first synchronized to a local staging directory with rclone, while the database is dumped only from the current Patroni Primary. Restic then creates encrypted, deduplicated snapshots on the dedicated `/srv/backup` RAID1 volume of each storage server.

The procedure was tested on both storage nodes. Commands that configure the operating system, Restic, rclone, PostgreSQL credentials, and systemd should be executed on both `east-storage` and `west-storage` unless a step explicitly says otherwise.

## Backup design

- **Backup sources:** Garage buckets `product-images` and `monitoring-logs`, plus PostgreSQL database `shopdb`.
- **Backup destinations:** separate local Restic repositories under `/srv/backup/restic-repos/` on each storage VM.
- **S3 workflow:** Garage S3 → rclone staging directory → Restic repository.
- **Database workflow:** detect the current Patroni Primary → create a verified `pg_dump` → save it in Restic.
- **Isolation:** all backup operations run as the non-login system account `restic_sysuser`.
- **Scheduling:** the PostgreSQL backup runs daily at 02:10 UTC through a systemd timer.

> The screenshots use the same numbers and filenames as the edited Word document. Sensitive access keys, secret keys, and passwords remain redacted.

## 1 Create a read-only Garage key

Create a dedicated Garage key for backups. The key does not need permission to create buckets; it only needs read access to the two existing data buckets.

```bash
sudo garage key import --yes -n backup-reader "ACCESS_KEY" "SECRET_KEY"
```

<img width="1512" height="98" alt="image" src="https://github.com/user-attachments/assets/e9f7f0aa-34ba-4460-b2ee-540e45d3ed88" />


Confirm that the key exists and inspect its current permissions.

```bash
sudo garage key info backup-reader
```

<img width="526" height="367" alt="image" src="https://github.com/user-attachments/assets/889a95ec-8696-469f-bb69-cbaef97d1414" />


Grant read-only access to both buckets and verify the result.

```bash
sudo garage bucket allow --read product-images --key backup-reader
sudo garage bucket allow --read monitoring-logs --key backup-reader
sudo garage key info backup-reader
```

<img width="1383" height="676" alt="image" src="https://github.com/user-attachments/assets/18dbcaa8-32b4-49e2-a5dc-aec3e2e1d740" />

## 2 Install the backup tools

Restic stores encrypted snapshots, rclone reads the Garage S3 API, the PostgreSQL client provides `psql`, `pg_dump`, and `pg_restore`, and `util-linux` provides `flock` and `mountpoint`.

```bash
sudo apt update
sudo apt install -y restic rclone postgresql-client-18 util-linux
```

<img width="1741" height="1110" alt="image" src="https://github.com/user-attachments/assets/3fb039d5-9983-4efe-9d98-4a90f3de4dbc" />


## 3 Create the service account and directories

The dedicated account has no interactive shell. Repository, staging, cache, and configuration directories are owned so that the backup process can run without using root for normal data access.

```bash
sudo useradd --system --create-home --home-dir /var/lib/restic --shell /usr/sbin/nologin restic_sysuser
```

<img width="1099" height="594" alt="image" src="https://github.com/user-attachments/assets/7a8823d4-acd4-49e0-8d69-9a4200f0460d" />


```bash
sudo install -d -o restic_sysuser -g restic_sysuser -m 0700 /srv/backup/restic-repos
sudo install -d -o restic_sysuser -g restic_sysuser -m 0700 \
  /srv/backup/restic-repos/s3-product-images \
  /srv/backup/restic-repos/s3-loki-logs \
  /srv/backup/restic-repos/postgresql-shopdb
sudo install -d -o restic_sysuser -g restic_sysuser -m 0700 \
  /var/lib/project-backup/staging/product-images \
  /var/lib/project-backup/staging/loki-logs \
  /var/lib/project-backup/staging/postgresql-shopdb
sudo install -d -o root -g restic_sysuser -m 0750 /etc/project-backup
```

<img width="1744" height="695" alt="image" src="https://github.com/user-attachments/assets/1eeac8bc-a549-4f4c-8075-d9d8b5556cc6" />


## 4 Configure the Restic repository password

The same password file can unlock all three repositories on one node. Store its value in Ansible Vault for automated deployment. Losing this password makes the Restic snapshots unrecoverable.

```bash
sudo install -o restic_sysuser -g restic_sysuser -m 0600 /dev/null /etc/project-backup/restic-password
sudoedit /etc/project-backup/restic-password
```

The file must contain only the repository password and a final newline.

<img width="712" height="695" alt="image" src="https://github.com/user-attachments/assets/ea8c1456-652b-4322-9199-1cd5ac65b641" />


## 5 Configure rclone for Garage S3

Each storage node connects to its local Garage S3 endpoint at `127.0.0.1:3900`. The `backup-reader` credentials are used only for reading objects into the staging directories.

```bash
sudo install -o restic_sysuser -g restic_sysuser -m 0600 /dev/null /etc/project-backup/rclone.conf
sudoedit /etc/project-backup/rclone.conf
```

```ini
[garage]
type = s3
provider = Other
env_auth = false
access_key_id = BACKUP_ACCESS_KEY
secret_access_key = BACKUP_SECRET_KEY
region = garage
endpoint = http://127.0.0.1:3900
force_path_style = true
acl = private
bucket_acl = private
```

<img width="724" height="844" alt="image" src="https://github.com/user-attachments/assets/d4850690-0456-4f10-883b-368b4e7edd34" />


Verify that rclone can read both buckets. Empty buckets should report zero objects and zero bytes without an authentication error.

```bash
sudo -u restic_sysuser rclone --config /etc/project-backup/rclone.conf size garage:product-images
sudo -u restic_sysuser rclone --config /etc/project-backup/rclone.conf size garage:monitoring-logs
```

<img width="1104" height="707" alt="image" src="https://github.com/user-attachments/assets/72f7e443-cb3c-479c-9dc8-be7bde32b667" />


## 6 Initialize the Restic repositories

Separate repositories make retention, restoration, and access checks independent for images, Loki logs, and PostgreSQL. Initialize all three repositories on each storage VM.

```bash
sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/s3-product-images init
sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/s3-loki-logs init
sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/postgresql-shopdb init
```

<img width="1401" height="885" alt="image" src="https://github.com/user-attachments/assets/bab879db-7d6a-4e2b-8269-34dc0880b47c" />


## 7 Test the S3 backup workflow

The staging directory is synchronized from Garage before Restic creates a snapshot. The `sync` operation also removes local staging files that no longer exist in the source bucket, while historical versions remain available in older Restic snapshots.

### Product images

```bash
sudo -u restic_sysuser rclone --config /etc/project-backup/rclone.conf \
  sync garage:product-images /var/lib/project-backup/staging/product-images

sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/s3-product-images \
  backup /var/lib/project-backup/staging/product-images \
  --host garage-cluster --tag s3 --tag product-images

sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/s3-product-images snapshots
```

<img width="1697" height="1077" alt="image" src="https://github.com/user-attachments/assets/52233fb7-03c6-4484-9edf-a2d98c138a65" />


### Loki logs

```bash
sudo -u restic_sysuser rclone --config /etc/project-backup/rclone.conf \
  sync garage:monitoring-logs /var/lib/project-backup/staging/loki-logs

sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/s3-loki-logs \
  backup /var/lib/project-backup/staging/loki-logs \
  --host garage-cluster --tag s3 --tag loki

sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/s3-loki-logs snapshots
```
<img width="1698" height="1058" alt="image" src="https://github.com/user-attachments/assets/88af1130-a329-4008-b685-b41c49e9e2e0" />


## 8 Configure PostgreSQL authentication

The backup account must be able to connect to both Patroni database nodes. The `.pgpass` format is `host:port:database:user:password`, with one line for each possible Primary.

```bash
sudo install -o restic_sysuser -g restic_sysuser -m 0600 /dev/null /etc/project-backup/pgpass
sudoedit /etc/project-backup/pgpass
```
<img width="1698" height="1058" alt="image" src="https://github.com/user-attachments/assets/6e1c94f3-fc41-4a8b-ba22-5493ecb33396" />


```text
192.168.72.4:5432:shopdb:backup_reader:BACKUP_READER_PASSWORD
192.168.73.4:5432:shopdb:backup_reader:BACKUP_READER_PASSWORD
```

<img width="1507" height="742" alt="image" src="https://github.com/user-attachments/assets/4e39a82d-c7ad-4c66-831c-c2a4befb47d1" />


## 9 Prepare the PostgreSQL staging area

The database dump and its metadata are written to a protected staging directory. Restic cache data is kept under `/var/lib/project-backup/restic-cache` so the service can run with `ProtectHome=true`.

```bash
sudo install -d -o restic_sysuser -g restic_sysuser -m 0700 \
  /var/lib/project-backup/staging/postgresql-shopdb
sudo install -d -o restic_sysuser -g restic_sysuser -m 0700 \
  /var/lib/project-backup/restic-cache
```

<img width="1698" height="1058" alt="image" src="https://github.com/user-attachments/assets/a9de0985-a42d-4c71-8fef-a7e6cf2a9d89" />


## 10 Create the Primary-aware database backup script

The script checks both database nodes and continues only when exactly one node reports itself as Primary. It writes the dump to a temporary file, verifies that the same node is still Primary after `pg_dump`, validates the dump with `pg_restore --list`, and only then moves the file into its final location. This prevents an interrupted failover from producing a snapshot that appears successful but contains an incomplete or stale dump.

```bash
sudo install -o root -g root -m 0755 /dev/null /usr/local/sbin/project-db-backup
sudoedit /usr/local/sbin/project-db-backup
```

<img width="1324" height="817" alt="image" src="https://github.com/user-attachments/assets/2a489bc2-cb9d-4422-82d3-7bf427e0d05b" />


```bash
#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly DATABASE="shopdb"
readonly DATABASE_USER="backup_reader"
readonly DATABASE_PORT="5432"

readonly -a DATABASE_HOSTS=(
  "192.168.72.4"
  "192.168.73.4"
)

readonly BACKUP_MOUNT="/srv/backup"
readonly RESTIC_REPOSITORY="/srv/backup/restic-repos/postgresql-shopdb"
readonly STAGING_DIRECTORY="/var/lib/project-backup/staging/postgresql-shopdb"
readonly TEMPORARY_DUMP="${STAGING_DIRECTORY}/shopdb.dump.part"
readonly FINAL_DUMP="${STAGING_DIRECTORY}/shopdb.dump"
readonly PRIMARY_FILE="${STAGING_DIRECTORY}/source-primary.txt"
readonly DATE_FILE="${STAGING_DIRECTORY}/backup-created-utc.txt"
readonly LOCK_FILE="${STAGING_DIRECTORY}/backup.lock"

export PGPASSFILE="/etc/project-backup/pgpass"
export RESTIC_PASSWORD_FILE="/etc/project-backup/restic-password"
export XDG_CACHE_HOME="/var/lib/project-backup/restic-cache"
export PGCONNECT_TIMEOUT="10"

log() {
  printf '[db-backup] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

cleanup() {
  local exit_code=$?
  rm -f "$TEMPORARY_DUMP"

  if [[ "$exit_code" -ne 0 ]]; then
    log "Backup failed"
  fi

  exit "$exit_code"
}

detect_primary() {
  local database_host
  local database_role
  local primary_count=0

  PRIMARY_DATABASE=""

  for database_host in "${DATABASE_HOSTS[@]}"; do
    database_role=$(psql \
      --host="$database_host" \
      --port="$DATABASE_PORT" \
      --username="$DATABASE_USER" \
      --dbname="$DATABASE" \
      --no-password \
      --tuples-only \
      --no-align \
      --command="SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END;" \
      2>/dev/null || true)

    case "$database_role" in
      primary)
        log "$database_host is Primary"
        PRIMARY_DATABASE="$database_host"
        primary_count=$((primary_count + 1))
        ;;
      replica)
        log "$database_host is Replica"
        ;;
      *)
        log "$database_host is unavailable"
        ;;
    esac
  done

  if [[ "$primary_count" -ne 1 ]]; then
    log "Expected exactly one Primary, found $primary_count"
    PRIMARY_DATABASE=""
    return 1
  fi
}

verify_primary_after_dump() {
  local database_role

  database_role=$(psql \
    --host="$PRIMARY_DATABASE" \
    --port="$DATABASE_PORT" \
    --username="$DATABASE_USER" \
    --dbname="$DATABASE" \
    --no-password \
    --tuples-only \
    --no-align \
    --command="SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END;" \
    2>/dev/null || true)

  [[ "$database_role" == "primary" ]]
}

main() {
  local attempt
  local dump_created=0

  mountpoint -q "$BACKUP_MOUNT" || fail "$BACKUP_MOUNT is not mounted"
  [[ -f "${RESTIC_REPOSITORY}/config" ]] || fail "Restic repository is not initialized"
  [[ -r "$PGPASSFILE" ]] || fail "PostgreSQL password file is not readable"
  [[ -r "$RESTIC_PASSWORD_FILE" ]] || fail "Restic password file is not readable"

  mkdir -p "$STAGING_DIRECTORY"

  exec 9>"$LOCK_FILE"
  flock -n 9 || fail "Another database backup is already running"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  for attempt in 1 2 3; do
    log "Backup attempt $attempt of 3"

    if ! detect_primary; then
      rm -f "$TEMPORARY_DUMP"

      if [[ "$attempt" -lt 3 ]]; then
        log "Waiting 10 seconds before retry"
        sleep 10
      fi

      continue
    fi

    rm -f "$TEMPORARY_DUMP"

    if ! pg_dump \
      --host="$PRIMARY_DATABASE" \
      --port="$DATABASE_PORT" \
      --username="$DATABASE_USER" \
      --dbname="$DATABASE" \
      --no-password \
      --format=custom \
      --file="$TEMPORARY_DUMP"; then
      log "pg_dump failed on $PRIMARY_DATABASE"
      rm -f "$TEMPORARY_DUMP"

      if [[ "$attempt" -lt 3 ]]; then
        log "Waiting 10 seconds before retry"
        sleep 10
      fi

      continue
    fi

    if ! verify_primary_after_dump; then
      log "$PRIMARY_DATABASE is no longer Primary; discarding dump"
      rm -f "$TEMPORARY_DUMP"

      if [[ "$attempt" -lt 3 ]]; then
        log "Waiting 10 seconds before retry"
        sleep 10
      fi

      continue
    fi

    pg_restore --list "$TEMPORARY_DUMP" >/dev/null || fail "Created PostgreSQL dump is invalid"

    dump_created=1
    break
  done

  [[ "$dump_created" -eq 1 ]] || fail "Database backup failed after 3 attempts"

  mv -f "$TEMPORARY_DUMP" "$FINAL_DUMP"
  printf '%s\n' "$PRIMARY_DATABASE" >"$PRIMARY_FILE"
  date -u +'%Y-%m-%dT%H:%M:%SZ' >"$DATE_FILE"

  log "Saving PostgreSQL dump to Restic"

  restic \
    --repo "$RESTIC_REPOSITORY" \
    backup \
    "$FINAL_DUMP" \
    "$PRIMARY_FILE" \
    "$DATE_FILE" \
    --host="project-postgres" \
    --tag="postgresql" \
    --tag="shopdb"

  log "Latest Restic snapshot"

  restic \
    --repo "$RESTIC_REPOSITORY" \
    snapshots \
    --latest 1

  log "Database backup completed successfully"
}

main "$@"
```

```bash
sudo chown root:root /usr/local/sbin/project-db-backup
sudo chmod 0755 /usr/local/sbin/project-db-backup
```

<img width="1698" height="1101" alt="image" src="https://github.com/user-attachments/assets/54f179dd-9bb8-4c74-8d76-1f204a21131d" />


## 11 Create the systemd service

The oneshot service runs as `restic_sysuser`, refuses to start when `/srv/backup` is not mounted, and limits writable paths to the backup volume and working directory.

```bash
sudo install -o root -g root -m 0644 /dev/null /etc/systemd/system/project-db-backup.service
sudoedit /etc/systemd/system/project-db-backup.service
```

```ini
[Unit]
Description=Backup current Patroni Primary database to Restic
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/srv/backup

[Service]
Type=oneshot
User=restic_sysuser
Group=restic_sysuser
UMask=0077

Environment=PGPASSFILE=/etc/project-backup/pgpass
Environment=RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password
Environment=XDG_CACHE_HOME=/var/lib/project-backup/restic-cache

ExecStartPre=/usr/bin/mountpoint -q /srv/backup
ExecStart=/usr/local/sbin/project-db-backup

TimeoutStartSec=30min
Nice=10

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/backup /var/lib/project-backup
```

<img width="1324" height="842" alt="image" src="https://github.com/user-attachments/assets/ce111b98-5307-4170-83d9-7a6c8a3e40ad" />


Reload systemd, start the service manually, and confirm that a PostgreSQL snapshot was created.

```bash
sudo systemctl daemon-reload
sudo systemctl start project-db-backup.service
sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/postgresql-shopdb snapshots
```

<img width="1507" height="911" alt="image" src="https://github.com/user-attachments/assets/d949e9ae-2cec-4c5d-9cf2-ed1b527beee9" />


## 12 Schedule the daily database backup

The timer runs the service every day at 02:10 UTC. `Persistent=true` causes a missed run to start after the machine becomes available again, while the randomized delay prevents both storage nodes from starting at exactly the same second.

```bash
sudo install -o root -g root -m 0644 /dev/null /etc/systemd/system/project-db-backup.timer
sudoedit /etc/systemd/system/project-db-backup.timer
```

```ini
[Unit]
Description=Daily PostgreSQL backup timer

[Timer]
OnCalendar=*-*-* 02:10:00 UTC
Persistent=true
RandomizedDelaySec=5m
Unit=project-db-backup.service

[Install]
WantedBy=timers.target
```

<img width="1116" height="911" alt="image" src="https://github.com/user-attachments/assets/333ca662-a8f1-4190-b651-8fb8bc39e35a" />


Enable the timer on both storage nodes.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now project-db-backup.timer
```

<img width="1222" height="911" alt="image" src="https://github.com/user-attachments/assets/fb245c63-2c5c-4f62-bf50-cba283ee79df" />


## 13 Verification and maintenance

Use the following commands after deployment and during troubleshooting.

```bash
systemctl list-timers project-db-backup.timer
sudo systemctl status project-db-backup.timer --no-pager
sudo journalctl -u project-db-backup.service -n 100 --no-pager

sudo -u restic_sysuser env RESTIC_PASSWORD_FILE=/etc/project-backup/restic-password \
  restic -r /srv/backup/restic-repos/postgresql-shopdb check
```

The current configuration creates and schedules PostgreSQL snapshots. The S3 commands above are manual tests and should later be wrapped in their own service and timer or Ansible-managed scripts. A Restic retention policy (`forget --prune`) and regular restore tests should also be added before treating the solution as production-ready.

## Result

Both storage servers now hold independent Restic repositories on local RAID1 volumes. The database job follows Patroni failover by detecting the current Primary at runtime.
