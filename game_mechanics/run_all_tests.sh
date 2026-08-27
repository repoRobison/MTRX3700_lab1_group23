#!/bin/sh
# run_all_tests.sh -- MTRX3700 Assignment 1, Piano Tiles
#
# FOLDER-AGNOSTIC BY DESIGN. It discovers every *_tb.sv / *_tb.v in the tree and
# passes EVERY directory containing sources to Verilator as a -y search path.
#
# Why not hardcode the folders: Verilator resolves `include from its -y search
# paths, so a folder that is not listed makes the build fail with
#   "Cannot find include file: game_params.svh ... Looked in: <wrong dir>"
# which points at the directory of the INCLUDING file, not the missing one.
# That error costs an hour the first time you see it. Discovering the dirs
# removes the failure mode entirely, and survives the group moving files.
#
# THREE GUARDS were added after they each cost real time:
#
#   1. EMPTY SOURCE FILES are reported by name and fail the run. Under Verilog
#      library lookup an empty file is WORSE than an absent one: -y finds it,
#      matches the module name, and reports the module as unresolvable rather
#      than missing. This turns a cryptic "Can't resolve module reference"
#      into "synchroniser.v is empty".
#
#   2. FILENAME / MODULE MISMATCH is reported before the build. --top is
#      derived from the filename, and library lookup resolves modules by
#      filename too, so a file named game_fsm_tb.sv declaring lane_fsm_tb can
#      never be found by either mechanism.
#
#   3. TIMEOUTS. A bench with no watchdog used to stall the whole suite
#      instead of failing it.
#
# -Wno-fatal is deliberately NOT passed. A warning stops the build. Do not
# widen VFLAGS to make a bench pass -- WIDTHTRUNC in particular is a genuine
# narrowing and must never join WIDTHEXPAND in the waiver list.

VFLAGS="-Wall -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND --trace --timing --assert"
TIMEOUT=180

SRCS=$(find . -name obj_dir -prune -o \( -name '*.sv' -o -name '*.v' -o -name '*.svh' \) -print | sort)

# ---- guard 1: empty sources ------------------------------------------------
empty=0
for f in $SRCS; do
  if [ ! -s "$f" ] || [ "$(tr -d ' \t\n' < "$f" | wc -c)" -eq 0 ]; then
    echo "EMPTY $f  -- delete it, or write it; it will shadow a real module"
    empty=$((empty+1))
  fi
done
if [ "$empty" -ne 0 ]; then
  echo "-----"
  echo "$empty empty source file(s); refusing to run."
  exit 1
fi

# every directory holding a .v/.sv/.svh, as -y flags
INCDIRS=$(echo "$SRCS" | sed 's|/[^/]*$||' | sort -u | sed 's|^|-y |' | tr '\n' ' ')

pass=0; fail=0
for tb in $(find . -name obj_dir -prune -o \( -name '*_tb.sv' -o -name '*_tb.v' \) -print | sort); do
  name=$(basename "$tb" | sed 's/\.sv$//; s/\.v$//')

  # ---- guard 2: the file must declare the module its name promises ---------
  if ! grep -qE "^[[:space:]]*module[[:space:]]+$name\b" "$tb"; then
    decl=$(grep -oE "^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*" "$tb" \
           | head -1 | awk '{print $2}')
    echo "FAIL  $name  (file declares module '${decl:-none}'; rename one to match the other)"
    fail=$((fail+1))
    continue
  fi

  rm -rf obj_dir
  # ---- guard 3: timeouts --------------------------------------------------
  if timeout $TIMEOUT verilator $VFLAGS $INCDIRS +libext+.v+.sv \
       --top "$name" --cc "$tb" --main --exe > "$name.log" 2>&1 \
     && timeout $TIMEOUT make -s -C obj_dir -f "V$name.mk" "V$name" >> "$name.log" 2>&1 \
     && timeout $TIMEOUT ./obj_dir/"V$name" >> "$name.log" 2>&1
  then echo "PASS  $name"; pass=$((pass+1))
  else echo "FAIL  $name  (see $name.log)"; fail=$((fail+1))
  fi
done

echo "-----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
