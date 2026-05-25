`timescale 1ns / 1ps

/**
 * Register File
 * -------------------------------------------------------------------------
 * Contains the 32 general-purpose 32-bit registers (x0 - x31) for RISC-V.
 * * Key Features:
 * - Register x0 is hardwired to 0 (reads always return 0, writes are ignored).
 * - Internal Bypass (Forwarding): Solves the Write-then-Read hazard in the 
 * same clock cycle by routing the incoming write_data directly to the read ports.
 */
module reg_file (
    input  logic        clk,
    input  logic        we,             // Write Enable (driven by WB stage)
    input  logic [4:0]  read_reg1,      // Address of rs1
    input  logic [4:0]  read_reg2,      // Address of rs2
    input  logic [4:0]  write_reg,      // Address of destination rd
    input  logic [31:0] write_data,     // Payload to be stored
    output logic [31:0] read_data1,     // Output data for rs1
    output logic [31:0] read_data2      // Output data for rs2
);

    // The actual memory array: 32 registers of 32 bits
    logic [31:0] registers [31:0];

    // Initialization for simulation cleanlyness
    initial begin
        for (int i = 0; i < 32; i++) registers[i] = 32'b0;
    end

    // ==============================================================================
    // Read Logic (Asynchronous with Internal Bypass)
    // ==============================================================================
    // Port 1 Read
    assign read_data1 = (read_reg1 == 5'b0) ? 32'b0 : 
                        ((we && (read_reg1 == write_reg)) ? write_data : registers[read_reg1]);
                        
    // Port 2 Read
    assign read_data2 = (read_reg2 == 5'b0) ? 32'b0 : 
                        ((we && (read_reg2 == write_reg)) ? write_data : registers[read_reg2]);

    // ==============================================================================
    // Write Logic (Synchronous)
    // ==============================================================================
    always_ff @(posedge clk) begin
        // Only write if enabled AND we are not trying to overwrite the zero register
        if (we && (write_reg != 5'b0)) begin
            registers[write_reg] <= write_data;
        end
    end
endmodule