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

@test "build-appimage pins Qt xcb xkbcommon libs for AppDir usr/lib" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    grep -q 'libxkbcommon-x11-0_1.5.0-1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q '9b34d760f0ca0f125419a6becc6492c489f0371953ef42caad3401199a497ff5' \
        "$ROOT/scripts/build-appimage.sh"
    grep -q 'libxkbcommon0_1.5.0-1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q 'e3fe045b9a33a101de1c5a912a4a10928db055c3f68930f47eccbb44d7c7d54e' \
        "$ROOT/scripts/build-appimage.sh"
    grep -q 'libxcb-xkb1_1.15-1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q '1dc2f0de8576b1855b451a7e2a7163ecb5be08f8384f49655414714b48f6fa1b' \
        "$ROOT/scripts/build-appimage.sh"
}
