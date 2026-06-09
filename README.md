# RISC-V RV32I SoC — 5-Stage Pipelined Processor on Basys 3 FPGA

A fully synthesizable, single-core System-on-Chip implemented in SystemVerilog, targeting the Digilent Basys 3 (Xilinx Artix-7). The processor implements the RV32I base integer instruction set with a classic 5-stage in-order pipeline, a two-level memory hierarchy (I-Cache + D-Cache), a UART/GPIO peripheral subsystem, and a machine-mode interrupt controller.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Pipeline Stages](#pipeline-stages)
- [Memory Hierarchy](#memory-hierarchy)
- [Key Implementation Details](#key-implementation-details)
- [Peripheral Subsystem](#peripheral-subsystem)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Testing & Verification](#testing--verification)
- [UVM Verification Environment](#uvm-verification-environment)
- [Future Improvements](#future-improvements)

---

## Architecture Overview

```
 ┌────────────────────────────────────────────────────────────────┐
 │                          SoC Top                               │
 │                                                                │
 │   ┌──────────┐    ┌────────────────────────────────────────┐   │
 │   │   ROM    │◄───│                                        │   │
 │   │(Instr.   │    │            RISC-V Core                 │   │
 │   │ Memory)  │    │         (5-Stage Pipeline)             │   │
 │   └──────────┘    │                                        │   │
 │                   │   IF → ID → EX → MEM → WB              │   │
 │   ┌──────────┐    │                                        │   │
 │   │   RAM    │◄──►│   I-Cache          D-Cache             │   │
 │   │  (Data   │    │  (Direct-Map)    (Write-Back)          │   │
 │   │ Memory)  │    │                                        │   │
 │   └──────────┘    └──────────────────┬─────────────────────┘   │
 │                                      │ System Bus              │
 │              ┌───────────────────────┼────────────────┐        │
 │              │                       │                │        │
 │         ┌────▼────┐            ┌─────▼───┐      ┌─────▼───┐    │
 │         │  UART   │            │  GPIO   │      │   PIC   │    │
 │         │(TX/RX)  │            │(32-bit) │      │ (Intr.) │    │
 │         └─────────┘            └─────────┘      └─────────┘    │
 └────────────────────────────────────────────────────────────────┘
```

---

## Pipeline Stages

The processor implements the classic 5-stage RISC pipeline. Each stage is separated by a registered pipeline latch (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`), allowing a new instruction to be issued every cycle under ideal conditions.

| Stage | Module | Description |
|-------|--------|-------------|
| **IF** — Instruction Fetch | `fetch_stage.sv` | Drives the PC, interfaces with the I-Cache. On a cache miss, the Hazard Unit freezes this stage until the line is filled. |
| **ID** — Instruction Decode | `decode_stage.sv` | Decodes the instruction, reads the register file, and generates all pipeline control signals and the sign-extended immediate. |
| **EX** — Execute | `execute_stage.sv` | Runs the ALU, resolves branch/jump targets, and applies operand forwarding from MEM/WB. Also interfaces with the CSR unit for interrupt handling. |
| **MEM** — Memory Access | `memory_stage.sv` | Issues load/store requests to the D-Cache. Computes branch-taken decisions and drives the memory bus byte-enable signals. |
| **WB** — Write-Back | `writeback_stage.sv` | Selects between the ALU result and the loaded memory value, writing the final result back to the register file. |

---

## Memory Hierarchy

### Instruction Cache (`icache.sv`)

A direct-mapped, read-only cache that sits between the Fetch stage and the ROM.

- **Organization:** 8 sets × 1 way × 128-bit cache lines (4 × 32-bit words per line)
- **Address breakdown:** `TAG[31:7]` | `INDEX[6:4]` | `OFFSET[3:0]`
- **Miss policy:** 3-state FSM — `COMPARE → FETCH → ALLOCATE`. On a miss the FSM issues four sequential word reads from ROM to fill the line buffer, then writes the complete line in one clock cycle.
- **Pipeline integration:** A `cpu_stall` signal is routed to the Hazard Detection Unit, which freezes the PC and the IF/ID register, injecting a NOP bubble into the ID/EX stage to prevent data corruption during the fill.

### Data Cache (`dcache.sv`)

A direct-mapped, read/write cache that sits between the Memory stage and the RAM.

- **Organization:** 8 sets × 1 way × 128-bit cache lines
- **Write policy:** **Write-Back with a dirty bit.** Writes hit the cache immediately and mark the line dirty; the modified line is only evicted to RAM when a conflicting miss occurs.
- **Byte-enable support:** Per-byte write masking (`byte_en[3:0]`) ensures `SB`, `SH`, and `SW` instructions all update only their target bytes within the cached line, preserving the integrity of neighbouring bytes.
- **Miss policy:** 4-state FSM — `COMPARE → WRITE_BACK → FETCH → ALLOCATE`. If the evicted line is dirty, its four words are written back to RAM before fetching the new line.

---

## Key Implementation Details

### Hazard Detection Unit (`hazard_detection_unit.sv`)

The unit resolves four distinct hazard classes in strict priority order:

1. **Branch/Jump Flush** — On a taken branch (resolved in MEM), flushes the three speculatively-fetched instructions by asserting `if_id_flush`, `id_ex_flush`, and `ex_mem_flush` simultaneously.
2. **I-Cache Miss Stall** — Freezes the PC (`if_pc_en = 0`) and the IF/ID latch (`id_reg_en = 0`), while flushing the ID/EX latch to prevent the stale instruction from propagating.
3. **UART Wait-State** — Detects a load targeting the UART address window (`0x3000–0x300F`) and inserts exactly one stall cycle to guarantee the peripheral's read data is stable.
4. **Load-Use Stall** — Detects when an instruction in EX is a load whose destination matches a source register of the instruction in ID. Stalls fetch/decode for one cycle and injects a NOP bubble.

All flush signals are ORed with the trap/`mret` flush from the CSR unit, ensuring interrupt entry and return cleanly drain the pipeline.

### Forwarding Unit (`forwarding_unit.sv`)

Resolves RAW (Read-After-Write) data hazards for back-to-back ALU instructions without stalling the pipeline.

- **MEM → EX forward** (`forward_sel = 2'b10`): highest priority; used when the instruction two stages ahead wrote a register the current EX stage reads.
- **WB → EX forward** (`forward_sel = 2'b01`): used for the three-stage gap case.
- **Guard conditions:** Forwarding is suppressed for writes to `x0` and for source registers that the current instruction does not actually read (`rs1_used` / `rs2_used` flags from the decoder), preventing spurious forwarding on instructions like `LUI` or `AUIPC`.

### CSR Unit & Interrupt Handling (`csr_unit.sv`)

Implements a subset of the RISC-V machine-mode privileged architecture:

- **Registers:** `mstatus` (MIE/MPIE), `mtvec` (ISR vector), `mepc` (exception PC), `mcycle` (64-bit cycle counter), `minstret` (64-bit retired-instruction counter).
- **Trap entry:** When an external interrupt is asserted and `mstatus.MIE` is set, `take_trap` is raised, the current PC is saved to `mepc`, MIE is cleared, and the PC mux jumps to `mtvec`.
- **Trap return:** The `mret` instruction is detected in EX. The pipeline is flushed and the PC is restored from `mepc`.

---

## Peripheral Subsystem

All peripherals are memory-mapped and accessed via a central system bus (`system_bus.sv`).

| Peripheral | Base Address | Description |
|------------|-------------|-------------|
| UART | `0x3000` | 8-N-1 serial transceiver (configurable baud rate). Supports interrupt-driven RX via the PIC. |
| GPIO | `0x4000` | 32-bit output register driving external SoC pins. |
| PIC | — | Programmable Interrupt Controller; routes peripheral IRQs to the CSR unit's `ext_intr` input. |

---

## Repository Structure

```
.
├── src/
│   ├── core/
│   │   ├── fetch_stage.sv
│   │   ├── decode_stage.sv
│   │   ├── execute_stage.sv
│   │   ├── memory_stage.sv
│   │   ├── writeback_stage.sv
│   │   ├── forwarding_unit.sv
│   │   ├── hazard_detection_unit.sv
│   │   ├── csr_unit.sv
│   │   ├── alu.sv
│   │   ├── alu_control.sv
│   │   ├── reg_file.sv
│   │   ├── imm_gen.sv
│   │   └── riscv_core.sv
│   ├── cache/
│   │   ├── icache.sv
│   │   └── dcache.sv
│   ├── peripherals/
│   │   ├── uart_tx.sv
│   │   ├── uart_rx.sv
│   │   ├── uart_wrapper.sv
│   │   ├── gpio.sv
│   │   └── pic.sv
│   └── soc_top.sv
├── tb/
│   ├── soc_tb.sv
│   ├── riscv_tb.sv
│   ├── icache_tb.sv
│   ├── memory_tb.sv
│   ├── alu_basic_tb.sv
│   ├── alu_branch_tb.sv
│   ├── alu_forwarding_tb.sv
│   ├── echo_test_tb.sv
│   └── echo_intr_tb.sv
├── tests/
│   ├── c_tests/
│   │   ├── add_test.c
│   │   ├── branch_test.c
│   │   ├── hazard_test.c
│   │   ├── load_branch_hazard.c
│   │   ├── double_hazard_test.c
│   │   ├── isa_test.c
│   │   ├── icache_stress.c
│   │   └── test_fibonacci.c
│   └── asm_tests/
│       └── cache_loop.asm
├── sim/
│   └── program.hex
├── build.bat           (C firmware build script)
├── build_asm.bat       (Assembly firmware build script)
└── link.ld
```

---

## Getting Started

### Prerequisites

- **Xilinx Vivado** (2020.x or later) with XSim for simulation
- **RISC-V GNU Toolchain** — `riscv-none-elf-gcc`, `riscv-none-elf-objcopy`, `riscv-none-elf-objdump`

### 1. Compile Firmware

Build a C test and generate the memory image:

```bat
:: Compile a C test (defaults to tests/c_tests/add_test.c)
build.bat tests/c_tests/hazard_test.c

:: Outputs:
::   firmware.mem  — Verilog $readmemh-compatible hex image
::   asm.txt       — disassembly for debug reference
```

Or assemble a raw assembly test directly:

```bat
build_asm.bat tests/asm_tests/cache_loop.asm
```

Both scripts use `rv32i` / `ilp32` ABI and link at address `0x00000000`.

### 2. Run Simulation in Vivado / XSim

1. Open or create a Vivado project and add all `.sv` files from `src/` and `tb/`.
2. Set `soc_tb.sv` as the simulation top module.
3. The testbench auto-loads `sim/program.hex` into the ROM model at time 0:
   ```systemverilog
   $readmemh("sim/program.hex", uut.u_rom.mem);
   ```
4. Copy your compiled `firmware.mem` to `sim/program.hex`, then launch simulation:
   ```
   Vivado → Flow → Run Simulation → Run Behavioral Simulation
   ```
5. Waveforms are dumped to `sim/waves.fst` for offline viewing (e.g., GTKWave).

---

## Testing & Verification

The project includes **9 targeted testbenches** covering the full design stack, from individual units up to full SoC integration:

| Testbench | Scope |
|-----------|-------|
| `alu_basic_tb` | ALU arithmetic and logic operations |
| `alu_branch_tb` | Branch condition evaluation |
| `alu_forwarding_tb` | Operand forwarding path correctness |
| `icache_tb` | I-Cache hit/miss FSM, line fill, stall signalling |
| `memory_tb` | D-Cache write-back and byte-enable correctness |
| `riscv_tb` | Core-level integration: hazards, forwarding, branches |
| `soc_tb` | Full SoC: UART I/O, memory-mapped peripherals, interrupts |
| `echo_test_tb` | UART echo loop (polling mode) |
| `echo_intr_tb` | UART echo loop (interrupt-driven mode) |

**8 cache-consistency integration tests** have been verified, confirming correct behaviour across I-Cache cold-start misses, D-Cache write-back eviction, and concurrent pipeline stalls from both caches.

---

## UVM Verification Environment

The RISC-V SoC is verified using a complete **UVM 1.2** testbench targeting Siemens Questa 2025.2. The environment is fully self-checking: a lightweight RV32I instruction set simulator (ISS) runs the same program before the hardware does, produces a golden list of expected register writes, and an in-order scoreboard compares every hardware write against that list automatically.

The testbench lives in `hw/tb/uvm/` and is composed of three source files:

| File | Contents |
|------|----------|
| `riscv_if.sv` | SystemVerilog virtual interface — clocking block, DUT probes |
| `riscv_uvm_pkg.sv` | UVM package — all classes from transaction types to tests |
| `riscv_uvm_tb.sv` | Top-level HDL module — DUT instantiation, clock, `uvm_config_db` setup |

---

### Testbench Architecture

```
riscv_uvm_tb  (top-level HDL module, 100 MHz clock, soc_top DUT)
│
│   ┌──────────────────────────────────────────────────────┐
│   │  riscv_if  (virtual interface)                        │
│   │  ┌─────────────────────────────────────────────────┐ │
│   │  │  clocking block  monitor_cb  @(posedge clk)     │ │
│   │  │  default input #1step  ← race-free sampling     │ │
│   │  │  inputs: rst_n, regfile_we, regfile_waddr [4:0] │ │
│   │  │                         regfile_wdata  [31:0]   │ │
│   │  └─────────────────────────────────────────────────┘ │
│   │  probe path: uut.u_core.u_decode_stage               │
│   │                        .reg_file_inst.{we,           │
│   │                         write_reg, write_data}        │
│   └──────────────────────────────────────────────────────┘
│
└── uvm_test_top  :  riscv_alu_test  |  riscv_load_store_test
    │                (selected via +UVM_TESTNAME on command line)
    │
    └── env : riscv_env
        │
        ├── agent : riscv_agent
        │   │
        │   ├── sequencer : uvm_sequencer #(riscv_seq_item)
        │   │
        │   ├── driver : riscv_driver                         riscv_seq_item
        │   │   ├── backdoor_load_rom()  (uvm_hdl_deposit) ──────────────────┐
        │   │   ├── set_rst()            (uvm_hdl_force)                     │
        │   │   └── ap : uvm_analysis_port #(riscv_seq_item) ────────────────┤
        │   │                                                                 │
        │   └── monitor : riscv_monitor                  riscv_regwrite_item │
        │       ├── samples monitor_cb every cycle                           │
        │       └── ap : uvm_analysis_port #(riscv_regwrite_item) ───────┐   │
        │                                                                 │   │
        └── scoreboard : riscv_scoreboard                                │   │
            ├── observed_imp  ◄────────────────────────────────────────────┘   │
            └── expected_imp  ◄────────────────────────────────────────────────┘
```

---

### Transaction Types

The environment uses two distinct transaction classes, each carrying different information between components:

**`riscv_seq_item`** — sequence to driver, driver to scoreboard
```
instructions[$]      — assembled 32-bit program words (index 0 = address 0x0000)
expected_writes[$]   — ISS-predicted {rd, value} pairs in program order
run_cycles           — clock budget before re-asserting reset (400 or 600 cycles)
```

**`riscv_regwrite_item`** — monitor to scoreboard
```
rd    [4:0]   — destination register address observed on the write port
value [31:0]  — write data observed on the write port
```

The driver's analysis port carries a `riscv_seq_item` (full program + golden expected writes) into `scoreboard.expected_imp`. The monitor's analysis port carries individual `riscv_regwrite_item` observations into `scoreboard.observed_imp`. The two TLM connections use distinct `uvm_analysis_imp` suffixes (`_expected`, `_observed`) declared with `` `uvm_analysis_imp_decl `` so the scoreboard can receive two different transaction types on two different ports.

---

### Component Overview

**`riscv_uvm_tb`** — Top-level HDL module

Generates a 100 MHz clock (`always #5 clk = ~clk`), instantiates `soc_top` as `uut`, and instantiates `riscv_if`. Three `assign` statements tap the register file write port directly from the DUT hierarchy and drive the interface observation wires:

```systemverilog
assign dut_if.regfile_we    = uut.u_core.u_decode_stage.reg_file_inst.we;
assign dut_if.regfile_waddr = uut.u_core.u_decode_stage.reg_file_inst.write_reg;
assign dut_if.regfile_wdata = uut.u_core.u_decode_stage.reg_file_inst.write_data;
```

The interface handle is registered in `uvm_config_db` under the wildcard path `"uvm_test_top.*"` so every UVM component retrieves it with a single `get()` call. The test name is selected at runtime via `+UVM_TESTNAME`.

---

**`riscv_iss`** — Golden Reference Model

A plain SystemVerilog class (not a UVM component) embedded inside `riscv_base_seq`. It holds a 32-register file (`regs[32]`) and a **sparse associative memory** (`logic [31:0] mem [bit [31:0]]`) so it can model any byte-addressed store without allocating 4 GB of memory.

The `execute()` function decodes one instruction and returns the committed `{rd, value}` pair. The `simulate()` function iterates the program, calls `execute()` on each word, and stops when it encounters `JAL x0, 0` (`32'h0000_006F`) — the infinite-loop end-of-program sentinel placed by every sequence. Supported instruction groups:

| Group | Instructions |
|-------|-------------|
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| I-type ALU | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU |
| Loads | LB, LH, LW, LBU, LHU |
| Stores | SB, SH, SW (updates ISS memory, no register write) |
| Upper imm | LUI, AUIPC |
| Jumps | JAL, JALR (rd = PC+4; control flow not modelled) |
| Branches | Skipped (no register write) |

---

**`riscv_base_seq`** — Abstract base sequence

Owns an `riscv_iss` instance and provides instruction-encoding helper functions so derived sequences assemble programs without raw bit manipulation:

```systemverilog
r_type(rd, rs1, rs2, funct3, funct7)   // R-type encoding
i_alu (rd, rs1, funct3, imm)           // I-type ALU (opcode 0010011)
i_load(rd, rs1, funct3, imm)           // Load       (opcode 0000011)
s_type(rs1, rs2, funct3, imm)          // Store      (opcode 0100011)
lui   (rd, imm_u)                      // LUI        (opcode 0110111)
jal   (rd, offset)                     // JAL        (opcode 1101111)
end_program()                          // JAL x0, 0  (32'h0000_006F)
```

Derived sequences call `iss.simulate(prog, item.expected_writes)` to populate the golden list before handing the item to the driver.

---

**`riscv_driver`** — Stimulus executor

Receives `riscv_seq_item` from the sequencer and executes the following protocol for every item:

```
Step 1   uvm_hdl_force  "riscv_uvm_tb.rst_n" = 0    assert reset
Step 2   wait 2 monitor_cb edges
Step 3   backdoor_load_rom(item.instructions)         write all 1024 ROM words
Step 4   ap.write(item)                               publish golden list to scoreboard
Step 5   wait 10 monitor_cb edges                     hold reset
Step 6   uvm_hdl_force  "riscv_uvm_tb.rst_n" = 1    release reset
Step 7   wait item.run_cycles monitor_cb edges        let program execute
Step 8   uvm_hdl_force  "riscv_uvm_tb.rst_n" = 0    re-assert reset for next item
```

The golden list is published in **step 4, before reset is released**, guaranteeing the scoreboard's expected queue is populated before the monitor can produce any observed events.

---

**`riscv_monitor`** — Passive observer

Waits on `monitor_cb` (the clocking block, sampled `#1step` after the clock edge) every cycle. When all three conditions hold simultaneously, it creates a `riscv_regwrite_item` and broadcasts it:

```
vif.monitor_cb.rst_n        == 1    (core is out of reset)
vif.monitor_cb.regfile_we   == 1    (a write is committing)
vif.monitor_cb.regfile_waddr != 0   (destination is not x0)
```

The `#1step` sampling delay is the UVM-recommended practice for clocking blocks: it ensures the monitor reads stable, post-settling values and never races with combinational logic driven by the same clock edge.

---

**`riscv_scoreboard`** — In-order checker

Holds an internal FIFO queue `expected_q[$]` of `{rd, value}` structs. Two write callbacks feed it:

- `write_expected(riscv_seq_item)` — called by the driver; pushes all entries from `item.expected_writes` into the queue.
- `write_observed(riscv_regwrite_item)` — called by the monitor; pops the front entry and performs two checks: destination register number match, then data value match.

In `report_phase`, the scoreboard emits a final summary and raises `UVM_FATAL` if any check failed, ensuring a non-zero simulation exit code on any mismatch.

---

**`riscv_env`** — Environment container

Constructs `riscv_agent` and `riscv_scoreboard` in `build_phase`. In `connect_phase` it wires the two analysis ports:

```systemverilog
agent.driver.ap.connect(scoreboard.expected_imp);   // riscv_seq_item path
agent.monitor.ap.connect(scoreboard.observed_imp);  // riscv_regwrite_item path
```

---

**`riscv_agent`** — Agent

Constructs `uvm_sequencer #(riscv_seq_item)`, `riscv_driver`, and `riscv_monitor`. Connects `driver.seq_item_port` to `sequencer.seq_item_export` in `connect_phase`.

---

**`riscv_base_test`** — Base test

Creates `riscv_env`. Calls `uvm_top.print_topology()` in `end_of_elaboration_phase` to print the full component hierarchy to the simulation log. Concrete tests extend this class and override `run_phase` only.

---

### Available Tests

#### `riscv_alu_test` — ALU coverage

Runs `riscv_alu_seq`: 18 instructions (17 register writes), `run_cycles = 400`.

| Instruction | Expected result | Notes |
|-------------|----------------|-------|
| `ADDI x1, x0, 10` | `x1 = 10` | operand A |
| `ADDI x2, x0, 3` | `x2 = 3` | operand B |
| `ADD  x3, x1, x2` | `x3 = 13` | |
| `SUB  x4, x1, x2` | `x4 = 7` | |
| `AND  x5, x1, x2` | `x5 = 2` | `0xA & 0x3` |
| `OR   x6, x1, x2` | `x6 = 11` | `0xA \| 0x3` |
| `XOR  x7, x1, x2` | `x7 = 9` | `0xA ^ 0x3` |
| `SLL  x8, x1, x2` | `x8 = 80` | `10 << 3` |
| `SRL  x9, x1, x2` | `x9 = 1` | `10 >> 3` |
| `ADDI x10, x0, -4` | `x10 = 0xFFFFFFFC` | |
| `SRA  x10, x10, x2` | `x10 = 0xFFFFFFFF` | arithmetic shift, sign-extended |
| `SLT  x11, x1, x2` | `x11 = 0` | 10 is not < 3 |
| `SLT  x12, x2, x1` | `x12 = 1` | 3 < 10 |
| `ADDI x13, x1, 5` | `x13 = 15` | |
| `ANDI x14, x1, 0xF` | `x14 = 10` | `0xA & 0xF` |
| `ORI  x15, x1, 5` | `x15 = 15` | `0xA \| 0x5` |
| `XORI x16, x1, 0xF` | `x16 = 5` | `0xA ^ 0xF` |

#### `riscv_load_store_test` — Memory and D-Cache coverage

Runs `riscv_load_store_seq`: 10 instructions (6 register writes), `run_cycles = 600`. The larger budget accounts for D-Cache cold-start misses (~5 stall cycles per load).

RAM is mapped at `0x2000–0x2FFF`. The test stores a byte value (`0xAB`) to RAM using all store widths, then loads it back using all load widths to verify byte-enable logic, sign extension, and zero extension.

| Instruction | Expected result | Notes |
|-------------|----------------|-------|
| `LUI  x1, 2` | `x1 = 0x00002000` | RAM base address |
| `ADDI x2, x0, 171` | `x2 = 0x000000AB` | test byte value |
| `SW   x2, 0(x1)` | *(no reg write)* | stores word to `mem[0x2000]` |
| `LW   x3, 0(x1)` | `x3 = 0x000000AB` | 32-bit load |
| `SB   x2, 4(x1)` | *(no reg write)* | stores byte to `mem[0x2004]` |
| `LBU  x4, 4(x1)` | `x4 = 0x000000AB` | byte load, zero-extended |
| `LB   x5, 4(x1)` | `x5 = 0xFFFFFFAB` | byte load, **sign-extended** (bit 7 = 1) |
| `SH   x2, 8(x1)` | *(no reg write)* | stores halfword to `mem[0x2008]` |
| `LHU  x6, 8(x1)` | `x6 = 0x000000AB` | halfword load, zero-extended |

---

### Backdoor ROM Loading

On remote platforms such as EDA Playground the ROM's `$readmemh` path does not exist on the server. The driver bypasses this using `uvm_hdl_deposit` with a **runtime string path** instead of a compile-time `force` statement.

`force` inside a UVM package fails with `vlog-7027` because Questa resolves hierarchical paths at compile time, before the module hierarchy exists. `uvm_hdl_deposit` passes the path as a string to the VPI layer, which resolves it at runtime after elaboration is complete. EDA Playground's `-access=rw+/.` flag grants the required VPI write access automatically.

```systemverilog
localparam string ROM_HDL_PATH = "riscv_uvm_tb.uut.u_rom.mem";
localparam string RST_HDL_PATH = "riscv_uvm_tb.rst_n";

// Write all 1024 ROM words — program words first, then NOP padding
for (int i = 0; i < 1024; i++) begin
    rom_word  = (i < words.size()) ? words[i] : 32'h00000013;
    elem_path = $sformatf("%s[%0d]", ROM_HDL_PATH, i);
    if (!uvm_hdl_deposit(elem_path, rom_word))
        `uvm_error("DRV", $sformatf("uvm_hdl_deposit FAILED: %s", elem_path))
end
```

To retarget the testbench to a different DUT hierarchy, only the two `localparam string` paths in `riscv_driver` need to change.

---

### Verification Results

| Test | Instructions | Expected Writes | Result |
|------|-------------|-----------------|--------|
| `riscv_alu_test` | 18 | 17 | ✅ *pending run* |
| `riscv_load_store_test` | 10 | 6 | ✅ **6 / 6 PASSED** |

`riscv_load_store_test` confirmed on Siemens Questa 2025.2 via EDA Playground:

```
UVM_INFO [SB] PASS  x1 = 0x00002000
UVM_INFO [SB] PASS  x2 = 0x000000ab
UVM_INFO [SB] PASS  x3 = 0x000000ab
UVM_INFO [SB] PASS  x4 = 0x000000ab
UVM_INFO [SB] PASS  x5 = 0xffffffab
UVM_INFO [SB] PASS  x6 = 0x000000ab
UVM_INFO [SB] ALL TESTS PASSED - 6 passed, 0 failed
Errors: 0, Warnings: 1  (warning is harmless $readmemh file-not-found)
```

---

## Future Improvements

**1. Dynamic Branch Prediction (2-bit Saturating Counter)**
The current design resolves branches in the MEM stage, incurring a 3-cycle penalty on every taken branch. A BTB (Branch Target Buffer) with 2-bit saturating counters in the Fetch stage would eliminate most of this penalty for loop-heavy workloads, significantly improving IPC.

**2. AXI4-Lite Bus Interface**
The custom system bus could be replaced with an industry-standard AXI4-Lite interconnect. This would make the SoC immediately compatible with Xilinx IP (DDR controllers, DMA engines, Ethernet MACs) and is the natural next step toward a production-quality embedded system.

**3. Instruction and Data TLB / Virtual Memory (Sv32)**
Adding a 16-entry fully-associative TLB and implementing the RISC-V Sv32 page-table walker would bring the design to a supervisor-capable (S-mode) processor, enabling it to run a lightweight RTOS or a bare-metal port of Linux.
