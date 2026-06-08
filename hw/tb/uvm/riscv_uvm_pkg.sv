// ============================================================================
// Package : riscv_uvm_pkg
// Description : UVM agent for the RISC-V SoC.
//
//   Contents (in dependency order):
//     riscv_regwrite_item  — one observed register-file write (monitor → SB)
//     riscv_seq_item       — one complete test program (sequence → driver → SB)
//     riscv_iss            — simple RV32I ISS; computes expected register writes
//     riscv_base_seq       — abstract base with instruction-encoding helpers
//     riscv_alu_seq        — R-type + I-type ALU test program
//     riscv_load_store_seq — load/store test program
//     riscv_driver         — loads ROM (backdoor), drives rst_n, runs program
//     riscv_monitor        — watches register-file write port each cycle
//     riscv_scoreboard     — in-order comparison of observed vs expected writes
//     riscv_agent          — driver + monitor + sequencer
//     riscv_env            — agent + scoreboard with TLM connections
//     riscv_base_test      — base test (creates env)
//     riscv_alu_test       — runs riscv_alu_seq
//     riscv_load_store_test— runs riscv_load_store_seq
//
// Simulator notes:
//   - Tested with Questa / VCS.  Xsim has limited UVM support; the backdoor
//     force statements inside UVM tasks require +acc access for Xsim.
//   - The driver references the fixed hierarchy riscv_uvm_tb.uut.* for force
//     and $deposit.  If the top-level module or DUT instance name changes,
//     update the two macros at the top of riscv_driver.
// ============================================================================
`ifndef RISCV_UVM_PKG_SV
`define RISCV_UVM_PKG_SV

package riscv_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Multiple-write analysis imp suffixes — declared before any class that
    // instantiates them.
    `uvm_analysis_imp_decl(_expected)
    `uvm_analysis_imp_decl(_observed)


    // ========================================================================
    // riscv_regwrite_item
    // Sent by the monitor for every non-x0 register-file write it observes.
    // ========================================================================
    class riscv_regwrite_item extends uvm_sequence_item;
        `uvm_object_utils(riscv_regwrite_item)

        logic [4:0]  rd;
        logic [31:0] value;

        function new(string name = "riscv_regwrite_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("x%0d = 0x%08h", rd, value);
        endfunction
    endclass : riscv_regwrite_item


    // ========================================================================
    // riscv_seq_item
    // Sent by the sequence to the driver.  Carries the full test program and
    // the ISS-predicted register writes in execution order.
    // ========================================================================
    typedef struct packed {
        logic [4:0]  rd;
        logic [31:0] value;
    } riscv_expected_write_t;

    class riscv_seq_item extends uvm_sequence_item;
        `uvm_object_utils(riscv_seq_item)

        // Word-addressed program to load into ROM (index 0 → address 0x0000)
        logic [31:0] instructions[$];

        // ISS-predicted writes in program order (only non-x0 rd instructions)
        riscv_expected_write_t expected_writes[$];

        // Clocks to run before the driver re-asserts reset
        int unsigned run_cycles = 300;

        function new(string name = "riscv_seq_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("[%0d instr | %0d expected writes | %0d cycles]",
                instructions.size(), expected_writes.size(), run_cycles);
        endfunction
    endclass : riscv_seq_item


    // ========================================================================
    // riscv_iss (Instruction Set Simulator)
    // Lightweight RV32I instruction set simulator.
    // Tracks register state and (sparse) data-memory state.
    // Does not model branches/jumps for control flow — intended for
    // straight-line test programs that execute every instruction once.
    // ========================================================================
    class riscv_iss;

        logic [31:0] regs [32];
        logic [31:0] mem  [bit [31:0]];  // sparse: key = word address
        logic [31:0] pc;

        function void reset();
            foreach (regs[i]) regs[i] = '0;
            mem.delete();
            pc = '0;
        endfunction

        // Execute one instruction.
        // Returns 1 and sets rd_out/val_out when it commits a non-x0 write.
        function automatic bit execute(
            input  logic [31:0] instr,
            output logic [4:0]  rd_out,
            output logic [31:0] val_out
        );
            logic [6:0] opcode = instr[6:0];
            logic [4:0] rd     = instr[11:7];
            logic [2:0] f3     = instr[14:12];
            logic [4:0] rs1    = instr[19:15];
            logic [4:0] rs2    = instr[24:20];
            logic [6:0] f7     = instr[31:25];
            logic [4:0] shamt  = instr[24:20];

            logic signed [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
            logic signed [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            logic [31:0]        imm_u = {instr[31:12], 12'b0};
            logic signed [31:0] imm_j = {{12{instr[31]}}, instr[19:12],
                                          instr[20], instr[30:21], 1'b0};

            logic [31:0] a = (rs1 == 0) ? '0 : regs[rs1];
            logic [31:0] b = (rs2 == 0) ? '0 : regs[rs2];
            logic [31:0] result = '0;
            bit    has_write = 0;

            rd_out  = rd;
            val_out = '0;

            case (opcode)

                // R-type
                7'b0110011: begin
                    has_write = (rd != 0);
                    case ({f7[5], f3})
                        4'b0_000: result = a + b;                           // ADD
                        4'b1_000: result = a - b;                           // SUB
                        4'b0_111: result = a & b;                           // AND
                        4'b0_110: result = a | b;                           // OR
                        4'b0_100: result = a ^ b;                           // XOR
                        4'b0_001: result = a << b[4:0];                     // SLL
                        4'b0_101: result = a >> b[4:0];                     // SRL
                        4'b1_101: result = logic'($signed(a) >>> b[4:0]);   // SRA
                        4'b0_010: result = ($signed(a) < $signed(b)) ? 1:0; // SLT
                        4'b0_011: result = (a < b) ? 1 : 0;                 // SLTU
                        default:  has_write = 0;
                    endcase
                end

                // I-type ALU
                7'b0010011: begin
                    has_write = (rd != 0);
                    case (f3)
                        3'b000: result = a + imm_i;                          // ADDI
                        3'b111: result = a & imm_i;                          // ANDI
                        3'b110: result = a | imm_i;                          // ORI
                        3'b100: result = a ^ imm_i;                          // XORI
                        3'b001: result = a << shamt;                         // SLLI
                        3'b101: result = f7[5] ?
                                    logic'($signed(a) >>> shamt) :           // SRAI
                                    a >> shamt;                              // SRLI
                        3'b010: result = ($signed(a) < $signed(imm_i))?1:0; // SLTI
                        3'b011: result = (a < 32'(unsigned'(imm_i))) ? 1:0; // SLTIU
                        default: has_write = 0;
                    endcase
                end

                // Load
                7'b0000011: begin
                    has_write = (rd != 0);
                    begin
                        automatic logic [31:0] addr   = a + imm_i;
                        automatic logic [31:0] waddr  = addr >> 2;
                        automatic logic [31:0] word   =
                            mem.exists(waddr) ? mem[waddr] : '0;
                        case (f3)
                            3'b000: result = {{24{word[8*addr[1:0]+7]}},
                                              word[8*addr[1:0] +: 8]};      // LB
                            3'b001: result = {{16{word[16*addr[1]+15]}},
                                              word[16*addr[1] +: 16]};      // LH
                            3'b010: result = word;                           // LW
                            3'b100: result = {24'b0, word[8*addr[1:0]+:8]}; // LBU
                            3'b101: result = {16'b0, word[16*addr[1]+:16]}; // LHU
                            default: has_write = 0;
                        endcase
                    end
                end

                // Store — no register write, but update ISS memory model
                7'b0100011: begin
                    has_write = 0;
                    begin
                        automatic logic [31:0] addr  = a + imm_s;
                        automatic logic [31:0] waddr = addr >> 2;
                        automatic logic [31:0] word  =
                            mem.exists(waddr) ? mem[waddr] : '0;
                        case (f3)
                            3'b000: begin // SB
                                word[8*addr[1:0] +: 8] = b[7:0];
                                mem[waddr] = word;
                            end
                            3'b001: begin // SH
                                word[16*addr[1] +: 16] = b[15:0];
                                mem[waddr] = word;
                            end
                            3'b010: mem[waddr] = b; // SW
                            default: ;
                        endcase
                    end
                end

                // Branch — no register write
                7'b1100011: has_write = 0;

                // JAL: rd = PC + 4
                7'b1101111: begin
                    has_write = (rd != 0);
                    result    = pc + 4;
                    // Control flow not modelled (straight-line ISS)
                end

                // JALR: rd = PC + 4
                7'b1100111: begin
                    has_write = (rd != 0);
                    result    = pc + 4;
                end

                // LUI
                7'b0110111: begin
                    has_write = (rd != 0);
                    result    = imm_u;
                end

                // AUIPC
                7'b0010111: begin
                    has_write = (rd != 0);
                    result    = pc + imm_u;
                end

                default: has_write = 0;
            endcase

            pc += 4;

            if (has_write && rd != 0) begin
                regs[rd] = result;
                rd_out   = rd;
                val_out  = result;
                return 1;
            end
            return 0;
        endfunction  // execute

        // Run the full program and collect predicted register writes.
        function automatic void simulate(
            input  logic [31:0]           instructions[$],
            output riscv_expected_write_t writes[$]
        );
            logic [4:0]  rd;
            logic [31:0] val;
            reset();
            writes = {};
            foreach (instructions[i]) begin
                // Stop at JAL x0, 0 (infinite loop sentinel)
                if (instructions[i] == 32'h0000006f) break;
                if (execute(instructions[i], rd, val)) begin
                    riscv_expected_write_t w;
                    w.rd    = rd;
                    w.value = val;
                    writes.push_back(w);
                end
            end
        endfunction

    endclass : riscv_iss


    // ========================================================================
    // riscv_base_seq
    // Abstract base sequence.  Provides instruction-encoding helper functions
    // so derived sequences can build programs without raw bit manipulation.
    // ========================================================================
    class riscv_base_seq extends uvm_sequence #(riscv_seq_item);
        `uvm_object_utils(riscv_base_seq)

        riscv_iss iss;

        function new(string name = "riscv_base_seq");
            super.new(name);
            iss = new();
        endfunction

        // --- Encoding helpers -----------------------------------------------

        function automatic logic [31:0] r_type(
            input logic [4:0] rd, rs1, rs2,
            input logic [2:0] funct3,
            input logic [6:0] funct7
        );
            return {funct7, rs2, rs1, funct3, rd, 7'b0110011};
        endfunction

        function automatic logic [31:0] i_alu(
            input logic [4:0]          rd, rs1,
            input logic [2:0]          funct3,
            input logic signed [11:0]  imm
        );
            return {imm, rs1, funct3, rd, 7'b0010011};
        endfunction

        function automatic logic [31:0] i_load(
            input logic [4:0]          rd, rs1,
            input logic [2:0]          funct3,
            input logic signed [11:0]  imm
        );
            return {imm, rs1, funct3, rd, 7'b0000011};
        endfunction

        function automatic logic [31:0] s_type(
            input logic [4:0]          rs1, rs2,
            input logic [2:0]          funct3,
            input logic signed [11:0]  imm
        );
            return {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
        endfunction

        function automatic logic [31:0] lui(
            input logic [4:0]  rd,
            input logic [19:0] imm_u // bits [31:12] of the 32-bit immediate
        );
            return {imm_u, rd, 7'b0110111};
        endfunction

        function automatic logic [31:0] jal(
            input logic [4:0]          rd,
            input logic signed [20:1]  offset
        );
            return {offset[20], offset[10:1], offset[11], offset[19:12],
                    rd, 7'b1101111};
        endfunction

        // JAL x0, 0 — program end marker (infinite loop; ISS stops here)
        function automatic logic [31:0] end_program();
            return 32'h0000006f; // jal x0, 0
        endfunction

        virtual task body();
            `uvm_fatal("BASE_SEQ", "Derived class must override body()")
        endtask

    endclass : riscv_base_seq


    // ========================================================================
    // riscv_alu_seq
    // Exercises all R-type and I-type ALU instructions on two operands.
    //
    // Register assignments:
    //   x1 = 10,  x2 = 3
    //   x3  = ADD  x1,x2 → 13
    //   x4  = SUB  x1,x2 → 7
    //   x5  = AND  x1,x2 → 2
    //   x6  = OR   x1,x2 → 11
    //   x7  = XOR  x1,x2 → 9
    //   x8  = SLL  x1,x2 → 80
    //   x9  = SRL  x1,x2 → 1
    //   x10 = -4;  x10   = SRA x10,x2 → -1
    //   x11 = SLT  x1,x2 → 0 (10 is not < 3)
    //   x12 = SLT  x2,x1 → 1 (3 is < 10)
    //   x13 = ADDI x1, 5 → 15
    //   x14 = ANDI x1,0xF→ 10
    //   x15 = ORI  x1, 5 → 15
    //   x16 = XORI x1,0xF→ 5
    // ========================================================================
    class riscv_alu_seq extends riscv_base_seq;
        `uvm_object_utils(riscv_alu_seq)

        function new(string name = "riscv_alu_seq");
            super.new(name);
        endfunction

        virtual task body();
            riscv_seq_item  item = riscv_seq_item::type_id::create("alu_item");
            logic [31:0]    prog[$];

            prog.push_back(i_alu(5'd1,  5'd0, 3'b000, 12'd10));              // ADDI x1,  x0, 10
            prog.push_back(i_alu(5'd2,  5'd0, 3'b000, 12'd3));               // ADDI x2,  x0, 3
            prog.push_back(r_type(5'd3,  5'd1, 5'd2, 3'b000, 7'b0000000));   // ADD  x3, x1, x2
            prog.push_back(r_type(5'd4,  5'd1, 5'd2, 3'b000, 7'b0100000));   // SUB  x4, x1, x2
            prog.push_back(r_type(5'd5,  5'd1, 5'd2, 3'b111, 7'b0000000));   // AND  x5, x1, x2
            prog.push_back(r_type(5'd6,  5'd1, 5'd2, 3'b110, 7'b0000000));   // OR   x6, x1, x2
            prog.push_back(r_type(5'd7,  5'd1, 5'd2, 3'b100, 7'b0000000));   // XOR  x7, x1, x2
            prog.push_back(r_type(5'd8,  5'd1, 5'd2, 3'b001, 7'b0000000));   // SLL  x8, x1, x2
            prog.push_back(r_type(5'd9,  5'd1, 5'd2, 3'b101, 7'b0000000));   // SRL  x9, x1, x2
            prog.push_back(i_alu(5'd10, 5'd0, 3'b000, -12'd4));              // ADDI x10, x0, -4
            prog.push_back(r_type(5'd10, 5'd10, 5'd2, 3'b101, 7'b0100000)); // SRA  x10, x10, x2
            prog.push_back(r_type(5'd11, 5'd1, 5'd2, 3'b010, 7'b0000000));   // SLT  x11, x1, x2
            prog.push_back(r_type(5'd12, 5'd2, 5'd1, 3'b010, 7'b0000000));   // SLT  x12, x2, x1
            prog.push_back(i_alu(5'd13, 5'd1, 3'b000,  12'd5));              // ADDI x13, x1, 5
            prog.push_back(i_alu(5'd14, 5'd1, 3'b111, 12'hf));               // ANDI x14, x1, 0xF
            prog.push_back(i_alu(5'd15, 5'd1, 3'b110, 12'h5));               // ORI  x15, x1, 5
            prog.push_back(i_alu(5'd16, 5'd1, 3'b100, 12'hf));               // XORI x16, x1, 0xF
            prog.push_back(end_program());

            item.instructions = prog;
            item.run_cycles   = 400;
            iss.simulate(prog, item.expected_writes);

            start_item(item);
            finish_item(item);
        endtask

    endclass : riscv_alu_seq


    // ========================================================================
    // riscv_load_store_seq
    // Tests word/byte load and store instructions via the data cache and RAM.
    // RAM is mapped at base address 0x2000.
    //
    //   x1 = 0x2000      (LUI x1, 2)
    //   x2 = 171 = 0xAB  (ADDI x2, x0, 171)
    //   SW  x2, 0(x1)   → mem[0x2000] = 0x000000AB
    //   LW  x3, 0(x1)   → x3 = 0x000000AB
    //   SB  x2, 4(x1)   → mem[0x2004][7:0] = 0xAB
    //   LBU x4, 4(x1)   → x4 = 0x000000AB (zero-extended)
    //   LB  x5, 4(x1)   → x5 = 0xFFFFFFAB (0xAB has bit7=1 → sign-extended)
    //   SH  x2, 8(x1)   → mem[0x2008][15:0] = 0x00AB
    //   LHU x6, 8(x1)   → x6 = 0x000000AB
    // ========================================================================
    class riscv_load_store_seq extends riscv_base_seq;
        `uvm_object_utils(riscv_load_store_seq)

        function new(string name = "riscv_load_store_seq");
            super.new(name);
        endfunction

        virtual task body();
            riscv_seq_item item = riscv_seq_item::type_id::create("ls_item");
            logic [31:0]   prog[$];

            prog.push_back(lui(5'd1, 20'd2));                               // LUI  x1, 2  → x1=0x2000
            prog.push_back(i_alu(5'd2, 5'd0, 3'b000, 12'd171));            // ADDI x2, x0, 171
            prog.push_back(s_type(5'd1, 5'd2, 3'b010, 12'd0));             // SW   x2, 0(x1)
            prog.push_back(i_load(5'd3, 5'd1, 3'b010, 12'd0));             // LW   x3, 0(x1) → 171
            prog.push_back(s_type(5'd1, 5'd2, 3'b000, 12'd4));             // SB   x2, 4(x1)
            prog.push_back(i_load(5'd4, 5'd1, 3'b100, 12'd4));             // LBU  x4, 4(x1) → 171
            prog.push_back(i_load(5'd5, 5'd1, 3'b000, 12'd4));             // LB   x5, 4(x1) → 171
            prog.push_back(s_type(5'd1, 5'd2, 3'b001, 12'd8));             // SH   x2, 8(x1)
            prog.push_back(i_load(5'd6, 5'd1, 3'b101, 12'd8));             // LHU  x6, 8(x1) → 171
            prog.push_back(end_program());

            item.instructions = prog;
            item.run_cycles   = 600; // loads stall ~5 cycles each due to D-Cache
            iss.simulate(prog, item.expected_writes);

            start_item(item);
            finish_item(item);
        endtask

    endclass : riscv_load_store_seq


    // ========================================================================
    // riscv_driver
    //
    // Protocol:
    //   1. Receive seq_item from sequencer.
    //   2. Force rst_n=0 (keep DUT in reset).
    //   3. Backdoor-write the test program into ROM via UVM HDL backdoor.
    //   4. Broadcast seq_item (with expected writes) to scoreboard NOW,
    //      before releasing reset, so expected_q is populated before the
    //      monitor can produce any observed events.
    //   5. Hold reset for 10 cycles, then release.
    //   6. Wait item.run_cycles for execution to complete.
    //   7. Re-assert reset and call item_done.
    //
    // Backdoor mechanism — uvm_hdl_deposit / uvm_hdl_force (string paths):
    //   Questa resolves hierarchical `force` paths inside a *package* at
    //   compile time, before the module hierarchy is built, so absolute
    //   paths such as "riscv_uvm_tb.uut.u_rom.mem" cannot be found.
    //   uvm_hdl_deposit / uvm_hdl_force accept *string* paths resolved at
    //   runtime via VPI — no compile-time hierarchy check at all.
    //   EDA Playground passes -access=rw+/. automatically, granting the
    //   full read/write VPI access these functions require.
    //
    //   To retarget: change ROM_HDL_PATH / RST_HDL_PATH below.
    // ========================================================================

    class riscv_driver extends uvm_driver #(riscv_seq_item);
        `uvm_component_utils(riscv_driver)

        // String paths for UVM HDL backdoor — resolved at runtime, not
        // at compile time, so no hierarchical-reference compile errors.
        localparam string ROM_HDL_PATH = "riscv_uvm_tb.uut.u_rom.mem";
        localparam string RST_HDL_PATH = "riscv_uvm_tb.rst_n";

        virtual riscv_if vif;

        // Analysis port: broadcasts seq_item (with expected writes) to SB.
        uvm_analysis_port #(riscv_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual riscv_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV_CFG", "Virtual interface 'vif' not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            riscv_seq_item item;
            set_rst(1'b0); // keep in reset until a sequence arrives
            forever begin
                seq_item_port.get_next_item(item);
                `uvm_info("DRV", {"Received program: ", item.convert2string()}, UVM_MEDIUM)
                drive_program(item);
                seq_item_port.item_done();
            end
        endtask

        task drive_program(riscv_seq_item item);
            // Step 1: assert reset before touching ROM
            set_rst(1'b0);
            repeat(2) @(vif.monitor_cb);

            // Step 2: backdoor-load the test program into ROM
            backdoor_load_rom(item.instructions);

            // Step 3: publish expected writes BEFORE releasing reset so the
            //         scoreboard queue is populated before any monitor events.
            ap.write(item);

            // Step 4: hold reset for 10 cycles then release
            repeat(10) @(vif.monitor_cb);
            set_rst(1'b1);
            `uvm_info("DRV", "Reset released - program running", UVM_HIGH)

            // Step 5: wait for the program to run
            repeat(item.run_cycles) @(vif.monitor_cb);

            // Step 6: re-assert reset so the core is clean for the next item
            set_rst(1'b0);
            repeat(2) @(vif.monitor_cb);
            `uvm_info("DRV", "Program run complete", UVM_MEDIUM)
        endtask

        // Backdoor-load every ROM word via uvm_hdl_deposit.
        // The string path is resolved at runtime through VPI — no
        // compile-time hierarchy check, no automatic-variable restriction.
        task automatic backdoor_load_rom(input logic [31:0] words[$]);
            logic [31:0] rom_word;
            string       elem_path;
            for (int i = 0; i < 1024; i++) begin
                rom_word  = (i < int'(words.size())) ? words[i]
                                                     : 32'h00000013; // NOP
                elem_path = $sformatf("%s[%0d]", ROM_HDL_PATH, i);
                if (!uvm_hdl_deposit(elem_path, rom_word))
                    `uvm_error("DRV",
                        $sformatf("uvm_hdl_deposit FAILED: %s", elem_path))
            end
            `uvm_info("DRV",
                $sformatf("ROM loaded via backdoor (%0d words)", words.size()),
                UVM_HIGH)
        endtask

        // Drive rst_n via uvm_hdl_force — string path, runtime resolved.
        task set_rst(input logic val);
            logic rst_val = val;   // 1-bit logic; auto zero-extended to hdl_data_t
            if (!uvm_hdl_force(RST_HDL_PATH, rst_val))
                `uvm_error("DRV",
                    $sformatf("uvm_hdl_force FAILED: %s", RST_HDL_PATH))
        endtask

    endclass : riscv_driver


    // ========================================================================
    // riscv_monitor
    // Samples the register-file write port every clock cycle.
    // Sends one riscv_regwrite_item to the scoreboard for each non-x0 write.
    // ========================================================================
    class riscv_monitor extends uvm_monitor;
        `uvm_component_utils(riscv_monitor)

        virtual riscv_if vif;
        uvm_analysis_port #(riscv_regwrite_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual riscv_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON_CFG", "Virtual interface 'vif' not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(vif.monitor_cb);
                // Only capture writes while the core is out of reset and
                // the destination is a real register (not x0).
                if (vif.monitor_cb.rst_n &&
                    vif.monitor_cb.regfile_we &&
                    vif.monitor_cb.regfile_waddr != 5'd0)
                begin
                    riscv_regwrite_item obs =
                        riscv_regwrite_item::type_id::create("obs");
                    obs.rd    = vif.monitor_cb.regfile_waddr;
                    obs.value = vif.monitor_cb.regfile_wdata;
                    `uvm_info("MON",
                        $sformatf("Observed: %s", obs.convert2string()), UVM_HIGH)
                    ap.write(obs);
                end
            end
        endtask

    endclass : riscv_monitor


    // ========================================================================
    // riscv_scoreboard
    // Receives expected writes from the driver and observed writes from the
    // monitor, comparing them in program order (FIFO).
    // ========================================================================
    class riscv_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(riscv_scoreboard)

        // expected_imp  → write_expected()  (called by driver analysis port)
        // observed_imp  → write_observed()  (called by monitor analysis port)
        uvm_analysis_imp_expected #(riscv_seq_item,      riscv_scoreboard) expected_imp;
        uvm_analysis_imp_observed #(riscv_regwrite_item, riscv_scoreboard) observed_imp;

        riscv_expected_write_t expected_q[$];

        int unsigned pass_count = 0;
        int unsigned fail_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            expected_imp = new("expected_imp", this);
            observed_imp = new("observed_imp", this);
        endfunction

        // Called by driver: load the full list of expected writes into the FIFO.
        function void write_expected(riscv_seq_item item);
            foreach (item.expected_writes[i])
                expected_q.push_back(item.expected_writes[i]);
            `uvm_info("SB",
                $sformatf("Loaded %0d expected writes", item.expected_writes.size()),
                UVM_MEDIUM)
        endfunction

        // Called by monitor: compare one observed write against the next expected.
        function void write_observed(riscv_regwrite_item obs);
            riscv_expected_write_t exp;

            if (expected_q.size() == 0) begin
                `uvm_error("SB", $sformatf(
                    "Unexpected extra write: x%0d = 0x%08h (expected queue empty)",
                    obs.rd, obs.value))
                fail_count++;
                return;
            end

            exp = expected_q.pop_front();

            if (obs.rd !== exp.rd) begin
                `uvm_error("SB", $sformatf(
                    "Register mismatch — observed x%0d, expected x%0d (value 0x%08h)",
                    obs.rd, exp.rd, obs.value))
                fail_count++;
            end else if (obs.value !== exp.value) begin
                `uvm_error("SB", $sformatf(
                    "Value mismatch for x%0d — got 0x%08h, expected 0x%08h",
                    obs.rd, obs.value, exp.value))
                fail_count++;
            end else begin
                `uvm_info("SB", $sformatf(
                    "PASS  x%0d = 0x%08h", obs.rd, obs.value), UVM_MEDIUM)
                pass_count++;
            end
        endfunction

        function void report_phase(uvm_phase phase);
            string result_str = (fail_count == 0 && pass_count > 0) ?
                "ALL TESTS PASSED" : "TESTS FAILED";
            `uvm_info("SB", $sformatf(
                "%s — %0d passed, %0d failed",
                result_str, pass_count, fail_count), UVM_NONE)
            if (expected_q.size() > 0)
                `uvm_warning("SB", $sformatf(
                    "%0d expected writes were never observed — program may not have finished",
                    expected_q.size()))
            if (fail_count > 0)
                `uvm_fatal("SB", "Simulation ended with failures")
        endfunction

    endclass : riscv_scoreboard


    // ========================================================================
    // riscv_agent
    // ========================================================================
    class riscv_agent extends uvm_agent;
        `uvm_component_utils(riscv_agent)

        riscv_driver                    driver;
        riscv_monitor                   monitor;
        uvm_sequencer #(riscv_seq_item) sequencer;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = uvm_sequencer #(riscv_seq_item)::type_id::create(
                            "sequencer", this);
            driver    = riscv_driver::type_id::create("driver",   this);
            monitor   = riscv_monitor::type_id::create("monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction

    endclass : riscv_agent


    // ========================================================================
    // riscv_env
    // ========================================================================
    class riscv_env extends uvm_env;
        `uvm_component_utils(riscv_env)

        riscv_agent      agent;
        riscv_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = riscv_agent::type_id::create("agent",       this);
            scoreboard = riscv_scoreboard::type_id::create("scoreboard", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            // Driver broadcasts expected writes → scoreboard expected queue
            agent.driver.ap.connect(scoreboard.expected_imp);
            // Monitor broadcasts observed writes → scoreboard comparison
            agent.monitor.ap.connect(scoreboard.observed_imp);
        endfunction

    endclass : riscv_env


    // ========================================================================
    // riscv_base_test
    // ========================================================================
    class riscv_base_test extends uvm_test;
        `uvm_component_utils(riscv_base_test)

        riscv_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = riscv_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.print_topology();
        endfunction

    endclass : riscv_base_test


    // ========================================================================
    // riscv_alu_test
    // ========================================================================
    class riscv_alu_test extends riscv_base_test;
        `uvm_component_utils(riscv_alu_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            riscv_alu_seq seq = riscv_alu_seq::type_id::create("alu_seq");
            phase.raise_objection(this, "ALU test running");
            seq.start(env.agent.sequencer);
            // Drain a few cycles for final pipeline writeback
            repeat(20) @(env.agent.monitor.vif.monitor_cb);
            phase.drop_objection(this, "ALU test done");
        endtask

    endclass : riscv_alu_test


    // ========================================================================
    // riscv_load_store_test
    // ========================================================================
    class riscv_load_store_test extends riscv_base_test;
        `uvm_component_utils(riscv_load_store_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            riscv_load_store_seq seq =
                riscv_load_store_seq::type_id::create("ls_seq");
            phase.raise_objection(this, "Load/store test running");
            seq.start(env.agent.sequencer);
            repeat(20) @(env.agent.monitor.vif.monitor_cb);
            phase.drop_objection(this, "Load/store test done");
        endtask

    endclass : riscv_load_store_test

endpackage : riscv_uvm_pkg

`endif // RISCV_UVM_PKG_SV
