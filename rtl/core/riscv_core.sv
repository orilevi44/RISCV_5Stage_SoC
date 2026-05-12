`timescale 1ns / 1ps

// RISC-V Core — 5-Stage Pipeline (IF → ID → EX → MEM → WB)
// Instantiates every pipeline stage, register, and control unit.
// Exposes a simple instruction-memory port and a data-memory port to soc_top.
module riscv_core (
    input  logic         clk,
    input  logic         rst_n,
    
    // Instruction Memory Interface
    output logic [31:0]  instr_mem_addr,
    input  logic [31:0]  instr_mem_data,
    input  logic         instr_mem_ready,

    // Data Memory Interface
    output logic [31:0]  data_mem_addr,
    output logic [31:0]  data_mem_wr_data,
    output logic         data_mem_wr_en,
    output logic         data_mem_rd_en, 
    input  logic [31:0]  data_mem_rd_data
);

    // --- 1. Internal Pipeline Wires ---
    logic [31:0] if_pc, if_inst;
    logic        if_pc_en, if_stall;

    logic [31:0] id_pc, id_inst, id_read_data1, id_read_data2, id_imm;
    logic [4:0]  id_rs1, id_rs2, id_rd_addr;
    logic        id_reg_write_en, id_mem_read_en, id_mem_write_en, id_mem_to_reg_sel;
    logic [2:0]  id_alu_op_sel;
    logic        id_alu_src_sel, id_branch_en, id_jal_en, id_jalr_en;
    logic        id_reg_en, if_id_flush, id_rs1_used, id_rs2_used;
    logic [2:0]  id_funct3;
    logic        id_auipc_en, id_csr_en, id_valid_inst;

    logic [31:0] ex_pc, ex_read_data1, ex_read_data2, ex_imm, ex_inst, ex_alu_res, ex_branch_target, ex_wr_data_mem;
    logic [4:0]  ex_rs1, ex_rs2, ex_rd_addr;
    logic        ex_reg_write_en, ex_mem_read_en, ex_mem_write_en, ex_mem_to_reg_sel;
    logic        ex_alu_src_sel, ex_branch_en, ex_alu_zero, ex_jal_en, ex_jalr_en;
    logic [2:0]  ex_alu_op_sel;
    logic        id_ex_flush, ex_rs1_used, ex_rs2_used;
    logic        ex_auipc_en, ex_csr_en, ex_valid_inst;
    logic [31:0] ex_csr_rdata;

    logic [31:0] mem_alu_res, mem_wr_data, mem_rd_data, mem_branch_target;
    logic [4:0]  mem_rd_addr;
    logic [2:0]  mem_funct3;
    logic        mem_reg_write_en, mem_mem_read_en, mem_mem_write_en, mem_mem_to_reg_sel;
    logic        mem_branch_en, mem_alu_zero, mem_branch_taken, ex_mem_flush;
    logic        mem_jal_en, mem_jalr_en;
    logic        mem_valid_inst;

    logic [31:0] wb_alu_res, wb_mem_data, wb_final_data; 
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_write_en, wb_mem_to_reg_sel, wb_valid_inst;

    logic [1:0]  forward_a_sel, forward_b_sel;
    logic [31:0] final_branch_addr;
    logic        actual_jump;

    // Logic for Jump Detection
    assign actual_jump = (mem_branch_taken || mem_jal_en || mem_jalr_en);

    // Bus Interface
    assign data_mem_addr     = mem_alu_res;
    assign data_mem_wr_data  = mem_wr_data;
    assign data_mem_rd_en    = mem_mem_read_en;
    assign data_mem_wr_en    = mem_mem_write_en;

    // [FETCH]
    fetch_stage u_fetch_unit (
        .clk(clk), .rst_n(rst_n), .en(if_pc_en && !global_stall),
        .jump_sel(actual_jump), .jump_addr(final_branch_addr),
        .icache_addr(instr_mem_addr), .icache_instr(instr_mem_data), .icache_ready(instr_mem_ready),
        .if_pc(if_pc), .if_instr(if_inst), .if_stall(if_stall)
    );

    if_id_reg u_if_id_reg (
        .clk(clk), .rst_n(rst_n), .flush(if_id_flush), .en(id_reg_en && !global_stall),
        .if_pc(if_pc), .if_inst(if_inst), .id_pc(id_pc), .id_inst(id_inst)
    );

    // [DECODE]
    decode_stage u_decode_stage (
        .clk(clk), .if_id_inst(id_inst), .if_id_pc(id_pc),
        .wb_reg_write_en(wb_reg_write_en), .wb_write_reg_addr(wb_rd_addr), .wb_write_data(wb_final_data),
        .id_read_data1(id_read_data1), .id_read_data2(id_read_data2), .id_imm(id_imm),
        .id_rs1(id_rs1), .id_rs2(id_rs2), .id_rd(id_rd_addr), .id_funct3(id_funct3),
        .id_reg_write_en(id_reg_write_en), .id_mem_read_en(id_mem_read_en),
        .id_mem_write_en(id_mem_write_en), .id_mem_to_reg_sel(id_mem_to_reg_sel),
        .id_alu_op_sel(id_alu_op_sel), .id_alu_src_sel(id_alu_src_sel),
        .id_branch_en(id_branch_en), .id_jal_en(id_jal_en), .id_jalr_en(id_jalr_en),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used),
        .id_auipc_en(id_auipc_en), .id_csr_en(id_csr_en), .id_valid_inst(id_valid_inst)
    );
    
    id_ex_reg u_id_ex_reg (
        .clk(clk), .rst_n(rst_n), .flush(id_ex_flush),.en(!global_stall),
        .id_pc(id_pc), .id_read_data1(id_read_data1), .id_read_data2(id_read_data2),
        .id_imm(id_imm), .id_inst(id_inst), .id_rs1(id_rs1), .id_rs2(id_rs2), .id_rd(id_rd_addr),
        .id_alu_op_sel(id_alu_op_sel), .id_alu_src_sel(id_alu_src_sel), .id_reg_write_en(id_reg_write_en),
        .id_mem_read_en(id_mem_read_en), .id_mem_write_en(id_mem_write_en), .id_mem_to_reg_sel(id_mem_to_reg_sel),
        .id_branch_en(id_branch_en), .id_jal_en(id_jal_en), .id_jalr_en(id_jalr_en),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used),
        .id_auipc_en(id_auipc_en), .id_csr_en(id_csr_en), .id_valid_inst(id_valid_inst),
        .ex_pc(ex_pc), .ex_read_data1(ex_read_data1), .ex_read_data2(ex_read_data2),
        .ex_imm(ex_imm), .ex_inst(ex_inst), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .ex_rd(ex_rd_addr),
        .ex_alu_op_sel(ex_alu_op_sel), .ex_alu_src_sel(ex_alu_src_sel), .ex_reg_write_en(ex_reg_write_en),
        .ex_mem_read_en(ex_mem_read_en), .ex_mem_write_en(ex_mem_write_en), .ex_mem_to_reg_sel(ex_mem_to_reg_sel),
        .ex_branch_en(ex_branch_en), .ex_jal_en(ex_jal_en), .ex_jalr_en(ex_jalr_en),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .ex_auipc_en(ex_auipc_en), .ex_csr_en(ex_csr_en), .ex_valid_inst(ex_valid_inst)
    );

    // [EXECUTE]
    execute_stage u_execute_stage (
        .ex_pc(ex_pc), .ex_read_data1(ex_read_data1), .ex_read_data2(ex_read_data2),
        .ex_imm(ex_imm), .ex_inst(ex_inst), 
        .mem_forward_data(mem_mem_to_reg_sel ? mem_rd_data : mem_alu_res), .wb_forward_data(wb_final_data),
        .forward_a_sel(forward_a_sel), .forward_b_sel(forward_b_sel),
        .ex_alu_op_sel(ex_alu_op_sel), .ex_alu_src_sel(ex_alu_src_sel),
        .ex_branch_en(ex_branch_en), .ex_jal_en(ex_jal_en), .ex_jalr_en(ex_jalr_en),
        .ex_branch_target(ex_branch_target), .ex_alu_result(ex_alu_res),
        .ex_write_data_mem(ex_wr_data_mem), .ex_alu_zero(ex_alu_zero),
        .ex_csr_rdata(ex_csr_rdata), .ex_csr_en(ex_csr_en), .ex_auipc_en(ex_auipc_en)
    );

    ex_mem_reg u_ex_mem_reg_inst (
        .clk(clk), .rst_n(rst_n), .flush(ex_mem_flush),.en(!global_stall),
        .ex_alu_result(ex_alu_res), .ex_write_data(ex_wr_data_mem), .ex_branch_target(ex_branch_target),
        .ex_rd_addr(ex_rd_addr), .ex_funct3(ex_inst[14:12]), .ex_alu_zero(ex_alu_zero), .ex_valid_inst(ex_valid_inst),
        .ex_reg_write_en(ex_reg_write_en), .ex_mem_to_reg_sel(ex_mem_to_reg_sel),
        .ex_mem_read_en(ex_mem_read_en), .ex_mem_write_en(ex_mem_write_en),
        .ex_branch_en(ex_branch_en), .ex_jal_en(ex_jal_en), .ex_jalr_en(ex_jalr_en),
        .mem_alu_result(mem_alu_res), .mem_write_data(mem_wr_data), .mem_branch_target(mem_branch_target),
        .mem_rd_addr(mem_rd_addr), .mem_funct3(mem_funct3), .mem_alu_zero(mem_alu_zero), .mem_valid_inst(mem_valid_inst),
        .mem_reg_write_en(mem_reg_write_en), .mem_mem_to_reg_sel(mem_mem_to_reg_sel),
        .mem_mem_read_en(mem_mem_read_en), .mem_mem_write_en(mem_mem_write_en),
        .mem_branch_en(mem_branch_en), .mem_jal_en(mem_jal_en), .mem_jalr_en(mem_jalr_en)
    );

    // [MEMORY]

    memory_stage u_memory_stage (
        .mem_alu_result(mem_alu_res), .mem_write_data(mem_wr_data),
        .mem_branch_target_in(mem_branch_target),
        .mem_mem_read_en(mem_mem_read_en), .mem_mem_write_en(mem_mem_write_en),
        .mem_branch_en(mem_branch_en), .mem_funct3(mem_funct3), .mem_alu_zero(mem_alu_zero),
        .ram_rd_data(data_mem_rd_data),
        .mem_read_data(mem_rd_data), .mem_branch_target_out(final_branch_addr),
        .mem_branch_taken(mem_branch_taken)
    );

    mem_wb_reg u_mem_wb_reg_inst (
        .clk(clk), .rst_n(rst_n),
        // During the UART stall cycle, FLUSH (not freeze) the MEM/WB register.
        // This inserts a NOP into WB so the instruction that was already there
        // does not get written to the register file a second time on release.
        // On the next cycle (stall gone), en=1 captures the now-settled
        // uart_rdata_sync value into WB.
        .flush(uart_stall),
        .en(1'b1),
        .mem_alu_res(mem_alu_res), .mem_mem_data(mem_rd_data), .mem_rd_addr(mem_rd_addr), .mem_valid_inst(mem_valid_inst),
        .mem_reg_write_en(mem_reg_write_en), .mem_mem_to_reg_sel(mem_mem_to_reg_sel),
        .wb_alu_res(wb_alu_res), .wb_mem_data(wb_mem_data), .wb_rd_addr(wb_rd_addr), .wb_valid_inst(wb_valid_inst),
        .wb_reg_write_en(wb_reg_write_en), .wb_mem_to_reg_sel(wb_mem_to_reg_sel)
    );

    writeback_stage u_writeback_stage (
        .wb_alu_res(wb_alu_res), .wb_mem_data(wb_mem_data),
        .wb_mem_to_reg_sel(wb_mem_to_reg_sel), .wb_final_data(wb_final_data)
    );

    // [UNITS]
    forwarding_unit u_forwarding_unit (
        .clk(clk), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2), .mem_rd_addr(mem_rd_addr), .wb_rd_addr(wb_rd_addr),
        .mem_reg_write_en(mem_reg_write_en), .wb_reg_write_en(wb_reg_write_en),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .forward_a_sel(forward_a_sel), .forward_b_sel(forward_b_sel)
    );


    hazard_detection_unit u_hazard_detection_unit (
        .id_rs1            (id_rs1),
        .id_rs2            (id_rs2),
        .ex_rd_addr        (ex_rd_addr),
        .ex_mem_read_en    (ex_mem_read_en),
        .jump_branch_taken (actual_jump),
        .mem_mem_read_en   (mem_mem_read_en),
        .mem_alu_result    (mem_alu_res),
        // The FF below captures uart_stall so the HDU can deassert on cycle+1.
        .uart_already_waited (uart_wait_cycle_q),
        .if_pc_en          (if_pc_en),
        .id_reg_en         (id_reg_en),
        .id_ex_flush       (id_ex_flush),
        .if_id_flush       (if_id_flush),
        .ex_mem_flush      (ex_mem_flush),
        .uart_stall        (uart_stall)
    );

    csr_unit u_csr_unit (
        .clk(clk), .rst_n(rst_n),
        .inst_retired(ex_valid_inst), 
        .csr_we(1'b0), // No CSR writes for now — read-only path
        .csr_addr(ex_inst[31:20]),
        .csr_wdata(32'b0),
        .csr_rdata(ex_csr_rdata)
    );

    // -----------------------------------------------------------------------
    // UART wait-state state machine
    //
    // uart_stall is driven combinatorially by the HDU (uart_stall output).
    // uart_wait_cycle_q is the one-cycle memory: it goes high the cycle after
    // uart_stall fires and feeds back into the HDU as uart_already_waited,
    // causing the HDU to deassert uart_stall on that second cycle.
    //
    // Timing diagram (lbu t1, 0(t0) targeting 0x3000):
    //
    //  Cycle:             N          N+1        N+2
    //  lbu in stage:      MEM        MEM        WB
    //  uart_stall:        1          0          0
    //  uart_wait_cycle_q: 0          1          0
    //  uart_rdata_sync:   stale    correct    correct
    //  mem_wb_reg action: flush    capture      --
    //  t1 written:                              ✓
    // -----------------------------------------------------------------------
    logic uart_stall;       // driven by HDU
    logic uart_wait_cycle_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) uart_wait_cycle_q <= 1'b0;
        else        uart_wait_cycle_q <= uart_stall;
    end

    // global_stall freezes every pipeline register except mem_wb_reg
    // (which is handled separately with a flush to avoid double-writes).
    logic global_stall;
    assign global_stall = uart_stall;

endmodule