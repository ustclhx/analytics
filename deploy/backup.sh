#!/bin/bash
# 每日备份：Postgres 用 pg_dump，ClickHouse 用 BACKUP DATABASE，保留最近 7 天。
# 由 /etc/cron.d/plausible-backup 调用；在 deploy 目录下执行。
set -euo pipefail
cd "$(dirname "$0")"
ts=$(date -u +%Y%m%dT%H%M%SZ)
dir=backups/$ts
mkdir -p "$dir"
# ClickHouse 容器以 uid 101 写入，备份目录只给它和 root 访问
chown 101:101 backups "$dir"
chmod 700 backups "$dir"

docker compose exec -T plausible_db pg_dump -U postgres -Fc plausible_db > "$dir/plausible_db.dump"
docker compose exec -T plausible_events_db clickhouse-client \
  --query "BACKUP DATABASE plausible_events_db TO File('/backups/$ts/events/')" > /dev/null

# 空文件视为失败，避免静默产生无效备份
[ -s "$dir/plausible_db.dump" ] || { echo "backup: empty pg dump" >&2; exit 1; }
[ -d "$dir/events" ] || { echo "backup: missing clickhouse backup" >&2; exit 1; }

find backups -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
echo "backup ok: $dir $(du -sh "$dir" | cut -f1)"
