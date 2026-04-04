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
    input logic [1:0]  fwd_a, 
    input logic [1:0]  fwd_b, 
    input logic        uart_busy
);

    initial begin
        // עדכון הכותרת
        $display("\n[TIME]    |  PC  |  INSTR   | ALU_RES | FWD_A | FWD_B");
        $display("------------------------------------------------------");
    end

    always @(negedge clk) begin
        if (rst_n && instr !== 32'h0 && instr !== 32'hxxxxxxxx) begin
            // הדפסה של אותות ה-Forwarding
            $strobe("%7t | %h | %h | %h |   %b   |   %b", $time, pc, instr, alu_res, fwd_a, fwd_b);
        end
    end
endmodule