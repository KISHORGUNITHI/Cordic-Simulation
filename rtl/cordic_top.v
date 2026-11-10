// ============================================================================
// Module:      cordic_top
// Description: Top-level structural CORDIC sine/cosine core.
//              Accepts signed Q3.13 radians over the full [-pi, +pi] circle
//              and produces signed Q1.15 sine and cosine outputs in 18 clock
//              cycles after the start edge (19 total cycles from start high).
// ============================================================================

module cordic_top #(
    parameter DATA_WIDTH  = 16,
    parameter ANGLE_WIDTH = 16,
    parameter INT_WIDTH   = 22,
    parameter ITER_BITS   = 4,
    parameter NUM_ITER    = 16,
    parameter ATAN_WIDTH  = 18,
    parameter EXTRA_FRAC  = 4
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         start,
    input  wire signed [ANGLE_WIDTH-1:0] angle_in,
    output wire                         done,
    output wire signed [DATA_WIDTH-1:0] sine_out,
    output wire signed [DATA_WIDTH-1:0] cosine_out
);

    // Input capture and quadrant state registers
    reg  signed [ANGLE_WIDTH-1:0] angle_latched;
    reg         [1:0]             quadrant_latched;

    // Quadrant pre-processing signals
    wire signed [ANGLE_WIDTH-1:0] folded_angle;
    wire        [1:0]             quadrant;

    // FSM control signals
    wire                          load_en;
    wire                          iter_en;
    wire                          cnt_rst;
    wire                          out_latch;
    wire                          fsm_done_unused;
    wire                          ready;

    // Iteration counter and ROM signals
    wire        [ITER_BITS-1:0]   iter_count;
    wire                          iter_done;
    wire        [ATAN_WIDTH-1:0]  atan_val;

    // Datapath output signals
    wire signed [INT_WIDTH-1:0]   x_result;
    wire signed [INT_WIDTH-1:0]   y_result;

    // Capture angle_in on accepted start edge so caller need not hold angle_in
    always @(posedge clk) begin
        if (rst)
            angle_latched <= {ANGLE_WIDTH{1'b0}};
        else if (ready && start)
            angle_latched <= angle_in;
    end

    // Latch quadrant synchronously with datapath Z0 load
    always @(posedge clk) begin
        if (rst)
            quadrant_latched <= 2'b00;
        else if (load_en)
            quadrant_latched <= quadrant;
    end

    // ---- Quadrant folding ----
    cordic_quadrant #(
        .ANGLE_WIDTH(ANGLE_WIDTH)
    ) u_quadrant (
        .angle_in    (angle_latched),
        .folded_angle(folded_angle),
        .quadrant    (quadrant)
    );

    // ---- Control FSM ----
    cordic_fsm u_fsm (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .iter_done(iter_done),
        .load_en  (load_en),
        .iter_en  (iter_en),
        .cnt_rst  (cnt_rst),
        .out_latch(out_latch),
        .done     (fsm_done_unused),
        .ready    (ready)
    );

    // ---- Iteration counter ----
    cordic_iter_counter #(
        .ITER_BITS(ITER_BITS),
        .NUM_ITER (NUM_ITER)
    ) u_counter (
        .clk      (clk),
        .rst      (rst),
        .cnt_rst  (cnt_rst),
        .iter_en  (iter_en),
        .count    (iter_count),
        .iter_done(iter_done)
    );

    // ---- Arctangent ROM ----
    cordic_atan_rom #(
        .ADDR_WIDTH(ITER_BITS),
        .ATAN_WIDTH(ATAN_WIDTH)
    ) u_rom (
        .addr    (iter_count),
        .atan_val(atan_val)
    );

    // ---- CORDIC arithmetic datapath ----
    cordic_datapath #(
        .ANGLE_WIDTH(ANGLE_WIDTH),
        .INT_WIDTH  (INT_WIDTH),
        .ITER_BITS  (ITER_BITS),
        .ATAN_WIDTH (ATAN_WIDTH),
        .EXTRA_FRAC (EXTRA_FRAC)
    ) u_datapath (
        .clk       (clk),
        .rst       (rst),
        .load_en   (load_en),
        .iter_en   (iter_en),
        .angle_in  (folded_angle),
        .iter_count(iter_count),
        .atan_val  (atan_val),
        .x_out     (x_result),
        .y_out     (y_result)
    );

    // ---- Output rounding, sign correction, saturation, and holding registers ----
    cordic_output_reg #(
        .DATA_WIDTH(DATA_WIDTH),
        .INT_WIDTH (INT_WIDTH),
        .EXTRA_FRAC(EXTRA_FRAC)
    ) u_outreg (
        .clk      (clk),
        .rst      (rst),
        .out_latch(out_latch),
        .x_in     (x_result),
        .y_in     (y_result),
        .quadrant (quadrant_latched),
        .cos_out  (cosine_out),
        .sin_out  (sine_out),
        .done_out (done)
    );

endmodule

