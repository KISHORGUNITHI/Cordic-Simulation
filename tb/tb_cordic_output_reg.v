`timescale 1ns/1ps

module tb_cordic_output_reg;

    parameter CLK_PERIOD = 20;

    reg                clk;
    reg                rst;
    reg                out_latch;
    reg  signed [21:0] x_in;
    reg  signed [21:0] y_in;
    reg         [1:0]  quadrant;
    wire signed [15:0] cos_out;
    wire signed [15:0] sin_out;
    wire               done_out;

    integer pass_count;
    integer fail_count;

    cordic_output_reg dut (
        .clk      (clk),
        .rst      (rst),
        .out_latch(out_latch),
        .x_in     (x_in),
        .y_in     (y_in),
        .quadrant (quadrant),
        .cos_out  (cos_out),
        .sin_out  (sin_out),
        .done_out (done_out)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    task check_output;
        input signed [15:0] exp_cos;
        input signed [15:0] exp_sin;
        input               exp_done;
        input        [8*24:1] label;
        begin
            if (cos_out === exp_cos && sin_out === exp_sin && done_out === exp_done) begin
                $display("PASS: %-16s | cos=0x%04h sin=0x%04h done=%b", label, cos_out, sin_out, done_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %-16s | got(cos=0x%04h, sin=0x%04h, done=%b) exp(cos=0x%04h, sin=0x%04h, done=%b)",
                         label, cos_out, sin_out, done_out, exp_cos, exp_sin, exp_done);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cordic_output_reg.vcd");
        $dumpvars(0, tb_cordic_output_reg);

        pass_count = 0;
        fail_count = 0;

        // 1. Reset check
        rst       = 1'b1;
        out_latch = 1'b0;
        x_in      = 22'sd0;
        y_in      = 22'sd0;
        quadrant  = 2'b00;
        repeat (3) @(posedge clk);
        #1;
        check_output(16'sh0000, 16'sh0000, 1'b0, "RESET_CHECK");

        @(negedge clk);
        rst = 1'b0;

        // 2. Quadrant 1 (cos > 0, sin > 0): 0.7071 (approx 23170 << 4 = 370720 = 22'h05A820)
        @(negedge clk);
        x_in      = 22'sd370720; // 23170 in Q1.15 -> 0x5A82
        y_in      = 22'sd370720;
        quadrant  = 2'b00;       // Q1
        out_latch = 1'b1;
        @(posedge clk);
        #1;
        check_output(16'sh5A82, 16'sh5A82, 1'b1, "Q1_LATCH");

        // Verify hold when out_latch = 0
        @(negedge clk);
        out_latch = 1'b0;
        x_in      = 22'sd0;
        y_in      = 22'sd0;
        @(posedge clk);
        #1;
        check_output(16'sh5A82, 16'sh5A82, 1'b0, "Q1_HOLD");

        // 3. Quadrant 2 (cos < 0, sin > 0): negate cos
        @(negedge clk);
        x_in      = 22'sd370720;
        y_in      = 22'sd370720;
        quadrant  = 2'b01;       // Q2
        out_latch = 1'b1;
        @(posedge clk);
        #1;
        check_output(-16'sh5A82, 16'sh5A82, 1'b1, "Q2_LATCH");

        // 4. Quadrant 3 (cos < 0, sin < 0): negate cos, negate sin
        @(negedge clk);
        x_in      = 22'sd370720;
        y_in      = 22'sd370720;
        quadrant  = 2'b10;       // Q3
        out_latch = 1'b1;
        @(posedge clk);
        #1;
        check_output(-16'sh5A82, -16'sh5A82, 1'b1, "Q3_LATCH");

        // 5. Quadrant 4 (cos > 0, sin < 0): negate sin
        @(negedge clk);
        x_in      = 22'sd370720;
        y_in      = 22'sd370720;
        quadrant  = 2'b11;       // Q4
        out_latch = 1'b1;
        @(posedge clk);
        #1;
        check_output(16'sh5A82, -16'sh5A82, 1'b1, "Q4_LATCH");

        // 6. Saturation check: max positive saturation
        @(negedge clk);
        x_in      = 22'sd1000000; // > 32767 << 4
        y_in      = -22'sd1000000; // < -32768 << 4
        quadrant  = 2'b00;
        out_latch = 1'b1;
        @(posedge clk);
        #1;
        check_output(16'sh7FFF, -16'sh8000, 1'b1, "SATURATION");

        $display("OUTPUT_REG TB RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $finish;
    end

endmodule

