`timescale 1ns / 1ps

module riscv_core (
    input  logic        clk,
    input  logic        rst_n,
    
    // Instruction Memory Interface
    output logic [31:0] instr_mem_addr,
    input  logic [31:0] instr_mem_data,
    input  logic        instr_mem_ready,

    // Data Memory Interface
    output logic [31:0] data_mem_addr,
    output logic [31:0] data_mem_wr_data,
    output logic        data_mem_wr_en,
    input  logic [31:0] data_mem_rd_data
);

    // --- 1. Internal Wires ---
    logic [31:0] if_pc, if_inst;
    logic        if_pc_en, if_stall;

    logic [31:0] id_pc, id_inst, id_read_data1, id_read_data2, id_imm;
    logic [4:0]  id_rs1, id_rs2, id_rd_addr;
    logic [2:0]  id_funct3;
    logic        id_reg_write_en, id_mem_read_en, id_mem_write_en, id_mem_to_reg_sel;
    logic [1:0]  id_alu_op_sel;
    logic        id_alu_src_sel, id_branch_en, id_jal_en, id_jalr_en;
    logic        id_reg_en, if_id_flush;
    logic        id_rs1_used, id_rs2_used;

    logic [31:0] ex_pc, ex_read_data1, ex_read_data2, ex_imm, ex_inst, ex_alu_res, ex_branch_target, ex_wr_data_mem;
    logic [4:0]  ex_rs1, ex_rs2, ex_rd_addr;
    logic [2:0]  ex_funct3;
    logic        ex_reg_write_en, ex_mem_read_en, ex_mem_write_en, ex_mem_to_reg_sel;
    logic        ex_alu_src_sel, ex_branch_en, ex_alu_zero, ex_jal_en, ex_jalr_en;
    logic [1:0]  ex_alu_op_sel;
    logic        id_ex_flush;
    logic        ex_rs1_used, ex_rs2_used;

    logic [31:0] mem_alu_res, mem_wr_data, mem_rd_data, mem_branch_target;
    logic [4:0]  mem_rd_addr;
    logic [2:0]  mem_funct3;
    logic        mem_reg_write_en, mem_mem_read_en, mem_mem_write_en, mem_mem_to_reg_sel;
    logic        mem_branch_en, mem_alu_zero, mem_branch_taken, mem_jal_en, mem_jalr_en;

    logic [31:0] wb_alu_res, wb_mem_data, wb_final_data; 
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_write_en, wb_mem_to_reg_sel;

    logic [1:0]  forward_a_sel, forward_b_sel;

    // הגנה על סיגנל הקפיצה מפני ערכי X
    wire actual_jump = (mem_branch_taken === 1'b1) || (mem_jal_en === 1'b1) || (mem_jalr_en === 1'b1);

    // --- 2. Instantiations ---

    fetch_stage u_fetch_unit (
        .clk(clk), .rst_n(rst_n), .en(if_pc_en),
        .jump_sel(actual_jump), .jump_addr(mem_branch_target),
        .icache_addr(instr_mem_addr), .icache_instr(instr_mem_data), .icache_ready(instr_mem_ready),
        .if_pc(if_pc), .if_instr(if_inst), .if_stall(if_stall)
    );

    if_id_reg if_id_reg_inst (
        .clk(clk), .rst_n(rst_n), .flush(if_id_flush), .en(id_reg_en),
        .if_pc(if_pc), .if_inst(if_inst), .id_pc(id_pc), .id_inst(id_inst)
    );

    decode_stage u_decode_stage (
        .clk(clk), .if_id_inst(id_inst), .if_id_pc(id_pc),
        .wb_reg_write_en(wb_reg_write_en), .wb_write_reg_addr(wb_rd_addr), .wb_write_data(wb_final_data),
        .id_read_data1(id_read_data1), .id_read_data2(id_read_data2), .id_imm(id_imm),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .id_rd(id_rd_addr), .id_funct3(id_funct3),
        .id_reg_write_en(id_reg_write_en), .id_mem_read_en(id_mem_read_en),
        .id_mem_write_en(id_mem_write_en), .id_mem_to_reg_sel(id_mem_to_reg_sel),
        .id_alu_op_sel(id_alu_op_sel), .id_alu_src_sel(id_alu_src_sel),
        .id_branch_en(id_branch_en), .id_jal_en(id_jal_en), .id_jalr_en(id_jalr_en),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used)
    );

    id_ex_reg id_ex_reg_inst (
        .clk(clk), .rst_n(rst_n), .flush(id_ex_flush),
        .id_pc(id_pc), .id_read_data1(id_read_data1), .id_read_data2(id_read_data2),
        .id_imm(id_imm), .id_inst(id_inst), .id_rs1(id_rs1), .id_rs2(id_rs2), .id_rd(id_rd_addr),
        .id_alu_op_sel(id_alu_op_sel), .id_alu_src_sel(id_alu_src_sel), .id_reg_write_en(id_reg_write_en),
        .id_mem_read_en(id_mem_read_en), .id_mem_write_en(id_mem_write_en), .id_mem_to_reg_sel(id_mem_to_reg_sel),
        .id_branch_en(id_branch_en), .id_jal_en(id_jal_en), .id_jalr_en(id_jalr_en),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used),
        
        .ex_pc(ex_pc), .ex_read_data1(ex_read_data1), .ex_read_data2(ex_read_data2),
        .ex_imm(ex_imm), .ex_inst(ex_inst), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .ex_rd(ex_rd_addr),
        .ex_alu_op_sel(ex_alu_op_sel), .ex_alu_src_sel(ex_alu_src_sel), .ex_reg_write_en(ex_reg_write_en),
        .ex_mem_read_en(ex_mem_read_en), .ex_mem_write_en(ex_mem_write_en), .ex_mem_to_reg_sel(ex_mem_to_reg_sel),
        .ex_branch_en(ex_branch_en), .ex_jal_en(ex_jal_en), .ex_jalr_en(ex_jalr_en),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used)
    );

    execute_stage u_execute_stage (
        .ex_pc(ex_pc), .ex_read_data1(ex_read_data1), .ex_read_data2(ex_read_data2),
        .ex_imm(ex_imm), .ex_inst(ex_inst), .mem_forward_data(mem_alu_res), .wb_forward_data(wb_final_data),
        .forward_a_sel(forward_a_sel), .forward_b_sel(forward_b_sel),
        .ex_alu_op_sel(ex_alu_op_sel), .ex_alu_src_sel(ex_alu_src_sel),
        .ex_jal_en(ex_jal_en), .ex_jalr_en(ex_jalr_en),
        .ex_branch_target(ex_branch_target), .ex_alu_result(ex_alu_res),
        .ex_write_data_mem(ex_wr_data_mem), .ex_alu_zero(ex_alu_zero)
    );

    ex_mem_reg ex_mem_reg_inst (
        .clk(clk), .rst_n(rst_n),
        .ex_alu_result(ex_alu_res), .ex_write_data(ex_wr_data_mem), .ex_branch_target(ex_branch_target),
        .ex_rd_addr(ex_rd_addr), .ex_funct3(ex_funct3), .ex_alu_zero(ex_alu_zero),
        .ex_reg_write_en(ex_reg_write_en), .ex_mem_to_reg_sel(ex_mem_to_reg_sel),
        .ex_mem_read_en(ex_mem_read_en), .ex_mem_write_en(ex_mem_write_en),
        .ex_branch_en(ex_branch_en), .ex_jal_en(ex_jal_en), .ex_jalr_en(ex_jalr_en),
        
        .mem_alu_result(mem_alu_res), .mem_write_data(mem_wr_data), .mem_branch_target(mem_branch_target),
        .mem_rd_addr(mem_rd_addr), .mem_funct3(mem_funct3), .mem_alu_zero(mem_alu_zero),
        .mem_reg_write_en(mem_reg_write_en), .mem_mem_to_reg_sel(mem_mem_to_reg_sel),
        .mem_mem_read_en(mem_mem_read_en), .mem_mem_write_en(mem_mem_write_en),
        .mem_branch_en(mem_branch_en), .mem_jal_en(mem_jal_en), .mem_jalr_en(mem_jalr_en)
    );

    memory_stage u_memory_stage (
        .mem_alu_result(mem_alu_res), .mem_write_data(mem_wr_data),
        .mem_mem_read_en(mem_mem_read_en), .mem_mem_write_en(mem_mem_write_en),
        .mem_alu_zero(mem_alu_zero), .ram_addr(data_mem_addr), .ram_wr_data(data_mem_wr_data),
        .ram_wr_en(data_mem_wr_en), .ram_rd_data(data_mem_rd_data),
        .mem_read_data(mem_rd_data), .mem_branch_taken(mem_branch_taken)
    );

    mem_wb_reg mem_wb_reg_inst (
        .clk(clk), .rst_n(rst_n),
        .mem_alu_res(mem_alu_res), .mem_mem_data(mem_rd_data), .mem_rd_addr(mem_rd_addr),
        .mem_reg_write_en(mem_reg_write_en), .mem_mem_to_reg_sel(mem_mem_to_reg_sel),
        
        .wb_alu_res(wb_alu_res), .wb_mem_data(wb_mem_data), .wb_rd_addr(wb_rd_addr),
        .wb_reg_write_en(wb_reg_write_en), .wb_mem_to_reg_sel(wb_mem_to_reg_sel)
    );

    writeback_stage u_writeback_stage (
        .wb_alu_res(wb_alu_res), .wb_mem_data(wb_mem_data),
        .wb_mem_to_reg_sel(wb_mem_to_reg_sel), .wb_final_data(wb_final_data)
    );

    forwarding_unit u_forwarding_unit (
        .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .mem_rd_addr(mem_rd_addr), .wb_rd_addr(wb_rd_addr),
        .mem_reg_write_en(mem_reg_write_en), .wb_reg_write_en(wb_reg_write_en),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .forward_a_sel(forward_a_sel), .forward_b_sel(forward_b_sel)
    );

    hazard_detection_unit u_hazard_detection_unit (
        .id_rs1(id_rs1), .id_rs2(id_rs2), .ex_rd_addr(ex_rd_addr),
        .ex_mem_read_en(ex_mem_read_en), .jump_branch_taken(actual_jump),
        .if_pc_en(if_pc_en), .id_reg_en(id_reg_en), .id_ex_flush(id_ex_flush), .if_id_flush(if_id_flush)
    );

endmodule