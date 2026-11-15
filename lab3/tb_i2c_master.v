`timescale 1ns/1ps
//==============================================================================
// Testbench для i2c_master (самоперевіряючий)
// Тести: 1) запис 0xA5  2) читання  3) запис 0x3C + читання  4) хибна адреса
//==============================================================================
module tb_i2c_master;
    reg        clk = 1'b0, rst = 1'b1;
    reg        start = 1'b0, rw = 1'b0;
    reg  [6:0] addr = 7'h00;
    reg  [7:0] wdata = 8'h00;
    wire       busy, done, ack_err, rdata_valid;
    wire [7:0] rdata;
    tri1       scl, sda;                  // tri1 = лінія з підтяжкою до 1 (pull-up)
    integer    errors = 0;

    always #10 clk = ~clk;                // 50 МГц

    i2c_master #(.CLK_DIV(125)) dut (.clk(clk), .rst(rst), .start(start), .rw(rw),
        .addr(addr), .wdata(wdata), .busy(busy), .done(done), .ack_err(ack_err),
        .rdata(rdata), .rdata_valid(rdata_valid), .scl(scl), .sda(sda));
    i2c_slave_model #(.ADDR(7'h50)) slave (.scl(scl), .sda(sda));

    task i2c_xfer(input r, input [6:0] a, input [7:0] d);
        begin
            @(negedge clk); rw = r; addr = a; wdata = d; start = 1'b1;
            @(negedge clk); start = 1'b0;
            @(posedge done);
            @(negedge clk);
        end
    endtask

    task check(input cond, input [255:0] name);
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    initial begin
        $dumpfile("tb_i2c_master.vcd");
        $dumpvars(0, tb_i2c_master);
        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);

        i2c_xfer(1'b0, 7'h50, 8'hA5);
        check(ack_err == 1'b0 && slave.mem == 8'hA5, "T1: write 0xA5");

        i2c_xfer(1'b1, 7'h50, 8'h00);
        check(ack_err == 1'b0 && rdata == 8'hA5, "T2: read back 0xA5");

        i2c_xfer(1'b0, 7'h50, 8'h3C);
        i2c_xfer(1'b1, 7'h50, 8'h00);
        check(ack_err == 1'b0 && rdata == 8'h3C, "T3: write/read 0x3C");

        i2c_xfer(1'b0, 7'h51, 8'h11);
        check(ack_err == 1'b1 && slave.mem == 8'h3C, "T4: NACK on wrong address");

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED: %0d", errors);
        #1000 $finish;
    end

    initial begin #20_000_000; $display("TIMEOUT"); $finish; end   // сторожовий таймер
endmodule
