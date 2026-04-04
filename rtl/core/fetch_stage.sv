`timescale 1ns / 1ps

module fetch_stage (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         en,             // Stall from Hazard Unit
    input  logic         jump_sel,       // High if Branch/Jump taken
    input  logic [31:0] jump_addr,      // Target from MEM stage

    // Memory Interface
    output logic [31:0] icache_addr,    
    input  logic [31:0] icache_instr,   
    input  logic         icache_ready,   

    // Pipeline Outputs
    output logic [31:0] if_pc,          
    output logic [31:0] if_instr,       
    output logic         if_stall        
);

    // --- Internal Signals ---
    logic [31:0] current_fetch_pc;
    logic [31:0] next_pc;
    logic [31:0] pc_plus_4;
    logic [31:0] pc_delayed_q;
    logic        pc_en;

    // 1. Next PC Logic
    assign pc_plus_4 = current_fetch_pc + 32'd4;
    
    // Multiplexer עם עדיפות מפורשת לקפיצה
    always_comb begin
        if (jump_sel === 1'b1) begin
            next_pc = jump_addr;
        end else if (en === 1'b1) begin
            next_pc = pc_plus_4;
        end else begin
            next_pc = current_fetch_pc; // שמירה על הקיים בזמן Stall
        end
    end

    // 2. Control Logic - תיקון קריטי!
    // ה-PC צריך להתעדכן אם הזיכרון מוכן ו-(או שיש אישור מה-Hazard Unit או שיש קפיצה)
    assign pc_en    = icache_ready && (en || jump_sel);
    assign if_stall = !icache_ready;

    // 3. PC Register
    pc_reg pc_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pc_en),
        .next_pc (next_pc),
        .pc_out  (current_fetch_pc)
    );

    // 4. Delay Register: סנכרון ה-PC עם הגעת הפקודה מהזיכרון
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_delayed_q <= 32'b0;
        end else if (pc_en) begin
            // אם אנחנו קופצים, ה-PC שיוצא ל-Decode במחזור הבא חייב להיות יעד הקפיצה
            pc_delayed_q <= next_pc; 
        end
    end

    // --- Output Assignments ---
    assign icache_addr = next_pc;       // שולחים לזיכרון את הכתובת הבאה (יעיל יותר)
    assign if_pc       = pc_delayed_q; 
    assign if_instr    = icache_instr; 

endmodule