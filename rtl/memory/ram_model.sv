/**
 * Simple RAM Model for SoC
 */
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
    assign rd_data = mem[addr[11:2]];

endmodule