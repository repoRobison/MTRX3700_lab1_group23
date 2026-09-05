#!/usr/bin/env python3
"""compile_fpga.py, the full Quartus flow: analysis & synthesis, fit, assemble,
timing analysis.

    python scripts/compile_fpga.py

Run this on a machine with Quartus 18.1. Quartus is not available in the Ed
workspace, so you will need to run this on your own computer or the lab machines.
"""

import re
import sys
from pathlib import Path

import common

PROJECT = "demo"        # rename this if you rename the .qpf/.qsf files

# Warning IDs that a clean build of this scaffold produces, and why each one
# is harmless. The summary at the end of the build filters these out, so
# anything it does print is worth reading. If you meet another warning and
# convince yourself it is harmless, add its ID here with a reason.
BENIGN_WARNING_IDS = {
    "13410":  "output pin tied to a constant on purpose (held-off LED, blank HEX)",
    "13024":  "the summary line for the 13410s",
    "15705":  "the header line for the 15706s",
    "15706":  "pin assignment for board I/O this design does not use (demo.qsf "
              "deliberately carries the whole DE1-SoC pin map)",
    "171167": "the Fitter's summary line for the 15706s ('invalid' here just "
              "means 'assigned node not in this design')",
    "18236":  "parallel-compilation performance hint",
    "12473":  "parallel-compilation performance hint",
    "15714":  "drive strength / slew rate left at their defaults",
    "292013": "LogicLock advert (Lite edition has no subscription)",
}

# Warning lines in the reports look like:
#     Warning (13410): Pin "LEDR[7]" is stuck at GND
WARNING_RE = re.compile(r"^\s*(Critical Warning|Warning) \((\d+)\): (.*)$", re.M)


def warning_summary(report_paths):
    """Read every warning out of the compilation reports and split them into
    (benign_count, interesting_lines). Critical Warnings are never benign.
    """
    benign = 0
    interesting = []
    for report in report_paths:
        if not report.exists():
            continue
        for kind, wid, text in WARNING_RE.findall(report.read_text(errors="replace")):
            if kind == "Warning" and wid in BENIGN_WARNING_IDS:
                benign += 1
            else:
                line = f"{kind} ({wid}): {text}"
                if line not in interesting:      # the same warning can appear twice
                    interesting.append(line)
    return benign, interesting


def worst_slack(sta_report):
    """Returns the smallest timing slack in the report, or None if there are none.

    The timing analyser checks setup, hold, recovery times, removal and minimum pulse
    width, at several temperature and voltage combinations, and prints a worst case
    for each. Every one of them has to be met, so the number that matters is the
    minimum.

    The lines look like:
        Info (332146): Worst-case setup slack is 16.381
    """
    if not sta_report.exists():
        return None

    slacks = re.findall(r"Worst-case .* slack is\s+(-?\d+\.?\d*)",
                        sta_report.read_text(errors="replace"))
    if not slacks:
        return None
    return min(float(s) for s in slacks)


def main():
    common.chdir_to_project_root()

    common.require_tool("quartus_sh", "Install Quartus Prime Lite 18.1 and check it is on your PATH.")

    sof = Path("output_files") / f"{PROJECT}.sof"
    sta = Path("output_files") / f"{PROJECT}.sta.rpt"

    # Run the flow. It is a single command, but it does a lot of work:
    if common.run(["quartus_sh", "--flow", "compile", PROJECT]).returncode != 0:
        print()
        print(f"{common.C_FAIL}FAIL{common.C_OFF} Quartus reported errors. Search the output above for 'Error'.")
        return 1

    # A zero exit status is not proof of a bitstream: check the .sof is there.
    if not sof.exists():
        print()
        print(f"{common.C_FAIL}FAIL{common.C_OFF} the flow finished but {sof} was not produced.")
        return 1

    # Quartus exits 0 (success) even when the design FAILS TIMING. It assembles a .sof
    # regardless, and a board programmed with it can behave erratically in ways
    # that look like logic bugs. So we must check the timing slack ourselves rather
    # than trusting the exit status.
    slack = worst_slack(sta)
    timing_ok = True

    print()
    if slack is None:
        common.warn(f"No timing results found in {sta}. Is there an .sdc file with a")
        print("   create_clock in it? Without one, 'timing met' means nothing.")
    elif slack < 0:
        print(f"{common.C_FAIL}TIMING FAILED{common.C_OFF}  worst-case slack {slack} ns (all checks, all corners).")
        print("   The .sof was still built, but do not trust it: the design is not fast")
        print(f"   enough for its clock. Find the failing path in {sta}.")
        timing_ok = False
    else:
        print(f"{common.C_PASS}Timing met{common.C_OFF}  worst-case slack {slack} ns (all checks, all corners).")

    # Quartus is chatty: even this tiny scaffold compiles with dozens of
    # warnings, all of them explainable (see README). Filter the known-harmless
    # ones so that any warning actually worth reading stands out.
    reports = [Path("output_files") / f"{PROJECT}.{tool}.rpt"
               for tool in ("map", "fit", "asm", "sta")]
    benign, interesting = warning_summary(reports)
    if interesting:
        common.warn(f"{len(interesting)} warnings to read"
                    f" ({benign} known-harmless ones filtered out):")
        for line in interesting:
            print(f"   {line}")
    else:
        common.info(f"Warnings: {benign}, all known-harmless (constant outputs,"
                    " unused pin assignments,")
        print("   parallel-compile hints, LogicLock advert). See README.")

    print()
    common.info(f"Bitstream: {sof}")
    common.info("Resource numbers are in")
    print(f"   output_files/{PROJECT}.fit.rpt (ALMs, registers, memory bits, pins).")
    print()
    common.info("To program the board via a CLI, use:")
    print(f'     quartus_pgm -m jtag -o "p;{sof}@2"')

    # Non-zero exit when timing failed, so this script can gate a commit or a
    # demo the same way the test runners do:
    return 0 if timing_ok else 1


if __name__ == "__main__":
    sys.exit(main())
