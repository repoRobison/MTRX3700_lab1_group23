//=============================================================================
// button_input.sv  --  MTRX3700 Assignment 1, Piano Tiles
//
// Owns every asynchronous input to the design: the four lane keys, the reset
// switch, and the two level-select switches. Everything downstream of this
// module is synchronous, debounced, active high, and glitch free.
//
// Task division: this is the "button behaviour / no mashing" block.
//
// WHICH HALF OF R11 THIS DELIVERS
//   R11 has two independent halves and they belong to different owners:
//     "holding a KEY down must not score successive notes"
//         -> edge detection. A held key yields exactly one edge however long
//            it is held. See the OPEN INTERFACE DECISION below for WHERE that
//            edge detector lives; today it exists in BOTH this module and
//            lane_fsm, and exactly one of the two must survive.
//     "pressing early must carry some consequence beyond simply not scoring"
//         -> lane_fsm's FORFEIT state and score_counter's penalty.
//   Do not look for the second half here.
//
// INTERFACE, SETTLED BY THE GROUP README
//   The README writes the contract as "Task 1 -> Task 2: press_pulse[3:0]".
//   The signal is named `pulse` here; the README line should be amended to
//   match, because a port name mismatch is discovered at integration, which
//   is the worst possible time. Substance is unchanged: the edge detector
//   lives HERE, and Task 2 (timing + hit detection) consumes one-cycle
//   pulses, not levels.
//   An earlier revision recommended the opposite -- keeping the detector in
//   the consumer, matching Ed L2 3.4 reaction_time_fsm. The group contract
//   overrides that recommendation, and this module now owns R11's first half
//   outright rather than sharing it.
//
//   The objection to a pulse contract was that "exactly one cycle wide" is
//   unenforceable at a port, because the $fatal guarding it lives inside
//   translate_off and does not exist on the board. That objection is answered
//   STRUCTURALLY rather than by assertion:
//
//       pulse[n]   = press[n]   & ~press[n-1]
//       pulse[n+1] = press[n+1] & ~press[n]
//
//   If pulse[n] is high then press[n] is 1, so the second term is
//   identically 0. A pulse can therefore never span two cycles for ANY input
//   waveform -- it is one cycle by construction, not by convention. The
//   assertion below is retained only to catch an edit to that line.
//
//   `press` (the debounced level) is also exported. It costs no logic -- it is
//   the debounce output directly -- and it is what Q3 waveforms annotate to
//   show glitch rejection. It is NOT part of the Task 1 -> Task 2 contract.
//
// WHY THE SWITCHES ARE DEBOUNCED AND NOT MERELY SYNCHRONISED
//   A slide switch bounces on transition like any other mechanical contact.
//   Bounce on RELEASE of SW0 is the dangerous case: beat_gen places beat zero
//   on the exact clock cycle reset drops, so a bouncing release would start the
//   song, restart it, and start again. The symptom on stage is the game running
//   a beat out of step with the music, which reads as a timing bug rather than
//   as switch bounce.
//
// WHERE THE ACTIVE-LOW INVERSION LIVES
//   Here, once, at the point where raw pins enter the design. The mini-project
//   put it in top_level's port map, and its reasoning was that inverting inside
//   `debounce` would make a general-purpose reused module board-specific. That
//   reasoning does not apply to this module, whose entire job IS to describe
//   what this particular board does. Nothing downstream needs to know that KEY
//   is active low, and nothing else in the design should ever invert it again.
//=============================================================================
`timescale 1ns/1ps
`include "game_params.svh"

module button_input #(
    parameter int NUM_LANES     = `GP_NUM_LANES,
    parameter int KEY_DEBOUNCE  = `GP_DEBOUNCE_COUNTS,
    parameter int SW_DEBOUNCE   = `GP_SW_DEBOUNCE_COUNTS,
    parameter int POR_COUNTS    = `GP_POR_COUNTS
) (
    input  logic                 clk,

    // LANE INDEX CONVENTION -- read this before wiring LEDR.
    //   Brief 2.1: "Lane i uses HEXi and KEYi, while its hit indicator is
    //   LEDR(i+3)". Lanes are therefore ZERO-indexed: KEY0 is lane 0, drives
    //   HEX0, and its indicator is LEDR3.
    //
    //   The group README numbers the same lanes 1..4 ("KEY0 -> Lane 1"). That
    //   naming is harmless in prose and dangerous in RTL: computing
    //   LEDR(lane + 3) with the README's lane number puts KEY0's indicator on
    //   LEDR4 instead of LEDR3, and every lane is off by one. Indices in this
    //   module are the brief's, so pulse[0] IS KEY0 IS the README's
    //   "Lane 1".

    // Raw board pins. KEY is ACTIVE LOW; SW is active high.
    // top_level passes SW[2:0]; the remaining switches are free for other use
    // and are deliberately not routed through here.
    input  logic [NUM_LANES-1:0] KEY,
    input  logic [2:0]           SW,

    // Conditioned, active high, one clock domain.
    output logic [NUM_LANES-1:0] press,        // debounced level: key is down
    output logic [NUM_LANES-1:0] pulse,        // one cycle on the press edge
    output logic                 reset,        // SW0, plus power-on reset
    output logic [1:0]           level         // SW2:1, for level_select
);

    //-------------------------------------------------------------------------
    // Lane keys
    //-------------------------------------------------------------------------
    // One debounce per lane, each of which instantiates its own synchroniser,
    // so the two-flop metastability guard comes along for free. The lanes are
    // fully independent: nothing here couples one key to another, which is what
    // lets four keys be pressed in the same clock cycle.
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i = i + 1) begin : lane_keys
            debounce #(.DELAY_COUNTS(KEY_DEBOUNCE)) u_deb (
                .clk            (clk),
                .button         (~KEY[i]),     // <-- the inversion, exactly here
                .button_pressed (press[i])
            );
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Edge detection -- the half of R11 this module owns
    //-------------------------------------------------------------------------
    // `press` stays high for as long as the key is held. Without this, a level
    // sensitive consumer would see a fresh press on every clock edge of a long
    // hold, and holding all four keys would be a winning strategy.
    //
    // No reset on press_q, and that is deliberate: if a key is already held when
    // the game is reset, press and press_q are both high, no edge is produced,
    // and the player does not get a free note for having been leaning on the
    // button. Tested.
    logic [NUM_LANES-1:0] press_q;

    always_ff @(posedge clk) begin
        press_q <= press;
    end

    assign pulse = press & ~press_q;

    //-------------------------------------------------------------------------
    // Switches
    //-------------------------------------------------------------------------
    logic sw_reset, sw_level0, sw_level1;

    debounce #(.DELAY_COUNTS(SW_DEBOUNCE)) u_sw0 (
        .clk(clk), .button(SW[0]), .button_pressed(sw_reset));    // active high
    debounce #(.DELAY_COUNTS(SW_DEBOUNCE)) u_sw1 (
        .clk(clk), .button(SW[1]), .button_pressed(sw_level0));
    debounce #(.DELAY_COUNTS(SW_DEBOUNCE)) u_sw2 (
        .clk(clk), .button(SW[2]), .button_pressed(sw_level1));

    assign level = {sw_level1, sw_level0};

    //-------------------------------------------------------------------------
    // Power-on reset
    //-------------------------------------------------------------------------
    // Two distinct problems, and the first comment this module carried
    // described neither of them accurately. Both are now measured.
    //
    // 1. FOUR-STATE SIMULATION. `debounce` carries no reset, so `count` powers
    //    up x, (count != DELAY_COUNTS) evaluates x, the if/else-if/else chain
    //    falls through to its LAST arm, and button_pressed starts tracking
    //    prev_button within about four clocks. So sw_reset is x for roughly
    //    three cycles -- not, as previously claimed, until the switch value
    //    has propagated. Three cycles of x reset is still enough to put every
    //    lane_fsm and the score counter into an x state that Verilator and
    //    ModelSim then disagree about, which is the asymmetry the brief warns
    //    about in 2.5.
    //
    // 2. HARDWARE. Registers power up at 0, so there is no x -- but if SW0 is
    //    already UP when the board is configured, button_pressed cannot report
    //    it until the counter has run the full SW_DEBOUNCE window. Measured at
    //    the old POR of 50000 against a switch chain of 250004, reset dropped
    //    at 1 ms and did not re-assert until 5 ms: 200004 clocks of the game
    //    running while the player held the reset switch on.
    //
    // Sizing the POR above SW_DEBOUNCE + 4 closes both. The counter is seeded
    // with an `initial` block, the same mechanism rng uses for its LFSR seed
    // (Ed Lesson 2, 1.4), which Quartus honours as a power-up value on the
    // Cyclone V.
    localparam int POR_W = $clog2(POR_COUNTS + 1);

    logic [POR_W-1:0] por_count;
    logic             por_active;

    initial por_count = '0;

    assign por_active = (por_count != POR_W'(POR_COUNTS));

    always_ff @(posedge clk) begin
        if (por_active) por_count <= por_count + POR_W'(1);
    end

    // OR, not a mux, and the order matters in simulation: while por_active is
    // high the result is 1 even though sw_reset is still x, because x | 1 is 1.
    // That is precisely the property needed -- reset is known from cycle zero.
    assign reset = por_active | sw_reset;

    //-------------------------------------------------------------------------
    // Assertions
    //-------------------------------------------------------------------------
    // synthesis translate_off
    logic [NUM_LANES-1:0] pulse_q;
    always @(posedge clk) pulse_q <= pulse;

    always @(posedge clk) begin
        // A pulse two cycles wide would be counted twice by anything downstream.
        // Now that a stray press SUBTRACTS a point, a stuck pulse would drain
        // the score at fifty million points per second.
        if ((pulse & pulse_q) != '0)
            $fatal(1, "button_input: pulse wider than one cycle (%b)", pulse);

        // A pulse can only occur where the key is actually down. Note this
        // is structurally unreachable against the assign above -- press & ~q
        // & ~press is identically zero -- so it fires only if that line is
        // edited. That is its purpose: it is what catches a falling-edge
        // detector, and it is why it is kept despite looking redundant.
        if ((pulse & ~press) != '0)
            $fatal(1, "button_input: pulse asserted on a key that is not pressed");
    end

    initial begin
        if (POR_COUNTS < 1)
            $fatal(1, "button_input: POR_COUNTS must be at least 1");

        // params_tb can only see the DEFAULTS in game_params.svh; it cannot
        // see a testbench override. This guard is the same relation checked
        // per-INSTANCE, so a bench that scales the parameters apart fails
        // loudly here instead of silently releasing reset early.
        if (POR_COUNTS < SW_DEBOUNCE + 4)
            $fatal(1, "button_input: POR_COUNTS (%0d) must be >= SW_DEBOUNCE+4 (%0d), or reset releases before SW0's debounced value exists",
                   POR_COUNTS, SW_DEBOUNCE + 4);
    end
    // synthesis translate_on

endmodule
