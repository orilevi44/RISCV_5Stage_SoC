`timescale 1ns / 1ps

// Memory Stage
// Evaluates branch conditions and formats the data returned by a load instruction.
// Does not directly access memory — the bus is driven by riscv_core connections.
module memory_stage (
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_write_data,
    input  logic [31:0] mem_branch_target_in,
    input  logic        mem_mem_read_en,     
    input  logic        mem_mem_write_en,    
    input  logic        mem_branch_en,       
    input  logic        mem_alu_zero,        
    input  logic [2:0]  mem_funct3,          
    
    input  logic [31:0] ram_rd_data, // Data coming from System Bus.

    output logic [3:0] byte_en, // <-- NEW: Byte Enable Output to System Bus
    output logic [31:0] mem_formatted_write_data, // <-- Data ready for the bus (replicated)
    
    output logic [31:0] mem_read_data,        
    output logic [31:0] mem_branch_target_out, 
    output logic        mem_branch_taken   
);
    logic        sign_data_byte, sign_data_half;
    logic [7:0]  byte_data;
    logic [15:0] half_data;

    
    

    // Read Alignment Logic: Extract the correct byte/halfword based on the address
    always_comb begin
        // Byte extraction (depends on bits [1:0])
        case (mem_alu_result[1:0])
            2'b00: byte_data = ram_rd_data[7:0];
            2'b01: byte_data = ram_rd_data[15:8];
            2'b10: byte_data = ram_rd_data[23:16];
            2'b11: byte_data = ram_rd_data[31:24];
        endcase

        // Halfword extraction (depends on bit [1])
        if (mem_alu_result[1] == 1'b0) begin
            half_data = ram_rd_data[15:0];
        end else begin
            half_data = ram_rd_data[31:16];
        end
    end


    assign sign_data_byte = byte_data[7];
    assign sign_data_half = half_data[15];

    // Branch Evaluation — check whether funct3 condition matches the ALU output
    always_comb begin
        mem_branch_taken = 1'b0;
        if (mem_branch_en) begin
            case (mem_funct3)
                3'b000:  mem_branch_taken = mem_alu_zero;  // BEQ  (ALU does SUB, zero if a==b)
                3'b001:  mem_branch_taken = !mem_alu_zero; // BNE  (ALU does SUB, not zero if a!=b)
                3'b100:  mem_branch_taken = !mem_alu_zero; // BLT  (ALU does SLT, result 1 if a<b)
                3'b101:  mem_branch_taken = mem_alu_zero;  // BGE  (ALU does SLT, result 0 if a>=b)
                3'b110:  mem_branch_taken = !mem_alu_zero; // BLTU (ALU does SLTU, result 1 if a<b)
                3'b111:  mem_branch_taken = mem_alu_zero;  // BGEU (ALU does SLTU, result 0 if a>=b)
                default: mem_branch_taken = 1'b0;
            endcase
        end
    end

    assign mem_branch_target_out = mem_branch_target_in;

    // Load Formatting — zero-extend the raw bus data to the right width
    always_comb begin
        if (mem_mem_read_en) begin
            case (mem_funct3)
                3'b000:  mem_read_data = {{24{sign_data_byte}}, byte_data};       // LB
                3'b001:  mem_read_data = {{16{sign_data_half}}, half_data};       // LH          
                3'b010:  mem_read_data = ram_rd_data;              // LW
                3'b100:  mem_read_data = {24'b0, byte_data};       // LBU
                3'b101:  mem_read_data = {16'b0, half_data};       // LHU
                
                default: mem_read_data = ram_rd_data;
            endcase
        end else begin
            mem_read_data = 32'b0;
        end
    end

    //deciding for store half and store byte
    always_comb begin
        if (mem_mem_write_en) begin
            case (mem_funct3)
                3'b000: // sb = store byte
                    case(mem_alu_result[1:0]) 
                    2'h00:byte_en = 4'b0001;   
                    2'h01:byte_en = 4'b0010;
                    2'h02:byte_en = 4'b0100;    
                    2'h03:byte_en = 4'b1000;
                    default: byte_en = 4'b0000; 
                    endcase
                
                3'b001: // sh = store half byte
                    if (mem_alu_result[1] == 1'b0) begin
                        byte_en = 4'b0011; // lower half
                    end else begin
                        byte_en = 4'b1100; // upper half
                    end
                3'b010: // sw = store word  
                    byte_en = 4'b1111;
                default: byte_en = 4'b0000;
            endcase
        end
        else begin
            byte_en = 4'b0000;
        end
    end

    
    // Write Data Alignment (Byte/Halfword Replication)
    // This replicates the data across all bytes/halfwords to align with the active byte_en.
    always_comb begin
        case (mem_funct3)
            3'b000: mem_formatted_write_data = {4{mem_write_data[7:0]}};  // SB: Replicate byte 4 times
            3'b001: mem_formatted_write_data = {2{mem_write_data[15:0]}}; // SH: Replicate halfword 2 times
            default: mem_formatted_write_data = mem_write_data;           // SW/Others: Pass through as is
        endcase
    end
endmodule