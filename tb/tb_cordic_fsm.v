`timescale 1ns/1ps

module tb_cordic_fsm;

    parameter CLK_PERIOD = 20;

    reg  clk;
    reg  rst;
    reg  start;
    reg  iter_done;
    wire load_en;
    wire iter_en;
    wire cnt_rst;
    wire out_latch;
    wire done;
    wire ready;

    integer i;
    integer pass_count;
    integer fail_count;

    cordic_fsm dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .iter_done(iter_done),
        .load_en  (load_en),
        .iter_en  (iter_en),
        .cnt_rst  (cnt_rst),
        .out_latch(out_latch),
        .done     (done),
        .ready    (ready)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    task check_outputs;
        input exp_load;
        input exp_iter;
        input exp_cnt_rst;
        input exp_latch;
        input exp_done;
        input exp_ready;
        input [8*32:1] state_name;
        begin
            if ({load_en, iter_en, cnt_rst, out_latch, done, ready} ===
                {exp_load, exp_iter, exp_cnt_rst, exp_latch, exp_done, exp_ready}) begin
                $display("PASS: %-8s outputs matched", state_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %-8s got=%b exp=%b", state_name,
                         {load_en, iter_en, cnt_rst, out_latch, done, ready},
                         {exp_load, exp_iter, exp_cnt_rst, exp_latch, exp_done, exp_ready});
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_cordic_fsm.vcd");
        $dumpvars(0, tb_cordic_fsm);

        pass_count = 0;
        fail_count = 0;

        // Reset -> IDLE
        rst       = 1'b1;
        start     = 1'b0;
        iter_done = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        check_outputs(0, 0, 1, 0, 0, 1, "IDLE_RST");

        // Release reset -> stay IDLE while start=0
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        #1;
        check_outputs(0, 0, 1, 0, 0, 1, "IDLE");

        // Pulse start -> LOAD
        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        check_outputs(1, 0, 1, 0, 0, 0, "LOAD");

        // Next cycle -> ITERATE (hold for 16 cycles)
        for (i = 0; i < 16; i = i + 1) begin
            if (i == 15) begin
                @(negedge clk);
                iter_done = 1'b1;
            end
            @(posedge clk);
            #1;
            if (i < 15)
                check_outputs(0, 1, 0, 0, 0, 0, "ITERATE");
            else
                check_outputs(0, 1, 0, 0, 0, 0, "ITER_15");
        end

        // Next cycle -> DONE
        @(negedge clk);
        iter_done = 1'b0;
        @(posedge clk);
        #1;
        check_outputs(0, 0, 0, 1, 1, 0, "DONE");

        // Next cycle -> IDLE
        @(posedge clk);
        #1;
        check_outputs(0, 0, 1, 0, 0, 1, "IDLE_END");

        $display("FSM TB RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $finish;
    end

endmodule

