// ============================================================================
// Module:      cordic_atan_rom
// Description: Combinational 16-entry arctangent lookup table for CORDIC.
//              Stores round(atan(2^-i) * 2^18) in Q0.18 unsigned fixed-point
//              to match the 4 extra fractional guard bits in the datapath.
// ============================================================================

module cordic_atan_rom #(
    parameter ADDR_WIDTH = 4,
    parameter ATAN_WIDTH = 18
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [ATAN_WIDTH-1:0] atan_val
);

    always @(*) begin
        case (addr)
            4'd0:    atan_val = 18'd205887; // atan(2^0)   = 0.7853981634 rad (45.0000 deg)
            4'd1:    atan_val = 18'd121542; // atan(2^-1)  = 0.4636476090 rad (26.5651 deg)
            4'd2:    atan_val = 18'd64220;  // atan(2^-2)  = 0.2449786631 rad (14.0362 deg)
            4'd3:    atan_val = 18'd32599;  // atan(2^-3)  = 0.1243549945 rad ( 7.1250 deg)
            4'd4:    atan_val = 18'd16363;  // atan(2^-4)  = 0.0624188100 rad ( 3.5763 deg)
            4'd5:    atan_val = 18'd8189;   // atan(2^-5)  = 0.0312398334 rad ( 1.7899 deg)
            4'd6:    atan_val = 18'd4096;   // atan(2^-6)  = 0.0156237286 rad ( 0.8952 deg)
            4'd7:    atan_val = 18'd2048;   // atan(2^-7)  = 0.0078123411 rad ( 0.4476 deg)
            4'd8:    atan_val = 18'd1024;   // atan(2^-8)  = 0.0039062301 rad ( 0.2238 deg)
            4'd9:    atan_val = 18'd512;    // atan(2^-9)  = 0.0019531225 rad ( 0.1119 deg)
            4'd10:   atan_val = 18'd256;    // atan(2^-10) = 0.0009765622 rad ( 0.0560 deg)
            4'd11:   atan_val = 18'd128;    // atan(2^-11) = 0.0004882812 rad ( 0.0280 deg)
            4'd12:   atan_val = 18'd64;     // atan(2^-12) = 0.0002441406 rad ( 0.0140 deg)
            4'd13:   atan_val = 18'd32;     // atan(2^-13) = 0.0001220703 rad ( 0.0070 deg)
            4'd14:   atan_val = 18'd16;     // atan(2^-14) = 0.0000610352 rad ( 0.0035 deg)
            4'd15:   atan_val = 18'd8;      // atan(2^-15) = 0.0000305176 rad ( 0.0017 deg)
            default: atan_val = {ATAN_WIDTH{1'b0}};
        endcase
    end

endmodule

