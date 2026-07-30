#!/usr/bin/env bats
# Builtin- vs. native-DLL-Erkennung — darf nicht von der `file`-Version abhängen.
# Ubuntu 24.04 liefert file 5.45; dort fehlt die "WINE (DLL)"-Magic (erst ab 5.46).

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TMP="$(mktemp -d)"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-validate.sh"

    BUILTIN="$TMP/builtin.dll"
    NATIVE="$TMP/native.dll"
    printf 'MZ\0\0Wine builtin DLL\0padding' >"$BUILTIN"
    printf 'MZ\0\0This program cannot be run in DOS mode.\0' >"$NATIVE"

    # `file` wie auf Ubuntu 24.04: kennt WINE nicht, meldet alles als MS Windows.
    FAKEBIN="$TMP/bin"
    mkdir -p "$FAKEBIN"
    cat >"$FAKEBIN/file" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { echo "file-5.45"; exit 0; }
echo "$1: PE32 executable (DLL) (GUI) Intel 80386, for MS Windows"
EOF
    chmod +x "$FAKEBIN/file"
}

teardown() {
    rm -rf "$TMP"
}

@test "builtin wird auch mit altem file erkannt" {
    PATH="$FAKEBIN:$PATH" run recipe_validate::dll_is_wine_builtin "$BUILTIN"
    [ "$status" -eq 0 ]
}

@test "native gilt mit altem file weiterhin als nativ" {
    PATH="$FAKEBIN:$PATH" run recipe_validate::native_pe "$NATIVE"
    [ "$status" -eq 0 ]
}

@test "builtin ist nicht nativ — auch ohne WINE-Magic in file" {
    PATH="$FAKEBIN:$PATH" run recipe_validate::native_pe "$BUILTIN"
    [ "$status" -ne 0 ]
}

@test "msxml_is_native meldet builtin nicht als nativ" {
    PATH="$FAKEBIN:$PATH" run recipe_validate::msxml_is_native "$BUILTIN"
    [ "$status" -ne 0 ]
}

@test "fehlende DLL ist nie nativ" {
    run recipe_validate::native_pe "$TMP/gibtsnicht.dll"
    [ "$status" -ne 0 ]
}

@test "ohne nutzbares file bleibt die Erkennung korrekt" {
    mkdir -p "$TMP/nofile"
    printf '#!/usr/bin/env bash\nexit 127\n' >"$TMP/nofile/file"
    chmod +x "$TMP/nofile/file"

    PATH="$TMP/nofile:$PATH" run recipe_validate::native_pe "$BUILTIN"
    [ "$status" -ne 0 ]
    PATH="$TMP/nofile:$PATH" run recipe_validate::native_pe "$NATIVE"
    [ "$status" -eq 0 ]
}

@test "ie8_present verlangt natives mshtml, nicht nur iexplore.exe" {
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-adobe-setup.sh"
    export WINEPREFIX="$TMP/prefix"
    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64" \
        "$WINEPREFIX/drive_c/windows/system32" \
        "$WINEPREFIX/drive_c/Program Files/Internet Explorer"
    cp "$BUILTIN" "$WINEPREFIX/drive_c/Program Files/Internet Explorer/iexplore.exe"
    cp "$BUILTIN" "$WINEPREFIX/drive_c/windows/syswow64/mshtml.dll"
    cp "$BUILTIN" "$WINEPREFIX/drive_c/windows/system32/mshtml.dll"
    run adobe_setup::ie8_present
    [ "$status" -ne 0 ]

    cp "$NATIVE" "$WINEPREFIX/drive_c/windows/syswow64/mshtml.dll"
    run adobe_setup::ie8_present
    [ "$status" -eq 0 ]
}
