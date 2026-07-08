#!/usr/bin/env bash
# wineboot / winecfg helpers via Proton-GE

photoshop_setup::wine_binary() {
    wine_runtime::export_env 2>/dev/null || true
    if [ -n "${WINE_RUNTIME_BIN:-}" ] && [ -x "${WINE_RUNTIME_BIN}" ]; then
        echo "$WINE_RUNTIME_BIN"
    elif [ -n "${WINE:-}" ] && [ -x "${WINE}" ]; then
        echo "$WINE"
    else
        type -P wine 2>/dev/null || echo "wine"
    fi
}

photoshop_setup::run_winecfg() {
    local wine_binary
    wine_binary="$(photoshop_setup::wine_binary)"
    "$wine_binary" winecfg "$@"
}

photoshop_setup::kill_all_wineservers() {
    local wine_binary
    wine_binary="$(photoshop_setup::wine_binary)"
    "$wine_binary" wineserver -k 2>/dev/null || true
    pkill -9 wineserver 2>/dev/null || true
}
