//=============================================================================
// params_tb.sv  --  self-check for game_params.svh
//
// Why this exists.
//
// The header is the file Demo Part B makes you edit in front of a tutor, and
// most of its values are consumed by modules that are not written yet. That
// leaves the majority of the design's constants with no test covering them at
// all: a change card that halves a window or doubles a bonus would pass the
// whole suite while quietly breaking a requirement.
//
// This bench has no DUT. It checks the RELATIONSHIPS between constants that the
// requirements and the hardware impose, so an edit that violates one fails
// immediately in the testbench the tutor just asked you to re-run.
//
// Every check names the requirement or the mechanism it protects.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module params_tb;

    int errors = 0;

    task automatic check(bit cond, string what);
        if (!cond) begin
            errors = errors + 1;
            $display("  FAIL: %s", what);
        end
    endtask

    // Every per-level constraint, applied to each of the three levels.
    task automatic check_level(input string name,
                               input int tick_ms, input int cmin, input int cmask,
                               input int win_ms,  input int perfect_ms,
                               input int cadence,
                               input int max_chord);
        real rate;
        begin
            // ---- R4: values must be drawn from within 1 to 9, and must VARY --
            check(cmin >= 1,
                  {name, ": CMIN must be at least 1 (0 breaks the reserve-vector index and can stall a lane)"});
            check(cmin + cmask <= 9,
                  {name, ": CMIN+CMASK exceeds 9, outside R4's permitted range"});
            check(cmask >= 1,
                  {name, ": CMASK is 0, so every countdown is identical - R4 requires VARYING values"});
            // The mask must be all-ones, or CMIN + (rnd & CMASK) is not a
            // contiguous range. Anything else needs a modulo, which synthesises
            // a divider (see the L2 4.3 contrast in the header).
            check((cmask & (cmask + 1)) == 0,
                  {name, ": CMASK must be all-ones (1, 3, 7, 15) or the range is not contiguous"});

            // ---- R12: the perfect window must be a strict subset of the hit
            //      window, ON THIS LEVEL. Checking a single global figure hid
            //      the fact that the README's 200 ms is impossible on hard,
            //      whose entire hit window is 125 ms.
            check(win_ms > perfect_ms,
                  {name, ": hit window is not longer than this level's perfect window, so every valid press would score a perfect"});
            check(perfect_ms > 0,
                  {name, ": perfect window is zero, so no press on this level can ever be perfect"});
            // A perfect window that is nearly the whole hit window makes the
            // bonus automatic and R12's discrimination meaningless.
            check(perfect_ms * 4 <= win_ms * 3,
                  {name, ": perfect window is more than 75% of the hit window, so almost every hit scores a perfect"});

            // ---- R6/R13: a hit window cannot outlast the tick that opened it --
            check(win_ms <= tick_ms,
                  {name, ": hit window is longer than a tick; lane_fsm closes the window on the next tick regardless"});
            check(tick_ms > 0, {name, ": tick_ms must be positive"});

            // ---- R7: nominal note rate must clear 0.5 notes/s ----------------
            // Necessary, not sufficient: spawn attempts are also REFUSED when
            // the chosen lane is busy or the resolve tick is full, which is why
            // note_scheduler must retry. Measured, a single attempt per cadence
            // drops the easy level to 0.27 notes/s in its worst 15 s window.
            rate = 1000.0 / (cadence * tick_ms);
            check(rate >= 0.5,
                  {name, ": nominal note rate is below R7's floor of 0.5 notes/s even before refusals"});
            check(cadence >= 1, {name, ": cadence must be at least 1 tick"});

            // ---- simultaneous resolves (group decision) ----------------------
            check(max_chord >= 1 && max_chord <= `GP_NUM_LANES,
                  {name, ": MAX_CHORD must be between 1 and the number of lanes"});

            // ---- widths ------------------------------------------------------
            check((cmin + cmask) < (1 << `GP_COUNT_W),
                  {name, ": largest countdown does not fit in GP_COUNT_W bits"});
            check((cmin + cmask) < `GP_RESERVE_W,
                  {name, ": reserve vector is shallower than the largest countdown"});
            check(tick_ms < (1 << `GP_MS_W),
                  {name, ": tick_ms does not fit in GP_MS_W bits"});
        end
    endtask

    // Best case a player can achieve: every note hit, every one perfect, streak
    // never broken. Returns the score after `notes` notes.
    function automatic int flawless_score(input int notes);
        int score, streak, mult, i;
        begin
            score = 0; streak = 0;
            for (i = 0; i < notes; i++) begin
                // The threshold hit receives the newly unlocked multiplier, so
                // update the streak BEFORE selecting the multiplier. This is
                // intentionally the same ordering as multiplier.sv.
                if (streak < `GP_MAX_STREAK) streak = streak + 1;
                if      (streak >= `GP_MULT3_STREAK) mult = 3;
                else if (streak >= `GP_MULT2_STREAK) mult = 2;
                else                                 mult = 1;
                score = score + `GP_PERFECT_POINTS * mult;
            end
            flawless_score = score;
        end
    endfunction

    int notes_15s, best, fastest_ms;

    initial begin
        $display("params_tb: checking game_params.svh");

        //---------------------------------------------------------------------
        // Per-level constraints
        //---------------------------------------------------------------------
        check_level("easy",   `GP_L0_TICK_MS, `GP_L0_CMIN, `GP_L0_CMASK,
                              `GP_L0_WIN_MS,  `GP_L0_PERFECT_MS,
                              `GP_L0_CADENCE, `GP_L0_MAX_CHORD);
        check_level("medium", `GP_L1_TICK_MS, `GP_L1_CMIN, `GP_L1_CMASK,
                              `GP_L1_WIN_MS,  `GP_L1_PERFECT_MS,
                              `GP_L1_CADENCE, `GP_L1_MAX_CHORD);
        check_level("hard",   `GP_L2_TICK_MS, `GP_L2_CMIN, `GP_L2_CMASK,
                              `GP_L2_WIN_MS,  `GP_L2_PERFECT_MS,
                              `GP_L2_CADENCE, `GP_L2_MAX_CHORD);

        // README: the perfect window is a DIFFICULTY AXIS, so it must actually
        // narrow as the level gets harder. Equal values would silently drop
        // one of the three differentiators the README lists.
        check(`GP_L0_PERFECT_MS > `GP_L1_PERFECT_MS,
              "easy's perfect window is not wider than medium's; README lists it as a difficulty axis");
        check(`GP_L1_PERFECT_MS > `GP_L2_PERFECT_MS,
              "medium's perfect window is not wider than hard's; README lists it as a difficulty axis");

        //---------------------------------------------------------------------
        // R2: the hit indicator must be visible but not linger
        //---------------------------------------------------------------------
        check(`GP_FLASH_MS >= 200 && `GP_FLASH_MS <= 500,
              "GP_FLASH_MS is outside R2's 200-500 ms band");
        check(`GP_PERFECT_BLINK_MS > 0
              && `GP_PERFECT_BLINK_MS < `GP_FLASH_MS,
              "perfect-hit blink phase must fit inside the hit flash event");
        check(`GP_WIN_FLASH_MS > 0,
              "game-over LED flash phase must be positive");

        //---------------------------------------------------------------------
        // R12: multiplier thresholds must be ordered and reachable
        //---------------------------------------------------------------------
        check(`GP_MULT2_STREAK < `GP_MULT3_STREAK, "multiplier thresholds are out of order (x2 >= x3)");
        check(`GP_MAX_STREAK >= `GP_MULT3_STREAK,
              "GP_MAX_STREAK saturates below GP_MULT3_STREAK, so the x3 multiplier is unreachable");
        check(`GP_MAX_MULTIPLIER == 3,
              "the agreed multiplier display and scoring design has exactly x1/x2/x3 tiers");
        check(flawless_score(`GP_MULT2_STREAK - 1) ==
              (`GP_MULT2_STREAK - 1) * `GP_PERFECT_POINTS,
              "a hit before the x2 threshold did not score at x1");
        check(flawless_score(`GP_MULT2_STREAK) ==
              (`GP_MULT2_STREAK - 1) * `GP_PERFECT_POINTS
              + `GP_PERFECT_POINTS * 2,
              "the hit that reaches GP_MULT2_STREAK did not receive x2");
        check(flawless_score(`GP_MULT3_STREAK) - flawless_score(`GP_MULT3_STREAK - 1)
              == `GP_PERFECT_POINTS * 3,
              "the hit that reaches GP_MULT3_STREAK did not receive x3");
        check(`GP_BASE_POINTS > 0, "GP_BASE_POINTS must award a positive score");
        check(`GP_PERFECT_POINTS > `GP_BASE_POINTS,
              "a perfect hit is worth no more than a plain one, so R12's bonus does nothing");
        check(`GP_FORFEIT_PENALTY > 0,
              "an early/forfeited press has no score consequence, weakening R11");
        check(`GP_STRAY_PENALTY > 0,
              "a press on a blank lane has no score consequence, allowing mashing");
        // GP_PERFECT_MS is now only the module parameter DEFAULT; the real
        // values are per level and are checked in check_level above.
        check(`GP_PERFECT_MS > 0, "GP_PERFECT_MS default is zero");

        //---------------------------------------------------------------------
        // R9: the score must fit the two digits it is displayed on
        //---------------------------------------------------------------------
        check(`GP_WIN_SCORE <= 99, "GP_WIN_SCORE exceeds what HEX5:HEX4 can display");
        check(`GP_WIN_SCORE > 0,   "GP_WIN_SCORE must be positive");

        //---------------------------------------------------------------------
        // Demo Part A item 8 vs the win condition
        //---------------------------------------------------------------------
        // The group chose "at 99 the game is won". Part A item 8 requires a 15 s
        // run hitting EVERY note -- a flawless run, which is precisely the case
        // that scores fastest. If the scoring rates let a flawless run reach 99
        // inside 15 s, the game declares itself won in the middle of the
        // requirement being demonstrated.
        //
        // Checked against the FASTEST level, using the nominal note rate (which
        // is optimistic, and therefore the right way round for a safety check).
        // Do NOT hardcode L2 as the fastest level: a change card that speeds
        // up medium would leave this silently checking the wrong one.
        fastest_ms = `GP_L0_CADENCE * `GP_L0_TICK_MS;
        if (`GP_L1_CADENCE * `GP_L1_TICK_MS < fastest_ms)
            fastest_ms = `GP_L1_CADENCE * `GP_L1_TICK_MS;
        if (`GP_L2_CADENCE * `GP_L2_TICK_MS < fastest_ms)
            fastest_ms = `GP_L2_CADENCE * `GP_L2_TICK_MS;

        notes_15s = 15000 / fastest_ms;
        best      = flawless_score(notes_15s);
        check(best < `GP_WIN_SCORE,
              $sformatf("a flawless 15 s run on the fastest level scores %0d, reaching the win threshold of %0d before the demo ends - lower GP_PERFECT_POINTS or raise the multiplier thresholds",
                        best, `GP_WIN_SCORE));
        $display("  flawless 15 s run on the fastest level: %0d notes, %0d points (win at %0d)",
                 notes_15s, best, `GP_WIN_SCORE);

        //---------------------------------------------------------------------
        // Scheduler and timer mechanics
        //---------------------------------------------------------------------
        check(`GP_SPAWN_RETRIES >= `GP_NUM_LANES,
              "fewer spawn retries than lanes; measured, a single attempt per cadence fails R7 on the easy level");
        check(`GP_CLKS_PER_MS >= 2,
              "timer declares its prescaler [$clog2(CLKS_PER_MS)-1:0]; $clog2(1) is 0, an illegal [-1:0] vector");
        check(`GP_MS_W == $clog2(`GP_TIMER_MAX_MS),
              "GP_MS_W does not match $clog2(GP_TIMER_MAX_MS); timer declares its ports from MAX_MS");
        check((`GP_TIMER_MAX_MS & (`GP_TIMER_MAX_MS + 1)) == 0,
              "GP_TIMER_MAX_MS is not 2^n-1; $clog2 would round down and the counter would silently under-range");
        check(`GP_BLANK_DIGIT > 9,
              "GP_BLANK_DIGIT is a valid BCD digit, so seven_seg would display it instead of blanking (R5)");
        check(`GP_NUM_LANES == 4, "the fixed hardware interface in section 2.1 defines exactly four lanes");

        //---------------------------------------------------------------------
        // Input conditioning
        //---------------------------------------------------------------------
        check(`GP_SW_DEBOUNCE_COUNTS >= `GP_DEBOUNCE_COUNTS,
              "switches must be debounced at least as hard as push buttons; SW0 bounce on release would restart the song (R6)");
        check(`GP_DEBOUNCE_COUNTS >= 1, "GP_DEBOUNCE_COUNTS must be at least 1");
        // The power-on reset has to outlast the time it takes SW0's DEBOUNCED
        // value to exist, which is the whole switch chain, not the ~4 clocks
        // debounce needs to resolve its own x state. Measured with the old
        // 50000 against a 250004-clock switch chain: a board configured with
        // SW0 already up released reset at 1 ms and did not re-assert until
        // 5 ms -- 200004 clocks of the game running under a held reset switch.
        check(`GP_POR_COUNTS >= `GP_SW_DEBOUNCE_COUNTS + 4,
              "POR expires before SW0's debounced value exists: reset releases early on a board configured with SW0 already up");
        check(`GP_POR_COUNTS > 8,
              "power-on reset is shorter than the time debounce takes to resolve its own x state");
        // ...and it must be short enough that a player never notices it.
        check(`GP_POR_COUNTS <= 10 * `GP_CLKS_PER_MS,
              "power-on reset lasts longer than 10 ms; the board would appear slow to start");

        //---------------------------------------------------------------------
        if (errors == 0) begin
            $display("params_tb: PASS");
            $finish;
        end else begin
            $display("params_tb: FAIL (%0d checks failed)", errors);
            $fatal(1, "params_tb failed");
        end
    end

endmodule
