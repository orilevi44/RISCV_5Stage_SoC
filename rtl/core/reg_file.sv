`timescale 1ns / 1ps

/**
 * Register File
 * -------------
 * 32 general-purpose 32-bit registers.
 * Includes Internal Forwarding (Bypass) to handle Write-then-Read dependencies 
 * within the same clock cycle.
 */
module reg_file (
    input  logic         clk,
    input  logic         we,             // Write Enable (from WB stage)
    input  logic [4:0]   read_reg1,      // Source Register 1 (rs1)
    input  logic [4:0]   read_reg2,      // Source Register 2 (rs2)
    input  logic [4:0]   write_reg,      // Destination Register (rd)
    input  logic [31:0]  write_data,     // Data to be written
    output logic [31:0]  read_data1,
    output logic [31:0]  read_data2
);

    logic [31:0] registers [31:0];

    // Initialize all registers to zero
    initial begin
        for (int i = 0; i < 32; i++) registers[i] = 32'b0;
    end

    /**
     * Internal Forwarding (Bypass Logic):
     * If we read from a register exactly when it is being written (same cycle),
     * we pull the data directly from 'write_data' instead of the stale array value.
     * Note: x0 is hardwired to zero.
     */
    assign read_data1 = (read_reg1 == 5'b0) ? 32'b0 : 
                        ((we && (read_reg1 == write_reg)) ? write_data : registers[read_reg1]);
                        
    assign read_data2 = (read_reg2 == 5'b0) ? 32'b0 : 
                        ((we && (read_reg2 == write_reg)) ? write_data : registers[read_reg2]);

    // Clock-synchronized write logic
    always_ff @(posedge clk) begin
        if (we && (write_reg != 5'b0)) begin
            registers[write_reg] <= write_data;
        end
    end
endmodule