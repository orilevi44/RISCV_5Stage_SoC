`timescale 1ns / 1ps

module pic (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Bus Interface ---
    input  logic        sel,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    
    // --- Interrupt Sources (IRQs) ---
    input  logic        irq_uart_rx,
    input  logic        irq_uart_tx,
    input  logic        irq_timer,    
    
    // --- Output to CPU Core ---
    output logic        ext_intr
);

    logic [31:0] irq_enable;
    wire  [31:0] irq_pending = {29'b0, irq_timer, irq_uart_tx, irq_uart_rx};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_enable <= 32'b0; 
        end else if (sel && we && (addr == 32'h0000_4004)) begin
            irq_enable <= wdata;
        end
    end

    always_comb begin
        if (sel && !we) begin
            if (addr == 32'h0000_4000)
                rdata = irq_pending;
            else if (addr == 32'h0000_4004)
                rdata = irq_enable;
            else
                rdata = 32'b0;
        end else begin
            rdata = 32'b0;
        end
    end

    assign ext_intr = |(irq_pending & irq_enable);

endmodule