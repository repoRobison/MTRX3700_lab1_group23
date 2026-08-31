//=============================================================================
// game_params.svh  --  MTRX3700 Assignment 1, Piano Tiles
/*
// Shared game parameters and constants for the Piano Tiles
// game, including timing, countdown, scoring, and difficulty
// settings used across multiple modules.
*/
// EVERY tunable constant in the design lives in this file and nowhere else.
// If a number appears twice in the project, one of them is a bug waiting.
//
// How this is used:
//   Modules declare real `parameter` ports whose DEFAULTS come from here, e.g.
//       module hit_flash #(parameter int FLASH_MS = `GP_FLASH_MS) (...);
//   Testbenches then override those parameters at instantiation, which is what
//   the brief asks for in section 2.5, WITHOUT editing this file. So:
//       - change gameplay          -> edit this file
//       - make a simulation fast   -> override at the testbench instantiation
//
// Demo Part B: the tutor's change card almost certainly lands in section 3 or
// section 6 below. Both are one-line edits.
//=============================================================================
`ifndef GAME_PARAMS_SVH
`define GAME_PARAMS_SVH

//-----------------------------------------------------------------------------
// 1. Clock and simulation scaling
//-----------------------------------------------------------------------------
// These two are the ONLY parameters that differ between hardware and
// simulation. Both are overridden at instantiation in the testbenches, never
// edited here -- see the 2500x table in the mini-project integration notes.
//
//                       hardware (50 MHz)     simulation (20 kHz)
//   GP_CLKS_PER_MS            50000                    20
//   GP_DEBOUNCE_COUNTS         2500                     1
//
`define GP_CLKS_PER_MS      50000   // clock cycles in one millisecond
`define GP_DEBOUNCE_COUNTS  2500    // 50 us debounce window at 20 ns period

// Slide switches bounce for longer than push buttons, and SW0 is the game
// reset. beat_gen places beat zero on the exact cycle reset drops, so bounce on
// RELEASE would start the song, restart it, and start again -- breaking the R6
// synchronisation in a way that looks like a timing bug. 5 ms is comfortably
// longer than any mechanical switch bounce and is invisible against R6's 250 ms
// tolerance.
`define GP_SW_DEBOUNCE_COUNTS 250000  // 5 ms at 50 MHz

// Power-on reset.
//
// CORRECTED, and the old value was a live defect. The POR must outlast the
// time it takes SW0's debounced value to become available, which is
// GP_SW_DEBOUNCE_COUNTS + 4 clocks -- not the ~4 clocks the previous comment
// assumed. At the old 50000 (1 ms) against a switch chain of 250004 (5 ms),
// a board configured with SW0 ALREADY UP released reset at 1 ms and did not
// re-assert it until 5 ms: a measured 200004-cycle window in which the game
// ran while the player was holding the reset switch on.
//
//   REQUIRED:  GP_POR_COUNTS >= GP_SW_DEBOUNCE_COUNTS + 4
//   checked in params_tb, and again at elaboration inside button_input.
//
// 300000 is 6 ms: clear of the 250004 floor, and far below the 10 ms at which
// a player would notice the board being slow to start.
`define GP_POR_COUNTS       300000  // 6 ms at 50 MHz

//-----------------------------------------------------------------------------
// 2. Timer geometry
//-----------------------------------------------------------------------------
// timer.v declares  reg [$clog2(MAX_MS)-1:0] ms_count.  $clog2(2047) == 11,
// giving a counter that holds 0..2047 exactly. Do NOT set this to a power of
// two: $clog2(2048) is also 11, so the counter would top out at 2047 and the
// parameter would silently lie about its own range.
`define GP_TIMER_MAX_MS     2047
`define GP_MS_W             11      // == $clog2(GP_TIMER_MAX_MS)
`define GP_BPM_W            8       // supports integer tempos from 1..255 BPM

//-----------------------------------------------------------------------------
// 3. Game feel                                    <-- likely Part B target
//-----------------------------------------------------------------------------
// GP_FLASH_MS   : hit indicator LED event duration. R2 requires 200..500 ms.
//                 Normal hits stay solid; perfect hits blink during the same
//                 250 ms event so their double score is visibly explained.
// GP_PERFECT_BLINK_MS: length of each on/off portion of the perfect-hit blink.
// GP_WIN_FLASH_MS: length of each all-LEDR on/off game-over phase.
// GP_PERFECT_MS : R12 perfect-timing window, measured from the beat boundary.
//                 The window is ONE-SIDED: a press before the boundary is an
//                 early press and is forfeited under R11, so "perfect" can only
//                 be measured after the note reaches zero.
//
// PER-LEVEL, because the group README makes the perfect window a difficulty
// axis ("Perfect Window: Wide / Medium / Narrow") alongside spawn rate and hit
// window. The per-level values live in section 6 with the rest of the level
// table; GP_PERFECT_MS is only the module parameter DEFAULT, and every
// instance is overridden from the level table at run time.
//
// PROVISIONAL NUMBERS, needing a playtest and Task 2/Task 4 sign-off. The
// The easy default is deliberately widest and the value scales down with each
// level. Every value remains a strict subset of its level's hit window.
`define GP_FLASH_MS         250
`define GP_PERFECT_BLINK_MS 50
`define GP_WIN_FLASH_MS     250
`define GP_PERFECT_MS       250     // parameter default == the easy value

//-----------------------------------------------------------------------------
// 4. Scoring                                      <-- likely Part B target
//-----------------------------------------------------------------------------
// GROUP DECISION: a mistimed press, a press on a blank lane, and mashing all
// REDUCE the score and reset the multiplier. Score therefore moves in both
// directions and must clamp at both ends: 0 at the bottom, GP_WIN_SCORE at the
// top, where the game is won.
//
// Because up to FOUR lanes can be pressed in the same clock cycle, penalties
// must be SUMMED across lanes, not OR-reduced. Four simultaneous forfeits are
// four penalties. (Resetting the streak stays an OR -- one reset is one reset.)
//
// Worst case in one clock cycle:
//   gain    2 hits x GP_PERFECT_POINTS x 3       = 12   (hard level, chord)
//   loss    4 x GP_FORFEIT_PENALTY               =  4
// so the intermediate sum needs headroom above 99 and below 0: use a signed
// 9-bit accumulator, then clamp into the 7-bit score.
`define GP_WIN_SCORE        99      // R9: reaching this WINS the game
`define GP_BASE_POINTS      1
`define GP_PERFECT_POINTS   2       // a perfect note is worth 2x a plain hit
`define GP_FORFEIT_PENALTY  1       // early press destroyed a live note
`define GP_STRAY_PENALTY    1       // press on a blank / inactive lane

// Multiplier thresholds, in consecutive clean hits.
//
// GROUP DECISION: the threshold hit receives the multiplier it unlocks. Hits
// 1..5 score at x1, hit 6 scores at x2, and hit 16 scores at x3. A two-note
// chord is one simultaneous event: both successes are added to the old streak
// before the multiplier is selected, so a chord that moves the streak from 4
// to 6 scores both notes at x2. There is deliberately no x4/x5 tier; with a
// win score of 99 those tiers would exist for too few notes to add meaningful
// gameplay. At the fastest nominal rate, 20 flawless perfect hits score 80,
// leaving the required 15-second playable demonstration clear of the win state.
`define GP_MULT2_STREAK     6
`define GP_MULT3_STREAK     16
`define GP_MAX_MULTIPLIER   3
`define GP_MAX_STREAK       31      // 5 bits: must exceed GP_MULT3_STREAK

//-----------------------------------------------------------------------------
// 5. Lane geometry
//-----------------------------------------------------------------------------
// GP_BLANK_DIGIT exploits seven_seg's existing default arm: any bcd value
// greater than 9 drives 7'b1111111, which is all segments off. R5 therefore
// costs no extra logic -- the lane just stops driving a real digit.
`define GP_NUM_LANES        4
`define GP_COUNT_W          4       // one decimal digit, 0..9
`define GP_BLANK_DIGIT      4'hF    // > 9, so seven_seg blanks the display

//-----------------------------------------------------------------------------
// 6. Levels (R13)                                 <-- likely Part B target
//-----------------------------------------------------------------------------
// Selected by SW2:SW1, applied through a clean automatic reset, and shown
// one-hot on LEDR9:7.
//
//   level   song             bpm  countdown  win_ms  perf_ms  cadence  chord
//   -----   ---------------  ---  ---------  ------  -------  -------  -----
//   easy    Come Together     83    3 .. 6     700      250       2        1
//   medium  Get Back         123    3 .. 6     400      150       2        1
//   hard    Get Back         123    2 .. 5     250       80       2        2
//
// The perfect window is 40%, 48% and 40% of its own hit window, so "perfect"
// stays a real discrimination at every level rather than becoming either
// automatic or unhittable. params_tb enforces perf_ms < win_ms per level.
//
// GROUP DECISION on countdown range: "work with 5 for now". Read as 5 being the
// TOP of the range, not a constant. A constant would fail R4, which requires
// countdowns to "appear with varying initial countdown values". 2..5 keeps 5 as
// the ceiling, gives four distinct values, and is a power-of-two span.
//
// GROUP DECISION on simultaneous resolves: forbidden on easy and medium,
// allowed on hard. GP_L*_MAX_CHORD is how that is enforced, and it becomes a
// third R13 differentiator alongside tick speed and window length.
//
// Medium and Hard deliberately share the exact 120 BPM Get Back timebase.
// Hard permits two independently scheduled notes to coincide, but does not
// force a second lane. Chords therefore remain an occasional possibility
// rather than a fixed-probability pattern.

// CMIN/CMASK, not CMIN/CMAX: the countdown value is computed as
//     cand = CMIN + (rnd & CMASK)
// which is a bitwise AND. Every span is therefore a power of two in size.
// A "nicer" range such as 4..6 would need  rnd % 3  -- and modulo by a value
// that is not a compile-time power of two synthesises a real divider: dozens
// of ALMs and a long combinational path, to buy nothing a player can perceive.
//
// beat_gen uses a fractional accumulator. Over exactly one minute of FPGA
// clocks it emits exactly BPM ticks, even where 60/BPM is not a whole number of
// milliseconds (83 BPM alternates between adjacent clock-length intervals).

`define GP_L0_BPM         83        // Come Together
`define GP_L0_TICK_MS     723       // nearest whole ms; validation/docs only
`define GP_L0_CMIN        3
`define GP_L0_CMASK       3         // 3 + (0..3) -> 3..6
`define GP_L0_WIN_MS      700       // below the shortest 83 BPM interval
`define GP_L0_PERFECT_MS  250       // widest perfect window
`define GP_L0_CADENCE     2         // spawn attempt every 2 ticks
`define GP_L0_MAX_CHORD   1         // no two notes resolve on one tick

`define GP_L1_BPM         123       // Get Back
`define GP_L1_TICK_MS     488       // exact whole-ms period; validation/docs
`define GP_L1_CMIN        3
`define GP_L1_CMASK       3         // 3 + (0..3) -> 3..6
`define GP_L1_WIN_MS      400
`define GP_L1_PERFECT_MS  150
`define GP_L1_CADENCE     2
`define GP_L1_MAX_CHORD   1         // no two notes resolve on one tick

`define GP_L2_BPM         123       // Get Back; difficulty comes from chords
`define GP_L2_TICK_MS     488       // exact whole-ms period; validation/docs
`define GP_L2_CMIN        2
`define GP_L2_CMASK       3         // 2 + (0..3) -> 2..5
`define GP_L2_WIN_MS      250
`define GP_L2_PERFECT_MS  80
`define GP_L2_CADENCE     2
`define GP_L2_MAX_CHORD   2         // chords allowed -- the hard-level feature

//-----------------------------------------------------------------------------
// 7. Scheduler
//-----------------------------------------------------------------------------
// The reserve vector records, for each of the next GP_RESERVE_W ticks, HOW MANY
// notes already resolve on that tick -- a saturating count, not a flag, because
// the cap is now per-level rather than always one. It must be at least as deep
// as the largest countdown value, plus slack.
`define GP_RESERVE_W        16

// Retry is NOT an optimisation. A spawn attempt is refused whenever the chosen
// lane is busy or the chosen resolve tick is full, and with a single attempt
// per cadence the easy level delivers 0.27 notes/s in the worst 15 s window
// against R7's floor of 0.5. Retrying over all four lanes restores it to 0.67.
`define GP_SPAWN_RETRIES    4

// GROUP DECISION on sequencing: "randomly". Implemented as random LANE and
// random COUNTDOWN on a DETERMINISTIC cadence -- random in what happens, fixed
// in when it is attempted. Making the timing itself random as well was measured
// and fails R7 on every level (worst 15 s window: 0.07 easy, 0.27 medium, 0.40
// hard), because R7 is stated over ANY 15 s and a Poisson arrival process has
// arbitrarily quiet stretches.

`endif // GAME_PARAMS_SVH
