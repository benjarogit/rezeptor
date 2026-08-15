# Changelog

All notable changes to **Rezeptor** are documented here (English).
GitHub Release notes should match these bullets.

## [Unreleased]

## [1.1.47] - 2026-08-15

### Fixed
- Photoshop quit: read the parent pid of a Wine process correctly when its `comm` holds spaces, so windows owned by a helper process are found again
- Photoshop quit: only close windows that can be traced to this recipe's Wine prefix — a second Photoshop installation running next to it is left untouched

## [1.1.46] - 2026-08-15

### Fixed
- Photoshop Quit when no window is left (after ✕, Alt+F4 or File → Exit): Rezeptor now waits briefly and asks Wine to close Photoshop normally before it forces the quit, so prefs/Recents still get written ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Release notes link to the real compare view again instead of pointing at `CHANGELOG.md`

## [1.1.45] - 2026-08-15

### Added
- Lightroom Classic recipe (15.4.1 offline installer on Proton-GE)

### Fixed
- Photoshop Quit: ask the window manager to close Photoshop instead of destroying its window. Destroying it left Photoshop running with no window, so it never ran its quit path and never wrote Recents/prefs ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Photoshop Quit no longer stalls on “Window closed”: if Photoshop stays up it is ended after a timeout instead of leaving a half-dead session behind ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Photoshop cleanup: stop `CCLibrary` / `AdobeNotificationClient` too and end the prefix `wineserver` once `Photoshop.exe` is really gone, so leftover helpers cannot crash the next launch ([#10](https://github.com/benjarogit/rezeptor/issues/10))

## [1.1.44] - 2026-08-13

### Fixed
- Photoshop Quit: once the window is gone, wait for a normal exit and do not force-kill or `wineserver -k` (Recents/prefs amnesia, [#10](https://github.com/benjarogit/rezeptor/issues/10))
- Photoshop launch: do not bounce wineserver on every start (cold start looked like a hang)
- Header watermark: keep the faded recipe icon above Fluent card chrome (visible in Flatpak)

### Changed
- Photoshop runtime is Proton-GE 11-3 + DXVK from 10-28 + X11 + `d2d1=n` (Medizin toggle removed)
- Mehr menu actions use Font Awesome icons; FA fonts resolve from extra Flatpak/AppImage paths
- Sidebar: Finanzen & Steuer first (WISO); Video & editing and Documents & PDF are standard categories again
- README marks Rezeptor as experimental (fixes can creep back after refactors)

## [1.1.43] - 2026-08-12

### Fixed
- Halo repair: stop `winetricks vcrun2019` from pinning MSVC 14.29; ensure CRT 14.40+ via cabextract
- Deploy vkd3d-proton `d3d12` / `d3d12core` into the prefix (validate no longer reports missing D3D12 after repair)
- Vorgang tab: Schritte/Live no longer overlap; OK/FAIL rows appear in Schritte
- Header health chip text no longer clipped (e.g. “4 Hinweise”)
- Window icon: opaque anthracite PNG/ICO (no white corners in title bars)
- Keep relocated data_root.path when the target disk is temporarily unmounted
- Launch dialog: show real script errors (missing EXE) instead of “not active after launch”

## [1.1.42] - 2026-08-12

### Added
- UI themes: Standard (brand), Dracula, and Alucard (persisted; menubar cycle)
- Home community links use site favicons (LinuxChooser, CachyOS, LinuxGuides)
- Recipe app/game folder symlink into `DATA_ROOT` via `core/recipe-app-link.sh`

### Changed
- Home and sidebar layout: content-sized recipe list, compact window height when not maximized
- Theme-aware status pills, activity colors, and header watermark clipped to card radius
- Action bar stays visible on the home page (docs CTA)

### Fixed
- Home link URLs for LinuxChooser and LinuxGuides forum
- Low-contrast secondary text when switching to Alucard/Dracula

## [1.1.41] - 2026-08-12

### Added
- System check: detect 32-bit FreeType and libgcc (Arch `lib32-freetype2` / `lib32-gcc-libs` and equivalents) needed for Adobe Setup / IE8 under Wine ([#11](https://github.com/benjarogit/rezeptor/issues/11))

### Changed
- System check re-opens when required packages are still missing (not only on first launch)
- Install/Repair for WoW64 recipes (e.g. Photoshop) is blocked until required 32-bit host libraries are present; user can install via pkexec or copy the command

## [1.1.40] - 2026-08-12

### Fixed
- Photoshop Quit: host window-close via process id (and related Wine PIDs), retries, and Alt+F4; drop soft `taskkill` that left Wine “Not responding” while the UI still painted ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Mehr menu: no trailing empty separator when the last group (e.g. Uninstall) is omitted
- Message dialogs use Font Awesome icons instead of Qt stock glyphs

## [1.1.39] - 2026-08-11

### Added
- Home: cross-recipe activity history (recent installs/repairs/etc., click to select the recipe)
- Optional recipe `tested_on` date next to the Proton-GE badge (when set in `recipe.yml`)
- Diagnose: export a sanitized zip of recent logs (allowlisted paths)
- Backup reminders before relocate and before uninstall (WISO names tax data explicitly)
- Friendlier install path preview (pending source and target) and related launcher UX polish

### Changed
- Recipe process ops live in `launcher/recipe_process.py` (same behaviour, clearer structure)

### Fixed
- Recipe trust manifest stays in sync after Halo asset edits (`make recipe-manifest-check`)

### Internal
- CI: Python 3.11–3.13 matrix with pytest; shell/bats job once; aggregator job still named `validate`
- Dead unused `.lang` trees and legacy Bash `launcher()` removed from core

## [1.1.38] - 2026-08-11

### Fixed
- Photoshop Quit: close only real Photoshop windows via WM_CLASS (never by title substring), so browser tabs mentioning “Photoshop” stay open ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Photoshop launch cleanup: prefix-scoped process kills (no global `pkill` on `Photoshop.exe` / Adobe IPC broker)
- Adobe diagnose / case-alias helpers: do not abort under `set -e` when `output::*` is not loaded

## [1.1.37] - 2026-08-10

### Fixed
- Photoshop Quit: ask for a normal exit first (host window-close / `taskkill` without `/F`) so Recent Files and prefs can flush; only escalate if Photoshop stays up ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Host check for 32-bit loader (`lib32-glibc` / `libc6-i386`): fail early with a clear install hint instead of obscure winetricks `syswow64\\regedit` `c0000135` failures ([#11](https://github.com/benjarogit/rezeptor/issues/11))

## [1.1.36] - 2026-08-09

### Fixed
- Photoshop: after closing the PS window, Rezeptor runs orphan cleanup (Spaces/CEP/IPC + wineserver) so helpers do not linger and the next launch keeps session prefs; Quit also asks PS to exit before forcing. Cleanup is **prefix-scoped** (`WINEPREFIX` in process environ / `wineserver -k`) so parallel Wine sessions stay untouched ([#10](https://github.com/benjarogit/rezeptor/issues/10))
- Do not rewrite a recipe’s `data_root.path` when `RECIPE_DATA_ROOT` and `DATA_ROOT` disagree (stale env from another selected recipe, e.g. Halo → Photoshop). Exit-cleanup now sets both roots for the stopped recipe; Activity lines for cleanup only when that recipe is selected
- `recipe-lint`: allow optional root script `cleanup-orphans.sh` (needed for #10 exit cleanup)


## [1.1.35] - 2026-08-08

### Changed
- Photoshop Medizin **Test: Proton-GE 11-3**: GE-Proton11-3 + **DXVK 2.7 from GE-Proton10-28** + **forced X11** + **`d2d1=n`** (Wine 11 builtin d2d1 painted a white main window; GDI path restores dark chrome). Still experimental; daily default stays GE-Proton10-28 ([#8](https://github.com/benjarogit/rezeptor/issues/8))

### Added
- `PROTON_GE_DXVK_TAG` / `wine_runtime::_resolve_dxvk_root` / `ensure_proton_ge_tag` — deploy DXVK from a different Proton-GE tree than the active Wine root

## [1.1.34] - 2026-08-07

### Fixed
- **Photoshop / global runtime:** restore default Proton-GE pin to **GE-Proton10-28** (1.1.33 had bumped the global lock to 11-3 for Halo and broke PS UI for some users — [#8](https://github.com/benjarogit/rezeptor/issues/8))
- Flatpak verify: accept Proton `wine` without separate `wine64` (same as AppImage); bundle default tag from `runtime.lock` again (**10-28**)

### Added
- Per-recipe Proton-GE pin: `proton_ge_tag` / optional `proton_ge_url` + `proton_ge_sha256` in `recipe.yml`; alternate SHA/URL via `PROTON_GE_ALT_*` in `core/runtime.lock`
- Halo pins **GE-Proton11-3** via `proton_ge_tag` (on-demand download; not the AppImage/Flatpak default bundle)
- Photoshop Medizin: **Test: Proton-GE 11-3** toggle (default off = GE-Proton10-28 healing; on = GE-Proton11-3 for issue #8 A/B)
- Launcher Proton badge uses the **per-recipe** effective tag (not only the global lock)

### Documentation
- ENTWICKLER / RECIPE-AUTHORING / PROJECT-LAYOUT / CORE-API / README: per-recipe Proton pins

## [1.1.33] - 2026-08-06

### Added
- **Halo Campaign Evolved:** system-tuned graphics quality presets (`HALO_GFX_PRESET`: ultra_low → ultra; default **Recommended / RTX 2060 / 1080p144**)
- Halo: optional **Launch via Steam** (Non-Steam shortcut, Proton choice, Steam grid art, soft low-latency under Steam)
- **Master PDF Editor** official recipe (BYOS MSI 5.9; optional pack `fix/`; `recipe_master_pdf_editor::run_msi` / `finalize`)
- Medizin `type: choice` combos (presets / Steam Proton) in the launcher

### Changed
- Halo VRAM soft caps follow the preset (ultra_low–high); `HALO_GFX_VRAM_6GB` only **forces** caps (e.g. on Ultra)
- Steam Non-Steam path: do not kill/restart Steam on every launch when shortcut already exists
- Recipe manifest generator skips `__pycache__` / `.pyc`
- Docs / README / catalog: 6 official recipes, 5 categories; Halo + Master PDF author notes

### Removed
- **photoshop-m0nkrus-220** recipe (ISO-only duplicate of the standard 22.0.0.35 path)

### Fixed
- Winetricks install steps ensure `LOG_DIR` before package loops
- Flatpak / runtime pin adjustments for reproducible builds
- CI: restore valid `release.yml` (column-0 heredoc broke YAML / `workflow_dispatch`); changelog notes via `scripts/changelog-release-notes.py`

### Documentation
- USER-GUIDE / CATALOG: Halo Medizin presets + Steam medicine; choice YAML example for authors
- INSTALLER / ENTWICKLER: Master PDF MSI pattern; drop m0nkrus-220 references
- Halo `info.de.md` / `info.en.md` aligned with presets and Steam behaviour
- Master PDF: user-facing docs use BYOS `fix/` only (Rezeptor ships neither MSI nor fix)

## [1.1.32] - 2026-08-05

### Fixed
- Flatpak build: pin `winetricks` to a commit URL with a stable SHA256 (upstream `master` tip moved and broke CI)

### Documentation
- README recipe count corrected to **6** official recipes
- Catalog / Halo blurb: offline login, Medizin, BYOS trainer

## [1.1.31] - 2026-08-05

### Added
- **Halo Campaign Evolved** recipe published publicly (ElAmigos/RUNE, Proton-GE 11)
- Offline Xbox/XAL login path (`SteamDeck=1`), modern MSVC CRT (14.40+), real `libHttpClient`
- Medizin graphics options: clear image, lower mouse latency (winewayland + vkd3d frame queue), optional VRR / 6 GB VRAM
- BYOS trainer deploy from Medizin (pick EXE or folder → `trainer/`)
- Halo recipe tests (`tests/test_recipe_halo.bats`, trainer deploy bats)

### Changed
- Launcher Medizin UI: trainer folder/EXE picker and deploy helpers
- Official catalog now lists **6** product recipes (Halo public)

### Removed
- **House of Ashes** recipe (early experiment, not maintained)
- **ZA4 trainer** recipe (early experiment, not maintained)

### Fixed
- Halo sign-in crash from outdated MSVC CRT / stub HTTP client under Proton
- High mouse input lag on KDE Wayland (enable real `winewayland.drv`, reduce swapchain latency)

## [3.0.5] - 2026-01-12

### Added
- **Wine 11.0 Support**: Added proper detection and handling for Wine 11.0
  - Wine 11.0 has fully supported WoW64 mode (no longer experimental)
  - Wine 11.0 is now treated differently from Wine 10.x (no warnings)
  - Wine 10.x warnings remain (experimental WoW64 mode)

### Improved
- **Wine Version Detection**: Better distinction between Wine 10.x (experimental) and Wine 11.0+ (fully supported)
  - Wine 10.x: Shows warning about experimental WoW64 mode
  - Wine 11.0+: No warnings, standard timeouts (WoW64 fully supported)
  - Wine 9.x: Still recommended for maximum stability
- **Version Selection Menu**: Updated recommendations to include Wine 11.0+ as viable option

### Fixed
- **WoW64 Warnings**: Fixed incorrect warnings for Wine 11.0+ - WoW64 is fully supported in 11.0, not experimental

## [3.0.4] - 2026-01-12

### Fixed
- **Copyright**: Updated copyright notice to "Sunny C." in setup.sh banner

### Removed
- **Icon Issue Warning**: Removed outdated "Known Issue" about icon display problems in KDE - icons now work correctly

### Improved
- **Documentation**: Cleaned up README files by removing obsolete warnings

## [3.0.3] - 2026-01-12

### Fixed
- **Version Display**: Fixed version confusion - VERSION file now correctly shows installed version (3.0.1), GitHub shows latest release (3.0.2)
- **Banner Display**: Banner now correctly shows "Photoshop Installer v3.0.1 - Github v3.0.2" format

### Removed
- **Cache System**: Removed unnecessary caching mechanism from update check - GitHub API is now queried directly on each call (simple and reliable)

### Improved
- **Update Check**: Simplified `update::get_latest_version()` - no cache, direct API call with timeout protection
- **Code Cleanup**: Removed all cache-related variables and logic (`UPDATE_CACHE_FILE`, `UPDATE_CACHE_TTL`)

## [3.0.2] - 2026-01-11

### Fixed
- **Banner Version Display**: Fixed GitHub version detection - now correctly shows both local and GitHub versions (e.g., "v3.0.0 - Github v3.0.1")
- **Banner Width Consistency**: Header and footer now have consistent width (25 characters each)
- **PS Logo Colors**: Fixed logo color scheme - `████` blocks now use `C_CYAN` to match banner frame, PS text retains `C_BLUE_LIGHT` for contrast
- **System Info Enhancement**: Added architecture detection (64-bit/ARM64) and GPU information to system info display
- **VERSION File Update Logic**: VERSION file is now automatically updated after `git pull` with the latest GitHub release version
- **VERSION File Initialization**: Added fallback logic to create VERSION file if it doesn't exist (GitHub API → git tags → CHANGELOG)

### Added
- **VERSION File Management**: 
  - New function `update::init_version_file()` - Creates VERSION file on first run if missing
  - New function `update::update_version_file()` - Updates VERSION file after successful git pull
  - Automatic initialization in `setup.sh` on startup
- **Enhanced System Info**: 
  - Architecture display: Shows "(64-bit)" for x86_64, "(ARM64)" for aarch64
  - GPU detection: Prioritizes `nvidia-smi`, falls back to `lspci` and `glxinfo`
  - GPU names are truncated to ~25 characters for display
- **Logo Enhancements**: Added "Linux" and "2021" text to PS logo for better visual identification

### Improved
- **Banner Display**: Consistent banner width calculation for header and footer
- **Version Tracking**: VERSION file is now properly maintained and synchronized with GitHub releases
- **Update Process**: After `git pull`, VERSION file is automatically updated to match the installed release version

## [3.0.0] - 2026-01-11

### Major Release - Complete Toolset

This release represents a complete transformation of the project from a simple installer into a comprehensive, production-ready toolset for running Photoshop on Linux. The modular architecture, extensive feature set, and professional polish make this a milestone release.

**Critical Fixes in this Release:**
- Fixed Photoshop startup issues: Launcher now properly exports environment variables and uses `nohup` to prevent premature termination
- Fixed `finish_installation()` not being called: Added error handling to prevent script termination when `launcher()` fails
- Fixed `agent_debug_log` errors: Removed all debug log calls and added dummy function to prevent launcher crashes
- Fixed `output::section` logging: Now properly logs to file for debugging
- Fixed Wine version selection message: Removed incorrect message about window opening (it's a text menu, not a window)
- Fixed WICHTIG message formatting: Restored consistent `output::header` format instead of `output::box`

### Added
- **Complete modular architecture**: Separated concerns into dedicated modules (sharedFuncs, output, security, checkpoint, system, update, i18n)
- **Troubleshoot module**: Automatic diagnosis and fixes for common issues (GPU settings, VC++ runtimes, log analysis)
- **Camera Raw installer**: Automated installation with MD5 verification and Wine silent mode
- **Update check system**: GitHub API integration with caching (24h TTL) and timeout protection
- **Checkpoint/Rollback system**: Safe installation with recovery points (create, list, rollback, cleanup)
- **Security module**: Path validation, safe operations, shell injection prevention
- **System information module**: Cross-distro system detection and reporting
- **Output module**: Consistent formatting with Quiet/Verbose support, responsive design
- **i18n system**: External language files (DE/EN) with locale detection and fallbacks
- **Pre-check script**: Detailed system validation with distro-specific install hints
- **Wine configuration launcher**: Interactive winecfg with tips and security checks
- **Kill-Photoshop utility**: Force termination of stuck processes (wineserver -k + pkill)
- **File opening support**: Launcher accepts files as parameters ("Open with Photoshop")
- **Log rotation with gzip**: Automatic compression of old logs to save disk space
- **winepath support**: Accurate Linux-to-Windows path conversion with sed fallback
- **Unified notification system**: Consistent notify-send handling across all scripts
- **Responsive UI**: Banner, boxes, and headers adapt to terminal width (40-80 chars)
- **Quiet/Verbose flags**: `--quiet` / `-q` and `--verbose` / `-v` for CI/testing and debugging
- **Portable log rotation**: GNU find / BSD/macOS fallback with nullglob support
- **Desktop entry backup**: Prevents data loss when overwriting existing entries
- **Enhanced shell injection checks**: Comprehensive pattern matching for security
- **Official VC++ installer**: Microsoft Visual C++ 2015-2022 Redistributable x64 (avoids ARM64 DLL issues)
- **Wine 10.x WOW64 detection**: Extended initialization timeouts (up to 90s) with user warnings
- **Additional DLL-Overrides**: d3d11, dxgi, d3dcompiler_47/43, d2d1, opcservices for better graphics compatibility
- **Post-installation tips**: Virtual Desktop, GPU settings, documentation links

### Removed
- **Proton GE support completely removed** - Only Wine Standard and Wine Staging supported now
- `.NET Framework 4.8` installation option (not required for Photoshop 2021, caused hangs under Wine 10.x)
- All AI-agent specific debug logging (`agent_debug_log`, `#region agent` / `#endregion` markers)
- Redundant `INSTALLATION_LOG` alias
- Redundant Visual C++ runtime installations (vcrun2010-2019 removed, only 2015-2022 kept)
- All commented-out code remnants from Proton GE removal
- Redundant find-in-find calls in log rotation

### Improved
- **Modular architecture**: Clean separation of concerns, maintainable codebase
- **Log rotation**: Now compresses old logs with gzip before deletion, works on BSD/macOS systems
- **Update check**: Timeout protection (10s connect, 30s total) prevents hanging on slow connections
- **All output functions**: Now respect `QUIET` mode (info, success, warning, step, substep, header)
- **Debug logs**: Only shown in `VERBOSE` mode, always logged to files
- **Menu navigation**: "Photoshop deinstallieren" renamed to "Photoshop deinstallieren + Killer"
- **Menu navigation**: All submenus allow return to main menu (including troubleshooting)
- **Consistent output formatting**: Removed double success messages, fixed spacing issues
- **Better progress feedback**: Clearer download/installation steps during installation
- **Wine 10.x WOW64 mode handling**: Extended initialization timeouts (up to 90s) and user warning
- **DLL-Overrides**: Added d3d11, dxgi, d3dcompiler_47/43, d2d1, opcservices for better graphics compatibility
- **GPU acceleration**: Properly disabled by default (GPUForce 0 in PSUserConfig.txt + Registry tweaks)
- **Icon display**: Improved icon caching and desktop entry handling
- **Launcher**: Desktop entry creation no longer blocks installation (SKIP_COMMAND_CREATION)
- **Error handling**: `|| true` statements replaced with proper `log_warning` calls for better debugging
- **sed pattern for alias removal**: Now uses exact match (`^alias photoshop=`) instead of substring match
- **Visual C++ installation**: Now uses official Microsoft installer to avoid ARM64 DLL architecture issues
- **Installation flow**: More streamlined, less redundant component installations
- **Path conversion**: Uses `winepath -w` for accuracy, falls back to `sed` if unavailable
- **Notifications**: Unified `send_notification()` function for consistent handling
- **Photoshop startup**: Uses `nohup` to prevent premature termination, exports all required environment variables
- **Error recovery**: `finish_installation()` now always called even if `launcher()` fails
- **Logging**: Enhanced logging for Photoshop startup process (PID tracking, error messages)

### Fixed
- Fixed misleading comments (e.g., GPUForce value descriptions)
- Fixed regex warnings in `[[ "$dirname" =~ "2022" ]]` (removed quotes from regex patterns)
- Fixed syntax errors from Proton GE removal (empty `;;` in case statements)
- Fixed `local` outside function linter errors (removed all Proton GE function remnants)
- Fixed double "Photoshop Installation abgeschlossen" messages
- Fixed script hanging after "Desktop-Verknüpfung erstellt"
- Fixed `notify-send` icon display issues
- Fixed menu indentation inconsistencies (Toggle alignment)
- Fixed empty input handling in finish_installation() prompts
- Fixed redundant VC++ installations (removed 2010-2019, kept only 2015-2022)
- Consistent notify-send error handling across all scripts

### Changed
- **Project structure**: Modular architecture replaces monolithic script approach
- **Version numbering**: Jump to v3.0.0 to reflect major architectural changes
- Log rotation: GNU find `-printf` preferred, `ls -t` as BSD/macOS fallback, gzip compression added
- Visual C++ installation: Now uses official Microsoft installer (vc_redist.x64.exe) instead of winetricks
- Wine selection: Removed Proton GE option, only Wine Standard/Staging available
- Installation flow: More streamlined, less redundant component installations
- Header/Box width: Now responsive (40-80 characters based on `tput cols`)
- Error messages: More descriptive and user-friendly
- Logging: All critical operations now log warnings instead of silently failing
- Debug output: Completely removed from console during installation (only in logs or with --verbose)

### Security
- Enhanced `security::safe_eval()`: Now checks for shell injection characters (`;`, `&`, `|`, backticks, `$()`, `${}`)
- Desktop entry: Backup created before overwriting
- Path validation: Improved checks against system directory access
- WINEPREFIX validation: Prevents manipulation and system directory access

### Performance
- Log rotation: Cached find results reduce I/O operations, gzip compression saves disk space
- Installation: Removed redundant component installations (only necessary ones kept)
- Update check: Caching (24h TTL) reduces API calls

## [2.3.0] - 2026-01-XX

### Added
- `--quiet` / `-q` flag: Suppress all output except errors (useful for CI/testing)
- `--verbose` / `-v` flag: Show debug logs on console
- Portable log rotation with GNU find / BSD/macOS fallback
- Improved notify-send handling with success/failure logging
- `output::empty_line()` function for consistent empty line output
- Post-installation tips display (Virtual Desktop, GPU settings, documentation links)
- Responsive header width using `tput cols` (adapts to terminal size, clamped 40-80 chars)
- Desktop entry backup before overwriting (prevents data loss)
- Enhanced shell injection checks in `security::safe_eval()` (checks for `;`, `&`, `|`, backticks, command substitution)
- Official Microsoft Visual C++ 2015-2022 Redistributable x64 installer (replaces winetricks vcrun2019 to avoid ARM64 DLL issues)
- Better error logging for registry operations (wine reg add commands now log warnings on failure)
- Wine 10.x WOW64 mode detection with extended initialization timeouts (up to 90s)
- Additional DLL-Overrides for better graphics compatibility (d3d11, dxgi, d3dcompiler_47/43, d2d1, opcservices)
- i18n strings for post-installation tips (DE/EN)

### Removed
- **Proton GE support completely removed** - Only Wine Standard and Wine Staging supported now
- `.NET Framework 4.8` installation option (not required for Photoshop 2021, caused hangs under Wine 10.x)
- All AI-agent specific debug logging (`agent_debug_log`, `#region agent` / `#endregion` markers)
- Redundant `INSTALLATION_LOG` alias
- Redundant Visual C++ runtime installations (vcrun2010-2019 removed, only 2015-2022 kept)
- All commented-out code remnants from Proton GE removal
- Redundant find-in-find calls in log rotation

### Improved
- Log rotation now works on BSD/macOS systems (uses `ls -t` fallback with nullglob)
- Menu navigation: "Photoshop deinstallieren" renamed to "Photoshop deinstallieren + Killer"
- Menu navigation: All submenus now allow return to main menu (including troubleshooting)
- Consistent output formatting: Removed double success messages, fixed spacing issues
- Better progress feedback during installation (clearer download/installation steps)
- Wine 10.x WOW64 mode handling with extended initialization timeouts (up to 90s) and user warning
- DLL-Overrides: Added d3d11, dxgi, d3dcompiler_47/43, d2d1, opcservices for better graphics compatibility
- GPU acceleration: Properly disabled by default (GPUForce 0 in PSUserConfig.txt + Registry tweaks)
- Icon display: Improved icon caching and desktop entry handling
- Launcher: Desktop entry creation no longer blocks installation (SKIP_COMMAND_CREATION)
- Error handling: `|| true` statements replaced with proper `log_warning` calls for better debugging
- `sed` pattern for alias removal: Now uses exact match (`^alias photoshop=`) instead of substring match
- Log rotation: Cached find results for better performance (avoids multiple find calls)
- All output functions now respect `QUIET` mode (info, success, warning, step, substep)
- Debug logs only shown in `VERBOSE` mode
- Spinner disabled in quiet mode (just logs to file)
- Visual C++ installation: Now uses official Microsoft installer to avoid ARM64 DLL architecture issues
- Installation flow: More streamlined, less redundant component installations

### Fixed
- Fixed misleading comments (e.g., GPUForce value descriptions)
- Fixed regex warnings in `[[ "$dirname" =~ "2022" ]]` (removed quotes from regex patterns)
- Fixed syntax errors from Proton GE removal (empty `;;` in case statements)
- Fixed `local` outside function linter errors (removed all Proton GE function remnants)
- Fixed double "Photoshop Installation abgeschlossen" messages
- Fixed script hanging after "Desktop-Verknüpfung erstellt"
- Fixed `notify-send` icon display issues
- Fixed menu indentation inconsistencies (Toggle alignment)
- Fixed empty input handling in finish_installation() prompts
- Fixed redundant VC++ installations (removed 2010-2019, kept only 2015-2022)
- Consistent notify-send error handling across all scripts

### Changed
- Log rotation: GNU find `-printf` preferred, `ls -t` as BSD/macOS fallback
- Visual C++ installation: Now uses official Microsoft installer (vc_redist.x64.exe) instead of winetricks to avoid ARM64 DLL issues
- Wine selection: Removed Proton GE option, only Wine Standard/Staging available
- Installation flow: More streamlined, less redundant component installations
- Header/Box width: Now responsive (40-80 characters based on `tput cols`)
- Error messages: More descriptive and user-friendly
- Logging: All critical operations now log warnings instead of silently failing
- Debug output: Completely removed from console during installation (only in logs or with --verbose)

### Security
- Enhanced `security::safe_eval()`: Now checks for shell injection characters (`;`, `&`, `|`, backticks, `$()`, `${}`)
- Desktop entry: Backup created before overwriting
- Path validation: Improved checks against system directory access

### Performance
- Log rotation: Cached find results reduce I/O operations
- Installation: Removed redundant component installations (only necessary ones kept)

## [2.2.x] - Previous versions

See git history for previous changelog entries.
