`timescale 1ns/1ns
module system_tb;
  localparam int CPMS=20, KDB=2, SDB=8, POR=12;
  logic CLOCK_50=0; logic [3:0] KEY=4'hF; logic [9:0] SW=10'b0;
  wire [9:0] LEDR; wire [6:0] HEX0,HEX1,HEX2,HEX3,HEX4,HEX5;
  top_level #(.CLKS_PER_MS(CPMS),.KEY_DEBOUNCE(KDB),.SW_DEBOUNCE(SDB),.POR_COUNTS(POR))
    dut(.CLOCK_50,.KEY,.SW,.LEDR,.HEX0,.HEX1,.HEX2,.HEX3,.HEX4,.HEX5);
  always #10 CLOCK_50=~CLOCK_50;
  integer t,i,hits,stuck,auto_resets,errors,played_score,win_transitions;
  logic [9:0] previous_win_leds;
  // play perfectly: press a lane the cycle after it reaches zero
  always @(posedge CLOCK_50) begin
    for (i=0;i<4;i=i+1)
      KEY[i] <= ~(dut.lane_zero[i] & ~dut.press[i]);   // press once per zero
    if (dut.level_change_reset) auto_resets <= auto_resets + 1;
  end
  initial begin
    auto_resets=0; errors=0;
    SW = 10'b000000_0011;            // SW0=1 reset held, SW2:1=01 medium
    repeat(60) @(posedge CLOCK_50);
    SW[0]=1'b0;                      // release reset -> game starts
    repeat(100) @(posedge CLOCK_50);
    if (LEDR[9:7] != 3'b010) begin
      $display("FAIL: initial Medium level did not latch");
      errors=errors+1;
    end

    // Change to Easy without touching SW0. The debounced level change must
    // generate one internal reset and update the level indicator.
    SW[2:1]=2'b00;
    repeat(100) @(posedge CLOCK_50);
    if (LEDR[9:7] != 3'b100) begin
      $display("FAIL: switch-only level change did not select Easy");
      errors=errors+1;
    end
    if (auto_resets != 1) begin
      $display("FAIL: expected one automatic level reset, saw %0d", auto_resets);
      errors=errors+1;
    end

    hits=0; stuck=0;
    for (t=0;t<400000;t=t+1) begin
      @(posedge CLOCK_50);
      if (dut.any_hit!=0) hits=hits+1;
      if (dut.lane_zero==4'b1111) stuck=stuck+1;
    end
    played_score=dut.score_value;

    // Drive the terminal score to exercise integration of the existing score
    // saturation with the new stop/flash behaviour.
    force dut.u_score.score = 7'd99;
    repeat(4) @(posedge CLOCK_50);
    if (!dut.won || dut.score_value != 7'd99) begin
      $display("FAIL: score 99 did not assert the terminal won state");
      errors=errors+1;
    end
    if (dut.lane_active != 4'b0000 || dut.due_notes != 4'b0000) begin
      $display("FAIL: gameplay did not stop and clear at score 99");
      errors=errors+1;
    end
    if (HEX0 != 7'b1111111 || HEX1 != 7'b1111111
        || HEX2 != 7'b1111111 || HEX3 != 7'b1111111) begin
      $display("FAIL: lane displays did not blank at game over");
      errors=errors+1;
    end

    previous_win_leds=LEDR; win_transitions=0;
    for (t=0;t<(2*250*CPMS+100);t=t+1) begin
      @(posedge CLOCK_50);
      if (LEDR != previous_win_leds) win_transitions=win_transitions+1;
      previous_win_leds=LEDR;
      if (LEDR != 10'b0000000000 && LEDR != 10'b1111111111) begin
        $display("FAIL: game-over display did not own all ten LEDs");
        errors=errors+1;
      end
    end
    if (win_transitions < 2) begin
      $display("FAIL: game-over LEDs did not flash, transitions=%0d", win_transitions);
      errors=errors+1;
    end
    $display("--------------------------------------------------");
    $display("hits registered      : %0d", hits);
    $display("score (binary)       : %0d   HEX5=%b HEX4=%b", dut.score_value,HEX5,HEX4);
    $display("cycles all-lanes-stuck: %0d  (deadlock indicator)", stuck);
    $display("final lane_zero      : %b", dut.lane_zero);
    $display("LEDR                 : %b  [9:7 level | 6:3 hits | 2:0 mult]", LEDR);
    $display("--------------------------------------------------");
    if (played_score>0 && stuck==0 && errors==0) begin
      $display("SYSTEM PASS: game plays, level auto-restarts, game over flashes, and no deadlock");
      $finish;
    end else begin
      $fatal(1, "SYSTEM FAIL: played_score=%0d stuck=%0d errors=%0d",
             played_score, stuck, errors);
    end
  end
endmodule
