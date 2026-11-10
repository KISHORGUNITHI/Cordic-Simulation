`timescale 1ns/1ps

module tb_cordic_iter_counter;

    parameter CLK_PERIOD = 20;

    reg        clk;
    reg        rst;
    reg        cnt_rst;
    reg        iter_en;
    wire [3:0] count;
    wire       iter_done;

    integer i;
    integer pass_count;
    integer fail_count;

    cordic_iter_counter dut (
        .clk      (clk),
        .rst      (rst),
        .cnt_rst  (cnt_rst),
        .iter_en  (iter_en),
        .count    (count),
        .iter_done(iter_done)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    task check_cond;
        input cond;
        input [8*40:1] msg;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s (count=%0d iter_done=%b)", msg, count, iter_done);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cordic_iter_counter.vcd");
        $dumpvars(0, tb_cordic_iter_counter);

        pass_count = 0;
        fail_count = 0;

        // 1. Synchronous reset
        rst     = 1'b1;
        cnt_rst = 1'b0;
        iter_en = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        check_cond((count === 4'd0) && (iter_done === 1'b0), "Reset clears count and iter_done");

        // 2. Hold when iter_en = 0
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check_cond((count === 4'd0) && (iter_done === 1'b0), "Hold at 0 when iter_en=0");

        // 3. Count 0..15 with iter_en = 1
        @(negedge clk);
        iter_en = 1'b1;
        for (i = 0; i < 16; i = i + 1) begin
            #1;
            check_cond(count === i[3:0], "Sequential count value");
            if (i < 15)
                check_cond(iter_done === 1'b0, "iter_done low before count 15");
            else
                check_cond(iter_done === 1'b1, "iter_done high at count 15 with iter_en=1");
            @(posedge clk);
        end

        // 4. cnt_rst resets count immediately on next clock
        @(negedge clk);
        iter_en = 1'b0;
        cnt_rst = 1'b1;
        @(posedge clk);
        #1;
        check_cond((count === 4'd0) && (iter_done === 1'b0), "cnt_rst clears count");

        $display("COUNTER TB RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $finish;
    end

endmodule

