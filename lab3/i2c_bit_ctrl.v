//==============================================================================
// Модуль   : i2c_bit_ctrl
// Призначення: бітовий рівень I2C Master. Формує елементарні послідовності на
//              лініях SCL/SDA: START, STOP, запис біта, читання біта.
//              Кожна команда триває 4 фази (ph0..ph3), кожна фаза = CLK_DIV тактів,
//              отже період SCL = 4*CLK_DIV тактів clk.
// Лінії open-drain: модуль лише керує сигналами "притиснути до землі" (*_low),
//              лінія відпускається (Z) і підтягується резистором до 1.
//==============================================================================
module i2c_bit_ctrl #(
    parameter CLK_DIV = 125          // 50 МГц / (4*125) = 100 кГц (Standard mode)
)(
    input  wire       clk,           // системний такт
    input  wire       rst,           // синхронне скидання (активний 1)
    input  wire       cmd_valid,     // запит на виконання команди (1 такт)
    input  wire [1:0] cmd,           // 0-START, 1-STOP, 2-WR bit, 3-RD bit
    input  wire       din,           // біт для запису (команда WR)
    output reg        cmd_done,      // імпульс: команду завершено
    output reg        dout,          // прочитаний біт (команда RD)
    output reg        scl_low,       // 1 - притиснути SCL до 0
    output reg        sda_low,       // 1 - притиснути SDA до 0
    input  wire       sda_in         // стан лінії SDA (синхронізований)
);
    localparam [1:0] CMD_START = 2'd0, CMD_STOP = 2'd1,
                     CMD_WR    = 2'd2, CMD_RD   = 2'd3;

    reg        active;               // виконується команда
    reg  [1:0] cmd_r;                // збережена команда
    reg        din_r;                // збережений біт даних
    reg  [1:0] ph;                   // поточна фаза 0..3
    reg [15:0] cnt;                  // лічильник тривалості фази

    // Таблиця станів ліній: {scl_low, sda_low} для команди c у фазі p
    function [1:0] drive;
        input [1:0] c;
        input [1:0] p;
        input       d;
        begin
            case (c)
                CMD_START: case (p)               // SDA 1->0 при SCL=1
                    2'd0:    drive = 2'b00;
                    2'd1:    drive = 2'b01;
                    default: drive = 2'b11;
                endcase
                CMD_STOP: case (p)                // SDA 0->1 при SCL=1
                    2'd0:    drive = 2'b11;
                    2'd1:    drive = 2'b01;
                    default: drive = 2'b00;
                endcase
                CMD_WR: case (p)                  // SDA змінюється при SCL=0
                    2'd0:    drive = {1'b1, ~d};
                    2'd1:    drive = {1'b0, ~d};
                    2'd2:    drive = {1'b0, ~d};
                    default: drive = {1'b1, ~d};
                endcase
                default: case (p)                 // RD: SDA відпущена
                    2'd0:    drive = 2'b10;
                    2'd1:    drive = 2'b00;
                    2'd2:    drive = 2'b00;
                    default: drive = 2'b10;
                endcase
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0; cmd_done <= 1'b0; dout <= 1'b1;
            scl_low <= 1'b0; sda_low <= 1'b0;
            ph <= 2'd0; cnt <= 16'd0; cmd_r <= 2'd0; din_r <= 1'b0;
        end else begin
            cmd_done <= 1'b0;
            if (!active) begin
                cnt <= 16'd0; ph <= 2'd0;
                if (cmd_valid) begin                 // прийом нової команди
                    active <= 1'b1; cmd_r <= cmd; din_r <= din;
                    {scl_low, sda_low} <= drive(cmd, 2'd0, din);
                end
            end else if (cnt == CLK_DIV-1) begin     // кінець фази
                cnt <= 16'd0;
                if (cmd_r == CMD_RD && ph == 2'd2)   // середина високого SCL
                    dout <= sda_in;                  // ... фіксуємо біт
                if (ph == 2'd3) begin
                    active <= 1'b0; cmd_done <= 1'b1;
                end else begin
                    ph <= ph + 2'd1;
                    {scl_low, sda_low} <= drive(cmd_r, ph + 2'd1, din_r);
                end
            end else begin
                cnt <= cnt + 16'd1;
            end
        end
    end
endmodule
