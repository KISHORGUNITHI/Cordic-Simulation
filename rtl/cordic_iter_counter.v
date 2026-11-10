// ============================================================================
// Module:      cordic_iter_counter
// Description: Synchronous 4-bit iteration counter (0 to NUM_ITER-1).
//              Asserts iter_done combinationally during the final iteration
//              when count == NUM_ITER - 1 and iter_en is high.
// ============================================================================

module cordic_iter_counter #(
    parameter ITER_BITS = 4,
    parameter NUM_ITER  = 16
)(
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 cnt_rst,
    input  wire                 iter_en,
    output reg  [ITER_BITS-1:0] count,
    output wire                 iter_done
);

    localparam [ITER_BITS-1:0] MAX_COUNT = NUM_ITER - 1;
    localparam [ITER_BITS-1:0] ONE_VAL   = {{(ITER_BITS-1){1'b0}}, 1'b1};

    always @(posedge clk) begin
        if (rst || cnt_rst)
            count <= {ITER_BITS{1'b0}};
        else if (iter_en)
            count <= count + ONE_VAL;
    end

    assign iter_done = (count == MAX_COUNT) && iter_en;

endmodule

