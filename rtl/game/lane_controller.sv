module lane_controller (
    input             clk,
    input             reset,

    // Scheduler: note has just reached countdown 0
    input      [3:0]  due_notes,

    // Task 2: current zero-note has been resolved
    input      [3:0]  hit,
    input      [3:0]  miss,

    // Future-note information from scheduler
    input      [3:0]  future_active,

    input      [3:0]  future_countdown0,
    input      [3:0]  future_countdown1,
    input      [3:0]  future_countdown2,
    input      [3:0]  future_countdown3,

    // Sent to hit-detection logic
    output     [3:0]  lane_zero,

    // Sent to seven-segment decoders
    output reg [3:0]  lane_active,

    output reg [3:0]  display_countdown0,
    output reg [3:0]  display_countdown1,
    output reg [3:0]  display_countdown2,
    output reg [3:0]  display_countdown3
);

    /*
     * A bit is 1 while that lane currently has
     * a note sitting in the 0 / hit window.
     */
    reg [3:0] zero_active;


    // ---------------------------------------------------------
    // Zero-window state
    // ---------------------------------------------------------
    always @(posedge clk) begin

        if (reset) begin
            zero_active <= 4'b0000;
        end
        else begin

            /*
             * A due note enters the zero window.
             *
             * It stays there until Task 2 reports
             * either a successful hit or a miss.
             */
            zero_active <=
                (zero_active | due_notes)
                & ~(hit | miss);

        end

    end


    // Task 2 uses this to know which lanes are at zero.
    assign lane_zero = zero_active;


    // ---------------------------------------------------------
    // Display selection
    // ---------------------------------------------------------
    always @(*) begin

        // Lane 0
        if (zero_active[0]) begin
            lane_active[0]        = 1'b1;
            display_countdown0    = 4'd0;
        end
        else begin
            lane_active[0]        = future_active[0];
            display_countdown0    = future_countdown0;
        end


        // Lane 1
        if (zero_active[1]) begin
            lane_active[1]        = 1'b1;
            display_countdown1    = 4'd0;
        end
        else begin
            lane_active[1]        = future_active[1];
            display_countdown1    = future_countdown1;
        end


        // Lane 2
        if (zero_active[2]) begin
            lane_active[2]        = 1'b1;
            display_countdown2    = 4'd0;
        end
        else begin
            lane_active[2]        = future_active[2];
            display_countdown2    = future_countdown2;
        end


        // Lane 3
        if (zero_active[3]) begin
            lane_active[3]        = 1'b1;
            display_countdown3    = 4'd0;
        end
        else begin
            lane_active[3]        = future_active[3];
            display_countdown3    = future_countdown3;
        end

    end

endmodule
