`timescale 1ns / 1ps

module forwarding_unit (
    input  logic [4:0]  ex_rs1,
    input  logic [4:0]  ex_rs2,
    input  logic [4:0]  mem_rd_addr,
    input  logic [4:0]  wb_rd_addr,
    input  logic        mem_reg_write_en,
    input  logic        wb_reg_write_en,
    
    // אותות חדשים: האם הפקודה ב-EX באמת צריכה את הרגיסטרים האלו?
    input  logic        ex_rs1_used,
    input  logic        ex_rs2_used,
    
    output logic [1:0]  forward_a_sel,
    output logic [1:0]  forward_b_sel
);

    // לוגיקת Forwarding עבור אופרנד A (rs1)
    always_comb begin
        if (ex_rs1_used && mem_reg_write_en && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs1))
            forward_a_sel = 2'b10; // מהזיכרון (הכי מעודכן)
        else if (ex_rs1_used && wb_reg_write_en && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs1))
            forward_a_sel = 2'b01; // מה-Writeback
        else
            forward_a_sel = 2'b00; // מה-Register File
    end

    // לוגיקת Forwarding עבור אופרנד B (rs2)
    always_comb begin
        if (ex_rs2_used && mem_reg_write_en && (mem_rd_addr != 5'b0) && (mem_rd_addr == ex_rs2))
            forward_b_sel = 2'b10;
        else if (ex_rs2_used && wb_reg_write_en && (wb_rd_addr != 5'b0) && (wb_rd_addr == ex_rs2))
            forward_b_sel = 2'b01;
        else
            forward_b_sel = 2'b00;
    end

endmodule