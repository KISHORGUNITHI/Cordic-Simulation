// ============================================================================
// Module:      cordic_datapath
// Description: Multiplier-free CORDIC rotation-mode datapath using 22-bit
//              internal fixed-point arithmetic (X/Y in Q3.19, Z in Q4.18).
//              2 MSB integer guard bits prevent intermediate CORDIC growth
//              overflow; 4 LSB fractional guard bits bound quantization error.
// ============================================================================

module cordic_datapath #(
    parameter ANGLE_WIDTH = 16, // Q3.13 folded angle input
    parameter INT_WIDTH   = 22, // X/Y: Q3.19, Z: Q4.18
    parameter ITER_BITS   = 4,
    parameter ATAN_WIDTH  = 18, // Q0.18 unsigned ROM input
    parameter EXTRA_FRAC  = 4
)(
    input  wire                          clk,
    input  wire                          rst,
    input  wire                          load_en,
    input  wire                          iter_en,
    input  wire signed [ANGLE_WIDTH-1:0] angle_in,
    input  wire        [ITER_BITS-1:0]   iter_count,
    input  wire        [ATAN_WIDTH-1:0]  atan_val,
    output wire signed [INT_WIDTH-1:0]   x_out,
    output wire signed [INT_WIDTH-1:0]   y_out
);

    // Pre-scaled initial vector: X0 = 1/K16 = 0.607252935 * 2^19 = 318375
    localparam signed [INT_WIDTH-1:0] X0_CONST = 22'sh04DBA7;
    localparam signed [INT_WIDTH-1:0] Y0_CONST = {INT_WIDTH{1'b0}};

    // Alignment shifts: Q3.13 -> Q4.18 (shift left by 1 + EXTRA_FRAC = 5)
    localparam ANGLE_SHIFT    = 1 + EXTRA_FRAC;
    localparam ANGLE_SIGN_EXT = INT_WIDTH - ANGLE_WIDTH - ANGLE_SHIFT;
    localparam ATAN_ZERO_EXT  = INT_WIDTH - ATAN_WIDTH;

    reg signed [INT_WIDTH-1:0] x_reg;
    reg signed [INT_WIDTH-1:0] y_reg;
    reg signed [INT_WIDTH-1:0] z_reg;

    wire                       sigma;
    wire signed [INT_WIDTH-1:0] x_shift;
    wire signed [INT_WIDTH-1:0] y_shift;
    wire signed [INT_WIDTH-1:0] angle_ext;
    wire signed [INT_WIDTH-1:0] atan_ext;
    wire signed [INT_WIDTH-1:0] x_next;
    wire signed [INT_WIDTH-1:0] y_next;
    wire signed [INT_WIDTH-1:0] z_next;

    // Rotation direction: sigma = 0 (Z >= 0, CCW), sigma = 1 (Z < 0, CW)
    assign sigma = z_reg[INT_WIDTH-1];

    // Arithmetic right shifts (sign bit replicated)
    assign x_shift = x_reg >>> iter_count;
    assign y_shift = y_reg >>> iter_count;

    // Align folded Q3.13 angle and unsigned Q0.18 atan_val to Q4.18
    assign angle_ext = $signed({{ANGLE_SIGN_EXT{angle_in[ANGLE_WIDTH-1]}}, angle_in, {ANGLE_SHIFT{1'b0}}});
    assign atan_ext  = $signed({{ATAN_ZERO_EXT{1'b0}}, atan_val});

    // Core CORDIC micro-rotation equations
    assign x_next = sigma ? (x_reg + y_shift) : (x_reg - y_shift);
    assign y_next = sigma ? (y_reg - x_shift) : (y_reg + x_shift);
    assign z_next = sigma ? (z_reg + atan_ext) : (z_reg - atan_ext);

    always @(posedge clk) begin
        if (rst) begin
            x_reg <= {INT_WIDTH{1'b0}};
            y_reg <= {INT_WIDTH{1'b0}};
            z_reg <= {INT_WIDTH{1'b0}};
        end else if (load_en) begin
            x_reg <= X0_CONST;
            y_reg <= Y0_CONST;
            z_reg <= angle_ext;
        end else if (iter_en) begin
            x_reg <= x_next;
            y_reg <= y_next;
            z_reg <= z_next;
        end
    end

    assign x_out = x_reg;
    assign y_out = y_reg;

endmodule

