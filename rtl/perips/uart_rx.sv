`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ = 100_000_000, 
    parameter BAUD_RATE = 12_500_000
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       uart_rxd,   // Physical RX serial pin (Asynchronous)
    input  logic       rx_clear,   // Pulse from Bus Wrapper
    output logic [7:0] rx_data,    // The received 8-bit byte
    output logic       rx_valid    // High when new data is ready
);

    localparam BIT_PERIOD  = CLK_FREQ / BAUD_RATE;
    localparam HALF_PERIOD = BIT_PERIOD / 2;
    
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;

    logic [31:0] clk_count;
    logic [2:0]  bit_index;
    logic [7:0]  shift_reg;

    // --- SECURE: 2-Flip-Flop Synchronizer for Metastability ---
    logic rxd_sync1, rxd_sync2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_sync1 <= 1'b1; // UART Idle is High
            rxd_sync2 <= 1'b1;
        end else begin
            rxd_sync1 <= uart_rxd;
            rxd_sync2 <= rxd_sync1; // Safe to use in FSM
        end
    end

    // --- RX FSM ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            rx_data   <= 8'b0;
            rx_valid  <= 1'b0;
            shift_reg <= 8'b0;
        end else begin
            //if (rx_clear) rx_valid <= 1'b0;
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    // SECURE: Explicit clock count reset
                    clk_count <= 0; 
                    if (rxd_sync2 == 1'b0) begin 
                        state <= START;
                    end
                end

                START: begin
                    if (clk_count == HALF_PERIOD) begin
                        if (rxd_sync2 == 1'b0) begin 
                            clk_count <= 0;
                            state     <= DATA;
                            bit_index <= 0;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA: begin
                    if (clk_count == BIT_PERIOD - 1) begin
                        clk_count <= 0;
                        shift_reg <= {rxd_sync2, shift_reg[7:1]}; 
                        
                        if (bit_index == 7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP: begin
                    if (clk_count == BIT_PERIOD - 1) begin
                        state <= IDLE;
                        // SECURE: Verify STOP bit framing (Optional but recommended)
                        if (rxd_sync2 == 1'b1) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;  
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
            endcase
        end
    end
endmodule