`timescale 1ns/1ps

module tb_cordic_datapath;

    parameter CLK_PERIOD = 20;

    reg                clk;
    reg                rst;
    reg                load_en;
    reg                iter_en;
    reg  signed [15:0] angle_in;
    reg         [3:0]  iter_count;
    wire        [17:0] atan_val;
    wire signed [21:0] x_out;
    wire signed [21:0] y_out;

    integer i;
    integer cos_q15;
    integer sin_q15;
    integer cos_err;
    integer sin_err;
    integer pass_count;
    integer fail_count;

    cordic_atan_rom u_rom (
        .addr    (iter_count),
        .atan_val(atan_val)
    );

    cordic_datapath dut (
        .clk       (clk),
        .rst       (rst),
        .load_en   (load_en),
        .iter_en   (iter_en),
        .angle_in  (angle_in),
        .iter_count(iter_count),
        .atan_val  (atan_val),
        .x_out     (x_out),
        .y_out     (y_out)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    task run_datapath_angle;
        input signed [15:0] ang;
        input signed [15:0] exp_cos;
        input signed [15:0] exp_sin;
        input        [8*20:1] label;
        begin
            // Load phase
            @(negedge clk);
            angle_in   = ang;
            load_en    = 1'b1;
            iter_en    = 1'b0;
            iter_count = 4'd0;
            @(posedge clk);
            #1;
            load_en = 1'b0;

            if (x_out !== 22'sh04DBA7 || y_out !== 22'sd0) begin
                $display("FAIL: %0s load mismatch x=%0d y=%0d", label, x_out, y_out);
                fail_count = fail_count + 1;
            end

            // 16 CORDIC iterations
            for (i = 0; i < 16; i = i + 1) begin
                @(negedge clk);
                iter_count = i[3:0];
                iter_en    = 1'b1;
                @(posedge clk);
                #1;
            end
            iter_en = 1'b0;

            // Round Q3.19 -> Q1.15 and saturate 32768 -> 32767 for verification
            cos_q15 = (x_out + 22'sd8) >>> 4;
            sin_q15 = (y_out + 22'sd8) >>> 4;
            if (cos_q15 > 32767) cos_q15 = 32767;
            if (sin_q15 > 32767) sin_q15 = 32767;

            cos_err = (cos_q15 >= exp_cos) ? (cos_q15 - exp_cos) : (exp_cos - cos_q15);
            sin_err = (sin_q15 >= exp_sin) ? (sin_q15 - exp_sin) : (exp_sin - sin_q15);

            if (cos_err <= 2 && sin_err <= 2) begin
                $display("PASS: %-12s | cos=0x%04h (err=%0d) | sin=0x%04h (err=%0d)",
                         label, cos_q15[15:0], cos_err, sin_q15[15:0], sin_err);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %-12s | cos=%0d exp=%0d (err=%0d) | sin=%0d exp=%0d (err=%0d)",
                         label, cos_q15, exp_cos, cos_err, sin_q15, exp_sin, sin_err);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cordic_datapath.vcd");
        $dumpvars(0, tb_cordic_datapath);

        pass_count = 0;
        fail_count = 0;
        rst        = 1'b1;
        load_en    = 1'b0;
        iter_en    = 1'b0;
        angle_in   = 16'sd0;
        iter_count = 4'd0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        run_datapath_angle(16'sh0000, 16'sh7FFF, 16'sh0000, "0_deg");
        run_datapath_angle(16'sh10C1, 16'sh6EDA, 16'sh4000, "30_deg");
        run_datapath_angle(16'sh1922, 16'sh5A82, 16'sh5A82, "45_deg");
        run_datapath_angle(16'sh2183, 16'sh4000, 16'sh6EDA, "60_deg");
        run_datapath_angle(16'sh3244, 16'sh0000, 16'sh7FFF, "90_deg");

        $display("DATAPATH TB RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $finish;
    end

endmodule

