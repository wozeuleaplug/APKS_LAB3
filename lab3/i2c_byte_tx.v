//==============================================================================
// Модуль   : i2c_byte_tx  (ПЕРЕДАВАЧ Tx)
// Призначення: передає один байт (MSB першим) через i2c_bit_ctrl, після чого
//              читає біт ACK від Slave (ack_ok=1, якщо Slave тримав SDA=0).
//==============================================================================
module i2c_byte_tx (
    input  wire       clk, rst,
    input  wire       start,        // імпульс запуску передачі байта
    input  wire [7:0] data,         // байт для передачі
    // інтерфейс до бітового рівня
    output wire       bc_valid,
    output wire [1:0] bc_cmd,
    output wire       bc_din,
    input  wire       bc_done,
    input  wire       bc_dout,
    // статус
    output wire       busy,
    output wire       done,         // імпульс завершення (разом з ack_ok)
    output reg        ack_ok        // 1 - отримано ACK
);
    localparam [2:0] S_IDLE=0, S_BIT=1, S_BIT_W=2, S_ACK=3, S_ACK_W=4, S_DONE=5;
    reg [2:0] state;
    reg [7:0] sh;                   // зсувний регістр
    reg [2:0] cnt;                  // номер біта 0..7

    always @(posedge clk) begin
        if (rst) begin state <= S_IDLE; sh <= 8'd0; cnt <= 3'd0; ack_ok <= 1'b0; end
        else case (state)
            S_IDLE:  if (start) begin sh <= data; cnt <= 3'd0; state <= S_BIT; end
            S_BIT:   state <= S_BIT_W;                      // видано команду WR
            S_BIT_W: if (bc_done) begin
                         sh <= {sh[6:0], 1'b0};
                         if (cnt == 3'd7) state <= S_ACK;
                         else begin cnt <= cnt + 3'd1; state <= S_BIT; end
                     end
            S_ACK:   state <= S_ACK_W;                      // видано команду RD
            S_ACK_W: if (bc_done) begin ack_ok <= ~bc_dout; state <= S_DONE; end
            S_DONE:  state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end

    assign bc_valid = (state == S_BIT) || (state == S_ACK);
    assign bc_cmd   = (state == S_ACK) ? 2'd3 : 2'd2;       // RD для ACK, WR для даних
    assign bc_din   = sh[7];
    assign busy     = (state != S_IDLE);
    assign done     = (state == S_DONE);
endmodule
