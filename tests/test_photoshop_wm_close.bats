#!/usr/bin/env bats
# issue #10: wm close must target Photoshop windows only (never title substring)

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    FAKEBIN="$TMP/bin"
    mkdir -p "$FAKEBIN"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-photoshop-cleanup.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "wm_class_is_photoshop accepts Wine Photoshop.exe class" {
    recipe_photoshop::_wm_class_is_photoshop 'photoshop.exe.Photoshop'
    recipe_photoshop::_wm_class_is_photoshop 'Photoshop.exe'
    recipe_photoshop::_wm_class_is_photoshop 'Photoshop.Photoshop'
    run recipe_photoshop::_wm_class_is_photoshop 'yandex-browser.Yandex-browser'
    [ "$status" -ne 0 ]
    run recipe_photoshop::_wm_class_is_photoshop 'navigator.Firefox'
    [ "$status" -ne 0 ]
}

@test "wm_close_photoshop closes by class id, not by title substring" {
    cat >"$FAKEBIN/wmctrl" <<'EOF'
#!/bin/sh
# Log invocations; -lx lists fake windows; -ic records close by id.
log="${WMCTRL_LOG:?}"
printf '%s\n' "$*" >>"$log"
case "$1" in
    -lx)
        cat <<'LIST'
0x1000001  0  yandex-browser.Yandex-browser  host  Adobe Photoshop CC 2021 — GitHub
0x1000002  0  photoshop.exe.Photoshop  host  Adobe Photoshop 2021
0x1000003  0  navigator.Firefox  host  Photoshop tips
LIST
        ;;
    -ic)
        echo "CLOSE:$2" >>"$log"
        ;;
    -c)
        echo "TITLE_CLOSE:$2" >>"$log"
        ;;
esac
EOF
    chmod +x "$FAKEBIN/wmctrl"
    # No xprop → class fallback; hide real xdotool so we don't touch the session.
    cat >"$FAKEBIN/xprop" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$FAKEBIN/xprop"
    cat >"$FAKEBIN/xdotool" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$FAKEBIN/xdotool"
    export WMCTRL_LOG="$TMP/wmctrl.log"
    : >"$WMCTRL_LOG"
    # Empty prefix PIDs → class-only path
    recipe_photoshop::_photoshop_pids() { return 0; }
    PATH="$FAKEBIN:$PATH" recipe_photoshop::_wm_close_photoshop
    grep -q 'CLOSE:0x1000002' "$WMCTRL_LOG"
    ! grep -q 'CLOSE:0x1000001' "$WMCTRL_LOG"
    ! grep -q 'CLOSE:0x1000003' "$WMCTRL_LOG"
    ! grep -q 'TITLE_CLOSE:' "$WMCTRL_LOG"
}

@test "wm_close_photoshop closes by _NET_WM_PID of Photoshop.exe" {
    cat >"$FAKEBIN/wmctrl" <<'EOF'
#!/bin/sh
log="${WMCTRL_LOG:?}"
printf '%s\n' "$*" >>"$log"
case "$1" in
    -lx)
        cat <<'LIST'
0x1000001  0  yandex-browser.Yandex-browser  host  Adobe Photoshop CC 2021 — GitHub
0x1000002  0  wine.Photoshop  host  Adobe Photoshop 2021
0x1000003  0  navigator.Firefox  host  Photoshop tips
LIST
        ;;
    -ic)
        echo "CLOSE:$2" >>"$log"
        ;;
esac
EOF
    chmod +x "$FAKEBIN/wmctrl"
    cat >"$FAKEBIN/xprop" <<'EOF'
#!/bin/sh
# xprop -id 0x… _NET_WM_PID
id=""
while [ $# -gt 0 ]; do
    case "$1" in
        -id) id="$2"; shift 2 ;;
        *) shift ;;
    esac
done
case "$id" in
    0x1000001) echo '_NET_WM_PID(CARDINAL) = 111' ;;
    0x1000002) echo '_NET_WM_PID(CARDINAL) = 222' ;;
    0x1000003) echo '_NET_WM_PID(CARDINAL) = 333' ;;
esac
EOF
    chmod +x "$FAKEBIN/xprop"
    cat >"$FAKEBIN/xdotool" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$FAKEBIN/xdotool"
    export WMCTRL_LOG="$TMP/wmctrl.log"
    : >"$WMCTRL_LOG"
    recipe_photoshop::_photoshop_pids() { printf '%s\n' 222; }
    recipe_photoshop::_related_pids() { cat; }
    # Class wine.Photoshop would NOT match class filter — PID must win.
    PATH="$FAKEBIN:$PATH" recipe_photoshop::_wm_close_photoshop
    grep -q 'CLOSE:0x1000002' "$WMCTRL_LOG"
    ! grep -q 'CLOSE:0x1000001' "$WMCTRL_LOG"
    ! grep -q 'CLOSE:0x1000003' "$WMCTRL_LOG"
}

@test "wm_close_photoshop closes parent-PID window of Photoshop.exe" {
    cat >"$FAKEBIN/wmctrl" <<'EOF'
#!/bin/sh
log="${WMCTRL_LOG:?}"
printf '%s\n' "$*" >>"$log"
case "$1" in
    -lx)
        echo '0x1000002  0  wine.Something  host  Adobe Photoshop 2021'
        ;;
    -ic)
        echo "CLOSE:$2" >>"$log"
        ;;
esac
EOF
    chmod +x "$FAKEBIN/wmctrl"
    cat >"$FAKEBIN/xprop" <<'EOF'
#!/bin/sh
echo '_NET_WM_PID(CARDINAL) = 50'
EOF
    chmod +x "$FAKEBIN/xprop"
    cat >"$FAKEBIN/xdotool" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$FAKEBIN/xdotool"
    export WMCTRL_LOG="$TMP/wmctrl.log"
    : >"$WMCTRL_LOG"
    # Photoshop.exe is 99; Wine put _NET_WM_PID=50 (parent) on the window.
    recipe_photoshop::_photoshop_pids() { printf '%s\n' 99; }
    recipe_photoshop::_related_pids() { printf '%s\n' 99 50; }
    PATH="$FAKEBIN:$PATH" recipe_photoshop::_wm_close_photoshop
    grep -q 'CLOSE:0x1000002' "$WMCTRL_LOG"
}

@test "related_pids reads the parent pid even when comm holds spaces" {
    # Wine comms like "Adobe Spaces He" break naive field splitting on
    # /proc/pid/stat, which dropped the parent window owner.
    mkdir -p "$TMP/proc/4242"
    printf '4242 (Adobe Spaces He) S 4200 4242 4242 0 -1 0\n' >"$TMP/proc/4242/stat"
    ppid="$(sed 's/.*) //' "$TMP/proc/4242/stat" | awk '{print $2}')"
    [ "$ppid" = "4200" ]
}

@test "wm_close asks the WM to close, never destroys the window" {
    # xdotool windowclose destroys the X window without telling Photoshop: it
    # keeps running windowless and never writes prefs (issue #10 regression).
    cat >"$FAKEBIN/wmctrl" <<'EOF'
#!/bin/sh
log="${WMCTRL_LOG:?}"
case "$1" in
    -lx) echo '0x1000002  0  photoshop.exe.Photoshop  host  Adobe Photoshop 2021' ;;
    -ic) echo "CLOSE:$2" >>"$log" ;;
esac
EOF
    chmod +x "$FAKEBIN/wmctrl"
    cat >"$FAKEBIN/xprop" <<'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "$FAKEBIN/xprop"
    cat >"$FAKEBIN/xdotool" <<'EOF'
#!/bin/sh
echo "XDOTOOL:$*" >>"${WMCTRL_LOG:?}"
EOF
    chmod +x "$FAKEBIN/xdotool"
    export WMCTRL_LOG="$TMP/wmctrl.log"
    : >"$WMCTRL_LOG"
    recipe_photoshop::_photoshop_pids() { return 0; }
    PATH="$FAKEBIN:$PATH" recipe_photoshop::_wm_close_photoshop
    grep -q 'CLOSE:0x1000002' "$WMCTRL_LOG"
    ! grep -q 'windowclose' "$WMCTRL_LOG"
    ! grep -q 'windowkill' "$WMCTRL_LOG"
}

@test "request_photoshop_exit waits instead of force-killing when Photoshop exits" {
    recipe_photoshop::photoshop_running() { return 0; }
    recipe_photoshop::_wm_close_photoshop() { return 0; }
    recipe_photoshop::_photoshop_windows_open() { return 1; }
    recipe_photoshop::wait_photoshop_gone() { return 0; }
    recipe_photoshop::_wine_taskkill() { echo "TASKKILL:$1" >>"$TMP/force.log"; }
    recipe_photoshop::_wm_alt_f4_photoshop() { echo ALT >>"$TMP/force.log"; }
    : >"$TMP/force.log"
    recipe_photoshop::request_photoshop_exit
    [ ! -s "$TMP/force.log" ]
}

@test "quit without a reachable window asks Wine to close before forcing" {
    # User already closed the window (✕ / Alt+F4 / File→Exit) but Photoshop.exe
    # hangs around: Quit must still try a normal close first (#10).
    recipe_photoshop::photoshop_running() { return 0; }
    recipe_photoshop::_photoshop_window_ids() { return 0; }
    recipe_photoshop::_photoshop_windows_open() { return 1; }
    recipe_photoshop::wait_photoshop_gone() { return 1; }
    recipe_photoshop::_pkill_pat() { echo "PKILL:${2:-TERM}" >>"$TMP/force.log"; }
    recipe_photoshop::_wine_taskkill() { echo "TASKKILL:$1" >>"$TMP/force.log"; }
    : >"$TMP/force.log"
    PATH="$FAKEBIN:$PATH" recipe_photoshop::request_photoshop_exit
    # Soft close request comes before the hard kill.
    head -1 "$TMP/force.log" | grep -q 'TASKKILL:0'
    grep -q 'TASKKILL:1' "$TMP/force.log"
}

@test "request_photoshop_exit forces when Photoshop hangs after the window is gone" {
    # Otherwise Quit waits forever, helpers stay in RAM and the next launch crashes.
    recipe_photoshop::photoshop_running() { return 0; }
    recipe_photoshop::_wm_close_photoshop() { return 0; }
    recipe_photoshop::_photoshop_windows_open() { return 1; }
    recipe_photoshop::wait_photoshop_gone() { return 1; }
    recipe_photoshop::_pkill_pat() { echo "PKILL:${2:-TERM}" >>"$TMP/force.log"; }
    recipe_photoshop::_wine_taskkill() { echo "TASKKILL:$1" >>"$TMP/force.log"; }
    : >"$TMP/force.log"
    PHOTOSHOP_EXIT_WAIT_S=1 recipe_photoshop::request_photoshop_exit
    grep -q 'TASKKILL:1' "$TMP/force.log"
    grep -q 'PKILL:9' "$TMP/force.log"
}

@test "cleanup_orphans kills CCLibrary and ends the prefix wineserver" {
    recipe_photoshop::_prefix() { printf '%s' "$TMP"; }
    recipe_photoshop::photoshop_running() { return 1; }
    recipe_photoshop::_pkill_pat() { echo "PKILL:$1" >>"$TMP/clean.log"; }
    wine_runtime::wineserver() { echo "WINESERVER:$*" >>"$TMP/clean.log"; }
    : >"$TMP/clean.log"
    recipe_photoshop::cleanup_orphans
    grep -q 'PKILL:CCLibrary' "$TMP/clean.log"
    grep -q 'PKILL:Adobe Spaces Helper' "$TMP/clean.log"
    grep -q 'WINESERVER:-k' "$TMP/clean.log"
}
