#!/bin/sh
# Run every Piano Tiles self-checking testbench with Verilator 5.
#
# Usage, from any directory:
#   sh scripts/run_all_tests.sh
#
# Optional overrides:
#   PT_VERILATOR=/path/to/verilator PT_TIMEOUT=180 sh scripts/run_all_tests.sh

set -u

case "$0" in
    */*) SCRIPT_PATH=${0%/*} ;;
    *)   SCRIPT_PATH=. ;;
esac
SCRIPT_DIR=$(CDPATH= cd "$SCRIPT_PATH" && pwd)
PROJECT_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

PT_VERILATOR=${PT_VERILATOR:-verilator}
PT_TIMEOUT=${PT_TIMEOUT:-180}
# Keep all lint diagnostics visible, but do not let warnings prevent a compiled
# self-checking testbench from running.  PASS/FAIL is decided by compilation,
# simulation exit status, and the bench's own assertions.
VFLAGS="-Wall -Wno-fatal -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND --trace --timing --assert"

if ! command -v "$PT_VERILATOR" >/dev/null 2>&1; then
    echo "ERROR: Verilator was not found. Install Verilator 5 or set PT_VERILATOR."
    exit 2
fi

VERILATOR_VERSION=$($PT_VERILATOR --version 2>/dev/null || true)
case "$VERILATOR_VERSION" in
    "Verilator 5."*) ;;
    *)
        echo "ERROR: Verilator 5 is required; found: ${VERILATOR_VERSION:-unknown version}"
        exit 2
        ;;
esac

for tool in make timeout find sed grep awk mktemp tr wc sort head tail basename mkdir rm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required command '$tool' was not found."
        exit 2
    fi
done

# Restrict discovery to intentional source locations. This prevents generated
# Quartus/simulator files, report evidence, or deliberately broken examples
# elsewhere in the repository from entering the submitted regression suite.
SOURCE_ROOTS="rtl smoke_test tb"
SOURCES=$(find $SOURCE_ROOTS -type f \( -name '*.sv' -o -name '*.v' -o -name '*.svh' \) -print | sort)
TESTS=$(find tb -type f \( -name '*_tb.sv' -o -name '*_tb.v' \) -print | sort)

if [ -z "$TESTS" ]; then
    echo "ERROR: no testbenches were found under tb/."
    exit 1
fi

# Fail early on empty HDL, which otherwise produces misleading library lookup
# errors when a same-named module is requested.
empty=0
for source in $SOURCES; do
    if [ ! -s "$source" ] || [ "$(tr -d ' \t\r\n' < "$source" | wc -c)" -eq 0 ]; then
        echo "EMPTY  $source"
        empty=$((empty + 1))
    fi
done
if [ "$empty" -ne 0 ]; then
    echo "ERROR: $empty empty HDL source file(s)."
    exit 1
fi

# Verilator library/include search paths for DUT dependencies.
SOURCE_DIRS=$(printf '%s\n' "$SOURCES" | sed 's|/[^/]*$||' | sort -u)
SEARCH_FLAGS="-Irtl/common"
for source_dir in $SOURCE_DIRS; do
    SEARCH_FLAGS="$SEARCH_FLAGS -y $source_dir"
done

BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/piano_tiles_verilator.XXXXXX") || exit 1
trap 'rm -rf "$BUILD_ROOT"' EXIT HUP INT TERM

pass=0
fail=0

for test_file in $TESTS; do
    test_name=$(basename "$test_file")
    test_name=$(printf '%s' "$test_name" | sed 's/\.sv$//; s/\.v$//')
    log_file="$BUILD_ROOT/$test_name.log"
    build_dir="$BUILD_ROOT/$test_name"

    # The filename, declared top module and --top-module value must agree.
    if ! grep -qE "^[[:space:]]*module[[:space:]]+$test_name([[:space:];(#]|$)" "$test_file"; then
        declared=$(grep -oE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$test_file" \
            | head -1 | awk '{print $2}')
        echo "FAIL  $test_name  (declares '${declared:-no module}' instead)"
        fail=$((fail + 1))
        continue
    fi

    mkdir "$build_dir"
    if timeout "$PT_TIMEOUT" "$PT_VERILATOR" $VFLAGS $SEARCH_FLAGS \
            +libext+.v+.sv --top-module "$test_name" \
            --Mdir "$build_dir" --cc "$test_file" --main --exe \
            >"$log_file" 2>&1 \
        && timeout "$PT_TIMEOUT" make -s -C "$build_dir" -f "V$test_name.mk" "V$test_name" \
            >>"$log_file" 2>&1 \
        && (cd "$build_dir" && timeout "$PT_TIMEOUT" "./V$test_name") >>"$log_file" 2>&1 \
        && grep -q "PASS" "$log_file"
    then
        echo "PASS  $test_name"
        pass=$((pass + 1))
    else
        echo "FAIL  $test_name"
        tail -40 "$log_file"
        fail=$((fail + 1))
    fi
done

echo "-----"
echo "$pass passed, $fail failed"

[ "$fail" -eq 0 ]
