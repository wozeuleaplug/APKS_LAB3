//==============================================================================
// Модуль   : i2c_master  (верхній рівень, варіант 20: I2C, Verilog)
// Призначення: однобайтні транзакції:
//   rw=0:  START | ADDR+W | ACK | DATA | ACK | STOP
//   rw=1:  START | ADDR+R | ACK | DATA(від Slave) | NACK | STOP
//==============================================================================
module i2c_master #(
    parameter CLK_DIV = 125
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,        // імпульс запуску транзакції
    input  wire       rw,           // 0 - запис, 1 - читання
    input  wire [6:0] addr,         // 7-бітна адреса Slave
    input  wire [7:0] wdata,        // дані для запису
    output wire       busy,
    output reg        done,         // імпульс завершення транзакції
    output reg        ack_err,      // 1 - Slave не підтвердив (NACK)
    output reg  [7:0] rdata,        // прочитані дані
    output reg        rdata_valid,  // імпульс: rdata оновлено
    inout  wire       scl,          // open-drain
    inout  wire       sda           // open-drain
);
    // ---- open-drain вихід та синхронізація входу SDA ----
    wire scl_low, sda_low;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    reg [1:0] sda_sync;
    always @(posedge clk) sda_sync <= {sda_sync[0], sda};
    wire sda_in = sda_sync[1];

    // ---- бітовий рівень ----
    wire       bc_valid, bc_done, bc_dout, bc_din;
    wire [1:0] bc_cmd;
    i2c_bit_ctrl #(.CLK_DIV(CLK_DIV)) u_bit (
        .clk(clk), .rst(rst), .cmd_valid(bc_valid), .cmd(bc_cmd), .din(bc_din),
        .cmd_done(bc_done), .dout(bc_dout), .scl_low(scl_low), .sda_low(sda_low),
        .sda_in(sda_in));

    // ---- FSM верхнього рівня ----
    localparam [3:0] S_IDLE=0, S_START=1, S_START_W=2, S_ADDR_GO=3, S_ADDR_W=4,
                     S_WR_GO=5, S_WR_W=6, S_RD_GO=7, S_RD_W=8, S_STOP=9, S_STOP_W=10;
    reg [3:0] state;
    reg       rw_r;
    reg [6:0] addr_r;
    reg [7:0] wdata_r;

    wire tx_start = (state == S_ADDR_GO) || (state == S_WR_GO);
    wire [7:0] tx_data = (state == S_ADDR_GO) ? {addr_r, rw_r} : wdata_r;
    wire rx_start = (state == S_RD_GO);
    wire tx_valid, rx_valid, tx_busy, tx_done, rx_busy, rx_done, tx_ack_ok;
    wire [1:0] tx_cmd, rx_cmd;
    wire tx_din, rx_din;
    wire [7:0] rx_data;

    i2c_byte_tx u_tx (.clk(clk), .rst(rst), .start(tx_start), .data(tx_data),
        .bc_valid(tx_valid), .bc_cmd(tx_cmd), .bc_din(tx_din),
        .bc_done(bc_done), .bc_dout(bc_dout),
        .busy(tx_busy), .done(tx_done), .ack_ok(tx_ack_ok));
    i2c_byte_rx u_rx (.clk(clk), .rst(rst), .start(rx_start), .nack(1'b1),
        .bc_valid(rx_valid), .bc_cmd(rx_cmd), .bc_din(rx_din),
        .bc_done(bc_done), .bc_dout(bc_dout),
        .data(rx_data), .busy(rx_busy), .done(rx_done));

    // мультиплексор команд до бітового рівня
    wire sel_tx = (state == S_ADDR_W) || (state == S_WR_W);
    wire sel_rx = (state == S_RD_W);
    wire top_valid = (state == S_START) || (state == S_STOP);
    wire [1:0] top_cmd = (state == S_START) ? 2'd0 : 2'd1;
    assign bc_valid = sel_tx ? tx_valid : sel_rx ? rx_valid : top_valid;
    assign bc_cmd   = sel_tx ? tx_cmd   : sel_rx ? rx_cmd   : top_cmd;
    assign bc_din   = sel_tx ? tx_din   : sel_rx ? rx_din   : 1'b0;
    assign busy     = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 1'b0; ack_err <= 1'b0; rdata <= 8'd0;
            rdata_valid <= 1'b0; rw_r <= 1'b0; addr_r <= 7'd0; wdata_r <= 8'd0;
        end else begin
            done <= 1'b0; rdata_valid <= 1'b0;
            case (state)
                S_IDLE:    if (start) begin
                               rw_r <= rw; addr_r <= addr; wdata_r <= wdata;
                               ack_err <= 1'b0; state <= S_START;
                           end
                S_START:   state <= S_START_W;
                S_START_W: if (bc_done) state <= S_ADDR_GO;
                S_ADDR_GO: state <= S_ADDR_W;
                S_ADDR_W:  if (tx_done) begin
                               if (!tx_ack_ok) begin ack_err <= 1'b1; state <= S_STOP; end
                               else state <= rw_r ? S_RD_GO : S_WR_GO;
                           end
                S_WR_GO:   state <= S_WR_W;
                S_WR_W:    if (tx_done) begin
                               if (!tx_ack_ok) ack_err <= 1'b1;
                               state <= S_STOP;
                           end
                S_RD_GO:   state <= S_RD_W;
                S_RD_W:    if (rx_done) begin
                               rdata <= rx_data; rdata_valid <= 1'b1; state <= S_STOP;
                           end
                S_STOP:    state <= S_STOP_W;
                S_STOP_W:  if (bc_done) begin done <= 1'b1; state <= S_IDLE; end
                default:   state <= S_IDLE;
            endcase
        end
    end
endmodule
