`timescale 1ns / 1ps

/**
 * Execute Stage
 * Performs arithmetic operations, branch target calculations, and link address logic.
 * Note: PC offsets (+4, +8) are adjusted for PC-Instruction misalignment.
 */
module execute_stage (
    input  logic [31:0] ex_pc,
    input  logic [31:0] ex_read_data1,
    input  logic [31:0] ex_read_data2,
    input  logic [31:0] ex_imm,
    input  logic [31:0] ex_inst,
    
    // Forwarding
    input  logic [31:0] mem_forward_data, 
    input  logic [31:0] wb_forward_data,  
    input  logic [1:0]  forward_a_sel,
    input  logic [1:0]  forward_b_sel,
    
    // Control
    input  logic [2:0]  ex_alu_op_sel,
    input  logic        ex_alu_src_sel,   // 0=Reg, 1=Imm
    input  logic        ex_jal_en,   
    input  logic        ex_jalr_en,   

    output logic [31:0] ex_branch_target,
    output logic [31:0] ex_alu_result,
    output logic [31:0] ex_write_data_mem,
    output logic        ex_alu_zero
);

    logic [31:0] alu_in1;
    logic [31:0] alu_rs2_fwd;
    logic [31:0] alu_in2;
    logic [3:0]  alu_ctrl_wire; 
    logic [31:0] alu_raw_out;   

    // 1. בחירת אופרנד A (rs1) עם Forwarding
    always_comb begin
        case (forward_a_sel)
            2'b00:   alu_in1 = ex_read_data1;
            2'b01:   alu_in1 = wb_forward_data;
            2'b10:   alu_in1 = mem_forward_data;
            default: alu_in1 = ex_read_data1;
        endcase
    end

    // 2. בחירת ערך RS2 המקורי (למקרה של Store או השוואה)
    always_comb begin
        case (forward_b_sel)
            2'b00:   alu_rs2_fwd = ex_read_data2;
            2'b01:   alu_rs2_fwd = wb_forward_data;
            2'b10:   alu_rs2_fwd = mem_forward_data;
            default: alu_rs2_fwd = ex_read_data2;
        endcase
    end
    
    // 3. בחירת אופרנד B הסופי ל-ALU (Reg vs Imm)
    assign alu_in2 = (ex_alu_src_sel) ? ex_imm : alu_rs2_fwd;

    // 4. חישוב כתובת הקפיצה (Target)
    // JALR: rs1 + imm | Branch/JAL: (Current PC) + imm
    // מכיוון ש-ex_pc מפגר ב-4, הכתובת האמיתית של הפקודה היא ex_pc + 4
    assign ex_branch_target = (ex_jalr_en) ? (alu_in1 + ex_imm) : (ex_pc + ex_imm);

    // 5. מידע לכתיבה לזיכרון
    assign ex_write_data_mem = alu_rs2_fwd;

    // 6. בחירת התוצאה הסופית של השלב (ALU Result or Link Address)
    // עבור JAL/JALR, התוצאה שנכתבת ל-rd היא הכתובת של הפקודה הבאה.
    // אם הפקודה הנוכחית היא ב-PC+4, הבאה אחריה היא ב-PC+8.
    assign ex_alu_result = (ex_jal_en || ex_jalr_en) ? (ex_pc + 32'd4) : alu_raw_out;

    // --- קריאה ליחידות המשנה ---
    alu_control alu_control_unit (
        .alu_op     (ex_alu_op_sel),
        .funct3     (ex_inst[14:12]),
        .funct7_bit (ex_inst[30]),
        .alu_ctrl   (alu_ctrl_wire)
    );

    alu alu_unit (
        .a        (alu_in1),
        .b        (alu_in2),
        .alu_ctrl (alu_ctrl_wire),
        .result   (alu_raw_out),
        .zero     (ex_alu_zero)
    );

endmodule