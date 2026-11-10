// ============================================================================
// Module:      cordic_output_reg
// Description: Output rounding, quadrant sign reconstruction, saturation, and
//              output holding registers. Rounds Q3.19 -> Q1.15, applies the
//              latched quadrant signs prior to clamping (preventing -32768
//              negation wraparound), saturates to [-32768, +32767], and
//              registers done_out synchronously with cos_out and sin_out.
// ============================================================================

module cordic_output_reg #(
    parameter DATA_WIDTH = 16,
    parameter INT_WIDTH  = 22,
    parameter EXTRA_FRAC = 4
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         out_latch,
    input  wire signed [INT_WIDTH-1:0]  x_in,
    input  wire signed [INT_WIDTH-1:0]  y_in,
    input  wire        [1:0]            quadrant,
    output reg  signed [DATA_WIDTH-1:0] cos_out,
    output reg  signed [DATA_WIDTH-1:0] sin_out,
    output reg                          done_out
);

    localparam signed [INT_WIDTH-1:0]  ONE_EXT    = $signed({{(INT_WIDTH-1){1'b0}}, 1'b1});
    localparam signed [INT_WIDTH-1:0]  ROUND_BIAS = (EXTRA_FRAC > 0) ? (ONE_EXT <<< (EXTRA_FRAC - 1)) : {INT_WIDTH{1'b0}};
    localparam signed [INT_WIDTH-1:0]  Q15_MAX    = (ONE_EXT <<< (DATA_WIDTH - 1)) - ONE_EXT;
    localparam signed [INT_WIDTH-1:0]  Q15_MIN    = -(ONE_EXT <<< (DATA_WIDTH - 1));
    localparam signed [DATA_WIDTH-1:0] OUT_MAX    = {1'b0, {(DATA_WIDTH-1){1'b1}}};
    localparam signed [DATA_WIDTH-1:0] OUT_MIN    = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    wire signed [INT_WIDTH-1:0]  x_rounded;
    wire signed [INT_WIDTH-1:0]  y_rounded;
    wire                         cos_neg;
    wire                         sin_neg;
    wire signed [INT_WIDTH-1:0]  x_signed;
    wire signed [INT_WIDTH-1:0]  y_signed;
    wire signed [DATA_WIDTH-1:0] x_sat;
    wire signed [DATA_WIDTH-1:0] y_sat;

    // Round-to-nearest (drop EXTRA_FRAC fractional guard bits)
    assign x_rounded = (x_in + ROUND_BIAS) >>> EXTRA_FRAC;
    assign y_rounded = (y_in + ROUND_BIAS) >>> EXTRA_FRAC;

    // Quadrant sign reconstruction: Q2/Q3 negate cos; Q3/Q4 negate sin
    assign cos_neg = (quadrant == 2'b01) || (quadrant == 2'b10);
    assign sin_neg = (quadrant == 2'b10) || (quadrant == 2'b11);

    assign x_signed = cos_neg ? -x_rounded : x_rounded;
    assign y_signed = sin_neg ? -y_rounded : y_rounded;

    // Saturate to 16-bit signed Q1.15 [-32768, +32767]
    assign x_sat = (x_signed > Q15_MAX) ? OUT_MAX :
                   (x_signed < Q15_MIN) ? OUT_MIN :
                   $signed(x_signed[DATA_WIDTH-1:0]);

    assign y_sat = (y_signed > Q15_MAX) ? OUT_MAX :
                   (y_signed < Q15_MIN) ? OUT_MIN :
                   $signed(y_signed[DATA_WIDTH-1:0]);

    always @(posedge clk) begin
        if (rst) begin
            cos_out  <= {DATA_WIDTH{1'b0}};
            sin_out  <= {DATA_WIDTH{1'b0}};
            done_out <= 1'b0;
        end else begin
            done_out <= out_latch;
            if (out_latch) begin
                cos_out <= x_sat;
                sin_out <= y_sat;
            end
        end
    end

endmodule

