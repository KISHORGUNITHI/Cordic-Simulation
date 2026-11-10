`timescale 1ns/1ps

module tb_cordic_atan_rom;

    reg  [3:0]  addr;
    wire [17:0] atan_val;

    reg  [17:0] expected [0:15];
    integer     i;
    integer     pass_count;
    integer     fail_count;

    cordic_atan_rom dut (
        .addr    (addr),
        .atan_val(atan_val)
    );

    initial begin
        $dumpfile("tb_cordic_atan_rom.vcd");
        $dumpvars(0, tb_cordic_atan_rom);

        expected[0]  = 18'd205887;
        expected[1]  = 18'd121542;
        expected[2]  = 18'd64220;
        expected[3]  = 18'd32599;
        expected[4]  = 18'd16363;
        expected[5]  = 18'd8189;
        expected[6]  = 18'd4096;
        expected[7]  = 18'd2048;
        expected[8]  = 18'd1024;
        expected[9]  = 18'd512;
        expected[10] = 18'd256;
        expected[11] = 18'd128;
        expected[12] = 18'd64;
        expected[13] = 18'd32;
        expected[14] = 18'd16;
        expected[15] = 18'd8;

        pass_count = 0;
        fail_count = 0;

        for (i = 0; i < 16; i = i + 1) begin
            addr = i[3:0];
            #5;
            if (atan_val === expected[i]) begin
                $display("PASS: addr=%2d | atan_val=%6d (0x%05h)", i, atan_val, atan_val);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: addr=%2d | got=%6d exp=%6d", i, atan_val, expected[i]);
                fail_count = fail_count + 1;
            end
        end

        $display("ROM TB RESULTS: %0d PASS, %0d FAIL", pass_count, fail_count);
        $finish;
    end

endmodule
