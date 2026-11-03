# 自建 Plausible 运维手册

所有项目共用的 Plausible 社区版实例。本目录只放部署材料，fork 的其余部分是上游源码，保持与上游同步。

| 项目 | 值 |
|---|---|
| 地址 | `https://stats.ganjiday.com`（以后可换，见「换域名」） |
| 服务器 | 阿里云新加坡 `ecs.e-c1m2.large`（2 vCPU / 4 GB / 60 GB），Ubuntu 22.04，SSH 别名 `plausible-ecs` |
| 版本 | 官方镜像 `ghcr.io/plausible/community-edition:v3.2.1`，ClickHouse 24.12，Postgres 16 |
| 部署目录 | `/opt/plausible/deploy`（本仓库 `ops/selfhost-deploy` 分支的稀疏检出） |
| 证书 | 实例自己签发 Let's Encrypt，DNS 记录必须是 DNS only（不开 Cloudflare 代理） |

真值只在服务器的 `deploy/.env`（root:600），不进仓库。

## 首次部署

1. 服务器：装 Docker（官方 apt 源），`ufw` 只放行 22/80/443，root 只允许密钥登录。阿里云安全组同样只放行这三个端口。
2. DNS：在 Cloudflare 为子域名加 A 记录，指向服务器公网 IP，Proxy status 选 DNS only。
3. 检出并生成配置：

   ```bash
   cd /opt
   git clone --filter=blob:none --sparse --branch ops/selfhost-deploy https://github.com/ustclhx/analytics.git plausible
   cd plausible && git sparse-checkout set deploy && cd deploy
   umask 077
   sed -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')|" \
       -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" .env.example > .env
   mkdir -p backups && chown 101:101 backups && chmod 700 backups
   docker compose up -d
   ```

4. 打开 `BASE_URL/register` 注册第一个账号（即管理员）。之后 `DISABLE_REGISTRATION=invite_only` 只允许邀请注册。
5. 安装每日备份：

   ```bash
   echo '30 3 * * * root /opt/plausible/deploy/backup.sh >> /var/log/plausible-backup.log 2>&1' > /etc/cron.d/plausible-backup
   ```

## 新站接入

每个项目建两个 site：生产 `<项目名>`、staging `<项目名>-staging`。目标与自定义属性清单见模板仓库 `docs/analytics.md` §4，然后在项目里填 `PLAUSIBLE_DOMAIN` 与 `PLAUSIBLE_HOST=https://stats.ganjiday.com`。

## 备份与恢复

`backup.sh` 每天 03:30（服务器时区）把 Postgres（`pg_dump -Fc`）和 ClickHouse（`BACKUP DATABASE`）写到 `deploy/backups/<UTC 时间>/`，保留 7 天。另外请在阿里云控制台为系统盘开启自动快照，作为整机兜底。异地备份（R2）尚未配置。

恢复（先在空实例上演练）：

```bash
cd /opt/plausible/deploy
docker compose stop plausible
ts=<备份目录名>
docker compose exec -T plausible_db pg_restore -U postgres -d plausible_db --clean --if-exists < backups/$ts/plausible_db.dump
docker compose exec -T plausible_events_db clickhouse-client \
  --query "RESTORE DATABASE plausible_events_db FROM File('/backups/$ts/events/') SETTINGS allow_non_empty_tables=true"
docker compose start plausible
```

## 升级

1. 读上游 community-edition 对应版本的发布说明和 `compose.yml` 改动，同步到本目录。
2. 先跑一次 `backup.sh`。
3. 改 `compose.yml` 的镜像标签，提交后在服务器 `git pull && docker compose pull && docker compose up -d`。

用本 fork 自行构建镜像时，在 `.env` 设置 `PLAUSIBLE_IMAGE`。

## 换域名

1. Cloudflare 加新子域名 A 记录（DNS only）。
2. 改 `.env` 的 `BASE_URL`，`docker compose up -d`，实例会为新域名签证书。
3. 各项目改 `PLAUSIBLE_HOST` 并重新部署，确认新地址有数据后再删旧记录。

## 已知限制

- 社区版没有漏斗和收入目标，详见模板仓库 `docs/analytics.md` §4。
- 没有配置 SMTP：不能发邀请和找回密码邮件。阿里云默认封出站 25 端口，需要时配 SMTP 中继（`.env` 中的 `SMTP_*`）。
