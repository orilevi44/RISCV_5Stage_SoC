/**
 * CPU Pipeline Monitor
 * Tracks PC, Instructions, and ALU results for debugging.
 */
module cpu_monitor (
    input logic clk,
    input logic rst_n,
    input logic [31:0] pc,
    input logic [31:0] instr,
    input logic [31:0] alu_res,
    input logic        uart_busy
);

    initial begin
        $display("\n[TIME]    |  PC  |  INSTR   | ALU_RES | UART_ST");
        $display("-----------------------------------------------");
    end

    // Monitor logic on every clock cycle
    always @(negedge clk) begin
        if (rst_n && instr !== 32'h0 && instr !== 32'hxxxxxxxx) begin
            // $strobe("%7t | %h | %h | %h | %b", 
            //     $time, pc, instr, alu_res, uart_busy
            // );
        end
    end
endmodule