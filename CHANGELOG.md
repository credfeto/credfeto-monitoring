# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Please ADD ALL Changes to the UNRELEASED SECTION and not a specific release
-->

## [Unreleased]
### Security
### Added
- Add Grafana to the VictoriaMetrics server stack for dashboarding collected metrics
### Fixed
- Fixed README.md formatting to pass the markdownlint pre-commit baseline check.
- VictoriaMetrics was bound to 127.0.0.1 only, making it unreachable from any other host on the network; changed to publish the port on all interfaces so Telegraf agents and the reverse proxy can actually reach it.
- Telegraf install on Ubuntu/Debian failed because the InfluxData signing key it fetched had expired and no longer covered the repository's active signing subkey; now fetches the current key, verifies its fingerprint before trusting it, and self-repairs hosts left with the stale keyring.
### Changed
- Rewrote README.md to describe the actual repo contents (VictoriaMetrics server and Telegraf client) instead of the leftover cs-template placeholder text.
### Deprecated
### Removed
### Deployment Changes
<!--
Releases that have at least been deployed to staging, BUT NOT necessarily released to live.  Changes should be moved from [Unreleased] into here as they are merged into the appropriate release branch
-->
## [0.0.2] - 2026-07-16
### Changed
- SDK - Updated DotNet SDK to 10.0.302

## [0.0.1] - 2026-06-11
### Fixed
- on_new_pr.yml: inline composite action logic to fix local action path resolution failure under pull_request_target
### Changed
- SDK - Updated DotNet SDK to 10.0.301

## [0.0.0] - Project created