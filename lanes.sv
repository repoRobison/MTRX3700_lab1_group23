module lane{
    input reg [MAX_LOAD_TIME:0] // The lane length should have a spot for seconds 0, 1, 2, .... max note length time
};

    al
    
    
    simple_fsm(
    input  logic clk,
    input  logic rst,
    output logic y
);

    typedef enum logic {S0, S1} state_type;
    state_type state, next_state;

    // Combinational: determine next state
    always_comb begin
        case (state)
            S0: next_state = S1;
            S1: next_state = S0;
        endcase
    end

    // Sequential: store current state
    always_ff @(posedge clk) begin
        if (rst)
            state <= S0;
        else
            state <= next_state;
    end

    // Moore output
    assign y = state;

endmodule
