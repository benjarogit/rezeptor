#!/usr/bin/env bats
# issue #10: wm close must use WM_CLASS, not window title (browser tabs)

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
    export WMCTRL_LOG="$TMP/wmctrl.log"
    : >"$WMCTRL_LOG"
    PATH="$FAKEBIN:$PATH" recipe_photoshop::_wm_close_photoshop
    grep -q 'CLOSE:0x1000002' "$WMCTRL_LOG"
    ! grep -q 'CLOSE:0x1000001' "$WMCTRL_LOG"
    ! grep -q 'CLOSE:0x1000003' "$WMCTRL_LOG"
    ! grep -q 'TITLE_CLOSE:' "$WMCTRL_LOG"
}
