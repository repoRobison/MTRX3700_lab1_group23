//=============================================================================
// note_scheduler.sv -- difficulty-aware four-lane note scheduler
//
// A note is stored at schedule[lane][countdown]. On each beat the schedule
// shifts toward zero. New notes are attempted at the selected difficulty's
// cadence and countdown range. The aggregate occupancy of a resolve slot is
// checked across all lanes, which guarantees that Easy/Medium cannot create a
// chord while still allowing a two-note chord on Hard.
//=============================================================================

module note_scheduler #(
    parameter integer RNG_WIDTH     = 10,
    parameter integer RESERVE_W     = 16,
    parameter integer SPAWN_RETRIES = 4
) (
    input                       clk,
    input                       reset,
    input                       beat_tick,
    input      [RNG_WIDTH-1:0]  random_value,

    input      [3:0]            countdown_min,
    input      [3:0]            countdown_mask,
    input      [3:0]            spawn_cadence,
    input      [1:0]            max_chord,

    // One-clock pulse for every lane whose note reaches countdown zero.
    output reg [3:0]            due_notes,

    // Nearest scheduled note in each lane.
    output reg [3:0]            countdown0,
    output reg [3:0]            countdown1,
    output reg [3:0]            countdown2,
    output reg [3:0]            countdown3,

    // At least one scheduled note exists in each lane.
    output reg [3:0]            future_active
);

    reg [RESERVE_W-1:0] schedule      [0:3];
    reg [RESERVE_W-1:0] schedule_next [0:3];

    reg [3:0] cadence_count;
    reg [3:0] cadence_count_next;

    reg [1:0] base_lane;
    integer selected_time;
    integer selected_lane;
    integer chord_count;
    integer minimum_spacing;
    integer lane_i;
    integer slot_i;
    integer retry_i;
    reg valid_spawn;
    reg spawn_inserted;

    //-------------------------------------------------------------------------
    // Schedule movement and insertion
    //-------------------------------------------------------------------------
    always @(*) begin
        for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1)
            schedule_next[lane_i] = schedule[lane_i];

        cadence_count_next = cadence_count;
        base_lane          = random_value[2:1];
        selected_time      = countdown_min
                           + ((random_value >> 3) & countdown_mask);
        minimum_spacing    = countdown_min + 1;
        selected_lane      = 0;
        chord_count        = 0;
        valid_spawn        = 1'b0;
        spawn_inserted     = 1'b0;
        slot_i             = 0;
        retry_i            = 0;

        if (beat_tick) begin
            // Slot 1 becomes due on this edge; the stored schedule advances so
            // it is visible at slot 0 throughout the open hit window.
            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1)
                schedule_next[lane_i] = schedule[lane_i] >> 1;

            // A zero cadence is treated safely as one. Valid level parameters
            // never drive zero, but this prevents an underflow after bad input.
            if ((spawn_cadence <= 1)
                    || (cadence_count >= spawn_cadence - 1'b1)) begin
                cadence_count_next = 4'd0;

                // Retry the four lanes in a random cyclic order. Only one note
                // is inserted per cadence event.
                for (retry_i = 0; retry_i < SPAWN_RETRIES;
                     retry_i = retry_i + 1) begin
                    selected_lane = (base_lane + retry_i) & 3;
                    valid_spawn   = !spawn_inserted;

                    // Reject an out-of-range countdown defensively.
                    if ((selected_time < 1) || (selected_time >= RESERVE_W))
                        valid_spawn = 1'b0;

                    // Count all notes already reserved to resolve on the same
                    // beat. This is the cross-lane check missing previously.
                    chord_count = 0;
                    if ((selected_time >= 0) && (selected_time < RESERVE_W)) begin
                        for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1)
                            if (schedule_next[lane_i][selected_time])
                                chord_count = chord_count + 1;
                    end
                    if ((max_chord == 0) || (chord_count >= max_chord))
                        valid_spawn = 1'b0;

                    // Do not overlap notes too closely within one lane. Other
                    // lanes remain available through the retry loop.
                    for (slot_i = 0; slot_i < RESERVE_W;
                         slot_i = slot_i + 1) begin
                        if (schedule_next[selected_lane][slot_i]) begin
                            if (slot_i >= selected_time) begin
                                if ((slot_i - selected_time) < minimum_spacing)
                                    valid_spawn = 1'b0;
                            end else begin
                                if ((selected_time - slot_i) < minimum_spacing)
                                    valid_spawn = 1'b0;
                            end
                        end
                    end

                    if (valid_spawn) begin
                        schedule_next[selected_lane][selected_time] = 1'b1;
                        spawn_inserted = 1'b1;
                    end
                end
            end else begin
                cadence_count_next = cadence_count + 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // State and due-note pulse
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            due_notes     <= 4'b0000;
            cadence_count <= 4'd0;
            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1)
                schedule[lane_i] <= {RESERVE_W{1'b0}};
        end else begin
            if (beat_tick) begin
                due_notes[0] <= schedule[0][1];
                due_notes[1] <= schedule[1][1];
                due_notes[2] <= schedule[2][1];
                due_notes[3] <= schedule[3][1];
            end else begin
                due_notes <= 4'b0000;
            end

            cadence_count <= cadence_count_next;
            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1)
                schedule[lane_i] <= schedule_next[lane_i];
        end
    end

    //-------------------------------------------------------------------------
    // Nearest countdown in each lane
    //-------------------------------------------------------------------------
    integer display_i;
    always @(*) begin
        countdown0    = 4'd0;
        countdown1    = 4'd0;
        countdown2    = 4'd0;
        countdown3    = 4'd0;
        future_active = 4'b0000;

        for (display_i = 0; display_i < RESERVE_W;
             display_i = display_i + 1) begin
            if (schedule[0][display_i] && !future_active[0]) begin
                countdown0 = display_i[3:0];
                future_active[0] = 1'b1;
            end
            if (schedule[1][display_i] && !future_active[1]) begin
                countdown1 = display_i[3:0];
                future_active[1] = 1'b1;
            end
            if (schedule[2][display_i] && !future_active[2]) begin
                countdown2 = display_i[3:0];
                future_active[2] = 1'b1;
            end
            if (schedule[3][display_i] && !future_active[3]) begin
                countdown3 = display_i[3:0];
                future_active[3] = 1'b1;
            end
        end
    end

endmodule
