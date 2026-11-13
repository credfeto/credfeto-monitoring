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

The stack runs two [Model Context Protocol][mcp] servers so an AI client can query the monitoring data directly. Both use the streamable HTTP transport:

| Service               | Host port | Endpoint                   | Backed by                                 |
|-----------------------|-----------|----------------------------|-------------------------------------------|
| `mcp-victoriametrics` | `8081`    | `http://<host>:8081/mcp`   | VictoriaMetrics (queries, series, labels) |
| `mcp-grafana`         | `8082`    | `http://<host>:8082/mcp`   | Grafana (dashboards, datasources, alerts) |

To connect a client, add each endpoint as a streamable HTTP MCP server. For example, in a client that reads an `mcpServers` JSON configuration:

```json
{
  "mcpServers": {
    "victoriametrics": { "type": "http", "url": "http://<host>:8081/mcp" },
    "grafana": { "type": "http", "url": "http://<host>:8082/mcp" }
  }
}
```

Neither endpoint has any authentication. Anyone who can reach the ports can use them: `mcp-victoriametrics` has full query access to every metric (VictoriaMetrics itself has no authentication), and `mcp-grafana` has whatever the Grafana service account below allows. `mcp-grafana` also runs with `--disable-write`, so it offers no tools that create or change anything in Grafana. Keep both ports on the LAN only; they are not published through Traefik or the Cloudflare Tunnel.

`mcp-grafana` authenticates to Grafana with a service account token from `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.env`. Grafana provisioning does not create the account, so on first setup:

1. Run `./install` with the placeholder token from `.env.example`. Grafana tools exposed by `mcp-grafana` cannot work until a real token is set.
2. In Grafana, open **Administration > Users and access > Service accounts** and select **Add service account**. Give it a name such as `mcp-grafana` and the `Viewer` role, so the MCP server has read-only access.
3. On the new service account, select **Add service account token**, generate a token and copy it (it is shown only once).
4. Set `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.env` to the token, then recreate the container with `sudo docker compose up -d mcp-grafana`.

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
