`timescale 1ns / 1ps
/**
 * GPIO Module
 * Memory-mapped I/O for controlling external SoC pins.
 */

module gpio (
    input  logic        clk,
    input  logic        rst_n,
    
    // Bus Interface
    input  logic        sel,    // Chip Select from Bus
    input  logic        we,     // Write Enable
    input  logic [31:0] wdata,  // Data from CPU
    output logic [31:0] rdata,  // Data to CPU

    // External SoC Interface
    output logic [31:0] gpio_pins
);

    logic [31:0] gpio_reg;

    // Sequential Write Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_reg <= 32'b0;
        end else if (sel && we) begin
            gpio_reg <= wdata;
        end
    end

    // Combinational Read Logic
    assign rdata      = gpio_reg;
    assign gpio_pins  = gpio_reg;

endmodule