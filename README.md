# credfeto-monitoring

Deployment scripts and configuration for a self-hosted [VictoriaMetrics][victoriametrics] metrics server and the [Telegraf][telegraf] agents that feed it.

## Build Status

| Branch  | Status                                                |
|---------|-------------------------------------------------------|
| main    | [![Build: Pre-Release][pre-release-img]][pre-release] |
| release | [![Build: Release][release-img]][release]             |

[![Licence][licence-img]][licence]

## Overview

This repo hosts the infrastructure for a small self-hosted monitoring stack: a VictoriaMetrics server that stores time-series metrics, and Telegraf client agents that collect system and Docker metrics from each host and ship them to it.

## Usage

### Server: VictoriaMetrics

`server/victoriaMetrics/` contains the Docker Compose stack and helper scripts for the metrics server, including a [Grafana][grafana] instance provisioned to visualise the collected metrics, and [vmalert][vmalert] plus [Alertmanager][alertmanager] to alert on them.

```sh
cd server/victoriaMetrics
cp .env.example .env # first-time setup: set GF_SECURITY_ADMIN_PASSWORD
echo "<webhook url>" > alertmanager/webhook_url # first-time setup: chat webhook for alert notifications
./install # creates the data volumes and starts the stack
./update # pulls the latest images and restarts the stack
```

### Logs (VictoriaLogs)

[VictoriaLogs][victorialogs] stores logs for the whole network. It accepts syslog (RFC 3164 and RFC 5424) on port `514` TCP and UDP, so OPNsense, the MikroTik switches, the Zyxel APs, the Technitium Log Exporter app and journald forwarders can all send to it, and its HTTP API (including the native and Loki/Elasticsearch-compatible ingestion endpoints) is on port `9428`. Data lives in the `victoria-logs-data` volume (`/data/victoria-logs`); retention is `VICTORIALOGS_RETENTION` in `.env` (default `30d`). Grafana gets a provisioned `VictoriaLogs` datasource (plugin `victoriametrics-logs-datasource`). Like VictoriaMetrics, VictoriaLogs has no authentication, so keep ports `514` and `9428` LAN-only. After upgrading an existing install, run `./install` once (it is idempotent) to create the new data volume.

Grafana is available on port `3000` once the stack is running. Its VictoriaMetrics datasource and dashboards (host overview, Docker containers) are provisioned automatically from `server/victoriaMetrics/grafana/provisioning/`; no manual configuration is required.

### Alerting

`vmalert` evaluates the alerting rules in `server/victoriaMetrics/vmalert/rules/` against VictoriaMetrics and sends firing alerts to Alertmanager, which routes them to a Slack- or Discord-compatible chat webhook (Discord accepts Slack-formatted payloads via its `/slack` webhook suffix). vmalert's UI is available on port `8880`, Alertmanager's on port `9093`.

The webhook URL is never committed: create `server/victoriaMetrics/alertmanager/webhook_url` on the host (a plain text file containing only the URL) before running `./install`; that path is gitignored.

The starting rule set covers:

- a host that has stopped reporting metrics
- disk usage over 85%, or predicted to fill within 24 hours
- sustained high CPU usage
- low available memory
- a Docker container that is restart-looping
- the metrics ingestion pipeline stalling entirely

Firing alerts do not yet surface inside Grafana; that is tracked separately in [#20][alerting-in-grafana].

### MCP servers

The stack runs three [Model Context Protocol][mcp] servers so an AI client can query the monitoring data directly. All use the streamable HTTP transport:

| Service               | Host port | Endpoint                   | Backed by                                 |
|-----------------------|-----------|----------------------------|-------------------------------------------|
| `mcp-victoriametrics` | `8081`    | `http://<host>:8081/mcp`   | VictoriaMetrics (queries, series, labels) |
| `mcp-grafana`         | `8082`    | `http://<host>:8082/mcp`   | Grafana (dashboards, datasources, alerts) |
| `mcp-victorialogs`    | `8083`    | `http://<host>:8083/mcp`   | VictoriaLogs (log search, stats, streams) |

To connect a client, add each endpoint as a streamable HTTP MCP server. For example, in a client that reads an `mcpServers` JSON configuration:

```json
{
  "mcpServers": {
    "victoriametrics": {
      "type": "http",
      "url": "http://<host>:8081/mcp",
      "headers": { "Authorization": "Bearer <MCP_VICTORIAMETRICS_AUTH_TOKEN>" }
    },
    "grafana": {
      "type": "http",
      "url": "http://<host>:8082/mcp",
      "headers": { "Authorization": "Bearer <MCP_GRAFANA_SERVER_TOKEN>" }
    },
    "victorialogs": {
      "type": "http",
      "url": "http://<host>:8083/mcp",
      "headers": { "Authorization": "Bearer <MCP_VICTORIALOGS_AUTH_TOKEN>" }
    }
  }
}
```

Each endpoint requires a bearer token: clients must send `Authorization: Bearer <token>`, and requests without the right token are rejected with `401` before any tool runs. The tokens are set in `.env` (`MCP_VICTORIAMETRICS_AUTH_TOKEN`, `MCP_GRAFANA_SERVER_TOKEN`, `MCP_VICTORIALOGS_AUTH_TOKEN`); generate each with `openssl rand -hex 32`. `docker compose` refuses to start the stack while any of them is unset. Health and metrics paths (`/health/*`, `/metrics`) stay unauthenticated.

`mcp-victorialogs` v1.10.0 does not support `MCP_AUTH_TOKEN` yet (it is on upstream `main`), so port 8083 stays open to anyone who can reach it until a release that includes it is out. No configuration change is needed then: the MCP servers use `:latest` images and Watchtower picks up the new release.

The stack runs Watchtower to keep the `:latest` images (the three MCP servers) up to date. It checks hourly (default `0 17 * * * *`, override with `WATCHTOWER_SCHEDULE` in `.env`, a 6-field cron with seconds first). Images pinned to a version are left alone, because Watchtower only pulls a newer image for the same tag.

The tokens only control who may use the MCP servers. `mcp-victoriametrics` has full query access to every metric and `mcp-victorialogs` to every log line (VictoriaMetrics and VictoriaLogs themselves have no authentication), and `mcp-grafana` has whatever the Grafana service account below allows. `mcp-grafana` also runs with `--disable-write`, so it offers no tools that create or change anything in Grafana. The traffic is plain HTTP, so keep the ports on the LAN only and put TLS in front (a reverse proxy) for anything that crosses an untrusted network.

`mcp-grafana` authenticates to Grafana with a service account token from `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.env`. Grafana provisioning does not create the account, so on first setup:

1. Run `./install` with the placeholder token from `.env.example`. Grafana tools exposed by `mcp-grafana` cannot work until a real token is set.
2. In Grafana, open **Administration > Users and access > Service accounts** and select **Add service account**. Give it a name such as `mcp-grafana` and the `Viewer` role, so the MCP server has read-only access.
3. On the new service account, select **Add service account token**, generate a token and copy it (it is shown only once).
4. Set `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.env` to the token, then recreate the container with `sudo docker compose up -d mcp-grafana`.

### Firewall

`./update` (and `./install`) run `firewall/configure`, which locks the host down for ingress and egress:

| Filter                                | Traffic                     | Allowed                                                                                                                                                                                                                                                      |
|---------------------------------------|-----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `mon_ingress` (nftables)              | LAN -> published ports      | syslog (514) and the VictoriaLogs ingest (9428) from the internal networks; Grafana (3000), metrics ingest (8428) and the MCP servers (8081-8083) from the reverse proxies only                                                                                 |
| `host_out` (nftables `mon_egress`)     | host -> anywhere            | DNS to the fleet's DNS servers, NTP to the router, HTTPS to the proxies (Docker Hub mirror, pacman cache, metrics and log shipping), GitHub, ghcr.io, Docker Hub, Cloudflare, chaotic-aur, pkgstats and the Arch WKD, ICMP                                  |
| `docker_fwd` (nftables `mon_egress`)   | containers -> outside world | DNS, HTTPS to the proxies, Discord (Alertmanager), grafana.com (Grafana), Docker Hub and ghcr.io (Watchtower)                                                                                                                                                 |

SSH to the host is left to the host's base configuration.

Ingress is an nftables table of its own (`firewall/ingress.nft.template`, loaded by `monitoring-ingress-firewall.service` before Docker starts) rather than a firewalld policy, because Docker translates published ports itself and firewalld accepts all translated traffic before its policies run. The table only looks at new connections to published ports and matches the published port number. Egress is a table of its own too: the whole table, address sets included, is replaced in a single `nft -f` transaction, so a refresh never makes firewalld reload, and a ruleset that fails to load leaves the previous one in place.

Destinations without a stable address are address sets in the table that `monitoring-egress-refresh.timer` rebuilds 30 seconds after boot and then every 10 minutes, loading the table only when it differs from the loaded one: names resolved from DNS (a name that does not resolve keeps its last good addresses), plus GitHub's and Cloudflare's published ranges (`firewall/github-egress-ranges` and `firewall/cloudflare-egress-ranges`, regenerated on a workstation with the matching `firewall/update-*-egress-ranges` script). Cloudflare is allowed as a whole range because it fronts Discord and Docker Hub's image CDN and rotates their addresses too fast for resolved addresses to keep up.

`MONITORING_FIREWALL_ENFORCE` in `.env` is the only switch. Unset or anything other than `true` is observation mode: every rule is in place, but traffic that matches none of them still flows and is logged with the prefix `mon-ingress-unmatched:`, `mon-egress-unmatched:` or `mon-egress-docker-unmatched:` (rate-limited to 30 a minute). Run in observation mode first and check the journal for anything legitimate that is not covered:

```sh
sudo journalctl -k --since -1d | grep -E 'mon-[a-z-]+-unmatched'
```

then set `MONITORING_FIREWALL_ENFORCE=true` and run `./update` to drop everything else. To see the live egress rules:

```sh
sudo nft list table inet mon_egress
```

The firewall keeps itself in step with the repo, like the zone sync on the DNS servers: `monitoring-firewall-sync.timer` (every 15 minutes) refreshes the egress table, pulls the checkout and re-runs `firewall/configure` when anything under `server/victoriaMetrics/firewall/` changed since the commit it last applied. Container and compose changes still wait for `./update`. The `Repo: Update egress ranges` workflow regenerates the GitHub and Cloudflare range files daily and commits any change to main, refusing a list that has shrunk by more than a fifth, so new ranges reach the host within a day without anyone running anything.

### Client: Telegraf

`client/Telegraf/` contains the install and configuration scripts for the Telegraf agent deployed to each monitored host.

```sh
cd client/Telegraf
./install.sh    # installs the Telegraf package (Ubuntu/Debian or Arch)
./configure.sh  # validates and deploys telegraf.conf, then (re)starts the service
```

`configure.sh` checks `telegraf.conf` against the installed Telegraf (`telegraf config check`, available from Telegraf 1.32) before deploying it, and stops without touching `/etc/telegraf` or the service if Telegraf rejects the configuration. Pull requests that change `client/Telegraf/` run the same check against the latest Telegraf release.

When the installed Telegraf systemd unit reads `/etc/default/telegraf` (as the InfluxData package unit does), `configure.sh` creates that file with `TELEGRAF_OPTS=""` if it is missing, or appends `TELEGRAF_OPTS=""` if the file does not define the variable, so systemd stops warning about an unset variable on every start. An existing `TELEGRAF_OPTS` definition is never changed, and the service is restarted only when the file was created or updated.

The Docker input keeps only the `com.docker.compose.project` and `com.docker.compose.service` container labels as tags; all other labels are dropped to avoid a new series every time a container is recreated.

## Changelog

View [changelog][changelog]

## Contributing

See [CONTRIBUTING][contributing]

## Security

See [SECURITY][security]

## Licence

See [LICENSE][licence]

[alerting-in-grafana]: https://github.com/credfeto/credfeto-monitoring/issues/20
[alertmanager]: https://prometheus.io/docs/alerting/latest/alertmanager/
[changelog]: CHANGELOG.md
[contributing]: CONTRIBUTING.md
[grafana]: https://grafana.com/
[licence]: LICENSE
[licence-img]: https://img.shields.io/github/license/credfeto/credfeto-monitoring
[mcp]: https://modelcontextprotocol.io/
[pre-release]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-pre-release.yml
[pre-release-img]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-pre-release.yml/badge.svg
[release]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-release.yml
[release-img]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-release.yml/badge.svg
[security]: SECURITY.md
[telegraf]: https://www.influxdata.com/time-series-platform/telegraf/
[victoriametrics]: https://victoriametrics.com/
[vmalert]: https://docs.victoriametrics.com/victoriametrics/vmalert/
[victorialogs]: https://docs.victoriametrics.com/victorialogs/
