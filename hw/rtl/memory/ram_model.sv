`timescale 1ns / 1ps

// RAM Model — 4 KB (1024 × 32-bit words), base address 0x2000
// Writes are synchronous (clocked). Reads are asynchronous (combinational).
// Word index = addr[11:2], so bytes within a word are ignored.
module ram_model (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        wr_en,
    input  logic [31:0] wr_data,
    output logic [31:0] rd_data
);

    logic [31:0] mem [0:1023]; // 4KB RAM

    // Synchronous Write
    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[addr[11:2]] <= wr_data;
        end
    end

    // Asynchronous Read
    //assign rd_data = mem[addr[11:2]];
    assign rd_data = (addr[11:2] < 1024) ? mem[addr[11:2]] : 32'h0;

endmodule