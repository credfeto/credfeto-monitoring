# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Please ADD ALL Changes to the UNRELEASED SECTION and not a specific release
-->

## [Unreleased]
### Security
- Firewall: the reverse proxies' Servers VLAN addresses are no longer allowed; only their DMZ ones are
- Firewall: the reverse proxies' DMZ VLAN addresses are allowed too, so each can move to the DMZ
- Host ingress and egress firewall (`firewall/configure`), in observation mode until enforce is set
- MCP servers need a bearer token (401 without it); mcp-victorialogs v1.10.0 does not enforce it yet
### Added
- Alertmanager also sends every alert to a second receiver, the Familiar agent webhook
- Firewall auto-sync timer on the monitoring host, and a daily workflow refreshing egress range files
- VictoriaLogs records each syslog sender's address as `remote_ip`, to tell same-named senders apart
- mcp-victorialogs (v1.10.0) MCP server on LAN port 8083, so AI assistants can search the central logs
- VictoriaLogs (v1.54.0) as the central log store: syslog on 514, HTTP API on 9428, Grafana datasource
- mcp-victoriametrics and mcp-grafana MCP servers on LAN ports 8081 and 8082 for AI assistants (#45)
- Restricted Funfair MCP server `mcp-victoriametrics-funfair` (port 8084, proxies only) via vmauth
### Fixed
- The egress script takes a lock and uses a unique temp file, so concurrent runs no longer fail
- `firewall/configure` takes a lock, so the sync timer and `./update` cannot run it at the same time
- DiskWillFillWithin24Hours misfired after reboots; it now ignores `mode` and needs 6h of history
- `./update` reloads vmalert (SIGHUP) after updating, so changed alert rules take effect straight away
- `./update` re-runs itself after `git pull`, so changes to the update script apply on the same run
- `./update` recreates alertmanager, as its single-file bind mount kept the old config after a pull
- Alertmanager never delivered a notification: it now uses discord_configs instead of slack_configs
- HostNotReporting could never fire: host:metrics_stale_seconds now uses tlast_over_time
- mcp-grafana rejected every request (host not allowed); it now reads MCP_GRAFANA_ALLOWED_HOSTS
- Funfair MCP host filter matched nothing: vmauth decoded the + in its regex as a space
### Changed
- All containers use `restart: always` instead of `unless-stopped`, so they come back after a reboot
- The MCP servers use `:latest` images, and Watchtower (`WATCHTOWER_SCHEDULE`) keeps them up to date
- The host egress firewall is one nftables table (`inet mon_egress`) instead of firewalld policies
### Deprecated
### Removed
- Unused .NET template scaffolding removed: src/global.json and the Credfeto.Template solution files
### Deployment Changes
- The firewall starts in observation mode: check the unmatched logs, then enable enforcing in `.env`
- Before updating, add the three MCP auth tokens to `.env`, then the Bearer header to every MCP client

<!--
Releases that have at least been deployed to staging, BUT NOT necessarily released to live.  Changes should be moved from [Unreleased] into here as they are merged into the appropriate release branch
-->

## [0.0.7] - 2026-11-04
### Changed
- SDK - Updated DotNet SDK to 11.0.100-rc.3.26522.148

## [0.0.6] - 2026-10-26
### Changed
- SDK - Updated DotNet SDK to 10.0.403

## [0.0.5] - 2026-10-15
### Added
- configure.sh and a CI workflow check telegraf.conf with telegraf config check before deploying it
### Fixed
- Telegraf 1.38+ failed to start: inputs.docker now uses perdevice_include and total_include
- Fixed vmalert failing to start due to an invalid --remoteWrite.tmpDataPath flag
- systemd warned about an unset TELEGRAF_OPTS; configure.sh now defines it in /etc/default/telegraf
- configure.sh now stops with an error when reading or writing the config or defaults file fails
- Fixed alertmanager crash-looping reading its config; install/update grant its uid/gid read access
### Changed
- The Docker input tags only the compose project and service labels, so recreates no longer add series
- skip_processors_after_aggregators is set explicitly in [agent] to silence Telegraf's warning
- Telegraf disk input also ignores the nsfs and efivarfs pseudo-filesystems
- SDK - Updated DotNet SDK to 10.0.402
### Removed
- Unused src/FunFair.props
### Deployment Changes
- Run client/Telegraf/configure.sh on each host to apply the Telegraf config and defaults-file changes

## [0.0.4] - 2026-09-17
### Fixed
- Telegraf used metrics.markridgwell.com, which has no DNS record; now monitoring.markridgwell.com
### Changed
- SDK - Updated DotNet SDK to 10.0.401

## [0.0.3] - 2026-08-20
### Added
- Add Grafana to the VictoriaMetrics stack, with a datasource and dashboards provisioned from the repo
- Add vmalert and Alertmanager to the VictoriaMetrics stack, alerting via a chat webhook
### Fixed
- Fixed README.md formatting to pass the markdownlint pre-commit baseline check.
- VictoriaMetrics was bound to 127.0.0.1 only; it now publishes its port on all interfaces
- Telegraf install on Ubuntu/Debian failed on an expired InfluxData key; it now fetches a verified one
### Changed
- Rewrote README.md to describe the actual repo contents instead of the cs-template placeholder text
- SDK - Updated DotNet SDK to 10.0.400

## [0.0.2] - 2026-07-16
### Changed
- SDK - Updated DotNet SDK to 10.0.302

## [0.0.1] - 2026-06-11
### Fixed
- on_new_pr.yml: inline the composite action logic to fix local action path resolution failure
### Changed
- SDK - Updated DotNet SDK to 10.0.301

## [0.0.0] - Project created