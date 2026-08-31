# FPGA smoke-test revision

Select `fpga_smoke_test` in Quartus to build the deterministic hardware test.
It uses only:

- `smoke_test/fpga_smoke_test.sv`
- `smoke_test/seven_seg_decoder.sv`
- `rtl/input/synchroniser.v`
- `rtl/input/debounce.v`
- `rtl/timing/timer.v`
- `constraints/fpga_smoke_test.sdc`

The smoke-test testbench is `tb/fpga_smoke_test_tb.sv` and is not included in
synthesis. Generated files are written under `build/fpga_smoke_test/`.
