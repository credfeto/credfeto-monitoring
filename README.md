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

`server/victoriaMetrics/` contains the Docker Compose stack and helper scripts for the metrics server, including a [Grafana][grafana] instance provisioned to visualise the collected metrics.

```sh
cd server/victoriaMetrics
cp .env.example .env  # first-time setup: set GF_SECURITY_ADMIN_PASSWORD
./install              # creates the data volumes and starts the stack
./update               # pulls the latest images and restarts the stack
```

Grafana is available on port `3000` once the stack is running. Its VictoriaMetrics datasource and dashboards (host overview, Docker containers) are provisioned automatically from `server/victoriaMetrics/grafana/provisioning/`; no manual configuration is required.

### Client: Telegraf

`client/Telegraf/` contains the install and configuration scripts for the Telegraf agent deployed to each monitored host.

```sh
cd client/Telegraf
./install.sh    # installs the Telegraf package (Ubuntu/Debian or Arch)
./configure.sh  # deploys telegraf.conf and (re)starts the service
```

## Changelog

View [changelog][changelog]

## Contributing

See [CONTRIBUTING][contributing]

## Security

See [SECURITY][security]

## Licence

See [LICENSE][licence]

[changelog]: CHANGELOG.md
[contributing]: CONTRIBUTING.md
[grafana]: https://grafana.com/
[licence]: LICENSE
[licence-img]: https://img.shields.io/github/license/credfeto/credfeto-monitoring
[pre-release]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-pre-release.yml
[pre-release-img]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-pre-release.yml/badge.svg
[release]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-release.yml
[release-img]: https://github.com/credfeto/credfeto-monitoring/actions/workflows/build-and-publish-release.yml/badge.svg
[security]: SECURITY.md
[telegraf]: https://www.influxdata.com/time-series-platform/telegraf/
[victoriametrics]: https://victoriametrics.com/
