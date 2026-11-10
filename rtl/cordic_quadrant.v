// ============================================================================
// Module:      cordic_quadrant
// Description: Full-circle [-pi, +pi] coarse quadrant folding unit.
//              Accepts signed Q3.13 radians (range [-4.0, +4.0) rad) and folds
//              all four quadrants symmetrically into [0, +pi/2] so that every
//              quadrant shares identical CORDIC convergence and sign-correction:
//                Q1 (2'b00): [  0,   +pi/2] -> folded =  angle_in       (+cos, +sin)
//                Q2 (2'b01): (+pi/2, +pi  ] -> folded =  pi - angle_in  (-cos, +sin)
//                Q3 (2'b10): [-pi,   -pi/2) -> folded =  angle_in + pi  (-cos, -sin)
//                Q4 (2'b11): [-pi/2,  0   ) -> folded = -angle_in       (+cos, -sin)
// ============================================================================

module cordic_quadrant #(
    parameter ANGLE_WIDTH = 16
)(
    input  wire signed [ANGLE_WIDTH-1:0] angle_in,
    output reg  signed [ANGLE_WIDTH-1:0] folded_angle,
    output reg         [1:0]             quadrant
);

    // Q3.13 thresholds (scale = 2^13 = 8192)
    localparam signed [ANGLE_WIDTH-1:0] ZERO_VAL      = {ANGLE_WIDTH{1'b0}};
    localparam signed [ANGLE_WIDTH-1:0] PI_VAL        = 16'sh6488; // +25736 = +pi
    localparam signed [ANGLE_WIDTH-1:0] PI_OVER_2     = 16'sh3244; // +12868 = +pi/2
    localparam signed [ANGLE_WIDTH-1:0] NEG_PI_OVER_2 = -PI_OVER_2;

    always @(*) begin
        if (angle_in >= ZERO_VAL && angle_in <= PI_OVER_2) begin
            quadrant     = 2'b00; // Q1
            folded_angle = angle_in;
        end else if (angle_in > PI_OVER_2) begin
            quadrant     = 2'b01; // Q2
            folded_angle = PI_VAL - angle_in;
        end else if (angle_in >= NEG_PI_OVER_2) begin
            quadrant     = 2'b11; // Q4
            folded_angle = -angle_in;
        end else begin
            quadrant     = 2'b10; // Q3
            folded_angle = angle_in + PI_VAL;
        end
    end

endmodule

