`timescale 1ns / 1ps

/**
 * Branch Monitor (Final Production Version)
 * מזהה סיום תוכנית תקין ומבדיל בינו לבין לופ אינסופי של באג.
 */
module branch_monitor (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] ex_pc,
    input  logic [31:0] jump_addr,
    input  logic        actual_jump,
    input  logic [31:0] next_if_pc
);

    logic        actual_jump_q;
    logic [31:0] jump_addr_q;
    logic [31:0] ex_pc_q; 
    integer      jump_count = 0; 
    logic        is_end_of_program = 0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actual_jump_q <= 1'b0;
            jump_addr_q   <= 32'h0;
            ex_pc_q       <= 32'h0;
        end else begin
            actual_jump_q <= actual_jump;
            jump_addr_q   <= jump_addr;
            ex_pc_q       <= ex_pc;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (actual_jump) begin
                // בדיקה: האם זו קפיצת חניה (Target == Current PC)
                // במעבד שלך ex_pc הוא תמיד הכתובת של הפקודה + 4
                if (jump_addr != (ex_pc - 4)) begin 
                    jump_count = jump_count + 1;
                    $display("\n[BRANCH_WATCHER] @%t | Jump #%0d Detected", $time, jump_count);
                end else if (!is_end_of_program) begin
                    $display("\n[MONITOR] SUCCESS: CPU reached the end of the program and is now parking.");
                    $display("[MONITOR] Check UART Monitor above for the final '!' character.");
                    is_end_of_program = 1;
                end
                
                // הגנה רק מפני לופים לא מכוונים
                if (jump_count > 25) begin
                    $display("\n>>> [FAIL] REAL Infinite Loop detected! Check logic.");
                    $finish; 
                end
            end
            
            // אימות הגעה ליעד
            if (actual_jump_q && !is_end_of_program) begin
                if (next_if_pc == jump_addr_q) begin
                    $display("    >>> STATUS: Jump Successful! (PC moved to %h)", next_if_pc);
                end else begin
                    $display("\n    >>> STATUS: Jump FAILED! Target was %h, PC is %h", jump_addr_q, next_if_pc);
                end
            end
        end
    end
endmodule