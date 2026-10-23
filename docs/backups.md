# Production backups

The production data on stargate is backed up every night. A backup is the Postgres dump
plus the whole MinIO object storage, in the format `deploy/restore.sh` reads.

## What runs

Cron on stargate starts `deploy/backup-nightly.sh` at 03:30 local time. The script:

- writes one full backup through `deploy/backup.sh` to
  `~/backups/form-production/nightly/<UTC timestamp>/` (`postgres.dump` and
  `object-storage.tar.gz`),
- keeps only the newest three and deletes the rest,
- removes folders a failed run left without both files,
- skips the run when the volume has less than 20 GB free, so backups never fill the disk,
- appends one line per run to `~/backups/form-production/nightly.log`.

A backup is about 390 MB on 2026-10-23, almost all of it object storage, so three take
about 1.2 GB and grow with the photos. `FORM_BACKUP_KEEP`, `FORM_BACKUP_MIN_FREE_GB` and
`FORM_BACKUP_DIR` override the defaults.

## Check that it works

```sh
ssh stargate
tail -5 ~/backups/form-production/nightly.log   # e.g. "… kept 3, 408 GB free"
ls ~/backups/form-production/nightly
```

A line with `skipped:` means the disk ran low; free space first, nothing was written.

## The cron entry

The user crontab on stargate can only be installed with `sudo`, because `crontab` there
lacks the permission to write user crontabs on its own. The entry lives in
`~/backups/form-production/crontab.txt`:

```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 3 * * * cd $HOME/dev/wardrobe-studio && ./deploy/backup-nightly.sh >> $HOME/backups/form-production/nightly.log 2>&1
```

Install or update it with:

```sh
sudo crontab -u Nicolas ~/backups/form-production/crontab.txt
sudo crontab -u Nicolas -l
```

Only the host's cron reads it. The `busybox crond` that also shows up in `ps` runs inside a
Docker container of another service.

## Before risky work

`deploy/backup.sh ~/backups/form-production` takes an extra backup by hand, for example
before a deploy with migrations. Those land next to `nightly/` and are not rotated, so
delete them once they are no longer needed.

## Restore

Restoring stops production and replaces its data, so it only happens on an explicit
request:

```sh
cd ~/dev/wardrobe-studio
FORM_RESTORE_CONFIRMED=true ./deploy/restore.sh ~/backups/form-production/nightly/<timestamp>
```

The previous data stays recoverable in a `*.before-restore.<timestamp>` folder next to the
data directory.
