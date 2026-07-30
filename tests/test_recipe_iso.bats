#!/usr/bin/env bats
# ISO mount: Mountpunkt darf nicht mit GUI-@tags vermischt werden

load test_helper

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=/dev/null
    source "$ROOT/core/output.sh"
    # shellcheck source=/dev/null
    source "$ROOT/core/recipe-iso.sh"
}

@test "GUI tags must not be captured as ISO mount path" {
    export LAUNCHER_GUI=1
    local fake_mount="$BATS_TEST_TMPDIR/iso-mount"
    mkdir -p "$fake_mount"
    touch "$fake_mount/setup.exe"

    # Altes Anti-Pattern: $() fängt @step/@info + Pfad ein → kein gültiges Verzeichnis
    local polluted
    polluted="$(
        recipe_iso::_step "ISO mounten: demo.iso"
        recipe_iso::_info "ISO gemountet: $fake_mount"
        printf '%s\n' "$fake_mount"
    )"
    [ ! -d "$polluted" ]

    # Korrekt: Mount setzt RECIPE_ISO_MOUNT; Aufrufer nicht via $()
    export RECIPE_ISO_MOUNT="$fake_mount"
    local work_root="${RECIPE_ISO_MOUNT:-}"
    [ -d "$work_root" ]
    [ -f "$work_root/setup.exe" ]
}

@test "recipe_iso::mount sets RECIPE_ISO_MOUNT and avoids path-only capture" {
    export LAUNCHER_GUI=1
    export DATA_ROOT="$BATS_TEST_TMPDIR/data"
    mkdir -p "$DATA_ROOT"

    local bindir="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bindir"
    local fake_mount="$BATS_TEST_TMPDIR/mnt"
    mkdir -p "$fake_mount"
    cat >"$bindir/udisksctl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  loop-setup) echo "Mapped file as /dev/loop99."; exit 0 ;;
  mount) echo "Mounted /dev/loop99 at $fake_mount."; exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$bindir/udisksctl"
    export PATH="$bindir:$PATH"

    local iso="$BATS_TEST_TMPDIR/game.iso"
    : >"$iso"

    # Ohne \$() — sonst geht export RECIPE_ISO_MOUNT im Subshell verloren
    unset RECIPE_ISO_MOUNT
    recipe_iso::mount "$iso"
    [ -n "${RECIPE_ISO_MOUNT:-}" ]
    [ -d "$RECIPE_ISO_MOUNT" ]
    [ "$RECIPE_ISO_MOUNT" = "$fake_mount" ]

    # Altes \$()-Muster bliebe kaputt, weil @tags auf stdout landen
    local polluted
    polluted="$(
        output::_gui_emit step "ISO mounten: demo.iso"
        output::_gui_emit info "ISO gemountet: $fake_mount"
        printf '%s\n' "$fake_mount"
    )"
    [ ! -d "$polluted" ]
}
