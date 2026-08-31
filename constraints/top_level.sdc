# =============================================================================
# piano_tiles.sdc  --  MTRX3700 Assignment 1, Piano Tiles
#                      TimeQuest constraints for the DE1-SoC top level
#
# WHY THIS FILE HAS TO EXIST
#   Without a create_clock, TimeQuest reports every path as unconstrained and
#   the Timing Analyzer summary is empty. Quartus will still produce a .sof and
#   the board will still appear to work -- at 50 MHz this design has enormous
#   slack -- but you will have no evidence that it closes timing, and "it looked
#   fine on the bench" is not a timing result. Q4 asks for numbers.
#
# READING THE RESULT
#   After Compilation, open Tools > Timing Analyzer and check the Fmax summary
#   for CLOCK_50. Report the slack, not just "it passed".
# =============================================================================

# -----------------------------------------------------------------------------
# The one clock in the design
# -----------------------------------------------------------------------------
# 50 MHz -> 20 ns. Everything in this project is synchronous to this single
# clock: there is no PLL, no second domain, and no generated clock. The only
# asynchronous things in the design are the KEY and SW pins, and they enter
# through the two-flop synchroniser inside every debounce instance.
create_clock -name {CLOCK_50} -period 20.000 [get_ports {CLOCK_50}]

# Model the real clock's jitter and the fitter's uncertainty rather than
# assuming an ideal edge. Always call this after the clock is defined.
derive_clock_uncertainty

# -----------------------------------------------------------------------------
# Asynchronous inputs
# -----------------------------------------------------------------------------
# KEY and SW are mechanical contacts driven by a human. They have no relationship
# to CLOCK_50, so constraining their setup and hold against it is meaningless --
# TimeQuest would report violations that describe nothing real.
#
# This is safe to declare ONLY because every one of these pins passes through
# synchroniser.v (two flops) inside debounce before reaching any logic. That is
# the mechanism that handles metastability; the false path here just stops
# TimeQuest from analysing a path that the synchroniser already owns.
#
# If a future revision ever routes a raw SW or KEY pin straight into logic
# without a synchroniser, DELETE the matching line below rather than keeping it.
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]

# -----------------------------------------------------------------------------
# Slow outputs
# -----------------------------------------------------------------------------
# LEDs and 7-segment displays are watched by a human eye. There is no receiving
# device with a setup requirement, so there is no output delay to constrain.
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
set_false_path -to [get_ports {HEX4[*]}]
set_false_path -to [get_ports {HEX5[*]}]

# -----------------------------------------------------------------------------
# Where to look if timing does NOT close
# -----------------------------------------------------------------------------
# Three candidates, in order of likelihood:
#
#   1. note_scheduler's spawn logic. It indexes schedule_next with a variable
#      lane AND a variable time, then loops a spacing comparison over every
#      slot, all in one combinational block. It is the longest path in the
#      design by a wide margin.
#
#   2. score.sv's arithmetic. The pop-counts, the multiply-by-3, the signed
#      accumulate and the double-ended clamp are one combinational chain from
#      the event pulses to the score register.
#
#   3. display's score path. bcd_encoder_4 is a synchronous lookup ROM, so its
#      registered boundary should make this shorter than the old division path.
#
# None of these should trouble a 20 ns period on a Cyclone V. Measure before
# optimising anything.
