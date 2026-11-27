# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Please ADD ALL Changes to the UNRELEASED SECTION and not a specific release
-->

## [Unreleased]
### Security
- Firewall: reverse proxies' Servers VLAN addresses no longer allowed; only DMZ addresses work
- Firewall: reverse proxies' DMZ VLAN addresses allowed alongside Servers VLAN ones for migration
- Host firewall lockdown (`firewall/configure`), log only until `MONITORING_FIREWALL_ENFORCE`
- MCP servers require a bearer token (`MCP_AUTH_TOKEN`, `MCP_GRAFANA_SERVER_TOKEN`) or return 401
- mcp-victorialogs v1.10.0 does not yet enforce the bearer token (`MCP_AUTH_TOKEN`)
### Added
- Firewall auto-sync timer (`monitoring-firewall-sync.timer`) and a daily egress range workflow
- VictoriaLogs records each syslog sender address as `remote_ip` to tell shared hostnames apart
- mcp-victorialogs (v1.10.0) MCP server on LAN port 8083 so AI assistants can search logs
- VictoriaLogs v1.54.0 central log store (syslog on 514, API on 9428) with a Grafana datasource
- mcp-victoriametrics and mcp-grafana MCP servers on LAN ports 8081 and 8082 (#45)
- Restricted Funfair MCP `mcp-victoriametrics-funfair` (port 8084, proxies only) via vmauth
- vmalert alerts `SmartDeviceUnhealthy` and `SmartDeviceWearHigh` for failing or worn disks
- vmalert `SmartDeviceNotReporting` warns when a disk stops sending SMART data
- Telegraf collects SMART disk health and wear data (`inputs.smart`); installs `smartmontools`
- Telegraf SMART collection runs every 5 minutes; `install.sh` also installs `nvme-cli`
- Telegraf sudoers rule allows only the read-only `smartctl` queries it runs
### Fixed
- Egress script takes a lock and uses a unique temp cache file, so concurrent runs no longer fail
- `firewall/configure` takes a lock, so the sync timer and `./update` cannot run it concurrently
- `DiskWillFillWithin24Hours` no longer fires after reboots: ignores `mode`, needs 6h of data
- `./update` now reloads vmalert (SIGHUP) so changed alert rules take effect straight away
- `./update` re-runs itself after `git pull`, so script changes apply on the same run
- `./update` recreates alertmanager so changes to its bind-mounted `alertmanager.yml` apply
- Alertmanager now delivers: uses native `discord_configs` instead of `slack_configs`
- `HostNotReporting` can now fire: `host:metrics_stale_seconds` uses `tlast_over_time`
- mcp-grafana no longer rejects requests as forbidden: Hosts set by `MCP_GRAFANA_ALLOWED_HOSTS`
- Funfair MCP host filter matched nothing: vmauth decoded the + in its regex as a space
- Firewall sync script no longer word-splits changed file paths, so paths with spaces work
- Client and server scripts print colour codes only to a terminal, not into piped output
### Changed
- All containers use `restart: always`, not `unless-stopped`, so they return after a reboot
- MCP servers use `:latest` images, kept updated by hourly Watchtower (`WATCHTOWER_SCHEDULE`)
- Host egress firewall is one atomic nftables table (`inet mon_egress`), not firewalld policies
### Deprecated
### Removed
- Removed unused .NET scaffolding: `src/global.json`, `Credfeto.Template.slnx`, `.DotSettings`
### Deployment Changes
- Firewall starts observe-only; check `journalctl -k`, then enable `MONITORING_FIREWALL_ENFORCE`
- After a day, check `journalctl -k | grep -E 'mon-[a-z-]+-unmatched'` for uncovered traffic
- Then set `MONITORING_FIREWALL_ENFORCE=true` in `.env` and run `./update`
- Add `MCP_VICTORIAMETRICS_AUTH_TOKEN` and `MCP_VICTORIALOGS_AUTH_TOKEN` to `.env` first
- Add `MCP_GRAFANA_SERVER_TOKEN` to `.env` too; generate each token with `openssl rand -hex 32`
- `docker compose` refuses to start the stack without the three MCP token variables
- Add `Authorization: Bearer` with the token to every MCP client

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
- configure.sh validates telegraf.conf with telegraf config check before deploying it
- CI runs the same check against the latest Telegraf release on pull requests
- Removed Telegraf options are now caught before they break a host
### Fixed
- Telegraf 1.38+ failed to start because telegraf.conf used options removed from inputs.docker
- inputs.docker: removed options container_names, perdevice and total are no longer used
- inputs.docker now uses perdevice_include and total_include instead
- Fixed vmalert failing to start due to the unsupported --remoteWrite.tmpDataPath flag
- systemd warned about an unset TELEGRAF_OPTS on every Telegraf start
- configure.sh now creates /etc/default/telegraf when it does not exist
- configure.sh appends TELEGRAF_OPTS="" when the defaults file exists but does not define it
- configure.sh leaves any existing TELEGRAF_OPTS definition unchanged
- configure.sh reported success and restarted Telegraf even when config or defaults I/O failed
- configure.sh now stops with an error when reading or writing the config or defaults fails
- Fixed alertmanager crash-looping due to permission-denied reading its config
- install/update scripts now grant alertmanager's runtime uid/gid read access to its config
### Changed
- The Docker input now tags only the com.docker.compose.project and service container labels
- The Docker input no longer tags every container label
- Labels that change on every recreate (such as the compose config hash) no longer add series
- Series cardinality no longer grows on each watchtower update
- Set skip_processors_after_aggregators in [agent] to silence Telegraf's default-change warning
- Telegraf disk input now also ignores the nsfs and efivarfs pseudo-filesystems
- nsfs and efivarfs have no meaningful disk-usage metrics
- SDK - Updated DotNet SDK to 10.0.402
### Removed
- Unused src/FunFair.props
### Deployment Changes
- Run client/Telegraf/configure.sh on each monitored host to apply config and defaults changes

## [0.0.4] - 2026-09-17
### Fixed
- Telegraf client config pointed at metrics.markridgwell.com, which has no DNS record
- Metrics pushes silently failed on every host; Telegraf now uses monitoring.markridgwell.com
### Changed
- SDK - Updated DotNet SDK to 10.0.401

## [0.0.3] - 2026-08-20
### Added
- Add Grafana as a sibling service in the VictoriaMetrics compose stack
- Grafana is provisioned from repo-checked-in files so metrics are visible without manual setup
- Grafana has a VictoriaMetrics datasource and host overview and Docker containers dashboards
- Add vmalert and Alertmanager to the VictoriaMetrics compose stack
- Alerts on host outages, disk usage/predicted fill, sustained CPU load and low memory
- Alerts on Docker container restart loops and stalled metrics ingestion
- Alertmanager notifies via a Slack/Discord-compatible chat webhook
### Fixed
- Fixed README.md formatting to pass the markdownlint pre-commit baseline check.
- VictoriaMetrics was bound to 127.0.0.1 only, so no other host on the network could reach it
- VictoriaMetrics now publishes its port on all interfaces for Telegraf and the reverse proxy
- Telegraf install on Ubuntu/Debian failed as the fetched InfluxData signing key had expired
- The expired key no longer covered the repository's active signing subkey
- Telegraf install now fetches the current key and verifies its fingerprint before trusting it
- Telegraf install self-repairs hosts left with the stale keyring
### Changed
- Rewrote README.md to describe the actual repo contents, not cs-template placeholder text
- README.md now covers the VictoriaMetrics server and Telegraf client
- SDK - Updated DotNet SDK to 10.0.400

## [0.0.2] - 2026-07-16
### Changed
- SDK - Updated DotNet SDK to 10.0.302

## [0.0.1] - 2026-06-11
### Fixed
- on_new_pr.yml: inline composite action logic to fix local action path resolution failure
- The local action path resolution failure occurred under pull_request_target
### Changed
- SDK - Updated DotNet SDK to 10.0.301

## [0.0.0] - Project created