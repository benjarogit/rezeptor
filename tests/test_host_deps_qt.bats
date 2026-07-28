#!/usr/bin/env bats
# host_deps Qt xcb-cursor package mapping (multi-distro)

load test_helper

@test "host_deps maps qt_xcb_cursor packages for apt/pacman/dnf/zypper" {
    run python3 "$BATS_TEST_DIRNAME/test_host_deps_qt.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "AppRun documents multi-distro libxcb-cursor install hints" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    grep -q 'libxcb-cursor0' "$ROOT/AppDir/AppRun"
    grep -q 'pacman -S libxcb-cursor' "$ROOT/AppDir/AppRun"
    grep -q 'dnf install libxcb-cursor' "$ROOT/AppDir/AppRun"
    grep -q 'zypper install libxcb-cursor0' "$ROOT/AppDir/AppRun"
}

@test "build-appimage pins libxcb-cursor0 for AppDir usr/lib" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    grep -q 'libxcb-cursor0_0.1.4-1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q 'a4b3c32dc008275ffcacccc1c77c030f01aad38e232e05d5ad116b76656c607c' \
        "$ROOT/scripts/build-appimage.sh"
}
