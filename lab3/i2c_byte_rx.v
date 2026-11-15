//==============================================================================
// Модуль   : i2c_byte_rx  (ПРИЙМАЧ Rx)
// Призначення: приймає один байт від Slave (MSB першим), після чого формує
//              ACK (nack=0) або NACK (nack=1) для Slave.
//==============================================================================
module i2c_byte_rx (
    input  wire       clk, rst,
    input  wire       start,        // імпульс запуску прийому
    input  wire       nack,         // 1 - відповісти NACK (останній байт)
    output wire       bc_valid,
    output wire [1:0] bc_cmd,
    output wire       bc_din,
    input  wire       bc_done,
    input  wire       bc_dout,
    output wire [7:0] data,         // прийнятий байт (дійсний при done=1)
    output wire       busy,
    output wire       done
);
    localparam [2:0] S_IDLE=0, S_BIT=1, S_BIT_W=2, S_ACK=3, S_ACK_W=4, S_DONE=5;
    reg [2:0] state;
    reg [7:0] sh;
    reg [2:0] cnt;
    reg       nack_r;

    always @(posedge clk) begin
        if (rst) begin state <= S_IDLE; sh <= 8'd0; cnt <= 3'd0; nack_r <= 1'b0; end
        else case (state)
            S_IDLE:  if (start) begin cnt <= 3'd0; nack_r <= nack; state <= S_BIT; end
            S_BIT:   state <= S_BIT_W;                      // команда RD
            S_BIT_W: if (bc_done) begin
                         sh <= {sh[6:0], bc_dout};          // зсув у регістр
                         if (cnt == 3'd7) state <= S_ACK;
                         else begin cnt <= cnt + 3'd1; state <= S_BIT; end
                     end
            S_ACK:   state <= S_ACK_W;                      // команда WR (ACK/NACK)
            S_ACK_W: if (bc_done) state <= S_DONE;
            S_DONE:  state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end

    assign bc_valid = (state == S_BIT) || (state == S_ACK);
    assign bc_cmd   = (state == S_ACK) ? 2'd2 : 2'd3;
    assign bc_din   = nack_r;                               // ACK=0, NACK=1
    assign data     = sh;
    assign busy     = (state != S_IDLE);
    assign done     = (state == S_DONE);
endmodule
