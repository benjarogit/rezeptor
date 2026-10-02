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

@test "build-appimage pins full Qt xcb-util family for AppDir usr/lib" {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    grep -q 'libxcb-icccm4_0.4.1-1.1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q 'f323194cb04cd4e5ae064fafec39db6dcf8a431cbd65a0bc53fa6c359862d8ff' \
        "$ROOT/scripts/build-appimage.sh"
    grep -q 'libxcb-image0_0.4.0-2_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q 'a475522faef7672ca065fdcd2594bc755bfcc4d819909f9d944e8c002b4460d1' \
        "$ROOT/scripts/build-appimage.sh"
    grep -q 'libxcb-keysyms1_0.4.0-1+b2_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q 'aed1436db9a3e63b10d00c4ed16248b5c82b5dd2963a83a761f406af65eb4b49' \
        "$ROOT/scripts/build-appimage.sh"
    grep -q 'libxcb-render-util0_0.3.9-1+b1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q 'be4b38a63e65c84e2f1322f044d05a9baa677e0f3dc68b742a0a109a3ff40ae9' \
        "$ROOT/scripts/build-appimage.sh"
    grep -q 'libxcb-util1_0.4.0-1+b1_amd64.deb' "$ROOT/scripts/build-appimage.sh"
    grep -q '4c48af51fb2ac1be0490067e7450aeda27bf6c6c395165de02199eee4835336f' \
        "$ROOT/scripts/build-appimage.sh"
}
