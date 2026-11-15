//==============================================================================
// Поведінкова модель Slave (тільки для симуляції, не синтезується).
// Має один 8-бітний регістр mem: запис зберігає байт, читання повертає його.
//==============================================================================
module i2c_slave_model #(parameter ADDR = 7'h50)(inout scl, inout sda);
    reg       sda_low = 1'b0;
    reg [7:0] mem     = 8'h00;
    reg [7:0] sh, sh2;
    integer   i;
    assign sda = sda_low ? 1'b0 : 1'bz;

    task recv_byte(output [7:0] b);
        integer k;
        reg [7:0] t;
        begin
            t = 8'd0;
            for (k = 0; k < 8; k = k + 1) begin
                @(posedge scl); t = {t[6:0], sda};
            end
            b = t;
        end
    endtask

    initial forever begin
        @(negedge sda);
        if (scl === 1'b1) begin                    // умова START
            recv_byte(sh);
            if (sh[7:1] == ADDR) begin
                @(negedge scl); sda_low = 1'b1;    // ACK адреси
                @(negedge scl);
                if (sh[0] == 1'b0) begin           // запис
                    sda_low = 1'b0;
                    recv_byte(sh2);
                    @(negedge scl); sda_low = 1'b1; mem = sh2;   // ACK даних
                    @(negedge scl); sda_low = 1'b0;
                end else begin                     // читання
                    for (i = 7; i >= 0; i = i - 1) begin
                        sda_low = ~mem[i]; @(negedge scl);
                    end
                    sda_low = 1'b0;
                    @(posedge scl); @(negedge scl);// (N)ACK від Master
                end
            end
        end
    end
endmodule
