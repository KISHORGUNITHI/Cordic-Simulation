`timescale 1ns/1ps

module tb_cordic_quadrant;

    reg  signed [15:0] angle_in;
    wire signed [15:0] folded_angle;
    wire        [1:0]  quadrant;

    integer pass_count;
    integer fail_count;

    cordic_quadrant dut (
        .angle_in    (angle_in),
        .folded_angle(folded_angle),
        .quadrant    (quadrant)
    );

    task check_quad;
        input signed [15:0] ang;
        input        [1:0]  exp_q;
        input signed [15:0] exp_fold;
        input        [8*24:1] label;
        begin
            angle_in = ang;
            #5;
            if (quadrant === exp_q && folded_angle === exp_fold) begin
                $display("PASS: %-10s | in=%6d -> q=%b folded=%6d",
                         label, ang, quadrant, folded_angle);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %-10s | in=%6d | got(q=%b, fold=%6d) exp(q=%b, fold=%6d)",
                         label, ang, quadrant, folded_angle, exp_q, exp_fold);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cordic_quadrant.vcd");
        $dumpvars(0, tb_cordic_quadrant);

        pass_count = 0;
        fail_count = 0;

        check_quad(16'sh0000, 2'b00, 16'sd0,     "0_deg");
        check_quad(16'sh1922, 2'b00, 16'sd6434,  "45_deg");
        check_quad(16'sh3244, 2'b00, 16'sd12868, "90_deg");
        check_quad(16'sh4305, 2'b01, 16'sd8579,  "120_deg");
        check_quad(16'sh4B66, 2'b01, 16'sd6434,  "135_deg");
        check_quad(16'sh6488, 2'b01, 16'sd0,     "180_deg");
        check_quad(16'shE6DE, 2'b11, 16'sd6434,  "neg45_deg");
        check_quad(16'shCDBC, 2'b11, 16'sd12868, "neg90_deg");
        check_quad(16'shBCFB, 2'b10, 16'sd8579,  "neg120_deg");
        check_quad(16'shB49A, 2'b10, 16'sd6434,  "neg135_deg");
        check_quad(16'sh9B78, 2'b10, 16'sd0,     "neg180_deg");

        $display("QUADRANT TB RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $finish;
    end

endmodule

