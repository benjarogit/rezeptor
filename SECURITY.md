# Security policy

## Supported versions

Security fixes are applied to the current release on the `main` branch and the latest tagged AppImage/Flatpak release.

## Reporting a vulnerability

**Please do not open public GitHub issues for security vulnerabilities.**

Report privately via GitHub Security Advisories:

https://github.com/benjarogit/rezeptor/security/advisories/new

Or email the maintainer listed in the repository profile with:

- Affected version / commit
- Steps to reproduce
- Impact assessment (if known)

We aim to acknowledge reports within a few business days.

## Scope

In scope: Rezeptor launcher, `core/` modules, official recipes, update scripts (`scripts/rezeptor-update.sh`), and release artifacts (AppImage/Flatpak).

Out of scope: Third-party Windows installers, Adobe/Steam binaries, and host Wine/Proton builds outside this repository.

## Safe defaults

- Recipe trust manifest (`recipes/manifest.json`) — install/launch blocked when tampered
- Archive passwords stored encrypted (`settings` secrets store, mode `0600`)
- Release updates verified against `SHA256SUMS` when applying AppImage/Flatpak updates
