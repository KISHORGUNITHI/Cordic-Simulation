`timescale 1ns/1ps

module tb_cordic_top;

    parameter CLK_PERIOD   = 20; // 50 MHz
    parameter RESET_CYCLES = 5;
    parameter MAX_WAIT     = 30;
    parameter ERROR_LIMIT  = 4;  // Max allowed error in Q1.15 LSBs

    reg                clk;
    reg                rst;
    reg                start;
    reg  signed [15:0] angle_in;
    wire               done;
    wire signed [15:0] sine_out;
    wire signed [15:0] cosine_out;

    integer pass_count;
    integer fail_count;
    integer wait_cnt;
    integer cos_err;
    integer sin_err;
    reg signed [15:0] saved_cos;
    reg signed [15:0] saved_sin;

    cordic_top dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .angle_in  (angle_in),
        .done      (done),
        .sine_out  (sine_out),
        .cosine_out(cosine_out)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Signed 16-bit absolute difference (handles negative-vs-zero wrap safely)
    function [15:0] abs_diff16;
        input signed [15:0] a;
        input signed [15:0] b;
        reg   signed [16:0] diff;
        begin
            diff       = a - b;
            abs_diff16 = (diff < 0) ? -diff : diff;
        end
    endfunction

    task do_reset;
        begin
            rst      = 1'b1;
            start    = 1'b0;
            angle_in = 16'sh0000;
            repeat (RESET_CYCLES) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            #1;
        end
    endtask

    task run_test;
        input signed [15:0] angle;
        input signed [15:0] exp_cos;
        input signed [15:0] exp_sin;
        input        [8*20:1] label;
        begin
            @(negedge clk);
            angle_in = angle;
            start    = 1'b1;
            @(posedge clk);
            #1;
            start    = 1'b0;
            // Change angle_in immediately after start to verify input capture
            angle_in = 16'sh0000;

            wait_cnt = 0;
            while (!done && wait_cnt < MAX_WAIT) begin
                @(posedge clk);
                #1;
                wait_cnt = wait_cnt + 1;
            end

            if (wait_cnt >= MAX_WAIT) begin
                $display("FAIL: %-14s | TIMEOUT waiting for done", label);
                fail_count = fail_count + 1;
            end else begin
                cos_err = abs_diff16(cosine_out, exp_cos);
                sin_err = abs_diff16(sine_out,   exp_sin);

                if (wait_cnt == 18 && cos_err <= ERROR_LIMIT && sin_err <= ERROR_LIMIT) begin
                    $display("PASS: %-14s | lat=%2d | cos=0x%04h (err=%0d) | sin=0x%04h (err=%0d)",
                             label, wait_cnt, cosine_out[15:0], cos_err, sine_out[15:0], sin_err);
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL: %-14s | lat=%2d | cos=0x%04h exp=0x%04h (err=%0d) | sin=0x%04h exp=0x%04h (err=%0d)",
                             label, wait_cnt, cosine_out[15:0], exp_cos[15:0], cos_err,
                             sine_out[15:0], exp_sin[15:0], sin_err);
                    fail_count = fail_count + 1;
                end

                // Verify done is a single-cycle pulse and outputs hold afterwards
                saved_cos = cosine_out;
                saved_sin = sine_out;
                @(posedge clk);
                #1;
                if (done !== 1'b0 || cosine_out !== saved_cos || sine_out !== saved_sin) begin
                    $display("FAIL: %-14s | done pulse width or output hold error", label);
                    fail_count = fail_count + 1;
                end
            end

            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("cordic_tb.vcd");
        $dumpvars(0, tb_cordic_top);

        pass_count = 0;
        fail_count = 0;

        $display("=================================================================");
        $display("  CORDIC Integration Testbench (Q3.13 Full-Circle -> Q1.15)      ");
        $display("=================================================================");

        do_reset;

        // Verify reset outputs
        if (done !== 1'b0 || cosine_out !== 16'sh0000 || sine_out !== 16'sh0000) begin
            $display("FAIL: Reset state check failed");
            fail_count = fail_count + 1;
        end else begin
            $display("PASS: Reset outputs cleared");
            pass_count = pass_count + 1;
        end

        // Quadrant 1 [0 to +90 deg] (angle_in in Q3.13)
        run_test(16'sh0000, 16'sh7FFF, 16'sh0000, "T01_0deg");
        run_test(16'sh0861, 16'sh7BA3, 16'sh2121, "T02_15deg");
        run_test(16'sh10C1, 16'sh6EDA, 16'sh4000, "T03_30deg");
        run_test(16'sh1922, 16'sh5A82, 16'sh5A82, "T04_45deg");
        run_test(16'sh2183, 16'sh4000, 16'sh6EDA, "T05_60deg");
        run_test(16'sh29E3, 16'sh2121, 16'sh7BA3, "T06_75deg");
        run_test(16'sh3244, 16'sh0000, 16'sh7FFF, "T07_90deg");

        // Quadrant 2 (+90 to +180 deg]
        run_test(16'sh4305, 16'shC000, 16'sh6EDA, "T08_120deg");
        run_test(16'sh4B66, 16'shA57E, 16'sh5A82, "T09_135deg");
        run_test(16'sh53C7, 16'sh9126, 16'sh4000, "T10_150deg");
        run_test(16'sh6488, 16'sh8000, 16'sh0000, "T11_180deg");

        // Quadrant 4 [-90 to 0 deg)
        run_test(16'shF79F, 16'sh7BA3, 16'shDEDF, "T12_neg15deg");
        run_test(16'shEF3F, 16'sh6EDA, 16'shC000, "T13_neg30deg");
        run_test(16'shE6DE, 16'sh5A82, 16'shA57E, "T14_neg45deg");
        run_test(16'shDE7D, 16'sh4000, 16'sh9126, "T15_neg60deg");
        run_test(16'shD61D, 16'sh2121, 16'sh845D, "T16_neg75deg");
        run_test(16'shCDBC, 16'sh0000, 16'sh8000, "T17_neg90deg");

        // Quadrant 3 [-180 to -90 deg)
        run_test(16'shBCFB, 16'shC000, 16'sh9126, "T18_neg120deg");
        run_test(16'shB49A, 16'shA57E, 16'shA57E, "T19_neg135deg");
        run_test(16'shAC39, 16'sh9126, 16'shC000, "T20_neg150deg");
        run_test(16'sh9B78, 16'sh8000, 16'sh0000, "T21_neg180deg");

        // Zero-gap back-to-back test: assert second start on the exact cycle done=1
        $display("--- Zero-gap back-to-back test ---");
        @(negedge clk);
        angle_in = 16'sh1922; // 45 deg
        start    = 1'b1;
        @(posedge clk);
        #1;
        start    = 1'b0;

        wait_cnt = 0;
        while (!done && wait_cnt < MAX_WAIT) begin
            @(posedge clk);
            #1;
            wait_cnt = wait_cnt + 1;
        end

        cos_err = abs_diff16(cosine_out, 16'sh5A82);
        sin_err = abs_diff16(sine_out,   16'sh5A82);
        if (done === 1'b1 && cos_err <= ERROR_LIMIT && sin_err <= ERROR_LIMIT) begin
            $display("PASS: T22_BB_45deg   | cos=0x%04h | sin=0x%04h", cosine_out[15:0], sine_out[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: T22_BB_45deg");
            fail_count = fail_count + 1;
        end

        // Launch 30 deg on the very next rising edge while done == 1
        @(negedge clk);
        angle_in = 16'sh10C1; // 30 deg
        start    = 1'b1;
        @(posedge clk);
        #1;
        start    = 1'b0;

        wait_cnt = 0;
        while (!done && wait_cnt < MAX_WAIT) begin
            @(posedge clk);
            #1;
            wait_cnt = wait_cnt + 1;
        end

        cos_err = abs_diff16(cosine_out, 16'sh6EDA);
        sin_err = abs_diff16(sine_out,   16'sh4000);
        if (done === 1'b1 && wait_cnt == 18 && cos_err <= ERROR_LIMIT && sin_err <= ERROR_LIMIT) begin
            $display("PASS: T23_BB_30deg   | cos=0x%04h | sin=0x%04h", cosine_out[15:0], sine_out[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: T23_BB_30deg   | lat=%0d cos=0x%04h sin=0x%04h", wait_cnt, cosine_out[15:0], sine_out[15:0]);
            fail_count = fail_count + 1;
        end

        // Start-while-busy immunity test (spurious start during ITERATE ignored)
        $display("--- Start-while-busy immunity test ---");
        @(negedge clk);
        angle_in = 16'sh2183; // 60 deg
        start    = 1'b1;
        @(posedge clk);
        #1;
        start    = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        angle_in = 16'sh0000; // Spurious 0 deg pulse mid-iteration
        start    = 1'b1;
        @(posedge clk);
        #1;
        start    = 1'b0;

        wait_cnt = 0;
        while (!done && wait_cnt < MAX_WAIT) begin
            @(posedge clk);
            #1;
            wait_cnt = wait_cnt + 1;
        end

        cos_err = abs_diff16(cosine_out, 16'sh4000);
        sin_err = abs_diff16(sine_out,   16'sh6EDA);
        if (done === 1'b1 && cos_err <= ERROR_LIMIT && sin_err <= ERROR_LIMIT) begin
            $display("PASS: T24_BusyIgnore | cos=0x%04h | sin=0x%04h", cosine_out[15:0], sine_out[15:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: T24_BusyIgnore | cos=0x%04h sin=0x%04h", cosine_out[15:0], sine_out[15:0]);
            fail_count = fail_count + 1;
        end

        // Mid-computation synchronous reset recovery test
        $display("--- Mid-computation reset recovery test ---");
        @(negedge clk);
        angle_in = 16'sh2183; // 60 deg
        start    = 1'b1;
        @(posedge clk);
        #1;
        start    = 1'b0;
        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        run_test(16'sh1922, 16'sh5A82, 16'sh5A82, "T25_AfterReset");

        $display("=================================================================");
        $display("  FINAL RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("  STATUS: ALL TESTS PASSED");
        else
            $display("  STATUS: SOME TESTS FAILED");
        $display("=================================================================");

        $finish;
    end

    // Global watchdog
    initial begin
        #(CLK_PERIOD * 4000);
        $display("WATCHDOG: Simulation exceeded time limit");
        $finish;
    end

endmodule

