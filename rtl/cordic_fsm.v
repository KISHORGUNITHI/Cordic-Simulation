// ============================================================================
// Module:      cordic_fsm
// Description: 4-state Moore finite state machine controlling the serial
//              iterative CORDIC datapath, counter, and output latch.
//              States: IDLE -> LOAD -> ITERATE -> DONE -> IDLE
// ============================================================================

module cordic_fsm (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire iter_done,
    output reg  load_en,
    output reg  iter_en,
    output reg  cnt_rst,
    output reg  out_latch,
    output reg  done,
    output reg  ready
);

    localparam [1:0] IDLE    = 2'b00;
    localparam [1:0] LOAD    = 2'b01;
    localparam [1:0] ITERATE = 2'b10;
    localparam [1:0] DONE    = 2'b11;

    reg [1:0] state, next_state;

    // Sequential state register (synchronous active-high reset)
    always @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Combinational next-state logic
    always @(*) begin
        case (state)
            IDLE:    next_state = start     ? LOAD : IDLE;
            LOAD:    next_state = ITERATE;
            ITERATE: next_state = iter_done ? DONE : ITERATE;
            DONE:    next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Combinational Moore output decode (defaults prevent inferred latches)
    always @(*) begin
        load_en   = 1'b0;
        iter_en   = 1'b0;
        cnt_rst   = 1'b0;
        out_latch = 1'b0;
        done      = 1'b0;
        ready     = 1'b0;

        case (state)
            IDLE: begin
                cnt_rst = 1'b1;
                ready   = 1'b1;
            end
            LOAD: begin
                load_en = 1'b1;
                cnt_rst = 1'b1;
            end
            ITERATE: begin
                iter_en = 1'b1;
            end
            DONE: begin
                out_latch = 1'b1;
                done      = 1'b1;
            end
            default: begin
                cnt_rst = 1'b1;
                ready   = 1'b1;
            end
        endcase
    end

endmodule

