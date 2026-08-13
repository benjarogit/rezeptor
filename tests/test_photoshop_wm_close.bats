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

@test "request_photoshop_exit does not force-kill after window is gone" {
    recipe_photoshop::photoshop_running() { return 0; }
    recipe_photoshop::_wm_close_photoshop() { :; }
    recipe_photoshop::_photoshop_windows_open() { return 1; }
    recipe_photoshop::wait_photoshop_gone() { return 0; }
    recipe_photoshop::_wine_taskkill() { echo "TASKKILL:$1" >>"$TMP/force.log"; }
    recipe_photoshop::_wm_alt_f4_photoshop() { echo ALT >>"$TMP/force.log"; }
    : >"$TMP/force.log"
    recipe_photoshop::request_photoshop_exit
    [ "${PHOTOSHOP_EXIT_GRACEFUL:-}" = "1" ]
    [ ! -s "$TMP/force.log" ]
}
