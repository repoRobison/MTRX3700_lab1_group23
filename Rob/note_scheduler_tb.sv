`timescale 1ns/1ps

module note_scheduler_tb;
    logic clk = 1'b0;
    logic reset = 1'b0;
    logic beat_tick = 1'b0;
    logic [9:0] random_value = 10'd0;
    logic [3:0] countdown_min = 4'd3;
    logic [3:0] countdown_mask = 4'd3;
    logic [3:0] spawn_cadence = 4'd1;
    logic [1:0] max_chord = 2'd1;

    wire [3:0] due_notes;
    wire [3:0] countdown0, countdown1, countdown2, countdown3;
    wire [3:0] future_active;

    integer errors = 0;
    integer largest_due = 0;
    logic [3:0] sampled_due;

    note_scheduler #(
        .RNG_WIDTH(10), .RESERVE_W(16), .SPAWN_RETRIES(4)
    ) dut (
        .clk(clk), .reset(reset), .beat_tick(beat_tick),
        .random_value(random_value),
        .countdown_min(countdown_min), .countdown_mask(countdown_mask),
        .spawn_cadence(spawn_cadence), .max_chord(max_chord),
        .due_notes(due_notes),
        .countdown0(countdown0), .countdown1(countdown1),
        .countdown2(countdown2), .countdown3(countdown3),
        .future_active(future_active)
    );

    always #5 clk = ~clk;

    function automatic integer bit_count(input logic [3:0] value);
        integer n;
        begin
            bit_count = 0;
            for (n = 0; n < 4; n = n + 1)
                bit_count = bit_count + value[n];
        end
    endfunction

    task automatic check(input bit condition, input string what);
        if (!condition) begin
            errors = errors + 1;
            $display("  FAIL: %s (t=%0t due=%b active=%b cd=%0d,%0d,%0d,%0d)",
                     what, $time, due_notes, future_active,
                     countdown0, countdown1, countdown2, countdown3);
        end
    endtask

    task automatic reset_scheduler;
        begin
            @(negedge clk);
            reset = 1'b1;
            beat_tick = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            reset = 1'b0;
            largest_due = 0;
        end
    endtask

    task automatic beat(input logic [9:0] rnd);
        integer due_count;
        begin
            @(negedge clk);
            random_value = rnd;
            beat_tick = 1'b1;
            @(posedge clk);
            #1;
            sampled_due = due_notes;
            due_count = bit_count(due_notes);
            if (due_count > largest_due) largest_due = due_count;
            @(negedge clk);
            beat_tick = 1'b0;
            @(posedge clk);
            #1;
            check(due_notes == 4'b0000, "due_notes is not a one-clock pulse");
        end
    endtask

    initial begin
        $display("T1 Easy/Medium cap rejects a second lane at one resolve time");
        countdown_min  = 4'd3;
        countdown_mask = 4'd3;
        spawn_cadence  = 4'd1;
        max_chord      = 2'd1;
        reset_scheduler();

        // Beat 1: lane 0 at 4. Beat 2: lane 1 at 3, which would resolve on
        // the same future beat after the first schedule shifts from 4 to 3.
        beat(10'd8);
        beat(10'd2);
        spawn_cadence = 4'd15;
        beat(10'd0);
        beat(10'd0);
        beat(10'd0);
        check(sampled_due == 4'b0001,
              "max_chord=1 did not leave exactly the first due note");
        check(largest_due <= 1,
              "max_chord=1 allowed simultaneous due lanes");

        $display("T2 Hard cap permits two lanes but still caps the resolve slot");
        spawn_cadence = 4'd1;
        max_chord = 2'd2;
        reset_scheduler();
        beat(10'd8);  // lane 0, countdown 4
        beat(10'd2);  // lane 1, countdown 3 -> same resolve time
        beat(10'd4);  // lane 2, countdown 3 -> same resolve time, rejected
        spawn_cadence = 4'd15;
        beat(10'd0);
        beat(10'd0);
        check(sampled_due == 4'b0011,
              "max_chord=2 did not produce the expected two-lane chord");
        check(largest_due == 2,
              "max_chord=2 did not enforce exactly a two-lane maximum");

        $display("T3 spawn_cadence is used at run time");
        countdown_min  = 4'd3;
        countdown_mask = 4'd0;
        spawn_cadence  = 4'd2;
        max_chord      = 2'd1;
        reset_scheduler();
        beat(10'd4);  // lane 2; first cadence tick must not spawn
        check(future_active == 4'b0000,
              "cadence=2 spawned on the first beat");
        beat(10'd4);  // second cadence tick spawns lane 2 at countdown 3
        check(future_active == 4'b0100 && countdown2 == 4'd3,
              "cadence=2 did not spawn on the second beat");

        if (errors == 0) begin
            $display("note_scheduler_tb: PASS");
            $finish;
        end else begin
            $display("note_scheduler_tb: FAIL (%0d errors)", errors);
            $fatal(1, "note_scheduler_tb failed");
        end
    end

    initial begin
        #100000;
        $fatal(1, "note_scheduler_tb: timeout");
    end
endmodule
