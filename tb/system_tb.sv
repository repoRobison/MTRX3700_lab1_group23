`timescale 1ns/1ns
`include "game_params.svh"

module system_tb;
  localparam int CPMS=20, KDB=2, SDB=8, POR=12;
  logic CLOCK_50=0;
  logic [3:0] KEY=4'hF;
  logic [9:0] SW=10'b0;
  wire [9:0] LEDR;
  wire [6:0] HEX0,HEX1,HEX2,HEX3,HEX4,HEX5;

  top_level #(
    .CLKS_PER_MS(CPMS), .KEY_DEBOUNCE(KDB),
    .SW_DEBOUNCE(SDB), .POR_COUNTS(POR)
  ) dut (
    .CLOCK_50, .KEY, .SW, .LEDR,
    .HEX0, .HEX1, .HEX2, .HEX3, .HEX4, .HEX5
  );

  always #10 CLOCK_50=~CLOCK_50;

  integer t, i, lane, hits, stuck, auto_resets, errors;
  integer score_before, expected_score, event_gain;
  integer win_transitions;
  logic auto_play=1'b0;
  logic [9:0] previous_win_leds;
  logic [3:0] eligible_lanes;
  logic [3:0] event_normal, event_perfect, event_forfeit;
  logic [1:0] event_multiplier;

  function automatic [6:0] seven_seg_digit(input integer digit);
    case (digit)
      0: seven_seg_digit=7'b1000000;
      1: seven_seg_digit=7'b1111001;
      2: seven_seg_digit=7'b0100100;
      3: seven_seg_digit=7'b0110000;
      4: seven_seg_digit=7'b0011001;
      5: seven_seg_digit=7'b0010010;
      6: seven_seg_digit=7'b0000010;
      7: seven_seg_digit=7'b1111000;
      8: seven_seg_digit=7'b0000000;
      9: seven_seg_digit=7'b0010000;
      default: seven_seg_digit=7'b1111111;
    endcase
  endfunction

  task automatic check(input bit condition, input string what);
    if (!condition) begin
      errors=errors+1;
      $display("  FAIL: %s (t=%0t score=%0d zero=%b active=%b)",
               what, $time, dut.score_value, dut.lane_zero, dut.lane_active);
    end
  endtask

  task automatic check_score_display(input integer expected);
    begin
      check(HEX4 == seven_seg_digit(expected % 10),
            "HEX4 did not show the score units digit");
      check(HEX5 == seven_seg_digit((expected / 10) % 10),
            "HEX5 did not show the score tens digit");
    end
  endtask

  task automatic release_lane(input integer selected_lane);
    begin
      @(negedge CLOCK_50);
      KEY[selected_lane]=1'b1;
      while (dut.press[selected_lane] !== 1'b0) begin
        @(posedge CLOCK_50);
        #1;
      end
    end
  endtask

  // Automatic play is disabled during the report-oriented directed checks.
  // It is enabled only for the longer no-deadlock exercise.
  always @(posedge CLOCK_50) begin
    if (auto_play) begin
      for (i=0;i<4;i=i+1)
        KEY[i] <= ~(dut.lane_zero[i] & ~dut.press[i]);
    end
    if (dut.level_change_reset)
      auto_resets <= auto_resets + 1;
  end

  initial begin
    $dumpfile("system.vcd");
    $dumpvars(0, system_tb);
    auto_resets=0;
    errors=0;

    $display("T1 reset starts the game and latches Medium difficulty");
    SW=10'b000000_0011;             // SW0 reset, SW2:1=01 Medium
    repeat(60) @(posedge CLOCK_50);
    SW[0]=1'b0;
    repeat(100) @(posedge CLOCK_50);
    check(dut.game_active, "game did not enter its active state");
    check(LEDR[9:7] == 3'b010, "initial Medium level did not latch");
    check(dut.score_value == 0, "score was not zero after reset");

    $display("T2 a level-switch change selects Easy and resets exactly once");
    SW[2:1]=2'b00;
    repeat(100) @(posedge CLOCK_50);
    check(LEDR[9:7] == 3'b100,
          "switch-only level change did not select Easy");
    check(auto_resets == 1,
          "level change did not generate exactly one automatic reset");

    $display("T3 one due-note press produces one hit and the exact score");
    while (dut.lane_zero == 4'b0000) @(posedge CLOCK_50);
    lane=0;
    if (dut.lane_zero[1]) lane=1;
    if (dut.lane_zero[2]) lane=2;
    if (dut.lane_zero[3]) lane=3;
    score_before=dut.score_value;
    @(negedge CLOCK_50);
    KEY[lane]=1'b0;
    while (dut.press_pulse[lane] !== 1'b1) begin
      @(posedge CLOCK_50);
      #1;
    end
    event_normal=dut.normal_hit;
    event_perfect=dut.perfect_hit;
    event_multiplier=dut.hit_multiplier;
    check((event_normal[lane] ^ event_perfect[lane]) == 1'b1,
          "due-note press was not exactly one of normal/perfect");
    check((event_normal & event_perfect) == 0,
          "normal and perfect were asserted together");
    event_gain=(event_normal[lane] ? `GP_BASE_POINTS : `GP_PERFECT_POINTS)
               * event_multiplier;
    expected_score=score_before+event_gain;
    @(posedge CLOCK_50); #1;
    check(dut.score_value == expected_score,
          "classified hit did not add the exact expected score");
    @(posedge CLOCK_50); #1;
    check_score_display(expected_score);
    release_lane(lane);

    $display("T4 an early press is a forfeit and applies one exact penalty");
    eligible_lanes=dut.lane_active & ~dut.lane_zero;
    while (eligible_lanes == 4'b0000) begin
      @(posedge CLOCK_50);
      #1;
      eligible_lanes=dut.lane_active & ~dut.lane_zero;
    end
    lane=0;
    if (eligible_lanes[1]) lane=1;
    if (eligible_lanes[2]) lane=2;
    if (eligible_lanes[3]) lane=3;
    score_before=dut.score_value;
    expected_score=(score_before > `GP_FORFEIT_PENALTY)
                 ? score_before-`GP_FORFEIT_PENALTY : 0;
    @(negedge CLOCK_50);
    KEY[lane]=1'b0;
    while (dut.press_pulse[lane] !== 1'b1) begin
      @(posedge CLOCK_50);
      #1;
    end
    event_forfeit=dut.forfeit;
    check(event_forfeit[lane], "early press was not classified as a forfeit");
    check((dut.normal_hit | dut.perfect_hit | dut.stray) == 0,
          "forfeit was also classified as another press outcome");
    @(posedge CLOCK_50); #1;
    check(dut.score_value == expected_score,
          "forfeit did not subtract one point with zero saturation");
    @(posedge CLOCK_50); #1;
    check_score_display(expected_score);
    release_lane(lane);

    // The compact VCD now contains the directed report flow. Avoid making it
    // enormous during the long-running robustness exercise.
    $dumpoff;

    $display("T5 sustained automatic play continues without lane deadlock");
    auto_play=1'b1;
    hits=0;
    stuck=0;
    for (t=0;t<400000;t=t+1) begin
      @(posedge CLOCK_50);
      if (dut.any_hit!=0) hits=hits+1;
      if (dut.lane_zero==4'b1111) stuck=stuck+1;
    end
    check(hits > 0, "sustained play did not register any hit");
    check(stuck == 0, "all four lanes entered a deadlocked zero state");

    $display("T6 score 99 stops play, blanks lanes, and flashes all LEDs");
    auto_play=1'b0;
    KEY=4'hF;
    force dut.u_score.score=7'd99;
    repeat(4) @(posedge CLOCK_50);
    check(dut.won && dut.score_value == 7'd99,
          "score 99 did not assert the terminal won state");
    check(dut.lane_active == 0 && dut.due_notes == 0,
          "gameplay did not stop and clear at score 99");
    check(HEX0 == 7'b1111111 && HEX1 == 7'b1111111
       && HEX2 == 7'b1111111 && HEX3 == 7'b1111111,
          "lane displays did not blank at game over");

    previous_win_leds=LEDR;
    win_transitions=0;
    for (t=0;t<(2*250*CPMS+100);t=t+1) begin
      @(posedge CLOCK_50);
      if (LEDR != previous_win_leds) win_transitions=win_transitions+1;
      previous_win_leds=LEDR;
      check(LEDR == 10'b0000000000 || LEDR == 10'b1111111111,
            "game-over state did not own all ten LEDs");
    end
    check(win_transitions >= 2, "game-over LEDs did not flash twice");

    $display("--------------------------------------------------");
    $display("directed hit gain     : %0d", event_gain);
    $display("automatic-play hits   : %0d", hits);
    $display("all-lanes-stuck cycles: %0d", stuck);
    $display("automatic level resets: %0d", auto_resets);
    $display("--------------------------------------------------");
    if (errors==0) begin
      $display("system_tb: PASS");
      $finish;
    end else begin
      $fatal(1, "system_tb: FAIL (%0d errors)", errors);
    end
  end

  initial begin
    #30000000;
    $fatal(1, "system_tb: timeout");
  end
endmodule
