`timescale 1ns / 1ps

module uart_wrapper #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 12_500_000
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        sel,       
    input  logic        we,    
    input  logic        re,    // Read Enable מהמעבד
    input  logic [31:0] addr,       
    input  logic [31:0] wdata,     
    output logic [31:0] rdata,     
    output logic        uart_txd,  
    input  logic        uart_rxd   
);

    // רגיסטרים פנימיים
    logic [7:0] tx_data_reg; 
    logic [7:0] rx_data_reg;
    logic       tx_en, tx_busy;
    logic [7:0] rx_phy_data;
    logic       rx_valid_pulse, rx_valid_sticky, rx_clear;
    logic [3:0] addr_offset;
    logic       data_read_done;

    assign addr_offset = addr[3:0];

    // PHY Units
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx_phy (
        .clk(clk), .rst_n(rst_n), .tx_data(tx_data_reg), 
        .tx_en(tx_en), .tx_busy(tx_busy), .uart_txd(uart_txd)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx_phy (
        .clk(clk), .rst_n(rst_n), .uart_rxd(uart_rxd),
        .rx_clear(rx_clear), .rx_data(rx_phy_data), .rx_valid(rx_valid_pulse)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid_sticky <= 1'b0;
            rx_data_reg     <= 8'b0;
            tx_data_reg     <= 8'b0;
            tx_en           <= 1'b0;
            rx_clear        <= 1'b0;
            data_read_done  <= 1'b0;
        end else begin
            // Default values
            tx_en    <= 1'b0;
            rx_clear <= 1'b0;
            data_read_done <= 1'b0;

            /**
             * לוגיקת נעילת נתונים (RX Latch Logic)
             * תיקון: מתן עדיפות לפולס מהחומרה. 
             * גם אם יש בקשת CLEAR מהמעבד, אם הגיע תו חדש - הוא ננעל.
             */
            if (rx_valid_pulse) begin
                rx_valid_sticky <= 1'b1;
                rx_data_reg     <= rx_phy_data;
            end 
            else if (data_read_done) begin
                // מנקים רק אם לא הגיע תו חדש באותו מחזור שעון
                rx_valid_sticky <= 1'b0;
                rx_clear        <= 1'b1;
            end

            // פעולות מול ה-Bus
            if (sel) begin
                if (addr_offset == 4'h0) begin
                    if (we && !tx_busy) begin
                        tx_en       <= 1'b1;
                        tx_data_reg <= wdata[7:0]; 
                    end 
                    // בדיקת re מבטיחה שרק קריאה אמיתית תפעיל את הניקוי
                    else if (!we && re) begin 
                        data_read_done <= 1'b1;
                    end
                end
            end
        end
    end

    // Mux הקריאה - ביט 0 הוא RX Ready
    always_comb begin
        rdata = 32'b0;
        if (sel && !we) begin
            case (addr_offset)
                4'h0: rdata = {24'b0, rx_data_reg};
                4'h4: rdata = {30'b0, tx_busy, rx_valid_sticky}; 
                default: rdata = 32'b0;
            endcase
        end
    end
endmodule