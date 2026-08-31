# DE1-SoC CLOCK_50 oscillator: 50 MHz, 20.000 ns period.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# SW/KEY are asynchronous mechanical controls which enter two-flop
# synchronisers. HEX/LEDR drive human-visible board peripherals and have no
# external source- or destination-synchronous timing requirement.
set_false_path -from [get_ports {SW* KEY*}]
set_false_path -to   [get_ports {HEX* LEDR*}]
