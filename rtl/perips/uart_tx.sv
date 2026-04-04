`timescale 1ns / 1ps

/**
 * UART Transmitter (PHY)
 * ----------------------
 * Transmits 8-bit data serially (1 start bit, 8 data bits, 1 stop bit).
 */
module uart_tx #(
    parameter CLK_FREQ = 100_000_000, // Default 100MHz
    parameter BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,  // 8-bit data to send
    input  logic       tx_en,    // Start pulse (from Bus Wrapper)
    output logic       tx_busy,  // High when transmission is in progress
    output logic       uart_txd  // Physical TX serial pin
);

    // Calculate clock cycles per bit
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;
    
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [31:0] clk_count;
    logic [2:0]  bit_index;
    logic [7:0]  data_buffer;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            uart_txd <= 1'b1; // UART Idle state is High
            tx_busy  <= 1'b0;
            clk_count <= 0;
        end else begin
            case (state)
                IDLE: begin
                    uart_txd <= 1'b1;
                    tx_busy  <= 1'b0;
                    if (tx_en) begin
                        data_buffer <= tx_data;
                        tx_busy     <= 1'b1;
                        state       <= START;
                        clk_count   <= 0;
                    end
                end

                START: begin
                    uart_txd <= 1'b0; // Start bit is Low
                    if (clk_count < BIT_PERIOD - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state     <= DATA;
                        bit_index <= 0;
                    end
                end

                DATA: begin
                    uart_txd <= data_buffer[bit_index];
                    if (clk_count < BIT_PERIOD - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= STOP;
                        end
                    end
                end

                STOP: begin
                    uart_txd <= 1'b1; // Stop bit is High
                    if (clk_count < BIT_PERIOD - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule