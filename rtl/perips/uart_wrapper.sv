`timescale 1ns / 1ps

// UART Wrapper — Memory-mapped register interface around the TX and RX PHY units.
// Register map (relative to base address):
//   offset 0x0  write → send byte (ignored if tx_busy)
//   offset 0x0  read  → received byte (clears rx_valid on read)
//   offset 0x4  read  → status: bit[0]=rx_valid, bit[1]=tx_busy
module uart_wrapper #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 12_500_000
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         sel,       
    input  logic         we,    
    input  logic         re,    
    input  logic [31:0]  addr,      
    input  logic [31:0]  wdata,     
    output logic [31:0]  rdata,     
    output logic         uart_txd,  
    input  logic         uart_rxd   
);

    // --- Internal Registers & Signals ---
    logic [7:0] tx_data_reg; 
    logic [7:0] rx_data_reg;
    logic       tx_en, tx_busy;
    logic [7:0] rx_phy_data;
    logic       rx_valid_pulse, rx_valid_sticky, rx_clear;
    logic [3:0] addr_offset;
    
    logic       reading_rx_data;

    assign addr_offset = addr[3:0];
    assign reading_rx_data = sel && re && !we && (addr_offset == 4'h0);

    // --- PHY Units Instantiation ---
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx_phy (
        .clk(clk), .rst_n(rst_n), .tx_data(tx_data_reg), 
        .tx_en(tx_en), .tx_busy(tx_busy), .uart_txd(uart_txd)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx_phy (
        .clk(clk), .rst_n(rst_n), .uart_rxd(uart_rxd),
        .rx_clear(rx_clear), .rx_data(rx_phy_data), .rx_valid(rx_valid_pulse)
    );

    // --- Control Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid_sticky <= 1'b0;
            rx_data_reg     <= 8'b0;
            tx_data_reg     <= 8'b0;
            tx_en           <= 1'b0;
            rx_clear        <= 1'b0;
        end else begin
            tx_en    <= 1'b0;
            rx_clear <= 1'b0;

            // Bus Transactions (Write to TX)
            if (sel && we && (addr_offset == 4'h0) && !tx_busy) begin
                tx_en       <= 1'b1;
                tx_data_reg <= wdata[7:0];
            end

            // RX Sticky Bit Logic
            if (rx_valid_pulse) begin
                rx_valid_sticky <= 1'b1;
                rx_data_reg     <= rx_phy_data;
            end 
            else if (reading_rx_data) begin
                rx_valid_sticky <= 1'b0;
                rx_clear        <= 1'b1; 
            end
        end
    end

    // --- Bus Read Multiplexer ---
    // Drives rdata only on a genuine read cycle (sel && re && !we).
    always_comb begin
        rdata = 32'b0;
        if (sel && re && !we) begin
            case (addr_offset)
                4'h0: rdata = {24'b0, rx_data_reg};                // RX data register
                4'h4: rdata = {30'b0, tx_busy, rx_valid_sticky};   // Status: [1]=tx_busy, [0]=rx_valid
                default: rdata = 32'b0;
            endcase
        end
    end

endmodule