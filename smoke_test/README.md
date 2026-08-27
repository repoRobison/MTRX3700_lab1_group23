# FPGA smoke-test revision

`fpga_smoke_test` is a minimal DE1-SoC hardware check. It is intentionally
isolated from the unfinished Piano Tiles game FSM, scheduler, RNG, multiplier,
difficulty logic, and reaction-time logic.

## Hardware behavior

- `CLOCK_50` is the only clock and is constrained to 50 MHz (20.000 ns).
- `SW0` is an active-high synchronous reset after a two-flop synchroniser.
- One active lane cycles deterministically through lane 0, 1, 2, 3, then wraps.
- Each lane shows `3`, `2`, `1`, `0` for one second per digit on its matching
  `HEX0` through `HEX3`; every inactive lane display is blank.
- `KEY0` through `KEY3` are active-low, synchronised and debounced. A clean
  rising internal press edge is generated once per physical press.
- A matching press during that lane's `0` interval adds one point. Incorrect or
  early presses do nothing.
- `HEX5:HEX4` shows the score as `00` through `99`. The score **saturates at 99**;
  further valid hits leave it at 99.
- A successful lane 0..3 press lights `LEDR3`..`LEDR6`, respectively, for
  250 ms.
- `LEDR0` is a slow heartbeat: 500 ms off, 500 ms on. `LEDR1` and `LEDR2` are
  deliberately off.

## Reused project modules

- `player_input/synchroniser.v`
- `player_input/debounce.v`
- `timing/timer.v`
- `Rob/seven_seg_decoder.sv`

Only these reusable utilities and `smoke_test/fpga_smoke_test.sv` are listed in
the smoke-test QSF. The testbench is not a Quartus synthesis source.

## Pin provenance

The existing `top_level.qsf` contains the Cyclone V device assignment but no
board pin locations. Every smoke-test location and 3.3-V LVTTL I/O-standard
assignment in `fpga_smoke_test.qsf` was copied from the user-supplied verified
reference:

`C:\Users\jimmy\Documents\Year_3\MTRX3700\DE1-SoC_pin_assignments.csv`

No pin was guessed.

## Revision and generated-file isolation

- Project: `piano_tiles.qpf`
- Existing revision settings, unchanged: `top_level.qsf`
- Existing default revision, preserved: `top_level`
- Smoke-test revision: `fpga_smoke_test.qsf`
- Smoke-test top-level entity: `fpga_smoke_test`
- Configured smoke-test output directory: `smoke_test/quartus_output`

The command-line verification is run from an isolated temporary copy so it
cannot modify this project's pre-existing `db`, `incremental_db`, `output_files`,
or `work` directories. A successful programming file is copied back to
`smoke_test/artifacts/fpga_smoke_test.sof`.

## Files created

- `fpga_smoke_test.qsf` — separate Quartus revision, sources, device, and pins.
- `piano_tiles.qpf` — changed only to register the additional
  `fpga_smoke_test` revision after the preserved `top_level` revision.
- `smoke_test/fpga_smoke_test.sv` — synthesizable smoke-test top level.
- `smoke_test/fpga_smoke_test.sdc` — 50 MHz clock constraint.
- `smoke_test/fpga_smoke_test_tb.sv` — self-checking simulation testbench.
- `smoke_test/README.md` — this behavior, build, and change record.
- `smoke_test/artifacts/fpga_smoke_test.sof` — verified Quartus programming
  artifact copied from the isolated build.

No full-game HDL, `top_level.qsf`, or generated `db`, `incremental_db`,
`output_files`, or `work` content was changed.

## Verification record

Verified on 2026-08-27 with Quartus Prime Lite 18.1 build 625 and ModelSim
Intel FPGA Edition 10.5b. Verilator 5 was not installed.

- ModelSim compilation: 0 errors, 0 warnings.
- Self-checking simulation: all checks passed for reset, complete lane order,
  countdown values, inactive-display blanking, incorrect and correct keys,
  held-key suppression, score updates, score display, exact LED pulse duration,
  a second reset, BCD carry through 09/10, and saturation at 99.
- Analysis & Synthesis: successful, 0 errors.
- Fitter: successful, 0 errors; 259 ALMs (<1%), 299 registers, 55 pins.
- TimeQuest: successful, 0 errors; fully constrained for setup and hold.
  Worst setup slack was 14.888 ns, worst hold slack was 0.172 ns, and worst
  minimum-pulse-width slack was 9.064 ns across the reported corners.
- Assembler: successful, 0 errors.
- SOF: produced as `smoke_test/artifacts/fpga_smoke_test.sof` (6,690,412
  bytes), SHA-256
  `259F13E6CE09FFB04BC50D34089FCAD00F406B8941DEB44DFCB1F956E7F78597`.

The Fitter reports one incomplete-I/O category because the supplied pin CSV
does not specify output drive strength or slew rate. Those values were not
guessed; Quartus used its legal 3.3-V LVTTL defaults. The fit report confirms
all 55 locations were user-assigned.
