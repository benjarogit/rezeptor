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
    # No existing loop
    cat >"$bindir/losetup" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$bindir/udisksctl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  loop-setup) echo "Mapped file as /dev/loop99."; exit 0 ;;
  mount) echo "Mounted /dev/loop99 at $fake_mount."; exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$bindir/losetup" "$bindir/udisksctl"
    export PATH="$bindir:$PATH"

    local iso="$BATS_TEST_TMPDIR/game.iso"
    : >"$iso"

    unset RECIPE_ISO_MOUNT
    recipe_iso::mount "$iso"
    [ -n "${RECIPE_ISO_MOUNT:-}" ]
    [ -d "$RECIPE_ISO_MOUNT" ]
    [ "$RECIPE_ISO_MOUNT" = "$fake_mount" ]

    local polluted
    polluted="$(
        output::_gui_emit step "ISO mounten: demo.iso"
        output::_gui_emit info "ISO gemountet: $fake_mount"
        printf '%s\n' "$fake_mount"
    )"
    [ ! -d "$polluted" ]
}

@test "recipe_iso::mount reuses existing loop for same ISO" {
    export LAUNCHER_GUI=1
    export DATA_ROOT="$BATS_TEST_TMPDIR/data2"
    mkdir -p "$DATA_ROOT"

    local bindir="$BATS_TEST_TMPDIR/bin2"
    mkdir -p "$bindir"
    local fake_mount="$BATS_TEST_TMPDIR/mnt2"
    mkdir -p "$fake_mount"
    local iso="$BATS_TEST_TMPDIR/game2.iso"
    : >"$iso"
    local setup_count="$BATS_TEST_TMPDIR/loop_setup_count"
    : >"$setup_count"

    # Fake losetup -j: first call empty, after mount reports loop
    # We simulate reuse: losetup always reports existing after first "mount"
    cat >"$bindir/losetup" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-j" ]; then
  if [ -f "$BATS_TEST_TMPDIR/loop_ready" ]; then
    echo "/dev/loop7: [0000]:0 (\$2)"
  fi
  exit 0
fi
exit 0
EOF
    cat >"$bindir/findmnt" <<EOF
#!/usr/bin/env bash
# -S /dev/loop7 → mount
for a in "\$@"; do
  case "\$a" in
    /dev/loop7|/dev/loop99) echo "$fake_mount"; exit 0 ;;
  esac
done
exit 1
EOF
    cat >"$bindir/udisksctl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  loop-setup)
    echo 1 >>"$setup_count"
    echo "Mapped file as /dev/loop99."
    touch "$BATS_TEST_TMPDIR/loop_ready"
    # After setup, pretend losetup sees loop7 for reuse path on 2nd call —
    # first mount uses loop99 from udisks
    exit 0
    ;;
  mount) echo "Mounted /dev/loop99 at $fake_mount."; exit 0 ;;
  *) exit 0 ;;
esac
EOF
    chmod +x "$bindir/losetup" "$bindir/findmnt" "$bindir/udisksctl"
    export PATH="$bindir:$PATH"

    unset RECIPE_ISO_MOUNT
    recipe_iso::mount "$iso"
    [ "$RECIPE_ISO_MOUNT" = "$fake_mount" ]
    first_count="$(wc -l <"$setup_count" | tr -d ' ')"

    # Second mount: losetup -j finds loop → no new loop-setup
    touch "$BATS_TEST_TMPDIR/loop_ready"
    # Point existing to loop7 with findmnt
    cat >"$bindir/losetup" <<EOF
#!/usr/bin/env bash
[ "\$1" = "-j" ] && echo "/dev/loop7: [0000]:0 (\$2)" && exit 0
exit 0
EOF
    chmod +x "$bindir/losetup"

    recipe_iso::mount "$iso"
    second_count="$(wc -l <"$setup_count" | tr -d ' ')"
    [ "$second_count" = "$first_count" ]
    [ "$RECIPE_ISO_MOUNT" = "$fake_mount" ]
}
